"""Лёгкая турель «Грача» (средний класс; референс владельца 16.10): низкая тумба, компактная башня
со скошенным лбом, два коротких ствола один над другим. Меньше и слабее турели «Кита».
Запуск (bpy 5.x):  python3 turret_light.py <out_dir>  → turret_light.blend / .glb / preview_*.png
Оси как у turret_twin: стволы +X, начало — центр тумбы, длина башни = 1."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L

OUT = sys.argv[-1] if len(sys.argv) > 1 else "."
L.reset()
M_BODY = mat("turret_body", (0.4, 0.39, 0.37), 0.35, 0.5)
M_DARK = mat("turret_dark", (0.1, 0.1, 0.1), 0.5, 0.5)
M_BARREL = mat("turret_barrel", (0.3, 0.3, 0.29), 0.6, 0.4)

# тумба: низкие кольца
cyl("base", (-0.05, 0, 0.03), 0.34, 0.06, M_BODY, bevel=0.01)
cyl("base_ring", (-0.05, 0, 0.07), 0.355, 0.02, M_DARK)
cyl("base_top", (-0.05, 0, 0.115), 0.3, 0.07, M_BODY, bevel=0.01)

# основной блок со скошенным лбом
main = [(-0.45, 0.15), (0.3, 0.15), (0.38, 0.24), (0.38, 0.36), (0.16, 0.58), (-0.45, 0.58)]
prism("main", main, 0.42, M_BODY).location.y = 0.12
# второй блок справа — ниже и короче, из него выходят стволы
right = [(-0.45, 0.15), (0.12, 0.15), (0.2, 0.22), (0.2, 0.44), (0.08, 0.52), (-0.45, 0.52)]
prism("right", right, 0.26, M_BODY).location.y = -0.235
# швы-плиты сверху
for x in (-0.3, -0.02):
    box("plate", (x, 0.12, 0.588), (0.25, 0.38, 0.018), M_BODY, 0.006)
# накладка на борту и прорези
box("panel", (-0.1, 0.338, 0.37), (0.4, 0.012, 0.2), M_BODY, 0.006)
for i in range(4):
    box("vent", (-0.36 + i * 0.05, 0.337, 0.52), (0.03, 0.01, 0.05), M_DARK, 0.0)
for sgn, y in ((1, 0.335), (-1, -0.37)):
    box("ledge", (-0.1, y + sgn * 0.01, 0.17), (0.6, 0.03, 0.025), M_BODY, 0.004)

# стволы: два, один над другим, короткие
y = -0.18
box("mount", (0.24, y, 0.34), (0.1, 0.14, 0.27), M_DARK, 0.01)
for z in (0.27, 0.41):
    cyl("sleeve", (0.38, y, z), 0.04, 0.26, M_BARREL, "X")
    cyl("collar", (0.5, y, z), 0.046, 0.03, M_BARREL, "X")
    cyl("barrel", (0.83, y, z), 0.02, 0.66, M_BARREL, "X", 16)
    cyl("tip", (1.14, y, z), 0.028, 0.06, M_BARREL, "X", 16)
    cyl("bore", (1.172, y, z), 0.012, 0.01, M_DARK, "X", 12)

build("turret_light", OUT)
preview(OUT, [("ref", (2.4, -2.6, 1.4), (0.35, 0, 0.32), 50),
              ("rear", (-2.0, 2.0, 1.6), (0.3, 0, 0.32), 50),
              ("side", (0.35, -4.2, 0.45), (0.35, 0, 0.32), 40),
              ("top", (0.35, 0.0, 4.4), None, 40)])
print("DONE")
