"""Т-7: вражеский транспортник для боя из сырой модели Meshy (план после разбора каталога, п. 1.2, 1.3, 7.2).
Вход — модель после model_lab.gd prep (нос +X, длина 1, центр по высоте):
  godot --headless --path . --script res://tools/model_lab/model_lab.gd -- prep transport_meshy_raw.glb prep.glb --nose=-x --budget=30000
Что делает:
  • окраска врага, как у ЗСУ и «Крепости»: тёмный металл с красными полосами — кольца на фюзеляже за кабиной
    и перед хвостом, красные законцовки крыла и стабилизатора, верх киля. Перекраска по 3D-координате точки
    обшивки (карта положений запекается Cycles в развёртку, как в splinter_camo.py);
  • надписи и знаки Meshy стираются: из исходной текстуры берутся только тёмные швы (множитель ≤ 1),
    цветные пятна (трафареты) и светлые круги пропадают; фонарь, винты и ниши (тёмное) — исходные;
  • 3 детали силуэта «по мотивам»: гондолы на законцовках крыла, подвесные баки под крылом у фюзеляжа
    (выступают вперёд кромки), гаргрот-«каноэ» на спине.
Дальше: battle_lod.py → models/battle/fh_battle_e_transport.glb; спрайт сверху — tools/model_lab/sprite_top.gd.

Запуск (bpy 5.x): python3 transport_enemy.py <prep.glb> <out.glb>"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bpy
from mathutils import Vector
from PIL import Image, ImageFilter

src, dst = sys.argv[-2], sys.argv[-1]
HULL = np.array([0.32, 0.33, 0.33])      # sRGB, тёмный металл (≈ enemy_hull «Крепости» 0.13 линейн.)
RED = np.array([0.68, 0.17, 0.13])        # sRGB, enemy_red
BANDS_X = [(0.265, 0.305), (-0.31, -0.27)]   # кольца на фюзеляже
WING_TIP = 0.46       # |y| дальше — красная законцовка крыла
STAB_TIP = (-0.37, 0.17)   # x < …, |y| > … — законцовки стабилизатора
FIN_TOP = 0.115       # z выше — верх киля
LUMA = np.array([0.299, 0.587, 0.114], np.float32)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
obs = [o for o in sc.objects if o.type == "MESH"]

# --- текстура цвета (Base Color)
base_img = None
for o in obs:
    for m in o.data.materials:
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        for l in b.inputs["Base Color"].links:
            n = l.from_node
            while n.type != "TEX_IMAGE" and n.inputs and n.inputs[0].links:
                n = n.inputs[0].links[0].from_node
            if n.type == "TEX_IMAGE":
                base_img = n.image
W, H = base_img.size
print("TEX", base_img.name, W, H)

# --- карта положений: Emission(Position) → запекание в развёртку; потом материал возвращается
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
pos_img = bpy.data.images.new("pos", W, H, float_buffer=True, alpha=True)
pos_img.generated_color = (0, 0, 0, 0)
restore = []
for o in obs:
    for m in o.data.materials:
        nt = m.node_tree
        out_n = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        old = out_n.inputs["Surface"].links[0].from_socket
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(geo.outputs["Position"], em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], out_n.inputs["Surface"])
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = pos_img
        nt.nodes.active = tn
        restore.append((nt, out_n, old, [geo, em, tn]))
bpy.ops.object.select_all(action="DESELECT")
for o in obs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
bpy.ops.object.bake(type="EMIT", margin=4)
pos = np.array(pos_img.pixels[:], dtype=np.float32).reshape(H, W, 4)
for nt, out_n, old, nodes in restore:
    nt.links.new(old, out_n.inputs["Surface"])
    for n in nodes:
        nt.nodes.remove(n)
P, cov = pos[..., :3], pos[..., 3] > 0

# --- перекраска (пиксели Blender: строки снизу вверх, как и карта положений)
px = np.array(base_img.pixels[:], dtype=np.float32).reshape(H, W, 4)
rgb = px[..., :3]
lum = rgb @ LUMA
sat = rgb.max(-1) - rgb.min(-1)
s = W / 2048.0


def filt(a, f):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(f), np.float32) / 255


blur = filt(lum, ImageFilter.GaussianBlur(5 * s))
detail = np.clip(lum / np.maximum(blur, 0.05), 0.8, 1.0)          # только тёмные швы
detail = np.where(sat > 0.12, 1.0, detail)                          # цветные трафареты — стереть
detail = filt(detail, ImageFilter.MedianFilter(3))
red = np.zeros(lum.shape, bool)
for x0, x1 in BANDS_X:
    red |= (P[..., 0] > x0) & (P[..., 0] < x1) & (np.abs(P[..., 1]) < 0.09)
red |= (np.abs(P[..., 1]) > WING_TIP)
red |= (P[..., 0] < STAB_TIP[0]) & (np.abs(P[..., 1]) > STAB_TIP[1])
red |= (P[..., 2] > FIN_TOP) & (np.abs(P[..., 1]) < 0.03)
col = np.where(red[..., None], RED, HULL) * (0.55 + 0.45 * detail[..., None])
keep = np.clip((0.16 - filt(lum, ImageFilter.GaussianBlur(3 * s))) / 0.05, 0, 1)   # фонарь, винты, ниши
keep = np.where(cov, keep, 1.0)[..., None]
px[..., :3] = col * (1 - keep) + rgb * keep
base_img.pixels.foreach_set(px.ravel())
base_img.pack()

# --- детали силуэта
dg = bpy.context.evaluated_depsgraph_get()


def hit(o, d):
    ok, loc, *_ = sc.ray_cast(dg, Vector(o), Vector(d))
    return loc if ok else None


def lin(c):
    c = np.asarray(c)
    return tuple(np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4))


def mat(name, rgb, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(rgb), 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


M_HULL = mat("enemy_hull", HULL * 0.95, 0.5, 0.5)
M_RED = mat("enemy_red", RED, 0.2, 0.5)
M_DARK = mat("enemy_dark", (0.12, 0.12, 0.13), 0.4, 0.6)


def pod(name, c, r, m, seg=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = r
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


# 1) гондолы на законцовках: центр по хорде законцовки, чуть ниже крыла
half = max(abs((o.matrix_world @ v.co).y) for o in obs for v in o.data.vertices)
for sd in (1, -1):
    y = sd * (half - 0.004)
    xs = [x for x in np.arange(0.2, -0.1, -0.004) if hit((x, y * 0.97, 1.0), (0, 0, -1)) is not None]
    xm = (xs[0] + xs[-1]) / 2 if xs else 0.05
    z = hit((xm, y * 0.97, 1.0), (0, 0, -1)).z if xs else -0.04
    pod("tip_pod", (xm + 0.02, y, z - 0.004), (0.085, 0.013, 0.013), M_HULL)
    pod("tip_pod_nose", (xm + 0.085, y, z - 0.004), (0.03, 0.0105, 0.0105), M_RED)
# 2) подвесные баки под крылом у фюзеляжа: выступают вперёд передней кромки
for sd in (1, -1):
    y = sd * 0.108
    lo = hit((0.05, y, -1.0), (0, 0, 1))
    z = lo.z if lo is not None else -0.05
    pod("tank", (0.07, y, z - 0.022), (0.1, 0.019, 0.019), M_HULL)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0.06, y, z - 0.008))
    py = bpy.context.object
    py.name = "tank_pylon"
    py.scale = (0.06, 0.005, 0.016)
    bpy.ops.object.transform_apply(scale=True)
    py.data.materials.append(M_DARK)
# 3) гаргрот-«каноэ» на спине: от крыла назад, вдоль верха фюзеляжа
top = hit((0.0, 0.0, 1.0), (0, 0, -1))
ztop = top.z if top is not None else -0.02
pod("canoe", (-0.12, 0, ztop - 0.002), (0.16, 0.022, 0.016), M_HULL, 28)

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT")
print("DONE", dst)
