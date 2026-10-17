"""V-07: свои знаки на крыльях и киле — «наклейки» по обшивке, отдельный маленький GLB в осях модели ангара
(как механизация крыла, wing_mech.py): models/mech/fh_ins_<класс>_<ур>.glb. Игра подвешивает его к модели
ангара и к боевой модели и ставит в каждую наклейку свою картинку (Insignia.attach, art/insignia/*.png).
Узлы: wing_l, wing_r — сверху на крыльях; fin_l, fin_r — на киле (у двухкилевых — на внешних сторонах);
side_l, side_r — на борту за кабиной (знак аса). Каждая наклейка — сетка точек, спроецированная лучами на
обшивку и приподнятая по нормали; UV 0…1 на весь знак, верх знака — к носу (крыло) или вверх (киль, борт).
Место ищется по самой модели: крыло — середина хорды на доле размаха WING_F; киль — центр плоской части
у самой высокой точки; борт — по таблице SIDE (x, доля высоты).

Запуск (bpy 5.x): python3 insignia.py <модель ангара.glb> <класс_ур> <out.glb>"""
import sys
import bpy, bmesh
import numpy as np
from mathutils import Vector

# доля полуразмаха под знак на крыле (у «Кита» дальше к концу — между мотогондолами и законцовкой)
WING_F = {"bomber_1": 0.74, "bomber_2": 0.66}
# знак аса на борту: x (длина 1, нос +X) и сдвиг по высоте от оси борта
SIDE = {"attacker_1": (0.16, 0.0), "attacker_2": (0.17, 0.0), "fighter_1": (0.14, 0.0),
        "fighter_2": (0.12, 0.0), "bomber_1": (0.3, 0.0), "bomber_2": (0.28, 0.0)}
N = 8             # сетка наклейки N×N
LIFT = 0.0008     # над обшивкой

src, key, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene
V = np.array([tuple(o.matrix_world @ v.co) for o in plane for v in o.data.vertices])


def ray(o, d):
    ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, Vector(o), Vector(d))
    return (loc, nrm) if ok else None


def sticker(name, centre, du, dv, size, origin_of, direction):
    """Наклейка; если край не попал на обшивку (стреловидная кромка, наклонный киль) — меньше"""
    for _ in range(8):
        ob = _sticker(name, centre, du, dv, size, origin_of, direction)
        if ob is not None:
            return ob
        size *= 0.88
    return None


def _sticker(name, centre, du, dv, size, origin_of, direction):
    """du, dv — направления «вправо» и «вверх» знака; origin_of(p) — откуда бросать луч к точке p"""
    bm = bmesh.new()
    uvk = bm.loops.layers.uv.new("UVMap")
    grid = []
    for j in range(N + 1):
        row = []
        for i in range(N + 1):
            u, v = i / N, j / N
            p = centre + du * ((u - 0.5) * size) + dv * ((v - 0.5) * size)
            h = ray(origin_of(p), direction)
            if h is None:
                bm.free()
                return None
            n = h[1] if h[1].dot(direction) < 0 else -h[1]
            row.append((bm.verts.new(h[0] + n * LIFT), (u, v)))
        grid.append(row)
    for j in range(N):
        for i in range(N):
            quad = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
            f = bm.faces.new([q[0] for q in quad])
            for lp, q in zip(f.loops, quad):
                lp[uvk].uv = q[1]
    # лицом к лучу (наружу)
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(direction) > 0:
            f.normal_flip()
    print("INS %s: size %.3f" % (name, size))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.new("insignia_" + name)
    m.use_nodes = True
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    return ob


out = []
# --- крыло: на доле размаха — середина самого длинного отрезка хорды под лучами сверху
half = float(np.abs(V[:, 1]).max())
for side, s in ((1, "l"), (-1, "r")):
    y = side * half * WING_F.get(key, 0.6)
    xs = np.arange(0.5, -0.5, -0.004)
    hit = [ray((x, y, 1.0), (0, 0, -1)) for x in xs]
    runs, cur = [], []
    for x, h in zip(xs, hit):
        if h is not None and h[1].z > 0.5:
            cur.append((x, h[0].z))
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    run = max(runs, key=len)
    x0, x1 = run[0][0], run[-1][0]
    chord = abs(x0 - x1)
    size = min(0.6 * chord, 0.14)
    c = Vector(((x0 + x1) * 0.5, y, 0.0))
    # «вправо» у знака сверху (нос вверх) — к правому борту (−Y)
    out.append(sticker("wing_" + s, c, Vector((0, -1, 0)), Vector((1, 0, 0)), size,
                       lambda p: (p.x, p.y, 1.0), Vector((0, 0, -1))))
    print("INS wing_%s: x %.3f y %.3f chord %.3f size %.3f" % (s, c.x, y, chord, size))

# --- киль: точки обшивки около плоскости киля (|y − y_fin| мало, нормаль вбок), центр и размер плоской части
top = V[V[:, 2].argmax()]
yfin = abs(float(top[1]))
ztop = float(top[2])
for side, s in ((1, "l"), (-1, "r")):
    pts = []
    for x in np.arange(top[0] - 0.12, top[0] + 0.2, 0.004):
        for z in np.arange(ztop * 0.25, ztop, 0.003):
            h = ray((x, side * 2.0, z), (0, -side, 0))
            if h and abs(abs(h[0].y) - yfin) < 0.03 and abs(h[1].y) > 0.6:
                pts.append((x, z))
    pts = np.array(pts)
    # нижнюю часть (стык с фюзеляжем) отрезаем: берём верхние 80% по высоте
    zlo = np.quantile(pts[:, 1], 0.2)
    pts = pts[pts[:, 1] > zlo]
    cx, cz = pts.mean(0)
    # размер — по ширине киля на высоте центра и по высоте плоской части
    row = pts[np.abs(pts[:, 1] - cz) < 0.004]
    width = row[:, 0].max() - row[:, 0].min()
    height = pts[:, 1].max() - pts[:, 1].min()
    size = min(0.6 * width, 0.6 * height, 0.09)
    c = Vector((cx, side * yfin, cz))
    out.append(sticker("fin_" + s, c, Vector((-side, 0, 0)), Vector((0, 0, 1)), size,
                       lambda p, side=side: (p.x, side * 2.0, p.z), Vector((0, -side, 0))))
    print("INS fin_%s: x %.3f z %.3f width %.3f height %.3f size %.3f" % (s, cx, cz, width, height, size))

# --- борт за кабиной: знак аса
sx, sdz = SIDE[key]
lo = ray((sx, 0, -1.0), (0, 0, 1))[0].z
hi = ray((sx, 0, 1.0), (0, 0, -1))[0].z
for side, s in ((1, "l"), (-1, "r")):
    zc = (lo + hi) * 0.5 + sdz
    size = min(0.55 * (hi - lo), 0.06)
    c = Vector((sx, 0, zc))
    out.append(sticker("side_" + s, c, Vector((-side, 0, 0)), Vector((0, 0, 1)), size,
                       lambda p, side=side: (p.x, side * 2.0, p.z), Vector((0, -side, 0))))
    print("INS side_%s: x %.3f z %.3f size %.3f" % (s, sx, zc, size))

for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT")
print("INS %s: %d stickers" % (dst, len([o for o in out if o])))
