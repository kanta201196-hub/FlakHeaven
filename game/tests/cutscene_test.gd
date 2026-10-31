extends SceneTree
## Unit tests for `CutsceneKeys` (the pure maths of `Cutscene`, plan step 2): camera keys, captions and fades, and the test
## scene definition. Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	var sc := {"dur": 10.0, "cam": [[0.0, Vector2(0, 100), 0.5], [10.0, Vector2(0, -100), 1.0]],
		"lines": [[1.0, 3.0, "", "Title"], [4.0, 6.0, "Купол", "Line"]]}
	var c0: Array = CutsceneKeys.cam_at(sc, 0.0)
	_check((c0[0] as Vector2) == Vector2(0, 100) and float(c0[1]) == 0.5, "camera at the first key")
	var c1: Array = CutsceneKeys.cam_at(sc, 10.0)
	_check((c1[0] as Vector2) == Vector2(0, -100) and float(c1[1]) == 1.0, "camera at the last key")
	var c2: Array = CutsceneKeys.cam_at(sc, 99.0)
	_check((c2[0] as Vector2) == Vector2(0, -100), "camera stays at the last key after the end")
	var cm: Array = CutsceneKeys.cam_at(sc, 5.0)
	_check(is_equal_approx((cm[0] as Vector2).y, 0.0) and is_equal_approx(float(cm[1]), 0.75), "midway: half the move, half the zoom")
	_check((CutsceneKeys.cam_at({}, 3.0)[0] as Vector2) == Vector2.ZERO, "no keys: zero offset")
	_check(CutsceneKeys.line_at(sc, 0.5).is_empty(), "no caption before the first line")
	var l1: Array = CutsceneKeys.line_at(sc, 2.0)
	_check(l1.size() == 3 and String(l1[1]) == "Title" and is_equal_approx(float(l1[2]), 1.0), "title fully visible in the middle")
	var l2: Array = CutsceneKeys.line_at(sc, 4.1)
	_check(String(l2[0]) == "Купол" and float(l2[2]) < 0.5, "radio line fades in")
	_check(is_equal_approx(CutsceneKeys.fade_at(0.0, 10.0), 1.0), "black at the start")
	_check(is_equal_approx(CutsceneKeys.fade_at(5.0, 10.0), 0.0), "clear in the middle")
	_check(CutsceneKeys.fade_at(9.9, 10.0) > 0.7, "fading to black at the end")
	# the test scene is well-formed
	_check(float(StoryScenes.TEST["dur"]) >= 5.0 and (StoryScenes.TEST["cam"] as Array).size() >= 2, "test scene has a duration and two camera keys")
	for l in StoryScenes.TEST["lines"]:
		_check(float((l as Array)[1]) <= float(StoryScenes.TEST["dur"]), "every caption ends inside the scene")
	_check(StoryScenes.intro("pass").is_empty() and StoryScenes.outro("pass").is_empty(), "no operation scenes yet (steps 5–8)")
	_check(StoryFlags.MODES.size() == 3, "setting names present for the menu row")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
