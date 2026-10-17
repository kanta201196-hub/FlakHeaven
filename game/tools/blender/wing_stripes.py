"""Т-8: окраска ведомых — полосы звена на крыльях и киле (план после разбора каталога, раздел 4).
Ведомые летают на тех же моделях, что игрок («Оса 1», «Грач 1»), поэтому полосы — отдельный маленький GLB
в осях модели ангара (как знаки, insignia.py): models/mech/fh_stripe_<класс>_<ур>.glb. Игра подвешивает его
только к ведомым и красит в цвет типа ведомого (WingMech.attach_wing_kit).
Узлы: stripe_wl / stripe_wr — две поперечные полосы на каждом крыле (по всей хорде), stripe_fin — полоса
поперёк киля (у двухкилевых — на каждом). Полоса — сетка точек, спроецированная лучами на обшивку
(сверху — крыло, сбоку — киль) и приподнятая по нормали.

Запуск (bpy 5.x): python3 wing_stripes.py <модель ангара.glb> <класс_ур> <out.glb>"""
import sys
import bpy, bmesh
import numpy as np
from mathutils import Vector

WING_F = (0.55, 0.66)   # доли полуразмаха — две полосы на крыле
BAND = 0.035            # ширина полосы
NX = 24                 # точек вдоль полосы
LIFT = 0.0012

src, key, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene
V = np.array([tuple(o.matrix_world @ v.co) for o in plane for v in o.data.vertices])
out = []


def ray(o, d):
    ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, Vector(o), Vector(d))
    return (loc, nrm) if ok else None


def strip(name, pts_of, origin_of, direction):
    """Полоса: pts_of(t, s) — точка-прицел для t (вдоль полосы, 0…1) и s (поперёк, 0 или 1);
    точки без попадания по обшивке отбрасываются целыми столбцами"""
    bm = bmesh.new()
    cols = []
    for i in range(NX + 1):
        t = i / NX
        col = []
        for s in (0.0, 1.0):
            h = ray(origin_of(pts_of(t, s)), direction)
            if h is None:
                col = None
                break
            n = h[1] if h[1].dot(direction) < 0 else -h[1]
            col.append(bm.verts.new(h[0] + n * LIFT))
        cols.append(col)
    faces = 0
    for a, b in zip(cols, cols[1:]):
        if a is None or b is None:
            continue
        f = bm.faces.new((a[0], b[0], b[1], a[1]))
        faces += 1
    for f in bm.faces:
        f.normal_update()
        if f.normal.dot(direction) > 0:
            f.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bpy.data.materials.new("stripe_" + name))
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    out.append(ob)
    print("STRIPE %s: %d quads" % (name, faces))
    return ob


# --- крылья: поперечные полосы на долях полуразмаха, по всей хорде (x от передней до задней кромки)
half = float(np.abs(V[:, 1]).max())
xmin, xmax = float(V[:, 0].min()), float(V[:, 0].max())
for side, sname in ((1, "l"), (-1, "r")):
    for k, f in enumerate(WING_F):
        y0 = side * half * f
        # хорда на этой линии: самый длинный непрерывный отрезок попаданий сверху
        xs = np.arange(xmax, xmin, -0.004)
        runs, cur = [], []
        for x in xs:
            h = ray((x, y0, 1.0), (0, 0, -1))
            if h is not None and h[1].z > 0.4:
                cur.append(x)
            elif cur:
                runs.append(cur)
                cur = []
        if cur:
            runs.append(cur)
        if not runs:
            continue
        run = max(runs, key=len)   # крыло, а не стабилизатор или подвесное на той же линии
        x0, x1 = run[0] + 0.004, run[-1] - 0.004
        strip("stripe_w%s%d" % (sname, k),
              lambda t, s, x0=x0, x1=x1, y0=y0: Vector((x0 + (x1 - x0) * t, y0 + side * (s - 0.5) * BAND, 0)),
              lambda p: (p.x, p.y, 1.0), Vector((0, 0, -1)))

# --- киль: полоса поперёк (по хорде) на 60% высоты; у двухкилевых — на каждом
top = V[V[:, 2].argmax()]
ztop = float(top[2])
yfin = abs(float(top[1]))
fins = [0.0] if yfin < 0.02 else [yfin, -yfin]
for fy in fins:
    zc = ztop * 0.62
    near = V[(np.abs(V[:, 1] - fy) < 0.03) & (np.abs(V[:, 2] - zc) < 0.01)]
    if len(near) == 0:
        continue
    fx0, fx1 = float(near[:, 0].max()) + 0.01, float(near[:, 0].min()) - 0.01
    for side, sname in ((1, "l"), (-1, "r")):
        if fy != 0 and side * fy < 0:   # у двухкилевых — только внешняя сторона (внутреннюю закрывает второй киль)
            continue
        strip("stripe_fin%s%s" % ("" if fy == 0 else ("p" if fy > 0 else "n"), sname),
              lambda t, s, fx0=fx0, fx1=fx1, zc=zc: Vector((fx0 + (fx1 - fx0) * t, 0, zc + (s - 0.5) * BAND * 0.8)),
              lambda p, side=side, fy=fy: (p.x, fy + side * 0.5, p.z), Vector((0, -side, 0)))

for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT")
print("STRIPES %s: %d" % (dst, len(out)))
