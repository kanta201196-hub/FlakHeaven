extends SceneTree
## Unit tests for `DpsWindow`: damage per second of each source over the last minute, shown
## in the pause screen («Урон за последнюю минуту»). Rules pinned here: damage older than the
## window drops out; in the first minute the rate divides by the time flown, not by 60;
## sources come out sorted by rate; a reset empties everything.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_single_source()
	_test_early_divides_by_elapsed()
	_test_old_damage_drops_out()
	_test_top_sorted()
	_test_reset()
	_test_time_going_back()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


func _test_single_source() -> void:
	var w := DpsWindow.new()
	for s in 120:
		w.add(&"aam", 30.0, 100.0 + s)   # 30 damage every second for two minutes
	_check(_near(w.rate(&"aam", 220.0), 30.0), "steady 30/s reads 30/s")
	_check(_near(w.rate(&"gun", 220.0), 0.0), "unknown source reads 0")


func _test_early_divides_by_elapsed() -> void:
	var w := DpsWindow.new()
	w.add(&"gun", 100.0, 0.5)
	w.add(&"gun", 100.0, 9.5)
	# 200 damage in the first 10 s of the sortie: 20/s, not 200/60
	_check(_near(w.rate(&"gun", 10.0), 20.0), "first minute divides by time flown")


func _test_old_damage_drops_out() -> void:
	var w := DpsWindow.new()
	w.add(&"bombs", 600.0, 10.0)
	_check(w.rate(&"bombs", 60.0) > 0.0, "damage 50 s ago still counts")
	_check(_near(w.rate(&"bombs", 75.0), 0.0), "damage 65 s ago is out of the window")
	w.add(&"bombs", 60.0, 130.0)
	_check(_near(w.rate(&"bombs", 130.5), 1.0), "a reused bucket does not keep old damage")


func _test_top_sorted() -> void:
	var w := DpsWindow.new()
	w.add(&"gun", 60.0, 70.0)
	w.add(&"aam", 600.0, 70.0)
	w.add(&"turret", 120.0, 70.0)
	var top := w.top(2, 80.0)
	_check(top.size() == 2, "top(2) gives two sources")
	_check(top[0][0] == &"aam" and top[1][0] == &"turret", "sorted by rate, highest first")
	_check(_near(float(top[0][1]), 10.0), "rate goes with the source")


func _test_reset() -> void:
	var w := DpsWindow.new()
	w.add(&"gun", 60.0, 5.0)
	w.reset()
	_check(w.top(5, 6.0).is_empty(), "reset forgets all sources")


func _test_time_going_back() -> void:
	# a new sortie restarts run time at 0 without reset: old buckets must not leak in
	var w := DpsWindow.new()
	w.add(&"gun", 600.0, 500.0)
	_check(_near(w.rate(&"gun", 3.0), 0.0), "damage from a later time does not count")
