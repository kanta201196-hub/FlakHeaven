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
## Village clutter and the market (Kanta 26.10.2026: "everything as you recommend is ok"; "put some tents in
## the centre of the kishlak to imitate a market"), built by tools/blender/village_props.py:
## [file, size (x, height, depth) in metres]. Variant index = PROP0 + row. Surfaces named vh_<class> get the class
## materials below; the rest keep their own (graded, matte) texture.
const PROPS := [
	["vc_stall", Vector3(3.86, 3.01, 3.89)],     # market stall: cloth tent on poles, crates, pots, baskets (126)
	["vc_awning", Vector3(10.24, 4.62, 4.78)],   # cloth awning on a timber frame, over a shop front (127)
	["vc_cart", Vector3(2.23, 0.77, 1.01)],      # two-wheeled wooden cart (128)
	["vc_bags", Vector3(1.82, 0.59, 1.71)],      # pile of burlap sacks (132)
	["vc_pots", Vector3(1.85, 0.69, 1.16)],      # clay pots with lids (134)
	["vc_rug", Vector3(2.48, 0.01, 1.62)],       # rug laid out on the ground (138)
	["vc_hay", Vector3(2.16, 0.85, 1.18)],       # haystack (139)
	["vc_wood", Vector3(1.53, 1.04, 1.55)],      # woodpile (140)
	["vc_trough", Vector3(3.25, 0.59, 2.31)],    # water trough and a bucket (141)
	["vc_tent_a", Vector3(3.60, 2.55, 3.20)],    # market tent, built: gabled cloth canopy over a counter
	["vc_tent_b", Vector3(3.60, 2.55, 3.20)],
	["vc_tent_c", Vector3(3.60, 2.55, 3.20)],
	["vc_tandoor", Vector3(1.50, 1.15, 1.50)],   # clay oven on a plinth, built
	["vc_rugframe", Vector3(2.90, 2.20, 0.09)],  # rugs hung on a timber frame, built
]
## A rug is 1 cm thick: at the houses' sunk base the ground swallows it, so it lies a hair above the ground
## (old units, ≈ 15 cm, unseen from above)
const RUG_LIFT := 0.0035
const PROP0 := 9
const STALL := 9
const AWNING := 10
const CART := 11
const BAGS := 12
const POTS := 13
const RUG := 14
const HAY := 15
const WOODPILE := 16
const TROUGH := 17
const TENT := 18                     ## TENT, TENT + 1, TENT + 2: the three cloth colours
const TANDOOR := 21
const RUGFRAME := 22
## Yard and square trees: the biome's tree cards (BiomeProps._lite_tree, 6 triangles) in place of the old stacked
## boxes. The cards have the full model's size, width 1 on X/Z, so a record's scale is the crown's width in old units
const ORCHARD := 23
const PALM := 24
const TREE_KINDS := {ORCHARD: "orchard", PALM: "palm"}
const DIR := "res://models/village/"
## Render budget (graphics option «props», as BiomeProps): the rug lies a centimetre off the ground, so its shadow
## is never seen on any preset; one shadow draw per village saved
const NO_SHADOW := [RUG]
## «Мало» (props 0, preset «Низкое»): yard and market clutter under ~3 m is left out. Each kind is a few pixels at
## gameplay height but one draw call per village; the tents, stalls, awnings and rug frames keep the market
const LOW_SKIP := [CART, BAGS, POTS, RUG, HAY, WOODPILE, TROUGH, TANDOOR]
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
	if TREE_KINDS.has(v):
		return Vector3(1.0, 1.4, 1.0)
	if v >= PROP0:
		return PROPS[v - PROP0][1]
	return VARIANTS[v][1]


## Add the houses of one village under its MeshInstance3D: homes are AdobeBuild records
## [variant, centre (old units), yaw, scale (x, y, z)]; one MultiMeshInstance3D per variant present.
## The «props» graphics option trims it the way BiomeProps trims the biome: on «Мало» the small clutter
## (LOW_SKIP) is not drawn and the remaining clutter, well and trees cast no shadow (as biome models there); on
## «Средне» the LOW_SKIP models and the well, a few pixels at gameplay height, cast none. Houses always cast one.
## Main thread only (loads the models). Returns the number of triangles added.
static func attach(parent: Node3D, homes: Array) -> int:
	var props := Settings.gopt("props")
	var by := {}
	for h in homes:
		var v := int(h[0])
		if props == 0 and LOW_SKIP.has(v):
			continue
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
			var o := Vector3(c.x, AdobeBuild.SINK - 0.002 + (RUG_LIFT if v == RUG else 0.0), c.y) * AdobeBuild.V_UNIT
			mm.set_instance_transform(i, Transform3D(b, o))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if NO_SHADOW.has(v) or (props == 0 and _small(v)) or (props == 1 and (LOW_SKIP.has(v) or v == WELL)):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		tris += _tris(mesh) * by[v].size()
	return tris


## Clutter, the yard well and the tree cards: the models BiomeProps would call small (no house)
static func _small(v: int) -> bool:
	return v == WELL or v >= PROP0


## Triangles the houses of a village draw (visual_bench's per-village count). Main thread only
static func tris(homes: Array) -> int:
	var n := 0
	for h in homes:
		var mesh := _mesh(int(h[0]))
		if mesh != null:
			n += _tris(mesh)
	return n


## Draw calls the models of a village add to a colour pass: one per surface of each variant present (attach makes
## one MultiMesh per variant). Main thread only
static func draws(homes: Array) -> int:
	var seen := {}
	var n := 0
	for h in homes:
		var v := int(h[0])
		if seen.has(v):
			continue
		seen[v] = true
		var mesh := _mesh(v)
		if mesh != null:
			n += mesh.get_surface_count()
	return n


static func _tris(mesh: ArrayMesh) -> int:
	var n := 0
	for si in mesh.get_surface_count():
		var ni := mesh.surface_get_array_index_len(si)
		n += (ni if ni > 0 else mesh.surface_get_array_len(si)) / 3
	return n


## Mesh of a variant with the fort's materials on its surfaces (classes by surface material name); textured props
## keep their own texture, matte; trees are the biome's tree cards
static func _mesh(v: int) -> ArrayMesh:
	if _meshes.has(v):
		return _meshes[v]
	if TREE_KINDS.has(v):
		_meshes[v] = BiomeProps.new(null)._lite_tree(TREE_KINDS[v]) as ArrayMesh
		return _meshes[v]
	var file := WELL_FILE if v == WELL else String(PROPS[v - PROP0][0] if v >= PROP0 else VARIANTS[v][0])
	var path := DIR + file + ".glb"
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
			if m is StandardMaterial3D and not m.resource_name.begins_with("vh_"):
				var t := m as StandardMaterial3D   # a prop's own texture (graded in village_props.py): matte, both sides
				t.roughness = 1.0
				t.metallic = 0.0
				t.metallic_specular = 0.2
				t.cull_mode = BaseMaterial3D.CULL_DISABLED
				if t.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					t.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					t.alpha_scissor_threshold = 0.5
				continue
			mesh.surface_set_material(si, material(m.resource_name.trim_prefix("vh_") if m != null else "plaster"))
	elif mesh != null:
		var m := mesh.surface_get_material(0) as StandardMaterial3D
		if m != null:   # the scan's pump is bright green paint: weathered toward the village's dust
			m.albedo_color = Color(0.72, 0.64, 0.54)
			m.roughness = 1.0
			m.metallic_specular = 0.2
	_meshes[v] = mesh
	return mesh


## Flat lit colours of the classes without a fort texture: openings, three faded cloths (market tents come in all
## three), terracotta, wicker and burlap
const FLAT := {
	"dark": Color(0.118, 0.102, 0.086),
	"cloth": Color(0.48, 0.4, 0.33),
	"cloth2": Color(0.36, 0.38, 0.4),     # washed-out indigo
	"cloth3": Color(0.5, 0.33, 0.28),     # faded madder
	"clay": Color(0.56, 0.4, 0.3),
	"straw": Color(0.6, 0.52, 0.37),
	"bag": Color(0.55, 0.49, 0.39),
}


## Material of a model class: the fort's texture sets for plaster, brick, stone and wood (fort shader, terms in
## metres), FLAT colours with procedural weathering (FortBuild.flat_material) for the rest
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
	else:   # procedural wear and dust over the flat colour (Kanta 26.10: no flat even paint); model units are metres
		mat = FortBuild.flat_material(FLAT.get(cls, FLAT["cloth"]), 1.0, 1.0, 0.0 if cls == "dark" else 1.0)   # no dust in the dark openings
	_mats[cls] = mat
	return mat
