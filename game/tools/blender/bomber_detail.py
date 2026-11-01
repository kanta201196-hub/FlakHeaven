"""Т-2: силуэт «Кита 1/2» «по мотивам», без сходства с реальными машинами (каталог 1.3: 2–3 заметные детали).
Отдельный маленький GLB в осях модели ангара, как у «Грача 2» (attacker2_detail.py):
models/mech/fh_detail_bomber_<ур>.glb; игра подвешивает его к модели ангара и к боевой (WingMech.attach_detail).
«Кит 1» (винтовой): концевые шайбы-кили на законцовках стабилизатора (Н-образное оперение) и подвесные баки
на законцовках крыла со стабилизаторами.
«Кит 2» (реактивный): ПГО-«утки» перед кабиной и законцовки-винглеты (развал-кили на мотогондолах сняты 31.10:
на новой модели со своим килём они торчали серыми плитами над гондолами).
Цвет — один на деталь, средний по текстуре обшивки рядом (песочная окраска splinter_camo.py, извлечённый
*_0.png ангара); тёмные — обтекатели и кромки.

Запуск (bpy 5.x): python3 bomber_detail.py <модель ангара.glb> <текстура _0.png> <bomber_1|bomber_2> <out.glb>"""
import sys, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, geometry
from PIL import Image

src, tex, key, dst = sys.argv[-4], sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene
_PX = np.asarray(Image.open(tex).convert("RGBA"), np.float32)[::-1] / 255.0   # строки снизу вверх, как UV
_H, _W = _PX.shape[:2]
V = np.array([tuple(o.matrix_world @ v.co) for o in plane for v in o.data.vertices])
parts = []


def ray(o, d):
    """Точка обшивки, нормаль и цвет под ней (sRGB)"""
    ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, Vector(o), Vector(d))
    if not ok:
        return None
    me = ob.data
    poly = me.polygons[idx]
    uvl = me.uv_layers.active.data
    vs = [ob.matrix_world @ me.vertices[v].co for v in poly.vertices[:3]]
    uv = [Vector((*uvl[li].uv, 0)) for li in poly.loop_indices[:3]]
    b = geometry.barycentric_transform(loc, vs[0], vs[1], vs[2], uv[0], uv[1], uv[2])
    px = int((b.x % 1.0) * (_W - 1))
    py = int((b.y % 1.0) * (_H - 1))
    r = max(2, _W // 256)
    c = _PX[max(0, py - r):py + r + 1, max(0, px - r):px + r + 1, :3].reshape(-1, 3).mean(axis=0)
    return loc, nrm, tuple(c)


def skin(*pts):
    """Средний цвет обшивки по лучам сверху в точках (x, y)"""
    cs = [h[2] for h in (ray((x, y, 1), (0, 0, -1)) for x, y in pts) if h]
    return tuple(np.mean(cs, axis=0)) if cs else (0.6, 0.52, 0.37)


def lin(c):
    c = np.clip(np.array(c[:3], dtype=np.float64), 0, 1)
    return (*np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4), 1.0)


def mat(name, col, rough=0.6, metal=0.15):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


M_DARK = mat("detail_dark", (0.05, 0.05, 0.055, 1), 0.45, 0.5)


def mesh_obj(name, bm, col):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # вертикальные кили освещены слабее обшивки сверху — тон чуть светлее среднего под ними
    me.materials.append(mat("detail_" + name, lin(np.clip(np.array(col[:3]) * 1.1, 0, 1))))
    me.materials.append(M_DARK)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    parts.append(ob)
    return ob


def plate(bm, ring, normal, th, dark_edge=None):
    """Плоская пластина толщиной th по контуру ring (точки по кругу), смещение по normal.
    dark_edge — индекс ребра контура, которое красится тёмным (передняя кромка)"""
    n = Vector(normal).normalized() * th
    a = [bm.verts.new(p + n) for p in ring]
    b = [bm.verts.new(p - n) for p in ring]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    k = len(ring)
    for i in range(k):
        f = bm.faces.new([a[i], a[(i + 1) % k], b[(i + 1) % k], b[i]])
        if i == dark_edge:
            f.material_index = 1


def body(bm, prof, y, z, seg=20, dark_rings=2, axis_dir=1.0):
    """Тело вращения вдоль X: prof — [(x, r)], тёмный — первые dark_rings колец (обтекатель носа)"""
    rings = [[bm.verts.new((x, y + math.cos(2 * math.pi * k / seg) * r, z + math.sin(2 * math.pi * k / seg) * r))
              for k in range(seg)] for x, r in prof]
    for i in range(len(rings) - 1):
        for k in range(seg):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]))
            f.material_index = 1 if i < dark_rings else 0
    for rr, rev in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(rr[::-1] if rev else rr)
        f.material_index = 1 if rev else 0


def ogive(x0, x1, r, n=16, nose=0.22, tail=0.12, tail_r=0.35):
    out = []
    for i in range(n + 1):
        t = i / n
        if t < nose:
            rr = r * math.sin(t / nose * math.pi / 2) ** 0.7
        elif t > 1 - tail:
            rr = r * (tail_r + (1 - tail_r) * math.cos((t - 1 + tail) / tail * math.pi / 2))
        else:
            rr = r
        out.append((x0 + (x1 - x0) * t, max(rr, 0.0008)))
    return out


def tip_of(xmin=-1.0, xmax=1.0):
    """Законцовка: |y| максимум среди точек с x в диапазоне, хорда и высота там"""
    m = (V[:, 0] > xmin) & (V[:, 0] < xmax)
    ay = np.abs(V[m, 1])
    t = V[m][ay > ay.max() - 0.012]
    return float(ay.max()), float(t[:, 0].min()), float(t[:, 0].max()), float(t[:, 2].mean())


if key == "bomber_1":
    # --- концевые шайбы на стабилизаторе: трапеция со стреловидной передней кромкой, выше и ниже стабилизатора
    sy, sx0, sx1, sz = tip_of(xmax=-0.3)
    for side in (1, -1):
        y = side * (sy + 0.002)
        ring = [Vector((sx0 - 0.012, y, sz - 0.03)), Vector((sx1 + 0.02, y, sz - 0.022)),
                Vector((sx1 - 0.02, y, sz + 0.085)), Vector((sx0 + 0.005, y, sz + 0.09))]
        bm = bmesh.new()
        plate(bm, ring, (0, 1, 0), 0.0022, dark_edge=None)
        mesh_obj("endplate_" + ("l" if side > 0 else "r"), bm, skin((sx0 + 0.02, side * (sy - 0.03))))
    # --- баки на законцовках: веретено с тёмным носом и тремя стабилизаторами
    wy, wx0, wx1, wz = tip_of(xmin=-0.3, xmax=0.0)
    R = 0.016
    for side in (1, -1):
        y = side * (wy + R * 0.4)
        x0, x1 = wx1 + 0.045, wx0 - 0.045
        bm = bmesh.new()
        body(bm, ogive(x0, x1, R), y, wz)
        for ang in (90, 210, 330):   # «Y» — снизу два, сверху один
            d = Vector((0, math.cos(math.radians(ang)), math.sin(math.radians(ang))))
            base = Vector((x1 + 0.03, y, wz))
            ring = [base + Vector((0.012, 0, 0)) + d * R * 0.5, base - Vector((0.018, 0, 0)) + d * R * 0.5,
                    base - Vector((0.012, 0, 0)) + d * R * 1.9, base + Vector((0.0, 0, 0)) + d * R * 1.9]
            plate(bm, ring, d.cross(Vector((1, 0, 0))), 0.0012)
        mesh_obj("tip_tank_" + ("l" if side > 0 else "r"), bm, skin((wx0 + 0.02, side * (wy - 0.04)), ((wx0 + wx1) / 2, side * (wy - 0.02))))

elif key == "bomber_2":
    # --- развал-кили на мотогондолах: по лучам сверху — самая высокая точка гондолы на линии x
    xs = (-0.25, -0.15)
    # S14 (31.10): off. On the remeshed hangar model, which has its own central fin, the two canted fins read as
    # flat grey slabs standing over the nacelles (self-check sheet, Kanta: «убрать или исправить»).
    NACELLE_FINS = False
    for side in ((1, -1) if NACELLE_FINS else ()):
        best = None
        for y in np.arange(0.04, 0.16, 0.002):
            h = ray((xs[1], side * y, 1), (0, 0, -1))
            if h and (best is None or h[0].z > best[0].z):
                best = (h[0], y)
        gy = best[1]
        tops = [ray((x, side * gy, 1), (0, 0, -1))[0].z for x in xs]
        cant = math.radians(22)
        up = Vector((0, side * math.sin(cant), math.cos(cant)))
        H = 0.075
        ring = [Vector((xs[0] - 0.01, side * gy, tops[0] - 0.003)), Vector((xs[1] + 0.03, side * gy, tops[1] - 0.003))]
        ring += [ring[1] - Vector((0.075, 0, 0)) + up * H, ring[0] - Vector((0.02, 0, 0)) + up * H * 0.92]
        bm = bmesh.new()
        plate(bm, ring, up.cross(Vector((1, 0, 0))), 0.0024, dark_edge=None)
        mesh_obj("fin_" + ("l" if side > 0 else "r"), bm, skin((xs[0], side * (gy + 0.03)), (xs[1], side * (gy + 0.03))))
    # --- ПГО: дельта по бортам перед кабиной, на середине высоты борта
    CX = (0.29, 0.2)
    for side in (1, -1):
        pts = []
        for x in CX:
            top = ray((x, 0, 1), (0, 0, -1))[0].z
            bot = ray((x, 0, -1), (0, 0, 1))[0].z
            zc = top * 0.45 + bot * 0.55
            pts.append(ray((x, side * 1.0, zc), (0, -side, 0)))
        (lf, _, cf), (lr, _, cr) = pts
        root_f = lf - Vector((0, side * 0.004, 0))
        root_r = lr - Vector((0, side * 0.004, 0))
        tip = Vector((lr.x - 0.006, lr.y + side * 0.07, lr.z + 0.003))
        tip_f = Vector((tip.x + 0.014, tip.y, tip.z))
        bm = bmesh.new()
        plate(bm, [root_f, tip_f, tip, root_r], (0, 0, 1), 0.0022)
        mesh_obj("canard_" + ("l" if side > 0 else "r"), bm, tuple((np.array(cf) + np.array(cr)) * 0.5))
    # --- винглеты: от законцовки вверх с развалом наружу, стреловидные
    wy, wx0, wx1, wz = tip_of()
    for side in (1, -1):
        cant = math.radians(18)
        up = Vector((0, side * math.sin(cant), math.cos(cant)))
        y = side * (wy - 0.004)
        root0, root1 = Vector((wx0 + 0.004, y, wz)), Vector((wx1 - 0.004, y, wz))
        H = 0.055
        ring = [root0, root1, root1 - Vector((0.05, 0, 0)) + up * H, root0 - Vector((0.012, 0, 0)) + up * H]
        bm = bmesh.new()
        plate(bm, ring, up.cross(Vector((1, 0, 0))), 0.0018, dark_edge=1)
        mesh_obj("winglet_" + ("l" if side > 0 else "r"), bm, skin(((wx0 + wx1) / 2, side * (wy - 0.03))))

for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT")
print("DETAIL %s: %d parts" % (dst, len(parts)))
