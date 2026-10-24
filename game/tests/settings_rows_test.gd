extends SceneTree
## Unit tests for `SettingsRows` (UI-01 step 2): scrolling of the settings list. Rules pinned
## here: the scroll never goes above the top or past the end of the content, a short list does
## not scroll, and moving focus scrolls just enough to show the focused row with a margin.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_clamp()
	_test_follow_focus()
	_test_step_value()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_clamp() -> void:
	_check(SettingsRows.clamp_scroll(-50.0, 800.0, 1200.0) == 0.0, "no scroll above the top")
	_check(SettingsRows.clamp_scroll(900.0, 800.0, 1200.0) == 400.0, "no scroll past the end")
	_check(SettingsRows.clamp_scroll(200.0, 800.0, 1200.0) == 200.0, "scroll inside the range kept")
	_check(SettingsRows.clamp_scroll(100.0, 800.0, 500.0) == 0.0, "short list never scrolls")


func _test_follow_focus() -> void:
	# view 800 px, content 2000 px, margin 40
	_check(SettingsRows.follow(0.0, 100.0, 146.0, 800.0, 2000.0, 40.0) == 0.0, "visible row keeps the scroll")
	_check(SettingsRows.follow(0.0, 900.0, 946.0, 800.0, 2000.0, 40.0) == 186.0, "row below the view scrolls down to bottom + margin")
	_check(SettingsRows.follow(500.0, 300.0, 346.0, 800.0, 2000.0, 40.0) == 260.0, "row above the view scrolls up to top − margin")
	_check(SettingsRows.follow(0.0, 1960.0, 2000.0, 800.0, 2000.0, 40.0) == 1200.0, "last row clamps to the end")
	_check(SettingsRows.follow(100.0, 10.0, 56.0, 800.0, 2000.0, 40.0) == 0.0, "first row clamps to the top")


func _test_step_value() -> void:
	_check(SettingsRows.step_value(0.5, 0.0, 1.0, 0.05, 1) == 0.55, "slider step up")
	_check(SettingsRows.step_value(0.0, 0.0, 1.0, 0.05, -1) == 0.0, "slider stays at the minimum")
	_check(SettingsRows.step_value(1.0, 0.0, 1.0, 0.05, 1) == 1.0, "slider stays at the maximum")
	_check(is_equal_approx(SettingsRows.step_value(-12.0, -30.0, 10.0, 1.0, -1), -13.0), "volume step down in dB")
