class_name AcesBalance
extends RefCounted
## Numbers and rules of the «Битва асов» test mode (Kanta 2026-10-26, AB-01, plan
## `docs/superpowers/plans/2026-10-26-aces-battle-test.md`): «Оса» against a few interceptors, more missile
## carriers and frequent rival aces, with heavier flight and «realistic» damage. First guesses, to be tuned by
## Kanta's feel in play; the campaign does not read any of them.

## Flight, as multipliers on the campaign numbers (defaults of the F1 sliders `aces_*` in `Tuning`, which the
## game reads, so Kanta can tune them in the tester build): inertia of the heading catch-up, speed lost in a hard turn,
## turn rate (wider turns), cruise speed of the player and interceptors, camera zoom (less = further out).
## Sky Knights gameplay frames (2026-10-26): the plane does not slide, the nose follows the path; the weight is
## in the speed lost in a turn and in the bank. Kanta asked for a little slide on top: inertia ×1.4 ≈ 0.2 s of
## catch-up (campaign ≈ 0.14 s, the first guess ×2.5 ≈ 0.36 s slid too much). Turn ≈ 100°/s like theirs.
const INERTIA_K := 1.4
const BLEED_K := 2.0
const TURN_K := 0.5
const SPEED_K := 1.3
const ZOOM_K := 0.85

## Look of the turn (Sky Knights frames): the plane rolls to about 60° (campaign ≈ 32°), rolls in fast
## (≈ 0.3 s) and out slowly (≈ 0.8 s); the white contrail behind it lives 3.5 s, so whole arcs stay on screen.
const BANK_VIS_DEG := 60.0
const BANK_IN_RATE := 10.0
const BANK_OUT_RATE := 3.5
const TRAIL_LIFE := 3.5

## Share of the player's max HP one hit takes: a missile (3 kill), a bullet of a rival ace (two long bursts of
## 5 rounds, a miss or two, kill), a bullet of anyone else, a ram. s12 (Kanta's log 26.10): with every bullet at
## the ace share, two interceptors killed «Оса» in 78 s before she met an ace; their guns now take ~25 hits.
const MISSILE_SHARE := 0.34
const BULLET_SHARE := 0.115
const LIGHT_BULLET_SHARE := 0.04
const RAM_SHARE := 0.5
## Post-hit invulnerability, s: the campaign's 0.7 s would swallow most of a burst (rounds 0.09 s apart).
const HIT_INVULN := 0.05

## Fixed enemy HP. «Оса» air-to-air missile is 45 at level 1, its gun ≈ 100 per second (11 × 9):
## interceptor ≈ 1.5 missiles or one long burst, carrier 2 missiles, rival ace 3 missiles or two long bursts.
const INTERCEPTOR_HP := 70.0
const CARRIER_HP := 90.0
const ACE_HP := 140.0

## Rival aces: the first one at ACE_FIRST s, then every ACE_EVERY s, at most ACE_MAX in the air.
## s12, Kanta: «слишком много мелких, хочется больше асов» — aces come sooner and more often, fewer escorts.
const ACE_FIRST := 10.0
const ACE_EVERY := 25.0
const ACE_MAX := 3
## Rival ace flares in the mode: chance to lure a missile and charges (campaign 0.8 and 3). s12 log: aces
## lured 10 of «Оса»'s missiles in 78 s, and three missiles are meant to bring an ace down.
const ACE_FLARE_CHANCE := 0.5
const ACE_FLARE_CHARGES := 2
## How many of each kind stay in the air and how often the spawner tops them up, s.
const INTERCEPTOR_MAX := 1
const CARRIER_MAX := 2
## Build loop (Kanta 2026-10-26, option 1): DRAFT_PICKS ordinary card picks in a row before takeoff, then one
## more for every rival ace shot down, CARDS_MAX picks per sortie at most. No XP from kills.
const DRAFT_PICKS := 8
const CARDS_MAX := 20
## Player flares on F (the 2nd skill slot) in the mode: a salvo like «Кит»'s, every FLARE_CD s.
const FLARE_CD := 6.0
const TOPUP_EVERY := 6.0


## Damage of one hit on the player in the mode: missiles, bullets and rams take a fixed share of `max_hp`
## (the plane's armour and shields still apply after this); a rival ace's bullets (`who` = its `kind()`) hit
## harder than anyone else's; any other source keeps its `amount`.
static func player_hit(source: String, amount: float, max_hp: float, who := "") -> float:
	match source:
		"ракеты":   # i18n-skip
			return max_hp * MISSILE_SHARE
		"пули":   # i18n-skip
			return max_hp * (BULLET_SHARE if who == "ас-соперник" else LIGHT_BULLET_SHARE)   # i18n-skip
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


## Rate (1/s) at which the bank follows `want`: fast when rolling deeper into a turn, slow when levelling out.
static func bank_rate(bank: float, want: float, rate_in: float = BANK_IN_RATE, rate_out: float = BANK_OUT_RATE) -> float:
	var deeper := absf(want) > absf(bank) and (signf(want) == signf(bank) or bank == 0.0)
	return rate_in if deeper else rate_out


## Card picks earned by shooting down the `aces_down`-th rival ace: one while the sortie total (draft + aces)
## stays within CARDS_MAX, then none.
static func ace_picks(aces_down: int) -> int:
	return 1 if DRAFT_PICKS + aces_down <= CARDS_MAX else 0
