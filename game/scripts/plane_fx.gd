class_name PlaneFx
## 3.4-t1 (п. 9, 19, 10): огонь из сопел реактивных, крутящиеся винты «Кита 1» и точки,
## из которых тянутся инверсионные следы. Всё — дочерние узлы объёмного самолёта (Render3D),
## координаты в пикселях текстуры самолёта: центр картинки, нос по +X, Z — вниз по картинке.

## Сопла / двигатели по картинкам art/planes (замерено по спрайтам).
## jet — сопла (огонь), r — радиус сопла; prop — оси винтов, pr — радиус винта; trail — откуда след.
const SPEC := {
	"fighter_1": {"jet": [Vector2(-81, -12), Vector2(-81, 12)], "r": 6.5},
	"fighter_2": {"jet": [Vector2(-99, -12), Vector2(-99, 11)], "r": 7.0},
	"attacker_1": {"jet": [Vector2(-49, -19.5), Vector2(-49, 18.5)], "r": 6.5},
	"attacker_2": {"jet": [Vector2(-61, -20), Vector2(-61, 20)], "r": 7.0},
	"bomber_1": {"prop": [Vector2(37, -81), Vector2(55, -39), Vector2(55, 39), Vector2(37, 82)], "pr": 20.0,
		"trail": [Vector2(-10, -81), Vector2(8, -39), Vector2(8, 39), Vector2(-10, 82)]},
	"bomber_2": {"jet": [Vector2(-80, -21.5), Vector2(-80, 21)], "r": 12.0},
}

static var _flame_mesh: QuadMesh
static var _flame_mat: StandardMaterial3D
static var _prop_mesh: QuadMesh
static var _prop_mat: ShaderMaterial

## Винт: диск, как на картинке самолёта (сплюснутый эллипс перед мотором), по нему крутятся
## четыре размытые лопасти. Вращение — в шейдере (TIME), узлы каждый кадр не трогаем.
const PROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float speed = 14.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x) + TIME * speed;
	float blade = pow(abs(cos(2.0 * a)), 22.0) * smoothstep(1.0, 0.86, r) * smoothstep(0.1, 0.25, r);
	float disc = 0.1 * smoothstep(1.0, 0.9, r);
	float hub = 1.0 - smoothstep(0.12, 0.17, r);
	ALBEDO = mix(vec3(0.1, 0.1, 0.11), vec3(0.55), hub);
	ALPHA = clamp(max(blade * 0.95, disc) + hub, 0.0, 1.0);
}
"""


static func spec_of(tex: Texture2D) -> Dictionary:
	return SPEC.get(tex.resource_path.get_file().get_basename(), {})


## Создаёт огонь сопел и винты на самолёте (u — запись Render3D._units)
static func attach(u: Dictionary, tex: Texture2D) -> void:
	var s := spec_of(tex)
	var root: Node3D = u["node"]
	var fx := {"flames": [], "props": [], "trail": []}
	u["fx"] = fx
	if s.is_empty():
		return
	_init_res()
	var y := tex.get_width() * 0.012
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
	for pt: Vector2 in s.get("prop", []):
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


## boost 0…1 — форсаж; винты крутятся всегда, пламя дрожит и вытягивается на форсаже
static func update(u: Dictionary, _delta: float, boost: float, on := true) -> void:
	var fx: Dictionary = u.get("fx", {})
	if fx.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
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


## Точки следа в мировых координатах
static func trail_points(u: Dictionary) -> Array:
	var out := []
	var fx: Dictionary = u.get("fx", {})
	if fx.is_empty():
		return out
	var xf := (u["node"] as Node3D).global_transform
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
	_prop_mesh = QuadMesh.new()
	_prop_mesh.size = Vector2(1, 1)
	var sh := Shader.new()
	sh.code = PROP_SHADER
	_prop_mat = ShaderMaterial.new()
	_prop_mat.shader = sh


## Факел: у сопла бело-жёлтый, к хвосту оранжевый и прозрачный; по ширине — мягкий край.
## U = 0 — хвост факела, U = 1 — сопло (квад повёрнут носом самолёта к +X).
static func _flame_tex() -> ImageTexture:
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
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(a * 1.4, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
