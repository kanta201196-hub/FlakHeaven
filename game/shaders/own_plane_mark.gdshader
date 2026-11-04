// S15-G12 (Kanta s15 review, item 12; R-22 toggle own_plane_read): in the last minutes blasts, rings, smoke and
// tracers covered the player's own plane. This overlay goes on the player's hull mesh (material_overlay) and is
// drawn after every effect, without the depth test: only a two-tone outline of the silhouette (dark outer line,
// light band inside it), so the plane keeps its own paint and shading and its shape reads over dark smoke and
// over bright fire alike.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, shadows_disabled, fog_disabled;
#include "res://shaders/fx_exposure.gdshaderinc"

uniform vec3 light_color : source_color = vec3(0.92, 0.96, 1.0);
uniform vec3 dark_color : source_color = vec3(0.03, 0.04, 0.06);
uniform float strength = 0.8;

void fragment() {
	// 0 where the surface faces the camera, 1 at the silhouette
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float band = smoothstep(0.55, 0.8, f);
	float edge = smoothstep(0.82, 0.95, f);
	ALBEDO = mix(light_color * FX_EXP, dark_color, edge);
	ALPHA = band * strength;
}
