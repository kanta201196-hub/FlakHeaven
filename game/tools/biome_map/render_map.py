"""Картинка карты расстановки биома из JSON biome_map.gd: зоны рельефа, объекты клеток, модели, сцены боёв.
python3 render_map.py map.json out.png [масштаб: px мира на пиксель картинки, по умолчанию 10] [заголовок]"""
import base64, json, sys
from PIL import Image, ImageDraw, ImageFont

src, dst = sys.argv[1], sys.argv[2]
S = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
TITLE = sys.argv[4] if len(sys.argv) > 4 else ""
d = json.load(open(src, encoding="utf-8"))
W, H, step = d["W"], d["H"], d["step"]
zone = base64.b64decode(d["zone"]); hts = base64.b64decode(d["h"])
ZC = {"river": (70, 120, 150), "road": (60, 45, 35), "bank": (120, 140, 90), "floor": (200, 180, 140),
      "fan": (180, 160, 125), "slope": (150, 130, 110), "crest": (170, 160, 150)}
names = d["zones"]
k = step / S
iw, ih = int(W * k), int(H * k)
base = Image.new("RGB", (W, H))
px = base.load()
for j in range(H):
    for i in range(W):
        z = names[zone[j * W + i]]
        c = ZC[z]
        if hts[j * W + i] > 0.85 * 255:   # снег шейдера — выше 85 % высоты
            c = (240, 242, 246)
        elif z in ("slope", "crest", "fan"):
            f = 0.75 + 0.45 * hts[j * W + i] / 255.0
            c = tuple(min(255, int(v * f)) for v in c)
        px[i, j] = c
im = base.resize((iw, ih), Image.NEAREST).convert("RGBA")
dr = ImageDraw.Draw(im, "RGBA")
x0, z0 = d["x0"], d["z0"]
def P(x, z): return ((x - x0) / S, (z - z0) / S)
# сетка клеток
C = 1400.0
for cx in range(int(W * step / C) + 1):
    dr.line([((cx * C) / S, 0), ((cx * C) / S, ih)], fill=(0, 0, 0, 40))
for cz in range(int(H * step / C) + 1):
    dr.line([(0, (cz * C) / S), (iw, (cz * C) / S)], fill=(0, 0, 0, 40))
PROP = {"poplar": ((40, 110, 40), 2), "orchard": ((70, 140, 50), 3), "shrub": ((95, 120, 60), 1.5),
        "boulders": ((110, 100, 95), 2), "outcrop": ((80, 70, 65), 4), "spire": ((60, 55, 55), 3),
        "yurt": ((245, 245, 235), 3), "sandbag": ((160, 140, 90), 3), "truck": ((40, 30, 30), 3),
        "tank": ((40, 30, 30), 3.5), "plane": ((20, 20, 20), 5)}
for kind, arr in d["props"].items():
    col, r = PROP.get(kind, ((255, 0, 255), 2))
    for x, z, w in arr:
        a, b = P(x, z)
        dr.ellipse([a - r, b - r, a + r, b + r], fill=col)
for it in d["scenes"]:
    if it["k"] in ("scorch", "crater"):
        a, b = P(*it["p"]); r = it["r"] / S
        dr.ellipse([a - r, b - r, a + r, b + r], fill=(30, 20, 15, 90))
OBJ = {"o_village": (230, 110, 60), "o_fort": (180, 40, 40), "o_oasis": (60, 170, 90), "o_crater": (60, 50, 40),
       "o_wreck": (20, 20, 20), "o_rocks_big": (90, 80, 75), "o_rocks_small": (110, 100, 95), "o_mesa": (140, 90, 160)}
F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
for o in d["objs"]:
    col = OBJ.get(o["name"], (255, 0, 255))
    rx, rz = P(*o["raw"])
    if o["pos"] is None:   # убран (не нашёл места у реки)
        dr.line([rx - 6, rz - 6, rx + 6, rz + 6], fill=col, width=3); dr.line([rx - 6, rz + 6, rx + 6, rz - 6], fill=col, width=3)
        continue
    a, b = P(*o["pos"])
    if (a - rx) ** 2 + (b - rz) ** 2 > 4:
        dr.line([rx, rz, a, b], fill=(255, 255, 255, 160), width=1)
    r = o["size"] * 0.5 / S
    if o["name"] in ("o_village", "o_fort", "o_oasis", "o_mesa"):
        dr.ellipse([a - r, b - r, a + r, b + r], outline=col, width=3)
    else:
        dr.ellipse([a - 4, b - 4, a + 4, b + 4], fill=col, outline=(0, 0, 0))
# легенда справа
LW = 300
out = Image.new("RGB", (iw + LW, max(ih, 760)), (250, 250, 248))
out.paste(im.convert("RGB"), (0, 0))
dl = ImageDraw.Draw(out)
FB = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
y = 10
if TITLE:
    for line in TITLE.split("|"):
        dl.text((iw + 12, y), line, font=FB, fill=(0, 0, 0)); y += 20
    y += 6
items = [("Зоны рельефа", None, None)] + [(t, ZC[z], "box") for z, t in [("river", "Река и мокрый берег"), ("road", "Дорога"), ("bank", "Прибрежная полоса"), ("floor", "Дно долины"), ("fan", "Конусы выноса, осыпи"), ("slope", "Склон (темнее — ниже)"), ("crest", "Гребень")]]
items += [("Снег (выше 85 % высоты)", (240, 242, 246), "box"), ("Объекты клеток", None, None)]
items += [(t, OBJ[k], "ring") for k, t in [("o_village", "Кишлак (городок)"), ("o_fort", "Крепость"), ("o_oasis", "Оазис"), ("o_mesa", "Столовая гора (в 3D пусто)")]]
items += [(t, OBJ[k], "dot") for k, t in [("o_rocks_big", "Скалы (группа)"), ("o_crater", "Воронка"), ("o_wreck", "Обломки самолёта")]]
items += [("Белая линия — сдвиг от реки", (200, 200, 200), "line"), ("Модели биома", None, None)]
items += [(t, PROP[k][0], "dot") for k, t in [("poplar", "Тополь"), ("orchard", "Сад (абрикос)"), ("shrub", "Куст"), ("boulders", "Валуны"), ("outcrop", "Выход породы"), ("yurt", "Юрта"), ("sandbag", "Мешки"), ("tank", "Сгоревшая техника")]]
items += [("Пятна гари и воронки", (120, 110, 100), "dot"), ("Клетка карты 1400 px", (150, 150, 150), "line")]
for t, col, kind in items:
    if col is None:
        y += 4; dl.text((iw + 12, y), t, font=FB, fill=(0, 0, 0)); y += 20; continue
    x = iw + 14
    if kind == "box": dl.rectangle([x, y + 2, x + 16, y + 14], fill=col, outline=(60, 60, 60))
    elif kind == "ring": dl.ellipse([x, y + 1, x + 14, y + 15], outline=col, width=3)
    elif kind == "dot": dl.ellipse([x + 3, y + 4, x + 11, y + 12], fill=col, outline=(0, 0, 0))
    else: dl.line([x, y + 8, x + 16, y + 8], fill=col, width=3)
    dl.text((x + 24, y), t, font=F, fill=(20, 20, 20)); y += 18
dl.text((iw + 12, out.size[1] - 22), "1 пиксель = %d px мира" % S, font=F, fill=(80, 80, 80))
out.save(dst)
print(dst, out.size)
