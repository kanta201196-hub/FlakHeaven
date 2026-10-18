extends Node
## Тест 3.5-s4, п. 35: лист окрасок (Livery) — модель ангара или боя с механизацией и деталями,
## каждый вариант окраски в двух видах (3/4 сверху и сверху), всё на одном листе user://livery_<…>.png.
## Быстрее стенда ангара: без интерфейса и сверхвыборки. Из папки game/:
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/model_lab/livery_sheet.tscn -- [cls=fighter] [lvl=2] [kind=battle]
##   [liv=classic,black_gloss] — только эти окраски; [views=0,1,2] — виды: 0 — 3/4 сверху, 1 — сверху, 2 — крупно кабина;
##   тест 3.5-s7 (дефекты окраски в ангаре), крупно как в ангаре: 3 — двигатель и крыло спереди слева (ракурс Kanta),
##   4 — крыло сзади сверху, 5 — низ спереди, 6 — хвост, 7 — нос, 8 / 9 — гондола и правое крыло сзади почти по горизонту (ракурс скриншота Kanta), 10 — хвост внутренней гондолы снизу сзади;
##   [scale=2] — кадр вдвое крупнее [env=hangar] — небо, свет и винты как в ангаре
var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var queue: Array = []
var frames := 0
var shots: Array = []
var cur: Array
var sc := 1
const CLOSE := [
	[Vector3(0.05, -0.02, -0.2), -0.75, 0.18, 0.42],
	[Vector3(-0.05, 0.0, -0.2), -2.3, 0.55, 0.45],
	[Vector3(0.0, 0.0, 0.0), -0.9, -0.55, 0.6],
	[Vector3(-0.38, 0.05, 0.0), -2.6, 0.3, 0.42],
	[Vector3(0.32, 0.0, 0.0), -0.6, 0.25, 0.38],
	[Vector3(-0.12, 0.0, 0.2), 2.75, 0.1, 0.34],
	[Vector3(-0.12, 0.0, 0.2), 2.45, 0.02, 0.5],
	[Vector3(-0.17, -0.03, 0.145), 2.6, -0.35, 0.2],
]

func _ready():
	var args := OS.get_cmdline_user_args()
	var classes := ["fighter", "attacker", "bomber"]
	var lvls := [1]
	var kind := "hangar"
	var only: Array = []
	var views: Array = [0, 1]
	var hangar_env := false
	for a in args:
		if a.begins_with("scale="): sc = int(a.get_slice("=", 1))
	for a in args:
		if a.begins_with("liv="): only = Array(a.get_slice("=", 1).split(","))
		if a.begins_with("views="):
			views = []
			for x in a.get_slice("=", 1).split(","):
				views.append(int(x))
		if a.begins_with("cls="): classes = [a.get_slice("=", 1)]
		if a.begins_with("lvl="): lvls = [int(a.get_slice("=", 1))]
		if a.begins_with("kind="): kind = a.get_slice("=", 1)
		if a == "env=hangar": hangar_env = true
	for c in classes:
		for l in lvls:
			for v in Livery.list(c):
				if not only.is_empty() and not only.has(v[0]):
					continue
				for view in views:
					queue.append([c, l, v[0], view, kind])
	vp = SubViewport.new()
	vp.size = Vector2i(560, 400) * sc
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.68, 0.82)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.85)
	key.basis = Basis.looking_at(Vector3(0.55, -0.55, -0.62).normalized(), Vector3.UP)
	vp.add_child(key)
	if hangar_env:   # как Hangar3D в «полёте»: небо (оно же даёт отражения), контровой свет
		var sky := Sky.new()
		var skm := ShaderMaterial.new()
		var sks := Shader.new()
		sks.code = Hangar3D.SKY_SHADER
		skm.shader = sks
		sky.sky_material = skm
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		var rim := DirectionalLight3D.new()
		rim.light_color = Color(0.6, 0.72, 1.0)
		rim.light_energy = 0.4
		rim.basis = Basis.looking_at(Vector3(-0.6, -0.2, 0.75).normalized(), Vector3.UP)
		vp.add_child(rim)
		vp.msaa_3d = Viewport.MSAA_4X
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.02
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)

func _process(_d: float) -> void:
	if cur.is_empty():
		if queue.is_empty():
			_sheet()
			get_tree().quit()
			return
		cur = queue.pop_front()
		for c in holder.get_children():
			c.free()
		var path := "res://models/%s/fh_%s_%s_%d.glb" % [cur[4], cur[4], cur[0], cur[1]]
		var model: Node3D = (load(path) as PackedScene).instantiate()
		holder.add_child(model)
		var k := "%s_%d" % [cur[0], cur[1]]
		WingMech.attach(model, k)
		WingMech.attach_detail(model, k)
		WingMech.attach_tail(model, k)
		var bay := WingMech.attach_bay(model, k)
		if bay != null:
			WingMech.pose_bay(bay, 1.0)
		WingMech.attach_props(model, k)
		Insignia.attach(model, k, "player")
		Livery.apply(model, cur[0], cur[1], cur[2])
		if cur[3] == 0:
			cam.position = Vector3(cos(-2.3), 0.0, sin(-2.3)) * cos(0.45) * 0.95 + Vector3(0, sin(0.45) * 0.95, 0)
			cam.look_at(Vector3.ZERO, Vector3.UP)
		elif cur[3] == 1:
			cam.position = Vector3(0, 1.15, 0.001)
			cam.look_at(Vector3.ZERO, Vector3(1, 0, 0))
		elif cur[3] >= 3:   # крупные планы: [фокус, рысканье, тангаж, дальность] — как камера ангара
			var cv: Array = CLOSE[cur[3] - 3]
			var dir := Vector3(cos(cv[2]) * cos(cv[1]), sin(cv[2]), cos(cv[2]) * sin(cv[1]))
			cam.position = cv[0] + dir * float(cv[3])
			cam.look_at(cv[0], Vector3.UP)
		else:   # крупно кабина: место фонаря — как у модулей прокачки (ModuleParts._measure)
			ModuleParts.attach(model, k)
			var cp: Vector3 = (ModuleParts._anchors.get(k, {}) as Dictionary).get("canopy", Vector3(0.2, 0.05, 0))
			cam.position = cp + Vector3(0.22, 0.17, -0.25)
			cam.look_at(cp, Vector3.UP)
		frames = 0
		return
	frames += 1
	if frames == 3:
		var img := vp.get_texture().get_image()
		shots.append([cur.duplicate(), img])
		cur = []

func _sheet():
	var w := 560 * sc
	var h := 400 * sc
	var cols := 4
	var rows := int(ceil(shots.size() / float(cols)))
	var out := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var img: Image = shots[i][1]
		img.convert(Image.FORMAT_RGBA8)
		out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	var name := "user://livery_%s.png" % ("_".join(OS.get_cmdline_user_args()).replace("=", ""))
	out.save_png(name)
	print("SHEET ", ProjectSettings.globalize_path(name))
