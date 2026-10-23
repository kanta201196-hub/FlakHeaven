#!/usr/bin/env bash
# Юнит-тесты чистой логики (CS-03): RunState и таблица наград, без окна, ~5 с.
# Запуск из корня репозитория: tools/ci/unit.sh. Новый тест — файл game/tests/*_test.gd (extends SceneTree).
# Падает, если какой-то тест напечатал FAIL, упал с SCRIPT ERROR или вернул код не 0.
set -uo pipefail
GODOT="${GODOT:-godot}"
ERR_RE="SCRIPT ERROR|Parse Error|FAIL"
fail=0
for t in game/tests/*_test.gd; do
	name="res://tests/$(basename "$t")"
	out=$("$GODOT" --headless --path game -s "$name" 2>&1)
	code=$?
	echo "$out" | grep -E "UNIT:|$ERR_RE"
	if [ $code -ne 0 ] || echo "$out" | grep -qE "$ERR_RE"; then
		echo "unit: FAIL $name"; fail=1
	fi
done
[ $fail -eq 0 ] && echo "unit: ok"
exit $fail
