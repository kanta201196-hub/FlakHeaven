extends SceneTree
## Unit tests for `Binds` (UI-01 step 4): the key binding table behind the controls tab. Each
## action has three slots (key, alternative key, gamepad) holding a token string. Rules pinned
## here: tokens round-trip through input events, defaults are read from InputMap events, a key
## already used by another action is a conflict, «swap» hands the old key to that action, old
## one-key saves migrate, and broken saves fall back to defaults.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_tokens()
	_test_from_events()
	_test_conflicts()
	_test_swap()
	_test_migrate()
	_test_sanitize()
	_test_labels()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


func _test_tokens() -> void:
	_check(Binds.token_of(_key(KEY_W)) == "k:%d" % KEY_W, "key token")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	_check(Binds.token_of(mb) == "m:%d" % MOUSE_BUTTON_RIGHT, "mouse button token")
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	_check(Binds.token_of(jb) == "jb:%d" % JOY_BUTTON_A, "gamepad button token")
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = -0.8
	_check(Binds.token_of(jm) == "ja:%d:-" % JOY_AXIS_LEFT_X, "stick direction token")
	for t: String in ["k:%d" % KEY_SPACE, "m:%d" % MOUSE_BUTTON_LEFT, "jb:%d" % JOY_BUTTON_Y, "ja:%d:+" % JOY_AXIS_TRIGGER_RIGHT]:
		_check(Binds.token_of(Binds.event_of(t)) == t, "round trip " + t)
	_check(Binds.event_of("") == null and Binds.event_of("zz:1") == null, "empty or bad token has no event")
	_check(Binds.is_pad("jb:1") and Binds.is_pad("ja:0:+") and not Binds.is_pad("k:87") and not Binds.is_pad("m:1"), "pad tokens")


func _test_from_events() -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_TRIGGER_RIGHT
	jm.axis_value = 1.0
	var s := Binds.from_events([_key(KEY_J), jm, mb])
	_check(s == ["k:%d" % KEY_J, "m:%d" % MOUSE_BUTTON_LEFT, "ja:%d:+" % JOY_AXIS_TRIGGER_RIGHT], "key, mouse as second key, trigger as pad")
	var s2 := Binds.from_events([_key(KEY_A), _key(KEY_LEFT), _key(KEY_Q)])
	_check(s2[Binds.KEY1] == "k:%d" % KEY_A and s2[Binds.KEY2] == "k:%d" % KEY_LEFT and s2[Binds.PAD] == "", "two keys kept, third dropped, no pad")


func _table() -> Dictionary:
	return {
		"roll": ["k:%d" % KEY_SPACE, "", "jb:%d" % JOY_BUTTON_A],
		"afterburner": ["k:%d" % KEY_SHIFT, "", "jb:%d" % JOY_BUTTON_RIGHT_SHOULDER],
		"dive": ["k:%d" % KEY_V, "m:%d" % MOUSE_BUTTON_MIDDLE, "jb:%d" % JOY_BUTTON_RIGHT_STICK],
	}


func _test_conflicts() -> void:
	var t := _table()
	_check(Binds.conflicts(t, "roll", Binds.KEY1, "k:%d" % KEY_SHIFT) == [["afterburner", Binds.KEY1]], "shift is taken by afterburner")
	_check(Binds.conflicts(t, "roll", Binds.KEY1, "k:%d" % KEY_SPACE).is_empty(), "own key is no conflict")
	_check(Binds.conflicts(t, "roll", Binds.KEY2, "m:%d" % MOUSE_BUTTON_MIDDLE) == [["dive", Binds.KEY2]], "mouse button conflicts across key slots")
	_check(Binds.conflicts(t, "roll", Binds.PAD, "jb:%d" % JOY_BUTTON_RIGHT_SHOULDER) == [["afterburner", Binds.PAD]], "gamepad button conflict")
	_check(Binds.conflicts(t, "roll", Binds.KEY1, "").is_empty(), "clearing never conflicts")


func _test_swap() -> void:
	var t := _table()
	var s := Binds.swapped(t, "roll", Binds.KEY1, "k:%d" % KEY_SHIFT)
	_check(s["roll"][Binds.KEY1] == "k:%d" % KEY_SHIFT, "roll gets shift")
	_check(s["afterburner"][Binds.KEY1] == "k:%d" % KEY_SPACE, "afterburner gets roll's old space")
	_check(t["roll"][Binds.KEY1] == "k:%d" % KEY_SPACE, "the input table is not changed")
	var w := Binds.with(t, "roll", Binds.KEY2, "k:%d" % KEY_B)
	_check(w["roll"][Binds.KEY2] == "k:%d" % KEY_B and w["roll"][Binds.KEY1] == "k:%d" % KEY_SPACE, "plain set of the second key")


func _test_migrate() -> void:
	var defaults := {"move_left": ["k:%d" % KEY_A, "k:%d" % KEY_LEFT, "ja:0:-"], "roll": ["k:%d" % KEY_SPACE, "", "jb:0"]}
	var m := Binds.migrate(defaults, {"move_left": float(KEY_J), "unknown": float(KEY_K)})
	_check(m["move_left"] == ["k:%d" % KEY_J, "k:%d" % KEY_LEFT, "ja:0:-"], "old key goes to the first slot, alternative and pad stay")
	_check(m["roll"] == defaults["roll"] and not m.has("unknown"), "untouched and unknown actions")
	var m2 := Binds.migrate(defaults, {"move_left": float(KEY_LEFT)})
	_check(m2["move_left"][Binds.KEY2] == "", "duplicate alternative cleared")


func _test_sanitize() -> void:
	var defaults := {"roll": ["k:32", "", "jb:0"], "dive": ["k:86", "m:3", "jb:8"]}
	var s := Binds.sanitize({"roll": ["k:66", "m:2", "jb:1"], "dive": ["bad", 5], "x": ["k:1", "", ""]}, defaults)
	_check(s["roll"] == ["k:66", "m:2", "jb:1"], "valid entry kept")
	_check(s["dive"] == defaults["dive"], "broken entry falls back to defaults")
	_check(not s.has("x") and s.size() == 2, "unknown actions dropped")
	var s2 := Binds.sanitize({"roll": ["jb:1", "", "k:32"]}, defaults)
	_check(s2["roll"] == defaults["roll"], "gamepad token in a key slot is rejected")


func _test_labels() -> void:
	_check(Binds.pad_glyph("jb:%d" % JOY_BUTTON_A) == "a", "A button glyph")
	_check(Binds.pad_glyph("ja:%d:+" % JOY_AXIS_TRIGGER_RIGHT) == "rt", "right trigger glyph")
	_check(Binds.pad_glyph("ja:%d:-" % JOY_AXIS_LEFT_X) == "l_left", "left stick left glyph")
	_check(Binds.pad_text("jb:%d" % JOY_BUTTON_LEFT_SHOULDER, "xbox") == "LB" and Binds.pad_text("jb:%d" % JOY_BUTTON_LEFT_SHOULDER, "ps") == "L1",
		"shoulder name per controller family")
	_check(Binds.family_of("Sony DualSense Wireless Controller") == "ps" and Binds.family_of("Steam Deck") == "deck"
		and Binds.family_of("Xbox Series X Controller") == "xbox" and Binds.family_of("") == "xbox", "controller family from its name")
	var names := Binds.glyph_names()
	_check(names.size() == 24, "24 glyphs per controller family")
	for n: String in names:
		_check(FileAccess.file_exists("res://art/glyphs/xbox/%s.png" % n) and FileAccess.file_exists("res://art/glyphs/ps/%s.png" % n)
			and FileAccess.file_exists("res://art/glyphs/deck/%s.png" % n), "glyph file " + n)
