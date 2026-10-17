"""Замечание 31/33 (3.5-s4): свои винты «Кита 1» вместо винтов Meshy (те удаляет kit_props_cut.py).
Четыре одинаковых винта: 4 лопасти с профилем и круткой (тёмный металл, жёлтые кончики), кок по размеру
капота. Узлы GLB prop_outer_l, prop_inner_l, prop_inner_r, prop_outer_r: origin — на оси двигателя
у основания кока, ось вращения — локальная X (в Godot тоже X, нос). Игра крутит узлы (PlaneFx.update,
hangar3d) и подвешивает файл к модели ангара и к боевой (WingMech.attach_props), как fh_detail_*.glb.

Оси двигателей и края отверстий — из kit_props_cut.py --json (модель ангара). В таблице ниже — те же числа,
пересчитанные в оси Blender: X нос, Y левое крыло (= −Z glTF), Z верх (= Y glTF).

Запуск (bpy 5.x): python3 kit_props.py <out.glb> [папка для .blend и кадра]"""
import math
import os
import sys

import bpy  # noqa: I001 — bpy до bmesh
import bmesh
from mathutils import Matrix, Vector

# имя: (x основания кока, y, z, радиус кока) — Blender; glTF z → −y
ENG = {
    "prop_outer_l": (0.1135, 0.2902, -0.0770, 0.0168),
    "prop_inner_l": (0.1685, 0.1393, -0.0628, 0.0222),
    "prop_inner_r": (0.1685, -0.1398, -0.0628, 0.0222),
    "prop_outer_r": (0.1135, -0.2902, -0.0767, 0.0168),
}
SPIN_L = 0.034        # длина кока
BLADE_X = 0.009       # плоскость лопастей от основания кока
R_TIP = 0.066         # радиус винта (у Meshy был 0.063–0.069)
R_ROOT = 0.011        # где начинается перо лопасти
BLADES = 4
TIP_K = 0.9           # от этой доли радиуса — жёлтая законцовка


def lin(c):
    return tuple(v ** 2.2 for v in c)


def mat(name, rgb, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(rgb), 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


def spinner(bm, R, mi):
    """Кок: огива от основания (радиус R) к острию, 12 граней по кругу, донце закрыто."""
    seg, rings = 12, 7
    prof = []
    for i in range(rings):
        t = i / (rings - 1)
        # огива: радиус спадает к носу плавно, у основания — короткий цилиндр
        r = R * math.sqrt(max(0.0, 1.0 - t ** 1.6)) if t > 0 else R
        prof.append((SPIN_L * t, r))
    prof.insert(1, (0.003, R))
    rings_v = []
    for x, r in prof:
        if r < 1e-5:
            rings_v.append([bm.verts.new((x, 0, 0))])
            continue
        rings_v.append([bm.verts.new((x, r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg)))
                        for k in range(seg)])
    for a, b in zip(rings_v[:-1], rings_v[1:]):
        for k in range(seg):
            k2 = (k + 1) % seg
            if len(b) == 1:
                f = bm.faces.new((a[k], a[k2], b[0]))
            else:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.material_index = mi
            f.smooth = True
    f = bm.faces.new(list(reversed(rings_v[0])))
    f.material_index = mi


def blade(bm, rot, mi_blade, mi_tip):
    """Лопасть вдоль локальной +Z (до поворота rot вокруг X), хорда — в плоскости Y/X с углом установки."""
    n_sec = 7
    prof = [(0.5, 0.0), (0.25, 0.55), (-0.1, 0.62), (-0.5, 0.0), (-0.1, -0.22), (0.25, -0.2)]   # (по хорде, по толщине)
    secs = []
    for i in range(n_sec):
        t = i / (n_sec - 1)
        r = R_ROOT + (R_TIP - R_ROOT) * t
        if i == 0:
            r = 0.006          # комель уходит в кок
        # хорда: у комля узкая (ножка), шире к трети, к концу сужается и скругляется
        chord = 0.004 if i == 0 else 0.014 * (1.0 - 0.45 * t) * (1.0 - 0.7 * max(0.0, t - 0.85) / 0.15) * min(1.0, 0.55 + 2.2 * t)
        thick = 0.0032 if i == 0 else 0.0026 * (1.0 - 0.6 * t)
        beta = math.radians(42.0 - 30.0 * t)          # крутка: у комля круче, к концу положе
        ch = Vector((math.sin(beta), math.cos(beta), 0))   # передняя кромка: вперёд (+X) и по вращению (+Y)
        th = Vector((math.cos(beta), -math.sin(beta), 0))
        # перо чуть сдвинуто назад от оси (саблевидность едва заметна)
        off = Vector((0, -0.0015 * t * t, 0))
        ring = []
        for u, v in prof:
            p = off + ch * (u * chord) + th * (v * thick) + Vector((0, 0, r))
            ring.append(bm.verts.new(rot @ p))
        secs.append((ring, t))
    for (a, ta), (b, tb) in zip(secs[:-1], secs[1:]):
        for k in range(len(prof)):
            k2 = (k + 1) % len(prof)
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.material_index = mi_tip if ta >= TIP_K - 1e-6 else mi_blade
            f.smooth = True
    f = bm.faces.new(secs[-1][0])
    f.material_index = mi_tip


def make_prop(name, R, mats):
    me = bpy.data.meshes.new(name)
    for m in mats:
        me.materials.append(m)
    bm = bmesh.new()
    spinner(bm, R, 0)
    for k in range(BLADES):
        rot = Matrix.Translation((BLADE_X, 0, 0)) @ Matrix.Rotation(2 * math.pi * k / BLADES + math.pi / 4, 4, "X")
        blade(bm, rot, 1, 2)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


out = sys.argv[1]
extra = sys.argv[2] if len(sys.argv) > 2 else ""
bpy.ops.wm.read_factory_settings(use_empty=True)
mats = [mat("prop_spinner", (0.42, 0.36, 0.26), 0.15, 0.6),       # в тон светлому песку «Кита»
        mat("prop_blade", (0.12, 0.12, 0.13), 0.55, 0.45),      # тёмный металл
        mat("prop_tip", (0.95, 0.75, 0.12), 0.1, 0.5)]          # жёлтые законцовки
root = bpy.data.objects.new("props", None)
bpy.context.scene.collection.objects.link(root)
tris = 0
for name, (x, y, z, R) in ENG.items():
    ob = make_prop(name, R, mats)
    ob.location = (x, y, z)
    ob.parent = root
    tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
print("PROP TRIS", tris)
if extra:
    os.makedirs(extra, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(extra, "fh_prop_bomber_1.blend"))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_materials="EXPORT")
