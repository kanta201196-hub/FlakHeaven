# Plane tiers 1–5: plan (2026-11-06)

Backlog PT-04 (progression for 5 tiers) with PT-05 (future systems) folded in. Kanta's decision is in `docs/game-context.md` (journal 2026-11-06, «Plane tiers 1–5»), concept page https://claude.ai/artifact/Jcn2GtNbLrRuCVn2xbS9dE. Models are PT-02 / PT-03, owned by the 3D thread «3D-модели по плану Kirill».

**Status: prices and demo settled by Kanta 06.11 18:19 UTC (section 8). Node design (3.4) waits for his «да»; no code before that.** All numbers marked *guess* are first guesses for the balance run, not rules.

## 1. What Kanta decided (fixed, not up for discussion here)

- Five tiers per class: 1 — early aircraft; 2–3 — the current models (plane 1 → tier 2, plane 2 → tier 3); 4–5 — near future (shields, lasers).
- Tier 1 references: Оса — MiG-15/17-like; Грач — Strikemaster-like (backup Su-11 1947); Кит — He 177 A-3-like piston (tier 1 cannot be a jet, Кит 2 has propellers). Real names never go into the repo or the game.
- Experimental weapons move from plane lvl 2 to tiers 4–5.
- Demo: tiers 1–3 playable; tiers 4–5 visible in the hangar, locked («в полной игре»).

## 2. Today in code (main 552ec666)

- Two planes per class. `Profile` class dict: `plane2` (bought), `plane_sel` (1/2), `nodes` / `nodes2`, `kit1` / `kit2`, `decals1` / `decals2`. `Profile.plane_lvl(c)` returns 1 or 2; `--plane=1|2` debug flag.
- Plane 2: `PLANE2_COST` 50 000 parts, crew lvl 3 (`PLANE2_CREW`), after operation 1 «Перевал» (`can_buy_plane2`). Not sold in the demo (`Profile.plane2` is false when `Demo.on`).
- What plane 2 gives over plane 1 (`PlaneClasses.PLANES`): ★ class bonus 15 % → 20 %; Оса — `srm` and agm +5 %; Грач — turrets max 1 → 2; Кит — turrets max 2 → 3; Оса — wingman type «Грачонок». Also: heavy hardpoint with experimental weapons (`Player`, `Weapons.EXP`, gated per operation by `Weapons.EXP_OP`), weapon branch tier 3 (`Profile.evo_variant`, needs plane 2), +1 card reroll (`Profile.extra_rerolls`).
- Node progress is separate per plane, plane 2 starts from zero (Kanta, test 3.5-s5 edit 6). Node prices 160 / 500 / 1 200 / 2 800 / 5 800, all six nodes of one plane 62 760 parts. A sortie earns about 13–15 k (s16 logs).
- `plane_lvl` / `plane2` / `nodes2` / `kit2` / `PLANE2` appear in 23 scripts, 46 times in `profile.gd`. Models: `fh_battle_<cls>_1|2.glb` and hangar twins; `PlaneArt.plane_tex / shape_info / slot_points` and `WeaponModels.mounts` key on `(cls, lvl)`.
- Demo (`Demo`): operations «Перевал» and «Сухое русло», only plane 1, node cap 2, branch tier cap 1, crew cap 5; the first clear of «Сухое русло» shows «Конец демо».

## 3. Design

### 3.1 Principle

A tier gives *something new to build with*, not only bigger numbers (Kanta 04.11: buildcraft first). Tier 1 is *simpler, not weaker*: fewer weapon kinds in the card pool, the same hull, speed and course gun as today's start plane. Fewer kinds also means the first cards stack faster, so the first sortie feels strong (Kanta's «кайфовать» principle).

### 3.2 Tier table (*guess* for every number)

| Tier | Оса | Грач | Кит | ★ bonus |
| --- | --- | --- | --- | --- |
| 1 (new) | aam, rockets, flares; wingmen 1 «Стриж» | rockets, bombs, aam, flares; turrets 0; wingmen 1 | bombs, hebomb, turret, flares; turrets max 2; wingmen 1 | 15 % |
| 2 (today's plane 1, unchanged) | + agm | + agm, turret (max 1) | + rockets; wingmen 2 | 15 % |
| 3 (today's plane 2, minus heavy hardpoint) | + srm, agm +5 %, «Грачонок» | turrets max 2 | turrets max 3 | 20 % |
| 4 (future) | heavy hardpoint: laser «Луч», EMP; built-in laser course gun | heavy hardpoint; built-in «Луч» point-defence laser (shoots down missiles) | heavy hardpoint; laser turrets; EMP bomb | 20 % |
| 5 (future) | + railgun on heavy; phase shield during the roll; micro-missile swarm | + railgun, plasma; front energy shield | + plasma; shield dome over wingmen; drone bay | 25 % |

Kept from plane 2 and moved by rule: weapon branch tier 3 needs tier ≥ 3; +1 reroll at tier ≥ 3. Heavy hardpoint and `Weapons.EXP` move to tier ≥ 4; the per-operation gate `EXP_OP` is replaced by the tier (tier 4 itself already needs operation 3).

Hull, speed and turn stay the class values on all tiers in stage A. Per-tier stats (e.g. a slower piston Кит 1) are a later balance item, measured, one package per build.

### 3.3 Unlock (*guess*)

| Tier | Parts | Crew lvl | Campaign gate | Demo |
| --- | --- | --- | --- | --- |
| 1 | free | — | — | yes |
| 2 | 20 000 | 2 | «Перевал» cleared | yes, last playable |
| 3 | 50 000 | 4 | «Сухое русло» cleared | visible, locked |
| 4 | 120 000 | 8 | «Крепости» cleared | visible, locked |
| 5 | 250 000 | 12 | «Небо над Шахрисангом» cleared | visible, locked |

Prices are Kanta's (06.11 18:19 UTC): tiers 2–5 = 20 000 / 50 000 / 120 000 / 250 000. At ~14 k a sortie: ≈ 1.5 / 3.5 / 8.5 / 18 sorties. Crew levels and gates are *guess*. Demo (Kanta Q4): tier 2 is the last playable one, tiers 3–5 visible and locked; demo node cap stays 2.

### 3.4 Nodes per tier (Kanta 06.11: «оставляем как есть, подумай над разными узлами для уровней… базовые на начальных, потом композитные материалы, мощность энергоустановки»)

Each tier keeps its own nodes from zero (unchanged rule). New: each tier has its *own node catalog*, one generation of hardware. The six hangar places stay (frame, engine, armor, wing, pylons, tank) plus two new ones, avionics (tier ≥ 3) and power plant (tier ≥ 4); a later tier swaps a node for an advanced version in the same place.

Rules (all numbers *guess*):
1. Node count and cap grow: tier 1 — 4 nodes (frame, engine, armor, pylons), cap 3; tier 2 — today's 6, cap 4; tier 3 — 7 (+ avionics), cap 5; tiers 4–5 — 7 (tank and wing fold into engine, + power plant), cap 5.
2. From tier 3, the top level of every node adds a combat rule, not a percent (precedent: «Узлы подвеса» lvl 2 opens the third group).
3. Future nodes feed future systems: without the power plant lasers and shields run on base numbers.
4. Tier 4 «Тяжёлый подвес» node lvl 1 opens the heavy hardpoint (so the experimental weapon is something you build toward on the plane).
5. Price ladder stays 160 / 500 / 1 200 / 2 800 / 5 800 × tier factor 0.5 / 1 / 1.25 / 1.5 / 2. One class, everything: nodes ≈ 380 k + planes 440 k ≈ 59 sorties at 14 k (today ≈ 12); later operations pay more (Ас ×2.2), real count lower — check in logs.

| Place | Tier 1 | Tier 2 (today's 1) | Tier 3 (today's 2) | Tier 4 | Tier 5 |
| --- | --- | --- | --- | --- | --- |
| Frame | riveted: roll/afterburner cd −4 % | −4 % (today) | composite: −4 %, hull +2 %; top: roll i-frames +0.3 s | low-observable: enemy missiles lock 6 % slower; top: AA sites fire less at you | metamaterial: Оса 5 phase shield longer; top: 1 hit per 20 s passes through |
| Engine | first jet (Кит: piston): speed +2 % | jet +2 % | afterburning: +2 %, afterburner +10 %; top: 2 s afterburner without fuel | thrust vectoring: speed +2 %, turn +2 %; top: hard turn keeps speed | adaptive: speed +2 %, tank +6 %; top: 3 s free afterburner after a roll |
| Armor | plates: hull +5 % | +5 % | composite: +5 %, AA damage −3 %; top: card repair +20 % | ceramic: +6 %; top: first hit per 20 s halved | active protection: +6 %; top: shoots down 1 missile per 15 s |
| Wing | — | turn +3 % | high-lift devices: +3 %; top: turn radius −10 % | new profile: +3 %, speed in turns +2 % | in engine |
| Pylons | pylons: +4 %; lvl 2 third group | +4 % (today) | multi-ejector racks: +4 %, reload −2 %; top: +1 missile per salvo every 10 s | heavy hardpoint: lvl 1 opens it, then EXP damage +6 % | internal bay: +4 %, reload −3 %; top: second heavy hardpoint |
| Fuel | — | tank +8 % | drop tanks: +8 %; top: tanker comes 30 % earlier | in engine | in engine |
| Avionics | — | — | radar: lock range +5 %; top: off-screen target marks | AESA: +5 %, missile turn +4 %; top: missiles retarget on their own | network: wingmen +6 % on your target; top: wingmen share your sight |
| Power plant | — | — | — | power plant: laser damage and shield HP +8 %; top: second shield charge | compact reactor: +8 %, future-system cooldown −4 %; top: shield and laser at once |

Why tier 1 still makes you want tier 2 (Kanta Q3 «разница всё равно должна быть»): 3–4 weapon kinds instead of 4–5, 4 nodes instead of 6, node cap 3 instead of 4 (armor +15 % instead of +20 %), Кит one wingman instead of two; hull, speed and ★ at start equal today's start plane. A fresh next tier is weaker than a maxed previous one (fresh tier 3 has 14 % less hull than maxed tier 2) but carries more weapons, ★ 20 % and a higher ceiling; optional per-tier base step (hull +6 %, speed +3 %) decided after measurement.

**Top-level rules, tiers 3–4, rework (Kanta 06.11 18:41 «перки 3 и 4 ступени в доработку», read as the top rules of tiers 3 and 4).** The first draft had one rule per node, several invisible in battle (tanker earlier, off-screen marks, repair +20 %). Now each node's top level offers a free-to-switch choice of two rules, each tied to a build archetype (`balance/archetypes.gd`), so the hangar becomes part of the build. Missile-leaning rules are capped at 3 of 14 on different nodes (lesson of 04–05.11: missiles must not become the default again). Full list with numbers (*guess*) on the Kanta page https://claude.ai/artifact/DNzimPAoYKaGTpqc6q7cpt, section «Потолок узлов на ур. 3 и 4». Tier 3: composite frame (post-roll +25 % dmg 2 s | below 30 % hull roll cd ×0.5), afterburning engine (gun +30 % on afterburner | missiles reload ×2 on afterburner), composite armor (ram ×3 / take ×0.5 | +8 % hull per 40 kills), high-lift wing (turrets and wingmen +20 % in hard turns | hard turn breaks missile lock once per 12 s), multi-ejector racks (+1 missile per salvo every 10 s | bombs drop a second half-damage series), drop tanks (tank +20 %, parts +5 % | tanker repairs 15 %), radar (wingmen +20 % on your target | first enemy missile per 20 s misses). Tier 4: low-observable frame (3 s silent: AA loses lock, next salvo +50 % | decoy left by a roll once per 15 s), thrust vectoring (double-tap roll = 180° turn in 0.6 s, cd 12 s | 2 s full afterburner → shock wave on small planes), ceramic armor (20 % of enemy bullets ricochet | first hit per 20 s halved and AA −15 %), new wing (hard turn keeps speed | dive ×2 longer, ground dmg +30 % in it), heavy hardpoint (EXP reload −20 % | EXP dmg +30 %, reload +15 %), AESA (all missiles retarget | enemy missiles within 400 px of you and wingmen turn 30 % worse), power plant (shield survives two breaks | laser triple pulse every 10 s). Before code: equal-value check per pair on typical weapons and a stacking check for degenerate builds.

Code: `PlaneTiers.NODES[tier]` = ordered list of node ids per tier, `NODE_DEF[id]` = title, step effects, cap, top rule; `Profile` stores nodes per tier (`nodes_t1`…`nodes_t5`); `Profile.apply_nodes` reads effects from the table instead of the six fixed lines (profile.gd ~905). Top-level rules are each a small hook with a unit test.

### 3.5 Hangar

- Plane tab: a strip of 5 tier cards per class (model render or silhouette, tier number, «есть / купить — цена / нужно: …»). The player flies any tier they own (`plane_sel` becomes 1–5). The current single «МОДЕРНИЗИРОВАТЬ» button becomes «Купить — цена» on the next locked card.
- Tiers 4–5 in the demo: card visible with the concept silhouette and the list of its future systems, button «В полной игре».
- Until a tier's model exists, the card and the battle use the nearest existing model with the note «модель в работе» (tier 1 → tier 2 model, tiers 4–5 → tier 3 model), so code does not wait for art.

### 3.6 Save migration

Profile version bump. Old plane 1 → tier 2, old plane 2 → tier 3 (`nodes`/`nodes2`, `kit1`/`kit2`, `decals1`/`decals2` move with them; with question 1 = «carry over», nodes take the max of both). Every existing save gets tier 1 free and keeps its selected plane. Testers who flew plane 2 lose the heavy hardpoint until tier 4 (that is Kanta's decision; say it in the build's «Что нового»).

## 4. Code shape

- New pure-logic file `game/scripts/balance/plane_tiers.gd` (`class_name PlaneTiers`): `MAX := 5`, `UNLOCK` (parts, crew, op gate per tier), `DEMO_MAX := 3`, `NODE_CAP`, `MODEL` (tier → model id with fallback), `heavy(tier)`, `exp_pool(cls, tier)`, `can_buy(...)` as a pure function over plain values, so it is unit-tested without the profile.
- `PlaneClasses.PLANES` keyed 1–5; `plane()` and `bonus_k()` clamp to 1–5 instead of 1–2.
- `Profile`: `plane2: bool` → `tiers` (owned, tier 1 always), `plane_sel` 1–5, `nodes_t1`…`nodes_t5`, `kit_t1`…`kit_t5`; `can_buy_plane2` / `buy_plane2` → `tier_lock(c, t)`, `can_buy_tier(c, t)`, `buy_tier(c, t)`; `--plane=1..5`.
- **As built (stage A, 06.11):** `Profile.tier(c)` is the tier (game rules); `Profile.plane_lvl(c)` and `Player.plane_lvl` stay the *model generation* (1 or 2, `PlaneTiers.model`), so every art path keyed `<cls>_<n>` (PlaneArt, WeaponModels, Hangar3D, Livery, WingMech, title flight) works unchanged; `Player.tier` and `cls["tier"]` carry the tier. Stage B switches `PlaneTiers.MODEL` to the new `_t1` / `_t4` / `_t5` keys. Decals stay per model (`decals1` / `decals2`): they sit on the model surface.
- Every `plane_lvl == 2` rule became a tier rule: heavy hardpoint `PlaneTiers.heavy` (tier ≥ 4), branch tier 3 and +1 reroll at tier ≥ 3, telemetry `plane_lvl` = tier; run log column `plane2` → `plane_tier`.
- Nodes: places stay the ids (`frame`, `engine`, `armor`, `wing`, `pylons`, `tank`, `avionics`, `power`), each tier has its own titles and effects (`PlaneTiers.NODES`); a node whose step is not wired yet shows «в работе» and is not sold (tier 3 radar, most tier 4–5 nodes; partly-wired steps name the part in work).
- Model paths built as `"%s_%d" % [cls, lvl]` today (3D thread, 06.11): `hangar3d.gd:878`, `title_flight.gd:151–153`, `self_check.gd:335`, `render3d.gd:658/672` (sprite basename); `PlaneArt` reads `res://art/planes/<cls>_<lvl>.png` for slot points. All go through `PlaneTiers.MODEL`. Agreed names: `fh_battle_<cls>_t1|t4|t5`, `fh_hangar_<cls>_t1|t4|t5`, sprite `<cls>_t1.png` etc.; `_1` / `_2` stay as tiers 2 / 3. The 3D thread ships each model with its top-down sprite and `WING_PAIR` / `OUTER_PAIR` entries if needed; order tier 1 trio → Грач 4 → the rest; dates wait for Kanta's «да» on the sources page https://claude.ai/artifact/47ZGcWwvu5L34zKzenkAZB.
- **As built (stage B, 07.11):** the model generation is a String key, `PlaneTiers.MODEL = ["t1", "1", "2", "2", "2"]` (`OWN_MODEL` marks tiers 4–5 as borrowing «2»); `Profile.plane_model(c)` / `Player.plane_model` replace `plane_lvl`, every art path goes through `PlaneTiers.art_key(cls, key)`. Decals: `decals1` / `decals2` keep their names, the t1 model gets `decals_t1` (`Profile.decal_key`), no profile version bump. Every per-model table has `_t1` rows measured on the t1 GLBs, and `tests/model_tables_test.gd` fails when a model key in `MODEL` lacks its files or a table row. Adding t4 / t5: ship the GLBs, sprite, `fh_mech_` / `fh_ins_` files, fill the rows the test names, then set `MODEL[3..4]` and `OWN_MODEL`.
- `Demo`: `tier_ok(t)`; texts in `Demo.OPENS` and `Campaign.OPS[*].opens` updated (no more «Самолёт ур. 2 … тяжёлый подвес»).
- Player text through `.po` keys (ru source, en, zh_CN).

## 5. Stages

| Stage | What | Needs | Checks |
| --- | --- | --- | --- |
| A — tiers in the game (demo-critical) | `PlaneTiers`, profile + migration, `PLANES` 1–5 with tier 1 kits, unlock rules, hangar strip, demo gating, texts. Tiers 1, 4, 5 on fallback models | Kanta's «да» | TDD for `PlaneTiers` and migration (`unit.sh`); `smoke.sh all`; `full.sh` once (cards and hardpoints change) |
| B — tier 1 models | wire `fh_battle_<cls>_t1` + hangar twins, mount points, icons | 3D thread PT-03 | `--visual` frames of all three, smoke |
| C — tiers 4–5 playable with today's mechanics | heavy hardpoint on tier ≥ 4, EXP per tier as in 3.2, ★ 20/25 % | stage A | smoke, full, bot run per class on tier 4 (method agreed with Kanta first) |
| D — future systems (PT-05), one PR each, each behind an F1 toggle until Kanta's «ок» (R-22) | order: «Луч» point-defence (Грач 4, pilot model) → laser course gun (Оса 4) → laser turrets + EMP bomb (Кит 4) → front shield (Грач 5) → phase shield in the roll (Оса 5) → shield dome over wingmen (Кит 5) → micro-missile swarm (Оса 5) → drone bay (Кит 5) | stage C; tier 4–5 models from PT-02 | per system: brainstorm note, unit tests for its numbers, frames page, measurement before numbers become rules |

Stage A size: ~600–900 lines over ~20 files, so it is one feature branch with 2–3 PRs (data + profile + tests; hangar UI; demo and texts). Stage A should land before the demo build review (18.01, `docs/demo-next-fest.md`), ideally by end of November so testers see it in an s-build.

## 6. Risks

- Save migration breaks testers' profiles → unit test on a copy of a real s16 profile, plus a backup of the old save on first load (`user://profile.bak`).
- 23 scripts read the plane level → grep `plane_lvl|plane2|nodes2|kit2|decals2|PLANE2` must be empty of `== 2` checks after stage A.
- Tier 1 with fewer weapon kinds could feel thin by minute 10 → check the card offers in the bot run: no empty «Э+ only» stretches before 8:00.
- Demo length grows with tiers 2–3 → that is the point (a goal in the demo), but the «Конец демо» screen text changes.

## 7. Open questions for Kanta (numbered, with recommendation)

1. Nodes between tiers: (1) each tier from zero, as plane 2 today; (2) nodes carry over and the cap grows with the tier — **recommended**; (3) half carries over.
2. Prices and gates in 3.3: (1) as in the table — **recommended**; (2) cheaper (tier 3 at 30 000, tier 4 at 80 000, tier 5 at 150 000).
3. Tier 1: (1) simpler, not weaker — fewer weapon kinds, same hull, speed and ★ 15 % — **recommended**; (2) also weaker by numbers (★ 10 %, hull −10 %), to feel the jump to tier 2.
4. Tier 3 in the demo: (1) opens after «Перевал» with crew 4 and 50 000, so it is reachable before «Конец демо» — **recommended**; (2) after «Сухое русло», i.e. only after the demo's end screen.

**Kanta's answers 06.11 18:05 UTC:** 1 — keep «each tier from zero», design distinct nodes per tier (3.4); 2 — prices 10 000 / 35 000 / 60 000 / 115 000 / 200 000; 3 — yes, but tier 1 must still differ enough to want tier 2; 4 — «ур. 2 открывается после 2 этапа Перевала и на нем играем до конца» (demo ends on tier 2).

## 8. Settled 06.11 18:19 UTC (was: to confirm)

1. **Settled: tiers 2–5 = 20 000 / 50 000 / 120 000 / 250 000.** Was: five prices for four purchases: (1) tiers 2–5 = 10 000 / 35 000 / 60 000 / 115 000, 200 000 for something he names — working reading; (2) tiers 2–5 = 35 000 … 200 000, 10 000 = tier 1 of the second and third class.
2. **Settled: «этап» = operation; read as tier 2 opening after the first clear of «Перевал», then «Сухое русло» is flown on it to the demo end.** Was: «2 этап Перевала» (operations have no stages in code): (1) after the first clear of «Перевал» — working reading; (2) after the second clear; (3) after «Сухое русло».
3. Node design 3.4: «да» or edits.
