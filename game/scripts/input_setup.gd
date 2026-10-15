extends Node
## Раскладка управления: клавиатура + мышь + геймпад.
## Используются физические клавиши — WASD работает и на русской раскладке.
## Полное переназначение клавиш появится позже (в прототипе — фиксированная раскладка).


func _ready() -> void:
	_add("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_add("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_add("move_up", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add("move_down", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add("fire", [KEY_J], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [MOUSE_BUTTON_LEFT])
	_add("toggle_fire_mode", [KEY_Q], [JOY_BUTTON_Y])
	_add("roll", [KEY_SPACE], [JOY_BUTTON_A])
	_add("afterburner", [KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER])
	_add("throttle_cut", [KEY_CTRL], [JOY_BUTTON_LEFT_SHOULDER])
	_add("sharp_turn", [KEY_E], [JOY_BUTTON_X])
	_add("skill_2", [KEY_F], [JOY_BUTTON_B])
	_add("toggle_scheme", [KEY_F2], []) # 3.4: без L3 — нажатие стика в бою случайно меняло схему
	_add("toggle_tuning", [KEY_F1], [])
	_add("toggle_numbers", [KEY_F3], [])
	_add("toggle_sprites", [KEY_F4], [])
	_add("pause", [KEY_ESCAPE], [JOY_BUTTON_BACK])
	_add("restart", [KEY_R], [JOY_BUTTON_START])
	_add("loadout", [KEY_TAB], [])
	_add("fire_hardpoint", [KEY_K], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [MOUSE_BUTTON_RIGHT])
	_add("reroll", [KEY_R], [])
	_add("change_class", [KEY_C], [])
	_add("ui_hangar", [KEY_H], [])
	_add("debug_level", [KEY_F5], [])
	_add("debug_skip", [KEY_F6], [])
	_add("debug_god", [KEY_F7], [])
	_add("debug_activity", [KEY_F8], [])
	_add("choose_1", [KEY_1, KEY_KP_1], [JOY_BUTTON_A])
	_add("choose_2", [KEY_2, KEY_KP_2], [JOY_BUTTON_X])
	_add("choose_3", [KEY_3, KEY_KP_3], [JOY_BUTTON_B])
	_add("choose_4", [KEY_4, KEY_KP_4], [JOY_BUTTON_Y])


func _add(action: StringName, keys: Array, buttons: Array, axes: Array = [], mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action, jm)
	for mb in mouse:
		var me := InputEventMouseButton.new()
		me.button_index = mb
		InputMap.action_add_event(action, me)
