# Balance method (R-10, GD-01)

Version 1, 2026-10-23. Kanta's decisions of 2026-10-23: balance is measured on the demo player profile (GD-01); Kanta's task: "build a system of balance changes on sortie data, run as many sorties as it needs". Background and the first diagnosis: `docs/playtest/gd-review-2026-10-23.md`. The game designer skill (`flak-heaven-game-design`) applies on top of this document.

**Status: approved by Kanta on 2026-10-23** — corridors (section 3) and the decision rule (section 4).

## 1. Data: three sources, one table

| Source | What it is | Used for |
| --- | --- | --- |
| **Bot, demo profile** (main) | `tools/ci/balance.sh` with `PROFILE=demo`: plane lvl 1, nodes lvl 2, crew lvl 5, weapon tier 1, first-step perks; operations «Перевал» and «Сухое русло» (the demo) | "before → after" of every change |
| Bot, fresh profile | `PROFILE=fresh`: empty hangar, crew lvl 1 | the floor: the very first sortie of a new player |
| Humans | tester reports, Google Sheet, sheet «Вылеты» (the same l7 line) | truth check after a build: the bot flies worse than a human and picks cards at random |

All three go through `tools/ci/balance_table.py`, so the numbers are comparable.

## 2. Metrics (one row per sortie)

| # | Metric | Where from | What it says |
| --- | --- | --- | --- |
| M1 | Level at 5:00 / 10:00 / 15:00 | timeline `L` | card pace; when content runs out |
| M2 | Lowest HP up to 5:00, % | timeline `hp` | early deaths (minutes 3–4) |
| M3 | Lowest HP at 5:00–7:00, % | timeline `hp` | first ace danger |
| M4 | Ace fight, s (avg / max) | `boss_life_avg`, `boss_life_max` | duel length |
| M5 | "Would die" per sortie | autotest output (`--nodie`) | overall danger, mostly late |
| M6 | Repair / damage taken | `healed` / `taken_*` | is there a threat at all |
| M7 | Signature weapon share of damage, % | `dealt_*` («Оса» A2A missiles, «Грач» rockets, «Кит» bombs + carpet) | does the class role show |

M2, M3 and M7 are not in the table script yet (computed by hand in this version). They go into `balance_table.py` with the next tools change.

## 3. Corridors (approved by Kanta 2026-10-23, bot on the demo profile)

The bot's baseline of 2026-10-23 is below (section 6). A corridor is the range we want for the class median. The proposal starts from Kanta's goals ("enjoy, not overcome", last core cards by minute 12–13, a dangerous but forgiving first ace) and from the baseline.

| # | Corridor (class median) | Baseline «Оса» / «Грач» / «Кит» | In corridor? |
| --- | --- | --- | --- |
| M1 | 20–26 / 30–38 / 38–48 | 24/35/43 · 22/33/43 · 24/35/40 | yes |
| M2 | ≥ 35 % | 55 · 33 · 55 | «Грач» just below |
| M3 | ≥ 35 % | 36 · 55 · 39 | yes, on the edge |
| M4 | first-wave ace 20–45 s | 44 · 39 · 75 | «Кит» no |
| M5 | ≤ 30, and no class above 2× another | 41 · 8 · 77 | «Оса», «Кит» no |
| M6 | 0.6–0.95 | 0.75 · 0.94 · 0.65 | yes |
| M7 | ≥ 20 % | 17 · 8 · 4 | no for all three |

The bot dies more than a human, so M5 is compared between classes and with "before", not as an absolute.

## 4. How a change is made

1. **Pick one problem**: the metric furthest outside its corridor, in this order — M2/M3 (early deaths), M4, M5, M7, M1, M6. Danger first: a player who dies at minute 4 never sees the rest.
2. **Find the cause in the mechanics** (skill: double counting, unlimited bonuses, a role that does not show), not "make the weak stronger" blindly. Write it down as a hypothesis with the metric and the run it comes from.
3. **One change per build**, step 10–20 % (skill rule). Balance is never changed together with a new mechanic.
4. **"Before" and "after" on the same `main` commit**: 24 sorties each (`OPS="1 2" PAR=2 RUNS=6`, 8 per class, ~1 h each in the cloud).
5. **The change counts** when the class median moved toward the corridor by more than half of the "before" interquartile range. Otherwise it is noise: 24 more sorties for both, or drop the change.
6. **Check the neighbours**: the change must not push another metric out of its corridor (for example, less ace damage → M5 still within 2× between classes).
7. **PR** with both tables and one line "was → became" per number, then the usual checks (`smoke.sh`; `full.sh` if combat changed).
8. **After the build**: human logs from the sheet through the same table. Bot and humans agree → a line in the decision log; they disagree → humans win, and the bot method is corrected.

Who decides (Kanta, 2026-10-23): Kanta approves the corridors (section 3), any change of a corridor and every change of rules. A number change that brings a metric back into its corridor is made by Claude without asking: it follows section 4, one per build, with "was → became" in the PR; Kanta sees it in the build.

## 5. Commands

```
# baseline or "after", demo profile, demo operations, 24 sorties, 4 processes (~1 h)
OPS="1 2" PAR=2 RUNS=6 PROFILE=demo OUT=balance_out tools/ci/balance.sh
# floor: fresh profile
OPS="1 2" PAR=2 RUNS=6 PROFILE=fresh OUT=balance_fresh tools/ci/balance.sh
# table again from saved logs
python3 tools/ci/balance_table.py balance_out/op*/godot/app_userdata/*/playtest_log_*.csv
```

In the cloud, Godot 4.4.1 is downloaded from GitHub (link in `.github/workflows/check.yml`) and passed as `GODOT=…`. Run long jobs detached (`setsid nohup`): a container restart kills them, and finished sorties stay in `OUT`. On Kanta's PC (i5-12400) `PAR=3`…`4` is possible (guess).

## 6. Baseline of 2026-10-23 (demo profile, commit 359d42c)

20 sorties (8 «Перевал», 12 «Сухое русло»; the run was cut by a container restart). Median [min–max]:

| Class | Sorties | Lvl 5 / 10 / 15:00 | HP ≤ 5:00, % | HP 5–7:00, % | Ace fight, s | Would die | Repair / taken | Signature, % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| «Оса» | 7 | 24 / 35 / 43 | 55 [1–79] | 36 [2–89] | 44 [36–63] | 41 [4–123] | 0.75 | 17 [11–43] |
| «Грач» | 7 | 22 / 33 / 43 | 33 [12–73] | 55 [12–90] | 39 [33–46] | 8 [0–43] | 0.94 | 8 [1–16] |
| «Кит» | 6 | 24 / 35 / 40 | 55 [52–68] | 39 [0–85] | 75 [38–121] | 77 [5–194] | 0.65 | 4 [2–26] |

The spread is wide: "would die" goes from 5 to 194 for one class. That is why section 4 asks for 8 sorties per class and medians, not single runs.

What the baseline adds to the review:
- With the demo hangar XP is in its corridor (S10-13 works): level 40–43 at 15:00.
- **«Кит» is the weakest for the bot**: most "would die" and the longest ace fight. This agrees with Kanta's s9 note (S9-24: «Кит» lacks air damage) and supports GD-03.
- The signature weapon is weak for all three classes (M7), not only for «Кит».
