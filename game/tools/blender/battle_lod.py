"""Облегчённая модель для боя из модели ангара (решение 14.10: в бою 5–15 тыс. треугольников).
Запуск: python3 battle_lod.py <in.glb> <out.glb> [треугольников=9000] [текстура=1024]
Оси и масштаб не меняются (длина 1, нос +X) — в игре модель ставится так же, как в ангаре."""
import sys
import bpy

src, dst = sys.argv[1], sys.argv[2]
budget = int(sys.argv[3]) if len(sys.argv) > 3 else 9000
texsz = int(sys.argv[4]) if len(sys.argv) > 4 else 1024
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
total = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
for o in meshes:
    md = o.modifiers.new("dec", "DECIMATE")
    md.ratio = min(1.0, budget / max(total, 1))
    md.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="dec")
for img in bpy.data.images:
    if img.size[0] > texsz:
        k = texsz / img.size[0]
        img.scale(texsz, max(1, int(img.size[1] * k)))
after = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88)
print("LOD %s: %d -> %d tris" % (dst, total, after))
