// Тест 3.5-s5, п. 2 (Kanta): стекло фонаря кабины своих самолётов — одно на все окраски (Livery его не трогает).
// Тёмное тонированное стекло: почти чёрный цвет, острый блик от солнца (низкая шероховатость, сильный спекуляр)
// и отражение неба по Френелю (по краям фонаря сильнее, сверху — лёгкий голубой отлив). Небо — градиентом
// в шейдере, без карты окружения: так одинаково в ангаре и в бою (GL Compatibility).
// Подключается как внешний материал «glass» в .import моделей ангара и боя (tools/blender/canopy_glass.py),
// у кормовой кабины «Кита» — материал «tail_glass».
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.03, 0.045, 0.06);
uniform vec3 sky_top : source_color = vec3(0.50, 0.64, 0.82);
uniform vec3 sky_horizon : source_color = vec3(0.80, 0.84, 0.88);
uniform vec3 ground : source_color = vec3(0.10, 0.095, 0.085);
uniform float reflect_k = 0.7;      // сила отражения неба
uniform float fresnel_min = 0.18;   // отражение, когда смотрим на стекло прямо (сверху в бою)
uniform float rough = 0.05;

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	float f = fresnel_min + (1.0 - fresnel_min) * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 env = r.y > 0.0 ? mix(sky_horizon, sky_top, sqrt(r.y)) : mix(sky_horizon * 0.5, ground, clamp(-r.y * 4.0, 0.0, 1.0));
	ALBEDO = tint;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = rough;
	EMISSION = env * f * reflect_k;
}
