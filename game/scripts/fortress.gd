class_name Fortress
extends Boss
## FB-01 (решение Kanta 18.10.2026, `docs/proposals/final-boss-rework.md`): финальный босс «Прорыв».
## Тяжёлый носитель не кружит вокруг игрока, а летит по маршруту к нашей базе; игрок его перехватывает.
## Дошёл до базы — бомбит её (запчасти за него −50%) и заходит на второй круг; бой продолжается.
##   1. «Строй» — 4 турели, у каждой свой сектор обстрела; нос и хвост — мёртвые зоны. Эскорт из перехватчиков
##      пополняется, пока цела верхняя (командная) турель.
##   2. «Боевой курс» — люки открываются циклами (6 с из 14) и кладут за собой ковровую дорожку; попадание
##      в открытый люк — ×3 урона по корпусу. Двигатели бьются с задней полусферы; каждый — минус 20% скорости.
##   3. «Падение» — корпус открыт, двигатели чадят чёрным дымом; бросает маршрут и тянет прочь от игрока
##      (S9-20: не кружит), огрызается кольцами пуль и ловушками. Не добили за FLEE_T с — падает сама,
##      запчастей за неё вдвое меньше.
## Урон по точке — только попаданием в неё (своя форма: корпус, крылья, точки — seg_test/aoe_dist);
## автотурели игрока бьют по «Крепости» ×0,35, самонаводящиеся ракеты ×0,6 (тест 3.5-s7: на «Ките» 82% урона — турели).

const LEN := 270.0               # длина корпуса на экране, пикс.
const BASE_SPEED := 230.0        # «Кит» ~320 пикс./с — догоняет с трудом
const HULL_SHARE := 0.5          # доли общей прочности: корпус / 4 турели / 2 двигателя
const TURRET_SHARE := 0.07
const ENGINE_SHARE := 0.11
const PASS := 0.1                # доля урона в корпус мимо точек, пока он прикрыт
const HULL_FLOOR := 0.5          # до фазы 3 корпус не опускается ниже половины своей прочности
const PT_R := 26.0               # круг попадания точки
const PT_NEAR := 46.0            # попадание (или взрыв) ближе этого к точке — урон в неё
const BAY := Vector2(-10, 0)     # бомбовый люк (в осях самолёта)
const BAY_R := 34.0
const BAY_K := 3.0
const BAY_OPEN := 6.0
const BAY_CLOSED := 8.0
const ROUTE_LEN := 26000.0       # от точки появления до базы, ~110 с полёта
const BASE_R := 260.0
const OVERSHOOT := 5000.0        # после налёта уходит на столько и разворачивается на второй круг (~45 с)
const TURRET_K := 0.35           # автотурели и гондола игрока
const HOMING_K := 0.6            # самонаводящиеся ракеты
const NOSE_DEAD := 0.26          # мёртвые зоны: ±15° от носа, ±20° от хвоста
const TAIL_DEAD := 0.35
const SECTOR_R := 750.0
const ESCORT_N := 4
const MIN_FIGHT := 45.0          # предел урона: бой не короче 45 с при любой сборке
const FLEE_SPEED := 0.75         # фаза 3: доля BASE_SPEED — игрок догоняет
const FLEE_T := 50.0

var phase := 1
var points: Array = []           # [{name, node, kind, off (в осях самолёта: x — вперёд), hp, max, cd, shots, st, sec: [центр, полуширина]}]
## Для 3D-модели (узлы GLB: turret_1…turret_4, engine_l, engine_r, hatch_l/r, bay_l/r, core):
## выбитые части — имя узла → true; люки открыты в фазе 2 циклами, корпус раскрыт в фазе 3
var parts_down := {}
var hatches_open := false
var hull_open := false
var base_pos := Vector2.INF      # наша база — цель маршрута
var base_hits := 0
var _wp := Vector2.INF           # текущая точка маршрута (база или точка разворота)
var _to_base := true
var _missile_cd := 4.0
var _ring_cd := 3.0
var total_max := 0.0
var _budget := -1.0
var _budget_t := 0.0
var _zones: Array = []           # [{p, t}] ковровая дорожка: метка на земле → взрыв
var _bay_t := 2.0
var _drop_t := 0.0
var _escorts: Array = []
var _escort_t := 0.0
var _hit_fx := 0.0
var _flee_t := 0.0
var _smoke_t := 0.0


func setup_fortress(total: float) -> void:
	setup("fortress", total * HULL_SHARE)
	total_max = total
	log_entry["hp"] = total
	min_life = 0.0   # у «Крепости» свой предел — на весь бой (MIN_FIGHT)
	shield = 0.0
	shield_max = 0.0
	radius = 70.0
	xp = 150
	parts = 250
	kill_shake = 22.0
	contact_damage = 25.0
	var k := LEN / 270.0
	points = [
		_pt("турель левого крыла", "turret_1", "turret", Vector2(-16, -78) * k, total * TURRET_SHARE, [-PI / 2.0, deg_to_rad(60.0)]),
		_pt("турель правого крыла", "turret_2", "turret", Vector2(-16, 78) * k, total * TURRET_SHARE, [PI / 2.0, deg_to_rad(60.0)]),
		_pt("верхняя турель", "turret_3", "turret", Vector2(22, 0) * k, total * TURRET_SHARE, [0.0, deg_to_rad(100.0)]),
		_pt("кормовая турель", "turret_4", "turret", Vector2(-40, 0) * k, total * TURRET_SHARE, [PI, deg_to_rad(70.0)]),
		_pt("левый двигатель", "engine_l", "engine", Vector2(14, -21) * k, total * ENGINE_SHARE, []),
		_pt("правый двигатель", "engine_r", "engine", Vector2(14, 21) * k, total * ENGINE_SHARE, []),
	]
	_set_title()


func _pt(n: String, node: String, kd: String, off: Vector2, h: float, sec: Array) -> Dictionary:
	return {"name": n, "node": node, "kind": kd, "off": off, "hp": h, "max": h, "cd": randf_range(0.8, 2.0), "shots": 0, "st": 0.0, "sec": sec}


func kind() -> String:
	return "асы"


func _set_title() -> void:
	match phase:
		1: title = "«Крепость» идёт на базу — сбейте турели: %d из 4" % (4 - _alive("turret"))
		2: title = "«Крепость» на боевом курсе — двигатели %d из 2, бейте в открытый люк" % (2 - _alive("engine"))
		_: title = "«Крепость» падает и идёт на таран — добивайте!"


func _alive(kd: String) -> int:
	var n := 0
	for pt in points:
		if pt["kind"] == kd and float(pt["hp"]) > 0.0:
			n += 1
	return n


func _world(pt: Dictionary) -> Vector2:
	return global_position + (pt["off"] as Vector2).rotated(heading)


func _bay_world() -> Vector2:
	return global_position + BAY.rotated(heading)


func _want() -> String:
	return "turret" if phase == 1 else ("engine" if phase == 2 else "")


## Угол на точку относительно курса (−PI…PI): 0 — прямо по носу
func _rel(from: Vector2, to: Vector2) -> float:
	return wrapf((to - from).angle() - heading, -PI, PI)


func _in_dead(a: float) -> bool:
	return absf(a) < NOSE_DEAD or absf(a) > PI - TAIL_DEAD


## ---------- Форма для попаданий ----------

## Hit circles of the flying wing (plane axes, px): the centre body from nose to tail and each swept wing along
## its mid-chord out to the tip (VIS-01, Kanta 26.10: the boss is a flying wing at the old span). The points above
## sit on the same model: wing turrets behind the leading edge, the top turret behind the cockpit, the tail turret
## on the centre trailing point, the engines on the intake humps.
static var _shape: Array = []


static func _hull_shape() -> Array:
	if _shape.is_empty():
		for x in [40.0, 18.0, -4.0, -26.0, -40.0]:
			_shape.append([Vector2(x, 0.0), 22.0])
		# wing: [mid-chord x, y, radius], measured on the model at 270 px per hull length
		for w in [[-8.0, 32.0, 22.0], [-11.0, 54.0, 18.0], [-16.0, 78.0, 13.0], [-27.0, 95.0, 13.0], [-40.0, 113.0, 13.0], [-50.0, 128.0, 9.0]]:
			for s in [-1.0, 1.0]:
				_shape.append([Vector2(w[0], s * w[1]), w[2]])
	return _shape


func _closest(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return a + ab * t


func seg_test(a: Vector2, b: Vector2) -> bool:
	if not Projectiles.seg_hit(a, b, global_position, 150.0):
		return false
	var want := _want()
	for pt in points:
		if pt["kind"] == want and float(pt["hp"]) > 0.0 and Projectiles.seg_hit(a, b, _world(pt), PT_R):
			hit_at = _closest(a, b, _world(pt))
			return true
	if phase == 2 and hatches_open and Projectiles.seg_hit(a, b, _bay_world(), BAY_R):
		hit_at = _closest(a, b, _bay_world())
		return true
	for c in _hull_shape():
		var w: Vector2 = global_position + (c[0] as Vector2).rotated(heading)
		if Projectiles.seg_hit(a, b, w, float(c[1])):
			hit_at = _closest(a, b, w)
			return true
	return false


func aoe_dist(pos: Vector2) -> float:
	var d := INF
	var want := _want()
	for pt in points:
		if pt["kind"] == want and float(pt["hp"]) > 0.0:
			d = minf(d, pos.distance_to(_world(pt)) - PT_R)
	if phase == 2 and hatches_open:
		d = minf(d, pos.distance_to(_bay_world()) - BAY_R)
	for c in _hull_shape():
		d = minf(d, pos.distance_to(global_position + (c[0] as Vector2).rotated(heading)) - float(c[1]))
	return d


## Самонаводящиеся ракеты идут в ближайшую уязвимую точку текущей фазы (в фазе 2 — и в открытый люк)
func aim_point(from: Vector2) -> Vector2:
	var best := global_position
	var best_d := INF
	var want := _want()
	for pt in points:
		if pt["kind"] == want and float(pt["hp"]) > 0.0:
			var d := _world(pt).distance_to(from)
			if d < best_d:
				best_d = d
				best = _world(pt)
	if phase == 2 and hatches_open and _bay_world().distance_to(from) < best_d:
		best = _bay_world()
	return best


func aim_radius() -> float:
	return radius if phase >= 3 else PT_R


## ---------- Урон ----------

func _src_k(src: String) -> float:
	if src == "турели" or src == "гондола":
		return TURRET_K
	if src.begins_with("ракеты В-В") or src in ["ёлочка", "противоракеты", "связка: зеркало"]:
		return HOMING_K
	return 1.0


## Damage goes where it hit: into a point of the current phase, into the open bay (×3) or into the hull (10%, not
## below half). S11-30: the fight-length cap (_cap_total) counts only damage that reached the hit points. It used to be
## charged before the hit was routed, so hits on the covered hull (2/3 of the bot's damage in phase 1) used up the
## turrets' share and stretched phase 1 to 75–95 s.
func absorb(dmg: float) -> float:
	var at := hit_at
	hit_at = Vector2.INF
	var offered := dmg * _src_k(last_src)
	_split("in", offered)
	if offered <= 0.0:
		return 0.0
	if phase >= 3:
		var d3 := _landed(offered, "hull")
		_confirm(global_position if at == Vector2.INF else at, d3, Color(1, 0.9, 0.6))
		return d3
	if at != Vector2.INF:
		var want := _want()
		var best: Dictionary = {}
		var best_d := PT_NEAR
		for pt in points:
			if pt["kind"] != want or float(pt["hp"]) <= 0.0:
				continue
			var d := _world(pt).distance_to(at)
			if d < best_d:
				best_d = d
				best = pt
		if not best.is_empty():
			var pd := _landed(offered, "pt")
			_confirm(_world(best), pd, Color(1.0, 0.85, 0.35))
			best["hp"] = float(best["hp"]) - pd
			Main.I.add_stat("dealt", last_src, pd)
			if float(best["hp"]) <= 0.0:
				_point_down(best)
			return 0.0
		if phase == 2 and hatches_open and at.distance_to(_bay_world()) < BAY_R + 12.0:
			var raw_bay := minf(offered * BAY_K, maxf(0.0, hp - max_hp * HULL_FLOOR))
			var bd := _landed(raw_bay, "bay")
			_confirm(_bay_world(), bd, Color(1.0, 0.55, 0.2))
			Main.I.tele.add("fortress_bay")
			return bd
	var raw_hull := minf(offered * PASS, maxf(0.0, hp - max_hp * HULL_FLOOR))
	_split("lost", offered - raw_hull)
	return _landed(raw_hull, "hull")


## Damage that reached the hit points, through the fight-length cap; the autotest counters say where it went and how much was cut
func _landed(d: float, where: String) -> float:
	var c := _cap_total(d)
	_split(where, c)
	_split("cut", d - c)
	return c


## S11-30: where the damage offered to the Fortress went, per phase (autotest prints it at the end of a sortie):
## in — after the source factor, lost — hit the covered hull and did nothing, cut — landed but over the fight-length
## cap, pt — into a point, bay, hull — what reached the hull. Counters only, not log columns.
func _split(k: String, v: float) -> void:
	Main.I.tele.add("fort%d_%s" % [phase, k], v)


func _point_down(pt: Dictionary) -> void:
	var at := _world(pt)
	parts_down[pt["node"]] = true
	Main.I.fx.explosion(at, 34.0)
	Main.I.add_shake(5.0)
	Main.I.sfx.play("fortress_part", -4.0, 0.8)
	Main.I.tele.add("fortress_points")
	if pt["kind"] == "engine":
		Events.banner.emit("Двигатель сбит: %d из 2 — «Крепость» теряет скорость" % (2 - _alive("engine")), 2.5)
	elif pt["node"] == "turret_3":
		Events.banner.emit("Командная турель сбита — эскорт больше не придёт", 2.5)
	else:
		Events.banner.emit("Турель сбита: %d из 4" % (4 - _alive("turret")), 2.0)
	Main.I.fx.text(at + Vector2(0, -40), "СБИТА!" if pt["kind"] == "turret" else "СБИТ!", Color(1.0, 0.8, 0.4))
	Main.I.fx.ring(at, 70.0, Color(1.0, 0.6, 0.25))
	if phase == 1 and _alive("turret") == 0:
		phase = 2
		_bay_t = 1.5
		Events.banner.emit("Турели сбиты! «Крепость» на боевом курсе — бейте в открытый люк и по двигателям", 3.5)
		Events.radio.emit("Штаб", "Турели молчат! Ждите, когда откроется люк, — бейте в брюхо. Двигатели — с задней полусферы.", false)
		Main.I.tele.add("fortress_phase2_s", Main.I.run_time - _born)
		_missile_cd = 3.0
	elif phase == 2 and _alive("engine") == 0:
		phase = 3
		hull_open = true
		hatches_open = false
		_zones.clear()
		Events.banner.emit("Двигатели горят! «Крепость» дымит и уходит — догоните и добейте!", 3.5)
		Events.radio.emit("Штаб", "Она горит и уходит! Догоняйте, пока не скрылась, — кормовые кольца бьют назад, заходите сбоку.", false)
		Main.I.tele.add("fortress_phase3_s", Main.I.run_time - _born)
	_set_title()


## ---------- Поведение ----------

func behave(delta: float) -> void:
	_t += delta
	_hit_fx = maxf(0.0, _hit_fx - delta)
	var p := Main.I.player
	if base_pos == Vector2.INF:
		_start_route(p)
	var spd := BASE_SPEED * (1.0 - 0.2 * (2 - _alive("engine")))
	if p == null or p.hp <= 0.0:
		position += Vector2.from_angle(heading) * spd * delta
		return
	var to := p.global_position - global_position
	var d := to.length()
	if phase >= 3:
		# S9-20: подбитая — бросает маршрут и тянет прочь от игрока, за двигателями чёрный дым
		heading = rotate_toward(heading, (-to).angle(), deg_to_rad(25.0) * delta)
		position += Vector2.from_angle(heading) * BASE_SPEED * FLEE_SPEED * delta
		_flee_t += delta
		_smoke_t -= delta
		if _smoke_t <= 0.0 and Boom3D.active():
			_smoke_t = 0.07
			for pt in points:
				if pt["kind"] == "engine":
					Boom3D.ensure().black_smoke(_world(pt), 46.0)
		if _flee_t >= FLEE_T and hp > 0.0:
			parts = int(parts * 0.5)
			hp = 0.0
			_die()
			return
	else:
		heading = rotate_toward(heading, (_wp - global_position).angle(), deg_to_rad(22.0) * delta)
		position += Vector2.from_angle(heading) * spd * delta
		if global_position.distance_to(_wp) < BASE_R:
			if _to_base:
				_bomb_base()
				_wp = base_pos + Vector2.from_angle(heading) * OVERSHOOT
			else:
				_wp = base_pos
			_to_base = not _to_base
	if d < SECTOR_R:
		Main.I.tele.add("fort%d_near_s" % phase, delta)
	Main.I.tele.add("fort%d_s" % phase, delta)
	_turrets(delta, p)
	_escort(delta)
	if phase == 2:
		_bay(delta, p, to, d)
	_update_zones(delta, p)
	if phase >= 3:
		flare_defense(delta, 440.0, 280.0, 0.75, 2.5, 8.0)
		_ring_cd -= delta
		if _ring_cd <= 0.0 and d < 900.0:
			_ring_cd = 3.2
			var off := randf() * TAU
			for i in 16:
				var dir := Vector2.from_angle(off + TAU * i / 16.0)
				Main.I.projectiles.spawn_enemy_bullet(global_position + dir * radius, dir * 270.0, kind(), true)
			Main.I.sfx.play("fortress_ring", -8.0, 0.4)
		if int(_t * 8.0) % 3 == 0:
			Main.I.fx.ring(global_position + Vector2(randf_range(-40, 40), randf_range(-40, 40)), 14.0, Color(1.0, 0.55, 0.2))


## Маршрут: от точки появления мимо игрока к базе за ROUTE_LEN пикс.
func _start_route(p: Player) -> void:
	var dir := Vector2.from_angle(heading)
	if p != null:
		dir = (p.global_position - global_position).normalized()
	heading = dir.angle()
	base_pos = global_position + dir * ROUTE_LEN
	_wp = base_pos
	_to_base = true
	Events.banner.emit("«Крепость» идёт на нашу базу! Перехватите её, пока не дошла", 4.0)
	Events.radio.emit("Штаб", "«Крепость» на подходе. Сначала турели — у каждой свой сектор, заходите с носа или с хвоста, там мёртвые зоны.", false)
	Hints.show("fortress", "«Крепость» летит к нашей базе (стрелка «база»). Турели бьют в свои сектора, нос и хвост — мёртвые зоны. Урон идёт в ту точку, куда попали.", 10.0, 2)


func _bomb_base() -> void:
	base_hits += 1
	Main.I.tele.add("fortress_base")
	for i in 6:
		Main.I.fx.explosion(base_pos + Vector2(randf_range(-180, 180), randf_range(-180, 180)), 40.0, false)
	if is_instance_valid(Main.I.fx.ground):
		Main.I.fx.ground.crater(base_pos, 120.0)
	Main.I.add_shake(6.0)
	if base_hits == 1:
		parts = int(parts * 0.5)
		Events.banner.emit("«Крепость» отбомбилась по базе — запчастей за неё вдвое меньше. Она заходит на второй круг!", 4.0)
	else:
		Events.banner.emit("«Крепость» снова над базой! Сбейте её", 3.0)


## Турели: очередь из 3 пуль ближе SECTOR_R, только в свой сектор; в мёртвых зонах (нос, хвост) не бьют
func _turrets(delta: float, p: Player) -> void:
	for pt in points:
		if pt["kind"] != "turret" or float(pt["hp"]) <= 0.0:
			continue
		var at := _world(pt)
		var to := p.global_position - at
		if int(pt["shots"]) > 0:
			pt["st"] = float(pt["st"]) - delta
			if float(pt["st"]) <= 0.0:
				var spd := Tuning.g("ebullet_speed")
				var lead := p.global_position + p.velocity * (to.length() / spd) * 0.6
				var dir := (lead - at).normalized().rotated(randf_range(-0.07, 0.07))
				Main.I.projectiles.spawn_enemy_bullet(at + dir * 10.0, dir * spd, kind(), false, 1.0, int(pt["shots"]) != 3)
				pt["shots"] = int(pt["shots"]) - 1
				pt["st"] = 0.12
			continue
		pt["cd"] = float(pt["cd"]) - delta
		if float(pt["cd"]) > 0.0 or to.length() > SECTOR_R or not _covers(pt, global_position, p.global_position):
			continue
		pt["shots"] = 3
		pt["cd"] = randf_range(1.6, 2.4)


## Видит ли турель точку: в своём секторе и не в мёртвой зоне (углы — от центра «Крепости»)
func _covers(pt: Dictionary, from: Vector2, to: Vector2) -> bool:
	var a := _rel(from, to)
	if _in_dead(a):
		return false
	var sec: Array = pt["sec"]
	return absf(wrapf(a - float(sec[0]), -PI, PI)) <= float(sec[1])


## Эскорт (фаза 1): ESCORT_N перехватчиков; пока цела верхняя турель, раз в 20 с — пополнение
func _escort(delta: float) -> void:
	if phase != 1:
		return
	for i in range(_escorts.size() - 1, -1, -1):
		var e = _escorts[i]
		if not is_instance_valid(e) or (e as Enemy).hp <= 0.0:
			_escorts.remove_at(i)
	_escort_t -= delta
	if _escort_t > 0.0:
		return
	var first := _t < 1.0
	if not first and parts_down.has("turret_3"):
		return
	_escort_t = 20.0
	var n := ESCORT_N - _escorts.size() if first else mini(1, ESCORT_N - _escorts.size())
	for i in n:
		var f := Interceptor.new()
		f.position = global_position + Vector2.from_angle(heading + PI / 2.0 * (i - 1.5)) * 160.0
		f.heading = heading
		Main.I.world.add_child(f)
		f.apply_hp_mult(Tuning.g("enemy_hp_mult") * Spawner.hp_ramp(Main.I.run_time))
		_escorts.append(f)


## Люки (фаза 2): открыты 6 с из 14 — кладут ковровую дорожку под собой; пока закрыты — залп из 4 ракет после захвата
func _bay(delta: float, p: Player, to: Vector2, d: float) -> void:
	_bay_t -= delta
	if _bay_t <= 0.0:
		hatches_open = not hatches_open
		_bay_t = BAY_OPEN if hatches_open else BAY_CLOSED
		if hatches_open:
			Events.banner.emit("Люк открыт! Попадание в люк — ×3 урона", 2.0)
			Main.I.sfx.play("lock", -6.0, 0.6)
	if hatches_open:
		_drop_t -= delta
		if _drop_t <= 0.0:
			_drop_t = 0.4
			_zones.append({"p": _bay_world() + Vector2(randf_range(-30, 30), randf_range(-30, 30)), "t": 1.4})
			Main.I.sfx.play("bomb_drop", -12.0, 0.8)
		return
	if _lock > 0.0:
		_lock -= delta
		if _lock <= 0.0:
			for i in 4:
				# S10-04: пуск с крыльев вперёд по курсу, потом доворот на цель
				Main.I.projectiles.spawn_missile(global_position + Vector2.from_angle(heading + PI / 2.0 * (1.0 if i % 2 else -1.0)) * 40.0,
					Vector2.from_angle(heading + (i - 1.5) * 0.15), "aam", kind(), Projectiles.MSL_FREE)
			Main.I.sfx.play("missile_enemy", -4.0, 0.7)
			_missile_cd = 6.0
		return
	_missile_cd -= delta
	if _missile_cd <= 0.0 and d < 1000.0:
		_lock = 1.1
		Main.I.sfx.play("lock", -4.0, 0.7)


func _update_zones(delta: float, p: Player) -> void:
	for i in range(_zones.size() - 1, -1, -1):
		var z: Dictionary = _zones[i]
		z["t"] = float(z["t"]) - delta
		if float(z["t"]) <= 0.0:
			var zp: Vector2 = z["p"]
			Main.I.fx.explosion(zp, 30.0, false)
			if p.global_position.distance_to(zp) < ZONE_R + p.radius:
				p.damage(18.0, "бомбы", kind())
			_zones.remove_at(i)


## Общая прочность (корпус + живые точки), 0…1
func total_frac() -> float:
	var s := maxf(0.0, hp)
	for pt in points:
		s += maxf(0.0, float(pt["hp"]))
	return s / maxf(total_max, 1.0)


func _cap_total(dmg: float) -> float:
	var rate := total_max / MIN_FIGHT
	var now := Main.I.run_time
	if _budget < 0.0:
		_budget = rate * 1.5
	else:
		_budget = minf(rate * 1.5, _budget + rate * maxf(0.0, now - _budget_t))
	_budget_t = now
	var d := minf(dmg, _budget)
	_budget -= d
	return d


## Подтверждение попадания: искры на точке; раз в 0,15 с — цифра (с выключенными цифрами урона — без неё)
func _confirm(at: Vector2, dmg: float, col: Color) -> void:
	Main.I.fx.hit_spark(at, col)
	if _hit_fx > 0.0:
		return
	_hit_fx = 0.15
	if dmg < 1.0:
		return
	if Tuning.g("damage_numbers") > 0.5:
		Main.I.fx.number(at + Vector2(randf_range(-12, 12), -24), dmg)


const ZONE_R := 80.0


func _die() -> void:
	if _flee_t >= FLEE_T:
		Events.banner.emit("«Крепость» не дотянула и рухнула сама — запчастей за неё вдвое меньше", 4.0)
	else:
		Events.banner.emit("«Крепость» сбита!" if base_hits == 0 else "«Крепость» сбита! (успела отбомбиться по базе)", 4.0)
	for i in 4:
		Main.I.fx.explosion(global_position + Vector2(randf_range(-90, 90), randf_range(-60, 60)), 50.0)
	super()


## Где рисовать кольцо точки. С 3D-моделью (PR #38) башни и винты стоят выше плоскости боя, и на наклонной
## камере кольцо по логическому смещению уезжает от них (~25 пикс. при 28°). Поэтому берём узел модели
## (turret_N, engine_X_prop) и ищем точку плоскости боя (y = 0), которая на экране совпадает с ним.
func _ring_at(pt: Dictionary, xf: Transform2D) -> Vector2:
	var fallback := xf * (pt["off"] as Vector2)
	var r := Render3D.I
	if not Render3D.enabled or r == null or r.cam == null:
		return fallback
	var u: Unit3D = r._units.get(get_instance_id())
	var parts: Dictionary = u.fparts if u != null and u.fparts != null else {}
	var nm := String(pt["node"]) + ("_prop" if pt["kind"] == "engine" else "")
	var n := parts.get(nm) as Node3D
	if n == null or not is_instance_valid(n):
		return fallback
	var c := r.cam.global_position
	var g := n.global_position
	if c.y - g.y < 1.0:
		return fallback
	var k := c.y / (c.y - g.y)   # луч камера → узел до пересечения с y = 0
	var on_plane := Vector2(c.x + (g.x - c.x) * k, c.z + (g.z - c.z) * k)
	return to_local(on_plane)


func _draw() -> void:
	var xf := Transform2D(heading, Vector2.ZERO)
	_draw_route()
	if phase == 1:
		_draw_sectors()
	var tex := "e_fortress" if Enemy.etex("e_fortress") != null else "e_transport"
	if not draw_enemy_sprite(tex, LEN, Color(0.75, 0.72, 0.68)):
		draw_colored_polygon(xf * PackedVector2Array([Vector2(110, 0), Vector2(70, 18), Vector2(10, 20), Vector2(-5, 130), Vector2(-35, 130), Vector2(-40, 20),
			Vector2(-100, 14), Vector2(-120, 50), Vector2(-135, 50), Vector2(-128, 0), Vector2(-135, -50), Vector2(-120, -50), Vector2(-100, -14),
			Vector2(-40, -20), Vector2(-35, -130), Vector2(-5, -130), Vector2(10, -20), Vector2(70, -18)]), body_color(Color(0.42, 0.44, 0.4)))
	# уязвимые точки текущей фазы — мигающие кольца с полоской прочности
	var want := _want()
	for pt in points:
		var at := _ring_at(pt, xf)
		if float(pt["hp"]) <= 0.0:
			draw_circle(at, 9.0, Color(0.15, 0.12, 0.1, 0.9))   # выбитая точка — копоть
			continue
		var active: bool = pt["kind"] == want
		var col := Color(1.0, 0.85, 0.3) if pt["kind"] == "turret" else Color(1.0, 0.45, 0.2)
		var a := 0.55 + 0.4 * absf(sin(_t * 5.0)) if active else 0.3
		draw_arc(at, 16.0, 0.0, TAU, 24, Color(col, a), 3.0 if active else 1.5)
		if active:
			draw_arc(at, 22.0, -PI / 2.0, -PI / 2.0 + TAU * float(pt["hp"]) / float(pt["max"]), 24, Color(0.4, 1.0, 0.5, 0.9), 3.0)
	# открытый люк — пульсирующее кольцо «×3»
	if phase == 2 and hatches_open:
		var bl := xf * BAY
		draw_arc(bl, BAY_R, 0.0, TAU, 32, Color(1.0, 0.45, 0.15, 0.6 + 0.35 * absf(sin(_t * 8.0))), 4.0)
		draw_string(Hud.ui_font(), bl + Vector2(-20, -BAY_R - 6.0), "×3", HORIZONTAL_ALIGNMENT_CENTER, 40, 18, Color(1.0, 0.7, 0.3))
	for z in _zones:
		var zl := to_local(z["p"] as Vector2)
		var k := clampf(1.0 - float(z["t"]) / 1.4, 0.0, 1.0)
		draw_circle(zl, ZONE_R * k, Color(1.0, 0.15, 0.1, 0.22))
		draw_arc(zl, ZONE_R, 0.0, TAU, 40, Color(1.0, 0.2, 0.1, 0.5 + 0.4 * absf(sin(_t * 12.0))), 3.0)
	if _lock > 0.0:
		var p := Main.I.player
		if p != null and p.hp > 0.0:
			var la := 0.35 + 0.5 * absf(sin(_t * 30.0))
			var target := to_local(p.global_position)
			draw_line(Vector2.ZERO, target, Color(1, 0.15, 0.1, la), 3.0)
			draw_arc(target, 30.0, 0.0, TAU, 32, Color(1, 0.15, 0.1, la), 3.0)
	draw_string(Hud.ui_font(), Vector2(-120, -radius - 24.0), Loc.out("«Крепость»"), HORIZONTAL_ALIGNMENT_CENTER, 240, 18, Color(1, 0.85, 0.7))


## Маршрут к базе — пунктир по земле, база — круг с подписью
func _draw_route() -> void:
	if base_pos == Vector2.INF or phase >= 3:
		return
	var bl := to_local(base_pos)
	draw_dashed_line(Vector2.ZERO, to_local(_wp), Color(1.0, 0.35, 0.25, 0.45), 4.0, 40.0)
	draw_circle(bl, BASE_R, Color(0.3, 0.7, 1.0, 0.12))
	draw_arc(bl, BASE_R, 0.0, TAU, 64, Color(0.4, 0.8, 1.0, 0.7), 4.0)
	draw_string(Hud.ui_font(), bl + Vector2(-120, 8), Loc.out("НАША БАЗА"), HORIZONTAL_ALIGNMENT_CENTER, 240, 28, Color(0.6, 0.9, 1.0))


## Сектора турелей (фаза 1): красный веер там, где бьёт хоть одна живая турель; мёртвые зоны — зелёные
func _draw_sectors() -> void:
	var steps := 72
	for i in steps:
		var a0 := -PI + TAU * i / steps
		var a1 := a0 + TAU / steps
		var mid := (a0 + a1) / 2.0
		var col := Color(0, 0, 0, 0)
		if _in_dead(mid):
			col = Color(0.3, 1.0, 0.45, 0.07)
		else:
			var n := 0
			for pt in points:
				if pt["kind"] == "turret" and float(pt["hp"]) > 0.0 and absf(wrapf(mid - float(pt["sec"][0]), -PI, PI)) <= float(pt["sec"][1]):
					n += 1
			if n > 0:
				col = Color(1.0, 0.2, 0.15, 0.012 + 0.012 * n)
		if col.a <= 0.0:
			continue
		var r0 := 220.0
		var r1 := SECTOR_R
		draw_colored_polygon(PackedVector2Array([Vector2.from_angle(heading + a0) * r0, Vector2.from_angle(heading + a0) * r1,
			Vector2.from_angle(heading + a1) * r1, Vector2.from_angle(heading + a1) * r0]), col)
		# край сектора — тонкая дуга, чтобы граница читалась без сплошной заливки
		draw_line(Vector2.from_angle(heading + a0) * r1, Vector2.from_angle(heading + a1) * r1, Color(col, minf(1.0, col.a * 6.0)), 3.0)
