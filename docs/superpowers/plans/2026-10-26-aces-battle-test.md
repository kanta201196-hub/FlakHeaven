# «Битва асов» test mode — plan

Kanta 2026-10-26: option 1 of thread «Продумать режим «Битва асов»» — a hidden test mode, judged by feel.
Backlog: AB-01. Later the game is meant to have two modes, campaign and «Битва асов» (PvE, PvP later);
PvP is not part of this plan (decided after early access).

## What the mode is

- Main menu item «БИТВА АСОВ · ТЕСТ» (not in the demo build). Always «Оса» with the hangar setup
  (gun, ammo, starting weapons, modules). Нагорье.
- Enemies: only a few interceptors and more missile carriers; a rival ace (the existing «Догфайт» `RivalAce`)
  every ~45 s, up to two at once. No drones, bombers, ace waves, «Крепость», activities, convoys, evacuation.
- Flight: more inertia (×2.5), more speed lost in a hard turn (×2), wider turns (turn rate ×0.8),
  speed ×1.3 for the player and interceptors (the rival ace follows the player's cruise speed already),
  camera a little further out (×0.85).
- «Realistic» damage: the player dies from 3 missiles or about 8 bullets (two long bursts of an ace);
  shots are not swallowed by the 0.7 s post-hit invulnerability (0.05 s instead). Enemies have fixed HP:
  interceptor ≈ 1.5 missiles of «Оса» (45) or one long gun burst, carrier 2 missiles, rival ace 3 missiles or
  two long bursts. No HP ramp, no «напряжение боя», no difficulty multipliers.
- No XP cards, no fuel burn, no profile award (parts, crew XP) and no campaign progress: the hangar setup is the
  build, and the test cannot be farmed. The sortie ends with death or «Покинуть вылет»; the HUD and the result
  screen count aces shot down.

## Where it lives

1. `game/scripts/balance/aces_mode.gd` (`AcesBalance`): all numbers + pure rules (TDD,
   `game/tests/aces_mode_test.gd`): `player_hit(source, amount, max_hp)`, `ace_due(t, next_t, alive)`,
   `needs(kind, alive)` (spawn caps).
2. `Main.mode` (`"campaign"` / `"aces"`), `Main.aces()`; menu item → `ui_click("menu_aces")`; mode resets on menu,
   «В вылет» and hangar; restart keeps it. `start_run` skips story, class task, campaign banner/hints.
3. `Spawner._aces_tick` replaces the campaign spawn rules while the mode is on.
4. Flight multipliers in `Player.cruise_speed / turn_rate_free`, `PlayerFlight._move`, camera zoom in `Main`.
5. `Player.damage`: `AcesBalance.player_hit` instead of difficulty and late-fight ramps.
6. HUD goal rows and the result screen subtitle for the mode. Strings through `Loc.t` + `en.po` / `zh_CN.po`.

## Checks

`tools/ci/unit.sh`, `tools/ci/smoke.sh all` (campaign unchanged), a headless aces run (`--aces` flag starts
the mode for checks), `tools/ci/full.sh` once (combat code changed).

## Turn feel from Sky Knights gameplay (2026-10-26, Kanta «да» with a little slide, PR #437)

Frames of a Sky Knights tutorial sortie (720p, plane ≈ 25 px, so angles are estimates): the plane banks to
about 60° (never fully on its side), rolls in within ~0.3 s and out in ~0.8 s; turns ≈ 100°/s with no slide,
the nose always along the path; speed drops 10–20 % in a hard turn; one thin white contrail from the tail,
always on, lives 3+ s, so whole arcs stay on screen; camera far (plane 3–4 % of screen height), north-up,
leads the plane, constant zoom; low semi-transparent clouds sell speed.

Our mode before this: bank shown ≈ 32°, same rate in and out; turn 168°/s; inertia ×2.5 (a visible slide);
contrail 1.2–1.8 s. Change, aces mode only: `AcesBalance.BANK_VIS` 60°, `BANK_IN_RATE` / `BANK_OUT_RATE`,
`TRAIL_LIFE` 3.5 s, `TURN_K` 0.5 (≈ 105°/s), `INERTIA_K` 1.4 (Kanta 26.10: «как у них, но немного скольжения»;
≈ 0.2 s catch-up instead of 0.36 s; the weight stays mostly in `BLEED_K`).
Camera (already north-up with look-ahead) and zoom unchanged.
All seven numbers are F1 sliders `aces_*` in `Tuning` (defaults from `AcesBalance`); in the aces mode F1 opens
just those sliders, also in the tester build, so Kanta tunes the feel himself.
