# Подгонка размаха модели под спрайт: TRELLIS угадывает пропорции, крыло бывает уже, чем на спрайте.
# Растягивает поперёк полёта только то, что дальше полуширины фюзеляжа (крылья, стабилизаторы).
# Вход — GLB как из генератора (нос по Z, размах по X), запускать до `model_lab.gd prep`.
#   python3 fit_span.py <in.glb> <out.glb> <размах/длина по спрайту, напр. 0.753> [полуширина фюзеляжа/длина=0.06]
import sys
import numpy as np
import trimesh

src, dst, ratio = sys.argv[1], sys.argv[2], float(sys.argv[3])
body = float(sys.argv[4]) if len(sys.argv) > 4 else 0.06

scene = trimesh.load(src, force="scene")
for g in scene.geometry.values():
    v = np.array(g.vertices)
    length, span = np.ptp(v[:, 2]), np.ptp(v[:, 0])
    cx = (v[:, 0].min() + v[:, 0].max()) / 2.0
    f = body * length
    k = (ratio * length / 2.0 - f) / (span / 2.0 - f)
    d = v[:, 0] - cx
    a = np.abs(d)
    v[:, 0] = np.where(a > f, cx + np.sign(d) * (f + (a - f) * k), v[:, 0])
    g.vertices = v
    print("размах/длина: %.3f → %.3f (крылья ×%.2f)" % (span / length, ratio, k))
scene.export(dst, include_normals=True)
