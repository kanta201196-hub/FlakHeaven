"""Т-5: створки бомбоотсека «Кита» — отдельный маленький GLB в осях модели ангара (как механизация крыла,
wing_mech.py): models/mech/fh_bay_<класс>_<ур>.glb. Игра подвешивает его к модели ангара и к боевой модели
и открывает створки при сбросе бомб (WingMech.bay).
Узлы: bay_l, bay_r — створки по бокам оси, петля по внешней кромке; точка узла — середина петли,
локальная X — вперёд вдоль петли. Открытие: bay_l — поворот вокруг X на +угол, bay_r — на −угол
(внутренняя кромка уходит вниз). bay_well — тёмная ниша над створками: видна, когда они открыты.
Цвет створок — вершинный, снят с текстуры брюха под ними (UV Meshy рваные, как в wing_mech.py).

Запуск (bpy 5.x): python3 bay_doors.py <модель ангара.glb> <класс_ур> <out.glb>
  например: python3 bay_doors.py ../../models/hangar/fh_hangar_bomber_1.glb bomber_1 ../../models/mech/fh_bay_bomber_1.glb"""
import sys
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix, geometry

# отсек по длине (x, модель длиной 1) и полуширина: под точками бомбоотсека PlaneArt.slot_points
# (wing_x ± 0.09 длины) плюс половина длины бомбы
BAYS = {
    "bomber_1": (-0.2, 0.15, 0.028),
    "bomber_2": (-0.33, 0.0, 0.03),
}
DROP = 0.0018     # створка ниже обшивки, чтобы не утонула
THICK = 0.0015
NX, NY = 14, 4
DARK = 0.86

src, key, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
X0, X1, W = BAYS[key]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene

_img = next(n.image for n in plane[0].data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image
            and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links))
_W, _H = _img.size
_PX = np.array(_img.pixels[:], dtype=np.float32).reshape(_H, _W, 4)


def belly(x, y):
    """Нижняя обшивка под (x, y): точка и цвет текстуры; None — промах"""
    o = Vector((x, y, -1.0))
    for _ in range(6):   # детали без UV (винты, антенны) пропускаем — ищем обшивку выше
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, o, Vector((0, 0, 1)))
        if not ok:
            return None
        if ob.data.uv_layers.active is not None:
            break
        o = loc + Vector((0, 0, 1e-4))
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


def material(name, col=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    if col is None:
        vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        m.node_tree.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = col
    return m


mat_skin = material("mech_skin")
mat_well = material("bay_well", (0.03, 0.03, 0.035, 1))


def grid(side):
    """Сетка точек брюха: строки по x, столбцы по y от оси (0) к кромке (W) с нужной стороны"""
    rows = []
    for i in range(NX + 1):
        x = X0 + (X1 - X0) * i / NX
        row = []
        for j in range(NY + 1):
            h = belly(x, side * W * j / NY)
            if h is None:
                break
            row.append(h)
        if len(row) == NY + 1:
            rows.append(row)
    return rows


def sheet(name, rows, dz, thick, mat, seam_edge=None):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    colk = bm.loops.layers.color.new("Col")
    top = [[bm.verts.new(p + Vector((0, 0, dz))) for p, c in row] for row in rows]
    cols = [[c for p, c in row] for row in rows]
    bot = [[bm.verts.new(v.co - Vector((0, 0, thick))) for v in row] for row in top] if thick > 0 else None
    for i in range(len(rows) - 1):
        for j in range(len(rows[0]) - 1):
            quads = [((top[i][j], top[i][j + 1], top[i + 1][j + 1], top[i + 1][j]),
                      (cols[i][j], cols[i][j + 1], cols[i + 1][j + 1], cols[i + 1][j]))]
            if bot:
                quads.append(((bot[i][j], bot[i + 1][j], bot[i + 1][j + 1], bot[i][j + 1]),
                              (cols[i][j], cols[i + 1][j], cols[i + 1][j + 1], cols[i][j + 1])))
            for vs, cs in quads:
                f = bm.faces.new(vs)
                for lp, c in zip(f.loops, cs):
                    lp[colk] = c
    if bot:   # торцы по контуру
        n, m = len(rows), len(rows[0])
        ring = [(0, j) for j in range(m)] + [(i, m - 1) for i in range(1, n)] + \
               [(n - 1, j) for j in range(m - 2, -1, -1)] + [(i, 0) for i in range(n - 2, 0, -1)]
        for k in range(len(ring)):
            (a, b), (c, d) = ring[k], ring[(k + 1) % len(ring)]
            f = bm.faces.new((top[a][b], top[c][d], bot[c][d], bot[a][b]))
            for lp in f.loops:
                lp[colk] = cols[a][b]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    return ob


out = []
for side, s in ((1, "l"), (-1, "r")):
    rows = grid(side)
    if len(rows) < 2:
        raise SystemExit("bay %s: брюхо не найдено" % s)
    # ниша — по обшивке, створка — чуть ниже
    out.append(sheet("bay_well_" + s, rows, 0.0004, 0.0, mat_well))
    door = sheet("bay_" + s, rows, -DROP, THICK, mat_skin)
    # петля — по внешней кромке (столбец NY), середина по длине; X узла — вперёд вдоль петли
    a, b = rows[0][-1][0], rows[-1][-1][0]
    ax_x = (b - a).normalized()
    ax_z = Vector((0, 0, 1)) - ax_x * ax_x.z
    ax_z.normalize()
    ax_y = ax_z.cross(ax_x)
    mw = Matrix((ax_x, ax_y, ax_z)).transposed().to_4x4()
    mw.translation = (a + b) * 0.5 + Vector((0, 0, -DROP))
    door.data.transform(mw.inverted())
    door.matrix_world = mw
    out.append(door)

for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT", export_vertex_color="MATERIAL")
print("BAY %s: %d objects" % (dst, len(out)))
