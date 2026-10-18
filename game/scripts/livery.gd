class_name Livery
## Тест 3.5-s4 (второй список), п. 35 (Kanta): выбор окраски самолёта — по 3 варианта к текущей на класс.
## Без новых текстур: каждой поверхности своего самолёта (модель ангара или боя + механизация, детали,
## створки, кормовая кабина) ставится ShaderMaterial поверх её же albedo / normal / ORM-текстур (или вершинного
## цвета у деталей). Яркость исходной текстуры даёт рисунок камуфляжа (тёмные пятна / основной тон / светлые
## пятна → цвета палитры) и мелкие детали (швы, панели); очень тёмное (сопла, ниши) не трогается.
## Стекло фонаря (тест 3.5-s5, п. 2) — отдельная поверхность «glass» (ShaderMaterial shaders/canopy_glass.tres,
## tools/blender/canopy_glass.py): одно на все окраски, здесь не перекрашивается.
## «Леопард» и «Тигр» — процедурный узор в осях модели (нос +X, верх +Y), «Классика» «Кита» и «Чёрный с красным» —
## раскладка по верху / низу и по габариту модели. Глянец — низкая шероховатость, мат — высокая.
## Один проход, без compute — GL Compatibility. Вариант без цветов — исходная окраска модели (шейдер не ставится).
## Свои знаки (Insignia) и полосы ведомых не перекрашиваются; ведомые — всегда в своей окраске.

## id → [название, тёмный, основной, светлый, шероховатость, металл, узор, цвет узора A, цвет узора B]
## Узоры: 0 — нет, 1 — леопард, 2 — тигр, 3 — верх белый, низ голубой, синие полоса по борту, киль и законцовки; 4 — красные нос, законцовки, киль;
## 5 — разрывной камуфляж: основной (песок) / тёмный (охра) / узор A (тёмно-оливково-бурый) крупными пятнами с чёткими краями,
##     узор B — светлое брюхо (тест 3.5-s6, С-1, решение Kanta 18.10: свой «Грач» и «Кит» читаются на бежевой земле);
## 6 — тёмные законцовки крыльев и стабилизатора (узор A), светлое брюхо (узор B)
## Первый вариант — окраска по умолчанию (профиль без выбора, ""); у «Грача» и «Кита» это «Песочный камуфляж»,
## исходная окраска модели («Камуфляж» / «Песок», без шейдера) — по своему id, выбор в профиле сохраняется.
const SAND_CAMO := ["sand_camo", "Песочный камуфляж", Color(0.60, 0.37, 0.18), Color(0.85, 0.77, 0.58), Color(0.91, 0.85, 0.70), 0.7, 0.05, 5,
	Color(0.19, 0.17, 0.10), Color(0.76, 0.81, 0.84)]
## «Хаки» на бежевой земле сливается (С-1, п. 2): тёмные законцовки крыльев и стабилизатора, светлое брюхо (узор 6)
const KHAKI := ["khaki", "Хаки", Color(0.36, 0.35, 0.23), Color(0.45, 0.43, 0.29), Color(0.52, 0.50, 0.35), 0.78, 0.05, 6,
	Color(0.13, 0.13, 0.09), Color(0.70, 0.73, 0.68)]
const VARIANTS := {
	"fighter": [
		["classic", "Классика"],
		["sand", "Песок", Color(0.56, 0.43, 0.29), Color(0.80, 0.69, 0.50), Color(0.88, 0.80, 0.63), 0.62, 0.05, 0],
		["black_gloss", "Чёрный глянец", Color(0.05, 0.05, 0.056), Color(0.075, 0.075, 0.082), Color(0.12, 0.12, 0.13), 0.14, 0.3, 0],
		["pink_leopard", "Розовый леопард", Color(0.86, 0.52, 0.64), Color(0.96, 0.62, 0.74), Color(1.0, 0.74, 0.83), 0.55, 0.05, 1,
			Color(0.22, 0.07, 0.13), Color(0.80, 0.36, 0.50)],
	],
	"attacker": [
		SAND_CAMO,
		["camo", "Камуфляж"],
		KHAKI,
		["black_matte", "Чёрный мат", Color(0.05, 0.05, 0.05), Color(0.085, 0.085, 0.085), Color(0.12, 0.12, 0.115), 0.95, 0.0, 0],
		["tiger", "Тигр", Color(0.78, 0.42, 0.10), Color(0.88, 0.50, 0.14), Color(0.93, 0.58, 0.20), 0.6, 0.05, 2,
			Color(0.05, 0.04, 0.035), Color(0.92, 0.86, 0.72)],
	],
	"bomber": [
		SAND_CAMO,
		["sand", "Песок"],
		["classic", "Классика", Color(0.80, 0.82, 0.84), Color(0.92, 0.93, 0.94), Color(0.96, 0.96, 0.97), 0.42, 0.1, 3,
			Color(0.16, 0.36, 0.68), Color(0.55, 0.72, 0.90)],
		KHAKI,
		["black_red", "Чёрный с красным", Color(0.04, 0.04, 0.045), Color(0.07, 0.07, 0.075), Color(0.11, 0.11, 0.115), 0.42, 0.25, 4,
			Color(0.78, 0.07, 0.05), Color(0.0, 0.0, 0.0)],
	],
}

## Исходная окраска модели: [яркость основного тона (линейная), ниже этой яркости — не трогать (фонарь, сопла)]
## по гистограммам текстур ангара (у моделей боя те же текстуры, уменьшенные)
const SRC := {
	"fighter_1": [0.42, 0.022], "fighter_2": [0.39, 0.022],
	"attacker_1": [0.056, 0.011], "attacker_2": [0.056, 0.011],
	"bomber_1": [0.079, 0.013], "bomber_2": [0.078, 0.013],
}

static var _shader: Shader
static var _force := ""   # стенд: --livery=<id> — окраска своего самолёта в бою, если у класса такая есть


## Список вариантов класса: [[id, название], …]; первый — по умолчанию
static func list(cls: String) -> Array:
	var out: Array = []
	for v: Array in VARIANTS.get(cls, []):
		out.append([v[0], v[1]])
	return out


static func _find(cls: String, id: String) -> Array:
	for v: Array in VARIANTS.get(cls, []):
		if v[0] == id:
			return v
	return []


## Выбранная окраска класса (из профиля; стенд --livery=… сильнее)
static func current(cls: String) -> String:
	if _force == "":
		_force = "-"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--livery="):
				_force = a.get_slice("=", 1)
	if _force != "-" and not _find(cls, _force).is_empty():
		return _force
	var id := Profile.livery(cls)
	if _find(cls, id).is_empty():
		var l: Array = VARIANTS.get(cls, [[""]])
		return String(l[0][0])
	return id


## Перекрасить модель самолёта (корень модели ангара или боевой; key — «fighter_1» и т. п.). Звать после того,
## как подвешены механизация, детали, створки и кормовая кабина. Исходная окраска (вариант без цветов) — ничего не делает.
static func apply(model: Node3D, cls: String, lvl: int, id: String) -> void:
	var v := _find(cls, id)
	if v.size() < 8:
		return
	var key := "%s_%d" % [cls, lvl]
	var src: Array = SRC.get(key, [0.1, 0.012])
	# основной меш (текстура Meshy) — по нему габарит модели для узоров
	var box := AABB()
	var body: Array = []
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if _skip(mi, model):
			continue
		var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
		if m != null and m.albedo_texture != null:
			var xf := _rel(mi, model)
			var bb := xf * mi.mesh.get_aabb()
			box = bb if body.is_empty() else box.merge(bb)
			body.append(mi)
	if body.is_empty():
		return
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if _skip(mi, model):
			continue
		var xf := _rel(mi, model)
		for si in mi.mesh.get_surface_count():
			# вид поверхности — по имени материала в GLB (у механизации поверх стоит общий материал WingMech)
			var m0 := mi.mesh.surface_get_material(si)
			var m := mi.get_surface_override_material(si)
			var sm := _material(m if m != null else m0, String(m0.resource_name) if m0 != null else "", v, src, xf, box)
			if sm != null:
				mi.set_surface_override_material(si, sm)


## Перекрашиваем модель и подвешенные к ней механизацию, детали, створки, кормовую кабину;
## знаки, модули прокачки и полосы ведомых — нет
static func _skip(mi: MeshInstance3D, model: Node3D) -> bool:
	var n: Node = mi
	while n != null and n != model:
		if String(n.name) in ["insignia", "module_parts", "wing_kit"]:
			return true
		n = n.get_parent()
	return false


## Преобразование меша в оси модели (без собственного масштаба корня модели в бою)
static func _rel(mi: Node3D, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _material(m: Material, nm: String, v: Array, src: Array, xf: Transform3D, box: AABB) -> ShaderMaterial:
	var bm := m as BaseMaterial3D
	if bm == null or nm == "glass":
		return null                     # стекло фонаря (ShaderMaterial «glass») — одно на все окраски
	var mode := -1
	if bm.albedo_texture != null:
		mode = 0                        # обшивка Meshy: текстуры
	elif nm.begins_with("mech_skin"):
		mode = 1                        # механизация, створки, кормовая кабина: вершинный цвет (снят с текстуры)
	elif nm.begins_with("detail_") and not nm.begins_with("detail_dark"):
		mode = 2                        # детали силуэта: цвет материала
	if mode < 0:
		return null                     # швы, стекло, ниши, тёмные детали — как есть
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	sm.set_shader_parameter("src_mode", mode)
	if mode == 0:
		sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
		sm.set_shader_parameter("has_normal", bm.normal_texture != null)
		if bm.normal_texture != null:
			sm.set_shader_parameter("normal_tex", bm.normal_texture)
			sm.set_shader_parameter("normal_scale", bm.normal_scale)
		var orm := bm.roughness_texture
		sm.set_shader_parameter("has_orm", orm != null)
		if orm != null:
			sm.set_shader_parameter("orm_tex", orm)
	else:
		sm.set_shader_parameter("src_color", bm.albedo_color)
		sm.set_shader_parameter("src_rough", bm.roughness)
	sm.set_shader_parameter("vcol_mul", 1.3 if mode == 1 else 1.0)
	sm.set_shader_parameter("l_base", float(src[0]))
	sm.set_shader_parameter("l_keep", float(src[1]))
	sm.set_shader_parameter("c_dark", v[2])
	sm.set_shader_parameter("c_mid", v[3])
	sm.set_shader_parameter("c_light", v[4])
	sm.set_shader_parameter("liv_rough", float(v[5]))
	sm.set_shader_parameter("liv_metal", float(v[6]))
	sm.set_shader_parameter("pattern", int(v[7]))
	if v.size() > 9:
		sm.set_shader_parameter("pat_a", v[8])
		sm.set_shader_parameter("pat_b", v[9])
	sm.set_shader_parameter("to_model", Projection(xf))
	sm.set_shader_parameter("box_min", box.position)
	sm.set_shader_parameter("box_size", box.size)
	return sm


const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int src_mode = 0;   // 0 — текстуры, 1 — вершинный цвет, 2 — цвет материала
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform float normal_scale = 1.0;
uniform vec4 src_color : source_color = vec4(1.0);
uniform float src_rough = 0.6;
uniform float vcol_mul = 1.0;
uniform float l_base = 0.1;
uniform float l_keep = 0.012;
uniform vec3 c_dark : source_color;
uniform vec3 c_mid : source_color;
uniform vec3 c_light : source_color;
uniform float liv_rough = 0.6;
uniform float liv_metal = 0.05;
uniform int pattern = 0;
uniform vec3 pat_a : source_color;
uniform vec3 pat_b : source_color;
uniform mat4 to_model = mat4(1.0);
uniform vec3 box_min = vec3(-0.5);
uniform vec3 box_size = vec3(1.0);

const float CAMO_DARK = 0.52;
const float CAMO_OCHRE = 0.53;

varying vec3 lp;
varying vec3 ln;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), u.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0)), u.x), u.y);
	return mix(a, b, u.z);
}
// крупные пятна с неровным краем: основная частота + мелкая рябь края
float blobs(vec3 p) {
	return 0.62 * vnoise3(p) + 0.28 * vnoise3(p * 2.1 + 7.3) + 0.10 * vnoise3(p * 4.7 + 3.1);
}
vec2 hash22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// плоскость узора по преобладающей оси нормали: сверху — (x, z), борт — (x, y), торец — (z, y)
vec2 plane_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y >= a.x && a.y >= a.z) return p.xz;
	if (a.z >= a.x) return p.xy;
	return p.zy;
}

// леопард: розетки — разорванное тёмное кольцо, внутри чуть темнее основы; между ними мелкие пятна
vec2 leopard(vec2 uv) {
	vec2 g = uv * 12.0;
	vec2 i = floor(g); vec2 f = fract(g);
	float d1 = 9.0; vec2 dv = vec2(0.0); float hid = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = hash22(i + o);
			vec2 r = o + 0.15 + 0.7 * h - f;
			float d = dot(r, r);
			if (d < d1) { d1 = d; dv = r; hid = h.x; }
		}
	}
	float d = sqrt(d1) * (0.85 + 0.3 * vnoise(uv * 60.0));
	float rad = 0.30 + 0.08 * hid;
	float ang = atan(dv.y, dv.x);
	float gaps = smoothstep(-0.75, -0.35, sin(ang * 3.0 + hid * 40.0) + 0.35 * vnoise(uv * 40.0));
	float ring = smoothstep(rad - 0.15, rad - 0.10, d) * (1.0 - smoothstep(rad + 0.03, rad + 0.08, d)) * gaps;
	float inner = 1.0 - smoothstep(rad - 0.16, rad - 0.11, d);
	return vec2(ring, inner);
}

// тигр: изогнутые поперечные полосы, к концам сужаются
float tiger(vec3 p) {
	float w = vnoise(p.xz * 4.0 + p.y * 3.0) * 1.4 + vnoise(p.xz * 11.0) * 0.45;
	float s = p.x * 15.0 + abs(p.z) * 5.0 + w + p.y * 3.0;
	float tri = abs(fract(s) - 0.5);
	// ширина полосы меняется вдоль неё — к концам сужается до нуля (рваный «клин»)
	float along = vnoise(vec2(floor(s) * 5.1, 0.0) + vec2(abs(p.z) * 7.0 + p.y * 8.0, p.x * 3.0));
	float width = 0.24 * smoothstep(0.25, 0.75, along) + 0.03 * vnoise(p.xz * 30.0);
	return 1.0 - smoothstep(width - 0.03, width, tri);
}

void vertex() {
	lp = (to_model * vec4(VERTEX, 1.0)).xyz;
	ln = normalize((to_model * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 src;
	float rough0 = src_rough;
	if (src_mode == 0) {
		src = texture(albedo_tex, UV).rgb;
		if (has_orm) {
			rough0 = texture(orm_tex, UV).g;
		}
		if (has_normal) {
			NORMAL_MAP = texture(normal_tex, UV).rgb;
			NORMAL_MAP_DEPTH = normal_scale;
		}
	} else if (src_mode == 1) {
		src = COLOR.rgb * vcol_mul;
	} else {
		src = src_color.rgb;
	}
	float l = dot(src, vec3(0.2126, 0.7152, 0.0722));
	float t = l / l_base;
	// полосы яркости исходного камуфляжа → тёмный / основной / светлый тон варианта
	float wd = 1.0 - smoothstep(0.45, 0.75, t);
	float wl = smoothstep(1.35, 1.8, t);
	vec3 col = mix(mix(c_mid, c_dark, wd), c_light, wl);
	// мелкие детали (швы, панели, грязь) — отклонение от середины своей полосы, приглушённо
	float centre = mix(mix(1.0, 0.3, wd), 2.4, wl);
	col *= mix(1.0, clamp(t / centre, 0.7, 1.25), 0.5);
	vec3 q = (lp - box_min) / box_size;   // 0…1 по габариту: x — хвост→нос, y — низ→верх, z — левое→правое крыло
	if (pattern == 1) {
		vec2 lr = leopard(plane_uv(lp, ln));
		col = mix(col, pat_b * mix(1.0, clamp(t / centre, 0.8, 1.15), 0.5), lr.y * 0.8);
		col = mix(col, pat_a, lr.x);
	} else if (pattern == 2) {
		float belly = smoothstep(-0.15, -0.55, ln.y);
		col = mix(col, pat_b, belly);
		col = mix(col, pat_a, tiger(lp) * (1.0 - belly * 0.85));
	} else if (pattern == 3) {
		// бело-голубая «классика»: низ голубой, по борту синяя полоса, киль синий
		float under = smoothstep(-0.05, -0.4, ln.y);
		col = mix(col, pat_b * mix(1.0, clamp(t / centre, 0.8, 1.15), 0.5), under);
		float side = smoothstep(0.55, 0.8, abs(ln.z)) * (1.0 - smoothstep(0.55, 0.8, abs(ln.y)));
		float band = (1.0 - smoothstep(0.04, 0.05, abs(q.y - 0.5))) * side * step(0.06, q.x);
		float fin = smoothstep(0.66, 0.72, q.y) * (1.0 - smoothstep(0.32, 0.4, q.x));
		float tips = smoothstep(0.41, 0.42, abs(q.z - 0.5));   // законцовки крыльев — видно сверху, из камеры боя
		col = mix(col, pat_a, max(max(band, fin), tips));
	} else if (pattern == 4) {
		// чёрный с красным: нос, законцовки крыльев, верх киля
		float nose = smoothstep(0.915, 0.93, q.x);
		float tips = smoothstep(0.43, 0.445, abs(q.z - 0.5));
		float fin = smoothstep(0.80, 0.82, q.y);
		float red = max(max(nose, tips), fin);
		col = mix(col, pat_a * mix(1.0, clamp(t / centre, 0.8, 1.2), 0.4), red);
	} else if (pattern == 5) {
		// разрывной камуфляж в осях модели: охра и тёмные пятна поверх песка, края чёткие (сглаживание — на пиксель)
		float a = blobs(lp * vec3(7.5, 7.5, 7.5) + vec3(3.1, 0.0, 1.7));
		float b = blobs(lp * vec3(8.0, 8.0, 8.0) + vec3(-8.3, 4.2, 2.9));
		float aw = fwidth(a) + 0.002;
		float bw = fwidth(b) + 0.002;
		float dk = smoothstep(CAMO_DARK - aw, CAMO_DARK + aw, a);
		float oc = smoothstep(CAMO_OCHRE - bw, CAMO_OCHRE + bw, b);
		vec3 cam = mix(mix(c_mid, c_dark, oc), pat_a, dk);
		// светлое брюхо (видно на кренах и разворотах)
		float belly = smoothstep(-0.18, -0.32, ln.y);
		cam = mix(cam, pat_b, belly);
		col = cam * mix(1.0, clamp(t / centre, 0.8, 1.15), 0.5);
	} else if (pattern == 6) {
		float belly = smoothstep(-0.18, -0.32, ln.y);
		col = mix(col, pat_b * mix(1.0, clamp(t / centre, 0.8, 1.15), 0.5), belly);
		float tips = smoothstep(0.375, 0.385, abs(q.z - 0.5));
		float htail = smoothstep(0.215, 0.225, abs(q.z - 0.5)) * (1.0 - smoothstep(0.12, 0.13, q.x));
		col = mix(col, pat_a, max(tips, htail) * (1.0 - belly));
	}
	// очень тёмное (фонарь, сопла, ниши) — исходный цвет
	float keep = 1.0 - smoothstep(l_keep * 0.6, l_keep, l);
	ALBEDO = mix(col, src, keep);
	ROUGHNESS = mix(clamp(liv_rough + (rough0 - 0.6) * 0.25, 0.05, 1.0), rough0, keep);
	METALLIC = liv_metal * (1.0 - keep);
}
"""
