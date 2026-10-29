extends SceneTree
## 3.4-t1 (п. 17): картинки для облегчённых деревьев (пресеты ниже «Максимального»).
## The model is shot from the side and from above on a transparent background; the light tree (BiomeProps._lite_tree)
## is one side card turned to the camera and one horizontal card with the top view.
## Forward+ (the renderer the cards are drawn with; lavapipe in the cloud):
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run godot --path game --rendering-method forward_plus \
##     -s res://tools/model_lab/bake_impostor.gd
## Результат — game/models/biome/<имя>_side.png и <имя>_top.png (256 × 256).
## Только некоторые модели: ... -s res://tools/model_lab/bake_impostor.gd -- b05_orchard_tree
##
## Light (Kanta 28.10: the cards were dark and blotchy next to the full model). The game camera looks down from the
## south, so what it sees of a full tree is mostly sunlit leaf tops. The top view takes the game's sun; the side view
## takes the same sun turned round to the camera's side, otherwise the card shows the crown's shaded back. The ambient
## is lifted and a weak fill light from the opposite side lightens leaves that face away from the sun (double-sided
## leaf cards light their back face dark). Holes: see _fill_holes.
## The date palm's pictures are still the earlier bake (Kanta 28.10 frames: with this light its fronds came out paler
## than the vivid old ones, and the camera-facing card already removed its dark X); bake it only to change that.

const MODELS := ["b04_poplar", "b05_orchard_tree", "b12_date_palm"]
const SIZE := 256

## Hole-filling radius in pixels per model (_fill_holes); the code-built poplar has open gaps between its leaf
## clusters that read as see-through holes on a 6-triangle card
const FILL := {"b04_poplar": 3, "b05_orchard_tree": 2, "b12_date_palm": 1}

## Top views whose crown is closed over the middle (_close_crown): share of the picture's width the trunk's fork
## and the gaps round it show in. The orchard tree's open centre showed its pale branch cross on the top card,
## seen through the side card's crown from the near-top-down camera (Kanta 28.10 review)
const CLOSE_CROWN := {"b05_orchard_tree": 0.3}

## Ambient energy: the game's Forward+ ambient (render3d.gd FP_AMBIENT 0.38) lifted, so the crown's self-shaded
## patches are lighter than on the full model (a 6-triangle card shows them as flat dark blotches)
const AMBIENT := 0.45
## Energy of the fill light opposite the sun
const FILL_LIGHT := 0.25

## Game sun direction (render3d.gd) and its mirror towards the side camera at +Z
const SUN_TOP := Vector3(0.62, -0.85, 0.75)
const SUN_SIDE := Vector3(0.62, -0.85, -0.75)

var _vp: SubViewport
var _cam: Camera3D
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
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
	e.ambient_light_energy = AMBIENT
	# no tonemapping here: the card is unshaded, and the game's exposure and filmic curve apply to it as they do
	# to the lit full model, so the picture must hold the linear lit colour (Forward+ stores it sRGB-encoded)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	_vp.add_child(env)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.9, 0.76)
	_sun.light_energy = 1.15
	_vp.add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.light_color = Color(0.85, 0.9, 1.0)
	_fill.light_energy = FILL_LIGHT
	_vp.add_child(_fill)
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
		var sun_dir: Vector3 = SUN_SIDE if _cur[1] == "side" else SUN_TOP
		_sun.basis = Basis.looking_at(sun_dir.normalized(), Vector3(0, 0, -1))
		_fill.basis = Basis.looking_at(Vector3(-sun_dir.x, -0.4, -sun_dir.z).normalized(), Vector3(0, 0, -1))
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
		img.convert(Image.FORMAT_RGBA8)
		_fill_holes(img, int(FILL.get(_cur[0], 0)))
		if _cur[1] == "top" and CLOSE_CROWN.has(_cur[0]):
			_close_crown(img, float(CLOSE_CROWN[_cur[0]]))
		var path := "res://models/biome/%s_%s.png" % [_cur[0], _cur[1]]
		img.save_png(ProjectSettings.globalize_path(path))
		print("BAKED ", path)
		_cur = []
	return false


## Closes see-through gaps in a baked card: a morphological closing of the alpha mask (grow by r pixels, then
## shrink by r) marks the pinholes and narrow gaps inside the crown, and each one is filled opaque with the mean
## colour of the opaque pixels around it. The outline stays where it was (closing does not grow the silhouette),
## and mipmapped alpha-scissor cards no longer break up into holes at a distance.
func _fill_holes(img: Image, r: int) -> void:
	if r <= 0:
		return
	var n := img.get_width()
	var solid := PackedByteArray()
	solid.resize(n * n)
	for y in n:
		for x in n:
			solid[y * n + x] = 1 if img.get_pixel(x, y).a > 0.5 else 0
	var grown := _morph(solid, n, r, true)
	var closed := _morph(grown, n, r, false)
	var filled := 0
	for y in n:
		for x in n:
			var i := y * n + x
			if solid[i] == 1 or closed[i] == 0:
				continue
			var sum := Color(0, 0, 0, 0)
			var k := 0
			for dy in range(-r - 1, r + 2):
				for dx in range(-r - 1, r + 2):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < n and yy < n and solid[yy * n + xx] == 1:
						sum += img.get_pixel(xx, yy)
						k += 1
			if k > 0:
				var c := sum / float(k)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
				filled += 1
	print("FILLED %d px (r %d)" % [filled, r])


## Closes the middle of a top view: within r_share × width of the centre every see-through or bark pixel (the
## trunk's fork and the gaps round it) takes the pixel of a leafy patch of the crown further out (the same spot
## shifted by about a third of the width, trying eight directions until it lands on leaves), so the centre
## continues the crown's own leaf texture and light instead of a flat fill.
func _close_crown(img: Image, r_share: float) -> void:
	var n := img.get_width()
	var c := Vector2(n, n) * 0.5
	var rc := n * r_share
	var src := img.duplicate() as Image
	var done := 0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5) - c
			if d.length() > rc:
				continue
			var px := src.get_pixel(x, y)
			if px.a > 0.5 and not _bark(px):
				continue
			for k in 8:   # a patch of the crown shifted in whole: the leaves keep their own grain and scale
				var q := Vector2(x, y) + Vector2.from_angle(0.6 + 0.785 * k) * n * 0.36
				var qx := clampi(int(q.x), 0, n - 1)
				var qy := clampi(int(q.y), 0, n - 1)
				var s := src.get_pixel(qx, qy)
				if s.a > 0.5 and not _bark(s):
					img.set_pixel(x, y, Color(s.r, s.g, s.b, 1.0))
					done += 1
					break
	print("CROWN closed %d px" % done)


## A bark pixel of the orchard tree's top view: warmer than the olive leaves (red over green)
func _bark(c: Color) -> bool:
	return c.r > c.g * 1.04


## Square dilation (grow = true) or erosion of a 0/1 mask of side n by radius r
func _morph(m: PackedByteArray, n: int, r: int, grow: bool) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n * n)
	var want := 1 if grow else 0
	for y in n:
		for x in n:
			var v := 1 - want
			for dy in range(-r, r + 1):
				var yy := y + dy
				if yy < 0 or yy >= n:
					if not grow:
						v = 0
					continue
				for dx in range(-r, r + 1):
					var xx := x + dx
					if xx < 0 or xx >= n:
						if not grow:
							v = 0
						continue
					if m[yy * n + xx] == want:
						v = want
						break
				if v == want:
					break
			out[y * n + x] = v
	return out


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var a := mi.global_transform * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out
