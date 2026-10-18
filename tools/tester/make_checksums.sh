#!/usr/bin/env bash
# Считает SHA-256 для архивов тестовой сборки: tools/tester/make_checksums.sh <папка со сборкой>
# Результат — SHA256SUMS.txt в той же папке; приложить к раздаче вместе с SAFETY_NOTE_ru.txt.
set -euo pipefail
dir="${1:?укажите папку со сборкой, например /mnt/project-files/builds/3.5-s7}"
cd "$dir"
shopt -s nullglob
files=(*.zip)
[ ${#files[@]} -gt 0 ] || { echo "в $dir нет .zip" >&2; exit 1; }
sha256sum "${files[@]}" > SHA256SUMS.txt
cat SHA256SUMS.txt
