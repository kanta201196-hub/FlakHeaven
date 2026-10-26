extends SceneTree
## Unit tests for `AceBalance.flare_chance` (Kanta 2026-10-26, card «Ловушки асов слабее»): aces' flares pull away
## «Оса»'s missiles at FLARE_CHANCE_OSA; other classes keep each ace's normal chance.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(is_equal_approx(AceBalance.flare_chance(AceBalance.FLARE_CHANCE_BOSS, "fighter"), 0.5), "«Оса» vs wave ace: 0.5")
	_check(is_equal_approx(AceBalance.flare_chance(AceBalance.FLARE_CHANCE_RIVAL, "fighter"), 0.5), "«Оса» vs rival ace: 0.5")
	_check(is_equal_approx(AceBalance.flare_chance(AceBalance.FLARE_CHANCE_BOSS, "attacker"), 0.85), "«Грач» vs wave ace: unchanged")
	_check(is_equal_approx(AceBalance.flare_chance(AceBalance.FLARE_CHANCE_RIVAL, "bomber"), 0.8), "«Кит» vs rival ace: unchanged")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
