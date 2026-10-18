"""Тест 3.5-s5, п. 2 (Kanta): стекло фонаря кабины — отдельный материал «glass» у своих самолётов
(6 моделей ангара и 6 боевых). Расцветка (scripts/livery.gd) стекло не перекрашивает, сам материал один на все
окраски: shaders/canopy_glass.tres (подключён как внешний материал «glass» в .import каждой модели).

Без Blender (numpy + PIL): картинки в GLB остаются байт в байт (glb_io), поэтому Godot не перезаписывает
извлечённые текстуры (*_col.jpg, *_Image_N.jpg) — окраска не страдает. Обшивка остаётся первым примитивом
(surface 0), стекло — второй примитив (surface 1) с общими вершинами.

Шаги:
1. Где фонарь — области в таблице TUNE (по кадрам --debug); для новой модели — по горбу, как ModuleParts._measure.
2. В области — треугольники, у которых на текстуре стекло (тёмное / синевато-серое), дыры (блики) закрываются;
   у «Кита 1» стекло закрашено камуфляжем — берётся вся поверхность области (mode geo).
3. По выбранному строится гладкая граница (в плане суперэллипс, сбоку — линия низа стекла) и треугольники
   режутся по ней: край стекла ровный, а не «лесенкой» по сетке Meshy.

Запуск из game/tools/blender — по исходным моделям без стекла (повторный запуск по уже разрезанной модели
работает, но режет ещё раз): исходники — /mnt/project-files/models_src/canopy_glass/orig/.
  python3 canopy_glass.py all [--debug папка] [--dry]
  python3 canopy_glass.py ../../models/hangar/fh_hangar_fighter_1.glb --debug /tmp/glass
--debug: кадры сверху и сбоку с сеткой 0.05 (выбор по текстуре и итог после разреза в <папка>/cut/).
После запуска: godot --headless --path game --import. После battle_lod.py или новой модели Meshy — запустить
заново (и добавить внешний материал «glass» в .import новой модели, как у нынешних).
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.normpath(os.path.join(HERE, "..", "..", "models"))
GLASS = "glass"

# Настройки по моделям: порог яркости стекла на текстуре (линейная яркость) и запас по длине фонаря.
# Порог чуть выше Livery.SRC[...][1] (там «не перекрашивать»): стекло на текстурах Meshy — самое тёмное место.
TUNE = {
    # области фонаря (по кадрам --debug, сетка 0.05): x — от и до, hw — полуширина, y — нижняя граница
    # стекла в начале и в конце области; mode: tex — стекло по текстуре (dark — порог яркости, blue — синеватость),
    # geo — вся поверхность области (у «Кита 1» стекло закрашено камуфляжем, на текстуре его не видно)
    "fighter_1": [{"x": (0.12, 0.34), "hw": 0.035, "y": (-0.012, -0.012), "mode": "tex", "dark": 0.05, "pad": 0.009}],
    "fighter_2": [{"x": (-0.01, 0.31), "hw": 0.04, "y": (0.012, 0.008), "mode": "tex", "dark": 0.05, "pad": 0.006}],
    "attacker_1": [{"x": (0.12, 0.35), "hw": 0.04, "y": (-0.006, -0.012), "mode": "tex", "dark": 0.03,
                    "blue": -0.025, "blue_lum": 0.07}],
    "attacker_2": [{"x": (0.09, 0.315), "hw": 0.042, "y": (0.02, 0.0), "mode": "tex", "dark": 0.03,
                    "blue": -0.012, "blue_lum": 0.08},
                   {"x": (0.315, 0.40), "hw": 0.032, "y": (-0.03, -0.055), "mode": "tex", "dark": 0.03,
                    "blue": -0.012, "blue_lum": 0.08}],
    "bomber_1": [{"x": (0.212, 0.372), "hw": 0.03, "y": (-0.029, -0.029), "mode": "geo"}],
    "bomber_2": [{"x": (0.235, 0.40), "hw": 0.032, "y": (0.016, -0.012), "mode": "tex", "dark": 0.035}],
}

# порог «очень тёмного» из Livery.SRC (ниже — расцветка не трогает): по нему стекло дорастает до кромки
GROW = {"fighter_1": 0.022, "fighter_2": 0.022, "attacker_1": 0.011, "attacker_2": 0.011,
        "bomber_1": 0.013, "bomber_2": 0.013}


def srgb_lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def base_image(path, g, prim):
    """Цветовая текстура так, как её видит игра: извлечённый Godot файл рядом с GLB."""
    mat = g.j["materials"][prim["material"]]
    ti = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = g.j["images"][g.j["textures"][ti]["source"]]
    stem = path[:-4]
    name = img.get("name", "")
    for cand in (f"{stem}_{name}.jpg", f"{stem}_{name}.png", f"{stem}_{ti}.png"):
        if os.path.exists(cand):
            return Image.open(cand).convert("RGB"), cand
    raise SystemExit(f"нет картинки рядом с {path} ({name})")


def merge_back(g, mesh):
    """Если стекло уже выделено — вернуть его треугольники в примитив обшивки (повторный запуск)."""
    prims = mesh["primitives"]
    names = [g.j["materials"][p["material"]].get("name", "") for p in prims]
    if GLASS not in names:
        return None
    gi = names.index(GLASS)
    body = 0 if gi != 0 else 1
    tb = g.accessor(prims[body]["indices"]).reshape(-1, 3)
    tg = g.accessor(prims[gi]["indices"]).reshape(-1, 3)
    mat_i = prims[gi]["material"]
    del prims[gi]
    g.set_indices(0, 0, np.concatenate([tb, tg]))
    return mat_i


class Surf:
    """Высота поверхности над точкой (x, z) — как ModuleParts._surf: верхняя или нижняя, NaN — промах."""

    def __init__(self, P, T):
        self.a, self.b, self.c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        self.xmin = np.minimum(np.minimum(self.a[:, 0], self.b[:, 0]), self.c[:, 0])
        self.xmax = np.maximum(np.maximum(self.a[:, 0], self.b[:, 0]), self.c[:, 0])

    def y(self, x, z, low=False):
        m = (self.xmin <= x) & (self.xmax >= x)
        a, b, c = self.a[m], self.b[m], self.c[m]
        v0 = c[:, [0, 2]] - a[:, [0, 2]]
        v1 = b[:, [0, 2]] - a[:, [0, 2]]
        v2 = np.array([x, z]) - a[:, [0, 2]]
        d00 = (v0 * v0).sum(1)
        d01 = (v0 * v1).sum(1)
        d11 = (v1 * v1).sum(1)
        d20 = (v2 * v0).sum(1)
        d21 = (v2 * v1).sum(1)
        den = d00 * d11 - d01 * d01
        ok = np.abs(den) > 1e-14
        den = np.where(ok, den, 1.0)
        u = (d11 * d20 - d01 * d21) / den
        v = (d00 * d21 - d01 * d20) / den
        hit = ok & (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6)
        if not hit.any():
            return np.nan
        ys = a[hit, 1] + u[hit] * (c[hit, 1] - a[hit, 1]) + v[hit] * (b[hit, 1] - a[hit, 1])
        return ys.min() if low else ys.max()

    def y_or(self, x, z, d):
        r = self.y(x, z)
        return d if np.isnan(r) else r


def canopy_box(P, T):
    """Фонарь как в ModuleParts._measure: верх горба, его длина и высота над спиной"""
    s = Surf(P, T)
    ax = np.abs(P[:, 2]) < 0.02
    nose_x = P[ax, 0].max()
    best = (0.0, -1.0)
    for i in range(46):
        x = 0.02 + i * 0.01
        y = s.y(x, 0.0)
        if not np.isnan(y) and y > best[1] and x < nose_x - 0.05:
            best = (x, y)
    bx, by = best
    back = s.y(bx - 0.18, 0.0)
    back = by - 0.02 if np.isnan(back) else back
    hump = max(by - back, 0.01)
    x0 = bx
    while x0 > bx - 0.2 and s.y_or(x0, 0.0, back) > back + hump * 0.4:
        x0 -= 0.005
    x1 = bx
    while x1 < nose_x and s.y_or(x1, 0.0, back) > back + hump * 0.4:
        x1 += 0.005
    return {"x": bx, "y": by, "back": back, "hump": hump, "x0": x0, "x1": x1, "nose": nose_x}


def components(T, sel, keyp):
    """Связные куски выбранных треугольников (соседи — общая вершина по положению, швы UV не рвут)"""
    idx = np.nonzero(sel)[0]
    parent = {int(i): int(i) for i in idx}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    owner = {}
    for f in idx:
        for k in keyp[T[f]]:
            k = int(k)
            if k in owner:
                ra, rb = find(owner[k]), find(int(f))
                if ra != rb:
                    parent[ra] = rb
            else:
                owner[k] = int(f)
    comp = {}
    for f in idx:
        comp.setdefault(find(int(f)), []).append(int(f))
    return list(comp.values())


def regions_of(key, cb):
    """Области поиска стекла: из таблицы TUNE или (новая модель) по горбу ModuleParts"""
    if key in TUNE:
        return TUNE[key]
    L = cb["x1"] - cb["x0"]
    return [{"x": (cb["x0"] - L * 0.35, cb["x1"] + L * 0.25), "hw": max(L * 0.45, 0.05),
             "y": (cb["back"] - cb["hump"] * 0.6,) * 2, "mode": "tex", "dark": 0.04}]


def select(P, N, UV, T, img, key, dbg=None):
    cb = canopy_box(P, T)
    c = P[T].mean(1)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    area = np.linalg.norm(fn, axis=1) * 0.5
    vn = N[T].mean(1)
    vn = vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
    W, H = img.size
    px = np.asarray(img, dtype=np.float32)
    lum = srgb_lin(px) @ np.array([0.2126, 0.7152, 0.0722])
    blue = (px[..., 2] - np.maximum(px[..., 0], px[..., 1])) / 255.0   # синеватость (стекло «Грача»)

    def samp(arr, uv):
        u = np.clip((uv[:, 0] % 1.0) * W, 0, W - 1).astype(int)
        v = np.clip((uv[:, 1] % 1.0) * H, 0, H - 1).astype(int)
        return arr[v, u]

    # цвет текстуры в центре треугольника и ближе к трём вершинам; «стекло», если так хотя бы в 3 точках из 4
    uvs = [UV[T].mean(1)] + [UV[T[:, k]] * 0.7 + UV[T].mean(1) * 0.3 for k in range(3)]
    ls = [samp(lum, uv) for uv in uvs]
    bs = [samp(blue, uv) for uv in uvs]
    win = np.zeros(len(T), bool)
    wide = np.zeros(len(T), bool)    # окно с запасом: туда стекло дорастает по тёмной кромке
    geo = np.zeros(len(T), bool)
    glassy = np.zeros(len(T), bool)
    rin = []
    for r in regions_of(key, cb):
        (xa, xb), (ya, yb) = r["x"], r["y"]
        t = np.clip((c[:, 0] - xa) / (xb - xa), 0, 1)
        # в плане — эллипс по длине и ширине области (фонарь скруглён спереди и сзади)
        ex = (c[:, 0] - (xa + xb) / 2) / ((xb - xa) / 2)
        ez = c[:, 2] / r["hw"]
        inr = (ex * ex + ez * ez < 1.0) & (c[:, 1] > ya + (yb - ya) * t) & (vn[:, 1] > -0.3)
        win |= inr
        rin.append((inr, r.get("pad", 0.004)))
        wide |= (ex * ex / 1.25 + ez * ez / 1.5 < 1.0) & (c[:, 1] > ya + (yb - ya) * t - 0.012)
        if r["mode"] == "geo":
            geo |= inr
        else:
            n = sum(((x < r["dark"]) | ((b > r.get("blue", 9.0)) & (x < r.get("blue_lum", 0.15)))).astype(int)
                    for x, b in zip(ls, bs))
            glassy |= inr & (n >= 3)
    keyp = np.unique(np.round(P / 1e-5).astype(np.int64), axis=0, return_inverse=True)[1].reshape(-1)
    glass = geo.copy()
    comps = components(T, glassy, keyp)
    tot = sum(area[cp].sum() for cp in comps) or 1.0
    for cp in comps:   # стёкла (между ними — рамы); мелкие тёмные пятна — не стекло
        if area[cp].sum() > tot * 0.03:
            glass[np.array(cp)] = True
    # дыры: куски окна, со всех сторон окружённые стеклом (блики и отражения на текстуре). Рамы и борт
    # связаны с обшивкой вокруг фонаря — остаются в цвет самолёта
    vout = np.zeros(keyp.max() + 1, bool)
    vout[keyp[T[~win]].reshape(-1)] = True
    for cp in components(T, win & ~glass, keyp):
        cp = np.array(cp)
        if not vout[keyp[T[cp]].reshape(-1)].any():
            glass[cp] = True
    # тёмная кромка вокруг стекла на текстуре: расцветка такое не перекрашивает (Livery: «очень тёмное») —
    # без этого вокруг фонаря остаются чёрные зубцы. Стекло дорастает по ней до 6 шагов
    grow = GROW.get(key, 0.015)
    dk = sum((x < grow).astype(int) for x in ls) >= 2
    for _ in range(6):
        vg = np.zeros(keyp.max() + 1, bool)
        vg[keyp[T[glass]].reshape(-1)] = True
        add = vg[keyp[T]].any(1) & wide & dk & ~glass
        if not add.any():
            break
        glass |= add
        win |= add
    # одиночные «зубцы»: треугольник окна, у которого все три вершины на стекле — стекло
    vglass = np.zeros(keyp.max() + 1, bool)
    for _ in range(2):
        vglass[keyp[T[glass]].reshape(-1)] = True
        glass |= vglass[keyp[T]].all(1) & win
    if not glass.any():
        print(f"{key}: стекло не найдено (горб {cb})")
    info = dict(cb, tris=int(glass.sum()), area=float(area[glass].sum()), comps=len(comps))
    if dbg:
        u = np.clip((UV[T].mean(1)[:, 0] % 1.0) * W, 0, W - 1).astype(int)
        v = np.clip((UV[T].mean(1)[:, 1] % 1.0) * H, 0, H - 1).astype(int)
        debug_img(P, T, glass, win, cb, dbg, key, px[v, u], ls[0])
    info["rin"] = rin
    return glass, info


def field(P, T, glass, rin, p=2.4):
    """Гладкая граница фонаря по выбранным треугольникам: в плане — суперэллипс по длине и ширине стекла,
    сбоку — линия низа стекла (прямая по нижним точкам вдоль фонаря). f < 0 — стекло. Значение f в вершинах;
    по нему треугольники режутся (cut), поэтому край стекла ровный, а не «лесенкой» по сетке."""
    c = P[T].mean(1)
    f = np.full(len(P), np.inf)
    shapes = []
    for inr, pad in rin:   # pad — запас края стекла наружу (тёмная кромка фонаря на текстуре)
        g = glass & inr
        if g.sum() < 3:
            continue
        cg = c[g]
        xa, xb = np.percentile(cg[:, 0], 0.5) - pad, np.percentile(cg[:, 0], 99.5) + pad
        hw = np.percentile(np.abs(cg[:, 2]), 99.5) + pad
        xm, hx = (xa + xb) / 2, (xb - xa) / 2
        # низ стекла: нижние точки по 6 отрезкам вдоль фонаря → прямая
        bx, by = [], []
        for i in range(6):
            m = (cg[:, 0] >= xa + (xb - xa) * i / 6) & (cg[:, 0] < xa + (xb - xa) * (i + 1) / 6)
            if m.sum() >= 3:
                bx.append(cg[m, 0].mean())
                by.append(np.percentile(cg[m, 1], 3))
        k, b0 = np.polyfit(bx, by, 1) if len(bx) >= 2 else (0.0, (by or [cg[:, 1].min()])[0])
        e = (np.abs((P[:, 0] - xm) / hx) ** p + np.abs(P[:, 2] / hw) ** p) ** (1 / p) - 1.0
        fh = (k * P[:, 0] + b0 - pad) - P[:, 1]
        f = np.minimum(f, np.maximum(e * hw, fh))
        shapes.append(" ".join(f"{float(v):.3f}" for v in (xa, xb, hw, k, b0)))
    return f, shapes


def cut(g, prim, T, f, eps=1e-7):
    """Режет треугольники по линии f = 0 (новые вершины — на рёбрах, атрибуты по линейной интерполяции).
    Возвращает (треугольники стекла, треугольники обшивки); атрибуты примитива дописываются на месте."""
    names = list(prim["attributes"])
    A = {n: g.accessor(prim["attributes"][n]).astype(np.float64) for n in names}
    nv = len(A["POSITION"])
    new = {n: [] for n in names}
    fv = list(f)
    cache = {}

    def mid(a, b):
        key = (a, b) if a < b else (b, a)
        if key in cache:
            return cache[key]
        t = fv[a] / (fv[a] - fv[b])
        for n in names:
            v = A[n][a] * (1 - t) + A[n][b] * t
            new[n].append(v)
        idx = nv + len(new["POSITION"]) - 1
        fv.append(0.0)
        cache[key] = idx
        return idx

    s = np.where(f < -eps, -1, np.where(f > eps, 1, 0))
    tin, tout = [], []
    for tri in T:
        st = s[tri]
        if (st <= 0).all() and (st < 0).any():
            tin.append(tri)
            continue
        if not ((st < 0).any() and (st > 0).any()):
            tout.append(tri)          # снаружи или целиком на границе
            continue
        pin, pout = [], []
        for i in range(3):
            a, b = int(tri[i]), int(tri[(i + 1) % 3])
            sa, sb = s[a], s[b]
            if sa <= 0:
                pin.append(a)
            if sa >= 0:
                pout.append(a)
            if sa * sb < 0:
                m = mid(a, b)
                pin.append(m)
                pout.append(m)
        for poly, out in ((pin, tin), (pout, tout)):
            for i in range(1, len(poly) - 1):
                out.append([poly[0], poly[i], poly[i + 1]])
    if new["POSITION"]:
        for n in names:
            arr = np.concatenate([A[n], np.array(new[n])])
            if n == "NORMAL":
                arr /= np.maximum(np.linalg.norm(arr, axis=1, keepdims=True), 1e-12)
            set_attr(g, prim["attributes"][n], arr, n == "POSITION")
    return np.array(tin, dtype=np.int64).reshape(-1, 3), np.array(tout, dtype=np.int64).reshape(-1, 3)


def set_attr(g, ai, arr, minmax):
    """Переписать данные атрибута (float32) в конец буфера; старые байты уберёт compact()"""
    a = g.j["accessors"][ai]
    data = arr.astype(np.float32)
    while len(g.bin) % 4:
        g.bin.append(0)
    off = len(g.bin)
    g.bin += data.tobytes()
    g.j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": int(data.nbytes), "target": 34962})
    a["bufferView"] = len(g.j["bufferViews"]) - 1
    a["count"] = int(len(data))
    a.pop("byteOffset", None)
    if minmax:
        a["min"] = data.min(0).tolist()
        a["max"] = data.max(0).tolist()


def debug_img(P, T, glass, win, cb, folder, key, fcol, flum):
    """Кадры сверху (x, z) и сбоку (x, y) носовой части с сеткой через 0.05: стекло — голубой контур,
    окно поиска — жёлтый, крестик — верх горба (ModuleParts)."""
    os.makedirs(folder, exist_ok=True)
    X0, X1, sc = -0.1, 0.55, 2400
    for view, (ib, r0, r1) in {"top": (2, -0.13, 0.13), "side": (1, -0.1, 0.13)}.items():
        Wd, Hd = int((X1 - X0) * sc), int((r1 - r0) * sc)
        im = Image.new("RGB", (Wd, Hd), (40, 40, 44))
        d = ImageDraw.Draw(im)
        tp = lambda p: ((p[0] - X0) * sc, (r1 - p[ib]) * sc)
        cen = P[T].mean(1)
        inside = (cen[:, 0] > X0 - 0.05) & (cen[:, 0] < X1 + 0.05)
        depth = cen[:, 1] if view == "top" else -cen[:, 2]
        for f in np.nonzero(inside)[0][np.argsort(depth[inside])]:
            col = tuple(int(x) for x in fcol[f])
            d.polygon([tp(p) for p in P[T[f]]], fill=col,
                      outline=(0, 170, 255) if glass[f] else None)
        for i in range(int(X0 * 20), int(X1 * 20) + 1):
            x = (i / 20 - X0) * sc
            d.line([(x, 0), (x, Hd)], fill=(255, 255, 255) if i % 2 == 0 else (130, 130, 130))
            d.text((x + 2, 2), f"{i / 20:.2f}", fill=(255, 255, 0))
        for i in range(int(r0 * 50), int(r1 * 50) + 1):
            y = (r1 - i / 50) * sc
            d.line([(0, y), (Wd, y)], fill=(90, 90, 90))
            d.text((2, y + 1), f"{i / 50:.2f}", fill=(255, 255, 0))
        c = tp(np.array([cb["x"], cb["y"], 0.0]))
        d.line([(c[0] - 8, c[1] - 8), (c[0] + 8, c[1] + 8)], fill=(255, 0, 0), width=2)
        d.line([(c[0] - 8, c[1] + 8), (c[0] + 8, c[1] - 8)], fill=(255, 0, 0), width=2)
        im.save(os.path.join(folder, f"{key}_{view}.png"))


def glass_material(g):
    for i, m in enumerate(g.j["materials"]):
        if m.get("name") == GLASS:
            return i
    g.j["materials"].append({
        "name": GLASS,
        "doubleSided": True,
        # на случай, если .import без внешнего материала: тёмное стекло с бликом
        "pbrMetallicRoughness": {"baseColorFactor": [0.03, 0.045, 0.06, 1.0], "metallicFactor": 0.4, "roughnessFactor": 0.08},
    })
    return len(g.j["materials"]) - 1


def process(path, dbg=None, dry=False):
    key = "_".join(os.path.basename(path)[:-4].split("_")[2:])
    g = glb_io.load(path)
    mesh = g.j["meshes"][0]
    mat_glass = merge_back(g, mesh)
    prim = mesh["primitives"][0]
    P, T = g.mesh_world(0, 0)
    m = g.world_of_mesh(0)
    N = g.accessor(prim["attributes"]["NORMAL"]).astype(np.float64) @ m[:3, :3].T
    UV = g.accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    img, src = base_image(path, g, prim)
    glass, info = select(P, N, UV, T, img, key, os.path.join(dbg, os.path.basename(os.path.dirname(path))) if dbg else None)
    if not glass.any():
        return
    # гладкий край: поле по выбору и разрез треугольников по нему
    f, shapes = field(P, T, glass, info["rin"])
    tin, tout = cut(g, prim, T, f)
    if mat_glass is None:
        mat_glass = glass_material(g)
    # стекло — второй примитив с теми же атрибутами (вершины общие), обшивка остаётся первой
    gp = {"attributes": dict(prim["attributes"]), "material": mat_glass, "mode": prim.get("mode", 4)}
    acc = dict(g.j["accessors"][prim["indices"]])
    g.j["accessors"].append(acc)
    gp["indices"] = len(g.j["accessors"]) - 1
    mesh["primitives"].append(gp)
    g.set_indices(0, 1, tin)
    g.set_indices(0, 0, tout)
    if dbg:   # кадры после разреза: стекло — голубым поверх текстуры
        P2 = g.mesh_world(0, 0)[0]
        UV2 = g.accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
        T2 = np.concatenate([tout, tin])
        gl = np.zeros(len(T2), bool)
        gl[len(tout):] = True
        px = np.asarray(img, dtype=np.float32)
        H, W = px.shape[:2]
        uv = UV2[T2].mean(1)
        fc = px[np.clip((uv[:, 1] % 1) * H, 0, H - 1).astype(int), np.clip((uv[:, 0] % 1) * W, 0, W - 1).astype(int)]
        fc[gl] = fc[gl] * 0.3 + np.array([0, 150, 255]) * 0.7
        debug_img(P2, T2, np.zeros(len(T2), bool), gl, info, os.path.join(dbg, "cut", os.path.basename(os.path.dirname(path))),
                  key, fc, None)
    if not dry:
        g.save(path)
    print(f"{key}: стекло {len(tin)} тр., обшивка {len(tout)} тр. (+{len(tin) + len(tout) - len(T)} от разреза); "
          f"фонарь (x от, до, полуширина, наклон и высота низа) {shapes}; текстура {os.path.basename(src)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb", nargs="+")
    ap.add_argument("--debug", default="")
    ap.add_argument("--dry", action="store_true", help="не записывать GLB")
    a = ap.parse_args()
    paths = a.glb
    if paths == ["all"]:
        paths = [os.path.join(MODELS, k, f"fh_{k}_{c}_{l}.glb") for k in ("hangar", "battle")
                 for c in ("fighter", "attacker", "bomber") for l in (1, 2)]
    for p in paths:
        process(p, a.debug or None, a.dry)


if __name__ == "__main__":
    main()
