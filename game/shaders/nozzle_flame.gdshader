// Jet flame at a plane's nozzle in the hangar (NozzleFlame, Kanta 25.10.2026). Unshaded light with premultiplied
// alpha: the fire adds its light and also covers part of what is behind it, so it stays orange over the bright
// sky (purely additive fire washed out to white there) and hides the cap inside the nozzle.
// Plume (disc = false): a cone mesh, mesh +Y at the nozzle. `t` runs 0 at the nozzle to 1 at the tip.
// The cone fades along t, the faces seen edge-on fade to keep the silhouette soft, and shock diamonds
// brighten a few bands. Kanta 25.10 «огонь же будет анимированным»: noise tongues run down the plume, the
// cone wobbles a little and its length breathes. Disc (disc = true): a quad in the nozzle exit, a hot glow.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/fx_exposure.gdshaderinc"

uniform bool disc = false;
uniform vec4 hot : source_color = vec4(1.0, 0.92, 0.7, 1.0);    // at the nozzle
uniform vec4 mid : source_color = vec4(1.0, 0.38, 0.06, 1.0);   // middle of the plume
uniform vec4 tail : source_color = vec4(0.55, 0.1, 0.04, 1.0);  // towards the tip
uniform float energy = 2.0;
uniform float half_len = 0.1;      // half the cone height (mesh units)
uniform float diamonds = 4.0;      // shock diamonds along the plume, 0 = none
uniform float seed = 0.0;          // flicker phase, so twin nozzles don't pulse together
uniform float cover = 0.8;         // how much of the background the fire covers at full strength

uniform float flow = 2.2;          // tongue speed down the plume, plume lengths per second

varying float t;
varying float ang;   // angle around the plume axis, 0..1

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise, wrapping every `per` cells in y so the tongues close around the cone.
float vnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float y0 = mod(i.y, per);
	float y1 = mod(i.y + 1.0, per);
	float a = hash(vec2(i.x, y0));
	float b = hash(vec2(i.x + 1.0, y0));
	float c = hash(vec2(i.x, y1));
	float d = hash(vec2(i.x + 1.0, y1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	t = clamp((half_len - VERTEX.y) / (2.0 * half_len), 0.0, 1.0);
	ang = atan(VERTEX.z, VERTEX.x) / TAU + 0.5;
	if (!disc) {
		// the far part of the plume sways and swells a little, the root stays in the nozzle
		float w = vnoise(vec2(t * 3.0 - TIME * flow * 3.0 + seed, ang * 6.0), 6.0) - 0.5;
		VERTEX.xz *= 1.0 + w * 0.5 * t;
	}
}

void fragment() {
	float flick = 0.88 + 0.08 * sin(TIME * 37.0 + seed) + 0.04 * sin(TIME * 61.0 + seed * 2.3);
	if (disc) {
		float d = length(UV - 0.5) * 2.0;
		float a = 1.0 - smoothstep(0.6, 1.0, d);
		ALBEDO = mix(hot.rgb, mid.rgb, smoothstep(0.0, 0.9, d)) * a * energy * flick * FX_EXP;
		ALPHA = a;
	} else {
		float face = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 0.8);
		vec3 c = t < 0.45 ? mix(hot.rgb, mid.rgb, t / 0.45) : mix(mid.rgb, tail.rgb, (t - 0.45) / 0.55);
		// the plume length breathes, tongues of brighter and darker fire run from the nozzle to the tip
		float reach = 1.0 + 0.08 * sin(TIME * 9.0 + seed) + 0.05 * sin(TIME * 23.0 + seed * 1.3);
		float tt = t / reach;
		float fade = pow(max(1.0 - tt, 0.0), 1.6) * smoothstep(0.0, 0.04, t + 0.02);
		float n = vnoise(vec2(t * 7.0 - TIME * flow * 7.0 + seed * 5.0, ang * 8.0), 8.0);
		n = 0.6 * n + 0.4 * vnoise(vec2(t * 15.0 - TIME * flow * 15.0, ang * 16.0 + 3.0), 16.0);
		fade *= mix(1.0, 0.15 + 1.5 * n * n, smoothstep(0.05, 0.35, t));
		float shock = 1.0;
		if (diamonds > 0.0) {
			shock += 0.6 * pow(max(0.0, sin(t * diamonds * PI)), 6.0) * (1.0 - t);
		}
		float k = face * fade * shock * flick;
		ALBEDO = c * k * energy * FX_EXP;
		ALPHA = clamp(k * cover, 0.0, 1.0);
	}
}
