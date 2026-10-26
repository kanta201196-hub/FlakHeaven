// Weathered surfaces of the procedural Highland props (PropBuild: road bridge, footbridge, yurt).
// The owner asked for no flat even paint (Kanta 26.10): on top of a CC0 texture and the per-piece vertex
// colour this adds large soft stains, a dust band from the ground up, dust on up-facing faces, a damp zone
// with a tide line low on bridge piers, and roughness that varies with the same noise, so the matte surface
// never reads as one uniform sheet. Positions are in metres (`unit` per mesh unit), so the wear has the same
// size on every instance whatever its scale on the map.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/srgb.gdshaderinc"

uniform sampler2D color_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform vec3 gain = vec3(1.0);
uniform float desat = 0.0;          // texture towards its own grey: keeps the weave, drops its colour (felt)
uniform bool tex_norm = false;      // divide by the texture's mean (its last mip): only its pattern stays and the
                                    // vertex colour alone sets the tone, the same in Forward+ and Compatibility
uniform float tex_mix = 1.0;        // with tex_norm: how much of the pattern shows (felt: a hint of the weave)
uniform float normal_depth = 1.0;
uniform float unit = 15.0;          // metres per mesh unit
uniform float ground_y = 0.0;       // metres: where the dust band starts
uniform float dust_h = 0.8;         // metres: height of the dust band
uniform vec3 dust_col : source_color = vec3(0.6, 0.52, 0.42);
uniform float dust_amt = 0.5;
uniform float dust_top = 0.25;      // dust settled on up-facing faces
uniform float stain = 0.25;         // depth of the large dark stains
uniform float stain_scale = 0.6;    // stains per metre
uniform float wet_y = -999.0;       // metres: below it the surface is damp (piers in the stream)
uniform float rough = 0.92;
uniform float rough_var = 0.08;

varying vec3 fp;
varying vec3 nrm;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	fp = VERTEX * unit;
	nrm = NORMAL;
}

void fragment() {
	vec3 tx = texture(color_tex, UV).rgb;
	if (tex_norm) {
		vec3 avg = textureLod(color_tex, vec2(0.5), 12.0).rgb;
		tx /= max(vec3(dot(avg, vec3(0.3, 0.55, 0.15))), vec3(0.02));
	}
	tx = mix(tx, vec3(dot(tx, vec3(0.3, 0.55, 0.15))), desat);
	if (tex_norm) {
		tx = mix(vec3(1.0), tx, tex_mix);
	}
	vec3 c = tx * gain * SRGB(COLOR.rgb);
	float n1 = vnoise(fp * stain_scale);
	float n2 = vnoise(fp * stain_scale * 3.7 + vec3(11.0, 3.0, 7.0));
	float n3 = vnoise(fp * 9.0);
	float st = smoothstep(0.5, 0.85, n1 * 0.7 + n2 * 0.3);
	c *= 1.0 - stain * st;
	c *= 0.93 + 0.12 * n3;   // fine blotches: no two square metres alike
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float g = (1.0 - smoothstep(0.0, dust_h, fp.y - ground_y)) * (0.65 + 0.35 * n2);
	c = mix(c, dust_col * (0.75 + 0.5 * lum), g * dust_amt);
	float top = smoothstep(0.55, 0.95, nrm.y) * (0.4 + 0.6 * n2);
	c = mix(c, dust_col, top * dust_top);
	float w = 1.0 - smoothstep(wet_y - 0.05, wet_y + 0.05, fp.y - 0.35 * (n2 - 0.5));
	float tide = smoothstep(wet_y - 0.05, wet_y + 0.05, fp.y) * (1.0 - smoothstep(wet_y + 0.08, wet_y + 0.35, fp.y));
	c = mix(c, c * SRGB(vec3(0.62, 0.62, 0.55)), w);
	c = mix(c, c * 0.82 + dust_col * 0.12, tide * 0.7);
	ALBEDO = c;
	ROUGHNESS = clamp(rough + (n2 - 0.5) * 2.0 * rough_var - w * 0.18, 0.45, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.3;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
