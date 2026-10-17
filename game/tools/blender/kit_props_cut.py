"""Замечание 31/33 (3.5-s4): у «Кита 1» винты Meshy разные (наружные — 5 лопастей, внутренние — 4), на ступице
внутреннего — тёмная «пружина». Модель — одна сплошная оболочка, лопасти и коки срослись с мотогондолами,
поэтому они удаляются по положению: треугольники перед срезом капота в цилиндре вокруг оси двигателя.
Свои одинаковые винты — kit_props.py (models/mech/fh_prop_bomber_1.glb), игра подвешивает их (WingMech.attach_props).

Правится только список треугольников (glb_io.py): вершины, UV, материал и встроенные картинки — байт в байт,
поэтому Godot не перезаписывает извлечённые текстуры с песочной окраской (splinter_camo.py).
Печатает оси двигателей и края отверстий (центр, радиус) — по ним kit_props.py ставит коки.

Запуск: python3 kit_props_cut.py <in.glb> <out.glb> [--json=оси.json]"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

# Оси glTF (как в Godot): нос +X, верх +Y, правое крыло +Z. Длина модели 1.
# Двигатель: (примерный центр z, срез капота x — дальше вперёд всё удаляется; по виду сбоку модели ангара)
ENGINES = {"outer_r": (0.29, 0.1155), "inner_r": (0.145, 0.1705), "inner_l": (-0.145, 0.1705), "outer_l": (-0.29, 0.1155)}
R_ZONE = 0.085     # радиус цилиндра удаления вокруг оси (лопасти ~0.07)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
src, dst = args[0], args[1]
g = glb_io.load(src)
w, t = g.mesh_world()
cen = w[t].mean(1)
kill = np.zeros(len(t), bool)
axes = {}
for name, (zc, xcut) in ENGINES.items():
    # ось: острие кока — самая передняя вершина в полосе двигателя
    band = (np.abs(w[:, 2] - zc) < 0.03) & (w[:, 0] > xcut)
    tip = w[band][np.argmax(w[band][:, 0])]
    ay, az = float(tip[1]), float(tip[2])
    rr = np.hypot(cen[:, 1] - ay, cen[:, 2] - az)
    k = (cen[:, 0] > xcut) & (rr < R_ZONE)
    kill |= k
    axes[name] = {"tip": [float(v) for v in tip], "y": ay, "z": az, "xcut": xcut, "removed": int(k.sum())}

keep = t[~kill]
# края отверстий: рёбра, принадлежащие одному треугольнику, у среза капота
q = np.round(w / 1e-5).astype(np.int64)
_, weld = np.unique(q, axis=0, return_inverse=True)
weld = weld.reshape(-1)
kt = weld[keep]
e = np.sort(np.concatenate([kt[:, [0, 1]], kt[:, [1, 2]], kt[:, [2, 0]]]), axis=1)
eu, ec = np.unique(e, axis=0, return_counts=True)
bnd = eu[ec == 1]
rep = np.zeros(weld.max() + 1, np.int64)
rep[weld] = np.arange(len(w))
bv = w[rep[np.unique(bnd)]]
for name, a in axes.items():
    m = (np.abs(bv[:, 0] - a["xcut"]) < 0.03) & (np.hypot(bv[:, 1] - a["y"], bv[:, 2] - a["z"]) < R_ZONE)
    p = bv[m]
    if len(p):
        cy, cz = float(p[:, 1].mean()), float(p[:, 2].mean())
        r = np.hypot(p[:, 1] - cy, p[:, 2] - cz)
        a["hole"] = {"n": int(len(p)), "x": [float(p[:, 0].min()), float(p[:, 0].max())], "y": cy, "z": cz,
                     "r_mean": float(r.mean()), "r_max": float(r.max())}
    print(name, json.dumps(a))
print("tris %d -> %d" % (len(t), len(keep)))
g.set_indices(0, 0, keep)
g.save(dst)
if "json" in opts:
    json.dump(axes, open(opts["json"], "w"), indent=1)
