extends SceneTree
## Unit tests for `MouseView` (S16-28): the system arrow is hidden in flight and cutscenes, shows on menu screens,
## and in a dialogue scene shows only while the mouse has moved recently.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(MouseView.hidden("playing", 0.0), "hidden in flight even while the mouse moves (it steers)")
	_check(MouseView.hidden("cutscene", 0.0), "hidden in a cutscene even while the mouse moves")
	_check(not MouseView.hidden("menu", 100.0), "shown in the main menu")
	_check(not MouseView.hidden("hangar", 100.0), "shown in the hangar")
	_check(not MouseView.hidden("levelup", 100.0), "shown on the card pick")
	_check(not MouseView.hidden("paused", 100.0), "shown on pause")
	_check(not MouseView.hidden("dialog", 0.0), "dialogue: shown right after the mouse moved")
	_check(not MouseView.hidden("dialog", MouseView.IDLE_HIDE - 0.01), "dialogue: still shown just before the idle limit")
	_check(MouseView.hidden("dialog", MouseView.IDLE_HIDE), "dialogue: hidden once the mouse rests")
	_check(MouseView.mode(true) == Input.MOUSE_MODE_HIDDEN, "hidden maps to MOUSE_MODE_HIDDEN (clicks still arrive)")
	_check(MouseView.mode(false) == Input.MOUSE_MODE_VISIBLE, "shown maps to MOUSE_MODE_VISIBLE")
	print("UNIT: mouse_view %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
