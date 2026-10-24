class_name PlayerDraw
extends RefCounted
## Отрисовка самолёта: спрайт, 3D-дополнения, оверлеи и круги дальности.
## Вынесено из player.gd без изменения поведения: состояние (переменные) живёт в Player, здесь только код.

var pl: Player


func _init(p: Player) -> void:
	pl = p


func _draw() -> void:
	var w := 1.0 - 0.45 * absf(pl.bank)
	if pl.roll_t > 0.0:
		var p := 1.0 - pl.roll_t / pl.roll_time()
		w = maxf(0.15, absf(cos(p * TAU)))
	var xf := Transform2D(pl.heading, Vector2.ZERO).scaled(Vector2(pl.size, pl.size))
	if Tuning.g("sprites") >= 1 and PlaneArt.plane_tex(pl.cls_id, pl.plane_lvl) != null:
		if Render3D.enabled:
			_draw_3d_extras(w)
		else:
			_draw_sprite(w)
		_draw_overlays()
		return
	var shape: PackedVector2Array
	var ww := maxf(w, 0.35) # не даём крылу «схлопнуться» в бочке — иначе полигон самопересекается
	match pl.cls_id:
		"attacker":
			shape = PackedVector2Array([Vector2(20, 0), Vector2(4, 4), Vector2(-2, 17 * ww), Vector2(-10, 17 * ww), Vector2(-8, 4),
				Vector2(-16, 8 * ww), Vector2(-16, -8 * ww), Vector2(-8, -4), Vector2(-10, -17 * ww), Vector2(-2, -17 * ww), Vector2(4, -4)])
		"bomber":
			shape = PackedVector2Array([Vector2(18, 0), Vector2(6, 4), Vector2(-4, 20 * ww), Vector2(-10, 20 * ww), Vector2(-8, 4),
				Vector2(-16, 4), Vector2(-16, -4), Vector2(-8, -4), Vector2(-10, -20 * ww), Vector2(-4, -20 * ww), Vector2(6, -4)])
		_:
			shape = PackedVector2Array([Vector2(20, 0), Vector2(-14, 15 * w), Vector2(-8, 0), Vector2(-14, -15 * w)])
	var body := xf * shape
	var col: Color = pl.cls["color"]
	if pl.roll_t > 0.0:
		col = Color(0.85, 0.97, 1.0)
	elif pl.invuln > 0.0 and int(pl._blink * 20.0) % 2 == 0:
		col.a = 0.35
	if pl.ab_t > 0.0:
		var fl := xf * PackedVector2Array([Vector2(-9, 4), Vector2(-30 - randf() * 10.0, 0), Vector2(-9, -4)])
		pl.draw_colored_polygon(fl, Color(1.0, 0.6, 0.2, 0.9))
	pl.draw_colored_polygon(body, col)
	_draw_overlays()


func _sprite_scale() -> float:
	var s := PlaneArt.shape_info(pl.cls_id, pl.plane_lvl)
	if s.is_empty():
		return 1.0
	# длина на экране: истребитель plane_len, остальные × size; ур. 2 чуть крупнее по пропорции картинок
	var base_len := Tuning.g("plane_len") * pl.size
	var s1 := PlaneArt.shape_info(pl.cls_id, 1)
	var k_lvl := float(s["w"]) / float(s1["w"]) if not s1.is_empty() else 1.0
	return base_len * k_lvl / float(s["w"])


func _draw_sprite(w: float) -> void:
	var tex := PlaneArt.plane_tex(pl.cls_id, pl.plane_lvl)
	var k := _sprite_scale()
	var sc := Vector2(k, k * w)
	var col := Color(1, 1, 1, 1)
	if pl.invuln > 0.0 and pl.roll_t <= 0.0 and int(pl._blink * 20.0) % 2 == 0:
		col.a = 0.4
	var half := tex.get_size() / 2.0
	# тень на земле: сдвиг вниз-вправо, тёмная и полупрозрачная
	pl.draw_set_transform(Vector2(10.0, 16.0) * pl.size, pl.heading, sc * 0.92)
	pl.draw_texture(tex, -half, Color(0, 0, 0, 0.28 * col.a))
	# форсаж — пламя за соплами
	if pl.ab_t > 0.0:
		var s := PlaneArt.shape_info(pl.cls_id, pl.plane_lvl)
		var tx: float = s.get("tail", -half.x)
		pl.draw_set_transform(Vector2.ZERO, pl.heading, sc)
		var fl := PackedVector2Array([Vector2(tx + 3, 3.0 / maxf(w, 0.3)), Vector2(tx - 14.0 - randf() * 8.0, 0), Vector2(tx + 3, -3.0 / maxf(w, 0.3))])
		pl.draw_colored_polygon(fl, Color(1.0, 0.6, 0.2, 0.9))
	var base := Transform2D(pl.heading, sc, 0.0, Vector2.ZERO)
	pl.draw_set_transform_matrix(base)
	pl.draw_texture(tex, -half, col)
	# подвесы: видны на точках подвеса, на перезарядке — полупрозрачные
	for gi in pl.groups.size():
		var g: Hardpoint = pl.groups[gi]
		if g.is_empty():
			continue
		var pts := PlaneArt.slot_points(pl.cls_id, pl.plane_lvl, gi, g)
		var a := 1.0
		if Weapons.leaves_pylon(g.weapon) and g.cd > 0.3:
			a = 0.4
		var wk := 1.0 / maxf(k, 0.01) # оружие в экранных пикселях, независимо от масштаба картинки
		for pt in pts:
			PlaneArt.draw_weapon(pl, g.weapon, pt, wk, a * col.a, base)
	pl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if pl.roll_t > 0.0:
		pl.draw_set_transform(Vector2.ZERO, pl.heading, sc)
		pl.draw_texture(tex, -half, Color(0.8, 0.95, 1.0, 0.35))
		pl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if pl._upgrade_flash > 0.0:
		pl.draw_circle(Vector2.ZERO, 40.0 * pl.size * (1.6 - pl._upgrade_flash), Color(1.0, 0.95, 0.6, 0.35 * pl._upgrade_flash))


## 3.0: модель в 3D — здесь только пламя форсажа и вспышка модернизации
func _draw_3d_extras(w: float) -> void:
	var tex := PlaneArt.plane_tex(pl.cls_id, pl.plane_lvl)
	var k := _sprite_scale()
	if pl.ab_t > 0.0:
		var s := PlaneArt.shape_info(pl.cls_id, pl.plane_lvl)
		var tx: float = s.get("tail", -tex.get_width() / 2.0)
		pl.draw_set_transform(Vector2.ZERO, pl.heading, Vector2(k, k * w))
		var fl := PackedVector2Array([Vector2(tx + 3, 3.0 / maxf(w, 0.3)), Vector2(tx - 14.0 - randf() * 8.0, 0), Vector2(tx + 3, -3.0 / maxf(w, 0.3))])
		pl.draw_colored_polygon(fl, Color(1.0, 0.6, 0.2, 0.9))
		pl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if pl._upgrade_flash > 0.0:
		pl.draw_circle(Vector2.ZERO, 40.0 * pl.size * (1.6 - pl._upgrade_flash), Color(1.0, 0.95, 0.6, 0.35 * pl._upgrade_flash))


func _draw_overlays() -> void:
	if pl.on_tail():
		var tp := pl.to_local(pl.tail_target.global_position)
		pl.draw_arc(tp, pl.tail_target.radius + 12.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.3, 0.9), 2.0)
		pl.draw_line(Vector2.from_angle(pl.heading) * 30.0, tp, Color(1.0, 0.9, 0.3, 0.25), 1.0)
	if pl.combat_t > 0.0 and pl.lock_ok():
		var lp := pl.to_local(pl.turn_lock.global_position)
		var lr := pl.turn_lock.radius + 16.0
		pl.draw_arc(lp, lr, 0.0, TAU, 36, Color(0.6, 0.9, 1.0, 0.9), 3.0)
		for i in 4:
			var a := i * PI / 2.0 + pl._blink * 2.0
			pl.draw_line(lp + Vector2.from_angle(a) * (lr + 4.0), lp + Vector2.from_angle(a) * (lr + 14.0), Color(0.6, 0.9, 1.0, 0.9), 2.0)
	if pl.combat_t > 0.0:
		pl.draw_arc(Vector2.ZERO, 24.0 * pl.size, 0.0, TAU, 32, Color(0.6, 0.9, 1.0, 0.5 + 0.3 * sin(pl._blink * 20.0)), 2.0)
	if pl.shield_t > 0.0:
		pl.draw_arc(Vector2.ZERO, 30.0 * pl.size, 0.0, TAU, 40, Color(0.5, 1.0, 0.6, 0.8), 4.0)
		pl.draw_circle(Vector2.ZERO, 30.0 * pl.size, Color(0.5, 1.0, 0.6, 0.12))
	# 3.1: дальность курсового и ракет В-В — пунктирные круги (можно выключить в настройках)
	if Tuning.g("range_rings") > 0.5:
		_dashed_circle(pl.gun_range(), Color(1.0, 0.95, 0.75, 0.26))
		for g in pl.groups:
			var h: Hardpoint = g
			if h.weapon == "emp" and h.cd <= 0.25:   # тест 3.5-s7: заряд готов — видна зона, где он сработает
				_dashed_circle(h.range_px(), Color(0.55, 0.8, 1.0, 0.3), 2.0, 48)
			if h.weapon == "aam" or (h.weapon == "turret" and h.slots > 0):
				_dashed_circle(h.range_px(), Color(1.0, 0.5, 0.4, 0.2) if h.weapon == "aam" else Color(0.4, 0.9, 0.85, 0.16), 2.0, 72 if h.weapon == "aam" else 56)
	# тест 3.5-s7: прицел бомб без 3D (в 3D его рисует земля по рельефу — render3d._sync_ground_zones)
	if not (Render3D.I != null and Render3D.I.ground_zones_on()):
		for g in pl.groups:
			var hb: Hardpoint = g
			if hb.aiming:
				var col := Color(1.0, 0.68, 0.28, 0.85) if hb.cd <= 0.0 else Color(0.8, 0.82, 0.8, 0.5)
				for z in hb.aim_zones(pl):
					var a: Vector2 = pl.to_local(z[0])
					var b: Vector2 = pl.to_local(z[1])
					pl.draw_arc(a, z[2], 0.0, TAU, 48, col, 2.0)
					if a != b:
						pl.draw_arc(b, z[2], 0.0, TAU, 48, col, 2.0)
	# Радиус подбора опыта — еле заметный круг
	pl.draw_arc(Vector2.ZERO, pl.pickup_radius(), 0.0, TAU, 64, Color(0.5, 1.0, 0.6, 0.06), 1.0)
	if pl.manual_mode:
		var f := Vector2.from_angle(pl.heading)
		pl.draw_line(f * 26.0 * pl.size, f * 90.0, Color(1, 1, 1, 0.25), 1.0)
		var frac := pl.manual_bonus / maxf(Tuning.g("manual_max"), 0.01)
		var rr := 30.0 * pl.size + 8.0
		pl.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 3.0)
		var tc := Color(0.4, 1.0, 0.5).lerp(Color(1.0, 0.85, 0.3), clampf(frac * 2.0, 0.0, 1.0))
		if frac > 0.5:
			tc = tc.lerp(Color(1.0, 0.3, 0.2), (frac - 0.5) * 2.0)
		pl.draw_arc(Vector2.ZERO, rr, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, tc, 4.0)


func _dashed_circle(r: float, col: Color, width := 2.0, dashes := 64) -> void:
	var step := TAU / dashes
	for i in dashes:
		var a0 := i * step
		pl.draw_arc(Vector2.ZERO, r, a0, a0 + step * 0.5, 4, col, width)
