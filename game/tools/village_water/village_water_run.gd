extends Node
## Рабочая часть village_water.gd (грузится после автозагрузок Tuning/Settings)

var t: Terrain3D


func _ready() -> void:
	var r := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--r="):
			r = int(a.substr(4))
	var bg: Background = load("res://scripts/background.gd").new()
	add_child(bg)
	await get_tree().process_frame
	t = load("res://scripts/terrain3d.gd").new()
	add_child(t)
	t.setup(500.0, StandardMaterial3D.new(), bg)
	var props := BiomeProps.new(t)
	t.props = props
	var t0 := Time.get_ticks_msec()
	var villages := []
	for cx in range(-r, r):
		for cz in range(-r, r):
			var o := t._obj(Vector2i(cx, cz))
			if not o.is_empty() and o["name"] == "o_village":
				villages.append([Vector2i(cx, cz), o])
	var before := {}
	var after := {}
	var lots_wet := 0
	var lots_left := 0
	var ms_max := 0.0
	var ms_core := 0.0
	var lots_all := 0
	var with_stream := 0
	AdobeBuild.edge_log_on = true
	for vo in villages:
		var o: Dictionary = vo[1]
		var vr := int(o.get("var", 0))
		var water := t.village_water(o)
		if not (water["segs"] as Array).is_empty():
			with_stream += 1
		AdobeBuild.village(vr)   # общая сетка в игре собирается заранее (prewarm)
		var tb := Time.get_ticks_usec()
		AdobeBuild.village_core(vr, water)
		ms_core = maxf(ms_core, (Time.get_ticks_usec() - tb) / 1000.0)
		tb = Time.get_ticks_usec()
		AdobeBuild.village_edge(vr, water)
		ms_max = maxf(ms_max, (Time.get_ticks_usec() - tb) / 1000.0)
		var was := {}
		for k in ["garden", "trench", "pit", "post"]:
			was[k] = int(before.get(k, [0, 0])[0])
		for pass_i in 2:
			AdobeBuild.edge_log = []
			AdobeBuild.village_edge(vr, {} if pass_i == 0 else water)
			_count(o, AdobeBuild.edge_log, before if pass_i == 0 else after)
		var line := ""
		for k in was:
			var d := int(before.get(k, [0, 0])[0]) - int(was[k])
			if d > 0:
				line += " %s %d" % [k, d]
		if line != "":   # где было на воде «до» — для кадров (visual_bench --only=village_water --vat=x,z)
			print("WATER   кишлак (%d, %d) var %d rot %.2f, до на воде:%s" % [roundi(o["pos"].x), roundi(o["pos"].y), vr, float(o["rot"]), line])
		for l in (AdobeBuild._vcache["village%d_edge" % vr][0] as Array):
			lots_all += 1
			if _box_wet(o, l[0], l[1], l[2]):
				lots_wet += 1
				if not AdobeBuild._wet_box(water, l[0], l[1], l[2], 0.004):
					lots_left += 1   # village_core его не вырезал
	AdobeBuild.edge_log_on = false
	# сады, юрты и тополя BiomeProps и сцены боёв у кишлаков (клетки ±2 от каждого)
	var keys := {}
	for vo in villages:
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				keys[(vo[0] as Vector2i) + Vector2i(dx, dz)] = true
	var trees := [0, 0]
	var scn := [0, 0]
	for key: Vector2i in keys:
		var put := props.plan(key, t._ctx(key))
		for kind in ["orchard", "yurt", "poplar"]:
			for tr: Transform3D in put.get(kind, []):
				trees[1] += 1
				if t.in_water(Vector2(tr.origin.x, tr.origin.z), tr.basis.x.length() * 0.45 - 2.0):
					trees[0] += 1
		for it in t.scenes(key):
			scn[1] += 1
			if t.in_water(it["p"], (0.0 if it["k"] in ["scorch", "crater"] else float(it["r"])) - 2.0):
				scn[0] += 1
	print("WATER кишлаков %d (с ручьём рядом %d), клеток %d×%d, %d мс" % [villages.size(), with_stream, 2 * r, 2 * r, Time.get_ticks_msec() - t0])
	var bad := 0
	for k in ["garden", "trench", "pit", "post"]:
		var b: Array = before.get(k, [0, 0])
		var a: Array = after.get(k, [0, 0])
		bad += int(a[0])
		print("WATER %s до: на воде %d из %d   после: на воде %d из %d" % [k, b[0], b[1], a[0], a[1]])
	print("WATER дворы и дома до: на воде %d из %d   после: на воде %d" % [lots_wet, lots_all, lots_left])
	print("WATER сборка кишлака на месте: застройка до %.1f мс, окраина до %.1f мс" % [ms_core, ms_max])
	print("WATER сады/юрты/тополя BiomeProps на воде: %d из %d" % trees)
	print("WATER сцены боёв на воде: %d из %d" % scn)
	print("WATER итог: ", "ok" if bad == 0 and lots_left == 0 and trees[0] == 0 and scn[0] == 0 else "FAIL")
	get_tree().quit()


## Точка окраины (старые единицы, оси сетки посёлка) → мир
func _w(o: Dictionary, u: Vector2) -> Vector2:
	return (o["pos"] as Vector2) + (u * float(o["size"]) * AdobeBuild.V_UNIT).rotated(float(o["rot"]))


## Прямоугольник (старые единицы) задевает охранную зону реки или ручья: сетка точек с шагом ~5 px
func _box_wet(o: Dictionary, c: Vector2, h: Vector2, yaw: float) -> bool:
	var ax := Vector2.from_angle(yaw)
	var az := ax.orthogonal()
	var nx := maxi(1, ceili(h.x / 0.008))
	var nz := maxi(1, ceili(h.y / 0.008))
	for i in nx + 1:
		for j in nz + 1:
			var u := c + ax * h.x * (2.0 * i / nx - 1.0) + az * h.y * (2.0 * j / nz - 1.0)
			if t.in_water(_w(o, u)):
				return true
	return false


func _count(o: Dictionary, entries: Array, out: Dictionary) -> void:
	for e in entries:
		var k: String = e[0]
		var wet := false
		match k:
			"garden":
				wet = _box_wet(o, e[1], e[2], e[3])
			"trench":   # бруствер по a–b и окоп за ним (к центру посёлка)
				var a: Vector2 = e[1]
				var b: Vector2 = e[2]
				var inward := -((a + b) * 0.5).normalized() * 0.022
				var hh := Vector2(a.distance_to(b) * 0.5, 0.01)
				wet = _box_wet(o, (a + b) * 0.5, hh, (b - a).angle()) or _box_wet(o, (a + b) * 0.5 + inward, hh, (b - a).angle())
			"pit":
				wet = _box_wet(o, e[1], Vector2(0.055, 0.055), 0.0)
			"post":
				var c: Vector2 = e[1]
				wet = _box_wet(o, c, Vector2(0.07, 0.025), c.angle() + PI * 0.5)
		var cnt: Array = out.get(k, [0, 0])
		cnt[0] += 1 if wet else 0
		cnt[1] += 1
		out[k] = cnt
