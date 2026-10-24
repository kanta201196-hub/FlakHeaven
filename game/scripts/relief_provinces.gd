class_name ReliefProvinces
extends RefCounted
## Landform regions of the Нагорье relief (RV-01, Kanta 2026-10-24): what rises above the valley
## floor differs by region — rolling hills with lone peaks, mid mountains, high sharp ranges with
## snow, mesas with stepped cliffs over canyons — and the two banks of one valley can differ.
## Why a separate class: Terrain3D owns the valley network, river, road and settlements; this
## class only shapes the mountains, has no autoload dependencies and is unit-tested
## (game/tests/relief_provinces_test.gd). Pure function of the point, safe on worker threads
## (FastNoiseLite reads only). Numbers live in ReliefBalance.
## RV-02: gullies and spurs from our own per-point "erosion filter" (_gullies) instead of one
## uniform wrinkle pattern; it needs the valley field's gradient, passed in by Terrain3D.



var _elev := FastNoiseLite.new()
var _mesa := FastNoiseLite.new()
var _asym := FastNoiseLite.new()
var _roll := FastNoiseLite.new()
var _cone := FastNoiseLite.new()
var _spine := FastNoiseLite.new()
var _canyon := FastNoiseLite.new()
var _gorge := FastNoiseLite.new()
## RV-04 landforms (pillars, river terraces, gorges) on/off; Terrain3D sets it from the F1 slider.
var landforms := true
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
	_smooth(_gorge, 8231, ReliefBalance.GORGE_WAVE, 1)
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
## pv: weights(x, z, v) when the caller already has them (chunk build needs them for the
## shader too); x < 0 means "compute here".
## gv: gradient of the valley field v at the point (per px) for the RV-02 gullies; Vector2.INF —
## no gullies (old look, or a caller without the gradient).
func relief(x: float, z: float, a: float, v: float, pv := Vector4(-1.0, 0.0, 0.0, 0.0), gv := Vector2.INF) -> Vector3:
	if a <= ReliefBalance.D_FLOOR:
		# valley floor (river, road, fields): only the small bumps; no region noise (cheaper)
		return Vector3((_hill.get_noise_2d(x, z) + 1.0) * 0.5 * 0.025 * 0.3, 0.0, 0.0)
	if pv.x < 0.0:
		pv = weights(x, z, v)
	var e := pv.x
	var mesa := pv.y
	var hill := pv.w
	var fan := smoothstep(ReliefBalance.D_FLOOR, ReliefBalance.D_FAN, a)
	var h := 0.1 * fan * fan * (1.0 - mesa * 0.7)
	var run := lerpf(ReliefBalance.RUN_HILLS, ReliefBalance.RUN_HIGH, e) * pv.z
	# RV-04 gorge: on some stretches both banks stand close and steep above the same floor
	var gk := 0.0
	if landforms and mesa < 1.0:
		gk = smoothstep(ReliefBalance.GORGE_FROM, ReliefBalance.GORGE_TO, _gorge.get_noise_2d(x, z)) * (1.0 - hill) * (1.0 - mesa)
		run *= lerpf(1.0, ReliefBalance.GORGE_RUN, gk)
	var start := lerpf(ReliefBalance.D_FAN - 40.0, ReliefBalance.D_FAN + ReliefBalance.HILLS_FOOT, hill)
	var climb := smoothstep(start, start + run, a)
	var top := minf(lerpf(ReliefBalance.TOP_LOW, ReliefBalance.TOP_HIGH, pow(e, 1.3)) + ReliefBalance.GORGE_TOP * gk, 1.0)
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
	var gully_on := gv.is_finite() and a > ReliefBalance.D_FAN and mesa < 1.0
	# with gullies on, the uniform wrinkle keeps ERO_KEEP of its swing around its mean (0.3), so
	# the ranges keep their height (and snow) and the gullies carry the slope pattern
	var wr := lerpf(0.3, er * er, ReliefBalance.ERO_KEEP) if gully_on else er * er
	mt += (wr * lerpf(0.06, 0.38, e) - 0.02) * ew * lerpf(0.4, 1.0, e)
	mt += (rl * rl * ReliefBalance.ROLL_K - 0.04) * ew * hill
	var cone_g := Vector2.ZERO   # slope of the hill knolls and lone peaks, for the gullies
	if hill > 0.0:
		var cd := _cone.get_noise_2d(x, z)   # about −1 at a cell's feature point
		var cone := 1.0 - smoothstep(-1.0, -0.4, cd)
		var cone_k := ReliefBalance.CONE_K * hill * smoothstep(ReliefBalance.D_FAN, ReliefBalance.D_FAN + 600.0, a)
		mt += cone * cone * cone_k
		if gully_on:
			var tc := clampf((cd + 1.0) / 0.6, 0.0, 1.0)
			cone_g = _noise_grad(_cone, x, z) * (-2.0 * cone * 6.0 * tc * (1.0 - tc) / 0.6 * cone_k)
			if rl > 0.0:
				cone_g += _noise_grad(_roll, wx, wz) * (rl * ReliefBalance.ROLL_K * ew * hill)
	if gully_on:
		# slope of the big shape (profile across the valley + main crests), share of the ceiling per px
		var p_exp := lerpf(1.1, 2.0, e)
		var t := clampf((a - start) / maxf(run, 1.0), 0.0, 1.0)
		var dcv := p_exp * pow(1.0 - climb, p_exp - 1.0) * 6.0 * t * (1.0 - t) / maxf(run, 1.0)
		var sp_k := ReliefBalance.SPINE_K * smoothstep(0.3, 0.8, e)
		var g := gv * (signf(v) * ((top - 0.1) * lerpf(0.75, 0.45, e) + sp * sp * sp * sp_k) * dcv) + cone_g
		if sp > 0.0:
			g += _noise_grad(_spine, wx, wz) * (1.5 * sp * sp * sp_k * cv)
		var slope_k := smoothstep(ReliefBalance.GULLY_SLOPE_FROM, ReliefBalance.GULLY_SLOPE_TO, g.length())
		# the highest crests keep their gentle snow fields (the ground shader puts snow only on gentle slopes)
		slope_k *= 1.0 - smoothstep(0.5, 0.75, mt)
		if slope_k > 0.0:
			mt += _gullies(x, z, g) * slope_k * smoothstep(ReliefBalance.D_FAN, ReliefBalance.D_FAN + 300.0, a) * lerpf(0.6, 1.0, e) * sqrt(top) * lerpf(1.0, 0.6, hill)
	# RV-04 river terraces: the low part of a gentle bank climbs in benches (treads keep a tilt)
	if landforms and mt > 0.0:
		var tk := (1.0 - mesa) * (1.0 - smoothstep(0.45, 0.7, e)) * (1.0 - gk) \
			* smoothstep(ReliefBalance.TERRACE_FROM, ReliefBalance.TERRACE_TO, _gorge.get_noise_2d(x * 0.7 + 5000.0, z * 0.7))
		if tk > 0.0:
			var ts := ReliefBalance.TERRACE_STEP
			var tq := mt / ts
			var stair := (floorf(tq) + smoothstep(0.72, 0.97, tq - floorf(tq))) * ts
			stair = lerpf(stair, mt, ReliefBalance.TERRACE_TREAD)
			mt = lerpf(mt, stair, tk * (1.0 - smoothstep(ts * ReliefBalance.TERRACE_STEPS - ts * 0.3, ts * ReliefBalance.TERRACE_STEPS, mt)))
	# mesa: cliff right above a narrow fan, flat tops in steps, rock only on the cliff faces
	var ms := 0.0
	var mr := 0.0
	var apron := 0.0   # mesa talus band (scree in the shader)
	if mesa_on:
		var cl := smoothstep(ReliefBalance.D_FLOOR + 40.0, ReliefBalance.D_FLOOR + 40.0 + ReliefBalance.MESA_CLIFF * pv.z, a)
		var q := cl * lerpf(ReliefBalance.MESA_TOP_LOW, ReliefBalance.MESA_TOP_HIGH, e) + (er - 0.5) * 0.1 * cl + (rl - 0.5) * 0.35 * cl
		# side canyons cut the plateau down to its first ledge (dry gorges with sheer walls)
		var cy := absf(_canyon.get_noise_2d(wx, wz))
		var cut := 1.0 - smoothstep(ReliefBalance.CANYON_W, ReliefBalance.CANYON_W * 2.5, cy)
		# the gorge floor is a wash rising away from the valley, below the first ledge (no dead-flat bottom)
		var wash_q := (0.14 + 0.36 * smoothstep(ReliefBalance.D_FLOOR + 40.0, ReliefBalance.D_FLOOR + 1400.0, a)) / ReliefBalance.MESA_LEVELS
		q = lerpf(q, minf(q, wash_q + (rl - 0.5) * 0.04), cut * cl)
		var lv := q * ReliefBalance.MESA_LEVELS
		var fr := lv - floorf(lv)
		# a step: the wall on top, a concave scree apron under it (talus), not one sheer drop
		var tal := smoothstep(0.18, 0.84, fr)
		var w0 := 0.64 + (er - 0.5) * 0.16   # the rim is eaten by gullies, not a ruled line
		var rise := lerpf(smoothstep(w0, w0 + 0.2, fr), tal * tal, ReliefBalance.MESA_TALUS)
		var st := (floorf(lv) + rise) / ReliefBalance.MESA_LEVELS
		# ledges keep part of the ground's rise and roll, plus hummocks and shallow gullies: never a dead-flat table
		# (only added: clipping at the floor level would flatten the low ledges again); gorge floors get more
		var hum := (_hill.get_noise_2d(wx * 1.7, wz * 1.7) + 1.0) * ReliefBalance.MESA_HUMMOCK * (1.0 + cut)
		var knob := (_hill.get_noise_2d(wx * 3.6 + 913.0, wz * 3.6 - 377.0) + 1.0) * ReliefBalance.MESA_KNOB   # ~180 px mounds: they catch the light
		st = maxf(lerpf(st, q, ReliefBalance.MESA_TREAD), 0.0) + (er * 0.07 + hum + knob) * cl
		ms = st + r * r * 0.015 * cl
		mr = smoothstep(0.56, 0.68, fr) * (1.0 - smoothstep(0.86, 0.95, fr)) * smoothstep(0.02, 0.1, q)
		apron = smoothstep(0.46, 0.56, fr) * (1.0 - smoothstep(0.62, 0.7, fr)) * smoothstep(0.02, 0.1, q)
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
	# RV-04 lone rock pillars and buttes on mesa land and dry hills, away from the valley floor
	if landforms and a > ReliefBalance.D_FAN + 250.0:
		var pk := maxf(mesa, hill) * smoothstep(ReliefBalance.D_FAN + 250.0, ReliefBalance.D_FAN + 550.0, a)
		if pk > 0.0:
			var pl := _pillar(x, z)
			if pl.x > 0.0:
				var cap := minf(h + pl.x * pk, maxf(h, ReliefBalance.PILLAR_CAP_MAX))
				h = maxf(h, lerpf(h, cap, pl.y)) + pl.z * pk
				rock = maxf(rock, pl.y * pk)
	# small bumps on the floor and fans (as the old relief)
	h += (_hill.get_noise_2d(x, z) + 1.0) * 0.5 * 0.025 * (0.3 + fan)
	var scree := foot * smoothstep(-0.1, 0.25, cr + 0.1) * lerpf(0.5, 1.0, maxf(e, mesa))
	scree = maxf(scree, apron * mesa)
	return Vector3(clampf(h, -0.03, 1.0), clampf(rock, 0.0, 1.0), clampf(scree, 0.0, 1.0))


## RV-04: the pillar nearest to (x, z), if its cell has one. Cells of PILLAR_CELL px, one jittered
## centre each, PILLAR_CHANCE of them carry a pillar (the cell hash decides, so the world is fixed).
## Returns x — pillar height (share of the ceiling, 0 — none here), y — body mask 0…1 (1 inside,
## a ~25 px near-vertical wall), z — scree skirt height at its foot. Nearest of the 3×3 cells: a
## pillar never spans more than one cell (radius ≤ PILLAR_R_MAX < cell / 4).
func _pillar(x: float, z: float) -> Vector3:
	var c := ReliefBalance.PILLAR_CELL
	var ci := floorf(x / c)
	var cj := floorf(z / c)
	var best := Vector3.ZERO
	for oj in 3:
		for oi in 3:
			var cx := ci + oi - 1.0
			var cz := cj + oj - 1.0
			var hh := sin(cx * 91.3 + cz * 417.9 + 3.1) * 43758.5453
			if fposmod(hh, 1.0) > ReliefBalance.PILLAR_CHANCE:
				continue
			var px := (cx + 0.25 + 0.5 * fposmod(hh * 7.31, 1.0)) * c
			var pz := (cz + 0.25 + 0.5 * fposmod(hh * 13.17, 1.0)) * c
			var d := Vector2(x - px, z - pz).length()
			var rr := lerpf(ReliefBalance.PILLAR_R_MIN, ReliefBalance.PILLAR_R_MAX, fposmod(hh * 3.77, 1.0))
			if d > rr * 2.4:
				continue
			# slightly lobed outline: not a perfect cylinder
			var ang := atan2(z - pz, x - px)
			rr *= 1.0 + 0.12 * sin(ang * 3.0 + hh) + 0.06 * sin(ang * 5.0 - hh * 2.0)
			var body := 1.0 - smoothstep(rr - 25.0, rr, d)
			var ph := lerpf(ReliefBalance.PILLAR_H_MIN, ReliefBalance.PILLAR_H_MAX, fposmod(hh * 5.93, 1.0))
			ph *= 1.0 - 0.15 * (d / rr) * (d / rr)   # a little domed cap
			var sk := 1.0 - smoothstep(rr, rr * 2.4, d)
			var v := Vector3(ph, body, sk * sk * ReliefBalance.PILLAR_SKIRT)
			if v.y + v.z > best.y + best.z:
				best = v
	return best


## Gradient of a noise (per px) by central differences 120 px apart: smooth enough to steer the
## gullies (a short step follows the kinks of cellular noise and crumples the stripes).
## The warp is left out: it bends the noise slowly, its share of the slope is small.
func _noise_grad(n: FastNoiseLite, x: float, z: float) -> Vector2:
	var dd := 120.0
	return Vector2(n.get_noise_2d(x + dd, z) - n.get_noise_2d(x - dd, z),
		n.get_noise_2d(x, z + dd) - n.get_noise_2d(x, z - dd)) / (2.0 * dd)


## RV-02: our own per-point "erosion filter". g is the slope of the big shape (uphill, share of the
## ceiling per px). Each layer lays stripes across the slope direction around jittered cell
## points, blended with a smooth kernel of 1.5 cells (4×4 nearest cells: exact, no seams), so the
## troughs run downhill (gullies) and the crests between them are spurs. Each finer layer follows
## the slope plus the coarser layers' own slope, so small gullies bend into the big ones
## (branching), and it fades where those layers flattened the ground (gully floors, spur tops).
## Result: height offset, share of the ceiling, about ±GULLY_AMP·(1 + GAIN + GAIN²), deeper than
## high on average (erosion removes ground). Pure function of the point. Kernel and neighbourhood
## match on purpose: a kernel wider than the cells looked at leaves seams on cell borders, a random
## phase per cell crumples the stripes (both seen on a numpy mock-up with cones).
func _gullies(x: float, z: float, g: Vector2) -> float:
	var h := 0.0
	var amp := ReliefBalance.GULLY_AMP
	var cell := ReliefBalance.GULLY_CELL
	var g0 := g.length()
	if g0 < 1e-9:
		return 0.0
	for k in ReliefBalance.GULLY_OCTAVES:
		var gl := g.length()
		if gl < 1e-9:
			break
		var fade := minf(gl / g0, 1.0)
		var ax := -g.y / gl
		var az := g.x / gl
		var f := TAU / cell
		var ux := x / cell
		var uz := z / cell
		var ci := floorf(ux)
		var cj := floorf(uz)
		# the 4×4 cells whose points can be within 1.5 cells: two on the near side, one beyond
		var i0 := ci - (2.0 if ux - ci < 0.5 else 1.0)
		var j0 := cj - (2.0 if uz - cj < 0.5 else 1.0)
		var sum := 0.0
		var dsum := 0.0
		var wsum := 0.0
		var hk := k * 74.7
		for oj in 4:
			var cz := j0 + oj
			var dz := maxf(maxf(cz - uz, uz - cz - 1.0), 0.0)   # from the point to this cell row
			if dz >= 1.5:
				continue
			var hz := cz * 311.7 + hk
			for oi in 4:
				var cx := i0 + oi
				var dx := maxf(maxf(cx - ux, ux - cx - 1.0), 0.0)
				if dx * dx + dz * dz >= 2.25:
					continue   # no point of this cell can be within reach
				var hh := sin(cx * 127.1 + hz) * 43758.5453
				var ox := ux - cx - fposmod(hh, 1.0)
				var oz := uz - cz - fposmod(hh * 31.7, 1.0)
				var w := 1.0 - (ox * ox + oz * oz) / 2.25
				if w <= 0.0:
					continue
				w *= w
				var cs := Vector2.from_angle((ox * ax + oz * az) * TAU)
				sum += w * cs.x
				dsum += w * cs.y
				wsum += w
		if wsum <= 0.0:
			break
		h += amp * (sum / wsum - ReliefBalance.GULLY_BIAS) * fade
		var dk := -dsum / wsum * f * amp * fade
		g += Vector2(ax, az) * dk
		amp *= ReliefBalance.GULLY_GAIN
		cell *= 0.5
	return h
