# Flak Heaven — resume pack (README-RESTORE)

Generated: @DATE@ (UTC). Repo `main` at @MAIN@.

## What this is
Flak Heaven: top-down roguelike / bullet heaven about combat aviation (Godot 4.4.1, Steam early access goal). Fictional world: no real countries, flags, aircraft names. Owner/decision maker: Kanta (chat in Russian; code, docs, commits in English).

## How to continue exactly from here
1. Code: `git clone https://github.com/kanta201196-hub/FlakHeaven`; all branches and PRs live on GitHub. `repo-refs.txt` lists every branch SHA at backup time. `repo-incremental.bundle` (if present) holds commits since the previous backup: `git fetch repo-incremental.bundle 'refs/*:refs/restored/*'`.
2. Read in order: `CLAUDE.md`, `docs/standards/code.md`, `docs/standards/architecture.md`, `docs/game-context.md` (rules in force + decision log), `docs/process/working-rules.md`, `docs/backlog.md`.
3. Memory: `project-memory.tgz` = coordinator memory files (one fact per file, `MEMORY.md` is the index: priorities, rules from Kanta, builds, threads).
4. `threads.md` = every work thread with state and last activity; `open-prs.md` = PR summary; `project-instructions.md` = Kanta's standing rules.
5. `project-files-manifest.tsv` = list of the shared folder (/mnt/project-files: builds, models, marketing, docs); large binaries are NOT copied (10 GB project limit); builds are rebuilt with `tools/tester/make_kit.sh` only on Kanta's command.

## Hard rules to keep
No balance/art/audio/money/legal changes without Kanta's explicit "yes". No test builds unless asked. No spending, no writes to external services without "yes". Secrets only in environment secrets, never in files. ASCII file names. See CLAUDE.md.

## Not in this pack
Secrets/tokens, `.godot/`, builds, raw generator output, files on Kanta's PCs outside E:\Claude\FlakHeaven.
