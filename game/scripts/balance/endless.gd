class_name EndlessBalance
extends RefCounted
## «Долгий вылет» (MO-01, Kanta 05.11): once the operation goal is done and 15:00 has passed, the sortie becomes a
## survival run. Enemy caps keep rising without an upper bound, and dying no longer costs what was earned by 15:00, so
## staying is never worse than evacuating at 15:00. Plan: docs/superpowers/plans/2026-11-05-build-depth.md, part C.
## Pure rules; Main, Spawner and the HUD read them.

## When the long sortie can start, s (the regular sortie length).
const START := Rewards.SORTIE_LENGTH
## Growth of the enemy toughness cap (Spawner.PRESSURE_MAX) per minute past START.
const PRESSURE_GROW := 0.08
## Growth of the wave density cap (Spawner.DENS_MAX) per minute past START (the enemy count cap still holds).
const DENS_GROW := 0.04
## Share kept of the parts earned past START when the plane is shot down (before START it stays 50 %).
const LATE_KEEP := 0.5


## Seconds of the long sortie at sortie time `t` (0 before START).
static func over(t: float) -> float:
	return maxf(0.0, t - START)


## Toughness cap at `t` while the long sortie is on: `base` before START, then +PRESSURE_GROW of it per minute.
static func pressure_max(base: float, t: float, on: bool) -> float:
	return base * (1.0 + PRESSURE_GROW * over(t) / 60.0) if on else base


## Density cap at `t` while the long sortie is on: `base` before START, then +DENS_GROW of it per minute.
static func dens_max(base: float, t: float, on: bool) -> float:
	return base * (1.0 + DENS_GROW * over(t) / 60.0) if on else base


## Parts kept after being shot down in the long sortie: all of `at_start` (earned by START) and LATE_KEEP of the rest.
static func kept_on_death(total: float, at_start: float) -> float:
	var a := clampf(at_start, 0.0, total)
	return a + (total - a) * LATE_KEEP


## True when `t` beats the record `best` (seconds past START; 0 or less means no record yet).
static func is_record(t: float, best: float) -> bool:
	return over(t) > 0.0 and over(t) > best
