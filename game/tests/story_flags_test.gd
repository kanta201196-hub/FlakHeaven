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
	_check(StoryText.op_line("postman", "strait", "spawn", 0) == "", "op without story lines → empty string (generic line)")
	_check(StoryText.ENEMY_HQ != StoryText.DISPATCH, "the Fortress controller is not our dispatcher")
	for k in StoryText.RADIO:
		_check(String(StoryText.RADIO[k]).length() <= 120, "radio line fits the panel: " + k)
	# per-operation lines (step 5+): key = speaker.op.moment, every line fits the radio panel
	for k in StoryText.OP_LINES:
		var parts := String(k).split(".")
		_check(parts.size() == 3 and parts[0] in ["postman", "draft", "graf", "hq", "baron"], "op line key is speaker.op.moment: " + k)
		_check(parts[1] in ["pass", "riverbed", "forts", "sky"], "op line key names a Highlands operation: " + k)
		var arr: Array = StoryText.OP_LINES[k]
		_check(not arr.is_empty(), "op line key has lines: " + k)
		for l in arr:
			_check(String(l).length() <= 120, "op line fits the panel: " + k)
		if parts[2].begins_with("spawn_"):
			_check(StoryText.OP_LINES.has("%s.%s.spawn" % [parts[0], parts[1]]), "a spawn variant has its plain spawn line: " + k)
	# op 3 (step 7): Baron speaks through the table, with a variant by the H2′ choice; Graf's one line; the result line
	_check(StoryText.op_line("baron", "forts", "spawn", 0).begins_with("Один на один"), "Baron's challenge is the first-meeting line")
	_check(StoryText.op_line("baron", "forts", "spawn_quiet", 0).contains("Гром"), "quiet lead: Baron still brags about Grom")
	_check(StoryText.op_line("baron", "forts", "spawn_recon", 0).contains("парашют"), "recon lead: Baron knows we search")
	_check(StoryText.op_line("baron", "pass", "spawn", 0) == "", "Baron has no table line in op 1 (generic BARON_LINES)")
	_check(StoryText.op_line("graf", "forts", "baron_down", 0).begins_with("«Барон» был лучшим"), "Graf's line on Baron down")
	_check(StoryText.op_line("draft", "forts", "spawn_after", 0).contains("ведущий"), "Draft after Baron: his wingman is bitter")
	_check(StoryText.result("forts", ["grom_free"]).contains("свободен"), "op 3 result line")
	_check(StoryText.radio("fortress.sight.forts") != "", "Kupol has a Fortress-sighting line in op 3")
	_check(StoryText.op_line("postman", "pass", "spawn", 0).begins_with("Доставка"), "Postman's first line in op 1")
	_check(StoryText.op_line("postman", "pass", "spawn", 1) != StoryText.op_line("postman", "pass", "spawn", 0), "Postman's second meeting: another line")
	_check(StoryText.op_line("draft", "pass", "run", 0) == "", "no draft.pass.run → generic line")
	for k in StoryText.RESULT:
		_check(String(StoryText.RESULT[k]).length() <= 110, "result line fits one row: " + k)
	_check(StoryText.result("pass").begins_with("Перевал"), "result line of op 1")
	_check(StoryText.result("pass", ["rescued"]) == StoryText.result("pass"), "no variant → base line")
	_check(StoryText.result("nope") == "", "unknown op → empty")
	_check(StoryText.radio("ground.pass") != "", "the «they build» line of op 1 exists")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
