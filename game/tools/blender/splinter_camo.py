"""Т-2: камуфляж класса «Оса» на «Осе 2» (каталог: кили в тон фюзеляжа, камуфляж как у «Осы 1»).
У «Осы 2» развёртка аккуратная, но окраска одноцветная, а кили — темнее. Перекрашиваем по 3D-координате точки
обшивки (карта положений запекается Cycles в развёртку модели), а не по атласу: «осколочный» камуфляж из
прямых кромок — области между случайными плоскостями, каждая область тёмная или светлая. Цвета — палитра
«Осы 1» (clean_camo.py, k-means). Швы и лючки — множитель из высоких частот исходной яркости; фонарь, сопла,
ниши (тёмное) и обтекатель носа — исходные. Кили перекрашиваются вместе со всем — становятся в тон.
Пишет извлечённый *_0.png ангара и, если задан, *_Image_0.jpg боевой модели (та же развёртка).
Набор цветов — PRESETS: «osa» — голубой «Осы 1»; «kit» — песочный класса «Кит» (цвет класса в интерфейсе
Color(0.95, 0.85, 0.55), каталог: оба «Кита» голый металл). У «Кита» краска матовая: в карте
металличности/шероховатости (соседняя картинка *_1 / *_Image_1, glTF: G — шероховатость, B — металл)
окрашенная обшивка становится менее металлической и более шероховатой.

Запуск (bpy 5.x): python3 splinter_camo.py <набор osa|kit> <модель ангара.glb> <текстура ангара _0.png> [боевая _Image_0.jpg]"""
import sys
import numpy as np
import bpy
from PIL import Image, ImageFilter

# dark / light — цвета областей, nose_x — дальше по носу обшивка исходная (радиопрозрачный обтекатель),
# matte — (металл не больше, шероховатость не меньше) для окрашенного, None — карту не трогаем
PRESETS = {
    "osa": {"dark": [0.264, 0.37, 0.504], "light": [0.544, 0.662, 0.841], "dark_share": 0.38, "nose_x": 0.37,
            "seed": 4, "matte": None},     # «Оса 1» после clean_camo.py
    "kit": {"dark": [0.36, 0.3, 0.21], "light": [0.52, 0.45, 0.32], "dark_share": 0.4, "nose_x": 0.44,
            "seed": 7, "matte": (0.15, 0.5)},
}
PLANES = 9            # плоскостей-разрезов
LUMA = np.array([0.299, 0.587, 0.114], np.float32)

pr = PRESETS[sys.argv[1]]
glb, tex_f = sys.argv[2], sys.argv[3]
battle_f = sys.argv[4] if len(sys.argv) > 4 else None
DARK, LIGHT = np.array(pr["dark"]), np.array(pr["light"])
DARK_SHARE, NOSE_X, SEED = pr["dark_share"], pr["nose_x"], pr["seed"]

# --- карта положений: Emission(Position) → запекание в развёртку
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
src_im = Image.open(tex_f)
R = src_im.size[1]
obs = [o for o in sc.objects if o.type == "MESH"]
img = bpy.data.images.new("pos", R, R, float_buffer=True, alpha=True)
img.generated_color = (0, 0, 0, 0)
for o in obs:
    for m in o.data.materials:
        nt = m.node_tree
        out_n = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(geo.outputs["Position"], em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], out_n.inputs["Surface"])
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        nt.nodes.active = tn
bpy.ops.object.select_all(action="DESELECT")
for o in obs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
bpy.ops.object.bake(type="EMIT", margin=4)
pos = np.array(img.pixels[:], dtype=np.float32).reshape(R, R, 4)[::-1]
P = pos[..., :3]
cov = pos[..., 3] > 0

# --- «осколки»: знак каждой плоскости — бит номера области; цвет области — по хэшу номера
rng = np.random.default_rng(SEED)
code = np.zeros(P.shape[:2], np.int64)
for k in range(PLANES):
    n = rng.normal(size=3)
    n[2] *= 0.35          # разрезы в основном «сверху вниз»: на виде сверху пятна крупные
    n /= np.linalg.norm(n)
    c = rng.uniform([-0.4, -0.25, -0.05], [0.4, 0.25, 0.05])
    code |= (((P - c) @ n) > 0).astype(np.int64) << k
h = ((code * 2654435761 + SEED * 97) % 4294967296) / 4294967296.0
dark = h < DARK_SHARE
camo = np.where(dark[..., None], DARK, LIGHT)

src = src_im.convert("RGB")
rgb = np.asarray(src, np.float32) / 255
lum = rgb @ LUMA
s = R / 2048.0


def gray(a, f):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(f), np.float32) / 255


blur = gray(lum, ImageFilter.GaussianBlur(4 * s))
detail = 1 + (np.clip(lum / np.maximum(blur, 0.05), 0.7, 1.08) - 1) * 0.8
new = np.clip(camo * detail[..., None], 0, 1)

# исходным остаётся: фонарь и сопла (тёмное), обтекатель носа, фон атласа
keep = np.clip((0.3 - blur) / 0.06, 0, 1)
keep = np.maximum(keep, np.clip((P[..., 0] - NOSE_X) / 0.01, 0, 1))
keep = np.where(cov, keep, 1.0)
keep = gray(gray(keep, ImageFilter.MedianFilter(5)), ImageFilter.MaxFilter(3))[..., None]
new = new * (1 - keep) + rgb * keep

out = Image.fromarray((new * 255 + 0.5).astype(np.uint8), "RGB")
out.save(tex_f)
print("SAVED", tex_f)
if battle_f:
    b = Image.open(battle_f)
    out.resize(b.size, Image.LANCZOS).save(battle_f, quality=92)
    print("SAVED", battle_f)

# матовая краска: карта металличности/шероховатости той же развёртки
if pr["matte"]:
    metal, rough = pr["matte"]
    paint = 1 - keep[..., 0]
    for f in [tex_f.replace("_0.png", "_1.png"), battle_f.replace("Image_0", "Image_1") if battle_f else None]:
        if not f:
            continue
        im = Image.open(f)
        a = np.asarray(im.convert("RGB"), np.float32) / 255
        pm = np.asarray(Image.fromarray((paint * 255).astype(np.uint8)).resize(im.size, Image.BILINEAR), np.float32)[..., None] / 255
        m = a.copy()
        m[..., 1] = np.maximum(a[..., 1], rough)
        m[..., 2] = np.minimum(a[..., 2], metal)
        a = a * (1 - pm) + m * pm
        o = Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGB")
        o.save(f, quality=92) if f.endswith(".jpg") else o.save(f)
        print("SAVED", f)
