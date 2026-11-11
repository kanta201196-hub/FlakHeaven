# task-observer trial

Started 2026-11-11 (Kanta chose "install, but control it": analyse every 3 days, judge efficiency, remove if it does not pay off).

## What it is
Meta-skill from https://github.com/rebelytics/one-skill-to-rule-them-all (v3.10.0, license CC BY 4.0, copy in `.claude/skills/task-observer/`, license text in `LICENSE-CC-BY-4.0`). It logs corrections and repeating patterns as observations and proposes skill updates in a weekly review. Plugin folder, CI files and docs of the original were not copied.

## Wiring
- Activation: one bullet in `CLAUDE.md` (Skills section).
- Log: `docs/process/skill-observations/observation-log/`, one Markdown file per observation. Threads are disposable, so observations are committed to `main` (docs rule) in the same thread that wrote them.
- Skills and rules are changed only with Kanta's "yes" (see "Log, don't act" in the skill).

## Review every 3 days (scheduled task, owner: this thread)
Review dates: 2026-11-14, 11-17, 11-20, ... Each review records one row below.
Measure:
1. Observations written since last review (count; how many are specific and new vs. noise or duplicates of memory/backlog).
2. Observations that led to a concrete accepted change (skill/rule edit, new skill) with Kanta's yes.
3. Cost: extra tool calls and time per thread spent on the protocol (sample 3-5 recent threads; SKILL.md is 50 KB and loads in every activated thread). Tokens are a guess unless the session reports them.
4. Friction: conflicts with CLAUDE.md or project instructions, threads that stalled on the protocol.

Verdict rule (proposal, Kanta decides): keep if at least 1 accepted improvement per 2 reviews and cost stays small; otherwise remove.

## Removal
Delete `.claude/skills/task-observer/`, the task-observer bullet in `CLAUDE.md`, this file's "Wiring" and keep `docs/process/skill-observations/` as history (or delete with Kanta's yes). Then stop the scheduled review.

## Review log
| Date | Observations | Accepted changes | Cost / friction | Verdict |
| --- | --- | --- | --- | --- |
| 2026-11-11 | 0 | 0 | baseline | installed |
