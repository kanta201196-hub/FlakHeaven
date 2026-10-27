class_name NozzleFlame
## Jet flame at the nozzles of a hangar plane (Kanta 25.10.2026: every plane except «Кит» 1, which has
## propellers). The remeshed hangar models have rough, capped nozzles; a running engine's glow fills the
## exit and hides them. Each nozzle gets a glow disc in its exit plane, an outer orange plume and a short
## hot core with shock diamonds (shaders/nozzle_flame.gdshader), all moving: tongues run down the plume,
## it sways and its length breathes. Behind it a heat-haze cone (shaders/nozzle_haze.gdshader) shimmers the
## picture, and the hangar's glow (Hangar3D, flight background) blooms the hot core. Hangar only: in battle
## the plane's own exhaust trail (Contrails) already sits at the nozzle.

## Nozzle exits per hangar model, in model axes (nose +X, up +Y, length 1): [exit x, axis y, axis |z|, inner
## radius]. |z| > 0 means a pair, mirrored. Fighters measured from a rear depth map of the hangar GLBs (the
## cavity inside the lip). Attackers and «Кит» 2 (S13, Kanta: the «Грач» 1 flame was wider than its nozzles and
## off their axis): circle fits of the nozzle lip in cross-sections of the hangar GLBs, checked on the battle
## GLBs (same axes within 0.001): x of the lip, centre of the opening, radius of the opening inside the lip.
## The earlier values came from the nacelle radius (Livery.ENGINE_HOLES), 1.6–2× the opening.
const NOZZLES := {
	"fighter_1": [-0.47, -0.058, 0.0, 0.028],
	"fighter_2": [-0.455, -0.042, 0.0755, 0.025],
	"attacker_1": [-0.242, -0.0386, 0.0807, 0.016],
	"attacker_2": [-0.292, -0.032, 0.088, 0.0158],
	"bomber_2": [-0.274, -0.0156, 0.0702, 0.0176],
}
const PLUME_LEN := 9.0   # outer plume length, in nozzle radii
const CORE_LEN := 3.2    # hot core length, in nozzle radii
const HAZE_LEN := 11.0   # heat haze length, in nozzle radii

static var _shader: Shader
static var _haze_shader: Shader


## Adds the flames as a child of `model` (key «fighter_1» etc.). Returns null for a plane without jets.
static func attach(model: Node3D, key: String) -> Node3D:
	var n: Array = NOZZLES.get(key, [])
	if n.is_empty():
		return null
	if _shader == null:
		_shader = preload("res://shaders/nozzle_flame.gdshader")
		_haze_shader = preload("res://shaders/nozzle_haze.gdshader")
	var root := Node3D.new()
	root.name = "nozzle_flame"
	model.add_child(root)
	var x: float = n[0]
	var r: float = n[3]
	var sides: Array = [0.0] if is_zero_approx(float(n[2])) else [-float(n[2]), float(n[2])]
	for i in sides.size():
		var at := Vector3(x, n[1], sides[i])
		_disc(root, at, r, i)
		_plume(root, at, r, r * PLUME_LEN, 0.4, 4.5, 0.0, i)
		_plume(root, at, r * 0.7, r * CORE_LEN, 0.2, 5.0, 3.0, i)
		_haze(root, at, r, i)
	return root


## Glow disc a little inside the exit, facing back (−X), so the nozzle lip stays in front of it.
static func _disc(root: Node3D, at: Vector3, r: float, i: int) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mat({"disc": true, "energy": 1.5, "seed": i * 1.7})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), at + Vector3(r * 0.4, 0.0, 0.0))
	root.add_child(mi)


## Cone from the exit backwards: mesh +Y turned to +X, so the wide end sits at the nozzle.
static func _plume(root: Node3D, at: Vector3, r: float, length: float, tip: float, energy: float, diamonds: float, i: int) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * tip
	c.height = length
	c.radial_segments = 24
	c.rings = 8
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = _mat({"half_len": length * 0.5, "energy": energy, "diamonds": diamonds, "seed": i * 1.7})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), at - Vector3(length * 0.5, 0.0, 0.0))
	root.add_child(mi)


## Heat-haze cone around the plume, wider and longer, so the shimmer reaches past the visible flame.
static func _haze(root: Node3D, at: Vector3, r: float, i: int) -> void:
	var length := r * HAZE_LEN
	var c := CylinderMesh.new()
	c.top_radius = r * 1.1
	c.bottom_radius = r * 2.2
	c.height = length
	c.radial_segments = 24
	c.rings = 6
	c.cap_top = false
	c.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = _haze_shader
	m.set_shader_parameter("half_len", length * 0.5)
	m.set_shader_parameter("seed", i * 3.1)
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), at - Vector3(length * 0.5, 0.0, 0.0))
	root.add_child(mi)


static func _mat(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m
