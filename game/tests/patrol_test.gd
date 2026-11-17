extends SceneTree
## Unit tests of the «Кит» patrol columns (GD-18, Kanta 12.11: «надо менять количество наземки, а не урон бомб»):
## how often a column comes, how many may be on the map, what it carries, and when an untouched column the
## bomber flew past is dropped so the next one can come. Runs from tools/ci/unit.sh.

var _failed := 0
var _checks := 0


func _initialize() -> void:
	_test_numbers()
	_test_order()
	_test_gone()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Toggle off keeps the s18 rules (one column every 35 s); on — every 20 s, up to two at once.
func _test_numbers() -> void:
	_check(is_equal_approx(ActivityBalance.patrol_every(false), 35.0), "off: every 35 s")
	_check(is_equal_approx(ActivityBalance.patrol_every(true), 20.0), "on: every 20 s")
	_check(ActivityBalance.patrol_max(false) == 1, "off: one column at a time")
	_check(ActivityBalance.patrol_max(true) == 2, "on: two columns at a time")


## Off: pickup, truck, technical (3). On: five vehicles, two of them trucks (cargo), no armour or MANPADS.
func _test_order() -> void:
	var off := ActivityBalance.patrol_order(false)
	_check(off == ["technical", "truck", "light"], "off: the s18 column")
	var on := ActivityBalance.patrol_order(true)
	_check(on.size() == 5, "on: five vehicles")
	_check(on.count("truck") == 2, "on: two trucks")
	_check(not on.has("ifv") and not on.has("manpads"), "on: no armour, no MANPADS")


## A column is dropped only when the toggle is on, it was never alarmed, it has lived past the grace time,
## and every live vehicle is farther than the drop distance. An empty column (all dead) is not this case.
func _test_gone() -> void:
	var far := [3000.0, 3500.0]
	var t := ActivityBalance.PATROL_GRACE + 1.0
	_check(ActivityBalance.patrol_gone(true, false, t, far), "untouched, old, all far → dropped")
	_check(not ActivityBalance.patrol_gone(false, false, t, far), "toggle off → kept (s18)")
	_check(not ActivityBalance.patrol_gone(true, true, t, far), "alarmed → kept, it ends by its own timer")
	_check(not ActivityBalance.patrol_gone(true, false, ActivityBalance.PATROL_GRACE - 1.0, far), "young → kept")
	_check(not ActivityBalance.patrol_gone(true, false, t, [3000.0, 1200.0]), "one vehicle near → kept")
	_check(not ActivityBalance.patrol_gone(true, false, t, []), "no live vehicles → not this rule")
