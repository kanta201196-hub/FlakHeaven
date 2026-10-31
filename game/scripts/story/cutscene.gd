class_name Cutscene
extends RefCounted
## In-engine story scenes (plan step 2, design `docs/story/cutscenes-and-presentation.md` §3.4): the camera flies
## over the live sortie terrain, the player's flight (TitleFlight models) sits at the screen anchor, captions in a
## letterbox. The world stays paused (`Main.state == "cutscene"`), so nothing in the sortie moves or fires.
## Any key, button or click skips (real input events only, so the autotest bot's synthetic actions do not); the autotest skips at SKIP_AUTOTEST s and logs the scene. The light preset is
## restored and the camera returns to the player when the scene ends, then `Main` goes to `next_state`.

const SKIP_AUTOTEST := 0.2
const SKIP_ARM := 0.3   # s before a press counts as a skip (the press that started the sortie must not skip)

static var active := false
static var id := ""
static var def := {}
static var t := 0.0
static var next_state := "playing"
static var anchor := Vector2.ZERO
static var _flight := false
static var _skip := false   # a real key, button or click arrived (Main._input); synthetic bot actions do not count


## Starts a scene. `scene_id` is the campaign flag name ("intro_pass"); `after` — Main state when it ends.
static func play(m: Main, scene_id: String, scene: Dictionary, after: String) -> void:
	if scene.is_empty():
		m._set_state(after)
		return
	active = true
	id = scene_id
	def = scene
	t = 0.0
	next_state = after
	anchor = m.player.global_position if is_instance_valid(m.player) else m.camera.global_position
	_flight = bool(def.get("flight", false))
	_skip = false
	TitleFlight.override = _flight
	TitleFlight.ov_heading = float(def.get("heading", TitleFlight.H0))
	m._set_state("cutscene")
	var k0: Array = (def["cam"] as Array)[0]
	m.camera.global_position = anchor + (k0[1] as Vector2)
	m.camera.zoom = Vector2.ONE * float(k0[2])
	m.camera.reset_smoothing()
	if m.render3d != null:
		m.render3d.set_light(String(def.get("light", "day")))
	if OS.get_cmdline_user_args().has("--autotest"):
		print("CUTSCENE %s started" % id)


## Whether the flight of hangar models is shown this scene (Render3D asks each frame).
static func flight_on() -> bool:
	return active and _flight


## Pure maths live in `CutsceneKeys` (unit-tested); these wrappers keep the HUD's call sites short.
static func cam_at(scene: Dictionary, tt: float) -> Array:
	return CutsceneKeys.cam_at(scene, tt)


static func line_at(scene: Dictionary, tt: float) -> Array:
	return CutsceneKeys.line_at(scene, tt)


static func fade_at(tt: float, dur: float) -> float:
	return CutsceneKeys.fade_at(tt, dur)


## Called from `Main._process` while the state is "cutscene"; `dt` is real seconds.
static func tick(m: Main, dt: float) -> void:
	if not active:
		m._set_state(next_state)
		return
	t += minf(dt, 0.1)   # a long frame (terrain chunks building on the first frames) must not eat the scene
	var c := cam_at(def, t)
	m.camera.global_position = anchor + (c[0] as Vector2)
	m.camera.zoom = Vector2.ONE * float(c[1])
	var args := OS.get_cmdline_user_args()
	var autotest := args.has("--autotest")
	# `--cutshot`: hold the scene to its middle, save one frame for the review page, then skip as the autotest does
	# (separate from `--shots`, whose screen tour drives the states itself)
	var skip_at := float(def.get("dur", 1.0)) * 0.5 if args.has("--cutshot") else SKIP_AUTOTEST
	if autotest and t >= skip_at:
		if args.has("--cutshot"):
			var img := m.get_viewport().get_texture().get_image()
			if img != null:
				img.save_png("user://shot_cutscene_%s.png" % id)
		print("CUTSCENE %s skipped" % id)
		finish(m)
	elif t >= float(def.get("dur", 0.0)):
		finish(m)
	elif t >= SKIP_ARM and _skip:
		finish(m)
	_skip = false


## A press from the player (key, mouse or gamepad button): the scene skips on its next tick once armed.
static func request_skip(event: InputEvent) -> void:
	if not active or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_skip = true


## Ends the scene: light and camera back, flag the scene as seen, hand over to `next_state`.
static func finish(m: Main) -> void:
	if not active:
		return
	active = false
	TitleFlight.override = false
	if m.render3d != null:
		m.render3d.set_light("day")
	if is_instance_valid(m.player):
		m.camera.global_position = m.player.global_position
		m.camera.reset_smoothing()
	if not m.aces():
		Campaign.mark_story_scene(id)
	m._set_state(next_state)
