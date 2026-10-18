extends SceneTree
## Быстрый осмотр подготовленной модели (нос +X, длина 1): три кадра в ряд — сверху, наклон 35° и сбоку.
##   xvfb-run godot --path game --rendering-driver opengl3 --script res://tools/model_lab/look.gd -- <in.glb> <out.png> [px=480] [кадр=1.15]
## Фон — серо-синяя «вода», чтобы были видны и светлые, и тёмные модели.

var _out := ""
var _px := 480
var _size := 1.15
var _vps: Array[SubViewport] = []
var _frames := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		push_error("нужно: <in.glb> <out.png> [px] [кадр]")
		quit(1)
		return
	_out = a[1]
	if a.size() > 2:
		_px = int(a[2])
	if a.size() > 3:
		_size = float(a[3])
	for ang in [-90.0, -35.0, 0.0]:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(a[0], st) != OK:
			push_error("не читается " + a[0])
			quit(1)
			return
		var vp := SubViewport.new()
		vp.size = Vector2i(_px, _px)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		vp.own_world_3d = true
		root.add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.36, 0.45, 0.52)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
		env.environment.ambient_light_energy = 0.55
		vp.add_child(env)
		vp.add_child(doc.generate_scene(st))
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-60, -30, 0)
		sun.light_energy = 1.25
		vp.add_child(sun)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = _size
		cam.rotation_degrees = Vector3(ang, 0, 0)
		cam.position = cam.transform.basis.z * 5.0
		vp.add_child(cam)
		cam.make_current()
		_vps.append(vp)


func _process(_d: float) -> bool:
	if _vps.is_empty():
		return false
	_frames += 1
	if _frames < 6:
		return false
	var out := Image.create(_px * 3, _px, false, Image.FORMAT_RGBA8)
	for i in _vps.size():
		var img := _vps[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		out.blit_rect(img, Rect2i(0, 0, _px, _px), Vector2i(i * _px, 0))
	out.save_png(_out)
	print("LOOK: ", _out)
	quit(0)
	return true
