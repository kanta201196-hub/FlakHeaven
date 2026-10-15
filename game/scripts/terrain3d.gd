class_name Terrain3D
extends Node3D
## B-26: рельеф «Нагорья Шахрисанг» — бесконечная земля из кусков сетки высот.
## Композиция (правила — docs/sprint1/s4-landscape-rules.md): сеть долин из нулевых линий шума —
## по дну каждой долины течёт река, вдоль одного берега идёт дорога; от дна вверх — ровная пойма,
## вогнутые конусы выноса и осыпи, крутые склоны с уступами пород, острые гребни. Кишлаки, крепости
## и оазисы стоят на дне долин: от каждого к ближайшей долине прорезана боковая долина.
## Высота считается одной функцией height() — по ней же ставятся наземные цели, пятна и объекты,
## поэтому один и тот же участок карты всегда одинаковый (зерно — от мира, а не от вылета).
## Координаты: x, z — как 2D-мир (px), y — вверх; base_y — дно долин, рельеф не выше ceiling.

const CHUNK := 1400.0          # совпадает с Background.CHUNK: объекты биома и куски рельефа — одна сетка
## ячеек сетки по стороне куска (20 px) — острее гребни и уступы.
## 3.5 (правка 7): на «Низком» 40, на «Среднем» 56 — втрое / в полтора раза меньше треугольников и быстрее сборка
const N_GFX := [40, 56, 70, 70]
var N := 70
## Поселения — на дне долин (вес 1); обломки самолёта и воронки могут быть где угодно, под ними лишь вмятина
const FLAT_OBJS := {"o_village": 1.0, "o_fort": 1.0, "o_oasis": 1.0, "o_crater": 0.3, "o_wreck": 0.3}
const SETTLE := ["o_village", "o_fort", "o_oasis"]
## Профиль поперёк долины по расстоянию до линии реки, px (знак — берег: дорога со стороны «+»)
const D_RIVER := 26.0          # полуширина русла
const D_ROAD := 85.0           # ось дороги
const D_FLOOR := 260.0         # ровное дно долины
const D_FAN := 480.0           # конусы выноса и осыпи до подножия склона
const D_CLIMB := 2200.0        # от подножия до гребня
const V_SCALE := 0.00028       # перевод поля долин в «пиксели» вдали от реки

var base_y := -500.0
var ceiling := 470.0           # максимальная высота рельефа над дном долин
var material: Material
var _chunks := {}              # Vector2i → MeshInstance3D
var _objs_cache := {}          # Vector2i → объект биома клетки (или пусто)
var _mask := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _hill := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _valley := FastNoiseLite.new()
var _plains := FastNoiseLite.new()
var _side := {}                # Vector2i → боковые долины поселений рядом: [[A, B, ширина], …]
var _bg: Background
var props: BiomeProps          # B-41: модели биома на рельефе (null — без них)


func setup(depth: float, mat: Material, bg: Background) -> void:
	base_y = -depth
	N = N_GFX[clampi(Settings.gfx, 0, 3)]
	ceiling = maxf(depth - 30.0, 0.0)   # запас на крен и толщину моделей у плоскости боя
	material = mat
	_bg = bg
	_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mask.seed = 7311
	_mask.frequency = 1.0 / 5200.0
	_mask.fractal_type = FastNoiseLite.FRACTAL_FBM
	_mask.fractal_octaves = 2
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.seed = 1291
	_ridge.frequency = 1.0 / 2100.0
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.fractal_gain = 0.5
	_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hill.seed = 4417
	_hill.frequency = 1.0 / 650.0
	_hill.fractal_octaves = 3
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.seed = 977
	_warp.frequency = 1.0 / 3000.0
	_valley.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_valley.seed = 5023
	_valley.frequency = 1.0 / 5200.0
	# одна октава: вторая давала мелкие замкнутые петли нулевой линии — «ямы» без стока
	_valley.fractal_type = FastNoiseLite.FRACTAL_NONE
	_plains.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_plains.seed = 8861
	_plains.frequency = 1.0 / 7000.0
	clear()


func clear() -> void:
	N = N_GFX[clampi(Settings.gfx, 0, 3)]
	for k in _chunks:
		(_chunks[k] as Node).queue_free()
	_chunks.clear()
	_objs_cache.clear()
	_side.clear()


## Расстояние до линии реки, px, со знаком берега; боковые долины поселений сводят его к нулю
func valley(x: float, z: float) -> float:
	var d := river_field(x, z)
	for s in _sides(x, z):
		var dc := maxf(_seg_dist(Vector2(x, z), s[0], s[1]) - float(s[2]) * 0.5, 0.0)
		if dc < absf(d):
			d = dc
	return d


## Высота рельефа над дном долин (0 … ceiling) в точке мира
func height(x: float, z: float) -> float:
	return _height_v(x, z, valley(x, z))


func _height_v(x: float, z: float, v: float) -> float:
	var a := absf(v)
	# пойма и конусы выноса: вогнутый подъём к подножию
	var fan := smoothstep(D_FLOOR, D_FAN, a)
	var h := 0.1 * fan * fan
	# склон: круто вверх, высота хребта — от гребневого шума (острые гребни) и маски равнин
	var wx := x + _warp.get_noise_2d(x - 311.0, z + 71.0) * 300.0
	var wz := z + _warp.get_noise_2d(x + 57.0, z - 919.0) * 300.0
	var r := clampf((_ridge.get_noise_2d(wx, wz) + 1.0) * 0.5, 0.0, 1.0)
	var open := smoothstep(-0.45, 0.25, _plains.get_noise_2d(x, z))   # 0 — широкая равнина, 1 — горы
	# высота хребта растёт монотонно от подножия (иначе между гребнями — замкнутые ямы без стока),
	# гребневой шум добавляет острые зубцы сверху, а не вычитает долины
	var top := lerpf(0.3, 1.0, open)
	var climb := smoothstep(D_FAN - 40.0, D_CLIMB, a)
	climb = 1.0 - pow(1.0 - climb, 1.6)   # выпуклый склон: круче у подножия плеча, острее у гребня
	h += (top - 0.1) * climb * 0.85
	h += r * r * 0.15 * climb * climb * top   # только прибавка: зубцы над склоном, без ям между ними
	# уступы пород: горизонтальные слои дают скальные пояса на склонах
	# только на крутой части склона — на пологих конусах и плато уступы дают полосы «как горизонтали»
	var steep := smoothstep(0.08, 0.25, climb) * (1.0 - smoothstep(0.7, 0.92, climb))
	if h > 0.16 and steep > 0.0:
		var t := h * 7.0
		var step := (floorf(t) + smoothstep(0.25, 0.75, t - floorf(t))) / 7.0
		h = lerpf(h, step, 0.45 * steep)
	# мелкие бугры на дне и на конусах
	h += (_hill.get_noise_2d(x, z) + 1.0) * 0.5 * 0.025 * (0.3 + fan)
	h *= _flat(x, z)
	return clampf(h, 0.0, 1.0) * ceiling


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Боковые долины поселений, влияющие на клетку точки (от поселения к ближайшей линии реки)
func _sides(x: float, z: float) -> Array:
	if _bg == null:
		return []
	var key := Vector2i(int(floorf(x / CHUNK)), int(floorf(z / CHUNK)))
	if _side.has(key):
		return _side[key]
	var out := []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var o := _obj(Vector2i(key.x + dx, key.y + dz))
			if o.is_empty() or not (o["name"] in SETTLE):
				continue
			var a: Vector2 = o["pos"]
			out.append([a, _river_near(a), float(o["size"]) * 0.75])
	_side[key] = out
	if _side.size() > 600:
		_side.clear()
	return out


## Ближайшая точка линии реки (v = 0) без учёта боковых долин; детерминирована
func _river_near(a: Vector2) -> Vector2:
	var best := a
	var best_v := INF
	for ring in range(0, 9):
		var rr := ring * 220.0
		var n := maxi(1, ring * 8)
		for i in n:
			var p := a + Vector2.from_angle(TAU * i / n) * rr
			var v := absf(_v_raw(p.x, p.y))
			if v < best_v:
				best_v = v
				best = p
		if best_v < 0.01:
			break
	return best


## Расстояние до линии реки без боковых долин поселений, px со знаком: по нему идут река и дорога.
## Поле шума делим на его наклон — получается почти настоящее расстояние (ширина русла везде одна)
func river_field(x: float, z: float) -> float:
	var e := 6.0
	var v := _v_raw(x, z)
	var g := Vector2(_v_raw(x + e, z) - v, _v_raw(x, z + e) - v) / e
	# у реки — точное расстояние (ровная ширина русла и дороги); дальше — по самому полю с постоянным
	# масштабом: расстояние-оценка «гуляет» с наклоном поля и рождала ямы на склонах
	var near := v / maxf(g.length(), 1e-5)
	var far := v / V_SCALE
	return lerpf(near, far, smoothstep(0.03, 0.12, absf(v)))


func _v_raw(x: float, z: float) -> float:
	# сдвиг умеренный: сильный «складывает» поле и рождает замкнутые петли русла — ямы без стока
	var wx := x + _warp.get_noise_2d(x, z) * 380.0
	var wz := z + _warp.get_noise_2d(x + 913.0, z - 377.0) * 380.0
	return _valley.get_noise_2d(wx, wz)


## Ближайшая точка дна долины (не дальше D_FLOOR от реки) около p — для наземной техники
func find_floor(p: Vector2, radius := 900.0) -> Vector2:
	var best := p
	var best_s := INF
	for ring in range(0, 10):
		var rr := radius * ring / 9.0
		var n := maxi(1, ring * 8)
		for i in n:
			var q := p + Vector2.from_angle(TAU * i / n) * rr
			var a := absf(valley(q.x, q.y))
			var ar := absf(river_field(q.x, q.y))
			# дно долины, но не в русле; ближе — лучше
			var sc := maxf(a - D_FLOOR * 0.8, 0.0) / 100.0 + maxf(D_RIVER * 2.0 - ar, 0.0) / 20.0 + rr / radius * 0.2
			if sc < best_s:
				best_s = sc
				best = q
		if best_s < 0.05 + rr / radius * 0.2:
			break
	return best


## Точка мира на поверхности рельефа
func surface(x: float, z: float) -> Vector3:
	return Vector3(x, base_y + height(x, z), z)


## Под кишлаками, крепостями, оазисами земля ровная (вес 0 — плоско, 1 — рельеф как есть)
func _flat(x: float, z: float) -> float:
	if _bg == null:
		return 1.0
	var cx := int(floorf(x / CHUNK))
	var cz := int(floorf(z / CHUNK))
	var k := 1.0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var o := _obj(Vector2i(cx + dx, cz + dz))
			if o.is_empty() or not FLAT_OBJS.has(o["name"]):
				continue
			var r: float = float(o["size"]) * 0.55
			var d := Vector2(x, z).distance_to(o["pos"])
			var f := smoothstep(r, r * 2.2, d)
			k = minf(k, lerpf(1.0 - float(FLAT_OBJS[o["name"]]), 1.0, f))
	return k


func _obj(key: Vector2i) -> Dictionary:
	if not _objs_cache.has(key):
		_objs_cache[key] = _bg.chunk_object(key.x, key.y)
	return _objs_cache[key]


## Держим куски рельефа под видимой областью; новые строим не больше budget за кадр
func sync(view: Rect2, budget := 2) -> void:
	var want := {}
	for cx in range(int(floorf(view.position.x / CHUNK)), int(floorf(view.end.x / CHUNK)) + 1):
		for cz in range(int(floorf(view.position.y / CHUNK)), int(floorf(view.end.y / CHUNK)) + 1):
			want[Vector2i(cx, cz)] = true
	# сначала ближние к центру
	var c := view.get_center() / CHUNK
	var keys := want.keys()
	keys.sort_custom(func(a, b): return Vector2(a).distance_squared_to(c) < Vector2(b).distance_squared_to(c))
	# скачок камеры (старт, стенд, телепорт отладки): не хватает многих кусков — строим все сразу,
	# иначе на экране дыра до фона
	var missing := 0
	for key in keys:
		if not _chunks.has(key):
			missing += 1
	if missing > 6:
		budget = missing
	for key in keys:
		if _chunks.has(key):
			continue
		if budget <= 0:
			break
		budget -= 1
		var t0 := Time.get_ticks_usec()
		_chunks[key] = _build(key)
		if Main.I != null and Main.I.state == "playing":   # T4-03: рывки от сборки кусков рельефа
			Main.I.tele.chunk_built((Time.get_ticks_usec() - t0) / 1000.0)
	for key in _chunks.keys():
		if not want.has(key):
			(_chunks[key] as Node).queue_free()
			_chunks.erase(key)
	if _objs_cache.size() > 400:
		_objs_cache.clear()


func _build(key: Vector2i) -> MeshInstance3D:
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var step := CHUNK / N
	var W := N + 3   # +1 узел и по одному с каждой стороны — нормали на стыках кусков совпадают
	var hs := PackedFloat32Array()
	var vs := PackedFloat32Array()
	hs.resize(W * W)
	vs.resize(W * W)
	for j in W:
		for i in W:
			var x := ox + (i - 1) * step
			var z := oz + (j - 1) * step
			# русло и дорога — по «чистому» полю (река не огибает кишлаки кольцом), высота — с боковыми долинами
			vs[j * W + i] = river_field(x, z)
			hs[j * W + i] = _height_v(x, z, valley(x, z))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()   # x — расстояние до реки, px со знаком (цвет вершины — всего 8 бит)
	var V := N + 1
	verts.resize(V * V)
	norms.resize(V * V)
	tans.resize(V * V * 4)
	cols.resize(V * V)
	uv2.resize(V * V)
	for j in V:
		for i in V:
			var gi := (j + 1) * W + (i + 1)
			var hx := hs[gi + 1] - hs[gi - 1]
			var hz := hs[gi + W] - hs[gi - W]
			var n := Vector3(-hx, 2.0 * step, -hz).normalized()
			var vi := j * V + i
			verts[vi] = Vector3(ox + i * step, base_y + hs[gi], oz + j * step)
			norms[vi] = n
			var t := Vector3(2.0 * step, hx, 0.0).normalized()
			tans[vi * 4] = t.x
			tans[vi * 4 + 1] = t.y
			tans[vi * 4 + 2] = t.z
			tans[vi * 4 + 3] = -1.0
			# затенение впадин: насколько точка ниже среднего соседей (в R), высота 0…1 (в G)
			var avg := (hs[gi - 1] + hs[gi + 1] + hs[gi - W] + hs[gi + W]) * 0.25
			var cav := clampf(0.5 + (hs[gi] - avg) / 30.0, 0.0, 1.0)
			# поле долин — в UV2: шейдер рисует русло и дорогу
			cols[vi] = Color(cav, hs[gi] / maxf(ceiling, 1.0), 0.5, 1.0)
			uv2[vi] = Vector2(vs[gi], 0.0)
	var idx := PackedInt32Array()
	idx.resize(N * N * 6)
	var p := 0
	for j in N:
		for i in N:
			var a := j * V + i
			var b := a + 1
			var c2 := a + V
			var d := c2 + 1
			# диагональ по меньшему перепаду — меньше «пилы» на гребнях
			if absf(hs[(j + 1) * W + i + 1] - hs[(j + 2) * W + i + 2]) < absf(hs[(j + 1) * W + i + 2] - hs[(j + 2) * W + i + 1]):
				idx[p] = a; idx[p + 1] = b; idx[p + 2] = d
				idx[p + 3] = a; idx[p + 4] = d; idx[p + 5] = c2
			else:
				idx[p] = a; idx[p + 1] = b; idx[p + 2] = c2
				idx[p + 3] = b; idx[p + 4] = d; idx[p + 5] = c2
			p += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TANGENT] = tans
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	if props != null:
		props.build(key, mi)
	return mi


## Самая высокая точка рельефа рядом с p (для стенда скриншотов)
func find_peak(p: Vector2, radius := 6000.0) -> Vector2:
	var best := p
	var best_h := -1.0
	var s := 250.0
	var x := -radius
	while x <= radius:
		var z := -radius
		while z <= radius:
			var h := height(p.x + x, p.y + z)
			if h > best_h:
				best_h = h
				best = Vector2(p.x + x, p.y + z)
			z += s
		x += s
	return best
