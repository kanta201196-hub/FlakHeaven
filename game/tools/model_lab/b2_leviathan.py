# Б-3 «Левиафан» (босс Архипелага) и его выбиваемые части — переделка по замечаниям Kanta 19.10:
# палуба — ровный настил с разметкой без нарисованной техники исходника; части (башня ГК, пусковая, РЛС, ЗСУ) —
# кодом, чистыми объёмами с фасками; разбитые версии — пробоины с рваными краями и лепестками наружу, сорванные
# крышки, вывернутые и оторванные стволы, копоть пятнами вокруг пробоин, обломки рядом. Окраска — матовая
# «натуральная» (шероховатость 0.9, без металла, насыщенность ×0.8, яркость ≤ 0.72), цвет — в вершинах (один
# материал на модель), поэтому копоть и грязь ложатся пятнами без текстур.
#   python3 -I game/tools/model_lab/b2_leviathan.py <e_leviathan|e_lev_turret|e_lev_launcher|e_lev_radar|e_lev_zsu|all>
#       [--src=/mnt/project-files/docs/biome2/models_in] [--out=game/models]
# Узлы частей (их двигает scripts/leviathan_parts.gd): башня — turret (поворот) → guns (наклон стволов);
# пусковая — lid_0…lid_7 (крышки на шарнире, ось вдоль X); РЛС — antenna (вращение); ЗСУ — turret → gun.
# Начало координат части — центр гнезда на верху площадки; длина 1 = REF[часть] метров (у целой и разбитой
# одинаково, чтобы разбитая встала точно на место целой). Места и размеры — models/biome2/leviathan_sockets.json.
import sys, os, math, random, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
import b2lib as L

A = sys.argv[1:]
OPT = dict(x[2:].split('=', 1) for x in A if x.startswith('--') and '=' in x)
SRC = OPT.get('src', '/mnt/project-files/docs/biome2/models_in')
MODELS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'models'))
OUT = OPT.get('out', MODELS)

LEV_LEN = 250.0
LEV_DECK = 15.0          # условная высота палубы для гнёзд (настил полётной палубы — 13.7 м над водой)
# длина 1 модели части = REF метров
REF = {'main_turret': 26.0, 'launcher': 10.0, 'radar': 10.0, 'zsu': 7.0}
# гнёзда (метры в модели: x вперёд, y влево, z вверх от воды) — те же, что были (PR #190)
SOCKETS = [('main_turret', (96.0, 0.0, 18.3), 0.0), ('main_turret', (74.0, 0.0, 21.3), 0.0),
           ('launcher', (52.0, -8.5, 18.3), 0.0), ('launcher', (52.0, 8.5, 18.3), 0.0),
           ('radar', (5.04, -6.25, 37.72), 0.0),
           ('zsu', (-95.0, 20.53, 15.6), 90.0), ('zsu', (-95.0, -12.61, 15.6), -90.0),
           ('zsu', (-40.0, 25.37, 15.6), 90.0), ('zsu', (-40.0, -13.04, 15.6), -90.0),
           ('zsu', (28.0, 27.87, 15.6), 90.0), ('zsu', (28.0, -11.96, 15.6), -90.0)]


def battle(name):
    return os.path.join(OUT, 'battle', 'fh_battle_%s.glb' % name)


# ---------------- окраска ----------------
def nat(rgb):
    """«Натуральная» окраска Архипелага: насыщенность ×0.8, яркость (максимум канала) не выше 0.72."""
    l = rgb[0] * 0.3 + rgb[1] * 0.59 + rgb[2] * 0.11
    c = [l + (x - l) * 0.8 for x in rgb]
    k = min(1.0, 0.72 / max(max(c), 1e-3))
    return tuple(max(0.0, x * k) for x in c)


HULL = (0.42, 0.435, 0.45)        # шаровый (башни, корпус)
HULL_D = (0.30, 0.31, 0.32)       # погоны, основания
PAD = (0.20, 0.205, 0.21)         # площадки гнёзд на палубе
DECK = (0.27, 0.28, 0.29)         # настил
SUPER = (0.47, 0.485, 0.50)       # надстройки, мачты — светлее корпуса (дымка на высоте)
LID = (0.30, 0.31, 0.32)
RED = (0.50, 0.21, 0.17)          # приглушённый сурик: крыши башен — опознавание врага, как у «Сторожа»
GUN = (0.23, 0.235, 0.24)         # стволы: тёмная матовая краска
RUBBER = (0.15, 0.15, 0.15)       # чехлы стволов
DOME = (0.64, 0.64, 0.61)         # обтекатели (стеклопластик)
MSL = (0.60, 0.60, 0.58)
INSIDE = (0.07, 0.065, 0.06)      # выгоревшее нутро
SOOT = (0.045, 0.04, 0.035)


def vc(c):
    """Цвет вершин пишем в sRGB: Godot читает COLOR_0 этих моделей как sRGB (проверено кадром рядом с обычным
    материалом того же цвета)."""
    return tuple(c)


def vmat():
    """Один матовый материал: цвет — атрибут вершин Col (glTF COLOR_0), двусторонний (лепестки пробоин)."""
    m = bpy.data.materials.get('fh_lev_paint')
    if m:
        return m
    m = bpy.data.materials.new('fh_lev_paint'); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    ca = nt.nodes.new('ShaderNodeVertexColor'); ca.layer_name = 'Col'
    nt.links.new(ca.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.9
    b.inputs['Metallic'].default_value = 0.0
    m.use_backface_culling = False
    return m


def _col(o):
    me = o.data
    if 'Col' not in me.color_attributes:
        me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    return me.color_attributes['Col']


def paint(o, rgb):
    a = _col(o); c = (*vc(nat(rgb)), 1.0)
    for d in a.data:
        d.color = c
    L.assign(o, vmat())
    return o


def tint(objs, fn):
    """Перекрасить вершины: fn(точка, линейный rgb) → линейный rgb."""
    for o in objs:
        if not alive(o):
            continue
        a = _col(o)
        for i, v in enumerate(o.data.vertices):
            c = a.data[i].color
            r = fn(v.co, (c[0], c[1], c[2]))
            a.data[i].color = (r[0], r[1], r[2], 1.0)


def grime(objs, z0, h, k=0.78):
    """Пыль и потёки снизу: к основанию (z0) темнее, выше h — чисто."""
    def f(p, c):
        t = min(1.0, max(0.0, (p.z - z0) / h))
        m = k + (1 - k) * t * t * (3 - 2 * t)
        return (c[0] * m, c[1] * m * 0.99, c[2] * m * 0.97)
    tint(objs, f)


# ---------------- форма: фаски и сглаживание ----------------
def _apply(o):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    o.modifiers.clear(); o.data = me


def bev(o, w, seg=2, ang=40):
    if w > 0:
        m = o.modifiers.new('b', 'BEVEL'); m.width = w; m.segments = seg
        m.limit_method = 'ANGLE'; m.angle_limit = math.radians(ang)
        _apply(o)
    L.smooth([o], 42)
    return o


def solid(o, t):
    m = o.modifiers.new('s', 'SOLIDIFY'); m.thickness = t; m.offset = 0
    _apply(o)
    return o


def B(c, size, col, w=0.06, rz=0.0, seg=2):
    return paint(bev(L.box(c, size, None, 'p', rz=rz), min(w, min(size) * 0.3), seg), col)


def C(c, r, h, col, seg=24, axis='Z', r2=None, w=0.0, rot=None):
    o = L.cyl(c, r, h, None, 'p', seg=seg, axis=axis, r2=r2, rot=rot)
    return paint(bev(o, min(w, h * 0.3, r * 0.3) if w else 0, 2, 50), col)


def H(pts, col, w=0.08, seg=2):
    return paint(bev(L.hull(pts, None, 'p'), w, seg, 30), col)


def S(c, r, col, seg=16, scale=(1, 1, 1)):
    o = L.sphere(c, r, None, 'p', seg=seg, scale=scale)
    L.smooth([o], 80)
    return paint(o, col)


def rod(p0, p1, r, col, seg=6, r2=None):
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    o = L.cyl((p0 + p1) / 2, r, d.length, None, 'p', seg=seg, axis='Z', r2=r2, rot=rot)
    L.smooth([o], 60)
    return paint(o, col)


def bar(p0, p1, w, col, up=(0, 0, 1)):
    """Брусок квадратного сечения w между точками (решётки антенн, фермы)."""
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    o = L.box((0, 0, 0), (d.length, w, w), None, 'p')
    x = d.normalized(); u = Vector(up)
    if abs(x.dot(u)) > 0.95:
        u = Vector((1, 0, 0)) if abs(x.x) < 0.9 else Vector((0, 1, 0))
    y = u.cross(x).normalized(); z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    o.data.transform(Matrix.Translation((p0 + p1) / 2) @ m)
    return paint(o, col)


def alive(o):
    try:
        return o.name in bpy.data.objects
    except ReferenceError:
        return False


def xf(objs, m):
    for o in objs:
        o.data.transform(m); o.data.update()
    return objs


def rot_about(p, axis, deg):
    p = Vector(p)
    return Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-p)


# ---------------- разрушения ----------------
_NK = {}


def _noise(p, seed, f=1.0):
    """Гладкий шум −1…1 (сумма синусов по случайным направлениям) — рваные, но не «игольчатые» края."""
    ks = _NK.get(seed)
    if ks is None:
        r = random.Random(seed)
        ks = [(Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-1, 1))).normalized() * (1.9 ** i), r.uniform(0, 6.28), 1.0 / (1.5 ** i)) for i in range(5)]
        _NK[seed] = ks
    return sum(math.sin(p.dot(k) * f + ph) * a for k, ph, a in ks) / 2.1


def densify(o, c, R, cell):
    """Измельчить сетку у точки c (радиус R) до ячейки cell — чтобы пробоина и копоть легли плавно."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    for _ in range(7):
        bmesh.ops.triangulate(bm, faces=bm.faces)
        es = [e for e in bm.edges if e.calc_length() > cell and min((v.co - c).length for v in e.verts) < R]
        if not es:
            break
        bmesh.ops.subdivide_edges(bm, edges=es, cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(o.data); bm.free()


def _near(o, c, R):
    mn, mx = L.bounds([o])
    q = Vector([min(max(c[i], mn[i]), mx[i]) for i in range(3)])
    return (q - c).length < R


def blast(objs, c, R, n, seed, hole=True, push=0.55, soot=2.6, cell=None, heat=True):
    """Взрыв в точке c: дыра с рваным краем радиуса ~R (hole), края — лепестками наружу по n, вокруг — копоть
    пятном (до ~soot·R, край неровный), у самой кромки — побежалость (бурый нагар)."""
    c = Vector(c); n = Vector(n).normalized(); cell = cell or R / 2.5
    f = 2.2 / R
    for o in objs:
        if not alive(o) or not _near(o, c, R * soot * 1.3):
            continue
        mn, mx = L.bounds([o]); size = (mx - mn).length
        small = size < R * 1.2
        if small and hole and ((mn + mx) / 2 - c).length < R * 0.9:
            bpy.data.objects.remove(o)                   # мелкую деталь в центре взрыва снесло целиком
            continue
        if hole and not small:
            densify(o, c, R * 1.9, cell)                 # у дыры — мелко, на копоть хватит крупнее
        if size > R * 2.0:
            densify(o, c, R * soot * 1.1, max(R / 1.0, 0.3))
        if hole and not small:
            bm = bmesh.new(); bm.from_mesh(o.data)
            kill = [fc for fc in bm.faces if (fc.calc_center_median() - c).length < R * (1 + 0.38 * _noise(fc.calc_center_median(), seed, f))]
            bmesh.ops.delete(bm, geom=kill, context='FACES')
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
            for v in bm.verts:
                d = (v.co - c).length
                rr = R * (1 + 0.38 * _noise(v.co, seed, f))
                if d < rr * 1.9:
                    t = max(0.0, 1 - (d - rr * 0.9) / (rr * 1.0)) ** 1.7
                    rad = (v.co - c) - n * (v.co - c).dot(n)
                    rad = rad.normalized() if rad.length > 1e-6 else Vector()
                    curl = 0.65 + 0.45 * _noise(v.co, seed + 7, f * 1.7)
                    v.co += (n * 0.85 + rad * 0.4) * t * R * push * curl
            bm.to_mesh(o.data); bm.free()
        sl = vc(SOOT)
        burn = vc((0.20, 0.13, 0.08))

        def fn(p, col):
            d = (p - c).length
            edge = R * soot * (1 + 0.35 * _noise(p, seed + 3, f * 0.8))
            s = min(1.0, max(0.0, (d - R * 0.95) / max(edge - R * 0.95, 1e-3)))
            s = s * s * (3 - 2 * s)
            spot = 0.5 + 0.5 * _noise(p, seed + 11, f * 2.5)     # копоть неровная, пятнами
            s = min(1.0, s + (1 - s) * 0.25 * spot)
            out = [sl[i] * (1 - s) + col[i] * s for i in range(3)]
            if heat and hole and d < R * 1.6:
                h = max(0.0, 1 - (d - R) / (R * 0.6)) * 0.45
                out = [out[i] * (1 - h) + burn[i] * h for i in range(3)]
            return out
        tint([o], fn)


def scorch(c, R, seed, z=0.03, base=PAD):
    """Пятно копоти на палубе — тонкий диск с рваным краем, цвет — от копоти к палубе."""
    bm = bmesh.new(); n = 28
    cv = bm.verts.new(Vector(c) + Vector((0, 0, z)))
    ring1, ring2 = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        d = Vector((math.cos(a), math.sin(a), 0))
        r = R * (1 + 0.22 * _noise(d * 3, seed))
        ring1.append(bm.verts.new(Vector(c) + d * r * 0.55 + Vector((0, 0, z))))
        ring2.append(bm.verts.new(Vector(c) + d * r + Vector((0, 0, z))))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((cv, ring1[i], ring1[j]))
        bm.faces.new((ring1[i], ring2[i], ring2[j], ring1[j]))
    o = L._new('p', bm, None)
    paint(o, base)
    sl = vc((0.07, 0.065, 0.06)); bl = vc(nat(base))
    tint([o], lambda p, col: [sl[i] + (bl[i] - sl[i]) * min(1.0, ((p - Vector(c)).length / R) ** 1.4) for i in range(3)])
    return o


def chunk(c, s, col, seed, flat=0.45):
    """Обломок: неправильный многогранник, лежит на z = c.z."""
    r = random.Random(seed)
    pts = [(r.uniform(-1, 1) * s, r.uniform(-0.7, 0.7) * s, r.uniform(0, flat) * s) for _ in range(9)]
    o = H(pts, col, w=0.0)
    xf([o], Matrix.Translation(c) @ Matrix.Rotation(r.uniform(0, 6.28), 4, 'Z'))
    return o


def plate(c, w, h, col, seed, bend=25.0, t=0.08, tilt=(0, 0, 0)):
    """Сорванный лист брони: изогнут, края рваные, с толщиной."""
    r = random.Random(seed)
    bm = bmesh.new(); nx, ny = 6, 4
    vs = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            x = (i / nx - 0.5) * w; y = (j / ny - 0.5) * h
            if i in (0, nx) or j in (0, ny):
                x += r.uniform(-0.12, 0.12) * w / nx * 2; y += r.uniform(-0.12, 0.12) * h / ny * 2
            z = math.sin(math.radians(bend)) * ((i / nx) ** 2) * w * 0.5 + r.uniform(-0.02, 0.02) * w
            vs[i, j] = bm.verts.new((x, y, z))
    for i in range(nx):
        for j in range(ny):
            bm.faces.new((vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]))
    o = L._new('p', bm, None)
    solid(o, t)
    L.smooth([o], 50)
    paint(o, col)
    xf([o], Matrix.Translation(c) @ Matrix.Rotation(math.radians(tilt[2]), 4, 'Z') @ Matrix.Rotation(math.radians(tilt[1]), 4, 'Y')
       @ Matrix.Rotation(math.radians(tilt[0]), 4, 'X'))
    return o


def pipe(p0, p1, r0, r1, col, seg=16, jag=0.0, seed=1, flare=0.0, cap0=True):
    """Труба/ствол от p0 к p1 (конус r0→r1). jag > 0 — конец оторван: рваная кромка, раструб, копоть."""
    r = random.Random(seed)
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0; ln = d.length
    bm = bmesh.new(); rings = []
    steps = [0.0, 1.0] if not jag else [0.0, 0.7, 0.86, 1.0]
    for t in steps:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rr = r0 + (r1 - r0) * t
            dz = 0.0
            if jag and t == 1.0:
                dz = -r.uniform(0, jag)
                rr *= 1 + flare * r.uniform(0.3, 1.0)
            elif jag and t > 0.8:
                rr *= 1 + flare * 0.3 * r.uniform(0, 1)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), t * ln + dz)))
        rings.append(ring)
    for ra, rb in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
    if cap0:
        bm.faces.new(list(reversed(rings[0])))
    if not jag:
        bm.faces.new(rings[-1])
    o = L._new('p', bm, None)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    o.data.transform(Matrix.Translation(p0) @ rot)
    L.smooth([o], 50)
    paint(o, col)
    if jag:
        sl = vc(SOOT); e = p1
        tint([o], lambda p, col: [sl[i] + (col[i] - sl[i]) * min(1.0, ((p - e).length / (ln * 0.35)) ** 1.5) for i in range(3)])
    return o


# ---------------- выход: узлы с точкой вращения ----------------
def export(groups, path, ref):
    """groups — [(имя узла, детали, точка вращения (м), родитель | None)]; длина 1 = ref метров."""
    k = 1.0 / ref
    made = {}
    for name, objs, piv, parent in groups:
        objs = [o for o in objs if alive(o) and len(o.data.polygons)]
        for o in objs:
            _col(o)
        if os.environ.get('LEV_DBG'):
            for o in sorted(objs, key=lambda o: -L.tris([o]))[:6]:
                mn, mx = L.bounds([o])
                print('DBG', name, L.tris([o]), tuple(round(v, 1) for v in mn), tuple(round(v, 1) for v in mx))
        ob = L.join(objs, name) if len(objs) > 1 else objs[0]
        ob.name = name; ob.data.name = name
        piv = Vector(piv)
        ob.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-piv)); ob.data.update()
        ob.location = piv * k
        made[name] = (ob, piv)
    for name, objs, piv, parent in groups:
        if parent:
            ob = made[name][0]
            ob.parent = made[parent][0]
            ob.location = (made[name][1] - made[parent][1]) * k
    keep = {v[0] for v in made.values()}
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o)
    t = L.tris(list(keep))
    print("EXPORT", os.path.basename(path), "tris", t, "nodes", [g[0] for g in groups])
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_vertex_color='MATERIAL',
                              use_selection=False, export_apply=False)
    return t


# ================= башня главного калибра (Ø 14 м, стволы 14 м) =================
TRUN = Vector((3.6, 0.0, 2.6))      # цапфы стволов
BY = 1.65                           # полуразнос стволов


def _gunhouse_pts(z0, z1, s=1.0):
    base = [(-6.6, 4.3), (-5.6, 5.0), (2.6, 5.0), (5.6, 3.2)]
    top = [(-6.4, 4.0), (-5.5, 4.6), (1.6, 4.5), (3.9, 2.9)]
    pts = []
    for (x, y) in base:
        pts += [(x * s, y * s, z0), (x * s, -y * s, z0)]
    for (x, y) in top:
        pts += [(x * s, y * s, z1), (x * s, -y * s, z1)]
    return pts


def _turret_parts():
    """Возвращает словарь групп деталей: body (поворот), guns (наклон), а также опорные точки."""
    body = [C((0, 0, 0.45), 6.4, 0.9, HULL_D, seg=56, w=0.12),
            H(_gunhouse_pts(0.9, 4.3), HULL, w=0.32)]
    # крыша — сурик, чуть утоплена в кромку
    roof = H([(x, y, z) for (x, y, z) in _gunhouse_pts(4.25, 4.4, 0.93) if z > 4.3] +
             [(x, y, 4.25) for (x, y, z) in _gunhouse_pts(4.25, 4.4, 0.93) if z > 4.3], RED, w=0.05)
    body.append(roof)
    # дальномер поперёк кормы крыши с бронеколпаками на концах
    body += [C((-4.6, 0, 4.95), 0.42, 10.6, HULL, seg=20, axis='Y', w=0.08)]
    for s in (1, -1):
        body += [B((-4.6, s * 5.35, 4.95), (1.3, 0.9, 1.3), HULL, w=0.18),
                 B((-4.0, s * 5.35, 5.05), (0.12, 0.62, 0.22), INSIDE, w=0.02)]
    # командирские башенки с перископами, люк, грибки вентиляции, рымы
    for s in (1, -1):
        body += [C((-2.3, s * 2.7, 4.6), 0.75, 0.55, HULL, seg=24, w=0.12),
                 C((-2.3, s * 2.7, 4.92), 0.55, 0.1, RED, seg=24, w=0.03),
                 B((-1.65, s * 2.7, 4.75), (0.22, 0.5, 0.3), HULL_D, w=0.04),
                 C((-5.6, s * 3.4, 4.55), 0.22, 0.4, HULL, seg=12),
                 C((-5.6, s * 3.4, 4.8), 0.34, 0.12, HULL, seg=12, w=0.04),
                 B((1.0, s * 3.9, 4.45), (0.35, 0.18, 0.2), HULL_D, w=0.04)]
    body += [B((-0.6, 0, 4.47), (1.4, 1.1, 0.1), LID, w=0.03),
             C((-1.3, 0, 4.5), 0.06, 1.1, HULL_D, seg=8, axis='Y')]
    # корма: дверь подачи боеприпасов, поручни-скобы
    body += [B((-6.62, 0, 2.4), (0.1, 2.2, 1.8), LID, w=0.03)]
    for z in (1.6, 2.4, 3.2):
        body.append(B((-6.7, 2.0, z), (0.12, 0.5, 0.08), HULL_D, w=0.02))
    # амбразуры в лобовом листе (тёмные проёмы)
    for s in (1, -1):
        body.append(B((4.62, s * BY, 2.6), (0.9, 1.15, 1.7), INSIDE, w=0.1))
    guns = []
    for s in (1, -1):
        y = s * BY
        guns += [B((4.75, y, 2.6), (1.0, 1.0, 1.3), HULL, w=0.25),                      # маска ствола
                 C((5.55, y, 2.6), 0.62, 0.7, RUBBER, seg=20, axis='X', w=0.1),            # чехол
                 C((7.0, y, 2.6), 0.52, 2.4, GUN, seg=20, axis='X', r2=0.46),              # казённая часть
                 C((13.1, y, 2.6), 0.44, 9.8, GUN, seg=20, axis='X', r2=0.32),             # ствол
                 C((18.3, y, 2.6), 0.36, 0.7, GUN, seg=20, axis='X', w=0.06)]             # дульное утолщение
    return body, guns


def _turret(broken=False):
    L.reset()
    body, guns = _turret_parts()
    if not broken:
        grime(body, 0.0, 2.5)
        return export([('turret', body, (0, 0, 0), None), ('guns', guns, TRUN, 'turret')],
                      battle('e_lev_turret'), REF['main_turret'])
    # --- взорванная башня ---
    keep = [o for o in body if alive(o)]
    roof = keep[2]
    bpy.data.objects.remove(roof)                       # крышу сорвало
    keep = [o for o in keep if alive(o)]
    gh = keep[1]
    # без крыши — рваный верх: пробоина во всю крышу и в правом борту, лепестки наружу
    c0 = Vector((-0.6, 0.8, 4.3))
    for o in keep[2:]:                                   # всё, что стояло на крыше в зоне взрыва, сорвано
        mn, mx = L.bounds([o])
        if mn.z > 4.2 and ((mn + mx) / 2 - c0).length < 3.2:
            bpy.data.objects.remove(o)
    keep = [o for o in keep if alive(o)]
    gh = keep[1]
    blast([gh], c0, 2.6, (0.1, 0.15, 1), 51, push=0.7)
    blast(keep[2:], c0, 2.6, (0.1, 0.15, 1), 51, hole=False)
    blast([gh], (-2.8, -4.9, 2.6), 1.5, (0, -1, 0.15), 52, push=0.6)
    blast([gh], (4.6, 2.2, 3.6), 1.0, (1, 0.3, 0.6), 53, hole=False, soot=3.0)
    # выгоревшее нутро (видно через пробоины), обломок казённика
    keep += [B((-1.5, 0, 2.5), (9.6, 7.6, 3.0), INSIDE, w=0.0),
             C((0.5, 0.9, 3.4), 0.5, 3.0, SOOT, seg=12, axis='X', rot=Matrix.Rotation(0.4, 3, 'Y'))]
    # правый (−y) бронеколпак дальномера сорван
    for o in keep:
        if alive(o):
            mn, mx = L.bounds([o])
            if mn.y < -4.7 and mx.y < -4.5 and mn.x < -3.9 and mx.x > -5.3 and mn.z > 4.2:
                bpy.data.objects.remove(o)
    keep = [o for o in keep if alive(o)]
    blast([keep[2]], (-4.6, -5.3, 4.95), 0.6, (0, -1, 0), 54, push=0.4, soot=2.0)
    # стволы: левый (+y) оторван у маски, обрубок рваный; правый вывернут вниз и вбок, с изломом
    for o in guns:
        bpy.data.objects.remove(o)
    y = BY
    wreck = [B((4.75, y, 2.6), (1.0, 1.0, 1.3), HULL, w=0.25),
             pipe((5.3, y, 2.6), (8.6, y + 0.15, 2.45), 0.52, 0.47, GUN, jag=0.9, seed=55, flare=0.25)]
    y = -BY
    a = Vector((5.3, y, 2.6)); b = Vector((10.8, y - 1.6, 1.25)); e = Vector((14.6, y - 3.9, -0.15))
    wreck += [B((4.85, y, 2.45), (1.0, 1.0, 1.3), HULL, w=0.25, rz=math.radians(-12)),
              pipe(a, b, 0.5, 0.44, GUN, seed=56),
              pipe(b, e, 0.43, 0.38, GUN, jag=0.35, seed=57, flare=0.2),
              S(b, 0.47, GUN, seg=14)]
    blast(wreck[-2:], b, 0.45, (0.3, -0.5, 0.8), 58, hole=False, soot=2.2, heat=True)
    # оторванный кусок ствола лежит на площадке, крыша — сорванным листом у борта, обломки
    deb = [pipe((3.2, 6.6, 0.42), (7.6, 4.0, 0.42), 0.44, 0.40, GUN, jag=0.5, seed=59, flare=0.2),
           plate((-4.6, 5.7, 0.9), 4.6, 3.2, RED, 60, bend=35, t=0.12, tilt=(22, 0, 70)),
           plate((-7.0, -2.5, 0.25), 1.6, 1.1, HULL, 61, bend=40, tilt=(10, 15, 20)),
           B((-6.8, -5.3, 0.55), (1.2, 0.9, 1.1), HULL, w=0.15, rz=0.7)]
    rr = random.Random(62)
    for i in range(9):
        a_ = rr.uniform(0, 6.28); d = rr.uniform(5.2, 7.0)
        deb.append(chunk((math.cos(a_) * d, math.sin(a_) * d, 0.0), rr.uniform(0.25, 0.6), rr.choice([HULL, HULL_D, RED, SOOT]), 63 + i))
    deb += [scorch((0.5, 0.6, 0.0), 4.4, 70, z=0.02), scorch((5.0, 4.4, 0.0), 1.4, 71, z=0.03)]
    grime(keep + wreck, 0.0, 2.5, 0.72)
    return export([('turret', keep + wreck + deb, (0, 0, 0), None)], battle('e_lev_turret_broken'), REF['main_turret'])


# ================= пусковая (8 контейнеров под крышками) =================
CELLS = [(-2.85 + 1.9 * i, s * 1.55) for s in (1, -1) for i in range(4)]   # lid_0…3 — левый борт (+y), 4…7 — правый
LID_Z = 1.62
CW, CH = 1.5, 1.35                                                          # проём контейнера


def _launcher_base(broken_cells=()):
    o = [H([(sx * 4.3, sy * 3.3, 0) for sx in (1, -1) for sy in (1, -1)] +
           [(sx * 4.05, sy * 3.05, 1.2) for sx in (1, -1) for sy in (1, -1)], HULL, w=0.12)]
    # рама настила вокруг проёмов (проёмы открыты в колодцы контейнеров)
    xs = sorted({x for x, _ in CELLS})
    edges_x = [-4.0] + [(xs[i] + xs[i + 1]) / 2 for i in range(3)] + [4.0]
    for i, ex in enumerate(edges_x):
        if 0 < i < 4:
            o.append(B((ex, 0, 1.4), (0.4, 6.1, 0.4), DECK, w=0.04))
        else:
            o.append(B((math.copysign(3.92, ex), 0, 1.4), (0.66, 6.1, 0.4), DECK, w=0.04))
    yo = 1.55 + CH / 2
    for s in (1, -1):
        o.append(B((0, s * (yo + 0.41), 1.4), (8.1, 0.84, 0.4), DECK, w=0.04))
    o.append(B((0, 0, 1.45), (8.0, 2 * (1.55 - CH / 2), 0.5), HULL, w=0.06))   # газоотвод между рядами
    for i in range(7):
        o.append(B((-3.0 + i, 0, 1.71), (0.12, 0.42, 0.04), INSIDE, w=0.0))   # жалюзи газоотвода
    for k, (x, y) in enumerate(CELLS):
        if k in broken_cells:
            continue
        o += [B((x, y, 1.01), (CW, CH, 0.4), INSIDE, w=0.0),               # дно колодца — темно
              C((x, y, 1.18), 0.36, 0.42, MSL, seg=16, r2=0.05)]          # головной обтекатель ракеты в контейнере
    # торцы: шкаф управления (корма), коллектор орошения (нос), рымы
    o += [B((-4.55, 0, 0.8), (0.7, 4.6, 1.5), SUPER, w=0.1),
          B((-4.92, 1.2, 0.9), (0.06, 1.2, 1.0), LID, w=0.02),
          B((-4.92, -1.2, 0.9), (0.06, 1.2, 1.0), LID, w=0.02),
          C((4.45, 0, 0.55), 0.14, 5.4, HULL_D, seg=10, axis='Y'),
          C((4.45, 2.0, 0.85), 0.1, 0.6, HULL_D, seg=8), C((4.45, -2.0, 0.85), 0.1, 0.6, HULL_D, seg=8)]
    return o


def _lid(k):
    x, y = CELLS[k]
    s = 1 if y > 0 else -1
    hy = y + s * (CH / 2 + 0.12)                                       # шарнир — по внешней кромке
    p = [B((x, y + s * 0.02, LID_Z), (CW + 0.12, CH + 0.16, 0.1), LID, w=0.035),
         B((x, y, LID_Z + 0.07), (0.1, CH * 0.9, 0.06), LID, w=0.02),
         B((x, y, LID_Z + 0.07), (CW * 0.85, 0.1, 0.06), LID, w=0.02),
         B((x + CW * 0.36, y - s * 0.45, LID_Z + 0.06), (0.4, 0.04, 0.04), RED, w=0.0)]   # риска-указатель
    for dx in (-0.45, 0.45):
        p.append(C((x + dx, hy, LID_Z), 0.08, 0.36, HULL_D, seg=10, axis='X'))
    return p, (x, hy, LID_Z)


def _launcher(broken=False):
    L.reset()
    if not broken:
        base = _launcher_base()
        grime(base, 0.0, 1.0)
        groups = [('launcher', base, (0, 0, 0), None)]
        for k in range(len(CELLS)):
            p, piv = _lid(k)
            groups.append(('lid_%d' % k, p, piv, 'launcher'))
        return export(groups, battle('e_lev_launcher'), REF['launcher'])
    # --- разбитая: средние контейнеры левого ряда и один правого взорваны, крышки сорваны; 4 целых — стреляют ---
    gone = (1, 2, 5)
    base = _launcher_base(broken_cells=gone)
    blast(base, (-0.2, 1.5, 1.5), 1.75, (0, 0.3, 1), 81, push=0.75)
    blast(base, (-0.9, -1.6, 1.5), 1.0, (0, -0.4, 1), 82, push=0.6)
    blast(base, (1.0, 3.3, 0.7), 0.8, (0, 1, 0.2), 83, push=0.5)
    # колодцы взорванных — выгоревшие, разорванный контейнер торчит косо
    base += [B((-0.4, 1.5, 0.75), (3.8, 1.6, 0.6), INSIDE, w=0.0),
             B((-0.95, -1.55, 0.75), (1.6, 1.5, 0.6), INSIDE, w=0.0),
             pipe((0.9, 1.55, 0.6), (1.35, 2.2, 2.9), 0.62, 0.62, HULL_D, seg=14, jag=0.7, seed=84, flare=0.35)]
    groups = [('launcher', base, (0, 0, 0), None)]
    lost = []
    for k in range(len(CELLS)):
        p, piv = _lid(k)
        if k in gone:
            lost.append((k, p, piv))
        else:
            groups.append(('lid_%d' % k, p, piv, 'launcher'))
    # крышка 1 — вывернута на шарнире и погнута, 2 и 5 — сорваны: лежат на палубе у торца
    k, p, piv = lost[0]
    xf(p, rot_about(piv, 'X', -150))
    blast(p, (CELLS[1][0] + 0.4, 2.9, 1.95), 0.6, (0, 0.5, 1), 85, hole=False, soot=2.0)
    base += p
    for (k, p, piv), (c, rz, tl) in zip(lost[1:], [((5.6, 1.2, -0.12), 30, (12, 8)), ((5.3, -1.9, -0.18), -55, (-6, 4))]):
        x, y = CELLS[k]
        xf(p, Matrix.Translation(c) @ Matrix.Rotation(math.radians(rz), 4, 'Z') @ Matrix.Rotation(math.radians(tl[0]), 4, 'X')
           @ Matrix.Rotation(math.radians(tl[1]), 4, 'Y') @ Matrix.Translation((-x, -y, -LID_Z)))
        blast(p, (c[0] + 0.3, c[1], c[2]), 0.45, (0, 0, 1), 86 + k, hole=False, soot=2.2)
        base += p
    rr = random.Random(90)
    for i in range(7):
        base.append(chunk((rr.uniform(4.6, 6.2), rr.uniform(-3.0, 3.0), -0.3), rr.uniform(0.15, 0.35), rr.choice([HULL, LID, SOOT, MSL]), 91 + i))
    base += [scorch((-0.4, 1.0, 0.0), 2.6, 99, z=0.02)]
    grime(base, 0.0, 1.0, 0.72)
    return export(groups, battle('e_lev_launcher_broken'), REF['launcher'])


# ================= РЛС: решётчатая мачта и вращающаяся решётчатая антенна =================
ANT_Z = 9.4


def _lattice(z0, z1, a0, a1, levels, col, r=0.09):
    """Ферма из 4 стоек (квадрат a0 внизу → a1 вверху) с поясами и раскосами по граням."""
    o = []
    def pt(sx, sy, t):
        a = a0 + (a1 - a0) * t
        return (sx * a, sy * a, z0 + (z1 - z0) * t)
    corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    for sx, sy in corners:
        o.append(rod(pt(sx, sy, 0), pt(sx, sy, 1), r * 1.3, col, seg=8))
    ts = [i / levels for i in range(levels + 1)]
    for i, t in enumerate(ts):
        for k in range(4):
            a, b = corners[k], corners[(k + 1) % 4]
            if i > 0:
                o.append(rod(pt(*a, t), pt(*b, t), r, col, seg=6))
            if i < levels:
                o.append(rod(pt(*a, t), pt(*b, ts[i + 1]), r * 0.8, col, seg=5))
                o.append(rod(pt(*b, t), pt(*a, ts[i + 1]), r * 0.8, col, seg=5))
    return o


def _array(c, w, h, col, tilt=15.0, holes=0.0, seed=1):
    """Плоская решётчатая антенна (лицо — +X): рама, вертикали и горизонтали; holes — доля вырванных прутков."""
    r = random.Random(seed)
    o = []
    hw, hh = w / 2, h / 2
    for y in (-hw, hw):
        o.append(bar((0, y, -hh), (0, y, hh), 0.2, col))
    for z in (-hh, hh):
        o.append(bar((0, -hw, z), (0, hw, z), 0.2, col))
    o.append(bar((-0.35, -hw, 0), (-0.35, hw, 0), 0.24, col))          # хребтовая балка
    nv = int(w / 0.42)
    for i in range(1, nv):
        if r.random() >= holes:
            y = -hw + w * i / nv
            o.append(bar((0.05, y, -hh), (0.05, y, hh), 0.07, col))
    nh = int(h / 0.42)
    for j in range(1, nh):
        if r.random() >= holes:
            z = -hh + h * j / nh
            o.append(bar((0.12, -hw, z), (0.12, hw, z), 0.06, col))
    # облучатели — короткие штыри на лицевой стороне
    for i in range(0, nv, 2):
        for j in range(1, nh, 2):
            if r.random() >= holes:
                o.append(bar((0.1, -hw + w * i / nv, -hh + h * j / nh), (0.42, -hw + w * i / nv, -hh + h * j / nh), 0.05, col))
    xf(o, Matrix.Translation(c) @ Matrix.Rotation(math.radians(-tilt), 4, 'Y'))
    return o


def _radar_static(broken=False):
    o = [B((0, 0, 1.1), (4.4, 4.0, 2.2), SUPER, w=0.15),
         B((2.21, 0.9, 0.95), (0.05, 0.8, 1.5), LID, w=0.02),             # дверь
         B((0, 0, 2.27), (4.5, 4.1, 0.14), SUPER, w=0.04)]
    for s in (1, -1):                                                    # обтекатели на углах рубки
        o += [C((1.5, s * 1.45, 2.6), 0.22, 0.6, SUPER, seg=10),
              S((1.5, s * 1.45, 3.35), 0.62, DOME, seg=18, scale=(1, 1, 1.05)),
              C((1.5, s * 1.45, 2.95), 0.5, 0.12, SUPER, seg=18)]
    if not broken:
        o += _lattice(2.34, 8.6, 1.8, 0.75, 3, SUPER)
        o += [C((0, 0, 8.7), 1.5, 0.22, SUPER, seg=28, w=0.05)]
        for i in range(10):                                             # леер площадки
            a = 2 * math.pi * i / 10
            o.append(rod((math.cos(a) * 1.42, math.sin(a) * 1.42, 8.8), (math.cos(a) * 1.42, math.sin(a) * 1.42, 9.55), 0.035, SUPER, seg=4))
        for i in range(10):
            a0, a1 = 2 * math.pi * i / 10, 2 * math.pi * (i + 1) / 10
            o.append(rod((math.cos(a0) * 1.42, math.sin(a0) * 1.42, 9.55), (math.cos(a1) * 1.42, math.sin(a1) * 1.42, 9.55), 0.04, SUPER, seg=4))
        # рей с антеннами связи
        o += [rod((0.0, -2.8, 7.2), (0.0, 2.8, 7.2), 0.07, SUPER, seg=6)]
        for y in (-2.6, -1.6, 1.6, 2.6):
            o.append(rod((0, y, 7.2), (0, y, 8.6), 0.03, SUPER, seg=4))
    return o


def _antenna():
    o = [C((0, 0, ANT_Z - 0.15), 0.55, 0.5, SUPER, seg=20, w=0.06),
         C((0, 0, ANT_Z + 0.35), 0.38, 0.6, SUPER, seg=16),
         B((-0.4, 0, ANT_Z + 0.7), (1.0, 0.8, 0.4), SUPER, w=0.06)]
    arr = _array((0.0, 0, ANT_Z + 2.15), 7.4, 2.9, SUPER, tilt=15)
    # подкосы от опоры к раме, сверху — антенна опознавания
    for y in (-2.6, 2.6):
        o.append(rod((-0.4, y * 0.15, ANT_Z + 0.8), (-0.55, y, ANT_Z + 1.3), 0.06, SUPER, seg=5))
    o += arr + [bar((-0.75, -3.0, ANT_Z + 3.95), (-0.75, 3.0, ANT_Z + 3.95), 0.16, SUPER)]
    for i in range(7):
        y = -2.7 + i * 0.9
        o.append(bar((-0.75, y, ANT_Z + 3.95), (-0.45, y, ANT_Z + 3.95), 0.08, SUPER))
    return o


def _radar(broken=False):
    L.reset()
    if not broken:
        st = _radar_static()
        grime(st, 0.0, 1.5)
        return export([('radar', st, (0, 0, 0), None), ('antenna', _antenna(), (0, 0, ANT_Z), 'radar')],
                      battle('e_lev_radar'), REF['radar'])
    # --- разбитая: мачту переломило (верх завалился), антенна сорвана и лежит на рубке и площадке ---
    st = _radar_static(broken=True)
    st += _lattice(2.34, 4.6, 1.8, 1.42, 1, SUPER)
    # верхняя секция ферм — наклонена на 28° и с одной выбитой стойкой
    up = _lattice(4.6, 8.0, 1.42, 0.8, 2, SUPER)
    up = [b for i, b in enumerate(up) if i not in (1, 6, 7, 12)]
    xf(up, rot_about((1.42, 0, 4.6), 'Y', 28) @ rot_about((0, 0, 4.6), 'X', 6))
    st += up
    st += [pipe((-1.42, -1.42, 4.6), (-1.0, -1.25, 5.6), 0.12, 0.11, SUPER, seg=8, jag=0.3, seed=101, flare=0.4),
           pipe((-1.42, 1.42, 4.6), (-1.15, 1.2, 5.3), 0.12, 0.11, SUPER, seg=8, jag=0.3, seed=102, flare=0.4)]
    # площадка мачты — на вершине наклонной секции, перекошена
    pf = [C((0, 0, 8.1), 1.5, 0.22, SUPER, seg=28, w=0.05)]
    xf(pf, rot_about((1.42, 0, 4.6), 'Y', 28) @ rot_about((0, 0, 4.6), 'X', 6))
    blast(pf, Vector(pf[0].data.vertices[0].co), 0.9, (0, 0, 1), 103, push=0.5, soot=2.0)
    st += pf
    # антенна — сорвана: перекручена, половина прутков выбита, лежит наискось на рубке и палубе
    ant = _array((0, 0, 0), 7.4, 2.9, SUPER, tilt=0, holes=0.45, seed=104)
    for ob in ant:
        for v in ob.data.vertices:                                       # перекрут вдоль размаха и концы свисают с рубки
            a = v.co.y / 3.7 * math.radians(18)
            y, z = v.co.y, v.co.z
            v.co.x, v.co.z = v.co.x * math.cos(a) - z * math.sin(a), v.co.x * math.sin(a) + z * math.cos(a)
            v.co.x -= 0.28 * max(0.0, abs(y) - 2.0) ** 2 + 0.12 * math.sin(y * 1.3)
    xf(ant, Matrix.Translation((0.2, 0.1, 2.75)) @ Matrix.Rotation(math.radians(35), 4, 'Z') @ Matrix.Rotation(math.radians(-80), 4, 'Y'))
    st += ant
    # обтекатель левого угла разбит, рубка пробита, копоть, обломки
    domes = [o for o in st if alive(o) and abs(L.bounds([o])[0].z - 2.73) < 0.05 and L.bounds([o])[0].y > 0]
    blast(domes, (1.5, 1.6, 3.9), 0.55, (0.3, 0.3, 1), 105, push=0.5, soot=1.8)
    body = [st[0], st[2]]
    blast(body, (2.2, -1.0, 1.4), 0.8, (1, 0, 0.1), 106, push=0.5)
    blast(body, (0.4, 1.6, 2.3), 0.9, (0, 0.2, 1), 107, hole=False, soot=2.8)
    st += [B((0.1, 0, 1.1), (3.9, 3.5, 1.9), INSIDE, w=0.0)]
    rr = random.Random(108)
    for i in range(6):
        a_ = rr.uniform(0, 6.28); d = rr.uniform(2.4, 3.1)
        st.append(chunk((math.cos(a_) * d, math.sin(a_) * d, 0.0), rr.uniform(0.15, 0.3), rr.choice([SUPER, DOME, SOOT]), 109 + i))
    st += [scorch((1.6, -0.6, 0.0), 1.8, 116, z=0.02)]
    grime(st, 0.0, 1.5, 0.72)
    return export([('radar', st, (0, 0, 0), None)], battle('e_lev_radar_broken'), REF['radar'])


# ================= ЗСУ: многоствольный автомат в куполе с радиолокационным прицелом =================
ZTR = Vector((0.75, 0.0, 1.55))      # цапфы


def _zsu_dome():
    pts = []
    for (z, rx, ry, xo) in ((0.8, 1.45, 1.3, 0.0), (1.4, 1.55, 1.4, 0.05), (2.0, 1.3, 1.15, 0.0), (2.35, 0.85, 0.8, -0.15)):
        for i in range(20):
            a = 2 * math.pi * i / 20
            pts.append((xo + rx * math.cos(a), ry * math.sin(a), z))
    o = paint(L.hull(pts, None, 'p'), HULL)
    L.smooth([o], 38)
    return o


def _zsu_parts():
    ped = [C((0, 0, 0.35), 1.55, 0.7, HULL_D, seg=40, w=0.1),
           C((0, 0, 0.74), 1.62, 0.08, HULL_D, seg=40)]
    tur = [_zsu_dome(),
           B((1.35, 0, 1.55), (0.55, 0.62, 0.95), INSIDE, w=0.08),           # проём под автомат
           C((-0.55, 0, 2.45), 0.32, 0.3, HULL, seg=16),
           S((-0.55, 0, 2.85), 0.48, DOME, seg=18, scale=(1, 1, 0.9)),       # обтекатель прицела
           B((0.0, 0.95, 2.05), (0.5, 0.32, 0.36), HULL, w=0.06),            # оптический прицел
           B((0.24, 0.95, 2.05), (0.04, 0.22, 0.16), INSIDE, w=0.0),
           C((-1.25, 0, 1.0), 0.45, 0.06, RED, seg=16, axis='X', w=0.01),    # сурик — опознавательный круг на корме
           B((-0.3, -1.38, 1.3), (0.9, 0.06, 0.6), LID, w=0.02)]             # лючок
    gun = [C((1.15, 0, 1.55), 0.3, 1.0, GUN, seg=16, axis='X', w=0.05),       # кожух
           C((1.7, 0, 1.55), 0.24, 0.25, GUN, seg=16, axis='X')]
    for i in range(6):
        a = 2 * math.pi * i / 6
        gun.append(C((2.85, 0.14 * math.cos(a), 1.55 + 0.14 * math.sin(a)), 0.045, 2.3, GUN, seg=8, axis='X'))
    gun += [C((2.6, 0, 1.55), 0.24, 0.1, GUN, seg=16, axis='X'),
            C((3.85, 0, 1.55), 0.25, 0.16, GUN, seg=16, axis='X', w=0.03)]
    return ped, tur, gun


def _zsu(broken=False):
    L.reset()
    ped, tur, gun = _zsu_parts()
    if not broken:
        grime(ped + tur, 0.0, 1.2)
        return export([('zsu', ped, (0, 0, 0), None), ('turret', tur, (0, 0, 0.7), 'zsu'), ('gun', gun, ZTR, 'turret')],
                      battle('e_lev_zsu'), REF['zsu'])
    # --- разбитая: купол вскрыт взрывом, стволы веером вывернуты, один оторван, прицел разбит ---
    dome = tur[0]
    blast([dome], (0.1, 0.35, 2.3), 0.75, (0.1, 0.3, 1), 121, push=0.65)
    blast([dome], (0.5, -1.35, 1.35), 0.5, (0.2, -1, 0), 122, push=0.5)
    blast([tur[3]], (-0.55, 0.0, 3.2), 0.38, (0, 0.2, 1), 123, push=0.5, soot=2.0)
    tur += [S((0.0, 0, 1.45), 1.1, INSIDE, seg=12, scale=(1.1, 1.0, 0.65))]
    for o in gun[2:8] + gun[9:]:
        bpy.data.objects.remove(o)
    gun = [g for g in gun if alive(g)]
    rr = random.Random(124)
    root = Vector((1.75, 0, 1.55))
    for i in range(5):
        a = 2 * math.pi * i / 6
        r0 = root + Vector((0, 0.14 * math.cos(a), 0.14 * math.sin(a)))
        d = Vector((1.0, math.cos(a) * rr.uniform(0.35, 0.8), math.sin(a) * rr.uniform(0.25, 0.7) - 0.25)).normalized()
        ln = rr.uniform(1.0, 2.2)
        gun.append(pipe(r0, r0 + d * ln, 0.05, 0.045, GUN, seg=8, jag=0.12 if ln < 1.7 else 0.0, seed=125 + i, flare=0.3))
    deb = [pipe((1.4, -2.0, 0.06), (2.8, -1.1, 0.06), 0.05, 0.045, GUN, seg=8, jag=0.1, seed=131),
           C((-1.9, -0.9, 0.08), 0.25, 0.16, GUN, seg=16),
           plate((-1.6, 1.6, 0.25), 1.1, 0.8, HULL, 132, bend=40, t=0.06, tilt=(15, 20, 40))]
    for i in range(5):
        a_ = rr.uniform(0, 6.28); d = rr.uniform(1.8, 2.4)
        deb.append(chunk((math.cos(a_) * d, math.sin(a_) * d, 0.0), rr.uniform(0.1, 0.22), rr.choice([HULL, DOME, SOOT]), 133 + i))
    deb += [scorch((0.6, 0.4, 0.0), 1.8, 140, z=0.02)]
    allp = ped + tur + gun
    xf(tur + gun, rot_about((0, 0, 0.7), 'Z', 18) @ rot_about((0, 0, 0.7), 'Y', -4))   # погон заклинило вкось
    grime(allp, 0.0, 1.2, 0.72)
    return export([('zsu', allp + deb, (0, 0, 0), None)], battle('e_lev_zsu_broken'), REF['zsu'])


def e_lev_turret():
    _turret(); _turret(True)


def e_lev_launcher():
    _launcher(); _launcher(True)


def e_lev_radar():
    _radar(); _radar(True)


def e_lev_zsu():
    _zsu(); _zsu(True)


# ================= корпус «Левиафана» (250 м) =================
SHIP_HULL = (0.37, 0.38, 0.395)
DECK_Z = 13.7                    # настил полётной палубы исходника
FC_Z = 18.0                      # бак (носовая надстройка под башни)
DECK_Y = (-17.0, 35.0)           # полоса текстуры настила поперёк корпуса


def _deck_image():
    """Текстура настила 2048×512 (вдоль × поперёк), sRGB: шаровое нескользящее покрытие с лёгкими пятнами,
    швами листов, следами вдоль полосы, разметка блёклая (белая и жёлтая), без знаков, номеров и техники."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
    W, Hh = 2048, 512
    rng = np.random.default_rng(7)
    def noise(sc):
        a = rng.random((max(2, Hh // sc), max(2, W // sc))).astype(np.float32)
        return np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((W, Hh), Image.BICUBIC), dtype=np.float32) / 255.0
    n = noise(64) * 0.45 + noise(16) * 0.3 + noise(4) * 0.15 + noise(1) * 0.1
    base = np.array(nat(DECK), dtype=np.float32)
    k = 0.9 + 0.2 * n
    img = np.stack([base[i] * k for i in range(3)], -1)
    def px(x, y):
        return (x + 125.0) / 250.0 * W, (y - DECK_Y[0]) / (DECK_Y[1] - DECK_Y[0]) * Hh
    lay = Image.new('L', (W, Hh), 0); d = ImageDraw.Draw(lay)          # швы листов: тёмные
    for x in np.arange(-125, 125, 4.0):
        d.line([px(x, DECK_Y[0]), px(x, DECK_Y[1])], fill=60, width=1)
    for y in np.arange(DECK_Y[0], DECK_Y[1], 2.5):
        d.line([px(-125, y), px(125, y)], fill=40, width=1)
    seams = np.asarray(lay, dtype=np.float32) / 255.0
    img *= (1 - 0.12 * seams)[..., None]
    # следы колёс и выхлопа вдоль полосы — тёмная полоса с вытянутыми пятнами
    streak = np.asarray(Image.fromarray((rng.random((Hh // 4, W // 64)) * 255).astype(np.uint8)).resize((W, Hh), Image.BICUBIC), dtype=np.float32) / 255.0
    yy = (np.arange(Hh)[:, None] / Hh) * (DECK_Y[1] - DECK_Y[0]) + DECK_Y[0]
    band = np.exp(-((yy - 17.0) / 4.5) ** 2)
    img *= (1 - 0.18 * band * streak)[..., None]
    # разметка: белая (блёклая) и жёлтая; рисуется маской, краска чуть «стёрта» шумом
    white = Image.new('L', (W, Hh), 0); yel = Image.new('L', (W, Hh), 0)
    dw, dy = ImageDraw.Draw(white), ImageDraw.Draw(yel)
    for x in np.arange(-120, 42, 9.0):                                  # осевая полосы — пунктир
        dw.line([px(x, 17.0), px(x + 5.0, 17.0)], fill=255, width=4)
    for y in (8.5, 25.5):                                               # кромки полосы
        dw.line([px(-121, y), px(42, y)], fill=255, width=3)
    for (x0, y0, x1, y1) in ((-74.0, -11.5, -60.0, 0.0), (-104.0, -10.0, -90.0, 0.5)):   # подъёмники — жёлтая рамка
        dy.rectangle([px(x0, y0), px(x1, y1)], outline=255, width=3)
    for x in np.arange(-110, 40, 22.0):                                 # места стоянки — короткие жёлтые «скобы»
        dy.line([px(x, 2.0), px(x, 6.5)], fill=255, width=3)
    wear = 0.55 + 0.45 * noise(2)
    wm = np.asarray(white.filter(ImageFilter.GaussianBlur(0.6)), dtype=np.float32) / 255.0 * wear
    ym = np.asarray(yel.filter(ImageFilter.GaussianBlur(0.6)), dtype=np.float32) / 255.0 * wear
    wc = np.array(nat((0.66, 0.66, 0.63)), dtype=np.float32); yc = np.array(nat((0.66, 0.56, 0.26)), dtype=np.float32)
    img = img * (1 - wm[..., None] * 0.8) + wc * (wm[..., None] * 0.8)
    img = img * (1 - ym[..., None] * 0.75) + yc * (ym[..., None] * 0.75)
    # точки крепления (рымы в настиле) — сетка тёмных точек
    dots = Image.new('L', (W, Hh), 0); dd = ImageDraw.Draw(dots)
    for x in np.arange(-121, 124, 3.0):
        for y in np.arange(DECK_Y[0] + 1, DECK_Y[1], 3.0):
            if not (6.0 < y < 28.0 and x < 44):
                X, Y = px(x, y); dd.ellipse([X - 1, Y - 1, X + 1, Y + 1], fill=255)
    img *= (1 - 0.25 * np.asarray(dots, dtype=np.float32) / 255.0)[..., None]
    img = np.clip(img, 0, 1)
    im = bpy.data.images.new('fh_lev_deck', W, Hh, alpha=True)
    a = np.ones((Hh, W, 4), dtype=np.float32); a[..., :3] = img            # строка 0 — v = 0 (y = DECK_Y[0])
    im.pixels.foreach_set(a.ravel()); im.update(); im.pack()
    return im


def deck_mat():
    m = bpy.data.materials.get('fh_lev_deck')
    if m:
        return m
    m = bpy.data.materials.new('fh_lev_deck'); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = _deck_image()
    nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.92; b.inputs['Metallic'].default_value = 0.0
    return m


def _deck_uv(o, uvname, test):
    """Грани настила (test(центр, нормаль)) → материал настила и плоская развёртка сверху."""
    me = o.data
    if uvname not in me.uv_layers:
        me.uv_layers.new(name=uvname)
    uv = me.uv_layers[uvname]
    dm = deck_mat()
    if dm.name not in [m.name for m in me.materials if m]:
        me.materials.append(dm)
    di = [i for i, m in enumerate(me.materials) if m and m.name == dm.name][0]
    n = 0
    for p in me.polygons:
        if test(p.center, p.normal):
            p.material_index = di; n += 1
            for li in p.loop_indices:
                v = me.vertices[me.loops[li].vertex_index].co
                uv.data[li].uv = ((v.x + 125.0) / 250.0, (v.y - DECK_Y[0]) / (DECK_Y[1] - DECK_Y[0]))
    return n


def e_leviathan():
    import numpy as np
    L.reset()
    o = L.load(os.path.join(SRC, 'B-3_carrier.glb'))
    L.place(o, bow='-y', length=LEV_LEN)
    L.xform(o, Matrix.Translation((0, 13.0, -9.0)))   # ось корпуса — на y = 0, ватерлиния — z = 0 (как в PR #190)
    # вертолёты (Object_3) и самолёты (Object_5) исходника — целиком; палубная разметка исходника — полосами-сетками
    o = L.drop(o, names=('Object_3', 'Object_5'))
    o = L.kill_faces(o, lambda c, n: c.x > 42 and c.z > LEV_DECK + 1.2)     # нос: пусковые и артустановки исходника
    o = L.kill_faces(o, lambda c, n: c.x < -70 and c.z > LEV_DECK + 0.8)    # корма: стоянка самолётов
    o = L.kill_faces(o, lambda c, n: c.z > 35.0)                            # мачта с куполами
    o = L.kill_parts(o, lambda mn, mx, k: mn.z > DECK_Z - 0.2 and mx.z < DECK_Z + 0.35 and min(mx.x - mn.x, mx.y - mn.y) < 1.6)
    o = L.kill_parts(o, lambda mn, mx, k: (mx - mn).length < 0.9)           # мелочь, слипшаяся в комки
    L.matte(o, 0.9)
    for m in L.mats(o):                     # краска исходника → шаровая, без цвета (рыжая палуба, номера, знаки)
        t = L.tex_of(m)
        if t:
            L.regrade(t, nat(SHIP_HULL), keep=0.55, lo=0.55, hi=1.35)
    uvname = o[0].data.uv_layers[0].name if o[0].data.uv_layers else 'UVMap'
    nd = 0
    for ob in o:                            # настил полётной палубы — своя чистая текстура
        nd += _deck_uv(ob, uvname, lambda c, n: n.z > 0.92 and (abs(c.z - DECK_Z) < 0.5 or (c.x > 40 and DECK_Z - 0.5 < c.z < FC_Z + 0.5)))
    print('DBG deck faces', nd)
    print('DBG src tris', L.tris(o))
    L.planar(o, 0.5)                                  # слить плоские грани — форма та же, треугольников меньше
    print('DBG src tris planar', L.tris(o))
    for ob in o:
        _col(ob)
        for d in ob.data.color_attributes['Col'].data:
            d.color = (1, 1, 1, 1)
    # --- свои надстройки: бак под башни, барбет, погреб, спонсоны ЗСУ, площадки гнёзд, труба ---
    add = []
    sec = [(42, 11.5), (60, 11.3), (80, 10.3), (98, 8.7), (112, 7.0)]
    pts = [(x, s * w, DECK_Z - 0.2) for x, w in sec for s in (1, -1)] + [(x - (1.2 if x == 42 else 0), s * (w - 0.9), FC_Z) for x, w in sec for s in (1, -1)]
    fc = H(pts, SHIP_HULL, w=0.35, seg=2)
    add.append(fc)
    add.append(C((74, 0, (FC_Z + LEV_DECK + 6.0) / 2), 8.5, LEV_DECK + 6.0 - FC_Z, SHIP_HULL, seg=56, w=0.25))
    add.append(B((52, 0, FC_Z + 1.0), (12, 6, 2.0), SHIP_HULL, w=0.25))
    for kind, (x, y, z), yaw in SOCKETS:
        r = {'main_turret': 7.5, 'launcher': 4.6, 'radar': 3.2, 'zsu': 2.6}[kind]
        sg = 56 if r > 4 else 40
        add += [C((x, y, z - 0.15), r, 0.3, PAD, seg=sg),
                paint(L.ring((x, y, z - 0.3), r + 0.45, r, 0.42, None, 'p', seg=sg), HULL_D)]
        if kind == 'zsu':
            sd = 1 if y > 0 else -1
            add.append(B((x, y + sd * 1.0, LEV_DECK - 0.3), (8, 7, 1.2), SHIP_HULL, w=0.2))
            for dx in (-3.0, 3.0):                                     # кницы под спонсоном
                add.append(H([(x + dx - 0.2, y + sd * 4.4, LEV_DECK - 0.95), (x + dx + 0.2, y + sd * 4.4, LEV_DECK - 0.95),
                              (x + dx - 0.2, y - sd * 2.4, LEV_DECK - 0.95), (x + dx + 0.2, y - sd * 2.4, LEV_DECK - 0.95),
                              (x + dx - 0.2, y - sd * 2.4, LEV_DECK - 5.0), (x + dx + 0.2, y - sd * 2.4, LEV_DECK - 5.0)], SHIP_HULL, w=0.05))
    # вторая труба у кормы рубки — наклонный овальный кожух с тёмным срезом
    isl_y = -6.25
    tp = []
    for z, sx, sy, dx in ((LEV_DECK + 0.5, 5.2, 3.2, 0.0), (LEV_DECK + 9.0, 4.6, 2.9, -1.2), (LEV_DECK + 13.2, 4.2, 2.6, -1.9)):
        for i in range(20):
            a = 2 * math.pi * i / 20
            tp.append((-30 + dx + sx * math.cos(a), isl_y + sy * math.sin(a), z))
    fn = paint(L.hull(tp, None, 'p'), SUPER); L.smooth([fn], 40)
    add += [fn, C((-31.9, isl_y, LEV_DECK + 13.5), 2.3, 0.7, SOOT, seg=24, rot=Matrix.Rotation(0.0, 3, 'Z')),
            B((-27.0, isl_y, LEV_DECK + 6.0), (0.08, 4.0, 3.0), LID, w=0.0)]
    for x in (-33.5, -30.5):
        add.append(C((x, isl_y, LEV_DECK + 13.95), 0.45, 0.6, HULL_D, seg=12))
    grime(add, LEV_DECK - 1.0, 3.0, 0.85)
    for ob in add:                                   # верх бака и барбета — тоже настил
        _deck_uv(ob, uvname, lambda c, n: n.z > 0.92 and (abs(c.z - FC_Z) < 0.3 or abs(c.z - LEV_DECK - 6.0) < 0.3) and c.x > 40)
    print('DBG add tris', L.tris(add))
    o += add
    ob = L.join(o, 'body')
    print('TRIS hull', L.tris([ob]))
    L.shrink(2048)
    ob.data.transform(Matrix.Scale(1.0 / LEV_LEN, 4)); ob.data.update()
    print("EXPORT fh_battle_e_leviathan.glb tris", L.tris([ob]), "mats", len(ob.data.materials))
    bpy.ops.export_scene.gltf(filepath=battle('e_leviathan'), export_format='GLB', export_yup=True, export_image_format='JPEG',
                              export_jpeg_quality=88, export_vertex_color='MATERIAL', use_selection=False)
    write_sockets()


def write_sockets():
    k = 1.0 / LEV_LEN
    out = []
    for kind, (x, y, z), yaw in SOCKETS:
        out.append({'kind': kind, 'm': [x, y, z], 'yaw_deg': yaw,
                    'norm': [round(x * k, 4), round(z * k, 4), round(-y * k, 4)]})
    path = os.path.join(OUT, 'biome2', 'leviathan_sockets.json')
    print('SOCKETS', len(out))
    with open(path, 'w') as f:
        json.dump({'model': 'res://models/battle/fh_battle_e_leviathan.glb', 'length_m': LEV_LEN,
                   'note': 'm — метры в модели (x вперёд, y влево, z вверх от воды); norm — в единицах модели glTF (длина 1): x, y вверх, z; '
                           'part_m — длина 1 модели части в метрах (масштаб части к корпусу = part_m / length_m); '
                           'начало координат части — центр гнезда',
                   'part_m': REF,
                   'sockets': out}, f, ensure_ascii=False, indent=1)


RECIPES = {f.__name__: f for f in [e_leviathan, e_lev_turret, e_lev_launcher, e_lev_radar, e_lev_zsu]}

if __name__ == '__main__':
    names = [a for a in A if not a.startswith('--')]
    for n in (RECIPES if names == ['all'] else names):
        RECIPES[n]()
