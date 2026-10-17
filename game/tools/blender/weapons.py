"""Подвесное оружие по примерам владельца 16.10 (catalog/refs/aam_*, rockets): 3 ступени, отличаются
формой, длиной и деталями, а не только размером. «По мотивам»: без надписей, номеров и эмблем.
Запуск: python3 weapons.py <aam|rockets|flares|bombs> <1|2|3|evo> <out_dir>
Единицы как у WeaponModels: длина 1 вдоль +X (нос вперёд), центр корпуса в начале координат,
верх (+Z в Blender, +Y в Godot) — сторона крепления к пилону.
  aam 1 — ракета средней дальности: гладкий светлый корпус, крестообразные крылья посередине, рули у сопла;
  aam 2 — ракета ближнего боя: тёмный нос со стеклянной головкой («глаз»), передние треугольные рули,
          тонкий корпус с поясками, задние рули с роллеронами;
  aam 3 — тяжёлая: гранёный корпус, скошенный нос с окном головки, большие крылья, сбрасываемый
          ускоритель с медным кольцом;
  rockets 1 — короткий блок с открытыми трубами; 2 — длинный блок с конусом-обтекателем из лепестков;
  rockets 3 — спаренные блоки с обтекателями на общей балке. У всех сверху балка-держатель с замками.
Эволюции (Т-6, plan-after-review раздел 3: эволюция — совсем другая модель, не «ступень 4»):
  aam evo     «Шмель» — толстая ракета-носитель, вокруг корпуса 4 боевые части в открытых отсеках, жёлтые полосы;
  rockets evo «Ливень» — веерная пусковая: три расходящихся пакета труб на поворотной раме;
  flares evo  «Салют» — на спине фюзеляжа: поворотная платформа и два барабана с цветными зарядами
              (основание на z = 0, всё выше — как у турелей);
  bombs evo   «Бабушкин ковёр» — планка-раздатчик под фюзеляжем, ряд из 8 бомб поперёк полёта.
Т-5 (plan-after-review 3.4–3.5):
  bombs 1 — 2 бомбы рядом на балке, крестовое оперение с кольцом; 2 — 4 бомбы попарно на кассетном держателе;
  bombs 3 — крупная кассета: линии створок, оперение с кольцом, раскрывающиеся стабилизаторы;
  flares 1 / 2 — кассеты-«соты», встроенные в обшивку (основание на z = 0, ячейки сверху), 2 — крупнее;
  flares 3 — контейнер ловушек на законцовке крыла (центр на оси, симметричный — на обе консоли)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L

kind, tier, OUT = sys.argv[-3], sys.argv[-2], sys.argv[-1]
EVO = tier == "evo"
tier = 0 if EVO else int(tier)
L.reset()
M_WHITE = mat("white", (0.72, 0.73, 0.74), 0.3, 0.45)
M_DARK = mat("dark", (0.08, 0.08, 0.09), 0.4, 0.55)
M_STEEL = mat("steel", (0.38, 0.39, 0.4), 0.7, 0.35)
M_OLIVE = mat("olive", (0.3, 0.33, 0.26), 0.25, 0.6)
M_GLASS = mat("glass", (0.15, 0.25, 0.3), 0.6, 0.08)
M_BAND = mat("band", (0.62, 0.45, 0.12), 0.3, 0.5)
M_COPPER = mat("copper", (0.6, 0.3, 0.15), 0.8, 0.35)
M_YELLOW = mat("yellow", (0.85, 0.65, 0.05), 0.2, 0.5)
M_RED = mat("charge_red", (0.8, 0.12, 0.08), 0.1, 0.4)
M_GREEN = mat("charge_green", (0.1, 0.6, 0.2), 0.1, 0.4)
M_BLUE = mat("charge_blue", (0.15, 0.35, 0.85), 0.1, 0.4)


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


def sphere(name, c, r, sc, m, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m)


def small_bomb(x, y, z, r, ln, m_body):
    """Бомба носом вперёд: корпус, оживальный нос, крестовое оперение с кольцом"""
    cyl("b_body", (x, y, z), r, ln * 0.6, m_body, "X", 16)
    sphere("b_nose", (x + ln * 0.3, y, z), r, (1.9, 1, 1), m_body, 16)
    cone("b_tail", x - ln * 0.3, x - ln * 0.45, r, r * 0.4, m_body, 16).location.y = y
    bpy.context.object.location.z = z
    for k in range(2):
        ob = box("b_fin", (0, 0, 0), (ln * 0.12, 0.004, r * 2.6), M_DARK, 0.0)
        sel(ob)
        ob.rotation_euler = (math.pi / 4 + k * math.pi / 2, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        ob.location = (x - ln * 0.44, y, z)
    cyl("b_ring", (x - ln * 0.47, y, z), r * 1.25, ln * 0.05, M_DARK, "X", 16)


if EVO and kind == "aam":
    # «Шмель»: носитель вдвое толще обычной ракеты, 4 отсека с боевыми частями-«пулями»
    R = 0.07
    cyl("body", (-0.05, 0, 0), R, 0.74, M_WHITE, "X", 24)
    sphere("nose", (0.32, 0, 0), R, (2.4, 1, 1), M_WHITE, 24)
    cyl("nozzle", (-0.43, 0, 0), R * 0.75, 0.03, M_DARK, "X", 20)
    for x in (0.26, 0.2, -0.3, -0.36):
        cyl("stripe", (x, 0, 0), R * 1.02, 0.03, M_YELLOW, "X", 24)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        cy, cz = -math.sin(a) * R * 0.95, math.cos(a) * R * 0.95
        # отсек: тёмная выемка вдоль корпуса, в ней боевая часть с жёлтым носом
        ob = box("bay", (-0.04, cy, cz), (0.34, R * 0.75, R * 0.75), M_DARK, 0.004)
        ob.rotation_euler = (a, 0, 0)
        cyl("sub_body", (-0.06, cy * 1.12, cz * 1.12), R * 0.3, 0.22, M_STEEL, "X", 12)
        sphere("sub_nose", (0.06, cy * 1.12, cz * 1.12), R * 0.3, (2.2, 1, 1), M_YELLOW, 12)
        fin("tail", [(-0.46, R * 0.8), (-0.33, R * 0.8), (-0.4, R + 0.06), (-0.46, R + 0.06)], 0.006, a, M_WHITE)
    lugs([0.12, -0.22], R)

elif EVO and kind == "rockets":
    # «Ливень»: поворотная рама с тремя пакетами труб веером (центр прямо, бока ±22°)
    cyl("turntable", (0.0, 0, 0.2), 0.16, 0.04, M_STEEL, "Z", 28, 0.004)
    cyl("turntable_ring", (0.0, 0, 0.17), 0.18, 0.015, M_DARK, "Z", 28)
    box("frame", (-0.02, 0, 0.12), (0.3, 0.62, 0.05), M_OLIVE, 0.008)
    for ang, y in ((0.0, 0.0), (0.38, 0.27), (-0.38, -0.27)):
        L.parts_before = len(L.parts)
        R, ln = 0.085, 0.62
        cyl("pack", (0, 0, 0), R, ln, M_OLIVE, "X", 20, 0.004)
        for x in (-ln / 2 + 0.05, ln / 2 - 0.05):
            cyl("pack_band", (x, 0, 0), R * 1.04, 0.02, M_DARK, "X", 20)
        cyl("pack_face", (ln / 2 + 0.002, 0, 0), R * 0.92, 0.005, M_DARK, "X", 20)
        for rr, n in ((0.0, 1), (R * 0.52, 6)):
            for i in range(n):
                t = 2 * math.pi * i / n
                cyl("tube", (ln / 2 + 0.005, math.cos(t) * rr, math.sin(t) * rr), R * 0.2, 0.008, M_STEEL, "X", 10)
        # повернуть и сдвинуть всё, что относится к пакету
        for ob in L.parts[L.parts_before:]:
            sel(ob)
            ob.rotation_euler = (0, 0, ang)
            bpy.ops.object.transform_apply(rotation=True)
            ob.location.y += y
            ob.location.x += 0.05 - abs(y) * 0.25
        box("arm", (-0.05 - abs(y) * 0.2, y * 0.6, 0.06), (0.08, 0.04 + abs(y) * 0.5, 0.05), M_STEEL, 0.004)

elif EVO and kind == "flares":
    # «Салют»: на спине; поворотная платформа, два барабана-«фейерверка» с цветными зарядами
    cyl("base", (0, 0, 0.02), 0.2, 0.04, M_STEEL, "Z", 28, 0.004)
    cyl("base_ring", (0, 0, 0.045), 0.17, 0.012, M_DARK, "Z", 28)
    box("yoke", (0, 0, 0.1), (0.14, 0.42, 0.06), M_OLIVE, 0.008)
    cols = [M_RED, M_GREEN, M_YELLOW, M_BLUE]
    for y in (0.19, -0.19):
        L.parts_before = len(L.parts)
        cyl("drum", (0, 0, 0), 0.11, 0.36, M_OLIVE, "X", 24, 0.004)
        for x in (-0.15, 0.15):
            cyl("drum_band", (x, 0, 0), 0.115, 0.02, M_DARK, "X", 24)
        for i in range(8):
            t = 2 * math.pi * i / 8
            r = 0.072
            cyl("cell", (0.181, math.cos(t) * r, math.sin(t) * r), 0.026, 0.006, M_DARK, "X", 12)
            sphere("charge", (0.186, math.cos(t) * r, math.sin(t) * r), 0.022, (0.5, 1, 1), cols[i % 4], 10)
        cyl("hub", (0.185, 0, 0), 0.025, 0.012, M_STEEL, "X", 12)
        for ob in L.parts[L.parts_before:]:
            sel(ob)
            ob.rotation_euler = (0, -0.5, 0)     # барабаны смотрят вперёд-вверх
            bpy.ops.object.transform_apply(rotation=True)
            ob.location.y += y
            ob.location.z += 0.2
        cyl("trunnion", (0, y * 0.75, 0.2), 0.03, 0.12, M_STEEL, "Y", 12)

elif EVO and kind == "bombs":
    # «Бабушкин ковёр»: длинная планка поперёк полёта, под ней 8 бомб в ряд
    box("bar", (0, 0, 0.13), (0.22, 1.7, 0.05), M_STEEL, 0.006)
    box("bar_top", (0, 0, 0.16), (0.12, 1.6, 0.012), M_DARK, 0.0)
    box("mount", (0, 0, 0.2), (0.18, 0.18, 0.06), M_DARK, 0.006)
    for i in range(8):
        y = (i - 3.5) * 0.21
        box("rack", (0, y, 0.09), (0.05, 0.03, 0.04), M_DARK, 0.0)
        small_bomb(0.0, y, 0.02, 0.055, 0.5, M_OLIVE)

elif kind == "aam" and tier == 1:
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

elif kind == "bombs":
    # Т-5: кассетные бомбы; верх (z > 0) — к пилону, оперение крестом с кольцом
    if tier == 1:
        # 2 бомбы рядом на балке
        box("beam", (0, 0, 0.13), (0.62, 0.3, 0.04), M_STEEL, 0.004)
        box("beam_top", (0, 0, 0.155), (0.5, 0.1, 0.01), M_DARK, 0.0)
        for y in (0.11, -0.11):
            box("rack", (0, y, 0.09), (0.2, 0.03, 0.05), M_DARK, 0.0)
            small_bomb(0.02, y, 0.0, 0.085, 0.82, M_OLIVE)
            cyl("band", (0.14, y, 0.0), 0.087, 0.03, M_BAND, "X", 16)
    elif tier == 2:
        # кассетный держатель: 4 бомбы попарно друг за другом
        box("holder", (0, 0, 0.14), (0.95, 0.12, 0.05), M_STEEL, 0.004)
        box("holder_top", (0, 0, 0.17), (0.7, 0.07, 0.012), M_DARK, 0.0)
        for x in (0.23, -0.23):
            box("cross", (x, 0, 0.1), (0.07, 0.3, 0.03), M_DARK, 0.0)
            for y in (0.11, -0.11):
                small_bomb(x, y, 0.0, 0.07, 0.46, M_OLIVE)
                cyl("band", (x + 0.08, y, 0.0), 0.072, 0.02, M_BAND, "X", 16)
    else:
        # крупная кассета: створки по бокам, крестовое оперение с кольцом, раскрывающиеся стабилизаторы
        R = 0.15
        cyl("body", (-0.03, 0, 0), R, 0.62, M_OLIVE, "X", 28, 0.004)
        sphere("nose", (0.28, 0, 0), R, (1.6, 1, 1), M_OLIVE, 28)
        cone("tail", -0.34, -0.46, R, R * 0.45, M_OLIVE, 28)
        for x in (0.2, -0.26):
            cyl("seam", (x, 0, 0), R * 1.01, 0.01, M_DARK, "X", 28)
        for y in (1, -1):   # линии створок вдоль корпуса
            box("door_line", (-0.03, y * R * 0.99, 0.0), (0.46, 0.006, 0.012), M_DARK, 0.0)
            box("door_line2", (-0.03, y * R * 0.7, -R * 0.71), (0.46, 0.006, 0.012), M_DARK, 0.0)
        cyl("nose_band", (0.24, 0, 0), R * 1.02, 0.025, M_BAND, "X", 28)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            fin("tail_fin", [(-0.5, R * 0.4), (-0.36, R * 0.4), (-0.42, R + 0.06), (-0.5, R + 0.06)], 0.008, a, M_DARK)
            fin("mid_fin", [(-0.12, R * 0.9), (0.0, R * 0.9), (-0.04, R + 0.035), (-0.12, R + 0.035)], 0.006, a + math.pi / 4, M_DARK)
        cyl("ring", (-0.48, 0, 0), R + 0.065, 0.05, M_DARK, "X", 28)
        cyl("ring_in", (-0.48, 0, 0), R + 0.05, 0.052, M_OLIVE, "X", 28)
        lugs([0.12, -0.18], R)

elif kind == "flares":
    # Т-5: кассеты ловушек встроены в обшивку (не на пилоне): «соты» — основание на z = 0, ячейки сверху.
    # Ступень 3 — подвесной контейнер на законцовке крыла (центр на оси, как у ракет).
    def cassette(ln, w, rows, cols):
        box("plate", (0, 0, 0.022), (ln, w, 0.044), M_OLIVE, 0.006)
        prism("ramp", [(ln / 2, 0.0), (ln / 2 + 0.12, 0.0), (ln / 2, 0.044)], w * 0.96, M_OLIVE, 0.0)
        box("frame", (0, 0, 0.046), (ln * 0.92, w * 0.86, 0.006), M_DARK, 0.0)
        for i in range(cols):
            for j in range(rows):
                x = (i - (cols - 1) / 2) * ln * 0.86 / cols
                y = (j - (rows - 1) / 2) * w * 0.8 / rows
                cyl("cell", (x, y, 0.05), w * 0.3 / rows, 0.006, M_DARK, "Z", 10)
                cyl("cap", (x, y, 0.052), w * 0.22 / rows, 0.006, M_COPPER, "Z", 10)
    if tier == 1:
        cassette(0.55, 0.3, 3, 7)
    elif tier == 2:
        cassette(0.75, 0.4, 4, 9)
    else:
        R = 0.075
        cyl("pod", (-0.06, 0, 0), R, 0.7, M_OLIVE, "X", 24, 0.003)
        sphere("pod_nose", (0.29, 0, 0), R, (2.2, 1, 1), M_OLIVE, 24)
        cyl("pod_rear", (-0.412, 0, 0), R * 0.94, 0.006, M_DARK, "X", 24)
        for rr, n in ((0.0, 1), (R * 0.55, 6)):
            for i in range(n):
                a = 2 * math.pi * i / n
                cyl("pod_cell", (-0.416, math.cos(a) * rr, math.sin(a) * rr), R * 0.16, 0.006, M_COPPER, "X", 10)
        for x in (0.15, -0.3):
            cyl("pod_band", (x, 0, 0), R * 1.03, 0.015, M_DARK, "X", 24)

L.group = ""
name = "%s_evo" % kind if EVO else "%s_%d" % (kind, tier)
root = build(name, OUT)
root.location.z += 0.35   # для предпросмотра — над полом (в .glb центр остаётся в начале координат)
if "nopreview" not in sys.argv:
    preview(OUT, [("iso", (1.3, -1.5, 1.25), (0, 0, 0.35), 60), ("side", (0, -2.4, 0.35), (0, 0, 0.35), 50)])
print("DONE")
