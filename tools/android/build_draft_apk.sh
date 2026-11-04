#!/usr/bin/env bash
## Builds the Android draft APK from a throwaway copy of game/ whose textures are capped for
## phones (process/size_limit), so the PC project and its imports stay untouched.
## Needs: Godot 4.4.1 as $GODOT, Android export templates, Android SDK in Godot's editor
## settings (export/android/android_sdk_path) and a debug keystore. Cold import ~30-60 min.
## Usage: tools/android/build_draft_apk.sh [size_limit=1024] [work_dir=/tmp/fh_mobile]
set -euo pipefail
LIMIT="${1:-1024}"
WORK="${2:-/tmp/fh_mobile}"
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$WORK"
# keep WORK/game/.godot between runs: a second build only reimports what changed
rsync -a --delete --exclude .godot "$ROOT/game/" "$WORK/game/"
# cap every texture import; size_limit=0 (no cap) and missing keys both get the cap
find "$WORK/game" -name '*.import' -print0 | xargs -0 grep -lZ '^importer="texture"' | while IFS= read -r -d '' f; do
	if grep -q '^process/size_limit=' "$f"; then
		sed -i "s/^process\/size_limit=.*/process\/size_limit=$LIMIT/" "$f"
	fi
done
"$GODOT" --headless --path "$WORK/game" --import >"$WORK/import.log" 2>&1 || true
mkdir -p "$ROOT/export/android"
"$GODOT" --headless --path "$WORK/game" --export-debug "Android Draft" "$ROOT/export/android/FlakHeaven_draft.apk" >"$WORK/export.log" 2>&1
ls -la "$ROOT/export/android/FlakHeaven_draft.apk"
