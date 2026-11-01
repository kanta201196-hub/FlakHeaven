class_name PlaneDetail
extends RefCounted
## Hangar close-up detail of the six player planes (owner's ask 31.10: «как на рендере» — engraved panel lines and
## rivets, glossy worn paint). The hangar models come from a generator with soft textures and no panel work, so the
## detail is drawn procedurally by the livery shader (shaders/plane_detail.gdshaderinc) in model axes rather than
## baked: it stays crisp at any zoom and works the same under every livery. Livery.apply(..., detail = true) calls
## setup() for every surface it paints; only the hangar passes detail, the battle models stay as they were.
## F1 `hangar_detail` (default on) turns the layer off for comparison.

## Per plane: [fuselage axis height y, fuselage half-width (outboard of it the frame lines follow the wing sweep),
## spar sweep (tan: how far back a spar line runs per unit of |z|)]. Measured on the hangar models (cross-sections at
## x = 0.05 and the leading / trailing edges between half and 0.9 span); the deltas get a spar sweep between their
## leading and trailing edges.
const SHAPE := {
	"fighter_1": [-0.03, 0.05, 0.55],
	"fighter_2": [-0.03, 0.06, 0.35],
	"attacker_1": [-0.044, 0.05, 0.31],
	"attacker_2": [-0.034, 0.05, 0.29],
	"bomber_1": [-0.03, 0.06, 0.6],
	"bomber_2": [-0.019, 0.065, 0.55],
}
## Clear-coat strength in the hangar (pd_gloss): roughness goes towards 0.55 × itself + 0.05, so matte camouflage
## keeps a soft sheen and gloss paints get a sharp highlight; chipped metal keeps its own value
const GLOSS := 1.0


## Whether the hangar draws the detail layer (F1 `hangar_detail`)
static func enabled() -> bool:
	return Tuning.g("hangar_detail") > 0.0


## Turns the layer on in one livery ShaderMaterial of plane `key` («fighter_1» …); `xf` — the surface's transform
## into model axes (the same one Livery gives the shader as to_model).
static func setup(sm: ShaderMaterial, key: String, xf: Transform3D) -> void:
	var s: Array = SHAPE.get(key, [-0.03, 0.06, 0.4])
	# panels shrink with the plane's size more slowly than the camouflage does: a bigger plane has more panels, but
	# the full CLASS_SCALE turned the bombers' wings into graph paper
	var cls_scale := sqrt(float(Livery.CLASS_SCALE.get(key.get_slice("_", 0), 1.0)))
	sm.set_shader_parameter("detail_k", 1.0)
	sm.set_shader_parameter("pd_shape", Vector4(float(s[0]), float(s[1]), float(s[2]), cls_scale))
	sm.set_shader_parameter("pd_gloss", GLOSS)
	sm.set_shader_parameter("from_model", Projection(xf.affine_inverse()))
