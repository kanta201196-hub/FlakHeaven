"""Стереть знаки на хвостовом оперении (правило 4: без опознавательных знаков).
Берёт треугольники хвоста (x < начало + cut × длина, кроме торцов сопел), находит на их участках
текстуры пиксели, сильно отличающиеся от основного цвета оперения (эмблемы, круги, номера), и
закрашивает их основным цветом с лёгким шумом исходной яркости.
Запуск: python3 erase_tail_marks.py <in.glb> <out.glb> [cut=0.3] [порог=0.18]"""
import sys
import numpy as np
import bpy

src, dst = sys.argv[1], sys.argv[2]
cut = float(sys.argv[3]) if len(sys.argv) > 3 else 0.3
thr = float(sys.argv[4]) if len(sys.argv) > 4 else 0.18
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
xs = [(o.matrix_world @ v.co).x for o in obs for v in o.data.vertices]
x0, x1 = min(xs), max(xs)
xcut = x0 + cut * (x1 - x0)
done = 0
for o in obs:
    me = o.data
    uvl = me.uv_layers.active.data
    for mi, mat in enumerate(me.materials):
        img = None
        if mat and mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    l = n.inputs["Base Color"].links
                    if l and l[0].from_node.type == "TEX_IMAGE":
                        img = l[0].from_node.image
        if img is None:
            continue
        W, H = img.size
        px = np.empty(W * H * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(H, W, 4)
        mask = np.zeros((H, W), bool)
        for p in me.polygons:
            if p.material_index != mi:
                continue
            c = o.matrix_world @ p.center
            n = (o.matrix_world.to_3x3() @ p.normal).normalized()
            if c.x > xcut or abs(n.x) > 0.7:
                continue
            uv = np.array([uvl[li].uv[:] for li in p.loop_indices])
            for k in range(1, len(uv) - 1):
                tri = np.array([uv[0], uv[k], uv[k + 1]]) * [W, H]
                lo = np.floor(tri.min(0)).astype(int).clip(0, [W - 1, H - 1])
                hi = np.ceil(tri.max(0)).astype(int).clip(0, [W - 1, H - 1])
                gx, gy = np.meshgrid(np.arange(lo[0], hi[0] + 1) + 0.5, np.arange(lo[1], hi[1] + 1) + 0.5)
                a, b, cc = tri
                d = (b[1] - cc[1]) * (a[0] - cc[0]) + (cc[0] - b[0]) * (a[1] - cc[1])
                if abs(d) < 1e-9:
                    continue
                l1 = ((b[1] - cc[1]) * (gx - cc[0]) + (cc[0] - b[0]) * (gy - cc[1])) / d
                l2 = ((cc[1] - a[1]) * (gx - cc[0]) + (a[0] - cc[0]) * (gy - cc[1])) / d
                ins = (l1 >= -0.02) & (l2 >= -0.02) & (l1 + l2 <= 1.02)
                mask[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1] |= ins
        if not mask.any():
            continue
        rgb = px[..., :3]
        base = np.median(rgb[mask], axis=0)
        dist = np.abs(rgb - base).max(-1)
        sat = rgb.max(-1) - rgb.min(-1)
        bad = mask & ((dist > thr) | (sat > 0.25))
        # расширить на 2 пикселя — края эмблем
        for _ in range(2):
            b2 = bad.copy()
            b2[1:] |= bad[:-1]; b2[:-1] |= bad[1:]; b2[:, 1:] |= bad[:, :-1]; b2[:, :-1] |= bad[:, 1:]
            bad = b2 & mask
        lum = rgb.mean(-1, keepdims=True)
        noise = (lum - lum[mask].mean()) * 0.15
        rgb[bad] = np.clip(base + noise[bad], 0, 1)
        px[..., :3] = rgb
        img.pixels.foreach_set(px.ravel())
        img.update()
        img.pack()
        done += int(bad.sum())
        print("ERASE %s %s: %d px (base %s)" % (o.name, img.name, bad.sum(), np.round(base, 2)))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90)
print("ERASED", done)
