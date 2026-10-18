"""Вражеский транспортно-боевой вертолёт «Сарыч» — по мотивам тяжёлого вертолёта классической схемы
(референсы Kanta 18.10.2026: /mnt/project-files/refs/helicopter/). Вымышленная машина: без звёзд, надписей,
номеров и опознавательных знаков. Окраска — как на референсах (правка Kanta 18.10): крупные пятна песочного
хаки и серо-зелёного, низ голубовато-серый; красных меток врага нет (TIP = "red" вернёт красные законцовки лопастей).
Вооружение: две фермы по бокам, на каждой три блока неуправляемых ракет (НАР) с сотами труб; курсовой пулемёт в носу.

Строится набором convoy_kit.py (детали из данных, запекание цвета и нормалей в Cycles), без генераторов.
Размеры в метрах по референсам (фюзеляж 18,2 м, несущий винт 21,3 м), в конце всё делится на 18,2:
длина фюзеляжа (нос — втулка рулевого винта) = 1, нос +X, низ колёс на z = 0.
Узлы GLB: rotor — несущий винт (вращение вокруг локальной вертикали, по часовой сверху),
          tail_rotor — рулевой винт (вращение вокруг своей оси, слева по борту).
Запуск: python3 helicopter.py <папка>   (→ helicopter.glb, helicopter.blend, helicopter_color/normal.png, кадры)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import convoy_kit as K
from convoy_kit import box, cyl, lathe, prism_z, loft, tube, tyre, rim
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

OUT = sys.argv[-1]
L = 18.2                 # длина фюзеляжа, м → 1
NOSE = L / 2             # нос на x = +9,1 м (центр фюзеляжа в начале координат)
K.reset()
# окраска врага: серо-оливковый камуфляж (пятна ~2–3 м), пыли меньше, чем у машин
# окраска по референсам Kanta (правка 18.10): крупные пятна песочного хаки и серо-зелёного, низ голубовато-серый
K.CAMO = [(0.33, 0.38, 0.335), (0.6, 0.585, 0.44), (0.3, 0.35, 0.31)]
K.CAMO_SCALE = 1.9
K.CAMO_STRETCH = (0.75, 1.0, 1.3)
K.BELLY = (0.46, 0.51, 0.55)
K.KINDS["paint"] = (K.CAMO[0], 0.1, 0.65, 0.3, True)
K.KINDS["olive"] = ((0.28, 0.31, 0.28), 0.2, 0.6, 0.2, False)      # блоки НАР
K.KINDS["yellow"] = ((0.78, 0.64, 0.2), 0.1, 0.6, 0.1, False)       # окантовка двери
K.KINDS["red"] = ((0.68, 0.17, 0.13), 0.1, 0.55, 0.15, False)        # enemy_red, как у транспортника
K.KINDS["blade"] = ((0.17, 0.175, 0.17), 0.2, 0.6, 0.1, False)       # лопасти
K.KINDS["lamp_green"] = ((0.1, 0.6, 0.25), 0.2, 0.3, 0.3, False)


def X(d):
    """Расстояние от носа, м → координата x (нос +X)"""
    return NOSE - d


def grp(name, pivot=None):
    K.group = name
    if name:
        K.pivots[name] = pivot


# ---------------------------------------------------------------- фюзеляж: сечения-«суперэллипсы»
# (d от носа, низ z, верх z, полуширина, показатель формы: 2 — овал, 3+ — «коробка» со скруглением)
ST = [(-0.08, 1.25, 1.5, 0.15, 2.0), (0.08, 0.98, 1.62, 0.5, 2.2), (0.3, 0.88, 1.72, 0.74, 2.4),
      (0.6, 0.83, 2.05, 0.92, 2.6), (0.95, 0.8, 2.42, 1.08, 2.8), (1.4, 0.78, 2.66, 1.18, 3.0),
      (2.1, 0.77, 2.84, 1.24, 3.2), (3.0, 0.77, 2.9, 1.25, 3.3), (8.8, 0.77, 2.9, 1.25, 3.3),
      (9.6, 0.86, 2.98, 1.22, 3.2), (10.4, 1.4, 3.2, 1.05, 3.0), (11.3, 2.25, 3.45, 0.72, 2.6),
      (12.3, 2.62, 3.5, 0.48, 2.2), (14.0, 2.76, 3.45, 0.38, 2.0), (16.4, 2.93, 3.4, 0.27, 2.0),
      (17.0, 2.98, 3.38, 0.22, 2.0)]

def _cr(p0, p1, p2, p3, t):
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def sec(d):
    """Параметры сечения на расстоянии d (сплайн Катмулла — Рома по таблице ST)"""
    ds = [s[0] for s in ST]
    d = min(max(d, ds[0]), ds[-1])
    i = max(0, min(len(ST) - 2, next((k for k in range(len(ST) - 1) if ds[k + 1] >= d), len(ST) - 2)))
    t = (d - ds[i]) / (ds[i + 1] - ds[i])
    out = []
    for j in range(1, 5):
        p0 = ST[max(i - 1, 0)][j]
        p1 = ST[i][j]
        p2 = ST[i + 1][j]
        p3 = ST[min(i + 2, len(ST) - 1)][j]
        out.append(_cr(p0, p1, p2, p3, t))
    return out   # zb, zt, w, n


def _se(c, n):
    return math.copysign(abs(c) ** (2.0 / n), c)


def surf(d, th, off=0.0):
    """Точка обшивки: th — угол сечения в градусах (0 — левый борт +Y, 90 — верх, 180 — правый, 270 — низ);
    off — отступ наружу по нормали"""
    zb, zt, w, n = sec(d)
    a = math.radians(th)
    zc, h = (zb + zt) / 2, (zt - zb) / 2
    y = w * _se(math.cos(a), n)
    z = zc + h * _se(math.sin(a), n)
    p = Vector((X(d), y, z))
    if off:
        e = 0.01
        pa = Vector((X(d), w * _se(math.cos(a + e), n), zc + h * _se(math.sin(a + e), n)))
        pd = surf(d + 0.05, th) if d < 16.9 else surf(d - 0.05, th)
        t1 = (pa - p).normalized()
        t2 = (pd - p).normalized() * (1 if d < 16.9 else -1)
        nn = t2.cross(t1).normalized()
        if nn.dot(Vector((0, p.y, p.z - zc))) < 0:
            nn = -nn
        p = p + nn * off
    return p


def ring(d, off=0.0, N=28):
    return [surf(d, 360.0 * k / N, off) for k in range(N)]


def patch(name, d0, d1, t0, t1, kind, off=0.025, nu=5, nv=5):
    """Лоскут на обшивке (стекло, панель, полоса): сетка по d и углу, приподнята на off"""
    secs = []
    for i in range(nu + 1):
        d = d0 + (d1 - d0) * i / nu
        row = [surf(d, t0 + (t1 - t0) * j / nv, off) for j in range(nv + 1)]
        secs.append(row)
    vs = [p for r in secs for p in r]
    f = []
    W = nv + 1
    for i in range(nu):
        for j in range(nv):
            f.append((i * W + j, i * W + j + 1, (i + 1) * W + j + 1, (i + 1) * W + j))
    return K._obj(name, vs, f, kind)


def side_y(d, z):
    """Полуширина обшивки на расстоянии d и высоте z (0 — выше/ниже сечения)"""
    zb, zt, w, n = sec(d)
    zc, h = (zb + zt) / 2, (zt - zb) / 2
    t = abs(z - zc) / h
    return 0.0 if t >= 1.0 else w * (1.0 - t ** n) ** (1.0 / n)


def _out(p, pa, pb, ref):
    nn = (pa - p).cross(pb - p).normalized()
    return -nn if nn.dot(ref) < 0 else nn


def side_pt(d, z, s, off=0.0):
    """Точка борта (s = +1 левый, −1 правый) на высоте z — окна, двери, полосы ровные по горизонтали"""
    p = Vector((X(d), s * side_y(d, z), z))
    if off:
        e = 0.02
        nn = _out(p, Vector((X(d + e), s * side_y(d + e, z), z)), Vector((X(d), s * side_y(d, z + e), z + e)), Vector((0, s, 0)))
        p = p + nn * off
    return p


def front_d(y, z):
    """Где по длине нос проходит через точку (y, z) спереди — поиск делением пополам"""
    lo, hi = -0.08, 3.0
    for _ in range(40):
        m = (lo + hi) / 2
        if side_y(m, z) <= abs(y):
            lo = m
        else:
            hi = m
    return (lo + hi) / 2


def front_pt(y, z, off=0.0):
    p = Vector((X(front_d(y, z)), y, z))
    if off:
        e = 0.02
        nn = _out(p, Vector((X(front_d(y + e, z)), y + e, z)), Vector((X(front_d(y, z + e)), y, z + e)), Vector((1, 0, 0)))
        p = p + nn * off
    return p


def grid(name, fn, u0, u1, v0, v1, kind, nu=4, nv=4):
    rows = [[fn(u0 + (u1 - u0) * i / nu, v0 + (v1 - v0) * j / nv) for j in range(nv + 1)] for i in range(nu + 1)]
    vs = [p for r in rows for p in r]
    W = nv + 1
    f = [(i * W + j, i * W + j + 1, (i + 1) * W + j + 1, (i + 1) * W + j) for i in range(nu) for j in range(nv)]
    return K._obj(name, vs, f, kind)


_BVH = []


def hit(o, dr, off):
    """Точка обшивки по лучу из o в направлении dr, приподнятая по нормали на off"""
    if not _BVH:
        ob = bpy.data.objects["fuselage"]
        mw = ob.matrix_world
        _BVH.append(BVHTree.FromPolygons([mw @ v.co for v in ob.data.vertices], [tuple(pl.vertices) for pl in ob.data.polygons]))
    loc, nn, _, _ = _BVH[0].ray_cast(o, dr, 50.0)
    if loc is None:
        return o + dr * 5.0
    if nn.dot(dr) > 0:
        nn = -nn
    return loc + nn * off


def window_ray(name, c, dr, uax, u0, u1, z0, z1, kind="glass", off=0.022, frame=0.05, nu=7, nv=6):
    """Окно: сетка в плоскости, спроецированная лучами dr на обшивку — края ровные, форма повторяет корпус"""
    dr = Vector(dr).normalized()
    uax = Vector(uax).normalized()
    base = Vector(c) - dr * 6.0

    def pt(o):
        return lambda u, z: hit(base + uax * u + Vector((0, 0, z - c[2])), dr, o)
    lo, hi = min(u0, u1), max(u0, u1)
    grid(name + "_frame", pt(off - 0.012), lo - frame, hi + frame, z0 - frame, z1 + frame, "dark", nu, nv)
    grid(name, pt(off), lo, hi, z0, z1, kind, nu, nv)


def window_side(name, d0, d1, z0, z1, s, kind="glass", off=0.022, frame=0.05, nu=7, nv=6):
    """Окно на борту (луч поперёк корпуса)"""
    window_ray(name, (X(d0), 0.0, z0), (0, -s, 0), (-1, 0, 0), 0.0, d1 - d0, z0, z1, kind, off, frame, nu, nv)


def window_front(name, y0, y1, z0, z1, kind="glass", off=0.022, frame=0.05, nu=7, nv=6):
    """Окно спереди носа (луч вдоль корпуса)"""
    window_ray(name, (X(-1.0), 0.0, z0), (-1, 0, 0), (0, 1, 0), y0, y1, z0, z1, kind, off, frame, nu, nv)


grp("")
ds = [-0.05, 0.05, 0.15, 0.3, 0.5, 0.75, 1.0, 1.3, 1.65, 2.0, 2.4, 3.0, 4.0, 5.5, 7.0, 8.5, 9.0, 9.5, 9.9,
      10.3, 10.75, 11.2, 11.7, 12.2, 13.0, 14.0, 15.0, 16.0, 16.6, 17.0]
loft("fuselage", [ring(d) for d in ds], "paint")

# остекление кабины (по референсам): лента окон на средней высоте носа — два больших лобовых стекла
# с переплётом посередине, угловые стёкла, сдвижной блистер и второе боковое окно; снизу носа — малые окна
WZ0, WZ1 = 1.66, 2.28
for s in (1, -1):
    window_front("wind", s * 0.05, s * 0.5, WZ0, WZ1 - 0.08, nu=8, nv=6)
    # угловое стекло — по борту, от края лобового до блистера (на скруглении носа фронтальная проекция косит)
    c = front_pt(0.72 * s, (WZ0 + WZ1) / 2)
    window_ray("wind_corner", c, (-1, -s, 0), (s, -1, 0), -0.15, 0.15, WZ0, WZ1 - 0.2, frame=0.04)
    window_side("blister", 0.84, 1.3, WZ0, WZ1 - 0.08, s)
    window_side("side_win", 1.38, 1.86, WZ0 - 0.1, WZ1, s)
    window_front("chin", s * 0.28, s * 0.62, 1.0, 1.28, nu=5, nv=3)
# круглые окна грузовой кабины: по пять на борт, на одной высоте
for side in (1, -1):
    for d in (4.75, 5.35, 6.0, 6.65, 7.25):
        p = side_pt(d, 1.87, side, 0.01)
        cyl("win", tuple(p), 0.17, 0.05, "glass", "Y", 12)
        cyl("win_rim", tuple(p - Vector((0, side * 0.005, 0))), 0.21, 0.035, "dark", "Y", 12)
# сдвижная дверь слева: жёлтая окантовка, шов, круглое окно, направляющая сверху
DD0, DD1, DZ0, DZ1 = 2.4, 3.6, 0.88, 2.24
for a, b, z0, z1 in ((DD0 - 0.05, DD0, DZ0, DZ1), (DD1, DD1 + 0.05, DZ0, DZ1), (DD0 - 0.05, DD1 + 0.05, DZ1, DZ1 + 0.05),
                     (DD0 - 0.05, DD1 + 0.05, DZ0 - 0.05, DZ0)):
    grid("door_line", lambda d, z: side_pt(d, z, 1, 0.012), a, b, z0, z1, "yellow", 2, 2)
grid("door_seam", lambda d, z: side_pt(d, z, 1, 0.013), DD1 - 0.02, DD1, DZ0, DZ1, "black", 1, 3)
p = side_pt(2.85, 1.87, 1, 0.01)
cyl("door_win", tuple(p), 0.16, 0.04, "glass", "Y", 12)
box("door_rail", tuple(side_pt(4.4, 2.42, 1, 0.04)), (3.2, 0.06, 0.07), "steel", 0.01)
# створки грузового люка сзади: шов по центру и по краю
for th in (205, 335):
    patch("cargo_seam", 9.6, 9.65, th - 25, th + 25, "black", 0.012, 1, 6)
patch("cargo_seam", 9.65, 11.0, 268.8, 271.2, "black", 0.012, 6, 1)

# ---------------------------------------------------------------- двигатели и редуктор сверху
CW = [(2.0, 2.6, 3.15, 0.86, 2.6), (2.35, 2.6, 3.62, 1.0, 3.0), (3.1, 2.6, 3.84, 1.06, 3.2),
      (6.5, 2.6, 3.94, 1.05, 3.2), (7.6, 2.6, 4.04, 0.98, 3.0), (8.7, 2.6, 3.95, 0.86, 2.8),
      (9.7, 2.6, 3.72, 0.66, 2.6), (10.7, 2.6, 3.52, 0.42, 2.4), (11.4, 2.6, 3.47, 0.25, 2.2)]


def cring(c, N=24):
    d, zb, zt, w, n = c
    zc, h = (zb + zt) / 2, (zt - zb) / 2
    return [Vector((X(d), w * _se(math.cos(2 * math.pi * k / N), n), zc + h * _se(math.sin(2 * math.pi * k / N), n))) for k in range(N)]


loft("cowl", [cring(c) for c in CW], "paint")
# разделка между двигателями и решётки по бокам
box("cowl_groove", (X(5.0), 0, 3.93), (4.6, 0.05, 0.04), "dark", 0.0)
for side in (1, -1):
    for d in (3.2, 4.1, 5.0):
        box("louver", (X(d), side * 1.05, 3.3), (0.55, 0.05, 0.22), "dark", 0.01)
    # воздухозаборники с пылезащитными «грибками»
    lathe("intake", [(0.38, 0.0), (0.4, 0.06), (0.34, 0.1), (0.001, 0.12)], (X(2.0), side * 0.47, 3.22), "dark", "X", 16)
    lathe("dust_dome", [(0.3, 0.1), (0.31, 0.2), (0.27, 0.36), (0.17, 0.47), (0.001, 0.51)],
          (X(2.01), side * 0.47, 3.22), "steel", "X", 16)
    # выхлопные патрубки: назад-вбок-вниз
    tube("exhaust", [(X(6.3), side * 0.92, 3.5), (X(6.75), side * 1.18, 3.42), (X(7.2), side * 1.42, 3.24)], 0.27, "steel", 12)
    cyl("exhaust_in", (X(7.22), side * 1.43, 3.23), 0.22, 0.04, "black",
        (Vector((X(7.2), side * 1.42, 3.72)) - Vector((X(6.75), side * 1.18, 3.9))).normalized()[:], 12)
# вентилятор маслорадиатора за редуктором — круглая решётка вперёд
lathe("fan_ring", [(0.3, 0.0), (0.32, 0.08), (0.001, 0.09)], (X(7.45), 0, 4.0), "dark", "X", 16)
# обтекатель редуктора у вала
lathe("gearbox", [(0.6, 0.0), (0.52, 0.14), (0.3, 0.26), (0.2, 0.32)], (X(5.3), 0, 3.88), "paint", "Z", 16, cap1=True)

# ---------------------------------------------------------------- килевая балка и рулевой винт
PY = [(15.9, 3.15, 0.36, 0.25), (16.9, 3.42, 0.37, 0.18), (17.5, 3.95, 0.37, 0.15), (17.9, 4.62, 0.35, 0.13),
      (18.1, 5.15, 0.3, 0.11), (18.2, 5.42, 0.18, 0.08)]


def pylon(rows, k=1.0, kind="paint", name="pylon"):
    """Килевая балка: сечения перпендикулярно оси PY, профиль — капля (передняя кромка круглее)"""
    secs = []
    for i in rows:
        d, z, a, b = PY[i]
        p = Vector((X(d), 0, z))
        q = Vector((X(PY[min(i + 1, len(PY) - 1)][0]), 0, PY[min(i + 1, len(PY) - 1)][1]))
        o = Vector((X(PY[max(i - 1, 0)][0]), 0, PY[max(i - 1, 0)][1]))
        t = (q - o).normalized()
        nrm = Vector((-t.z, 0, t.x))      # перпендикуляр в плоскости XZ (вперёд-вверх)
        s = []
        for j in range(16):
            ang = 2 * math.pi * j / 16
            ca = math.cos(ang)
            r = a * k * (1.0 if ca > 0 else 1.2)
            s.append(p + nrm * (ca * r) + Vector((0, b * k * math.sin(ang), 0)))
        secs.append(s)
    loft(name, secs, kind)


pylon(range(len(PY)))
# редуктор рулевого винта слева сверху
cyl("tr_gear", (X(17.95), 0.16, 4.82), 0.2, 0.32, "paint", "Y", 14)
lathe("tr_gear_cap", [(0.2, 0.0), (0.12, 0.08), (0.001, 0.1)], (X(17.95), 0.32, 4.82), "steel", "Y", 14)
# стабилизатор под балкой: трапеция, стреловидная передняя кромка, красные законцовки
for side in (1, -1):
    prof = [(X(16.0), 0.0), (X(16.35), side * 1.32), (X(16.75), side * 1.32), (X(16.95), 0.0)]
    prism_z("stab", prof, 2.95, 3.04, "paint", 0.015)
    prism_z("stab_tip", [(X(16.35), side * 1.32), (X(16.42), side * 1.62), (X(16.72), side * 1.62), (X(16.75), side * 1.32)], 2.95, 3.04, "paint", 0.015)
# хвостовая опора
tube("tail_skid", [(X(15.1), 0, 3.0), (X(15.45), 0, 2.4), (X(15.75), 0, 2.25)], 0.05, "steel", 8)
box("tail_skid_pad", (X(15.75), 0, 2.24), (0.25, 0.14, 0.04), "steel", 0.01)
# антенны и огни
lathe("beacon", [(0.09, 0.0), (0.08, 0.08), (0.001, 0.12)], (X(13.4), 0, 3.42), "lamp_red", "Z", 10)
lathe("beacon2", [(0.09, 0.0), (0.08, -0.08), (0.001, -0.12)], (X(4.0), 0, 0.8), "lamp_red", "Z", 10)
for side, k in ((1, "lamp_red"), (-1, "lamp_green")):
    cyl("nav", tuple(side_pt(2.3, 2.55, side, 0.02)), 0.07, 0.06, k, "Y", 8)
lathe("landing_lamp", [(0.15, 0.04), (0.14, -0.02), (0.001, -0.03)], (X(1.4), 0.35, 0.86), "lamp", "Z", 12)
lathe("landing_lamp", [(0.15, 0.04), (0.14, -0.02), (0.001, -0.03)], (X(1.4), -0.35, 0.86), "lamp", "Z", 12)

# ---------------------------------------------------------------- шасси
for side in (1, -1):
    c = (X(7.3), side * 2.2, 0.45)
    tyre("main_tyre", c, 0.45, 0.32, 0.27, lugs=8, chevron=False, depth=0.02)
    rim("main_rim", c, 0.27, 0.32, side, "steel", bolts=6, style="plain")
    hub_in = (X(7.3), side * 2.02, 0.45)
    tube("oleo", [hub_in, (X(7.3), side * 1.6, 1.25), (X(7.3), side * 1.24, 2.0)], 0.085, "steel", 10)
    tube("oleo_sleeve", [(X(7.3), side * 1.5, 1.45), (X(7.3), side * 1.26, 1.95)], 0.12, "paint", 10)
    tube("v_strut", [hub_in, (X(6.6), side * 0.75, 0.82)], 0.06, "dark", 8)
    tube("v_strut", [hub_in, (X(8.0), side * 0.75, 0.82)], 0.06, "dark", 8)
    box("sponson", (X(7.3), side * 1.22, 2.02), (0.6, 0.12, 0.25), "paint", 0.03)
for side in (1, -1):
    c = (X(2.7), side * 0.27, 0.32)
    tyre("nose_tyre", c, 0.32, 0.2, 0.18, lugs=7, chevron=False, depth=0.02)
    rim("nose_rim", c, 0.18, 0.2, side, "steel", bolts=5, style="plain")
tube("nose_strut", [(X(2.7), 0, 0.32), (X(2.62), 0, 0.62), (X(2.55), 0, 0.88)], 0.07, "steel", 10)
box("nose_axle", (X(2.7), 0, 0.32), (0.08, 0.4, 0.08), "dark", 0.01)

# ---------------------------------------------------------------- топливные баки по бортам
for side, d0, d1 in ((1, 3.6, 6.2), (-1, 3.6, 6.6)):
    lathe("tank", [(0.001, 0.0), (0.24, 0.06), (0.4, 0.25), (0.45, 0.6), (0.45, d1 - d0 - 0.6), (0.4, d1 - d0 - 0.25),
                   (0.24, d1 - d0 - 0.06), (0.001, d1 - d0)], (X(d1), side * 1.55, 1.08), "paint", "X", 18)
    for d in (d0 + 0.5, d1 - 0.5):
        box("tank_strap", (X(d), side * 1.55, 1.08), (0.08, 0.9, 0.9), "dark", 0.04)

# ---------------------------------------------------------------- фермы с блоками НАР
FD = 5.9            # где ферма по длине
for side in (1, -1):
    s = side
    # балка: от борта наружу, к концу тоньше
    loft("farm", [[Vector((X(FD) + dx, s * 1.15, 1.75 + dz)) for dx, dz in ((0.2, 0.1), (-0.2, 0.1), (-0.2, -0.1), (0.2, -0.1))],
                  [Vector((X(FD) + dx, s * 3.7, 1.75 + dz)) for dx, dz in ((0.14, 0.07), (-0.14, 0.07), (-0.14, -0.07), (0.14, -0.07))]],
         "paint", 0.02)
    # подкосы: от конца балки вверх к борту, снизу к днищу
    tube("brace", [(X(FD), s * 3.55, 1.8), (X(FD), s * 1.2, 2.6)], 0.045, "dark", 8)
    tube("brace", [(X(FD) + 0.5, s * 2.4, 1.78), (X(FD) + 0.9, s * 1.2, 2.5)], 0.04, "dark", 8)
    tube("brace", [(X(FD), s * 2.6, 1.67), (X(FD), s * 1.05, 0.95)], 0.05, "dark", 8)
    for y in (2.3, 2.88, 3.46):
        y *= s
        xb, xf = X(6.9), X(4.85)
        # блок: соты спереди, цилиндр, конус сзади
        lathe("pod", [(0.001, 0.0), (0.09, 0.03), (0.2, 0.18), (0.27, 0.42), (0.27, 1.92), (0.25, 2.0), (0.2, 2.02)],
              (xb, y, 1.33), "olive", "X", 16)
        cyl("pod_face", (xf + 0.01, y, 1.33), 0.205, 0.04, "steel", "X", 16)
        for k in range(7):
            ry, rz = (0.0, 0.0) if k == 0 else (0.115 * math.cos(math.pi * k / 3), 0.115 * math.sin(math.pi * k / 3))
            cyl("pod_tube", (xf + 0.025, y + ry, 1.33 + rz), 0.05, 0.02, "black", "X", 8)
        box("pod_band", (xb + 1.55, y, 1.33), (0.08, 0.57, 0.57), "dark", 0.02)
        box("pylon", (X(FD), y, 1.62), (0.6, 0.1, 0.12), "dark", 0.015)

# курсовой пулемёт в носу
tube("nose_gun", [(X(0.4), 0.0, 1.32), (X(-0.75), 0.0, 1.32)], 0.032, "black", 8)
lathe("nose_gun_mount", [(0.12, 0.0), (0.11, 0.18), (0.001, 0.2)], (X(0.25), 0, 1.32), "dark", "X", 12)
# трубка ПВД (приёмник давления)
tube("pitot", [tuple(side_pt(0.6, 1.45, 1, -0.02)), (X(-0.4), 0.62, 1.45)], 0.02, "steel", 6)

# ---------------------------------------------------------------- несущий винт (узел rotor)
HUB = (X(5.3), 0.0, 4.75)
grp("rotor", HUB)
cyl("mast", (HUB[0], 0, 4.33), 0.15, 0.85, "steel", "Z", 12)
cyl("swash", (HUB[0], 0, 4.22), 0.34, 0.06, "steel", "Z", 16)
lathe("hub", [(0.42, -0.12), (0.45, 0.0), (0.42, 0.12), (0.26, 0.2), (0.001, 0.24)], HUB, "steel", "Z", 16, cap0=True)
TIP = "blade"        # законцовки лопастей; "red" — красные метки врага (до правки 18.10)
AF = [(0.5, 0.0), (0.3, 0.075), (0.0, 0.09), (-0.4, 0.045), (-0.5, 0.0), (-0.4, -0.025), (0.0, -0.035), (0.3, -0.04)]


def blade(name, c, ang, r0, r1, chord, kind, up=(0, 0, 1), cone=0.035, red_from=None, n_mid=3):
    """Лопасть: лофт крылового профиля AF от радиуса r0 до r1 по направлению ang (в плоскости, перпендикулярной up);
    передняя кромка — по ходу вращения (по часовой сверху: для несущего); red_from — радиус начала красной законцовки"""
    c = Vector(c)
    w = Vector(up).normalized()
    u0 = Vector((1, 0, 0)) if abs(w.x) < 0.9 else Vector((0, 0, 1))
    u = (u0 - w * u0.dot(w)).normalized()
    v = w.cross(u)
    dirv = (u * math.cos(ang) + v * math.sin(ang))
    lead = -w.cross(dirv)          # по часовой, если смотреть со стороны up
    def S(r, ch):
        o = c + dirv * r + w * (r * cone)
        return [o + lead * (a * ch) + w * (t * ch) for a, t in AF]
    rr = [r0 + (r1 - r0) * i / (n_mid + 1) for i in range(n_mid + 2)]
    if red_from:
        rr = [r for r in rr if r < red_from] + [red_from]
        loft(name, [S(r, chord) for r in rr], kind)
        loft(name + "_tip", [S(red_from, chord), S(r1 - 0.05, chord), S(r1, chord * 0.7)], TIP)
    else:
        loft(name, [S(r, chord) for r in rr], kind)
    # комель: стакан крепления
    tube(name + "_root", [c + dirv * (r0 * 0.4) + w * 0.0, c + dirv * (r0 + 0.1) + w * (r0 * cone)], chord * 0.18, "steel", 8)


for i in range(5):
    a = 2 * math.pi * i / 5
    blade("blade", HUB, a, 0.75, 10.65, 0.52, "blade", red_from=9.95)
    # гаситель колебаний у втулки
    dv = Vector((math.cos(a), math.sin(a), 0))
    box("damper", tuple(Vector(HUB) + dv * 0.55 + Vector((0, 0, 0.12))), (0.35, 0.1, 0.1), "dark", 0.01,
        rot=Matrix.Rotation(a, 3, "Z"))

# ---------------------------------------------------------------- рулевой винт (узел tail_rotor), слева
TR = (X(17.95), 0.48, 4.82)
grp("tail_rotor", TR)
lathe("tr_hub", [(0.13, -0.08), (0.14, 0.0), (0.001, 0.1)], TR, "steel", "Y", 12, cap0=True)
for i in range(3):
    blade("tr_blade", TR, 2 * math.pi * i / 3 + 0.3, 0.18, 1.95, 0.3, "blade", up=(0, 1, 0), cone=0.0, red_from=1.62, n_mid=1)
grp("")

# ---------------------------------------------------------------- метры → длина 1
SC = 1.0 / L
M = Matrix.Scale(SC, 4)
for o in K.parts:
    o.data.transform(M)
    for md in o.modifiers:
        if md.type == "BEVEL":
            md.width *= SC
for k in list(K.pivots):
    K.pivots[k] = tuple(v * SC for v in K.pivots[k])

root, tris = K.bake_export("helicopter", OUT, tex=int(os.environ.get("TEX", "1024")))
if not os.environ.get("NOPREVIEW"):
    K.preview(OUT, "helicopter", 1.5)
print("DONE tris", tris)
