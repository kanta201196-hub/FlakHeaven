#!/usr/bin/env bash
# Balance run (GD-01, Kanta's decision of 2026-10-23): the bot plays N full 15-minute sorties as a demo player
# (plane lvl 1, hangar nodes lvl 2, crew lvl 5, weapon tier 1) and prints the metrics table (tools/ci/balance_table.py).
# Long run: one 15-minute sortie takes 6–15 min of real time in the cloud. Run from the repository root.
# Settings (environment variables):
#   OPS="1 2"       operations, each in its own parallel process (1 «Перевал», 2 «Сухое русло» — the demo operations)
#   RUNS=6          sorties per process (classes rotate: 6 = every class twice)
#   PAR=1           processes per operation (4 cloud cores: OPS="1 2" PAR=2 — four at once)
#   PROFILE=demo    demo — demo player profile; fresh — empty hangar
#   UNTIL=900       sortie length, s (no evacuation; deaths are counted, the sortie goes on)
#   OUT=balance_out folder for logs and per-process user:// data
#   WALL=14400      real-time limit per process, s
set -uo pipefail
GODOT="${GODOT:-godot}"
OPS="${OPS:-1 2}"
RUNS="${RUNS:-6}"
PROFILE="${PROFILE:-demo}"
UNTIL="${UNTIL:-900}"
OUT="${OUT:-balance_out}"
WALL="${WALL:-14400}"
PAR="${PAR:-1}"
ERR_RE="SCRIPT ERROR|Parse Error"
extra=()
[ "$PROFILE" = "demo" ] && extra=(--demo --profile=demo)
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"   # absolute: XDG_DATA_HOME must not depend on the working folder
"$GODOT" --headless --path game --import >"$OUT/import.log" 2>&1
pids=()
for op in $OPS; do
	for k in $(seq 1 "$PAR"); do
		id="op${op}_$k"
		rm -rf "$OUT/$id"; mkdir -p "$OUT/$id"
		# own XDG_DATA_HOME: every process gets a clean profile and its own sortie log (user://playtest_log_*.csv)
		XDG_DATA_HOME="$OUT/$id" timeout "$WALL" "$GODOT" --headless --path game --fixed-fps 60 -- --autotest --fast \
			--op="$op" --runs="$RUNS" --noevac --nodie --until="$UNTIL" "${extra[@]}" >"$OUT/$id.log" 2>&1 &
		pids+=($!)
	done
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
if grep -lE "$ERR_RE" "$OUT"/op*.log; then
	echo "balance: SCRIPT ERROR"; fail=1
fi
python3 tools/ci/balance_table.py "$OUT"/op*/godot/app_userdata/*/playtest_log_*.csv
exit $fail
