// Weathered plain paint for the procedural models that have no texture of their own (Kanta 2026-10-26: no model
// ships with flat, even paint): the fort's dark, olive, steel and charred parts (FortBuild) and the village's
// cloth, clay, straw and burlap (VillageHouses). These meshes are built in GDScript, so there is nothing to bake
// into: the detail is procedural in mesh space instead — large soft tone patches and fine mottling, dust on
// upward faces and along the lowest metre, faint rain streaks down the walls, light scuffs, and roughness that
// varies with all of them. Matte throughout. Heights and sizes are in metres (`unit` metres per mesh unit), so
// the look does not depend on a piece's scale. The base colour is a `source_color` uniform (the same sRGB colour
// the plain StandardMaterial3D had); the dust constant goes through SRGB().
shader_type spatial;
render_mode cull_back;

#include "res://shaders/srgb.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness = 0.95;
uniform float specular = 0.2;
uniform float unit = 1.0;     // metres per mesh unit
uniform float dust = 1.0;     // how much valley dust settles (0 — none)

varying vec3 fp;
varying vec3 fn;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	fp = VERTEX * unit;
	fn = NORMAL;
}

void fragment() {
	vec3 c = albedo.rgb;
	float big = vnoise(fp * 0.35) * 0.65 + vnoise(fp * 0.9) * 0.35;
	float fine = vnoise(fp * 4.0) * 0.6 + vnoise(fp * 11.0) * 0.4;
	c *= mix(0.84, 1.08, big);
	c *= 0.93 + 0.14 * fine;
	vec3 dust_c = SRGB(vec3(0.66, 0.58, 0.46));
	float d_up = smoothstep(0.35, 0.95, fn.y) * (0.18 + 0.32 * vnoise(fp * 1.7));
	float d_low = (1.0 - smoothstep(0.0, 1.1, fp.y)) * 0.3 * (0.6 + 0.4 * fine);
	float d = clamp((d_up + d_low) * dust, 0.0, 0.6);
	c = mix(c, dust_c, d);
	float wall = 1.0 - abs(fn.y);
	float st = vnoise(vec3(fp.x * 6.0, fp.y * 0.4, fp.z * 6.0));
	c *= 1.0 - smoothstep(0.6, 0.85, st) * wall * 0.14;
	float scuff = smoothstep(0.78, 0.86, vnoise(fp * 7.0 + vec3(5.3)));
	c = mix(c, c * 1.18 + vec3(0.015), scuff * 0.5);
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness + 0.08 * (fine - 0.5) + 0.06 * d, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = specular;
}
