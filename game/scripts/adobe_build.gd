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
static var _mat: ShaderMaterial
## Warm bounce from the sunlit ground into the shaded sides of the walls (adobe.gdshader, bounce.gdshaderinc)
const BOUNCE := 0.35


## Material of the village and oasis meshes (adobe.gdshader): clay from the CC0 ground set in three world
## projections (no unwrap, no stretching on walls), vertex colour as albedo, matte (Kanta 19.10). The vertex
## colour's alpha picks own surfaces — sandbags, trench and street strips (ID_* below) — textured by RoadTex
static func material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/adobe.gdshader")
	var p := "res://art/ground/pbr/clay_albedo.jpg"
	if ResourceLoader.exists(p):
		_mat.set_shader_parameter("clay_tex", load(p))
	_mat.set_shader_parameter("albedo", Color(1.0, 0.95, 0.88))
	_mat.set_shader_parameter("bounce", BOUNCE)
	RoadTex.apply_adobe(_mat)
	return _mat


## Vertex-colour alpha codes read by adobe.gdshader. Strips carry ±ID_SPAN across their width (edge to edge),
## so the shader knows the middle of a trench or a street
const ID_WATER := 0.12   ## still water: the oasis pond, and as a strip its irrigation channels (OasisBuild)
const ID_BAG := 0.25
const ID_TRENCH := 0.5
const ID_STREET := 0.75
const ID_SPAN := 0.08


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


## Тест 3.5-s8 (Kanta: «кишлак должен стать больше по площади — мини-городок, а не 4–7 сараев»):
## размер o_village 900 → 1650 (площадь ×3,4). Кишлак строится в «старых» единицах (1 = 640 px мира):
## дома, стены и мешки остаются прежнего размера в мире, растёт только площадь застройки; потом сетка
## сжимается под размер объекта. Доля размера, занятая застройкой, — прежняя (0,43)
const V_UNIT := 640.0 / 1650.0  # размер o_village — 1650 (background.gd)
const V_EDGE := 1.1             # радиус края застройки, старые единицы (× outline)
const SINK := 0.0101 / V_UNIT   # меш утоплен на 1 % размера (render3d): уровень земли в старых единицах


## Улицы (правка Kanta 18.10, L-01: главная тропа по +x объекта — fix_object разворачивает посёлок так,
## чтобы +x смотрел к реке; тропа выходит к дороге и дальше к воде). 3.5-s8: главная улица через весь
## город с изгибами по шуму, поперечная улица, 3–4 радиальные, полукольцо и 14–20 переулков-тупиков между
## дворами. Каждая — [ломаная, ширина] в старых единицах; одинаковы для раскладки в любом потоке
const PATH_W := 0.032        # главная улица (~20 px мира)
const STREET_W := 0.024      # улицы
const LANE_W := 0.015        # переулки
const PATH_OUT := 1.9        # главная улица за край застройки: к дороге и к воде
const SQ_R := 0.17           # площадь-базар в центре (~110 px)
const PG := 0.1              # клетка сетки поиска улиц
static var _paths := {}
static var _pgrid := {}
static var _pmx := Mutex.new()


static func village_paths(variant: int) -> Array:
	_pmx.lock()
	if not _paths.has(variant):
		_build_paths(variant)
	var out: Array = _paths[variant]
	_pmx.unlock()
	return out


static func _grid(variant: int) -> Dictionary:
	_pmx.lock()
	if not _paths.has(variant):
		_build_paths(variant)
	var g: Dictionary = _pgrid[variant]
	_pmx.unlock()
	return g


## Плавная ломаная от a до b с изгибами поперёк (сумма синусов — «шум»), концы на месте
static func _curvy(a: Vector2, b: Vector2, amp: float, ph: float, n: int) -> PackedVector2Array:
	var pl := PackedVector2Array()
	var side := (b - a).normalized().orthogonal()
	for k in n + 1:
		var t := float(k) / n
		var w := sin(t * PI) * (sin(t * 7.0 + ph) * 0.7 + sin(t * 13.0 + ph * 1.7) * 0.3)
		pl.append(a.lerp(b, t) + side * w * amp)
	return pl


static func _build_paths(variant: int) -> void:
	var out := []
	var v := float(variant)
	# главная: от края со стороны гор (−x) через площадь к реке (+x); у площади — ровно через центр
	var main := PackedVector2Array()
	var x0 := -V_EDGE * outline(variant, PI) * 1.02
	var n := 30
	for k in n + 1:
		var x := lerpf(x0, PATH_OUT, float(k) / n)
		var y := 0.075 * sin(x * 2.6 + v * 1.7) + 0.035 * sin(x * 6.3 + v * 0.9 + 1.0)
		var y0 := 0.075 * sin(v * 1.7) + 0.035 * sin(v * 0.9 + 1.0)
		main.append(Vector2(x, y - y0 * (1.0 - smoothstep(0.0, 0.7, absf(x)))))
	out.append([main, PATH_W])
	# поперечная улица
	var ca := PI * 0.5 + (_vr(variant, 3) - 0.5) * 0.6
	out.append([_curvy(Vector2.from_angle(ca + PI) * V_EDGE * outline(variant, ca + PI) * 1.0,
		Vector2.from_angle(ca) * V_EDGE * outline(variant, ca) * 1.0, 0.07, v * 2.0 + 1.0, 18), STREET_W])
	# радиальные улицы от площади к краю — между главной и поперечной
	var rad := []
	for i in 4:
		var ang := PI * 0.25 + PI * 0.5 * i + (_vr(variant, 10 + i) - 0.5) * 0.5
		if i == 3 and _vr(variant, 9) < 0.4:
			continue
		rad.append(ang)
		var e := V_EDGE * outline(variant, ang) * 1.04
		out.append([_curvy(Vector2.from_angle(ang) * SQ_R * 0.9, Vector2.from_angle(ang) * e, 0.06, v + i * 2.3, 12), STREET_W])
	# полукольцо на середине радиуса
	var ring := PackedVector2Array()
	var a0 := _vr(variant, 30) * TAU
	for k in 19:
		var ang := a0 + PI * 1.2 * float(k) / 18.0
		ring.append(Vector2.from_angle(ang) * V_EDGE * 0.55 * outline(variant, ang))
	out.append([ring, STREET_W])
	# переулки-тупики: от улиц вбок, с изломом
	var streets := out.size()
	var lanes := 14 + int(_vr(variant, 31) * 7.0)
	for i in lanes:
		var si := 1 + int(_vr(variant, 50 + i) * (streets - 1)) if i % 3 != 0 else 0
		var pl: PackedVector2Array = out[si][0]
		var k := int(_vr(variant, 80 + i) * (pl.size() - 2))
		var p: Vector2 = pl[k].lerp(pl[k + 1], _vr(variant, 110 + i))
		var e := V_EDGE * outline(variant, p.angle())
		if p.length() > e * 0.85 or p.length() < SQ_R * 1.3:
			continue
		var d := (pl[k + 1] - pl[k]).normalized().orthogonal() * (1.0 if _vr(variant, 140 + i) < 0.5 else -1.0)
		d = d.rotated((_vr(variant, 170 + i) - 0.5) * 0.7)
		var len := 0.12 + _vr(variant, 200 + i) * 0.16
		var q1 := p + d * len * 0.55
		var q2 := q1 + d.rotated((_vr(variant, 230 + i) - 0.5) * 1.4) * len * 0.45
		if q2.length() > e * 0.95:
			q2 = q1
		out.append([PackedVector2Array([p, q1, q2]), LANE_W])
	_paths[variant] = out
	# сетка поиска: в клетке — отрезки улиц ближе 0,12 к ней
	var g := {}
	for pi in out.size():
		var pl: PackedVector2Array = out[pi][0]
		for k in pl.size() - 1:
			var a := pl[k]
			var b := pl[k + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * 0.12
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * 0.12
			for gx in range(floori(lo.x / PG), floori(hi.x / PG) + 1):
				for gy in range(floori(lo.y / PG), floori(hi.y / PG) + 1):
					var key := Vector2i(gx, gy)
					if not g.has(key):
						g[key] = []
					g[key].append([a, b - a, float(out[pi][1]), pi])
	_pgrid[variant] = g


## Ближайшая улица к точке u (старые единицы): x — расстояние до края полотна, y — до оси, z — номер
## улицы (0 — главная), w — угол улицы там. Дальше 0,12 от улиц — (1, 1, −1, 0)
static func path_info(variant: int, u: Vector2) -> Vector4:
	var cell: Array = _grid(variant).get(Vector2i(floori(u.x / PG), floori(u.y / PG)), [])
	var best := Vector4(1.0, 1.0, -1.0, 0.0)
	for s in cell:
		var a: Vector2 = s[0]
		var ab: Vector2 = s[1]
		var t := clampf((u - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := u.distance_to(a + ab * t)
		var e := d - float(s[2]) * 0.5
		if e < best.x:
			best = Vector4(e, d, float(s[3]), ab.angle())
	return best


## Расстояние от точки u (старые единицы) до оси ближайшей улицы (дальше 0,12 — 1)
static func path_dist(variant: int, u: Vector2) -> float:
	return path_info(variant, u).y


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
			# улицы: между домами и за край — главная к дороге и к воде, остальные тают в степи
			var pi := path_info(variant, u)
			if pi.z >= 0.0:
				var reach := PATH_OUT if int(pi.z) == 0 and u.x > 0.0 else e * 1.2
				tr = maxf(tr, (1.0 - smoothstep(0.0, 0.018, pi.x)) * (1.0 - smoothstep(reach * 0.92, reach, rad)) * 0.9)
			# L-08: утоптанная полоса вдоль линии обороны (окоп, позиции орудий)
			var off_arc := smoothstep(def_arc(variant), def_arc(variant) + 0.12, absf(angle_difference(ang, PI)))
			tr = maxf(tr, (1.0 - off_arc) * (1.0 - smoothstep(0.035, 0.075, absf(rad - e * DEF_R))) * 0.6)
			# огороды, сады, поля — за домами (не между ними) и не на линии обороны: кольцо за краем застройки,
			# только в части секторов — пятнами, не кругом (правка Kanta 18.10: поля лезли на позиции и в посёлок)
			var gr := smoothstep(e * 1.02, e * 1.1, rad) * (1.0 - smoothstep(e * 1.45, e * 1.65, rad)) * _sect(variant, ang)
			gr *= smoothstep(def_arc(variant) + 0.1, def_arc(variant) + 0.35, absf(angle_difference(ang, PI)))
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


## Секторы с огородами и полями вокруг кишлака (0…1)
static func _sect(variant: int, ang: float) -> float:
	return smoothstep(-0.15, 0.45, sin(2.0 * ang + 0.5 + variant * 1.3) + 0.6 * sin(5.0 * ang + variant * 0.7))


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
			return 0.68   # half-diagonal of the turned walls plus corner towers, so the ×2 fort keeps its corner off the road
	return 0.45


## Правка Kanta 18.10.2026 (L-08, схема Kanta): перед посёлком — линия обороны. Дугой со стороны,
## противоположной реке (−x объекта), окоп с бруствером из мешков соединяет 3 позиции с орудиями;
## где через линию идёт тропа — проход. На выходах троп с другой стороны — посты из мешков.
## Остовы подбитой техники перед линией ставит Terrain3D.scenes. Меш посёлка утоплен на 1 % размера
## (render3d) — всё низкое поднимаем на SINK, иначе уходит под землю
const BAG := Color(0.8, 0.72, 0.55, ID_BAG)   # alpha: hessian in adobe.gdshader
const TRENCH := Color(0.42, 0.36, 0.29)
const GUN := Color(0.36, 0.37, 0.34)
const DEF_R := 1.07   # радиус линии, доля края застройки


## Полуугол дуги линии обороны (вокруг −x объекта, стороны гор)
static func def_arc(variant: int) -> float:
	return 0.85 + _vr(variant, 40) * 0.25


static func _defence(st: SurfaceTool, variant: int, rng: RandomNumberGenerator, water := {}) -> void:
	var sink := SINK
	var arc := def_arc(variant)
	var line := PackedVector2Array()
	for k in 25:
		var ang := PI - arc + 2.0 * arc * float(k) / 24.0
		var r := V_EDGE * outline(variant, ang) * DEF_R + sin(k * 0.9 + variant) * 0.012
		line.append(Vector2.from_angle(ang) * r)
	var pits := []
	for k0: int in [0, 12, 24]:
		# S9-08: позиция орудия на ручье — ближайшая сухая точка линии (к середине дуги); нет такой — позиции нет
		for d in 7:
			var k := k0 + (d if k0 < 12 else -d if k0 > 12 else ceili(d * 0.5) * (1 if d % 2 == 1 else -1))
			if not _wet_box(water, line[k], Vector2(PIT_R, PIT_R), 0.0, 0.0):
				pits.append(line[k])
				break
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		if path_dist(variant, (a + b) * 0.5) < 0.04:
			continue   # проход для тропы
		# правка Kanta 18.10: бруствер и окоп упираются в позицию орудия, а не идут сквозь неё
		for pc: Vector2 in pits:
			if a.distance_to(pc) < PIT_R:
				a = pc + (a - pc).normalized() * PIT_R if a.distance_to(pc) > 1e-4 else pc + (b - pc).normalized() * PIT_R
			if b.distance_to(pc) < PIT_R:
				b = pc + (b - pc).normalized() * PIT_R if b.distance_to(pc) > 1e-4 else pc + (a - pc).normalized() * PIT_R
		if a.distance_to(b) < 0.006 or _seg_near(a, b, pits, PIT_R * 0.9):
			continue
		if _wet_seg(water, a, b, 0.05):
			continue   # S9-08: над ручьём окоп и бруствер прерываются (с запасом на окоп за бруствером)
		var inward := -((a + b) * 0.5).normalized() * 0.022
		_strip(st, a + inward, b + inward, 0.02, TRENCH, sink + 0.003, ID_TRENCH)   # окоп за бруствером
		if edge_log_on:
			edge_log.append(["trench", a, b])
		_bags(st, a, b, sink, rng)
	for pc: Vector2 in pits:
		_gun_pit(st, pc, pc.angle(), sink, rng)
		if edge_log_on:
			edge_log.append(["pit", pc])
	# посты у выходов троп с остальных сторон
	for p in village_paths(variant):
		var pl: PackedVector2Array = p[0]
		if float(p[1]) <= LANE_W:
			continue
		var tip: Vector2 = pl[pl.size() - 1]
		var e := V_EDGE * outline(variant, tip.angle())
		if tip.length() < e * 0.9 or absf(angle_difference(tip.angle(), PI)) < arc + 0.2:
			continue
		var c := tip.normalized() * e * 1.08
		var side := c.normalized().orthogonal() * 0.045
		if _wet_box(water, c, Vector2(0.075, 0.03), c.angle() + PI * 0.5, 0.0):
			continue   # S9-08: пост у тропы не на ручье
		_post(st, c + side, c.angle(), sink, rng)
		_post(st, c - side, c.angle(), sink, rng)
		if edge_log_on:
			edge_log.append(["post", c])


const PIT_R := 0.062   # радиус позиции орудия с бруствером (кольцо мешков 0,046 + полмешка + зазор)


static func _seg_near(a: Vector2, b: Vector2, pts: Array, r: float) -> bool:
	for p: Vector2 in pts:
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		if p.distance_to(a + ab * t) < r:
			return true
	return false


## A row of sandbags from a to b: two overlapping rows, each bag its own "pillow" (_bag) with a gap,
## slightly different in size and turned (Kanta 26.10: the bags used to be solid slabs)
static func _bags(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, rng: RandomNumberGenerator) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 1e-6)
	var n := maxi(1, int(len / 0.019))
	for row in 2:
		for i in n:
			var c := a + dir * (len * (i + 0.5 * row + 0.25) / n)
			var s := Vector3(0.022, 0.011, 0.016) * rng.randf_range(0.9, 1.1)
			_bag(st, Vector3(c.x, y0 + row * 0.0085, c.y), s, dir.angle() + rng.randf_range(-0.12, 0.12), rng)


## One bag: a "pillow" s.x long, s.y high, s.z wide on base c.y, turned by yaw. A ring of 10 points
## (superellipse: straight sides, rounded ends) at three heights: bottom tucked in, middle bulging, top rounded
## to the centre; smooth normals (group 1). 50 triangles; colour BAG (alpha ID_BAG: hessian in adobe.gdshader),
## the tone varies slightly from bag to bag
static func _bag(st: SurfaceTool, c: Vector3, s: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var col := BAG.darkened(rng.randf_range(0.0, 0.12))
	col.a = BAG.a
	var fx := Vector2.from_angle(yaw)
	var fz := -fx.orthogonal()
	var ring := func(k: int, sc: float) -> Vector2:
		var t := TAU * (k + 0.5) / 10.0
		var cx := cos(t)
		var sz := sin(t)
		var u := signf(cx) * pow(absf(cx), 0.4) * s.x * 0.5 * sc
		var v := signf(sz) * pow(absf(sz), 0.6) * s.z * 0.5 * sc
		return Vector2(c.x, c.z) + fx * u + fz * v
	var levels := [[0.0, 0.86], [0.5, 1.0], [0.88, 0.7]]
	st.set_smooth_group(1)
	st.set_color(col)
	for li in 2:
		var y0 := c.y + s.y * float(levels[li][0])
		var y1 := c.y + s.y * float(levels[li + 1][0])
		for k in 10:
			var p0: Vector2 = ring.call(k, levels[li][1])
			var p1: Vector2 = ring.call((k + 1) % 10, levels[li][1])
			var q0: Vector2 = ring.call(k, levels[li + 1][1])
			var q1: Vector2 = ring.call((k + 1) % 10, levels[li + 1][1])
			# facing out: same order as _quad (a, c, b, a, d, c) with a = p1 bottom, b = p0 bottom
			var va := Vector3(p1.x, y0, p1.y)
			var vb := Vector3(p0.x, y0, p0.y)
			var vc := Vector3(q0.x, y1, q0.y)
			var vd := Vector3(q1.x, y1, q1.y)
			for v: Vector3 in [va, vc, vb, va, vd, vc]:
				st.add_vertex(v)
	var top := Vector3(c.x, c.y + s.y, c.z)
	for k in 10:
		var p0: Vector2 = ring.call(k, levels[2][1])
		var p1: Vector2 = ring.call((k + 1) % 10, levels[2][1])
		var yt := c.y + s.y * float(levels[2][0])
		for v: Vector3 in [Vector3(p0.x, yt, p0.y), top, Vector3(p1.x, yt, p1.y)]:
			st.add_vertex(v)
	st.set_smooth_group(-1)


## Позиция с орудием: кольцо мешков и ствол наружу
static func _gun_pit(st: SurfaceTool, c: Vector2, out_ang: float, y0: float, rng: RandomNumberGenerator) -> void:
	var r := 0.046
	for i in 9:
		var a0 := out_ang + PI * 0.25 + TAU * 0.85 * float(i) / 9.0   # проём сзади, к посёлку
		var p := c + Vector2.from_angle(a0) * r
		_bag(st, Vector3(p.x, y0, p.y), Vector3(0.027, 0.008, 0.017) * rng.randf_range(0.92, 1.08), a0 + PI * 0.5 + rng.randf_range(-0.1, 0.1), rng)
		_bag(st, Vector3(p.x, y0 + 0.007, p.y), Vector3(0.024, 0.007, 0.015) * rng.randf_range(0.92, 1.08), a0 + PI * 0.5 + rng.randf_range(-0.15, 0.15), rng)
	_box_yaw(st, Vector3(c.x, y0, c.y), Vector3(0.03, 0.013, 0.022), out_ang, GUN)   # лафет
	var tip := c + Vector2.from_angle(out_ang) * 0.03
	_box_yaw(st, Vector3(tip.x, y0 + 0.009, tip.y), Vector3(0.055, 0.006, 0.006), out_ang, GUN)   # ствол


## Пост: подкова из мешков, открытая к посёлку
static func _post(st: SurfaceTool, c: Vector2, out_ang: float, y0: float, rng: RandomNumberGenerator) -> void:
	for i in 6:
		var a0 := out_ang - PI * 0.6 + PI * 1.2 * float(i) / 5.0
		var p := c + Vector2.from_angle(a0) * 0.026
		_bag(st, Vector3(p.x, y0, p.y), Vector3(0.021, 0.0075, 0.014) * rng.randf_range(0.92, 1.08), a0 + PI * 0.5 + rng.randf_range(-0.1, 0.1), rng)
		if i % 5 != 0:
			_bag(st, Vector3(p.x, y0 + 0.0065, p.y), Vector3(0.019, 0.0065, 0.013) * rng.randf_range(0.92, 1.08), a0 + PI * 0.5 + rng.randf_range(-0.15, 0.15), rng)


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


const PATH := Color(0.86, 0.84, 0.86)   # утоптанная улица: в тон земле, чуть светлее (3.5-s8: была оранжевой)


## Flat strip (path) from a to b, w wide, just above the ground. id (ID_TRENCH, ID_STREET) picks its own material
## in adobe.gdshader: colour alpha id - ID_SPAN on one edge and id + ID_SPAN on the other (the shader knows the middle)
static func _strip(st: SurfaceTool, a: Vector2, b: Vector2, w: float, col: Color, y := 0.002, id := 1.0) -> void:
	var n := (b - a).normalized().orthogonal() * w * 0.5
	var ext := (b - a).normalized() * w * 0.5   # стык соседних кусков без щелей
	var p0 := a - ext
	var p1 := b + ext
	var lo := Color(col, id - ID_SPAN if id < 1.0 else col.a)
	var hi := Color(col, id + ID_SPAN if id < 1.0 else col.a)
	var qa := Vector3(p0.x - n.x, y, p0.y - n.y)
	var qb := Vector3(p1.x - n.x, y, p1.y - n.y)
	var qc := Vector3(p1.x + n.x, y, p1.y + n.y)
	var qd := Vector3(p0.x + n.x, y, p0.y + n.y)
	st.set_smooth_group(-1)
	for v: Array in [[qa, lo], [qc, hi], [qb, lo], [qa, lo], [qd, hi], [qc, hi]]:   # as _quad: a, c, b, a, d, c
		st.set_color(v[1])
		st.add_vertex(v[0])


## Сжать готовую сетку в k раз (кишлак строится в старых единицах)
static func _scaled(st: SurfaceTool, k: float) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _scaled_arrays(st, k))
	return m


## Surface arrays of st (normals generated, vertices scaled by k). Callers that need the arrays again keep
## this copy: ArrayMesh.surface_get_arrays on a worker thread waits for the main thread's RenderingServer
## flush, and deadlocks when the main thread is itself waiting for that worker (village_at in the background)
static func _scaled_arrays(st: SurfaceTool, k: float) -> Array:
	st.generate_normals()
	var arr := st.commit_to_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in vs.size():
		vs[i] *= k
	arr[Mesh.ARRAY_VERTEX] = vs
	return arr


## The Highland oasis (o_oasis) on its 1 × 1 plot: the farmstead's walls, pond, channels and ruins
## (OasisBuild.mesh); Render3D adds its house models with OasisBuild.attach
static func oasis(variant: int) -> ArrayMesh:
	return OasisBuild.mesh(variant)


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


## Timber tones of the village's posts, crates and trench planks (the bridges moved to PropBuild)
const WOOD := Color(0.47, 0.35, 0.24)
const WOOD_DARK := Color(0.3, 0.22, 0.16)


## Палитра кишлака (3.5-s8, аудит Б-5: крыши были одного оранжевого цвета, ярче земли). Цвет вершины
## умножается на текстуру глины — оттенки подобраны так, чтобы крыши были в тон выгоревшей земле:
## светлее и серее, с разбросом от дома к дому (свежая обмазка, старая, тёмная от времени)
const T_ROOFS := [Color(0.86, 0.86, 0.9), Color(0.82, 0.83, 0.88), Color(0.9, 0.87, 0.86), Color(0.78, 0.77, 0.8), Color(0.88, 0.88, 0.95)]
const T_WALL := Color(0.8, 0.79, 0.82)
const T_RUBBLE := Color(0.76, 0.74, 0.76)
const T_DARK := Color(0.42, 0.39, 0.38)
const T_TREE := Color(0.36, 0.4, 0.25)
const T_METAL := Color(0.5, 0.47, 0.44)
const T_BUND := Color(0.72, 0.7, 0.66)
const T_CLOTH := [Color(0.62, 0.5, 0.42), Color(0.52, 0.5, 0.5), Color(0.66, 0.6, 0.5), Color(0.5, 0.42, 0.4), Color(0.58, 0.56, 0.48)]


static func _roof_col(rng: RandomNumberGenerator) -> Color:
	var c: Color = T_ROOFS[rng.randi() % T_ROOFS.size()]
	var k := rng.randf_range(-0.05, 0.05)
	return Color(clampf(c.r + k, 0.0, 1.0), clampf(c.g + k, 0.0, 1.0), clampf(c.b + k, 0.0, 1.0))


## 3.5-s8: мини-городок. Площадь-базар в центре (навесы, лавки, хауз), вдоль главной улицы — ряды лавок,
## караван-сарай у въезда со стороны реки, водокачка, иногда склад; 30–45 дворов-кварталов (глухая стена
## по периметру, ворота к улице, 1–3 дома по стенам внутри, дерево во дворе), дома в 1–2 этажа; часть дворов
## разрушена (стены рваной сплошной линией, груды глины). По краям — сады за дувалами и поля с межами.
## Всё — одна сетка (один вызов отрисовки), повёрнутые коробки
static var _cmx := Mutex.new()
static var model_houses := true   # VIS-01: houses as models (VillageHouses); false — the old box houses (bench «before»)
static var _vcache := {}   # сетки кишлака: собираются и в фоне (prewarm) — только под _cmx


## Собрать все раскладки кишлака заранее (в фоне при старте вылета) — сборка одной 0,15–0,4 с
static func prewarm() -> void:
	for v in 4:
		village(v)


static func village(variant: int) -> ArrayMesh:
	var key := "village%d" % variant
	_cmx.lock()
	var have: ArrayMesh = _vcache.get(key)
	_cmx.unlock()
	if have != null:
		return have
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paths := village_paths(variant)
	var lots := []   # [центр, полуразмер, угол] — повёрнутые прямоугольники: ничто не наползает друг на друга и на улицы
	var stats := {"yards": 0, "houses": 0}
	if model_houses:
		stats["homes"] = []   # VIS-01: houses as models (VillageHouses), recorded instead of drawn
	# 1) крупные здания: караван-сарай у главной улицы со стороны реки, водокачка у полукольца, склад
	var ex := V_EDGE * outline(variant, 0.0)
	for tr in 16:
		var mx := lerpf(0.4, 0.8, rng.randf()) * ex
		var d := _main_dir(variant, mx)
		var sg := 1.0 if rng.randf() < 0.5 else -1.0
		var h := Vector2(0.15, 0.15)
		var c := Vector2(mx, _main_y(variant, mx)) + d.orthogonal() * sg * (PATH_W * 0.5 + h.y + 0.012)
		if _place(c, h, d.angle(), lots, variant, 0.01, true):
			_serai(st, c, h, d.angle(), 2 if sg > 0.0 else 0, rng, stats.get("homes"))
			stats["serai"] = 1
			break
	var tower := false
	var ware := rng.randf() < 0.55
	for tr in 80:
		if tower and not ware:
			break
		var ang := rng.randf() * TAU
		var c := Vector2.from_angle(ang) * V_EDGE * outline(variant, ang) * rng.randf_range(0.4, 0.8)
		var pi := path_info(variant, c)
		var yaw := pi.w if pi.z >= 0.0 else rng.randf() * TAU
		if not tower:
			if _place(c, Vector2(0.03, 0.03), yaw, lots, variant, 0.015, false):
				_water_tower(st, c, yaw, rng)
				tower = true
				stats["tower"] = 1
		elif _place(c, Vector2(0.12, 0.05), yaw, lots, variant, 0.012, false):
			_warehouse(st, c, Vector2(0.12, 0.05), yaw, rng)
			ware = false
			stats["warehouse"] = 1
	# 2) площадь-базар: хауз, навесы торговцев по кругу; ряды лавок вдоль главной улицы у площади
	_bazaar(st, variant, lots, rng, stats.get("homes"))
	for sgx: float in [-1.0, 1.0]:
		for sg: float in [-1.0, 1.0]:
			var x := SQ_R + 0.03
			while x < 0.5 * ex:
				var w := rng.randf_range(0.022, 0.032)
				var u := Vector2(sgx * (x + w), 0.0)
				u.y = _main_y(variant, u.x)
				var d := _main_dir(variant, u.x)
				var nrm := d.orthogonal()
				var hz := 0.026
				var c := u + nrm * sg * (PATH_W * 0.5 + hz + 0.004)
				if _place(c, Vector2(w, hz), d.angle(), lots, variant, 0.003, false):
					_shop(st, c, Vector2(w, hz), d.angle(), sg, rng, stats.get("homes"))
				x += w * 2.0 + 0.004
	# 3) дворы-кварталы вдоль улиц (ворота к улице), потом — в глубине кварталов (ворота к ближайшему проходу)
	var want := rng.randi_range(40, 45)
	for pi in paths.size():
		var pl: PackedVector2Array = paths[pi][0]
		var pw := float(paths[pi][1])
		for k in pl.size() - 1:
			var a := pl[k]
			var b := pl[k + 1]
			var dir := (b - a).normalized()
			var nrm := dir.orthogonal()
			var t := rng.randf_range(0.0, 0.04)
			while t < a.distance_to(b):
				var hx := rng.randf_range(0.075, 0.13)
				var c0 := a + dir * (t + hx)
				t += hx * 2.0 + rng.randf_range(0.015, 0.04)
				for sg: float in [-1.0, 1.0]:
					if stats["yards"] >= want or rng.randf() < 0.15:
						continue
					var hz := rng.randf_range(0.07, 0.11)
					var c := c0 + nrm * sg * (pw * 0.5 + hz + rng.randf_range(0.005, 0.01))
					# улица у центра двора — со стороны −nrm·sg, в осях двора (dir, −nrm) это сторона z = sg·hz
					if _place(c, Vector2(hx, hz), dir.angle(), lots, variant, 0.008, false):
						_yard(st, c, Vector2(hx, hz), dir.angle(), 2 if sg > 0.0 else 0, rng, stats)
	for i in 900:
		if stats["yards"] >= want:
			break
		var c := Vector2.from_angle(rng.randf() * TAU) * V_EDGE * 0.95 * sqrt(rng.randf())
		var pi := path_info(variant, c)
		var yaw := pi.w if pi.z >= 0.0 else _vr(variant, 300) * PI
		var h := Vector2(rng.randf_range(0.06, 0.12), rng.randf_range(0.055, 0.1)) * (1.0 if i < 450 else 0.75)
		if not _place(c, h, yaw, lots, variant, 0.008, false):
			continue
		# ворота — на сторону, ближайшую к улице или переулку
		var best := 0
		var bd := INF
		for s in 4:
			var m := c + (Vector2(0.0, -h.y - 0.02) if s == 0 else Vector2(h.x + 0.02, 0.0) if s == 1 else Vector2(0.0, h.y + 0.02) if s == 2 else Vector2(-h.x - 0.02, 0.0)).rotated(yaw)
			var dd := path_info(variant, m).x
			if dd < bd:
				bd = dd
				best = s
		_yard(st, c, h, yaw, best, rng, stats)
	# 4) отдельные дома, развалины и груды в промежутках
	var singles := rng.randi_range(24, 34)
	for i in 600:
		if singles <= 0:
			break
		var c := Vector2.from_angle(rng.randf() * TAU) * V_EDGE * 1.02 * sqrt(rng.randf())
		var pi := path_info(variant, c)
		var yaw := pi.w if pi.z >= 0.0 else rng.randf() * TAU
		var h := Vector2(rng.randf_range(0.024, 0.036), rng.randf_range(0.022, 0.03))
		if not _place(c, h, yaw, lots, variant, 0.01, false):
			continue
		singles -= 1
		var roll := rng.randf()
		if roll < 0.55:
			_t_house(st, c, h, yaw, 1 if rng.randf() < 0.85 else 2, _roof_col(rng), rng, stats.get("homes"))
			stats["houses"] += 1
		elif roll < 0.8:
			_t_ruin(st, c, h, yaw, rng.randf_range(0.025, 0.04), rng)
		else:
			_heap(st, c, h.x * 0.9, rng)
	# улицы — утоптанная полоса чуть над землёй внутри города (за краем их рисует пятно на рельефе: ground_mask)
	for p in paths:
		var pl: PackedVector2Array = p[0]
		for k in pl.size() - 1:
			var a := pl[k]
			var b := pl[k + 1]
			if a.length() > V_EDGE * outline(variant, a.angle()) * 1.02:
				continue
			_strip(st, a, b, float(p[1]), PATH, SINK + 0.0025, ID_STREET)
	# S9-07/S9-08: окраина (сады, поля, линия обороны) — отдельной сеткой на каждый посёлок (village_edge):
	# ручей долины-притока и река у каждого посёлка свои, а эта сетка общая для раскладки
	var marr := _scaled_arrays(st, V_UNIT)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, marr)
	# центры треугольников (старые единицы, x–z) — village_core вырезает по ним дворы на воде
	var vs: PackedVector3Array = marr[Mesh.ARRAY_VERTEX]
	var cen := PackedVector2Array()
	cen.resize(vs.size() / 3)
	for ti in cen.size():
		var q := (vs[ti * 3] + vs[ti * 3 + 1] + vs[ti * 3 + 2]) / (3.0 * V_UNIT)
		cen[ti] = Vector2(q.x, q.z)
	var edge := [lots.duplicate(), rng.state, cen]
	var homes: Array = stats.get("homes", [])
	stats.erase("homes")
	stats["models"] = homes.size()
	print_verbose("AdobeBuild village%d: дворов %d, домов %d, треугольников %d" % [variant, stats["yards"], stats["houses"], m.surface_get_array_len(0) / 3])
	_cmx.lock()
	if _vcache.has(key):   # параллельно собрал другой поток — берём его сетку
		m = _vcache[key]
	else:
		_vcache[key] = m
		_vcache[key + "_stats"] = stats
		_vcache[key + "_edge"] = edge
		_vcache[key + "_homes"] = homes
		_vcache[key + "_arrays"] = marr   # village_core cuts wet yards from these (no surface_get_arrays off the main thread)
	_cmx.unlock()
	return m


## S9-07/S9-08 (правка Kanta 23.10): кишлак на месте — у каждого посёлка свой ручей долины-притока (протока)
## и своя река, а сетка застройки общая для раскладки. water — вода у посёлка в осях сетки, старые единицы
## (Terrain3D.village_water): {"id" — ключ посёлка, "segs": [[a, b], …] — оси ручья, "w": полуширина его
## охранной полосы, "river": Callable(u) -> запас до охранной зоны реки (< 0 — в ней)}.
## Возвращает [застройка, окраина]: дворы и дома, задетые водой, вырезаны из общей сетки (village_core);
## сады, поля и линия обороны собраны заново с учётом воды (village_edge). Последние посёлки — в кэше
static var _icache := {}
static var ignore_water := false   # стенд (visual_bench --nowater): кадр «до» S9-07/S9-08


## Кишлак на месте уже собран (render3d собирает его заранее в фоне)
static func has_at(variant: int, water: Dictionary) -> bool:
	_cmx.lock()
	var ok := _icache.has(_at_key(variant, {} if ignore_water else water))
	_cmx.unlock()
	return ok


static func _at_key(variant: int, water: Dictionary) -> String:
	return "%d@%s" % [variant, str(water.get("id", ""))]


static func village_at(variant: int, water: Dictionary) -> Array:
	if ignore_water:
		water = {}
	var key := _at_key(variant, water)
	_cmx.lock()
	var have: Array = _icache.get(key, [])
	_cmx.unlock()
	if not have.is_empty():
		return have
	var trees := []
	var edge := village_edge(variant, water, trees)
	var out := [village_core(variant, water), edge, village_homes(variant, water) + trees]
	_cmx.lock()
	if _icache.size() > 12:
		_icache.clear()
	_icache[key] = out
	_cmx.unlock()
	return out


## VIS-01: model houses and wells of the village (VillageHouses.attach records), without those in the yards and
## lots that the settlement's water cuts out of the core mesh (village_core); props on no lot (the market, shop
## awnings) are dropped when the water's guard reaches them
static func village_homes(variant: int, water := {}) -> Array:
	village(variant)
	_cmx.lock()
	var homes: Array = _vcache.get("village%d_homes" % variant, [])
	var edge: Array = _vcache.get("village%d_edge" % variant, [[], 0, PackedVector2Array()])
	_cmx.unlock()
	if water.is_empty() or homes.is_empty():
		return homes
	var out := []
	for hm in homes:
		var q: Vector2 = hm[1]
		var wet := false
		var in_lot := false
		for l in edge[0]:
			var lc := (q - (l[0] as Vector2)).rotated(-float(l[2]))
			var hh: Vector2 = l[1] + Vector2.ONE * 0.004
			if absf(lc.x) <= hh.x and absf(lc.y) <= hh.y:
				in_lot = true
				wet = _wet_box(water, l[0], l[1], l[2], 0.004)
				break
		if not in_lot:   # the square's market and stalls stand on no lot: each keeps off the water on its own
			wet = _wet_box(water, q, Vector2.ONE * 0.02, 0.0, 0.004)
		if not wet:
			out.append(hm)
	return out


## S9-07: общая сетка застройки без дворов и домов, задетых водой посёлка (вырезаются треугольники с центром
## в их участке: участки не пересекаются друг с другом и с улицами — _place). Сухо — сама общая сетка
static func village_core(variant: int, water := {}) -> ArrayMesh:
	var base := village(variant)
	if water.is_empty():
		return base
	_cmx.lock()
	var edge: Array = _vcache.get("village%d_edge" % variant, [[], 0, PackedVector2Array()])
	_cmx.unlock()
	var cut := []
	for l in edge[0]:
		if _wet_box(water, l[0], l[1], l[2], 0.004):
			var hh: Vector2 = l[1] + Vector2.ONE * 0.004
			cut.append([l[0], hh, l[2], hh.length_squared()])
	if cut.is_empty():
		return base
	_cmx.lock()
	var arr: Array = (_vcache["village%d_arrays" % variant] as Array).duplicate()
	_cmx.unlock()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cen: PackedVector2Array = edge[2]
	var runs := PackedInt32Array()   # оставляемые отрезки вершин [начало, конец)
	var start := 0
	for ti in cen.size():
		var q := cen[ti]
		var hit := false
		for l in cut:
			var d: Vector2 = q - (l[0] as Vector2)
			if d.length_squared() > float(l[3]):
				continue
			var lc := d.rotated(-float(l[2]))
			if absf(lc.x) <= l[1].x and absf(lc.y) <= l[1].y:
				hit = true
				break
		if hit:
			if ti * 3 > start:
				runs.append_array([start, ti * 3])
			start = ti * 3 + 3
	if vs.size() > start:
		runs.append_array([start, vs.size()])
	for ai in arr.size():
		var a = arr[ai]
		if a == null or not (a is PackedVector3Array or a is PackedColorArray or a is PackedVector2Array or a is PackedFloat32Array):
			continue
		var per := roundi(float(a.size()) / vs.size())   # тангенсы — по 4 числа на вершину
		var b = a.slice(0, 0)
		for ri in runs.size() / 2:
			b.append_array(a.slice(runs[ri * 2] * per, runs[ri * 2 + 1] * per))
		arr[ai] = b
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## S9-07/S9-08: окраина кишлака — сады за дувалами, поля с межами, линия обороны. Сады и поля на воду
## не встают, окоп и бруствер прерываются над ручьём (как проход для тропы), позиция орудия сдвигается
## по линии на сухое, пост у тропы на воде не ставится. Без воды (water пуст) — прежняя раскладка:
## генератор продолжает с того же состояния, что после застройки (village)
static var edge_log_on := false   # проверка S9-07/S9-08 (tools/village_water): что поставлено на окраине
static var edge_log := []         # ["garden", c, h, yaw] | ["trench", a, b] | ["pit", c] | ["post", c], старые единицы


## The outskirts mesh of variant at its water (see above). trees — an Array to append the orchards' tree records
## to (VillageHouses.attach records, old units), or null when only the mesh is wanted
static func village_edge(variant: int, water := {}, trees = null) -> ArrayMesh:
	var key := "village%d" % variant
	village(variant)
	_cmx.lock()
	var edge: Array = _vcache.get(key + "_edge", [])
	var dry: ArrayMesh = _vcache.get(key + "_edge_dry") if water.is_empty() else null
	var dry_trees: Array = _vcache.get(key + "_edge_dry_trees", [])
	_cmx.unlock()
	if dry != null and not edge_log_on:
		if trees != null:
			(trees as Array).append_array(dry_trees)
		return dry
	var tr := []   # the orchards' trees as model records (VillageHouses.ORCHARD), not boxes
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	rng.state = int(edge[1])
	var lots: Array = (edge[0] as Array).duplicate()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 5) по краю: сады за дувалами с рядами деревьев и поля с межами — в секторах зелени, не на линии обороны
	var gardens := rng.randi_range(9, 14)
	for i in (120 if water.is_empty() else 240):   # S9-07: часть мест у ручья отпадает — попыток вдвое больше
		if gardens <= 0:
			break
		var ang := rng.randf() * TAU
		if absf(angle_difference(ang, PI)) < def_arc(variant) + 0.3 or _sect(variant, ang) < 0.5:
			continue
		var c := Vector2.from_angle(ang) * V_EDGE * outline(variant, ang) * rng.randf_range(1.12, 1.4)
		var h := Vector2(rng.randf_range(0.06, 0.11), rng.randf_range(0.05, 0.09))
		var yaw := ang + rng.randf_range(-0.3, 0.3)
		if _wet_box(water, c, h, yaw, 0.01) or not _place(c, h, yaw, lots, variant, 0.02, true):
			continue   # S9-07: не на ручье и не в охранной зоне реки
		gardens -= 1
		if edge_log_on:
			edge_log.append(["garden", c, h, yaw])
		if rng.randf() < 0.55:
			_orchard(st, c, h, yaw, rng, tr)
		else:
			_field(st, c, h, yaw, rng)
	_defence(st, variant, rng, water)
	var m := _scaled(st, V_UNIT)
	if water.is_empty():
		_cmx.lock()
		_vcache[key + "_edge_dry"] = m
		_vcache[key + "_edge_dry_trees"] = tr
		_cmx.unlock()
	if trees != null:
		(trees as Array).append_array(tr)
	return m


## S9-07/S9-08: повёрнутый прямоугольник (центр c, полуразмер h, старые единицы) с запасом m задевает воду
static func _wet_box(water: Dictionary, c: Vector2, h: Vector2, yaw: float, m: float) -> bool:
	if water.is_empty():
		return false
	var e := h + Vector2.ONE * (float(water["w"]) + m)
	for s in water["segs"]:
		if _seg_box(((s[0] as Vector2) - c).rotated(-yaw), ((s[1] as Vector2) - c).rotated(-yaw), e):
			return true
	var rv: Callable = water.get("river", Callable())
	if rv.is_valid():
		var ax := Vector2.from_angle(yaw)
		var az := ax.orthogonal()
		for cx: float in [-1.0, 0.0, 1.0]:
			for cz: float in [-1.0, 0.0, 1.0]:
				if float(rv.call(c + ax * h.x * cx + az * h.y * cz)) < m:
					return true
	return false


## S9-08: отрезок a–b (ряд мешков, окоп) с запасом m задевает воду
static func _wet_seg(water: Dictionary, a: Vector2, b: Vector2, m: float) -> bool:
	return _wet_box(water, (a + b) * 0.5, Vector2(a.distance_to(b) * 0.5, 0.0), (b - a).angle(), m)


## Высота оси главной улицы над x (в осях посёлка) и её направление — как в _build_paths
static func _main_y(variant: int, x: float) -> float:
	var v := float(variant)
	var y := 0.075 * sin(x * 2.6 + v * 1.7) + 0.035 * sin(x * 6.3 + v * 0.9 + 1.0)
	var y0 := 0.075 * sin(v * 1.7) + 0.035 * sin(v * 0.9 + 1.0)
	return y - y0 * (1.0 - smoothstep(0.0, 0.7, absf(x)))


static func _main_dir(variant: int, x: float) -> Vector2:
	return Vector2(0.02, _main_y(variant, x + 0.01) - _main_y(variant, x - 0.01)).normalized()


## Занять место под повёрнутый прямоугольник (центр c, полуразмер h, угол yaw), если оно свободно:
## внутри контура (outside = true — можно за краем), не на площади, не на улице, не на соседе (зазор gap)
static func _place(c: Vector2, h: Vector2, yaw: float, lots: Array, variant: int, gap: float, outside: bool) -> bool:
	var ax := Vector2.from_angle(yaw)
	var az := ax.rotated(PI * 0.5)
	if not outside:
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var q := c + ax * h.x * cx + az * h.y * cz
				if q.length() > V_EDGE * outline(variant, q.angle()) * 1.04:
					return false
	# площадь: ближайшая к центру точка прямоугольника
	var lc := (-c).rotated(-yaw)
	if Vector2(clampf(lc.x, -h.x, h.x), clampf(lc.y, -h.y, h.y)).distance_to(lc) < SQ_R + 0.01:
		return false
	# улицы: отрезки из клеток сетки, которые накрывает прямоугольник
	var r := h.length()
	var g := _grid(variant)
	var seen := {}
	for gx in range(floori((c.x - r) / PG), floori((c.x + r) / PG) + 1):
		for gy in range(floori((c.y - r) / PG), floori((c.y + r) / PG) + 1):
			for s in g.get(Vector2i(gx, gy), []):
				var a: Vector2 = s[0]
				var ab: Vector2 = s[1]
				var sk := Vector3(a.x, a.y, ab.x)
				if seen.has(sk):
					continue
				seen[sk] = true
				var e := Vector2.ONE * (float(s[2]) * 0.5 + 0.004)
				if _seg_box((a - c).rotated(-yaw), (a + ab - c).rotated(-yaw), h + e):
					return false
	for l in lots:
		if _obb_hit(c, h, yaw, l[0], l[1], l[2], gap):
			return false
	lots.append([c, h, yaw])
	return true


## Отрезок a–b (в осях прямоугольника) задевает прямоугольник с полуразмером h
static func _seg_box(a: Vector2, b: Vector2, h: Vector2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for i in 2:
		if absf(d[i]) < 1e-9:
			if a[i] < -h[i] or a[i] > h[i]:
				return false
			continue
		var ta := (-h[i] - a[i]) / d[i]
		var tb := (h[i] - a[i]) / d[i]
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


## Два повёрнутых прямоугольника ближе m друг к другу (теорема о разделяющей оси)
static func _obb_hit(c1: Vector2, h1: Vector2, y1: float, c2: Vector2, h2: Vector2, y2: float, m: float) -> bool:
	var u1 := Vector2.from_angle(y1)
	var v1 := u1.rotated(PI * 0.5)
	var u2 := Vector2.from_angle(y2)
	var v2 := u2.rotated(PI * 0.5)
	var d := c2 - c1
	for ax: Vector2 in [u1, v1, u2, v2]:
		var r1 := h1.x * absf(u1.dot(ax)) + h1.y * absf(v1.dot(ax))
		var r2 := h2.x * absf(u2.dot(ax)) + h2.y * absf(v2.dot(ax))
		if absf(d.dot(ax)) > r1 + r2 + m:
			return false
	return true


## Коробка в осях постройки: центр основания (lx, lz) в осях (c, yaw), размер s (x, видимая высота над
## землёй, z), низ уходит под землю (меш утоплен), y0 — подъём низа над землёй
static func _ob(st: SurfaceTool, c: Vector2, yaw: float, lx: float, lz: float, s: Vector3, side: Color, top: Color, y0 := 0.0) -> void:
	var p := c + Vector2(lx, lz).rotated(yaw)
	var ax := Vector2.from_angle(yaw) * s.x * 0.5
	var az := Vector2.from_angle(yaw).rotated(PI * 0.5) * s.z * 0.5
	var q := [p - ax - az, p + ax - az, p + ax + az, p - ax + az]
	var yb := 0.0 if y0 <= 0.0 else SINK + y0
	var yt := SINK + y0 + s.y
	_quad(st, Vector3(q[0].x, yt, q[0].y), Vector3(q[1].x, yt, q[1].y), Vector3(q[2].x, yt, q[2].y), Vector3(q[3].x, yt, q[3].y), top)
	for i in 4:
		var a: Vector2 = q[(i + 1) % 4]
		var b: Vector2 = q[i]
		_quad(st, Vector3(a.x, yb, a.y), Vector3(b.x, yb, b.y), Vector3(b.x, yt, b.y), Vector3(a.x, yt, a.y), side)


## Compound wall (duval) in the building's axes from a to b (local coordinates), base thickness t, height h:
## a battered mud wall (top WALL_TAPER of the base) under a rounded coping, its top eroded in shallow dips, a
## damp darker foot and a sun-bleached crest in the vertex colours (adobe.gdshader adds plaster wear, fallen
## plaster with mud-brick courses, cracks and rain streaks). ragged — a broken top, pieces of different height
## joined by jagged slopes; breach — a gap in the middle with a heap of fallen clay. The village's rng is drawn
## exactly as the old box walls drew it (the layout and the edge that continue the same generator stay put);
## the erosion has a generator of its own, seeded by the wall's place.
static func _t_wall(st: SurfaceTool, c: Vector2, yaw: float, a: Vector2, b: Vector2, t: float, h: float, col: Color, rng: RandomNumberGenerator, ragged := false, breach := false) -> void:
	var len := a.distance_to(b)
	if len < 0.002:
		return
	var n := maxi(1, int(len / 0.022)) if ragged else 1
	var hh := h
	var tops := PackedFloat32Array()   # height of each piece, -1 for the breach
	for k in n:
		var f0 := float(k) / n
		var f1 := float(k + 1) / n
		if breach and n >= 3 and k == n / 2:
			_heap(st, c + a.lerp(b, (f0 + f1) * 0.5).rotated(yaw), 0.014, rng)
			tops.append(-1.0)
			continue
		if ragged:
			hh = clampf(hh + rng.randf_range(-0.35, 0.35) * h, h * 0.3, h)
		tops.append(hh)
	var wr := RandomNumberGenerator.new()
	wr.seed = hash(Vector2i(roundi((a.x + b.x + c.x * 3.0) * 1e5), roundi((a.y + b.y + c.y * 3.0) * 1e5)))
	# the top's outline as runs of [share of the length, height] points; a breach splits the wall in two runs
	var runs := []
	var pts := []
	for k in n:
		var f0 := float(k) / n
		var f1 := float(k + 1) / n
		if tops[k] < 0.0:
			if not pts.is_empty():
				pts.append([f0, tops[k - 1] * wr.randf_range(0.25, 0.45)])
				runs.append(pts)
			pts = []
			continue
		if pts.is_empty():
			var y0 := tops[k] if k == 0 else tops[k] * wr.randf_range(0.25, 0.45)
			pts.append([f0, y0])
		if ragged:
			_ragged_top(pts, f0, f1, len, h, tops, k, wr)
		else:
			var m := maxi(1, int(len / WALL_SEG))
			for i in range(1, m):
				var dip := wr.randf_range(0.8, 0.9) if wr.randf() < 0.14 else wr.randf_range(0.96, 1.03)
				pts.append([float(i) / m, h * dip])
		if k == n - 1:
			pts.append([1.0, tops[k]])
	if not pts.is_empty():
		runs.append(pts)
	for r: Array in runs:
		_wall_run(st, c, yaw, a, b, t, r, col, true, ragged)


## Broken top of piece k (shares f0…f1 of a wall `len` long, full height h) of a ragged wall, appended to pts:
## points at irregular spacing whose height follows the pieces' levels (tops, eased from one piece to the next)
## under three octaves of noise, with V-shaped bites and sheer breaks where a block of mud brick came away. The
## old outline peaked in every piece's middle and dipped at every joint: a regular saw that read as stair steps.
## Only wr (the wall's own generator) is drawn. The piece's end point is added when another piece follows.
static func _ragged_top(pts: Array, f0: float, f1: float, len: float, h: float, tops: PackedFloat32Array, k: int,
		wr: RandomNumberGenerator) -> void:
	var n := tops.size()
	var prev := tops[k - 1] if k > 0 and tops[k - 1] >= 0.0 else tops[k]
	var next := tops[k + 1] if k < n - 1 and tops[k + 1] >= 0.0 else tops[k]
	var sd := wr.randf() * 40.0
	var f := f0
	while true:
		f += wr.randf_range(0.003, 0.008) / len
		if f >= f1 - 0.002 / len:
			break
		var u := (f - f0) / (f1 - f0)
		var lv := lerpf((prev + tops[k]) * 0.5, tops[k], smoothstep(0.0, 0.5, u)) if u < 0.5 \
			else lerpf(tops[k], (tops[k] + next) * 0.5, smoothstep(0.5, 1.0, u))
		var d := f * len
		var y := lv + (_vn1(d / 0.009, sd) - 0.5) * 0.4 * h + (_vn1(d / 0.0032, sd + 5.0) - 0.5) * 0.14 * h \
			+ (_vn1(d / 0.0013, sd + 9.0) - 0.5) * 0.05 * h   # the crumbled lip of each brick course
		var roll := wr.randf()
		if roll < 0.12:   # a bite: the top dips sharply and climbs back
			pts.append([f, clampf(y * wr.randf_range(0.45, 0.7), h * 0.15, h)])
			continue
		if roll < 0.22:   # a sheer break: a near-vertical edge between two levels
			var y2 := y * wr.randf_range(0.65, 0.85) if wr.randf() < 0.5 else minf(y * wr.randf_range(1.15, 1.35), h)
			pts.append([f, clampf(y, h * 0.15, h)])
			f += 0.0009 / len
			pts.append([f, clampf(y2, h * 0.15, h)])
			continue
		pts.append([f, clampf(y, h * 0.15, h)])
	if k < n - 1 and tops[k + 1] >= 0.0:
		pts.append([f1, clampf((tops[k] + next) * 0.5 * wr.randf_range(0.85, 1.0), h * 0.15, h)])


## Smooth value noise, 0…1, of one coordinate and a seed: no generator, so it is the same in any thread and order
static func _vn1(x: float, sd: float) -> float:
	var i := floorf(x)
	var t := x - i
	t = t * t * (3.0 - 2.0 * t)
	var a := sin((i + sd * 17.13) * 12.9898 + 4.1) * 43758.5453
	var b := sin((i + 1.0 + sd * 17.13) * 12.9898 + 4.1) * 43758.5453
	return lerpf(a - floorf(a), b - floorf(b), t)


## One unbroken stretch of a compound wall: pts — [share of a→b, height] along its top. Sections of the
## profile (battered sides, damp foot band, rounded coping smoothed across its crest) between consecutive
## points; the stretch's ends get end caps and reach t/2 past a wall end, so walls overlap at the corners
const WALL_TAPER := 0.72   ## a compound wall's top is this share of its base thickness
const COPING := 0.22       ## the rounded coping rises this share of the base thickness above its shoulders
const DAMP := 0.0055       ## the damp, dirtier foot of a wall: this high above the ground, old units (~0.5 m)
const WALL_SEG := 0.026    ## an intact wall's eroded top: one height point per this length, old units (~2.4 m)


## broken — a ruined wall's torn top (ragged _t_wall): no rounded coping, the two faces broken off at different
## heights that change along the wall and a low ridge off the middle, flat-shaded, so the top reads as snapped
## mud brick rather than a smooth roll following the outline.
static func _wall_run(st: SurfaceTool, c: Vector2, yaw: float, a: Vector2, b: Vector2, t: float, pts: Array, col: Color, ext := true, broken := false) -> void:
	if pts.size() < 2:
		return
	var len := a.distance_to(b)
	var dir := (b - a) / len
	var nrm := dir.orthogonal()
	var damp := col.darkened(0.3)
	var top := col.lightened(0.06)
	var crest := col.lightened(0.14) if not broken else col.lightened(0.03)   # a torn top: no bleached crest
	var sd := float(absi(hash(Vector2i(roundi(a.x * 1e5), roundi(b.y * 1e5)))) % 991)
	var secs := []   # per point: [left rows, right rows] of Vector3, bottom to crest
	for i in pts.size():
		var f: float = pts[i][0]
		var y: float = pts[i][1]
		var along := f * len
		if ext and i == 0 and f <= 0.0:
			along -= t * 0.5
		elif ext and i == pts.size() - 1 and f >= 1.0:
			along += t * 0.5
		var o := a + dir * along
		var yd := minf(DAMP, y * 0.4)
		var hw := [t * 0.5, t * 0.5, lerpf(t * 0.5, t * WALL_TAPER * 0.5, yd / maxf(y, 0.0001)), t * WALL_TAPER * 0.5, 0.0]
		var ys := [y, y]   # each face's broken height
		var ridge := t * COPING
		var off := 0.0     # the ridge's offset across the wall
		if broken:
			var u := _vn1(along / 0.0024, sd) - 0.5
			var drop := y * 0.07 * (0.4 + _vn1(along / 0.0041, sd + 3.0))
			ys = [y - drop * (0.5 + u), y - drop * (0.5 - u)]
			ridge = t * 0.04 * _vn1(along / 0.0017, sd + 6.0)
			off = (_vn1(along / 0.0033, sd + 9.0) - 0.5) * t * WALL_TAPER * 0.5
		var side := []
		for si in 2:
			var s := -1.0 if si == 0 else 1.0
			var hy := [0.0, SINK, SINK + yd, SINK + float(ys[si]), SINK + y + ridge]
			var rows := []
			for j in 5:
				var q := c + (o + nrm * (s * float(hw[j]) if j < 4 else off)).rotated(yaw)
				rows.append(Vector3(q.x, float(hy[j]), q.y))
			side.append(rows)
		secs.append(side)
	var cols := [damp, damp, col, top, crest]
	for i in secs.size() - 1:
		for s in 2:
			var p: Array = secs[i][s]
			var q: Array = secs[i + 1][s]
			for j in 4:
				# the coping is rounded: smooth across its crest; a torn top keeps its facets
				st.set_smooth_group(7 if j == 3 and not broken else -1)
				var v := [p[j], q[j], q[j + 1], p[j + 1]]
				var cs := [cols[j], cols[j], cols[j + 1], cols[j + 1]]
				if s == 0:
					v = [q[j], p[j], p[j + 1], q[j + 1]]
				for k: int in [0, 2, 1, 0, 3, 2]:
					st.set_color(cs[k])
					st.add_vertex(v[k])
	# end caps: the profile polygon (left rows up, crest, right rows down), fanned from its first point
	for e: int in [0, secs.size() - 1]:
		var l: Array = secs[e][0]
		var r: Array = secs[e][1]
		var ring := [l[0], l[1], l[2], l[3], l[4], r[3], r[2], r[1], r[0]]
		var rc := [damp, damp, col, top, crest, top, col, damp, damp]
		st.set_smooth_group(-1)
		for k in range(1, ring.size() - 1):
			var tri := [0, k, k + 1] if e == 0 else [0, k + 1, k]
			for ti: int in tri:
				st.set_color(rc[ti])
				st.add_vertex(ring[ti])


## Gate of a compound wall in the yard's axes: two adobe piers with rounded caps either side of the passage,
## a timber frame (posts and a lintel under a small mud roof) and two plank leaves — shut, or one swung in.
## g — the passage centre on the wall line (yard axes), dirv — along the wall, gw — half the passage width,
## state — the yard's (0 whole, 1 damaged: a leaf fallen, 2 ruined: no frame, the lintel on the ground).
## Its own generator: the village's rng is not drawn.
static func _gate(st: SurfaceTool, c: Vector2, yaw: float, g: Vector2, dirv: Vector2, gw: float, t: float, wh: float, state: int, shut: bool, col: Color) -> void:
	var gr := RandomNumberGenerator.new()
	gr.seed = hash(Vector2i(roundi((c.x + g.x) * 1e5), roundi((c.y + g.y) * 1e5))) + 3
	var inw := -g.normalized() if g.length() > 0.0001 else Vector2.ZERO   # towards the yard
	var ph := wh * (1.2 if state < 2 else gr.randf_range(0.55, 0.85))
	for s: float in [-1.0, 1.0]:
		var p0 := g + dirv * s * (gw - t * 0.5)
		var p1 := g + dirv * s * (gw + t * 1.1)
		_wall_run(st, c, yaw, p0, p1, t * 1.35, [[0.0, ph], [1.0, ph]], col.lightened(0.03), false)
	if state == 2:   # the lintel lies across the rubble of the passage
		var la := g + dirv * gw * 0.9 + inw * 0.004
		var lb := g - dirv * gw * 0.7 + inw * 0.012
		_beam(st, c, yaw, Vector3(la.x, SINK + 0.002, la.y), Vector3(lb.x, SINK + 0.004, lb.y), 0.0024, WOOD_DARK)
		return
	var fh := wh * 1.12
	for s: float in [-1.0, 1.0]:   # timber posts against the piers
		var q := g + dirv * s * (gw - 0.0012)
		_beam(st, c, yaw, Vector3(q.x, SINK - 0.002, q.y), Vector3(q.x, SINK + fh, q.y), 0.0026, WOOD)
	var l0 := g - dirv * (gw + t * 0.9)
	var l1 := g + dirv * (gw + t * 0.9)
	_beam(st, c, yaw, Vector3(l0.x, SINK + fh + 0.0012, l0.y), Vector3(l1.x, SINK + fh + 0.0012, l1.y), 0.0026, WOOD)
	var roof := col.lightened(0.05)   # a small mud roof on the lintel
	_ob(st, c + g.rotated(yaw), yaw + dirv.angle(), 0.0, 0.0, Vector3(gw * 2.0 + t * 2.4, 0.003, t * 1.5), roof, roof.lightened(0.06), fh + 0.0025)
	var lw := gw * 0.98
	if shut:
		for s: float in [-1.0, 1.0]:   # two leaves meeting in the middle
			var m := g + dirv * s * lw * 0.5 + inw * 0.001
			_beam(st, c, yaw, Vector3(m.x, SINK - 0.001, m.y), Vector3(m.x, SINK + wh * 1.02, m.y), 0.0, WOOD_DARK,
				Vector2(lw * 0.96, 0.0013), dirv)
	elif state == 0 and gr.randf() < 0.6:   # one leaf swung into the yard
		var hinge := g + dirv * lw
		var open := (inw * 0.8 - dirv * 0.6).normalized()
		var m := hinge + open * lw * 0.5
		_beam(st, c, yaw, Vector3(m.x, SINK - 0.001, m.y), Vector3(m.x, SINK + wh * 1.02, m.y), 0.0, WOOD_DARK,
			Vector2(lw * 0.96, 0.0013), open)
	elif state == 1:   # a leaf torn off, lying in the passage
		var m := g + inw * 0.006 + dirv * gw * 0.2
		_beam(st, c, yaw, Vector3(m.x, SINK + 0.0007, m.y) - Vector3(dirv.x, 0.0, dirv.y) * lw * 0.5,
			Vector3(m.x, SINK + 0.0007, m.y) + Vector3(dirv.x, 0.0, dirv.y) * lw * 0.5, 0.0, WOOD_DARK,
			Vector2(wh * 0.95, 0.0013), Vector2(-dirv.y, dirv.x))


## Timber (or a plank) in the building's axes from p (Vector3, x/z local) to q: square section w thick, or with
## sec (width, thickness) a plank whose width lies along `across` (local, horizontal). Flat-shaded box
static func _beam(st: SurfaceTool, c: Vector2, yaw: float, p: Vector3, q: Vector3, w: float, col: Color, sec := Vector2.ZERO, across := Vector2.ZERO) -> void:
	var d := q - p
	if d.length() < 0.00001:
		return
	var dn := d.normalized()
	var u: Vector3
	if across != Vector2.ZERO:
		u = Vector3(across.x, 0.0, across.y).normalized()
	else:
		u = dn.cross(Vector3.UP)
		if u.length() < 0.001:
			u = Vector3.RIGHT
		u = u.normalized()
	var v := dn.cross(u).normalized()
	var su := (sec.x if sec != Vector2.ZERO else w) * 0.5
	var sv := (sec.y if sec != Vector2.ZERO else w) * 0.5
	var k := []
	for e: Vector3 in [p, q]:
		for f: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var l := e + u * su * f.x + v * sv * f.y
			var wpt := c + Vector2(l.x, l.z).rotated(yaw)
			k.append(Vector3(wpt.x, l.y, wpt.y))
	var top := col.lightened(0.06)
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, k[i], k[4 + i], k[4 + j], k[j], top if i == 0 else col)
	_quad(st, k[0], k[1], k[2], k[3], col)
	_quad(st, k[7], k[6], k[5], k[4], col)


## Дом в осях (c, yaw): плоская глиняная крыша, 1–2 этажа, иногда парапет, надстройка, копоть; дверь —
## тёмный проём на стороне z = +h.y (во двор). VIS-01: with homes (an Array) the house is not drawn but recorded
## there for VillageHouses (_home); rng is drawn exactly as before either way, so the layout and the edge that
## continues the same generator do not move
static func _t_house(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, floors: int, roof: Color, rng: RandomNumberGenerator, homes = null) -> void:
	var hh := rng.randf_range(0.03, 0.038) if floors == 1 else rng.randf_range(0.058, 0.07)
	var parapet := floors == 2 or rng.randf() < 0.3
	var bx := 0.0
	var sx := 0.0
	if not parapet and floors == 1 and h.x > 0.03 and rng.randf() < 0.25:   # a balakhana (upper room) over part of the roof
		bx = h.x * rng.randf_range(0.35, 0.5)
		sx = (h.x - bx) * (1.0 if rng.randf() < 0.5 else -1.0)
	var door := rng.randf_range(-0.4, 0.4) * h.x
	var soot := rng.randf() < 0.15
	var sp := Vector2(rng.randf_range(-0.3, 0.3) * h.x, rng.randf_range(-0.3, 0.3) * h.y) if soot else Vector2.ZERO
	if homes != null:
		_home(homes, c, h, yaw, hh, floors)
		return
	var wall := T_WALL.lerp(roof, 0.4).darkened(0.04)
	_ob(st, c, yaw, 0.0, 0.0, Vector3(h.x * 2.0, hh, h.y * 2.0), wall, roof)
	if parapet:
		var t := 0.005
		for s: float in [-1.0, 1.0]:
			_ob(st, c, yaw, 0.0, s * (h.y - t * 0.5), Vector3(h.x * 2.0, 0.007, t), wall, roof.lightened(0.04), hh)
			_ob(st, c, yaw, s * (h.x - t * 0.5), 0.0, Vector3(t, 0.007, h.y * 2.0 - 2.0 * t), wall, roof.lightened(0.04), hh)
	elif bx > 0.0:
		_ob(st, c, yaw, sx, 0.0, Vector3(bx * 2.0, 0.026, h.y * 1.6), wall, roof.darkened(0.04), hh)
	_ob(st, c, yaw, door, h.y + 0.0015, Vector3(0.011, minf(hh * 0.6, 0.024), 0.003), T_DARK, T_DARK)
	if soot:   # soot
		_ob(st, c, yaw, sp.x, sp.y, Vector3(h.x * 0.9, 0.001, h.y * 0.8), BURNT, BURNT, hh)


const M_PER_UNIT := 6.94 / 640.0   ## one metre of a model (≈ the fort's preview unit, 6.94 px) in old units

## VIS-01: a house lot as model houses for VillageHouses — [variant, centre, yaw, scale old units per metre]. A long
## lot (yard houses run the whole wall) is split into 1–3 houses of different variants and heights; each is fitted
## to its part (at most 25 % off the model's proportions, height near the box house's). Its own generator, seeded
## by the lot, so the village's generator is untouched
static func _home(homes: Array, c: Vector2, h: Vector2, yaw: float, hh: float, floors: int) -> void:
	var hr := RandomNumberGenerator.new()
	hr.seed = hash(Vector2i(roundi(c.x * 1e5), roundi(c.y * 1e5)))
	if h.y > h.x:   # long side along the model's X
		h = Vector2(h.y, h.x)
		yaw += PI * 0.5
	var n := clampi(roundi(h.x / (h.y * 1.4)), 1, 3)
	var seg := h.x * 2.0 / n
	for k in n:
		var f := floors if k == 0 or hr.randf() < 0.5 else 3 - floors
		var v := VillageHouses.pick(seg, h.y * 2.0, f, hr)
		var ms := VillageHouses.size(v)
		var sx := seg * 0.94 / ms.x
		var sz := h.y * 2.0 / ms.z
		var s := minf(sx, sz)
		sx = minf(sx, s * 1.25)
		sz = minf(sz, s * 1.25)
		var ht := hh if f == floors else (0.034 if f == 1 else 0.064)
		var sy := clampf(ht / ms.y, s * 0.8, s * 1.4)
		var flip := PI if hr.randf() < 0.5 else 0.0
		homes.append([v, c + Vector2(-h.x + seg * (k + 0.5), 0.0).rotated(yaw), yaw + flip, Vector3(sx, sy, sz)])


## Дом без крыши: четыре стены рваным верхом сплошной линией, внутри груда глины. Charred roof beams lie
## across the heap and stick out over the broken walls (own generator: the village's rng is drawn as before)
static func _t_ruin(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, hh: float, rng: RandomNumberGenerator) -> void:
	var t := 0.007
	var corners := [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]
	var down := rng.randi() % 4
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var inw := -((a + b) * 0.5).normalized() * t * 0.5
		if i == down:
			_t_wall(st, c, yaw, a + inw, a.lerp(b, 0.35) + inw, t, hh * 0.5, T_WALL, rng, true)
			continue
		_t_wall(st, c, yaw, a + inw, b + inw, t, hh, T_WALL, rng, true)
	var hc := c + Vector2(rng.randf_range(-0.3, 0.3) * h.x, 0.0).rotated(yaw)
	_heap(st, hc, minf(h.x, h.y) * 0.75, rng)
	var br := RandomNumberGenerator.new()
	br.seed = hash(Vector2i(roundi(c.x * 1e5), roundi(c.y * 1e5))) + 5
	for k in br.randi_range(1, 3):
		var ang := br.randf() * TAU
		var l := maxf(h.x, h.y) * br.randf_range(1.0, 1.6)
		var m := (hc - c).rotated(-yaw) + Vector2(br.randf_range(-0.3, 0.3) * h.x, br.randf_range(-0.3, 0.3) * h.y)
		var e := Vector2.from_angle(ang) * l * 0.5
		var y0 := SINK + br.randf_range(0.002, 0.012)
		var y1 := SINK + br.randf_range(0.004, hh * 0.8)
		_beam(st, c, yaw, Vector3(m.x - e.x, y0, m.y - e.y), Vector3(m.x + e.x, y1, m.y + e.y), 0.0022,
			BURNT if br.randf() < 0.6 else WOOD_DARK)


## Груда глины и обломков: a lumpy mound of fallen mud brick (rings of jittered points, darker in the hollows,
## lighter on top), clay chunks round it and a broken beam now and then. The village's rng gives the mound's
## turn and tone and the two big chunks as before; the shape has a generator of its own
static func _heap(st: SurfaceTool, c: Vector2, r: float, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf() * TAU
	var col := T_RUBBLE.darkened(rng.randf_range(0.0, 0.08))
	var hr := RandomNumberGenerator.new()
	hr.seed = hash(Vector2i(roundi(c.x * 1e5), roundi(c.y * 1e5))) + 7
	var mh := minf(0.013, r * 0.45)
	_mound(st, c, Vector2(r * 1.05, r * 0.85), mh, yaw, col, hr)
	for k in 2:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.9, 1.3)
		var cc := BURNT if rng.randf() < 0.25 else col
		_clod(st, p, rng.randf() * TAU, Vector3(0.008, 0.005, 0.006), cc, cc.lightened(0.05))
	for k in hr.randi_range(4, 8):   # loose bricks and clods
		var p := c + Vector2.from_angle(hr.randf() * TAU) * r * hr.randf_range(0.7, 1.5)
		var cc := col.darkened(hr.randf_range(-0.05, 0.12))
		_clod(st, p, hr.randf() * TAU, Vector3(0.0036, 0.0022, 0.0026) * hr.randf_range(0.8, 1.4), cc, cc.lightened(0.06))
	for k in hr.randi_range(7, 11):   # broken bricks and clods half buried in the heap's slopes
		var d := sqrt(hr.randf()) * 0.8
		var p := c + Vector2.from_angle(hr.randf() * TAU) * r * 0.85 * d
		var sz := Vector3(0.0042, 0.0026, 0.0032) * hr.randf_range(0.8, 1.7)
		var cc := BURNT if hr.randf() < 0.15 else col.darkened(hr.randf_range(-0.08, 0.1))
		_clod(st, p, hr.randf() * TAU, sz, cc, cc.lightened(0.06), mh * (1.0 - d * d) * 0.85 - sz.y * 0.4)
	if hr.randf() < 0.45:
		var e := Vector2.from_angle(hr.randf() * TAU) * r * 0.8
		_beam(st, c, 0.0, Vector3(-e.x, SINK + 0.003, -e.y), Vector3(e.x, SINK + hr.randf_range(0.006, 0.014), e.y), 0.002, WOOD_DARK)


## Broken clod of mud brick at c (turned by yaw, size s as _ob's box): a chipped, uneven lump instead of a
## box, whose clean edges read as building blocks at gameplay height. A seven-sided outline in three rings
## (the foot sunk a little, a bulging middle, a smaller tilted top), each corner pushed in or out by a hash of
## the place, so no generator is drawn (the village's rng stays as the boxes left it). Flat-shaded. y0 — the
## foot's height above the ground (a clod lying on a heap's slope).
static func _clod(st: SurfaceTool, c: Vector2, yaw: float, s: Vector3, side: Color, top: Color, y0 := 0.0) -> void:
	var n := 7
	var sd := float(absi(hash(Vector2i(roundi(c.x * 1e5), roundi(c.y * 1e5)))) % 997)
	var tilt := Vector2(_vn1(sd, 3.0) - 0.5, _vn1(sd, 5.0) - 0.5) * s.y * 0.6
	var rings := [[], [], []]
	var lv := [[0.82, -0.0008], [1.0, s.y * 0.45], [0.62, s.y]]
	for i in n:
		var a := (float(i) + (_vn1(sd + i * 1.7, 1.0) - 0.5) * 0.6) / n * TAU
		var k := 0.7 + 0.45 * _vn1(sd + i * 2.3, 2.0)
		var q := Vector2(cos(a) * s.x * 0.5 * k, sin(a) * s.z * 0.5 * k)
		for li in 3:
			var kk := float(lv[li][0]) * (0.9 + 0.2 * _vn1(sd + i * 3.1 + li, 4.0))
			var y := float(lv[li][1])
			if li == 2:
				y += q.dot(tilt) / maxf(s.x, 0.0001) + (_vn1(sd + i * 0.9, 6.0) - 0.5) * s.y * 0.5
			var w := c + (q * kk).rotated(yaw)
			rings[li].append(Vector3(w.x, SINK + y0 + y, w.y))
	st.set_smooth_group(-1)
	for li in 2:
		for i in n:
			var j := (i + 1) % n
			var v := [rings[li][i], rings[li][j], rings[li + 1][j], rings[li + 1][i]]
			for kk: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(side if li == 0 else side.lerp(top, 0.5))
				st.add_vertex(v[kk])
	for i in range(1, n - 1):
		for v: Vector3 in [rings[2][0], rings[2][i + 1], rings[2][i]]:
			st.set_color(top)
			st.add_vertex(v)


## Rubble mound of radii rad (x, z, turned by yaw) and height hgt: a talus profile (steep foot, flatter crown) in six
## rings whose outline wanders in a few lobes and whose points are jittered in and out, so it reads as slumped mud
## brick rather than a smooth dome; smooth-shaded, the base ring a little under the ground; vertex colour darker
## low and in the hollows, lighter towards the top. _heap lays broken clods into its slopes.
static func _mound(st: SurfaceTool, c: Vector2, rad: Vector2, hgt: float, yaw: float, col: Color, hr: RandomNumberGenerator) -> void:
	var nseg := 20
	var lv := [[1.0, -0.002], [0.88, 0.2], [0.72, 0.46], [0.54, 0.7], [0.34, 0.88], [0.15, 0.97]]
	var ph := Vector3(hr.randf() * TAU, hr.randf() * TAU, hr.randf() * TAU)
	var rings := []
	var rcol := []
	for li in lv.size():
		var ring := []
		var rc := []
		for i in nseg:
			var a := TAU * (float(i) + 0.5 * float(li % 2)) / nseg
			var lobe := 1.0 + 0.13 * sin(2.0 * a + ph.x) + 0.08 * sin(3.0 * a + ph.y) + 0.05 * sin(5.0 * a + ph.z)
			var k := float(lv[li][0]) * lobe * hr.randf_range(0.9, 1.1)
			var q := c + Vector2(cos(a) * rad.x * k, sin(a) * rad.y * k).rotated(yaw)
			var y := SINK + float(lv[li][1]) * hgt * hr.randf_range(0.8, 1.2) * (0.85 + 0.15 * lobe)
			ring.append(Vector3(q.x, y, q.y))
			var hollow := hr.randf_range(0.0, 0.14)
			rc.append(col.darkened(hollow + 0.04 * (lv.size() - 1 - li)).lightened(0.03 * li))
		rings.append(ring)
		rcol.append(rc)
	var apex := Vector3(c.x, SINK + hgt, c.y) + Vector3(hr.randf_range(-0.15, 0.15) * rad.x, 0.0, hr.randf_range(-0.15, 0.15) * rad.y)
	st.set_smooth_group(5)   # a heap of earth and broken brick, not a faceted rock
	for li in rings.size() - 1:
		for i in nseg:
			var j := (i + 1) % nseg
			var v := [rings[li][i], rings[li][j], rings[li + 1][j], rings[li + 1][i]]
			var cs := [rcol[li][i], rcol[li][j], rcol[li + 1][j], rcol[li + 1][i]]
			for k: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(cs[k])
				st.add_vertex(v[k])
	var last: Array = rings[rings.size() - 1]
	for i in nseg:
		var j := (i + 1) % nseg
		for k: int in [0, 1, 2]:
			var vv: Vector3 = [last[i], apex, last[j]][k]
			st.set_color(col.lightened(0.1) if k == 1 else rcol[rings.size() - 1][i if k == 0 else j])
			st.add_vertex(vv)
	st.set_smooth_group(-1)


## Двор-квартал в осях (c, yaw), полуразмер h. Глухая стена по периметру, ворота на стороне gate
## (0: z = −h.y, 1: x = +h.x, 2: z = +h.y, 3: x = −h.x); дома — по стенам, дальней от ворот и боковым
static func _yard(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, gate: int, rng: RandomNumberGenerator, stats: Dictionary) -> void:
	stats["yards"] += 1
	var roll := rng.randf()
	var state := 0 if roll < 0.68 else (1 if roll < 0.9 else 2)   # целый, повреждён, разрушен
	var t := 0.007
	var wh := rng.randf_range(0.014, 0.02)
	var wall := T_WALL.darkened(rng.randf_range(-0.03, 0.05))
	var corners := [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]
	var breach_side := rng.randi() % 4 if state > 0 else -1
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var dirv := (b - a).normalized()
		var nin: Vector2 = (Vector2.ZERO - (a + b) * 0.5)
		nin = (Vector2(0.0, nin.y).normalized() if i % 2 == 0 else Vector2(nin.x, 0.0).normalized()) * t * 0.5
		if i == gate:
			var g := rng.randf_range(-0.3, 0.3)
			var gm := a.lerp(b, 0.5 + g)
			var gw := 0.016
			_t_wall(st, c, yaw, a + nin, gm - dirv * gw + nin, t, wh, wall, rng, state == 2)
			_t_wall(st, c, yaw, gm + dirv * gw + nin, b + nin, t, wh, wall, rng, state == 2)
			# piers, a timber frame under a small mud roof and plank leaves (shut as often as the old dark leaves)
			var shut := state == 0 and rng.randf() < 0.5
			_gate(st, c, yaw, gm + nin, dirv, gw, t, wh, state, shut, wall)
			continue
		_t_wall(st, c, yaw, a + nin, b + nin, t, wh, wall, rng, state == 2, i == breach_side)
	# дома: A — вдоль стены напротив ворот во всю длину, B и C — вдоль боковых
	var back := (gate + 2) % 4
	var along_x := back % 2 == 0      # стена вдоль оси x
	var inner := Vector2(h.x - t, h.y - t)
	var d := rng.randf_range(0.024, 0.032)   # полуглубина дома
	var floors := 2 if rng.randf() < 0.22 else 1
	var houses := []   # [центр, полуразмер] в осях двора; поворот у всех домов — как у двора
	if along_x:
		var zc := (inner.y - d) * (-1.0 if back == 0 else 1.0)
		houses.append([Vector2(0.0, zc), Vector2(inner.x, d)])
		if rng.randf() < 0.75:
			var sx := -1.0 if rng.randf() < 0.5 else 1.0
			var len := (inner.y * 2.0 - d * 2.0) * rng.randf_range(0.45, 0.85) * 0.5
			var zs := zc - signf(zc) * (d + len)
			houses.append([Vector2(sx * (inner.x - d * 0.9), zs), Vector2(d * 0.9, len)])
			if rng.randf() < 0.35:
				houses.append([Vector2(-sx * (inner.x - d * 0.8), zc - signf(zc) * (d + len * 0.6)), Vector2(d * 0.8, len * 0.6)])
	else:
		var xc := (inner.x - d) * (1.0 if back == 1 else -1.0)
		houses.append([Vector2(xc, 0.0), Vector2(d, inner.y)])
		if rng.randf() < 0.75:
			var sz := -1.0 if rng.randf() < 0.5 else 1.0
			var len := (inner.x * 2.0 - d * 2.0) * rng.randf_range(0.45, 0.85) * 0.5
			var xs := xc - signf(xc) * (d + len)
			houses.append([Vector2(xs, sz * (inner.y - d * 0.9)), Vector2(len, d * 0.9)])
			if rng.randf() < 0.35:
				houses.append([Vector2(xc - signf(xc) * (d + len * 0.6), -sz * (inner.y - d * 0.8)), Vector2(len * 0.6, d * 0.8)])
	var roof := _roof_col(rng)
	var ruined := rng.randi() % houses.size() if state == 1 else -1
	for i in houses.size():
		var hc: Vector2 = houses[i][0]
		var hs: Vector2 = houses[i][1]
		var wc := c + hc.rotated(yaw)
		if state == 2:
			if rng.randf() < 0.5:
				_t_ruin(st, wc, hs, yaw, rng.randf_range(0.015, 0.03), rng)
			else:
				_heap(st, wc, minf(hs.x, hs.y) * 0.9, rng)
			continue
		if i == ruined:
			_t_ruin(st, wc, hs, yaw, rng.randf_range(0.025, 0.04), rng)
			continue
		# дверь — во двор: дом повёрнут так, чтобы его сторона +z смотрела к центру двора
		var to_c := -hc
		var hy := yaw
		var hsz := hs
		if absf(to_c.x) > absf(to_c.y):
			hy = yaw + (-PI * 0.5 if to_c.x > 0.0 else PI * 0.5)
			hsz = Vector2(hs.y, hs.x)
		elif to_c.y < 0.0:
			hy = yaw + PI
		_t_house(st, wc, hsz, hy, floors if i == 0 else (1 if rng.randf() < 0.85 else 2), roof.lightened(rng.randf_range(-0.03, 0.03)), rng, stats.get("homes"))
		stats["houses"] += 1
	# дерево во дворе
	var taken := []   # VIS-01: yard spots already used (tree, well), in yard axes
	if state < 2 and rng.randf() < 0.5:
		var tc := Vector2(rng.randf_range(-0.3, 0.3) * h.x, rng.randf_range(-0.3, 0.3) * h.y)
		var free := true
		for hh in houses:
			if absf(tc.x - hh[0].x) < hh[1].x + 0.018 and absf(tc.y - hh[0].y) < hh[1].y + 0.018:
				free = false
		if free:
			_crown(st, c + tc.rotated(yaw), rng.randf_range(0.016, 0.024), rng, stats.get("homes"))
			taken.append(tc)
	if state >= 2 or not stats.has("homes"):
		return
	# VIS-01: a hand-pump well in some yards, clear of the houses (its own generator: the layout does not move)
	var wr := RandomNumberGenerator.new()
	wr.seed = hash(Vector2i(roundi(c.x * 1e5), roundi(c.y * 1e5))) + 1
	if wr.randf() < 0.35:
		for k in 6:
			var wp := Vector2(wr.randf_range(-0.5, 0.5) * h.x, wr.randf_range(-0.5, 0.5) * h.y)
			var free := true
			for hs in houses:
				if absf(wp.x - hs[0].x) < hs[1].x + 0.016 and absf(wp.y - hs[0].y) < hs[1].y + 0.016:
					free = false
			if free:
				stats["homes"].append([VillageHouses.WELL, c + wp.rotated(yaw), yaw + wr.randf() * TAU, Vector3.ONE * M_PER_UNIT])
				taken.append(wp)
				break
	# VIS-01 (Kanta 26.10): household clutter — a tandoor, a woodpile, a haystack — in some yards, clear of the
	# houses, the tree and the well; a generator of its own again
	var yr := RandomNumberGenerator.new()
	yr.seed = hash(Vector2i(roundi(c.x * 1e5), roundi(c.y * 1e5))) + 2
	for kv: Array in [[VillageHouses.TANDOOR, 0.3], [VillageHouses.WOODPILE, 0.35], [VillageHouses.HAY, 0.22]]:
		if yr.randf() >= float(kv[1]):
			continue
		for k in 6:
			var q := Vector2(yr.randf_range(-0.6, 0.6) * h.x, yr.randf_range(-0.6, 0.6) * h.y)
			var free := true
			for hs in houses:
				if absf(q.x - hs[0].x) < hs[1].x + 0.015 and absf(q.y - hs[0].y) < hs[1].y + 0.015:
					free = false
			for o: Vector2 in taken:
				if o.distance_to(q) < 0.024:
					free = false
			if free:
				stats["homes"].append([kv[0], c + q.rotated(yaw), yaw + PI * 0.5 * yr.randi_range(0, 3), Vector3.ONE * M_PER_UNIT])
				taken.append(q)
				break


## Model studio (tools/model_lab/studio.gd): one village piece built by the same functions as village(), for
## close-up review of the compound walls, gates and ruins. kind: "yard" (an intact walled yard, gate on -z),
## "yard_damaged" (a breach and one ruined house), "yard_ruined" (ragged walls, heaps), "orchard" (an outskirts
## orchard: its low wall and rows of tree models), "ruins" (a roofless
## house, a heap and a breached ragged wall). Returns [mesh (old units × V_UNIT, like the village mesh),
## homes (VillageHouses.attach records)]. The seed is searched so the yard comes out in the asked state.
static func debug_piece(kind: String) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var homes := []
	var stats := {"yards": 0, "houses": 0, "homes": homes}
	var rng := RandomNumberGenerator.new()
	if kind.begins_with("yard"):
		var want: int = {"yard": 0, "yard_damaged": 1, "yard_ruined": 2}.get(kind, 0)
		for s in 400:
			rng.seed = 4100 + s
			var r := rng.randf()
			if (0 if r < 0.68 else (1 if r < 0.9 else 2)) == want:
				rng.seed = 4100 + s
				break
		_yard(st, Vector2.ZERO, Vector2(0.11, 0.085), 0.0, 0, rng, stats)
	elif kind == "orchard":
		rng.seed = 11
		_orchard(st, Vector2.ZERO, Vector2(0.1, 0.075), 0.0, rng, homes)
	else:
		rng.seed = 5
		_t_ruin(st, Vector2(-0.055, 0.01), Vector2(0.034, 0.028), 0.0, 0.035, rng)
		_heap(st, Vector2(0.035, 0.03), 0.026, rng)
		_t_wall(st, Vector2(0.0, -0.045), 0.0, Vector2(-0.09, 0.0), Vector2(0.09, 0.0), 0.007, 0.018, T_WALL, rng, true, true)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _scaled_arrays(st, V_UNIT))
	return [m, homes]


## Крона дерева: два повёрнутых друг к другу яруса (сверху — восьмиугольник), оливково-серая.
## VIS-01: with homes, a tree model (VillageHouses.ORCHARD or PALM, picked by place: palm_share of them palms) is
## recorded instead; rng is drawn exactly as for the boxes. Every sortie path passes homes (yards, the square,
## the outskirts' orchards); the boxes are left only for the bench's box-house «before» frames (--boxhouses)
static func _crown(st: SurfaceTool, c: Vector2, r: float, rng: RandomNumberGenerator, homes = null, palm_share := 0.3) -> void:
	var col := T_TREE.lightened(rng.randf_range(-0.05, 0.08))
	var y0 := rng.randf_range(0.012, 0.02)
	var yaw := rng.randf() * TAU
	if homes != null:
		var roll := float(absi(hash(Vector2i(roundi(c.x * 1e5), roundi(c.y * 1e5)))) % 1000) / 1000.0
		homes.append([VillageHouses.PALM if roll < palm_share else VillageHouses.ORCHARD, c, yaw, Vector3.ONE * r * 2.6])
		return
	_ob(st, c, yaw, 0.0, 0.0, Vector3(0.004, y0 + 0.004, 0.004), T_DARK, T_DARK)   # ствол
	_ob(st, c, yaw, 0.0, 0.0, Vector3(r * 1.7, r * 0.9, r * 1.7), col.darkened(0.1), col, y0)
	_ob(st, c, yaw + PI * 0.25, 0.0, 0.0, Vector3(r * 1.5, r * 1.15, r * 1.5), col.darkened(0.1), col.lightened(0.05), y0)


## Лавка у главной улицы: низкий дом, навес из ткани над улицей (сторона к улице — z = −sg·h.y в осях d).
## VIS-01: with homes, the shop is a model house (_home) and its cloth is the awning model over the front;
## rng is drawn exactly as for the boxes
static func _shop(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, sg: float, rng: RandomNumberGenerator, homes = null) -> void:
	var hy := yaw + (PI if sg < 0.0 else 0.0)   # +z дома — к улице
	var roof := _roof_col(rng)
	var ht := rng.randf_range(0.026, 0.034)
	var awning := rng.randf() < 0.7
	var cl := Color()
	if awning:
		cl = T_CLOTH[rng.randi() % T_CLOTH.size()]
	if homes != null:
		_home(homes, c, Vector2(h.x - 0.0015, h.y), hy, ht, 1)
		if awning:   # the awning's width over the shop front, a little shallower than the model so it keeps off mid-street
			var s := h.x * 1.9 / float(VillageHouses.PROPS[VillageHouses.AWNING - VillageHouses.PROP0][1].x)
			homes.append([VillageHouses.AWNING, c + Vector2(0.0, h.y + 0.008).rotated(hy), hy, Vector3(s, s, s * 0.7)])
		return
	_ob(st, c, hy, 0.0, 0.0, Vector3(h.x * 2.0 - 0.003, ht, h.y * 2.0), T_WALL.lerp(roof, 0.4), roof)
	_ob(st, c, hy, 0.0, h.y + 0.001, Vector3(h.x * 1.2, 0.018, 0.003), T_DARK, T_DARK)
	if awning:
		_ob(st, c, hy, 0.0, h.y + 0.009, Vector3(h.x * 1.9, 0.0025, 0.018), cl.darkened(0.1), cl, 0.02)


## Площадь-базар: хауз (пруд в глиняном борту) и 10–14 навесов торговцев по кругу, не на улицах
## VIS-01: with homes, the stalls are recorded as models (VillageHouses.STALL, sacks as BAGS) and a market of tent
## rows fills the square (_market); rng is drawn exactly as for the boxes
static func _bazaar(st: SurfaceTool, variant: int, lots: Array, rng: RandomNumberGenerator, homes = null) -> void:
	var pc := Vector2.from_angle(rng.randf() * TAU) * SQ_R * 0.45
	var pool := path_info(variant, pc).x > 0.03
	if pool:
		_ob(st, pc, 0.3, 0.0, 0.0, Vector3(0.05, 0.004, 0.04), T_WALL, WATER)
		for s: float in [-1.0, 1.0]:
			_ob(st, pc, 0.3, 0.0, s * 0.022, Vector3(0.056, 0.007, 0.006), T_WALL, T_ROOFS[0])
			_ob(st, pc, 0.3, s * 0.027, 0.0, Vector3(0.006, 0.007, 0.04), T_WALL, T_ROOFS[0])
		_crown(st, pc + Vector2(0.045, 0.02), 0.024, rng, homes, 1.0)   # a palm by the pool
	var put := []
	var stalls := []   # [place, yaw, sacks] when recording models
	for i in 60:
		if put.size() >= 14:
			break
		var a := rng.randf() * TAU
		var p := Vector2.from_angle(a) * SQ_R * rng.randf_range(0.55, 0.9)
		if path_info(variant, p).x < 0.02 or p.distance_to(pc) < 0.06:
			continue
		var ok := true
		for q: Vector2 in put:
			if q.distance_to(p) < 0.042:
				ok = false
		if not ok:
			continue
		put.append(p)
		var yaw := a + PI * 0.5
		var cl: Color = T_CLOTH[rng.randi() % T_CLOTH.size()]
		if homes != null:
			stalls.append([p, yaw, rng.randf() < 0.4])
			continue
		_ob(st, p, yaw, 0.0, 0.006, Vector3(0.028, 0.008, 0.01), T_WALL, T_RUBBLE)   # прилавок
		for sx: float in [-1.0, 1.0]:
			_ob(st, p, yaw, sx * 0.015, -0.011, Vector3(0.0025, 0.02, 0.0025), WOOD_DARK, WOOD_DARK)
		_ob(st, p, yaw, 0.0, 0.0, Vector3(0.036, 0.0025, 0.03), cl.darkened(0.12), cl, 0.02)   # навес
		if rng.randf() < 0.4:   # мешки, корзины
			_ob(st, p, yaw + 0.5, 0.012, 0.018, Vector3(0.008, 0.006, 0.008), BAG, BAG)
	if homes != null:
		_market(variant, pc, pool, stalls, homes)


const MKT_TENT := 0.9        ## market tents at 90 %: 3.2 × 2.9 m
const MKT_STEP := 0.039      ## tent pitch along a row (a tent and ~0.4 m between), old units
## Row lines either side of the main street: the first two face each other across a ~2.2 m aisle, the third
## stands back to back with the second, facing the square's edge
const MKT_ROWS := [0.038, 0.094, 0.131]
const MKT_CLEAR := 0.005     ## tents keep this off street edges
const MKT_STALLS := 4        ## ring stalls (model 126) the rows always make room for


## VIS-01 (Kanta 26.10: "put some tents in the centre of the kishlak to imitate a market"): the
## square as a bazaar. Tent rows run along the main street on both sides, the first two facing each other across
## an aisle where rugs, pots and sacks lie out; rugs hang on frames at the row ends, a cart or two and the trough
## stand in the gaps. Each row takes a tent wherever one fits off the streets, the pool and the first ring stalls
## of _bazaar (models too; the other ring stalls stay where they clear the tents). Its own generator (the village's is untouched), so the layout is fixed per variant
static func _market(variant: int, pc: Vector2, pool: bool, stalls: Array, homes: Array) -> void:
	var mr := RandomNumberGenerator.new()
	mr.seed = 7919 * (variant + 1) + 4241
	var d := _main_dir(variant, 0.0)
	var ya := d.angle()
	var n := Vector2(0.0, 1.0).rotated(ya)   # local +z of a model at yaw ya: the tent's counter side
	var hx := 0.0195 * MKT_TENT   # tent half size, old units
	var hz := 0.0175 * MKT_TENT
	var tents := []
	var spots := []   # the first ring stalls of _bazaar stay for sure: the rows leave gaps for them
	for s: Array in stalls.slice(0, MKT_STALLS):
		spots.append(s[0])
	for ri in MKT_ROWS.size():
		for side: float in [-1.0, 1.0]:
			var v: float = MKT_ROWS[ri] * side
			var face := side if ri % 2 == 0 else -side   # the counter's side: +n·face
			# along the row, a tent wherever one fits (streets cross the square at different places per variant)
			var u := -SQ_R
			while u < SQ_R:
				var c := d * u + n * v
				var ok := not (pool and c.distance_to(pc) < 0.05) and not _near(c, spots, 0.042)
				for cx: float in [-1.0, 0.0, 1.0]:
					for cz: float in [-1.0, 0.0, 1.0]:
						var q := c + d * hx * cx + n * hz * cz
						if ok and (q.length() > SQ_R - 0.004 or path_info(variant, q).x < MKT_CLEAR):
							ok = false
				if not ok:
					u += 0.004
					continue
				u += MKT_STEP
				var yaw := ya + (0.0 if face > 0.0 else PI) + mr.randf_range(-0.04, 0.04)
				var roll := mr.randf()
				homes.append([VillageHouses.TENT + (0 if roll < 0.4 else (1 if roll < 0.7 else 2)), c, yaw, Vector3.ONE * M_PER_UNIT * MKT_TENT])
				tents.append(c)
				if ri == 2:   # the back row faces the square's edge: no aisle in front
					continue
				# goods laid out in front, in the aisle
				var g := mr.randf()
				var gp := c + n * face * (hz + 0.011) + d * mr.randf_range(-0.006, 0.006)
				if path_info(variant, gp).x < 0.004:
					continue
				if g < 0.35:
					homes.append([VillageHouses.RUG, gp, ya + mr.randf_range(-0.12, 0.12), Vector3.ONE * M_PER_UNIT * 0.8])
				elif g < 0.55:
					homes.append([VillageHouses.POTS, gp, mr.randf() * TAU, Vector3.ONE * M_PER_UNIT * 0.8])
				elif g < 0.75:
					homes.append([VillageHouses.BAGS, gp, mr.randf() * TAU, Vector3.ONE * M_PER_UNIT * 0.7])
	# rugs hung on frames at the ends of the rows
	var ends := []
	for c: Vector2 in tents:
		var lone_l := true
		var lone_r := true
		for o: Vector2 in tents:
			if o.distance_to(c - d * MKT_STEP) < 0.01:
				lone_l = false
			if o.distance_to(c + d * MKT_STEP) < 0.01:
				lone_r = false
		if lone_l:
			ends.append(c - d * (hx + 0.008))
		if lone_r:
			ends.append(c + d * (hx + 0.008))
	# the ring stalls: the first MKT_STALLS, and the rest where they clear the tents
	var taken := tents + spots
	for i in stalls.size():
		var s: Array = stalls[i]
		var p: Vector2 = s[0]
		if i >= MKT_STALLS:
			if _near(p, tents, 0.046):
				continue
			taken.append(p)
		homes.append([VillageHouses.STALL, p, s[1], Vector3.ONE * M_PER_UNIT * 0.8])
		if s[2]:
			homes.append([VillageHouses.BAGS, p + Vector2(0.012, 0.03).rotated(float(s[1])), float(s[1]) + 0.5, Vector3.ONE * M_PER_UNIT * 0.6])
	var frames := 0
	for e: Vector2 in ends:
		if frames >= 3 or mr.randf() < 0.45:
			continue
		if e.length() < SQ_R - 0.01 and path_info(variant, e).x > 0.006 and not _near(e, taken, 0.024):
			homes.append([VillageHouses.RUGFRAME, e, ya + PI * 0.5, Vector3.ONE * M_PER_UNIT])
			taken.append(e)
			frames += 1
	# the trough by the pool, carts in empty spots of the square
	var free := []
	var gy := -SQ_R
	while gy < SQ_R:
		var gx := -SQ_R
		while gx < SQ_R:
			var c := d * gx + n * gy
			gx += 0.03
			if c.length() > SQ_R - 0.02 or path_info(variant, c).x < 0.016 or (pool and c.distance_to(pc) < 0.05):
				continue
			if not _near(c, taken, 0.036):
				free.append(c)
		gy += 0.03
	if pool:
		var tp := pc + Vector2.from_angle(0.3 + PI * 0.5) * 0.04
		if path_info(variant, tp).x > 0.006:
			homes.append([VillageHouses.TROUGH, tp, 0.3, Vector3.ONE * M_PER_UNIT * 0.8])
	elif not free.is_empty():
		homes.append([VillageHouses.TROUGH, free.pop_at(mr.randi() % free.size()), ya, Vector3.ONE * M_PER_UNIT * 0.8])
	for i in mini(1 + mr.randi() % 2, free.size()):
		homes.append([VillageHouses.CART, free.pop_at(mr.randi() % free.size()), ya + mr.randf_range(-0.6, 0.6), Vector3.ONE * M_PER_UNIT])


## Some point of pts lies closer than r to p
static func _near(p: Vector2, pts: Array, r: float) -> bool:
	for q: Vector2 in pts:
		if q.distance_to(p) < r:
			return true
	return false


## Караван-сарай: квадрат толстых стен, кельи по периметру внутри, угловые башни, высокий портал ворот
## на стороне gate (0: z = −h.y, 2: z = +h.y), во дворе — колодец и груз
## VIS-01: with homes, its cargo is recorded as models (sacks and pots) instead of boxes; rng as before
static func _serai(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, gate: int, rng: RandomNumberGenerator, homes = null) -> void:
	var t := 0.012
	var wh := 0.042
	var roof := _roof_col(rng)
	var wall := T_WALL.lerp(roof, 0.3)
	var d := 0.05   # глубина келий
	var gz := -h.y if gate == 0 else h.y
	for s: float in [-1.0, 1.0]:   # стены и кельи вдоль x
		_ob(st, c, yaw, 0.0, s * (h.y - t * 0.5), Vector3(h.x * 2.0, wh, t), wall, roof)
		_ob(st, c, yaw, s * (h.x - t * 0.5), 0.0, Vector3(t, wh, h.y * 2.0), wall, roof)
		if absf(s * h.y - gz) > 0.01:
			_ob(st, c, yaw, 0.0, s * (h.y - t - d * 0.5), Vector3(h.x * 2.0 - 2.0 * t, wh - 0.008, d), wall, roof.darkened(0.03))
		else:   # кельи по обе стороны ворот
			for sx: float in [-1.0, 1.0]:
				_ob(st, c, yaw, sx * (h.x * 0.5 + 0.02), s * (h.y - t - d * 0.5), Vector3(h.x - 0.04 - 2.0 * t, wh - 0.008, d), wall, roof.darkened(0.03))
		_ob(st, c, yaw, s * (h.x - t - d * 0.5), 0.0, Vector3(d, wh - 0.008, h.y * 2.0 - 2.0 * (t + d)), wall, roof.darkened(0.03))
	# перегородки келий на крыше — читается масштаб
	for k in 9:
		var f := -h.x + (k + 1) * h.x * 2.0 / 10.0
		for s: float in [-1.0, 1.0]:
			_ob(st, c, yaw, f, s * (h.y - t - d * 0.5), Vector3(0.004, 0.003, d), wall, roof.lightened(0.05), wh - 0.008)
	# угловые башни; одна обрушена
	var broken := rng.randi() % 4
	var k2 := 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var th := 0.062 if k2 != broken else 0.03
			_ob(st, c, yaw, sx * (h.x - 0.012), sz * (h.y - 0.012), Vector3(0.042, th, 0.042), wall, roof)
			if k2 == broken:
				_heap(st, c + Vector2(sx * (h.x + 0.02), sz * (h.y - 0.03)).rotated(yaw), 0.02, rng)
			k2 += 1
	# портал ворот
	var sg := signf(gz)
	_ob(st, c, yaw, 0.0, gz, Vector3(0.08, 0.068, 0.03), wall, roof)
	_ob(st, c, yaw, 0.0, gz + sg * 0.0155, Vector3(0.03, 0.044, 0.002), T_DARK, T_DARK)
	# колодец и груз во дворе
	_ob(st, c, yaw, 0.0, 0.0, Vector3(0.022, 0.008, 0.022), wall, T_DARK)
	for i in rng.randi_range(3, 6):
		var p := Vector2(rng.randf_range(-0.6, 0.6) * (h.x - d - t), rng.randf_range(-0.6, 0.6) * (h.y - d - t))
		if p.length() < 0.03:
			continue
		var cy := yaw + rng.randf_range(-0.3, 0.3)
		var crate := rng.randf() < 0.5
		if homes != null:
			homes.append([VillageHouses.POTS if crate else VillageHouses.BAGS, c + p.rotated(cy), cy, Vector3.ONE * M_PER_UNIT * 0.9])
			continue
		_ob(st, c, cy, p.x, p.y, Vector3(0.016, 0.009, 0.012), WOOD, WOOD.lightened(0.08) if crate else BAG)


## Водокачка: глинобитная башня-основание и восьмигранный металлический бак сверху
static func _water_tower(st: SurfaceTool, c: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var wall := T_WALL.lerp(_roof_col(rng), 0.4)
	_ob(st, c, yaw, 0.0, 0.0, Vector3(0.05, 0.05, 0.05), wall, wall.lightened(0.05))
	_ob(st, c, yaw, 0.0, 0.0, Vector3(0.04, 0.085, 0.04), wall, wall.lightened(0.05))
	_ob(st, c, yaw, 0.0, 0.026, Vector3(0.012, 0.022, 0.002), T_DARK, T_DARK)
	_ob(st, c, yaw, 0.0, 0.0, Vector3(0.05, 0.034, 0.05), T_METAL, T_METAL.lightened(0.06), 0.085)
	_ob(st, c, yaw + PI * 0.25, 0.0, 0.0, Vector3(0.05, 0.034, 0.05), T_METAL.darkened(0.05), T_METAL.lightened(0.06), 0.085)
	_ob(st, c, yaw, 0.0, 0.0, Vector3(0.003, 0.03, 0.003), T_METAL.darkened(0.2), T_METAL, 0.119)   # труба-отдушина


## Склад: длинное низкое здание, три пролёта крыши разной высоты, широкие тёмные ворота
static func _warehouse(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var roof := _roof_col(rng)
	var wall := T_WALL.lerp(roof, 0.4)
	for k in 3:
		var x := -h.x + (k + 0.5) * h.x * 2.0 / 3.0
		_ob(st, c, yaw, x, 0.0, Vector3(h.x * 2.0 / 3.0 + 0.001, 0.04 + 0.006 * (k % 2), h.y * 2.0), wall, roof.lightened(0.02 * k))
		_ob(st, c, yaw, x, h.y + 0.001, Vector3(0.026, 0.028, 0.003), T_DARK, T_DARK)


## Сад за дувалом: ограда по периметру с проходом, внутри ряды деревьев. The trees are recorded in `trees`
## as orchard tree models (VillageHouses.ORCHARD, drawn by VillageHouses.attach) instead of the old stacked boxes
## that read as stars from above; rng is drawn exactly as before
static func _orchard(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, rng: RandomNumberGenerator, trees: Array) -> void:
	var t := 0.006
	var wh := rng.randf_range(0.008, 0.012)
	var corners := [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]
	var gate := rng.randi() % 4
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == gate:
			_t_wall(st, c, yaw, a, a.lerp(b, 0.42), t, wh, T_WALL, rng)
			_t_wall(st, c, yaw, a.lerp(b, 0.58), b, t, wh, T_WALL, rng)
		else:
			_t_wall(st, c, yaw, a, b, t, wh, T_WALL, rng, rng.randf() < 0.2)
	var nx := maxi(2, int(h.x / 0.03))
	var nz := maxi(2, int(h.y / 0.03))
	for i in nx:
		for j in nz:
			if rng.randf() < 0.15:
				continue
			var p := Vector2(-h.x + (i + 0.5) * h.x * 2.0 / nx, -h.y + (j + 0.5) * h.y * 2.0 / nz)
			_crown(st, c + p.rotated(yaw), rng.randf_range(0.012, 0.017), rng, trees, 0.0)


## Поле: межи (низкие земляные валики) по краю и поперёк — 2–4 полосы
static func _field(st: SurfaceTool, c: Vector2, h: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var w := 0.005
	var hh := 0.003
	var col := T_BUND.darkened(rng.randf_range(0.0, 0.06))
	for s: float in [-1.0, 1.0]:
		_ob(st, c, yaw, 0.0, s * h.y, Vector3(h.x * 2.0, hh, w), col, col)
		_ob(st, c, yaw, s * h.x, 0.0, Vector3(w, hh, h.y * 2.0), col, col)
	var n := rng.randi_range(1, 3)
	for k in n:
		var x := -h.x + (k + 1) * h.x * 2.0 / (n + 1)
		_ob(st, c, yaw, x, 0.0, Vector3(w * 0.8, hh, h.y * 2.0), col, col)
