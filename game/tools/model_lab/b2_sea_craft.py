# Морская техника «Архипелага» кодом (замечания Kanta 19.10): катер ПВО «Скат», экраноплан «Крачка»,
# гидросамолёт «Буревестник», дрон «Чайка». Модели собираются целиком из гладких тел (лофт по сечениям,
# тела вращения, профилированные крылья и лопасти, скруглённые коробки), без исходников Sketchfab.
#   python3 -I game/tools/model_lab/b2_sea_craft.py <e_ship_aa|e_ekranoplan|e_seaplane|e_drone_sea|all> [--out=game/models]
# (biome2_models.py вызывает эти же рецепты по прежним именам.)
# Оси как в b2lib: нос +X, левый борт +Y, верх +Z, метры; ватерлиния (у самолётов — что угодно, центр по высоте) z = 0.
# Окраска — «натуральная» (Kanta 19.10): матовая (roughness ≥ 0,88), без металла, приглушённые выгоревшие цвета,
# снизу грязнее; яркость ≤ 0,72.
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
import b2lib as L

A = sys.argv[1:]
OPT = dict(x[2:].split('=', 1) for x in A if x.startswith('--') and '=' in x)
MODELS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'models'))
OUT = OPT.get('out', MODELS)


def battle(name):
    return os.path.join(OUT, 'battle', 'fh_battle_%s.glb' % name)


# ---------- палитра (sRGB): флот противника — серый «шаровый», красные метки врага приглушены ----------
NAVY = (0.40, 0.42, 0.43)        # борт и надстройки
NAVY_LT = (0.47, 0.49, 0.50)     # надстройки светлее (выгорели)
NAVY_DK = (0.31, 0.33, 0.34)     # борт у воды, в потёках
DECK = (0.26, 0.27, 0.27)        # палуба (противоскользящая, тёмная)
BOOT = (0.13, 0.13, 0.13)        # ватерлинийная полоса
ANTIFOUL = (0.36, 0.20, 0.17)    # подводная часть, суриком
GUNMETAL = (0.24, 0.25, 0.26)
RED = (0.58, 0.21, 0.16)         # метка врага: крыши башен, коки, законцовки
GLASS = (0.10, 0.12, 0.14)
SOOT = (0.27, 0.27, 0.27)
AIR_UP = (0.36, 0.39, 0.41)      # самолёты: верх тёмно-серый морской
AIR_LO = (0.50, 0.52, 0.52)      # низ светлее
FLOAT_LO = (0.34, 0.35, 0.35)    # низ поплавков и днище — в грязи и потёках
INTAKE = (0.07, 0.07, 0.08)


def M(name, rgb, rough=0.9, metal=0.0):
    return L.flat('fhs_' + name, rgb, rough, metal)


# ---------- сборка сеток ----------

def _obj(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate(); me.update()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    if mat:
        me.materials.append(mat)
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    return o


def _is_pt(r):
    return isinstance(r[0], (int, float))


def loft(rings, mat, name='loft', smooth=40, cap0=True, cap1=True):
    """Тело по кольцам одинаковой длины; кольцо из одной точки (x, y, z) — полюс (острый нос/хвост)."""
    verts, faces, idx = [], [], []
    for r in rings:
        if _is_pt(r):
            idx.append(len(verts)); verts.append(r)
        else:
            idx.append(list(range(len(verts), len(verts) + len(r)))); verts += list(r)
    for a, b in zip(idx, idx[1:]):
        if isinstance(a, int) and isinstance(b, int):
            continue
        if isinstance(a, int):
            n = len(b); faces += [(a, b[(i + 1) % n], b[i]) for i in range(n)]
        elif isinstance(b, int):
            n = len(a); faces += [(a[i], a[(i + 1) % n], b) for i in range(n)]
        else:
            n = len(a); faces += [(a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]) for i in range(n)]
    if cap0 and not isinstance(idx[0], int):
        faces.append(tuple(reversed(idx[0])))
    if cap1 and not isinstance(idx[-1], int):
        faces.append(tuple(idx[-1]))
    o = _obj(name, verts, faces, mat)
    if smooth:
        L.smooth([o], smooth)
    return o


def se_ring(x, ry, rz_top, rz_bot, zc=0.0, n=24, p=2.0, pb=None, yc=0.0):
    """Сечение-суперэллипс в плоскости YZ: верх с показателем p (больше — «коробчатее»), низ — pb (меньше 2 — килем)."""
    pb = pb or p
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        e = 2.0 / (p if s >= 0 else pb)
        y = yc + ry * math.copysign(abs(c) ** e, c)
        z = zc + (rz_top if s >= 0 else rz_bot) * math.copysign(abs(s) ** e, s)
        pts.append((x, y, z))
    return pts


def catmull(keys, n_between=2):
    """Сгладить ряд станций (кортежей чисел) кривой Катмулла–Рома: между соседними — n_between промежуточных."""
    out = []
    for i in range(len(keys) - 1):
        p0 = keys[max(0, i - 1)]; p1 = keys[i]; p2 = keys[i + 1]; p3 = keys[min(len(keys) - 1, i + 2)]
        for k in range(n_between + 1):
            t = k / (n_between + 1)
            out.append(tuple(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3)
                             for a, b, c, d in zip(p0, p1, p2, p3)))
    out.append(keys[-1])
    return out


def lathe(prof, mat, name='lathe', seg=20, c=(0, 0, 0), axis='X', sq=(1.0, 1.0), smooth=40):
    """Тело вращения: prof — [(s, r)] вдоль оси от c; r = 0 — полюс. sq — сплющивание сечения."""
    c = Vector(c); rings = []
    for s, r in prof:
        if r <= 1e-6:
            p = {'X': (s, 0, 0), 'Y': (0, s, 0), 'Z': (0, 0, s)}[axis]
            rings.append(tuple(c + Vector(p)))
            continue
        ring = []
        for i in range(seg):
            t = 2 * math.pi * i / seg
            a, b = r * sq[0] * math.cos(t), r * sq[1] * math.sin(t)
            p = {'X': (s, a, b), 'Y': (a, s, b), 'Z': (a, b, s)}[axis]
            ring.append(tuple(c + Vector(p)))
        rings.append(ring)
    return loft(rings, mat, name, smooth)


def tube(path, r, mat, name='tube', seg=6, smooth=60):
    """Труба по ломаной (поручни, растяжки)."""
    rings = []
    for i, p in enumerate(path):
        p = Vector(p)
        a = Vector(path[max(0, i - 1)]); b = Vector(path[min(len(path) - 1, i + 1)])
        t = (b - a).normalized()
        up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        u = t.cross(up).normalized(); v = t.cross(u)
        rings.append([tuple(p + (u * math.cos(2 * math.pi * k / seg) + v * math.sin(2 * math.pi * k / seg)) * r) for k in range(seg)])
    return loft(rings, mat, name, smooth)


AF_CACHE = {}


def airfoil(n=10, t=0.12):
    """Симметричный профиль NACA 00xx: замкнутый контур (u — доля хорды от носка, v — толщина в долях хорды)."""
    key = (n, t)
    if key not in AF_CACHE:
        xs = [(1 - math.cos(math.pi * i / n)) / 2 for i in range(n + 1)]
        yt = lambda x: 5 * t * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)
        up = [(x, max(yt(x), 0.004 * t)) for x in reversed(xs)]
        lo = [(x, -yt(x)) for x in xs[1:-1]]
        AF_CACHE[key] = up + lo
    return AF_CACHE[key]


def surface(stations, mat, name='wing', n=10, smooth=38, chord_dir=(-1, 0, 0), thick_dir=(0, 0, 1), round_tip=True):
    """Крыло / киль / лопасть по станциям: [(носок (x,y,z), хорда, отн. толщина)]. Хорда — вдоль chord_dir,
    толщина — вдоль thick_dir. round_tip — на конце ещё тонкое кольцо: законцовка скруглена, а не обрублена."""
    cd = Vector(chord_dir).normalized(); td = Vector(thick_dir).normalized()
    st = list(stations)
    if round_tip and len(st) > 1:
        (p1, c1, t1), (p0, c0, t0) = st[-1], st[-2]
        span = (Vector(p1) - Vector(p0)); sd = span - cd * span.dot(cd) - td * span.dot(td)
        sd = sd.normalized() if sd.length > 1e-6 else Vector((0, 1, 0))
        st.append((tuple(Vector(p1) + cd * c1 * 0.06 + sd * c1 * t1 * 0.9), c1 * 0.88, t1 * 0.45))
    rings = []
    for p, c, t in st:
        p = Vector(p)
        rings.append([tuple(p + cd * (u * c) + td * (v * c)) for u, v in airfoil(n, t)])
    return loft(rings, mat, name, smooth)


def rbox(c, size, mat, name='rbox', r=0.1, seg=3, rot=None):
    """Коробка со скруглёнными рёбрами (фаска в seg сегментов) и взвешенными нормалями — без «рубленых» углов."""
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    r = min(r, 0.49 * min(size))
    bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=r, segments=seg, profile=0.5, affect='EDGES',
                    clamp_overlap=True)
    if rot is not None:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    o = L._new(name, bm, mat)
    L.smooth([o], 60); wnormals(o)
    return o


def rhull(pts, mat, name='rhull', r=0.1, seg=3):
    """Выпуклая оболочка точек со скруглёнными рёбрами — надстройки, рубки, щиты."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(p)) for p in pts]
    bmesh.ops.convex_hull(bm, input=vs)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharp = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0) > math.radians(20)]
    bmesh.ops.bevel(bm, geom=sharp + list({v for e in sharp for v in e.verts}), offset=r, segments=seg, profile=0.5,
                    affect='EDGES', clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = L._new(name, bm, mat)
    L.smooth([o], 60); wnormals(o)
    return o


def wnormals(o):
    """Взвешенные нормали: плоские грани остаются ровными, свет «течёт» только по фаскам."""
    m = o.modifiers.new('wn', 'WEIGHTED_NORMAL'); m.keep_sharp = True; m.mode = 'FACE_AREA'; m.weight = 50
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.modifier_apply(modifier='wn')


def paint(o, fn):
    """Раскраска по зонам: fn(центр грани, нормаль) → материал или None (оставить)."""
    names = [m.name for m in o.data.materials]
    for p in o.data.polygons:
        m = fn(p.center, p.normal)
        if m is None:
            continue
        if m.name not in names:
            o.data.materials.append(m); names.append(m.name)
        p.material_index = names.index(m.name)


def xf(objs, m):
    for o in (objs if isinstance(objs, (list, tuple)) else [objs]):
        o.data.transform(m); o.data.update()
    return objs


def mirror_y(objs):
    """Копии с зеркалом по Y (левый борт → правый)."""
    out = []
    for o in objs:
        c = o.copy(); c.data = o.data.copy(); bpy.context.scene.collection.objects.link(c)
        c.data.transform(Matrix.Scale(-1, 4, Vector((0, 1, 0)))); c.data.flip_normals(); c.data.update()
        out.append(c)
    return out


def prop(center, R, blades, mat_blade, mat_spinner, name='prop', pusher=False, spinner_len=None, r_hub=None,
         chord=None, phase=0.0, n=6):
    """Воздушный винт: кок и отдельные лопасти (между ними — зазор у комля, кок их не слепляет).
    Ось — X, тянущий винт смотрит коком в +X, толкающий (pusher) — в −X."""
    r_hub = r_hub or R * 0.2
    sl = spinner_len or r_hub * 2.6
    chord = chord or R * 0.22
    sp = lathe([(sl * 0.95, 0), (sl * 0.88, r_hub * 0.38), (sl * 0.7, r_hub * 0.72), (sl * 0.45, r_hub * 0.93),
                (sl * 0.15, r_hub), (-sl * 0.12, r_hub), (-sl * 0.12, 0)], mat_spinner, name + '_spinner', seg=16, c=(0, 0, 0))
    parts = [sp]
    r0 = r_hub * 0.75
    for k in range(blades):
        st = []
        for i in range(n):
            f = i / (n - 1)
            r = r0 + (R - r0) * f
            c = chord * (0.55 + 0.75 * math.sin(math.pi * min(1.0, f * 1.15 + 0.12)) * 0.6) * (1.0 - 0.45 * f * f)
            pitch = math.radians(58 - 40 * f)
            cdir = Vector((-math.sin(pitch), math.cos(pitch), 0))   # хорда — почти в плоскости вращения
            le = Vector((0, 0, r)) - cdir * (c * 0.35) + Vector((sl * 0.02, 0, 0))
            st.append((tuple(le), c, 0.16 - 0.09 * f, cdir))
        rings = []
        for i, (p, c, t, cdir) in enumerate(st):
            tdir = Vector((math.cos(math.radians(58 - 40 * i / (n - 1))), math.sin(math.radians(58 - 40 * i / (n - 1))), 0))
            rings.append([tuple(Vector(p) + cdir * (u * c) + tdir * (v * c)) for u, v in airfoil(6, t)])
        tip = Vector((0, 0, R + chord * 0.12)) + Vector((sl * 0.02, 0, 0))
        rings.append(tuple(tip))
        b = loft(rings, mat_blade, name + '_blade', 50)
        xf(b, Matrix.Rotation(phase + 2 * math.pi * k / blades, 4, 'X'))
        parts.append(b)
    if pusher:
        xf(parts, Matrix.Scale(-1, 4, Vector((1, 0, 0))))
        for o in parts:
            o.data.flip_normals()
    xf(parts, Matrix.Translation(Vector(center)))
    return parts


def finish(objs, name, center=False, budget=15000):
    """Склеить (нормали деталей сохраняются), длина по X = 1, записать GLB (+Y вверх)."""
    objs = [o for o in objs if o.name in bpy.data.objects and o.type == 'MESH' and len(o.data.polygons)]
    ob = L.join(objs, 'body')
    mn, mx = L.bounds([ob])
    # центр по X и Y в нуле; по высоте — ватерлиния z = 0 (корабли) или середина (самолёты, center)
    ob.data.transform(Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -(mn.z + mx.z) / 2 if center else 0.0)))
    ob.data.transform(Matrix.Scale(1.0 / (mx.x - mn.x), 4)); ob.data.update()
    for o in list(bpy.data.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    mn, mx = L.bounds([ob]); t = L.tris([ob])
    print("FINISH", name, "tris", t, "size", tuple(round(v, 3) for v in (mx - mn)), "min", tuple(round(v, 3) for v in mn),
          "mats", [m.name for m in ob.data.materials])
    assert t <= budget, "бюджет треугольников превышен: %d > %d" % (t, budget)
    bpy.ops.export_scene.gltf(filepath=battle(name), export_format='GLB', use_selection=False, export_yup=True)
    return ob


# ======================= В-1 катер ПВО «Скат» (30 м) =======================
# Ракетно-артиллерийский катер «по мотивам»: длинный бак со скулой, развал бортов к носу, острый форштевень,
# транец; на палубе — носовая и кормовая зенитные спарки в скруглённых башнях с красными крышами, рубка
# с ходовым мостиком и наклонными окнами, мачта с антенной РЛС, плотики, кнехты, леерное ограждение.

def _skat_stations():
    # x, полуширина, палуба z, киль z, показатель днища (меньше — острее килеватость)
    keys = [(-15.0, 3.15, 2.15, -0.70, 2.6), (-12.0, 3.42, 2.15, -1.05, 2.3), (-6.0, 3.55, 2.20, -1.20, 2.0),
            (0.0, 3.55, 2.28, -1.20, 1.85), (5.0, 3.42, 2.45, -1.15, 1.7), (9.0, 2.98, 2.66, -1.00, 1.55),
            (12.0, 2.20, 2.88, -0.70, 1.4), (14.0, 1.20, 3.04, -0.15, 1.3), (14.7, 0.5, 3.1, 0.3, 1.25), (15.0, 0.07, 3.12, 0.55, 1.25)]
    return catmull(keys, 3)


def _skat_hull(hull_m):
    rings = []
    for x, b, h, k, pb in _skat_stations():
        zc = 0.75
        # развал бортов к носу: верх шире ватерлинии (показатель верха больше у носа — скула мягче)
        rings.append(se_ring(x, b, h - zc, zc - k, zc, n=44, p=5.0, pb=pb))
    return loft(rings, hull_m, 'hull', 38)


def _gun_twin(x, y, z, rz, body, roof, gun, name):
    """Зенитная спарка: башня-купол, красная крыша, два ствола с кожухами и дульными тормозами."""
    tur = lathe([(0.0, 0), (0.0, 1.18), (0.25, 1.2), (0.85, 1.12), (1.15, 0.98), (1.35, 0.72), (1.45, 0.35), (1.48, 0)],
                body, name, seg=28, c=(0, 0, 0), axis='Z')
    paint(tur, lambda c, n: roof if n.z > 0.55 else None)
    base = lathe([(-0.2, 0), (-0.2, 1.3), (0.05, 1.3), (0.05, 0)], gun, name + '_ring', seg=28, axis='Z')
    parts = [tur, base, rbox((0.95, 0, 0.75), (0.5, 1.3, 0.62), body, name + '_mantlet', r=0.18)]
    for off in (-0.33, 0.33):
        parts += [lathe([(0.9, 0), (0.9, 0.17), (1.9, 0.17), (2.0, 0.11), (3.7, 0.085), (3.7, 0.12), (4.05, 0.12), (4.05, 0)],
                        gun, name + '_gun', seg=10, c=(0, off, 0.78))]
    xf(parts, Matrix.Rotation(rz, 4, 'Z'))
    xf(parts, Matrix.Translation((x, y, z)))
    return parts


def e_ship_aa():
    L.reset()
    hull_m = M('aa_hull', NAVY)
    hull_dk = M('aa_hull_dk', NAVY_DK)
    deck_m = M('aa_deck', DECK)
    sup = M('aa_super', NAVY_LT)
    boot = M('aa_boot', BOOT)
    anti = M('aa_antifoul', ANTIFOUL)
    red = M('red', RED)
    gun = M('gun', GUNMETAL)
    glass = M('glass', GLASS, 0.5)
    raft = M('aa_raft', (0.50, 0.48, 0.44))
    soot = M('soot', SOOT)

    hull = _skat_hull(hull_m)
    paint(hull, lambda c, n: anti if c.z < -0.05 else boot if c.z < 0.32 else hull_dk if c.z < 1.0 and n.z < 0.5
          else deck_m if n.z > 0.82 else None)
    o = [hull]
    # бак: невысокий волнолом перед носовой башней (V-образный щит)
    for sd in (-1, 1):
        o.append(rhull([(9.5, 0, 2.62), (9.5, 0, 3.3), (8.25, sd * 1.95, 2.55), (8.25, sd * 1.95, 3.1),
                        (9.32, 0, 2.62), (9.32, 0, 3.3), (8.08, sd * 1.82, 2.55), (8.08, sd * 1.82, 3.1)],
                       hull_m, 'breakwater', r=0.04, seg=2))
    # рубка: нижний ярус со скруглёнными углами, ходовой мостик с наклонными окнами, крыша мостика
    o.append(rbox((0.3, 0, 3.15), (9.6, 4.3, 1.9), sup, 'house', r=0.45, seg=4))
    o.append(rhull([(-1.2, 1.75, 4.0), (-1.2, -1.75, 4.0), (3.6, 1.75, 4.0), (3.6, -1.75, 4.0), (4.5, 1.55, 4.0), (4.5, -1.55, 4.0),
                    (-1.2, 1.6, 5.55), (-1.2, -1.6, 5.55), (3.0, 1.6, 5.55), (3.0, -1.6, 5.55)], sup, 'bridge', r=0.22, seg=3))
    # окна: наклонная лента спереди и по бокам мостика
    ang = math.atan2(1.55, 1.5)
    o.append(rbox((3.82, 0, 4.98), (0.06, 2.9, 0.55), glass, 'win_front', r=0.02, seg=1,
                  rot=Matrix.Rotation(-(math.pi / 2 - ang) * 0.62, 3, 'Y')))
    for s in (-1, 1):
        o.append(rbox((1.2, s * 1.68, 4.95), (3.0, 0.05, 0.45), glass, 'win_side', r=0.02, seg=1))
    o.append(rbox((0.9, 0, 5.62), (4.4, 3.4, 0.16), hull_dk, 'bridge_roof', r=0.07, seg=2))
    # директор управления огнём на крыше мостика
    o.append(lathe([(0, 0), (0, 0.62), (0.35, 0.62), (0.62, 0.4), (0.7, 0)], sup, 'director', seg=20, c=(2.2, 0, 5.7), axis='Z'))
    o.append(rbox((2.9, 0, 6.05), (0.12, 0.9, 0.42), gun, 'director_dish', r=0.05, seg=2))
    # мачта-тренога: стойка и два подкоса, рей, антенна РЛС, радиопрозрачный купол и красный топ
    mx, mz0, mz1 = -0.6, 5.6, 10.6
    o.append(lathe([(0, 0.2), (mz1 - mz0, 0.11)], sup, 'mast', seg=10, c=(mx, 0, mz0), axis='Z'))
    for s in (-1, 1):
        o.append(tube([(mx - 2.4, s * 1.3, 4.1), (mx, s * 0.05, 8.6)], 0.09, sup, 'mast_leg'))
    o.append(tube([(mx, -1.5, 8.7), (mx, 1.5, 8.7)], 0.06, sup, 'yard'))
    o.append(rbox((mx + 0.1, 0, 9.5), (0.55, 3.0, 0.42), sup, 'radar', r=0.16, seg=3,
                  rot=Matrix.Rotation(math.radians(18), 3, 'Z')))
    o.append(lathe([(0, 0.18), (0.5, 0.42), (0.95, 0.38), (1.15, 0)], sup, 'radome', seg=16, c=(mx, 0, 9.8), axis='Z'))
    o.append(lathe([(0, 0.14), (0.35, 0.14), (0.42, 0)], red, 'mast_top', seg=10, c=(mx, 0, mz1), axis='Z'))
    # дымоходы двигателей — низкий кожух за рубкой с решётками выхлопа
    o.append(rbox((-5.4, 0, 2.75), (2.8, 2.6, 0.9), sup, 'engine_casing', r=0.3, seg=3))
    for s in (-1, 1):
        o.append(rbox((-5.4, s * 1.31, 2.85), (1.8, 0.04, 0.45), soot, 'exhaust', r=0.02, seg=1))
    # спарки: носовая и кормовая (корма смотрит назад)
    o += _gun_twin(6.6, 0, 2.62, 0.0, sup, red, gun, 'aa_bow')
    o += _gun_twin(-10.4, 0, 2.2, math.pi, sup, red, gun, 'aa_stern')
    # плотики в контейнерах по бортам рубки, ящики боезапаса у кормовой башни
    for s in (-1, 1):
        for x in (-2.6, -4.1):
            o.append(lathe([(-0.65, 0), (-0.65, 0.3), (-0.55, 0.36), (0.55, 0.36), (0.65, 0.3), (0.65, 0)], raft, 'raft',
                           seg=14, c=(x, s * 2.75, 2.75)))
        o.append(rbox((-8.1, s * 2.2, 2.55), (1.4, 0.9, 0.7), hull_dk, 'ammo', r=0.1, seg=2))
    # кнехты, брашпиль и якорный клюз на баке, кнехты на юте
    for x, y in ((11.2, 1.1), (11.2, -1.1), (-13.6, 2.4), (-13.6, -2.4), (-2.8, 2.9), (-2.8, -2.9)):
        z = 2.8 if x > 0 else 2.2
        o.append(lathe([(0, 0.17), (0.35, 0.17), (0.42, 0.22), (0.48, 0)], gun, 'bollard', seg=10, c=(x, y, z - 0.05), axis='Z'))
    o.append(lathe([(-0.55, 0), (-0.55, 0.38), (0.55, 0.38), (0.55, 0)], gun, 'windlass', seg=14, c=(12.4, 0, 3.15), axis='Y'))
    # леерное ограждение: стойки и два поручня по кромке палубы (от рубки до кормы и на баке)
    st = [s for s in _skat_stations()]
    for side in (-1, 1):
        for lo_x, hi_x in ((-14.6, -4.0), (5.4, 13.6)):
            pts = [(x, side * (b - 0.18), h) for x, b, h, k, pb in st if lo_x <= x <= hi_x]
            for zz in (0.55, 1.0):
                o.append(tube([(x, y, z + zz) for x, y, z in pts], 0.035, sup, 'rail', seg=5))
            for x, y, z in pts[::2]:
                o.append(lathe([(0, 0.035), (1.0, 0.035)], sup, 'stanchion', seg=5, c=(x, y, z), axis='Z', smooth=0))
    for side in (-1, 1):
        o.append(tube([(x, side * (b + 0.04), h - 0.42) for x, b, h, k, pb in st if -14.9 <= x <= 12.6], 0.1, hull_dk, 'rubbing', seg=6))
    # выхлоп в транце — тёмные патрубки
    for s in (-1, 1):
        o.append(lathe([(0.1, 0), (0.1, 0.32), (-0.25, 0.32), (-0.25, 0.22), (0.0, 0)], soot, 'exhaust_port', seg=14,
                       c=(-15.0, s * 1.4, 1.1)))
    finish(o, 'e_ship_aa', budget=12000)


# ======================= В-3 экраноплан «Крачка» (70 м) =======================
# По референсам Kanta (docs/biome2/refs/V-3_ekranoplan): корпус-лодка с реданом, крыло малого удлинения с
# поплавками на концах, на носовом пилоне — два блока по три двигателя, на спине три пары ракетных контейнеров,
# высокий Т-образный киль с обтекателем-шаром на стыке со стабилизатором. «По мотивам»: двигателей 6, а не 8,
# пилон короче, контейнеры крупнее; без знаков и бортовых номеров.

EKR_ST_FRONT = [  # x, полуширина, днище z, верх z, доля высоты для широкого места, показатель верха, низа
    (34.2, 0.55, 2.55, 3.9, 0.45, 2.2, 2.0), (33.2, 1.25, 1.75, 4.65, 0.42, 2.2, 1.9), (31.5, 2.0, 1.05, 5.55, 0.38, 2.3, 1.8),
    (28.8, 2.7, 0.5, 6.45, 0.34, 2.4, 1.65), (25.0, 3.12, 0.18, 7.05, 0.32, 2.5, 1.55), (20.0, 3.32, 0.04, 7.35, 0.3, 2.6, 1.5),
    (12.0, 3.4, 0.0, 7.45, 0.3, 2.6, 1.5), (4.0, 3.4, 0.0, 7.45, 0.3, 2.6, 1.5), (-2.0, 3.4, 0.0, 7.45, 0.3, 2.6, 1.5)]
EKR_ST_REAR = [   # за реданом днище поднято
    (-2.05, 3.4, 0.42, 7.45, 0.3, 2.6, 1.6), (-9.0, 3.32, 0.62, 7.4, 0.3, 2.6, 1.65), (-16.0, 3.05, 1.15, 7.25, 0.32, 2.6, 1.7),
    (-22.0, 2.55, 2.2, 7.05, 0.34, 2.5, 1.8), (-27.0, 1.9, 3.5, 6.85, 0.36, 2.4, 1.9), (-30.5, 1.15, 4.75, 6.7, 0.4, 2.3, 2.0),
    (-32.6, 0.55, 5.55, 6.55, 0.45, 2.2, 2.0)]


def _ekr_ring(s, n=44):
    x, b, zb, zt, f, p, pb = s
    zc = zb + f * (zt - zb)
    return se_ring(x, b, zt - zc, zc - zb, zc, n=n, p=p, pb=pb)


def e_ekranoplan():
    L.reset()
    up = M('ekr_grey', (0.44, 0.46, 0.47))
    lo = M('ekr_grey_lo', (0.34, 0.35, 0.35))
    wing_m = M('ekr_wing', (0.42, 0.44, 0.45))
    walk = M('ekr_walk', (0.36, 0.38, 0.39))
    red = M('red', RED)
    glass = M('glass', GLASS, 0.5)
    intake = M('intake', INTAKE)
    soot = M('soot', SOOT)
    tube_m = M('ekr_tube', (0.40, 0.42, 0.42))
    gun = M('gun', GUNMETAL)

    # корпус: две части лофта с общим сечением на редане — ступенька днища остаётся острой
    front = [s for s in catmull(EKR_ST_FRONT, 2)]
    rear = [s for s in catmull(EKR_ST_REAR, 2)]
    rings = [(34.95, 0.0, 3.2)] + [_ekr_ring(s) for s in front] + [_ekr_ring(s) for s in rear] + [(-33.4, 0.0, 6.1)]
    hull = loft(rings, up, 'hull', 40)
    # низ корпуса темнее (брызги, соль, потёки), копоть за двигателями на спине
    paint(hull, lambda c, n: lo if c.z < 1.9 else None)
    o = [hull]
    # кабина: остеклённый «горб» над носом
    cab = loft([(31.8, 0.0, 6.05)] + [se_ring(x, w, h, 0.9, zb, n=28, p=2.6) for x, w, h, zb in
               catmull([(31.2, 0.55, 0.25, 5.85), (30.0, 1.25, 0.7, 6.2), (28.0, 1.55, 0.95, 6.55), (25.5, 1.55, 0.85, 6.85),
                        (23.0, 1.2, 0.45, 7.0)], 2)] + [(22.0, 0.0, 7.2)], up, 'cabin', 40)
    paint(cab, lambda c, n: glass if c.x > 26.6 and c.z > 6.5 else None)
    o.append(cab)
    # гребень-обтекатель вдоль спины под контейнерами
    o.append(loft([(16.0, 0.0, 7.4)] + [se_ring(x, 1.05, 0.42, 0.3, 7.35, n=20, p=3.0) for x in (14.5, 10.0, 0.0, -10.0, -15.5)]
                  + [(-17.0, 0.0, 7.2)], up, 'spine', 40))
    # ракетные контейнеры: три пары, передний край приподнят на 9°
    tilt = math.radians(-9)
    for x0 in (11.0, 1.0, -9.0):
        for s in (-1, 1):
            body = lathe([(4.4, 0), (4.35, 0.32), (4.18, 0.56), (3.9, 0.74), (3.5, 0.82), (-4.3, 0.82), (-4.3, 0.74),
                          (-4.25, 0.6), (-4.25, 0)], tube_m, 'tube', seg=18)
            paint(body, lambda c, n: red if c.x > 3.75 else intake if c.x < -4.2 and abs(n.x) > 0.8 else None)
            ring = lathe([(3.0, 0.83), (3.0, 0.88), (2.75, 0.88), (2.75, 0.83)], gun, 'tube_band', seg=18, smooth=0)
            ring2 = lathe([(-2.4, 0.83), (-2.4, 0.88), (-2.65, 0.88), (-2.65, 0.83)], gun, 'tube_band', seg=18, smooth=0)
            parts = [body, ring, ring2]
            xf(parts, Matrix.Rotation(tilt, 4, 'Y'))
            xf(parts, Matrix.Translation((x0, s * 1.55, 8.75)))
            o += parts
            for dx in (-2.6, 2.4):   # ложементы
                o.append(rhull([(x0 + dx - 0.5, s * 0.8, 7.55), (x0 + dx + 0.5, s * 0.8, 7.55), (x0 + dx - 0.5, s * 2.3, 7.4),
                                (x0 + dx + 0.5, s * 2.3, 7.4), (x0 + dx - 0.4, s * 1.2, 8.25 - dx * 0.16),
                                (x0 + dx + 0.4, s * 1.2, 8.25 - dx * 0.16), (x0 + dx - 0.4, s * 1.95, 8.25 - dx * 0.16),
                                (x0 + dx + 0.4, s * 1.95, 8.25 - dx * 0.16)], gun, 'cradle', r=0.08, seg=2))
    # крыло малого удлинения: от борта до поплавка, слабая обратная поперечная V
    half = []
    w = surface([((5.0, 2.6, 2.75), 19.5, 0.14), ((3.5, 7.5, 2.62), 17.0, 0.13), ((1.6, 13.0, 2.45), 14.4, 0.115),
                 ((-1.6, 17.2, 2.32), 11.2, 0.105)], wing_m, 'wing', n=12, round_tip=False)
    paint(w, lambda c, n: walk if 4.0 < c.y < 16.2 and c.x < -10.6 else None)   # закрылки и элероны — полоса у задней кромки
    half.append(w)
    # поплавок-шайба на конце крыла: веретено с острыми концами, нос красный
    fl = lathe([(6.6, 0), (6.2, 0.35), (5.2, 0.72), (3.6, 0.98), (1.2, 1.1), (-5.0, 1.1), (-9.6, 0.92), (-12.4, 0.58),
                (-13.8, 0.24), (-14.3, 0)], up, 'tip_float', seg=24, c=(0, 17.9, 2.05), sq=(1.0, 1.0))
    paint(fl, lambda c, n: red if c.x > 5.4 else lo if c.z < 1.35 else None)
    half.append(fl)
    # концевая шайба между крылом и поплавком
    half.append(rhull([(0.4, 17.25, 2.5), (-12.3, 17.25, 2.4), (-0.5, 17.9, 1.6), (-11.8, 17.9, 1.6),
                       (0.4, 17.5, 2.5), (-12.3, 17.5, 2.4), (-0.5, 18.1, 1.6), (-11.8, 18.1, 1.6)], wing_m, 'endplate', r=0.06, seg=2))
    # пилон двигателей у носа и блок из трёх двигателей
    half.append(surface([((24.4, 2.0, 6.55), 6.2, 0.13), ((24.0, 6.0, 6.95), 5.6, 0.12), ((23.6, 10.0, 7.25), 5.0, 0.12)],
                        wing_m, 'pylon', n=10))
    for y in (4.45, 6.5, 8.55):
        nac = lathe([(-0.6, 0), (-0.6, 0.62), (0.15, 0.72), (0.35, 0.86), (0.25, 0.97), (0.0, 1.0), (-1.2, 1.01), (-4.0, 0.96),
                     (-5.4, 0.8), (-5.75, 0.72), (-5.75, 0.5), (-5.4, 0.42), (-5.4, 0)], up, 'engine', seg=18,
                    c=(25.6, y, 7.95))
        paint(nac, lambda c, n: intake if (c.x > 24.9 and n.x > -0.2 and (Vector((0, c.y - y, c.z - 7.95)).length < 0.8)) or
              (c.x < 20.3 and Vector((0, c.y - y, c.z - 7.95)).length < 0.6) else soot if c.x < 21.0 else None)
        half.append(nac)
        half.append(lathe([(0.1, 0), (0.1, 0.24), (-0.25, 0.16), (-0.25, 0)], gun, 'fan_hub', seg=12, c=(25.0, y, 7.95)))
    o += half + mirror_y(half)
    # высокий стреловидный киль, Т-образный стабилизатор и обтекатель-шар на стыке
    fin = surface([((-17.2, 0, 6.6), 15.6, 0.12), ((-21.5, 0, 11.0), 12.4, 0.115), ((-25.4, 0, 15.2), 9.6, 0.11),
                   ((-27.8, 0, 18.0), 7.6, 0.11)], up, 'fin', n=12, thick_dir=(0, 1, 0), round_tip=False)
    o.append(fin)
    for s in (-1, 1):
        o.append(surface([((-27.6, 0, 18.25), 7.1, 0.11), ((-29.4, s * 5.0, 18.35), 5.4, 0.1), ((-30.9, s * 9.4, 18.45), 3.9, 0.095)],
                         up, 'stab', n=10))
    ball = lathe([(4.0, 0), (3.6, 0.65), (2.6, 1.25), (1.0, 1.55), (-0.6, 1.5), (-2.0, 1.2), (-3.4, 0.6), (-4.0, 0)],
                 up, 'tail_ball', seg=24, c=(-29.6, 0, 18.3))
    paint(ball, lambda c, n: red if c.x < -32.6 else None)
    o.append(ball)
    finish(o, 'e_ekranoplan', budget=15000)


# ======================= В-4 гидросамолёт-ракетоносец «Буревестник» (14 м) =======================
# Двухмоторный высокоплан на двух поплавках: остеклённый штурманский нос, кабина над ним, моторы на крыле с
# трёхлопастными винтами (лопасти раздельно, с зазором, кок красный), четыре ракеты под крылом, N-стойки
# поплавков. Верх тёмно-серый морской, низ светлее, днища поплавков в потёках. Центр по высоте (как самолёты).

def e_seaplane():
    L.reset()
    upm = M('sea_up', AIR_UP)
    lom = M('sea_lo', AIR_LO)
    flo = M('sea_float_lo', FLOAT_LO)
    red = M('red', RED)
    glass = M('glass', GLASS, 0.5)
    dark = M('sea_blade', (0.16, 0.16, 0.17))
    gun = M('gun', GUNMETAL)
    soot = M('soot', SOOT)

    def two_tone(o, zsplit=None):
        paint(o, lambda c, n: lom if n.z < -0.25 or (zsplit is not None and c.z < zsplit) else upm)

    # фюзеляж: x, полуширина, низ, верх (z центра ≈ 0)
    keys = [(7.0, 0.12, -0.15, 0.22), (6.7, 0.42, -0.42, 0.45), (6.1, 0.66, -0.66, 0.66), (5.0, 0.78, -0.82, 0.86),
            (3.4, 0.8, -0.86, 1.02), (1.0, 0.78, -0.84, 1.0), (-1.5, 0.66, -0.66, 0.86), (-3.8, 0.46, -0.36, 0.7),
            (-5.6, 0.28, -0.05, 0.62), (-6.7, 0.14, 0.15, 0.58)]
    rings = [(7.12, 0.0, 0.03)] + [se_ring(x, b, zt - (zb + zt) / 2, (zt - zb) / 2, (zb + zt) / 2, n=32, p=2.2, pb=2.1)
                                   for x, b, zb, zt in catmull(keys, 2)] + [(-6.95, 0.0, 0.38)]
    fus = loft(rings, upm, 'fuselage', 40)
    paint(fus, lambda c, n: glass if c.x > 6.05 else lom if n.z < -0.25 else upm)
    # фонарь кабины лётчиков над носом
    can = loft([(5.75, 0.0, 0.92)] + [se_ring(x, w, h, 0.3, z0, n=24, p=2.4) for x, w, h, z0 in
               catmull([(5.55, 0.22, 0.08, 0.86), (5.25, 0.42, 0.2, 0.9), (4.7, 0.5, 0.27, 0.95), (4.0, 0.48, 0.24, 1.0),
                        (3.3, 0.36, 0.1, 1.02)], 2)] + [(3.05, 0.0, 1.05)], glass, 'canopy', 40)
    o = [fus, can]
    # переплёт фонаря: дуги и продольная планка
    for x, w, h, z0 in ((5.25, 0.42, 0.2, 0.9), (4.7, 0.5, 0.27, 0.95), (4.0, 0.48, 0.24, 1.0)):
        o.append(tube([(x, w * 1.03 * math.cos(t), z0 + h * 1.04 * math.sin(t) ** 0.83) for t in
                       [math.pi * k / 10 for k in range(11)]], 0.025, upm, 'canopy_frame', seg=5))
    o.append(tube([(x, 0, z0 + h * 1.04) for x, w, h, z0 in catmull([(5.55, 0.22, 0.08, 0.86), (5.25, 0.42, 0.2, 0.9),
                   (4.7, 0.5, 0.27, 0.95), (4.0, 0.48, 0.24, 1.0), (3.3, 0.36, 0.1, 1.02)], 2)], 0.025, upm, 'canopy_frame', seg=5))
    # рамы остекления носа (тонкие обручи)
    for xx, rr, zz in ((6.55, 0.5, 0.01), (6.2, 0.64, 0.0)):
        o.append(lathe([(0.03, rr * 0.97), (0.03, rr * 1.03), (-0.03, rr * 1.03), (-0.03, rr * 0.97)], gun, 'frame', seg=24,
                       c=(xx, 0, zz), smooth=0))
    # крыло-высокоплан: прямое, с сужением к концам
    wing = surface([((2.9, 0.0, 1.12), 2.5, 0.15), ((2.85, 3.6, 1.2), 2.35, 0.145), ((2.6, 7.0, 1.28), 1.85, 0.13),
                    ((2.4, 9.0, 1.33), 1.5, 0.12)], upm, 'wing', n=12)
    two_tone(wing)
    half = [wing]
    # мотогондола и винт
    nac = lathe([(4.65, 0), (4.6, 0.28), (4.4, 0.5), (3.9, 0.6), (2.0, 0.6), (0.6, 0.5), (-0.6, 0.32), (-1.4, 0.12), (-1.6, 0)],
                upm, 'nacelle', seg=20, c=(0, 3.6, 1.05))
    paint(nac, lambda c, n: lom if n.z < -0.25 else None)
    half.append(nac)
    half.append(lathe([(0.0, 0.605), (0.0, 0.625), (-0.12, 0.625), (-0.12, 0.605)], soot, 'exhaust_ring', seg=20, c=(3.95, 3.6, 1.05), smooth=0))
    half += prop((4.7, 3.6, 1.05), 1.42, 3, dark, red, 'prop', r_hub=0.27, spinner_len=0.62, chord=0.36, phase=math.radians(20))
    # пилоны и ракеты под крылом
    for yy in (5.4, 6.7):
        half.append(rhull([(2.75, yy - 0.05, 1.18), (1.75, yy - 0.05, 1.18), (2.55, yy - 0.05, 0.6), (2.0, yy - 0.05, 0.6),
                           (2.75, yy + 0.05, 1.18), (1.75, yy + 0.05, 1.18), (2.55, yy + 0.05, 0.6), (2.0, yy + 0.05, 0.6)],
                          lom, 'pylon', r=0.02, seg=1))
        rk = lathe([(4.1, 0), (3.95, 0.09), (3.6, 0.19), (3.15, 0.22), (0.6, 0.22), (0.5, 0.18), (0.5, 0)], lom, 'rocket', seg=14,
                   c=(-0.6, yy, 0.38))
        paint(rk, lambda c, n: red if c.x > 3.0 else None)
        half.append(rk)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            ca, sa = math.cos(a), math.sin(a)
            fin_ = rhull([(x, yy + rr * ca + d * sa, 0.38 + rr * sa - d * ca) for x, rr in ((0.0, 0.1), (0.7, 0.1), (-0.05, 0.42), (0.3, 0.42))
                          for d in (-0.015, 0.015)], lom, 'rocket_fin', r=0.005, seg=1)
            half.append(fin_)
    # поплавок: днище с реданом, подъём носа; стойки N
    fkeys = [(4.6, 0.08, -2.0, -1.78), (4.2, 0.3, -2.25, -1.64), (3.4, 0.44, -2.4, -1.6), (1.5, 0.48, -2.45, -1.6),
             (0.0, 0.48, -2.45, -1.6), (-0.02, 0.48, -2.33, -1.6), (-1.8, 0.4, -2.2, -1.64), (-3.4, 0.22, -1.98, -1.72),
             (-3.8, 0.08, -1.88, -1.77)]
    def fring(x, b, zb, zt):
        zc = zb + 0.22 * (zt - zb)
        return se_ring(x, b, zt - zc, zc - zb, zc, n=28, p=2.6, pb=1.6, yc=1.9)
    fl_rings = ([(4.75, 1.9, -1.86)] + [fring(*k) for k in catmull(fkeys[:5], 2)] + [fring(*k) for k in catmull(fkeys[5:], 2)]
                + [(-3.95, 1.9, -1.82)])
    flt = loft(fl_rings, upm, 'float', 40)
    paint(flt, lambda c, n: flo if c.z < -2.08 else None)
    half.append(flt)
    for x0 in (2.6, -0.2):
        half.append(tube([(x0, 1.9, -1.62), (x0 + 0.15, 0.62, -0.55)], 0.06, lom, 'strut', seg=8))
        half.append(tube([(x0, 1.9, -1.62), (x0 + 0.2, 3.4, 1.05)], 0.055, lom, 'strut', seg=8))
    o += half + mirror_y(half)
    # оперение: киль с красной законцовкой, стабилизатор
    fin = surface([((-4.4, 0, 0.55), 2.3, 0.12), ((-5.6, 0, 1.7), 1.6, 0.11), ((-6.1, 0, 2.35), 1.1, 0.1)], upm, 'fin', n=10,
                  thick_dir=(0, 1, 0))
    paint(fin, lambda c, n: red if c.z > 2.15 else None)
    o.append(fin)
    for s in (-1, 1):
        st = surface([((-5.0, 0, 0.5), 1.55, 0.11), ((-5.55, s * 2.9, 0.58), 0.95, 0.1)], upm, 'stab', n=10)
        two_tone(st)
        o.append(st)
    # антенна-штырь и турельный купол сверху за крылом
    o.append(lathe([(0, 0.22), (0.12, 0.21), (0.22, 0.15), (0.26, 0)], glass, 'astrodome', seg=16, c=(-0.8, 0, 0.84), axis='Z'))
    finish(o, 'e_seaplane', center=True, budget=12000)


# ======================= В-5 дрон «Чайка» (3 м) =======================
# Малый ударный дрон: обтекаемый фюзеляж с красным носом, оптический шар под носом, крыло «чайкой» с изломом,
# V-образное оперение, толкающий двухлопастной винт с коком за хвостом.

def e_drone_sea():
    L.reset()
    grey = M('drone_grey', (0.42, 0.44, 0.45))
    lo = M('drone_lo', (0.52, 0.53, 0.53))
    dark = M('drone_dark', (0.18, 0.18, 0.19))
    red = M('red', RED)
    glass = M('glass', GLASS, 0.5)
    fus = lathe([(1.55, 0), (1.5, 0.06), (1.38, 0.12), (1.15, 0.16), (0.8, 0.18), (0.0, 0.18), (-0.7, 0.15), (-1.05, 0.11),
                 (-1.22, 0.075), (-1.26, 0)], grey, 'fuselage', seg=20, sq=(1.0, 1.08))
    paint(fus, lambda c, n: red if c.x > 1.12 else lo if n.z < -0.4 else None)
    o = [fus]
    o.append(lathe([(0, 0.1), (0.07, 0.09), (0.11, 0)], glass, 'sensor', seg=12, c=(0.95, 0, -0.17), axis='Z', sq=(1, 1)))
    o.append(lathe([(0.06, 0.13), (-0.02, 0.13), (-0.02, 0)], dark, 'sensor_mount', seg=12, c=(0.95, 0, -0.14), axis='Z'))
    # крыло «чайкой»: корень вверх, излом, внешняя часть с небольшим V
    w = surface([((0.42, 0.12, 0.04), 0.5, 0.13), ((0.36, 0.72, 0.2), 0.42, 0.12), ((0.27, 1.25, 0.15), 0.33, 0.11),
                 ((0.18, 1.62, 0.11), 0.26, 0.1)], grey, 'wing', n=9)
    paint(w, lambda c, n: lo if n.z < -0.3 else red if c.y > 1.55 else None)
    half = [w]
    half.append(surface([((-0.78, 0.0, 0.08), 0.42, 0.11), ((-0.98, 0.33, 0.36), 0.27, 0.1), ((-1.06, 0.42, 0.44), 0.21, 0.1)],
                        grey, 'vtail', n=8, thick_dir=(0, -0.79, 0.62)))
    o += half + mirror_y(half)
    o.append(lathe([(0.0, 0.075), (-0.08, 0.06), (-0.08, 0)], dark, 'motor_cap', seg=12, c=(-1.25, 0, 0)))
    o += prop((-1.36, 0, 0), 0.5, 2, dark, dark, 'prop', pusher=True, r_hub=0.07, spinner_len=0.17, chord=0.11,
              phase=math.radians(70))
    finish(o, 'e_drone_sea', center=True, budget=3000)


RECIPES = {f.__name__: f for f in (e_ship_aa, e_ekranoplan, e_seaplane, e_drone_sea)}

if __name__ == '__main__':
    names = [a for a in A if not a.startswith('--')]
    for nm in (list(RECIPES) if names == ['all'] else names):
        RECIPES[nm]()
