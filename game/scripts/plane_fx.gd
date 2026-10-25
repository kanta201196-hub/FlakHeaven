class_name PlaneFx
## 3.4-t1 (п. 9, 19, 10): огонь из сопел реактивных, крутящиеся винты «Кита 1» и точки,
## из которых тянутся инверсионные следы. Всё — дочерние узлы объёмного самолёта (Render3D),
## координаты в пикселях текстуры самолёта: центр картинки, нос по +X, Z — вниз по картинке.

## Сопла / двигатели по картинкам art/planes (замерено по спрайтам).
## jet — сопла (огонь), r — радиус сопла; prop — оси винтов, pr — радиус винта; trail — откуда след;
## y — высота оси сопел над центром модели (пикс.), если сопло не на общей высоте (ширина картинки × 0,012).
## «Оса 1» (модель Sketchfab, VIS-01): одно сопло по оси, срез x −0,464 длины, ось на −0,060, радиус 0,031 — по модели.
const SPEC := {
	"fighter_1": {"jet": [Vector2(-79, 0)], "r": 5.3, "y": -10.2},
	"fighter_2": {"jet": [Vector2(-100, -16.5), Vector2(-100, 16.5)], "r": 5.5},   # Meshy model 24.10: nozzle exits x -0.444, z ±0.074
	"attacker_1": {"jet": [Vector2(-49, -19.5), Vector2(-49, 18.5)], "r": 6.5},
	"attacker_2": {"jet": [Vector2(-61, -20), Vector2(-61, 20)], "r": 7.0},
	"bomber_1": {"prop": [Vector2(37, -81), Vector2(55, -39), Vector2(55, 39), Vector2(37, 82)], "pr": 20.0,
		"trail": [Vector2(-10, -81), Vector2(8, -39), Vector2(8, 39), Vector2(-10, 82)]},
	"bomber_2": {"jet": [Vector2(-80, -21.5), Vector2(-80, 21)], "r": 12.0},
}

static var _flame_mesh: QuadMesh
static var _flame_mat: StandardMaterial3D
static var _flame_blue: StandardMaterial3D
static var _prop_mesh: QuadMesh
static var _prop_mat: ShaderMaterial
static var _blur_mat: ShaderMaterial

## Замечание 31/33 (3.5-s4): у 3D-модели «Кита 1» — свои винты (WingMech.attach_props, 4 × 4 лопасти).
## Они крутятся узлами; поверх — слабый диск размытия в плоскости вращения (как у настоящего винта).
## Диск на картинке (горизонтальный эллипс) — только для плоского спрайта («Качество графики» = «Низкое»).
const PROP_RATE := TAU * 5.5   # рад/с — винты в полёте
const PROP_IDLE := TAU * 0.4   # авторотация, когда «двигатель выключен» (падение ведомого)
const PROP_R := 0.066          # радиус винта в длинах модели (kit_props.py R_TIP)

## Винт: диск, как на картинке самолёта (сплюснутый эллипс перед мотором), по нему крутятся
## четыре размытые лопасти. Вращение — в шейдере (TIME), узлы каждый кадр не трогаем.
const PROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float speed = 14.0;
uniform float k = 1.0;   // общая плотность: у диска при настоящих лопастях — слабее
uniform float hub_on = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x) + TIME * speed;
	float blade = pow(abs(cos(2.0 * a)), 22.0) * smoothstep(1.0, 0.86, r) * smoothstep(0.1, 0.25, r);
	float disc = 0.1 * smoothstep(1.0, 0.9, r);
	float hub = (1.0 - smoothstep(0.12, 0.17, r)) * hub_on;
	ALBEDO = mix(vec3(0.1, 0.1, 0.11), vec3(0.55), hub);
	ALPHA = clamp((max(blade * 0.95, disc) + hub) * k, 0.0, 1.0);
}
"""


static func spec_of(tex: Texture2D) -> Dictionary:
	return SPEC.get(tex.resource_path.get_file().get_basename(), {})


## Creates engine flames and props on a plane (u — a Render3D / TitleFlight unit; fills u.fx, u.props)
static func attach(u: Unit3D, tex: Texture2D) -> void:
	var s := spec_of(tex)
	var root: Node3D = u.node
	var fx := {"flames": [], "props": [], "trail": []}
	u.fx = fx
	if s.is_empty():
		return
	_init_res()
	# своя высота сопла — только у 3D-модели; рельеф из картинки («Низкое» качество) плоский, огонь на общей высоте
	var y: float = s.get("y", tex.get_width() * 0.012) if u.bm != null else tex.get_width() * 0.012
	for pt: Vector2 in s.get("jet", []):
		var r: float = s["r"]
		# две скрещённые плоскости: сверху видна горизонтальная, при крене и наклоне камеры — вертикальная
		var f := Node3D.new()
		f.position = Vector3(pt.x, y, pt.y)
		for i in 2:
			var q := MeshInstance3D.new()
			q.mesh = _flame_mesh
			q.material_override = _flame_mat
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.add_child(q)
		root.add_child(f)
		fx["flames"].append({"n": f, "r": r, "ph": randf() * 10.0})
		fx["trail"].append(Vector3(pt.x - r, y, pt.y))
	var props: Node3D = null
	if s.has("prop") and u.bm != null:
		props = WingMech.attach_props(root.get_child(0) as Node3D, tex.resource_path.get_file().get_basename())
	if props != null:
		u.props = props
		fx["blades"] = WingMech.prop_nodes(props)
		fx["blurs"] = []
		for n: Node3D in fx["blades"]:
			var d := MeshInstance3D.new()
			d.mesh = _prop_mesh
			d.material_override = _blur_mat
			d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# квад в плоскости Y/Z модели (нормаль — ось винта X), в плоскости лопастей
			d.position = n.position + Vector3(0.009, 0, 0)
			d.basis = Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3.ONE * PROP_R * 2.0)
			n.get_parent().add_child(d)   # рядом с винтом: сам диск не вращается, полосы крутит шейдер
			fx["blurs"].append(d)
	for pt: Vector2 in (s.get("prop", []) if props == null else []):
		var pr: float = s["pr"]
		var d := MeshInstance3D.new()
		d.mesh = _prop_mesh
		d.material_override = _prop_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# горизонтальный квад; по X (вдоль полёта) сплюснут, как диск винта на картинке
		d.position = Vector3(pt.x, tex.get_width() * 0.03, pt.y)
		d.basis = Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(pr * 0.8, pr * 2.2, 1.0))
		root.add_child(d)
		fx["props"].append(d)
	for pt: Vector2 in s.get("trail", []):
		fx["trail"].append(Vector3(pt.x, y, pt.y))


## Per frame for unit u: boost 0…1 is afterburner; props always spin, flames flicker and stretch on boost
static func update(u: Unit3D, delta: float, boost: float, on := true) -> void:
	var fx: Dictionary = u.fx
	if fx.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	if fx.has("blades"):
		# шаг за кадр не больше 0,4 промежутка между лопастями — при любом FPS винт крутится вперёд, без «стробоскопа»
		var step := minf((PROP_RATE if on else PROP_IDLE) * delta, 0.4 * TAU / 4.0)
		WingMech.spin_props(fx["blades"], step)
		for d: Node3D in fx["blurs"]:
			d.visible = on
	for f: Dictionary in fx["flames"]:
		var n: Node3D = f["n"]
		n.visible = on
		if not on:
			continue
		var r: float = f["r"]
		var fl := 1.0 + 0.12 * sin(t * 47.0 + float(f["ph"])) + 0.08 * sin(t * 83.0 + float(f["ph"]) * 2.0)
		var ln := r * lerpf(1.6, 5.5, boost) * fl
		var wd := r * lerpf(1.5, 1.9, boost)
		# квад единичный, центр в середине: сдвигаем назад на половину длины; 0 — горизонтальный, 1 — вертикальный
		for i in n.get_child_count():
			var q: MeshInstance3D = n.get_child(i)
			q.position = Vector3(-ln * 0.5 + r * 0.25, 0, 0)
			q.basis = Basis(Vector3.RIGHT, -PI / 2.0 if i == 0 else 0.0) * Basis.from_scale(Vector3(ln, wd, 1.0))


## T-3: blue flame on unit u (module «Форсированный двигатель» lv. 5)
static func set_blue(u: Unit3D, on: bool) -> void:
	var fx: Dictionary = u.fx
	if fx.is_empty() or bool(fx.get("blue", false)) == on:
		return
	fx["blue"] = on
	for f: Dictionary in fx["flames"]:
		for q in (f["n"] as Node3D).get_children():
			(q as MeshInstance3D).material_override = _flame_blue if on else _flame_mat


## Trail points of unit u in world coordinates
static func trail_points(u: Unit3D) -> Array:
	var out := []
	var fx: Dictionary = u.fx
	if fx.is_empty():
		return out
	var xf := (u.node as Node3D).global_transform
	for p: Vector3 in fx["trail"]:
		out.append(xf * p)
	return out


static func _init_res() -> void:
	if _flame_mesh != null:
		return
	_flame_mesh = QuadMesh.new()
	_flame_mesh.size = Vector2(1, 1)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.albedo_texture = _flame_tex()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_blue = _flame_mat.duplicate()
	_flame_blue.albedo_texture = _flame_tex(true)
	_prop_mesh = QuadMesh.new()
	_prop_mesh.size = Vector2(1, 1)
	var sh := Shader.new()
	sh.code = PROP_SHADER
	_prop_mat = ShaderMaterial.new()
	_prop_mat.shader = sh
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = sh
	_blur_mat.set_shader_parameter("k", 0.45)
	_blur_mat.set_shader_parameter("hub_on", 0.0)
	_blur_mat.set_shader_parameter("speed", 30.0)


## Факел: у сопла бело-жёлтый, к хвосту оранжевый и прозрачный; по ширине — мягкий край.
## U = 0 — хвост факела, U = 1 — сопло (квад повёрнут носом самолёта к +X).
static func _flame_tex(blue := false) -> ImageTexture:
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var u := float(x) / (w - 1)          # 1 у сопла
		for y in h:
			var v := absf(float(y) / (h - 1) * 2.0 - 1.0)
			var core := pow(u, 1.6)
			var width := lerpf(0.25, 1.0, u)  # к хвосту сужается
			var edge := clampf(1.0 - v / width, 0.0, 1.0)
			var a := core * edge * edge
			var c := Color(1.0, 0.45, 0.15).lerp(Color(1.0, 0.92, 0.7), clampf(core * edge * 1.3, 0.0, 1.0))
			if blue:   # Т-3: форсированный двигатель ур. 5 — голубой факел
				c = Color(0.25, 0.45, 1.0).lerp(Color(0.85, 0.95, 1.0), clampf(core * edge * 1.3, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(a * 1.4, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
