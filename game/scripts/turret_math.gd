class_name TurretMath
extends RefCounted
## Pure helpers of the machine-gun turrets (Kanta 25.10, Sublight as the reference): a damped turn that speeds up
## and slows down instead of the old constant-speed rotate_toward, and the burst a turret fires each reload.
## Hardpoint aims with turn(); Render3D turns the barrel models with the same function, so both move alike.
## Tests: game/tests/turret_test.gd.

## Speed changes by at most ACCEL × the speed cap per second: full traverse speed in ~0.08 s
const ACCEL := 12.0
## Closing speed per radian of remaining angle (1/s): the barrels slow down softly over the last ~15°
const SETTLE := 10.0
## Rounds in one burst; together they deal the old single round's damage, so damage per second is unchanged
const BURST := 4
## Seconds between rounds of a burst (~22 rounds a second, the dense "brrt" of the reference)
const GAP := 0.045


## Angle `cur` turning at `w` rad/s chases `tgt`, which itself turns at `tgt_w` rad/s (the target crossing the
## view; 0 for a still one). Returns Vector2(new angle, new speed). Speed stays within ±wmax, so the servo cards
## keep their meaning; the feed-forward on tgt_w holds a moving target without lagging behind it.
static func turn(cur: float, w: float, tgt: float, tgt_w: float, wmax: float, delta: float, settle := SETTLE) -> Vector2:
	var want := clampf(tgt_w + wrapf(tgt - cur, -PI, PI) * settle, -wmax, wmax)
	w = move_toward(w, want, wmax * ACCEL * delta)
	return Vector2(cur + w * delta, w)


## Damage of one round of a burst
static func round_dmg(shot_dmg: float) -> float:
	return shot_dmg / float(BURST)


## Gap between rounds for a given reload: GAP, shortened when cards make the reload shorter than a whole burst
static func gap(reload: float) -> float:
	return minf(GAP, reload / float(BURST))
