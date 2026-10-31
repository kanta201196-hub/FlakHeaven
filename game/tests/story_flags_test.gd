extends SceneTree
## Unit tests for `StoryFlags` and `StoryText` (Highlands story, plan step 1): the «Заставки» setting against the
## seen flag, the «again» line index of recurring pilots, and the text table lookups.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	# scene_due: setting vs seen flag
	_check(StoryFlags.scene_due(StoryFlags.MODE_FIRST, false), "first time: a new scene plays")
	_check(not StoryFlags.scene_due(StoryFlags.MODE_FIRST, true), "first time: a seen scene is skipped")
	_check(StoryFlags.scene_due(StoryFlags.MODE_ALWAYS, true), "always: replays a seen scene")
	_check(not StoryFlags.scene_due(StoryFlags.MODE_NEVER, false), "never: skips even a new scene")
	_check(StoryFlags.MODES.size() == 3, "three setting names")
	# line_index: first meeting → line 0, later meetings cycle through the rest
	_check(StoryFlags.line_index(0, 3) == 0, "first meeting: line 0")
	_check(StoryFlags.line_index(1, 3) == 1, "second meeting: line 1")
	_check(StoryFlags.line_index(2, 3) == 2, "third meeting: line 2")
	_check(StoryFlags.line_index(3, 3) == 1, "fourth meeting: cycles back to line 1, never to the first-meeting line")
	_check(StoryFlags.line_index(5, 1) == 0, "one line: always 0")
	_check(StoryFlags.line_index(-1, 2) == 0, "negative count is treated as the first meeting")
	_check(StoryFlags.line_key("postman", "pass", "spawn") == "postman.pass.spawn", "line key format")
	# text table
	_check(StoryText.radio("baron.taunt").begins_with("Ваш ведущий"), "radio table has the EX-09 taunt")
	_check(StoryText.radio("no.such.key") == "", "unknown radio key → empty string")
	_check(StoryText.op_line("postman", "pass", "spawn", 0) == "", "empty op table → empty string (generic line)")
	_check(StoryText.ENEMY_HQ != StoryText.DISPATCH, "the Fortress controller is not our dispatcher")
	for k in StoryText.RADIO:
		_check(String(StoryText.RADIO[k]).length() <= 120, "radio line fits the panel: " + k)
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
