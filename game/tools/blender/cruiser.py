"""Вражеский лёгкий крейсер «Сторож» для второго биома «Архипелаг» (роль утвердил Kanta 18.10: мини-босс 10:00
и редкое тяжёлое сопровождение морского конвоя) — по мотивам крейсера середины века
(референсы Kanta 18.10.2026: /mnt/project-files/refs/cruiser/). Вымышленный корабль: без флагов, номеров,
надписей и опознавательных знаков; свой силуэт — башни с гранёной лобовой плитой, слегка наклонённые трубы.
Детализация под вид сверху с высоты 2–4 км: корпус, палуба, четыре башни главного калибра по три ствола,
шесть спаренных башен универсального калибра, две трубы, мачты с антенной, зенитные «кадки» с четырьмя
стволами, шлюпки, кран на корме. Тросы, леера и мелочь не строим.
Окраска врага: тёмно-серый корпус, светло-серые надстройки, тёмная палуба; красные метки, как у других врагов —
крыши башен главного калибра и полосы на трубах (хорошо видно сверху).

Набор деталей и запекание — convoy_kit.py. Размеры в метрах (длина 186 м, ширина 20 м), в конце всё делится
на длину: длина = 1, нос +X, ватерлиния на z = 0 (корпус ниже воды — на 1,5 м, чтобы не было щели у волны).
Узлы GLB: turret_1 … turret_4 — башни главного калибра (поворот вокруг вертикали; 1–2 в нос, 3–4 в корму),
          sec_1 … sec_6 — башни универсального калибра.
Запуск: python3 cruiser.py <папка>   (TEX=2048 — размер текстуры, по умолчанию 2048)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import convoy_kit as K
from convoy_kit import box, cyl, lathe, prism_z, loft, tube
from mathutils import Vector, Matrix

OUT = sys.argv[-1]
L = 186.0
K.reset()
K.EDGE_K = 0.06       # кромки ~6 см, а не ~1 м
K.AO_K = 0.2
GREY = (0.47, 0.48, 0.49)
K.KINDS.update({
    "hull": ((0.29, 0.3, 0.315), 0.2, 0.6, 0.0, False),
    "paint": (GREY, 0.15, 0.6, 0.0, False),                 # надстройки
    "deck": ((0.2, 0.215, 0.235), 0.1, 0.8, 0.0, False),
    "turret": ((0.38, 0.39, 0.4), 0.2, 0.55, 0.0, False),
    "red": ((0.68, 0.17, 0.13), 0.1, 0.55, 0.0, False),
    "black": ((0.03, 0.03, 0.03), 0.2, 0.6, 0.0, False),
    "below": ((0.3, 0.12, 0.1), 0.1, 0.7, 0.0, False),     # подводная часть
    "dark": ((0.1, 0.1, 0.1), 0.3, 0.6, 0.0, False),
    "steel": ((0.3, 0.3, 0.3), 0.7, 0.45, 0.0, False),
    "wood": ((0.47, 0.4, 0.3), 0.0, 0.85, 0.0, False),
    "glass": ((0.06, 0.08, 0.09), 0.0, 0.1, 0.0, False),
})


def grp(name, pivot=None):
    K.group = name
    if name:
        K.pivots[name] = pivot


# ---------------------------------------------------------------- корпус
# (x, полуширина по палубе, полуширина по ватерлинии, высота палубы)
HS = [(93.0, 0.3, 0.15, 11.6), (88.0, 3.4, 2.0, 11.2), (80.0, 6.6, 4.8, 10.6), (68.0, 8.9, 7.3, 9.8),
      (50.0, 9.9, 9.3, 8.9), (30.0, 10.1, 10.0, 8.4), (0.0, 10.1, 10.1, 8.0), (-30.0, 10.1, 10.0, 7.6),
      (-55.0, 9.8, 9.4, 7.2), (-75.0, 9.0, 8.0, 7.0), (-88.0, 8.2, 6.4, 7.0), (-93.0, 7.8, 5.6, 7.1)]


def _cr(p0, p1, p2, p3, t):
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def hs(x):
    """(полуширина палубы, полуширина ватерлинии, высота палубы) в точке x — сплайн по HS"""
    xs = [s[0] for s in HS]
    x = min(max(x, xs[-1]), xs[0])
    i = next(k for k in range(len(HS) - 1) if xs[k + 1] <= x)
    t = (xs[i] - x) / (xs[i] - xs[i + 1])
    return [_cr(HS[max(i - 1, 0)][j], HS[i][j], HS[i + 1][j], HS[min(i + 2, len(HS) - 1)][j], t) for j in (1, 2, 3)]


def deck_h(x):
    return hs(x)[2]


def half_w(x, z):
    b, bw, h = hs(x)
    if z >= 0:
        return bw + (b - bw) * (min(z, h) / h) ** 0.6
    return bw * (1.0 + z / 2.5)


def rake(x, z):
    """Наклон форштевня: у носа нижние точки сдвинуты назад"""
    s = max(0.0, (x - 70.0) / 23.0) ** 1.5
    return -3.2 * s * (1.0 - max(z, -1.5) / 11.6)


ZS = [-1.5, -0.6, 0.0, 1.0, 2.5, 4.5, 6.5, None]   # None — кромка палубы


def hull_pt(x, z, side, off=0.0):
    zz = deck_h(x) if z is None else z
    return Vector((x + rake(x, zz), side * (half_w(x, zz) + off), zz))


xs = [93.0, 92.0, 90.5, 88.5, 86.0, 83.0, 79.0, 74.0, 68.0, 60.0, 50.0, 38.0, 24.0, 10.0, 0.0, -14.0, -30.0, -45.0,
      -58.0, -70.0, -80.0, -87.0, -91.0, -93.0]
secs = []
for x in xs:
    h = deck_h(x)
    s = [hull_pt(x, z, 1) for z in ZS] + [Vector((x + rake(x, h), 0, h + 0.25))] + \
        [hull_pt(x, z, -1) for z in reversed(ZS)] + [Vector((x + rake(x, -1.5), 0, -1.5))]
    secs.append(s)
loft("hull", secs, "hull")
# палуба: чуть выше корпуса, по всей длине
dsecs = []
for x in xs[1:]:
    h = deck_h(x)
    b = half_w(x, h) - 0.25
    dsecs.append([Vector((x + rake(x, h), y * b, h + 0.04 + 0.25 * (1 - abs(y)))) for y in (1.0, 0.5, 0.0, -0.5, -1.0)])
vs = [p for r in dsecs for p in r]
f = [(i * 5 + j, i * 5 + j + 1, (i + 1) * 5 + j + 1, (i + 1) * 5 + j) for i in range(len(dsecs) - 1) for j in range(4)]
K._obj("deck", vs, f, "deck")
# полосы на борту: подводная часть и чёрная полоса по ватерлинии


def side_strip(name, z0, z1, kind, off=0.04):
    for side in (1, -1):
        rows = [[hull_pt(x, z0, side, off), hull_pt(x, z1, side, off)] for x in xs[1:-1]]
        vs = [p for r in rows for p in r]
        f = [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(len(rows) - 1)]
        K._obj(name, vs, f, kind)


side_strip("below", -1.5, -0.35, "below")
side_strip("boot", -0.35, 0.7, "black")
# якоря и клюзы
for side in (1, -1):
    p = hull_pt(84.0, 8.2, side, 0.05)
    cyl("hawse", tuple(p), 0.6, 0.15, "black", (0, side, 0), 12)
    box("anchor", (p.x - 0.4, p.y + side * 0.1, 7.4), (0.6, 0.25, 1.6), "dark", 0.05)
# волнолом перед башней 1 (V-образный)
for side in (1, -1):
    tube("breakwater", [(70.5, 0, deck_h(70.5) + 0.6), (67.0, side * 6.5, deck_h(67.0) + 0.6)], 0.35, "paint", 6)
# шпили и кнехты на баке
for x, y in ((80.0, 1.6), (80.0, -1.6), (76.0, 2.6), (76.0, -2.6)):
    cyl("capstan", (x, y, deck_h(x) + 0.35), 0.55, 0.7, "dark", "Z", 10)

# люки, вентиляторы и рундуки на баке и юте
for x, y, sx, sy in ((62.5, 3.5, 2.0, 1.4), (62.5, -3.5, 2.0, 1.4), (39.0, 5.5, 2.4, 1.6), (39.0, -5.5, 2.4, 1.6),
                     (-49.0, 4.8, 2.2, 1.6), (-49.0, -4.8, 2.2, 1.6), (-62.0, 0.0, 3.0, 2.2), (-68.0, 3.6, 1.6, 1.2), (-68.0, -3.6, 1.6, 1.2)):
    box("hatch_s", (x, y, deck_h(x) + 0.3), (sx, sy, 0.6), "paint", 0.0)
for x, y in ((71.0, 1.4), (71.0, -1.4), (52.0, 3.0), (52.0, -3.0), (-60.0, 6.5), (-60.0, -6.5), (-72.0, 0.0)):
    cyl("vent", (x, y, deck_h(x) + 0.7), 0.45, 1.4, "paint", "Z", 10)
    cyl("vent_top", (x + 0.2, y, deck_h(x) + 1.5), 0.55, 0.35, "dark", "Z", 10)
for x in (60.0, 56.0, -52.0, -58.0):
    for side in (1, -1):
        box("bitt", (x, side * (half_w(x, deck_h(x)) - 0.9), deck_h(x) + 0.3), (0.9, 0.4, 0.6), "dark", 0.0)

# ---------------------------------------------------------------- надстройки


def house(name, x0, x1, hw, z0, z1, kind="paint", round_front=0.0, hw_back=None, bevel=0.08):
    """Рубка: вид сверху — прямоугольник (нос скруглён на round_front м), выдавлен по высоте"""
    hb = hw if hw_back is None else hw_back
    prof = [(x0, -hb), (x0, hb)]
    if round_front > 0:
        prof += [(x1 - round_front + round_front * math.sin(math.pi * k / 8), hw * math.cos(math.pi * k / 8)) for k in range(9)]
    else:
        prof += [(x1, hw), (x1, -hw)]
    return prism_z(name, prof, z0, z1, kind, bevel)


def windows(x0, x1, y, z, h=0.7, n=6):
    """Ряд иллюминаторов/окон на стенке рубки (y — борт рубки)"""
    s = 1 if y > 0 else -1
    for k in range(n):
        x = x0 + (x1 - x0) * (k + 0.5) / n
        box("win", (x, y + s * 0.03, z), (0.8, 0.06, h), "glass", 0.0)


D0 = deck_h(20.0)
# носовая надстройка — ярусами
house("fwd_1", 8.0, 35.0, 7.2, D0 - 0.2, D0 + 3.0, round_front=4.0)
house("fwd_2", 11.0, 31.0, 6.0, D0 + 3.0, D0 + 6.0, round_front=3.0)
house("fwd_3", 15.0, 28.0, 5.2, D0 + 6.0, D0 + 9.0, round_front=2.5)
house("bridge_wing", 22.5, 26.5, 8.2, D0 + 8.3, D0 + 8.85)
for side in (1, -1):
    windows(15.5, 26.0, side * 5.2, D0 + 8.0, 0.7, 7)
box("bridge_front", (27.4, 0, D0 + 8.0), (0.1, 7.0, 0.8), "glass", 0.0)
for side in (1, -1):
    windows(10.0, 30.0, side * 7.2, D0 + 1.6, 0.5, 10)
    windows(12.0, 27.0, side * 6.0, D0 + 4.6, 0.6, 8)
# фок-мачта: тренога, площадка, решётчатая антенна
MX = 11.0
for p in ((MX + 2.5, 0, D0 + 6.0), (MX - 1.5, 2.5, D0 + 3.0), (MX - 1.5, -2.5, D0 + 3.0)):
    tube("mast_leg", [p, (MX, 0, D0 + 24.0)], 0.32, "paint", 8)
tube("mast_top", [(MX, 0, D0 + 24.0), (MX, 0, D0 + 33.0)], 0.2, "paint", 8)
box("mast_plat", (MX, 0, D0 + 22.5), (3.6, 3.6, 0.3), "paint", 0.05)
box("yard", (MX, 0, D0 + 25.5), (0.3, 9.0, 0.25), "paint", 0.03)
box("radar", (MX + 0.4, 0, D0 + 28.5), (0.4, 4.6, 3.4), "dark", 0.05)
for k in range(5):
    box("radar_grid", (MX + 0.65, -1.85 + k * 0.925, D0 + 28.5), (0.12, 0.12, 3.4), "steel", 0.0)
# середина: рубка под трубами и платформы
D1 = deck_h(-4.0)
house("mid", -24.0, 8.0, 6.0, D1 - 0.2, D1 + 3.0)
house("mid_plat", -6.0, 0.0, 7.6, D1 + 3.0, D1 + 3.4)
for side in (1, -1):
    windows(-22.0, 6.0, side * 6.0, D1 + 1.6, 0.5, 12)
# прожекторы на площадке между трубами
for side in (1, -1):
    cyl("search_base", (-3.0, side * 5.2, D1 + 3.9), 0.7, 1.0, "paint", "Z", 10)
    cyl("searchlight", (-2.8, side * 5.2, D1 + 4.8), 0.6, 0.8, "dark", "X", 12)

cyl("tower", (22.0, 0, D0 + 11.0), 2.3, 4.0, "paint", "Z", 20, 0.05)
box("director", (22.3, 0, D0 + 14.3), (4.2, 3.4, 2.6), "paint", 0.2)
box("rangefinder", (21.6, 0, D0 + 14.6), (1.0, 9.0, 0.7), "paint", 0.1)
cyl("dir_top", (22.3, 0, D0 + 15.8), 1.0, 0.5, "dark", "Z", 12)


def funnel(x, h_top):
    """Труба: овал в плане, наклон назад, кожух у основания, красная полоса и чёрный срез"""
    secs = []
    z0 = D1 + 3.0
    n = 18
    for k, z in enumerate((z0, z0 + 3, z0 + 8, h_top - 1.2, h_top)):
        dx = -(z - z0) * 0.04              # лёгкий наклон назад
        rx, ry = (3.4, 2.5) if k == 0 else (3.0, 2.2)
        secs.append([Vector((x + dx + rx * math.cos(2 * math.pi * i / n), ry * math.sin(2 * math.pi * i / n), z)) for i in range(n)])
    loft("funnel", secs, "paint", caps=False)
    # красная полоса
    zr0, zr1 = h_top - 4.0, h_top - 2.4
    loft("funnel_red", [[Vector((x - (z - z0) * 0.04 + 3.06 * math.cos(2 * math.pi * i / n), 2.26 * math.sin(2 * math.pi * i / n), z))
                         for i in range(n)] for z in (zr0, zr1)], "red", caps=False)
    # срез: чёрный провал и ободок
    xt = x - (h_top - z0) * 0.04
    prism_z("funnel_cap", [(xt + 2.9 * math.cos(2 * math.pi * i / n), 2.1 * math.sin(2 * math.pi * i / n)) for i in range(n)],
            h_top - 0.6, h_top - 0.1, "black", 0.0)
    for k in (-0.9, 0.9):
        box("funnel_bar", (xt, k, h_top - 0.2), (5.6, 0.2, 0.25), "dark", 0.0)


funnel(4.0, D1 + 18.0)
funnel(-9.5, D1 + 18.0)
# шлюпки на шлюпбалках
for side in (1, -1):
    for x in (-15.0, -21.0):
        z = D1 + 3.6
        lathe("boat", [(0.001, -3.2), (0.7, -2.6), (1.0, -1.0), (1.0, 1.4), (0.7, 2.8), (0.001, 3.2)],
              (x, side * 7.6, z), "wood", "X", 10)
        box("boat_cover", (x, side * 7.6, z + 0.55), (5.4, 1.5, 0.2), "paint", 0.0)
        for dx in (-2.2, 2.2):
            tube("davit", [(x + dx, side * 6.0, D1 + 3.0), (x + dx, side * 6.4, z + 1.8), (x + dx, side * 7.6, z + 1.8)], 0.12, "dark", 6)
# кормовая надстройка
D2 = deck_h(-30.0)
house("aft_1", -42.0, -24.0, 6.4, D2 - 0.2, D2 + 3.0)
house("aft_2", -39.0, -26.0, 5.0, D2 + 3.0, D2 + 6.0)
cyl("aft_tower", (-31.0, 0, D2 + 8.0), 2.0, 4.0, "paint", "Z", 18, 0.05)
box("aft_dir", (-31.0, 0, D2 + 11.0), (3.6, 3.0, 2.2), "paint", 0.15)
box("aft_rf", (-31.4, 0, D2 + 11.2), (0.9, 7.0, 0.6), "paint", 0.1)
tube("mainmast", [(-27.0, 0, D2 + 6.0), (-27.0, 0, D2 + 24.0)], 0.3, "paint", 8)
box("mainyard", (-27.0, 0, D2 + 20.0), (0.25, 6.0, 0.2), "paint", 0.03)
for side in (1, -1):
    windows(-41.0, -25.0, side * 6.4, D2 + 2.0, 0.6, 8)
# корма: люк ангара и кран
DS = deck_h(-78.0)
box("hatch", (-76.0, 0, DS + 0.12), (12.0, 7.0, 0.2), "dark", 0.05)
for k in range(5):
    box("hatch_seam", (-81.0 + k * 2.5, 0, DS + 0.24), (0.12, 7.0, 0.05), "black", 0.0)
cyl("crane_base", (-88.0, 0, DS + 1.0), 1.3, 2.0, "paint", "Z", 14)
for side in (1, -1):
    tube("crane_jib", [(-88.0, side * 0.6, DS + 2.0), (-86.0, side * 0.3, DS + 12.0), (-80.5, 0, DS + 14.0)], 0.22, "paint", 6)
tube("crane_tie", [(-88.0, 0, DS + 2.0), (-84.0, 0, DS + 8.0), (-80.5, 0, DS + 14.0)], 0.16, "dark", 6)

# ---------------------------------------------------------------- зенитные «кадки» с четырьмя стволами


def aa_tub(x, y, z, yaw=0.0):
    lathe("tub", [(1.9, 0.0), (1.9, 1.15), (1.75, 1.15), (1.75, 0.15), (0.001, 0.15)], (x, y, z), "paint", "Z", 10)
    box("aa_mount", (x, y, z + 0.6), (1.2, 1.2, 0.8), "dark", 0.0)
    d = Vector((math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0.55)).normalized()
    side_v = Vector((-d.y, d.x, 0)).normalized()
    for k in (-0.45, -0.15, 0.15, 0.45):
        p0 = Vector((x, y, z + 0.9)) + side_v * k
        tube("aa_barrel", [tuple(p0), tuple(p0 + d * 3.4)], 0.07, "black", 6)


for x, y, z, yaw in ((30.0, 7.6, D0 + 3.0, 60), (30.0, -7.6, D0 + 3.0, -60), (-2.5, 6.6, D1 + 3.4, 90), (-2.5, -6.6, D1 + 3.4, -90),
                     (-36.0, 5.6, D2 + 6.0, 120), (-36.0, -5.6, D2 + 6.0, -120), (-64.0, 6.8, deck_h(-64.0), 150),
                     (-64.0, -6.8, deck_h(-64.0), -150), (74.0, 4.6, deck_h(74.0), 30), (74.0, -4.6, deck_h(74.0), -30)):
    aa_tub(x, y, z, yaw)

# ---------------------------------------------------------------- башни
MAIN = [(57.5, 0.0, 0.0, 0.0), (45.0, 0.0, 3.2, 0.0), (-44.0, 0.0, 3.2, 180.0), (-56.5, 0.0, 0.0, 180.0)]


def main_turret(i, x, y, lift, yaw):
    z0 = deck_h(x) + lift
    if lift > 0:
        cyl("barbette", (x, y, deck_h(x) + lift / 2), 4.6, lift + 0.4, "paint", "Z", 24, 0.05)
    node = "turret_%d" % i
    grp(node, (x, y, z0))
    R = Matrix.Rotation(math.radians(yaw), 3, "Z")
    o = Vector((x, y, z0))

    def P(px, py, pz):
        return o + R @ Vector((px, py, pz))
    # гранёный корпус: низ шире, лоб и бока наклонены
    lo = [(3.9, 2.9), (1.8, 4.5), (-4.6, 4.5), (-5.2, 3.0), (-5.2, -3.0), (-4.6, -4.5), (1.8, -4.5), (3.9, -2.9)]
    hi = [(2.6, 2.2), (1.2, 3.9), (-4.3, 3.9), (-4.8, 2.6), (-4.8, -2.6), (-4.3, -3.9), (1.2, -3.9), (2.6, -2.2)]
    loft("turret", [[P(a, b, 0.0) for a, b in lo], [P(a, b, 2.9) for a, b in hi]], "turret", 0.06)
    loft("turret_roof", [[P(a * 0.97, b * 0.97, 2.92) for a, b in hi], [P(a * 0.97, b * 0.97, 2.98) for a, b in hi]], "red", 0.0)
    for py in (-1.5, 1.5):     # колпаки дальномера/перископов
        cyl("hood", tuple(P(-1.0, py, 3.1)), 0.55, 0.4, "turret", "Z", 10)
    box("rf_arm", tuple(P(-3.6, 0, 2.2)), (1.0, 10.0, 0.8), "turret", 0.0, rot=R)
    for py in (-1.5, 0.0, 1.5):
        tube("gun", [tuple(P(3.0, py, 1.35)), tuple(P(15.0, py, 1.45))], 0.32, "dark", 10)
        tube("gun_bag", [tuple(P(2.6, py, 1.35)), tuple(P(4.0, py, 1.37))], 0.55, "dark", 8)
    grp("")


for i, t in enumerate(MAIN):
    main_turret(i + 1, *t)

SEC = [(35.5, 0.0, D0 + 6.0, 0.0), (19.0, 7.0, D0 + 3.0, 50.0), (19.0, -7.0, D0 + 3.0, -50.0),
       (-18.0, 6.2, D1 + 3.0, 110.0), (-18.0, -6.2, D1 + 3.0, -110.0), (-38.5, 0.0, D2 + 6.0, 180.0)]


def sec_turret(i, x, y, z0, yaw):
    node = "sec_%d" % i
    cyl("sec_ring", (x, y, z0 + 0.15), 2.5, 0.3, "paint", "Z", 16)
    grp(node, (x, y, z0))
    R = Matrix.Rotation(math.radians(yaw), 3, "Z")
    o = Vector((x, y, z0))

    def P(px, py, pz):
        return o + R @ Vector((px, py, pz))
    n = 16
    rows = []
    for k, (z, s) in enumerate(((0.3, 1.0), (1.6, 0.97), (2.3, 0.82), (2.55, 0.55))):
        rows.append([P(s * (2.6 if math.cos(2 * math.pi * j / n) > 0 else 2.2) * math.cos(2 * math.pi * j / n),
                       s * 2.1 * math.sin(2 * math.pi * j / n), z) for j in range(n)])
    loft("sec", rows, "turret")
    for py in (-0.6, 0.6):
        tube("sec_gun", [tuple(P(2.3, py, 1.2)), tuple(P(7.5, py, 1.25))], 0.17, "dark", 8)
    grp("")


for i, t in enumerate(SEC):
    sec_turret(i + 1, *t)

# одиночные зенитки по краю палубы
for x in (64.0, 52.0, -50.0, -68.0):
    for side in (1, -1):
        z = deck_h(x)
        lathe("tub_s", [(1.0, 0.0), (1.0, 0.9), (0.9, 0.9), (0.9, 0.1), (0.001, 0.1)], (x, side * (half_w(x, z) - 1.6), z), "paint", "Z", 8)
        tube("aa_single", [(x, side * (half_w(x, z) - 1.6), z + 0.7), (x + 1.2, side * (half_w(x, z) - 0.6), z + 2.3)], 0.07, "black", 6)

# ---------------------------------------------------------------- метры → длина 1
SC = 1.0 / L
M = Matrix.Scale(SC, 4)
for o in K.parts:
    o.data.transform(M)
    for md in o.modifiers:
        if md.type == "BEVEL":
            md.width *= SC
for k in list(K.pivots):
    K.pivots[k] = tuple(v * SC for v in K.pivots[k])

root, tris = K.bake_export("cruiser", OUT, tex=int(os.environ.get("TEX", "2048")))
print("DONE tris", tris)
