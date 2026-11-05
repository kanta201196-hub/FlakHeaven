extends CanvasLayer
## Touch controls for phones and tablets (Android draft, scheme «стик + кнопки навыков», Kanta's
## pick 05.11 pending). Left half: a floating stick that appears under the thumb and drives
## move_* like a gamepad stick. Right corner: an arc of skill buttons for the right thumb — the
## same skills, icons and cooldowns as the PC skill bar (HudFlight.skill_list), which is hidden on
## touch screens. A «Пуск» button appears only while some weapon is set to fire by button. Guns
## fire on their own. Shown only while a sortie is flown and not paused; menus, cards and the
## hangar take plain taps (Godot turns a tap into a mouse click). Also draws a small perf line
## (fps, frame and script time, draw calls, 3D lines) so a tablet screenshot tells what is slow.

## Sizes in millimetres on the glass, turned into canvas units with the screen's DPI, so a button
## is the same size under the thumb on a 6" phone and an 11" tablet
const STICK_MM := 22.0
const MAIN_MM := 12.0      # the first skill (evade / flares): the one pressed most
const BTN_MM := 9.0
const PAUSE_MM := 6.0
const ARC_MM := 24.0       # arc radius around the main button
const EDGE_MM := 14.0      # main button centre from the right and bottom edges
## Canvas units per mm when the screen gives no DPI (a 6.5" 1080p phone)
const FALLBACK_UPMM := 9.0

var _view: Control
## Touch index → button id (action name) or "stick"
var _touches := {}
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_on := false
## This frame's buttons: [{action, key, fam, cd, full, active, title, c (centre), r}]
var _buttons: Array = []
var _upmm := FALLBACK_UPMM
var _perf_t := 0.0
var _perf := ""


func _ready() -> void:
	layer = 90
	# the tree is paused on every screen but the sortie; the overlay must keep checking to hide/show
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)


func _process(delta: float) -> void:
	var on := _active()
	if visible != on:
		visible = on
		if not on:
			_release_all()
	if not on:
		return
	_upmm = _units_per_mm()
	_layout()
	_perf_t -= delta
	if _perf_t <= 0.0:
		_perf_t = 0.5
		_perf = _perf_line()
	_view.queue_redraw()


## A sortie is being flown and nothing covers it: Main sets the screen cap off only in flight.
func _active() -> bool:
	return not Settings.screen_cap and not get_tree().paused and Main.I != null \
		and is_instance_valid(Main.I.player)


## Canvas units per millimetre of glass, from the screen DPI and how the canvas is stretched.
func _units_per_mm() -> float:
	var dpi := DisplayServer.screen_get_dpi()
	var px := float(DisplayServer.window_get_size().y)
	if dpi <= 0 or px <= 0.0:
		return maxf(FALLBACK_UPMM, _view.size.y / 160.0)
	var px_per_mm := float(dpi) / 25.4
	# floor: as if the screen were 160 mm tall (a big tablet), so a wrong or missing DPI never
	# makes buttons smaller than they would be on a 12" tablet
	return clampf(px_per_mm * _view.size.y / px, _view.size.y / 160.0, 20.0)


## Builds this frame's buttons: main skill in the corner, the rest on an arc around it from left
## to straight up, so each sits one thumb roll away.
func _layout() -> void:
	var p: Player = Main.I.player
	var size := _view.size
	var list: Array = HudFlight.skill_list(p)
	if _manual_weapon(p):
		list.append({"key": "", "action": "fire_hardpoint", "title": Loc.t("Пуск"),
			"cd": 0.0, "full": 1.0, "active": 0.0, "fam": "weapon"})
	var main_c := Vector2(size.x - EDGE_MM * _upmm, size.y - EDGE_MM * _upmm)
	_buttons.clear()
	var rest := list.size() - 1
	for i in list.size():
		var b: Dictionary = (list[i] as Dictionary).duplicate()
		if i == 0:
			b["c"] = main_c
			b["r"] = MAIN_MM * _upmm * 0.5
		else:
			# angles from 180° (left of the main button) to 270° (above it)
			var t := 0.5 if rest <= 1 else float(i - 1) / float(rest - 1)
			var a := PI + t * PI * 0.5
			b["c"] = main_c + Vector2.from_angle(a) * ARC_MM * _upmm
			b["r"] = BTN_MM * _upmm * 0.5
		_buttons.append(b)
	_buttons.append({"action": "pause", "key": "", "title": "II", "fam": "", "cd": 0.0, "full": 1.0,
		"active": 0.0, "c": Vector2(size.x * 0.62, PAUSE_MM * _upmm), "r": PAUSE_MM * _upmm * 0.5})


## True while some weapon group fires only on the button (rockets or bombs set to «по кнопке»).
func _manual_weapon(p: Player) -> bool:
	for g in p.groups:
		var hp := g as Hardpoint
		if hp != null and hp.uses_trigger() and hp.trigger != "auto":
			return true
	return false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touches.get(d.index, "") == "stick":
			_stick_pos = d.position
			_send_stick()
		get_viewport().set_input_as_handled()


func _touch_down(index: int, pos: Vector2) -> void:
	for b: Dictionary in _buttons:
		# a little slack around each button: thumbs land off-centre
		if pos.distance_to(b["c"]) <= float(b["r"]) * 1.15:
			_touches[index] = String(b["action"])
			_press(b["action"], true)
			return
	if pos.x < _view.size.x * 0.5 and not _stick_on:
		_touches[index] = "stick"
		_stick_on = true
		_stick_origin = pos
		_stick_pos = pos
		_send_stick()


func _touch_up(index: int) -> void:
	if not _touches.has(index):
		return
	var id: String = _touches[index]
	_touches.erase(index)
	if id == "stick":
		_stick_on = false
		_stick_pos = _stick_origin
		_send_stick()
	else:
		_press(id, false)


func _release_all() -> void:
	for index in _touches.keys():
		_touch_up(index)


## Sends the stick as four move_* action strengths, like a gamepad's left stick.
func _send_stick() -> void:
	var v := (_stick_pos - _stick_origin) / (STICK_MM * 0.5 * _upmm)
	v = v.limit_length(1.0)
	_press("move_left", v.x < 0.0, -v.x)
	_press("move_right", v.x > 0.0, v.x)
	_press("move_up", v.y < 0.0, -v.y)
	_press("move_down", v.y > 0.0, v.y)


## Feeds an action event, so both polling (is_action_pressed) and _input handlers see it.
func _press(action: StringName, on: bool, strength: float = 1.0) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = on
	e.strength = clampf(strength, 0.0, 1.0) if on else 0.0
	Input.parse_input_event(e)


## «FPS 41 · 24 ms · scripts 9 ms · calls 820 · 3D 540 px»: frame time, GDScript+engine process
## time, draw calls and the 3D render height — enough to tell CPU-bound from GPU-bound.
func _perf_line() -> String:
	var fps := Engine.get_frames_per_second()
	var ms := 1000.0 / maxf(fps, 1.0)
	var scr := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var lines := int(float(DisplayServer.window_get_size().y) * get_viewport().scaling_3d_scale)
	return "FPS %d · %d ms · scripts %d ms · calls %d · 3D %d px" % [fps, int(ms), int(scr), calls, lines]


func _draw_view() -> void:
	var font := ThemeDB.fallback_font
	for b: Dictionary in _buttons:
		var held := _touches.values().has(String(b["action"]))
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		_view.draw_circle(c, r, Color(0, 0, 0, 0.38 if held else 0.22))
		var cd: float = float(b.get("cd", 0.0))
		var active: float = float(b.get("active", 0.0))
		var ring := UiStyle.ACCENT if active > 0.0 else Color(1, 1, 1, 0.55 if cd <= 0.0 else 0.25)
		_view.draw_arc(c, r, 0.0, TAU, 48, ring, 3.0 if active <= 0.0 else 5.0)
		if String(b["key"]) != "":
			var side := r * 1.1
			var tile := Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))
			HudIcons.tile(_view, tile, String(b["key"]), String(b["fam"]), Color(1, 1, 1, 0.0), -1, 0.0, cd > 0.0 and active <= 0.0)
		else:
			var fs0 := int(r * 0.8)
			var tw := font.get_string_size(String(b["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs0).x
			_view.draw_string(font, c + Vector2(-tw * 0.5, fs0 * 0.35), String(b["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, Color(1, 1, 1, 0.85))
		if cd > 0.0 and active <= 0.0:
			# cooldown: the dark part shrinks clockwise from 12 o'clock, seconds in the middle
			var frac := clampf(cd / maxf(float(b["full"]), 0.01), 0.0, 1.0)
			if frac > 0.01:
				_view.draw_arc(c, r * 0.5, -PI / 2.0 + TAU * (1.0 - frac), PI * 1.5, 32, Color(0, 0, 0, 0.5), r)
			var s := ("%.1f" % cd) if cd < 10.0 else str(int(ceil(cd)))
			var fs := int(r * 0.6)
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_view.draw_string_outline(font, c + Vector2(-w * 0.5, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
			_view.draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if b.has("title") and String(b["key"]) != "":
			var t := String(b["title"]).to_upper()
			var tfs := 15
			var ttw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
			_view.draw_string_outline(font, c + Vector2(-ttw * 0.5, r + 16.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 4, Color(0, 0, 0, 0.8))
			_view.draw_string(font, c + Vector2(-ttw * 0.5, r + 16.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(1, 1, 1, 0.85))
	if _stick_on:
		var sr := STICK_MM * 0.5 * _upmm
		_view.draw_arc(_stick_origin, sr, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(sr)
		_view.draw_circle(knob, sr * 0.4, Color(1, 1, 1, 0.35))
	if Settings.show_fps and _perf != "":
		_view.draw_string_outline(font, Vector2(12.0, _view.size.y * 0.5), _perf, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		_view.draw_string(font, Vector2(12.0, _view.size.y * 0.5), _perf, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.7, 0.9))
