# Steam integration plan (needs Kanta's "yes" before any code)

Draft 2026-11-02. This is a new system boundary (`architecture.md`), so per CLAUDE.md it waits for a "yes". It touches no gameplay rule, balance or visuals.

## Goal
The Steam build starts through Steamworks, shows the Steam overlay, saves to Steam Cloud, and can grant achievements; the game still runs without Steam (tester builds, itch.io, dev).

## Pieces
1. **Wrapper `SteamBridge`** (autoload, one file): `available`, `init()`, `unlock(achievement_id)`, `open_store()`, `set_rich_presence()`. Everything else calls this wrapper; nothing else touches the Steam API. If the plugin or Steam client is missing, every call is a no-op.
2. **GodotSteam plugin** (GDExtension build for Godot 4.4). **[verify]** the exact release that supports 4.4.1 on the GodotSteam site before choosing it; not checked yet. Windows x86_64 only at first. Licence (MIT) goes to `game/models/CREDITS.md`-style credits.
3. **Steam Cloud**: Steamworks "Auto-Cloud" on `user://` save files, configured in the Steamworks Cloud tab (Kanta clicks), no code. The demo and the game keep the same project name so they share the folder (`docs/demo-next-fest.md` §5).
4. **Wishlist / store button**: `Demo.STEAM_APP_ID` already opens `steam://store/<id>`; with the overlay use `SteamBridge.open_store()`.
5. **Achievements**: later, from the medals system (MD-01), only after the list is approved; not for the demo.
6. **Dev run**: `steam_appid.txt` next to the exe (git-ignored), never in the depot.
7. **Release preset**: "Windows Release" with feature `release` (done 2026-11-02).

## Tests
Unit tests for `SteamBridge` with the plugin absent (all no-ops, no errors). `smoke.sh all` must still pass without Steam. A real check with the Steam client is only possible on Kanta's PC after the App ID exists.

## Order
1. Kanta's "yes" and the App ID (after Valve approval).
2. Wrapper + no-op tests, PR.
3. Plugin in a branch, run on Kanta's PC with `steam_appid.txt`.
4. Auto-Cloud setup in Steamworks; upload test build to a non-default branch with `tools/steam/upload.sh`.
