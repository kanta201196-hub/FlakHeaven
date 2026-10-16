class_name WeaponModels
## 3.4-t1 (п. 3): объёмное оружие на узлах подвески, вид меняется с уровнем (решение владельца 16.10).
## Ступени вида: 1 — ур. 1–2, 2 — ур. 3–4, 3 — ур. 5 и эволюция.
## Модель строится из простых форм: длина по +X = 1 (нос вперёд), центр в начале координат;
## снаружи масштабируется под длину оружия. Точка вылета снаряда — muzzle() (п. 37).

static var _cache := {}
static var _mats := {}
## Вид турелей (на выбор владельца): 1 — всё с живыми стрелками: остеклённые колпаки и кабина в корме;
## 2 — всё дистанционное: низкие обтекатели и металлический кормовой конус;
## 3 — смешанный: кормовая кабина стрелка + дистанционные башни сверху и снизу
static var turret_style := 3


static func tier(level: int, evo := false) -> int:
	if evo or level >= 5:
		return 3
	return 2 if level >= 3 else 1


## Узел с моделью (общий меш из кэша — копировать дёшево)
## side — место крепления (mounts): от него зависит вид турели; cls — класс самолёта
## (у «Кита» и «Грача» свои турели — модели Blender по фото владельца, 16.10)
static func make(weapon: String, t: int, side := "", cls := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm: Mesh = turret_model(cls, t, side) if weapon == "turret" else weapon_model(weapon, t)
	mi.mesh = tm if tm != null else mesh(weapon, t, side)
	# кормовая кабина стрелка неподвижна — поворачивается только шар со стволами (поворот гасит render3d)
	if weapon == "turret" and side == "tail" and tm != null:
		var cab := turret_model(cls, t, "cabin")
		if cab != null:
			var cmi := MeshInstance3D.new()
			cmi.name = "cabin"
			cmi.mesh = cab
			mi.add_child(cmi)
	return mi


## Турели из Blender (game/tools/blender/turret_*.py → models/turrets): стволы +X, основание на y = 0.
## Масштаб — под размеры прежней турели (длина корпуса TURRET_MODELS.s), обшивка — в цвет самолёта.
const TURRET_MODELS := {
	# стволы укорочены на ~40% (владелец 16.10); ступень 3 — «Дикобраз»: 4 ствола и антенна наведения
	"bomber": {"file": "res://models/turrets/turret_kit.glb", "file3": "res://models/turrets/turret_kit_quad.glb",
		"s": 0.3, "muzzle": Vector3(2.09, 0.43, 0.0), "body": Color(0.5, 0.52, 0.54),
		# корма (пример владельца 16.10): кабина стрелка с фонарём и шаровая установка под килем
		"tail": "res://models/turrets/turret_kit_tail_ball.glb", "cabin": "res://models/turrets/turret_kit_tail_cabin.glb",
		"muzzle_tail": Vector3(1.36, 0.0, 0.0)},
	"attacker": {"file": "res://models/turrets/turret_grach.glb", "s": 0.36, "muzzle": Vector3(1.17, 0.34, 0.18),
		"body": Color(0.34, 0.37, 0.28)},
}


## Ракеты В-В и блоки НАР из Blender (tools/blender/weapons.py) по примерам владельца 16.10:
## ступени отличаются формой и деталями. Те же оси и длина 1, что у процедурных моделей ниже.
const WEAPON_GLB := {"aam": "res://models/weapons/aam_%d.glb", "rockets": "res://models/weapons/rockets_%d.glb"}


static func weapon_model(weapon: String, t: int) -> Mesh:
	if not WEAPON_GLB.has(weapon):
		return null
	var file: String = WEAPON_GLB[weapon] % t
	if not ResourceLoader.exists(file):
		return null
	return _glb_mesh(file, 1.0, Color(), "glb_%s_%d" % [weapon, t])


static func turret_model(cls: String, t := 1, side := "") -> Mesh:
	var spec: Dictionary = TURRET_MODELS.get(cls, {})
	var file: String = spec.get("file3", "") if t >= 3 and spec.has("file3") else spec.get("file", "")
	if side in ["tail", "cabin"] and spec.has(side):
		file = spec[side]
	if spec.is_empty() or not ResourceLoader.exists(file):
		return null
	return _glb_mesh(file, float(spec["s"]), spec["body"], "turret_model_%s_%s" % [cls, file.get_file()])


## Меш из GLB: все части в один ArrayMesh с масштабом s; материалы «body» перекрашиваются в tint
static func _glb_mesh(file: String, s: float, tint: Color, key: String) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var root: Node = (load(file) as PackedScene).instantiate()
	var src: MeshInstance3D = null
	for c in root.find_children("*", "MeshInstance3D", true, false):
		src = c
		break
	if src == null:
		root.free()
		return null
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO) * src.transform
	var am := ArrayMesh.new()
	for si in src.mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(src.mesh, si, xf)
		st.commit(am)
		var m: Material = src.mesh.surface_get_material(si)
		if tint != Color() and m is StandardMaterial3D and String(m.resource_name).contains("body"):
			m = (m as StandardMaterial3D).duplicate()
			(m as StandardMaterial3D).albedo_color = tint
		am.surface_set_material(am.get_surface_count() - 1, m)
	root.free()
	_cache[key] = am
	return am


static func mesh(weapon: String, t: int, side := "") -> ArrayMesh:
	var key := "%s_%d" % [weapon, t]
	if weapon == "turret":
		key += "_%d_%s" % [turret_style, side]
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
			_turret(parts, t, side)
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
	for mname in ["steel", "dark", "olive", "band", "white", "hull", "glass"]:
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
static func muzzle(weapon: String, cls := "", side := "") -> Vector3:
	if weapon == "turret" and TURRET_MODELS.has(cls):
		var spec: Dictionary = TURRET_MODELS[cls]
		return (spec.get("muzzle_tail" if side == "tail" and spec.has("tail") else "muzzle") as Vector3) * float(spec["s"])
	match weapon:
		"gunpod":
			return Vector3(0.78, 0, 0)
		"turret":
			return Vector3(0.72, 0.05, 0) * TURRET_K
		"rockets":
			return Vector3(0.5, 0, 0)
		"aam":
			return Vector3(0.5, 0, 0)
	return Vector3.ZERO


# ---------- турели ----------
# Стволы по +X (турель повёрнута стволами назад — yaw из mounts), срез у x = 0.72 до масштаба TURRET_K;
# основание верхней/нижней — на y = 0 (поверхность фюзеляжа); у кормовой начало координат — конец фюзеляжа.
# Ступени: 1 — спарка лёгких пушек, 2 — спарка тяжёлых с дульными тормозами, 3 — то же + прицел-радар.
const TURRET_K := 0.8


static func _turret(parts: Array, t: int, side: String) -> void:
	var st := turret_style
	var n0 := parts.size()
	if side == "tail":
		# корма: фюзеляж заканчивается установкой — остеклённой кабиной стрелка или металлическим конусом
		if st == 2:
			_tail_remote(parts, t)
		else:
			_tail_cabin(parts, t)
	elif st == 1:
		_dome(parts, t)
	else:
		_barbette(parts, t)
	for i in range(n0, parts.size()):
		parts[i][1] = Transform3D(Basis.from_scale(Vector3.ONE * TURRET_K)) * (parts[i][1] as Transform3D)


## Остеклённый колпак стрелка на погоне: стрелок под стеклом, пушки — из прорези спереди
static func _dome(parts: Array, t: int) -> void:
	parts.append([_cyl(0.22, 0.05), Transform3D(Basis(), Vector3(0, 0.02, 0)), "hull"])
	parts.append([_hemi(0.19), Transform3D(Basis().scaled(Vector3(1.15, 0.85, 1.0)), Vector3(0, 0.045, 0)), "glass"])
	parts.append([_torus(0.185, 0.2), Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.15, 1.0, 0.85)), Vector3(0, 0.045, 0)), "hull"])
	parts.append([_cyl(0.18, 0.016), Transform3D(Basis(), Vector3(0, 0.11, 0)), "hull"])
	parts.append([_box(Vector3(0.12, 0.07, 0.16)), Transform3D(Basis(), Vector3(0.2, 0.06, 0)), "dark"])
	_barrels(parts, t, 0.24, 0.06, 0.06)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(-0.05, 0.03, 0.2)), "hull"])


## Дистанционная башня: низкий обтекатель цвета обшивки, пушки из подвижной маски; стрелок — у прицела в кабине
static func _barbette(parts: Array, t: int) -> void:
	parts.append([_sphere(0.22), Transform3D(Basis().scaled(Vector3(1.45, 0.4, 1.0)), Vector3(-0.02, 0.0, 0)), "hull"])
	parts.append([_cyl(0.23, 0.03), Transform3D(Basis(), Vector3(-0.02, 0.0, 0)), "dark"])   # погон
	parts.append([_box(Vector3(0.09, 0.08, 0.2)), Transform3D(Basis(), Vector3(0.3, 0.04, 0)), "dark"])
	_barrels(parts, t, 0.33, 0.04, 0.07)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(-0.05, 0.03, 0.2)), "hull"])


## Кормовая кабина стрелка: остеклённый «фонарь» — продолжение фюзеляжа, спарка под ним
static func _tail_cabin(parts: Array, t: int) -> void:
	parts.append([_cyl(0.13, 0.32), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.06, 0, 0)), "hull"])
	parts.append([_cyl(0.135, 0.2), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.07, 0, 0)), "glass"])
	parts.append([_hemi(0.135), Transform3D(Basis(Vector3.BACK, -PI / 2.0).scaled(Vector3(1.0, 0.9, 1.0)), Vector3(0.17, 0, 0)), "glass"])
	for xr: float in [0.0, 0.1, 0.17]:
		parts.append([_torus(0.13, 0.145), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(xr, 0, 0)), "hull"])
	parts.append([_sphere(0.09), Transform3D(Basis().scaled(Vector3(1.2, 0.8, 1.0)), Vector3(0.22, -0.13, 0)), "dark"])
	_barrels(parts, t, 0.26, -0.13, 0.07)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(0.0, 0.14, 0)), "hull"])


## Кормовая дистанционная установка: металлический конус, сверху маленькое окно прицела
static func _tail_remote(parts: Array, t: int) -> void:
	parts.append([_cyl(0.12, 0.3), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.05, 0, 0)), "hull"])
	parts.append([_cone(0.12, 0.18), Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.19, 0, 0)), "hull"])
	parts.append([_hemi(0.05), Transform3D(Basis(), Vector3(-0.08, 0.11, 0)), "glass"])
	parts.append([_box(Vector3(0.1, 0.1, 0.16)), Transform3D(Basis(), Vector3(0.24, -0.02, 0)), "dark"])
	_barrels(parts, t, 0.28, -0.02, 0.06)
	if t == 3:
		parts.append([_sphere(0.05), Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.0)), Vector3(0.0, 0.12, 0.06)), "hull"])


## Спарка пушек от x0 до среза 0.72
static func _barrels(parts: Array, t: int, x0: float, y: float, gap: float) -> void:
	var r := 0.014 if t == 1 else 0.019
	var ln := 0.72 - x0
	for i in 2:
		var z := (i - 0.5) * gap
		parts.append([_cyl(r, ln), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(x0 + ln * 0.5, y, z)), "steel"])
		parts.append([_cyl(r * 1.8, ln * 0.3), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(x0 + ln * 0.15, y, z)), "dark"])
		if t >= 2:
			parts.append([_cyl(r * 1.6, 0.05), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.695, y, z)), "dark"])


# ---------- формы ----------

static func _hemi(r: float) -> SphereMesh:
	var s := _sphere(r)
	s.is_hemisphere = true
	s.height = r
	s.radial_segments = 20
	s.rings = 8
	return s


static func _torus(ri: float, ro: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = ri
	t.outer_radius = ro
	t.rings = 24
	t.ring_segments = 4
	return t


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
		"hull":   # металл обшивки: нейтральный серый, не спорит с окраской самолёта
			m.albedo_color = Color(0.52, 0.54, 0.55)
			m.metallic = 0.55
			m.roughness = 0.45
		"glass":  # остекление: тёмное, с бликом
			m.albedo_color = Color(0.4, 0.55, 0.62, 0.45)
			m.metallic = 0.85
			m.roughness = 0.06
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	var side: String = (pts[si % pts.size()] as Dictionary)["side"]
	var k := Tuning.g("plane_len") * p.size / float(tex1.get_width())   # пикселей мира на пиксель картинки
	var len_px: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) * Tuning.g("plane_len") / k
	var mz := muzzle(g.weapon, p.cls_id, side) * len_px
	var local := pt + Vector2(mz.x, mz.z)
	if not is_nan(aim):   # турель: ствол смотрит на цель
		local = pt + Vector2(mz.x, 0.0).rotated(aim - p.heading)
	return p.global_position + (local * k).rotated(p.heading)



## Точка турели сверху на крыле (пиксели картинки): по размаху — между фюзеляжем и мотогондолами
## (WING_TURRET_Z доли полуразмаха), по хорде — середина крыла на этой линии. side: -1 левое, 1 правое
const WING_TURRET_Z := {"bomber_1": 0.44, "bomber_2": 0.3}
static var _wing_pts := {}


static func wing_point(cls_id: String, lvl: int, side: float) -> Vector2:
	var key := "%s_%d" % [cls_id, lvl]
	if not _wing_pts.has(key):
		var t := PlaneArt.plane_tex(cls_id, lvl)
		var s := PlaneArt.shape_info(cls_id, lvl)
		var res := Vector2.ZERO
		if t != null and not s.is_empty():
			var img := t.get_image()
			if img.is_compressed():
				img.decompress()
			var w := img.get_width()
			var h := img.get_height()
			var zf: float = WING_TURRET_Z.get(key, 0.35)
			var row := int(h / 2.0 + float(s["half"]) * zf)
			# самый длинный непрерывный отрезок по строке — хорда крыла (без мотогондол спереди)
			var best0 := 0
			var best1 := -1
			var run0 := -1
			for x in w + 1:
				var on := x < w and img.get_pixel(x, clampi(row, 0, h - 1)).a > 0.4
				if on and run0 < 0:
					run0 = x
				elif not on and run0 >= 0:
					if x - run0 > best1 - best0:
						best0 = run0
						best1 = x
					run0 = -1
			res = Vector2((best0 + best1) / 2.0 - w / 2.0, row - h / 2.0)
		_wing_pts[key] = res
	var r: Vector2 = _wing_pts[key]
	return Vector2(r.x, absf(r.y) * signf(side))


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
		# решение владельца 16.10: кормовая — снизу под килем, две — сверху на крыльях
		var wl := wing_point(cls_id, lvl, -1.0)
		var wr := wing_point(cls_id, lvl, 1.0)
		order = [["tail", tail + L * 0.035, PI, 0.0], ["wing", wl.x, PI, wl.y], ["wing", wr.x, PI, wr.y]]
	else:
		# штурмовик: стрелок за кабиной (верхняя), вторая — нижняя под фюзеляжем
		order = [["top", nose - L * 0.36, PI, 0.0], ["bottom", nose - L * 0.45, PI, 0.0], ["tail", tail + L * 0.035, PI, 0.0]]
	for i in g.slots:
		var o: Array = order[i % order.size()]
		out.append({"p": Vector2(o[1], o[3]), "side": o[0], "yaw": o[2]})
	return out
