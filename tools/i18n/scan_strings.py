#!/usr/bin/env python3
"""Опись текстов игры для перевода.

Ищет в game/scripts и game/scenes строки с русскими буквами и печатает:
сколько строк в каждом файле, сколько слов всего и какие строки код
сравнивает (== / !=) — такие нельзя просто обернуть в tr(), их сначала
меняют на латинские ключи.

Запуск из корня репозитория:
  python3 tools/i18n/scan_strings.py            # сводка по файлам
  python3 tools/i18n/scan_strings.py --csv out.csv  # таблица строк: файл, строка, текст
"""
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRS = [ROOT / "game" / "scripts", ROOT / "game" / "scenes"]
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
CYR = re.compile(r"[А-Яа-яЁё]")
CMP = re.compile(r'(?:==|!=)\s*"((?:[^"\\]|\\.)*)"|"((?:[^"\\]|\\.)*)"\s*(?:==|!=)')


def scan():
	rows, cmps = [], []
	for d in DIRS:
		for p in sorted(list(d.rglob("*.gd")) + list(d.rglob("*.tscn"))):
			rel = p.relative_to(ROOT).as_posix()
			for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
				code = line.split("#", 1)[0] if p.suffix == ".gd" and not line.lstrip().startswith('"') else line
				if line.lstrip().startswith("#"):
					continue
				for m in STR.finditer(code):
					if CYR.search(m.group(1)):
						rows.append((rel, n, m.group(1)))
				for m in CMP.finditer(code):
					s = m.group(1) or m.group(2) or ""
					if CYR.search(s):
						cmps.append((rel, n, s))
	return rows, cmps


def main():
	rows, cmps = scan()
	if "--csv" in sys.argv:
		out = Path(sys.argv[sys.argv.index("--csv") + 1])
		with out.open("w", encoding="utf-8", newline="") as f:
			w = csv.writer(f)
			w.writerow(["file", "line", "ru"])
			w.writerows(rows)
		print(f"записано {len(rows)} строк в {out}")
		return
	per = {}
	for r in rows:
		per[r[0]] = per.get(r[0], 0) + 1
	uniq = {r[2] for r in rows}
	words = sum(len(s.split()) for s in uniq)
	print(f"строк с русским текстом: {len(rows)}, разных: {len(uniq)}, слов в разных: {words}")
	print("\nпо файлам:")
	for f, c in sorted(per.items(), key=lambda x: -x[1]):
		print(f"  {c:5d}  {f}")
	print(f"\nрусский текст как ключ в сравнениях ({len(cmps)}): сначала заменить на латинские ключи")
	for f, n, s in cmps:
		print(f"  {f}:{n}  \"{s}\"")


if __name__ == "__main__":
	main()
