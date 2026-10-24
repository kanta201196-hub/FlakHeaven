import sys, json, base64
import numpy as np
from PIL import Image, ImageDraw, ImageFont
src, dst = sys.argv[1], sys.argv[2]
m = json.load(open(src + ".json")); W, H, step = m["W"], m["H"], m["step"]
h = np.fromfile(src, dtype=np.float32).reshape(H, W)
e = np.frombuffer(base64.b64decode(m["pe"]), np.uint8).reshape(H, W) / 255.
ms = np.frombuffer(base64.b64decode(m["pm"]), np.uint8).reshape(H, W) / 255.
hill = (1 - np.clip((e - .2) / .35, 0, 1)) * (1 - ms)
col = np.zeros((H, W, 3))
types = {"hills": (hill, (120, 170, 90)), "high": (np.clip((e - .6) / .3, 0, 1) * (1 - ms), (235, 235, 245)),
         "mesa": (ms, (200, 110, 70))}
mid = np.clip(1 - hill - types["high"][0] - ms, 0, 1)
types["mid"] = (mid, (150, 120, 95))
for k, (w, c) in types.items():
    col += w[..., None] * np.array(c)
gy, gx = np.gradient(h, step)
shade = np.clip(0.6 + 0.4 * (-gx - gy) / (np.hypot(gx, gy) + 1e-3) * np.clip(np.hypot(gx, gy) * 3, 0, 1), 0.3, 1)
col *= shade[..., None]
col[h < -2] = (60, 110, 150)
img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
dr = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
leg = [("Холмы и одиночные вершины", (120, 170, 90)), ("Средние горы", (150, 120, 95)), ("Высокий хребет со снегом", (235, 235, 245)), ("Столовые горы и каньоны", (200, 110, 70))]
dr.rectangle([0, 0, W, 34], fill=(0, 0, 0)); dr.text((10, 5), "Какой рельеф где (черновик)", fill="white", font=font)
for i, (t, c) in enumerate(leg):
    dr.rectangle([10, 44 + i * 28, 32, 66 + i * 28], fill=c, outline="black"); dr.text((40, 44 + i * 28), t, fill="black", font=font)
img.save(dst)
# pick spots: strongest of each type, away from river (h > 0.1*ceiling)
ceil = m["ceiling"]
for k, (w, c) in types.items():
    score = w * (h > 0.08 * ceil)
    j, i = np.unravel_index(np.argmax(score * (1 + 0.0 * h)), score.shape)
    # prefer a spot near the valley edge of that type: look for pixel with w>0.9 and h in 0.15-0.4
    cand = np.argwhere((w > 0.9) & (h > 0.12 * ceil) & (h < 0.45 * ceil))
    if len(cand):
        j, i = cand[len(cand) // 2]
    print(k, round(m["x0"] + (i + .5) * step), round(m["z0"] + (j + .5) * step), round(float(w[j, i]), 2))
