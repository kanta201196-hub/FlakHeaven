"""Тест 3.5-s8: оружие для ангара в высоком качестве (Kanta: «блоки НАР и всё оружие — супер качественные модели,
они показываются близко»; «то же — бомбы и экспериментальное») и новая шкала бомб.
Одна раскладка — две версии (hq_lib): ангарная (--hq, по умолчанию: фаски, заклёпки, швы, ушки, трафареты
без настоящих надписей, запечённый AO и грязь в текстуре; до ~60 тыс. треуг.) и боевая (--battle: та же форма
малым числом треугольников). Размеры и места крепления — как у боевых моделей weapons.py / exp_weapons.py
(рельс пилона ложится на тот же верх габарита), поэтому ангарная версия меняет только качество.
«По мотивам»: без надписей, номеров и эмблем; цветные пояса — только маркировка.
Запуск (bpy 5.x): python3 weapons_hq.py <вид> <ступень> <out_dir> [--battle] [--blend=<папка .blend>]
  aam 1|2|3|evo, arm 1, rockets 1|2|3|evo, flares 1|2|3|evo, bombs 1…5|evo|evobay, bombdrop evo,
  exp railgun|emp|laser|plasma
Ангарные версии — в models/weapons/hq/ (WeaponModels.weapon_model(..., hq = true)), боевые — в models/weapons/.

Шкала бомб (тест 3.5-s8, Kanta: «эволюция бомб нелогична — в конце они меньше и слабее»): на пилоне одна бомба —
та, что падает; калибр растёт с уровнем оружия, модернизация — восемь бомб среднего калибра («ковёр», 2 т):
  ур. 1 «50»   — короткая тупоносая, простое крестовое оперение, одно ушко, один пояс;
  ур. 2 «100»  — длиннее, оживальный нос, коробчатый стабилизатор, взрыватель с вертушкой;
  ур. 3 «250»  — ещё длиннее и толще, два ушка, два пояса, хвостовой взрыватель;
  ур. 4 «500»  — толстый корпус, баллистическое кольцо на носу, крупный коробчатый стабилизатор, ложемент;
  ур. 5 «1000» — самая крупная: толстостенный корпус, кольцевой стабилизатор, кольцо на носу, усиленные ушки,
                 три пояса, лючки заливки;
  модернизация — планка с 8 бомбами «250» (у «Кита» — кассета в отсеке), двойные жёлтые пояса."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hq_lib as H
from hq_lib import *

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
kind, tier, OUT = ARGS[-3], ARGS[-2], ARGS[-1]
BATTLE = "--battle" in sys.argv
BLEND = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--blend=")), None)
H.reset(not BATTLE)

# Kanta 19.10: окраска реалистичная, матовая; металл — только голые детали (сопла, крепёж, ушки)
M_MSL = paint("msl_white", (0.43, 0.44, 0.43), 0.84, ao=0.5, grime=0.12, dust=0.22)
M_MSL_DARK = paint("msl_dark", (0.07, 0.07, 0.075), 0.84)
M_BOMB = paint("bomb_olive", (0.12, 0.14, 0.085), 0.88, ao=0.5, grime=0.2, dust=0.35)
M_OLIVE = paint("pod_olive", (0.19, 0.2, 0.145), 0.88, ao=0.55, grime=0.2, dust=0.3)
M_CASE = paint("flare_case", (0.24, 0.26, 0.22), 0.86)
M_HULL = paint("exp_hull", (0.225, 0.238, 0.217), 0.85)
M_BAND = paint("band_yellow", (0.51, 0.38, 0.082), 0.84, ao=0.4, grime=0.12)
M_YELLOW = paint("yellow", (0.56, 0.43, 0.045), 0.84, ao=0.4, grime=0.12)
M_BROWN = paint("band_brown", (0.33, 0.2, 0.09), 0.84, ao=0.4, grime=0.1)
M_RED = paint("mark_red", (0.5, 0.09, 0.06), 0.84, ao=0.35, grime=0.1)
M_STENCIL = paint("stencil", (0.78, 0.76, 0.68), 0.86, ao=0.25, grime=0.12, dust=0.1)
M_STENCIL_D = paint("stencil_dark", (0.05, 0.05, 0.05), 0.86, ao=0.2, grime=0.0, dust=0.05)
M_DARK = paint("dark", (0.045, 0.045, 0.05), 0.86, ao=0.4, grime=0.05, dust=0.05)
M_STEEL = metal("steel", (0.36, 0.36, 0.37), 0.48, 0.7)
M_NOZZLE = metal("nozzle", (0.13, 0.12, 0.11), 0.6, 0.55)
M_BRASS = metal("brass", (0.66, 0.5, 0.22), 0.5, 0.5)
M_COPPER = metal("copper", (0.58, 0.3, 0.15), 0.5, 0.55)
M_GLASS = glass("glass", (0.1, 0.16, 0.2))


def fin(outline, thick, ang, m, bev=None, M=None):
    """Перо: контур (x, s) — s от оси наружу; поворот вокруг оси X на ang"""
    bm = prism(outline, thick, thick * 0.42 if bev is None else bev, 2)
    emit(bm, m, (M or Matrix.Identity(4)) @ RX(ang))


def ring_band(x0, x1, r, m, lift=0.0004, yz=(0, 0), seg=56):
    """Цветной пояс: тонкое кольцо поверх корпуса (столько же граней, что у корпуса, — без «пунктира» в бою)"""
    emit(lathe([(x0, r + lift * (1 if HQ else 3)), (x1, r + lift * (1 if HQ else 3))], seg, False, False), m, T(0, *yz))


def put_z(r, h, m, x, y, z, seg=24, bevel=0.0):
    """Цилиндр по оси Z"""
    emit(cyl(r, h, seg, bevel), m, T(x, y, z) @ RY(-math.pi / 2))


# ======================= БОМБЫ =======================
# [длина L, радиус R] в долях длины подвеса (1 = 0,27 длины самолёта, PlaneArt.WEAPON_FRAC)
LADDER = {1: (0.42, 0.05), 2: (0.53, 0.064), 3: (0.66, 0.08), 4: (0.8, 0.1), 5: (1.0, 0.13)}


def bomb(L, R, cls, x=0.0, y=0.0, z=0.0, body=None, bands=None, evo=False):
    """Авиабомба калибра cls (1…5) носом +X: корпус с хвостовым конусом (открытый срез с полостью), оперение,
    взрыватели, ушки, пояса, трафареты. Центр габарита — (x, y, z)"""
    body = body or M_BOMB
    with xf(T(x, y, z)):
        xs, xe = -L / 2, L / 2
        fz = 0.035 * L                       # взрыватель в носу
        xtip = xe - fz
        tail_len = 0.3 * L
        xt = xs + 0.05 * L                   # срез хвостового конуса
        xb = xs + tail_len                   # начало цилиндра
        nose_len = (0.2 if cls == 1 else 0.27) * L
        xn = xtip - nose_len
        rt = R * 0.45
        seams = [xb + 0.03 * L, (xb + xn) / 2] if cls >= 3 else [(xb + xn) / 2]
        nose = dome_prof(xn, R, nose_len, 8, R * 0.2) if cls == 1 else ogive(xn, xtip, R, R * 0.17, 12)
        prof = [(xt + 0.05 * L, rt * 0.78), (xt, rt * 0.84), (xt, rt)]
        prof += [(xt + (xb - xt) * t, rt + (R - rt) * (t ** 0.8)) for t in (0.35, 0.7)] + [(xb, R)]
        prof += grooves(xb, xn, R, seams)[1:] + nose[1:]
        emit(lathe(prof, 56), body)
        emit(cyl(rt * 0.78, 0.004, 24), M_DARK, T(xt + 0.05 * L - 0.003, 0, 0))   # дно полости
        if cls >= 3:   # хвостовой взрыватель в полости
            emit(cyl(rt * 0.28, 0.03 * L, 16, 0.002), M_STEEL, T(xt + 0.035 * L, 0, 0))
        # носовой взрыватель: корпус, гайка, вертушка
        fr = R * (0.2 if cls == 1 else 0.17)
        emit(lathe([(xtip - 0.002, fr), (xtip + fz * 0.45, fr), (xtip + fz * 0.55, fr * 0.8), (xtip + fz, fr * 0.55), (xtip + fz, 0)], 20), M_STEEL)
        if HQ:
            emit(lathe([(xtip, fr * 1.15), (xtip + fz * 0.25, fr * 1.15)], 6), M_STEEL)   # шестигранная гайка
            if cls >= 2:
                for k in range(2):
                    emit(box((0.002, fr * 2.4, fr * 0.55), 0.0005), M_STEEL, T(xtip + fz * 0.7, 0, 0) @ RX(k * math.pi / 2 + 0.4) @ RY(0.35))
        # оперение
        s_tip = R * (1.08 if cls == 5 else 1.32)
        thick = max(R * 0.05, 0.003)

        def rcone(xx):
            if xx <= xt:
                return rt
            return rt + (R - rt) * min(1.0, (xx - xt) / (xb - xt)) ** 0.8

        x_root = xb - 0.03 * L
        x_le = xb - (0.1 if cls < 5 else 0.06) * L
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            outline = [(xs, rcone(xs) * 0.92), (x_root, rcone(x_root) * 0.95), (x_le, s_tip), (xs, s_tip)]
            fin(outline, thick, a, M_BOMB if cls == 5 else M_DARK if cls == 1 else body)
        if cls in (2, 3, 4):   # коробчатый стабилизатор: 4 пластины по концам перьев, сквозной
            d = s_tip / math.sqrt(2.0)
            w = s_tip * math.sqrt(2.0)
            ch = 0.1 * L
            xc = xs + ch / 2
            t = max(R * 0.04, 0.0022)
            for sz in (1, -1):
                emit(box((ch, w, t), t * 0.4), body, T(xc, 0, sz * d))
                emit(box((ch, t, w), t * 0.4), body, T(xc, sz * d, 0))
        if cls == 5:   # кольцевой стабилизатор
            ch = 0.13 * L
            emit(tube_shell(s_tip + R * 0.035, s_tip, ch, 56), body, T(xs + ch / 2, 0, 0))
            rivets(xs + ch * 0.3, s_tip + R * 0.035, 32, M_STEEL, 0.0018)
            rivets(xs + ch * 0.7, s_tip + R * 0.035, 32, M_STEEL, 0.0018)
        if cls >= 4:   # баллистическое кольцо на носу на 4 стойках
            xr = xn + nose_len * 0.42
            rr = R * 0.82
            ch = 0.045 * L
            emit(tube_shell(rr + R * 0.05, rr, ch, 48), body, T(xr, 0, 0))
            r_n = R * 0.62
            for k in range(4):
                a = math.pi / 4 + k * math.pi / 2
                emit(box((ch * 0.8, 0.003, rr - r_n + 0.004), 0.0008), body, T(xr, math.cos(a) * (rr + r_n) / 2, math.sin(a) * (rr + r_n) / 2) @ RX(a - math.pi / 2))
        # пояса: жёлтый у носа (у «ковра» — двойной), у крупных ещё у хвоста
        bw = 0.032 * L
        ring_band(xn - bw * 1.6, xn - bw * 0.6, R, M_BAND)
        if evo:
            ring_band(xn - bw * 3.0, xn - bw * 2.0, R, M_BAND)
        if cls >= 3:
            ring_band(xb + bw * 0.8, xb + bw * 1.8, R, M_BAND)
        if cls == 5:
            ring_band((xb + xn) / 2 + bw * 0.4, (xb + xn) / 2 + bw * 1.4, R, M_BAND)
        # ушки; у крупных — ложемент между ними
        ls = 0.6 + R * 7.5
        lx = [0.0] if cls == 1 else [-0.16 * L, 0.16 * L]
        for x0 in lx:
            lug((xb + xn) / 2 + x0 - 0.02 * L, R - 0.002, M_STEEL, ls)
        if cls >= 4:
            cx = (xb + xn) / 2 - 0.02 * L
            emit(box((0.36 * L, R * 0.42, 0.004 * ls), 0.0015), M_STEEL if cls == 5 else body, T(cx, 0, R - 0.0005))
            rivets(cx - 0.17 * L, R, 7, M_STEEL, 0.0015, arc=(math.pi / 2 - 0.18, math.pi / 2 + 0.18))
            rivets(cx + 0.17 * L, R, 7, M_STEEL, 0.0015, arc=(math.pi / 2 - 0.18, math.pi / 2 + 0.18))
        # швы: заклёпки по стыкам корпуса с хвостом и носом
        rivets(xb + 0.006, R, 18 + 6 * cls, M_STEEL, 0.0012 + 0.0002 * cls, skip_top=True)
        rivets(xn - 0.006, R, 18 + 6 * cls, M_STEEL, 0.0012 + 0.0002 * cls, skip_top=True)
        # лючки заливки ВВ (крупные калибры)
        if cls >= 4 and HQ:
            for a in (0.0, math.pi):
                xx = xb + (xn - xb) * 0.62
                emit(cyl(R * 0.16, 0.003, 24, 0.001), body, surf(xx, a, R, 0.0005))
                for k in range(6):
                    q = 2 * math.pi * k / 6
                    screw(surf(xx + math.cos(q) * R * 0.12, a + math.sin(q) * R * 0.12 / R, R, 0.0012), 0.0016, M_STEEL)
        # трафарет по бокам (строки «слов» без смысла)
        x0 = xb + (xn - xb) * 0.2
        x1 = xb + (xn - xb) * (0.55 if cls >= 4 else 0.75)
        for a, sd in ((0.15, 1), (math.pi - 0.15, 2)):
            stencil(x0, x1, a, R, M_STENCIL if body == M_BOMB else M_STENCIL_D, 3 if cls >= 3 else 2, 0.0035 + 0.0006 * cls, seed=cls * 10 + sd)


# ======================= РАКЕТЫ =======================
def shoe(x0, x1, zb, zt):
    """Колодка пускового рельса — от корпуса до верха габарита (на неё ложится рельс пилона)"""
    emit(box((x1 - x0, 0.016, zt - zb), 0.0015), M_STEEL, T((x0 + x1) / 2, 0, (zb + zt) / 2))
    for x in (x0 + 0.03, x1 - 0.03):
        emit(box((0.03, 0.022, 0.008), 0.001), M_DARK, T(x, 0, zt - 0.004))
    if HQ:
        for x in [x0 + 0.015 + i * (x1 - x0 - 0.03) / 7 for i in range(8)]:
            for sy in (1, -1):
                screw(T(x, sy * 0.008, (zb + zt) / 2) @ RZ(sy * math.pi / 2), 0.0014, M_STEEL)


def missile_body(prof, m, seg=40):
    emit(lathe(prof, seg), m)


def nozzle(x, r, m=M_NOZZLE, ln=0.014):
    """Сопло: раструб с внутренней полостью (вдоль -X от x)"""
    emit(lathe([(x - ln * 0.9, r * 0.55), (x - ln, r * 0.8), (x - ln, r * 0.92), (x - ln * 0.3, r * 0.98), (x, r)], 32, True, False), m)
    emit(cyl(r * 0.5, 0.003, 16), M_DARK, T(x - ln * 0.85, 0, 0))


def raceway(x0, x1, r, a, m):
    """Кабельный короб вдоль корпуса ракеты"""
    if not HQ:
        return
    w = 0.006
    emit(box((x1 - x0, 0.004, w), 0.0015), m, surf((x0 + x1) / 2, a, r, 0.0015) @ RZ(math.pi / 2))


def aam(t):
    if t == 1:
        # ступень 1: лёгкая ракета — гладкий корпус, оживальный нос, крылья посередине, рули у сопла
        R = 0.03
        prof = [(-0.49, R * 0.82), (-0.485, R)] + grooves(-0.485, 0.33, R, [-0.36, -0.12, 0.12, 0.25])[1:] + ogive(0.33, 0.5, R, 0.003, 10)[1:] + [(0.5, 0)]
        missile_body(prof, M_MSL, 40)
        nozzle(-0.49, R * 0.8)
        ring_band(0.2, 0.225, R, M_BAND)
        ring_band(-0.2, -0.18, R, M_BROWN)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            fin([(-0.1, R * 0.8), (0.06, R * 0.8), (0.02, R + 0.05), (-0.08, R + 0.05)], 0.005, a, M_MSL)
            fin([(-0.48, R * 0.8), (-0.37, R * 0.8), (-0.42, R + 0.045), (-0.48, R + 0.045)], 0.005, a, M_MSL)
        rivets(0.3, R, 20, M_STEEL, 0.0009, skip_top=True)
        rivets(-0.33, R, 20, M_STEEL, 0.0009, skip_top=True)
        raceway(-0.4, 0.28, R, -math.pi / 2, M_MSL)
        stencil(-0.05, 0.1, 0.1, R, M_STENCIL_D, 2, 0.0028, seed=11)
        shoe(-0.22, 0.16, R * 0.85, 0.062)
    elif t == 2:
        # ступень 2: толще, тёмный отсек головки со стеклянным «глазом», передние рули, роллероны
        R = 0.038
        prof = [(-0.505, R * 0.82), (-0.5, R)] + grooves(-0.5, 0.26, R, [-0.36, -0.1, 0.1])[1:] + [(0.26, R)]
        missile_body(prof, M_MSL, 40)
        emit(lathe([(0.26, R), (0.46, R)], 40, False, False), M_MSL_DARK)
        emit(lathe(dome_prof(0.46, R, R * 1.4, 10), 40, True, False), M_GLASS)
        if HQ:   # внутри «глаза» — головка
            emit(sphere(R * 0.42, 16), M_DARK, T(0.47, 0, 0))
        nozzle(-0.505, R * 0.75)
        for x in (0.2, 0.05, -0.36):
            ring_band(x - 0.01, x + 0.01, R, M_BAND)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            fin([(0.28, R * 0.8), (0.4, R * 0.8), (0.3, R + 0.05)], 0.0045, a, M_MSL_DARK)
            fin([(-0.5, R * 0.8), (-0.36, R * 0.8), (-0.44, R + 0.052), (-0.5, R + 0.052)], 0.0045, a, M_MSL)
            # роллерон на конце руля: колёсико с осью
            y, zz = -math.sin(a) * (R + 0.05), math.cos(a) * (R + 0.05)
            emit(cyl(0.013, 0.006, 20, 0.0015), M_STEEL, T(-0.485, y, zz) @ RX(a) @ RZ(math.pi / 2))
        rivets(0.25, R, 24, M_STEEL, 0.001, skip_top=True)
        rivets(-0.34, R, 24, M_STEEL, 0.001, skip_top=True)
        raceway(-0.42, 0.22, R, -math.pi / 2, M_MSL)
        stencil(-0.06, 0.08, 0.1, R, M_STENCIL_D, 2, 0.003, seed=12)
        shoe(-0.24, 0.14, R * 0.85, 0.068)
    else:
        # ступень 3: тяжёлая — гранёный корпус, скошенный нос с окном, большие крылья, ускоритель с медным кольцом
        R = 0.048
        emit(lathe([(-0.33, R), (0.33, R)], 8), M_MSL)
        emit(prism([(0.33, -R * 0.92), (0.5, -R * 0.5), (0.5, R * 0.25), (0.33, R * 0.92)], R * 1.84, 0.004), M_MSL)
        emit(box((0.004, R * 1.1, R * 0.55), 0.0008), M_GLASS, T(0.4995, 0, -R * 0.12))
        if HQ:
            emit(box((0.003, R * 1.22, R * 0.67), 0.0006), M_DARK, T(0.4985, 0, -R * 0.12))
        emit(lathe([(0.29, R * 1.01), (0.315, R * 1.01)], 8, False, False), M_MSL_DARK)
        emit(box((0.24, R * 0.9, 0.006), 0.0015), M_MSL_DARK, T(0.05, 0, -R * 0.9))
        emit(lathe([(-0.36, R * 0.85), (-0.33, R * 0.85)], 32, False, False), M_COPPER)
        emit(lathe([(-0.485, R * 0.9)] + [(-0.36, R * 0.9)], 32, False, True), M_MSL)
        emit(lathe(dome_prof(-0.485, R * 0.9, -R * 0.36, 6), 32, False, True), M_MSL_DARK)
        ring_band(-0.446, -0.434, R * 0.9, M_MSL_DARK)
        ring_band(0.22, 0.25, R, M_BAND)
        for k in range(2):
            a = math.pi / 2 + k * math.pi
            fin([(-0.06, R * 0.7), (0.12, R * 0.7), (0.0, R + 0.12), (-0.07, R + 0.12)], 0.006, a, M_MSL)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            fin([(-0.33, R * 0.7), (-0.22, R * 0.7), (-0.28, R + 0.05), (-0.33, R + 0.05)], 0.005, a, M_MSL)
        emit(box((0.3, 0.012, 0.022), 0.003), M_MSL, T(-0.05, 0, R + 0.012))
        if HQ:   # швы граней и лючки
            for x in (-0.2, 0.15):
                for k in range(8):
                    a = 2 * math.pi * k / 8 + math.pi / 8
                    if math.sin(a) > 0.8:
                        continue
                    screw(surf(x, a, R * math.cos(math.pi / 8), 0.0005), 0.0015, M_STEEL)
            for a in (0.0, math.pi):
                emit(box((0.003, 0.05, 0.026), 0.0008), M_MSL, surf(-0.08, a, R * 0.93, 0.0008))
            stencil(-0.25, -0.1, 0.0, R * 0.93, M_STENCIL_D, 3, 0.0034, seed=13)
        shoe(-0.24, 0.19, R * 0.9, 0.08)


def aam_evo():
    # «Шмель»: носитель вдвое толще ракеты, 4 открытых отсека с боевыми частями, жёлтые полосы
    R = 0.07
    prof = [(-0.42, R * 0.78), (-0.42, R)] + grooves(-0.42, 0.32, R, [-0.3, 0.2])[1:] + ogive(0.32, 0.5, R, 0.004, 12)[1:] + [(0.5, 0)]
    missile_body(prof, M_MSL, 48)
    nozzle(-0.42, R * 0.75, ln=0.025)
    for x in (0.26, 0.2, -0.3, -0.36):
        ring_band(x - 0.015, x + 0.015, R, M_YELLOW, 0.0008)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        cy, cz = -math.sin(a) * R * 0.95, math.cos(a) * R * 0.95
        emit(box((0.34, R * 0.75, R * 0.75), 0.004), M_DARK, T(-0.04, cy, cz) @ RX(a))
        # боевая часть: корпус, жёлтый нос, хвостовые перышки
        with xf(T(0, cy * 1.12, cz * 1.12)):
            emit(lathe([(-0.17, R * 0.22), (-0.17, R * 0.3), (0.05, R * 0.3)] + ogive(0.05, 0.12, R * 0.3, 0.001, 8)[1:], 20), M_STEEL)
            emit(lathe(ogive(0.05, 0.12, R * 0.31, 0.001, 8), 20, False, False), M_YELLOW)
            if HQ:
                for q in range(4):
                    fin([(-0.17, R * 0.25), (-0.13, R * 0.25), (-0.15, R * 0.45), (-0.17, R * 0.45)], 0.002, q * math.pi / 2, M_STEEL)
        if HQ:   # рамка отсека
            emit(box((0.35, 0.004, R * 0.08), 0.001), M_MSL, T(-0.04, cy * 1.02, cz * 1.02) @ RX(a) @ T(0, R * 0.37, 0))
            emit(box((0.35, 0.004, R * 0.08), 0.001), M_MSL, T(-0.04, cy * 1.02, cz * 1.02) @ RX(a) @ T(0, -R * 0.37, 0))
        fin([(-0.46, R * 0.8), (-0.33, R * 0.8), (-0.4, R + 0.06), (-0.46, R + 0.06)], 0.006, a, M_MSL)
    rivets(0.3, R, 36, M_STEEL, 0.0014, skip_top=True)
    rivets(-0.38, R, 36, M_STEEL, 0.0014, skip_top=True)
    for x in (0.12, -0.22):
        lug(x, R, M_STEEL, 1.0)


def arm():
    # противорадарная «Ласки»: длиннее и толще В-В, длинные узкие крылья, тёмный обтекатель головки
    R = 0.04
    prof = [(-0.465, R * 0.8), (-0.46, R)] + grooves(-0.46, 0.34, R, [-0.3, 0.0, 0.2])[1:] + [(0.34, R)]
    missile_body(prof, M_MSL, 40)
    emit(lathe(ogive(0.34, 0.5, R, 0.003, 10) + [(0.5, 0)], 40, False, True), M_MSL_DARK)
    ring_band(0.32, 0.34, R * 1.02, M_BAND)
    nozzle(-0.465, R * 0.8)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        fin([(-0.2, R * 0.8), (0.12, R * 0.8), (0.06, R + 0.035), (-0.18, R + 0.035)], 0.005, a, M_MSL)
        fin([(-0.46, R * 0.8), (-0.34, R * 0.8), (-0.41, R + 0.05), (-0.46, R + 0.05)], 0.005, a, M_MSL)
    rivets(0.33, R, 24, M_STEEL, 0.001, skip_top=True)
    raceway(-0.4, 0.3, R, -math.pi / 2, M_MSL)
    stencil(-0.12, 0.06, 0.1, R, M_STENCIL_D, 2, 0.003, seed=14)
    shoe(-0.24, 0.18, R * 0.85, 0.068)


# ======================= БЛОКИ НАР =======================
# Тест 3.5-s8, вторая версия (правки по кадру weapons_rockets_after): блок — окрашенный матовым хаки корпус,
# металл только на крепеже и соплах; лепестки обтекателя — отдельная геометрия того же цвета (шов — щель между
# лепестками и их торцы), без тёмных накладок. Габарит и верх (место крепления к пилону) — как у прежних.
M_RKT = paint("rocket_grey", (0.3, 0.31, 0.28), 0.85, ao=0.45, grime=0.15, dust=0.2)


def ring_pts(rings):
    """Центры труб пакета: rings = [(радиус круга, число труб, сдвиг угла)]"""
    out = []
    for rr, n, ph in rings:
        for i in range(n):
            a = ph + 2 * math.pi * i / n
            out.append((math.cos(a) * rr, math.sin(a) * rr))
    return out


def tube_fronts(x_face, pts, rt, depth):
    """Передний срез: торцы труб выступают из переборки на depth, в каждой — головка НАР с взрывателем"""
    for y, z in pts:
        emit(tube_shell(rt, rt * 0.84, depth, 20), M_OLIVE, T(x_face + depth / 2, y, z))
        emit(cyl(rt * 0.84, 0.002, 16), M_DARK, T(x_face + 0.0012, y, z))
        if HQ:
            rn = rt * 0.72
            prof = [(x_face + 0.001, rn)] + ogive(x_face + depth * 0.2, x_face + depth * 0.82, rn, rn * 0.16, 7)
            emit(lathe(prof, 16, False, True), M_RKT, T(0, y, z))
            emit(lathe([(x_face + depth * 0.8, rn * 0.17), (x_face + depth * 0.9, rn * 0.12), (x_face + depth * 0.92, 0)], 10, True, False), M_STEEL, T(0, y, z))
        else:
            emit(cyl(rt * 0.6, depth * 0.6, 8), M_RKT, T(x_face + depth * 0.3, y, z))


def tube_rears(x_face, pts, rt, depth=0.006):
    """Задний срез: сопловые отверстия — короткий раструб из переборки и тёмный канал"""
    for y, z in pts:
        emit(cyl(rt * 0.82, 0.002, 16), M_DARK, T(x_face - depth * 0.6, y, z))
        if HQ:
            emit(tube_shell(rt, rt * 0.82, depth, 20), M_NOZZLE, T(x_face - depth / 2, y, z))
            emit(torus(rt * 0.5, rt * 0.07, 14, 6), M_NOZZLE, T(x_face - depth * 0.55, y, z))
        else:
            emit(tube_shell(rt, rt * 0.8, depth, 10), M_NOZZLE, T(x_face - depth / 2, y, z))


def grille(x, r, step):
    """Защитная решётка заднего среза: тонкие прутья крест-накрест и обод"""
    k = int(r / step)
    for i in range(-k, k + 1):
        c = i * step
        h = 2 * math.sqrt(max(r * r - c * c, 0.0))
        if h < 0.01:
            continue
        emit(box((0.003, 0.0032, h), 0.0008 if HQ else 0.0), M_OLIVE, T(x, c, 0))
        emit(box((0.003, h, 0.0032), 0.0008 if HQ else 0.0), M_OLIVE, T(x - 0.0034, 0, c))
    emit(lathe([(x - 0.006, r * 0.96), (x - 0.006, r * 1.02), (x + 0.002, r * 1.02), (x + 0.002, r * 0.96)], 48, False, False), M_OLIVE)


def petal_nose(xb, xf, R, n, a0=math.pi / 2):
    """Разрушаемый обтекатель из n лепестков: каждый лепесток — отдельный сектор с торцами, между ними узкая
    щель; под щелью — внутренний конус того же цвета (шов читается тенью, не краской)"""
    gap = 0.024 if HQ else 0.04
    prof = ogive(xb, xf, R, R * 0.035, 12)
    emit(lathe(ogive(xb, xf - 0.004, R * 0.94, 0.0, 12), 48), M_OLIVE)
    for k in range(n):
        ac = a0 + 2 * math.pi * k / n
        h = math.pi / n - gap / 2
        emit(lathe_sector(prof, ac - h, ac + h, 14, 0.94), M_OLIVE)
        # петля лепестка у основания и прижимная планка по шву
        rivets(xb + 0.008, R * 0.995, 3, M_STEEL, 0.0016, arc=(ac - h * 0.55, ac + h * 0.55))
        if HQ:
            emit(box((0.003, 0.012, 0.006), 0.001), M_STEEL, surf(xb + 0.006, ac + math.pi / n, R, 0.0012) @ RZ(0))


def pod_shell(x0, xb, R, seams, rear):
    """Корпус блока от заднего среза x0 до основания обтекателя xb. rear = ("flat", r_face) — плоский
    срез с кромкой, ("cone", r_face, длина) — хвостовой конус. Возвращает x и радиус задней переборки"""
    b = 0.006
    if rear[0] == "flat":
        rf, xr = rear[1], x0 + 0.012
        prof = [(xr, rf), (x0, rf), (x0, R * 0.95), (x0 + b * 0.3, R - b * 0.3), (x0 + b, R)]
        body0 = x0 + b
    else:
        rf, ln = rear[1], rear[2]
        xr = x0 + 0.01
        prof = [(xr, rf * 0.94), (x0, rf * 0.94), (x0, rf), (x0 + 0.003, rf * 1.02), (x0 + ln, R)]
        body0 = x0 + ln
    prof += grooves(body0, xb - 0.004, R, seams)[1:] + [(xb - 0.002, R * 0.985), (xb, R * 0.985)]
    emit(lathe(prof, 64, True, True), M_OLIVE)
    for x in seams:
        rivets(x - 0.006, R, 48, M_STEEL, 0.0016, skip_top=True)
        rivets(x + 0.006, R, 48, M_STEEL, 0.0016, skip_top=True)
    return xr, rf


def strap(x, R, w=0.022, lift=0.003):
    """Бандаж: окрашенная лента поверх корпуса, стяжной замок снизу (металл)"""
    ring_band(x - w / 2, x + w / 2, R, M_OLIVE, lift)
    emit(box((w * 1.3, 0.026, 0.012), 0.002), M_STEEL, T(x, 0, -R - 0.006))
    if HQ:
        for sy in (1, -1):
            screw(T(x, sy * 0.009, -R - 0.012) @ RY(math.pi / 2), 0.0026, M_STEEL)
        rivets(x, R + lift, 40, M_STEEL, 0.0013, skip_top=True)


def cable_box(x0, x1, R, a, breaks=()):
    """Кабельный короб вдоль борта (крашеный, с хомутами) с разрывами под бандажи"""
    hgt, w = 0.011, 0.02
    pts = [x0] + [v for x in sorted(breaks) for v in (x - 0.018, x + 0.018)] + [x1]
    for s0, s1 in zip(pts[0::2], pts[1::2]):
        emit(box((hgt, s1 - s0, w), 0.002), M_OLIVE, surf((s0 + s1) / 2, a, R, hgt / 2 - 0.001))
        if HQ:
            k = max(1, int((s1 - s0) / 0.07))
            for i in range(k + 1):
                x = s0 + 0.012 + (s1 - s0 - 0.024) * i / k
                emit(box((0.003, 0.006, w + 0.008), 0.001), M_STEEL, surf(x, a, R, hgt))
    # разъёмы на концах короба
    for x in (x0 - 0.008, x1 + 0.008):
        emit(cyl(0.009, 0.016, 16, 0.002), M_DARK, surf(x, a, R, 0.007) @ RZ(math.pi / 2))


def beam(x0, x1, z, w):
    """Балка-держатель (окрашена) с замками-крюками и винтами (металл)"""
    emit(box((x1 - x0, w, 0.045), 0.006), M_OLIVE, T((x0 + x1) / 2, 0, z))
    emit(box(((x1 - x0) * 0.9, w * 0.6, 0.008), 0.002), M_DARK, T((x0 + x1) / 2, 0, z + 0.025))
    for x in (x0 + 0.12, x1 - 0.12):
        if HQ:
            emit(torus(0.011, 0.0032, 20, 8), M_STEEL, T(x, 0, z + 0.04) @ RZ(math.pi / 2))
            emit(box((0.03, 0.026, 0.012), 0.002), M_STEEL, T(x, 0, z + 0.028))
        else:
            put_z(0.012, 0.03, M_STEEL, x, 0, z + 0.04, 10)
    if HQ:
        for x in [x0 + 0.03 + i * (x1 - x0 - 0.06) / 11 for i in range(12)]:
            for sy in (1, -1):
                screw(T(x, sy * w / 2, z) @ RZ(sy * math.pi / 2), 0.0022, M_STEEL)


def pylon(x0, x1, R):
    """Балка-держатель: скосы на концах, замки, упоры к блоку"""
    z0 = R + 0.012
    emit(prism([(x0, z0), (x1, z0), (x1 - 0.05, z0 + 0.07), (x0 + 0.1, z0 + 0.07)], 0.05, 0.006), M_OLIVE)
    emit(box(((x1 - x0) * 0.6, 0.03, 0.008), 0.002), M_DARK, T((x0 + x1) / 2, 0, z0 + 0.072))
    for x in (x0 + 0.13, x1 - 0.12):
        if HQ:
            emit(torus(0.01, 0.003, 20, 8), M_STEEL, T(x, 0, z0 + 0.082) @ RZ(math.pi / 2))
        else:
            put_z(0.01, 0.03, M_STEEL, x, 0, z0 + 0.08, 10)
    for x in (x0 + 0.15, x1 - 0.15):
        for y in (1, -1):
            rod((x, y * 0.02, z0 + 0.01), (x, y * R * 0.45, R * 0.9), 0.008, M_STEEL)
            emit(box((0.022, 0.018, 0.006), 0.002), M_STEEL, T(x, y * R * 0.45, R * 0.9) @ RX(-y * 0.45))
        emit(box((0.04, 0.04, 0.014), 0.003), M_OLIVE, T(x + 0.06, 0, z0 - 0.004))
    if HQ:
        for i in range(10):
            x = x0 + 0.06 + i * (x1 - x0 - 0.11) / 9
            for y in (1, -1):
                screw(T(x, y * 0.025, z0 + 0.035) @ RZ(y * math.pi / 2), 0.002, M_STEEL)


def petal_pod(x0, xb, xf, R, petals, rear, rings, rt, seams):
    """Блок с лепестковым обтекателем: корпус, хвостовой срез с соплами, нос из лепестков"""
    xr, rf = pod_shell(x0, xb, R, seams, rear)
    tube_rears(xr, ring_pts(rings), rt)
    petal_nose(xb, xf, R, petals)
    return xr, rf


def rockets(t):
    if t == 1:
        # малый блок: цилиндр с утолщённым оживальным носом-обтекателем; спереди — торцы труб с головками НАР,
        # сзади — сопловые отверстия под защитной решёткой
        R, Rb = 0.135, 0.15
        x0, xb, xf = -0.37, 0.19, 0.385
        xr, rf = pod_shell(x0, xb, R, [-0.25, -0.05, 0.12], ("flat", R * 0.9))
        # носовой обтекатель: утолщение-бурт, затем оживало к переднему срезу
        prof = [(xb - 0.002, R * 0.985), (xb + 0.004, R * 1.01), (xb + 0.022, Rb * 0.99), (xb + 0.034, Rb),
                (xb + 0.07, Rb)] + ogive(xb + 0.07, xf, Rb, R * 0.68, 10)[1:] + [(xf, R * 0.66), (xf - 0.02, R * 0.66)]
        emit(lathe(prof, 64, False, True), M_OLIVE)
        if HQ:
            rivets(xb + 0.052, Rb, 44, M_STEEL, 0.0016, skip_top=True)
            for k in range(4):   # лючки замков обтекателя
                a = -math.pi / 2 + (k - 1.5) * 0.7
                patch(xb + 0.04, xb + 0.064, a - 0.09, a + 0.09, Rb, M_OLIVE, 0.0008, 1, 2)
                rivets(xb + 0.052, Rb + 0.0008, 2, M_STEEL, 0.0013, arc=(a - 0.07, a + 0.07))
        pts = ring_pts([(0.0, 1, 0.0), (R * 0.4, 6, math.pi / 2)])
        tube_fronts(xf - 0.02, pts, R * 0.13, 0.017)
        tube_rears(xr, pts, R * 0.13)
        grille(x0 + 0.004, rf, 0.016)
        for x in (-0.2, 0.06):
            strap(x, R)
        beam(-0.3, 0.26, Rb + 0.04, 0.07)
        for x in (-0.18, 0.0, 0.16):   # упоры между корпусом и балкой
            emit(box((0.045, 0.05, 0.036), 0.004), M_OLIVE, T(x, 0, R + 0.016))
        if HQ:   # электроразъём с кабелем к балке
            put_z(0.012, 0.02, M_DARK, 0.1, 0.03, R + 0.006, 16, 0.002)
            rod((0.1, 0.03, R + 0.016), (0.12, 0.03, Rb + 0.02), 0.004, M_DARK)
            stencil(-0.16, 0.08, 0.05, R, M_STENCIL, 3, 0.006, seed=21)
            stencil(-0.16, 0.08, math.pi - 0.05, R, M_STENCIL, 3, 0.006, seed=22)
    elif t == 2:
        # средний блок: длиннее и толще, нос из 6 лепестков, сзади хвостовой конус с соплами
        R = 0.15
        petal_pod(-0.48, 0.16, 0.5, R, 6, ("cone", R * 0.72, 0.08),
                  [(0.0, 1, 0.0), (R * 0.3, 6, math.pi / 2), (R * 0.56, 10, math.pi / 2 + 0.31)], R * 0.085,
                  [-0.36, -0.12, 0.08])
        for x in (-0.3, 0.0):
            strap(x, R)
        pylon(-0.4, 0.14, R)
        if HQ:
            stencil(-0.24, -0.04, 0.05, R, M_STENCIL, 3, 0.006, seed=23)
            stencil(-0.24, -0.04, math.pi - 0.05, R, M_STENCIL, 3, 0.006, seed=24)
    else:
        # большой блок: ещё крупнее, 21 труба, два силовых бандажа, нос из 8 лепестков, кабельный короб по борту
        R = 0.2
        petal_pod(-0.5, 0.2, 0.5, R, 8, ("cone", R * 0.8, 0.07),
                  [(0.0, 1, 0.0), (R * 0.28, 7, math.pi / 2), (R * 0.54, 13, math.pi / 2 + 0.24)], R * 0.075,
                  [-0.38, -0.12, 0.1])
        for x in (-0.25, 0.0):
            strap(x, R, 0.03, 0.004)
        cable_box(-0.42, 0.17, R, 0.62, (-0.25, 0.0))
        pylon(-0.38, 0.2, R)
        if HQ:
            stencil(-0.2, -0.04, -0.15, R, M_STENCIL, 3, 0.007, seed=25)
            stencil(0.04, 0.16, math.pi + 0.15, R, M_STENCIL, 3, 0.007, seed=26)


def rockets_evo():
    # «Ливень»: тройка блоков с лепестковыми обтекателями на общем переходнике-балке; между блоками — обтекатели,
    # сверху — узел крепления к пилону (тот же верх габарита, что у прежней модели)
    R, sp = 0.095, 0.25
    x0, xb, xn = -0.38, 0.17, 0.43
    rings = [(0.0, 1, 0.0), (R * 0.42, 6, math.pi / 2)]
    for y in (-sp, 0.0, sp):
        with xf(T(0, y, 0)):
            petal_pod(x0, xb, xn, R, 6, ("cone", R * 0.74, 0.06), rings, R * 0.13, [-0.26, -0.02])
            for x in (-0.2, 0.08):
                strap(x, R, 0.018, 0.0025)
    # обтекатели между блоками: клин, утопленный в соседние корпуса; нос скошен вниз
    for y in (-sp / 2, sp / 2):
        out = [(x0 + 0.04, R * 0.1), (xb + 0.06, R * 0.1), (xb - 0.04, R + 0.02), (x0 + 0.08, R + 0.02)]
        emit(prism(out, sp - 1.4 * R, 0.004), M_OLIVE, T(0, y, 0))
        if HQ:
            for x in [x0 + 0.1 + i * 0.06 for i in range(8)]:
                screw(T(x, y, R + 0.02) @ RY(-math.pi / 2), 0.0022, M_STEEL)
    # переходник-балка поперёк блоков с ложементами и стяжками
    zb = R + 0.032
    for xc in (-0.17, 0.09):
        emit(box((0.07, 2 * sp + 0.12, 0.03), 0.005), M_OLIVE, T(xc, 0, zb))
        for y in (-sp, 0.0, sp):
            emit(box((0.06, 0.07, 0.02), 0.004), M_OLIVE, T(xc, y, R + 0.008))
            if HQ:
                for sy in (1, -1):
                    screw(T(xc, y + sy * 0.036, zb) @ RZ(sy * math.pi / 2), 0.0024, M_STEEL)
    emit(box((0.33, 0.06, 0.028), 0.005), M_OLIVE, T(-0.04, 0, zb))
    # узел крепления к пилону: короб с замками-крюками и упорами
    zt = zb + 0.015
    emit(prism([(-0.26, zt), (0.18, zt), (0.13, zt + 0.055), (-0.2, zt + 0.055)], 0.05, 0.006), M_OLIVE)
    emit(box((0.26, 0.03, 0.006), 0.002), M_DARK, T(-0.04, 0, zt + 0.057))
    for x in (-0.15, 0.07):
        if HQ:
            emit(torus(0.009, 0.0028, 20, 8), M_STEEL, T(x, 0, zt + 0.064) @ RZ(math.pi / 2))
        else:
            put_z(0.009, 0.024, M_STEEL, x, 0, zt + 0.064, 10)
        for y in (1, -1):
            rod((x + 0.02, y * 0.02, zt + 0.03), (x + 0.02, y * 0.11, zt), 0.006, M_STEEL)
    if HQ:
        for i in range(8):
            x = -0.22 + i * 0.05
            for y in (1, -1):
                screw(T(x, y * 0.025, zt + 0.028) @ RZ(y * math.pi / 2), 0.002, M_STEEL)
        for y in (-sp, sp):
            stencil(-0.2, -0.04, math.pi / 2 + (0.9 if y > 0 else -0.9), R, M_STENCIL, 2, 0.005, yz=(y, 0), seed=27)


# ======================= ЛОВУШКИ =======================
def cassette_block(ln, w, h, rows, cols, ramp=False):
    """Кассета ловушек: корпус с фаской, рамка, ряды ячеек с латунными торцами патронов; ячейки на верхней грани"""
    emit(box((ln, w, h), min(h, w) * 0.12), M_CASE)
    if ramp:
        emit(prism([(ln / 2, -h / 2), (ln / 2 + h * 2.6, -h / 2), (ln / 2, h / 2)], w * 0.96, 0.002), M_CASE)
    emit(box((ln * 0.93, w * 0.88, 0.004), 0.0012), M_DARK, T(0, 0, h / 2 + 0.001))
    for i in range(cols):
        for j in range(rows):
            x = (i - (cols - 1) / 2) * ln * 0.86 / cols
            yy = (j - (rows - 1) / 2) * w * 0.8 / rows
            rc = w * 0.34 / rows
            with xf(T(x, yy, 0) @ RY(-math.pi / 2)):
                if HQ:
                    emit(tube_shell(rc, rc * 0.84, 0.006, 16), M_DARK, T(h / 2 + 0.002, 0, 0))
                    emit(cyl(rc * 0.82, 0.003, 16, 0.0006), M_BRASS, T(h / 2 + 0.0015, 0, 0))
                    emit(cyl(rc * 0.25, 0.002, 10), M_STEEL, T(h / 2 + 0.0035, 0, 0))
                else:
                    emit(cyl(rc, 0.004, 10), M_DARK, T(h / 2 + 0.003, 0, 0))
                    emit(cyl(rc * 0.74, 0.004, 10), M_BRASS, T(h / 2 + 0.005, 0, 0))
    for xx in (ln * 0.44, -ln * 0.44):
        emit(box((0.008, w * 1.004, h * 1.004)), M_RED, T(xx, 0, 0))
    if HQ:
        for sx in (1, -1):
            for sy in (1, -1):
                screw(T(sx * ln * 0.47, sy * w * 0.47, h / 2 + 0.002) @ RY(-math.pi / 2), 0.003, M_STEEL)
        for sy in (1, -1):
            for i in range(6):
                screw(T((i - 2.5) * ln * 0.15, sy * w * 0.5, 0) @ RZ(sy * math.pi / 2), 0.0022, M_STEEL)


def flares(t):
    if t == 1:
        with xf(T(0, 0, 0.022)):
            cassette_block(0.5, 0.28, 0.044, 3, 7, True)
    elif t == 2:
        with xf(T(0, 0, 0.025)):
            cassette_block(0.72, 0.38, 0.05, 4, 9, True)
    else:
        Hh = 0.07
        emit(box((0.6, 0.15, Hh * 2), 0.02), M_CASE)
        emit(sphere(1.0, 32), M_CASE, T(0.3, 0, 0) @ SC(0.17, 0.075, Hh))
        emit(prism([(-0.3, -Hh), (-0.4, -Hh * 0.4), (-0.4, Hh * 0.4), (-0.3, Hh)], 0.15, 0.01), M_CASE)
        for sz in (1, -1):
            with xf(T(-0.03, 0, sz * (Hh + 0.012)) @ (RX(math.pi) if sz < 0 else Matrix.Identity(4))):
                cassette_block(0.5, 0.14, 0.03, 2, 8)
        for x in (0.2, -0.29):
            emit(box((0.014, 0.154, Hh * 2.04)), M_DARK, T(x, 0, 0))
        if HQ:
            for x in (0.25, 0.27, -0.33):
                for sy in (1, -1):
                    screw(T(x, sy * 0.075, 0) @ RZ(sy * math.pi / 2), 0.0025, M_STEEL)


def flares_evo():
    # «Салют»: на спине поворотная пусковая, на ней веером три кассеты ловушек
    put_z(0.2, 0.04, M_STEEL, 0, 0, 0.02, 64, 0.006)
    put_z(0.17, 0.012, M_DARK, 0, 0, 0.045, 64, 0.002)
    emit(box((0.16, 0.5, 0.05), 0.008), M_CASE, T(0, 0, 0.085))
    for y in (0.21, -0.21):
        emit(box((0.12, 0.03, 0.11), 0.006), M_CASE, T(0, y, 0.13))
    emit(cyl(0.022, 0.48, 20, 0.003), M_STEEL, T(0, 0, 0.16) @ RZ(math.pi / 2))
    if HQ:
        for k in range(20):
            a = 2 * math.pi * k / 20
            screw(T(math.cos(a) * 0.185, math.sin(a) * 0.185, 0.04) @ RY(-math.pi / 2), 0.004, M_STEEL)
        for y in (0.245, -0.245):
            emit(cyl(0.035, 0.008, 24, 0.002), M_STEEL, T(0, y, 0.16) @ RZ(math.pi / 2))
    for y, splay in ((0.0, 0.0), (0.175, -0.28), (-0.175, 0.28)):
        with xf(T(-0.02, y, 0.2 + abs(y) * 0.05) @ RX(splay) @ RY(-0.6)):
            cassette_block(0.36, 0.13, 0.075, 3, 6)


# ======================= ЭКСПЕРИМЕНТАЛЬНОЕ =======================
def exp(kind):
    if kind == "railgun":
        M_COIL = glow("glow_blue", (0.2, 0.6, 1.0), 0.9)
        emit(box((0.9, 0.11, 0.05), 0.008), M_HULL, T(-0.05, 0, 0.0))
        for y in (0.035, -0.035):
            emit(box((0.94, 0.018, 0.045), 0.004), M_DARK, T(0.03, y, 0.035))
            if HQ:   # болты крепления шин и изоляторы
                for i in range(16):
                    x = -0.42 + i * 0.058
                    screw(T(x, y + 0.009 * (1 if y > 0 else -1), 0.035) @ RZ((1 if y > 0 else -1) * math.pi / 2), 0.0025, M_STEEL)
                emit(box((0.9, 0.006, 0.008), 0.001), M_COPPER, T(0.03, y * 0.72, 0.052))
        for i in range(7):
            x = -0.32 + i * 0.12
            if HQ:   # катушка: обойма, витки, светящееся ядро
                emit(tube_shell(0.06, 0.044, 0.03, 48), M_DARK, T(x, 0, 0.035))
                for j in range(4):
                    emit(torus(0.052, 0.0035, 48, 8), M_COPPER, T(x - 0.0105 + j * 0.007, 0, 0.035))
                emit(torus(0.045, 0.004, 48, 8), M_COIL, T(x, 0, 0.035))
            else:
                emit(torus(0.05, 0.009, 20, 6), M_COIL, T(x, 0, 0.035))
        emit(box((0.03, 0.1, 0.07), 0.004), M_STEEL, T(0.49, 0, 0.035))
        if HQ:
            emit(box((0.034, 0.03, 0.024), 0.002), M_DARK, T(0.49, 0, 0.035))
        emit(box((0.26, 0.15, 0.1), 0.012), M_HULL, T(-0.38, 0, 0.0))
        for i in range(5):
            emit(box((0.012, 0.155, 0.012), 0.002), M_DARK, T(-0.46 + i * 0.04, 0, 0.055))
        if HQ:   # кабели от накопителей к катушкам, жалюзи
            for y in (0.05, -0.05):
                rod((-0.25, y, 0.03), (-0.1, y * 0.9, 0.03), 0.006, M_DARK)
                for i in range(7):
                    emit(box((0.18, 0.002, 0.006), 0.0008), M_DARK, T(-0.38, y * 1.52, -0.03 + i * 0.01))
            stencil(-0.48, -0.3, 0.0, 0.075, M_STENCIL, 2, 0.006, seed=31)
        for x in (-0.3, 0.1):
            lug(x, 0.055, M_STEEL, 1.1)
    elif kind == "emp":
        M_DOME = glow("glow_blue", (0.25, 0.65, 1.0), 0.9)
        R = 0.11
        prof = [(-0.37, R * 0.95), (-0.365, R)] + grooves(-0.365, 0.245, R, [-0.25, 0.15])[1:] + [(0.25, R * 0.98)]
        emit(lathe(prof, 64), M_HULL)
        emit(sphere(R * 0.97, 48), M_DOME, T(0.25, 0, 0) @ SC(1.25, 1, 1))
        emit(torus(R, 0.01, 64, 10), M_DARK, T(0.245, 0, 0))
        if HQ:   # решётка-излучатель поверх купола
            for k in range(8):
                a = 2 * math.pi * k / 8
                pts = [(0.25 + R * 1.25 * math.sin(q * math.pi / 2 / 8), R * 1.0 * math.cos(q * math.pi / 2 / 8)) for q in range(9)]
                for (x0, r0), (x1, r1) in zip(pts, pts[1:]):
                    rod((x0, math.cos(a) * r0, math.sin(a) * r0), (x1, math.cos(a) * r1, math.sin(a) * r1), 0.0035, M_DARK, 8)
        for i in range(6):
            x = -0.12 + i * 0.03
            if HQ:
                for j in range(3):
                    emit(torus(R * 1.04, 0.004, 64, 8), M_COPPER, T(x - 0.009 + j * 0.009, 0, 0))
            else:
                emit(torus(R * 1.04, 0.012, 28, 6), M_COPPER, T(x, 0, 0))
        emit(lathe([(-0.47, R * 0.6), (-0.37, R * 0.7)], 48), M_DARK)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            fin([(-0.47, R * 0.6), (-0.33, R * 0.7), (-0.37, R * 0.7 + 0.08), (-0.47, R * 0.7 + 0.08)], 0.006, a, M_DARK)
        rivets(-0.25, R, 48, M_STEEL, 0.0016, skip_top=True)
        rivets(0.15, R, 48, M_STEEL, 0.0016, skip_top=True)
        stencil(-0.33, -0.2, 0.05, R, M_STENCIL, 3, 0.006, seed=32)
        for x in (-0.2, 0.08):
            lug(x, R + 0.002, M_STEEL, 1.1)
    elif kind == "laser":
        M_LENS = glow("glow_orange", (1.0, 0.4, 0.05), 1.0)
        R = 0.085
        prof = dome_prof(-0.41, R, -R * 0.8, 8)[::-1] + grooves(-0.41, 0.25, R, [-0.3, 0.0, 0.18])[1:] + [(0.25, R * 0.95)]
        emit(lathe(prof, 56), M_HULL)
        for s in (1, -1):   # рёбра охлаждения по бокам
            n = 17 if HQ else 9
            for i in range(n):
                emit(box((0.006 if HQ else 0.012, 0.03, R * 1.3), 0.0015), M_DARK, T(-0.3 + i * 0.4 / (n - 1), s * (R + 0.012), 0.0))
            emit(box((0.43, 0.006, 0.012), 0.002), M_STEEL, T(-0.1, s * (R + 0.003), R * 0.62))
            emit(box((0.43, 0.006, 0.012), 0.002), M_STEEL, T(-0.1, s * (R + 0.003), -R * 0.62))
        emit(lathe([(0.24, R * 0.85), (0.3, R * 0.85)], 48, False, False), M_DARK)
        emit(sphere(R * 1.05, 48), M_STEEL, T(0.36, 0, -0.01))
        emit(torus(R * 1.05, 0.004, 48, 8), M_DARK, T(0.36, 0, -0.01) @ RZ(math.pi / 2))
        with xf(T(0.36, 0, -0.01) @ RY(math.radians(18))):
            emit(cyl(R * 0.45, 0.012, 40), M_LENS, T(0.08, 0, -0.02))
            emit(torus(R * 0.5, 0.008, 40, 8), M_DARK, T(0.083, 0, -0.02))
            if HQ:
                emit(torus(R * 0.58, 0.004, 40, 8), M_STEEL, T(0.08, 0, -0.02))
                for k in range(8):
                    a = 2 * math.pi * k / 8
                    screw(T(0.086, math.cos(a) * R * 0.54, -0.02 + math.sin(a) * R * 0.54), 0.0025, M_STEEL)
        rivets(0.18, R, 40, M_STEEL, 0.0015, skip_top=True)
        stencil(-0.38, -0.32, -math.pi / 2 + 0.6, R, M_STENCIL, 2, 0.005, seed=33)
        for x in (-0.22, 0.1):
            lug(x, R + 0.002, M_STEEL, 1.0)
    elif kind == "plasma":
        M_CORE = glow("glow_violet", (0.65, 0.2, 1.0), 0.9)
        R = 0.1
        emit(sphere(R * 0.95, 48), M_CORE, SC(1.35, 1, 1))
        for i in range(3):
            emit(torus(R * 1.05, 0.008, 56, 8), M_DARK, RX(i * math.pi / 3) @ SC(1.35, 1, 1) @ RZ(math.pi / 2))
        for i in range(6 if HQ else 0):
            emit(torus(R * 1.07, 0.0035, 56, 6), M_STEEL, RX(i * math.pi / 6 + math.pi / 12) @ SC(1.35, 1, 1) @ RZ(math.pi / 2))
        emit(torus(R * 1.07, 0.012, 56, 10), M_STEEL)
        emit(lathe([(0.14, R * 0.75), (0.2, R * 0.75)], 48, True, False), M_HULL)
        emit(lathe(ogive(0.2, 0.36, R * 0.75, 0.004, 12) + [(0.36, 0)], 48, False, True), M_HULL)
        emit(lathe([(-0.21, R * 0.45), (-0.21, R * 0.75), (-0.15, R * 0.75)], 48, False, True), M_HULL)
        emit(lathe([(-0.4, R * 0.4), (-0.4, R * 0.45), (-0.21, R * 0.45)], 40, True, False), M_HULL)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            fin([(-0.425, R * 0.45), (-0.3, R * 0.45), (-0.34, R * 0.45 + 0.09), (-0.425, R * 0.45 + 0.09)], 0.006, a, M_DARK)
        emit(tube_shell(R * 0.95 + 0.006, R * 0.95 - 0.004, 0.05, 48), M_DARK, T(-0.39, 0, 0))
        rivets(0.17, R * 0.75, 32, M_STEEL, 0.0014, skip_top=True)
        rivets(-0.18, R * 0.75, 32, M_STEEL, 0.0014, skip_top=True)
        stencil(0.21, 0.3, 0.1, lambda x: R * 0.75 * max(0.3, 1 - ((x - 0.2) / 0.16) ** 2) ** 0.5, M_STENCIL, 2, 0.004, seed=34)
        for x in (-0.1, 0.1):
            lug(x, R * 0.95 + 0.002, M_STEEL, 1.0)
    else:
        raise SystemExit("неизвестное оружие " + kind)


# ======================= сборка =======================
name = None
if kind == "bombs":
    if tier == "evo":
        # «Бабушкин ковёр»: планка поперёк полёта, под ней 8 бомб «250»
        emit(box((0.22, 1.7, 0.05), 0.008), M_STEEL, T(0, 0, 0.13))
        emit(box((0.12, 1.6, 0.012), 0.003), M_DARK, T(0, 0, 0.16))
        emit(box((0.18, 0.18, 0.06), 0.008), M_DARK, T(0, 0, 0.2))
        if HQ:
            for i in range(30):
                for sx in (1, -1):
                    screw(T(sx * 0.11, (i - 14.5) * 0.055, 0.13) @ RZ(0 if sx > 0 else math.pi), 0.0025, M_STEEL)
        for i in range(8):
            y = (i - 3.5) * 0.21
            emit(box((0.05, 0.03, 0.03), 0.004), M_DARK, T(0, y, 0.095))
            bomb(0.62, 0.075, 3, 0.0, y, 0.0, evo=True)
        name = "bombs_evo"
    elif tier == "evobay":
        # «ковёр» у «Кита»: кассета внутри отсека, 4 ряда по 2 бомбы (точки — WeaponModels.CARPET_BAY_PTS)
        emit(box((1.86, 0.07, 0.024), 0.004), M_STEEL, T(0, 0, 0.118))
        for y in (0.13, -0.13):
            emit(box((1.86, 0.022, 0.05), 0.003), M_DARK, T(0, y, 0.09))
        for x in (-0.92, -0.44, 0.0, 0.44, 0.92):
            emit(box((0.03, 0.28, 0.05), 0.003), M_STEEL, T(x, 0, 0.095))
        for x in (-0.66, -0.22, 0.22, 0.66):
            for y in (0.072, -0.072):
                emit(box((0.1, 0.022, 0.03), 0.002), M_DARK, T(x + 0.02, y, 0.072))
                bomb(0.4, 0.058, 3, x, y, 0.0, evo=True)
        name = "bombs_evo_bay"
    else:
        n = int(tier)
        L, R = LADDER[n]
        bomb(L, R, n)
        name = "bombs_%d" % n
elif kind == "bombdrop":
    # бомба «ковра» для падения в бою: та же «250» с двойным поясом, длина 1
    bomb(1.0, 0.075 / 0.62, 3, evo=True)
    name = "bombdrop_evo"
elif kind == "aam":
    aam_evo() if tier == "evo" else aam(int(tier))
    name = "aam_" + tier
elif kind == "arm":
    arm()
    name = "arm_1"
elif kind == "rockets":
    rockets_evo() if tier == "evo" else rockets(int(tier))
    name = "rockets_" + tier
elif kind == "flares":
    flares_evo() if tier == "evo" else flares(int(tier))
    name = "flares_" + tier
elif kind == "exp":
    exp(tier)
    name = "exp_" + tier
else:
    raise SystemExit("неизвестный вид " + kind)

build(name, OUT, 1024 if kind != "rockets" and tier not in ("evo", "evobay") else 2048, BLEND)
print("DONE", name)
