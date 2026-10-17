"""Чистая окраска моделей ангара (тест 3.5-s3: текстуры «идеально»; решение Kanta 17.10 — перекраска кодом,
кредиты Meshy не тратим). Раскладка пятен камуфляжа — исходная, от Meshy, но каждая точка обшивки
приводится к одному из K цветов палитры (k-means по самой текстуре, насыщенность возвращается): уходят
«сетка», «трещины» и грязь Meshy, кромки пятен ровные. Швы и лючки — множитель из высоких частот исходной
яркости, крупная светотень — слабо. Стекло фонаря (синее) и тёмные части (сопла, ниши, обтекатель) — исходные.
Пишет базовую текстуру ангара (извлечённый *_0.png) и, если задана, боевую (*_Image_0.jpg — та же развёртка,
размер свой). Сами GLB не трогаем: Godot перезаписывает извлечённую картинку, только если изменилась встроенная.

Применено (17.10.2026) к камуфлированным: attacker_1 2, attacker_2 2, fighter_1 2. Бомбардировщики и fighter_2
одноцветные и уже чистые — перекраска давала пятна и съедала швы, оставлены исходными.

Запуск: python3 clean_camo.py <K> <текстура ангара _0.png> [боевая _Image_0.jpg]"""
import sys
import numpy as np
from PIL import Image, ImageFilter

K = int(sys.argv[1])
src_f = sys.argv[2]
battle_f = sys.argv[3] if len(sys.argv) > 3 else None
SAT = 1.45        # k-means усредняет пятна с грязью — палитра сереет; столько насыщенности возвращаем
LUMA = np.array([0.299, 0.587, 0.114], np.float32)

src_im = Image.open(src_f)
src = src_im.convert("RGB")
H = src.size[1]
s = H / 2048.0    # радиусы фильтров заданы для 2048
rgb = np.asarray(src, np.float32) / 255
lum = rgb @ LUMA


def gray(a, f):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(f), np.float32) / 255


# палитра: k-means по пикселям обшивки (без тёмных и пересвеченных)
rng = np.random.default_rng(1)
pick = rgb[(lum > 0.18) & (lum < 0.92)]
pick = pick[rng.integers(0, len(pick), 60000)]
cent = np.quantile(pick, np.linspace(0.2, 0.8, K), axis=0) if K > 1 else pick.mean(0, keepdims=True)
for _ in range(30):
    lab = ((pick[:, None, :] - cent[None]) ** 2).sum(-1).argmin(1)
    cent = np.array([pick[lab == k].mean(0) if (lab == k).any() else cent[k] for k in range(K)])
cent = cent[np.argsort(cent @ LUMA)]
lc = (cent @ LUMA)[:, None]
cent = np.clip(lc + (cent - lc) * SAT, 0, 1)
print("PALETTE", np.round(cent, 3).tolist())

# раскладка: ближайший цвет палитры по сглаженному исходнику, кромки — медианой
sm = np.asarray(src.filter(ImageFilter.GaussianBlur(5 * s)), np.float32) / 255
l0 = (sm @ LUMA)[..., None]
sm = l0 + (sm - l0) * SAT
idx = ((sm[..., None, :] - cent[None, None]) ** 2).sum(-1).argmin(-1).astype(np.uint8)
med = max(3, int(9 * s) | 1)
idx = np.asarray(Image.fromarray(idx * 50).filter(ImageFilter.MedianFilter(med)).filter(ImageFilter.MedianFilter(med)),
                 np.uint8) // 50
camo = cent[np.minimum(idx, K - 1)]

# детали: высокие частоты яркости (швы, лючки), «трещины» почти не видны; крупная светотень — слабо
blur = gray(lum, ImageFilter.GaussianBlur(4 * s))
detail = 1 + (np.clip(lum / np.maximum(blur, 0.05), 0.75, 1.06) - 1) * 0.6
blur24 = gray(lum, ImageFilter.GaussianBlur(24 * s))
skin = lum > 0.18
shade = np.clip(blur24 / max(1e-3, float(np.median(blur24[skin]))), 0.85, 1.12)
new = np.clip(camo * (detail * shade)[..., None], 0, 1)

# стекло (тёмное синее; у голубых самолётов обшивка тоже синяя, но светлая) и тёмное (сопла, ниши, обтекатель носа) — исходные, с мягким переходом
glass = ((rgb[..., 2] - np.maximum(rgb[..., 0], rgb[..., 1]) > 0.03) & (blur < 0.4)).astype(np.float32)
dark = np.clip((0.27 - blur) / 0.06, 0, 1)
keep = gray(np.maximum(glass, dark), ImageFilter.MedianFilter(5))
keep = gray(keep, ImageFilter.MaxFilter(3))[..., None]
new = new * (1 - keep) + rgb * keep

out = Image.fromarray((new * 255 + 0.5).astype(np.uint8), "RGB")
if src_im.mode == "RGBA":
    out.putalpha(src_im.getchannel("A"))
out.save(src_f)
print("SAVED", src_f)
if battle_f:
    b = Image.open(battle_f)
    out.convert("RGB").resize(b.size, Image.LANCZOS).save(battle_f, quality=92)
    print("SAVED", battle_f)
