# Flak Heaven — CLAUDE.md

Top-down roguelike / bullet heaven about combat aviation, 15-minute sorties. Target: Steam early access.
Engine: **Godot 4.4.1**, renderer **GL Compatibility**. Game logic is 2D; visuals are a 3D scene with a top-down camera.

## Read before coding
- How to write code: `docs/standards/code.md` (GDScript style, types, ids, performance, saves, debug flags, Python, Bash/CI, PR author checklist).
- Architecture: `docs/standards/architecture.md` (game map, target architecture, ADRs).
- UI: `docs/standards/ui-design-system.md` (tokens, components, gamepad focus).
- Code review findings and best practices behind the standards: `docs/review/code-2026-10-23/README.md`, `r6-practices.md` (Godot 4.4 and Python, with sources).
- Game rules in force and decision log: `docs/game-context.md` (read before any gameplay/balance change).
- Process outside code (decisions, art pipeline, site, builds): `docs/process/working-rules.md`.

## Repository map
| Path | What |
| --- | --- |
| `game/` | Godot project (`game/project.godot`). Balance numbers: F1 sliders in `game/scripts/tuning.gd`, the rest in `game/scripts/balance/<system>.gd` (`code.md` §5) |
| `game/tools/model_lab/` | 3D model pipeline (commands at the top of `model_lab.gd`) |
| `tools/ci/` | `pick.sh` (which checks to run), `smoke.sh`, `full.sh` |
| `tools/reports/`, `tools/tester/` | Tester report intake; tester instructions and kit script |
| `site/` | flakheaven.com (Cloudflare Pages, deploys from `main`) |
| `docs/` | All working documents; the source of truth |

## Hard rules
1. **Fictional world.** No real countries, flags, insignia, real aircraft names or real conflicts. Hardware is "inspired by". Applies to code, assets, strings and docs.
2. **No game-rule, balance, art, audio, money or legal changes without the user's explicit "yes".** Balance at most once per build cycle.
3. **Never build or export a test build (zip/exe/app) unless the user asks for it directly.**
4. **No spending** (paid services, generator credits) and **no writes to external services** without the user's "yes". Do not bypass service or region restrictions or captchas.
5. **Secrets** live only in environment secrets. Never print, log or commit tokens, keys, passwords.
6. **File and folder names: ASCII only** (Cyrillic breaks zip archives and some OSes). File contents may be in any language.
7. **Never delete files on a user's machine** without their permission.
8. Do not commit: `.godot/`, `export/`, `builds/`, `.blend`, raw generator output, personal logs, secrets (full list: `code.md` §16).

## Must-do in every code change
- `##` docstring for every new or changed class and public function (`code.md` §2); explain why, not change history.
- Run through the PR author checklist (`code.md` §17).

## Language
English for code, comments, docstrings, commits, PRs and internal docs. Russian for chat with the user. Player-facing text goes through translation keys (`.po`); player/tester docs and the site use the audience's language.

## Git
- Code: branch `name/task`, PR into `main`. Claude merges its own PR when there are no conflicts, required checks passed, and the PR body says what was checked.
- Docs, `tools/tester/`, `site/` (except mini-game code): commit straight to `main`, no PR.
- `git pull` before starting. Don't edit a system another open task owns (owner is in `docs/backlog.md`).
- Small commits: what and why.

## Checks (Godot 4.4.1 as `godot` or in `$GODOT`)
- `tools/ci/pick.sh` — prints which checks your diff needs (runs nothing).
- After every change: `tools/ci/smoke.sh fighter` (`attacker`, `bomber`, `all` ≈ 40 s). Fails on the first `SCRIPT ERROR`.
- Combat code changed: run `tools/ci/full.sh` once before the PR is ready (~4 min). Unrelated failure: rerun once, then log "flaky test" in the backlog.
- Long tests and balance measurements: only after agreeing the method with the user.
- GitHub Actions are off (no minutes left): run checks locally and paste results in the PR.
- After adding a script with `class_name`: `godot --headless --path game --import` once.
- Screenshots: `xvfb-run godot --path game --rendering-driver opengl3 -- --autotest --shots` (`user://shot_*.png`).
- The cloud has no GPU: FPS here means nothing; judge performance only from logs on real PCs.

## Skills (superpowers in `.claude/skills/`)
Project rules override skills. Small, clear changes (one file, a number, text): just do them. Mandatory:
- **flak-heaven-game-design** (account skill) before any change to game rules, combat numbers, XP/damage, upgrade cards, classes or meta-progression; it goes before brainstorming.
- **brainstorming → writing-plans** before a new scene, system or screen, or any change to game rules. Plan goes to `docs/superpowers/plans/`; large work waits for the user's "yes".
- **systematic-debugging** on any error or failing check: find the cause before fixing.
- **verification-before-completion** before saying "done": run the checks above and show the output.
- **requesting-code-review** (or the Engineering plugin's **code-review**) before merging a code PR.
- Engineering plugin **architecture** / **system-design** when a change touches the structure in `architecture.md` (new ADR, new system boundary).
- **test-driven-development** for any new non-visual logic: formulas, progression, saves, rewards, card selection (unit tests; mandatory once the test framework is in `main`). Combat feel, graphics and menus: `smoke.sh` / `full.sh`.
- Docs, site, marketing and builds: no skill chain.

## Library docs (Context7)
Use Context7 (`resolve-library-id` → `query-docs`) before writing or changing code that relies on a Godot, GDScript or Python library API you are not sure about, and when debugging engine behaviour. Godot: library `/godotengine/godot`, version `4.4.1-stable` (the docs repo has only 4.5+, which has APIs 4.4 lacks — see `code.md` §1). If Context7 is not available in the session, use the official docs via web search.
