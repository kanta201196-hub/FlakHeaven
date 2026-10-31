extends SceneTree
## Unit tests for `AccentCurve` (in-combat story accents, plan step 4): the slow-motion starts at SLOW, eases back
## monotonically and ends at exactly 1.0. Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(is_equal_approx(AccentCurve.scale_at(AccentCurve.DUR), AccentCurve.SLOW), "start of the accent: SLOW")
	_check(is_equal_approx(AccentCurve.scale_at(0.0), 1.0), "end of the accent: normal speed")
	_check(is_equal_approx(AccentCurve.scale_at(-1.0), 1.0), "after the accent: normal speed")
	_check(is_equal_approx(AccentCurve.scale_at(AccentCurve.DUR * 2.0), AccentCurve.SLOW), "longer than DUR left: still SLOW")
	var mid := AccentCurve.scale_at(AccentCurve.DUR * 0.5)
	_check(mid > AccentCurve.SLOW and mid < 1.0, "halfway: between SLOW and 1")
	_check(mid < (AccentCurve.SLOW + 1.0) * 0.5, "quadratic return: the first half stays slow (ease-in)")
	var prev := 0.0
	var ok := true
	for i in 31:
		var v := AccentCurve.scale_at(AccentCurve.DUR * (1.0 - i / 30.0))
		if v < prev - 1e-6:
			ok = false
		prev = v
	_check(ok, "scale never goes back down while the accent plays out")
	_check(AccentCurve.SLOW > 0.0 and AccentCurve.SLOW < 1.0, "SLOW is a slow-down")
	_check(AccentCurve.DUR > 0.0 and AccentCurve.DUR <= 2.0, "accent is short (design: 1.5–2 s)")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
