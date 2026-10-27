"""Лёгкая турель «Грача» (средний класс; референс владельца 16.10): низкая тумба, компактная башня
со скошенным лбом. Меньше и слабее турели «Кита».
Запуск (bpy 5.x):  python3 turret_light.py [t1|t2|t3|evo] [nopreview] [nopaint] [livery=steppe|rock] <out_dir>
  → turret_light_t<N>.blend / .glb / preview_*.png (по умолчанию t1); evo → turret_light_evo
evo — «Дикобраз» on the «Грач» (3.5-s12, Kanta: "turret lv5 and the evolution look the same in the hangar"):
  the t3 turret plus a fire-control head on the roof (mast, box search radar, tracking dish) and cable runs,
  the same look as the «Кит» quad, so the card that shoots missiles down shows on the model.
Ступени — S9-04 (Kanta 23.10: «турель почти не меняется при улучшении — каждый уровень должен заметно
отличаться: стволы, короба, щитки, размер»). Силуэт меняется на каждом шаге:
  t1 (ур. 1–2) — малая (×0,88): одна башня без бокового блока, ОДИН короткий ствол с пламегасителем,
                 круглая маска, без щитков и коробов;
  t2 (ур. 3–4) — средняя (×1,0): боковой блок, ДВА ствола один над другим с дульными тормозами,
                 рамка-щиток вокруг стволов, короб ленты на левом борту с рукавом подачи;
  t3 (ур. 5, эволюция) — тяжёлая (×1,12): ДВА ствола рядом в дырчатых кожухах охлаждения и с крупными
                 тормозами, сплошной бронещиток во всю ширину лба со щеками, два короба лент по бортам,
                 бортовые экраны и прицельная головка сверху.
Стволы не длиннее прежних (замечание владельца 16.10): дульный срез t3 с учётом масштаба — x ≈ 1.15
(было 1.17). Точка вылета по ступени — WeaponModels.TURRET_MODELS.attacker.muzzle_t.
Окраска матовая (Kanta 19.10): краска roughness 0.86 / metallic 0.08, металл — только стволы (воронёные, S9-03).
Оси как у turret_twin: стволы +X, начало — центр тумбы, длина башни t2 = 1."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L
import bpy
from turret_twin import hedgehog_pods

OUT = sys.argv[-1] if len(sys.argv) > 1 else "."
EVO = "evo" in sys.argv[1:-1]
TIER = 3 if EVO else next((int(a[1]) for a in sys.argv[1:-1] if a in ("t1", "t2", "t3")), 1)
K = {1: 0.88, 2: 1.0, 3: 1.12}[TIER]   # размер ступени (вся турель относительно центра тумбы)
L.reset()
M_BODY = mat("turret_body", (0.4, 0.39, 0.37), 0.08, 0.86)
M_DARK = mat("turret_dark", (0.1, 0.1, 0.1), 0.12, 0.85)
M_BARREL = mat("turret_barrel", (0.17, 0.17, 0.165), 0.35, 0.62)   # S9-03: воронёная сталь, без белых бликов

# --- тумба: низкие кольца (у всех ступеней) ---
cyl("base", (-0.05, 0, 0.03), 0.34, 0.06, M_BODY, bevel=0.01)
cyl("base_ring", (-0.05, 0, 0.07), 0.355, 0.02, M_DARK)
cyl("base_top", (-0.05, 0, 0.115), 0.3, 0.07, M_BODY, bevel=0.01)
for i in range(8):   # болты погона
    a = i * math.tau / 8
    cyl("bolt", (-0.05 + math.cos(a) * 0.32, math.sin(a) * 0.32, 0.065), 0.014, 0.012, M_DARK, verts=8)

if TIER == 1:
    # ---------- t1: одна компактная башня, один ствол по оси ----------
    main = [(-0.4, 0.15), (0.2, 0.15), (0.3, 0.24), (0.3, 0.38), (0.12, 0.5), (-0.4, 0.5)]
    prism("main", main, 0.5, M_BODY)
    box("plate", (-0.14, 0, 0.507), (0.36, 0.36, 0.016), M_BODY, 0.005)
    box("hatch", (-0.26, 0.08, 0.52), (0.12, 0.12, 0.02), M_DARK, 0.004)
    for sgn in (1, -1):
        box("ledge", (-0.08, sgn * 0.258, 0.17), (0.56, 0.02, 0.022), M_BODY, 0.004)
        for i in range(3):
            box("vent", (-0.3 + i * 0.05, sgn * 0.251, 0.42), (0.026, 0.008, 0.05), M_DARK, 0.0)
    L.group = "guns"
    L.pivots["guns"] = (0.3, 0, 0.32)
    cyl("mantlet", (0.3, 0, 0.32), 0.1, 0.09, M_DARK, "X", 20, 0.01)
    cyl("sleeve", (0.4, 0, 0.32), 0.045, 0.14, M_BARREL, "X")
    cyl("barrel", (0.64, 0, 0.32), 0.022, 0.4, M_BARREL, "X", 16)
    drill(cyl("hider", (0.86, 0, 0.32), 0.03, 0.07, M_BARREL, "X", 16), (0.895, 0, 0.32), 0.014, 0.05, M_DARK)   # пламегаситель с каналом
    L.group = ""

elif TIER == 2:
    # ---------- t2: башня с боковым блоком, два ствола один над другим ----------
    main = [(-0.45, 0.15), (0.3, 0.15), (0.38, 0.24), (0.38, 0.36), (0.16, 0.58), (-0.45, 0.58)]
    prism("main", main, 0.42, M_BODY).location.y = 0.12
    right = [(-0.45, 0.15), (0.12, 0.15), (0.2, 0.22), (0.2, 0.44), (0.08, 0.52), (-0.45, 0.52)]
    prism("right", right, 0.26, M_BODY).location.y = -0.235
    for x in (-0.3, -0.02):
        box("plate", (x, 0.12, 0.588), (0.25, 0.38, 0.018), M_BODY, 0.006)
    box("panel", (-0.1, 0.338, 0.37), (0.4, 0.012, 0.2), M_BODY, 0.006)
    for i in range(4):
        box("vent", (-0.36 + i * 0.05, 0.337, 0.52), (0.03, 0.01, 0.05), M_DARK, 0.0)
    for sgn, y in ((1, 0.335), (-1, -0.37)):
        box("ledge", (-0.1, y + sgn * 0.01, 0.17), (0.6, 0.03, 0.025), M_BODY, 0.004)
    # короб ленты на левом борту и рукав подачи через верх к стволам
    box("ammo_box", (-0.12, 0.39, 0.36), (0.3, 0.09, 0.18), M_BODY, 0.008)
    box("ammo_lid", (-0.12, 0.39, 0.458), (0.26, 0.07, 0.016), M_DARK, 0.003)
    box("ammo_latch", (0.0, 0.437, 0.36), (0.03, 0.01, 0.06), M_DARK, 0.0)
    tube("feed", [(0.0, 0.39, 0.42), (0.1, 0.3, 0.62), (0.18, -0.1, 0.62), (0.24, -0.18, 0.47)], 0.022, M_DARK)
    y = -0.18
    L.group = "guns"
    L.pivots["guns"] = (0.24, y, 0.34)
    box("mount", (0.24, y, 0.34), (0.1, 0.14, 0.27), M_DARK, 0.01)
    for z in (0.27, 0.41):
        cyl("sleeve", (0.38, y, z), 0.04, 0.26, M_BARREL, "X")
        cyl("collar", (0.5, y, z), 0.046, 0.03, M_BARREL, "X")
        cyl("barrel", (0.83, y, z), 0.02, 0.66, M_BARREL, "X", 16)
        # 3.5-s12: the bore is drilled into the brake's face
        drill(box("brake", (1.12, y, z), (0.11, 0.05, 0.05), M_BARREL, 0.005), (1.175, y, z), 0.013, 0.022, M_DARK)
        box("brake_slot", (1.12, y, z), (0.035, 0.052, 0.03), M_DARK, 0.0)
    # щиток: рамка вокруг стволов на лбу правого блока
    box("shield", (0.31, y, 0.34), (0.035, 0.22, 0.34), M_BODY, 0.008)
    box("shield_cap", (0.3, y, 0.52), (0.08, 0.22, 0.025), M_BODY, 0.005)
    L.group = ""

else:
    # ---------- t3: широкая тяжёлая башня, два ствола рядом в кожухах, сплошной бронещиток ----------
    main = [(-0.48, 0.15), (0.26, 0.15), (0.36, 0.25), (0.36, 0.4), (0.18, 0.6), (-0.48, 0.6)]
    prism("main", main, 0.62, M_BODY)
    for x in (-0.34, -0.06):
        box("plate", (x, 0, 0.607), (0.25, 0.54, 0.016), M_BODY, 0.006)
    box("hatch", (-0.34, 0.15, 0.622), (0.14, 0.14, 0.02), M_DARK, 0.004)
    # прицельная головка сверху: тумба, корпус, тёмное окно
    cyl("sight_base", (-0.02, -0.17, 0.63), 0.06, 0.04, M_BODY, verts=16)
    box("sight", (0.0, -0.17, 0.69), (0.16, 0.1, 0.09), M_BODY, 0.01)
    box("sight_win", (0.082, -0.17, 0.695), (0.006, 0.07, 0.045), M_DARK, 0.0)
    for sgn in (1, -1):
        yb = sgn * 0.31
        # бортовой экран на стойках с зазором
        box("skirt", (-0.1, sgn * 0.345, 0.36), (0.62, 0.016, 0.3), M_BODY, 0.005)
        for x in (-0.34, 0.12):
            box("skirt_post", (x, sgn * 0.33, 0.36), (0.03, 0.03, 0.03), M_DARK, 0.0)
        # короб ленты поверх экрана и рукав подачи к своему стволу
        box("ammo_box", (-0.16, sgn * 0.41, 0.4), (0.32, 0.1, 0.2), M_BODY, 0.008)
        box("ammo_lid", (-0.16, sgn * 0.41, 0.508), (0.28, 0.08, 0.016), M_DARK, 0.003)
        for x in (-0.26, -0.06):
            box("ammo_rib", (x, sgn * 0.462, 0.4), (0.02, 0.006, 0.18), M_BODY, 0.0)
        tube("feed", [(0.0, sgn * 0.41, 0.46), (0.12, sgn * 0.36, 0.56), (0.22, sgn * 0.2, 0.52)], 0.022, M_DARK)
        box("ledge", (-0.1, sgn * 0.322, 0.17), (0.66, 0.02, 0.025), M_BODY, 0.004)
    L.group = "guns"
    L.pivots["guns"] = (0.3, 0, 0.36)
    # сплошной бронещиток во всю ширину лба, сверху козырёк, по бокам щёки
    box("shield", (0.4, 0, 0.36), (0.05, 0.5, 0.3), M_BODY, 0.01)
    box("shield_cap", (0.38, 0, 0.52), (0.1, 0.5, 0.025), M_BODY, 0.005)
    for sgn in (1, -1):
        box("cheek", (0.36, sgn * 0.26, 0.36), (0.1, 0.025, 0.3), M_BODY, 0.006)
    for yb in (0.11, -0.11):
        cyl("collar", (0.44, yb, 0.36), 0.052, 0.04, M_BARREL, "X")
        # кожух охлаждения с рядами отверстий
        cyl("jacket", (0.6, yb, 0.36), 0.036, 0.3, M_BARREL, "X", 20)
        for i in range(5):
            for a in range(6):
                ang = a * math.tau / 6
                cyl("hole", (0.49 + i * 0.055, yb + math.cos(ang) * 0.035, 0.36 + math.sin(ang) * 0.035),
                    0.009, 0.006, M_DARK, "Y" if abs(math.sin(ang)) < 0.5 else "Z", 8)
        cyl("barrel", (0.85, yb, 0.36), 0.019, 0.22, M_BARREL, "X", 16)
        drill(box("brake", (0.99, yb, 0.36), (0.09, 0.06, 0.055), M_BARREL, 0.005), (1.035, yb, 0.36), 0.012, 0.012, M_DARK)
        for x in (0.97, 1.01):
            box("brake_slot", (x, yb, 0.36), (0.016, 0.062, 0.035), M_DARK, 0.0)
    L.group = ""

# S12 (Kanta 26.10: "add detail so the upgrade difference shows"): small parts per tier
# on top of the silhouette steps above — t1 stays the plain box; t2 gets rivet rows, lifting eyes and a roof
# grab rail; t3 also a whip antenna, a rear stowage bustle with straps and a cable conduit to the sight.
if TIER >= 2:
    # (wall y, first and last rivet x, wall top z) — rows stop short of the sloped front
    walls = {2: [(0.33, -0.42, 0.08, 0.58), (-0.365, -0.42, 0.0, 0.52)],
             3: [(0.31, -0.44, 0.1, 0.6), (-0.31, -0.44, 0.1, 0.6)]}[TIER]
    for y, x0, x1, top in walls:
        sgn = 1 if y > 0 else -1
        n = int((x1 - x0) / 0.09) + 1
        for i in range(n):
            cyl("rivet", (x0 + i * 0.09, y + sgn * 0.004, top - 0.03), 0.009, 0.008, M_DARK, "Y", 8)
            cyl("rivet", (x0 + i * 0.09, y + sgn * 0.004, 0.19), 0.009, 0.008, M_DARK, "Y", 8)
    top = {2: 0.58, 3: 0.6}[TIER]
    yc = 0.12 if TIER == 2 else 0.0
    for sgn in (1, -1):
        y = yc + sgn * 0.14
        tube("eye", [(-0.4, y, top + 0.015), (-0.4, y, top + 0.045), (-0.35, y, top + 0.045), (-0.35, y, top + 0.015)],
             0.007, M_DARK)
    tube("grab_rail", [(-0.2, yc - 0.12, top + 0.01), (-0.2, yc - 0.12, top + 0.05), (-0.2, yc + 0.12, top + 0.05),
                       (-0.2, yc + 0.12, top + 0.01)], 0.009, M_DARK)
if TIER == 3:
    cyl("ant_base", (-0.42, -0.2, 0.62), 0.022, 0.03, M_DARK, "Z", 10)
    cyl("ant_whip", (-0.42, -0.2, 0.8), 0.005, 0.34, M_BARREL, "Z", 6)
    box("bustle", (-0.55, 0, 0.42), (0.14, 0.44, 0.2), M_BODY, 0.01)
    box("bustle_lid", (-0.55, 0, 0.53), (0.15, 0.42, 0.02), M_DARK, 0.004)
    for y in (-0.12, 0.12):
        box("strap", (-0.55, y, 0.42), (0.152, 0.025, 0.205), M_DARK, 0.0)
    tube("conduit", [(-0.3, -0.25, 0.62), (-0.1, -0.24, 0.63), (-0.04, -0.2, 0.66)], 0.012, M_DARK)

if EVO:
    # fire-control head of «Дикобраз»: mast behind the sight, box radar with a dark array face, tracking dish
    zt = 0.6
    cyl("radar_mast", (-0.3, 0.0, zt + 0.08), 0.03, 0.16, M_DARK, "Z", 12)
    cyl("radar_turntable", (-0.3, 0.0, zt + 0.17), 0.06, 0.025, M_DARK, "Z", 16)
    box("radar_box", (-0.3, 0.0, zt + 0.26), (0.13, 0.32, 0.14), M_BODY, 0.01)
    box("radar_face", (-0.23, 0.0, zt + 0.26), (0.012, 0.28, 0.11), M_DARK, 0.003)
    for i in range(5):
        box("radar_rib", (-0.223, -0.11 + i * 0.055, zt + 0.26), (0.008, 0.008, 0.1), M_BARREL, 0.0)
    box("radar_hood", (-0.27, 0.0, zt + 0.34), (0.11, 0.34, 0.02), M_BODY, 0.004)
    cyl("dish_arm", (-0.3, 0.2, zt + 0.26), 0.011, 0.09, M_DARK, "Y", 8)
    cyl("dish", (-0.26, 0.26, zt + 0.26), 0.065, 0.016, M_BODY, "X", 24, 0.004)
    cyl("dish_feed", (-0.21, 0.26, zt + 0.26), 0.007, 0.08, M_DARK, "X", 8)
    for sgn in (1, -1):
        tube("cable", [(-0.3, sgn * 0.05, zt + 0.02), (-0.05, sgn * 0.07, zt + 0.02), (0.15, sgn * 0.08, zt - 0.02)],
             0.01, M_DARK)

# «Стальной ёж» mini-missile pods (separate node "pods", shown only with the card): beside the hull per tier
POD = {1: ([(-0.22, 0.32, 0.33), (-0.22, -0.32, 0.33)], 0.25, 0.8),
       2: ([(-0.37, 0.41, 0.38), (-0.37, -0.43, 0.38)], 0.33, 0.8),
       3: ([(-0.44, 0.43, 0.42), (-0.44, -0.43, 0.42)], 0.31, 0.85)}[TIER]
hedgehog_pods(POD[0], POD[1], M_BODY, M_DARK, M_BARREL, cyl, POD[2])

# размер ступени: вся турель — от центра тумбы (у основания)
if K != 1.0:
    for ob in L.parts:
        ob.location = ob.location * K
        ob.scale = (K, K, K)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in L.parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = L.parts[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for g, p in list(L.pivots.items()):
        L.pivots[g] = tuple(c * K for c in p)

from turret_paint import pick
build("turret_light_evo" if EVO else "turret_light_t%d" % TIER, OUT, None if "nopaint" in sys.argv else pick("grach", sys.argv))
if "nopreview" not in sys.argv:
    preview(OUT, [("ref", (2.4, -2.6, 1.4), (0.35, 0, 0.32), 50),
                  ("rear", (-2.0, 2.0, 1.6), (0.3, 0, 0.32), 50),
                  ("side", (0.35, -4.2, 0.45), (0.35, 0, 0.32), 40),
                  ("top", (0.35, 0.0, 4.4), None, 40)])
print("DONE")
