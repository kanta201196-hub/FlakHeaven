# Steam upload tools

Prepared 2026-11-02. Nothing here builds, exports or uploads by itself.

1. Export is done only on Kanta's direct command (CLAUDE.md rule 3): preset **Windows Release** (`game/export_presets.cfg`, feature `release`, output `export/win-release/FlakHeaven.exe`). The `release` feature turns the dev flags off (`Main.DEBUG`), like `tester` does. Demo: preset **Windows Demo**.
2. Upload: `STEAM_USER=<login> tools/steam/upload.sh <app_id> <depot_id> <build folder> [branch] [description]`. The password and Steam Guard code are typed into steamcmd by Kanta; nothing is stored. `DRY_RUN=1` prints the generated `app_build.vdf` only.
3. Default branch is empty, so the upload is not live until the build is set live on the Steamworks Builds page. Use `default` only after the store build review.
4. The demo is a separate App ID with its own depot: run the same script with the demo ids.
5. `steam_appid.txt` (dev only, next to the exe) is excluded from the depot.

App ID and depot ids appear in Steamworks after Valve approves the account (expected 16.11 to 01.12).
