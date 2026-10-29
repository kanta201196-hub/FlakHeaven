"""Процедурные текстуры для моделей биома (numpy + PIL, без генераторов и скачиваний): листья с альфой,
кора, мешковина, земля, пятно гари; к каждой — карта нормалей из карты высот. Все повторяются без шва
(шум — сумма синусов с целыми частотами). Цвета — sRGB 0…1.
Используют biome_flora.py и plane_wreck.py."""
import math, os, tempfile
import numpy as np
from PIL import Image

_TMP = tempfile.mkdtemp(prefix="fh_tex_")


def pnoise(h, w, seed, fmin=1, fmax=8, n=40, aniso=(1.0, 1.0)):
    """Бесшовный шум h×w: сумма n синусов со случайными целыми частотами fmin…fmax, ~[-1, 1]"""
    rng = np.random.default_rng(seed)
    y = np.arange(h, dtype=np.float32)[:, None] / h
    x = np.arange(w, dtype=np.float32)[None, :] / w
    out = np.zeros((h, w), np.float32)
    for _ in range(n):
        f = rng.uniform(fmin, fmax)
        a = rng.uniform(0, 2 * math.pi)
        kx = int(round(f * math.cos(a) * aniso[0]))
        ky = int(round(f * math.sin(a) * aniso[1]))
        if kx == 0 and ky == 0:
            kx = 1
        amp = 1.0 / math.hypot(kx, ky)
        out += amp * np.sin(2 * math.pi * (kx * x + ky * y) + rng.uniform(0, 2 * math.pi))
    return out / (np.abs(out).max() + 1e-6)


def normal_map(height, strength=2.0):
    """Карта нормалей (OpenGL/glTF: +Y вверх по картинке) из карты высот 0…1, бесшовно"""
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * strength * height.shape[1] / 64
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * strength * height.shape[0] / 64
    n = np.stack([-dx, dy, np.ones_like(height)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return (n * 0.5 + 0.5)


def save(name, rgb, alpha=None, jpg=True):
    """Сохранить во временную папку; возвращает путь (PNG с альфой, иначе JPEG)"""
    a = np.clip(rgb, 0, 1)
    if alpha is not None:
        im = Image.fromarray((np.dstack([a, np.clip(alpha, 0, 1)]) * 255).astype(np.uint8), "RGBA")
        p = os.path.join(_TMP, name + ".png")
        im.save(p)
    else:
        im = Image.fromarray((a * 255).astype(np.uint8), "RGB")
        p = os.path.join(_TMP, name + (".jpg" if jpg else ".png"))
        im.save(p, quality=90) if jpg else im.save(p)
    return p


# ---------------- листья ----------------
def leaves(name, seed, n_leaf=95, size=512, leaf_len=(0.17, 0.25), width=0.36, base=(0.36, 0.42, 0.2),
           dry=(0.56, 0.5, 0.3), dry_share=0.12, var=0.07, stems=True):
    """Веточка с листьями на прозрачном фоне: черешки от низа к краям, листья-«лодочки» с центральной жилкой,
    светлее к краю, сухие (жёлтые) — dry_share. Возвращает (цвет RGBA, нормали) — пути к файлам"""
    rng = np.random.default_rng(seed)
    S = size * 2   # рисуем вдвое крупнее, потом уменьшаем — сглаженный край альфы
    col = np.zeros((S, S, 3), np.float32)
    hgt = np.zeros((S, S), np.float32)
    alp = np.zeros((S, S), np.float32)
    # веточки: из нижнего центра веером
    stems = []
    for i in range(5):
        a = math.radians(rng.uniform(35, 145))
        L = rng.uniform(0.55, 0.8) * S
        p0 = np.array([S * 0.5 + rng.uniform(-0.05, 0.05) * S, S * 0.98])
        stems.append((p0, np.array([math.cos(a), -math.sin(a)]), L))
        for t in np.linspace(0, 1, int(L)):
            q = p0 + stems[-1][1] * L * t
            r = (1 - t) * S * 0.003 + S * 0.0015
            x0, x1 = int(q[0] - r - 1), int(q[0] + r + 2)
            y0, y1 = int(q[1] - r - 1), int(q[1] + r + 2)
            if min(y1, S) <= max(y0, 0) or min(x1, S) <= max(x0, 0):
                continue
            yy, xx = np.mgrid[max(y0, 0):min(y1, S), max(x0, 0):min(x1, S)]
            m = (xx - q[0]) ** 2 + (yy - q[1]) ** 2 <= r * r
            if stems:   # черешки тонкие, в тон коры; у куста не рисуются (на карточках — «проволока»)
                col[yy[m], xx[m]] = (0.3, 0.26, 0.18)
                alp[yy[m], xx[m]] = 1
                hgt[yy[m], xx[m]] = 0.4
    order = []
    for i in range(n_leaf):
        p0, d, L = stems[rng.integers(len(stems))]
        t = rng.uniform(0.25, 1.0)
        c = p0 + d * L * t
        ang = math.atan2(d[1], d[0]) + rng.choice([-1, 1]) * rng.uniform(0.4, 1.2)
        ll = rng.uniform(*leaf_len) * S
        c = c + np.array([math.cos(ang), math.sin(ang)]) * ll * 0.5
        order.append((c, ang, ll))
    for c, ang, ll in order:
        hw = ll * width * 0.5
        ca, sa = math.cos(ang), math.sin(ang)
        R = int(ll * 0.55) + 2
        y0, y1, x0, x1 = int(c[1] - R), int(c[1] + R), int(c[0] - R), int(c[0] + R)
        if min(y1, S) <= max(y0, 0) or min(x1, S) <= max(x0, 0):
            continue
        yy, xx = np.mgrid[max(y0, 0):min(y1, S), max(x0, 0):min(x1, S)]
        u = ((xx - c[0]) * ca + (yy - c[1]) * sa) / (ll * 0.5)        # вдоль листа −1…1
        v = (-(xx - c[0]) * sa + (yy - c[1]) * ca) / hw               # поперёк
        prof = np.clip(1 - u * u, 0, 1) ** 0.8                        # форма «лодочки» с острыми концами
        inside = np.abs(v) <= prof
        if not inside.any():
            continue
        dryk = rng.random() < dry_share
        b = np.array(dry if dryk else base, np.float32) * (1 + rng.uniform(-var, var, 3)).astype(np.float32)
        vv = np.where(inside, np.abs(v) / np.maximum(prof, 1e-3), 0)
        shade = 0.82 + 0.3 * (u * 0.5 + 0.5) - 0.12 * (vv < 0.08)    # к кончику светлее, жилка темнее
        cc = b[None, None, :] * shade[..., None]
        h = 0.5 + 0.5 * np.sqrt(np.clip(1 - vv ** 2, 0, 1)) * prof    # выпуклый лист
        sel = inside
        col[yy[sel], xx[sel]] = cc[sel]
        hgt[yy[sel], xx[sel]] = h[sel]
        alp[yy[sel], xx[sel]] = 1
    img = Image.fromarray((np.dstack([np.clip(col, 0, 1), alp]) * 255).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)
    a = np.asarray(img, np.float32) / 255
    # цвет под прозрачными пикселями — средний цвет листвы (без тёмной каймы на мип-уровнях)
    m = a[..., 3] > 0.5
    mean = a[m][:, :3].mean(0)
    rgb = np.where(a[..., 3:4] > 0.05, a[..., :3] / np.maximum(a[..., 3:4], 1e-3), mean)
    rgb = np.where(a[..., 3:4] > 0.05, rgb, mean)
    hs = np.asarray(Image.fromarray((hgt * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS), np.float32) / 255
    pc = save(name + "_color", rgb, a[..., 3])
    pn = save(name + "_normal", normal_map(hs, 3.0), jpg=False)
    return pc, pn


# ---------------- кора ----------------
def bark(name, seed, size=(256, 512), base=(0.36, 0.31, 0.25)):
    """Bark colour and normal maps (paths): furrows along the trunk, cracks, lichen and dust; base — the bark tone
    (the default is the orchard's brown; the poplar passes a light grey)"""
    w, h = size
    n1 = pnoise(h, w, seed, 8, 24, 50, aniso=(1.0, 0.12))    # продольные борозды
    n2 = pnoise(h, w, seed + 1, 10, 40, 60)
    hgt = np.clip(0.55 + 0.35 * np.abs(n1) ** 0.6 * np.sign(n1) + 0.1 * n2, 0, 1)
    crack = np.clip((0.35 - np.abs(n1)) * 4, 0, 1)            # трещины
    base = np.array(base, np.float32)
    rgb = base * (0.8 + 0.3 * hgt[..., None]) * (1 - 0.45 * crack[..., None])
    rgb = rgb + np.array([0.04, 0.04, 0.03]) * pnoise(h, w, seed + 2, 1, 4, 20)[..., None]   # лишайник/пыль
    return save(name + "_color", rgb), save(name + "_normal", normal_map(hgt * (1 - 0.5 * crack), 2.5))


# ---------------- мешковина ----------------
def burlap(name, seed, size=256):
    s = size
    y = np.arange(s, dtype=np.float32)[:, None] / s
    x = np.arange(s, dtype=np.float32)[None, :] / s
    F = 48
    weave = 0.5 + 0.25 * np.sin(2 * math.pi * F * x) * np.sign(np.sin(math.pi * F * y)) + 0.25 * np.sin(2 * math.pi * F * y) * np.sign(np.sin(math.pi * F * x))
    stain = pnoise(s, s, seed, 1, 5, 30)
    dust = pnoise(s, s, seed + 1, 3, 12, 40)
    base = np.array([0.56, 0.53, 0.46], np.float32)   # пыльный бежево-серый
    rgb = base * (0.9 + 0.12 * weave[..., None]) * (1 - 0.1 * np.clip(stain, 0, 1)[..., None])
    rgb = rgb * (1 - 0.15 * np.clip(-dust, 0, 1)[..., None]) + np.array([0.06, 0.05, 0.03]) * np.clip(dust, 0, 1)[..., None]
    return save(name + "_color", rgb), save(name + "_normal", normal_map(weave * 0.6 + 0.1 * stain, 1.2))


# ---------------- земля ----------------
def earth(name, seed, size=512, base=(0.55, 0.5, 0.41)):
    s = size
    rng = np.random.default_rng(seed)
    n1 = pnoise(s, s, seed, 2, 10, 50)
    n2 = pnoise(s, s, seed + 1, 12, 48, 70)
    hgt = 0.5 + 0.25 * n1 + 0.15 * n2
    rgb = np.array(base, np.float32) * (0.86 + 0.16 * n1[..., None] + 0.08 * n2[..., None])
    # камешки и комочки
    yy, xx = np.mgrid[0:s, 0:s]
    for i in range(260):
        cx, cy = rng.uniform(0, s, 2)
        r = rng.uniform(1.5, 5.5)
        d2 = ((xx - cx + s / 2) % s - s / 2) ** 2 + ((yy - cy + s / 2) % s - s / 2) ** 2
        m = d2 < r * r
        k = rng.uniform(0.7, 1.15)
        rgb[m] = rgb[m] * k
        hgt[m] = hgt[m] + 0.35 * np.sqrt(1 - d2[m] / (r * r))
    return save(name + "_color", rgb), save(name + "_normal", normal_map(np.clip(hgt, 0, 1.5) / 1.5, 2.5))


# ---------------- пятно гари ----------------
def scorch(name, seed, size=512):
    """Scorched ground under a wreck: a charcoal core flecked with grey ash, burnt earth and grass round it, soot
    fingers thrown out by the fire, charred specks; a ragged edge, the alpha fading out at the rim. sRGB"""
    s = size
    y, x = np.mgrid[0:s, 0:s].astype(np.float32)
    dx, dy = x - s / 2, y - s / 2
    r = np.hypot(dx, dy) / (s / 2)
    ang = np.arctan2(dy, dx)
    n = pnoise(s, s, seed, 2, 9, 50)
    n2 = pnoise(s, s, seed + 1, 10, 40, 60)
    n3 = pnoise(s, s, seed + 2, 40, 110, 90)
    rng = np.random.default_rng(seed)
    fing = np.zeros_like(r)
    for k in (5, 7, 11):   # soot fingers: angular lobes of different counts and phases
        fing += np.clip(np.sin(ang * k + rng.uniform(0, 6.3) + 2.0 * n), 0, 1) ** 3 / 3.0
    rr = r * (1 + 0.26 * n + 0.08 * n2) - 0.22 * fing * np.clip(r, 0, 1)
    alpha = np.clip((1.0 - rr) * 2.3, 0, 1) ** 1.3 * 0.95
    core = np.clip((0.55 - rr) * 2.6, 0, 1)
    edge = np.clip((rr - 0.55) * 3.0, 0, 1)
    rgb = np.array([0.055, 0.048, 0.042], np.float32) * core[..., None] \
        + np.array([0.2, 0.15, 0.1], np.float32) * ((1 - core) * (1 - edge))[..., None] \
        + np.array([0.33, 0.26, 0.17], np.float32) * ((1 - core) * edge)[..., None]
    ash = np.clip((0.45 - rr) * 3.0, 0, 1) * np.clip((n2 + n3 * 0.6 - 0.3) * 2.5, 0, 1)
    rgb = rgb * (1 - 0.7 * ash[..., None]) + np.array([0.42, 0.4, 0.37], np.float32) * (0.7 * ash)[..., None]
    speck = (n3 > 0.62) & (rr < 0.95)
    rgb[speck] *= 0.35
    rgb = rgb * (0.85 + 0.25 * n2[..., None])
    return save(name + "_color", rgb, alpha)
