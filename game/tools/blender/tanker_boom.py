"""Свой заправщик для боя: облегчённая модель Meshy + выдвижная заправочная штанга (разбор каталога 7.1,
решение владельца 16.10: штанга выдвигается и стыкуется с самолётом игрока).
Запуск: python3 tanker_boom.py <tanker_prep.glb> <out.glb> [треугольников=10000]
Вход — модель после model_lab prep (длина 1, нос +X). Узлы штанги в GLB:
  Boom      — основание под хвостом: обтекатель и V-рули; поворачивается вбок (rotation.y = boom_angle);
  BoomTube  — внутренняя труба, ось −X с наклоном вниз; длина 1, в игре scale.x = длина выдвижения;
  BoomTip   — наконечник; в игре ставится на конец трубы.
Наклон штанги вниз — PITCH (в игре тот же)."""
import sys, math
import bpy
from mathutils import Vector, Matrix

src, dst = sys.argv[-2] if len(sys.argv) > 3 and not sys.argv[-1].isdigit() else sys.argv[-3], None,
args = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else sys.argv[1:]
src, dst = args[0], args[1]
budget = int(args[2]) if len(args) > 2 else 10000
PITCH = math.radians(10)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.object
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")   # масштаб prep лежит на корневом узле
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
body.name = "tanker"
total = sum(len(p.vertices) - 2 for p in body.data.polygons)
md = body.modifiers.new("dec", "DECIMATE")
md.ratio = min(1.0, budget / max(total, 1))
md.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, max(1, int(img.size[1] * 1024 / img.size[0])))
for o in list(bpy.context.scene.objects):
    if o != body and o.type != "MESH":
        bpy.data.objects.remove(o)

# хвост: самая задняя точка фюзеляжа у оси, высота — середина фюзеляжа там
vs = [body.matrix_world @ v.co for v in body.data.vertices]
xmin = min(v.x for v in vs if abs(v.y) < 0.02)
near = [v for v in vs if abs(v.y) < 0.03 and v.x < xmin + 0.08]
zc = (min(v.z for v in near) + max(v.z for v in near)) * 0.5
zlow = min(v.z for v in near)
root = Vector((xmin + 0.07, 0.0, zlow + 0.004))
print("TAIL", xmin, zc, "ROOT", tuple(root))


def mat(name, rgb, metal=0.5, rough=0.45):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m

M_BOOM = mat("boom_hull", (0.62, 0.63, 0.64))
M_DARK = mat("boom_dark", (0.08, 0.08, 0.09))
M_LIGHT = mat("boom_light", (0.9, 0.85, 0.3), 0.1, 0.5)


def join_parts(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    return o


def cyl_x(r, x0, x1, m, verts=14):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=abs(x1 - x0), location=((x0 + x1) / 2, 0, 0))
    o = bpy.context.object
    o.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(m)
    return o


def box(c, s, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    o = bpy.context.object
    o.scale = s
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(m)
    return o


def fin(ang):
    # V-руль на конце наружной трубы
    o = box((-0.115, 0, 0.022), (0.03, 0.002, 0.04), M_BOOM)
    o.rotation_euler = (ang, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return o


# все части строятся в осях штанги (ось −X), потом наклоняются на PITCH и ставятся в root
outer = [box((0.0, 0, 0.004), (0.05, 0.022, 0.014), M_BOOM),
         cyl_x(0.0075, -0.13, 0.0, M_BOOM),
         fin(math.radians(35)), fin(math.radians(-35)),
         box((-0.02, 0, 0.0), (0.012, 0.016, 0.008), M_DARK)]
boom = join_parts(outer, "Boom")
tube = join_parts([cyl_x(0.0045, -1.0, 0.0, M_BOOM, 10), cyl_x(0.0048, -0.02, 0.0, M_DARK, 10)], "BoomTube")
tip = join_parts([cyl_x(0.006, -0.03, 0.0, M_DARK, 10), cyl_x(0.0035, -0.045, -0.03, M_LIGHT, 8)], "BoomTip")

rot = Matrix.Rotation(-PITCH, 4, "Y")   # конец штанги (−X) уходит вниз
for o in (boom, tube, tip):
    o.data.transform(rot)              # наклон запекается в геометрию основания
# основание — в точке крепления; труба и наконечник — дети основания с наклоном в осях узла
for o in (tube, tip):
    o.data.transform(rot.inverted())   # у трубы наклон — поворот узла (чтобы scale.x вытягивал вдоль оси)
    o.rotation_euler = (0, -PITCH, 0)
boom.location = root
for o in (tube, tip):
    o.parent = boom
    o.location = (0, 0, 0)
tip.location = rot @ Vector((-0.2, 0, 0))
body.select_set(False)
boom.parent = body
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88)
print("DONE", dst, sum(len(p.vertices) - 2 for p in body.data.polygons))
