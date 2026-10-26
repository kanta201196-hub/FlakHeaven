"""Ступени 2 и 3 для оружия из Sketchfab (3.5-s12, Kanta: «ракета В-З при прокачке в ангаре не меняется»,
«фугасная — все уровни одинаковые»). В PG-01 одна модель Sketchfab (sf_weapon_prep.py) стала всеми тремя
ступенями; здесь к модели ступени 1 добавляются детали кодом (hq_lib), так что ступень видна издали:
  srm   2 — пояса, кольцо у носа, гаргрот; 3 — ещё длинные гребни вдоль корпуса и тёмный обтекатель головки
  agm   2 — пояса, передние рули, гаргрот; 3 — ещё гребни, окно лазерной головки и антенна линии связи
  hebomb 2 — штанга-удлинитель взрывателя с диском (рвёт над землёй) и пояса; 3 — ещё баллистическое кольцо
              на носу и усиленный ложемент с ушками
Размеры — по замеру моделей ступени 1 (радиус корпуса, место оперения); длина и оси прежние (нос +X, длина 1).
«По мотивам»: без надписей и эмблем, пояса — только маркировка.
Запуск (bpy 5.x): python3.11 sf_tiers.py <srm|agm|hebomb> <2|3> <in tier-1 .glb> <out_dir> [--battle]"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import hq_lib as H
from hq_lib import *

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
kind, tier, src, OUT = ARGS[0], int(ARGS[1]), ARGS[2], ARGS[3]
BATTLE = "--battle" in sys.argv
H.reset(not BATTLE)
bpy.ops.import_scene.gltf(filepath=src)
base = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(False)

M_YELLOW = paint("t_yellow", (0.56, 0.43, 0.045), 0.84, ao=0.4, grime=0.12)
M_BROWN = paint("t_brown", (0.33, 0.2, 0.09), 0.84, ao=0.4, grime=0.1)
M_DARK = paint("t_dark", (0.05, 0.05, 0.055), 0.86, ao=0.4, grime=0.05, dust=0.05)
M_BODY = paint("t_body", (0.085, 0.08, 0.045), 0.86, ao=0.5, grime=0.15, dust=0.2)   # тон корпуса Sketchfab-модели
M_WHITE = paint("t_white", (0.55, 0.56, 0.54), 0.84, ao=0.5, grime=0.12, dust=0.2)   # тон корпуса srm
M_OLIVE = paint("t_olive", (0.17, 0.18, 0.12), 0.87, ao=0.5, grime=0.2, dust=0.3)
M_STEEL = metal("t_steel", (0.36, 0.36, 0.37), 0.48, 0.7)
M_GLASS = glass("t_glass", (0.08, 0.12, 0.14))


def band(x0, x1, r, m):
    """Цветной пояс поверх корпуса"""
    emit(lathe([(x0, r + 0.0008), (x1, r + 0.0008)], S(56), False, False), m)


def fin(outline, thick, ang, m):
    """Перо: контур (x, s) — s от оси наружу; поворот вокруг оси X"""
    emit(prism(outline, thick, thick * 0.4, 2), m, RX(ang))


def raceway(x0, x1, r, m):
    """Гаргрот кабелей сверху (сторона пилона — +Z)"""
    emit(box((x1 - x0, r * 0.32, r * 0.22), r * 0.05), m, T((x0 + x1) / 2, 0, r + r * 0.08))


def nose_ring(x, r, m):
    """Кольцо-обойма корпуса (стык отсеков)"""
    emit(tube_shell(r * 1.06, r * 0.98, 0.012, S(48)), m, T(x, 0, 0))


if kind == "agm":
    R = 0.060
    band(0.12, 0.138, R, M_YELLOW)
    band(0.15, 0.168, R, M_YELLOW)
    raceway(-0.36, 0.22, R, M_BODY)
    for k in range(4):   # передние рули у головки
        fin([(0.3, R * 0.85), (0.37, R * 0.85), (0.33, R + 0.035)], 0.004, math.pi / 4 + k * math.pi / 2, M_BODY)
    if tier == 3:
        band(-0.27, -0.25, R, M_BROWN)
        for k in range(4):   # длинные гребни вдоль корпуса между крыльями
            fin([(-0.42, R * 0.9), (-0.33, R * 0.9), (-0.36, R + 0.018), (-0.41, R + 0.018)], 0.004, k * math.pi / 2, M_BODY)
            fin([(0.16, R * 0.9), (0.28, R * 0.9), (0.26, R + 0.014), (0.18, R + 0.014)], 0.003, k * math.pi / 2, M_BODY)
        # лазерная головка вместо телевизионной: тёмный гранёный обтекатель поверх носа и окно
        emit(lathe([(0.38, R * 1.06), (0.44, R * 1.06), (0.48, R * 0.92), (0.5, R * 0.68), (0.514, R * 0.36), (0.514, 0)], 8), M_DARK)
        emit(box((0.004, R * 0.5, R * 0.36), 0.0008), M_GLASS, T(0.5155, 0, 0))
        emit(cyl(0.004, 0.06, S(12)), M_STEEL, T(-0.44, 0, R + 0.03) @ RY(-math.pi / 2))   # антенна линии связи
        emit(box((0.03, 0.012, 0.008), 0.002), M_DARK, T(-0.44, 0, R + 0.062))
elif kind == "srm":
    R = 0.037
    band(0.2, 0.215, R, M_YELLOW)
    band(-0.1, -0.085, R, M_BROWN)
    nose_ring(0.33, R, M_STEEL)
    raceway(-0.28, 0.3, R, M_WHITE)
    if tier == 3:
        for k in range(4):   # длинные гребни: ракета манёвреннее
            fin([(-0.24, R * 0.9), (0.24, R * 0.9), (0.2, R + 0.016), (-0.2, R + 0.016)], 0.003, math.pi / 4 + k * math.pi / 2, M_WHITE)
        emit(lathe(ogive(0.42, 0.5, R * 1.02, R * 0.32, 10) + [(0.5, 0)], S(40), False, True), M_DARK)   # тёмный обтекатель
        band(0.23, 0.245, R, M_YELLOW)
else:   # hebomb
    R = 0.128
    x_nose = 0.5
    band(0.12, 0.15, R, M_YELLOW)
    band(-0.17, -0.14, R * 1.03, M_YELLOW)
    # штанга-удлинитель взрывателя с диском на конце
    rod((x_nose - 0.02, 0, 0), (x_nose + 0.13, 0, 0), 0.011, M_STEEL, S(16))
    emit(cyl(0.032, 0.008, S(24), 0.0015), M_STEEL, T(x_nose + 0.13, 0, 0))
    emit(cyl(0.018, 0.02, S(20), 0.002), M_DARK, T(x_nose + 0.005, 0, 0))
    if tier == 3:
        # баллистическое кольцо на носу на 4 стойках
        xr, rr = 0.36, 0.105
        emit(tube_shell(rr + 0.008, rr, 0.03, S(48)), M_OLIVE, T(xr, 0, 0))
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            emit(box((0.024, 0.004, rr - 0.08), 0.0008), M_OLIVE, T(xr, math.cos(a) * (rr + 0.08) / 2, math.sin(a) * (rr + 0.08) / 2) @ RX(a - math.pi / 2))
        # усиленный ложемент с двумя ушками
        emit(box((0.3, R * 0.5, 0.008), 0.002), M_STEEL, T(0.0, 0, R + 0.002))
        for x0 in (-0.08, 0.08):
            lug(x0, R + 0.006, M_STEEL, 1.6)
        band(-0.02, 0.01, R, M_BROWN)

build("%s_%d" % (kind, tier), OUT, 512, join=base)
