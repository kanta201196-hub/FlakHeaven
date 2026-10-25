extends SceneTree
## Unit tests for the menu flight route (`TitleRoute`, S11-01): the camera follows the
## moving average of the traced river line. Rules pinned here: on a straight river the average lies
## on the river; the average slides smoothly as s grows even when the river zigzags hard (a window
## of whole samples jumped up to 40 px per sample and drew zigzag contrails); before the window
## reaches the route the point is its first sample; far from the world origin the average keeps
## sub-pixel precision.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_straight_line()
	_test_smooth_on_zigzag()
	_test_start_is_river()
	_test_far_from_origin()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


var _r := TitleRoute.new(40.0, 1200.0)


## Puts pts into the route as if TitleFlight had traced them
func _load(pts: Array) -> void:
	_r.clear()
	for p: Vector2 in pts:
		_r.add(p)


func _test_straight_line() -> void:
	var pts := []
	for i in 400:
		pts.append(Vector2(0.0, -_r.step * i))
	_load(pts)
	var c := _r.point(6000.0)
	_check(absf(c.x) < 0.01, "straight river: the average stays on the river line (x = %.3f)" % c.x)
	_check(absf(c.y + 6000.0) < _r.step, "straight river: the average is near s (y = %.1f)" % c.y)


func _test_smooth_on_zigzag() -> void:
	var pts := []
	for i in 400:
		pts.append(Vector2(1200.0 if i % 2 == 0 else -1200.0, -_r.step * i))
	_load(pts)
	var worst := 0.0
	var prev := _r.point(2000.0)
	for k in range(1, 4000):
		var c := _r.point(2000.0 + k)
		worst = maxf(worst, c.distance_to(prev))
		prev = c
	_check(worst < 3.0, "zigzag river: 1 px of s moves the average by %.2f px (< 3)" % worst)


func _test_start_is_river() -> void:
	var pts := []
	for i in 400:
		pts.append(Vector2(500.0 + i, 300.0 - _r.step * i))
	_load(pts)
	var c := _r.point(-_r.win - 10.0)
	_check(c.distance_to(pts[0]) < 0.01, "before the window reaches the route the point is its first sample")


func _test_far_from_origin() -> void:
	var pts := []
	for i in 8000:
		pts.append(Vector2(200000.0 + 25.0 * sin(i * 1.7), 150000.0 - _r.step * i))
	_load(pts)
	var worst := 0.0
	var prev := _r.point(300000.0)
	for k in range(1, 400):
		var c := _r.point(300000.0 + k)
		worst = maxf(worst, absf(c.x - prev.x))
		prev = c
	_check(worst < 0.2, "8000 samples 200 km out: sideways wobble per px of s %.3f px (< 0.2)" % worst)
