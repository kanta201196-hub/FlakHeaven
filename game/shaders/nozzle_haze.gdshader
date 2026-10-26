// Heat haze behind a jet nozzle in the hangar (NozzleFlame, Kanta 25.10.2026: «ангар выставочный, должен быть
// максимально красивым»). A cone a little wider and longer than the flame bends the picture behind it with a
// rising, flowing noise: the sky and the tail shimmer in the hot exhaust. Strongest near the nozzle, gone at the
// tip and at the cone's edge-on faces, so the cone itself never shows.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float half_len = 0.1;   // half the cone height (mesh units), mesh +Y at the nozzle
uniform float strength = 0.012; // screen UV offset at the nozzle
uniform float flow = 1.6;       // ripple speed down the plume, plume lengths per second
uniform float seed = 0.0;

varying float t;
varying float ang;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise, wrapping every 12 cells in y (around the cone) so there is no seam.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float y0 = mod(i.y, 12.0);
	float y1 = mod(i.y + 1.0, 12.0);
	return mix(mix(hash(vec2(i.x, y0)), hash(vec2(i.x + 1.0, y0)), f.x), mix(hash(vec2(i.x, y1)), hash(vec2(i.x + 1.0, y1)), f.x), f.y);
}

void vertex() {
	t = clamp((half_len - VERTEX.y) / (2.0 * half_len), 0.0, 1.0);
	ang = atan(VERTEX.z, VERTEX.x) / TAU + 0.5;
}

void fragment() {
	float face = smoothstep(0.1, 0.7, abs(dot(NORMAL, VIEW)));
	float k = face * (1.0 - t) * smoothstep(0.0, 0.08, t);
	vec2 p = vec2(t * 9.0 - TIME * flow * 9.0 + seed, ang * 12.0);
	vec2 off = vec2(vnoise(p), vnoise(p + vec2(17.3, 0.0))) - 0.5;
	vec2 uv = SCREEN_UV + off * strength * k * 2.0;
	ALBEDO = textureLod(screen_tex, uv, 0.0).rgb;
	ALPHA = k;
}
