class_name AccentCurve
extends RefCounted
## Pure maths of an in-combat «кино-момент» (plan step 4, design `docs/story/cutscenes-and-presentation.md` §3.3):
## time slows to SLOW at once and eases back to normal over DUR seconds with a quadratic (exponential-like) return, so
## the hit lands hard and the fight resumes smoothly. No engine state: unit-tested in `game/tests/accent_curve_test.gd`;
## `Main` multiplies the result into `Engine.time_scale` like the card-combo slow-motion.

## Length of the accent, real seconds, and the time scale at its start.
const DUR := 1.5
const SLOW := 0.35
## Music duck of an accent, dB (the `Music` bus; `Sfx._duck` returns by itself).
const DUCK_DB := 8.0


## Time-scale factor with `left` seconds of the accent remaining: SLOW at the start, 1.0 when it is over.
static func scale_at(left: float) -> float:
	if left <= 0.0:
		return 1.0
	var k := 1.0 - clampf(left / DUR, 0.0, 1.0)   # 0 at the start → 1 at the end
	return SLOW + (1.0 - SLOW) * k * k
