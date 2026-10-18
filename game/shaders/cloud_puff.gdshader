// M-31 (тест 3.5-s5): объёмные облака — «пуф» облака, круглый клуб дыма, всегда повёрнутый к камере.
// Все пуфы всех облаков — один MultiMesh (CloudPuffs), один вызов отрисовки. Освещение без света сцены:
// плотность в сторону солнца → теневая сторона клуба темнее и голубее; низ облака темнее (тон экземпляра).
// INSTANCE_CUSTOM: x — поворот шума, y — вариант (целая часть 0–3) + рваность края (дробная),
//                  z — тон (0 — низ облака, 1 — освещённая вершина), w — непрозрачность.
// Э-3 (аудит 3.5-s6): светлый верх, серо-голубой низ — нижняя (по мировой вертикали) сторона каждого клуба
// в тени, теневая сторона от солнца темнее, низ облака заметно темнее и голубее. sun_to задаёт Render3D.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 sun_to = vec3(-0.62, 0.85, -0.75);   // направление на солнце (мир)
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 shade_color : source_color = vec3(0.5, 0.56, 0.67);
uniform vec3 base_color : source_color = vec3(0.46, 0.51, 0.61);

varying vec2 v_sun;     // смещение к солнцу в UV квадрата
varying vec2 v_up;      // мировая вертикаль в UV квадрата (длина — насколько «боком» видно клуб)
varying vec4 v_data;
varying mat2 v_rot;

void vertex() {
	// billboard: квадрат к камере, масштаб — из матрицы экземпляра
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec3 ls = (VIEW_MATRIX * vec4(normalize(sun_to), 0.0)).xyz;
	vec2 d = vec2(ls.x, -ls.y);
	v_sun = d / max(length(d), 0.001) * 0.2;
	vec3 lu = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	v_up = vec2(lu.x, -lu.y);
	v_data = INSTANCE_CUSTOM;
	float r = INSTANCE_CUSTOM.x;
	v_rot = mat2(vec2(cos(r), sin(r)), vec2(-sin(r), cos(r)));
}

float dens(vec2 uv) {
	vec2 c = uv - 0.5;
	float r = length(c) * 2.0;
	float variant = floor(v_data.y);
	float wisp = fract(v_data.y);
	vec2 q = v_rot * c * 0.5 + vec2(mod(variant, 2.0), floor(variant / 2.0)) * 0.5 + 0.25;
	float n = texture(noise_tex, q).r;
	float n2 = texture(noise_tex, q * 2.3 + 0.37).r;
	float nn = n * 0.7 + n2 * 0.3;
	// ядро с «кочанным» краем: шум двигает радиус края; у рваных (низких) клочьев шум съедает больше
	float r2 = r * (1.0 + (0.5 - nn) * (0.5 + wisp * 0.6));
	float core = 1.0 - smoothstep(0.2 - wisp * 0.1, 0.97, r2);
	return clamp(core * (0.6 + 0.8 * nn) - wisp * 0.3 * (1.0 - nn), 0.0, 1.0);
}

void fragment() {
	float a = dens(UV);
	float s = dens(UV + v_sun);
	// к солнцу плотность растёт → эта сторона клуба в тени; край к солнцу светлый
	float lit = clamp(0.86 - (s - a) * 3.4, 0.0, 1.0);
	lit *= 0.8 + 0.2 * smoothstep(0.3, 0.9, a);   // у края клуба — чуть темнее (щели между клубами)
	// нижняя сторона клуба (по мировой вертикали) — в тени самого облака; сверху камеры (v_up≈0) не действует
	float hgt = dot(UV - 0.5, v_up) * 2.0;
	lit *= 1.0 - 0.32 * smoothstep(0.05, -0.75, hgt);
	float tone = v_data.z;
	vec3 top = mix(shade_color, lit_color, lit);
	vec3 low = base_color * mix(0.78, 1.05, lit);
	vec3 col = mix(low, top, smoothstep(0.0, 0.85, tone));
	ALBEDO = col;
	ALPHA = smoothstep(0.05, 0.5, a) * v_data.w;
}
