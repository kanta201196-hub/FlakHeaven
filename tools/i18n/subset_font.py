#!/usr/bin/env python3
"""Китайский шрифт для игры (L-05): Noto Sans SC, урезанный до знаков из перевода.

  python3 tools/i18n/subset_font.py [путь к NotoSansSC[wght].ttf]

Полный шрифт (~17 МБ, SIL OFL 1.1) в репозиторий не кладём: скрипт сам скачивает его
с github.com/google/fonts (или берёт указанный файл), делает обычное начертание (вес 400)
и оставляет только знаки из msgstr в game/locale/zh_CN.po + латиницу и цифры.
Результат — game/fonts/noto_sans_sc_subset.ttf. Запускать после каждой правки zh_CN.po:
иероглиф, которого нет в урезанном шрифте, в игре покажется пустым квадратом.
Нужен fontTools: python3 -m pip install fonttools
"""
import re
import sys
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[2]
PO = ROOT / "game" / "locale" / "zh_CN.po"
OUT = ROOT / "game" / "fonts" / "noto_sans_sc_subset.ttf"
URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
CACHE = Path("/tmp/NotoSansSC-wght.ttf")


def main():
	src = Path(sys.argv[1]) if len(sys.argv) > 1 else CACHE
	if not src.exists():
		print("качаю", URL)
		urllib.request.urlretrieve(URL, src)
	text = "".join(m.group(1) for m in re.finditer(r'^msgstr "((?:[^"\\]|\\.)*)"', PO.read_text(encoding="utf-8"), re.M))
	# латиница, цифры, знаки — на случай, если основной шрифт их не нарисует рядом с иероглифами
	chars = set(text) | {chr(c) for c in range(0x20, 0x7F)} | set("“”‘’…—–·×→←↑↓、。，：；？！（）《》「」【】％＋－")
	font = instancer.instantiateVariableFont(TTFont(src), {"wght": 400})
	opts = subset.Options()
	opts.layout_features = ["*"]
	opts.name_IDs = ["*"]
	opts.notdef_outline = True
	sub = subset.Subsetter(opts)
	sub.populate(text="".join(sorted(chars)))
	sub.subset(font)
	font.save(OUT)
	print(f"{len(chars)} знаков → {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} КБ)")


if __name__ == "__main__":
	main()
