"""Кормовая установка «Кита» по примеру владельца 16.10 (catalog/refs/tail_turret): кабина стрелка
в конце фюзеляжа под килем — остеклённый фонарь сверху, под ним сферическая установка со спаренными
пушками. Две модели, потому что кабина неподвижна, а шар со стволами поворачивается:
  python3 turret_tail.py ball [t1|t2|t3] <out_dir>   → turret_tail_ball_t<N>.glb  (шар и стволы)
     ступени стволов (Т-4): t1 — без тормозов, t2 — дульные тормоза, t3 — тормоза и дырчатый кожух
  python3 turret_tail.py cabin <out_dir>  → turret_tail_cabin.glb (кабина)
Обе в одних осях: начало координат — центр шара, стволы +X (в игре развёрнуты назад), Z вверх.
Единицы как у turret_twin.py (длина башни = 1), стволы короткие — как у укороченной турели.
S12: baked paint in the «Кит» palette (turret_paint.py, 1024 px atlas); nopaint skips it."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L
from turret_twin import hedgehog_pods

OUT = sys.argv[-1]
part = "ball" if "ball" in sys.argv else "cabin"
TIER = next((int(a[1]) for a in sys.argv[1:-1] if a in ("t1", "t2", "t3")), 2)
L.reset()
# окраска матовая (Kanta 19.10): краска без блеска, металл — только стволы и мелкие детали
M_BODY = mat("turret_body", (0.36, 0.35, 0.33), 0.08, 0.86)
M_DARK = mat("turret_dark", (0.12, 0.12, 0.12), 0.15, 0.8)
M_BARREL = mat("turret_barrel", (0.3, 0.3, 0.29), 0.45, 0.6)
M_GLASS = mat("turret_glass", (0.12, 0.2, 0.24), 0.6, 0.06)


def sphere(name, c, r, sc, m, seg=28):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m)


if part == "ball":
    sphere("ball", (0, 0, 0), 0.3, (1, 1, 1), M_BODY)
    cyl("ball_ring", (-0.05, 0, 0), 0.31, 0.05, M_DARK, "X", 28)
    box("gun_slot", (0.24, 0, 0), (0.12, 0.3, 0.1), M_DARK, 0.01)
    for sgn in (1, -1):
        y = sgn * 0.085
        cyl("sleeve", (0.38, y, 0), 0.045, 0.24, M_BARREL, "X")
        cyl("barrel", (0.85, y, 0), 0.026, 0.8, M_BARREL, "X", 16)
        for x in (0.62, 1.05):
            cyl("band", (x, y, 0), 0.034, 0.03, M_BARREL, "X", 16)
        if TIER >= 2:
            box("brake", (1.29, y, 0), (0.14, 0.064, 0.064), M_BARREL, 0.006)
            box("brake_slot", (1.29, y, 0), (0.05, 0.066, 0.04), M_DARK, 0.0)
            cyl("bore", (1.3605, y, 0), 0.016, 0.004, M_DARK, "X", 12)   # 3.5-s12: bore on the brake's face
        else:
            cyl("tip", (1.29, y, 0), 0.032, 0.14, M_BARREL, "X", 16)
            cyl("bore", (1.362, y, 0), 0.015, 0.01, M_DARK, "X", 12)
        if TIER == 3:
            # дырчатый кожух охлаждения на средней части ствола
            cyl("jacket", (0.83, y, 0), 0.04, 0.34, M_DARK, "X", 16)
            for x in (0.72, 0.8, 0.88, 0.96):
                cyl("jacket_ring", (x, y, 0), 0.044, 0.018, M_BARREL, "X", 16)
    # S12: «Стальной ёж» launch pods on the ball sides (node "pods", shown only with the card)
    hedgehog_pods([(-0.04, sgn * 0.34, 0.0) for sgn in (1, -1)], 0.27, M_BODY, M_DARK, M_BARREL, cyl, 0.7)
    shots = [("iso", (2.4, -2.8, 1.6), (0.4, 0, 0), 50)]
else:
    # корпус кабины — круглый хвост фюзеляжа, сужается к шару; сверху остеклённый фонарь с переплётами
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=0.42, radius2=0.3, depth=1.1, location=(-0.7, 0, 0.0))
    ob = bpy.context.object
    ob.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    # широкий конец — к фюзеляжу (−X), узкий — к шару
    wide = [v.co.x for v in ob.data.vertices if (v.co.y ** 2 + v.co.z ** 2) > 0.38 ** 2]
    if sum(wide) / len(wide) > ob.location.x:
        ob.scale.x = -1
        bpy.ops.object.transform_apply(scale=True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    finish(ob, M_BODY, 0.03, 2)
    CX, CZ, RX, RY, RZ = -0.55, 0.3, 0.38, 0.26, 0.22
    sphere("canopy", (CX, 0, CZ), 1.0, (RX, RY, RZ), M_GLASS)
    for x in (-0.68, -0.5, -0.32):
        k = math.sqrt(max(0.0, 1 - ((x - CX) / RX) ** 2))
        pts = [(x, math.cos(t) * RY * k * 1.02, CZ + math.sin(t) * RZ * k * 1.02) for t in [i * math.pi / 8 for i in range(9)]]
        tube("frame", pts, 0.01, M_DARK)
    tube("frame", [(CX + RX * math.cos(t) * 1.02, 0, CZ + RZ * math.sin(t) * 1.02) for t in [i * math.pi / 8 for i in range(9)]], 0.01, M_DARK)
    for sgn in (1, -1):
        sphere("side_win", (-0.95, sgn * 0.38, 0.06), 0.08, (1.4, 0.35, 1.0), M_GLASS, 16)
    cyl("ball_seat", (-0.14, 0, 0.0), 0.31, 0.06, M_DARK, "X", 28)
    shots = [("iso", (1.6, -2.4, 1.4), (-0.5, 0, 0.1), 50)]

from turret_paint import PALETTES
root = build("turret_tail_" + part + ("_t%d" % TIER if part == "ball" else ""), OUT,
             None if "nopaint" in sys.argv else PALETTES["kit"], 1024)
root.location.z += 0.6   # предпросмотр над полом
if "nopreview" not in sys.argv:
    preview(OUT, [(n, (p[0], p[1], p[2] + 0.6), (t[0], t[1], t[2] + 0.6), l) for n, p, t, l in shots])
print("DONE")
