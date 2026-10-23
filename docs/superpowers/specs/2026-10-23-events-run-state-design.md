# Design: event bus and RunState (ADR-02)

Date: 2026-10-23. Status: **accepted by Kanta 2026-10-23, in progress**. Kanta chose signals (review question 2) and approach 1 "event bus + RunState" (thread "Ревью кода и стандарты разработки", 2026-10-23). Plan — [../plans/2026-10-23-events-run-state.md](../plans/2026-10-23-events-run-state.md).

## Problem

`Main` holds the whole sortie state (level, XP, parts, card queue, kills, activities) and 46 files reach it through `Main.I`. About 85 % of uses are service calls (sound 89, player 86, projectiles 81, fx 67, telemetry 48) — those are fine. The trouble is the rest:

- **Rewards are written in five places**, each with its own arithmetic: `Main.on_activity_success`, `Transport._die`, `Rescue._success`, `ClassTask` (`class_task.gd:46-49`), cards and pickups (`Main.I.parts += …`). The transport banner says "+90 parts" but pays `90 × continue_mult`.
- **Sortie state is written from outside** (`m.pending_levels += 1`, `m.rare_picks += 1`, `m.rare_reasons.append`, `m.activities_done += 1`) — this is how the empty card screen (CR-02) happened.
- **Events are direct calls into Main** (`on_enemy_killed`, `on_player_damaged`, `on_boss_wave`, …), so every new listener (telemetry, class task, hints, HUD) is wired by editing `Main`.

## Goal

1. One place decides rewards; activities only report "done".
2. Sortie state changes only through named `RunState` methods.
3. Gameplay events are signals on one bus; listeners subscribe, emitters don't know them.
4. **No gameplay or balance change.** Same numbers, same autotest behavior. The only visible change: banners show the amount actually paid.

Out of scope: service calls (`Main.I.sfx`, `.projectiles`, `.fx`, `.tele`, `.player`) stay direct; `render3d.gd`; UI drawing.

## Design

### `Events` — autoload `game/scripts/events.gd`

A `Node` with signals only, no state:

| Signal | Emitted by | Listeners (initially) |
| --- | --- | --- |
| `enemy_hit(enemy: Enemy, dmg: float)` | `Enemy.take_hit` | Main (spark, number, sound) |
| `enemy_killed(enemy: Enemy)` | `Enemy._die`, `ConvoyVehicle._die` | RunState (kills, parts, streak), Spawner, Player, ClassTask, Main (fx, evac, op flags) |
| `player_damaged(amount: float)` | `Player` | Main (shake, hitstop, sound, HUD flash, hint) |
| `player_died()` | `Player` | Main |
| `near_miss(kind: StringName)` | `Player` | RunState (streak), Main (fx, sound) |
| `activity_succeeded(kind: StringName)` | AA site, convoy, rival ace, transport, rescue, class task | RunState (reward), Main (story, banner, sound) |
| `activity_failed(kind: StringName, who: String)` | rival ace, transport, rescue | Main |
| `boss_wave(wave: int, count: int)` | Spawner | Main |
| `evac_reached()`, `evac_closed()`, `evac_point_lost(who: String)` | EvacZone, Warship | Main |
| `banner(text: String, duration: float)` | anyone (replaces `Main.I.show_banner`) | Hud |
| `radio(from: String, text: String, enemy: bool)` | anyone (replaces `Main.I.radio`) | Hud, Sfx |

Rules: signals in past tense, typed arguments, connected with Callables in `_ready`/`start_run`, disconnected automatically when the listener is freed (Godot does this for Object-bound Callables). Kinds are `StringName` ids (`&"ground"`, `&"convoy"`, `&"dogfight"`, `&"transport"`, `&"rescue"`, `&"class_task"`), not Russian text — a first step of CS-06.

### `RunState` — `game/scripts/run_state.gd`, `class_name RunState extends RefCounted`

Owned by `Main` (`Main.I.run`), recreated in `start_run`. Holds: `level`, `xp`, `pending_levels`, `rare_picks`, `rare_reasons`, `parts`, `parts_kept`, `kills`, `activities_done`, `streak`, `streak_t`, `best_streak`, `tail_kills`, `near_misses`, `bosses_killed`.

Methods (the only way to change these fields):
- `add_xp(v)` — the current curve, unchanged.
- `grant_parts(amount, reason: StringName) -> float` — applies `continue_mult` once, returns the paid amount (for banners and log).
- `grant_rare_pick(reason_label: String)` — `pending_levels += 1`, `rare_picks += 1`, appends the reason.
- `award_activity(kind) -> Dictionary` — reads the reward table, applies parts / rare pick / repair / course points, returns what was paid so the banner text is built from it.
- `on_kill(enemy)` — kills, streak, parts from the kill (the current formula).

### Reward table — `game/scripts/balance/rewards.gd` (ADR-04)

One table, numbers copied as they are today:

| Kind | Parts | Rare pick | Otherwise |
| --- | --- | --- | --- |
| `ground` | 40 always + 60 when not rare | every 2nd activity | repair 20 % |
| `convoy` | 60 when not rare | every 2nd | repair 20 % |
| `dogfight` | — | always | — |
| `transport` | 90 + 3 repair kits dropped | every 2nd | — |
| `rescue` | 40 | always | — |
| `class_task` | `ClassTask.PARTS` | always | — |

Course points +1 for every kind (as today).

### Migration without breaking readers

During the move `Main` keeps read-only forwarding properties (`var parts: float: get: return run.parts`) so HUD, log, report and telemetry keep working untouched; they are switched to `m.run.*` when touched. Writing through `Main` is removed in the same PR that moves each field.

### Guard

`tools/ci/smoke.sh` gets a grep check: outside `run_state.gd`, lines matching `(m|Main\.I)\.(parts|pending_levels|rare_picks|rare_reasons|activities_done|kills|level|xp)\s*([+-]?=|\.append)` fail the smoke run. That keeps agents from reintroducing direct writes. `main_debug.gd` uses a `debug_set(...)` method on `RunState` instead.

## Testing

- **Unit (new, small):** `game/tests/run_state_test.gd` run headless via `tools/ci/unit.sh` (`godot --headless --path game -s res://tests/run_state_test.gd`, plain asserts, no framework): reward table per kind, every-2nd rule, `continue_mult` applied once, XP curve level-ups, `grant_rare_pick` queue.
- **Smoke** all three classes after every PR; **full autotest** once per PR (combat files change).
- **Behavior equivalence:** before/after each PR, compare autotest summary lines (`AUTOTEST: activity success …`, `SMOKE: ok … level, kills`) — same activity kinds and comparable level/kills ranges (runs are not bit-exact, so ranges, not exact numbers).

## Risks

| Risk | Mitigation |
| --- | --- |
| Signal emitted while a listener is being freed between sorties | Listeners connect in `start_run`, `world` children die with the world; `Events` holds no state |
| Order of listeners changes results (e.g. parts counted before streak) | `RunState` subscribes first and does all state math in one handler; other listeners only react (fx, sound, UI) |
| Conflicts with other code threads (combat, game-design balance profile) | 4 small PRs, each merged the same day; rebase before each |
| Autotest prints that scripts parse | Keep the exact `AUTOTEST: …` strings, printed in one place |

## Cost (estimate)

4 PRs, 2–3 days of one strong-model thread including tests. Demo work loses one of the two strong-model slots for that time.
