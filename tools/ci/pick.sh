#!/usr/bin/env bash
# Подсказка: какие проверки нужны для текущих правок (ничего не запускает).
# Запуск из корня репозитория: tools/ci/pick.sh [база, по умолчанию origin/main]
# Смотрит список изменённых файлов относительно базы и пишет, что гонять.
set -uo pipefail
BASE="${1:-origin/main}"
files=$( { git diff --name-only "$BASE"...HEAD 2>/dev/null; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
[ -z "$files" ] && { echo "pick: изменений нет — проверки не нужны"; exit 0; }

code=$(echo "$files" | grep -E '^game/.*\.(gd|tscn|tres|gdshader|cfg|godot)$|^game/project\.godot$' || true)
assets=$(echo "$files" | grep -E '^game/' | grep -vE '\.(gd|tscn|tres|gdshader|cfg)$|project\.godot$' || true)
combat=$(echo "$code" | grep -E 'game/scripts/(tuning|main|main_debug|player|enemy|boss|spawner|weapon|hardpoint|bullet|missile|plane_classes|fuel|tanker|transport)[a-z_0-9]*\.gd' || true)
view=$(echo "$code" | grep -E 'render3d|camera|hangar3d|boom3d|fx\.gd|background|\.gdshader|\.tscn' || true)

if [ -z "$code" ] && [ -z "$assets" ]; then
	echo "pick: правки только вне игры (docs/, tools/, тексты) — проверки игры не нужны"; exit 0
fi
if [ -z "$code" ]; then
	echo "pick: только ассеты (модели/текстуры/звук) — один раз: tools/ci/smoke.sh fighter (импорт + вылет). Полный автотест и кадры не нужны"; exit 0
fi
echo "pick: после каждой правки — tools/ci/smoke.sh fighter (один класс). Остальные два класса не гонять: их проверит GitHub."
[ -n "$combat" ] && echo "pick: менялся бой (файлы ниже) — перед готовым PR ОДИН раз полный автотест tools/ci/full.sh:" && echo "$combat" | sed 's/^/   /'
[ -n "$view" ] && echo "pick: менялся вид — кадры: xvfb-run godot --path game --rendering-driver opengl3 -- --autotest --shots (только если нужен скриншот в PR)"
echo "$code" | grep -qE 'demo\.gd|export_presets' && echo "pick: менялось демо — ещё: godot --headless --path game -- --autotest --smoke --turbo --god --class=fighter --demo"
[ -n "$combat" ] || echo "pick: бой не менялся — полный автотест не нужен"
echo "pick: перед сборкой — лист самопроверки tools/ci/selfcheck.sh (R-23, ~1 ч на пресет; --quick — один пресет)"
exit 0
