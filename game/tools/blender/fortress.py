"""Босс «Крепость» (решение владельца 16.10): тяжёлый бомбардировщик-носитель, бой по фазам
турели → люки и двигатели → раскрытый корпус. Вымышленный, «по мотивам»: без знаков и надписей.
Запуск: python3 fortress.py <out_dir> [--sprite <png>] [--nopreview]
  out_dir/fortress.glb (+ .blend и предпросмотры); с --sprite ещё вид строго сверху с прозрачным фоном
  для спрайта art/enemies/e_fortress.png (ширина картинки = длина модели).
Длина модели = 1 (= LEN 270 пикс. в fortress.gd), нос +X, центр в начале координат.
Точки уязвимости стоят там же, где Fortress.points[i].off (пикс. / 270; в Blender Y = −y экрана):
  turret_1 левое крыло (−6, −78), turret_2 правое крыло (−6, 78), turret_3 верхняя (48, 0),
  turret_4 кормовая (−112, 0), engine_l (14, −44), engine_r (14, 44).
  Wing mode (--wing): dome turrets two per wing, turret_1/2 outer (−20, ∓92), turret_3/4 inner (−4, ∓48),
  engines (14, ∓21).
Подвижные узлы GLB:
  turret_1…turret_4 — башни (спаренные турели из turret_twin.py, S8-K1), поворот вокруг вертикали (стволы по +X);
  engine_l/r_prop  — соосные винты двигателей, вращаются вокруг оси X;
  hatch_l/r        — створки люков на спине (фаза 2), открываются поворотом вокруг оси X;
  bay_l/r          — ракеты под люками, приподнимаются, когда люки открыты;
  hull_l/r         — панели обшивки над «ядром» (фаза 3), откидываются;
  core             — раскалённое ядро внутри корпуса.
Wing mode (Kanta 27.10): hatch_l/r and hull_l/r are doors cut out of the hull's own top skin (spine_doors): the node
holds the dark edges, underside, hinge strip and latches; its child hatch_X_skin / hull_X_skin is the door's skin with
the hull's texture and UVs. engine_X_prop is the compressor face at the back of the hull's intake duct; the domes
sit on a level race with a fixed fairing ring down to the curved skin. Rebuild of the battle model:
  python3 fortress.py <out> --wing <e_fortress_hull.glb from sf_rework.py e_fortress_hull> --nopreview \\
      --sprite ../../art/enemies/e_fortress.png
  then copy <out>/fortress.glb to ../../models/battle/fh_battle_e_fortress.glb and run godot --import."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L
from turret_twin import twin
from mathutils import Matrix
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = args[0]
SPRITE = args[args.index("--sprite") + 1] if "--sprite" in args else ""
PREVIEW = "--nopreview" not in args   # Cycles previews take minutes on a CPU
# VIS-01 (Kanta 26.10): --wing <glb> builds the flying-wing «Крепость» on the reworked CC BY hull (sf_recipes
# e_fortress_hull) at the old span instead of the code-built fuselage; turrets, hatches and core sit on its top skin
WING = args[args.index("--wing") + 1] if "--wing" in args else ""
WING_SCALE = 0.404   # hull span 2.436 at length 1 → the old span 0.98
L.reset()
# корпус матовый (правило Kanta 19.10, S8-K1): краска без блеска, тон приглушён, полосы — тусклый сурик;
# лёгкая грязь — множитель цвета по вершинам (атрибут Col → glTF COLOR_0, см. grime() перед сборкой)
M_HULL = mat("enemy_hull", (0.115, 0.12, 0.112), 0.08, 0.9)
M_LIGHT = mat("enemy_hull_light", (0.17, 0.175, 0.165), 0.08, 0.88)
M_DARK = mat("enemy_dark", (0.05, 0.05, 0.055), 0.1, 0.9)
M_RED = mat("enemy_red", (0.3, 0.075, 0.045), 0.05, 0.9)
M_STEEL = mat("enemy_steel", (0.2, 0.205, 0.21), 0.15, 0.85)
M_GLASS = mat("enemy_glass", (0.05, 0.08, 0.1), 0.8, 0.1)
M_CORE = mat("enemy_core", (0.9, 0.3, 0.05), 0.0, 0.4)
_b = M_CORE.node_tree.nodes["Principled BSDF"]
_b.inputs["Emission Color"].default_value = (1.0, 0.35, 0.05, 1)
_b.inputs["Emission Strength"].default_value = 0.6
# башни — матовая краска врага (как у турелей игрока после решения Kanta 19.10: без блеска)
M_T_BODY = mat("enemy_turret", (0.12, 0.13, 0.12), 0.1, 0.85)
M_T_DARK = mat("enemy_turret_dark", (0.05, 0.05, 0.055), 0.1, 0.88)
M_T_BARREL = mat("enemy_turret_barrel", (0.16, 0.165, 0.17), 0.15, 0.8)
M_T_GLASS = mat("enemy_turret_glass", (0.05, 0.08, 0.1), 0.0, 0.8)
M_MSL = mat("enemy_missile", (0.3, 0.3, 0.29), 0.1, 0.75)   # the dome's rail missile: a shade lighter than the wing so it reads
# the dome's gun barrels: the turret's dark paint; the name tells the weathering bake where the muzzles are (soot)
M_T_GUN = mat("enemy_gun_barrel", (0.05, 0.05, 0.055), 0.1, 0.88)
TS = 0.062          # масштаб турели turret_twin (длина башни 1) в оси «Крепости» (длина самолёта 1)

PX = 270.0
FR = 0.058          # радиус фюзеляжа


def at(x_px, y_px):
    """Точка из осей fortress.gd (пикс., y экрана вниз) → Blender (x, y)"""
    return x_px / PX, -y_px / PX


def loft(name, st, m, seg=24):
    """Тело вращения вдоль X: станции (x, ry, rz, zc) — эллиптическое сечение"""
    bm = bmesh.new()
    rings = []
    for x, ry, rz, zc in st:
        rings.append([bm.verts.new((x, math.cos(2 * math.pi * i / seg) * ry, zc + math.sin(2 * math.pi * i / seg) * rz)) for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    for r in (rings[0], rings[-1]):
        bm.faces.new(r)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return finish(ob, m)


def plate(name, pts, z, thick, m, z_tip=None):
    """Плоская деталь (крыло, стабилизатор) по контуру в плане (x, y), толщина thick;
    z_tip — высота дальних от оси точек (поперечное V)"""
    bm = bmesh.new()
    ymax = max(abs(y) for x, y in pts) or 1
    def zz(y):
        return z if z_tip is None else z + (z_tip - z) * abs(y) / ymax
    top = [bm.verts.new((x, y, zz(y) + thick / 2)) for x, y in pts]
    bot = [bm.verts.new((x, y, zz(y) - thick / 2)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for i in range(n):
        bm.faces.new((top[i], bot[i], bot[(i + 1) % n], top[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob = finish(ob, m)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def wing_solid(name, root, tip, span_y, z0, z1, m, nx=10):
    """Крыло с профилем (толще к передней трети, тонкая задняя кромка): root/tip — (x передней, x задней кромки),
    толщина 12% хорды у корня и 9% у законцовки; z0 / z1 — высота корня / конца (поперечное V)"""
    bm = bmesh.new()
    def prof(t):   # t 0…1 от передней к задней кромке → полутолщина в долях хорды (NACA-подобный)
        return 0.6 * (0.2969 * math.sqrt(t) - 0.126 * t - 0.3516 * t * t + 0.2843 * t ** 3 - 0.1036 * t ** 4)
    secs = []
    for j, (y, (xl, xt), th, z) in enumerate(((0.0, root, 0.12, z0), (span_y, tip, 0.09, z1))):
        c = xl - xt
        up = [bm.verts.new((xl - c * (i / nx) ** 1.6, y, z + prof((i / nx) ** 1.6) * c * th / 0.12)) for i in range(nx + 1)]
        lo = [bm.verts.new((xl - c * (i / nx) ** 1.6, y, z - prof((i / nx) ** 1.6) * c * th / 0.12 * 0.6)) for i in range(1, nx)]
        secs.append(up + list(reversed(lo)))
    a, b = secs
    n = len(a)
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return finish(ob, m)


def sphere(name, c, r, sc, m, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m)


def turret(n, x, y, z, tier):
    """Башня — спаренная турель из turret_twin.py (решение Kanta 23.10, S8-K1: «используй имеющиеся модели»)
    в окраске врага, масштаб TS: погон Ø ≈ 0,055 длины самолёта. Основание-кольцо в корпусе неподвижно,
    вся башня со стволами — узел turret_n (поворот вокруг вертикали, стволы по +X)."""
    L.group = ""
    cyl("turret_ring", (x, y, z), 0.034, 0.008, M_DARK, "Z", 24)
    g = "turret_%d" % n
    k = len(L.parts)
    twin(tier, False, M_T_BODY, M_T_DARK, M_T_BARREL, M_T_GLASS, base=g, guns=g, seg=0.5)
    # S11-29: twin() sets the pivot of its gun group to the cradle trunnions in turret units; here the guns
    # are the turret node itself, so that pivot replaced the ring centre and the turrets swung off the hull
    # when render3d turned them. The node turns about the vertical through the ring centre.
    L.pivots[g] = (x, y, z)
    m = Matrix.Translation((x, y, z)) @ Matrix.Scale(TS, 4)
    for ob in L.parts[k:]:
        # фаски — в единицах турели, потом перенос в оси «Крепости»
        bpy.context.view_layer.objects.active = ob
        for md in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
        ob.data.transform(m @ ob.matrix_basis)
        ob.matrix_basis = Matrix.Identity(4)
    L.group = ""


SKIN = None   # wing mode: HullUV of the intact hull, set right after the import (the skin before any cut-out)


def top(x, y):
    """Height of the hull's top skin at (x, y) (wing mode): a ray from above onto the intact hull only, so a
    part already placed (a dome, a fan) or a hole already cut does not change where the next one sits"""
    loc, _n, _i, _d = SKIN.bvh.ray_cast(Vector((x, y, 1.0)), Vector((0, 0, -1)))
    return loc.z if loc is not None else 0.0


class HullUV:
    """The hull's paint under a point (wing mode): a ray straight down onto the hull triangles gives the UV
    there, so a fairing built on the skin carries on the camouflage and wear of the skin beneath it."""

    def __init__(self, hulls):
        from mathutils.bvhtree import BVHTree
        self.tris = []   # [(uv a, uv b, uv c, corners a, b, c, material)]
        verts, polys = [], []
        for ob in hulls:
            me = ob.data
            me.calc_loop_triangles()
            uvl = me.uv_layers.active.data
            for lt in me.loop_triangles:
                cs = [ob.matrix_world @ me.vertices[me.loops[li].vertex_index].co for li in lt.loops]
                uvs = [Vector((*uvl[li].uv, 0.0)) for li in lt.loops]
                polys.append((len(verts), len(verts) + 1, len(verts) + 2))
                verts += cs
                self.tris.append((uvs, cs, me.materials[lt.material_index]))
        self.bvh = BVHTree.FromPolygons(verts, polys)

    def at(self, x, y):
        """(uv, material) of the hull skin at plan point (x, y); None off the hull"""
        from mathutils.geometry import barycentric_transform
        loc, _n, i, _d = self.bvh.ray_cast(Vector((x, y, 1.0)), Vector((0, 0, -1)))
        if i is None:
            return None
        uvs, cs, m = self.tris[i]
        uv = barycentric_transform(loc, cs[0], cs[1], cs[2], uvs[0], uvs[1], uvs[2])
        return (uv.x, uv.y), m

    def paint(self, ob, x0, y0, k=1.0):
        """Give ob the hull material and UVs of the skin under it, its plan shrunk by k about (x0, y0)
        (k < 1 keeps a small dome inside one camouflage patch instead of smearing a wide strip onto it)"""
        mw = ob.matrix_world
        me = ob.data
        uvl = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
        m = self.at(x0, y0)[1]
        for li, lp in enumerate(me.loops):
            p = mw @ me.vertices[lp.vertex_index].co
            hit = self.at(x0 + (p.x - x0) * k, y0 + (p.y - y0) * k) or self.at(x0, y0)
            uvl.data[li].uv = hit[0]
        me.materials.clear()
        me.materials.append(m)


def ellipsoid(name, c, r, m, seg=32, rings=16):
    """Upper half of an ellipsoid with radii r = (rx, ry, rz), base on c"""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.05], context="VERTS")
    for v in bm.verts:
        v.co = Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = c
    bpy.context.view_layer.update()
    return finish(ob, m)


DOME_R, DOME_H = 0.018, 0.0102   # 60 % of the old twin turret (ring Ø 0.068 → dome Ø 0.036 of the hull length)


def fairing(name, x, y, zb, r0, r1, hull_uv, seg=24, rings=4):
    """Fixed fairing ring of a dome turret (Kanta 27.10: seat the domes into the skin): the dome turns on a level
    race at height zb, while the wing under it is curved and tilted, so a flat collar floated on one side and
    sank on the other. The ring starts level at radius r0 (under the dome's rim) and runs down to the real skin
    at r1 with a cosine shoulder; every vertex takes the hull's UV under it, so the ring is the same painted skin."""
    bm = bmesh.new()
    grid = []
    for j in range(rings + 1):
        t = j / rings
        r = r0 + (r1 - r0) * t
        f = 0.5 * (1.0 + math.cos(math.pi * t))   # 1 at the race, 0 on the skin
        row = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            px, py = x + r * math.cos(a), y + r * math.sin(a)
            assert SKIN.at(px, py) is not None, ("fairing off the wing", name, px, py)
            zs = top(px, py) + 0.00015
            row.append(bm.verts.new((px, py, zs + (zb - zs) * f)))
        grid.append(row)
    for a, b in zip(grid, grid[1:]):
        for i in range(seg):
            bm.faces.new((a[i], b[i], b[(i + 1) % seg], a[(i + 1) % seg]))
    bm.faces.new(list(reversed(grid[0])))   # the race floor under the dome, never seen but closes the ring
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    if bm.faces[0].normal.z < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    finish(ob, M_HULL)
    hull_uv.paint(ob, x, y, 1.0)
    return ob


def dome_turret(n, x, y, hull_uv):
    """Wing-mode turret (Kanta 26.10, concept Б and his sketch): a low dome on a fixed fairing ring blended into the
    skin, with a gun slit, twin short barrels, a seam band, a sensor eye and a small finned missile on a short rail
    along the crown. The ring stays with the hull; the dome, guns and rail are node turret_n, pivot on the vertical
    through the dome centre, barrels along +X, so render3d's yaw turns the whole dome to track the player. The
    missile is its own node turret_n_missile under turret_n, so it turns with the dome and can be hidden while it
    reloads after a launch. Dome and ring wear the hull's own paint (HullUV).
    The dome is a body of revolution turning about the vertical, so its base must be level: it sits on a race at
    the highest skin point under its rim (it never cuts into the skin as it turns), and the fairing ring fills the
    space between that level race and the curved skin around it."""
    R, H = DOME_R, DOME_H
    z = max(top(x + r * math.cos(a), y + r * math.sin(a)) for r in (0.0, R * 0.5, R) for a in
            (i * math.pi / 8 for i in range(16))) + 0.0004
    L.group = ""
    fairing("dome_fairing", x, y, z, R * 0.97, R * 1.45, hull_uv)
    L.group = "fittings"   # fixed dark fittings get the weathering bake; the hull skin keeps its own texture
    cyl("dome_seam", (x, y, z + H * 0.03), R * 1.03, H * 0.08, M_DARK, "Z", 32)
    g = "turret_%d" % n
    L.group = g
    L.pivots[g] = (x, y, z)
    dome = ellipsoid("dome", (x, y, z), (R, R, H), M_HULL)
    hull_uv.paint(dome, x, y, 0.8)
    # panel seam round the shoulder and a flush access hatch on the crown, just proud of the skin
    bpy.ops.mesh.primitive_torus_add(major_radius=R * 0.78, minor_radius=R * 0.014, major_segments=32, minor_segments=6,
                                     location=(x, y, z + H * 0.64))
    ob = bpy.context.object
    ob.name = "dome_panel"
    ob.scale = (1, 1, 0.6)
    bpy.ops.object.transform_apply(scale=True)
    finish(ob, M_DARK)
    # launch rail on the crown: a low pylon, the missile hangs on top of it nose forward; its foot goes down into
    # the curved crown (0.82 H, below the dome surface at the rail's ends) so neither end floats
    box("dome_rail", (x - R * 0.05, y, z + H * 0.975), (R * 0.9, R * 0.12, H * 0.31), M_T_DARK, 0.0)
    # gun slit in the front face and twin barrels with muzzle brakes, dark gunmetal
    box("dome_slit", (x + R * 0.62, y, z + H * 0.5), (R * 0.85, R * 0.62, H * 0.26), M_T_DARK, 0.0)
    for s in (-1, 1):
        by = y + s * R * 0.2
        cyl("barrel", (x + R * 1.12, by, z + H * 0.5), 0.0012, R * 1.15, M_T_GUN, "X", 12)
        cyl("muzzle", (x + R * 1.72, by, z + H * 0.5), 0.0018, R * 0.18, M_T_GUN, "X", 12)
    # sensor eye on the shoulder, looking where the guns look
    sphere("dome_eye_rim", (x + R * 0.55, y - R * 0.48, z + H * 0.72), R * 0.17, (1, 1, 0.55), M_T_DARK, 12)
    sphere("dome_eye", (x + R * 0.62, y - R * 0.48, z + H * 0.74), R * 0.12, (1, 1, 0.6), M_T_GLASS, 12)
    m = g + "_missile"
    L.group = m
    L.pivots[m] = (x, y, z)
    L.parents[m] = g
    mr, mz, mx0, mx1 = R * 0.1, z + H * 1.13 + R * 0.1, x - R * 0.7, x + R * 0.55   # body radius, axis height, tail, nose root
    cyl("msl_body", ((mx0 + mx1) / 2, y, mz), mr, mx1 - mx0, M_MSL, "X", 12)
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=mr, radius2=0.0, depth=R * 0.32, location=(mx1 + R * 0.16, y, mz))
    ob = bpy.context.object
    ob.name = "msl_nose"
    ob.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    finish(ob, M_T_DARK)
    for a in range(4):   # cruciform tail fins, and a smaller set of canards behind the nose
        ang = math.pi / 4 + a * math.pi / 2
        for fx, fl, fs in ((mx0 + R * 0.1, R * 0.22, R * 0.2), (mx1 - R * 0.12, R * 0.1, R * 0.09)):
            ob = box("msl_fin", (0, 0, 0), (fl, R * 0.04, fs), M_MSL, 0.0)
            ob.data.transform(Matrix.Rotation(ang - math.pi / 2, 4, "X") @ Matrix.Translation((0, 0, mr + fs / 2)))
            ob.location = (fx, y, mz)
    L.group = ""


if WING:
    bpy.ops.import_scene.gltf(filepath=WING)
    for ob in list(bpy.context.scene.objects):
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world.copy()
        ob.parent = None
        ob.matrix_world = Matrix.Scale(WING_SCALE, 4) @ mw
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        ob.name = "hull"
        ob["fh_group"] = ""
        L.parts.append(ob)
    for ob in list(bpy.context.scene.objects):
        if ob.type == "EMPTY":
            bpy.data.objects.remove(ob)
    bpy.context.view_layer.update()
    SKIN = HullUV([o for o in L.parts if o.name.startswith("hull")])
    # jet intakes (Kanta 27.10): the hull already has a letterbox intake mouth at the front of each engine hump
    # (lip at x ≈ 0.08, opening y ≈ ±0.055…0.095, z ≈ 0.009…0.019, duct back wall at x ≈ 0.05). The compressor
    # face sits at the back of that duct on its centre line, facing forward, with a fixed dark blanking disc behind
    # it; nothing of it reaches the hump's skin (the old fan stood half out of the hump, blades through the skin).
    # The face is the node render3d spins (engine_X_prop, rotation about X).
    FAN_X, FAN_Y, FAN_Z, FAN_R = 0.057, 0.0765, 0.0145, 0.0047
    for nm, s in (("engine_l", 1), ("engine_r", -1)):
        ey = s * FAN_Y
        L.group = "fittings"
        cyl("duct_blank", (FAN_X - 0.0022, ey, FAN_Z), FAN_R + 0.0008, 0.0006, M_DARK, "X", 16)
        L.group = nm + "_prop"
        L.pivots[L.group] = (FAN_X, ey, FAN_Z)
        cyl("fan_hub", (FAN_X, ey, FAN_Z), FAN_R * 0.38, 0.0018, M_STEEL, "X", 12)
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=FAN_R * 0.38, radius2=0.0, depth=0.0016,
                                        location=(FAN_X + 0.0017, ey, FAN_Z), rotation=(0, math.pi / 2, 0))
        ob = bpy.context.object
        ob.name = "fan_spinner"
        bpy.ops.object.transform_apply(rotation=True)
        finish(ob, M_STEEL)
        for i in range(9):
            a = i * 2 * math.pi / 9
            rc = FAN_R * 0.68
            bpy.ops.mesh.primitive_cube_add(size=1, location=(FAN_X, ey + math.cos(a) * rc, FAN_Z + math.sin(a) * rc))
            ob = bpy.context.object
            ob.name = "fan_blade"
            ob.scale = (0.0004, FAN_R * 0.62, 0.0016)
            ob.rotation_euler = (a, 0.0, 0.0)   # the long (Y) side radial
            bpy.ops.object.transform_apply(scale=True, rotation=True)
            # blade pitch: a twist about its own radial axis (transform_apply also applied the location, so the
            # mesh is in model coordinates: turn it about the blade centre)
            bc = Vector((FAN_X, ey + math.cos(a) * rc, FAN_Z + math.sin(a) * rc))
            ob.data.transform(Matrix.Translation(bc) @ Matrix.Rotation(0.45, 4, Vector((0, math.cos(a), math.sin(a))))
                              @ Matrix.Translation(-bc))
            finish(ob, M_DARK)
        L.group = ""
else:
    # --- фюзеляж: длинный, остеклённый нос, на корме сужается под кормовую башню ---
    loft("fuselage", [(0.5, 0.004, 0.004, -0.004), (0.49, 0.016, 0.015, -0.004), (0.475, 0.027, 0.026, -0.003),
                      (0.455, 0.037, 0.036, -0.002), (0.43, 0.046, 0.045, -0.001), (0.39, 0.053, 0.053, 0.0),
                      (0.33, 0.057, 0.058, 0.0), (0.25, FR, FR + 0.002, 0.0), (-0.1, FR, FR + 0.002, 0.0), (-0.22, FR * 0.97, FR, 0.001),
                      (-0.3, 0.052, 0.051, 0.003), (-0.38, 0.043, 0.041, 0.006), (-0.44, 0.032, 0.03, 0.01), (-0.5, 0.012, 0.012, 0.014)], M_HULL, 36)
    sphere("nose_glass", (0.468, 0, -0.002), 0.031, (1.1, 1.0, 0.9), M_GLASS, 28)
    for k in range(5):   # переплёт остеклённого носа
        a = math.pi * (k + 1) / 6
        tube("nose_frame", [(0.452, math.cos(a) * 0.035, -0.002 + math.sin(a) * 0.033), (0.49, math.cos(a) * 0.012, -0.002 + math.sin(a) * 0.011)], 0.0012, M_DARK)
    for x in (0.452, 0.472):
        cyl("nose_ring", (x, 0, -0.002), 0.036 if x < 0.46 else 0.029, 0.002, M_DARK, "X", 28)
    sphere("cockpit", (0.36, 0, 0.044), 0.03, (1.9, 1.0, 0.6), M_GLASS, 24)
    for x in (0.33, 0.35, 0.37, 0.39):   # переплёт фонаря
        k = math.sqrt(max(0.0, 1 - ((x - 0.36) / 0.057) ** 2))
        bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.05, major_segments=24, minor_segments=6,
                                         location=(x, 0, 0.044), rotation=(0, math.pi / 2, 0))
        fr = bpy.context.object
        bpy.ops.object.transform_apply(rotation=True)
        fr.scale = (0.03, 0.0305 * k, 0.0185 * k)
        bpy.ops.object.transform_apply(scale=True)
        finish(fr, M_DARK)
    tube("canopy_spine", [(0.305, 0, 0.0545), (0.415, 0, 0.0545)], 0.0012, M_DARK)
    # панели обшивки: кольцевые швы и продольные линии лючков
    for x in (0.42, 0.2, 0.08, -0.05, -0.17, -0.27, -0.38):
        r = FR if -0.22 < x < 0.25 else (0.05 if x > 0 else 0.046)
        cyl("seam", (x, 0, 0.0), r * 1.004, 0.0015, M_DARK, "X", 36)
    for s in (1, -1):
        box("side_hatch", (0.27, s * FR * 0.99, -0.012), (0.03, 0.002, 0.024), M_DARK, 0.0)
        box("side_line", (0.0, s * FR * 1.0, 0.018), (0.4, 0.0015, 0.0015), M_DARK, 0.0)
    cyl("antenna", (0.2, 0, FR + 0.012), 0.0015, 0.024, M_STEEL, "Z", 8)
    box("spine", (-0.02, 0, FR + 0.002), (0.5, 0.012, 0.008), M_LIGHT, 0.002)
    for x in (0.3, -0.31):
        cyl("red_band", (x, 0, 0), FR * 1.02 if x > 0 else 0.046, 0.016, M_RED, "X", 24)

    # --- крыло почти прямое, с поперечным V; красные законцовки; закрылки и предкрылки ---
    span = 0.48
    wing = [(0.07, 0.0), (-0.02, span), (-0.1, span), (-0.17, 0.0)]   # трапеция: корень шире, лёгкая стреловидность
    for s in (1, -1):
        wing_solid("wing", (0.07, -0.17), (-0.02, -0.1), s * span, -0.012, 0.01, M_HULL)
        for t in (0.3, 0.6, 0.85):   # швы панелей вдоль размаха
            x0, x1 = 0.07 - 0.09 * t, -0.17 + 0.07 * t
            y = s * span * t
            box("wing_seam", ((x0 + x1) / 2, y, -0.012 + 0.022 * t + 0.0075 * (1 - 0.25 * t)), (x0 - x1 - 0.04, 0.0015, 0.001), M_DARK, 0.0)
        plate("tip", [(-0.017, s * (span - 0.005)), (-0.103, s * (span - 0.005)), (-0.103, s * (span + 0.012)), (-0.02, s * (span + 0.012))],
              0.01, 0.016, M_RED)
        plate("flap", [(-0.145, s * 0.07), (-0.115, s * 0.36), (-0.128, s * 0.36), (-0.162, s * 0.07)], -0.004, 0.006, M_DARK, 0.004)
        plate("slat", [(0.032, s * 0.2), (0.002, s * 0.44), (-0.006, s * 0.44), (0.024, s * 0.2)], -0.002, 0.006, M_LIGHT, 0.008)

    # --- двигатели: две большие гондолы с соосными винтами (как в fortress.gd — два двигателя) ---
    for nm, (ex, ey) in (("engine_l", at(14, -44)), ("engine_r", at(14, 44))):
        L.group = ""
        loft("nacelle", [(0.2, 0.01, 0.01, 0.0), (0.185, 0.022, 0.024, 0.0), (0.15, 0.026, 0.03, -0.004),
                         (0.05, 0.025, 0.03, -0.008), (-0.04, 0.012, 0.014, -0.006), (-0.06, 0.004, 0.004, -0.004)], M_HULL, 20)
        nac = L.parts[-1]
        nac.location = (ex - 0.06, ey, -0.006)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = nac
        nac.select_set(True)
        bpy.ops.object.transform_apply(location=True)
        nac.name = nm + "_nacelle"
        cyl("intake", (ex + 0.1, ey, -0.032), 0.009, 0.03, M_DARK, "X", 12)
        for cx in (ex + 0.12, ex + 0.04):   # кольца капота
            cyl("cowl_ring", (cx, ey, -0.01), 0.0275, 0.003, M_DARK, "X", 24)
        for k in range(3):   # патрубки выхлопа
            cyl("stack", (ex + 0.06 - k * 0.018, ey + (0.026 if ey > 0 else -0.026), 0.006), 0.004, 0.01, M_STEEL, "X", 8)
        cyl("exhaust", (ex - 0.02, ey + (0.024 if ey > 0 else -0.024), 0.004), 0.006, 0.04, M_DARK, "X", 10)
        px = ex + 0.145
        for k, dx in enumerate((0.0, -0.014)):
            L.group = "%s_prop%s" % (nm, "" if k == 0 else "2")
            L.pivots[L.group] = (px + dx, ey, -0.006)
            for i in range(4):
                a = i * math.pi / 2 + (math.pi / 4 if k else 0)
                bpy.ops.mesh.primitive_cube_add(size=1, location=(px + dx, ey + math.cos(a) * 0.038, -0.006 + math.sin(a) * 0.038))
                ob = bpy.context.object
                ob.name = "blade"
                ob.scale = (0.004, 0.072, 0.011)
                ob.rotation_euler = (a, 0, 0)
                bpy.ops.object.transform_apply(scale=True, rotation=True)
                finish(ob, M_DARK)
        L.group = ""
        sphere("spinner", (px + 0.006, ey, -0.006), 0.014, (1.6, 1.0, 1.0), M_RED, 14)

    # --- хвост: стабилизатор и два киля на концах (H-хвост — силуэт сверху отличается от транспортника) ---
    for s in (1, -1):
        plate("stab", [(-0.4, 0.0), (-0.44, s * 0.17), (-0.49, s * 0.17), (-0.485, 0.0)], 0.02, 0.012, M_HULL)
        prism("fin", [(-0.42, 0.02), (-0.47, 0.11), (-0.5, 0.11), (-0.495, 0.02)], 0.008, M_HULL, 0.0)
        fin = L.parts[-1]
        fin.location.y = s * 0.17
        plate("fin_red", [(-0.462, s * 0.166), (-0.499, s * 0.166), (-0.499, s * 0.174), (-0.462, s * 0.174)], 0.115, 0.01, M_RED)

# --- башни ---
if WING:
    # the points match Fortress.points in fortress.gd: two dome turrets per wing (Kanta 26.10), outer pair first,
    # then the inner pair; turret_3 (inner left) is the command turret
    for n, (x, y) in enumerate([at(-20, -92), at(-20, 92), at(-4, -48), at(-4, 48)], 1):
        dome_turret(n, x, y, SKIN)
else:
    TPOS = [at(-6, -78), at(-6, 78), at(48, 0), at(-112, 0)]
    for n, (x, y) in enumerate(TPOS, 1):
        z = 0.008 if n <= 2 else (FR + 0.006 if n == 3 else 0.042)
        turret(n, x, y, z, 3 if n == 3 else 2)   # верхняя — ступень 3 (короба лент, прицел), остальные — 2

# --- wing mode: weapon bay (phase 2) and core access panel (phase 3) cut out of the centre-body skin ---
# Kanta 27.10: the old hatches and core panels were flat light boxes on top of the curved skin ("what is glued
# onto the Fortress?"). Here they are the hull's own skin: each door is cut out of the top skin along its outline,
# keeps the hull's triangles, UVs and paint (so it is flush and the same colour), gets a thin dark edge and
# underside, and a dark well goes down into the hull under it. What shows when closed: the seam gap round each
# door, a hinge strip along its outer edge and latch plates along the centre line.
# Placement, from the airframe (hull height map and top view):
#  - the centre body is the ridge |y| < ~0.035 from the canopy (x 0.10…0.16) back to the trailing-edge tip
#    (x −0.18); the engine humps run beside it at |y| 0.05…0.10, intakes at x ≈ 0.08, exhausts at x ≈ −0.08;
#  - the weapon bay sits on the ridge between the two engine humps, just aft of the canopy: two doors split on
#    the centre line, hinged on their outer edges (lines parallel to the centre line, the axis render3d turns
#    them about), with the fore and aft edges swept parallel to the leading edge (the usual sawtooth of a
#    flying wing's doors), so the bay is a chevron of constant length;
#  - the core panel is a larger access panel on the ridge aft of the bay, past a 0.016 frame, between the
#    exhaust humps: fore edge parallel to the leading edge like the bay's, aft edge parallel to the centre
#    section's trailing edge; split on the centre line, hinged on the outer edges as well.
LE_K = 0.71     # the leading edge runs x = 0.2 − 0.71·|y|: door edges parallel to it fall back 0.71 per |y|
TE_K = 0.94     # the centre section's trailing edge runs forward 0.94 per |y| from its tip (x −0.18, y 0)
SEAM = 0.001    # gap round a door; the dark wall of the well under it is the panel line
DOOR_T = 0.0012  # door skin thickness (dark edge and underside)
BAY_F, BAY_L, BAY_W = 0.074, 0.072, 0.03       # bay: fore point on the centre line, length along x, half width
CORE_F, CORE_A, CORE_W = -0.014, -0.135, 0.032  # core panel: fore point, aft point (centre line), half width


def _ccw(poly):
    """The polygon wound counter-clockwise seen from above"""
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]))
    return list(poly) if a > 0 else list(reversed(poly))


def _inside(poly, p, eps=1e-9):
    """Plan point p inside the convex counter-clockwise polygon"""
    for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
        if (bx - ax) * (p[1] - ay) - (by - ay) * (p[0] - ax) < -eps:
            return False
    return True


def _inset(poly, d):
    """Convex counter-clockwise polygon with its edge i (poly[i] → poly[i+1]) moved inward by d[i]"""
    n = len(poly)
    lines = []
    for i in range(n):
        a, b = Vector(poly[i]), Vector(poly[(i + 1) % n])
        t = (b - a).normalized()
        lines.append((a + Vector((-t.y, t.x)) * d[i], t))
    out = []
    for i in range(n):
        (p0, t0), (p1, t1) = lines[i - 1], lines[i]
        s = ((p1.x - p0.x) * t1.y - (p1.y - p0.y) * t1.x) / (t0.x * t1.y - t0.y * t1.x)
        q = p0 + t0 * s
        out.append((q.x, q.y))
    return out


def _new_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def cut_top(obs, poly, name):
    """Cut the top skin of obs inside the convex plan polygon poly out into new objects (the same materials and
    UVs, so the same paint); obs keep the rest of their skin with a hole. The skin is split exactly on the
    polygon's edges by vertical planes (only top faces reaching the polygon's box are split, so the rest of the
    hull is untouched). Returns the cut pieces."""
    poly = _ccw(poly)
    x0, x1 = min(p[0] for p in poly), max(p[0] for p in poly)
    y0, y1 = min(p[1] for p in poly), max(p[1] for p in poly)
    out = []
    for ob in obs:
        bm = bmesh.new()
        bm.from_mesh(ob.data)

        def region():
            fs = []
            for f in bm.faces:
                if f.normal.z < 0.05:
                    continue
                xs, ys = [v.co.x for v in f.verts], [v.co.y for v in f.verts]
                if max(xs) < x0 or min(xs) > x1 or max(ys) < y0 or min(ys) > y1:
                    continue
                c = f.calc_center_median()
                if abs(c.z - top(c.x, c.y)) > 0.0015:   # top skin only, not the duct roofs or the belly
                    continue
                fs.append(f)
            return fs

        for a, b in zip(poly, poly[1:] + poly[:1]):
            fs = region()
            geom = list({v for f in fs for v in f.verts}) + list({e for f in fs for e in f.edges}) + fs
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-7, plane_co=Vector((a[0], a[1], 0.0)),
                                   plane_no=Vector((b[1] - a[1], a[0] - b[0], 0.0)).normalized())
            bm.normal_update()
        bm.faces.ensure_lookup_table()
        bm.faces.index_update()
        sel = {f.index for f in region() if _inside(poly, f.calc_center_median())}
        if sel:
            cp = bm.copy()
            cp.faces.ensure_lookup_table()
            assert len(cp.faces) == len(bm.faces)
            bmesh.ops.delete(cp, geom=[f for i, f in enumerate(cp.faces) if i not in sel], context="FACES")
            bmesh.ops.delete(bm, geom=[bm.faces[i] for i in sel], context="FACES")
            piece = _new_object(name, cp)
            cp.free()
            for m in ob.data.materials:
                piece.data.materials.append(m)
            out.append(piece)
        bm.to_mesh(ob.data)
        bm.free()
    return out


def _join(obs, name):
    """One object from obs (None when obs is empty)"""
    if not obs:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for ob in obs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def door_back(skin, name, m):
    """The door's dark edge walls and underside: the skin piece lowered by DOOR_T (its inner face, seen when the
    door stands open) and walls round its free edges. The skin piece itself is the door's top."""
    src = bmesh.new()
    src.from_mesh(skin.data)
    bm = bmesh.new()
    up, low = {}, {}

    def tv(v):
        if v not in up:
            up[v] = bm.verts.new(v.co)
        return up[v]

    def lv(v):
        if v not in low:
            low[v] = bm.verts.new(v.co - Vector((0, 0, DOOR_T)))
        return low[v]

    for f in src.faces:
        bm.faces.new([lv(v) for v in reversed(f.verts)])   # facing down
    for e in src.edges:
        if len(e.link_faces) == 1:
            lp = e.link_loops[0]
            a, b = lp.vert, lp.link_loop_next.vert
            bm.faces.new((tv(a), lv(a), lv(b), tv(b)))      # facing out of the door
    src.free()
    ob = _new_object(name, bm)
    bm.free()
    return finish(ob, m)


def skin_patch(name, quad, m, lift=0.00035, n=8):
    """A thin plate lying on the skin over the plan quad [(x, y)] × 4 (bilinear, n cells along its first side)"""
    bm = bmesh.new()
    (ax, ay), (bx, by), (cx, cy), (dx, dy) = quad
    rows = []
    for j in range(2):
        row = []
        for i in range(n + 1):
            t = i / n
            if j == 0:
                px, py = ax + (bx - ax) * t, ay + (by - ay) * t
            else:
                px, py = dx + (cx - dx) * t, dy + (cy - dy) * t
            row.append(bm.verts.new((px, py, top(px, py) + lift)))
        rows.append(row)
    for i in range(n):
        bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    if bm.faces[0].normal.z < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    ob = _new_object(name, bm)
    bm.free()
    return finish(ob, m)


def well(name, outline, z_floor, m, floor_group=None):
    """Dark well under an opening: walls from the skin edge of the outline (any simple polygon) straight down to
    z_floor, facing into the well, and a floor at z_floor (in floor_group if given, e.g. the pulsing core)"""
    outline = _ccw(outline)
    pts = []
    for a, b in zip(outline, outline[1:] + outline[:1]):
        k = max(1, int(math.dist(a, b) / 0.004))
        pts += [(a[0] + (b[0] - a[0]) * i / k, a[1] + (b[1] - a[1]) * i / k) for i in range(k)]
    bm = bmesh.new()
    tops = [bm.verts.new((x, y, top(x, y) + 0.0003)) for x, y in pts]
    bots = [bm.verts.new((x, y, z_floor)) for x, y in pts]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((tops[i], tops[j], bots[j], bots[i]))   # normal to the left of a→b: into the well
    ob = finish(_new_object(name + "_walls", bm), m)
    bm.free()
    g = L.group
    if floor_group is not None:
        L.group = floor_group
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((x, y, z_floor)) for x, y in outline])
    ob2 = finish(_new_object(name + "_floor", bm), m)
    bm.free()
    L.group = g
    return ob, ob2


def spine_doors(hulls, half, prefix, latches):
    """Two doors split on the centre line out of the skin inside the plan outline: half(s) is the convex half
    polygon on side s (+1 left, −1 right) whose edge 0 runs along the centre line and edge 2 along the outer
    hinge line. Node prefix_l / prefix_r: dark edges, underside, hinge strip and latches (weathered); its child
    prefix_X_skin: the door's own skin with the hull paint. Pivot on the hinge line, so render3d's turn about X
    swings each door up and outwards. Returns {side: pivot}."""
    pivots = {}
    for s, side in ((1, "l"), (-1, "r")):
        hole = _ccw(half(s))
        pieces = cut_top(hulls, hole, prefix + "_cut")
        # the door: the hole less SEAM round it (half of it at the centre line, where the other door meets it)
        d = [SEAM * 0.5 if abs(hole[i][1]) < 1e-9 and abs(hole[(i + 1) % 4][1]) < 1e-9 else SEAM for i in range(4)]
        door = _inset(hole, d)
        skins = cut_top(pieces, door, prefix + "_skin")
        for p in pieces:   # the seam strip left round the door: open, the well wall shows through
            bpy.data.objects.remove(p)
        g = prefix + "_" + side
        skin = _join(skins, g + "_skin")
        outer = sorted(door, key=lambda p: -abs(p[1]))[:2]           # the hinge edge
        inner = sorted(door, key=lambda p: abs(p[1]))[:2]            # the centre-line edge
        xm = (outer[0][0] + outer[1][0]) / 2
        hy = outer[0][1]
        pv = (xm, hy, top(xm, hy) - DOOR_T * 0.5)
        pivots[side] = pv
        L.group = g
        L.pivots[g] = pv
        door_back(skin, "door_back", M_DARK)
        xa, xb = sorted((outer[0][0], outer[1][0]))
        w = 0.0013 * s
        skin_patch("hinge", [(xa + 0.001, hy - w * 0.15), (xb - 0.001, hy - w * 0.15),
                             (xb - 0.001, hy - w * 1.15), (xa + 0.001, hy - w * 1.15)], M_DARK)
        ia, ib = sorted((inner[0][0], inner[1][0]))
        iy = inner[0][1]
        for t in latches:
            lx = ia + (ib - ia) * t
            skin_patch("latch", [(lx - 0.0024, iy + s * 0.0006), (lx + 0.0024, iy + s * 0.0006),
                                 (lx + 0.0024, iy + s * 0.0022), (lx - 0.0024, iy + s * 0.0022)], M_DARK, n=3)
        skin["fh_group"] = g + "_skin"
        L.parts.append(skin)
        L.pivots[g + "_skin"] = pv
        L.parents[g + "_skin"] = g
    L.group = ""
    return pivots


def spine_bay(hulls):
    """Phase 2 weapon bay on the centre body (see the placement note above): doors hatch_l / hatch_r, the two
    missiles bay_l / bay_r lying in the well under them (render3d lifts them 0.012 when the doors open)."""
    xa = BAY_F - BAY_L

    def half(s):
        return [(BAY_F, 0.0), (xa, 0.0), (xa - LE_K * BAY_W, s * BAY_W), (BAY_F - LE_K * BAY_W, s * BAY_W)]

    outline = [(BAY_F, 0.0), (BAY_F - LE_K * BAY_W, BAY_W), (xa - LE_K * BAY_W, BAY_W), (xa, 0.0),
               (xa - LE_K * BAY_W, -BAY_W), (BAY_F - LE_K * BAY_W, -BAY_W)]
    # missiles: as before (body r 0.0055, 0.05 long, seeker eye in front), centred in the chevron at |y| = 0.016;
    # deep enough that each stays under the skin above it with 1.5 mm to spare while the doors are shut
    my, mr = 0.016, 0.0055
    fore = BAY_F - LE_K * (my + mr)           # the bay's fore edge where the missile's outer side is
    aft = xa - LE_K * (my - mr)               # its aft edge where the missile's inner side is
    x0 = (fore + aft) / 2 - 0.024             # missile from x0 − 0.005 (tail) to x0 + 0.053 (eye tip)
    assert x0 - 0.005 > aft + 0.001 and x0 + 0.053 < fore - 0.001, ("bay too short for the missiles", x0, fore, aft)
    sky = min(top(x, sy * yy) for x in np.linspace(x0 - 0.005, x0 + 0.053, 12) for yy in (my - mr, my, my + mr)
              for sy in (1, -1))
    mz = sky - 0.0015 - mr
    z_floor = min(mz - mr - 0.0005, min(top(x, y) for x, y in outline) - 0.004)
    L.group = "fittings"
    well("bay_well", outline, z_floor, M_DARK)
    for s, side in ((1, "l"), (-1, "r")):
        L.group = "bay_" + side
        L.pivots[L.group] = (x0 + 0.02, s * my, mz)
        cyl("missile", (x0 + 0.02, s * my, mz), mr, 0.05, M_STEEL, "X", 10)
        sphere("missile_eye", (x0 + 0.046, s * my, mz), mr, (1.3, 1, 1), M_GLASS, 10)
    L.group = ""
    spine_doors(hulls, half, "hatch", (0.3, 0.7))
    print("BAY floor %.4f missiles z %.4f skin min over them %.4f" % (z_floor, mz, sky))


def spine_core(hulls):
    """Phase 3 core under the large access panel aft of the bay (see the placement note above): panels hull_l /
    hull_r, node core (glowing block, coils and the well floor; render3d pulses it), walls in the fixed fittings."""
    def fore(y):
        return CORE_F - LE_K * abs(y)

    def aft(y):
        return CORE_A + TE_K * abs(y)

    def half(s):
        return [(CORE_F, 0.0), (CORE_A, 0.0), (aft(CORE_W), s * CORE_W), (fore(CORE_W), s * CORE_W)]

    outline = [(CORE_F, 0.0), (fore(CORE_W), CORE_W), (aft(CORE_W), CORE_W), (CORE_A, 0.0),
               (aft(CORE_W), -CORE_W), (fore(CORE_W), -CORE_W)]
    z_floor = min(top(x, y) for x, y in outline) - 0.006
    cx = -0.07
    L.group = "core"
    L.pivots[L.group] = (cx, 0, z_floor)
    L.group = "fittings"
    well("core_well", outline, z_floor, M_DARK, floor_group="core")
    L.group = "core"
    # the glowing block and its three coils as before (0.06 × 0.04 now, it fits the panel's narrower aft end)
    assert fore(0.02) > cx + 0.03 + 0.003 and aft(0.02) < cx - 0.03 - 0.003
    box("core_block", (cx, 0, z_floor + 0.0015), (0.06, 0.04, 0.003), M_CORE, 0.0)
    for x in (cx - 0.02, cx, cx + 0.02):
        cyl("core_coil", (x, 0, z_floor + 0.0025), 0.01, 0.003, M_DARK, "Z", 12)
    L.group = ""
    spine_doors(hulls, half, "hull", (0.2, 0.5, 0.8))
    print("CORE floor %.4f" % z_floor)


if WING:
    _hulls = [o for o in L.parts if o.name.startswith("hull") and o.get("fh_group", "") == ""]
    spine_bay(_hulls)
    spine_core(_hulls)
else:
    # --- люки на спине (фаза 2): ракеты под створками ---
    HX0, HX1, HY = -0.0, 0.12, 0.034
    L.group = "fittings"
    box("bay_well", ((HX0 + HX1) / 2, 0, FR + 0.0005), (HX1 - HX0, 0.07, 0.004), M_DARK, 0.0)
    for s, side in ((1, "l"), (-1, "r")):
        L.group = "bay_" + side
        L.pivots[L.group] = ((HX0 + HX1) / 2, s * 0.018, FR - 0.002)
        for x0 in (HX0 + 0.012, HX0 + 0.066):
            cyl("missile", (x0 + 0.02, s * 0.018, FR - 0.002), 0.0055, 0.05, M_STEEL, "X", 10)
            sphere("missile_eye", (x0 + 0.046, s * 0.018, FR - 0.002), 0.0055, (1.3, 1, 1), M_GLASS, 10)
        L.group = "hatch_" + side
        L.pivots[L.group] = ((HX0 + HX1) / 2, s * (HY + 0.004), FR + 0.006)
        box("hatch", ((HX0 + HX1) / 2, s * HY / 2, FR + 0.007), (HX1 - HX0, HY, 0.004), M_LIGHT, 0.001)
        box("hatch_stripe", ((HX0 + HX1) / 2, s * HY / 2, FR + 0.0095), (HX1 - HX0 - 0.02, 0.006, 0.001), M_RED, 0.0)
    L.group = ""

    # --- ядро (фаза 3): раскалённый блок под откидными панелями обшивки ---
    CX0, CX1 = -0.26, -0.08
    L.group = "core"
    L.pivots[L.group] = ((CX0 + CX1) / 2, 0, FR)
    box("core_well", ((CX0 + CX1) / 2, 0, FR + 0.0005), (CX1 - CX0, 0.066, 0.004), M_DARK, 0.0)
    box("core_block", ((CX0 + CX1) / 2, 0, FR + 0.002), (CX1 - CX0 - 0.03, 0.044, 0.003), M_CORE, 0.0)
    for x in (CX0 + 0.03, (CX0 + CX1) / 2, CX1 - 0.03):
        cyl("core_coil", (x, 0, FR + 0.003), 0.01, 0.003, M_DARK, "Z", 12)
    for s, side in ((1, "l"), (-1, "r")):
        L.group = "hull_" + side
        L.pivots[L.group] = ((CX0 + CX1) / 2, s * 0.036, FR + 0.006)
        box("hull_panel", ((CX0 + CX1) / 2, s * 0.018, FR + 0.006), (CX1 - CX0, 0.036, 0.004), M_HULL, 0.001)
        for x in (CX0 + 0.02, CX1 - 0.02):
            box("rivet_strip", (x, s * 0.018, FR + 0.0085), (0.004, 0.032, 0.001), M_DARK, 0.0)
    L.group = ""


def grime():
    """Лёгкая грязь и потёртости: пятна шумом (±8%), брюхо и корма темнее (копоть, пыль). Множитель пишется
    в sRGB (Godot читает COLOR_0 как sRGB) и умножается на цвет материала узлом Multiply — glTF его понимает."""
    from mathutils import noise
    for m in (M_HULL, M_LIGHT, M_DARK, M_RED):
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        ca = nt.nodes.new("ShaderNodeVertexColor")
        ca.layer_name = "Col"
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        mx.blend_type = "MULTIPLY"
        mx.inputs["Factor"].default_value = 1.0
        mx.inputs["A"].default_value = b.inputs["Base Color"].default_value[:]
        nt.links.new(ca.outputs["Color"], mx.inputs["B"])
        nt.links.new(mx.outputs["Result"], b.inputs["Base Color"])
    for ob in L.parts:
        me = ob.data
        a = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        if me.materials[0] not in (M_HULL, M_LIGHT, M_DARK, M_RED):
            for d in a.data:   # турели, стекло, сталь, ядро — без грязи (множитель 1)
                d.color = (1.0, 1.0, 1.0, 1.0)
            continue
        mb = ob.matrix_basis
        for i, v in enumerate(me.vertices):
            p = mb @ v.co
            k = 1.0 + 0.08 * noise.noise(p * 22.0) + 0.04 * noise.noise(p * 70.0)
            k *= 1.0 - 0.14 * min(1.0, max(0.0, -p.z / 0.04))          # брюхо
            k *= 1.0 - 0.1 * min(1.0, max(0.0, (-p.x - 0.25) / 0.2))   # корма
            k = max(0.0, min(1.0, k)) ** (1 / 2.2)
            a.data[i].color = (k, k, k * 0.98, 1.0)


def weather(root):
    """Weathered paint on everything but the hull skin (Kanta 26.10: the domes looked flat — even paint, no
    roughness, no wear). Wing mode only: the CC BY hull already carries its own baked texture (sf_recipes).
    Each surface keeps its own colour (turret_paint own-colour mode); the dome takes the skin under it.
    Atlas A — dome turret 1 with its rail missile, at turret scale; turrets 2…4 are the same meshes moved,
    so they share its mesh (UVs and material included: one texture set instead of four). Atlas B — every other
    moving or fixed detail: door edges, hinges and latches, bay missiles, the core, intake fans and the dark
    fittings on the skin. The doors' own skin (groups *_skin) keeps the hull's texture and UVs untouched, so a
    shut door is the same paint as the skin round it."""
    import turret_paint
    obj = bpy.data.objects
    pal = {"own": True, "seed": 31, "wear": 0.9, "dust": 0.7}
    turret_paint.bake_set([obj["turret_1"], obj["turret_1_missile"]], pal, 1024, "fortress_dome_paint", TS)
    for n in (2, 3, 4):
        for a, b in (("turret_1", "turret_%d" % n), ("turret_1_missile", "turret_%d_missile" % n)):
            # Kanta 27.10 review: copying turret 1's UVs loop by loop scrambled the paint on turrets 2…4 (the
            # joined parts came in another order, 40 % of the loops sat elsewhere); the mesh itself is shared now.
            # Each node's origin is its pivot and the parts are built relative to it, so the shapes are equal.
            old = obj[b].data
            obj[b].data = obj[a].data
            bpy.data.meshes.remove(old)
    rest = [o for o in obj if o.type == "MESH" and o.get("fh_group", "") and not o.name.startswith("turret_")
            and not o.name.endswith("_skin")]
    turret_paint.bake_set(rest, dict(pal, seed=37), 1024, "fortress_fit_paint", 0.1)


if not WING:
    grime()
root = build("fortress", OUT, before_export=weather if WING else None)

if SPRITE:
    # вид строго сверху, ортографический: ширина кадра = длина модели (1), фон прозрачный
    sc = bpy.context.scene
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(25), math.radians(10), math.radians(-30))
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.82, 0.85, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    sc.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.0
    cam.location = (0, 0, 2)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 64
    sc.cycles.device = "CPU"
    sc.render.film_transparent = True
    sc.render.resolution_x = 512
    sc.render.resolution_y = 512
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.render.filepath = SPRITE
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(sun)

if PREVIEW:
    root.location.z += 0.15
    preview(OUT, [("iso", (0.9, -1.1, 0.9), (0, 0, 0.15), 50), ("top", (0, 0, 2.6), None, 45),
                  ("side", (0, -2.2, 0.2), (0, 0, 0.15), 50)])
print("DONE")
