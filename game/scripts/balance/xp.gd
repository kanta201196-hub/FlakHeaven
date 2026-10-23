class_name XpCurve
extends RefCounted
## Experience curve of a sortie (ADR-04). Used by `RunState`.

## XP for the next level: `BASE + (level - 1) * LINEAR + QUAD * (level - 1)²`
## (aim: about level 35 at 15:00).
const BASE := 4.0
const LINEAR := 2.0
const QUAD := 0.07

## Kill XP fades after 5:00 and is `KILL_LATE` of normal from 7:00 on, so the last main cards
## arrive at minutes 12–13 instead of 10 (S10-13, Kanta 2026-10-23).
const KILL_FROM := 300.0
const KILL_TO := 420.0
const KILL_LATE := 0.5


## XP needed to go from `level` to `level + 1`.
static func need(level: int) -> float:
	return BASE + (level - 1) * LINEAR + QUAD * pow(level - 1, 2.0)


## Multiplier for kill XP at sortie time `t`, s.
static func kill_k(t: float) -> float:
	return lerpf(1.0, KILL_LATE, clampf((t - KILL_FROM) / (KILL_TO - KILL_FROM), 0.0, 1.0))
