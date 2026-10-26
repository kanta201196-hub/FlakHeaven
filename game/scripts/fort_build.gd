class_name FortBuild
extends RefCounted
## Highland fort model, texture set Г (FA-02, Kanta 2026-10-25; spec docs/superpowers/specs/2026-10-25-fortified-area-design.md).
## Built in code at first use, ported from the approved three.js preview
## (/mnt/project-files/visual/fort_rework/hq/hq_scene.html), so the numbers below are the preview's units:
## wall line ±46, round corner towers r 10.5 × 23, gate in +z. The mesh is returned in unit space (wall line ±0.42,
## like the old AdobeBuild.fort), Render3D scales it by the map object's size. One surface per material.
## Box-projected UVs are baked here in preview units, so the texel size does not change with the fort's size.
## FA-03: the model is split into breakable pieces (FortDamage ids: towers t0..t3, wall sections w0..w7, gate,
## store) over a fixed base. mesh() merges base and intact pieces for every untouched fort; FortView swaps to
## base() + piece(id, state) once a fort is hit. Broken variants (preview hq_scene.html brokenTower, wallBreach,
## blown gate, burnt store) build in a second background task after the intact set.

enum M { PLASTER, STONE, BRICK, CONC, WOOD, DARK, BAG, OLIVE, STEEL, RUB_PLASTER, RUB_BRICK, RUB_STONE, SOOT, CHAR, NET }

const K := 0.42 / 46.0          ## preview unit → unit mesh (the old fort's wall line was 0.42)
const S := 46.0                 ## wall line, half side
const WH := 15.0                ## wall height
const WT := 7.0                 ## wall base thickness
const TOWER_R := 10.5
const TOWER_H := 23.0
const PAD_H := 0.6              ## concrete turntable pad on each tower
const TOWER_C := S * K          ## tower centre, ±share of the size on both axes
const TOWER_TOP := (TOWER_H + PAD_H) * K   ## pad top above the ground, share of the size (FortArea launchers)
## Jeep spots in the yard (preview props), unit space: by the citadel's door and by the gate road.
const YARD := [Vector2(8.0 * K, 6.0 * K), Vector2(2.0 * K, 28.0 * K)]
## Breakable wall sections (FA-03, FortDamage): [id, a, b, out, patches] in preview units, two per side; the
## south pair is the wall either side of the gate. `out` — which local z side of the run faces outwards;
## patches — exposed brick / concrete repair [x along the run from its centre, y, w, h, material] (_wall_run).
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
## Plaster gain a touch paler than the preview's (the game's sun is warmer). Tiles are twice the preview's: the game camera is far higher, at the preview's size stones melt into a flat tone.
## RUB_*: debris of the same sets, dustier and darker, no dust band or sun bleach (the preview's RUB), so piles
## read as broken material rather than clean blocks.
const SETS := {
	M.PLASTER: ["plaster", Vector3(1.0, 0.92, 0.8), 1.05, 4.6, 0.42, 5.0, 12.0],
	M.STONE: ["stone", Vector3(1.05, 0.98, 0.88), 1.0, 7.0, 1.3, 4.0, 12.0],
	M.BRICK: ["brick", Vector3(0.95, 0.86, 0.74), 1.0, 5.2, 1.3, 5.0, 12.0],
	M.CONC: ["conc", Vector3(0.98, 0.84, 0.66), 1.0, 10.0, 1.3, 5.0, 12.0],
	M.WOOD: ["wood", Vector3(0.8, 0.72, 0.62), 1.0, 5.0, 1.3, 0.01, 12.0],
	M.RUB_PLASTER: ["plaster", Vector3(0.84, 0.72, 0.58), 1.0, 4.6, 0.6, 0.01, 99.0],
	M.RUB_BRICK: ["brick", Vector3(0.78, 0.66, 0.54), 1.0, 5.2, 1.3, 0.01, 99.0],
	M.RUB_STONE: ["stone", Vector3(0.86, 0.8, 0.72), 1.0, 7.0, 1.3, 0.01, 99.0],
}
const BAG_TEX := "res://models/biome/b10_sandbag_post_sandbag_burlap_color.jpg"
const TOWERS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]   ## t0..t3, FortArea.tower_points order

static var _mesh: ArrayMesh      # base + every intact piece, one surface per material
static var _base: ArrayMesh
static var _intact := {}         # piece id → ArrayMesh
static var _broken := {}         # "id:state" → ArrayMesh (FortDamage.DAMAGED / BROKEN)
static var _mats := {}
static var _task := -1
static var _btask := -1
static var _bstarted := false    # main thread only: the broken set's build was started (workers write _broken)

var _st := {}                    # piece → {material → SurfaceTool}
var _piece := "base"
var _xf := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()


## The intact fort mesh, built once per run (~25k triangles, ~0.25 s on the cloud CPU). Waits for prefetch() if
## it is still building, otherwise builds here.
static func mesh() -> ArrayMesh:
	_wait_intact()
	return _mesh


## Everything that never breaks (citadel, rooms, gate half-towers): FortView draws it under the pieces.
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


## Material of one surface, shared by every piece: the fort shader for the textured sets, plain lit colours for the rest.
static func material(m: int) -> Material:
	if _mats.has(m):
		return _mats[m]
	var mat: Material
	if SETS.has(m):
		var s: Array = SETS[m]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/fort.gdshader")
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
		mat = sm
	elif m in [M.DARK, M.OLIVE, M.STEEL, M.SOOT, M.CHAR]:
		# plain colours get procedural wear and dust, not flat even paint (Kanta 26.10)
		match m:
			M.DARK:
				mat = flat_material(Color(0.118, 0.102, 0.086), 0.95, 1.0 / K)
			M.OLIVE:   # darker than the preview: the warm sun tint turned it lime
				mat = flat_material(Color(0.29, 0.3, 0.21), 0.95, 1.0 / K)
			M.STEEL:
				mat = flat_material(Color(0.357, 0.365, 0.361), 0.8, 1.0 / K)
			M.SOOT:   # burnt-out steel of the store
				mat = flat_material(Color(0.133, 0.114, 0.098), 1.0, 1.0 / K, 0.4)
			M.CHAR:   # charred gate leaves and planks
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


## Shader of flat_material. Preloaded with the script on the main thread: the materials are first made inside
## the fort and village build tasks, and a load() there hung the sortie start while the main thread waited on them.
const FLAT_SHADER := preload("res://shaders/weathered_flat.gdshader")


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


## Tile size of a surface's UVs, preview units per texture repeat.
static func _tile(m: int) -> float:
	if SETS.has(m):
		return float(SETS[m][3])
	return 2.0 if m == M.BAG else 8.0


## Surface arrays of several pieces joined per material (the intact fort is ~10 draw calls, not ~60). Works on
## arrays, never reads a committed mesh back: that would ask the RenderingServer from the worker thread while
## the main thread may be waiting on it (a deadlock seen at sortie start).
static func _merge(parts: Dictionary) -> ArrayMesh:
	var by := {}
	for id: String in parts:
		var sts: Dictionary = parts[id]
		for m: int in sts:
			var a: Array = sts[m]
			if not by.has(m):
				by[m] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array()]
			var o: Array = by[m]
			o[0].append_array(a[Mesh.ARRAY_VERTEX])
			o[1].append_array(a[Mesh.ARRAY_NORMAL])
			o[2].append_array(a[Mesh.ARRAY_TANGENT])
			o[3].append_array(a[Mesh.ARRAY_TEX_UV])
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
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, material(m))
	return out


## Starts piece `id`: the next primitives go into its mesh, with its own random stream, so a piece looks the
## same whichever order the pieces are built in.
func _begin(id: String) -> void:
	_piece = id
	_xf = Transform3D.IDENTITY
	_rng.seed = hash(id) ^ 7


func _build() -> void:
	_begin("base")
	_gate_towers()
	for c: Vector2 in [Vector2(-18, S + 16), Vector2(18, S + 16)]:   # sandbag checkpoints on the gate road
		_sandbag_ring(c.x, 0.0, c.y, 4.2, 0.0 if c.x < 0.0 else PI)
	_begin("citadel")
	_citadel()
	for i in 4:
		_begin("t%d" % i)
		_tower(TOWERS[i].x * S, TOWERS[i].y * S)
	for w: Array in WALLS:
		_begin(w[0])
		_wall_half(w, false)
	_begin("gate")
	_gate_leaves()
	_begin("store")
	for z: float in [-12.0, -5.0, 2.0]:
		_fuel_tank(30.0, z, 0.1)
	_camo_net(31.0, -5.0, 0.1)


## Damaged and broken variants of every piece, keyed "id:state" (FortDamage states).
func _build_broken() -> void:
	for i in 4:
		var x: float = TOWERS[i].x * S
		var z: float = TOWERS[i].y * S
		_begin("t%d:%d" % [i, FortDamage.DAMAGED])
		_tower(x, z, true)
		_begin("t%d:%d" % [i, FortDamage.BROKEN])
		_tower_broken(x, z)
	for w: Array in WALLS:
		_begin("%s:%d" % [w[0], FortDamage.BROKEN])
		_wall_half(w, true)
	_begin("gate:%d" % FortDamage.BROKEN)
	_gate_blown()
	_begin("store:%d" % FortDamage.BROKEN)
	_store_burnt()
	_begin("citadel:%d" % FortDamage.BROKEN)
	_citadel(true)


# ---------- layout (preview «live» state; gate in the south, +z) ----------

## Wall section `w` (WALLS row): whole, or blown through the middle (the preview's wallBreach): two shorter runs,
## stepped brick ends, plinth stumps, slabs and merlons thrown both ways, a rubble cone mostly outside.
func _wall_half(w: Array, broken: bool) -> void:
	var a: Vector2 = w[1]
	var b: Vector2 = w[2]
	var out: float = w[3]
	if not broken:
		_wall_run(a.x, a.y, b.x, b.y, out, w[4])
		return
	var len := a.distance_to(b)
	var d := (b - a) / len
	var g := minf(22.0, len * 0.55)
	var g0 := (a + b) * 0.5 - d * g * 0.5
	var g1 := (a + b) * 0.5 + d * g * 0.5
	var l0 := a.distance_to(g0)
	_wall_run(a.x, a.y, g0.x, g0.y, out, _patches_in(w[4], -(len - l0) * 0.5, l0))
	_wall_run(g1.x, g1.y, b.x, b.y, out, _patches_in(w[4], (len - l0) * 0.5, l0))
	var keep := _xf
	_xf = Transform3D(Basis(Vector3.UP, -atan2(d.y, d.x)), Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5))
	_breach(g, out)
	_xf = keep


## Patches of a whole section that fall inside a shorter run centred `shift` along it, `len` long, moved to its centre.
func _patches_in(patches: Array, shift: float, len: float) -> Array:
	var out := []
	for p: Array in patches:
		var x: float = float(p[0]) - shift
		if absf(x) + float(p[2]) * 0.5 < len * 0.5 - 1.0:
			out.append([x, p[1], p[2], p[3], p[4]])
	return out


## One wall run from a to b: battered plastered core on a stone plinth, outer parapet with rounded merlons
## and embrasures, low inner lip, beam ends on both faces, drain spouts, patches where the plaster fell off.
## `out` — which local z side faces outwards.
func _wall_run(ax: float, az: float, bx: float, bz: float, out: float, patches: Array) -> void:
	var len := Vector2(bx - ax, bz - az).length()
	var ang := atan2(bz - az, bx - ax)
	var keep := _xf
	_xf = Transform3D(Basis(Vector3.UP, -ang), Vector3((ax + bx) * 0.5, 0.0, (az + bz) * 0.5))
	_prism(M.PLASTER, PackedVector2Array([Vector2(-WT * 0.5, 0), Vector2(WT * 0.5, 0), Vector2(WT * 0.33, WH), Vector2(-WT * 0.33, WH)]), len)
	_prism(M.STONE, PackedVector2Array([Vector2(-WT * 0.5 - 0.6, 0), Vector2(WT * 0.5 + 0.6, 0), Vector2(WT * 0.5 + 0.1, 3.2), Vector2(-WT * 0.5 - 0.1, 3.2)]), len)
	var po := out * WT * 0.28
	_box(M.PLASTER, Vector3(len, 1.2, 1.2), Vector3(0, WH, po))
	_box(M.PLASTER, Vector3(len, 0.7, 0.9), Vector3(0, WH, -po))
	var x := -len * 0.5 + 2.2
	while x < len * 0.5 - 1.5:
		var mh := _rng.randf_range(1.6, 2.2)
		_box(M.PLASTER, Vector3(2.0, mh, 1.3), Vector3(x, WH + 1.2, po))
		_half_cyl(M.PLASTER, 0.65, 2.0, Vector3(x, WH + 1.2 + mh, po))
		if _rng.randf() < 0.5:
			_box(M.DARK, Vector3(0.5, 0.9, 1.4), Vector3(x + 1.7, WH + 1.6, po))   # embrasure
		x += 3.4
	x = -len * 0.5 + 3.0
	while x < len * 0.5 - 2.0:
		for s: float in [1.0, -1.0]:
			_cyl(M.WOOD, 0.32, 0.36, 1.6, 7, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, WH - 2.2, s * (WT * 0.36 + 0.5))))
		x += 3.8
	x = -len * 0.5 + 9.0
	while x < len * 0.5 - 6.0:
		_box(M.WOOD, Vector3(0.7, 0.35, 2.6), Vector3(x, WH - 0.4, out * (WT * 0.34 + 1.1)))   # drain spout
		x += 17.0
	for p: Array in patches:
		var py: float = p[1]
		var ph: float = p[3]
		var z := out * (WT * 0.5 - (py + ph * 0.5) / WH * WT * 0.17 - 0.05)
		_box(int(p[4]), Vector3(p[2], ph, 0.5), Vector3(p[0], py, z), 0.0, -out * 0.18)
	_xf = keep


## The hole of a blown wall section, `g` wide, in the section's own frame (x along, `out` z side outwards).
func _breach(g: float, out: float) -> void:
	for e: Vector2 in [Vector2(-g * 0.5, 1.0), Vector2(g * 0.5, -1.0)]:
		for k in 5:
			var hh := WH * (0.95 - k * _r(0.13, 0.24)) - (_r(0.0, 2.5) if k > 0 else 0.0)
			if hh < 1.0:
				break
			var th := WT * (0.86 - hh / WH * 0.25)
			var xx := e.x + e.y * (k * _r(0.9, 1.4) + 0.55)
			var zc := _r(-0.3, 0.3)
			_boxr(M.BRICK, Vector3(1.3, hh, th), Vector3(xx, hh * 0.5, zc), Basis(Vector3.UP, _r(-0.06, 0.06)) * Basis(Vector3.RIGHT, _r(-0.05, 0.05)))
			var sh := hh * _r(0.75, 0.95)
			_boxr(M.PLASTER, Vector3(1.35, sh, 0.45), Vector3(xx, sh * 0.5, out * (th * 0.5 + 0.12)), Basis.IDENTITY)   # plaster skin peeled short of the top
			for j in 4:   # loose bricks on the broken top
				_boxr(M.RUB_BRICK, Vector3(0.62, 0.3, 0.3), Vector3(xx + _r(-0.5, 0.5), hh + 0.15, _r(-th * 0.5, th * 0.5)), _tumble(0.4))
			if _rng.randf() < 0.7:
				var dir := Vector3(0, 0, out if e.y > 0.0 else -out).rotated(Vector3.UP, _r(-0.6, 0.6))
				_beam(Vector3(xx + e.y * 0.4, hh - 0.6, zc + _r(-1.0, 1.0)), _r(2.0, 3.6), dir, _r(-0.3, 0.6))
	var x := -g * 0.5 + 0.6
	while x < g * 0.5 - 0.6:   # plinth stumps
		var sh := _r(0.5, 2.2)
		_boxr(M.STONE, Vector3(1.4, sh, WT + 0.6), Vector3(x, sh * 0.5, 0), Basis(Vector3.UP, _r(-0.1, 0.1)))
		x += 1.4
	for i in 6:   # big slabs thrown outwards and inwards
		var sz := out * _r(5.0, 13.0) * (1.0 if i < 4 else -1.0)
		_boxr(M.PLASTER if _rng.randf() < 0.7 else M.BRICK, Vector3(_r(3.0, 5.0), _r(0.8, 1.3), _r(4.0, 7.0)), Vector3(_r(-8.0, 8.0), 0.3, sz), _tumble(0.35))
	for i in 6:   # fallen merlons
		_boxr(M.PLASTER, Vector3(2.0, 1.9, 1.3), Vector3(_r(-10.0, 10.0), 0.6, out * _r(-6.0, 14.0)), _tumble(1.0))
	_rubble(Vector3(0, 0, out * 3.0), 150, 11.0, 2.4)
	_rubble(Vector3(0, 0, -out * 2.0), 70, 8.0, 2.0)
	_rubble(Vector3(0, 3.0, 0), 30, 4.0, 1.6)


## Round corner tower: tapering plastered shaft on a stone ring, machicolation ring on wooden corbels,
## crenels, two rows of loopholes; a concrete pad with a sandbag nest on top for the launcher.
## `worn` (FortDamage.DAMAGED, the launcher at half HP): the crown and corbels on the outer side are knocked off
## and lie at the foot with a rubble cone; snapped beams stick out of the crown; the pad still holds the launcher.
func _tower(x: float, z: float, worn := false) -> void:
	var r := TOWER_R
	var h := TOWER_H
	var out := atan2(z, x)
	_cyl(M.PLASTER, r * 0.84, r, h, 40, _at(x, 0.0, z))
	_cyl(M.STONE, r + 0.5, r + 0.7, 3.4, 40, _at(x, 0.0, z))
	_cyl(M.PLASTER, r * 0.92, r * 0.86, 1.6, 40, _at(x, h - 1.4, z))
	var n := 14
	for i in n:
		var a := float(i) / n * TAU
		var ga := absf(wrapf(a - out, -PI, PI))
		if not worn or ga > 0.7:
			_box(M.WOOD, Vector3(0.8, 1.2, 0.9), Vector3(x + cos(a) * r * 0.9, h - 2.5, z + sin(a) * r * 0.9), -a)   # corbels
		if i % 2 == 0 and (not worn or ga > 1.0):
			_box(M.PLASTER, Vector3(2.6, 2.2, 1.4), Vector3(x + cos(a) * r * 0.86, h + 0.2, z + sin(a) * r * 0.86), -a + PI * 0.5)
	for i in 6:
		var a := float(i) / 6.0 * TAU + 0.3
		for yy: float in [7.0, 14.0]:
			var rr := r * (1.0 - yy / h * 0.16) - 0.05
			_box(M.DARK, Vector3(0.55, 2.4, 0.6), Vector3(x + cos(a) * rr, yy, z + sin(a) * rr), -a + PI * 0.5)
	_cyl(M.CONC, r * 0.8, r * 0.82, PAD_H, 32, _at(x, h, z))
	_sandbag_ring(x, h + PAD_H, z, r * 0.66, out + PI)
	if not worn:
		return
	var o := Vector3(cos(out), 0.0, sin(out))
	for i in 4:   # snapped corbel beams over the knocked-off arc
		var a := out + _r(-0.8, 0.8)
		_beam(Vector3(x + cos(a) * r * 0.86, h - 2.2, z + sin(a) * r * 0.86), _r(2.0, 3.4), Vector3(cos(a), 0, sin(a)), _r(-0.6, 0.3))
	for i in 5:   # crown pieces at the foot
		var a := out + _r(-0.9, 0.9)
		var d := r + _r(2.0, 9.0)
		_boxr(M.PLASTER, Vector3(2.6, 2.2, 1.4), Vector3(x + cos(a) * d, 0.7, z + sin(a) * d), _tumble(0.9))
	_rubble(Vector3(x, 0, z) + o * (r + 3.0), 50, r * 0.6, 1.6)
	_rubble(Vector3(x, h + PAD_H, z) + o * r * 0.62, 10, 1.6, 0.7)   # chips on the pad, clear of the launcher


## Crown collapsed (FortDamage.BROKEN, launcher destroyed; the preview's brokenTower): a jagged stump at ~60 %
## height, blown open towards the outside, brick core showing inside and on the gap faces, crumbling rim,
## rubble floor at half height, snapped beams, and the blast cone spilling out through the gap.
func _tower_broken(x: float, z: float) -> void:
	var r := TOWER_R
	var h := TOWER_H
	var hb := h * _r(0.55, 0.66)
	var out := atan2(z, x)
	var gap := 0.95
	var rt := r * (1.0 - hb / h * 0.16)
	_cyl(M.STONE, r + 0.5, r + 0.7, 3.4, 40, _at(x, 0.0, z))
	_shell(M.PLASTER, x, z, rt, r, hb, 0.0, out, gap, true)
	_shell(M.BRICK, x, z, rt - 1.6, r - 1.8, hb, -0.3, out, gap, false)
	var t := gap * 0.5 + 0.06
	while t < TAU - gap * 0.5 - 0.06:   # crumbling brick rim along the jagged top
		var la := out + t
		var top := hb - _jag(la, x, z, out)
		var rr := rt - 0.8 + (hb - top) / hb * 0.3
		_boxr(M.RUB_BRICK if _rng.randf() < 0.75 else M.RUB_PLASTER, Vector3(_r(1.4, 1.9), _r(0.7, 1.6), _r(1.0, 1.5)),
			Vector3(x + cos(la) * rr, top - 0.6, z + sin(la) * rr), Basis(Vector3.UP, -la + _r(-0.25, 0.25)) * _tumble(0.25))
		t += 0.13
	for sgn: float in [-1.0, 1.0]:   # stepped brick on both faces of the blown gap
		var ea := out + sgn * gap * 0.5
		var ex := x + cos(ea) * (r - 1.0)
		var ez := z + sin(ea) * (r - 1.0)
		for k in 5:
			var hh := hb * (0.52 - k * 0.09) + _r(-1.0, 1.0)
			if hh < 1.5:
				break
			var p := Vector3(ex - cos(out) * k * 0.4 + sgn * sin(out) * k * 0.9, hh * 0.5, ez - sin(out) * k * 0.4 - sgn * cos(out) * k * 0.9)
			_boxr(M.BRICK, Vector3(2.2, hh, 1.4), p, Basis(Vector3.UP, -ea + _r(-0.2, 0.2)) * Basis(Vector3.BACK, _r(-0.08, 0.08)))
	var fy := hb * 0.42
	for i in 28:   # rubble floor inside
		var a0 := float(i) / 28.0 * TAU
		var a1 := float(i + 1) / 28.0 * TAU
		var c := Vector3(x, fy, z)
		_tri(M.BRICK, c, c + Vector3(cos(a0), 0, sin(a0)) * (r - 1.9), c + Vector3(cos(a1), 0, sin(a1)) * (r - 1.9), c - Vector3(0, 1, 0))
	_rubble(Vector3(x, fy, z), 40, r * 0.7, 1.3)
	for i in 7:   # snapped corbel beams
		var a := out + _r(1.0, 5.3)
		_beam(Vector3(x + cos(a) * (rt - 0.6), hb * _r(0.55, 0.85), z + sin(a) * (rt - 0.6)), _r(2.4, 4.5), Vector3(cos(a), 0, sin(a)), _r(-0.7, 0.5))
	for i in 9:   # fallen crown pieces
		var a := out + _r(-1.3, 1.3)
		var d := r + _r(2.0, 12.0)
		_boxr(M.PLASTER, Vector3(2.6, 2.2, 1.4), Vector3(x + cos(a) * d, 0.7, z + sin(a) * d), _tumble(0.9))
	var o := Vector3(cos(out), 0.0, sin(out))
	_rubble(Vector3(x, 0, z) + o * (r + 3.0), 120, r * 1.1, 2.2)
	_rubble(Vector3(x, 2.0, z) + o * (r - 2.0), 40, r * 0.5, 1.6)


## Height bitten off the stump's top at angle `la`: a saw-tooth crown, deeper next to the blown gap at `out`.
func _jag(la: float, x: float, z: float, out: float) -> float:
	var ga := absf(wrapf(la - out, -PI, PI))
	return (sin(la * 3.0 + x) * 0.5 + 0.5) * 4.0 + (sin(la * 13.0 + z) * 0.5 + 0.5) * 2.2 + maxf(0.0, 1.2 - ga) * 7.0


## Open tapered shell of a broken tower (radius rb at the foot, rt at hb), missing the arc `gap` around `out`;
## the upper half follows _jag. `outward` — the plaster face, else the brick core seen from inside.
func _shell(m: int, x: float, z: float, rt: float, rb: float, hb: float, y0: float, out: float, gap: float, outward: bool) -> void:
	var segs := 48
	var rings := 10
	var slope := (rb - rt) / hb
	var grid := []
	var nrm := []
	for i in segs + 1:
		var la := out + gap * 0.5 + (TAU - gap) * float(i) / segs
		var drop := _jag(la, x, z, out)
		var col := []
		for j in rings + 1:
			var y := hb * float(j) / rings
			var rr := rb + (rt - rb) * y / hb
			col.append(Vector3(x + cos(la) * rr, y0 + y - drop * smoothstep(hb * 0.45, hb, y), z + sin(la) * rr))
		grid.append(col)
		nrm.append(Vector3(cos(la), slope, sin(la)).normalized() * (1.0 if outward else -1.0))
	for i in segs:
		for j in rings:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			_tri_n(m, a, b, c, nrm[i], nrm[i + 1], nrm[i + 1])
			_tri_n(m, a, c, d, nrm[i], nrm[i + 1], nrm[i])


## Gate half-towers and the deck over the passage (they stand in every state).
func _gate_towers() -> void:
	for sx: float in [-1.0, 1.0]:
		_cyl(M.PLASTER, 5.6, 6.4, 19.0, 28, _at(sx * 10.0, 0.0, S + 1.0))
		_cyl(M.STONE, 6.8, 7.0, 3.2, 28, _at(sx * 10.0, 0.0, S + 1.0))
		_box(M.PLASTER, Vector3(3, 1.6, 3), Vector3(sx * 10.0, 19.0, S + 1.0))
	_box(M.WOOD, Vector3(8.8, 0.8, 8.4), Vector3(0, 11.2, S + 1.0))


## Arched lintel and the wooden doors (the breakable gate).
func _gate_leaves() -> void:
	_box(M.PLASTER, Vector3(14, 4, 8), Vector3(0, 12, S + 1.0))
	_box(M.WOOD, Vector3(8.4, 11.6, 0.6), Vector3(0, 0, S + 3.9))


## Gate blown in: lintel cracked and sagging over a brick core, one leaf hanging off its hinge, the other flat in
## the passage, charred planks and rubble spilling out of the gate.
func _gate_blown() -> void:
	_boxr(M.PLASTER, Vector3(7.4, 4, 8), Vector3(-3.6, 14, S + 1), Basis(Vector3.BACK, -0.07))
	_boxr(M.PLASTER, Vector3(6.2, 3.6, 7.6), Vector3(4.6, 12.4, S + 1), Basis(Vector3.BACK, 0.2))
	_boxr(M.BRICK, Vector3(1.6, 3.8, 7.8), Vector3(0.9, 13.3, S + 1), Basis(Vector3.BACK, 0.12))
	_boxr(M.CHAR, Vector3(4.2, 11, 0.6), Vector3(-3.5, 5.5, S + 6.0), Basis(Vector3.UP, -0.9) * Basis(Vector3.BACK, 0.05))
	_boxr(M.CHAR, Vector3(4.2, 0.6, 11), Vector3(2.4, 0.4, S + 9), Basis(Vector3.UP, 0.25))
	for i in 9:
		_boxr(M.CHAR, Vector3(_r(1.2, 3.0), 0.3, _r(0.4, 0.7)), Vector3(_r(-7.0, 7.0), 0.3, S + _r(4.0, 16.0)), Basis(Vector3.UP, _rng.randf() * 3.0))
	_rubble(Vector3(0, 0, S + 2.0), 60, 6.0, 1.4)
	_rubble(Vector3(0, 0, S + 8.0), 40, 7.0, 1.2)


## Store went up: two soot-black tanks left, one burst and tipped onto its saddle, scattered debris.
func _store_burnt() -> void:
	_fuel_tank(30.0, -12.0, 0.1, M.SOOT)
	_fuel_tank(31.0, -4.0, 0.5, M.SOOT, 0.35, 1.2)
	_rubble(Vector3(30, 0, 1), 25, 5.0, 1.2)
	for i in 8:
		_boxr(M.SOOT, Vector3(_r(1.0, 2.6), 0.15, _r(0.6, 1.4)), Vector3(30.0 + _r(-6.0, 6.0), 0.2, -5.0 + _r(-10.0, 10.0)), _tumble(0.5))


## Citadel (two stepped blocks and the keep) and the rooms along the inner walls. `burnt` (FA-04, the fort taken):
## the upper block's roof has fallen in onto the lower roof, soot licks up from every window, beams stick out.
func _citadel(burnt := false) -> void:
	_block(-6, -16, 32, 22, 12, 0.0, burnt)
	if burnt:
		_block(-10, -18, 16, 12, 4.5, 12.8, true)
		_rubble(Vector3(-10, 17.3, -18), 45, 5.0, 1.2)
		_rubble(Vector3(-2, 12.8, -12), 25, 4.0, 1.0)
		for i in 5:
			var a := _rng.randf() * TAU
			_beam(Vector3(-10.0 + cos(a) * 5.0, 17.0, -18.0 + sin(a) * 4.0), _r(3.0, 5.0), Vector3(cos(a), 0, sin(a)), _r(-0.5, 0.4))
		# the camera looks down, so the fire shows on the roofs: char around the gutted top, soot spreading out
		_box(M.CHAR, Vector3(15.0, 0.1, 11.0), Vector3(-10, 18.1, -18))
		for i in 7:
			var m := M.CHAR if i < 3 else M.SOOT
			_box(m, Vector3(_r(4.0, 8.0), 0.1, _r(3.0, 6.0)), Vector3(_r(-20.0, 8.0), 12.8 + 0.01 * i, _r(-26.0, -6.0)), _r(0.0, PI))
	else:
		_block(-10, -18, 16, 12, 7, 12.8)
	_box(M.PLASTER, Vector3(9, 27, 9), Vector3(6, 0, -22))
	_box(M.PLASTER, Vector3(9.6, 0.8, 9.6), Vector3(6, 27, -22))
	for d: Vector2 in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]:
		_box(M.PLASTER, Vector3(1.6, 2, 1.6), Vector3(6 + d.x * 0.95, 27.8, -22 + d.y * 0.95))
	_box(M.DARK, Vector3(1.2, 3, 0.5), Vector3(6, 18, -17.4))
	_box(M.DARK, Vector3(1.2, 3, 0.5), Vector3(6, 10, -17.4))
	_block(-30, 32, 18, 9, 7)
	_block(28, -34, 22, 9, 8)
	_block(34, 18, 9, 20, 6)


## Flat-roofed adobe block: parapet with merlons on the long sides, windows and beam ends on the +z face, stone base.
## `burnt` — soot stains rising from the windows.
func _block(x: float, z: float, w: float, d: float, h: float, y0 := 0.0, burnt := false) -> void:
	_box(M.PLASTER, Vector3(w, h, d), Vector3(x, y0, z))
	_box(M.PLASTER, Vector3(w + 0.4, 0.8, d + 0.4), Vector3(x, y0 + h, z))
	var i := -w * 0.5 + 2.0
	while i < w * 0.5 - 1.0:
		_box(M.PLASTER, Vector3(1.6, 1.4, 0.9), Vector3(x + i, y0 + h + 0.8, z - d * 0.5))
		_box(M.PLASTER, Vector3(1.6, 1.4, 0.9), Vector3(x + i, y0 + h + 0.8, z + d * 0.5))
		i += 3.2
	i = -w * 0.5 + 3.0
	while i < w * 0.5 - 2.0:
		_box(M.DARK, Vector3(1.2, 2.2, 0.5), Vector3(x + i, y0 + h * 0.55, z + d * 0.5 + 0.05))
		if burnt:
			var sh := minf(h * 0.4, 4.0)
			_box(M.SOOT, Vector3(_r(1.8, 2.6), sh, 0.3), Vector3(x + i, y0 + h * 0.55 + 1.6, z + d * 0.5 + 0.12))
		_cyl(M.WOOD, 0.3, 0.3, 1.4, 6, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x + i + 1.6, y0 + h - 1.4, z + d * 0.5 + 0.5)))
		i += 4.5
	_box(M.STONE, Vector3(w, 3, d), Vector3(x, y0 - 0.01, z))


## Fuel store tank on two steel saddles; `m` OLIVE, or SOOT when burnt out; `tip` rolls it about its long axis
## and `lift` raises it (a burst tank half off its saddle).
func _fuel_tank(x: float, z: float, ry: float, m := M.OLIVE, tip := 0.0, lift := 0.0) -> void:
	var keep := _xf
	_xf = _xf * Transform3D(Basis(Vector3.UP, ry), Vector3(x, 0, z))
	var body := _xf
	_xf = body * Transform3D(Basis(Vector3.BACK, tip), Vector3(0, lift, 0))
	_cyl(m, 2.1, 2.1, 8.0, 20, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(4.0, 2.9, 0)))
	for s: float in [-1.0, 1.0]:
		_half_dome(m, 2.1, Vector3(s * 4.0, 2.9, 0), s)
	_cyl(M.STEEL if m == M.OLIVE else m, 0.5, 0.5, 0.8, 10, _at(1.0, 4.8, 0.0))
	_xf = body
	for s: float in [-1.0, 1.0]:
		_box(M.STEEL if m == M.OLIVE else m, Vector3(0.7, 2.2, 3.6), Vector3(s * 3.0, 0, 0))
	_xf = keep


## Camouflage net over the store: sags between its poles, edges hanging down to ~0.7 m over the ground.
func _camo_net(x: float, z: float, ry: float) -> void:
	var nx := 16
	var nz := 12
	var keep := _xf
	_xf = _xf * Transform3D(Basis(Vector3.UP, ry), Vector3(x, 0, z))
	var g := []
	for i in nx + 1:
		var col := []
		for j in nz + 1:
			var px := -11.0 + 22.0 * i / nx
			var pz := -8.0 + 16.0 * j / nz
			var e := minf(1.0, minf(11.0 - absf(px), 8.0 - absf(pz)) / 3.5)
			col.append(_xf * Vector3(px, 6.2 - (1.0 - e) * 5.5 + sin(px * 0.8) * cos(pz * 0.7) * 0.35, pz))
		g.append(col)
	var below := _xf * Vector3(0, -40.0, 0)
	for i in nx:
		for j in nz:
			_quad(M.NET, g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j + 1], below)
	_xf = keep


## Three courses of sandbags around a tower pad, open towards `gap_a` (the yard side).
func _sandbag_ring(x: float, y: float, z: float, r: float, gap_a: float) -> void:
	var n := roundi(r * TAU / 1.7)
	for k in 3:
		for i in n:
			var a := (i + (k % 2) * 0.5) / n * TAU
			if absf(wrapf(a - gap_a, -PI, PI)) < 0.45:
				continue
			var rr := r - k * 0.15
			var yaw := -a + PI * 0.5 + _rng.randf_range(-0.15, 0.15)
			var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, 0.62, 0.95))
			var c := Vector3(x + cos(a) * rr, y + 0.36 + k * 0.66, z + sin(a) * rr) + b * Vector3(0.95, 0, 0)   # centre the bag
			_cyl(M.BAG, 0.55, 0.55, 1.9, 8, Transform3D(b * Basis(Vector3.BACK, PI * 0.5), c))


# ---------- destruction kit (the preview's rubble, chunkGeo, beam) ----------

## Debris pile heaped in a cone around c: plaster slabs, lumpy chunks, loose bricks and splinters.
func _rubble(c: Vector3, n: int, spread: float, s: float) -> void:
	for i in n:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * spread
		var cone := 1.0 - d / spread
		var p := c + Vector3(cos(a) * d, cone * s * 1.6 * _r(0.6, 1.3), sin(a) * d)
		var t := _rng.randf()
		if t < 0.22:
			_boxr(M.RUB_PLASTER if _rng.randf() < 0.7 else M.RUB_BRICK, Vector3(_r(1.2, 2.6) * s, _r(0.35, 0.7), _r(1.0, 2.0) * s), p, _tumble(0.6))
		elif t < 0.62:
			var q := _rng.randf()
			_chunk(M.RUB_PLASTER if q < 0.5 else (M.RUB_BRICK if q < 0.8 else M.RUB_STONE), _r(0.25, 0.7) * s, p)
		elif t < 0.92:
			_boxr(M.RUB_BRICK, Vector3(0.62, 0.3, 0.3), Vector3(p.x, c.y + (p.y - c.y) * 0.7 + 0.15, p.z), _tumble(0.5))
		else:
			_boxr(M.WOOD, Vector3(_r(1.5, 3.5), 0.22, 0.32), p, _tumble(0.5))


const _ICO_F := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
	[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]


## Lumpy stone/adobe chunk of size s at p: an icosahedron bent by three sines and flattened, flat-shaded.
func _chunk(m: int, s: float, p: Vector3) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := Vector3(_r(2.0, 4.0), _r(2.0, 4.0), _r(2.0, 4.0))
	var ph := Vector3(_rng.randf() * 6.0, _rng.randf() * 6.0, _rng.randf() * 6.0)
	var fl := _r(0.5, 0.85)
	var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf() * 3.0)
	var v := []
	for q: Vector3 in raw:
		var u := q.normalized()
		var k := 1.0 + 0.22 * sin(u.x * f.x + ph.x) + 0.2 * sin(u.y * f.y + ph.y) + 0.18 * sin(u.z * f.z + ph.z)
		v.append(_xf * (p + b * (Vector3(u.x, u.y * fl, u.z) * s * k)))
	var c := _xf * p
	for fc: Array in _ICO_F:
		_tri(m, v[fc[0]], v[fc[1]], v[fc[2]], c)


## Snapped beam through c, `len` long, along the horizontal direction `dir` tilted up by `pitch`.
func _beam(c: Vector3, len: float, dir: Vector3, pitch: float) -> void:
	var ax := (dir.normalized() * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var b := Basis(Quaternion(Vector3.UP, ax))
	_cyl(M.WOOD, 0.26, 0.34, len, 7, Transform3D(b, c - ax * len * 0.5))


func _r(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


## Random yaw with a tilt of up to ±t on both horizontal axes (a piece lying where it fell).
func _tumble(t: float) -> Basis:
	return Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _r(-t, t)) * Basis(Vector3.BACK, _r(-t, t))


# ---------- primitives (preview units, through the current group transform _xf) ----------

func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## Box of size s, its base centred at p (like the preview's `box`), turned by ry about y then rx about x.
func _box(m: int, s: Vector3, p: Vector3, ry := 0.0, rx := 0.0) -> void:
	var b := Basis(Vector3.UP, ry) * Basis(Vector3.RIGHT, rx)
	_boxr(m, s, p + b * Vector3(0, s.y * 0.5, 0), b)


## Box of size s centred at c, turned by b.
func _boxr(m: int, s: Vector3, c: Vector3, b: Basis) -> void:
	var xf := _xf * Transform3D(b, c)
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for f: Array in [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3], [0, 1, 5, 4]]:
		_quad(m, xf * v[f[0]], xf * v[f[1]], xf * v[f[2]], xf * v[f[3]], xf.origin)


## Wall profile (local z across, y up) extruded along local x over len, flat-shaded, capped.
func _prism(m: int, prof: PackedVector2Array, len: float) -> void:
	var n := prof.size()
	var x0 := -len * 0.5
	var x1 := len * 0.5
	var mid := Vector2.ZERO
	for q in prof:
		mid += q / n
	var inside := _xf * Vector3(0, mid.y, mid.x)
	for i in n:
		var a := prof[i]
		var b := prof[(i + 1) % n]
		_quad(m, _xf * Vector3(x0, a.y, a.x), _xf * Vector3(x0, b.y, b.x), _xf * Vector3(x1, b.y, b.x), _xf * Vector3(x1, a.y, a.x), inside)
	for i in range(1, n - 1):
		for x: float in [x0, x1]:
			_tri(m, _xf * Vector3(x, prof[0].y, prof[0].x), _xf * Vector3(x, prof[i + 1].y, prof[i + 1].x), _xf * Vector3(x, prof[i].y, prof[i].x), inside)


## Truncated cone along local y from 0 to h (rt top, rb bottom radius), smooth sides and both caps,
## placed by xf inside the current group.
func _cyl(m: int, rt: float, rb: float, h: float, seg: int, place: Transform3D) -> void:
	var xf := _xf * place
	var slope := (rb - rt) / h
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var p := [xf * (d0 * rb), xf * (d1 * rb), xf * (d1 * rt + Vector3(0, h, 0)), xf * (d0 * rt + Vector3(0, h, 0))]
		var nn := [xf.basis * n0, xf.basis * n1, xf.basis * n1, xf.basis * n0]
		_tri_n(m, p[0], p[2], p[1], nn[0], nn[2], nn[1])
		_tri_n(m, p[0], p[3], p[2], nn[0], nn[3], nn[2])
		_tri(m, xf * Vector3(0, h, 0), xf * (d1 * rt + Vector3(0, h, 0)), xf * (d0 * rt + Vector3(0, h, 0)), xf * Vector3(0, h * 0.5, 0))
		_tri(m, xf * Vector3.ZERO, xf * (d0 * rb), xf * (d1 * rb), xf * Vector3(0, h * 0.5, 0))


## Rounded merlon cap: half cylinder of radius r along local x (length len), dome up, base at p.
func _half_cyl(m: int, r: float, len: float, p: Vector3) -> void:
	var seg := 6
	for i in seg:
		var a0 := float(i) / seg * PI
		var a1 := float(i + 1) / seg * PI
		var d0 := Vector3(0, sin(a0), cos(a0))
		var d1 := Vector3(0, sin(a1), cos(a1))
		var q := [p + d0 * r + Vector3(-len * 0.5, 0, 0), p + d1 * r + Vector3(-len * 0.5, 0, 0), p + d1 * r + Vector3(len * 0.5, 0, 0), p + d0 * r + Vector3(len * 0.5, 0, 0)]
		_tri_n(m, _xf * q[0], _xf * q[2], _xf * q[1], _xf.basis * d0, _xf.basis * d1, _xf.basis * d1)
		_tri_n(m, _xf * q[0], _xf * q[3], _xf * q[2], _xf.basis * d0, _xf.basis * d0, _xf.basis * d1)
		_tri(m, _xf * (p + Vector3(len * 0.5, 0, 0)), _xf * q[3], _xf * q[2], _xf * p)
		_tri(m, _xf * (p - Vector3(len * 0.5, 0, 0)), _xf * q[1], _xf * q[0], _xf * p)


## Tank end: a quarter-sphere-ish dome closing a horizontal cylinder of radius r at p, bulging to side s.
func _half_dome(m: int, r: float, p: Vector3, s: float) -> void:
	var seg := 16
	var rings := 4
	for j in rings:
		var b0 := float(j) / rings * PI * 0.5
		var b1 := float(j + 1) / rings * PI * 0.5
		for i in seg:
			var a0 := float(i) / seg * TAU
			var a1 := float(i + 1) / seg * TAU
			var v := [_dome(a0, b0, s), _dome(a1, b0, s), _dome(a1, b1, s), _dome(a0, b1, s)]
			var w := []
			for d: Vector3 in v:
				w.append(_xf * (p + d * r))
			var nb := _xf.basis
			_tri_n(m, w[0], w[1], w[2], nb * v[0], nb * v[1], nb * v[2])
			_tri_n(m, w[0], w[2], w[3], nb * v[0], nb * v[2], nb * v[3])


## Unit direction on the tank's end hemisphere: a around the axis, b from the rim (0) to the pole (PI/2).
func _dome(a: float, b: float, s: float) -> Vector3:
	return Vector3(s * sin(b), cos(b) * sin(a), cos(b) * cos(a))


func _quad(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	_tri(m, a, b, c, inside)
	_tri(m, a, c, d, inside)


## Flat triangle facing away from `inside` (a point inside the convex piece it bounds), so the vertex order
## written above never decides which side is lit.
func _tri(m: int, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	_tri_n(m, a, b, c, n, n, n)


## Triangle with per-vertex normals; positions already in fort space (preview units). The UV of all three
## vertices comes from the face's dominant axis (the preview's boxUV), so a face never smears its texture.
func _tri_n(m: int, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if not _st.has(_piece):
		_st[_piece] = {}
	var sts: Dictionary = _st[_piece]
	if not sts.has(m):
		var nst := SurfaceTool.new()
		nst.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[m] = nst
	var st: SurfaceTool = sts[m]
	var fn := (na + nb + nc).normalized()
	var k := 1.0 / _tile(m)
	# Godot's front faces are clockwise seen from outside: the winding's cross product points away from fn
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
		st.set_normal(v[1])
		st.set_uv(uv * k)
		st.add_vertex(p * K)


## Surface arrays of every piece built so far: piece → {material → arrays}, tangents generated.
func _arrays() -> Dictionary:
	var out := {}
	for id: String in _st:
		var sts: Dictionary = _st[id]
		var per := {}
		for m: int in sts:
			var st: SurfaceTool = sts[m]
			st.generate_tangents()
			per[m] = st.commit_to_arrays()
		out[id] = per
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
