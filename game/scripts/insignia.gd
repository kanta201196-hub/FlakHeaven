class_name Insignia
## V-07: свои знаки на самолётах (решение Kanta 17.10: все шесть, art/insignia/insignia_N.png).
## Наклейки по обшивке — отдельный GLB в осях модели (tools/blender/insignia.py → models/mech/fh_ins_<класс>_<ур>.glb):
## узлы wing_l / wing_r (сверху на крыльях), fin_l / fin_r (киль), side_l / side_r (борт за кабиной).
## Крыло — без знака: «Вершину» (1) Kanta 28.10 велел убрать с крыльев, узлы wing_l / wing_r удаляются. Киль — знак класса: 2 «Стрела» у «Осы», 4 «Перо» у «Грача»,
## 5 «Винт» у «Кита»; у ведомых — 3 «Шевроны». Борт — 6 «Коготь» у асов: экипаж от ACE_RANK звания.

const ACE_RANK := 15
const CLASS_MARK := {"fighter": 2, "attacker": 4, "bomber": 5}
const WING_MARK := 1   ## fallback fin mark of a class not in CLASS_MARK; the wings themselves carry none any more
const WINGMAN_MARK := 3
const ACE_MARK := 6

static var _scenes := {}
static var _mats := {}
static var _force_ace := OS.get_cmdline_user_args().has("--ace")   # стенд: знак аса на всех


## role: "player" — свой самолёт (в ангаре и в бою), "wing" — ведомый; null, если для модели наклеек нет
static func attach(model: Node3D, key: String, role := "player") -> Node3D:
	var path := "res://models/mech/fh_ins_%s.glb" % key
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return null
	var cls := key.get_slice("_", 0)
	var ins: Node3D = (_scenes[path] as PackedScene).instantiate()
	ins.name = "insignia"
	var fin: int = WINGMAN_MARK if role == "wing" else int(CLASS_MARK.get(cls, WING_MARK))
	var ace := role == "player" and (_force_ace or Profile.crew_lvl(cls) >= ACE_RANK)
	for c in ins.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		# узел наклейки — родитель меша (glTF: узел → MeshInstance3D) или сам меш
		var n := String(mi.name) if String(mi.name).begins_with("wing") or String(mi.name).begins_with("fin") \
				or String(mi.name).begins_with("side") else String(mi.get_parent().name)
		if n.begins_with("wing"):
			# Kanta 28.10: no roundel on the wings. Freed, not hidden, so the decal code (PlaneDecals roundel hull,
			# the editor's «a roundel will cover this» note) finds no roundel either and decals may go there.
			mi.free()
			continue
		var mark: int = fin if n.begins_with("fin") else (ACE_MARK if ace else 0)
		mi.visible = mark > 0
		if mark > 0:
			mi.material_override = _mat(mark)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(ins)
	if role == "player":   # the player's own decals (free placement, Kanta 27.10); wingmen have none
		PlaneDecals.attach(model, key, ins)
	return ins


static func _mat(mark: int) -> StandardMaterial3D:
	if not _mats.has(mark):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://art/insignia/insignia_%d.png" % mark)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.roughness = 0.75
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mats[mark] = m
	return _mats[mark]


## Мигание неуязвимости — как у самой модели
static func set_transparency(ins: Node3D, v: float) -> void:
	for c in ins.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).transparency = v
