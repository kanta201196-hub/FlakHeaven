class_name PlaneDecals
## Player decals on the own plane (Kanta 27.10: free placement, spec docs/superpowers/specs/2026-10-27-plane-decals-design.md).
## The plane's records (Profile.decals, or the debug samples with `--decals`) are cut out of the hull by
## `DecalMesh` and merged into one mesh with one material — one extra draw call, the same in the hangar, the title
## flight and combat, in Forward+ and GL Compatibility. The mesh hangs under the insignia node, so the
## invulnerability blink covers it. A decal laid over the fin badge hides that badge (Kanta: a personal fin badge
## may replace the class mark); the wing roundels always stay.
## Art: one mask atlas (tools/decal_atlas.py): R/G/B weights of the primary, secondary and ink paints, A coverage.

const WEAR := 0.35   ## default weathering: chips and fading of the paint
## Debug samples per plane (`--decals`), shot onto the skin by `Hull.raycast` from the side (nose, tally, number,
## fin, right side) or from above (right wing). [x, y, size] in model axes; a wing entry is [x, −z, size] (left wing
## coordinates, mirrored); the tally x is its front end.
const SAMPLE_SPOTS := {
	"fighter_1": {"nose": [0.33, -0.032, 0.03], "kills": [0.255, -0.022, 0.011], "num": [0.03, -0.035, 0.026],
		"fin": [-0.407, 0.064, 0.035], "wing": [-0.24, -0.09, 0.045]},
	"fighter_2": {"nose": [0.405, -0.036, 0.026], "kills": [0.33, -0.008, 0.01], "num": [0.02, -0.052, 0.016],
		"fin": [-0.318, 0.058, 0.03], "wing": [-0.2, -0.16, 0.05]},
	"attacker_1": {"nose": [0.365, -0.067, 0.03], "kills": [0.285, -0.03, 0.012], "num": [-0.12, -0.034, 0.022],
		"fin": [-0.42, 0.07, 0.035], "wing": [-0.15, -0.17, 0.05]},
	"attacker_2": {"nose": [0.395, -0.064, 0.03], "kills": [0.29, -0.07, 0.012], "num": [-0.18, -0.027, 0.024],
		"fin": [-0.392, 0.08, 0.04], "wing": [-0.18, -0.18, 0.05]},
	"bomber_1": {"nose": [0.38, -0.066, 0.026], "kills": [0.33, -0.053, 0.01], "num": [-0.2, -0.058, 0.03],
		"fin": [-0.404, 0.087, 0.045], "wing": [0.0, -0.12, 0.05]},
	"bomber_2": {"nose": [0.405, -0.046, 0.024], "kills": [0.36, -0.025, 0.01], "num": [0.23, -0.026, 0.016],
		"fin": [-0.378, 0.08, 0.045], "wing": [-0.12, -0.2, 0.05]},
}
## Debug sample art per class: nose, tally, number, fin, wing, wing turn (radians), primary and secondary paint
const SAMPLE_ART := {
	"fighter": ["shark_mouth", "tally_air", "07", "skull_winged", "bolt", 0.35, "bone", "red"],
	"attacker": ["rook", "tally_ground", "312", "skull_wrench", "chevrons", -0.5, "bone", "rust"],
	"bomber": ["whale", "tally_bomb", "45", "ace_card", "sun", 0.25, "sand", "teal"],
}

static var _shader: Shader
static var _flags_read := false
static var _samples := false
static var _sample_tally := 9
static var _wear := WEAR


## True when the debug flag `--decals` puts the sample decals on every own plane (read once)
static func samples_on() -> bool:
	if not _flags_read:
		_flags_read = true
		for a in OS.get_cmdline_user_args():
			if a == "--decals":
				_samples = true
			elif a.begins_with("--decaltally="):
				_sample_tally = clampi(int(a.get_slice("=", 1)), 0, DecalCatalog.TALLY_MAX)
			elif a.begins_with("--decalwear="):
				_wear = clampf(float(a.get_slice("=", 1)), 0.0, 1.0)
	return _samples


## Builds the decal mesh of the own plane `model` (key «fighter_1» and so on) under the insignia node `ins`;
## nothing when the plane has no decals. Called from Insignia.attach for the player's plane only.
static func attach(model: Node3D, key: String, ins: Node3D) -> void:
	if ins == null:
		return
	var cls := key.get_slice("_", 0)
	var lvl := int(key.get_slice("_", 1))
	var hull: DecalMesh.Hull = null
	var records: Array[DecalRecord] = []
	var tally := 0
	var t0 := Time.get_ticks_usec()
	if samples_on():
		hull = DecalMesh.hull_of(model)
		if hull != null:
			records = samples(hull, key)
		tally = _sample_tally
	else:
		records = Profile.decals(cls, lvl)
		if records.is_empty():
			return
		hull = DecalMesh.hull_of(model)
		tally = tally_count()
	if hull == null or records.is_empty():
		return
	var mesh := DecalMesh.build(hull, records, tally)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "decals"
	mi.mesh = mesh
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ins.add_child(mi)
	_hide_covered_badges(ins, records)
	if _samples:
		print("DECALS %s: %d decals, %d triangles, hull %d triangles, %.1f ms" % [key, records.size(),
			int(mesh.surface_get_array_len(0) / 3.0), int(hull.pos.size() / 3.0), (Time.get_ticks_usec() - t0) / 1000.0])


## Kill tally marks (Kanta 27.10, option A): rival aces and «Крепости» downed, lifetime (medal counters)
static func tally_count() -> int:
	var mc: Dictionary = Profile.medal_counters()
	return int(mc.get("aces", 0)) + int(mc.get("fortresses", 0))


## The debug sample decals of plane `key`, placed by rays on its hull (a missed ray drops that decal)
static func samples(hull: DecalMesh.Hull, key: String) -> Array[DecalRecord]:
	var out: Array[DecalRecord] = []
	var spots: Dictionary = SAMPLE_SPOTS.get(key, {})
	var art: Array = SAMPLE_ART.get(key.get_slice("_", 0), [])
	if spots.is_empty() or art.is_empty():
		return out
	for side: float in [-1.0, 1.0]:   # −Z — left side, +Z — right side
		var nose: Array = spots["nose"]
		_place(out, hull, String(art[0]), Vector3(nose[0], nose[1], side), side, nose[2], 0.0, side > 0.0, art, "")
		var num: Array = spots["num"]
		_place(out, hull, DecalCatalog.NUMBER, Vector3(num[0], num[1], side), side, num[2], 0.0, false, art, String(art[2]))
		var k: Array = spots["kills"]
		_place(out, hull, String(art[1]), Vector3(k[0], k[1], side), side, k[2], 0.0, side > 0.0, art, "")
	var fin: Array = spots["fin"]
	_place(out, hull, String(art[3]), Vector3(fin[0], fin[1], 1.0), 1.0, fin[2], 0.0, false, art, "")
	var wing: Array = spots["wing"]   # the right wing (+Z): the lit side in the hangar
	var hit := hull.raycast(Vector3(wing[0], 1.0, -float(wing[1])), Vector3.DOWN)
	if hit.size() == 2:
		DecalLoadout.add(out, _record(String(art[4]), hit, wing[2], float(art[5]), false, art, ""))
	return out


static func _place(out: Array[DecalRecord], hull: DecalMesh.Hull, id: String, origin: Vector3, side: float,
		size: float, angle: float, mirror: bool, art: Array, text: String) -> void:
	var hit := hull.raycast(origin, Vector3(0.0, 0.0, -side))
	if hit.size() == 2:
		DecalLoadout.add(out, _record(id, hit, size, angle, mirror, art, text))


static func _record(id: String, hit: Array, size: float, angle: float, mirror: bool, art: Array, text: String) -> DecalRecord:
	var r := DecalRecord.new()
	r.id = id
	r.pos = hit[0]
	r.normal = hit[1]
	r.size = size
	r.angle = angle
	r.mirror = mirror
	r.c1 = String(art[6])
	r.c2 = String(art[7])
	r.text = text
	return r


## Fin and side insignia under a decal are hidden (the wing roundels never are)
static func _hide_covered_badges(ins: Node3D, records: Array[DecalRecord]) -> void:
	for c in ins.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var n := String(mi.name) if not String(mi.name).begins_with("Mesh") else String(mi.get_parent().name)
		if not (n.begins_with("fin") or n.begins_with("side")) or mi.mesh == null:
			continue
		var centre := DecalMesh.rel_transform(mi, ins) * mi.mesh.get_aabb().get_center()
		for r in records:
			if r.pos.distance_to(centre) < maxf(r.size * 0.6, 0.02):
				mi.visible = false


## The decal material (one per plane; the shader is shared)
static func material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("atlas", load(DecalCatalog.ATLAS_PATH))
	var pal := PackedVector3Array()
	for col in DecalCatalog.palette():
		pal.append(Vector3(col.r, col.g, col.b))
	while pal.size() < 16:   # the shader's array is fixed at 16
		pal.append(Vector3.ZERO)
	m.set_shader_parameter("palette", pal)
	m.set_shader_parameter("ink", DecalCatalog.palette().size() - 1)
	m.set_shader_parameter("wear", _wear)
	return m


const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/srgb.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 palette[16];   // DecalCatalog paints (sRGB), then the ink
uniform int ink = 12;
uniform float wear = 0.35;  // 0 — fresh, 1 — chipped and faded

varying vec3 lp;
varying flat vec2 paint;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	lp = VERTEX;
	paint = UV2;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	vec3 w = t.rgb / max(t.r + t.g + t.b, 1e-3);
	vec3 col = w.r * SRGB(palette[int(paint.x + 0.5)]) + w.g * SRGB(palette[int(paint.y + 0.5)]) + w.b * SRGB(palette[ink]);
	// weathering in model space (does not swim with the projection): chips show the paint below, the rest fades
	// towards a dusty grey and gets grime blotches
	float chip = vnoise3(lp * 900.0) * 0.6 + vnoise3(lp * 260.0) * 0.4;
	float cover = t.a * step(wear * 0.42, chip);
	float grime = vnoise3(lp * 120.0 + 3.7);
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(l) * vec3(1.02, 0.98, 0.9), 0.25 * wear);
	col *= 1.0 - 0.18 * wear * smoothstep(0.45, 0.8, grime);
	ALBEDO = col;
	ROUGHNESS = 0.82 + 0.1 * grime;
	METALLIC = 0.0;
	ALPHA = cover;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
