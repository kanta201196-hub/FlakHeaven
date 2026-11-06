extends SceneTree
## Unit tests of DistText: world px shown to the player as metres / kilometres and km/h (Kanta 06.11: «we fly a
## plane and the marker says 100 m»). Runs from tools/ci/unit.sh.

var _failed := 0
var _checks := 0


func _initialize() -> void:
	TranslationServer.set_locale("ru")
	_test_scale()
	_test_text()
	_test_kmh()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## The scale is picked from the cruise speed: the fighter's 390 px/s must read as a jet's few hundred km/h.
func _test_scale() -> void:
	var fighter := DistText.kmh(390.0)
	_check(fighter >= 750 and fighter <= 950, "fighter 390 px/s → 750…950 km/h (got %d)" % fighter)
	var attacker := DistText.kmh(390.0 * 0.86)
	_check(attacker >= 650 and attacker <= 800, "attacker → 650…800 km/h (got %d)" % attacker)
	_check(is_equal_approx(DistText.metres(1000.0), 1000.0 * DistText.M_PER_PX), "metres = px × M_PER_PX")


## Under a kilometre: whole metres rounded to 10; from 1 km: kilometres with one decimal (Russian comma).
func _test_text() -> void:
	_check(DistText.text(0.0) == "0 м", "0 px → «0 м» (got %s)" % DistText.text(0.0))
	_check(DistText.text(500.0) == "300 м", "500 px → «300 м» (got %s)" % DistText.text(500.0))
	_check(DistText.text(508.0) == "300 м", "rounds to 10 m (got %s)" % DistText.text(508.0))
	_check(DistText.text(1660.0) == "1,0 км", "≈ 996 m rounds up to «1,0 км» (got %s)" % DistText.text(1660.0))
	_check(DistText.text(8900.0) == "5,3 км", "8900 px → «5,3 км» (got %s)" % DistText.text(8900.0))
	_check(DistText.text(-500.0) == "300 м", "negative distance is shown as its size")


func _test_kmh() -> void:
	_check(DistText.kmh(0.0) == 0, "0 px/s → 0 km/h")
	_check(DistText.kmh(100.0) == roundi(100.0 * DistText.M_PER_PX * 3.6), "km/h = px/s × M_PER_PX × 3.6")
