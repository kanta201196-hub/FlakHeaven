"""Картинки техники сверху для боя (art/enemies/e_<имя>.png): нос вправо, ширина картинки = длина модели (1),
прозрачный фон — как у остальных наземных целей; 3D-модель боя берёт масштаб от ширины. Нужны и на «Низком»
качестве графики, где вместо моделей рисуются картинки.
Запуск: python3 convoy_sprites.py <папка с convoy_*.glb> <папка art/enemies>             — машины конвоя
        python3 convoy_sprites.py <папка с ground_*.glb> <папка art/enemies> --ground    — позиция ПВО (ground_models.py)"""
import sys, os, math
import bpy

GROUND = "--ground" in sys.argv
args = [a for a in sys.argv if a != "--ground"]
SRC, OUT = args[-2], args[-1]
if GROUND:
    # высота картинки — по ширине модели сверху: у РЛС зеркало шире машины, бункер почти квадратный
    KINDS = {"zsu": 96, "sam": 96, "radar": 160, "bunker": 212}
    SRCN = "ground_%s.glb"
    OUTN = "e_%s.png"
else:
    KINDS = {k: 128 for k in ["truck", "pickup_tent", "ifv", "scout", "technical", "manpads"]}
    SRCN = "convoy_%s.glb"
    OUTN = "e_convoy_%s.png"
for k, h in KINDS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, SRCN % k))
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
    sc.render.resolution_y = h
    sc.view_settings.view_transform = "Standard"
    sc.render.filepath = os.path.join(OUT, OUTN % k)
    bpy.ops.render.render(write_still=True)
print("DONE")
