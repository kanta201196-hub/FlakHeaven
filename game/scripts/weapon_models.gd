class_name WeaponModels
## 3.4-t1 (п. 3): объёмное оружие на узлах подвески, вид меняется с уровнем (решение владельца 16.10).
## Ступени вида: 1 — ур. 1–2, 2 — ур. 3–4, 3 — ур. 5 и эволюция.
## Модель строится из простых форм: длина по +X = 1 (нос вперёд), центр в начале координат;
## снаружи масштабируется под длину оружия. Точка вылета снаряда — muzzle() (п. 37).

static var _cache := {}
static var _mats := {}


static func tier(level: int, evo := false) -> int:
	if evo or level >= 5:
		return 3
	return 2 if level >= 3 else 1


## Узел с моделью (общий меш из кэша — копировать дёшево)
static func make(weapon: String, t: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(weapon, t)
	return mi


static func mesh(weapon: String, t: int) -> ArrayMesh:
	var key := "%s_%d" % [weapon, t]
	if _cache.has(key):
		return _cache[key]
	var parts: Array = []   # [меш-примитив, Transform3D, материал]
	match weapon:
		"aam":
			# 3.5: ракеты — «качество вместо количества» (1 ракета с точки), поэтому с уровнем ракета
			# не множится, а тяжелеет: обычная → крупнее, на пилоне → тяжёлая, с ускорителем
			var r: float = [0.045, 0.055, 0.066][t - 1]
			_missile(parts, Vector3.ZERO, 1.0, r)
			if t >= 2:
				parts.append([_box(Vector3(0.45, 0.06, 0.02)), Transform3D(Basis(), Vector3(0, r + 0.03, 0)), "dark"])
			if t == 3:
				parts.append([_cyl(r * 1.15, 0.22), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.32, 0, 0)), "dark"])
		"rockets":
			# малый блок → большой блок → два блока
			var r := 0.13 if t == 1 else 0.18
			var pods: Array = [0.0] if t < 3 else [-0.17, 0.17]
			for z: float in pods:
				_pod(parts, Vector3(0, 0, z), 1.0, r, 7 if t == 1 else 12)
		"bombs":
			# 2 бомбы → 4 → кассета
			if t == 3:
				parts.append([_cyl(0.16, 1.0), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3.ZERO), "olive"])
				parts.append([_cone(0.16, 0.18), Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.59, 0, 0)), "olive"])
				for a in 4:
					parts.append([_box(Vector3(0.16, 0.012, 0.2)), Transform3D(Basis(Vector3.RIGHT, a * PI / 2.0), Vector3(-0.42, 0, 0)), "dark"])
			else:
				var n := 2 if t == 1 else 4
				for i in n:
					var z := (i - (n - 1) / 2.0) * 0.16
					_bomb(parts, Vector3(0, 0, z))
		"gunpod":
			# 1 ствол → 2 → 3 ствола в кожухе
			parts.append([_cyl(0.12, 0.75), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.1, 0, 0)), "dark"])
			var nb := t
			for i in nb:
				var z := (i - (nb - 1) / 2.0) * 0.07
				parts.append([_cyl(0.022, 0.55), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.5, 0, z)), "steel"])
			if t == 3:
				parts.append([_cyl(0.13, 0.25), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.4, 0, 0)), "dark"])
		"turret":
			# одноствольная → спарка → спарка со щитком (стволы по +X — турель поворачивается целиком)
			parts.append([_sphere(0.28), Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3.ZERO), "dark"])
			var nb2 := 1 if t == 1 else 2
			for i in nb2:
				var z2 := (i - (nb2 - 1) / 2.0) * 0.12
				parts.append([_cyl(0.03, 0.6), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.45, 0.04, z2)), "steel"])
			if t == 3:
				parts.append([_box(Vector3(0.04, 0.22, 0.42)), Transform3D(Basis(), Vector3(0.2, 0.06, 0)), "olive"])
		"flares":
			# малый кассетник → большой → два
			var boxes: Array = [0.0] if t < 3 else [-0.14, 0.14]
			for z3: float in boxes:
				var s := 0.75 if t == 1 else 1.0
				parts.append([_box(Vector3(0.9 * s, 0.14 * s, 0.22 * s)), Transform3D(Basis(), Vector3(0, 0, z3)), "olive"])
				for c in 4:
					parts.append([_cyl(0.035 * s, 0.02), Transform3D(Basis(), Vector3((c - 1.5) * 0.18 * s, 0.075 * s, z3)), "dark"])
		_:
			parts.append([_box(Vector3(1.0, 0.1, 0.12)), Transform3D(), "steel"])
	var am := ArrayMesh.new()
	# по поверхности на материал: светлый металл, тёмный металл, оливковый, красная полоса
	for mname in ["steel", "dark", "olive", "band", "white"]:
		var s2 := SurfaceTool.new()
		s2.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		for p in parts:
			if p[2] != mname:
				continue
			s2.append_from(p[0], 0, p[1])
			any = true
		if any:
			s2.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, _mat(mname))
	_cache[key] = am
	return am


## Точка вылета снаряда в координатах модели (длина 1): для ракет и бомб — центр, для стволов — дульный срез
static func muzzle(weapon: String) -> Vector3:
	match weapon:
		"gunpod":
			return Vector3(0.78, 0, 0)
		"turret":
			return Vector3(0.75, 0.04, 0)
		"rockets":
			return Vector3(0.5, 0, 0)
		"aam":
			return Vector3(0.5, 0, 0)
	return Vector3.ZERO


# ---------- формы ----------

static func _missile(parts: Array, at: Vector3, length: float, r: float) -> void:
	var body := length * 0.78
	parts.append([_cyl(r, body), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(-0.05, 0, 0)), "white"])
	parts.append([_cone(r, length * 0.16), Transform3D(Basis(Vector3.BACK, -PI / 2.0), at + Vector3(body * 0.5 - 0.05 + length * 0.08, 0, 0)), "white"])
	parts.append([_cyl(r * 1.02, length * 0.05), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(body * 0.3, 0, 0)), "band"])
	for a in 4:
		parts.append([_box(Vector3(0.12, 0.008, r * 4.0)), Transform3D(Basis(Vector3.RIGHT, a * PI / 4.0 + PI / 4.0), at + Vector3(-body * 0.5 + 0.02, 0, 0)), "steel"])


static func _pod(parts: Array, at: Vector3, length: float, r: float, holes: int) -> void:
	parts.append([_cyl(r, length * 0.82), Transform3D(Basis(Vector3.BACK, PI / 2.0), at), "olive"])
	parts.append([_cone(r, length * 0.1), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(-length * 0.46, 0, 0)), "olive"])
	# дульные отверстия на переднем торце
	for i in holes:
		var a := TAU * i / holes
		var rr := r * (0.55 if i % 2 == 0 or holes < 10 else 0.25)
		parts.append([_cyl(r * 0.16, 0.02), Transform3D(Basis(Vector3.BACK, PI / 2.0), at + Vector3(length * 0.41, sin(a) * rr, cos(a) * rr)), "dark"])


static func _bomb(parts: Array, at: Vector3) -> void:
	parts.append([_sphere(0.1), Transform3D(Basis().scaled(Vector3(3.2, 1, 1)), at), "olive"])
	for a in 4:
		parts.append([_box(Vector3(0.12, 0.008, 0.16)), Transform3D(Basis(Vector3.RIGHT, a * PI / 2.0), at + Vector3(-0.33, 0, 0)), "dark"])


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


static func _cone(r: float, h: float) -> CylinderMesh:
	var c := _cyl(r, h)
	c.top_radius = 0.0
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func _mat(n: String) -> StandardMaterial3D:
	if _mats.has(n):
		return _mats[n]
	var m := StandardMaterial3D.new()
	match n:
		"steel":
			m.albedo_color = Color(0.62, 0.64, 0.66)
			m.metallic = 0.6
			m.roughness = 0.4
		"dark":
			m.albedo_color = Color(0.16, 0.17, 0.18)
			m.metallic = 0.4
			m.roughness = 0.55
		"olive":
			m.albedo_color = Color(0.4, 0.42, 0.33)
			m.roughness = 0.7
		"band":
			m.albedo_color = Color(0.75, 0.2, 0.15)
			m.roughness = 0.6
		"white":
			m.albedo_color = Color(0.88, 0.89, 0.9)
			m.roughness = 0.45
	_mats[n] = m
	return m


## 3.4-t1 (п. 37): точка вылета снаряда в мире (2D) для узла si группы g самолёта игрока —
## ракета с её пилона, очередь — из ствола контейнера, турель — из своей башни, повёрнутой на aim.
## Совпадает с тем, где 3D-модуль стоит на самолёте (Render3D._sync_weapons).
static func muzzle_world(p: Player, g: Hardpoint, si: int, aim := NAN) -> Vector2:
	var gi := p.groups.find(g)
	var tex := PlaneArt.plane_tex(p.cls_id, p.plane_lvl)
	var tex1 := PlaneArt.plane_tex(p.cls_id, 1)
	if gi < 0 or tex == null or tex1 == null:
		return p.global_position
	var pts := mounts(p.cls_id, p.plane_lvl, gi, g)
	if pts.is_empty():
		return p.global_position
	var pt: Vector2 = (pts[si % pts.size()] as Dictionary)["p"]
	var k := Tuning.g("plane_len") * p.size / float(tex1.get_width())   # пикселей мира на пиксель картинки
	var len_px: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) * Tuning.g("plane_len") / k
	var mz := muzzle(g.weapon) * len_px
	var local := pt + Vector2(mz.x, mz.z)
	if not is_nan(aim):   # турель: ствол смотрит на цель
		local = pt + Vector2(mz.x, 0.0).rotated(aim - p.heading)
	return p.global_position + (local * k).rotated(p.heading)



## Точки крепления оружия (пиксели картинки самолёта, центр картинки, нос по +X) и сторона:
##   "under" — под крылом на пилоне (НАР, ракеты, бомбы, контейнеры — как на настоящих самолётах);
##   встроенные турели — как у реальных бомбардировщиков и штурмовиков:
##   "tail" — кормовая установка в хвосте фюзеляжа (стволы назад), "top" — верхняя за кабиной,
##   "bottom" — нижняя под фюзеляжем. yaw — куда смотрят стволы без цели (0 — вперёд, PI — назад).
static func mounts(cls_id: String, lvl: int, gi: int, g: Hardpoint) -> Array:
	var out: Array = []
	if not g.builtin:
		for pt: Vector2 in PlaneArt.slot_points(cls_id, lvl, gi, g):
			out.append({"p": pt, "side": "under", "yaw": 0.0})
		return out
	var s := PlaneArt.shape_info(cls_id, lvl)
	if s.is_empty():
		return out
	var L: float = s["len"]
	var tail: float = s["tail"]
	var nose: float = s["nose"]
	var order: Array
	if cls_id == "bomber":
		# кормовая (главная), верхняя за кабиной, нижняя за крылом
		order = [["tail", tail + L * 0.035, PI], ["top", nose - L * 0.3, PI], ["bottom", tail + L * 0.3, PI]]
	else:
		# штурмовик: стрелок за кабиной (верхняя), вторая — нижняя под фюзеляжем
		order = [["top", nose - L * 0.36, PI], ["bottom", nose - L * 0.45, PI], ["tail", tail + L * 0.035, PI]]
	for i in g.slots:
		var o: Array = order[i % order.size()]
		out.append({"p": Vector2(o[1], 0.0), "side": o[0], "yaw": o[2]})
	return out
