class_name Dialog
extends RefCounted
## Hangar dialogue scenes (plan step 3, design `docs/story/highlands-storyline.md` §11): the crew member and a guest
## («Купол», «Гром», «Ключ») talk over the 3D hangar, lines type out, the player advances with Enter / click /
## gamepad A, picks 2–3 options at a choice and skips the whole scene with Esc. Choices are words only: they are
## saved in the campaign (`Campaign.set_story_choice`) and change later lines (`only`), never numbers.
## The world stays paused (`Main.state == "dialog"`). When the scene ends, `then` runs (start the sortie, show the
## results, back to the campaign screen). The branching rules are `DialogFlow` (unit-tested); the picture is `HudDialog`.
## The autotest skips every scene at SKIP_AUTOTEST s and logs `DIALOG <id> skipped`; `--cutshot` saves one frame first.

const SKIP_AUTOTEST := 0.2
const ARM := 0.3       # s before a press counts (the press that opened the scene must not advance it)
const SHOT_AT := 1.6   # `--cutshot`: the frame is saved here, with the first line fully typed
const FADE := 0.4      # s of black at the start

static var active := false
static var id := ""
static var def := {}
static var steps: Array = []
static var i := 0          # current step
static var t := 0.0        # s in the current step (typewriter)
static var total := 0.0    # s in the scene
static var focus := 0      # focused option of a choice step
static var replay := false # from the story log: nothing is saved
static var last_guest := ""   # the guest on the right stays while the crew talks
static var _then := Callable()
static var _choices := {}  # choice id → option, saved ones first, then those made in this scene


## Whether a scene plays now: the «Заставки» setting against the seen flag, and the scene is written.
static func due(scene_id: String) -> bool:
	return Campaign.story_scene_due(scene_id, Settings.cutscenes) and not StoryDialogs.scene(scene_id).is_empty()


## Starts a scene; `then` runs when it ends (skipped or played through). An empty scene runs `then` at once.
static func play(m: Main, scene_id: String, scene: Dictionary, then: Callable, as_replay := false) -> void:
	if scene.is_empty():
		_run(then)
		return
	active = true
	id = scene_id
	def = scene
	steps = def.get("steps", [])
	replay = as_replay
	_then = then
	_choices = {}
	for s: Dictionary in steps:
		if s.has("choice"):
			var saved := Campaign.story_choice(String(s["choice"]))
			if saved != "":
				_choices[String(s["choice"])] = saved
	i = DialogFlow.next_step(steps, 0, _choices)
	t = 0.0
	total = 0.0
	focus = 0
	last_guest = _first_guest()
	m._set_state("dialog")
	if OS.get_cmdline_user_args().has("--autotest"):
		print("DIALOG %s started" % id)
	if i >= steps.size():
		finish(m)


## The step on screen ({} when the scene is over).
static func current() -> Dictionary:
	return steps[i] if active and i < steps.size() else {}


static func is_choice() -> bool:
	return current().has("choice")


## Called from `Main._process` while the state is "dialog"; `dt` is real seconds.
static func tick(m: Main, dt: float) -> void:
	if not active:
		return
	dt = minf(dt, 0.1)
	t += dt
	total += dt
	var args := OS.get_cmdline_user_args()
	if not args.has("--autotest"):
		return
	if args.has("--cutshot"):
		if total >= SHOT_AT - 0.3:
			t = 100.0   # the whole first line on the saved frame
		if total >= SHOT_AT:
			var img := m.get_viewport().get_texture().get_image()
			if img != null:
				img.save_png("user://shot_dialog_%s.png" % id)
			print("DIALOG %s skipped" % id)
			finish(m)
	elif total >= SKIP_AUTOTEST:
		print("DIALOG %s skipped" % id)
		finish(m)


## Enter / click / gamepad A: a line still typing shows whole, a typed line goes to the next step, a choice takes
## the focused option.
static func advance(m: Main) -> void:
	if not active or total < ARM:
		return
	var s := current()
	if s.has("choice"):
		pick(m, focus)
	elif not DialogFlow.typed(String(s.get("text", "")), t):
		t = 100.0
	else:
		_next(m)


## Takes option `k` of the current choice step (number keys, click, Enter on the focused option).
static func pick(m: Main, k: int) -> void:
	if not active or total < ARM or not is_choice():
		return
	var s := current()
	var opt := DialogFlow.option_id(s, k)
	if opt == "":
		return
	_choices[String(s["choice"])] = opt
	if not replay and not m.aces():
		Campaign.set_story_choice(String(s["choice"]), opt)
	m.sfx.play("card", -12.0, 1.3)
	_next(m)


## Moves the option focus of a choice step by `dir` (±1).
static func move(dir: int) -> void:
	if is_choice():
		focus = DialogFlow.move_focus(focus, dir, (current().get("options", []) as Array).size())


## Esc / Back: the whole scene is skipped (still counts as seen).
static func skip(m: Main) -> void:
	if active and total >= ARM:
		finish(m)


## Mouse clicks from the HUD: "dlg:next", "dlg:opt:<k>", "dlg:skip".
static func ui(m: Main, action: String) -> void:
	if action == "dlg:next":
		advance(m)
	elif action == "dlg:skip":
		skip(m)
	elif action.begins_with("dlg:opt:"):
		pick(m, int(action.substr(8)))


static func _next(m: Main) -> void:
	i = DialogFlow.next_step(steps, i + 1, _choices)
	t = 0.0
	focus = 0
	if i >= steps.size():
		finish(m)
		return
	var who := String(current().get("who", ""))
	if who != "" and who != "crew":
		last_guest = who


## Ends the scene: flag it as seen (not on a replay or in «Битва асов»), then run `then`.
static func finish(m: Main) -> void:
	if not active:
		return
	active = false
	if not replay and not m.aces():
		Campaign.mark_story_scene(id)
	var cb := _then
	_then = Callable()
	_run(cb)


static func _run(cb: Callable) -> void:
	if cb.is_valid():
		cb.call()


static func _first_guest() -> String:
	for s: Dictionary in steps:
		var who := String(s.get("who", ""))
		if who != "" and who != "crew":
			return who
	return StoryText.DISPATCH
