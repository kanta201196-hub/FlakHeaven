class_name VillageHouses
## Highland kishlak houses from models (VIS-01, Kanta 26.10.2026: village houses from models 49, 50 and 51, model 71
## may be used too, mix them). AdobeBuild lays the village out as before and, instead of drawing a house as
## boxes, records where it stands (`AdobeBuild._home`); this class picks a model variant for each lot and draws all
## of one variant in a village with one MultiMeshInstance3D. The models (game/models/village, built by
## tools/blender/village_houses.py) carry no textures of their own: their surfaces are named by material class and
## get the fortified-area fort's texture set Г (FortBuild.SETS), so the village and the fort read as one place.
## Model units are metres, long side along X, base on y = 0, centred on the footprint.

## [file, size (x, height, depth) in metres, floors, weight]. Sizes come from village_houses.py's printout.
const VARIANTS := [
	["vh_h49", Vector3(14.01, 5.33, 11.99), 1, 0.35],   # big L-shaped house on a stone plinth, beam ends
	["vh_h50a", Vector3(8.49, 6.55, 8.08), 2, 1.0],
	["vh_h50b", Vector3(9.57, 6.52, 4.25), 2, 1.0],
	["vh_h50c", Vector3(8.51, 3.37, 8.08), 1, 1.0],
	["vh_h50d", Vector3(7.78, 3.37, 5.64), 1, 1.0],
	["vh_h50e", Vector3(8.51, 3.58, 4.26), 1, 1.0],     # arcade front
	["vh_h50f", Vector3(8.50, 6.69, 8.08), 2, 0.7],     # arcade front
	["vh_h51", Vector3(9.00, 3.48, 8.14), 1, 0.8],      # small house, open pergola and a cloth awning
]
const WELL := 8                      ## variant index of the yard well (hand pump on a slab, model 71)
const WELL_FILE := "vh_well"
const WELL_SCALE := 1.6              ## the scan is a 1.2 m slab: barely a few pixels at the game's height
const DIR := "res://models/village/"
## Fort shader terms in model metres (the fort's are in preview units of a far taller wall)
const GRIME := 1.5
const BLEACH := 2.8

static var _meshes := {}             # variant index → ArrayMesh with its surfaces' materials set (main thread only)
static var _mats := {}


## Model variant for a lot of lx × lz (any units) with `floors` floors: the closest footprint shape among the
## variants of that height, with some randomness from rng so neighbours differ. Pure: safe on worker threads.
static func pick(lx: float, lz: float, floors: int, rng: RandomNumberGenerator) -> int:
	var a := lx / maxf(lz, 0.0001)
	var best := 3
	var bs := INF
	for i in VARIANTS.size():
		var v: Array = VARIANTS[i]
		if int(v[2]) != floors:
			continue
		var s: Vector3 = v[1]
		var sc := absf(log(a / (s.x / s.z))) + rng.randf() * 0.6 / float(v[3])
		if sc < bs:
			bs = sc
			best = i
	return best


## Model size (x, height, depth) of a variant, metres
static func size(v: int) -> Vector3:
	if v == WELL:
		return Vector3(1.22, 1.31, 1.25) * WELL_SCALE
	return VARIANTS[v][1]


## Add the houses of one village under its MeshInstance3D: homes are AdobeBuild records
## [variant, centre (old units), yaw, scale (x, y, z)]; one MultiMeshInstance3D per variant present.
## Main thread only (loads the models). Returns the number of triangles added.
static func attach(parent: Node3D, homes: Array) -> int:
	var by := {}
	for h in homes:
		var v := int(h[0])
		if not by.has(v):
			by[v] = []
		by[v].append(h)
	var tris := 0
	for v: int in by:
		var mesh := _mesh(v)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = by[v].size()
		for i in by[v].size():
			var h: Array = by[v][i]
			var c: Vector2 = h[1]
			var s: Vector3 = h[3]
			if v == WELL:
				s *= WELL_SCALE
			var b := Basis(Vector3.UP, -float(h[2])) * Basis.from_scale(s * AdobeBuild.V_UNIT)
			var o := Vector3(c.x, AdobeBuild.SINK - 0.002, c.y) * AdobeBuild.V_UNIT
			mm.set_instance_transform(i, Transform3D(b, o))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		parent.add_child(mmi)
		tris += _tris(mesh) * by[v].size()
	return tris


## Triangles the houses of a village draw (visual_bench's per-village count). Main thread only
static func tris(homes: Array) -> int:
	var n := 0
	for h in homes:
		var mesh := _mesh(int(h[0]))
		if mesh != null:
			n += _tris(mesh)
	return n


static func _tris(mesh: ArrayMesh) -> int:
	var n := 0
	for si in mesh.get_surface_count():
		var ni := mesh.surface_get_array_index_len(si)
		n += (ni if ni > 0 else mesh.surface_get_array_len(si)) / 3
	return n


## Mesh of a variant with the fort's materials on its surfaces (classes by surface material name)
static func _mesh(v: int) -> ArrayMesh:
	if _meshes.has(v):
		return _meshes[v]
	var path := DIR + (WELL_FILE if v == WELL else String(VARIANTS[v][0])) + ".glb"
	var mesh: ArrayMesh = null
	if ResourceLoader.exists(path):
		var n: Node = (load(path) as PackedScene).instantiate()
		var mi := n.find_children("*", "MeshInstance3D", true, false)
		if not mi.is_empty():
			mesh = (mi[0] as MeshInstance3D).mesh as ArrayMesh
		n.free()
	if mesh != null and v != WELL:
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si)
			mesh.surface_set_material(si, material(m.resource_name.trim_prefix("vh_") if m != null else "plaster"))
	elif mesh != null:
		var m := mesh.surface_get_material(0) as StandardMaterial3D
		if m != null:   # the scan's pump is bright green paint: weathered toward the village's dust
			m.albedo_color = Color(0.72, 0.64, 0.54)
			m.roughness = 1.0
			m.metallic_specular = 0.2
	_meshes[v] = mesh
	return mesh


## Material of a model class: the fort's texture sets for plaster, brick, stone and wood (fort shader, terms in
## metres), flat lit colours for dark openings and faded cloth
static func material(cls: String) -> Material:
	if _mats.has(cls):
		return _mats[cls]
	var ids := {"plaster": FortBuild.M.PLASTER, "brick": FortBuild.M.BRICK, "stone": FortBuild.M.STONE, "wood": FortBuild.M.WOOD}
	var mat: Material
	if ids.has(cls):
		var sm := (FortBuild.material(ids[cls]) as ShaderMaterial).duplicate() as ShaderMaterial
		sm.set_shader_parameter("unit", 1.0)
		sm.set_shader_parameter("grime", GRIME if cls != "wood" else 0.01)
		sm.set_shader_parameter("bleach", BLEACH)
		sm.set_shader_parameter("roof_clean", 1.0)
		sm.set_shader_parameter("normal_depth", 0.0)   # no relief: at 40 px it adds nothing, and on the Low preset the models' tangents blew it out to white
		mat = sm
	else:
		var f := StandardMaterial3D.new()
		f.metallic_specular = 0.2
		f.roughness = 1.0
		f.albedo_color = Color(0.118, 0.102, 0.086) if cls == "dark" else Color(0.48, 0.4, 0.33)
		mat = f
	_mats[cls] = mat
	return mat
