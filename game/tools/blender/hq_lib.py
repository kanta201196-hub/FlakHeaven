"""Тест 3.5-s8 (Kanta: «для ангара — супер качественные модели оружия»): общая библиотека моделей оружия кодом.
Детали собираются прямо в bmesh (без сотен операторов Blender), по материалам; одна и та же раскладка даёт
две версии: боевую (HQ = False — мало сегментов, без мелочи) и ангарную (HQ = True — фаски, заклёпки, швы,
трафареты, ушки; окраска с запечённым AO и грязью в текстуре).
Оси как у WeaponModels: длина 1 вдоль +X (нос вперёд), центр в начале координат, верх (+Z в Blender) —
сторона крепления к пилону. Окраска (Kanta 19.10, S9-03 23.10): матовая краска roughness 0.84–0.88, metallic 0,
металл — только голые детали."""
import math, os, random
import bpy, bmesh
from mathutils import Vector, Matrix

HQ = True
G = {}          # материал → [вершины, грани]
XF = [Matrix.Identity(4)]   # стек преобразований: группа деталей (пакет, кассета) ставится одной матрицей
SPEC = {}       # материал → параметры
RNG = random.Random(7)


def reset(hq: bool):
    global HQ, G
    bpy.ops.wm.read_factory_settings(use_empty=True)
    HQ = hq
    G = {}
    SPEC.clear()
    del XF[1:]
    RNG.seed(7)


def S(n: int, lo: int = 8) -> int:
    """Число сегментов: в бою — втрое меньше"""
    return n if HQ else max(lo, int(round(n / 3.0)))


# ---------- материалы ----------
def paint(name, rgb, rough=0.86, metal=0.0, ao=0.55, grime=0.18, dust=0.3):
    """Краска: матовая, с AO, пятнами грязи и пылью снизу (запекается в текстуру ангарной версии)"""
    SPEC[name] = dict(rgb=rgb, rough=rough, metal=metal, ao=ao, grime=grime, dust=dust, emit=0.0)
    return name


def metal(name, rgb, rough=0.45, metal=0.75):
    SPEC[name] = dict(rgb=rgb, rough=rough, metal=metal, ao=0.6, grime=0.25, dust=0.15, emit=0.0)
    return name


def glow(name, rgb, strength=2.0):
    SPEC[name] = dict(rgb=rgb, rough=0.35, metal=0.0, ao=0.0, grime=0.0, dust=0.0, emit=strength)
    return name


def glass(name, rgb):
    SPEC[name] = dict(rgb=rgb, rough=0.12, metal=0.0, ao=0.2, grime=0.0, dust=0.0, emit=0.0)
    return name


# ---------- сборка геометрии ----------
def emit(bm, m, M=None):
    vs, fs = G.setdefault(m, ([], []))
    off = len(vs)
    bm.verts.index_update()
    M = XF[-1] if M is None else XF[-1] @ M
    vs.extend(M @ v.co for v in bm.verts)
    for f in bm.faces:
        fs.append([off + v.index for v in f.verts])
    bm.free()


class xf:
    """with xf(M): детали внутри ставятся с преобразованием M (вложенные — перемножаются)"""
    def __init__(self, M):
        self.M = M

    def __enter__(self):
        XF.append(XF[-1] @ self.M)

    def __exit__(self, *a):
        XF.pop()


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def RX(a):
    return Matrix.Rotation(a, 4, "X")


def RY(a):
    return Matrix.Rotation(a, 4, "Y")


def RZ(a):
    return Matrix.Rotation(a, 4, "Z")


def SC(x, y=None, z=None):
    return Matrix.Diagonal((x, x if y is None else y, x if z is None else z, 1.0))


def AX(d):
    """Поворот, переводящий +X в направление d"""
    return Vector((1, 0, 0)).rotation_difference(Vector(d).normalized()).to_matrix().to_4x4()


def lathe(prof, seg=48, cap0=True, cap1=True):
    """Тело вращения вокруг X: профиль [(x, r)] от хвоста к носу; r = 0 — вершина. Наружу — нормали"""
    if prof[-1][0] < prof[0][0]:   # нормали наружу: профиль всегда от хвоста к носу
        prof = prof[::-1]
        cap0, cap1 = cap1, cap0
    bm = bmesh.new()
    n = S(seg)
    rings = []
    for x, r in prof:
        if r <= 1e-7:
            rings.append([bm.verts.new((x, 0, 0))])
        else:
            rings.append([bm.verts.new((x, math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r)) for k in range(n)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(n):
            k1 = (k + 1) % n
            if len(a) == 1:
                bm.faces.new((a[0], b[k1], b[k]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[k1], b[0]))
            else:
                bm.faces.new((a[k], a[k1], b[k1], b[k]))
    if cap0 and len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if cap1 and len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    return bm


def lathe_sector(prof, a0, a1, seg=24, wall=None):
    """Сектор тела вращения (лепесток обтекателя) от угла a0 до a1; wall — доля радиуса: боковые стенки
    до r × wall (толщина лепестка видна в щели)"""
    if prof[-1][0] < prof[0][0]:
        prof = prof[::-1]
    bm = bmesh.new()
    n = max(2, S(seg, 3))
    ang = [a0 + (a1 - a0) * k / n for k in range(n + 1)]
    rings = [[bm.verts.new((x, math.cos(a) * r, math.sin(a) * r)) for a in ang] for x, r in prof]
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
    if wall:
        inner = [[bm.verts.new((x, math.cos(a) * r * wall, math.sin(a) * r * wall)) for a in (a0, a1)] for x, r in prof]
        for i in range(len(prof) - 1):
            if prof[i][1] < 1e-6 or prof[i + 1][1] < 1e-6:
                continue
            bm.faces.new((inner[i][0], rings[i][0], rings[i + 1][0], inner[i + 1][0]))
            bm.faces.new((inner[i][1], inner[i + 1][1], rings[i + 1][n], rings[i][n]))
    return bm


def ogive(x0, x1, r0, r_tip=0.0, k=8, power=0.62):
    """Оживальный нос: профиль от (x0, r0) к (x1, r_tip)"""
    out = []
    kk = S(k, 4)
    for i in range(kk + 1):
        t = i / kk
        r = r_tip + (r0 - r_tip) * (1 - t ** (1 / power)) ** 0.5 if t < 1 else r_tip
        out.append((x0 + (x1 - x0) * t, max(r, r_tip)))
    return out


def dome_prof(x0, r0, length, k=6, r_tip=0.0):
    """Полусфера/купол вдоль +X: от (x0, r0) до (x0 + length, r_tip)"""
    out = []
    kk = S(k, 3)
    for i in range(kk + 1):
        a = (math.pi / 2) * i / kk
        out.append((x0 + length * math.sin(a), r_tip + (r0 - r_tip) * math.cos(a)))
    return out


def grooves(x0, x1, r, at, w=0.004, d=0.0012):
    """Цилиндрический участок x0…x1 радиуса r со швами-канавками в точках at (только в ангаре)"""
    pts = [(x0, r)]
    if HQ:
        for x in sorted(at):
            if x0 + w < x < x1 - w:
                pts += [(x - w * 0.5, r), (x - w * 0.3, r - d), (x + w * 0.3, r - d), (x + w * 0.5, r)]
    pts.append((x1, r))
    return pts


def box(size, bevel=0.0, segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    b = min(bevel, min(size) * 0.45)
    if b > 1e-5 and (HQ or b > 0.004):
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=b, offset_type="OFFSET", segments=segs if HQ else 1,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def prism(outline, width, bevel=0.0, segs=2):
    """Профиль (x, z) выдавлен по Y на width (по центру) — перо оперения, пластина"""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -width / 2, z)) for x, z in outline]
    f = bm.faces.new(vs)
    bm.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.y += width
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    b = min(bevel, width * 0.45)
    if b > 1e-5 and HQ:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=b, offset_type="OFFSET", segments=segs, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    return bm


def cyl(r, h, seg=24, bevel=0.0):
    """Цилиндр вдоль X по центру, с фаской на торцах"""
    if bevel > 0 and HQ:
        b = min(bevel, r * 0.4, h * 0.4)
        prof = [(-h / 2, r - b), (-h / 2 + b * 0.3, r - b * 0.3), (-h / 2 + b, r), (h / 2 - b, r), (h / 2 - b * 0.3, r - b * 0.3), (h / 2, r - b)]
    else:
        prof = [(-h / 2, r), (h / 2, r)]
    return lathe(prof, seg)


def tube_shell(r_out, r_in, h, seg=24):
    """Открытая труба (стенка), вдоль X"""
    return lathe([(-h / 2, r_in), (-h / 2, r_out), (h / 2, r_out), (h / 2, r_in), (-h / 2, r_in)], seg, False, False)


def sphere(r, seg=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=S(seg), v_segments=max(4, S(seg) // 2), radius=r)
    return bm


def torus(R, r, seg=32, mseg=8):
    bm = bmesh.new()
    n, m = S(seg), S(mseg, 4)
    rings = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * math.sin(2 * math.pi * j / m), (R + r * math.cos(2 * math.pi * j / m)) * c,
                                    (R + r * math.cos(2 * math.pi * j / m)) * s)) for j in range(m)])
    for i in range(n):
        a, b = rings[i], rings[(i + 1) % n]
        for j in range(m):
            j1 = (j + 1) % m
            bm.faces.new((a[j], b[j], b[j1], a[j1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def rod(p0, p1, r, m, seg=10):
    """Тяга/трубка между точками"""
    d = Vector(p1) - Vector(p0)
    emit(cyl(r, d.length, seg), m, T(*((Vector(p0) + Vector(p1)) / 2)) @ AX(d))


def surf(x, a, r, h=0.0):
    """Матрица на поверхности тела вращения: +X локальной детали — наружу по радиусу, +Y — вдоль оси"""
    d = Vector((0, math.cos(a), math.sin(a)))
    rot = Matrix((Vector((0, math.cos(a), math.sin(a))), Vector((1, 0, 0)), Vector((0, math.sin(a), -math.cos(a))))).transposed()
    return T(x, d.y * (r + h), d.z * (r + h)) @ rot.to_4x4()


# ---------- мелкие детали (только ангар) ----------
def rivets(x, r, n, m, rr=0.0016, a0=0.0, skip_top=False, arc=None, yz=(0, 0)):
    """Кольцо заклёпок на радиусе r. arc=(a_from, a_to) — только дуга"""
    if not HQ:
        return
    for k in range(n):
        a = a0 + 2 * math.pi * k / n if arc is None else arc[0] + (arc[1] - arc[0]) * k / max(1, n - 1)
        if skip_top and math.sin(a) > 0.8:
            continue
        bm = lathe([(0, rr), (rr * 0.25, rr * 0.92), (rr * 0.5, rr * 0.55), (rr * 0.6, 0)], 6, True, False)
        emit(bm, m, T(0, yz[0], yz[1]) @ surf(x, a, r, -rr * 0.15))


def patch(x0, x1, a0, a1, r, m, lift=0.0005, nx=1, na=None, yz=(0, 0)):
    """Изогнутая накладка на теле вращения: краска, трафарет, лючок (r — число или функция r(x))"""
    rf = r if callable(r) else (lambda _x: r)
    na = na or max(1, int(abs(a1 - a0) / 0.2) + 1)
    bm = bmesh.new()
    grid = []
    for i in range(nx + 1):
        x = x0 + (x1 - x0) * i / nx
        row = []
        for j in range(na + 1):
            a = a0 + (a1 - a0) * j / na
            rr = rf(x) + lift
            row.append(bm.verts.new((x, yz[0] + math.cos(a) * rr, yz[1] + math.sin(a) * rr)))
        grid.append(row)
    for i in range(nx):
        for j in range(na):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]) if a1 > a0 else
                         (grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    emit(bm, m)


def stencil(x0, x1, a_mid, r, m, rows=3, h=0.0045, yz=(0, 0), seed=None):
    """Трафаретная маркировка без настоящих надписей: строки «слов» из коротких штрихов разной длины"""
    if not HQ:
        return
    rnd = random.Random(seed if seed is not None else RNG.random())
    rf = r if callable(r) else (lambda _x: r)
    for row in range(rows):
        a = a_mid + (row - (rows - 1) / 2) * h * 1.9 / rf((x0 + x1) / 2)
        x = x0
        end = x0 + (x1 - x0) * rnd.uniform(0.55, 1.0)
        while x < end:
            word = rnd.randint(2, 6)
            for _ in range(word):
                w = h * rnd.choice((0.35, 0.6, 0.8, 0.8, 1.0))
                if x + w > end:
                    break
                da = h * rnd.choice((0.55, 1.0, 1.0)) / 2 / rf(x)
                patch(x, x + w, a - da, a + da, rf, m, 0.0006, 1, 1, yz)
                x += w + h * 0.35
            x += h * 1.4


def screw(M, r, m):
    """Головка винта со шлицем (матрица — на поверхности, +X наружу)"""
    if not HQ:
        return
    emit(lathe([(0, r), (r * 0.25, r * 0.95), (r * 0.4, r * 0.7), (r * 0.45, 0)], 8, True, False), m, M)


def lug(x, z, m, size=1.0, along=True):
    """Подвесное ушко: опорная плита и скоба-петля сверху (ушки бомб, рельсы ракет)"""
    s = size
    emit(box((0.03 * s, 0.022 * s, 0.006 * s), 0.0015 * s), m, T(x, 0, z + 0.003 * s))
    if HQ:
        bm = torus(0.0085 * s, 0.0024 * s, 20, 8)
        # петля стоит вертикально в плоскости XZ, нижняя половина утоплена в плиту
        emit(bm, m, T(x, 0, z + 0.0075 * s) @ RZ(math.pi / 2))
    else:
        emit(box((0.016 * s, 0.006 * s, 0.014 * s)), m, T(x, 0, z + 0.008 * s))


# ---------- сборка, развёртка, запекание, экспорт ----------
def _material(name):
    sp = SPEC[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*sp["rgb"], 1)
    b.inputs["Metallic"].default_value = sp["metal"]
    b.inputs["Roughness"].default_value = sp["rough"]
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.35 if sp["metal"] < 0.3 else 0.5
    if sp["emit"] > 0:
        b.inputs["Emission Color"].default_value = (*sp["rgb"], 1)
        b.inputs["Emission Strength"].default_value = sp["emit"]
    return m


def _bake_setup(m, sp, img):
    """Процедурный цвет для запекания: цвет × AO × пятна грязи + пыль на нижних гранях"""
    nt = m.node_tree
    N, Lk = nt.nodes, nt.links
    b = N["Principled BSDF"]
    rgb = N.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (*sp["rgb"], 1)
    ao = N.new("ShaderNodeAmbientOcclusion")
    ao.samples = 12
    ao.inputs["Distance"].default_value = 0.035
    aom = N.new("ShaderNodeMapRange")
    aom.inputs["To Min"].default_value = 1.0 - sp["ao"]
    Lk.new(ao.outputs["AO"], aom.inputs["Value"])
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 22.0
    nz.inputs["Detail"].default_value = 8.0
    Lk.new(tc.outputs["Object"], nz.inputs["Vector"])
    gm = N.new("ShaderNodeMapRange")   # пятна: 1 → 1 − grime
    gm.inputs["From Min"].default_value = 0.42
    gm.inputs["From Max"].default_value = 0.7
    gm.inputs["To Min"].default_value = 1.0
    gm.inputs["To Max"].default_value = 1.0 - sp["grime"]
    Lk.new(nz.outputs["Fac"], gm.inputs["Value"])
    mul = N.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    Lk.new(rgb.outputs[0], mul.inputs[0])
    sc = N.new("ShaderNodeMath")
    sc.operation = "MULTIPLY"
    Lk.new(aom.outputs[0], sc.inputs[0])
    Lk.new(gm.outputs[0], sc.inputs[1])
    Lk.new(sc.outputs[0], mul.inputs[1])
    # пыль: нижние грани (нормаль вниз) и мелкий шум — к песочному
    geo = N.new("ShaderNodeNewGeometry")
    sep = N.new("ShaderNodeSeparateXYZ")
    Lk.new(geo.outputs["Normal"], sep.inputs[0])
    dm = N.new("ShaderNodeMapRange")
    dm.inputs["From Min"].default_value = 0.1
    dm.inputs["From Max"].default_value = -0.9
    dm.inputs["To Max"].default_value = sp["dust"]
    Lk.new(sep.outputs["Z"], dm.inputs["Value"])
    nz2 = N.new("ShaderNodeTexNoise")
    nz2.inputs["Scale"].default_value = 60.0
    Lk.new(tc.outputs["Object"], nz2.inputs["Vector"])
    dmul = N.new("ShaderNodeMath")
    dmul.operation = "MULTIPLY"
    Lk.new(dm.outputs[0], dmul.inputs[0])
    Lk.new(nz2.outputs["Fac"], dmul.inputs[1])
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    Lk.new(dmul.outputs[0], mix.inputs["Factor"])
    Lk.new(mul.outputs[0], mix.inputs[6])
    mix.inputs[7].default_value = (0.55, 0.49, 0.38, 1)
    Lk.new(mix.outputs[2], b.inputs["Base Color"])
    tex = N.new("ShaderNodeTexImage")
    tex.image = img
    N.active = tex
    for n in N:
        n.select = False
    tex.select = True
    return tex


def build(name, out, tex_size=1024, blend_dir=None, join=()):
    """Слить детали в один объект (по материалу — поверхность), сглаживание по углу, развёртка, запекание (HQ), GLB.
    join — готовые меши сцены (например, импортированная модель Sketchfab), которые после запекания деталей
    вливаются в тот же объект: в GLB игра берёт один меш на оружие (WeaponModels._glb_mesh)."""
    os.makedirs(out, exist_ok=True)
    verts, faces, mids, names = [], [], [], []
    for mi, (mname, (vs, fs)) in enumerate(G.items()):
        off = len(verts)
        verts.extend(vs)
        faces.extend([[off + i for i in f] for f in fs])
        mids.extend([mi] * len(fs))
        names.append(mname)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update(calc_edges=True)
    for n in names:
        me.materials.append(_material(n))
    for p, mi in zip(me.polygons, mids):
        p.material_index = mi
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    # сварка совпадающих вершин внутри деталей (полюса, стыки колец) и сглаживание по углу 38°
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-7)
    for f in bm.faces:
        f.smooth = True
    thr = math.radians(38)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            if e.calc_face_angle(0.0) > thr:
                e.smooth = False
        else:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("TRIS", name, tris)
    if HQ:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")
        img = bpy.data.images.new(name + "_albedo", tex_size, tex_size)
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 6
        sc.render.bake.margin = 6
        texn = {}
        for m in me.materials:
            sp = SPEC[m.name]
            if sp["emit"] > 0:
                # светящиеся детали без текстуры, но с активным узлом-приёмником (иначе bake не стартует)
                t = m.node_tree.nodes.new("ShaderNodeTexImage")
                t.image = img
                m.node_tree.nodes.active = t
                continue
            texn[m.name] = _bake_setup(m, sp, img)
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=6, use_clear=True)
        img.filepath_raw = os.path.join(out, name + "_albedo.png")
        img.file_format = "PNG"
        img.save()
        for m in me.materials:
            nt = m.node_tree
            b = nt.nodes["Principled BSDF"]
            if m.name in texn:
                nt.links.new(texn[m.name].outputs["Color"], b.inputs["Base Color"])
            else:
                for n in list(nt.nodes):
                    if n.type == "TEX_IMAGE":
                        nt.nodes.remove(n)
    if join:
        bpy.ops.object.select_all(action="DESELECT")
        for o in join:
            o.select_set(True)
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.join()
    if blend_dir:
        os.makedirs(blend_dir, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, name + (".blend" if HQ else "_battle.blend")))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format="GLB", use_selection=False,
                              export_image_format="JPEG", export_jpeg_quality=88, export_apply=True)
    png = os.path.join(out, name + "_albedo.png")
    if os.path.exists(png):
        os.remove(png)
    return ob
