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


## Тест 3.5-s4 (п. 32): небо для вида «полёт» — от дымки у горизонта к синеве в зените, мягкое солнце
const SKY_SHADER := """
shader_type sky;
void sky() {
	float h = EYEDIR.y;
	vec3 haze = vec3(0.78, 0.83, 0.88);
	vec3 zen = vec3(0.30, 0.47, 0.72);
	vec3 low = vec3(0.42, 0.45, 0.47);   // далеко внизу — земля в дымке, темнее неба: светлый самолёт читается сверху
	vec3 c = mix(haze, zen, smoothstep(0.0, 0.7, h));
	c = mix(c, low, smoothstep(-0.02, -0.35, h));
	vec3 sd = normalize(vec3(-0.55, 0.55, 0.62));
	float sun = max(dot(EYEDIR, sd), 0.0);
	c += vec3(1.0, 0.9, 0.7) * (pow(sun, 400.0) * 1.5 + pow(sun, 12.0) * 0.12);
	COLOR = c;
}
"""
## Слой облаков под самолётом: шумовые клочья плывут назад (самолёт летит носом +X), к краю тают
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float speed = 0.35;
uniform float scale = 0.55;
uniform float cover = 0.5;
uniform float alpha_k = 0.9;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * scale + vec2(TIME * speed, 0.0);
	float n = fbm(p);
	float a = smoothstep(cover, cover + 0.22, n);
	float edge = 1.0 - smoothstep(4.0, 11.0, length(wp.xz));
	ALBEDO = mix(vec3(0.82, 0.85, 0.9), vec3(1.0), smoothstep(cover, cover + 0.35, n));
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


## Каждый кадр, пока открыта вкладка «САМОЛЁТ»: какой самолёт показать и где
func show_plane(cls_id: String, r: Rect2) -> Texture2D:
	if cls_id != _cls:
		_cls = cls_id
		view_lvl = 1
	rect = r
	_drawn_frame = Engine.get_process_frames()
	_fit_vp(r)
	_set_bg("flight")
	var k := "%s_%d_%d_%s" % [cls_id, view_lvl, weapon_tier, Livery.current(cls_id)]   # п. 35: и окраска
	if k != _key:
		if _key.begins_with("w_"):
			_dist = DIST0
		_key = k
		_build(cls_id, view_lvl)
	return vp.get_texture()


## Тест 3.5-s3 («текстуры в ангаре — идеально»): вид рисуется с запасом по разрешению — в пикселях экрана
## (при растяжении окна) × SUPERSAMPLE и сжимается в рамку: текстура модели чётче, края без лесенки
const SUPERSAMPLE := 1.5


func _fit_vp(r: Rect2) -> void:
	var k := SUPERSAMPLE * maxf(1.0, _ctrl.get_viewport().get_final_transform().get_scale().x) if _ctrl != null else SUPERSAMPLE
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
		var side := "top" if weapon == "turret" else ("" if weapon == "flares" and not evo else "under")
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
		# турель — в одном масштабе на всех ступенях (модель меньше 1 — множитель не зависит от габарита),
		# поэтому рост ступени виден; S9-04: стоит неподвижно, стволами вперёд-вбок к камере (3/4 спереди)
		var rot := TURRET_SHOW_YAW if weapon == "turret" else 0.0
		wmi.basis = Basis(Vector3.UP, rot).scaled(Vector3.ONE * s)
		var c := Basis(Vector3.UP, rot) * (bb.get_center() * s)
		wmi.position = Vector3(-c.x, -0.03 if side == "under" else (-0.15 if weapon == "turret" else -0.08), -c.z)
		pivot.add_child(wmi)
		# п. 32: на складе оружие лежит на двух ложементах-подставках от пола до низа модели
		var bottom := wmi.position.y + bb.position.y * s
		if weapon != "turret" and bottom > -0.19:
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


func _build(cls_id: String, lvl: int) -> void:
	for c in pivot.get_children():
		c.queue_free()
	var path := "res://models/hangar/fh_hangar_%s_%d.glb" % [cls_id, lvl]
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	# обшивка под углом (крылья, фюзеляж сбоку) — анизотропная фильтрация, иначе текстура «плывёт»
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m != null:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	pivot.add_child(model)
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
	_add_weapons(cls_id, lvl)


## Тест 3.5-s4, п. 35: выбранная окраска — на модель и подвешенные к ней механизацию, детали, створки, кабину
func _apply_livery(model: Node3D, cls_id: String, lvl: int) -> void:
	Livery.apply(model, cls_id, lvl, Livery.current(cls_id))


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
		if g.builtin and g.weapon == "turret":   # тест 3.5-s7: верхняя турель «Кита» — с ур. 3
			g.slots = PlaneClasses.turret_slots(cls_id, g.level)
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
				turret_pos.append([wmi.position, side])   # S9-04: в ангаре турель неподвижна (HangarAnim её не трогает)
			elif side == "bay":
				wmi.set_meta("bay_load", true)   # тест 3.5-s8: при закрытых створках бомбы убраны (HangarAnim)
			var bs := Basis(Vector3.UP, float(mt["yaw"]))
			if side == "bottom" or (side == "tail" and WeaponModels.TURRET_MODELS.has(cls_id) and not (WeaponModels.TURRET_MODELS[cls_id] as Dictionary).has("tail")):
				bs = bs * Basis(Vector3.RIGHT, PI)
			wmi.basis = bs.scaled(Vector3(wlen, wlen, wlen))
			pivot.add_child(wmi)


var _faces := PackedVector3Array()
var _tail: Node3D = null
var _props: Array = []       # замечание 31/33: винты «Кита 1» — в ангаре медленно крутятся, как на прогреве
const PROP_HANGAR := TAU * 0.6   # рад/с


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
	_t += delta
	# п. 32: в «полёте» самолёт чуть покачивается, как в воздухе; на складе оружие стоит
	if _bg == "flight":
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
	if not _drag and _idle > 3.0:
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
