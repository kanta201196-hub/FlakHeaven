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
## B-26: земля ниже плоскости боя на ground_depth (было 70 px) — между ними настоящий рельеф
var GROUND_Y := -500.0
const CLOUD_Y := 380.0       # облака между камерой и самолётами
const ON := true

static var I: Render3D
static var enabled := true

var cam: Camera3D
var sun: DirectionalLight3D
var terrain: Terrain3D
var _ground_mat: ShaderMaterial
var _units := {}      # instance_id → {node, kind, prev_heading, bank}
var _objs := {}       # ключ клетки → MeshInstance3D
var _clouds: Array = []
var _scorch: Array = []
var _scorch_mesh: QuadMesh
var _scorch_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _elite_mat: StandardMaterial3D
var _zoom := 1.0
var _shadow_shader: Shader
## Высотная тень: силуэт самолёта, размытый, меньше и бледнее настоящей тени. На высоте в километры
## настоящая тень размыта полутенью солнца до пятна и лежит далеко в стороне, а крупная чёткая тень
## читается как бреющий полёт. Оставляем подсказку «где самолёт над землёй», но в стиле высоты.
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : filter_linear, repeat_disable;
uniform float alpha = 0.35;
uniform float blur = 0.03;
void fragment() {
	float a = 0.0;
	for (int i = 0; i < 12; i++) {
		float t = float(i) * 2.39996;
		float r = blur * sqrt((float(i) + 0.5) / 12.0);
		a += texture(tex, UV + vec2(cos(t), sin(t)) * r).a;
	}
	ALBEDO = vec3(0.04, 0.05, 0.09);
	ALPHA = a / 12.0 * alpha;
}
"""
## B-47: наклонная камера. Слой боя (2D: пули, взрывы, эффекты) рисуется вторым вьюпортом с тем же
## World2D в текстуру, а она лежит в 3D на плоскости боя (y = 0) — совпадает с моделями в любой точке
## кадра. В основном вьюпорте слой боя скрыт маской (видимость CanvasItem, бит COMBAT_LAYER).
const COMBAT_LAYER := 2
const COMBAT_VP_MAX := 2600.0     # предел стороны текстуры слоя боя, px
var _combat_vp: SubViewport
var _combat_quad: MeshInstance3D
var _tilt_on := false


func _ready() -> void:
	I = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = Tuning.g("render3d") > 0.5
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.47, 0.4)
	# B-24: заполняющий свет от неба — холодный, тени голубоватые, а не серые
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.68, 0.82)
	e.ambient_light_energy = 0.5
	# экспозиция и яркость земли ниже, чем в 3.3, — песок и вершины гор не выгорают в белое
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = Tuning.g("light_exposure")
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.05
	e.fog_enabled = false
	env.environment = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 4000.0
	sun.shadow_bias = 0.05
	# B-24: солнце ниже (~40° над горизонтом) — тени длиннее, у объектов видна теневая сторона.
	# Свет сверху-слева (на экране): тени уходят вниз-вправо
	sun.basis = Basis.looking_at(Vector3(0.62, -0.85, 0.75).normalized(), Vector3(0, 0, -1))
	add_child(sun)

	_setup_combat_layer()

	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 10.0
	cam.far = 6000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(cam)
	cam.current = true

	GROUND_Y = -Tuning.g("ground_depth")
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/ground3d.gdshader")
	# B-25: наборы PBR (CC0, game/art/ground/pbr/) — если есть все, иначе старые текстуры 2.6
	var slots := [["sand", "sand"], ["clay", "clay"], ["gravel", "gravel"], ["river", "riverbed"], ["rock", "gravel"]]
	var pbr := true
	for n in slots:
		pbr = pbr and ResourceLoader.exists("res://art/ground/pbr/%s_albedo.jpg" % n[0]) and ResourceLoader.exists("res://art/ground/pbr/%s_nh.jpg" % n[0])
	for n in slots:
		if pbr:
			sm.set_shader_parameter("t_" + n[0], load("res://art/ground/pbr/%s_albedo.jpg" % n[0]))
			sm.set_shader_parameter("n_" + n[0], load("res://art/ground/pbr/%s_nh.jpg" % n[0]))
		else:
			var p := "res://art/ground/g_%s.png" % n[1]
			if ResourceLoader.exists(p):
				sm.set_shader_parameter("t_" + n[0], load(p))
	sm.set_shader_parameter("use_nh", pbr)
	if pbr:
		sm.set_shader_parameter("tex_world", Tuning.g("ground_tile"))
	sm.set_shader_parameter("seed", float(randi() % 1000))
	sm.set_shader_parameter("albedo_k", Tuning.g("ground_albedo"))
	sm.set_shader_parameter("relief", true)
	_ground_mat = sm
	terrain = Terrain3D.new()
	add_child(terrain)
	terrain.setup(-GROUND_Y, sm, null)
	terrain.props = BiomeProps.new(terrain)

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
	apply_gfx(Settings.gfx)


## T4-04: «Качество графики». Низкое — тени солнца ближе и грубее, мелкие модели биома без теней и вдвое реже;
## Среднее — тени ближе и грубее; Высокое — как было; Максимальное — + сглаживание MSAA 2×.
## Деревья полной детализации (11–14 тыс. треуг.) — только на «Максимальном» (BiomeProps).
func apply_gfx(q: int) -> void:
	# тени не выключаем: в GL Compatibility без теней солнца кадр темнее и рыжее (замер стенда: яркость 104 против 144)
	sun.directional_shadow_max_distance = [1500.0, 2500.0, 4000.0, 4000.0][q]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 4096][q], true)
	get_viewport().msaa_3d = Viewport.MSAA_2X if q >= 3 else Viewport.MSAA_DISABLED
	if terrain != null:
		terrain.clear()   # куски рельефа пересоберутся с новыми моделями биома


# ---------- слой боя для наклонной камеры (B-47) ----------

func _setup_combat_layer() -> void:
	_combat_vp = SubViewport.new()
	_combat_vp.transparent_bg = true
	_combat_vp.disable_3d = true
	_combat_vp.canvas_cull_mask = 0xFFFFFFFF   # предки слоя боя (Main) в слое 1 — иначе отсекаются вместе с детьми
	_combat_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_combat_vp.size = Vector2i(16, 16)
	add_child(_combat_vp)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_combat_quad = MeshInstance3D.new()
	_combat_quad.mesh = pm
	_combat_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true      # как раньше 2D-слой: пули и вспышки поверх самолётов и облаков
	m.render_priority = 100
	m.albedo_texture = _combat_vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_combat_quad.material_override = m
	_combat_quad.visible = false
	add_child(_combat_quad)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if _tilt_on and n is CanvasItem and Main.I != null and is_instance_valid(Main.I.world) and Main.I.world.is_ancestor_of(n):
		(n as CanvasItem).visibility_layer = COMBAT_LAYER


func _set_layer(n: Node, layer: int) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visibility_layer = layer
	for c in n.get_children():
		_set_layer(c, layer)


## Включение и выключение наклона: слой боя уходит из основного вьюпорта в текстуру на плоскости
func _set_tilt_mode(on: bool, m: Main) -> void:
	if on == _tilt_on and (not on or m.world.visibility_layer == COMBAT_LAYER):
		return
	_tilt_on = on
	_set_layer(m.world, COMBAT_LAYER if on else 1)
	get_viewport().canvas_cull_mask = 0xFFFFFFFF & ~COMBAT_LAYER if on else 0xFFFFFFFF
	_combat_vp.world_2d = get_viewport().world_2d
	_combat_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_combat_quad.visible = on


## Каждый кадр: какую часть плоскости боя видит камера → такой прямоугольник рисуем в текстуру
func _sync_combat_layer() -> void:
	var vs := get_viewport().get_visible_rect().size
	var r := Rect2()
	var first := true
	for corner in [Vector2.ZERO, Vector2(vs.x, 0), Vector2(0, vs.y), vs, Vector2(vs.x * 0.5, 0)]:
		var o := cam.project_ray_origin(corner)
		var d := cam.project_ray_normal(corner)
		if d.y > -0.05:
			d.y = -0.05
		var t := -o.y / d.y
		var p := Vector2(o.x + d.x * t, o.z + d.z * t)
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	var base := vs / _zoom
	r = r.intersection(Rect2(r.get_center() - base * 1.5, base * 3.0))   # не тянуть текстуру до горизонта
	var px := r.size * _zoom
	var k := minf(1.0, COMBAT_VP_MAX / maxf(px.x, px.y))
	var size := Vector2i(maxi(16, int(px.x * k)), maxi(16, int(px.y * k)))
	if _combat_vp.size != size:
		_combat_vp.size = size
	var sc := float(size.x) / r.size.x
	_combat_vp.canvas_transform = Transform2D(0.0, Vector2(sc, sc), 0.0, -r.position * sc)
	_combat_quad.position = Vector3(r.get_center().x, 0.0, r.get_center().y)
	_combat_quad.scale = Vector3(r.size.x, 1.0, r.size.y)


## Точка плоскости боя под курсором мыши (с наклоном камеры — через луч из камеры)
func mouse_world(fallback: Vector2) -> Vector2:
	if not _tilt_on:
		return fallback
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if d.y > -0.01:
		return fallback
	var t := -o.y / d.y
	return Vector2(o.x + d.x * t, o.z + d.z * t)


## Экранная точка для точки мира (указатели интерфейса); без наклона — как 2D-камера
func world_to_screen(p: Vector2, fallback: Vector2) -> Vector2:
	if not _tilt_on:
		return fallback
	return cam.unproject_position(Vector3(p.x, 0.0, p.y))


# ---------- камера ----------

func _cam_height(zoom: float) -> float:
	var vh := get_viewport().get_visible_rect().size.y
	return (vh / maxf(zoom, 0.01)) / (2.0 * tan(deg_to_rad(FOV) / 2.0))


## Точка на земле, которая на экране совпадает с точкой p плоскости боя (для наземных целей и пятен).
## B-26: луч камеры через p пересекаем с рельефом — три уточнения высоты хватает (склоны пологие
## относительно высоты камеры)
func ground_under(p: Vector2) -> Vector3:
	var c := cam.global_position
	var h := c.y
	var y := GROUND_Y
	var g := Vector3.ZERO
	for i in 3:
		var k := (h - y) / h
		g = Vector3(c.x + (p.x - c.x) * k, 0.0, c.z + (p.y - c.z) * k)
		y = terrain.surface(g.x, g.z).y if terrain != null else GROUND_Y
	g.y = y
	return g


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
	var tilt := deg_to_rad(Tuning.g("cam_tilt"))
	if tilt > 0.001:
		# проба наклона: камера отходит назад (вниз по экрану) на той же дальности до центра плоскости боя.
		# Внимание: 2D-слой (пули, эффекты) рисуется без наклона — совпадает с 3D только в центре кадра.
		cam.global_position = Vector3(c2.x, h * cos(tilt), c2.y + h * sin(tilt))
		cam.basis = Basis.looking_at(Vector3(0, -cos(tilt), -sin(tilt)), Vector3(0, 0, -1))
	else:
		cam.global_position = Vector3(c2.x, h, c2.y)
		cam.basis = Basis.looking_at(Vector3(0, -1, 0), Vector3(0, 0, -1))
	# рельеф — куски под видимой областью дна долин (+ запас на тени и сглаживание камеры)
	if terrain._bg != m.background:
		terrain._bg = m.background
		terrain.clear()
	var half_g := vs / zoom * 0.5 * ((h - GROUND_Y) / h) + Vector2(700, 700)
	_set_tilt_mode(tilt > 0.001, m)
	if _tilt_on:
		_sync_combat_layer()
	var view_g := Rect2(c2 - half_g, half_g * 2.0)
	if tilt > 0.001:
		# с наклоном видно дальше вперёд (вверх по экрану)
		view_g = view_g.grow_individual(half_g.x * tilt, half_g.y * tilt * 3.0, half_g.x * tilt, 0.0)
	terrain.sync(view_g, 64 if terrain._chunks.is_empty() else 2)
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
		if kind != "enemy" or thick > 0.06:   # у наземных целей (thick 0.05) тень настоящая
			u["sh"] = _make_shadow(tex, root)
		_units[id] = u
	u["seen"] = true
	return u


func _place(u: Dictionary, p: Vector2, heading: float, bank: float, roll: float, y := 0.0, scale_k := 1.0) -> void:
	var root: Node3D = u["node"]
	root.position = Vector3(p.x, y, p.y)
	var b := Basis(Vector3.UP, -heading) * Basis(Vector3.RIGHT, bank + roll)
	var k: float = u["k"] * scale_k
	root.basis = b.scaled(Vector3(k, k, k))
	if u.has("sh"):
		_place_shadow(u, p, heading, k)


func _make_shadow(tex: Texture2D, root: Node3D) -> MeshInstance3D:
	if _shadow_shader == null:
		_shadow_shader = Shader.new()
		_shadow_shader.code = SHADOW_SHADER
	var pm := PlaneMesh.new()
	pm.size = Vector2(tex.get_width(), tex.get_height())
	var mat := ShaderMaterial.new()
	mat.shader = _shadow_shader
	mat.set_shader_parameter("tex", tex)
	var sh := MeshInstance3D.new()
	sh.mesh = pm
	sh.material_override = mat
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.tree_exiting.connect(sh.queue_free)
	add_child(sh)
	return sh


## Тень самолёта: точка на рельефе по лучу солнца, сдвиг от самолёта укорочен (shadow_off),
## силуэт уменьшен (shadow_size) и прижат к склону по нормали рельефа.
func _place_shadow(u: Dictionary, p: Vector2, heading: float, k: float) -> void:
	var sh: MeshInstance3D = u["sh"]
	var hi := Tuning.g("plane_shadow") > 0.5 and terrain != null
	var cs := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if hi else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in (u["node"] as Node3D).find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = cs
	sh.visible = hi
	if not hi:
		return
	var d := -sun.global_transform.basis.z   # куда светит солнце
	var y := GROUND_Y
	var g := Vector2.ZERO
	var off := Tuning.g("shadow_off")
	for i in 3:
		var t := y / d.y
		g = p + Vector2(d.x, d.z) * t * off
		y = terrain.surface(g.x, g.y).y
	var e := 8.0
	var n := Vector3(terrain.surface(g.x - e, g.y).y - terrain.surface(g.x + e, g.y).y, 2.0 * e,
		terrain.surface(g.x, g.y - e).y - terrain.surface(g.x, g.y + e).y).normalized()
	var s := k * Tuning.g("shadow_size")
	var yaw := Basis(Vector3.UP, -heading)
	var tilt := Basis(Quaternion(Vector3.UP, n))
	sh.global_transform = Transform3D((tilt * yaw).scaled(Vector3(s, 1.0, s)), Vector3(g.x, y + 3.0, g.y))
	var mat := sh.material_override as ShaderMaterial
	mat.set_shader_parameter("alpha", Tuning.g("shadow_alpha"))
	mat.set_shader_parameter("blur", 0.03 + 0.03 * (1.0 - Tuning.g("shadow_size")))


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
			# 3.5: у целей с точкой на рельефе (anchor) — ставим ровно туда, иначе проекция с камеры
			var gp := terrain.surface(e.anchor.x, e.anchor.y) if (e.anchor != Vector2.INF and terrain != null) else ground_under(e.global_position)
			_place(ue, Vector2(gp.x, gp.z), ang, 0.0, 0.0, gp.y + 1.0, (cam.global_position.y - gp.y) / cam.global_position.y)
		else:
			_place(ue, e.global_position, ang, _turn_bank(ue, ang, delta), e.roll_angle()) # 3.5: бочка при уклонении
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

## Верх объектов не ближе 30 px к плоскости боя (запас на крен и толщину моделей)
const OBJ_TOP := -30.0
## B-26: столовая гора-картинка не нужна — горы теперь настоящие;
## B-41: скалы-картинки заменены группами моделей (biome_props.gd)
const OBJ_SKIP_3D := ["o_mesa", "o_rocks_big", "o_rocks_small"]

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
			if o.is_empty() or o["name"] in OBJ_SKIP_3D:
				continue
			seen[key] = true
			if _objs.has(key):
				continue
			var t: Texture2D = bg._tex[o["name"]]
			var rel: Array = OBJ_RELIEF.get(o["name"], [0.08, 0.3])
			var mi := MeshInstance3D.new()
			var k: float = o["size"] / float(maxi(t.get_width(), t.get_height()))
			var gy := terrain.surface(o["pos"].x, o["pos"].y).y
			if float(rel[0]) > 0.0:
				# 3.3: самолёт летит над всем (как в Sublight) — рельеф никогда не дотягивается до плоскости боя
				var h_world := clampf(float(o["size"]) * float(rel[0]), 2.0, OBJ_TOP - gy)
				mi.mesh = ReliefMesh.build(t, snappedf(h_world / k, 1.0), 80, float(rel[1]), 0.8, false)
			else:
				var qm := PlaneMesh.new()
				qm.size = Vector2(t.get_width(), t.get_height())
				mi.mesh = qm
			mi.material_override = ReliefMesh.material(t, 0.0, 0.95, Color.WHITE * Tuning.g("obj_albedo"))
			mi.position = Vector3(o["pos"].x, gy + 0.5, o["pos"].y)
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
