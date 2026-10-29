// Baked adobe buildings of the kishlak and the oasis farmstead (VillageHouses: the vh_h50* houses and oh_* models
// from tools/blender/village_adobe.py and oasis_adobe.py). Their albedo, roughness and relief are final in the
// textures (weathering and cavity AO baked in), so this is the glTF material they come with (double-sided,
// metallic-roughness: roughness in G, no metal) plus the warm bounce from the sunlit ground into the shaded walls
// (bounce.gdshaderinc), which a StandardMaterial3D cannot add on the shade side only.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/bounce.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float specular = 0.25;

varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	ALBEDO = a;
	ROUGHNESS = texture(rough_tex, UV).g;
	METALLIC = 0.0;
	SPECULAR = specular;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	EMISSION = bounce_fill(a, FRONT_FACING ? wn : -wn);
}
