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
