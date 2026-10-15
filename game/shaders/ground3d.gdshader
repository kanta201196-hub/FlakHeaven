shader_type spatial;
render_mode cull_disabled;
// 3.0: земля биома в 3D — 4 материала смешиваются пятнами по шуму, получает свет и тени.
// B-24: множитель яркости и псевдорельеф по яркости.
// B-25: PBR-наборы CC0 (цвет + нормаль + высота), смешивание по высоте (камни проступают сквозь
// песок, а не «растворяются»), защита от повторов плитки (случайный сдвиг по шуму, 2 выборки),
// крупная вариация цвета. Без наборов PBR (use_nh = false) работает на старых текстурах.
// B-26: рельеф (terrain3d.gd) — скала на крутых склонах (проекция с трёх сторон, слои горизонтальны),
// снег на высоких гребнях, затенение впадин (COLOR.r) и лёгкая дымка в долинах; высота 0…1 — COLOR.g.

uniform sampler2D t_sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_clay : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_gravel : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_river : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
// R,G — нормаль (OpenGL), B — высота
uniform sampler2D n_sand : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_clay : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_gravel : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_river : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D t_rock : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D n_rock : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool use_nh = false;
uniform bool relief = false;
uniform float rock_world = 520.0;  // размер плитки скалы, px
uniform float snow_from = 0.86;    // доля высоты, выше которой снег на пологих гребнях
uniform vec3 haze_color : source_color = vec3(0.62, 0.68, 0.78);
// русло и дорога по расстоянию до реки (terrain3d.gd: D_RIVER, D_ROAD; в UV2.x, px со знаком)
uniform float river_w = 26.0;
uniform float road_v = 85.0;
uniform float road_w = 10.0;
uniform vec3 water_color : source_color = vec3(0.42, 0.58, 0.62);
uniform vec3 road_color : source_color = vec3(0.78, 0.7, 0.58);
uniform vec3 rock_tint : source_color = vec3(0.74, 0.66, 0.58); // скала к палитре стайл-гайда (фото рыжее)
uniform float rock_sat = 0.45;
uniform float hillshade = 0.3;     // отмывка рельефа: склоны от солнца темнее — горы читаются сверху
uniform vec3 shade_dir = vec3(-0.55, 0.6, -0.58); // откуда «светит» отмывка (как солнце, но ниже)
uniform bool anti_tile = true;

uniform float tex_world = 460.0;   // мировой размер плитки, px
uniform float patch_world = 1500.0; // размер пятен материалов, px
uniform float sharp = 9.0;
uniform float seed = 0.0;
uniform float albedo_k = 0.8;
uniform float bump_k = 6.0;         // псевдорельеф по яркости (без наборов PBR)
uniform float normal_k = 1.0;       // сила карт нормалей
uniform float height_blend = 0.35;  // ширина перехода по высоте (меньше — резче)
uniform float saturation = 0.8;     // насыщенность земли (фото CC0 ярче палитры стайл-гайда)

varying vec2 world;
varying vec3 world3;
varying vec3 wnorm;
varying vec3 rel;   // x — открытость (впадина < 0.5 < гребень), y — высота 0…1, z — расстояние до реки, px

void vertex() {
	world3 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world = world3.xz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	rel = relief ? vec3(COLOR.rg, UV2.x) : vec3(0.5, 0.0, 9999.0);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.65 + vnoise(p * 2.7 + 17.0) * 0.35; }

// Защита от повторов (по мотивам И. Килеза): шум выбирает один из 8 сдвигов плитки,
// между соседними сдвигами — плавный переход по двум выборкам. Производные — от исходных UV,
// иначе на стыках сдвигов вылезают швы мипмапов.
struct Tap { vec4 a; vec4 n; };
Tap tap(sampler2D ta, sampler2D tn, vec2 uv, float k) {
	vec2 dx = dFdx(uv); vec2 dy = dFdy(uv);
	Tap r;
	if (!anti_tile) {
		r.a = textureGrad(ta, uv, dx, dy);
		r.n = use_nh ? textureGrad(tn, uv, dx, dy) : vec4(0.5, 0.5, dot(r.a.rgb, vec3(0.3333)), 1.0);
		return r;
	}
	float l = k * 8.0;
	float i = floor(l);
	float f = fract(l);
	vec2 oa = sin(vec2(3.0, 7.0) * i);
	vec2 ob = sin(vec2(3.0, 7.0) * (i + 1.0));
	vec4 ca = textureGrad(ta, uv + oa, dx, dy);
	vec4 cb = textureGrad(ta, uv + ob, dx, dy);
	float w = smoothstep(0.2, 0.8, f - 0.1 * dot(ca.rgb - cb.rgb, vec3(1.0)));
	r.a = mix(ca, cb, w);
	if (use_nh) {
		r.n = mix(textureGrad(tn, uv + oa, dx, dy), textureGrad(tn, uv + ob, dx, dy), w);
	} else {
		r.n = vec4(0.5, 0.5, dot(r.a.rgb, vec3(0.3333)), 1.0);
	}
	return r;
}

void fragment() {
	vec2 q = world / patch_world;
	float w0 = fbm(q);
	float w1 = fbm(q + vec2(31.7, 7.3));
	float w2 = fbm(q + vec2(-13.1, 41.9));
	float w3 = fbm(q * 1.3 + vec2(57.2, -21.4)) * 0.88;
	vec2 uv = world / tex_world;
	float k = vnoise(world / (tex_world * 0.45) + 3.1);
	Tap s0 = tap(t_sand, n_sand, uv, k);
	Tap s1 = tap(t_clay, n_clay, uv * 1.03 + 0.37, k);
	Tap s2 = tap(t_gravel, n_gravel, uv * 0.97 + 0.61, k);
	Tap s3 = tap(t_river, n_river, uv + 0.13, k);
	// смешивание по высоте: вес пятна + высота материала, оставляем только верхний слой ± height_blend
	vec4 hw = vec4(w0, w1, w2, w3) * 3.0 + vec4(s0.n.b, s1.n.b, s2.n.b, s3.n.b) * 0.6;
	float m = max(max(hw.x, hw.y), max(hw.z, hw.w));
	vec4 e = max(hw - (m - height_blend), vec4(0.0));
	// мягкий запасной вариант старого смешивания, чтобы переходы не стали «ступеньками»
	vec4 eo = exp((vec4(w0, w1, w2, w3) - max(max(w0, w1), max(w2, w3))) * sharp);
	e = mix(eo / (eo.x + eo.y + eo.z + eo.w), e / max(e.x + e.y + e.z + e.w, 1e-4), use_nh ? 1.0 : 0.0);
	vec3 c = s0.a.rgb * e.x + s1.a.rgb * e.y + s2.a.rgb * e.z + s3.a.rgb * e.w;
	vec2 nxy = vec2(0.0);
	float hgt = 0.5;
	if (use_nh) {
		nxy = (s0.n.rg * e.x + s1.n.rg * e.y + s2.n.rg * e.z + s3.n.rg * e.w) * 2.0 - 1.0;
		hgt = s0.n.b * e.x + s1.n.b * e.y + s2.n.b * e.z + s3.n.b * e.w;
	}
	float ao = 1.0;
	float wet_out = 0.0;  // вода в русле: блестит (ниже шероховатость)
	float hs = 1.0;  // отмывка — в цвет, а не в AO (AO в Godot гасит только рассеянный свет)
	if (relief) {
		// скала на крутых склонах: три проекции, на стенах слои пород горизонтальны
		float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
		float rk = smoothstep(0.22, 0.42, slope + (hgt - 0.5) * 0.15);
		if (rk > 0.001) {
			vec3 bw = pow(abs(wnorm), vec3(4.0));
			bw /= (bw.x + bw.y + bw.z);
			vec3 rx = texture(t_rock, world3.zy / rock_world * vec2(1.0, -1.0)).rgb;
			vec3 ry = texture(t_rock, world3.xz / rock_world).rgb;
			vec3 rz = texture(t_rock, world3.xy / rock_world * vec2(1.0, -1.0)).rgb;
			vec3 rc = rx * bw.x + ry * bw.y + rz * bw.z;
			rc = mix(vec3(dot(rc, vec3(0.299, 0.587, 0.114))), rc, rock_sat) * rock_tint * 1.35;
			c = mix(c, rc, rk);
			nxy = mix(nxy, (texture(n_rock, world3.xz / rock_world).rg * 2.0 - 1.0) * bw.y, rk);
		}
		// осыпь у подножия: светлее и серее в местах, где склон переходит в долину
		float scree = smoothstep(0.08, 0.2, slope) * (1.0 - rk) * 0.35;
		c = mix(c, vec3(dot(c, vec3(0.333))) * 1.08, scree);
		// снег на высоких пологих гребнях
		float snow = smoothstep(snow_from, snow_from + 0.08, rel.y + (hgt - 0.5) * 0.08) * (1.0 - smoothstep(0.35, 0.6, slope));
		c = mix(c, vec3(0.85, 0.86, 0.88), snow);
		ao = mix(0.55, 1.0, smoothstep(0.15, 0.55, rel.x));
	}
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
	float macro = 0.88 + 0.2 * vnoise(world / 2600.0 + 5.0) + 0.06 * (vnoise(world / 700.0 - 9.0) - 0.5);
	vec3 alb = c * macro * albedo_k * hs;
	if (relief) {
		// дымка: дно долин чуть голубее и светлее (воздушная перспектива — глубина без тумана)
		alb = mix(alb, haze_color * 0.75, (1.0 - rel.y) * 0.08);
	}
	ALBEDO = alb;
	if (use_nh) {
		nxy *= normal_k;
		NORMAL_MAP = normalize(vec3(nxy, 1.0)) * 0.5 + 0.5;
		AO = ao * mix(0.7, 1.0, clamp(hgt + 0.35, 0.0, 1.0));
	} else {
		float h = dot(c, vec3(0.3333));
		vec2 g = vec2(dFdx(h), dFdy(h)) * bump_k;
		NORMAL_MAP = normalize(vec3(-g.x, g.y, 1.0)) * 0.5 + 0.5;
		AO = ao;
	}
	ROUGHNESS = mix(0.95, 0.12, wet_out);
	SPECULAR = mix(0.1, 0.6, wet_out);
}
