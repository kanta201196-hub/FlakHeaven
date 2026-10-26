// «Укрепрайон» fort walls (FA-02, texture set Г, Kanta 2026-10-25): Poly Haven CC0 sets in game/art/fort/,
// UVs box-projected at build time (FortBuild). The grading follows the approved preview scene
// (/mnt/project-files/visual/fort_rework/hq/hq_scene.html): the lower metres pick up the valley's dust,
// soft large-scale tone patches, rain streaks under the parapet, the top bleached by the sun.
// Heights are in preview units (`unit` per mesh unit), so the terms do not depend on the fort's size.
// Multipliers act on the sampled (linear) texture colour, as in the preview; no colour constants to SRGB().
shader_type spatial;
render_mode cull_back;

uniform sampler2D color_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 gain = vec3(1.0);
uniform float gamma = 1.0;
uniform float normal_depth = 1.3;
uniform float grime = 5.0;     // dust band height, preview units
uniform float bleach = 12.0;   // sun-bleached from this height up
uniform float ao_amount = 0.55;
uniform float unit = 109.52;   // preview units per mesh unit (FortBuild.K inverse)
uniform float roof_clean = 0.0;   // VIS-01 village houses: no rain streaks on low flat roofs (the fort keeps 0)

varying vec3 fp;
varying float up;

void vertex() {
	fp = VERTEX * unit;
	up = NORMAL.y;
}

void fragment() {
	vec3 c = pow(texture(color_tex, UV).rgb, vec3(gamma)) * gain;
	float g = 1.0 - smoothstep(0.0, grime, fp.y);
	float n = fract(sin(dot(floor(fp.xz * 0.35), vec2(12.9898, 78.233))) * 43758.5453);
	c = mix(c, c * vec3(0.78, 0.68, 0.56), g * (0.75 + 0.25 * n));
	float lf = sin(fp.x * 0.11 + sin(fp.z * 0.07) * 2.0) * sin(fp.z * 0.09 + fp.y * 0.05) * 0.5 + 0.5;
	c *= mix(vec3(0.9, 0.86, 0.8), vec3(1.04, 1.02, 0.98), lf);
	float col = fract(sin(floor((fp.x + fp.z) * 0.9) * 91.7) * 4375.3);
	float streak = step(0.86, col) * smoothstep(14.0, 4.0, fp.y) * smoothstep(0.0, 3.0, fp.y);
	c *= 1.0 - streak * 0.14 * (1.0 - roof_clean * step(0.7, up));
	float top = smoothstep(bleach, bleach + 6.0, fp.y);
	c = mix(c, c * 1.08 + vec3(0.03), top);
	vec3 arm = texture(arm_tex, UV).rgb;
	ALBEDO = c;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
	SPECULAR = 0.3;
	AO = mix(1.0, arm.r, ao_amount);
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
