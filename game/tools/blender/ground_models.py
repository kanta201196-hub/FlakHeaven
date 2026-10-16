"""Наземная техника позиции ПВО (разбор каталога 16.10, примеры владельца 16.10): ЗСУ, ЗРК, РЛС в Blender.
Запуск: python3 ground_models.py <zsu|sam|radar> <out_dir>
Все три — на одном вымышленном 4-осном шасси (своя угловатая кабина, без марок и эмблем — «по мотивам»).
Длина машины = 1 (как ширина спрайта врага), нос +X, низ колёс на z = 0. Окраска врагов:
тёмный металл с красными полосами. Подвижные части — отдельные узлы GLB:
  turret   (ЗСУ) — башня, поворот вокруг вертикали, стоит на выносных опорах (боевое положение);
  launcher (ЗРК) — подъёмная рама с 4 контейнерами 2×2, в модели лежит по-походному;
               ось подъёма — шарнир сзади (в Godot поворот вокруг локальной Z, нос вверх);
  antenna  (РЛС) — поворотная установка с двумя большими и одной малой тарелкой, вращается."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L

kind, OUT = sys.argv[-2], sys.argv[-1]
L.reset()
M_HULL = mat("enemy_hull", (0.17, 0.18, 0.19), 0.45, 0.55)
M_DARK = mat("enemy_dark", (0.06, 0.06, 0.07), 0.4, 0.6)
M_RED = mat("enemy_red", (0.55, 0.07, 0.05), 0.2, 0.5)
M_STEEL = mat("enemy_steel", (0.32, 0.33, 0.34), 0.7, 0.35)
M_GLASS = mat("enemy_glass", (0.05, 0.08, 0.1), 0.8, 0.1)
M_TYRE = mat("enemy_tyre", (0.04, 0.04, 0.04), 0.0, 0.9)

W = 0.27            # ширина кузова
AXLES = [0.33, 0.19, -0.2, -0.34]
WR = 0.052          # радиус колеса


def rbox(name, c, s, m, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = s
    bpy.ops.object.transform_apply(scale=True)
    ob.rotation_euler = rot
    bpy.ops.object.transform_apply(rotation=True)
    return finish(ob, m, bevel)


def dish(name, c, r, m, rot=(0, -math.pi / 2, 0)):
    """Параболическая тарелка: усечённый конус, раструбом вдоль +X; облучатель по оси"""
    bpy.ops.mesh.primitive_cone_add(vertices=28, radius1=r, radius2=r * 0.22, depth=r * 0.38, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = rot
    bpy.ops.object.transform_apply(rotation=True)
    finish(ob, m)
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r * 0.08, depth=r * 0.9, location=c)
    ob = bpy.context.object
    ob.rotation_euler = rot
    bpy.ops.object.transform_apply(rotation=True)
    # облучатель выдвинут вперёд из центра тарелки
    d = ob.matrix_world.to_3x3() @ Vector((0, 0, -1))
    ob.location = Vector(c) + d * (r * 0.45)
    bpy.ops.object.transform_apply(location=True)
    finish(ob, M_DARK)


def jack(x, y):
    """Выносная опора: стойка до земли и пятка"""
    cyl("jack", (x, y, 0.05), 0.009, 0.1, M_STEEL, "Z", 10)
    cyl("jack_pad", (x, y, 0.004), 0.022, 0.008, M_DARK, "Z", 14)


def chassis():
    # колёса 8×8
    for x in AXLES:
        for s in (1, -1):
            cyl("wheel", (x, s * 0.112, WR), WR, 0.045, M_TYRE, "Y", 18, 0.006)
            cyl("hub", (x, s * 0.136, WR), WR * 0.5, 0.006, M_STEEL, "Y", 12)
    box("frame", (-0.02, 0, 0.085), (0.92, 0.14, 0.04), M_DARK, 0.004)
    # своя кабина: угловатая, капот-скос, разрезное лобовое, решётка-«отбойник»
    prism("cab", [(0.3, 0.07), (0.49, 0.07), (0.5, 0.135), (0.475, 0.19), (0.445, 0.262), (0.3, 0.262)], W, M_HULL, 0.008)
    # лобовое стекло лежит на скосе кабины, стойка посередине — два стекла
    prism("windshield", [(0.474, 0.196), (0.479, 0.196), (0.45, 0.258), (0.445, 0.258)], 0.23, M_GLASS, 0.0)
    prism("windshield_post", [(0.4745, 0.19), (0.481, 0.19), (0.451, 0.262), (0.4445, 0.262)], 0.012, M_DARK, 0.0)
    for s in (1, -1):
        box("side_window", (0.4, s * W / 2, 0.215), (0.07, 0.004, 0.05), M_GLASS, 0.0)
        box("door_line", (0.345, s * W / 2, 0.16), (0.004, 0.004, 0.13), M_DARK, 0.0)
        box("red_stripe", (0.4, s * W / 2, 0.12), (0.16, 0.004, 0.014), M_RED, 0.0)
        box("mirror", (0.47, s * (W / 2 + 0.02), 0.215), (0.012, 0.006, 0.03), M_DARK, 0.0)
        box("fender", (0.33, s * 0.112, 0.108), (0.12, 0.052, 0.006), M_DARK, 0.002)
        box("headlamp", (0.497, s * 0.1, 0.105), (0.008, 0.026, 0.018), M_STEEL, 0.0)
        cyl("fuel_tank", (0.0, s * 0.105, 0.07), 0.024, 0.13, M_STEEL, "X", 14)
    box("grille", (0.497, 0, 0.152), (0.008, 0.13, 0.04), M_DARK, 0.0)
    for i in range(5):
        box("grille_bar", (0.502, 0, 0.136 + i * 0.008), (0.004, 0.14, 0.003), M_STEEL, 0.0)
    box("bumper", (0.505, 0, 0.074), (0.02, W * 0.95, 0.022), M_DARK, 0.003)
    box("roof_hatch", (0.37, 0, 0.266), (0.05, 0.06, 0.008), M_DARK, 0.002)
    cyl("roof_lamp", (0.44, 0.09, 0.272), 0.008, 0.012, M_STEEL, "Z", 10)
    box("cab_back", (0.288, 0, 0.17), (0.024, W * 0.9, 0.16), M_DARK, 0.0)


chassis()

if kind == "zsu":
    # отсек аппаратуры за кабиной, запаска на борту, кузов с сеткой по бортам
    box("equip", (0.2, 0, 0.18), (0.16, W, 0.18), M_HULL, 0.006)
    for s in (1, -1):
        box("equip_vent", (0.2, s * W / 2, 0.19), (0.06, 0.004, 0.09), M_DARK, 0.0)
        box("ladder", (0.16, s * W / 2, 0.17), (0.018, 0.004, 0.1), M_STEEL, 0.0)
    cyl("spare", (0.255, 0.0, 0.29), 0.048, 0.04, M_TYRE, "Z", 18)
    box("body", (-0.19, 0, 0.15), (0.62, W, 0.1), M_HULL, 0.006)
    for s in (1, -1):
        box("body_mesh", (-0.25, s * W / 2, 0.15), (0.34, 0.004, 0.07), M_DARK, 0.0)
        box("red_band", (-0.19, s * W / 2, 0.193), (0.6, 0.004, 0.012), M_RED, 0.0)
        jack(-0.47, s * 0.13)
        jack(0.02, s * 0.13)
    box("rear_ladder", (-0.5, 0.09, 0.15), (0.006, 0.03, 0.1), M_STEEL, 0.0)
    # башня: корпус, по бортам — спаренные пушки и пакеты по 6 ракет, спереди круглый радар
    # сопровождения, сверху сзади — плоская антенна обзора
    L.group = "turret"
    L.pivots["turret"] = (-0.18, 0, 0.2)
    cyl("ring", (-0.18, 0, 0.212), 0.1, 0.024, M_DARK, "Z", 24)
    prism("turret_body", [(-0.34, 0.22), (-0.02, 0.22), (0.03, 0.26), (0.0, 0.31), (-0.3, 0.31), (-0.34, 0.28)], 0.15, M_HULL, 0.006)
    for s in (1, -1):
        box("gun_mount", (-0.08, s * 0.1, 0.27), (0.14, 0.05, 0.06), M_HULL, 0.005)
        for dz in (0.285, 0.258):
            cyl("barrel", (0.08, s * 0.1, dz), 0.0065, 0.24, M_STEEL, "X", 10)
            cyl("muzzle", (0.2, s * 0.1, dz), 0.0095, 0.02, M_DARK, "X", 10)
        box("pack_frame", (-0.12, s * 0.165, 0.258), (0.3, 0.07, 0.1), M_HULL, 0.004)
        for col in (0.15, 0.182):
            for dz in (0.222, 0.258, 0.294):
                cyl("tube", (-0.06, s * col, dz), 0.0155, 0.32, M_HULL, "X", 14)
                cyl("tube_cap", (0.1, s * col, dz), 0.0125, 0.006, M_RED, "X", 12)
        box("turret_red", (-0.2, s * 0.076, 0.3), (0.18, 0.004, 0.012), M_RED, 0.0)
    cyl("track_radar", (0.035, 0, 0.29), 0.042, 0.018, M_STEEL, "X", 24, 0.003)
    box("sight", (-0.14, 0.04, 0.33), (0.05, 0.04, 0.04), M_DARK, 0.004)
    cyl("search_post", (-0.28, 0, 0.34), 0.016, 0.06, M_STEEL, "Z", 12)
    rbox("search_radar", (-0.28, 0, 0.395), (0.024, 0.17, 0.07), M_HULL, (0, math.radians(-15), 0), 0.004)
    rbox("search_face", (-0.267, 0, 0.398), (0.004, 0.16, 0.06), M_DARK, (0, math.radians(-15), 0))
    for y in (0.05, -0.05):
        cyl("whip", (-0.32, y, 0.45), 0.002, 0.26, M_STEEL, "Z", 6)
    shots = [("iso", (1.1, -1.25, 0.9), (0, 0, 0.18), 50), ("top", (0, 0, 3.2), None, 45), ("side", (0, -2.4, 0.3), (0, 0, 0.2), 50)]

elif kind == "sam":
    # агрегат за кабиной, платформа, рама с 4 контейнерами 2×2 по-походному (вдоль машины)
    box("power", (0.24, 0, 0.17), (0.09, W, 0.16), M_HULL, 0.006)
    box("rollbar", (0.3, 0, 0.29), (0.006, W * 0.8, 0.006), M_STEEL, 0.0)
    box("deck", (-0.15, 0, 0.12), (0.7, W, 0.04), M_HULL, 0.005)
    for s in (1, -1):
        for x in (-0.33, -0.08, 0.1):
            box("locker", (x, s * (W / 2 - 0.002), 0.11), (0.09, 0.008, 0.05), M_DARK, 0.0)
        box("red_band", (-0.15, s * W / 2, 0.142), (0.68, 0.004, 0.01), M_RED, 0.0)
        jack(-0.49, s * 0.12)
        jack(0.08, s * 0.13)
    L.group = "launcher"
    HX, HZ = -0.47, 0.155                 # шарнир подъёма — сзади
    L.pivots["launcher"] = (HX, 0, HZ)
    box("lift_beam", (-0.14, 0, 0.152), (0.64, 0.05, 0.014), M_DARK, 0.003)
    for s in (1, -1):
        rbox("rear_fork", (-0.48, s * 0.03, 0.27), (0.016, 0.012, 0.25), M_STEEL, (s * math.radians(-12), 0, 0), 0.002)
    box("rear_plate", (-0.47, 0, 0.22), (0.014, 0.06, 0.13), M_HULL, 0.003)
    R = 0.044
    for iy in (-1, 1):
        for iz in (0, 1):
            y, z = iy * 0.048, 0.207 + iz * 0.092
            cyl("canister", (-0.12, y, z), R, 0.7, M_HULL, "X", 24, 0.004)
            for k in range(6):
                cyl("canister_ring", (-0.42 + k * 0.12, y, z), R + 0.003, 0.012, M_DARK, "X", 24)
            cyl("cap_front", (0.233, y, z), R * 0.96, 0.008, M_DARK, "X", 24)
            cyl("cap_rear", (-0.473, y, z), R * 0.96, 0.008, M_DARK, "X", 24)
            cyl("cap_hub", (-0.48, y, z), 0.01, 0.01, M_STEEL, "X", 10)
            cyl("cap_red", (0.24, y, z), R * 0.35, 0.006, M_RED, "X", 14)
    box("top_band", (-0.12, 0, 0.346), (0.66, 0.02, 0.006), M_RED, 0.0)
    shots = [("iso", (1.1, -1.25, 0.9), (0, 0, 0.18), 50), ("top", (0, 0, 3.2), None, 45), ("side", (0, -2.4, 0.3), (0, 0, 0.2), 50)]

elif kind == "radar":
    # бронированный кунг с дверями и окошком, решётчатое ограждение по крыше, мачта сзади
    prism("van", [(-0.47, 0.1), (0.25, 0.1), (0.25, 0.27), (0.23, 0.29), (-0.45, 0.29), (-0.47, 0.27)], W, M_HULL, 0.006)
    cyl("spare", (0.26, -0.11, 0.165), 0.048, 0.04, M_TYRE, "Y", 18)
    for s in (1, -1):
        for x in (-0.36, -0.24, 0.0):
            box("door", (x, s * W / 2, 0.19), (0.08, 0.004, 0.13), M_DARK, 0.0)
        box("window", (-0.12, s * W / 2, 0.235), (0.04, 0.005, 0.03), M_GLASS, 0.0)
        box("red_band", (-0.11, s * W / 2, 0.115), (0.7, 0.004, 0.012), M_RED, 0.0)
        jack(-0.49, s * 0.12)
    box("rear_grille", (-0.48, 0, 0.2), (0.02, W * 0.8, 0.14), M_DARK, 0.0)
    # ограждение крыши: верхний поручень и косые раскосы
    zt, zb = 0.33, 0.29
    for s in (1, -1):
        tube("rail", [(-0.44, s * 0.13, zt), (0.22, s * 0.13, zt)], 0.003, M_STEEL)
        for i in range(11):
            x0 = -0.44 + i * 0.06
            tube("brace", [(x0, s * 0.13, zb), (x0 + 0.03, s * 0.13, zt), (x0 + 0.06, s * 0.13, zb)], 0.002, M_STEEL)
    tube("rail", [(0.22, 0.13, zt), (0.22, -0.13, zt)], 0.003, M_STEEL)
    tube("rail", [(-0.44, 0.13, zt), (-0.44, -0.13, zt)], 0.003, M_STEEL)
    box("roof_hood", (0.1, 0, 0.305), (0.18, 0.16, 0.03), M_HULL, 0.006)
    # телескопическая мачта с растяжками и фонарями
    mx, my = -0.41, 0.1
    cyl("mast", (mx, my, 0.47), 0.008, 0.36, M_STEEL, "Z", 10)
    cyl("mast_low", (mx, my, 0.36), 0.012, 0.14, M_STEEL, "Z", 10)
    cyl("mast_head", (mx, my, 0.655), 0.03, 0.01, M_DARK, "Z", 12)
    box("mast_box", (mx + 0.02, my, 0.635), (0.02, 0.016, 0.014), M_DARK, 0.0)
    for (dx, dy) in ((0.1, 0.0), (-0.03, -0.12), (0.05, 0.04)):
        tube("guy", [(mx, my, 0.5), (mx + dx, my + dy, 0.29)], 0.0018, M_STEEL)
    # поворотная антенная установка
    L.group = "antenna"
    L.pivots["antenna"] = (-0.12, 0, 0.29)
    cyl("pedestal", (-0.12, 0, 0.305), 0.045, 0.03, M_DARK, "Z", 20)
    box("yoke", (-0.12, 0, 0.335), (0.06, 0.12, 0.03), M_HULL, 0.004)
    box("cabinet", (-0.13, 0, 0.395), (0.07, 0.08, 0.1), M_HULL, 0.006)
    box("cabinet_red", (-0.094, 0, 0.42), (0.004, 0.06, 0.012), M_RED, 0.0)
    for s in (1, -1):
        box("dish_arm", (-0.125, s * 0.06, 0.39), (0.02, 0.04, 0.02), M_DARK, 0.0)
        dish("dish", (-0.11, s * 0.115, 0.39), 0.07, M_STEEL)
    cyl("top_post", (-0.13, 0, 0.455), 0.006, 0.02, M_DARK, "Z", 8)
    dish("dish_small", (-0.12, 0, 0.49), 0.034, M_STEEL)
    rbox("panel", (-0.075, 0, 0.345), (0.006, 0.13, 0.06), M_HULL, (0, math.radians(25), 0), 0.002)
    shots = [("iso", (1.1, -1.25, 1.0), (0, 0, 0.25), 50), ("top", (0, 0, 3.2), None, 45), ("side", (0, -2.4, 0.35), (0, 0, 0.25), 50)]

L.group = ""
build("ground_" + kind, OUT)
preview(OUT, shots)
print("DONE")
