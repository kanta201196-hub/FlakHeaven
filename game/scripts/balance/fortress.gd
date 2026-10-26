class_name FortressBalance
extends RefCounted
## Numbers of the «Крепость» boss fight (Fortress) that Kanta set by name; the rest still live as constants
## at the top of fortress.gd.

## Kanta 2026-10-26 (decision card «Пускать раз в 12 с»): until the fall every live dome turret launches the
## missile on its rail once per this many seconds, counted launch to launch. The dome shows no missile for
## the same time, so the player reads the reload off the model.
const DOME_MSL_EVERY := 12.0
## The first dome launch comes this long after the Fortress appears, and each next dome waits STAGGER more,
## so four domes fire one by one (every 3 s) instead of as a four-missile salvo.
const DOME_MSL_FIRST := 4.0
const DOME_MSL_STAGGER := 3.0
## Lock warning before a dome launch: the same 1.1 s and «lock» sound as the phase-2 bay volley.
const DOME_MSL_LOCK := 1.1
## A dome locks only while the player is closer than this (the bay volley's range).
const DOME_MSL_RANGE := 1000.0
## At most this many Fortress missiles in the air, locks in progress included (same cap as the
## «Укрепрайон» base), so a full set of domes never stacks with leftovers into a wall of missiles.
const MSL_CAP := 4


## One dome's launch clock, pure so the unit test can drive it: "dm" counts down to the next lock, "lk" is the
## lock in progress. Returns "lock" when a lock starts (only if `may`), "fire" when it ends, else "". The next lock
## comes DOME_MSL_EVERY − LOCK after a launch, so an unblocked dome fires exactly every DOME_MSL_EVERY s.
static func dome_step(pt: Dictionary, delta: float, may: bool) -> String:
	if float(pt["lk"]) > 0.0:
		pt["lk"] = float(pt["lk"]) - delta
		if float(pt["lk"]) > 0.0:
			return ""
		pt["lk"] = 0.0
		pt["dm"] = DOME_MSL_EVERY - DOME_MSL_LOCK
		return "fire"
	pt["dm"] = maxf(0.0, float(pt["dm"]) - delta)
	if float(pt["dm"]) > 0.0 or not may:
		return ""
	pt["lk"] = DOME_MSL_LOCK
	return "lock"


## «Крыло за крылом» (Kanta 2026-10-26, decision card): the fight goes wing by wing. Phase 1 is the left wing
## (two domes and the left engine), phase 2 the right wing (two domes, the right engine and the open bay), phase 3
## the fall. Point HP shares are unchanged, only the order. A point's wing comes from its offset in the plane's
## axes: y < 0 is the left wing.
static func wing_of(off: Vector2) -> int:
	return 1 if off.y < 0.0 else 2


## Whether a point of wing `wing` takes damage in phase `phase`: only the current phase's wing, none in the fall
static func targets(phase: int, wing: int) -> bool:
	return phase < 3 and wing == phase


## The phase after a point went down: `wing_alive` is how many points of the current phase's wing are still up
static func next_phase(phase: int, wing_alive: int) -> int:
	return phase + 1 if phase < 3 and wing_alive == 0 else phase
