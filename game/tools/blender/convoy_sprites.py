"""Картинки техники конвоя сверху для боя (art/enemies/e_convoy_<имя>.png): нос вправо, ширина картинки =
длина модели (1), прозрачный фон — как у остальных наземных целей; 3D-модель боя берёт масштаб от ширины.
Запуск: python3 convoy_sprites.py <папка с convoy_*.glb> <папка art/enemies>"""
import sys, os, math
import bpy

SRC, OUT = sys.argv[-2], sys.argv[-1]
KINDS = ["truck", "pickup_tent", "ifv", "scout", "technical", "manpads"]
for k in KINDS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "convoy_%s.glb" % k))
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(25), math.radians(10), 0)
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.0
    cam.location = (0, 0, 3)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 32
    sc.cycles.device = "CPU"
    sc.render.film_transparent = True
    sc.render.resolution_x = 256
    sc.render.resolution_y = 128
    sc.view_settings.view_transform = "Standard"
    sc.render.filepath = os.path.join(OUT, "e_convoy_%s.png" % k)
    bpy.ops.render.render(write_still=True)
print("DONE")
