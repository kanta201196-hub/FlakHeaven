# Plan: event bus and RunState

Date: 2026-10-23. Design — [../specs/2026-10-23-events-run-state-design.md](../specs/2026-10-23-events-run-state-design.md). Status: **awaiting Kanta's "yes"**. Executor: one strong-model code thread (assigned by the coordinator). Each task is one PR, merged before the next starts. All new code follows `docs/standards/code.md` (English docstrings, typed).

Checks for every PR: `tools/ci/smoke.sh all`, `tools/ci/full.sh` once (combat files change), `tools/ci/unit.sh` from PR 1 on; results and the before/after `AUTOTEST:` summary in the PR description. Run tests with a temporary `XDG_DATA_HOME` so the real profile is untouched.

## PR 1 — Skeleton: `Events`, `RunState`, unit tests (no behavior change)

Files: new `game/scripts/events.gd`, `game/scripts/run_state.gd`, `game/scripts/balance/rewards.gd`, `game/tests/run_state_test.gd`, `tools/ci/unit.sh`; edit `game/project.godot` (autoload `Events`), `game/scripts/main.gd`.

1. `Events` autoload with all signals from the design (typed, docstring each). Nothing emits yet.
2. `RunState` with the fields and methods from the design; `balance/rewards.gd` with the reward table (numbers copied from `main.gd:558-581`, `transport.gd:93-112`, `rescue.gd:72-86`, `class_task.gd:46-49`).
3. `Main.start_run` creates `run = RunState.new(self)`; `Main` fields `level, xp, pending_levels, rare_picks, rare_reasons, parts, parts_kept, kills, activities_done, streak, streak_t, best_streak, tail_kills, near_misses, bosses_killed` become forwarding properties (get **and** set for now, so nothing else changes in this PR).
4. `main.gd` `add_xp`, `xp_need`, `kill_xp_k`, `continue_mult` move into `RunState`; `Main` keeps thin wrappers.
5. Unit tests: reward per kind; "every 2nd" counter shared across ground/convoy/transport; dogfight/rescue/class_task always rare; `continue_mult` applied exactly once; XP: level-ups from a known XP sum; `grant_rare_pick` appends the reason.
Done when: unit, smoke all, full autotest green; autotest summary within the same ranges as `main`.

## PR 2 — Rewards in one place

Files: `main.gd` (`on_activity_success`, `refill_offers` parts), `transport.gd`, `rescue.gd`, `class_task.gd`, `cards.gd:983`, `pickups.gd:73`, `aa_site.gd`/`convoy.gd`/`rival_ace.gd` (emit), `main_input.gd:109`, `main_debug.gd` (debug writes → `run.debug_set`).

1. Every activity emits `Events.activity_succeeded(&"kind")` / `activity_failed(...)` instead of calling Main or writing fields.
2. `RunState` subscribes to `activity_succeeded` and calls `award_activity(kind)`; `Main` subscribes after it and shows the banner built from the returned dictionary (fixes "+90" vs paid amount), story line, sound.
3. Card "Резерв: награда" and cargo pickups call `run.grant_parts(…)`.
4. Forwarding setters on `Main` removed for these fields → any leftover write is a parse error, found by smoke.
5. Add the smoke grep guard from the design.
Done when: the guard finds nothing; unit + smoke + full green; activity count and kinds in the autotest summary unchanged.

## PR 3 — Combat events

Files: `enemy.gd` (`take_hit`, `_die`), `convoy_vehicle.gd` (`_die`), `player.gd` (damage, death, near miss), `spawner.gd` (boss wave, `note_kill` via signal), `class_task.gd` (`on_kill` via signal), `evac.gd`, `warship.gd`, `main.gd` handlers.

1. Emitters call `Events.enemy_hit/enemy_killed/player_damaged/player_died/near_miss/boss_wave/evac_*`.
2. `Main.on_*` handlers become private `_on_*` slots connected in `start_run`; `RunState.on_kill` takes over kills/streak/parts; Spawner, Player, ClassTask subscribe themselves.
3. `Enemy._die` and `ConvoyVehicle._die` share `_grant_rewards()` (review r2, important 5).
Done when: no `Main.I.on_` calls remain (grep); unit + smoke + full green; kills/level ranges unchanged.

## PR 4 — Banner and radio through the bus; cleanup

Files: ~40 callers of `Main.I.show_banner` / `m.show_banner`, 11 of `radio`, `hud*.gd`, `story.gd`; `docs/standards/architecture.md` (ADR-02 → accepted, done), `docs/standards/code.md` §6.

1. Callers emit `Events.banner(text, dur)` / `Events.radio(...)`; `Hud` owns banner/radio state (moved from `Main`); `Main.show_banner`/`radio` removed.
2. HUD, log and report read `m.run.*` directly; forwarding getters on `Main` removed.
3. Update the standards: event list, "emit, don't call Main" rule.
Done when: unit + smoke + full green; screenshots `--shots` show banners and radio as before.

## Order and timing

PR 1 → PR 2 → PR 3 → PR 4, each merged before the next. Estimate 2–3 days total. Coordinate with the code threads working in `main.gd`/`enemy.gd`/`spawner.gd`: rebase right before each PR, keep each PR within one day.
