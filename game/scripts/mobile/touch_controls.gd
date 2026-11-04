extends CanvasLayer
## Minimal touch controls for the Android draft: a floating stick on the left half of the screen
## drives move_* (as a gamepad stick would), and three round buttons on the right press roll,
## afterburner and pause. Guns fire on their own (auto mode), so no fire button is needed. Shown
## only while a sortie is flown and not paused; menus, cards and the hangar take plain taps
## (Godot turns a tap into a mouse click).

## Stick radius at the 1080-px-high reference screen; scaled with the screen height
const STICK_R := 150.0
const BUTTON_R := 95.0
const PAUSE_R := 55.0
## Button centres as fractions of the screen size, right side
const BUTTONS := [
	{"action": "roll", "label": "Бочка", "pos": Vector2(0.90, 0.78), "r": BUTTON_R},
	{"action": "afterburner", "label": "Форсаж", "pos": Vector2(0.77, 0.86), "r": BUTTON_R},
	{"action": "pause", "label": "II", "pos": Vector2(0.95, 0.08), "r": PAUSE_R},
]

var _view: Control
## Touch index → button index, or −1 for the stick
var _touches := {}
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_on := false


func _ready() -> void:
	layer = 90
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)


func _process(_delta: float) -> void:
	var on := _active()
	if visible != on:
		visible = on
		if not on:
			_release_all()
	if on:
		_view.queue_redraw()


## A sortie is being flown and nothing covers it: Main sets the screen cap off only in flight.
func _active() -> bool:
	return not Settings.screen_cap and not get_tree().paused


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
		if _touches.get(d.index, -2) == -1:
			_stick_pos = d.position
			_send_stick()
		get_viewport().set_input_as_handled()


func _touch_down(index: int, pos: Vector2) -> void:
	var size := _view.size
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		if pos.distance_to(_centre(b, size)) <= _radius(b["r"], size):
			_touches[index] = i
			_press(b["action"], true)
			return
	if pos.x < size.x * 0.5 and not _stick_on:
		_touches[index] = -1
		_stick_on = true
		_stick_origin = pos
		_stick_pos = pos
		_send_stick()


func _touch_up(index: int) -> void:
	if not _touches.has(index):
		return
	var i: int = _touches[index]
	_touches.erase(index)
	if i == -1:
		_stick_on = false
		_stick_pos = _stick_origin
		_send_stick()
	else:
		_press(BUTTONS[i]["action"], false)


func _release_all() -> void:
	for index in _touches.keys():
		_touch_up(index)


## Sends the stick as four move_* action strengths, like a gamepad's left stick.
func _send_stick() -> void:
	var v := (_stick_pos - _stick_origin) / _radius(STICK_R, _view.size)
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


func _centre(b: Dictionary, size: Vector2) -> Vector2:
	return (b["pos"] as Vector2) * size


func _radius(r: float, size: Vector2) -> float:
	return r * size.y / 1080.0


func _draw_view() -> void:
	var size := _view.size
	var font := ThemeDB.fallback_font
	var fs := int(30.0 * size.y / 1080.0)
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		var held := _touches.values().has(i)
		var c := _centre(b, size)
		var r := _radius(b["r"], size)
		_view.draw_circle(c, r, Color(1, 1, 1, 0.28 if held else 0.14))
		_view.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		var text := tr(b["label"])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_view.draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1, 0.85))
	if _stick_on:
		var sr := _radius(STICK_R, size)
		_view.draw_arc(_stick_origin, sr, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(sr)
		_view.draw_circle(knob, sr * 0.4, Color(1, 1, 1, 0.35))
