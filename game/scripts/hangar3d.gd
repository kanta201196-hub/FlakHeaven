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
## Стенд --hangarevo: оружие в пустых группах (класс → [оружие по группам]), чтобы показать все эволюции
static var bench_weapons := {}
var weapon_tier := 1        # п. 3: вид оружия — 1 (ур. 1–2), 2 (ур. 3–4), 3 (ур. 5), 4 — эволюция (Т-4)
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
var focus := Vector3.ZERO    # куда смотрит камера (стенд крупных планов турелей)
var turret_pos: Array = []   # [Vector3, сторона] — турели текущей модели


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
	turret_pos.clear()
	_collect_faces(model)
	# Т-1: предкрылки и закрылки; в ангаре убраны (стенд --mechdown показывает выпущенными)
	var mech := WingMech.attach(model, "%s_%d" % [cls_id, lvl])
	if mech != null and OS.get_cmdline_user_args().has("--mechdown"):
		WingMech.pose(mech, 1.0)
	# тест 3.5-s3: кормовая кабина «Кита» — продолжение фюзеляжа в цвет обшивки
	_tail = WingMech.attach_tail(model, "%s_%d" % [cls_id, lvl])
	# Т-5: створки бомбоотсека в ангаре открыты — видно бомбы
	var bay := WingMech.attach_bay(model, "%s_%d" % [cls_id, lvl])
	if bay != null:
		WingMech.pose_bay(bay, 1.0)
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
		if bench_weapons.has(cls_id) and gi < (bench_weapons[cls_id] as Array).size() and bench_weapons[cls_id][gi] != "":
			g.weapon = bench_weapons[cls_id][gi]
		g.evo = weapon_tier == 4
		g.level = [1, 3, 5][mini(weapon_tier, 3) - 1]   # ступень вида → уровень оружия (ловушки ставятся по уровню)
		if g.is_empty():
			continue
		var wt := PlaneArt.weapon_tex(g.weapon)
		if wt == null:
			continue
		var wlen: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) / plane_k
		for mt: Dictionary in WeaponModels.mounts(cls_id, lvl, gi, g):
			var pt: Vector2 = mt["p"]
			var side: String = mt["side"]
			var mtr: int = mt.get("t", mini(weapon_tier, 3))
			var wmi := WeaponModels.make(g.weapon, mtr, side, cls_id, weapon_tier == 4, lvl)
			# по настоящей поверхности модели: подвес — под крылом на пилоне, верхняя турель
			# утоплена в спину фюзеляжа, нижняя — в брюхо, кормовая — в конце фюзеляжа
			var x := pt.x / tw
			var z := pt.y / tw
			var lo := _surface_y(x, z, true)
			var hi := _surface_y(x, z, false)
			var y := 0.0
			match side:
				"under":
					y = (lo if not is_nan(lo) else -0.02) - WeaponModels.hang(g.weapon, mtr, weapon_tier == 4) * wlen
				"belly":   # Т-6: «Бабушкин ковёр» — своим узлом прямо к брюху, без пилона
					y = (lo if not is_nan(lo) else -0.03) - (WeaponModels.hang(g.weapon, 3, true) - WeaponModels.PYLON_H) * wlen
				"top", "wing":
					y = hi if not is_nan(hi) else 0.03
				"bay":   # Т-5: бомбы «Кита» в открытом бомбоотсеке — верх утоплен в фюзеляж
					y = (lo if not is_nan(lo) else -0.03) - (WeaponModels.hang(g.weapon, mtr) - WeaponModels.PYLON_H) * wlen * 0.6
				"tip":   # Т-5: контейнер ловушек на законцовке — по оси крыла
					# законцовка картинки шире модели — ищем крыло ближе к оси и вперёд по хорде
					var k := 0
					while is_nan(lo) and k < 30:
						z *= 0.98
						x += 0.004
						lo = _surface_y(x, z, true)
						hi = _surface_y(x, z, false)
						k += 1
					y = (lo + hi) * 0.5 if not is_nan(lo) else 0.0
				"bottom":
					y = lo if not is_nan(lo) else -0.03
				"tail":
					# корма: установка — продолжение фюзеляжа; ищем, где фюзеляж кончается на оси
					var xe := -0.52
					while xe < x + 0.1 and is_nan(_surface_y(xe, 0.0, true)):
						xe += 0.004
					x = xe + 0.006
					z = 0.0
					var l2 := _surface_y(x, 0.0, true)
					var h2 := _surface_y(x, 0.0, false)
					y = 0.0 if is_nan(l2) else ((l2 + h2) * 0.5 if h2 - l2 < 0.03 else l2 + 0.012)
					if (WeaponModels.TURRET_MODELS.get(cls_id, {}) as Dictionary).has("tail"):
						# кабина стрелка с шаровой установкой: шар сразу за концом фюзеляжа, кабина — внутри него
						x = xe + 0.012
						y = 0.0 if is_nan(l2) else (l2 + h2) * 0.5
					elif WeaponModels.TURRET_MODELS.has(cls_id):
						# турель-модель: под концом фюзеляжа, основанием вверх (сверху мешает киль)
						x = xe + 0.035
						var l3 := _surface_y(x, 0.0, true)
						y = l3 if not is_nan(l3) else y
			wmi.position = Vector3(x, y, z)
			if side == "tail" and g.weapon == "turret" and _tail != null:
				var tp := WingMech.tail_mount(_tail, pivot)
				if tp != Vector3.INF:
					wmi.position = tp
					var cab := wmi.find_child("cabin", false, false)
					if cab != null:
						cab.visible = false   # своя кабина модели вместо общей
			if g.weapon == "turret":
				turret_pos.append([wmi.position, side])
			var bs := Basis(Vector3.UP, float(mt["yaw"]))
			if side == "bottom" or (side == "tail" and WeaponModels.TURRET_MODELS.has(cls_id) and not (WeaponModels.TURRET_MODELS[cls_id] as Dictionary).has("tail")):
				bs = bs * Basis(Vector3.RIGHT, PI)
			wmi.basis = bs.scaled(Vector3(wlen, wlen, wlen))
			pivot.add_child(wmi)


var _faces := PackedVector3Array()
var _tail: Node3D = null


## Треугольники модели (в осях pivot) — чтобы найти поверхность крыла под точкой подвеса
func _collect_faces(model: Node3D) -> void:
	_faces = PackedVector3Array()
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf := pivot.global_transform.affine_inverse() * mi.global_transform
		for v in mi.mesh.get_faces():
			_faces.append(xf * v)


## Высота поверхности модели на вертикали (x, z): нижняя (low) или верхняя; NAN — промах
var _ycache := {}


func _surface_y(x: float, z: float, low: bool) -> float:
	var ck := "%s|%.4f|%.4f|%s" % [_key.get_slice("_", 0) + _key.get_slice("_", 1), x, z, low]
	if _ycache.has(ck):
		return _ycache[ck]
	var best := NAN
	var p := Vector2(x, z)
	for i in range(0, _faces.size(), 3):
		var a := _faces[i]
		var b := _faces[i + 1]
		var c := _faces[i + 2]
		var a2 := Vector2(a.x, a.z)
		var v0 := Vector2(b.x, b.z) - a2
		var v1 := Vector2(c.x, c.z) - a2
		var v2 := p - a2
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-12:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u < 0.0 or w < 0.0 or u + w > 1.0:
			continue
		var y := a.y + u * (b.y - a.y) + w * (c.y - a.y)
		if is_nan(best) or (low and y < best) or (not low and y > best):
			best = y
	_ycache[ck] = best
	return best


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
	_dist = clampf(_dist, 0.7 if focus == Vector3.ZERO else 0.2, 3.2)
	var dir := Vector3(cos(_pitch) * cos(_yaw), sin(_pitch), cos(_pitch) * sin(_yaw))
	cam.position = focus + dir * _dist
	cam.look_at(focus, Vector3.UP)


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
