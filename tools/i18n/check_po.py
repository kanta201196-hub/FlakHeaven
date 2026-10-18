#!/usr/bin/env python3
"""Проверка файла перевода против кода.

  python3 tools/i18n/check_po.py game/locale/en.po

Печатает: строки из кода без перевода, переводы строк, которых в коде уже нет,
и переводы с другими %d / %s / \\n, чем в оригинале (такие сломают вывод).
Код выхода 1 — если есть ошибки в подстановках.

  python3 tools/i18n/check_po.py game/locale/en.po --sync
пересобирает файл по коду: переводы сохраняются, новые строки добавляются
с пустым msgstr (в игре они остаются русскими), строк, которых нет в коде, больше нет.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scan_strings  # noqa: E402

PH = re.compile(r"%[-+0#]*\d*(?:\.\d+)?[dsfix%]|\\n")
ENTRY = re.compile(r'^msgid "((?:[^"\\]|\\.)*)"\nmsgstr "((?:[^"\\]|\\.)*)"', re.M)


def load(path: Path) -> dict:
	return {m.group(1): m.group(2) for m in ENTRY.finditer(path.read_text(encoding="utf-8")) if m.group(1)}


def sync(path: Path, po: dict):
	tmp = path.with_suffix(".pot.tmp")
	scan_strings.write_pot(scan_strings.scan()[0], tmp)
	text = tmp.read_text(encoding="utf-8")
	tmp.unlink()
	head = path.read_text(encoding="utf-8").split("\n\n", 1)[0]
	body = text.split("\n\n", 1)[1]
	body = ENTRY.sub(lambda m: f'msgid "{m.group(1)}"\nmsgstr "{po.get(m.group(1), "")}"', body)
	path.write_text(head + "\n\n" + body, encoding="utf-8")


def main():
	po = load(Path(sys.argv[1]))
	if "--sync" in sys.argv:
		sync(Path(sys.argv[1]), po)
		po = load(Path(sys.argv[1]))
	rows, _ = scan_strings.scan()
	code = {s for f, n, s in rows if Path(f).name not in scan_strings.DEBUG}
	missing = sorted(code - po.keys())
	extra = sorted(po.keys() - code)
	bad = [(k, v) for k, v in po.items() if v and PH.findall(k) != PH.findall(v)]
	empty = [k for k, v in po.items() if not v]
	print(f"в коде {len(code)}, в переводе {len(po)} (пустых {len(empty)}), нет перевода {len(missing)}, лишних {len(extra)}, ошибок подстановки {len(bad)}")
	for s in missing[:40]:
		print("  нет перевода:", s)
	for s in extra[:20]:
		print("  лишний:", s)
	for k, v in bad:
		print(f"  ПОДСТАНОВКА: {k!r} → {v!r}")
	sys.exit(1 if bad else 0)


if __name__ == "__main__":
	main()
