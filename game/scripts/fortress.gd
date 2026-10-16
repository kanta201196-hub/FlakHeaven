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


func setup_fortress(total: float) -> void:
	setup("fortress", total * HULL_SHARE)
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
	if phase >= 3:
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
	Main.I.sfx.play("shield_break", -4.0, 0.8)
	Main.I.tele.add("fortress_points")
	if pt["kind"] == "engine":
		Main.I.show_banner("%s сбит — «Крепость» теряет скорость" % String(pt["name"]).capitalize(), 2.5)
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
	if phase >= 2:
		_hatches(delta, p, to, d)
	if phase >= 3:
		_flare_cd -= delta
		if _flare_cd <= 0.0 and pop_flares(420.0, 260.0, 0.6) > 0:
			_flare_cd = 5.0
		_ring_cd -= delta
		if _ring_cd <= 0.0 and d < 900.0:
			_ring_cd = 3.2
			var off := randf() * TAU
			for i in 16:
				var dir := Vector2.from_angle(off + TAU * i / 16.0)
				Main.I.projectiles.spawn_enemy_bullet(global_position + dir * radius, dir * 270.0, kind(), true)
			Main.I.sfx.play("enemy_fire", -8.0, 0.4)
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


func _die() -> void:
	Main.I.show_banner("«Крепость» сбита!", 4.0)
	for i in 4:
		Main.I.fx.explosion(global_position + Vector2(randf_range(-90, 90), randf_range(-60, 60)), 50.0)
	super()


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
		var at := xf * (pt["off"] as Vector2)
		if float(pt["hp"]) <= 0.0:
			draw_circle(at, 9.0, Color(0.15, 0.12, 0.1, 0.9))   # выбитая точка — копоть
			continue
		var active: bool = pt["kind"] == want
		var col := Color(1.0, 0.85, 0.3) if pt["kind"] == "turret" else Color(1.0, 0.45, 0.2)
		var a := 0.55 + 0.4 * absf(sin(_t * 5.0)) if active else 0.3
		draw_arc(at, 16.0, 0.0, TAU, 24, Color(col, a), 3.0 if active else 1.5)
		if active:
			draw_arc(at, 22.0, -PI / 2.0, -PI / 2.0 + TAU * float(pt["hp"]) / float(pt["max"]), 24, Color(0.4, 1.0, 0.5, 0.9), 3.0)
	if _lock > 0.0:
		var p := Main.I.player
		if p != null and p.hp > 0.0:
			var la := 0.35 + 0.5 * absf(sin(_t * 30.0))
			var target := to_local(p.global_position)
			draw_line(Vector2.ZERO, target, Color(1, 0.15, 0.1, la), 3.0)
			draw_arc(target, 30.0, 0.0, TAU, 32, Color(1, 0.15, 0.1, la), 3.0)
	draw_string(Hud.ui_font(), Vector2(-120, -radius - 24.0), "«Крепость»", HORIZONTAL_ALIGNMENT_CENTER, 240, 18, Color(1, 0.85, 0.7))
