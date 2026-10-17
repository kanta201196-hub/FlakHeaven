"""Т-2: убрать выпущенное шасси с модели Meshy («Кит 2»). Модель — один меш, шасси срослось с обшивкой, поэтому
отделить его как «отдельную деталь» нельзя. Удаляются UV-острова (связные куски развёртки Meshy) целиком лежащие
в «коробках» стоек и колёс из таблицы GEAR и опускающиеся ниже брюха (ZDEEP). Створки ниш остаются.
Модель перезаписывается: встроенные картинки кодируются заново, Godot заново извлечёт *_0.png — окраску
(splinter_camo.py) делать после. Потом — battle_lod.py для боевой модели.

Запуск (bpy 5.x): python3 remove_gear.py <модель ангара.glb> <ключ, например bomber_2> <out.glb>"""
import sys
import numpy as np
import bpy, bmesh

# ключ: [(x от, x до), (|y| от, |y| до)] — основные стойки и носовая; оси модели: длина 1, нос +X, верх +Z
GEAR = {"bomber_2": [((-0.16, -0.085), (0.058, 0.105)), ((0.13, 0.24), (0.0, 0.035))]}
ZDEEP = -0.068     # остров шасси опускается ниже этого
ZTOP = -0.035      # и целиком ниже этого (обшивка брюха выше)

src, key, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
removed = 0
for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
    me = o.data
    co = np.array([tuple(o.matrix_world @ v.co) for v in me.vertices])
    par = np.arange(len(co))

    def root(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for e in me.edges:
        a, b = root(e.vertices[0]), root(e.vertices[1])
        if a != b:
            par[a] = b
    ids, inv = np.unique([root(i) for i in range(len(co))], return_inverse=True)
    kill = np.zeros(len(co), bool)
    for k in range(len(ids)):
        m = inv == k
        c = co[m]
        if c[:, 2].min() >= ZDEEP or c[:, 2].max() >= ZTOP:
            continue
        for (x0, x1), (y0, y1) in GEAR[key]:
            ay = np.abs(c[:, 1])
            if (c[:, 0] >= x0).all() and (c[:, 0] <= x1).all() and (ay >= y0).all() and (ay <= y1).all():
                kill |= m
                break
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(kill)[0]], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    removed += int(kill.sum())
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB")
print("GEAR %s: removed %d verts" % (dst, removed))
