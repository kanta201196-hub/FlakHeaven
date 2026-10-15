class_name ReliefMesh
## 3.0: объёмные модели из спрайтов. Силуэт картинки выдавливается в «рельеф»:
## толщина растёт от края к середине (фюзеляж толще крыла), сверху — сама картинка,
## снизу — тёмное зеркало. Модели появятся из Hunyuan3D/Blender — тогда этот генератор
## останется запасным путём для любых новых картинок.
##
## Координаты меша — в пикселях исходной текстуры, центр в середине, нос по +X (как спрайт),
## Y — вверх (толщина), Z — вниз по картинке.

static var _cache := {}


## height_px — максимальная толщина в пикселях текстуры; grid — сетка по длинной стороне;
## lum_k — доля рельефа от яркости (0 — только силуэт; для скал/зданий 0.3–0.5);
## profile — степень профиля толщины (меньше — «пухлее»), bottom — нижняя половина (для самолётов).
static func build(tex: Texture2D, height_px: float, grid := 72, lum_k := 0.0, profile := 0.55, bottom := true) -> ArrayMesh:
	var key := "%s|%.1f|%d|%.2f|%.2f|%s" % [tex.resource_path if tex.resource_path != "" else str(tex.get_rid()), height_px, grid, lum_k, profile, bottom]
	if _cache.has(key):
		return _cache[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var tw := img.get_width()
	var th := img.get_height()
	var gw := grid if tw >= th else maxi(8, int(round(grid * float(tw) / th)))
	var gh := grid if th > tw else maxi(8, int(round(grid * float(th) / tw)))
	var small := img.duplicate() as Image
	small.resize(gw, gh, Image.INTERPOLATE_BILINEAR)
	# маска и расстояние до края (шахматная метрика, два прохода)
	var n := gw * gh
	var dist := PackedFloat32Array()
	dist.resize(n)
	var lum := PackedFloat32Array()
	lum.resize(n)
	var BIG := 1e6
	for y in gh:
		for x in gw:
			var c := small.get_pixel(x, y)
			dist[y * gw + x] = BIG if c.a > 0.4 else 0.0
			lum[y * gw + x] = (c.r + c.g + c.b) / 3.0
	for y in gh:
		for x in gw:
			var i := y * gw + x
			if dist[i] == 0.0:
				continue
			var d := BIG
			if x > 0: d = minf(d, dist[i - 1] + 1.0)
			else: d = 1.0
			if y > 0: d = minf(d, dist[i - gw] + 1.0)
			else: d = minf(d, 1.0)
			if x > 0 and y > 0: d = minf(d, dist[i - gw - 1] + 1.41)
			if x < gw - 1 and y > 0: d = minf(d, dist[i - gw + 1] + 1.41)
			dist[i] = minf(dist[i], d)
	for y in range(gh - 1, -1, -1):
		for x in range(gw - 1, -1, -1):
			var i2 := y * gw + x
			if dist[i2] == 0.0:
				continue
			var d2 := dist[i2]
			if x < gw - 1: d2 = minf(d2, dist[i2 + 1] + 1.0)
			else: d2 = minf(d2, 1.0)
			if y < gh - 1: d2 = minf(d2, dist[i2 + gw] + 1.0)
			else: d2 = minf(d2, 1.0)
			if x < gw - 1 and y < gh - 1: d2 = minf(d2, dist[i2 + gw + 1] + 1.41)
			if x > 0 and y < gh - 1: d2 = minf(d2, dist[i2 + gw - 1] + 1.41)
			dist[i2] = d2
	var dmax := 1.0
	for v in dist:
		dmax = maxf(dmax, v)
	# высота ячейки
	var hc := PackedFloat32Array()
	hc.resize(n)
	for i3 in n:
		if dist[i3] <= 0.0:
			hc[i3] = -1.0
			continue
		var k := pow(clampf(dist[i3] / dmax, 0.0, 1.0), profile)
		hc[i3] = height_px * (k * (1.0 - lum_k) + k * lum_k * (0.4 + 1.2 * lum[i3]))
	# высота в узлах сетки (углы ячеек) — среднее соседних ячеек; узел на краю силуэта — 0
	var vh := PackedFloat32Array()
	vh.resize((gw + 1) * (gh + 1))
	for y in gh + 1:
		for x in gw + 1:
			var s := 0.0
			var cnt := 0
			var empty := false
			for dy in [-1, 0]:
				for dx in [-1, 0]:
					var cx: int = x + dx
					var cy: int = y + dy
					if cx < 0 or cy < 0 or cx >= gw or cy >= gh or hc[cy * gw + cx] < 0.0:
						empty = true
					else:
						s += hc[cy * gw + cx]
						cnt += 1
			vh[y * (gw + 1) + x] = 0.0 if (empty or cnt == 0) else s / cnt
	# ячейки для отрисовки: в маске + кольцо вокруг (края обрежет альфа текстуры)
	var draw := PackedByteArray()
	draw.resize(n)
	for y in gh:
		for x in gw:
			var on := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var cx2: int = x + dx
					var cy2: int = y + dy
					if cx2 >= 0 and cy2 >= 0 and cx2 < gw and cy2 < gh and hc[cy2 * gw + cx2] >= 0.0:
						on = true
			draw[y * gw + x] = 1 if on else 0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := float(tw) / gw
	var sz := float(th) / gh
	var ox := tw / 2.0
	var oz := th / 2.0
	var sides := [1.0, -0.45] if bottom else [1.0]
	for side in sides:
		var col := Color(1, 1, 1) if side > 0.0 else Color(0.45, 0.45, 0.48)
		for y in gh:
			for x in gw:
				if draw[y * gw + x] == 0:
					continue
				var corners := [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 1, y + 1), Vector2i(x, y + 1)]
				var vs: Array = []
				for c2 in corners:
					var hh: float = vh[c2.y * (gw + 1) + c2.x] * side
					vs.append([Vector3(c2.x * sx - ox, hh, c2.y * sz - oz), Vector2(float(c2.x) / gw, float(c2.y) / gh)])
				var order := [0, 1, 2, 0, 2, 3] if side > 0.0 else [0, 2, 1, 0, 3, 2]
				for oi in order:
					st.set_color(col)
					st.set_uv(vs[oi][1])
					st.add_vertex(vs[oi][0])
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static var _mats := {}


## Материал для модели: текстура сверху, отсечение по альфе, металл/шероховатость;
## tint — множитель цвета (объекты биома: в их картинках уже «нарисован» свет)
static func material(tex: Texture2D, metal := 0.35, rough := 0.5, tint := Color.WHITE) -> StandardMaterial3D:
	var key := str(tex.get_rid()) + "|%.2f|%.2f|%s" % [metal, rough, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_mats[key] = m
	return m
