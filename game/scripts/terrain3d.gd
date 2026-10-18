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
const FLAT_OBJS := {"o_village": 1.0, "o_fort": 1.0, "o_oasis": 1.0, "o_crater": 0.3}   # o_wreck — без площадки (тест 3.5-s4, п. 18)
const SETTLE := ["o_village", "o_fort", "o_oasis"]
## Профиль поперёк долины по расстоянию до линии реки, px (знак — берег: дорога со стороны «+»)
const D_RIVER := 26.0          # полуширина русла
const D_ROAD := 85.0           # ось дороги
const D_FLOOR := 260.0         # ровное дно долины
const D_FAN := 480.0           # конусы выноса и осыпи до подножия склона
const D_CLIMB := 2200.0        # от подножия до гребня
const V_SCALE := 0.00028       # перевод поля долин в «пиксели» вдали от реки
## Тест 3.5-s5 (M-35, решение Kanta 18.10.2026): охранная зона реки — полуширина от оси русла, px мира.
## Вода (~D_RIVER × 0,8) + мокрый берег шейдера (river_w × 2,4 ± кромка 4 px ≈ 66) + запас 2 px.
## Внутри — только вода и берег: ни объектов клеток, ни предметов биома, ни садов/полей/утоптанной земли,
## ни сцен прошедших боёв и гари, ни наземных активностей. Край зоны (68) не задевает дорогу
## (ось D_ROAD = 85, полоса ±14): колонна едет вдоль реки по дороге, не по воде.
const RIVER_GUARD := 68.0

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
var _scenes := {}              # Vector2i → сцены прошедших боёв клетки (scenes())
var _side := {}                # Vector2i → боковые долины поселений рядом: [[A, B, ширина], …]
var _bg: Background
## Сборка кусков в фоне (тест 3.5-s3: кусок считался в главном потоке до 77 мс — рывки при полёте).
## Высоты и массивы вершин считает пул потоков по снимку данных (ctx), сетку и модели биома
## ставим в главном потоке — не больше одного куска за кадр.
var _pending := {}             # Vector2i → id задачи пула
var _done := {}                # Vector2i → готовые массивы (под _mx)
var _mx := Mutex.new()
var _gen := 0                  # поколение: после clear() результаты старых задач выбрасываем
## Ушедшие с экрана куски не удаляем сразу: в бою кружат на месте — кусок часто нужен снова
var _spare := {}               # Vector2i → MeshInstance3D (скрыт)
var _spare_order: Array[Vector2i] = []
## Высоты построенных кусков (для быстрого surface_fast: тени, высота полёта, наземные цели)
var _hgrid := {}               # Vector2i → [hs, W, step]
const SPARE_MAX := 30
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
	_gen += 1
	_wait_pending()   # потоки читают N — меняем после них
	N = N_GFX[clampi(Settings.gfx, 0, 3)]
	for k in _chunks:
		(_chunks[k] as Node).queue_free()
	_chunks.clear()
	for k in _spare:
		(_spare[k] as Node).queue_free()
	_spare.clear()
	_hgrid.clear()
	_spare_order.clear()
	_objs_cache.clear()
	_side.clear()
	_scenes.clear()


## Расстояние до линии реки, px, со знаком берега; боковые долины поселений сводят его к нулю
func valley(x: float, z: float, ctx := {}) -> float:
	var d := river_field(x, z)
	for s in _sides(x, z, ctx):
		if float(s[2]) < 0.0:
			continue   # ручей (stream_field)
		# L-08: не ближе края русла — иначе врез русла (_height_v) опускал всю площадку поселения
		# на 2,5 % высоты, и край посёлка (линия обороны) уходил под землю
		var dc := maxf(_seg_dist(Vector2(x, z), s[0], s[1]) - float(s[2]) * 0.5, D_RIVER * 1.8)
		if dc < absf(d):
			d = dc
	return d


## Высота рельефа над дном долин (0 … ceiling) в точке мира
func height(x: float, z: float, ctx := {}) -> float:
	return _height_v(x, z, valley(x, z, ctx), ctx)


func _height_v(x: float, z: float, v: float, ctx := {}) -> float:
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
		var step := (floorf(t) + smoothstep(0.12, 0.88, t - floorf(t))) / 7.0
		# 3.4-t1 (п. 18): уступы мягче — обрыв в 1/7 высоты с тенью читался чёрной канавой поперёк склона
		h = lerpf(h, step, 0.28 * steep)
	# мелкие бугры на дне и на конусах
	h += (_hill.get_noise_2d(x, z) + 1.0) * 0.5 * 0.025 * (0.3 + fan)
	h *= _flat(x, z, ctx)
	# русло врезано в пойму: вода лежит в ложбине, а не на ровном месте
	h -= (1.0 - smoothstep(D_RIVER * 0.5, D_RIVER * 1.8, a)) * 0.025
	# L-09: ручей посёлка тоже лежит в ложбинке, мельче реки
	var sd := absf(stream_field(x, z, ctx))
	if sd < STREAM_W * 3.0:
		h -= (1.0 - smoothstep(STREAM_W * 0.6, STREAM_W * 3.0, sd)) * 0.012
	return clampf(h, -0.03, 1.0) * ceiling


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## L-09 (вариант 2 Kanta): ручей долины-притока — полуширина воды, сдвиг от оси долины, во сколько раз
## ручей уже реки в поле шейдера (вода, мокрый берег и колея вдоль ручья рисуются тем же кодом, что у реки)
const STREAM_W := 7.0
const STREAM_OFF := 95.0
const STREAM_K := D_RIVER / 8.5
const STREAM_REACH := 36.0  # дальше ручей в поле не участвует (колея — в 28 px от воды)
const TRIB_MIN := 420.0    # посёлок глубже в долине-притоке, чем дорога: + к полю реки, px
const TRIB_MAX := 760.0


## L-06 (правка Kanta): поливные поля и сады полосой вдоль реки, как зелень вдоль рек в пустыне —
## участками по 1–3 км с разрывами, на каждом берегу свои; ширина гуляет. 0…1 — доля «огородов» в маске земли
const GREEN_W := 520.0   # в единицах поля реки: вдали от русла оно растёт быстрее расстояния (~×2)


func green(x: float, z: float, v := NAN) -> float:
	if is_nan(v):
		v = river_field(x, z)
	var a := absf(v)
	if a < RIVER_GUARD - 4.0 or a > RIVER_GUARD + GREEN_W:
		return 0.0
	var on := smoothstep(-0.06, 0.04, _plains.get_noise_2d(x * 2.6 + 9100.0 * signf(v), z * 2.6 - 4400.0))
	if on <= 0.0:
		return 0.0
	var w := GREEN_W * (0.55 + 0.45 * (_hill.get_noise_2d(x * 0.3 + 500.0, z * 0.3) + 1.0) * 0.5) * sqrt(on)
	# поля — на дне долины и пологих конусах, не на склоне
	return (1.0 - smoothstep(w * 0.75, w, a - RIVER_GUARD)) * smoothstep(RIVER_GUARD - 4.0, RIVER_GUARD + 14.0, a) * (1.0 - smoothstep(D_FLOOR, D_FAN * 0.9, a))


## Расстояние до ручья посёлка, px, со знаком: «+» — к оси долины (там тропа); ручья рядом нет — INF
func stream_field(x: float, z: float, ctx := {}) -> float:
	var best := INF
	var p := Vector2(x, z)
	for s in _sides(x, z, ctx):
		if float(s[2]) >= 0.0:
			continue
		var d := _seg_dist(p, s[0], s[1])
		if d < absf(best):
			var ab: Vector2 = s[1] - s[0]
			var sg := signf(ab.cross(p - (s[0] as Vector2)) * ab.cross(-(s[3] as Vector2)) + 1e-6)
			if s[4] and ab.dot(p - (s[0] as Vector2)) < 0.0:
				sg = 1.0   # за истоком знак не меняется — иначе от истока тянулась бы «вода»
			best = d * sg
	return best if absf(best) < STREAM_REACH else INF


## Сглаживание ломаной (срез углов Чайкина), концы на месте
func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out


## Меандры ручья: мелкие изгибы поперёк течения, у истока и устья — на нет
func _meander(pts: PackedVector2Array, seed_p: Vector2) -> PackedVector2Array:
	var ph := float(absi(hash(Vector2i(roundi(seed_p.x), roundi(seed_p.y)))) % 628) / 100.0
	var n := pts.size()
	for i in range(1, n - 1):
		var t := (pts[i + 1] - pts[i - 1]).normalized().orthogonal()
		var k := sin(PI * float(i) / float(n - 1))
		pts[i] += t * sin(float(i) * 0.6 + ph) * 30.0 * k
	return pts


## Ломаная долины-притока: от посёлка a к ближайшей точке реки, два изгиба по хешу; детерминирована
func _trib(a: Vector2) -> PackedVector2Array:
	var b := _river_point(a)
	var d := b - a
	var n := d.orthogonal().normalized() * d.length()
	var h := hash(Vector2i(roundi(a.x), roundi(a.y)))
	var w1 := (float(h & 0xff) / 255.0 - 0.5) * 0.45
	var w2 := (float((h >> 8) & 0xff) / 255.0 - 0.5) * 0.35
	return PackedVector2Array([a, a + d * 0.35 + n * w1, a + d * 0.7 + n * w2, b])


## Боковые долины поселений, влияющие на клетку точки (от поселения к ближайшей линии реки)
func _sides(x: float, z: float, ctx := {}) -> Array:
	var key := Vector2i(int(floorf(x / CHUNK)), int(floorf(z / CHUNK)))
	if not ctx.is_empty():
		return (ctx["sides"] as Dictionary).get(key, [])
	if _bg == null:
		return []
	if _side.has(key):
		return _side[key]
	var out := []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var o := _obj(Vector2i(key.x + dx, key.y + dz))
			if o.is_empty() or not (o["name"] in SETTLE):
				continue
			var a: Vector2 = o["pos"]
			var sz := float(o["size"])
			if o["name"] != "o_village":
				out.append([a, _river_point(a), sz * 0.75])
				continue
			# L-09: посёлок — в извилистой долине-притоке; вдоль неё — ручей с одной стороны оси
			var tr := _trib(a)
			for i in tr.size() - 1:
				out.append([tr[i], tr[i + 1], sz * (0.75 if i == 0 else 0.5)])
			var nrm := (tr[tr.size() - 1] - a).orthogonal().normalized()
			var R := sz * AdobeBuild.footprint("o_village")
			# исток — сбоку от посёлка, ручей идёт вдоль долины и к устью прижимается к её оси
			var st := PackedVector2Array([a + nrm * (R * 0.8 + 30.0)])
			for i in range(1, tr.size() - 1):
				st.append(tr[i] + nrm * lerpf(R * 0.8 + 30.0, STREAM_OFF, float(i) / float(tr.size() - 1)))
			st.append(tr[tr.size() - 1])
			st = _meander(_chaikin(_chaikin(_chaikin(st))), a)
			for i in st.size() - 1:
				out.append([st[i], st[i + 1], -1.0, nrm, i == 0])
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


## Ближайшая точка русла: шаги Ньютона по полю реки, не сошлись — поиск по кольцам (_river_near).
## Кольца находят точку с самым малым полем, а не самую близкую — боковая долина тянулась вдоль реки
func _river_point(a: Vector2) -> Vector2:
	var q := _field_point(a, 0.0)
	if absf(river_field(q.x, q.y)) <= 4.0 and q.distance_to(a) < 2000.0:
		return q
	return _river_near(a)


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


## M-35: насколько точка p за пределами охранной зоны реки, px (< 0 — внутри зоны).
## margin — полуразмер того, что ставим (радиус объекта, полкорпуса машины): зона расширяется на него
func river_guard_dist(p: Vector2, margin := 0.0) -> float:
	return absf(river_field(p.x, p.y)) - RIVER_GUARD - margin


## M-35: точка p (с запасом margin) в охранной зоне реки — сюда ничего не ставим и не везём
func in_river_guard(p: Vector2, margin := 0.0) -> bool:
	return river_guard_dist(p, margin) < 0.0


## M-35: рельеф боя, если он есть (3D-рендер и фон уже связаны), иначе null — для кода вне Terrain3D
static func active() -> Terrain3D:
	if Render3D.I != null and Render3D.I.terrain != null and Render3D.I.terrain._bg != null:
		return Render3D.I.terrain
	return null


## M-35: то же из любого кода без ссылки на рельеф: нет рельефа (2D, меню) — зоны нет (INF)
static func guard_dist_at(p: Vector2, margin := 0.0) -> float:
	var t := active()
	return t.river_guard_dist(p, margin) if t != null else INF


## M-35: ближайшая к p точка вне охранной зоны (с запасом margin) на том же берегу; p уже вне — p
func out_of_river_guard(p: Vector2, margin := 0.0) -> Vector2:
	for i in 4:
		var v := river_field(p.x, p.y)
		var need := RIVER_GUARD + margin + 2.0
		if absf(v) >= need:
			return p
		var e := 8.0
		var g := Vector2(river_field(p.x + e, p.y) - river_field(p.x - e, p.y), river_field(p.x, p.y + e) - river_field(p.x, p.y - e)) / (2.0 * e)
		if g.length_squared() < 1e-12:
			break
		var side := signf(v) if v != 0.0 else 1.0
		p -= g * (v - side * need) / g.length_squared()
	return p


func _v_raw(x: float, z: float) -> float:
	# сдвиг умеренный: сильный «складывает» поле и рождает замкнутые петли русла — ямы без стока
	var wx := x + _warp.get_noise_2d(x, z) * 380.0
	var wz := z + _warp.get_noise_2d(x + 913.0, z - 377.0) * 380.0
	return _valley.get_noise_2d(wx, wz)


## Ближайшая точка дна долины (не дальше D_FLOOR от реки) около p — для наземной техники.
## Тест 3.5-s4 (п. 20): техника стояла в реке — русло с берегом (M-35: охранная зона RIVER_GUARD
## + полкорпуса машины) и объекты клеток (кишлак, крепость, оазис, воронка, обломки) — запретные;
## если вокруг всё запретное, берётся наименее плохая точка — дальше всех от воды и объектов.
## side ≠ 0 — только этот берег (знак river_field): переезжающая техника не пересекает реку
## avoid — [[точка, радиус]] куда нельзя (другие машины позиции); dry — сколько держаться от линии реки
func find_floor(p: Vector2, radius := 900.0, side := 0.0, avoid := [], dry := RIVER_GUARD + 10.0) -> Vector2:
	var objs := []
	if _bg != null:
		var c := Vector2i(int(floorf(p.x / CHUNK)), int(floorf(p.y / CHUNK)))
		var span := int(ceilf(radius / CHUNK)) + 1
		for dx in range(-span, span + 1):
			for dz in range(-span, span + 1):
				var o := _obj(Vector2i(c.x + dx, c.y + dz))
				if not o.is_empty():
					objs.append([o["pos"], float(o["size"]) * 0.6 + 50.0])
	var best := p
	var best_s := INF
	for ring in range(0, 10):
		var rr := radius * ring / 9.0
		var n := maxi(1, ring * 8)
		for i in n:
			var q := p + Vector2.from_angle(TAU * i / n) * rr
			var a := absf(valley(q.x, q.y))
			var rf := river_field(q.x, q.y)
			var ar := absf(rf)
			# дно долины, но не у воды и не на объекте биома; ближе — лучше
			var sc := maxf(a - D_FLOOR * 0.8, 0.0) / 100.0 + rr / radius * 0.2
			if ar < dry:
				sc += 50.0 + (dry - ar)
			if side != 0.0 and signf(rf) != side:
				sc += 50.0 + ar
			for o in objs + avoid:
				var d := q.distance_to(o[0])
				if d < float(o[1]):
					sc += 50.0 + (float(o[1]) - d)
			if sc < best_s:
				best_s = sc
				best = q
		if best_s < 0.05 + rr / radius * 0.2:
			break
	return best


## Тест 3.5-s4 (п. 20): объект клетки (кишлак, крепость, оазис, воронка, обломки, скалы) не лежит в реке.
## Второй список (п. 16): проверка по кольцам точек на всю площадь объекта (у кишлака — с окраинами,
## AdobeBuild.footprint), а не одной точкой в центре: на изгибе реки оценка поля в центре врёт.
## Задетые водой точки толкают объект прочь; не вышло за 10 шагов — объекта в клетке нет
func fix_object(o: Dictionary) -> Dictionary:
	var p0: Vector2 = o["pos"]
	if o["name"] in SETTLE and _bg != null:
		p0 = _settle_spot(o)
		if not p0.is_finite() or _settle_crowded(o, p0):
			return {}
		if o["name"] == "o_village":   # L-01: главная тропа посёлка (+x объекта) — к реке через дорогу
			o = o.duplicate()
			o["rot"] = (_trib(p0)[1] - p0).angle()   # L-09: вниз по долине-притоку
	elif o["name"] == "o_crater" and absf(_v_raw(p0.x, p0.y)) / V_SCALE > D_FAN:
		return {}   # воронка с площадкой на склоне выглядела ямой в горе: воронки — на дне долин и конусах
	var p := p0
	var R := float(o["size"]) * AdobeBuild.footprint(o["name"])
	var clear := RIVER_GUARD   # M-35: охранная зона — вода и мокрый берег (в шейдере берег темнеет до river_w × 2.4)
	for it in 10:
		var push := Vector2.ZERO
		var worst := 0.0
		for ring: float in [0.0, 0.35, 0.7, 1.0]:
			var n := 1 if ring == 0.0 else int(8.0 + ring * 24.0)
			for i in n:
				var q := p + Vector2.from_angle(TAU * i / n + ring) * R * ring
				var v := river_field(q.x, q.y)
				var w := clear - absf(v)
				if w <= 0.0:
					continue
				worst = maxf(worst, w)
				if ring == 0.0:
					var e := 8.0
					var g := Vector2(river_field(q.x + e, q.y) - river_field(q.x - e, q.y), river_field(q.x, q.y + e) - river_field(q.x, q.y - e))
					if g.length_squared() > 1e-10:
						push += g.normalized() * signf(v + 1e-3) * w * 4.0
				else:
					push -= (q - p).normalized() * w
		if worst <= 0.0:
			var out := o.duplicate()
			out["pos"] = p
			return out
		if push.length_squared() < 1e-8:
			push = Vector2.from_angle(float(it))
		p += push.normalized() * clampf(worst + 12.0, R * 0.08, R * 0.5)
		if p.distance_to(p0) > CHUNK * 0.45:
			break
	return {}


## Карта расстановки (тред «Второй биом», 18.10.2026): поселения — у реки, а не где выпала клетка.
## Кишлак и крепость встают за дорогой (дорога идёт по их краю), оазис — на другом берегу.
## Нет реки ближе SETTLE_REACH — поселения в клетке нет (раньше к нему прорезалась длинная боковая долина)
const SETTLE_REACH := 1300.0   # < CHUNK: сдвинутое поселение остаётся в соседней клетке (_flat смотрит ±1)
const SETTLE_GAP := 2000.0     # между поселениями не ближе


## Место поселения у реки (INF — реки рядом нет)
func _settle_spot(o: Dictionary) -> Vector2:
	var raw: Vector2 = o["pos"]
	var q := _river_point(raw)
	if absf(_v_raw(q.x, q.y)) > 0.01:
		return Vector2.INF
	var R := float(o["size"]) * AdobeBuild.footprint(o["name"])
	var target := D_ROAD + 16.0 + R + 10.0 if o["name"] != "o_oasis" else -(RIVER_GUARD + R + 10.0)
	if o["name"] == "o_village":   # L-09: посёлок — в глубине долины-притока, за дорогой
		target += lerpf(TRIB_MIN, TRIB_MAX, float(absi(hash(raw)) % 1000) / 1000.0)
	var p := _field_point(q + (raw - q).limit_length(40.0), target)
	if p.distance_to(raw) > SETTLE_REACH:
		return Vector2.INF
	return p


## Рядом уже есть поселение с большим приоритетом (от хеша клетки) — это не ставим
func _settle_crowded(o: Dictionary, p: Vector2) -> bool:
	var key := Vector2i(int(floorf((o["pos"] as Vector2).x / CHUNK)), int(floorf((o["pos"] as Vector2).y / CHUNK)))
	var mine := hash(key) & 0xffff
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			if dx == 0 and dz == 0:
				continue
			var k := Vector2i(key.x + dx, key.y + dz)
			if (hash(k) & 0xffff) <= mine:
				continue
			var n := _bg._chunk_object_raw(k.x, k.y)
			if n.is_empty() or not (n["name"] in SETTLE):
				continue
			var np := _settle_spot(n)
			if np.is_finite() and np.distance_to(p) < SETTLE_GAP:
				return true
	return false


## Русло с берегом (как в find_floor): сюда наземная техника не заезжает (M-35: зона + полкорпуса)
func wet(p: Vector2) -> bool:
	return in_river_guard(p, 10.0)


## Тест 3.5-s4 (второй список): «сцены прошедших боёв» — у кишлаков, крепостей и местами у дорог группы
## из 2–5 элементов: подбитый танк с воронками, сгоревший грузовик, упавший самолёт с выгоревшей
## полосой, брошенная позиция из мешков. Модели ставит BiomeProps (k = truck, tank, plane, sandbag),
## выгоревшие пятна и воронки рисует шейдер рельефа (k = scorch, crater). Не в воде и не на берегу,
## не на домах и огородах, не друг в друге; на склон техника не заезжает. Только главный поток (кэш)
## Элемент: {k, p (Vector2), yaw, w (ширина модели, px), r (радиус занятого места, px)}
const SCENE_W := {"tank": 64.0, "truck": 60.0, "plane": 120.0, "sandbag": 48.0}


func scenes(key: Vector2i) -> Array:
	if _bg == null:
		return []
	if _scenes.has(key):
		return _scenes[key]
	if _scenes.size() > 800:
		_scenes.clear()
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0xb477e
	var obj := _obj(key)
	var near := []   # объекты вокруг — сцены их не задевают
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var o := _obj(Vector2i(key.x + dx, key.y + dz))
			if not o.is_empty():
				near.append(o)
	var anchors := []   # [центр, радиус от центра объекта]
	if not obj.is_empty():
		var sz := float(obj["size"])
		match obj["name"]:
			"o_village":   # L-08 (схема Kanta): остовы техники, подбитой при штурме, — перед линией обороны
				for i in (2 if rng.randf() < 0.6 else 1):
					anchors.append([obj["pos"], sz * rng.randf_range(0.62, 0.85), float(obj["rot"]) + PI])
			"o_fort":
				if rng.randf() < 0.6:
					anchors.append([obj["pos"], sz * rng.randf_range(0.75, 1.0)])
			"o_oasis":
				if rng.randf() < 0.25:
					anchors.append([obj["pos"], sz * rng.randf_range(0.6, 0.75)])
	if rng.randf() < 0.1:   # засада у дороги
		var q := Vector2((key.x + rng.randf_range(0.2, 0.8)) * CHUNK, (key.y + rng.randf_range(0.2, 0.8)) * CHUNK)
		anchors.append([_field_point(q, D_ROAD + rng.randf_range(40.0, 120.0) * (1.0 if rng.randf() < 0.6 else -2.5)), 0.0])
	for an in anchors:
		for attempt in 4:
			var a := rng.randf() * TAU if an.size() < 3 else float(an[2]) + rng.randf_range(-0.85, 0.85)
			var c: Vector2 = (an[0] as Vector2) + Vector2.from_angle(a) * float(an[1])
			# у посёлка — подбитая техника, шедшая на посёлок (без брошенных позиций)
			var items := _scene_items(rng, c, near, out, (an[0] as Vector2) - c if an.size() >= 3 else Vector2.ZERO)
			if items.size() >= 2:
				out.append_array(items)
				break
	_scenes[key] = out
	return out


func _scene_items(rng: RandomNumberGenerator, c: Vector2, near: Array, taken: Array, assault := Vector2.ZERO) -> Array:
	var items := []
	var dir := Vector2.from_angle(rng.randf() * TAU)
	var kind := rng.randi() % 3
	if assault != Vector2.ZERO:
		dir = assault.normalized().rotated(rng.randf_range(-0.5, 0.5))
		kind = 0 if rng.randf() < 0.75 else 1
	var side := dir.orthogonal()
	var main: String = ["tank", "plane", "sandbag"][kind]
	if not _scene_put(items, main, c, dir.angle(), near, taken):
		return []
	match kind:
		0:   # подбитый танк: выгорел на месте, рядом воронки, иногда грузовик колонны
			# гарь — рядом и шире корпуса (горело топливо), чтобы тёмный остов не терялся в чёрном пятне
			_scene_put(items, "scorch", c + dir * rng.randf_range(25.0, 40.0), 0.0, near, taken, rng.randf_range(40.0, 52.0))
			_scene_put(items, "crater", c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(70.0, 110.0), 0.0, near, taken, rng.randf_range(24.0, 34.0))
			if rng.randf() < 0.55:
				var t := c + dir * rng.randf_range(95.0, 130.0) + side * rng.randf_range(-25.0, 25.0)
				if _scene_put(items, "truck", t, dir.angle() + rng.randf_range(-0.6, 0.6), near, taken):
					_scene_put(items, "scorch", t - dir * 30.0, 0.0, near, taken, 36.0)
		1:   # упавший самолёт: выгоревшая полоса юза и воронка от удара
			_scene_put(items, "scorch", c - dir * 45.0, 0.0, near, taken, 50.0)
			_scene_put(items, "scorch", c - dir * 105.0, 0.0, near, taken, 40.0)
			_scene_put(items, "crater", c - dir * rng.randf_range(150.0, 180.0), 0.0, near, taken, rng.randf_range(28.0, 38.0))
		2:   # брошенная позиция: мешки, воронки от обстрела, сгоревший грузовик
			_scene_put(items, "sandbag", c + side * rng.randf_range(55.0, 70.0), dir.angle() + 0.4, near, taken)
			for i in rng.randi_range(1, 2):
				_scene_put(items, "crater", c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, 140.0), 0.0, near, taken, rng.randf_range(22.0, 32.0))
			if rng.randf() < 0.45:
				var t := c - side * rng.randf_range(90.0, 120.0)
				if _scene_put(items, "truck", t, rng.randf() * TAU, near, taken):
					_scene_put(items, "scorch", t + side * 28.0, 0.0, near, taken, 34.0)
	return items


## Поставить элемент сцены, если место годится; true — поставлен
func _scene_put(items: Array, k: String, p: Vector2, yaw: float, near: Array, taken: Array, r := 0.0) -> bool:
	var w: float = SCENE_W.get(k, 0.0)
	if r <= 0.0:
		r = w * 0.55
	var mark := k in ["scorch", "crater"]   # пятна могут лежать под техникой
	if in_river_guard(p, r):   # M-35: ни техники, ни гари, ни воронок в охранной зоне реки
		return false
	if absf(valley(p.x, p.y)) > D_FAN:
		return false
	if not mark and absf(river_field(p.x, p.y) - D_ROAD) < 16.0 + r:
		return false   # на самой дороге — колонны biome_props
	for o in near:
		var sz := float(o["size"])
		var off: Vector2 = p - (o["pos"] as Vector2)
		if o["name"] in SETTLE:
			if not AdobeBuild.outside(o["name"], int(o.get("var", 0)), off.rotated(-float(o["rot"])) / sz, r / sz):
				return false
		elif off.length() < sz * 0.5 + r:
			return false
	for lst in [items, taken]:
		for it in lst:
			var both_solid: bool = not mark and not (it["k"] in ["scorch", "crater"])
			var sep: float = (float(it["r"]) + r) if both_solid else (0.0 if not mark or not (it["k"] in ["scorch", "crater"]) else (float(it["r"]) + r) * 0.6)
			if p.distance_to(it["p"]) < sep:
				return false
	items.append({"k": k, "p": p, "yaw": yaw, "w": w, "r": r})
	return true


## Точка около p, где поле реки равно target (шаги Ньютона): у дороги, у берега
func _field_point(p: Vector2, target: float) -> Vector2:
	for i in 5:
		var v := river_field(p.x, p.y)
		var e := 8.0
		var g := Vector2(river_field(p.x + e, p.y) - river_field(p.x - e, p.y), river_field(p.x, p.y + e) - river_field(p.x, p.y - e)) / (2.0 * e)
		if g.length_squared() < 1e-12:
			break
		p -= g * (v - target) / g.length_squared()
	return p


## Точка мира на поверхности рельефа
func surface(x: float, z: float, ctx := {}) -> Vector3:
	return Vector3(x, base_y + height(x, z, ctx), z)


## Точка поверхности по сетке уже построенного куска (как нарисовано, в разы дешевле height());
## куска нет — точный расчёт
func surface_fast(x: float, z: float) -> Vector3:
	var key := Vector2i(int(floorf(x / CHUNK)), int(floorf(z / CHUNK)))
	var g = _hgrid.get(key)
	if g == null:
		return surface(x, z)
	var hs: PackedFloat32Array = g[0]
	var W: int = g[1]
	var step: float = g[2]
	var fx := (x - key.x * CHUNK) / step
	var fz := (z - key.y * CHUNK) / step
	var i := clampi(int(fx), 0, W - 3)
	var j := clampi(int(fz), 0, W - 3)
	var tx := fx - i
	var tz := fz - j
	var gi := (j + 1) * W + (i + 1)
	var h := lerpf(lerpf(hs[gi], hs[gi + 1], tx), lerpf(hs[gi + W], hs[gi + W + 1], tx), tz)
	return Vector3(x, base_y + h, z)


## Под кишлаками, крепостями, оазисами земля ровная (вес 0 — плоско, 1 — рельеф как есть)
func _flat(x: float, z: float, ctx := {}) -> float:
	if _bg == null and ctx.is_empty():
		return 1.0
	var cx := int(floorf(x / CHUNK))
	var cz := int(floorf(z / CHUNK))
	var k := 1.0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var o: Dictionary = (ctx["objs"] as Dictionary).get(Vector2i(cx + dx, cz + dz), {}) if not ctx.is_empty() else _obj(Vector2i(cx + dx, cz + dz))
			if o.is_empty() or not FLAT_OBJS.has(o["name"]):
				continue
			# тест 3.5-s4 (п. 17): площадка неровная — по контуру поселения (AdobeBuild.outline), с мягким краем
			var off := Vector2(x, z) - (o["pos"] as Vector2)
			var r: float = float(o["size"]) * 0.5
			if o["name"] in SETTLE:
				r *= AdobeBuild.outline(int(o.get("var", 0)), off.rotated(-float(o["rot"])).angle()) * (1.15 if o["name"] == "o_village" else 1.0)
			var d := off.length()
			var f := smoothstep(r, r * 2.0, d)
			k = minf(k, lerpf(1.0 - float(FLAT_OBJS[o["name"]]), 1.0, f))
	return k


func _obj(key: Vector2i) -> Dictionary:
	if _bg != null and not _bg.place_filter.is_valid():
		_bg.place_filter = fix_object
	if not _objs_cache.has(key):
		_objs_cache[key] = _bg.chunk_object(key.x, key.y)
	return _objs_cache[key]


## Держим куски рельефа под видимой областью; новые считаем в фоне, ставим не больше budget за кадр
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
		if not _chunks.has(key) and not _spare.has(key):
			missing += 1
	var now := missing > maxi(6, keys.size() / 2)
	for key in keys:
		if _chunks.has(key):
			continue
		if _spare.has(key):   # кусок уже был — просто показываем
			var mi: MeshInstance3D = _spare[key]
			_spare.erase(key)
			_spare_order.erase(key)
			mi.visible = true
			_chunks[key] = mi
			continue
		if now:
			_place_chunk(key, _compute(key, _ctx(key), _gen))
			continue
		var res = _take_done(key)
		if res != null:
			if budget <= 0:
				_put_done(key, res)
				continue
			budget -= 1
			_place_chunk(key, res)
		elif not _pending.has(key) and _pending.size() < 4:
			_pending[key] = WorkerThreadPool.add_task(_compute_bg.bind(key, _ctx(key), _gen), false, "terrain chunk")
	# законченные задачи — забираем id (иначе пул держит их до wait)
	for key in _pending.keys():
		if WorkerThreadPool.is_task_completed(_pending[key]):
			WorkerThreadPool.wait_for_task_completion(_pending[key])
			_pending.erase(key)
	for key in _chunks.keys():
		if not want.has(key):
			var mi: MeshInstance3D = _chunks[key]
			_chunks.erase(key)
			mi.visible = false
			_spare[key] = mi
			_spare_order.append(key)
	while _spare_order.size() > SPARE_MAX:
		var old: Vector2i = _spare_order.pop_front()
		(_spare[old] as Node).queue_free()
		_spare.erase(old)
		_hgrid.erase(old)
	# готовые, но уже не нужные куски не копим
	_mx.lock()
	for key in _done.keys():
		if not want.has(key):
			_done.erase(key)
	_mx.unlock()
	if _objs_cache.size() > 400:
		_objs_cache.clear()


func _take_done(key: Vector2i):
	_mx.lock()
	var r = _done.get(key)
	_done.erase(key)
	_mx.unlock()
	return r


func _put_done(key: Vector2i, res: Dictionary) -> void:
	_mx.lock()
	_done[key] = res
	_mx.unlock()


func _wait_pending() -> void:
	for key in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[key])
	_pending.clear()
	_mx.lock()
	_done.clear()
	_mx.unlock()


func _exit_tree() -> void:
	_wait_pending()


## Снимок данных для фонового расчёта куска: объекты биома и боковые долины вокруг
## (поток только читает их, общие кэши трогает лишь главный поток)
func _ctx(key: Vector2i) -> Dictionary:
	var objs := {}
	var sides := {}
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var k := Vector2i(key.x + dx, key.y + dz)
			objs[k] = _obj(k) if _bg != null else {}
	for dx in range(-2, 3):   # ±2: модели биома у края клетки смотрят и в соседние
		for dz in range(-2, 3):
			var k := Vector2i(key.x + dx, key.y + dz)
			sides[k] = _sides((k.x + 0.5) * CHUNK, (k.y + 0.5) * CHUNK)
	var scn := {}
	if _bg != null:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k := Vector2i(key.x + dx, key.y + dz)
				scn[k] = scenes(k)
	var ctx := {"objs": objs, "sides": sides, "flat": _bg != null, "scenes": scn}
	if props != null:
		ctx["hk"] = props.mesh_heights()
	return ctx


func _compute_bg(key: Vector2i, ctx: Dictionary, gen: int) -> void:
	var res := _compute(key, ctx, gen)
	_mx.lock()
	if gen == _gen:
		_done[key] = res
	_mx.unlock()


## Высоты и массивы вершин куска — чистый расчёт, можно в потоке
func _compute(key: Vector2i, ctx: Dictionary, gen: int) -> Dictionary:
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var step := CHUNK / N
	var W := N + 3   # +1 узел и по одному с каждой стороны — нормали на стыках кусков совпадают
	var hs := PackedFloat32Array()
	var vs := PackedFloat32Array()
	var gs := PackedFloat32Array()   # L-06: зелёная полоса вдоль реки
	hs.resize(W * W)
	vs.resize(W * W)
	gs.resize(W * W)
	for j in W:
		for i in W:
			var x := ox + (i - 1) * step
			var z := oz + (j - 1) * step
			# русло и дорога — по «чистому» полю (река не огибает кишлаки кольцом), высота — с боковыми долинами
			vs[j * W + i] = river_field(x, z)
			gs[j * W + i] = green(x, z, vs[j * W + i])
			var sf := stream_field(x, z, ctx) * STREAM_K   # L-09: ручей — в том же поле, в K раз уже
			if absf(sf) < absf(vs[j * W + i]):
				vs[j * W + i] = sf
			hs[j * W + i] = _height_v(x, z, valley(x, z, ctx), ctx)
	# тест 3.5-s4 (п. 16–17): пятна поселений на земле (утоптанная земля, огороды и сады) — неровные, с мягким
	# краем, по тому же контуру, что постройки (AdobeBuild.ground_mask); выгоревшие пятна и воронки сцен
	# прошедших боёв; у воды и на мокром берегу всё это сходит на нет
	var setl := []
	var area := Rect2(ox, oz, CHUNK, CHUNK)
	if ctx.has("objs"):
		for k in ctx["objs"]:
			var o: Dictionary = ctx["objs"][k]
			if o.is_empty() or not (o["name"] in SETTLE):
				continue
			if area.grow(float(o["size"])).has_point(o["pos"]):
				setl.append(o)
	var burns := []
	if ctx.has("scenes"):
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for it in (ctx["scenes"] as Dictionary).get(Vector2i(key.x + dx, key.y + dz), []):
					if it["k"] in ["scorch", "crater"] and area.grow(float(it["r"])).has_point(it["p"]):
						burns.append(it)
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
			var sm := Vector2.ZERO
			var burn := 0.0
			if not setl.is_empty() or not burns.is_empty():
				var pw := Vector2(ox + i * step, oz + j * step)
				for o in setl:
					var sz := float(o["size"])
					var l := (pw - (o["pos"] as Vector2)).rotated(-float(o["rot"])) / sz
					if l.length_squared() < 1.0:
						var gm := AdobeBuild.ground_mask(o["name"], int(o.get("var", 0)), l)
						sm = Vector2(maxf(sm.x, gm.x), maxf(sm.y, gm.y))
				for it in burns:
					var r := float(it["r"])
					var d := pw.distance_to(it["p"])
					burn = maxf(burn, (1.0 - smoothstep(r * 0.3, r, d)) * (1.0 if it["k"] == "crater" else 0.8))
				# M-35: в охранной зоне масок нет; точный край — в шейдере по расстоянию до реки (river_guard),
				# здесь лишь гасим вершины глубоко в зоне (вершины через 20 px — край по ним был бы «лесенкой»)
				var dry := smoothstep(RIVER_GUARD - 30.0, RIVER_GUARD, absf(vs[gi]))
				sm *= dry
				burn *= dry
			sm.y = maxf(sm.y, gs[gi])
			cols[vi] = Color(cav, hs[gi] / maxf(ceiling, 1.0), sm.x, sm.y)
			uv2[vi] = Vector2(vs[gi], burn)
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
	var put: Dictionary = props.plan(key, ctx) if props != null else {}
	return {"verts": verts, "norms": norms, "tans": tans, "cols": cols, "uv2": uv2, "idx": idx, "gen": gen, "put": put,
		"hs": hs, "W": W, "step": step}


func _place_chunk(key: Vector2i, r: Dictionary) -> void:
	if int(r["gen"]) != _gen:
		return
	var t0 := Time.get_ticks_usec()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = r["verts"]
	arr[Mesh.ARRAY_NORMAL] = r["norms"]
	arr[Mesh.ARRAY_TANGENT] = r["tans"]
	arr[Mesh.ARRAY_COLOR] = r["cols"]
	arr[Mesh.ARRAY_TEX_UV2] = r["uv2"]
	arr[Mesh.ARRAY_INDEX] = r["idx"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	if props != null:
		props.apply(r["put"], mi)
	_chunks[key] = mi
	_hgrid[key] = [r["hs"], r["W"], r["step"]]
	if Main.I != null and Main.I.state == "playing":   # T4-03: рывки от сборки кусков рельефа (главный поток)
		Main.I.tele.chunk_built((Time.get_ticks_usec() - t0) / 1000.0)


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
