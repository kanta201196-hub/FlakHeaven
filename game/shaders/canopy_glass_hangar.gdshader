// Hangar canopy (HangarCockpit): clear glass over the cockpit with an opaque painted frame. Battle keeps the dark
// opaque canopy_glass.gdshader; here the glass shows the seat and the panel under it. Glass: almost clear where it
// faces the camera, a mirror of the sky towards its edges (Schlick fresnel drives both the reflection and the
// opacity, as real glass does), a faint blue-grey tint and a few wiped smears. Frame: the sill along the cut edge
// (UV2.x — distance to it, from HangarCockpit), bows across at model x (`bows`) and ribs along at |z| (`ribs`),
// one pixel of antialiasing, no stairs. The sky gradient is in the shader so the reflection is the same in Forward+
// and GL Compatibility; Forward+ adds the sky radiance on top.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.10, 0.13, 0.15);
uniform vec3 frame_col : source_color = vec3(0.22, 0.23, 0.22);
uniform vec3 sky_top : source_color = vec3(0.50, 0.64, 0.82);
uniform vec3 sky_horizon : source_color = vec3(0.80, 0.84, 0.88);
uniform vec3 ground : source_color = vec3(0.10, 0.095, 0.085);
uniform float reflect_k = 0.55;
uniform float alpha_min = 0.1;    // opacity looking straight through
uniform float alpha_max = 0.88;   // opacity at grazing angles
uniform float rim_w = 0.0032;     // sill frame width, model units
uniform float bow_w = 0.0018;     // half-width of a bow or rib
uniform float bows[12];
uniform int bow_count = 0;
uniform float ribs[4];
uniform int rib_count = 0;

varying vec3 mp;

float g_hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float g_noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(g_hash(i), g_hash(i + vec3(1.0, 0.0, 0.0)), u.x), mix(g_hash(i + vec3(0.0, 1.0, 0.0)), g_hash(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(g_hash(i + vec3(0.0, 0.0, 1.0)), g_hash(i + vec3(1.0, 0.0, 1.0)), u.x), mix(g_hash(i + vec3(0.0, 1.0, 1.0)), g_hash(i + vec3(1.0)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	mp = VERTEX;   // the cockpit node sits at the model root: its local axes are the model's
}

void fragment() {
	float fx = fwidth(mp.x);
	float fz = fwidth(abs(mp.z));
	float fr = fwidth(UV2.x);
	float frame = 1.0 - smoothstep(rim_w - fr, rim_w + fr, UV2.x);
	for (int i = 0; i < bow_count; i++) {
		float d = abs(mp.x - bows[i]);
		frame = max(frame, 1.0 - smoothstep(bow_w - fx, bow_w + fx, d));
	}
	for (int i = 0; i < rib_count; i++) {
		float d = abs(abs(mp.z) - ribs[i]);
		frame = max(frame, 1.0 - smoothstep(bow_w - fz, bow_w + fz, d));
	}
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	float cosv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = 0.04 + 0.96 * pow(1.0 - cosv, 5.0);
	vec3 env = r.y > 0.0 ? mix(sky_horizon, sky_top, sqrt(r.y)) : mix(sky_horizon * 0.5, ground, clamp(-r.y * 4.0, 0.0, 1.0));
	float smear = smoothstep(0.55, 0.9, g_noise(mp * vec3(60.0, 160.0, 60.0)));
	float a_glass = clamp(mix(alpha_min, alpha_max, smoothstep(0.0, 0.6, f)) + 0.05 * smear, 0.0, 1.0);
	ALBEDO = mix(tint, frame_col, frame);
	METALLIC = mix(0.0, 0.25, frame);
	SPECULAR = mix(0.7, 0.5, frame);
	ROUGHNESS = mix(0.03 + 0.12 * smear, 0.5, frame);
	EMISSION = env * (0.12 + f) * reflect_k * (1.0 - frame);
	ALPHA = mix(a_glass, 1.0, frame);
}
