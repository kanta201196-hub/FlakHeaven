"""Босс «Крепость» (решение владельца 16.10): тяжёлый бомбардировщик-носитель, бой по фазам
турели → люки и двигатели → раскрытый корпус. Вымышленный, «по мотивам»: без знаков и надписей.
Запуск: python3 fortress.py <out_dir> [--sprite <png>] [--nopreview]
  out_dir/fortress.glb (+ .blend и предпросмотры); с --sprite ещё вид строго сверху с прозрачным фоном
  для спрайта art/enemies/e_fortress.png (ширина картинки = длина модели).
Длина модели = 1 (= LEN 270 пикс. в fortress.gd), нос +X, центр в начале координат.
Точки уязвимости стоят там же, где Fortress.points[i].off (пикс. / 270; в Blender Y = −y экрана):
  turret_1 левое крыло (−6, −78), turret_2 правое крыло (−6, 78), turret_3 верхняя (48, 0),
  turret_4 кормовая (−112, 0), engine_l (14, −44), engine_r (14, 44).
Подвижные узлы GLB:
  turret_1…turret_4 — башни (спаренные турели из turret_twin.py, S8-K1), поворот вокруг вертикали (стволы по +X);
  engine_l/r_prop  — соосные винты двигателей, вращаются вокруг оси X;
  hatch_l/r        — створки люков на спине (фаза 2), открываются поворотом вокруг оси X;
  bay_l/r          — ракеты под люками, приподнимаются, когда люки открыты;
  hull_l/r         — панели обшивки над «ядром» (фаза 3), откидываются;
  core             — раскалённое ядро внутри корпуса."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L
from turret_twin import twin
from mathutils import Matrix

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = args[0]
SPRITE = args[args.index("--sprite") + 1] if "--sprite" in args else ""
PREVIEW = "--nopreview" not in args   # Cycles previews take minutes on a CPU
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
for n, (x, y) in enumerate([at(-6, -78), at(-6, 78), at(48, 0), at(-112, 0)], 1):
    z = 0.008 if n <= 2 else (FR + 0.006 if n == 3 else 0.042)
    turret(n, x, y, z, 3 if n == 3 else 2)   # верхняя — ступень 3 (короба лент, прицел), остальные — 2

# --- люки на спине (фаза 2): ракеты под створками ---
HX0, HX1, HY = -0.0, 0.12, 0.034
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


grime()
root = build("fortress", OUT)

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
