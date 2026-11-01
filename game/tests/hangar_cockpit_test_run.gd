extends Node
## Working part of hangar_cockpit_test.gd: HangarCockpit and PlaneDetail compile against the autoloads (Tuning,
## Profile through Livery), which exist only after the SceneTree starts.

const KEYS := ["fighter_1", "fighter_2", "attacker_1", "attacker_2", "bomber_1", "bomber_2"]

var _failed := 0
var _checks := 0


func _ready() -> void:
	_check(Tuning.g("hangar_light") == 0.0, "showcase light is off by default (R-22)")
	_check(PlaneDetail.enabled(), "hangar detail is on by default")
	for key: String in KEYS:
		_check(PlaneDetail.SHAPE.has(key), "%s has a panel layout" % key)
		_check(HangarCockpit.FRAMES.has(key), "%s has canopy frames" % key)
		_test_plane(key)
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_plane(key: String) -> void:
	var path := "res://models/hangar/fh_hangar_%s.glb" % key
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	var glass_box := AABB()
	var hidden := 0
	var node := HangarCockpit.attach(model, key, HangarCockpit.FRAME_DEFAULT)
	_check(node != null, "%s: cockpit built" % key)
	if node == null:
		model.free()
		return
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m != null and String(m.resource_name) == "glass":
				_check(mi.get_surface_override_material(si) != null, "%s: GLB glass hidden" % key)
				hidden += 1
	_check(hidden > 0, "%s: the model has GLB glass" % key)
	var gl := node.get_node_or_null("glass") as MeshInstance3D
	_check(gl != null and gl.mesh != null, "%s: hangar glass mesh" % key)
	if gl == null or gl.mesh == null:
		model.free()
		return
	glass_box = gl.mesh.get_aabb()
	var gm := gl.material_override as ShaderMaterial
	var bows: PackedFloat32Array = gm.get_shader_parameter("bows")
	for b in bows:
		_check(b >= glass_box.position.x and b <= glass_box.end.x, "%s: bow at x %.3f is on the glass" % [key, b])
	var inner := node.get_node_or_null("interior") as MeshInstance3D
	_check(inner != null, "%s: seat and panel built" % key)
	var own: bool = (HangarCockpit.FRAMES[key] as Dictionary).get("own_pit", false)
	if own:
		_check(node.get_node_or_null("tub") == null, "%s keeps its own cockpit tub" % key)
	if inner != null:
		if not own:
			_check(node.get_node_or_null("tub") != null, "%s: tub under the glass" % key)
		if inner.mesh != null:
			var ib := inner.mesh.get_aabb()
			_check(ib.end.y <= glass_box.end.y - 0.001, "%s: interior top %.4f under the glass top %.4f" % [
					key, ib.end.y, glass_box.end.y])
			_check(ib.position.x >= glass_box.position.x - 0.02 and ib.end.x <= glass_box.end.x + 0.005,
					"%s: interior within the canopy length" % key)
	model.free()
