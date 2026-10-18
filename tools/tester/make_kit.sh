#!/usr/bin/env bash
# Собирает комплект тестера для сборки: tools/tester/make_kit.sh <папка со сборкой> [номер сборки]
# В папке сборки появятся: SHA256SUMS.txt, SAFETY_NOTE_ru.txt, INSTRUCTIONS_*.txt, TESTER_NOTE.txt
# (записка с номером сборки, суммами и ссылками VirusTotal по хэшу). Сами архивы не меняются.
# Запускает тред сборки сразу после экспорта. Наружу ничего не отправляет.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:?укажите папку со сборкой, например /mnt/project-files/builds/3.5-s7}"
build="${2:-$(basename "$dir")}"
"$here/make_checksums.sh" "$dir" >/dev/null
cp "$here/SAFETY_NOTE_ru.txt" "$here"/INSTRUCTIONS_*.txt "$dir"/
{
  echo "FLAK HEAVEN — тестовая сборка $build"
  echo "Дата комплекта: $(date -u +%Y-%m-%d)"
  echo
  echo "Что внутри: архивы для Windows и Mac, контрольные суммы, инструкция, записка о безопасности."
  [ -f "$dir/WHATS_NEW.md" ] && echo "Что нового: WHATS_NEW.md" || true
  echo
  echo "Контрольные суммы SHA-256 (проверка — см. SAFETY_NOTE_ru.txt):"
  while read -r sum name; do
    name="${name#\*}"
    echo "  $name"
    echo "    $sum"
    echo "    VirusTotal по хэшу: https://www.virustotal.com/gui/file/$sum"
  done < "$dir/SHA256SUMS.txt"
  echo
  echo "Ссылка VirusTotal открывается с результатом, если файл уже проверяли;"
  echo "иначе загрузите архив на virustotal.com сами — хэш у вас совпадёт."
  echo "Отчёт тестера отправляется кнопкой в игре; имён, почты и личных файлов игра не собирает."
  echo "Если сумма не совпала — не запускайте и напишите нам."
} > "$dir/TESTER_NOTE.txt"
echo "Комплект готов в $dir:"; ls "$dir"
