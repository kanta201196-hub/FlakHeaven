"""Техника наземного конвоя (A-02, концепция docs/activities/convoy.md, референсы Kanta 17.10 —
/mnt/project-files/refs/convoy/). Вымышленные машины «по мотивам»: свой силуэт кабин, без марок,
решёток с логотипами, номеров и знаков. Окраска (решение Kanta 17.10, вопрос 4 = 3): песочный камуфляж под Нагорье — текстура пятен
из шума (camo_texture), на корпус кубической проекцией; тенты — выгоревший брезент, без красных полос.
Запуск: python3 convoy_models.py <truck|ifv|scout|technical|manpads|pickup_tent|crate> <out_dir>
Длина машины = 1, нос +X, низ колёс на z = 0. Подвижные части — отдельные узлы GLB:
  wheel_fl, wheel_fr, wheel_1l … — колёса: качение вокруг локальной Y; передние (wheel_f*) ещё и руль вокруг Z;
  tent     (грузовик) — тент с дугами, у остова прячется;
  track_l, track_r (БМП) — гусеницы с катками, бегущая текстура — в игре;
  turret   (БМП, броневик, боевой пикап) — башня или пулемёт на станке, поворот вокруг вертикали;
  gun      (БМП) — ствол, дочерний узел башни, подъём вокруг Y;
  launcher (пикап с ПЗРК) — труба с руками стрелка, подъём вокруг Y (захват цели — предупреждение)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L
import bmesh

kind, OUT = sys.argv[-2], sys.argv[-1]
L.reset()
CAMO = [(0.62, 0.52, 0.36), (0.50, 0.40, 0.27), (0.36, 0.30, 0.21)]   # песок, охра, бурый


def camo_texture(path, n=512, seed=7):
    """Пятна камуфляжа: два слоя сглаженного шума → три цвета, кромки ровные; плитка бесшовная"""
    import numpy as np
    rng = np.random.default_rng(seed)

    def noise(cells):
        g = rng.random((cells, cells))
        g = np.tile(g, (2, 2))[: cells + 1, : cells + 1]
        t = np.linspace(0, cells, n, endpoint=False)
        i = t.astype(int)
        f = t - i
        f = f * f * (3 - 2 * f)
        a = g[i][:, i] * (1 - f)[None, :] + g[i][:, i + 1] * f[None, :]
        b = g[i + 1][:, i] * (1 - f)[None, :] + g[i + 1][:, i + 1] * f[None, :]
        return a * (1 - f)[:, None] + b * f[:, None]

    v1 = noise(6) * 0.7 + noise(13) * 0.3
    v2 = noise(5) * 0.7 + noise(11) * 0.3
    img = np.empty((n, n, 3))
    img[:] = CAMO[0]
    img[v1 > 0.56] = CAMO[1]
    img[(v2 > 0.62) & (v1 <= 0.56)] = CAMO[2]
    img *= (0.96 + 0.04 * noise(40))[:, :, None]   # лёгкая неровность краски
    im = bpy.data.images.new("convoy_camo", n, n)
    rgba = np.concatenate([img[::-1], np.ones((n, n, 1))], axis=2).astype(np.float32)
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    return im


def camo_mat(name, im):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = im
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = 0.15
    b.inputs["Roughness"].default_value = 0.75
    return m


os.makedirs(OUT, exist_ok=True)
M_HULL = camo_mat("convoy_camo", camo_texture(os.path.join(OUT, "convoy_camo.png")))
M_DARK = mat("convoy_dark", (0.09, 0.08, 0.07), 0.3, 0.7)
M_RED = mat("convoy_lamp", (0.55, 0.07, 0.05), 0.2, 0.5)     # только фонари
M_STEEL = mat("convoy_steel", (0.2, 0.19, 0.17), 0.6, 0.45)
M_GLASS = mat("enemy_glass", (0.05, 0.08, 0.1), 0.8, 0.1)
M_TYRE = mat("enemy_tyre", (0.04, 0.04, 0.04), 0.0, 0.9)
M_CANVAS = mat("convoy_canvas", (0.4, 0.36, 0.27), 0.0, 0.95)
M_CLOTH = mat("convoy_cloth", (0.33, 0.29, 0.21), 0.0, 0.9)    # одежда стрелков
M_SKIN = mat("convoy_skin", (0.36, 0.25, 0.18), 0.0, 0.7)
M_WOOD = mat("convoy_wood", (0.42, 0.32, 0.2), 0.0, 0.85)

PARENT = {}         # подвижная часть → родительская подвижная часть (иначе — корпус)


def prism_x(name, profile, x0, x1, m, bevel=0.01):
    """Профиль (y, z) в поперечном сечении, выдавлен вдоль X от x0 до x1"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new((x0, y, z)) for y, z in profile]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.x = x1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    return finish(ob, m, bevel, 2)


def rbox(name, c, s, m, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = s
    bpy.ops.object.transform_apply(scale=True)
    ob.rotation_euler = rot
    bpy.ops.object.transform_apply(rotation=True)
    return finish(ob, m, bevel)


def wheel(node, x, y, r, w, hub=True):
    """Колесо отдельным узлом: шина, диск, ступица; ось качения — локальная Y"""
    L.group = node
    L.pivots[node] = (x, y, r)
    s = 1 if y > 0 else -1
    cyl("tyre", (x, y, r), r, w, M_TYRE, "Y", 16, r * 0.12)
    if hub:
        cyl("rim", (x, y + s * w * 0.42, r), r * 0.58, w * 0.2, M_STEEL, "Y", 12)
        cyl("hub", (x, y + s * w * 0.55, r), r * 0.2, w * 0.16, M_DARK, "Y", 8)
    L.group = ""


def build_c(name, out):
    """Как turret_lib.build, но подвижная часть может висеть на другой (PARENT: ствол на башне)"""
    os.makedirs(out, exist_ok=True)
    for ob in L.parts:
        bpy.context.view_layer.objects.active = ob
        for md in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
    # развёртка кубом для пятен камуфляжа: в координатах мира, чтобы пятна шли через детали
    for ob in L.parts:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        me = ob.data
        uv = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
        for poly in me.polygons:
            n = poly.normal
            ax = max(range(3), key=lambda k: abs(n[k]))
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                u, v = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][ax]
                uv.data[li].uv = (u * 1.6, v * 1.6)
    groups = {}
    for ob in L.parts:
        groups.setdefault(ob["fh_group"], []).append(ob)
    root = None
    tris = 0
    for gname, obs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for ob in obs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.join()
        j = bpy.context.object
        j.name = gname if gname else name
        tris += sum(len(p.vertices) - 2 for p in j.data.polygons)
        if gname:
            bpy.context.scene.cursor.location = L.pivots.get(gname, (0, 0, 0))
            bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        else:
            root = j
    for gname in groups:
        if gname:
            o = bpy.data.objects[gname]
            mw = o.matrix_world.copy()
            o.parent = bpy.data.objects[PARENT[gname]] if gname in PARENT else root
            o.matrix_world = mw
    print("TRIS", tris)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format="GLB", use_selection=False)
    return root


# камеры: изометрия, сверху, сбоку и как в игре — наклон 28° от вертикали
SHOTS = [("iso", (1.1, -1.25, 0.9), (0, 0, 0.15), 50), ("top", (0, 0, 3.2), None, 45),
         ("side", (0, -2.4, 0.25), (0, 0, 0.18), 50),
         ("game28", (0, -3.0 * math.sin(math.radians(28)), 3.0 * math.cos(math.radians(28))), (0, 0, 0.1), 45)]


def gunner(x, y, z, kneel=False):
    """Стрелок: туловище, голова в шлеме; ноги — если стоит"""
    if not kneel:
        box("legs", (x, y, z + 0.04), (0.03, 0.04, 0.08), M_CLOTH, 0.006)
    zb = z + (0.04 if kneel else 0.08)
    box("torso", (x, y, zb + 0.04), (0.035, 0.05, 0.08), M_CLOTH, 0.008)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.018, location=(x, y, zb + 0.1))
    ob = bpy.context.object
    ob.name = "helmet"
    finish(ob, M_CLOTH)
    return zb


def pickup(bed):
    """Пикап по мотивам референсов: капот, одинарная кабина, кузов; bed — open | tent | mg | manpads"""
    W = 0.36
    R = 0.07
    YW = 0.15
    wheel("wheel_fl", 0.31, YW, R, 0.05)
    wheel("wheel_fr", 0.31, -YW, R, 0.05)
    wheel("wheel_1l", -0.29, YW, R, 0.05)
    wheel("wheel_1r", -0.29, -YW, R, 0.05)
    box("frame", (0.0, 0, 0.09), (0.92, 0.2, 0.03), M_DARK, 0.003)
    # капот и крылья: свой угловатый передок, решётка без эмблем
    prism("nose", [(0.2, 0.1), (0.49, 0.1), (0.5, 0.18), (0.48, 0.2), (0.2, 0.215)], W, M_HULL, 0.01)
    box("grille", (0.502, 0, 0.16), (0.006, 0.2, 0.04), M_DARK, 0.0)
    for i in range(3):
        box("grille_bar", (0.506, 0, 0.148 + i * 0.012), (0.003, 0.2, 0.003), M_STEEL, 0.0)
    box("bull_bar", (0.52, 0, 0.13), (0.012, W * 0.9, 0.05), M_DARK, 0.003)
    for s in (1, -1):
        box("headlamp", (0.503, s * 0.14, 0.17), (0.006, 0.04, 0.025), M_STEEL, 0.0)
        box("arch_f", (0.31, s * (W / 2 - 0.01), 0.17), (0.17, 0.02, 0.012), M_DARK, 0.002)
        box("arch_r", (-0.29, s * (W / 2 - 0.01), 0.17), (0.17, 0.02, 0.012), M_DARK, 0.002)
        box("mirror", (0.17, s * (W / 2 + 0.018), 0.27), (0.012, 0.006, 0.03), M_DARK, 0.0)
        box("step", (0.05, s * (W / 2 - 0.005), 0.085), (0.2, 0.025, 0.008), M_DARK, 0.0)
    cyl("snorkel", (0.2, 0.17, 0.27), 0.01, 0.13, M_DARK, "Z", 8)
    # кабина
    prism("cab", [(-0.05, 0.1), (0.2, 0.1), (0.2, 0.215), (0.15, 0.33), (-0.04, 0.335), (-0.05, 0.33)], W, M_HULL, 0.01)
    prism("windshield", [(0.193, 0.222), (0.2, 0.222), (0.157, 0.323), (0.15, 0.323)], W * 0.86, M_GLASS, 0.0)
    for s in (1, -1):
        box("side_window", (0.06, s * W / 2, 0.275), (0.13, 0.004, 0.065), M_GLASS, 0.0)
        box("door_line", (-0.01, s * W / 2, 0.2), (0.004, 0.004, 0.17), M_DARK, 0.0)
    box("rear_window", (-0.052, 0, 0.28), (0.004, W * 0.7, 0.05), M_GLASS, 0.0)
    # кузов
    box("bed_floor", (-0.27, 0, 0.13), (0.44, W, 0.02), M_HULL, 0.003)
    if bed not in ("open", "manpads"):
        for s in (1, -1):
            box("bed_side", (-0.27, s * (W / 2 - 0.006), 0.175), (0.44, 0.012, 0.07), M_HULL, 0.003)
        box("tailgate", (-0.484, 0, 0.175), (0.012, W, 0.07), M_HULL, 0.003)
    else:
        # платформа с низкими бортами и дугой безопасности — как на референсе открытого пикапа
        for s in (1, -1):
            box("bed_side", (-0.27, s * (W / 2 + 0.004), 0.16), (0.44, 0.008, 0.04), M_HULL, 0.002)
        box("tailgate", (-0.488, 0, 0.16), (0.008, W, 0.04), M_HULL, 0.002)
        tube("roll_bar", [(-0.07, 0.16, 0.14), (-0.07, 0.16, 0.36), (-0.07, -0.16, 0.36), (-0.07, -0.16, 0.14)], 0.009, M_DARK)
    for s in (1, -1):
        box("tail_lamp", (-0.49, s * 0.15, 0.2), (0.006, 0.025, 0.02), M_RED, 0.0)
    if bed == "tent":
        L.group = "tent"
        L.pivots["tent"] = (-0.27, 0, 0.21)
        prof = [(W / 2 - 0.005, 0.21)] + [((W / 2 - 0.01) * math.cos(math.radians(a)), 0.3 + 0.03 * math.sin(math.radians(a))) for a in range(0, 181, 30)] + [(-W / 2 + 0.005, 0.21)]
        prism_x("tent_body", prof, -0.48, -0.06, M_CANVAS, 0.004)
        for k in range(3):
            x = -0.43 + k * 0.17
            prism_x("tent_rib", [(p[0] * 1.03, p[1] + 0.003) for p in prof], x - 0.005, x + 0.005, M_DARK, 0.0)
        L.group = ""
    elif bed == "mg":
        # крупнокалиберный пулемёт на станке-тумбе, стрелок за ним
        box("pedestal_base", (-0.27, 0, 0.15), (0.06, 0.06, 0.02), M_DARK, 0.003)
        cyl("pedestal", (-0.27, 0, 0.23), 0.012, 0.15, M_STEEL, "Z", 8)
        L.group = "turret"
        L.pivots["turret"] = (-0.27, 0, 0.3)
        box("mg_cradle", (-0.26, 0, 0.31), (0.06, 0.03, 0.03), M_DARK, 0.003)
        box("mg_body", (-0.25, 0, 0.33), (0.14, 0.028, 0.035), M_STEEL, 0.003)
        cyl("mg_barrel", (-0.1, 0, 0.335), 0.006, 0.18, M_STEEL, "X", 8)
        cyl("mg_muzzle", (-0.005, 0, 0.335), 0.01, 0.02, M_DARK, "X", 8)
        box("mg_box", (-0.25, 0.03, 0.315), (0.04, 0.03, 0.03), M_DARK, 0.002)
        box("mg_shield", (-0.2, 0, 0.35), (0.006, 0.09, 0.06), M_HULL, 0.002)
        gunner(-0.37, 0, 0.14)
        L.group = ""
    elif bed == "manpads":
        # стрелок с трубой ПЗРК стоит в кузове за дугой; второй номер с запасной трубой сидит у борта
        zb = gunner(-0.3, 0.04, 0.14)
        L.group = "launcher"
        L.pivots["launcher"] = (-0.3, 0.04, zb + 0.07)
        cyl("tube", (-0.29, 0.065, zb + 0.08), 0.012, 0.26, M_HULL, "X", 10)
        cyl("tube_cap", (-0.16, 0.065, zb + 0.08), 0.014, 0.012, M_DARK, "X", 10)
        box("grip", (-0.27, 0.065, zb + 0.06), (0.03, 0.012, 0.03), M_DARK, 0.0)
        box("sight", (-0.27, 0.085, zb + 0.09), (0.03, 0.012, 0.02), M_DARK, 0.0)
        box("arms", (-0.28, 0.05, zb + 0.065), (0.06, 0.03, 0.018), M_CLOTH, 0.004)
        L.group = ""
        gunner(-0.42, -0.1, 0.14, kneel=True)
        cyl("spare_tube", (-0.3, -0.13, 0.155), 0.012, 0.26, M_HULL, "X", 10)
        box("case", (-0.18, -0.1, 0.16), (0.1, 0.06, 0.04), M_DARK, 0.003)
    return W


if kind == "scout":
    # --- дозорный броневик: широкий низкий бронекорпус, малые окна-бойницы, башенка с пулемётом ---
    W = 0.44
    R = 0.085
    YW = 0.18
    wheel("wheel_fl", 0.3, YW, R, 0.065)
    wheel("wheel_fr", 0.3, -YW, R, 0.065)
    wheel("wheel_1l", -0.3, YW, R, 0.065)
    wheel("wheel_1r", -0.3, -YW, R, 0.065)
    box("frame", (0.0, 0, 0.11), (0.86, 0.22, 0.04), M_DARK, 0.004)
    # корпус: длинный плоский капот, рубка с наклонными бортами, корма прямая
    prism("hood", [(0.15, 0.12), (0.48, 0.12), (0.5, 0.2), (0.47, 0.235), (0.15, 0.25)], W, M_HULL, 0.01)
    prism_x("cabin", [(W / 2, 0.12), (W / 2, 0.25), (W / 2 - 0.03, 0.37), (-W / 2 + 0.03, 0.37), (-W / 2, 0.25), (-W / 2, 0.12)], -0.48, 0.16, M_HULL, 0.01)
    prism("windshield_frame", [(0.15, 0.25), (0.18, 0.25), (0.16, 0.37), (0.13, 0.37)], W - 0.06, M_HULL, 0.004)
    for s in (1, -1):
        box("windshield", (0.165, s * 0.09, 0.31), (0.012, 0.14, 0.07), M_GLASS, 0.0)
        for x in (0.05, -0.15):
            rbox("side_window", (x, s * (W / 2 - 0.013), 0.31), (0.12, 0.004, 0.05), M_GLASS, (s * math.radians(-14), 0, 0))
            rbox("door_plate", (x, s * (W / 2 - 0.008), 0.24), (0.18, 0.006, 0.18), M_HULL, (s * math.radians(-6), 0, 0), 0.003)
        box("arch_f", (0.3, s * (W / 2 - 0.02), 0.2), (0.22, 0.05, 0.015), M_DARK, 0.003)
        box("arch_r", (-0.3, s * (W / 2 - 0.02), 0.2), (0.22, 0.05, 0.015), M_DARK, 0.003)
        box("headlamp", (0.495, s * 0.17, 0.2), (0.006, 0.04, 0.025), M_STEEL, 0.0)
        box("tail_lamp", (-0.485, s * 0.18, 0.3), (0.006, 0.03, 0.02), M_RED, 0.0)
    box("grille", (0.502, 0, 0.17), (0.006, 0.18, 0.05), M_DARK, 0.0)
    for i in range(5):
        box("grille_slot", (0.505, -0.08 + i * 0.04, 0.17), (0.004, 0.008, 0.045), M_STEEL, 0.0)
    box("bumper", (0.51, 0, 0.13), (0.02, W, 0.035), M_DARK, 0.003)
    cyl("spare", (-0.5, 0.08, 0.24), R, 0.06, M_TYRE, "X", 16)
    box("rear_door", (-0.483, -0.07, 0.25), (0.006, 0.14, 0.18), M_DARK, 0.0)
    cyl("whip", (-0.4, 0.18, 0.5), 0.002, 0.26, M_STEEL, "Z", 6)
    # башенка: кольцо, щиток с пулемётом
    L.group = "turret"
    L.pivots["turret"] = (-0.1, 0, 0.37)
    cyl("ring", (-0.1, 0, 0.385), 0.075, 0.03, M_DARK, "Z", 16)
    prism_x("shield", [(0.07, 0.4), (0.07, 0.47), (0.04, 0.49), (-0.04, 0.49), (-0.07, 0.47), (-0.07, 0.4)], -0.03, -0.012, M_HULL, 0.003)
    for s in (1, -1):
        rbox("shield_wing", (-0.05, s * 0.085, 0.435), (0.06, 0.006, 0.07), M_HULL, (0, 0, s * math.radians(35)), 0.002)
    box("mg_body", (-0.04, 0, 0.45), (0.12, 0.022, 0.03), M_STEEL, 0.003)
    cyl("mg_barrel", (0.08, 0, 0.455), 0.005, 0.15, M_STEEL, "X", 8)
    box("mg_box", (-0.06, 0.025, 0.44), (0.035, 0.025, 0.025), M_DARK, 0.002)
    gunner(-0.13, 0, 0.37, kneel=True)
    L.group = ""
    shots = SHOTS
    name = "convoy_scout"

elif kind in ("technical", "manpads", "pickup_tent"):
    pickup({"technical": "mg", "manpads": "manpads", "pickup_tent": "tent"}[kind])
    shots = SHOTS
    name = "convoy_" + kind

elif kind == "crate":
    # --- ящик груза: доски, обвязка, ручки; длина = 1 ---
    box("crate", (0, 0, 0.21), (1.0, 0.7, 0.42), M_WOOD, 0.02)
    for x in (-0.42, 0.42):
        box("rim_x", (x, 0, 0.21), (0.08, 0.72, 0.44), M_WOOD, 0.01)
    for z in (0.08, 0.34):
        box("strap", (0, 0, z), (1.02, 0.72, 0.03), M_DARK, 0.0)
    box("lid_seam", (0, 0, 0.422), (0.84, 0.02, 0.006), M_DARK, 0.0)
    for s in (1, -1):
        box("handle", (0, s * 0.36, 0.25), (0.2, 0.02, 0.04), M_STEEL, 0.004)
    shots = [("iso", (2.2, -2.5, 1.8), (0, 0, 0.2), 50), ("top", (0, 0, 6.0), None, 45)]
    name = "convoy_crate"

elif kind == "truck":
    # --- тяжёлый грузовик 6×6: кабина над передней осью, тандем сзади, кузов с тентом ---
    W = 0.3
    R = 0.068
    YW = 0.122
    wheel("wheel_fl", 0.31, YW, R, 0.055)
    wheel("wheel_fr", 0.31, -YW, R, 0.055)
    for i, x in enumerate((-0.16, -0.33)):
        wheel("wheel_%dl" % (i + 1), x, YW, R, 0.055)
        wheel("wheel_%dr" % (i + 1), x, -YW, R, 0.055)
    box("frame", (-0.03, 0, 0.1), (0.9, 0.15, 0.04), M_DARK, 0.004)
    # своя кабина: короткий капот-скос, плоская крыша, двухстворчатое лобовое
    prism("cab", [(0.24, 0.1), (0.48, 0.1), (0.5, 0.17), (0.49, 0.2), (0.455, 0.3), (0.255, 0.31), (0.24, 0.3)], W, M_HULL, 0.008)
    prism("windshield", [(0.487, 0.208), (0.492, 0.208), (0.458, 0.292), (0.453, 0.292)], W * 0.86, M_GLASS, 0.0)
    prism("windshield_post", [(0.488, 0.204), (0.495, 0.204), (0.461, 0.296), (0.454, 0.296)], 0.012, M_DARK, 0.0)
    for s in (1, -1):
        box("side_window", (0.39, s * W / 2, 0.255), (0.08, 0.004, 0.06), M_GLASS, 0.0)
        box("door_line", (0.33, s * W / 2, 0.2), (0.004, 0.004, 0.16), M_DARK, 0.0)
        box("step", (0.38, s * (W / 2 - 0.01), 0.085), (0.07, 0.03, 0.008), M_STEEL, 0.0)
        box("mirror", (0.47, s * (W / 2 + 0.022), 0.26), (0.012, 0.006, 0.04), M_DARK, 0.0)
        box("fender_f", (0.31, s * YW, 0.143), (0.15, 0.06, 0.006), M_DARK, 0.002)
        box("fender_r", (-0.245, s * YW, 0.143), (0.32, 0.06, 0.006), M_DARK, 0.002)
        box("headlamp", (0.502, s * 0.115, 0.13), (0.008, 0.03, 0.022), M_STEEL, 0.0)
        cyl("fuel_tank", (0.03, s * 0.115, 0.1), 0.028, 0.15, M_STEEL, "X", 12)
        box("toolbox", (0.14, s * 0.12, 0.1), (0.06, 0.035, 0.04), M_DARK, 0.002)
    box("grille", (0.503, 0, 0.165), (0.008, 0.16, 0.045), M_DARK, 0.0)
    for i in range(4):
        box("grille_bar", (0.508, 0, 0.15 + i * 0.011), (0.004, 0.17, 0.003), M_STEEL, 0.0)
    box("bumper", (0.51, 0, 0.09), (0.024, W, 0.026), M_DARK, 0.003)
    box("roof_hatch", (0.36, 0, 0.312), (0.05, 0.07, 0.008), M_DARK, 0.002)
    cyl("exhaust", (0.235, 0.12, 0.3), 0.009, 0.14, M_STEEL, "Z", 8)
    # запасное колесо стоя за кабиной
    cyl("spare", (0.215, 0, 0.215), R, 0.05, M_TYRE, "X", 16)
    # кузов-платформа с бортами
    box("bed", (-0.15, 0, 0.135), (0.66, W, 0.03), M_HULL, 0.004)
    for s in (1, -1):
        box("side_board", (-0.15, s * (W / 2 - 0.006), 0.175), (0.66, 0.012, 0.06), M_HULL, 0.003)
        box("mudflap", (-0.41, s * YW, 0.07), (0.006, 0.05, 0.06), M_DARK, 0.0)
    box("tail_board", (-0.477, 0, 0.175), (0.012, W, 0.06), M_HULL, 0.003)
    for s in (1, -1):
        box("tail_lamp", (-0.485, s * 0.12, 0.13), (0.006, 0.02, 0.012), M_RED, 0.0)
    # тент: сечение со скруглённой крышей, дуги поверх, задний полог
    L.group = "tent"
    L.pivots["tent"] = (-0.15, 0, 0.2)
    prof = [(-W / 2, 0.2), (W / 2, 0.2)]
    for i in range(9):
        a = math.radians(i * 180 / 8)
        prof.append((W / 2 * 0.98 * math.cos(a), 0.315 + 0.055 * math.sin(a)))
    prof = [(W / 2, 0.2)] + prof[2:] + [(-W / 2, 0.2)]
    prism_x("tent_body", prof, -0.47, 0.17, M_CANVAS, 0.004)
    for k in range(5):
        x = -0.44 + k * 0.145
        ribs = [(W / 2 + 0.003, 0.2)] + [(p[0] * 1.02, p[1] + 0.003) for p in prof[1:-1]] + [(-W / 2 - 0.003, 0.2)]
        prism_x("tent_rib", ribs, x - 0.006, x + 0.006, M_DARK, 0.0)
    box("tent_flap", (-0.474, 0, 0.29), (0.006, W * 0.9, 0.12), M_DARK, 0.0)
    L.group = ""
    shots = SHOTS
    name = "convoy_truck"

elif kind == "ifv":
    # --- боевая машина пехоты: клиновидный нос, двигатель спереди справа, башня в центре, кормовая дверь ---
    W = 0.42
    HB, HT = 0.07, 0.25          # низ и верх корпуса
    TW = 0.085                   # ширина гусеницы
    YT = W / 2 - TW / 2
    for side, s in (("l", 1), ("r", -1)):
        node = "track_" + side
        L.group = node
        L.pivots[node] = (0, s * YT, 0.05)
        # гусеница: обвод по профилю (низ плоский, спереди и сзади скруглён ленивцем и ведущим)
        prism("track", [(-0.46, 0.02), (0.38, 0.02), (0.44, 0.06), (0.43, 0.1), (0.4, 0.115), (-0.45, 0.115), (-0.48, 0.09), (-0.48, 0.05)],
              TW, M_TYRE, 0.006).location.y = s * YT
        bpy.ops.object.transform_apply(location=True)
        for i in range(7):
            x = -0.36 + i * 0.12
            cyl("roadwheel", (x, s * (YT + TW / 2 + 0.002), 0.055), 0.042, 0.008, M_STEEL, "Y", 12)
            cyl("roadwheel_hub", (x, s * (YT + TW / 2 + 0.006), 0.055), 0.013, 0.004, M_DARK, "Y", 8)
        cyl("idler", (0.4, s * (YT + TW / 2 + 0.002), 0.075), 0.03, 0.008, M_STEEL, "Y", 12)
        cyl("sprocket", (-0.445, s * (YT + TW / 2 + 0.002), 0.075), 0.033, 0.008, M_DARK, "Y", 12)
    L.group = ""
    # корпус: верхний и нижний лобовые листы клином, наклонная корма
    prism("hull", [(-0.46, HB), (0.4, HB), (0.47, 0.152), (-0.47, 0.152)], W - 2 * TW + 0.01, M_HULL, 0.006)
    # верхний корпус во всю ширину над гусеницами (как у БМП на референсах — высокий короб)
    prism("upper_hull", [(-0.47, 0.15), (0.43, 0.15), (0.34, HT), (-0.46, HT), (-0.48, 0.21)], W, M_HULL, 0.008)
    # надгусеничные полки и бортовые экраны поверх гусениц
    for s in (1, -1):
        box("fender", (-0.02, s * YT, 0.15), (0.9, TW + 0.012, 0.012), M_HULL, 0.003)
        prism("skirt", [(-0.44, 0.085), (0.36, 0.085), (0.42, 0.1), (0.42, 0.15), (-0.44, 0.15)], 0.01, M_HULL, 0.003).location.y = s * (W / 2 + 0.004)
        bpy.ops.object.transform_apply(location=True)
        for i in range(5):
            box("skirt_bolt", (-0.36 + i * 0.17, s * (W / 2 + 0.01), 0.1), (0.012, 0.004, 0.012), M_DARK, 0.0)
        box("stowage", (-0.3, s * (W / 2 - 0.05), 0.172), (0.18, 0.05, 0.03), M_DARK, 0.003)
    # крыша: люк водителя слева спереди, решётки двигателя справа, десантные люки сзади
    cyl("driver_hatch", (0.27, 0.08, HT + 0.004), 0.032, 0.012, M_DARK, "Z", 14)
    for i in range(4):
        box("engine_grille", (0.24 + i * 0.022, -0.08, HT - 0.004 - i * 0.0), (0.01, 0.12, 0.004), M_DARK, 0.0)
    for s in (1, -1):
        box("troop_hatch", (-0.33, s * 0.06, HT + 0.004), (0.11, 0.07, 0.01), M_DARK, 0.002)
    box("rear_door", (-0.468, 0, 0.15), (0.008, 0.16, 0.12), M_DARK, 0.002)
    for s in (1, -1):
        box("tail_lamp", (-0.474, s * 0.12, 0.18), (0.004, 0.02, 0.01), M_RED, 0.0)
        box("headlamp", (0.405, s * 0.14, 0.18), (0.02, 0.028, 0.014), M_STEEL, 0.0)
        box("tow_hook", (0.46, s * 0.07, 0.12), (0.016, 0.014, 0.02), M_DARK, 0.0)
    for y in (0.15, -0.15):
        cyl("whip", (-0.38, y, HT + 0.13), 0.002, 0.26, M_STEEL, "Z", 6)
    # башня: граненая, со сдвигом назад, прицел командира, дымовые гранатомёты по бортам
    TX = -0.02
    L.group = "turret"
    L.pivots["turret"] = (TX, 0, HT)
    cyl("turret_ring", (TX, 0, HT + 0.008), 0.095, 0.016, M_DARK, "Z", 20)
    prism("turret_body", [(TX - 0.16, HT + 0.012), (TX + 0.13, HT + 0.012), (TX + 0.17, HT + 0.05), (TX + 0.12, HT + 0.08),
                          (TX - 0.13, HT + 0.08), (TX - 0.17, HT + 0.06)], 0.19, M_HULL, 0.006)
    for s in (1, -1):
        rbox("turret_cheek", (TX + 0.02, s * 0.1, HT + 0.045), (0.22, 0.02, 0.06), M_HULL, (s * math.radians(-14), 0, 0), 0.004)
        for k in range(3):
            cyl("smoke_tube", (TX + 0.08 - k * 0.025, s * 0.115, HT + 0.075), 0.009, 0.04, M_DARK, "X", 8)
    box("bustle", (TX - 0.2, 0, HT + 0.05), (0.06, 0.18, 0.06), M_HULL, 0.004)
    box("cmd_sight", (TX - 0.05, 0.06, HT + 0.115), (0.04, 0.035, 0.05), M_DARK, 0.004)
    rbox("cmd_sight_glass", (TX - 0.028, 0.06, HT + 0.12), (0.003, 0.03, 0.025), M_GLASS)
    box("gunner_sight", (TX + 0.06, -0.08, HT + 0.11), (0.05, 0.03, 0.035), M_DARK, 0.004)
    cyl("cmd_hatch", (TX - 0.09, -0.04, HT + 0.083), 0.03, 0.008, M_DARK, "Z", 12)
    # ствол — отдельный узел на башне, шарнир у маски
    L.group = "gun"
    L.pivots["gun"] = (TX + 0.15, 0, HT + 0.055)
    PARENT["gun"] = "turret"
    box("mantlet", (TX + 0.16, 0, HT + 0.055), (0.04, 0.07, 0.05), M_HULL, 0.004)
    cyl("barrel", (TX + 0.3, 0, HT + 0.055), 0.008, 0.26, M_STEEL, "X", 10)
    cyl("barrel_jacket", (TX + 0.22, 0, HT + 0.055), 0.013, 0.1, M_DARK, "X", 10)
    cyl("muzzle", (TX + 0.435, 0, HT + 0.055), 0.012, 0.025, M_DARK, "X", 10)
    cyl("coax", (TX + 0.2, 0.03, HT + 0.045), 0.004, 0.06, M_STEEL, "X", 6)
    L.group = ""
    shots = [(n, p, t, f) for n, p, t, f in SHOTS]
    name = "convoy_ifv"

build_c(name, OUT)
preview(OUT, shots)
print("DONE")
