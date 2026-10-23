class_name SeaWakes
extends MeshInstance3D
## S10-10 (замечание Kanta 23.10): след на воде за судами «Архипелага» — кильватер, как его видно сверху:
## белая взбитая полоса за кормой (ширина корпуса, расплывается и тает) и две тонкие расходящиеся «усы»
## волн от носа под углом ~20° к курсу. Каждый след — цепочка точек на воде с курсом, шириной корпуса и скоростью;
## один меш на все следы, пересобирается каждый кадр (как Contrails). Пятна пены — шумом в шейдере.

const MAX_POINTS := 1800
const LIFE := 9.0          # с — сколько живёт точка следа
const ARM_K := 0.36        # tg ~20°: на сколько расходятся «усы» за 1 px пройденного пути
const STEP_K := 0.22       # шаг точек — доля длины корпуса

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec2 wpos;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), u.x), u.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
	// UV.x — поперёк полосы 0…1, UV.y — 0 взбитая полоса за кормой, 1 «ус» волны
	float x = abs(UV.x * 2.0 - 1.0);
	float n = vn(wpos / 9.0) * 0.6 + vn(wpos / 3.5 + 7.0) * 0.4;
	float edge;
	if (UV.y < 0.5) {
		// пена за кормой: плотная в середине, рваные края, пятнами
		edge = 1.0 - smoothstep(0.35 + 0.35 * n, 1.0, x);
		edge *= 0.55 + 0.45 * smoothstep(0.25, 0.7, n);
	} else {
		// «ус»: тонкий гребень волны с мягким краем, местами рвётся
		edge = 1.0 - smoothstep(0.15, 1.0, x);
		edge *= 0.45 + 0.55 * smoothstep(0.2, 0.65, n);
	}
	ALBEDO = mix(vec3(0.78, 0.88, 0.9), vec3(0.97, 0.99, 1.0), COLOR.r);
	ALPHA = clamp(COLOR.a * edge, 0.0, 1.0);
}
"""

var _tr := {}        # ключ → {"p": [Vector3], "t": [рождение], "d": [курс Vector2], "w": [полуширина], "v": [доля скорости], "head", "hd", "seen", "spd", "last", "lt"}
var _time := 0.0
var _am := ArrayMesh.new()
var _count := 0
var _dead := 0
static var _shader: Shader


func _ready() -> void:
	mesh = _am
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	material_override = m
	extra_cull_margin = 16384.0


## Судно key на воде в точке pos (поверхность воды), курс heading, длина корпуса len_px, полуширина beam
func emit(key: Variant, pos: Vector3, heading: float, len_px: float, beam: float) -> void:
	var t: Dictionary = _tr.get(key, {})
	if not t.is_empty() and (t["head"] as Vector3).distance_squared_to(pos) > 300.0 * 300.0:
		_dead += 1   # скачок (новый вылет, стенд): старый след дотаивает сам
		_tr["dead%d" % _dead] = t
		t["seen"] = false
		t = {}
	if t.is_empty():
		t = {"p": [], "t": [], "d": [], "w": [], "v": [], "head": pos, "hd": Vector2.from_angle(heading), "seen": true,
			"spd": 0.0, "last": pos, "lt": _time}
		_tr[key] = t
	# скорость — по пути за кадры (у кораблей-боссов и машин конвоя она своя), сглаженная
	var dt := _time - float(t["lt"])
	if dt > 0.05:
		var v := Vector2(pos.x - (t["last"] as Vector3).x, pos.z - (t["last"] as Vector3).z).length() / dt
		t["spd"] = lerpf(float(t["spd"]), v, 0.5)
		t["last"] = pos
		t["lt"] = _time
	t["seen"] = true
	t["head"] = pos
	t["hd"] = Vector2.from_angle(heading)
	t["len"] = len_px
	t["beam"] = beam
	var pts: Array = t["p"]
	var step := maxf(len_px * STEP_K, 5.0)
	if pts.is_empty() or (pts[pts.size() - 1] as Vector3).distance_squared_to(pos) > step * step:
		if _count >= MAX_POINTS:
			return
		pts.append(pos)
		t["t"].append(_time)
		t["d"].append(Vector2.from_angle(heading))
		t["w"].append(beam)
		t["v"].append(clampf(float(t["spd"]) / 40.0, 0.0, 1.0))   # тихий ход — след слабее
		_count += 1


func tick(delta: float) -> void:
	_time += delta
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	_count = 0
	for key in _tr.keys():
		var t: Dictionary = _tr[key]
		var born: Array = t["t"]
		var cut := 0
		while cut < born.size() and _time - float(born[cut]) > LIFE:
			cut += 1
		if cut > 0:
			for k in ["p", "t", "d", "w", "v"]:
				t[k] = (t[k] as Array).slice(cut)
		var pts: Array = t["p"]
		var live: bool = t["seen"]
		t["seen"] = false
		if pts.is_empty():
			if not live:
				_tr.erase(key)
			continue
		_count += pts.size()
		_build(t, live, verts, cols, uvs, idx)
	_am.clear_surfaces()
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


## Три полосы одного следа: пена за кормой и два «уса» от носа (по точкам пути, от старых к новым)
func _build(t: Dictionary, live: bool, verts: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array) -> void:
	var pts: Array = t["p"]
	var born: Array = t["t"]
	var dirs: Array = t["d"]
	var ws: Array = t["w"]
	var vs: Array = t["v"]
	var len_px := float(t.get("len", 60.0))
	var n := pts.size() + (1 if live else 0)
	if n < 2:
		return
	# путь от каждой точки до судна (для расхождения «усов»): с головы к хвосту
	var along := PackedFloat32Array()
	along.resize(n)
	along[n - 1] = 0.0
	for i in range(n - 2, -1, -1):
		var a: Vector3 = pts[i]
		var b: Vector3 = t["head"] if i + 1 == pts.size() else pts[i + 1]
		along[i] = along[i + 1] + Vector2(b.x - a.x, b.z - a.z).length()
	for band in 3:   # 0 — пена за кормой, 1 и 2 — «усы» слева и справа
		var base := verts.size()
		for i in n:
			var head := i == pts.size()
			var j := mini(i, pts.size() - 1)
			var p: Vector3 = t["head"] if head else pts[i]
			var d: Vector2 = t["hd"] if head else dirs[j]
			var age := 0.0 if head else _time - float(born[j])
			var k := clampf(age / LIFE, 0.0, 1.0)
			var beam := float(ws[j])
			var vk := float(vs[j]) if not head else float(vs[j])
			var side := Vector2(-d.y, d.x)
			var c := Color(1, 1, 1, 0)
			var mid := Vector2(p.x, p.z)
			var hw := 0.0
			if band == 0:
				# пена начинается у кормы (половина корпуса за центром), шире корпуса, расплывается
				mid -= d * len_px * 0.45
				hw = beam * (0.75 + 1.6 * sqrt(k) + along[i] / len_px * 0.08)
				c.a = 0.85 * vk * (1.0 - k) * (1.0 - k) * smoothstep(0.0, len_px * 0.3, along[i] + len_px * 0.05)
				c.r = 1.0 - k
			else:
				# «ус»: гребень от носа, уходит в сторону на ARM_K от пройденного пути
				var sg := 1.0 if band == 1 else -1.0
				mid += d * len_px * 0.42 + side * sg * (beam * 0.9 + along[i] * ARM_K)
				hw = beam * (0.22 + 0.9 * k)
				c.a = 0.55 * vk * (1.0 - k) * smoothstep(0.0, len_px * 0.5, along[i] + len_px * 0.1)
				c.r = 0.6 * (1.0 - k)
			var e := Vector3(side.x, 0.0, side.y) * hw
			var at := Vector3(mid.x, p.y, mid.y)
			verts.append(at - e)
			verts.append(at + e)
			cols.append(c)
			cols.append(c)
			var v := 0.0 if band == 0 else 1.0
			uvs.append(Vector2(0.0, v))
			uvs.append(Vector2(1.0, v))
			if i > 0:
				var q := base + (i - 1) * 2
				idx.append_array(PackedInt32Array([q, q + 1, q + 2, q + 1, q + 3, q + 2]))


func clear() -> void:
	_tr.clear()
	_am.clear_surfaces()
	_count = 0
