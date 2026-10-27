extends SceneTree
## Unit tests for `AceBalance.shield_after` (Kanta 2026-10-27, card «Щит не растёт в бою»). Rules pinned here: the
## shield never regrows while the ace is within SHIELD_CALM_R of the player, however long since the last hit; far
## away it regrows after SHIELD_WAIT s at SHIELD_REGEN per second and stops at full.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	var near := AceBalance.SHIELD_CALM_R - 1.0
	var far := AceBalance.SHIELD_CALM_R + 1.0
	_check(AceBalance.shield_after(10.0, 100.0, 30.0, near, 1.0) == 10.0, "near the player: no regrowth after 30 s without hits")
	_check(AceBalance.shield_after(10.0, 100.0, 2.0, far, 1.0) == 10.0, "far, but hit 2 s ago: no regrowth yet")
	_check(is_equal_approx(AceBalance.shield_after(10.0, 100.0, 5.0, far, 1.0), 25.0), "far and calm: +15 % of the shield per second")
	_check(AceBalance.shield_after(95.0, 100.0, 5.0, far, 1.0) == 100.0, "stops at full")
	_check(AceBalance.shield_after(10.0, 100.0, 5.0, INF, 1.0) > 10.0, "no player (dead): regrows")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
