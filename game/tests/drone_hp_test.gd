extends SceneTree
## Unit tests for `DroneBalance.hp` (Kanta 2026-10-27, s13 item 11: drones die from a couple of hits). Rules pinned
## here: two base course-gun bullets kill a drone and one does not; a tail hit (×1.5) kills it at once; the floor holds.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	for gun in [7.5, 11.0, 15.0, 40.0]:
		var hp := DroneBalance.hp(gun)
		_check(gun < hp and gun * 2.0 >= hp, "gun %.1f: dies from 2 hits, not 1 (hp %.1f)" % [gun, hp])
		_check(gun * 1.5 >= hp, "gun %.1f: one tail hit kills" % gun)
	_check(is_equal_approx(DroneBalance.hp(1.0), DroneBalance.HP_MIN), "floor")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
