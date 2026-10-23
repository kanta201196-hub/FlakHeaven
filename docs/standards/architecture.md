# Flak Heaven architecture

Version 1, 2026-10-23. Produced with the `engineering:architecture` skill from the [code review of 2026-10-23](../review/code-2026-10-23/README.md). Describes **how the game is built today**, where to take it, and the decisions behind that (ADRs at the end). Coding rules — [code.md](code.md); UI — [ui-design-system.md](ui-design-system.md).

## 1. Constraints that shape the architecture

- **Godot 4.4.1, GL Compatibility** — for Steam Deck, weak PCs and Mac. No compute shaders, at most 8 lights per mesh, shaders compile on first draw.
- **Bullet heaven:** dozens of air enemies (cap `enemy_cap` = 70), hundreds of projectiles, 15-minute sorties.
- **Most code is written by Claude agents** in separate threads with no shared memory. Rules must be simple, checkable and written down; coupling must be explicit, because an agent only knows what it has read.
- **Deadlines:** Next Fest demo by 2026-12-15, Early Access after. No big rewrites "for cleanliness" — improve along the way.

## 2. How it works today

### 2.1. Layers

```
Autoloads (live for the whole game)
  InputSetup — input actions · Tuning — balance parameters (F1) · Settings — player settings · Profile — progression, hangar

Static modules (class_name + static var/func, no nodes)
  Campaign, Story, Hints, Demo, Loc, Prog, PlaneClasses, Cards, Weapons, Biome …

Main (Node2D, main.tscn) — root, Main.I
├─ UI (CanvasLayer): Hud (+ HudFlight / HudScreens / HudHangar / HudCampaign / HudCodex / HudMinimap),
│                    Menu, TuningPanel (F1), ReportPanel, Sfx, Camera2D
├─ world (Node2D, recreated every sortie)
│    Background, Clouds, Pickups, Spawner, Player, Projectiles, Fx, enemies and targets (Enemy and subclasses)
├─ Render3D (Node3D) — 3D mirror of the world: top-down camera, Terrain3D, models, shadows, clouds, Boom3D, lights
└─ Hangar3D — hangar plane model (own SubViewport)

Main helpers (RefCounted with field m): MainInput (input and clicks), MainDebug (autotest, screenshots), RunLog, Telemetry
Player helpers (RefCounted): PlayerFlight, PlayerGuns, PlayerSkills, PlayerDraw, Hardpoint (weapon mounts)
```

### 2.2. Core idea: logic in 2D, picture in 3D

All game logic lives in 2D (pixels, `Vector2`): flight, projectiles, hits, spawning. Every frame `Render3D` mirrors it into 3D with `(x, y) → (x, height, y)`; the combat plane y = 0 matches 2D pixel for pixel, so bullets and UI stay 2D. This is a good decision: logic is simple and deterministic, the autotest runs without a GPU, and visuals change without touching rules.

### 2.3. Data and owners

| Data | Owner | On disk |
| --- | --- | --- |
| Progression, hangar, crew | `Profile` | `user://profile.json` (atomic write) |
| Player settings | `Settings` | `user://settings.json` |
| F1 balance parameters | `Tuning` | `user://tuning.json` (volume is written there too — a bug) |
| Campaign, hints | `Campaign`, `Hints` | `user://campaign.cfg`, `hints.cfg` |
| Sortie state (level, XP, parts, cards) | `Main` (fields) | not saved |
| Reports and sortie rows | `ReportPanel` | queues in `user://`, upload to a Google Sheet |

### 2.4. How parts talk

- **Service locator `Main.I`:** 657 uses in 46 files. Entities get the player, projectiles, effects, sound and telemetry through it — and **write sortie fields directly** (`m.parts += …`, `m.pending_levels += 1`).
- **View singletons** `Render3D.I`, `Boom3D.I`, `Hangar3D.I`; 2D logic sometimes calls `Render3D.I` (dependency in the wrong direction).
- **Groups** (`enemies`, `allies3d`) and duck typing (`get("…")`, `call("…")`).
- **Almost no signals** (zero in combat); timers are `float -= delta`.
- **UI is immediate mode:** every frame `_draw` redraws everything and rebuilds a button list `[Rect2, "action:param"]`; click → `Main.ui_click(action)` → string parsing in `MainInput`.
- **Game state is a string** `Main.state` (`menu`, `playing`, `levelup`, `course_pick`, `paused`, `dead`, `evac`, `hangar`, `campaign`, `codex`, `settings`).

## 3. Assessment

### What works and stays
1. 2D logic separated from the 3D view (§2.2).
2. Node-less projectiles: arrays + one `_draw`/MultiMesh; segment-based hits; fire rate independent of FPS.
3. Deterministic timers — the fixed-step autotest and `--turbo` are reproducible.
4. MultiMesh for mass objects, enemy model pool, background terrain build with a generation counter.
5. Atomic profile write, purchases through `can_*`/`*` pairs, demo mode in one place (`demo.gd`).
6. Telemetry and the `l7` log from real PCs — the basis for performance and balance decisions.
7. Everything is built in code — easier for agents than editing `.tscn`.

### Where the architecture hurts (from the review)
| Problem | Risk | Example |
| --- | --- | --- |
| Sortie state spread out: 46 files write it | Card-offer rule repeated in 4 places → screen with no exit | CR-02 |
| Mechanics keyed on Russian strings | A typo breaks balance with no error | enemy armor, bonuses |
| One rule in several places | S10-13 had to be applied in two places by hand | rewards, `_die` |
| No shared save layer | Profile can be lost; tests corrupt the developer's profile | CR-03 |
| No per-frame enemy list or shared grid | 45 `get_nodes_in_group` calls in combat, no headroom | performance |
| God files and reading other classes' `_fields` | A change in one place silently breaks another | `render3d.gd`, 2565 lines |
| Screen state as a string with no transition table | Screen with no exit; gamepad input collides with combat | CR-02, CR-05 |
| Launch flags read in 34 places | Cheats in tester builds, per-frame garbage | code.md §11 |

## 4. Target architecture (step by step)

Principle: **extract along the way, don't rewrite**. Each step is a separate small task (CS-…) that fits into a build cycle next to other changes.

```
Autoloads:       InputSetup · Settings (+ report consent) · Profile · Tuning (F1 only) · DebugFlags · SaveIO (functions)
Main             — node assembly and state transitions (transition table), nothing else
RunState         — sortie state and its operations: add_xp, grant_parts, grant_rare_pick, refill_offers, award_activity
Sortie services  — Projectiles, Fx, Sfx, Telemetry, EnemyRegistry (per-frame enemy list + grid)
Entities         — read RunState, call services, report events via signals (died, reward_granted)
View             — Render3D split into UnitViews / VehicleParts / GroundMarks / CrashFx; logic sees a narrow View interface
UI               — Hud + Menu on shared UiStyle/HudKit primitives, gamepad focus model
```

### Steps (backlog tasks)

| # | Step | Gain | Size |
| --- | --- | --- | --- |
| CS-01 | Type warnings: enable as warnings, clean up, raise to errors | Agents cannot write untyped code | medium, in parts |
| CS-02 | `SaveIO`: atomic write, `.bak`, recovery, version and migrations, test folder override; `custom_user_dir_name` | Closes CR-03, tests stop corrupting profiles, demo → full game transfer | medium |
| CS-03 | `RunState` out of `Main` fields; writes only through methods; one `refill_offers` | Closes CR-02 and duplicated rewards | medium |
| CS-04 | `EnemyRegistry`: one enemy list per frame + hit grid | Performance headroom, −45 group scans | medium |
| CS-05 | `DebugFlags`: flags read once, cheats only in debug | No cheats in builds, less per-frame garbage | small |
| CS-06 | Ids instead of Russian strings: damage source, weapon kind, state, button action | Translation and renames cannot break balance | medium |
| CS-07 | Python: `pyproject.toml` with ruff, `requirements.txt` | One style for tools | small |
| CS-08 | CI: `pick.sh` "all combat except list", smoke catches `ERROR:`/`SHADER ERROR`, `check_po` and `.gd` tools in smoke; tests in a temp `user://` | Checks stop letting errors through | small |
| CS-09 | Combat preload: operation models in the background, `Boom3D` and materials warmed up at sortie start | No hitches in the demo's first session | medium |
| CS-10 | Split `render3d.gd`; unit records become a `UnitView` class; private fields closed | Safe visual changes | large, after the demo |
| CS-11 | `UiStyle` and shared UI primitives, gamepad focus model | Closes CR-05, Steam Deck | large, in parts |

Recommended order before the demo: CR bugs → CS-05, CS-08 (small) → CS-02, CS-03 → CS-09, CS-11 (focus and input delay) → the rest after Next Fest.

## 5. Decisions (ADR)

### ADR-01. Logic in 2D, picture in 3D
**Status:** accepted (since 3.0, plan `docs/sprint1/s3-3d-cloud-plan.md`). **Recorded:** 2026-10-23.
**Context:** we needed depth and terrain, but rules, the GPU-less autotest and balance were already 2D.
**Decision:** logic stays 2D; `Render3D` mirrors it into a 3D scene with a top-down camera.
**Consequences:** + deterministic autotest, visuals change without touching combat rules. − Anything logic needs from the terrain goes through inverse projections; the 3D → 2D link must be a narrow interface (`View`), not `Render3D.I` from logic.

### ADR-02. Keep the `Main.I` service locator, with rules
**Status:** proposed. **Decides:** Kanta (code structure, not game rules — can be accepted together with the standard).
**Context:** 657 uses; a full move to signals and dependency injection would take weeks before the demo.

| Option | Complexity | Risk | Benefit |
| --- | --- | --- | --- |
| A. Rewrite to signals and explicit dependencies | high | regressions before the demo | maximal, but too late |
| **B. Keep `Main.I` for reads and services; writes only through methods; sortie state in `RunState`** | low, incremental | small | fixes real bugs (CR-02, duplicated rewards) |
| C. Change nothing | none | bugs repeat | none |

**Decision (B recommended):** reads and service calls through `Main.I` are allowed; writing `Main` fields from other code is forbidden; new sortie state goes to `RunState`; events with several listeners are signals.
**Consequences:** + incremental, no big rewrite; + `RunState` can be unit-tested without a scene. − Coupling through a global access point remains.

### ADR-03. Projectiles and mass effects are data, not nodes
**Status:** accepted de facto, now recorded. Arrays + one `_draw`/MultiMesh, a cap on every pool. Next step if the Deck runs short on CPU — packed arrays (`PackedVector2Array`/`PackedFloat32Array`) instead of dictionaries; decide from `perf.gd` logs, not in advance.

### ADR-04. Where balance numbers live
**Status:** awaiting Kanta's decision. Options and recommendation — [code.md §5](code.md). After the decision — a decision-log line in `docs/game-context.md` and a CLAUDE.md rule update.

### ADR-05. UI is drawn in code (immediate mode), not with Control nodes
**Status:** accepted de facto, recorded with conditions.
**Context:** Godot offers Control + Theme (gamepad focus out of the box). All our UI is drawn in `_draw`.

| Option | Pros | Cons |
| --- | --- | --- |
| A. Move to Control + Theme | focus, anchors, Theme Type Variations | rewriting ~3800 lines of UI before the demo is unrealistic |
| **B. Keep drawing in code + own focus model + `UiStyle`** | incremental, look unchanged | focus and layout are ours to write |

**Decision (B recommended):** B until Early Access. New complex forms (text input, long scrolling lists) may use Control, like the report form. Revisit after Next Fest.

### ADR-06. Player data is uploaded only with consent
**Status:** decision DM-07 already exists ("report with player consent"); the code does not match it (CR-04). Technically: a consent flag in `Settings`, off by default outside tester builds; a separate receiver URL, or none, in demo and release.

### ADR-07. Saves through one layer
**Status:** proposed (CS-02). One `SaveIO` module for every `user://` file: atomic write, `.bak`, version, migrations, test folder override. The `user://` folder does not depend on the project name. The file list is ready for Steam Cloud.

## 6. Revisit later

- After Next Fest: ADR-05 (Control + Theme for menu and hangar), CS-10 (split `render3d.gd`).
- If the Steam Deck is CPU-bound — ADR-03 next step (packed arrays, RenderingServer for projectiles).
- Logic tests (TDD for damage and XP formulas) — GUT 9.4.0 or gdUnit4 5.x (both support 4.4); choose with the first TDD task.
