class_name NozzleFlame
## Jet flame at the nozzles of a hangar plane (Kanta 25.10.2026: every plane except «Кит» 1, which has
## propellers). The remeshed hangar models have rough, capped nozzles; a running engine's glow fills the
## exit and hides them. Each nozzle gets a glow disc in its exit plane, an outer orange plume and a short
## hot core with shock diamonds (shaders/nozzle_flame.gdshader). Hangar only: in battle the plane's own
## exhaust trail (Contrails) already sits at the nozzle.

## Nozzle exits per hangar model, in model axes (nose +X, up +Y, length 1): [exit x, axis y, axis |z|, inner
## radius]. |z| > 0 means a pair, mirrored. Fighters measured from a rear depth map of the hangar GLBs (the
## cavity inside the lip); attackers and «Кит» 2 match Livery.ENGINE_HOLES (nozzle x0, slightly inside r).
const NOZZLES := {
	"fighter_1": [-0.47, -0.058, 0.0, 0.028],
	"fighter_2": [-0.455, -0.042, 0.0755, 0.025],
	"attacker_1": [-0.255, -0.0387, 0.0884, 0.03],
	"attacker_2": [-0.305, -0.0293, 0.0919, 0.036],
	"bomber_2": [-0.285, -0.0144, 0.0702, 0.027],
}
const PLUME_LEN := 7.0   # outer plume length, in nozzle radii
const CORE_LEN := 3.2    # hot core length, in nozzle radii

static var _shader: Shader


## Adds the flames as a child of `model` (key «fighter_1» etc.). Returns null for a plane without jets.
static func attach(model: Node3D, key: String) -> Node3D:
	var n: Array = NOZZLES.get(key, [])
	if n.is_empty():
		return null
	if _shader == null:
		_shader = preload("res://shaders/nozzle_flame.gdshader")
	var root := Node3D.new()
	root.name = "nozzle_flame"
	model.add_child(root)
	var x: float = n[0]
	var r: float = n[3]
	var sides: Array = [0.0] if is_zero_approx(float(n[2])) else [-float(n[2]), float(n[2])]
	for i in sides.size():
		var at := Vector3(x, n[1], sides[i])
		_disc(root, at, r, i)
		_plume(root, at, r, r * PLUME_LEN, 0.35, 2.4, 0.0, i)
		_plume(root, at, r * 0.7, r * CORE_LEN, 0.15, 4.0, 3.0, i)
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


static func _mat(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m
