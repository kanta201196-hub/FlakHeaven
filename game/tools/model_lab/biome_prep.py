# B-41: доводка моделей биома из Meshy под игру.
#   упрощение до бюджета (decimate_glb.py) → текстуры не больше 1024 → цвет под палитру
#   стайл-гайда → модель стоит на y = 0, центр по X/Z в нуле, наибольший размер по X/Z = 1
#   (игра масштабирует под размер в пикселях мира).
#   python3 -m pip install pymeshlab trimesh   (pymeshlab на Linux нужна libopengl0)
#   python3 tools/model_lab/biome_prep.py <папка raw> <папка вывода> [имена моделей…]   (без имён — все)
import sys, os, subprocess, tempfile, io
import numpy as np
import trimesh
from PIL import Image, ImageEnhance

# имя: (треугольников, текстура, насыщенность, яркость, оттенок RGB)
# Скалы и валуны Meshy светлее земли и рыжее палитры — приглушаем; деревья чуть темнее и спокойнее.
MODELS = {
    "b01_rock_outcrop": (3000, 1024, 0.45, 0.78, (0.97, 0.95, 0.92)),
    "b02_boulders": (3000, 1024, 0.7, 0.82, (1.0, 0.95, 0.86)),
    "b03_rock_spire": (3000, 1024, 0.45, 0.8, (0.97, 0.95, 0.92)),
    "b04_poplar": (2000, 1024, 0.85, 0.9, (1.0, 1.0, 0.95)),
    "b05_orchard_tree": (2000, 1024, 0.85, 0.9, (1.0, 1.0, 0.95)),
    "b06_shrub": (900, 512, 0.8, 0.88, (1.0, 1.0, 0.94)),
    "b07_wreck_truck": (7000, 1024, 0.8, 0.85, (1.0, 0.97, 0.94)),   # Т-9: было 4000 — угловатые колёса
    "b08_wreck_tank": (7000, 1024, 0.8, 0.85, (1.0, 0.97, 0.94)),
    "b10_sandbag_post": (2000, 1024, 0.8, 0.88, (1.0, 0.97, 0.92)),
}

src_dir, dst_dir = sys.argv[1], sys.argv[2]
os.makedirs(dst_dir, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
only = sys.argv[3:]
for name, (tris, tex, sat, val, tint) in MODELS.items():
    if only and name not in only:
        continue
    with tempfile.TemporaryDirectory() as d:
        mid = os.path.join(d, "m.glb")
        subprocess.run([sys.executable, os.path.join(here, "decimate_glb.py"), os.path.join(src_dir, name + ".glb"), mid, str(tris), str(tex)], check=True)
        scene = trimesh.load(mid, force="scene")
    mesh = scene.to_geometry() if hasattr(scene, "to_geometry") else scene.dump(concatenate=True)
    mat = mesh.visual.material
    img = mat.baseColorTexture.convert("RGB")
    img = ImageEnhance.Color(img).enhance(sat)
    a = np.asarray(img, dtype=np.float32) * val * np.array(tint, dtype=np.float32)
    mat.baseColorTexture = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    # JPEG вместо PNG внутри GLB: в 3–4 раза меньше; карта металл/шероховатость — вдвое меньше
    for key in ("baseColorTexture", "metallicRoughnessTexture", "normalTexture"):
        im = getattr(mat, key, None)
        if im is None:
            continue
        im = im.convert("RGB")
        if key == "metallicRoughnessTexture":
            im = im.resize((im.size[0] // 2, im.size[1] // 2), Image.LANCZOS)
        b = io.BytesIO()
        im.save(b, format="JPEG", quality=90)
        b.seek(0)
        setattr(mat, key, Image.open(b))
    lo, hi = mesh.bounds
    mesh.apply_translation([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])
    ext = mesh.extents
    mesh.apply_scale(1.0 / max(ext[0], ext[2]))
    mesh.vertex_attributes.clear()
    out = os.path.join(dst_dir, name + ".glb")
    trimesh.Scene(mesh).export(out, include_normals=True)
    print("%s: %d треугольников, высота %.2f от ширины, %d КБ" % (name, len(mesh.faces), mesh.extents[1], os.path.getsize(out) // 1024))
