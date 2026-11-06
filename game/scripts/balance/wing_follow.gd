class_name WingFollow
extends RefCounted
## S14-08 (Kanta 31.10.2026: the wingman stops dead and flips round): smooth formation following, behind the F1
## toggle `wing_smooth` (R-22, on since Kanta's «ок» 31.10). The old follower blended its velocity straight towards
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
## S16-24 (Kanta: the wingman «nose-pokes» into the leader again): within AVOID_R × clear radius the nose line may
## not cross the leader's keep-out disc (clear radius × AVOID_DISC); the wanted heading is pushed to the edge of the
## disc, nor may a straight flight of AVOID_T s bring it into the disc; the turn may be quicker (AVOID_TURN). Toggle
## `wing_avoid`.
const AVOID_R := 2.0
const AVOID_DISC := 1.0
const AVOID_T := 0.3     # s, how far ahead a heading is checked against the leader's flight
const AVOID_FAR := 8.0   # × clear radius, beyond this the leader is not checked at all
const AVOID_STEP := 0.087  # rad (5°), heading search step
const AVOID_SAMPLES := 8
const CROSS_BACK := 2.7  # × clear radius behind the leader, where a wingman on the wrong side crosses over
const CROSS_LAT := 0.3   # wrong side counts once lateral offsets (wingman × slot) are below −clear² × this
const NOSE_R := 2.6      # × clear radius, the nose is held off the leader closer than this
const NOSE_FADE := 0.5   # × clear radius over which that hold fades in
const LEAD_W_MAX := 0.0  # rad/s, cap of the leader turn rate the prediction uses (the combat turn is ~9)
const AVOID_TURN := 1.5  # × TURN and × ROLL_ACC while dodging
const DETOUR := 1.7      # × clear radius, how wide the path to the slot goes round the leader (as Wingman did)


## One frame of formation flight around the leader, pure so the unit test flies the same path as the game:
## the path to the slot goes round the leader, then `follow`, then the wingman is eased out of the leader's
## clear radius. `pos`/`slot`/`lp` are world positions of the wingman, its slot and the leader, `clear` is
## Wingman.clear_r, `side` −1/+1 the slot's side. `avoid` turns on the S16-24 nose rule. Returns the new
## position; the velocity is left in `st.vel`.
static func step(st: Dictionary, pos: Vector2, slot: Vector2, lp: Vector2, pv: Vector2, clear: float, side: float,
		delta: float, avoid := false) -> Vector2:
	var target := slot
	var speed_to := slot - pos
	if avoid:
		# S16-24: on the wrong side of the leader the wingman crosses over behind its tail (out of the nose range)
		# instead of sitting wing to wing on the wrong side, unable to pass the leader
		var fwd := pv.normalized() if pv.length() > 1.0 else Vector2.RIGHT
		var perp := fwd.orthogonal()
		var lat_s := (slot - lp).dot(perp)
		if (pos - lp).dot(perp) * lat_s < -clear * clear * CROSS_LAT:
			target = lp - fwd * clear * CROSS_BACK + perp * signf(lat_s) * clear * 0.5
			speed_to = target - pos
	var seg := target - pos
	var t_c := clampf((lp - pos).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
	var near := pos + seg * t_c
	var gap := clear * DETOUR
	var nd := near.distance_to(lp)
	if nd < gap and t_c > 0.05 and t_c < 0.95:
		var out := (near - lp) / nd if nd > 1.0 else Vector2.from_angle(pv.angle() + side * PI / 2.0)
		target += out * (gap - nd) * 1.5
	# S16-24: the speed comes from the real slot; from the detour point it stalled level with the leader behind it
	var v := follow(st, target - pos, pv, delta, lp - pos if avoid else Vector2.ZERO, clear if avoid else 0.0,
		speed_to if avoid else target - pos)
	if avoid:
		v = nose_clear(st, lp - pos, clear)
	pos += v * delta
	var rel := pos - lp
	var l := rel.length()
	if l < clear:
		var away := rel / l if l > 1.0 else Vector2.from_angle(pv.angle() + side * PI / 2.0)
		pos += away * (clear - l) * (1.0 if avoid else minf(1.0, delta * 10.0))   # S16-24: no overlap at all
		v -= away * minf(0.0, v.dot(away) - pv.dot(away))
	st.vel = v
	return pos


## One frame of formation following. `st` holds heading, spd, turn_v (changed in place); `to` is the vector from the
## wingman to its slot, `pv` the leader's velocity; with `clear` > 0, `lead` (wingman → leader) feeds the S16-24
## nose rule, `speed_to` (if given) is what the speed is matched to instead of `to`. Returns the wingman's
## velocity for this frame.
static func follow(st: Dictionary, to: Vector2, pv: Vector2, delta: float, lead := Vector2.ZERO, clear := 0.0,
		speed_to := Vector2.INF) -> Vector2:
	var ps := maxf(pv.length(), 1.0)
	var fwd := pv / ps
	var dist := to.length()
	var aim := to + pv * (LOOK + clampf(dist / ps, 0.0, 1.2))
	var along := (to if speed_to == Vector2.INF else speed_to).dot(fwd)
	var want_s := ps * clampf(1.0 + along / SPD_GAIN, MIN_K, MAX_NEAR if dist < FAR_R else MAX_FAR)
	var want_h := aim.angle()
	var turn_k := 1.0
	if clear > 0.0:
		var pa: float = st.get("lead_h", pv.angle())
		var lw := clampf(angle_difference(pa, pv.angle()) / maxf(delta, 0.001), -LEAD_W_MAX, LEAD_W_MAX)
		st.lead_h = pv.angle()
		st.lead_w = lerpf(float(st.get("lead_w", 0.0)), lw, minf(1.0, delta * 12.0))
		var h := avoid_heading(want_h, float(st.heading), maxf(float(st.get("spd", ps)), 1.0), lead, pv, clear,
			float(st.lead_w))
		if h != want_h:
			want_h = h
			turn_k = AVOID_TURN
	steer(st, want_h, want_s, ps, delta, turn_k, turn_k)
	var v := Vector2.from_angle(st.heading) * float(st.spd)
	return v + to * NUDGE * clampf(1.0 - dist / NEAR_R, 0.0, 1.0)


## S16-24: the heading nearest to `want_h` that is safe from the leader (`lead` = wingman → leader, `pv` its
## velocity), tried in AVOID_STEP steps. A heading is unsafe when, flown at `spd` for AVOID_T s against the leader's
## own flight, it brings the wingman inside the keep-out disc (clear × AVOID_DISC), or when the leader is closer
## than clear × AVOID_R and the nose line crosses the disc; `lw` is the leader's turn rate (the «nose-poke» Kanta saw). Of two equally near safe
## headings the one on the side the nose (`cur_h`) already is wins, so the nose never swings across the leader.
## With nothing safe (already inside the disc), the heading that opens the gap the most.
static func avoid_heading(want_h: float, cur_h: float, spd: float, lead: Vector2, pv: Vector2, clear: float, lw := 0.0) -> float:
	var d := lead.length()
	if d >= clear * AVOID_FAR:
		return want_h
	var side := signf(wrapf(cur_h - lead.angle(), -PI, PI))   # the side of the leader the nose is on
	if side == 0.0:
		side = 1.0
	var best := want_h
	var best_miss := -INF
	for i in int(PI / AVOID_STEP) + 1:
		for s in [side, -side]:
			var h: float = want_h + s * AVOID_STEP * i
			var miss := _miss(h, spd, lead, pv, lw)
			var r := clear * AVOID_DISC
			var nose_ok := d >= clear * AVOID_R or absf(wrapf(h - lead.angle(), -PI, PI)) >= asin(minf(1.0, r / maxf(d, 0.001)))
			if miss >= r and nose_ok:
				return h
			if miss > best_miss:
				best_miss = miss
				best = h
			if i == 0:
				break
	return best


## S16-24 last line of defence when steering alone was too slow (the leader turned hard into the wingman): closer
## than clear × NOSE_R the nose is held out of the cone in which its line would cross the leader's disc, on the side
## it already is; the cone fades in over NOSE_FADE so the nose never jumps. Returns the velocity along the nose.
static func nose_clear(st: Dictionary, lead: Vector2, clear: float) -> Vector2:
	var d := lead.length()
	var k := clampf((clear * NOSE_R - d) / (clear * NOSE_FADE), 0.0, 1.0)
	if k > 0.0:
		var b := lead.angle()
		var cone := asin(minf(1.0, clear * AVOID_DISC / maxf(d, 0.001))) * k
		var diff := wrapf(float(st.heading) - b, -PI, PI)
		if absf(diff) < cone:
			st.heading = wrapf(b + (1.0 if diff >= 0.0 else -1.0) * cone, -PI, PI)
	return Vector2.from_angle(float(st.heading)) * float(st.spd)


## Closest the wingman comes to the leader within AVOID_T s, flying heading `h` straight at `spd` while the
## leader keeps turning at `lw` rad/s (so a hard turn into the wingman is seen as it starts). Only points where the
## gap is smaller than now count: INF when the gap only opens, so a wingman already too close may still fly out.
static func _miss(h: float, spd: float, lead: Vector2, pv: Vector2, lw := 0.0) -> float:
	var d0 := lead.length()
	var u := Vector2.from_angle(h) * spd
	var lp := lead
	var v := pv
	var dt := AVOID_T / float(AVOID_SAMPLES)
	var best := INF
	for i in AVOID_SAMPLES:
		v = v.rotated(lw * dt)
		lp += v * dt
		var d := (lp - u * dt * (i + 1)).length()
		if d < d0:
			best = minf(best, d)
	return best


## Turn towards `want_h` and change speed towards `want_s` with eased turn rate and limited acceleration
## (`ps` scales the acceleration; `turn_k` widens the turn rate for attack runs).
static func steer(st: Dictionary, want_h: float, want_s: float, ps: float, delta: float, turn_k := 1.0, roll_k := 1.0) -> void:
	var spd := float(st.get("spd", 0.0))
	if spd <= 0.0:
		spd = want_s
	var max_w := minf(deg_to_rad(TURN * turn_k), spd / MIN_R)
	var diff := wrapf(want_h - float(st.heading), -PI, PI)
	var want_w := clampf(diff * TURN_GAIN, -max_w, max_w)
	var w := move_toward(float(st.get("turn_v", 0.0)), want_w, deg_to_rad(ROLL_ACC * roll_k) * delta)
	st.turn_v = w
	st.heading = wrapf(float(st.heading) + w * delta, -PI, PI)
	st.spd = move_toward(spd, want_s, maxf(ps, 1.0) * ACC * delta)
