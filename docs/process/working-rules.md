# Working rules outside code

Moved out of `CLAUDE.md` on 2026-10-23 so that every thread doesn't load them. Code rules: `CLAUDE.md` and `docs/standards/`. Text for the Claude project instructions field: `project-instructions.md`. Stages to early access and task sizing: `early-access.md`.

## Decisions and money
- Decisions on game design, art, audio, money, legal and team are made by Kanta (Kirill stepped back on 2026-10-18). Each decision is a line in the decision log `docs/game-context.md` with who decided → a numbered task in `docs/backlog.md` → an owner thread right away. Agents prepare options and a recommendation.
- A new test build only on Kanta's direct command, once the previous build's list is closed and checked in game; at least a day between builds (Kanta, 2026-10-22).
- After Kanta uploads a build to itch.io: set `site/version.json` → `"build"` to the new number (commit to `main`; testers on an older build then see «Вышла сборка …» in the main menu with the itch.io link) (Kanta, 2026-10-25). Posts about the build in Discord and Telegram belong to the marketing thread, not the build thread (Kanta, 2026-11-06).
- Standing permission (Kanta, 2026-11-06): once a build is built and self-checked (after his "собери"), upload it to the Yandex Disk folders `FlakHeaven - testers/Test for Win` and `Test for Mac` via the Disk API (`cloud-api.yandex.net`, secret `Authorization: OAuth ...` in Network secrets) with no further approval, then bump `site/version.json`. Testers get only current builds (Kanta, 2026-11-06): after a successful upload and size check, delete the previous version from the same test folder (to the Disk trash, not permanently); touch no other Disk folder. Telegram posts and bot broadcasts still need his yes. Options doc: `docs/testers/automation-intake-and-delivery.md`.
- No spending on people. Money only for tools and subscriptions, Kanta decides.
- Documents are the source of truth: decision → `docs/game-context.md`, task → `docs/backlog.md`, build result → `docs/status-log.md` and `game/README.md`. Heavy files (builds, raw models, `.blend`) stay in the Claude project files (`/mnt/project-files`).

## Communication
- Chat, statuses, thread titles and in-game menus in Russian. Before sending, a reply that came out in English is rewritten in Russian (Kanta, 2026-11-06, R-32, after three English coordinator replies). GitHub buttons quoted as on screen ("Merge pull request", "Confirm merge").
- Feedback is collected into one numbered list per build; work starts after "готово".
- Questions as numbered options with a recommendation; a choice card is only an addition.
- A reply starts with what is needed from Kanta; each action with a direct link.
- Proposal first for large changes to rules, structure and settings; small reversible things are done right away and reported.
- Do it yourself / automate first; ask Kanta last (Kanta, 2026-10-20).
- One thread per system; at most 6 strong-model (Opus) threads at once (Kanta, 2026-10-25).
- Daily stand-up 17:00 MSK; weekly owner checklist (`docs/owner-checklist/`) and Friday review.
- Models: strong for code, game design, 3D; lighter for statuses, docs, builds. Claude picks and says which. Weapons, damage and upgrade work starts on Opus; Fable only for story and texts (its safety filter stopped weapon-upgrade work twice on 31.10; Kanta 2026-11-06, R-33). Long processes in background, heavy work during the day.
- Marketing: posts from the approved weekly plan go out at 12:00 MSK unless Kanta writes «стоп» by 11:00; texts in Kanta's own voice (devlog, opinions, replies to people) still need «ок» (Kanta, 2026-10-31, R-19).
- Second opinions (GPT, Gemini) are advice: parsed point by point, Kanta decides.

## Art and 3D
- Tool by object type: complex shapes (aircraft, large vehicles, rocks) — Meshy; simple precise parts (turrets, weapons, missiles, AA) — Blender via code from references; portraits and concepts — ChatGPT or Gemini from Claude's prompts; ground and rock textures — CC0 (Poly Haven, ambientCG).
- Catalog before models: list with pictures, Kanta's notes and references, then models.
- Generator credits: input image and generation package approved by Kanta before spending.
- Two quality levels: in combat ~5–15k triangles; hangar and close-ups — max. Always keep sources (project files).
- Every model is shown as a screenshot from the game camera.
- No model ships with flat, even paint (Kanta 2026-10-26, Fortress domes): every own or procedural model gets a natural surface before review — edge wear, cavity grime and dust, seams or panel lines where they fit, soot near engines and guns, and a roughness map with variation. Matte, no gloss. Bake approach: `game/tools/blender/turret_paint.py`.
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
- Every build ships with a «что проверить» page (≤ 15 lines), attached to the build message. 24 h after Kanta's first message about the build, every item he did not flag becomes «проверено в sN» in the backlog and the build list is archived; the build thread itself adds the build line to `docs/status-log.md` (Kanta, 2026-10-31 R-18; 2026-11-06 R-30).
- Builds are delivered from the cloud without the home PC: itch.io via butler with the environment key, Yandex Disk via the Disk API «upload by URL» (Disk pulls the file server-side; direct PUT from the cloud is cut after ~30 s on slow routes). The PC is a fallback only (Kanta, 2026-11-06, R-26).
- Balance: all balance changes of a build cycle form one numbered package (one journal line, each change «было → стало»), read against the next build log (Kanta, 2026-11-06, R-28; replaces «one change per build»).
- Before a build: the self-check contact sheet (hangar and combat) is attached to the build message (R-23). Command: `nohup tools/ci/selfcheck.sh &` (presets 0, 2, 3, Forward+ via lavapipe, about an hour per preset; `--quick` — preset 2 only, `--compat` — GL Compatibility, `--only=bomber_2` — one plane). Output: `builds/selfcheck-<commit>/index.html`; exit code 1 on a failed capture or a `SCRIPT ERROR`.
- Feel and effects changes Kanta wants to judge (turret firing, flight feel, effects) go into `main` behind an F1 toggle that is **on by default**, so Kanta tries them in the next build; 0 gives the old look, and Kanta's «нет» turns it off or removes it (Kanta, 2026-10-31, R-22; changed 2026-11-06: «сначала включены, я же хочу их попробовать» — the tester build has no F1 outside «Битва асов»).
- Debug flags: `--tester`, `--report-url=…`, `--mesatest`, `--reporttest`, `--turbo`.

## Backup
- Daily full backup at 06:47 MSK to Yandex Disk, folder `FlakHeaven backup/<YYYY-MM-DD>`; script `tools/backup/yadisk_daily.sh`, scheduled task `trig_01STd9R9WMJZhHWF3eJmrDFm` (Kanta, 2026-11-06).
- Contents: all git branches (bundle), a `main` snapshot, models, docs and source assets from the shared folder (without builds, marketing, old backups, root mp4/rar), project memory and instructions. About 5.8 GB, about 156 files.
- Retention: 14 days; older dated folders go to the Disk trash, and only after a fully verified run (Kanta, 2026-11-06).
- A day is complete only when `SHA256SUMS.txt` is uploaded last. Check that the folder has `SHA256SUMS.txt`.
- The backup must happen without Kanta (Kanta, 2026-11-06). How each failure is handled:
  - Upload cut off or container lost: rerunning resumes. Today's pack is reused if it is still on disk; files already on the Disk with the same size and sha256 are skipped; parts of an older pack are removed from the day folder before `SHA256SUMS.txt` goes up. Each run makes up to 3 passes over the files that failed.
  - Run failed or never fired: the watchdog task `trig_01RZM2LwqJnzsYaTBLGduvbS` (10:17, 14:17, 20:17 MSK, thread "Сделать бэкап надёжным без Kanta", a different session from the main run) checks for today's `SHA256SUMS.txt` and reruns the script if it is missing.
  - Disk unreachable, token rejected, not enough space, or shared folder missing: the script stops before uploading and saves the small irreplaceable part (project memory, instructions, branch list, `WHY.txt`) to `/mnt/project-files/backups/emergency/<date>/` (newest 3 kept). Code stays on GitHub and models stay in the shared folder, so nothing exists in only one place.
  - Exit codes: 0 done, 2 Disk unreachable or token rejected, 3 not enough space, 4 shared folder missing or under 500 files, 5 files failed after 3 passes, 1 other.
  - Kanta is told only when he must act (token rejected: renew it in the environment's network secret for `cloud-api.yandex.net`; Disk full) or when the 20:17 watchdog run still has no complete day. Disk trash counts toward the quota and is never emptied without Kanta.
- Old twice-weekly routine (Fri and Mon, Google Drive and laptop copies) is off since 2026-11-06 (R-31).
- Full copies on the home PC are manual, one-off, and need Kanta's request.

## Superpowers experiment (since 2026-10-23)
- 15 skills in `.claude/skills/`; rollback steps in `docs/process/backup-2026-10-23/`. Assessed at the review on 2026-10-30 (task R-16).
- Task size: small — do it; medium (several files of one system, rules unchanged) — short plan in the PR body; large (new system or screen, rule change, >3 systems or ~500 lines) — brainstorming → plan → Kanta's "yes". The game-designer skill goes before brainstorming for rules, balance and progression.
- Critical path to Next Fest (11-01 Steamworks, 11-10 fee, 11-30 store page, 12-15 demo, 01-10 registration, 01-25 Valve review) goes first in the strong-model queue.
- Unit tests (TDD) are mandatory for any new non-visual logic once the test framework is in `main` (Kanta, 2026-10-23); combat, graphics and menus are checked by smoke and the full autotest.
- Subagents are allowed for plan tasks. Skills never spend money or write to external services without Kanta's "yes". No worktrees or finishing-a-development-branch menus unless Kanta asks.
