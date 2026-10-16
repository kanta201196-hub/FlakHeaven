extends SceneTree
## 3.5: спрайт «вид сверху» из подготовленной модели (после model_lab.gd prep: нос +X, длина 1).
## Прозрачный фон, обрезка по силуэту — как спрайты в art/enemies (нос вправо).
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/model_lab/sprite_top.gd -- <in.glb> <out.png> [px=600]

var _out := ""
var _px := 600
var _frames := 0
var _vp: SubViewport


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		push_error("нужно: <in.glb> <out.png> [px]")
		quit(1)
		return
	_out = a[1]
	if a.size() > 2:
		_px = int(a[2])
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		push_error("не читается " + a[0])
		quit(1)
		return
	var model := doc.generate_scene(st)
	_vp = SubViewport.new()
	_vp.size = Vector2i(_px, _px)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.55
	_vp.add_child(env)
	_vp.add_child(model)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 1.25
	_vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.08
	cam.position = Vector3(0, 5, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)  # смотрит вниз, верх кадра — −Z
	_vp.add_child(cam)
	cam.make_current()


func _process(_d: float) -> bool:
	if _vp == null:
		return false
	_frames += 1
	if _frames < 10:
		return false
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x > 0:
		img = img.get_region(used.grow(2).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	img.save_png(_out)
	print("СПРАЙТ: ", _out, " ", img.get_size())
	quit(0)
	return true
