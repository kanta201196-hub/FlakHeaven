#!/usr/bin/env bash
# Быстрая проверка правки: импорт проекта + один короткий вылет без окна (~30 с на класс).
# Запуск из корня репозитория: tools/ci/smoke.sh [fighter|attacker|bomber|all]
# «all» — три класса одновременно после одного импорта (~40 с вместо ~100 с по очереди).
# Падает сразу при первой SCRIPT ERROR / Parse Error или если вылет не дошёл до «SMOKE: ok».
# Полный автотест (--autotest --fast) — один раз перед готовым PR и только если менялся бой. Что нужно для ваших правок: tools/ci/pick.sh
set -uo pipefail
CLS="${1:-fighter}"
GODOT="${GODOT:-godot}"
LOG="${SMOKE_LOG:-smoke_${CLS}.log}"
ERR_RE="SCRIPT ERROR|Parse Error"

# CS-03: состояние вылета меняется только методами RunState — прямые записи в Main не пропускаем
if [ -z "${SMOKE_SKIP_IMPORT:-}" ]; then
	RS_RE='\b(m|Main\.I)\.(parts|pending_levels|rare_picks|rare_reasons|activities_done|kills|level|xp|streak|streak_t|best_streak|near_misses|tail_kills|bosses_killed)\s*([-+*/]?=[^=]|\.(append|clear|pop_front|erase))'
	if grep -rnE "$RS_RE" game/scripts --include=*.gd | grep -v "game/scripts/run_state.gd"; then
		echo "smoke: прямая запись в состояние вылета — используйте методы RunState (docs/standards/code.md §6)"; exit 1
	fi
fi

if [ -z "${SMOKE_SKIP_IMPORT:-}" ]; then
	"$GODOT" --headless --path game --import >import.log 2>&1
	if grep -E "$ERR_RE" import.log; then
		echo "smoke: ошибки при импорте (import.log)"; exit 1
	fi
fi

if [ "$CLS" = all ]; then
	pids=()
	for c in fighter attacker bomber; do
		SMOKE_SKIP_IMPORT=1 SMOKE_LOG="smoke_$c.log" "$0" "$c" >"smoke_$c.out" 2>&1 &
		pids+=($!)
	done
	fail=0
	for p in "${pids[@]}"; do wait "$p" || fail=1; done
	cat smoke_fighter.out smoke_attacker.out smoke_bomber.out
	rm -f smoke_fighter.out smoke_attacker.out smoke_bomber.out
	[ $fail -eq 0 ] && echo "smoke: все три класса ok" || echo "smoke: FAIL"
	exit $fail
fi

# VFX-01: SMOKE_RENDER=forward_plus runs the sortie with a real Forward+ renderer (GPU effects are off in
# headless mode). Without a GPU it needs xvfb and Mesa lavapipe: apt-get install mesa-vulkan-drivers; slow (minutes).
if [ "${SMOKE_RENDER:-}" = forward_plus ]; then
	ICD=/usr/share/vulkan/icd.d/lvp_icd.json
	[ -f "$ICD" ] && [ -z "${VK_ICD_FILENAMES:-}" ] && export VK_ICD_FILENAMES="$ICD"
	xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path game --rendering-method forward_plus -- --autotest --smoke --turbo --god --class="$CLS" >"$LOG" 2>&1 &
else
	"$GODOT" --headless --path game -- --autotest --smoke --turbo --god --class="$CLS" >"$LOG" 2>&1 &
fi
pid=$!
# следим за логом: при первой ошибке скрипта останавливаем только свой процесс Godot
while kill -0 "$pid" 2>/dev/null; do
	if grep -qE "$ERR_RE" "$LOG"; then
		kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
		grep -m3 -nE -A4 "$ERR_RE" "$LOG"
		echo "smoke: SCRIPT ERROR ($CLS), лог $LOG"; exit 1
	fi
	sleep 2
done
wait "$pid"; code=$?
grep -E "^(SMOKE|AUTOTEST: class)" "$LOG"
if grep -m3 -nE -A4 "$ERR_RE" "$LOG"; then
	echo "smoke: SCRIPT ERROR ($CLS), лог $LOG"; exit 1
fi
if [ $code -ne 0 ] || ! grep -q "^SMOKE: ok" "$LOG"; then
	echo "smoke: вылет не завершился (код $code), хвост $LOG:"; tail -40 "$LOG"; exit 1
fi
echo "smoke: $CLS ok"
