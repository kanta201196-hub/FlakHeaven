extends SceneTree
## Unit test for `GroundTarget.site_floor_hp` (S16-05/06): site members hold longer than convoy vehicles at the same
## player damage, and the old base × growth value still wins when the player's damage is low.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0


func _init() -> void:
	# low damage: base x growth decides (bunker 270 x 1.68 = 453)
	_check(is_equal_approx(GroundTarget.site_floor_hp(GroundTarget.HP_FORT, 1.68, 10.0), 270.0 * 1.68), "low dps: base x growth")
	# high damage: 20 s of it for the bunker, 6 s for armor, 3 s for standard
	_check(is_equal_approx(GroundTarget.site_floor_hp(GroundTarget.HP_FORT, 1.0, 1000.0), 20000.0), "bunker 20 s of damage")
	_check(is_equal_approx(GroundTarget.site_floor_hp(GroundTarget.HP_ARMOR, 1.0, 1000.0), 6000.0), "armor 6 s of damage")
	_check(is_equal_approx(GroundTarget.site_floor_hp(GroundTarget.HP_STD, 1.0, 1000.0), 3000.0), "standard 3 s of damage")
	# the convoy keeps the old floor
	_check(is_equal_approx(GroundTarget.floor_hp(GroundTarget.HP_FORT, 1.0, 1000.0), 3000.0), "convoy floor unchanged")
	_check(AASite.LIMIT >= 150.0 and FortBalance.LIMIT >= 150.0, "site timers cover the 60-100 s goal")
	print("UNIT: site_hp_test %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
