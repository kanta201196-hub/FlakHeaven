"""Подвесное оружие по примерам владельца 16.10 (catalog/refs/aam_*, rockets): 3 ступени, отличаются
формой, длиной и деталями, а не только размером. «По мотивам»: без надписей, номеров и эмблем.
Запуск: python3 weapons.py <aam|rockets|flares|bombs|bombdrop|arm> <1|2|3|evo> <out_dir>
  arm 1 — Т-8: противорадарная ракета ведомого «Ласка» (длиннее В-В, длинные узкие крылья, тёмный обтекатель)
Единицы как у WeaponModels: длина 1 вдоль +X (нос вперёд), центр корпуса в начале координат,
верх (+Z в Blender, +Y в Godot) — сторона крепления к пилону.
  aam 1 — ракета средней дальности: гладкий светлый корпус, крестообразные крылья посередине, рули у сопла;
  aam 2 — ракета ближнего боя: тёмный нос со стеклянной головкой («глаз»), передние треугольные рули,
          тонкий корпус с поясками, задние рули с роллеронами;
  aam 3 — тяжёлая: гранёный корпус, скошенный нос с окном головки, большие крылья, сбрасываемый
          ускоритель с медным кольцом;
  rockets 1 — короткий блок с открытыми трубами; 2 — длинный блок, обтекатель из лепестков с пусковыми
  отверстиями, сзади ниша с трубами (фото rockets_1); 3 — один крупный блок с глубокой нишей и пакетом
  из 20 труб, тупой обтекатель (фото rockets_3; тест 3.5-s3: не спарка «слипшихся бочек»).
Эволюции (Т-6, plan-after-review раздел 3: эволюция — совсем другая модель, не «ступень 4»):
  aam evo     «Шмель» — толстая ракета-носитель, вокруг корпуса 4 боевые части в открытых отсеках, жёлтые полосы;
  rockets evo «Ливень» — веерная пусковая: три расходящихся пакета труб на поворотной раме;
  flares evo  «Салют» — на спине фюзеляжа: поворотная пусковая и веер из трёх кассет ловушек
              (тот же вид, что у ступеней; основание на z = 0, всё выше — как у турелей);
  bombs evo   «Бабушкин ковёр» — планка-раздатчик под фюзеляжем, ряд из 8 бомб поперёк полёта.
Т-5 (plan-after-review 3.4–3.5):
  bombs 1 — 2 бомбы рядом на балке; 2 — 4 бомбы попарно на кассетном держателе; у обеих открытый хвост,
          крестовое оперение и сквозной коробчатый стабилизатор (тест 3.5-s4, п. 4: без колпачков и колец-дисков);
  bombs 3 — крупная кассета: линии створок, крестовое оперение без кольца, раскрывающиеся стабилизаторы;
  flares 1 / 2 — кассеты ловушек, встроенные в обшивку (основание на z = 0, ячейки сверху), 2 — крупнее;
  flares 3 — контейнер на законцовке крыла с такими же кассетами сверху и снизу (центр на оси, симметричный).
  bombdrop 1 / 2 / 3 — одна бомба ступени для падения в бою (тест 3.5-s4, п. 10), длина 1."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
from mathutils import Matrix, Vector
import bmesh
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
M_RED = mat("mark_red", (0.62, 0.1, 0.07), 0.1, 0.5)
# тест 3.5-s4 (п. 3): одна линия ловушек на всех ступенях — серо-оливковая кассета, латунные торцы патронов
M_CASE = mat("flare_case", (0.25, 0.27, 0.23), 0.35, 0.55)
M_BRASS = mat("brass", (0.72, 0.53, 0.22), 0.85, 0.3)
# тест 3.5-s4 (п. 10): бомбы — тёмно-оливковые (светлый «олив» на солнце в бою выглядел белыми таблетками)
M_BOMB = mat("bomb_olive", (0.11, 0.13, 0.075), 0.2, 0.55)


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


def shoe(x0, x1, zb, zt):
    """Колодка пускового рельса: от корпуса ракеты до верха габарита (кончиков рулей), чтобы рельс пилона
    лежал на ней, а не висел над корпусом (тест 3.5-s3: «ракеты висят в воздухе без связи с крылом»)"""
    box("shoe", ((x0 + x1) / 2, 0, (zb + zt) / 2), (x1 - x0, 0.016, zt - zb), M_STEEL, 0.002)
    for x in (x0 + 0.03, x1 - 0.03):
        box("shoe_hook", (x, 0, zt - 0.004), (0.03, 0.022, 0.008), M_DARK, 0.0)


def sphere(name, c, r, sc, m, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m)


def open_cone(name, x0, x1, r0, r1, m, verts=16, wall=0.004):
    """Конус-обтекатель хвоста без торцов (тест 3.5-s4, п. 4: хвост не закрыт заглушкой — сквозь срез видна
    полость), стенка — модификатор толщины"""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=abs(x1 - x0), end_fill_type="NOTHING",
                                    location=((x0 + x1) / 2, 0, 0))
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = (0, math.pi / 2 if x1 > x0 else -math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    md = ob.modifiers.new("sol", "SOLIDIFY")
    md.thickness = wall
    md.offset = -1
    return finish(ob, m)


def tail_unit(x, y, z, r, ln, m_body, box_fin=True):
    """Хвост авиабомбы по фото (тест 3.5-s4, п. 4): сужающийся конус с открытым срезом, крестовое оперение
    из 4 перьев «иксом» и (box_fin) открытый коробчатый стабилизатор — 4 тонкие пластины, соединяющие концы
    перьев: спереди и сзади он сквозной, через него видно конус. Никаких колец-дисков и заглушек."""
    xa, xb = x - ln * 0.28, x - ln * 0.5          # конус хвоста: от корпуса к срезу
    rb = r * 0.42
    ob = open_cone("b_tail", xa, xb, r, rb, m_body, 16, max(r * 0.06, 0.002))
    ob.location = (ob.location.x, y, z)
    # тёмная полость глубоко внутри среза — видно, что хвост пустой
    ob = cyl("b_tail_in", (0, 0, 0), rb * 0.8, ln * 0.08, M_DARK, "X", 12)
    ob.location = (xb + ln * 0.07, y, z)
    s_tip = r * 1.32
    c0, c1 = xb - ln * 0.02, xa - ln * 0.02         # хорда пера у корня
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        # перо: корень на конусе, передняя кромка скошена, задняя — прямо у среза
        ob = fin("b_fin", [(c0, rb * 0.8), (c1, r * 0.85), (c1 - ln * 0.06, s_tip), (c0, s_tip)], max(r * 0.05, 0.0025), a, M_DARK)
        ob.location.y += y
        ob.location.z += z
    if box_fin:
        d = s_tip / math.sqrt(2.0)
        w = s_tip * math.sqrt(2.0)
        ch = ln * 0.1
        xc = c0 + ch * 0.5
        t = max(r * 0.04, 0.002)
        for sz in (1, -1):
            box("b_box", (xc, y, z + sz * d), (ch, w, t), M_DARK, 0.0)
            box("b_box", (xc, y + sz * d, z), (ch, t, w), M_DARK, 0.0)


def small_bomb(x, y, z, r, ln, m_body):
    """Бомба носом вперёд: корпус, оживальный нос, открытый хвост с крестовым и коробчатым оперением"""
    cyl("b_body", (x, y, z), r, ln * 0.56, m_body, "X", 16)
    sphere("b_nose", (x + ln * 0.28, y, z), r, (1.9, 1, 1), m_body, 16)
    box("b_fuze", (x + ln * 0.28 + r * 1.88, y, z), (r * 0.12, r * 0.22, r * 0.22), M_STEEL, 0.0)   # взрыватель в носу
    tail_unit(x, y, z, r, ln, m_body)


def rot_world(obs, axis, ang):
    """Повернуть детали вокруг начала координат (а не каждую вокруг своей точки) и запечь поворот"""
    rm = Matrix.Rotation(ang, 4, axis)
    for ob in obs:
        ob.matrix_world = rm @ ob.matrix_world
        sel(ob)
        bpy.ops.object.transform_apply(rotation=True)


def cassette_block(ln, w, h, rows, cols, ramp=False):
    """Кассета ловушек — общий вид всех ступеней (тест 3.5-s4, п. 3): серо-оливковый корпус с фаской,
    тёмная рамка, ряды ячеек с одинаковыми латунными торцами патронов; центр в начале координат,
    ячейки на верхней грани (z = +h/2)"""
    box("case", (0, 0, 0), (ln, w, h), M_CASE, min(h, w) * 0.12)
    if ramp:   # обтекатель спереди — кассета встроена в обшивку
        prism("ramp", [(ln / 2, -h / 2), (ln / 2 + h * 2.6, -h / 2), (ln / 2, h / 2)], w * 0.96, M_CASE, 0.0)
    box("frame", (0, 0, h / 2 + 0.001), (ln * 0.93, w * 0.88, 0.004), M_DARK, 0.0)
    for i in range(cols):
        for j in range(rows):
            x = (i - (cols - 1) / 2) * ln * 0.86 / cols
            yy = (j - (rows - 1) / 2) * w * 0.8 / rows
            cyl("cell", (x, yy, h / 2 + 0.003), w * 0.34 / rows, 0.004, M_DARK, "Z", 12)
            cyl("cap", (x, yy, h / 2 + 0.005), w * 0.25 / rows, 0.004, M_BRASS, "Z", 12)
            cyl("primer", (x, yy, h / 2 + 0.0075), w * 0.07 / rows, 0.002, M_STEEL, "Z", 8)
    for xx in (ln * 0.44, -ln * 0.44):   # красная маркировка у торцов
        box("mark", (xx, 0, 0), (0.008, w * 1.004, h * 1.004), M_RED, 0.0)


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
    # «Салют» (тест 3.5-s4, п. 3: развитие той же кассеты, без «дискошаров»): на спине поворотная пусковая,
    # на ней веером три кассеты ловушек — тот же серо-оливковый корпус и латунные торцы, что у ступеней 1–3,
    # ячейками вверх-назад. Красные полоски — только маркировка. Основание на z = 0, всё выше — как у турелей.
    cyl("base", (0, 0, 0.02), 0.2, 0.04, M_STEEL, "Z", 28, 0.004)
    cyl("base_ring", (0, 0, 0.045), 0.17, 0.012, M_DARK, "Z", 28)
    box("yoke", (0, 0, 0.085), (0.16, 0.5, 0.05), M_CASE, 0.008)
    for y in (0.21, -0.21):
        box("cheek", (0, y, 0.13), (0.12, 0.03, 0.11), M_CASE, 0.006)
    cyl("trunnion", (0, 0, 0.16), 0.022, 0.48, M_STEEL, "Y", 12)
    for y, splay in ((0.0, 0.0), (0.175, -0.28), (-0.175, 0.28)):
        L.parts_before = len(L.parts)
        cassette_block(0.36, 0.13, 0.075, 3, 6)
        blk = L.parts[L.parts_before:]
        rot_world(blk, "Y", -0.6)    # ячейки смотрят вверх-назад
        rot_world(blk, "X", splay)   # боковые — веером наружу
        for ob in blk:
            ob.location.y += y
            ob.location.z += 0.2 + abs(y) * 0.05
            ob.location.x -= 0.02

elif EVO and kind == "bombs":
    # «Бабушкин ковёр»: длинная планка поперёк полёта, под ней 8 бомб в ряд
    box("bar", (0, 0, 0.13), (0.22, 1.7, 0.05), M_STEEL, 0.006)
    box("bar_top", (0, 0, 0.16), (0.12, 1.6, 0.012), M_DARK, 0.0)
    box("mount", (0, 0, 0.2), (0.18, 0.18, 0.06), M_DARK, 0.006)
    for i in range(8):
        y = (i - 3.5) * 0.21
        box("rack", (0, y, 0.09), (0.05, 0.03, 0.04), M_DARK, 0.0)
        small_bomb(0.0, y, 0.02, 0.055, 0.5, M_BOMB)

elif kind == "aam" and tier == 1:
    R = 0.034
    cyl("body", (-0.07, 0, 0), R, 0.84, M_WHITE, "X", 24)
    cone("nose", 0.35, 0.5, R, 0.008, M_WHITE)
    cyl("nozzle", (-0.495, 0, 0), R * 0.8, 0.012, M_DARK, "X", 20)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        fin("wing", [(-0.1, R * 0.8), (0.06, R * 0.8), (0.02, R + 0.05), (-0.08, R + 0.05)], 0.005, a, M_WHITE)
        fin("tail", [(-0.48, R * 0.8), (-0.37, R * 0.8), (-0.42, R + 0.045), (-0.48, R + 0.045)], 0.005, a, M_WHITE)
    shoe(-0.22, 0.16, R * 0.85, 0.062)

elif kind == "arm":
    # Т-8: противорадарная ракета «Ласки» — длиннее и толще В-В, длинные узкие крылья посередине,
    # тёмный радиопрозрачный обтекатель головки, крестовые рули у сопла
    R = 0.04
    cyl("body", (-0.06, 0, 0), R, 0.8, M_WHITE, "X", 24)
    cone("nose", 0.34, 0.5, R, 0.006, M_DARK)
    cyl("nose_band", (0.33, 0, 0), R * 1.02, 0.02, M_BAND, "X", 24)
    cyl("nozzle", (-0.465, 0, 0), R * 0.8, 0.012, M_DARK, "X", 20)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        fin("wing", [(-0.2, R * 0.8), (0.12, R * 0.8), (0.06, R + 0.035), (-0.18, R + 0.035)], 0.005, a, M_WHITE)
        fin("tail", [(-0.46, R * 0.8), (-0.34, R * 0.8), (-0.41, R + 0.05), (-0.46, R + 0.05)], 0.005, a, M_WHITE)
    shoe(-0.24, 0.18, R * 0.85, 0.068)

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
    shoe(-0.24, 0.14, R * 0.85, 0.056)

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
    shoe(-0.24, 0.19, R * 0.9, 0.08)

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

    def petal_cone(x0, x1, r0, n, holes):
        """Обтекатель из n лепестков с тёмными щелями между ними и пусковыми отверстиями на лепестках"""
        cone("petal_core", x0, x1 - 0.01, r0 * 0.9, r0 * 0.05, M_DARK, 24)
        me = bpy.data.meshes.new("petals")
        bm = bmesh.new()
        K, M = 6, 5
        for k in range(n):
            a0 = 2 * math.pi * k / n
            h = math.pi / n * 0.8
            grid = []
            for i in range(K + 1):
                t = i / K
                x = x0 + (x1 - x0) * t
                r = r0 * (1 - t) + r0 * 0.04 * t
                grid.append([bm.verts.new((x, math.cos(a0 - h + 2 * h * j / M) * r, math.sin(a0 - h + 2 * h * j / M) * r))
                             for j in range(M + 1)])
            for i in range(K):
                for j in range(M):
                    bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("petals", me)
        bpy.context.scene.collection.objects.link(ob)
        md = ob.modifiers.new("sol", "SOLIDIFY")
        md.thickness = 0.006
        finish(ob, M_OLIVE)
        slant = Vector((x1 - x0, 0, -r0))
        for k in range(n):
            a0 = 2 * math.pi * k / n
            rad = Vector((0, math.cos(a0), math.sin(a0)))
            u = (Vector((x1 - x0, 0, 0)) - rad * r0 * 0.96).normalized()
            w = rad.cross(u).normalized()
            nn = u.cross(w).normalized()
            for hi in range(holes):
                t = 0.16 + 0.34 * hi
                c = Vector((x0 + (x1 - x0) * t, 0, 0)) + rad * (r0 * (1 - t) + r0 * 0.04 * t)
                ln = (x1 - x0) * (0.17 if holes > 1 else 0.3)
                bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=1)
                hole = bpy.context.object
                hole.name = "launch_hole"
                hole.scale = (ln * 0.85, r0 * (1 - t) * 0.13, 0.0035)
                bpy.ops.object.transform_apply(scale=True)
                hole.matrix_world = Matrix((u, w, nn)).transposed().to_4x4() @ Matrix.Identity(4)
                hole.location = c
                bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
                finish(hole, M_DARK)

    def pod_ref(x0, x1, x2, R, depth, rings, holes, perf_rows):
        """Блок по фото: корпус x0…x1, обтекатель x1…x2; сзади открытая ниша глубиной depth с трубами"""
        cyl("pod", ((x0 + depth + x1) / 2, 0, 0), R, x1 - x0 - depth, M_OLIVE, "X", 32, 0.003)
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=R, depth=depth + 0.004, end_fill_type="NOTHING",
                                            location=(x0 + depth / 2, 0, 0), rotation=(0, math.pi / 2, 0))
        lip = bpy.context.object
        lip.name = "pod_lip"
        bpy.ops.object.transform_apply(rotation=True)
        md = lip.modifiers.new("sol", "SOLIDIFY")
        md.thickness = R * 0.08
        md.offset = -1
        finish(lip, M_OLIVE)
        cyl("cavity", (x0 + depth * 0.5, 0, 0), R * 0.93, depth, M_DARK, "X", 32)
        for rr, n in rings:
            for i in range(n):
                a = 2 * math.pi * i / n + (0.3 if n > 7 else 0.0)
                y, z = math.cos(a) * rr, math.sin(a) * rr
                cyl("tube", (x0 + depth * 0.45, y, z), R * 0.12, depth * 0.9, M_STEEL, "X", 12)
                cyl("bore", (x0 + depth * 0.45 - 0.002, y, z), R * 0.085, depth * 0.9, M_DARK, "X", 10)
        for x in (x0 + depth + 0.03, (x0 + x1) / 2 + 0.05, x1 - 0.02):
            cyl("seam", (x, 0, 0), R * 1.008, 0.006, M_DARK, "X", 32)
        for row in range(perf_rows):   # перфорация у заднего среза, как на фото
            for i in range(26):
                a = 2 * math.pi * (i + 0.5 * row) / 26
                if math.sin(a) > 0.55:
                    continue   # сверху — пилон
                bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=R * 0.03,
                                                     location=(x0 + 0.02 + 0.022 * row, math.cos(a) * R, math.sin(a) * R))
                finish(bpy.context.object, M_DARK)
        petal_cone(x1, x2, R * 0.98, 8, holes)

    def pylon(x0, x1, R):
        """Балка-держатель по фото: скосы на концах, замки, упоры к блоку"""
        z0 = R + 0.012
        prism("pylon", [(x0, z0), (x1, z0), (x1 - 0.05, z0 + 0.07), (x0 + 0.1, z0 + 0.07)], 0.05, M_OLIVE, 0.004)
        box("pylon_rail", ((x0 + x1) / 2, 0, z0 + 0.072), ((x1 - x0) * 0.6, 0.03, 0.008), M_DARK, 0.0)
        for x in (x0 + 0.13, x1 - 0.12):
            cyl("hook", (x, 0, z0 + 0.08), 0.01, 0.03, M_STEEL, "Z", 10)
        for x in (x0 + 0.15, x1 - 0.15):
            for y in (1, -1):
                tube("sway", [(x, y * 0.02, z0 + 0.01), (x, y * R * 0.45, R * 0.9)], 0.008, M_STEEL)
            box("latch", (x + 0.06, 0, z0 - 0.004), (0.04, 0.04, 0.014), M_DARK, 0.002)

    if tier == 1:
        R = 0.15
        pod(0, -0.36, 0.36, R, 7, False)
        beam(-0.32, 0.32, R + 0.04, 0.07)
        for x in (-0.18, 0.0, 0.18):
            box("latch", (x, 0, R + 0.012), (0.05, 0.05, 0.025), M_DARK, 0.002)
    elif tier == 2:
        # по фото rockets_1: длинный блок, обтекатель из лепестков с пусковыми отверстиями, сзади — ниша с трубами
        R = 0.15
        pod_ref(-0.48, 0.2, 0.5, R, 0.06, [(0.0, 1), (R * 0.42, 6), (R * 0.76, 9)], 2, 1)
        pylon(-0.4, 0.14, R)
    else:
        # по фото rockets_3: один крупный блок (не спарка), глубокая ниша сзади с пакетом труб, тупой обтекатель
        R = 0.2
        pod_ref(-0.5, 0.32, 0.5, R, 0.1, [(0.0, 1), (R * 0.36, 7), (R * 0.68, 12)], 2, 2)
        pylon(-0.38, 0.2, R)
        for x in (-0.22, 0.12):   # бандажи
            cyl("band", (x, 0, 0), R * 1.02, 0.02, M_STEEL, "X", 32)

elif kind == "bombs":
    # Т-5: кассетные бомбы; верх (z > 0) — к пилону; хвост открытый, оперение крестом с коробчатым стабилизатором
    if tier == 1:
        # 2 бомбы рядом на балке
        box("beam", (0, 0, 0.13), (0.62, 0.3, 0.04), M_STEEL, 0.004)
        box("beam_top", (0, 0, 0.155), (0.5, 0.1, 0.01), M_DARK, 0.0)
        for y in (0.11, -0.11):
            box("rack", (0, y, 0.09), (0.2, 0.03, 0.05), M_DARK, 0.0)
            small_bomb(0.02, y, 0.0, 0.085, 0.82, M_BOMB)
            cyl("band", (0.14, y, 0.0), 0.087, 0.03, M_BAND, "X", 16)
    elif tier == 2:
        # кассетный держатель: 4 бомбы попарно друг за другом
        box("holder", (0, 0, 0.14), (0.95, 0.12, 0.05), M_STEEL, 0.004)
        box("holder_top", (0, 0, 0.17), (0.7, 0.07, 0.012), M_DARK, 0.0)
        for x in (0.23, -0.23):
            box("cross", (x, 0, 0.1), (0.07, 0.3, 0.03), M_DARK, 0.0)
            for y in (0.11, -0.11):
                small_bomb(x, y, 0.0, 0.07, 0.46, M_BOMB)
                cyl("band", (x + 0.08, y, 0.0), 0.072, 0.02, M_BAND, "X", 16)
    else:
        # крупная кассета: створки по бокам, крестовое оперение (без кольца), раскрывающиеся стабилизаторы
        R = 0.15
        cyl("body", (-0.03, 0, 0), R, 0.62, M_BOMB, "X", 28, 0.004)
        sphere("nose", (0.28, 0, 0), R, (1.6, 1, 1), M_BOMB, 28)
        open_cone("tail", -0.33, -0.47, R, R * 0.45, M_BOMB, 28, 0.006)
        cyl("tail_in", (-0.43, 0, 0), R * 0.38, 0.06, M_DARK, "X", 16)
        for x in (0.2, -0.26):
            cyl("seam", (x, 0, 0), R * 1.01, 0.01, M_DARK, "X", 28)
        for y in (1, -1):   # линии створок вдоль корпуса
            box("door_line", (-0.03, y * R * 0.99, 0.0), (0.46, 0.006, 0.012), M_DARK, 0.0)
            box("door_line2", (-0.03, y * R * 0.7, -R * 0.71), (0.46, 0.006, 0.012), M_DARK, 0.0)
        cyl("nose_band", (0.24, 0, 0), R * 1.02, 0.025, M_BAND, "X", 28)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            # тест 3.5-s4 (п. 4): крестовое оперение без кольца-диска — перья от конуса до среза, концы открыты
            fin("tail_fin", [(-0.49, R * 0.42), (-0.33, R * 0.9), (-0.4, R + 0.075), (-0.49, R + 0.075)], 0.008, a, M_DARK)
            fin("mid_fin", [(-0.12, R * 0.9), (0.0, R * 0.9), (-0.04, R + 0.035), (-0.12, R + 0.035)], 0.006, a + math.pi / 4, M_DARK)
        lugs([0.12, -0.18], R)

elif kind == "flares":
    # Т-5: кассеты ловушек встроены в обшивку (не на пилоне): основание на z = 0, ячейки сверху.
    # Тест 3.5-s4 (п. 3): одна линия на всех ступенях — та же кассета (cassette_block), растёт и множится:
    # 1 — малая, 2 — крупнее, 3 — контейнер на законцовке крыла с такими же кассетами сверху и снизу
    # (центр на оси, симметричный — на обе консоли), не гладкая белая труба.
    if tier == 1:
        cassette_block(0.5, 0.28, 0.044, 3, 7, True)
        for ob in L.parts:
            ob.location.z += 0.022
    elif tier == 2:
        cassette_block(0.72, 0.38, 0.05, 4, 9, True)
        for ob in L.parts:
            ob.location.z += 0.025
    else:
        H = 0.07
        box("pod", (0, 0, 0), (0.6, 0.15, H * 2), M_CASE, 0.02)
        sphere("pod_nose", (0.3, 0, 0), 1.0, (0.17, 0.075, H), M_CASE, 20)
        prism("pod_tail", [(-0.3, -H), (-0.4, -H * 0.4), (-0.4, H * 0.4), (-0.3, H)], 0.15, M_CASE, 0.01)
        for sz in (1, -1):
            L.parts_before = len(L.parts)
            cassette_block(0.5, 0.14, 0.03, 2, 8)
            blk = L.parts[L.parts_before:]
            if sz < 0:
                rot_world(blk, "X", math.pi)
            for ob in blk:
                ob.location.z += sz * (H + 0.012)
                ob.location.x -= 0.03
        for x in (0.2, -0.29):
            box("pod_band", (x, 0, 0), (0.014, 0.154, H * 2.04), M_DARK, 0.0)

elif kind == "bombdrop":
    # тест 3.5-s4 (п. 10): одна бомба ступени — падает в бою носом по ходу (длина 1, центр на оси)
    if tier == 1:
        small_bomb(0.02, 0, 0, 0.104, 1.0, M_BOMB)
        cyl("band", (0.17, 0, 0), 0.106, 0.036, M_BAND, "X", 16)
    elif tier == 2:
        small_bomb(0.0, 0, 0, 0.13, 0.86, M_BOMB)
        cyl("band", (0.15, 0, 0), 0.132, 0.04, M_BAND, "X", 16)
    else:
        R = 0.15
        cyl("body", (-0.03, 0, 0), R, 0.62, M_BOMB, "X", 24, 0.004)
        sphere("nose", (0.28, 0, 0), R, (1.6, 1, 1), M_BOMB, 24)
        open_cone("tail", -0.33, -0.47, R, R * 0.45, M_BOMB, 24, 0.006)
        cyl("tail_in", (-0.43, 0, 0), R * 0.38, 0.06, M_DARK, "X", 16)
        cyl("nose_band", (0.24, 0, 0), R * 1.02, 0.025, M_BAND, "X", 24)
        for x in (0.2, -0.26):
            cyl("seam", (x, 0, 0), R * 1.01, 0.01, M_DARK, "X", 24)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            fin("tail_fin", [(-0.49, R * 0.42), (-0.33, R * 0.9), (-0.4, R + 0.075), (-0.49, R + 0.075)], 0.008, a, M_DARK)

L.group = ""
name = "%s_evo" % kind if EVO else "%s_%d" % (kind, tier)
root = build(name, OUT)
root.location.z += 0.35   # для предпросмотра — над полом (в .glb центр остаётся в начале координат)
if "nopreview" not in sys.argv:
    shots = [("iso", (1.3, -1.5, 1.25), (0, 0, 0.35), 60), ("side", (0, -2.4, 0.35), (0, 0, 0.35), 50)]
    if kind in ("rockets", "bombs", "bombdrop"):
        shots.append(("rear", (-1.6, -0.9, 0.6), (0, 0, 0.35), 60))
    preview(OUT, shots)
print("DONE")
