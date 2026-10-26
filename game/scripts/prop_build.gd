class_name PropBuild
extends RefCounted
## Procedural Highland props at the fort's quality bar (Kanta 26.10, "bridges and the yurt — remake ours"):
## the road bridge over a village stream, the suspension footbridge over the river and the felt yurt.
## Built in code at first use like FortBuild, from real-world proportions in metres, with the fort's CC0 texture
## set Г (stone, concrete, old planks) and the hessian of the trench bags for the felt cover. Every surface uses
## prop_wear.gdshader (stains, dust band, damp piers, rough matte), each piece carries its own vertex tone, so
## nothing reads as flat even paint. Meshes come out in the units BiomeProps expects: the bridges span x
## -0.5..0.5 with the deck at the old height, the yurt is 1 wide with its bottom at y = 0.
## Not a FortBuild subclass: FortBuild's UV tiles, unit and materials are static and bound to the fort's scale,
## and the props need vertex colours the fort does not write.

enum M { STONE, CONC, WOOD, FELT, PLAIN }

const FORT := "res://art/fort/"
const FELT_TEX := "res://art/ground/road/bag_hessian_"
## Metres per texture repeat; PLAIN is untextured (vertex colour only).
const TILE := {M.STONE: 2.6, M.CONC: 4.0, M.WOOD: 2.2, M.FELT: 1.6, M.PLAIN: 1.0}

## Road bridge: metres per mesh unit (the span). Deck 0.4 of the span (6 m, room for 1.5 trucks, PR #443);
## its top stays at 0.06 of the span, where BiomeProps._put_bridge expects the old deck.
const ROAD_L := 15.0
## Footbridge: metres per mesh unit; 0.09 of the span across the pylons, as before.
const FOOT_L := 30.0
## Yurt: 6.2 m wall diameter (a common family yurt), ground ring 7.4 m across = the mesh's width of 1.
const YURT_R := 3.1
const YURT_L := 7.4
const YURT_SINK := 0.3   ## metres below ground in the mesh: BiomeProps sinks every model by 4 % of its width

static var _cache := {}

var _st := {}            # material → SurfaceTool
var _k := 1.0            # mesh units per metre
var _lift := 0.0         # metres added to y on output (the yurt's sunk base)
var _xf := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()


## Road bridge (foot = false) or river footbridge (foot = true), cached. Same frame as the old AdobeBuild.bridge,
## so placement (BiomeProps._put_bridge: span along x, uniform scale by the span in px) is unchanged.
static func bridge(foot: bool) -> ArrayMesh:
	var key := "foot" if foot else "road"
	if not _cache.has(key):
		var b := PropBuild.new()
		b._rng.seed = 7707 if foot else 7708
		if foot:
			b._k = 1.0 / FOOT_L
			b._footbridge()
			_cache[key] = b._commit(FOOT_L, {"ground_y": -2.0, "wet_y": -1.4})
		else:
			b._k = 1.0 / ROAD_L
			b._road_bridge()
			_cache[key] = b._commit(ROAD_L, {"ground_y": -3.2, "wet_y": -1.3})
	return _cache[key]


## The felt yurt, cached: 1 wide (ground ring), bottom at y = 0, ground level YURT_SINK above it.
static func yurt() -> ArrayMesh:
	if not _cache.has("yurt"):
		var b := PropBuild.new()
		b._rng.seed = 9091
		b._k = 1.0 / YURT_L
		b._lift = YURT_SINK
		b._yurt()
		_cache["yurt"] = b._commit(YURT_L, {"ground_y": YURT_SINK, "dust_h": 0.7, "wet_y": -999.0})
	return _cache["yurt"]


## Triangle count of a mesh (bench and report).
static func tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


# ---------- road bridge ----------

## Three-span road bridge, 15 m: stone abutments with wing walls and corner posts on the banks, two masonry
## piers whose pointed cutwaters rise past the deck as buttresses (the masonry reads from the top-down camera),
## concrete bed blocks, four steel stringers, a transverse plank deck with two wheel-track runners,
## timber kerbs and a post-and-rail parapet. Wear: plank tones and a few fresh replacements, ruts darker on the
## runners, leaning posts, one broken rail, fallen stones at the pier feet.
func _road_bridge() -> void:
	var hl := ROAD_L * 0.5
	var hw := ROAD_L * 0.2          # half deck width, 3 m
	var top := ROAD_L * 0.06        # deck top, 0.9 m
	var plank_t := 0.1
	var str_top := top - plank_t    # stringers' top
	var str_h := 0.45
	var cap_top := str_top - str_h  # bed blocks' top
	var foot := -3.6
	# abutments: battered stone, concrete bed block, short wing walls into the banks, stone end posts that
	# mark the bridge's four corners from above
	for sx: float in [-1.0, 1.0]:
		var x0 := sx * (hl - 0.9)
		_column(M.STONE, _rect(1.9, hw * 2.0 + 1.2), Vector3(x0 + sx * 0.25, foot, 0), cap_top - 0.3 - foot, 0.06, _tone(0.95, 0.05))
		_box(M.CONC, Vector3(1.6, 0.3, hw * 2.0 + 0.9), Vector3(x0, cap_top - 0.15, 0), Basis.IDENTITY, _tone(0.97, 0.04))
		for sz: float in [-1.0, 1.0]:
			var b := Basis(Vector3.UP, sx * sz * 0.3)
			_box(M.STONE, Vector3(2.2, top - foot - 0.2, 0.6), Vector3(sx * (hl + 0.4), (top + foot) * 0.5 - 0.1, sz * (hw + 0.6)), b, _tone(0.9, 0.05))
			_column(M.STONE, _rect(0.8, 0.8), Vector3(sx * (hl - 0.3), cap_top - 0.3, sz * (hw + 0.5)), top + 0.55 - cap_top + 0.3, 0.02, _tone(0.93, 0.05))
			_box(M.CONC, Vector3(0.9, 0.12, 0.9), Vector3(sx * (hl - 0.3), top + 0.61, sz * (hw + 0.5)), Basis(Vector3.UP, _r(-0.04, 0.04)), _tone(0.9, 0.05))
	# river piers: cutwater plan both ends, battered, concrete bed block on top
	for px: float in [-2.5, 2.5]:
		var hz := hw + 0.7
		var poly := PackedVector2Array([Vector2(-0.6, -hz), Vector2(0.0, -hz - 0.9), Vector2(0.6, -hz), Vector2(0.6, hz), Vector2(0.0, hz + 0.9), Vector2(-0.6, hz)])
		_column(M.STONE, poly, Vector3(px, foot, 0), cap_top - 0.3 - foot, 0.05, _tone(0.92, 0.05))
		_box(M.CONC, Vector3(1.5, 0.3, hz * 2.0 + 0.3), Vector3(px, cap_top - 0.15, 0), Basis.IDENTITY, _tone(0.96, 0.05))
		for sz: float in [-1.0, 1.0]:   # cutwaters carried up past the deck as buttresses, as on masonry bridges
			var cw := PackedVector2Array([Vector2(-0.55, sz * (hw + 0.2)), Vector2(0.55, sz * (hw + 0.2)), Vector2(0.55, sz * hz), Vector2(0.0, sz * (hz + 0.85)), Vector2(-0.55, sz * hz)])
			_column(M.STONE, cw, Vector3(px, cap_top - 0.3, 0), top + 0.45 - cap_top + 0.3, 0.02, _tone(0.9, 0.05))
		for i in 5:   # stones knocked off the cutwaters, at the pier's foot
			var a := _rng.randf() * TAU
			_chunk(M.STONE, _r(0.18, 0.35), Vector3(px + cos(a) * _r(0.9, 1.6), foot + 2.0 + _r(-0.2, 0.2), (hz + 0.6) * signf(sin(a)) + _r(-0.6, 0.6)), _tone(0.85, 0.06))
	# steel stringers (I-beams: flanges and web)
	for z: float in [-2.25, -0.75, 0.75, 2.25]:
		var c := _tone(0.36, 0.03) * Color(1.0, 0.92, 0.84)   # rust-brown dark steel
		_box(M.PLAIN, Vector3(ROAD_L - 0.6, 0.04, 0.28), Vector3(0, str_top - 0.02, z), Basis.IDENTITY, c)
		_box(M.PLAIN, Vector3(ROAD_L - 0.6, str_h - 0.08, 0.04), Vector3(0, str_top - str_h * 0.5, z), Basis.IDENTITY, c.darkened(0.15))
		_box(M.PLAIN, Vector3(ROAD_L - 0.6, 0.04, 0.28), Vector3(0, cap_top + 0.02, z), Basis.IDENTITY, c.darkened(0.1))
	# transverse planks, 0.25 m with 2 cm gaps, every tone a little different, a few fresh replacements
	var x := -hl + 0.15
	while x < hl - 0.15:
		var fresh := _rng.randf() < 0.07
		var col := Color(1.12, 1.06, 0.95) if fresh else _tone(0.9, 0.12)
		_box(M.WOOD, Vector3(0.25, plank_t, hw * 2.0 - _r(0.0, 0.12)), Vector3(x, top - plank_t * 0.5 + _r(-0.008, 0.008), _r(-0.04, 0.04)), Basis(Vector3.UP, _r(-0.006, 0.006)), col)
		x += 0.27
	# wheel-track runners, darker where the tyres run
	for z: float in [-1.25, 1.25]:
		for i in 5:
			var x0 := -hl + ROAD_L * i / 5.0
			_box(M.WOOD, Vector3(ROAD_L / 5.0 - 0.03, 0.06, 0.9), Vector3(x0 + ROAD_L * 0.1, top + 0.03, z), Basis.IDENTITY, _tone(0.72, 0.06))
	# kerbs and parapet: posts every 1.5 m, a top rail and a mid rail; one bay's rails broken
	var bad := _rng.randi_range(2, 7)
	for sz: float in [-1.0, 1.0]:
		_box(M.WOOD, Vector3(ROAD_L, 0.22, 0.25), Vector3(0, top + 0.11, sz * (hw - 0.2)), Basis.IDENTITY, _tone(0.78, 0.06))
		var n := 11
		var posts := []
		for i in n:
			var px := -hl + 0.25 + (ROAD_L - 0.5) * i / (n - 1)
			var lean := Basis(Vector3.RIGHT, _r(-0.05, 0.05)) * Basis(Vector3.BACK, _r(-0.04, 0.04))
			var base := Vector3(px, top - 0.2, sz * (hw + 0.05))
			_box(M.WOOD, Vector3(0.16, 1.25, 0.16), base + lean * Vector3(0, 0.62, 0), lean, _tone(0.8, 0.08))
			posts.append(base + lean * Vector3(0, 1.2, 0))
		for i in n - 1:
			var a: Vector3 = posts[i]
			var b: Vector3 = posts[i + 1]
			if sz > 0.0 and i == bad:   # broken bay: top rail snapped and hanging, mid rail gone
				var mid := a.lerp(b, 0.45) + Vector3(0, -0.35, 0)
				_beam(M.WOOD, a, mid, 0.12, _tone(0.7, 0.05))
				continue
			_beam(M.WOOD, a, b, 0.12, _tone(0.82, 0.07))
			_beam(M.WOOD, a + Vector3(0, -0.5, 0), b + Vector3(0, -0.5, 0), 0.1, _tone(0.8, 0.07))


# ---------- footbridge ----------

## Suspension footbridge, 30 m, of the kind strung over mountain rivers: two masonry pylons with a timber
## lintel at each bank, two sagging main cables anchored behind them to concrete blocks, hangers every 1.5 m,
## a gently sagging plank deck on two stringer cables with wire handrails. Wear: uneven and missing planks,
## patched pylon stone, fallen stones at the pylon feet.
func _footbridge() -> void:
	var hl := FOOT_L * 0.5
	var hw := 0.8                       # half deck width: a 1.6 m walkway
	var pz := FOOT_L * 0.045            # pylon line: 0.09 of the span across, as the old model
	var tower_h := 3.4
	var deck := func(px: float) -> float: return 0.35 - 0.75 * (1.0 - pow(px / hl, 2.0))
	for sx: float in [-1.0, 1.0]:
		var tx := sx * (hl - 0.6)
		for sz: float in [-1.0, 1.0]:
			_column(M.STONE, _rect(0.8, 0.8), Vector3(tx, -2.0, sz * pz), tower_h + 2.0, 0.05, _tone(0.93, 0.06))
			_box(M.CONC, Vector3(0.95, 0.18, 0.95), Vector3(tx, tower_h + 0.09, sz * pz), Basis.IDENTITY, _tone(0.95, 0.05))
			_box(M.CONC, Vector3(1.1, 1.0, 1.1), Vector3(sx * (hl + 2.2), -0.4, sz * pz), Basis(Vector3.UP, _r(-0.1, 0.1)), _tone(0.9, 0.06))   # cable anchors
			for i in 3:
				_chunk(M.STONE, _r(0.12, 0.25), Vector3(tx + _r(-0.9, 0.9), -0.05, sz * pz + _r(-0.9, 0.9)), _tone(0.85, 0.06))
		_box(M.WOOD, Vector3(0.35, 0.35, pz * 2.0 + 0.9), Vector3(tx, tower_h - 0.55, 0), Basis.IDENTITY, _tone(0.75, 0.06))
	var steel := Color(0.3, 0.29, 0.27)
	var segs := 20
	for sz: float in [-1.0, 1.0]:
		# main cable: anchor → pylon top → catenary-like sag to 1.1 m over mid-deck → pylon → anchor
		var top_y := tower_h + 0.2
		var a0 := Vector3(-hl - 2.2, 0.0, sz * pz)
		var t0 := Vector3(-hl + 0.6, top_y, sz * pz)
		_beam(M.PLAIN, a0, t0, 0.06, steel)
		_beam(M.PLAIN, Vector3(hl + 2.2, 0.0, sz * pz), Vector3(hl - 0.6, top_y, sz * pz), 0.06, steel)
		var prev := t0
		for i in range(1, segs + 1):
			var u := float(i) / segs
			var px := lerpf(-hl + 0.6, hl - 0.6, u)
			var z := sz * lerpf(pz, hw + 0.05, sin(u * PI))   # cables pulled in towards the deck mid-span
			var q := Vector3(px, lerpf(top_y, float(deck.call(px)) + 1.1, sin(u * PI)), z)
			_beam(M.PLAIN, prev, q, 0.05, steel)
			if i < segs and i % 2 == 0:   # hangers down to the deck edge
				_beam(M.PLAIN, q, Vector3(px, float(deck.call(px)) - 0.05, sz * hw), 0.025, steel.lightened(0.05))
			prev = q
		# stringer cable and wire handrail at 1 m
		for i in segs:
			var x0 := lerpf(-hl, hl, float(i) / segs)
			var x1 := lerpf(-hl, hl, float(i + 1) / segs)
			_beam(M.PLAIN, Vector3(x0, float(deck.call(x0)) - 0.08, sz * (hw - 0.1)), Vector3(x1, float(deck.call(x1)) - 0.08, sz * (hw - 0.1)), 0.05, steel)
			_beam(M.PLAIN, Vector3(x0, float(deck.call(x0)) + 0.95, sz * hw), Vector3(x1, float(deck.call(x1)) + 0.95, sz * hw), 0.03, steel.lightened(0.08))
	var x := -hl + 0.2
	while x < hl - 0.2:
		if _rng.randf() > 0.03:   # one in thirty planks gone
			var y := float(deck.call(x))
			var slope := atan(1.5 * x / (hl * hl))
			var b := Basis(Vector3.BACK, slope + _r(-0.03, 0.03)) * Basis(Vector3.UP, _r(-0.04, 0.04))
			_box(M.WOOD, Vector3(0.24, 0.06, hw * 2.0 - _r(0.0, 0.2)), Vector3(x, y, _r(-0.05, 0.05)), b, _tone(0.86, 0.12))
		x += 0.3


# ---------- yurt ----------

## Felt yurt, 6.2 m across and 3 m to the crown, wall 1.55 m. Lattice wall (khana) under a felt cover whose
## lower edge is rolled up on the shady side for summer air, showing the lattice and the dark inside; roof felt
## draped over 64 roof poles (ribs show through), soot-darkened round the crown; the wooden crown ring with
## crossed bent bars, its felt flap half drawn back, a stovepipe; three woollen bands round the wall and ropes
## over the roof; a painted wooden door under a rolled felt door curtain; stones weighting the skirt in a ring
## round its foot. Wear: felt panels of different age, stains, dust up from the ground.
func _yurt() -> void:
	var r := YURT_R
	var wall_h := 1.55
	var crown_y := 2.85
	var crown_r := 0.72
	var seg := 48
	var door_a := PI * 0.5            # door faces +z (south: the camera looks north, the door is in view)
	var door_half := 0.5 / r          # half-angle of the 1 m door
	var roll_a := -PI * 0.5           # rolled-up felt on the far side
	var roll_half := 1.0
	var felt := Color(0.8, 0.76, 0.68)
	var dark := Color(0.09, 0.075, 0.06)
	# inner darkness behind the lattice and under the crown
	_ring_wall(M.PLAIN, r - 0.12, r - 0.14, -YURT_SINK, wall_h, seg, -INF, 0.0, dark, true)
	_disc(M.PLAIN, crown_r + 0.05, crown_y - 0.35, 16, dark)
	# felt wall in panels (each about 1.2 m, own tone); the door gap and the rolled-up strip left open
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var am := (a0 + a1) * 0.5
		if absf(wrapf(am - door_a, -PI, PI)) < door_half + 0.02:
			continue
		var col := felt * _panel_tone(i / 3)
		var y0 := -YURT_SINK
		if absf(wrapf(am - roll_a, -PI, PI)) < roll_half:
			y0 = 0.62
		_wall_quad(M.FELT, r - 0.04, r + 0.03, a0, a1, y0, wall_h, col)
	# rolled felt roll and the exposed lattice below it
	var steps := 12
	for i in steps:
		var a0 := roll_a - roll_half + 2.0 * roll_half * i / steps
		var a1 := roll_a - roll_half + 2.0 * roll_half * (i + 1) / steps
		var p0 := Vector3(cos(a0) * (r + 0.08), 0.62, sin(a0) * (r + 0.08))
		var p1 := Vector3(cos(a1) * (r + 0.08), 0.62, sin(a1) * (r + 0.08))
		_beam(M.FELT, p0, p1, 0.11, felt * 0.86)
	var lat := Color(0.62, 0.46, 0.3)
	var nl := 22
	for i in nl:   # lattice: two layers of slats crossing at 45°, about 0.3 m apart
		var a := roll_a - roll_half + 2.0 * roll_half * (i + 0.5) / nl
		for s: float in [-1.0, 1.0]:
			var da := s * 0.28 / r
			var pa := Vector3(cos(a - da) * (r - 0.06), 0.0, sin(a - da) * (r - 0.06))
			var pb := Vector3(cos(a + da) * (r - 0.06), 0.6, sin(a + da) * (r - 0.06))
			_beam(M.WOOD, pa, pb, 0.025, lat * _tone(1.0, 0.08))
	# roof felt over the poles: radius bulges a little at each pole, soot darkens it towards the crown
	var rs := 64
	var rings := 4
	var eave_r := r + 0.14
	var eave_y := wall_h - 0.1
	for j in rings:
		var u0 := float(j) / rings
		var u1 := float(j + 1) / rings
		for i in rs:
			var a0 := float(i) / rs * TAU
			var a1 := float(i + 1) / rs * TAU
			var v := [_roof_pt(a0, u0, eave_r, eave_y, crown_r, crown_y, i % 2 == 0), _roof_pt(a1, u0, eave_r, eave_y, crown_r, crown_y, (i + 1) % 2 == 0),
				_roof_pt(a1, u1, eave_r, eave_y, crown_r, crown_y, (i + 1) % 2 == 0), _roof_pt(a0, u1, eave_r, eave_y, crown_r, crown_y, i % 2 == 0)]
			var soot := lerpf(1.0, 0.62, pow(u1, 2.2))
			var col := felt * _panel_tone(i / 8 + j * 9) * soot
			_quad(M.FELT, v[0], v[1], v[2], v[3], Vector3(0, -2.0, 0), col)
	# felt overhang lip over the wall top
	_ring_wall(M.FELT, eave_r, r + 0.03, eave_y - 0.12, eave_y + 0.01, seg, door_a, door_half * 0.6, felt * 0.93, false)
	# woollen bands round the wall (ochre-brown) and roof ropes (crown to eave, plus a ring)
	var band := Color(0.5, 0.36, 0.24)
	for y: float in [0.38, 0.95, 1.38]:
		_ring_wall(M.PLAIN, r + 0.045, r + 0.045, y - 0.06, y + 0.06, seg, door_a, door_half + 0.04, band * _tone(1.0, 0.06), false, roll_a if y < 0.62 else -INF, roll_half)
	for i in 8:
		var a := float(i) / 8.0 * TAU + 0.2
		var pts := []
		for k in 5:
			pts.append(_roof_pt(a + k * 0.04, float(k) / 4.0, eave_r + 0.03, eave_y + 0.03, crown_r + 0.02, crown_y + 0.03, true))
		for k in 4:
			_beam(M.PLAIN, pts[k], pts[k + 1], 0.03, band.darkened(0.15))
	for i in rs:
		var a0 := float(i) / rs * TAU
		var a1 := float(i + 1) / rs * TAU
		_beam(M.PLAIN, _roof_pt(a0, 0.45, eave_r + 0.03, eave_y + 0.03, crown_r, crown_y + 0.03, true), _roof_pt(a1, 0.45, eave_r + 0.03, eave_y + 0.03, crown_r, crown_y + 0.03, true), 0.025, band.darkened(0.1))
	# crown ring, crossed bent bars, felt flap half drawn back, stovepipe
	var wood := Color(0.82, 0.66, 0.46)
	_ring_wall(M.WOOD, crown_r + 0.06, crown_r + 0.06, crown_y - 0.06, crown_y + 0.1, 24, -INF, 0.0, wood, false)
	_ring_wall(M.WOOD, crown_r - 0.07, crown_r - 0.07, crown_y - 0.06, crown_y + 0.1, 24, -INF, 0.0, wood * 0.8, true)
	_disc_ring(M.WOOD, crown_r - 0.07, crown_r + 0.06, crown_y + 0.1, 24, wood * 1.05)
	for i in 3:
		for s: float in [-0.22, 0.22]:
			var a := float(i) / 3.0 * PI
			var d := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-d.z, 0, d.x) * s
			var prev := side - d * crown_r + Vector3(0, crown_y + 0.08, 0)
			for k in range(1, 5):
				var t := -1.0 + 2.0 * k / 4.0
				var q := side + d * crown_r * t + Vector3(0, crown_y + 0.08 + 0.32 * (1.0 - t * t), 0)
				_beam(M.WOOD, prev, q, 0.035, wood * 0.92)
				prev = q
	var flap := 6
	for i in flap:   # crown flap: a felt square drawn back over the north half, sagging off the far rim
		var t0 := float(i) / flap
		var t1 := float(i + 1) / flap
		var z0 := lerpf(-0.1, -crown_r - 0.9, t0)
		var z1 := lerpf(-0.1, -crown_r - 0.9, t1)
		var y0 := crown_y + 0.42 * (1.0 - pow(t0, 1.6)) - 0.35 * pow(t0, 3.0)
		var y1 := crown_y + 0.42 * (1.0 - pow(t1, 1.6)) - 0.35 * pow(t1, 3.0)
		var hw := crown_r + 0.25
		_quad(M.FELT, Vector3(-hw, y0, z0), Vector3(hw, y0, z0), Vector3(hw, y1, z1), Vector3(-hw, y1, z1), Vector3(0, y0 - 2.0, (z0 + z1) * 0.5), felt * 0.7 * _tone(1.0, 0.04), true)
	_cyl(M.PLAIN, 0.08, 0.08, 1.2, 8, Transform3D(Basis.IDENTITY, Vector3(0.32, crown_y - 0.2, 0.25)), Color(0.18, 0.16, 0.15))
	_cyl(M.PLAIN, 0.12, 0.12, 0.12, 8, Transform3D(Basis.IDENTITY, Vector3(0.32, crown_y + 0.95, 0.25)), Color(0.14, 0.12, 0.11))
	# door: frame, two painted leaves (faded red, worn at the edges), rolled felt curtain above
	var dc := Vector3(cos(door_a), 0, sin(door_a))
	var dt := Vector3(-dc.z, 0, dc.x)
	var db := Basis(dt, Vector3.UP, dc)
	var fr := dc * (r + 0.02)
	_box(M.WOOD, Vector3(1.12, 0.12, 0.14), fr + Vector3(0, 1.42, 0), db, wood * 0.85)
	_box(M.WOOD, Vector3(1.12, 0.1, 0.14), fr + Vector3(0, 0.02, 0), db, wood * 0.75)
	for s: float in [-1.0, 1.0]:
		_box(M.WOOD, Vector3(0.1, 1.4, 0.14), fr + dt * s * 0.51 + Vector3(0, 0.72, 0), db, wood * 0.85)
		_box(M.WOOD, Vector3(0.44, 1.26, 0.05), fr + dt * s * 0.235 + Vector3(0, 0.72, -0.0), db, Color(0.62, 0.3, 0.2) * _tone(1.0, 0.05))
		_box(M.PLAIN, Vector3(0.3, 0.3, 0.02), fr + dc * 0.035 + dt * s * 0.235 + Vector3(0, 0.95, 0), db, Color(0.7, 0.55, 0.32))   # painted panel
	_beam(M.FELT, fr + dc * 0.12 - dt * 0.62 + Vector3(0, 1.56, 0), fr + dc * 0.12 + dt * 0.62 + Vector3(0, 1.56, 0), 0.12, felt * 0.8)
	# skirt stones
	var ns := 34
	for i in ns:
		var a := float(i) / ns * TAU + _r(-0.05, 0.05)
		if absf(wrapf(a - door_a, -PI, PI)) < door_half + 0.1:
			continue
		_chunk(M.STONE, _r(0.12, 0.2), Vector3(cos(a) * (r + 0.2), 0.04, sin(a) * (r + 0.2)), _tone(0.9, 0.08))


## Felt tone of panel `i`: covers are patched over years, so neighbouring panels differ a little.
func _panel_tone(i: int) -> float:
	var h := absi(hash(i * 7919 + 13)) % 1000 / 1000.0
	return 0.86 + 0.18 * h


## Point on the roof at angle a, u from the eave (0) to the crown (1); pole angles stand 2 cm proud, the felt
## between them sags, so the 64 poles read through the cover.
func _roof_pt(a: float, u: float, er: float, ey: float, cr: float, cy: float, pole: bool) -> Vector3:
	var rr := lerpf(er, cr, u)
	var y := lerpf(ey, cy, pow(u, 0.85)) + (0.018 if pole else -0.006) * sin(u * PI)
	return Vector3(cos(a) * rr, y, sin(a) * rr)


# ---------- primitives (metres, through _xf) ----------

func _r(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


## Vertex tone near `v`, ± `d`: per-piece variation that the shader multiplies into the texture.
func _tone(v: float, d: float) -> Color:
	var t := v + _rng.randf_range(-d, d)
	return Color(t, t, t)


func _rect(sx: float, sz: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-sx * 0.5, -sz * 0.5), Vector2(sx * 0.5, -sz * 0.5), Vector2(sx * 0.5, sz * 0.5), Vector2(-sx * 0.5, sz * 0.5)])


## Upright prism of plan `poly` (x, z around `base`) from base.y up `h`, its plan shrunk by `batter` per metre
## of height (masonry piers lean in), flat-shaded, top capped.
func _column(m: int, poly: PackedVector2Array, base: Vector3, h: float, batter: float, col: Color) -> void:
	var n := poly.size()
	var mid := Vector2.ZERO
	for q in poly:
		mid += q / n
	var inside := base + Vector3(mid.x, h * 0.5, mid.y)
	var top := []
	var bot := []
	for q in poly:
		var d := (q - mid)
		var shrink := maxf(0.0, 1.0 - batter * h / maxf(d.length(), 0.01))
		var qt := mid + d * shrink
		bot.append(base + Vector3(q.x, 0, q.y))
		top.append(base + Vector3(qt.x, h, qt.y))
	for i in n:
		var j := (i + 1) % n
		_quad(m, bot[i], bot[j], top[j], top[i], inside, col)
	for i in range(1, n - 1):
		_tri(m, top[0], top[i], top[i + 1], inside, col)


## Box of size s centred at c, turned by b.
func _box(m: int, s: Vector3, c: Vector3, b: Basis, col: Color) -> void:
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for f: Array in [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3], [0, 1, 5, 4]]:
		_quad(m, c + b * v[f[0]], c + b * v[f[1]], c + b * v[f[2]], c + b * v[f[3]], c, col)


## Square-section bar of width w from a to b (rails, cables, ropes, slats): four sides, no end caps, which are
## too small to see from the game camera.
func _beam(m: int, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var ax := b - a
	if ax.length_squared() < 1e-8:
		return
	var up := Vector3.UP if absf(ax.normalized().y) < 0.9 else Vector3.RIGHT
	var s1 := ax.cross(up).normalized() * w * 0.5
	var s2 := ax.cross(s1).normalized() * w * 0.5
	var c := (a + b) * 0.5
	var cs := [s1 + s2, s1 - s2, -s1 - s2, -s1 + s2]
	for i in 4:
		var j := (i + 1) % 4
		_quad(m, a + cs[i], b + cs[i], b + cs[j], a + cs[j], c, col)


## Truncated cone along local y from 0 to h (rt top, rb bottom), smooth sides, top cap, placed by `place`.
func _cyl(m: int, rt: float, rb: float, h: float, seg: int, place: Transform3D, col: Color) -> void:
	var slope := (rb - rt) / h
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := place.basis * (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := place.basis * (d1 + Vector3(0, slope, 0)).normalized()
		var p := [place * (d0 * rb), place * (d1 * rb), place * (d1 * rt + Vector3(0, h, 0)), place * (d0 * rt + Vector3(0, h, 0))]
		_tri_n(m, p[0], p[2], p[1], n0, n1, n1, col)
		_tri_n(m, p[0], p[3], p[2], n0, n0, n1, col)
		_tri(m, place * Vector3(0, h, 0), p[2], p[3], place * Vector3(0, h * 0.5, 0), col)


## Smooth ring wall of radius rb at y0 to rt at y1, `seg` sides, facing out (or in when `inward`); skips the
## arc of half-width `gap` round `gap_a`, and a second arc round `gap2_a` (the yurt's door, its rolled felt).
func _ring_wall(m: int, rb: float, rt: float, y0: float, y1: float, seg: int, gap_a: float, gap: float, col: Color, inward: bool, gap2_a := -INF, gap2 := 0.0) -> void:
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var am := (a0 + a1) * 0.5
		if gap_a > -INF and absf(wrapf(am - gap_a, -PI, PI)) < gap:
			continue
		if gap2_a > -INF and absf(wrapf(am - gap2_a, -PI, PI)) < gap2:
			continue
		_wall_quad(m, rb, rt, a0, a1, y0, y1, col, inward)


func _wall_quad(m: int, rb: float, rt: float, a0: float, a1: float, y0: float, y1: float, col: Color, inward := false) -> void:
	var d0 := Vector3(cos(a0), 0, sin(a0))
	var d1 := Vector3(cos(a1), 0, sin(a1))
	var s := -1.0 if inward else 1.0
	var p := [d0 * rb + Vector3(0, y0, 0), d1 * rb + Vector3(0, y0, 0), d1 * rt + Vector3(0, y1, 0), d0 * rt + Vector3(0, y1, 0)]
	_tri_n(m, p[0], p[2], p[1], d0 * s, d1 * s, d1 * s, col)
	_tri_n(m, p[0], p[3], p[2], d0 * s, d0 * s, d1 * s, col)


## Flat disc of radius r at height y, facing up (or down).
func _disc(m: int, r: float, y: float, seg: int, col: Color, down := false) -> void:
	var c := Vector3(0, y, 0)
	var n := Vector3.DOWN if down else Vector3.UP
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		_tri(m, c, c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r, c - n, col)


## Flat annulus between ri and ro at height y, facing up (the crown ring's top).
func _disc_ring(m: int, ri: float, ro: float, y: float, seg: int, col: Color) -> void:
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(m, d0 * ri + Vector3(0, y, 0), d1 * ri + Vector3(0, y, 0), d1 * ro + Vector3(0, y, 0), d0 * ro + Vector3(0, y, 0), Vector3(0, y - 1.0, 0), col)


const _ICO_F := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
	[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]


## Lumpy stone of size s at p (FortBuild._chunk): a bent, flattened icosahedron, flat-shaded.
func _chunk(m: int, s: float, p: Vector3, col: Color) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := Vector3(_r(2.0, 4.0), _r(2.0, 4.0), _r(2.0, 4.0))
	var ph := Vector3(_r(0.0, 6.0), _r(0.0, 6.0), _r(0.0, 6.0))
	var fl := _r(0.45, 0.7)
	var b := Basis(Vector3.UP, _r(0.0, TAU))
	var v := []
	for q: Vector3 in raw:
		var u := q.normalized()
		var k := 1.0 + 0.22 * sin(u.x * f.x + ph.x) + 0.2 * sin(u.y * f.y + ph.y) + 0.18 * sin(u.z * f.z + ph.z)
		v.append(p + b * (Vector3(u.x, u.y * fl, u.z) * s * k))
	for fc: Array in _ICO_F:
		_tri(m, v[fc[0]], v[fc[1]], v[fc[2]], p, col)


## Quad a-b-c-d; its faces point away from `inside` (both ways when `both`: thin felt seen from either side).
func _quad(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Color, both := false) -> void:
	_tri(m, a, b, c, inside, col)
	_tri(m, a, c, d, inside, col)
	if both:
		var mid := (a + b + c + d) * 0.25
		var away := mid + (mid - inside)
		_tri(m, a, b, c, away, col)
		_tri(m, a, c, d, away, col)


## Flat triangle facing away from `inside`, so the winding written above never decides which side is lit.
func _tri(m: int, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	_tri_n(m, a, b, c, n, n, n, col)


## Triangle with per-vertex normals in metres (through _xf). UVs from the face's dominant axis, in metres per
## TILE, like FortBuild, so the texel size is the same on every face and every instance.
func _tri_n(m: int, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	if not _st.has(m):
		var nst := SurfaceTool.new()
		nst.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[m] = nst
	var st: SurfaceTool = _st[m]
	a = _xf * a
	b = _xf * b
	c = _xf * c
	var fn := (na + nb + nc).normalized()
	var k := 1.0 / float(TILE[m])
	var order := [[a, na], [c, nc], [b, nb]] if (b - a).cross(c - a).dot(fn) > 0.0 else [[a, na], [b, nb], [c, nc]]
	for v: Array in order:
		var p: Vector3 = v[0]
		var uv: Vector2
		if absf(fn.y) > 0.75:
			uv = Vector2(p.x, p.z)
		elif absf(fn.x) >= absf(fn.z):
			uv = Vector2(p.z * signf(fn.x if fn.x != 0.0 else 1.0), -p.y)
		else:
			uv = Vector2(-p.x * signf(fn.z if fn.z != 0.0 else 1.0), -p.y)
		st.set_color(col)
		st.set_normal(v[1])
		st.set_uv(uv * k)
		st.add_vertex((p + Vector3(0, _lift, 0)) * _k)


## One surface per material, in enum order, each with its prop_wear material for this model's scale.
func _commit(unit: float, wear: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	var ms := _st.keys()
	ms.sort()
	for m: int in ms:
		var st: SurfaceTool = _st[m]
		st.generate_tangents()
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, _material(m, unit, wear))
	return out


## prop_wear material of one surface: texture set, gain and wear strengths per material, `unit` metres per mesh
## unit of this model, ground and damp heights from `wear` (metres).
static func _material(m: int, unit: float, wear: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/prop_wear.gdshader")
	sm.set_shader_parameter("unit", unit)
	for k: String in wear:
		sm.set_shader_parameter(k, wear[k])
	var tex := ""
	var nrm := ""
	match m:
		M.STONE:
			tex = FORT + "stone_color.jpg"
			nrm = FORT + "stone_normal.jpg"
			sm.set_shader_parameter("gain", Vector3(1.0, 0.95, 0.86))
			sm.set_shader_parameter("normal_depth", 1.3)
			sm.set_shader_parameter("stain", 0.3)
			sm.set_shader_parameter("dust_top", 0.08)
		M.CONC:
			tex = FORT + "conc_color.jpg"
			nrm = FORT + "conc_normal.jpg"
			sm.set_shader_parameter("gain", Vector3(0.84, 0.79, 0.7))
			sm.set_shader_parameter("normal_depth", 1.2)
			sm.set_shader_parameter("stain", 0.3)
			sm.set_shader_parameter("dust_top", 0.1)
		M.WOOD:
			tex = FORT + "wood_color.jpg"
			nrm = FORT + "wood_normal.jpg"
			sm.set_shader_parameter("gain", Vector3(0.82, 0.72, 0.6))
			sm.set_shader_parameter("normal_depth", 1.2)
			sm.set_shader_parameter("stain", 0.28)
			sm.set_shader_parameter("dust_top", 0.3)
		M.FELT:
			tex = FELT_TEX + "albedo.jpg"
			nrm = FELT_TEX + "nh.jpg"
			sm.set_shader_parameter("tex_norm", true)   # hessian is dark and golden: only its weave is kept,
			sm.set_shader_parameter("desat", 0.92)      # the vertex tone sets the felt colour
			sm.set_shader_parameter("tex_mix", 0.45)
			sm.set_shader_parameter("gain", Vector3(0.95, 0.95, 0.95))
			sm.set_shader_parameter("normal_depth", 0.5)
			sm.set_shader_parameter("stain", 0.22)
			sm.set_shader_parameter("stain_scale", 0.9)
			sm.set_shader_parameter("dust_top", 0.12)
			sm.set_shader_parameter("rough", 0.97)
			sm.set_shader_parameter("rough_var", 0.03)
		M.PLAIN:
			sm.set_shader_parameter("stain", 0.2)
			sm.set_shader_parameter("rough", 0.85)
			sm.set_shader_parameter("rough_var", 0.12)
	if tex != "" and ResourceLoader.exists(tex):
		sm.set_shader_parameter("color_tex", load(tex))
	if nrm != "" and ResourceLoader.exists(nrm):
		sm.set_shader_parameter("normal_tex", load(nrm))
		sm.set_shader_parameter("use_normal", true)
	return sm
