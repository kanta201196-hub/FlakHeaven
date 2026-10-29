class_name FortBuild
extends FortWalls
## Highland fort «Укрепрайон» (spec docs/superpowers/specs/2026-10-25-fortified-area-design.md), built in code at
## first use. A mountain qala of rammed earth and mud brick, in the village's building tradition (adobe walls,
## timber, the same weathering, adobe_wear.gdshaderinc): battered walls on a rubble-stone plinth that wander
## along the ground, semi-round buttresses, eroded parapets with loopholes and timber machicolation balconies,
## squat tapered towers (rounded-square keeps and round bastions), a gate with a timber-framed passage between two
## bastions, a stepped citadel with a keep, roof terraces, a stair and an ayvan, rooms along the inner walls.
## Erosion is in the shapes (rain gullies, notched parapets, scree at the feet, fallen plaster, mud repairs) and
## in the material (fort.gdshader: weathered plaster, rammed-earth lifts, a damp foot from the vertex colour).
## Numbers are in preview units (≈ metres; the old three.js preview's units): wall line ±46, gate in +z. The mesh
## is returned in unit space (wall line ±0.42); Render3D scales it by the map object's size. One surface per
## material. FA-03: the model is split into breakable pieces (FortDamage ids: towers t0..t3, wall sections
## w0..w7, gate, store, citadel) over a fixed base. mesh() merges base and intact pieces for every untouched fort;
## FortView swaps to base() + piece(id, state) once a fort is hit. Broken variants build in a second background
## task after the intact set.

const WH := 15.0                ## wall height to the parapet's crest (effects height, FortArea.piece_spot)
const WT := 7.0                 ## wall thickness the blasts test against (FortDamage), mid height of the batter
const TOWER_R := 10.5           ## a tower's mean half width
const TOWER_H := 23.0           ## tower roof, under the launcher pad
const PAD_H := 0.6              ## concrete turntable pad on each tower
const TOWER_C := S * K          ## tower centre, ±share of the size on both axes
const TOWER_TOP := (TOWER_H + PAD_H) * K   ## pad top above the ground, share of the size (FortArea launchers)
## Jeep spots in the yard, unit space: by the citadel's door and by the gate road.
const YARD := [Vector2(8.0 * K, 6.0 * K), Vector2(2.0 * K, 28.0 * K)]
## Breakable wall sections (FA-03, FortDamage): [id, a, b, out, patches] in preview units, two per side; the
## south pair is the wall either side of the gate. a → b is the logic line the blasts test; the drawn wall
## wanders up to ~2 units off it (_wall_at). `out` — which side of a → b (its left normal × out) faces outwards;
## patches — exposed mud brick / cement repair [x along the run from its centre, y, w, h, material].
const WALLS := [
	["w0", Vector2(-S, -S), Vector2(0, -S), -1.0, [[11.0, 5.0, 6.0, 4.0, M.BRICK]]],
	["w1", Vector2(0, -S), Vector2(S, -S), -1.0, [[-7.0, 3.0, 8.0, 5.0, M.BRICK]]],
	["w2", Vector2(-S, S), Vector2(-12, S), 1.0, [[-10.0, 6.0, 5.0, 3.0, M.BRICK]]],
	["w3", Vector2(12, S), Vector2(S, S), 1.0, [[-9.0, 4.0, 7.0, 4.0, M.BRICK], [8.0, 7.0, 5.0, 3.0, M.BRICK]]],
	["w4", Vector2(-S, -S), Vector2(-S, 0), 1.0, [[12.0, 2.0, 12.0, 10.0, M.CONC]]],
	["w5", Vector2(-S, 0), Vector2(-S, S), 1.0, [[1.0, 6.0, 6.0, 4.0, M.BRICK]]],
	["w6", Vector2(S, -S), Vector2(S, 0), -1.0, [[8.0, 5.0, 7.0, 4.0, M.BRICK]]],
	["w7", Vector2(S, 0), Vector2(S, S), -1.0, []],
]
const GATE_C := Vector2(0, S + 1)   ## gate passage centre and reach of a blast on it, preview units
const GATE_R := 7.0
const STORE_C := Vector2(30, -5)    ## fuel store (three tanks), centre and half extents, preview units
const STORE_H := Vector2(5, 10)

## Textured sets: [file prefix in game/art/fort, gain, gamma, tile (preview units per repeat), normal depth, grime, bleach].
## Tiles are twice the preview's: the game camera is far higher, at the preview's size stones melt into a flat tone.
## RUB_*: debris of the same sets, dustier and darker, no dust band or sun bleach, so piles read as broken material.
## MUD: the plaster photo graded to the brown of the village's rammed-earth walls.
const SETS := {
	M.PLASTER: ["plaster", Vector3(1.0, 0.92, 0.8), 1.05, 4.6, 0.42, 5.0, 12.0],
	M.STONE: ["stone", Vector3(1.05, 0.98, 0.88), 1.0, 7.0, 1.3, 4.0, 12.0],
	M.BRICK: ["brick", Vector3(0.95, 0.86, 0.74), 1.0, 5.2, 1.3, 5.0, 12.0],
	M.CONC: ["conc", Vector3(0.98, 0.84, 0.66), 1.0, 10.0, 1.3, 5.0, 12.0],
	M.WOOD: ["wood", Vector3(0.8, 0.72, 0.62), 1.0, 5.0, 1.3, 0.01, 12.0],
	M.RUB_PLASTER: ["plaster", Vector3(0.84, 0.72, 0.58), 1.0, 4.6, 0.6, 0.01, 99.0],
	M.RUB_BRICK: ["brick", Vector3(0.78, 0.66, 0.54), 1.0, 5.2, 1.3, 0.01, 99.0],
	M.RUB_STONE: ["stone", Vector3(0.86, 0.8, 0.72), 1.0, 7.0, 1.3, 0.01, 99.0],
	M.MUD: ["plaster", Vector3(0.9, 0.72, 0.52), 1.0, 4.6, 0.7, 5.0, 14.0],
}
## The fort's own grading of a set where it differs from the set as the village houses use it (set_material):
## the towers' and citadel's plaster a warmer, earthier lime-mud than the village houses' whitewash.
const FORT_GAIN := {M.PLASTER: Vector3(1.02, 0.86, 0.66)}
## Weathered mud plaster on the fort's earthen sets (fort.gdshader): [wear, lift of shaded vertical faces, courses]
const WEAR := {
	M.MUD: [1.0, Vector3(1.22, 1.15, 1.06), 1.0],
	M.PLASTER: [0.8, Vector3(1.15, 1.1, 1.04), 0.0],
	M.RUB_PLASTER: [0.6, Vector3(1.0, 1.0, 1.0), 0.0],
}
## Warm bounce from the sunlit ground into the shaded faces of the fort's earth, brick and stone (fort.gdshader,
## bounce.gdshaderinc), as on the village walls: the faces the camera sees are the shaded ones
const BOUNCE := 0.35
const BAG_TEX := "res://models/biome/b10_sandbag_post_sandbag_burlap_color.jpg"
const TOWERS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]   ## t0..t3, FortArea.tower_points order
## Tower shapes: rounded-square keeps at t0 and t3, round bastions at t1 and t2
const TOWER_SQUARE := [true, false, false, true]
const TOWER_PL := GROUND + 3.0   ## top of a tower's stone plinth
const CORNICE := 19.6            ## a tower's body ends here; the corbelled band and the parapet ring sit above

var _gcache := {}                # tower index → its rain gullies (_gullies)

static var _mesh: ArrayMesh      # base + every intact piece, one surface per material
static var _base: ArrayMesh
static var _intact := {}         # piece id → ArrayMesh
static var _broken := {}         # "id:state" → ArrayMesh (FortDamage.DAMAGED / BROKEN)
static var _mats := {}
static var _smats := {}
static var _task := -1
static var _btask := -1
static var _bstarted := false    # main thread only: the broken set's build was started (workers write _broken)


## The intact fort mesh, built once per run. Waits for prefetch() if it is still building, otherwise builds here.
static func mesh() -> ArrayMesh:
	_wait_intact()
	return _mesh


## Everything that never breaks (gate bastions, checkpoints): FortView draws it under the pieces.
static func base() -> ArrayMesh:
	_wait_intact()
	return _base


## Mesh of piece `id` (FortDamage ids) in `state` (FortDamage.INTACT / DAMAGED / BROKEN). A broken variant waits
## for the background build if it is not done yet (it starts right after the intact set, long before a fight).
static func piece(id: String, state: int) -> ArrayMesh:
	_wait_intact()
	if state == FortDamage.INTACT:
		return _intact.get(id)
	if _btask >= 0:
		WorkerThreadPool.wait_for_task_completion(_btask)
		_btask = -1
	if not _bstarted:
		_bstarted = true
		_make_broken()
	return _broken.get("%s:%d" % [id, state])


## Starts building the meshes in the background (Render3D, as soon as the Highland is on), so the first fort
## on screen does not stall a frame: the intact set first, then the broken variants. Cheap to call every frame.
## The two builds never overlap, so the material cache needs no lock.
static func prefetch() -> void:
	if _mesh == null and _task < 0:
		_task = WorkerThreadPool.add_task(_make, false, "fort_build")
	elif _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	elif _task < 0 and _mesh != null and not _bstarted:
		_bstarted = true
		_btask = WorkerThreadPool.add_task(_make_broken, false, "fort_build_broken")
	elif _btask >= 0 and WorkerThreadPool.is_task_completed(_btask):
		WorkerThreadPool.wait_for_task_completion(_btask)
		_btask = -1


static func _wait_intact() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _mesh == null:
		_make()


static func _make() -> void:
	var b := FortBuild.new()
	b._build()
	var arrays := b._arrays()
	var parts := _meshes(arrays)
	_intact = parts
	_base = parts["base"]
	_mesh = _merge(arrays)


static func _make_broken() -> void:
	var b := FortBuild.new()
	b._build_broken()
	_broken = _meshes(b._arrays())


## Material of one fort surface, shared by every piece: the fort shader for the textured sets (with the fort's
## weathering and vertex tones), weathered plain colours for the rest.
static func material(m: int) -> Material:
	if _mats.has(m):
		return _mats[m]
	var mat: Material
	if SETS.has(m):
		var sm := _set_shader(m)
		sm.set_shader_parameter("vcol", 1.0)
		sm.set_shader_parameter("bounce", BOUNCE if m != M.WOOD else 0.0)
		if FORT_GAIN.has(m):
			sm.set_shader_parameter("gain", FORT_GAIN[m])
		if WEAR.has(m):
			var w: Array = WEAR[m]
			sm.set_shader_parameter("wear", w[0])
			sm.set_shader_parameter("lift", w[1])
			sm.set_shader_parameter("courses", w[2])
		mat = sm
	elif m in [M.DARK, M.OLIVE, M.STEEL, M.SOOT, M.CHAR]:
		# plain colours get procedural wear and dust, not flat even paint (Kanta 26.10)
		match m:
			M.DARK:
				mat = flat_material(Color(0.1, 0.085, 0.07), 0.95, 1.0 / K)
			M.OLIVE:   # darker than the preview: the warm sun tint turned it lime
				mat = flat_material(Color(0.29, 0.3, 0.21), 0.95, 1.0 / K)
			M.STEEL:
				mat = flat_material(Color(0.357, 0.365, 0.361), 0.8, 1.0 / K)
			M.SOOT:   # burnt-out steel of the store, soot licking up walls
				mat = flat_material(Color(0.133, 0.114, 0.098), 1.0, 1.0 / K, 0.4)
			M.CHAR:   # charred timber and planks
				mat = flat_material(Color(0.2, 0.16, 0.13), 1.0, 1.0 / K, 0.4)
	else:
		var f := StandardMaterial3D.new()
		f.metallic_specular = 0.2
		f.roughness = 0.95
		match m:
			M.BAG:
				f.albedo_color = Color(0.85, 0.78, 0.65)
				if ResourceLoader.exists(BAG_TEX):
					f.albedo_texture = load(BAG_TEX)
				f.roughness = 1.0
			M.NET:    # camouflage net over the store, seen from both sides
				f.albedo_color = Color(0.46, 0.44, 0.29)
				f.roughness = 1.0
				f.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = f
	_mats[m] = mat
	return mat


## A texture set's material as other models use it (the village houses): fort shader, the set's own grading,
## none of the fort's weathering or vertex tones. `m` must be a SETS key; other ids get material(m).
static func set_material(m: int) -> Material:
	if not SETS.has(m):
		return material(m)
	if not _smats.has(m):
		_smats[m] = _set_shader(m)
	return _smats[m]


## The fort shader with texture set m's photos and grading (SETS); material() adds the fort-only extras.
static func _set_shader(m: int) -> ShaderMaterial:
	var s: Array = SETS[m]
	var sm := ShaderMaterial.new()
	sm.shader = FORT_SHADER
	var dir := "res://art/fort/%s_" % s[0]
	sm.set_shader_parameter("color_tex", load(dir + "color.jpg"))
	sm.set_shader_parameter("normal_tex", load(dir + "normal.jpg"))
	sm.set_shader_parameter("arm_tex", load(dir + "arm.jpg"))
	sm.set_shader_parameter("gain", s[1])
	sm.set_shader_parameter("gamma", s[2])
	sm.set_shader_parameter("normal_depth", s[4])
	sm.set_shader_parameter("grime", s[5])
	sm.set_shader_parameter("bleach", s[6])
	sm.set_shader_parameter("unit", 1.0 / K)
	return sm


## Shaders of the fort's materials. Preloaded with the script on the main thread: the materials are first made
## inside the fort and village build tasks, and a load() there hung the sortie start while the main thread waited.
const FLAT_SHADER := preload("res://shaders/weathered_flat.gdshader")
const FORT_SHADER := preload("res://shaders/fort.gdshader")


## Plain-coloured surface with procedural weathering (shaders/weathered_flat.gdshader): colour `c` (sRGB, as a
## StandardMaterial3D albedo), base `rough`ness, `unit` metres per mesh unit (fort: 1 / K, village models: 1) and
## how much `dust` settles. Shared by FortBuild and VillageHouses; callers cache the result.
static func flat_material(c: Color, rough: float, unit: float, dust := 1.0) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = FLAT_SHADER
	sm.set_shader_parameter("albedo", c)
	sm.set_shader_parameter("roughness", rough)
	sm.set_shader_parameter("unit", unit)
	sm.set_shader_parameter("dust", dust)
	return sm


## Metres one texture repeat covers for material m: the set's own tile, sandbags and flat colours otherwise.
func _uv_tile(m: int) -> float:
	if SETS.has(m):
		return float(SETS[m][3])
	return 2.0 if m == M.BAG else 8.0


## Surface arrays of several pieces joined per material (the intact fort is ~12 draw calls, not ~70). Works on
## arrays, never reads a committed mesh back: that would ask the RenderingServer from the worker thread while
## the main thread may be waiting on it (a deadlock seen at sortie start).
static func _merge(parts: Dictionary) -> ArrayMesh:
	var by := {}
	for id: String in parts:
		var sts: Dictionary = parts[id]
		for m: int in sts:
			var a: Array = sts[m]
			if not by.has(m):
				by[m] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(), PackedColorArray()]
			var o: Array = by[m]
			o[0].append_array(a[Mesh.ARRAY_VERTEX])
			o[1].append_array(a[Mesh.ARRAY_NORMAL])
			o[2].append_array(a[Mesh.ARRAY_TANGENT])
			o[3].append_array(a[Mesh.ARRAY_TEX_UV])
			o[4].append_array(a[Mesh.ARRAY_COLOR])
	var out := ArrayMesh.new()
	var ms := by.keys()
	ms.sort()
	for m: int in ms:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = by[m][0]
		arr[Mesh.ARRAY_NORMAL] = by[m][1]
		arr[Mesh.ARRAY_TANGENT] = by[m][2]
		arr[Mesh.ARRAY_TEX_UV] = by[m][3]
		arr[Mesh.ARRAY_COLOR] = by[m][4]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, material(m))
	return out


## One mesh per piece, surfaces in material order, materials shared between pieces.
static func _meshes(arrays: Dictionary) -> Dictionary:
	var out := {}
	for id: String in arrays:
		var me := ArrayMesh.new()
		var per: Dictionary = arrays[id]
		var ms := per.keys()
		ms.sort()
		for m: int in ms:
			me.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, per[m])
			me.surface_set_material(me.get_surface_count() - 1, material(m))
		out[id] = me
	return out


## Base and the intact pieces, each piece in its own FortDamage id so FortView can swap it on its own.
func _build() -> void:
	_begin("base")
	for sx: float in [-1.0, 1.0]:
		_bastion(sx)
	_box(M.WOOD, Vector3(8.8, 0.8, 8.4), Vector3(0, 10.0, S + 1.0))   # the deck over the passage
	for c: Vector2 in [Vector2(-18, S + 16), Vector2(18, S + 16)]:   # sandbag checkpoints on the gate road
		_sandbag_ring(c.x, GROUND - 0.4, c.y, 4.2, 0.0 if c.x < 0.0 else PI)
	_begin("citadel")
	_citadel()
	for i in 4:
		_begin("t%d" % i)
		_tower(i)
	for w: Array in WALLS:
		_begin(w[0])
		_wall(w, false)
	_begin("gate")
	_gate()
	_begin("store")
	_store(false)


## Damaged and broken variants of every piece, keyed "id:state" (FortDamage states).
func _build_broken() -> void:
	for i in 4:
		_begin("t%d:%d" % [i, FortDamage.DAMAGED])
		_tower(i, true)
		_begin("t%d:%d" % [i, FortDamage.BROKEN])
		_tower_broken(i)
	for w: Array in WALLS:
		_begin("%s:%d" % [w[0], FortDamage.BROKEN])
		_wall(w, true)
	_begin("gate:%d" % FortDamage.BROKEN)
	_gate(true)
	_begin("store:%d" % FortDamage.BROKEN)
	_store(true)
	_begin("citadel:%d" % FortDamage.BROKEN)
	_citadel(true)


# ---------- towers ----------

## Offset from tower i's centre of its outer face at angle a and height y, grown by `grow`: squat and strongly
## battered, a rounded square (t0, t3) or round (t1, t2), lumpy as hand-laid earth, cut by rain gullies.
func _tp(i: int, a: float, y: float, grow := 0.0) -> Vector2:
	var sq: bool = TOWER_SQUARE[i]
	var f := clampf((y - GROUND) / (CORNICE - GROUND), 0.0, 1.0)
	var r := lerpf(10.8 if sq else 12.2, 8.6 if sq else 9.6, f) + grow
	var o := _rrect(a, r, r, r * 0.42) if sq else Vector2.from_angle(a) * r
	var k := 1.0 + 0.045 * _pn(a, y * 0.13, 3.0 * i + 1.0)
	if not _gcache.has(i):
		_gcache[i] = _gullies(i)
	for gg: Vector3 in _gcache[i]:
		var d := wrapf(a - gg.x, -PI, PI) / gg.z
		k -= gg.y / r * exp(-d * d) * smoothstep(GROUND + 3.0, CORNICE + 2.0, y)
	return o * k


## Rain gullies of tower i: [angle, depth, width in radians], mostly on its weather (outer) side.
func _gullies(i: int) -> Array:
	var c: Vector2 = TOWERS[i]
	var out := atan2(c.y, c.x)
	var r := RandomNumberGenerator.new()
	r.seed = 31 + i
	var g := []
	for k in 4:
		g.append(Vector3(out + r.randf_range(-1.5, 1.5), r.randf_range(0.6, 1.1), r.randf_range(0.07, 0.12)))
	return g


## Unit outward normal (xz) of tower i's face at angle a, height y.
func _tn(i: int, a: float, y: float) -> Vector2:
	var t := _tp(i, a + 0.01, y) - _tp(i, a - 0.01, y)
	var n := Vector2(t.y, -t.x).normalized()
	return n if n.dot(_tp(i, a, y)) > 0.0 else -n


## Tower i: stone plinth, battered earth body with gullies and loopholes, a row of beam ends under a corbelled
## band, an eroded parapet ring with loopholes and spouts, timber machicolation balconies on its outer faces, a
## concrete pad with a sandbag nest for the launcher. `worn` (FortDamage.DAMAGED, the launcher at half HP): the
## crown and balconies on the outer side are knocked off and lie at the foot, snapped beams stick out.
func _tower(i: int, worn := false) -> void:
	var c: Vector2 = TOWERS[i] * S
	var out := atan2(c.y, c.x)
	var sq: bool = TOWER_SQUARE[i]
	var seg := 72 if sq else 64
	_tower_trunk(i, seg)
	var hit := func(a: float, arc: float) -> bool: return worn and absf(wrapf(a - out, -PI, PI)) < arc
	# beam ends of the roof joists, then the corbelled band over them
	var nb := 34
	for k in nb:
		var a := (k + 0.5) / nb * TAU + _r(-0.03, 0.03)
		if hit.call(a, 0.8) or _rng.randf() < 0.15:
			continue
		var n := _tn(i, a, 19.0)
		var p := c + _tp(i, a, 19.0) + n * 0.15
		_beam(Vector3(p.x, 19.0 + _r(-0.15, 0.15), p.y), 1.6, Vector3(n.x, 0, n.y), _r(-0.1, 0.03), M.WOOD, 0.26)
	var crown := func(a: float, y: float) -> Vector2:
		var e := 0.0
		if y > CORNICE + 0.2:
			e = 0.6
		if y > CORNICE + 1.7:
			e = 0.45
		return _tp(i, a, minf(y, CORNICE), e)
	_loft(M.PLASTER, c, crown, PackedFloat32Array([CORNICE - 0.2, CORNICE + 0.4, CORNICE + 1.6, CORNICE + 2.0]), seg, false)
	# the roof and the parapet ring (open over the knocked-off arc when worn)
	var ry := TOWER_H
	var path := PackedVector2Array()
	var fill := PackedVector2Array()
	for k in seg + 1:
		var a := float(k % seg) / seg * TAU
		path.append(c + _tp(i, a, CORNICE, 0.3))
		fill.append(c + _tp(i, a, CORNICE, -0.9))
	var sd := 3.0 * i
	if not worn:
		_parapet(M.PLASTER, path, -1.0, CORNICE + 2.0, 1.2, ry + 1.0, ry + 2.3, sd, true)
	else:
		var arc := PackedVector2Array()
		var a0 := out + 0.75
		for k in seg + 1:
			var a := a0 + (TAU - 1.5) * k / seg
			arc.append(c + _tp(i, a, CORNICE, 0.3))
		_parapet(M.PLASTER, arc, -1.0, CORNICE + 2.0, 1.2, ry + 1.0, ry + 2.3, sd, false)
	var up := Vector3.UP
	for k in seg:
		var p := fill[k]
		var q := fill[k + 1]
		_tri_n(M.PLASTER, Vector3(c.x, ry, c.y), Vector3(p.x, ry, p.y), Vector3(q.x, ry, q.y), up, up, up)
	# parapet loopholes and spouts
	for k in 11:
		var a := (k + _r(0.2, 0.8)) / 11.0 * TAU
		if hit.call(a, 0.85):
			continue
		var n := _tn(i, a, CORNICE)
		var p := c + _tp(i, a, CORNICE, 0.3) - n * 0.6
		var fb := Basis(Vector3.UP.cross(Vector3(n.x, 0, n.y)), Vector3.UP, Vector3(n.x, 0, n.y))
		_boxr(M.DARK, Vector3(0.45, 0.9, 1.9), Vector3(p.x, ry + 0.75, p.y), fb)
	for s: float in [-1.0, 1.0]:
		var a := out + s * _r(0.95, 1.4)
		var n := _tn(i, a, CORNICE)
		var zf := Vector3(n.x, 0, n.y)
		var p := c + _tp(i, a, CORNICE, 0.6)
		_boxr(M.WOOD, Vector3(0.45, 0.32, 2.4), Vector3(p.x, ry + 0.2, p.y), Basis(Vector3.UP.cross(zf), Vector3.UP, zf))
		var q := c + _tp(i, a, CORNICE - 0.6)
		_streak_t(Vector3(q.x, CORNICE - 0.6, q.y), Vector3.UP.cross(zf), zf, _r(6.0, 10.0), 0.5)
	# loopholes in the body, two rows
	for y: float in [8.5, 14.5]:
		for k in 7:
			var a := (k + _r(0.15, 0.85)) / 7.0 * TAU
			var n := _tn(i, a, y)
			var zf := Vector3(n.x, 0, n.y)
			var p := c + _tp(i, a, y) - n * 0.3
			var fb := Basis(Vector3.UP.cross(zf), Vector3.UP, zf) * Basis(Vector3.RIGHT, -0.14)
			_boxr(M.DARK, Vector3(0.5, 1.6, 1.0), Vector3(p.x, y, p.y), fb)
	# timber balconies: two on a square tower's outer faces, one on a round tower's outer side
	var balc := [out - PI * 0.25, out + PI * 0.25] if sq else [out]
	for a: float in balc:
		var n := _tn(i, a, 16.0)
		var zf := Vector3(n.x, 0, n.y)
		var p := c + _tp(i, a, 16.0) - n * 0.15
		if worn:
			_beam(Vector3(p.x, 15.6, p.y) + zf * 0.6, _r(1.6, 2.6), zf, _r(-0.5, 0.1))
		else:
			_balcony(Vector3(p.x, 16.0, p.y), Basis(Vector3.UP.cross(zf), Vector3.UP, zf), 4.2, 2.0)
	# the launcher's pad and nest
	_cyl(M.CONC, 7.0, 7.2, PAD_H, 32, _at(c.x, ry, c.y))
	_sandbag_ring(c.x, ry + PAD_H, c.y, 6.2, out + PI)
	# scree slumped at the foot
	for k in 3:
		var a := out + _r(-1.2, 1.2)
		var p := c + _tp(i, a, GROUND) + Vector2.from_angle(a) * 1.8
		_tint = Color(0.92, 0.88, 0.84)
		_heap(M.MUD, p, Vector2(_r(2.5, 4.0), _r(1.6, 2.4)), _r(1.0, 2.0), GROUND - 0.4, a + PI * 0.5)
		_tint = Color.WHITE
	if not worn:
		return
	var o := Vector3(cos(out), 0.0, sin(out))
	for k in 5:   # snapped corbels and joists over the knocked-off arc
		var a := out + _r(-0.8, 0.8)
		var n := _tn(i, a, 19.0)
		var p := c + _tp(i, a, 19.0)
		_beam(Vector3(p.x, 19.0 + _r(-0.3, 1.2), p.y), _r(2.0, 3.4), Vector3(n.x, 0, n.y), _r(-0.6, 0.3))
	for k in 6:   # crown pieces at the foot
		var a := out + _r(-0.9, 0.9)
		var d := 12.5 + _r(1.0, 8.0)
		_shard(M.PLASTER, Vector3(_r(2.0, 3.2), 1.9, 1.3), Vector3(c.x + cos(a) * d, GROUND + 0.6, c.y + sin(a) * d), _tumble(0.9), 8)
	for k in 4:   # what is left of the balconies
		var a := out + _r(-0.7, 0.7)
		var d := 13.0 + _r(1.0, 6.0)
		_boxr(M.WOOD, Vector3(_r(2.0, 4.0), 0.3, 0.4), Vector3(c.x + cos(a) * d, GROUND + 0.3, c.y + sin(a) * d), _tumble(0.4))
	_tint = Color(0.95, 0.9, 0.84)
	_heap(M.MUD, Vector2(c.x, c.y) + Vector2(o.x, o.z) * 15.0, Vector2(6.0, 4.0), 2.6, GROUND - 0.4, out + PI * 0.5)
	_tint = Color.WHITE
	_rubble(Vector3(c.x, GROUND, c.y) + o * 15.0, 50, 6.5, 1.6)
	_rubble(Vector3(c.x, ry + PAD_H, c.y) + o * 6.8, 10, 1.4, 0.7)   # chips on the pad, clear of the launcher


## Plinth and battered body of tower i up to the cornice, `seg` points round.
func _tower_trunk(i: int, seg: int) -> void:
	var c: Vector2 = TOWERS[i] * S
	var plinth := func(a: float, y: float) -> Vector2:
		return _tp(i, a, GROUND, 1.0 - 0.55 * clampf((y - GROUND + 0.8) / (TOWER_PL - GROUND + 0.8), 0.0, 1.0))
	_loft(M.STONE, c, plinth, PackedFloat32Array([GROUND - 0.8, GROUND + 1.2, TOWER_PL]), seg, false)
	var ledge := func(a: float, y: float) -> Vector2: return _tp(i, a, TOWER_PL, 0.45 - (y - TOWER_PL) * 1.5)
	_loft(M.STONE, c, ledge, PackedFloat32Array([TOWER_PL, TOWER_PL + 0.3]), seg, false)
	var body := func(a: float, y: float) -> Vector2: return _tp(i, a, y)
	var ys := PackedFloat32Array()
	var y := TOWER_PL - 0.2
	while y < CORNICE:
		ys.append(y)
		y += 1.3
	ys.append(CORNICE)
	_loft(M.PLASTER, c, body, ys, seg, false)


## Streak down a tower's face (flat, along its tangent plane at o): like _streak with the tower's own batter.
func _streak_t(o: Vector3, xa: Vector3, zf: Vector3, len: float, wd: float) -> void:
	_tint = Color(0.74, 0.7, 0.66)
	var s := 0.14
	var v := (Vector3.UP - zf * s).normalized()
	var n := (zf + Vector3.UP * s).normalized()
	var j := _r(-0.3, 0.3)
	_slab(M.PLASTER, o, xa, v, n, PackedVector2Array([Vector2(-wd, 0.0), Vector2(wd, 0.0), Vector2(wd * 0.5 + j, -len * 0.6),
		Vector2(wd * 0.15 + j, -len), Vector2(-wd * 0.3 + j * 0.5, -len * 0.75)]), 0.12)
	_tint = Color.WHITE


# ---------- broken towers ----------

## Crown collapsed (FortDamage.BROKEN, launcher destroyed): a jagged stump at ~60 % height, blown open towards
## the outside, the mud-brick core showing inside and on the gap faces, a crumbling rim, a rubble floor, snapped
## beams, and the collapse slumped into a cone of earth spilling out through the gap.
func _tower_broken(i: int) -> void:
	var c: Vector2 = TOWERS[i] * S
	var hb := TOWER_H * _r(0.55, 0.66)
	var out := atan2(c.y, c.x)
	var gap := 0.95
	var plinth := func(a: float, y: float) -> Vector2:
		return _tp(i, a, GROUND, 1.0 - 0.55 * clampf((y - GROUND + 0.8) / (TOWER_PL - GROUND + 0.8), 0.0, 1.0))
	_loft(M.STONE, c, plinth, PackedFloat32Array([GROUND - 0.8, GROUND + 1.2, TOWER_PL]), 56, false)
	_shell(i, M.PLASTER, 0.0, hb, out, gap, true)
	_shell(i, M.BRICK, 1.7, hb, out, gap, false)
	var t := gap * 0.5 + 0.06
	while t < TAU - gap * 0.5 - 0.06:   # crumbling brick rim along the jagged top
		var la := out + t
		var top := hb - _jag(la, c, out)
		var p := c + _tp(i, la, top, -0.8)
		_shard(M.RUB_BRICK if _rng.randf() < 0.75 else M.RUB_PLASTER, Vector3(_r(1.4, 1.9), _r(0.7, 1.6), _r(1.0, 1.5)),
			Vector3(p.x, top - 0.6, p.y), Basis(Vector3.UP, -la + _r(-0.25, 0.25)) * _tumble(0.25), 7)
		t += _r(0.1, 0.17)
	for sgn: float in [-1.0, 1.0]:   # the shell's torn ends crumble on into the blown gap, unevenly
		var ea := out + sgn * gap * 0.5
		var h0 := hb - _jag(ea, c, out)
		var path := PackedVector2Array()
		var hs := PackedFloat32Array()
		var sd := _rng.randf() * 30.0
		var n := 10
		for k in n + 1:
			var f := float(k) / n   # 0 just inside the shell's end, 1 well into the gap
			var la := ea + sgn * (f * 0.42 - 0.08)
			path.append(c + _tp(i, la, 0.0, -0.85))
			var fall := clampf(1.0 - pow(f, 1.2) * 0.85 + (_n1(f * 5.0, sd) - 0.5) * 0.35 * smoothstep(0.0, 0.2, f), 0.08, 1.0)
			hs.append(maxf(h0 * fall, TOWER_PL + 0.4))
		if sgn < 0.0:   # the sweep's outside is the path's right: keep it walking the same way round
			path.reverse()
			hs.reverse()
		_broken_end(M.BRICK, path, hs, 1.1, 1.1, 0.03, -1.0)
	var fy := hb * 0.42
	for k in 28:   # rubble floor inside
		var p := c + _tp(i, float(k) / 28.0 * TAU, fy, -1.9)
		var q := c + _tp(i, float(k + 1) / 28.0 * TAU, fy, -1.9)
		_tri(M.BRICK, Vector3(c.x, fy, c.y), Vector3(p.x, fy, p.y), Vector3(q.x, fy, q.y), Vector3(c.x, fy - 1.0, c.y))
	_rubble(Vector3(c.x, fy, c.y), 40, 7.0, 1.3)
	for k in 7:   # snapped joists
		var a := out + _r(1.0, 5.3)
		var p := c + _tp(i, a, hb * 0.7, -0.6)
		_beam(Vector3(p.x, hb * _r(0.55, 0.85), p.y), _r(2.4, 4.5), Vector3(cos(a), 0, sin(a)), _r(-0.7, 0.5))
	for k in 9:   # fallen crown pieces
		var a := out + _r(-1.3, 1.3)
		var d := 13.0 + _r(1.0, 11.0)
		_shard(M.PLASTER, Vector3(_r(2.0, 3.2), 1.9, 1.3), Vector3(c.x + cos(a) * d, GROUND + 0.6, c.y + sin(a) * d), _tumble(0.9), 8)
	var o := Vector2.from_angle(out)
	_tint = Color(0.95, 0.9, 0.84)
	_heap(M.MUD, c + o * 13.5, Vector2(9.0, 6.0), 4.0, GROUND - 0.4, out + PI * 0.5)
	_tint = Color.WHITE
	_rubble(Vector3(c.x, GROUND, c.y) + Vector3(o.x, 0, o.y) * 14.0, 110, 11.0, 2.0)
	_rubble(Vector3(c.x, GROUND + 2.0, c.y) + Vector3(o.x, 0, o.y) * 9.0, 40, 5.0, 1.6)


## Height bitten off the stump's top at angle `la`: a saw-tooth crown, deeper next to the blown gap at `out`.
func _jag(la: float, c: Vector2, out: float) -> float:
	var ga := absf(wrapf(la - out, -PI, PI))
	return (sin(la * 3.0 + c.x) * 0.5 + 0.5) * 4.0 + (sin(la * 13.0 + c.y) * 0.5 + 0.5) * 2.2 + maxf(0.0, 1.2 - ga) * 7.0


## Open shell of tower i's stump, inset `inset` from its face, up to hb (minus _jag), missing the arc `gap`
## around `out`. `outward` — the plaster face, else the brick core seen from inside.
func _shell(i: int, m: int, inset: float, hb: float, out: float, gap: float, outward: bool) -> void:
	var c: Vector2 = TOWERS[i] * S
	var segs := 52
	var rings := 10
	var grid := []
	var nrm := []
	for k in segs + 1:
		var la := out + gap * 0.5 + (TAU - gap) * float(k) / segs
		var drop := _jag(la, c, out)
		var col := []
		var nc := []
		for j in rings + 1:
			var y := TOWER_PL - 0.3 + (hb - TOWER_PL + 0.3) * float(j) / rings
			var p := c + _tp(i, la, y, -inset)
			col.append(Vector3(p.x, y - drop * smoothstep(hb * 0.45, hb, y), p.y))
			var n := _tn(i, la, y)
			nc.append(Vector3(n.x, 0.15, n.y).normalized() * (1.0 if outward else -1.0))
		grid.append(col)
		nrm.append(nc)
	for k in segs:
		for j in rings:
			_tri_n(m, grid[k][j], grid[k + 1][j], grid[k + 1][j + 1], nrm[k][j], nrm[k + 1][j], nrm[k + 1][j + 1])
			_tri_n(m, grid[k][j], grid[k + 1][j + 1], grid[k][j + 1], nrm[k][j], nrm[k + 1][j + 1], nrm[k][j + 1])