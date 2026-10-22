# Общие функции подготовки моделей «Архипелага» в Blender (bpy). Используются в biome2_models.py.
# Рабочая система координат после place(): нос +X, левый борт +Y, верх +Z (Blender), единица — метр,
# ватерлиния (или земля) на z = 0, центр по X/Y в нуле. finish() поворачивает в glTF (+Y вверх) и делает длину 1.
import math, bpy, bmesh
from mathutils import Vector, Matrix


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    """Импорт GLB; трансформации запекаются в сетку, родители снимаются. Возвращает меши."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    ms = [o for o in new if o.type == 'MESH']
    for o in ms:
        if o.data.users > 1:
            o.data = o.data.copy()
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in new:
        if o.type != 'MESH':
            bpy.data.objects.remove(o)
    for m in mats(ms):   # «неосвещённые» материалы сканов (KHR_materials_unlit) → обычные, чтобы был свет и тень
        if m.use_nodes and not any(n.type == 'BSDF_PRINCIPLED' for n in m.node_tree.nodes):
            nt = m.node_tree
            tex = next((n for n in nt.nodes if n.type == 'TEX_IMAGE'), None)
            out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
            b = nt.nodes.new('ShaderNodeBsdfPrincipled')
            if tex:
                nt.links.new(tex.outputs['Color'], b.inputs['Base Color'])
            nt.links.new(b.outputs['BSDF'], out.inputs['Surface'])
    return ms


def bounds(objs):
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return Vector(map(min, *pts)), Vector(map(max, *pts))


def diag(o):
    mn, mx = bounds([o])
    return (mx - mn).length


def tris(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


def drop(objs, names=(), mindiag=0.0, keep=None):
    """Убрать объекты по имени ('Rail*' — по началу имени) или мельче габарита (метры после place)."""
    out = []
    for o in objs:
        if any(k.upper() == o.name.upper() or (k.endswith('*') and o.name.upper().startswith(k[:-1].upper())) for k in names) or diag(o) < mindiag or (keep and not keep(o)):
            bpy.data.objects.remove(o)
        else:
            out.append(o)
    return out


def xform(objs, m):
    for o in objs:
        o.data.transform(m)
        o.data.update()


def place(objs, bow='+x', length=None, water=None, up='+z'):
    """Повернуть носом на +X, поставить ватерлинию/землю на z=0, длина по X = length метров.
    water — высота ватерлинии в исходных единицах (после поворота up), None — низ модели."""
    if up == '+y':   # модель лежит «на боку» (glTF без поворота)
        xform(objs, Matrix.Rotation(math.radians(90), 4, 'X'))
    rot = {'+x': 0, '-y': 90, '-x': 180, '+y': -90}[bow]
    xform(objs, Matrix.Rotation(math.radians(rot), 4, 'Z'))
    mn, mx = bounds(objs)
    wz = mn.z if water is None else water
    xform(objs, Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -wz)))
    if length:
        xform(objs, Matrix.Scale(length / (mx.x - mn.x), 4))


def scale_to(objs, length):
    mn, mx = bounds(objs)
    xform(objs, Matrix.Scale(length / (mx.x - mn.x), 4))


def kill_faces(objs, fn, mat=None):
    """Удалить грани, у которых fn(центр, нормаль) истинно (координаты после place); mat — только с этим материалом."""
    for o in objs:
        idx = [i for i, m in enumerate(o.data.materials) if m and (mat is None or m.name == mat)]
        if not idx:
            continue
        bm = bmesh.new(); bm.from_mesh(o.data)
        kill = [f for f in bm.faces if f.material_index in idx and fn(f.calc_center_median(), f.normal)]
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        bm.to_mesh(o.data); bm.free()
    out = []
    for o in objs:
        if len(o.data.polygons):
            out.append(o)
        else:
            bpy.data.objects.remove(o)
    return out


def kill_parts(objs, fn):
    """Удалить связные куски сетки, у которых fn(min, max, число вершин) истинно — мелочь, антенны, знаки."""
    n = 0
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data); bm.verts.ensure_lookup_table()
        seen = set(); kill = []
        for v in bm.verts:
            if v.index in seen:
                continue
            st = [v]; comp = []; seen.add(v.index)
            while st:
                x = st.pop(); comp.append(x)
                for e in x.link_edges:
                    y = e.other_vert(x)
                    if y.index not in seen:
                        seen.add(y.index); st.append(y)
            cs = [c.co for c in comp]
            mn = Vector([min(c[i] for c in cs) for i in range(3)]); mx = Vector([max(c[i] for c in cs) for i in range(3)])
            if fn(mn, mx, len(comp)):
                kill += comp
        n += len(kill)
        bmesh.ops.delete(bm, geom=kill, context='VERTS')
        bm.to_mesh(o.data); bm.free()
    print("kill_parts: вершин убрано", n)
    return [o for o in objs if len(o.data.polygons)]


def regrade(img, rgb, keep=0.7, lo=0.35, hi=1.6):
    """Перекрасить текстуру в цвет rgb, сохранив светотень и грязь: яркость/средняя ^ keep."""
    import numpy as np
    a = pixels(img)
    l = a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11
    k = np.clip((l / max(1e-3, float(l.mean()))) ** keep, lo, hi)
    for i in range(3):
        a[..., i] = np.clip(rgb[i] * k, 0, 1)
    put_pixels(img, a)


def _box_area(o):
    mn, mx = bounds([o]); d = mx - mn
    return d.x * d.y + d.y * d.z + d.x * d.z + 1e-6


def _decimate(o, ratio):
    if ratio >= 1:
        return
    m = o.modifiers.new('dc', 'DECIMATE'); m.ratio = max(0.01, ratio); m.use_collapse_triangulate = True
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.modifier_apply(modifier='dc')


def planar(objs, deg=1.0):
    """Слить плоские грани (limited dissolve) — без потери формы."""
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(deg), verts=bm.verts, edges=bm.edges)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.to_mesh(o.data); bm.free()


def weld(objs, dist=1e-4):
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
        bm.to_mesh(o.data); bm.free()


def budget(objs, target, power=1.0):
    """Упростить до target треугольников: бюджет делим по видимой площади детали (крупное остаётся гладким)."""
    tot = tris(objs)
    if tot <= target:
        return
    w = {o: _box_area(o) ** power for o in objs}; s = sum(w.values())
    for it in range(5):
        for o in objs:
            t = tris([o]); want = max(12, target * w[o] / s * (0.92 ** it))
            if t > want:
                _decimate(o, want / t)
        if tris(objs) <= target * 1.05:
            break


def join(objs, name='body'):
    objs = [o for o in objs if o.name in bpy.data.objects]
    with bpy.context.temp_override(object=objs[0], active_object=objs[0], selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


# ---------- материалы ----------

def lin(c):
    """sRGB 0..1 → линейный (цвет материала в Blender задаётся линейным)."""
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def flat(name, rgb, rough=0.75, metal=0.0):
    """Материал без текстуры; rgb — sRGB, как на экране."""
    rgb = lin(rgb)
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*rgb, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    return m


def bsdf(mat):
    return next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def tex_of(mat):
    for l in bsdf(mat).inputs['Base Color'].links:
        if l.from_node.type == 'TEX_IMAGE':
            return l.from_node.image
    return None


def solid(mat, rgb, rough=None, metal=None):
    """Убрать текстуру цвета и залить цветом."""
    b = bsdf(mat)
    for l in list(b.inputs['Base Color'].links):
        mat.node_tree.links.remove(l)
    b.inputs['Base Color'].default_value = (*lin(rgb), 1)
    if rough is not None:
        b.inputs['Roughness'].default_value = rough
    if metal is not None:
        b.inputs['Metallic'].default_value = metal


def no_emit(objs):
    for o in objs:
        for mat in o.data.materials:
            if not mat or not mat.use_nodes:
                continue
            b = bsdf(mat)
            for l in list(b.inputs['Emission Color'].links):
                mat.node_tree.links.remove(l)
            b.inputs['Emission Strength'].default_value = 0.0


def mats(objs):
    out = []
    for o in objs:
        for m in o.data.materials:
            if m and m not in out:
                out.append(m)
    return out


def assign(o, mat):
    o.data.materials.clear(); o.data.materials.append(mat)


def pixels(img):
    import numpy as np
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32); img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def put_pixels(img, a):
    img.pixels.foreach_set(a.ravel()); img.update()
    img.pack()


def shrink(maxpx=1024):
    for im in bpy.data.images:
        if im.size[0] > maxpx or im.size[1] > maxpx:
            k = maxpx / max(im.size)
            im.scale(max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k)))


# ---------- простые детали (координаты после place, метры) ----------

def _new(name, bm, mat):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    if mat:
        me.materials.append(mat)
    return o


def box(c, size, mat, name='box', rz=0.0):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rz, 3, 'Z'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    return _new(name, bm, mat)


def cyl(c, r, h, mat, name='cyl', seg=12, axis='Z', r2=None, rot=None):
    """Цилиндр (или конус, r2) вдоль оси; c — центр."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    m = {'Z': Matrix.Identity(3), 'X': Matrix.Rotation(math.radians(90), 3, 'Y'),
         'Y': Matrix.Rotation(math.radians(-90), 3, 'X')}[axis]
    if rot is not None:
        m = rot @ m
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=m, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    return _new(name, bm, mat)


def sphere(c, r, mat, name='sph', seg=12, scale=(1, 1, 1)):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(4, seg // 2), radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    return _new(name, bm, mat)


def hull(pts, mat, name='hull'):
    """Выпуклая оболочка точек — для простых корпусов и надстроек."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(p)) for p in pts]
    bmesh.ops.convex_hull(bm, input=vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new(name, bm, mat)


def loft(sections, mat, name='loft', cap=True):
    """Тело по сечениям: sections — список колец точек одинаковой длины (по порядку вдоль тела)."""
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector(p)) for p in s] for s in sections]
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new(name, bm, mat)


def smooth(objs, deg=35):
    for o in objs:
        for p in o.data.polygons:
            p.use_smooth = True
        if hasattr(o.data, 'set_sharp_from_angle'):
            o.data.set_sharp_from_angle(angle=math.radians(deg))


def copy_glb(path, mat=None):
    """Взять готовую игровую модель (glTF, длина 1, +Y вверх) как деталь: возвращает меши в рабочей системе."""
    objs = load(path)
    return objs


# ---------- выход ----------

def finish(objs, out, target=None, maxtex=1024, length=1.0, name='body', center=False, fit='x'):
    """Склеить, упростить до target и записать GLB (glTF: +Y вверх). fit='x' — длина по X = length (корабли, враги),
    fit='xy' — наибольший размер по горизонтали = length (постройки, природа — как biome_prep.py)."""
    objs = [o for o in objs if o.name in bpy.data.objects and len(o.data.polygons)]
    if target:
        budget(objs, target)
    ob = join(objs, name)
    weld([ob], 1e-5)
    if target and tris([ob]) > target * 1.05:
        _decimate(ob, target / tris([ob]))
    mn, mx = bounds([ob])
    if center:   # самолёты — центр по высоте в нуле (соглашение model_lab.gd)
        ob.data.transform(Matrix.Translation((0, 0, -(mn.z + mx.z) / 2)))
    span = (mx.x - mn.x) if fit == 'x' else max(mx.x - mn.x, mx.y - mn.y)   # 'xy' — постройки и природа Нагорья
    ob.data.transform(Matrix.Scale(length / span, 4)); ob.data.update()
    shrink(maxtex)
    natural([ob])
    for o in list(bpy.data.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    mn, mx = bounds([ob])
    print("FINISH", out.split('/')[-1], "tris", tris([ob]), "size", tuple(round(v, 3) for v in (mx - mn)),
          "zmin", round(mn.z, 3), "mats", len(ob.data.materials))
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_image_format='JPEG',
                              export_jpeg_quality=88, use_selection=False, export_yup=True)
    return ob


def natural(objs, rough=0.88, vmax=0.72, sat=0.80):
    """Реалистичная окраска (правило Kanta 19.10): без блеска и металла, без чисто белого и кислотных цветов.
    Шероховатость не ниже rough, металл 0; яркость цвета не выше vmax, насыщенность × sat — и у заливок, и у текстур."""
    import colorsys
    import numpy as np
    done = set()
    for m in mats(objs):
        if not m.use_nodes:
            continue
        b = bsdf(m)
        r = b.inputs['Roughness'].default_value if not b.inputs['Roughness'].links else rough
        for k in ('Metallic', 'Roughness'):
            for l in list(b.inputs[k].links):
                m.node_tree.links.remove(l)
        b.inputs['Metallic'].default_value = 0.0
        b.inputs['Roughness'].default_value = max(r, rough)
        img = tex_of(m)
        if img is None:
            c = b.inputs['Base Color'].default_value
            srgb = [x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055 for x in c[:3]]
            h, sv, v = colorsys.rgb_to_hsv(*srgb)
            b.inputs['Base Color'].default_value = (*lin(colorsys.hsv_to_rgb(h, sv * sat, min(v, vmax))), 1)
        elif img.name not in done:
            done.add(img.name)
            a = pixels(img)
            rgb = a[..., :3]
            mx = rgb.max(axis=-1, keepdims=True); mn = rgb.min(axis=-1, keepdims=True)
            rgb = mx - (mx - rgb) * sat                       # насыщенность × sat при той же яркости
            hi = float(np.percentile(mx, 98))
            if hi > vmax:                                     # самые светлые места — не выше vmax
                rgb = rgb * (vmax / hi)
            a[..., :3] = np.clip(rgb, 0, 1)
            put_pixels(img, a)


def matte(objs, rough=0.8, metal=0.0):
    """Снять карты металла/шероховатости исходника: в игре корпуса матовые, без «зеркала»."""
    for m in mats(objs):
        if not m.use_nodes:
            continue
        b = bsdf(m)
        for k in ('Metallic', 'Roughness'):
            for l in list(b.inputs[k].links):
                m.node_tree.links.remove(l)
        b.inputs['Metallic'].default_value = metal
        b.inputs['Roughness'].default_value = rough


def degraffiti(img, keep_hues=((20, 75), (75, 160)), sat=0.22, gray=None):
    """Стереть яркие надписи и граффити на скане: насыщенные пиксели вне «природных» оттенков
    (песок/охра 20–75°, трава 75–160°) → серый бетон той же яркости."""
    import numpy as np
    a = pixels(img)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = np.max(a[..., :3], axis=2); mn = np.min(a[..., :3], axis=2); d = mx - mn + 1e-6
    h = np.where(mx == r, (g - b) / d % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    s = d / (mx + 1e-6)
    natural = np.zeros_like(s, dtype=bool)
    for lo, hi in keep_hues:
        natural |= (h >= lo) & (h < hi)
    bad = (s > sat) & ~natural
    l = r * 0.3 + g * 0.59 + b * 0.11
    base = gray or (0.62, 0.61, 0.58)
    k = np.clip(l / 0.6, 0.5, 1.2)
    for i in range(3):
        a[..., i] = np.where(bad, base[i] * k, a[..., i])
    put_pixels(img, a)
    print("degraffiti: пикселей", int(bad.sum()), "из", bad.size)


def ring(c, r_out, r_in, h, mat, name='ring', seg=24):
    """Кольцевой бруствер / стенка: труба с верхом, без дна."""
    bm = bmesh.new()
    def circ(r, z):
        return [bm.verts.new((c[0] + r * math.cos(2 * math.pi * i / seg), c[1] + r * math.sin(2 * math.pi * i / seg), c[2] + z))
                for i in range(seg)]
    ob, ot, it, ib = circ(r_out, 0), circ(r_out, h), circ(r_in, h), circ(r_in, 0)
    for a, b in ((ob, ot), (ot, it), (it, ib)):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new(name, bm, mat)


def crown(objs, mat, n=10, seed=1, flat=0.75, grow=1.15, seg=8):
    """Крона из «облаков»: точки листвы делим на n кучек (k-средних), на каждую — сплюснутый шар.
    С высоты 2–4 км листья по одному не видны — читается масса кроны, а треугольников в десятки раз меньше."""
    import numpy as np, random
    pts = np.array([tuple(o.matrix_world @ v.co) for o in objs for v in o.data.vertices])
    rng = np.random.default_rng(seed)
    c = pts[rng.choice(len(pts), n, replace=False)]
    for _ in range(12):
        lab = np.argmin(((pts[:, None, :] - c[None]) ** 2).sum(-1), axis=1)
        c = np.array([pts[lab == k].mean(0) if (lab == k).any() else c[k] for k in range(n)])
    out = []
    r = random.Random(seed)
    for k in range(n):
        p = pts[lab == k]
        if len(p) < 4:
            continue
        sd = p.std(0) * 1.7 * grow
        rad = float(max(sd[0], sd[1], 0.3))
        sph = sphere(tuple(c[k]), rad, mat, 'crown', seg=seg, scale=(sd[0] / rad + 0.15, sd[1] / rad + 0.15, max(flat * sd[2] / rad, 0.35)))
        for v in sph.data.vertices:   # неровный край
            v.co += Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-1, 1))) * rad * 0.12
        out.append(sph)
    return out
