#!/usr/bin/env bash
## Builds the Android draft APK from a throwaway copy of game/ whose textures are capped for
## phones (process/size_limit), so the PC project and its imports stay untouched.
## Needs: Godot 4.4.1 as $GODOT, Android export templates, Android SDK in Godot's editor
## settings (export/android/android_sdk_path) and a debug keystore. Cold import ~30-60 min.
## Usage: tools/android/build_draft_apk.sh [size_limit=1024] [work_dir=/tmp/fh_mobile]
## Env: CAPS="dir:px ..." per-folder caps under game/; LOW_QUALITY=0 keeps high_quality textures.
set -euo pipefail
LIMIT="${1:-1024}"
WORK="${2:-/tmp/fh_mobile}"
GODOT="${GODOT:-godot}"
# Per-folder caps, "dir:px", applied in order (later wins). Models are 100-300 px on a phone
# screen; turret paint variants alone were ~70 % of all texture bytes at full size.
CAPS="${CAPS:-models:512 models/turrets:256}"
# 1 = turn off high_quality (ASTC 4x4, 1 byte/px) so textures use ETC2 (0.5-1 byte/px)
LOW_QUALITY="${LOW_QUALITY:-1}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$WORK"
# keep WORK/game/.godot between runs: a second build only reimports what changed
mkdir -p "$WORK/game"
find "$WORK/game" -mindepth 1 -maxdepth 1 ! -name .godot -exec rm -rf {} +
tar -C "$ROOT/game" --exclude=./.godot -cf - . | tar -C "$WORK/game" -xf -
# cap every texture import that has the key (an empty .import gets defaults on import, uncapped)
find "$WORK/game" -name '*.import' -print0 | xargs -0 grep -lZ '^importer="texture"' | while IFS= read -r -d '' f; do
	if grep -q '^process/size_limit=' "$f"; then
		sed -i "s/^process\/size_limit=.*/process\/size_limit=$LIMIT/" "$f"
	fi
done
for c in $CAPS; do
	find "$WORK/game/${c%%:*}" -name '*.import' -exec sed -i "s/^process\/size_limit=.*/process\/size_limit=${c##*:}/" {} +
done
if [ "$LOW_QUALITY" = 1 ]; then
	find "$WORK/game" -path "$WORK/game/.godot" -prune -o -name '*.import' -exec sed -i 's/^compress\/high_quality=true/compress\/high_quality=false/' {} +
fi
"$GODOT" --headless --path "$WORK/game" --import >"$WORK/import.log" 2>&1 || true
mkdir -p "$ROOT/export/android"
"$GODOT" --headless --path "$WORK/game" --export-debug "Android Draft" "$ROOT/export/android/FlakHeaven_draft.apk" >"$WORK/export.log" 2>&1
ls -la "$ROOT/export/android/FlakHeaven_draft.apk"
