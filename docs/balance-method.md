# Balance method (R-10, GD-01)

Version 1.1, 2026-10-24 (noise rule replaced after the A/A check, section 6). Kanta's decisions of 2026-10-23: balance is measured on the demo player profile (GD-01); Kanta's task: "build a system of balance changes on sortie data, run as many sorties as it needs". Background and the first diagnosis: `docs/playtest/gd-review-2026-10-23.md`. The game designer skill (`flak-heaven-game-design`) applies on top of this document.

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

All seven are computed by `tools/ci/balance_table.py` (PR #347), with a per-class summary and the corridor check.

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
4. **"Before" and "after" on the same `main` commit**: at least 24 sorties each (`OPS="1 2" PAR=2 RUNS=6`, 8 per class, 1–2 h each in the cloud). For the HP metrics (M2, M3, M5) 48 each (16 per class): with 8 their interval is about ±50 points and almost nothing shows.
5. **The change counts** when the bootstrap 90 % interval of the median difference excludes 0 (`balance_table.py <after> --before <before>` marks it **counts**). Otherwise it is noise: 24 more sorties for both, or drop the change. A change aimed at one metric must "count" on that metric; about 1 in 20 other cells will "count" by chance.
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

## 7. Noise check (A/A), 2026-10-24

A second baseline of the same profile (18 sorties, `main` after the RunState refactor PR #344–#346, no balance change) compared with the first (20 sorties):
- The first rule ("median moved by more than half the IQR") called 9 of 21 metric × class cells a shift — it is too strict to tell noise from a change, so it is replaced (section 4, item 5).
- The bootstrap 90 % interval flags 1 of 21 («Грач» signature share 8 → 18 %; about 2 of 21 are expected by chance). The refactor itself may also have moved it — it is watched in the next baseline.
- Detectable with 6–8 sorties per class: level ±5, ace fight ±10–20 s, repair / taken ±0.2, signature share ±10 points. HP metrics (M2, M3) and "would die" (M5) need 16 per class.
- Both baselines agree on the problems: «Оса» and «Кит» are outside M2/M3/M4/M5, the signature share is below 20 % for all three, levels and repair are inside. From now on the two baselines are pooled (38 sorties) as "before" for the next change.
- 2 of 24 sorties of the second run hung at minute 9–11 (process asleep on a lock, no CPU, no error) at about the same real time; killed after 1.5 h. Guess: something outside the game (both at once); if it repeats, it goes to the backlog as a bug.

## 8. Pooled baseline and the floor, 2026-10-24

"Before" for the next change — demo profile, both baselines pooled (38 sorties; commits 359d42c and ce7ad98, no balance change between them). Floor — fresh profile (empty hangar, crew lvl 1), 29 sorties, same operations. Median [min–max], ✗ outside the corridor:

| Metric | Corridor | Demo «Оса» (13) | Demo «Грач» (13) | Demo «Кит» (12) | Fresh «Оса» (10) | Fresh «Грач» (10) | Fresh «Кит» (9) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Lvl 5 / 10 / 15:00 | 20–26 / 30–38 / 38–48 | 24 / 34 / 40 | 25 / 36 / 44 | 26 / 35 / 42 | 24 / 34 / 43 | 24 / 34 / 42 | 22 / 32 / 39 |
| HP ≤ 5:00, % | ≥ 35 | 37 | 47 | 53 | 40 | 34 ✗ | 37 |
| HP 5–7:00, % | ≥ 35 | 22 ✗ | 55 | 28 ✗ | 2 ✗ | 30 ✗ | 18 ✗ |
| Ace fight, s | 20–45 | 49 ✗ | 38 | 62 ✗ | 57 ✗ | 45 | 91 ✗ |
| Would die | ≤ 30 | 41 ✗ | 16 | 66 ✗ | 57 ✗ | 64 ✗ | 119 ✗ |
| Repair / taken | 0.6–0.95 | 0.69 | 0.83 | 0.64 | 0.71 | 0.69 | 0.61 |
| Signature, % | ≥ 20 | 19 ✗ | 12 ✗ | 7 ✗ | 16 ✗ | 9 ✗ | 10 ✗ |

Reading by section 4, item 1 (danger first):
1. **M3 — the first ace window** is the furthest outside: «Оса» 22 %, «Кит» 28 % on the demo profile; on the fresh profile all three. Together with M4 (ace fight 49 / 62 s) this points at the first ace — GD-02 (first-wave ace ×0.7 damage, Kanta's decision) is the first change by the method.
2. **M7 — signature weapons** below 20 % for all three classes: GD-03 for «Кит», then «Грач» (rockets 12 %).
3. Levels (M1) and repair (M6) are inside on both profiles: S10-13 and EX-10 do not need a follow-up by these numbers.
4. «Грач» is the strongest class on the demo profile (inside on everything but M7). The hangar helps «Грач» much more than the others (would die 64 → 16), «Кит» barely (119 → 66).

Order: GD-02 goes into the next build cycle (this one already carries S10-13 and EX-10), measured "before → after" against this pooled baseline, 48 sorties.

**Third baseline (2026-10-24, 24 sorties, commit 2071305, `balance.sh` from a copy, no hangs).** Against the pooled 38 it is a second A/A check: 1 of 27 cells "counts" («Грач» ace fight 38 → 44 s), about what chance gives at 90 %. The rule holds. The demo baseline is now **62 sorties** (`base_demo_a`, `_b`, `_c`; about 20 per class), enough for the HP metrics too. Its picture is the same as above: «Оса» and «Кит» outside M3 and M5, «Кит» also M4, signature weapons below 20 % for all three.

## 9. The Fortress fight (S11-30), 2026-10-25

The method's metrics stop at 15:00; the Fortress comes at 15:00. Fortress runs use `UNTIL=1080` (3 minutes of fight) and «Грач» only (`EXTRA="--class=attacker"`). `PROFILE=max` is an upgraded player copied from Kanta's 3.5-s11 hangar (`Profile.debug_max_profile`). The autotest prints per phase where the damage offered to the Fortress went: `AUTOTEST: fortress phase N s … near … in … cut … pt … bay … hull … lost …` (in — after the source factor; lost — hit the covered hull; cut — landed but over the fight-length cap).

**Corridor (approved by Kanta on 2026-10-25):** median fight 60–100 s (not killed counts as 180), turrets ≤ 45 s, killed within 3 minutes in ≥ 90 % of sorties.

**What the counters showed (before):** in phase 1 about 2/3 of the damage that passed the cap hit the covered hull, and on the demo profile the cap cut 62 % of all incoming damage. The cap was charged before the hit was routed, so misses used up the turrets' share. Two number changes (turret share 0.07 → 0.056, point radius 46 → 55, 7–8 sorties each) showed no difference from noise.

**Change:** the cap counts only damage that reached the hit points. Before 15–16 / after 8 sorties per profile, median, bootstrap 90 % interval:

| Profile | Fight, s | Turrets, s | Killed in 3 min | Reached the base |
| --- | --- | --- | --- | --- |
| demo | 148 → 93 [−95…−16] **counts** | 81 → 45 [−68…−10] **counts** | 10/15 → 8/8 | 9/15 → 1/8 |
| max | 144 → 134 [−80…+46] | 78 → 70 [−58…+94] | 10/16 → 5/8 | 11/16 → 4/8 |

The upgraded bot's damage is rarely over the cap, so the change barely touches it; in 3 of its 8 "after" sorties it barely attacked the Fortress (bot behaviour). Kanta's s11 sortie dealt about 2.9× the Fortress's strength in 95 s, which is over the cap, so a human upgraded player should gain more than the bot. Check after the build on human logs.

