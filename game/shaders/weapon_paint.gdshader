// Service paint for the hangar weapons, their pylons and their stands (S14-13, Kanta 31.10: "natural paint for
// missiles, weapons and stands"). WeaponPaint puts it in place of the StandardMaterial3D a GLB or the code gave a
// part and keeps that material's own colour, textures, roughness and metal; on top it lays what a store of
// weapons in daily service shows: large soft fading patches and fine mottling, sun-bleached upper sides, grime
// streaks running aft and collecting underneath, dust on the upper faces, small paint chips showing primer or
// bare metal, ring seams between body sections with a little dirt along them, a faint orange-peel bump, and a
// roughness that varies with all of these. Paint stays matte (roughness 0.68 or more, low specular); bare metal
// parts get only grime and a varied roughness. Patterns are in object space, in object lengths (`size` mesh
// units = 1), so the look does not depend on how a part is scaled in the view. Colour constants go through SRGB().
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/srgb.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 uv_xform = vec4(1.0, 1.0, 0.0, 0.0);   // the source material's uv1 scale (xy) and offset (zw)
uniform float roughness = 0.86;
uniform bool use_rough_tex = false;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_ch = vec4(0.0, 1.0, 0.0, 0.0);   // which channel of rough_tex holds roughness (glTF: green)
uniform float metallic = 0.0;
uniform bool use_metal_tex = false;
uniform sampler2D metal_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metal_ch = vec4(0.0, 0.0, 1.0, 0.0);   // glTF: blue
uniform bool use_normal_tex = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform bool use_ao_tex = false;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 ao_ch = vec4(1.0, 0.0, 0.0, 0.0);

uniform float size = 1.0;       // object length in mesh units: patterns are in object lengths
uniform float wear = 1.0;       // 0 — the source material as it was, 1 — full service wear
uniform float body_r = 0.0;     // radius of a round body along X (object lengths); seams only show on it
uniform vec4 seams = vec4(9.0); // X of ring seams between body sections (object lengths from the centre); 9 — none
uniform float sat = 1.0;        // share of the source colours kept (stands in loud colours: less; the rest goes khaki)
uniform float tone = 1.0;       // brightness of the source colours

varying vec3 op;
varying vec3 on;
varying float obj_len;   // the object's length in view (world) units

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
	op = VERTEX / max(size, 1e-4);
	on = NORMAL;
	obj_len = length(MODEL_MATRIX[0].xyz) * size;
}

// thin dark line where p.x crosses seam x `s` (anti-aliased by the screen footprint `fw`), plus a soft dirt halo
vec2 seam_line(float x, float s, float fw) {
	float d = abs(x - s);
	float w = 0.0018;
	return vec2(1.0 - smoothstep(w, w + fw * 1.5, d), exp(-d / 0.012));
}

void fragment() {
	vec2 uv = UV * uv_xform.xy + uv_xform.zw;
	// screen-space derivatives first (before any per-pixel branch, code.md §7.7)
	float peel = vnoise(op * 160.0) * 0.6 + vnoise(op * 61.0) * 0.4;
	float fw_peel = length(fwidth(op)) * 160.0;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(peel);
	float dhdy = dFdy(peel);
	float fwx = fwidth(op.x);

	vec3 base = albedo.rgb;
	if (use_albedo_tex) {
		vec4 t = texture(albedo_tex, uv);
		base *= t.rgb;
	}
	float rough = roughness;
	if (use_rough_tex) {
		rough *= dot(texture(rough_tex, uv), rough_ch);
	}
	float metal = metallic;
	if (use_metal_tex) {
		metal *= dot(texture(metal_tex, uv), metal_ch);
	}
	// loud factory colours (the orange missile cart) fade towards a dull khaki of the same brightness
	base = mix(vec3(dot(base, vec3(0.299, 0.587, 0.114))) * vec3(1.1, 1.0, 0.72), base, sat) * tone;
	float paint = 1.0 - smoothstep(0.3, 0.6, metal);   // 1 — painted, 0 — bare metal (nozzles, lugs, fasteners)

	vec3 n = normalize(on);
	float big = vnoise(op * 3.0) * 0.6 + vnoise(op * 7.3 + 5.0) * 0.4;
	float fine = vnoise(op * 26.0) * 0.6 + vnoise(op * 63.0) * 0.4;
	float up = smoothstep(0.15, 0.9, n.y);
	float down = smoothstep(0.1, -0.85, n.y);
	vec3 c = base;
	// fading: large soft patches, fine mottling, sun-bleached upper sides (lighter and greyer)
	c *= mix(0.8, 1.1, big) * (0.93 + 0.14 * fine);
	float lum = dot(c, vec3(0.3333));
	c = mix(c, vec3(lum) * 1.16, up * 0.16 * paint);
	// grime: streaks running aft along the body, heavier underneath; slightly oily (smoother)
	float streak = vnoise(vec3(op.x * 2.6, op.y * 34.0, op.z * 34.0)) * 0.7 + vnoise(vec3(op.x * 7.0, op.y * 90.0, op.z * 90.0)) * 0.3;
	float grime = smoothstep(0.44, 0.8, streak) * (0.35 + 0.65 * down) * (0.55 + 0.45 * big);
	c = mix(c, c * SRGB(vec3(0.42, 0.38, 0.32)), grime * 0.72);
	// dust: settles on the upper faces in soft drifts
	float drift = smoothstep(0.45, 0.8, vnoise(op * 11.0 + 3.0) * 0.7 + fine * 0.3);
	float dust = up * drift * 0.3 * paint;
	c = mix(c, SRGB(vec3(0.56, 0.51, 0.43)), dust);
	// ring seams between body sections: only on the round body, not across fins
	float on_body = body_r > 0.0 ? 1.0 - smoothstep(body_r * 1.06, body_r * 1.2, length(op.yz)) : 0.0;
	vec2 sl = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 s = seam_line(op.x, seams[i], fwx);
		sl = max(sl, s);
	}
	sl *= on_body;
	c *= 1.0 - 0.5 * sl.x;
	c = mix(c, c * SRGB(vec3(0.55, 0.5, 0.44)), sl.y * 0.35);
	// chips: small flakes of paint gone in the worn zones, primer grey or bare metal under them
	float flake = vnoise(op * 38.0 + 11.0) * 0.65 + vnoise(op * 97.0) * 0.35;
	float chip = smoothstep(0.8, 0.83, flake) * smoothstep(0.62, 0.82, big) * paint;
	c = mix(c, SRGB(vec3(0.38, 0.38, 0.36)), chip * 0.7);
	// small scuffs along the body (handling, loading): lighter, rubbed smooth
	float scuff = smoothstep(0.8, 0.9, vnoise(vec3(op.x * 9.0, op.y * 160.0, op.z * 160.0))) * smoothstep(0.4, 0.7, fine) * paint;
	c = mix(c, c * 1.25 + vec3(0.01), scuff * 0.4);

	// roughness: paint matte and uneven, metal varied; grime and scuffs smoother, dust rougher, chips metallic
	float r = paint > 0.5 ? clamp(rough, 0.68, 0.97) : clamp(rough, 0.38, 0.9);
	r += (big - 0.5) * 0.12 + (fine - 0.5) * 0.08;
	r -= grime * 0.14 + scuff * 0.12;
	r = mix(r, 1.0, dust);
	r = mix(r, 0.5, chip);
	float m = mix(metal, 0.55, chip * 0.7);

	ALBEDO = mix(base, c, wear);
	ROUGHNESS = clamp(mix(rough, r, wear), 0.05, 1.0);
	METALLIC = m;
	SPECULAR = mix(0.5, 0.32, paint);
	if (use_ao_tex) {
		AO = dot(texture(ao_tex, uv), ao_ch);
		AO_LIGHT_AFFECT = 0.2;
	}
	// orange peel / pitting as a faint bump, faded out where the pattern gets finer than a pixel
	// (surface-gradient bump: the height is 0.0004 of the object's length in the view)
	float bump = 0.0004 * obj_len * wear * (1.0 - smoothstep(0.4, 1.2, fw_peel));
	vec3 nv = normalize(NORMAL);
	vec3 r1 = cross(dpdy, nv);
	vec3 r2 = cross(nv, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2) * bump;
	NORMAL = normalize(abs(det) * nv - grad);
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
