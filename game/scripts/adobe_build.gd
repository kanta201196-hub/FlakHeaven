class_name AdobeBuild
extends RefCounted
## 3.4-t1 (п. 25): крепость и кишлак в объёме. Раньше это были картинки, нарисованные в перспективе и
## выдавленные «рельефом» по яркости — при наклонной камере они выглядели плоской наклейкой.
## Теперь — глинобитные постройки из коробок: стены с зубцами, угловые башни, ворота, дворы,
## дома с плоскими крышами и парапетом (как в горных кишлаках). Координаты — доли размера объекта:
## площадка 1 × 1 с центром в нуле, Y — вверх. Игра масштабирует под размер в пикселях мира.

const WALL := Color(0.93, 0.85, 0.72)
const ROOF := Color(1.0, 0.94, 0.82)
const DARK := Color(0.62, 0.55, 0.47)    # проёмы, бойницы, двери

static var _cache := {}
static var _mat: StandardMaterial3D


## Материал: глина из набора земли CC0 в трёх проекциях — без развёртки, без растяжения на стенах
static func material() -> StandardMaterial3D:
	if _mat != null:
		return _mat
	_mat = StandardMaterial3D.new()
	var p := "res://art/ground/pbr/clay_albedo.jpg"
	if ResourceLoader.exists(p):
		_mat.albedo_texture = load(p)
	_mat.uv1_triplanar = true
	_mat.uv1_world_triplanar = true
	_mat.uv1_scale = Vector3.ONE / 160.0
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color(1.0, 0.95, 0.88)
	_mat.roughness = 0.95
	_mat.metallic = 0.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


static func fort() -> ArrayMesh:
	if _cache.has("fort"):
		return _cache["fort"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.42      # от центра до внешней грани стены
	var t := 0.05         # толщина стены
	var h := 0.11         # высота стены
	var tw := 0.17        # сторона башни
	var th := 0.17        # высота башни
	var gate := 0.09      # ширина ворот (в южной стене)
	# стены: север, юг (с воротами), запад, восток
	_wall(st, Vector2(-half + tw * 0.5, -half), Vector2(half - tw * 0.5, -half), t, h)
	_wall(st, Vector2(-half + tw * 0.5, half), Vector2(-gate * 0.5 - 0.03, half), t, h)
	_wall(st, Vector2(gate * 0.5 + 0.03, half), Vector2(half - tw * 0.5, half), t, h)
	_wall(st, Vector2(-half, -half + tw * 0.5), Vector2(-half, half - tw * 0.5), t, h)
	_wall(st, Vector2(half, -half + tw * 0.5), Vector2(half, half - tw * 0.5), t, h)
	# угловые башни с зубцами и бойницами
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector2(sx * (half - tw * 0.4), sz * (half - tw * 0.4))
			_tower(st, c, tw, th)
	# надвратные башенки и проём ворот
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * (gate * 0.5 + 0.035), 0.0, half), Vector3(0.07, h * 1.3, t * 1.6), WALL, ROOF)
		_merlons(st, Vector3(sx * (gate * 0.5 + 0.035), h * 1.3, half), Vector2(0.07, t * 1.6), 0.018)
	_box(st, Vector3(0.0, 0.0, half + t * 0.3), Vector3(gate, h * 0.62, t * 0.4), DARK, DARK)
	# постройки вдоль стен изнутри и цитадель
	var inner := half - t * 0.5
	var d := 0.11
	_box(st, Vector3(0.0, 0.0, -inner + d * 0.5), Vector3(0.5, 0.07, d), WALL, ROOF)
	_box(st, Vector3(-inner + d * 0.5, 0.0, -0.05), Vector3(d, 0.06, 0.38), WALL, ROOF)
	_box(st, Vector3(inner - d * 0.5, 0.0, 0.08), Vector3(d, 0.065, 0.3), WALL, ROOF)
	_box(st, Vector3(-0.17, 0.0, inner - d * 0.5), Vector3(0.18, 0.055, d), WALL, ROOF)
	_box(st, Vector3(0.18, 0.0, inner - d * 0.5), Vector3(0.16, 0.06, d), WALL, ROOF)
	_box(st, Vector3(0.06, 0.0, -0.02), Vector3(0.2, 0.13, 0.17), WALL, ROOF)       # цитадель
	_parapet(st, Vector3(0.06, 0.13, -0.02), Vector2(0.2, 0.17), 0.012, 0.016)
	_box(st, Vector3(0.12, 0.0, -0.06), Vector3(0.07, 0.17, 0.07), WALL, ROOF)      # дозорная вышка цитадели
	_merlons(st, Vector3(0.12, 0.17, -0.06), Vector2(0.07, 0.07), 0.016)
	st.generate_normals()
	var m := st.commit()
	_cache["fort"] = m
	return m


## Тест 3.5-s4 (п. 19): кишлак — разрушенный городок, а не пара квадратных построек. Плотные кварталы
## вдоль двух улиц (главная и поперечная), в каждом участке — дом в одном из состояний:
## целый (плоская крыша с парапетом), без крыши (стены с рваным верхом, внутри завал), обрушенный
## (обломки стен и груда глины), остов двух-трёхэтажного дома (стены с проёмами окон), пустырь с завалом.
## Пятна копоти на крышах и стенах. variant — номер раскладки (0…3), соседние города не одинаковые.
const BURNT := Color(0.3, 0.27, 0.24)   # копоть
const RUBBLE := Color(0.82, 0.74, 0.62)  # битая глина


static func village(variant: int) -> ArrayMesh:
	var key := "village%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R := 0.47
	var street := 0.055
	var cross_x := rng.randf_range(-0.15, 0.15)    # поперечная улица
	var main_z := rng.randf_range(-0.06, 0.06)      # главная улица
	var lot := 0.105
	var n := int(ceilf(R * 2.0 / lot))
	for i in n:
		for j in n:
			var c := Vector2(-R + (i + 0.5) * lot, -R + (j + 0.5) * lot) + Vector2(rng.randf_range(-0.01, 0.01), rng.randf_range(-0.01, 0.01))
			# город — неровное пятно, а не квадрат: к краю участки реже
			var d := c.length() / R
			if d > 1.0 or rng.randf() < smoothstep(0.7, 1.0, d) * 0.6:
				continue
			var sz := Vector2(lot - rng.randf_range(0.012, 0.03), lot - rng.randf_range(0.012, 0.03))
			# участок не на улице: дом сдвигается от улицы и сужается, совсем на улице — не ставится
			for ax in 2:
				var line := main_z if ax == 0 else cross_x
				var v := c.y if ax == 0 else c.x
				var gap := absf(v - line) - street * 0.5
				var half := (sz.y if ax == 0 else sz.x) * 0.5
				if gap < half:
					var keep := half + gap   # от улицы до дальнего края участка
					if keep < 0.03:
						sz = Vector2.ZERO
						break
					var sgn := 1.0 if v >= line else -1.0
					var far := v + sgn * half
					var near := line + sgn * street * 0.5
					if ax == 0:
						sz.y = absf(far - near)
						c.y = (far + near) * 0.5
					else:
						sz.x = absf(far - near)
						c.x = (far + near) * 0.5
			if sz == Vector2.ZERO:
				continue
			var roll := rng.randf()
			if roll < 0.3:
				_house(st, c, sz, rng.randf_range(0.04, 0.065), rng)
			elif roll < 0.62:
				_roofless(st, c, sz, rng.randf_range(0.04, 0.07), rng)
			elif roll < 0.8:
				_collapsed(st, c, sz, rng)
			elif roll < 0.92:
				_shell(st, c, sz * 1.05, rng.randf_range(0.1, 0.14), rng)
			else:
				_rubble(st, c, sz.x * 0.45, 5, rng)
	# завалы и воронки на улицах
	for k in 6:
		var along := rng.randf_range(-R * 0.8, R * 0.8)
		var c := Vector2(along, main_z) if k % 2 == 0 else Vector2(cross_x, along)
		_rubble(st, c, 0.025, 3, rng)
	st.generate_normals()
	var m := st.commit()
	_cache[key] = m
	return m


## Целый дом: плоская крыша с парапетом, дверь; иногда пятно копоти
static func _house(st: SurfaceTool, c: Vector2, s: Vector2, h: float, rng: RandomNumberGenerator) -> void:
	_box(st, Vector3(c.x, 0.0, c.y), Vector3(s.x, h, s.y), WALL, ROOF)
	_parapet(st, Vector3(c.x, h, c.y), s, 0.006, 0.009)
	_box(st, Vector3(c.x, 0.0, c.y + s.y * 0.5 + 0.001), Vector3(0.014, h * 0.6, 0.003), DARK, DARK)
	if rng.randf() < 0.4:
		_soot(st, Vector3(c.x + rng.randf_range(-0.3, 0.3) * s.x, h + 0.001, c.y + rng.randf_range(-0.3, 0.3) * s.y), s * 0.45, rng)


## Дом без крыши: стены разной высоты с рваным верхом, внутри тёмный пол и завал
static func _roofless(st: SurfaceTool, c: Vector2, s: Vector2, h: float, rng: RandomNumberGenerator) -> void:
	var t := 0.008
	var x0 := c.x - s.x * 0.5
	var x1 := c.x + s.x * 0.5
	var z0 := c.y - s.y * 0.5
	var z1 := c.y + s.y * 0.5
	for side in [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x1, z1)], [Vector2(x1, z1), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0, z0)]]:
		_broken_wall(st, side[0], side[1], t, h, rng)
	_box(st, Vector3(c.x, 0.0, c.y), Vector3(s.x - t * 2.0, 0.004, s.y - t * 2.0), BURNT, BURNT)   # пол в копоти
	_rubble(st, c + Vector2(rng.randf_range(-0.2, 0.2) * s.x, rng.randf_range(-0.2, 0.2) * s.y), s.x * 0.3, 3, rng)


## Обрушенный дом: обломки стен по углам и груда глины
static func _collapsed(st: SurfaceTool, c: Vector2, s: Vector2, rng: RandomNumberGenerator) -> void:
	var t := 0.009
	var a := Vector2(c.x - s.x * 0.5, c.y - s.y * 0.5)
	_broken_wall(st, a, a + Vector2(s.x * rng.randf_range(0.4, 0.8), 0.0), t, rng.randf_range(0.025, 0.045), rng)
	_broken_wall(st, a, a + Vector2(0.0, s.y * rng.randf_range(0.4, 0.8)), t, rng.randf_range(0.025, 0.045), rng)
	_rubble(st, c, s.x * 0.42, 7, rng)


## Остов многоэтажного дома: высокие стены с проёмами окон, без крыши, рваный верх
static func _shell(st: SurfaceTool, c: Vector2, s: Vector2, h: float, rng: RandomNumberGenerator) -> void:
	var t := 0.01
	var x0 := c.x - s.x * 0.5
	var x1 := c.x + s.x * 0.5
	var z0 := c.y - s.y * 0.5
	var z1 := c.y + s.y * 0.5
	var sides := [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x1, z1)], [Vector2(x1, z1), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0, z0)]]
	var down := rng.randi() % 4   # одна стена обрушена почти до земли
	for i in 4:
		var a: Vector2 = sides[i][0]
		var b: Vector2 = sides[i][1]
		_broken_wall(st, a, b, t, h * (0.3 if i == down else 1.0), rng)
		if i == down:
			continue
		# окна: тёмные проёмы в два-три ряда на внешней грани
		var dir := (b - a).normalized()
		var out := Vector2(dir.y, -dir.x)
		var len := a.distance_to(b)
		for fl in [0.3, 0.55, 0.8]:
			for k in 3:
				var f := (k + 0.5) / 3.0
				var p := a + dir * len * f + out * (t * 0.5 + 0.001)
				var ws := Vector3(0.016, 0.018, 0.003) if absf(dir.x) > 0.5 else Vector3(0.003, 0.018, 0.016)
				_box(st, Vector3(p.x, h * fl * 0.85, p.y), ws, DARK, DARK)
	# перекрытие обрушилось внутрь — завал до половины высоты
	_rubble(st, c, s.x * 0.35, 6, rng, 0.04)
	_soot(st, Vector3(x0 - 0.001, h * 0.5, c.y), Vector2(0.003, s.y * 0.5), rng)


## Стена с рваным верхом: 3–5 кусков разной высоты, иногда пролом
static func _broken_wall(st: SurfaceTool, a: Vector2, b: Vector2, t: float, h: float, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(3, 5)
	var horiz := absf(b.x - a.x) >= absf(b.y - a.y)
	for k in n:
		if rng.randf() < 0.15:
			continue   # пролом
		var p0 := a.lerp(b, float(k) / n)
		var p1 := a.lerp(b, float(k + 1) / n)
		var mid := (p0 + p1) * 0.5
		var len := p0.distance_to(p1) + (t if k == n - 1 else 0.0)
		var hh := h * rng.randf_range(0.35, 1.0)
		_box(st, Vector3(mid.x, 0.0, mid.y), Vector3(len, hh, t) if horiz else Vector3(t, hh, len), WALL, RUBBLE)


## Груда обломков: низкие коробки вразброс, сверху битая глина и копоть
static func _rubble(st: SurfaceTool, c: Vector2, r: float, n: int, rng: RandomNumberGenerator, top := 0.022) -> void:
	for k in n:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf())
		var sx := rng.randf_range(0.01, 0.028)
		var sz := rng.randf_range(0.01, 0.028)
		var col := BURNT if rng.randf() < 0.3 else RUBBLE
		_box(st, Vector3(p.x, 0.0, p.y), Vector3(sx, top * rng.randf_range(0.3, 1.0), sz), col, col)


## Пятно копоти: тонкая тёмная пластина (на крыше — горизонтальная, на стене — size.x ≈ 0)
static func _soot(st: SurfaceTool, c: Vector3, s: Vector2, rng: RandomNumberGenerator) -> void:
	_box(st, c, Vector3(maxf(s.x, 0.003), 0.002 if s.x > 0.004 else s.y * 0.6, s.y), BURNT, BURNT)


## Стена от a до b (план XZ), с зубцами по верху
static func _wall(st: SurfaceTool, a: Vector2, b: Vector2, t: float, h: float, merlons := true) -> void:
	var c := (a + b) * 0.5
	var horiz := absf(b.x - a.x) >= absf(b.y - a.y)
	var len := a.distance_to(b) + t
	var size := Vector3(len, h, t) if horiz else Vector3(t, h, len)
	_box(st, Vector3(c.x, 0.0, c.y), size, WALL, ROOF)
	if merlons:
		_merlons(st, Vector3(c.x, h, c.y), Vector2(size.x, size.z), t * 0.45)


static func _tower(st: SurfaceTool, c: Vector2, w: float, h: float) -> void:
	_box(st, Vector3(c.x, 0.0, c.y), Vector3(w, h, w), WALL, ROOF)
	_merlons(st, Vector3(c.x, h, c.y), Vector2(w, w), w * 0.13)
	# бойницы — тёмные щели на четырёх гранях
	for dir: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var p := Vector3(c.x, h * 0.55, c.y) + dir * (w * 0.5 + 0.001)
		var s := Vector3(0.004, w * 0.22, w * 0.07) if dir.x != 0.0 else Vector3(w * 0.07, w * 0.22, 0.004)
		_box(st, p, s, DARK, DARK)


## Зубцы по краю прямоугольника size (X, Z) на высоте c.y
static func _merlons(st: SurfaceTool, c: Vector3, size: Vector2, m: float) -> void:
	var gap := m * 1.1
	for edge in 4:
		var horiz := edge < 2
		var len := size.x if horiz else size.y
		var n := maxi(2, int(len / (m + gap)))
		for i in n:
			var f := (float(i) + 0.5) / n - 0.5
			var p: Vector3 = Vector3(c.x + f * len, c.y, c.z + (size.y * 0.5 - m * 0.5) * (1.0 if edge == 0 else -1.0)) if horiz \
				else Vector3(c.x + (size.x * 0.5 - m * 0.5) * (1.0 if edge == 2 else -1.0), c.y, c.z + f * len)
			_box(st, p, Vector3(m, m, m), WALL, ROOF)


## Невысокий бортик по краю плоской крыши
static func _parapet(st: SurfaceTool, c: Vector3, size: Vector2, t: float, h: float) -> void:
	_box(st, c + Vector3(0, 0, -size.y * 0.5 + t * 0.5), Vector3(size.x, h, t), WALL, ROOF)
	_box(st, c + Vector3(0, 0, size.y * 0.5 - t * 0.5), Vector3(size.x, h, t), WALL, ROOF)
	_box(st, c + Vector3(-size.x * 0.5 + t * 0.5, 0, 0), Vector3(t, h, size.y - 2.0 * t), WALL, ROOF)
	_box(st, c + Vector3(size.x * 0.5 - t * 0.5, 0, 0), Vector3(t, h, size.y - 2.0 * t), WALL, ROOF)


## Коробка: низ в c.y, центр по X/Z в c; без нижней грани. side — цвет стен, top — крыши
static func _box(st: SurfaceTool, c: Vector3, s: Vector3, side: Color, top: Color) -> void:
	var x0 := c.x - s.x * 0.5
	var x1 := c.x + s.x * 0.5
	var z0 := c.z - s.z * 0.5
	var z1 := c.z + s.z * 0.5
	var y0 := c.y
	var y1 := c.y + s.y
	_quad(st, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), top)   # крыша
	_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), side)  # +Z
	_quad(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), side)  # −Z
	_quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), side)  # +X
	_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), side)  # −X


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_smooth_group(-1)   # плоские грани: у каждой коробки острые рёбра
	for v in [a, c, b, a, d, c]:
		st.set_color(col)
		st.add_vertex(v)
