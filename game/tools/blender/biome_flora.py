"""Тест 3.5-s8 (правки Kanta 19.10): модели биома кодом вместо моделей Meshy — фруктовое дерево, куст,
пост из мешков с песком. У Meshy после упрощения до бюджета они были «слеплены треугольниками»:
крона рваная, куст — тёмный «паук», мешки — тонкие оранжевые кольца.

Здесь — чистая геометрия:
  дерево  — ствол и ветви трубами (сечение 7–8 граней, сужаются к концам), крона — кластеры листвы:
            округлые объёмы с шумом (икосферы, смещённые 3D-шумом), без рваных треугольников;
  куст    — 5–7 приплюснутых кластеров листвы на коротких веточках, светлее и «пыльнее» дерева;
  пост    — подкова из мешков с песком рядами (кладка вперевязку, 3 ряда снаружи и 2 изнутри), под ней
            земляной вал, в середине тёмный окоп, на бруствере пулемёт на сошках и ящик.
Цвет — вершинный (один материал на модель, полностью матовый: roughness 1, metallic 0): листва
оливково-зелёная, приглушённая (аудит Б-9), снизу кластеров темнее, сверху светлее и теплее; мешки —
песочно-серые с разбросом, пыльные.
Единицы — как у моделей биома (tools/model_lab/biome_prep.py): стоит на z = 0 (в Godot y = 0), центр
в нуле, наибольший размер в плане = 1 — игра масштабирует под ширину в пикселях (biome_props.gd).

Запуск (bpy 5.x): python3 biome_flora.py <папка вывода> [orchard] [shrub] [sandbag]
  → <папка>/b05_orchard_tree.glb, b06_shrub.glb, b10_sandbag_post.glb (+ .blend в $FH_SRC, если задан)
Облегчённое дерево («карточки») после этого: tools/model_lab/bake_impostor.gd (см. его шапку)."""
import sys, os, math
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, noise

OUT = sys.argv[1]
ONLY = sys.argv[2:] or ["orchard", "shrub", "sandbag"]
SRC = os.environ.get("FH_SRC", "")


def srgb(c):
    """sRGB → линейный (вершинный цвет glTF — линейный)"""
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    m.node_tree.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.15
    return m


class Builder:
    """Копит вершины, грани и цвета углов; в конце — один объект с одним материалом"""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def face(self, vs, cols, smooth=True):
        f = self.bm.faces.new(vs)
        f.smooth = smooth
        for lp, c in zip(f.loops, cols):
            lp[self.col] = (*c, 1.0)
        return f

    def sweep(self, pts, radii, colf, sides=7, cap=True):
        """Труба по ломаной pts с радиусами radii; colf(t, угол) → цвет (t — 0…1 вдоль трубы)"""
        pts = [Vector(p) for p in pts]
        rings = []
        prev_n = None
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            n = prev_n if prev_n is not None else (Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0)))
            n = (n - d * n.dot(d)).normalized()     # перенос рамки вдоль трубы — без перекрута
            prev_n = n
            b = d.cross(n)
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                ring.append(self.bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * radii[i]))
            rings.append(ring)
        m = len(pts) - 1
        for i in range(m):
            for k in range(sides):
                k2 = (k + 1) % sides
                a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * k2 / sides
                self.face([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]],
                          [colf(i / m, a0), colf(i / m, a1), colf((i + 1) / m, a1), colf((i + 1) / m, a0)])
        if cap:
            tip = self.bm.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 0.6)
            for k in range(sides):
                self.face([rings[-1][k], rings[-1][(k + 1) % sides], tip], [colf(1, 0)] * 3)

    def blob(self, c, r, sq, colf, subdiv=3, amp=0.22, freq=1.6, seed=0.0):
        """Кластер листвы: икосфера, смещённая 3D-шумом (бугристая, но гладкая); sq — сжатие (x, y, z);
        colf(локальная точка на единичной сфере, мировая точка) → цвет"""
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
        c = Vector(c)
        vmap = {}
        for v in tmp.verts:
            u = v.co.normalized()
            q = u * freq + Vector((seed, seed * 1.7, seed * 0.3))
            dn = noise.noise(q) * 0.55 + noise.noise(q * 2.4) * 0.3 + noise.noise(q * 5.1) * 0.15
            k = 1.0 + amp * dn
            w = c + Vector((u.x * sq[0], u.y * sq[1], u.z * sq[2])) * r * k
            vmap[v] = (self.bm.verts.new(w), u, w, max(0.62, min(1.18, 1.0 + 0.7 * dn)))
        for f in tmp.faces:
            vs = [vmap[v][0] for v in f.verts]
            # впадины между «пучками» листьев темнее, выпуклости светлее — читается листва, а не гладкий шар
            self.face(vs, [tuple(x * vmap[v][3] for x in colf(vmap[v][1], vmap[v][2])) for v in f.verts])
        tmp.free()

    def box(self, c, s, rot, col, z_rot_only=True):
        """Ящик c (центр), s (полуразмеры), поворот вокруг z (рад)"""
        c = Vector(c)
        R = Matrix.Rotation(rot, 3, "Z")
        vs = []
        for dx, dy, dz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]:
            vs.append(self.bm.verts.new(c + R @ Vector((dx * s[0], dy * s[1], dz * s[2]))))
        for ids, k in [((0, 3, 2, 1), 0.7), ((4, 5, 6, 7), 1.0), ((0, 1, 5, 4), 0.82), ((1, 2, 6, 5), 0.86), ((2, 3, 7, 6), 0.8), ((3, 0, 4, 7), 0.84)]:
            self.face([vs[i] for i in ids], [tuple(x * k for x in col)] * 4, smooth=False)

    def finish(self, name, mat):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-6)
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def normalize_export(ob, name):
    me = ob.data
    xs = [v.co for v in me.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    k = 1.0 / max(hi.x - lo.x, hi.y - lo.y)
    me.transform(Matrix.Diagonal((k, k, k, 1)) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    me.update()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    os.makedirs(OUT, exist_ok=True)
    if SRC:
        os.makedirs(SRC, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              export_materials="EXPORT", export_vertex_color="MATERIAL", export_normals=True)
    print("MODEL %s: %d треугольников, высота/ширина %.2f" % (name, tris, (hi.z - lo.z) * k))


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


# ---------------- листва: общий раскрас ----------------
def leaf_col(base, dark, light, ctr, crown_r, seed):
    """Цвет кластера: низ и середина кроны темнее (тень внутри), верх под солнцем светлее и теплее,
    пятна крупным шумом — чтобы крона не была одного «пластикового» тона"""
    def f(u, w):
        up = u.z * 0.5 + 0.5                                     # 0 — низ кластера, 1 — верх
        rim = min(1.0, (Vector((w.x, w.y)) - Vector((ctr[0], ctr[1]))).length / crown_r)   # к краю кроны светлее
        t = up * 0.75 + rim * 0.25
        c = lerp(dark, base, min(1.0, t * 1.5)) if t < 0.66 else lerp(base, light, (t - 0.66) / 0.34)
        n = noise.noise(w * 1.9 + Vector((seed, 0, 0))) * 0.5 + noise.noise(w * 5.0) * 0.25
        return srgb(tuple(max(0.0, x * (1.0 + 0.16 * n)) for x in c))
    return f


# ---------------- фруктовое дерево ----------------
def orchard():
    reset()
    rng = np.random.default_rng(11)
    B = Builder()
    bark = lambda t, a: srgb(lerp((0.25, 0.21, 0.17), (0.36, 0.31, 0.25), 0.5 + 0.5 * math.cos(a - 0.8)))
    # ствол: невысокий, чуть наклонён, у земли расширяется (сад — привитые деревья с низкой штамбой)
    trunk = [(0, 0, -0.05), (0.02, 0.0, 0.35), (0.06, 0.03, 0.8), (0.1, 0.05, 1.25)]
    B.sweep(trunk, [0.26, 0.19, 0.17, 0.15], bark, sides=8, cap=False)
    tips = []
    n_limb = 4
    a0 = rng.uniform(0, math.tau)
    for i in range(n_limb):
        a = a0 + math.tau * i / n_limb + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        reach = rng.uniform(1.25, 1.6)
        top = rng.uniform(2.55, 2.95)
        p0 = Vector(trunk[-1])
        p1 = p0 + d * reach * 0.35 + Vector((0, 0, 0.55))
        p2 = p0 + d * reach * 0.75 + Vector((0, 0, top - 1.25 - 0.35))
        p3 = p0 + d * reach + Vector((0, 0, top - 1.25))
        B.sweep([p0, p1, p2, p3], [0.12, 0.09, 0.065, 0.04], bark, sides=7)
        tips.append(p3)
        # боковая ветвь от середины сука
        a2 = a + rng.choice([-1, 1]) * rng.uniform(0.7, 1.0)
        d2 = Vector((math.cos(a2), math.sin(a2), 0))
        q0 = p1.lerp(p2, 0.4)
        q1 = q0 + d2 * 0.55 + Vector((0, 0, 0.45))
        q2 = q0 + d2 * 0.95 + Vector((0, 0, 0.75))
        B.sweep([q0, q1, q2], [0.06, 0.045, 0.03], bark, sides=6)
        tips.append(q2)
    # центральный проводник
    c0 = Vector(trunk[-1])
    B.sweep([c0, c0 + Vector((0.05, -0.04, 0.7)), c0 + Vector((0.02, 0.02, 1.55))], [0.1, 0.07, 0.04], bark, sides=7)
    tips.append(c0 + Vector((0.02, 0.02, 1.55)))
    # крона — кластеры листвы у концов ветвей и по сукам, неровный купол с «карманами» тени;
    # нижние кластеры — меньше и ниже: видно ярусы, а не шар
    ctr = (0.1, 0.05)
    crown_r = 2.1
    leaf = leaf_col((0.4, 0.45, 0.22), (0.15, 0.19, 0.09), (0.6, 0.61, 0.33), ctr, crown_r, 3.0)
    s = 0.0
    spots = []
    small = []
    for t in tips:   # у конца каждой ветви — пучок: крупный кластер и мелкий сбоку-снизу
        spots.append((t + Vector((0, 0, 0.12)), rng.uniform(0.55, 0.66)))
        off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized() * 0.42
        small.append((t + off + Vector((0, 0, -0.18)), rng.uniform(0.4, 0.48)))
    for k in range(6):   # плечи кроны между суками — закрывают просветы сверху
        a = a0 + math.tau * (k + 0.5) / 6 + rng.uniform(-0.2, 0.2)
        rr = rng.uniform(0.7, 1.2)
        spots.append((Vector((ctr[0] + math.cos(a) * rr, ctr[1] + math.sin(a) * rr, rng.uniform(2.1, 2.55))), rng.uniform(0.5, 0.62)))
    spots.append((Vector((ctr[0] + 0.1, ctr[1] - 0.1, 2.95)), 0.62))
    for c, r in spots:
        B.blob(c, r, (1.0, 1.0, 0.85), leaf, subdiv=3, amp=0.42, freq=2.4, seed=s)
        s += 3.1
    for c, r in small:   # мелкие — снизу кроны, почти не видны сверху: 80 треугольников
        B.blob(c, r, (1.0, 1.0, 0.85), leaf, subdiv=2, amp=0.35, freq=2.4, seed=s)
        s += 3.1
    ob = B.finish("b05_orchard_tree", material("flora"))
    normalize_export(ob, "b05_orchard_tree")


# ---------------- куст ----------------
def shrub():
    reset()
    rng = np.random.default_rng(7)
    B = Builder()
    twig = lambda t, a: srgb(lerp((0.27, 0.23, 0.18), (0.36, 0.31, 0.24), t))
    # пыльная полынно-оливковая зелень, светлее дерева (кусты в сухих долинах), низ — бурый
    # пыльная оливковая зелень, светлее дерева (кусты в сухих долинах); снизу — бурые веточки
    leaf = leaf_col((0.48, 0.5, 0.3), (0.3, 0.31, 0.19), (0.62, 0.62, 0.41), (0, 0), 1.2, 9.0)
    s = 0.0
    # 10 пучков куполом: 4 в середине повыше, 6 по краю пониже и мельче — неровный край, не «камень»
    for i in range(10):
        if i < 4:
            a = math.tau * i / 4 + rng.uniform(-0.4, 0.4)
            rr, r, h = rng.uniform(0.1, 0.35), rng.uniform(0.38, 0.46), rng.uniform(0.42, 0.55)
        else:
            a = math.tau * (i - 4) / 6 + rng.uniform(-0.3, 0.3)
            rr, r, h = rng.uniform(0.62, 0.82), rng.uniform(0.27, 0.36), rng.uniform(0.2, 0.3)
        c = Vector((math.cos(a) * rr, math.sin(a) * rr, h))
        B.sweep([Vector((c.x * 0.15, c.y * 0.15, -0.02)), Vector((c.x * 0.8, c.y * 0.8, h * 0.75))], [0.03, 0.018], twig, sides=5)
        B.blob(c, r, (1.0, 1.0, 0.8), leaf, subdiv=3 if i < 4 else 2, amp=0.4, freq=2.6, seed=s)
        s += 2.3
    ob = B.finish("b06_shrub", material("flora"))
    normalize_export(ob, "b06_shrub")


# ---------------- пост из мешков с песком ----------------
def bag(B, c, yaw, size, col, tilt=0.0):
    """Мешок-подушка: приплюснутая сфера 6×4 (36 треуг.), верх и низ срезаны — лежит плоско"""
    lx, ly, lz = size
    R = Matrix.Rotation(yaw, 3, "Z") @ Matrix.Rotation(tilt, 3, "X")
    c = Vector(c)
    seg, ring = 6, 4
    rows = []
    for j in range(ring + 1):
        th = math.pi * j / ring
        z = math.cos(th)
        rr = math.sin(th)
        row = []
        for k in range(seg if 0 < j < ring else 1):
            ph = 2 * math.pi * (k + 0.5) / seg
            x, y = math.cos(ph) * rr, math.sin(ph) * rr
            # «подушка»: бока полнее (степень < 1), верх и низ плоские
            x = math.copysign(abs(x) ** 0.7, x)
            y = math.copysign(abs(y) ** 0.8, y)
            zz = max(-0.8, min(0.8, z))
            row.append(B.bm.verts.new(c + R @ Vector((x * lx, y * ly, zz * lz))))
        rows.append(row)
    top = tuple(x * 1.06 for x in col)
    side = tuple(x * 0.84 for x in col)
    bot = tuple(x * 0.6 for x in col)
    cs = [top, top, side, bot, bot]
    for j in range(ring):
        for k in range(seg):
            k2 = (k + 1) % seg
            if j == 0:
                B.face([rows[0][0], rows[1][k2], rows[1][k]], [cs[0], cs[1], cs[1]])
            elif j == ring - 1:
                B.face([rows[j][k], rows[j][k2], rows[ring][0]], [cs[j], cs[j], cs[ring]])
            else:
                B.face([rows[j][k], rows[j][k2], rows[j + 1][k2], rows[j + 1][k]], [cs[j], cs[j], cs[j + 1], cs[j + 1]])


def sandbag():
    reset()
    rng = np.random.default_rng(5)
    B = Builder()
    # единицы — метры: окоп ~4,4 м внутри, стенка в 2 мешка, высота ~0,75 м; вал вокруг — до ~8 м
    sand = [(0.74, 0.69, 0.57), (0.68, 0.65, 0.55), (0.64, 0.61, 0.53), (0.77, 0.7, 0.57), (0.6, 0.58, 0.51)]
    L, W, H = 0.36, 0.2, 0.085     # полуразмеры мешка (0,72 × 0,4 × 0,17 м)
    gap = math.radians(70)        # проход в тыл (−X)
    # всё стоит на насыпи высотой BASE: игра утапливает модель на 4 % ширины и рельеф неровный —
    # без насыпи низкий пост уходил в землю (кадр игры 19.10)
    BASE = 0.42
    a_lo, a_hi = math.pi + gap / 2 - 2 * math.pi, math.pi - gap / 2
    for row, (r, courses) in enumerate([(2.75, 3), (2.35, 3), (1.98, 2)]):
        n = int((a_hi - a_lo) * r / (2 * L * 0.98))
        for cz in range(courses):
            off = 0.5 if cz % 2 else 0.0          # кладка вперевязку
            z = BASE + 0.05 + H + cz * H * 1.75
            r_c = r - cz * 0.04                    # стенка чуть заваливается внутрь
            for i in range(n + (0 if off else 1)):
                a = a_lo + (i + off) * (a_hi - a_lo) / n
                jit = rng.uniform(-0.03, 0.03)
                kk = rng.uniform(0.9, 1.06)
                col = tuple(min(1, x * kk) for x in sand[rng.integers(len(sand))])
                # пыль: нижние ряды и внешний ряд — светлее и рыжее (земля)
                if cz == 0:
                    col = lerp(col, (0.6, 0.5, 0.38), 0.35)
                bag(B, (math.cos(a) * (r_c + jit), math.sin(a) * (r_c + jit), z), a + math.pi / 2 + rng.uniform(-0.08, 0.08),
                    (L * rng.uniform(0.95, 1.05), W, H), srgb(col), tilt=rng.uniform(-0.06, 0.06))
    # земляной вал снаружи (выброшенный из окопа грунт) — кольцо от стенки к земле
    seg = 40
    ring_r = [(2.92, BASE + 0.06), (3.0, BASE + 0.2), (3.25, BASE + 0.08), (3.6, 0.22), (3.85, -0.02)]
    earth = [(0.6, 0.55, 0.45), (0.7, 0.63, 0.5), (0.72, 0.64, 0.5), (0.7, 0.61, 0.47), (0.72, 0.62, 0.47)]
    vs = [[B.bm.verts.new((math.cos(2 * math.pi * k / seg) * r * (1 + 0.04 * noise.noise((k * 0.4, r, 0))),
                           math.sin(2 * math.pi * k / seg) * r * (1 + 0.04 * noise.noise((k * 0.4, r, 0))), z)) for k in range(seg)] for r, z in ring_r]
    for j in range(len(ring_r) - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            B.face([vs[j][k], vs[j + 1][k], vs[j + 1][k2], vs[j][k2]], [srgb(earth[j]), srgb(earth[j + 1]), srgb(earth[j + 1]), srgb(earth[j])])
    # окоп: тёмное дно, к стенкам светлее (тень бруствера)
    rings = [(0.0, (0.33, 0.29, 0.23)), (1.0, (0.36, 0.31, 0.25)), (1.6, (0.42, 0.37, 0.29)), (2.95, (0.58, 0.52, 0.42))]
    cen = B.bm.verts.new((0, 0, BASE + 0.02))
    prev = None
    for r, col in rings[1:]:
        cur = [B.bm.verts.new((math.cos(2 * math.pi * k / seg) * r, math.sin(2 * math.pi * k / seg) * r, BASE + 0.02 + 0.04 * min(1.0, r / 2.0) ** 2)) for k in range(seg)]
        for k in range(seg):
            k2 = (k + 1) % seg
            if prev is None:
                B.face([cen, cur[k], cur[k2]], [srgb(rings[0][1]), srgb(col), srgb(col)])
            else:
                B.face([prev[0][k], cur[k], cur[k2], prev[0][k2]], [srgb(prev[1]), srgb(col), srgb(col), srgb(prev[1])])
        prev = (cur, col)
    # пулемёт на бруствере (смотрит вперёд, +X): сошки, короб, ствол; рядом ящик с лентами
    gun = srgb((0.16, 0.16, 0.15))
    zt = BASE + 0.05 + H + 2 * H * 1.75 + H
    B.box((2.55, 0.0, zt + 0.07), (0.2, 0.06, 0.06), 0.0, gun)
    B.sweep([(2.7, 0.0, zt + 0.08), (3.35, 0.0, zt + 0.1)], [0.025, 0.02], lambda t, a: gun, sides=6)
    B.sweep([(2.95, 0.0, zt + 0.07), (3.05, 0.15, zt - 0.02)], [0.015, 0.015], lambda t, a: gun, sides=4)
    B.sweep([(2.95, 0.0, zt + 0.07), (3.05, -0.15, zt - 0.02)], [0.015, 0.015], lambda t, a: gun, sides=4)
    B.box((1.55, -0.45, BASE + 0.14), (0.2, 0.12, 0.12), 0.4, srgb((0.3, 0.32, 0.22)))
    B.box((-1.0, 1.0, BASE + 0.14), (0.28, 0.17, 0.12), -0.6, srgb((0.3, 0.32, 0.22)))
    ob = B.finish("b10_sandbag_post", material("sandbag"))
    normalize_export(ob, "b10_sandbag_post")


for k in ONLY:
    {"orchard": orchard, "shrub": shrub, "sandbag": sandbag}[k]()
