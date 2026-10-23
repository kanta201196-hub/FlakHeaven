# Flak Heaven coding standards

Version 1, 2026-10-23. Based on the [code review of 2026-10-23](../review/code-2026-10-23/README.md) (how the code is written today and where it breaks) and on [Godot 4.4 and Python best practices](../review/code-2026-10-23/r6-practices.md) (with sources).

Audience: every Claude and every person who writes code in this repository. CLAUDE.md links here and does not repeat it. Process (branches, PRs, smoke test, full autotest, task size) lives in CLAUDE.md; this file says **how to write the code**.

**How to apply.** Rules are mandatory for new code and for the lines you change. Do not rewrite old code just to match the standard: "touch it, tidy it" within the scope of your change. Items marked **[Kanta to decide]** are recommendations until Kanta decides.

---

## 0. Language (one parameter)

> **CODE_LANGUAGE = English** *(Kanta's decision of 2026-10-23, option 2)*

Everywhere below, "in CODE_LANGUAGE" refers to this parameter. To switch languages, change this one line.

| What | Language |
| --- | --- |
| Identifiers (classes, functions, variables, files, folders) | always English, ASCII only |
| Comments, `##` docstrings, commit messages, PR descriptions | CODE_LANGUAGE |
| Internal documents in `docs/`, plans, specs, backlog, decision log, CLAUDE.md | CODE_LANGUAGE |
| Player-facing strings (translation keys) | Russian phrase as the `.po` key (independent of this parameter) |
| Player and tester documents, website, marketing | the audience's language |
| Chat with Kanta, thread replies | Russian |

Migration: new code and new documents are written in English right away. Existing comments and documents are translated when a file is touched (no mass rewrite), plus a separate pass over key documents (backlog task LANG-01). Why: comments and docs are read mostly by agents, and Cyrillic costs roughly 2–4× more tokens than Latin text (an estimate, not measured). Kanta reads documents through Claude when needed.

## 1. Engine and versions

1. Godot **4.4.1**, **GL Compatibility** renderer. Do not use what 4.4 lacks: `@abstract`, variadic `...args`, `duplicate_deep()` (all 4.5). Typed dictionaries `Dictionary[K, V]` exist in 4.4 — use them.
2. GL Compatibility has no SSAO, SSR, volumetric fog, decals, DOF, TAA, FXAA or compute shaders. It has MSAA, glow, depth and height fog. At most 8 omni/spot lights per mesh — extra lights are silently dropped.
3. Always commit `.uid` files and move them together with their script or shader.

## 2. GDScript: style and documentation

Based on the official Godot style guide. Indent with tabs; lines under 100 characters (under 80 for comments).

| What | How | Example |
| --- | --- | --- |
| File | `snake_case.gd` | `convoy_vehicle.gd` |
| Class | PascalCase `class_name` in every file except autoloads | `class_name ConvoyVehicle` |
| Function, field, variable | `snake_case`, English, meaningful | `pending_levels`, not `pl`, `L`, `k` |
| Constant, enum value | `UPPER_CASE` | `OFFER_COUNT`, `State.LEVELUP` |
| Signal | past tense | `enemy_died`, `reward_granted` |
| Private | `_` prefix — **never read or write it from outside** | `_grid`, `_units` |
| Local variable | short names only in 3–5 line loops (`i`, `e`) | — |

**Member order:** `class_name` → `extends` → `##` class docstring → signals → enums → constants → `static var` → `@export` → fields → `@onready` → `_init`/`_ready`/`_process` → public methods → private methods (`_…`) → inner classes.

**Documentation and comments — in CODE_LANGUAGE (§0).** Today 43 % of functions have a `##` docstring (665 of 1549 in `game/scripts`), full-line comments are about 9 % of code lines, and most existing comments are change history rather than explanation.
- **A `##` docstring is mandatory** for every class (right after `extends`: why the class exists, who creates it, what it talks to) and every public function (what it does, what parameters and result mean, side effects: writes to disk, changes run state, creates nodes). A one-liner is fine when the name and types already say everything.
- **Private functions** get a docstring when longer than ~15 lines or non-obvious.
- **Inline comments explain why, not what:** a game rule, an engine limitation, a bug workaround, a non-obvious number. Balance formulas and thresholds explain their meaning.
- **Non-obvious constants and fields** get a `##` line (Godot shows it as a tooltip in the editor).
- Task or decision id — one reference at the end: `## Air enemy cap (EX-04)`.
- Change history ("was 1 s, now 0.5", "test 3.5-s7, Kanta") goes to the commit message and the decision log in `docs/game-context.md`, **not into code**. Shorten old history comments when you touch the line.
- New or changed code in a PR without docstrings is a review finding (severity "important").

## 3. GDScript: types

1. Type everything: fields, parameters, return values, locals (`:=` only when the type is obvious on the right), `Array[T]`, `Dictionary[K, V]`, loop variables (`for e: Enemy in enemies`). Typed code catches errors before running and runs faster.
2. Untyped `var x = …` only for JSON data before its type is checked.
3. Engine warnings are switched on in steps (task CS-01): first `debug/gdscript/warnings/untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument` as warnings; once the code is clean, as errors, so `smoke.sh` fails on untyped code.
4. Silence a warning locally with `@warning_ignore("name")` and a comment explaining why.

## 4. Data: dictionaries, enums, ids

1. **Logic uses ids, not text.** Game state, weapon kind, damage source, enemy type, button action — `enum` or `StringName` (`&"gun_auto"`). The Russian label lives only in an "id → label" table used by UI and reports through translation. Comparing player-facing strings in logic (`"курсовое (авто)"`) is forbidden. *Why:* today enemy armor and bonuses depend on Russian labels; a typo breaks balance with no error.
2. **Anything that lives longer than a frame** (3D unit view, enemy record, particle with fields) is a small `extends RefCounted` class with typed fields, not a `Dictionary` with string keys. Dictionaries are fine for JSON, constant tables and projectile arrays where speed matters (§7).
3. **Array as a tuple** — at most two fields (`[rect, action]`). More than that — a class or a dictionary with named keys. No data tables with positional indices (`br[1][1][0]`).

## 5. Where balance numbers live

**Decision (Kanta 2026-10-23, option 2):** `tuning.gd` holds only what is tuned with sliders in the F1 panel; all other balance numbers live in `game/scripts/balance/<system>.gd` (e.g. `balance/enemies.gd`, `balance/weapons.gd`, `balance/rewards.gd`) as constants with `##` docstrings; class code keeps only geometry and visuals. Existing constants move there when their file is touched (no mass move).

Regardless of the choice:
- A rule number the player sees in text ("+40 parts", "15 minutes") is formatted from the same constant, never typed into the string.
- Sortie length (900 s) is one constant.
- Temporary test values (`TEST_PICKS`) live in `tuning.gd`, marked "revert by …", with a backlog line.

## 6. Coupling between parts (details — [architecture.md](architecture.md))

1. `Main.I` is the access point to sortie services. Entities **may** read (`Main.I.player`, `run_time`) and call services (`projectiles.spawn_*`, `fx`, `sfx`, `tele`). Entities **may not** write `Main` fields directly (`Main.I.parts += …`, `m.pending_levels += 1`) — only through a named `RunState` method: `run.grant_parts(n, reason)` (ADR-02).
2. Never touch another class's `_` fields and methods. Need access — add a public method (for tools — with a `debug_` prefix).
3. 2D logic does not call `Render3D.I` directly; whatever logic needs from the view (`ground_under`, `mouse_world`) goes through a narrow interface.
4. Gameplay events (enemy killed, player damaged, activity done, banner, radio) are emitted on the `Events` bus (ADR-02): `Events.activity_succeeded.emit(&"transport")`, not calls into `Main`. Listeners connect via Callable: `Events.enemy_killed.connect(_on_enemy_killed)`.
5. One rule — one place. Rewards, XP and card offers are not copied across files (change S10-13 had to be made in two places by hand).
6. Sortie state is read as `Main.I.run.*` (`run.level`, `run.parts`, `run.kills`) and changed only by `RunState` methods (`grant_parts`, `grant_rare_pick`, `award_activity`, `on_kill`; debug tools — `debug_set`). `tools/ci/smoke.sh` fails on a direct write such as `m.parts += …`. A new activity is a row in `balance/rewards.gd` plus `Events.activity_succeeded.emit(&"kind")`.
7. Pure logic (`RunState`, reward and XP formulas) has unit tests in `game/tests/*_test.gd` (`extends SceneTree`, plain checks), run by `tools/ci/unit.sh` (~5 s) before every code PR.

## 7. Performance (bullet heaven)

1. **One enemy list per frame.** Do not call `get_tree().get_nodes_in_group(...)` in combat code or HUD drawing — use the shared per-frame list (task CS-04). Hits and `aoe` go through the `Spawner._grid` grid (future `EnemyGrid`).
2. **Projectiles and mass effects have no nodes:** data arrays + one `_draw` or a MultiMesh. Every pool has a cap (oldest removed). Remove from the middle with "swap with last and `pop_back()`".
3. **No allocations in `_process` and hot loops:** no string keys (`"p%d" % i`, `"eb_%s_dmg"`), no temporary `Packed*Array([...])`, no `duplicate()`, no `find_child`/`find_children`, no `OS.get_cmdline_user_args()`. Cache all of these at creation.
4. **`_draw` only draws.** State that others need (e.g. 3D models) is not computed inside `_draw`.
5. **Resource loading.** Everything combat needs is loaded at sortie start (`preload` for permanent resources, `ResourceLoader.load_threaded_request` for the operation's models). No `load()` in the middle of combat. New shaders and materials are warmed up for one frame at sortie start.
6. **Lights.** A new `OmniLight3D` only through the shared flash pool. Mass fires use emission and glow, not lights.
7. **Shaders.** At most 8 custom samplers (macOS). `dFdx`/`dFdy`/`fwidth` before any per-pixel branch. Shared noise code goes to `shaders/common.gdshaderinc` via `#include`.
8. Performance is judged only from real-PC logs (`perf.gd`, log `l7`), never from cloud FPS.

## 8. Nodes and lifecycle

1. Entities are created in code in one order: `X.new()` → `setup(params)` (all stats, including HP with multipliers) → `add_child()`. `_ready` only joins groups and sets up visuals; it does not overwrite base numbers.
2. A reference to a node that may disappear is checked with `is_instance_valid(x)`, not `x != null`. Targets kept longer than a frame use `weakref`.
3. Before `queue_free()` an enemy leaves the `enemies` group and sets `hp <= 0` (as today).
4. A long-lived view or system node that survives a sortie has `reset_run()`, and `Main.start_run()` calls it.
5. Timers are `float -= delta` (as today): this works with pause, `--turbo` and the autotest's fixed step. No `await` or `Timer` on entities.
6. File size guideline: up to ~800 lines. Larger files are split by subsystem at the next major change (candidates: `render3d.gd`, `adobe_build.gd`, `terrain3d.gd`, `cards.gd`, `projectiles.gd`).

## 9. Saves and player data

1. All player files live in `user://` and go through one `SaveIO` layer (task CS-02): write to a temp file → verify → `rename`; keep a `.bak`; load order `file → .tmp → .bak`; rename a corrupt file to `*.broken-<time>.json` instead of overwriting it; a `version` field and migrations.
2. The `user://` folder does not depend on the project name: `application/config/use_custom_user_dir=true`, `custom_user_dir_name="FlakHeaven"`.
3. Personal settings (volume, keys, graphics) and balance live in different files. Only the F1 panel in a debug build writes balance to disk.
4. Tests (`smoke.sh`, `full.sh`, `--shots`) run in a separate temporary `user://`, never in a developer's real profile.
5. Never load objects from untrusted files (no `get_var(allow_objects=true)`). Check the type of every JSON field (`d.get("x") is Array`); JSON integers arrive as `float`.

## 10. Network and privacy

1. Any upload of player data requires the player's consent (a flag in `Settings`, off by default outside tester builds). A persistent `tester_id` only in tester builds.
2. Upload success is decided by the receiver's response body (`ok`), not by a 3xx code. The upload queue is capped by size and attempts.
3. The token in the game is a junk filter, not authentication: everything arriving in the sheet is untrusted (text starting with `=`, `+`, `-`, `@` gets a `'` prefix).
4. Keys and passwords only in the environment's "Network secrets" and environment variables. Never in the repository or logs.

## 11. Debugging and launch flags

1. Command-line flags are read **once** at startup in one place (`DebugFlags`/`Main.flags`, task CS-05). Code calls `DebugFlags.has("--x")`, not `OS.get_cmdline_user_args()`.
2. Flags that change gameplay (`--god`, `--mastery`, `--heavy=`, `--turbo`, `--warship`) work only when `Main.DEBUG` is on; not in tester or release builds.
3. Debug values set by flags never reach `tuning.json`.
4. The build number lives in one place in the repository and changes by commit before export; the build script checks that it is new.

## 12. UI in code (details — [ui-design-system.md](ui-design-system.md))

1. Colors, font sizes and spacing come only from `UiStyle` (role tokens). A `Color(...)` literal in `hud_*`/`menu.gd` only for one-off decoration, with a comment.
2. Minimum font size is 14 (Steam Deck: ≥ 9 px at 1280×800).
3. Buttons are hit-tested so that "drawn last — gets the click" (search the button list from the end).
4. Every button is reachable with a gamepad (focus); a screen opened over combat ignores input for the first 0.3 s.
5. Key labels only via `key_label(action)` — no "Space"/"Shift" inside strings.

## 13. Localization

1. The key is the Russian phrase; `.po` (gettext) files are in git, `*.translation` in `.gitignore`.
2. Strings with numbers: **translate the template first, then format** — `Loc.t("до базы %d м") % d`. The reverse (`Loc.t("до базы %d м" % d)`) is forbidden: it breaks translation and costs time every frame.
3. Plurals via `tr_n`/`Loc.n` (Russian has three forms), not "1 подходящих карточек".
4. Translation goes through one function (`Loc.t`), not `TranslationServer.translate` directly.
5. After changing strings run `python3 tools/i18n/scan_strings.py` and `check_po.py` (they catch placeholder mismatches).

## 14. Python tools (`tools/`, `game/tools/`)

1. Each file starts with a docstring header in CODE_LANGUAGE: purpose, run command, dependencies, decision and date (as today — the best part of the tooling). Public library functions have docstrings.
2. Template: `argparse` with `--help`; `def main() -> int`; `if __name__ == "__main__": sys.exit(main())`; paths via `pathlib` relative to `__file__` (`ROOT = Path(__file__).resolve().parents[N]`); `encoding="utf-8"` for text I/O.
3. PEP 8, 4 spaces, type hints on public functions. Formatting and linting with `ruff format` and `ruff check` (config in `pyproject.toml`, task CS-07).
4. **Input ≠ output.** A tool never overwrites its input; `--in-place` only explicitly and with a `.bak`. The command chain for every asset is recorded (recipe in `game/models/CREDITS.md` or `docs/tasks/`).
5. Downloads go through one function: write to `.part` → `os.replace`; the URL is pinned to a version or commit, with SHA-256 where possible.
6. Dependencies in `requirements.txt` with exact versions (`tools/` and `game/tools/` separately); the `bpy`/Blender version is recorded.
7. One library per job: Blender geometry — `hq_lib` (details) or `convoy_kit` (vehicles with baking); GLB — `blender/glb_io.py`. No new copies of `box`/`cyl`.
8. Blender: prefer the data API and `bmesh` over `bpy.ops` (operators fail on `poll()` in background mode); fixed seed for anything procedural.
9. `.gd` tools (`game/tools/**`) call only the game's public API.

## 15. Bash and CI

1. `#!/usr/bin/env bash`, `set -euo pipefail` (CI scripts that check exit codes manually: `set -uo pipefail`), quoted variables, run from the repo root with a `[ -f game/project.godot ]` check.
2. The game check catches not only `SCRIPT ERROR|Parse Error` but also `^ERROR:`, `SHADER ERROR`, `USER ERROR` (known noise in an allowlist `tools/ci/known_errors.txt`).
3. `pick.sh` treats every `game/scripts/*.gd` as combat except an explicit non-combat list (UI, menu, hangar, settings, localization, profile, report, benches).
4. Every scenario that broke by hand (empty card offer, click on a nested button) gets an autotest check.

## 16. Repository

1. In git: code, `.uid`, `.import` for every asset in `game/` (same import settings for everyone and in CI), `.tscn/.tres`, `project.godot`, `export_presets.cfg`, `.po`.
2. Not in git: `.godot/`, builds, `*.translation`, `.blend`/`.blend1`, raw generator outputs, `.venv/`, `node_modules/`, `.env`, `*.session`, logs. A work folder inside `game/` that Godot must not import gets an empty `.gdignore`.
3. File and folder names — ASCII only (CLAUDE.md, hard rule 6).
4. Commits are small, in CODE_LANGUAGE: what and why.

## 17. Author checklist before a PR

- [ ] Everything is typed; no `untyped` warnings.
- [ ] New and changed classes and public functions have a `##` docstring in CODE_LANGUAGE.
- [ ] Logic does not compare Russian strings; new ids are enums or `StringName`.
- [ ] New balance numbers are where §5 says; player-facing text takes the number from there.
- [ ] No writes to foreign fields or other classes' `_` fields.
- [ ] No new allocations, `get_nodes_in_group` or `load()` in `_process`.
- [ ] Player strings follow "template → `Loc.t` → `%`".
- [ ] New buttons work with mouse and gamepad; font size ≥ 14.
- [ ] `tools/ci/pick.sh` → required checks passed, results in the PR description.
