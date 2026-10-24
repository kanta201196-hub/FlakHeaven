class_name Contrails
extends MeshInstance3D
## 3.4-t1 (п. 10, 34): инверсионные следы — белые ленты за самолётами и ракетами.
## Каждый след — цепочка точек в мире; точка живёт life секунд, со временем расплывается и тает.
## Один меш на все следы, пересобирается каждый кадр (ArrayMesh из массивов — дёшево).

const MAX_POINTS := 2600

var _tr := {}        # ключ → {"p": [Vector3], "t": [рождение], "s": [стиль], "head": Vector3, "seen": bool}
var _time := 0.0
var _am := ArrayMesh.new()
var _mat := StandardMaterial3D.new()
var _count := 0
var _dead := 0
var _fancy := false   # VFX-03: Forward+ draws missile smoke with SMOKE_SH; Compatibility keeps the flat soft ribbon

## VFX-03 (Forward+): plane contrails look as before (soft texture across the ribbon); missile smoke (a style with
## a colour) is a lit tube of billowing smoke: world-anchored noise erodes the edges more with age, the sun side
## is brighter, and a short hot glow sits at the nozzle. UV.y = across, NORMAL = ribbon side direction,
## CUSTOM0 (float, exact distances) = (distance from the nozzle, distance from the tail, age 0..1, smoke 0/1).
const SMOKE_SH := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D soft : source_color, filter_linear_mipmap;
uniform vec3 to_sun = vec3(-0.46, 0.63, -0.56);
%s
varying vec3 wp;
varying vec3 sd;
varying vec4 cu;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sd = NORMAL;
	cu = CUSTOM0;
}
void fragment() {
	if (cu.w < 0.5) {
		vec4 t = texture(soft, vec2(0.5, UV.y));   // contrail: UV.x is a distance here, only the profile across matters
		ALBEDO = COLOR.rgb * t.rgb;
		ALPHA = COLOR.a * t.a;
	} else {
		float k = cu.z;
		// Kanta 24.10: no cut ends. From the nozzle the smoke starts as a thin bright jet and widens over the first
		// ~30 units; towards the tail it breaks up into thinning puffs over the last ~140 units instead of ending.
		// As real trails age they spread, turn wavy and break into puffs that thin out (the core drifts across the
		// ribbon by up to 0.3 of its half-width, so the visible smoke is drawn at 0.7 of it).
		float head = smoothstep(0.0, 30.0, cu.x);
		float tail = smoothstep(0.0, 140.0, cu.y);
		float wob = (fbm(wp * 0.02 + vec3(3.1, 0.0, 7.7)) - 0.5) * 0.6 * k;
		float x = (UV.y * 2.0 - 1.0 - wob) / (0.7 * mix(0.25, 1.0, head));
		float prof = max(1.0 - x * x, 0.0);
		vec3 drift = vec3(0.7, 1.3, 0.4) * k;
		float big = fbm(wp * 0.05 + drift);
		vec3 qf = wp * 0.17 + drift * 1.6;
		float fine = fbm(qf);
		float fine2 = fbm(qf + to_sun * 0.6);
		float d = prof * (0.25 + 1.25 * (big * 0.5 + fine * 0.5)) - k * 0.5 - (1.0 - tail) * 0.75;
		float a = smoothstep(0.1, 0.38, d);
		vec3 nrm = normalize(normalize(sd) * x + vec3(0.0, sqrt(max(prof, 0.0)), 0.0));
		float lit = 0.62 + 0.38 * max(dot(nrm, to_sun), 0.0) + (fine - fine2) * 1.6;
		vec3 col = min(COLOR.rgb * clamp(lit, 0.35, 1.3), vec3(0.97));
		float heat = (1.0 - smoothstep(0.0, 14.0, cu.x)) * prof;
		col = mix(col, vec3(2.6, 1.35, 0.42), heat);
		ALBEDO = col;
		ALPHA = clamp(COLOR.a * a * (1.0 + heat), 0.0, 1.0);
	}
}
"""


func _ready() -> void:
	mesh = _am
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	_fancy = GpuFx.active()
	if _fancy:
		var sh := Shader.new()
		sh.code = SMOKE_SH % Boom3D.COMMON
		var sm := ShaderMaterial.new()
		sm.shader = sh
		material_override = sm
		return
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat


## Точка следа. style: [альфа, ширина у источника, ширина в конце, время жизни, шаг точек, (цвет)]
## M-39 (аудит 3.5-s6 Э-2): цвет — необязательный 6-й элемент (дым ракет светло-серый), без него — белая инверсия
func emit(key: Variant, pos: Vector3, style: Array) -> void:
	var t: Dictionary = _tr.get(key, {})
	if not t.is_empty() and (t["head"] as Vector3).distance_squared_to(pos) > 250.0 * 250.0:
		# скачок (телепорт, новый вылет): старый след дотаивает сам, новый начинается заново
		_dead += 1
		_tr["dead%d" % _dead] = t
		t["seen"] = false
		t = {}
	if t.is_empty():
		t = {"p": [], "t": [], "s": [], "head": pos, "seen": true}
		_tr[key] = t
	t["seen"] = true
	t["head"] = pos
	var pts: Array = t["p"]
	var step: float = style[4]
	if pts.is_empty() or (pts[pts.size() - 1] as Vector3).distance_squared_to(pos) > step * step:
		if _count >= MAX_POINTS:
			return
		pts.append(pos)
		t["t"].append(_time)
		t["s"].append(style)
		_count += 1


## Каждый кадр после всех emit: стареют точки, исчезнувшие источники дотаивают
func tick(delta: float) -> void:
	if _mat.albedo_texture == null and Fx._soft != null:
		_mat.albedo_texture = Fx._soft
		if _fancy:
			(material_override as ShaderMaterial).set_shader_parameter("soft", Fx._soft)
	_time += delta
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var cus := PackedFloat32Array()
	var nrms := PackedVector3Array()
	var idx := PackedInt32Array()
	_count = 0
	for key in _tr.keys():
		var t: Dictionary = _tr[key]
		var pts: Array = t["p"]
		var born: Array = t["t"]
		var st: Array = t["s"]
		# старые точки (с хвоста)
		var cut := 0
		while cut < pts.size() and _time - float(born[cut]) > float(st[cut][3]):
			cut += 1
		if cut > 0:
			pts = pts.slice(cut)
			born = born.slice(cut)
			st = st.slice(cut)
			t["p"] = pts
			t["t"] = born
			t["s"] = st
		var live: bool = t["seen"]
		t["seen"] = false
		if pts.is_empty():
			if not live:
				_tr.erase(key)
			continue
		_count += pts.size()
		var n := pts.size() + (1 if live else 0)
		if n < 2:
			continue
		var base := verts.size()
		var total := 0.0   # VFX-03: trail length, so the smoke can taper from the nozzle and thin out to the tail
		var along := 0.0
		if _fancy:
			for i in range(1, n):
				var pi: Vector3 = t["head"] if i == pts.size() else pts[i]
				total += pi.distance_to(pts[i - 1])
		for i in n:
			var p: Vector3 = t["head"] if i == pts.size() else pts[i]
			var j := mini(i, pts.size() - 1)
			var s: Array = st[j]
			var age := (_time - float(born[j])) if i < pts.size() else 0.0
			var k := clampf(age / float(s[3]), 0.0, 1.0)
			var q: Vector3 = pts[i + 1] if i + 1 < pts.size() else (t["head"] if live and i + 1 == pts.size() else p)
			var o: Vector3 = pts[i - 1] if i > 0 else p
			var d := Vector2(q.x - o.x, q.z - o.z)
			d = d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT
			# ширина растёт со временем (след расплывается), быстрее в начале
			var w: float = lerpf(float(s[1]), float(s[2]), 1.0 - (1.0 - k) * (1.0 - k)) * 0.5
			var smoke := s.size() > 5
			if _fancy and smoke:
				w *= 2.0   # the noise eats the edges and the core wanders, so the ribbon is wider than its visible smoke
			var side := Vector3(-d.y, 0.0, d.x) * w
			# у источника след проявляется (не начинается резко у сопла), к концу тает
			# M-39: у сопла след плотный (проявление короче), к концу короткой жизни тает
			var a: float = float(s[0]) * (1.0 - k) * (1.0 - 0.6 * k) * clampf(age / 0.04, 0.0, 1.0) if i < pts.size() else float(s[0]) * 0.5
			var c: Color = s[5] if s.size() > 5 else Color.WHITE
			c.a = a
			verts.append(p - side)
			verts.append(p + side)
			cols.append(c)
			cols.append(c)
			uvs.append(Vector2(0.5, 0.0))
			uvs.append(Vector2(0.5, 1.0))
			if _fancy:
				if i > 0:
					along += p.distance_to(o)
				var cu := [total - along, along, k, 1.0 if smoke else 0.0]
				cus.append_array(cu)
				cus.append_array(cu)
				var sn := Vector3(-d.y, 0.0, d.x)
				nrms.append(sn)
				nrms.append(sn)
			if i > 0:
				var v := base + (i - 1) * 2
				idx.append_array(PackedInt32Array([v, v + 1, v + 2, v + 1, v + 3, v + 2]))
	_am.clear_surfaces()
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	if _fancy:
		arr[Mesh.ARRAY_CUSTOM0] = cus
		arr[Mesh.ARRAY_NORMAL] = nrms
	arr[Mesh.ARRAY_INDEX] = idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) if _fancy else 0
	_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)


func clear() -> void:
	_tr.clear()
	_am.clear_surfaces()
	_count = 0
