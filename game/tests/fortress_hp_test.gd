extends SceneTree
## Unit tests for `AceBalance.fortress_hp`: GD-08 (Kanta 2026-10-25, option 1). The Fortress strength
## follows the player's damage with one landing share for every class (0.55), not the share measured
## in ace duels. Rules pinned here: the share is fixed; the formula floor still holds; Kanta's s11 «Оса»
## (605k with share 1.6) comes out at about 208k.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_fixed_share()
	_test_floor()
	_test_kanta_osa()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_fixed_share() -> void:
	_check(is_equal_approx(AceBalance.fortress_hp(0.0, 1000.0), 1000.0 * AceBalance.FORTRESS_SINGLE_K),
		"strength by damage uses the fixed share")


func _test_floor() -> void:
	_check(is_equal_approx(AceBalance.fortress_hp(5000.0, 100.0), 5000.0), "formula floor wins over a small damage term")


func _test_kanta_osa() -> void:
	# s11: 605,557 = per-share term × 1.6 (both before × 2 × 1.35, which the caller applies)
	var per_share := 605557.0 / 1.6
	var hp := AceBalance.fortress_hp(0.0, per_share)
	_check(hp > 200000.0 and hp < 215000.0, "Kanta's «Оса»: 605k → about 208k (got %.0f)" % hp)
