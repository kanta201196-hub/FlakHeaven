class_name Render3D
extends Node3D
## 3.0: трёхмерная картинка мира. Логика игры по-прежнему в 2D (Vector2, пиксели) —
## этот узел каждый кадр «отражает» её в 3D:
##   • камера смотрит строго вниз с перспективой и следует за 2D-камерой — плоскость боя (y = 0)
##     совпадает с 2D-слоем пиксель в пиксель, поэтому пули, взрывы, интерфейс остаются 2D;
##   • земля, объекты биома, облака — ниже/выше плоскости боя: перспектива даёт глубину и параллакс;
##   • самолёты и враги — объёмные модели (ReliefMesh) с креном, «бочкой», светом и тенями;
##   • солнце сверху-слева, тени на земле.
## 2D→3D: (x, y) → (x, высота, y).

const FOV := 50.0
const GROUND_Y := -70.0      # земля ниже плоскости боя: тени и параллакс
const CLOUD_Y := 380.0       # облака между камерой и самолётами
const ON := true

static var I: Render3D
static var enabled := true

var cam: Camera3D
var sun: DirectionalLight3D
var ground: MeshInstance3D
var _units := {}      # instance_id → {node, kind, prev_heading, bank}
var _objs := {}       # ключ клетки → MeshInstance3D
var _clouds: Array = []
var _scorch: Array = []
var _scorch_mesh: QuadMesh
var _scorch_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _elite_mat: StandardMaterial3D
var _zoom := 1.0


func _ready() -> void:
	I = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = Tuning.g("render3d") > 0.5
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.47, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.7, 0.68)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = false
	env.environment = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 4000.0
	sun.shadow_bias = 0.05
	# свет сверху-слева (на экране): тени уходят вниз-вправо
	sun.basis = Basis.looking_at(Vector3(0.45, -1.0, 0.6).normalized(), Vector3(0, 0, -1))
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 10.0
	cam.far = 6000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(cam)
	cam.current = true

	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	ground.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/ground3d.gdshader")
	for n in [["t_sand", "sand"], ["t_clay", "clay"], ["t_gravel", "gravel"], ["t_river", "riverbed"]]:
		var p := "res://art/ground/g_%s.png" % n[1]
		if ResourceLoader.exists(p):
			sm.set_shader_parameter(n[0], load(p))
	sm.set_shader_parameter("seed", float(randi() % 1000))
	ground.material_override = sm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	_scorch_mesh = QuadMesh.new()
	_scorch_mesh.size = Vector2(1, 1)
	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.albedo_texture = Fx._soft
	_scorch_mat.albedo_color = Color(0.04, 0.03, 0.02, 0.55)
	_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1, 1, 1, 0.75)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_elite_mat = StandardMaterial3D.new()
	_elite_mat.albedo_color = Color(1.0, 0.75, 0.2, 0.28)
	_elite_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_elite_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# ---------- камера ----------

func _cam_height(zoom: float) -> float:
	var vh := get_viewport().get_visible_rect().size.y
	return (vh / maxf(zoom, 0.01)) / (2.0 * tan(deg_to_rad(FOV) / 2.0))


## Точка на земле, которая на экране совпадает с точкой p плоскости боя (для наземных целей и пятен)
func ground_under(p: Vector2) -> Vector3:
	var c := cam.global_position
	var h := c.y
	var k := (h - GROUND_Y) / h
	return Vector3(c.x + (p.x - c.x) * k, GROUND_Y, c.z + (p.y - c.z) * k)


func _process(delta: float) -> void:
	enabled = Tuning.g("render3d") > 0.5
	visible = enabled
	if not enabled:
		return
	var m := Main.I
	if m == null or m.camera == null:
		return
	# центр и масштаб берём из того, как реально нарисован 2D-слой (с тряской и сглаживанием)
	var ct := get_viewport().get_canvas_transform()
	var vs := get_viewport().get_visible_rect().size
	var c2 := ct.affine_inverse() * (vs / 2.0)
	var zoom := ct.get_scale().y
	if not (is_finite(c2.x) and is_finite(c2.y) and zoom > 0.001):
		return
	_zoom = zoom
	var h := _cam_height(zoom)
	cam.global_position = Vector3(c2.x, h, c2.y)
	cam.basis = Basis.looking_at(Vector3(0, -1, 0), Vector3(0, 0, -1))
	# земля — большой квадрат под камерой
	var span := h * 2.6 + 3000.0
	ground.global_position = Vector3(c2.x, GROUND_Y, c2.y)
	ground.scale = Vector3(span, 1, span)
	_sync_units(m, delta)
	_sync_objects(c2, h)
	_sync_clouds(m, c2, h)
	_sync_scorch(m)
	_sync_lights(delta)
	if OS.get_cmdline_user_args().has("--dbg3") and Engine.get_process_frames() % 30 == 0:
		var pp := m.player.global_position if is_instance_valid(m.player) else Vector2.ZERO
		print("R3D c2=", c2, " ct=", get_viewport().get_canvas_transform(), " cam=", cam.global_position, " zoom=", m.camera.zoom, " player=", pp, " units=", _units.size(), " objs=", _objs.size())
		for id in _units:
			var u: Dictionary = _units[id]
			if u["kind"] == "player":
				print("  P ", (u["node"] as Node3D).global_transform, " k=", u["k"])


# ---------- самолёты и наземные цели ----------

func _unit_mesh(tex: Texture2D, length_px: float, thick: float, grid: int) -> Dictionary:
	var mesh := ReliefMesh.build(tex, tex.get_width() * thick, grid)
	return {"mesh": mesh, "mat": ReliefMesh.material(tex), "k": length_px / float(tex.get_width())}


func _ensure(id: int, kind: String, tex: Texture2D, length_px: float, thick: float, grid := 56) -> Dictionary:
	var u: Dictionary = _units.get(id, {})
	if u.is_empty() or u["tex"] != tex:
		if not u.is_empty():
			(u["node"] as Node).queue_free()
		var root := Node3D.new()
		var mi := MeshInstance3D.new()
		var d := _unit_mesh(tex, length_px, thick, grid)
		mi.mesh = d["mesh"]
		mi.material_override = d["mat"]
		root.add_child(mi)
		add_child(root)
		u = {"node": root, "mi": mi, "kind": kind, "tex": tex, "k": d["k"], "ph": 0.0, "bank": 0.0, "seen": true, "weapons": {}}
		_units[id] = u
	u["seen"] = true
	return u


func _place(u: Dictionary, p: Vector2, heading: float, bank: float, roll: float, y := 0.0, scale_k := 1.0) -> void:
	var root: Node3D = u["node"]
	root.position = Vector3(p.x, y, p.y)
	var b := Basis(Vector3.UP, -heading) * Basis(Vector3.RIGHT, bank + roll)
	var k: float = u["k"] * scale_k
	root.basis = b.scaled(Vector3(k, k, k))


func _sync_units(m: Main, delta: float) -> void:
	for id in _units:
		_units[id]["seen"] = false
	var p := m.player
	if is_instance_valid(p) and p.is_visible_in_tree():
		var tex := PlaneArt.plane_tex(p.cls_id, p.plane_lvl)
		if tex != null:
			var u := _ensure(p.get_instance_id(), "player", tex, Tuning.g("plane_len") * p.size * (float(tex.get_width()) / PlaneArt.plane_tex(p.cls_id, 1).get_width()), 0.075, 72)
			var roll := 0.0
			if p.roll_t > 0.0:
				roll = (1.0 - p.roll_t / p.roll_time()) * TAU * p.roll_dir
			_place(u, p.global_position, p.heading, p.bank * 0.45, roll)
			var mi: MeshInstance3D = u["mi"]
			mi.transparency = 0.6 if (p.invuln > 0.0 and p.roll_t <= 0.0 and int(p._blink * 20.0) % 2 == 0) else 0.0
			_sync_weapons(u, p, tex)
		for w in p.wingmen:
			var wm: Wingman = w
			var wt := wm.plane_tex()
			if wt == null or not wm.alive():
				continue
			var len_w := Tuning.g("plane_len") * 0.85 * float(wt.get_width()) / float(PlaneArt.plane_tex("fighter", 1).get_width())
			var uw := _ensure(wm.get_instance_id(), "wing", wt, len_w, 0.075, 48)
			_place(uw, wm.global_position, wm.heading, _turn_bank(uw, wm.heading, delta), 0.0)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var info := e.sprite_info()
		if info.is_empty():
			continue
		var t: Texture2D = Enemy.etex(info["tex"])
		if t == null:
			continue
		var len_px: float = float(info["len"]) * Tuning.g("unit_scale") * (1.2 if e.elite else 1.0)
		var ue := _ensure(e.get_instance_id(), "enemy", t, len_px, 0.05 if e.is_ground else 0.07, 40 if not e.is_boss else 64)
		var ang: float = info.get("angle", e.heading)
		if e.is_ground:
			var gp := ground_under(e.global_position)
			_place(ue, Vector2(gp.x, gp.z), ang, 0.0, 0.0, GROUND_Y + 1.0, (cam.global_position.y - GROUND_Y) / cam.global_position.y)
		else:
			_place(ue, e.global_position, ang, _turn_bank(ue, ang, delta), 0.0)
		var mi2: MeshInstance3D = ue["mi"]
		mi2.material_overlay = _flash_mat if e._flash > 0.0 else (_elite_mat if e.elite else null)
	for id in _units.keys():
		if not _units[id]["seen"]:
			(_units[id]["node"] as Node).queue_free()
			_units.erase(id)


## Крен от скорости поворота (для врагов и ведомых)
func _turn_bank(u: Dictionary, heading: float, delta: float) -> float:
	var dh := wrapf(heading - float(u["ph"]), -PI, PI)
	u["ph"] = heading
	var target := clampf(dh / maxf(delta, 0.001) * 0.35, -1.0, 1.0)
	u["bank"] = lerpf(float(u["bank"]), target, 1.0 - exp(-delta * 6.0))
	return float(u["bank"])


## Подвесы — объёмные модели на точках подвеса поверх крыла
func _sync_weapons(u: Dictionary, p: Player, tex: Texture2D) -> void:
	var root: Node3D = u["node"]
	var want := {}
	var half := tex.get_size() / 2.0
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		if g.is_empty():
			continue
		var wt := PlaneArt.weapon_tex(g.weapon)
		if wt == null:
			continue
		var pts := PlaneArt.slot_points(p.cls_id, p.plane_lvl, gi, g)
		var k: float = u["k"]
		var len_px: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) * Tuning.g("plane_len") / k  # в пикселях текстуры самолёта
		var dim := g.weapon in ["aam", "rockets", "bombs"] and g.cd > 0.3
		for si in pts.size():
			var key := "%d_%d_%s" % [gi, si, g.weapon]
			want[key] = true
			var wmi: MeshInstance3D = u["weapons"].get(key)
			if wmi == null:
				wmi = MeshInstance3D.new()
				wmi.mesh = ReliefMesh.build(wt, wt.get_width() * 0.35, 24)
				wmi.material_override = ReliefMesh.material(wt, 0.5, 0.4)
				root.add_child(wmi)
				u["weapons"][key] = wmi
			var pt: Vector2 = pts[si]
			var wk := len_px / float(wt.get_height())
			# текстура оружия носом вверх → поворот на 90°, чтобы нос смотрел по +X
			wmi.position = Vector3(pt.x, tex.get_width() * 0.03, pt.y)
			wmi.basis = Basis(Vector3.UP, -PI / 2.0).scaled(Vector3(wk, wk, wk))
			wmi.transparency = 0.6 if dim else 0.0
	for key in u["weapons"].keys():
		if not want.has(key):
			(u["weapons"][key] as Node).queue_free()
			u["weapons"].erase(key)


# ---------- объекты биома ----------

## Потолок рельефа: 70 px до плоскости боя минус запас на крен и толщину моделей.
const OBJ_MAX_H := 48.0

const OBJ_RELIEF := {
	"o_rocks_big": [0.16, 0.45], "o_rocks_small": [0.18, 0.45], "o_mesa": [0.16, 0.25],
	"o_fort": [0.07, 0.35], "o_village": [0.05, 0.35], "o_oasis": [0.06, 0.5], "o_crater": [0.0, 0.0], "o_wreck": [0.04, 0.2],
}


func _sync_objects(c2: Vector2, h: float) -> void:
	var bg: Background = Main.I.background
	if bg == null or not bg.biome_ok:
		return
	var half := get_viewport().get_visible_rect().size / _zoom * 0.5 * ((h - GROUND_Y) / h) + Vector2(900, 900)
	var view := Rect2(c2 - half, half * 2.0)
	var seen := {}
	var CH := Background.CHUNK
	for cx in range(int(floorf(view.position.x / CH)), int(floorf(view.end.x / CH)) + 1):
		for cy in range(int(floorf(view.position.y / CH)), int(floorf(view.end.y / CH)) + 1):
			var key := Vector2i(cx, cy)
			var o := bg.chunk_object(cx, cy)
			if o.is_empty():
				continue
			seen[key] = true
			if _objs.has(key):
				continue
			var t: Texture2D = bg._tex[o["name"]]
			var rel: Array = OBJ_RELIEF.get(o["name"], [0.08, 0.3])
			var mi := MeshInstance3D.new()
			var k: float = o["size"] / float(maxi(t.get_width(), t.get_height()))
			if float(rel[0]) > 0.0:
				# 3.3: самолёт летит над всем (как в Sublight) — рельеф никогда не дотягивается до плоскости боя
				var h_world := minf(float(o["size"]) * float(rel[0]), OBJ_MAX_H)
				mi.mesh = ReliefMesh.build(t, snappedf(h_world / k, 1.0), 80, float(rel[1]), 0.8, false)
			else:
				var qm := PlaneMesh.new()
				qm.size = Vector2(t.get_width(), t.get_height())
				mi.mesh = qm
			mi.material_override = ReliefMesh.material(t, 0.0, 0.95)
			mi.position = Vector3(o["pos"].x, GROUND_Y + 0.5, o["pos"].y)
			mi.basis = Basis(Vector3.UP, -float(o["rot"])).scaled(Vector3(k, k, k))
			add_child(mi)
			_objs[key] = mi
	for key in _objs.keys():
		if not seen.has(key):
			(_objs[key] as Node).queue_free()
			_objs.erase(key)


# ---------- облака ----------

func _sync_clouds(m: Main, c2: Vector2, h: float) -> void:
	var cl: Clouds = m.clouds
	if cl == null:
		return
	var its := cl.items()
	while _clouds.size() < its.size():
		var mi := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		qm.size = Vector2(1, 1)
		mi.mesh = qm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_clouds.append(mi)
	var pp := m.player.global_position if is_instance_valid(m.player) else c2
	for i in _clouds.size():
		var mi2: MeshInstance3D = _clouds[i]
		if i >= its.size():
			mi2.visible = false
			continue
		var it: Array = its[i]
		var t: Texture2D = it[3]
		var mat: StandardMaterial3D = mi2.get_meta("mat") if mi2.has_meta("mat") else null
		if mat == null or mat.albedo_texture != t:
			mat = StandardMaterial3D.new()
			mat.albedo_texture = t
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi2.material_override = mat
			mi2.set_meta("mat", mat)
		mi2.visible = true
		var gp: Vector2 = it[0]
		var size: float = it[1]
		mi2.position = Vector3(gp.x, CLOUD_Y, gp.y)
		mi2.basis = Basis(Vector3.UP, -float(it[2])).scaled(Vector3(size, 1, size))
		# над самолётом облако прозрачнее: точка облака на экране ≈ проекция на плоскость боя
		var sp := Vector2(c2.x + (gp.x - c2.x) * h / (h - CLOUD_Y), c2.y + (gp.y - c2.y) * h / (h - CLOUD_Y))
		var d := sp.distance_to(pp)
		var ss := size * h / (h - CLOUD_Y)
		mat.albedo_color = Color(1, 1, 1, 0.5 * clampf((d - ss * 0.1) / (ss * 0.45), 0.2, 1.0))


# ---------- 3.2: свет взрывов ----------

var _lights: Array = []
var _light_i := 0


## Вспышка света в точке взрыва: подсвечивает модели и землю, гаснет за ~0,35 с
func light_flash(p: Vector2, size: float) -> void:
	if _lights.is_empty():
		for i in 8:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.62, 0.28)
			l.shadow_enabled = false
			l.visible = false
			add_child(l)
			_lights.append({"l": l, "t": 0.0, "e": 0.0})
	var slot: Dictionary = _lights[_light_i % _lights.size()]
	_light_i += 1
	var l2: OmniLight3D = slot["l"]
	l2.position = Vector3(p.x, 60.0, p.y)
	l2.omni_range = clampf(size * 9.0, 140.0, 900.0)
	slot["e"] = clampf(size / 12.0, 1.5, 6.0)
	slot["t"] = 0.35
	l2.light_energy = slot["e"]
	l2.visible = true


func _sync_lights(delta: float) -> void:
	for slot in _lights:
		if float(slot["t"]) <= 0.0:
			continue
		slot["t"] = float(slot["t"]) - delta
		var l: OmniLight3D = slot["l"]
		var k := clampf(float(slot["t"]) / 0.35, 0.0, 1.0)
		l.light_energy = float(slot["e"]) * k * k
		l.visible = float(slot["t"]) > 0.0


# ---------- выжженные пятна ----------

func _sync_scorch(m: Main) -> void:
	if m.fx == null or not is_instance_valid(m.fx.ground):
		return
	var marks: Array = m.fx.ground.marks
	if _scorch_mat.albedo_texture == null:
		if Fx._soft == null:
			return
		_scorch_mat.albedo_texture = Fx._soft
	while _scorch.size() < marks.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _scorch_mesh
		mi.material_override = _scorch_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_scorch.append(mi)
	for i in _scorch.size():
		var mi2: MeshInstance3D = _scorch[i]
		if i >= marks.size():
			mi2.visible = false
			continue
		var mk: Dictionary = marks[i]
		if not mk.has("g3"):
			mk["g3"] = ground_under(mk["p"])
		var r: float = mk["r"] * 1.6
		mi2.visible = true
		mi2.transparency = 1.0 - clampf(float(mk["life"]) / 6.0, 0.0, 1.0)
		mi2.position = mk["g3"] + Vector3(0, 0.8, 0)
		mi2.basis = Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(r, 1, r))
