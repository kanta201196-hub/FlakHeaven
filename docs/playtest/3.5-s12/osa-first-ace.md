# 3.5-s12: why «Оса» dies and «Грач» does not (Kanta, 2026-10-26)

Kanta: «На Осе прям чет тяжко было, на Граче попроще». Data: sheet «Вылеты», rows 45–49 (tester 2fba92dd, build 3.5-s12). Skill: `flak-heaven-game-design`; nothing changed in the game yet.

## Sorties

| Row | Class | Mode | Result | Time | Level | Max HP | First ace (5:00) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 45 | «Оса» | «Битва асов» (test) | died | 1:18 | 1 | 172 | — |
| 46 | «Оса» | sky / Ас | died | 6:14 | 20 | 287 | HP 11,256, alive after 73 s, Оса dealt 16,274 into it |
| 47 | «Оса» | sky / Ас | died | 5:50 | 21 | 314 | HP 8,156, alive after 49 s, dealt 14,116 |
| 48 | «Оса» | sky / Ас | died | 6:04 | 20 | 239 | HP 10,645, alive after 64 s, dealt 7,119 |
| 49 | «Грач» | sky / Ас | evacuated | 16:35 | 52 | 605 | HP 8,848, killed in 38 s, dealt 44,377 |

All three campaign deaths of «Оса» are inside the fight with the first ace: it comes at 5:00, she dies 49–73 s later with the ace still alive. Up to 5:00 she is as strong as «Грач» (level 19–20 vs 28, damage per minute at minute 5: 16–19k vs 21k).

## Cause

1. **The first ace is built too strong for «Оса».** Ace HP = player's damage over 14 s × share `single_k`. Before the first ace the share comes from the 2:00 duel ×1.4 (`Spawner.SINGLE_K_FIRST`): «Оса» got 1.02 / 1.36 / 1.49, «Грач» 0.95. What she really put into the ace: 0.42 / 0.70 / 0.93 of her average damage. «Грач» put 3.4 (course gun 33k of 44k). So «Оса» needs 50–120 s instead of the planned ~20 s, and the crowd keeps shooting her meanwhile.
2. **Her main weapon is flared away.** Enemy flares took 36 / 71 / 83 of her missiles in 6 minutes (12–14 per minute); «Грач» lost 81 in 16.5 minutes (5 per minute). «Оса» picks A2A missiles first (4–5 missile cards per sortie), and the ace counters exactly that.
3. **Damage taken in the ace minute:** 109–258 per minute (1/3 to all of her HP); drones and interceptors 55–60 % of all damage, the ace 19–31 %, ramming 20–29 %.

## Options (one balance change per build)

1. **Recommended: the first ace uses a share of at most 1.0** (now up to 1.6 for «Оса»). Her ace HP falls by a quarter to a third (11.3k → ~8.3k, 10.6k → ~7.1k); «Грач» (0.95) and «Кит» (0.49) unchanged. Same idea as GD-08 for the Fortress. Check: bot «Оса» sky/Ас, first-ace fight length and deaths at minutes 5–7, before/after.
2. Aces' flares work worse against «Оса»'s A2A missiles (chance 0.85 → 0.5): the missile class keeps its tool against aces. Rule change, next build.
3. Ramming ×0.5 for «Оса» only (GD-07, D2-B): −10–15 % damage taken.

«Битва асов» (row 45): «Оса» died at level 1 in 78 s, all 205 damage from interceptors. Passed to the «Битва асов» thread.
