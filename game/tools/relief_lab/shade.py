"""Hillshade map of a relief_dump.gd output + simple stats. python3 shade.py in.bin out.png [title]"""
import sys, json, base64
import numpy as np
from PIL import Image, ImageDraw, ImageFont
src, dst = sys.argv[1], sys.argv[2]
title = sys.argv[3] if len(sys.argv) > 3 else ""
meta = json.load(open(src + ".json"))
W, H, step, ceil = meta["W"], meta["H"], meta["step"], meta["ceiling"]
h = np.fromfile(src, dtype=np.float32).reshape(H, W)
rock = np.frombuffer(base64.b64decode(meta["rock"]), dtype=np.uint8).reshape(H, W) / 255.0
gy, gx = np.gradient(h, step)
slope = np.degrees(np.arctan(np.hypot(gx, gy)))
# sun from upper-left like the game
az, alt = np.radians(315), np.radians(40)
asp = np.arctan2(-gx, gy)
sl = np.arctan(np.hypot(gx, gy) * 1.6)
shade = np.sin(alt) * np.cos(sl) + np.cos(alt) * np.sin(sl) * np.cos(az - asp)
shade = np.clip(shade, 0, 1)
t = np.clip(h / ceil, 0, 1)
stops = np.array([[0.0, 196, 178, 138], [0.12, 186, 160, 118], [0.35, 160, 128, 96], [0.6, 135, 112, 96], [0.82, 165, 158, 150], [0.9, 236, 238, 242], [1.0, 250, 250, 252]])
col = np.stack([np.interp(t, stops[:, 0], stops[:, k]) for k in (1, 2, 3)], -1)
col = col * (1 - 0.35 * rock[..., None]) + np.array([120, 112, 104]) * 0.35 * rock[..., None]
col = col * (0.35 + 0.85 * shade[..., None])
water = h < -2
col[water] = [70, 115, 145]
img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
dr = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
except Exception:
    font = None
# 5 km scale bar (game px: assume 1 px ~ 1 m? just label in chunks)
kpx = 5 * 1400 / step
dr.rectangle([20, H - 40, 20 + kpx, H - 32], fill=(20, 20, 20))
dr.text((20, H - 70), "5 клеток (7000 px)", fill=(20, 20, 20), font=font)
if title:
    dr.rectangle([0, 0, W, 34], fill=(0, 0, 0))
    dr.text((10, 5), title, fill=(255, 255, 255), font=font)
img.save(dst)
land = h > 5
hist = np.histogram(t[land], bins=[0, .1, .25, .4, .55, .7, .85, 1.01])[0] / land.sum()
sh = np.histogram(slope[land], bins=[0, 5, 15, 25, 35, 50, 90])[0] / land.sum()
print("height share by band 0-.1/.1-.25/.25-.4/.4-.55/.55-.7/.7-.85/.85+:", np.round(hist * 100, 1))
print("slope share 0-5/5-15/15-25/25-35/35-50/50+ deg:", np.round(sh * 100, 1))
# regional variety: std of local max height over 4x4 chunk windows
per = int(1400 / step) * 3
mx = [h[j:j + per, i:i + per].max() / ceil for j in range(0, H - per + 1, per) for i in range(0, W - per + 1, per)]
print("3x3-chunk window peak height (share of ceiling): min %.2f max %.2f std %.2f" % (min(mx), max(mx), np.std(mx)))
print("us/sample", meta.get("us_per_sample"))
