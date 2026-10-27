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
const DIST0 := 1.15   # тест 3.5-s4 / Т-10: камера ближе — самолёт ~70% ширины вида (было 1.4)

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var rect := Rect2()          # где на экране (в координатах ctrl) нарисован вид
var lvl_rects: Array = []    # [Rect2, ур.] — переключатель «Ур. 1 / Ур. 2»
var view_lvl := 1
## Стенд --hangarevo: оружие в пустых группах (класс → [оружие по группам]), чтобы показать все эволюции
static var bench_weapons := {}
static var bench_pitch_min := -0.2   # стенд: камера ниже обычного (тест 3.5-s5, п. 3 — открытый бомбоотсек снизу)
static var bench_seeker := 0   # Т-3: стенд --modules — «Глазастик» на ракетах
## Bench --hangarweaptab: weapon shown on the weapons tab even if it is not in the class list (PG-01 frames)
static var bench_tab_w := ""
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
var _built_lvl := 1          # plane level of the model on view (model_key)
## Kanta 24.10: real stands from Sketchfab (CC BY, CREDITS.md) instead of box stands. Per weapon, shares of the stand
## model (measured on it): x — weapon centre from the stand centre (of its length), y — weapon bottom over the floor
## (of its height). Size: len — stand length per weapon length, or ring — inner radius of the stand's rings (of its
## length), so the missile body fills them. slots — across offsets (of its length) of the missiles it holds, one
## missile in each; mid — y is the missile axis; cradle — beam on the plate the weapon is strapped to (of its length),
## band — strap arc in degrees (open at the top for a pod with a suspension beam, S11-03); pod — the weapon is a round
## pod with a beam on top, so its width, not its height, sizes the body;
## view — weapon scale so the stand fits the view; body — the weapon lies on its body, not on its fin tips
## (fins wider than the body hang beside the cradles, 3.5-s12: the HE bomb floated); turn — the weapon is turned
## lengthwise on the stand and the stand is stretched along it to `len` of the weapon, its width to `wide` of the
## weapon's depth (Kanta 26.10 «растяни её»: the carpet row of eight bombs on the bomb cart).
## The bomb cart lost its floating discs and reflectors (glb_drop_parts.py), so y counts to its cradle tops.
const STAND_CART := "res://models/hangar/stand_cart.glb"
const STAND_BOMB := {"path": STAND_CART, "len": 1.05, "x": 0.0, "y": 0.95, "view": 1.0}
## 3.5-s12 (Kanta: «модерниз. — на кирпичах»): every evolved weapon stands on a real stand too
const STAND_LOADER := {"path": "res://models/hangar/stand_loader.glb", "len": 1.6, "x": 0.44, "y": 0.854, "cradle": 0.13, "view": 0.5}
const STANDS_EVO := {
	"aam": STAND_LOADER,
	"rockets": {"path": STAND_CART, "len": 1.15, "x": 0.0, "y": 0.97, "view": 0.85},
	"flares": {"path": STAND_CART, "len": 1.25, "x": 0.0, "y": 1.0, "view": 0.8},
	"bombs": {"path": STAND_CART, "len": 1.04, "x": 0.0, "y": 0.95, "view": 1.0, "turn": true, "wide": 1.15},
}
const MISSILE_CART := {"path": "res://models/hangar/stand_missile_cart.glb", "ring": 0.052, "x": 0.0, "y": 0.863,
	"mid": true, "slots": [-0.2317, 0.2475], "view": 0.8}
const STANDS := {
	"hebomb": {"path": STAND_CART, "len": 1.05, "x": 0.0, "y": 0.95, "view": 0.72, "body": true},
	"flares": {"path": STAND_CART, "len": 1.25, "x": 0.0, "y": 0.86, "view": 0.85},   # the cassette nests into the cradle saddles
	"aam": MISSILE_CART,
	"srm": MISSILE_CART,
	"agm": STAND_LOADER,
	"rockets": {"path": "res://models/hangar/stand_loader.glb", "len": 1.6, "x": 0.44, "y": 0.854, "cradle": 0.13, "view": 0.5, "band": 240.0,
		"pod": true},
}
## Floor of the weapon store in the weapon view (box stands went from here up to the weapon)
const FLOOR_Y := -0.2
## S11-13 (Kanta: the turret "hangs in the air"): in the weapon store the turret sits on its ring mount
## in a fuselage skin section on a wheeled frame (tools/blender/turret_stand.py). seat_r / seat_y - the
## flange top's radius and height in the stand model; view - turret scale so the stand fits the view;
## lift - the camera aims at this share of the pair's height over the floor.
const TURRET_STAND := {"path": "res://models/hangar/stand_turret.glb", "seat_r": 1.0, "seat_y": 1.75,
	"view": 0.55, "lift": 0.5}
var turret_pos: Array = []   # [Vector3, сторона] — турели текущей модели
var _model: Node3D           # S13: the plane model of the view; flush flare panels and turret fairings go under it
## Тест 3.5-s8: показ механизации (HangarAnim) — кнопка на виде самолёта или курсор на узле «Крыло»
var mech_demo := false
var mech_hover := false      # HudHangar ставит каждый кадр, пока курсор на узле «Крыло»
var mech_rect := Rect2()     # кнопка «Механизация» на виде (в координатах ctrl)
static var anim_time := -1.0   # стенд --mechanim: момент анимации задан (≥ 0), а не по часам
var _anim := {}
var _anim_key := ""
var _env: Environment
var _key_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
var _fill_light: DirectionalLight3D   # S9-03: заполняющий свет склада (только вкладка «ОРУЖИЕ»)
var _flight_bg: Node3D       # п. 32: облака под самолётом плывут назад — «полёт»
var _store_bg: Node3D        # п. 32: склад вооружения — пол, стеллажи, ящики
var _bg := ""
var _t := 0.0


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
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	# тест 3.5-s4 (п. 1, 32): свет без пересвета сверху; фон — полёт в небе (самолёт) или склад (оружие)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 1.6
	var sky := Sky.new()
	var skm := ShaderMaterial.new()
	var sks := Shader.new()
	sks.code = SKY_SHADER
	skm.shader = sks
	sky.sky_material = skm
	_env.sky = sky
	we.environment = _env
	vp.add_child(we)
	_key_light = DirectionalLight3D.new()
	_key_light.light_color = Color(1.0, 0.94, 0.85)
	_key_light.shadow_enabled = true
	# сбоку-спереди, а не сверху: верх светлой окраски не выбеливается при взгляде сверху
	_key_light.basis = Basis.looking_at(Vector3(0.55, -0.55, -0.62).normalized(), Vector3.UP)
	vp.add_child(_key_light)
	_rim_light = DirectionalLight3D.new()
	_rim_light.light_color = Color(0.6, 0.72, 1.0)
	_rim_light.light_energy = 0.4
	_rim_light.basis = Basis.looking_at(Vector3(-0.6, -0.2, 0.75).normalized(), Vector3.UP)
	vp.add_child(_rim_light)
	# S9-03: с противоположной от ключевого стороны, сверху, без теней — теневая сторона оружия не проваливается
	_fill_light = DirectionalLight3D.new()
	_fill_light.light_color = Color(0.92, 0.94, 1.0)
	_fill_light.light_specular = 0.0   # без бликов: только мягко поднимает тень
	_fill_light.basis = Basis.looking_at(Vector3(-0.5, -0.75, 0.45).normalized(), Vector3.UP)
	vp.add_child(_fill_light)
	_flight_bg = _make_flight_bg()
	vp.add_child(_flight_bg)
	_store_bg = _make_store_bg()
	vp.add_child(_store_bg)
	_set_bg("flight")
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.02
	cam.far = 30.0
	vp.add_child(cam)
	cam.current = true


## Тест 3.5-s4 (п. 32): небо для вида «полёт» — от дымки у горизонта к синеве в зените, мягкое солнце.
## s13 (Kanta: «фон квадратами, сделай правдоподобное небо с облаками»): below the horizon the plane now flies
## over a sea of cumulus tops (lit from the sun, blue-grey in the hollows, fading into haze far off) instead of a
## flat grey; the colours go through SRGB(), so Forward+ no longer washes them out to grey
const SKY_SHADER := """
shader_type sky;
#include "res://shaders/srgb.gdshaderinc"
#include "res://shaders/hangar_clouds.gdshaderinc"
void sky() {
	float h = EYEDIR.y;
	vec3 haze = SRGB(vec3(0.76, 0.82, 0.89));
	vec3 zen = SRGB(vec3(0.22, 0.42, 0.72));
	vec3 c = mix(haze, zen, smoothstep(0.0, 0.65, h));
	vec3 sd = normalize(vec3(-0.55, 0.55, 0.62));
	if (h < 0.02) {
		// cloud sea 1 unit below the eye, seen to the horizon
		float d = 1.0 / max(-h + 0.035, 0.035);
		vec2 p = EYEDIR.xz * d * 0.55 + vec2(cloud_time(TIME, 0.06), 0.0);
		vec3 cl = cloud_col(p, normalize(sd.xz), 0.47);
		float far = smoothstep(4.0, 26.0, d);
		c = mix(cl, haze, far);
	}
	float sun = max(dot(EYEDIR, sd), 0.0);
	c += SRGB(vec3(1.0, 0.9, 0.7)) * (pow(sun, 400.0) * 1.5 + pow(sun, 12.0) * 0.12);
	COLOR = c;
}
"""
## Слой облаков под самолётом: шумовые клочья плывут назад (самолёт летит носом +X), к краю тают.
## s13: the same cumulus look as the cloud sea of the sky, so the near layers drift over it without a seam
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://shaders/srgb.gdshaderinc"
#include "res://shaders/hangar_clouds.gdshaderinc"
uniform float speed = 0.35;
uniform float scale = 0.55;
uniform float cover = 0.5;
uniform float alpha_k = 0.9;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * scale + vec2(cloud_time(TIME, speed), 0.0);
	float n = cloud_fbm(p);
	float a = smoothstep(cover, cover + 0.22, n);
	float edge = 1.0 - smoothstep(4.0, 11.0, length(wp.xz));
	ALBEDO = cloud_col(p, normalize(vec2(-0.55, 0.62)), cover);
	ALPHA = a * edge * alpha_k;
}
"""


func _make_flight_bg() -> Node3D:
	var n := Node3D.new()
	for l: Array in [[-0.9, 0.42, 0.62, 0.58, 0.55], [-2.2, 0.22, 0.32, 0.55, 0.7]]:   # высота, скорость, масштаб, покрытие, прозрачность
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(24, 24)
		mi.mesh = pm
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = CLOUD_SHADER
		sm.shader = sh
		sm.set_shader_parameter("speed", l[1])
		sm.set_shader_parameter("scale", l[2])
		sm.set_shader_parameter("cover", l[3])
		sm.set_shader_parameter("alpha_k", l[4])
		mi.material_override = sm
		mi.position.y = l[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	return n


## Склад вооружения: бетонный пол с разметкой, по кругу — стеллажи с ящиками и бомбами (вид с любой стороны)
func _make_store_bg() -> Node3D:
	var n := Node3D.new()
	var mats := {}
	for k: String in ["floor", "metal", "olive", "wood", "line", "wall"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = {"floor": Color(0.23, 0.23, 0.22), "metal": Color(0.3, 0.32, 0.34), "olive": Color(0.28, 0.31, 0.22),
			"wood": Color(0.42, 0.32, 0.2), "line": Color(0.75, 0.6, 0.12), "wall": Color(0.16, 0.16, 0.17)}[k]
		m.roughness = 0.85 if k != "metal" else 0.5
		m.metallic = 0.5 if k == "metal" else 0.0
		mats[k] = m
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	fl.mesh = pm
	fl.material_override = mats["floor"]
	fl.position.y = -0.2
	n.add_child(fl)
	var add := func(size: Vector3, pos: Vector3, mat: String, rot := 0.0) -> void:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		b.mesh = bm
		b.material_override = mats[mat]
		b.position = pos
		b.rotation.y = rot
		n.add_child(b)
	# разметка: квадрат стоянки под оружием
	for i in 4:
		var a := i * PI / 2.0
		add.call(Vector3(1.3, 0.002, 0.03), Vector3(cos(a) * 0.65, -0.199, sin(a) * 0.65), "line", a + PI / 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	for i in 10:
		var a := TAU * i / 10.0
		var c := Vector3(cos(a), 0, sin(a)) * 2.9
		var rot := -a + PI / 2.0
		var side := Vector3(-sin(a), 0, cos(a))
		for py: float in [-0.2, 0.25, 0.7, 1.15]:   # полки
			add.call(Vector3(1.6, 0.035, 0.55), c + Vector3(0, py, 0), "metal", rot)
		for sx: float in [-0.78, 0.78]:   # стойки
			for sz: float in [-0.25, 0.25]:
				add.call(Vector3(0.04, 1.45, 0.04), c + side * sx + Vector3(cos(a), 0, sin(a)) * sz + Vector3(0, 0.5, 0), "metal", rot)
		for py: float in [-0.2, 0.25, 0.7]:   # ящики на полках
			var x := -0.65
			while x < 0.6:
				var w := rng.randf_range(0.22, 0.42)
				var h := rng.randf_range(0.14, 0.32)
				add.call(Vector3(w, h, 0.42), c + side * (x + w / 2.0) + Vector3(0, py + 0.02 + h / 2.0, 0), "olive" if rng.randf() < 0.7 else "wood", rot)
				x += w + rng.randf_range(0.04, 0.12)
		add.call(Vector3(0.1, 2.2, 6.0), c * 1.35 + Vector3(0, 0.9, 0), "wall", rot + PI / 2.0)   # стена за стеллажами
	return n


## S9-03: свет склада (вкладка «ОРУЖИЕ»)
const STORE_KEY := 0.62
const STORE_FILL := 0.25
const STORE_AMBIENT := 0.36
const STORE_WHITE := 4.0
const STORE_EXPOSURE := 1.0
const GLOW_THRESHOLD := 1.6   # flight background: glow only above this HDR level (the flame core, not the sky)
## S9-04: поворот турели на вкладке «ОРУЖИЕ» (рад): при виде по умолчанию (YAW0) стволы — к зрителю под ~55°
const TURRET_SHOW_YAW := 1.35


func _set_bg(mode: String) -> void:
	if mode == _bg:
		return
	_bg = mode
	var fly := mode == "flight"
	_flight_bg.visible = fly
	_store_bg.visible = not fly
	_env.background_mode = Environment.BG_SKY if fly else Environment.BG_COLOR
	_env.background_color = Color(0.06, 0.06, 0.065)
	# S9-03: на складе окружающий свет нейтральный (тёплый 0,75/0,68/0,58 желтил оливковую краску до кремовой)
	_env.ambient_light_color = Color(0.6, 0.68, 0.82) if fly else Color(0.66, 0.66, 0.66)
	_env.ambient_light_energy = 0.5 if fly else STORE_AMBIENT
	_key_light.light_color = Color(1.0, 0.94, 0.85) if fly else Color(1.0, 0.96, 0.91)
	_key_light.light_energy = 1.0 if fly else STORE_KEY
	_key_light.shadow_enabled = not fly   # в полёте тени на «пол» нет — пола нет
	# S9-03 (Kanta 23.10: «оружие засвечено, выглядит неестественно»): на складе засвет давал свет, а не материал —
	# ключевой 0,95 скользящим лучом при «белой точке» тонемаппера 1,6 выбеливал освещённые грани (олива → крем),
	# холодный контровой 0,4 давал голубые блики на металле пилона, а теневая сторона проваливалась в черноту.
	# Теперь: ключевой слабее, мягкий заполняющий без бликов, контровой слабый и нейтральный,
	# окружающий нейтральный, тонемаппер с запасом по светам (белая точка 4 вместо 1,6 — света не «выгорают»)
	_rim_light.light_energy = 0.4 if fly else 0.12
	_rim_light.light_color = Color(0.6, 0.72, 1.0) if fly else Color(0.85, 0.88, 0.95)
	_rim_light.light_specular = 0.5 if fly else 0.2
	_fill_light.visible = not fly
	_fill_light.light_energy = STORE_FILL
	_env.tonemap_white = 1.6 if fly else STORE_WHITE
	_env.tonemap_exposure = 1.0 if fly else STORE_EXPOSURE
	# Kanta 25.10: the nozzle flame (NozzleFlame) blooms in the showcase; only HDR-bright pixels glow, so the
	# sky and the paint stay as they were
	_env.glow_enabled = fly
	_env.glow_hdr_threshold = GLOW_THRESHOLD
	_env.glow_intensity = 0.45
	_env.glow_bloom = 0.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE


## Каждый кадр, пока открыта вкладка «САМОЛЁТ»: какой самолёт показать и где
func show_plane(cls_id: String, r: Rect2) -> Texture2D:
	if cls_id != _cls:
		_cls = cls_id
		view_lvl = Profile.plane_lvl(cls_id)   # S9-02: открываем тот самолёт, на котором летаем
	rect = r
	_drawn_frame = Engine.get_process_frames()
	_fit_vp(r)
	_set_bg("flight")
	var k := "%s_%d_%d_%s" % [cls_id, view_lvl, weapon_tier, Livery.current(cls_id)]   # п. 35: и окраска
	if k != _key:
		if _key.begins_with("w_"):
			_dist = DIST0
			focus = Vector3.ZERO   # the turret on its mount stand aims the camera higher (S11-13)
		_key = k
		_build(cls_id, view_lvl)
	return vp.get_texture()


## Тест 3.5-s3 («текстуры в ангаре — идеально»): вид рисуется с запасом по разрешению — в пикселях экрана
## (при растяжении окна) × SUPERSAMPLE и сжимается в рамку: текстура модели чётче, края без лесенки
const SUPERSAMPLE := 1.5
## Bench (--hcam close-ups, S11): supersample factor instead of SUPERSAMPLE, so saved close-ups are large; 0 — off
static var bench_supersample := 0.0


func _fit_vp(r: Rect2) -> void:
	var ss := bench_supersample if bench_supersample > 0.0 else SUPERSAMPLE
	var k := ss * maxf(1.0, _ctrl.get_viewport().get_final_transform().get_scale().x) if _ctrl != null else ss
	k = minf(k, 3200.0 / maxf(r.size.x, 1.0))
	var sz := Vector2i(maxi(64, int(r.size.x * k)), maxi(64, int(r.size.y * k)))
	if vp.size != sz:
		vp.size = sz
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Тест 3.5-s3: вкладка «ОРУЖИЕ» — то же оружие объёмной моделью, крупно, со ступенями 1 / 3 / 5 и модернизацией
## (подвесное — на пилоне, как под крылом; турель — класса, выбранного в ангаре)
func show_weapon(cls_id: String, weapon: String, r: Rect2) -> Texture2D:
	rect = r
	_drawn_frame = Engine.get_process_frames()
	_fit_vp(r)
	_set_bg("store")
	var k := "w_%s_%s_%d" % [cls_id, weapon, weapon_tier]
	if k != _key:
		if not _key.begins_with("w_"):
			_yaw = YAW0
			_pitch = 0.25
			_dist = 1.0
			focus = Vector3.ZERO
		_key = k
		_cls = ""   # при возврате на «САМОЛЁТ» модель соберётся заново
		for c in pivot.get_children():
			c.queue_free()
		turret_pos.clear()
		var evo := weapon_tier == 4
		var t := mini(weapon_tier, 3)
		# Kanta 24.10: the weapon itself on the stands, without the pylon that holds it on the wing
		var on_mount := weapon == "turret" and ResourceLoader.exists(TURRET_STAND["path"])
		# S11-13: on the mount stand the stand is the ring mount: no collar from the plane
		var side := ("mount" if on_mount else "top") if weapon == "turret" else ""
		if evo and weapon in ["flares"]:
			side = "top"
		elif evo and weapon == "bombs":
			side = ""
			if WeaponModels.has_bay(cls_id, 1):   # тест 3.5-s5 (п. 3): у «Кита» «ковёр» — кассета бомбоотсека
				t = WeaponModels.CARPET_BAY_T
		if weapon == "bombs" and not evo:   # тест 3.5-s8: калибр по уровню вкладки (ур. 1 / 3 / 5 → «50» / «250» / «1000»)
			t = WeaponModels.bomb_t([1, 3, 5][t - 1])
		var wmi := WeaponModels.make(weapon, t, side, cls_id, evo, 1, true)
		# во весь вид по габариту модели («Бабушкин ковёр» поперёк полёта шире, чем длинный)
		var bb := wmi.mesh.get_aabb()
		var s := (0.62 if weapon != "turret" else 1.05) / maxf(1.0, maxf(bb.size.x, bb.size.z))
		var stand: Dictionary = STANDS.get(weapon, STAND_BOMB if Weapons.is_bomb(weapon) else {})
		if evo:
			stand = STANDS_EVO.get(weapon, {})
			if weapon == "bombs" and t == WeaponModels.CARPET_BAY_T:
				stand = STAND_BOMB   # the bomber's bay cassette is already long: it lies along the cart as it is
		if not ResourceLoader.exists(stand.get("path", "")):
			stand = {}
		s *= stand.get("view", 1.0)
		if on_mount:
			s *= float(TURRET_STAND["view"])
		# турель — в одном масштабе на всех ступенях (модель меньше 1 — множитель не зависит от габарита),
		# поэтому рост ступени виден; S9-04: стоит неподвижно, стволами вперёд-вбок к камере (3/4 спереди)
		var rot := TURRET_SHOW_YAW if weapon == "turret" else (PI / 2.0 if stand.get("turn", false) else 0.0)
		wmi.basis = Basis(Vector3.UP, rot).scaled(Vector3.ONE * s)
		var c := Basis(Vector3.UP, rot) * (bb.get_center() * s)
		wmi.position = Vector3(-c.x, -0.03 if side == "under" else (-0.15 if weapon == "turret" else -0.08), -c.z)
		pivot.add_child(wmi)
		# п. 32: на складе оружие лежит на двух ложементах-подставках от пола до низа модели
		var bottom := wmi.position.y + bb.position.y * s
		var on_cart := false
		if not stand.is_empty():
			on_cart = _place_on_stand(wmi, bb, s, bottom, stand)
		focus = Vector3.ZERO
		if on_mount:
			_place_on_mount(wmi, s, bottom)
		if weapon != "turret" and not on_cart and bottom > -0.19:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.32, 0.34, 0.3)
			sm.metallic = 0.1   # S9-03: крашеные ложементы — матовые
			sm.roughness = 0.88
			for sx: float in [-0.17, 0.17]:
				var st := MeshInstance3D.new()
				var bx := BoxMesh.new()
				bx.size = Vector3(0.035, bottom + 0.2, minf(0.12, bb.size.z * s * 0.8 + 0.02))
				st.mesh = bx
				st.material_override = sm
				st.position = Vector3(sx, (bottom - 0.2) * 0.5, 0)
				pivot.add_child(st)
	return vp.get_texture()


## Puts the stand under the weapon `wmi` (mesh box `bb`, scale `s`, lowest point `bottom`) as `stand` describes
## (STANDS): on the cradle, in the rings (a second missile in the next ring pair) or strapped to the loader plate.
## The weapon and the stand move apart by half the cradle offset each, so the pair is centred in the view.
func _place_on_stand(wmi: MeshInstance3D, bb: AABB, s: float, bottom: float, stand: Dictionary) -> bool:
	var cart := WeaponModels._glb_mesh(stand["path"], 1.0, Color(), stand["path"].get_file().get_basename())
	if cart == null:
		return false
	var cb := cart.get_aabb()
	# a pod is round, but its suspension beam on top lifts the box centre: its width gives the body
	var pod: bool = stand.get("pod", false)
	var body := (bb.size.z * 0.5 if pod else _body_radius(wmi.mesh)) * s
	var turn: bool = stand.get("turn", false)
	var lx := (bb.size.z if turn else bb.size.x) * s   # the weapon's length along the stand
	var ck: float = (body / stand["ring"] if stand.has("ring") else lx * stand["len"]) / cb.size.x
	var cw := ck   # across and up: the stand keeps its proportions unless it is stretched along a turned weapon
	if turn:
		cw = bb.size.x * s * float(stand.get("wide", 1.0)) / cb.size.z
	var cm := MeshInstance3D.new()
	cm.mesh = cart
	cm.basis = Basis.from_scale(Vector3(ck, cw, cw))
	var dx: float = cb.size.x * stand["x"] * ck
	cm.position = Vector3(-cb.get_center().x * ck - dx * 0.5, FLOOR_Y - cb.position.y * cw, -cb.get_center().z * cw)
	pivot.add_child(cm)
	wmi.position.x += dx * 0.5
	var axis := wmi.position.y + (bb.position.y + bb.size.z * 0.5 if pod else bb.get_center().y) * s
	var low := bottom
	if stand.get("body", false):
		low = axis - _body_radius(wmi.mesh) * s
	elif stand.get("mid", false):
		low = axis
	elif stand.has("cradle"):
		low = axis - body * 1.52   # beam 0.35 and saddles 0.25 of the body radius; the beam sits 0.08 into the plate
	var lift: float = FLOOR_Y + cb.size.y * cw * stand["y"] - low
	wmi.position.y += lift
	axis += lift
	var slots: Array = stand.get("slots", [])
	var z0 := wmi.position.z
	for i in slots.size():
		var w := wmi if i == 0 else wmi.duplicate() as MeshInstance3D
		w.position.z = z0 + float(slots[i]) * cb.size.x * ck
		if i > 0:
			pivot.add_child(w)
	if stand.has("cradle"):
		_cradle(Vector3(wmi.position.x + bb.get_center().x * s, axis, wmi.position.z + bb.get_center().z * s),
			body, float(stand["cradle"]) * cb.size.x * ck, float(stand.get("band", 360.0)))
	return true


## S11-13: seats the turret `wmi` (view scale `s`, lowest point `bottom`) on the ring mount stand
## (TURRET_STAND): the stand's flange fits the turret's own base ring, its wheels stand on the store floor
## and the turret is raised onto the flange; the camera aims at the middle of the pair.
func _place_on_mount(wmi: MeshInstance3D, s: float, bottom: float) -> void:
	var path: String = TURRET_STAND["path"]
	var stand := WeaponModels._glb_mesh(path, 1.0, Color(), path.get_file().get_basename())
	if stand == null:
		return
	var ck := _base_radius(wmi.mesh) * s / float(TURRET_STAND["seat_r"])
	wmi.position.y += FLOOR_Y + float(TURRET_STAND["seat_y"]) * ck - bottom
	# the turret origin is the centre of its base ring; the stand's fuselage runs along the barrels
	var sm := MeshInstance3D.new()
	sm.mesh = stand
	sm.basis = Basis(Vector3.UP, TURRET_SHOW_YAW).scaled(Vector3.ONE * ck)
	sm.position = Vector3(wmi.position.x, FLOOR_Y, wmi.position.z)
	pivot.add_child(sm)
	var top := wmi.position.y + wmi.mesh.get_aabb().end.y * s
	# the turret mesh box is centred on x, z (show_weapon), so the camera stays on that vertical
	focus = Vector3(0.0, FLOOR_Y + (top - FLOOR_Y) * float(TURRET_STAND["lift"]), 0.0)


## Radius of a turret mesh's base ring: the widest vertex from the vertical axis in its lowest tenth.
func _base_radius(m: Mesh) -> float:
	var bb := m.get_aabb()
	var lim := bb.position.y + bb.size.y * 0.1
	var r := 0.0
	for si in m.get_surface_count():
		var verts: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y <= lim:
				r = maxf(r, Vector2(v.x, v.z).length())
	return r if r > 0.0 else bb.size.z * 0.4


## Cradle on the loader plate (Kanta 24.10: the missile is held, not laid): a beam `span` long under the weapon
## body (radius `r`, axis at `axis`), a saddle at each end and a strap round the body over each saddle.
## `band` is the strap's arc in degrees from the bottom: 360 closes it, less leaves the top free for a pod's
## suspension beam (S11-03: a full ring would cut through it).
func _cradle(axis: Vector3, r: float, span: float, band := 360.0) -> void:
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.58, 0.62, 0.66)   # the loader's own grey: the cradle reads as part of it
	sm.metallic = 0.3   # painted steel, matte (Kanta 19.10)
	sm.roughness = 0.8
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(span, r * 0.35, r * 0.9)
	beam.mesh = bm
	beam.material_override = sm
	beam.position = axis + Vector3(0, -r * 1.425, 0)
	pivot.add_child(beam)
	for sx: float in [-0.45, 0.45]:
		var strap := MeshInstance3D.new()
		if band >= 360.0:
			var tm := TorusMesh.new()
			tm.inner_radius = r * 1.0
			tm.outer_radius = r * 1.16
			strap.mesh = tm
			strap.basis = Basis(Vector3.BACK, PI / 2.0)
		else:
			strap.mesh = _arc_strap(r, r * 1.12, r * 0.22, deg_to_rad(band))
		strap.material_override = sm
		strap.position = axis + Vector3(sx * span, 0, 0)
		pivot.add_child(strap)
		var sad := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(r * 0.6, r * 0.45, r * 1.5)
		sad.mesh = bx
		sad.material_override = sm
		sad.position = axis + Vector3(sx * span, -r * 1.03, 0)
		pivot.add_child(sad)


## Strap arc round the X axis, open at the top: inner radius `r0`, outer `r1`, `w` wide along X, `arc` radians
## centred on the bottom.
static func _arc_strap(r0: float, r1: float, w: float, arc: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var pt := func(a: float, r: float, x: float) -> Vector3: return Vector3(x, -cos(a) * r, sin(a) * r)
	for i in n:
		var a0 := -arc * 0.5 + arc * i / n
		var a1 := -arc * 0.5 + arc * (i + 1) / n
		for q: Array in [[r1, r1, w, -w], [r0, r0, -w, w], [r0, r1, w, w], [r1, r0, -w, -w]]:
			# outer face, inner face, two side faces: each quad as two triangles
			var p00: Vector3 = pt.call(a0, q[0], q[2] * 0.5)
			var p01: Vector3 = pt.call(a0, q[1], q[3] * 0.5)
			var p10: Vector3 = pt.call(a1, q[0], q[2] * 0.5)
			var p11: Vector3 = pt.call(a1, q[1], q[3] * 0.5)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(v)
	for a: float in [-arc * 0.5, arc * 0.5]:   # end caps
		var c := [pt.call(a, r0, -w * 0.5), pt.call(a, r1, -w * 0.5), pt.call(a, r1, w * 0.5), pt.call(a, r0, w * 0.5)]
		for v in [c[0], c[1], c[2], c[0], c[2], c[3]]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static var _radius_cache := {}

## Body radius of a weapon mesh lying along X: the thinnest of the widest cross-sections over the middle 60 %
## (wings and fins widen some slices, the body is in every one); cached per mesh.
static func _body_radius(m: Mesh) -> float:
	if _radius_cache.has(m):
		return _radius_cache[m]
	var bb := m.get_aabb()
	var c := bb.get_center()
	var step := bb.size.x * 0.05
	var wide := PackedFloat32Array()
	wide.resize(13)
	for si in m.get_surface_count():
		var vs: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in vs:
			var i := roundi((v.x - c.x) / step)
			if absi(i) <= 6 and absf(v.x - c.x - i * step) < step * 0.4:
				wide[i + 6] = maxf(wide[i + 6], Vector2(v.y - c.y, v.z - c.z).length())
	var r := INF
	for w in wide:
		if w > 0.0:
			r = minf(r, w)
	if r == INF:
		r = minf(bb.size.y, bb.size.z) * 0.5
	_radius_cache[m] = r
	return r


## Bench: --hangarglb=<cls_lvl>=<absolute .glb> shows that file instead of the imported hangar model, so a GLB fix
## made outside the project (S11-07: glove pylons cut from «Оса» 1 while another task owns the hangar GLBs) can be
## checked in the hangar without importing it. Loaded at run time (GLTFDocument), so the canopy keeps the GLB's
## own glass material. null — no override for this plane.
func _bench_glb(key: String) -> Node3D:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hangarglb=%s=" % key):
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			if doc.append_from_file(a.get_slice("=", 2), st) == OK:
				return doc.generate_scene(st) as Node3D
	return null


func _build(cls_id: String, lvl: int) -> void:
	for c in pivot.get_children():
		c.queue_free()
	var path := "res://models/hangar/fh_hangar_%s_%d.glb" % [cls_id, lvl]
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = _bench_glb("%s_%d" % [cls_id, lvl])
	if model == null:
		model = (load(path) as PackedScene).instantiate()
	# обшивка под углом (крылья, фюзеляж сбоку) — анизотропная фильтрация, иначе текстура «плывёт»
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m != null:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	pivot.add_child(model)
	_model = model
	_built_lvl = lvl
	turret_pos.clear()
	_collect_faces(model)
	# Т-3: модули прокачки — стенд --modules=N показывает все модули на уровне N
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--modules="):
			var ml := int(a.get_slice("=", 1))
			ModuleParts.update(ModuleParts.attach(model, "%s_%d" % [cls_id, lvl]), {"engine": ml, "armor": ml, "gun_dmg": ml, "radio": ml})
			bench_seeker = ModuleParts.stage(ml)
	# Т-1: предкрылки и закрылки; в ангаре убраны (стенд --mechdown показывает выпущенными)
	var mech := WingMech.attach(model, "%s_%d" % [cls_id, lvl])
	if mech != null and OS.get_cmdline_user_args().has("--mechdown"):
		WingMech.pose(mech, 1.0)
	# Т-2: отличие «Грача 2» сверху (ПГО, контейнеры на законцовках)
	WingMech.attach_detail(model, "%s_%d" % [cls_id, lvl])
	# V-07: свои знаки на крыльях, киле и (у асов) на борту
	Insignia.attach(model, "%s_%d" % [cls_id, lvl], "player")
	# тест 3.5-s3: кормовая кабина «Кита» — продолжение фюзеляжа в цвет обшивки
	_tail = WingMech.attach_tail(model, "%s_%d" % [cls_id, lvl])
	# замечание 31/33 (3.5-s4): свои винты «Кита 1» — 4 одинаковых по 4 лопасти (винты Meshy из модели удалены)
	var props := WingMech.attach_props(model, "%s_%d" % [cls_id, lvl])
	_props = WingMech.prop_nodes(props) if props != null else []
	# Т-5: створки бомбоотсека в ангаре открыты — видно бомбы
	var bay := WingMech.attach_bay(model, "%s_%d" % [cls_id, lvl])
	if bay != null:
		WingMech.pose_bay(bay, 1.0)
	_apply_livery(model, cls_id, lvl)
	# Kanta 25.10: running engines — the flame fills the rough remeshed nozzles (not on «Кит» 1, propellers)
	NozzleFlame.attach(model, "%s_%d" % [cls_id, lvl])
	_add_weapons(cls_id, lvl)


## Тест 3.5-s4, п. 35: выбранная окраска — на модель и подвешенные к ней механизацию, детали, створки, кабину
func _apply_livery(model: Node3D, cls_id: String, lvl: int) -> void:
	Livery.apply(model, cls_id, lvl, Livery.current(cls_id))


## Стартовое оружие класса на узлах подвески — под крылом / в бомбоотсеке (те же точки, что в игре).
## Flares and wing-turret fairings are laid onto the model's skin (SkinPatch), the same as Render3D does in battle.
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
	var repaint := false   # a turret fairing was added: the livery has to paint it like the rest of the skin
	for gi in groups.size():
		var g: Hardpoint = groups[gi]
		if bench_weapons.has(cls_id) and gi < (bench_weapons[cls_id] as Array).size() and bench_weapons[cls_id][gi] != "":
			g.weapon = bench_weapons[cls_id][gi]
		g.evo = weapon_tier == 4
		g.level = [1, 3, 5][mini(weapon_tier, 3) - 1]   # ступень вида → уровень оружия (ловушки ставятся по уровню)
		if g.builtin and g.weapon == "turret":   # тест 3.5-s7: верхняя турель «Кита» — с ур. 3
			g.slots = PlaneClasses.turret_slots(cls_id, g.level, lvl)
		if g.is_empty():
			continue
		var wt := PlaneArt.weapon_tex(g.weapon)
		if wt == null:
			continue
		var wlen: float = PlaneArt.WEAPON_FRAC.get(g.weapon, 0.25) / plane_k
		for mt: Dictionary in WeaponModels.mounts(cls_id, lvl, gi, g):
			var pt: Vector2 = mt["p"]
			var side: String = mt["side"]
			if side == "skin":   # S13: flush flare-dispenser panel in the model's own skin, no weapon model
				var fp := SkinPatch.flare_panel(_model, float(mt["mx"]), float(mt["mz"]), float(mt.get("seed", 0.0)))
				if fp != null:
					_model.add_child(fp)
				continue
			var mtr: int = mt.get("t", mini(weapon_tier, 3))
			var wmi := WeaponModels.make(g.weapon, mtr, side, cls_id, weapon_tier == 4, lvl, true)   # тест 3.5-s8: ангарная версия
			if g.weapon == "aam" and weapon_tier != 4:
				ModuleParts.seeker_head(wmi, bench_seeker, mtr)
			# по настоящей поверхности модели: подвес — под крылом на пилоне, верхняя турель
			# утоплена в спину фюзеляжа, нижняя — в брюхо, кормовая — в конце фюзеляжа
			var x := pt.x / tw
			var z := pt.y / tw
			var lo := _surface_y(x, z, true)
			var hi := _surface_y(x, z, false)
			var y := 0.0
			var pitch := 0.0
			match side:
				"under":
					y = (lo if not is_nan(lo) else -0.02) - WeaponModels.hang(g.weapon, mtr, weapon_tier == 4) * wlen
					pitch = _chord_pitch(x - 0.02 * wlen, z, (0.18 if g.weapon in ["aam", "arm"] else 0.25) * wlen)
				"belly":   # Т-6: «Бабушкин ковёр» — своим узлом прямо к брюху, без пилона
					y = (lo if not is_nan(lo) else -0.03) - (WeaponModels.hang(g.weapon, 3, true) - WeaponModels.PYLON_H) * wlen
				"top":
					y = hi if not is_nan(hi) else 0.03
				"wing":
					y = hi if not is_nan(hi) else 0.03
					if g.weapon == "turret":   # S13: «Грач» 2 wing turret — its ring on the crown of a wing fairing
						var fr := SkinPatch.turret_fairing(_model, x, z, WeaponModels.collar_r(cls_id, 3) * wlen)
						if fr != null:
							_model.add_child(fr)
							y = float(fr.get_meta("crown"))
							repaint = true
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
				turret_pos.append([wmi.position, side])   # S9-04: в ангаре турель неподвижна (HangarAnim её не трогает)
			elif side == "bay":
				wmi.set_meta("bay_load", true)   # тест 3.5-s8: при закрытых створках бомбы убраны (HangarAnim)
			var bs := Basis(Vector3.UP, float(mt["yaw"]))
			if side == "bottom" or (side == "tail" and WeaponModels.TURRET_MODELS.has(cls_id) and not (WeaponModels.TURRET_MODELS[cls_id] as Dictionary).has("tail")):
				bs = bs * Basis(Vector3.RIGHT, PI)
			if pitch != 0.0:   # S11-07: the pylon lies along the wing's chord, not level under a sloping glove
				bs = Basis(Vector3.BACK, pitch) * bs
			wmi.basis = bs.scaled(Vector3(wlen, wlen, wlen))
			pivot.add_child(wmi)
	if repaint:
		_apply_livery(_model, cls_id, lvl)


## Largest chord slope a pylon follows (rad): a steeper difference between its ends means one end reaches past the
## wing (nacelle, fairing, trailing edge), and the pylon stays level
const PYLON_PITCH_MAX := 0.1


## S11-07 (Kanta: «ракеты висят криво»): pitch (rad, nose up > 0) that lays a pylon of half-length `half` centred at
## (x, z) along the wing underside, so both its ends touch the skin instead of one end floating below a sloping glove.
## 0 when either end misses the model or the slope is not a plain wing chord.
func _chord_pitch(x: float, z: float, half: float) -> float:
	var lf := _surface_y(x + half, z, true)
	var lr := _surface_y(x - half, z, true)
	if is_nan(lf) or is_nan(lr):
		return 0.0
	var p := atan2(lf - lr, 2.0 * half)
	return p if absf(p) <= PYLON_PITCH_MAX else 0.0


var _faces := PackedVector3Array()
var _tail: Node3D = null
var _props: Array = []       # замечание 31/33: винты «Кита 1» — в ангаре медленно крутятся, как на прогреве
const PROP_HANGAR := TAU * 0.6   # рад/с


## Треугольники модели (в осях pivot) — чтобы найти поверхность крыла под точкой подвеса
func _collect_faces(model: Node3D) -> void:
	_faces = PackedVector3Array()
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		# S11-11: the bay doors cut out of a «Kit» belly are not the surface the bombs hang from — the bay ceiling is
		if mi.get_parent() != null and mi.get_parent().name == "bay_doors":
			continue
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
	_t += delta
	# п. 32: в «полёте» самолёт чуть покачивается, как в воздухе; на складе оружие стоит
	if decal_mode:   # the decal editor: the plane holds still under the cursor
		pivot.position.y = 0.0
		pivot.rotation = Vector3.ZERO
	elif _bg == "flight":
		var st := anim_time if anim_time >= 0.0 else _t   # стенд --mechanim: покачивание тоже по заданному моменту
		pivot.position.y = sin(st * 0.9) * 0.012
		pivot.rotation = Vector3(sin(st * 0.6) * 0.035, 0.0, sin(st * 0.75 + 1.0) * 0.02)
	else:
		pivot.position.y = 0.0
		pivot.rotation = Vector3.ZERO
	WingMech.spin_props(_props, PROP_HANGAR * delta)
	# тест 3.5-s8: механизация и створки (турели в ангаре неподвижны — S9-04)
	if _anim_key != _key:
		_anim_key = _key
		_anim = HangarAnim.collect(pivot)
	HangarAnim.step(_anim, anim_time if anim_time >= 0.0 else _t, mech_demo or mech_hover or _key.begins_with("w_"), delta)
	mech_hover = false
	if not _drag and _idle > 3.0 and not decal_mode:
		_yaw += delta * 0.25
	_pitch = clampf(_pitch, bench_pitch_min, 1.35)
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
				if mech_rect.has_point(mp) and not _key.begins_with("w_"):
					mech_demo = not mech_demo
					get_viewport().set_input_as_handled()
					return
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
				if decal_mode and rect.has_point(mp):   # the left button places and moves decals
					decal_press.emit(mp, true)
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
				if decal_mode:
					decal_press.emit(mp, false)
				_drag = false
		elif decal_mode and mb.button_index == MOUSE_BUTTON_RIGHT:   # editor: the right button orbits
			_drag = mb.pressed and rect.has_point(mp)
			if _drag:
				get_viewport().set_input_as_handled()
		elif decal_mode and mb.pressed and rect.has_point(mp) and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			decal_wheel.emit(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
		elif mb.pressed and rect.has_point(mp) and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_dist *= 0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			_idle = 0.0
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and decal_mode and not _drag:
		decal_cursor = mp
		decal_pad = false
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * 0.008
		_pitch += mm.relative.y * 0.006
		_idle = 0.0


# ---------- Decal editor mode (spec 2026-10-27-plane-decals-design.md §6) ----------

## The decal editor is open: no idle spin or sway, the left button and the wheel go to the editor (signals below),
## the right button orbits
var decal_mode := false
## Editor cursor in ctrl coordinates (the mouse, or the gamepad stick moves it)
var decal_cursor := Vector2(-1.0, -1.0)
## The cursor was last moved by the gamepad (HudDecals draws a cross for it)
var decal_pad := false
## Left button pressed (true) or released (false) over the view in decal mode, at `p` (ctrl coordinates)
signal decal_press(p: Vector2, pressed: bool)
## Wheel over the view in decal mode: +1 up, −1 down
signal decal_wheel(steps: int)
var _dc_model: Node3D
var _dc_sig := ""
var _dc_live_sig := ""


## Plane key of the model on view («fighter_2»): what the decal presets and Profile.decals are keyed by
func model_key() -> String:
	return "%s_%d" % [_cls, _built_lvl]


## The skin under screen point `p` (ctrl coordinates): [position, normal] in model axes, [] off the plane
func decal_ray(p: Vector2) -> Array:
	if _model == null or not is_instance_valid(_model) or not rect.has_point(p) or rect.size.x < 1.0:
		return []
	var hull := PlaneDecals.hull_of(_model)
	if hull == null:
		return []
	var px := (p - rect.position) / rect.size * Vector2(vp.size)
	var inv := _model.global_transform.affine_inverse()
	var o := inv * cam.project_ray_origin(px)
	var d := (inv.basis * cam.project_ray_normal(px)).normalized()
	# start the march where the ray enters the plane's sphere (the model is about 1 long round its centre)
	var b := o.dot(d)
	var disc := b * b - (o.length_squared() - DECAL_REACH * DECAL_REACH)
	if disc < 0.0:
		return []
	var t0 := maxf(0.0, -b - sqrt(disc))
	return hull.raycast(o + d * t0, d, 2.0 * DECAL_REACH)


const DECAL_REACH := 0.8   ## model units round the centre where the cursor ray looks for skin


## Draws the editor's decals: `records` on the plane (rebuilt only when they change), `live` — the decal under the
## cursor / being moved / selected, with the highlight (null none); `tally` — marks for tally decals
func decal_refresh(records: Array[DecalRecord], live: DecalRecord, tally: int) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	var sig := "%d|%s" % [tally, str(records.map(func(r: DecalRecord) -> Dictionary: return r.to_dict()))]
	if _model != _dc_model or sig != _dc_sig:
		_dc_model = _model
		_dc_sig = sig
		_dc_live_sig = "-"
		PlaneDecals.show(_model, model_key(), records, tally)
	var ls := str(live.to_dict()) if live != null else ""
	if ls != _dc_live_sig:
		_dc_live_sig = ls
		PlaneDecals.show_preview(_model, live, tally)


## Leaves decal mode: plane `key` shows `records` with the real `tally` again, the preview goes away (a model of
## another plane, already rebuilt from the profile, is left as it is)
func decal_close(key: String, records: Array[DecalRecord], tally: int) -> void:
	decal_mode = false
	_drag = false
	if _model != null and is_instance_valid(_model) and model_key() == key:
		PlaneDecals.show(_model, model_key(), records, tally)
		PlaneDecals.show_preview(_model, null, tally)
	_dc_model = null
	_dc_sig = ""
	_dc_live_sig = ""


## The skin of the plane on view the decals are cut from (null without a model)
func decal_hull() -> PlaneHull:
	return PlaneDecals.hull_of(_model) if _model != null and is_instance_valid(_model) else null


## Turns the camera by `dx`, `dy` radians (the gamepad's right stick in the editor)
func orbit(dx: float, dy: float) -> void:
	_yaw += dx
	_pitch += dy
	_idle = 0.0


## Zooms by `steps` wheel notches (+ closer)
func zoom(steps: int) -> void:
	_dist *= pow(0.9, steps)
	_idle = 0.0
