#!/usr/bin/env bash
# Build self-check (R-23): contact sheet of the hangar (every plane × weapon × lvl 1/3/5/modernised, the weapon store)
# and of combat (every plane in flight and close-ups of nozzles, muzzle points, stores, trails) to attach to a build.
# Run from the repository root:
#   tools/ci/selfcheck.sh [--gfx=0,2,3] [--out DIR] [--quick] [--compat] [--parts=hangar,combat] [--only=a,b]
#     --gfx      graphics presets, comma-separated (default 0,2,3)
#     --quick    one preset (2) — about a third of the time
#     --compat   GL Compatibility renderer (fast, what PCs without Vulkan see) instead of Forward+ via lavapipe
#     --parts    which parts to shoot (default both)
#     --only     keep jobs of these classes, planes («bomber_2»), sections (hangar/store/combat) or weapons
#     --out      output folder (default builds/selfcheck-<commit>); it gets the JPEGs, thumbs/, index.html,
#                manifest.json and logs/
# One Godot process per part and preset, one at a time (lavapipe start-up is slow, so each batches all its frames).
# Exit code 1 when a process fails, a frame is not captured or a log has a SCRIPT ERROR; automatic-check findings
# (floating parts, missing nodes) are listed on the page but do not fail the run. Needs xvfb-run, Pillow and, for
# Forward+, Mesa lavapipe (apt-get install mesa-vulkan-drivers). Forward+ takes about an hour per preset.
set -uo pipefail
[ -f game/project.godot ] || { echo "selfcheck: run from the repository root"; exit 2; }
GODOT="${GODOT:-godot}"
GFX="0,2,3"
OUT=""
COMPAT=0
PARTS="hangar,combat"
ONLY=""
while [ $# -gt 0 ]; do
	case "$1" in
		--gfx=*) GFX="${1#--gfx=}" ;;
		--quick) GFX="2" ;;
		--compat) COMPAT=1 ;;
		--parts=*) PARTS="${1#--parts=}" ;;
		--only=*) ONLY="${1#--only=}" ;;
		--out) OUT="${2:-}"; shift ;;
		--out=*) OUT="${1#--out=}" ;;
		*) echo "selfcheck: unknown argument $1"; exit 2 ;;
	esac
	shift
done
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
git diff --quiet HEAD -- game 2>/dev/null || COMMIT="$COMMIT+changes"
BUILD="$(sed -nE 's/^const BUILD := "([^"]+)".*/\1/p' game/scripts/main.gd)"
[ -n "$OUT" ] || OUT="builds/selfcheck-${COMMIT%%+*}"
mkdir -p "$OUT/logs" "$OUT/.work"
OUT="$(cd "$OUT" && pwd)"   # absolute: Godot gets it as a flag and runs from game/
ERR_RE="SCRIPT ERROR|Parse Error|SHADER ERROR"
if [ "$COMPAT" = 1 ]; then
	RENDER=(--rendering-driver opengl3)
	RENDERER="gl_compatibility"
else
	export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
	RENDER=(--rendering-method forward_plus)
	RENDERER="forward_plus (lavapipe)"
fi
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"   # lavapipe threads: leave cores for the rest of the machine
: >"$OUT/runs.tsv"
t_all=$(date +%s)

if [ -z "${SELFCHECK_SKIP_IMPORT:-}" ]; then
	echo "selfcheck: import"
	nice -n 10 timeout 1800 "$GODOT" --headless --path game --import >"$OUT/logs/import.log" 2>&1
	if grep -E "$ERR_RE" "$OUT/logs/import.log"; then
		echo "selfcheck: errors while importing ($OUT/logs/import.log)"; exit 1
	fi
fi

for g in ${GFX//,/ }; do
	for part in ${PARTS//,/ }; do
		log="logs/${part}_g${g}.log"
		# the hangar shots come from its own supersampled view: a small window renders faster;
		# combat frames are the window itself at 1920 × 1080, the gameplay camera at tilt 28 over «Перевал»
		res="640x360"
		extra=()
		if [ "$part" = combat ]; then
			res="1920x1080"
			extra=(--tilt=28 --op=1)
		fi
		[ -n "$ONLY" ] && extra+=(--selfcheck-only="$ONLY")
		wall=5400
		[ "$part" = combat ] && wall=7200   # ~100 s a frame at 1080p on lavapipe, 30 frames
		echo "selfcheck: $part, preset $g ($RENDERER)"
		t0=$(date +%s)
		# own user:// per process (code.md §9.4): no developer profile, no leftovers between parts
		XDG_DATA_HOME="$OUT/.work/xdg_${part}_g${g}" nice -n 10 timeout "$wall" \
			xvfb-run -a -s "-screen 0 ${res}x24" "$GODOT" --path game "${RENDER[@]}" --resolution "$res" -- \
			--visual --selfcheck="$part" --selfcheck-out="$OUT" --gfx="$g" "${extra[@]}" >"$OUT/$log" 2>&1
		code=$?
		secs=$(( $(date +%s) - t0 ))
		frames=$(grep -c "^SELFCHECK frame" "$OUT/$log")
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$part" "$g" "$secs" "$code" "$log" "$frames" >>"$OUT/runs.tsv"
		nerr=$(grep -cE "$ERR_RE" "$OUT/$log")
		echo "selfcheck: $part g$g — ${secs} s, $frames frames, exit $code, script errors $nerr"
	done
done

rm -rf "$OUT/.work"
python3 tools/ci/selfcheck_page.py "$OUT" --build "$BUILD" --commit "$COMMIT" --renderer "$RENDERER"
code=$?
echo "selfcheck: total $(( $(date +%s) - t_all )) s — $OUT/index.html"
exit $code
