"""Обломки в биоме — объёмные остовы на земле (тест 3.5-s4, п. 18; варианты — тест 3.5-s8, правка Kanta 19.10:
«ещё 2 версии расположения обломков и обломки вертолёта»). Из боевой модели машины игры (по мотивам, без знаков):
корпус разрезается по положению граней на части, части разбросаны, перевёрнуты и легли на землю (z = 0),
текстура обожжена и в пыли (темнее, копоть пятнами, ржавчина, рыжая пыль), краска матовая; вокруг мелкие обломки.

Раскладки (layout):
  a    — самолёт развалился на месте: нос, крылья, хвост рядом с фюзеляжем, одно крыло перевёрнуто (как было);
  b    — посадка на брюхо: самолёт целиком с подломленным крылом, хвост оторвало в начале юза — лежит отдельно
         в конце борозды (борозда — вдоль −X, там же сцена боя рисует выгоревшую полосу, terrain3d.gd);
  c    — фюзеляж переломлен пополам: передняя половина с одним крылом, задняя с оперением — развёрнута и на боку,
         второе крыло оторвано и лежит в стороне перевёрнутым;
  heli — вертолёт: кабина с фюзеляжем на боку, хвостовая балка отломана, лопасти несущего винта — в стороны
         (часть согнута, одна отброшена), рулевой винт — на конце балки.
Единицы как у моделей биома (tools/model_lab/biome_prep.py): стоит на z = 0 (в Godot y = 0), центр в нуле,
наибольший размер в плане = 1 (борозда в b — сверх этого, позади) — игра масштабирует под размер (biome_props.gd,
render3d.gd o_wreck).

Запуск (bpy 5.x): python3 plane_wreck.py <боевая модель.glb> <out.glb> [seed] [layout]
  b11_wreck_plane   = fh_battle_e_interceptor.glb 3 a
  b11_wreck_plane_b = fh_battle_e_rival.glb 5 b
  b11_wreck_plane_c = fh_battle_attacker_1.glb 8 c
  b11_wreck_heli    = fh_battle_e_helicopter.glb 4 heli"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, Euler, noise

args = [a for a in sys.argv[1:]]
src, dst = args[0], args[1]
seed = int(args[2]) if len(args) > 2 else 3
layout = args[3] if len(args) > 3 else "a"
rng = np.random.default_rng(seed)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
obs = [o for o in sc.objects if o.type == "MESH"]
for o in obs:   # подвижные узлы (винты) — в общие координаты до слияния
    o.data.transform(o.matrix_world)
for o in obs:
    o.parent = None
    o.matrix_world = Matrix.Identity(4)


def join(lst):
    bpy.ops.object.select_all(action="DESELECT")
    for o in lst:
        o.select_set(True)
    bpy.context.view_layer.objects.active = lst[0]
    if len(lst) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


rotor = None
if layout == "heli":
    rotor = next(o for o in obs if o.name.startswith("rotor") and not o.name.startswith("rotor_"))
    obs.remove(rotor)
body = join(obs)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
if layout == "heli":
    # 18 тыс. треугольников боевой модели — для остова в биоме вдвое меньше
    md = body.modifiers.new("dec", "DECIMATE")
    md.ratio = 0.45
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier="dec")


def split(ob, part_of, names):
    """Разрезать объект по граням: part_of(центр грани) → имя части; первая часть остаётся в ob"""
    out = {}
    for name in names[1:]:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if part_of(f.calc_center_median()) != name], context="FACES")
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in ob.data.materials:
            me.materials.append(m)
        o = bpy.data.objects.new(name, me)
        sc.collection.objects.link(o)
        out[name] = o
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if part_of(f.calc_center_median()) != names[0]], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    ob.name = names[0]
    out[names[0]] = ob
    for o in out.values():
        ragged(o)
    return out


def ragged(ob, passes=1, prob=0.3):
    """Рваный край разреза: грани у открытой кромки выкусываются случайно (2 прохода)"""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for _ in range(passes):
        edge = set()
        for e in bm.edges:
            if e.is_boundary:
                for f in e.link_faces:
                    edge.add(f)
        gone = [f for f in edge if rng.random() < prob]
        if gone and len(gone) < len(bm.faces) * 0.3:
            bmesh.ops.delete(bm, geom=gone, context="FACES")
    # иглы: длинные узкие треугольники на кромке после выкусывания — убрать, край рваный, но без «шипов»
    for _ in range(3):
        sl = []
        for f in bm.faces:
            if not any(e.is_boundary for e in f.edges):
                continue
            longest = max(e.calc_length() for e in f.edges)
            if longest > 1e-6 and f.calc_area() / (longest * longest) < 0.12:
                sl.append(f)
        if not sl or len(sl) > len(bm.faces) * 0.25:
            break
        bmesh.ops.delete(bm, geom=sl, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()


def holes(ob, sel, prob):
    """Пробоины: случайные грани, где sel(центр грани, материал) — выбиты"""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    mats = [m.name for m in ob.data.materials]
    gone = [f for f in bm.faces if sel(f.calc_center_median(), mats[f.material_index] if mats else "") and rng.random() < prob]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()


def place(ob, dx, dy, yaw, roll, pitch, squash=0.75, sink=0.008, pivot=None, ground_pct=18, dent=0.01):
    """Повернуть часть вокруг её центра (или pivot), сдвинуть и положить на землю, приплюснуть (смята ударом)"""
    me = ob.data
    if len(me.vertices) == 0:
        return
    cen = Vector(pivot) if pivot else sum((v.co for v in me.vertices), Vector()) / len(me.vertices)
    rot = Euler((math.radians(roll), math.radians(pitch), math.radians(yaw)), "XYZ").to_matrix().to_4x4()
    me.transform(Matrix.Translation(cen) @ rot @ Matrix.Translation(-cen))
    me.transform(Matrix.Translation((dx, dy, 0)))
    # лечь на землю всем весом: земля — на уровне нижних 20 % вершин, всё, что ниже, смято в землю
    # (не висит на законцовках и пилонах); вмятины — шумом по обшивке
    zs = np.array([v.co.z for v in me.vertices])
    g = float(np.percentile(zs, ground_pct))
    for v in me.vertices:
        z = v.co.z - g
        if z < 0:
            z = z * 0.08
        dn = noise.noise(v.co * 23.0 + Vector((seed, 0, 0)))
        v.co.z = z * squash - sink + dent * dn
        v.co.x += dent * 0.5 * noise.noise(v.co * 17.0 + Vector((0, seed, 0)))


def bend(ob, axis_pt, along, k):
    """Изогнуть часть: вершины дальше от axis_pt по направлению along опускаются/закручиваются (крыло подломлено)"""
    a = Vector(axis_pt)
    d = Vector(along).normalized()
    for v in ob.data.vertices:
        t = max(0.0, (v.co - a).dot(d))
        v.co.z -= k * t * t


parts = {}
if layout == "heli":
    # фюзеляж: кабина и середина (x > −0,14) и хвостовая балка с рулевым винтом
    parts = split(body, lambda c: "boom" if c.x < -0.14 else "cabin", ["cabin", "boom"])
    hub = Vector((0.209, 0.0, 0.261))
    def blade_of(c):
        d = Vector((c.x - hub.x, c.y - hub.y))
        if d.length < 0.07:
            return "hub"
        a = math.atan2(d.y, d.x) % (2 * math.pi)
        return "blade%d" % int(((a + math.pi / 5) % (2 * math.pi)) / (2 * math.pi / 5))
    parts.update(split(rotor, blade_of, ["hub"] + ["blade%d" % i for i in range(5)]))
    # кабина разбита: остекление выбито почти целиком, в носу и по крыше — пробоины
    holes(parts["cabin"], lambda c, m: "glass" in m, 0.8)
    holes(parts["cabin"], lambda c, m: c.x > 0.25 or c.z > 0.3, 0.22)
    holes(parts["boom"], lambda c, m: True, 0.08)
    ragged(parts["cabin"], 2, 0.35)
    # кабина на левом боку (крен 82°), смята; балка отломана и развёрнута; втулка с мачтой — у бывшего верха кабины
    place(parts["cabin"], 0.0, 0.0, 6.0, -82.0, 2.0, squash=0.7, ground_pct=30, dent=0.014)
    place(parts["boom"], -0.12, 0.13, 32.0, -25.0, 4.0, squash=0.75, ground_pct=25)
    place(parts["hub"], 0.17, -0.33, 0.0, -80.0, 0.0, squash=0.9)
    hubp = sum((v.co for v in parts["hub"].data.vertices), Vector()) / max(len(parts["hub"].data.vertices), 1)
    # лопасти — в стороны от втулки по земле: две согнуты, одна сломана и отброшена
    fan = [(-150, 0.0, 0.0), (-95, 0.06, 0.0), (-40, 0.0, 0.5), (15, 0.0, 0.0), (140, 0.32, 1.2)]
    for i in range(5):
        b = parts["blade%d" % i]
        me = b.data
        if len(me.vertices) == 0:
            continue
        # лопасть — вдоль радиуса: уложить плашмя, комлем к втулке, по направлению веера
        cen = sum((v.co for v in me.vertices), Vector()) / len(me.vertices)
        d0 = Vector((cen.x - hub.x, cen.y - hub.y, 0)).normalized()
        a0 = math.atan2(d0.y, d0.x)
        ang, throw, curl = fan[i]
        ang = math.radians(ang) + rng.uniform(-0.12, 0.12)
        me.transform(Matrix.Translation(-hub))
        me.transform(Matrix.Rotation(ang - a0, 4, "Z"))
        d = Vector((math.cos(ang), math.sin(ang), 0))
        # плашмя: убрать конусность (кончик был выше комля) — лопасть лежит на земле по всей длине
        ts = np.array([v.co.dot(d) for v in me.vertices])
        zs = np.array([v.co.z for v in me.vertices])
        kz = np.polyfit(ts, zs, 1)
        bury = rng.uniform(0.35, 0.7)          # где лопасть ушла под пыль/грунт
        for v, t0 in zip(me.vertices, ts):    # изгиб: лопасть загибается вбок от комля (ударилась о землю)
            t = max(0.0, t0 - 0.12)
            side = Vector((-d.y, d.x, 0))
            v.co += side * curl * t * t
            v.co.z = (v.co.z - (kz[0] * t0 + kz[1])) * 0.6 - (0.006 if abs(t0 / 0.6 - bury) < 0.12 else 0.0)
        me.transform(Matrix.Translation(Vector((hubp.x, hubp.y, 0)) + d * (0.04 + throw)))
        zs = sorted(v.co.z for v in me.vertices)
        me.transform(Matrix.Translation((0, 0, -zs[len(zs) // 5] - 0.002)))
else:
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

    if layout == "a":
        parts = split(body, part_of, ["body", "tail", "nose", "wing_l", "wing_r"])
        # длинные треугольники крыла заходили за линию разлома «зубьями» — подрезать по линии с неровностью
        cut = {"wing_l": (1, 0.115, 1), "wing_r": (1, -0.115, -1), "tail": (0, -0.25, -1), "nose": (0, 0.28, 1)}
        for name, (ax, lim, sg) in cut.items():
            for v in parts[name].data.vertices:
                c = v.co[ax]
                j = 0.012 * math.sin(v.co[1 - ax] * 97.0) + 0.008 * math.sin(v.co[1 - ax] * 211.0)
                if (c - (lim + j)) * sg < 0:
                    v.co[ax] = lim + j
        # разброс: (сдвиг x, y, поворот вокруг вертикали, крен, тангаж) — градусы
        LAYOUT = {
            "body":   (0.0, 0.0, 0.0, 22.0, 3.0),
            "nose":   (0.1, 0.04, 28.0, 40.0, -6.0),
            "wing_l": (0.0, 0.07, -8.0, -9.0, 0.0),
            "wing_r": (-0.08, -0.3, 55.0, 172.0, 0.0),    # оторвано и перевёрнуто
            "tail":   (-0.17, 0.03, -38.0, 14.0, 0.0),     # хвост отломан, лёг с креном
        }
        for name, ob in parts.items():
            place(ob, *LAYOUT[name])
    elif layout == "b":
        # хвост — отдельно (x < −0,33), остальное — одним куском на брюхе, правое крыло подломлено
        # и законцовку левого крыла оторвало при юзе — лежит у борозды перевёрнутой
        parts = split(body, lambda c: "tail" if c.x < -0.33 else ("tip" if c.y > 0.26 else "body"), ["body", "tail", "tip"])
        # правое крыло подломлено вниз — законцовка в земле, корпус на брюхе с креном на это крыло
        for v in parts["body"].data.vertices:
            t = max(0.0, -v.co.y - 0.15)
            v.co.z -= 0.55 * t * t
            v.co.x -= 0.25 * t * t   # и загнуто назад
        place(parts["body"], 0.18, 0.0, 9.0, -4.0, 2.0)
        place(parts["tail"], -0.62, 0.1, 118.0, 24.0, 0.0)
        place(parts["tip"], -0.42, 0.02, 150.0, 170.0, 0.0)
    elif layout == "c":
        # перелом по x = −0,06: перед с левым крылом; зад с оперением развёрнут и на боку; правое крыло — в стороне
        def pc(c):
            if c.y < -0.13 and -0.33 < c.x < 0.1:
                return "wing_r"
            return "front" if c.x > -0.06 else "rear"
        parts = split(body, pc, ["front", "rear", "wing_r"])
        place(parts["front"], 0.08, -0.02, -14.0, -12.0, -4.0)
        place(parts["rear"], -0.2, 0.17, 47.0, 28.0, 0.0)
        place(parts["wing_r"], 0.05, -0.38, -125.0, 176.0, 0.0)
        bend(parts["wing_r"], (0, -0.38, 0), (1, 0, 0), -0.08)

# --- краска: обожжена и в пыли, матовая (Kanta 19.10: никакого блеска, обломки — обгоревшие, в пыли)
from PIL import Image, ImageFilter


def blotch(h, w, cell, blur, off):
    n = np.random.default_rng(seed * 31 + off).random((h // cell + 2, w // cell + 2)).astype(np.float32)
    big = np.kron(n, np.ones((cell, cell), np.float32))[:h, :w]
    return np.asarray(Image.fromarray((big * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur)), np.float32) / 255


done = set()
for m in bpy.data.materials:
    if not m.use_nodes:
        continue
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        continue
    for inp in ("Metallic", "Roughness"):   # карта металл/шероховатость Meshy давала блеск — убрать
        for lk in list(bsdf.inputs[inp].links):
            m.node_tree.links.remove(lk)
    bsdf.inputs["Metallic"].default_value = 0.05
    bsdf.inputs["Roughness"].default_value = 0.93
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    glass = "glass" in m.name
    if not bsdf.inputs["Base Color"].links:   # без текстуры (стекло фонаря и т. п.) — закопчено
        c = bsdf.inputs["Base Color"].default_value
        l = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
        bsdf.inputs["Base Color"].default_value = (l * 0.2 + 0.02, l * 0.18 + 0.02, l * 0.16 + 0.02, 1)
    for lk in bsdf.inputs["Base Color"].links:
        node = lk.from_node
        if node.type != "TEX_IMAGE" or node.image is None or node.image.name in done:
            continue
        img = node.image
        done.add(img.name)
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        soot = np.clip((blotch(h, w, 32, 14, 1) - (0.22 if layout == "heli" else 0.35)) * 2.2, 0, 1)   # вертолёт выгорел сильнее
        dust = np.clip((blotch(h, w, 48, 22, 2) - 0.45) * 2.0, 0, 1)
        lum = px[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
        burnt = np.stack([lum * 0.62, lum * 0.5, lum * 0.42], -1) * 0.75          # обгорелый металл
        rust = np.array([0.32, 0.17, 0.08], np.float32)
        col = px[..., :3] * 0.12 + burnt * 0.88   # краска почти вся выгорела: красные метки и голубое стекло не видны
        col = col * (1 - 0.25 * (1 - soot[..., None])) + rust * 0.25 * (1 - soot[..., None])
        col *= (1 - 0.7 * soot[..., None])
        sand = np.array([0.36, 0.3, 0.22], np.float32)                            # пыль Нагорья (линейный цвет)
        col = col * (1 - 0.45 * dust[..., None]) + sand * 0.45 * dust[..., None]
        if glass:
            col = col * 0.25 + np.array([0.03, 0.03, 0.03], np.float32)          # выбитое закопчённое стекло
        px[..., :3] = col
        img.pixels.foreach_set(px.ravel())
        img.file_format = "JPEG"   # обожжённая текстура — JPEG (пятно гари с альфой — PNG)
        img.pack()
        print("BURNT", img.name)
    if glass:
        bsdf.inputs["Roughness"].default_value = 0.85

# --- мелкие обломки вокруг (тёмный обгорелый металл, матовый)
m_debris = bpy.data.materials.new("debris")
m_debris.use_nodes = True
b = m_debris.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.05, 0.045, 0.04, 1)
b.inputs["Metallic"].default_value = 0.1
b.inputs["Roughness"].default_value = 0.9
craft = [o for o in sc.objects if o.type == "MESH"]


def debris(n, cx, cy, rx, ry, smin, smax):
    for i in range(n):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.35, 1.0)
        s = rng.uniform(smin, smax)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(cx + math.cos(a) * r * rx, cy + math.sin(a) * r * ry, s * 0.15))
        ob = bpy.context.object
        ob.scale = (s * rng.uniform(1, 2.5), s, s * 0.25)
        ob.rotation_euler = (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(0, math.pi))
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        ob.data.materials.append(m_debris)


if layout == "a":
    debris(18, 0, 0, 0.45 * 1.1, 0.45 * 0.8, 0.012, 0.045)
elif layout == "b":
    debris(10, 0.15, 0, 0.4, 0.35, 0.012, 0.04)
    for i in range(8):   # вдоль борозды — то, что отрывалось при юзе
        debris(1, -0.25 - i * 0.07, rng.uniform(-0.05, 0.05), 0.03, 0.03, 0.01, 0.03)
elif layout == "c":
    debris(14, -0.05, 0.05, 0.35, 0.3, 0.012, 0.04)
else:
    debris(16, 0.0, 0.0, 0.45, 0.42, 0.012, 0.04)

# --- борозда юза: земля выворочена — тёмное дно, по краям валики грунта; лежит чуть выше нуля модели
#     (игра утапливает остов на 1 % ширины). Самолёт b — длинная, c и вертолёт — короче
furrow = None
FURROW = {"b": (0.02, -0.72, 0.1, 0.07), "c": (-0.12, -0.62, -0.06, 0.06), "heli": (-0.02, -0.5, 0.05, 0.075)}
if layout in FURROW:
    x0, x1, bendy, half0 = FURROW[layout]
    m_earth = bpy.data.materials.new("furrow")
    m_earth.use_nodes = True
    bs = m_earth.node_tree.nodes["Principled BSDF"]
    vc = m_earth.node_tree.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    m_earth.node_tree.links.new(vc.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Metallic"].default_value = 0.0
    bs.inputs["Roughness"].default_value = 1.0
    bm = bmesh.new()
    cl = bm.loops.layers.float_color.new("Col")
    n = 18
    prof = [(-1.0, 0.0), (-0.7, 0.014), (-0.4, 0.003), (0.0, -0.003), (0.4, 0.003), (0.7, 0.014), (1.0, 0.0)]
    cols = [(0.2, 0.16, 0.115), (0.17, 0.135, 0.095), (0.06, 0.05, 0.04), (0.045, 0.04, 0.035), (0.06, 0.05, 0.04), (0.17, 0.135, 0.095), (0.2, 0.16, 0.115)]
    rows = []
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        half = half0 * (1.0 - 0.45 * t) + 0.01 * noise.noise((x * 9, 0.3, 0))
        yc = bendy * t * t + 0.01 * noise.noise((x * 5, 1.7, 0))
        rows.append([bm.verts.new((x, yc + sd * half, 0.014 + z * (1.0 - 0.3 * t))) for sd, z in prof])
    for i in range(n):
        for j in range(len(prof) - 1):
            f = bm.faces.new([rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]])
            f.smooth = True
            for lp, jj in zip(f.loops, [j, j + 1, j + 1, j]):
                lp[cl] = (*cols[jj], 1.0)
    me = bpy.data.meshes.new("furrow")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m_earth)
    furrow = bpy.data.objects.new("furrow", me)
    sc.collection.objects.link(furrow)

# --- нормировка по самой машине (без борозды): центр в нуле, наибольший размер в плане = 1, стоит на z = 0
allv = [ob.matrix_world @ v.co for ob in craft for v in ob.data.vertices]
lo = Vector((min(v.x for v in allv), min(v.y for v in allv), min(v.z for v in allv)))
hi = Vector((max(v.x for v in allv), max(v.y for v in allv), max(v.z for v in allv)))
k = 1.0 / max(hi.x - lo.x, hi.y - lo.y)
T = Matrix.Diagonal((k, k, k, 1)) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -max(lo.z, 0.0)))
for ob in sc.objects:
    if ob.type == "MESH":
        ob.data.transform(T @ ob.matrix_world)
        ob.matrix_world = Matrix.Identity(4)
# --- пятно гари под обломками: выжженная земля (текстура с альфой, плавный край), чуть выше нуля модели
import tex_lib as TL
sp = TL.scorch("wreck_scorch", seed)
m_sc = bpy.data.materials.new("scorch")
m_sc.use_nodes = True
nt = m_sc.node_tree
bs = nt.nodes["Principled BSDF"]
img = bpy.data.images.load(sp)
img.pack()
tx = nt.nodes.new("ShaderNodeTexImage")
tx.image = img
nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"])
nt.links.new(tx.outputs["Alpha"], bs.inputs["Alpha"])
bs.inputs["Metallic"].default_value = 0.0
bs.inputs["Roughness"].default_value = 1.0
ex = (hi.x - lo.x) * k * 0.46
ey = (hi.y - lo.y) * k * 0.46
bm = bmesh.new()
uvl = bm.loops.layers.uv.new("UVMap")
segs = 28
cen = bm.verts.new((0, 0, 0.012))
ring = [bm.verts.new((math.cos(2 * math.pi * i / segs) * ex, math.sin(2 * math.pi * i / segs) * ey, 0.012)) for i in range(segs)]
for i in range(segs):
    f = bm.faces.new([cen, ring[i], ring[(i + 1) % segs]])
    for lp in f.loops:
        co = lp.vert.co
        lp[uvl].uv = (0.5 + co.x / (2 * ex), 0.5 + co.y / (2 * ey))
me = bpy.data.meshes.new("scorch")
bm.to_mesh(me)
bm.free()
me.materials.append(m_sc)
sc.collection.objects.link(bpy.data.objects.new("scorch", me))

for ob in sc.objects:   # пустые части (нечего резать) не экспортировать
    if ob.type == "MESH" and len(ob.data.polygons) == 0:
        bpy.data.objects.remove(ob, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88,   # с альфой (пятно гари) экспорт сам оставляет PNG
                          export_vertex_color="MATERIAL")
tris = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in sc.objects if ob.type == "MESH")
print("WRECK %s (%s): %d треугольников, высота %.2f" % (dst, layout, tris, (hi.z - lo.z) * k))
