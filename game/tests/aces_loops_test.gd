extends SceneTree
## Unit tests for the «Битва асов» loops of «Оса» (Kanta 2026-11-10, AB-09): E is a half loop with a half roll
## (Immelmann-style) instead of the snap combat turn, V is a full loop instead of the dive.
## Rules pinned here: the half loop ends on the reverse course (or on the enemy behind, within the lock cone)
## and over its starting point; the full loop keeps the course and ends where it began (pursuers overshoot);
## bullets pass under only in the middle of the manoeuvre; the pose is continuous (no visible jump at the top).
## Run from the repository root: `tools/ci/unit.sh`.

const STEPS := 600

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_exit_heading()
	_test_ground_track()
	_test_guard()
	_test_pose()
	_test_numbers()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: " + what)


func _near_angle(a: float, b: float, eps := 0.001) -> bool:
	return absf(wrapf(a - b, -PI, PI)) < eps


func _test_exit_heading() -> void:
	var h := 0.3
	_check(_near_angle(AcesBalance.half_loop_exit(h, 0.0, false), h + PI), "no target: half loop exits on the reverse course")
	var t := h + PI + deg_to_rad(40.0)
	_check(_near_angle(AcesBalance.half_loop_exit(h, t, true), t), "enemy 40° off the reverse course: exit nose on it")
	var far := h + PI + deg_to_rad(90.0)
	_check(_near_angle(AcesBalance.half_loop_exit(h, far, true), h + PI), "enemy 90° off: plain reverse course")
	_check(_near_angle(AcesBalance.half_loop_exit(h, h, true), h + PI), "enemy ahead: plain reverse course")


## Ground displacement along the entry course, in units of speed × duration
func _track(half: bool) -> Array:
	var x := 0.0
	var top := 0.0
	for i in STEPS:
		var f := (float(i) + 0.5) / STEPS
		x += AcesBalance.loop_ground_k(f, half) / STEPS
		top = maxf(top, x)
	return [x, top]


func _test_ground_track() -> void:
	var full: Array = _track(false)
	_check(absf(full[0]) < 0.01, "full loop ends where it began (%.3f)" % full[0])
	_check(full[1] > 0.1 and full[1] < 0.25, "full loop goes a little ahead first (%.3f)" % full[1])
	var half: Array = _track(true)
	_check(absf(half[0]) < 0.01, "half loop ends over its starting point (%.3f)" % half[0])
	_check(is_equal_approx(AcesBalance.loop_ground_k(0.0, true), 1.0), "half loop starts flying forward")
	_check(is_equal_approx(AcesBalance.loop_ground_k(1.0, true), -1.0), "half loop ends flying back along the entry course")
	_check(is_equal_approx(AcesBalance.loop_ground_k(1.0, false), 1.0), "full loop ends flying forward")


func _test_guard() -> void:
	var g := AcesBalance.LOOP_GUARD
	_check(not AcesBalance.loop_guard(0.02, g), "entry: bullets still hit")
	_check(AcesBalance.loop_guard(0.5, g), "top of the loop: bullets pass under")
	_check(not AcesBalance.loop_guard(0.98, g), "exit: bullets hit again")
	_check(not AcesBalance.loop_guard(0.5, 0.0), "guard 0: never protected")
	_check(AcesBalance.loop_guard(0.01, 1.0), "guard 1: whole manoeuvre")


func _test_pose() -> void:
	# pose = Vector4(yaw offset from the current heading, pitch, roll, height 0..1)
	for half in [true, false]:
		var prev: Vector4 = AcesBalance.loop_pose(0.0, half)
		_check(prev.is_equal_approx(Vector4.ZERO), "pose starts level (half=%s)" % half)
		var jump := 0.0
		for i in range(1, STEPS + 1):
			var f := float(i) / STEPS
			var p: Vector4 = AcesBalance.loop_pose(f, half)
			jump = maxf(jump, _pose_dist(prev, p, half, f))
			prev = p
		_check(jump < 0.1, "pose has no visible jump (half=%s, %.3f)" % [half, jump])
		var end: Vector4 = AcesBalance.loop_pose(1.0, half)
		_check(absf(wrapf(end.y, -PI, PI)) < 0.01 and absf(wrapf(end.z, -PI, PI)) < 0.01 and end.w < 0.01,
			"pose ends level and low (half=%s)" % half)
	_check(AcesBalance.loop_pose(0.5, false).w > 0.99, "full loop is highest in the middle")


## Distance between two poses as the model's nose and wing directions (so equal orientations given by different
## angles, like the heading flip at the vertical, count as equal)
func _pose_dist(a: Vector4, b: Vector4, half: bool, f: float) -> float:
	# the heading itself flips at the vertical of the half loop: add it back as yaw
	var ya := a.x + (PI if half and f - 1.0 / STEPS >= 0.5 else 0.0)
	var yb := b.x + (PI if half and f >= 0.5 else 0.0)
	var ba := Basis(Vector3.UP, -ya) * Basis(Vector3.BACK, a.y) * Basis(Vector3.RIGHT, a.z)
	var bb := Basis(Vector3.UP, -yb) * Basis(Vector3.BACK, b.y) * Basis(Vector3.RIGHT, b.z)
	return maxf((ba.x - bb.x).length(), (ba.z - bb.z).length()) + absf(a.w - b.w)


func _test_numbers() -> void:
	_check(AcesBalance.HALF_LOOP_TIME > 0.5 and AcesBalance.HALF_LOOP_TIME < AcesBalance.LOOP_TIME, "half loop is quicker than the full loop")
	_check(AcesBalance.LOOP_CD > AcesBalance.LOOP_TIME + 1.0, "full loop cannot be chained")
	_check(AcesBalance.HALF_EXIT > 0.3 and AcesBalance.HALF_EXIT <= 1.0, "half loop costs some speed")
	_check(AcesBalance.LOOP_EXIT > 0.3 and AcesBalance.LOOP_EXIT <= 1.0, "full loop costs some speed")
