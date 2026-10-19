"""Тест 3.5-s8 (блок air_b): летающая техника кодом вместо битых моделей Meshy (замечание Kanta 19.10:
«транспортник — битая модель, неровные полигоны», «все модели летающей техники противника кривые»).
Модели: вражеский транспортник (e_transport), ракетоносец (e_carrier), дрон (e_drone), дрон-камикадзе
(e_kamikaze) и свой заправщик (a_tanker). Силуэт, размеры по виду сверху (= спрайт), роль и окраска — как у
прежних моделей; машины вымышленные, «по мотивам», без знаков и надписей.

Строится набором convoy_kit.py, как вертолёт helicopter.py: фюзеляж — лофт по сечениям-«суперэллипсам»
(сплайн Катмулла — Рома по таблице, без бугров), крылья и оперение — лофт крылового профиля с круглой
законцовкой, гондолы и коки — тела вращения; цвет и нормали со скруглёнными кромками запекаются в одну
текстуру. Окраска матовая (Kanta 19.10): roughness 0.88, metallic 0, приглушённые цвета.

Оси: длина 1, нос +X, верх +Z, левое крыло +Y; по высоте модель центрируется по габариту (как после
model_lab prep). Узлы GLB: у транспортника винты prop_1…prop_4 (точка вращения — ось винта, вращение вокруг X);
у заправщика штанга Boom / BoomTube / BoomTip — достраивается tanker_boom.py (см. ниже).

Запуск (bpy 5.x):  python3 enemy_air_big.py <модель> <папка>
  модель: transport | carrier | drone | kamikaze | tanker
  → <папка>/<модель>.glb (+ .blend, текстуры). Дальше:
  transport/carrier/drone/kamikaze: cp <папка>/<модель>.glb game/models/battle/fh_battle_e_<модель>.glb
  tanker: python3 tanker_boom.py <папка>/tanker.glb game/models/battle/fh_battle_a_tanker.glb 20000
Переменные: TEX — размер текстуры (по умолчанию 1024, у дрона и камикадзе 512); PREVIEW=1 — кадры Cycles."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import convoy_kit as K
from convoy_kit import box, cyl, lathe, loft, tube
from mathutils import Vector, Matrix

MODEL, OUT = sys.argv[-2], sys.argv[-1]
K.reset()
K.EDGE_K = 0.35          # длина модели 1 = 8–35 м: кромки и углы мельче, чем у машин конвоя
K.AO_K = 0.6

# ---------------------------------------------------------------- окраска
# противник — прежняя схема (тёмно-серый металл с красными метками врага), но матовая и приглушённая:
# серый с оливковым оттенком, крупные мягкие пятна чуть темнее, низ светлее; красный — кирпичный
# (цвета линейные, как в convoy_kit: 0.1 ≈ 0.35 sRGB)
ENEMY_CAMO = [(0.1, 0.104, 0.095), (0.07, 0.074, 0.066), (0.13, 0.127, 0.108)]
ENEMY_BELLY = (0.17, 0.18, 0.185)
ENEMY_RED = (0.34, 0.06, 0.038)
# свой заправщик — светло-серый (прежний белый был «пластиком»)
OWN_CAMO = [(0.42, 0.44, 0.445), (0.41, 0.43, 0.437), (0.43, 0.447, 0.45)]   # почти ровный, без пятен
OWN_BELLY = (0.33, 0.35, 0.37)


def palette(camo, belly, scale):
    K.CAMO = camo
    K.BELLY = belly
    K.CAMO_SCALE = scale
    K.CAMO_STRETCH = (0.6, 1.0, 1.0)       # пятна вытянуты вдоль фюзеляжа
    # (цвет, металл, шероховатость, пыль, камуфляж): пыли снизу у самолётов нет (модель по высоте в нуле)
    # корпус — свой вид «hull»: у «paint» в convoy_kit светлые потёртости по кромкам (на тёмно-сером — белые искры)
    K.KINDS["hull"] = (camo[0], 0.0, 0.88, 0.0, True)
    K.KINDS["red"] = (ENEMY_RED, 0.0, 0.85, 0.0, False)
    K.KINDS["orange"] = ((0.46, 0.13, 0.03), 0.0, 0.85, 0.0, False)
    K.KINDS["dark"] = ((0.11, 0.11, 0.105), 0.1, 0.8, 0.0, False)
    K.KINDS["steel"] = ((0.27, 0.265, 0.255), 0.3, 0.6, 0.0, False)
    K.KINDS["black"] = ((0.025, 0.025, 0.025), 0.0, 0.8, 0.0, False)
    K.KINDS["radome"] = ((0.05, 0.052, 0.05), 0.0, 0.85, 0.0, False)
    K.KINDS["olive"] = ((0.09, 0.09, 0.065), 0.0, 0.85, 0.0, False)
    K.KINDS["glass"] = ((0.05, 0.065, 0.075), 0.0, 0.1, 0.0, False)
    K.KINDS["lamp_green"] = ((0.1, 0.5, 0.22), 0.0, 0.3, 0.0, False)


def grp(name, pivot=None):
    K.group = name
    if name:
        K.pivots[name] = pivot


def _cr(p0, p1, p2, p3, t):
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def _se(c, n):
    return math.copysign(abs(c) ** (2.0 / n), c)


class Body:
    """Тело по сечениям-«суперэллипсам»: строки (x, низ z, верх z, полуширина, показатель формы 2 — овал,
    3+ — «коробка» со скруглением), от носа к хвосту; между строками — сплайн Катмулла — Рома (гладко, без бугров).
    yc — смещение оси по Y (гондолы, обтекатели сбоку)."""

    def __init__(self, rows, yc=0.0):
        self.R = sorted(rows, key=lambda r: -r[0])
        self.yc = yc

    def sec(self, x):
        R = self.R
        xs = [r[0] for r in R]
        x = max(min(x, xs[0]), xs[-1])
        i = max(0, min(len(R) - 2, next((k for k in range(len(R) - 1) if xs[k + 1] <= x), len(R) - 2)))
        t = (xs[i] - x) / (xs[i] - xs[i + 1])
        out = []
        for j in range(1, 5):
            p0, p1, p2, p3 = R[max(i - 1, 0)][j], R[i][j], R[i + 1][j], R[min(i + 2, len(R) - 1)][j]
            out.append(_cr(p0, p1, p2, p3, t))
        return out

    def surf(self, x, th, off=0.0):
        """th — угол сечения, ° (0 — левый борт +Y, 90 — верх, 180 — правый, 270 — низ); off — отступ наружу"""
        zb, zt, w, n = self.sec(x)
        a = math.radians(th)
        zc, h = (zb + zt) / 2, (zt - zb) / 2
        ca, sa = math.cos(a), math.sin(a)
        y = w * _se(ca, n)
        z = zc + h * _se(sa, n)
        if off:
            # нормаль суперэллипса в сечении: (|cos|^(2/n-1)… ) — приближённо по градиенту
            gy = abs(ca) ** max(2.0 - 2.0 / n, 0.0) * (1 if ca >= 0 else -1) / max(w, 1e-4)
            gz = abs(sa) ** max(2.0 - 2.0 / n, 0.0) * (1 if sa >= 0 else -1) / max(h, 1e-4)
            l = math.hypot(gy, gz) or 1.0
            y += off * gy / l
            z += off * gz / l
        return Vector((x, self.yc + y, z))

    def ring(self, x, N=32, off=0.0):
        return [self.surf(x, 360.0 * k / N, off) for k in range(N)]

    def build(self, name, xs, kind="hull", N=32, bands=(), off=0.0, caps=False):
        """Лофт по станциям xs (от носа к хвосту); bands — [(x_нос, x_хвост, вид)] — участки другого цвета
        (красные кольца, обтекатель РЛС): лофт режется на куски по тем же сечениям, шва по форме нет"""
        xs = sorted(set([round(v, 5) for v in xs] + [round(b, 5) for bb in bands for b in bb[:2]]), reverse=True)

        def kind_at(xm):
            for a, b, k in bands:
                if b <= xm <= a:
                    return k
            return kind
        segs = []
        for i in range(len(xs) - 1):
            k = kind_at((xs[i] + xs[i + 1]) / 2)
            if segs and segs[-1][0] == k:
                segs[-1][1].append(xs[i + 1])
            else:
                segs.append([k, [xs[i], xs[i + 1]]])
        for k, sx in segs:
            loft(name, [self.ring(x, N, off) for x in sx], k, caps=caps)

    def patch(self, name, x0, x1, t0, t1, kind, off=0.0015, nu=4, nv=5):
        rows = [[self.surf(x0 + (x1 - x0) * i / nu, t0 + (t1 - t0) * j / nv, off) for j in range(nv + 1)] for i in range(nu + 1)]
        vs = [p for r in rows for p in r]
        W = nv + 1
        f = [(i * W + j, i * W + j + 1, (i + 1) * W + j + 1, (i + 1) * W + j) for i in range(nu) for j in range(nv)]
        return K._obj(name, vs, f, kind)


def stations(x0, x1, n, k=1.0):
    """n+1 станций от x0 до x1; k > 1 — гуще у x0 (у носа)"""
    return [x0 + (x1 - x0) * (i / n) ** k for i in range(n + 1)]


def airfoil(n=10, camber=0.02):
    """Замкнутый профиль (доли хорды): [(x от передней кромки, z)], задняя кромка острая. Толщина — множитель
    к NACA 00xx с t = 1 (умножается на t сечения)"""
    xs = [0.5 * (1 - math.cos(math.pi * i / n)) for i in range(n + 1)]

    def yt(x):
        return 5 * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)

    def yc(x):
        return camber * 4 * x * (1 - x)
    up = [(x, yc(x), yt(x)) for x in reversed(xs)]           # от задней кромки к передней
    lo = [(x, yc(x), -yt(x)) for x in xs[1:-1]]              # от передней к задней, без повтора
    return up + lo


AF = airfoil(10, 0.02)
AF0 = airfoil(10, 0.0)
AFP = airfoil(4, 0.0)          # лопасти винтов — грубее


def surface(name, root, tip, kind="hull", n=4, bands=(), mirror=True, camber=True, round_tip=True, up=None):
    """Крыло / оперение: root, tip — (передняя кромка (x, y, z), хорда, отн. толщина). Хорда — вдоль −X.
    Толщина — поперёк плоскости размаха (у киля — по Y). bands — [(s0, s1, вид)] по доле размаха
    (красные законцовки, полосы); round_tip — скруглённая законцовка (ещё одно сечение потоньше)."""
    r0, c0, t0 = Vector(root[0]), root[1], root[2]
    r1, c1, t1 = Vector(tip[0]), tip[1], tip[2]
    sd = (r1 - r0)
    sd.x = 0.0
    sd.normalize()
    upv = Vector(up) if up is not None else Vector((1, 0, 0)).cross(sd).normalized()
    if upv.z < -0.01 or (abs(upv.z) <= 0.01 and upv.y < 0):
        upv = -upv
    prof = AF if camber else AF0

    def S(s, tk=1.0, ck=1.0, dx=0.0):
        le = r0.lerp(r1, s) + Vector((-dx, 0, 0))
        c = (c0 + (c1 - c0) * s) * ck
        t = (t0 + (t1 - t0) * s) * tk
        return [le + Vector((-xc * c, 0, 0)) + upv * (zc * c + tz * c * t) for xc, zc, tz in prof]
    cuts = sorted(set([0.0, 1.0] + [i / n for i in range(1, n)] + [b for bb in bands for b in bb[:2]]))

    def kind_at(sm):
        for a, b, k in bands:
            if a <= sm <= b:
                return k
        return kind
    pieces = []
    for i in range(len(cuts) - 1):
        k = kind_at((cuts[i] + cuts[i + 1]) / 2)
        if pieces and pieces[-1][0] == k:
            pieces[-1][1].append(cuts[i + 1])
        else:
            pieces.append([k, [cuts[i], cuts[i + 1]]])
    out = []
    for pi, (k, ss) in enumerate(pieces):
        secs = [S(s) for s in ss]
        if round_tip and pi == len(pieces) - 1:
            # законцовка: два сечения короче и тоньше, чуть дальше по размаху
            span = (r1 - r0).length
            e = sd * (0.012 * max(span, 0.1))
            secs.append([p + e * 0.6 for p in S(1.0, 0.7, 0.93, 0.03 * c1)])
            secs.append([p + e for p in S(1.0, 0.25, 0.8, 0.08 * c1)])
        out.append((k, secs))
    for side in ((1, -1) if mirror else (1,)):
        for k, secs in out:
            ss = [[Vector((p.x, p.y * side, p.z)) for p in s] for s in secs]
            loft(name, ss, k, caps=True)


def pod(name, x0, x1, y, z, r, kind="hull", nose_kind=None, nose_len=0.0, n=16, tail=0.25, nose=0.3):
    """Тело вращения вдоль X (гондола, бак, ракета): от x0 (нос) до x1 (хвост), радиус r;
    nose_kind — другой цвет носа на длину nose_len"""
    L = x0 - x1
    prof = []
    for i in range(7):
        t = i / 6.0
        prof.append((r * math.sin(t * math.pi / 2) ** 0.6 if t > 0 else 0.0005, -t * L * nose))
    prof += [(r, -L * (1 - tail))]
    for i in range(1, 6):
        t = i / 5.0
        prof.append((max(r * math.cos(t * math.pi / 2) ** 0.8, 0.0005 if i == 5 else 0.0), -L * (1 - tail) - t * L * tail))
    prof = [(max(rr, 0.0005), dd) for rr, dd in prof]
    c = (x0, y, z)
    if nose_kind and nose_len > 0:
        a = [p for p in prof if -p[1] <= nose_len + 1e-6]
        rn = _interp_r(prof, nose_len)
        a.append((rn, -nose_len))
        b = [(rn, -nose_len)] + [p for p in prof if -p[1] > nose_len + 1e-6]
        lathe(name + "_nose", a, c, nose_kind, "X", n)
        lathe(name, b, c, kind, "X", n)
    else:
        lathe(name, prof, c, kind, "X", n)


def _interp_r(prof, d):
    for (r0, t0), (r1, t1) in zip(prof, prof[1:]):
        if -t0 <= d <= -t1:
            k = (d + t0) / ((t0 - t1) or 1)
            return r0 + (r1 - r0) * k
    return prof[-1][0]


def prop(name, c, r, blades=4, chord=0.012, pitch=35.0, kind="dark", start=0.4):
    """Воздушный винт с осью вдоль X в точке c: лопасти — лофт тонкого профиля, крутка от комля к концу"""
    c = Vector(c)
    for i in range(blades):
        a = start + 2 * math.pi * i / blades
        dirv = Vector((0, math.cos(a), math.sin(a)))
        tang = Vector((1, 0, 0)).cross(dirv)
        secs = []
        for k in range(5):
            rr = r * (0.18 + 0.82 * k / 4)
            ch = chord * (1.0 - 0.45 * (k / 4) ** 2) * (0.75 if k == 0 else 1.0)
            ph = math.radians(pitch - 20.0 * k / 4)
            cdir = tang * math.cos(ph) + Vector((1, 0, 0)) * math.sin(ph)
            ndir = Vector((1, 0, 0)) * math.cos(ph) - tang * math.sin(ph)
            o = c + dirv * rr
            secs.append([o + cdir * (xc - 0.4) * ch + ndir * (tz * ch * 0.12) for xc, zc, tz in AFP])
        loft(name, secs, kind)


def finish(name, tex):
    """Центр по высоте — по габариту; запекание; матовые итоговые материалы; экспорт"""
    zs = [(o.matrix_world @ v.co).z for o in K.parts for v in o.data.vertices]
    dz = -(min(zs) + max(zs)) / 2
    M = Matrix.Translation((0, 0, dz))
    for o in K.parts:
        o.data.transform(M)
    for k in list(K.pivots):
        p = K.pivots[k]
        K.pivots[k] = (p[0], p[1], p[2] + dz)
    root, tris = K.bake_export(name, OUT, tex=tex)
    # матовые материалы (Kanta 19.10): bake_export ставит корпусу 0.72 / 0.05 — переписываем и экспортируем заново
    for m in bpy.data.materials:
        if m.name in (name + "_body", name + "_glass") and m.use_nodes:
            b = m.node_tree.nodes.get("Principled BSDF")
            if b is None:
                continue
            body = m.name.endswith("_body")
            b.inputs["Roughness"].default_value = 0.88 if body else 0.3
            b.inputs["Metallic"].default_value = 0.0
            if "Specular IOR Level" in b.inputs:
                b.inputs["Specular IOR Level"].default_value = 0.35 if body else 0.5
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_image_format="AUTO")
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "glb_merge_prims", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "glb_merge_prims.py"))
    gm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gm)
    gm.merge(path)
    if os.environ.get("PREVIEW"):
        os.environ.setdefault("QUICK", "1")
        K.preview(OUT, name, 1.0)
    print("DONE", name, "tris", tris)


# ================================================================ вражеский транспортник
def transport():
    """Высокоплан с четырьмя турбовинтовыми, хвост с грузовой рампой (по мотивам военных транспортников 60-х);
    прежние детали силуэта: гондолы на законцовках, баки под крылом у фюзеляжа, гаргрот на спине.
    Красные метки врага: кольца за кабиной и перед хвостом, законцовки крыла и стабилизатора, верх киля."""
    palette(ENEMY_CAMO, ENEMY_BELLY, 2.0)
    F = Body([(0.5, -0.032, -0.022, 0.004, 2.0), (0.494, -0.05, -0.002, 0.026, 2.1), (0.478, -0.064, 0.02, 0.043, 2.2),
              (0.45, -0.074, 0.04, 0.056, 2.4), (0.41, -0.079, 0.054, 0.065, 2.7), (0.36, -0.081, 0.062, 0.07, 3.0),
              (0.28, -0.082, 0.066, 0.072, 3.2), (-0.06, -0.082, 0.066, 0.072, 3.2), (-0.13, -0.077, 0.066, 0.07, 3.1),
              (-0.21, -0.052, 0.064, 0.061, 2.8), (-0.29, -0.016, 0.062, 0.048, 2.5), (-0.37, 0.014, 0.06, 0.034, 2.3),
              (-0.43, 0.032, 0.059, 0.022, 2.1), (-0.475, 0.042, 0.057, 0.012, 2.0), (-0.5, 0.048, 0.054, 0.004, 2.0)])
    xs = stations(0.5, 0.3, 9, 1.6) + stations(0.3, -0.1, 6) + stations(-0.1, -0.5, 12)
    F.build("fuselage", xs, "hull", 32, bands=[(0.5, 0.468, "radome"), (0.305, 0.275, "red"), (-0.27, -0.3, "red")])
    # кабина: лобовые и боковые стёкла с рамкой
    for t0, t1 in ((52, 86), (94, 128)):
        F.patch("wind_frame", 0.463, 0.428, t0 - 2, t1 + 2, "dark", 0.0010, 3, 4)
        F.patch("wind", 0.46, 0.431, t0, t1, "glass", 0.0016, 3, 4)
    for t0, t1 in ((28, 46), (134, 152)):
        F.patch("side_win_frame", 0.432, 0.392, t0 - 2, t1 + 2, "dark", 0.0010, 3, 3)
        F.patch("side_win", 0.43, 0.395, t0, t1, "glass", 0.0016, 3, 3)
    # грузовая рампа и створки снизу хвоста: швы
    F.patch("ramp_seam", -0.14, -0.33, 236, 238.5, "black", 0.0012, 6, 1)
    F.patch("ramp_seam", -0.14, -0.33, 301.5, 304, "black", 0.0012, 6, 1)
    F.patch("ramp_seam", -0.138, -0.145, 236, 304, "black", 0.0012, 1, 8)
    F.patch("ramp_seam", -0.24, -0.245, 236, 304, "black", 0.0012, 1, 8)
    # боковые двери десанта и иллюминаторы
    for s in (1, -1):
        th0 = 0 if s > 0 else 180
        F.patch("door_seam", -0.085, -0.088, th0 - 14 * s, th0 + 10 * s, "dark", 0.0012, 1, 3)
        F.patch("door_seam", -0.125, -0.128, th0 - 14 * s, th0 + 10 * s, "dark", 0.0012, 1, 3)
        for x in (0.24, 0.19, 0.14, 0.04, -0.01, -0.06):
            p = F.surf(x, th0 + 6 * s, 0.0006)
            cyl("porthole", tuple(p), 0.0055, 0.0016, "glass", "Y", 10)
    # обтекатели шасси по бортам внизу
    for s in (1, -1):
        Body([(0.09, -0.078, -0.05, 0.003, 2.4), (0.06, -0.08, -0.038, 0.01, 2.6), (0.0, -0.081, -0.034, 0.013, 2.8),
              (-0.1, -0.081, -0.034, 0.013, 2.8), (-0.15, -0.078, -0.04, 0.009, 2.6), (-0.175, -0.075, -0.05, 0.003, 2.4)],
             yc=s * 0.062).build("sponson", stations(0.09, -0.175, 10), "hull", 16, caps=True)
    # гаргрот-«каноэ» на спине и наплыв центроплана
    Body([(0.19, 0.06, 0.064, 0.008, 2.2), (0.15, 0.058, 0.08, 0.034, 2.4), (0.06, 0.058, 0.086, 0.04, 2.6),
          (-0.04, 0.058, 0.084, 0.036, 2.6), (-0.12, 0.058, 0.08, 0.026, 2.4), (-0.24, 0.058, 0.072, 0.014, 2.2),
          (-0.3, 0.056, 0.062, 0.004, 2.0)]).build("canoe", stations(0.19, -0.3, 14), "hull", 20, caps=True)
    # крыло: высокоплан, прямое с сужением, лёгкая обратная V
    WZ = 0.072
    surface("wing", ((0.118, 0.0, WZ), 0.118, 0.15), ((0.082, 0.545, WZ - 0.012), 0.07, 0.12), "hull", 6,
            bands=[(0.845, 1.0, "red")], round_tip=False)

    def wz(y):
        return WZ - 0.012 * abs(y) / 0.545

    def wle(y):
        return 0.118 - 0.036 * abs(y) / 0.545
    # гондолы на законцовках (красный нос)
    for s in (1, -1):
        pod("tip_pod", 0.13, -0.065, s * 0.553, wz(0.545), 0.0125, "hull", "red", 0.05, 14)
    # баки под крылом у фюзеляжа
    for s in (1, -1):
        y = s * 0.108
        pod("tank", 0.19, -0.04, y, wz(y) - 0.034, 0.017, "hull", None, 0, 16)
        box("tank_pylon", (0.07, y, wz(y) - 0.02), (0.08, 0.005, 0.02), "hull", 0.0008)
    # двигатели: гондолы под крылом, коки и винты (узлы prop_1…4)
    k = 0
    for s in (1, -1):
        for y in (0.175, 0.32):
            k += 1
            yy = s * y
            zc = wz(y) - 0.024
            x0 = wle(y) + 0.085
            lathe("nacelle", [(0.012, 0.0), (0.0175, -0.008), (0.0205, -0.03), (0.021, -0.08), (0.0195, -0.15),
                              (0.014, -0.22), (0.007, -0.255), (0.0008, -0.262)], (x0, yy, zc), "hull", "X", 18)
            # надстройка гондолы до крыла (капот сверху) и воздухозаборник снизу
            Body([(x0 - 0.02, zc + 0.008, zc + 0.014, 0.004, 2.2), (x0 - 0.05, zc + 0.006, zc + 0.03, 0.013, 2.6),
                  (x0 - 0.17, zc + 0.006, zc + 0.03, 0.013, 2.6), (x0 - 0.24, zc + 0.006, zc + 0.022, 0.004, 2.2)],
                 yc=yy).build("nacelle_top", stations(x0 - 0.02, x0 - 0.24, 8), "hull", 14, caps=True)
            Body([(x0 - 0.008, zc - 0.022, zc - 0.012, 0.003, 2.2), (x0 - 0.02, zc - 0.027, zc - 0.01, 0.008, 2.6),
                  (x0 - 0.06, zc - 0.026, zc - 0.01, 0.008, 2.6), (x0 - 0.09, zc - 0.02, zc - 0.012, 0.003, 2.2)],
                 yc=yy).build("chin_intake", stations(x0 - 0.008, x0 - 0.09, 5), "hull", 12, caps=True)
            cyl("intake_hole", (x0 - 0.011, yy, zc - 0.018), 0.0045, 0.002, "black", "X", 10)
            # выхлоп сбоку-сверху
            tube("exhaust", [(x0 - 0.1, yy + s * 0.016, zc + 0.012), (x0 - 0.14, yy + s * 0.02, zc + 0.013)], 0.0045, "steel", 8)
            pc = (x0 + 0.006, yy, zc)
            grp("prop_%d" % k, pc)
            lathe("spinner", [(0.0105, 0.0), (0.0095, 0.012), (0.0065, 0.024), (0.0008, 0.034)], pc, "steel", "X", 16, cap0=True)
            prop("blade", (pc[0] + 0.006, yy, zc), 0.058, 4, 0.0125, 38.0, "dark", 0.4 + 0.3 * k)
            grp("")
    # оперение: киль с красным верхом и стабилизатор на фюзеляже
    surface("fin", ((-0.29, 0.0, 0.052), 0.185, 0.11), ((-0.418, 0.0, 0.172), 0.078, 0.1), "hull", 4,
            bands=[(0.78, 1.0, "red")], mirror=False, camber=False, up=(0, 1, 0))
    # форкиль
    surface("dorsal", ((-0.23, 0.0, 0.056), 0.09, 0.08), ((-0.3, 0.0, 0.09), 0.03, 0.08), "hull", 2,
            mirror=False, camber=False, round_tip=False, up=(0, 1, 0))
    surface("stab", ((-0.352, 0.0, 0.064), 0.095, 0.1), ((-0.392, 0.245, 0.066), 0.052, 0.09), "hull", 4,
            bands=[(0.72, 1.0, "red")], camber=False)
    # огни и антенны
    lathe("beacon", [(0.006, 0.0), (0.0055, 0.004), (0.0005, 0.007)], (0.12, 0.0, 0.086), "lamp_red", "Z", 10)
    lathe("beacon", [(0.006, 0.0), (0.0055, -0.004), (0.0005, -0.007)], (0.0, 0.0, -0.088), "lamp_red", "Z", 10)
    for x in (0.3, -0.02):
        box("antenna", (x, 0.0, 0.074 if x > 0 else 0.093), (0.016, 0.0018, 0.012), "dark", 0.0005, rot=("Y", -25))
    finish("transport", int(os.environ.get("TEX", "1024")))


# ================================================================ ракетоносец
def carrier():
    """Двухдвигательный ударный самолёт: длинный нос с красным обтекателем, фонарь, гондолы двигателей по бокам
    фюзеляжа, стреловидное крыло с четырьмя ракетами (красные головки) и пусковыми на законцовках, однокилевое
    оперение. Красные метки: законцовки крыла и стабилизатора, полоса на киле, нос."""
    palette(ENEMY_CAMO, ENEMY_BELLY, 1.0)
    F = Body([(0.5, -0.004, 0.002, 0.002, 2.0), (0.47, -0.012, 0.012, 0.011, 2.0), (0.42, -0.021, 0.021, 0.019, 2.1),
              (0.36, -0.028, 0.03, 0.026, 2.3), (0.29, -0.033, 0.036, 0.031, 2.5), (0.2, -0.037, 0.038, 0.036, 2.7),
              (0.08, -0.039, 0.036, 0.04, 2.9), (-0.1, -0.038, 0.034, 0.04, 2.9), (-0.25, -0.032, 0.031, 0.034, 2.7),
              (-0.38, -0.024, 0.027, 0.024, 2.4), (-0.46, -0.016, 0.023, 0.014, 2.2), (-0.5, -0.012, 0.02, 0.006, 2.0)])
    F.build("fuselage", stations(0.5, 0.2, 12, 1.5) + stations(0.2, -0.5, 14), "hull", 28,
            bands=[(0.5, 0.415, "red")])
    # фонарь
    Body([(0.352, 0.02, 0.024, 0.004, 2.0), (0.33, 0.02, 0.045, 0.016, 2.2), (0.29, 0.02, 0.058, 0.022, 2.4),
          (0.24, 0.02, 0.058, 0.022, 2.4), (0.2, 0.02, 0.05, 0.018, 2.2), (0.17, 0.02, 0.04, 0.008, 2.0)]).build(
        "canopy", stations(0.352, 0.17, 10), "glass", 20, caps=True)
    for x in (0.305, 0.235):
        F2 = Body([(x + 0.002, 0.02, 0.06, 0.0235, 2.4), (x - 0.002, 0.02, 0.06, 0.0235, 2.4)])
        F2.build("canopy_frame", [x + 0.002, x - 0.002], "dark", 20, caps=False)
    # гаргрот за фонарём
    Body([(0.19, 0.02, 0.045, 0.014, 2.2), (0.1, 0.02, 0.046, 0.016, 2.4), (-0.15, 0.02, 0.04, 0.014, 2.4),
          (-0.3, 0.02, 0.03, 0.006, 2.0)]).build("spine", stations(0.19, -0.3, 10), "hull", 16, caps=True)
    # гондолы двигателей по бокам фюзеляжа: воздухозаборник под крылом, сопло в хвосте
    for s in (1, -1):
        y = s * 0.072
        lathe("engine", [(0.021, 0.0), (0.025, -0.006), (0.029, -0.03), (0.03, -0.2), (0.029, -0.36), (0.025, -0.43),
                         (0.023, -0.45)], (0.12, y, -0.016), "hull", "X", 20)
        cyl("intake", (0.119, y, -0.016), 0.019, 0.003, "black", "X", 16)
        lathe("nozzle", [(0.022, 0.0), (0.0215, -0.025), (0.019, -0.04)], (-0.326, y, -0.016), "steel", "X", 16)
        cyl("nozzle_in", (-0.364, y, -0.016), 0.016, 0.004, "black", "X", 16)
        # надстройка между гондолой и фюзеляжем (без щели)
        Body([(0.1, -0.03, 0.0, 0.004, 2.4), (0.05, -0.034, 0.012, 0.026, 2.6), (-0.25, -0.032, 0.01, 0.026, 2.6),
              (-0.31, -0.026, 0.004, 0.006, 2.2)], yc=s * 0.036).build("engine_fair", stations(0.1, -0.31, 10), "hull", 16, caps=True)
    # крыло: среднеплан, стреловидное
    surface("wing", ((0.07, 0.0, -0.004), 0.27, 0.06), ((-0.07, 0.515, -0.014), 0.105, 0.05), "hull", 5,
            bands=[(0.84, 1.0, "red")], round_tip=False)

    def wle(y):
        return 0.07 - 0.14 * abs(y) / 0.515

    def wz(y):
        return -0.004 - 0.01 * abs(y) / 0.515
    for s in (1, -1):
        # пусковая на законцовке
        pod("tip_rail", wle(0.515) + 0.035, wle(0.515) - 0.115, s * 0.522, wz(0.515), 0.0075, "dark", None, 0, 12, 0.15, 0.2)
        # четыре ракеты под крылом
        for y in (0.17, 0.3):
            yy = s * y
            zr = wz(y) - 0.024
            x0 = wle(y) + 0.085
            pod("missile", x0, x0 - 0.155, yy, zr, 0.0085, "olive", "red", 0.028, 12, 0.06, 0.18)
            box("missile_pylon", (wle(y) - 0.03, yy, wz(y) - 0.011), (0.07, 0.004, 0.013), "hull", 0.0008)
            for a in (45, 135, 225, 315):
                r = math.radians(a)
                d = Vector((0, math.cos(r), math.sin(r)))
                box("missile_fin", tuple(Vector((x0 - 0.14, yy, zr)) + d * 0.012), (0.018, 0.001, 0.008), "dark", 0.0003,
                    rot=Matrix.Rotation(r - math.pi / 2, 3, "X"))
            cyl("missile_band", (x0 - 0.06, yy, zr), 0.0088, 0.004, "red", "X", 12)
    # оперение
    surface("stab", ((-0.29, 0.035, -0.014), 0.13, 0.06), ((-0.405, 0.258, -0.022), 0.062, 0.05), "hull", 4,
            bands=[(0.62, 1.0, "red")], camber=False)
    surface("fin", ((-0.24, 0.0, 0.026), 0.2, 0.08), ((-0.37, 0.0, 0.126), 0.08, 0.07), "hull", 5,
            bands=[(0.42, 0.7, "red")], mirror=False, camber=False, up=(0, 1, 0))
    # пушка в носу снизу, ПВД, огни
    tube("gun", [(0.39, 0.012, -0.02), (0.44, 0.012, -0.016)], 0.0025, "black", 6)
    tube("pitot", [(0.495, 0.0, 0.0), (0.52, 0.0, 0.0)], 0.0013, "steel", 6)
    lathe("beacon", [(0.004, 0.0), (0.0035, 0.003), (0.0004, 0.005)], (0.0, 0.0, 0.04), "lamp_red", "Z", 8)
    finish("carrier", int(os.environ.get("TEX", "1024")))


# ================================================================ дрон
def drone():
    """Ударный беспилотник: фюзеляж-«сигара» с носовым шаром оптики и ПВД, прямое крыло большого удлинения
    с красными законцовками, V-оперение с красными концами, воздухозаборник на спине, сопло в хвосте."""
    palette(ENEMY_CAMO, ENEMY_BELLY, 0.7)
    F = Body([(0.45, -0.012, 0.004, 0.006, 2.0), (0.43, -0.035, 0.024, 0.028, 2.1), (0.39, -0.05, 0.042, 0.046, 2.3),
              (0.32, -0.058, 0.054, 0.058, 2.5), (0.2, -0.062, 0.058, 0.064, 2.6), (0.0, -0.062, 0.056, 0.064, 2.6),
              (-0.18, -0.054, 0.048, 0.055, 2.5), (-0.32, -0.04, 0.036, 0.04, 2.3), (-0.42, -0.026, 0.026, 0.026, 2.1),
              (-0.46, -0.022, 0.022, 0.022, 2.0)])
    F.build("fuselage", stations(0.45, 0.2, 10, 1.5) + stations(0.2, -0.46, 14), "hull", 28)
    # выход сопла
    lathe("nozzle", [(0.022, 0.0), (0.021, -0.02), (0.017, -0.035)], (-0.458, 0.0, 0.0), "steel", "X", 16)
    cyl("nozzle_in", (-0.492, 0.0, 0.0), 0.014, 0.003, "black", "X", 16)
    # ПВД и шар оптики под носом
    tube("probe", [(0.445, 0.0, -0.004), (0.5, 0.0, -0.004)], 0.0035, "steel", 8)
    lathe("ball_mount", [(0.018, 0.0), (0.016, -0.008), (0.001, -0.01)], (0.34, 0.0, -0.052), "dark", "Z", 14, cap0=True)
    lathe("ball", [(0.0005, -0.026), (0.012, -0.023), (0.019, -0.013), (0.021, -0.002), (0.016, 0.006), (0.0005, 0.008)],
          (0.34, 0.0, -0.052), "dark", "Z", 16)
    cyl("lens", (0.358, 0.0, -0.068), 0.008, 0.004, "glass", (1, 0, -0.6), 12)
    # спутниковый горб на носу и воздухозаборник на спине
    Body([(0.36, 0.04, 0.046, 0.01, 2.0), (0.3, 0.04, 0.072, 0.04, 2.2), (0.18, 0.04, 0.078, 0.046, 2.4),
          (0.06, 0.04, 0.066, 0.036, 2.4), (-0.02, 0.04, 0.052, 0.012, 2.0)]).build("hump", stations(0.36, -0.02, 10), "hull", 20, caps=True)
    Body([(-0.05, 0.04, 0.074, 0.03, 2.6), (-0.1, 0.04, 0.078, 0.032, 2.6), (-0.25, 0.03, 0.062, 0.026, 2.4),
          (-0.34, 0.025, 0.036, 0.008, 2.0)]).build("intake_body", stations(-0.05, -0.34, 8), "hull", 18, caps=False)
    Body([(-0.049, 0.045, 0.071, 0.026, 2.6), (-0.05, 0.045, 0.071, 0.026, 2.6)]).build("intake_hole", [-0.049, -0.05], "black", 18, caps=True)
    # крыло: высокоплан, прямое
    surface("wing", ((0.0, 0.0, 0.032), 0.19, 0.12), ((-0.025, 0.548, 0.04), 0.14, 0.1), "hull", 6,
            bands=[(0.83, 1.0, "red")])
    for s in (1, -1):
        y = s * 0.33
        pod("hardpoint", 0.03, -0.07, y, 0.004, 0.011, "olive", "dark", 0.012, 12)
        box("hp_pylon", (-0.03, y, 0.02), (0.05, 0.004, 0.02), "hull", 0.0008)
    # V-оперение
    for s in (1, -1):
        surface("vtail", ((-0.31, s * 0.02, 0.03), 0.13, 0.09), ((-0.415, s * 0.285, 0.098), 0.075, 0.08), "hull", 4,
                bands=[(0.74, 1.0, "red")], mirror=False, camber=False)
    lathe("beacon", [(0.004, 0.0), (0.0035, -0.003), (0.0004, -0.005)], (0.1, 0.0, -0.062), "lamp_red", "Z", 8)
    for x in (0.12, -0.2):
        box("antenna", (x, 0.0, -0.064 if x > 0 else -0.056), (0.014, 0.002, 0.012), "dark", 0.0005, rot=("Y", 25))
    finish("drone", int(os.environ.get("TEX", "512")))


# ================================================================ дрон-камикадзе
def kamikaze():
    """Ударный дрон-«ракета»: цилиндрический корпус с оранжевой боевой частью, крестообразное треугольное крыло
    с оранжевыми полосами, сопло; оранжевые пояса у боевой части и у крыла."""
    palette(ENEMY_CAMO, ENEMY_BELLY, 0.6)
    R = 0.05
    rows = [(0.5, -0.0015, 0.0015, 0.0015, 2.0)]
    for i in range(1, 9):
        t = i / 8.0
        x = 0.5 - 0.27 * t
        r = R * math.sqrt(1 - (1 - t) ** 2) ** 0.85            # оживало
        rows.append((x, -r, r, r, 2.0))
    rows += [(-0.38, -R, R, R, 2.0), (-0.44, -0.043, 0.043, 0.043, 2.0), (-0.46, -0.04, 0.04, 0.04, 2.0)]
    F = Body(rows)
    F.build("body", stations(0.5, 0.22, 12, 1.4) + stations(0.22, -0.46, 10), "hull", 28,
            bands=[(0.5, 0.23, "orange"), (0.165, 0.145, "orange"), (-0.385, -0.405, "orange")])
    # швы отсеков
    for x in (0.08, -0.08):
        F.patch("seam", x, x - 0.003, 0, 359.9, "black", 0.0008, 1, 24)
    lathe("nozzle", [(0.038, 0.0), (0.036, -0.02), (0.032, -0.04)], (-0.458, 0.0, 0.0), "steel", "X", 20)
    cyl("nozzle_in", (-0.497, 0.0, 0.0), 0.027, 0.003, "black", "X", 20)
    # крестообразное треугольное крыло (горизонтальная пара шире, вертикальная — киль и подфюзеляжный гребень)
    for up, span in (((0, 0, 1), 0.233), ((0, 1, 0), 0.198)):
        for s in (1, -1):
            if up[2]:
                r0, r1 = (-0.1, s * 0.04, 0.0), (-0.31, s * span, 0.0)
            else:
                r0, r1 = (-0.1, 0.0, s * 0.04), (-0.31, 0.0, s * span)
            surface("wing", (r0, 0.3, 0.05), (r1, 0.075, 0.05), "hull", 4,
                    bands=[(0.5, 0.64, "orange")], mirror=False, camber=False, up=up, round_tip=False)
            # законцовка: ограничитель
            tip = Vector(r1)
            d = Vector((0, 1 if up[2] else 0, 0 if up[2] else 1)) * s
            box("tip_cap", tuple(tip + Vector((-0.04, 0, 0)) + d * 0.003), (0.085, 0.006 if up[2] else 0.004, 0.004 if up[2] else 0.006),
                "dark", 0.0008)
    # датчик в носу (стекло) и антенна
    cyl("seeker", (0.497, 0.0, 0.0), 0.0022, 0.004, "glass", "X", 8)
    finish("kamikaze", int(os.environ.get("TEX", "512")))


# ================================================================ свой заправщик
def tanker():
    """Свой заправщик: четырёхмоторный реактивный, стреловидное низкое крыло с винглетами, обычное оперение.
    Штангу достраивает tanker_boom.py (узлы Boom / BoomTube / BoomTip). Окраска — светло-серая матовая."""
    palette(OWN_CAMO, OWN_BELLY, 1.6)
    F = Body([(0.5, -0.014, -0.006, 0.003, 2.0), (0.492, -0.031, 0.012, 0.023, 2.0), (0.472, -0.042, 0.027, 0.036, 2.0),
              (0.44, -0.047, 0.038, 0.044, 2.0), (0.4, -0.049, 0.044, 0.048, 2.0), (0.33, -0.05, 0.047, 0.05, 2.0),
              (-0.2, -0.05, 0.047, 0.05, 2.0), (-0.28, -0.042, 0.046, 0.045, 2.0), (-0.36, -0.024, 0.044, 0.035, 2.0),
              (-0.44, -0.003, 0.042, 0.021, 2.0), (-0.485, 0.012, 0.038, 0.01, 2.0), (-0.5, 0.018, 0.034, 0.004, 2.0)])
    F.build("fuselage", stations(0.5, 0.3, 10, 1.6) + stations(0.3, -0.2, 8) + stations(-0.2, -0.5, 10), "hull", 32,
            bands=[(0.5, 0.488, "radome")])
    for t0, t1 in ((48, 82), (98, 132)):
        F.patch("wind_frame", 0.468, 0.442, t0 - 2, t1 + 2, "dark", 0.0010, 3, 4)
        F.patch("wind", 0.466, 0.444, t0, t1, "glass", 0.0016, 3, 4)
    for t0, t1 in ((26, 44), (136, 154)):
        F.patch("side_win", 0.446, 0.42, t0, t1, "glass", 0.0016, 3, 3)
    # крыло: низкоплан, стреловидное, V; наплыв центроплана
    def wle(y):
        return 0.135 - 0.205 * abs(y) / 0.37

    def wz(y):
        return -0.034 + 0.03 * abs(y) / 0.37
    surface("wing", ((0.135, 0.0, -0.034), 0.17, 0.13), ((-0.07, 0.37, -0.004), 0.046, 0.1), "hull", 6, round_tip=False)
    Body([(0.17, -0.05, -0.03, 0.01, 2.2), (0.12, -0.056, -0.02, 0.05, 2.6), (-0.02, -0.058, -0.02, 0.054, 2.6),
          (-0.09, -0.052, -0.022, 0.04, 2.4), (-0.13, -0.05, -0.03, 0.01, 2.2)]).build("belly_fair", stations(0.17, -0.13, 10), "hull", 20, caps=True)
    # винглеты
    for s in (1, -1):
        surface("winglet", ((wle(0.37) + 0.002, s * 0.37, wz(0.37)), 0.042, 0.08), ((wle(0.37) - 0.03, s * 0.378, wz(0.37) + 0.035), 0.022, 0.08),
                "hull", 2, mirror=False, camber=False, up=(0, 1, 0))
    # двигатели на пилонах
    for s in (1, -1):
        for y, fwd in ((0.13, 0.075), (0.215, 0.06)):
            yy = s * y
            x0 = wle(y) + fwd
            zc = wz(y) - 0.026
            lathe("engine", [(0.0155, 0.0), (0.0185, -0.004), (0.0195, -0.02), (0.0185, -0.055), (0.0145, -0.078),
                             (0.0105, -0.08)], (x0, yy, zc), "hull", "X", 20)
            cyl("engine_lip", (x0 + 0.0005, yy, zc), 0.0157, 0.002, "steel", "X", 20, cap=False)
            cyl("intake", (x0 - 0.004, yy, zc), 0.0148, 0.002, "black", "X", 20)
            lathe("exhaust", [(0.0105, 0.0), (0.0085, -0.012), (0.0004, -0.024)], (x0 - 0.08, yy, zc), "steel", "X", 16)
            Body([(x0 - 0.015, zc + 0.01, zc + 0.016, 0.002, 2.4), (x0 - 0.03, zc + 0.008, wz(y) + 0.004, 0.004, 3.0),
                  (x0 - 0.1, zc + 0.008, wz(y) + 0.004, 0.004, 3.0), (x0 - 0.125, zc + 0.01, wz(y), 0.002, 2.4)],
                 yc=yy).build("pylon", stations(x0 - 0.015, x0 - 0.125, 6), "hull", 12, caps=True)
    # оперение
    surface("stab", ((-0.37, 0.0, 0.016), 0.105, 0.1), ((-0.455, 0.172, 0.03), 0.042, 0.09), "hull", 4, camber=False)
    surface("fin", ((-0.33, 0.0, 0.04), 0.15, 0.11), ((-0.44, 0.0, 0.132), 0.062, 0.1), "hull", 4,
            mirror=False, camber=False, up=(0, 1, 0))
    # огни заправки: жёлто-зелёные указатели под фюзеляжем у хвоста
    for s in (1, -1):
        cyl("director", (-0.3, s * 0.024, -0.044), 0.0022, 0.03, "lamp_green", "X", 8)
    lathe("beacon", [(0.005, 0.0), (0.0045, 0.004), (0.0004, 0.006)], (0.1, 0.0, 0.046), "lamp_red", "Z", 10)
    lathe("beacon", [(0.005, 0.0), (0.0045, -0.004), (0.0004, -0.006)], (0.0, 0.0, -0.058), "lamp_red", "Z", 10)
    for s, kk in ((1, "lamp_red"), (-1, "lamp_green")):
        cyl("nav", (wle(0.37) - 0.01, s * 0.372, wz(0.37)), 0.003, 0.006, kk, "Y", 8)
    finish("tanker", int(os.environ.get("TEX", "1024")))


{"transport": transport, "carrier": carrier, "drone": drone, "kamikaze": kamikaze, "tanker": tanker}[MODEL]()
