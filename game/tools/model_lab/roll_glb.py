# Поворот модели вокруг оси носа. Hunyuan 3D по виду сверху кладёт самолёт «на бок»: крылья вертикально.
#   python3 roll_glb.py <in.glb> <out.glb> <градусы, напр. -90> [ось носа x|z = x]
import sys
import numpy as np
import trimesh

src, dst, deg = sys.argv[1], sys.argv[2], float(sys.argv[3])
axis = [1, 0, 0] if (sys.argv[4] if len(sys.argv) > 4 else "x") == "x" else [0, 0, 1]
scene = trimesh.load(src, force="scene")
scene.apply_transform(trimesh.transformations.rotation_matrix(np.radians(deg), axis))
scene.export(dst, include_normals=True)
print("повёрнуто на %g° вокруг %s, размер: %s" % (deg, "XZ"[axis[2]], np.round(scene.extents, 3)))
