# Берег «Архипелага» начисто (замечания Kanta 19.10): батарея (целое и разбитое орудие), дот, маяк, тетраподы,
# руины, причалы, дома, колокольня, склады, кран, лодки, остовы, природа. Рецепты подключаются в biome2_models.py
# (RECIPES — эти функции заменяют прежние с тем же именем):
#   python3 -I game/tools/model_lab/biome2_models.py <имя|all>
#
# Как красим: каждая модель после сборки получает свою развёртку и одну текстуру, «запечённую» кодом (bake):
# цвет исходника или заливки детали + пятна, зерно, потёки по стенам, грязь и пыль снизу, мокрый низ у воды,
# кладка, черепица, доски, копоть. Так нет «пластика» и белых панелей: у каждой поверхности — фактура и износ.
# Потом b2lib.finish() → natural(): матовое, металл 0, без чисто белого.
import math, random
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix
import b2lib as L

# ---------------- цвета (sRGB): приглушённые, выгоревшие ----------------
PLASTER = [(0.58, 0.53, 0.44), (0.60, 0.50, 0.37), (0.52, 0.50, 0.45), (0.57, 0.51, 0.40)]   # охра, серая, песочная (не белее песка пляжа)
TILE_C = (0.62, 0.36, 0.25)       # терракота, выгоревшая
TILE_C2 = (0.55, 0.33, 0.24)
CONC = (0.38, 0.355, 0.31)        # бетон, выветренный серо-бежевый (тёплый: серый рядом с песком читается белым)
LIME = (0.58, 0.54, 0.46)         # известняк кладки
WOOD_C = (0.43, 0.35, 0.26)       # серое выгоревшее дерево
WOOD_DARK = (0.30, 0.25, 0.20)
GUNPAINT = (0.36, 0.37, 0.29)     # орудие: выгоревший тёмный хаки
DIRT = (0.42, 0.36, 0.28)
EARTH = (0.46, 0.40, 0.30)
DRYGRASS = (0.44, 0.44, 0.28)
IRON = (0.24, 0.23, 0.22)
RUST = (0.42, 0.27, 0.18)


# ================= шум =================
def _hash(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def vnoise(P, freq, seed=0):
    """Значение-шум 3D, P — (n,3) метры; результат 0..1."""
    p = P * freq
    i = np.floor(p).astype(np.int64)
    f = p - i
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(P, freq, octaves=4, seed=0):
    s, a, n = 0.0, 1.0, 0.0
    for k in range(octaves):
        s = s + a * vnoise(P, freq * (2.03 ** k), seed + k * 17)
        n += a
        a *= 0.5
    return s / n


def cell(ix, iy, seed=0):
    """Случайное 0..1 на целочисленную клетку (камень кладки, черепица, доска)."""
    return _hash(ix.astype(np.int64), iy.astype(np.int64), np.zeros_like(ix, dtype=np.int64), seed)


def mix(a, b, t):
    t = np.clip(t, 0, 1)[:, None]
    return a * (1 - t) + b * t


def col(rgb, n):
    return np.tile(np.array(rgb, dtype=np.float64)[None, :], (n, 1))


# ================= фактуры (векторные функции: base (n,3) sRGB, P (n,3) м, N (n,3)) =================
def tangent_u(P, N):
    """Горизонтальная координата вдоль стены (для кладки, досок): проекция на касательную к стене."""
    t = np.stack([-N[:, 1], N[:, 0], np.zeros(len(N))], 1)
    ln = np.linalg.norm(t, axis=1, keepdims=True)
    t = np.where(ln > 1e-3, t / np.maximum(ln, 1e-6), np.array([[1.0, 0, 0]]))
    return (P * t).sum(1)


def weather(base, P, N, seed=0, stain=0.16, grain=0.07, streak=0.12, grime_h=1.2, grime=0.45, dust=0.10, z0=0.0):
    """Износ: крупные пятна, зерно, потёки на стенах, грязь у земли, пыль на горизонталях."""
    n = len(P)
    up = np.clip(N[:, 2], -1, 1)
    c = base * (1 + stain * (fbm(P, 0.18, 3, seed) - 0.5) * 2)[:, None]
    c = c * (1 + grain * (fbm(P, 2.2, 3, seed + 5) - 0.5) * 2)[:, None]
    wall = np.clip(1 - np.abs(up) * 1.4, 0, 1)
    st = vnoise(P * np.array([1.0, 1.0, 0.06]), 2.4, seed + 9)
    st = np.clip((st - 0.45) * 2.5, 0, 1) * wall
    c = c * (1 - streak * st)[:, None]
    g = np.clip(1 - (P[:, 2] - z0) / max(grime_h, 1e-3), 0, 1) ** 1.6
    g = g * (0.7 + 0.6 * fbm(P, 0.9, 2, seed + 3))
    c = mix(c, col(DIRT, n), grime * g)
    c = mix(c, col((0.56, 0.52, 0.43), n), dust * np.clip(up - 0.6, 0, 1) * 2.5 * fbm(P, 0.6, 2, seed + 7))
    return c


def masonry(base, P, N, row=0.42, blen=0.75, mortar=0.035, seed=0, var=0.16):
    """Кладка из камня: ряды по высоте, со смещением; цвет камня меняется, швы темнее."""
    u = tangent_u(P, N)
    z = P[:, 2]
    r = np.floor(z / row)
    uu = u / blen + 0.5 * (r % 2) + cell(r, r, seed + 1) * 0.37
    cidx = np.floor(uu)
    fz = z / row - r
    fu = uu - cidx
    k = 1 + var * (cell(r, cidx, seed) - 0.5) * 2
    c = base * k[:, None]
    mz, mu = mortar / row, mortar / blen
    seam = (fz < mz) | (fz > 1 - mz) | (fu < mu) | (fu > 1 - mu)
    flat = np.abs(N[:, 2]) > 0.7   # верх стены — без рисунка кладки, только пятна
    seam = seam & ~flat
    c = np.where(seam[:, None], c * 0.62, c)
    edge = np.minimum(np.minimum(fz, 1 - fz) / 0.2, np.minimum(fu, 1 - fu) / 0.15)
    c = c * (0.9 + 0.1 * np.clip(edge, 0, 1))[:, None]
    return c


def tiles(base, P, N, seed=0):
    """Черепица: ряды поперёк ската, каждая плитка своего оттенка, тени под рядами."""
    z = P[:, 2]
    r = np.floor(z / 0.22)
    u = tangent_u(P, N) / 0.26 + 0.5 * (r % 2)
    ci = np.floor(u)
    k = 1 + 0.2 * (cell(r, ci, seed) - 0.5) * 2
    fz = z / 0.22 - r
    sh = 0.72 + 0.28 * np.clip(fz / 0.35, 0, 1)
    fu = u - ci
    gap = np.where((fu < 0.06) | (fu > 0.94), 0.8, 1.0)
    c = base * (k * sh * gap)[:, None]
    lich = np.clip((fbm(P, 0.5, 3, seed + 3) - 0.58) * 4, 0, 1)   # выгоревшие и замшелые участки
    return mix(c, col((0.56, 0.52, 0.42), len(P)), 0.45 * lich)


def planks(base, P, N, width=0.22, along='x', seed=0, gap=0.012, var=0.18):
    """Доски: вдоль оси along, у каждой свой тон; щели тёмные."""
    a = P[:, 0] if along == 'x' else P[:, 1]
    b = P[:, 1] if along == 'x' else P[:, 0]
    wall = np.abs(N[:, 2]) < 0.6
    b = np.where(wall, P[:, 2], b)
    i = np.floor(b / width)
    seg = np.floor(a / 3.2 + cell(i, i, seed + 4) * 3)
    k = 1 + var * (cell(i, seg, seed) - 0.5) * 2
    f = b / width - i
    c = base * k[:, None]
    c = c * (1 + 0.08 * (vnoise(P * np.array([0.3, 0.3, 0.3]) + np.stack([a * 6, i, i * 0], 1), 1.0, seed + 2) - 0.5))[:, None]
    return np.where(((f < gap / width) | (f > 1 - gap / width))[:, None], c * 0.45, c)


def corrugated(base, P, N, pitch=0.18, along='x'):
    a = P[:, 0] if along == 'x' else P[:, 1]
    return base * (0.9 + 0.1 * np.cos(a / pitch * 2 * math.pi))[:, None]


def soot(c, P, centers, r=3.0, seed=0, strength=0.85):
    """Копоть пятнами вокруг точек взрыва: не сплошная чернота — рваные пятна с просветами."""
    n = len(P)
    s = np.zeros(n)
    for cc, rr in centers:
        d = np.linalg.norm(P - np.array(cc), axis=1) / rr
        s = np.maximum(s, np.clip(1.2 - d, 0, 1))
    blot = fbm(P, 1.1, 4, seed)
    s = np.clip(s * 1.4 - (1 - blot) * 0.9, 0, 1)
    return mix(c, col((0.07, 0.065, 0.06), n), strength * s)


# ================= запекание =================
def _srgb(c):
    return [x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055 for x in c[:3]]


def color_tex(m):
    """Текстура цвета материала: прямо в Base Color или через Mix (как у маяка-исходника); карты нормалей не берём."""
    t = L.tex_of(m)
    if t:
        return t
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image and all(l.to_node.type in ('MIX', 'MIX_RGB', 'BSDF_PRINCIPLED') and l.to_socket.name != 'Normal'
                                                        for l in n.outputs['Color'].links) and n.outputs['Color'].links:
            return n.image
    return None


def lum_norm(base):
    """Яркость текстуры исходника относительно её средней по самой модели (чёрные поля атласа не в счёт)."""
    l = base @ np.array([0.3, 0.59, 0.11])
    return l / max(1e-3, float(np.median(l)))


def unwrap(ob, margin=0.004, angle=60):
    """Своя развёртка 'paint' (smart project) — равная плотность текселей по всей модели."""
    me = ob.data
    for o in list(bpy.context.view_layer.objects):
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    uv = me.uv_layers.new(name='paint')
    me.uv_layers.active = uv
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return uv


def bake(ob, shade, size=1024, name=None, rough=0.92, unwrap_angle=60, margin=0.004):
    """Запечь цвет модели в одну текстуру по своей развёртке.
    shade(base, P, N, mat_names[idx]) → цвет (n,3) sRGB; base — цвет детали (заливка или текстура исходника по старой UV),
    P — точка (м, рабочие оси), N — нормаль грани, idx — номер материала. Старые материалы и UV убираются."""
    me = ob.data
    old_uv = next((u.name for u in me.uv_layers if u.name != 'paint'), None)
    if 'paint' not in me.uv_layers:   # развёртку 'paint' можно сделать заранее (b2_ships: мельче под водой)
        unwrap(ob, margin, unwrap_angle)
    me.calc_loop_triangles()
    nl = len(me.loops)
    uvn = np.zeros(nl * 2); me.uv_layers['paint'].data.foreach_get('uv', uvn); uvn = uvn.reshape(-1, 2)
    uvo = np.zeros(nl * 2)
    if old_uv:
        me.uv_layers[old_uv].data.foreach_get('uv', uvo)
    uvo = uvo.reshape(-1, 2)
    vi = np.zeros(nl, dtype=np.int64); me.loops.foreach_get('vertex_index', vi)
    co = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
    nt = len(me.loop_triangles)
    tl = np.zeros(nt * 3, dtype=np.int64); me.loop_triangles.foreach_get('loops', tl); tl = tl.reshape(-1, 3)
    tm = np.zeros(nt, dtype=np.int64); me.loop_triangles.foreach_get('material_index', tm)
    tn = np.zeros(nt * 3); me.loop_triangles.foreach_get('normal', tn); tn = tn.reshape(-1, 3)
    mats = list(me.materials)
    # источники цвета деталей
    src = []
    for m in mats:
        img = color_tex(m) if (m and m.use_nodes) else None
        if img is not None and img.size[0] > 0:
            src.append(('img', L.pixels(img)[..., :3].astype(np.float64)))
        else:
            c = L.bsdf(m).inputs['Base Color'].default_value if (m and m.use_nodes) else (0.6, 0.6, 0.6, 1)
            src.append(('col', np.array(_srgb(c))))
    W = H = size
    acc_i, acc_b, acc_t = [], [], []
    for t in range(nt):
        lp = tl[t]
        q = uvn[lp] * (W, H) - 0.5
        x0, y0 = np.floor(q.min(0)).astype(int); x1, y1 = np.ceil(q.max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, W - 1), min(y1, H - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        gx = gx.ravel().astype(np.float64); gy = gy.ravel().astype(np.float64)
        (ax, ay), (bx, by), (cx, cy) = q
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        w0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
        w1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
        w2 = 1 - w0 - w1
        e = -0.02
        ins = (w0 >= e) & (w1 >= e) & (w2 >= e)
        if not ins.any():
            continue
        acc_i.append((gy[ins] * W + gx[ins]).astype(np.int64))
        acc_b.append(np.stack([w0[ins], w1[ins], w2[ins]], 1))
        acc_t.append(np.full(int(ins.sum()), t, dtype=np.int64))
    idx = np.concatenate(acc_i); bw = np.concatenate(acc_b); tri = np.concatenate(acc_t)
    lp = tl[tri]                                   # (n,3) петли
    P = (co[vi[lp]] * bw[:, :, None]).sum(1)
    Nn = tn[tri]
    M = tm[tri]
    base = np.zeros((len(idx), 3))
    for k, (kind, s) in enumerate(src):
        sel = M == k
        if not sel.any():
            continue
        if kind == 'col':
            base[sel] = s
        else:
            uvi = (uvo[lp[sel]] * bw[sel][:, :, None]).sum(1)
            h, w = s.shape[:2]
            px = np.mod(uvi[:, 0], 1.0) * w - 0.5; py = np.mod(uvi[:, 1], 1.0) * h - 0.5
            ix = np.floor(px).astype(int); iy = np.floor(py).astype(int); fx = (px - ix)[:, None]; fy = (py - iy)[:, None]
            ix0, iy0 = ix % w, iy % h; ix1, iy1 = (ix + 1) % w, (iy + 1) % h
            base[sel] = (s[iy0, ix0] * (1 - fx) * (1 - fy) + s[iy0, ix1] * fx * (1 - fy) + s[iy1, ix0] * (1 - fx) * fy + s[iy1, ix1] * fx * fy)
    names = [m.name if m else '' for m in mats]
    out = np.clip(shade(base, P, Nn, M, names), 0, 1)
    # потолок яркости: в игре солнце 1,15 + небо 0,5 — всё светлее ~0,45 выгорает в белое на фоне песка пляжа.
    # Выше колена яркость сжимается (оттенок сохраняется): ни одна крупная поверхность не светлее песка.
    lum = out @ np.array([0.3, 0.59, 0.11])
    knee = 0.36
    k = np.where(lum > knee, (knee + (lum - knee) * 0.35) / np.maximum(lum, 1e-4), 1.0)
    out = out * k[:, None]
    img = np.zeros((H * W, 3)); filled = np.zeros(H * W, dtype=bool)
    img[idx] = out; filled[idx] = True
    img = img.reshape(H, W, 3); filled = filled.reshape(H, W)
    for _ in range(6):   # растянуть края островов на поля (без швов при мип-картах)
        if filled.all():
            break
        acc = np.zeros_like(img); cnt = np.zeros((H, W))
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            sh = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += np.where(sh[..., None], np.roll(np.roll(img, dy, 0), dx, 1), 0); cnt += sh
        grow = ~filled & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        filled |= grow
    if not filled.all():
        img[~filled] = img[filled].mean(0)
    nm = name or ob.name
    im = bpy.data.images.new('paint_' + nm, W, H)
    a = np.ones((H, W, 4), dtype=np.float32); a[..., :3] = img
    L.put_pixels(im, a)
    mat = bpy.data.materials.new('fh_' + nm); mat.use_nodes = True
    nt_ = mat.node_tree; b = nt_.nodes['Principled BSDF']
    tx = nt_.nodes.new('ShaderNodeTexImage'); tx.image = im
    nt_.links.new(tx.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = 0.0
    me.materials.clear(); me.materials.append(mat)
    for p in me.polygons:
        p.material_index = 0
    for u in [u for u in me.uv_layers if u.name != 'paint']:
        me.uv_layers.remove(u)
    print("BAKE", nm, "texels", len(idx), "tris", nt)
    return ob


def by_mat(table, default=None):
    """shade-функция по имени материала: table = {префикс: f(base, P, N)}."""
    def f(base, P, N, M, names):
        out = base.copy()
        for k, nm in enumerate(names):
            sel = M == k
            if not sel.any():
                continue
            fn = next((v for p, v in table.items() if nm.startswith(p)), default)
            if fn is not None:
                out[sel] = fn(base[sel], P[sel], N[sel])
        return out
    return f


# ================= геометрия =================
def chamfer(objs, w=0.05, seg=1, sharp=40):
    """Фаска по рёбрам (ловит свет, убирает «картонность») + сглаживание с острыми рёбрами."""
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0) > math.radians(30)]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=w, segments=seg, affect='EDGES', profile=0.5, clamp_overlap=True)
        bm.to_mesh(o.data); bm.free()
    L.smooth(objs, sharp)


def join_bake(objs, shade, name, size=1024, **kw):
    ob = L.join([o for o in objs if o.name in bpy.data.objects and len(o.data.polygons)], name)
    L.weld([ob], 1e-5)
    return bake(ob, shade, size=size, name=name, **kw)


def prism_y(pts_xz, y0, y1, mat, name='prism'):
    """Призма: профиль в плоскости XZ, вытянутый по Y от y0 до y1."""
    return L.loft([[(x, y0, z) for x, z in pts_xz], [(x, y1, z) for x, z in pts_xz]], mat, name)


def arc_wall(c, r_in, r_out, h_in, h_out, a0, a1, mat, name='arc', seg=24):
    """Кольцевая стенка-сектор с наклонной внешней гранью (бруствер)."""
    bm = bmesh.new()
    n = max(2, int(seg * abs(a1 - a0) / (2 * math.pi)) + 1)
    rings = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((c[0] + r * ca, c[1] + r * sa, c[2] + z)) for r, z in
                      ((r_in, 0), (r_in, h_in), (r_out - (r_out - r_in) * 0.35, h_out), (r_out, 0))])
    for a, b in zip(rings, rings[1:]):
        for i in range(3):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
        bm.faces.new((a[3], a[0], b[0], b[3]))
    bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return L._new(name, bm, mat)


def jag(o, amp, seed=0, axis=None):
    """Рваный край: сдвинуть вершины случайно (для разбитых деталей, обломов стен)."""
    rng = random.Random(seed)
    for v in o.data.vertices:
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * amp
        if axis is not None:
            d = Vector([d[i] if axis[i] else 0 for i in range(3)])
        v.co += d


def subdiv(o, cuts=2):
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=cuts, use_grid_fill=True)
    bm.to_mesh(o.data); bm.free()


def plate(quad, t, mat, name='plate'):
    """Пластина брони по четырём точкам (по кругу) толщиной t (внутрь — по нормали к квадрату)."""
    a, b, c, d = [Vector(p) for p in quad]
    n = (b - a).cross(d - a).normalized() * t
    return L.hull([tuple(p) for p in (a, b, c, d)] + [tuple(p - n) for p in (a, b, c, d)], mat, name)


def tear(o, up, depth, seed=0, cuts=5):
    """Рваный край пластины: сетка мельче, вершины у края up опускаются на случайную глубину (оторванный металл)."""
    subdiv(o, cuts)
    rng = random.Random(seed)
    up = Vector(up).normalized()
    hs = [v.co.dot(up) for v in o.data.vertices]
    top = max(hs); span = top - min(hs)
    cut = {}
    for v, h in zip(o.data.vertices, hs):
        k = (h - (top - span * 0.45)) / (span * 0.45)
        if k > 0:
            key = (round(v.co.x, 2), round(v.co.y, 2), round(v.co.z, 2))
            d = cut.setdefault(key, rng.uniform(0.15, 1.0) * depth)
            v.co -= up * d * k


SAND_C = (0.52, 0.47, 0.37)       # мешковина, пыльная


# ================= мешки с песком (как пост Нагорья, game/tools/blender/biome_flora.py → bag) =================
def bags(items, mat, name='sandbag', seed=0, size=(0.4, 0.23, 0.1), ns=4, nt=6):
    """Мешки-подушки одной сеткой. items — [(центр, yaw)]. Сечение — суперэллипс, к завязанным концам уже и тоньше,
    на концах «ушки», верх просел. size — полуразмеры (0,8 × 0,46 × 0,2 м). ns×nt×2 + 2nt треугольников на мешок."""
    rng = random.Random(seed)
    Lh, Wh, Hh = size
    bm = bmesh.new()
    for c, yaw in items:
        R = Matrix.Rotation(yaw, 3, 'Z') @ Matrix.Rotation(rng.uniform(-0.06, 0.06), 3, 'X') @ Matrix.Rotation(rng.uniform(-0.04, 0.04), 3, 'Y')
        c = Vector(c)
        sx = rng.uniform(0.92, 1.08)
        rows = []
        for i in range(ns):
            s = (-1 + 2 * i / (ns - 1)) * 0.86
            fw = 1 - 0.32 * abs(s) ** 3
            fh = 1 - 0.45 * abs(s) ** 2.5
            row = []
            for k in range(nt):
                t = 2 * math.pi * k / nt + math.pi / nt
                ct, st = math.cos(t), math.sin(t)
                y = math.copysign(abs(ct) ** 0.55, ct) * Wh * fw
                z = math.copysign(abs(st) ** 0.6, st) * Hh * fh
                z = z * (1 - 0.18 * (1 - abs(s))) if z > 0 else z * 0.85
                row.append(bm.verts.new(c + R @ Vector((s * Lh * sx, y, z))))
            rows.append(row)
        for i in range(ns - 1):
            for k in range(nt):
                j = (k + 1) % nt
                bm.faces.new((rows[i][k], rows[i][j], rows[i + 1][j], rows[i + 1][k]))
        for end, row in ((-1, rows[0]), (1, rows[-1])):
            tip = bm.verts.new(c + R @ Vector((end * Lh * sx * 1.04, rng.uniform(-0.3, 0.3) * Wh, Hh * 0.1)))
            for k in range(nt):
                j = (k + 1) % nt
                bm.faces.new((row[k], row[j], tip) if end > 0 else (row[j], row[k], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = L._new(name, bm, mat)
    L.smooth([o], 80)
    return o


def bag_row(p0, p1, z, layers=2, size=(0.4, 0.23, 0.1)):
    """Мешки вдоль отрезка p0→p1 в layers рядов, вперевязку."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0; n = max(1, int(d.length / (size[0] * 1.9))); yaw = math.atan2(d.y, d.x)
    out = []
    for lay in range(layers):
        off = 0.5 if lay % 2 else 0.0
        for k in range(n - (1 if off else 0)):
            t = (k + 0.5 + off) / n
            p = p0 + d * t
            out.append(((p.x, p.y, z + size[2] * 0.85 + lay * size[2] * 1.75), yaw))
    return out


def f_burlap(seed=0):
    """Мешковина: пыльный бежево-серый, у каждого мешка свой тон, тёмные складки и щели снизу, пыль сверху."""
    def f(b, P, N):
        n = len(P)
        c = b * (1 + 0.22 * (vnoise(P, 1.3, seed) - 0.5) * 2)[:, None]          # мешки разного тона
        c = c * (1 + 0.10 * (vnoise(P, 9.0, seed + 1) - 0.5) * 2)[:, None]      # складки ткани
        under = np.clip(-N[:, 2] * 1.5, 0, 1)
        c = c * (1 - 0.55 * under)[:, None]                                     # тень в щелях между мешками
        c = mix(c, col((0.40, 0.35, 0.27), n), 0.35 * np.clip((fbm(P, 0.7, 3, seed + 2) - 0.5) * 3, 0, 1))   # сырые и грязные
        return mix(c, col((0.55, 0.51, 0.42), n), 0.25 * np.clip(N[:, 2], 0, 1) * fbm(P, 1.1, 2, seed + 3))
    return f


def cut(ob, cutters):
    """Булев вырез (амбразуры, ниши): cutters удаляются."""
    for c in cutters:
        m = ob.modifiers.new('cut', 'BOOLEAN'); m.operation = 'DIFFERENCE'; m.object = c; m.solver = 'EXACT'
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    old = ob.data; ob.data = me; bpy.data.meshes.remove(old)
    for c in cutters:
        bpy.data.objects.remove(c)
    return ob


def mound(c, r_in, r_rim, r_out, h, mat, name='mound', seg=28, seed=0, floor=0.03):
    """Воронка: дно чуть над землёй (z=floor), вал высотой h на r_rim, к r_out сходит в ноль; край рваный."""
    rng = random.Random(seed)
    bm = bmesh.new()
    rad = [0.0, r_in * 0.5, r_in, (r_in + r_rim) / 2, r_rim, (r_rim + r_out) / 2, r_out]
    zz = [floor, floor, floor + 0.05, h * 0.75, h, h * 0.35, 0.0]
    jit = [1 + rng.uniform(-0.18, 0.18) for _ in range(seg)]
    rings = []
    for r, z in zip(rad, zz):
        if r == 0:
            rings.append([bm.verts.new((c[0], c[1], z))])
            continue
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rr = r * jit[i] * (1 + rng.uniform(-0.05, 0.05))
            ring.append(bm.verts.new((c[0] + rr * math.cos(a), c[1] + rr * math.sin(a), z * (1 + rng.uniform(-0.2, 0.2)) if z > 0.05 else z)))
        rings.append(ring)
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((rings[0][0], rings[1][i], rings[1][j]))
    for a, b in zip(rings[1:], rings[2:]):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    o = L._new(name, bm, mat)
    L.smooth([o], 70)
    return o


def scorch_patch(c, r, mat, name='scorch', seg=24, seed=0, z=0.025):
    """Выжженная земля: плоское пятно с рваным краем чуть над землёй."""
    rng = random.Random(seed)
    bm = bmesh.new()
    cv = bm.verts.new((c[0], c[1], z))
    mid, out = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        k = rng.uniform(0.6, 1.15)
        mid.append(bm.verts.new((c[0] + r * 0.55 * k * math.cos(a), c[1] + r * 0.55 * k * math.sin(a), z)))
        out.append(bm.verts.new((c[0] + r * k * math.cos(a), c[1] + r * k * math.sin(a), z * 0.4)))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((cv, mid[i], mid[j]))
        bm.faces.new((mid[i], out[i], out[j], mid[j]))
    return L._new(name, bm, mat)


# ================= Т-1 береговая батарея: орудие в бетонном дворике (целое и разбитое) =================
def _gun_site(broken):
    rng = random.Random(7)
    conc = L.flat('conc', CONC, 0.95); gun = L.flat('gun', GUNPAINT, 0.9); iron = L.flat('iron', IRON, 0.9)
    sand = L.flat('sand', SAND_C, 1.0); floor = L.flat('floor', CONC, 0.95); brass = L.flat('brass', (0.55, 0.46, 0.30), 0.9)
    o = [L.cyl((0, 0, 0.125), 6.0, 0.25, floor, 'floor', seg=40)]
    gap = 0.42
    if not broken:
        o.append(arc_wall((0, 0, 0), 5.9, 6.8, 1.2, 1.3, -math.pi + gap, math.pi - gap, conc, 'parapet', seg=56))
    else:   # пролом бруствера спереди слева, куски бетона
        o.append(arc_wall((0, 0, 0), 5.9, 6.8, 1.2, 1.3, -math.pi + gap, 0.15, conc, 'parapet', seg=56))
        o.append(arc_wall((0, 0, 0), 5.9, 6.8, 1.2, 1.3, 0.75, math.pi - gap, conc, 'parapet', seg=56))
        for k in range(9):
            a = rng.uniform(0.1, 0.85); r = rng.uniform(5.4, 6.5); s = rng.uniform(0.35, 0.8)
            b = L.box((r * math.cos(a), r * math.sin(a), s * 0.35), (s, s * 0.8, s * 0.6), conc, 'rubble', rz=rng.uniform(0, 3))
            subdiv(b, 1); jag(b, s * 0.12, seed=k); o.append(b)
    # торцы бруствера у входа, ниши боезапаса, ящики, снаряды
    for sg in (-1, 1):
        a = math.pi - gap
        o.append(L.box((6.35 * math.cos(a), sg * 6.35 * math.sin(a), 0.6), (0.9, 0.5, 1.2), conc, 'pier', rz=sg * (math.pi / 2 - a)))
        a2 = sg * 2.2
        o.append(L.box((5.55 * math.cos(a2), 5.55 * math.sin(a2), 0.75), (0.7, 1.6, 1.0), conc, 'niche', rz=a2))
        o.append(L.box((5.18 * math.cos(a2), 5.18 * math.sin(a2), 0.75), (0.05, 1.2, 0.7), iron, 'niche_door', rz=a2))
        o.append(L.box((-3.6, sg * 3.3, 0.55), (1.1, 0.6, 0.6), gun, 'locker', rz=sg * 0.5))
    for k in range(5):   # снаряды в стойке у задней стенки
        o.append(L.cyl((-4.9, -1.0 + k * 0.28, 0.42), 0.11, 0.9, brass, 'shell', seg=8, axis='X'))
    o.append(L.box((-4.9, -0.45, 0.28), (1.1, 1.6, 0.08), iron, 'rack'))
    # мешки с песком по гребню бруствера спереди: два ряда понизу, один поверх вперевязку (подушки, как у поста Нагорья)
    items = []
    for lay, rr in ((0, 6.0), (0, 6.42), (1, 6.21)):
        step = 0.80 / rr
        a = -1.1 + (step / 2 if lay else 0)
        while a < 1.1:
            if not (broken and 0.0 < a < 0.9):
                z = (1.21 if rr < 6.1 else 1.27) + 0.085 + lay * 0.175
                items.append(((rr * math.cos(a), rr * math.sin(a), z), a + math.pi / 2))
            a += step
    o.append(bags(items, sand, 'sandbag', seed=3))
    if broken:   # мешки, сброшенные взрывом: лежат вразброс у пролома, внутри и снаружи
        r2 = random.Random(21)
        spill = [((r * math.cos(a), r * math.sin(a), 0.33 if r < 5.9 else 0.085), r2.uniform(0, 3))
                 for a, r in [(r2.uniform(0.0, 0.9), r2.uniform(5.0, 8.4)) for _ in range(14)]]
        o.append(bags(spill, sand, 'sandbag', seed=4))
    # тумба, погон, щит, ствол
    o += [L.cyl((0, 0, 0.55), 1.0, 0.6, iron, 'pedestal', seg=24),
          L.cyl((0, 0, 0.95), 2.0, 0.22, gun, 'turntable', seg=36)]
    z0, z1 = 1.06, 2.95
    front = [(1.55, -1.55, z0), (1.55, 1.55, z0), (0.95, 1.3, z1), (0.95, -1.3, z1)]
    roof = [(0.95, -1.3, z1), (0.95, 1.3, z1), (-2.0, 1.36, z1 - 0.05), (-2.0, -1.36, z1 - 0.05)]
    side_l = [(-2.0, 1.55, z0), (1.55, 1.55, z0), (0.95, 1.3, z1), (-2.0, 1.36, z1 - 0.05)]
    side_r = [(1.55, -1.55, z0), (-2.0, -1.55, z0), (-2.0, -1.36, z1 - 0.05), (0.95, -1.3, z1)]
    pf = plate(front, 0.09, gun, 'shield_front'); pr = plate(roof, 0.07, gun, 'shield_roof')
    pl = plate(side_l, 0.07, gun, 'shield_side'); pr2 = plate(side_r, 0.07, gun, 'shield_side')
    breech = L.box((-0.4, 0, 1.95), (1.6, 0.7, 0.6), iron, 'breech')
    cradle = L.box((0.2, 0, 1.6), (2.4, 0.9, 0.35), gun, 'cradle')
    sight = [L.box((0.3, 0.95, 2.4), (0.5, 0.2, 0.3), iron, 'sight'), L.cyl((-0.6, -0.8, z1 + 0.25), 0.12, 0.5, iron, 'periscope', seg=8)]
    el = Matrix.Rotation(math.radians(-4), 4, 'Y')
    if not broken:
        barrel = [L.cyl((4.4, 0, 0), 0.17, 6.6, gun, 'barrel', seg=16, axis='X', r2=0.13),
                  L.cyl((7.6, 0, 0), 0.165, 0.32, gun, 'muzzle', seg=16, axis='X'),
                  L.cyl((1.35, 0, 0), 0.34, 0.9, gun, 'mantlet', seg=16, axis='X'),
                  L.cyl((1.5, 0, -0.28), 0.12, 1.8, iron, 'recoil', seg=10, axis='X')]
        for b in barrel:
            b.data.transform(Matrix.Translation((0, 0, 2.0)) @ el)
        o += [pf, pr, pl, pr2, breech, cradle] + sight + barrel
    else:
        # щит разворочен: крыша сорвана и лежит у бруствера, левый борт отогнут наружу, верх рваный
        tear(pf, (0, 0, 1), 0.9, seed=3)
        tear(pl, (0, 0, 1), 0.7, seed=4)
        pl.data.transform(Matrix.Translation((0, 1.55, z0)) @ Matrix.Rotation(math.radians(-32), 4, 'X') @ Matrix.Translation((0, -1.55, -z0)))
        tear(pr2, (0, 0, 1), 0.5, seed=5)
        tear(pr, (-1, 0, 0), 0.8, seed=6)
        pr.data.transform(Matrix.Translation((-3.4, -2.9, 0.75)) @ Matrix.Rotation(math.radians(55), 4, 'Z') @ Matrix.Rotation(math.radians(24), 4, 'X')
                          @ Matrix.Translation((0.5, 0, -z1)))
        # ствол переломлен: обрубок опущен, отломанная часть лежит через пролом бруствера
        stub = [L.cyl((2.4, 0, 0), 0.17, 2.6, gun, 'barrel', seg=16, axis='X', r2=0.155),
                L.cyl((1.35, 0, 0), 0.34, 0.9, gun, 'mantlet', seg=16, axis='X'),
                L.cyl((1.5, 0, -0.28), 0.12, 1.8, iron, 'recoil', seg=10, axis='X')]
        tip = L.cyl((3.85, 0, 0), 0.165, 0.35, iron, 'barrel_torn', seg=16, axis='X', r2=0.2)
        subdiv(tip, 1); jag(tip, 0.06, seed=8)
        stub.append(tip)
        for b in stub:
            b.data.transform(Matrix.Translation((0, 0, 2.0)) @ Matrix.Rotation(math.radians(9), 4, 'Y'))
        piece = [L.cyl((0, 0, 0), 0.15, 4.0, gun, 'barrel_piece', seg=16, axis='X', r2=0.13),
                 L.cyl((2.15, 0, 0), 0.165, 0.32, gun, 'muzzle', seg=16, axis='X')]
        end = L.cyl((-2.1, 0, 0), 0.15, 0.3, iron, 'barrel_torn', seg=16, axis='X', r2=0.19)
        subdiv(end, 1); jag(end, 0.06, seed=9); piece.append(end)
        for b in piece:
            b.data.transform(Matrix.Translation((4.3, 2.3, 0.62)) @ Matrix.Rotation(0.45, 4, 'Z') @ Matrix.Rotation(math.radians(-9), 4, 'Y'))
        breech.data.transform(Matrix.Rotation(math.radians(6), 4, 'Z'))
        o += [pf, pr, pl, pr2, breech, cradle] + stub + piece + [sight[0]]
        bpy.data.objects.remove(sight[1])
        for k in range(14):   # осколки брони и бетона на полу
            a = rng.uniform(0, 2 * math.pi); r = rng.uniform(2.0, 5.4); s = rng.uniform(0.25, 0.7)
            c = Vector((r * math.cos(a), r * math.sin(a), 0.3))
            b = L.box((0, 0, 0), (s, s * 0.7, 0.05), gun if k % 2 else iron, 'shard')
            b.data.transform(Matrix.Translation(c) @ Matrix.Rotation(rng.uniform(0, 3), 4, 'Z') @ Matrix.Rotation(rng.uniform(-0.5, 0.5), 4, 'X'))
            o.append(b)
        # воронка от попадания перед проломом, выжженная земля вокруг пролома и орудия
        earth_m = L.flat('earth', EARTH, 1.0); scorch_m = L.flat('scorch', (0.20, 0.18, 0.16), 1.0)
        crater_c = (8.6 * math.cos(0.42), 8.6 * math.sin(0.42))
        o.append(mound(crater_c, 1.5, 2.4, 3.6, 0.55, earth_m, 'crater', seed=5))
        o.append(scorch_patch((7.4 * math.cos(0.45), 7.4 * math.sin(0.45)), 5.2, scorch_m, 'scorch', seed=6))
        # кусок бруствера вывален наружу: сегмент стенки опрокинут и сдвинут от пролома, края рваные, торчит арматура
        chunk = arc_wall((0, 0, 0), 5.9, 6.8, 1.2, 1.3, 0.28, 0.58, conc, 'parapet_chunk', seg=56)
        subdiv(chunk, 2); jag(chunk, 0.12, seed=11)
        ca = 0.43
        chunk.data.transform(Matrix.Translation((8.0 * math.cos(ca), 8.0 * math.sin(ca), 0.45)) @ Matrix.Rotation(ca, 4, 'Z')
                             @ Matrix.Rotation(math.radians(68), 4, "Y") @ Matrix.Rotation(-ca, 4, 'Z')
                             @ Matrix.Translation((-6.35 * math.cos(ca), -6.35 * math.sin(ca), -0.6)))
        o.append(chunk)
        for a_end in (0.15, 0.75):   # арматура из торцов пролома
            for k in range(3):
                r = 6.0 + 0.3 * k; zb = 0.4 + 0.3 * k
                p0 = Vector((r * math.cos(a_end), r * math.sin(a_end), zb))
                d = Vector((math.cos(a_end + (0.9 if a_end < 0.4 else -0.9) * math.pi / 2), math.sin(a_end + (0.9 if a_end < 0.4 else -0.9) * math.pi / 2),
                            rng.uniform(-0.2, 0.5))).normalized()
                ln = rng.uniform(0.5, 0.9)
                rod = L.cyl((0, 0, 0), 0.025, ln, iron, 'rebar', seg=4)
                rod.data.transform(Matrix.Translation(p0 + d * ln / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4())
                o.append(rod)
        for k in range(16):   # глыбы бетона, выброшенные наружу
            a = rng.uniform(0.0, 0.95); r = rng.uniform(6.9, 11.5); s = rng.uniform(0.3, 1.0)
            b = L.box((r * math.cos(a), r * math.sin(a), s * 0.25), (s, s * rng.uniform(0.6, 0.9), s * 0.55), conc, 'rubble', rz=rng.uniform(0, 3))
            subdiv(b, 1); jag(b, s * 0.15, seed=40 + k); o.append(b)
    chamfer([b for b in o if b.name.startswith(('parapet', 'pier', 'niche', 'locker', 'breech', 'cradle'))], 0.04)
    L.smooth([b for b in o if b.name.startswith(('barrel', 'muzzle', 'mantlet', 'recoil', 'pedestal', 'turntable', 'shell', 'floor'))], 50)
    L.smooth([b for b in o if b.name.startswith(('shield', 'sandbag'))], 30)

    def concrete(b, P, N):
        n = len(P)
        c = weather(b, P, N, seed=11, stain=0.22, grain=0.1, grime_h=0.8, grime=0.55, streak=0.32)
        lines = np.where((np.abs(N[:, 2]) < 0.5) & (np.mod(P[:, 2], 0.45) < 0.025), 0.88, 1.0)   # следы опалубки
        c = c * lines[:, None]
        chip = np.clip((vnoise(P, 3.0, 61) - 0.80) * 6, 0, 1)                # сколы: свежий излом чуть светлее, с тёмной кромкой
        rim = np.clip((vnoise(P, 3.0, 61) - 0.74) * 6, 0, 1) - chip
        c = mix(c, c * 1.12, chip); c = mix(c, c * 0.7, np.clip(rim, 0, 1))
        moss = np.clip((fbm(P, 0.6, 3, 62) - 0.55) * 4, 0, 1) * np.clip(1 - P[:, 2] / 0.6, 0, 1)
        return mix(c, col((0.30, 0.31, 0.22), n), 0.45 * moss)              # зелёный налёт у основания

    def scorch_f(b, P, N):
        n = len(P)
        r = np.linalg.norm(P[:, :2] - np.array([7.4 * math.cos(0.45), 7.4 * math.sin(0.45)]), axis=1)
        burnt = np.clip(1.25 - r / 4.2, 0, 1) * (0.55 + 0.6 * fbm(P, 0.8, 4, 63))
        c = mix(col(EARTH, n) * 0.85, col((0.09, 0.085, 0.08), n), np.clip(burnt, 0, 1))
        return c * (1 + 0.15 * (vnoise(P, 4.0, 64) - 0.5))[:, None]

    def crater_f(b, P, N):
        n = len(P)
        c = f_earth(65)(b, P, N)
        r = np.linalg.norm(P[:, :2] - np.array([8.6 * math.cos(0.42), 8.6 * math.sin(0.42)]), axis=1)
        burnt = np.clip(1.4 - r / 1.9, 0, 1) * (0.6 + 0.5 * fbm(P, 1.2, 3, 66))
        c = mix(c, col((0.10, 0.09, 0.085), n), np.clip(burnt, 0, 1))
        return mix(c, col((0.36, 0.30, 0.22), n), 0.4 * np.clip((r - 2.0) / 1.2, 0, 1))   # свежий выброс грунта на валу

    def paint(b, P, N):
        c = weather(b, P, N, seed=12, stain=0.12, grime_h=1.6, grime=0.3, streak=0.15)
        chip = np.clip((fbm(P, 1.6, 4, 13) - 0.66) * 6, 0, 1)   # облупленная краска, ржавчина
        return mix(c, col(RUST, len(P)), 0.55 * chip)

    def floor_f(b, P, N):
        c = weather(b, P, N, seed=14, stain=0.2)
        return mix(c, col(EARTH, len(P)), 0.55 * np.clip((fbm(P, 0.35, 3, 15) - 0.45) * 3, 0, 1))   # нанесённый песок

    table = {'conc': concrete, 'gun': paint, 'floor': floor_f, 'scorch': scorch_f, 'earth': crater_f,
             'sand': f_burlap(16),
             'iron': lambda b, P, N: weather(b, P, N, seed=17, grime=0.2), 'brass': lambda b, P, N: weather(b, P, N, seed=18)}
    sh = by_mat(table)
    if broken:
        base_sh = sh

        def sh(base, P, N, M, names):
            c = base_sh(base, P, N, M, names)
            c = mix(c, col(RUST, len(P)), 0.35 * np.clip(1 - np.linalg.norm(P - np.array([0, 0, 2.0]), axis=1) / 4.5, 0, 1))   # окалина от огня
            return soot(c, P, [((0.3, 0.2, 2.2), 3.4), ((0.8, 0.9, 0.3), 3.2), ((4.6, 2.5, 0.8), 2.0), ((-3.0, -2.6, 0.6), 1.6), ((6.0, 2.9, 0.9), 2.4)], seed=19)
    name = 'a01_battery_gun' + ('_broken' if broken else '')
    return join_bake(o, sh, name, size=1024), name


def finish_ref(ob, out, ref, **kw):
    """Как finish(fit='xy'), но масштаб задан размером ref (м) = 1: разбитая версия того же масштаба, что целая."""
    mn, mx = L.bounds([ob])
    L.finish([ob], out, length=(mx.x - mn.x) / ref, fit='x', **kw)


GUN_REF = 13.95   # длина целого орудия по X (бруствер 13,6 м + дульный срез), м


def a01_battery_gun(scenery, src=None):
    ob, name = _gun_site(False)
    finish_ref(ob, scenery(name), GUN_REF, target=9000, maxtex=1024)


def a01_battery_gun_broken(scenery, src=None):
    ob, name = _gun_site(True)
    finish_ref(ob, scenery(name), GUN_REF, target=9000, maxtex=1024)


# ================= общие фактуры построек =================
def f_concrete(seed=0, grime_h=0.7):
    def f(b, P, N):
        c = weather(b, P, N, seed=seed, grime_h=grime_h, grime=0.4, streak=0.2, stain=0.18)
        lines = np.where((np.abs(N[:, 2]) < 0.5) & (np.mod(P[:, 2], 0.5) < 0.03), 0.9, 1.0)   # следы опалубки
        return c * lines[:, None]
    return f


def f_earth(seed=0):
    def f(b, P, N):
        n = len(P)
        c = weather(b, P, N, seed=seed, stain=0.25, grain=0.12, streak=0.0, grime=0.0)
        g = np.clip((fbm(P, 0.25, 4, seed + 1) - 0.42) * 3.0, 0, 1) * np.clip(N[:, 2], 0, 1)
        c = mix(c, col(DRYGRASS, n) * (0.85 + 0.3 * vnoise(P, 3.0, seed + 2))[:, None], 0.75 * g)
        # камешки — не белые крапины, а чуть темнее земли, с мягким краем
        st = np.clip((vnoise(P, 2.2, seed + 3) - 0.80) * 8, 0, 1)
        return mix(c, c * 0.78, st)
    return f


def f_plaster(seed=0):
    def f(b, P, N):
        c = weather(b, P, N, seed=seed, stain=0.12, grain=0.05, streak=0.16, grime_h=1.0, grime=0.4, dust=0.0)
        peel = np.clip((fbm(P, 0.9, 4, seed + 4) - 0.7) * 5, 0, 1) * (np.abs(N[:, 2]) < 0.5)   # облетевшая побелка: камень под ней
        return mix(c, col(LIME, len(P)) * 0.8, 0.6 * peel)
    return f


def f_tiles(seed=0):
    return lambda b, P, N: weather(tiles(b, P, N, seed), P, N, seed=seed + 1, stain=0.1, grain=0.04, streak=0.0, grime=0.0, dust=0.0)


def f_stone(seed=0, row=0.42, blen=0.75):
    return lambda b, P, N: weather(masonry(b, P, N, row=row, blen=blen, seed=seed), P, N, seed=seed + 1, stain=0.18, grime_h=0.8, grime=0.35)


def f_wood(seed=0, along='x', width=0.22):
    return lambda b, P, N: weather(planks(b, P, N, width=width, along=along, seed=seed), P, N, seed=seed + 1, stain=0.15, streak=0.08, grime_h=0.6, grime=0.3)


def f_paint(seed=0):
    def f(b, P, N):
        c = weather(b, P, N, seed=seed, stain=0.14, grime_h=1.2, grime=0.3)
        return mix(c, col(RUST, len(P)), 0.5 * np.clip((fbm(P, 1.4, 4, seed + 5) - 0.68) * 6, 0, 1))
    return f


def f_roof_flat(seed=0):
    """Плоская крыша: серая стяжка, заплаты битума, ржавые потёки, нанесённая пыль и грязь у парапета."""
    def f(b, P, N):
        n = len(P)
        c = weather(b, P, N, seed=seed, stain=0.25, grain=0.1, streak=0.0, grime=0.0, dust=0.0)
        tar = np.clip((fbm(P, 0.45, 4, seed + 1) - 0.60) * 6, 0, 1)
        c = mix(c, col((0.17, 0.16, 0.15), n), 0.85 * tar)
        dirt = np.clip((fbm(P, 0.8, 3, seed + 2) - 0.45) * 3, 0, 1)
        return mix(c, col(DIRT, n), 0.45 * dirt)
    return f


def f_plain(seed=0, **kw):
    return lambda b, P, N: weather(b, P, N, seed=seed, **kw)


# ================= Т-1 дот на берегу (25 м, кодом): чёткая бетонная форма вместо скана =================
def a02_bunker_coast(scenery, src=None):
    """Дот 25 м кодом. Каземат врыт в обваловку: земля с травой обнимает его с боков, сзади и сверху, наружу
    смотрит только бетонный лоб с козырьком. Амбразуры — настоящие проёмы (вырезаны) глубиной ~1 м с тёмной
    глубиной. Вход справа — по траншее со ступенями, стенки траншеи из мешков. Бетон — тёмный выветренный,
    камуфляжные пятна, потёки, грязь снизу."""
    L.reset()
    conc = L.flat('conc', CONC, 0.95); earth = L.flat('earth', EARTH, 1.0); trench = L.flat('trench', DIRT, 1.0)
    void = L.flat('void', (0.03, 0.03, 0.03), 1.0); iron = L.flat('iron', IRON, 0.9); sand = L.flat('sand', SAND_C, 1.0)
    o = []
    FRONT = -5.5                      # лицо каземата (к морю −Y)
    # каземат и плита крыши, козырёк над амбразурами, отмостка
    # под насыпью ничего не прячем: скрытые плиты в 0,7 м под землёй на дальности 2–4 км «пробивают» её (z-fighting)
    cas = L.box((0, FRONT + 1.5, 1.7), (14.0, 3.0, 3.4), conc, 'casemate')
    cutters = []
    EMB = ((0.0, 5.6), (-4.9, 1.6), (4.0, 1.6))
    for x, w in EMB:   # проём с откосами: снаружи шире, вглубь сужается
        cutters.append(L.hull([(x - w / 2 - 0.35, FRONT - 0.2, 1.55), (x + w / 2 + 0.35, FRONT - 0.2, 1.55),
                               (x - w / 2 - 0.35, FRONT - 0.2, 2.45), (x + w / 2 + 0.35, FRONT - 0.2, 2.45),
                               (x - w / 2, FRONT + 1.0, 1.7), (x + w / 2, FRONT + 1.0, 1.7),
                               (x - w / 2, FRONT + 1.0, 2.25), (x + w / 2, FRONT + 1.0, 2.25)], None, 'cutter'))
    cutters.append(L.box((6.0, FRONT + 0.5, 1.15), (1.3, 1.4, 2.3), None, 'cutter'))   # ниша входа
    cut(cas, cutters)
    o.append(cas)
    for x, w in EMB:   # тёмная глубина амбразуры (задняя стенка и ствол пулемёта в глубине)
        o.append(L.box((x, FRONT + 1.0, 1.98), (w + 0.1, 0.06, 0.7), void, 'embrasure_back'))
    o.append(L.box((6.0, FRONT + 1.18, 1.1), (1.1, 0.08, 2.1), iron, 'door'))
    o += [L.box((0, FRONT + 0.175, 3.7), (14.8, 1.15, 0.6), conc, 'roof'),   # видимая полоса плиты над лбом
          L.box((0, FRONT - 0.3, 2.78), (14.8, 1.3, 0.42), conc, 'visor'),
          L.box((0, FRONT - 0.9, 0.06), (15.0, 1.8, 0.12), conc, 'apron')]
    # обваловка: тело насыпи вокруг каземата; спереди уходит в землю по сторонам от лба
    rng = random.Random(23)
    # высоты по сетке: плато над плитой (+0,7 м земли), к краям — плавный откос до нуля за ~6 м, бугры;
    # спереди насыпь обрезана по лбу каземата (лоб открыт), у боков от лба сходит в ноль за 1,2 м
    top, fall = 4.7, 5.1
    xs = np.linspace(-12.6, 12.6, 39); ys = np.concatenate([np.linspace(-7.0, FRONT, 5)[:-1], [FRONT, FRONT + 0.7], np.linspace(FRONT + 1.4, 9.1, 22)])
    bm = bmesh.new(); grid = []
    for y in ys:
        row = []
        for x in xs:
            dx = max(0.0, abs(x) - 7.4); dy = max(0.0, y - 3.9, (FRONT + 0.7) - y if abs(x) > 7.4 else 0.0)
            d = math.hypot(dx, dy)
            t = min(1.0, d / fall); h = top * (1 - t * t * (3 - 2 * t)) + 0.35 * max(0.0, 1 - (x / 9.0) ** 2 - ((y + 0.5) / 7.0) ** 2)   # купол, не плато
            if y < FRONT + 0.7:
                h = 0.0 if abs(x) < 7.4 else h * max(0.0, 1 - (FRONT + 0.7 - y) / 1.9)
            nz = vnoise(np.array([[x, y, 0.0]]), 0.32, 24)[0] - 0.5
            h = max(0.0, h + nz * 0.45 * min(1.0, h / 1.2))
            row.append(bm.verts.new((x + rng.uniform(-0.12, 0.12), y + rng.uniform(-0.12, 0.12), h if h > 0.02 else -0.05)))
        grid.append(row)
    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            q = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
            if all(v.co.z < 0 for v in q):
                continue
            bm.faces.new(q)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    berm = L._new('berm', bm, earth)
    o.append(berm)
    # траншея ко входу: от ниши двери вправо вдоль лба, стенки из мешков, на выходе ступени
    tz = 0.03
    o.append(L.box((8.4, FRONT - 1.05, tz / 2), (7.6, 1.5, tz), trench, 'trench_floor'))
    items = bag_row((4.6, FRONT - 1.95), (11.0, FRONT - 1.95), 0.0, layers=3)       # бруствер траншеи со стороны моря
    items += bag_row((7.4, FRONT - 0.25), (11.0, FRONT - 0.25), 0.0, layers=2)      # подпорная стенка у подошвы насыпи
    o.append(bags(items, sand, 'sandbag', seed=7))
    for k in range(4):   # ступени выхода из траншеи на восток
        o.append(L.box((10.75 + k * 0.45, FRONT - 1.05, 0.08 + k * 0.09), (0.45, 1.4, 0.16 + k * 0.18), conc, 'step'))
    # на насыпи: наблюдательный колпак, перископ, вентиляция, антенна
    top = 5.0                          # верх обваловки (4,7 м + купол)
    o += [L.sphere((3.4, 0.6, top - 0.1), 1.0, iron, 'cupola', seg=16, scale=(1, 1, 0.62)),
          L.cyl((3.4, 0.6, top - 0.05), 1.1, 0.25, conc, 'cupola_ring', seg=20),
          L.box((3.4, -0.35, top + 0.2), (0.9, 0.12, 0.12), void, 'cupola_slit'),
          L.cyl((-2.5, 1.8, top + 0.3), 0.14, 1.2, iron, 'periscope', seg=8),
          L.cyl((-5.0, 2.2, top + 0.15), 0.25, 0.8, iron, 'vent', seg=10), L.cyl((-5.0, 2.2, top + 0.6), 0.36, 0.1, iron, 'vent_cap', seg=10),
          L.cyl((0.5, 3.0, top + 0.15), 0.25, 0.8, iron, 'vent', seg=10), L.cyl((0.5, 3.0, top + 0.6), 0.36, 0.1, iron, 'vent_cap', seg=10),
          L.cyl((-6.0, 2.6, top + 2.4), 0.06, 5.0, iron, 'antenna', seg=6), L.box((-6.0, 2.6, top), (0.6, 0.6, 0.35), conc, 'antenna_base')]
    # колья с проволокой перед дотом
    for k in range(7):
        x = -9.0 + k * 3.0
        o.append(L.box((x, -9.6 + (k % 2) * 0.4, 0.6), (0.08, 0.08, 1.2), WOOD_post(), 'post'))
    o.append(L.box((0, -9.4, 0.95), (18.4, 0.03, 0.03), iron, 'wire'))
    o.append(L.box((0, -9.4, 0.45), (18.4, 0.03, 0.03), iron, 'wire'))
    chamfer([b for b in o if b.name.startswith(('roof', 'visor', 'apron', 'antenna_base', 'step'))], 0.08)
    L.smooth([cas], 40)
    L.smooth([b for b in o if b.name.startswith(('cupola', 'vent', 'periscope'))], 40)
    L.smooth([berm], 75)

    emb_boxes = [(x - w / 2 - 0.4, x + w / 2 + 0.4) for x, w in EMB]

    def conc_f(b, P, N):
        n = len(P)
        c = f_concrete(20, grime_h=1.2)(b, P, N)
        # камуфляж: крупные пятна охры и оливы, края размыты, полустёртые
        m1 = np.clip((fbm(P, 0.16, 3, 25) - 0.52) * 7, 0, 1)
        m2 = np.clip((fbm(P, 0.16, 3, 26) - 0.55) * 7, 0, 1) * (1 - m1)
        wear = 0.55 + 0.35 * fbm(P, 1.2, 2, 27)
        c = mix(c, col((0.40, 0.36, 0.27), n), 0.75 * m1 * wear)
        c = mix(c, col((0.30, 0.31, 0.25), n), 0.75 * m2 * wear)
        # наметённый песок и земля на плите и козырьке, глубина амбразур и ниши темнее
        c = mix(c, col(EARTH, n), 0.5 * np.clip(N[:, 2], 0, 1) * np.clip((fbm(P, 0.4, 3, 28) - 0.4) * 3, 0, 1))
        inside = np.zeros(n, dtype=bool)
        for x0, x1 in emb_boxes:
            inside |= (P[:, 0] > x0) & (P[:, 0] < x1) & (P[:, 1] > FRONT - 0.05) & (P[:, 2] > 1.5) & (P[:, 2] < 2.5)
        inside |= (P[:, 0] > 5.3) & (P[:, 0] < 6.7) & (P[:, 1] > FRONT - 0.05) & (P[:, 2] < 2.35)
        depth = np.clip((P[:, 1] - FRONT + 0.05) / 1.0, 0, 1)
        c = np.where(inside[:, None], c * (0.55 - 0.4 * depth)[:, None], c)
        return c

    def berm_f(b, P, N):
        n = len(P)
        c = weather(b, P, N, seed=30, stain=0.25, grain=0.14, streak=0.0, grime=0.0, dust=0.0)
        grass = np.clip((fbm(P, 0.22, 4, 31) - 0.12) * 2.6, 0, 1) * np.clip(N[:, 2] * 1.3, 0, 1)
        tuft = 0.8 + 0.4 * vnoise(P, 3.5, 32)
        c = mix(c, col((0.31, 0.41, 0.18), n) * tuft[:, None], 0.95 * grass)        # трава Архипелага (как у земли рельефа; насыщенность с запасом на natural())
        c = mix(c, col((0.39, 0.45, 0.22), n) * tuft[:, None], 0.5 * grass * np.clip((fbm(P, 0.5, 3, 33) - 0.5) * 3, 0, 1))
        steep = np.clip((0.75 - N[:, 2]) * 3, 0, 1)                                    # осыпи на крутых местах — голая земля
        c = mix(c, col(DIRT, n) * (0.9 + 0.2 * vnoise(P, 2.0, 34))[:, None], 0.6 * steep)
        st = np.clip((vnoise(P, 2.4, 35) - 0.82) * 8, 0, 1)
        return mix(c, c * 0.75, st)

    sh = by_mat({'conc': conc_f, 'earth': berm_f, 'trench': f_earth(29), 'void': lambda b, P, N: b,
                 'iron': f_paint(25), 'sand': f_burlap(26), 'wood': f_wood(27)})
    ob = join_bake(o, sh, 'a02_bunker_coast', size=1024)
    L.finish([ob], scenery('a02_bunker_coast'), target=8000, maxtex=1024, fit='xy')


def WOOD_post():
    return L.flat('wood', WOOD_C, 1.0)


# ================= Т-5 тетрапод (4 м): серо-бежевый бетон, мокрый тёмный низ, водоросли у воды =================
def a07_tetrapod(scenery, src):
    L.reset()
    o = L.load(src('T-5_tetrapod.glb'))
    o = L.drop(o, names=('Line001_Standardmaterial_0',))
    L.place(o, length=4.0)
    L.smooth(o, 50)
    ob = L.join(o, 'a07_tetrapod')

    def sh(base, P, N, M, names):
        n = len(P)
        l = np.clip(lum_norm(base), 0.6, 1.4) ** 0.8
        c = col((0.47, 0.45, 0.41), n) * l[:, None]
        c = weather(c, P, N, seed=31, stain=0.22, grain=0.1, streak=0.12, grime=0.0)
        pits = vnoise(P, 6.0, 32) > 0.8                                   # раковины в бетоне
        c = np.where(pits[:, None], c * 0.75, c)
        z = P[:, 2]
        wet = np.clip((1.5 - z) / 0.5, 0, 1)                              # мокрый низ, граница размыта
        c = mix(c, c * 0.55, wet)
        alg = np.clip((1.1 - z) / 0.6, 0, 1) * np.clip((fbm(P, 1.3, 3, 33) - 0.35) * 2.5, 0, 1)
        c = mix(c, col((0.24, 0.27, 0.17), n), 0.7 * alg)                 # водоросли и налёт у воды
        salt = np.clip((z - 1.5) / 0.3, 0, 1) * np.clip(1 - (z - 1.8) / 0.4, 0, 1) * vnoise(P, 4, 34)
        return mix(c, col((0.60, 0.58, 0.53), n), 0.35 * salt)            # соляная кромка над водой
    bake(ob, sh, size=512, name='a07_tetrapod')
    L.finish([ob], scenery('a07_tetrapod'), target=1000, maxtex=512, fit='xy')


# ================= дома: общий конструктор (П-1, П-2, домик смотрителя маяка) =================
def house_parts(o, cx, cy, w, d, floors, roof, wall_rgb, seed, rz=0.0, shutters=(0.30, 0.40, 0.36), door_side='s', chimney=True,
                flat_extras=True):
    """Дом w×d, этажей floors, крыша 'flat' | 'gable' | 'hip'. Детали — с материалами по типу (стены, черепица, ставни...)."""
    rng = random.Random(seed)
    wall = L.flat('plaster_%d' % seed, wall_rgb, 0.95)
    trim = L.flat('plaster_trim', (0.60, 0.57, 0.50), 0.95)
    plinth = L.flat('stone_plinth', (0.47, 0.44, 0.38), 0.95)
    tile = L.flat('tile_%d' % (seed % 2), TILE_C if seed % 2 == 0 else TILE_C2, 0.9)
    glass = L.flat('glass', (0.05, 0.05, 0.06), 0.9)
    shut = L.flat('shutter_%d' % seed, shutters, 0.95)
    wood = L.flat('wood', WOOD_DARK, 1.0)
    fh = 3.0
    h = floors * fh
    parts = [L.box((cx, cy, h / 2), (w, d, h), wall, 'wall'),
             L.box((cx, cy, 0.3), (w + 0.12, d + 0.12, 0.6), plinth, 'plinth')]
    chamfer(parts, 0.04)
    # окна в нишах, рамы, ставни; дверь со ступенью
    for f in range(floors):
        z = f * fh + 1.75
        for side in 'snwe':
            along = w if side in 'sn' else d
            nwin = max(1, int(along / 3.2))
            for k in range(nwin):
                t = -along / 2 + along * (k + 0.5) / nwin
                is_door = f == 0 and side == door_side and k == nwin // 2
                if not is_door and rng.random() < 0.15:
                    continue
                ww, wh, wz = (1.1, 2.2, 1.1) if is_door else (0.85, 1.25, z)
                if side in 'sn':
                    y = cy + (d / 2 if side == 'n' else -d / 2); ny = 1 if side == 'n' else -1
                    x = cx + t
                    parts.append(L.box((x, y + ny * 0.005, wz), (ww, 0.06, wh), wood if is_door else glass, 'door' if is_door else 'win'))
                    parts.append(L.box((x, y + ny * 0.03, wz + wh / 2 + 0.06), (ww + 0.25, 0.1, 0.12), trim, 'lintel'))
                    if not is_door:
                        parts.append(L.box((x, y + ny * 0.06, wz - wh / 2 - 0.05), (ww + 0.2, 0.16, 0.08), trim, 'sill'))
                        if rng.random() < 0.75:
                            op = rng.random() < 0.5
                            for sg in (-1, 1):
                                if op:
                                    parts.append(L.box((x + sg * (ww / 2 + 0.24), y + ny * 0.05, wz), (0.44, 0.05, wh), shut, 'shutter'))
                                else:
                                    parts.append(L.box((x + sg * ww / 4, y + ny * 0.05, wz), (ww / 2 - 0.02, 0.05, wh), shut, 'shutter'))
                    else:
                        parts.append(L.box((x, y + ny * 0.35, 0.08), (1.6, 0.7, 0.16), plinth, 'step'))
                else:
                    x = cx + (w / 2 if side == 'e' else -w / 2); nx = 1 if side == 'e' else -1
                    y = cy + t
                    parts.append(L.box((x + nx * 0.005, y, wz), (0.06, ww, wh), wood if is_door else glass, 'door' if is_door else 'win'))
                    parts.append(L.box((x + nx * 0.03, y, wz + wh / 2 + 0.06), (0.1, ww + 0.25, 0.12), trim, 'lintel'))
                    if not is_door:
                        parts.append(L.box((x + nx * 0.06, y, wz - wh / 2 - 0.05), (0.16, ww + 0.2, 0.08), trim, 'sill'))
                        if rng.random() < 0.75:
                            op = rng.random() < 0.5
                            for sg in (-1, 1):
                                if op:
                                    parts.append(L.box((x + nx * 0.05, y + sg * (ww / 2 + 0.24), wz), (0.05, 0.44, wh), shut, 'shutter'))
                                else:
                                    parts.append(L.box((x + nx * 0.05, y + sg * ww / 4, wz), (0.05, ww / 2 - 0.02, wh), shut, 'shutter'))
    ov = 0.45
    if roof == 'flat':
        conc_r = L.flat('roofflat', (0.45, 0.42, 0.37), 0.95)
        # стены ниже на 0,3 м, крыша — толстая плита: нет двух близких параллельных граней (мерцание на дальности)
        parts[0].data.transform(Matrix.Translation((cx, cy, 0)) @ Matrix.Scale((h - 0.3) / h, 4, Vector((0, 0, 1))) @ Matrix.Translation((-cx, -cy, 0)))
        parts.append(L.box((cx, cy, h - 0.1), (w - 0.2, d - 0.2, 0.4), conc_r, 'roof'))
        for sx, sy, lx, ly in ((0, 1, w + 0.1, 0.25), (0, -1, w + 0.1, 0.25), (1, 0, 0.25, d + 0.1), (-1, 0, 0.25, d + 0.1)):
            parts.append(L.box((cx + sx * (w / 2 - 0.075), cy + sy * (d / 2 - 0.075), h + 0.25), (lx, ly, 1.1), wall, 'parapet'))
            parts.append(L.box((cx + sx * (w / 2 - 0.075), cy + sy * (d / 2 - 0.075), h + 0.84), (lx + 0.06, ly + 0.08, 0.08), trim, 'coping'))
        if flat_extras:
            sx_, sy_ = cx - w / 2 + 1.6, cy + d / 2 - 1.6
            hut = [L.box((sx_, sy_, h + 1.2), (2.4, 2.4, 2.4), wall, 'stair_hut'),
                   L.box((sx_, sy_, h + 2.46), (2.6, 2.6, 0.12), trim, 'stair_roof'),
                   L.box((sx_ + 1.205, sy_, h + 1.0), (0.06, 0.9, 2.0), wood, 'hut_door')]
            chamfer(hut[:2], 0.03)
            parts += hut
            parts += [L.cyl((cx + w / 2 - 1.2, cy + d / 2 - 1.2, h + 0.8), 0.55, 1.2, L.flat('iron_tank', (0.32, 0.32, 0.31), 0.9), 'tank', seg=14),
                      L.box((cx + w / 2 - 1.2, cy + d / 2 - 1.2, h + 0.15), (1.4, 1.4, 0.2), trim, 'tank_stand')]
            if rng.random() < 0.75:   # пергола с виноградом
                vine = L.flat('vine', (0.33, 0.40, 0.22), 1.0)
                px, py = cx + w / 4, cy - d / 4
                for ax in (-1, 1):
                    for ay in (-1, 1):
                        parts.append(L.box((px + ax * w / 5, py + ay * d / 5, h + 1.15), (0.14, 0.14, 2.3), wood, 'post'))
                for k in range(5):
                    parts.append(L.box((px - w / 5 + k * w / 10, py, h + 2.35), (0.1, d / 2.4, 0.1), wood, 'beam'))
                v = L.sphere((px, py, h + 2.5), 1.0, vine, 'vine', seg=10, scale=(w / 4.2, d / 4.6, 0.22))
                jag(v, 0.12, seed)
                parts.append(v)
    else:
        rh = min(w, d) * 0.3
        if roof == 'gable':
            along_x = w >= d
            a, b = (w, d) if along_x else (d, w)
            # фронтоны — стена, черепица — две плиты со свесом и коньком
            tri = [(-b / 2, h), (b / 2, h), (0, h + rh)]
            if along_x:
                parts.append(L.loft([[(cx - a / 2, cy + p, z) for p, z in tri], [(cx + a / 2, cy + p, z) for p, z in tri]], wall, 'gable'))
            else:
                parts.append(L.loft([[(cx + p, cy - a / 2, z) for p, z in tri], [(cx + p, cy + a / 2, z) for p, z in tri]], wall, 'gable'))
            k = rh / (b / 2)
            for sg in (-1, 1):
                e = b / 2 + ov
                q = [(-a / 2 - ov, sg * e, h - ov * k + 0.12), (a / 2 + ov, sg * e, h - ov * k + 0.12), (a / 2 + ov, 0, h + rh + 0.14), (-a / 2 - ov, 0, h + rh + 0.14)]
                if sg < 0:
                    q = [q[1], q[0], q[3], q[2]]
                if not along_x:
                    q = [(y, x, z) for x, y, z in q]
                    q = [q[1], q[0], q[3], q[2]]
                q = [(cx + x, cy + y, z) for x, y, z in q]
                parts.append(plate(q, 0.14, tile, 'roof'))
            r = (L.box((cx, cy, h + rh + 0.16), (a + 2 * ov, 0.3, 0.14), tile, 'ridge') if along_x else
                 L.box((cx, cy, h + rh + 0.16), (0.3, a + 2 * ov, 0.14), tile, 'ridge'))
            parts.append(r)
        else:   # вальмовая: тело кровли со свесом 0,12 м по кромке
            x0, x1, y0, y1 = cx - w / 2 - ov, cx + w / 2 + ov, cy - d / 2 - ov, cy + d / 2 + ov
            if w >= d:
                ridge = [(cx - w / 2 + d / 2, cy, h + rh), (cx + w / 2 - d / 2, cy, h + rh)]
            else:
                ridge = [(cx, cy - d / 2 + w / 2, h + rh), (cx, cy + d / 2 - w / 2, h + rh)]
            z0 = h - ov * rh / (min(w, d) / 2) + 0.05
            parts.append(L.hull([(x0, y0, z0), (x1, y0, z0), (x0, y1, z0), (x1, y1, z0),
                                 (x0, y0, z0 + 0.14), (x1, y0, z0 + 0.14), (x0, y1, z0 + 0.14), (x1, y1, z0 + 0.14)] + ridge, tile, 'roof'))
        parts.append(L.box((cx, cy, h - 0.12), (w + 0.1, d + 0.1, 0.24), trim, 'cornice'))
        if chimney:
            chx, chy = cx + w / 4, cy + d / 6
            parts += [L.box((chx, chy, h + rh * 0.75), (0.7, 0.7, rh * 1.5), wall, 'chimney'),
                      L.box((chx, chy, h + rh * 1.5 + 0.06), (0.9, 0.9, 0.12), trim, 'chimney_cap')]
    if rz:
        L.xform(parts, Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(rz, 4, 'Z') @ Matrix.Translation((-cx, -cy, 0)))
    o += parts
    return h


def town_shade(seed=0):
    return by_mat({'plaster': f_plaster(seed), 'tile': f_tiles(seed + 1), 'stone': f_stone(seed + 2, row=0.3, blen=0.5),
                   'shutter': f_wood(seed + 3, along='z', width=0.12), 'wood': f_wood(seed + 4), 'glass': f_plain(seed + 5, grime=0.0),
                   'roofflat': f_roof_flat(seed + 6), 'iron': f_paint(seed + 7),
                   'vine': f_plain(seed + 8, stain=0.3, grain=0.2, streak=0.0, grime=0.0), 'yard': f_earth(seed + 9),
                   'drystone': f_stone(seed + 10, row=0.32, blen=0.55), 'soil': f_earth(seed + 11), 'tree': f_plain(seed + 12, stain=0.3, grain=0.2, grime=0.0),
                   'conc': f_concrete(seed + 13)})


def yard_wall(o, a, b, hgt, seed=0, th=0.45):
    """Каменная ограда от a до b (сухая кладка, верх неровный)."""
    st = L.flat('drystone', LIME, 1.0)
    a, b = Vector(a), Vector(b); d = b - a; n = d.length; r = math.atan2(d.y, d.x)
    c = (a + b) / 2
    w = L.box((c.x, c.y, hgt / 2), (n, th, hgt), st, 'yard_wall', rz=r)
    o.append(w)


# ================= П-1, П-2 дома посёлка =================
def _house(scenery, name, w, d, floors, roof, seed, wing=None, extra=()):
    L.reset()
    o = []
    wall_rgb = PLASTER[seed % len(PLASTER)]
    shut = [(0.30, 0.40, 0.36), (0.42, 0.32, 0.24), (0.32, 0.40, 0.44), (0.46, 0.38, 0.26)][seed % 4]
    house_parts(o, 0, 0, w, d, floors, roof, wall_rgb, seed, shutters=shut)
    if wing:
        dx, dy, ww, wd, wf = wing
        house_parts(o, dx, dy, ww, wd, wf, 'flat' if roof == 'flat' else 'flat', wall_rgb, seed + 100, shutters=shut, door_side='e' if dx > 0 else 'w',
                    chimney=False, flat_extras=False)
    for e in extra:
        e(o, w, d, floors * 3.0, seed)
    ob = join_bake(o, town_shade(seed * 7), name, size=1024)
    L.finish([ob], scenery(name), target=4000, maxtex=1024, fit='xy')


def _balcony(o, w, d, h, seed):
    trim = L.flat('plaster_trim', (0.60, 0.57, 0.50), 0.95); iron = L.flat('iron', (0.20, 0.20, 0.20), 0.9)
    o.append(L.box((0, -d / 2 - 0.65, 3.0), (w * 0.5, 1.3, 0.15), trim, 'balcony'))
    o.append(L.box((0, -d / 2 - 1.28, 3.95), (w * 0.5, 0.05, 0.05), iron, 'rail'))
    for k in range(int(w * 0.5 / 0.25) + 1):
        o.append(L.box((-w * 0.25 + k * 0.25, -d / 2 - 1.28, 3.5), (0.03, 0.03, 0.9), iron, 'baluster'))
    for sg in (-1, 1):
        o.append(L.box((sg * w * 0.25, -d / 2 - 0.65, 3.5), (0.05, 1.3, 0.05), iron, 'rail'))


def _yard(o, w, d, h, seed):
    soil = L.flat('yard', EARTH, 1.0)
    o.append(L.box((w / 2 + 1.6, 0, 0.03), (3.2, d, 0.06), soil, 'yard'))
    yard_wall(o, (w / 2, d / 2 - 0.22), (w / 2 + 3.2, d / 2 - 0.22), 1.2, seed)
    yard_wall(o, (w / 2, -d / 2 + 0.22), (w / 2 + 3.2, -d / 2 + 0.22), 1.2, seed + 1)
    yard_wall(o, (w / 2 + 3.2, -d / 2), (w / 2 + 3.2, -0.6), 1.2, seed + 2)
    yard_wall(o, (w / 2 + 3.2, 0.6), (w / 2 + 3.2, d / 2), 1.2, seed + 3)
    tree = L.flat('tree', (0.36, 0.42, 0.25), 1.0)
    cr = L.sphere((w / 2 + 1.5, d / 4, 2.6), 1.4, tree, 'crown', seg=12, scale=(1, 1, 0.8)); jag(cr, 0.15, seed)
    o += [cr, L.cyl((w / 2 + 1.5, d / 4, 1.0), 0.14, 2.0, L.flat('wood', WOOD_DARK, 1.0), 'trunk', seg=8)]
    L.smooth([cr], 70)


HOUSES = {'a12_house_1': (8, 7, 1, 'flat', 1, None, ()), 'a13_house_2': (10, 8, 2, 'flat', 2, None, (_balcony,)),
          'a14_house_3': (9, 7, 2, 'flat', 3, (6.5, -1.0, 4.0, 5.0, 1), ()), 'a15_house_4': (8, 6, 1, 'gable', 4, None, (_yard,)),
          'a16_house_5': (11, 8, 2, 'hip', 5, None, (_balcony,)), 'a17_house_6': (9, 8, 2, 'gable', 6, (-6.5, 1.5, 4.0, 5.0, 1), ()),
          'a18_house_7': (12, 9, 3, 'hip', 7, None, ()), 'a19_house_8': (7, 7, 1, 'hip', 8, None, (_yard,))}


def _house_recipe(name):
    w, d, f, r, s, wing, extra = HOUSES[name]
    return lambda scenery, src=None: _house(scenery, name, w, d, f, r, s, wing, extra)


for _hn in HOUSES:
    globals()[_hn] = _house_recipe(_hn)


# ================= Т-3 маяк (25 м): цвет исходника, красный верх, домик смотрителя =================
def a04_lighthouse(scenery, src):
    L.reset()
    o = L.load(src('T-3_lighthouse.glb'))
    L.place(o, length=10)   # исходник в метрах: башня 25 м, основание 10 м
    o = L.drop(o, names=('Object_8',))   # ручка-«ворот» у подножия
    tower_top = max(L.bounds([ob])[1].z for ob in o if ob.name == 'Object_4')
    glass_top = L.bounds([ob for ob in o if ob.name == 'Object_15'])[1].z
    # перила исходника — 66 тыс. треугольников тонких прутьев: при упрощении рвутся, ставим свои (кольцо и стойки)
    rails = [ob for ob in o if ob.name in ('Object_11', 'Object_12')]
    rmn, rmx = L.bounds(rails)
    o = L.drop(o, names=('Object_11', 'Object_12'))
    L.budget(o, 6000)
    for ob in o:   # сетка исходника: гладко, острые рёбра — по углу
        L.smooth([ob], 45)
    iron = L.flat('railings_own', (0.2, 0.2, 0.2), 0.9)
    rr = (rmx.x - rmn.x) / 2 - 0.05
    zg = rmn.z
    o += [L.ring((0, 0, zg + 0.95), rr, rr - 0.06, 0.06, iron, 'rail', seg=40),
          L.ring((0, 0, zg + 0.5), rr, rr - 0.04, 0.04, iron, 'rail', seg=40)]
    for k in range(28):
        a = 2 * math.pi * k / 28
        o.append(L.box((rr * math.cos(a), rr * math.sin(a), zg + 0.5), (0.05, 0.05, 1.0), iron, 'rail_post'))
    red_m = L.flat('lh_red', (0.60, 0.20, 0.16), 0.9)
    o.append(L.cyl((0, 0, tower_top + 0.45), 1.75, 0.9, red_m, 'dome', seg=24, r2=0.35))
    o.append(L.sphere((0, 0, tower_top + 1.05), 0.28, red_m, 'vent_ball', seg=10))
    L.smooth([b for b in o if b.name in ('dome', 'vent_ball')], 60)
    # домик смотрителя и двор с оградой
    house_parts(o, 10.5, 0.0, 8.0, 6.0, 1, 'gable', (0.57, 0.50, 0.39), 41, shutters=(0.32, 0.40, 0.44), door_side='n')
    yard = L.flat('yard', (0.46, 0.41, 0.32), 1.0)
    o.append(L.box((8.0, 0, 0.04), (22.0, 14.0, 0.08), yard, 'yard'))
    for y in (6.8, -6.8):
        yard_wall(o, (-3.0, y), (19.0, y), 1.1, 41)
    yard_wall(o, (19.0, -6.8), (19.0, -1.2), 1.1, 42)
    yard_wall(o, (19.0, 1.2), (19.0, 6.8), 1.1, 43)
    stone_names = ('Concrete_material', 'Concrete_material.002')
    sh_town = town_shade(41)

    def sh(base, P, N, M, names):
        n = len(P)
        out = sh_town(base, P, N, M, names)
        for k, nm in enumerate(names):
            sel = M == k
            if not sel.any():
                continue
            b, p, nn = base[sel], P[sel], N[sel]
            if nm.startswith(stone_names):   # кладка исходника: свой серо-бежевый камень с потёками, красный верх фонаря
                # ствол — серо-охристая кладка из тёсаного камня (не побелка): камни разного тона, тёмные швы,
                # ржавые и сырые потёки сверху вниз, грязь и мох у основания
                l = np.clip(lum_norm(b), 0.7, 1.3) ** 0.6
                c = col((0.54, 0.49, 0.40), len(p)) * l[:, None]
                c = masonry(c, p, nn, row=0.55, blen=0.95, mortar=0.04, seed=44, var=0.22)
                c = mix(c, col((0.46, 0.44, 0.40), len(p)), 0.5 * np.clip((fbm(p, 0.3, 3, 49) - 0.45) * 3, 0, 1))   # серые выветренные участки
                c = weather(c, p, nn, seed=44, stain=0.16, streak=0.30, grime_h=3.0, grime=0.5)
                top = p[:, 2] > glass_top - 0.1
                c = np.where(top[:, None], weather(col((0.60, 0.20, 0.16), len(p)), p, nn, seed=45, streak=0.1, grime=0), c)
                out[sel] = c
            elif nm.startswith('railings'):
                out[sel] = weather(col((0.20, 0.19, 0.18), len(p)), p, nn, seed=46, grime=0)
            elif nm.startswith('glass'):
                out[sel] = col((0.22, 0.27, 0.28), len(p)) * (0.9 + 0.2 * vnoise(p, 2, 47))[:, None]
            elif nm.startswith(('LIGHT', 'red_light', 'handle', 'window_sill', 'door')):
                out[sel] = col((0.22, 0.20, 0.18), len(p))
            elif nm.startswith('lh_red'):
                out[sel] = weather(col((0.60, 0.20, 0.16), len(p)), p, nn, seed=48, streak=0.15, grime=0)
        return out
    ob = join_bake(o, sh, 'a04_lighthouse', size=1024)
    L.finish([ob], scenery('a04_lighthouse'), target=8000, maxtex=1024, fit='xy')


# ================= Т-8 руины крепости (20 м): три башни скана и стены кладкой с обломанным верхом =================
RUIN = (0.56, 0.52, 0.44)


def ruin_wall(a, b, h, th, mat, seed, broken_ends=(False, False), step=0.7):
    """Стена от a до b: сечения через ~step м, верх неровный (выкрошенная кладка), у обломанных концов — ступенями вниз."""
    rng = random.Random(seed)
    a, b = Vector(a), Vector(b); d = b - a; n = max(2, int(d.length / step))
    nrm = Vector((-d.y, d.x, 0)).normalized() * th / 2
    secs = []
    for i in range(n + 1):
        t = i / n
        p = a + d * t
        hh = h * (1 - 0.12 * rng.random())
        for end, k in ((broken_ends[0], t), (broken_ends[1], 1 - t)):
            if end and k < 0.3:
                hh *= 0.35 + 0.65 * (k / 0.3) ** 0.7 * (0.8 + 0.2 * rng.random())
        jog = (rng.random() - 0.5) * 0.12
        secs.append([(p.x - nrm.x, p.y - nrm.y, 0), (p.x - nrm.x * (1 + jog), p.y - nrm.y * (1 + jog), hh),
                     (p.x + nrm.x * (1 - jog), p.y + nrm.y * (1 - jog), hh * (0.92 + 0.08 * rng.random())), (p.x + nrm.x, p.y + nrm.y, 0)])
    return L.loft(secs, mat, 'wall')


def rubble(o, c, r, n, mat, seed, smax=0.9):
    rng = random.Random(seed)
    for k in range(n):
        a = rng.uniform(0, 2 * math.pi); rr = r * math.sqrt(rng.random()); s = rng.uniform(0.3, smax)
        p = (c[0] + rr * math.cos(a), c[1] + rr * math.sin(a), s * 0.25)
        b = L.box(p, (s, s * rng.uniform(0.6, 0.9), s * rng.uniform(0.4, 0.7)), mat, 'rubble', rz=rng.uniform(0, 3))
        subdiv(b, 1); jag(b, s * 0.1, seed + k)
        o.append(b)


def a11_tower_ruins(scenery, src):
    L.reset()
    o = L.load(src('T-8_towers_ruins.glb'))
    L.place(o, length=10)   # исходник: башни Ø10 в ряд
    L.budget(o, 7000)
    pos = {'Object_3': (-5.5, 6.0), 'Object_2': (6.5, 0.0), 'Object_4': (-5.5, -6.0)}
    for ob in o:   # башни треугольником, Ø6
        mn, mx = L.bounds([ob]); c = (mn + mx) / 2
        ob.data.transform(Matrix.Translation((pos[ob.name][0], pos[ob.name][1], 0)) @ Matrix.Scale(0.6, 4) @ Matrix.Translation((-c.x, -c.y, 0)))
    L.smooth(o, 40)
    st = L.flat('ruinwall', RUIN, 1.0)
    T = {k: Vector(v) for k, v in pos.items()}
    def edge(p, q, r=2.6):   # стена от края башни до края башни
        d = (q - p).normalized()
        return p + d * r, q - d * r
    a, b = edge(T['Object_3'], T['Object_2']); o.append(ruin_wall(a, b, 5.0, 1.4, st, 61))
    a, b = edge(T['Object_2'], T['Object_4'])
    m1, m2 = a + (b - a) * 0.42, a + (b - a) * 0.66
    o += [ruin_wall(a, m1, 3.6, 1.4, st, 62, (False, True)), ruin_wall(m2, b, 3.4, 1.4, st, 63, (True, False))]
    rubble(o, ((m1 + m2) / 2).to_tuple(), 2.2, 16, st, 64)
    a, b = edge(T['Object_4'], T['Object_3'])
    m1, m2 = a + (b - a) * 0.3, a + (b - a) * 0.5
    o += [ruin_wall(a, m1, 4.2, 1.4, st, 65, (False, True)), ruin_wall(m2, b, 4.4, 1.4, st, 66, (True, False))]
    rubble(o, ((m1 + m2) / 2).to_tuple(), 1.8, 12, st, 67)
    rubble(o, (0.5, 0.0, 0), 5.0, 10, st, 68, smax=0.6)   # камни во дворе
    L.smooth([b for b in o if b.name.startswith(('wall', 'rubble'))], 35)

    def sh(base, P, N, M, names):
        n = len(P)
        out = np.zeros((n, 3))
        for k, nm in enumerate(names):
            sel = M == k
            if not sel.any():
                continue
            p, nn = P[sel], N[sel]
            if nm.startswith('ruinwall'):
                c = masonry(col(RUIN, len(p)), p, nn, row=0.38, blen=0.62, seed=69, var=0.2)
            else:   # камень башен — фактура скана, приведённая к тону стен
                l = np.clip(lum_norm(base[sel]), 0.5, 1.6) ** 0.9
                c = col(RUIN, len(p)) * l[:, None]
            out[sel] = c
        out = weather(out, P, N, seed=70, stain=0.2, streak=0.18, grime_h=1.2, grime=0.45, dust=0.0)
        g = np.clip(N[:, 2] - 0.55, 0, 1) * 2.2 * np.clip((fbm(P, 0.6, 3, 71) - 0.4) * 3, 0, 1)   # сухая трава на гребнях и камнях
        return mix(out, col(DRYGRASS, n) * 0.85, 0.7 * g)
    ob = join_bake(o, sh, 'a11_tower_ruins', size=1024)
    L.finish([ob], scenery('a11_tower_ruins'), target=8000, maxtex=1024, fit='xy')


# ================= Т-4 причалы (кодом: у сканов настил рвался при упрощении) =================
def a05_pier_a(scenery, src=None):
    """Деревянный причал 40 × 7 м: настил на 1,5 м над водой, сваи, тумбы, кранцы, ящики и бухты каната на конце."""
    L.reset()
    rng = random.Random(5)
    deck = L.flat('wood_deck', WOOD_C, 1.0); beam = L.flat('wood_beam', WOOD_DARK, 1.0); iron = L.flat('iron', IRON, 0.9)
    crate = L.flat('wood_crate', (0.50, 0.42, 0.30), 1.0); rope = L.flat('rope', (0.55, 0.50, 0.38), 1.0)
    tyre = L.flat('tyre', (0.12, 0.12, 0.12), 1.0)
    o = [L.box((0, 0, 1.38), (40.0, 7.0, 0.24), deck, 'deck'),
         L.box((0, 3.3, 1.12), (40.0, 0.3, 0.3), beam, 'stringer'), L.box((0, -3.3, 1.12), (40.0, 0.3, 0.3), beam, 'stringer'),
         L.box((0, 0, 1.12), (40.0, 0.3, 0.3), beam, 'stringer'),
         L.box((0, 3.55, 1.45), (40.0, 0.2, 0.3), beam, 'curb'), L.box((0, -3.55, 1.45), (40.0, 0.2, 0.3), beam, 'curb')]
    for k in range(14):   # сваи с подкосами
        x = -19.5 + k * 3.0
        for y in (-3.3, 0.0, 3.3):
            o.append(L.cyl((x, y, -0.7), 0.17, 3.7, beam, 'pile', seg=10))
        o.append(L.box((x, 0, 1.0), (0.3, 7.0, 0.25), beam, 'cap'))
    for x in (-15.0, -5.0, 5.0, 15.0):
        for y in (-3.2, 3.2):
            o += [L.cyl((x, y, 1.75), 0.2, 0.5, iron, 'bollard', seg=12), L.cyl((x, y, 2.02), 0.26, 0.08, iron, 'bollard_cap', seg=12)]
    for x in (-12.0, -2.0, 8.0, 18.0):   # кранцы-покрышки на борту
        for y in (-3.72, 3.72):
            o.append(L.cyl((x, y, 0.9), 0.42, 0.22, tyre, 'tyre', seg=14, axis='Y'))
    o += [L.box((17.2, 1.4, 1.95), (1.4, 1.2, 0.9), crate, 'crate'), L.box((17.6, 0.2, 1.85), (1.0, 1.0, 0.7), crate, 'crate', rz=0.3),
          L.box((17.3, 1.3, 2.62), (0.9, 0.9, 0.45), crate, 'crate', rz=0.15),
          L.cyl((15.6, -2.0, 1.62), 0.55, 0.24, rope, 'rope', seg=14), L.cyl((-17.0, 2.2, 1.62), 0.5, 0.24, rope, 'rope', seg=14),
          L.cyl((-19.0, -3.0, 2.6), 0.08, 2.4, iron, 'lamp', seg=6), L.box((-19.0, -2.8, 3.8), (0.3, 0.5, 0.2), iron, 'lamp_head')]
    for k in range(5):   # лестница к воде
        o.append(L.box((10.0, -3.75, 1.2 - k * 0.35), (0.7, 0.06, 0.06), iron, 'ladder'))
    chamfer([b for b in o if b.name.startswith(('deck', 'stringer', 'curb', 'cap', 'crate'))], 0.03)
    L.smooth([b for b in o if b.name.startswith(('pile', 'bollard', 'tyre', 'rope'))], 50)

    def deck_f(b, P, N):
        c = weather(planks(b, P, N, width=0.24, along='y', seed=81), P, N, seed=82, stain=0.2, streak=0.05, grime=0.0, dust=0.0)
        return c

    def pile_f(b, P, N):
        c = weather(b, P, N, seed=83, stain=0.15, grime=0.0)
        z = P[:, 2]
        c = mix(c, c * 0.5, np.clip((0.6 - z) / 0.5, 0, 1))                                    # мокрые сваи
        return mix(c, col((0.26, 0.28, 0.18), len(P)), 0.6 * np.clip((0.4 - z) / 0.6, 0, 1))   # налёт у воды
    sh = by_mat({'wood_deck': deck_f, 'wood_beam': pile_f, 'iron': f_paint(84), 'wood_crate': f_wood(85, along='x', width=0.15),
                 'rope': f_plain(86, grime=0), 'tyre': f_plain(87, grime=0)})
    ob = join_bake(o, sh, 'a05_pier_a', size=1024)
    L.finish([ob], scenery('a05_pier_a'), target=5000, maxtex=1024, fit='xy')


def a06_pier_b(scenery, src=None):
    """Старый причал на сваях 39 × 3 м: настил с выпавшими досками, кривые сваи, покрышки по борту."""
    L.reset()
    rng = random.Random(6)
    deck = L.flat('wood_deck', (0.40, 0.34, 0.26), 1.0); beam = L.flat('wood_beam', (0.27, 0.23, 0.19), 1.0)
    tyre = L.flat('tyre', (0.12, 0.12, 0.12), 1.0)
    o = [L.box((0, 1.25, 0.95), (39.0, 0.22, 0.22), beam, 'stringer'), L.box((0, -1.25, 0.95), (39.0, 0.22, 0.22), beam, 'stringer')]
    x = -19.5
    while x < 19.4:   # доски поперёк, местами выпали или сдвинуты
        w = 0.24
        if rng.random() > 0.08:
            dz = rng.uniform(-0.02, 0.02); rz = rng.uniform(-0.04, 0.04)
            ln = 3.0 if rng.random() > 0.1 else rng.uniform(1.6, 2.4)
            o.append(L.box((x + w / 2, (3.0 - ln) / 2 * (1 if rng.random() < 0.5 else -1), 1.13 + dz), (w - 0.03, ln, 0.08), deck, 'plank', rz=rz))
        x += w
    for k in range(14):
        x = -19.2 + k * 3.0
        for y in (-1.25, 1.25):
            p = L.cyl((x, y, -0.8), 0.15, 3.8, beam, 'pile', seg=8)
            t = rng.uniform(-0.06, 0.06)
            p.data.transform(Matrix.Translation((x, y, 0.9)) @ Matrix.Rotation(t, 4, 'X') @ Matrix.Rotation(rng.uniform(-0.05, 0.05), 4, 'Y')
                             @ Matrix.Translation((-x, -y, -0.9)))
            o.append(p)
        if k % 2 == 0:
            for y in (-1.45, 1.45):
                o.append(L.cyl((x + 1.5, y, 0.55), 0.38, 0.2, tyre, 'tyre', seg=12, axis='Y'))
    L.smooth([b for b in o if b.name.startswith(('pile', 'tyre'))], 50)
    chamfer([b for b in o if b.name.startswith('stringer')], 0.02)

    def pile_f(b, P, N):
        c = weather(b, P, N, seed=91, stain=0.15, grime=0.0)
        z = P[:, 2]
        c = mix(c, c * 0.5, np.clip((0.5 - z) / 0.5, 0, 1))
        return mix(c, col((0.26, 0.28, 0.18), len(P)), 0.6 * np.clip((0.3 - z) / 0.6, 0, 1))
    sh = by_mat({'wood_deck': lambda b, P, N: weather(b * (0.85 + 0.3 * vnoise(P * np.array([0.2, 5, 1]), 1.0, 92))[:, None], P, N, seed=93, stain=0.25, grime=0, dust=0),
                 'wood_beam': pile_f, 'tyre': f_plain(94, grime=0)})
    ob = join_bake(o, sh, 'a06_pier_b', size=1024)
    L.finish([ob], scenery('a06_pier_b'), target=5000, maxtex=1024, fit='xy')


# ================= П-4 стена террасы, сухая кладка (10 м) =================
def a21_terrace_wall(scenery, src=None):
    L.reset()
    st = L.flat('drystone', LIME, 1.0); soil = L.flat('soil', EARTH, 1.0)
    rng = random.Random(21)
    secs = []
    n = 16
    for i in range(n + 1):   # стенка с наклоном внутрь, верх неровный
        x = -5.0 + 10.0 * i / n
        h = 1.55 + rng.uniform(-0.12, 0.08)
        secs.append([(x, -0.35, 0), (x, -0.2, h), (x, 0.35, h), (x, 0.35, 0)])
    o = [L.loft(secs, st, 'wall')]
    o.append(L.hull([(-5.0, 0.3, 0), (5.0, 0.3, 0), (-5.0, 0.3, 1.5), (5.0, 0.3, 1.5), (-5.0, 2.6, 0), (5.0, 2.6, 0), (-5.0, 2.6, 1.6), (5.0, 2.6, 1.6)], soil, 'fill'))
    for k in range(10):   # камни сверху и у подножия
        s = rng.uniform(0.25, 0.5)
        b = L.box((rng.uniform(-4.6, 4.6), rng.choice((-0.6, 0.05)), (1.6 if k % 2 else 0.12)), (s, s * 0.8, s * 0.6), st, 'stone', rz=rng.uniform(0, 3))
        subdiv(b, 1); jag(b, s * 0.1, k); o.append(b)
    L.smooth(o, 35)
    sh = by_mat({'drystone': lambda b, P, N: weather(masonry(b, P, N, row=0.3, blen=0.5, seed=95, var=0.22, mortar=0.05), P, N, seed=96, grime_h=0.5),
                 'soil': f_earth(97), 'stone': f_plain(98, stain=0.2)})
    ob = join_bake(o, sh, 'a21_terrace_wall', size=512)
    L.finish([ob], scenery('a21_terrace_wall'), target=1500, maxtex=512, fit='xy')


# ================= природа: листва и кора =================
def f_leaf(rgb, seed, zr=None, dry=(0.50, 0.50, 0.33)):
    """Листва: светлее сверху, темнее внизу и внутри кроны, комки и просветы, выгоревшие пятна — не «пластик»."""
    def f(b, P, N):
        n = len(P)
        c = col(rgb, n)
        up = np.clip(N[:, 2] * 0.5 + 0.5, 0, 1)
        k = 0.62 + 0.5 * up
        if zr:
            k = k * (0.7 + 0.35 * np.clip((P[:, 2] - zr[0]) / max(zr[1] - zr[0], 1e-3), 0, 1))
        k = k * (0.78 + 0.44 * vnoise(P, 4.5, seed)) * (0.85 + 0.3 * fbm(P, 1.0, 3, seed + 1))
        c = c * k[:, None]
        return mix(c, col(dry, n) * k[:, None], 0.35 * np.clip((fbm(P, 0.4, 3, seed + 2) - 0.5) * 3, 0, 1))
    return f


def f_bark(rgb, seed):
    def f(b, P, N):
        l = np.clip(lum_norm(b), 0.5, 1.6) if b.std() > 0.01 else 1.0 + 0.25 * (vnoise(P * np.array([4, 4, 0.6]), 3.0, seed) - 0.5)
        c = col(rgb, len(P)) * np.asarray(l).reshape(-1, 1)
        return weather(c, P, N, seed=seed + 1, stain=0.15, streak=0.0, grime_h=0.4, grime=0.3, dust=0.0)
    return f


def _tree(scenery, src, name, path, leaf_names, height, n, seed, crown_rgb, bark_rgb, trunk_target=900, flat=0.75):
    L.reset()
    o = L.load(src(path))
    L.place(o)
    mn, mx = L.bounds(o)
    L.xform(o, Matrix.Scale(height / (mx.z - mn.z), 4))
    leaves = [ob for ob in o if any(ob.data.materials and ob.data.materials[0].name.startswith(k) for k in leaf_names)]
    trunk = [ob for ob in o if ob not in leaves]
    for ob in trunk:
        for m in ob.data.materials:
            if m:
                m.name = 'bark_' + m.name
    L.budget(trunk, trunk_target)
    L.smooth(trunk, 60)
    cm = L.flat('crown', crown_rgb, 1.0)
    cr = L.crown(leaves, cm, n=n, seed=seed, flat=flat, seg=12)
    # к каждой «подушке» — 2 меньших комка по краю: крона рваная, со светом и тенью, а не набор шаров
    rng = random.Random(seed)
    extra = []
    for c in cr:
        cmn, cmx = L.bounds([c]); cc = (cmn + cmx) / 2; r = (cmx.x - cmn.x) / 2
        for k in range(2):
            a = rng.uniform(0, 2 * math.pi)
            e = L.sphere((cc.x + r * 0.7 * math.cos(a), cc.y + r * 0.7 * math.sin(a), cc.z + rng.uniform(-0.2, 0.3) * r), r * 0.5, cm, 'crown', seg=10,
                         scale=(1, 1, 0.75))
            jag(e, r * 0.08, seed + k)
            extra.append(e)
    cr += extra
    L.smooth(cr, 80)
    for ob in leaves:
        bpy.data.objects.remove(ob)
    zc = L.bounds(cr)
    sh = by_mat({'crown': f_leaf(crown_rgb, seed, (zc[0].z, zc[1].z)), 'bark': f_bark(bark_rgb, seed + 3)})
    ob = join_bake(trunk + cr, sh, name, size=512)
    L.finish([ob], scenery(name), target=trunk_target + n * 360, maxtex=512, fit='xy')


def a34_olive_a(scenery, src):
    _tree(scenery, src, 'a34_olive_a', 'N-2a_olive.glb', ('OliveSingleLeaf', 'OliveLeaf'), 7.0, 12, 34, (0.33, 0.38, 0.26), (0.46, 0.42, 0.36))


def a35_olive_b(scenery, src):
    _tree(scenery, src, 'a35_olive_b', 'N-2b_olive_old.glb', ('olive-leaves',), 6.0, 11, 35, (0.35, 0.39, 0.28), (0.44, 0.39, 0.33))


def a36_pine_a(scenery, src=None):
    """Пиния: голый наклонный ствол с развилкой, плоская широкая крона из рваных «подушек»."""
    rng = random.Random(36)
    L.reset()
    bark = L.flat('bark', (0.44, 0.34, 0.27), 1.0)
    green = L.flat('crown', (0.25, 0.33, 0.19), 1.0)
    o = [L.cyl((0.4, 0, 4.0), 0.36, 8.0, bark, 'trunk', seg=10, r2=0.24, rot=Matrix.Rotation(math.radians(6), 3, 'Y')),
         L.cyl((1.5, 0.4, 7.6), 0.15, 2.8, bark, 'branch', seg=8, r2=0.1, rot=Matrix.Rotation(math.radians(52), 3, 'Y')),
         L.cyl((-0.5, -0.6, 7.7), 0.14, 2.6, bark, 'branch', seg=8, r2=0.1, rot=Matrix.Rotation(math.radians(-48), 3, 'X')),
         L.cyl((0.6, 0.9, 7.8), 0.12, 2.2, bark, 'branch', seg=8, r2=0.08, rot=Matrix.Rotation(math.radians(45), 3, 'X'))]
    for k in range(11):
        a = k / 11 * 2 * math.pi * 1.7 + rng.random() * 0.4
        rr = 0 if k == 0 else 1.6 + rng.random() * 2.2
        s = 2.0 + rng.random() * 0.9
        sph = L.sphere((0.9 + rr * math.cos(a), rr * math.sin(a), 8.5 + rng.random() * 0.9), s, green, 'pad', seg=12, scale=(1.0, 1.0, 0.34))
        for v in sph.data.vertices:
            v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.6))) * 0.3
        o.append(sph)
    L.smooth(o, 70)
    sh = by_mat({'crown': f_leaf((0.25, 0.33, 0.19), 36, (8.0, 9.8), dry=(0.36, 0.38, 0.24)), 'bark': f_bark((0.46, 0.36, 0.28), 37)})
    ob = join_bake(o, sh, 'a36_pine_a', size=512)
    L.finish([ob], scenery('a36_pine_a'), target=3000, maxtex=512, fit='xy')


# ================= Н-1 скалы: тон известняка, без белизны; дубль-сетка у a33 убрана (дыры) =================
def _rock(scenery, src, name, path, length, rgb, target, keep=None, bow='+x', zscale=1.0):
    L.reset()
    o = L.load(src(path))
    if keep:
        o = L.drop(o, keep=keep)
    L.place(o, bow=bow, length=length)
    if zscale != 1.0:
        L.xform(o, Matrix.Scale(zscale, 4, Vector((0, 0, 1))))
    L.budget(o, int(target * 1.3))
    L.smooth(o, 50)
    ob = L.join(o, name)

    def sh(base, P, N, M, names):
        n = len(P)
        l = np.clip(lum_norm(base), 0.45, 1.7) ** 0.9
        c = col(rgb, n) * l[:, None]
        c = weather(c, P, N, seed=hash(name) % 1000, stain=0.2, streak=0.2, grime_h=1.5, grime=0.3, dust=0.0)
        g = np.clip(N[:, 2] - 0.6, 0, 1) * 2.5 * np.clip((fbm(P, 0.3, 3, 5) - 0.45) * 3, 0, 1)   # сухая трава на уступах
        return mix(c, col(DRYGRASS, n) * 0.8, 0.6 * g)
    bake(ob, sh, size=1024, name=name)
    L.finish([ob], scenery(name), target=target, maxtex=1024, fit='xy')


def a31_cliff_a(scenery, src):
    _rock(scenery, src, 'a31_cliff_a', 'N-1a_cliff.glb', 60, (0.54, 0.51, 0.45), 5000)


def a32_cliff_b(scenery, src):
    _rock(scenery, src, 'a32_cliff_b', 'N-1c_cliff_rock.glb', 30, (0.62, 0.59, 0.51), 5000, zscale=0.55)


def a33_rock(scenery, src):
    # скан N-1b — односторонняя «стенка» с дырами (снизу пусто): скала читалась тонкой плитой. Обычная скала —
    # из цельной груды N-1a (как обрыв a31), развёрнута на 90° и ниже: ею же заменена скала-столб a32
    _rock(scenery, src, 'a33_rock', 'N-1a_cliff.glb', 40, (0.56, 0.53, 0.46), 4000, bow='+y', zscale=0.8)


# ================= сканы и модели исходников: перекраска запеканием =================
def retone(base, rgb, k=0.85):
    """Цвет исходника → тон rgb: средний цвет детали становится rgb, светотень и пятна исходника сохраняются (степень k)."""
    med = np.median(base, axis=0) + 1e-3
    rel = np.clip(base / med, 0.3, 2.2) ** k
    return np.clip(rel * np.array(rgb), 0, 1)


def waterline(c, P, z_wet=0.3, z_alg=0.1):
    n = len(P)
    z = P[:, 2]
    c = mix(c, c * 0.55, np.clip((z_wet - z) / 0.3, 0, 1))
    return mix(c, col((0.24, 0.27, 0.17), n), 0.6 * np.clip((z_alg - z) / 0.4, 0, 1) * np.clip((fbm(P, 1.5, 3, 3) - 0.3) * 2, 0, 1))


def _scan(scenery, src, name, path, shade, target, place=None, drop=(), keep=None, pre=None, size=1024, smooth=45, budget=True):
    L.reset()
    o = L.load(src(path) if not path.startswith('/') else path)
    if drop or keep:
        o = L.drop(o, names=drop, keep=keep)
    L.place(o, **(place or {}))
    if pre:
        o = pre(o) or o
    if budget:
        L.budget(o, int(target * 1.2))
    L.smooth(o, smooth)
    ob = L.join(o, name)
    bake(ob, shade, size=size, name=name)
    L.finish([ob], scenery(name), target=target, maxtex=size, fit='xy')


def rusty_roof(c, base, P, N, seed=0):
    """Кровля складов (грани, смотрящие вверх): старое железо — тёмно-серое с бурой ржавчиной полосами по скату и пятнами,
    рисунок волны исходника сохраняется через его яркость."""
    n = len(P)
    roof = np.clip((N[:, 2] - 0.3) / 0.25, 0, 1)
    l = np.clip(lum_norm(base), 0.6, 1.4) ** 0.7
    iron = col((0.30, 0.29, 0.27), n) * l[:, None]
    r = np.clip((fbm(P * np.array([1.0, 1.0, 0.3]), 0.5, 4, seed) - 0.42) * 2.5, 0, 1)
    r = np.maximum(r, np.clip((vnoise(P * np.array([0.15, 1.0, 1.0]), 1.6, seed + 1) - 0.55) * 3, 0, 1) * 0.7)   # потёки вдоль ската
    roofc = mix(iron, col(RUST, n) * l[:, None], 0.8 * r)
    roofc = roofc * (1 + 0.12 * (fbm(P, 2.5, 2, seed + 2) - 0.5))[:, None]
    return mix(c, roofc, roof)


def a08_warehouse_a(scenery, src):
    """Ряд складов 30 м: кирпич → охристая штукатурка, крыша — выгоревший серый шифер; потёки, грязь снизу; бочки и ящики."""
    def pre(o):
        crate = L.flat('wood_crate', (0.50, 0.42, 0.30), 1.0); drum = L.flat('drum', (0.30, 0.36, 0.30), 1.0)
        mn, mx = L.bounds(o)
        add = [L.box((mx.x + 1.8, -2.0, 0.6), (2.4, 2.4, 1.2), crate, 'crates'), L.box((mx.x + 1.8, 1.2, 0.45), (2.0, 2.0, 0.9), crate, 'crates', rz=0.2)]
        for k in range(4):
            add.append(L.cyl((mx.x + 1.2 + (k % 2) * 1.0, mn.y + 1.0 + (k // 2) * 1.0, 0.45), 0.45, 0.9, drum, 'drum', seg=12))
        chamfer(add[:2], 0.03)
        return o + add

    def sh(base, P, N, M, names):
        n = len(P)
        out = base.copy()
        for k, nm in enumerate(names):
            sel = M == k
            if not sel.any():
                continue
            b, p, nn = base[sel], P[sel], N[sel]
            if nm.startswith('wood_crate'):
                out[sel] = f_wood(101, width=0.15)(b, p, nn)
            elif nm.startswith('drum'):
                out[sel] = f_paint(102)(b, p, nn)
            else:
                red = b[:, 0] > b[:, 2] * 1.3
                l = b @ np.array([0.3, 0.59, 0.11])
                lr = l / max(1e-3, float(np.median(l[red])) if red.any() else 0.5)
                lg = l / max(1e-3, float(np.median(l[~red])) if (~red).any() else 0.5)
                c = np.where(red[:, None], col((0.60, 0.49, 0.36), len(p)) * np.clip(lr, 0.6, 1.4)[:, None] ** 0.6,
                             col((0.44, 0.43, 0.40), len(p)) * np.clip(lg, 0.5, 1.6)[:, None] ** 0.8)
                c = weather(c, p, nn, seed=103, stain=0.15, streak=0.2, grime_h=1.0, grime=0.4)
                out[sel] = rusty_roof(c, b, p, nn, seed=104)
        return out
    _scan(scenery, src, 'a08_warehouse_a', 'T-6a_warehouses.glb', sh, 3500, place={'length': 30}, pre=pre)


def a09_warehouse_b(scenery, src):
    def sh(base, P, N, M, names):
        c = retone(base, (0.50, 0.47, 0.41), 0.9)
        c = weather(c, P, N, seed=111, stain=0.15, streak=0.22, grime_h=1.2, grime=0.4)
        return rusty_roof(c, base, P, N, seed=112)
    _scan(scenery, src, 'a09_warehouse_b', 'T-6b_warehouse.glb', sh, 3500, place={'length': 24}, drop=('Object_3',))


def a10_crane(scenery, src):
    """Портовый кран 30 м: без пятна земли и троса с крюком; стрела светло-серая, портал тёмно-синий, ржавчина, грязь."""
    cables = ('Crane_anim_8*', 'Crane_anim_9*', 'Decor*', 'Details_anim_3_*', 'Details_anim_6_*', 'Details_anim_7_*', 'Details_anim_9_*')

    def pre(o):
        L.xform(o, Matrix.Scale(0.75, 4, Vector((0, 0, 1))))   # ниже исходника на четверть, как раньше
        return o

    def sh(base, P, N, M, names):
        n = len(P)
        b = base
        yel = (b[:, 0] > 0.45) & (b[:, 1] > 0.35) & (b[:, 2] < b[:, 1] * 0.6)
        red = (b[:, 0] > 0.35) & (b[:, 1] < b[:, 0] * 0.5) & (b[:, 2] < b[:, 0] * 0.5)
        l = np.clip(lum_norm(b), 0.5, 1.6)
        c = np.where(yel[:, None], col((0.55, 0.55, 0.52), n) * l[:, None] ** 0.6,
                     np.where(red[:, None], col((0.27, 0.32, 0.38), n) * l[:, None] ** 0.6, retone(b, (0.42, 0.41, 0.39), 0.8)))
        c = weather(c, P, N, seed=121, stain=0.14, streak=0.2, grime_h=2.0, grime=0.35)
        return mix(c, col(RUST, n), 0.5 * np.clip((fbm(P, 0.9, 4, 122) - 0.66) * 5, 0, 1))
    _scan(scenery, src, 'a10_crane', 'T-7_port_crane.glb', sh, 6000, place={'length': 30}, drop=cables, pre=pre)


def a20_bell_tower(scenery, src):
    """Колокольня 15 м: светлый известняк исходника, потёки и грязь; шпиль (мог нести символ) заменён шаром."""
    def pre(o):
        mx = L.bounds(o)[1]
        o = L.kill_faces(o, lambda c, n: c.z > mx.z - 2.6 and Vector((c.x, c.y)).length < 0.3)
        m2 = L.bounds(o)[1]
        s = L.sphere((0, 0, m2.z + 0.15), 0.22, L.flat('finial', LIME, 1.0), 'finial', seg=12)
        return o + [s]

    def sh(base, P, N, M, names):
        c = col((0.56, 0.52, 0.44), len(P)) * (np.clip(lum_norm(base), 0.5, 1.4) ** 0.85)[:, None]   # тон — по яркости: исходник голубовато-серый
        fin = np.array([nm.startswith('finial') for nm in names])[M]
        c = np.where(fin[:, None], col((0.52, 0.48, 0.41), len(P)), c)
        return weather(c, P, N, seed=131, stain=0.16, streak=0.25, grime_h=1.5, grime=0.4)
    _scan(scenery, src, 'a20_bell_tower', 'P-3_bell_tower.glb', sh, 5000, place={'length': 4.3}, pre=pre)


def _hue_rules(b, rules):
    out = b.copy()
    l = b @ np.array([0.3, 0.59, 0.11])
    for cond, rgb in rules:
        m = cond(b[:, 0], b[:, 1], b[:, 2])
        if m.any():
            k = np.clip(l[m] / max(1e-3, float(np.median(l[m]))), 0.5, 1.4)
            out[m] = np.array(rgb) * k[:, None]
    return out


def a24_boat_a(scenery, src):
    """Рыбацкий катер 10 м: корпус выгоревший бирюзовый вместо красного, белое — в кремовый, ржавые потёки, мокрая ватерлиния."""
    def pre(o):
        L.xform(o, Matrix.Translation((0, 0, -0.9)))
        return L.kill_parts(o, lambda mn, mx, n: mx.z - mn.z > 2.0 and mx.x - mn.x < 0.25 and mx.y - mn.y < 0.25)   # удочки

    def sh(base, P, N, M, names):
        c = _hue_rules(base, [(lambda r, g, b: (r > g * 1.6) & (r > b * 1.6) & (r > 0.25), (0.22, 0.42, 0.42)),
                              (lambda r, g, b: (r > 0.75) & (g > 0.75) & (b > 0.75), (0.62, 0.60, 0.55))])
        c = weather(c, P, N, seed=141, stain=0.14, streak=0.25, grime=0.0, dust=0.0)
        return waterline(c, P, 0.35, 0.15)
    _scan(scenery, src, 'a24_boat_a', 'M-2a_fishing_boat.glb', sh, 4000, place={'bow': '+x', 'length': 10}, pre=pre)


def a25_boat_b(scenery, src):
    def pre(o):
        L.xform(o, Matrix.Translation((0, 0, -0.2)))
        wood = L.flat('mast', WOOD_C, 1.0)
        return o + [L.cyl((0.9, 0, 1.7), 0.06, 3.0, wood, 'mast', seg=8),
                    L.cyl((0.1, 0, 0.7), 0.12, 1.8, L.flat('sail', (0.62, 0.58, 0.49), 1.0), 'sail_furled', seg=8, axis='X')]

    def sh(base, P, N, M, names):
        c = retone(base, (0.48, 0.38, 0.28), 0.9)
        isn = np.array([nm.startswith(('mast', 'sail')) for nm in names])[M]
        c = np.where(isn[:, None], base, c)
        c = weather(c, P, N, seed=151, stain=0.18, streak=0.1, grime=0.0, dust=0.0)
        return waterline(c, P, 0.2, 0.05)
    _scan(scenery, src, 'a25_boat_b', 'M-2b_fishing_boat.glb', sh, 2500, place={'bow': '+y', 'length': 5.0}, pre=pre)


def a29_hedgehog(scenery, src):
    def sh(base, P, N, M, names):
        c = retone(base, (0.36, 0.25, 0.18), 0.8)
        return weather(c, P, N, seed=161, stain=0.25, grain=0.12, grime_h=0.5, grime=0.4)
    _scan(scenery, src, 'a29_hedgehog', 'M-5_hedgehog.glb', sh, 900, place={'length': 2.0}, size=512)


def a26_wreck_a(scenery, src):
    """Остов катера на мели 30 м: ржавый металл и тёмное дерево вместо белых пятен скана, мокрый низ с водорослями."""
    def pre(o):
        P = np.array([tuple(v.co) for ob in o for v in ob.data.vertices])
        A = np.c_[P[:, 0], P[:, 1], np.ones(len(P))]
        k = np.linalg.lstsq(A, P[:, 2], rcond=None)[0]
        o = L.kill_faces(o, lambda c, n: c.z - (k[0] * c.x + k[1] * c.y + k[2]) < 0.7)   # песчаное дно скана
        o = L.kill_parts(o, lambda mn, mx, n: n < 60)
        L.place(o)
        L.xform(o, Matrix.Translation((0, 0, -0.6)))
        return o

    def sh(base, P, N, M, names):
        n = len(P)
        l = np.clip(lum_norm(base), 0.4, 1.3) ** 0.8
        c = mix(col((0.40, 0.31, 0.24), n), col((0.30, 0.27, 0.24), n), fbm(P, 0.5, 3, 171)) * l[:, None]
        c = mix(c, col(RUST, n) * 1.1, 0.5 * np.clip((fbm(P, 1.2, 4, 172) - 0.5) * 3, 0, 1))
        c = weather(c, P, N, seed=173, stain=0.2, streak=0.25, grime=0.0, dust=0.0)
        return waterline(c, P, 0.6, 0.3)
    _scan(scenery, src, 'a26_wreck_a', 'M-3a_wreck_small.glb', sh, 7000, place={'length': 30}, pre=pre)


def a27_wreck_b(scenery, src):
    """Остов судна 80 м: выгоревшая краска с ржавыми потёками вместо надписей и полос, низ под водой."""
    def pre(o):
        L.xform(o, Matrix.Translation((0, 0, -2.5)))
        return o

    def sh(base, P, N, M, names):
        n = len(P)
        hsv_s = (base.max(1) - base.min(1)) / (base.max(1) + 1e-3)
        l = np.clip(lum_norm(base), 0.4, 1.3) ** 0.85
        c = col((0.48, 0.45, 0.40), n) * l[:, None]   # надписи, полосы и белые пятна скана — в одну выгоревшую краску   # надписи и полосы — в краску
        c = mix(c, col(RUST, n), 0.55 * np.clip((fbm(P * np.array([1, 1, 0.25]), 0.8, 4, 181) - 0.55) * 3, 0, 1))
        c = weather(c, P, N, seed=182, stain=0.2, streak=0.3, grime=0.0, dust=0.0)
        return waterline(c, P, 0.8, 0.4)
    _scan(scenery, src, 'a27_wreck_b', 'M-3b_wreck_ship.glb', sh, 9000, place={'bow': '+y', 'length': 80}, pre=pre)


def a39_reed(scenery, src=None):
    """Камыш: пучок стеблей с метёлками; цвет — выгоревшая зелень и солома, у корня темнее."""
    rng = random.Random(39)
    L.reset()
    m = L.flat('reed', (0.45, 0.46, 0.30), 1.0)
    o = []
    for k in range(26):
        a = rng.random() * 2 * math.pi; r = rng.random() * 0.9
        h = 1.4 + rng.random() * 0.9
        tilt = Matrix.Rotation(r * 0.35, 3, Vector((-math.sin(a), math.cos(a), 0)))
        base = Vector((r * math.cos(a), r * math.sin(a), 0))
        top = base + tilt @ Vector((0, 0, h))
        o.append(L.cyl(tuple((base + top) / 2), 0.03, h, m, 'stem', seg=5, rot=tilt))
        if rng.random() < 0.6:
            o.append(L.cyl(tuple(top), 0.05, 0.3, m, 'tuft', seg=5, rot=tilt, r2=0.02))

    def sh(base, P, N, M, names):
        n = len(P)
        z = np.clip(P[:, 2] / 2.2, 0, 1)
        c = mix(col((0.30, 0.34, 0.22), n), col((0.52, 0.48, 0.32), n), z)
        c = c * (0.8 + 0.4 * vnoise(P * np.array([6, 6, 0.5]), 1.0, 391))[:, None]
        return mix(c, col((0.40, 0.34, 0.24), n), 0.6 * np.clip((P[:, 2] - 1.9) / 0.4, 0, 1))   # метёлки
    ob = join_bake(o, sh, 'a39_reed', size=256)
    L.finish([ob], scenery('a39_reed'), target=1200, maxtex=256, fit='xy')


def a03_radar_mast(scenery, src=None):
    """РЛС на мачте: своя сборка из biome2_models без изменений формы, но окраска — оцинковка, штукатурка будки, бетон."""
    import biome2_models as B
    real = L.finish
    got = {}

    def grab(objs, out, **kw):   # перехватить детали до записи и запечь
        got['o'] = objs
    L.finish = grab
    try:
        B.a03_radar_mast()
    finally:
        L.finish = real
    o = got['o']
    for ob in o:
        for mt in ob.data.materials:
            if mt and mt.name.startswith('fh_hut'):
                mt.name = 'plaster_hut'
    sh = by_mat({'fh_steel': f_paint(301), 'fh_concrete': f_concrete(302), 'plaster': f_plaster(303), 'fh_radar': f_plain(304, grime=0.1),
                 'fh_red': f_plain(305, grime=0)})
    ob = join_bake(o, sh, 'a03_radar_mast', size=512)
    L.finish([ob], scenery('a03_radar_mast'), target=2500, maxtex=512, fit='xy')


# рецепты этого файла: имя → функция(scenery); biome2_models.py подменяет ими прежние
SHORE = ['a01_battery_gun', 'a01_battery_gun_broken', 'a02_bunker_coast', 'a04_lighthouse', 'a07_tetrapod', 'a11_tower_ruins', 'a05_pier_a', 'a06_pier_b', 'a21_terrace_wall',
         'a34_olive_a', 'a35_olive_b', 'a36_pine_a', 'a31_cliff_a', 'a32_cliff_b', 'a33_rock',
         'a08_warehouse_a', 'a09_warehouse_b', 'a10_crane', 'a20_bell_tower', 'a24_boat_a', 'a25_boat_b', 'a29_hedgehog', 'a26_wreck_a', 'a27_wreck_b',
         'a39_reed', 'a03_radar_mast'] + list(HOUSES)
