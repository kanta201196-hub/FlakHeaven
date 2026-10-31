class_name WingFollow
extends RefCounted
## S14-08 (Kanta 31.10.2026: the wingman stops dead and flips round): smooth formation following, behind the F1
## toggle `wing_smooth` (R-22, off until Kanta's «ок»). The old follower blended its velocity straight towards
## "slot velocity", so when the slot swung behind it the velocity passed through zero and the nose snapped round.
## Here the wingman always flies nose-first like a plane: speed never drops below MIN_K of the leader's, it changes
## by at most ACC of the leader's speed per second, and the turn eases in and out (ROLL_ACC) within a turn radius.
## Overshot the slot: it slows down and lets the leader catch up; overshot far: it loops back on an arc.

const TURN := 160.0      # °/s, the same as Wingman.WING_TURN
const MIN_R := 110.0     # px, tightest turn radius (the turn rate never exceeds speed / MIN_R)
const ROLL_ACC := 420.0  # °/s², how fast the turn rate builds up and dies down
const TURN_GAIN := 3.0   # rad/s of turn per rad of heading error
const LOOK := 0.8        # s, the aim point is the slot plus this much of the leader's flight (plus the distance)
const MIN_K := 0.8       # × leader speed, slowest the wingman flies
const MAX_NEAR := 1.45   # × leader speed, fastest within FAR_R of the slot
const MAX_FAR := 1.8     # × leader speed, fastest further out
const FAR_R := 500.0
const SPD_GAIN := 300.0  # px of along-track gap per +100 % speed
const ACC := 0.8         # × leader speed per second, speed change limit
const NEAR_R := 60.0     # px, within this the wingman is also nudged straight onto the slot
const NUDGE := 1.5       # 1/s, strength of that nudge


## One frame of formation following. `st` holds heading, spd, turn_v (changed in place); `to` is the vector from the
## wingman to its slot, `pv` the leader's velocity. Returns the wingman's velocity for this frame.
static func follow(st: Dictionary, to: Vector2, pv: Vector2, delta: float) -> Vector2:
	var ps := maxf(pv.length(), 1.0)
	var fwd := pv / ps
	var dist := to.length()
	var aim := to + pv * (LOOK + clampf(dist / ps, 0.0, 1.2))
	var along := to.dot(fwd)
	var want_s := ps * clampf(1.0 + along / SPD_GAIN, MIN_K, MAX_NEAR if dist < FAR_R else MAX_FAR)
	steer(st, aim.angle(), want_s, ps, delta)
	var v := Vector2.from_angle(st.heading) * float(st.spd)
	return v + to * NUDGE * clampf(1.0 - dist / NEAR_R, 0.0, 1.0)


## Turn towards `want_h` and change speed towards `want_s` with eased turn rate and limited acceleration
## (`ps` scales the acceleration; `turn_k` widens the turn rate for attack runs).
static func steer(st: Dictionary, want_h: float, want_s: float, ps: float, delta: float, turn_k := 1.0) -> void:
	var spd := float(st.get("spd", 0.0))
	if spd <= 0.0:
		spd = want_s
	var max_w := minf(deg_to_rad(TURN * turn_k), spd / MIN_R)
	var diff := wrapf(want_h - float(st.heading), -PI, PI)
	var want_w := clampf(diff * TURN_GAIN, -max_w, max_w)
	var w := move_toward(float(st.get("turn_v", 0.0)), want_w, deg_to_rad(ROLL_ACC) * delta)
	st.turn_v = w
	st.heading = wrapf(float(st.heading) + w * delta, -PI, PI)
	st.spd = move_toward(spd, want_s, maxf(ps, 1.0) * ACC * delta)
