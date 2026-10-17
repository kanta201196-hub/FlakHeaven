"""Тест 3.5-s4 (п. 18): обломки самолёта в биоме — объёмный остов, лежащий на земле, вместо выдавленной
картинки o_wreck.png в круглой выровненной площадке. Из боевой модели врага (по умолчанию перехватчик):
корпус разрезается по положению граней на нос, хвост, левое и правое крыло; части разбросаны, перевёрнуты
и легли на землю (z = 0), текстура обожжена (темнее, копоть пятнами, ржавчина), вокруг мелкие обломки.
Вымышленный: модель врага «по мотивам», без знаков.
Единицы как у моделей биома (tools/model_lab/biome_prep.py): стоит на z = 0 (в Godot y = 0), центр в нуле,
наибольший размер в плане = 1 — игра масштабирует под размер объекта клетки (render3d.gd, o_wreck).

Запуск (bpy 5.x): python3 plane_wreck.py <боевая модель.glb> <out.glb> [seed]"""
import sys, math
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

args = [a for a in sys.argv[1:]]
src, dst = args[0], args[1]
seed = int(args[2]) if len(args) > 2 else 3
rng = np.random.default_rng(seed)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
obs = [o for o in sc.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in obs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
if len(obs) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.parent = None
body.data.transform(body.matrix_world)
body.matrix_world = Matrix.Identity(4)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)

# --- части по положению центра грани
def part_of(c):
    if c.x < -0.27:
        return "tail"
    if c.x > 0.3:
        return "nose"
    if c.y > 0.13:
        return "wing_l"
    if c.y < -0.13:
        return "wing_r"
    return "body"


parts = {}
for name in ["tail", "nose", "wing_l", "wing_r"]:
    bm = bmesh.new()
    bm.from_mesh(body.data)
    gone = [f for f in bm.faces if part_of(f.calc_center_median()) != name]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in body.data.materials:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    parts[name] = ob
bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if part_of(f.calc_center_median()) != "body"], context="FACES")
bm.to_mesh(body.data)
bm.free()
parts["body"] = body

# --- разброс: (сдвиг x, y, поворот вокруг вертикали, крен, тангаж) — градусы
LAYOUT = {
    "body":   (0.0, 0.0, 0.0, 22.0, 3.0),
    "nose":   (0.1, 0.04, 28.0, 40.0, -6.0),
    "wing_l": (0.0, 0.07, -8.0, -9.0, 0.0),
    "wing_r": (-0.08, -0.3, 55.0, 172.0, 0.0),    # оторвано и перевёрнуто
    "tail":   (-0.17, 0.03, -38.0, 14.0, 0.0),     # хвост отломан, лёг с креном
}
for name, ob in parts.items():
    dx, dy, yaw, roll, pitch = LAYOUT[name]
    me = ob.data
    cen = sum((v.co for v in me.vertices), Vector()) / max(len(me.vertices), 1)
    rot = Euler((math.radians(roll), math.radians(pitch), math.radians(yaw)), "XYZ").to_matrix().to_4x4()
    me.transform(Matrix.Translation(cen) @ rot @ Matrix.Translation(-cen))
    me.transform(Matrix.Translation((dx, dy, 0)))
    # лечь на землю: нижняя точка чуть в грунте, остов приплюснут (смят ударом)
    zmin = min(v.co.z for v in me.vertices)
    me.transform(Matrix.Translation((0, 0, -zmin - 0.008)))
    me.transform(Matrix.Diagonal((1, 1, 0.75, 1)))

# --- обожжённая текстура: темнее, пятна копоти, к краям ржавчина
for img in bpy.data.images:
    if img.name != "Image_0" or img.size[0] == 0:
        continue
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    n = rng.random((h // 32 + 2, w // 32 + 2)).astype(np.float32)
    big = np.kron(n, np.ones((32, 32), np.float32))[:h, :w]
    from PIL import Image, ImageFilter
    big = np.asarray(Image.fromarray((big * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)), np.float32) / 255
    soot = np.clip((big - 0.35) * 2.2, 0, 1)
    lum = px[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
    burnt = np.stack([lum * 0.62, lum * 0.5, lum * 0.42], -1) * 0.75          # обгорелый металл
    rust = np.array([0.32, 0.17, 0.08], np.float32)
    col = px[..., :3] * 0.35 + burnt * 0.65
    col = col * (1 - 0.25 * (1 - soot[..., None])) + rust * 0.25 * (1 - soot[..., None])
    col *= (1 - 0.7 * soot[..., None])
    px[..., :3] = col
    img.pixels.foreach_set(px.ravel())
    img.pack()
    print("BURNT", img.name)

# --- мелкие обломки вокруг (тёмный металл)
m_debris = bpy.data.materials.new("debris")
m_debris.use_nodes = True
b = m_debris.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.05, 0.045, 0.04, 1)
b.inputs["Metallic"].default_value = 0.4
b.inputs["Roughness"].default_value = 0.7
for i in range(18):
    a = rng.uniform(0, 2 * math.pi)
    r = rng.uniform(0.15, 0.45)
    s = rng.uniform(0.012, 0.045)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(math.cos(a) * r * 1.1, math.sin(a) * r * 0.8, s * 0.15))
    ob = bpy.context.object
    ob.scale = (s * rng.uniform(1, 2.5), s, s * 0.25)
    ob.rotation_euler = (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(0, math.pi))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    ob.data.materials.append(m_debris)

# --- нормировка: центр в нуле, наибольший размер в плане = 1, стоит на z = 0
allv = [ob.matrix_world @ v.co for ob in sc.objects if ob.type == "MESH" for v in ob.data.vertices]
lo = Vector((min(v.x for v in allv), min(v.y for v in allv), min(v.z for v in allv)))
hi = Vector((max(v.x for v in allv), max(v.y for v in allv), max(v.z for v in allv)))
k = 1.0 / max(hi.x - lo.x, hi.y - lo.y)
T = Matrix.Diagonal((k, k, k, 1)) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0))
for ob in sc.objects:
    if ob.type == "MESH":
        ob.data.transform(T @ ob.matrix_world)
        ob.matrix_world = Matrix.Identity(4)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88)
tris = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in sc.objects if ob.type == "MESH")
print("WRECK %s: %d треугольников, высота %.2f" % (dst, tris, (hi.z - lo.z) * k))
