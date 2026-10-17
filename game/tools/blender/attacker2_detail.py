"""Т-2: отличие «Грача 2» от «Грача 1», видное сверху (каталог: законцовки, нос или бронеплиты).
Отдельный маленький GLB в осях модели ангара, как механизация крыла: models/mech/fh_detail_attacker_2.glb.
Две детали: переднее горизонтальное оперение (ПГО) — треугольные плоскости по бортам перед кабиной,
и крупные контейнеры на законцовках крыла (вместо тонких) с тёмными обтекателями и стабилизаторами.
Цвет — один на деталь, средний по текстуре обшивки под ней (UV Meshy рваные, как в tail_cabin.py); пишется
в цвет материала (линейный), без вершинных цветов.

Цвет берётся с извлечённой текстуры ангара (*_0.png — уже с чистым камуфляжем clean_camo.py), а не со встроенной.

Запуск (bpy 5.x): python3 attacker2_detail.py <модель ангара.glb> <текстура _0.png> <out.glb>"""
import sys, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, geometry

CANARD_X = (0.3, 0.205)       # корень ПГО: передняя и задняя кромка по длине
CANARD_SPAN = 0.075           # вылет от борта
POD_R = 0.017                 # контейнер на законцовке
POD_X = (-0.07, -0.33)        # нос и хвост контейнера
DARK = 1.0

src, tex, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene
from PIL import Image
_PX = np.asarray(Image.open(tex).convert("RGBA"), np.float32)[::-1] / 255.0   # строки снизу вверх, как UV
_H, _W = _PX.shape[:2]
V = np.array([tuple(o.matrix_world @ v.co) for o in plane for v in o.data.vertices])


def ray(o, d):
    """Точка обшивки и её цвет; детали без UV пропускаются"""
    o = Vector(o)
    d = Vector(d)
    for _ in range(6):
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, o, d)
        if not ok:
            return None
        if ob.data.uv_layers.active is not None:
            break
        o = loc + d * 1e-4
    else:
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
    return loc, (*(c * DARK), 1.0)


def mat(name, col=None, rough=0.5, metal=0.3):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    if col is None:
        vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        m.node_tree.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


M_DARK = mat("detail_dark", (0.05, 0.05, 0.055, 1), 0.45, 0.5)
parts = []


def lin(c):
    c = np.clip(np.array(c[:3], dtype=np.float64), 0, 1)
    return (*np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4), 1.0)


def mesh_obj(name, bm, m):
    if isinstance(m, tuple):     # цвет sRGB → свой материал
        m = mat("detail_" + name, lin(m), 0.7, 0.1)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    me.materials.append(M_DARK)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    parts.append(ob)
    return ob


# --- ПГО: корень — на борту фюзеляжа на высоте середины борта, плоскость с лёгкой стреловидностью
for side in (1, -1):
    xs = CANARD_X
    pts = []
    for x in xs:
        top = ray((x, 0, 1), (0, 0, -1))[0].z
        bot = ray((x, 0, -1), (0, 0, 1))[0].z
        zc = top * 0.4 + bot * 0.6
        h = ray((x, side * 1.0, zc), (0, -side, 0))
        pts.append(h)
    (lf, cf), (lr, cr) = pts
    root_f = lf - Vector((0, side * 0.004, 0))   # корень чуть внутри борта — без щели
    root_r = lr - Vector((0, side * 0.004, 0))
    tip_r = Vector((lr.x - 0.012, lr.y + side * CANARD_SPAN, lr.z + 0.004))
    tip_f = Vector((tip_r.x + 0.022, tip_r.y, tip_r.z))
    th = 0.0025
    bm = bmesh.new()
    ring = [root_f, tip_f, tip_r, root_r]
    top_v = [bm.verts.new(p + Vector((0, 0, th))) for p in ring]
    bot_v = [bm.verts.new(p - Vector((0, 0, th))) for p in ring]
    col = tuple((np.array(cf) + np.array(cr)) * 0.5)
    faces = [top_v, bot_v[::-1]] + [[top_v[i], top_v[(i + 1) % 4], bot_v[(i + 1) % 4], bot_v[i]] for i in range(4)]
    for fv in faces:
        bm.faces.new(fv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_obj("canard_" + ("l" if side > 0 else "r"), bm, col)

# --- контейнеры на законцовках: цилиндр с оживальным носом, тёмный обтекатель и два стабилизатора
tip = V[np.abs(V[:, 1]) > np.abs(V[:, 1]).max() - 0.02]
tip_y = float(np.abs(tip[:, 1]).max())
tip_z = float(tip[:, 2].mean())
for side in (1, -1):
    y = side * (tip_y + POD_R * 0.6)
    skin = ray((POD_X[0] - 0.08, y, 1), (0, 0, -1)) or ray((-0.17, side * (tip_y - 0.03), 1), (0, 0, -1))
    col = skin[1] if skin else (0.3, 0.32, 0.26, 1)
    SEG = 20
    prof = []    # (x, r)
    n = 14
    x0, x1 = POD_X
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        if t < 0.25:
            r = POD_R * math.sin(t / 0.25 * math.pi / 2) ** 0.7
        elif t > 0.9:
            r = POD_R * (0.55 + 0.45 * (1 - (t - 0.9) / 0.1))
        else:
            r = POD_R
        prof.append((x, max(r, 0.0008)))
    bm = bmesh.new()
    rings = []
    for x, r in prof:
        rings.append([bm.verts.new((x, y + math.cos(2 * math.pi * k / SEG) * r, tip_z + math.sin(2 * math.pi * k / SEG) * r))
                      for k in range(SEG)])
    for i in range(n):
        dark = i < 2       # тёмный обтекатель носа
        for k in range(SEG):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % SEG], rings[i + 1][(k + 1) % SEG], rings[i + 1][k]))
            f.material_index = 1 if dark else 0
    for rr, rev in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(rr[::-1] if rev else rr)
        f.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # стабилизаторы в хвосте контейнера: вверх и вниз
    for dz in (1, -1):
        p0 = Vector((x1 + 0.045, y, tip_z + dz * POD_R * 0.6))
        p1 = Vector((x1 + 0.005, y, tip_z + dz * POD_R * 0.6))
        p2 = Vector((x1 + 0.012, y, tip_z + dz * POD_R * 2.1))
        p3 = Vector((x1 + 0.03, y, tip_z + dz * POD_R * 2.1))
        th = Vector((0, 0.0012, 0))
        a = [bm.verts.new(p + th) for p in (p0, p1, p2, p3)]
        b = [bm.verts.new(p - th) for p in (p0, p1, p2, p3)]
        for fv in [a, b[::-1]] + [[a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]] for i in range(4)]:
            bm.faces.new(fv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_obj("tip_pod_" + ("l" if side > 0 else "r"), bm, tuple(col))

for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT")
print("DETAIL %s: %d parts, tip y %.3f z %.3f" % (dst, len(parts), tip_y, tip_z))
