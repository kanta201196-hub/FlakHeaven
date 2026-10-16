"""Спаренная турель «Кита» (по референсу владельца 16.10): основание-погон, бронированная
башня с плитами сверху, люлька и два ствола с дульными тормозами.
Запуск (bpy 5.x):  python3 turret_twin.py <out_dir>
Выход: turret_twin.blend, turret_twin.glb (ось стволов +X, верх +Y в Godot, начало — центр погона),
       preview_*.png. Единица — длина башни (без стволов) = 1."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L

OUT = sys.argv[-1] if len(sys.argv) > 1 else "."
L.reset()
M_BODY = mat("turret_body", (0.36, 0.35, 0.33), 0.25, 0.55)
M_DARK = mat("turret_dark", (0.12, 0.12, 0.12), 0.5, 0.5)
M_BARREL = mat("turret_barrel", (0.3, 0.3, 0.29), 0.6, 0.4)

# --- погон и тумба ---
cyl("ring", (0, 0, 0.04), 0.44, 0.08, M_BODY, bevel=0.015)
cyl("ring_top", (0, 0, 0.09), 0.36, 0.03, M_DARK, bevel=0.005)
cyl("pedestal", (-0.02, 0, 0.15), 0.25, 0.12, M_BODY, bevel=0.01)
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
box("cradle", (0.42, 0, BZ), (0.5, 0.17, 0.13), M_BODY, 0.015)
box("mantlet", (0.68, 0, BZ), (0.08, 0.26, 0.11), M_DARK, 0.01)
for sgn in (1, -1):
    y = sgn * 0.075
    cyl("sleeve", (0.86, y, BZ), 0.05, 0.36, M_BARREL, "X")
    for x in (0.74, 0.86, 1.02):
        cyl("collar", (x, y, BZ), 0.058, 0.035, M_BARREL, "X")
    cyl("barrel", (1.78, y, BZ), 0.028, 1.5, M_BARREL, "X", 16)
    for x in (1.3, 1.36, 2.38, 2.44):
        cyl("band", (x, y, BZ), 0.036, 0.03, M_BARREL, "X", 16)
    # дульный тормоз: короб с двумя окнами
    box("brake", (2.6, y, BZ), (0.17, 0.07, 0.07), M_BARREL, 0.006)
    for x in (2.56, 2.65):
        box("brake_slot", (x, y, BZ + 0.0), (0.05, 0.072, 0.045), M_DARK, 0.0)

# --- поручни сзади сверху ---
for sgn in (1, -1):
    y = sgn * 0.42
    tube("rail", [(-0.58, y, Z1), (-0.6, y, Z1 + 0.09), (-0.2, y, Z1 + 0.09), (-0.16, y, Z1 + 0.03)], 0.012, M_DARK)
tube("rail_back", [(-0.6, -0.42, Z1 + 0.09), (-0.6, 0.42, Z1 + 0.09)], 0.012, M_DARK)


build("turret_twin", OUT)
preview(OUT, [("ref", (3.3, -3.9, 2.6), (1.05, 0, 0.35), 50),
              ("rear", (-2.6, 2.6, 2.0), (0.6, 0, 0.35), 50),
              ("side", (1.1, -6.2, 0.6), (1.1, 0, 0.35), 40),
              ("top", (1.1, 0.0, 6.4), None, 40)])
print("DONE")
