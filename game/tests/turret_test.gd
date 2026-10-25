extends SceneTree
## Unit tests for TurretMath (Kanta 25.10, Sublight-style machine-gun turrets): the damped turn must start and stop
## softly, never overshoot a still target, hold a moving one inside the firing gate, and a burst must keep the old
## damage per second whatever the reload. Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0
const DT := 1.0 / 60.0
const GATE := 0.09   # Hardpoint.TURRET_GATE (Hardpoint needs the autoloads, which a -s test does not have)


func _init() -> void:
	_test_soft_start()
	_test_no_overshoot()
	_test_holds_moving_target()
	_test_speed_cap()
	_test_burst()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## First frames speed up gradually instead of jumping to full traverse speed
func _test_soft_start() -> void:
	var wmax := deg_to_rad(150.0)
	var r := TurretMath.turn(0.0, 0.0, PI / 2.0, 0.0, wmax, DT)
	_check(r.y > 0.0 and r.y < wmax * 0.5, "first frame below half speed: %.3f" % r.y)
	for i in 20:
		r = TurretMath.turn(r.x, r.y, PI / 2.0, 0.0, wmax, DT)
	_check(is_equal_approx(r.y, wmax), "full speed after a third of a second: %.3f" % r.y)


## Turning 90° onto a still target: arrives, slows down before it, never swings past it
func _test_no_overshoot() -> void:
	var wmax := deg_to_rad(150.0)
	var cur := 0.0
	var w := 0.0
	var peak := 0.0
	for i in 120:
		var r := TurretMath.turn(cur, w, PI / 2.0, 0.0, wmax, DT)
		cur = r.x
		w = r.y
		peak = maxf(peak, cur)
	_check(absf(cur - PI / 2.0) < 0.01, "arrives within 0.01 rad: %.4f" % cur)
	_check(peak < PI / 2.0 + 0.02, "no overshoot: peak %.4f" % peak)
	_check(absf(w) < 0.05, "stops on the target: %.4f" % w)
	# arrival time stays close to the old linear turn (0.6 s for 90° at 150°/s)
	cur = 0.0
	w = 0.0
	var t := 0.0
	while absf(cur - PI / 2.0) > GATE and t < 3.0:
		var r2 := TurretMath.turn(cur, w, PI / 2.0, 0.0, wmax, DT)
		cur = r2.x
		w = r2.y
		t += DT
	_check(t < 0.75, "inside the firing gate within 0.75 s: %.2f" % t)


## A target crossing at 1 rad/s is held inside the firing gate (the feed-forward takes the target's own turn)
func _test_holds_moving_target() -> void:
	var wmax := deg_to_rad(150.0)
	var cur := 0.0
	var w := 0.0
	var tgt := 0.0
	var worst := 0.0
	for i in 180:
		tgt += 1.0 * DT
		var r := TurretMath.turn(cur, w, tgt, 1.0, wmax, DT)
		cur = r.x
		w = r.y
		if i > 60:
			worst = maxf(worst, absf(wrapf(tgt - cur, -PI, PI)))
	_check(worst < GATE * 0.5, "moving target held well inside the gate: %.4f" % worst)


## The servo cards keep their meaning: speed never goes above wmax, and a faster cap turns faster
func _test_speed_cap() -> void:
	var r := Vector2(0.0, 0.0)
	var top := 0.0
	for i in 60:
		r = TurretMath.turn(r.x, r.y, PI, 0.0, 2.0, DT)
		top = maxf(top, absf(r.y))
	_check(top <= 2.0 + 1e-4, "speed capped: %.4f" % top)
	_check(TurretMath.turn(0.0, 0.0, -1.0, 0.0, 2.0, DT).y < 0.0, "turns the short way to a negative angle")
	_check(TurretMath.turn(3.0, 0.0, -3.0, 0.0, 2.0, DT).y > 0.0, "turns the short way across ±PI")


## A burst splits the old round's damage evenly and always fits inside the reload, so damage per second is unchanged
func _test_burst() -> void:
	var n := TurretMath.BURST
	_check(n >= 3, "a burst has at least 3 rounds")
	_check(is_equal_approx(TurretMath.round_dmg(6.0) * n, 6.0), "rounds of a burst add up to the old round")
	_check(is_equal_approx(TurretMath.gap(0.3), TurretMath.GAP), "normal reload: Sublight-like gap")
	_check(TurretMath.gap(0.06) * n <= 0.06 + 1e-6, "very fast reload: the burst still ends before the next one")
