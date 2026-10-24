# Нагорье relief variety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Нагорье relief varied: regions of rolling hills with lone peaks, mid mountains, high sharp snowy ranges, mesas with stepped cliffs over canyons, wide valleys; different slopes on the two banks of one valley (stage 1, RV-01). Then replace the uniform "wrinkle" on slopes with branching gullies and spurs (stage 2, RV-02).

**Decision:** Kanta, 2026-10-24, thread «Разнообразить рельеф Нагорья», option «1, затем 2». Gallery with the draft: https://claude.ai/artifact/4XisXiNvidRLvudgQifPq4

**Architecture:** A new pure class `ReliefProvinces` (no autoloads, unit-testable) owns the low-frequency province noises and returns landform weights and the mountain part of the height for a point. `Terrain3D._relief` keeps the valley floor, river cut, road, streams and settlement flats exactly as now and asks `ReliefProvinces` for what rises above the fan. Everything still runs per point on WorkerThreadPool (chunk build), same seed for the world, infinite map. The Archipelago (`_sea`) keeps its relief untouched.

**Tech stack:** Godot 4.4.1 GDScript, FastNoiseLite, ground3d.gdshader (GL Compatibility now, Forward+ migration in thread «3D-модели по плану Kirill»).

**Draft:** branch `claude/project-thread-8fzulg`, commit "Relief variety spike" (`Terrain3D._relief_prov`, `province()`), lab tools in `game/tools/relief_lab/`.

## Constraints (do not break)

- Valley floor `|v| < D_FAN − 40` keeps today's height, river guard, road band, greens, streams, settlement flats (`_flat`), `find_floor`, `flat_at` behave as now.
- Height stays in `0 … ceiling` (470 px under the combat plane); no relief above `ceiling`. "Higher" comes from contrast with low regions. A deeper ground (`ground_depth`) is a separate test only if Kanta asks.
- Chunk compute cost on worker threads: at most +35 % per sample (draft: 18 → 23 µs). Main-thread cost unchanged.
- `surface_fast`, enemy relief checks, bomb aim and craters work on the new heights without changes (they read the same height grid).
- Fictional world; no new assets.

## File structure

| File | Responsibility |
| --- | --- |
| `game/scripts/relief_provinces.gd` (new, `class_name ReliefProvinces`) | Province noises, `weights(x, z, v) -> Vector4` (elevation class, mesa share, bank asymmetry, hill share), `mountain(x, z, a, v, n) -> Vector3` (height share, rock, scree) for the part above the fan |
| `game/scripts/terrain3d.gd` | Calls `ReliefProvinces` from `_relief` when `relief_style == 1`; old path kept behind `relief_style == 0` for A/B until the build is checked, then removed |
| `game/scripts/balance/relief.gd` (new) | Province numbers: frequencies, height ranges, run lengths, mesa levels (code.md §5) |
| `game/scripts/tuning.gd` | F1 slider `relief_variety` 0/1 (A/B in game) |
| `game/shaders/ground3d.gdshader` | Province tint channel: mesa tops sand, hills steppe-grass tint, snow only in high ranges |
| `game/tests/relief_provinces_test.gd` (new) | Unit tests (below) |
| `game/tools/relief_lab/` | Dump + maps (already in the draft); kept as the before/after tool |
| `game/tools/biome_map/` | Province layer on the placement map |

## Stage 1 — landform provinces (RV-01)

### Task 1: ReliefProvinces with tests

- [ ] Write `game/tests/relief_provinces_test.gd` (extends SceneTree, prints `UNIT:` lines, `FAIL` on error):
  - determinism: same (x, z) → same weights and height twice and on a second instance;
  - ranges: weights in 0…1, asymmetry in 0.55…1.7, height share in −0.03…1;
  - area shares over a 60 × 60 km grid (step 200 px): hills 15–40 %, high ranges 15–40 %, mesas 8–30 %, mid the rest;
  - floor untouched: for `a < D_FAN − 40` the mountain part is 0;
  - regional contrast: std of 4 × 4 km window peaks ≥ 0.08 of ceiling (now 0.04);
  - no wall at a province border: max height step between neighbours 20 px apart ≤ 0.12 of ceiling outside mesa cliffs.
- [ ] Run `tools/ci/unit.sh`, see the tests fail.
- [ ] Move the draft code from `_relief_prov` into `ReliefProvinces`, numbers into `balance/relief.gd`.
- [ ] Run `tools/ci/unit.sh`, tests pass. Commit.

### Task 2: Terrain3D wiring, A/B slider, perf

- [ ] `Terrain3D._relief` calls `ReliefProvinces.mountain` (style 1); F1 slider `relief_variety` rebuilds chunks (`clear()`).
- [ ] Measure chunk compute headless (relief_dump `us_per_sample`, perf log `chunk_ms`) before/after; must be ≤ +35 %.
- [ ] `tools/ci/smoke.sh all`. Commit.

### Task 3: Look — tuning by frames

- [ ] Lab maps 22 × 17 km (step 10) and game frames (`--visual --pts=…`, `--relief0` for "before") at one spot of each province, far and mid zoom.
- [ ] Tune: hills rounder with grass tint and 1–3 lone peaks per 5 km; mesas with 2–3 flat levels and canyon cuts into the plateau; high ranges with main crest lines and snow; wide valleys where hills meet the river.
- [ ] Ground shader: province tint channel (vertex color or UV2.y spare bits — check with the Forward+ thread first), mesa tops not rock-grey, snow only where elevation class is high.
- [ ] Gallery update (full-size frames, fullscreen and zoom — rule of Kanta 24.10). Commit.

### Task 4: Gameplay checks and PR

- [ ] Placement: settlements, AA sites, convoy, scenes of past battles still on the floor (biome_map counts before/after equal ±5 %).
- [ ] Flight: dives keep `relief_min`; bomb aim on mesa tops and cliffs (`bomb_aim_hill` frame).
- [ ] `tools/ci/full.sh` once (combat reads relief). PR with checks pasted, merge after green.

## Stage 2 — branching gullies and spurs (RV-02)

### Task 5: Erosion filter

- [ ] Own implementation of a per-point "erosion filter" (idea: gully stripes aligned with the slope gradient over several octaves, faded toward crests and valley lines; reference write-up blog.runevision.com, 2026). Code written from the description, not ported: the reference code is MPL-2.0 and porting it is a legal question for Kanta.
- [ ] Height gradient from `ReliefProvinces` analytically or by central differences (2 extra samples, cost check).
- [ ] Strength by province: strong in high ranges, medium in mid, weak in hills, off on mesa tops (cliff faces only).
- [ ] Tests: determinism, height range, floor untouched, cost ≤ +60 % over stage 1.
- [ ] Frames before/after, gallery, smoke, full autotest, PR.

## Risks

- Mesa cliffs right above the road may hide the convoy from a tilted camera: check `road_convoy` frames; if needed keep the cliff ≥ D_FLOOR from the river.
- Hills regions lower the average height: more open floor for ground spawns — check spawn counts in the full autotest.
- Forward+ changes the ground shader at the same time: shader edits go through one owner (thread «3D-модели по плану Kirill»); this plan only adds one mask channel.
