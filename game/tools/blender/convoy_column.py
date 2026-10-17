"""Кадр колонны конвоя как в игре: машины в порядке марша на песчаной дороге, камера с наклоном 28°.
Длины машин — как на экране (концепция, раздел 10.1). Запуск: python3 convoy_column.py <папка с GLB> <out.png>"""
import sys, os, math
import bpy
from mathutils import Vector

SRC, OUT = sys.argv[-2], sys.argv[-1]
# порядок марша (раздел 3) и длина на экране, пикс.
ORDER = [("scout", 40), ("technical", 36), ("truck", 58), ("pickup_tent", 38), ("truck", 58), ("ifv", 52), ("manpads", 36)]
GAP = 22.0

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
x = 0.0
for i, (k, ln) in enumerate(ORDER):
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "convoy_%s.glb" % k))
    roots = [o for o in bpy.context.selected_objects if o.parent is None]
    for r in roots:
        r.scale = (ln, ln, ln)
        r.location = (x - ln / 2, 0, 0)
    x -= ln + GAP

# дорога и обочина
def plane(name, size, loc, rgb):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc)
    o = bpy.context.object
    o.scale = (*size, 1)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
    o.data.materials.append(m)

mid = x / 2
plane("ground", (1200, 800), (mid, 0, -0.05), (0.55, 0.47, 0.36))
plane("road", (1200, 34), (mid, 0, 0.0), (0.46, 0.4, 0.31))

w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.85, 0.9, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(-30))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
# камера игры: наклон 28° от вертикали, высота такая, чтобы колонна занимала ~2/3 ширины кадра
d = 900.0
cam.location = (mid, -d * math.sin(math.radians(28)), d * math.cos(math.radians(28)))
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (Vector((mid, 0, 0)) - cam.location).to_track_quat("-Z", "Y")
cam.data.lens = 50
sc.render.engine = "CYCLES"
sc.cycles.samples = 48
sc.cycles.device = "CPU"
sc.render.resolution_x = 1600
sc.render.resolution_y = 600
sc.view_settings.view_transform = "AgX"
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("DONE")
