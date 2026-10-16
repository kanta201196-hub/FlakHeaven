class_name Hangar3D
extends Node
## 3.4-t1 (п. 1): самолёт в ангаре — объёмная модель Meshy максимального качества (models/hangar,
## ~50 тыс. треугольников, текстуры 2K) со стартовым оружием на узлах подвески.
## Мышью: тянуть — вращение, колесо — приближение, двойной щелчок — вид по умолчанию.
## Ур. 2 показывается всегда, даже если не куплен (тогда в вылет недоступен).
## Отрисовка: отдельный SubViewport, вкладка «САМОЛЁТ» (HudHangar) рисует его текстуру.

static var I: Hangar3D

const YAW0 := -2.3
const PITCH0 := 0.3
const DIST0 := 1.4

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var rect := Rect2()          # где на экране (в координатах ctrl) нарисован вид
var lvl_rects: Array = []    # [Rect2, ур.] — переключатель «Ур. 1 / Ур. 2»
var view_lvl := 1
var weapon_tier := 1        # п. 3: вид оружия — 1 (ур. 1–2), 2 (ур. 3–4), 3 (ур. 5)
var tier_rects: Array = []   # [Rect2, ступень]
var _ctrl: Control
var _key := ""
var _yaw := YAW0
var _pitch := PITCH0
var _dist := DIST0
var _drag := false
var _idle := 0.0             # секунд без мыши — потом медленно крутится сам
var _drawn_frame := -10
var _cls := ""


static func ensure(ctrl: Control) -> Hangar3D:
	if I == null or not is_instance_valid(I):
		I = Hangar3D.new()
		I._ctrl = ctrl
		ctrl.add_child(I)
	return I


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	vp = SubViewport.new()
	vp.size = Vector2i(640, 480)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.115)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.8)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 1.25
	key.shadow_enabled = true
	key.basis = Basis.looking_at(Vector3(0.5, -0.8, -0.35).normalized(), Vector3.UP)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.6, 0.72, 1.0)
	rim.light_energy = 0.45
	rim.basis = Basis.looking_at(Vector3(-0.6, -0.2, 0.75).normalized(), Vector3.UP)
	vp.add_child(rim)
	# пол ангара: тёмный бетон, на нём тень
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.21, 0.22)
	fm.roughness = 0.9
	floor_mi.material_override = fm
	floor_mi.position.y = -0.2
	vp.add_child(floor_mi)
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.02
	cam.far = 30.0
	vp.add_child(cam)
	cam.current = true


## Каждый кадр, пока открыта вкладка «САМОЛЁТ»: какой самолёт показать и где
func show_plane(cls_id: String, r: Rect2) -> Texture2D:
	if cls_id != _cls:
		_cls = cls_id
		view_lvl = 1
	rect = r
	_drawn_frame = Engine.get_process_frames()
	var sz := Vector2i(maxi(64, int(r.size.x)), maxi(64, int(r.size.y)))
	if vp.size != sz:
		vp.size = sz
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var k := "%s_%d_%d" % [cls_id, view_lvl, weapon_tier]
	if k != _key:
		_key = k
		_build(cls_id, view_lvl)
	return vp.get_texture()


func _build(cls_id: String, lvl: int) -> void:
	for c in pivot.get_children():
		c.queue_free()
	var path := "res://models/hangar/fh_hangar_%s_%d.glb" % [cls_id, lvl]
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	pivot.add_child(model)
	_add_weapons(cls_id, lvl)


## Стартовое оружие класса на узлах подвески — под крылом / в бомбоотсеке (те же точки, что в игре)
func _add_weapons(cls_id: String, lvl: int) -> void:
	var tex := PlaneArt.plane_tex(cls_id, lvl)
	var tex1 := PlaneArt.plane_tex(cls_id, 1)
	if tex == null or tex1 == null:
		return
	var data := PlaneClasses.get_data(cls_id)
	var groups: Array = []
	for gd in data["groups"]:
		groups.append(Hardpoint.new(gd["name"], int(gd["slots"]), gd["weapon"]))
	if int(data["turrets"]) > 0:
		groups.append(Hardpoint.new("Турели", int(data["turrets"]), "turret", true))
	var tw := float(tex.get_width())
	# длина самолёта в игре: plane_len × размер класса × (ширина картинки ур. / ур. 1); модель — длиной 1
	var plane_k := float(data["size"]) * tw / float(tex1.get_width())
	for gi in groups.size():
		var g: Hardpoint = groups[gi]
		if g.is_empty():
			continue
		var wt := PlaneArt.weapon_tex(g.weapon)
		if wt == null:
			continue
		var wlen: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) / plane_k
		for pt: Vector2 in PlaneArt.slot_points(cls_id, lvl, gi, g):
			var wmi := WeaponModels.make(g.weapon, weapon_tier)
			# турели — сверху по фюзеляжу, подвесы — под крылом
			var y := 0.035 if g.builtin else -0.045
			wmi.position = Vector3(pt.x / tw, y, pt.y / tw)
			wmi.basis = Basis().scaled(Vector3(wlen, wlen, wlen))
			pivot.add_child(wmi)


func _process(delta: float) -> void:
	if Engine.get_process_frames() - _drawn_frame > 2:
		if vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_drag = false
		return
	_idle += delta
	if not _drag and _idle > 3.0:
		_yaw += delta * 0.25
	_pitch = clampf(_pitch, -0.2, 1.35)
	_dist = clampf(_dist, 0.7, 3.2)
	var dir := Vector3(cos(_pitch) * cos(_yaw), sin(_pitch), cos(_pitch) * sin(_yaw))
	cam.position = dir * _dist
	cam.look_at(Vector3.ZERO, Vector3.UP)


func _input(event: InputEvent) -> void:
	if Engine.get_process_frames() - _drawn_frame > 2 or _ctrl == null:
		return
	var mp := _ctrl.get_local_mouse_position()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				for lr in lvl_rects:
					if (lr[0] as Rect2).has_point(mp):
						view_lvl = int(lr[1])
						get_viewport().set_input_as_handled()
						return
				for tr in tier_rects:
					if (tr[0] as Rect2).has_point(mp):
						weapon_tier = int(tr[1])
						get_viewport().set_input_as_handled()
						return
				if rect.has_point(mp):
					if mb.double_click:
						_yaw = YAW0
						_pitch = PITCH0
						_dist = DIST0
					_drag = true
					_idle = 0.0
					get_viewport().set_input_as_handled()
			else:
				_drag = false
		elif mb.pressed and rect.has_point(mp) and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_dist *= 0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			_idle = 0.0
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * 0.008
		_pitch += mm.relative.y * 0.006
		_idle = 0.0
