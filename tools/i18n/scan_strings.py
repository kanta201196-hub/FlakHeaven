#!/usr/bin/env python3
"""Опись текстов игры для перевода.

Ищет в game/scripts и game/scenes строки с русскими буквами и печатает:
сколько строк в каждом файле, сколько слов всего и какие строки код
сравнивает (== / !=) — такие нельзя просто обернуть в tr(), их сначала
меняют на латинские ключи.

Запуск из корня репозитория:
  python3 tools/i18n/scan_strings.py            # сводка по файлам
  python3 tools/i18n/scan_strings.py --csv out.csv  # таблица строк: файл, строка, текст
  python3 tools/i18n/scan_strings.py --pot game/locale/messages.pot  # шаблон gettext для перевода

В шаблон не идут отладочные файлы (DEBUG ниже) и строки с пометкой `# i18n-skip`
(внутренние ключи по-русски: формы слов для поиска терминов, префиксы источников урона). Ключ перевода — русская фраза
как в коде, вместе с %d / %s: переводится шаблон, а числа подставляются после.
"""
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRS = [ROOT / "game" / "scripts", ROOT / "game" / "scenes"]
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
CYR = re.compile(r"[А-Яа-яЁё]")
# отладка и стенды — игрок их не видит, не переводим
DEBUG = {"main_debug.gd", "tuning.gd", "tuning_panel.gd", "visual_bench.gd", "boom_bench.gd", "perf.gd"}
CMP = re.compile(r'(?:==|!=)\s*"((?:[^"\\]|\\.)*)"|"((?:[^"\\]|\\.)*)"\s*(?:==|!=)')


def scan():
	rows, cmps = [], []
	for d in DIRS:
		for p in sorted(list(d.rglob("*.gd")) + list(d.rglob("*.tscn"))):
			rel = p.relative_to(ROOT).as_posix()
			for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
				code = line.split("#", 1)[0] if p.suffix == ".gd" and not line.lstrip().startswith('"') else line
				if line.lstrip().startswith("#") or "# i18n-skip" in line:
					continue
				for m in STR.finditer(code):
					if CYR.search(m.group(1)):
						rows.append((rel, n, m.group(1)))
				for m in CMP.finditer(code):
					s = m.group(1) or m.group(2) or ""
					if CYR.search(s):
						cmps.append((rel, n, s))
	return rows, cmps


def write_pot(rows, out: Path):
	refs: dict[str, list[str]] = {}
	for f, n, s in rows:
		if Path(f).name not in DEBUG:
			refs.setdefault(s, []).append(f"{f}:{n}")
	lines = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', '"Language: ru\\n"', ""]
	for s, rr in refs.items():
		lines.append("#: " + " ".join(rr[:6]))
		if "%" in s:
			lines.append("#, c-format")
		lines += [f'msgid "{s}"', 'msgstr ""', ""]
	out.parent.mkdir(parents=True, exist_ok=True)
	out.write_text("\n".join(lines), encoding="utf-8")
	print(f"шаблон: {len(refs)} строк в {out}")


def main():
	rows, cmps = scan()
	if "--pot" in sys.argv:
		write_pot(rows, Path(sys.argv[sys.argv.index("--pot") + 1]))
		return
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
