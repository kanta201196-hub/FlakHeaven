"""U-08: экспериментальное оружие тяжёлого подвеса самолёта ур. 2 (PR #68, #70) — модели вместо заглушки-бруска.
Одна модель на оружие (ступеней нет), подвес — по оси под фюзеляжем на пилоне (Hardpoint.heavy, slot_points).
Простые детали — Blender кодом, кредиты Meshy не тратятся. «По мотивам»: без надписей, номеров и эмблем.
Светящиеся части — материал с излучением (glTF emissive): по ним оружие узнаётся сверху.
  railgun — рельсотрон: длинная направляющая из двух тёмных шин, между ними голубые кольца-катушки,
            сзади короб накопителей с рёбрами; дульный срез на x = 0.5;
  emp     — ЭМИ-заряд: толстая капсула, посередине медная обмотка, спереди голубой купол-излучатель,
            сзади короткое крестовое оперение;
  laser   — лазер «Луч»: контейнер с рёбрами охлаждения по бокам, спереди шаровая головка
            с оранжевой линзой (смотрит вперёд-вниз);
  plasma  — плазменная бомба: светящийся фиолетовый шар-заряд в клетке из обручей, оживальный нос,
            оперение с кольцом.
Единицы как у WeaponModels: длина 1 вдоль +X (нос вперёд), центр корпуса в начале координат,
верх (+Z в Blender, +Y в Godot) — сторона крепления к пилону.
Запуск (bpy 5.x): python3 exp_weapons.py <railgun|emp|laser|plasma> <out_dir> [nopreview]
→ <out_dir>/exp_<оружие>.glb (в игре: models/weapons/exp_*.glb, WeaponModels.EXP_GLB)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import bmesh
import turret_lib as L

args = [a for a in sys.argv if a != "nopreview"]
kind, OUT = args[-2], args[-1]
L.reset()
M_HULL = mat("hull", (0.36, 0.38, 0.35), 0.45, 0.5)
M_DARK = mat("dark", (0.08, 0.08, 0.09), 0.4, 0.55)
M_STEEL = mat("steel", (0.38, 0.39, 0.4), 0.7, 0.35)
M_COPPER = mat("copper", (0.6, 0.3, 0.15), 0.8, 0.35)


def glow(name, rgb, strength=2.0):
    m = mat(name, rgb, 0.0, 0.3)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = (*rgb, 1)
    b.inputs["Emission Strength"].default_value = strength
    return m


def sel(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def sphere(name, c, r, sc, m, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m)


def torus(name, c, r, t, m, axis="X", seg=28):
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=t, major_segments=seg, minor_segments=8, location=c)
    ob = bpy.context.object
    ob.name = name
    if axis == "X":
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "Y":
        ob.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return finish(ob, m)


def cross_fins(x, r, span, chord, m, n=4, a0=math.pi / 4):
    """Оперение вокруг оси X: n плоскостей, корень на радиусе r"""
    for k in range(n):
        a = a0 + k * 2 * math.pi / n
        ob = box("fin", (x, 0, r + span / 2), (chord, 0.006, span), m, 0.0)
        sel(ob)
        bpy.context.scene.cursor.location = (x, 0, 0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        ob.rotation_euler = (a, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)


def pylon_lugs(xs, z):
    for x in xs:
        box("lug", (x, 0, z), (0.04, 0.02, 0.016), M_STEEL, 0.0)


if kind == "railgun":
    M_COIL = glow("glow_blue", (0.2, 0.6, 1.0), 2.5)
    box("rail_base", (-0.05, 0, 0.0), (0.9, 0.11, 0.05), M_HULL, 0.008)
    for y in (0.035, -0.035):
        box("rail", (0.03, y, 0.035), (0.94, 0.018, 0.045), M_DARK, 0.004)
    for i in range(7):
        x = -0.32 + i * 0.12
        torus("coil", (x, 0, 0.035), 0.05, 0.009, M_COIL, "X", 20)
    box("muzzle", (0.49, 0, 0.035), (0.03, 0.1, 0.07), M_STEEL, 0.004)
    box("caps", (-0.38, 0, 0.0), (0.26, 0.15, 0.1), M_HULL, 0.012)
    for i in range(5):
        box("rib", (-0.46 + i * 0.04, 0, 0.055), (0.012, 0.155, 0.012), M_DARK, 0.0)
    pylon_lugs((-0.3, 0.1), 0.055)
elif kind == "emp":
    M_DOME = glow("glow_blue", (0.25, 0.65, 1.0), 2.0)
    R = 0.11
    cyl("body", (-0.06, 0, 0), R, 0.62, M_HULL, "X", 28, 0.004)
    sphere("dome", (0.25, 0, 0), R * 0.97, (1.25, 1, 1), M_DOME, 28)
    torus("dome_ring", (0.245, 0, 0), R * 1.0, 0.01, M_DARK, "X", 28)
    for i in range(6):
        torus("winding", (-0.12 + i * 0.03, 0, 0), R * 1.04, 0.012, M_COPPER, "X", 28)
    cyl("tail", (-0.42, 0, 0), R * 0.7, 0.1, M_DARK, "X", 24)
    cross_fins(-0.4, R * 0.7, 0.08, 0.14, M_DARK)
    pylon_lugs((-0.2, 0.08), R + 0.006)
elif kind == "laser":
    M_LENS = glow("glow_orange", (1.0, 0.4, 0.05), 3.0)
    R = 0.085
    cyl("body", (-0.08, 0, 0), R, 0.66, M_HULL, "X", 24, 0.004)
    sphere("tail", (-0.41, 0, 0), R, (0.8, 1, 1), M_HULL, 24)
    for s in (1, -1):   # рёбра охлаждения по бокам
        for i in range(9):
            box("rad", (-0.3 + i * 0.05, s * (R + 0.012), 0.0), (0.012, 0.03, R * 1.3), M_DARK, 0.0)
    cyl("neck", (0.27, 0, 0), R * 0.85, 0.06, M_DARK, "X", 24)
    sphere("ball", (0.36, 0, -0.01), R * 1.05, (1, 1, 1), M_STEEL, 28)
    lens = cyl("lens", (0.44, 0, -0.03), R * 0.45, 0.012, M_LENS, "X", 24)
    sel(lens)
    bpy.context.scene.cursor.location = (0.36, 0, -0.01)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    lens.rotation_euler = (0, math.radians(18), 0)   # линза вперёд-вниз
    bpy.ops.object.transform_apply(rotation=True)
    torus("lens_ring", (0.0, 0, 0), R * 0.5, 0.008, M_DARK, "X", 24).location = (0.442, 0, -0.035)
    pylon_lugs((-0.22, 0.1), R + 0.006)
elif kind == "plasma":
    M_CORE = glow("glow_violet", (0.65, 0.2, 1.0), 2.5)
    R = 0.1
    sphere("core", (0.0, 0, 0), R * 0.95, (1.35, 1, 1), M_CORE, 28)
    for i in range(3):   # клетка из продольных обручей
        ob = torus("cage", (0, 0, 0), R * 1.05, 0.008, M_DARK, "Y", 28)
        sel(ob)
        ob.scale = (1.35, 1, 1)
        bpy.ops.object.transform_apply(scale=True)
        ob.rotation_euler = (i * math.pi / 3, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
    torus("belt", (0, 0, 0), R * 1.07, 0.012, M_STEEL, "X", 28)
    cyl("nose_base", (0.17, 0, 0), R * 0.75, 0.06, M_HULL, "X", 24)
    sphere("nose", (0.2, 0, 0), R * 0.75, (2.1, 1, 1), M_HULL, 24)
    cyl("tail_base", (-0.18, 0, 0), R * 0.75, 0.06, M_HULL, "X", 24)
    cyl("tail", (-0.3, 0, 0), R * 0.45, 0.2, M_HULL, "X", 20)
    cross_fins(-0.36, R * 0.45, 0.09, 0.13, M_DARK)
    torus("fin_ring", (-0.38, 0, 0), R * 0.95, 0.008, M_DARK, "X", 24)
    pylon_lugs((-0.1, 0.1), R * 0.95 + 0.006)
else:
    raise SystemExit("неизвестное оружие " + kind)

L.group = ""
root = build("exp_" + kind, OUT)
root.location.z += 0.35
if "nopreview" not in sys.argv:
    preview(OUT, [("iso", (1.3, -1.5, 1.25), (0, 0, 0.35), 60), ("top", (0.001, 0, 2.6), (0, 0, 0.35), 50)])
print("DONE")
