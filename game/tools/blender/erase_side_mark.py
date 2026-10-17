"""Стереть знак на борту фюзеляжа (правило 4; тест 3.5-s3: «у Грача 2 эмблема на боку»).
Участок задаётся в осях модели ангара (длина 1, нос +X, Z вверх): x0…x1 по длине, z0…z1 по высоте.
С обоих бортов (±Y) по сетке точек с полем MARGIN вокруг участка бросаются лучи: у каждой точки — место
в текстуре (UV). Цвет точек поля известен, точки участка заполняются диффузией по сетке на самом борту
(а не по атласу: развёртка Meshy рваная, соседи в атласе — чужие детали), с лёгким шумом, и записываются
обратно в свои пиксели. Маска по UV одна и ложится на извлечённую базовую текстуру модели ангара и на
текстуру боевой модели (battle_lod.py сохраняет развёртку). Сами GLB не трогаем: Godot перезаписывает
извлечённую картинку, только если изменилась встроенная (md5).
Запуск: python3 erase_side_mark.py <модель ангара.glb> [top] x0 x1 z0 z1 <текстуры …>
  (top — знак сверху на хребте: вместо z0 z1 — y0 y1, луч сверху)"""
import sys
import numpy as np
import bpy
from mathutils import Vector, geometry
from PIL import Image

src = sys.argv[1]
TOP = sys.argv[2] == "top"   # знак сверху на хребте: второй отрезок — по ширине (y0 y1), луч сверху
args = sys.argv[3:] if TOP else sys.argv[2:]
X0, X1, Z0, Z1 = (float(a) for a in args[:4])
files = args[4:]
STEP = 0.0006
MARGIN = 0.012
SPLAT = 1     # пикселей вокруг попадания

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
dg = bpy.context.evaluated_depsgraph_get()
xs = np.arange(X0 - MARGIN, X1 + MARGIN, STEP)
zs = np.arange(Z0 - MARGIN, Z1 + MARGIN, STEP)
inside = (xs[:, None] >= X0) & (xs[:, None] <= X1) & (zs[None, :] >= Z0) & (zs[None, :] <= Z1)


def uv_at(x, z, side):
    if TOP:
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, Vector((x, z, 2.0)), Vector((0, 0, -1)))
    else:
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, Vector((x, side * 2.0, z)), Vector((0, -side, 0)))
    if not ok or ob.data.uv_layers.active is None or abs(nrm.z if TOP else nrm.y) < 0.3:
        return None
    me = ob.data
    poly = me.polygons[idx]
    uvl = me.uv_layers.active.data
    li = poly.loop_indices
    vs = [ob.matrix_world @ me.vertices[v].co for v in poly.vertices]
    for k in range(1, len(vs) - 1):
        tri = (vs[0], vs[k], vs[k + 1])
        if geometry.intersect_point_tri(loc, *tri) or k == len(vs) - 2:
            t_uv = [Vector((*uvl[li[j]].uv, 0)) for j in (0, k, k + 1)]
            b = geometry.barycentric_transform(loc, *tri, *t_uv)
            return (b.x % 1.0, b.y % 1.0)


grids = []
for side in ((1,) if TOP else (1, -1)):
    g = np.full(inside.shape + (2,), np.nan)
    for i, x in enumerate(xs):
        for j, z in enumerate(zs):
            uv = uv_at(x, z, side)
            if uv is not None:
                g[i, j] = uv
    grids.append(g)
    print("SIDE %d: %d hits, %d inside" % (side, (~np.isnan(g[..., 0])).sum(), (~np.isnan(g[..., 0]) & inside).sum()))


def diffuse(col, known):
    col = col.copy()
    known = known.copy()
    while True:
        acc = np.zeros_like(col)
        cnt = np.zeros(col.shape[:2] + (1,))
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(np.where(known[..., None], col, 0), di, 0), dj, 1)
            cnt += np.roll(np.roll(known, di, 0), dj, 1)[..., None]
        new = ~known & (cnt[..., 0] > 0)
        if not new.any():
            break
        col[new] = acc[new] / cnt[new]
        known |= new
    # сгладить залитое, чтобы не было полос от фронта диффузии
    for _ in range(int(0.004 / STEP)):
        col = (col + np.roll(col, 1, 0) + np.roll(col, -1, 0) + np.roll(col, 1, 1) + np.roll(col, -1, 1)) / 5
    return col


for path in files:
    im = Image.open(path)
    mode = im.mode
    arr = np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0
    H, W = arr.shape[:2]
    out = arr.copy()
    n_px = 0
    for g in grids:
        hit = ~np.isnan(g[..., 0])
        px = np.clip((np.nan_to_num(g[..., 0]) * W).astype(int), 0, W - 1)
        py = np.clip(((1.0 - np.nan_to_num(g[..., 1])) * H).astype(int), 0, H - 1)
        col = arr[py, px]
        known = hit & ~inside
        filled = diffuse(col, known)
        lum = col.mean(-1, keepdims=True)
        noise = (lum - lum[known].mean()) * 0.06
        for i, j in zip(*np.nonzero(hit & inside)):
            c = np.clip(filled[i, j] + noise[i, j], 0, 1)
            out[max(0, py[i, j] - SPLAT):py[i, j] + SPLAT + 1, max(0, px[i, j] - SPLAT):px[i, j] + SPLAT + 1] = c
            n_px += 1
    res = Image.fromarray((out * 255 + 0.5).clip(0, 255).astype(np.uint8), "RGB")
    if mode == "RGBA":
        res.putalpha(im.getchannel("A"))
    res.save(path, quality=92) if path.lower().endswith(".jpg") else res.save(path)
    print("ERASE %s: %d points" % (path, n_px))
