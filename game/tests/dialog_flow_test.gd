extends SceneTree
## Unit tests for `DialogFlow` and the `StoryDialogs` registry (Highlands story, plan step 3): branching by choices,
## the typewriter, option lookups, focus moves, portrait files, scene validation over every registered scene.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	var steps: Array = [
		{"who": "Купол", "text": "A"},
		{"choice": "q", "prompt": "?", "options": [["Да", "yes"], ["Нет", "no"]]},
		{"who": "Купол", "text": "B", "only": ["q", "yes"]},
		{"who": "crew", "text": "C", "only": ["q", "no"]},
		{"who": "crew", "text": "D"},
	]
	# next_step: plain lines and the choice always show, `only` lines follow the choice
	_check(DialogFlow.next_step(steps, 0, {}) == 0, "first step shows")
	_check(DialogFlow.next_step(steps, 1, {}) == 1, "the choice step shows")
	_check(DialogFlow.next_step(steps, 2, {}) == 4, "without a choice both branch lines are skipped")
	_check(DialogFlow.next_step(steps, 2, {"q": "yes"}) == 2, "yes → line B")
	_check(DialogFlow.next_step(steps, 2, {"q": "no"}) == 3, "no → line C")
	_check(DialogFlow.next_step(steps, 3, {"q": "yes"}) == 4, "yes past B → D")
	_check(DialogFlow.next_step(steps, 5, {}) == 5, "past the end → steps.size()")
	_check(DialogFlow.next_step(steps, -3, {}) == 0, "negative from is clamped")
	_check(DialogFlow.next_step([], 0, {}) == 0, "empty scene is over at once")
	# typewriter: SPEED characters per second
	_check(DialogFlow.shown("Привет, звено", 0.0) == "", "nothing at t = 0")
	_check(DialogFlow.shown("Привет, звено", 0.1) == "Прив", "4 characters after 0.1 s at 40 c/s")
	_check(DialogFlow.shown("Привет", 10.0) == "Привет", "long t → whole line")
	_check(not DialogFlow.typed("Привет", 0.1), "not typed yet")
	_check(DialogFlow.typed("Привет", 0.15), "typed at 6 characters")
	_check(DialogFlow.typed("", 0.0), "an empty line counts as typed")
	# options
	_check(DialogFlow.option_id(steps[1], 0) == "yes", "option 0 id")
	_check(DialogFlow.option_id(steps[1], 1) == "no", "option 1 id")
	_check(DialogFlow.option_id(steps[1], 2) == "", "option out of range → empty")
	_check(DialogFlow.option_id(steps[0], 0) == "", "a line has no options")
	_check(DialogFlow.option_label({"steps": steps}, "q", "no") == "Нет", "option label for the log")
	_check(DialogFlow.option_label({"steps": steps}, "q", "maybe") == "", "unknown option → empty label")
	_check(DialogFlow.option_label({"steps": steps}, "zz", "no") == "", "unknown choice → empty label")
	# focus
	_check(DialogFlow.move_focus(0, 1, 2) == 1, "focus down")
	_check(DialogFlow.move_focus(0, -1, 2) == 1, "focus wraps up")
	_check(DialogFlow.move_focus(1, 1, 2) == 0, "focus wraps down")
	_check(DialogFlow.move_focus(3, 1, 0) == 0, "no options → 0")
	# portraits
	_check(DialogFlow.portrait_file("Купол") == "res://art/portraits/story_kupol.png", "guest portrait path")
	_check(DialogFlow.portrait_file("crew") == "", "crew portrait comes from Profile")
	_check(DialogFlow.portrait_file("Барон") == "", "enemies have no portrait")
	# validate
	_check(DialogFlow.validate({"steps": steps}) == "", "sample scene is sound")
	_check(DialogFlow.validate({}) != "", "no steps → error")
	_check(DialogFlow.validate({"steps": [{"who": "Барон", "text": "x"}]}) != "", "unknown speaker → error")
	_check(DialogFlow.validate({"steps": [{"who": "crew"}]}) != "", "line without text → error")
	_check(DialogFlow.validate({"steps": [{"choice": "c", "prompt": "?", "options": [["a", "a"]]}]}) != "", "one option → error")
	_check(DialogFlow.validate({"steps": [{"choice": "c", "options": [["a", "a"], ["b", "b"]]}]}) != "", "choice without prompt → error")
	_check(DialogFlow.validate({"steps": [{"who": "crew", "text": "x", "only": ["c", "a"]}]}) != "", "only before its choice → error")
	_check(DialogFlow.validate({"steps": [{"who": "crew", "text": "x".repeat(221)}]}) != "", "overlong line → error")
	# registry
	_check(DialogFlow.validate(StoryDialogs.TEST) == "", "TEST scene is sound: " + DialogFlow.validate(StoryDialogs.TEST))
	var ids := {}
	for row: Array in StoryDialogs.ORDER:
		_check(row.size() == 3 and String(row[2]) in ["dlg", "cut"], "ORDER row has id, title, kind: " + String(row[0]))
		_check(not ids.has(String(row[0])), "ORDER ids are unique: " + String(row[0]))
		ids[String(row[0])] = true
	for id in StoryDialogs.SCENES:
		_check(ids.has(String(id)), "every scene is listed in ORDER: " + String(id))
		_check(StoryDialogs.title(String(id)) != "", "every scene has a log title: " + String(id))
		_check(DialogFlow.validate(StoryDialogs.scene(String(id))) == "", "scene is sound: %s (%s)" % [String(id), DialogFlow.validate(StoryDialogs.scene(String(id)))])
	_check(StoryDialogs.scene("no_such_scene").is_empty(), "unknown scene → empty")
	_check(StoryDialogs.title("hangar_prologue") != "", "prologue has a title")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
