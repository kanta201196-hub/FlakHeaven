extends SceneTree
## Unit tests for `MobileRules` (Android draft): on PC nothing is capped and the render scale is
## untouched; on a phone every preset is held under the phone maximum, and the 3D render height
## follows LINES_AT_FULL instead of the panel's own resolution.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	MobileRules.on = false
	_test_pc_untouched()
	MobileRules.on = true
	_test_phone_caps()
	_test_phone_scale()
	MobileRules.on = false
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_pc_untouched() -> void:
	var top := GfxPresets.preset(GfxPresets.PRESETS.size() - 1)
	for id: String in GfxPresets.IDS:
		_check(MobileRules.cap(id, int(top[id])) == int(top[id]), "PC keeps %s of the top preset" % id)
	_check(is_equal_approx(MobileRules.scale_k(2160.0), 1.0), "PC render scale untouched")


func _test_phone_caps() -> void:
	for i in GfxPresets.PRESETS.size():
		var opts := GfxPresets.preset(i)
		for id: String in MobileRules.MAX:
			_check(MobileRules.cap(id, int(opts[id])) <= int(MobileRules.MAX[id]), "phone caps %s in preset %d" % [id, i])
	# a value already under the cap is kept, and options without a cap pass through
	_check(MobileRules.cap("terrain", 0) == 0, "phone keeps a value under the cap")
	_check(MobileRules.cap("scale", 5) == 5, "render scale option is not capped (scale_k does it)")


func _test_phone_scale() -> void:
	_check(is_equal_approx(MobileRules.scale_k(1800.0), 0.5), "1800-line tablet draws 3D at half height")
	_check(is_equal_approx(MobileRules.scale_k(720.0), 1.0), "small screen is not upscaled")
	_check(MobileRules.scale_k(10000.0) >= 0.3, "scale never drops below 30 %")
	_check(is_equal_approx(MobileRules.scale_k(0.0), 1.0), "unknown screen size leaves the scale alone")
