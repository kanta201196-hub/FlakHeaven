extends SceneTree
## Unit tests for `WingFollow` (S14-08, smooth wingman). Rules pinned here: the wingman never drops below MIN_K of
## the leader's speed and never flies backwards when it overshoots; its turn rate and turn-rate change stay within
## TURN and ROLL_ACC; it settles onto its slot on straight flight and after the leader's U-turn.
## Run from the repository root: `tools/ci/unit.sh`.

const DT := 1.0 / 60.0
const PS := 390.0
const SLOT := Vector2(-20.0, 90.0)

var _failed := 0
var _checks := 0


func _init() -> void:
	_straight(Vector2(-300.0, 0.0), "starts 300 px behind")
	_straight(Vector2(250.0, 0.0), "starts 250 px ahead (overshoot)")
	_straight(Vector2(0.0, 120.0), "starts 120 px off to the side")
	_u_turn()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


## Leader flies straight along +x; the wingman starts at the slot plus `start`, nose along the leader's course.
func _straight(start: Vector2, what: String) -> void:
	var lp := Vector2.ZERO
	var pv := Vector2(PS, 0.0)
	var wp := SLOT + start
	var st := {"heading": 0.0, "spd": PS, "turn_v": 0.0}
	var r := _fly(lp, pv, wp, st, 0.0, 0.0, 10.0)
	_check(r.min_k >= WingFollow.MIN_K - 0.01, "%s: speed never below MIN_K (min %.2f)" % [what, r.min_k])
	_check(r.min_fwd > 0.0, "%s: never flies backwards (min forward %.0f)" % [what, r.min_fwd])
	_check(r.max_w <= deg_to_rad(WingFollow.TURN) + 0.001, "%s: turn rate within TURN" % what)
	_check(r.max_dw <= deg_to_rad(WingFollow.ROLL_ACC) * DT + 0.0001, "%s: turn eases in and out" % what)
	_check(r.end_d < 15.0, "%s: on the slot after 10 s (%.1f px off)" % [what, r.end_d])


## Leader turns 180° at 210 °/s; the formation frame follows at 75 °/s, as in Wingman.FORM_TURN.
func _u_turn() -> void:
	var st := {"heading": 0.0, "spd": PS, "turn_v": 0.0}
	var r := _fly(Vector2.ZERO, Vector2(PS, 0.0), SLOT, st, deg_to_rad(210.0), PI, 12.0)
	_check(r.min_k >= WingFollow.MIN_K - 0.01, "U-turn: speed never below MIN_K (min %.2f)" % r.min_k)
	_check(r.max_dw <= deg_to_rad(WingFollow.ROLL_ACC) * DT + 0.0001, "U-turn: turn eases in and out")
	_check(r.end_d < 20.0, "U-turn: back on the slot after 12 s (%.1f px off)" % r.end_d)


func _fly(lp: Vector2, pv: Vector2, wp: Vector2, st: Dictionary, lead_w: float, lead_turn: float, secs: float) -> Dictionary:
	var lh := 0.0
	var fh := 0.0
	var turned := 0.0
	var out := {"min_k": INF, "min_fwd": INF, "max_w": 0.0, "max_dw": 0.0, "end_d": 0.0}
	var prev_w := 0.0
	for i in int(secs / DT):
		if turned < lead_turn:
			var s := minf(lead_w * DT, lead_turn - turned)
			lh += s
			turned += s
		fh = rotate_toward(fh, lh, deg_to_rad(75.0) * DT)
		pv = Vector2.from_angle(lh) * PS
		lp += pv * DT
		var slot := lp + SLOT.rotated(fh)
		var v := WingFollow.follow(st, slot - wp, pv, DT)
		wp += v * DT
		out.min_k = minf(out.min_k, float(st.spd) / PS)
		out.min_fwd = minf(out.min_fwd, v.dot(pv / PS))
		out.max_w = maxf(out.max_w, absf(float(st.turn_v)))
		out.max_dw = maxf(out.max_dw, absf(float(st.turn_v) - prev_w))
		prev_w = float(st.turn_v)
		out.end_d = wp.distance_to(slot)
	return out


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
