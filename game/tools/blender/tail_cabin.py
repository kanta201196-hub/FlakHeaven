"""Кормовая кабина стрелка «Кита» — продолжение фюзеляжа (замечание Kanta по тесту 3.5-s3: кормовая
установка встроена в корпус и в цвет обшивки). Отдельный маленький GLB в осях модели ангара, как
механизация крыла (wing_mech.py): models/mech/fh_tail_<класс>_<ур>.glb.
Сечение берётся с самой модели: эллипс фюзеляжа в X0 (лучи сверху, снизу и сбоку), дальше к X1 корпус
плавно сужается до шара установки. Цвет обшивки — вершинный, снят с текстуры фюзеляжа по кругу сечения,
поэтому верх и низ кабины того же тона, что фюзеляж перед ней. Сверху у торца — остеклённый фонарь
с переплётами, по бокам окна. Узел ball_mount — центр шара со стволами (игра ставит туда турель).

Запуск (bpy 5.x): python3 tail_cabin.py <модель ангара.glb> <класс_ур> <out.glb>"""
import sys, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, geometry

# начало кабины (внутри фюзеляжа, чтобы не было щели) и торец под шар; доля сужения к торцу
TAILS = {
    "bomber_1": (-0.39, -0.478, 0.6),
    "bomber_2": (-0.385, -0.468, 0.55),
}
RINGS, SEG = 10, 28
GROW = 1.06          # кабина чуть толще конуса фюзеляжа, чтобы его закрыть
DARK = 0.9

src, key, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
X0, X1, TAPER = TAILS[key]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene
_img = next(n.image for n in plane[0].data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image
            and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links))
_W, _H = _img.size
_PX = np.array(_img.pixels[:], dtype=np.float32).reshape(_H, _W, 4)


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


# сечение в X0: низ по оси, полуширина сбоку, верх — в стороне от киля (на 0.6 полуширины)
lo = ray((X0, 0, -1), (0, 0, 1))[0].z
side = ray((X0, 1, lo + 0.012), (0, -1, 0))[0].y
a0 = abs(side)
top = ray((X0, a0 * 0.6, 1), (0, 0, -1))[0].z
low6 = ray((X0, a0 * 0.6, -1), (0, 0, 1))[0].z
zc = (top + low6) * 0.5
b0 = (top - low6) / 1.6
side = ray((X0, 1, zc), (0, -1, 0))[0].y
a0 = abs(side)
print("TAIL section: zc=%.4f a=%.4f b=%.4f" % (zc, a0, b0))

# цвет по кругу сечения — с обшивки чуть впереди кабины
# лучи — из точки рядом с обшивкой (не издалека: стабилизаторы и киль закрывают фюзеляж), медиана по длине
ring_col = []
for k in range(SEG):
    t = 2 * math.pi * k / SEG
    d = Vector((0, math.cos(t), math.sin(t)))
    cs = []
    for dx in (0.02, 0.05, 0.08, 0.11, 0.14):
        h = ray((X0 + dx, d.y * a0 * 3, zc + d.z * b0 * 3), (0, -d.y, -d.z))
        if h:
            cs.append(h[1][:3])
    c = np.median(np.array(cs), axis=0) if cs else np.array([0.6, 0.6, 0.62])
    ring_col.append((*c, 1.0))
print("TAIL colour", np.round(np.mean([c[:3] for c in ring_col], axis=0), 2))


def mat(name, col=None, rough=0.5, metal=0.3, alpha=1.0):
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


M_SKIN = mat("mech_skin")
M_DARK = mat("tail_dark", (0.06, 0.06, 0.065, 1), 0.5, 0.5)
M_GLASS = mat("tail_glass", (0.06, 0.1, 0.12, 1), 0.08, 0.6)


def section(i):
    f = i / RINGS
    s = GROW * (1.0 - (1.0 - TAPER) * f * f)
    return X0 + (X1 - X0) * f, a0 * s, b0 * s


bm = bmesh.new()
colk = bm.loops.layers.color.new("Col")
rings = []
for i in range(RINGS + 1):
    x, a, b = section(i)
    rings.append([bm.verts.new((x, math.cos(2 * math.pi * k / SEG) * a, zc + math.sin(2 * math.pi * k / SEG) * b))
                  for k in range(SEG)])
for i in range(RINGS):
    for k in range(SEG):
        k2 = (k + 1) % SEG
        f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
        for lp, kk in zip(f.loops, (k, k2, k2, k)):
            lp[colk] = ring_col[kk]
# торец под шар закрыт обшивкой (тёмный только тонкий погон — тор ниже)
cen = bm.verts.new((X1, 0, zc))
for k in range(SEG):
    f = bm.faces.new((rings[-1][(k + 1) % SEG], rings[-1][k], cen))
    for lp, kk in zip(f.loops, ((k + 1) % SEG, k, k)):
        lp[colk] = ring_col[kk]
# трубка открыта спереди — recalc_face_normals ошибается; разворачиваем по радиусу: нормали наружу
bm.normal_update()
for f in bm.faces:
    c = f.calc_center_median()
    out = Vector((0, c.y, c.z - zc)) if (c.y ** 2 + (c.z - zc) ** 2) > 1e-10 else Vector((-1, 0, 0))
    if f.normal.dot(out) < 0:
        f.normal_flip()
me = bpy.data.meshes.new("tail_cabin")
bm.to_mesh(me)
bm.free()
me.materials.append(M_SKIN)
cab = bpy.data.objects.new("tail_cabin", me)
sc.collection.objects.link(cab)
parts = [cab]


def add(ob, m):
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.use_smooth = True
    parts.append(ob)
    return ob


# фонарь стрелка: остеклённый горб сверху у торца с переплётами
xe, ae, be = section(RINGS)
xm, am, bm_ = section(int(RINGS * 0.55))
cx = (xm + xe) * 0.5
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=(cx, 0, zc + bm_ * 0.62))
can = bpy.context.object
can.scale = (abs(xe - xm) * 0.55, am * 0.6, bm_ * 0.5)
bpy.ops.object.transform_apply(scale=True)
add(can, M_GLASS)
for fx in (-0.5, 0.0, 0.5):
    x = cx + fx * abs(xe - xm) * 0.55
    k = math.sqrt(max(0.0, 1 - fx * fx))
    bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.04, major_segments=24, minor_segments=6,
                                     location=(x, 0, zc + bm_ * 0.62), rotation=(0, math.pi / 2, 0))
    fr = bpy.context.object
    bpy.ops.object.transform_apply(rotation=True)
    fr.scale = (0.02, am * 0.6 * k * 1.03, bm_ * 0.5 * k * 1.03)
    bpy.ops.object.transform_apply(scale=True)
    add(fr, M_DARK)
# боковые окна
for sgn in (1, -1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=1,
                                         location=(xm + (xe - xm) * 0.2, sgn * am * 0.97, zc + bm_ * 0.1))
    w = bpy.context.object
    w.scale = (abs(xe - xm) * 0.22, am * 0.08, bm_ * 0.22)
    bpy.ops.object.transform_apply(scale=True)
    add(w, M_GLASS)
# шов на стыке с фюзеляжем и погон шара
for x, m in ((X0 + (X1 - X0) * 0.08, M_DARK), (X1, M_DARK)):
    _, a, b = section(0 if x != X1 else RINGS)
    bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.05, major_segments=SEG, minor_segments=6,
                                     location=(x, 0, zc), rotation=(0, math.pi / 2, 0))
    t = bpy.context.object
    bpy.ops.object.transform_apply(rotation=True)
    t.scale = (0.03, a * 1.01, b * 1.01)
    bpy.ops.object.transform_apply(scale=True)
    add(t, m)

bpy.ops.object.select_all(action="DESELECT")
for p in parts:
    p.select_set(True)
bpy.context.view_layer.objects.active = cab
bpy.ops.object.join()
mount = bpy.data.objects.new("ball_mount", None)
mount.location = (X1 - 0.002, 0, zc)
sc.collection.objects.link(mount)
mount.parent = cab
mount.matrix_parent_inverse = cab.matrix_world.inverted()
for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type not in ("MESH", "EMPTY"):
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT", export_vertex_color="MATERIAL")
print("TAIL %s: %d tris, ball at x=%.3f z=%.4f end r=%.4f/%.4f" % (dst, sum(len(p.vertices) - 2 for p in cab.data.polygons), X1, zc, ae, be))
