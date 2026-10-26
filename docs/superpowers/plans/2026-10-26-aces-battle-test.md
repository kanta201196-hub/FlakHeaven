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
