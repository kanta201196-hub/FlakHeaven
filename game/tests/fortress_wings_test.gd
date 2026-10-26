extends SceneTree
## Unit tests for the «Крыло за крылом» phase order (Kanta 2026-10-26, decision card): phase 1 is the left wing
## (two domes and the left engine), phase 2 the right wing (two domes, the right engine and the bay), phase 3 the
## fall. Rules pinned here: which wing a point belongs to; a phase ends only when every point of its wing is down;
## the fall never goes back.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_wing_of()
	_test_phase_order()
	_test_targets()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_wing_of() -> void:
	_check(FortressBalance.wing_of(Vector2(-20, -92)) == 1, "left outer dome (y < 0) is wing 1")
	_check(FortressBalance.wing_of(Vector2(14, -21)) == 1, "left engine is wing 1")
	_check(FortressBalance.wing_of(Vector2(-4, 48)) == 2, "right inner dome is wing 2")
	_check(FortressBalance.wing_of(Vector2(14, 21)) == 2, "right engine is wing 2")


func _test_phase_order() -> void:
	_check(FortressBalance.next_phase(1, 1) == 1, "phase 1 holds while one left-wing point is up")
	_check(FortressBalance.next_phase(1, 0) == 2, "left wing down: phase 2")
	_check(FortressBalance.next_phase(2, 2) == 2, "phase 2 holds while right-wing points are up")
	_check(FortressBalance.next_phase(2, 0) == 3, "right wing down: the fall")
	_check(FortressBalance.next_phase(3, 0) == 3, "the fall stays")


func _test_targets() -> void:
	_check(FortressBalance.targets(1, 1) and not FortressBalance.targets(1, 2), "phase 1 takes damage on the left wing only")
	_check(FortressBalance.targets(2, 2) and not FortressBalance.targets(2, 1), "phase 2 takes damage on the right wing only")
	_check(not FortressBalance.targets(3, 1) and not FortressBalance.targets(3, 2), "phase 3 has no points, the hull is open")
