# Нагорье relief stage 3: landforms (RV-04)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three landforms that the region noise (RV-01) and the gullies (RV-02) cannot give, so a flight crosses recognisable places, not only "more mountains": lone rock pillars and buttes (hoodoos), river terraces (benches stepping up from the valley), gorges (stretches where the valley narrows between steep walls).

**Decision:** Kanta, 2026-10-24 19:15, thread «Разнообразить рельеф Нагорья»: «Почему ты не хочешь переходить к этапу?» → stage 3 «формы земли». Frames first, then wiring (same as RV-01/RV-02).

**Architecture:** all three live in `ReliefProvinces.relief()` (pure, per point, worker-safe), numbers in `balance/relief.gd`, one F1 slider `relief_landforms` (0 — as after RV-02) and `--landforms0` for frames. No new assets; the ground shader already paints rock by the relief rock mask (`rock` output).

## Constraints (do not break)

- Valley floor `|v| ≤ D_FAN − 40` untouched: river, road, fields, villages, streams, settlement flats, AA sites (`flat_at`, `find_floor`), convoy.
- Heights stay in `0 … ceiling`; pillars never reach the combat plane (cap ≤ 0.85 of the ceiling).
- Chunk build cost: at most +15 % over RV-02 (pillars are one cellular noise lookup, terraces and gorges are arithmetic on values already computed).
- Snow, mesas, gullies keep their look outside the new landforms.
- Fictional world, no real places.

## Landforms

1. **Pillars and buttes** (mesa regions, dry hills): cellular noise with ~1600 px cells; a cell gets a pillar with chance ~25 % (hash of the cell). Pillar: radius 60–160 px, height 0.25–0.6 of the ceiling, near-vertical wall (smoothstep over ~25 px), flat or slightly domed cap, scree skirt at the foot, rock mask on the wall. Only at `a > D_FAN + 250` and not on mesa tops above the first ledge (would read as noise).
2. **River terraces** (hills and mid mountains, where the bank is gentle): between `D_FAN` and the slope start, the rise is redistributed into 1–2 flat benches (treads) with short risers, tread level wobbling along the river (noise). Steep banks (high ranges, mesas) have none.
3. **Gorges** (any region except hills): along the river a slow noise marks stretches of ~2–5 km; there the slope run on both banks shrinks to ~35 % and the crest rises, so the valley walls stand close and steep above the same floor. Rock mask on the walls, gullies stay.

## Tasks

### Task 1: Prototype by hillshade
- [ ] Add the three terms behind a flag in `ReliefProvinces.relief()`; numbers in `ReliefBalance` (`PILLAR_*`, `TERRACE_*`, `GORGE_*`).
- [ ] `relief_dump` + `shade.py` on areas a/b and a mesa area; compare with `--landforms0`.

### Task 2: Frames for Kanta
- [ ] GL frames (`--op=1`) before/after at fixed points: a pillar field, terraces on a hill river, a gorge, plus the usual high/mid/hills points to show nothing else changed. Large, zoomable, on the gallery page.

### Task 3: Tests (test-driven where it is logic)
- [ ] Floor untouched with landforms on; heights in range; pillars stay under 0.85 of the ceiling; pillar share of area 1–6 %; terraces have flat treads (share of near-flat ground in the terrace band grows); gorge stretches cut the slope run (mean slope near the river grows) and exist on 10–30 % of the river length.
- [ ] `unit.sh`, `smoke.sh all`, `aa_site_test` (sites still found, not by water), chunk cost measured.

### Task 4: PR, review, merge; gallery and backlog.

## Risks
- Pillars next to the AA search ring: `flat_at` rejects them (steep), fine; a pillar right over a road: excluded by `a > D_FAN + 250`.
- Gorges narrow the view of the floor from the camera tilt: check frames at combat zoom.
- Terrace treads may look like flat «tables» again (Kanta 24.10 dislikes dead-flat): treads keep a little roll (like mesa ledges).
