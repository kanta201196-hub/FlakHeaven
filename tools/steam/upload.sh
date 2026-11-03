#!/usr/bin/env bash
# Upload an exported build folder to Steam with SteamCMD. Run by Kanta on his PC (needs his Steam login + Steam Guard).
# Never builds or exports anything and never stores credentials: the password is typed into steamcmd itself.
#   STEAM_USER=<login> tools/steam/upload.sh <app_id> <depot_id> <build folder> [branch] [description]
# "branch" defaults to "" (nothing goes live: set the build live in the Steamworks Builds page). Use "default" only
# after the store build review. Dry run (prints the generated vdf, calls nothing): add DRY_RUN=1.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="${1:?app id}"; depot="${2:?depot id}"; content="${3:?folder with the exported build}"
branch="${4:-}"; desc="${5:-$(basename "$content") $(date -u +%Y-%m-%d)}"
user="${STEAM_USER:?set STEAM_USER to your Steamworks login}"
[ -d "$content" ] || { echo "no such folder: $content" >&2; exit 1; }
[ -f "$content/steam_appid.txt" ] && echo "WARNING: steam_appid.txt in the build folder is excluded from the depot (dev file)." >&2
out="$(mktemp -d)"
sed -e "s|@APP_ID@|$app|" -e "s|@DEPOT_ID@|$depot|" -e "s|@DESC@|$desc|" \
    -e "s|@OUT@|$out|" -e "s|@CONTENT@|$(cd "$content" && pwd)|" -e "s|@BRANCH@|$branch|" \
    "$here/app_build.vdf.tpl" > "$out/app_build.vdf"
if [ "${DRY_RUN:-}" = 1 ]; then cat "$out/app_build.vdf"; exit 0; fi
command -v steamcmd >/dev/null || { echo "steamcmd not found: https://developer.valvesoftware.com/wiki/SteamCMD" >&2; exit 1; }
steamcmd +login "$user" +run_app_build "$out/app_build.vdf" +quit
