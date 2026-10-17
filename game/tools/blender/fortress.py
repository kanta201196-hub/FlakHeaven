"""Босс «Крепость» (решение владельца 16.10): тяжёлый бомбардировщик-носитель, бой по фазам
турели → люки и двигатели → раскрытый корпус. Вымышленный, «по мотивам»: без знаков и надписей.
Запуск: python3 fortress.py <out_dir> [--sprite <png>]
  out_dir/fortress.glb (+ .blend и предпросмотры); с --sprite ещё вид строго сверху с прозрачным фоном
  для спрайта art/enemies/e_fortress.png (ширина картинки = длина модели).
Длина модели = 1 (= LEN 270 пикс. в fortress.gd), нос +X, центр в начале координат.
Точки уязвимости стоят там же, где Fortress.points[i].off (пикс. / 270; в Blender Y = −y экрана):
  turret_1 левое крыло (−6, −78), turret_2 правое крыло (−6, 78), turret_3 верхняя (48, 0),
  turret_4 кормовая (−112, 0), engine_l (14, −44), engine_r (14, 44).
Подвижные узлы GLB:
  turret_1…turret_4 — башни, поворот вокруг вертикали (стволы по +X);
  engine_l/r_prop  — соосные винты двигателей, вращаются вокруг оси X;
  hatch_l/r        — створки люков на спине (фаза 2), открываются поворотом вокруг оси X;
  bay_l/r          — ракеты под люками, приподнимаются, когда люки открыты;
  hull_l/r         — панели обшивки над «ядром» (фаза 3), откидываются;
  core             — раскалённое ядро внутри корпуса."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = args[0]
SPRITE = args[args.index("--sprite") + 1] if "--sprite" in args else ""
L.reset()
M_HULL = mat("enemy_hull", (0.13, 0.14, 0.13), 0.45, 0.5)
M_LIGHT = mat("enemy_hull_light", (0.22, 0.23, 0.22), 0.4, 0.5)
M_DARK = mat("enemy_dark", (0.06, 0.06, 0.07), 0.4, 0.6)
M_RED = mat("enemy_red", (0.55, 0.07, 0.05), 0.2, 0.5)
M_STEEL = mat("enemy_steel", (0.34, 0.35, 0.36), 0.7, 0.35)
M_GLASS = mat("enemy_glass", (0.05, 0.08, 0.1), 0.8, 0.1)
M_CORE = mat("enemy_core", (0.9, 0.3, 0.05), 0.0, 0.4)
_b = M_CORE.node_tree.nodes["Principled BSDF"]
_b.inputs["Emission Color"].default_value = (1.0, 0.35, 0.05, 1)
_b.inputs["Emission Strength"].default_value = 0.6

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


def sphere(name, c, r, sc, m, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m)


def turret(n, x, y, z):
    """Башня со спаркой: основание в корпусе, поворотная часть — узел turret_n"""
    L.group = ""
    cyl("turret_ring", (x, y, z), 0.034, 0.008, M_DARK, "Z", 24)
    L.group = "turret_%d" % n
    L.pivots[L.group] = (x, y, z)
    sphere("dome", (x, y, z + 0.004), 0.028, (1.0, 1.0, 0.7), M_LIGHT)
    box("mantlet", (x + 0.022, y, z + 0.01), (0.02, 0.03, 0.016), M_DARK, 0.002)
    for s in (1, -1):
        cyl("barrel", (x + 0.06, y + s * 0.009, z + 0.01), 0.0045, 0.07, M_STEEL, "X", 10)
        box("brake", (x + 0.096, y + s * 0.009, z + 0.01), (0.01, 0.009, 0.009), M_STEEL, 0.0)
    L.group = ""


# --- фюзеляж: длинный, остеклённый нос, на корме сужается под кормовую башню ---
loft("fuselage", [(0.5, 0.004, 0.004, -0.004), (0.485, 0.022, 0.02, -0.004), (0.46, 0.036, 0.034, -0.002),
                  (0.42, 0.048, 0.046, 0.0), (0.36, 0.056, 0.054, 0.0), (0.25, FR, FR, 0.0), (-0.22, FR, FR, 0.0),
                  (-0.34, 0.048, 0.046, 0.004), (-0.44, 0.032, 0.03, 0.01), (-0.5, 0.012, 0.012, 0.014)], M_HULL)
sphere("nose_glass", (0.47, 0, 0.0), 0.03, (1.1, 1.0, 0.9), M_GLASS)
sphere("cockpit", (0.36, 0, 0.042), 0.03, (1.8, 1.0, 0.6), M_GLASS)
box("spine", (-0.02, 0, FR + 0.002), (0.5, 0.012, 0.008), M_LIGHT, 0.002)
for x in (0.3, -0.31):
    cyl("red_band", (x, 0, 0), FR * 1.02 if x > 0 else 0.046, 0.016, M_RED, "X", 24)

# --- крыло почти прямое, с поперечным V; красные законцовки; закрылки и предкрылки ---
span = 0.48
wing = [(0.07, 0.0), (-0.02, span), (-0.1, span), (-0.17, 0.0)]   # трапеция: корень шире, лёгкая стреловидность
for s in (1, -1):
    plate("wing", [(x, s * y) for x, y in wing], -0.012, 0.016, M_HULL, 0.01)
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
    turret(n, x, y, z)

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

root.location.z += 0.15
preview(OUT, [("iso", (0.9, -1.1, 0.9), (0, 0, 0.15), 50), ("top", (0, 0, 2.6), None, 45),
              ("side", (0, -2.2, 0.2), (0, 0, 0.15), 50)])
print("DONE")
