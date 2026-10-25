"""Спаренная турель «Кита» (по референсу владельца 16.10): основание-погон, бронированная
башня с плитами сверху, люлька и два ствола с дульными тормозами.
Запуск (bpy 5.x):  python3 turret_twin.py [t1|t2|t3|quad] [nopreview] <out_dir>
Ступени (Т-4, plan-after-review 3.6 — меняют форму и детали, не размер; по умолчанию t2):
  t1 (ур. 1–2) — спарка без дульных тормозов, простой маск;
  t2 (ур. 3–4) — дульные тормоза и бронещиток перед люлькой;
  t3 (ур. 5)   — то же + короба лент по бокам и прицельная головка сверху.
quad — эволюция «Дикобраз» (одобрена 16.10): 4 ствола двумя парами и антенна наведения сверху.
Стволы укорочены на ~40% по замечанию владельца 16.10 («не слишком ли длинные стволы»).
Выход: turret_twin_t<N>.blend / .glb (quad — turret_twin_quad) (ось стволов +X, верх +Y в Godot, начало — центр погона),
       preview_*.png. Единица — длина башни (без стволов) = 1."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L


def twin(TIER=2, QUAD=False, M_BODY=None, M_DARK=None, M_BARREL=None, M_GLASS=None, base="", guns="guns", seg=1.0,
         detail=False):
    """Геометрия спаренной турели в своих единицах (длина башни = 1, начало — центр погона).
    base — группа неподвижной части (у «Крепости» — узел turret_N), guns — группа люльки со стволами
    (может совпадать с base); seg — множитель числа граней цилиндров (для облегчённой модели боя);
    detail — hangar close-up detail (S11-13): ring bolts, hatch, vision blocks, rivets, lifting eyes,
    recoil cylinders, cable conduit. Off for the Fortress, whose turrets are a few pixels in battle."""
    def c(name, cc, r, h, m, axis="Z", verts=24, bevel=0.0):
        return cyl(name, cc, r, h, m, axis, max(8, int(round(verts * seg))), bevel)
    L.group = base
    # --- погон и тумба ---
    c("ring", (0, 0, 0.04), 0.44, 0.08, M_BODY, bevel=0.015)
    c("ring_top", (0, 0, 0.09), 0.36, 0.03, M_DARK, bevel=0.005)
    c("pedestal", (-0.02, 0, 0.15), 0.25, 0.12, M_BODY, bevel=0.01)
    box("bracket_l", (0.18, 0.2, 0.17), (0.12, 0.05, 0.12), M_BODY, 0.01)
    box("bracket_r", (0.18, -0.2, 0.17), (0.12, 0.05, 0.12), M_BODY, 0.01)

    # --- башня: две бронированные половины с проёмом под люльку посередине ---
    Z0, Z1 = 0.2, 0.62
    side = [(-0.58, Z0), (0.26, Z0), (0.44, Z0 + 0.14), (0.44, Z1 - 0.04), (0.38, Z1), (-0.58, Z1)]
    for sgn in (1, -1):
        prism("hull_%d" % sgn, side, 0.36, M_BODY).location.y = sgn * 0.27
        # плиты сверху 2×1 на половину
        for x in (-0.33, 0.12):
            box("plate", (x, sgn * 0.27, Z1 + 0.012), (0.4, 0.3, 0.03), M_BODY, 0.008)
        # боковые накладки с фаской
        box("side_panel", (-0.1, sgn * 0.455, 0.42), (0.6, 0.02, 0.2), M_BODY, 0.01)
        box("side_panel2", (0.25, sgn * 0.452, 0.36), (0.18, 0.02, 0.14), M_BODY, 0.008)
    # перемычка сзади и снизу (единый корпус)
    box("bridge_back", (-0.3, 0, 0.41), (0.56, 0.14, 0.42), M_BODY, 0.01)
    box("bridge_floor", (0.0, 0, 0.24), (0.9, 0.2, 0.08), M_BODY, 0.01)

    # --- люлька и стволы ---
    BZ = 0.43
    # тест 3.5-s8 (анимация в ангаре): люлька и стволы — отдельный узел «guns», шарнир — цапфы люльки
    # (качание стволами по углу места вокруг оси Y Blender); бронещиток, короба и рукава остаются на башне
    L.group = guns
    L.pivots[guns] = (0.3, 0, BZ)
    LEVELS = [BZ + 0.06, BZ - 0.06] if QUAD else [BZ]
    box("cradle", (0.42, 0, BZ), (0.5, 0.17, 0.13 + (0.12 if QUAD else 0)), M_BODY, 0.015)
    box("mantlet", (0.68, 0, BZ), (0.08, 0.26, 0.11 + (0.12 if QUAD else 0)), M_DARK, 0.01)
    L.group = base
    if TIER >= 2 and not QUAD:
        # бронещиток: широкая плита перед люлькой, скошена назад, с вырезами под стволы
        shield = [(0.7, Z0 + 0.04), (0.76, Z0 + 0.1), (0.76, Z1 - 0.06), (0.7, Z1 + 0.02), (0.64, Z1 + 0.02), (0.64, Z0 + 0.04)]
        for sgn in (1, -1):
            prism("shield_%d" % sgn, shield, 0.2, M_BODY, 0.01).location.y = sgn * 0.2
        box("shield_top", (0.7, 0, Z1 - 0.01), (0.1, 0.2, 0.05), M_BODY, 0.008)
    L.group = guns
    for bz in LEVELS:
        for sgn in (1, -1):
            y = sgn * 0.075
            c("sleeve", (0.86, y, bz), 0.05, 0.36, M_BARREL, "X")
            for x in (0.74, 0.86, 1.02):
                c("collar", (x, y, bz), 0.058, 0.035, M_BARREL, "X")
            c("barrel", (1.48, y, bz), 0.028, 0.9, M_BARREL, "X", 16)
            for x in (1.2, 1.26, 1.74, 1.8):
                c("band", (x, y, bz), 0.036, 0.03, M_BARREL, "X", 16)
            if TIER >= 2:
                # дульный тормоз: короб с двумя окнами
                box("brake", (2.0, y, bz), (0.17, 0.07, 0.07), M_BARREL, 0.006)
                for x in (1.96, 2.05):
                    box("brake_slot", (x, y, bz), (0.05, 0.072, 0.045), M_DARK, 0.0)
            else:
                # ступень 1: ствол без тормоза — простой пламегаситель-втулка, срез там же
                c("tip", (2.0, y, bz), 0.034, 0.16, M_BARREL, "X", 16)
                c("bore", (2.085, y, bz), 0.016, 0.01, M_DARK, "X", 12)
    L.group = base
    if TIER == 3 and not QUAD:
        # короба лент по бокам башни с рукавами подачи к люльке
        for sgn in (1, -1):
            box("ammo_box", (-0.05, sgn * 0.5, 0.38), (0.34, 0.09, 0.2), M_BODY, 0.01)
            box("ammo_lid", (-0.05, sgn * 0.5, 0.49), (0.3, 0.07, 0.02), M_DARK, 0.004)
            tube("feed", [(0.12, sgn * 0.5, 0.42), (0.3, sgn * 0.42, 0.47), (0.42, sgn * 0.12, BZ + 0.05)], 0.025, M_DARK)
        # прицельная головка: короб на стойке слева сверху, стекло смотрит по стволам
        c("sight_post", (0.05, 0.16, Z1 + 0.06), 0.03, 0.1, M_DARK, "Z", 12)
        box("sight_head", (0.08, 0.16, Z1 + 0.15), (0.2, 0.1, 0.1), M_BODY, 0.01)
        box("sight_hood", (0.2, 0.16, Z1 + 0.18), (0.06, 0.11, 0.03), M_DARK, 0.004)
        c("sight_lens", (0.185, 0.16, Z1 + 0.15), 0.035, 0.012, M_GLASS, "X", 16)
    if QUAD:
        # антенна наведения: стойка и тарелка, смотрит вперёд по стволам
        c("ant_post", (-0.2, 0, Z1 + 0.08), 0.025, 0.16, M_DARK, "Z", 12)
        c("ant_dish", (-0.17, 0, Z1 + 0.25), 0.16, 0.025, M_BODY, "X", 28, 0.006)
        c("ant_feed", (-0.08, 0, Z1 + 0.25), 0.018, 0.16, M_DARK, "X", 10)
        for sgn in (1, -1):
            box("ammo_box", (-0.05, sgn * 0.47, 0.36), (0.3, 0.07, 0.16), M_BODY, 0.01)

    # --- поручни сзади сверху ---
    for sgn in (1, -1):
        y = sgn * 0.42
        tube("rail", [(-0.58, y, Z1), (-0.6, y, Z1 + 0.09), (-0.2, y, Z1 + 0.09), (-0.16, y, Z1 + 0.03)], 0.012, M_DARK)
    tube("rail_back", [(-0.6, -0.42, Z1 + 0.09), (-0.6, 0.42, Z1 + 0.09)], 0.012, M_DARK)
    if detail:
        _twin_detail(TIER, QUAD, M_BODY, M_DARK, M_BARREL, M_GLASS, base, guns, Z0, Z1, BZ, LEVELS, c)
    L.group = ""


def _twin_detail(TIER, QUAD, M_BODY, M_DARK, M_BARREL, M_GLASS, base, guns, Z0, Z1, BZ, LEVELS, c):
    """S11-13 (Kanta: hangar turrets look low quality): small parts that read in the hangar close-up.
    Same axes and units as twin(); nothing changes the silhouette or the muzzle point."""
    L.group = base
    # bolted turret ring: bolts on the ring top and a dark race groove
    for i in range(18):
        a = i * math.tau / 18
        c("ring_bolt", (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.083), 0.016, 0.014, M_DARK, verts=8)
    c("race", (0, 0, 0.006), 0.445, 0.012, M_DARK)
    # traverse drive housing at the back of the pedestal with a cable conduit into the hull
    box("traverse", (-0.3, -0.12, 0.15), (0.14, 0.12, 0.1), M_BODY, 0.01)
    c("motor", (-0.3, -0.21, 0.15), 0.04, 0.08, M_DARK, "Y", 12)
    tube("conduit", [(-0.3, 0.0, 0.17), (-0.42, 0.06, 0.2), (-0.5, 0.1, 0.28)], 0.018, M_DARK)
    # rivets along the top edge of each armour half and on the side panels
    for sgn in (1, -1):
        for i in range(8):
            x = -0.53 + i * 0.12
            c("rivet", (x, sgn * 0.44, Z1 - 0.025), 0.011, 0.01, M_DARK, "Y", 8)
        for i in range(5):
            x = -0.36 + i * 0.13
            c("rivet", (x, sgn * 0.467, 0.5), 0.009, 0.008, M_DARK, "Y", 8)
            c("rivet", (x, sgn * 0.467, 0.34), 0.009, 0.008, M_DARK, "Y", 8)
        # lifting eyes on the roof plates
        tube("eye", [(-0.48, sgn * 0.33, Z1 + 0.027), (-0.48, sgn * 0.33, Z1 + 0.06),
                     (-0.42, sgn * 0.33, Z1 + 0.06), (-0.42, sgn * 0.33, Z1 + 0.027)], 0.008, M_DARK)
        # vision block: armoured periscope head on the front of each roof plate, dark glass forward
        if not (QUAD and sgn < 0):
            box("vision", (0.24, sgn * 0.3, Z1 + 0.05), (0.1, 0.09, 0.05), M_BODY, 0.006)
            box("vision_glass", (0.292, sgn * 0.3, Z1 + 0.052), (0.006, 0.07, 0.026), M_GLASS, 0.0)
    # gunner's hatch on the left rear plate: round lid, hinge, grab handle
    c("hatch", (-0.33, 0.27, Z1 + 0.034), 0.12, 0.018, M_BODY, "Z", 24, 0.004)
    c("hatch_rim", (-0.33, 0.27, Z1 + 0.027), 0.13, 0.008, M_DARK, "Z", 24)
    box("hinge", (-0.45, 0.27, Z1 + 0.036), (0.03, 0.12, 0.022), M_DARK, 0.004)
    tube("handle", [(-0.26, 0.23, Z1 + 0.043), (-0.26, 0.23, Z1 + 0.065), (-0.26, 0.31, Z1 + 0.065),
                    (-0.26, 0.31, Z1 + 0.043)], 0.007, M_DARK)
    # weld seams where the halves meet the back bridge
    for sgn in (1, -1):
        box("weld", (-0.3, sgn * 0.09, Z1 - 0.01), (0.56, 0.012, 0.012), M_DARK, 0.0)
    # radio antenna base at the back
    c("ant_base", (-0.5, -0.32, Z1 + 0.03), 0.025, 0.03, M_DARK, "Z", 10)
    c("ant_whip", (-0.5, -0.32, Z1 + 0.16), 0.006, 0.24, M_BARREL, "Z", 6)
    # recoil buffers above each gun pair and cooling slots on the sleeves (they elevate with the guns)
    L.group = guns
    for bz in LEVELS:
        c("buffer", (0.82, 0, bz + 0.055), 0.022, 0.34, M_BARREL, "X", 12)
        c("buffer_cap", (1.0, 0, bz + 0.055), 0.026, 0.03, M_DARK, "X", 12)
        for sgn in (1, -1):
            for x in (0.79, 0.86, 0.93):
                box("slot", (x, sgn * 0.075, bz + 0.05), (0.035, 0.03, 0.008), M_DARK, 0.0)
    L.group = base


if __name__ == "__main__":
    OUT = sys.argv[-1] if len(sys.argv) > 1 else "."
    QUAD = "quad" in sys.argv
    TIER = 3 if QUAD else next((int(a[1]) for a in sys.argv[1:-1] if a in ("t1", "t2", "t3")), 2)
    L.reset()
    # окраска матовая (Kanta 19.10): краска без блеска, металл — только стволы и мелкие детали
    M_BODY = mat("turret_body", (0.36, 0.35, 0.33), 0.08, 0.86)
    M_DARK = mat("turret_dark", (0.12, 0.12, 0.12), 0.15, 0.8)
    M_BARREL = mat("turret_barrel", (0.3, 0.3, 0.29), 0.45, 0.6)
    M_GLASS = mat("turret_glass", (0.12, 0.2, 0.24), 0.6, 0.06)

    twin(TIER, QUAD, M_BODY, M_DARK, M_BARREL, M_GLASS, detail=True)
    build("turret_twin_quad" if QUAD else "turret_twin_t%d" % TIER, OUT)
    if "nopreview" not in sys.argv:
        preview(OUT, [("ref", (3.3, -3.9, 2.6), (1.05, 0, 0.35), 50),
                      ("rear", (-2.6, 2.6, 2.0), (0.6, 0, 0.35), 50),
                      ("side", (1.1, -6.2, 0.6), (1.1, 0, 0.35), 40),
                      ("top", (1.1, 0.0, 6.4), None, 40)])
    print("DONE")
