class_name AcesBalance
extends RefCounted
## Numbers and rules of the «Битва асов» test mode (Kanta 2026-10-26, AB-01, plan
## `docs/superpowers/plans/2026-10-26-aces-battle-test.md`): «Оса» against a few interceptors, more missile
## carriers and frequent rival aces, with heavier flight and «realistic» damage. First guesses, to be tuned by
## Kanta's feel in play; the campaign does not read any of them.

## Flight, as multipliers on the campaign numbers (defaults of the F1 sliders `aces_*` in `Tuning`, which the
## game reads, so Kanta can tune them in the tester build): inertia of the heading catch-up, speed lost in a hard turn,
## turn rate (wider turns). Cruise speed and camera zoom: SPEED_NEW and ZOOM_NEW below.
## Sky Knights gameplay frames (2026-10-26): the plane does not slide, the nose follows the path; the weight is
## in the speed lost in a turn and in the bank. Kanta asked for a little slide on top: inertia ×1.4 ≈ 0.2 s of
## catch-up (campaign ≈ 0.14 s, the first guess ×2.5 ≈ 0.36 s slid too much). Turn ≈ 100°/s like theirs.
const INERTIA_K := 1.4
const BLEED_K := 2.0
const TURN_K := 0.5

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

## Kanta 2026-11-04 (AB-03): «асы дохнут с 1–2 ракет». With the 8-card draft «Оса»'s air-to-air missile is already
## level 3–5 (≈ 100–230 per missile), above the ace's whole hull. One homing missile of the player now takes at most
## 1 / ACE_MISSILES of a rival ace's hull (F1 `aces_ace_msl`), so an ace takes at least that many hits, mirroring
## the player's own «3 missiles kill». Bullets are not capped: guns keep rewarding the tail.
const ACE_MISSILES := 4.0
## Kanta 2026-11-04 (AB-03): «увеличить скорость где-то на 20 % и отдалить камеру слегка». Defaults of the F1
## sliders `aces_speed` and `aces_zoom`; in s15 they were 1.3 and 0.85.
const SPEED_NEW := 1.56
const ZOOM_NEW := 0.75
## Rival ace behaviour in the mode (AB-03, F1 `aces_ai`, 0 — as in s15):
## missiles: one launch every ACE_MSL_CD s when the player is between ACE_MSL_MIN and ACE_MSL_MAX px and within
## ACE_MSL_CONE degrees of its nose, after the usual lock warning; collision: when the two planes will pass closer
## than AVOID_R px within AVOID_T s, the ace turns away; attack runs: after an overshoot it comes back in
## BREAK_T s (s15 1.6 s).
const ACE_MSL_CD := 6.0
const ACE_MSL_FIRST := 3.0
const ACE_MSL_MIN := 250.0
const ACE_MSL_MAX := 950.0
const ACE_MSL_CONE := 25.0
const AVOID_R := 110.0
const AVOID_T := 0.9
const BREAK_T := 1.0

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


## Most a player's hit from `src_class` (`Enemy.src_class`) may take from a rival ace with `max_hp` when
## `missiles` homing missiles must be needed to bring it down (AB-03); INF for every other kind of hit.
static func ace_hit_cap(src_class: String, max_hp: float, missiles: float = ACE_MISSILES) -> float:
	if src_class != "homing" or missiles <= 0.0:
		return INF
	return max_hp / missiles


## True when two planes, `rel_pos` = other − self and `rel_vel` = other's velocity − self's, will pass closer than
## `r` px within the next `t` s (closest approach of straight-line flight). Used by the rival ace to break off
## before a ram, which in the mode costs half the player's hull (AB-03).
static func collision_ahead(rel_pos: Vector2, rel_vel: Vector2, r: float = AVOID_R, t: float = AVOID_T) -> bool:
	if rel_pos.length() < r:
		return true
	var vv := rel_vel.length_squared()
	if vv < 1.0:
		return false
	var tc := clampf(-rel_pos.dot(rel_vel) / vv, 0.0, t)
	return (rel_pos + rel_vel * tc).length() < r


## True when a rival ace may launch a missile at the player `d` px away and `off_deg` degrees off its nose.
static func ace_can_launch(d: float, off_deg: float) -> bool:
	return d >= ACE_MSL_MIN and d <= ACE_MSL_MAX and off_deg <= ACE_MSL_CONE
