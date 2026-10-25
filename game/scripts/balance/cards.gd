class_name CardBalance
extends RefCounted
## Card-offer rules that are balance numbers (read by `Cards.offer`).

## GD-06 (Kanta 2026-10-25, option «б»): «Бронеплиты» is almost the only source of max HP in a sortie.
## In 3.5-s11 «Оса» ended a 52-level sortie with 172 HP because the card never came, «Кит» got 882
## with it. From this level the card is guaranteed in a choice while the plane has none.
const ARMOR_LVL := 10
## After a guaranteed offer the player declined, this many choices pass before the next guaranteed one
const ARMOR_EVERY := 3


## Whether the next card choice must carry «Бронеплиты»: the plane is at `level`, has taken the card
## `armor_taken` times, makes choice number `picks`; `next` — the first choice allowed after the last
## guaranteed offer (0 — never offered).
static func armor_due(level: int, armor_taken: int, picks: int, next: int) -> bool:
	return level >= ARMOR_LVL and armor_taken == 0 and picks >= next


## The first choice that may carry the guarantee again after one shown at choice `picks`
static func next_pick(picks: int) -> int:
	return picks + ARMOR_EVERY
