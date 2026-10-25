# Working rules outside code

Moved out of `CLAUDE.md` on 2026-10-23 so that every thread doesn't load them. Code rules: `CLAUDE.md` and `docs/standards/`. Text for the Claude project instructions field: `project-instructions.md`. Stages to early access and task sizing: `early-access.md`.

## Decisions and money
- Decisions on game design, art, audio, money, legal and team are made by Kanta (Kirill stepped back on 2026-10-18). Each decision is a line in the decision log `docs/game-context.md` with who decided → a numbered task in `docs/backlog.md` → an owner thread right away. Agents prepare options and a recommendation.
- A new test build only on Kanta's direct command, once the previous build's list is closed and checked in game; at least a day between builds (Kanta, 2026-10-22).
- After Kanta uploads a build to itch.io: set `site/version.json` → `"build"` to the new number (commit to `main`; testers on an older build then see «Вышла сборка …» in the main menu with the itch.io link), and post the build in Discord and Telegram (Kanta, 2026-10-25).
- No spending on people. Money only for tools and subscriptions, Kanta decides.
- Documents are the source of truth: decision → `docs/game-context.md`, task → `docs/backlog.md`, build result → `docs/status-log.md` and `game/README.md`. Heavy files (builds, raw models, `.blend`) stay in the Claude project files (`/mnt/project-files`).

## Communication
- Chat, statuses, thread titles and in-game menus in Russian. GitHub buttons quoted as on screen ("Merge pull request", "Confirm merge").
- Feedback is collected into one numbered list per build; work starts after "готово".
- Questions as numbered options with a recommendation; a choice card is only an addition.
- A reply starts with what is needed from Kanta; each action with a direct link.
- Proposal first for large changes to rules, structure and settings; small reversible things are done right away and reported.
- Do it yourself / automate first; ask Kanta last (Kanta, 2026-10-20).
- One thread per system; at most 3 code threads and 2 Opus threads at once.
- Daily stand-up 17:00 MSK; weekly owner checklist (`docs/owner-checklist/`) and Friday review.
- Models: strong for code, game design, 3D; lighter for statuses, docs, builds. Claude picks and says which. Long processes in background, heavy work during the day.
- Second opinions (GPT, Gemini) are advice: parsed point by point, Kanta decides.

## Art and 3D
- Tool by object type: complex shapes (aircraft, large vehicles, rocks) — Meshy; simple precise parts (turrets, weapons, missiles, AA) — Blender via code from references; portraits and concepts — ChatGPT or Gemini from Claude's prompts; ground and rock textures — CC0 (Poly Haven, ambientCG).
- Catalog before models: list with pictures, Kanta's notes and references, then models.
- Generator credits: input image and generation package approved by Kanta before spending.
- Two quality levels: in combat ~5–15k triangles; hangar and close-ups — max. Always keep sources (project files).
- Every model is shown as a screenshot from the game camera.
- Remaining 3D-model tasks: `docs/tasks/3d-models-handoff.md`.

## Site flakheaven.com
- `site/` (Cloudflare Pages, deploys from `main`); details in `site/README.md`.
- The "Marketing" thread checks both addresses hourly (flakheaven.com and www): if down or missing "Flak Heaven", find the cause; bugs in `site/` → PR, Cloudflare/registrar issues → described to Kanta.
- Cloudflare token (Pages edit, DNS edit, zone read) is in the environment's network secrets for api.cloudflare.com; never print or commit it. It may be used to view builds and DNS and to retry a build.
- Domain bought at reg.ru on 2026-10-18 for a year; renew by 2027-10-18 (reminder a month ahead).
- After merging a `site/` change, check the page opens.

## Builds
- Export presets in `game/export_presets.cfg`: "Windows Tester", "macOS Tester", "Linux Check". The `tester` feature turns off debug (F1, F4–F8, hangar debug).
- Build number: `BUILD` in `game/scripts/main.gd`; report endpoint: `REPORT_URL_BUILTIN` there. Kits: `tools/tester/make_kit.sh`.
- Debug flags: `--tester`, `--report-url=…`, `--mesatest`, `--reporttest`, `--turbo`.

## Superpowers experiment (since 2026-10-23)
- 15 skills in `.claude/skills/`; rollback steps in `docs/process/backup-2026-10-23/`. Assessed at the review on 2026-10-30 (task R-16).
- Task size: small — do it; medium (several files of one system, rules unchanged) — short plan in the PR body; large (new system or screen, rule change, >3 systems or ~500 lines) — brainstorming → plan → Kanta's "yes". The game-designer skill goes before brainstorming for rules, balance and progression.
- Critical path to Next Fest (11-01 Steamworks, 11-10 fee, 11-30 store page, 12-15 demo, 01-10 registration, 01-25 Valve review) goes first in the strong-model queue.
- Unit tests (TDD) are mandatory for any new non-visual logic once the test framework is in `main` (Kanta, 2026-10-23); combat, graphics and menus are checked by smoke and the full autotest.
- Subagents are allowed for plan tasks. Skills never spend money or write to external services without Kanta's "yes". No worktrees or finishing-a-development-branch menus unless Kanta asks.
