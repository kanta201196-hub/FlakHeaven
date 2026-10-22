"""Тест 3.5-s8 (правки Kanta 19.10): модели биома кодом вместо моделей Meshy — фруктовое дерево, куст,
пост из мешков с песком. У Meshy после упрощения до бюджета они были «слеплены треугольниками»; первая
версия кодом (шары с шумом) — «мультяшная». Здесь:
  дерево  — кривой толстый ствол с корой (текстура цвет + нормаль), скелетные сучья расходятся чашей
            (как у абрикоса/яблони в садах), на них ветви 2-го и 3-го порядка; листва — карточки с альфа-
            текстурой веточек с листьями (запечённая нормаль листвы), собраны в пучки на концах ветвей:
            крона неровная, с просветами, сквозь них видны сучья. Нормали карточек — наружу от кроны
            (мягкий свет без «граней»), внутри кроны темнее (вершинный цвет), часть пучков подсушена;
  куст    — 14 веточек веером от земли, на верхней части каждой — пучки листовых карточек: рваный силуэт;
  пост    — мешки-подушки (скруглённые, к завязанным углам сужаются, слегка просели), мешковина (цвет +
            нормаль), пыльные бежево-серые; кладка подковой вперевязку в 2 мешка толщиной и 3 ряда;
            под ней насыпь из земли с комьями (текстура земли, матовая, цвет земли Нагорья), внутри — окоп
            с земляным дном; пулемёт на сошках, ящики.
Текстуры — процедурные (tex_lib.py), всё матовое (roughness 1, metallic 0).
Единицы — как у моделей биома (tools/model_lab/biome_prep.py): стоит на z = 0 (в Godot y = 0), центр
в нуле, наибольший размер в плане = 1 — игра масштабирует под ширину в пикселях (biome_props.gd).

Запуск (bpy 5.x): python3 biome_flora.py <папка вывода> [orchard] [shrub] [sandbag]
  → <папка>/b05_orchard_tree.glb, b06_shrub.glb, b10_sandbag_post.glb (+ .blend в $FH_SRC, если задан)
Облегчённое дерево («карточки») после этого: tools/model_lab/bake_impostor.gd (см. его шапку)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, noise
import tex_lib as T

OUT = sys.argv[1]
ONLY = sys.argv[2:] or ["orchard", "shrub", "sandbag"]
SRC = os.environ.get("FH_SRC", "")


def srgb(c):
    """sRGB → линейный (вершинный цвет glTF — линейный)"""
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color_path=None, normal_path=None, alpha=False, nstrength=1.0):
    """Матовый материал: текстура цвета × вершинный цвет (glTF COLOR_0), карта нормалей; alpha — обрезка по альфе"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.15
    if color_path:
        img = bpy.data.images.load(color_path)
        img.name = name + "_color"
        img.pack()
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = img
        nt.links.new(tx.outputs["Color"], b.inputs["Base Color"])
        if alpha:
            # обрезка по альфе: экспорт glTF понимает «Round» как alphaMode MASK (порог 0,5)
            rd = nt.nodes.new("ShaderNodeMath")
            rd.operation = "ROUND"
            nt.links.new(tx.outputs["Alpha"], rd.inputs[0])
            nt.links.new(rd.outputs[0], b.inputs["Alpha"])
    else:
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        nt.links.new(vc.outputs["Color"], b.inputs["Base Color"])
    if normal_path:
        img = bpy.data.images.load(normal_path)
        img.name = name + "_normal"
        img.colorspace_settings.name = "Non-Color"
        img.pack()
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = img
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = nstrength
        nt.links.new(tx.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    m.use_backface_culling = not alpha
    return m


class Builder:
    """Копит вершины, грани (материал по номеру), UV и цвет углов, свои нормали карточек"""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.nrm = {}   # вершина → своя нормаль (карточки листвы)

    def face(self, vs, cols, uvs=None, mat=0, smooth=True):
        f = self.bm.faces.new(vs)
        f.smooth = smooth
        f.material_index = mat
        for i, lp in enumerate(f.loops):
            lp[self.col] = (*cols[i], 1.0)
            lp[self.uv].uv = uvs[i] if uvs else (0.0, 0.0)
        return f

    def sweep(self, pts, radii, col, mat=0, sides=8, cap=True, uv_len=1.0, wobble=0.0, seed=0.0):
        """Труба по ломаной с радиусами; UV: u — по окружности (0…1), v — вдоль, uv_len метров на повтор;
        wobble — неровность сечения (наплывы коры)"""
        pts = [Vector(p) for p in pts]
        rings = []
        prev_n = None
        dist = [0.0]
        for i in range(1, len(pts)):
            dist.append(dist[-1] + (pts[i] - pts[i - 1]).length)
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            n = prev_n if prev_n is not None else (Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0)))
            n = (n - d * n.dot(d)).normalized()     # перенос рамки — без перекрута
            prev_n = n
            b = d.cross(n)
            ring = []
            for k in range(sides + 1):          # шов: последняя вершина дублирует первую (u = 1)
                a = 2 * math.pi * k / sides
                rr = radii[i] * (1 + wobble * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, dist[i] * 3 + seed))))
                ring.append(self.bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * rr))
            rings.append(ring)
        for i in range(len(pts) - 1):
            for k in range(sides):
                u0, u1 = k / sides, (k + 1) / sides
                v0, v1 = dist[i] / uv_len, dist[i + 1] / uv_len
                self.face([rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]], [col] * 4,
                          [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], mat)
        if cap:
            tip = self.bm.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 0.8)
            for k in range(sides):
                self.face([rings[-1][k], rings[-1][k + 1], tip], [col] * 3, [(k / sides, 0), ((k + 1) / sides, 0), (0.5, 0.05)], mat)

    def card(self, c, n, size, col, nrm_fn, rot, mat, aspect=1.0):
        """Карточка листвы: квадрат size в плоскости ⟂ n, повёрнут на rot; nrm_fn(точка) → своя нормаль"""
        n = Vector(n).normalized()
        t = n.orthogonal().normalized()
        t = Matrix.Rotation(rot, 3, n) @ t
        b = n.cross(t)
        h = size * 0.5
        ps = [c - t * h - b * h * aspect, c + t * h - b * h * aspect, c + t * h + b * h * aspect, c - t * h + b * h * aspect]
        vs = [self.bm.verts.new(p) for p in ps]
        for v, p in zip(vs, ps):
            self.nrm[v] = nrm_fn(p)
        self.face(vs, col, [(0, 0), (1, 0), (1, 1), (0, 1)], mat)

    def blob(self, c, r, sq, col_fn, mat, subdiv=2, amp=0.3, freq=2.0, seed=0.0, uv_scale=1.0):
        """Ком (земля): икосфера, смещённая шумом; UV — проекция сверху"""
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
        c = Vector(c)
        vmap = {}
        for v in tmp.verts:
            u = v.co.normalized()
            q = u * freq + Vector((seed, seed * 1.7, seed * 0.3))
            k = 1.0 + amp * (noise.noise(q) * 0.7 + noise.noise(q * 2.3) * 0.3)
            w = c + Vector((u.x * sq[0], u.y * sq[1], u.z * sq[2])) * r * k
            vmap[v] = (self.bm.verts.new(w), u, w)
        for f in tmp.faces:
            vs = [vmap[v][0] for v in f.verts]
            self.face(vs, [col_fn(vmap[v][1], vmap[v][2]) for v in f.verts],
                      [(vmap[v][2].x * uv_scale, vmap[v][2].y * uv_scale) for v in f.verts], mat)
        tmp.free()

    def box(self, c, s, rot, col, mat):
        c = Vector(c)
        R = Matrix.Rotation(rot, 3, "Z")
        vs = [self.bm.verts.new(c + R @ Vector((dx * s[0], dy * s[1], dz * s[2])))
              for dx, dy, dz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
        for ids, k in [((0, 3, 2, 1), 0.7), ((4, 5, 6, 7), 1.0), ((0, 1, 5, 4), 0.82), ((1, 2, 6, 5), 0.86), ((2, 3, 7, 6), 0.8), ((3, 0, 4, 7), 0.84)]:
            self.face([vs[i] for i in ids], [tuple(x * k for x in col)] * 4, None, mat, smooth=False)

    def finish(self, name, mats):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        nrm = {}
        for v, n in self.nrm.items():
            nrm[v.index] = n
        self.bm.to_mesh(me)
        self.bm.free()
        for m in mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.update()
        if nrm:   # свои нормали карточек; у остального — сглаженные нормали вершин
            loops = []
            for lp in me.loops:
                vi = lp.vertex_index
                loops.append(tuple(nrm[vi]) if vi in nrm else tuple(me.vertices[vi].normal))
            me.normals_split_custom_set(loops)
        me.color_attributes.active_color = me.color_attributes["Col"]
        return ob


def normalize_export(ob, name):
    me = ob.data
    xs = [v.co for v in me.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    k = 1.0 / max(hi.x - lo.x, hi.y - lo.y)
    # равномерный масштаб и сдвиг: свои нормали не меняются
    me.transform(Matrix.Diagonal((k, k, k, 1)) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    me.update()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    os.makedirs(OUT, exist_ok=True)
    if SRC:
        os.makedirs(SRC, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              export_materials="EXPORT", export_vertex_color="NAME", export_vertex_color_name="Col", export_all_vertex_colors=False, export_normals=True,
                              export_image_format="JPEG")   # с альфой (листья) экспорт сам оставляет PNG
    print("MODEL %s: %d треугольников, высота/ширина %.2f" % (name, tris, (hi.z - lo.z) * k))


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def unit(rng, up=0.0):
    v = Vector((rng.normal(), rng.normal(), rng.normal() + up)).normalized()
    return v


# ---------------- листва ----------------
def foliage(B, rng, clumps, crown_c, crown_sq, size, mat, n_per, dry_share=0.15, dark=0.42, tint=1.0):
    """Пучки листовых карточек. clumps: [(центр, радиус)]. Нормаль карточки в вершине — наружу от центра кроны
    (сжатого по crown_sq) с примесью — от центра пучка; вершинный цвет: внутри пучка и кроны темнее,
    подсушенные пучки — желтее"""
    cc = Vector(crown_c)

    def nrm_of(cl_c):
        def f(p):
            a = Vector(((p.x - cc.x) / crown_sq[0], (p.y - cc.y) / crown_sq[1], (p.z - cc.z) / crown_sq[2]))
            return (a.normalized() * 0.65 + (p - cl_c).normalized() * 0.35 + Vector((0, 0, 0.25))).normalized()
        return f
    for c, r in clumps:
        c = Vector(c)
        dryk = rng.random() < dry_share
        ct = np.array((1.07, 1.0, 0.82) if dryk else (1.0, 1.0, 1.0)) * rng.uniform(0.88, 1.08) * tint
        nf = nrm_of(c)
        for i in range(n_per):
            d = unit(rng, 0.35)
            t = rng.uniform(0.3, 1.0) ** 0.5
            p = c + Vector((d.x, d.y, d.z * 0.8)) * r * t
            # затенение: глубже в пучке и ниже в кроне — темнее
            hz = (p.z - (cc.z - crown_sq[2])) / (2 * crown_sq[2])
            ao = dark + (1 - dark) * min(1.0, 0.45 * t + 0.55 * max(0.0, min(1.0, hz)) + 0.1)
            col = srgb(tuple(min(1.0, x) for x in ct * ao))
            n_card = (d * 0.6 + unit(rng) * 0.6).normalized()
            B.card(p, n_card, size * rng.uniform(0.8, 1.15), [col] * 4, nf, rng.uniform(0, math.tau), mat)


def branch(B, p0, d, length, r0, r1, col, mat, rng, segs=5, curve=0.25, sides=6, up=0.0):
    """Ветвь: из p0 по направлению d, загибается вверх (curve) и чуть извилиста; возвращает точки"""
    pts = [Vector(p0)]
    d = Vector(d).normalized()
    for i in range(1, segs + 1):
        t = i / segs
        d = (d + Vector((0, 0, curve / segs)) + Vector((rng.normal(), rng.normal(), up)) * 0.12).normalized()
        pts.append(pts[-1] + d * length / segs)
    B.sweep(pts, [r0 + (r1 - r0) * (i / segs) for i in range(segs + 1)], col, mat, sides=sides, uv_len=0.8)
    return pts


# ---------------- фруктовое дерево ----------------
def orchard():
    reset()
    rng = np.random.default_rng(23)
    B = Builder()
    bark_c, bark_n = T.bark("orchard_bark", 3)
    leaf_c, leaf_n = T.leaves("orchard_leaves", 1, leaf_len=(0.14, 0.2), base=(0.33, 0.37, 0.2), dry=(0.5, 0.45, 0.28), var=0.08)
    m_bark = material("orchard_bark", bark_c, bark_n, nstrength=1.2)
    m_leaf = material("orchard_leaves", leaf_c, leaf_n, alpha=True, nstrength=0.8)
    white = srgb((1.0, 1.0, 1.0))
    # ствол: толстый, кривой, у земли расширяется, наплывы коры
    tr = [Vector((0, 0, -0.05))]
    lean = Vector((rng.normal() * 0.12, rng.normal() * 0.12, 1)).normalized()
    for i in range(1, 7):
        tr.append(tr[-1] + lean * 0.18 + Vector((math.sin(i * 1.7) * 0.05, math.cos(i * 1.3) * 0.05, 0)))
    B.sweep(tr, [0.36, 0.27, 0.24, 0.23, 0.22, 0.21, 0.2], white, 0, sides=11, cap=False, wobble=0.12, seed=1.0)
    top = tr[-1]
    clumps = []
    a0 = rng.uniform(0, math.tau)
    # скелетные сучья — чашей: 4 под 45–55° от вертикали, середина открыта
    for i in range(5):
        a = a0 + math.tau * i / 5 + rng.uniform(-0.2, 0.2)
        el = math.radians(rng.uniform(24, 36))
        d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        start = top - lean * rng.uniform(0.0, 0.2)
        L = rng.uniform(1.25, 1.5)
        p = branch(B, start, d, L, 0.15, 0.08, white, 0, rng, segs=5, curve=0.35, sides=8)
        # ветви 2-го порядка — от середины и конца сука, 3-го — от их концов; пучки листвы — на концах
        for j, (k0, side) in enumerate([(3, -1), (5, 1)]):
            q0 = p[k0]
            dd = (p[k0] - p[k0 - 1]).normalized()
            d2 = (Matrix.Rotation(side * rng.uniform(0.45, 0.75), 3, "Z") @ dd + Vector((0, 0, 0.35))).normalized()
            p2 = branch(B, q0, d2, rng.uniform(0.75, 1.0), 0.075, 0.035, white, 0, rng, segs=4, curve=0.2, sides=6)
            clumps.append((p2[2] + Vector((0, 0, 0.1)), rng.uniform(0.32, 0.4)))
            for s3 in (-1, 0, 1):
                d3 = (Matrix.Rotation(s3 * rng.uniform(0.5, 0.9), 3, "Z") @ (p2[-1] - p2[-2]).normalized() + Vector((0, 0, 0.15 + 0.2 * (s3 == 0)))).normalized()
                p3 = branch(B, p2[-1], d3, rng.uniform(0.35, 0.6), 0.035, 0.014, white, 0, rng, segs=3, curve=0.1, sides=5)
                clumps.append((p3[-1] + Vector((0, 0, 0.06)), rng.uniform(0.36, 0.48)))
    # центр кроны и сжатие — для нормалей карточек
    xs = [c for c, r in clumps]
    cc = sum(xs, Vector()) / len(xs)
    cc.z -= 0.25
    foliage(B, rng, clumps, cc, (2.2, 2.2, 1.1), 0.46, 1, 62, dark=0.32, tint=0.86)
    ob = B.finish("b05_orchard_tree", [m_bark, m_leaf])
    normalize_export(ob, "b05_orchard_tree")


# ---------------- куст ----------------
def shrub():
    reset()
    rng = np.random.default_rng(7)
    B = Builder()
    bark_c, bark_n = T.bark("shrub_bark", 13)
    leaf_c, leaf_n = T.leaves("shrub_leaves", 2, n_leaf=150, leaf_len=(0.08, 0.12), width=0.3, base=(0.38, 0.4, 0.27), dry=(0.5, 0.46, 0.32), dry_share=0.18, stems=False)
    m_bark = material("shrub_twig", bark_c, bark_n)
    m_leaf = material("shrub_leaves", leaf_c, leaf_n, alpha=True, nstrength=0.8)
    white = srgb((0.9, 0.85, 0.8))
    clumps = []
    for i in range(14):
        a = math.tau * i / 14 + rng.uniform(-0.2, 0.2)
        el = math.radians(rng.uniform(30, 75))
        d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        L = rng.uniform(0.55, 0.85) * (0.75 if el > math.radians(60) else 1.0)
        p = branch(B, Vector((rng.normal() * 0.05, rng.normal() * 0.05, -0.03)), d, L, 0.028, 0.008, white, 0, rng, segs=4, curve=0.15, sides=4)
        clumps.append((p[2] + Vector((0, 0, 0.04)), rng.uniform(0.17, 0.24)))
        clumps.append((p[-1], rng.uniform(0.2, 0.27)))
    foliage(B, rng, clumps, (0, 0, 0.2), (0.85, 0.85, 0.5), 0.26, 1, 26, dry_share=0.2, dark=0.42, tint=0.9)
    ob = B.finish("b06_shrub", [m_bark, m_leaf])
    normalize_export(ob, "b06_shrub")


# ---------------- пост из мешков с песком ----------------
def bag(B, c, yaw, L, W, H, col, rng, mat):
    """Мешок-подушка: сечение — скруглённый прямоугольник (суперэллипс), к концам уже и тоньше, на концах —
    завязанные «ушки»; верх чуть просел. 5 сечений × 8 + ушки = 80 треуг."""
    R = Matrix.Rotation(yaw, 3, "Z") @ Matrix.Rotation(rng.uniform(-0.05, 0.05), 3, "X")
    c = Vector(c)
    NS, NT = 5, 8
    rows = []
    for i in range(NS):
        s = -1 + 2 * i / (NS - 1)
        s = s * 0.86
        fw = 1 - 0.32 * abs(s) ** 3
        fh = 1 - 0.45 * abs(s) ** 2.5
        row = []
        for k in range(NT + 1):
            t = 2 * math.pi * k / NT + math.pi / NT
            ct, st = math.cos(t), math.sin(t)
            y = math.copysign(abs(ct) ** 0.55, ct) * W * fw
            z = math.copysign(abs(st) ** 0.6, st) * H * fh
            if z > 0:
                z *= 1 - 0.18 * (1 - abs(s))       # верх просел посередине
            else:
                z *= 0.85                          # низ плоский — лежит
            row.append(B.bm.verts.new(c + R @ Vector((s * L, y, z))))
        rows.append(row)
    for i in range(NS - 1):
        for k in range(NT):
            B.face([rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]],
                   [col] * 4, [(i / (NS - 1), k / NT), (i / (NS - 1), (k + 1) / NT), ((i + 1) / (NS - 1), (k + 1) / NT), ((i + 1) / (NS - 1), k / NT)], mat)
    for end, row in ((-1, rows[0]), (1, rows[-1])):   # завязанный угол — сборка ткани в «ушко»
        tip = B.bm.verts.new(c + R @ Vector((end * L * 1.04, rng.uniform(-0.3, 0.3) * W, H * 0.1)))
        for k in range(NT):
            vs = [row[k], row[k + 1], tip] if end > 0 else [row[k + 1], row[k], tip]
            B.face(vs, [col] * 3, [(0.5 + end * 0.5, k / NT), (0.5 + end * 0.5, (k + 1) / NT), (0.5 + end * 0.55, 0.5)], mat)


def sandbag():
    reset()
    rng = np.random.default_rng(5)
    B = Builder()
    bc, bn = T.burlap("sandbag_burlap", 4)
    ec, en = T.earth("sandbag_earth", 5, base=(0.55, 0.5, 0.41))
    m_bag = material("sandbag_burlap", bc, bn)
    m_earth = material("sandbag_earth", ec, en, nstrength=1.2)
    m_gun = material("sandbag_gun")
    # насыпь: всё стоит на земле выше уровня — игра утапливает модель на 4 % ширины и рельеф неровный
    BASE = 0.42
    L, W, H = 0.4, 0.23, 0.1          # полуразмеры мешка: 0,8 × 0,46 × 0,2 м
    gap = math.radians(70)            # проход в тыл (−X)
    a_lo, a_hi = math.pi + gap / 2 - 2 * math.pi, math.pi - gap / 2
    for r, courses in [(2.62, 3), (2.16, 3)]:
        n = int((a_hi - a_lo) * r / (2 * L * 0.96))
        for cz in range(courses):
            off = 0.5 if cz % 2 else 0.0          # вперевязку
            z = BASE + H * 0.85 + cz * H * 1.7
            r_c = r - cz * 0.05                   # стенка чуть заваливается внутрь
            for i in range(n + (0 if off else 1)):
                a = a_lo + (i + off) * (a_hi - a_lo) / n
                k = rng.uniform(0.78, 0.92)
                tint = (k, k * rng.uniform(0.98, 1.0), k * rng.uniform(0.95, 0.99))
                if cz == 0:   # нижний ряд — в пыли и земле
                    tint = tuple(x * 0.88 for x in tint)
                jit = rng.uniform(-0.03, 0.03)
                bag(B, (math.cos(a) * (r_c + jit), math.sin(a) * (r_c + jit), z), a + math.pi / 2 + rng.uniform(-0.1, 0.1),
                    L * rng.uniform(0.94, 1.04), W, H, srgb(tint), rng, 0)
    # земля: от стенки наружу — насыпь, вал и спуск к земле; внутри — окоп с земляным дном. Профиль (r, z),
    # смещение шумом, вершинный цвет — оттенок (окоп темнее)
    prof = [(0.0, BASE - 0.22), (0.9, BASE - 0.2), (1.55, BASE - 0.14), (1.85, BASE - 0.02), (2.0, BASE + 0.02),
            (2.85, BASE + 0.04), (2.98, BASE + 0.18), (3.15, BASE + 0.1), (3.4, 0.2), (3.62, 0.03), (3.75, -0.04)]
    shade = [0.62, 0.64, 0.7, 0.85, 0.95, 0.95, 1.0, 1.02, 1.0, 1.0, 1.0]
    seg = 72
    grid = []
    for j, (r, z) in enumerate(prof):
        row = []
        for k in range(seg + 1):
            a = 2 * math.pi * k / seg
            if r == 0.0:
                p = Vector((0, 0, z))
            else:
                q = Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, r * 0.7))
                p = Vector((math.cos(a) * r, math.sin(a) * r, z + 0.06 * noise.noise(q * 2.0) + 0.03 * noise.noise(q * 6.0)))
            row.append((B.bm.verts.new(p), p))
        grid.append(row)
    for j in range(len(prof) - 1):
        for k in range(seg):
            vs = [grid[j][k], grid[j + 1][k], grid[j + 1][k + 1], grid[j][k + 1]]
            cs = [srgb((shade[j],) * 3), srgb((shade[j + 1],) * 3), srgb((shade[j + 1],) * 3), srgb((shade[j],) * 3)]
            uvs = [(p.x / 2.0, p.y / 2.0) for v, p in vs]
            if j == 0:
                B.face([vs[0][0], vs[1][0], vs[2][0]], cs[:3], uvs[:3], 1)
            else:
                B.face([v for v, p in vs], cs, uvs, 1)
    # комья земли на валу и в окопе
    for i in range(36):
        a = rng.uniform(0, math.tau)
        inside = i < 10
        r = rng.uniform(0.4, 1.7) if inside else rng.uniform(2.9, 3.55)
        zz = BASE - 0.2 if inside else (BASE + 0.12 if r < 3.2 else 0.15)
        s = rng.uniform(0.07, 0.16)
        k = rng.uniform(0.75, 1.0) * (0.7 if inside else 1.0)
        B.blob((math.cos(a) * r, math.sin(a) * r, zz + s * 0.3), s, (1.0, 0.9, 0.6),
               lambda u, w, k=k: srgb((k, k, k)), 1, subdiv=1, amp=0.35, freq=2.0, seed=i * 1.3, uv_scale=0.5)
    # пулемёт на бруствере (смотрит вперёд, +X): короб, ствол, сошки; ящики с лентами
    gun = srgb((0.16, 0.16, 0.15))
    zt = BASE + H * 0.85 + 2 * H * 1.7 + H * 0.9
    B.box((2.45, 0.0, zt + 0.07), (0.22, 0.06, 0.06), 0.0, gun, 2)
    B.sweep([(2.6, 0.0, zt + 0.08), (3.3, 0.0, zt + 0.1)], [0.025, 0.02], gun, 2, sides=6)
    B.sweep([(2.9, 0.0, zt + 0.07), (3.0, 0.16, zt - 0.03)], [0.015, 0.015], gun, 2, sides=4)
    B.sweep([(2.9, 0.0, zt + 0.07), (3.0, -0.16, zt - 0.03)], [0.015, 0.015], gun, 2, sides=4)
    B.box((1.4, -0.5, BASE - 0.1), (0.22, 0.13, 0.12), 0.4, srgb((0.27, 0.29, 0.21)), 2)
    B.box((-0.9, 0.9, BASE - 0.1), (0.3, 0.18, 0.12), -0.6, srgb((0.27, 0.29, 0.21)), 2)
    ob = B.finish("b10_sandbag_post", [m_bag, m_earth, m_gun])
    normalize_export(ob, "b10_sandbag_post")


for k in ONLY:
    {"orchard": orchard, "shrub": shrub, "sandbag": sandbag}[k]()
