#!/usr/bin/env bash
# Собирает комплект тестера для сборки: tools/tester/make_kit.sh <папка со сборкой> [номер сборки]
# В папке сборки появятся: SHA256SUMS.txt, SAFETY_NOTE_ru.txt / _en.txt, INSTRUCTIONS_*.txt (русские и *_en),
# TESTER_NOTE.txt (записка на русском и английском: номер сборки, суммы, ссылки VirusTotal по хэшу). Сами архивы не меняются.
# Запускает тред сборки сразу после экспорта. Наружу ничего не отправляет.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:?укажите папку со сборкой, например /mnt/project-files/builds/3.5-s7}"
build="${2:-$(basename "$dir")}"
"$here/make_checksums.sh" "$dir" >/dev/null
cp "$here"/SAFETY_NOTE_*.txt "$here"/INSTRUCTIONS_*.txt "$dir"/
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
  echo
  echo "------------------------------------------------------------"
  echo "FLAK HEAVEN — test build $build ($(date -u +%Y-%m-%d))"
  echo "Inside: Windows and Mac archives, checksums, instructions (INSTRUCTIONS_*_en.txt),"
  echo "safety note (SAFETY_NOTE_en.txt). Game language: Settings → Game → Language."
  echo "SHA-256 checksums and VirusTotal links are listed above (same for every language)."
  echo "If the checksum doesn't match, don't run the game and contact us."
  echo "The tester report is sent with a button in the game; it collects no names, emails or personal files."
} > "$dir/TESTER_NOTE.txt"
echo "Комплект готов в $dir:"; ls "$dir"
