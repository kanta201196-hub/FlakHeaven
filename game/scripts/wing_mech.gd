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
static var _skin: StandardMaterial3D


## Подвесить механизацию к модели (key — «fighter_1» и т. п.); null, если для модели её нет
static func attach(model: Node3D, key: String) -> Node3D:
	var path := "res://models/mech/fh_mech_%s.glb" % key
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return null
	var mech: Node3D = (_scenes[path] as PackedScene).instantiate()
	mech.name = "wing_mech"
	if _skin == null:
		# цвет пластин — вершинный (снят с текстуры крыла под ними)
		_skin = StandardMaterial3D.new()
		_skin.vertex_color_use_as_albedo = true
		_skin.vertex_color_is_srgb = true
		_skin.roughness = 0.6
		_skin.metallic = 0.25
	for c in mech.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m != null and String(m.resource_name).begins_with("mech_skin"):
				mi.set_surface_override_material(si, _skin)
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
