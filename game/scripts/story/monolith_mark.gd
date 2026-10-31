class_name MonolithMark
## ST-09, story plan step 10: the Monolith company mark on enemy hardware — one plain grey slab laid on the top of
## the model (the storyline, §9: «no colours, no eagles, no letters»), so «they are one company» reads from the air
## on the Fortress, the AA sites and the convoy vehicles. Built in code from the model's own bounds: no texture, no
## extra GLB, two quads per unit, shared materials. Behind the F1 switch `story_mark` until Kanta's «ok» (R-22).
##
## The slab is a tall-narrow rectangle along the model's long axis, its length a fixed share of the model's length,
## on a slightly larger near-black base so the grey stays visible on light hulls and in dusk light.

## Enemy sprite names (art/enemies/<name>.png) that carry the mark, with the slab's centre in the model's axes
## (x, z; the model is 1 unit long, 1 = the sprite's width) and its length as a share of that unit; the width is
## WIDTH_K of the length. The Fortress is a flying wing: its 1 unit is the span (z), the body runs along x, and the
## slab sits on the body behind the dome, clear of the hull panels that fold open in phase 3 (Render3D._fortress_parts).
const MARKED := {"e_fortress": [-0.10, 0.0, 0.07], "e_zsu": [0.0, 0.0, 0.22], "e_sam": [0.0, 0.0, 0.22],
	"e_radar": [0.0, 0.0, 0.22], "e_lev_zsu": [0.0, 0.0, 0.22], "e_lev_radar": [0.0, 0.0, 0.22],
	"e_convoy_technical": [0.0, 0.0, 0.22], "e_convoy_pickup_tent": [0.0, 0.0, 0.22], "e_convoy_scout": [0.0, 0.0, 0.22]}
const WIDTH_K := 0.44     ## slab width to its length
const BASE_PAD := 0.08    ## the dark base sticks out this share of the slab's length on every side
const LIFT := 0.004       ## above the model's top, so the slab does not z-fight with the hull

static var _slab_mat: StandardMaterial3D
static var _base_mat: StandardMaterial3D


## Attaches the mark to `model` (the battle GLB instance, axes of the model) when `key` is in MARKED; the node
## added, or null. Call after the hull mesh is chosen: the slab is a MeshInstance3D too.
static func attach(model: Node3D, key: String) -> Node3D:
	if not MARKED.has(key):
		return null
	var box := _bounds(model)
	if box.size == Vector3.ZERO:
		return null
	var spec: Array = MARKED[key]
	var length := float(spec[2])
	var mark := Node3D.new()
	mark.name = "monolith_mark"
	mark.position = Vector3(float(spec[0]), box.end.y + LIFT, float(spec[1]))
	mark.add_child(_quad(length * (1.0 + 2.0 * BASE_PAD), length * (WIDTH_K + 2.0 * BASE_PAD), _base()))
	var slab := _quad(length, length * WIDTH_K, _slab())
	slab.position.y = LIFT * 0.5
	mark.add_child(slab)
	model.add_child(mark)
	return mark


## Bounds of every mesh under `model`, in the model's own axes (the GLB nodes carry their own transforms).
static func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != model:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _quad(len: float, wid: float, mat: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(len, wid)
	pm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _slab() -> StandardMaterial3D:
	if _slab_mat == null:
		_slab_mat = StandardMaterial3D.new()
		_slab_mat.albedo_color = Color(0.30, 0.31, 0.33)
		_slab_mat.roughness = 0.9
		_slab_mat.metallic = 0.0
	return _slab_mat


static func _base() -> StandardMaterial3D:
	if _base_mat == null:
		_base_mat = StandardMaterial3D.new()
		_base_mat.albedo_color = Color(0.05, 0.05, 0.06)
		_base_mat.roughness = 1.0
		_base_mat.metallic = 0.0
	return _base_mat
