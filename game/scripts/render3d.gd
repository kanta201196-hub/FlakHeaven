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
## B-26: the ground is ground_depth below the combat plane; 900 px since 25.10 (Kanta: planes felt like they hug the ground at 500)
var GROUND_Y := -900.0
const CLOUD_Y := 380.0       # облака между камерой и самолётами
const ON := true

static var I: Render3D
static var enabled := true
## World area worth drawing this frame: the 3D view (with its margin) plus the 2D screen and the
## tilted combat layer, both grown by ENEMY_DRAW_MARGIN. Enemies outside skip their _draw (Enemy.in_draw_view). Empty until the first
## battle frame, which means «draw everything».
static var view_now := Rect2()
## Reach of the longest 2D enemy overlay past the screen edge (bomber tail sector 620 px, heli aim fan 520 px)
const ENEMY_DRAW_MARGIN := 800.0

var cam: Camera3D
var sun: DirectionalLight3D
var terrain: Terrain3D
var _ground_mat: ShaderMaterial
var _env: Environment   # тред «Второй биом»: цвет фона под биом
## Story scenes (step 2): time-of-day presets over the default light. Colours are multipliers and sun colours,
## so one table serves both renderers (the Forward+ exposure lift stays in `_light_base`). "day" = the default.
const SUN_COLOR := Color(1.0, 0.9, 0.76)
const SUN_ENERGY := 1.15
const SUN_DIR := Vector3(0.62, -0.85, 0.75)
const LIGHT_PRESETS := {
	"day": {"sun": SUN_COLOR, "energy": 1.0, "dir": SUN_DIR, "exposure": 1.0, "ambient": 1.0, "bg": Color(1, 1, 1)},
	"dawn": {"sun": Color(1.0, 0.74, 0.52), "energy": 0.85, "dir": Vector3(0.9, -0.42, 0.55), "exposure": 0.9, "ambient": 0.8, "bg": Color(0.95, 0.8, 0.7)},
	"dusk": {"sun": Color(1.0, 0.6, 0.42), "energy": 0.75, "dir": Vector3(-0.85, -0.38, 0.6), "exposure": 0.8, "ambient": 0.7, "bg": Color(0.85, 0.6, 0.55)},
	"night": {"sun": Color(0.55, 0.65, 0.95), "energy": 0.3, "dir": Vector3(0.3, -0.9, 0.4), "exposure": 0.55, "ambient": 0.5, "bg": Color(0.35, 0.4, 0.6)},
}
var _light_base := {}
var _light_tw: Tween
var light_preset := "day"
var _units: Dictionary[int, Unit3D] = {}   # instance_id → its 3D unit
var _objs := {}       # ключ клетки → MeshInstance3D (у обломков o_wreck — сцена модели)
var _clouds: Array = []          # «Низкое» качество: прежние плоские облака
var _puffs: CloudPuffs           # M-31: объёмные облака из клубов (остальные качества)
var _cloud_shift_v := Vector2.ZERO
var _scorch_mm: MultiMeshInstance3D
var _scorch_mesh: QuadMesh
var _scorch_mat: StandardMaterial3D
var _crater_mm: MultiMeshInstance3D   # тест 3.5-s4 (п. 14): воронки от бомб (FxGround.craters), один MultiMesh
var _crater_mat: StandardMaterial3D
## VFX-06: Forward+ decal pools for scorch marks and craters (see marks_as_decals)
var _scorch_decals: Array[Decal] = []
var _scorch_decal_tex: Texture2D
var _crater_decals: Array[Decal] = []
var _crater_mesh: PlaneMesh
var _bombs3 := {}                  # тест 3.5-s4 (п. 10): падающие бомбы — номер → MeshInstance3D
var _bid := 0
var _flash_mat: Material        # hit flash over a 3D enemy model (_unit_overlay)
var _boss_flash_mat: Material   # hit flash of a boss: it is under steady fire, so it stays weak
var _elite_mat: Material        # elite enemy: gold tint
var _zoom := 1.0
var _c2 := Vector2.ZERO        # центр кадра на плоскости боя (для указателей за краем экрана)
var _shadow_shader: Shader
var _trails: Contrails       # 3.4-t1 (п. 10, 34): инверсионные следы самолётов и ракет
var _wakes: SeaWakes         # S10-10: кильватерный след судов «Архипелага» на воде
var _tid := 0                # номера ракет для их следов
var _eshot_mm: MultiMeshInstance3D   # тест 3.5-s5 (п. 11): ракеты врагов — модели
var _eglow_mm: MultiMeshInstance3D   # и светящиеся точки: трассеры пуль, ореол и факел ракет
var _fx_clear := Vector4.ZERO   # last value sent to the fx_clear shader global (_sync_fx_clear)
var _crashes: Array = []     # 3.4-t1 (п. 32): сбитые ведомые падают
var _wrecks: Array = []      # и остаются обломками на земле
var _wreck_mat: Material
var _burnt_sprite_mat: StandardMaterial3D   # остов без 3D-модели (картинка): тёмная заливка, как раньше
var _smoke_mat: Material
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


var _prewarm_id := -1   # задача AdobeBuild.prewarm: забрать при выходе (пул не держит её и не обрывает)


## S9-07/S9-08: кишлак на месте (AdobeBuild.village_at, 20–40 мс) — в фоне, за клетку до появления: клетка → задача
var _vtasks := {}


## Forward+ exposure gain, saturation, contrast and sky fill that bring its frame to the Compatibility
## look (see _ready): there shadows came out lighter and the frame flatter
const FP_EXPOSURE_K := 1.5
const FP_SATURATION := 1.05
const FP_CONTRAST := 1.18
const FP_AMBIENT := 0.38


## Tweens the sun and environment to a preset of LIGHT_PRESETS over `dur` s; unknown names mean "day".
## Scenes call it on start and `set_light("day")` on end; the sortie itself always runs in "day".
func set_light(preset: String, dur := 1.0) -> void:
	if not LIGHT_PRESETS.has(preset):
		preset = "day"
	if preset == light_preset or _env == null or sun == null or _light_base.is_empty():
		return
	light_preset = preset
	var p: Dictionary = LIGHT_PRESETS[preset]
	if _light_tw != null and _light_tw.is_valid():
		_light_tw.kill()
	_light_tw = create_tween().set_parallel(true)
	_light_tw.tween_property(sun, "light_color", p["sun"] as Color, dur)
	_light_tw.tween_property(sun, "light_energy", SUN_ENERGY * float(p["energy"]), dur)
	_light_tw.tween_property(_env, "tonemap_exposure", float(_light_base["exposure"]) * float(p["exposure"]), dur)
	_light_tw.tween_property(_env, "ambient_light_energy", float(_light_base["ambient"]) * float(p["ambient"]), dur)
	_light_tw.tween_property(_env, "background_color", (_light_base["bg"] as Color) * (p["bg"] as Color), dur)
	var target := Basis.looking_at((p["dir"] as Vector3).normalized(), Vector3(0, 0, -1))
	_light_tw.tween_method(func(u: float) -> void: sun.basis = sun.basis.slerp(target, u).orthonormalized(), 0.0, 1.0, dur)


func _exit_tree() -> void:
	if _prewarm_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_prewarm_id)
		_prewarm_id = -1
	for key in _vtasks:
		WorkerThreadPool.wait_for_task_completion(_vtasks[key])
	_vtasks.clear()


func _ready() -> void:
	I = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = Tuning.g("render3d") > 0.5
	if enabled:   # 3.5-s8: кишлак-городок собирается 0,15–0,4 с — заранее в фоне, без рывка при появлении
		_prewarm_id = WorkerThreadPool.add_task(AdobeBuild.prewarm, false, "AdobeBuild.prewarm")
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
	# Forward+ only settings in one place (agreed between the effects and 3D-models threads, 24.10): Compatibility
	# keeps today's look. VFX-01: HDR glow, so fire, flashes and tracers above 1.0 bloom; tonemap stays as above.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		# Forward+ switch (24.10): linear lighting draws the same scene darker and flatter than Compatibility
		# (frame means 18-22 % lower, contrast a quarter lower on the --visual bench), so they are lifted to match
		e.tonemap_exposure = Tuning.g("light_exposure") * FP_EXPOSURE_K
		e.adjustment_saturation = FP_SATURATION
		e.adjustment_contrast = FP_CONTRAST
		e.ambient_light_energy = FP_AMBIENT
		e.glow_enabled = true
		e.glow_intensity = 0.9
		e.glow_bloom = 0.0
		e.glow_hdr_threshold = 1.0
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.environment = e
	_env = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 4000.0
	sun.shadow_bias = 0.05
	# 3.4-t1 (п. 18): тени уступов на склонах были почти чёрными полосами — свет неба их подсвечивает
	sun.shadow_opacity = 0.8
	# B-24: солнце ниже (~40° над горизонтом) — тени длиннее, у объектов видна теневая сторона.
	# Свет сверху-слева (на экране): тени уходят вниз-вправо
	sun.basis = Basis.looking_at(SUN_DIR.normalized(), Vector3(0, 0, -1))
	add_child(sun)
	_light_base = {"exposure": e.tonemap_exposure, "ambient": e.ambient_light_energy, "bg": e.background_color}

	_setup_combat_layer()

	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 10.0
	cam.far = 9000.0   # a deeper ground (ground_depth) with the tilted camera and the zoomed-out boss view
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
	_flash_mat = _unit_overlay(OVERLAY_FLASH)
	_boss_flash_mat = _unit_overlay(OVERLAY_BOSS_FLASH)
	_elite_mat = _unit_overlay(OVERLAY_ELITE)
	_wreck_mat = _make_burnt_mat()   # S10-07: остов самолёта — закопчённый металл, а не чёрная заливка
	_trails = Contrails.new()
	add_child(_trails)
	_wakes = SeaWakes.new()
	add_child(_wakes)
	title = TitleFlight.new(self)
	add_child(title)
	apply_gfx()


## T4-04: «Качество графики».
## 3.5 (правка 7): в 3.4 пресеты меняли только тени — на слабом ноутбуке разницы не было. Теперь:
##   Низкое — 3D-картинка в 60% разрешения, слой боя до 1400 пикс., рельеф реже (сетка 40), модели биома
##            без теней и мелочи вдвое реже, тени грубее (атлас 1024);
##   Среднее — 80% разрешения, слой боя до 2000, сетка рельефа 56, мелкие модели без теней, атлас 2048;
##   Высокое — как было; Максимальное — + сглаживание MSAA 2×.
## Деревья полной детализации (11–14 тыс. треуг.) — только на «Максимальном» (BiomeProps).
## Правка 16: дальность теней теперь по видимой земле (углы кадра), а не по пресету — тень не обрывается
## полосой посреди экрана при наклоне камеры; грубость слабых пресетов — размером атласа.
## UI-01 step 3: each part of «Качество графики» is its own option (GfxPresets); the presets
## keep the numbers above. Shadow soft-filter levels per GfxPresets.SHADOWS_* (off → no sun shadow).
const SHADOW_FILTER := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD,
	RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH]
## «Дальность теней»: «Ближе» covers this share of the visible ground
const SHADOW_NEAR := 0.6
## Combat layer size cap (px) follows the render scale: 60 % → 1400, 80 % → 2000, 100 % → 2600
var _combat_max := 2600.0
var _shadow_k := 1.0
## Terrain and props levels the current terrain chunks were built with (rebuild only on change)
var _built := Vector2i(-1, -1)


## Applies every graphics option (Settings.gopt: values the renderer can draw). Light, shadows,
## antialiasing and render scale change at once; terrain and props rebuild only when theirs change.
func apply_gfx() -> void:
	var vp := get_viewport()
	var sh := Settings.gopt("shadows")
	# в GL Compatibility без теней солнца кадр темнее и рыжее (замер стенда: яркость 104 против 144) — там «Выкл» недоступно
	sun.shadow_enabled = sh != GfxPresets.SHADOWS_OFF
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER[sh])
	RenderingServer.directional_shadow_atlas_set_size(GfxPresets.SHADOW_RES[Settings.gopt("shadow_res")], true)
	_shadow_k = 1.0 if Settings.gopt("shadow_dist") == 1 else SHADOW_NEAR
	var aa := Settings.gopt("aa")
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
		Viewport.MSAA_8X, Viewport.MSAA_DISABLED][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == GfxPresets.AA_FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == GfxPresets.AA_TAA
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][Settings.gopt("upscale")]
	var pct: int = GfxPresets.SCALES[Settings.gopt("scale")]
	vp.scaling_3d_scale = pct / 100.0
	_combat_max = 1400.0 + (pct - 60) * 30.0
	if _env != null and Settings.forward_plus():
		var ao := Settings.gopt("ssao")
		_env.ssao_enabled = ao > 0
		if ao > 0:
			RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
				RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][ao], true, 0.5, 2, 50.0, 300.0)
		_env.ssil_enabled = Settings.gopt("ssil") > 0
		_env.glow_enabled = Settings.gopt("glow") > 0
	var t := Settings.gopt("terrain")
	if _ground_mat != null:   # M-36: скала с трёх проекций — только «Высокое» и «Максимальное»
		_ground_mat.set_shader_parameter("rock_tri", t >= 2)
	var built := Vector2i(t, Settings.gopt("props"))
	if terrain != null and built != _built:
		terrain.clear()   # куски рельефа пересоберутся с новыми моделями биома и сеткой
	_built = built


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
	sun.directional_shadow_max_distance = clampf((far * 1.1 + 300.0) * _shadow_k, 1500.0, 12000.0)


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
## World area the tilted combat layer shows this frame (empty while the camera looks straight down)
var _combat_rect := Rect2()


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
	var k := minf(1.0, minf(COMBAT_VP_MAX, _combat_max) / maxf(px.x, px.y))
	var size := Vector2i(maxi(16, int(px.x * k)), maxi(16, int(px.y * k)))
	if _combat_vp.size != size:
		_combat_vp.size = size
	var sc := float(size.x) / r.size.x
	_combat_vp.canvas_transform = Transform2D(0.0, Vector2(sc, sc), 0.0, -r.position * sc)
	_combat_rect = r
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


## VFX-04: player tracers are 3D glow strips (with HDR bloom) instead of lines on the 2D combat layer; Forward+ only,
## Compatibility keeps the 2D lines it was tuned with
func tracers_3d() -> bool:
	return enabled and GpuFx.active()


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
		terrain.clear()   # сначала дождаться фоновых кусков: set_biome меняет поля, которые читает поток
		_apply_biome()
	var half_g := vs / zoom * 0.5 * ((h - GROUND_Y) / h) + Vector2(700, 700)
	_set_tilt_mode(tilt > 0.001, m)
	if _tilt_on:
		_sync_combat_layer()
	var view_g := Rect2(c2 - half_g, half_g * 2.0)
	if tilt > 0.001:
		# с наклоном видно дальше вперёд (вверх по экрану)
		view_g = view_g.grow_individual(half_g.x * tilt, half_g.y * tilt * 3.0, half_g.x * tilt, 0.0)
	var screen := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	view_now = view_g.merge(screen.grow(ENEMY_DRAW_MARGIN))
	if _tilt_on and _combat_rect.has_area():
		# with the camera tilted the 2D world is shown through the combat layer, which reaches
		# farther up the screen than the 2D camera's own rect
		view_now = view_now.merge(_combat_rect.grow(ENEMY_DRAW_MARGIN))
	var pt := Time.get_ticks_usec() if Perf.on else 0
	terrain.sync(view_g, 64 if terrain._chunks.is_empty() else 1, _screen_ground(vs))
	_fit_shadow()
	if Perf.on: pt = Perf.sub("r3d.terrain", pt)
	var sd := 0.0 if get_tree().paused else delta   # время эффектов стоит на паузе
	_sync_units(m, delta, sd)
	_sync_fx_clear(m, vs)
	if Perf.on: pt = Perf.sub("r3d.units", pt)
	_sync_missiles(m)
	_sync_enemy_shots(m)
	if Perf.on: pt = Perf.sub("r3d.missiles", pt)
	var ct0 := pt
	_sync_crashes(m, sd)
	if Perf.on: ct0 = Perf.sub("r3d.c.crashes", ct0)
	title.sync((m.state in ["menu", "settings"] and m.menu != null and m.menu.back_state == "menu") or Cutscene.flight_on(), delta)
	_trails.tick(delta if title.active() else sd)   # в меню мир на паузе, а следы звена тают в реальном времени
	if Perf.on: Perf.sub("r3d.c.trails", ct0)
	_wakes.tick(sd)
	if Perf.on: pt = Perf.sub("r3d.crash_trails", pt)
	_sync_objects(c2, h)
	if Perf.on: pt = Perf.sub("r3d.objects", pt)
	_sync_clouds(m, c2, h)
	_sync_scorch(m)
	_sync_craters(m)
	_sync_bombs(m)
	_sync_ground_zones(m)
	_sync_lights(delta)
	if Perf.on: pt = Perf.sub("r3d.clouds_scorch_lights", pt)
	if OS.get_cmdline_user_args().has("--dbg3") and Engine.get_process_frames() % 30 == 0:
		var pp := m.player.global_position if is_instance_valid(m.player) else Vector2.ZERO
		print("R3D c2=", c2, " ct=", get_viewport().get_canvas_transform(), " cam=", cam.global_position, " zoom=", m.camera.zoom, " player=", pp, " units=", _units.size(), " objs=", _objs.size())
		for id in _units:
			var u: Unit3D = _units[id]
			if u.kind == "player":
				print("  P ", (u.node as Node3D).global_transform, " k=", u.k)


# ---------- самолёты и наземные цели ----------

## Overlay over an enemy's 3D model (S11-24, S11-29): [Forward+ multiplier, Compatibility colour and alpha].
## Compatibility draws a see-through unshaded fill, as tuned before the Forward+ switch. On Forward+ that
## fill flooded the enemies' dark paint in the linear HDR frame (elite drones flat yellow, the Fortress
## under fire flat white), so there the model's own colour is multiplied (shaders/unit_tint.gdshader):
## paint, shading and markings stay. A boss is under steady fire, so its hit flash is on almost every
## frame: it only lightens the paint a little.
const OVERLAY_FLASH := [Vector3(2.4, 2.4, 2.4), Color(1.0, 1.0, 1.0, 0.75)]
const OVERLAY_BOSS_FLASH := [Vector3(1.3, 1.3, 1.3), Color(1.0, 1.0, 1.0, 0.3)]
const OVERLAY_ELITE := [Vector3(1.55, 1.2, 0.5), Color(1.0, 0.75, 0.2, 0.28)]


## Overlay material for enemy 3D models from one of the OVERLAY_* pairs, for the renderer in use.
func _unit_overlay(pair: Array) -> Material:
	if Settings.forward_plus():
		var t := ShaderMaterial.new()
		t.shader = preload("res://shaders/unit_tint.gdshader")
		t.set_shader_parameter("k", pair[0])
		return t
	var m := StandardMaterial3D.new()
	m.albedo_color = pair[1]
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _unit_mesh(tex: Texture2D, length_px: float, thick: float, grid: int) -> Dictionary:
	var mesh := ReliefMesh.build(tex, tex.get_width() * thick, grid)
	return {"mesh": mesh, "mat": ReliefMesh.material(tex), "k": length_px / float(tex.get_width())}


## 3.5: бой на 3D-моделях (решение 14.10, подтверждено владельцем 16.10). Облегчённая модель
## models/battle/fh_battle_<картинка>.glb (tools/blender/battle_lod.py из модели ангара); длина модели 1 =
## ширина картинки, нос +X — те же оси, что у рельефа из спрайта, поэтому подвесы, сопла и следы на месте.
## Used on every graphics preset, «Низкое» included: a sprite relief looks flat next to the 3D
## world. The battle model is already the cheap LOD (~9k triangles, 1K textures; the player planes baked from
## the hangar models by battle_bake.py carry 30–36k, Godot's import LODs thin them with distance); no lighter one
## exists. Returns null only when the picture has no GLB: then ReliefMesh is the fallback (VIS-01).
func _battle_model(tex: Texture2D) -> PackedScene:
	# оптимизация: кэш по самой картинке — без сборки пути каждый кадр у каждого самолёта
	var hit = _bm_cache.get(tex)
	if hit != null or _bm_cache.has(tex):
		return hit
	var path := "res://models/battle/fh_battle_%s.glb" % tex.resource_path.get_file().get_basename()
	_bm_cache[tex] = load(path) if ResourceLoader.exists(path) else null
	return _bm_cache[tex]


var _bm_cache := {}


## Whether the battle model for `tex` can be used this frame without blocking. The first enemy of a type
## used to load its GLB on the main thread (15–350 ms freeze in a fight); now the load runs in the
## background and the new enemy, still off screen where it spawns, waits a few frames for its model.
func _battle_model_ready(tex: Texture2D) -> bool:
	if _bm_cache.has(tex):
		return true
	var path := "res://models/battle/fh_battle_%s.glb" % tex.resource_path.get_file().get_basename()
	if not ResourceLoader.exists(path):
		_bm_cache[tex] = null
		return true
	match ResourceLoader.load_threaded_get_status(path):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
		ResourceLoader.THREAD_LOAD_LOADED:
			_bm_cache[tex] = ResourceLoader.load_threaded_get(path)
			return true
		ResourceLoader.THREAD_LOAD_FAILED:
			return true   # _battle_model() tries the ordinary load and reports the error
	ResourceLoader.load_threaded_request(path)
	return false
## M-37 (Kanta 18.10): высота модели к её длине ближе к настоящей — при наклоне камеры 28–45° высокая модель
## «встаёт» над землёй и кажется крупнее. Бункер Meshy вдвое выше настоящего укрытия с обваловкой (0,8 длины
## против ~0,3), у РЛС антенна на мачте ~1 длины против ~0,8. Сжатие только по вертикали; у РЛС ось вращения
## антенны вертикальная — сжатие её не перекашивает. ЗСУ и ЗРК в норме (подъём контейнеров ЗРК так не исказится).
## Тест 3.5-s8: бункер и РЛС пересобраны кодом (tools/blender/ground_models.py) сразу в настоящей высоте —
## сжатие не нужно (бункер ~0,25 длины с колпаком, РЛС ~0,55 с зеркалом). Таблица остаётся для будущих моделей.
const MODEL_H := {}


## Для лога: (самолётов-моделей в бою, их треугольников всего)
func model_units() -> Vector2:
	var n := 0
	var t := 0
	for id in _units:
		var u: Unit3D = _units[id]
		if u.bm != null:
			n += 1
			if u.tris < 0:
				u.tris = (u.mi as MeshInstance3D).mesh.get_faces().size() / 3
			t += int(u.tris)
	return Vector2(n, t)


func _ensure(id: int, kind: String, tex: Texture2D, length_px: float, thick: float, grid := 56) -> Unit3D:
	var u: Unit3D = _units.get(id)
	var bm: PackedScene = _battle_model(tex)   # 3.5 этап 2: враги в воздухе и наземные ПВО (ЗСУ, ЗРК, РЛС)
	if u == null or u.tex != tex or u.bm != bm:
		var nt := Time.get_ticks_usec() if Perf.on else 0
		if u != null:
			(u.node as Node).queue_free()
		var pooled := _pool_take(tex, kind, thick, bm)
		if pooled != null:
			pooled.k = length_px / float(tex.get_width())
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
			# the hull mesh carries the hit flash and the elite tint: propellers (prop_*) come first in the
			# transport and drone GLBs, and a flash on a propeller alone is not seen
			for c in inst.find_children("*", "MeshInstance3D", true, false):
				if not String(c.name).begins_with("prop_"):
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
		u = Unit3D.new()
		u.node = root
		u.mi = mi
		u.kind = kind
		u.tex = tex
		u.k = d["k"]
		u.bm = bm
		if bm != null and kind == "player":   # Т-3: модули прокачки на модели (до механизации — мерится чистый корпус)
			u.modp = ModuleParts.attach(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
		if bm != null and kind in ["player", "wing"]:   # Т-1: предкрылки и закрылки своих самолётов
			u.mech = WingMech.attach(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
			# Т-2: отличие «Грача 2» сверху (ПГО, контейнеры на законцовках)
			u.detail = WingMech.attach_detail(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
			# V-07: свои знаки на крыльях, киле и (у асов) на борту
			u.ins = Insignia.attach(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename(), kind)
			if kind == "player":   # Т-5: створки бомбоотсека «Кита»
				u.bay = WingMech.attach_bay(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
				u.tail = WingMech.attach_tail(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
				_apply_livery(root.get_child(0) as Node3D, tex)
		if kind == "enemy" and thick > 0.06:
			u.shb = tex   # оптимизация: тени врагов одного вида — один MultiMesh (_flush_shadows)
		elif kind != "enemy":   # у наземных целей (thick 0.05) тень настоящая
			u.sh = _make_shadow(tex, root)
		if kind != "enemy":
			PlaneFx.attach(u, tex)
		_units[id] = u
		if Perf.on:
			Perf.peak("r3d.new_model_max", Perf.sub("r3d.new_model", nt) - nt)
	u.seen = true
	return u


## Тест 3.5-s4, п. 35: окраска своего самолёта из ангара (ведомые — в своей, с полосами звена)
func _apply_livery(model: Node3D, tex: Texture2D) -> void:
	var key := tex.resource_path.get_file().get_basename()   # «fighter_1»
	var cls := key.get_slice("_", 0)
	Livery.apply(model, cls, int(key.get_slice("_", 1)), Livery.current(cls))


func _place(u: Unit3D, p: Vector2, heading: float, bank: float, roll: float, y := 0.0, scale_k := 1.0, pitch := 0.0) -> void:
	var root: Node3D = u.node
	var q := p
	if u.has_alt:
		# самолёт выше или ниже плоскости боя — на луче камеры через точку p: на экране он там же,
		# где его пули и хитбокс, а высоту видно по размеру и по рельефу под ним
		q = _on_ray(p, y)
	var b := Basis(Vector3.UP, -heading) * Basis(Vector3.BACK, pitch) * Basis(Vector3.RIGHT, bank + roll)
	var k: float = u.k * scale_k
	# one transform write: each write re-sends the transform of every mesh in the model to the renderer
	root.transform = Transform3D(b.scaled(Vector3(k, k, k)), Vector3(q.x, y, q.y))
	if u.sh != null or u.shb != null:
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
## плюс запас relief_clear, в пределах relief_up / relief_down от плоскости боя. Returns the height;
## the nose pitch to draw is left in `u.pitch` (an Array per call was a big-fight allocation per plane).
func _relief_alt(u: Unit3D, p: Vector2, fwd: Vector2, look: float, delta: float) -> float:
	_frame_tuning()
	var alt: float = u.alt
	if terrain == null or not _ft_relief:
		u.has_alt = true
		u.alt = move_toward(alt, 0.0, delta * 60.0)
		u.pitch = 0.0
		return u.alt
	# высоту рельефа считаем не каждый кадр (дорого для сотни врагов): игрок — каждый кадр,
	# остальные — раз в ~0,25 с, вразнобой
	var target: float = u.alt_to
	var next: float = float(u.alt_next) - delta
	if next <= 0.0 or u.kind == "player":
		next = randf_range(0.2, 0.3)
		var top := terrain.surface_fast(p.x, p.y).y
		if look > 0.0:
			for f: float in [0.5, 1.0]:
				var a: Vector2 = p + fwd * look * f
				top = maxf(top, terrain.surface_fast(a.x, a.y).y)
		target = clampf(top + _ft_relief_clear, -_ft_relief_down, _ft_relief_up)
		u.alt_to = target
	u.alt_next = next
	var nw := lerpf(alt, target, 1.0 - exp(-delta * _ft_relief_rate))
	u.has_alt = true
	u.alt = nw
	# нос вверх при наборе, вниз при снижении (сглажено, не больше ~15°)
	var vy := (nw - alt) / maxf(delta, 0.001)
	var pt := clampf(atan2(vy, 400.0), -0.26, 0.26)
	u.pitch = lerpf(u.pitch, pt, 1.0 - exp(-delta * 5.0))
	return nw


## Sliders and the sun direction the per-unit code reads, refreshed once a frame: with 60+ planes
## the Tuning lookups alone were several hundred a frame.
var _ft_frame := -1
var _ft_relief := false
var _ft_relief_clear := 0.0
var _ft_relief_down := 0.0
var _ft_relief_up := 0.0
var _ft_relief_rate := 0.0
var _ft_shadow := false
var _ft_shadow_off := 0.0
var _ft_shadow_size := 0.0
var _ft_shadow_alpha := 0.0
var _ft_sun := Vector3.DOWN


## Refreshes the _ft_* copies on the first call in a process frame.
func _frame_tuning() -> void:
	var fr := Engine.get_process_frames()
	if fr == _ft_frame:
		return
	_ft_frame = fr
	_ft_relief = Tuning.g("relief_follow") >= 0.5
	_ft_relief_clear = Tuning.g("relief_clear")
	_ft_relief_down = Tuning.g("relief_down")
	_ft_relief_up = Tuning.g("relief_up")
	_ft_relief_rate = Tuning.g("relief_rate")
	_ft_shadow = Tuning.g("plane_shadow") > 0.5
	_ft_shadow_off = Tuning.g("shadow_off")
	_ft_shadow_size = Tuning.g("shadow_size")
	_ft_shadow_alpha = Tuning.g("shadow_alpha")
	_ft_sun = -sun.global_transform.basis.z if sun != null else Vector3.DOWN


## Тест 3.5-s7: нижняя граница для самолёта игрока — самая высокая точка земли под ним и вокруг
## (на полкорпуса во все стороны: крыло в крене и склон между камерой и самолётом) плюс relief_min.
## В нырке над горами самолёт идёт ниже, но в склон не уходит.
func _ground_floor(p: Vector2, r: float) -> float:
	if terrain == null or Tuning.g("relief_follow") < 0.5:
		return -INF
	var top := terrain.surface_fast(p.x, p.y).y
	for o: Vector2 in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		top = maxf(top, terrain.surface_fast(p.x + o.x, p.y + o.y).y)
	return top + Tuning.g("relief_min")


## Биом нового мира (Biome.cur(), тред «Второй биом»): поле берега у рельефа, вода и дороги в шейдере земли
func _apply_biome() -> void:
	terrain.set_biome()
	var sea := Biome.sea()
	_ground_mat.set_shader_parameter("sea", sea)
	_ground_mat.set_shader_parameter("sea_w", Terrain3D.SEA_W)
	_ground_mat.set_shader_parameter("shore_a", Terrain3D.SHORE_A)
	_ground_mat.set_shader_parameter("sea_depth_px", float(Biome.g("depth_px", 450.0)))
	var look := 5   # S10-06: 5 — вид 4 с мелкими волнами, бликами и каустикой (замечание Kanta 23.10). E-13: вид воды 3 (прозрачная отмель) — выбор Kanta 21.10; 4 — тот же вид с берегом по фото Kanta 21.10
	for arg in OS.get_cmdline_user_args():   # сравнение вариантов воды на кадрах: --sealook=0…3
		if arg.begins_with("--sealook="):
			look = int(arg.substr(10))
	_ground_mat.set_shader_parameter("sea_look", look)
	_ground_mat.set_shader_parameter("road_w", 0.0 if sea else Terrain3D.ROAD_W)   # дороги нет: конвой — по фарватеру
	_ground_mat.set_shader_parameter("road_w_in", 0.0 if sea else Terrain3D.ROAD_W_IN)
	for k in (Biome.g("ground", {}) as Dictionary):
		_ground_mat.set_shader_parameter(k, Biome.g("ground")[k])
	if _env != null:
		_env.background_color = Biome.g("bg", Color(0.52, 0.47, 0.4))


func _setup_plane_shadows() -> void:
	_psh_vp = SubViewport.new()
	_psh_vp.name = "PlaneShadows"
	var n := 1024 if Settings.gopt("shadow_res") >= 2 else 512
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
	_frame_tuning()
	var on := _ft_shadow and terrain != null
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
func _place_shadow(u: Unit3D, p: Vector2, heading: float, k: float) -> void:
	_frame_tuning()
	var sh: MeshInstance3D = u.sh
	var hi := _ft_shadow and terrain != null
	var cs := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if hi else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# поиск по дереву модели — только при смене режима (раньше каждый кадр у каждого самолёта)
	var n_kids := (u.node as Node3D).get_child_count()
	if u.cs != cs or u.cs_n != n_kids:
		u.cs = cs
		u.cs_n = n_kids
		for c in (u.node as Node3D).find_children("*", "GeometryInstance3D", true, false):
			(c as GeometryInstance3D).cast_shadow = cs
	if sh != null:
		sh.visible = hi
	if not hi:
		return
	# оптимизация (финальный проход 3.5): точку тени на рельефе и наклон склона (8 замеров высоты)
	# у чужих самолётов считаем раз в 4 кадра вразнобой; между замерами тень едет за самолётом
	# с тем же сдвигом — на глаз не отличить, рельеф пологий
	var fr := Engine.get_process_frames()
	if u.kind == "player" or not u.sh_ok or (fr + int(u.sh_f)) % 4 == 0:
		if u.sh_f < 0:
			u.sh_f = randi() % 4
		var d := _ft_sun   # куда светит солнце
		var y := GROUND_Y
		var g := Vector2.ZERO
		var off := _ft_shadow_off
		for i in 3:
			var t := y / d.y
			g = p + Vector2(d.x, d.z) * t * off
			y = terrain.surface_fast(g.x, g.y).y
		var e := 8.0
		u.sh_n = Vector3(terrain.surface_fast(g.x - e, g.y).y - terrain.surface_fast(g.x + e, g.y).y, 2.0 * e,
			terrain.surface_fast(g.x, g.y - e).y - terrain.surface_fast(g.x, g.y + e).y).normalized()
		u.sh_b = Basis(Quaternion(Vector3.UP, u.sh_n))
		u.sh_ok = true
		u.sh_off = g - p
		u.sh_y = y
	var gp: Vector2 = p + u.sh_off
	var s := k * _ft_shadow_size
	var yaw := Basis(Vector3.UP, -heading)
	var xf := Transform3D((u.sh_b * yaw).scaled(Vector3(s, 1.0, s)), Vector3(gp.x, u.sh_y + 3.0, gp.y))
	if sh == null:
		var tx: Texture2D = u.shb
		if not _shb.has(tx):
			_shb[tx] = []
		(_shb[tx] as Array).append(xf)
		return
	sh.global_transform = xf
	var al := _ft_shadow_alpha
	if u.sh_a != al:
		# параметры материала — только при смене настройки, а не каждый кадр
		u.sh_a = al
		var mat := sh.material_override as ShaderMaterial
		mat.set_shader_parameter("alpha", al)
		mat.set_shader_parameter("blur", 0.03 + 0.03 * (1.0 - _ft_shadow_size))


## Оптимизация (финальный проход 3.5): модели сбитых самолётов врага не удаляем, а прячем и отдаём
## следующему врагу того же вида — создание модели 2–10 мс, волна из шести дронов давала рывок кадра
const POOL_MAX := 24
var _pool := {}      # картинка → [скрытые корни моделей]


func _poolable(kind: String, thick: float, bm: PackedScene, tex: Texture2D) -> bool:
	return kind == "enemy" and thick > 0.06 and bm != null and not tex.resource_path.contains("fortress")


func _pool_put(u: Unit3D) -> bool:
	if u.shb == null or u.bm == null or u.kind != "enemy" or not is_nan(u.hull):
		return false
	var tex: Texture2D = u.tex
	if tex.resource_path.contains("fortress"):
		return false
	var arr: Array = _pool.get(tex, [])
	if arr.size() >= POOL_MAX:
		return false
	var root: Node3D = u.node
	root.visible = false
	(u.mi as MeshInstance3D).material_overlay = null
	arr.append(root)
	_pool[tex] = arr
	return true


func _pool_take(tex: Texture2D, kind: String, thick: float, bm: PackedScene) -> Unit3D:
	if not _poolable(kind, thick, bm, tex):
		return null
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
		var pu := Unit3D.new()
		pu.node = root
		pu.mi = mi
		pu.kind = kind
		pu.tex = tex
		pu.bm = bm
		pu.shb = tex
		return pu
	return null


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
		_units[id].seen = false
	var ut := Time.get_ticks_usec() if Perf.on else 0
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
			var y: float = maxf(ra - Tuning.g("dive_depth") * dk, _ground_floor(p.global_position, Tuning.g("plane_len") * p.size * 0.5))
			_place(u, p.global_position, p.heading, (p.bank * deg_to_rad(Tuning.g("aces_bank")) if Main.aces() else vis_bank(p.bank, float(p.cls.get("bank_deg", 32.0)))), roll, y, (1.0 - 0.15 * dk) * _alt_scale(y), u.pitch - 0.2 * p.dive_pitch())
			# форсаж: огонь длиннее, след плотнее и шире (плавно, без скачка)
			# S9-16: на «Звуковом ударе» (ram_t) — тот же огонь и плотный след, что на форсаже
			u.ab = move_toward(float(u.ab), 1.0 if p.ab_t > 0.0 or p.ram_t > 0.0 else 0.0, sd * 4.0)
			var ab: float = u.ab
			PlaneFx.update(u, sd, ab)
			# «Битва асов»: след живёт дольше — на экране остаются целые дуги виражей, как в Sky Knights
			# M-39 (Э-2): инверсия белая, у сопла узкая и плотная, расплывается шире и тает быстрее (жизнь короче)
			var st := [lerpf(0.32, 0.55, ab), lerpf(3.0, 5.0, ab) * p.size, lerpf(18.0, 28.0, ab) * p.size, Tuning.g("aces_trail") if Main.aces() else lerpf(1.2, 1.8, ab), 12.0]
			var pts := PlaneFx.trail_points(u)
			for i in pts.size():
				_trails.emit("p%d" % i, pts[i], st)
			var mi: MeshInstance3D = u.mi
			mi.transparency = 0.6 if (p.invuln > 0.0 and p.roll_t <= 0.0 and int(p._blink * 20.0) % 2 == 0) else 0.0
			if u.mech != null:
				# Т-1: выпуск в крутом вираже и при торможении (РУД меньше крейсерского или сброс газа)
				var brake := 1.0 if p.throttle_cut_on() else (1.0 - p.throttle) / 0.4
				WingMech.update(u.mech, p.bank, brake, int(p.taken.get("wing", 0)), sd)
				WingMech.set_transparency(u.mech, mi.transparency)
			if u.ins != null:
				Insignia.set_transparency(u.ins, mi.transparency)
			if u.detail != null:
				WingMech.set_transparency(u.detail, mi.transparency)
			if u.props != null:   # винты «Кита 1» мигают вместе с моделью
				WingMech.set_transparency(u.props, mi.transparency)
			if u.bay != null:
				# Т-5: створки открываются при сбросе бомб (перезарядка группы бомбоотсека скакнула вверх)
				var dropped := false
				for g: Hardpoint in p.groups:
					if Weapons.is_bomb(g.weapon):
						var key := "bay_cd_%s" % g.name
						dropped = dropped or g.cd > float(u.bay_cd.get(g.name, g.cd)) + 0.3
						u.bay_cd[g.name] = g.cd
				u.bay_t = WingMech.update_bay(u.bay, dropped, sd)
				WingMech.set_transparency(u.bay, mi.transparency)
			if u.modp != null:
				ModuleParts.update(u.modp, p.taken)
				ModuleParts.set_transparency(u.modp, mi.transparency)
				PlaneFx.set_blue(u, bool((u.modp as Node3D).get_meta("blue_flame", false)))
			_sync_weapons(u, p, tex)
		for w in p.wingmen:
			var wm: Wingman = w
			var wt := wm.plane_tex()
			if wt == null or not wm.alive():
				continue
			var len_w := Tuning.g("plane_len") * 0.85 * float(wt.get_width()) / float(PlaneArt.plane_tex("fighter", 1).get_width())
			var uw := _ensure(wm.get_instance_id(), "wing", wt, len_w, 0.075, 48)
			uw.ref = weakref(wm)
			if uw.kit == null and uw.bm != null:   # Т-8: полосы звена и подвесы по типу ведомого
				uw.kit = WingMech.attach_wing_kit(uw.node.get_child(0) as Node3D, wt.resource_path.get_file().get_basename(), wm.type, uw.bm)
			var rw := _relief_alt(uw, wm.global_position, Vector2.from_angle(wm.heading) * 300.0, 1.0, sd)
			_place(uw, wm.global_position, wm.heading, _turn_bank(uw, wm.heading, delta), 0.0, rw, _alt_scale(rw), uw.pitch)
			if uw.mech != null:
				WingMech.update(uw.mech, float(uw.bank), 0.0, 0, sd)
			PlaneFx.update(uw, sd, 0.0)
			var wpts := PlaneFx.trail_points(uw)
			for i in wpts.size():
				_trails.emit("w%d_%d" % [wm.get_instance_id(), i], wpts[i], [0.22, 2.5, 14.0, 1.0, 14.0])
	if Perf.on: ut = Perf.sub("r3d.u.player", ut)
	# 3.5: свои самолёты вне звена (заправщик): ally_tex(), ally_len(), heading
	for n in get_tree().get_nodes_in_group("allies3d"):
		var an := n as Node2D
		var at: Texture2D = an.call("ally_tex")
		if at == null:
			continue
		var ua := _ensure(an.get_instance_id(), "ally", at, float(an.call("ally_len")), 0.075, 56)
		var ah: float = an.get("heading")
		var rl := _relief_alt(ua, an.global_position, Vector2.from_angle(ah) * 300.0, 1.0, sd)
		_place(ua, an.global_position, ah, _turn_bank(ua, ah, delta), 0.0, rl, _alt_scale(rl), ua.pitch)
		PlaneFx.update(ua, sd, 0.0)
		if ua.bm != null and an.get("boom_len") != null:
			_tanker_boom(ua, an, float(an.call("ally_len")))
	var unit_scale := Tuning.g("unit_scale")
	for n in get_tree().get_nodes_in_group("enemies"):
		var et := Time.get_ticks_usec() if Perf.on else 0   # a slow unit shows as «пик:r3d.e.<class>»
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var info := e.sprite_info()
		if info.is_empty():
			continue
		var t: Texture2D = Enemy.etex(info["tex"])
		if t == null:
			continue
		var len_px: float = float(info["len"]) * unit_scale * (1.2 if e.elite else 1.0)
		if not _units.has(e.get_instance_id()) and not _battle_model_ready(t):
			continue   # its model is still loading; an existing unit never waits (it would count as gone)
		var ue := _ensure(e.get_instance_id(), "enemy", t, len_px, 0.05 if e.is_ground else 0.07, 40 if not e.is_boss else 64)
		var ang: float = info.get("angle", e.heading)
		if e.is_ground:
			# 3.5: у целей с точкой на рельефе (anchor) — ставим ровно туда, иначе проекция с камеры
			var gp := terrain.surface_fast(e.anchor.x, e.anchor.y) if (e.anchor != Vector2.INF and terrain != null) else ground_under(e.global_position)
			var hull := ang
			var tilt := Vector2.ZERO
			var lev := false
			if e is ConvoyVehicle:
				# A-03: машина конвоя — корпус по курсу, наклон по склону и от разгона, колёса и башня
				var cr := _convoy_parts(ue, e as ConvoyVehicle, len_px, delta)
				hull = cr.x
				tilt = Vector2(cr.y, cr.z)
				_convoy_dust(e as ConvoyVehicle, gp, hull, len_px)
			elif e is Warship or e is Ekranoplan:
				# «Архипелаг»: корабли-боссы и экраноплан — курс из маршрута, качка, пенный след
				hull = e.heading
				var wt := Time.get_ticks_msec() * 0.001 + float(e.get_instance_id() % 53)
				tilt = Vector2(sin(wt * 0.6) * 0.012, sin(wt * 0.45 + 1.0) * 0.02) if e is Warship else Vector2.ZERO
				_sea_wake(e, gp, hull, len_px)
				lev = e is Warship and (e as Warship).variant == "leviathan" and ue.bm != null
			elif ue.bm != null:
				hull = _ground_parts(ue, e, ang, delta)
				var gt := e as GroundTarget
				if gt != null and gt.mount_h > 0.0:
					_fort_mount(ue)
					gp.y += gt.mount_h   # FA-01: on the tower top
				if gt != null and gt.drive != null:
					# правка 3.5-s4: ЗСУ и ЗРК — корпус по курсу машины, наклон по склону и от разгона
					tilt = _drive_tilt(ue, gt.anchor, hull, gt.drive, len_px, delta)
			_place(ue, Vector2(gp.x, gp.z), hull, tilt.y, 0.0, gp.y + 1.0, (cam.global_position.y - gp.y) / cam.global_position.y, tilt.x)
			if lev:   # «Левиафан»: башни, пусковые, РЛС, ЗСУ — наведение, пуски, разрушение (замечания Kanta 19.10)
				LeviathanParts.update(ue, e as Warship, delta)
		else:
			var re := _relief_alt(ue, e.global_position, Vector2.from_angle(ang) * 250.0, 0.0 if e.is_boss else 1.0, sd)
			_place(ue, e.global_position, ang, _turn_bank(ue, ang, delta), e.roll_angle(), re, _alt_scale(re), ue.pitch) # 3.5: бочка при уклонении
			if ue.bm != null and e is Fortress:
				_fortress_parts(ue, e as Fortress, ang, delta)
			elif ue.bm != null and e is Helicopter:
				_rotors(ue, delta)
			elif ue.bm != null:   # винты prop_* (транспортник, «Буревестник», «Чайка»); нет узлов — нет работы
				_props(ue, delta)
		var mi2: MeshInstance3D = ue.mi
		var ov: Material
		if ue.bm != null:
			var hit_mat := _boss_flash_mat if e.is_boss else _flash_mat
			ov = hit_mat if e._flash > 0.0 else (_elite_mat if e.elite else null)
		else:
			# модель из картинки (транспортник и др.): подсветка только по силуэту, иначе видна сетка квадратами
			ov = _cut_overlay(ue.tex, "flash") if e._flash > 0.0 else (_cut_overlay(ue.tex, "elite") if e.elite else null)
		if mi2.material_overlay != ov:   # the setter always re-sends the material to the renderer
			mi2.material_overlay = ov
		if Perf.on: Perf._spike("r3d.e." + _perf_cls(e), Time.get_ticks_usec() - et)
	if Perf.on: ut = Perf.sub("r3d.u.enemies", ut)
	_sync_wrecks(delta)
	if Perf.on: ut = Perf.sub("r3d.u.wrecks", ut)
	_sync_dust(delta)
	if Perf.on: ut = Perf.sub("r3d.u.dust", ut)
	_flush_shadows()
	_sync_plane_shadows()
	if Perf.on: ut = Perf.sub("r3d.u.shadows", ut)
	for id in _units.keys():
		if not _units[id].seen:
			if not _start_crash(_units[id]) and not _pool_put(_units[id]):
				(_units[id].node as Node).queue_free()
			_units.erase(id)


## Class name of a unit for Perf spike labels (script class, else the engine class).
static func _perf_cls(n: Node) -> String:
	var sc: Script = n.get_script()
	return sc.get_global_name() if sc != null and sc.get_global_name() != "" else n.get_class()


## Helicopter rotors: the main rotor turns clockwise seen from above, the tail rotor about its own axis (local Z
## in the GLB). S9-22: in battle the blades are a light translucent blur disc with streaks (RotorBlur); the model
## keeps only the hub and blade roots. Sizes follow the model (VIS-01, sf_recipes.py "e_helicopter", measured on the
## GLB vertices, fuselage length = 1): main rotor 5 blades, tips at r 0.474, hub kept inside 0.05 (the blade cuffs
## past it read as light spikes over the disc); tail rotor 3 blades, r 0.116, hub kept inside 0.03.
const ROTOR_R := 0.474
const ROTOR_HUB := 0.05
const TAIL_R := 0.116
const TAIL_HUB := 0.03


func _rotors(u: Unit3D, delta: float) -> void:
	if u.rot == null:
		var inst := (u.node as Node3D).get_child(0)
		var r := inst.find_child("rotor", true, false) as MeshInstance3D
		var tr := inst.find_child("tail_rotor", true, false) as MeshInstance3D
		u.rot = [r, tr]
		RotorBlur.attach(r, ROTOR_R, 5, ROTOR_HUB, Vector3.AXIS_Y)
		RotorBlur.attach(tr, TAIL_R, 3, TAIL_HUB, Vector3.AXIS_Z)
	var rr: Array = u.rot
	if rr[0] != null:
		(rr[0] as Node3D).rotate_y(-delta * 9.0)
	if rr[1] != null:
		(rr[1] as Node3D).rotate_z(delta * 40.0)


## 3.5-s8: винты транспортника (tools/blender/enemy_air_big.py, узлы prop_1…prop_4, ось — локальная X);
## так же — винты «Буревестника» и «Чайки» (tools/model_lab/b2_sea_craft.py), дрона и транспортника из sf_recipes.py.
## VIS-01 (Kanta 26.10): лопасти крутящегося винта читались отдельными палками, поэтому у винта-меша, как у
## вертолёта, остаётся втулка, а лопасти заменяет диск размытия (RotorBlur). Радиус — по самому мешу винта
## (наибольшее удаление от оси X), втулка — 15 % радиуса, так что подходит любая модель с узлами prop_*.
func _props(u: Unit3D, delta: float) -> void:
	if u.props3 == null:
		var inst := (u.node as Node3D).get_child(0)
		u.props3 = inst.find_children("prop_*", "Node3D", true, false)
		for p in u.props3:
			var mi := p as MeshInstance3D
			if mi != null and mi.mesh != null:
				var bb := mi.mesh.get_aabb()
				var r := maxf(maxf(absf(bb.position.y), absf(bb.end.y)), maxf(absf(bb.position.z), absf(bb.end.z)))
				RotorBlur.attach(mi, r, 3, r * 0.15, Vector3.AXIS_X)
	for p in u.props3:
		(p as Node3D).rotate_x(delta * 22.0)


## Подвижные части наземных моделей (tools/blender/ground_models.py): корпус стоит, как встал,
## башня ЗСУ (turret) смотрит на цель, антенна РЛС (antenna) вращается, контейнеры ЗРК (launcher)
## поднимаются, пока идёт захват цели — предупреждение перед пуском. Возвращает курс корпуса.
func _ground_parts(u: Unit3D, e: Enemy, ang: float, delta: float) -> float:
	if is_nan(u.hull):
		u.hull = ang
		var inst := (u.node as Node3D).get_child(0)
		u.turret = inst.find_child("turret", true, false) as Node3D
		u.antenna = inst.find_child("antenna", true, false) as Node3D
		u.launcher = inst.find_child("launcher", true, false) as Node3D
		u.launcher_yaw = inst.find_child("launcher_yaw", true, false) as Node3D
		u.launcher_pitch = inst.find_child("launcher_pitch", true, false) as Node3D
		if u.launcher_pitch != null:
			var cells := []
			for i in 64:
				var c := (u.launcher_pitch as Node3D).find_child("cell_%d" % i, false, false)
				if c == null:
					break
				cells.append(c)
			u.cells = cells
	var gt := e as GroundTarget
	if gt != null and gt.fixed:
		pass   # FortArea: tower launchers and yard jeeps never turn their hull (the screen point drifts with the camera)
	elif gt != null and gt.drive != null:
		# правка 3.5-s4: курс корпуса — из модуля движения. Раньше брался сдвиг точки на экране,
		# а она смещается и от движения камеры — корпус «перекатывался» на стоящей машине
		u.hull = gt.drive.heading
	else:
		# едет — корпус по ходу движения
		var lp: Vector2 = (u.lastp if u.lastp != null else e.global_position)
		var mv := e.global_position - lp
		u.lastp = e.global_position
		if mv.length() > 0.3:
			u.hull = lerp_angle(float(u.hull), mv.angle(), 1.0 - exp(-delta * 4.0))
	var hull: float = u.hull
	if u.turret != null:
		(u.turret as Node3D).rotation.y = -wrapf(ang - hull, -PI, PI)
	if u.antenna != null:
		(u.antenna as Node3D).rotate_y(delta * 1.6)
	if u.launcher != null:
		var up := deg_to_rad(55.0) if float(e.get("_lock") if e.get("_lock") != null else 0.0) > 0.0 else 0.0
		var ln := u.launcher as Node3D
		ln.rotation.z = move_toward(ln.rotation.z, up, delta * 1.2)
	if u.launcher_pitch != null and gt != null:
		_sam_launcher(u, gt, hull, delta)
	return hull if (u.turret != null or u.antenna != null or u.launcher != null or u.launcher_pitch != null) else ang


## FA-01 (Kanta 2026-10-25): a FortArea tower launcher is the SAM truck's own launcher subtree
## (launcher_yaw → launcher_pitch → cell_*), so `_sam_launcher` animates it unchanged; the truck body is
## hidden and the turntable moves out of it to the model origin, onto the tower pad. Runs once per unit.
func _fort_mount(u: Unit3D) -> void:
	if u.fort_mount or u.launcher_yaw == null:
		return
	u.fort_mount = true
	var yaw := u.launcher_yaw as Node3D
	var inst := (u.node as Node3D).get_child(0) as Node3D
	yaw.reparent(inst, false)   # in the GLB the turntable is a child of the body mesh, which gets hidden
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if mi != yaw and not yaw.is_ancestor_of(mi):
			(mi as MeshInstance3D).visible = false
	yaw.position = Vector3(0.0, 0.02, 0.0)
	if yaw is MeshInstance3D:
		u.mi = yaw   # hit flash on a visible part


## SAM launcher (Kanta 24.10, model tools/blender/sf_recipes.py "e_sam"): the box rides folded flat over the
## deck; when the launcher stands at a live site it rises, then the turntable turns it after the plane and
## keeps tracking through the lock; a launch kicks the box. Folding runs the other way round — turn back
## first, then lower — because a folded box swung sideways would cut through the cab.
const SAM_UP := deg_to_rad(30.0)     # raised elevation of the source model
const SAM_RAISE := deg_to_rad(70.0)  # elevation rate, °/s: ~0.45 s to raise, inside the 1.2 s lock
const SAM_TRAVERSE := deg_to_rad(120.0)
const SAM_KICK := deg_to_rad(4.0)    # box dips on each launch, settles back


func _sam_launcher(u: Unit3D, gt: GroundTarget, hull: float, delta: float) -> void:
	var yaw := u.launcher_yaw as Node3D
	var pitch := u.launcher_pitch as Node3D
	var up := gt.launcher_up()
	var raised: float = u.sam_el
	var want_yaw := 0.0
	var pl := Main.I.player
	if up and raised > SAM_UP * 0.8 and pl != null:
		want_yaw = -wrapf((pl.global_position - gt.global_position).angle() - hull, -PI, PI)
	yaw.rotation.y = rotate_toward(yaw.rotation.y, want_yaw, SAM_TRAVERSE * delta)
	var want_el := SAM_UP if up else (SAM_UP if absf(yaw.rotation.y) > 0.05 else 0.0)
	raised = move_toward(raised, want_el, SAM_RAISE * delta)
	u.sam_el = raised
	if gt.launches != int(u.sam_n):
		u.sam_n = gt.launches
		u.sam_kick = SAM_KICK
	var kick: float = u.sam_kick
	u.sam_kick = move_toward(kick, 0.0, SAM_KICK * 3.0 * delta)
	pitch.rotation.z = raised - kick
	var cells: Array = u.cells
	gt.launch_at = _ground_to_combat((cells[gt.launches % cells.size()] as Node3D).global_position) if not cells.is_empty() else Vector2.INF


## A-03: подвижные части машин конвоя (tools/blender/convoy_models.py): колёса крутятся по пройденному пути
## (GroundDrive.dist), передние поворачивают по рулю; башня и пулемёт смотрят на самолёт; труба ПЗРК
## поднимается при захвате. Корпус лежит на склоне (рельеф под носом и кормой, бортами), клюёт носом
## при торможении и кренится наружу на повороте. Возвращает (курс корпуса, тангаж, крен).
func _convoy_parts(u: Unit3D, v: ConvoyVehicle, len_px: float, delta: float) -> Vector3:
	var dr := v.drive
	var hull := v.heading
	if dr == null:
		return Vector3(hull, 0.0, 0.0)
	if u.bm != null and u.cv == null:
		var inst := (u.node as Node3D).get_child(0)
		var d := {"wheels": [], "front": [], "r": 0.072}
		for c in inst.find_children("wheel_*", "Node3D", true, false):
			(d["wheels"] as Array).append(c)
			if String(c.name).begins_with("wheel_f"):   # wheel_fl / wheel_f2l: both steered axles of an 8x8
				(d["front"] as Array).append(c)
			if c is MeshInstance3D:   # VIS-01: rolling radius from the model's own wheel (length-1 units)
				d["r"] = maxf((c as MeshInstance3D).get_aabb().size.y * 0.5, 0.02)
		for nm in ["turret", "launcher"]:
			var n := inst.find_child(nm, true, false)
			if n != null:
				d[nm] = n
		u.cv = d
	if u.cv != null:
		var d: Dictionary = u.cv
		# angle = distance / wheel radius (a share of the vehicle length, from the model; 0.072 without one)
		var roll := -dr.dist / (float(d["r"]) * len_px)
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
	if Biome.sea():
		# «Архипелаг»: корабль на воде — качка на волне (длинные корпуса качаются медленнее и меньше), крен на циркуляции
		var t := Time.get_ticks_msec() * 0.001 + float(v.get_instance_id() % 97)
		var k := clampf(120.0 / len_px, 0.3, 1.0)
		var sea := Vector2(sin(t * 0.9 * k) * 0.02 * k, sin(t * 0.7 * k + 1.3) * 0.035 * k - clampf(dr.yaw_rate * dr.speed * 0.0006, -0.05, 0.05))
		return Vector3(hull, sea.x, sea.y)
	var sm := _drive_tilt(u, v.anchor, hull, dr, len_px, delta)
	return Vector3(hull, sm.x, sm.y)


## Наклон корпуса машины (тангаж, крен): по рельефу под носом, кормой и бортами; клевок при торможении,
## приседание при разгоне, крен наружу на повороте, мелкая раскачка на ходу. Общее для конвоя и ПВО.
func _drive_tilt(u: Unit3D, a: Vector2, hull: float, dr: GroundDrive, len_px: float, delta: float) -> Vector2:
	var pitch := 0.0
	var bank := 0.0
	if terrain != null and a != Vector2.INF:
		var f := Vector2.from_angle(hull) * len_px * 0.45
		var sd := Vector2(-f.y, f.x) * 0.45
		pitch = atan2(terrain.surface_fast(a.x + f.x, a.y + f.y).y - terrain.surface_fast(a.x - f.x, a.y - f.y).y, len_px * 0.9)
		bank = atan2(terrain.surface_fast(a.x + sd.x, a.y + sd.y).y - terrain.surface_fast(a.x - sd.x, a.y - sd.y).y, len_px * 0.4)
	pitch += clampf(dr.acc_now * 0.0012, -0.06, 0.06)
	bank += clampf(-dr.yaw_rate * dr.speed * 0.0009, -0.07, 0.07) + sin(dr.dist * 0.09) * 0.006 * clampf(dr.speed / 60.0, 0.0, 1.0)
	var sm: Vector2 = (u.tilt if u.tilt != null else Vector2(pitch, bank))
	sm = sm.lerp(Vector2(pitch, bank), 1.0 - exp(-delta * 6.0))
	u.tilt = sm
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
	if Biome.sea():   # S10-10: судно каравана оставляет на воде кильватерный след
		_wakes.emit(id, Vector3(gp.x, gp.y + 0.6, gp.z), hull, len_px, len_px * 0.085)
	var back := Vector2(gp.x, gp.z) - Vector2.from_angle(hull) * len_px * (0.46 if Biome.sea() else 0.5)
	ps.global_position = Vector3(back.x, gp.y + len_px * (0.005 if Biome.sea() else 0.04), back.y)
	ps.emitting = v.drive.speed > (8.0 if Biome.sea() else 18.0)
	d["t"] = 0.0


## Пенный след корабля-босса и экраноплана (тот же след, что у судов конвоя, всегда на ходу)
func _sea_wake(e: Enemy, gp: Vector3, hull: float, len_px: float) -> void:
	var id := e.get_instance_id()
	var d: Dictionary = _dust.get(id, {})
	if d.is_empty():
		d = {"p": _make_dust(len_px * (0.6 if e is Warship else 1.0)), "t": 0.0}
		_dust[id] = d
	d["seen"] = true
	var ps := d["p"] as CPUParticles3D
	_wakes.emit(id, Vector3(gp.x, gp.y + 0.6, gp.z), hull, len_px, len_px * (0.14 if e is Ekranoplan else 0.085))   # S10-10
	var back := Vector2(gp.x, gp.z) - Vector2.from_angle(hull) * len_px * 0.46
	ps.global_position = Vector3(back.x, gp.y + 1.0, back.y)
	ps.emitting = true
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
	s.amount = [8, 14, 20, 24][Settings.gopt("effects")]
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
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	gr.colors = PackedColorArray([Color(0.92, 0.85, 0.72, 0.0), Color(0.9, 0.83, 0.7, 0.55), Color(0.84, 0.78, 0.68, 0.0)])   # светлее песка — видно сверху
	if Biome.sea():
		# «Архипелаг»: белый пенный след по воде — плоский, длинный, не поднимается; расходится в стороны «усами»
		s.amount = [14, 24, 34, 44][Settings.gopt("effects")]
		s.lifetime = 3.2
		s.spread = 180.0
		s.flatness = 1.0
		s.initial_velocity_min = 1.0
		s.initial_velocity_max = 4.0
		s.gravity = Vector3.ZERO
		s.emission_sphere_radius = len_px * 0.05
		s.scale_amount_min = len_px * 0.08
		s.scale_amount_max = len_px * 0.14
		sc = Curve.new()
		sc.add_point(Vector2(0, 0.6))
		sc.add_point(Vector2(1, 2.6))
		gr.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(0.97, 0.99, 1.0, 0.7), Color(0.85, 0.93, 0.95, 0.0)])
	s.scale_amount_curve = sc
	s.color_ramp = gr
	s.emitting = false
	add_child(s)
	return s


## A-03: остовы машин конвоя — та же модель, обгоревшая: тент и стрелки пропадают, корпус тёмный, дым столбом
var _burnt_mat: Material


## S10-07 (Kanta 23.10: «уничтоженная техника лежит как кусок тёмного чего-то»): было — непрозрачная почти чёрная
## заливка без света поверх модели. Стало — умножение поверх своего цвета модели: свет, тени и детали корпуса
## остаются, металл пятнами в саже, пепельно-серый и рыжий от окалины (по мировым координатам — у каждой машины свой)
const BURNT_SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, shadows_disabled, cull_back;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), u.x), u.y);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 q = wp.xz + wp.y * 0.7;
	float n = vn(q / 5.0) * 0.6 + vn(q / 2.0 + 7.0) * 0.4;
	vec3 soot = vec3(0.24, 0.23, 0.22);
	vec3 ash = vec3(0.5, 0.49, 0.47);
	vec3 rust = vec3(0.62, 0.44, 0.34);
	vec3 c = mix(soot, ash, smoothstep(0.5, 0.75, n));
	c = mix(c, rust, smoothstep(0.68, 0.82, vn(q / 3.0 + 3.0)) * 0.6);
	ALBEDO = c;
}
"""


func _make_burnt_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = BURNT_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


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
		if not u.wreck:
			u.wreck = true
			if _burnt_mat == null:
				_burnt_mat = _wreck_mat
			if u.bm != null:
				var inst := (u.node as Node3D).get_child(0)
				for nm in ["tent", "launcher"]:
					var hn := inst.find_child(nm, true, false) as Node3D
					if hn != null:
						hn.visible = false
				for c in inst.find_children("*", "GeometryInstance3D", true, false):
					(c as GeometryInstance3D).material_overlay = _burnt_mat
			var smoke := _make_smoke()   # создаётся дочерним у Render3D — переносим к остову, чтобы ушёл вместе с ним
			smoke.get_parent().remove_child(smoke)
			smoke.top_level = true
			(u.node as Node3D).add_child(smoke)
			u.wsmoke = smoke
		var gp := terrain.surface_fast(v.anchor.x, v.anchor.y) if terrain != null else ground_under(v.global_position)
		var tilt: Vector2 = (u.tilt if u.tilt != null else Vector2.ZERO)
		var sink := 0.0
		if Biome.sea():
			# S10-07: подбитое судно не лежит на воде тёмным куском — кренится, оседает кормой и уходит под воду
			# (вода «Архипелага» — поверхность рельефа: ниже неё модель скрыта); пока тонет — пена вокруг
			var st := minf(float(u.sink_t) + delta, SINK_TIME + 1.0)
			u.sink_t = st
			sink = smoothstep(0.0, SINK_TIME, st)
			tilt += Vector2(sink * 0.35, -sink * 0.18) * (1.0 if v.get_instance_id() % 2 == 0 else -1.0)
			_sink_foam(v.get_instance_id(), gp, len_px, st < SINK_TIME)
			(u.node as Node3D).visible = st < SINK_TIME
		_place(u, Vector2(gp.x, gp.z), v.heading, tilt.y + 0.04, 0.0, gp.y + 0.5 - sink * len_px * 0.3, (cam.global_position.y - gp.y) / cam.global_position.y, tilt.x)
		if u.wsmoke != null:
			var sm := u.wsmoke as CPUParticles3D
			sm.global_position = Vector3(gp.x, gp.y + 4.0, gp.z)
			sm.emitting = v._burn < 12.0 and sink < 0.7
		if u.bm == null:
			if _burnt_sprite_mat == null:
				_burnt_sprite_mat = StandardMaterial3D.new()
				_burnt_sprite_mat.albedo_color = Color(0.03, 0.025, 0.02, 0.78)
				_burnt_sprite_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_burnt_sprite_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(u.mi as MeshInstance3D).material_overlay = _burnt_sprite_mat


const SINK_TIME := 6.0   # S10-07: за сколько секунд подбитое судно каравана уходит под воду


## S10-07: пена и брызги вокруг тонущего судна (те же частицы, что у пенного следа)
func _sink_foam(id: int, gp: Vector3, len_px: float, on: bool) -> void:
	var d: Dictionary = _dust.get(id, {})
	if d.is_empty():
		if not on:
			return
		d = {"p": _make_dust(len_px), "t": 0.0}
		_dust[id] = d
	d["seen"] = true
	var ps := d["p"] as CPUParticles3D
	ps.global_position = Vector3(gp.x, gp.y + 1.0, gp.z)
	ps.emission_sphere_radius = len_px * 0.3
	ps.emitting = on
	d["t"] = 0.0


## Подвижные части «Крепости» (tools/blender/fortress.py): башни смотрят на игрока (ракета на куполе — с ней), винты крутятся,
## выбитые точки (Fortress.parts_down) пропадают или останавливаются; с фазы 2 открываются люки
## и поднимаются ракеты, в фазе 3 откидываются панели обшивки над раскалённым ядром.
const FORTRESS_NODES := ["turret_1", "turret_2", "turret_3", "turret_4", "turret_1_missile", "turret_2_missile",
	"turret_3_missile", "turret_4_missile", "engine_l_prop", "engine_l_prop2",
	"engine_r_prop", "engine_r_prop2", "hatch_l", "hatch_r", "bay_l", "bay_r", "hull_l", "hull_r", "core"]


func _fortress_parts(u: Unit3D, f: Fortress, ang: float, delta: float) -> void:
	if u.fparts == null:
		var inst := (u.node as Node3D).get_child(0)
		var d := {}
		for nm in FORTRESS_NODES:
			var n := inst.find_child(nm, true, false) as Node3D
			if n != null:
				d[nm] = n
				d[nm + "@"] = n.position
		u.fparts = d
	var parts: Dictionary = u.fparts
	var p := Main.I.player
	for i in 4:
		var nm := "turret_%d" % (i + 1)
		if not parts.has(nm):
			continue
		var t := parts[nm] as Node3D
		t.visible = not f.parts_down.has(nm)
		if parts.has(nm + "_missile") and i < f.points.size():   # the dome's rail missile, gone while it reloads
			(parts[nm + "_missile"] as Node3D).visible = float(f.points[i].get("msl", 0.0)) <= 0.0
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


func _tanker_boom(u: Unit3D, an: Node2D, len_px: float) -> void:
	if not u.boom_done:
		var inst := (u.node as Node3D).get_child(0)
		var b := inst.find_child("Boom", true, false) as Node3D
		u.boom_done = true
		u.boom = b
		u.boom_tube = inst.find_child("BoomTube", true, false) if b != null else null
		u.boom_tip = inst.find_child("BoomTip", true, false) if b != null else null
	var boom := u.boom as Node3D
	if boom == null or u.boom_tube == null:
		return
	# наконечник в осях заправщика (пикс., x — вперёд), потом в единицы модели (1 = длина модели)
	var tip := Vector2(-Tanker.BOOM_ROOT, 0.0) + Vector2(-float(an.get("boom_len")), 0.0).rotated(float(an.get("boom_angle")))
	var v := tip / len_px - Vector2(boom.position.x, boom.position.z)
	var l := maxf(v.length(), 0.05)
	boom.rotation.y = atan2(v.y, -v.x)
	(u.boom_tube as Node3D).scale.x = l
	if u.boom_tip != null:
		(u.boom_tip as Node3D).position = Vector3(-cos(BOOM_PITCH), -sin(BOOM_PITCH), 0.0) * l


## Крен от скорости поворота (для врагов и ведомых)
## Model roll of the player's plane for its bank (−1..1, share of the top turn rate). Kanta 27.10: a hard turn
## should lean much deeper for the feel of flight, the turn radius stays arcade. Steeper than linear: a gentle
## turn leans about as before (0.55 rad at full bank before), a hard one up to max_deg (per class, PlaneClasses)
static func vis_bank(bank: float, max_deg: float) -> float:
	return signf(bank) * pow(absf(bank), 1.35) * deg_to_rad(max_deg)


func _turn_bank(u: Unit3D, heading: float, delta: float) -> float:
	var dh := wrapf(heading - float(u.ph), -PI, PI)
	u.ph = heading
	var target := clampf(dh / maxf(delta, 0.001) * 0.35, -1.0, 1.0)
	u.bank = lerpf(float(u.bank), target, 1.0 - exp(-delta * 6.0))
	return float(u.bank)


## Подвесы — объёмные модели на точках подвеса поверх крыла; S13: flare panels and wing-turret fairings are
## built into the model's own skin (SkinPatch) and tracked in u.weapons like the weapon nodes
func _sync_weapons(u: Unit3D, p: Player, tex: Texture2D) -> void:
	var root: Node3D = u.node
	var want := {}
	var wc: Dictionary = u.wcache   # оптимизация (финальный проход 3.5): раскладка подвесов группы
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		if g.is_empty():
			continue
		# U-08: у экспериментального оружия нет плоского значка, но есть 3D-модель (exp_weapons.py)
		if PlaneArt.weapon_tex(g.weapon) == null and not (g.weapon in Weapons.EXP):
			continue
		var seek := ModuleParts.stage(int(p.taken.get("seeker", 0))) if g.weapon == "aam" and not g.evo else 0
		var sig := [p.cls_id, p.plane_lvl, g.weapon, g.level, g.evo, g.slots, g.builtin, g.name, seek, u.k, Tuning.g("plane_len"), u.bm]
		var ent: Dictionary = wc.get(gi, {})
		if ent.is_empty() or ent["sig"] != sig:
			ent = _weapon_layout(u, p, tex, gi, g, seek)
			ent["sig"] = sig
			ent["ver"] = int(wc.get("ver", 0)) + 1
			wc["ver"] = ent["ver"]
			wc[gi] = ent
		var dim := Weapons.leaves_pylon(g.weapon) and g.cd > 0.3
		var len_px: float = ent["len_px"]
		var l_offs: Array = []
		for mt: Dictionary in ent["mounts"]:
			var key: String = mt["key"]
			want[key] = true
			if mt.has("skin") or mt.has("fair_rb"):
				# S13: a flush flare panel / a wing-turret fairing — part of the model's skin, built once under it
				var skey := key if mt.has("skin") else key + "_fair"
				want[skey] = true
				if not u.weapons.has(skey):
					var model := root.get_child(0) as Node3D
					var sk: MeshInstance3D = null
					if mt.has("skin"):
						sk = SkinPatch.flare_panel(model, float(mt["mx"]), float(mt["mz"]), float(mt["seed"]))
					else:
						sk = SkinPatch.turret_fairing(model, float(mt["mx"]), float(mt["mz"]), float(mt["fair_rb"]))
					if sk == null:
						sk = MeshInstance3D.new()   # the skin missed the spot: keep an empty node so it is not retried
					model.add_child(sk)
					u.weapons[skey] = sk
					if mt.has("fair_rb"):
						_apply_livery(model, tex)   # the fairing takes the plane's paint
				# part of the airframe: blinks with the hull while invulnerable
				(u.weapons[skey] as GeometryInstance3D).transparency = (u.mi as GeometryInstance3D).transparency
				if mt.has("skin"):
					continue
			var wmi: MeshInstance3D = u.weapons.get(key)
			if wmi == null:
				wmi = WeaponModels.make(g.weapon, mt["t"], mt["side"], p.cls_id, g.evo, p.plane_lvl)
				ModuleParts.seeker_head(wmi, seek, mt["t"])   # Т-3: «Глазастик»
				root.add_child(wmi)
				u.weapons[key] = wmi
			var tail_cab: bool = mt["tail_cab"]
			var fresh := int(wmi.get_meta("wver", -1)) != int(ent["ver"])
			if fresh:
				wmi.set_meta("wver", ent["ver"])
				wmi.position = mt["pos"]
			if tail_cab and u.tail != null:   # кабина — продолжение фюзеляжа модели, шар — у её торца
				var tpos := WingMech.tail_mount(u.tail, root)
				if tpos != Vector3.INF:
					wmi.position = tpos
					if wmi.get_child_count() > 0:
						(wmi.get_child(0) as Node3D).visible = false
			var yaw: float = mt["yaw"]
			if g.weapon == "turret":   # п. 37: турель смотрит на ближайшую цель
				var pods := wmi.get_node_or_null("pods") as Node3D   # S12: «Стальной ёж» launch pods on the turret
				if pods != null:
					pods.visible = p.syn.has("hedgehog")
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
			if g.weapon in Hardpoint.MISSILES:
				# правка 3.5-s4 (п. 27): ракета ушла с пилона — её там нет до перезарядки; пуск — с этой точки
				wmi.visible = not dim
				var wp := root.global_transform * wmi.position
				l_offs.append((Vector2(wp.x, wp.z) - p.global_position).rotated(-p.heading))
			else:
				if Weapons.is_bomb(g.weapon):
					# тест 3.5-s5 (п. 3): бомбы падают с точек подвеса (из бомбоотсека — из открытого люка);
					# у «ковра» в отсеке — с места каждой из 8 бомб кассеты
					var bl: Array = WeaponModels.CARPET_BAY_PTS if int(mt["t"]) == WeaponModels.CARPET_BAY_T else [Vector3.ZERO]
					for lp: Vector3 in bl:
						var bw := root.global_transform * (wmi.transform * lp)
						l_offs.append((Vector2(bw.x, bw.z) - p.global_position).rotated(-p.heading))
				elif g.weapon == "turret" or g.weapon == "gunpod":
					# Kanta 26.10: turret and gun-pod rounds (and their muzzle flash) leave from the barrels of the model,
					# not from a fixed spot beside the fuselage; +X of the weapon mesh runs along the barrels
					var mw := root.global_transform * (wmi.transform * Vector3(0.35, 0.0, 0.0))
					l_offs.append((Vector2(mw.x, mw.z) - p.global_position).rotated(-p.heading))
				var tr_w := 0.6 if dim else 0.0
				if wmi.transparency != tr_w:
					wmi.transparency = tr_w
			if mt["side"] == "bay":   # в закрытом бомбоотсеке бомб не видно
				wmi.visible = float(u.bay_t) > 0.4
		if Weapons.leaves_pylon(g.weapon) or g.weapon == "turret" or g.weapon == "gunpod":
			g.launch_offs = l_offs
	for key in u.weapons.keys():
		if not want.has(key):
			(u.weapons[key] as Node).queue_free()
			u.weapons.erase(key)


## Раскладка подвесов группы: точки, высота пилона, модель — считается при смене оружия, уровня или самолёта,
## а не каждый кадр (раньше — до 1,7 мс на кадр у «Кита» с полным набором)
func _weapon_layout(u: Unit3D, p: Player, tex: Texture2D, gi: int, g: Hardpoint, seek: int) -> Dictionary:
	var pts := WeaponModels.mounts(p.cls_id, p.plane_lvl, gi, g)
	var k: float = u.k
	var len_px: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) * Tuning.g("plane_len") / k  # в пикселях текстуры самолёта
	# 3.4-t1 (п. 3): объёмные модели, вид меняется на ур. 3 и 5
	var tr := WeaponModels.tier(g.level, g.evo)
	var tw := float(tex.get_width())
	var root_model: Node3D = (u.node as Node3D).get_child(0) as Node3D if u.bm != null else null
	var out: Array = []
	for si in pts.size():
		var mt: Dictionary = pts[si]
		var mtr: int = mt.get("t", tr)   # Т-5: у ловушек модель задаёт точка (кассета / контейнер)
		var pt: Vector2 = mt["p"]
		var fair_rb := 0.0
		if mt["side"] == "skin":   # S13: flush flare panel, laid onto the model in _sync_weapons
			if u.bm != null:
				out.append({"key": "%d_%d_%s_skin" % [gi, si, g.weapon], "skin": true, "mx": mt["mx"], "mz": mt["mz"],
					"seed": float(mt.get("seed", 0.0))})
			continue
		# подвесы — под крылом на пилоне (видны на крене и под наклоном камеры), турели — на своих местах
		# турель-модель в корме висит под концом фюзеляжа основанием вверх (как нижняя)
		var tail_cab: bool = mt["side"] == "tail" and g.weapon == "turret" and (WeaponModels.TURRET_MODELS.get(p.cls_id, {}) as Dictionary).has("tail")
		var under_tail: bool = mt["side"] == "tail" and g.weapon == "turret" and WeaponModels.TURRET_MODELS.has(p.cls_id) and not tail_cab
		var y: float = {"under": -tw * 0.012 - WeaponModels.hang(g.weapon, mtr, g.evo) * len_px, "belly": -tw * 0.028 - (WeaponModels.hang(g.weapon, tr, true) - WeaponModels.PYLON_H) * len_px, "bay": -tw * 0.02 - (WeaponModels.hang(g.weapon, mtr) - WeaponModels.PYLON_H) * len_px * 0.6, "top": tw * 0.028, "wing": tw * 0.012, "bottom": -tw * 0.028, "tail": -tw * 0.028 if under_tail else 0.0}.get(mt["side"], 0.0)
		if mt["side"] == "under" and u.bm != null:   # пилон — под настоящим крылом модели (тест 3.5-s3)
			var lo := WeaponModels.surface_low(u.bm, pt.x / tw, pt.y / tw)
			if not is_nan(lo):
				y = lo * tw - WeaponModels.hang(g.weapon, mtr, g.evo) * len_px
		elif mt.get("rail", false) and u.bm != null:   # Kanta 24.10: missile beside the real wing tip, at wing level
			var tr2 := WeaponModels.tip_rail(u.bm, pt.x / tw, pt.y / tw)
			if not is_nan(tr2.x):
				pt.y = tr2.x * tw + signf(pt.y) * WeaponModels.TIP_GAP * len_px
				y = tr2.y * tw
		elif mt["side"] == "top" and g.weapon == "turret" and u.bm != null:
			# тест 3.5-s7: верхняя турель — на настоящей спине фюзеляжа (у «Кита» она выше, чем у «Грача»)
			var hi := WeaponModels.surface_low(u.bm, pt.x / tw, pt.y / tw, true)
			if not is_nan(hi):
				y = hi * tw
		elif mt["side"] == "bottom" and g.weapon == "turret" and u.bm != null:
			# S13: the ventral turret hangs from the real belly («Кит» 2 third slot), as in the hangar
			var lo3 := WeaponModels.surface_low(u.bm, pt.x / tw, pt.y / tw)
			if not is_nan(lo3):
				y = lo3 * tw
		elif mt["side"] == "wing" and g.weapon == "turret" and mt.has("mx") and u.bm != null:
			# S13: «Грач» 2 wing turret — its ring on the crown of the wing fairing (SkinPatch, same as the hangar)
			fair_rb = WeaponModels.collar_r(p.cls_id, 3) * len_px / tw
			var cr := SkinPatch.fairing_crown(root_model, float(mt["mx"]), float(mt["mz"]), fair_rb)
			if not is_nan(cr):
				y = cr * tw
			else:
				fair_rb = 0.0
				var hw := WeaponModels.surface_low(u.bm, pt.x / tw, pt.y / tw, true)
				if not is_nan(hw):
					y = hw * tw
		elif mt["side"] == "bay" and u.bm != null:
			# тест 3.5-s5 (п. 3): бомбы и кассета «ковра» — от настоящего брюха модели, как в ангаре
			# (иначе верх кассеты проходил сквозь фюзеляж и был виден сверху)
			var lo2 := WeaponModels.surface_low(u.bm, pt.x / tw, pt.y / tw)
			if not is_nan(lo2):
				y = lo2 * tw - (WeaponModels.hang(g.weapon, mtr) - WeaponModels.PYLON_H) * len_px * 0.6
		var ent := {"key": "%d_%d_%s_%d%s_s%d" % [gi, si, g.weapon, mtr, "e" if g.evo else "", seek], "t": mtr,
			"side": mt["side"], "yaw": float(mt["yaw"]), "pos": Vector3(pt.x, y, pt.y), "tail_cab": tail_cab,
			"flip": mt["side"] == "bottom" or under_tail}
		if fair_rb > 0.0:
			ent["fair_rb"] = fair_rb
			ent["mx"] = mt["mx"]
			ent["mz"] = mt["mz"]
		out.append(ent)
	return {"mounts": out, "len_px": len_px}


# ---------- 3.4-t1: следы ракет (п. 34) ----------

## S8 «eweap»: след вражеской ракеты по виду (стиль Contrails.emit: альфа, ширина у сопла, ширина в конце, жизнь, шаг, цвет).
## ПЗРК — тонкий белый дымок, быстро тает; ракета самолёта — как была; ЗРК — толстый серый дымный след, держится дольше
const MSL_TRAIL := {
	"manpads": [0.7, 2.2, 6.5, 0.6, 12.0, Color(0.97, 0.97, 0.96)],
	"aam": [0.8, 5.0, 13.0, 0.95, 16.0, Color(0.84, 0.83, 0.82)],
	"sam": [0.92, 9.0, 30.0, 1.9, 16.0, Color(0.6, 0.59, 0.57)],
	"hnar": [0.7, 2.5, 7.0, 0.55, 10.0, Color(0.9, 0.89, 0.86)],   # S9-25: НАР вертолёта
}

func _sync_missiles(m: Main) -> void:
	var pr := m.projectiles
	if pr == null:
		return
	# M-39 (аудит 3.5-s6 Э-2): дым ракет светло-серый, плотный и широкий у сопла, расплывается и тает быстрее
	# (жизнь короче — без длинных дуг через полэкрана); на «Низком» точки реже
	var lo := 1.5 if Settings.gopt("effects") == 0 else 1.0
	for arr_st in [[pr.pmissiles, [0.85, 5.0, 14.0, 1.0, 16.0 * lo, Color(0.9, 0.9, 0.91)]],
			[pr.missiles, [0.8, 5.0, 13.0, 0.95, 16.0 * lo, Color(0.84, 0.83, 0.82)]],
			[pr.rockets, [0.7, 3.5, 9.0, 0.6, 14.0 * lo, Color(0.88, 0.88, 0.9)]]]:
		for mm: Dictionary in arr_st[0]:
			if float(mm.get("delay", 0.0)) > 0.0 or float(mm.get("lev_hold", 0.0)) > 0.0:
				continue
			if not mm.has("tid"):
				_tid += 1
				mm["tid"] = _tid
			var v: Vector2 = mm["v"]
			var tail: Vector2 = mm["p"] - (v.normalized() * 9.0 if v.length() > 1.0 else Vector2.ZERO)
			var st: Array = arr_st[1]
			if mm.has("k") and MSL_TRAIL.has(mm["k"]):   # S8 «eweap»: след по виду вражеской ракеты
				var mts: Array = MSL_TRAIL[mm["k"]]
				st = [mts[0], mts[1], mts[2], mts[3], float(mts[4]) * lo, mts[5]]
			if mm.get("src", "") == "ёлочка":
				# Kanta s12: the 10–14 mini-rockets of the salvo fanned out in full missile smoke and hid the plane
				# for about a second; a mini-rocket leaves a thin, short-lived trail
				st = [0.6, 2.0, 5.5, 0.5, 12.0 * lo, st[5]]
			if mm.has("tint"):   # связки: след своего цвета (бирюзовый, золотой…), но светлый
				st = st.duplicate()
				st[5] = (mm["tint"] as Color).lerp(Color.WHITE, 0.45)
			# S9-13: у своего самолёта след идёт ниже крыла (пуск — с пилонов под ним), выше — по мере удаления
			var ty := -2.0
			if arr_st[0] != pr.missiles and is_instance_valid(m.player):
				ty = lerpf(-12.0, -2.0, clampf(tail.distance_to(m.player.global_position) / 160.0, 0.0, 1.0))
			_trails.emit(int(mm["tid"]), Vector3(tail.x, ty, tail.y), st)


# ---------- тест 3.5-s5 (п. 11): пули и ракеты врагов в 3D ----------

## Ракеты врагов — модель (WeaponModels «enemy_msl») по курсу, пули — светящиеся трассеры с ореолом:
## красные у обычных врагов, оранжевые у асов, крупные шары — залпы асов и «Крепости». Всё — два MultiMesh
## (два вызова отрисовки на любое число снарядов). Трассеры и ореолы поверх моделей и облаков, как прежний слой боя.
const ESHOT_LEN := 30.0              # длина ракеты врага, px (картинка была 24)
const EGLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
// VFX-04: in Forward+ the white core goes above 1.0 (and the halo a little), so the HDR glow blooms tracers
uniform float hdr = 1.0;
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
	float lift = col.a > 0.99 ? 1.0 + (hdr - 1.0) * 0.3 : 1.0;   // dark underlays (alpha < 1) do not glow
	ALBEDO = mix(col.rgb * lift, vec3(1.0, 0.96, 0.92) * hdr, core * step(0.6, col.r + col.g));
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
		mat.set_shader_parameter("hdr", 2.6 if GpuFx.active() else 1.0)
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
	var mine := tracers_3d()
	var need_g := pr.ebullets.size() + pr.missiles.size() * 2 + (pr.bullets.size() * 2 if mine else 0)
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
		# S8 «eweap»: цвет, длина и толщина трассера — по виду оружия (Projectiles.eb_look)
		var lk := Projectiles.eb_look(b)
		var c: Color = lk[0]
		var ln: float = lk[1]
		var w: float = lk[2]
		var ctr := Vector3(p.x - dir.x * ln * 0.55, 1.0, p.y - dir.y * ln * 0.55)
		var xa := Vector3(dir.x, 0, dir.y) * ln
		var za := Vector3(-dir.y, 0, dir.x) * w
		gmx.set_instance_transform(n_g, Transform3D(Basis(xa, Vector3.UP, za), ctr))
		gmx.set_instance_color(n_g, c)
		lo = lo.min(ctr)
		hi = hi.max(ctr)
		n_g += 1
	# VFX-04: player tracers (Projectiles._draw look: dark underlay, warm glow, white core) drawn here in Forward+
	for b: Dictionary in (pr.bullets if mine else []):
		var p: Vector2 = b["p"]
		var v: Vector2 = b["v"]
		var dir := v.normalized() if v.length() > 1.0 else Vector2.RIGHT
		var ln := 34.0 if b.has("pierce") else 24.0
		var ctr := Vector3(p.x - dir.x * ln * 0.5, 1.2, p.y - dir.y * ln * 0.5)
		# long thin needle: the player's fire must not read like the short fat enemy tracers next to it
		var xa := Vector3(dir.x, 0, dir.y) * ln * 0.85
		gmx.set_instance_transform(n_g, Transform3D(Basis(xa, Vector3.UP, Vector3(-dir.y, 0, dir.x) * 3.6), ctr))
		gmx.set_instance_color(n_g, Color(0.1, 0.07, 0.03, 0.5))
		n_g += 1
		gmx.set_instance_transform(n_g, Transform3D(Basis(xa, Vector3.UP, Vector3(-dir.y, 0, dir.x) * 2.4), ctr + Vector3(0, 0.1, 0)))
		gmx.set_instance_color(n_g, Color(1.0, 0.62, 0.15, 1.0))
		n_g += 1
		lo = lo.min(ctr)
		hi = hi.max(ctr)
	for ms: Dictionary in pr.missiles:
		if float(ms.get("lev_hold", 0.0)) > 0.0:   # «Левиафан»: ракета ещё выходит из контейнера (LeviathanParts)
			continue
		var p: Vector2 = ms["p"]
		var v: Vector2 = ms["v"]
		var dir := v.normalized() if v.length() > 1.0 else Vector2.RIGHT
		var y := 0.0
		# S8 «eweap»: размер по виду ракеты — ПЗРК ×0,6, ракета самолёта ×1, ЗРК ×1,5 (модель, факел, ореол)
		var sk := float(Projectiles.MSL_SIZE.get(ms.get("k", "aam"), 1.0))
		var ln := ESHOT_LEN * sk
		var bs := Basis(Vector3.UP, -dir.angle()).scaled(Vector3.ONE * ln)
		var pos := Vector3(p.x, y, p.y)
		mmx.set_instance_transform(n_m, Transform3D(bs, pos))
		n_m += 1
		lo = lo.min(pos)
		hi = hi.max(pos)
		var lost: bool = ms["lost"]
		# факел двигателя у хвоста и красный ореол вокруг (у уведённой ловушкой — без ореола, факел тусклый)
		var tail := pos - Vector3(dir.x, 0, dir.y) * ln * 0.55
		var fl := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05 + float(n_m))
		var fk := sqrt(sk)   # факел и ореол растут медленнее корпуса: маленькая ракета ПЗРК всё равно заметна
		gmx.set_instance_transform(n_g, Transform3D(Basis(Vector3(-dir.x, 0, -dir.y) * 9.0 * fl * fk, Vector3.UP, Vector3(-dir.y, 0, dir.x) * 4.5 * fk), tail + Vector3(0, 1.0, 0)))
		gmx.set_instance_color(n_g, Color(1.0, 0.7, 0.25, 1.0 if not lost else 0.5))
		n_g += 1
		if not lost:
			gmx.set_instance_transform(n_g, Transform3D(Basis(Vector3(dir.x, 0, dir.y) * 20.0 * fk, Vector3.UP, Vector3(-dir.y, 0, dir.x) * 14.0 * fk), pos - Vector3(0, 0.5, 0)))
			gmx.set_instance_color(n_g, Color(1.0, 0.1, 0.05, 0.45))
			n_g += 1
	mmx.visible_instance_count = n_m
	gmx.visible_instance_count = n_g
	if n_m + n_g > 0:
		var aabb := AABB(lo - Vector3(40, 40, 40), hi - lo + Vector3(80, 80, 80))
		_eshot_mm.custom_aabb = aabb
		_eglow_mm.custom_aabb = aabb


const FX_CLEAR_R := 2.2      # clear zone radius, plane lengths (s13: 1.6 was not enough late in a run)
const FX_CLEAR_CUT := 0.85   # share of an effect's opacity taken away over the plane itself


## Kanta s12 (26.10): late in a run blasts, fire, missile smoke and the fan of a missile salvo hid the player's
## plane; only the lock ring showed where it was. Effects thin out over the plane (fx_clear_k in
## fx_exposure.gdshaderinc): this puts the plane's screen spot and size into the global shader parameter
func _sync_fx_clear(m: Main, vs: Vector2) -> void:
	var v := Vector4.ZERO
	var pu: Unit3D = _units.get(m.player.get_instance_id()) if is_instance_valid(m.player) else null
	if pu != null and pu.node != null and (pu.node as Node3D).visible and not (m.state in ["menu", "settings"]) \
			and vs.y > 1.0:
		var p3 := (pu.node as Node3D).global_position
		if not cam.is_position_behind(p3):
			var a := cam.unproject_position(p3)
			# model length 1 is the picture width, so the plane is k × picture width long in the world
			var ln := pu.k * (float(pu.tex.get_width()) if pu.tex != null else 1.0)
			var b := cam.unproject_position(p3 + cam.global_basis.x * ln * FX_CLEAR_R)
			v = Vector4(a.x / vs.x, a.y / vs.y, a.distance_to(b) / vs.y, FX_CLEAR_CUT)
	if v != _fx_clear:
		_fx_clear = v
		RenderingServer.global_shader_parameter_set(&"fx_clear", v)


# ---------- 3.4-t1: сбитый ведомый падает (п. 32) ----------

const CRASH_G := 300.0        # ускорение падения, пикс/с²
const WRECK_LIFE := 40.0      # сколько лежат обломки, с
const WRECK_MAX := 8


## Ведомый сбит (hp ≤ 0) — модель не удаляем, а роняем: дым, крен, удар о землю
func _start_crash(u: Unit3D) -> bool:
	if u.kind != "wing" or u.ref == null:
		return false
	var wm: Wingman = (u.ref as WeakRef).get_ref()
	if wm == null or wm.hp > 0.0:
		return false
	var root: Node3D = u.node
	if u.sh != null:
		(u.sh as Node3D).visible = false
	PlaneFx.update(u, 0.0, 0.0, false)
	var smoke := _make_smoke()
	smoke.position = root.position
	var dir := Vector2.from_angle(wm.heading)
	_crashes.append({"u": u, "p": Vector2(root.position.x, root.position.z), "y": root.position.y, "vy": -60.0,
		"v": dir * 260.0, "hd": wm.heading, "roll": float(u.bank), "spin": (2.0 + randf() * 2.0) * (1.0 if randf() < 0.5 else -1.0),
		"t": 0.0, "smoke": smoke})
	return true


func _sync_crashes(m: Main, sd: float) -> void:
	for i in range(_crashes.size() - 1, -1, -1):
		var c: Dictionary = _crashes[i]
		var u: Unit3D = c["u"]
		var root: Node3D = u.node
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
		var k: float = u.k
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
		for hub in (u.fx as Dictionary).get("props", []):
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


## Whether ground point g lies on a river (with margin r): effects that belong to dry land skip it
func is_water(g: Vector3, r: float) -> bool:
	return _on_water(g, r)


func _free_wreck(w: Dictionary) -> void:
	(w["n"] as Node).queue_free()
	if is_instance_valid(w["smoke"]):
		(w["smoke"] as Node).queue_free()


## Точка плоскости боя (y = 0), которая на экране совпадает с точкой мира g3 (обратное ground_under)
func _ground_to_combat(g3: Vector3) -> Vector2:
	var c := cam.global_position
	var k := c.y / maxf(c.y - g3.y, 1.0)
	return Vector2(c.x + (g3.x - c.x) * k, c.z + (g3.z - c.z) * k)


## VFX-03 (Forward+): burning wrecks and falling planes smoke with Boom3D's lit smoke (self-shadowed puffs, fire
## glow from below while fresh) instead of the flat unlit quad. CPUParticles3D gives INSTANCE_CUSTOM = (angle, phase),
## so only the tile (by instance) and the heat (first ~20 % of life) are filled in here.
func _wreck_smoke_mat() -> Material:
	var bb := Boom3D.BILLBOARD.replace("cd = INSTANCE_CUSTOM;",
		"cd = vec4(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, float(INSTANCE_ID % 4), (1.0 - smoothstep(0.0, 0.2, INSTANCE_CUSTOM.y)) * 0.9);")
	var sh := Shader.new()
	sh.code = Boom3D.SMOKE_SH % [Boom3D.COMMON, bb]
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("puff", Boom3D._puff)
	return mat


## Шлейф дыма с огнём у падающего самолёта: частицы в мировых координатах, поднимаются и расплываются
func _make_smoke() -> CPUParticles3D:
	# also replaces the flat material cached by a wreck that came before Boom3D made its puff texture
	if not _smoke_mat is ShaderMaterial and GpuFx.active() and Boom3D._puff != null:
		_smoke_mat = _wreck_smoke_mat()
	if _smoke_mat == null:
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = Fx._smoke_n[0] if not Fx._smoke_n.is_empty() else Fx._soft
		sm.vertex_color_use_as_albedo = true
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_smoke_mat = sm
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
	if _smoke_mat is ShaderMaterial:
		# VFX-03: lit smoke reads as a dark column only when it is taller and denser than the old flat quads
		s.lifetime = 3.2
		s.scale_amount_min = 34.0
		s.scale_amount_max = 56.0
		gr.colors = PackedColorArray([Color(1.0, 0.7, 0.3, 0.9), Color(0.6, 0.25, 0.08, 0.85), Color(0.1, 0.095, 0.09, 0.8), Color(0.22, 0.21, 0.2, 0.0)])
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
## Objects with no 3D picture: BiomeProps models them (rocks), or the ground shader paints them (o_crater, S14-10:
## the level crater picture stuck out of slopes as a floating slab)
const OBJ_SKIP_3D := ["o_mesa", "o_rocks_big", "o_rocks_small", "o_crater"]
var _wreck_scenes := {}   # вид обломков (BiomeProps.PLANE_KINDS) → PackedScene или null


func _wreck_scene(p: Vector2) -> PackedScene:
	var kind := BiomeProps.plane_kind(p)
	if not _wreck_scenes.has(kind):
		var path := BiomeProps.DIR + String(BiomeProps.KINDS[kind][0]) + ".glb"
		_wreck_scenes[kind] = load(path) if ResourceLoader.exists(path) else null
	return _wreck_scenes[kind]

const OBJ_RELIEF := {
	"o_rocks_big": [0.16, 0.45], "o_rocks_small": [0.18, 0.45], "o_mesa": [0.16, 0.25],
	"o_fort": [0.07, 0.35], "o_village": [0.05, 0.35], "o_oasis": [0.06, 0.5], "o_crater": [0.0, 0.0], "o_wreck": [0.04, 0.2],
}


## S9-07/S9-08: кишлаки вокруг области объектов собираем на месте в фоне (вода посёлка — в главном потоке)
func _prefetch_villages(bg: Background, area: Rect2) -> void:
	for key in _vtasks.keys():
		if WorkerThreadPool.is_task_completed(_vtasks[key]):
			WorkerThreadPool.wait_for_task_completion(_vtasks[key])
			_vtasks.erase(key)
	var CH := Background.CHUNK
	for cx in range(int(floorf(area.position.x / CH)), int(floorf(area.end.x / CH)) + 1):
		for cy in range(int(floorf(area.position.y / CH)), int(floorf(area.end.y / CH)) + 1):
			var key := Vector2i(cx, cy)
			if _objs.has(key) or _vtasks.has(key):
				continue
			var o := bg.chunk_object(cx, cy)
			if o.is_empty() or o["name"] != "o_village":
				continue
			var vr: int = o.get("var", absi(hash(key)) % 4)
			var water := terrain.village_water(o)
			if not AdobeBuild.has_at(vr, water):
				_vtasks[key] = WorkerThreadPool.add_task(AdobeBuild.village_at.bind(vr, water), false, "village_at")


func _sync_objects(c2: Vector2, h: float) -> void:
	var bg: Background = Main.I.background
	if bg == null or not bg.biome_ok:
		return
	var half := get_viewport().get_visible_rect().size / _zoom * 0.5 * ((h - GROUND_Y) / h) + Vector2(1500, 1500)   # 3.5-s8: кишлак ~2100 px
	var view := Rect2(c2 - half, half * 2.0)
	var seen := {}
	var CH := Background.CHUNK
	_prefetch_villages(bg, view.grow(CH))
	FortBuild.prefetch()   # FA-02: the fort mesh builds in the background before the first fort shows
	for cx in range(int(floorf(view.position.x / CH)), int(floorf(view.end.x / CH)) + 1):
		for cy in range(int(floorf(view.position.y / CH)), int(floorf(view.end.y / CH)) + 1):
			var key := Vector2i(cx, cy)
			var o := bg.chunk_object(cx, cy)
			if o.is_empty() or o["name"] in OBJ_SKIP_3D:
				continue
			if o["name"] == "o_fort" and not bg.forts_hit.has(FortView.key_of(o["pos"])):
				continue   # Kanta s13: a fort is only the «Укрепрайон» activity's (FortArea registers it), not scenery
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
					"o_fort":
						mi.mesh = FortBuild.mesh()   # FA-02: set Г, materials per surface
						mi.add_child(FortView.new(o["pos"]))   # FA-03: broken pieces, idle until this fort is hit
					"o_village":
						# S9-07/S9-08: застройка без дворов на воде, сады, поля и линия обороны — по ручью и реке посёлка
						if _vtasks.has(key):
							WorkerThreadPool.wait_for_task_completion(_vtasks[key])
							_vtasks.erase(key)
						var vm := AdobeBuild.village_at(vr, terrain.village_water(o))
						mi.mesh = vm[0]
						var em := MeshInstance3D.new()
						em.mesh = vm[1]
						em.material_override = AdobeBuild.material()
						mi.add_child(em)
						VillageHouses.attach(mi, vm[2])   # VIS-01: houses as models, one MultiMesh per variant
					_:
						mi.mesh = AdobeBuild.oasis(vr)
						OasisBuild.attach(mi, vr)   # the farmstead's houses, cistern and pergola as models
				if o["name"] != "o_fort":
					mi.material_override = AdobeBuild.material()
				mi.position = Vector3(o["pos"].x, gy - sz * 0.01, o["pos"].y)
				mi.basis = Basis(Vector3.UP, -float(o["rot"])).scaled(Vector3(sz, sz, sz))
				add_child(mi)
				_objs[key] = mi
				continue
			var wreck_ps: PackedScene = _wreck_scene(o["pos"]) if o["name"] == "o_wreck" else null
			if wreck_ps != null:
				# тест 3.5-s4 (п. 18): обломки — объёмный остов (tools/blender/plane_wreck.py), лежит по склону;
				# земля под ним не выравнивается (раньше — выдавленная картинка в круглой площадке)
				var sw := float(o["size"])
				var e := sw * 0.35
				var px: float = o["pos"].x
				var pz: float = o["pos"].y
				var yl := terrain.surface_fast(px - e, pz).y
				var yr := terrain.surface_fast(px + e, pz).y
				var yb := terrain.surface_fast(px, pz - e).y
				var yf := terrain.surface_fast(px, pz + e).y
				var nrm := Vector3(yl - yr, 2.0 * e, yb - yf).normalized()
				# Kanta 26.10: in a hollow the tilted hull still sank at its ends and the ground showed through it;
				# lift by how far the ground curves up above the slope through the centre
				var lift := maxf(0.0, maxf((yl + yr) * 0.5, (yb + yf) * 0.5) - gy)
				var wn: Node3D = wreck_ps.instantiate()
				wn.position = Vector3(px, gy + lift * 0.8 - sw * 0.005, pz)
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
	if Settings.gopt("effects") >= 1 and Tuning.g("cloud3d") > 0.5:
		for mi0: MeshInstance3D in _clouds:
			mi0.visible = false
		if _puffs == null:
			_puffs = CloudPuffs.new()
			add_child(_puffs)
			_puffs.set_sun(sun.global_transform.basis.z)   # Э-3: свет клубов — от солнца сцены
		_puffs.visible = true
		var focus := Vector3(c2.x, 0.0, c2.y)
		if title.active():   # заставка: растворяются над ведущим звена
			focus = ((title._units[0] as Unit3D).node as Node3D).global_position
		elif is_instance_valid(m.player):
			focus = Vector3(m.player.global_position.x, 0.0, m.player.global_position.y)
		_puffs.sync(its, cam, c2, h, focus, Settings.gopt("effects"), get_process_delta_time())
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
		# VFX-06: Forward+ shades lights in clusters, so it affords 3x the flashes of Compatibility
		for i in (24 if GpuFx.active() else 8):
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.62, 0.28)
			l.shadow_enabled = false
			if GpuFx.active():
				l.omni_attenuation = Boom3D.LIGHT_FALLOFF_FWD
			l.visible = false
			add_child(l)
			_lights.append({"l": l, "t": 0.0, "e": 0.0})
	var slot: Dictionary = _lights[_light_i % _lights.size()]
	_light_i += 1
	var l2: OmniLight3D = slot["l"]
	l2.position = Vector3(p.x, 60.0, p.y)
	l2.omni_range = clampf(size * 9.0, 140.0, 900.0)
	slot["e"] = clampf(size / 12.0, 1.5, 6.0) * (Boom3D.FLASH_GAIN_FWD if GpuFx.active() else 1.0)
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
	var dm := marks_as_decals()
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
		var fade := clampf(float(mk["life"]) / 6.0, 0.0, 1.0)
		if dm:
			# baked mark (dark core, ragged rim, soot rays), turned at random so neighbours differ
			var sr := r * 2.0
			_place_decal(_scorch_decals, i, Transform3D(Basis(Vector3.UP, float(mk.get("rot", 0.0))), pos),
				Vector3(sr, r * 1.2 + 16.0, sr), _scorch_tex(), Color(1, 1, 1, 0.95 * fade))
			continue
		mmx.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(r, 1, r)), pos))
		mmx.set_instance_color(i, Color(1, 1, 1, fade))
		lo = lo.min(pos - Vector3(r, 1, r))
		hi = hi.max(pos + Vector3(r, 1, r))
	mmx.visible_instance_count = 0 if dm else n
	_hide_decals(_scorch_decals, n if dm else 0)
	if n > 0 and not dm:
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
		var ln := plen * WeaponModels.drop_len(vt)
		mi.global_transform = Transform3D(bs.scaled(Vector3(ln, ln, ln)), pos)
	for id in _bombs3.keys():
		if not seen.has(id):
			(_bombs3[id] as Node).queue_free()
			_bombs3.erase(id)


## Тест 3.5-s7: метки на земле рисует шейдер земли (ground3d.gdshader, gz_*) — они лежат по рельефу.
## Порядок важности: прицел бомб → падающие бомбы → огонь на земле ближе к центру кадра.
const GZ_MAX := 24
const GZ_AIM := Color(1.0, 0.68, 0.28)
const GZ_WAIT := Color(0.8, 0.82, 0.8)
var _gz_a := PackedVector4Array()
var _gz_b := PackedVector4Array()
var _gz_c := PackedVector4Array()


## Земля рисует метки сама (иначе — плоскими кругами в слое боя, projectiles._draw)
func ground_zones_on() -> bool:
	return enabled and terrain != null and _ground_mat != null


## on_ground (BM-01, Kanta 20.10): метка прицела и падения бомб — в точке рельефа под a/b (как взрыв бомбы,
## Boom3D: ground_under) и в мировых координатах: кольцо лежит по склонам, а не висит плоским кругом на высоте боя
func _gz_add(a: Vector2, b: Vector2, r: float, alpha: float, kind: int, col: Color, on_ground := false) -> void:
	if _gz_a.size() >= GZ_MAX or alpha <= 0.01:
		return
	var w := 1.0
	if on_ground:
		var ga := ground_under(a)
		var gb := ga if b == a else ground_under(b)
		var ch := cam.global_position.y
		r *= clampf((ch - ga.y) / maxf(ch, 1.0), 0.5, 3.0)
		a = Vector2(ga.x, ga.z)
		b = Vector2(gb.x, gb.z)
		w = 0.0
	_gz_a.append(Vector4(a.x, a.y, b.x, b.y))
	_gz_b.append(Vector4(r, alpha, float(kind), fmod(absf(a.x * 0.013 + a.y * 0.007), 50.0)))
	_gz_c.append(Vector4(col.r, col.g, col.b, w))


## S9-26: пунктир от самолёта вниз к метке прицела — видно, что метка на земле, далеко под самолётом
## (штрихи в метрах мира: к земле мельчают с перспективой)
var _drop_mesh: ImmediateMesh
var _drop_mi: MeshInstance3D


func _drop_lines(lines: Array) -> void:
	if _drop_mi == null:
		_drop_mesh = ImmediateMesh.new()
		_drop_mi = MeshInstance3D.new()
		_drop_mi.mesh = _drop_mesh
		_drop_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_drop_mi.material_override = mat
		add_child(_drop_mi)
	_drop_mesh.clear_surfaces()
	if lines.is_empty():
		return
	_drop_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for ln in lines:
		var a: Vector3 = ln[0]
		var b: Vector3 = ln[1]
		var col: Color = ln[2]
		var L := a.distance_to(b)
		var dir := (b - a) / maxf(L, 0.01)
		var dash := 14.0
		var t := 0.0
		while t < L:
			var p0 := a + dir * t
			var p1 := a + dir * minf(t + dash * 0.55, L)
			var side := dir.cross(cam.global_position - p0).normalized() * 2.2
			var c := Color(col, col.a * (0.35 + 0.5 * t / L))   # к земле ярче
			for v in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
				_drop_mesh.surface_set_color(c)
				_drop_mesh.surface_add_vertex(v)
			t += dash
	_drop_mesh.surface_end()


func _sync_ground_zones(m: Main) -> void:
	if _ground_mat == null:
		return
	_gz_a.clear()
	_gz_b.clear()
	_gz_c.clear()
	var pl := m.player
	var drops: Array = []
	if is_instance_valid(pl) and pl.hp > 0.0:
		for g in pl.groups:
			var h: Hardpoint = g
			if not h.aiming:
				continue
			var ready := h.cd <= 0.0
			for z in h.aim_zones(pl):
				_gz_add(z[0], z[1], z[2], 1.0 if ready else 0.6, 0 if ready else 1, GZ_AIM if ready else GZ_WAIT, true)
				var zc: Vector2 = ((z[0] as Vector2) + (z[1] as Vector2)) * 0.5
				drops.append([Vector3(pl.global_position.x, 0.0, pl.global_position.y), ground_under(zc), Color(GZ_AIM if ready else GZ_WAIT, 0.8)])
	_drop_lines(drops)
	var pr := m.projectiles
	if pr != null:
		var rk := pr.aoe_r_k()
		for i in range(pr.bombs.size() - 1, -1, -1):
			var b: Dictionary = pr.bombs[i]
			var k := 1.0 - float(b["t"]) / maxf(float(b["fuse"]), 0.01)
			_gz_add(b["to"], b["to"], float(b["r"]) * rk, 0.3 + 0.6 * k, 2, GZ_AIM, true)
		var fl: Array = pr.fires.duplicate()
		if fl.size() > GZ_MAX - _gz_a.size():
			fl.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
				return (x["p"] as Vector2).distance_squared_to(_c2) < (y["p"] as Vector2).distance_squared_to(_c2))
		for f: Dictionary in fl:
			var fc: Color = f.get("c", Color(1.0, 0.45, 0.1))
			_gz_add(f["p"], f["p"], float(f["r"]), clampf(float(f["t"]), 0.0, 1.0), 3, fc)
	_ground_mat.set_shader_parameter("gz_n", _gz_a.size())
	if _gz_a.is_empty():
		return
	_gz_a.resize(GZ_MAX)
	_gz_b.resize(GZ_MAX)
	_gz_c.resize(GZ_MAX)
	_ground_mat.set_shader_parameter("gz_a", _gz_a)
	_ground_mat.set_shader_parameter("gz_b", _gz_b)
	_ground_mat.set_shader_parameter("gz_c", _gz_c)
	_ground_mat.set_shader_parameter("gz_cam", cam.global_position)
	_ground_mat.set_shader_parameter("gz_time", Time.get_ticks_msec() * 0.001)
	_ground_mat.set_shader_parameter("gz_v2", Tuning.g("fx_s14") >= 1.0)


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
	var dm := marks_as_decals()
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
		var fade := clampf(float(c["life"]) / float(c.get("fd", Fx.FxGround.CRATER_FADE)), 0.0, 1.0)
		if dm:
			_place_decal(_crater_decals, i, Transform3D(xf.basis.orthonormalized(), xf.origin), Vector3(rr * 2.0, rr * 1.5 + 16.0, rr * 2.0),
				_crater_mat.albedo_texture, Color(1, 1, 1, fade))
			continue
		mmx.set_instance_transform(i, xf)
		mmx.set_instance_color(i, Color(1, 1, 1, fade))
		lo = lo.min(xf.origin - Vector3(rr, rr, rr))
		hi = hi.max(xf.origin + Vector3(rr, rr, rr))
	mmx.visible_instance_count = 0 if dm else cnt
	_hide_decals(_crater_decals, cnt if dm else 0)
	if cnt > 0 and not dm:
		_crater_mm.custom_aabb = AABB(lo, hi - lo)


## VFX-06: in Forward+ craters and scorch are Decals projected onto the relief, so they wrap a curved slope
## instead of a flat quad that floats over a hollow or sinks into a bump; Compatibility has no decals and
## keeps the quads. Decals take the scene light, so a crater is lit by the sun like the ground around it.
func marks_as_decals() -> bool:
	return GpuFx.active()


## Puts decal i of pool (creating it on first use) at xf with box size sz, texture tex and colour col
func _place_decal(pool: Array[Decal], i: int, xf: Transform3D, sz: Vector3, tex: Texture2D, col: Color) -> void:
	while pool.size() <= i:
		var d := Decal.new()
		d.cull_mask = Terrain3D.DECAL_LAYER   # ground only: not the wreck lying in the scorch
		d.upper_fade = 0.15
		d.lower_fade = 0.6
		add_child(d)
		pool.append(d)
	var dc := pool[i]
	# S14-19 (R-22 toggle fx_s14): a decal box projects along its Y axis, so a cliff wall inside the box got
	# the mark smeared down it as streaks («кусок взрыва в горе»); normal fade 0.5 hides surfaces at 90° to the
	# decal and keeps ordinary slopes (30° off the decal axis keeps ~95 %)
	dc.normal_fade = 0.5 if Tuning.g("fx_s14") >= 1.0 else 0.0
	dc.visible = col.a > 0.004
	dc.transform = xf
	dc.size = sz
	if dc.texture_albedo != tex:
		dc.texture_albedo = tex
	dc.modulate = col


## VFX-06: blast scorch decal baked by game/tools/vfx_bake/make_scorch.py: near-black middle fading to burnt
## soil, ragged rim and soot rays, so a mark reads as a blast and not as a soft round shadow
func _scorch_tex() -> Texture2D:
	if _scorch_decal_tex == null:
		_scorch_decal_tex = load("res://art/vfx/scorch.png")
	return _scorch_decal_tex


## Hides decals of pool from index `from` on (marks that ended)
func _hide_decals(pool: Array[Decal], from: int) -> void:
	for i in range(from, pool.size()):
		pool[i].visible = false

