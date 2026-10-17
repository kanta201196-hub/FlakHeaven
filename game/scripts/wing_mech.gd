class_name WingMech
## Т-1: предкрылки и закрылки — часть базовой модели каждого самолёта (решение владельца 16.10, модуль 3).
## Пластины — отдельный GLB в осях модели (tools/blender/wing_mech.py → models/mech/fh_mech_<класс>_<ур>.glb):
## узлы slat_l / slat_r / flap_l / flap_r, точка узла — середина шарнира, локальная −Z — вдоль шарнира.
## В вираже и при торможении закрылки опускаются, предкрылки выдвигаются вперёд-вниз;
## модуль «Механизация крыла» (cards.gd: wing) только ускоряет выпуск: ×1 без модуля → ×2 на ур. 5.

const FLAP_DEG := 22.0     # закрылки вниз
const SLAT_DEG := 12.0     # предкрылки носком вниз
const SLAT_OUT := 0.008    # и вперёд, в длинах модели
const RATE := 1.6          # доля полного хода в секунду без модуля

static var _scenes := {}
static var _force := OS.get_cmdline_user_args().has("--mechdown")   # стенд: всё выпущено


## Подвесить механизацию к модели (key — «fighter_1» и т. п.); null, если для модели её нет
static func attach(model: Node3D, key: String) -> Node3D:
	var path := "res://models/mech/fh_mech_%s.glb" % key
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return null
	var mech: Node3D = (_scenes[path] as PackedScene).instantiate()
	mech.name = "wing_mech"
	attach_skin(mech, model)   # цвет пластин — вершинный (снят с текстуры крыла под ними)
	for n in ["slat_l", "slat_r", "flap_l", "flap_r"]:
		var part := mech.find_child(n, true, false) as Node3D
		if part != null:
			part.set_meta("rest", part.transform)
	mech.set_meta("t", 0.0)
	model.add_child(mech)
	return mech


## Выпуск 0…1: крен (|bank| 0…1) и торможение (0…1); wing_lvl — уровень модуля «Механизация крыла»
static func update(mech: Node3D, bank: float, brake: float, wing_lvl: int, delta: float) -> void:
	var want := 1.0 if _force else maxf(smoothstep(0.45, 0.95, absf(bank)), clampf(brake, 0.0, 1.0))
	var rate := RATE * (1.0 + 0.2 * clampi(wing_lvl, 0, 5))
	var t := move_toward(float(mech.get_meta("t", 0.0)), want, rate * delta)
	mech.set_meta("t", t)
	pose(mech, t)


static func pose(mech: Node3D, t: float) -> void:
	for n in ["slat_l", "slat_r", "flap_l", "flap_r"]:
		var part := mech.find_child(n, true, false) as Node3D
		if part == null or not part.has_meta("rest"):
			continue
		var rest: Transform3D = part.get_meta("rest")
		# ось шарнира — локальная −Z узла (Y в Blender): закрылок вниз — отрицательный угол, предкрылок — положительный
		if n.begins_with("flap"):
			part.transform = rest * Transform3D(Basis(Vector3.FORWARD, -deg_to_rad(FLAP_DEG) * t), Vector3.ZERO)
		else:
			part.transform = rest * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(SLAT_DEG) * t), Vector3(SLAT_OUT * t, 0, 0))


## Мигание неуязвимости — как у самой модели
static func set_transparency(mech: Node3D, v: float) -> void:
	for c in mech.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).transparency = v


# ---------- Т-5: створки бомбоотсека «Кита» ----------
## tools/blender/bay_doors.py → models/mech/fh_bay_<класс>_<ур>.glb: узлы bay_l / bay_r, петля по внешней
## кромке вдоль локальной X; открытие — поворот вокруг X (левая +угол, правая −угол), ниша bay_well_* под ними.
const BAY_DEG := 85.0
const BAY_RATE := 3.0         # доля хода в секунду
const BAY_HOLD := 1.2         # сколько створки открыты после сброса, с


static func attach_bay(model: Node3D, key: String) -> Node3D:
	var path := "res://models/mech/fh_bay_%s.glb" % key
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return null
	var bay: Node3D = (_scenes[path] as PackedScene).instantiate()
	bay.name = "bay_doors"
	attach_skin(bay, model)
	for n in ["bay_l", "bay_r"]:
		var part := bay.find_child(n, true, false) as Node3D
		if part != null:
			part.set_meta("rest", part.transform)
	bay.set_meta("t", 0.0)
	bay.set_meta("hold", 0.0)
	model.add_child(bay)
	return bay


## Пластины, створки и кабина — вершинный цвет (снят с текстуры самолёта под ними); металл и шероховатость —
## средние по карте металла самой модели (Meshy: G — шероховатость, B — металл), иначе кабина темнее обшивки
static func attach_skin(node: Node3D, model: Node3D = null) -> void:
	var mr := _metal_rough(model)
	var key := "%.2f_%.2f" % [mr.x, mr.y]
	if not _skins.has(key):
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.vertex_color_is_srgb = false   # COLOR_0 в glTF — уже линейный
		# среднее по атласу занижено пустым фоном Meshy и даёт «чёрный металл» при тёмном альбедо —
		# металл вдвое слабее, блеск сильнее, альбедо чуть светлее: на вид как обшивка рядом
		sm.metallic = mr.x * 0.5
		sm.roughness = mr.y * 0.8
		sm.albedo_color = Color(1.3, 1.3, 1.3)
		_skins[key] = sm
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m != null and String(m.resource_name).begins_with("mech_skin"):
				mi.set_surface_override_material(si, _skins[key])


static var _skins := {}
static var _mr_cache := {}


static func _metal_rough(model: Node3D) -> Vector2:
	var res := Vector2(0.25, 0.6)
	if model == null:
		return res
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var m := (c as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
		if m == null or m.metallic_texture == null:
			continue
		var tex := m.metallic_texture
		if not _mr_cache.has(tex):
			var img := tex.get_image()
			if img == null:
				return res
			if img.is_compressed():
				img.decompress()
			img.resize(32, 32)
			var sum := Vector2.ZERO
			for y in 32:
				for x in 32:
					var px := img.get_pixel(x, y)
					sum += Vector2(px.b, px.g)
			_mr_cache[tex] = Vector2(m.metallic, m.roughness) * sum / 1024.0
		return _mr_cache[tex]
	return res


## dropped — в этом кадре сброшены бомбы: створки открываются и держатся BAY_HOLD секунд; возвращает выпуск 0…1
static func update_bay(bay: Node3D, dropped: bool, delta: float) -> float:
	var hold := BAY_HOLD if dropped else maxf(0.0, float(bay.get_meta("hold", 0.0)) - delta)
	bay.set_meta("hold", hold)
	var t := move_toward(float(bay.get_meta("t", 0.0)), 1.0 if hold > 0.0 or _force else 0.0, BAY_RATE * delta)
	bay.set_meta("t", t)
	pose_bay(bay, t)
	return t


static func pose_bay(bay: Node3D, t: float) -> void:
	for n in ["bay_l", "bay_r"]:
		var part := bay.find_child(n, true, false) as Node3D
		if part == null or not part.has_meta("rest"):
			continue
		var a := deg_to_rad(BAY_DEG) * t * (1.0 if n == "bay_l" else -1.0)
		part.transform = (part.get_meta("rest") as Transform3D) * Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO)


# ---------- кормовая кабина «Кита» (тест 3.5-s3) ----------
## tools/blender/tail_cabin.py → models/mech/fh_tail_<класс>_<ур>.glb: продолжение фюзеляжа в цвет обшивки,
## узел ball_mount — центр шара со стволами. Вместо общей кабины turret_kit_tail_cabin.glb.
static func attach_tail(model: Node3D, key: String) -> Node3D:
	var path := "res://models/mech/fh_tail_%s.glb" % key
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return null
	var tail: Node3D = (_scenes[path] as PackedScene).instantiate()
	tail.name = "tail_cabin"
	attach_skin(tail, model)
	model.add_child(tail)
	return tail


## Точка шара установки в осях узла base (pivot ангара или корень боевой модели)
static func tail_mount(tail: Node3D, base: Node3D) -> Vector3:
	var m := tail.find_child("ball_mount", true, false) as Node3D
	if m == null:
		return Vector3.INF
	return (base.global_transform.affine_inverse() * m.global_transform).origin


# ---------- Т-2: отличие «Грача 2», видное сверху ----------
## tools/blender/attacker2_detail.py → models/mech/fh_detail_<класс>_<ур>.glb: ПГО перед кабиной и крупные
## контейнеры на законцовках; цвет — в материале детали (средний тон обшивки под ней)
static func attach_detail(model: Node3D, key: String) -> Node3D:
	var path := "res://models/mech/fh_detail_%s.glb" % key
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return null
	var det: Node3D = (_scenes[path] as PackedScene).instantiate()
	det.name = "detail"
	model.add_child(det)
	return det

