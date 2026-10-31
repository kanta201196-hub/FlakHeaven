extends SceneTree
## Unit tests of where ground-site activities may appear (ActivityBalance, S14-04, Kanta 31.10: never in view,
## at least two screens from the player) and of FortArea.pick_fort's distance rule. Runs from tools/ci/unit.sh.

var _failed := 0
var _checks := 0


func _initialize() -> void:
	_test_min_dist()
	_test_far_ok()
	_test_wants()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Two screens of the longer side: 1920×1080 → 3840 px; a zoomed-out camera (bigger rect) pushes sites farther.
func _test_min_dist() -> void:
	_check(is_equal_approx(ActivityBalance.min_dist(Rect2(0, 0, 1920, 1080)), 3840.0), "1920×1080 screen → 3840 px")
	_check(is_equal_approx(ActivityBalance.min_dist(Rect2(0, 0, 1080, 1920)), 3840.0), "longer side counts")
	_check(ActivityBalance.min_dist(Rect2(0, 0, 2880, 1620)) > 3840.0, "zoomed out → farther")


## Every point of the site counts, not only the centre; the view rect rejects even a far point inside it.
func _test_far_ok() -> void:
	var from := Vector2.ZERO
	var site := PackedVector2Array([Vector2(4000, 0), Vector2(4300, 200), Vector2(3900, -200)])
	_check(ActivityBalance.far_ok(site, from, 3840.0), "whole site beyond 3840 px")
	site.append(Vector2(3500, 0))   # one vehicle closer than two screens
	_check(not ActivityBalance.far_ok(site, from, 3840.0), "one point too close fails the site")
	_check(is_equal_approx(ActivityBalance.near_dist(site, from), 3500.0), "nearest point distance")
	var far := PackedVector2Array([Vector2(5000, 0)])
	_check(ActivityBalance.far_ok(far, from, 3840.0, Rect2()), "no view rect — not checked")
	_check(not ActivityBalance.far_ok(far, from, 3840.0, Rect2(-1000, -3000, 7000, 6000)), "inside the view rect fails")
	_check(ActivityBalance.far_ok(far, from, 3840.0, Rect2(-1000, -600, 2000, 1200)), "outside the view rect passes")


## Tries start straight ahead past the minimum distance, turn both ways, never come closer than the minimum.
func _test_wants() -> void:
	var w := ActivityBalance.wants(Vector2(100, 100), 0.0, 3840.0)
	_check(w.size() == ActivityBalance.TRIES, "TRIES centres")
	_check(w[0].is_equal_approx(Vector2(100 + 3840 + ActivityBalance.EXTRA, 100)), "first straight ahead")
	_check(w[1].y > 100.0 and w[2].y < 100.0, "then turned both ways")
	var ok := true
	for q in w:
		ok = ok and q.distance_to(Vector2(100, 100)) >= 3840.0 + ActivityBalance.EXTRA - 0.01
	_check(ok, "no centre closer than min + EXTRA")
	var last := ActivityBalance.wants(Vector2.ZERO, 0.0, 3840.0)[ActivityBalance.TRIES - 1]
	_check(last.length() > 3840.0 + ActivityBalance.EXTRA * 1.5, "second ring is farther")
