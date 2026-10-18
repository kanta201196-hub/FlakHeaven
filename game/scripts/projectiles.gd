class_name Projectiles
extends Node2D
## Пул снарядов без отдельных узлов: всё хранится в массивах и рисуется одним проходом —
## так выдерживаются сотни снарядов на Steam Deck.
## Снаряды игрока — приглушённые, вражеские — яркие (правило читаемости).

var bullets: Array[Dictionary] = []   # пули игрока, гондол, турелей, ведомых
var pmissiles: Array[Dictionary] = [] # ракеты В-В игрока
var rockets: Array[Dictionary] = []   # НАР игрока
var bombs: Array[Dictionary] = []     # бомбы игрока (взрыв по таймеру)
var missiles: Array[Dictionary] = []  # вражеские ракеты
var ebullets: Array[Dictionary] = []  # вражеские пули
var fires: Array[Dictionary] = []     # 3.1: огонь на земле («Новогодняя ночь»)


func _ready() -> void:
	z_index = 3


# ---------- Создание ----------

func spawn_player_bullet(pos: Vector2, vel: Vector2, dmg: float, life: float, manual := false, src := "курсовое (авто)", pierce := 0, he := 0.0) -> void:
	var b := {"p": pos, "v": vel, "life": life, "dmg": dmg, "m": manual, "src": src}
	if he > 0.0:
		b["he"] = he
	if pierce > 0:
		b["pierce"] = pierce
		b["hit"] = []
	bullets.append(b)


## opts: splash (радиус осколков, 55), bounce (сколько раз искать новую цель после сбития), fire (огонь на земле)
func spawn_player_missile(pos: Vector2, vel: Vector2, target: Enemy, dmg := 45.0, src := "ракеты В-В", opts := {}) -> void:
	var m := {"p": pos, "v": vel, "life": 2.8, "t": weakref(target), "dmg": dmg, "trail": PackedVector2Array(), "src": src}
	m.merge(opts, true)
	pmissiles.append(m)


func spawn_fire(pos: Vector2, r: float, dps: float, time: float, src: String, ground_only := false, col := Color(1.0, 0.45, 0.1)) -> void:
	fires.append({"p": pos, "r": r, "dps": dps, "t": time, "tick": 0.0, "src": src, "ground": ground_only, "c": col})
	if fires.size() > 60:
		fires.pop_front()


## opts: src (источник), life (время полёта = точка подрыва), sticky («Термобарика»)
func spawn_rocket(pos: Vector2, vel: Vector2, dmg: float, splash: float, delay := 0.0, opts := {}) -> void:
	var r := {"p": pos, "v": vel, "life": 0.9, "dmg": dmg, "r": splash, "delay": delay, "trail": PackedVector2Array(), "src": "НАР"}
	r.merge(opts, true)
	rockets.append(r)


var _thermo: Array = []   # последние объёмные взрывы «Термобарики»: [{p, t}] — для слияния


## След (шлейф): точка добавляется, когда снаряд сместился на step пикс.
static func _trail_push(m: Dictionary, p: Vector2, maxn: int, step := 9.0) -> void:
	var tr: PackedVector2Array = m["trail"]
	if tr.is_empty() or tr[tr.size() - 1].distance_to(p) >= step:
		tr.append(p)
		if tr.size() > maxn:
			tr.remove_at(0)
		m["trail"] = tr


## Бомба (2.8): летит к точке to за время fuse и рвётся там (воздушный подрыв — бьёт и самолёты).
## 3.5: ground_only — бомба рвётся на земле и бьёт только наземные цели (бомбы «Кита»).
func spawn_bomb(pos: Vector2, fuse: float, dmg: float, radius: float, src := "бомбы", to = null, ground_only := false) -> void:
	var dest: Vector2 = pos if to == null else to
	bombs.append({"p": pos, "from": pos, "to": dest, "t": fuse, "fuse": fuse, "dmg": dmg, "r": radius, "src": src, "ground": ground_only})


func spawn_missile(pos: Vector2, dir: Vector2) -> void:
	missiles.append({"p": pos, "v": dir * Tuning.g("missile_speed") * 0.6, "life": 4.5, "lost": false, "trail": PackedVector2Array()})


func spawn_enemy_bullet(pos: Vector2, vel: Vector2, who := "", big := false, dmg_k := 1.0, quiet := false) -> void:
	ebullets.append({"p": pos, "v": vel, "life": 3.3, "who": who, "big": big, "k": dmg_k})
	if not big and not quiet:
		Main.I.sfx.play("enemy_fire", -19.0)


# ---------- Служебные: противоракеты, срыв захвата, урон по площади ----------

func intercept_missile(from: Vector2, r: float) -> bool:
	return intercept_missile_at(from, r) != null


## Сбить ближайшую вражескую ракету в радиусе; вернёт точку перехвата или null
func intercept_missile_at(from: Vector2, r: float, decoy := false) -> Variant:
	var best := -1
	var best_d := r
	for i in missiles.size():
		if missiles[i].has("decoy"):
			continue
		var d: float = from.distance_to(missiles[i]["p"])
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return null
	var at: Vector2 = missiles[best]["p"]
	if decoy and is_instance_valid(Main.I.player) and Main.I.player.syn.has("mirror"):
		# «Зеркало»: уведённая ракета разворачивается и летит во врага как своя
		var mm := missiles[best]
		var tgt := Weapons.pick_target(at, 900.0, "nearest")
		Main.I.fx.flare_burst(from, (at - from).angle() + PI, 2)
		spawn_player_missile(at, -(mm["v"] as Vector2) * 0.6, tgt, 80.0, "связка: зеркало", {"splash": 90.0, "tint": Color(0.4, 1.0, 0.9)})
		missiles.remove_at(best)
		return at
	if decoy:
		# 3.1: ракета уходит на тепловую ловушку и рвётся рядом с ней
		var m := missiles[best]
		var fl: Array = Main.I.fx.flare_burst(from, (at - from).angle() + PI, 2, Vector2.ZERO)
		m["decoy"] = fl[0]
		m["lost"] = true
		m["life"] = randf_range(0.35, 0.55)
	else:
		Main.I.fx.zap(from, missiles[best]["p"])
		Main.I.fx.hit_spark(missiles[best]["p"], Color(1, 0.5, 0.2))
		missiles.remove_at(best)
	return at


func intercept_bullets(from: Vector2, r: float) -> int:
	var n := 0
	for i in range(ebullets.size() - 1, -1, -1):
		if from.distance_to(ebullets[i]["p"]) < r:
			Main.I.fx.hit_spark(ebullets[i]["p"], Color(1, 0.6, 0.8))
			ebullets.remove_at(i)
			n += 1
	return n


func break_locks(from: Vector2, r: float) -> int:
	var n := 0
	for m in missiles:
		if not m["lost"] and from.distance_to(m["p"]) < r:
			m["lost"] = true
			m["life"] = minf(float(m["life"]), 1.5)
			n += 1
	return n


## Взрыв по площади (2.8): урон падает от центра к краю — 100% в центре, 35% на границе зоны.
## 3.1: радиус × «Осколочная рубашка» (и «Штурмовой заход» II); нашивки «Взрыв» I (край 50%) и II (цепной подрыв).
func aoe(pos: Vector2, r: float, dmg: float, src: String, visual := true, exclude: Enemy = null, chain := 0, ground_only := false) -> void:
	var edge := 0.35
	var pl := Main.I.player
	var blast2 := false
	if is_instance_valid(pl):
		r *= float(pl.mods.get("blast_r", 1.0))
		if pl.assault_t > 0.0 and pl.lvl_of("assault") >= 2:
			r *= 1.25
		if pl.patch("blast") >= 1:
			edge = 0.5
		dmg *= float(pl.mods.get("blast_dmg", 1.0))
		blast2 = pl.syn.has("chain") and chain < 5 # 3.2: «Цепная реакция»
	var died: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or e == exclude or (ground_only and not e.is_ground):
			continue
		var d := pos.distance_to(e.global_position) - e.radius
		if d < r:
			var k := lerpf(1.0, edge, clampf(d / r, 0.0, 1.0))
			e.take_hit(dmg * k, src)
			if blast2 and e.hp <= 0.0 and not e.is_boss:
				died.append([e.global_position, e.max_hp])
	if visual:
		Main.I.fx.blast(pos, r)
	for dd in died.slice(0, 6):
		_chain_q.append({"p": dd[0], "dmg": 30.0 + 0.1 * float(dd[1]), "n": chain + 1, "t": 0.08})


var _chain_q: Array = []   # «Цепная реакция»: взрывы домино с небольшой задержкой


func _update_chain(delta: float) -> void:
	for i in range(_chain_q.size() - 1, -1, -1):
		_chain_q[i]["t"] = float(_chain_q[i]["t"]) - delta
		if float(_chain_q[i]["t"]) <= 0.0:
			var c: Dictionary = _chain_q[i]
			_chain_q.remove_at(i)
			aoe(c["p"], 90.0 * (1.0 + 0.15 * int(c["n"])), float(c["dmg"]), "связка: цепная реакция", true, null, int(c["n"]))
	if _chain_q.size() > 40:
		_chain_q = _chain_q.slice(_chain_q.size() - 40)


# ---------- Обновление ----------

func _process(delta: float) -> void:
	_update_bullets(delta)
	_update_player_missiles(delta)
	_update_rockets(delta)
	_update_bombs(delta)
	_update_missiles(delta)
	_update_enemy_bullets(delta)
	_update_fires(delta)
	_update_chain(delta)
	_update_thermo(delta)
	queue_redraw()


func _update_fires(delta: float) -> void:
	for i in range(fires.size() - 1, -1, -1):
		var f := fires[i]
		f["t"] = float(f["t"]) - delta
		f["tick"] = float(f["tick"]) - delta
		if float(f["tick"]) <= 0.0:
			f["tick"] = 0.25
			for n in get_tree().get_nodes_in_group("enemies"):
				var e := n as Enemy
				if e != null and e.hp > 0.0 and (e.is_ground or not f.get("ground", false)) and (f["p"] as Vector2).distance_to(e.global_position) < float(f["r"]) + e.radius:
					e.take_hit(float(f["dps"]) * 0.25, f["src"])
		if float(f["t"]) <= 0.0:
			fires.remove_at(i)


func _update_bullets(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		var dt := delta + float(b.get("lag", 0.0))
		b.erase("lag")
		b["life"] = float(b["life"]) - dt
		var p0: Vector2 = b["p"]
		var p: Vector2 = p0 + b["v"] * dt
		b["p"] = p
		var hit := false
		for n in enemies:
			var e := n as Enemy
			if e == null or e.hp <= 0.0:
				continue
			# 3.4: попадание по всему отрезку за кадр, а не только по конечной точке (на 30–40 FPS пули пролетали мелких врагов)
			if seg_hit(p0, p, e.global_position, e.radius):
				if b.has("hit") and (b["hit"] as Array).has(e):
					continue
				if p.distance_squared_to(e.global_position) >= e.radius * e.radius:
					Main.I.tele.add("swept_hits")
				if b.has("lead"):
					Main.I.tele.add("hits_lead")
				var manual: bool = b["m"]
				var src: String = b["src"]
				e.take_hit(float(b["dmg"]) * _bullet_k(src, e), src)
				if b.has("he"): # «Пушкарь»: фугасный снаряд
					aoe(p, float(b["he"]), float(b["dmg"]) * 0.6, "связка: пушкарь", true, e)
					b.erase("he")
				if int(b.get("pierce", 0)) > 0:
					b["pierce"] = int(b["pierce"]) - 1
					(b["hit"] as Array).append(e)
					if src.begins_with("курсовое"):
						Main.I.hits += 1
					continue
				if src.begins_with("курсовое"):
					Main.I.hits += 1
				if manual and is_instance_valid(Main.I.player):
					Main.I.player.on_bullet_hit()
				hit = true
				break
		if hit or float(b["life"]) <= 0.0:
			if not hit and b["m"] and is_instance_valid(Main.I.player):
				Main.I.player.on_bullet_miss()
			bullets.remove_at(i)


## Отрезок a→b проходит через круг (c, r)
static func seg_hit(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(c) < r * r


## 3.5: «Боевая часть» с 3-го взятия — разделяющаяся БЧ: ракета В-В при попадании даёт 3 суббоеприпаса
func _cluster(p: Vector2, m: Dictionary) -> void:
	var pl := Main.I.player
	if not is_instance_valid(pl) or int(pl.taken.get("msl_head", 0)) < 3 or m.get("src", "") != "ракеты В-В" or m.get("sub", false):
		return
	var n := 3
	for i in n:
		var to := p + Vector2.from_angle(TAU * i / n + randf() * 0.5) * randf_range(60.0, 110.0)
		spawn_bomb(p, 0.25 + 0.05 * i, float(m["dmg"]) * 0.3, 50.0 * float(pl.mods.get("msl_r", 1.0)), "разделяющаяся БЧ", to)


## 3.5: ГСН («Глазастик»): I — 600 пикс., 1 перенацеливание; II — 900 пикс., 2; без ГСН — нет
func _seeker() -> Array:
	var pl := Main.I.player
	var n := int(pl.taken.get("seeker", 0)) if is_instance_valid(pl) else 0
	if n <= 0:
		return [0.0, 0]
	return [600.0, 1] if n == 1 else [900.0, 2]


## «Шмель»: тяжёлая ракета делится на 4 самонаводящиеся БЧ
func _split(p: Vector2, m: Dictionary, hit: Enemy) -> void:
	var n := int(m.get("split", 0))
	var skip: Array = [hit]
	var spare := 0
	for i in n:
		var nt := Weapons.pick_target(p, 700.0, "nearest", skip, true)
		if nt == null:
			spare += 1 # целей рядом нет — эта БЧ рвётся на месте
			continue
		skip.append(nt)
		spawn_player_missile(p, Vector2.from_angle(TAU * i / n + randf() * 0.4) * 260.0, nt, float(m["split_dmg"]), "ракеты В-В", {"sub": true, "life": 1.1})
	if spare > 0:
		aoe(p, 90.0, float(m["split_dmg"]) * 0.5 * spare, "ракеты В-В", false)


## Множители пуль: нашивка «Кинетика I», «Штурмовой заход» по наземным
func _bullet_k(src: String, e: Enemy) -> float:
	var pl := Main.I.player
	if not is_instance_valid(pl):
		return 1.0
	var k := 1.0
	if pl.patch("kinetic") >= 1 and e.hp > e.max_hp * 0.5:
		if src == "гондола" or src == "турели":
			k *= 1.1
		elif src.begins_with("курсовое"):
			k *= 1.05 # курсовое — вполовину
	if pl.assault_t > 0.0 and e.is_ground and src.begins_with("курсовое"):
		k *= 1.5
	return k


func _update_player_missiles(delta: float) -> void:
	var sk := _seeker()
	var pl := Main.I.player
	var boost := float(pl.mods.get("msl_boost", 1.0)) if is_instance_valid(pl) else 1.0
	for i in range(pmissiles.size() - 1, -1, -1):
		var m := pmissiles[i]
		m["life"] = float(m["life"]) - delta
		m["age"] = float(m.get("age", 0.0)) + delta
		var v: Vector2 = m["v"]
		var p: Vector2 = m["p"]
		var t: Enemy = (m["t"] as WeakRef).get_ref() as Enemy
		if (t == null or t.hp <= 0.0) and not m.get("lost", false):
			var skm: Array = [0.0, 0] if m.get("sub", false) else sk # БЧ «Шмеля» не перенацеливаются — иначе рой
			# 3.5: перенацеливание — только с модулем ГСН; без него ракета летит прямо и через 0,5 с самоликвидируется
			t = null
			if int(m.get("rt", 0)) < int(skm[1]):
				t = Weapons.pick_target(p, float(skm[0]), "nearest", [], true)
				if t != null:
					m["rt"] = int(m.get("rt", 0)) + 1
					Main.I.tele.add("msl_retarget")
			m["t"] = weakref(t)
			if t == null:
				m["lost"] = true
				m["life"] = minf(float(m["life"]), 0.5)
				Main.I.tele.add("msl_lost")
		var spd := minf(v.length() + 1500.0 * delta, 720.0 * _missile_spd() * float(m.get("spd_k", 1.0)))
		if t != null:
			var ang := rotate_toward(v.angle(), (t.global_position - p).angle(), deg_to_rad(320.0) * delta)
			v = Vector2.from_angle(ang) * spd
		else:
			v = v.normalized() * spd
		p += v * delta
		m["v"] = v
		m["p"] = p
		_trail_push(m, p, 26)
		var done := float(m["life"]) <= 0.0
		if done and m.get("lost", false):
			Main.I.fx.explosion(p, 6.0) # самоликвидация
		if t != null and p.distance_to(t.global_position) < t.radius + 6.0:
			var dmg := float(m["dmg"]) * (boost if float(m["age"]) < 1.0 else 1.0) # «Форсированный старт»
			t.take_hit(dmg * (float(m.get("ground_k", 1.0)) if t.is_ground else 1.0), m.get("src", "ракеты В-В"))
			# 2.8: осколки — задевают соседей (55 пикс., урон падает к краю)
			var msl_r := float(pl.mods.get("msl_r", 1.0)) if is_instance_valid(pl) else 1.0
			aoe(p, float(m.get("splash", 55.0)) * msl_r, dmg * 0.5, m.get("src", "ракеты В-В"), false, t)
			Main.I.fx.explosion(p, 30.0 if m.get("big", false) else 20.0)
			_cluster(p, m)
			if int(m.get("split", 0)) > 0:
				_split(p, m, t)
			# «Карусель»: сбитие → новая ракета с пилона в ближайшую цель, урон ×1,2 (до 4 перепусков)
			if m.has("carousel") and t.hp <= 0.0 and int(m["carousel"]) < 4 and is_instance_valid(Main.I.player):
				var pl2 := Main.I.player
				var nt2 := Weapons.pick_target(pl2.global_position, 900.0, "nearest", [t], true)
				if nt2 != null:
					var o2 := {"carousel": int(m["carousel"]) + 1, "tint": Color(1.0, 0.95 - 0.12 * int(m["carousel"]), 0.4)}
					spawn_player_missile(pl2.global_position, pl2.velocity + Vector2.from_angle(pl2.heading + randf_range(-0.6, 0.6)) * 200.0,
						nt2, float(m["dmg"]) * 1.2, "связка: карусель", o2)
			if m.get("fire", false):
				spawn_fire(p, 55.0, 12.0, 3.0, m.get("src", "ракеты В-В"))
			done = true
			# 3.1: «ищет новую цель» — ракета летит дальше (bounce раз); 3.5: ГСН III — +1 раз после сбития
			var bounce := int(m.get("bounce", 0))
			if t.hp <= 0.0 and not m.get("sub", false) and int(m.get("gsn3", -1)) != 0 and int(pl.taken.get("seeker", 0) if is_instance_valid(pl) else 0) >= 3 and m.get("src", "") == "ракеты В-В":
				if not m.has("gsn3"):
					m["gsn3"] = 1
				bounce += int(m["gsn3"])
			if bounce > 0:
				var nt := Weapons.pick_target(p, 600.0, "nearest", [t], true)
				if nt != null:
					if int(m.get("bounce", 0)) > 0:
						m["bounce"] = int(m["bounce"]) - 1
					else:
						m["gsn3"] = 0
					m["t"] = weakref(nt)
					m["life"] = 2.0
					done = false
		if done:
			pmissiles.remove_at(i)


func _update_rockets(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for i in range(rockets.size() - 1, -1, -1):
		var r := rockets[i]
		if float(r["delay"]) > 0.0:
			r["delay"] = float(r["delay"]) - delta
			# до пуска ракета «висит» на подвесе — летит вместе с самолётом
			if is_instance_valid(Main.I.player):
				r["p"] = r["p"] + Main.I.player.velocity * delta
			continue
		r["life"] = float(r["life"]) - delta
		var p: Vector2 = r["p"] + r["v"] * delta
		r["p"] = p
		_trail_push(r, p, 8, 12.0)
		var boom := float(r["life"]) <= 0.0
		var hit_e: Enemy = null
		for n in enemies:
			var e := n as Enemy
			if e != null and e.hp > 0.0 and p.distance_to(e.global_position) < e.radius + 4.0:
				boom = true
				hit_e = e
				break
		if boom:
			if r.get("sticky", false):
				# «Термобарика»: заряд прилипает и рвётся через 0,5 с объёмным взрывом
				_sticky.append({"e": weakref(hit_e) if hit_e != null else null, "off": p - (hit_e.global_position if hit_e != null else p),
					"p": p, "t": 0.5, "dmg": float(r["dmg"]) * 1.5})
			else:
				aoe(p, float(r["r"]), float(r["dmg"]), r.get("src", "НАР"))
			rockets.remove_at(i)


var _sticky: Array = []


func _update_thermo(delta: float) -> void:
	for i in range(_thermo.size() - 1, -1, -1):
		_thermo[i]["t"] = float(_thermo[i]["t"]) - delta
		if float(_thermo[i]["t"]) <= 0.0:
			_thermo.remove_at(i)
	for i in range(_sticky.size() - 1, -1, -1):
		var s: Dictionary = _sticky[i]
		var wr = s["e"]
		if wr != null:
			var e: Enemy = (wr as WeakRef).get_ref() as Enemy
			if e != null:
				s["p"] = e.global_position + (s["off"] as Vector2)
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			_sticky.remove_at(i)
			var pos: Vector2 = s["p"]
			var near := 0
			for t in _thermo:
				if (t["p"] as Vector2).distance_to(pos) < 150.0:
					near += 1
			var k := minf(1.0 + 0.3 * near, 2.0) # слияние соседних взрывов
			_thermo.append({"p": pos, "t": 0.3})
			aoe(pos, 130.0 + 20.0 * mini(near, 4), float(s["dmg"]) * k, "связка: термобарика")
			Main.I.add_shake(1.5)


func _update_bombs(delta: float) -> void:
	for i in range(bombs.size() - 1, -1, -1):
		var b := bombs[i]
		b["t"] = float(b["t"]) - delta
		var k := 1.0 - clampf(float(b["t"]) / float(b["fuse"]), 0.0, 1.0)
		b["p"] = (b["from"] as Vector2).lerp(b["to"], 1.0 - pow(1.0 - k, 2.0))
		if float(b["t"]) <= 0.0:
			aoe(b["p"], float(b["r"]), float(b["dmg"]), b["src"], true, null, 0, bool(b.get("ground", false)))
			if b.get("road", false): # «Ковровая дорожка»: крест суббоеприпасов и горящее пятно
				for j in 4:
					var to: Vector2 = b["p"] + Vector2.from_angle(j * PI / 2.0 + PI / 4.0) * 90.0
					spawn_bomb(b["p"], 0.35, float(b["dmg"]) * 0.5, float(b["r"]) * 0.7, "связка: ковровая дорожка", to, bool(b.get("ground", false)))
				spawn_fire(b["p"], 70.0, 12.0, 2.5, "связка: ковровая дорожка")
			# тест 3.5-s4 (п. 14): на земле остаётся воронка (бомбы падают до земли; БЧ ракеты рвётся в воздухе)
			if String(b["src"]) != "разделяющаяся БЧ" and is_instance_valid(Main.I.fx.ground):
				Main.I.fx.ground.crater(b["p"], float(b["r"]))
			Main.I.sfx.play("bomb", -10.0)
			Main.I.add_shake(2.0)
			bombs.remove_at(i)


func _missile_spd() -> float:
	var pl := Main.I.player
	return float(pl.mods.get("missile_spd", 1.0)) if is_instance_valid(pl) else 1.0


func _update_missiles(delta: float) -> void:
	var pl := Main.I.player
	var alive := pl != null and pl.hp > 0.0
	var jam := pl.jam_chance() if alive else 0.0
	for i in range(missiles.size() - 1, -1, -1):
		var m := missiles[i]
		m["life"] = float(m["life"]) - delta
		var v: Vector2 = m["v"]
		var p: Vector2 = m["p"]
		# «Ласка»: помехи — ракета рядом с ведущим может потерять захват (проверка один раз)
		if alive and jam > 0.0 and not m["lost"] and not m.get("jam", false) and p.distance_to(pl.global_position) < 350.0:
			m["jam"] = true
			if randf() < jam:
				m["lost"] = true
				m["life"] = minf(float(m["life"]), 1.2)
				Main.I.stats_add_counter("jammed", 1)
		if m.has("decoy"):
			var fp: Vector2 = (m["decoy"] as Dictionary)["p"]
			var ang2 := rotate_toward(v.angle(), (fp - p).angle(), deg_to_rad(400.0) * delta)
			v = Vector2.from_angle(ang2) * v.length()
			if float(m["life"]) - delta <= 0.0:
				Main.I.fx.explosion(p, 14.0, true, true, "flak")
		elif alive and not m["lost"]:
			var ang := rotate_toward(v.angle(), (pl.global_position - p).angle(), deg_to_rad(Tuning.g("missile_turn")) * delta)
			var spd := minf(v.length() + 400.0 * delta, Tuning.g("missile_speed"))
			v = Vector2.from_angle(ang) * spd
		p += v * delta
		m["v"] = v
		m["p"] = p
		_trail_push(m, p, 30)
		var done := float(m["life"]) <= 0.0
		if alive:
			var dm := p.distance_to(pl.global_position)
			if not m["lost"] and dm < pl.radius + 6.0 and not pl.is_invulnerable():
				pl.damage(Tuning.g("missile_dmg"), "ракеты", "ракетоносцы")
				Main.I.stats_add_counter("missile_hits", 1)
				done = true
			else:
				_check_near_miss(m, dm, pl.radius + 50.0, pl, "ракета", pl.radius + 6.0)
		if done:
			Main.I.fx.hit_spark(p, Color(1, 0.5, 0.2))
			missiles.remove_at(i)


func _update_enemy_bullets(delta: float) -> void:
	var pl := Main.I.player
	var alive := pl != null and pl.hp > 0.0
	for i in range(ebullets.size() - 1, -1, -1):
		var b := ebullets[i]
		b["life"] = float(b["life"]) - delta
		var p0: Vector2 = b["p"]
		var p: Vector2 = p0 + b["v"] * delta
		b["p"] = p
		var done := float(b["life"]) <= 0.0
		var r := 9.0 if b["big"] else 5.0
		if not done:
			for w in (pl.wingmen if alive else []):
				var wm: Wingman = w
				if wm.alive() and p.distance_to(wm.global_position) < 14.0 + r:
					wm.damage(Tuning.g("ebullet_dmg") * (2.0 if b["big"] else 1.0) * float(b["k"]))
					done = true
					break
		if alive and not done:
			var d := p.distance_to(pl.global_position)
			# 3.4: пересечение по относительному движению за кадр (быстрый самолёт не «проскакивает» пулю)
			var rel_hit := seg_hit(p0 - (pl.global_position - pl.velocity * delta), p - pl.global_position, Vector2.ZERO, pl.radius + r)
			if rel_hit and pl.dodges("пули", str(b["who"])):
				Main.I.tele.add("dive_dodged") # 3.5: «Нырок» — пуля прошла над самолётом
			elif not pl.is_invulnerable() and rel_hit:
				pl.damage(Tuning.g("ebullet_dmg") * (2.0 if b["big"] else 1.0) * float(b["k"]), "пули", str(b["who"]))
				done = true
			else:
				_check_near_miss(b, d, pl.radius + r + 30.0, pl, "пуля", pl.radius + r)
		if done:
			ebullets.remove_at(i)


## Снаряд прошёл рядом и начал удаляться, не попав, — «на волоске»
func _check_near_miss(b: Dictionary, d: float, near: float, pl: Player, kind: String, hit_r := 0.0) -> void:
	if b.get("nm", false):
		return
	var prev: float = b.get("pd", INF)
	b["pd"] = d
	# 3.4: снаряд прошёл сквозь неуязвимый самолёт — это не «на волоске», перезарядки не сокращаются
	if d < hit_r and pl.is_invulnerable():
		b["through"] = true
	if d < near:
		b["close"] = true
	elif b.get("close", false) and d > prev:
		b["nm"] = true
		if b.get("through", false):
			Main.I.tele.add("nm_through")
		else:
			pl.on_near_miss(kind)
		# 2.4: увернулся от ракеты — она проскакивает и гаснет, второго захода нет
		if kind == "ракета":
			b["lost"] = true
			b["life"] = minf(float(b["life"]), 1.0)


# ---------- Отрисовка ----------

func _draw() -> void:
	for f in fires:
		var a := clampf(float(f["t"]), 0.0, 1.0)
		var fc: Color = f.get("c", Color(1.0, 0.45, 0.1))
		draw_circle(f["p"], float(f["r"]), Color(fc.r, fc.g, fc.b, 0.18 * a))
		draw_circle(f["p"], float(f["r"]) * 0.55, Color(lerpf(fc.r, 1.0, 0.5), lerpf(fc.g, 1.0, 0.5), lerpf(fc.b, 1.0, 0.5), 0.22 * a))
	# 3.1: трассеры игрока — яркое ядро, тёплое свечение и тёмная подложка (читается на светлой земле)
	for b in bullets:
		var p: Vector2 = b["p"]
		var dir := (b["v"] as Vector2).normalized()
		var l := 34.0 if b.has("pierce") else 24.0
		draw_line(p - dir * l, p, Color(0.1, 0.07, 0.03, 0.5), 6.0)
		draw_line(p - dir * l, p, Color(1.0, 0.62, 0.15, 0.75), 4.0)
		draw_line(p - dir * l * 0.6, p, Color(1.0, 0.97, 0.8), 1.6)
	for m in pmissiles:
		var tc: Color = m.get("tint", Color(0.86, 0.86, 0.9))
		_draw_smoke(m["trail"], m["p"], tc, 1.0)
		_draw_missile(m["p"], m["v"], 22.0, Color(0.95, 0.95, 1.0))
	for st in _sticky:
		var sp: Vector2 = st["p"]
		draw_circle(sp, 6.0 + 4.0 * sin(Time.get_ticks_msec() * 0.03), Color(1.0, 0.95, 0.7, 0.85))
	for r in rockets:
		if float(r["delay"]) > 0.0:
			continue
		_draw_smoke(r["trail"], r["p"], Color(0.86, 0.86, 0.9), 0.6)
		_draw_missile(r["p"], r["v"], 14.0, Color(0.85, 0.88, 0.9))
	for b in bombs:
		var k := 1.0 - float(b["t"]) / float(b["fuse"])
		if not Render3D.enabled:   # тест 3.5-s4 (п. 10): в 3D падает модель бомбы (render3d._sync_bombs)
			draw_circle(b["p"], 5.0, Color(0.6, 0.62, 0.55))
		# зона поражения: видно, куда упадёт и как далеко достанет
		draw_arc(b["to"], float(b["r"]), 0.0, TAU, 40, Color(1.0, 0.7, 0.3, 0.12 + 0.3 * k), 2.0)
		draw_circle(b["to"], float(b["r"]) * 0.35, Color(1.0, 0.55, 0.2, 0.06 + 0.1 * k))
	for b in ebullets:
		if Render3D.enabled:   # тест 3.5-s5 (п. 11): в 3D — светящиеся трассеры (render3d._sync_enemy_shots)
			break
		var ep: Vector2 = b["p"]
		if b["big"]:
			draw_circle(ep, 13.0, Color(1.0, 0.2, 0.5, 0.35))
			draw_circle(ep, 7.0, Color(1.0, 0.35, 0.6))
			draw_circle(ep, 3.2, Color(1.0, 0.9, 0.95))
			continue
		# 3.1: вражеский трассер — красно-розовый, с ярким наконечником
		var ed := (b["v"] as Vector2).normalized()
		draw_line(ep - ed * 26.0, ep, Color(0.2, 0.0, 0.05, 0.35), 6.0)
		draw_line(ep - ed * 26.0, ep, Color(1.0, 0.2, 0.35, 0.55), 4.5)
		draw_line(ep - ed * 14.0, ep, Color(1.0, 0.75, 0.8), 2.0)
		draw_circle(ep, 3.5, Color(1.0, 0.9, 0.95))
	for m in missiles:
		var lost: bool = m["lost"]
		_draw_smoke(m["trail"], m["p"], Color(0.55, 0.5, 0.5), 1.0)
		var p: Vector2 = m["p"]
		if Render3D.enabled:   # тест 3.5-s5 (п. 11): в 3D ракета — модель с факелом и ореолом
			continue
		if not lost:
			draw_circle(p, 11.0, Color(1.0, 0.1, 0.05, 0.25)) # вражеская ракета — красный ореол
		_draw_missile(p, m["v"], 24.0, Color(1.0, 0.45, 0.4) if not lost else Color(0.6, 0.5, 0.5))


## Дымный шлейф: у ракеты тонкий и плотный, к хвосту шире и прозрачнее
func _draw_smoke(tr: PackedVector2Array, head: Vector2, col: Color, k: float) -> void:
	var n := tr.size()
	if n == 0:
		return
	var prev := tr[0]
	for j in range(1, n + 1):
		var cur: Vector2 = head if j == n else tr[j]
		var a := float(j) / n
		draw_line(prev, cur, Color(col.r, col.g, col.b, 0.55 * a * k), (2.0 + 7.0 * (1.0 - a)) * (0.6 + 0.4 * k))
		draw_line(prev, cur, Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.22 * a * k), 1.2)
		prev = cur


static var _mtex: Texture2D = null

## Корпус ракеты: картинка ракеты В-В (нос вверх), повернутая по скорости, и факел двигателя
func _draw_missile(p: Vector2, v: Vector2, length: float, tint: Color) -> void:
	if _mtex == null:
		_mtex = PlaneArt.weapon_tex("aam")
	var dir := v.normalized() if v.length() > 1.0 else Vector2.RIGHT
	draw_circle(p - dir * length * 0.55, 3.0, Color(1.0, 0.75, 0.3, 0.95))
	if Fx._soft != null:
		draw_texture_rect(Fx._soft, Rect2(p - dir * length * 0.6 - Vector2(7, 7), Vector2(14, 14)), false, Color(1.0, 0.6, 0.2, 0.7))
	if _mtex == null:
		draw_line(p - dir * length * 0.5, p + dir * length * 0.5, tint, 3.0)
		return
	var k := length / float(_mtex.get_height())
	draw_set_transform(p, dir.angle() + PI / 2.0, Vector2(k * 1.6, k))
	draw_texture(_mtex, -_mtex.get_size() / 2.0, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
