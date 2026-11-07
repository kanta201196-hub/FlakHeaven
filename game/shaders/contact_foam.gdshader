shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;
#include "res://shaders/srgb.gdshaderinc"
// B2-Q08 (Kanta 07.11, close-up № 5: boats, wrecks and rocks just lay on the water): where a hull or a rock
// meets the sea — a darker band of wet hull shade right at the waterline and a torn white foam ring that
// breathes with the swell. One flat disc per object (SeaProps.FOAM), scaled to the hull's length and beam, so
// r = 1 is the disc edge and the hull covers r < ~0.7 in every direction.

varying vec3 wpos;

float h2(vec2 p) {
	uvec2 x = uvec2(ivec2(floor(p + 0.5)));
	uvec2 q = 1103515245u * ((x >> 1u) ^ x.yx);
	uint n = 1103515245u * (q.x ^ (q.y >> 3u));
	return float(n) * (1.0 / 4294967295.0);
}
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), u.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float t = TIME;
	float br = 0.04 * sin(t * 1.3 + wpos.x * 0.03 + wpos.z * 0.02);   // the ring swells with the waves
	// dark wet band hugging the hull
	float dark = smoothstep(0.62, 0.72, r) * (1.0 - smoothstep(0.78, 0.92, r + br));
	// foam: a torn ring just outside it, thin streaks fading outwards
	float n = vn(wpos.xz / 6.0 + vec2(t * 0.4, -t * 0.25)) * 0.65 + vn(wpos.xz / 2.2 - t * 0.3) * 0.35;
	float ring = smoothstep(0.7, 0.78, r + br) * (1.0 - smoothstep(0.82, 0.98, r + br * 0.5));
	float foam = ring * smoothstep(0.5, 0.75, n + (0.8 - r) * 0.8);
	foam *= 0.5 + 0.5 * smoothstep(0.3, 0.75, vn(wpos.xz / 2.5 + vec2(-t * 0.5, t * 0.35)));   // lace, not blots
	ALBEDO = mix(SRGB(vec3(0.04, 0.12, 0.13)), SRGB(vec3(0.9, 0.93, 0.92)), foam / max(foam + dark * 0.6, 1e-3));
	ALPHA = clamp(foam * 0.6 + dark * 0.15, 0.0, 1.0) * (1.0 - smoothstep(0.95, 1.0, r));
	ROUGHNESS = 0.9;
}
