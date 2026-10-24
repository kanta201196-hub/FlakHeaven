class_name Binds
extends RefCounted
## Key binding table behind the controls tab (UI-01 step 4). Every rebindable action has three
## slots: a key, an alternative key (a mouse button also counts as a key) and a gamepad input.
## A slot holds a token string so the table saves to JSON as is: "k:<physical keycode>",
## "m:<mouse button>", "jb:<gamepad button>", "ja:<axis>:+" or "ja:<axis>:-", "" when empty.
## Pure rules, unit-tested in `game/tests/binds_test.gd`; `Settings` applies the table to InputMap.

const KEY1 := 0
const KEY2 := 1
const PAD := 2

## Glyph file names (game/art/glyphs/<family>/<name>.png) per gamepad button
const BUTTON_GLYPH := {
	JOY_BUTTON_A: "a", JOY_BUTTON_B: "b", JOY_BUTTON_X: "x", JOY_BUTTON_Y: "y",
	JOY_BUTTON_LEFT_SHOULDER: "lb", JOY_BUTTON_RIGHT_SHOULDER: "rb",
	JOY_BUTTON_LEFT_STICK: "ls", JOY_BUTTON_RIGHT_STICK: "rs",
	JOY_BUTTON_BACK: "back", JOY_BUTTON_START: "start",
	JOY_BUTTON_DPAD_UP: "dup", JOY_BUTTON_DPAD_DOWN: "ddown", JOY_BUTTON_DPAD_LEFT: "dleft", JOY_BUTTON_DPAD_RIGHT: "dright",
}

## Text names per glyph for each controller family (the hint bars and key labels in the HUD)
const PAD_TEXT := {
	"xbox": {"a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT", "ls": "LS", "rs": "RS",
		"back": "View", "start": "Menu"},
	"ps": {"a": "✕", "b": "○", "x": "□", "y": "△", "lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "ls": "L3", "rs": "R3",
		"back": "Create", "start": "Options"},
	"deck": {"a": "A", "b": "B", "x": "X", "y": "Y", "lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "ls": "L3", "rs": "R3",
		"back": "View", "start": "Menu"},
}

## Shared names for d-pad and stick directions (same on every family)
const DIR_TEXT := {"dup": "D↑", "ddown": "D↓", "dleft": "D←", "dright": "D→",
	"l_left": "L←", "l_right": "L→", "l_up": "L↑", "l_down": "L↓",
	"r_left": "R←", "r_right": "R→", "r_up": "R↑", "r_down": "R↓"}


## Token for an input event, "" when the event kind can't be bound.
static func token_of(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var p := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "k:%d" % p if p != KEY_NONE else ""
	if ev is InputEventMouseButton:
		return "m:%d" % (ev as InputEventMouseButton).button_index
	if ev is InputEventJoypadButton:
		return "jb:%d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return "ja:%d:%s" % [m.axis, "+" if m.axis_value >= 0.0 else "-"]
	return ""


## Input event for a token (what goes into InputMap), null for an empty or broken token.
static func event_of(token: String) -> InputEvent:
	var p := token.split(":")
	if p.size() < 2 or not p[1].is_valid_int():
		return null
	var n := int(p[1])
	match p[0]:
		"k":
			if p.size() != 2 or n <= 0:
				return null
			var k := InputEventKey.new()
			k.physical_keycode = n as Key
			return k
		"m":
			if p.size() != 2 or n <= 0:
				return null
			var mb := InputEventMouseButton.new()
			mb.button_index = n as MouseButton
			return mb
		"jb":
			if p.size() != 2 or n < 0 or n >= JOY_BUTTON_MAX:
				return null
			var jb := InputEventJoypadButton.new()
			jb.button_index = n as JoyButton
			return jb
		"ja":
			if p.size() != 3 or n < 0 or n >= JOY_AXIS_MAX or not (p[2] == "+" or p[2] == "-"):
				return null
			var jm := InputEventJoypadMotion.new()
			jm.axis = n as JoyAxis
			jm.axis_value = 1.0 if p[2] == "+" else -1.0
			return jm
	return null


## True for gamepad tokens (they belong to the PAD slot only).
static func is_pad(token: String) -> bool:
	return token.begins_with("jb:") or token.begins_with("ja:")


## Slots read from an action's InputMap events: the first two keyboard keys, then mouse buttons
## as the second key if a slot is still free, and the first gamepad input.
static func from_events(events: Array) -> Array:
	var keys: Array[String] = []
	var mouse: Array[String] = []
	var pad := ""
	for ev: InputEvent in events:
		var t := token_of(ev)
		if t == "":
			continue
		if ev is InputEventKey:
			keys.append(t)
		elif ev is InputEventMouseButton:
			mouse.append(t)
		elif pad == "":
			pad = t
	var both := keys + mouse
	return [both[0] if both.size() > 0 else "", both[1] if both.size() > 1 else "", pad]


## Other [action, slot] pairs already holding `token`. Key slots are compared with key slots and
## the gamepad slot with gamepad slots; an empty token never conflicts.
static func conflicts(table: Dictionary, action: String, slot: int, token: String) -> Array:
	var out := []
	if token == "":
		return out
	var slots := [PAD] if slot == PAD else [KEY1, KEY2]
	for a: String in table:
		for s: int in slots:
			if a == action and s == slot:
				continue
			if str(table[a][s]) == token:
				out.append([a, s])
	return out


## Copy of `table` with `action`'s `slot` set to `token`; the table itself is not changed.
static func with(table: Dictionary, action: String, slot: int, token: String) -> Dictionary:
	var out := table.duplicate(true)
	var row: Array = (out.get(action, ["", "", ""]) as Array).duplicate()
	row[slot] = token
	out[action] = row
	return out


## Like `with`, but whoever held `token` gets the slot's old value («swap» in the conflict row).
static func swapped(table: Dictionary, action: String, slot: int, token: String) -> Dictionary:
	var old := str(table.get(action, ["", "", ""])[slot])
	var out := with(table, action, slot, token)
	for c: Array in conflicts(table, action, slot, token):
		out = with(out, c[0], c[1], old)
	return out


## Table from an old save (action → one physical keycode, before step 4): the old key goes to
## the first slot, the alternative key is cleared when it is the same key, unknown actions are dropped.
static func migrate(defaults: Dictionary, old: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	for a: String in old:
		if not out.has(a):
			continue
		var t := "k:%d" % int(old[a])
		var row: Array = out[a]
		row[KEY1] = t
		if row[KEY2] == t:
			row[KEY2] = ""
	return out


## Table loaded from settings.json: every default action present; an entry must be three strings,
## key tokens (or "") in the key slots and a gamepad token (or "") in the pad slot, else defaults.
static func sanitize(raw: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	for a: String in defaults:
		var r = raw.get(a, null)
		if r is Array and _valid_row(r):
			out[a] = [str(r[0]), str(r[1]), str(r[2])]
	return out


static func _valid_row(r: Array) -> bool:
	if r.size() != 3:
		return false
	for s in 3:
		if not r[s] is String:
			return false
		var t: String = r[s]
		if t == "":
			continue
		if event_of(t) == null or is_pad(t) != (s == PAD):
			return false
	return true


## Glyph file name for a gamepad token ("" when there is no glyph).
static func pad_glyph(token: String) -> String:
	var ev := event_of(token)
	if ev is InputEventJoypadButton:
		return BUTTON_GLYPH.get(int((ev as InputEventJoypadButton).button_index), "")
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		var plus := m.axis_value > 0.0
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "lt"
			JOY_AXIS_TRIGGER_RIGHT:
				return "rt"
			JOY_AXIS_LEFT_X:
				return "l_right" if plus else "l_left"
			JOY_AXIS_LEFT_Y:
				return "l_down" if plus else "l_up"
			JOY_AXIS_RIGHT_X:
				return "r_right" if plus else "r_left"
			JOY_AXIS_RIGHT_Y:
				return "r_down" if plus else "r_up"
	return ""


## Every glyph file name `pad_glyph` can return (for loading them ahead of drawing).
static func glyph_names() -> Array[String]:
	var out: Array[String] = ["lt", "rt"]
	for g: String in BUTTON_GLYPH.values():
		out.append(g)
	for g: String in DIR_TEXT:
		if g.begins_with("l_") or g.begins_with("r_"):
			out.append(g)
	return out


## Short text name of a gamepad token for controller `family` ("xbox", "ps", "deck").
static func pad_text(token: String, family: String) -> String:
	var g := pad_glyph(token)
	if g == "":
		return "?"
	if DIR_TEXT.has(g):
		return DIR_TEXT[g]
	return (PAD_TEXT.get(family, PAD_TEXT["xbox"]) as Dictionary).get(g, g.to_upper())


## Controller family from the name the OS reports (`Input.get_joy_name`).
static func family_of(joy_name: String) -> String:
	var n := joy_name.to_lower()
	if n.contains("sony") or n.contains("dualsense") or n.contains("dualshock") or n.contains("playstation") or n.contains("ps4") or n.contains("ps5"):
		return "ps"
	if n.contains("steam deck"):
		return "deck"
	return "xbox"
