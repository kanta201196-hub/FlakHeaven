class_name Hardpoint
extends RefCounted
## Группа подвесов: одно оружие на все точки группы, один приоритет целей.
## Логика стрельбы каждого вида оружия — здесь.

var name := ""
var slots := 1
var weapon := ""      # "" — пустая группа
var level := 1
var priority := "nearest"
var builtin := false  # встроенные турели: оружие не меняется
var cd := 1.5
var bonus := 0.0         # бонус урона от редкости карточек улучшения
var trigger := "auto"    # для НАР и бомб: "auto" — сами, "button" — по кнопке (ПКМ / LT)
var evo := false         # 3.1: эволюция (оружие ур. 5 + катализатор)
var evo_plus := 0        # «Э+» из резерва: +8% урона, −4% перезарядки
var _side := 1.0
var _icd := 0.0          # турели: перехват ракет (зонтик, «Дикобраз», нашивка)
var _barrel := 0


func _init(p_name: String, p_slots: int, p_weapon: String, p_builtin := false) -> void:
	name = p_name
	slots = p_slots
	weapon = p_weapon
	builtin = p_builtin
	cd = randf_range(0.5, 1.5)


func is_empty() -> bool:
	return weapon == ""


func label() -> String:
	if is_empty():
		return "%s: пусто" % name
	var s := "%s ×%d: %s ур. %d" % [name, slots, Weapons.DEFS[weapon]["short"], level]
	if evo:
		s = "%s ×%d: %s (Э%s)" % [name, slots, Prog.EVOS[weapon]["title"], ("+%d" % evo_plus) if evo_plus > 0 else ""]
	if bonus > 0.0:
		s += " (+%d%%)" % int(round(bonus * 100.0))
	if uses_trigger() and trigger == "button":
		s += " [ПКМ]"
	return s


func uses_trigger() -> bool:
	return not is_empty() and Weapons.DEFS[weapon].get("uses_trigger", false)


func dmg() -> float:
	var base: float = Weapons.DEFS[weapon]["dmg"] * (1.0 + bonus) * _owner_k()
	if evo:
		var ek := (1.0 + bonus) * _owner_k() * (1.0 + 0.08 * evo_plus)
		match weapon:
			"aam":
				return 120.0 * ek # «Шмель»: тяжёлая ракета; при попадании ещё 4 БЧ по 40
			"rockets":
				return 22.0 * ek
			"gunpod":
				return 7.0 * ek
			"bombs":
				return 55.0 * ek
			"turret":
				return Weapons.DEFS["turret"]["dmg"] * (1.0 + 0.15 * (level - 1)) * ek
	match weapon:
		"turret":
			return base * (1.0 + 0.15 * (level - 1))
		"rockets": # 3.5: залп фиксирован, уровень — урон и радиус
			return base * (1.0 + Tuning.g("rocket_lvl_dmg") * (level - 1))
		"aam": # 3.5: всегда 1 ракета с точки; ур. 4 вместо второй — урон и скорость
			return base * (1.0 + Tuning.g("aam_lvl_dmg") * (level - 1)) * (1.0 + Tuning.g("aam_l4_dmg") if level >= 4 else 1.0)
		_:
			return base * (1.0 + 0.25 * (level - 1))


func reload_time(p: Player) -> float:
	var base: float = Weapons.DEFS[weapon]["cd"]
	var k := 1.0
	if evo:
		match weapon:
			"aam":
				base = 4.5
			"rockets":
				base = 3.5
			"gunpod":
				base = 0.12
			"bombs":
				base = 4.0
		k *= pow(0.96, evo_plus)
	match weapon:
		"aam":
			if not evo:
				k *= 1.0 - 0.1 * (level - 1)
		"flares":
			k *= pow(0.9, level - 1)
		"bombs":
			if not evo:
				k *= 1.0 - 0.08 * (level - 1)
		"gunpod", "turret":
			if not (evo and weapon == "gunpod"):
				k *= 1.0 / (1.0 + 0.1 * (level - 1))
			k /= p.mods["servo_rate"]
	if weapon == "turret":
		if p.carpet_t > 0.0:
			k *= 0.5 # «Огненный ковёр»: турели в два раза чаще, пока действует
		if p.umbrella_t > 0.0:
			k *= 0.5 # «Зенитный зонтик»
	elif p.assault_t > 0.0 and not builtin:
		k /= 3.0 # «Штурмовой заход»: подвесы перезаряжаются втрое быстрее
	if weapon == "turret":
		k /= float(p.mods.get("turret_rate", 1.0))
	if weapon == "aam" or weapon == "rockets":
		k *= float(p.mods.get("msl_cd", 1.0)) # модуль «Пусковое устройство»
	return base * k * p.mods["hp_cd"] * Profile.wk(weapon, "cd")


## Множители урона от класса самолёта и связок (2.8)
func _owner_k() -> float:
	var p := Main.I.player if Main.I != null else null
	if p == null:
		return 1.0
	var k := 1.0
	if weapon == "turret":
		k *= float(p.cls.get("turret_k", 1.0))
	if weapon == "turret":
		k *= float(p.mods.get("turret_dmg", 1.0))
	if weapon == "aam" or weapon == "rockets":
		k *= p.missile_k()
	return k * (1.0 + float(p.mods.get("hp_dmg", 0.0)))


func range_px() -> float:
	var base: float = Weapons.DEFS[weapon]["range"]
	var p := Main.I.player if Main.I != null else null
	if p != null:
		if weapon == "turret":
			base *= float(p.cls.get("turret_range_k", 1.0))
			if p.umbrella_t > 0.0:
				base *= 1.3
			if evo:
				base *= 1.4
		if weapon == "gunpod" or weapon == "turret":
			base *= p.mods["servo_range"]
		base *= Profile.wk(weapon, "range")
		if weapon == "aam":
			base *= float(p.mods.get("msl_lock", 1.0)) # «Ракетный двигатель»: дальность захвата
		if evo and weapon == "gunpod":
			return 520.0 * p.mods["servo_range"]
		if evo and weapon == "flares":
			return 360.0
	match weapon:
		"flares":
			return base * (1.0 + 0.08 * (level - 1))
		"gunpod", "bombs":
			return base * (1.0 + 0.1 * (level - 1))
	return base


func update(delta: float, p: Player) -> void:
	if is_empty():
		return
	if weapon == "turret":
		_turret_intercept(delta, p)
		if p.syn.has("hedgehog"):
			_hedgehog(delta, p)
	cd -= delta
	if cd > 0.0:
		return
	var manual := uses_trigger() and trigger == "button"
	if manual and not Input.is_action_pressed("fire_hardpoint"):
		return
	var fired := false
	match weapon:
		"aam":
			fired = _fire_aam(p)
		"rockets":
			fired = _fire_rockets(p, manual)
		"gunpod", "turret":
			fired = _fire_gun(p)
		"flares":
			fired = _fire_flares(p)
		"bombs":
			fired = _fire_bombs(p, manual)
	# 3.4: после выстрела переносим опоздание (до 0,05 с) — темп меньше зависит от FPS
	cd = (minf(0.0, maxf(cd, -0.05)) + reload_time(p)) if fired else 0.2
	if _quick:
		_quick = false
		cd = 0.2


## Турели сбивают ракеты: «Зенитный зонтик» (раз в 0,5 с), «Дикобраз» (1,5 с), нашивка «Турели II» (3 с)
func _turret_intercept(delta: float, p: Player) -> void:
	var iv := INF
	if p.umbrella_t > 0.0:
		iv = 0.5
	if evo:
		iv = minf(iv, 1.5)
	if p.syn.has("hedgehog"):
		iv = minf(iv, 3.0) # «Стальной ёж»
	if p.has_perk("b_aa2"):
		iv = minf(iv, 4.0) # перк «Заградогонь»
	if iv == INF:
		return
	_icd -= delta
	if _icd > 0.0:
		return
	var r := 300.0 if p.umbrella_t > 0.0 else range_px() * 0.75
	var n := 0
	for s in slots:
		if Main.I.projectiles.intercept_missile(p.global_position, r):
			n += 1
	if p.umbrella_t > 0.0 and p.lvl_of("umbrella") >= 2:
		n += Main.I.projectiles.intercept_bullets(p.global_position, 180.0)
	if n > 0:
		Main.I.stats_add_counter("intercepted_turrets", n)
		_icd = iv
	else:
		_icd = 0.1


var _hh_cd := 5.0
var _quick := false
var _salvo_n := 0
var _gun_n := 0


## «Стальной ёж»: раз в 5 с каждая турель — 3 мини-ракеты по разным целям
func _hedgehog(delta: float, p: Player) -> void:
	_hh_cd -= delta
	if _hh_cd > 0.0:
		return
	var skip: Array = []
	var targets: Array = []
	for i in slots * 3:
		var t := Weapons.pick_target(p.global_position, 900.0, "nearest", skip)
		if t == null:
			break
		targets.append(t)
		skip.append(t)
	if targets.is_empty():
		_hh_cd = 0.3
		return
	_hh_cd = 5.0
	for i in slots * 3:
		var t2: Enemy = targets[i % targets.size()]
		Main.I.projectiles.spawn_player_missile(p.global_position, p.velocity + Vector2.from_angle(TAU * i / (slots * 3.0)) * 260.0, t2,
			22.0 * _owner_k(), "связка: стальной ёж", {"splash": 45.0, "tint": Color(0.4, 0.95, 0.9)})
	Main.I.sfx.play("aam_launch", -12.0, 1.8)


## «Волчья стая»: ведомые повторяют пуск по той же цели
func _wolf(p: Player, t: Enemy, d: float) -> void:
	if not p.syn.has("wolfpack") or t == null:
		return
	for w in p.wingmen:
		var wm: Wingman = w
		if wm.alive():
			wm.mirror_launch(t, d * 0.6)


func _slot_pos(p: Player, i: int) -> Vector2:
	if slots == 1:
		return p.global_position
	var side := -1.0 if i % 2 == 0 else 1.0
	return p.global_position + Vector2.from_angle(p.heading + PI / 2.0) * 12.0 * p.size * side


func _fire_aam(p: Player) -> bool:
	# 3.5: качество вместо количества — всегда 1 ракета с точки (ур. 4 усиливает ракету, а не добавляет вторую)
	var per_slot := 1
	if evo:
		per_slot = maxi(1, 2 / slots) # «Шмель»: 2 тяжёлые ракеты, каждая делится на 4 БЧ
	var hunter := int(p.taken.get("seeker", 0)) >= 3 # «ГСН» ×3: и по наземным
	var targets: Array = []
	var skip: Array = []
	for i in slots * per_slot:
		var t := Weapons.pick_target(p.global_position, range_px(), priority if hunter else ("nearest" if priority == "ground" else priority), skip, not hunter)
		if t == null:
			break
		targets.append(t)
		skip.append(t)
	if targets.is_empty():
		return false
	var n := slots * per_slot
	for i in n:
		var t: Enemy = targets[i % targets.size()]
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := _slot_pos(p, i)
		var vel := p.velocity + Vector2.from_angle(p.heading + side * 0.5) * 150.0
		var opts := {}
		if evo:
			opts = {"split": 4, "split_dmg": 40.0 * (1.0 + bonus) * _owner_k() * (1.0 + 0.08 * evo_plus), "big": true}
		if hunter:
			opts["ground_k"] = 1.5
		if p.syn.has("carousel"):
			opts["carousel"] = 0
		var md := dmg() * Profile.wk("aam", "dmg")
		opts["spd_k"] = Profile.wk("aam", "spd") * (1.2 if level >= 4 and not evo else 1.0)
		Main.I.projectiles.spawn_player_missile(pos, vel, t, md, "ракеты В-В", opts)
		if i < slots:
			_wolf(p, t, md)
	Main.I.sfx.play("aam_launch", -16.0, 1.4)
	return true


func _fire_rockets(p: Player, manual := false) -> bool:
	# Авто: залп, только когда цель точно перед носом (узкий конус) и близко — меньше промахов
	var fwd := Vector2.from_angle(p.heading)
	var ok := manual or p.assault_t > 0.0 # «Штурмовой заход»: без прицеливания
	var cone := deg_to_rad(25.0 if evo else 10.0) * (1.3 if Profile.wbranch("rockets", 1) == "b" else 1.0)
	for n in Main.I.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var to := e.global_position - p.global_position
		if ok:
			break
		if to.length() < (700.0 if evo else 620.0) * Profile.wk("rockets", "auto_r") * float(p.mods.get("msl_lock", 1.0)) and absf(fwd.angle_to(to)) < cone + atan2(e.radius, to.length()):
			ok = true
			break
	if not ok:
		return false
	var per_slot := 4 # 3.5: залп фиксирован — 4 с точки; уровень даёт урон и радиус
	var splash := 60.0 * (1.0 + Tuning.g("rocket_lvl_r") * (level - 1))
	var dirs := [0.0]
	if evo: # «Ливень»: веер в 3 стороны по 5 ракет
		per_slot = 5
		splash = 70.0
		dirs = [-deg_to_rad(25.0), 0.0, deg_to_rad(25.0)]
	var rd := dmg() * Profile.wk("rockets", "dmg")
	var rs := Profile.wk("rockets", "spd") * float(p.mods.get("missile_spd", 1.0))
	if p.mods.has("msl_boost"):
		rd *= float(p.mods["msl_boost"]) # «Форсированный старт»: НАР летит меньше секунды
	splash *= float(p.mods.get("msl_r", 1.0))
	_salvo_n += 1
	if p.syn.has("salvo") and _salvo_n % 3 == 0:
		_wall(p, fwd, rd)
		Main.I.sfx.play("rocket_launch", -10.0, 1.4)
		return true
	var ropts := {"sticky": true, "src": "связка: термобарика"} if p.syn.has("thermobaric") else {}
	_wolf(p, Weapons.pick_target(p.global_position + fwd * 300.0, 500.0, "nearest"), rd * 3.0)
	if p.assault_t > 0.0 and p.syn.has("s_conveyor"):
		per_slot *= 2 # «Конвейер»
	for s in slots:
		for d0 in dirs:
			for i in per_slot:
				var spread := deg_to_rad(randf_range(-4.5, 4.5)) + float(d0)
				var dir := fwd.rotated(spread)
				var pos := _slot_pos(p, s) + dir * 10.0
				Main.I.projectiles.spawn_rocket(pos, p.velocity + dir * randf_range(820.0, 980.0) * rs, rd, splash * Profile.wk("rockets", "blast_r"), i * 0.04, ropts)
	Main.I.sfx.play("rocket_launch", -14.0, 1.8)
	return true


## «Огненный вал»: три линии по 5 взрывов в 250 / 450 / 650 пикс. впереди, ширина 420
func _wall(p: Player, fwd: Vector2, d: float) -> void:
	var side := Vector2(-fwd.y, fwd.x)
	var spd := 900.0
	for li in 3:
		var dist := 250.0 + 200.0 * li
		for j in 5:
			var off := (float(j) / 4.0 - 0.5) * 420.0
			var target := p.global_position + fwd * dist + side * off
			var v := (target - p.global_position).normalized() * spd
			Main.I.projectiles.spawn_rocket(p.global_position + side * off * 0.1, p.velocity * 0.3 + v, d * 1.3, 70.0, 0.03 * j + 0.06 * li,
				{"life": p.global_position.distance_to(target) / spd, "src": "связка: огненный вал"})


func _fire_gun(p: Player) -> bool:
	var t: Enemy = null
	if weapon == "turret" and p.umbrella_t > 0.0:
		t = Weapons.pick_target(p.global_position, range_px(), priority, [], true) # зонтик: сначала самолёты
	if t == null:
		t = Weapons.pick_target(p.global_position, range_px(), priority)
	if t == null:
		return false
	var pierce := 0
	if weapon == "gunpod" and p.syn.has("gunner"):
		pierce += 1
	if evo and weapon == "gunpod":
		pierce += 1
	var barrels := 2 if (evo and weapon == "turret") else 1
	for s in slots:
		for b in barrels:
			var pos := _slot_pos(p, s)
			if evo and weapon == "gunpod": # «Газонокосилка»: стволы поочерёдно
				_barrel += 1
				pos += Vector2.from_angle(p.heading + PI / 2.0) * (6.0 if _barrel % 2 == 0 else -6.0)
			if barrels > 1:
				pos += Vector2.from_angle(p.heading + PI / 2.0) * (5.0 if b == 0 else -5.0)
			var to := t.global_position - pos
			var spd := 1300.0 * Profile.wk(weapon, "spd")
			var dir := (t.global_position - pos).normalized().rotated(randf_range(-0.04, 0.04))
			var gd := dmg() * Profile.wk(weapon, "dmg")
			var he := 0.0
			if weapon == "gunpod" and p.syn.has("gunner"):
				_gun_n += 1
				if _gun_n % 6 == 0: # «Пушкарь»: фугасный снаряд
					gd *= 4.0
					he = 70.0
			Main.I.projectiles.spawn_player_bullet(pos, dir * spd + p.velocity * 0.5, gd, (to.length() + 60.0) / spd, false,
				"турели" if weapon == "turret" else "гондола", pierce, he)
	Main.I.sfx.play("turret_fire" if weapon == "turret" else "gunpod_fire", -21.0)
	return true


func _fire_flares(p: Player) -> bool:
	# 3.1: ослаблены — одна ракета за срабатывание (с ур. 4 — две), пули — с ур. 4 и в малом радиусе.
	# Видно как отстрел тепловых ловушек: ракета уходит на ловушку и рвётся рядом с ней.
	var killed := 0
	var r := range_px()
	var per := (2 if level >= 4 else 1) + (1 if evo else 0)
	var any := false
	for s in per:
		var mp = Main.I.projectiles.intercept_missile_at(p.global_position, r, true)
		if mp != null:
			killed += 1
			any = true
			if Profile.wbranch("flares", 2) == "a": # «Ловушка с подрывом»
				Main.I.projectiles.aoe(mp, 60.0, 20.0, "противоракеты")
			if evo: # «Салют»: перехват выпускает 3 ловушки по врагам
				var skip: Array = []
				for j in 3:
					var t := Weapons.pick_target(mp, 700.0, "nearest", skip)
					if t != null:
						skip.append(t)
					Main.I.projectiles.spawn_player_missile(mp, Vector2.from_angle(randf() * TAU) * 200.0, t, 25.0 * (1.0 + 0.08 * evo_plus) * _owner_k(), "противоракеты")
	if level >= 4 or evo:
		killed += Main.I.projectiles.intercept_bullets(p.global_position, 200.0 if evo else 90.0 + 15.0 * (level - 4))
	if killed > 0 and Profile.wbranch("flares", 2) == "b" and randf() < 0.2:
		_quick = true # «Запас ловушек»
	if killed > 0:
		Main.I.fx.flare_burst(p.global_position, p.heading, 8, p.velocity, 1.15)
		Main.I.stats_add_counter("intercepted", killed)
		Main.I.sfx.play("flare", -12.0, 2.0)
	return killed > 0


## 3.5 (правка 8): бомбы только по наземным целям, зато вдвое сильнее
const GROUND_BOMB_K := 2.0


func _fire_bombs(p: Player, manual := false) -> bool:
	if evo:
		return _fire_carpet_row(p, manual)
	# 3.5: бомбы бьют только по земле (урон ×GROUND_BOMB_K), самолёты не задевают.
	# Авто — по ближайшим наземным целям в радиусе 600; по кнопке — к курсору / вперёд.
	var targets: Array = []
	if not manual:
		var skip: Array = []
		for s in slots:
			var t := Weapons.pick_target(p.global_position, 600.0, "nearest", skip, false, true)
			if t == null:
				break
			targets.append(t)
			skip.append(t)
		if targets.is_empty():
			return false
	var fuse := 0.55
	for s in slots:
		var to: Vector2
		if not targets.is_empty():
			var t: Enemy = targets[s % targets.size()]
			var tv: Vector2 = t.get("velocity") if t.get("velocity") is Vector2 else Vector2.ZERO
			to = t.global_position + tv * fuse
		elif int(Tuning.g("scheme")) == 2:
			var mp := Render3D.I.mouse_world(p.get_global_mouse_position())
			to = p.global_position + (mp - p.global_position).limit_length(460.0)
		else:
			to = p.global_position + Vector2.from_angle(p.heading) * 300.0
		to += Vector2(randf_range(-20, 20), randf_range(-20, 20))
		Main.I.projectiles.spawn_bomb(_slot_pos(p, s), fuse * Profile.wk("bombs", "fuse"), dmg() * Profile.wk("bombs", "dmg") * GROUND_BOMB_K,
			range_px() * Profile.wk("bombs", "blast_r"), "бомбы", to, true)
		if p.syn.has("carpet_road"): # «Ковровая дорожка»: крест суббоеприпасов и огонь
			Main.I.projectiles.bombs[-1]["road"] = true
	Main.I.sfx.play("bomb_drop", -14.0, 1.2)
	return true


## «Бабушкин ковёр»: ряд из 8 бомб поперёк курса, ширина 600
func _fire_carpet_row(p: Player, manual: bool) -> bool:
	if not manual and Weapons.pick_target(p.global_position, 700.0, "nearest", [], false, true) == null:
		return false
	var fwd := Vector2.from_angle(p.heading)
	var side := Vector2.from_angle(p.heading + PI / 2.0)
	var c := p.global_position + fwd * 220.0 + p.velocity * 0.4
	# 3.4: ветки бомб из ангара (урон, радиус, взрыватель) и «Ковровая дорожка» действуют и после эволюции
	var road := p.syn.has("carpet_road")
	for i in 8:
		var off := (float(i) / 7.0 - 0.5) * 600.0
		Main.I.projectiles.spawn_bomb(p.global_position, (0.5 + 0.04 * i) * Profile.wk("bombs", "fuse"), dmg() * Profile.wk("bombs", "dmg") * GROUND_BOMB_K,
			150.0 * Profile.wk("bombs", "blast_r"), "бомбы", c + side * off, true)
		if road:
			Main.I.projectiles.bombs[-1]["road"] = true
	if road:
		Main.I.tele.add("carpet_road_evo")
	Main.I.sfx.play("bomb_drop", -12.0, 1.0)
	return true
