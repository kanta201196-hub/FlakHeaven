# Deeper upgrades, stage 1 (PG-01) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** third hardpoint group (hangar node «Узлы подвеса» lvl 2), three new standard weapons (`srm`, `agm`, `hebomb`) and a course gun choice (`std`, `twin`, `heavy`).

**Architecture:** data in `Weapons.DEFS` / `PlaneClasses.DATA`, numbers in new `balance/weapons.gd`, firing of new weapons in new `weapon_fire.gd` dispatched from `Hardpoint.update`; third group appended after turrets/heavy so existing group indices never shift.

**Tech Stack:** Godot 4.4.1, GDScript, GL Compatibility; Blender-by-code models in `game/tools/model_lab/`.

**Spec:** [../specs/2026-10-24-progression-depth-stage1-design.md](../specs/2026-10-24-progression-depth-stage1-design.md)

Status: **planned 2026-10-24**. Executor: thread «Углубить прокачку для демо». Branch `claude/project-thread-akm2rs`, one PR. **Merge only after GD-02 and GD-03 are in a build** (Kanta 24.10, answer 4a).

## Global Constraints

- Fictional world: no real weapon or aircraft names in code, assets, strings (CLAUDE.md rule 1).
- English for identifiers, comments, docstrings; player text in Russian source strings through `Loc.t`, entries in `game/locale/en.po` and `zh_CN.po`.
- `##` docstring for every new or changed class and public function (`docs/standards/code.md` §2).
- Group indices 0–1, turrets and heavy hardpoint keep their indices; the third group is appended last.
- New profile keys added in `Profile._default_class`, or load drops them.
- Numbers from the spec tables are starting points; any change after the balance run goes "before → after" in the PR.
- Every new model and the hangar screen go to Kanta as large frames on a page where each opens full screen with zoom (rule 24.10), before merge.

## Review Focus

1. Saves from the current build (no `gun`, `guns` keys; pylons 0–5) load without errors and behave as before when pylons < 2.
2. Card ids `new_<w>_<gi>` / `up_<gi>` and `start2` with the third group present and empty.
3. «Кит» bomb bay doors and manual bomb aim with `hebomb` in the bay vs on the wing.
4. `gun_ap` vs armor and agile, and «Дятел» every-4th shot with `twin` (rate 1.6) — no runaway DPS.
5. Demo caps (`Demo.node_cap()` = 2): third group reachable in the demo.

## Tasks

### Task 0 — Environment and baseline
- [ ] Download Godot 4.4.1 headless into `/tmp/claude-0/godot` (cloud has none preinstalled), `export GODOT=…`.
- [ ] `tools/ci/unit.sh`, `tools/ci/smoke.sh fighter` on `main` — green before changes.
- [ ] Balance baseline: right before merge, on `main` with GD-02/03 merged: `OPS="1 2" PAR=2 RUNS=6 tools/ci/balance.sh` (`setsid nohup`, ~1 h).

### Task 1 — Weapon data, balance numbers, class lists (TDD)
Files: `game/scripts/weapons.gd`, new `game/scripts/balance/weapons.gd` (`WeaponBalance`), `game/scripts/plane_classes.gd`, `game/scripts/prog.gd` (`WEAPON_TAGS`), `game/scripts/cards.gd` (missile-module checks), new `game/tests/progression_test.gd`.
- [ ] Failing tests: `PlaneClasses.allows("fighter","hebomb") == false`, `allows("bomber","agm")`, `allows("attacker","srm")`; `Weapons.POOL` has the 3 ids; `Weapons.is_bomb("hebomb")`; `WeaponBalance.dmg_k("srm", 3) == 1.5`, `cd_k("agm", 5)` = 1 − 0.06·4, `range_k("hebomb", 2) == 1.08`; `WeaponBalance.CD_FLOOR["srm"] == 2.0`.
- [ ] Add `DEFS` entries (spec table), `POOL`, `is_bomb()`, `WeaponBalance` (level factors, floors), class lists, tags; module checks count `srm`/`agm` as missiles.
- [ ] `tools/ci/unit.sh` green; commit.

### Task 2 — Profile: course guns and third group (TDD)
Files: `game/scripts/profile.gd`, `game/scripts/balance/weapons.gd` (`GUNS`, `GUN_PRICE`), tests.
- [ ] Failing tests: defaults `gun == "std"`, `guns == ["std"]`; `buy_gun` with too few parts → false and parts unchanged; with enough → owned, parts reduced by price; `set_gun` to unowned → ignored; `third_group(c, lv)` false at pylons 1, true at 2; save → load round trip keeps keys; an old save without the keys loads with defaults.
- [ ] Implement `gun`, `buy_gun`, `set_gun`, `third_group`; pylons node text: lvl 2 step mentions the third group.
- [ ] Unit green; commit.

### Task 3 — Third group in the plane (TDD + smoke)
Files: `game/scripts/plane_classes.gd` (`groups3` per class), `game/scripts/hardpoint.gd` (`mount_frac`), `game/scripts/player.gd` (`setup`), `game/scripts/plane_art.gd` (`slot_points`), `game/scripts/main_debug.gd` or arg parsing (`--group3`).
- [ ] Failing test (pure helper `PlaneClasses.group_defs(cls, third: bool) -> Array`): third=false → same list as today; third=true → today's list + spec group at the end.
- [ ] `Player.setup` appends the group after turrets/heavy when `Profile.third_group` or `--group3`.
- [ ] `slot_points`: `mount_frac` when > 0; belly single slot as today.
- [ ] Screenshot each class from above with `--group3` (frames page). Unit + `smoke.sh all` green; commit.

### Task 4 — Firing of `srm`, `agm`, `hebomb`; defence classes
Files: new `game/scripts/weapon_fire.gd` (`WeaponFire`), `game/scripts/hardpoint.gd` (dispatch, `_dmg`/`reload_time`/`range_px` via `WeaponBalance`, `is_bomb` in bomb aim / trigger), `game/scripts/render3d.gd` (bay doors via `is_bomb`), `game/scripts/enemy.gd` (`src_class`, `DEF_K`, armor hint), `game/scripts/main_debug.gd` (`--weapon=<id>`).
- [ ] Failing tests: `Enemy.src_class("УР В-З") == "ap"`; `src_class("курсовое: крупнокалиберная (авто)") == "gun_ap"`; `Enemy.DEF_K["armor"]["ap"] == 1.3`, `["armor"]["gun_ap"] == 0.8`.
- [ ] `fire_srm`: per slot one `spawn_player_missile` at nearest air target ≤ range, `opts` turn ×1.4, `src` "ракеты ближнего боя" (class `homing`).
- [ ] `fire_agm`: ground targets ≤ range, priority armored > big > nearest, `spawn_player_missile` with `ground_only`, src "УР В-З".
- [ ] `fire_hebomb`: like `_fire_bombs` one bomb per slot, big radius, `Main.I.shake`, src "фугасные бомбы" (class `blast`).
- [ ] Autotest `--weapon=srm` (fighter), `--weapon=agm` (attacker), `--weapon=hebomb` (bomber): no `SCRIPT ERROR`, damage by source shows the weapon in the summary. Commit.

### Task 5 — Course gun variants
Files: `game/scripts/player_guns.gd`, `game/scripts/player.gd` (`gun_variant`), `game/scripts/projectiles.gd` (tracer width by variant), arg `--gun=`.
- [ ] Failing test (pure helper `WeaponBalance.gun_k(id) -> Dictionary`): `twin` rate 1.6 dmg 0.65; `heavy` rate 0.55 dmg 2.0 speed 1.15; unknown id → `std`.
- [ ] `gun_damage`, `gun_rate`, bullet speed and spread use the variant; heavy bullets src "курсовое: крупнокалиберная (авто/ручн.)"; `_lead_dir` uses the variant bullet speed.
- [ ] Autotest `--gun=twin`, `--gun=heavy` per class: summary `gun_rate_max` matches ×1.6 / ×0.55. Commit.

### Task 6 — Models and icons
Files: `game/tools/model_lab/` (new generators), `game/models/weapons/srm_1..3.glb`, `agm_1..3.glb`, `hebomb_1..3.glb`, `game/scripts/weapon_models.gd` (`WEAPON_GLB`), `game/scripts/plane_art.gd` / `card_icons.gd` (icons).
- [ ] Generate, check triangle budget (combat 5–15 k per plane total), frames from the game camera and the hangar; frames page to Kanta; wait for "ок" before merge.

### Task 7 — Hangar UI
Files: `game/scripts/hud_hangar.gd`.
- [ ] Row «Курсовая пушка»: three buttons, owned/selected/price state, buy on click; pylons node card line about the third group. Gamepad focus per `docs/standards/ui-design-system.md`.
- [ ] Frames (RU and EN) on the frames page. Smoke; commit.

### Task 8 — Localization and docs
- [ ] All new strings in `en.po`, `zh_CN.po` (ZH draft marked); `docs/game-context.md` «Правила игры сейчас» updated in the same commit as the merge; backlog PG-01 → «на проверке в следующей сборке».

### Task 9 — Verification and PR
- [ ] `tools/ci/unit.sh`, `tools/ci/smoke.sh all`, `tools/ci/full.sh` once — outputs in the PR.
- [ ] Balance after: same `balance.sh` command on the branch; `balance_table.py <after> --before <before>`; M1–M7 inside corridors, damage share of new weapons reported.
- [ ] PR body: what was checked, before/after table, frames page link. Merge after GD-02/03 are in a build and Kanta's "ок" on models.
