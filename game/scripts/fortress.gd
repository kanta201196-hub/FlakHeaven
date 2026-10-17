class_name Fortress
extends Boss
## 3.5: босс «Крепость» (разбор каталога 16.10, выбор владельца) — третья волна асов (15:00) вместо пары асов.
## Тяжёлый бомбардировщик-носитель: медленно кружит вокруг игрока, не таранит. Бой идёт по фазам:
##   1. «Турели» — 4 турели (две на крыльях, верхняя, кормовая) бьют очередями. Корпус прикрыт:
##      урон идёт в ближайшую к игроку живую турель, в корпус — только 10%.
##   2. «Люки и двигатели» — открываются люки: залпы ракет после захвата, вызов звена перехватчиков.
##      Урон идёт в ближайший двигатель; каждый сбитый двигатель — минус 25% скорости, дымный след.
##   3. «Корпус» — корпус открыт, урон полный; Крепость горит, отстреливает ловушки и бьёт кольцами крупных пуль.
## Пока не пройдены фазы 1–2, корпус не опускается ниже 35%.
## Правка 3.5-s4: попадания видны (искры и цифры на точке), сбитая точка —
## надпись «Турель сбита: N из 4». По общей прочности — приёмы: 66% — кассетный сброс (красные круги на земле
## рвутся через 1,4 с), 33% — «последний рубеж» (спираль крупных пуль). Бой не короче 45 с (предел урона).
## Модель: пока вид сверху транспортника (art/enemies/e_transport.png); появится e_fortress.png — возьмётся она.

const LEN := 270.0               # длина корпуса на экране, пикс.
const BASE_SPEED := 150.0
const HULL_SHARE := 0.4          # доли общей прочности: корпус / 4 турели / 2 двигателя
const TURRET_SHARE := 0.075
const ENGINE_SHARE := 0.15
const PASS := 0.1                # доля урона в корпус, пока он прикрыт

var phase := 1
var points: Array = []           # [{name, node, kind, off (в осях самолёта: x — вперёд), hp, max, cd, shots, st}]
## Для 3D-модели (узлы GLB: turret_1…turret_4, engine_l, engine_r, hatch_l/r, bay_l/r, core):
## выбитые части — имя узла → true; люки открыты с фазы 2, корпус раскрыт в фазе 3
var parts_down := {}
var hatches_open := false
var hull_open := false
var _missile_cd := 4.0
var _escort_called := false
var _ring_cd := 3.0
const MIN_FIGHT := 70.0          # правка 3.5-s4: вся «Крепость» — не быстрее 70 с при любой сборке (в логе «Кита» — ~40 с)
var total_max := 0.0
var _budget := -1.0
var _budget_t := 0.0
var _stage := 0                  # приёмы по прочности: 1 — кассеты (66%), 2 — спираль (33%)
var _cluster_cd := 2.0
var _zones: Array = []           # [{p, t}] кассетный сброс: метка на земле → взрыв
var _spiral_cd := 3.0
var _spiral_t := 0.0
var _spiral_a := 0.0
var _spiral_shot := 0.0
var _hit_fx := 0.0


func setup_fortress(total: float) -> void:
	setup("fortress", total * HULL_SHARE)
	total_max = total
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
		_pt("турель левого крыла", "turret_1", "turret", Vector2(-6, -78) * k, total * TURRET_SHARE),
		_pt("турель правого крыла", "turret_2", "turret", Vector2(-6, 78) * k, total * TURRET_SHARE),
		_pt("верхняя турель", "turret_3", "turret", Vector2(48, 0) * k, total * TURRET_SHARE),
		_pt("кормовая турель", "turret_4", "turret", Vector2(-112, 0) * k, total * TURRET_SHARE),
		_pt("левый двигатель", "engine_l", "engine", Vector2(14, -44) * k, total * ENGINE_SHARE),
		_pt("правый двигатель", "engine_r", "engine", Vector2(14, 44) * k, total * ENGINE_SHARE),
	]
	_set_title()


func _pt(n: String, node: String, kd: String, off: Vector2, h: float) -> Dictionary:
	return {"name": n, "node": node, "kind": kd, "off": off, "hp": h, "max": h, "cd": randf_range(0.8, 2.0), "shots": 0, "st": 0.0}


func kind() -> String:
	return "асы"


func _set_title() -> void:
	match phase:
		1: title = "«Крепость» — сбейте турели: %d из 4" % (4 - _alive("turret"))
		2: title = "«Крепость» — сбейте двигатели: %d из 2" % (2 - _alive("engine"))
		_: title = "«Крепость» — корпус открыт, добивайте!"


func _alive(kd: String) -> int:
	var n := 0
	for pt in points:
		if pt["kind"] == kd and float(pt["hp"]) > 0.0:
			n += 1
	return n


func _world(pt: Dictionary) -> Vector2:
	return global_position + (pt["off"] as Vector2).rotated(heading)


## Урон идёт в ближайшую к игроку уязвимую точку текущей фазы; в корпус — 10% (не ниже 35%)
func absorb(dmg: float) -> float:
	dmg = _cap_total(dmg)
	if dmg <= 0.0:
		return 0.0
	if phase >= 3:
		_confirm(global_position, dmg, Color(1, 0.9, 0.6))
		return dmg
	var want := "turret" if phase == 1 else "engine"
	var p := Main.I.player
	var from := p.global_position if p != null else global_position
	var best: Dictionary = {}
	var best_d := INF
	for pt in points:
		if pt["kind"] != want or float(pt["hp"]) <= 0.0:
			continue
		var d := _world(pt).distance_to(from)
		if d < best_d:
			best_d = d
			best = pt
	if best.is_empty():
		return dmg * PASS
	_confirm(_world(best), dmg * (1.0 - PASS), Color(1.0, 0.85, 0.35))
	best["hp"] = float(best["hp"]) - dmg * (1.0 - PASS)
	Main.I.add_stat("dealt", "уязвимые точки «Крепости»", dmg * (1.0 - PASS))
	if float(best["hp"]) <= 0.0:
		_point_down(best)
	return minf(dmg * PASS, maxf(0.0, hp - max_hp * 0.35))


func _point_down(pt: Dictionary) -> void:
	var at := _world(pt)
	parts_down[pt["node"]] = true
	Main.I.fx.explosion(at, 34.0)
	Main.I.add_shake(5.0)
	Main.I.sfx.play("fortress_part", -4.0, 0.8)
	Main.I.tele.add("fortress_points")
	if pt["kind"] == "engine":
		Main.I.show_banner("Двигатель сбит: %d из 2 — «Крепость» теряет скорость" % (2 - _alive("engine")), 2.5)
	else:
		Main.I.show_banner("Турель сбита: %d из 4" % (4 - _alive("turret")), 2.0)
	Main.I.fx.text(at + Vector2(0, -40), "СБИТА!" if pt["kind"] == "turret" else "СБИТ!", Color(1.0, 0.8, 0.4))
	Main.I.fx.ring(at, 70.0, Color(1.0, 0.6, 0.25))
	if phase == 1 and _alive("turret") == 0:
		phase = 2
		hatches_open = true
		Main.I.show_banner("Турели сбиты! Люки открыты — бейте по двигателям", 3.5)
		Main.I.tele.add("fortress_phase2_s", Main.I.run_time - _born)
		_missile_cd = 1.5
	elif phase == 2 and _alive("engine") == 0:
		phase = 3
		hull_open = true
		Main.I.show_banner("Двигатели горят! Корпус открыт — добивайте «Крепость»", 3.5)
		Main.I.tele.add("fortress_phase3_s", Main.I.run_time - _born)
	_set_title()


func behave(delta: float) -> void:
	_t += delta
	_hit_fx = maxf(0.0, _hit_fx - delta)
	var p := Main.I.player
	var spd := BASE_SPEED * (1.0 - 0.25 * (2 - _alive("engine")))
	if p == null or p.hp <= 0.0:
		position += Vector2.from_angle(heading) * spd * delta
		return
	var to := p.global_position - global_position
	var d := to.length()
	# тяжёлая машина: широкий круг вокруг игрока на 500–750 пикс., разворачивается медленно
	var desired := to.angle() + PI / 2.0 * _orbit
	if d > 750.0:
		desired = to.angle() + 0.5 * _orbit
	elif d < 450.0:
		desired = to.angle() + PI * 0.75 * _orbit
	heading = rotate_toward(heading, desired, deg_to_rad(24.0) * delta)
	position += Vector2.from_angle(heading) * _speed(spd, d, p) * delta
	_turrets(delta, p)
	_stages(delta, p)
	if phase >= 2:
		_hatches(delta, p, to, d)
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


## Турели: очередь из 3 пуль ближе 750 пикс.; кормовая бьёт только в задний сектор, остальные — по кругу
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
		if float(pt["cd"]) > 0.0 or to.length() > 750.0:
			continue
		if pt["name"] == "кормовая турель" and absf(wrapf(to.angle() - heading, -PI, PI)) < PI * 0.55:
			continue
		pt["shots"] = 3
		pt["cd"] = randf_range(1.8, 2.6)


## Люки (фаза 2+): залп из 4 ракет после захвата; один раз — звено из 3 перехватчиков
func _hatches(delta: float, p: Player, to: Vector2, d: float) -> void:
	if not _escort_called:
		_escort_called = true
		for i in 3:
			var f := Interceptor.new()
			f.position = global_position + Vector2.from_angle(heading + PI / 2.0 * (i - 1)) * 120.0
			f.heading = heading
			Main.I.world.add_child(f)
			f.apply_hp_mult(Tuning.g("enemy_hp_mult") * Spawner.hp_ramp(Main.I.run_time))
	if _lock > 0.0:
		_lock -= delta
		if _lock <= 0.0:
			for i in 4:
				Main.I.projectiles.spawn_missile(global_position, to.normalized().rotated((i - 1.5) * 0.4))
			Main.I.sfx.play("missile_enemy", -4.0, 0.7)
			_missile_cd = 5.5 if phase == 2 else 4.5
		return
	_missile_cd -= delta
	if _missile_cd <= 0.0 and d < 1000.0:
		_lock = 1.1
		Main.I.sfx.play("lock", -4.0, 0.7)


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


## Приёмы по общей прочности: 66% — кассетный сброс, 33% — «последний рубеж»
func _stages(delta: float, p: Player) -> void:
	var f := total_frac()
	if _stage < 1 and f <= 0.66:
		_stage = 1
		_cluster_cd = 1.0
		Main.I.show_banner("«Крепость»: кассетный сброс! Уходите из красных кругов", 3.5)
		Main.I.sfx.play("lock", -2.0, 0.6)
	if _stage < 2 and f <= 0.33:
		_stage = 2
		_spiral_cd = 0.5
		Main.I.show_banner("«Крепость»: последний рубеж — спираль из пушек!", 3.5)
		Main.I.sfx.play("boss", -2.0, 0.8)
		Main.I.add_shake(8.0)
	if _stage >= 1:
		_cluster_cd -= delta
		if _cluster_cd <= 0.0:
			_cluster_cd = 7.0 if _stage == 1 else 9.0
			# 5 меток: на игрока с упреждением и вокруг — стоять нельзя, уйти можно
			var c := p.global_position + p.velocity * 0.8
			_zones.append({"p": c, "t": 1.4})
			for i in 4:
				_zones.append({"p": c + Vector2.from_angle(randf() * TAU) * randf_range(120.0, 220.0), "t": 1.4 + 0.15 * (i + 1)})
			Main.I.sfx.play("bomb_drop", -6.0, 0.7)
	for i in range(_zones.size() - 1, -1, -1):
		var z: Dictionary = _zones[i]
		z["t"] = float(z["t"]) - delta
		if float(z["t"]) <= 0.0:
			var zp: Vector2 = z["p"]
			Main.I.fx.explosion(zp, 30.0, false)
			if p.global_position.distance_to(zp) < ZONE_R + p.radius:
				p.damage(18.0, "бомбы", kind())
			_zones.remove_at(i)
	if _stage >= 2:
		if _spiral_t > 0.0:
			_spiral_t -= delta
			_spiral_shot -= delta
			if _spiral_shot <= 0.0:
				_spiral_shot = 0.09
				_spiral_a += 0.47
				for k in 3:
					var dir := Vector2.from_angle(_spiral_a + TAU * k / 3.0)
					Main.I.projectiles.spawn_enemy_bullet(global_position + dir * radius, dir * 240.0, kind(), true, 1.0, k > 0)
			return
		_spiral_cd -= delta
		if _spiral_cd <= 0.0:
			_spiral_cd = 9.0
			_spiral_t = 3.0


const ZONE_R := 90.0


func _die() -> void:
	Main.I.show_banner("«Крепость» сбита!", 4.0)
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
	var u: Dictionary = r._units.get(get_instance_id(), {})
	var parts: Dictionary = u.get("fparts", {})
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
	var tex := "e_fortress" if Enemy.etex("e_fortress") != null else "e_transport"
	if not draw_enemy_sprite(tex, LEN, Color(0.75, 0.72, 0.68)):
		draw_colored_polygon(xf * PackedVector2Array([Vector2(110, 0), Vector2(70, 18), Vector2(10, 20), Vector2(-5, 130), Vector2(-35, 130), Vector2(-40, 20),
			Vector2(-100, 14), Vector2(-120, 50), Vector2(-135, 50), Vector2(-128, 0), Vector2(-135, -50), Vector2(-120, -50), Vector2(-100, -14),
			Vector2(-40, -20), Vector2(-35, -130), Vector2(-5, -130), Vector2(10, -20), Vector2(70, -18)]), body_color(Color(0.42, 0.44, 0.4)))
	# уязвимые точки текущей фазы — мигающие кольца с полоской прочности
	var want := "turret" if phase == 1 else ("engine" if phase == 2 else "")
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
	for z in _zones:
		var zl := to_local(z["p"] as Vector2)
		var k := clampf(1.0 - float(z["t"]) / 1.4, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(zl, ZONE_R * k, Color(1.0, 0.15, 0.1, 0.22))
		draw_arc(zl, ZONE_R, 0.0, TAU, 40, Color(1.0, 0.2, 0.1, 0.5 + 0.4 * absf(sin(_t * 12.0))), 3.0)
	if _lock > 0.0:
		var p := Main.I.player
		if p != null and p.hp > 0.0:
			var la := 0.35 + 0.5 * absf(sin(_t * 30.0))
			var target := to_local(p.global_position)
			draw_line(Vector2.ZERO, target, Color(1, 0.15, 0.1, la), 3.0)
			draw_arc(target, 30.0, 0.0, TAU, 32, Color(1, 0.15, 0.1, la), 3.0)
	draw_string(Hud.ui_font(), Vector2(-120, -radius - 24.0), "«Крепость»", HORIZONTAL_ALIGNMENT_CENTER, 240, 18, Color(1, 0.85, 0.7))
