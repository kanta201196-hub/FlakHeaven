extends Node3D
## Model studio (VIS-01, Kanta 24.10: every model is reviewed in large close-ups on all graphics presets).
## Shows a set of game models on a flat sand plane under the game's sun, environment and graphics preset
## (the same engine calls as Render3D._ready / apply_gfx), with the game's own materials: village houses
## through VillageHouses, biome props through BiomeProps (tree cards below the Maximum preset, as in a sortie),
## battle units straight from their GLB. Each set is shot from a 3/4 view (35° above the horizon) and from
## straight above, framed on its bounds.
##
## Run (Forward+ needs a Vulkan device; in the cloud lavapipe):
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -s "-screen 0 1920x1080x24" \
##     godot --path game --rendering-method forward_plus --resolution 1920x1080 res://tools/model_lab/studio.tscn \
##     -- --gfx=2 --sets=houses,palms --out=/abs/dir
##   -> <out>/studio_<set>_<view>_g<gfx>.png, view = iso | top. --sets omitted: every set in SETS.

## Set → parts [source, what, x, z, width, yaw°]. source: "house" (VillageHouses variant, metres), "prop"
## (BiomeProps kind, width in world px like KINDS), "unit" (battle GLB under res://models/battle/, width = its
## sprite length). Widths only matter inside a set: the set is scaled to a fixed size before framing.
const SETS := {
	"houses": [["house", 0, -9.0, -4.0, 0.0, 10.0], ["house", 2, 7.0, -7.0, 0.0, -5.0], ["house", 5, 8.0, 4.0, 0.0, 90.0],
		["house", 7, -6.0, 9.0, 0.0, 180.0], ["house", 8, 1.5, 1.0, 0.0, 30.0]],
	"palms": [["prop", "palm", 0.0, 0.0, 38.0, 0.0], ["prop", "palm", 26.0, -10.0, 32.0, 70.0],
		["prop", "palm", -22.0, -14.0, 36.0, 140.0], ["prop", "palm", 12.0, 24.0, 28.0, 200.0],
		["prop", "palm", -18.0, 20.0, 30.0, 260.0], ["prop", "well", -2.0, -32.0, 11.0, 15.0]],
	"rocks": [["prop", "outcrop_b", 0.0, 0.0, 70.0, 0.0], ["prop", "spire_b", 52.0, -18.0, 40.0, 30.0],
		["prop", "boulders_b", -40.0, 22.0, 26.0, 0.0], ["prop", "boulders_b", -30.0, -30.0, 20.0, 120.0],
		["prop", "boulders_b", 34.0, 30.0, 24.0, 240.0]],
	# village clutter and market props (VillageHouses.PROPS, metres)
	"vprops": [["house", 9, -10.0, -7.0, 0.0, 0.0], ["house", 10, 2.0, -7.5, 0.0, 0.0],
		["house", 18, -10.0, -1.0, 0.0, 0.0], ["house", 19, -5.5, -1.0, 0.0, 0.0], ["house", 20, -1.0, -1.0, 0.0, 0.0],
		["house", 22, 3.5, -1.0, 0.0, 0.0], ["house", 21, 8.0, -1.0, 0.0, 0.0],
		["house", 11, -9.5, 4.0, 0.0, 0.0], ["house", 12, -5.0, 4.0, 0.0, 0.0], ["house", 13, -1.5, 4.0, 0.0, 0.0],
		["house", 14, 2.5, 4.0, 0.0, 0.0], ["house", 15, 7.0, 4.0, 0.0, 0.0],
		["house", 16, -9.5, 8.5, 0.0, 0.0], ["house", 17, -4.0, 8.5, 0.0, 0.0]],
	"radar": [["unit", "fh_battle_e_radar", 0.0, 0.0, 32.0, 30.0]],
	"bunker": [["unit", "fh_battle_e_bunker", 0.0, 0.0, 59.0, -40.0]],   # the embrasure side
	"bunker_rear": [["unit", "fh_battle_e_bunker", 0.0, 0.0, 59.0, 150.0]],   # the trench and door
	"manpads": [["unit", "fh_battle_e_convoy_manpads", 0.0, 0.0, 14.0, 30.0]],
	"pickup": [["unit", "fh_battle_e_convoy_pickup_tent", 0.0, 0.0, 14.0, 30.0]],
	"fortress": [["unit", "fh_battle_e_fortress", 0.0, 0.0, 270.0, 30.0]],
	"fortress_dome": [["unit", "fh_battle_e_fortress", 0.0, 0.0, 270.0, 30.0]],
}
## Sets framed on one node of the model instead of the whole set: set → [node name, bounds growth]. A boss is
## too big for its small parts to show in a whole-model frame (the Fortress dome turrets, weathering review).
const FOCUS := {"fortress_dome": ["turret_3", 3.2]}
const SIZE := 20.0          ## a set's longest side after scaling, units
const ISO_PITCH := 35.0     ## 3/4 view: degrees above the horizon
const ISO_YAW := 35.0       ## and around from the front (+z)

var _out := "user://"
var _gfx := 2
var _queue := []
var _cam: Camera3D
var _sun: DirectionalLight3D
var _set_root: Node3D
var _wait := 0


func _ready() -> void:
	var sets := SETS.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gfx="):
			_gfx = int(a.substr(6))
		elif a.begins_with("--sets="):
			sets = Array(a.substr(7).split(","))
		elif a.begins_with("--out="):
			_out = a.substr(6)
	Settings.set_preset(_gfx)
	_build_world()
	for s in sets:
		for v in ["iso", "top"]:
			_queue.append([s, v])


## Sky, sun and sand like Render3D._ready, with the preset's shadows, AA, render scale, SSAO and SSIL
func _build_world() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.47, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.68, 0.82)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = Tuning.g("light_exposure")
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.05
	if Settings.forward_plus():
		e.tonemap_exposure = Tuning.g("light_exposure") * Render3D.FP_EXPOSURE_K
		e.adjustment_saturation = Render3D.FP_SATURATION
		e.adjustment_contrast = Render3D.FP_CONTRAST
		e.ambient_light_energy = Render3D.FP_AMBIENT
		e.glow_enabled = Settings.gopt("glow") > 0
		e.glow_intensity = 0.9
		e.glow_bloom = 0.0
		e.glow_hdr_threshold = 1.0
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		var ao := Settings.gopt("ssao")
		e.ssao_enabled = ao > 0
		if ao > 0:
			RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
				RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][ao], true, 0.5, 2, 50.0, 300.0)
		e.ssil_enabled = Settings.gopt("ssil") > 0
	we.environment = e
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.9, 0.76)
	_sun.light_energy = 1.15
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = SIZE * 4.0
	_sun.shadow_bias = 0.03
	_sun.shadow_opacity = 0.8
	_sun.basis = Basis.looking_at(Vector3(0.62, -0.85, 0.75).normalized(), Vector3(0, 0, -1))
	var sh := Settings.gopt("shadows")
	_sun.shadow_enabled = sh != GfxPresets.SHADOWS_OFF
	RenderingServer.directional_soft_shadow_filter_set_quality(Render3D.SHADOW_FILTER[sh])
	RenderingServer.directional_shadow_atlas_set_size(GfxPresets.SHADOW_RES[Settings.gopt("shadow_res")], true)
	add_child(_sun)
	var vp := get_viewport()
	var aa := Settings.gopt("aa")
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
		Viewport.MSAA_8X, Viewport.MSAA_DISABLED][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == GfxPresets.AA_FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == GfxPresets.AA_TAA
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][Settings.gopt("upscale")]
	vp.scaling_3d_scale = GfxPresets.SCALES[Settings.gopt("scale")] / 100.0
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE * 12.0, SIZE * 12.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://art/ground/pbr/sand_albedo.jpg")
	gm.uv1_triplanar = true
	gm.uv1_world_triplanar = true
	gm.uv1_scale = Vector3.ONE * (1.0 / 6.0)
	gm.albedo_color = Color(0.78, 0.76, 0.74)   # the raw tile is brighter than the game's graded ground
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = Render3D.FOV
	_cam.near = 0.1
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true


func _process(_d: float) -> void:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var item: Array = _queue.pop_front()
			var path := _out.path_join("studio_%s_%s_g%d.png" % [item[0], item[1], _gfx])
			get_viewport().get_texture().get_image().save_png(path)
			print("STUDIO ", path)
		return
	if _queue.is_empty():
		get_tree().quit()
		return
	var item: Array = _queue[0]
	if item[1] == "iso":
		_show(item[0])
	_frame(item[1], item[0])
	_wait = 12   # TAA, SSAO and the shadow atlas settle over a few frames


## Builds set `name`: every part at its place and width, the whole scaled so its longest side is SIZE
func _show(name: String) -> void:
	if _set_root != null:
		_set_root.free()
	_set_root = Node3D.new()
	add_child(_set_root)
	var props := BiomeProps.new(null)
	for part: Array in SETS[name]:
		var n := Node3D.new()
		var body: Node3D = null
		match String(part[0]):
			"house":
				var mi := MeshInstance3D.new()
				mi.mesh = VillageHouses._mesh(int(part[1]))
				if int(part[1]) == VillageHouses.WELL:
					mi.scale = Vector3.ONE * VillageHouses.WELL_SCALE
				body = mi
			"prop":
				var mi := MeshInstance3D.new()
				mi.mesh = props._mesh(String(part[1]))
				mi.scale = Vector3.ONE * float(part[4])
				body = mi
			"unit":
				body = (load("res://models/battle/%s.glb" % part[1]) as PackedScene).instantiate()
				body.scale = Vector3.ONE * float(part[4])
		n.add_child(body)
		n.position = Vector3(float(part[2]), 0.0, float(part[3]))
		n.rotation_degrees.y = float(part[5])
		_set_root.add_child(n)
	var box := _bounds(_set_root, Transform3D.IDENTITY)
	var k := SIZE / maxf(maxf(box.size.x, box.size.z), 0.001)
	_set_root.scale = Vector3.ONE * k
	_set_root.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k


## Camera on the set's bounds (or on its FOCUS node, grown): `iso` from ISO_PITCH above the horizon, `top` straight down
func _frame(view: String, set_name := "") -> void:
	var box := _bounds(_set_root, Transform3D.IDENTITY)
	if FOCUS.has(set_name):
		var f: Node3D = _set_root.find_child(FOCUS[set_name][0], true, false) as Node3D
		if f != null:
			var fb := _bounds(f, f.get_parent().global_transform)
			box = AABB(fb.get_center() - fb.size * 0.5 * FOCUS[set_name][1], fb.size * FOCUS[set_name][1])
	var c := box.get_center()
	var r := box.size.length() * 0.5
	var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 0.6   # the set fills about 80 % of the frame height
	if view == "iso":
		var dir := Vector3(0, sin(deg_to_rad(ISO_PITCH)), cos(deg_to_rad(ISO_PITCH))).rotated(Vector3.UP, deg_to_rad(ISO_YAW))
		_cam.global_position = c + dir * dist
		_cam.look_at(c, Vector3.UP)
	else:
		_cam.global_position = c + Vector3.UP * dist
		_cam.look_at(c, Vector3(0, 0, -1))


## Bounds of every mesh under `n` in the space of xf (n's parent), as drawn
func _bounds(n: Node, xf: Transform3D) -> AABB:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	var box := AABB()
	var first := true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		box = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for ch in n.get_children():
		var b := _bounds(ch, t)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box
