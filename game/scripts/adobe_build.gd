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
const WATER := Color(0.3, 0.4, 0.42)     # вода в пруду оазиса

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


## Тест 3.5-s4 (второй список, п. 16–17): у поселения неровный край, как у настоящего: контур — сумма
## синусов по углу (у каждой раскладки свой), плотная застройка в середине, к краю — реже, дальше —
## огороды за дувалами и отдельные дома вдоль дорог. Тот же контур задаёт пятно утоптанной земли и
## полей на рельефе (ground_mask → terrain3d.gd) и площадку под поселением — всё совпадает.
## Множитель радиуса контура по углу (0.7 … 1.2); variant — номер раскладки
static func outline(variant: int, ang: float) -> float:
	var v := float(variant)
	var o := 1.0 + 0.15 * sin(2.0 * ang + 1.3 + v * 2.1) + 0.1 * sin(3.0 * ang + 0.7 + v * 1.7) \
		+ 0.06 * sin(5.0 * ang + 2.9 + v * 0.9) + 0.035 * sin(8.0 * ang + 0.4 + v * 2.6)
	return clampf(o, 0.7, 1.2)


## Псевдослучайное 0…1 от раскладки (без генератора — одинаково в любом потоке)
static func _vr(variant: int, k: int) -> float:
	var x := sin(float(variant) * 12.9898 + float(k) * 78.233 + 1.0) * 43758.5453
	return x - floorf(x)


## Кишлак строится в «старых» единицах (1 = 640 px, как было до увеличения), потом сжимается под размер
const V_UNIT := 640.0 / 900.0   # размер o_village — 900 (background.gd)
const V_EDGE := 0.6             # радиус края застройки, старые единицы (× outline)


## Правка Kanta 18.10.2026 (L-01): посёлок на 30–50 домов вдоль тропинок, а не сетка улиц.
## Главная тропа идёт по +x объекта — fix_object разворачивает посёлок так, чтобы +x смотрел к реке:
## тропа выходит к дороге (за краем застройки) и дальше к воде. От центра — 3–4 боковые тропы.
## Тропа — ломаная в старых единицах; одинакова для раскладки в любом потоке (без генератора)
const PATH_W := 0.024        # ширина тропы, старые единицы (~17 px мира)
const PATH_OUT := 1.02       # главная тропа: до дороги и к воде (центр посёлка — за дорогой, footprint ≈ 0,64)
static var _paths := {}


static func village_paths(variant: int) -> Array:
	if _paths.has(variant):
		return _paths[variant]
	var out := []
	# главная: к реке, лёгкий изгиб
	var main := PackedVector2Array()
	for k in 11:
		var t := float(k) / 10.0
		main.append(Vector2(t * PATH_OUT, sin(t * 4.1 + variant * 1.7) * 0.06 * t))
	out.append(main)
	var n := 3 + int(_vr(variant, 5) * 2.0)
	for i in n:
		var ang := PI * 0.45 + (TAU - PI * 0.9) * (i + 0.3 + _vr(variant, 10 + i) * 0.4) / n
		var e := V_EDGE * outline(variant, ang) * 1.08
		var pl := PackedVector2Array()
		for k in 9:
			var t := float(k) / 8.0
			var side := Vector2.from_angle(ang + PI * 0.5)
			pl.append(Vector2.from_angle(ang) * t * e + side * sin(t * 5.0 + i * 2.3 + variant) * 0.04 * t)
		out.append(pl)
	# кольцевая тропа между боковыми на половине радиуса
	var ring := PackedVector2Array()
	var a0 := _vr(variant, 30) * TAU
	for k in 13:
		var ang := a0 + PI * 1.1 * float(k) / 12.0
		ring.append(Vector2.from_angle(ang) * V_EDGE * 0.48 * outline(variant, ang))
	out.append(ring)
	_paths[variant] = out
	return out


## Расстояние от точки u (старые единицы) до ближайшей тропы посёлка
static func path_dist(variant: int, u: Vector2) -> float:
	var best := INF
	for pl: PackedVector2Array in village_paths(variant):
		for k in pl.size() - 1:
			var a := pl[k]
			var ab := pl[k + 1] - a
			var t := clampf((u - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			best = minf(best, u.distance_to(a + ab * t))
	return best


## Маска поселения на земле в точке l (смещение от центра / размер объекта, в осях объекта):
## x — утоптанная земля (дворы, улицы, тропы), y — зелень (огороды, сады, поля). 0…1, мягкие края
static func ground_mask(name: String, variant: int, l: Vector2) -> Vector2:
	var ang := l.angle()
	var o := outline(variant, ang)
	match name:
		"o_village":
			var u := l / V_UNIT
			var rad := u.length()
			var e := V_EDGE * o
			var tr := 1.0 - smoothstep(e * 0.82, e * 1.12, rad)
			# тропы (L-01): между домами и за край — главная к дороге и к воде, боковые тают в степи
			var dl := path_dist(variant, u)
			var reach := PATH_OUT if u.x > 0.0 and absf(u.y) < 0.12 else e * 1.3
			tr = maxf(tr, (1.0 - smoothstep(0.012, 0.03, dl)) * (1.0 - smoothstep(reach * 0.92, reach, rad)) * 0.9)
			# огороды и сады за домами: кольцо у края, только в части секторов — пятнами, не кругом
			var sect := smoothstep(-0.15, 0.45, sin(2.0 * ang + 0.5 + variant * 1.3) + 0.6 * sin(5.0 * ang + variant * 0.7))
			var gr := smoothstep(e * 0.7, e * 0.92, rad) * (1.0 - smoothstep(e * 1.2, e * 1.42, rad)) * sect
			return Vector2(tr, gr)
		"o_oasis":
			var rad := l.length()
			var e := 0.36 * o
			var core := l - Vector2(0.06, -0.05)
			var tr := 1.0 - smoothstep(0.07, 0.14, core.length() / o)
			var gr := 1.0 - smoothstep(e * 0.85, e * 1.15, rad)
			return Vector2(tr, gr)
		"o_fort":
			var box := maxf(absf(l.x), absf(l.y))
			var e := 0.5 + 0.12 * o
			var tr := 1.0 - smoothstep(e * 0.95, e * 1.3, box)
			var sect := smoothstep(0.1, 0.6, sin(3.0 * ang + variant * 1.9))
			var gr := smoothstep(0.55, 0.65, box) * (1.0 - smoothstep(0.78, 0.9, box)) * sect * 0.8
			return Vector2(tr, gr)
	return Vector2.ZERO


## Точка l (доля размера, в осях объекта) с запасом m — вне построек, огородов и садов поселения
static func outside(name: String, variant: int, l: Vector2, m: float) -> bool:
	var o := outline(variant, l.angle())
	match name:
		"o_village":
			return l.length() - m > V_EDGE * o * 1.3 * V_UNIT
		"o_oasis":
			return l.length() - m > 0.36 * o * 1.15
		"o_fort":
			return maxf(absf(l.x), absf(l.y)) - m > 0.56
	return l.length() - m > 0.5


## Радиус, в который укладываются постройки и поля поселения (доля размера) — для отвода от реки
static func footprint(name: String) -> float:
	match name:
		"o_village":
			return 1.25 * V_EDGE * 1.2 * V_UNIT   # ≈ 0.64: отдельные дома на окраине
		"o_oasis":
			return 0.5
		"o_fort":
			return 0.62
	return 0.45


static func village(variant: int) -> ArrayMesh:
	var key := "village%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paths := village_paths(variant)
	var lots := []   # [центр, полуразмер] — дома не наползают друг на друга и на тропы
	var want := rng.randi_range(34, 48)
	# дома вдоль троп: по обе стороны, чаще у центра
	for pl: PackedVector2Array in paths:
		for k in pl.size() - 1:
			var a := pl[k]
			var b := pl[k + 1]
			var dir := (b - a).normalized()
			var nrm := dir.orthogonal()
			var t := 0.0
			while t < a.distance_to(b):
				var c0 := a + dir * t
				t += rng.randf_range(0.075, 0.1)
				for sgn: float in [-1.0, 1.0]:
					if lots.size() >= want or rng.randf() < 0.22:
						continue
					var sz := Vector2(rng.randf_range(0.05, 0.072), rng.randf_range(0.045, 0.062))
					var c: Vector2 = c0 + nrm * sgn * (PATH_W * 0.5 + sz.y * 0.5 + rng.randf_range(0.006, 0.02))
					_put_house(st, c, sz, lots, rng, variant)
	# двор-кластер у центра, если вдоль троп набралось мало
	for i in 60:
		if lots.size() >= want:
			break
		var c := Vector2.from_angle(rng.randf() * TAU) * V_EDGE * 0.7 * sqrt(rng.randf())
		_put_house(st, c, Vector2(rng.randf_range(0.05, 0.075), rng.randf_range(0.045, 0.065)), lots, rng, variant)
	# тропы — утоптанная полоса чуть над землёй (вне застройки их рисует пятно на рельефе: ground_mask)
	for pl: PackedVector2Array in paths:
		for k in pl.size() - 1:
			var a := pl[k]
			var b := pl[k + 1]
			# за краем площадки земля уходит вниз к реке — тропа там приподнята чуть выше
			_strip(st, a, b, PATH_W * (1.0 if a.length() < V_EDGE else 0.8), PATH, 0.0165 if a.length() < V_EDGE else 0.021)   # меш утоплен на 1 % размера (render3d)
	# огороды за дувалами — у края, между тропами
	for i in rng.randi_range(5, 8):
		var ang := rng.randf() * TAU
		var c := Vector2.from_angle(ang) * V_EDGE * outline(variant, ang) * rng.randf_range(0.95, 1.15)
		if path_dist(variant, c) > 0.08:
			_garden(st, c, Vector2(0.105, 0.105) * rng.randf_range(0.9, 1.25), rng)
	_defence(st, variant, rng)
	var m := _scaled(st, V_UNIT)
	_cache[key] = m
	return m


## Правка Kanta 18.10.2026 (L-08, схема Kanta): перед посёлком — линия обороны. Дугой со стороны,
## противоположной реке (−x объекта), окоп с бруствером из мешков соединяет 3 позиции с орудиями;
## где через линию идёт тропа — проход. На выходах троп с другой стороны — посты из мешков.
## Остовы подбитой техники перед линией ставит Terrain3D.scenes. Меш посёлка утоплен на 1 % размера
## (render3d) — всё низкое поднимаем на SINK, иначе уходит под землю
const BAG := Color(0.8, 0.72, 0.55)
const TRENCH := Color(0.42, 0.36, 0.29)
const GUN := Color(0.36, 0.37, 0.34)
const DEF_R := 1.07   # радиус линии, доля края застройки


static func _defence(st: SurfaceTool, variant: int, rng: RandomNumberGenerator) -> void:
	var sink := 0.0101 / V_UNIT
	var arc := 0.85 + _vr(variant, 40) * 0.25
	var line := PackedVector2Array()
	for k in 25:
		var ang := PI - arc + 2.0 * arc * float(k) / 24.0
		var r := V_EDGE * outline(variant, ang) * DEF_R + sin(k * 0.9 + variant) * 0.012
		line.append(Vector2.from_angle(ang) * r)
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		if path_dist(variant, (a + b) * 0.5) < 0.04:
			continue   # проход для тропы
		var inward := -((a + b) * 0.5).normalized() * 0.022
		_strip(st, a + inward, b + inward, 0.02, TRENCH, sink + 0.003)   # окоп за бруствером
		_bags(st, a, b, sink, rng)
	for k in [0, 12, 24]:
		_gun_pit(st, line[k], line[k].angle(), sink, rng)
	# посты у выходов троп с остальных сторон
	for pl: PackedVector2Array in village_paths(variant):
		var tip: Vector2 = pl[pl.size() - 1]
		var e := V_EDGE * outline(variant, tip.angle())
		if tip.length() < e * 0.9 or absf(angle_difference(tip.angle(), PI)) < arc + 0.2:
			continue
		var c := tip.normalized() * e * 1.08
		var side := c.normalized().orthogonal() * 0.045
		_post(st, c + side, c.angle(), sink, rng)
		_post(st, c - side, c.angle(), sink, rng)


## Ряд мешков с песком от a до b: два ряда внахлёст
static func _bags(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, rng: RandomNumberGenerator) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 1e-6)
	var n := maxi(1, int(len / 0.019))
	for row in 2:
		for i in n:
			var c := a + dir * (len * (i + 0.5 * row + 0.25) / n)
			var s := Vector3(0.026, 0.011, 0.017) * rng.randf_range(0.9, 1.1)
			var yaw_c := Vector3(c.x, y0 + row * 0.009, c.y)
			_box_yaw(st, yaw_c, s, dir.angle(), BAG)


## Позиция с орудием: кольцо мешков и ствол наружу
static func _gun_pit(st: SurfaceTool, c: Vector2, out_ang: float, y0: float, rng: RandomNumberGenerator) -> void:
	var r := 0.046
	for i in 9:
		var a0 := out_ang + PI * 0.25 + TAU * 0.85 * float(i) / 9.0   # проём сзади, к посёлку
		var p := c + Vector2.from_angle(a0) * r
		_box_yaw(st, Vector3(p.x, y0, p.y), Vector3(0.03, 0.014, 0.018), a0 + PI * 0.5, BAG)
	_box_yaw(st, Vector3(c.x, y0, c.y), Vector3(0.03, 0.013, 0.022), out_ang, GUN)   # лафет
	var tip := c + Vector2.from_angle(out_ang) * 0.03
	_box_yaw(st, Vector3(tip.x, y0 + 0.009, tip.y), Vector3(0.055, 0.006, 0.006), out_ang, GUN)   # ствол


## Пост: подкова из мешков, открытая к посёлку
static func _post(st: SurfaceTool, c: Vector2, out_ang: float, y0: float, rng: RandomNumberGenerator) -> void:
	for i in 6:
		var a0 := out_ang - PI * 0.6 + PI * 1.2 * float(i) / 5.0
		var p := c + Vector2.from_angle(a0) * 0.026
		_box_yaw(st, Vector3(p.x, y0, p.y), Vector3(0.024, 0.013, 0.015), a0 + PI * 0.5, BAG)


## Коробка, повёрнутая на yaw вокруг вертикали (основание на c.y)
static func _box_yaw(st: SurfaceTool, c: Vector3, s: Vector3, yaw: float, col: Color) -> void:
	var ax := Vector2.from_angle(yaw) * s.x * 0.5
	var az := -Vector2.from_angle(yaw).orthogonal() * s.z * 0.5   # порядок вершин как у _box (лицом наружу)
	var p := Vector2(c.x, c.z)
	var q := [p - ax - az, p + ax - az, p + ax + az, p - ax + az]
	var y0 := c.y
	var y1 := c.y + s.y
	var top := col.lightened(0.08)
	_quad(st, Vector3(q[0].x, y1, q[0].y), Vector3(q[1].x, y1, q[1].y), Vector3(q[2].x, y1, q[2].y), Vector3(q[3].x, y1, q[3].y), top)
	for i in 4:
		var a: Vector2 = q[(i + 1) % 4]
		var b: Vector2 = q[i]
		_quad(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), col)


const PATH := Color(0.9, 0.83, 0.72)   # утоптанная тропа: чуть светлее земли, пыль


## Дом посёлка с двором, если место свободно (не на тропе, не на соседе, внутри контура). Война — по
## уровню 2 стайл-гайда: больше целых домов, часть без крыши, немного обрушенных
static func _put_house(st: SurfaceTool, c: Vector2, sz: Vector2, lots: Array, rng: RandomNumberGenerator, variant: int) -> void:
	if c.length() > V_EDGE * outline(variant, c.angle()) * 1.02:
		return
	if path_dist(variant, c) < PATH_W * 0.5 + minf(sz.x, sz.y) * 0.5:
		return
	for l in lots:
		if absf(c.x - l[0].x) < (sz.x + l[1].x) * 0.5 + 0.012 and absf(c.y - l[0].y) < (sz.y + l[1].y) * 0.5 + 0.012:
			return
	lots.append([c, sz])
	var roll := rng.randf()
	var centre := c.length() < V_EDGE * 0.45
	if roll < 0.56:
		_house(st, c, sz, rng.randf_range(0.04, 0.065), rng)
		if rng.randf() < 0.35:   # двор за дувалом со стороны от тропы
			var yard := c + Vector2(0.0, sz.y * 0.5 + 0.025) * (1.0 if rng.randf() < 0.5 else -1.0)
			if path_dist(variant, yard) > 0.045:
				_yard(st, yard, Vector2(sz.x, 0.045), rng)
	elif roll < 0.78:
		_roofless(st, c, sz, rng.randf_range(0.04, 0.07), rng)
	elif roll < 0.9:
		_collapsed(st, c, sz, rng)
	elif roll < 0.95 and centre:
		_shell(st, c, sz * 1.05, rng.randf_range(0.1, 0.14), rng)
	else:
		_rubble(st, c, sz.x * 0.45, 5, rng)


## Двор: низкий дувал с трёх сторон у дома
static func _yard(st: SurfaceTool, c: Vector2, s: Vector2, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.01, 0.015)
	var x0 := c.x - s.x * 0.5
	var x1 := c.x + s.x * 0.5
	var z0 := c.y - s.y * 0.5
	var z1 := c.y + s.y * 0.5
	_wall(st, Vector2(x0, z0), Vector2(x0, z1), 0.005, h, false)
	_wall(st, Vector2(x1, z0), Vector2(x1, z1), 0.005, h, false)
	var gate := rng.randf_range(0.3, 0.6)
	_wall(st, Vector2(x0, z1), Vector2(lerpf(x0, x1, gate - 0.12), z1), 0.005, h, false)
	_wall(st, Vector2(lerpf(x0, x1, gate + 0.12), z1), Vector2(x1, z1), 0.005, h, false)


## Плоская полоса (тропа) от a до b шириной w чуть над землёй
static func _strip(st: SurfaceTool, a: Vector2, b: Vector2, w: float, col: Color, y := 0.002) -> void:
	var n := (b - a).normalized().orthogonal() * w * 0.5
	var ext := (b - a).normalized() * w * 0.5   # стык соседних кусков без щелей
	var p0 := a - ext
	var p1 := b + ext
	_quad(st, Vector3(p0.x - n.x, y, p0.y - n.y), Vector3(p1.x - n.x, y, p1.y - n.y), Vector3(p1.x + n.x, y, p1.y + n.y), Vector3(p0.x + n.x, y, p0.y + n.y), col)


## Огород за дувалом: низкая глинобитная ограда по периметру с проходом
static func _garden(st: SurfaceTool, c: Vector2, s: Vector2, rng: RandomNumberGenerator) -> void:
	var t := 0.006
	var h := rng.randf_range(0.01, 0.016)
	var x0 := c.x - s.x * 0.5
	var x1 := c.x + s.x * 0.5
	var z0 := c.y - s.y * 0.5
	var z1 := c.y + s.y * 0.5
	var gate := rng.randi() % 4
	var sides := [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x1, z1)], [Vector2(x1, z1), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0, z0)]]
	for i in 4:
		var a: Vector2 = sides[i][0]
		var b: Vector2 = sides[i][1]
		if i == gate:   # проход: две половинки стены
			_wall(st, a, a.lerp(b, 0.4), t, h, false)
			_wall(st, a.lerp(b, 0.6), b, t, h, false)
		elif rng.randf() < 0.2:   # обвалившийся кусок
			_wall(st, a, a.lerp(b, 0.55), t, h, false)
		else:
			_wall(st, a, b, t, h, false)


## Сжать готовую сетку в k раз (кишлак строится в старых единицах)
static func _scaled(st: SurfaceTool, k: float) -> ArrayMesh:
	st.generate_normals()
	var arr := st.commit_to_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in vs.size():
		vs[i] *= k
	arr[Mesh.ARRAY_VERTEX] = vs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Оазис (тест 3.5-s4, п. 17): вместо круглой картинки-наклейки — несколько глинобитных домов у
## пруда, огороды за дувалами; зелень (поля, сады) — пятном на земле и деревьями biome_props.
## Площадка 1 × 1 = размер объекта
static func oasis(variant: int) -> ArrayMesh:
	var key := "oasis%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4241 * (variant + 3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var core := Vector2(0.06, -0.05)
	# пруд (хауз) с глиняным бортиком
	var pc := core + Vector2(-0.1, 0.06)
	_box(st, Vector3(pc.x, 0.0, pc.y), Vector3(0.1, 0.006, 0.075), WALL, WATER)
	_parapet(st, Vector3(pc.x, 0.0, pc.y), Vector2(0.11, 0.085), 0.008, 0.012)
	# 3–5 домов вокруг двора
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var c := core + Vector2.from_angle(a) * rng.randf_range(0.06, 0.11)
		if c.distance_to(pc) < 0.085:
			continue
		var s := Vector2(rng.randf_range(0.05, 0.075), rng.randf_range(0.045, 0.065))
		if rng.randf() < 0.75:
			_house(st, c, s, rng.randf_range(0.04, 0.06), rng)
		else:
			_roofless(st, c, s, rng.randf_range(0.04, 0.06), rng)
	# огороды за дувалами в зелёном пятне
	for i in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.17, 0.28) * outline(variant, a)
		_garden(st, Vector2.from_angle(a) * r, Vector2(rng.randf_range(0.08, 0.13), rng.randf_range(0.07, 0.11)), rng)
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
