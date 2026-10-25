# Enemy damage to the player: who deals it and how (2026-10-25)

Kanta's request (2026-10-25): the game designer analyses enemy damage and proposes how to shift the accents if needed. **Proposals only, nothing is changed**; Kanta collects the s11 list and hands it out after "готово". Skill: `flak-heaven-game-design`; method: `docs/balance-method.md`. Already merged and taken into account: GD-02 (first ace deals ×0.7, PR #412) and S11-30 (Fortress fight cap, PR #411).

## Data

| Source | Sorties | Notes |
| --- | --- | --- |
| Bot, demo profile, 15:00 (`base_demo_a/b/c`, 2026-10-23/24) | 62 (21 / 21 / 20 per class) | before GD-02; operations «Перевал», «Сухое русло» |
| Bot, fresh profile, 15:00 | 29 | the floor |
| Bot «Грач», Fortress fight to 18:00 (`fort_ademo`, `fort_amax`) | 16 | after S11-30 |
| Kanta, 3.5-s11 «Грач», sky/Ас, died at 16:35 in the Fortress fight | 1 | sheet «Вылеты» row 41; more s11 numbers are being collected by the s11 reports thread |

Columns used: `taken_ram / taken_bullets / taken_missiles`, `taken_by` (who), `taken_kind` (which weapon), timeline `tk` (taken per minute), `max_hp`. The bot flies worse than a human, so shares are more reliable than absolute numbers.

## What the numbers say

**1. One source deals most of the damage: the guns of drones and interceptors.** Share of all damage taken (bot demo, «Оса» / «Грач» / «Кит»): interceptors 37 / 42 / 40 %, drones 23 / 28 / 30 %. By weapon, "пушки истребителей" are 61 / 68 / 68 %. Kanta's s11 sortie: 76 % fighter guns, interceptors 40 %, drones 26 %. Everything else is small: missile carriers 3–13 %, aces 7–14 %, all ground threats (ПВО, ЗСУ, БМП, armoured car, pickup, MANPADS) together 2–7 %.

**2. Collisions are a quarter to a third of all damage.** Ramming (`taken_ram`, median per sortie): «Оса» 654 of 1798 (36 %), «Грач» 391 of 1572 (25 %), «Кит» 622 of 2556 (24 %). Kanta's s11 «Грач»: 689 of 2468 (28 %), the same as the bot. Drones (6) and interceptors (8) die on contact, so the player is punished for being where the action is.

**3. «Оса» takes the most relative to her strength.** Damage taken in "full HP bars" per sortie: «Оса» 10.2, «Грач» 5.7, «Кит» 6.5. «Оса» has 164 HP against 289 / 336 and is the class that should win by manoeuvre; her extra comes from ramming (36 %).

**4. Damage per minute grows about ×2.5 from minute 7 to 15.** Bot demo, median taken per minute: minutes 2–5 about 70 / 70 / 110, minute 6 (first ace) 243 / 163 / 255, minutes 7–8 about 75 / 70 / 125, minute 15 211 / 176 / 254. Two things multiply: `Spawner.dmg_ramp` (enemy damage ×1 at 7:00 → ×2 at 15:00) and more attackers at once (`attack_slots` 4 → 8) with wave density up to ×1.5. For «Оса» minute 15 is 1.3 HP bars per minute.

**5. The Fortress fight is the biggest spike of the sortie.** Bot «Грач», minutes 16–17: 825 and 658 per minute, 3–4× minute 15 (about 3 HP bars a minute). Most of it is ramming: in those sorties `taken_ram` is 1685–2210 against 280 in a normal 15-minute sortie (escort interceptors add a part; the split by attacker is not logged). The Fortress body (contact 25 per hit, radius 70) hits every time the player flies under it, and the turret phase now asks the player to stay close. Kanta died in exactly this fight (s11, 95 s in, HP 21 % at minute 14).

The first-ace spike (point 4, minute 6) is what GD-02 already addresses: ace damage up to 8:00 fell 214 → 150 / 120 → 82 / 222 → 124 (the combat thread's measurement, 48 + 48 sorties).

## What to shift, with options

Principle (Kanta, 2026-10-21): the player should enjoy, not overcome. Damage should come from threats the player can see and dodge, each class should feel its own danger, and the finale should be a show, not a wall.

### D1. Fortress body (point 5): **recommended first**
- **A (recommended):** no contact damage from the Fortress body (25 → 0). It is a heavy bomber high above the fight; the threat stays in the turrets, carpet, missiles and rings. Fits FB-01 ("intercept, choose the angle").
- B: contact 25 → 8 (as an interceptor), still a reason not to sit under it.
- C: keep 25, but the dive (нырок) and afterburner pass already reduce it; teach it with a hint.
Check: Fortress corridor (fight 60–100 s) and taken per minute in minutes 16–18 at most ×2 of minute 15 (new number, proposed).

### D2. Collisions with small fry (point 2, 3)
- **A (recommended):** drones and interceptors deal ×0.5 on contact (6 → 3, 8 → 4). They still die; the player is less punished for flying into the swarm. Expected: ramming 25–36 % → 13–20 % of damage, «Оса» gains the most.
- B: keep the numbers, give «Оса» her own rule: ramming ×0.5 only for her (fits "manoeuvre class").
- C: leave as is; it is a genre norm.

### D3. Late growth (point 4)
- **A (recommended):** `dmg_ramp` ×2 → ×1.6 at 15:00 (divisor 480 → 800). Density and attack slots still make the end busier, but each hit stays readable. Expected: late minutes −15–20 % damage; check M5 (would die) and M6 (repair/taken stays ≥ 0.6, otherwise there is no threat).
- B: keep the ramp, cap attack slots at 6 instead of 8.
- C: leave as is.

### D4. Variety of threats (point 1): bigger, rules
- **A (recommended, after the demo):** move part of the danger from guns to telegraphed threats: fighter guns −15 % (`eb_fighter_dmg` 3 → 2.5), missile carriers and ground AA (ЗСУ, ЗРК zones) +25 %. Then «Грач» feels the ground and «Кит» the missiles, and dodging matters more than HP.
- B: only raise ground AA around ground targets (+50 % in a 600 px zone), so «Грач»'s work has its own danger.
- C: leave the single source; tune only totals.
This changes how a sortie feels, not one number, so it is a rule change: separate plan and Kanta's yes, not before the Next Fest demo is stable.

## Recommended order

One balance change per build (Kanta allowed two for GD-02 + S11-30 once):
1. **D1-A** Fortress contact 25 → 0 — next build, measured on the Fortress runs (`UNTIL=1080 EXTRA="--class=attacker"`, demo and max).
2. **D2-A** small-fry contact ×0.5 — build after; measured on the 62-sortie demo baseline (M5, M6, share of ramming).
3. **D3-A** late ramp ×1.6 — after D2, if M5 for «Оса» and «Кит» is still outside the corridor.
4. **D4** — plan after the demo.

Not proposed: lowering all enemy damage at once (would make the threat vanish, M6 already 0.64–0.83), or more HP for «Оса» (hides the cause, which is ramming).
