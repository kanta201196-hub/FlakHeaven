extends SceneTree
## 3.4-t1 (п. 17): картинки для облегчённых деревьев (пресеты ниже «Максимального»).
## Модель Meshy снимается сбоку и сверху на прозрачном фоне при свете игры; облегчённое дерево —
## две скрещённые «карточки» с видом сбоку и одна горизонтальная с видом сверху (BiomeProps).
##   xvfb-run godot --path game --rendering-driver opengl3 -s res://tools/model_lab/bake_impostor.gd
## Результат — game/models/biome/<имя>_side.png и <имя>_top.png (256 × 256).
## Только некоторые модели: ... -s res://tools/model_lab/bake_impostor.gd -- b05_orchard_tree

const MODELS := ["b04_poplar", "b05_orchard_tree", "b12_date_palm"]
const SIZE := 256

var _vp: SubViewport
var _cam: Camera3D
var _queue: Array = []
var _frames := 0


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.68, 0.82)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.15
	sun.basis = Basis.looking_at(Vector3(0.62, -0.85, 0.75).normalized(), Vector3(0, 0, -1))
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	var only := Array(OS.get_cmdline_user_args())
	for name in MODELS:
		if not only.is_empty() and not only.has(name):
			continue
		_queue.append([name, "side"])
		_queue.append([name, "top"])


var _model: Node3D
var _cur: Array = []


func _process(_delta: float) -> bool:
	if _cur.is_empty():
		if _queue.is_empty():
			quit()
			return true
		_cur = _queue.pop_front()
		if is_instance_valid(_model):
			_model.queue_free()
		var ps: PackedScene = load("res://models/biome/%s.glb" % _cur[0])
		_model = ps.instantiate()
		_vp.add_child(_model)
		var aabb := _aabb(_model)
		var h := aabb.size.y
		var w := maxf(aabb.size.x, aabb.size.z)
		if _cur[1] == "side":
			_cam.size = maxf(h, w) * 1.02
			_cam.position = Vector3(0, h * 0.5, 50.0)
			_cam.basis = Basis()
		else:
			_cam.size = w * 1.02
			_cam.position = Vector3(0, h + 50.0, 0)
			_cam.basis = Basis.looking_at(Vector3.DOWN, Vector3(0, 0, -1))
		_frames = 0
		return false
	_frames += 1
	if _frames == 4:
		var img := _vp.get_texture().get_image()
		var path := "res://models/biome/%s_%s.png" % [_cur[0], _cur[1]]
		img.save_png(ProjectSettings.globalize_path(path))
		print("BAKED ", path)
		_cur = []
	return false


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var a := mi.global_transform * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out
