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


func _ready() -> void:
	mesh = _am
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat
	extra_cull_margin = 16384.0


## Точка следа. style: [альфа, ширина у источника, ширина в конце, время жизни, шаг точек]
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
	_time += delta
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
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
			var w: float = lerpf(float(s[1]), float(s[2]), sqrt(k)) * 0.5
			var side := Vector3(-d.y, 0.0, d.x) * w
			# у источника след проявляется (не начинается резко у сопла), к концу тает
			var a: float = float(s[0]) * (1.0 - k) * (1.0 - k) * clampf(age / 0.08, 0.0, 1.0) if i < pts.size() else 0.0
			verts.append(p - side)
			verts.append(p + side)
			cols.append(Color(1, 1, 1, a))
			cols.append(Color(1, 1, 1, a))
			uvs.append(Vector2(0.5, 0.0))
			uvs.append(Vector2(0.5, 1.0))
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
	arr[Mesh.ARRAY_INDEX] = idx
	_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


func clear() -> void:
	_tr.clear()
	_am.clear_surfaces()
	_count = 0
