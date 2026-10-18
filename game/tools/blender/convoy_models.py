"""Техника наземного конвоя, версия 2 — полноценная переработка (A-04, решение Kanta 18.10.2026; первая версия — A-02).
Концепция — docs/activities/convoy.md, референсы Kanta — /mnt/project-files/refs/convoy/. Вымышленные машины
«по мотивам»: свой силуэт, без марок, эмблем, номеров и надписей. Окраска — песочный камуфляж (Kanta, вариант 3),
запечённая текстура с пылью, затенением и потёртостями (convoy_kit.py).
Запуск: python3 convoy_models.py <truck|ifv|scout|technical|manpads|pickup_tent|crate> <out_dir>
Длина машины = 1, нос +X, низ колёс на z = 0. Подвижные части — отдельные узлы GLB (их ищет render3d.gd):
  wheel_fl, wheel_fr, wheel_1l … — колёса: качение вокруг локальной Y; передние (wheel_f*) ещё и руль вокруг Z;
  tent     (грузовики) — тент с дугами, у остова прячется;
  track_l, track_r (БМП) — гусеницы с катками;
  turret   (БМП, броневик, боевой пикап) — башня или пулемёт на станке, поворот вокруг вертикали;
  gun      (БМП) — ствол, дочерний узел башни;
  launcher (пикап с ПЗРК) — труба с руками стрелка, подъём вокруг Y."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convoy_kit as K
from convoy_kit import box, cyl, lathe, prism, prism_x, prism_z, loft, tube, arc_band, panel, side_panel, tyre, rim, wheel, person
from mathutils import Vector, Matrix

kind, OUT = sys.argv[-2], sys.argv[-1]
K.reset()


def grp(name, pivot, parent=None):
    K.group = name
    if name:
        K.pivots[name] = pivot
        if parent:
            K.PARENT[name] = parent


def turn_parts(n0, c, axis, deg):
    """Повернуть детали, созданные после parts[n0], вокруг точки c"""
    T = Matrix.Translation(Vector(c)) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-Vector(c))
    for o in K.parts[n0:]:
        o.data.transform(T)


def spare_wheel(c, r, w, axis_deg=90.0, **kw):
    """Запасное колесо (не крутится): по умолчанию ось вдоль X"""
    n0 = len(K.parts)
    tyre("spare_tyre", c, r, w, r * 0.6, lugs=kw.get("lugs", 10), chevron=kw.get("chevron", True))
    rim("spare_rim", c, r * 0.6, w, 1, kw.get("rim_kind", "paint"), style=kw.get("style", "beadlock"))
    turn_parts(n0, c, "Z", axis_deg)


def tent_cover(name, x0, x1, half_w, z0, z_side, z_top, bows, kind="canvas", sag=0.008, n_arc=8, per=5):
    """Брезентовый тент: борта, скруглённая крыша, провис между дугами; дуги — по списку x"""
    prof = [(half_w, z0), (half_w, z_side)]
    for i in range(1, n_arc):
        a = math.pi * i / n_arc
        prof.append((half_w * math.cos(a), z_side + (z_top - z_side) * math.sin(a)))
    prof += [(-half_w, z_side), (-half_w, z0)]
    xs = sorted(set([x0, x1] + list(bows)))
    st = []
    for a, b in zip(xs[:-1], xs[1:]):
        for k in range(per):
            st.append((a + (b - a) * k / per, a, b))
    st.append((x1, None, None))
    secs = []
    for x, a, b in st:
        t = 0.0 if a is None else (x - a) / (b - a)
        s = math.sin(math.pi * t) ** 1.5
        sec = []
        for j, (y, z) in enumerate(prof):
            if j in (0, len(prof) - 1):
                sec.append((x, y, z))
                continue
            # крыша провисает, борта чуть втягиваются
            k = 1.0 - s * 0.35 * (1 - abs(y) / half_w) if z > z_side else 1.0
            dz = -sag * s * (0.4 + 0.6 * (z - z0) / (z_top - z0))
            dy = -math.copysign(sag * 0.6 * s, y) if abs(y) > half_w * 0.6 else 0.0
            sec.append((x, y + dy, z + dz * k))
        secs.append(sec)
    loft(name, secs, kind)
    return prof


if kind == "truck":
    # --- тяжёлый грузовик 6×6 с кабиной над двигателем, бортовой кузов и тент (по мотивам refs/truck_6x6) ---
    W = 0.316
    hw = W / 2
    R, TW = 0.074, 0.052
    YW = hw - TW / 2 - 0.004
    XF, X1, X2 = 0.335, -0.132, -0.3
    for node, x in (("f", XF), ("1", X1), ("2", X2)):
        for s, sd in ((1, "l"), (-1, "r")):
            wheel("wheel_" + node + sd, (x, s * YW, R), R, TW, R * 0.58, lugs=10, style="beadlock")
    # рама, мосты, рессоры, карданы
    for s in (1, -1):
        box("rail", (-0.0, s * 0.055, 0.118), (0.94, 0.014, 0.04), "dark", 0.0)
        for x in (XF, X1, X2):
            box("spring", (x, s * 0.055, 0.092), (0.15, 0.022, 0.012), "dark", 0.0)
            box("spring2", (x, s * 0.055, 0.082), (0.1, 0.02, 0.01), "dark", 0.0)
    for x in (0.42, 0.18, 0.0, -0.2, -0.42):
        box("cross", (x, 0, 0.122), (0.02, 0.11, 0.03), "dark", 0.0)
    for x in (XF, X1, X2):
        cyl("axle", (x, 0, R), 0.012, 2 * YW - TW * 0.6, "dark", "Y", 8)
        lathe("diff", [(0.0005, -0.035), (0.022, -0.03), (0.032, 0.0), (0.022, 0.03), (0.0005, 0.035)], (x, 0, R), "dark", "Y", 10)
    box("balancer", ((X1 + X2) / 2, 0, 0.1), (0.05, 0.13, 0.03), "dark", 0.0)
    box("transfer", (0.06, 0, 0.1), (0.07, 0.06, 0.05), "dark", 0.003)
    tube("shaft", [(0.06, 0, 0.095), (XF - 0.04, 0, R + 0.01)], 0.007, "steel", 6)
    tube("shaft", [(0.03, 0, 0.095), (X1 + 0.03, 0, R + 0.01)], 0.007, "steel", 6)
    tube("shaft", [(X1 - 0.03, 0, R + 0.01), (X2 + 0.03, 0, R + 0.01)], 0.007, "steel", 6)
    # кабина: короткий нос, большое лобовое со скосом назад, крыша скруглена
    CX0, CX1 = 0.27, 0.493
    prism("cab", [(CX0, 0.172), (CX1, 0.172), (0.495, 0.245), (0.47, 0.335), (0.455, 0.355), (0.285, 0.36), (CX0, 0.345)],
          -hw, hw, "paint", 0.012, 3)
    # лобовое: два стекла, стойка посередине, рамка
    for s in (1, -1):
        panel("windshield", (0.4935, 0.252), (0.4705, 0.33), s * 0.006, s * 0.142, "glass", 0.003)
    panel("windshield_post", (0.494, 0.25), (0.471, 0.332), -0.006, 0.006, "dark", 0.004)
    # маска радиатора: решётка между фарами, щель воздухозаборника под стеклом
    box("grille_frame", (0.495, 0, 0.2), (0.006, 0.22, 0.07), "dark", 0.002)
    for i in range(5):
        box("grille_bar", (0.499, 0, 0.172 + i * 0.013), (0.004, 0.21, 0.006), "paint", 0.0)
    box("air_slot", (0.495, 0, 0.243), (0.004, 0.2, 0.008), "black", 0.0)
    # бампер с фарами и буксирными крюками
    box("apron", (0.49, 0, 0.155), (0.02, 0.17, 0.04), "dark", 0.002)
    box("bumper", (0.5, 0, 0.11), (0.03, W + 0.01, 0.055), "paint", 0.006)
    for s in (1, -1):
        cyl("headlamp_bezel", (0.513, s * 0.12, 0.115), 0.019, 0.008, "steel", "X", 14)
        cyl("headlamp", (0.517, s * 0.12, 0.115), 0.015, 0.004, "lamp", "X", 14)
        box("fog", (0.514, s * 0.075, 0.1), (0.006, 0.022, 0.014), "lamp_amber", 0.0)
        box("tow_hook", (0.52, s * 0.035, 0.09), (0.02, 0.012, 0.018), "dark", 0.0)
        cyl("turn_lamp", (0.488, s * 0.152, 0.27), 0.008, 0.01, "lamp_amber", "X", 8)
    # крыша: козырёк и габариты
    box("visor", (0.47, 0, 0.358), (0.03, W - 0.03, 0.008), "paint", 0.003)
    for y in (-0.03, 0, 0.03):
        box("marker", (0.484, y, 0.36), (0.008, 0.016, 0.008), "lamp_amber", 0.0)
    box("roof_hatch", (0.36, 0, 0.362), (0.07, 0.08, 0.008), "paint", 0.003)
    # двери: окно, форточка, ручка, шов двери; подножки; зеркала
    for s in (1, -1):
        y = s * hw
        side_panel("side_window", 0.31, 0.44, 0.255, 0.33, y, "glass", 0.004)
        side_panel("vent_post", 0.405, 0.41, 0.255, 0.33, s * (hw + 0.0015), "dark", 0.003)
        side_panel("door_seam_f", 0.452, 0.455, 0.175, 0.34, s * (hw + 0.001), "dark", 0.002)
        side_panel("door_seam_r", 0.296, 0.299, 0.175, 0.34, s * (hw + 0.001), "dark", 0.002)
        box("handle", (0.32, s * (hw + 0.004), 0.24), (0.03, 0.006, 0.008), "steel", 0.0)
        for i, z in enumerate((0.06, 0.1, 0.14)):
            box("step", (0.27, s * (hw - 0.012), z), (0.05, 0.03, 0.006), "steel", 0.0)
        box("step_bracket", (0.27, s * (hw - 0.002), 0.115), (0.05, 0.004, 0.12), "dark", 0.0)
        # крыло переднего колеса и брызговик
        arc_band("fender", XF, R, s * (YW - TW / 2 - 0.008), s * (hw + 0.003), R + 0.01, R + 0.016, 0, 180, "black", 14)
        box("mudflap_f", (XF - R - 0.012, s * YW, 0.06), (0.004, TW + 0.01, 0.05), "black", 0.0)
        # зеркало на трубчатом кронштейне
        tube("mirror_arm", [(0.47, s * hw, 0.3), (0.48, s * (hw + 0.035), 0.31), (0.478, s * (hw + 0.04), 0.27)], 0.003, "dark", 6)
        box("mirror", (0.476, s * (hw + 0.042), 0.285), (0.008, 0.022, 0.05), "dark", 0.002)
        # дворники
        tube("wiper", [(0.49, s * 0.04, 0.255), (0.478, s * 0.11, 0.29)], 0.0025, "black", 5)
    # за кабиной: воздухозаборник, выхлоп с экраном, запаска на кронштейне
    tube("intake", [(0.262, 0.11, 0.17), (0.262, 0.11, 0.38)], 0.014, "paint", 10)
    cyl("intake_cap", (0.262, 0.11, 0.388), 0.02, 0.015, "dark", "Z", 10)
    tube("exhaust", [(0.12, -0.13, 0.13), (0.24, -0.13, 0.13), (0.255, -0.12, 0.2), (0.255, -0.12, 0.37)], 0.009, "steel", 8)
    box("heat_shield", (0.262, -0.12, 0.3), (0.006, 0.03, 0.1), "dark", 0.0)
    spare_wheel((0.235, 0.0, 0.25), R * 0.96, TW, 90.0, lugs=10)
    box("spare_carrier", (0.24, 0, 0.16), (0.03, 0.18, 0.02), "dark", 0.0)
    # бак, ящик АКБ, ресиверы
    loft("fuel_tank", [[(x, 0.155 - 0.002, 0.105), (x, 0.155, 0.13), (x, 0.145, 0.155), (x, 0.085, 0.155), (x, 0.075, 0.13), (x, 0.085, 0.1), (x, 0.145, 0.1)]
                       for x in (0.235, 0.06)], "paint", 0.004)
    for x in (0.2, 0.1):
        box("tank_strap", (x, 0.115, 0.128), (0.006, 0.084, 0.06), "dark", 0.0)
    box("battery", (0.16, -0.12, 0.12), (0.12, 0.06, 0.06), "paint", 0.004)
    cyl("air_tank", (0.03, -0.11, 0.105), 0.022, 0.14, "dark", "X", 10)
    # кузов: пол, надрамник, откидные борта с рёбрами, передний борт, задний борт
    BX0, BX1 = 0.215, -0.495
    BZ = 0.17
    box("bed_floor", ((BX0 + BX1) / 2, 0, BZ), (BX0 - BX1, W, 0.016), "paint", 0.003)
    for s in (1, -1):
        box("bed_sill", ((BX0 + BX1) / 2, s * 0.06, 0.148), (BX0 - BX1, 0.016, 0.026), "dark", 0.0)
    for i in range(8):
        x = BX0 - 0.04 - i * 0.092
        box("bed_cross", (x, 0, 0.152), (0.012, W - 0.01, 0.018), "dark", 0.0)
    SZ = 0.245
    for s in (1, -1):
        y = s * (hw - 0.004)
        box("side_board", ((BX0 + BX1) / 2, y, (BZ + SZ) / 2 + 0.004), (BX0 - BX1, 0.008, SZ - BZ - 0.002), "paint", 0.002)
        box("side_rail", ((BX0 + BX1) / 2, s * (hw + 0.001), SZ), (BX0 - BX1, 0.012, 0.008), "paint", 0.002)
        for k in range(8):
            x = BX0 - 0.03 - k * 0.093
            box("rib", (x, s * (hw + 0.002), (BZ + SZ) / 2 + 0.004), (0.008, 0.006, SZ - BZ), "paint", 0.0)
        for x in (BX0 - 0.2, BX1 + 0.18):
            box("hinge", (x, s * (hw + 0.004), BZ + 0.01), (0.02, 0.006, 0.012), "dark", 0.0)
        # крылья задней тележки и брызговики
        box("fender_r", ((X1 + X2) / 2, s * YW, 0.158), ((X1 - X2) + 2 * R + 0.02, TW + 0.016, 0.006), "dark", 0.002)
        box("mudflap", (X2 - R - 0.02, s * YW, 0.085), (0.004, TW + 0.01, 0.07), "black", 0.0)
        # задние фонари
        box("tail_lamp_box", (-0.494, s * 0.12, 0.128), (0.012, 0.05, 0.022), "dark", 0.0)
        box("tail_lamp", (-0.5, s * 0.105, 0.128), (0.004, 0.018, 0.014), "lamp_red", 0.0)
        box("tail_lamp2", (-0.5, s * 0.135, 0.128), (0.004, 0.018, 0.014), "lamp_amber", 0.0)
    box("front_board", (BX0 - 0.004, 0, (BZ + 0.3) / 2), (0.01, W, 0.3 - BZ), "paint", 0.002)
    box("tail_board", (BX1 + 0.004, 0, (BZ + SZ) / 2 + 0.004), (0.008, W, SZ - BZ), "paint", 0.002)
    for y in (-0.1, 0.0, 0.1):
        box("tail_rib", (BX1, y, (BZ + SZ) / 2 + 0.004), (0.006, 0.008, SZ - BZ), "paint", 0.0)
    box("rear_bumper", (-0.49, 0, 0.12), (0.02, 0.2, 0.02), "dark", 0.0)
    cyl("hitch", (-0.505, 0, 0.11), 0.012, 0.02, "dark", "X", 8)
    # тент: отдельный узел (у остова прячется)
    grp("tent", (-0.14, 0, SZ))
    bows = [BX0 - 0.03 - k * 0.162 for k in range(5)]
    TH = hw + 0.002
    tent_cover("tent_body", BX1 + 0.002, BX0 - 0.008, TH, SZ - 0.02, 0.36, 0.415, bows, "canvas", 0.007)
    for x in bows:
        prof = [(TH + 0.003, 0.36)] + [((TH + 0.003) * math.cos(math.pi * i / 8), 0.36 + 0.058 * math.sin(math.pi * i / 8)) for i in range(1, 8)] + [(-TH - 0.003, 0.36)]
        tube("bow", [(x, y, z) for y, z in prof], 0.0035, "canvas_dark", 6)
    # стяжки по нижнему краю тента и свёрнутый задний полог
    for s in (1, -1):
        tube("tent_rope", [(BX0 - 0.01, s * (TH + 0.003), SZ - 0.008), (BX1 + 0.01, s * (TH + 0.003), SZ - 0.008)], 0.003, "canvas_dark", 5)
        for k in range(12):
            x = BX0 - 0.03 - k * 0.057
            box("tie", (x, s * (TH + 0.004), SZ - 0.002), (0.004, 0.003, 0.016), "canvas_dark", 0.0)
    cyl("flap_roll", (BX1 - 0.006, 0, 0.345), 0.016, W - 0.02, "canvas", "Y", 10)
    for y in (-0.1, 0.1):
        box("flap_strap", (BX1 - 0.012, y, 0.33), (0.004, 0.012, 0.05), "canvas_dark", 0.0)
    grp("", None)
    name = "convoy_truck"

def arch_profile(pts_before, wheels, pts_after, z_low, r_arch, n=8):
    """Нижняя кромка борта с вырезами над колёсами: идёт от носа к корме, над каждым колесом — полукруг"""
    out = list(pts_before)
    for x, zc in wheels:
        out.append((x + r_arch, z_low))
        for i in range(1, n):
            a = math.pi * i / n
            out.append((x + r_arch * math.cos(a), zc + (r_arch) * math.sin(a) * 1.0))
        out.append((x - r_arch, z_low))
    out += pts_after
    return out


def pickup(style, bed):
    """Пикап (длина 5,2 м = 1). style: boxy — старый угловатый (боевой пикап, тент); modern — с выносом крыльев,
    шноркелем и кенгурятником (пикап с ПЗРК). bed: tray — плоская платформа с низкими бортами; tent — кузов с тентом"""
    hw = 0.172
    R, TW = 0.074, 0.05
    YW = 0.142
    XF, XR = 0.3, -0.27
    lugs, chev, rs = (10, True, "steel") if style == "boxy" else (12, False, "beadlock")
    for s, sd in ((1, "l"), (-1, "r")):
        wheel("wheel_f" + sd, (XF, s * YW, R), R, TW, R * 0.6, lugs=lugs, chevron=chev, style=rs, depth=0.04)
        wheel("wheel_1" + sd, (XR, s * YW, R), R, TW, R * 0.6, lugs=lugs, chevron=chev, style=rs, depth=0.04)
    # рама, мосты, рессоры
    for s in (1, -1):
        box("rail", (0.0, s * 0.07, 0.1), (0.92, 0.014, 0.03), "dark", 0.0)
        box("spring", (XR, s * 0.07, 0.078), (0.2, 0.02, 0.01), "dark", 0.0)
    cyl("axle_f", (XF, 0, R), 0.01, 2 * YW - TW * 0.6, "dark", "Y", 8)
    cyl("axle_r", (XR, 0, R), 0.011, 2 * YW - TW * 0.6, "dark", "Y", 8)
    lathe("diff", [(0.0005, -0.03), (0.02, -0.025), (0.03, 0.0), (0.02, 0.025), (0.0005, 0.03)], (XR, 0.02, R), "dark", "Y", 10)
    tube("shaft", [(0.08, 0, 0.09), (XR + 0.02, 0.02, R + 0.005)], 0.007, "steel", 6)
    box("tank", (-0.1, -0.08, 0.1), (0.14, 0.07, 0.04), "dark", 0.002)
    tube("exhaust", [(0.15, -0.05, 0.09), (-0.42, -0.06, 0.09), (-0.5, -0.07, 0.085)], 0.006, "steel", 6)
    RA = R + 0.016
    if style == "boxy":
        # передок: капот и крылья одним объёмом, вырез над колесом, решётка с прямоугольными фарами
        prism("front", arch_profile([(0.495, 0.13)], [(XF, R)], [(0.2, 0.13), (0.2, 0.258), (0.47, 0.262), (0.495, 0.25)], 0.13, RA),
              -hw, hw, "paint", 0.008, 2)
        box("hood_crease", (0.34, 0, 0.262), (0.27, 0.12, 0.004), "paint", 0.002)
        box("grille", (0.497, 0, 0.19), (0.006, 0.26, 0.09), "dark", 0.0)
        for i in range(4):
            box("grille_bar", (0.501, 0, 0.158 + i * 0.022), (0.004, 0.25, 0.006), "steel", 0.0)
        box("grille_mid", (0.501, 0, 0.19), (0.004, 0.006, 0.086), "steel", 0.0)
        for s in (1, -1):
            box("headlamp_box", (0.5, s * 0.115, 0.205), (0.006, 0.05, 0.034), "steel", 0.0)
            box("headlamp", (0.503, s * 0.115, 0.205), (0.004, 0.04, 0.026), "lamp", 0.0)
            box("turn", (0.5, s * 0.115, 0.17), (0.006, 0.04, 0.012), "lamp_amber", 0.0)
        box("bumper", (0.51, 0, 0.12), (0.03, 2 * hw + 0.02, 0.035), "steel", 0.004)
        # кенгурятник из трубы
        tube("brush_guard", [(0.52, 0.13, 0.11), (0.53, 0.13, 0.25), (0.53, -0.13, 0.25), (0.52, -0.13, 0.11)], 0.007, "dark", 6)
        tube("brush_guard2", [(0.53, 0.13, 0.19), (0.53, -0.13, 0.19)], 0.005, "dark", 6)
        # кабина
        prism("cab", [(0.2, 0.13), (-0.075, 0.13), (-0.075, 0.355), (-0.06, 0.365), (0.125, 0.365), (0.2, 0.262)],
              -hw + 0.004, hw - 0.004, "paint", 0.008, 2)
        panel("windshield", (0.197, 0.268), (0.128, 0.36), -hw + 0.016, hw - 0.016, "glass", 0.003, -1.0)
        box("roof_lip", (0.12, 0, 0.366), (0.012, 2 * hw - 0.02, 0.006), "paint", 0.0)
        for s in (1, -1):
            side_panel("door_window", -0.02, 0.135, 0.268, 0.348, s * (hw - 0.004), "glass", 0.004)
            side_panel("door_seam", 0.165, 0.168, 0.14, 0.26, s * (hw - 0.003), "dark", 0.002)
            side_panel("door_seam2", -0.04, -0.037, 0.14, 0.355, s * (hw - 0.003), "dark", 0.002)
            box("handle", (-0.02, s * (hw - 0.001), 0.25), (0.024, 0.006, 0.006), "steel", 0.0)
            tube("mirror_arm", [(0.15, s * (hw - 0.004), 0.29), (0.16, s * (hw + 0.03), 0.3)], 0.003, "dark", 5)
            box("mirror", (0.16, s * (hw + 0.035), 0.29), (0.008, 0.02, 0.04), "dark", 0.002)
            box("sidestep", (0.06, s * (hw - 0.01), 0.11), (0.22, 0.02, 0.006), "dark", 0.0)
            tube("wiper", [(0.19, s * 0.02, 0.275), (0.175, s * 0.12, 0.298)], 0.0022, "black", 5)
        box("rear_window", (-0.077, 0, 0.305), (0.004, 2 * hw - 0.08, 0.06), "glass", 0.0)
    else:
        # передок с выпуклым капотом, расширители арок, шноркель, силовой бампер
        prism("front", arch_profile([(0.495, 0.14)], [(XF, R)], [(0.19, 0.14), (0.19, 0.26), (0.46, 0.255), (0.49, 0.24), (0.497, 0.22)], 0.14, RA),
              -hw + 0.012, hw - 0.012, "paint", 0.01, 2)
        prism("hood_bulge", [(0.2, 0.255), (0.44, 0.252), (0.44, 0.262), (0.22, 0.268)], -0.07, 0.07, "paint", 0.006, 2)
        box("grille", (0.497, 0, 0.2), (0.006, 0.2, 0.06), "dark", 0.0)
        for i in range(5):
            box("grille_slot", (0.501, -0.08 + i * 0.04, 0.2), (0.004, 0.008, 0.05), "steel", 0.0)
        for s in (1, -1):
            cyl("headlamp_bezel", (0.498, s * 0.13, 0.205), 0.022, 0.008, "dark", "X", 14)
            cyl("headlamp", (0.503, s * 0.13, 0.205), 0.017, 0.004, "lamp", "X", 14)
            arc_band("flare_f", XF, R, s * (hw - 0.03), s * (hw + 0.006), RA - 0.002, RA + 0.008, -5, 185, "black", 12)
            arc_band("flare_r", XR, R, s * (hw - 0.03), s * (hw + 0.006), RA - 0.002, RA + 0.008, -5, 185, "black", 12)
        box("bumper", (0.505, 0, 0.13), (0.03, 2 * hw, 0.045), "black", 0.004)
        tube("bull_bar", [(0.515, 0.1, 0.15), (0.535, 0.1, 0.24), (0.535, -0.1, 0.24), (0.515, -0.1, 0.15)], 0.008, "black", 6)
        tube("bull_bar2", [(0.535, 0.1, 0.21), (0.535, -0.1, 0.21)], 0.006, "black", 6)
        box("winch", (0.52, 0, 0.13), (0.02, 0.09, 0.03), "dark", 0.002)
        prism("cab", [(0.19, 0.14), (-0.08, 0.14), (-0.08, 0.36), (-0.065, 0.37), (0.1, 0.37), (0.19, 0.265)],
              -hw + 0.012, hw - 0.012, "paint", 0.01, 2)
        panel("windshield", (0.187, 0.272), (0.104, 0.364), -hw + 0.025, hw - 0.025, "glass", 0.003, -1.0)
        for s in (1, -1):
            side_panel("door_window", -0.03, 0.125, 0.275, 0.355, s * (hw - 0.012), "glass", 0.004)
            side_panel("door_seam", -0.045, -0.042, 0.15, 0.36, s * (hw - 0.011), "dark", 0.002)
            box("handle", (-0.025, s * (hw - 0.009), 0.255), (0.024, 0.006, 0.006), "black", 0.0)
            tube("mirror_arm", [(0.14, s * (hw - 0.012), 0.29), (0.15, s * (hw + 0.025), 0.3)], 0.003, "black", 5)
            box("mirror", (0.15, s * (hw + 0.03), 0.29), (0.008, 0.02, 0.04), "black", 0.002)
            box("rock_slider", (0.06, s * (hw - 0.012), 0.125), (0.24, 0.02, 0.012), "black", 0.002)
            tube("wiper", [(0.18, s * 0.02, 0.277), (0.165, s * 0.11, 0.3)], 0.0022, "black", 5)
        box("rear_window", (-0.082, 0, 0.31), (0.004, 2 * hw - 0.09, 0.06), "glass", 0.0)
        # шноркель по правой стойке
        tube("snorkel", [(0.24, -hw + 0.01, 0.2), (0.205, -hw - 0.004, 0.24), (0.15, -hw - 0.004, 0.36), (0.135, -hw - 0.004, 0.395)], 0.01, "black", 8)
        box("snorkel_head", (0.14, -hw - 0.004, 0.4), (0.04, 0.024, 0.02), "black", 0.003)
    # задние фонари на раме
    for s in (1, -1):
        box("tail_lamp", (-0.497, s * 0.13, 0.15), (0.006, 0.03, 0.03), "lamp_red", 0.0)
    if bed == "tray":
        # плоская платформа с низкими откидными бортами и щитом у кабины
        TZ = 0.165
        X0, X1 = -0.095, -0.5
        box("tray_deck", ((X0 + X1) / 2, 0, TZ), (X0 - X1, 2 * hw + 0.02, 0.014), "paint", 0.002)
        for i in range(4):
            box("tray_bearer", (X0 - 0.05 - i * 0.1, 0, TZ - 0.016), (0.014, 2 * hw, 0.018), "dark", 0.0)
        for s in (1, -1):
            box("tray_side", ((X0 + X1) / 2, s * (hw + 0.006), TZ + 0.025), (X0 - X1, 0.006, 0.038), "paint", 0.0015)
            for k in range(3):
                box("tray_post", (X0 - 0.06 - k * 0.14, s * (hw + 0.01), TZ + 0.025), (0.01, 0.004, 0.04), "dark", 0.0)
            box("mudguard", (XR, s * YW, TZ - 0.012), (0.18, TW + 0.02, 0.006), "black", 0.0)
            box("mudflap", (XR - R - 0.016, s * YW, 0.08), (0.004, TW + 0.006, 0.06), "black", 0.0)
        box("tray_tail", (X1 - 0.003, 0, TZ + 0.025), (0.006, 2 * hw + 0.02, 0.038), "paint", 0.0015)
        box("headboard", (X0 - 0.006, 0, TZ + 0.06), (0.01, 2 * hw + 0.02, 0.1), "paint", 0.002)
        for k in range(5):
            box("headboard_bar", (X0 - 0.012, -0.14 + k * 0.07, TZ + 0.13), (0.006, 0.01, 0.06), "dark", 0.0)
        tube("headboard_top", [(X0 - 0.012, hw + 0.01, TZ + 0.165), (X0 - 0.012, -hw - 0.01, TZ + 0.165)], 0.006, "dark", 6)
        box("toolbox", (X0 - 0.04, 0.11, TZ + 0.03), (0.06, 0.1, 0.045), "olive", 0.003)
        return TZ
    else:
        # кузов с бортами и вырезами над задними колёсами, тент на дугах
        BZ = 0.145
        X0, X1 = -0.09, -0.495
        prof = arch_profile([(X0, BZ)], [(XR, R)], [(X1, BZ), (X1, 0.25), (X0, 0.25)], BZ, RA)
        for s in (1, -1):
            prism("bed_side", prof, s * (hw - 0.012) if s > 0 else -hw, hw if s > 0 else -hw + 0.012, "paint", 0.003, 2)
            box("bed_rail", ((X0 + X1) / 2, s * (hw - 0.006), 0.253), (X0 - X1, 0.016, 0.008), "paint", 0.002)
            box("tail_lamp2", (X1 - 0.003, s * (hw - 0.02), 0.2), (0.006, 0.02, 0.04), "lamp_red", 0.0)
            for k in range(3):
                box("stake_pocket", (X0 - 0.06 - k * 0.15, s * (hw + 0.002), 0.242), (0.016, 0.006, 0.014), "dark", 0.0)
        box("bed_floor", ((X0 + X1) / 2, 0, BZ + 0.012), (X0 - X1, 2 * hw - 0.02, 0.012), "paint", 0.002)
        box("bed_front", (X0 - 0.006, 0, 0.2), (0.012, 2 * hw, 0.11), "paint", 0.002)
        box("tailgate", (X1 + 0.006, 0, 0.2), (0.012, 2 * hw - 0.024, 0.1), "paint", 0.002)
        box("tailgate_lip", (X1, 0, 0.245), (0.006, 2 * hw - 0.03, 0.01), "dark", 0.0)
        grp("tent", ((X0 + X1) / 2, 0, 0.25))
        bows = [X0 - 0.02, (X0 + X1) / 2, X1 + 0.02]
        tent_cover("tent_body", X1 + 0.004, X0 - 0.004, hw + 0.004, 0.235, 0.36, 0.395, bows, "canvas", 0.006, 8, 6)
        for x in bows:
            prof2 = [(hw + 0.008, 0.36)] + [((hw + 0.008) * math.cos(math.pi * i / 8), 0.36 + 0.037 * math.sin(math.pi * i / 8)) for i in range(1, 8)] + [(-hw - 0.008, 0.36)]
            tube("bow", [(x, y, z) for y, z in prof2], 0.003, "canvas_dark", 6)
        for s in (1, -1):
            for k in range(8):
                box("tie", (X0 - 0.03 - k * 0.052, s * (hw + 0.006), 0.24), (0.004, 0.003, 0.016), "canvas_dark", 0.0)
        cyl("flap_roll", (X1 - 0.004, 0, 0.345), 0.014, 2 * hw - 0.02, "canvas", "Y", 10)
        grp("", None)
        return BZ


def trap_loft(name, stations, zb, hb, ht, kind, bevel=0.006):
    """Корпус с наклонными бортами: stations — [(x, верх z)]; сечение — трапеция: низ zb ширина ±hb, верх ±ht"""
    secs = [[(x, hb, zb), (x, ht, zt), (x, -ht, zt), (x, -hb, zb)] for x, zt in stations]
    return loft(name, secs, kind, bevel, 2)


if kind == "scout":
    # --- дозорный броневик (по мотивам refs/armored_suv): широкий низкий корпус, бронированная рубка,
    # маленькие толстые окна, башенка со щитком и пулемётом, запаска на корме. Длина 5 м = 1 ---
    hw = 0.22
    R, TW = 0.088, 0.066
    YW = 0.176
    XF, XR = 0.31, -0.33
    for s, sd in ((1, "l"), (-1, "r")):
        wheel("wheel_f" + sd, (XF, s * YW, R), R, TW, R * 0.58, lugs=12, chevron=True, style="beadlock", depth=0.05)
        wheel("wheel_1" + sd, (XR, s * YW, R), R, TW, R * 0.58, lugs=12, chevron=True, style="beadlock", depth=0.05)
    for x in (XF, XR):
        box("axle_box", (x, 0, R + 0.005), (0.06, 2 * YW - TW, 0.03), "dark", 0.0)
        lathe("hub_red", [(0.0005, -0.03), (0.025, -0.025), (0.035, 0.0), (0.025, 0.025), (0.0005, 0.03)], (x, 0, R + 0.01), "dark", "Y", 10)
    box("belly", (0, 0, 0.115), (0.92, 0.2, 0.04), "dark", 0.0)
    RA = R + 0.02
    # нижний корпус: капот с крыльями, вырезы над колёсами, корма
    prism("body", arch_profile([(0.5, 0.135)], [(XF, R), (XR, R)], [(-0.5, 0.135), (-0.5, 0.25), (0.16, 0.25), (0.47, 0.268), (0.5, 0.245)], 0.135, RA),
          -hw, hw, "paint", 0.01, 2)
    # капот: решётки двигателя, центральный выступ
    prism("hood_center", [(0.17, 0.25), (0.46, 0.264), (0.46, 0.272), (0.18, 0.262)], -0.09, 0.09, "paint", 0.004, 2)
    for i in range(6):
        box("hood_louver", (0.3 + i * 0.02, 0, 0.268 + i * 0.0009), (0.008, 0.15, 0.004), "black", 0.0)
    # нос: решётка с вертикальными прорезями, фары в крыльях, бампер с лебёдкой, отбойник
    box("grille", (0.498, 0, 0.19), (0.006, 0.2, 0.08), "dark", 0.0)
    for i in range(7):
        box("grille_slot", (0.502, -0.075 + i * 0.025, 0.19), (0.004, 0.01, 0.07), "black", 0.0)
    for s in (1, -1):
        cyl("headlamp_bezel", (0.498, s * 0.165, 0.215), 0.022, 0.01, "dark", "X", 14)
        cyl("headlamp", (0.504, s * 0.165, 0.215), 0.017, 0.004, "lamp", "X", 14)
        box("turn", (0.501, s * 0.165, 0.18), (0.004, 0.03, 0.012), "lamp_amber", 0.0)
    box("bumper", (0.51, 0, 0.14), (0.03, 2 * hw, 0.04), "dark", 0.004)
    box("winch", (0.525, 0, 0.14), (0.02, 0.1, 0.028), "black", 0.002)
    tube("brush_guard", [(0.52, 0.09, 0.16), (0.535, 0.09, 0.26), (0.535, -0.09, 0.26), (0.52, -0.09, 0.16)], 0.007, "dark", 6)
    for s in (1, -1):
        box("tow_eye", (0.525, s * 0.15, 0.125), (0.02, 0.014, 0.02), "dark", 0.0)
    # бронированная рубка с наклонными бортами
    trap_loft("cabin", [(0.17, 0.255), (0.115, 0.39), (-0.455, 0.395), (-0.485, 0.375)], 0.245, hw - 0.004, hw - 0.04, "paint", 0.008)
    # лобовые: два толстых стекла в рамках
    for s in (1, -1):
        panel("windshield_frame", (0.168, 0.264), (0.118, 0.383), s * 0.012, s * 0.162, "dark", 0.004, -1.0)
        panel("windshield", (0.163, 0.27), (0.122, 0.377), s * 0.02, s * 0.155, "glass", 0.0065, -1.0)
    # двери: по две на борт, маленькие окна, швы, ручки; подножки
    for s in (1, -1):
        for x0, x1 in ((0.0, 0.1), (-0.22, -0.11)):
            side_panel("window_frame", x0 - 0.008, x1 + 0.008, 0.302, 0.372, s * (hw - 0.026), "dark", 0.006, 0.24)
            side_panel("window", x0, x1, 0.31, 0.364, s * (hw - 0.022), "glass", 0.006, 0.24)
        for x in (0.12, -0.08, -0.27):
            side_panel("door_seam", x, x + 0.003, 0.255, 0.38, s * (hw - 0.013), "dark", 0.004, 0.24)
        for x in (-0.065, -0.255):
            box("handle", (x, s * (hw - 0.004), 0.29), (0.03, 0.008, 0.01), "dark", 0.0)
        box("rock_slider", (-0.01, s * (hw - 0.006), 0.13), (0.38, 0.03, 0.014), "dark", 0.002)
        tube("mirror_arm", [(0.13, s * (hw - 0.03), 0.33), (0.15, s * (hw + 0.02), 0.34)], 0.003, "dark", 5)
        box("mirror", (0.15, s * (hw + 0.025), 0.325), (0.01, 0.025, 0.045), "dark", 0.002)
        box("tail_lamp", (-0.503, s * 0.18, 0.225), (0.006, 0.025, 0.04), "lamp_red", 0.0)
        cyl("whip_base", (-0.44, s * 0.17, 0.4), 0.008, 0.02, "dark", "Z", 8)
        tube("whip", [(-0.44, s * 0.17, 0.41), (-0.445, s * 0.17, 0.62)], 0.0018, "steel", 4)
    # корма: дверь и запасное колесо на ней
    box("rear_door_seam", (-0.487, 0, 0.31), (0.004, 0.003, 0.12), "dark", 0.0)
    spare_wheel((-0.53, 0.0, 0.29), R * 0.95, TW * 0.9, 90.0, lugs=12, chevron=True, style="beadlock")
    box("spare_mount", (-0.505, 0, 0.29), (0.03, 0.05, 0.05), "dark", 0.0)
    # крыша: люк, решётка вентиляции
    box("roof_vent", (-0.36, 0.08, 0.399), (0.08, 0.08, 0.008), "dark", 0.002)
    box("roof_hatch", (0.04, -0.08, 0.399), (0.08, 0.08, 0.008), "paint", 0.003)
    # башенка: погон, щиток из трёх листов, крупнокалиберный пулемёт, стрелок в люке
    TX, TZ = -0.12, 0.395
    grp("turret", (TX, 0, TZ))
    lathe("ring", [(0.085, 0.0), (0.09, 0.006), (0.09, 0.022), (0.08, 0.026)], (TX, 0, TZ), "dark", "Z", 20)
    for a, w in ((0, 0.11), (52, 0.07), (-52, 0.07)):
        R3 = Matrix.Rotation(math.radians(a), 3, "Z")
        c = Vector((TX, 0, 0)) + R3 @ Vector((0.085, 0, 0))
        box("shield", (c.x, c.y, TZ + 0.08), (0.008, w, 0.11), "paint", 0.003, rot=R3)
    box("shield_top", (TX + 0.088, 0, TZ + 0.137), (0.012, 0.11, 0.006), "paint", 0.0)
    box("shield_window", (TX + 0.092, 0.03, TZ + 0.11), (0.003, 0.03, 0.02), "glass", 0.0)
    z = TZ + 0.06
    box("mg_cradle", (TX + 0.04, 0, z), (0.06, 0.035, 0.02), "dark", 0.0)
    box("mg_receiver", (TX + 0.05, 0, z + 0.022), (0.11, 0.028, 0.03), "steel", 0.003)
    cyl("mg_barrel", (TX + 0.19, 0, z + 0.026), 0.006, 0.18, "steel", "X", 8)
    cyl("mg_jacket", (TX + 0.13, 0, z + 0.026), 0.01, 0.05, "dark", "X", 8)
    lathe("mg_muzzle", [(0.01, 0.0), (0.012, 0.01), (0.008, 0.025)], (TX + 0.28, 0, z + 0.026), "dark", "X", 8)
    box("mg_ammo", (TX + 0.04, 0.035, z + 0.006), (0.045, 0.03, 0.03), "olive", 0.002)
    person("gunner", TX - 0.03, 0, TZ - 0.17, 0.0, "stand", "cloth", "helmet")
    for s in (1, -1):
        tube("gunner_arm", [(TX - 0.025, s * 0.055, TZ + 0.165), (TX + 0.0, s * 0.05, TZ + 0.1), (TX + 0.02, s * 0.02, z + 0.02)], 0.013, "cloth", 6)
    grp("", None)
    name = "convoy_scout"

elif kind == "ifv":
    # --- боевая машина пехоты (по мотивам refs/bmp): высокий короб корпуса, бортовые экраны, двигатель спереди справа,
    # башня с длинной автоматической пушкой, кормовая дверь-аппарель. Длина 6,8 м = 1 ---
    hw = 0.22
    TW = 0.09
    YT = hw - TW / 2 - 0.004
    HT = 0.27
    RW, ZW = 0.042, 0.054
    xs = [0.3 - i * 0.108 for i in range(7)]
    SPR, IDL = (0.4, 0.1, 0.038), (-0.44, 0.085, 0.038)
    # обвод гусеницы: выпуклая оболочка катков, ленивца и ведущего колеса
    pts = []
    for cx, cz, r in [(x, ZW, RW) for x in xs] + [SPR, IDL]:
        for k in range(24):
            a = 2 * math.pi * k / 24
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    pts = sorted(set(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p_ in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p_) <= 0:
            lo.pop()
        lo.append(p_)
    for p_ in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p_) <= 0:
            hi.pop()
        hi.append(p_)
    hull = lo[:-1] + hi[:-1]           # против часовой (x вправо, z вверх)
    # равномерная разбивка по периметру
    per = [0.0]
    for i in range(len(hull)):
        a, b = hull[i], hull[(i + 1) % len(hull)]
        per.append(per[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    STEP = 0.015
    N = int(per[-1] / STEP)
    path = []
    j = 0
    for k in range(N):
        d = per[-1] * k / N
        while per[j + 1] < d:
            j += 1
        a, b = hull[j], hull[(j + 1) % len(hull)]
        f = (d - per[j]) / max(per[j + 1] - per[j], 1e-9)
        path.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    for side, s in (("l", 1), ("r", -1)):
        node = "track_" + side
        grp(node, (0, s * YT, 0.05))
        vs, fs = [], []
        for k in range(N):
            x0, z0 = path[k - 1]
            x1, z1 = path[(k + 1) % N]
            dx, dz = x1 - x0, z1 - z0
            l = math.hypot(dx, dz)
            nx, nz = dz / l, -dx / l          # наружу
            x, z = path[k]
            th = 0.012 if k % 2 else 0.019    # траки с грунтозацепами
            for o in (0.0, th):
                for y in (YT - TW / 2, YT + TW / 2):
                    vs.append((x + nx * o, s * y, z + nz * o))
        for k in range(N):
            a, b = 4 * k, 4 * ((k + 1) % N)
            fs += [(a, a + 1, b + 1, b), (a + 2, b + 2, b + 3, a + 3), (a, b, b + 2, a + 2), (a + 1, a + 3, b + 3, b + 1)]
        K._obj("track_belt", vs, fs, "rubber")
        yo = s * (YT + TW / 2 - 0.004)
        for x in xs:
            for dy in (-0.022, 0.022):
                lathe("roadwheel", [(RW - 0.004, dy - 0.012), (RW, dy - 0.009), (RW, dy + 0.009), (RW - 0.004, dy + 0.012), (RW * 0.55, dy + 0.012), (RW * 0.5, dy + 0.014), (0.0005, dy + 0.016)],
                      (x, s * YT, ZW), "dark", "Y", 14)
            cyl("hub", (x, s * (YT + 0.04), ZW), 0.012, 0.006, "steel", "Y", 8)
        for (cx, cz, r), nm in ((SPR, "sprocket"), (IDL, "idler")):
            lathe(nm, [(r * 0.9, -0.03), (r * 0.9, 0.03), (r * 0.4, 0.035), (0.0005, 0.038)], (cx, s * YT, cz), "dark", "Y", 16)
            if nm == "sprocket":
                for k in range(10):
                    a = 2 * math.pi * k / 10
                    box("tooth", (cx + math.cos(a) * r * 0.95, s * YT, cz + math.sin(a) * r * 0.95), (0.012, 0.05, 0.012), "steel", 0.0,
                        rot=("Y", -math.degrees(a)))
    grp("", None)
    # корпус: нижний между гусеницами, верхний во всю ширину с наклонными бортами, клиновидный нос
    prism("lower_hull", [(-0.47, 0.07), (0.42, 0.07), (0.5, 0.165), (-0.47, 0.165)], -(hw - TW - 0.006), hw - TW - 0.006, "paint", 0.006)
    trap_loft("upper_hull", [(0.5, 0.168), (0.33, HT), (-0.455, HT), (-0.48, HT - 0.015)], 0.15, hw + 0.004, hw - 0.026, "paint", 0.006)
    # бортовые экраны с болтами
    for s in (1, -1):
        prism("skirt", [(-0.45, 0.1), (0.36, 0.1), (0.42, 0.14), (0.42, 0.166), (-0.45, 0.166)], s * (hw + 0.004), s * (hw + 0.012), "paint", 0.003)
        for i in range(8):
            box("skirt_bolt", (-0.4 + i * 0.1, s * (hw + 0.014), 0.155), (0.008, 0.004, 0.008), "dark", 0.0)
        box("skirt_edge", (-0.02, s * (hw + 0.009), 0.102), (0.85, 0.012, 0.006), "dark", 0.0)
        # ящики ЗИП и буксирный трос по бортам
        box("stowage", (-0.32, s * (hw - 0.012), HT + 0.012), (0.16, 0.03, 0.024), "paint", 0.003)
        tube("tow_cable", [(0.28, s * (hw - 0.005), 0.2), (-0.1, s * (hw - 0.005), 0.21), (-0.42, s * (hw - 0.005), 0.2)], 0.004, "steel", 5)
        box("headlamp_guard", (0.45, s * 0.15, 0.21), (0.03, 0.04, 0.03), "dark", 0.0)
        box("headlamp", (0.456, s * 0.15, 0.205), (0.012, 0.028, 0.016), "lamp", 0.0)
        box("tail_lamp", (-0.483, s * 0.17, 0.24), (0.004, 0.02, 0.012), "lamp_red", 0.0)
        box("tow_hook", (0.49, s * 0.08, 0.12), (0.02, 0.014, 0.022), "dark", 0.0)
        box("rear_box", (-0.49, s * 0.15, 0.2), (0.03, 0.08, 0.1), "paint", 0.003)
    # запасные траки на лобовом листе
    for k in range(4):
        box("spare_link", (0.43, -0.12 + k * 0.035, 0.195 + 0.0), (0.03, 0.03, 0.006), "rubber", 0.0, rot=("Y", 33))
    # крыша: люк водителя, перископы, решётки двигателя справа, десантные люки, выхлоп
    cyl("driver_hatch", (0.3, 0.1, HT + 0.006), 0.035, 0.012, "paint", "Z", 14)
    for k in range(3):
        box("periscope", (0.345, 0.07 + k * 0.03, HT + 0.006), (0.012, 0.018, 0.012), "glass", 0.0)
    for i in range(5):
        box("engine_grille", (0.28 + i * 0.022, -0.1, HT + 0.002), (0.012, 0.13, 0.004), "black", 0.0)
    box("engine_deck", (0.325, -0.1, HT + 0.001), (0.12, 0.15, 0.002), "dark", 0.0)
    for s in (1, -1):
        box("troop_hatch", (-0.34, s * 0.07, HT + 0.005), (0.13, 0.08, 0.01), "paint", 0.003)
        box("troop_hinge", (-0.34, s * 0.11, HT + 0.008), (0.1, 0.008, 0.008), "dark", 0.0)
    box("exhaust", (0.36, -(hw + 0.003), 0.21), (0.08, 0.008, 0.03), "black", 0.0)
    # корма: большая дверь-аппарель
    box("rear_door", (-0.484, 0, 0.19), (0.006, 0.18, 0.13), "paint", 0.003)
    box("rear_door_hinge", (-0.487, 0, 0.126), (0.006, 0.16, 0.008), "dark", 0.0)
    box("rear_door_vision", (-0.488, 0.0, 0.225), (0.004, 0.03, 0.016), "glass", 0.0)
    # башня: граненая, сдвинута к корме, ниша сзади, прицелы, дымовые гранатомёты
    TX = -0.03
    grp("turret", (TX, 0, HT))
    lathe("turret_ring", [(0.105, 0.0), (0.108, 0.01), (0.1, 0.014)], (TX, 0, HT), "dark", "Z", 20)
    poly_b = [(TX + 0.15, 0.06), (TX + 0.1, 0.13), (TX - 0.14, 0.135), (TX - 0.22, 0.12), (TX - 0.22, -0.12), (TX - 0.14, -0.135), (TX + 0.1, -0.13), (TX + 0.15, -0.06)]
    poly_t = [(TX + 0.12, 0.05), (TX + 0.08, 0.11), (TX - 0.13, 0.115), (TX - 0.2, 0.105), (TX - 0.2, -0.105), (TX - 0.13, -0.115), (TX + 0.08, -0.11), (TX + 0.12, -0.05)]
    loft("turret_body", [[(x, y, HT + 0.012) for x, y in poly_b], [(x, y, HT + 0.06) for x, y in poly_b], [(x, y, HT + 0.09) for x, y in poly_t]], "paint", 0.006)
    box("bustle_basket", (TX - 0.235, 0, HT + 0.065), (0.04, 0.2, 0.04), "dark", 0.0)
    for k in range(3):
        box("basket_item", (TX - 0.235, -0.06 + k * 0.06, HT + 0.08), (0.03, 0.05, 0.03), "olive", 0.003)
    box("cmd_sight", (TX - 0.06, -0.07, HT + 0.12), (0.05, 0.045, 0.06), "paint", 0.004)
    box("cmd_sight_head", (TX - 0.04, -0.07, HT + 0.155), (0.04, 0.05, 0.02), "dark", 0.003)
    box("cmd_sight_glass", (TX - 0.019, -0.07, HT + 0.155), (0.003, 0.04, 0.014), "glass", 0.0)
    box("gunner_sight", (TX + 0.06, 0.08, HT + 0.105), (0.05, 0.04, 0.03), "paint", 0.003)
    box("gunner_sight_glass", (TX + 0.086, 0.08, HT + 0.107), (0.003, 0.03, 0.015), "glass", 0.0)
    cyl("cmd_hatch", (TX - 0.1, 0.05, HT + 0.093), 0.036, 0.008, "paint", "Z", 14)
    for s in (1, -1):
        for k in range(4):
            cyl("smoke_tube", (TX + 0.06 - k * 0.022, s * 0.128, HT + 0.08), 0.009, 0.045, "dark", (0.8, s * 0.6, 0.35), 8)
    tube("antenna", [(TX - 0.2, -0.09, HT + 0.09), (TX - 0.21, -0.09, HT + 0.33)], 0.002, "steel", 4)
    tube("antenna", [(TX - 0.2, 0.09, HT + 0.09), (TX - 0.21, 0.09, HT + 0.27)], 0.002, "steel", 4)
    # пушка — отдельный узел на башне
    grp("gun", (TX + 0.15, 0, HT + 0.05), "turret")
    box("mantlet", (TX + 0.165, 0, HT + 0.05), (0.05, 0.08, 0.055), "paint", 0.006)
    cyl("barrel_jacket", (TX + 0.23, 0, HT + 0.05), 0.015, 0.1, "paint", "X", 12)
    cyl("barrel", (TX + 0.37, 0, HT + 0.05), 0.0085, 0.24, "steel", "X", 10)
    cyl("muzzle_shroud", (TX + 0.48, 0, HT + 0.05), 0.013, 0.04, "dark", "X", 12)
    for k in range(4):
        cyl("muzzle_hole", (TX + 0.468 + k * 0.009, 0, HT + 0.063), 0.003, 0.003, "black", "Z", 6)
    cyl("coax", (TX + 0.2, 0.035, HT + 0.035), 0.004, 0.06, "black", "X", 6)
    grp("", None)
    name = "convoy_ifv"

elif kind == "crate":
    # --- ящик груза: доски с зазорами, планки, уголки, верёвочные ручки; длина = 1 ---
    L_, W_, H_ = 1.0, 0.7, 0.42
    for i in range(6):
        z = 0.035 + i * 0.07
        for s in (1, -1):
            box("plank", (0, s * W_ / 2, z), (L_ - 0.02, 0.03, 0.064), "wood", 0.006)
        for x in (-L_ / 2, L_ / 2):
            box("plank_end", (x, 0, z), (0.03, W_ - 0.02, 0.064), "wood", 0.006)
    for i in range(7):
        box("lid_plank", (0, -W_ / 2 + 0.05 + i * 0.1, H_ - 0.01), (L_ - 0.02, 0.094, 0.03), "wood", 0.006)
    box("core", (0, 0, H_ / 2), (L_ - 0.04, W_ - 0.04, H_ - 0.04), "black", 0.0)
    for x in (-0.3, 0.3):
        for s in (1, -1):
            box("batten", (x, s * (W_ / 2 + 0.018), H_ / 2), (0.08, 0.02, H_), "wood", 0.006)
        box("lid_batten", (x, 0, H_ + 0.012), (0.08, W_, 0.02), "wood", 0.006)
    for x in (-L_ / 2, L_ / 2):
        for y in (-W_ / 2, W_ / 2):
            box("corner", (x, y, H_ / 2), (0.06, 0.06, H_ + 0.02), "olive", 0.004)
    for s in (1, -1):
        tube("rope", [(-0.1, s * (W_ / 2 + 0.03), 0.28), (-0.05, s * (W_ / 2 + 0.06), 0.24), (0.05, s * (W_ / 2 + 0.06), 0.24), (0.1, s * (W_ / 2 + 0.03), 0.28)], 0.012, "canvas_dark", 6)
    name = "convoy_crate"

elif kind in ("technical", "manpads", "pickup_tent"):
    if kind == "pickup_tent":
        pickup("boxy", "tent")
    elif kind == "technical":
        TZ = pickup("boxy", "tray")
        # крупнокалиберный пулемёт на высокой тумбе посреди платформы, стрелок стоит за ним
        PX = -0.3
        cyl("pedestal_base", (PX, 0, TZ + 0.012), 0.05, 0.012, "dark", "Z", 12)
        for a in (45, 135, 225, 315):
            ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
            tube("pedestal_leg", [(PX + ca * 0.06, sa * 0.06, TZ + 0.01), (PX, 0, TZ + 0.12)], 0.005, "dark", 6)
        cyl("pedestal", (PX, 0, TZ + 0.15), 0.012, 0.1, "steel", "Z", 10)
        grp("turret", (PX, 0, TZ + 0.2))
        z = TZ + 0.205
        box("mg_cradle", (PX + 0.01, 0, z), (0.07, 0.04, 0.025), "dark", 0.003)
        box("mg_receiver", (PX + 0.02, 0, z + 0.025), (0.13, 0.03, 0.035), "steel", 0.003)
        cyl("mg_barrel", (PX + 0.17, 0, z + 0.03), 0.007, 0.2, "steel", "X", 8)
        cyl("mg_jacket", (PX + 0.11, 0, z + 0.03), 0.011, 0.07, "dark", "X", 8)
        lathe("mg_muzzle", [(0.012, 0.0), (0.014, 0.012), (0.009, 0.03)], (PX + 0.265, 0, z + 0.03), "dark", "X", 8)
        box("mg_rear_sight", (PX + 0.07, 0, z + 0.05), (0.008, 0.008, 0.018), "dark", 0.0)
        box("mg_grips", (PX - 0.055, 0, z + 0.02), (0.02, 0.05, 0.02), "dark", 0.0)
        box("mg_ammo", (PX + 0.02, 0.04, z + 0.008), (0.05, 0.035, 0.035), "olive", 0.003)
        tube("mg_belt", [(PX + 0.02, 0.025, z + 0.02), (PX + 0.03, 0.015, z + 0.03)], 0.004, "steel", 5)
        person("gunner", PX - 0.12, 0, TZ + 0.008, 0.0, "stand", "cloth", "wrap")
        tube("gunner_arm", [(PX - 0.115, 0.05, TZ + 0.3), (PX - 0.08, 0.045, TZ + 0.24), (PX - 0.06, 0.025, z + 0.02)], 0.013, "cloth", 6)
        tube("gunner_arm", [(PX - 0.115, -0.05, TZ + 0.3), (PX - 0.08, -0.045, TZ + 0.24), (PX - 0.06, -0.025, z + 0.02)], 0.013, "cloth", 6)
        grp("", None)
        for k in range(2):
            box("ammo_box", (-0.43, -0.08 + k * 0.05, TZ + 0.026), (0.07, 0.04, 0.04), "olive", 0.003)
        cyl("jerry", (-0.18, 0.13, TZ + 0.045), 0.02, 0.07, "olive", "Z", 8)
    else:
        TZ = pickup("modern", "tray")
        # расчёт ПЗРК: стрелок стоит в кузове с трубой на плече, второй номер на колене с запасной трубой
        GX = -0.32
        hip, top = person("gunner", GX, 0.05, TZ + 0.008, 0.0, "stand", "cloth", "helmet")
        grp("launcher", (GX, 0.05, top - 0.01))
        sh = top - 0.005
        cyl("tube", (GX + 0.03, 0.08, sh + 0.02), 0.016, 0.3, "olive", "X", 12)
        lathe("tube_front", [(0.018, 0.0), (0.02, 0.015), (0.0005, 0.016)], (GX + 0.18, 0.08, sh + 0.02), "black", "X", 12)
        lathe("tube_rear", [(0.0005, -0.016), (0.02, -0.015), (0.022, 0.0)], (GX - 0.12, 0.08, sh + 0.02), "dark", "X", 12)
        box("battery_unit", (GX + 0.05, 0.08, sh - 0.005), (0.03, 0.02, 0.025), "dark", 0.0)
        box("grip_unit", (GX + 0.02, 0.08, sh - 0.01), (0.05, 0.02, 0.03), "dark", 0.002)
        box("sight", (GX + 0.03, 0.105, sh + 0.035), (0.04, 0.012, 0.02), "dark", 0.0)
        tube("arm_r", [(GX + 0.0, 0.1, sh - 0.02), (GX + 0.03, 0.1, sh - 0.05), (GX + 0.03, 0.09, sh - 0.015)], 0.013, "cloth", 6)
        tube("arm_l", [(GX + 0.0, 0.0, sh - 0.02), (GX + 0.06, 0.03, sh - 0.06), (GX + 0.08, 0.075, sh - 0.02)], 0.013, "cloth", 6)
        grp("", None)
        person("loader", -0.42, -0.08, TZ + 0.008, 30.0, "kneel", "cloth2", "wrap", True)
        cyl("spare_tube", (-0.25, -0.11, TZ + 0.025), 0.016, 0.3, "olive", "X", 12)
        box("missile_case", (-0.2, -0.04, TZ + 0.03), (0.2, 0.05, 0.04), "olive", 0.003)
        box("missile_case2", (-0.2, 0.12, TZ + 0.03), (0.2, 0.05, 0.04), "olive", 0.003)
    name = "convoy_" + kind

root, tris = K.bake_export(name, OUT)
K.preview(OUT, name)
print("DONE", name, tris)
