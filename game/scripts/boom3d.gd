class_name Boom3D
extends Node3D
## 3.5: объёмные 3D-взрывы. До этого взрыв был 2D-картинкой на плоскости боя (плоские круги, п. 33 теста 3.4-t1).
## Теперь каждый взрыв — частицы в 3D-мире: огненный шар (сфера с шумом, клубится и выгорает),
## огненные клубы, дым с самозатенением (поднимается к камере и сносится ветром), искры по скорости,
## обломки-модели с тенью (кувыркаются, дымят, падают на рельеф), сферическая ударная волна,
## пыльная волна по земле, грибовидный столб дыма и догорающий огонь у наземных целей.
## Виды: flak (подрыв ракеты, перехват), air (сбит в воздухе), big (крупная цель, игрок), ground (наземная цель,
## падение самолёта), blast (бомбы и НАР по площади). Всё рисуется семью MultiMesh — один вызов отрисовки на слой.
## Текстура клубов и сетки строятся кодом — без файлов-ассетов. Fx.explosion() сам выбирает 3D или старый 2D.

static var I: Boom3D

enum { L_SMOKE, L_FIRE, L_CORE, L_DEBRIS, L_SPARK, L_SHOCK, L_FLASH }
const CAP := [1800, 1000, 140, 420, 1000, 60, 90]
const WIND := Vector3(22.0, 0.0, -6.0)
const STRIDE := 20
const BUDGET := [500.0, 800.0, 1200.0, 1600.0]   # частиц, после которых новые взрывы беднеют   # transform 12 + color 4 + custom 4

static var _puff: ImageTexture

var _mm: Array = []
var _parts: Array = [[], [], [], [], [], [], []]
var _buf: Array = []
var _emit: Array = []       # догорающие очаги
var _later: Array = []      # отложенные вспышки (цепочки у крупных)
var _lights: Array = []
var _light_i := 0
var _cam_f := Vector3.DOWN
var _q := 1.0               # множитель числа частиц по «Качеству графики»
var stats_peak := 0         # для лога: пик частиц за вылет
var stats_us := 0           # время последнего кадра обновления, мкс (процессор)


# ---------- шейдеры ----------

const COMMON := """
float hash3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; } return s / 0.9375; }
// температура → цвет огня: копоть → тёмно-красный → оранжевый → жёлтый → белое ядро (HDR, тонмаппинг сжимает)
vec3 ramp(float h) {
	h = clamp(h, 0.0, 1.0) * 4.0;
	vec3 c0 = vec3(0.05, 0.035, 0.03); vec3 c1 = vec3(0.55, 0.07, 0.015); vec3 c2 = vec3(1.7, 0.5, 0.07);
	vec3 c3 = vec3(2.1, 1.05, 0.26); vec3 c4 = vec3(2.7, 2.2, 1.5);
	if (h < 1.0) return mix(c0, c1, h);
	if (h < 2.0) return mix(c1, c2, h - 1.0);
	if (h < 3.0) return mix(c2, c3, h - 2.0);
	return mix(c3, c4, h - 3.0);
}
"""

## Плоская частица, всегда лицом к камере; поворот — INSTANCE_CUSTOM.x, размер — масштаб экземпляра
const BILLBOARD := """
varying vec4 cd;
void vertex() {
	cd = INSTANCE_CUSTOM;
	float c = cos(cd.x); float s = sin(cd.x);
	mat4 mw = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
vec2 tile_uv(vec2 uv) { vec2 t = vec2(mod(cd.z, 2.0), floor(cd.z * 0.5 + 0.01)); return (uv * 0.94 + 0.03 + t) * 0.5; }
"""

## Огненный клуб: шум выгорает от центра к краю (порог растёт с возрастом), температура падает
const FIRE_SH := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D puff : filter_linear_mipmap, repeat_disable;
%s
%s
void fragment() {
	vec4 t = texture(puff, tile_uv(UV));
	float age = cd.y;
	float d = t.r * (0.8 + 0.4 * t.g);
	float a = smoothstep(age * 0.85, age * 0.85 + 0.4, d);
	float heat = clamp(cd.w * (1.0 - age * 0.9) + (d - 0.45) * 0.9, 0.0, 1.0);
	ALBEDO = ramp(heat) * COLOR.rgb;
	ALPHA = a * COLOR.a;
}
"""

## Дым: самозатенение (сравнение плотности со сдвигом к солнцу), снизу подсвечен огнём, пока свежий
const SMOKE_SH := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D puff : filter_linear_mipmap, repeat_disable;
%s
%s
void fragment() {
	vec2 uv = tile_uv(UV);
	vec4 t = texture(puff, uv);
	float c = cos(-cd.x); float s = sin(-cd.x);
	vec2 ld = vec2(c * -0.62 - s * -0.78, s * -0.62 + c * -0.78);
	float d2 = texture(puff, uv + ld * 0.035).r;
	float d = t.r;
	float lit = clamp(0.85 + (d - d2) * 5.0 - (1.0 - d) * 0.2, 0.35, 1.45);
	float age = cd.y;
	float a = smoothstep(age * 0.55, age * 0.55 + 0.6, d * (0.85 + 0.3 * t.g));
	vec3 col = COLOR.rgb * lit + vec3(0.1, 0.095, 0.085) * clamp(lit - 0.9, -0.5, 0.5);
	col += ramp(cd.w * (0.4 + d * 0.8)) * cd.w * smoothstep(0.2, 0.8, d);
	ALBEDO = col;
	ALPHA = a * COLOR.a;
}
"""

## Огненный шар: сфера, вершины сдвинуты шумом (клубится), край темнее и выгорает раньше центра
const CORE_SH := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
%s
varying vec4 cd;
varying float vn;
varying vec3 lp;
void vertex() {
	cd = INSTANCE_CUSTOM;
	vec3 q = VERTEX * 1.6 + vec3(cd.y * 13.1, cd.y * 7.3 - cd.x * 1.2, -cd.y * 5.7);
	float n = fbm(q);
	vn = n;
	VERTEX += NORMAL * (n - 0.5) * (0.55 + 0.35 * cd.x);
	lp = VERTEX * 2.6 + vec3(cd.y * 11.0);
}
void fragment() {
	float age = cd.x;
	float n2 = fbm(lp + vec3(0.0, age * 2.5, age * 1.3));
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float heat = clamp(cd.z * (1.0 - age * 1.35) + (vn - 0.5) * 0.7 + (n2 - 0.5) * 0.8 - fres * 0.5 + 0.12, 0.0, 1.0);
	float body = n2 * 0.55 + vn * 0.45 + (1.0 - fres) * 0.25;
	float a = smoothstep(age * 1.05 - 0.05, age * 1.05 + 0.18, body);
	ALBEDO = ramp(heat) * COLOR.rgb;
	ALPHA = a * COLOR.a;
}
"""

## Искра: полоска вдоль скорости (поворот считается на процессоре), складывается со светом
const SPARK_SH := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	float w = 1.0 - abs(UV.y * 2.0 - 1.0);
	float a = w * w * smoothstep(0.0, 0.7, UV.x);
	ALBEDO = COLOR.rgb * 2.2;
	ALPHA = a * COLOR.a;
}
"""

## Вспышка: мягкий диск, складывается со светом
const FLASH_SH := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
%s
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = COLOR.rgb * 2.0;
	ALPHA = a * COLOR.a;
}
"""

## Ударная волна: прозрачная сфера, светится только край — объёмный «пузырь», а не круг на земле
const SHOCK_SH := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
%s
varying vec4 cd;
varying vec3 lp;
void vertex() { cd = INSTANCE_CUSTOM; lp = VERTEX * 3.0 + vec3(cd.y); }
void fragment() {
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	float n = fbm(lp + vec3(cd.x * 4.0));
	float a = (pow(f, 2.0) * 0.6 + 0.15) * smoothstep(0.35, 0.75, n);
	ALBEDO = COLOR.rgb;
	ALPHA = a * COLOR.a;
}
"""

## Обломки и комья земли: освещаются солнцем, бросают тень; пока горячие — светятся
const DEBRIS_SH := """
shader_type spatial;
render_mode cull_disabled;
%s
varying vec4 cd;
void vertex() { cd = INSTANCE_CUSTOM; }
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	METALLIC = cd.y;
	EMISSION = ramp(cd.x) * cd.x * 1.6;
}
"""


static func active() -> bool:
	return Render3D.I != null and Render3D.enabled and Tuning.g("fx3d") > 0.5 and not OS.get_cmdline_user_args().has("--nofx")


static func ensure() -> Boom3D:
	if I == null or not is_instance_valid(I):
		I = Boom3D.new()
		Render3D.I.add_child(I)
	return I


func _ready() -> void:
	if _puff == null:
		_puff = _make_puff()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	var shock := SphereMesh.new()
	shock.radius = 1.0
	shock.height = 2.0
	shock.radial_segments = 32
	shock.rings = 16
	var meshes := [quad, quad, sphere, _make_shard(), quad, shock, quad]
	var codes := [SMOKE_SH % [COMMON, BILLBOARD], FIRE_SH % [COMMON, BILLBOARD], CORE_SH % COMMON, DEBRIS_SH % COMMON,
		SPARK_SH, SHOCK_SH % COMMON, FLASH_SH % BILLBOARD]
	var prio := [1, 3, 2, 0, 5, 4, 6]
	for L in 7:
		var sh := Shader.new()
		sh.code = codes[L]
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.render_priority = prio[L]
		if L == L_SMOKE or L == L_FIRE:
			mat.set_shader_parameter("puff", _puff)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[L]
		mm.instance_count = CAP[L]
		mm.visible_instance_count = 0
		mm.custom_aabb = AABB(Vector3(-1e6, -1e4, -1e6), Vector3(2e6, 2e4, 2e6))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.custom_aabb = mm.custom_aabb
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if L == L_DEBRIS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mm.append(mm)
		var b := PackedFloat32Array()
		b.resize(CAP[L] * STRIDE)
		_buf.append(b)
	for i in 6:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.25)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append({"l": l, "t": 0.0, "max": 0.0, "e": 0.0})


# ---------- текстура и сетки ----------

## Атлас 2×2 клубов 128 px: R — плотность (круг × шум, рваный «живой» край), G — мелкий шум для выгорания
static func _make_puff() -> ImageTexture:
	var T := 128
	var img := Image.create(T * 2, T * 2, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.028
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n2.frequency = 0.06
	var c := (T - 1) / 2.0
	for tile in 4:
		n.seed = 101 + tile * 37
		n2.seed = 7 + tile * 13
		var ox := (tile % 2) * T
		var oy := (tile / 2) * T
		for y in T:
			for x in T:
				var v := Vector2(x - c, y - c) / c
				var d := v.length()
				var nz := n.get_noise_2d(x + ox * 3.0, y + oy * 3.0) * 0.5 + 0.5
				# клубы: крупные «кочаны» — ячеистый шум, инвертированный
				var cell := 1.0 - clampf(n2.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
				# край рваный: шум сильнее радиального спада у края — силуэт не круглый
				var dens := (1.0 - d) * 1.35 + (nz - 0.5) * 1.5 * (0.3 + d) + (cell - 0.5) * 0.45
				dens *= clampf((1.0 - d) * 2.5, 0.0, 1.0)
				img.set_pixel(ox + x, oy + y, Color(clampf(dens, 0.0, 1.0), nz, cell, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Осколок: неровный восьмигранник с плоскими гранями
static func _make_shard() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pts := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for i in pts.size():
		pts[i] = pts[i] * rng.randf_range(0.55, 1.25) + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[1]]
		var cc: Vector3 = pts[f[2]]
		var nrm := (b - a).cross(cc - a).normalized()
		for p in [a, b, cc]:
			st.set_normal(nrm)
			st.add_vertex(p)
	return st.commit()


# ---------- запуск взрыва ----------

## pos — точка плоскости боя (2D), s — радиус «ядра» в пикселях (как в Fx.explosion после масштаба)
func spawn(pos: Vector2, s: float, air: bool, kind := "") -> void:
	var R := Render3D.I
	if R == null or R.cam == null:
		return
	# частиц меньше на слабом пресете и когда их уже много (мясорубка): нагрузка не растёт без предела
	var gi := clampi(Settings.gfx, 0, 3)
	_q = [0.45, 0.7, 1.0, 1.25][gi] * clampf(1.25 - float(count()) / BUDGET[gi], 0.3, 1.0)
	if kind == "":
		if not air:
			kind = "ground"
		elif s < 18.0:
			kind = "flak"
		elif s >= 50.0:
			kind = "big"
		else:
			kind = "air"
	if kind == "ground" or kind == "blast":
		# на земле: та точка рельефа, что на экране под pos; размер — с поправкой на перспективу,
		# чтобы на экране взрыв совпадал с зоной поражения
		var g := R.ground_under(pos)
		var ch := R.cam.global_position.y
		var k := clampf((ch - g.y) / maxf(ch, 1.0), 0.5, 3.0)
		if kind == "ground":
			_ground(g, s * k * 1.3)
		else:
			_blast(g, s * k)
	elif kind == "flak":
		_flak(Vector3(pos.x, 0.0, pos.y), s)
	elif kind == "big":
		_big(Vector3(pos.x, 0.0, pos.y), s)
	else:
		_air(Vector3(pos.x, 0.0, pos.y), s, true)


func _n(base: float) -> int:
	return maxi(1, int(round(base * _q)))


static func _rdir(up := 0.0) -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1) + up, randf_range(-1, 1))
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.UP


## Все поля движения заданы заранее — в цикле кадра без проверок get()
const DEFAULTS := {"t": 0.0, "b": 0.0, "g": 0.0, "drag": 0.0, "wind": 0.0, "rot": 0.0, "spin": 0.0}


func _add(L: int, q: Dictionary) -> void:
	var arr: Array = _parts[L]
	if arr.size() >= CAP[L]:
		arr.pop_front()
	q.merge(DEFAULTS)
	arr.append(q)


func _flash(p: Vector3, r: float, life: float, c := Color(1.0, 0.85, 0.6, 0.9)) -> void:
	_add(L_FLASH, {"p": p, "v": Vector3.ZERO, "life": life, "r0": r * 0.6, "r1": r, "c": c})


func _core(p: Vector3, r0: float, r1: float, life: float, heat := 1.0, squash := 1.0, delay := 0.0) -> void:
	_add(L_CORE, {"p": p, "v": Vector3.ZERO, "life": life, "r0": r0, "r1": r1, "h": heat, "seed": randf() * 50.0, "sq": squash,
		"t": -delay, "c": Color(1, 1, 1, 1)})


func _fire(p: Vector3, v: Vector3, r0: float, r1: float, life: float, heat := 1.0, buoy := 0.0, delay := 0.0) -> void:
	_add(L_FIRE, {"p": p, "v": v, "life": life, "r0": r0, "r1": r1, "h": heat, "b": buoy, "drag": 3.0, "g": 0.0,
		"rot": randf() * TAU, "spin": randf_range(-1.5, 1.5), "tile": randi() % 4, "t": -delay, "c": Color(1, 1, 1, 1)})


func _smoke(p: Vector3, v: Vector3, r0: float, r1: float, life: float, col: Color, glow := 0.0, buoy := 10.0, drag := 1.2, delay := 0.0) -> void:
	_add(L_SMOKE, {"p": p, "v": v, "life": life, "r0": r0, "r1": r1, "glow": glow, "b": buoy, "drag": drag, "g": 0.0,
		"rot": randf() * TAU, "spin": randf_range(-0.5, 0.5), "tile": randi() % 4, "t": -delay, "c": col, "wind": 1.0,
		"fade": 0.4 if col.r < 0.18 else 0.0})


func _sparks(p: Vector3, n: int, speed: float, life: float, col := Color(1.0, 0.72, 0.3, 1.0), up := 0.0) -> void:
	for i in n:
		var c := col
		c.g *= randf_range(0.8, 1.15)
		_add(L_SPARK, {"p": p, "v": _rdir(up) * speed * randf_range(0.45, 1.0), "life": life * randf_range(0.5, 1.0),
			"g": 260.0, "drag": 1.6, "c": c, "w": randf_range(1.2, 2.4)})


## Обломок. trail: "" | "smoke" | "fire" (горит и дымит) | "dust"; burn — при падении на землю загорается очаг
func _debris(p: Vector3, v: Vector3, size: float, col: Color, heat: float, trail := "smoke", burn := false, metal := 0.4) -> void:
	_add(L_DEBRIS, {"p": p, "v": v, "life": 9.0, "sz": Vector3(randf_range(0.6, 1.4), randf_range(0.25, 0.6), randf_range(0.5, 1.2)) * size,
		"ax": _rdir(), "ang": randf() * TAU, "w": randf_range(-9.0, 9.0), "h": heat, "trail": trail, "tt": 0.0, "burn": burn,
		"c": col, "metal": metal, "gy": -INF, "gt": 0.0, "landed": false, "g": 520.0, "drag": 0.35})


func _light(p: Vector3, energy: float, rng: float, life: float) -> void:
	var slot: Dictionary = _lights[_light_i % _lights.size()]
	_light_i += 1
	var l: OmniLight3D = slot["l"]
	l.position = p
	l.omni_range = rng
	slot["e"] = energy
	slot["t"] = life
	slot["max"] = life
	l.light_energy = energy
	l.visible = true


# ---------- виды взрывов ----------

## Подрыв ракеты, перехват, самоликвидация: короткий огненный хлопок и чёрный клуб, как разрыв зенитного снаряда
func _flak(p: Vector3, s: float) -> void:
	s *= 1.25
	_flash(p, s * 3.2, 0.09)
	_core(p, s * 0.45, s * 1.25, 0.32, 1.0)
	for i in _n(4):
		var d := _rdir()
		_fire(p + d * s * 0.3, d * s * 2.2, s * 0.35, s * 0.85, randf_range(0.25, 0.45), 0.95)
	for i in _n(5):
		var d2 := _rdir()
		_smoke(p + d2 * s * 0.4, d2 * s * 0.9, s * 0.5, s * randf_range(1.6, 2.3), randf_range(1.8, 2.8),
			Color(0.11, 0.1, 0.095, 0.8), 0.7, 4.0, 1.5, randf_range(0.02, 0.1))
	_sparks(p, _n(12), 260.0 + s * 10.0, 0.35)


## Сбит в воздухе: огненный шар, клубы, дым, искры, горящие обломки падают на землю, объёмная ударная волна
func _air(p: Vector3, s: float, debris: bool) -> void:
	_flash(p, s * 3.6, 0.11)
	_core(p, s * 0.55, s * 1.65, 0.6, 1.0)
	_core(p + _rdir() * s * 0.35, s * 0.35, s * 1.1, 0.45, 0.9, 1.0, 0.06)
	_add(L_SHOCK, {"p": p, "v": Vector3.ZERO, "life": 0.22, "r0": s * 0.8, "r1": s * 4.2, "c": Color(1.0, 0.9, 0.75, 0.3), "seed": randf() * 40.0})
	var nf := _n(clampf(s / 3.0, 7.0, 14.0))
	for i in nf:
		var d := _rdir()
		_fire(p + d * s * 0.25, d * s * randf_range(1.8, 3.2), s * randf_range(0.35, 0.55), s * randf_range(0.9, 1.35),
			randf_range(0.4, 0.8), randf_range(0.6, 0.85), 6.0)
	for i in _n(clampf(s / 2.5, 9.0, 16.0)):
		var d2 := _rdir()
		var dark := i % 3 != 2
		var g := randf_range(0.09, 0.14) if dark else randf_range(0.28, 0.38)
		_smoke(p + d2 * s * 0.5, d2 * s * randf_range(0.5, 1.2), s * 0.55, s * randf_range(2.0, 2.9), randf_range(2.4, 3.8),
			Color(g, g * 0.96, g * 0.92, 0.7), 0.9 if dark else 0.3, 8.0, 1.2, randf_range(0.05, 0.25))
	_sparks(p, _n(clampf(s * 0.8, 14.0, 30.0)), 300.0 + s * 9.0, 0.55)
	if debris:
		for i in _n(clampf(s / 6.0, 3.0, 8.0)):
			var dv := _rdir(0.4) * randf_range(140.0, 320.0)
			var burning := i == 0 and s > 26.0
			_debris(p, dv, s * randf_range(0.1, 0.2) * (1.6 if burning else 1.0), Color(0.16, 0.15, 0.14), 1.0,
				"fire" if burning else "smoke", burning, 0.5)
	_light(p + Vector3(0, s * 2.0, 0), clampf(s / 9.0, 1.5, 6.0), clampf(s * 12.0, 200.0, 900.0), 0.4)


## Крупная цель или игрок: цепочка взрывов по корпусу, несколько горящих обломков до земли, большая волна
func _big(p: Vector3, s: float) -> void:
	_air(p, s, false)
	_add(L_SHOCK, {"p": p, "v": Vector3.ZERO, "life": 0.4, "r0": s * 1.0, "r1": s * 6.0, "c": Color(1.0, 0.85, 0.65, 0.22), "seed": randf() * 40.0})
	for i in randi_range(3, 4):
		var off := _rdir() * Vector3(1, 0.3, 1) * s * randf_range(0.6, 1.3)
		var ss := s * randf_range(0.4, 0.6)
		_later.append({"t": randf_range(0.08, 0.5), "p": p + off, "s": ss})
	for i in _n(randf_range(4.0, 6.0)):
		var dv := _rdir(0.3) * randf_range(120.0, 280.0)
		_debris(p, dv, s * randf_range(0.12, 0.2), Color(0.14, 0.13, 0.12), 1.0, "fire", true, 0.5)
	for i in _n(4):
		_debris(p, _rdir(0.3) * randf_range(180.0, 360.0), s * randf_range(0.06, 0.12), Color(0.18, 0.17, 0.16), 1.0, "smoke", false, 0.6)
	for i in _n(8):
		var d := _rdir()
		_smoke(p + d * s * 0.6, d * s * 0.6, s * 0.7, s * randf_range(2.8, 3.6), randf_range(4.0, 5.5),
			Color(0.1, 0.095, 0.09, 0.55), 0.8, 6.0, 1.0, randf_range(0.2, 0.6))


## Наземная цель или удар самолёта о землю: огненный шар у земли, грибовидный столб дыма, пыльная волна
## по рельефу, комья земли, догорающий очаг
func _ground(g: Vector3, s: float) -> void:
	var p := g + Vector3(0, s * 0.25, 0)
	_flash(p + Vector3(0, s * 0.5, 0), s * 3.4, 0.12)
	_core(p, s * 0.55, s * 1.6, 0.65, 1.0, 0.85)
	_core(p + Vector3(randf_range(-0.4, 0.4) * s, s * 0.7, randf_range(-0.4, 0.4) * s), s * 0.3, s * 1.15, 0.6, 0.85, 1.0, 0.1)
	for i in _n(clampf(s / 3.0, 8.0, 13.0)):
		var d := _rdir(0.9)
		d.y = absf(d.y)
		_fire(p + d * s * 0.2, Vector3(d.x * 1.4, d.y * 2.6 + 0.8, d.z * 1.4) * s, s * randf_range(0.35, 0.55), s * randf_range(0.9, 1.3),
			randf_range(0.5, 0.95), randf_range(0.6, 0.85), 30.0)
	# столб: клубы поднимаются к камере и тормозят — сверху виден растущий «гриб», с наклоном — колонна
	for i in _n(clampf(s / 2.5, 10.0, 15.0)):
		var d2 := _rdir()
		var up := randf_range(1.2, 3.0)
		var g2 := randf_range(0.08, 0.14) if i % 4 != 3 else randf_range(0.26, 0.36)
		_smoke(p + Vector3(d2.x, 0, d2.z) * s * 0.4, Vector3(d2.x * 0.5, up, d2.z * 0.5) * s, s * 0.55, s * randf_range(2.2, 3.1),
			randf_range(3.5, 5.5), Color(g2, g2 * 0.95, g2 * 0.9, 0.75), 0.9, 6.0, 0.9, randf_range(0.04, 0.3))
	_dust_skirt(g, s, 1.0)
	for i in _n(clampf(s / 4.0, 5.0, 10.0)):
		var a := randf() * TAU
		var dv := Vector3(cos(a) * randf_range(1.5, 3.5), randf_range(3.5, 7.0), sin(a) * randf_range(1.5, 3.5)) * s
		_debris(p, dv, s * randf_range(0.08, 0.16), Color(0.24, 0.19, 0.14), 0.25, "dust", false, 0.0)
	for i in _n(2):
		var a2 := randf() * TAU
		_debris(p, Vector3(cos(a2) * 2.0, 5.0, sin(a2) * 2.0) * s, s * 0.14, Color(0.15, 0.14, 0.13), 1.0, "fire", false, 0.5)
	_sparks(p, _n(clampf(s * 0.6, 10.0, 22.0)), 280.0 + s * 8.0, 0.6, Color(1.0, 0.7, 0.3, 1.0), 0.8)
	_emit.append({"p": g, "t": 0.0, "life": randf_range(4.0, 6.5), "s": s * 0.55, "acc_f": 0.0, "acc_s": 0.0})
	_light(g + Vector3(0, s * 2.5, 0), clampf(s / 7.0, 2.0, 7.0), clampf(s * 12.0, 260.0, 1000.0), 0.55)


## Бомбы и НАР по площади: меньше огня, больше пыли и земли; пыльная волна доходит до края зоны поражения
func _blast(g: Vector3, s: float) -> void:
	var p := g + Vector3(0, s * 0.2, 0)
	_flash(p + Vector3(0, s * 0.4, 0), s * 3.0, 0.1)
	_core(p, s * 0.45, s * 1.3, 0.45, 1.0, 0.75)
	for i in _n(7):
		var d := _rdir(0.9)
		d.y = absf(d.y)
		_fire(p + d * s * 0.2, Vector3(d.x * 1.6, d.y * 2.2 + 0.5, d.z * 1.6) * s, s * 0.35, s * 0.95, randf_range(0.35, 0.65), 0.95, 20.0)
	for i in _n(7):
		var d2 := _rdir()
		var g2 := randf_range(0.18, 0.3)
		_smoke(p + Vector3(d2.x, 0, d2.z) * s * 0.4, Vector3(d2.x * 0.6, randf_range(1.0, 2.2), d2.z * 0.6) * s, s * 0.5, s * randf_range(1.8, 2.5),
			randf_range(2.2, 3.5), Color(g2 * 1.15, g2, g2 * 0.82, 0.8), 0.6, 5.0, 1.0, randf_range(0.03, 0.2))
	_dust_skirt(g, s, 1.35)
	for i in _n(clampf(s / 3.5, 6.0, 12.0)):
		var a := randf() * TAU
		var dv := Vector3(cos(a) * randf_range(2.0, 4.0), randf_range(3.0, 6.0), sin(a) * randf_range(2.0, 4.0)) * s
		_debris(p, dv, s * randf_range(0.07, 0.14), Color(0.26, 0.2, 0.14), 0.2, "dust", false, 0.0)
	_sparks(p, _n(12), 260.0 + s * 8.0, 0.5, Color(1.0, 0.7, 0.3, 1.0), 0.8)
	_emit.append({"p": g, "t": 0.0, "life": 1.8, "s": s * 0.4, "acc_f": 0.0, "acc_s": 0.0})
	_light(g + Vector3(0, s * 2.0, 0), clampf(s / 8.0, 1.5, 5.0), clampf(s * 10.0, 220.0, 800.0), 0.4)


## Пыльная волна: клубы песка у самой земли разбегаются кольцом и оседают — объёмная, а не круг на земле
func _dust_skirt(g: Vector3, s: float, reach: float) -> void:
	var n := _n(clampf(s / 1.6, 14.0, 28.0))
	for i in n:
		var a := TAU * float(i) / n + randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var sh := randf_range(0.88, 1.08)
		_smoke(g + dir * s * randf_range(0.3, 0.7) + Vector3(0, s * 0.15, 0), dir * s * randf_range(3.5, 6.5) * reach + Vector3(0, s * 0.5, 0),
			s * 0.5, s * randf_range(1.4, 2.2), randf_range(1.4, 2.4), Color(0.7 * sh, 0.6 * sh, 0.46 * sh, 0.42), 0.0, 2.0, 2.8)


## Отложенный хлопок цепочки у крупных взрывов
func _sub(p: Vector3, s: float) -> void:
	_flash(p, s * 2.8, 0.08)
	_core(p, s * 0.5, s * 1.4, 0.45, 1.0)
	for i in _n(5):
		var d := _rdir()
		_fire(p + d * s * 0.3, d * s * 2.4, s * 0.4, s * 1.0, randf_range(0.35, 0.6), 0.95, 6.0)
	for i in _n(4):
		var d2 := _rdir()
		_smoke(p + d2 * s * 0.4, d2 * s * 0.7, s * 0.5, s * 2.2, randf_range(2.0, 3.0), Color(0.07, 0.065, 0.06, 0.8), 0.8)
	_sparks(p, _n(10), 280.0, 0.4)


# ---------- каждый кадр ----------

func _process(delta: float) -> void:
	var dt := 0.0 if get_tree().paused else delta
	var R := Render3D.I
	if R == null or R.cam == null:
		return
	var t0 := Time.get_ticks_usec()
	_cam_f = -R.cam.global_transform.basis.z
	if dt > 0.0:
		_tick_later(dt)
		_tick_emit(dt)
		_tick_debris(dt, R)
		for L in [L_SMOKE, L_FIRE, L_CORE, L_SPARK, L_SHOCK, L_FLASH]:
			_tick(_parts[L], dt)
		for sl in _lights:
			if float(sl["t"]) > 0.0:
				sl["t"] = float(sl["t"]) - dt
				var k := clampf(float(sl["t"]) / maxf(float(sl["max"]), 0.01), 0.0, 1.0)
				(sl["l"] as OmniLight3D).light_energy = float(sl["e"]) * k * k
				(sl["l"] as OmniLight3D).visible = float(sl["t"]) > 0.0
	var total := 0
	for L in 7:
		_write(L)
		total += (_parts[L] as Array).size()
	stats_peak = maxi(stats_peak, total)
	stats_us = Time.get_ticks_usec() - t0


func _tick(arr: Array, dt: float) -> void:
	var w := 0
	for j in arr.size():
		var q: Dictionary = arr[j]
		var t: float = q["t"] + dt
		q["t"] = t
		if t >= float(q["life"]):
			continue
		if t >= 0.0:
			var v: Vector3 = q["v"]
			v.y += (float(q["b"]) - float(q["g"])) * dt
			v *= 1.0 - minf(float(q["drag"]) * dt, 0.9)
			q["v"] = v
			q["p"] = (q["p"] as Vector3) + (v + WIND * float(q["wind"])) * dt
			q["rot"] = float(q["rot"]) + float(q["spin"]) * dt
		arr[w] = q
		w += 1
	arr.resize(w)


func _tick_later(dt: float) -> void:
	for i in range(_later.size() - 1, -1, -1):
		_later[i]["t"] = float(_later[i]["t"]) - dt
		if float(_later[i]["t"]) <= 0.0:
			var d: Dictionary = _later[i]
			_later.remove_at(i)
			_sub(d["p"], d["s"])
			if Render3D.I != null:
				Render3D.I.light_flash(Vector2((d["p"] as Vector3).x, (d["p"] as Vector3).z), d["s"])


## Догорающие очаги: языки огня и столб дыма, слабеют к концу
func _tick_emit(dt: float) -> void:
	for i in range(_emit.size() - 1, -1, -1):
		var e: Dictionary = _emit[i]
		e["t"] = float(e["t"]) + dt
		var k := 1.0 - float(e["t"]) / float(e["life"])
		if k <= 0.0:
			_emit.remove_at(i)
			continue
		var s: float = e["s"]
		var p: Vector3 = e["p"]
		e["acc_f"] = float(e["acc_f"]) + dt * 16.0 * _q * k
		e["acc_s"] = float(e["acc_s"]) + dt * 7.0 * _q * (0.4 + 0.6 * k)
		while float(e["acc_f"]) >= 1.0:
			e["acc_f"] = float(e["acc_f"]) - 1.0
			var o := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * s * 0.6
			_fire(p + o + Vector3(0, s * 0.2, 0), Vector3(0, s * randf_range(1.2, 2.2), 0), s * 0.35 * (0.5 + k), s * 0.75 * (0.5 + k),
				randf_range(0.35, 0.6), 0.75 + 0.2 * k, 10.0)
		while float(e["acc_s"]) >= 1.0:
			e["acc_s"] = float(e["acc_s"]) - 1.0
			var o2 := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * s * 0.4
			var gg := randf_range(0.09, 0.15)
			_smoke(p + o2 + Vector3(0, s * 0.6, 0), Vector3(0, s * randf_range(1.6, 2.6), 0), s * 0.6, s * randf_range(2.2, 3.2),
				randf_range(2.8, 4.0), Color(gg, gg * 0.95, gg * 0.9, 0.7 * (0.4 + 0.6 * k)), 0.5 * k, 4.0, 0.5)


## Обломки: баллистика, кувыркание, след; на рельефе останавливаются, лежат и гаснут
func _tick_debris(dt: float, R: Render3D) -> void:
	var arr: Array = _parts[L_DEBRIS]
	var w := 0
	for j in arr.size():
		var q: Dictionary = arr[j]
		q["t"] = float(q["t"]) + dt
		if float(q["t"]) >= float(q["life"]):
			continue
		var p: Vector3 = q["p"]
		q["gt"] = float(q["gt"]) - dt
		if float(q["gt"]) <= 0.0:
			q["gt"] = 0.2
			q["gy"] = R.terrain.surface(p.x, p.z).y if R.terrain != null else R.GROUND_Y
		q["h"] = maxf(0.0, float(q["h"]) - dt * (0.45 if q["trail"] == "fire" else 1.1))
		if not q["landed"]:
			var v: Vector3 = q["v"]
			v.y -= float(q["g"]) * dt
			v *= exp(-float(q["drag"]) * dt)
			q["v"] = v
			p += v * dt
			q["ang"] = float(q["ang"]) + float(q["w"]) * dt
			q["tt"] = float(q["tt"]) - dt
			if float(q["tt"]) <= 0.0:
				_trail(q, p)
			if p.y <= float(q["gy"]) + 1.0 and v.y < 0.0:
				p.y = float(q["gy"]) + 1.0
				q["landed"] = true
				q["life"] = float(q["t"]) + (6.0 if q["trail"] != "dust" else 3.0)
				var sz := (q["sz"] as Vector3).length()
				_smoke(p, Vector3(0, sz * 2.0, 0), sz * 0.8, sz * 3.0, 1.4, Color(0.62, 0.53, 0.4, 0.55), 0.0, 2.0, 2.0)
				if q["burn"]:
					_emit.append({"p": p, "t": 0.0, "life": randf_range(2.5, 4.0), "s": sz * 1.2, "acc_f": 0.0, "acc_s": 0.0})
					_flak(p + Vector3(0, sz, 0), sz * 1.4)
		q["p"] = p
		arr[w] = q
		w += 1
	arr.resize(w)


func _trail(q: Dictionary, p: Vector3) -> void:
	var sz := (q["sz"] as Vector3).length()
	match q["trail"]:
		"fire":
			q["tt"] = 0.02 / _q
			_fire(p, Vector3.ZERO, sz * 1.0, sz * 2.0, 0.4, 0.85 * float(q["h"]) + 0.15, 0.0)
			_smoke(p, Vector3(0, 10, 0), sz * 0.9, sz * 3.2, 1.6, Color(0.11, 0.1, 0.095, 0.65), 0.4, 4.0, 1.0)
		"smoke":
			q["tt"] = 0.025 / _q
			_smoke(p, Vector3.ZERO, sz * 0.7, sz * 2.4, 1.1, Color(0.14, 0.13, 0.12, 0.6), 0.3 * float(q["h"]), 2.0, 1.0)
		"dust":
			q["tt"] = 0.035 / _q
			_smoke(p, Vector3.ZERO, sz * 0.6, sz * 1.8, 0.8, Color(0.55, 0.46, 0.34, 0.5), 0.0, 0.0, 1.0)
		_:
			q["tt"] = 1e9


# ---------- запись в MultiMesh ----------

func _write(L: int) -> void:
	var arr: Array = _parts[L]
	var mm: MultiMesh = _mm[L]
	var buf: PackedFloat32Array = _buf[L]
	var n := arr.size()
	for i in n:
		var q: Dictionary = arr[i]
		var t: float = q["t"]
		var k := clampf(t / float(q["life"]), 0.0, 1.0)
		var b := Basis()
		var o: Vector3 = q["p"]
		var c: Color = q["c"]
		var cd := Color(0, 0, 0, 0)
		if t < 0.0:
			b = Basis.from_scale(Vector3.ZERO)   # ещё не появился (задержка)
		else:
			match L:
				L_SMOKE:
					var r := lerpf(q["r0"], q["r1"], 1.0 - pow(1.0 - k, 2.2))
					b = Basis.from_scale(Vector3.ONE * r * 2.0)
					c.a *= smoothstep(0.0, 0.08, k) * (1.0 - k * k)
					var grey := float(q.get("fade", 0.0))   # сажа рассеивается: чёрный дым светлеет к серому
					if grey > 0.0:
						var gk := smoothstep(0.1, 0.9, k) * 0.75
						c.r = lerpf(c.r, grey, gk); c.g = lerpf(c.g, grey * 0.97, gk); c.b = lerpf(c.b, grey * 0.93, gk)
					cd = Color(q["rot"], k, q["tile"], float(q["glow"]) * maxf(0.0, 1.0 - k * 3.5))
				L_FIRE:
					var r2 := lerpf(q["r0"], q["r1"], 1.0 - pow(1.0 - k, 2.0))
					b = Basis.from_scale(Vector3.ONE * r2 * 2.0)
					c.a *= smoothstep(0.0, 0.05, k)
					cd = Color(q["rot"], k, q["tile"], q["h"])
				L_CORE:
					var r3 := lerpf(q["r0"], q["r1"], 1.0 - pow(1.0 - k, 2.6))
					b = Basis.from_scale(Vector3(r3, r3 * float(q.get("sq", 1.0)), r3))
					cd = Color(k, q["seed"], q["h"], 0)
				L_SHOCK:
					var r4 := lerpf(q["r0"], q["r1"], 1.0 - pow(1.0 - k, 1.6))
					b = Basis.from_scale(Vector3(r4, r4 * float(q.get("sq", 1.0)), r4))
					c.a *= (1.0 - k)
					cd = Color(k, float(q.get("seed", 0.0)), 0, 0)
				L_FLASH:
					var r5 := lerpf(q["r0"], q["r1"], sqrt(k))
					b = Basis.from_scale(Vector3.ONE * r5 * 2.0)
					c.a *= (1.0 - k) * (1.0 - k)
				L_SPARK:
					var v: Vector3 = q["v"]
					var vd := v - _cam_f * v.dot(_cam_f)
					var ln := clampf(vd.length() * 0.05, 3.0, 70.0)
					var xd := vd.normalized() if vd.length_squared() > 0.01 else Vector3.RIGHT
					var yd := _cam_f.cross(xd).normalized() * float(q["w"]) * (1.0 - k * 0.5)
					b = Basis(xd * ln, yd, _cam_f)
					o -= xd * ln * 0.5
					c.a *= 1.0 - k
				L_DEBRIS:
					var shrink := clampf((float(q["life"]) - t) / 1.0, 0.0, 1.0)
					b = Basis(q["ax"], q["ang"]) * Basis.from_scale(q["sz"] * shrink)
					cd = Color(q["h"], q["metal"], 0, 0)
		var j := i * STRIDE
		buf[j] = b.x.x; buf[j + 1] = b.y.x; buf[j + 2] = b.z.x; buf[j + 3] = o.x
		buf[j + 4] = b.x.y; buf[j + 5] = b.y.y; buf[j + 6] = b.z.y; buf[j + 7] = o.y
		buf[j + 8] = b.x.z; buf[j + 9] = b.y.z; buf[j + 10] = b.z.z; buf[j + 11] = o.z
		buf[j + 12] = c.r; buf[j + 13] = c.g; buf[j + 14] = c.b; buf[j + 15] = c.a
		buf[j + 16] = cd.r; buf[j + 17] = cd.g; buf[j + 18] = cd.b; buf[j + 19] = cd.a
	_buf[L] = buf
	if n > 0 or mm.visible_instance_count != 0:
		mm.buffer = buf
	mm.visible_instance_count = n


## Для лога: частиц сейчас
func count() -> int:
	var t := 0
	for a in _parts:
		t += (a as Array).size()
	return t
