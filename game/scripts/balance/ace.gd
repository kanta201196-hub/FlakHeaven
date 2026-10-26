class_name AceBalance
extends RefCounted
## Numbers of the aces (`Boss`).

## Damage the first-wave ace (5:00) deals to the player and wingmen: bullets, missiles and ramming.
## Its HP stays the same. GD-02 (Kanta 2026-10-23, option 1): the first ace was the main place
## of death for «Оса» and «Кит» at minutes 5–7 (M3 on the edge of its corridor).
const FIRST_WAVE_DMG_K := 0.7


## Damage multiplier of an ace that came with spawner wave `wave` (1 — the 5:00 ace).
static func dmg_k(wave: int) -> float:
	return FIRST_WAVE_DMG_K if wave == 1 else 1.0


## Chance that an ace's flares pull away a player missile within their reach: wave aces (`Boss`) and the campaign
## rival ace. Kanta 2026-10-26 (decision card «Ловушки асов слабее», 3.5-s12): «Оса» is the missile class and died in
## the first-ace fight 3 of 3 times while flares took 36–83 of her missiles in 6 minutes («Грач»: 81 in 16.5), so
## against her missiles aces flare at FLARE_CHANCE_OSA. `docs/playtest/3.5-s12/osa-first-ace.md`.
const FLARE_CHANCE_BOSS := 0.85
const FLARE_CHANCE_RIVAL := 0.8
const FLARE_CHANCE_OSA := 0.5


## Flare chance of an ace whose normal chance is `base` against the missiles of the class `cls_id`
static func flare_chance(base: float, cls_id: String) -> float:
	return FLARE_CHANCE_OSA if cls_id == "fighter" else base


## GD-08 (Kanta 2026-10-25, option 1): the Fortress strength follows the player's damage with this share of it
## for every class. The share measured in ace duels does not fit the Fortress, where only hits near a turret or an
## engine count: in 3.5-s11 «Оса» duelled aces at 1.46–1.6 and met a Fortress of 605k against 82–97k for «Грач»
## and «Кит» (their share 0.55–0.56).
const FORTRESS_SINGLE_K := 0.55


## Fortress strength before the two-aces-with-shields factor: the time formula `formula_hp`, or the player's damage
## over the fight time at share 1 (`dps_hp_k1`) times FORTRESS_SINGLE_K, whichever is larger.
static func fortress_hp(formula_hp: float, dps_hp_k1: float) -> float:
	return maxf(formula_hp, dps_hp_k1 * FORTRESS_SINGLE_K)
