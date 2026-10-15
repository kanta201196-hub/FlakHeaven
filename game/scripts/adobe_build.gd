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


## Кишлак: дома-коробки с плоскими крышами и дувалами (глинобитными оградами дворов).
## variant — номер раскладки (0…3), чтобы соседние кишлаки не были одинаковыми.
static func village(variant: int) -> ArrayMesh:
	var key := "village%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed: Array[Rect2] = []
	# дворы по кругу и в середине: в каждом 1–3 дома у ограды
	var yards := 0
	var tries := 0
	while yards < 14 and tries < 160:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.33
		var c := Vector2(cos(a), sin(a)) * r
		var ys := Vector2(rng.randf_range(0.13, 0.2), rng.randf_range(0.12, 0.18))
		var yr := Rect2(c - ys * 0.5, ys)
		var bad := false
		for q in placed:
			if q.grow(0.012).intersects(yr):
				bad = true
				break
		if bad or yr.position.x < -0.46 or yr.position.y < -0.46 or yr.end.x > 0.46 or yr.end.y > 0.46:
			continue
		placed.append(yr)
		yards += 1
		_yard(st, yr, rng)
	st.generate_normals()
	var m := st.commit()
	_cache[key] = m
	return m


static func _yard(st: SurfaceTool, yr: Rect2, rng: RandomNumberGenerator) -> void:
	var wt := 0.012
	var wh := 0.022
	var p0 := yr.position
	var p1 := yr.end
	# дувал с проходом на одной из сторон
	var gap_side := rng.randi() % 4
	var sides := [[Vector2(p0.x, p0.y), Vector2(p1.x, p0.y)], [Vector2(p1.x, p0.y), Vector2(p1.x, p1.y)],
		[Vector2(p1.x, p1.y), Vector2(p0.x, p1.y)], [Vector2(p0.x, p1.y), Vector2(p0.x, p0.y)]]
	for i in 4:
		var a: Vector2 = sides[i][0]
		var b: Vector2 = sides[i][1]
		if i == gap_side:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_wall(st, a, mid - dir * 0.018, wt, wh, false)
			_wall(st, mid + dir * 0.018, b, wt, wh, false)
		else:
			_wall(st, a, b, wt, wh, false)
	# дома у дальних от прохода сторон
	var n := rng.randi_range(1, 3)
	for k in n:
		var side := (gap_side + 2 + k) % 4
		var horiz := side % 2 == 0
		var len := (yr.size.x if horiz else yr.size.y) * rng.randf_range(0.45, 0.85)
		var dep := rng.randf_range(0.06, 0.09)
		var hh := rng.randf_range(0.045, 0.075)
		var c := Vector3.ZERO
		match side:
			0: c = Vector3(yr.get_center().x + rng.randf_range(-0.2, 0.2) * (yr.size.x - len), 0.0, p0.y + dep * 0.5)
			1: c = Vector3(p1.x - dep * 0.5, 0.0, yr.get_center().y + rng.randf_range(-0.2, 0.2) * (yr.size.y - len))
			2: c = Vector3(yr.get_center().x + rng.randf_range(-0.2, 0.2) * (yr.size.x - len), 0.0, p1.y - dep * 0.5)
			3: c = Vector3(p0.x + dep * 0.5, 0.0, yr.get_center().y + rng.randf_range(-0.2, 0.2) * (yr.size.y - len))
		var size := Vector3(len, hh, dep) if horiz else Vector3(dep, hh, len)
		_box(st, c, size, WALL, ROOF)
		_parapet(st, c + Vector3(0, hh, 0), Vector2(size.x, size.z), 0.006, 0.009)
		# дверь во двор
		var inward := Vector3(0, 0, 1) if side == 0 else (Vector3(-1, 0, 0) if side == 1 else (Vector3(0, 0, -1) if side == 2 else Vector3(1, 0, 0)))
		_box(st, c + inward * (dep * 0.5 + 0.001), Vector3(0.012 if horiz else 0.003, hh * 0.6, 0.003 if horiz else 0.012), DARK, DARK)


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
