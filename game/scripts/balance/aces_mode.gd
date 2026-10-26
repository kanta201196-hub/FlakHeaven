class_name AcesBalance
extends RefCounted
## Numbers and rules of the «Битва асов» test mode (Kanta 2026-10-26, AB-01, plan
## `docs/superpowers/plans/2026-10-26-aces-battle-test.md`): «Оса» against a few interceptors, more missile
## carriers and frequent rival aces, with heavier flight and «realistic» damage. First guesses, to be tuned by
## Kanta's feel in play; the campaign does not read any of them.

## Flight, as multipliers on the campaign numbers: inertia of the heading catch-up, speed lost in a hard turn,
## turn rate (wider turns), cruise speed of the player and interceptors, camera zoom (less = further out).
const INERTIA_K := 2.5
const BLEED_K := 2.0
const TURN_K := 0.8
const SPEED_K := 1.3
const ZOOM_K := 0.85

## Share of the player's max HP one hit takes: a missile (3 kill), a bullet (two long ace bursts of 5 rounds,
## a miss or two, kill), a ram.
const MISSILE_SHARE := 0.34
const BULLET_SHARE := 0.115
const RAM_SHARE := 0.5
## Post-hit invulnerability, s: the campaign's 0.7 s would swallow most of a burst (rounds 0.09 s apart).
const HIT_INVULN := 0.05

## Fixed enemy HP. «Оса» air-to-air missile is 45 at level 1, its gun ≈ 100 per second (11 × 9):
## interceptor ≈ 1.5 missiles or one long burst, carrier 2 missiles, rival ace 3 missiles or two long bursts.
const INTERCEPTOR_HP := 70.0
const CARRIER_HP := 90.0
const ACE_HP := 140.0

## Rival aces: the first one at ACE_FIRST s, then every ACE_EVERY s, at most ACE_MAX in the air.
const ACE_FIRST := 20.0
const ACE_EVERY := 45.0
const ACE_MAX := 2
## How many of each kind stay in the air and how often the spawner tops them up, s.
const INTERCEPTOR_MAX := 2
const CARRIER_MAX := 4
const TOPUP_EVERY := 6.0


## Damage of one hit on the player in the mode: missiles, bullets and rams take a fixed share of `max_hp`
## (the plane's armour and shields still apply after this); any other source keeps its `amount`.
static func player_hit(source: String, amount: float, max_hp: float) -> float:
	match source:
		"ракеты":   # i18n-skip
			return max_hp * MISSILE_SHARE
		"пули":   # i18n-skip
			return max_hp * BULLET_SHARE
		"таран":   # i18n-skip
			return max_hp * RAM_SHARE
	return amount


## True when a new rival ace should take off at time `t`: its slot `next_t` has come and fewer than ACE_MAX
## are up.
static func ace_due(t: float, next_t: float, alive: int) -> bool:
	return t >= next_t and alive < ACE_MAX


## True when the spawner should add one enemy of `kind` ("interceptor", "carrier") with `alive` of them up;
## other kinds never spawn in the mode.
static func needs(kind: String, alive: int) -> bool:
	match kind:
		"interceptor":
			return alive < INTERCEPTOR_MAX
		"carrier":
			return alive < CARRIER_MAX
	return false
