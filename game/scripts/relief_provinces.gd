class_name ReliefProvinces
extends RefCounted
## Landform regions of the Нагорье relief (RV-01, Kanta 2026-10-24): what rises above the valley
## floor differs by region — rolling hills with lone peaks, mid mountains, high sharp ranges with
## snow, mesas with stepped cliffs over canyons — and the two banks of one valley can differ.
## Why a separate class: Terrain3D owns the valley network, river, road and settlements; this
## class only shapes the mountains, has no autoload dependencies and is unit-tested
## (game/tests/relief_provinces_test.gd). Pure function of the point, safe on worker threads
## (FastNoiseLite reads only). Numbers live in ReliefBalance.



var _elev := FastNoiseLite.new()
var _mesa := FastNoiseLite.new()
var _asym := FastNoiseLite.new()
var _roll := FastNoiseLite.new()
var _cone := FastNoiseLite.new()
var _spine := FastNoiseLite.new()
var _canyon := FastNoiseLite.new()
# Same seeds and frequencies as Terrain3D's noises: the old relief texture carries over.
var _warp := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _ero := FastNoiseLite.new()
var _crag := FastNoiseLite.new()
var _strata := FastNoiseLite.new()
var _hill := FastNoiseLite.new()


func _init() -> void:
	_smooth(_elev, 4243, ReliefBalance.ELEV_WAVE, 2)
	_smooth(_mesa, 6607, ReliefBalance.MESA_WAVE, 2)
	_smooth(_asym, 1879, ReliefBalance.ASYM_WAVE, 2)
	_smooth(_roll, 3301, ReliefBalance.ROLL_WAVE, 3)
	_smooth(_warp, 977, 3000.0, 0)
	_smooth(_hill, 4417, 650.0, 3)
	_smooth(_crag, 6151, 1100.0, 3)
	_cone.noise_type = FastNoiseLite.TYPE_CELLULAR
	_cone.seed = 5557
	_cone.frequency = 1.0 / ReliefBalance.CONE_WAVE
	_cone.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_cone.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_cone.cellular_jitter = 0.8
	_smooth(_canyon, 7151, ReliefBalance.CANYON_WAVE, 2)
	_ridged(_spine, 8017, ReliefBalance.SPINE_WAVE, 3, 0.45)
	_ridged(_ridge, 1291, 1300.0, 5, 0.5)
	_ridged(_ero, 2719, 560.0, 4, 0.45)
	_ero.fractal_lacunarity = 2.1
	_ridged(_strata, 3389, 260.0, 2, 0.5)


func _smooth(n: FastNoiseLite, sd: int, wave: float, octaves: int) -> void:
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = sd
	n.frequency = 1.0 / wave
	if octaves > 0:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	# octaves 0: FastNoiseLite default (FBM, 5 octaves) as Terrain3D's _warp and _hill use


func _ridged(n: FastNoiseLite, sd: int, wave: float, octaves: int, gain: float) -> void:
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = sd
	n.frequency = 1.0 / wave
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n.fractal_octaves = octaves
	n.fractal_gain = gain


## Landform weights at a point: x — elevation class (0 hills … 1 high range), y — mesa share,
## z — slope run factor of this bank (ASYM_MIN … ASYM_MAX), w — rounded-hill share.
## v is the signed valley field: its sign picks the bank, so two banks of a river can differ.
func weights(x: float, z: float, v: float) -> Vector4:
	var e := smoothstep(-ReliefBalance.ELEV_EDGE, ReliefBalance.ELEV_EDGE, _elev.get_noise_2d(x, z))
	var m := 0.0
	if e > ReliefBalance.MESA_ELEV_FROM:
		m = smoothstep(ReliefBalance.MESA_FROM, ReliefBalance.MESA_TO, _mesa.get_noise_2d(x + 7000.0, z - 3000.0))
		m *= smoothstep(ReliefBalance.MESA_ELEV_FROM, ReliefBalance.MESA_ELEV_TO, e)
	var s := _asym.get_noise_2d(x + 900.0 * signf(v), z - 1300.0 * signf(v))
	var asym := lerpf(ReliefBalance.ASYM_MIN, ReliefBalance.ASYM_MAX, smoothstep(-0.45, 0.45, s))
	var hill := (1.0 - smoothstep(ReliefBalance.HILLS_FROM, ReliefBalance.HILLS_TO, e)) * (1.0 - m)
	return Vector4(e, m, asym, hill)


## Name of the landform that dominates given weights (maps, tests, bench frames).
static func kind(w: Vector4) -> String:
	if w.y >= 0.5:
		return "mesa"
	if w.w >= 0.5:
		return "hills"
	if w.x >= 0.75:
		return "high"
	return "mid"


## Relief at a point a px from the valley line (a = |v|): x — height share of the ceiling,
## y — bare rock mask, z — scree mask at the foot (both 0…1, for the ground shader).
## Terrain3D then applies settlement flats, the river bed and streams.
func relief(x: float, z: float, a: float, v: float) -> Vector3:
	if a <= ReliefBalance.D_FLOOR:
		# valley floor (river, road, fields): only the small bumps; no region noise (cheaper)
		return Vector3((_hill.get_noise_2d(x, z) + 1.0) * 0.5 * 0.025 * 0.3, 0.0, 0.0)
	var pv := weights(x, z, v)
	var e := pv.x
	var mesa := pv.y
	var hill := pv.w
	var fan := smoothstep(ReliefBalance.D_FLOOR, ReliefBalance.D_FAN, a)
	var h := 0.1 * fan * fan * (1.0 - mesa * 0.7)
	var run := lerpf(ReliefBalance.RUN_HILLS, ReliefBalance.RUN_HIGH, e) * pv.z
	var start := lerpf(ReliefBalance.D_FAN - 40.0, ReliefBalance.D_FAN + ReliefBalance.HILLS_FOOT, hill)
	var climb := smoothstep(start, start + run, a)
	var top := lerpf(ReliefBalance.TOP_LOW, ReliefBalance.TOP_HIGH, pow(e, 1.3))
	var foot := smoothstep(ReliefBalance.D_FAN - 160.0, ReliefBalance.D_FAN + 40.0, a) * (1.0 - smoothstep(0.12, 0.3, climb))
	var r := 0.0
	var er := 0.0
	var cr := 0.0
	var rl := 0.0
	var sp := 0.0
	var mesa_on := mesa > 0.0 and a > ReliefBalance.D_FLOOR + 40.0
	var wx := x
	var wz := z
	if climb > 0.0 or foot > 0.0 or mesa_on:
		wx += _warp.get_noise_2d(x - 311.0, z + 71.0) * 300.0
		wz += _warp.get_noise_2d(x + 57.0, z - 919.0) * 300.0
		cr = _crag.get_noise_2d(wx, wz)
		if climb > 0.0 or mesa_on:
			r = clampf((_ridge.get_noise_2d(wx, wz) + 1.0) * 0.5, 0.0, 1.0)
			er = clampf((_ero.get_noise_2d(wx * 0.9 + wz * 0.25, wz) + 1.0) * 0.5, 0.0, 1.0)
			rl = (_roll.get_noise_2d(wx, wz) + 1.0) * 0.5
			if e > 0.3:
				sp = clampf((_spine.get_noise_2d(wx, wz) + 1.0) * 0.5, 0.0, 1.0)
	# mountains (hills … high range): convex profile; sharpness and gullies grow with elevation
	var cv := 1.0 - pow(1.0 - climb, lerpf(1.1, 2.0, e))
	var mt := (top - 0.1) * cv * lerpf(0.75, 0.45, e)
	mt += sp * sp * sp * ReliefBalance.SPINE_K * smoothstep(0.3, 0.8, e) * cv
	mt += r * r * lerpf(0.02, 0.2, e) * climb * climb * top
	var ew := smoothstep(0.0, 0.55, climb)
	mt += (er * er * lerpf(0.06, 0.38, e) - 0.02) * ew * lerpf(0.4, 1.0, e)
	mt += (rl * rl * ReliefBalance.ROLL_K - 0.04) * ew * hill
	if hill > 0.0:
		var cd := _cone.get_noise_2d(x, z)   # about −1 at a cell's feature point
		var cone := 1.0 - smoothstep(-1.0, -0.4, cd)
		mt += cone * cone * ReliefBalance.CONE_K * hill * smoothstep(ReliefBalance.D_FAN, ReliefBalance.D_FAN + 600.0, a)
	# mesa: cliff right above a narrow fan, flat tops in steps, rock only on the cliff faces
	var ms := 0.0
	var mr := 0.0
	if mesa_on:
		var cl := smoothstep(ReliefBalance.D_FLOOR + 40.0, ReliefBalance.D_FLOOR + 40.0 + ReliefBalance.MESA_CLIFF * pv.z, a)
		var q := cl * lerpf(ReliefBalance.MESA_TOP_LOW, ReliefBalance.MESA_TOP_HIGH, e) + (er - 0.5) * 0.1 * cl + (rl - 0.5) * 0.35 * cl
		# side canyons cut the plateau down to its first ledge (dry gorges with sheer walls)
		var cy := absf(_canyon.get_noise_2d(wx, wz))
		var cut := 1.0 - smoothstep(ReliefBalance.CANYON_W, ReliefBalance.CANYON_W * 2.5, cy)
		q = lerpf(q, minf(q, 0.3 / ReliefBalance.MESA_LEVELS + (rl - 0.5) * 0.04), cut * cl)
		var lv := q * ReliefBalance.MESA_LEVELS
		var st := (floorf(lv) + smoothstep(0.62, 0.82, lv - floorf(lv))) / ReliefBalance.MESA_LEVELS
		ms = maxf(st, 0.0) + r * r * 0.015 * cl
		var fr := lv - floorf(lv)
		mr = smoothstep(0.5, 0.62, fr) * (1.0 - smoothstep(0.84, 0.95, fr)) * smoothstep(0.02, 0.1, q)
	h += lerpf(mt, ms, mesa)
	var climb_r := lerpf(climb, smoothstep(ReliefBalance.D_FLOOR + 40.0, ReliefBalance.D_FLOOR + 300.0, a), mesa)
	var up := smoothstep(0.03, 0.2, climb_r)
	var rock := smoothstep(-0.05, 0.25, cr + climb_r * 0.3 + er * er * 0.45 * e + r * r * 0.2 - 0.2) * up * lerpf(0.25, 1.0, e)
	rock = lerpf(rock * (1.0 - hill * 0.7), mr, mesa)
	# rock belts on steep parts of mountain slopes (not on mesas: they have their own steps)
	var steep := smoothstep(0.08, 0.25, climb) * (1.0 - smoothstep(0.7, 0.92, climb)) * (1.0 - mesa) * e
	if h > 0.16 and steep > 0.0:
		var t := h * 7.0
		var step := (floorf(t) + smoothstep(0.12, 0.88, t - floorf(t))) / 7.0
		h = lerpf(h, step, 0.28 * steep * (1.0 - rock))
	if rock > 0.0:
		# layered ledges ~30 px high, slightly tilted; only added on top of the slope (no pits)
		var sn := _strata.get_noise_2d(x, z)
		var t2 := h * 16.0 + (x * 0.6 + z * 0.8) * 0.00035 + _warp.get_noise_2d(x * 3.0, z * 3.0) * 0.35
		var f2 := t2 - floorf(t2)
		var step2 := (floorf(t2) + smoothstep(0.55, 0.85, f2)) / 16.0
		h += ((step2 - t2 / 16.0) * lerpf(0.6, 0.9, mesa) + 0.016 + (sn + 1.0) * 0.01) * rock
	# small bumps on the floor and fans (as the old relief)
	h += (_hill.get_noise_2d(x, z) + 1.0) * 0.5 * 0.025 * (0.3 + fan)
	var scree := foot * smoothstep(-0.1, 0.25, cr + 0.1) * lerpf(0.5, 1.0, maxf(e, mesa))
	return Vector3(clampf(h, -0.03, 1.0), clampf(rock, 0.0, 1.0), clampf(scree, 0.0, 1.0))
