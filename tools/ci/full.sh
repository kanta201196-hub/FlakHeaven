#!/usr/bin/env bash
# Полный автотест: бот летает вылет за вылетом (классы по очереди) и сам заканчивает после RUNS вылетов.
# Запуск из корня репозитория: tools/ci/full.sh
# Настройки (переменные окружения):
#   RUNS=6        вылетов на каждую операцию (классы идут по кругу: 6 = каждый класс дважды)
#   OPS="1"       операции через пробел, каждая — свой процесс параллельно (1 — Нагорье «Перевал», 5 — Архипелаг «Пролив»)
#   FIXED_FPS=    если задано (например 60) — шаг кадра фиксирован, игра идёт так быстро, как тянет процессор
#   WALL=3600     предел по реальному времени на процесс, с
# Падает сразу при первой SCRIPT ERROR / Parse Error, иначе ждёт «AUTOTEST: done» от каждого процесса.
set -uo pipefail
GODOT="${GODOT:-godot}"
RUNS="${RUNS:-6}"
OPS="${OPS:-1}"
WALL="${WALL:-3600}"
ERR_RE="SCRIPT ERROR|Parse Error"
pre=()
[ -n "${FIXED_FPS:-}" ] && pre=(--fixed-fps "$FIXED_FPS")
t0=$(date +%s)

"$GODOT" --headless --path game --import >import.log 2>&1
if grep -E "$ERR_RE" import.log; then
	echo "full: ошибки при импорте (import.log)"; exit 1
fi

pids=()
logs=()
for op in $OPS; do
	log="full_op${op}.log"
	timeout "$WALL" "$GODOT" --headless --path game "${pre[@]}" -- --autotest --fast --god --op="$op" --runs="$RUNS" >"$log" 2>&1 &
	pids+=($!)
	logs+=("$log")
done

stop_all() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; }
# следим за логами: при первой ошибке скрипта останавливаем свои процессы Godot
while :; do
	for log in "${logs[@]}"; do
		if grep -qE "$ERR_RE" "$log"; then
			stop_all
			grep -m3 -nE -A4 "$ERR_RE" "$log"
			echo "full: SCRIPT ERROR, лог $log ($(( $(date +%s) - t0 )) с)"; exit 1
		fi
	done
	alive=0
	for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
	[ $alive -eq 0 ] && break
	sleep 2
done

fail=0
for i in "${!pids[@]}"; do
	wait "${pids[$i]}"; code=$?
	log="${logs[$i]}"
	grep -E "^AUTOTEST: (operation|evac|dead|done)" "$log" | cut -c1-120
	if grep -qE "$ERR_RE" "$log"; then
		grep -m3 -nE -A4 "$ERR_RE" "$log"; fail=1
	elif [ $code -ne 0 ] || ! grep -q "^AUTOTEST: done" "$log"; then
		echo "full: $log — автотест не закончился (код $code), хвост:"; tail -20 "$log"; fail=1
	fi
done
[ $fail -ne 0 ] && { echo "full: FAIL ($(( $(date +%s) - t0 )) с)"; exit 1; }
echo "full: ok, операции $OPS по $RUNS вылетов, $(( $(date +%s) - t0 )) с"
