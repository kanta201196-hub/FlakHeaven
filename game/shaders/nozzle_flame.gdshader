// Jet flame at a plane's nozzle in the hangar (NozzleFlame, Kanta 25.10.2026). Additive and unshaded, so it
// reads as light over the dark nozzle and also hides the cap inside it.
// Plume (disc = false): a cone mesh, mesh +Y at the nozzle. `t` runs 0 at the nozzle to 1 at the tip.
// The cone fades along t, the faces seen edge-on fade to keep the silhouette soft, and shock diamonds
// brighten a few bands. Disc (disc = true): a quad in the nozzle exit, a hot glow fading to its rim.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://shaders/fx_exposure.gdshaderinc"

uniform bool disc = false;
uniform vec4 hot : source_color = vec4(1.0, 0.92, 0.7, 1.0);    // at the nozzle
uniform vec4 mid : source_color = vec4(1.0, 0.45, 0.12, 1.0);   // middle of the plume
uniform vec4 tail : source_color = vec4(0.55, 0.1, 0.04, 1.0);  // towards the tip
uniform float energy = 2.0;
uniform float half_len = 0.1;      // half the cone height (mesh units)
uniform float diamonds = 4.0;      // shock diamonds along the plume, 0 = none
uniform float seed = 0.0;          // flicker phase, so twin nozzles don't pulse together

varying float t;

void vertex() {
	t = clamp((half_len - VERTEX.y) / (2.0 * half_len), 0.0, 1.0);
}

void fragment() {
	float flick = 0.88 + 0.08 * sin(TIME * 37.0 + seed) + 0.04 * sin(TIME * 61.0 + seed * 2.3);
	if (disc) {
		float d = length(UV - 0.5) * 2.0;
		float a = 1.0 - smoothstep(0.6, 1.0, d);
		ALBEDO = mix(hot.rgb, mid.rgb, smoothstep(0.0, 0.9, d)) * a * energy * flick * FX_EXP;
	} else {
		float face = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
		vec3 c = t < 0.45 ? mix(hot.rgb, mid.rgb, t / 0.45) : mix(mid.rgb, tail.rgb, (t - 0.45) / 0.55);
		float fade = pow(max(1.0 - t, 0.0), 1.6) * smoothstep(0.0, 0.04, t + 0.02);
		float shock = 1.0;
		if (diamonds > 0.0) {
			shock += 0.6 * pow(max(0.0, sin(t * diamonds * PI)), 6.0) * (1.0 - t);
		}
		ALBEDO = c * face * fade * shock * energy * flick * FX_EXP;
	}
}
