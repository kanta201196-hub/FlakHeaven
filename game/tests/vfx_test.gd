extends SceneTree
## Unit tests for the pure helpers of the GPU effects (VFX-01): explosion kind by size,
## the particle quality factor and the alive-particle estimate. No framework: each check prints
## FAIL with a message; the process exits with code 1 if any check failed.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_kind_for()
	_test_quality()
	_test_counter()
	_test_counter_horizon()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Same rules Boom3D used inline: ground below, flak under 18, big from 50, air otherwise; a given kind wins
func _test_kind_for() -> void:
	_check(FxMath.kind_for(30.0, false) == "ground", "not air → ground")
	_check(FxMath.kind_for(12.0, true) == "flak", "small air → flak")
	_check(FxMath.kind_for(18.0, true) == "air", "18 is air, not flak")
	_check(FxMath.kind_for(50.0, true) == "big", "50 is big")
	_check(FxMath.kind_for(49.0, true) == "air", "49 is air")
	_check(FxMath.kind_for(10.0, true, "blast") == "blast", "explicit kind wins")


## Preset factor × crowding factor: full count keeps the preset, a crowded scene drops to 30 %
func _test_quality() -> void:
	_check(is_equal_approx(FxMath.quality(2, 0), 1.0), "high preset, empty scene = 1.0")
	_check(is_equal_approx(FxMath.quality(0, 0), 0.45), "low preset = 0.45")
	_check(is_equal_approx(FxMath.quality(3, 0), 1.25), "ultra preset = 1.25")
	_check(is_equal_approx(FxMath.quality(2, 5000), 0.3), "crowded scene floors at 0.3 of the preset")
	_check(FxMath.quality(2, 900) < 1.0 and FxMath.quality(2, 900) > 0.3, "half-crowded scene in between")
	_check(is_equal_approx(FxMath.quality(9, 0), 1.25), "preset index is clamped")


## GPU particles cannot be counted from the CPU: the counter estimates them from emit times and lifetimes
func _test_counter() -> void:
	var c := FxCounter.new()
	c.add(0.0, 1.0, 3)
	c.add(0.0, 3.0, 2)
	_check(c.alive(0.5) == 5, "all alive at 0.5 s (got %d)" % c.alive(0.5))
	_check(c.alive(1.2) == 2, "short ones gone at 1.2 s (got %d)" % c.alive(1.2))
	c.add(1.2, 0.5)
	_check(c.alive(1.3) == 3, "new one counted (got %d)" % c.alive(1.3))
	_check(c.alive(3.2) == 0, "all gone at 3.2 s (got %d)" % c.alive(3.2))


## Lifetimes past the horizon still expire (clamped), and a long pause does not leave stale counts
func _test_counter_horizon() -> void:
	var c := FxCounter.new()
	c.add(0.0, 100.0)
	_check(c.alive(1.0) == 1, "long-lived counted")
	_check(c.alive(FxCounter.HORIZON + 1.0) == 0, "long-lived expires by the horizon")
	c.add(50.0, 1.0)
	_check(c.alive(500.0) == 0, "long pause clears everything")
