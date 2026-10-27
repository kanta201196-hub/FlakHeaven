class_name PlaneDecals
## Player decals on the own plane: nose art, side number, kill tally and a personal fin badge (prototype
## behind the debug flag `--decals`, spec docs/superpowers/specs/2026-10-27-plane-decals-design.md).
## Slots are sticker meshes shot onto the airframe offline (tools/blender/decal_slots.py →
## models/mech/fh_dec_<class>_<lvl>.glb), so every decal follows the skin's shape like the insignia do.
## Art is one mask atlas (tools/decal_atlas.py → art/decals/decal_atlas.png): R/G/B are the weights of the
## primary, secondary and ink paints, A the coverage; one small shader tints, fits, repeats (digits, tally)
## and weathers it. Works in Forward+ and GL Compatibility (no Decal nodes, which Compatibility lacks).
## Nothing is saved yet: the demo loadouts below stand in for the profile until Kanta approves the design.

const ATLAS_COLS := 8
const ATLAS_ROWS := 4
const DIGIT0 := 16   ## atlas cell of «0»; «1»…«9» follow
## Debug loadouts per class: [nose cell, nose width in cells, fin cell, number, tally cell, tally count,
## primary, secondary, ink]. `--decalset=2` picks the second row
const DEMO := {
	"fighter": [
		[12, 2, 0, "07", 26, 9, Color(0.87, 0.83, 0.72), Color(0.72, 0.16, 0.10), Color(0.06, 0.06, 0.07)],
		[14, 1, 3, "21", 26, 4, Color(0.90, 0.88, 0.80), Color(0.87, 0.56, 0.13), Color(0.06, 0.06, 0.07)],
	],
	"attacker": [
		[9, 1, 1, "312", 27, 7, Color(0.85, 0.80, 0.66), Color(0.75, 0.33, 0.14), Color(0.06, 0.06, 0.06)],
		[12, 2, 6, "58", 27, 12, Color(0.88, 0.85, 0.76), Color(0.70, 0.13, 0.10), Color(0.06, 0.06, 0.06)],
	],
	"bomber": [
		[10, 1, 4, "45", 28, 12, Color(0.86, 0.82, 0.70), Color(0.25, 0.48, 0.52), Color(0.07, 0.07, 0.08)],
		[5, 1, 2, "104", 28, 18, Color(0.88, 0.84, 0.72), Color(0.78, 0.30, 0.12), Color(0.07, 0.07, 0.08)],
	],
}

static var _on := -1     # -1 — flags not read yet
static var _set := 0
static var _wear := 0.35
static var _shader: Shader
static var _atlas: Texture2D
static var _scenes := {}


## True when the debug flag `--decals` is on (read once)
static func enabled() -> bool:
	if _on < 0:
		_on = 0
		for a in OS.get_cmdline_user_args():
			if a == "--decals":
				_on = 1
			elif a.begins_with("--decalset="):
				_set = clampi(int(a.get_slice("=", 1)) - 1, 0, 1)
			elif a.begins_with("--decalwear="):
				_wear = clampf(float(a.get_slice("=", 1)), 0.0, 1.0)
	return _on == 1


## Puts the demo loadout of the class on the model: slot stickers under `ins` (so insignia blinking covers
## them) and the personal badge on the insignia's fin stickers. key — «fighter_1» and so on
static func attach(model: Node3D, key: String, ins: Node3D) -> void:
	var cls := key.get_slice("_", 0)
	if not DEMO.has(cls) or ins == null:
		return
	var lo: Array = (DEMO[cls] as Array)[_set]
	var path := "res://models/mech/fh_dec_%s.glb" % key
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return
	var dec: Node3D = (_scenes[path] as PackedScene).instantiate()
	dec.name = "decals"
	ins.add_child(dec)   # both GLBs are in model axes and the insignia root has no transform of its own
	for c in dec.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var n := String(mi.name)
		if not (n.begins_with("nose") or n.begins_with("kills") or n.begins_with("num")):
			n = String(mi.get_parent().name)
		var right := n.ends_with("_r")
		var asp := _aspect(mi)
		var m: ShaderMaterial
		if n.begins_with("nose"):
			m = _material(0, int(lo[0]), int(lo[1]), asp, right, lo)
		elif n.begins_with("num"):
			m = _material(1, DIGIT0, 1, asp, false, lo)
			var s := String(lo[3])
			m.set_shader_parameter("digit_count", s.length())
			m.set_shader_parameter("digits", Vector3(s.unicode_at(0) - 48, s.unicode_at(mini(1, s.length() - 1)) - 48,
					s.unicode_at(mini(2, s.length() - 1)) - 48))
		else:
			m = _material(2, int(lo[4]), 1, asp, right, lo)   # the row starts at the nose on both sides
			m.set_shader_parameter("tally_count", int(lo[5]))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# personal fin badge instead of the class mark
	for c in ins.find_children("fin*", "", true, false):
		for mi2 in ([c] if c is MeshInstance3D else c.find_children("*", "MeshInstance3D", true, false)):
			(mi2 as MeshInstance3D).material_override = _material(0, int(lo[2]), 1, 1.0, false, lo)


## Width / height of a slot sticker in its own plane (side stickers lie along model X and Y)
static func _aspect(mi: MeshInstance3D) -> float:
	var bb := mi.mesh.get_aabb()
	return maxf(bb.size.x, 0.001) / maxf(bb.size.y, 0.001)


## One slot's material: mode 0 picture, 1 digits, 2 tally row; cell — atlas cell index, cells_w — picture
## width in cells, aspect — sticker width / height, flip — mirror directional art on the right side
static func _material(mode: int, cell: int, cells_w: int, aspect: float, flip: bool, lo: Array) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
		_atlas = load("res://art/decals/decal_atlas.png")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("atlas", _atlas)
	m.set_shader_parameter("mode", mode)
	var col := cell % ATLAS_COLS
	var row := floori(cell / float(ATLAS_COLS))
	m.set_shader_parameter("cell", Vector4(float(col) / ATLAS_COLS, float(row) / ATLAS_ROWS,
			float(cells_w) / ATLAS_COLS, 1.0 / ATLAS_ROWS))
	m.set_shader_parameter("content_aspect", float(cells_w))
	m.set_shader_parameter("slot_aspect", aspect)
	m.set_shader_parameter("flip_u", flip)
	m.set_shader_parameter("c_prim", lo[6])
	m.set_shader_parameter("c_sec", lo[7])
	m.set_shader_parameter("c_ink", lo[8])
	m.set_shader_parameter("wear", _wear)
	return m


const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int mode = 0;               // 0 — one picture, 1 — digits, 2 — tally row
uniform vec4 cell = vec4(0.0, 0.0, 0.125, 0.25);   // atlas rect of the picture (first digit for mode 1)
uniform float content_aspect = 1.0; // picture width / height in cells
uniform float slot_aspect = 1.0;    // sticker width / height on the skin
uniform bool flip_u = false;        // directional art (shark mouth) faces the nose on both sides
uniform int digit_count = 2;
uniform vec3 digits = vec3(0.0);
uniform int tally_count = 0;
uniform vec3 c_prim : source_color = vec3(0.87, 0.83, 0.72);
uniform vec3 c_sec : source_color = vec3(0.72, 0.16, 0.10);
uniform vec3 c_ink : source_color = vec3(0.06);
uniform float wear = 0.35;          // 0 — fresh, 1 — chipped and faded

varying vec3 lp;

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
}

// slot UV → content UV (letterboxed to keep the picture's proportions); x < 0 or > 1 — outside
vec2 fit(vec2 uv, float asp) {
	if (slot_aspect > asp) {
		float w = asp / slot_aspect;
		return vec2((uv.x - 0.5) / w + 0.5, uv.y);
	}
	float h = slot_aspect / asp;
	return vec2(uv.x, (uv.y - 0.5) / h + 0.5);
}

void fragment() {
	vec2 uv = UV;
	if (flip_u) uv.x = 1.0 - uv.x;
	vec2 a_uv;
	vec2 g;   // continuous atlas coordinate for mip selection (fract() in digits and tally makes seams)
	bool inside = true;
	if (mode == 1) {
		// digits: each takes 0.62 of a cell's width (the glyphs are narrow)
		vec2 c = fit(uv, 0.62 * float(digit_count));
		float k = clamp(floor(c.x * float(digit_count)), 0.0, float(digit_count - 1));
		float d = k < 0.5 ? digits.x : (k < 1.5 ? digits.y : digits.z);
		float idx = 16.0 + d;
		vec2 org = vec2(mod(idx, 8.0) * 0.125, floor(idx / 8.0) * 0.25);
		float lx = fract(c.x * float(digit_count));
		a_uv = org + vec2(0.19 + lx * 0.62, c.y) * vec2(0.125, 0.25);
		g = c * vec2(0.62 * float(digit_count) * 0.125, 0.25);
		inside = c.x >= 0.0 && c.x <= 1.0 && c.y >= 0.0 && c.y <= 1.0;
	} else if (mode == 2) {
		// tally: square marks from the start of the row, as many as the player has earned; a second,
		// smaller row when one row is full
		float per = max(floor(slot_aspect * 1.1), 1.0);
		float rows = float(tally_count) > per ? 2.0 : 1.0;
		per = max(floor(slot_aspect * 1.1 * rows), 1.0);
		float r = min(floor(uv.y * rows), rows - 1.0);
		float k = floor(uv.x * slot_aspect * 1.1 * rows) + r * per;
		vec2 l = vec2(fract(uv.x * slot_aspect * 1.1 * rows), fract(uv.y * rows));
		a_uv = cell.xy + l * cell.zw;
		g = vec2(uv.x * slot_aspect * 1.1, uv.y) * rows * cell.zw;
		inside = k < float(tally_count) && k < per * rows;
	} else {
		vec2 c = fit(uv, content_aspect);
		a_uv = cell.xy + c * cell.zw;
		g = c * cell.zw;
		inside = c.x >= 0.0 && c.x <= 1.0 && c.y >= 0.0 && c.y <= 1.0;
	}
	vec4 t = textureGrad(atlas, a_uv, dFdx(g), dFdy(g));
	float cover = inside ? t.a : 0.0;
	vec3 w = t.rgb / max(t.r + t.g + t.b, 1e-3);
	vec3 col = w.r * c_prim + w.g * c_sec + w.b * c_ink;
	// weathering in model space, so it does not swim with the UV stretch: chips show the paint below,
	// the rest fades towards a dusty grey and gets grime blotches
	float chip = vnoise3(lp * 900.0) * 0.6 + vnoise3(lp * 260.0) * 0.4;
	cover *= step(wear * 0.42, chip);
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
