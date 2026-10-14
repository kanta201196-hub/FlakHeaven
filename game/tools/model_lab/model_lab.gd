extends SceneTree
## Пилот 3D (этап 0): конвейер моделей в облаке, без Blender.
##
## Соглашение для всех моделей игры (models/*.glb):
##   • нос по +X, верх по +Y (как спрайты: нос вправо, вид сверху — плоскость XZ);
##   • длина по X = 1.0 — игра масштабирует под длину спрайта на экране;
##   • самолёты отцентрованы по высоте, наземное стоит на y = 0;
##   • подвижные части — отдельные узлы: body, turret_1, barrel_1…, pylon_…
##
## Команды (из папки game/):
##   godot --headless --path . --script res://tools/model_lab/model_lab.gd -- build-zsu <out.glb>
##   python3 tools/model_lab/trellis_gen.py <in.png> <seed> <out.glb>   (генерация TRELLIS.2, нужен HF_TOKEN)
##   python3 tools/model_lab/decimate_glb.py <in.glb> <out.glb> [12000]   (упрощение до бюджета)
##   godot --headless --path . --script res://tools/model_lab/model_lab.gd -- prep <in.glb> <out.glb> [--nose=+z] [--ground] [--budget=8000]
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/model_lab/model_lab.gd -- preview <model.glb> <sprite.png> <len_px> <out.png> [--ground] [--turret=40]
##
## Ввод из генераторов (Hunyuan, TRELLIS): glTF смотрит «лицом» в +Z, поэтому по умолчанию
## нос ищется по самой длинной горизонтальной оси, а знак — +Z / +X; при ошибке — --nose=.

const BUDGET_DEFAULT := 15000

var _args: PackedStringArray
var _preview_out := ""
var _frames := 0


func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	if _args.is_empty():
		_fail("нет команды: build-zsu | prep | preview")
		return
	match _args[0]:
		"build-zsu":
			_build_zsu(_arg(1, "user://fh_ground_zsu_code.glb"))
			quit(0)
		"prep":
			quit(_prep(_arg(1, ""), _arg(2, "")))
		"preview":
			_preview(_arg(1, ""), _arg(2, ""), float(_arg(3, "79")), _arg(4, "user://preview.png"))
		_:
			_fail("неизвестная команда " + _args[0])


func _process(_delta: float) -> bool:
	if _preview_out == "":
		return false
	_frames += 1
	if _frames < 8:
		return false
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_preview_out)
	print("ПРЕДПРОСМОТР: ", ProjectSettings.globalize_path(_preview_out))
	_preview_out = ""
	quit(0)
	return true


func _arg(i: int, def: String) -> String:
	var pos := []
	for a in _args:
		if not a.begins_with("--"):
			pos.append(a)
	return pos[i] if i < pos.size() else def


func _flag(name: String, def := "") -> String:
	for a in _args:
		if a == "--" + name:
			return "1"
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func _fail(msg: String) -> void:
	push_error("model_lab: " + msg)
	quit(1)


# ---------- модель машины ПВО кодом ----------

func _mat(c: Color, metal := 0.3, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _put(parent, name, bm, pos, mat)


func _cyl(parent: Node3D, name: String, r: float, len: float, pos: Vector3, mat: Material, along_x := true) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = len
	cm.radial_segments = 10
	cm.rings = 1
	var mi := _put(parent, name, cm, pos, mat)
	if along_x:
		mi.rotation = Vector3(0, 0, PI / 2.0)
	return mi


func _put(parent: Node3D, name: String, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = pos
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	mi.owner = parent.owner if parent.owner != null else parent
	return mi


## Самоходная зенитка «по мотивам» (спрайт e_zsu, 140×105): гусеничный корпус, башня, 4 ствола.
## Геометрия строится в пикселях спрайта (X — вправо, Z — вниз по картинке, Y — вверх),
## потом картинка спрайта проецируется сверху как текстура: детали рисунка остаются,
## а башня и стволы — настоящие отдельные узлы (крутятся вместе со своей частью рисунка).
func _build_zsu(out: String) -> void:
	var tex: Texture2D = load("res://art/enemies/e_zsu.png")
	var sz := Vector2(tex.get_width(), tex.get_height())
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = tex
	skin.metallic = 0.35
	skin.roughness = 0.5
	var top := Node3D.new()
	top.name = "fh_ground_zsu"
	var body := Node3D.new()
	body.name = "body"
	top.add_child(body)
	body.owner = top
	# гусеницы по краям, корпус между ними, кормовая плита
	_box(body, "track_l", Vector3(116, 12, 15), Vector3(60, 6, 8.5), skin)
	_box(body, "track_r", Vector3(116, 12, 15), Vector3(60, 6, 96.5), skin)
	_box(body, "hull", Vector3(114, 12, 80), Vector3(60, 14, 52), skin)
	_box(body, "deck_rear", Vector3(26, 3, 70), Vector3(16, 21.5, 52), skin)
	# башня: точка вращения — центр погона (62, 52)
	var turret := Node3D.new()
	turret.name = "turret_1"
	turret.position = Vector3(62, 20, 52)
	body.add_child(turret)
	turret.owner = top
	var ring := _cyl(turret, "turret_body", 31, 10, Vector3(0, 5, 0), skin, false)
	(ring.mesh as CylinderMesh).radial_segments = 16
	_box(turret, "gun_mount", Vector3(34, 8, 40), Vector3(20, 9, 0), skin)
	var dish := _cyl(turret, "radar", 9, 3, Vector3(0, 12, 0), skin, false)
	(dish.mesh as CylinderMesh).radial_segments = 12
	# 4 ствола: узел у маски, ствол по +X (отдача — по −X)
	var ys := [38.0, 44.5, 59.5, 66.0]
	for i in ys.size():
		var b := Node3D.new()
		b.name = "barrel_%d" % (i + 1)
		b.position = Vector3(86 - 62, 11, ys[i] - 52)
		turret.add_child(b)
		b.owner = top
		_cyl(b, "tube", 1.8, 54, Vector3(27, 0, 0), skin)
	_project_skin(top, sz)
	_normalize(top, true)
	var err := _save_glb(top, out)
	print("ZSU кодом: ", ProjectSettings.globalize_path(out), " треугольников=", _tris(top), " ошибка=", err)
	top.free()


## Переводит примитивы в ArrayMesh с UV = проекция сверху на спрайт (координаты в пикселях спрайта)
func _project_skin(top: Node3D, sz: Vector2) -> void:
	for mi in _meshes(top, []):
		var m: MeshInstance3D = mi
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != top:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var mat := m.get_surface_override_material(0)
		var arr := m.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv := PackedVector2Array()
		uv.resize(vs.size())
		for i in vs.size():
			var w := xf * vs[i]
			uv[i] = Vector2(clampf(w.x / sz.x, 0.002, 0.998), clampf(w.z / sz.y, 0.002, 0.998))
		arr[Mesh.ARRAY_TEX_UV] = uv
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, mat)
		m.mesh = am
		m.set_surface_override_material(0, null)


# ---------- подготовка чужой модели ----------

func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		return null
	return doc.generate_scene(st) as Node3D


func _save_glb(node: Node3D, path: String) -> int:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(node, st)
	if err != OK:
		return err
	return doc.write_to_filesystem(st, path)


func _meshes(n: Node, out: Array) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
	return out


## AABB всех мешей в координатах узла top (без дерева сцены — считаем трансформы сами)
func _aabb(top: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(top, []):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != top:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _tris(top: Node3D) -> int:
	var t := 0
	for mi in _meshes(top, []):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			t += idx.size() / 3 if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


## Длина по X = 1, центр по X/Z в нуле; наземное — дно на y = 0, самолёт — центр по высоте
func _normalize(top: Node3D, ground: bool) -> void:
	var holder := Node3D.new()
	_set_owner(top, null)
	for c in top.get_children():
		top.remove_child(c)
		holder.add_child(c)
	top.add_child(holder)
	holder.name = "pivot"
	var b := _aabb(top)
	var k := 1.0 / maxf(b.size.x, 0.0001)
	var c := b.get_center()
	var y0 := b.position.y if ground else c.y
	holder.transform = Transform3D(Basis().scaled(Vector3(k, k, k)), Vector3(-c.x, -y0, -c.z) * k)
	_set_owner(holder, top)


func _set_owner(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_set_owner(c, owner)


func _prep(src: String, dst: String) -> int:
	if src == "" or dst == "":
		_fail("prep <in.glb> <out.glb>")
		return 1
	var scene := _load_glb(src)
	if scene == null:
		_fail("не читается " + src)
		return 1
	var top := Node3D.new()
	top.name = src.get_file().get_basename()
	_set_owner(scene, null)
	top.add_child(scene)
	scene.owner = top
	_set_owner(scene, top)
	var b := _aabb(top)
	var nose := _flag("nose", "")
	if nose == "":
		nose = "+x" if b.size.x >= b.size.z else "+z"
	var yaw := {"+x": 0.0, "-x": PI, "+z": PI / 2.0, "-z": -PI / 2.0}
	if not yaw.has(nose):
		_fail("--nose = +x | -x | +z | -z")
		return 1
	scene.transform = Transform3D(Basis(Vector3.UP, yaw[nose]), Vector3.ZERO) * scene.transform
	var ground := _flag("ground") != ""
	_normalize(top, ground)
	var nb := _aabb(top)
	var tris := _tris(top)
	var budget := int(_flag("budget", str(BUDGET_DEFAULT)))
	# LOD: те же функции, что у импортёра Godot — проверяем, что сетка упрощается
	var lods := 0
	for mi in _meshes(top, []):
		var m: Mesh = (mi as MeshInstance3D).mesh
		var im := ImporterMesh.new()
		for s in m.get_surface_count():
			im.add_surface(m.surface_get_primitive_type(s), m.surface_get_arrays(s), [], {}, m.surface_get_material(s))
		im.generate_lods(60.0, 0.0, [])
		for s in im.get_surface_count():
			lods = maxi(lods, im.get_surface_lod_count(s))
	var texs := []
	for mi in _meshes(top, []):
		var m2: Mesh = (mi as MeshInstance3D).mesh
		for s in m2.get_surface_count():
			var mat := m2.surface_get_material(s) as BaseMaterial3D
			if mat != null and mat.albedo_texture != null:
				texs.append("%dx%d" % [mat.albedo_texture.get_width(), mat.albedo_texture.get_height()])
	var err := _save_glb(top, dst)
	print("ПОДГОТОВКА: ", src.get_file(), " → ", dst)
	print("  нос: ", nose, "  исходный размер: ", b.size, "  после: ", nb.size)
	print("  треугольников: ", tris, " (бюджет ", budget, ")", "  ← ПРЕВЫШЕН" if tris > budget else "")
	print("  уровней LOD: ", lods, "  текстуры: ", texs, "  мешей: ", _meshes(top, []).size())
	print("  части: ", _part_names(top))
	top.free()
	return 0 if err == OK else 1


func _part_names(n: Node, out := []) -> Array:
	var re := RegEx.create_from_string("^(body|turret_\\d+|barrel_\\d+|pylon_.+|launcher_\\d+)$")
	if re.search(String(n.name)) != null:
		out.append(String(n.name))
	for c in n.get_children():
		_part_names(c, out)
	return out


# ---------- предпросмотр «как в игре сверху» ----------

## Слева — нынешняя выдавленная модель из спрайта, справа — новая модель, свет как в Render3D.
## Верхний ряд — реальный размер в игре (1 px = 1 единица), нижний — ×4.
func _preview(model: String, sprite: String, len_px: float, out: String) -> void:
	var ground := _flag("ground") != ""
	var w := 900
	var h := 640
	root.size = Vector2i(w, h)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.47, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.7, 0.68)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 3000.0
	sun.shadow_bias = 0.05
	sun.basis = Basis.looking_at(Vector3(0.45, -1.0, 0.6).normalized(), Vector3(0, 0, -1))
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, 1000, 0)
	cam.basis = Basis.looking_at(Vector3(0, -1, 0), Vector3(0, 0, -1))
	cam.near = 1.0
	cam.far = 3000.0
	world.add_child(cam)
	cam.current = true
	# земля, как в игре — песок
	var gq := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 2, h * 2)
	gq.mesh = pm
	var gm := StandardMaterial3D.new()
	if ResourceLoader.exists("res://art/ground/g_sand.png"):
		gm.albedo_texture = load("res://art/ground/g_sand.png")
		gm.uv1_scale = Vector3(6, 4, 1)
	gq.material_override = gm
	gq.position = Vector3(0, -70, 0)
	world.add_child(gq)
	var tex: Texture2D = load(sprite) if sprite.begins_with("res://") else ImageTexture.create_from_image(Image.load_from_file(sprite))
	var mdl := _load_glb(model)
	if tex == null or mdl == null:
		_fail("нет спрайта или модели")
		return
	var y := -69.0 if ground else 0.0
	for row in 2:
		var sc := 1.0 if row == 0 else 4.0
		var L := len_px * sc
		var zc := -h * 0.36 if row == 0 else h * 0.12
		# выдавленный спрайт — как Render3D._ensure
		var sp := MeshInstance3D.new()
		sp.mesh = ReliefMesh.build(tex, tex.get_width() * (0.05 if ground else 0.075), 56)
		sp.material_override = ReliefMesh.material(tex)
		var k := L / float(tex.get_width())
		sp.basis = Basis().scaled(Vector3(k, k, k))
		sp.position = Vector3(-w * 0.25, y, zc)
		world.add_child(sp)
		var m: Node3D = mdl if row == 0 else mdl.duplicate()
		m.basis = Basis().scaled(Vector3(L, L, L))
		m.position = Vector3(w * 0.25, y, zc)
		world.add_child(m)
		# --turret=градусы: повернуть башню — проверка, что части модели двигаются отдельно
		var tr := m.find_child("turret_1", true, false) as Node3D
		if tr != null and _flag("turret") != "":
			tr.rotate_y(deg_to_rad(-float(_flag("turret"))))
	var lbl := Label.new()
	lbl.text = "слева — спрайт сейчас · справа — модель · сверху реальный размер, снизу ×4"
	lbl.position = Vector2(12, 8)
	lbl.add_theme_color_override("font_color", Color.BLACK)
	root.add_child(lbl)
	_preview_out = out
