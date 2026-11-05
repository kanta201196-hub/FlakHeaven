extends SceneTree
## Unit tests for `EndlessBalance` («Долгий вылет», MO-01). Rules pinned here: nothing changes before 15:00 or while the
## long sortie is off; caps then grow without an upper bound; a death in the long sortie keeps everything earned by
## 15:00, so staying is never worse than evacuating at 15:00.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	var s := EndlessBalance.START
	_check(EndlessBalance.pressure_max(4.0, s - 1.0, true) == 4.0, "before 15:00: toughness cap unchanged")
	_check(EndlessBalance.pressure_max(4.0, s + 600.0, false) == 4.0, "long sortie off: cap unchanged")
	var p10 := EndlessBalance.pressure_max(4.0, s + 600.0, true)
	var p20 := EndlessBalance.pressure_max(4.0, s + 1200.0, true)
	_check(p10 > 4.0 and p20 > p10, "toughness cap keeps growing (10 min %.2f, 20 min %.2f)" % [p10, p20])
	_check(EndlessBalance.dens_max(1.8, s + 600.0, true) > 1.8, "density cap grows")
	_check(EndlessBalance.dens_max(1.8, s + 600.0, false) == 1.8, "density cap unchanged when off")
	_check(is_equal_approx(EndlessBalance.kept_on_death(300.0, 200.0), 250.0), "death keeps all parts earned by 15:00 and half of the rest")
	_check(EndlessBalance.kept_on_death(300.0, 200.0) >= 200.0, "never worse than evacuating at 15:00 (before the operation reward multiplier)")
	_check(is_equal_approx(EndlessBalance.kept_on_death(100.0, 500.0), 100.0), "snapshot above the total is clamped")
	_check(EndlessBalance.is_record(s + 90.0, 60.0) and not EndlessBalance.is_record(s + 30.0, 60.0), "record compares seconds past 15:00")
	_check(not EndlessBalance.is_record(s - 10.0, 0.0), "no record before 15:00")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
