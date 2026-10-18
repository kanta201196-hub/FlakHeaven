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
var _objs := {}       # ключ клетки → MeshInstance3D (у обломков o_wreck — сцена модели)
var _clouds: Array = []          # «Низкое» качество: прежние плоские облака
var _puffs: CloudPuffs           # M-31: объёмные облака из клубов (остальные качества)
var _cloud_shift_v := Vector2.ZERO
var _scorch_mm: MultiMeshInstance3D
var _scorch_mesh: QuadMesh
var _scorch_mat: StandardMaterial3D
var _crater_mm: MultiMeshInstance3D   # тест 3.5-s4 (п. 14): воронки от бомб (FxGround.craters), один MultiMesh
var _crater_mat: StandardMaterial3D
var _crater_mesh: PlaneMesh
var _bombs3 := {}                  # тест 3.5-s4 (п. 10): падающие бомбы — номер → MeshInstance3D
var _bid := 0
var _flash_mat: StandardMaterial3D
var _elite_mat: StandardMaterial3D
var _zoom := 1.0
var _c2 := Vector2.ZERO        # центр кадра на плоскости боя (для указателей за краем экрана)
var _shadow_shader: Shader
var _trails: Contrails       # 3.4-t1 (п. 10, 34): инверсионные следы самолётов и ракет
var _tid := 0                # номера ракет для их следов
var _eshot_mm: MultiMeshInstance3D   # тест 3.5-s5 (п. 11): ракеты врагов — модели
var _eglow_mm: MultiMeshInstance3D   # и светящиеся точки: трассеры пуль, ореол и факел ракет
var _crashes: Array = []     # 3.4-t1 (п. 32): сбитые ведомые падают
var _wrecks: Array = []      # и остаются обломками на земле
var _wreck_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D
var title: TitleFlight       # тест 3.5-s5 (п. 1): звено 3D-моделей на заставке меню
## Высотная тень: силуэт самолёта, размытый, меньше и бледнее настоящей тени. На высоте в километры
## настоящая тень размыта полутенью солнца до пятна и лежит далеко в стороне, а крупная чёткая тень
## читается как бреющий полёт. Оставляем подсказку «где самолёт над землёй», но в стиле высоты.
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
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
	ALBEDO = vec3(1.0);   // тест 3.5-s5 (п. 8): рисуется в карту теней (_psh_vp), густота — в канале R
	ALPHA = a / 12.0 * alpha;
}
"""
## B-47: наклонная камера. Слой боя (2D: пули, взрывы, эффекты) рисуется вторым вьюпортом с тем же
## World2D в текстуру, а она лежит в 3D на плоскости боя (y = 0) — совпадает с моделями в любой точке
## кадра. В основном вьюпорте слой боя скрыт маской (видимость CanvasItem, бит COMBAT_LAYER).
const COMBAT_LAYER := 2
## Тест 3.5-s5 (п. 8): тени самолётов съедались рельефом — пластина тени над землёй, гребни, уступы и кусты
## прорастали сквозь неё. Теперь силуэты теней (тот же шейдер и те же пластины) видит только камера сверху
## в отдельном вьюпорте; её картинка — карта густоты тени, шейдер земли затемняет по ней свою точку, как
## тенями облаков. Тень лежит точно по рельефу; деревья и дома закрывают её как предметы над землёй.
const PSH_LAYER := 1 << 19        # слой 20: только силуэты теней
var _psh_vp: SubViewport
var _psh_cam: Camera3D
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
	# 3.4-t1 (п. 18): тени уступов на склонах были почти чёрными полосами — свет неба их подсвечивает
	sun.shadow_opacity = 0.8
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
	cam.cull_mask &= ~PSH_LAYER

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
	sm.set_shader_parameter("river_w", Terrain3D.D_RIVER)
	sm.set_shader_parameter("river_guard", Terrain3D.RIVER_GUARD)   # M-35: охранная зона реки
	sm.set_shader_parameter("road_v", Terrain3D.D_ROAD)
	sm.set_shader_parameter("road_w", Terrain3D.ROAD_W)        # M-36: дорога шире под конвой
	sm.set_shader_parameter("road_w_in", Terrain3D.ROAD_W_IN)
	_ground_mat = sm
	terrain = Terrain3D.new()
	add_child(terrain)
	terrain.setup(-GROUND_Y, sm, null)
	terrain.props = BiomeProps.new(terrain)
	_setup_plane_shadows()

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
	_wreck_mat = StandardMaterial3D.new()
	_wreck_mat.albedo_color = Color(0.07, 0.06, 0.05, 0.82)
	_wreck_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wreck_mat.roughness = 1.0
	_trails = Contrails.new()
	add_child(_trails)
	title = TitleFlight.new(self)
	add_child(title)
	apply_gfx(Settings.gfx)


## T4-04: «Качество графики».
## 3.5 (правка 7): в 3.4 пресеты меняли только тени — на слабом ноутбуке разницы не было. Теперь:
##   Низкое — 3D-картинка в 60% разрешения, слой боя до 1400 пикс., рельеф реже (сетка 40), модели биома
##            без теней и мелочи вдвое реже, тени грубее (атлас 1024);
##   Среднее — 80% разрешения, слой боя до 2000, сетка рельефа 56, мелкие модели без теней, атлас 2048;
##   Высокое — как было; Максимальное — + сглаживание MSAA 2×.
## Деревья полной детализации (11–14 тыс. треуг.) — только на «Максимальном» (BiomeProps).
## Правка 16: дальность теней теперь по видимой земле (углы кадра), а не по пресету — тень не обрывается
## полосой посреди экрана при наклоне камеры; грубость слабых пресетов — размером атласа.
const GFX_SCALE := [0.6, 0.8, 1.0, 1.0]
const GFX_COMBAT_MAX := [1400.0, 2000.0, 2600.0, 2600.0]
var _gfx := 2


func apply_gfx(q: int) -> void:
	_gfx = clampi(q, 0, 3)
	# тени не выключаем: в GL Compatibility без теней солнца кадр темнее и рыжее (замер стенда: яркость 104 против 144)
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 4096][_gfx], true)
	get_viewport().msaa_3d = Viewport.MSAA_2X if _gfx >= 3 else Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = GFX_SCALE[_gfx]
	if _ground_mat != null:   # M-36: скала с трёх проекций — только «Высокое» и «Максимальное»
		_ground_mat.set_shader_parameter("rock_tri", _gfx >= 2)
	if terrain != null:
		terrain.clear()   # куски рельефа пересоберутся с новыми моделями биома и сеткой


## Правка 16: тени — на всю видимую землю. Лучи из углов кадра до дна долин → самая дальняя точка.
func _fit_shadow() -> void:
	var vs := get_viewport().get_visible_rect().size
	var far := 0.0
	for corner in [Vector2.ZERO, Vector2(vs.x, 0), Vector2(0, vs.y), vs]:
		var o := cam.project_ray_origin(corner)
		var d := cam.project_ray_normal(corner)
		if d.y > -0.05:
			d.y = -0.05
		var t := (GROUND_Y - o.y) / d.y
		far = maxf(far, t)
	sun.directional_shadow_max_distance = clampf(far * 1.1 + 300.0, 1500.0, 12000.0)


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
	# С-2 (аудит 3.5-s6): 2D рисует в прозрачный вьюпорт цвет, уже умноженный на альфу (конус заправки
	# 0.4·0.16 → 16/255 при альфе 41). Обычное смешение умножало второй раз — полупрозрачное темнело:
	# зелёный конус за заправщиком лежал вокруг игрока тёмной трапецией, края пуль и вспышек — с серой каймой
	m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
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
	var k := minf(1.0, minf(COMBAT_VP_MAX, GFX_COMBAT_MAX[_gfx]) / maxf(px.x, px.y))
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
	var v := Vector3(p.x, 0.0, p.y)
	if not cam.is_position_behind(v):
		return cam.unproject_position(v)
	# Правка 3.5-s4: точка позади камеры (далеко внизу кадра) проецируется зеркально — стрелка эвакуации
	# показывала вперёд, хотя цель сзади. Берём направление от центра кадра и уводим точку далеко за край.
	var dir := (p - _c2).normalized()
	var a := cam.unproject_position(Vector3(_c2.x, 0.0, _c2.y))
	var b := cam.unproject_position(Vector3(_c2.x + dir.x * 100.0, 0.0, _c2.y + dir.y * 100.0))
	return a + (b - a).normalized() * 100000.0


## Р-13: земля, которую камера видит прямо сейчас — углы кадра на дне долин (дальние лучи наклона —
## не дальше 6000), с запасом на тряску и сглаживание камеры
func _screen_ground(vs: Vector2) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c in [Vector2.ZERO, Vector2(vs.x, 0), Vector2(0, vs.y), vs]:
		var o := cam.project_ray_origin(c)
		var d := cam.project_ray_normal(c)
		var t := (GROUND_Y - o.y) / d.y if d.y < -0.01 else 6000.0
		var q := o + d * minf(t, 6000.0)
		lo = lo.min(Vector2(q.x, q.z))
		hi = hi.max(Vector2(q.x, q.z))
	return Rect2(lo, hi - lo).grow(120.0)


func tilt_on() -> bool:
	return _tilt_on


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
		y = terrain.surface_fast(g.x, g.z).y if terrain != null else GROUND_Y
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
	_c2 = c2
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
		m.background.place_filter = terrain.fix_object   # тест 3.5-s4 (п. 20): объекты клеток не в реке
		terrain.clear()
	var half_g := vs / zoom * 0.5 * ((h - GROUND_Y) / h) + Vector2(700, 700)
	_set_tilt_mode(tilt > 0.001, m)
	if _tilt_on:
		_sync_combat_layer()
	var view_g := Rect2(c2 - half_g, half_g * 2.0)
	if tilt > 0.001:
		# с наклоном видно дальше вперёд (вверх по экрану)
		view_g = view_g.grow_individual(half_g.x * tilt, half_g.y * tilt * 3.0, half_g.x * tilt, 0.0)
	var pt := Time.get_ticks_usec() if Perf.on else 0
	terrain.sync(view_g, 64 if terrain._chunks.is_empty() else 1, _screen_ground(vs))
	_fit_shadow()
	if Perf.on: pt = Perf.sub("r3d.terrain", pt)
	var sd := 0.0 if get_tree().paused else delta   # время эффектов стоит на паузе
	_sync_units(m, delta, sd)
	if Perf.on: pt = Perf.sub("r3d.units", pt)
	_sync_missiles(m)
	_sync_enemy_shots(m)
	if Perf.on: pt = Perf.sub("r3d.missiles", pt)
	_sync_crashes(m, sd)
	title.sync(m.state in ["menu", "settings"] and m.menu != null and m.menu.back_state == "menu", delta)
	_trails.tick(delta if title.active() else sd)   # в меню мир на паузе, а следы звена тают в реальном времени
	if Perf.on: pt = Perf.sub("r3d.crash_trails", pt)
	_sync_objects(c2, h)
	if Perf.on: pt = Perf.sub("r3d.objects", pt)
	_sync_clouds(m, c2, h)
	_sync_scorch(m)
	_sync_craters(m)
	_sync_bombs(m)
	_sync_lights(delta)
	if Perf.on: pt = Perf.sub("r3d.clouds_scorch_lights", pt)
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


## 3.5: бой на 3D-моделях (решение 14.10, подтверждено владельцем 16.10). Облегчённая модель
## models/battle/fh_battle_<картинка>.glb (tools/blender/battle_lod.py из модели ангара); длина модели 1 =
## ширина картинки, нос +X — те же оси, что у рельефа из спрайта, поэтому подвесы, сопла и следы на месте.
## «Низкое» качество графики — прежний рельеф из спрайта (слабые ПК).
func _battle_model(tex: Texture2D) -> PackedScene:
	if Settings.gfx == 0:
		return null
	# оптимизация: кэш по самой картинке — без сборки пути каждый кадр у каждого самолёта
	var hit = _bm_cache.get(tex)
	if hit != null or _bm_cache.has(tex):
		return hit
	var path := "res://models/battle/fh_battle_%s.glb" % tex.resource_path.get_file().get_basename()
	_bm_cache[tex] = load(path) if ResourceLoader.exists(path) else null
	return _bm_cache[tex]


var _bm_cache := {}
## M-37 (Kanta 18.10): высота модели к её длине ближе к настоящей — при наклоне камеры 28–45° высокая модель
## «встаёт» над землёй и кажется крупнее. Бункер Meshy вдвое выше настоящего укрытия с обваловкой (0,8 длины
## против ~0,3), у РЛС антенна на мачте ~1 длины против ~0,8. Сжатие только по вертикали; у РЛС ось вращения
## антенны вертикальная — сжатие её не перекашивает. ЗСУ и ЗРК в норме (подъём контейнеров ЗРК так не исказится).
const MODEL_H := {"e_bunker": 0.6, "e_radar": 0.85}


## Для лога: (самолётов-моделей в бою, их треугольников всего)
func model_units() -> Vector2:
	var n := 0
	var t := 0
	for id in _units:
		var u: Dictionary = _units[id]
		if u.get("bm") != null:
			n += 1
			if not u.has("tris"):
				u["tris"] = (u["mi"] as MeshInstance3D).mesh.get_faces().size() / 3
			t += int(u["tris"])
	return Vector2(n, t)


func _ensure(id: int, kind: String, tex: Texture2D, length_px: float, thick: float, grid := 56) -> Dictionary:
	var u: Dictionary = _units.get(id, {})
	var bm: PackedScene = _battle_model(tex)   # 3.5 этап 2: враги в воздухе и наземные ПВО (ЗСУ, ЗРК, РЛС)
	if u.is_empty() or u["tex"] != tex or u.get("bm") != bm:
		var nt := Time.get_ticks_usec() if Perf.on else 0
		if not u.is_empty():
			(u["node"] as Node).queue_free()
		var pooled := _pool_take(tex, kind, thick, bm)
		if not pooled.is_empty():
			pooled["k"] = length_px / float(tex.get_width())
			_units[id] = pooled
			if Perf.on:
				Perf.sub("r3d.new_model", nt)
			return pooled
		var root := Node3D.new()
		var mi: MeshInstance3D = null
		var d := {"k": length_px / float(tex.get_width())}
		if bm != null:
			var inst: Node3D = bm.instantiate()
			inst.scale = Vector3.ONE * float(tex.get_width())
			inst.scale.y *= float(MODEL_H.get(tex.resource_path.get_file().get_basename(), 1.0))
			root.add_child(inst)
			for c in inst.find_children("*", "MeshInstance3D", true, false):
				mi = c
				break
		if mi == null:
			bm = null
			mi = MeshInstance3D.new()
			d = _unit_mesh(tex, length_px, thick, grid)
			mi.mesh = d["mesh"]
			mi.material_override = d["mat"]
			root.add_child(mi)
		add_child(root)
		u = {"node": root, "mi": mi, "kind": kind, "tex": tex, "k": d["k"], "ph": 0.0, "bank": 0.0, "seen": true, "weapons": {}, "bm": bm}
		if bm != null and kind == "player":   # Т-3: модули прокачки на модели (до механизации — мерится чистый корпус)
			u["modp"] = ModuleParts.attach(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
		if bm != null and kind in ["player", "wing"]:   # Т-1: предкрылки и закрылки своих самолётов
			u["mech"] = WingMech.attach(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
			# Т-2: отличие «Грача 2» сверху (ПГО, контейнеры на законцовках)
			u["detail"] = WingMech.attach_detail(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
			# V-07: свои знаки на крыльях, киле и (у асов) на борту
			u["ins"] = Insignia.attach(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename(), kind)
			if kind == "player":   # Т-5: створки бомбоотсека «Кита»
				u["bay"] = WingMech.attach_bay(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
				u["tail"] = WingMech.attach_tail(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
				_apply_livery(root.get_child(0) as Node3D, tex)
		if kind == "enemy" and thick > 0.06:
			u["shb"] = tex   # оптимизация: тени врагов одного вида — один MultiMesh (_flush_shadows)
		elif kind != "enemy":   # у наземных целей (thick 0.05) тень настоящая
			u["sh"] = _make_shadow(tex, root)
		if kind != "enemy":
			PlaneFx.attach(u, tex)
		_units[id] = u
		if Perf.on:
			Perf.peak("r3d.new_model_max", Perf.sub("r3d.new_model", nt) - nt)
	u["seen"] = true
	return u


## Тест 3.5-s4, п. 35: окраска своего самолёта из ангара (ведомые — в своей, с полосами звена)
func _apply_livery(model: Node3D, tex: Texture2D) -> void:
	var key := tex.resource_path.get_file().get_basename()   # «fighter_1»
	var cls := key.get_slice("_", 0)
	Livery.apply(model, cls, int(key.get_slice("_", 1)), Livery.current(cls))


func _place(u: Dictionary, p: Vector2, heading: float, bank: float, roll: float, y := 0.0, scale_k := 1.0, pitch := 0.0) -> void:
	var root: Node3D = u["node"]
	var q := p
	if u.has("alt"):
		# самолёт выше или ниже плоскости боя — на луче камеры через точку p: на экране он там же,
		# где его пули и хитбокс, а высоту видно по размеру и по рельефу под ним
		q = _on_ray(p, y)
	root.position = Vector3(q.x, y, q.y)
	var b := Basis(Vector3.UP, -heading) * Basis(Vector3.BACK, pitch) * Basis(Vector3.RIGHT, bank + roll)
	var k: float = u["k"] * scale_k
	root.basis = b.scaled(Vector3(k, k, k))
	if u.has("sh") or u.has("shb"):
		_place_shadow(u, p, heading, k)


const CUT_OVERLAY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 col : source_color;
void fragment() {
	ALBEDO = col.rgb;
	ALPHA = texture(tex, UV).a < 0.45 ? 0.0 : col.a;
}
"""
var _cut_shader: Shader
var _cut_mats := {}


## Подсветка попадания / элиты для модели из картинки: только там, где картинка непрозрачна
func _cut_overlay(tex: Texture2D, kind: String) -> ShaderMaterial:
	var key := "%s|%s" % [tex.get_rid(), kind]
	if _cut_mats.has(key):
		return _cut_mats[key]
	if _cut_shader == null:
		_cut_shader = Shader.new()
		_cut_shader.code = CUT_OVERLAY_SHADER
	var m := ShaderMaterial.new()
	m.shader = _cut_shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("col", Color(1, 1, 1, 0.75) if kind == "flash" else Color(1.0, 0.75, 0.2, 0.28))
	_cut_mats[key] = m
	return m


## Перспектива и так меняет размер самолёта с высотой — гасим половину, чтобы он не «прыгал»
func _alt_scale(y: float) -> float:
	var h := cam.global_position.y
	return sqrt(maxf(h - y, 1.0) / maxf(h, 1.0))


## Точка на высоте y на луче камеры через точку p плоскости боя (x, z)
func _on_ray(p: Vector2, y: float) -> Vector2:
	var c := cam.global_position
	var k := (c.y - y) / maxf(c.y, 1.0)
	return Vector2(c.x + (p.x - c.x) * k, c.z + (p.y - c.z) * k)


## Полёт по рельефу: самолёт плавно поднимается над хребтами и опускается в долины.
## Высота цели — рельеф под самолётом и впереди по курсу (look — на сколько пикс. вперёд смотреть)
## плюс запас relief_clear, в пределах relief_up / relief_down от плоскости боя. Возвращает [высота, тангаж].
func _relief_alt(u: Dictionary, p: Vector2, fwd: Vector2, look: float, delta: float) -> Array:
	var alt: float = u.get("alt", 0.0)
	if terrain == null or Tuning.g("relief_follow") < 0.5:
		u["alt"] = move_toward(alt, 0.0, delta * 60.0)
		return [float(u["alt"]), 0.0]
	# высоту рельефа считаем не каждый кадр (дорого для сотни врагов): игрок — каждый кадр,
	# остальные — раз в ~0,25 с, вразнобой
	var target: float = u.get("alt_to", 0.0)
	var next: float = float(u.get("alt_next", 0.0)) - delta
	if next <= 0.0 or u["kind"] == "player":
		next = randf_range(0.2, 0.3)
		var top := terrain.surface_fast(p.x, p.y).y
		if look > 0.0:
			for f: float in [0.5, 1.0]:
				var a: Vector2 = p + fwd * look * f
				top = maxf(top, terrain.surface_fast(a.x, a.y).y)
		target = clampf(top + Tuning.g("relief_clear"), -Tuning.g("relief_down"), Tuning.g("relief_up"))
		u["alt_to"] = target
	u["alt_next"] = next
	var nw := lerpf(alt, target, 1.0 - exp(-delta * Tuning.g("relief_rate")))
	u["alt"] = nw
	# нос вверх при наборе, вниз при снижении (сглажено, не больше ~15°)
	var vy := (nw - alt) / maxf(delta, 0.001)
	var pt := clampf(atan2(vy, 400.0), -0.26, 0.26)
	u["pitch"] = lerpf(float(u.get("pitch", 0.0)), pt, 1.0 - exp(-delta * 5.0))
	return [nw, float(u["pitch"])]


func _setup_plane_shadows() -> void:
	_psh_vp = SubViewport.new()
	_psh_vp.name = "PlaneShadows"
	var n := 1024 if Settings.gfx >= 2 else 512
	_psh_vp.size = Vector2i(n, n)
	_psh_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_psh_vp.positional_shadow_atlas_size = 0
	add_child(_psh_vp)   # мир 3D общий с основным вьюпортом
	_psh_cam = Camera3D.new()
	_psh_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_psh_cam.cull_mask = PSH_LAYER   # солнце (слой 1) камера не видит — без прохода теней от солнца
	_psh_cam.near = 10.0
	_psh_cam.far = 20000.0
	_psh_cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)   # вниз; верх кадра — к -Z
	var ce := Environment.new()
	ce.background_mode = Environment.BG_COLOR
	ce.background_color = Color.BLACK
	ce.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	ce.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_psh_cam.environment = ce
	_psh_vp.add_child(_psh_cam)
	_psh_cam.current = true
	_ground_mat.set_shader_parameter("plane_sh", _psh_vp.get_texture())


## Камера карты теней — над видимой землёй: углы кадра на плоскости земли, сторона с шагом 64 px,
## центр по сетке текселей (без мерцания краёв при движении)
func _sync_plane_shadows() -> void:
	if _psh_cam == null:
		return
	var on := Tuning.g("plane_shadow") > 0.5 and terrain != null
	_psh_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		_ground_mat.set_shader_parameter("plane_sh_rect", Vector4(0, 0, 1, 0))
		return
	var vs := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c in [Vector2.ZERO, Vector2(vs.x, 0), Vector2(0, vs.y), vs]:
		var o := cam.project_ray_origin(c)
		var d := cam.project_ray_normal(c)
		var t := (GROUND_Y - o.y) / d.y if d.y < -0.01 else 6000.0
		var q := o + d * minf(t, 6000.0)
		lo = lo.min(Vector2(q.x, q.z))
		hi = hi.max(Vector2(q.x, q.z))
	var size := ceilf(maxf(hi.x - lo.x, hi.y - lo.y) * 1.1 / 64.0) * 64.0
	var texel := size / float(_psh_vp.size.x)
	var ctr := ((lo + hi) * 0.5 / texel).round() * texel
	_psh_cam.size = size
	_psh_cam.position = Vector3(ctr.x, 8000.0, ctr.y)
	_ground_mat.set_shader_parameter("plane_sh_rect", Vector4(ctr.x - size * 0.5, ctr.y - size * 0.5, size, 1.0))


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
	sh.layers = PSH_LAYER
	root.tree_exiting.connect(sh.queue_free)
	add_child(sh)
	return sh


## Тень самолёта: точка на рельефе по лучу солнца, сдвиг от самолёта укорочен (shadow_off),
## силуэт уменьшен (shadow_size) и прижат к склону по нормали рельефа.
func _place_shadow(u: Dictionary, p: Vector2, heading: float, k: float) -> void:
	var sh: MeshInstance3D = u.get("sh")
	var hi := Tuning.g("plane_shadow") > 0.5 and terrain != null
	var cs := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if hi else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# поиск по дереву модели — только при смене режима (раньше каждый кадр у каждого самолёта)
	var n_kids := (u["node"] as Node3D).get_child_count()
	if u.get("cs") != cs or u.get("cs_n") != n_kids:
		u["cs"] = cs
		u["cs_n"] = n_kids
		for c in (u["node"] as Node3D).find_children("*", "GeometryInstance3D", true, false):
			(c as GeometryInstance3D).cast_shadow = cs
	if sh != null:
		sh.visible = hi
	if not hi:
		return
	# оптимизация (финальный проход 3.5): точку тени на рельефе и наклон склона (8 замеров высоты)
	# у чужих самолётов считаем раз в 4 кадра вразнобой; между замерами тень едет за самолётом
	# с тем же сдвигом — на глаз не отличить, рельеф пологий
	var fr := Engine.get_process_frames()
	if u["kind"] == "player" or not u.has("sh_n") or (fr + int(u.get("sh_f", 0))) % 4 == 0:
		if not u.has("sh_f"):
			u["sh_f"] = randi() % 4
		var d := -sun.global_transform.basis.z   # куда светит солнце
		var y := GROUND_Y
		var g := Vector2.ZERO
		var off := Tuning.g("shadow_off")
		for i in 3:
			var t := y / d.y
			g = p + Vector2(d.x, d.z) * t * off
			y = terrain.surface_fast(g.x, g.y).y
		var e := 8.0
		u["sh_n"] = Vector3(terrain.surface_fast(g.x - e, g.y).y - terrain.surface_fast(g.x + e, g.y).y, 2.0 * e,
			terrain.surface_fast(g.x, g.y - e).y - terrain.surface_fast(g.x, g.y + e).y).normalized()
		u["sh_off"] = g - p
		u["sh_y"] = y
	var gp: Vector2 = p + (u["sh_off"] as Vector2)
	var s := k * Tuning.g("shadow_size")
	var yaw := Basis(Vector3.UP, -heading)
	var tilt := Basis(Quaternion(Vector3.UP, u["sh_n"] as Vector3))
	var xf := Transform3D((tilt * yaw).scaled(Vector3(s, 1.0, s)), Vector3(gp.x, float(u["sh_y"]) + 3.0, gp.y))
	if sh == null:
		var tx: Texture2D = u["shb"]
		if not _shb.has(tx):
			_shb[tx] = []
		(_shb[tx] as Array).append(xf)
		return
	sh.global_transform = xf
	var al := Tuning.g("shadow_alpha")
	if u.get("sh_a") != al:
		# параметры материала — только при смене настройки, а не каждый кадр
		u["sh_a"] = al
		var mat := sh.material_override as ShaderMaterial
		mat.set_shader_parameter("alpha", al)
		mat.set_shader_parameter("blur", 0.03 + 0.03 * (1.0 - Tuning.g("shadow_size")))


## Оптимизация (финальный проход 3.5): модели сбитых самолётов врага не удаляем, а прячем и отдаём
## следующему врагу того же вида — создание модели 2–10 мс, волна из шести дронов давала рывок кадра
const POOL_MAX := 24
var _pool := {}      # картинка → [скрытые корни моделей]


func _poolable(kind: String, thick: float, bm: PackedScene, tex: Texture2D) -> bool:
	return kind == "enemy" and thick > 0.06 and bm != null and not tex.resource_path.contains("fortress")


func _pool_put(u: Dictionary) -> bool:
	if not u.has("shb") or u.get("bm") == null or u["kind"] != "enemy" or u.has("hull"):
		return false
	var tex: Texture2D = u["tex"]
	if tex.resource_path.contains("fortress"):
		return false
	var arr: Array = _pool.get(tex, [])
	if arr.size() >= POOL_MAX:
		return false
	var root: Node3D = u["node"]
	root.visible = false
	(u["mi"] as MeshInstance3D).material_overlay = null
	arr.append(root)
	_pool[tex] = arr
	return true


func _pool_take(tex: Texture2D, kind: String, thick: float, bm: PackedScene) -> Dictionary:
	if not _poolable(kind, thick, bm, tex):
		return {}
	var arr: Array = _pool.get(tex, [])
	while not arr.is_empty():
		var root: Node3D = arr.pop_back()
		if not is_instance_valid(root) or root.get_child_count() == 0:
			continue
		var mi: MeshInstance3D = null
		for c in root.get_child(0).find_children("*", "MeshInstance3D", true, false):
			mi = c
			break
		if mi == null and root.get_child(0) is MeshInstance3D:
			mi = root.get_child(0)
		if mi == null:
			root.queue_free()
			continue
		root.visible = true
		return {"node": root, "mi": mi, "kind": kind, "tex": tex, "k": 1.0, "ph": 0.0, "bank": 0.0, "seen": true,
			"weapons": {}, "bm": bm, "shb": tex}
	return {}


var _shb := {}       # картинка врага → [Transform3D] теней за кадр
var _shb_mm := {}    # картинка врага → MultiMeshInstance3D


## Тени врагов: по одному MultiMesh на вид самолёта (раньше — отдельный объект и вызов отрисовки
## на каждого врага, 60+ вызовов в тяжёлой сцене)
func _flush_shadows() -> void:
	var al := Tuning.g("shadow_alpha")
	var bl := 0.03 + 0.03 * (1.0 - Tuning.g("shadow_size"))
	for tx: Texture2D in _shb_mm:
		if not _shb.has(tx):
			(_shb_mm[tx] as MultiMeshInstance3D).multimesh.visible_instance_count = 0
	for tx: Texture2D in _shb:
		var arr: Array = _shb[tx]
		var mmi: MultiMeshInstance3D = _shb_mm.get(tx)
		if mmi == null:
			if _shadow_shader == null:
				_shadow_shader = Shader.new()
				_shadow_shader.code = SHADOW_SHADER
			var pm := PlaneMesh.new()
			pm.size = Vector2(tx.get_width(), tx.get_height())
			var mat := ShaderMaterial.new()
			mat.shader = _shadow_shader
			mat.set_shader_parameter("tex", tx)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pm
			mmi = MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.layers = PSH_LAYER
			mmi.top_level = true
			add_child(mmi)
			_shb_mm[tx] = mmi
		var mmx := mmi.multimesh
		if mmx.instance_count < arr.size():
			mmx.instance_count = arr.size() + 16
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var r := float(maxi(tx.get_width(), tx.get_height()))
		for i in arr.size():
			var xf: Transform3D = arr[i]
			mmx.set_instance_transform(i, xf)
			var e := Vector3.ONE * r * xf.basis.get_scale().x
			lo = lo.min(xf.origin - e)
			hi = hi.max(xf.origin + e)
		mmx.visible_instance_count = arr.size()
		mmi.custom_aabb = AABB(lo, hi - lo)
		var mat2 := mmi.material_override as ShaderMaterial
		if mmi.get_meta("al", -1.0) != al:
			mmi.set_meta("al", al)
			mat2.set_shader_parameter("alpha", al)
			mat2.set_shader_parameter("blur", bl)
	_shb.clear()


func _sync_units(m: Main, delta: float, sd: float) -> void:
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
			var dk := p.dive_k()   # 3.5 «Нырок»: самолёт плавно ниже и меньше на экране
			var ra := _relief_alt(u, p.global_position, p.velocity, 1.0, sd)
			var y: float = ra[0] - Tuning.g("dive_depth") * dk
			_place(u, p.global_position, p.heading, p.bank * 0.45, roll, y, (1.0 - 0.15 * dk) * _alt_scale(y), float(ra[1]) - 0.2 * p.dive_pitch())
			# форсаж: огонь длиннее, след плотнее и шире (плавно, без скачка)
			u["ab"] = move_toward(float(u.get("ab", 0.0)), 1.0 if p.ab_t > 0.0 else 0.0, sd * 4.0)
			var ab: float = u["ab"]
			PlaneFx.update(u, sd, ab)
			# M-39 (Э-2): инверсия белая, у сопла узкая и плотная, расплывается шире и тает быстрее (жизнь короче)
			var st := [lerpf(0.32, 0.55, ab), lerpf(3.0, 5.0, ab) * p.size, lerpf(18.0, 28.0, ab) * p.size, lerpf(1.2, 1.8, ab), 12.0]
			var pts := PlaneFx.trail_points(u)
			for i in pts.size():
				_trails.emit("p%d" % i, pts[i], st)
			var mi: MeshInstance3D = u["mi"]
			mi.transparency = 0.6 if (p.invuln > 0.0 and p.roll_t <= 0.0 and int(p._blink * 20.0) % 2 == 0) else 0.0
			if u.get("mech") != null:
				# Т-1: выпуск в крутом вираже и при торможении (РУД меньше крейсерского или сброс газа)
				var brake := 1.0 if p.throttle_cut_on() else (1.0 - p.throttle) / 0.4
				WingMech.update(u["mech"], p.bank, brake, int(p.taken.get("wing", 0)), sd)
				WingMech.set_transparency(u["mech"], mi.transparency)
			if u.get("ins") != null:
				Insignia.set_transparency(u["ins"], mi.transparency)
			if u.get("detail") != null:
				WingMech.set_transparency(u["detail"], mi.transparency)
			if u.get("props") != null:   # винты «Кита 1» мигают вместе с моделью
				WingMech.set_transparency(u["props"], mi.transparency)
			if u.get("bay") != null:
				# Т-5: створки открываются при сбросе бомб (перезарядка группы бомбоотсека скакнула вверх)
				var dropped := false
				for g: Hardpoint in p.groups:
					if g.weapon == "bombs":
						var key := "bay_cd_%s" % g.name
						dropped = dropped or g.cd > float(u.get(key, g.cd)) + 0.3
						u[key] = g.cd
				u["bay_t"] = WingMech.update_bay(u["bay"], dropped, sd)
				WingMech.set_transparency(u["bay"], mi.transparency)
			if u.get("modp") != null:
				ModuleParts.update(u["modp"], p.taken)
				ModuleParts.set_transparency(u["modp"], mi.transparency)
				PlaneFx.set_blue(u, bool((u["modp"] as Node3D).get_meta("blue_flame", false)))
			_sync_weapons(u, p, tex)
		for w in p.wingmen:
			var wm: Wingman = w
			var wt := wm.plane_tex()
			if wt == null or not wm.alive():
				continue
			var len_w := Tuning.g("plane_len") * 0.85 * float(wt.get_width()) / float(PlaneArt.plane_tex("fighter", 1).get_width())
			var uw := _ensure(wm.get_instance_id(), "wing", wt, len_w, 0.075, 48)
			uw["ref"] = weakref(wm)
			if uw.get("kit") == null and uw["bm"] != null:   # Т-8: полосы звена и подвесы по типу ведомого
				uw["kit"] = WingMech.attach_wing_kit(uw["node"].get_child(0) as Node3D, wt.resource_path.get_file().get_basename(), wm.type, uw["bm"])
			var rw := _relief_alt(uw, wm.global_position, Vector2.from_angle(wm.heading) * 300.0, 1.0, sd)
			_place(uw, wm.global_position, wm.heading, _turn_bank(uw, wm.heading, delta), 0.0, rw[0], _alt_scale(rw[0]), rw[1])
			if uw.get("mech") != null:
				WingMech.update(uw["mech"], float(uw["bank"]), 0.0, 0, sd)
			PlaneFx.update(uw, sd, 0.0)
			var wpts := PlaneFx.trail_points(uw)
			for i in wpts.size():
				_trails.emit("w%d_%d" % [wm.get_instance_id(), i], wpts[i], [0.22, 2.5, 14.0, 1.0, 14.0])
	# 3.5: свои самолёты вне звена (заправщик): ally_tex(), ally_len(), heading
	for n in get_tree().get_nodes_in_group("allies3d"):
		var an := n as Node2D
		var at: Texture2D = an.call("ally_tex")
		if at == null:
			continue
		var ua := _ensure(an.get_instance_id(), "ally", at, float(an.call("ally_len")), 0.075, 56)
		var ah: float = an.get("heading")
		var rl := _relief_alt(ua, an.global_position, Vector2.from_angle(ah) * 300.0, 1.0, sd)
		_place(ua, an.global_position, ah, _turn_bank(ua, ah, delta), 0.0, rl[0], _alt_scale(rl[0]), rl[1])
		PlaneFx.update(ua, sd, 0.0)
		if ua.get("bm") != null and an.get("boom_len") != null:
			_tanker_boom(ua, an, float(an.call("ally_len")))
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
			var gp := terrain.surface_fast(e.anchor.x, e.anchor.y) if (e.anchor != Vector2.INF and terrain != null) else ground_under(e.global_position)
			var hull := ang
			var tilt := Vector2.ZERO
			if e is ConvoyVehicle:
				# A-03: машина конвоя — корпус по курсу, наклон по склону и от разгона, колёса и башня
				var cr := _convoy_parts(ue, e as ConvoyVehicle, len_px, delta)
				hull = cr.x
				tilt = Vector2(cr.y, cr.z)
				_convoy_dust(e as ConvoyVehicle, gp, hull, len_px)
			elif ue.get("bm") != null:
				hull = _ground_parts(ue, e, ang, delta)
				var gt := e as GroundTarget
				if gt != null and gt.drive != null:
					# правка 3.5-s4: ЗСУ и ЗРК — корпус по курсу машины, наклон по склону и от разгона
					tilt = _drive_tilt(ue, gt.anchor, hull, gt.drive, len_px, delta)
			_place(ue, Vector2(gp.x, gp.z), hull, tilt.y, 0.0, gp.y + 1.0, (cam.global_position.y - gp.y) / cam.global_position.y, tilt.x)
		else:
			var re := _relief_alt(ue, e.global_position, Vector2.from_angle(ang) * 250.0, 0.0 if e.is_boss else 1.0, sd)
			_place(ue, e.global_position, ang, _turn_bank(ue, ang, delta), e.roll_angle(), re[0], _alt_scale(re[0]), re[1]) # 3.5: бочка при уклонении
			if ue.get("bm") != null and e is Fortress:
				_fortress_parts(ue, e as Fortress, ang, delta)
			elif ue.get("bm") != null and e is Helicopter:
				_rotors(ue, delta)
		var mi2: MeshInstance3D = ue["mi"]
		if ue.get("bm") != null:
			mi2.material_overlay = _flash_mat if e._flash > 0.0 else (_elite_mat if e.elite else null)
		else:
			# модель из картинки (транспортник и др.): подсветка только по силуэту, иначе видна сетка квадратами
			mi2.material_overlay = _cut_overlay(ue["tex"], "flash") if e._flash > 0.0 else (_cut_overlay(ue["tex"], "elite") if e.elite else null)
	_sync_wrecks(delta)
	_sync_dust(delta)
	_flush_shadows()
	_sync_plane_shadows()
	for id in _units.keys():
		if not _units[id]["seen"]:
			if not _start_crash(_units[id]) and not _pool_put(_units[id]):
				(_units[id]["node"] as Node).queue_free()
			_units.erase(id)


## Винты вертолёта (tools/blender/helicopter.py): несущий rotor — по часовой сверху, рулевой tail_rotor —
## вокруг своей оси (в GLB это локальная Z). Под лопастями — полупрозрачный диск, как размытый след винта.
func _rotors(u: Dictionary, delta: float) -> void:
	if not u.has("rot"):
		var inst := (u["node"] as Node3D).get_child(0)
		var r := inst.find_child("rotor", true, false) as Node3D
		u["rot"] = [r, inst.find_child("tail_rotor", true, false)]
		if r != null:
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.585
			cm.bottom_radius = 0.585
			cm.height = 0.002
			cm.radial_segments = 32
			cm.rings = 1
			var mt := StandardMaterial3D.new()
			mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mt.albedo_color = Color(0.12, 0.12, 0.11, 0.18)
			mt.cull_mode = BaseMaterial3D.CULL_DISABLED
			cm.material = mt
			disc.mesh = cm
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			disc.position = Vector3(0, 0.012, 0)
			r.add_child(disc)
	var rr: Array = u["rot"]
	if rr[0] != null:
		(rr[0] as Node3D).rotate_y(-delta * 9.0)
	if rr[1] != null:
		(rr[1] as Node3D).rotate_z(delta * 40.0)


## Подвижные части наземных моделей (tools/blender/ground_models.py): корпус стоит, как встал,
## башня ЗСУ (turret) смотрит на цель, антенна РЛС (antenna) вращается, контейнеры ЗРК (launcher)
## поднимаются, пока идёт захват цели — предупреждение перед пуском. Возвращает курс корпуса.
func _ground_parts(u: Dictionary, e: Enemy, ang: float, delta: float) -> float:
	if not u.has("hull"):
		u["hull"] = ang
		var inst := (u["node"] as Node3D).get_child(0)
		for nm in ["turret", "antenna", "launcher"]:
			var n := inst.find_child(nm, true, false)
			if n != null:
				u[nm] = n
	var gt := e as GroundTarget
	if gt != null and gt.drive != null:
		# правка 3.5-s4: курс корпуса — из модуля движения. Раньше брался сдвиг точки на экране,
		# а она смещается и от движения камеры — корпус «перекатывался» на стоящей машине
		u["hull"] = gt.drive.heading
	else:
		# едет — корпус по ходу движения
		var lp: Vector2 = u.get("lastp", e.global_position)
		var mv := e.global_position - lp
		u["lastp"] = e.global_position
		if mv.length() > 0.3:
			u["hull"] = lerp_angle(float(u["hull"]), mv.angle(), 1.0 - exp(-delta * 4.0))
	var hull: float = u["hull"]
	if u.has("turret"):
		(u["turret"] as Node3D).rotation.y = -wrapf(ang - hull, -PI, PI)
	if u.has("antenna"):
		(u["antenna"] as Node3D).rotate_y(delta * 1.6)
	if u.has("launcher"):
		var up := deg_to_rad(55.0) if float(e.get("_lock") if e.get("_lock") != null else 0.0) > 0.0 else 0.0
		var ln := u["launcher"] as Node3D
		ln.rotation.z = move_toward(ln.rotation.z, up, delta * 1.2)
	return hull if (u.has("turret") or u.has("antenna") or u.has("launcher")) else ang


## A-03: подвижные части машин конвоя (tools/blender/convoy_models.py): колёса крутятся по пройденному пути
## (GroundDrive.dist), передние поворачивают по рулю; башня и пулемёт смотрят на самолёт; труба ПЗРК
## поднимается при захвате. Корпус лежит на склоне (рельеф под носом и кормой, бортами), клюёт носом
## при торможении и кренится наружу на повороте. Возвращает (курс корпуса, тангаж, крен).
func _convoy_parts(u: Dictionary, v: ConvoyVehicle, len_px: float, delta: float) -> Vector3:
	var dr := v.drive
	var hull := v.heading
	if dr == null:
		return Vector3(hull, 0.0, 0.0)
	if u.get("bm") != null and not u.has("cv"):
		var inst := (u["node"] as Node3D).get_child(0)
		var d := {"wheels": [], "front": []}
		for c in inst.find_children("wheel_*", "Node3D", true, false):
			(d["wheels"] as Array).append(c)
			if String(c.name).begins_with("wheel_f"):
				(d["front"] as Array).append(c)
		for nm in ["turret", "launcher"]:
			var n := inst.find_child(nm, true, false)
			if n != null:
				d[nm] = n
		u["cv"] = d
	if u.has("cv"):
		var d: Dictionary = u["cv"]
		# колесо радиусом ~0,07 длины машины: угол = путь / радиус
		var roll := -dr.dist / (0.072 * len_px)
		for w in d["wheels"]:
			(w as Node3D).rotation = Vector3(0.0, 0.0, roll)
		for w in d["front"]:
			(w as Node3D).rotation = Vector3(0.0, -dr.steer * 0.45, roll)
		var p := Main.I.player
		if d.has("turret") and p != null:
			var t := d["turret"] as Node3D
			var aim := (p.global_position - v.global_position).angle()
			var want := -wrapf(aim - hull, -PI, PI) if v.alarm_on() else 0.0
			t.rotation.y = lerp_angle(t.rotation.y, want, 1.0 - exp(-delta * 3.0))
		if d.has("launcher"):
			var ln := d["launcher"] as Node3D
			ln.rotation.z = move_toward(ln.rotation.z, deg_to_rad(35.0) if v._lock > 0.0 else 0.0, delta * 1.5)
	var sm := _drive_tilt(u, v.anchor, hull, dr, len_px, delta)
	return Vector3(hull, sm.x, sm.y)


## Наклон корпуса машины (тангаж, крен): по рельефу под носом, кормой и бортами; клевок при торможении,
## приседание при разгоне, крен наружу на повороте, мелкая раскачка на ходу. Общее для конвоя и ПВО.
func _drive_tilt(u: Dictionary, a: Vector2, hull: float, dr: GroundDrive, len_px: float, delta: float) -> Vector2:
	var pitch := 0.0
	var bank := 0.0
	if terrain != null and a != Vector2.INF:
		var f := Vector2.from_angle(hull) * len_px * 0.45
		var sd := Vector2(-f.y, f.x) * 0.45
		pitch = atan2(terrain.surface_fast(a.x + f.x, a.y + f.y).y - terrain.surface_fast(a.x - f.x, a.y - f.y).y, len_px * 0.9)
		bank = atan2(terrain.surface_fast(a.x + sd.x, a.y + sd.y).y - terrain.surface_fast(a.x - sd.x, a.y - sd.y).y, len_px * 0.4)
	pitch += clampf(dr.acc_now * 0.0012, -0.06, 0.06)
	bank += clampf(-dr.yaw_rate * dr.speed * 0.0009, -0.07, 0.07) + sin(dr.dist * 0.09) * 0.006 * clampf(dr.speed / 60.0, 0.0, 1.0)
	var sm: Vector2 = u.get("tilt", Vector2(pitch, bank))
	sm = sm.lerp(Vector2(pitch, bank), 1.0 - exp(-delta * 6.0))
	u["tilt"] = sm
	return sm


## A-08: пыльный след за машиной конвоя (тест 3.5-s6): частицы в мировых координатах из-под кормы,
## гуще на скорости, сносятся ветром и расплываются. Остов и машина за кадром — след гаснет и убирается.
var _dust := {}      # instance_id → {"p": CPUParticles3D, "seen": bool, "t": сек. после остановки}
var _dust_mat: StandardMaterial3D


func _convoy_dust(v: ConvoyVehicle, gp: Vector3, hull: float, len_px: float) -> void:
	if v.drive == null:
		return
	var id := v.get_instance_id()
	var d: Dictionary = _dust.get(id, {})
	if d.is_empty():
		d = {"p": _make_dust(len_px), "t": 0.0}
		_dust[id] = d
	d["seen"] = true
	var ps := d["p"] as CPUParticles3D
	var back := Vector2(gp.x, gp.z) - Vector2.from_angle(hull) * len_px * 0.5
	ps.global_position = Vector3(back.x, gp.y + len_px * 0.04, back.y)
	ps.emitting = v.drive.speed > 18.0
	d["t"] = 0.0


func _sync_dust(delta: float) -> void:
	for id in _dust.keys():
		var d: Dictionary = _dust[id]
		var ps := d["p"] as CPUParticles3D
		if not d.get("seen", false):
			ps.emitting = false
			d["t"] = float(d["t"]) + delta
			if float(d["t"]) > ps.lifetime + 0.5:
				ps.queue_free()
				_dust.erase(id)
				continue
		d["seen"] = false


func _make_dust(len_px: float) -> CPUParticles3D:
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.albedo_texture = Fx._smoke_n[0] if not Fx._smoke_n.is_empty() else Fx._soft
		_dust_mat.vertex_color_use_as_albedo = true
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _dust_mat
	var s := CPUParticles3D.new()
	s.mesh = q
	s.amount = [8, 14, 20, 24][clampi(Settings.gfx, 0, 3)]
	s.lifetime = 2.2
	s.local_coords = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.direction = Vector3.UP
	s.spread = 70.0
	s.initial_velocity_min = 2.0
	s.initial_velocity_max = 7.0
	s.damping_min = 1.0
	s.damping_max = 2.0
	s.gravity = Vector3(5.0, 2.5, 3.0)   # ветер, как у дыма, но пыль тяжелее — почти не поднимается
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = len_px * 0.12
	s.angle_min = 0.0
	s.angle_max = 360.0
	s.scale_amount_min = len_px * 0.35
	s.scale_amount_max = len_px * 0.5
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.2))
	s.scale_amount_curve = sc
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	gr.colors = PackedColorArray([Color(0.92, 0.85, 0.72, 0.0), Color(0.9, 0.83, 0.7, 0.55), Color(0.84, 0.78, 0.68, 0.0)])   # светлее песка — видно сверху
	s.color_ramp = gr
	s.emitting = false
	add_child(s)
	return s


## A-03: остовы машин конвоя — та же модель, обгоревшая: тент и стрелки пропадают, корпус тёмный, дым столбом
var _burnt_mat: StandardMaterial3D


func _sync_wrecks(delta: float) -> void:
	for n in get_tree().get_nodes_in_group("wrecks3d"):
		var v := n as ConvoyVehicle
		if v == null or v.anchor == Vector2.INF:
			continue
		var info := v.sprite_info()
		var t: Texture2D = Enemy.etex(String(info.get("tex", ""))) if not info.is_empty() else null
		if t == null:
			continue
		var len_px: float = float(info["len"]) * Tuning.g("unit_scale")
		var u := _ensure(v.get_instance_id(), "enemy", t, len_px, 0.05, 40)
		if not u.has("wreck"):
			u["wreck"] = true
			if _burnt_mat == null:
				_burnt_mat = StandardMaterial3D.new()
				_burnt_mat.albedo_color = Color(0.03, 0.025, 0.02, 0.78)
				_burnt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_burnt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if u.get("bm") != null:
				var inst := (u["node"] as Node3D).get_child(0)
				for nm in ["tent", "launcher"]:
					var hn := inst.find_child(nm, true, false) as Node3D
					if hn != null:
						hn.visible = false
				for c in inst.find_children("*", "GeometryInstance3D", true, false):
					(c as GeometryInstance3D).material_overlay = _burnt_mat
			var smoke := _make_smoke()   # создаётся дочерним у Render3D — переносим к остову, чтобы ушёл вместе с ним
			smoke.get_parent().remove_child(smoke)
			smoke.top_level = true
			(u["node"] as Node3D).add_child(smoke)
			u["wsmoke"] = smoke
		var gp := terrain.surface_fast(v.anchor.x, v.anchor.y) if terrain != null else ground_under(v.global_position)
		var tilt: Vector2 = u.get("tilt", Vector2.ZERO)
		_place(u, Vector2(gp.x, gp.z), v.heading, tilt.y + 0.04, 0.0, gp.y + 0.5, (cam.global_position.y - gp.y) / cam.global_position.y, tilt.x)
		if u.has("wsmoke"):
			var sm := u["wsmoke"] as CPUParticles3D
			sm.global_position = Vector3(gp.x, gp.y + 4.0, gp.z)
			sm.emitting = v._burn < 12.0
		if u.get("bm") == null:
			(u["mi"] as MeshInstance3D).material_overlay = _burnt_mat


## Подвижные части «Крепости» (tools/blender/fortress.py): башни смотрят на игрока, винты крутятся,
## выбитые точки (Fortress.parts_down) пропадают или останавливаются; с фазы 2 открываются люки
## и поднимаются ракеты, в фазе 3 откидываются панели обшивки над раскалённым ядром.
const FORTRESS_NODES := ["turret_1", "turret_2", "turret_3", "turret_4", "engine_l_prop", "engine_l_prop2",
	"engine_r_prop", "engine_r_prop2", "hatch_l", "hatch_r", "bay_l", "bay_r", "hull_l", "hull_r", "core"]


func _fortress_parts(u: Dictionary, f: Fortress, ang: float, delta: float) -> void:
	if not u.has("fparts"):
		var inst := (u["node"] as Node3D).get_child(0)
		var d := {}
		for nm in FORTRESS_NODES:
			var n := inst.find_child(nm, true, false) as Node3D
			if n != null:
				d[nm] = n
				d[nm + "@"] = n.position
		u["fparts"] = d
	var parts: Dictionary = u["fparts"]
	var p := Main.I.player
	for i in 4:
		var nm := "turret_%d" % (i + 1)
		if not parts.has(nm):
			continue
		var t := parts[nm] as Node3D
		t.visible = not f.parts_down.has(nm)
		if t.visible and p != null and i < f.points.size():
			var to := p.global_position - (f.global_position + (f.points[i]["off"] as Vector2).rotated(ang))
			t.rotation.y = lerp_angle(t.rotation.y, -wrapf(to.angle() - ang, -PI, PI), 1.0 - exp(-delta * 6.0))
	for side in ["l", "r"]:
		var down := f.parts_down.has("engine_" + side)
		for k in ["", "2"]:
			var nm: String = "engine_%s_prop%s" % [side, k]
			if parts.has(nm):
				var pr := parts[nm] as Node3D
				if down:   # винт встал, лопасти перекошены
					pr.rotation.x = lerp_angle(pr.rotation.x, 0.4 if k == "" else -0.3, 1.0 - exp(-delta * 2.0))
				else:
					pr.rotate_x(delta * (22.0 if k == "" else -22.0))
		var s := -1.0 if side == "l" else 1.0   # левая створка (−Z в Godot) открывается против часовой вокруг X
		if parts.has("hatch_" + side):
			var h := parts["hatch_" + side] as Node3D
			h.rotation.x = move_toward(h.rotation.x, s * deg_to_rad(125.0) if f.hatches_open else 0.0, delta * 2.0)
		if parts.has("bay_" + side):
			var b := parts["bay_" + side] as Node3D
			var base: Vector3 = parts["bay_" + side + "@"]
			b.position.y = move_toward(b.position.y, base.y + (0.012 if f.hatches_open else 0.0), delta * 0.02)
		if parts.has("hull_" + side):
			var hp := parts["hull_" + side] as Node3D
			hp.rotation.x = move_toward(hp.rotation.x, s * deg_to_rad(140.0) if f.hull_open else 0.0, delta * 1.5)
	if parts.has("core"):
		var c := parts["core"] as Node3D
		var pulse := 1.0 + (0.08 * sin(Time.get_ticks_msec() * 0.012) if f.hull_open else 0.0)
		c.scale = Vector3(1.0, pulse, 1.0)


## Штанга заправщика (tools/blender/tanker_boom.py, узлы Boom / BoomTube / BoomTip).
## Логика заправщика (tanker.gd) считает штангу от точки в BOOM_ROOT пикс. за центром; у модели штанга
## выходит из-под хвоста — длину и угол пересчитываем так, чтобы наконечник был там же, где в логике.
const BOOM_PITCH := deg_to_rad(10.0)


func _tanker_boom(u: Dictionary, an: Node2D, len_px: float) -> void:
	if not u.has("boom"):
		var inst := (u["node"] as Node3D).get_child(0)
		var b := inst.find_child("Boom", true, false) as Node3D
		u["boom"] = b
		u["boom_tube"] = inst.find_child("BoomTube", true, false) if b != null else null
		u["boom_tip"] = inst.find_child("BoomTip", true, false) if b != null else null
	var boom := u["boom"] as Node3D
	if boom == null or u["boom_tube"] == null:
		return
	# наконечник в осях заправщика (пикс., x — вперёд), потом в единицы модели (1 = длина модели)
	var tip := Vector2(-Tanker.BOOM_ROOT, 0.0) + Vector2(-float(an.get("boom_len")), 0.0).rotated(float(an.get("boom_angle")))
	var v := tip / len_px - Vector2(boom.position.x, boom.position.z)
	var l := maxf(v.length(), 0.05)
	boom.rotation.y = atan2(v.y, -v.x)
	(u["boom_tube"] as Node3D).scale.x = l
	if u["boom_tip"] != null:
		(u["boom_tip"] as Node3D).position = Vector3(-cos(BOOM_PITCH), -sin(BOOM_PITCH), 0.0) * l


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
	var wc: Dictionary = u.get("wcache", {})   # оптимизация (финальный проход 3.5): раскладка подвесов группы
	u["wcache"] = wc
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		if g.is_empty():
			continue
		# U-08: у экспериментального оружия нет плоского значка, но есть 3D-модель (exp_weapons.py)
		if PlaneArt.weapon_tex(g.weapon) == null and not (g.weapon in Weapons.EXP):
			continue
		var seek := ModuleParts.stage(int(p.taken.get("seeker", 0))) if g.weapon == "aam" and not g.evo else 0
		var sig := [p.cls_id, p.plane_lvl, g.weapon, g.level, g.evo, g.slots, g.builtin, g.name, seek, u["k"], Tuning.g("plane_len"), u.get("bm")]
		var ent: Dictionary = wc.get(gi, {})
		if ent.is_empty() or ent["sig"] != sig:
			ent = _weapon_layout(u, p, tex, gi, g, seek)
			ent["sig"] = sig
			ent["ver"] = int(wc.get("ver", 0)) + 1
			wc["ver"] = ent["ver"]
			wc[gi] = ent
		var dim := g.weapon in ["aam", "rockets", "bombs"] and g.cd > 0.3
		var len_px: float = ent["len_px"]
		var l_offs: Array = []
		for mt: Dictionary in ent["mounts"]:
			var key: String = mt["key"]
			want[key] = true
			var wmi: MeshInstance3D = u["weapons"].get(key)
			if wmi == null:
				wmi = WeaponModels.make(g.weapon, mt["t"], mt["side"], p.cls_id, g.evo, p.plane_lvl)
				ModuleParts.seeker_head(wmi, seek, mt["t"])   # Т-3: «Глазастик»
				root.add_child(wmi)
				u["weapons"][key] = wmi
			var tail_cab: bool = mt["tail_cab"]
			var fresh := int(wmi.get_meta("wver", -1)) != int(ent["ver"])
			if fresh:
				wmi.set_meta("wver", ent["ver"])
				wmi.position = mt["pos"]
			if tail_cab and u.get("tail") != null:   # кабина — продолжение фюзеляжа модели, шар — у её торца
				var tpos := WingMech.tail_mount(u["tail"], root)
				if tpos != Vector3.INF:
					wmi.position = tpos
					if wmi.get_child_count() > 0:
						(wmi.get_child(0) as Node3D).visible = false
			var yaw: float = mt["yaw"]
			if g.weapon == "turret":   # п. 37: турель смотрит на ближайшую цель
				var idle := yaw
				# правка 3.5-s4 (п. 13): стволы смотрят туда же, куда наведена турель в бою (aim), без цели —
				# плавно возвращаются в походное положение; поворот с той же ограниченной скоростью
				var tgt := -wrapf(g.aim - p.heading, -PI, PI) if g.has_aim_target() else idle
				var cur := float(wmi.get_meta("yaw_cur", idle))
				cur = rotate_toward(cur, tgt, deg_to_rad(Hardpoint.TURRET_TRAVERSE) * float(p.mods.get("turret_traverse", 1.0)) * get_process_delta_time())
				wmi.set_meta("yaw_cur", cur)
				yaw = cur
				if mt["side"] == "tail":   # кормовая установка — в секторе ±60° назад, как настоящая
					yaw = idle + clampf(wrapf(yaw - idle, -PI, PI), -1.05, 1.05)
			if fresh or g.weapon == "turret":
				var b := Basis(Vector3.UP, yaw)
				if mt["flip"]:
					b = b * Basis(Vector3.RIGHT, PI)
				wmi.basis = b.scaled(Vector3(len_px, len_px, len_px))
				if tail_cab and wmi.get_child_count() > 0:   # кабина стрелка неподвижна, крутится только шар
					(wmi.get_child(0) as Node3D).basis = Basis(Vector3.UP, float(mt["yaw"]) - yaw)
			if g.weapon == "aam" or g.weapon == "rockets":
				# правка 3.5-s4 (п. 27): ракета ушла с пилона — её там нет до перезарядки; пуск — с этой точки
				wmi.visible = not dim
				var wp := root.global_transform * wmi.position
				l_offs.append((Vector2(wp.x, wp.z) - p.global_position).rotated(-p.heading))
			else:
				if g.weapon == "bombs":
					# тест 3.5-s5 (п. 3): бомбы падают с точек подвеса (из бомбоотсека — из открытого люка);
					# у «ковра» в отсеке — с места каждой из 8 бомб кассеты
					var bl: Array = WeaponModels.CARPET_BAY_PTS if int(mt["t"]) == WeaponModels.CARPET_BAY_T else [Vector3.ZERO]
					for lp: Vector3 in bl:
						var bw := root.global_transform * (wmi.transform * lp)
						l_offs.append((Vector2(bw.x, bw.z) - p.global_position).rotated(-p.heading))
				var tr_w := 0.6 if dim else 0.0
				if wmi.transparency != tr_w:
					wmi.transparency = tr_w
			if mt["side"] == "bay":   # в закрытом бомбоотсеке бомб не видно
				wmi.visible = float(u.get("bay_t", 1.0)) > 0.4
		if g.weapon in ["aam", "rockets", "bombs"]:
			g.launch_offs = l_offs
	for key in u["weapons"].keys():
		if not want.has(key):
			(u["weapons"][key] as Node).queue_free()
			u["weapons"].erase(key)


## Раскладка подвесов группы: точки, высота пилона, модель — считается при смене оружия, уровня или самолёта,
## а не каждый кадр (раньше — до 1,7 мс на кадр у «Кита» с полным набором)
func _weapon_layout(u: Dictionary, p: Player, tex: Texture2D, gi: int, g: Hardpoint, seek: int) -> Dictionary:
	var pts := WeaponModels.mounts(p.cls_id, p.plane_lvl, gi, g)
	var k: float = u["k"]
	var len_px: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) * Tuning.g("plane_len") / k  # в пикселях текстуры самолёта
	# 3.4-t1 (п. 3): объёмные модели, вид меняется на ур. 3 и 5
	var tr := WeaponModels.tier(g.level, g.evo)
	var tw := float(tex.get_width())
	var out: Array = []
	for si in pts.size():
		var mt: Dictionary = pts[si]
		var mtr: int = mt.get("t", tr)   # Т-5: у ловушек модель задаёт точка (кассета / контейнер)
		var pt: Vector2 = mt["p"]
		# подвесы — под крылом на пилоне (видны на крене и под наклоном камеры), турели — на своих местах
		# турель-модель в корме висит под концом фюзеляжа основанием вверх (как нижняя)
		var tail_cab: bool = mt["side"] == "tail" and g.weapon == "turret" and (WeaponModels.TURRET_MODELS.get(p.cls_id, {}) as Dictionary).has("tail")
		var under_tail: bool = mt["side"] == "tail" and g.weapon == "turret" and WeaponModels.TURRET_MODELS.has(p.cls_id) and not tail_cab
		var y: float = {"under": -tw * 0.012 - WeaponModels.hang(g.weapon, mtr, g.evo) * len_px, "belly": -tw * 0.028 - (WeaponModels.hang(g.weapon, tr, true) - WeaponModels.PYLON_H) * len_px, "bay": -tw * 0.02 - (WeaponModels.hang(g.weapon, mtr) - WeaponModels.PYLON_H) * len_px * 0.6, "top": tw * 0.028, "wing": tw * 0.012, "bottom": -tw * 0.028, "tail": -tw * 0.028 if under_tail else 0.0}.get(mt["side"], 0.0)
		if mt["side"] == "under" and u.get("bm") != null:   # пилон — под настоящим крылом модели (тест 3.5-s3)
			var lo := WeaponModels.surface_low(u["bm"], pt.x / tw, pt.y / tw)
			if not is_nan(lo):
				y = lo * tw - WeaponModels.hang(g.weapon, mtr, g.evo) * len_px
		elif mt["side"] == "top" and g.weapon == "turret" and u.get("bm") != null:
			# тест 3.5-s7: верхняя турель — на настоящей спине фюзеляжа (у «Кита» она выше, чем у «Грача»)
			var hi := WeaponModels.surface_low(u["bm"], pt.x / tw, pt.y / tw, true)
			if not is_nan(hi):
				y = hi * tw
		elif mt["side"] == "bay" and u.get("bm") != null:
			# тест 3.5-s5 (п. 3): бомбы и кассета «ковра» — от настоящего брюха модели, как в ангаре
			# (иначе верх кассеты проходил сквозь фюзеляж и был виден сверху)
			var lo2 := WeaponModels.surface_low(u["bm"], pt.x / tw, pt.y / tw)
			if not is_nan(lo2):
				y = lo2 * tw - (WeaponModels.hang(g.weapon, mtr) - WeaponModels.PYLON_H) * len_px * 0.6
		out.append({"key": "%d_%d_%s_%d%s_s%d" % [gi, si, g.weapon, mtr, "e" if g.evo else "", seek], "t": mtr,
			"side": mt["side"], "yaw": float(mt["yaw"]), "pos": Vector3(pt.x, y, pt.y), "tail_cab": tail_cab,
			"flip": mt["side"] == "bottom" or under_tail})
	return {"mounts": out, "len_px": len_px}


# ---------- 3.4-t1: следы ракет (п. 34) ----------

func _sync_missiles(m: Main) -> void:
	var pr := m.projectiles
	if pr == null:
		return
	# M-39 (аудит 3.5-s6 Э-2): дым ракет светло-серый, плотный и широкий у сопла, расплывается и тает быстрее
	# (жизнь короче — без длинных дуг через полэкрана); на «Низком» точки реже
	var lo := 1.5 if Settings.gfx == 0 else 1.0
	for arr_st in [[pr.pmissiles, [0.85, 5.0, 14.0, 1.0, 16.0 * lo, Color(0.9, 0.9, 0.91)]],
			[pr.missiles, [0.8, 5.0, 13.0, 0.95, 16.0 * lo, Color(0.84, 0.83, 0.82)]],
			[pr.rockets, [0.7, 3.5, 9.0, 0.6, 14.0 * lo, Color(0.88, 0.88, 0.9)]]]:
		for mm: Dictionary in arr_st[0]:
			if float(mm.get("delay", 0.0)) > 0.0:
				continue
			if not mm.has("tid"):
				_tid += 1
				mm["tid"] = _tid
			var v: Vector2 = mm["v"]
			var tail: Vector2 = mm["p"] - (v.normalized() * 9.0 if v.length() > 1.0 else Vector2.ZERO)
			var st: Array = arr_st[1]
			if mm.has("tint"):   # связки: след своего цвета (бирюзовый, золотой…), но светлый
				st = st.duplicate()
				st[5] = (mm["tint"] as Color).lerp(Color.WHITE, 0.45)
			_trails.emit(int(mm["tid"]), Vector3(tail.x, -2.0, tail.y), st)


# ---------- тест 3.5-s5 (п. 11): пули и ракеты врагов в 3D ----------

## Ракеты врагов — модель (WeaponModels «enemy_msl») по курсу, пули — светящиеся трассеры с ореолом:
## красные у обычных врагов, оранжевые у асов, крупные шары — залпы асов и «Крепости». Всё — два MultiMesh
## (два вызова отрисовки на любое число снарядов). Трассеры и ореолы поверх моделей и облаков, как прежний слой боя.
const ESHOT_LEN := 30.0              # длина ракеты врага, px (картинка была 24)
const EGLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
varying vec4 col;
void vertex() {
	col = COLOR;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;          // x — вдоль полёта (+1 — голова), y — поперёк
	float d = length(p);
	float head = smoothstep(-1.0, 0.5, p.x);   // к хвосту трассер гаснет
	float halo = smoothstep(1.0, 0.15, d) * head;
	float core = smoothstep(0.42, 0.08, length(vec2(p.x * 0.8, p.y * 1.6))) * head;
	ALBEDO = mix(col.rgb, vec3(1.0, 0.96, 0.92), core);
	ALPHA = clamp(halo * 0.7 * col.a + core, 0.0, 1.0);
}
"""


func _sync_enemy_shots(m: Main) -> void:
	var pr := m.projectiles
	if pr == null:
		return
	if _eshot_mm == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = WeaponModels.mesh("enemy_msl", 1)
		mm.instance_count = 32
		mm.visible_instance_count = 0
		_eshot_mm = MultiMeshInstance3D.new()
		_eshot_mm.multimesh = mm
		_eshot_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_eshot_mm.top_level = true
		add_child(_eshot_mm)
		var sh := Shader.new()
		sh.code = EGLOW_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.render_priority = 99   # под слоем боя (взрывы, текст), над моделями
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		var gm := MultiMesh.new()
		gm.transform_format = MultiMesh.TRANSFORM_3D
		gm.use_colors = true
		gm.mesh = pm
		gm.instance_count = 256
		gm.visible_instance_count = 0
		_eglow_mm = MultiMeshInstance3D.new()
		_eglow_mm.multimesh = gm
		_eglow_mm.material_override = mat
		_eglow_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_eglow_mm.top_level = true
		add_child(_eglow_mm)
	var mmx := _eshot_mm.multimesh
	var gmx := _eglow_mm.multimesh
	var n_m := 0
	var n_g := 0
	var need_g := pr.ebullets.size() + pr.missiles.size() * 2
	if gmx.instance_count < need_g:
		gmx.instance_count = need_g + 64
	if mmx.instance_count < pr.missiles.size():
		mmx.instance_count = pr.missiles.size() + 16
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for b: Dictionary in pr.ebullets:
		var p: Vector2 = b["p"]
		var v: Vector2 = b["v"]
		var dir := v.normalized() if v.length() > 1.0 else Vector2.RIGHT
		var ace: bool = b.get("who", "") == "асы"
		var c: Color
		var ln: float
		var w: float
		if b["big"]:
			c = Color(1.0, 0.42, 0.18, 1.0)
			ln = 16.0
			w = 16.0
		else:
			c = Color(1.0, 0.62, 0.15, 1.0) if ace else Color(1.0, 0.18, 0.3, 1.0)
			ln = 17.0
			w = 5.5
		var ctr := Vector3(p.x - dir.x * ln * 0.55, 1.0, p.y - dir.y * ln * 0.55)
		var xa := Vector3(dir.x, 0, dir.y) * ln
		var za := Vector3(-dir.y, 0, dir.x) * w
		gmx.set_instance_transform(n_g, Transform3D(Basis(xa, Vector3.UP, za), ctr))
		gmx.set_instance_color(n_g, c)
		lo = lo.min(ctr)
		hi = hi.max(ctr)
		n_g += 1
	for ms: Dictionary in pr.missiles:
		var p: Vector2 = ms["p"]
		var v: Vector2 = ms["v"]
		var dir := v.normalized() if v.length() > 1.0 else Vector2.RIGHT
		var y := 0.0
		var bs := Basis(Vector3.UP, -dir.angle()).scaled(Vector3.ONE * ESHOT_LEN)
		var pos := Vector3(p.x, y, p.y)
		mmx.set_instance_transform(n_m, Transform3D(bs, pos))
		n_m += 1
		lo = lo.min(pos)
		hi = hi.max(pos)
		var lost: bool = ms["lost"]
		# факел двигателя у хвоста и красный ореол вокруг (у уведённой ловушкой — без ореола, факел тусклый)
		var tail := pos - Vector3(dir.x, 0, dir.y) * ESHOT_LEN * 0.55
		var fl := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05 + float(n_m))
		gmx.set_instance_transform(n_g, Transform3D(Basis(Vector3(-dir.x, 0, -dir.y) * 9.0 * fl, Vector3.UP, Vector3(-dir.y, 0, dir.x) * 4.5), tail + Vector3(0, 1.0, 0)))
		gmx.set_instance_color(n_g, Color(1.0, 0.7, 0.25, 1.0 if not lost else 0.5))
		n_g += 1
		if not lost:
			gmx.set_instance_transform(n_g, Transform3D(Basis(Vector3(dir.x, 0, dir.y) * 20.0, Vector3.UP, Vector3(-dir.y, 0, dir.x) * 14.0), pos - Vector3(0, 0.5, 0)))
			gmx.set_instance_color(n_g, Color(1.0, 0.1, 0.05, 0.45))
			n_g += 1
	mmx.visible_instance_count = n_m
	gmx.visible_instance_count = n_g
	if n_m + n_g > 0:
		var aabb := AABB(lo - Vector3(40, 40, 40), hi - lo + Vector3(80, 80, 80))
		_eshot_mm.custom_aabb = aabb
		_eglow_mm.custom_aabb = aabb


# ---------- 3.4-t1: сбитый ведомый падает (п. 32) ----------

const CRASH_G := 300.0        # ускорение падения, пикс/с²
const WRECK_LIFE := 40.0      # сколько лежат обломки, с
const WRECK_MAX := 8


## Ведомый сбит (hp ≤ 0) — модель не удаляем, а роняем: дым, крен, удар о землю
func _start_crash(u: Dictionary) -> bool:
	if u["kind"] != "wing" or not u.has("ref"):
		return false
	var wm: Wingman = (u["ref"] as WeakRef).get_ref()
	if wm == null or wm.hp > 0.0:
		return false
	var root: Node3D = u["node"]
	if u.has("sh"):
		(u["sh"] as Node3D).visible = false
	PlaneFx.update(u, 0.0, 0.0, false)
	var smoke := _make_smoke()
	smoke.position = root.position
	var dir := Vector2.from_angle(wm.heading)
	_crashes.append({"u": u, "p": Vector2(root.position.x, root.position.z), "y": root.position.y, "vy": -60.0,
		"v": dir * 260.0, "hd": wm.heading, "roll": float(u["bank"]), "spin": (2.0 + randf() * 2.0) * (1.0 if randf() < 0.5 else -1.0),
		"t": 0.0, "smoke": smoke})
	return true


func _sync_crashes(m: Main, sd: float) -> void:
	for i in range(_crashes.size() - 1, -1, -1):
		var c: Dictionary = _crashes[i]
		var u: Dictionary = c["u"]
		var root: Node3D = u["node"]
		var smoke: CPUParticles3D = c["smoke"]
		c["t"] = float(c["t"]) + sd
		c["v"] = (c["v"] as Vector2) * exp(-0.5 * sd)
		c["p"] = (c["p"] as Vector2) + (c["v"] as Vector2) * sd
		c["vy"] = float(c["vy"]) - CRASH_G * sd
		c["y"] = float(c["y"]) + float(c["vy"]) * sd
		c["roll"] = float(c["roll"]) + float(c["spin"]) * sd
		c["hd"] = float(c["hd"]) + float(c["spin"]) * 0.25 * sd
		var p: Vector2 = c["p"]
		var pitch := clampf(float(c["t"]) * 0.6, 0.0, 1.0)   # нос опускается
		var k: float = u["k"]
		root.position = Vector3(p.x, c["y"], p.y)
		root.basis = (Basis(Vector3.UP, -float(c["hd"])) * Basis(Vector3.BACK, -pitch) * Basis(Vector3.RIGHT, c["roll"])).scaled(Vector3(k, k, k))
		smoke.position = root.position
		var gy := terrain.surface_fast(p.x, p.y).y if terrain != null else GROUND_Y
		if float(c["y"]) > gy + 6.0:
			continue
		# удар о землю: взрыв и пятно там, где на экране земля под обломками
		var g3 := Vector3(p.x, gy, p.y)
		var p2 := _ground_to_combat(g3)
		if m.fx != null:
			m.fx.explosion(p2, 30.0, false)
			if is_instance_valid(m.fx.ground):
				m.fx.ground.scorch(p2, 38.0, false)
		light_flash(p2, 30.0)
		_crashes.remove_at(i)
		if _on_water(g3, 0.0):   # M-35: упал в реку — остов уходит под воду, на берегу его нет
			_free_wreck({"n": root, "smoke": smoke})
			continue
		# остов: тёмный, приплюснутый, лежит по склону; дымит ещё несколько секунд
		root.position = g3 + Vector3(0, 2.0, 0)
		root.basis = (Basis(Vector3.UP, -float(c["hd"]) + randf_range(-0.4, 0.4)) * Basis(Vector3.RIGHT, randf_range(-0.15, 0.15))).scaled(Vector3(k * 0.9, k * 0.4, k * 0.9))
		for gi in root.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).material_overlay = _wreck_mat
		for hub in (u.get("fx", {}) as Dictionary).get("props", []):
			(hub as Node3D).visible = false
		smoke.position = g3 + Vector3(0, 6.0, 0)
		smoke.amount = 16
		_wrecks.append({"n": root, "t": WRECK_LIFE, "smoke": smoke})
		if _wrecks.size() > WRECK_MAX:
			_free_wreck(_wrecks.pop_front())
	for i in range(_wrecks.size() - 1, -1, -1):
		var w: Dictionary = _wrecks[i]
		w["t"] = float(w["t"]) - sd
		if is_instance_valid(w["smoke"]) and float(w["t"]) < WRECK_LIFE - 8.0:
			(w["smoke"] as CPUParticles3D).emitting = false
		if float(w["t"]) <= 0.0:
			_free_wreck(w)
			_wrecks.remove_at(i)


## M-35: пятно радиуса r с центром g на воде (русло + половина пятна). Копоть и воронки боя в воду не кладём;
## на мокрый берег — можно: это следы боя на 25–75 с, а не постоянная текстура, и бомбёжка колонны
## на прибрежной дороге без воронок у обочины выглядела бы пустой
func _on_water(g: Vector3, r: float) -> bool:
	return terrain != null and absf(terrain.river_field(g.x, g.z)) < Terrain3D.D_RIVER + r * 0.5


func _free_wreck(w: Dictionary) -> void:
	(w["n"] as Node).queue_free()
	if is_instance_valid(w["smoke"]):
		(w["smoke"] as Node).queue_free()


## Точка плоскости боя (y = 0), которая на экране совпадает с точкой мира g3 (обратное ground_under)
func _ground_to_combat(g3: Vector3) -> Vector2:
	var c := cam.global_position
	var k := c.y / maxf(c.y - g3.y, 1.0)
	return Vector2(c.x + (g3.x - c.x) * k, c.z + (g3.z - c.z) * k)


## Шлейф дыма с огнём у падающего самолёта: частицы в мировых координатах, поднимаются и расплываются
func _make_smoke() -> CPUParticles3D:
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.albedo_texture = Fx._smoke_n[0] if not Fx._smoke_n.is_empty() else Fx._soft
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _smoke_mat
	var s := CPUParticles3D.new()
	s.mesh = q
	s.amount = 36
	s.lifetime = 1.8
	s.local_coords = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.direction = Vector3.UP
	s.spread = 30.0
	s.initial_velocity_min = 10.0
	s.initial_velocity_max = 30.0
	s.gravity = Vector3(8.0, 25.0, 6.0)   # ветер и подъём тёплого дыма
	s.angle_min = 0.0
	s.angle_max = 360.0
	s.scale_amount_min = 26.0
	s.scale_amount_max = 40.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(1, 2.5))
	s.scale_amount_curve = sc
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.06, 0.2, 1.0])
	gr.colors = PackedColorArray([Color(1.0, 0.75, 0.3, 0.95), Color(0.9, 0.4, 0.12, 0.8), Color(0.18, 0.17, 0.16, 0.6), Color(0.3, 0.3, 0.3, 0.0)])
	s.color_ramp = gr
	s.emitting = true
	add_child(s)
	return s


## Угол турели (в осях самолёта) на ближайшего врага в радиусе 700 px; без цели — вперёд
func _turret_yaw(p: Player, root: Node3D, local: Vector3, idle := 0.0) -> float:
	var wp := root.global_transform * local
	var best: Node2D = null
	var bd := 700.0 * 700.0
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var d := e.global_position.distance_squared_to(Vector2(wp.x, wp.z))
		if d < bd:
			bd = d
			best = e
	if best == null:
		return idle
	var ang := (best.global_position - Vector2(wp.x, wp.z)).angle() - p.heading
	return -ang


# ---------- объекты биома ----------

## Верх объектов не ближе 30 px к плоскости боя (запас на крен и толщину моделей)
const OBJ_TOP := -30.0
## B-26: столовая гора-картинка не нужна — горы теперь настоящие;
## B-41: скалы-картинки заменены группами моделей (biome_props.gd)
const OBJ_SKIP_3D := ["o_mesa", "o_rocks_big", "o_rocks_small"]
var _wreck_plane: PackedScene = load("res://models/biome/b11_wreck_plane.glb") if ResourceLoader.exists("res://models/biome/b11_wreck_plane.glb") else null

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
			var gy := terrain.surface_fast(o["pos"].x, o["pos"].y).y
			if o["name"] in ["o_fort", "o_village", "o_oasis"]:
				# 3.4-t1 (п. 25): крепость и кишлак — объёмные постройки, а не выдавленная картинка;
				# тест 3.5-s4 (п. 17): и оазис — дома, пруд и огороды вместо круглой картинки, зелень — на земле
				var sz := float(o["size"])
				var vr: int = o.get("var", absi(hash(key)) % 4)
				match o["name"]:
					"o_fort": mi.mesh = AdobeBuild.fort()
					"o_village": mi.mesh = AdobeBuild.village(vr)
					_: mi.mesh = AdobeBuild.oasis(vr)
				mi.material_override = AdobeBuild.material()
				mi.position = Vector3(o["pos"].x, gy - sz * 0.01, o["pos"].y)
				mi.basis = Basis(Vector3.UP, -float(o["rot"])).scaled(Vector3(sz, sz, sz))
				add_child(mi)
				_objs[key] = mi
				continue
			if o["name"] == "o_wreck" and _wreck_plane != null:
				# тест 3.5-s4 (п. 18): обломки — объёмный остов (tools/blender/plane_wreck.py), лежит по склону;
				# земля под ним не выравнивается (раньше — выдавленная картинка в круглой площадке)
				var sw := float(o["size"])
				var e := sw * 0.35
				var px: float = o["pos"].x
				var pz: float = o["pos"].y
				var nrm := Vector3(terrain.surface_fast(px - e, pz).y - terrain.surface_fast(px + e, pz).y, 2.0 * e,
					terrain.surface_fast(px, pz - e).y - terrain.surface_fast(px, pz + e).y).normalized()
				var wn: Node3D = _wreck_plane.instantiate()
				wn.position = Vector3(px, gy - sw * 0.01, pz)
				wn.basis = (Basis(Quaternion(Vector3.UP, nrm)) * Basis(Vector3.UP, -float(o["rot"]))).scaled(Vector3(sw, sw, sw))
				add_child(wn)
				_objs[key] = wn
				mi.free()
				continue
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
	cl.title_on = title.active()
	var its := cl.items()
	# M-31: объёмные облака из клубов (один MultiMesh) — на всех качествах, кроме «Низкого»
	if Settings.gfx >= 1 and Tuning.g("cloud3d") > 0.5:
		for mi0: MeshInstance3D in _clouds:
			mi0.visible = false
		if _puffs == null:
			_puffs = CloudPuffs.new()
			add_child(_puffs)
			_puffs.set_sun(sun.global_transform.basis.z)   # Э-3: свет клубов — от солнца сцены
		_puffs.visible = true
		var focus := Vector3(c2.x, 0.0, c2.y)
		if title.active():   # заставка: растворяются над ведущим звена
			focus = (title._units[0]["node"] as Node3D).global_position
		elif is_instance_valid(m.player):
			focus = Vector3(m.player.global_position.x, 0.0, m.player.global_position.y)
		_puffs.sync(its, cam, c2, h, focus, Settings.gfx, get_process_delta_time())
		_cloud_shadows(cl, its)
		return
	if _puffs != null and _puffs.visible:
		_puffs.hide_all()
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
	_cloud_shadows(cl, its)


## 3.4-t1 (п. 33): тени облаков — в шейдер земли (до 12 ближайших облаков)
func _cloud_shadows(cl: Clouds, its: Array) -> void:
	if _ground_mat == null:
		return
	var arr := PackedVector4Array()
	var texs: Array = cl._tex
	for it in its:
		if arr.size() >= 12:
			break
		var ti := maxi(texs.find(it[3]), 0)
		var gp: Vector2 = it[0]
		var size := float(it[1])
		var inf: Dictionary = _puffs.info(it) if _puffs != null and _puffs.visible else {}
		if not inf.is_empty():
			# M-31: у 3D-облака своя высота (низкие клочья — у самолётов) — тень сдвигается по солнцу
			# от его высоты, а не от общей CLOUD_Y: точка облака P → P − сдвиг × (высота − CLOUD_Y)
			gp -= _cloud_shift_v * (float(inf["h"]) - CLOUD_Y)
			size = float(inf["size"])
		arr.append(Vector4(gp.x, gp.y, size, fposmod(float(it[2]), TAU) + 10.0 * ti))
	while arr.size() < 12:
		arr.append(Vector4.ZERO)
	_ground_mat.set_shader_parameter("clouds", arr)
	_ground_mat.set_shader_parameter("cloud_n", mini(its.size(), 12))
	if not _ground_mat.has_meta("cloud_tex") and texs.size() > 0:
		_ground_mat.set_meta("cloud_tex", true)
		_ground_mat.set_shader_parameter("cloud_a", texs[0])
		_ground_mat.set_shader_parameter("cloud_b", texs[mini(1, texs.size() - 1)])
		_ground_mat.set_shader_parameter("cloud_y", CLOUD_Y)
		var dv := -sun.global_transform.basis.z
		_cloud_shift_v = Vector2(dv.x, dv.z) / dv.y
		_ground_mat.set_shader_parameter("cloud_shift", _cloud_shift_v)   # точка земли → точка облака против луча


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
	# оптимизация (финальный проход 3.5): все пятна — один MultiMesh (один вызов отрисовки вместо
	# до 160); угасание — в цвете экземпляра
	if _scorch_mm == null:
		_scorch_mat.vertex_color_use_as_albedo = true
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _scorch_mesh
		mm.instance_count = 160
		mm.visible_instance_count = 0
		_scorch_mm = MultiMeshInstance3D.new()
		_scorch_mm.multimesh = mm
		_scorch_mm.material_override = _scorch_mat
		_scorch_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_scorch_mm)
	var mmx := _scorch_mm.multimesh
	var n := mini(marks.size(), mmx.instance_count)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in n:
		var mk: Dictionary = marks[i]
		if not mk.has("g3"):
			mk["g3"] = ground_under(mk["p"])
			if _on_water(mk["g3"], float(mk["r"]) * 1.6):   # M-35: копоть на воде не лежит
				mk["life"] = 0.0
		var r: float = mk["r"] * 1.6
		var pos: Vector3 = mk["g3"] + Vector3(0, 0.8, 0)
		mmx.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(r, 1, r)), pos))
		mmx.set_instance_color(i, Color(1, 1, 1, clampf(float(mk["life"]) / 6.0, 0.0, 1.0)))
		lo = lo.min(pos - Vector3(r, 1, r))
		hi = hi.max(pos + Vector3(r, 1, r))
	mmx.visible_instance_count = n
	if n > 0:
		_scorch_mm.custom_aabb = AABB(lo, hi - lo)


# ---------- тест 3.5-s4: падающие бомбы (п. 10) и воронки (п. 14) ----------

## Бомба падает моделью своей ступени: от узла подвески (плоскость боя) по баллистике до той точки
## рельефа, что на экране под точкой разрыва — по горизонтали равномерно, по вертикали с ускорением,
## нос по ходу (опускается к земле), лёгкое покачивание. Без теней — дёшево.
func _sync_bombs(m: Main) -> void:
	var pr := m.projectiles
	if pr == null:
		return
	var seen := {}
	var plen := Tuning.g("plane_len")
	for b: Dictionary in pr.bombs:
		if not b.has("bid"):
			_bid += 1
			b["bid"] = _bid
		var id: int = b["bid"]
		seen[id] = true
		var mi: MeshInstance3D = _bombs3.get(id)
		var vt := int(b.get("vt", 1))
		if mi == null:
			var mesh := WeaponModels.drop_mesh(vt)
			if mesh == null:
				continue
			mi = MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_bombs3[id] = mi
			b["wob"] = randf() * TAU
		# тест 3.5-s5 (п. 3): «rel» — бомба ещё в отсеке (створки открываются, ряд «ковра» уходит по очереди);
		# падение — за оставшееся до разрыва время, место и момент разрыва прежние
		var rel := float(b.get("rel", 0.0))
		var el := float(b["fuse"]) - float(b["t"])
		mi.visible = el >= rel
		var k := clampf((el - rel) / maxf(float(b["fuse"]) - rel, 0.01), 0.0, 1.0)
		var f2: Vector2 = b["from"]
		var y0 := -6.0
		var g3 := ground_under(b["to"])
		var a3 := Vector3(f2.x, y0, f2.y)
		var pos := Vector3(lerpf(a3.x, g3.x, k), lerpf(y0, g3.y, k * k), lerpf(a3.z, g3.z, k))
		var vel := Vector3(g3.x - a3.x, (g3.y - y0) * 2.0 * maxf(k, 0.12), g3.z - a3.z)
		var fwd := vel.normalized() if vel.length() > 0.01 else Vector3.DOWN
		var ref := Vector3.UP if absf(fwd.y) < 0.95 else Vector3(0, 0, -1)
		var zx := fwd.cross(ref).normalized()
		var bs := Basis(fwd, zx.cross(fwd), zx)
		var w := float(b["wob"]) + k * 14.0
		bs = bs * Basis(Vector3.BACK, 0.07 * sin(w)) * Basis(Vector3.UP, 0.06 * sin(w * 1.3 + 1.0)) * Basis(Vector3.RIGHT, 0.4 * k)
		var ln := plen * float(WeaponModels.DROP_LEN[clampi(vt, 1, 4)])
		mi.global_transform = Transform3D(bs.scaled(Vector3(ln, ln, ln)), pos)
	for id in _bombs3.keys():
		if not seen.has(id):
			(_bombs3[id] as Node).queue_free()
			_bombs3.erase(id)


## Воронки: плоский квадрат по наклону рельефа с общей текстурой и материалом (без теней, без света),
## размер с поправкой на перспективу — на экране совпадает с зоной разрыва; в конце жизни плавно гаснет
func _sync_craters(m: Main) -> void:
	if m.fx == null or not is_instance_valid(m.fx.ground):
		return
	var list: Array = m.fx.ground.craters
	if _crater_mat == null:
		_crater_mat = StandardMaterial3D.new()
		_crater_mat.albedo_texture = Fx.crater_tex()
		_crater_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_crater_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_crater_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_crater_mat.render_priority = -1   # под пятнами копоти и взрывами
		_crater_mesh = PlaneMesh.new()
		_crater_mesh.size = Vector2(2, 2)
	# как пятна копоти: все воронки — один MultiMesh (один вызов отрисовки), угасание — в цвете экземпляра
	if _crater_mm == null:
		_crater_mat.vertex_color_use_as_albedo = true
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _crater_mesh
		mm.instance_count = 48
		mm.visible_instance_count = 0
		_crater_mm = MultiMeshInstance3D.new()
		_crater_mm.multimesh = mm
		_crater_mm.material_override = _crater_mat
		_crater_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_crater_mm)
	var mmx := _crater_mm.multimesh
	var cnt := mini(list.size(), mmx.instance_count)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in cnt:
		var c: Dictionary = list[i]
		if not c.has("xf"):
			var g := ground_under(c["p"])
			var ch := cam.global_position.y
			var r: float = float(c["r"]) * clampf((ch - g.y) / maxf(ch, 1.0), 0.5, 3.0)
			var n := Vector3.UP
			if terrain != null:
				var d := maxf(r * 0.5, 6.0)
				n = Vector3(terrain.surface_fast(g.x - d, g.z).y - terrain.surface_fast(g.x + d, g.z).y, 2.0 * d,
					terrain.surface_fast(g.x, g.z - d).y - terrain.surface_fast(g.x, g.z + d).y).normalized()
			var rot := float(c["rot"])
			var x0 := Vector3(cos(rot), 0.0, sin(rot))
			var xa := (x0 - n * x0.dot(n)).normalized()
			var za := xa.cross(n)
			c["xf"] = Transform3D(Basis(xa * r, n, za * r), g + n * maxf(1.5, r * 0.12))   # над изгибом склона
			c["rr"] = r
			if _on_water(g, r):   # M-35: бомба в реке воронки не оставляет
				c["life"] = 0.0
		var xf: Transform3D = c["xf"]
		var rr := float(c["rr"])
		mmx.set_instance_transform(i, xf)
		mmx.set_instance_color(i, Color(1, 1, 1, clampf(float(c["life"]) / Fx.FxGround.CRATER_FADE, 0.0, 1.0)))
		lo = lo.min(xf.origin - Vector3(rr, rr, rr))
		hi = hi.max(xf.origin + Vector3(rr, rr, rr))
	mmx.visible_instance_count = cnt
	if cnt > 0:
		_crater_mm.custom_aabb = AABB(lo, hi - lo)

