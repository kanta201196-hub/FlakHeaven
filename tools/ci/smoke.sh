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

"$GODOT" --headless --path game -- --autotest --smoke --turbo --god --class="$CLS" >"$LOG" 2>&1 &
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
