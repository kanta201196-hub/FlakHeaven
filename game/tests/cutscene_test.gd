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
	_check(l1.size() == 4 and not bool(l1[3]) and String(l1[1]) == "Title" and is_equal_approx(float(l1[2]), 1.0), "title fully visible in the middle")
	var l2: Array = CutsceneKeys.line_at(sc, 4.1)
	_check(String(l2[0]) == "Купол" and float(l2[2]) < 0.5, "radio line fades in")
	_check(is_equal_approx(CutsceneKeys.fade_at(0.0, 10.0), 1.0), "black at the start")
	_check(is_equal_approx(CutsceneKeys.fade_at(5.0, 10.0), 0.0), "clear in the middle")
	_check(CutsceneKeys.fade_at(9.9, 10.0) > 0.7, "fading to black at the end")
	# the test scene is well-formed
	_check(float(StoryScenes.TEST["dur"]) >= 5.0 and (StoryScenes.TEST["cam"] as Array).size() >= 2, "test scene has a duration and two camera keys")
	for l in StoryScenes.TEST["lines"]:
		_check(float((l as Array)[1]) <= float(StoryScenes.TEST["dur"]), "every caption ends inside the scene")
	# every operation scene is well-formed: duration, ordered camera keys, captions inside the scene and ≤ 110 characters
	for table: Dictionary in [StoryScenes.INTRO, StoryScenes.OUTRO]:
		for op in table:
			var d: Dictionary = table[op]
			var dur := float(d.get("dur", 0.0))
			_check(dur >= 5.0 and dur <= 15.0, "scene %s: 5–15 s (rule: short, skippable)" % op)
			var cam: Array = d.get("cam", [])
			_check(cam.size() >= 2 and float(cam[0][0]) == 0.0 and float(cam[-1][0]) <= dur, "scene %s: camera keys start at 0 and end inside" % op)
			for l in d.get("lines", []):
				_check(float((l as Array)[0]) < float((l as Array)[1]) and float((l as Array)[1]) <= dur, "scene %s: caption inside the scene" % op)
				_check(String((l as Array)[3]).length() <= 110, "scene %s: caption fits the letterbox" % op)
			_check(String(d.get("light", "day")) in ["day", "dawn", "dusk", "night"], "scene %s: known light preset" % op)
	_check(not StoryScenes.intro("pass").is_empty() and not StoryScenes.outro("pass").is_empty(), "op 1 has an intro and an outro (step 5)")
	# op 3 (step 7): intro variant by the H2′ choice, Baron's caption as an enemy voice, night outro
	_check(not StoryScenes.intro("forts").is_empty() and not StoryScenes.outro("forts").is_empty(), "op 3 has an intro and an outro")
	_check(StoryScenes.intro("forts", "recon") != StoryScenes.intro("forts"), "recon lead picks the intro variant with the marker")
	_check(StoryScenes.intro("forts", "quiet") == StoryScenes.intro("forts"), "a choice without its own scene falls back to the plain intro")
	_check(StoryScenes.intro("forts", "") == StoryScenes.intro("forts"), "no choice → plain intro")
	var bl: Array = CutsceneKeys.line_at(StoryScenes.intro("forts"), 5.0)
	_check(bl.size() == 4 and bool(bl[3]) and String(bl[0]) == "Барон", "Baron's caption is flagged as an enemy voice")
	var kl: Array = CutsceneKeys.line_at(StoryScenes.intro("forts"), 8.0)
	_check(kl.size() == 4 and not bool(kl[3]), "Kupol's caption is not an enemy voice")
	_check(String(StoryScenes.outro("forts")["light"]) == "night", "op 3 outro is at night (green flare)")
	_check(StoryScenes.intro("no_such_op").is_empty(), "unknown operation → no scene")
	_check(StoryFlags.MODES.size() == 3, "setting names present for the menu row")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
