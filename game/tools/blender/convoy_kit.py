"""Набор деталей и конвейер для техники конвоя, версия 2 (A-04, полноценная переработка моделей 18.10.2026).
Blender: Z вверх, X — нос машины, длина машины = 1, низ колёс на z = 0.
- Детали строятся из данных (from_pydata): ящики с фаской, профили, лофты, трубы по точкам, шины с протектором, диски.
- Материалы — «виды» (paint, dark, steel, rubber, glass, canvas, …). Каждый вид — процедурный шейдер Cycles:
  песочный камуфляж пятнами в координатах мира (пятна идут через детали), пыль снизу и в углублениях,
  затенение углов (AO), потёртые кромки, потёки на бортах.
- bake_export(): сливает детали по узлам (подвижные части — отдельные узлы), развёртка всей машины в один лист,
  запекание цвета (EMIT) и нормалей со скруглёнными кромками (NORMAL) в 1024 × 1024, два итоговых материала
  (корпус и стекло), экспорт .glb и .blend."""
import math, os
import bpy, bmesh
from mathutils import Vector, Matrix

CAMO = [(0.62, 0.52, 0.36), (0.50, 0.40, 0.27), (0.36, 0.30, 0.21)]   # решение Kanta 17.10: песок, охра, бурый
DUST = (0.66, 0.58, 0.45)
CAMO_SCALE = 1.0    # крупность пятен: у машин длина 1 ≈ 5–8 м; вертолёт (длина 1 ≈ 18 м) задаёт больше
CAMO_STRETCH = (1, 1, 1)   # вытянутость пятен по осям
BELLY = None        # цвет низа (снизу смотрящие поверхности камуфляжа), None — без него
EDGE_K = 1.0        # скругление кромок и затенение углов (в долях длины): у крупных моделей (корабль) меньше
AO_K = 1.0
# итоговая краска (Kanta 19.10: окраска реалистичная и матовая, «без блеска и пластика»): корпус и стекло/фары
BODY_ROUGH, BODY_METAL = 0.9, 0.0
GLASS_ROUGH, GLASS_METAL = 0.35, 0.05

parts = []
group = ""          # пусто — корпус; иначе подвижная часть (узел GLB)
pivots = {}
PARENT = {}
_mats = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts.clear()
    pivots.clear()
    PARENT.clear()
    _mats.clear()


# ---------------------------------------------------------------- шейдеры для запекания
def _n(nt, typ, **kw):
    n = nt.nodes.new(typ)
    for k, v in kw.items():
        if k.startswith("_"):
            setattr(n, k[1:], v)
            continue
        s = n.inputs[k]
        if hasattr(v, "is_output") or isinstance(v, bpy.types.NodeSocket):
            nt.links.new(v, s)
        else:
            s.default_value = v
    return n


def lin(c):
    """Цвет как на картинке (sRGB) → линейный для шейдера"""
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c[:3])


def _sock(nt, v):
    """Число / цвет (в sRGB, как в палитре) → сокет-значение"""
    if isinstance(v, bpy.types.NodeSocket):
        return v
    if isinstance(v, (tuple, list)):
        n = nt.nodes.new("ShaderNodeRGB")
        n.outputs[0].default_value = (*lin(v), 1)
        return n.outputs[0]
    n = nt.nodes.new("ShaderNodeValue")
    n.outputs[0].default_value = v
    return n.outputs[0]


def _m(nt, op, a, b=0.0, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    nt.links.new(_sock(nt, a), n.inputs[0])
    nt.links.new(_sock(nt, b), n.inputs[1])
    return n.outputs[0]


def _mix(nt, fac, a, b, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    ins = [s for s in n.inputs if s.type == "RGBA"]
    nt.links.new(_sock(nt, fac), n.inputs[0])
    nt.links.new(_sock(nt, a), ins[0])
    nt.links.new(_sock(nt, b), ins[1])
    return [s for s in n.outputs if s.type == "RGBA"][0]


def _noise(nt, pos, scale, detail=2.0, off=(0, 0, 0), stretch=(1, 1, 1)):
    v = pos
    if stretch != (1, 1, 1):
        vm = nt.nodes.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY"
        nt.links.new(v, vm.inputs[0])
        vm.inputs[1].default_value = stretch
        v = vm.outputs[0]
    if off != (0, 0, 0):
        vm = nt.nodes.new("ShaderNodeVectorMath")
        vm.operation = "ADD"
        nt.links.new(v, vm.inputs[0])
        vm.inputs[1].default_value = off
        v = vm.outputs[0]
    n = _n(nt, "ShaderNodeTexNoise", Vector=v, Scale=scale, Detail=detail)
    return n.outputs["Fac"]


def _band(nt, x, lo, hi):
    """Гладкая ступень 0→1 между lo и hi"""
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = "SMOOTHSTEP"
    nt.links.new(_sock(nt, x), n.inputs["Value"])
    n.inputs["From Min"].default_value = lo
    n.inputs["From Max"].default_value = hi
    return n.outputs["Result"]


# вид → (цвет, металл, шероховатость, пыль, камуфляж)
KINDS = {
    "paint": (CAMO[0], 0.1, 0.7, 1.0, True),
    "dark": ((0.1, 0.095, 0.085), 0.3, 0.6, 1.0, False),       # рама, мосты, решётки, резина уплотнителей
    "steel": ((0.3, 0.29, 0.27), 0.7, 0.45, 0.6, False),
    "rubber": ((0.07, 0.068, 0.064), 0.0, 0.9, 0.45, False),
    "glass": ((0.06, 0.08, 0.09), 0.0, 0.1, 0.35, False),
    "canvas": ((0.53, 0.47, 0.35), 0.0, 0.95, 0.8, False),     # выгоревший брезент
    "canvas_dark": ((0.33, 0.29, 0.21), 0.0, 0.95, 0.6, False),
    "cloth": ((0.36, 0.33, 0.25), 0.0, 0.9, 0.5, False),       # одежда
    "cloth2": ((0.27, 0.27, 0.22), 0.0, 0.9, 0.5, False),
    "skin": ((0.42, 0.29, 0.21), 0.0, 0.7, 0.2, False),
    "wood": ((0.47, 0.36, 0.22), 0.0, 0.85, 0.5, False),
    "lamp": ((0.85, 0.85, 0.8), 0.2, 0.15, 0.3, False),
    "lamp_red": ((0.6, 0.08, 0.05), 0.2, 0.3, 0.3, False),
    "lamp_amber": ((0.8, 0.45, 0.08), 0.2, 0.3, 0.3, False),
    "olive": ((0.32, 0.31, 0.22), 0.1, 0.7, 0.8, False),       # ящики, канистры, трубы ПЗРК
    "black": ((0.025, 0.025, 0.025), 0.2, 0.6, 0.3, False),    # провалы, бойницы, стволы изнутри
    # позиция ПВО (ground_models.py): земля и глина Нагорья, бетон, мешки, маскировочная сеть
    "earth": ((0.52, 0.45, 0.34), 0.0, 1.0, 0.6, False),
    "earth_dark": ((0.4, 0.33, 0.24), 0.0, 1.0, 0.5, False),   # утоптанное дно траншеи
    "concrete": ((0.47, 0.44, 0.38), 0.0, 0.95, 0.9, False),   # выгоревший бетон в пыли
    "sandbag": ((0.6, 0.52, 0.38), 0.0, 1.0, 0.5, False),
    "net": ((0.43, 0.38, 0.27), 0.0, 1.0, 0.3, False),
    "net2": ((0.5, 0.44, 0.3), 0.0, 1.0, 0.3, False),
}


def kmat(kind):
    """Материал вида для запекания: выход EMIT — итоговый цвет; узел bsdf (нормаль со скруглением) — для NORMAL"""
    if kind in _mats:
        return _mats[kind]
    base, metal, rough, dust, camo = KINDS[kind]
    m = bpy.data.materials.new(kind)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    z = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(pos, z.inputs[0])
    nz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], nz.inputs[0])
    up = _m(nt, "MAXIMUM", nz.outputs["Z"], 0.0)
    side = _m(nt, "SUBTRACT", 1.0, _m(nt, "ABSOLUTE", nz.outputs["Z"]))
    if camo:
        n1 = _noise(nt, pos, 4.4 * CAMO_SCALE, 3.0, stretch=tuple(CAMO_STRETCH))
        n2 = _noise(nt, pos, 5.0 * CAMO_SCALE, 3.0, (5.3, 1.7, 9.1), tuple(CAMO_STRETCH))
        m1 = _band(nt, n1, 0.525, 0.532)
        m2 = _m(nt, "MULTIPLY", _band(nt, n2, 0.56, 0.567), _m(nt, "SUBTRACT", 1.0, m1))
        col = _mix(nt, m1, CAMO[0], CAMO[1])
        col = _mix(nt, m2, col, CAMO[2])
        if BELLY is not None:
            # низ (поверхности, смотрящие вниз) — отдельным цветом, как у вертолётов и самолётов
            col = _mix(nt, _band(nt, _m(nt, "MULTIPLY", nz.outputs["Z"], -1.0), 0.5, 0.62), col, BELLY)
    else:
        col = _sock(nt, base)
    # неровность краски / материала
    fine = _noise(nt, pos, 70.0, 4.0)
    col = _mix(nt, 1.0, col, _m(nt, "ADD", 0.9, _m(nt, "MULTIPLY", fine, 0.2)), "MULTIPLY")
    if kind in ("canvas", "canvas_dark"):
        # пятна выгорания и разводы на брезенте
        bl = _noise(nt, pos, 6.0, 4.0, (2.0, 7.0, 1.0))
        col = _mix(nt, _m(nt, "MULTIPLY", _band(nt, bl, 0.45, 0.7), 0.35), col, (0.6, 0.55, 0.44))
        dk = _noise(nt, pos, 9.0, 3.0, (8.0, 1.0, 3.0))
        col = _mix(nt, _m(nt, "MULTIPLY", _band(nt, dk, 0.55, 0.75), 0.3), col, (0.25, 0.22, 0.17))
    if kind in ("earth", "earth_dark", "concrete", "sandbag", "net", "net2"):
        # земля и бетон: крупные пятна светлее и темнее (выгорание, сырость, разводы), сеть — лоскутами
        big = _noise(nt, pos, 5.0 if kind != "net" else 14.0, 3.0, (4.0, 2.0, 7.0))
        col = _mix(nt, _m(nt, "MULTIPLY", _band(nt, big, 0.42, 0.62), 0.45), col, tuple(min(1.0, c * 1.18) for c in base))
        dk = _noise(nt, pos, 11.0 if kind != "net" else 24.0, 3.0, (9.0, 3.0, 1.0))
        col = _mix(nt, _m(nt, "MULTIPLY", _band(nt, dk, 0.55, 0.72), 0.4), col, tuple(c * 0.72 for c in base))
    if kind == "concrete":
        # подтёки на стенках
        st = _noise(nt, pos, 9.0, 2.0, (0, 0, 0), (6.0, 6.0, 0.6))
        col = _mix(nt, _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", _band(nt, st, 0.56, 0.72), side), 0.25), col, (0.33, 0.3, 0.25))
    if camo:
        # выгорание сверху на солнце
        col = _mix(nt, _m(nt, "MULTIPLY", up, 0.12), col, (0.8, 0.74, 0.62))
        # потёки на бортах
        st = _noise(nt, pos, 9.0, 2.0, (0, 0, 0), (6.0, 6.0, 0.6))
        col = _mix(nt, _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", _band(nt, st, 0.56, 0.72), side), 0.22), col, (0.2, 0.17, 0.12))
    # потёртые кромки: нормаль со скруглением отличается от настоящей
    bev = _n(nt, "ShaderNodeBevel", Radius=0.006 * EDGE_K)
    bev.samples = 6
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs[0], dot.inputs[0])
    nt.links.new(geo.outputs["True Normal"], dot.inputs[1])
    edge = _band(nt, _m(nt, "SUBTRACT", 1.0, dot.outputs["Value"]), 0.01, 0.08)
    if kind in ("paint", "olive", "dark", "steel"):
        wn = _noise(nt, pos, 30.0, 3.0, (3.3, 0.0, 1.1))
        wear = _m(nt, "MULTIPLY", edge, _band(nt, wn, 0.4, 0.6))
        wc = (0.72, 0.66, 0.55) if kind == "paint" else (0.42, 0.4, 0.37)
        col = _mix(nt, _m(nt, "MULTIPLY", wear, 0.75), col, wc)
    # затенение углов
    ao = _n(nt, "ShaderNodeAmbientOcclusion", Distance=0.035 * AO_K)
    ao.samples = 16
    ao.only_local = False
    # пыль: снизу (колёса, пороги), в углублениях, тонким слоем сверху
    if dust > 0:
        dn = _noise(nt, pos, 14.0, 3.0, (1.1, 2.2, 3.3))
        low = _m(nt, "MULTIPLY", _m(nt, "SUBTRACT", 1.0, _band(nt, z.outputs["Z"], 0.03, 0.16)), _m(nt, "ADD", 0.1, _m(nt, "MULTIPLY", dn, 0.6)))
        crev = _m(nt, "MULTIPLY", _m(nt, "SUBTRACT", 1.0, ao.outputs["AO"]), 0.3)
        top = _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", up, up), _m(nt, "MULTIPLY", _band(nt, dn, 0.5, 0.75), 0.2))
        d = _m(nt, "MULTIPLY", _m(nt, "ADD", _m(nt, "ADD", low, crev), top), dust, True)
        col = _mix(nt, _m(nt, "MINIMUM", d, 0.6), col, DUST)
    occl = _m(nt, "ADD", 0.42, _m(nt, "MULTIPLY", ao.outputs["AO"], 0.58))
    col = _mix(nt, 1.0, col, occl, "MULTIPLY")
    em = _n(nt, "ShaderNodeEmission", Color=col, Strength=1.0)
    # нормаль: скругление кромок + мелкая фактура
    nrm = _n(nt, "ShaderNodeBevel", Radius=0.004 * EDGE_K)
    nrm.samples = 8
    bump_str = 0.25 if kind.startswith("canvas") or kind in ("earth", "sandbag", "net", "net2") else 0.12 if kind == "concrete" else 0.05 if kind in ("paint", "olive") else 0.0
    nsock = nrm.outputs[0]
    if bump_str > 0:
        h = _noise(nt, pos, 40.0 if kind.startswith("canvas") or kind in ("earth", "sandbag", "net", "net2") else 120.0, 6.0)
        bp = _n(nt, "ShaderNodeBump", Strength=bump_str, Distance=0.002, Height=h, Normal=nsock)
        nsock = bp.outputs[0]
    bs = _n(nt, "ShaderNodeBsdfPrincipled", Normal=nsock)
    bs.name = "bsdf"
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.name = "out"
    nt.links.new(em.outputs[0], out.inputs[0])
    m["emit"] = em.name
    m["fh_metal"] = metal
    m["fh_rough"] = rough
    _mats[kind] = m
    return m


# ---------------------------------------------------------------- детали
def _obj(name, verts, faces, kind, bevel=0.0, seg=2, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(kmat(kind))
    if bevel > 0:
        md = ob.modifiers.new("bev", "BEVEL")
        md.width = bevel
        md.segments = seg
        md.limit_method = "ANGLE"
        md.angle_limit = math.radians(35)
        md.harden_normals = False
    ob["fh_group"] = group
    ob["fh_smooth"] = smooth
    parts.append(ob)
    return ob


def box(name, c, s, kind, bevel=0.003, seg=2, rot=None):
    """Ящик: центр c, размеры s; rot — (ось, угол°) или Matrix"""
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    vs = [Vector((x, y, z)) for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)]
    if rot is not None:
        R = rot if isinstance(rot, Matrix) else Matrix.Rotation(math.radians(rot[1]), 3, rot[0])
        vs = [R @ v for v in vs]
    vs = [v + Vector(c) for v in vs]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return _obj(name, vs, f, kind, bevel, seg)


def _frame(axis):
    """Ось цилиндра → (u, v, w) ортонормированные, w — ось"""
    w = Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis]) if isinstance(axis, str) else Vector(axis).normalized()
    u = w.orthogonal().normalized()
    v = w.cross(u)
    return u, v, w


def cyl(name, c, r, h, kind, axis="Z", n=16, bevel=0.0, r2=None, cap=True):
    """Цилиндр (или усечённый конус r → r2) по оси через центр c"""
    u, v, w = _frame(axis)
    c = Vector(c)
    r2 = r if r2 is None else r2
    vs = []
    for rr, t in ((r, -h / 2), (r2, h / 2)):
        for i in range(n):
            a = 2 * math.pi * i / n
            vs.append(c + w * t + (u * math.cos(a) + v * math.sin(a)) * rr)
    f = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    if cap:
        f += [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    return _obj(name, vs, f, kind, bevel, 2)


def lathe(name, prof, c, kind, axis="Y", n=16, cap0=False, cap1=False):
    """Тело вращения: prof — [(радиус, смещение по оси)]"""
    u, v, w = _frame(axis)
    c = Vector(c)
    vs = []
    for r, t in prof:
        for i in range(n):
            a = 2 * math.pi * i / n
            vs.append(c + w * t + (u * math.cos(a) + v * math.sin(a)) * r)
    f = []
    for j in range(len(prof) - 1):
        for i in range(n):
            f.append((j * n + i, j * n + (i + 1) % n, (j + 1) * n + (i + 1) % n, (j + 1) * n + i))
    if cap0:
        f.append(tuple(range(n))[::-1])
    if cap1:
        k = (len(prof) - 1) * n
        f.append(tuple(range(k, k + n)))
    return _obj(name, vs, f, kind)


def prism(name, prof, y0, y1, kind, bevel=0.004, seg=2):
    """Профиль (x, z) сбоку, выдавлен по Y от y0 до y1"""
    n = len(prof)
    vs = [(x, y0, z) for x, z in prof] + [(x, y1, z) for x, z in prof]
    f = [tuple(range(n)), tuple(range(n, 2 * n))[::-1]] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return _obj(name, vs, f, kind, bevel, seg)


def prism_x(name, prof, x0, x1, kind, bevel=0.004, seg=2):
    """Профиль (y, z) в сечении, выдавлен по X от x0 до x1"""
    n = len(prof)
    vs = [(x0, y, z) for y, z in prof] + [(x1, y, z) for y, z in prof]
    f = [tuple(range(n)), tuple(range(n, 2 * n))[::-1]] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return _obj(name, vs, f, kind, bevel, seg)


def prism_z(name, prof, z0, z1, kind, bevel=0.004, seg=2):
    """Профиль (x, y) сверху, выдавлен по Z от z0 до z1"""
    n = len(prof)
    vs = [(x, y, z0) for x, y in prof] + [(x, y, z1) for x, y in prof]
    f = [tuple(range(n)), tuple(range(n, 2 * n))[::-1]] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return _obj(name, vs, f, kind, bevel, seg)


def loft(name, secs, kind, bevel=0.0, seg=2, caps=True):
    """Лофт по замкнутым сечениям (одинаковое число точек), сечения — списки 3D-точек"""
    n = len(secs[0])
    vs = [p for s in secs for p in s]
    f = []
    for j in range(len(secs) - 1):
        for i in range(n):
            f.append((j * n + i, j * n + (i + 1) % n, (j + 1) * n + (i + 1) % n, (j + 1) * n + i))
    if caps:
        f += [tuple(range(n))[::-1], tuple(range((len(secs) - 1) * n, len(secs) * n))]
    return _obj(name, vs, f, kind, bevel, seg)


def tube(name, pts, r, kind, n=8, closed=False):
    """Труба по точкам с плавными стыками (рамы, дуги, поручни)"""
    P = [Vector(p) for p in pts]
    m = len(P)
    T = []
    for i in range(m):
        if closed:
            a, b = P[i - 1], P[(i + 1) % m]
        else:
            a, b = P[max(i - 1, 0)], P[min(i + 1, m - 1)]
        T.append((b - a).normalized())
    u = T[0].orthogonal().normalized()
    vs = []
    for i in range(m):
        if i > 0:
            u = (u - T[i] * u.dot(T[i])).normalized()
        v = T[i].cross(u)
        # на изгибе сечение растягивается, чтобы труба не худела
        k = 1.0
        if 0 < i < m - 1 or closed:
            d0 = (P[i] - P[i - 1]).normalized()
            d1 = (P[(i + 1) % m] - P[i]).normalized()
            k = 1.0 / max(math.cos(d0.angle(d1) / 2), 0.5) if d0.length > 0 and d1.length > 0 else 1.0
        for j in range(n):
            a = 2 * math.pi * j / n
            vs.append(P[i] + (u * math.cos(a) + v * math.sin(a) * k) * r)
    f = []
    segs = m if closed else m - 1
    for i in range(segs):
        i1 = (i + 1) % m
        for j in range(n):
            f.append((i * n + j, i * n + (j + 1) % n, i1 * n + (j + 1) % n, i1 * n + j))
    if not closed:
        f += [tuple(range(n))[::-1], tuple(range((m - 1) * n, m * n))]
    return _obj(name, vs, f, kind)


def arc_band(name, cx, cz, y0, y1, r0, r1, a0, a1, kind, n=10, bevel=0.002):
    """Крыло колеса: дуга в плоскости XZ вокруг (cx, cz) от угла a0 до a1 (°, 0 — вперёд, 90 — вверх)"""
    secs = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        ca, sa = math.cos(a), math.sin(a)
        secs.append([(cx + ca * r0, y0, cz + sa * r0), (cx + ca * r1, y0, cz + sa * r1),
                     (cx + ca * r1, y1, cz + sa * r1), (cx + ca * r0, y1, cz + sa * r0)])
    return loft(name, secs, kind, bevel)


def panel(name, p0, p1, y0, y1, kind, t=0.002, out=1.0):
    """Плоская панель (стекло, щиток) на наклонной плоскости: отрезок p0–p1 в XZ, по Y от y0 до y1,
    приподнята над поверхностью на t по нормали (out = ±1 — в какую сторону нормаль)"""
    x0, z0 = p0
    x1, z1 = p1
    dx, dz = x1 - x0, z1 - z0
    l = math.hypot(dx, dz)
    nx, nz = dz / l * out, -dx / l * out
    vs = []
    for o in (0.0, t):
        for (x, z) in ((x0, z0), (x1, z1)):
            for y in (y0, y1):
                vs.append((x + nx * o, y, z + nz * o))
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return _obj(name, vs, f, kind, 0.0)


def side_panel(name, x0, x1, z0, z1, y, kind, t=0.003, slope=0.0):
    """Панель на борту (окно, дверь): прямоугольник в плоскости XZ у борта y (знак — сторона)"""
    s = 1 if y > 0 else -1
    vs = []
    for o in (-t / 2, t / 2):
        for x in (x0, x1):
            for z in (z0, z1):
                vs.append((x, y + s * o - s * slope * (z - z0), z))
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return _obj(name, vs, f, kind, 0.0)


# ---------------------------------------------------------------- колёса
def tyre(name, c, r, w, rim_r, kind="rubber", lugs=12, depth=0.045, chevron=True):
    """Шина с протектором: профиль поперёк × кольцо; грунтозацепы ёлочкой (chevron) или дорожный рисунок"""
    c = Vector(c)
    prof = [(-0.5, rim_r / r, 0), (-0.5, 0.88, 0), (-0.38, 1.0, 1), (0.0, 1.0, 1), (0.38, 1.0, 1),
            (0.5, 0.88, 0), (0.5, rim_r / r, 0)]
    M = lugs * 4
    vs = []
    for j in range(M):
        a = 2 * math.pi * j / M
        for dy, rf, tread in prof:
            k = rf
            if tread:
                shift = int(round(abs(dy) * 2.5)) if chevron else 0
                k -= depth if ((j + shift) % 4) >= 2 else 0.0
            rr = r * k
            vs.append(c + Vector((math.cos(a) * rr, dy * w, math.sin(a) * rr)))
    P = len(prof)
    f = []
    for j in range(M):
        j1 = (j + 1) % M
        for i in range(P - 1):
            f.append((j * P + i, j * P + i + 1, j1 * P + i + 1, j1 * P + i))
    return _obj(name, vs, f, kind)


def rim(name, c, r, w, side, kind="paint", bolts=8, n=16, style="steel"):
    """Диск колеса снаружи (side = ±1 — где наружная сторона): обод, тарелка, ступица, болты; изнутри — заглушка"""
    c = Vector(c)
    s = side
    if style == "beadlock":
        prof = [(r * 1.02, s * w * 0.42), (r * 0.98, s * w * 0.48), (r * 0.9, s * w * 0.46), (r * 0.62, s * w * 0.3),
                (r * 0.42, s * w * 0.34), (r * 0.36, s * w * 0.42), (r * 0.18, s * w * 0.44), (0.0005, s * w * 0.45)]
    else:
        prof = [(r * 1.02, s * w * 0.44), (r * 0.97, s * w * 0.48), (r * 0.88, s * w * 0.4), (r * 0.66, s * w * 0.26),
                (r * 0.45, s * w * 0.3), (r * 0.36, s * w * 0.4), (r * 0.2, s * w * 0.42), (0.0005, s * w * 0.43)]
    lathe(name, prof, c, kind, "Y", n)
    lathe(name + "_in", [(r * 1.0, -s * w * 0.46), (0.0005, -s * w * 0.4)], c, "dark", "Y", 12)
    for i in range(bolts):
        a = 2 * math.pi * (i + 0.5) / bolts
        cyl(name + "_bolt", c + Vector((math.cos(a) * r * 0.29, s * w * 0.43, math.sin(a) * r * 0.29)),
            r * 0.05, w * 0.06, "steel", "Y", 6)
    # отверстия в тарелке
    if style == "steel":
        for i in range(6):
            a = 2 * math.pi * i / 6
            cyl(name + "_hole", c + Vector((math.cos(a) * r * 0.55, s * w * 0.29, math.sin(a) * r * 0.55)),
                r * 0.09, w * 0.03, "black", "Y", 8)


def wheel(node, c, r, w, rim_r=None, rim_kind="paint", lugs=12, chevron=True, style="steel", depth=0.045):
    """Колесо отдельным узлом (качение вокруг локальной Y; передние — ещё руль вокруг Z)"""
    global group
    g0 = group
    group = node
    pivots[node] = tuple(c)
    side = 1 if c[1] > 0 else -1
    rr = rim_r or r * 0.6
    tyre(node + "_tyre", c, r, w, rr, lugs=lugs, chevron=chevron, depth=depth)
    rim(node + "_rim", c, rr, w, side, rim_kind, style=style)
    group = g0


# ---------------------------------------------------------------- человек (расчёт пулемёта, ПЗРК)
def person(name, x, y, z, yaw=0.0, pose="stand", kind="cloth", head="helmet", arms=False):
    """Боец ростом 1,8 м в масштабе пикапа (длина 5,2 м = 1): стоя ≈ 0,36. pose: stand | kneel | sit;
    head: helmet — каска, wrap — платок; arms — руки опущены вперёд (иначе руки строит вызывающий)"""
    R = Matrix.Rotation(math.radians(yaw), 3, "Z")
    o = Vector((x, y, z))

    def P(px, py, pz):
        return tuple(o + R @ Vector((px, py, pz)))
    hip = {"stand": 0.18, "kneel": 0.1, "sit": 0.09}[pose]
    if pose == "stand":
        for s in (1, -1):
            tube(name + "_leg", [P(0, s * 0.03, 0.005), P(0.005, s * 0.03, 0.09), P(0, s * 0.03, hip)], 0.018, kind, 6)
            box(name + "_boot", P(0.015, s * 0.03, 0.01), (0.05, 0.03, 0.022), "black", 0.004, rot=R)
    elif pose == "kneel":
        tube(name + "_leg", [P(-0.07, 0.03, 0.012), P(0.0, 0.03, 0.02), P(0.0, 0.03, hip)], 0.018, kind, 6)
        tube(name + "_leg", [P(0.07, -0.03, 0.005), P(0.07, -0.03, 0.06), P(0.0, -0.03, hip)], 0.018, kind, 6)
    else:
        for s in (1, -1):
            tube(name + "_leg", [P(0.09, s * 0.03, 0.005), P(0.09, s * 0.03, 0.06), P(0.0, s * 0.03, hip)], 0.018, kind, 6)
    top = hip + 0.15

    def ring(zc, rx, ry, dx=0.0, n=8):
        return [P(dx + rx * math.cos(2 * math.pi * k / n), ry * math.sin(2 * math.pi * k / n), zc) for k in range(n)]
    loft(name + "_torso", [ring(hip - 0.01, 0.03, 0.045), ring(hip + 0.03, 0.032, 0.05), ring(hip + 0.1, 0.036, 0.06, 0.004),
                           ring(top - 0.012, 0.032, 0.058), ring(top, 0.02, 0.03)], kind)
    if arms:
        for s in (1, -1):
            tube(name + "_arm", [P(0, s * 0.058, top - 0.015), P(0.01, s * 0.064, top - 0.08), P(0.04, s * 0.05, top - 0.12)], 0.013, kind, 6)
    # разгрузка
    box(name + "_vest", P(0.033, 0, hip + 0.09), (0.016, 0.08, 0.06), "olive", 0.003, rot=R)
    lathe(name + "_neck", [(0.016, 0.0), (0.016, 0.02)], P(0, 0, top), "skin", "Z", 8)
    hz = top + 0.045
    lathe(name + "_head", [(0.0005, -0.03), (0.022, -0.025), (0.028, -0.005), (0.026, 0.015), (0.0005, 0.028)], P(0.002, 0, hz), "skin", "Z", 10)
    if head == "helmet":
        lathe(name + "_helmet", [(0.035, -0.002), (0.033, 0.01), (0.026, 0.026), (0.0005, 0.034)], P(-0.002, 0, hz), "olive", "Z", 12)
    else:
        lathe(name + "_wrap", [(0.031, -0.01), (0.032, 0.012), (0.022, 0.03), (0.0005, 0.034)], P(-0.003, 0, hz), "cloth2", "Z", 10)
    return hip, top


# ---------------------------------------------------------------- сборка, развёртка, запекание
def _select(obs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or obs[0]


def bake_export(name, out, tex=1024, glass_kinds=("glass", "lamp", "lamp_red", "lamp_amber")):
    os.makedirs(out, exist_ok=True)
    sc = bpy.context.scene
    for ob in parts:
        _select([ob])
        for md in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
    # развёртка по деталям; мелким деталям — меньше места на листе, крупным панелям — больше
    _select(parts)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for ob in parts:
        d = max(ob.dimensions)
        f = min(max(d / 0.2, 0.3), 1.0)
        uv = ob.data.uv_layers[0].data
        for l in uv:
            l.uv = l.uv * f
    # слить по узлам
    groups = {}
    for ob in parts:
        groups.setdefault(ob["fh_group"], []).append(ob)
    root = None
    joined = []
    tris = 0
    for gname, obs in groups.items():
        _select(obs)
        bpy.ops.object.join()
        j = bpy.context.object
        j.name = gname if gname else name
        j.data.name = j.name
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(32))
        tris += sum(len(p.vertices) - 2 for p in j.data.polygons)
        joined.append(j)
        if gname:
            sc.cursor.location = pivots.get(gname, (0, 0, 0))
            bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        else:
            root = j
    # развёртка всей машины в один лист
    _select(joined, root)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True, scale=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    # запекание
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 12
    sc.cycles.use_denoising = False
    img_c = bpy.data.images.new(name + "_color", tex, tex)
    img_n = bpy.data.images.new(name + "_normal", tex, tex)
    img_n.colorspace_settings.name = "Non-Color"
    used = {s.material for o in joined for s in o.material_slots if s.material}
    for m in used:
        nt = m.node_tree
        t = nt.nodes.new("ShaderNodeTexImage")
        t.name = "bake_target"
        nt.nodes.active = t
    _select(joined, root)
    for img, typ in ((img_c, "EMIT"), (img_n, "NORMAL")):
        for m in used:
            nt = m.node_tree
            t = nt.nodes["bake_target"]
            t.image = img
            nt.nodes.active = t
            outn = nt.nodes["out"]
            src = nt.nodes[m["emit"]] if typ == "EMIT" else nt.nodes["bsdf"]
            nt.links.new(src.outputs[0], outn.inputs[0])
        sc.render.bake.margin = 6
        bpy.ops.object.bake(type=typ, normal_space="TANGENT", margin=6, use_clear=True)
        img.filepath_raw = os.path.join(out, img.name + ".png")
        img.file_format = "PNG"
        img.save()
    # итоговые материалы: корпус и стекло/фары (глянец)
    fin = {}
    for key, rough, metal in (("body", BODY_ROUGH, BODY_METAL), ("glass", GLASS_ROUGH, GLASS_METAL)):
        m = bpy.data.materials.new("%s_%s" % (name, key))
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = img_c
        nt.links.new(tc.outputs["Color"], b.inputs["Base Color"])
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img_n
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        fin[key] = m
    for o in joined:
        for s in o.material_slots:
            s.material = fin["glass"] if s.material and s.material.name in glass_kinds else fin["body"]
        # убрать повторы слотов
        _select([o])
        bpy.ops.object.material_slot_remove_unused()
    for gname in groups:
        if gname:
            o = bpy.data.objects[gname]
            mw = o.matrix_world.copy()
            o.parent = bpy.data.objects[PARENT[gname]] if gname in PARENT else root
            o.matrix_world = mw
    print("TRIS", tris)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format="GLB", use_selection=False,
                              export_image_format="AUTO")
    # оптимизация перед 3.5-s6: экспорт даёт примитив на каждый слот материала (23–36 на машину), а запечённых
    # материалов два — склеиваем примитивы одного материала, вызовов отрисовки в 4 раза меньше
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "glb_merge_prims", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "glb_merge_prims.py"))
    gm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gm)
    gm.merge(os.path.join(out, name + ".glb"))
    return root, tris


def preview(out, name, size=1.0):
    """Кадры: изометрия, сбоку, сверху и как в игре (наклон 28°); фон — песок"""
    if os.environ.get("NOPREVIEW"):   # кадры смотрим в игре (tools/model_lab/gallery) — без долгого рендера Cycles
        return []
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.82, 0.92, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    sc.world = w
    me = bpy.data.meshes.new("floor")
    me.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    fl = bpy.data.objects.new("floor", me)
    sc.collection.objects.link(fl)
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.58, 0.5, 0.39, 1)
    fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
    me.materials.append(fm)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(3)
    sun.rotation_euler = (math.radians(38), math.radians(12), math.radians(-35))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 64
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 960
    sc.render.resolution_y = 600
    sc.view_settings.view_transform = "AgX"
    k = size
    shots = [("iso", (1.05 * k, -1.2 * k, 0.75 * k), (0, 0, 0.12 * k), 50), ("iso_rear", (-1.1 * k, 1.1 * k, 0.8 * k), (0, 0, 0.12 * k), 50),
             ("side", (0, -2.6 * k, 0.2 * k), (0, 0, 0.17 * k), 50), ("top", (0, 0, 3.0 * k), None, 45),
             ("game28", (0, -3.0 * k * math.sin(math.radians(28)), 3.0 * k * math.cos(math.radians(28))), (0, 0, 0.1 * k), 45)]
    if os.environ.get("QUICK"):
        shots = [s for s in shots if s[0] in ("iso", "game28")]
    files = []
    for nm, pos, target, lens in shots:
        cam.data.lens = lens
        cam.location = pos
        if target is None:
            cam.rotation_mode = "XYZ"
            cam.rotation_euler = (0, 0, 0)
        else:
            cam.rotation_mode = "QUATERNION"
            cam.rotation_quaternion = (Vector(target) - Vector(pos)).to_track_quat("-Z", "Y")
        sc.render.filepath = os.path.join(out, "preview_%s_%s.png" % (name, nm))
        bpy.ops.render.render(write_still=True)
        files.append(sc.render.filepath)
    return files
