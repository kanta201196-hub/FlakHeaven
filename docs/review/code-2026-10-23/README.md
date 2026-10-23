# Flak Heaven code review — 2026-10-23

Done with the superpowers `requesting-code-review` skill over the whole repository (commit `f9edc3e`, branch `main`) rather than a single PR: five reviewers by area plus a sixth collecting Godot 4.4 and Python best practices. No game code was changed. Reviewers did not run the game: screen-layout findings are computed from coordinates, performance findings come from reading code (project rule: FPS is measured only on real PCs).

The most important findings were re-checked by hand against the code (marked ✔).

| File | Area |
| --- | --- |
| [r1-core.md](r1-core.md) | Core: `main.gd`, states, profile and saves, reports, settings, campaign |
| [r2-combat.md](r2-combat.md) | Combat: player, weapons, projectiles, enemies, spawner, bosses, activities |
| [r3-render.md](r3-render.md) | 3D view: `render3d.gd`, terrain, explosions, shaders, sound |
| [r4-ui.md](r4-ui.md) | UI: HUD, menu, screens, localization + visual language inventory |
| [r5-tools.md](r5-tools.md) | Tooling: CI scripts, Python, Blender, report receiver |
| [r6-practices.md](r6-practices.md) | Industry best practices with sources (Godot 4.4, GDScript, Steam Deck, Python, Blender) |

The detailed reports r1–r6 are in Russian (written before the 2026-10-23 language decision); they are translated only if someone works from them.

Standards that grew out of the review:
- [Coding standards](../../standards/code.md)
- [Architecture](../../standards/architecture.md)
- [UI design system](../../standards/ui-design-system.md)

## Overall

For a prototype written mostly by agents, the code is in good shape: node-less projectiles, segment-based hits, deterministic timers, careful handling of freed objects, MultiMesh and pools in 3D, background terrain build, atomic profile writes, rich telemetry, no secrets in the repo. No combat crashes found.

**Code documentation is weak:** 43 % of functions have a `##` docstring (665 of 1549 in `game/scripts`), full-line comments are about 9 % of code lines, and they are mostly change history ("was → now", whose feedback) rather than an explanation of what the code does and why. An agent opening a file for the first time reconstructs meaning from the code. Rule — [code.md §2](../../standards/code.md); comment language — one parameter (§0).

The main debt is not the quality of individual functions but **coupling**: `Main.I` as a shared object for 46 files (657 uses), mechanics keyed on Russian strings, balance numbers in dozens of places, three button sets and 214 distinct colors in the UI. That is what the standards must stop.

## Findings by severity

### Critical — fix before the demo (2026-12-15)

| # | What | Where | Checked |
| --- | --- | --- | --- |
| CR-01 | Clicking "Pin" or "Ban" on a level-up card **picks the card**: the card rect is registered before the nested buttons and the click takes the first match. The autotest misses it — it calls `ban_card` directly | `hud_screens.gd:103,147-149`, `hud.gd:98-102` | ✔ |
| CR-02 | The game can **get stuck on an empty card screen** (Esc and pause do nothing there): an empty offer is handled only when the screen opens, not after a pick, course choice or ban | `main.gd:425-427, 455-458, 505-522` | ✔ |
| CR-03 | **The profile can be lost**: the `rename` result is not checked, `.tmp` is not looked for on load, broken JSON silently resets the profile and the next save overwrites it | `profile.gd:139-178` | — |
| CR-04 | **Every sortie row is uploaded to a Google Sheet without player consent**, demo included (OS, GPU, persistent `tester_id`). Contradicts decision DM-07 "report with player consent" | `report.gd:412-432`, `main.gd:83,115` | — |
| CR-05 | **Gamepad**: menu, settings and hangar are unreachable; A/X/B/Y are both combat actions and "pick card 1–4", and the level-up screen has no input delay — a dodge at the moment of level-up blindly takes the first card. Steam Deck blocker | `input_setup.gd:14,37`, `main_input.gd:33,47-58`, `menu.gd:68-113` | ✔ |
| CR-06 | Formula injection in the reports sheet: tester text starting with `=` becomes a formula | `tools/reports/apps_script.gs:61-77` | — |

### Important — next cycles

**Combat and rules**
- At the enemy cap the spawner `return`s and freezes the bomber, ekranoplan and gull timers — late in a sortie they almost never appear (`spawner.gd:203`) ✔.
- Bomb lead is always zero: `t.get("velocity")`, but enemies have `move_vel` (`hardpoint.gd:823`) ✔. The fix changes balance — per R-10.
- The "Skvoznyak" boss summons 3 interceptors every 10 s with no cap, right next to itself (`boss.gd:339-347`).
- Mechanics depend on Russian damage labels ("курсовое…", "турели"): a typo or rename breaks armor and bonuses with no error (`enemy.gd:72-81`, `boss.gd:120-131`, `projectiles.gd:421`).
- Activity rewards are copied into three places (`main.gd:546`, `transport.gd:93`, `rescue.gd:72`).
- Newcomer hints are spent on the menu background before the first sortie (`main.gd:237-243`, `hints.gd:172`).
- `TEST_PICKS = 10` rerolls and bans "for testing" — revert to 2 before the demo (`main.gd:51`).
- Cheat launch flags (`--mastery`, `--heavy=`, `--god`, `--turbo`) work in tester builds too.

**Data and saves**
- The `user://` folder is derived from the name "Flak Heaven - Prototype 3 (3D)": renaming for release loses all saves and breaks demo → full game transfer. Set `custom_user_dir_name` now (`project.godot:8`).
- Changing the volume writes all balance to `tuning.json`, debug values leak there too (`tuning.gd:186-213`).
- `smoke.sh`, `full.sh` and `--shots` run against the developer's real profile (`--shots` adds 8000 parts).
- `BUILD := "3.4-t1"` in code; the number is changed by hand at export (`main.gd:81`).
- The report queue can get stuck forever on one message; any 3xx counts as success.
- Rebinding a key removes the duplicate key (arrow keys).

**UI**
- Settings do not fit at 1920×1080: "Reset progress" is off screen, "Minimap" overlaps "Save" (`menu.gd:448-526`).
- About 25 places with font size 11–13: under 9 px on the Steam Deck (Valve's minimum). No UI scale setting.
- HUD key labels are hardcoded ("Space", "Shift"), ignoring rebinding and gamepad.
- In EN and ZH `Loc.out` re-parses strings every frame where numbers were inserted before translation.

**View and performance**
- Models and shaders load synchronously in combat on first appearance (`load()` on the main thread, no `preload`/`load_threaded_request`, `Boom3D` created on the first explosion) — hitches exactly in the demo's first session.
- The ground shader uses 13 samplers: risk of black ground on macOS (not tested on a Mac).
- `dFdx`/`fwidth` inside per-pixel branches in the ground shader — shimmering on Mesa (Deck) and Apple.
- Double explosion lights: two pools, up to 14 point lights against a limit of 8 per object.
- `get_nodes_in_group("enemies")` — 45 calls in combat, including one per explosion; bullets are tested against every enemy.
- `render3d.gd` is 2565 lines, unit records are dictionaries with ~40 string keys, other classes read its private fields.
- 20 new combat models have no `.import` in the repo (default import on a clean clone).

**Tooling**
- `pick.sh` does not treat `projectiles.gd`, `cards.gd`, `fortress.gd` and ~15 more as combat and says "full autotest not needed".
- `smoke.sh` catches only `SCRIPT ERROR|Parse Error`: "resource not found" and `SHADER ERROR` pass as ok.
- `check_po.py --sync` silently erases multi-line translations (if a translator opens the `.po` in Poedit).
- `game/models/pilot/` — 334 MB of raw generator models in git, unused by the game.
- The ground normal/height map is JPEG with 4:2:0 chroma subsampling (`prep_ground.py:37`).

### Minor
About 50 items in r1–r5 ("Мелкие" sections): dead code, Archipelago operation number shown as "5–8", banners showing a number without `continue_mult`, boss bar without `clamp`, 3D state not reset between sorties, etc.

## Next

Decisions that change rules or structure belong to Kanta (numbered questions in the thread "Ревью кода и стандарты разработки"). Tasks CR-01…CR-06 and CS-01…CS-12 are in `docs/backlog.md`, section "Code review (2026-10-23)".
