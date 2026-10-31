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
const FLAT_OBJS := {"o_village": 1.0, "o_fort": 1.0, "o_oasis": 1.0}   # o_wreck — без площадки (тест 3.5-s4, п. 18); o_crater — метка на земле (S14-10)
## S14-10: radius of a map crater's ground mark, share of its size (the old picture's crater fills ~0.4 of it)
const CRATER_MARK_R := 0.4
const SETTLE := ["o_village", "o_fort", "o_oasis"]
## Профиль поперёк долины по расстоянию до линии реки, px (знак — берег: дорога со стороны «+»)
const D_RIVER := 26.0          # полуширина русла
const D_ROAD := 85.0           # ось дороги
## M-36 (решение Kanta 18.10.2026): дорога шире под машины конвоя — полоса в шейдере земли, px от оси D_ROAD.
## Наружу (от реки) — ROAD_W (было 14, ×1,57); к реке — ROAD_W_IN: край не заходит в охранную зону RIVER_GUARD
## (85 − 14 = 71 > 68). Видимая ширина ~29 px вместо ~20 (×1,45): ось колонны — по-прежнему D_ROAD
## Road must fit 1.5 vehicle bodies. The widest convoy vehicle is the truck: 28 x unit_scale 1.8
## x model width 0.404 = ~20 px, so the solid band must be >= 31 px. The solid part reaches (half-width - 6)
## on each side (soft edge in ground3d.gdshader): (27 - 6) + (16 - 6) = 31 px, 43 px with edges.
## River side 16: the edge still stays outside the guard zone (85 - 16 = 69 > 68)
const ROAD_W := 27.0
const ROAD_W_IN := 16.0
const D_FLOOR := 260.0         # ровное дно долины
const D_FAN := 480.0           # конусы выноса и осыпи до подножия склона
## Тест 3.5-s6 (аудит Р-3, решение Kanta 18.10.2026 — «картографический» масштаб, земля как с 2–4 км):
## склоны вдвое короче и круче (было 2200), рисунок гребней и оврагов мельче (_ero)
const D_CLIMB := 1200.0        # от подножия до гребня
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
var _crag := FastNoiseLite.new()   # M-36: где на склонах скальные выходы (пятна поясов пород)
var _strata := FastNoiseLite.new() # M-36: наклон и изгиб слоёв пород, зубцы гребней
var _ero := FastNoiseLite.new()    # аудит Р-2: сеть острых гребней и оврагов на склонах (не гладкие валы)
## RV-01 (Kanta 2026-10-24): 1 — landform regions (ReliefProvinces), 0 — the relief before RV-01
## (F1 slider relief_variety, --relief0 for "before" frames); the Archipelago ignores it.
var relief_style := 1
var _prov := ReliefProvinces.new()
var _scenes := {}              # Vector2i → сцены прошедших боёв клетки (scenes())
var _side := {}                # Vector2i → боковые долины поселений рядом: [[A, B, ширина], …]
var _split := {}               # RV-05: Vector2i → [valley sides, streams within reach of the cell] (see _split_sides)
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
## Р-13 (аудит 3.5-s6): пока полный кусок на экране не готов, на его месте — заглушка: та же земля
## редкой сеткой (LOD_N ячеек, ~5 мс в главном потоке в облаке против ~100 мс полного куска) с юбкой
## по краю. Раньше там была дыра до фона.
const LOD_N := 14
var _lods := {}                # Vector2i → MeshInstance3D (заглушка до готовности полного куска)
var lod_frames := 0            # кадров, когда кусок на экране показывали заглушкой (стенд, автотест)
var props: BiomeProps          # B-41: модели биома на рельефе (null — без них)
## S14-05: cells whose ground changed mid-sortie (rebuild_area, a fort the activity took). _epoch counts the
## changes per cell: a result computed before the last change is thrown away. _redo holds the old mesh, still
## shown, until the new one is placed, so the rebuild never opens a hole.
var _epoch := {}               # Vector2i → int
var _redo := {}                # Vector2i → MeshInstance3D


## Relief with the valley floor depth px below the combat plane; mountains rise at most
## min(depth − 30, relief_height) above it
func setup(depth: float, mat: Material, bg: Background) -> void:
	base_y = -depth
	_pick_style()
	N = N_GFX[Settings.gopt("terrain")]
	# a gap for bank and model thickness at the combat plane; the mountains keep their own height
	# (relief_height) when the ground goes deeper, so a deeper ground lowers the whole landscape
	ceiling = clampf(depth - 30.0, 0.0, Tuning.g("relief_height"))
	material = mat
	_bg = bg
	_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mask.seed = 7311
	_mask.frequency = 1.0 / 5200.0
	_mask.fractal_type = FastNoiseLite.FRACTAL_FBM
	_mask.fractal_octaves = 2
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.seed = 1291
	_ridge.frequency = 1.0 / 1300.0   # Р-3: мельче (было 1/2100)
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
	_crag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crag.seed = 6151
	_crag.frequency = 1.0 / 1100.0
	_crag.fractal_type = FastNoiseLite.FRACTAL_FBM
	_crag.fractal_octaves = 3
	_strata.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_strata.seed = 3389
	_strata.frequency = 1.0 / 260.0
	_strata.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_strata.fractal_octaves = 2
	_ero.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ero.seed = 2719
	_ero.frequency = 1.0 / 560.0
	_ero.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ero.fractal_octaves = 4
	_ero.fractal_gain = 0.45
	_ero.fractal_lacunarity = 2.1
	_pad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_pad.seed = 4093
	_pad.frequency = 1.0 / 420.0
	_pad.fractal_type = FastNoiseLite.FRACTAL_FBM
	_pad.fractal_octaves = 2
	_find_loops()
	clear()


func clear() -> void:
	_gen += 1
	_wait_pending()   # потоки читают N — меняем после них
	N = N_GFX[Settings.gopt("terrain")]
	for k in _chunks:
		(_chunks[k] as Node).queue_free()
	_chunks.clear()
	for k in _spare:
		(_spare[k] as Node).queue_free()
	_spare.clear()
	for k in _lods:
		(_lods[k] as Node).queue_free()
	_lods.clear()
	for k in _redo:
		(_redo[k] as Node).queue_free()
	_redo.clear()
	_epoch.clear()
	_hgrid.clear()
	_spare_order.clear()
	_objs_cache.clear()
	_alive_mx.lock()
	_alive.clear()
	_alive_mx.unlock()
	_flats.clear()
	_side.clear()
	_split.clear()
	_scenes.clear()


## Расстояние до линии реки, px, со знаком берега; боковые долины поселений сводят его к нулю
func valley(x: float, z: float, ctx := {}, rf := NAN) -> float:
	var d := river_field(x, z) if is_nan(rf) else rf   # rf — уже посчитанное river_field(x, z) (кусок рельефа)
	for s in (_cell_list(ctx, "vsides", x, z) if ctx.has("vsides") else _sides(x, z, ctx)):
		if float(s[2]) < 0.0:
			continue   # ручей (stream_field)
		# L-08: не ближе края русла — иначе врез русла (_height_v) опускал всю площадку поселения
		# на 2,5 % высоты, и край посёлка (линия обороны) уходил под землю
		var e := _seg_dist(Vector2(x, z), s[0], s[1]) - float(s[2]) * 0.5
		if pads_natural and e > 0.0:
			e *= 1.0 + SIDE_WOBBLE * _pad.get_noise_2d(x * SIDE_WOBBLE_F, z * SIDE_WOBBLE_F)
		var dc := maxf(e, D_RIVER * 1.8)
		if dc < absf(d):
			d = dc
	return d


## Высота рельефа над дном долин (0 … ceiling) в точке мира
func height(x: float, z: float, ctx := {}) -> float:
	return _height_v(x, z, valley(x, z, ctx), ctx)


func _height_v(x: float, z: float, v: float, ctx := {}) -> float:
	return _relief(x, z, v, ctx).x


## Высота (x, в px над дном) и маски для шейдера земли: y — скальный выход (0…1), z — осыпь у подножия (0…1).
## M-36 (решение Kanta 18.10.2026): Нагорье — не сплошной песок: на склонах выше дна долины и на гребнях
## обнажённая порода (слоистые уступы с крутыми гранями), под ними светлые осыпи — видно, откуда камни.
## Дно долины (до D_FAN − 40), река, дорога и площадки поселений не меняются
## sd_in — уже посчитанное stream_field(x, z, ctx) (кусок рельефа считает его сам; проход по оптимизации 3.5-s7)
## pv — landform weights already computed for this point (RV-01 chunk build), x < 0 — none.
## gv — gradient of the valley field at the point when the caller has it (chunk grid), INF — computed here,
## NO_GULLIES — relief without the RV-02 gullies (coarse placeholder chunks).
func _relief(x: float, z: float, v: float, ctx := {}, sd_in := NAN, pv := Vector4(-1.0, 0.0, 0.0, 0.0),
		gv := Vector2.INF) -> Vector3:
	if relief_style == 1 and not _sea:
		return _relief_prov(x, z, v, ctx, sd_in, pv, gv)
	var a := absf(v)
	if _sea and a > SEA_W:
		# «Архипелаг»: берег поднимается в _land_k раз быстрее долины Нагорья — узкий пляж, сразу холмы
		# с маквисом (острова не плоские «блины» песка шириной в дно долины)
		# на равнинах (_plains, как «open» ниже) берег остаётся пологим: там пляжи, гавани и позиции ПВО
		var op := smoothstep(-0.45, 0.25, _plains.get_noise_2d(x, z))
		a = SEA_W + (a - SEA_W) * lerpf(1.0, _land_k, op)
	# пойма и конусы выноса: вогнутый подъём к подножию
	var fan := smoothstep(D_FLOOR, D_FAN, a)
	var h := 0.1 * fan * fan
	var open := smoothstep(-0.45, 0.25, _plains.get_noise_2d(x, z))   # 0 — широкая равнина, 1 — горы
	# высота хребта растёт монотонно от подножия (иначе между гребнями — замкнутые ямы без стока),
	# гребневой шум добавляет острые зубцы сверху, а не вычитает долины
	var top := lerpf(0.3, 1.0, open)
	var climb := smoothstep(D_FAN - 40.0, D_CLIMB, a)
	climb = 1.0 - pow(1.0 - climb, 1.6)   # выпуклый склон: круче у подножия плеча, острее у гребня
	h += (top - 0.1) * climb * 0.55
	# проход по оптимизации 3.5-s7: на дне долины (climb = 0) гребни, овраги и скалы дают ровно 0 —
	# шум не считаем (кусок рельефа ~в полтора раза быстрее); шум выходов нужен ещё осыпям у подножия
	var foot := smoothstep(D_FAN - 160.0, D_FAN + 40.0, a) * (1.0 - smoothstep(0.12, 0.3, climb))
	var r := 0.0
	var e := 0.0
	var cr := 0.0
	if climb > 0.0 or foot > 0.0:
		# склон: круто вверх, высота хребта — от гребневого шума (острые гребни) и маски равнин
		var wx := x + _warp.get_noise_2d(x - 311.0, z + 71.0) * 300.0
		var wz := z + _warp.get_noise_2d(x + 57.0, z - 919.0) * 300.0
		cr = _crag.get_noise_2d(wx, wz)
		if climb > 0.0:
			r = clampf((_ridge.get_noise_2d(wx, wz) + 1.0) * 0.5, 0.0, 1.0)
			e = clampf((_ero.get_noise_2d(wx * 0.9 + wz * 0.25, wz) + 1.0) * 0.5, 0.0, 1.0)
	h += r * r * 0.12 * climb * climb * top   # только прибавка: зубцы над склоном, без ям между ними
	# аудит Р-2: гребни и овраги — гребневой шум средней частоты, сила растёт от подножия к гребню;
	# квадрат — острые кромки и округлые днища оврагов; на гребне — главная доля высоты хребта
	var ew := smoothstep(0.0, 0.55, climb)
	h += (e * e * 0.3 - 0.02) * ew * lerpf(0.45, 1.0, open)
	# M-36: скальные выходы — пятна по шуму на склоне (не сплошной пояс) и почти сплошь на гребнях
	var up := smoothstep(0.03, 0.2, climb)   # не ниже подножия склона
	var rock := smoothstep(-0.05, 0.25, cr + climb * 0.3 + e * e * 0.45 + r * r * 0.2 - 0.2) * up * lerpf(0.55, 1.0, open)
	# уступы пород: горизонтальные слои дают скальные пояса на склонах
	# только на крутой части склона — на пологих конусах и плато уступы дают полосы «как горизонтали»
	var steep := smoothstep(0.08, 0.25, climb) * (1.0 - smoothstep(0.7, 0.92, climb))
	if h > 0.16 and steep > 0.0:
		var t := h * 7.0
		var step := (floorf(t) + smoothstep(0.12, 0.88, t - floorf(t))) / 7.0
		# 3.4-t1 (п. 18): уступы мягче — обрыв в 1/7 высоты с тенью читался чёрной канавой поперёк склона
		h = lerpf(h, step, 0.28 * steep * (1.0 - rock))
	if rock > 0.0:
		# слоистые уступы: пласты ~30 px высоты, слегка наклонены и изогнуты; грань пласта круче (уступ),
		# сверху — полка; в пятне выхода порода выпирает над склоном (только прибавка — без ям)
		var sn := _strata.get_noise_2d(x, z)
		var t2 := h * 16.0 + (x * 0.6 + z * 0.8) * 0.00035 + _warp.get_noise_2d(x * 3.0, z * 3.0) * 0.35
		var f2 := t2 - floorf(t2)
		var step2 := (floorf(t2) + smoothstep(0.55, 0.85, f2)) / 16.0
		var dh := step2 - (t2 / 16.0)   # −1/16 … +1/16 вокруг склона
		h += (dh * 0.6 + 0.016 + (sn + 1.0) * 0.01) * rock
	# мелкие бугры на дне и на конусах
	h += (_hill.get_noise_2d(x, z) + 1.0) * 0.5 * 0.025 * (0.3 + fan)
	# M-36: осыпи — конусы у подножия скал (по тому же пятну шума, что выходы выше по склону)
	var scree := foot * smoothstep(-0.1, 0.25, cr + 0.1) * lerpf(0.5, 1.0, open)
	var fl := _flat(x, z, ctx)
	h *= fl * _relief_k
	# русло врезано в пойму: вода лежит в ложбине, а не на ровном месте
	h -= (1.0 - smoothstep(D_RIVER * 0.5, D_RIVER * 1.8, a)) * 0.025
	# L-09: ручей посёлка тоже лежит в ложбинке, мельче реки
	var sd := absf(stream_field(x, z, ctx) if is_nan(sd_in) else sd_in)
	if sd < STREAM_W * 3.0:
		h -= (1.0 - smoothstep(STREAM_W * 0.6, STREAM_W * 3.0, sd)) * 0.012
	return Vector3(clampf(h, -0.03, 1.0) * ceiling, clampf(rock, 0.0, 1.0) * fl, clampf(scree, 0.0, 1.0) * fl)




## Which relief to build: F1 slider relief_variety (0 — before RV-01) or --relief0 (lab frames);
## RV-02 gullies: slider relief_gullies or --gullies0 (frames without them).
## RV-04 landforms (pillars, terraces, gorges): slider relief_landforms or --landforms0.
func _pick_style() -> void:
	var args := OS.get_cmdline_user_args()
	var on := Tuning.g("relief_variety") >= 0.5 and not args.has("--relief0")
	relief_style = 1 if on else 0
	gullies = Tuning.g("relief_gullies") >= 0.5 and not args.has("--gullies0")
	_prov.landforms = Tuning.g("relief_landforms") >= 0.5 and not args.has("--landforms0")
	pads_natural = Tuning.g("map_pads") >= 0.5 and not args.has("--pads0")


var gullies := true   # RV-02: gullies on the RV-01 relief (see _pick_style)
## gv value that turns the gullies off for one call: a placeholder chunk (LOD_N grid, ~100 px) cannot show
## them (the finest are ~100 px wide) and is built on the main thread, where their cost is a frame spike.
const NO_GULLIES := Vector2(-INF, -INF)


## Gradient of the valley field at a point (per px), central differences one chunk grid step apart:
## the same step the chunk build uses (_compute), so height() and the mesh agree at every graphics level
## (the field has kinks where valleys meet, and there a different step gives a different direction).
func valley_grad(x: float, z: float, ctx := {}) -> Vector2:
	var e := CHUNK / N
	return Vector2(valley(x + e, z, ctx) - valley(x - e, z, ctx), valley(x, z + e, ctx) - valley(x, z - e, ctx)) / (2.0 * e)


## Landform weights at a point (see ReliefProvinces.weights): maps, bench frames, shader masks.
func province(x: float, z: float, v := 0.0) -> Vector4:
	return _prov.weights(x, z, v)


## RV-01 relief: mountains by region from ReliefProvinces; settlement flats, the river bed and
## streams cut in here exactly as in the old relief.
func _relief_prov(x: float, z: float, v: float, ctx := {}, sd_in := NAN, pv := Vector4(-1.0, 0.0, 0.0, 0.0),
		gv := Vector2.INF) -> Vector3:
	var a := absf(v)
	if not gullies or gv == NO_GULLIES:
		gv = Vector2.INF
	elif not gv.is_finite() and a > ReliefBalance.D_FAN:   # floor and fan have no gullies: skip the cost there
		gv = valley_grad(x, z, ctx)
	var r := _prov.relief(x, z, a, v, pv, gv)
	var fl := _flat(x, z, ctx)
	var h := r.x * fl
	h -= (1.0 - smoothstep(D_RIVER * 0.5, D_RIVER * 1.8, a)) * 0.025
	var sd := absf(stream_field(x, z, ctx) if is_nan(sd_in) else sd_in)
	if sd < STREAM_W * 3.0:
		h -= (1.0 - smoothstep(STREAM_W * 0.6, STREAM_W * 3.0, sd)) * 0.012
	return Vector3(clampf(h, -0.03, 1.0) * ceiling, r.y * fl, r.z * fl)

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
## 3.5-s8: кишлак-городок вдвое шире (R ≈ 1050 вместо 580) — центр и так дальше от дороги на прирост R;
## глубину в притоке уменьшили (было 420…760), иначе посёлок чаще не находил места (SETTLE_REACH)
const TRIB_MIN := 220.0    # посёлок глубже в долине-притоке, чем дорога: + к полю реки, px
const TRIB_MAX := 520.0


## L-06 (правка Kanta): поливные поля и сады полосой вдоль реки, как зелень вдоль рек в пустыне —
## участками по 1–3 км с разрывами, на каждом берегу свои; ширина гуляет. 0…1 — доля «огородов» в маске земли
const GREEN_W := 520.0   # в единицах поля реки: вдали от русла оно растёт быстрее расстояния (~×2)


func green(x: float, z: float, v := NAN) -> float:
	if _sea:
		return 0.0   # «Архипелаг»: поливных полей вдоль берега нет (оливы и маквис — SeaProps)
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
	for s in (_cell_list(ctx, "streams", x, z) if ctx.has("streams") else _sides(x, z, ctx)):
		if float(s[2]) >= 0.0:
			continue
		var d := _seg_dist(p, s[0], s[1])
		if d < absf(best):
			var ab: Vector2 = s[1] - s[0]
			var sg := signf(ab.cross(p - (s[0] as Vector2)) + 1e-6) * float(s[3])
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
			if o.is_empty() or not (o["name"] in SETTLE) or not shown(o):
				continue   # S14-05: an unused fort spot cuts no side valley (that was the round basin)
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
			# сторона оси долины относительно течения — одна на весь ручей (по сегментам знак «прыгал»
			# на меандрах, и вдоль ручья тянулась ложная тонкая вода)
			var side := signf((tr[tr.size() - 1] - a).cross(-nrm))
			for i in st.size() - 1:
				out.append([st[i], st[i + 1], -1.0, side, i == 0])
	_side[key] = out
	if _side.size() > 600:
		_side.clear()
		_split.clear()
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
	var r := _river_raw(x, z)
	return _coast(x, z, r) if _sea else r


## «Архипелаг» (Biome.sea): поле берега вместо поля реки. Вода — пролив вокруг бывшей реки (полуширина
## strait) минус острова; на суше значение = SEA_W + расстояние от кромки воды (как от реки: охранная зона,
## поселения у «реки», дно долины — всё меряется от берега), в воде — 0 … SEA_W по глубине (0 — ось пролива).
## Шейдер земли рисует воду при |поле| < SEA_W, глубину — по доле SEA_W. Знак — берег пролива, как у реки
const SEA_W := D_RIVER * 0.62   # кромка воды в шейдере (smoothstep river_w × 0.45 … 0.8)
var _sea := false
var _strait := 820.0
var _isl_from := 0.34
var _isl_thr := 0.38
var _isl_k := 520.0
var _isl := FastNoiseLite.new()
var _relief_k := 1.0
var _depth := 450.0
var _land_k := 1.0


func _coast(x: float, z: float, r: float) -> float:
	var a := absf(r)
	var s := a - _strait
	var w := smoothstep(_strait * _isl_from, _strait * (_isl_from + 0.15), a)
	if w > 0.0:
		var isl := (_isl.get_noise_2d(x, z) - _isl_thr) * _isl_k
		s = maxf(s, lerpf(-_strait, isl, w))
	var sg := 1.0 if r >= 0.0 else -1.0
	if s >= 0.0:
		return sg * (SEA_W + s)
	# глубина — по расстоянию от берега (_depth px до полной), а не по доле пролива: у островов вдали от оси
	# вода иначе вся была мелкой и белой от пены
	return sg * SEA_W * clampf(1.0 + s / _depth, 0.0, 1.0)


## «Архипелаг», только для сетки (UV2.x → шейдер): у кромки поле берега в воде меняется в ~28 раз медленнее,
## чем на суше, и при линейной интерполяции по треугольникам берег выходил ломаной («рваный» край, замечание
## Kanta 21.10). Здесь первые SHORE_A пикс. воды идут с тем же шагом 1 ед./пикс., что и суша, дальше — до оси.
## Обратный пересчёт в глубину — в шейдере (ground3d.gdshader, shore_a / sea_depth_px)
const SHORE_A := 12.0
func _shore_u(v: float) -> float:
	var a := absf(v)
	if a >= SEA_W:
		return v
	var d := (1.0 - a / SEA_W) * _depth   # пикс. от берега
	var u := SEA_W - d if d < SHORE_A else (SEA_W - SHORE_A) * clampf(1.0 - (d - SHORE_A) / (_depth - SHORE_A), 0.0, 1.0)
	return u if v >= 0.0 else -u


## Глубина воды 0 (берег) … 1 (ось пролива) по полю берега; на суше < 0
static func sea_depth(v: float) -> float:
	return 1.0 - absf(v) / SEA_W


## Биом мира (Biome.cur()): включает поле берега «Архипелага»; кэш кусков сбрасывает clear()
func set_biome() -> void:
	_sea = Biome.sea()
	_pick_style()
	if _sea:
		# первое обращение к константам SeaProps — в главном потоке, до параллельной генерации клеток
		SeaProps.comp_of(Vector2i.ZERO)
		var _w: Vector2 = SeaProps.SIZE["s_gun"]
	_relief_k = float(Biome.g("relief_k", 1.0))
	_depth = float(Biome.g("depth_px", 450.0))
	_land_k = float(Biome.g("land_k", 1.0))
	_strait = float(Biome.g("strait", 820.0))
	_isl_from = float(Biome.g("isl_from", 0.34))
	_isl_thr = float(Biome.g("isl_thr", 0.38))
	_isl_k = float(Biome.g("isl_k", 520.0))
	_isl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_isl.seed = 4093
	_isl.frequency = float(Biome.g("isl_freq", 1.0 / 950.0))
	_isl.fractal_type = FastNoiseLite.FRACTAL_FBM
	_isl.fractal_octaves = 3


func _river_raw(x: float, z: float) -> float:
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


const RIVER_STEP := 12.0   # river_clear: arc between samples, px (the river bed is 2 × D_RIVER = 52 px wide)
const RIVER_RING := 40.0   # river_clear: gap between circles, px


## Kanta 24.10: true when no river water line passes within d px (real distance) of p. river_field is
## not a distance far from the river (field 400 can be 80 px from the water or 1200 px), so the check
## looks for the river itself: its line splits the field sign, so a line closer than d crosses one of
## the circles around p. Circles every RIVER_RING px out to d: the zero line also makes small closed
## loops (ponds in bends) that would slip between two far-apart circles.
## Cost: ~TAU·(sum of radii)/RIVER_STEP field samples (~210 for d = 170, ~560 for d = 260)
func river_clear(p: Vector2, d: float) -> bool:
	if _sea:   # «Архипелаг»: the coast field is already SEA_W + distance from the water edge
		return absf(river_field(p.x, p.y)) >= d
	var s := signf(river_field(p.x, p.y))
	var k := maxi(1, ceili(d / RIVER_RING))
	for j in range(1, k + 1):
		var r := d * j / k
		var n := maxi(8, ceili(TAU * r / RIVER_STEP))
		for i in n:
			var q := p + Vector2.from_angle(TAU * i / n) * r
			if signf(river_field(q.x, q.y)) != s:
				return false
	return true


## Real distance from p to the river line, px, capped at cap (bisection over river_clear, to cap/1024).
## For checks and tests; placement uses river_clear directly
func river_dist(p: Vector2, cap := 1000.0) -> float:
	if river_clear(p, cap):
		return cap
	var lo := 0.0
	var hi := cap
	for i in 10:
		var mid := (lo + hi) * 0.5
		if river_clear(p, mid):
			lo = mid
		else:
			hi = mid
	return lo


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
	for i in 10:   # S10-02: у изрезанного берега «Архипелага» 4 шагов не хватало — бункер оставался у воды
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


## S9-07/S9-08 (правка Kanta 23.10): охранная полоса ручья посёлка (протоки долины-притока) — полуширина
## от оси, px мира. Вода и мокрый берег ручья рисуются полем stream_field × STREAM_K тем же кодом, что у реки,
## и доходят до охранной зоны реки (RIVER_GUARD) при ~RIVER_GUARD / STREAM_K ≈ 22 px. river_field ручьёв
## не видит — расстановка у посёлков проверяет их отдельно (in_water, village_water)
const STREAM_GUARD := RIVER_GUARD / STREAM_K


## S9-07/S9-08: расстояние до оси ближайшего ручья посёлка, px (без отсечки STREAM_REACH); ручьёв рядом нет — INF
func stream_dist(p: Vector2, ctx := {}) -> float:
	var best := INF
	for s in _sides(p.x, p.y, ctx):
		if float(s[2]) < 0.0:
			best = minf(best, _seg_dist(p, s[0], s[1]))
	return best


## S9-07/S9-08: точка p (с запасом margin) в охранной зоне реки или ручья посёлка — сюда ничего не ставим.
## Для расстановки, не для езды: ручей пересекает дорогу под мостом (wet() его не учитывает)
func in_water(p: Vector2, margin := 0.0, ctx := {}) -> bool:
	return in_river_guard(p, margin) or stream_dist(p, ctx) < STREAM_GUARD + margin


## S9-07/S9-08: вода у посёлка o в осях его сетки (старые единицы AdobeBuild) — для AdobeBuild.village_edge:
## оси ручьёв в радиусе окраины, полуширина их охранной полосы и запас до охранной зоны реки
func village_water(o: Dictionary) -> Dictionary:
	var c: Vector2 = o["pos"]
	var rot := float(o["rot"])
	var k := float(o["size"]) * AdobeBuild.V_UNIT   # px мира в одной старой единице
	var reach := k * (AdobeBuild.V_EDGE * 1.2 * 1.5 + 0.2) + STREAM_GUARD
	var segs := []
	for s in _sides(c.x, c.y):
		if float(s[2]) < 0.0 and _seg_dist(c, s[0], s[1]) < reach:
			segs.append([((s[0] as Vector2) - c).rotated(-rot) / k, ((s[1] as Vector2) - c).rotated(-rot) / k])
	var river := func(u: Vector2) -> float: return river_guard_dist(c + (u * k).rotated(rot)) / k
	# id — ключ кэша AdobeBuild.village_at: место, биом (своя река) и ручьи
	return {"id": "%s:%d,%d:%d" % [str(Biome.id), roundi(c.x), roundi(c.y), hash(segs)], "segs": segs, "w": STREAM_GUARD / k, "river": river}


func _v_raw(x: float, z: float) -> float:
	# сдвиг умеренный: сильный «складывает» поле и рождает замкнутые петли русла — ямы без стока
	var wx := x + _warp.get_noise_2d(x, z) * 380.0
	var wz := z + _warp.get_noise_2d(x + 913.0, z - 377.0) * 380.0
	var v := _valley.get_noise_2d(wx, wz)
	if not _loops.is_empty():   # L-02: заплатки на мелкие кольца реки
		for b in _loops.get(Vector2i(floori(x / LOOP_CELL), floori(z / LOOP_CELL)), _NO_LOOPS):
			var d := Vector2(x, z).distance_to(b[0])
			if d < float(b[3]):
				v -= float(b[1]) * 1.25 * (1.0 - smoothstep(float(b[2]), float(b[3]), d))
	return v


## L-02 (правка Kanta 18.10, вариант «2»: заплатка, без перестройки сети): река — нулевая линия поля
## долин, и местами она замыкалась в кольцо вокруг «острова» поля другого знака. Один раз при запуске
## ищем такие острова (связные области одного знака, не касающиеся края, меньше LOOP_MAX) на сетке
## LOOP_STEP и поднимаем поле внутри до знака окружения: кольцо пропадает, снаружи поле только
## удаляется от нуля (соседние реки не сдвигаются). Остров накрывается целиком (поле в нём по модулю
## не больше его максимума v_e), край заплатки мягкий
const LOOP_STEP := 300.0
const LOOP_HALF := 54000.0     # область поиска вокруг начала мира, px
const LOOP_MAX := 16.0e6       # площадь острова, px² (~16 км²: на 80 × 80 км таких было ~28)
const LOOP_FADE := 1400.0
const LOOP_CELL := 4000.0
const _NO_LOOPS := []
var _loops := {}               # Vector2i ячейки LOOP_CELL → [[центр, v_e, R, R + LOOP_FADE], …]; после setup только читается


func _find_loops() -> void:
	_loops = {}
	_find_loops_pass()
	_find_loops_pass()   # второй проход по уже залатанному полю: остатки колец у края заплаток


func _find_loops_pass() -> void:
	var n := int(2.0 * LOOP_HALF / LOOP_STEP)
	var vs := PackedFloat32Array()
	vs.resize(n * n)
	for j in n:
		for i in n:
			vs[j * n + i] = _v_raw(-LOOP_HALF + i * LOOP_STEP, -LOOP_HALF + j * LOOP_STEP)
	var lab := PackedInt32Array()
	lab.resize(n * n)
	lab.fill(-1)
	var cmax := int(LOOP_MAX / (LOOP_STEP * LOOP_STEP))
	var c := 0
	for s0 in n * n:
		if lab[s0] >= 0:
			continue
		var pos := vs[s0] > 0.0
		var st: Array[int] = [s0]
		var cells: Array[int] = []
		lab[s0] = c
		var border := false
		while not st.is_empty():
			var k: int = st.pop_back()
			cells.append(k)
			var i: int = k % n
			var j: int = k / n
			if i == 0 or j == 0 or i == n - 1 or j == n - 1:
				border = true
			for kk: int in [k - 1 if i > 0 else -1, k + 1 if i < n - 1 else -1, k - n if j > 0 else -1, k + n if j < n - 1 else -1]:
				if kk >= 0 and lab[kk] < 0 and (vs[kk] > 0.0) == pos:
					lab[kk] = c
					st.append(kk)
		c += 1
		if border or cells.size() > cmax:
			continue
		var best := cells[0]
		for k in cells:
			if absf(vs[k]) > absf(vs[best]):
				best = k
		var ctr := Vector2(-LOOP_HALF + (best % n) * LOOP_STEP, -LOOP_HALF + (best / n) * LOOP_STEP)
		var r := 0.0
		for k in cells:
			r = maxf(r, ctr.distance_to(Vector2(-LOOP_HALF + (k % n) * LOOP_STEP, -LOOP_HALF + (k / n) * LOOP_STEP)))
		r += LOOP_STEP * 2.0
		var b := [ctr, vs[best], r, r + LOOP_FADE]
		var reach := r + LOOP_FADE
		for gx in range(floori((ctr.x - reach) / LOOP_CELL), floori((ctr.x + reach) / LOOP_CELL) + 1):
			for gz in range(floori((ctr.y - reach) / LOOP_CELL), floori((ctr.y + reach) / LOOP_CELL) + 1):
				var gk := Vector2i(gx, gz)
				if not _loops.has(gk):
					_loops[gk] = []
				_loops[gk].append(b)


## Ближайшая точка дна долины (не дальше D_FLOOR от реки) около p — для наземной техники.
## Тест 3.5-s4 (п. 20): техника стояла в реке — русло с берегом (M-35: охранная зона RIVER_GUARD
## + полкорпуса машины) и объекты клеток (кишлак, крепость, оазис, воронка, обломки) — запретные;
## если вокруг всё запретное, берётся наименее плохая точка — дальше всех от воды и объектов.
## side ≠ 0 — только этот берег (знак river_field): переезжающая техника не пересекает реку
## avoid — [[точка, радиус]] куда нельзя (другие машины позиции); dry — сколько держаться от линии реки
## flat — только равнина (flat_at): тест 3.5-s7, позиции ПВО оказывались на склоне
## S10-02: вода (wet) запретна всегда — у моря ПВО вставала в пролив; суши в радиусе нет — радиус шире
## max_h — highest ground still counted as "flat" when flat is on (AA sites: any level ground,
## also hill flats and mesa tops away from the river; others: valley floor only, FLAT_H).
## dry_streams — also keep out of village streams (AA sites). Off by default: settlements are
## placed with find_floor and streams come from settlements, so checking them there recurses.
func find_floor(p: Vector2, radius := 900.0, side := 0.0, avoid := [], dry := RIVER_GUARD + 10.0, flat := false,
		max_h := FLAT_H, dry_streams := false) -> Vector2:
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
			if ar < RIVER_GUARD + 10.0:   # S10-02: в воде (wet) — хуже склона, чужого берега и соседей: у моря воды много
				sc += 1000.0
			elif dry_streams and stream_dist(q) < STREAM_GUARD + 10.0:   # ручей посёлка — тоже вода (Kanta 24.10: бункер в воде)
				sc += 1000.0
			if side != 0.0 and signf(rf) != side:
				sc += 50.0 + ar
			for o in objs + avoid:
				var d := q.distance_to(o[0])
				if d < float(o[1]):
					sc += 50.0 + (float(o[1]) - d)
			if flat and sc < best_s and not flat_at(q, 0.0, max_h):
				sc += 30.0 + height_drawn(q.x, q.y) / 10.0   # склон — штраф меньше воды и соседей, больше дальности
			if sc < best_s:
				best_s = sc
				best = q
		if best_s < 0.05 + rr / radius * 0.2:
			break
	if wet(best) and radius < 6000.0:   # S10-02: вокруг одна вода (пролив «Архипелага») — ищем сушу шире
		return find_floor(p, radius * 2.5, side, avoid, dry, flat, max_h, dry_streams)
	return best


## Равнина (тест 3.5-s7: позиции ПВО — только на равнинах): не выше FLAT_H над поймой,
## наклон не круче FLAT_K (по 4 точкам в FLAT_E), не в русле с берегом (+ margin)
const FLAT_H := 60.0   # выше — уже не дно долины и не пологий конус выноса, а плечо горы
const FLAT_K := 0.12
const FLAT_E := 24.0


## max_h: highest ground that still counts (FLAT_H — valley floor and fans; INF — any level ground).
## Main thread only (reads the built chunk grid through height_drawn).
func flat_at(p: Vector2, margin := 10.0, max_h := FLAT_H) -> bool:
	if absf(river_field(p.x, p.y)) < RIVER_GUARD + margin:
		return false
	var h := height_drawn(p.x, p.y)
	if h > max_h:
		return false
	for d: Vector2 in [Vector2(FLAT_E, 0), Vector2(-FLAT_E, 0), Vector2(0, FLAT_E), Vector2(0, -FLAT_E)]:
		if absf(height_drawn(p.x + d.x, p.y + d.y) - h) > FLAT_K * FLAT_E:
			return false
	return true


## RV-03: height as the ground is drawn (built chunk grid, the same surface vehicles stand on through
## surface_fast); no chunk there yet — the exact height(). The grid is a lookup, height() with the
## RV-02 gullies is ~70 µs, and site searches (AASite.place at spawn) check hundreds of points on
## the main thread. Main thread only: _hgrid is filled by _place_chunk there.
func height_drawn(x: float, z: float) -> float:
	return surface_fast(x, z).y - base_y


## Точка дна главной долины на off px от линии реки, на том берегу, где p (тест 3.5-s7: позиция ПВО,
## выпавшая среди гор дальше поиска find_floor, переезжает на ближайшую равнину у реки)
func floor_near(p: Vector2, off: float) -> Vector2:
	var side := signf(river_field(p.x, p.y))
	var q := _river_point(p)
	return _field_point(q + (p - q).limit_length(40.0), (side if side != 0.0 else 1.0) * off)


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
	elif o["name"] == "o_mesa" and _bg != null and _mesa_blocked(o, p0):
		return {}
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
## Clear ground between the edges of two settlements (village, fort, oasis), px: one screen width at the
## default zoom (1920), so two big structures never share the screen (Kanta 26.10, s12: two forts and a
## fort with a village side by side; the old 2000 px between centres left ~500 px between the walls).
const SETTLE_GAP := 1920.0
## A mesa keeps this much ground clear of any settlement edge, px (a fort used to stand half on a mesa)
const MESA_GAP := 150.0


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


## True when a placed settlement of higher priority (cell hash) stands closer than SETTLE_GAP edge to edge,
## so this one is not placed. "Placed" is decided greedily from the highest priority down (_settle_alive),
## so a candidate dropped by a third one does not block anything: the map keeps as many settlements as fit.
## The search spans SETTLE_CELLS cells: two villages plus the gap plus SETTLE_REACH fit inside it.
const SETTLE_CELLS := 5
## Cell → whether its settlement candidate is placed (_settle_alive); chunk threads share it under the mutex
var _alive := {}
var _alive_mx := Mutex.new()


func _settle_crowded(o: Dictionary, p: Vector2) -> bool:
	var key := Vector2i(int(floorf((o["pos"] as Vector2).x / CHUNK)), int(floorf((o["pos"] as Vector2).y / CHUNK)))
	var mine := hash(key) & 0xffff
	var r := _settle_r(o)
	for dx in range(-SETTLE_CELLS, SETTLE_CELLS + 1):
		for dz in range(-SETTLE_CELLS, SETTLE_CELLS + 1):
			if dx == 0 and dz == 0:
				continue
			var k := Vector2i(key.x + dx, key.y + dz)
			if (hash(k) & 0xffff) <= mine:
				continue
			var n := _bg._chunk_object_raw(k.x, k.y)
			if n.is_empty() or not (n["name"] in SETTLE):
				continue
			var np := _settle_spot(n)
			if np.is_finite() and np.distance_to(p) < r + _settle_r(n) + SETTLE_GAP and _settle_alive(k):
				return true
	return false


## Whether the settlement candidate of cell `k` is placed: it has a settle spot and no placed settlement of
## higher priority crowds it. Recursion only climbs to higher priorities, so it ends; results are cached.
func _settle_alive(k: Vector2i) -> bool:
	_alive_mx.lock()   # Godot's Mutex is recursive: the nested calls below lock it again
	if _alive.has(k):
		var hit: bool = _alive[k]
		_alive_mx.unlock()
		return hit
	var ok := false
	var n := _bg._chunk_object_raw(k.x, k.y)
	if not n.is_empty() and n["name"] in SETTLE:
		var np := _settle_spot(n)
		ok = np.is_finite() and not _settle_crowded(n, np)
	if _alive.size() > 20000:
		_alive.clear()
	_alive[k] = ok
	_alive_mx.unlock()
	return ok


## Radius a big object takes on the ground, px (AdobeBuild.footprint of its size).
func _settle_r(o: Dictionary) -> float:
	return float(o["size"]) * AdobeBuild.footprint(o["name"])


## True when a placed settlement (village, fort, oasis) covers the ground mesa `o` at `p` would stand on.
## Settlements are read through the filter (cached), so their final, river-pushed spot counts.
func _mesa_blocked(o: Dictionary, p: Vector2) -> bool:
	var key := Vector2i(int(floorf((o["pos"] as Vector2).x / CHUNK)), int(floorf((o["pos"] as Vector2).y / CHUNK)))
	var r := _settle_r(o)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if dx == 0 and dz == 0:
				continue
			var raw := _bg._chunk_object_raw(key.x + dx, key.y + dz)
			if raw.is_empty() or not (raw["name"] in SETTLE):
				continue   # only settlements go through the filter here: a mesa next door would recurse
			var n := _bg.chunk_object(key.x + dx, key.y + dz)
			if n.is_empty():
				continue
			if (n["pos"] as Vector2).distance_to(p) < r + _settle_r(n) + MESA_GAP:
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
## Render layer only the ground has: scorch and crater decals project onto it alone, so a wreck, a house or a
## truck standing in a fresh scorch is not painted with the burnt ground texture (Kanta 26.10)
const DECAL_LAYER := 1 << 18
const SCENE_W := {"tank": 64.0, "truck": 60.0, "plane": 120.0, "sandbag": 48.0}


func scenes(key: Vector2i) -> Array:
	if _bg == null or _sea:   # сцены боёв Нагорья (засады у дороги, техника у кишлаков) — не у моря
		return []
	if _scenes.has(key):
		return _scenes[key]
	if _scenes.size() > 800:
		_scenes.clear()
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0xb477e
	var obj := _obj(key)
	var near := []   # объекты вокруг — сцены их не задевают (±2: кишлак-городок с окраинами шире клетки)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
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
			"o_fort":   # the fort shows only once «Укрепрайон» takes it (Kanta s13): no wreck ring round an empty pad
				rng.randf()   # the draw stays so the tile's other wrecks keep their places
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
	if in_water(p, r):   # M-35, S9-08: ни техники, ни гари, ни воронок в охранной зоне реки и ручья посёлка
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


## Под кишлаками, крепостями, оазисами земля ровная (вес 0 — плоско, 1 — рельеф как есть).
## 3.5-s8: кишлак-городок крупнее (площадка с краем до ~2600 px) — смотрим объекты ±3 клетки (список
## площадок заранее: в снимке ctx — «flats», в главном потоке — кэш по клетке)
func _flat(x: float, z: float, ctx := {}) -> float:
	if _bg == null and ctx.is_empty():
		return 1.0
	var lst: Array = ctx["flats"] if ctx.has("flats") else _flats_near(Vector2i(int(floorf(x / CHUNK)), int(floorf(z / CHUNK))))
	var k := 1.0
	for o: Dictionary in lst:
		# тест 3.5-s4 (п. 17): площадка неровная — по контуру поселения (AdobeBuild.outline), с мягким краем
		var off := Vector2(x, z) - (o["pos"] as Vector2)
		var r: float = float(o["size"]) * 0.5
		var big := r * (1.2 * 1.15 if o["name"] in SETTLE else 1.0) * (PAD_REACH if pads_natural else 2.0)
		if off.length_squared() >= big * big:
			continue
		if o["name"] in SETTLE:
			r *= AdobeBuild.outline(int(o.get("var", 0)), off.rotated(-float(o["rot"])).angle()) * (1.15 if o["name"] == "o_village" else 1.0)
		var d := off.length()
		var f := smoothstep(r, r * 2.0, d)
		if pads_natural and d > r:
			f = smoothstep(r, r * 2.0, r + (d - r) * pad_edge_k(o["pos"], off, r))
		k = minf(k, lerpf(1.0 - float(FLAT_OBJS[o["name"]]), 1.0, f))
	return k


var _flats := {}

## S14-05 (Kanta 31.10: «ровные выровненные круги»): the pad under a settlement no longer ends on a circle.
## Its fade-out distance changes with the direction (noise sampled on a ring round the pad, so along one ray
## the height still only rises), from PAD_K_MIN to PAD_K_MAX of the old r…2r fade: a ragged edge, as if the
## valley floor ran into the slopes. The flat core (r) under the buildings stays as it was.
## F1 slider map_pads or --pads0 (frames without it).
var pads_natural := true
const PAD_K_MIN := 0.7
const PAD_K_MAX := 1.6
## How far a pad reaches, in r: the fade ends at r + r / PAD_K_MIN at most
const PAD_REACH := 1.0 + 1.0 / PAD_K_MIN
var _pad := FastNoiseLite.new()
## S14-05: the side valley of a settlement (a capsule from it to the river, _sides) gave a round basin; with
## pads_natural its edge distance is scaled by 1 ± SIDE_WOBBLE of low-frequency noise (the _pad noise
## stretched SIDE_WOBBLE_F times, ~1/1700 px), gentle enough that the ground still only rises away from it.
const SIDE_WOBBLE := 0.3
const SIDE_WOBBLE_F := 0.25


## Fade-speed factor of a pad edge in the direction of `off` from the pad centre `c` (r — the pad's radius):
## PAD_K_MIN (wide, gentle edge) … PAD_K_MAX (short edge). Constant along the ray, see pads_natural.
func pad_edge_k(c: Vector2, off: Vector2, r: float) -> float:
	var q := c + off.normalized() * r * 1.5
	var n := clampf(_pad.get_noise_2d(q.x, q.y) * 1.8, -1.0, 1.0)
	return lerpf(PAD_K_MIN, PAD_K_MAX, n * 0.5 + 0.5)


## Whether a map object marks the ground (pad, trodden earth and fields, props round it). Kanta s13: a fort
## is no scenery and shows only once «Укрепрайон» takes it (Background.forts_hit), so before that its
## spot is plain land: S14-05, the empty pads with fields round them were those forts. Main thread only.
func shown(o: Dictionary) -> bool:
	return o.get("name", "") != "o_fort" or _bg == null or _bg.forts_hit.has(FortView.key_of(o["pos"]))


## Rebuilds the ground of every cell within `radius` of `c` (S14-05: the fort the activity just took gets
## its pad, earth and props). Cells on screen keep their old mesh until the new one is ready (_redo), cached
## and half-built results are dropped (_epoch). The activity takes forts far off screen, so the swap is
## not seen. Main thread only.
func rebuild_area(c: Vector2, radius: float) -> void:
	_flats.clear()
	_side.clear()   # the settlement's side valley (_sides) comes with it; ±2 cells read it, so clear all
	_split.clear()
	for cx in range(int(floorf((c.x - radius) / CHUNK)), int(floorf((c.x + radius) / CHUNK)) + 1):
		for cz in range(int(floorf((c.y - radius) / CHUNK)), int(floorf((c.y + radius) / CHUNK)) + 1):
			var key := Vector2i(cx, cz)
			_epoch[key] = int(_epoch.get(key, 0)) + 1
			_hgrid.erase(key)
			if _spare.has(key):
				(_spare[key] as Node).queue_free()
				_spare.erase(key)
				_spare_order.erase(key)
			if _chunks.has(key):
				if _redo.has(key):
					(_chunks[key] as Node).queue_free()
				else:
					_redo[key] = _chunks[key]
				_chunks.erase(key)
			_mx.lock()
			_done.erase(key)
			_mx.unlock()


## Объекты с площадкой (FLAT_OBJS) в клетках ±3 от key — только главный поток
func _flats_near(key: Vector2i) -> Array:
	if _flats.has(key):
		return _flats[key]
	var out := []
	if _bg != null:
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var o := _obj(Vector2i(key.x + dx, key.y + dz))
				if not o.is_empty() and FLAT_OBJS.has(o["name"]) and shown(o):
					out.append(o)
	if _flats.size() > 2000:
		_flats.clear()
	_flats[key] = out
	return out


func _obj(key: Vector2i) -> Dictionary:
	if _bg != null and not _bg.place_filter.is_valid():
		_bg.place_filter = fix_object
	if not _objs_cache.has(key):
		_objs_cache[key] = _bg.chunk_object(key.x, key.y)
	return _objs_cache[key]


## Держим куски рельефа под видимой областью; новые считаем в фоне, ставим не больше budget за кадр.
## core — земля, видимая на экране прямо сейчас (view — она же с запасом): кусок в core не ждёт очереди —
## готовый ставится сверх бюджета, неготовый закрывается заглушкой (Р-13)
func sync(view: Rect2, budget := 2, core := Rect2()) -> void:
	var want := {}
	for cx in range(int(floorf(view.position.x / CHUNK)), int(floorf(view.end.x / CHUNK)) + 1):
		for cz in range(int(floorf(view.position.y / CHUNK)), int(floorf(view.end.y / CHUNK)) + 1):
			want[Vector2i(cx, cz)] = true
	# сначала ближние к центру
	var c := view.get_center() / CHUNK
	if core.has_area():
		c = core.get_center() / CHUNK
	var keys := want.keys()
	keys.sort_custom(func(a, b): return Vector2(a).distance_squared_to(c) < Vector2(b).distance_squared_to(c))
	# скачок камеры (старт, стенд, телепорт отладки): не хватает многих кусков — строим все сразу,
	# иначе на экране дыра до фона
	var missing := 0
	for key in keys:
		# RV-05: a key already on its way (placeholder up, full chunk in the background) is not missing
		if not _chunks.has(key) and not _spare.has(key) and not _lods.has(key) and not _pending.has(key) \
				and not _redo.has(key):
			missing += 1
	var now := missing > maxi(6, keys.size() / 2)
	var hole := false
	var batch: Array[Vector2i] = []
	var lods: Array[Vector2i] = []
	for key in keys:
		if _chunks.has(key):
			continue
		if _spare.has(key):   # кусок уже был — просто показываем
			var mi: MeshInstance3D = _spare[key]
			_spare.erase(key)
			_spare_order.erase(key)
			mi.visible = true
			_chunks[key] = mi
			_drop_lod(key)
			continue
		var on_screen := core.has_area() and core.intersects(Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK)))
		if now:
			# RV-05: only what is on screen is built in full right away; the margin (off screen, kept for
			# shadows and camera drift) gets a coarse placeholder in the same batch and its full chunk
			# in the background, so the start freeze no longer pays for chunks nobody sees yet
			if on_screen or not core.has_area():
				batch.append(key)
				continue
			var ready = _take_done(key)
			if ready != null:   # computed earlier in the background: place it, no placeholder needed
				_place_chunk(key, ready)
			elif not _lods.has(key) and not _redo.has(key):
				lods.append(key)
			continue
		var res = _take_done(key)
		if res != null:
			if budget <= 0 and not (on_screen and not _lods.has(key)):
				_put_done(key, res)
				continue
			budget -= 1
			var tp := Time.get_ticks_usec()
			_place_chunk(key, res)
			if Perf.on: Perf.peak("ter.place_max", Perf.sub("ter.place", tp) - tp)
			continue
		if not _pending.has(key) and (_pending.size() < 4 or on_screen):
			var tc := Time.get_ticks_usec()
			_pending[key] = WorkerThreadPool.add_task(_compute_bg.bind(key, _ctx(key), _gen), false, "terrain chunk")
			if Perf.on: Perf.sub("ter.ctx", tc)
		if on_screen and not _redo.has(key):   # a cell being rebuilt keeps its old mesh meanwhile
			hole = true
			if not _lods.has(key):
				var tl := Time.get_ticks_usec()
				_place_chunk(key, _compute(key, _ctx(key), _gen, LOD_N))
				if Perf.on: Perf.peak("ter.lod_max", Perf.sub("ter.lod", tl) - tl)
	if not batch.is_empty() or not lods.is_empty():
		var tb := Time.get_ticks_usec()
		_build_now(batch, lods)
		if Perf.on: Perf.peak("ter.now_max", Perf.sub("ter.now", tb) - tb)
	if hole:
		lod_frames += 1
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
	for key in _lods.keys():
		if not want.has(key):
			_drop_lod(key)
	for key in _redo.keys():
		if not want.has(key):
			(_redo[key] as Node).queue_free()
			_redo.erase(key)
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
		_flats.clear()


var _batch_keys: Array[Vector2i] = []
var _batch_ctx: Array = []
var _batch_res: Array = []
var _batch_full := 0


## Скачок камеры / старт вылета: недостающие куски строим сразу, но всеми ядрами (проход по оптимизации 3.5-s7):
## раньше — по одному в главном потоке, 64 куска на старте ≈ 64 × 60 мс. Ставим в том же порядке (ближние первыми).
## RV-05: lods — off-screen keys that get a coarse placeholder (LOD_N) in the same parallel batch; their
## full chunks are queued in the background only after the batch, so they do not take its threads.
func _build_now(keys: Array[Vector2i], lods: Array[Vector2i] = []) -> void:
	_batch_keys = keys.duplicate()
	_batch_keys.append_array(lods)
	_batch_full = keys.size()
	_batch_ctx = []
	_batch_res = []
	for key in _batch_keys:
		_batch_ctx.append(_ctx(key))
	_batch_res.resize(_batch_keys.size())
	var gid := WorkerThreadPool.add_group_task(_build_one, _batch_keys.size(), -1, true, "terrain now")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for i in _batch_keys.size():
		_place_chunk(_batch_keys[i], _batch_res[i])
	for i in range(_batch_full, _batch_keys.size()):
		var key := _batch_keys[i]
		if not _pending.has(key):   # the same snapshot: threads only read it
			_pending[key] = WorkerThreadPool.add_task(_compute_bg.bind(key, _batch_ctx[i], _gen), false, "terrain chunk")
	_batch_ctx = []
	_batch_res = []


## One chunk of the _build_now batch on a worker: full grid for the first _batch_full keys, placeholder after.
func _build_one(i: int) -> void:
	var r := _compute(_batch_keys[i], _batch_ctx[i], _gen, 0 if i < _batch_full else LOD_N)
	_mx.lock()
	_batch_res[i] = r
	_mx.unlock()


func _drop_lod(key: Vector2i) -> void:
	var mi: MeshInstance3D = _lods.get(key)
	if mi != null:
		mi.queue_free()
		_lods.erase(key)


func _take_done(key: Vector2i):
	_mx.lock()
	var r = _done.get(key)
	_done.erase(key)
	_mx.unlock()
	if r != null and int(r.get("ep", 0)) != int(_epoch.get(key, 0)):
		return null   # built before rebuild_area() changed this cell's ground: the next sync queues it again
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


## RV-05: per-cell list from a ctx split (vsides, streams) for the cell of point (x, z); a point
## outside the cells the ctx covers gets none, like _sides with a ctx.
func _cell_list(ctx: Dictionary, name: String, x: float, z: float) -> Array:
	return (ctx[name] as Dictionary).get(Vector2i(int(floorf(x / CHUNK)), int(floorf(z / CHUNK))), [])


## RV-05: segment a–b touches the rect (conservative: its bounding box does). Used only to drop
## stream segments that are surely out of reach, so a false "near" costs time, never a wrong result.
static func _seg_rect_near(a: Vector2, b: Vector2, r: Rect2) -> bool:
	return Rect2(a, Vector2.ZERO).expand(b).intersects(r, true)


## RV-05: the chunk build asks valley() and stream_field() at every grid node; a village brings
## dozens of stream segments (smoothed polyline), and both functions walked all of them per node.
## Split a cell's side list once: [valley sides only, streams that can be within STREAM_REACH of the
## cell] (stream_field ignores farther ones anyway), so the result is exactly the same. Main thread.
func _split_sides(k: Vector2i, sides: Array) -> Array:
	var vl := []
	var sl := []
	var cell := Rect2(Vector2(k) * CHUNK, Vector2(CHUNK, CHUNK)).grow(STREAM_REACH + 1.0)
	for s in sides:
		if float(s[2]) >= 0.0:
			vl.append(s)
		elif _seg_rect_near(s[0], s[1], cell):
			sl.append(s)
	return [vl, sl]


## Снимок данных для фонового расчёта куска: объекты биома и боковые долины вокруг
## (поток только читает их, общие кэши трогает лишь главный поток)
func _ctx(key: Vector2i) -> Dictionary:
	var objs := {}
	var sides := {}
	var vsides := {}
	var streams := {}
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var k := Vector2i(key.x + dx, key.y + dz)
			var o := _obj(k) if _bg != null else {}
			objs[k] = o if o.is_empty() or shown(o) else {}
	for dx in range(-2, 3):   # ±2: модели биома у края клетки смотрят и в соседние
		for dz in range(-2, 3):
			var k := Vector2i(key.x + dx, key.y + dz)
			sides[k] = _sides((k.x + 0.5) * CHUNK, (k.y + 0.5) * CHUNK)
			if not _split.has(k):
				_split[k] = _split_sides(k, sides[k])
			vsides[k] = _split[k][0]
			streams[k] = _split[k][1]
	var scn := {}
	if _bg != null:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k := Vector2i(key.x + dx, key.y + dz)
				scn[k] = scenes(k)
	var flats := []
	for k in objs:
		var o: Dictionary = objs[k]
		if not o.is_empty() and FLAT_OBJS.has(o["name"]):
			flats.append(o)
	var ctx := {"objs": objs, "sides": sides, "flat": _bg != null, "scenes": scn, "flats": flats,
		"vsides": vsides, "streams": streams, "ep": int(_epoch.get(key, 0))}
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
func _compute(key: Vector2i, ctx: Dictionary, gen: int, lod := 0) -> Dictionary:
	var nn := lod if lod > 0 else N   # Р-13: заглушка — та же сетка, только реже
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var step := CHUNK / nn
	var W := nn + 3   # +1 узел и по одному с каждой стороны — нормали на стыках кусков совпадают
	var hs := PackedFloat32Array()
	var vs := PackedFloat32Array()
	var gs := PackedFloat32Array()   # L-06: зелёная полоса вдоль реки
	var rs := PackedVector2Array()   # M-36: маски скалы и осыпи (шейдер земли, UV)
	var ps := PackedVector4Array()   # RV-01: landform weights per grid point (shader CUSTOM0)
	var with_prov := relief_style == 1 and not _sea
	hs.resize(W * W)
	vs.resize(W * W)
	gs.resize(W * W)
	rs.resize(W * W)
	ps.resize(W * W)
	# RV-02: valley field with one more ring of nodes — its gradient (central differences) steers the gullies
	var with_gv := with_prov and gullies and lod == 0
	var W2 := W + 2
	var vg := PackedFloat32Array()
	var rg := PackedFloat32Array()   # river_field on the same ring, reused below (it is not cheap)
	if with_gv:
		vg.resize(W2 * W2)
		rg.resize(W2 * W2)
		for j in W2:
			for i in W2:
				var gx := ox + (i - 2) * step
				var gz := oz + (j - 2) * step
				rg[j * W2 + i] = river_field(gx, gz)
				vg[j * W2 + i] = valley(gx, gz, ctx, rg[j * W2 + i])
	for j in W:
		for i in W:
			var x := ox + (i - 1) * step
			var z := oz + (j - 1) * step
			# русло и дорога — по «чистому» полю (река не огибает кишлаки кольцом), высота — с боковыми долинами
			var c := (j + 1) * W2 + i + 1
			var rf := rg[c] if with_gv else river_field(x, z)
			vs[j * W + i] = rf
			gs[j * W + i] = green(x, z, rf)
			# L-09: ручей — в том же поле, в K раз уже (вода и мокрый берег шейдера). Знак — от реки, иначе
			# на стыке «ручей / река» поле проходило через 0, и шейдер рисовал там тонкую ложную воду;
			# за мокрым берегом поле резко растёт — полоса дороги шейдера (85) вдоль ручья не рисуется
			var sf := stream_field(x, z, ctx)
			var sd := absf(sf)
			if sd < STREAM_REACH:
				var g := sd * STREAM_K if sd < 20.0 else 20.0 * STREAM_K + (sd - 20.0) * 80.0
				if g < absf(vs[j * W + i]):
					vs[j * W + i] = g * (1.0 if vs[j * W + i] >= 0.0 else -1.0)
			var vv := vg[c] if with_gv else valley(x, z, ctx, rf)
			var pv := _prov.weights(x, z, vv) if with_prov else Vector4(-1.0, 0.0, 0.0, 0.0)
			ps[j * W + i] = pv
			var gv := NO_GULLIES
			if with_gv:
				gv = Vector2(vg[c + 1] - vg[c - 1], vg[c + W2] - vg[c - W2]) / (2.0 * step)
			var rl := _relief(x, z, vv, ctx, sf, pv, gv)
			hs[j * W + i] = rl.x
			rs[j * W + i] = Vector2(rl.y, rl.z)
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
	# S14-10 (Kanta 31.10, «кусок текстуры взрыва в горе»): a map crater (o_crater) was a level picture on a
	# plane that stuck out of any slope; now it is the same ground mark as a battle-scene crater, lying on the relief
	if ctx.has("objs"):
		for k in ctx["objs"]:
			var o: Dictionary = ctx["objs"][k]
			if not o.is_empty() and o["name"] == "o_crater":
				var cr := float(o["size"]) * CRATER_MARK_R
				if area.grow(cr).has_point(o["pos"]):
					burns.append({"k": "crater", "p": o["pos"], "r": cr})
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var uv1 := PackedVector2Array()   # M-36: x — скальный выход, y — осыпь
	var uv2 := PackedVector2Array()   # x — расстояние до реки, px со знаком (цвет вершины — всего 8 бит)
	var V := nn + 1
	verts.resize(V * V)
	norms.resize(V * V)
	tans.resize(V * V * 4)
	cols.resize(V * V)
	uv2.resize(V * V)
	uv1.resize(V * V)
	# RV-01: CUSTOM0 RGBA float — elevation class, mesa, hills, 1 = has regions. Float, not RGBA8:
	# in GL Compatibility (Godot 4.4.1) RGBA8_UNORM custom data reaches the shader garbled (only R)
	var c0 := PackedFloat32Array()
	c0.resize(V * V * 4)
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
			sm.y = maxf(sm.y, gs[gi] * (1.0 - smoothstep(0.05, 0.35, sm.x)))   # поля вдоль реки не лезут в посёлок и на линию обороны
			cols[vi] = Color(cav, hs[gi] / maxf(ceiling, 1.0), sm.x, sm.y)
			uv2[vi] = Vector2(_shore_u(vs[gi]) if _sea else vs[gi], burn)
			uv1[vi] = rs[gi]
			var pw4 := ps[gi]
			if pw4.x >= 0.0:
				c0[vi * 4] = pw4.x
				c0[vi * 4 + 1] = pw4.y
				c0[vi * 4 + 2] = pw4.w
				c0[vi * 4 + 3] = 1.0
	var idx := PackedInt32Array()
	idx.resize(nn * nn * 6)
	var p := 0
	for j in nn:
		for i in nn:
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
	if lod > 0:
		var sk := _skirt(verts, norms, tans, cols, uv1, uv2, idx, V, c0)
		verts = sk[0]; norms = sk[1]; tans = sk[2]; cols = sk[3]; uv1 = sk[4]; uv2 = sk[5]; idx = sk[6]; c0 = sk[7]
	var put: Dictionary = props.plan(key, ctx) if props != null and lod == 0 else {}
	return {"verts": verts, "norms": norms, "tans": tans, "cols": cols, "uv1": uv1, "uv2": uv2, "c0": c0, "idx": idx, "gen": gen, "ep": int(ctx.get("ep", 0)), "put": put,
		"hs": hs, "W": W, "step": step, "lod": lod}


## Р-13: юбка заглушки — край куска опущен вниз стенкой: редкая сетка заглушки на стыке с полным
## соседом не совпадает с его краем, без юбки в щель видно фон
const SKIRT := 90.0

func _skirt(verts: PackedVector3Array, norms: PackedVector3Array, tans: PackedFloat32Array, cols: PackedColorArray,
		uv1: PackedVector2Array, uv2: PackedVector2Array, idx: PackedInt32Array, V: int,
		c0: PackedFloat32Array) -> Array:
	var ring: Array[int] = []
	for i in V - 1:
		ring.append(i)                          # верхний край
	for j in V - 1:
		ring.append(j * V + V - 1)              # правый
	for i in range(V - 1, 0, -1):
		ring.append((V - 1) * V + i)            # нижний
	for j in range(V - 1, 0, -1):
		ring.append(j * V)                      # левый
	var base := verts.size()
	var n := ring.size()
	for k in n:
		var a := ring[k]
		verts.append(verts[a] - Vector3(0.0, SKIRT, 0.0))
		norms.append(norms[a])
		for c in 4:
			tans.append(tans[a * 4 + c])
		cols.append(cols[a])
		uv1.append(uv1[a])
		uv2.append(uv2[a])
		for c in 4:
			c0.append(c0[a * 4 + c])
	for k in n:
		var a := ring[k]
		var b := ring[(k + 1) % n]
		var a2 := base + k
		var b2 := base + (k + 1) % n
		# обе стороны: стенку видно и снаружи, и изнутри (наклон камеры)
		for t in [a, b, b2, a, b2, a2, a, b2, b, a, a2, b2]:
			idx.append(t)
	return [verts, norms, tans, cols, uv1, uv2, idx, c0]


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
	arr[Mesh.ARRAY_TEX_UV] = r["uv1"]
	arr[Mesh.ARRAY_TEX_UV2] = r["uv2"]
	arr[Mesh.ARRAY_CUSTOM0] = r["c0"]
	arr[Mesh.ARRAY_INDEX] = r["idx"]
	var mesh := ArrayMesh.new()
	# RV-01: CUSTOM0 holds 4 floats per vertex (landform weights for ground3d.gdshader)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.layers |= DECAL_LAYER
	add_child(mi)
	if int(r.get("lod", 0)) > 0:   # Р-13: заглушка — без моделей биома и без сетки высот (surface_fast считает точно)
		_lods[key] = mi
		return
	if props != null:
		props.apply(r["put"], mi)
	_drop_lod(key)
	if _redo.has(key):   # rebuild_area(): the old mesh stayed up until this one was ready
		(_redo[key] as Node).queue_free()
		_redo.erase(key)
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
