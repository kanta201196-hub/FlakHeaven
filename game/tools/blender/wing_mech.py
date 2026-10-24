"""Т-1: предкрылки и закрылки — часть базовой модели каждого самолёта (решение владельца 16.10, модуль 3).
Модели ангара не пересобираются: механизация — отдельный маленький GLB рядом с моделью, в тех же осях
(длина 1, нос +X, Z вверх в Blender). Игра подвешивает его к модели ангара и к боевой модели
(models/mech/fh_mech_<класс>_<ур>.glb) и красит пластины материалом самой модели: UV пластин сняты
с поверхности крыла под ними, поэтому камуфляж продолжается без шва; по линии шарнира — тёмный шов.
Узлы: slat_l, slat_r (передняя кромка), flap_l, flap_r (задняя кромка). Точка узла — середина шарнира,
локальная ось Y узла (в Godot −Z) — вдоль шарнира влево (+Y Blender) у обоих крыльев, X — вперёд по хорде,
Z — вверх. Закрылок вниз — поворот вокруг Y на −угол, предкрылок носком вниз — на +угол.

Запуск (bpy 5.x): python3 wing_mech.py <модель ангара.glb> <класс_ур> <out.glb>
  например: python3 wing_mech.py ../../models/hangar/fh_hangar_fighter_1.glb fighter_1 ../../models/mech/fh_mech_fighter_1.glb
После переделки модели (Т-2) — запустить заново; кромки ищутся по силуэту, в таблице ниже только размах."""
import sys, math
import bpy, bmesh
from mathutils import Vector, geometry

# Размах (y от оси, левое крыло; правое — зеркально) и середина хорды на концах отрезка (x),
# чтобы отличить крыло от мотогондол и стабилизатора. Снято по виду сверху 17.10.
# fighter_2 (Meshy model, 24.10): exposed wing |y| 0.18-0.41; inboard of 0.21 the tailplane almost touches the trailing
# edge under a top-down ray, so the flaps start at 0.21.
# Предкрылки — внешние 50–70% консоли, закрылки — внутренние, без элеронов на законцовке.
SPANS = {
    "fighter_1": {"slat": [(0.15, 0.30, -0.13, -0.22)], "flap": [(0.13, 0.24, -0.15, -0.19)]},
    "fighter_2": {"slat": [(0.20, 0.37, -0.165, -0.238)], "flap": [(0.21, 0.32, -0.174, -0.218)]},
    "attacker_1": {"slat": [(0.20, 0.42, -0.12, -0.17)], "flap": [(0.12, 0.32, -0.10, -0.14)]},
    "attacker_2": {"slat": [(0.20, 0.44, -0.16, -0.20)], "flap": [(0.15, 0.33, -0.15, -0.18)]},
    # «Кит 1»: между мотогондолами и за внешней
    "bomber_1": {"slat": [(0.21, 0.26, -0.03, -0.045), (0.37, 0.48, -0.11, -0.16)],
                 "flap": [(0.20, 0.27, -0.02, -0.04), (0.355, 0.41, -0.09, -0.12)]},
    "bomber_2": {"slat": [(0.20, 0.48, -0.11, -0.25)], "flap": [(0.17, 0.36, -0.10, -0.19)]},
}
SLAT_C = 0.15     # доля хорды
FLAP_C = 0.26
LIFT = 0.0022     # пластина над обшивкой, чтобы не утонула
THICK = 0.004
STEPS = 10

src, key, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene


def hit(x, y, down=True):
    """Точка на верхней (down) или нижней обшивке и UV в ней; None — промах"""
    o = Vector((x, y, 1.0 if down else -1.0))
    ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, o, Vector((0, 0, -1 if down else 1)))
    if not ok:
        return None
    me = ob.data
    poly = me.polygons[idx]
    uvl = me.uv_layers.active.data
    vs = [ob.matrix_world @ me.vertices[v].co for v in poly.vertices[:3]]
    uv = [Vector((*uvl[li].uv, 0)) for li in poly.loop_indices[:3]]
    b = geometry.barycentric_transform(loc, vs[0], vs[1], vs[2], uv[0], uv[1], uv[2])
    return loc, (b.x, b.y)


def edges(y, xm):
    """Передняя и задняя кромка крыла на сечении y: сплошной участок силуэта вокруг xm"""
    def inside(x):
        return hit(x, y) is not None
    if not inside(xm):
        return None
    le = xm
    while le < 0.6 and inside(le + 0.002):
        le += 0.002
    te = xm
    while te > -0.6 and inside(te - 0.002):
        te -= 0.002
    return le, te


def surf(x, y, xs):
    """Верхняя обшивка в x (если промах у самой кромки — ближайшая точка внутрь, к xs)"""
    for k in range(12):
        h = hit(x + (xs - x) * k / 11.0, y)
        if h:
            return Vector((x, y, h[0].z)), h[1]
    return None


# цвет пластин — цвет текстуры крыла под ними (вершинный цвет), чуть темнее, чтобы кромка читалась;
# UV текстуры Meshy рваные, поэтому саму текстуру на пластину не тянем
import numpy as np
_img = next(n.image for n in plane[0].data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image
            and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links))
_W, _H = _img.size
_PX = np.array(_img.pixels[:], dtype=np.float32).reshape(_H, _W, 4)
DARK = 0.86


def tex_color(uv):
    x = int((uv[0] % 1.0) * (_W - 1))
    y = int((uv[1] % 1.0) * (_H - 1))
    r = max(2, _W // 256)
    c = _PX[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1, :3].reshape(-1, 3).mean(axis=0)
    return (*(c * DARK), 1.0)


mat_skin = bpy.data.materials.new("mech_skin")    # в игре — материал с вершинным цветом
mat_skin.use_nodes = True
_ca = mat_skin.node_tree.nodes.new("ShaderNodeVertexColor")
_ca.layer_name = "Col"
mat_skin.node_tree.links.new(_ca.outputs["Color"], mat_skin.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
mat_seam = bpy.data.materials.new("mech_seam")
mat_seam.use_nodes = True
mat_seam.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.05, 0.05, 1)


def plate(name, kind, segs, side):
    """Пластина по размаху: ряд сечений, у каждого передняя и задняя точка на обшивке"""
    rows = []   # [(перед, зад, uv перед, uv зад)] по сечениям всех отрезков, с разрывами между отрезками
    for y0, y1, xm0, xm1 in segs:
        seg = []
        for i in range(STEPS + 1):
            t = i / STEPS
            y = (y0 + (y1 - y0) * t) * side
            e = edges(y, xm0 + (xm1 - xm0) * t)
            if e is None:
                continue
            le, te = e
            c = le - te
            if kind == "slat":
                xf, xb = le + 0.002, le - SLAT_C * c
            else:
                xf, xb = te + FLAP_C * c, te + 0.001
            mid = (le + te) * 0.5
            f, b = surf(xf, y, mid), surf(xb, y, mid)
            if f and b:
                seg.append((f, b))
        rows.append(seg)
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uvk = bm.loops.layers.uv.new("UVMap")
    colk = bm.loops.layers.color.new("Col")
    hinge = []
    uvmap = {}
    for seg in rows:
        prev = None
        for (fp, fuv), (bp, buv) in seg:
            up = Vector((0, 0, LIFT))
            dn = Vector((0, 0, LIFT - THICK))
            q = [bm.verts.new(fp + up), bm.verts.new(bp + up), bm.verts.new(bp + dn), bm.verts.new(fp + dn)]
            for v, uv in zip(q, (fuv, buv, buv, fuv)):
                uvmap[v] = uv
            hinge.append(fp if kind == "flap" else bp)
            if prev:
                for i in range(4):
                    j = (i + 1) % 4
                    face = bm.faces.new((prev[i], q[i], q[j], prev[j]))
                    for lp in face.loops:
                        lp[uvk].uv = uvmap[lp.vert]
                        lp[colk] = tex_color(uvmap[lp.vert])
            else:
                face = bm.faces.new(q)          # торец у корня
                for lp in face.loops:
                    lp[uvk].uv = uvmap[lp.vert]
                    lp[colk] = tex_color(uvmap[lp.vert])
            prev = q
        if prev:
            face = bm.faces.new(prev)           # торец у законцовки
            for lp in face.loops:
                lp[uvk].uv = uvmap[lp.vert]
                lp[colk] = tex_color(uvmap[lp.vert])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # шов по шарниру: тонкая тёмная полоска поверх пластины
    for seg in rows:
        for i in range(len(seg) - 1):
            pts = []
            for (fp, _), (bp, _) in seg[i:i + 2]:
                h = fp if kind == "flap" else bp
                d = (bp - fp).normalized() * (0.0025 if kind == "flap" else -0.0025)
                pts += [h + Vector((0, 0, LIFT + 0.0004)), h + d + Vector((0, 0, LIFT + 0.0004))]
            vv = [bm.verts.new(p) for p in (pts[0], pts[1], pts[3], pts[2])]
            fc = bm.faces.new(vv)
            fc.material_index = 1
            fc.normal_update()
            if fc.normal.z < 0:
                fc.normal_flip()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat_skin)
    me.materials.append(mat_seam)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    # точка и оси узла: середина шарнира, Y — вдоль шарнира наружу, X — вперёд по хорде
    a, b = hinge[0], hinge[-1]
    if b.y < a.y:      # ось Y узла всегда в +Y Blender (влево): у обоих крыльев Z вверх, повороты одинаковые
        a, b = b, a
    ax_y = (b - a).normalized()
    ax_x = Vector((1, 0, 0)) - ax_y * ax_y.x
    ax_x.normalize()
    ax_z = ax_x.cross(ax_y)
    from mathutils import Matrix
    mw = Matrix((ax_x, ax_y, ax_z)).transposed().to_4x4()
    mw.translation = (a + b) * 0.5
    me.transform(mw.inverted())
    ob.matrix_world = mw
    return sum(len(p.vertices) - 2 for p in me.polygons)


tris = 0
for kind in ("slat", "flap"):
    for side, s in ((1, "l"), (-1, "r")):
        tris += plate("%s_%s" % (kind, s), kind, SPANS[key][kind], side)
for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT", export_vertex_color="MATERIAL")
print("MECH %s: %d tris" % (dst, tris))
