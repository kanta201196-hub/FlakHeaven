#!/usr/bin/env bash
# Pre-publish audio check for a reel (mp4): loudness, true peak, sync to cuts, dead air, spectrum.
# Why: replaces "listen and hope" before a post goes out; uses earshot (MIT, CPU only, free).
# Usage: check_reel.sh REEL.mp4        EARSHOT=/path/to/earshot (default: earshot on PATH)
# Install once (needs uv + ffmpeg): uv tool install "earshot @ git+https://github.com/Leonxlnx/earshot" && earshot doctor --fetch
# NOTE: do not `pip install earshot` - that PyPI name is a different project.
set -euo pipefail
f="${1:?usage: check_reel.sh REEL.mp4}"
E="${EARSHOT:-earshot}"
out="$("$E" critique "$f" --video "$f")"
echo "$out" | sed -n '/^VERDICT/p'
bad="$(echo "$out" | grep -E '^\s+(loudness|music|sync|arc|ending|density|spectrum|stereo|realness)\s' | grep -v ' ok$' || true)"
if [ -n "$bad" ]; then echo "OUT OF RANGE:"; echo "$bad"; else echo "All scored metrics in range."; fi
echo "$out" | grep -E 'FIX FIRST' -A6 || true
echo "--- key numbers"
echo "$out" | grep -E 'integrated loudness|true peak|onset on visual|dead air at the end'
