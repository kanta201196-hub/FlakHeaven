"""Кормовая кабина стрелка «Кита» — продолжение фюзеляжа (замечание Kanta по тесту 3.5-s3: кормовая
установка встроена в корпус и в цвет обшивки). Отдельный маленький GLB в осях модели ангара, как
механизация крыла (wing_mech.py): models/mech/fh_tail_<класс>_<ур>.glb.
Сечение берётся с самой модели: эллипс фюзеляжа в X0 (лучи сверху, снизу и сбоку), дальше к X1 корпус
плавно сужается до шара установки. Цвет обшивки — вершинный, снят с текстуры фюзеляжа по кругу сечения,
поэтому верх и низ кабины того же тона, что фюзеляж перед ней. Узел ball_mount — центр шара со стволами
(игра ставит туда турель).

Weak-models list (Kanta 28.10, «кабина — капля»): the glazing is no longer a glass egg with torus hoops stuck on
the cone. The cabin is one lofted shell whose own quads are the details: over the rear of the cabin the upper
quads are panes set a little into the skin between frame strips (bows every third segment, a ring frame every
third ring), a flush side window each side ahead of it, a dark seam line where the cabin meets the fuselage and
a dark collar round the ball; short walls join the inset panes to the skin, so every frame edge is crisp.
Paint is matte (roughness 0.85); the livery shader repaints the skin (mech_skin) as before.
Build from the hangar model, the same skin the battle model is baked from (battle_bake.py):
  python3 tail_cabin.py game/models/hangar/fh_hangar_bomber_1.glb bomber_1 game/models/mech/fh_tail_bomber_1.glb \
      --tex=game/models/hangar/fh_hangar_bomber_1_col.jpg

Запуск (bpy 5.x): python3 tail_cabin.py <модель ангара.glb> <класс_ур> <out.glb> [--tex=<извлечённая *_0.png>]
--tex — цвет обшивки брать с извлечённой текстуры (там окраска splinter_camo.py), а не со встроенной в GLB.

Исправление 3.5-s4 (замечание 33, «непонятный элемент над фюзеляжем»): transform_apply в bpy по умолчанию
применяет и положение; поворот тора применялся вместе с положением, и следующий scale сжимал его к началу
координат — швы, погон и переплёты фонаря оказывались над серединой фюзеляжа «спиралью». Теперь применяется
только то, что нужно (location=False)."""
import sys, math
import bpy, bmesh
import numpy as np
from mathutils import Vector, geometry

# начало кабины (внутри фюзеляжа, чтобы не было щели) и торец под шар; доля сужения к торцу
TAILS = {
    "bomber_1": (-0.39, -0.478, 0.6),
    "bomber_2": (-0.385, -0.468, 0.55),
}
RINGS, SEG = 18, 36
SEAM_RING = 1          # the dark joint line with the fuselage
GLAZE0 = 8             # the canopy panes from this ring to the collar
WIN0, WIN1 = 4, 7      # the side windows
GROW = 1.06          # кабина чуть толще конуса фюзеляжа, чтобы его закрыть
DARK = 0.9

_args = [a for a in sys.argv if not a.startswith("--tex=")]
_tex = next((a[6:] for a in sys.argv if a.startswith("--tex=")), "")
src, key, dst = _args[-3], _args[-2], _args[-1]
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
if _tex:
    from PIL import Image
    _PX = np.asarray(Image.open(_tex).convert("RGBA"), np.float32)[::-1] / 255.0   # строки снизу вверх, как UV
    _H, _W = _PX.shape[:2]


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


M_SKIN = mat("mech_skin", None, 0.85, 0.1)
M_DARK = mat("tail_dark", (0.05, 0.05, 0.055, 1), 0.75, 0.3)
M_GLASS = mat("tail_glass", (0.06, 0.1, 0.12, 1), 0.08, 0.6)


def section(i):
    """x, half-width and half-height of ring i (0 = the joint inside the fuselage, RINGS = the ball end)"""
    f = i / RINGS
    s = GROW * (1.0 - (1.0 - TAPER) * f * f)
    return X0 + (X1 - X0) * f, a0 * s, b0 * s


def kind(i, k):
    """What the quad between rings i, i+1 and segments k, k+1 is: skin, glass, frame (skin between the panes),
    seam (the dark joint line at the fuselage) or collar (the dark ring round the ball)."""
    t = 2 * math.pi * (k + 0.5) / SEG
    up = math.sin(t)                 # +1 on top, -1 under the belly
    side = abs(math.cos(t))          # 1 on the flanks
    if i == SEAM_RING:
        return "seam"
    if i >= RINGS - 1:
        return "collar"
    if GLAZE0 <= i < RINGS - 1 and up > 0.25:          # the gunner's canopy over the rear of the cabin
        if (i - GLAZE0) % 3 == 2 or k % 3 == 0:        # ring frames every third ring, bows every third segment
            return "frame"
        return "glass"
    if WIN0 <= i < WIN1 and side > 0.8 and abs(up) < 0.5:   # a side window each side, ahead of the canopy
        return "glass"
    return "skin"


# panes and the seam sit a little below the skin; short walls join the levels, so each step reads as a crisp edge
INSET = {"skin": 1.0, "frame": 1.0, "glass": 0.975, "seam": 0.985, "collar": 1.0}
MATS = {"skin": 0, "frame": 0, "glass": 1, "seam": 2, "collar": 2}
bm = bmesh.new()
colk = bm.loops.layers.color.new("Col")
_vc = {}


def vert(i, k, s):
    """Shared vertex of ring i, segment k at inset s"""
    key = (i, k % SEG, s)
    if key not in _vc:
        x, a, b = section(i)
        t = 2 * math.pi * (k % SEG) / SEG
        _vc[key] = bm.verts.new((x, math.cos(t) * a * s, zc + math.sin(t) * b * s))
    return _vc[key]


def face(vs, mat, cols):
    """New face on the given verts with material index `mat`; corner colours come from the sampled skin ring
    (one segment per corner). The dark material (2) is flat-shaded so seams and walls read as crisp lines."""
    f = bm.faces.new(vs)
    f.material_index = mat
    f.smooth = mat != 2
    for lp, kk in zip(f.loops, cols):
        lp[colk] = ring_col[kk % SEG]
    return f


grid = {(i, k): kind(i, k) for i in range(RINGS) for k in range(SEG)}
for (i, k), kd in grid.items():
    s = INSET[kd]
    face((vert(i, k, s), vert(i, k + 1, s), vert(i + 1, k + 1, s), vert(i + 1, k, s)), MATS[kd], (k, k + 1, k + 1, k))
    # wall to the next segment (shared radial edge at k + 1)
    s2 = INSET[grid[(i, (k + 1) % SEG)]]
    if s2 != s:
        lo_s = min(s, s2)
        hi_s = max(s, s2)
        face((vert(i, k + 1, hi_s), vert(i + 1, k + 1, hi_s), vert(i + 1, k + 1, lo_s), vert(i, k + 1, lo_s)), 2,
             (k + 1,) * 4)
    # wall to the next ring (shared edge at ring i + 1)
    if i + 1 < RINGS:
        s2 = INSET[grid[(i + 1, k)]]
        if s2 != s:
            lo_s = min(s, s2)
            hi_s = max(s, s2)
            face((vert(i + 1, k, hi_s), vert(i + 1, k + 1, hi_s), vert(i + 1, k + 1, lo_s), vert(i + 1, k, lo_s)), 2,
                 (k, k + 1, k + 1, k))
# the end under the ball is closed (dark: only the collar shows round the ball)
cen = bm.verts.new((X1, 0, zc))
for k in range(SEG):
    face((vert(RINGS, k + 1, 1.0), vert(RINGS, k, 1.0), cen), 2, (k + 1, k, k))
bm.normal_update()
for f in bm.faces:
    c = f.calc_center_median()
    out = Vector((0, c.y, c.z - zc)) if (c.y ** 2 + (c.z - zc) ** 2) > 1e-10 else Vector((1, 0, 0))
    if len(f.verts) == 4 and f.material_index == 2 and abs(f.normal.x) > 0.7:
        continue   # ring walls face along the axis; recalc below keeps them consistent
    if f.normal.dot(out) < 0:
        f.normal_flip()
me = bpy.data.meshes.new("tail_cabin")
bm.to_mesh(me)
bm.free()
me.materials.append(M_SKIN)
me.materials.append(M_GLASS)
me.materials.append(M_DARK)
cab = bpy.data.objects.new("tail_cabin", me)
sc.collection.objects.link(cab)
parts = [cab]

mount = bpy.data.objects.new("ball_mount", None)
mount.location = (X1 - 0.002, 0, zc)
sc.collection.objects.link(mount)
mount.parent = cab
mount.matrix_parent_inverse = cab.matrix_world.inverted()
for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type not in ("MESH", "EMPTY") or (o.type == "EMPTY" and o is not mount):   # importer leftovers too
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT", export_vertex_color="MATERIAL")
print("TAIL %s: %d tris, ball at x=%.3f z=%.4f end r=%.4f/%.4f" % (dst, sum(len(p.vertices) - 2 for p in cab.data.polygons), X1, zc, *section(RINGS)[1:]))
