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


## GD-08 (Kanta 2026-10-25, option 1): the Fortress strength follows the player's damage with this share of it
## for every class. The share measured in ace duels does not fit the Fortress, where only hits near a turret or an
## engine count: in 3.5-s11 «Оса» duelled aces at 1.46–1.6 and met a Fortress of 605k against 82–97k for «Грач»
## and «Кит» (their share 0.55–0.56).
const FORTRESS_SINGLE_K := 0.55


## Fortress strength before the two-aces-with-shields factor: the time formula `formula_hp`, or the player's damage
## over the fight time at share 1 (`dps_hp_k1`) times FORTRESS_SINGLE_K, whichever is larger.
static func fortress_hp(formula_hp: float, dps_hp_k1: float) -> float:
	return maxf(formula_hp, dps_hp_k1 * FORTRESS_SINGLE_K)
