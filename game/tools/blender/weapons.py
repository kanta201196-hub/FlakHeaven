"""Подвесное оружие по примерам владельца 16.10 (catalog/refs/aam_*, rockets): 3 ступени, отличаются
формой, длиной и деталями, а не только размером. «По мотивам»: без надписей, номеров и эмблем.
Запуск: python3 weapons.py <aam|rockets> <1|2|3> <out_dir>
Единицы как у WeaponModels: длина 1 вдоль +X (нос вперёд), центр корпуса в начале координат,
верх (+Z в Blender, +Y в Godot) — сторона крепления к пилону.
  aam 1 — ракета средней дальности: гладкий светлый корпус, крестообразные крылья посередине, рули у сопла;
  aam 2 — ракета ближнего боя: тёмный нос со стеклянной головкой («глаз»), передние треугольные рули,
          тонкий корпус с поясками, задние рули с роллеронами;
  aam 3 — тяжёлая: гранёный корпус, скошенный нос с окном головки, большие крылья, сбрасываемый
          ускоритель с медным кольцом;
  rockets 1 — короткий блок с открытыми трубами; 2 — длинный блок с конусом-обтекателем из лепестков;
  rockets 3 — спаренные блоки с обтекателями на общей балке. У всех сверху балка-держатель с замками."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L

kind, tier, OUT = sys.argv[-3], int(sys.argv[-2]), sys.argv[-1]
L.reset()
M_WHITE = mat("white", (0.72, 0.73, 0.74), 0.3, 0.45)
M_DARK = mat("dark", (0.08, 0.08, 0.09), 0.4, 0.55)
M_STEEL = mat("steel", (0.38, 0.39, 0.4), 0.7, 0.35)
M_OLIVE = mat("olive", (0.3, 0.33, 0.26), 0.25, 0.6)
M_GLASS = mat("glass", (0.15, 0.25, 0.3), 0.6, 0.08)
M_BAND = mat("band", (0.62, 0.45, 0.12), 0.3, 0.5)
M_COPPER = mat("copper", (0.6, 0.3, 0.15), 0.8, 0.35)


def sel(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def fin(name, pts, thick, ang, m):
    """Плоскость оперения: контур (x, s) — s от оси наружу; поворот вокруг оси ракеты на ang"""
    ob = prism(name, [(x, s) for x, s in pts], thick, m, 0.0)
    sel(ob)
    ob.rotation_euler = (ang, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return ob


def cone(name, x0, x1, r0, r1, m, verts=24):
    """Усечённый конус вдоль X от x0 (радиус r0) до x1 (r1)"""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=abs(x1 - x0), location=((x0 + x1) / 2, 0, 0))
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = (0, math.pi / 2 if x1 > x0 else -math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return finish(ob, m)


def lugs(x_list, r):
    for x in x_list:
        box("lug", (x, 0, r + 0.006), (0.03, 0.014, 0.012), M_STEEL, 0.0)


if kind == "aam" and tier == 1:
    R = 0.034
    cyl("body", (-0.07, 0, 0), R, 0.84, M_WHITE, "X", 24)
    cone("nose", 0.35, 0.5, R, 0.008, M_WHITE)
    cyl("nozzle", (-0.495, 0, 0), R * 0.8, 0.012, M_DARK, "X", 20)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        fin("wing", [(-0.1, R * 0.8), (0.06, R * 0.8), (0.02, R + 0.05), (-0.08, R + 0.05)], 0.005, a, M_WHITE)
        fin("tail", [(-0.48, R * 0.8), (-0.37, R * 0.8), (-0.42, R + 0.045), (-0.48, R + 0.045)], 0.005, a, M_WHITE)
    lugs([0.12, -0.18], R)

elif kind == "aam" and tier == 2:
    R = 0.026
    cyl("body", (-0.12, 0, 0), R, 0.76, M_WHITE, "X", 20)
    cyl("seeker_sec", (0.36, 0, 0), R, 0.2, M_DARK, "X", 20)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=R, location=(0.46, 0, 0))
    ob = bpy.context.object
    ob.scale = (1.4, 1, 1)
    bpy.ops.object.transform_apply(scale=True)
    finish(ob, M_GLASS)
    for x in (0.2, 0.05, -0.36):
        cyl("band", (x, 0, 0), R * 1.03, 0.02, M_BAND, "X", 20)
    cyl("nozzle", (-0.505, 0, 0), R * 0.75, 0.012, M_DARK, "X", 16)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        fin("canard", [(0.24, R * 0.8), (0.34, R * 0.8), (0.25, R + 0.045)], 0.004, a, M_DARK)
        fin("tail", [(-0.5, R * 0.8), (-0.36, R * 0.8), (-0.44, R + 0.05), (-0.5, R + 0.05)], 0.004, a, M_WHITE)
    for k in range(4):   # роллероны — колёсики на концах задних рулей
        a = math.pi / 4 + k * math.pi / 2
        y, z = -math.sin(a) * (R + 0.05), math.cos(a) * (R + 0.05)
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.012, depth=0.006, location=(-0.485, y, z))
        ob = bpy.context.object
        ob.rotation_euler = (a, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        finish(ob, M_STEEL)
    lugs([0.1, -0.2], R)

elif kind == "aam" and tier == 3:
    R = 0.048
    cyl("body", (0.0, 0, 0), R, 0.66, M_WHITE, "X", 8)
    # скошенный нос: клин с окном головки
    prism("nose", [(0.33, -R * 0.92), (0.5, -R * 0.5), (0.5, R * 0.25), (0.33, R * 0.92)], R * 1.84, M_WHITE, 0.004)
    box("seeker_win", (0.499, 0, -R * 0.12), (0.004, R * 1.1, R * 0.55), M_GLASS, 0.0)
    cyl("dark_band", (0.3, 0, 0), R * 1.01, 0.025, M_DARK, "X", 8)
    box("side_panel", (0.05, 0, -R * 0.9), (0.24, R * 0.9, 0.006), M_DARK, 0.0)
    # ускоритель: цилиндр со скруглённым торцом и медным кольцом
    cyl("copper_ring", (-0.345, 0, 0), R * 0.85, 0.03, M_COPPER, "X", 20)
    cyl("booster", (-0.42, 0, 0), R * 0.9, 0.13, M_WHITE, "X", 20)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=R * 0.9, location=(-0.485, 0, 0))
    ob = bpy.context.object
    ob.scale = (0.4, 1, 1)
    bpy.ops.object.transform_apply(scale=True)
    finish(ob, M_DARK)
    cyl("booster_band", (-0.44, 0, 0), R * 0.92, 0.012, M_DARK, "X", 20)
    for k in range(2):
        a = math.pi / 2 + k * math.pi
        fin("wing", [(-0.06, R * 0.7), (0.12, R * 0.7), (0.0, R + 0.12), (-0.07, R + 0.12)], 0.006, a, M_WHITE)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        fin("tail", [(-0.33, R * 0.7), (-0.22, R * 0.7), (-0.28, R + 0.05), (-0.33, R + 0.05)], 0.005, a, M_WHITE)
    box("dorsal", (-0.05, 0, R + 0.012), (0.3, 0.012, 0.022), M_WHITE, 0.002)
    lugs([0.15, -0.2], R + 0.02)

elif kind == "rockets":
    def pod(y, x0, x1, R, tubes, petals):
        cyl("pod", (y * 0 + (x0 + x1) / 2, y, 0), R, x1 - x0, M_OLIVE, "X", 28, 0.004)
        for x in (x0 + 0.06, (x0 + x1) / 2, x1 - 0.06):
            cyl("seam", (x, y, 0), R * 1.01, 0.008, M_DARK, "X", 28)
        # сзади — открытые трубы
        cyl("rear_face", (x0 - 0.002, y, 0), R * 0.92, 0.006, M_DARK, "X", 28)
        rings = [(0.0, 1)] + [(R * 0.4, 6)] + ([(R * 0.72, tubes - 7)] if tubes > 7 else [])
        for rr, n in rings:
            for i in range(n):
                a = 2 * math.pi * i / n
                cyl("tube", (x0 - 0.004, y + math.cos(a) * rr, math.sin(a) * rr), R * 0.13, 0.006, M_STEEL, "X", 10)
        if petals:
            # конус-обтекатель из 8 лепестков, на кончике отверстие
            cone("petals", x1, x1 + R * 1.6, R, R * 0.12, M_OLIVE, 8)
        else:
            cyl("front_face", (x1 + 0.002, y, 0), R * 0.92, 0.006, M_DARK, "X", 28)
            for rr, n in rings:
                for i in range(n):
                    a = 2 * math.pi * i / n
                    cyl("tube_f", (x1 + 0.004, y + math.cos(a) * rr, math.sin(a) * rr), R * 0.13, 0.006, M_STEEL, "X", 10)

    def beam(x0, x1, z, w):
        box("beam", ((x0 + x1) / 2, 0, z), (x1 - x0, w, 0.045), M_STEEL, 0.004)
        box("beam_top", ((x0 + x1) / 2, 0, z + 0.025), ((x1 - x0) * 0.9, w * 0.6, 0.008), M_DARK, 0.0)
        for x in (x0 + 0.12, x1 - 0.12):
            cyl("hook", (x, 0, z + 0.04), 0.012, 0.03, M_STEEL, "Z", 10)

    if tier == 1:
        R = 0.15
        pod(0, -0.36, 0.36, R, 7, False)
        beam(-0.32, 0.32, R + 0.04, 0.07)
        for x in (-0.18, 0.0, 0.18):
            box("latch", (x, 0, R + 0.012), (0.05, 0.05, 0.025), M_DARK, 0.002)
    elif tier == 2:
        R = 0.16
        pod(0, -0.5, 0.25, R, 16, True)
        beam(-0.45, 0.22, R + 0.04, 0.08)
        for x in (-0.3, -0.1, 0.1):
            box("latch", (x, 0, R + 0.012), (0.05, 0.05, 0.025), M_DARK, 0.002)
    else:
        R = 0.15
        for y in (0.17, -0.17):
            pod(y, -0.5, 0.26, R, 16, True)
            for x in (-0.3, 0.05):
                tube("strut", [(x, y * 0.4, R + 0.05), (x, y, R * 0.7)], 0.012, M_DARK)
        beam(-0.45, 0.22, R + 0.06, 0.12)
        box("crossbar", (-0.12, 0, R + 0.045), (0.5, 0.36, 0.02), M_STEEL, 0.003)

L.group = ""
name = "%s_%d" % (kind, tier)
root = build(name, OUT)
root.location.z += 0.35   # для предпросмотра — над полом (в .glb центр остаётся в начале координат)
preview(OUT, [("iso", (1.3, -1.5, 1.25), (0, 0, 0.35), 60), ("side", (0, -2.4, 0.35), (0, 0, 0.35), 50)])
print("DONE")
