"""Вражеские самолёты кодом (тест 3.5-s8, замечание Kanta: «модели кривые, с буграми — переработать и выровнять»).
Замена моделей Meshy (115 оторванных кусков у «Перехватчика», бугристая обшивка, рваные нормали) на чистые модели:
фюзеляж — лофт по сечениям-суперэллипсам со сплайном Катмулла — Рома (гладкий, без бугров), крылья и оперение —
профиль NACA 00xx с толщиной, фонарь-капля, воздухозаборники, сопла, подвесы, полосы окраски по обшивке.
Цвет и нормали запекаются набором convoy_kit.py (как вертолёт «Сарыч», helicopter.py).

Машины вымышленные, «по мотивам» (силуэт и роль — как у прежних моделей и спрайтов art/enemies/e_*.png),
без знаков, номеров и надписей. Окраска противника — тёмно-серая с красными законцовками и полосами
(своя у каждого, игрока не напоминает: у игрока песочный камуфляж). Краска матовая (правило Kanta 19.10).

Самолёты (id → models/battle/fh_battle_e_<id>.glb):
  interceptor — «Перехватчик»: лёгкий, ПГО, стреловидное крыло, два киля с развалом, красные законцовки;
  rival       — «Ас-соперник»: тяжёлый двухдвигательный, большое трапециевидное крыло, два прямых киля;
  draft       — «Сквозняк» (босс): длинный нос, ПГО, разнесённые двигатели, «жало» между соплами,
                контейнеры на законцовках, чёрный с красными «языками пламени»;
  postman     — «Почтальон» (босс-ракетоносец): большое крыло, двухместный фонарь, 4 ракеты под каждым крылом,
                красно-белая «молния» по крылу.
Оси: нос +X, верх +Z, левое крыло +Y; в конце модель центрируется по габаритам и масштабируется до длины 1
(как прежние: центр габаритов в начале координат). Подвижных узлов у этих врагов нет (render3d их не ищет).

Запуск (из game/tools/blender):  python3 enemy_air.py <id> <папка>
  → <папка>/<id>.glb, <id>.blend, <id>_color.png, <id>_normal.png; NOPREVIEW=1 — без кадров Cycles,
  TEX=1024 — размер текстур. GLB затем копируется в models/battle/fh_battle_e_<id>.glb."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
import convoy_kit as K
from convoy_kit import box, cyl, lathe, loft, tube
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

PLANE = sys.argv[-2] if len(sys.argv) >= 3 else "interceptor"
OUT = sys.argv[-1]


# ================================================================ библиотека
def X(d):
    """Расстояние от носа, м → x (нос в x = 0, хвост в минус)"""
    return -d


def _cr(p0, p1, p2, p3, t):
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def interp(T, d):
    """Значения таблицы T (строки: d, a, b, …) в точке d — сплайн Катмулла — Рома (гладко, без изломов)"""
    ds = [r[0] for r in T]
    d = min(max(d, ds[0]), ds[-1])
    i = next((k for k in range(len(T) - 1) if ds[k + 1] >= d), len(T) - 2)
    t = (d - ds[i]) / (ds[i + 1] - ds[i])
    return [_cr(T[max(i - 1, 0)][j], T[i][j], T[i + 1][j], T[min(i + 2, len(T) - 1)][j], t) for j in range(1, len(T[0]))]


def _se(c, n):
    return math.copysign(abs(c) ** (2.0 / n), c)


class Body:
    """Тело вдоль оси X: таблица сечений (d, низ z, верх z, полуширина, показатель суперэллипса), центр по Y — yc"""

    def __init__(self, T, yc=0.0):
        self.T = T
        self.yc = yc

    def sec(self, d):
        return interp(self.T, d)

    def ring(self, d, N=32, scale=1.0):
        zb, zt, w, n = self.sec(d)
        zc, h = (zb + zt) / 2, (zt - zb) / 2 * scale
        w *= scale
        return [Vector((X(d), self.yc + w * _se(math.cos(2 * math.pi * k / N), n), zc + h * _se(math.sin(2 * math.pi * k / N), n)))
                for k in range(N)]

    def top(self, d):
        return self.sec(d)[1]

    def half_w(self, d, z):
        """Полуширина на высоте z (0 — выше или ниже сечения)"""
        zb, zt, w, n = self.sec(d)
        zc, h = (zb + zt) / 2, (zt - zb) / 2
        t = abs(z - zc) / h
        return 0.0 if t >= 1.0 else w * (1.0 - t ** n) ** (1.0 / n)

    def build(self, name, kinds, N=28, step=0.4):
        """kinds — [(d от, вид)] по возрастанию d: нос другого цвета и т. п. Соседние части делят одно сечение"""
        d0, d1 = self.T[0][0], self.T[-1][0]
        cuts = [k[0] for k in kinds] + [d1]
        for i, (a, kind) in enumerate(kinds):
            b = cuts[i + 1]
            a = max(a, d0)
            n = max(2, int(math.ceil((b - a) / step)))
            # у носа сечения чаще: там кривизна больше
            ds = [a + (b - a) * ((j / n) ** 1.0) for j in range(n + 1)]
            if a <= d0 + 1e-6:
                extra = [d0 + (ds[1] - d0) * f for f in (0.08, 0.25, 0.5)]
                ds = [ds[0]] + extra + ds[1:]
            loft(name if i == 0 else "%s_%d" % (name, i), [self.ring(d, N) for d in ds], kind)


def airfoil(m=10):
    """Симметричный профиль NACA 00xx (толщина 1): кольцо от задней кромки по верху к носку и по низу назад.
    Точки по косинусу — носок гладкий, задняя кромка тонкая, но не нулевая."""
    xs = [0.5 * (1 - math.cos(math.pi * i / m)) for i in range(m + 1)]

    def yt(x):
        return 5 * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1015 * x ** 4)
    return [(x, yt(x)) for x in reversed(xs)] + [(x, -yt(x)) for x in xs[1:]]


AF = airfoil()


def surface(name, st, kind, thick=0.05, flat=1.0):
    """Крыло / оперение / киль: станции (d передней кромки, y, z, хорда[, вид следующего участка]).
    Хорда — назад по X, толщина — поперёк плоскости размаха; flat < 1 — профиль площе (ПГО, стабилизатор)."""
    p0 = Vector((0, st[0][1], st[0][2]))
    p1 = Vector((0, st[-1][1], st[-1][2]))
    sd = (p1 - p0).normalized()
    nrm = Vector((-1, 0, 0)).cross(sd).normalized()
    if nrm.z < 0 or (abs(nrm.z) < 1e-6 and nrm.y < 0):
        nrm = -nrm

    def ring(s):
        d, y, z, ch = s[:4]
        le = Vector((X(d), y, z))
        t = s[5] if len(s) > 5 else thick
        return [le + Vector((-u * ch, 0, 0)) + nrm * (v * t * ch * flat) for u, v in AF]
    # вид участка от станции i к i + 1: свой у станции (5-й элемент) или как у предыдущего участка
    seg = []
    for i in range(len(st) - 1):
        k = st[i][4] if len(st[i]) > 4 and st[i][4] else (seg[-1] if seg else kind)
        seg.append(k)
    obs = []
    i0 = 0
    for i in range(1, len(seg) + 1):
        if i == len(seg) or seg[i] != seg[i0]:
            obs.append(loft(name if not obs else "%s_%d" % (name, len(obs)), [ring(s) for s in st[i0:i + 1]], seg[i0]))
            i0 = i
    return obs


def lerp_st(a, b, t, kind=None):
    """Промежуточная станция между a и b (для полос: красная законцовка с t = 0,8 и т. п.)"""
    s = tuple(a[i] + (b[i] - a[i]) * t for i in range(4))
    return s + (kind,)


def mirror(st):
    return [(s[0], -s[1]) + tuple(s[2:]) for s in st]


def canopy(name, body, d0, d1, h, hw, sink=0.08, peak=0.3, kind="glass", M=12, N=18):
    """Фонарь-капля на спине тела body: от d0 до d1, высота h над обшивкой, полуширина hw; низ утоплен в обшивку"""
    secs = []
    for i in range(M + 1):
        t = i / M
        # профиль: быстрый подъём лобового стекла, вершина в peak, длинный спад назад
        u = t / peak if t < peak else 1 + (t - peak) / (1 - peak)
        f = math.sin(u * math.pi / 2) if u <= 1 else math.cos((u - 1) * math.pi / 2)
        f = max(f, 0.0) ** 0.75
        d = d0 + (d1 - d0) * t
        base = body.top(d) - sink
        w = min(hw * max(f, 0.08) ** 0.5, 0.97 * body.half_w(d, base))
        hh = h * f + sink
        ring = []
        for k in range(N + 1):
            a = math.pi * k / N
            ring.append(Vector((X(d), body.yc + w * _se(math.cos(a), 2.3), base + hh * max(_se(math.sin(a), 2.3), 0.0))))
        ring.append(Vector((X(d), body.yc - w * 0.6, base - 0.05)))
        ring.append(Vector((X(d), body.yc + w * 0.6, base - 0.05)))
        secs.append(ring)
    ob = loft(name, secs, kind)
    return ob, secs


def arch(name, secs, i, r=0.035, kind="dark", out=0.012):
    """Переплёт фонаря: дуга по сечению i, чуть снаружи стекла"""
    ring = secs[i][:-2]
    c = Vector((ring[0].x, (ring[0].y + ring[-1].y) / 2, ring[0].z))
    pts = [p + (p - c).normalized() * out for p in ring]
    tube(name, pts, r, kind, 6)


def nozzle(name, d0, d1, y, z, r0, r1, kind="nozzle", petals=True):
    """Сопло: оболочка от d0 к d1 (радиус r0 → r1), внутри тёмная труба и турбина, кромка с утолщением"""
    ln = d1 - d0
    lathe(name, [(r0, 0.0), (r0 * 0.99, -ln * 0.3), (r1, -ln), (r1 * 0.9, -ln - 0.02), (r1 * 0.84, -ln + 0.25)],
          (X(d0), y, z), kind, "X", 24, cap1=True)
    cyl(name + "_in", (X(d1) + 0.2, y, z), r1 * 0.83, 0.05, "black", "X", 20)
    if petals:   # створки: тонкие продольные рёбра по оболочке
        for k in range(8):
            a = 2 * math.pi * (k + 0.5) / 8
            dv = Vector((0, math.cos(a), math.sin(a)))
            p0 = Vector((X(d0) - ln * 0.35, y, z)) + dv * (r0 * 0.99 + 0.01)
            p1 = Vector((X(d1) + 0.05, y, z)) + dv * (r1 + 0.01)
            tube(name + "_rib", [p0, p1], 0.018, "dark", 4)


def intake(name, T, yc, kind="paint"):
    """Воздухозаборник: тело по таблице (d, низ, верх, полуширина, n) у борта yc; спереди тёмный канал с кромкой"""
    b = Body(T, yc)
    b.build(name, [(T[0][0], kind)], N=24, step=0.4)
    hole(b, T[0][0], name + "_hole")
    return b


def hole(body, d, name="intake_hole"):
    """Тёмный канал воздухозаборника: диск чуть впереди переднего среза тела, кромка остаётся в цвет обшивки"""
    ring = body.ring(d - 0.01, 24, 0.8)
    ob = K._obj(name, ring, [tuple(range(len(ring)))], "black")
    _orient(ob, Vector((1, 0, 0)))


def missile(name, d_tip, y, z, ln, r, kind="missile", tip="red", fins=True):
    """Ракета: тело вращения нос +X, крестовидные рули у хвоста и крылышки посередине"""
    x_tail = X(d_tip + ln)
    lathe(name, [(r * 0.85, 0.0), (r, 0.04 * ln), (r, 0.78 * ln)], (x_tail, y, z), kind, "X", 12, cap0=True)
    lathe(name + "_nose", [(r, 0.78 * ln), (r * 0.72, 0.88 * ln), (r * 0.3, 0.97 * ln), (0.001, ln)], (x_tail, y, z), tip, "X", 12)
    cyl(name + "_noz", (x_tail - 0.02, y, z), r * 0.6, 0.04, "black", "X", 10)
    if fins:
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            R = Matrix.Rotation(a, 3, "X")
            for dd, sz in ((0.06, 0.12), (0.5, 0.16)):
                c = Vector((x_tail + dd * ln + sz * ln / 2, 0, 0)) + R @ Vector((0, r * 1.7, 0))
                box(name + "_fin", (c.x, y + c.y, z + c.z), (sz * ln, r * 1.5, 0.025), kind, 0.0, rot=R)


_bvh = {}


def _tree(names):
    key = (tuple(names), len(K.parts))
    if key not in _bvh:
        vs, fs = [], []
        for ob in K.parts:
            if any(ob.name == n or ob.name.startswith(n + "_") or ob.name.startswith(n + ".") for n in names):
                o = len(vs)
                vs += [v.co.copy() for v in ob.data.vertices]
                fs += [tuple(o + i for i in p.vertices) for p in ob.data.polygons]
        _bvh[key] = BVHTree.FromPolygons(vs, fs)
    return _bvh[key]


def surf_z(names, d, y, up=True):
    """Высота обшивки деталей names над точкой (d, y): сверху (up) или снизу"""
    t = _tree(names)
    if up:
        loc, _, _, _ = t.ray_cast(Vector((X(d), y, 30.0)), Vector((0, 0, -1)), 60.0)
    else:
        loc, _, _, _ = t.ray_cast(Vector((X(d), y, -30.0)), Vector((0, 0, 1)), 60.0)
    return None if loc is None else loc.z


def _orient(ob, want=Vector((0, 0, 1))):
    """Открытая полоса: нормали к want (bmesh для открытых листов направление не угадывает)"""
    me = ob.data
    s = sum((p.normal.dot(want) for p in me.polygons), 0.0)
    if s < 0:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()


def stripe(name, names, pts, widths, kind, off=0.012, sub=3, up=True):
    """Полоса краски по обшивке деталей names: осевая линия pts [(d, y)], ширины widths (одна или на точку).
    Вершины проецируются лучом сверху (снизу) на обшивку и приподнимаются на off — лежит ровно по профилю."""
    if not isinstance(widths, (list, tuple)):
        widths = [widths] * len(pts)
    P, W = [], []
    for i in range(len(pts) - 1):
        for k in range(sub):
            t = k / sub
            P.append((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t))
            W.append(widths[i] + (widths[i + 1] - widths[i]) * t)
    P.append(pts[-1])
    W.append(widths[-1])
    vs, rows = [], []
    for i, (d, y) in enumerate(P):
        a = P[max(i - 1, 0)]
        b = P[min(i + 1, len(P) - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / ln, tx / ln
        row = []
        for s in (-0.5, 0.0, 0.5):
            dd, yy = d + nx * W[i] * s, y + ny * W[i] * s
            z = surf_z(names, dd, yy, up)
            if z is None:
                row.append(None)
                continue
            row.append(len(vs))
            vs.append(Vector((X(dd), yy, z + (off if up else -off))))
        rows.append(row)
    fs = []
    for i in range(len(rows) - 1):
        for j in range(2):
            q = (rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j])
            if None not in q:
                fs.append(q)
    if not fs:
        return None
    ob = K._obj(name, vs, fs, kind)
    _orient(ob, Vector((0, 0, 1 if up else -1)))
    return ob


def pylon(name, d0, d1, y, z_top, z_bot, kind="dark"):
    """Пилон: обтекаемая пластина от низа крыла до подвеса"""
    ln = d1 - d0
    prof = [(X(d0), z_top), (X(d0) - ln * 0.15, z_bot), (X(d1) + ln * 0.1, z_bot), (X(d1), z_top)]
    K.prism(name, prof, y - 0.06, y + 0.06, kind, 0.015)


def finish(name):
    """Габариты → длина 1, центр в начале координат; запекание, экспорт; краска матовая"""
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in K.parts:
        for v in o.data.vertices:
            lo = Vector(map(min, lo, v.co))
            hi = Vector(map(max, hi, v.co))
    c = (lo + hi) / 2
    sc = 1.0 / (hi.x - lo.x)
    M = Matrix.Scale(sc, 4) @ Matrix.Translation(-c)
    for o in K.parts:
        o.data.transform(M)
        for md in o.modifiers:
            if md.type == "BEVEL":
                md.width *= sc
    print("SIZE length %.2f m, span %.3f, height %.3f (в долях длины)" % (hi.x - lo.x, (hi.y - lo.y) * sc, (hi.z - lo.z) * sc))
    if os.environ.get("DRY"):   # проверка геометрии без запекания: детали, треугольники, высоты
        for o in K.parts:
            zs = [v.co.z for v in o.data.vertices]
            print("PART", o.name, len(o.data.polygons), "z %.4f..%.4f" % (min(zs), max(zs)))
        return
    tune_paint()
    root, tris = K.bake_export(name, OUT, tex=int(os.environ.get("TEX", "1024")))
    matte(os.path.join(OUT, name + ".glb"), name)
    if not os.environ.get("NOPREVIEW"):
        K.preview(OUT, name, 0.8)
    print("DONE", name, "tris", tris)


def tune_paint():
    """Шейдер convoy_kit рассчитан на песочную краску: выгорание и потёртости там песочные и для тёмно-серой
    окраски самолёта дают бурый налёт. Здесь (без правки общего набора) — выгорание слабее и в серый,
    потёртые кромки — в светло-серый металл"""
    sand_bleach = K.lin((0.8, 0.74, 0.62))
    sand_wear = K.lin((0.72, 0.66, 0.55))

    def same(a, b):
        return all(abs(a[i] - b[i]) < 1e-4 for i in range(3))
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type == "VALUE" and abs(n.outputs[0].default_value - 0.12) < 1e-6:
                n.outputs[0].default_value = 0.04
            elif n.type == "RGB":
                c = n.outputs[0].default_value
                if same(c, sand_bleach):
                    n.outputs[0].default_value = (*K.lin((0.5, 0.5, 0.49)), 1)
                elif same(c, sand_wear):
                    n.outputs[0].default_value = (*K.lin((0.48, 0.48, 0.47)), 1)


def matte(path, name):
    """Правило Kanta 19.10: краска матовая (шероховатость 0,88, металл 0,08), стекло — без зеркального блеска"""
    import importlib.util
    spec = importlib.util.spec_from_file_location("glb_merge_prims", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "glb_merge_prims.py"))
    gm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gm)
    js, bin_ = gm.read_glb(path)
    for m in js.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        if m.get("name", "").endswith("_glass"):
            pbr["roughnessFactor"], pbr["metallicFactor"] = 0.32, 0.1
        else:
            pbr["roughnessFactor"], pbr["metallicFactor"] = 0.88, 0.08
    gm.write_glb(path, js, bin_)


# ================================================================ окраска противника
def scheme(dark=False):
    """Тёмно-серый матовый камуфляж из двух-трёх тонов (у draft — почти чёрный), светлее снизу; красный — приглушённый"""
    if dark:
        K.CAMO = [(0.15, 0.15, 0.155), (0.19, 0.19, 0.195), (0.12, 0.12, 0.125)]
        K.BELLY = (0.24, 0.24, 0.25)
    else:
        K.CAMO = [(0.25, 0.255, 0.265), (0.31, 0.315, 0.32), (0.2, 0.205, 0.215)]
        K.BELLY = (0.42, 0.43, 0.44)
    K.CAMO_SCALE = 1.5
    K.CAMO_STRETCH = (0.6, 1.0, 1.0)
    K.DUST = (0.47, 0.45, 0.41)
    K.EDGE_K = 0.6
    K.AO_K = 0.8
    K.KINDS["paint"] = (K.CAMO[0], 0.08, 0.88, 0.12, True)
    K.KINDS["red"] = ((0.55, 0.15, 0.11), 0.05, 0.88, 0.2, False)
    K.KINDS["white"] = ((0.72, 0.71, 0.66), 0.05, 0.88, 0.25, False)
    K.KINDS["radome"] = ((0.24, 0.245, 0.25), 0.05, 0.9, 0.2, False)
    K.KINDS["nozzle"] = ((0.27, 0.25, 0.23), 0.4, 0.75, 0.3, False)
    K.KINDS["missile"] = ((0.6, 0.6, 0.57), 0.05, 0.85, 0.2, False)
    K.KINDS["olive"] = ((0.3, 0.3, 0.27), 0.05, 0.85, 0.3, False)


# ================================================================ «Перехватчик» (15 м, размах 12,5 м)
def interceptor():
    scheme()
    fus = Body([
        (0.0, -0.03, 0.03, 0.03, 2.0), (0.4, -0.16, 0.17, 0.16, 2.0), (1.2, -0.32, 0.36, 0.32, 2.0),
        (2.2, -0.45, 0.5, 0.44, 2.1), (3.4, -0.53, 0.6, 0.52, 2.2), (4.6, -0.57, 0.64, 0.58, 2.3),
        (6.0, -0.58, 0.6, 0.7, 2.5), (7.5, -0.58, 0.56, 0.86, 2.8), (9.5, -0.56, 0.53, 0.95, 3.0),
        (11.5, -0.53, 0.5, 0.96, 3.0), (13.2, -0.48, 0.46, 0.92, 2.8), (14.3, -0.45, 0.43, 0.86, 2.6)])
    fus.build("fuselage", [(0.0, "red"), (1.5, "paint")])
    # горб за кабиной
    spine = Body([(5.0, 0.3, 0.45, 0.2, 2.2), (6.2, 0.3, 0.72, 0.36, 2.4), (9.0, 0.3, 0.72, 0.4, 2.6),
                  (12.0, 0.3, 0.6, 0.34, 2.4), (13.6, 0.3, 0.45, 0.2, 2.2)])
    spine.build("spine", [(5.0, "paint")], N=24)
    cb, cs = canopy("canopy", fus, 2.4, 6.0, 0.5, 0.44)
    arch("canopy_frame", cs, 4)
    # воздухозаборники по бортам под ПГО
    for s in (1, -1):
        intake("intake", [(4.9, -0.5, 0.25, 0.3, 4.0), (5.6, -0.52, 0.28, 0.33, 3.6), (7.5, -0.5, 0.22, 0.3, 3.0),
                          (9.5, -0.45, 0.1, 0.22, 2.6)], s * 0.82)
    # крыло: корень у борта, стреловидность ~48°, красная законцовка
    for s in (1, -1):
        root = (7.0, s * 0.75, -0.08, 4.6)
        tip = (10.9, s * 6.25, -0.12, 1.25)
        surface("wing", [root, lerp_st(root, tip, 0.5), lerp_st(root, tip, 0.8, "red"), tip], "paint", 0.05)
        # ПГО
        r2, t2 = (4.5, s * 0.6, 0.12, 1.5), (5.75, s * 2.15, 0.12, 0.55)
        surface("canard", [r2, lerp_st(r2, t2, 0.65, "red"), t2], "paint", 0.04)
        # стабилизатор
        r3, t3 = (12.1, s * 0.75, -0.2, 2.5), (13.9, s * 3.6, -0.24, 1.0)
        surface("stab", [r3, lerp_st(r3, t3, 0.7, "red"), t3], "paint", 0.04)
        # кили с развалом 14°
        a = math.radians(14)
        r4 = (11.0, s * 0.62, 0.4, 3.0)
        t4 = (13.4, s * (0.62 + 2.7 * math.sin(a)), 0.4 + 2.7 * math.cos(a), 1.1)
        surface("fin", [r4, lerp_st(r4, t4, 0.8, "red"), t4], "paint", 0.045)
        # ракеты под крылом
        for y, dd in ((2.6, 8.0), (4.3, 9.3)):
            zb = surf_z(["wing"], dd + 0.8, s * y, False)
            pylon("pylon", dd + 0.2, dd + 1.6, s * y, zb + 0.05, zb - 0.15)
            missile("aam", dd - 0.6, s * y, zb - 0.27, 3.0, 0.1)
        nozzle("nozzle", 13.9, 15.0, s * 0.44, -0.04, 0.42, 0.36)
    # ПВД на носу
    tube("pitot", [(X(0.2), 0, 0), (X(-0.7), 0, 0)], 0.025, "steel", 6)
    finish("interceptor")


# ================================================================ «Ас-соперник» (19 м, размах ~17,8 м)
def rival():
    scheme()
    fus = Body([
        (0.0, -0.04, 0.04, 0.04, 2.0), (0.5, -0.22, 0.22, 0.2, 2.0), (1.6, -0.42, 0.46, 0.4, 2.0),
        (3.0, -0.55, 0.62, 0.55, 2.1), (4.6, -0.6, 0.72, 0.62, 2.2), (6.4, -0.58, 0.72, 0.68, 2.4),
        (8.5, -0.5, 0.62, 0.66, 2.4), (11.0, -0.42, 0.52, 0.58, 2.4), (13.5, -0.34, 0.42, 0.45, 2.3),
        (15.0, -0.3, 0.35, 0.3, 2.2)])
    fus.build("fuselage", [(0.0, "red"), (1.7, "paint")])
    # плоская «палуба» между двигателями (несущий корпус) и хвостовая балка между соплами
    deck = Body([(6.0, -0.32, 0.05, 0.8, 4.0), (8.0, -0.42, 0.2, 2.0, 4.5), (12.0, -0.45, 0.24, 2.1, 4.5),
                 (16.0, -0.42, 0.18, 1.95, 4.5), (18.0, -0.3, 0.08, 1.1, 3.5), (19.0, -0.12, 0.02, 0.45, 2.6)])
    deck.build("deck", [(6.0, "paint")], step=0.4)
    for s in (1, -1):
        # гондолы двигателей с прямоугольными заборниками под наплывом
        nac = Body([(5.6, -0.95, 0.05, 0.55, 4.5), (6.5, -0.97, 0.1, 0.6, 4.0), (9.0, -0.92, 0.2, 0.62, 3.0),
                    (13.0, -0.82, 0.3, 0.62, 2.4), (16.5, -0.72, 0.28, 0.58, 2.2), (17.8, -0.68, 0.22, 0.52, 2.1)], s * 1.45)
        nac.build("nacelle", [(5.6, "paint")], N=24, step=0.4)
        hole(nac, 5.6)
        nozzle("nozzle", 17.7, 19.0, s * 1.45, -0.23, 0.5, 0.44)
        # крыло с наплывом: корень у борта, излом, законцовка (красная кромка)
        st = [(5.4, s * 0.5, 0.0, 10.0), (9.6, s * 2.6, 0.0, 6.2), (14.0, s * 8.9, -0.05, 2.2)]
        surface("wing", [st[0], st[1], lerp_st(st[1], st[2], 0.5), lerp_st(st[1], st[2], 0.88, "red"), st[2]], "paint", 0.045)
        r3, t3 = (15.4, s * 1.9, -0.25, 3.6), (17.3, s * 4.9, -0.28, 1.6)
        surface("stab", [r3, lerp_st(r3, t3, 0.75, "red"), t3], "paint", 0.04)
        a = math.radians(6)
        r4 = (12.2, s * 1.45, 0.3, 4.4)
        t4 = (15.4, s * (1.45 + 3.6 * math.sin(a)), 0.3 + 3.6 * math.cos(a), 1.7)
        surface("fin", [r4, lerp_st(r4, t4, 0.82, "red"), t4], "paint", 0.045)
        for y, dd in ((4.0, 9.8), (6.0, 11.6)):
            zb = surf_z(["wing"], dd + 1.0, s * y, False)
            pylon("pylon", dd + 0.3, dd + 1.9, s * y, zb + 0.05, zb - 0.16)
            missile("aam", dd - 0.7, s * y, zb - 0.3, 3.6, 0.11)
    cb, cs = canopy("canopy", fus, 2.8, 7.4, 0.62, 0.5)
    arch("canopy_frame", cs, 4)
    tube("pitot", [(X(0.2), 0, 0), (X(-0.6), 0, 0)], 0.028, "steel", 6)
    finish("rival")


# ================================================================ «Сквозняк» (босс, 21 м, размах ~18 м)
def draft():
    scheme(dark=True)
    fus = Body([
        (0.0, -0.03, 0.03, 0.03, 2.0), (0.6, -0.2, 0.2, 0.18, 2.0), (2.0, -0.42, 0.44, 0.38, 2.0),
        (3.6, -0.55, 0.6, 0.52, 2.1), (5.2, -0.6, 0.72, 0.6, 2.2), (7.0, -0.58, 0.74, 0.66, 2.4),
        (9.0, -0.5, 0.64, 0.66, 2.4), (12.0, -0.42, 0.55, 0.58, 2.4), (15.0, -0.33, 0.42, 0.42, 2.3),
        (17.5, -0.26, 0.3, 0.3, 2.2), (19.5, -0.2, 0.2, 0.22, 2.0), (21.0, -0.06, 0.06, 0.06, 2.0)])
    # длинное «жало» между соплами идёт в той же таблице, что и нос
    fus.build("fuselage", [(0.0, "red"), (2.2, "paint")])
    deck = Body([(6.8, -0.32, 0.05, 0.8, 4.0), (9.0, -0.44, 0.22, 2.3, 4.5), (13.5, -0.46, 0.25, 2.45, 4.5),
                 (17.0, -0.42, 0.18, 2.2, 4.5), (18.4, -0.3, 0.08, 1.3, 3.5)])
    deck.build("deck", [(6.8, "paint")], step=0.4)
    for s in (1, -1):
        nac = Body([(6.4, -0.98, 0.05, 0.58, 4.5), (7.4, -1.0, 0.12, 0.62, 4.0), (10.0, -0.95, 0.22, 0.64, 3.0),
                    (14.0, -0.84, 0.32, 0.64, 2.4), (17.0, -0.75, 0.28, 0.6, 2.2), (18.2, -0.7, 0.22, 0.55, 2.1)], s * 1.75)
        nac.build("nacelle", [(6.4, "paint")], N=24, step=0.4)
        hole(nac, 6.4)
        nozzle("nozzle", 18.1, 19.5, s * 1.75, -0.24, 0.53, 0.47)
        st = [(6.0, s * 0.5, 0.0, 10.4), (10.4, s * 2.9, 0.0, 6.4), (14.6, s * 8.6, -0.05, 2.4)]
        surface("wing", [st[0], st[1], lerp_st(st[1], st[2], 0.5), st[2]], "paint", 0.045)
        r2, t2 = (4.2, s * 0.62, 0.15, 2.0), (5.7, s * 3.0, 0.15, 0.85)
        surface("canard", [r2, t2], "paint", 0.04)
        r3, t3 = (16.0, s * 2.2, -0.25, 3.4), (18.0, s * 5.0, -0.28, 1.5)
        surface("stab", [r3, t3], "paint", 0.04)
        a = math.radians(10)
        r4 = (13.0, s * 1.75, 0.3, 4.2)
        t4 = (16.2, s * (1.75 + 3.4 * math.sin(a)), 0.3 + 3.4 * math.cos(a), 1.6)
        surface("fin", [r4, lerp_st(r4, t4, 0.8, "red"), t4], "paint", 0.045)
        # законцовки: пусковые с длинными контейнерами
        missile("tip_pod", 13.4, s * 8.75, -0.08, 4.4, 0.17, "olive", "red", fins=False)
        box("tip_rail", (X(15.6), s * 8.68, -0.03), (2.4, 0.1, 0.12), "dark", 0.01)
    cb, cs = canopy("canopy", fus, 3.3, 8.2, 0.62, 0.5)
    arch("canopy_frame", cs, 4)
    tube("pitot", [(X(0.2), 0, 0), (X(-0.7), 0, 0)], 0.028, "steel", 6)
    # «языки пламени»: красные полосы от корня крыла к законцовке с завитком, по ПГО, стабилизаторам и спине
    W = ["wing"]
    for s in (1, -1):
        stripe("flame", W, [(9.0, s * 2.0), (10.6, s * 3.4), (12.0, s * 5.0), (13.4, s * 6.6), (14.6, s * 8.0)], [0.5, 0.75, 0.7, 0.55, 0.35], "red")
        stripe("flame", W, [(11.2, s * 2.3), (12.3, s * 3.6), (13.3, s * 5.0), (14.0, s * 6.2)], [0.45, 0.5, 0.35, 0.15], "red")
        stripe("flame", W, [(14.4, s * 3.2), (15.4, s * 5.0), (16.2, s * 7.0), (16.6, s * 8.3)], [0.4, 0.45, 0.35, 0.2], "red")
        stripe("flame", ["canard"], [(4.5, s * 0.9), (5.2, s * 2.0), (5.9, s * 2.9)], [0.4, 0.3, 0.2], "red")
        stripe("flame", ["stab"], [(16.6, s * 2.4), (17.6, s * 3.6), (18.6, s * 4.8)], [0.6, 0.5, 0.3], "red")
        stripe("flame", ["deck", "nacelle"], [(8.0, s * 1.2), (10.5, s * 1.6), (13.5, s * 1.9), (16.5, s * 1.8)], [0.25, 0.35, 0.3, 0.15], "red", off=0.02)
    finish("draft")


# ================================================================ «Почтальон» (босс-ракетоносец, 20 м, размах ~20 м)
def postman():
    scheme()
    fus = Body([
        (0.0, -0.03, 0.03, 0.03, 2.0), (0.6, -0.22, 0.2, 0.2, 2.0), (2.0, -0.48, 0.48, 0.45, 2.0),
        (3.8, -0.62, 0.66, 0.6, 2.1), (5.8, -0.66, 0.8, 0.68, 2.2), (8.0, -0.62, 0.8, 0.72, 2.4),
        (10.5, -0.55, 0.68, 0.7, 2.4), (13.5, -0.46, 0.56, 0.6, 2.4), (16.0, -0.38, 0.44, 0.45, 2.3),
        (17.5, -0.32, 0.36, 0.32, 2.2)])
    fus.build("fuselage", [(0.0, "radome"), (1.9, "paint")])
    deck = Body([(6.5, -0.35, 0.05, 0.85, 4.0), (8.8, -0.45, 0.22, 1.75, 4.5), (14.0, -0.48, 0.25, 1.8, 4.5),
                 (17.4, -0.42, 0.18, 1.6, 4.5), (19.0, -0.25, 0.06, 0.7, 3.0)])
    deck.build("deck", [(6.5, "paint")], step=0.4)
    for s in (1, -1):
        nac = Body([(6.2, -1.0, 0.05, 0.56, 4.5), (7.2, -1.02, 0.12, 0.6, 4.0), (10.0, -0.96, 0.24, 0.64, 3.0),
                    (14.5, -0.85, 0.32, 0.64, 2.4), (17.6, -0.76, 0.28, 0.6, 2.2), (18.6, -0.72, 0.22, 0.56, 2.1)], s * 1.15)
        nac.build("nacelle", [(6.2, "paint")], N=24, step=0.4)
        hole(nac, 6.2)
        nozzle("nozzle", 18.5, 19.9, s * 1.15, -0.25, 0.53, 0.47)
        # большое стреловидное крыло (плечевое), законцовка срезана
        st = [(5.6, s * 0.5, 0.15, 10.4), (9.4, s * 2.7, 0.15, 7.0), (14.0, s * 10.0, 0.05, 2.7)]
        surface("wing", [st[0], st[1], lerp_st(st[1], st[2], 0.5), lerp_st(st[1], st[2], 0.93, "red"), st[2]], "paint", 0.045)
        r3, t3 = (15.6, s * 1.75, -0.25, 3.9), (18.0, s * 5.4, -0.3, 1.8)
        surface("stab", [r3, lerp_st(r3, t3, 0.85, "red"), t3], "paint", 0.04)
        a = math.radians(12)
        r4 = (12.6, s * 1.2, 0.3, 4.6)
        t4 = (16.2, s * (1.2 + 3.6 * math.sin(a)), 0.3 + 3.6 * math.cos(a), 1.8)
        surface("fin", [r4, lerp_st(r4, t4, 0.85, "red"), t4], "paint", 0.045)
        # 4 ракеты под крылом: носы выступают за переднюю кромку (видно сверху), белые с красной головкой
        for y in (3.6, 5.4, 7.2, 8.9):
            dd = st[1][0] + (st[2][0] - st[1][0]) * (y - 2.7) / (10.0 - 2.7)   # передняя кромка на этом y
            zb = surf_z(["wing"], dd + 1.4, s * y, False)
            pylon("pylon", dd + 0.4, dd + 2.4, s * y, zb + 0.05, zb - 0.18)
            missile("missile", dd - 1.1, s * y, zb - 0.36, 4.0, 0.15, "missile", "red")
        # «молния» по крылу: красная с белой окантовкой (белая — снизу, шире)
        # точки «молнии»: (y, доля хорды от передней кромки) → (d, y) на внешней части крыла
        def on_wing(y, f):
            k = (y - 2.7) / (10.0 - 2.7)
            return (st[1][0] + (st[2][0] - st[1][0]) * k + f * (st[1][3] + (st[2][3] - st[1][3]) * k), s * y)
        bolt = [on_wing(y, f) for y, f in ((3.0, 0.5), (4.5, 0.32), (5.0, 0.6), (6.6, 0.38), (7.1, 0.62), (9.2, 0.42))]
        stripe("bolt_w", ["wing"], bolt, [0.95, 0.9, 0.9, 0.8, 0.75, 0.5], "white", off=0.012, sub=4)
        stripe("bolt", ["wing"], bolt, [0.55, 0.52, 0.52, 0.45, 0.42, 0.25], "red", off=0.02, sub=4)
    cb, cs = canopy("canopy", fus, 2.8, 9.4, 0.62, 0.52, peak=0.22)
    arch("canopy_frame", cs, 3)
    arch("canopy_frame", cs, 7)
    tube("pitot", [(X(0.2), 0, 0), (X(-0.6), 0, 0)], 0.028, "steel", 6)
    finish("postman")


K.reset()
{"interceptor": interceptor, "rival": rival, "draft": draft, "postman": postman}[PLANE]()
