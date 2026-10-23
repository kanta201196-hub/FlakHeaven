class_name Rewards
extends RefCounted
## Reward table for sortie activities and level-up fallbacks (ADR-04, CS-03).
## Read only by `RunState.award_activity` and `RunState`'s level-up fallback, so every activity
## pays through one formula. Numbers match the game as of build 3.5-s10.

## How an activity decides whether it pays a pick from rare cards.
enum Rare {
	ALWAYS,     ## every success gives a rare pick
	EVERY_2ND,  ## odd-numbered counted activities of the sortie (1st, 3rd, …) give a rare pick
}

## Reward per activity kind. Keys:
## - `parts` — spare parts paid on every success (before the post-15:00 multiplier);
## - `parts_common` — extra parts when the success did not give a rare pick;
## - `heal_common` — repair, share of max hull, when there was no rare pick;
## - `rare` — `Rare` mode;
## - `counted` — counts towards `activities_done` (and the every-2nd rule);
## - `course_pts` — course points for the player;
## - `reason` — label of the rare pick on the card screen (shown through `Loc`).
const ACTIVITY := {
	&"ground": {"parts": 40.0, "parts_common": 60.0, "heal_common": 0.2, "rare": Rare.EVERY_2ND,
		"counted": true, "course_pts": 1, "reason": "ЗА ПОЗИЦИЮ ПВО"},
	&"convoy": {"parts": 0.0, "parts_common": 60.0, "heal_common": 0.2, "rare": Rare.EVERY_2ND,
		"counted": true, "course_pts": 1, "reason": "ЗА КОЛОННУ"},
	&"dogfight": {"parts": 0.0, "parts_common": 0.0, "heal_common": 0.0, "rare": Rare.ALWAYS,
		"counted": true, "course_pts": 1, "reason": "ЗА АСА"},
	&"transport": {"parts": 90.0, "parts_common": 0.0, "heal_common": 0.0, "rare": Rare.EVERY_2ND,
		"counted": true, "course_pts": 1, "reason": "ЗА ГРУЗ ТРАНСПОРТА"},
	&"rescue": {"parts": 40.0, "parts_common": 0.0, "heal_common": 0.0, "rare": Rare.ALWAYS,
		"counted": true, "course_pts": 1, "reason": "ЗА СПАСЁННОГО ПИЛОТА"},
	&"class_task": {"parts": 80.0, "parts_common": 0.0, "heal_common": 0.0, "rare": Rare.ALWAYS,
		"counted": false, "course_pts": 0, "reason": "ЗА ЗАДАНИЕ КЛАССА"},
}

## Repair kits dropped by a downed transport (picked up by the player, not paid directly).
const TRANSPORT_REPAIR_KITS := 3

## When every card is taken, each pending level pays this many parts instead of a card.
const ALL_CARDS_PARTS_PER_LEVEL := 30.0
## …and this share of max hull per pending level, capped by `ALL_CARDS_HEAL_MAX`.
const ALL_CARDS_HEAL_PER_LEVEL := 0.1
const ALL_CARDS_HEAL_MAX := 0.5

## Kill streak: each kill within `STREAK_WINDOW` s of the previous one adds `STREAK_STEP` to the
## parts and XP multiplier, up to `STREAK_CAP` kills. A near miss keeps the streak for at least
## `NEAR_MISS_HOLD` s.
const STREAK_WINDOW := 2.5
const STREAK_STEP := 0.03
const STREAK_CAP := 30
const NEAR_MISS_HOLD := 1.5

## Sortie length, s: after it every reward grows by `LATE_BONUS_PER_MIN` per minute.
const SORTIE_LENGTH := 900.0
const LATE_BONUS_PER_MIN := 0.1
