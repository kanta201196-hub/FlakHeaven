# Упрощение GLB из генераторов (TRELLIS.2 отдаёт от 100 000 треугольников) до бюджета игры
# с сохранением UV и PBR-материала. Запускать до `model_lab.gd prep`.
#   python3 -m pip install pymeshlab trimesh   (pymeshlab на Linux нужна libopengl0)
#   python3 decimate_glb.py <in.glb> <out.glb> [треугольников=12000] [макс. текстура=2048]
import sys, os, tempfile
import numpy as np
import trimesh, pymeshlab
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
target = int(sys.argv[3]) if len(sys.argv) > 3 else 12000
tex_max = int(sys.argv[4]) if len(sys.argv) > 4 else 2048  # Hunyuan отдаёт 4096 — для игры с запасом хватит 2048

scene = trimesh.load(src, force="scene")
out = trimesh.Scene()
for name, g in scene.geometry.items():
    mat = g.visual.material
    for key in ("baseColorTexture", "metallicRoughnessTexture", "normalTexture", "emissiveTexture", "occlusionTexture"):
        img = getattr(mat, key, None)
        if img is not None and max(img.size) > tex_max:
            setattr(mat, key, img.resize((tex_max, tex_max * img.size[1] // img.size[0]), Image.LANCZOS))
    with tempfile.TemporaryDirectory() as d:
        ms = pymeshlab.MeshSet()
        uv = np.asarray(g.visual.uv, dtype=np.float64)
        ms.add_mesh(pymeshlab.Mesh(vertex_matrix=g.vertices, face_matrix=g.faces, v_tex_coords_matrix=uv))
        # UV по вершинам → по углам граней: так фильтр с текстурой не рвёт швы развёртки
        ms.compute_texcoord_transfer_vertex_to_wedge()
        # GLB режет вершины по швам UV — сшиваем по положению, иначе швы считаются краями и не упрощаются
        ms.meshing_merge_close_vertices(threshold=pymeshlab.PercentageValue(0.01))
        ms.meshing_decimation_quadric_edge_collapse_with_texture(
            targetfacenum=target, qualitythr=0.5, extratcoordw=1.0,
            preserveboundary=False, optimalplacement=True, preservenormal=True, planarquadric=True)
        path = os.path.join(d, "m.obj")
        ms.save_current_mesh(path, save_wedge_texcoord=True, save_textures=False)
        m = trimesh.load(path, process=False, force="mesh")
    m.visual = trimesh.visual.TextureVisuals(uv=m.visual.uv, material=mat)
    m.vertex_attributes.clear()  # OBJ добавляет цвет вершин — в игре он лишний
    out.add_geometry(m, node_name=name, geom_name=name)
    print("%s: %d → %d треугольников" % (name, len(g.faces), len(m.faces)))
out.export(dst, include_normals=True)  # без нормалей Godot освещает модель темнее
print("GLB:", dst, os.path.getsize(dst) // 1024, "КБ")
