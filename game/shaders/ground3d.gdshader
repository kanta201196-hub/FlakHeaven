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
uniform float snow_north = 0.16;   // аудит Р-6: на теневых («северных») склонах и в кулуарах снег ниже на столько
uniform vec2 snow_shade_dir = vec2(0.62, 0.75); // куда смотрит теневой склон (по солнцу render3d.gd, xz)
uniform float clay_scale = 5.0;    // аудит Р-4 + Р-3: трещины такыра в 5 раз мельче плитки (были ~40 px)
// аудит Р-7: цвет по зонам — светлое дно, серые конусы, тёмно-бурые склоны, ещё темнее гребни
uniform vec3 zone_floor : source_color = vec3(0.92, 0.88, 0.84);
uniform vec3 zone_fan : source_color = vec3(0.74, 0.71, 0.67);
uniform vec3 zone_slope : source_color = vec3(0.76, 0.66, 0.57);
uniform vec3 zone_crest : source_color = vec3(0.6, 0.56, 0.52);
uniform vec3 haze_color : source_color = vec3(0.62, 0.68, 0.78);
// русло и дорога по расстоянию до реки (terrain3d.gd: D_RIVER, D_ROAD; в UV2.x, px со знаком)
uniform float river_w = 26.0;
uniform float river_guard = 68.0;  // M-35: охранная зона реки (terrain3d.gd RIVER_GUARD) — без пятен поселений, полей и гари
uniform float road_v = 85.0;
uniform float road_w = 22.0;     // M-36: полуширина дороги наружу от реки (terrain3d.gd ROAD_W; L-03 «Второго биома» — та же 22)
uniform float road_w_in = 14.0;  // M-36: полуширина к реке (ROAD_W_IN): край не заходит в охранную зону
uniform vec3 water_color : source_color = vec3(0.3, 0.42, 0.44);
// «Архипелаг» (Biome.sea): вода пролива — цвет по глубине (поле берега 0 … sea_w), пена у кромки
uniform bool sea = false;
uniform float sea_w = 16.12;
uniform vec3 sea_shallow : source_color = vec3(0.42, 0.74, 0.7);
uniform vec3 sea_mid : source_color = vec3(0.13, 0.47, 0.57);
uniform vec3 sea_deep : source_color = vec3(0.07, 0.25, 0.4);
// вид воды (замечание Kanta 20.10 «вода плохо выглядит»): 0 — как было; 1 — ровные цвета без зубцов;
// 2 — + рябь, блики и накат пены; 3 — + прозрачная отмель (видно песок и камни под водой);
// 4 — по фото Kanta 21.10: приглушённая вода, широкая отмель с косами, узкий пляж и зелень у воды, без белой обводки
uniform int sea_look = 0;
// поле берега в сетке (terrain3d.gd _shore_u): первые shore_a пикс. воды — шаг 1 ед./пикс., дальше до оси
uniform float shore_a = 12.0;
uniform float sea_depth_px = 450.0;
uniform vec3 road_color : source_color = vec3(0.7, 0.62, 0.5);
uniform vec3 rock_tint : source_color = vec3(0.74, 0.66, 0.58); // скала к палитре стайл-гайда (фото рыжее)
uniform float rock_sat = 0.45;
// M-36: скальные выходы и осыпи (маски — UV, terrain3d.gd _relief). Цвета — сухие горы: бурая и серая порода
// пластами, светлая серо-бурая осыпь у подножия
uniform vec3 rock_brown : source_color = vec3(0.63, 0.51, 0.42);
uniform vec3 rock_grey : source_color = vec3(0.5, 0.5, 0.49);
uniform vec3 scree_color : source_color = vec3(0.7, 0.66, 0.6);
uniform float scree_k = 0.75;   // сила осыпей; «Архипелаг» — слабее, у воды их нет (рваные серые полосы вдоль берега)
uniform float strata_px = 13.0;   // толщина пласта по высоте, px мира
// M-36: скала с трёх проекций (3 выборки) — только «Высокое»/«Максимальное»; на «Низком»/«Среднем» —
// две (сверху и сбоку по склону), меньше, чем было (3)
uniform bool rock_tri = true;
uniform float slope_fill = 0.22;   // M-36: подсветка крутых склонов — тень в оврагах не уходит в чёрное
uniform float hillshade = 0.3;     // отмывка рельефа: склоны от солнца темнее — горы читаются сверху
uniform vec3 shade_dir = vec3(-0.55, 0.6, -0.58); // откуда «светит» отмывка (как солнце, но ниже)
uniform bool anti_tile = true;
// 3.4-t1 (п. 33): тени облаков рисуются на самой земле (раньше — 2D-пятна на плоскости боя, при наклоне
// они висели поверх гор). Облако: xy — центр, z — размер, w — поворот + 10 × номер текстуры
uniform sampler2D cloud_a : filter_linear, repeat_disable;
uniform sampler2D cloud_b : filter_linear, repeat_disable;
uniform vec4 clouds[12];
uniform int cloud_n = 0;
uniform float cloud_y = 380.0;
uniform vec2 cloud_shift = vec2(0.0);  // сдвиг тени на 1 px высоты (по солнцу)
uniform float cloud_dark = 0.28;   // Э-3 (аудит 3.5-s6): тень облака заметнее (было 0,2)
// тест 3.5-s5 (п. 8): тени самолётов — карта сверху (render3d._psh_vp, канал R — густота тени);
// rect: x, z левого верхнего угла, сторона, включено
uniform sampler2D plane_sh : filter_linear, repeat_disable, hint_default_black;
uniform vec4 plane_sh_rect = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec3 plane_sh_color = vec3(0.04, 0.05, 0.09);
// Тест 3.5-s7: метки на земле — прицел и зона бомб, огонь на земле. Раньше это были плоские круги в слое боя
// (над рельефом); теперь земля сама рисует их: точка рельефа проецируется лучом камеры на плоскость боя
// (как GroundTarget.air_pos) и сравнивается с зоной там — метка ложится по склонам ровно туда, где бьёт.
// a: отрезок зоны на плоскости боя (x1, y1, x2, y2; круг — точки совпадают); b: радиус, яркость, вид, случайное;
// c: цвет. Вид 0 — прицел готов, 1 — прицел на перезарядке, 2 — падающая бомба, 3 — огонь на земле
uniform vec4 gz_a[24];
uniform vec4 gz_b[24];
uniform vec4 gz_c[24];
uniform int gz_n = 0;
uniform vec3 gz_cam = vec3(0.0, 1000.0, 0.0);
uniform float gz_time = 0.0;

uniform float tex_world = 460.0;   // мировой размер плитки, px
uniform float patch_world = 1500.0; // размер пятен материалов, px
uniform float sharp = 9.0;
uniform float seed = 0.0;
uniform float albedo_k = 0.8;
uniform float bump_k = 6.0;         // псевдорельеф по яркости (без наборов PBR)
uniform float normal_k = 1.0;       // сила карт нормалей
uniform float height_blend = 0.55;  // ширина перехода по высоте (меньше — резче)
uniform float saturation = 0.8;     // насыщенность земли (фото CC0 ярче палитры стайл-гайда)

varying vec2 world;
varying vec3 world3;
varying vec3 wnorm;
varying vec3 smask; // тест 3.5-s4 (п. 16–17): x — утоптанная земля поселения, y — огороды и сады, z — гарь и воронки (terrain3d.gd)
varying vec2 rmask; // M-36: x — скальный выход, y — осыпь у подножия (terrain3d.gd _relief)
varying vec3 rel;   // x — открытость (впадина < 0.5 < гребень), y — высота 0…1, z — расстояние до реки, px

void vertex() {
	world3 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world = world3.xz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	rel = relief ? vec3(COLOR.rg, UV2.x) : vec3(0.5, 0.0, 9999.0);
	smask = relief ? vec3(COLOR.ba, UV2.y) : vec3(0.0);
	rmask = relief ? UV : vec2(0.0);
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
	// аудит Р-4: такыр (растрескавшаяся глина) — только на ровном дне долин и равнин вдали от воды;
	// на склонах, конусах и гребнях — щебень и супесь
	float slope0 = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	if (relief) {
		w1 *= (1.0 - smoothstep(0.03, 0.08, slope0)) * (1.0 - smoothstep(0.04, 0.12, rel.y))
			* smoothstep(river_guard, river_guard + 60.0, abs(rel.z));
	}
	float w2 = fbm(q + vec2(-13.1, 41.9));
	float w3 = fbm(q * 1.3 + vec2(57.2, -21.4)) * 0.88;
	vec2 uv = world / tex_world;
	float k = vnoise(world / (tex_world * 0.45) + 3.1);
	Tap s0 = tap(t_sand, n_sand, uv, k);
	Tap s1 = tap(t_clay, n_clay, uv * clay_scale + 0.37, k);   // Р-4: ячейки трещин мельче
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
	vec3 sea_e = vec3(0.0);  // «Архипелаг»: блики солнца на ряби — в EMISSION (без неба отражений нет)
	vec2 sea_n = vec2(0.0);  // «Архипелаг»: нормаль ряби
	float hs = 1.0;  // отмывка — в цвет, а не в AO (AO в Godot гасит только рассеянный свет)
	if (relief) {
		// скала на крутых склонах: три проекции, на стенах слои пород горизонтальны
		float slope = slope0;
		// аудит Р-7: зоны по высоте — множитель к цвету грунта (свой тон у дна, конуса, склона, гребня);
		// граница размыта шумом, чтобы не читалась горизонталью
		float zh = rel.y + (vnoise(world / 300.0 + 5.0) - 0.5) * 0.06;
		float lum = dot(c, vec3(0.333));
		// конусы: серый щебень, но не сплошной светлой каймой — местами остаётся бурый грунт
		vec3 fan_c = mix(c * 1.05 * zone_floor, mix(vec3(lum), c, 0.3) * 1.35 * zone_fan, 0.35 + 0.65 * smoothstep(0.3, 0.7, vnoise(world / 220.0 + 8.0)));
		vec3 zc = mix(fan_c, mix(vec3(lum), c, 0.85) * 1.1 * zone_floor, 1.0 - smoothstep(0.03, 0.1, zh));
		zc = mix(zc, mix(vec3(lum), c, 0.6) * 1.85 * zone_slope, smoothstep(0.1, 0.22, zh));
		zc = mix(zc, vec3(lum) * 1.9 * zone_crest, smoothstep(0.55, 0.85, zh));
		c = zc;
		float rk = smoothstep(0.2, 0.5, slope + (hgt - 0.5) * 0.15);   // 3.4-t1 (п. 18): переход к скале шире
		// M-36: скальный выход по маске рельефа — порода и на полках уступов (там с каменной крошкой),
		// край пятна рваный по высоте текстуры и шуму
		float brk = (vnoise(world / 70.0 + 9.0) - 0.5) * 0.5 + (hgt - 0.5) * 0.4;
		float rg = smoothstep(0.3, 0.6, rmask.x + brk) * (0.6 + 0.4 * smoothstep(0.06, 0.3, slope));
		rk = max(rk, rg);
		if (rk > 0.001) {
			vec3 rc;
			if (rock_tri) {
				vec3 bw = pow(abs(wnorm), vec3(4.0));
				bw /= (bw.x + bw.y + bw.z);
				vec3 rx = texture(t_rock, world3.zy / rock_world * vec2(1.0, -1.0)).rgb;
				vec3 ry = texture(t_rock, world3.xz / rock_world).rgb;
				vec3 rz = texture(t_rock, world3.xy / rock_world * vec2(1.0, -1.0)).rgb;
				rc = rx * bw.x + ry * bw.y + rz * bw.z;
			} else {
				// сверху и сбоку — проекция вдоль склона (поперёк его горизонтали): 2 выборки
				vec2 hn = wnorm.xz / max(length(wnorm.xz), 1e-3);
				float by = pow(clamp(wnorm.y, 0.0, 1.0), 4.0);
				float bs = pow(1.0 - clamp(wnorm.y, 0.0, 1.0), 2.0) * 2.0;
				vec3 ry = texture(t_rock, world3.xz / rock_world).rgb;
				vec3 rs = texture(t_rock, vec2(dot(world3.xz, vec2(-hn.y, hn.x)), -world3.y) / rock_world).rgb;
				rc = (ry * by + rs * bs) / (by + bs);
			}
			// аудит Р-5: тёмные трещины фото скалы читались мазками копоти — контраст рисунка мягче
			float rl = mix(0.42, dot(rc, vec3(0.299, 0.587, 0.114)), 0.65);
			rc = mix(vec3(rl), rc, rock_sat) * rock_tint * 1.35;
			// пласты: бурые и серые слои по высоте, чуть наклонены и волнисты; тёмная кромка у каждого уступа
			float sy = world3.y / strata_px + dot(world3.xz, vec2(0.0021, 0.0013)) + vnoise(world / 240.0) * 1.6;
			float band = vnoise(vec2(floor(sy), 3.7) * 0.73);
			vec3 tint = mix(rock_brown, rock_grey, band) * 1.8;
			float lip = 1.0 - 0.18 * smoothstep(0.75, 1.0, fract(sy)) * smoothstep(0.15, 0.45, slope);
			rc = mix(rc, rl * tint, 0.7) * lip;
			// на полках уступов — каменная крошка (текстура щебня уже выбрана выше)
			float shelf = rg * (1.0 - smoothstep(0.12, 0.3, slope));
			rc = mix(rc, mix(s2.a.rgb, vec3(dot(s2.a.rgb, vec3(0.333))), 0.5) * 1.05, shelf * 0.45);
			c = mix(c, rc, rk);
			nxy = mix(nxy, (texture(n_rock, world3.xz / rock_world).rg * 2.0 - 1.0) * max(1.0 - slope, 0.4), rk);
		}
		// осыпь у подножия: светлее и серее в местах, где склон переходит в долину
		float scree = smoothstep(0.08, 0.2, slope) * (1.0 - rk) * 0.35;
		c = mix(c, vec3(dot(c, vec3(0.333))) * 1.08, scree);
		// M-36: осыпные конусы под скальными выходами — светлый серо-бурый щебень, мелкая фактура
		// (текстура щебня мельче плитки: тот же отсчёт, без новой выборки), край языками вниз по склону
		float sc = smoothstep(0.2, 0.55, rmask.y + (vnoise(world / 45.0 - 3.0) - 0.5) * 0.45 + (s2.n.b - 0.5) * 0.3) * (1.0 - rk);
		if (sc > 0.001) {
			vec3 grit = mix(vec3(dot(s2.a.rgb, vec3(0.333))), s2.a.rgb, 0.35);
			vec3 scc = scree_color * (0.7 + 0.45 * grit) * (0.93 + 0.12 * vnoise(world / 6.0));
			if (sea) {
				sc *= smoothstep(sea_w + 25.0, sea_w + 110.0, abs(rel.z));
			}
			c = mix(c, scc, sc * scree_k);
			nxy = mix(nxy, s2.n.rg * 2.0 - 1.0, sc * 0.6);
		}
		// снег на высоких пологих гребнях
		// B-47: снег был почти белым (0.85) и пересвечивался на солнце (до 18 % кадра в белый),
		// а рисунок трещин земли проступал сквозь него. Теперь снег серо-голубой, пятнистый по краю,
		// с мягкими застругами вместо рисунка грунта
		// аудит Р-6: снег — не «шапка» по высоте: ниже на теневых склонах и в кулуарах (вогнутость rel.x < 0.5),
		// не держится на крутых скалах и гребнях; под снегом рисунка грунта нет совсем
		float patch = (vnoise(world / 420.0 + 17.0) - 0.5) * 0.07 + (vnoise(world / 60.0 + 4.0) - 0.5) * 0.04;
		float shade_face = clamp(dot(wnorm.xz, normalize(snow_shade_dir)) * 2.5, -1.0, 1.0);
		float gully = clamp((0.5 - rel.x) * 3.0, -1.0, 1.0);
		float sfrom = snow_from - snow_north * clamp(shade_face * 0.7 + gully * 0.5, -0.6, 1.0);
		float snow = smoothstep(sfrom, sfrom + 0.05, rel.y + (hgt - 0.5) * 0.05 + patch)
			* (1.0 - smoothstep(0.3, 0.55, slope)) * (1.0 - 0.8 * rg);
		vec3 snow_c = vec3(0.64, 0.67, 0.72) * (0.93 + 0.1 * vnoise(world / 160.0 - 4.0));
		c = mix(c, snow_c, snow);
		nxy *= 1.0 - snow;
		hgt = mix(hgt, 0.65, snow);   // и в AO по высоте текстуры — трещины не проступают
		ao = mix(0.55, 1.0, smoothstep(0.15, 0.55, rel.x));
		// 3.4-t1 (п. 18): русло, влажный берег и дорога (B-46 обещал их, но в шейдер они не попали —
		// русло читалось чёрной канавой). rel.z — расстояние до линии реки со знаком, px
		// поселения: пятно утоптанной земли и лоскуты полей с неровной кромкой (маска — по вершинам, край — шумом)
		float rd = abs(rel.z);
		float edge = (vnoise(world / 90.0 + 3.0) - 0.5) * 8.0;
		// M-35: в охранной зоне реки ни утоптанной земли, ни огородов, ни гари — только вода и мокрый берег;
		// край — по расстоянию до реки в пикселе (у вершин шаг 20 px), с той же неровной кромкой, что у берега
		vec3 sm = smask * smoothstep(river_guard, river_guard + 10.0, rd + edge);
		if (sm.x + sm.y + sm.z > 0.004) {
			float en = vnoise(world / 55.0 + 11.0) - 0.5 + (vnoise(world / 17.0 - 5.0) - 0.5) * 0.4;
			float tr = smoothstep(0.2, 0.75, sm.x + en * 0.5);
			vec3 packed_c = mix(c, vec3(dot(c, vec3(0.333))) * vec3(1.1, 1.0, 0.86), 0.4) * (1.04 + 0.08 * (vnoise(world / 9.0) - 0.5));
			c = mix(c, packed_c, tr * 0.7);
			nxy *= 1.0 - 0.5 * tr;
			float gr = smoothstep(0.25, 0.7, sm.y + en * 0.55);
			if (gr > 0.001) {
				// лоскуты: участки ~60–90 px, повёрнутые немного по шуму; посевы, жнивьё, пахота, сад
				vec2 fq = mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * world;
				// ряды участков со сдвигом и разной длиной — без «шахматной доски»
				float row = floor(fq.y / 62.0);
				float cw = 70.0 + 50.0 * hash(vec2(row, 3.0));
				vec2 fg = vec2((fq.x + hash(vec2(row, 9.0)) * 200.0) / cw, fq.y / 62.0);
				vec2 cell = floor(fg);
				vec2 fr = fract(fg);
				float pick = hash(cell);
				// цвета — к палитре земли: приглушённые, поле не «газон»; внутри участка — рядки и пятна
				vec3 fc = pick < 0.3 ? vec3(0.46, 0.47, 0.3) : (pick < 0.55 ? vec3(0.64, 0.57, 0.4) : (pick < 0.78 ? vec3(0.5, 0.41, 0.31) : vec3(0.38, 0.41, 0.27)));
				fc = mix(fc, c, 0.25);
				float rows = 0.9 + 0.1 * sin((pick < 0.5 ? fq.x : fq.y) * 0.9);
				fc *= rows * (0.86 + 0.28 * vnoise(world / 7.0 + pick * 40.0)) * (0.9 + 0.2 * vnoise(world / 40.0 - pick * 13.0));
				// межи и арыки — светлые полоски по краю участка
				float mz = 1.0 - smoothstep(0.0, 0.05, min(min(fr.x, 1.0 - fr.x) * 1.4, min(fr.y, 1.0 - fr.y)));
				fc = mix(fc, packed_c, mz * 0.8);
				float keep = step(0.12, hash(cell + 7.0));   // часть участков — пустырь
				c = mix(c, fc, gr * keep * 0.82);
				nxy *= 1.0 - 0.6 * gr * keep;
			}
			// гарь: тёмное пятно с рваным краем, у воронки — темнее в середине
			float bn = smoothstep(0.25, 0.75, sm.z + (vnoise(world / 14.0 + 2.0) - 0.5) * 0.6 + (vnoise(world / 4.0) - 0.5) * 0.15);
			// не сплошная клякса: сажа пятнами, по краю — рыжеватая опалённая земля, в середине темнее
			float soot = 0.55 + 0.45 * smoothstep(0.3, 0.7, vnoise(world / 6.0 + 21.0));
			vec3 burnt = mix(c * vec3(0.62, 0.52, 0.44), vec3(0.2, 0.175, 0.155), smoothstep(0.55, 1.0, sm.z) * soot);
			c = mix(c, burnt, bn * 0.78);
			nxy *= 1.0 - 0.5 * bn;
		}
		float bank = 1.0 - smoothstep(river_w, river_w * 2.4, rd + edge);
		c = mix(c, c * vec3(0.78, 0.82, 0.7), bank * 0.6);       // сырая земля и зелень у воды
		float water = 1.0 - smoothstep(river_w * 0.45, river_w * 0.8, rd + edge * 0.5);
		if (sea && sea_look > 0) {
			// у моря поле по воде растянуто (1 ед. ≈ depth_px / sea_w px), у реки — нет: кромка резкая, ~15 px
			// поле у кромки — 1 ед./пикс. по обе стороны: край ровный, неровность — шумом в пикселях
			float sh_n = (vnoise(world / 23.0 + 7.0) - 0.5) * 7.0 + (vnoise(world / 7.0 - 3.0) - 0.5) * 2.5;
			water = 1.0 - smoothstep(sea_w - 1.5, sea_w + 1.0, rd + sh_n);
		}
		vec3 wc = water_color * (0.9 + 0.2 * vnoise(world / 60.0));
		if (sea && sea_look > 0) {
			// глубина по полю берега: оно линейно у кромки и обрезано у оси пролива — переходы цвета держим
			// в линейной части (иначе по треугольникам сетки идут зубцы), а дальше глубину рисует крупный шум
			// глубина 0 (берег) … 1 (ось) из поля сетки (обратно к terrain3d.gd _shore_u)
			float u0 = sea_w - shore_a;
			float dpx = rd >= u0 ? sea_w - rd : shore_a + (1.0 - rd / max(u0, 0.01)) * (sea_depth_px - shore_a);
			float dp0 = clamp(dpx / sea_depth_px, 0.0, 1.0);
			vec2 wq = world + vec2(vnoise(world / 230.0 + 5.0), vnoise(world / 230.0 - 9.0)) * 120.0;
			float big = vnoise(wq / 520.0 + 3.0) * 0.65 + vnoise(wq / 190.0 - 4.0) * 0.35;
			float dp = clamp(dp0 + (big - 0.5) * 0.22 * smoothstep(0.04, 0.25, dp0), 0.0, 1.0);
			vec3 sh = vec3(0.4, 0.66, 0.6), md = vec3(0.13, 0.4, 0.47), dpc = vec3(0.06, 0.2, 0.3);
			wc = mix(sh, md, smoothstep(0.03, 0.3, dp));
			// глубокое — по смеси поля и шума: у оси узкого пролива поле ломается по треугольникам, шум прячет излом
			wc = mix(wc, dpc, smoothstep(0.3, 0.55, dp * 0.55 + big * 0.45 + 0.08));
			wc *= 0.96 + 0.06 * vnoise(wq / 70.0 + 11.0);
			if (sea_look >= 4) {
				// вид 4 (по фото Kanta 21.10): приглушённая серо-бирюзовая вода, отмель широкая и плавная
				// оба перехода — по смеси поля и шума: у оси узкого пролива поле ломается по треугольникам
				float dd = dp * 0.6 + big * 0.4;
				wc = mix(vec3(0.34, 0.64, 0.62), vec3(0.15, 0.47, 0.55), smoothstep(0.02, 0.42, min(dp, dd + 0.12)));
				wc = mix(wc, vec3(0.09, 0.27, 0.4), smoothstep(0.32, 0.78, dd));
				wc *= 0.97 + 0.05 * vnoise(wq / 90.0 + 11.0);
			}
			float t = TIME;
			if (sea_look >= 3) {
				// отмель прозрачная: под водой песок и камни берега, с глубиной уходят в цвет воды
				vec3 bed = c * vec3(0.7, 0.9, 0.86) + vec3(0.02, 0.07, 0.07);
				if (sea_look >= 4) {
					// дно: светлые песчаные косы и тёмные пятна водорослей, видны далеко от берега
					float bar = smoothstep(0.45, 0.75, vnoise(vec2(world.x * 0.6 + world.y * 0.8, world.y * 0.6 - world.x * 0.8) / vec2(140.0, 45.0)));
					float weed = smoothstep(0.55, 0.8, vnoise(wq / 55.0 - 6.0)) * (0.6 + 0.4 * vnoise(world / 12.0));
					// под водой красный гаснет: дно в бирюзу, светлее только косы
					bed = mix(vec3(0.42, 0.66, 0.6), vec3(0.58, 0.76, 0.66), bar);
					bed = mix(bed, vec3(0.18, 0.34, 0.32), weed * 0.7);
					wc = mix(bed, wc, smoothstep(0.0, 0.45, dp0) * 0.75 + 0.25);
				} else {
					wc = mix(bed, wc, smoothstep(0.01, 0.3, dp0) * 0.85 + 0.15);
				}
				// блики-каустика на дне отмели
				float ca = vnoise(world / 11.0 + vec2(t * 0.35, t * 0.2)) * vnoise(world / 14.0 - vec2(t * 0.25, -t * 0.3));
				sea_e += vec3(0.9, 1.0, 0.95) * smoothstep(0.32, 0.5, ca) * 0.1 * (1.0 - smoothstep(0.0, 0.15, dp));
			}
			// пена: тонкая рваная линия у кромки
			float brk = smoothstep(0.35, 0.7, vnoise(world / 38.0 + 4.0)) * 0.6 + 0.4;
			float foam = (1.0 - smoothstep(0.012, 0.03, dp0)) * brk;
			if (sea_look >= 2) {
				// накат: полоса пены идёт от отмели к берегу и тает
				float ph = fract(t * 0.11 + vnoise(world / 260.0) * 0.6);
				float wv = (1.0 - smoothstep(0.0, 0.01, abs(dp0 - 0.02 - (1.0 - ph) * 0.1))) * ph * smoothstep(0.4, 0.7, vnoise(world / 30.0 + t * 0.05));
				foam = max(foam, wv * 0.8);
				// рябь: две бегущие волны шума — в нормаль и в блики солнца
				vec2 r1 = world / 26.0 + vec2(t * 0.6, t * 0.25);
				vec2 r2 = world / 41.0 - vec2(t * 0.2, -t * 0.45);
				float e1 = 0.6;
				sea_n = vec2(vnoise(r1 + vec2(e1, 0.0)) - vnoise(r1 - vec2(e1, 0.0)), vnoise(r1 + vec2(0.0, e1)) - vnoise(r1 - vec2(0.0, e1)))
					+ vec2(vnoise(r2 + vec2(e1, 0.0)) - vnoise(r2 - vec2(e1, 0.0)), vnoise(r2 + vec2(0.0, e1)) - vnoise(r2 - vec2(0.0, e1))) * 0.7;
				sea_n *= 0.6 * smoothstep(0.02, 0.15, dp0);
				// блики: произведение трёх шумов под углом к сетке — редкие искры без квадратов
				vec2 g1 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * world;
				float gl = vnoise(g1 / 13.0 + vec2(t * 0.9, -t * 0.4)) * vnoise(world / 17.0 - vec2(t * 0.5, t * 0.7)) * vnoise(world / 90.0 + t * 0.05);
				sea_e += vec3(1.0, 0.98, 0.9) * smoothstep(0.36, 0.55, gl) * 0.16 * smoothstep(0.1, 0.4, dp0);
				wc *= 0.95 + 0.1 * vnoise(r1 * 0.5);
			}
			if (sea_look >= 4) {
				// без обводки: прибой — слабая рваная полоса лишь на части берега, вместо искр — широкий мягкий отблеск
				foam *= 0.35 * smoothstep(0.45, 0.7, vnoise(world / 160.0 + 2.0));
				// прибой на кромке рифа в море (фото 2): рваные белые дуги вдоль берега на части отмели
				float rn = vnoise(world / 120.0 + 13.0);
				float sd = abs(dp0 - 0.16 - rn * 0.12);
				float surf = ((1.0 - smoothstep(0.0, 0.03, sd)) * 0.7 + (1.0 - smoothstep(0.0, 0.08, sd)) * 0.3)
					* smoothstep(0.55, 0.75, vnoise(world / 260.0 - 5.0))
					* smoothstep(0.35, 0.65, vnoise(world / 22.0 + vec2(t * 0.15, 0.0)));
				foam = max(foam, surf * 0.85);
				sea_e = sea_e * 0.25 + vec3(0.06, 0.065, 0.06) * smoothstep(0.4, 0.8, vnoise(world / 420.0 + vec2(t * 0.01, 0.0))) * smoothstep(0.2, 0.6, dp0);
			}
			wc = mix(wc, vec3(0.9, 0.93, 0.92), foam * 0.8);
			sea_e *= water;
		} else if (sea) {
			// глубина: у берега бирюзовая отмель, к оси пролива синее; пятна рифов и ряби — шумом
			float dp = clamp(1.0 - rd / sea_w, 0.0, 1.0);
			float dp0 = dp;
			dp = clamp(dp + (vnoise(world / 420.0 + 3.0) - 0.5) * 0.18 * smoothstep(0.05, 0.3, dp0), 0.0, 1.0);
			wc = mix(sea_shallow, sea_mid, smoothstep(0.02, 0.22, dp));
			wc = mix(wc, sea_deep, smoothstep(0.3, 0.85, dp));
			wc *= 0.95 + 0.08 * vnoise(world / 160.0) + 0.03 * vnoise(world / 55.0 + 11.0);
			float foam = (1.0 - smoothstep(0.0, 0.05, abs(dp0 - 0.03)))
				* (0.55 + 0.45 * smoothstep(0.3, 0.7, vnoise(world / 75.0 + 4.0)));
			wc = mix(wc, vec3(0.93, 0.95, 0.94), foam * 0.75);
		}
		if (sea && sea_look > 0) {
			// мокрый песок у кромки вместо сухой рыжей полосы
			float wet = (1.0 - smoothstep(sea_w + 2.0, sea_w + 16.0, rd + edge)) * (1.0 - water);
			if (sea_look >= 4) {
				// берег по фото: узкий светлый пляж переменной ширины (местами нет), за ним — зелень до воды;
				// рыжей полосы дна долины у воды нет
				float sl = rd - sea_w;   // пикс. от кромки по суше
				float bw = 22.0 * smoothstep(0.3, 0.65, vnoise(world / 210.0 + 8.0)) + 3.0 * vnoise(world / 9.0);
				float beach = (1.0 - smoothstep(bw - 3.0, bw + 1.0, sl)) * (1.0 - water);
				float veg = (1.0 - smoothstep(60.0, 190.0, sl + (vnoise(world / 70.0) - 0.5) * 80.0)) * (1.0 - beach);
				vec3 vc = mix(vec3(0.25, 0.39, 0.19), vec3(0.37, 0.47, 0.25), vnoise(world / 24.0)) * (0.85 + 0.3 * vnoise(world / 6.0));
				c = mix(c, vc, veg * 0.8 * smoothstep(0.3, 0.6, vnoise(world / 90.0 + 4.0) * 0.6 + 0.4));
				c = mix(c, vec3(0.88, 0.76, 0.55) * (0.94 + 0.1 * vnoise(world / 5.0)), beach * 0.92);
				wet *= 0.25;
			}
			c = mix(c, c * vec3(0.7, 0.72, 0.7), wet * 0.7);
		}
		c = mix(c, wc, water);
		nxy *= 1.0 - water;
		nxy += sea_n * water;
		wet_out = water;
		ao = mix(ao, 1.0, water);
		// M-36: дорога шире — наружу (от реки) road_w, к реке road_w_in (край вне охранной зоны);
		// плотная середина и мягкая обочина ~8 px; колеи — по обе стороны оси D_ROAD
		float rd0 = rel.z - road_v;
		float rhalf = rd0 < 0.0 ? road_w_in : road_w;
		float rdist = abs(rd0) + (vnoise(world / 140.0 - 7.0) - 0.5) * 4.0;
		float road = (1.0 - smoothstep(rhalf - 8.5, rhalf, rdist)) * (1.0 - water);
		float ruts = 1.0 - 0.18 * (1.0 - smoothstep(0.0, 1.6, abs(abs(rd0) - 5.5)));
		c = mix(c, road_color * (0.92 + 0.12 * vnoise(world / 30.0)) * ruts, road * 0.6);
		nxy *= 1.0 - road * 0.7;
	}
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
	float macro = 0.88 + 0.2 * vnoise(world / 2600.0 + 5.0) + 0.06 * (vnoise(world / 700.0 - 9.0) - 0.5);
	vec3 alb = c * macro * albedo_k * hs;
	if (relief) {
		// дымка: дно долин чуть голубее и светлее (воздушная перспектива — глубина без тумана)
		alb = mix(alb, haze_color * 0.75, (1.0 - rel.y) * 0.08);
	}
	float cs = 0.0;
	for (int ci = 0; ci < 12; ci++) {
		if (ci >= cloud_n) break;
		vec4 cl = clouds[ci];
		vec2 d = world3.xz + cloud_shift * (cloud_y - world3.y) - cl.xy;
		float idx = floor(cl.w / 10.0);
		float r = cl.w - idx * 10.0;
		vec2 l = vec2(d.x * cos(r) + d.y * sin(r), -d.x * sin(r) + d.y * cos(r)) / cl.z + 0.5;
		if (l.x > 0.0 && l.y > 0.0 && l.x < 1.0 && l.y < 1.0) {
			// край: 5 выборок (у текстур облаков нет мип-уровней); Э-3 — разброс вдвое меньше и контраст выше,
			// тень кучевого облака на земле с чётким краем, а не размытым пятном
			float acc = 0.0;
			for (int k = 0; k < 5; k++) {
				vec2 o = k == 0 ? vec2(0.0) : vec2(cos(float(k) * 1.5708), sin(float(k) * 1.5708)) * 0.025;
				acc += idx < 0.5 ? texture(cloud_a, l + o).a : texture(cloud_b, l + o).a;
			}
			cs = max(cs, smoothstep(0.12, 0.55, acc / 5.0));
		}
	}
	alb *= 1.0 - cloud_dark * cs;
	if (plane_sh_rect.w > 0.5) {
		vec2 suv = (world3.xz - plane_sh_rect.xy) / plane_sh_rect.z;
		if (suv.x > 0.0 && suv.x < 1.0 && suv.y > 0.0 && suv.y < 1.0) {
			alb = mix(alb, plane_sh_color, texture(plane_sh, suv).r);
		}
	}
	vec3 gz_e = vec3(0.0);
	if (gz_n > 0) {
		vec2 cp = gz_cam.xz + (world3.xz - gz_cam.xz) * gz_cam.y / max(gz_cam.y - world3.y, 1.0);
		for (int zi = 0; zi < 24; zi++) {
			if (zi >= gz_n) break;
			vec4 za = gz_a[zi];
			vec4 zb = gz_b[zi];
			// BM-01 (Kanta 20.10): w = 0 — зона задана в координатах мира (точка падения на рельефе) и ложится
			// по склонам; w = 1 — в координатах плоскости боя (проекция из камеры)
			vec2 q = gz_c[zi].w > 0.5 ? cp : world3.xz;
			vec2 ab = za.zw - za.xy;
			float h = clamp(dot(q - za.xy, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
			vec2 dv = q - za.xy - ab * h;
			float d = length(dv);
			float r = zb.x;
			if (d > r * 1.15 + 8.0) continue;
			float fw = max(fwidth(d), 0.05);
			vec3 zc = gz_c[zi].rgb;
			float a = zb.y;
			if (zb.z > 2.5) {
				// огонь: тлеющие угли с мерцанием, край рваный
				float n = vnoise(cp / 18.0 + zb.w + vec2(gz_time * 0.7, -gz_time * 0.4));
				float n2 = vnoise(cp / 16.0 - zb.w + vec2(-gz_time * 0.9, gz_time * 0.6)) * 0.65
					+ vnoise(cp / 6.0 + zb.w + vec2(gz_time * 1.4, 0.0)) * 0.35;
				float edge = 1.0 - smoothstep(r * (0.55 + 0.35 * n), r * (0.75 + 0.35 * n), d);
				// гарь с тлеющими прожилками: светятся только «трещины» шума, остальное — тёмная гарь с лёгким жаром
				float ember = smoothstep(0.42, 0.78, n2) * edge;
				alb = mix(alb, alb * vec3(0.2, 0.18, 0.16), edge * 0.8 * a);
				gz_e += zc * (ember * 1.1 + edge * 0.1) * a;
			} else {
				// S9-26 (Kanta: «прицел всё ещё как будто в воздухе»): метка нарисована краской на земле — толщина
				// кольца в метрах мира (сжимается на склонах и с перспективой), цвет — в альбедо под светом и тенями
				// рельефа; свечение слабое, только чтобы метку было видно в тени. Было: кольцо постоянной толщины
				// на экране и яркое свечение — читалось как наклейка интерфейса над землёй.
				float rw = max(r * 0.022, fw * 1.2);
				float ring = 1.0 - smoothstep(rw * 0.5, rw * 0.5 + fw * 1.2, abs(d - r));
				float fill = (1.0 - smoothstep(r - fw * 2.0, r, d)) * 0.22;
				float m = ring;
				if (zb.z < 1.5) {
					vec2 u = dv / max(d, 1e-3);
					float tick = step(0.993, max(abs(u.x), abs(u.y))) * step(r * 0.8, d) * step(d, r);
					float dot_c = 1.0 - smoothstep(rw * 0.9, rw * 0.9 + fw * 1.5, d);
					m = max(m, max(tick * 0.9, dot_c));
				}
				m = clamp(m, 0.0, 1.0) * a;
				// заливка — притенение земли внутри зоны (как пятно), кольцо и засечки — краска цвета метки
				alb *= 1.0 - fill * a;
				// краска пропускает рисунок земли: камни и трещины видны сквозь метку
				float lum = dot(alb, vec3(0.333));
				alb = mix(alb, zc * (0.45 + lum * 1.6), m * 0.85);
				gz_e += zc * m * 0.18;
			}
		}
	}
	ALBEDO = alb;
	// M-36: отражённый от долины свет на крутых склонах (у GL Compatibility нет GI — тень иначе почти чёрная)
	EMISSION = alb * slope_fill * smoothstep(0.12, 0.55, 1.0 - wnorm.y) + gz_e + sea_e;
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
	ROUGHNESS = mix(0.95, sea ? 0.62 : 0.3, wet_out);   // «Архипелаг»: широкая вода — без слепящего пятна солнца
	SPECULAR = mix(0.1, sea ? 0.2 : 0.35, wet_out);   // без неба для отражений сильный блеск давал чёрную воду
}
