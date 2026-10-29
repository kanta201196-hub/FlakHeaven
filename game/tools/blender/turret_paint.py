"""Baked PBR paint for the player turrets (S12, Kanta 26.10: "let us make a quality texture and paint";
target look — weathered painted armour like catalog pick 113, colours from our planes' livery, no rust or flags).

turret_lib.build(..., paint=PALETTES[...]) calls bake() on each joined object (root, "guns", "pods") before the
GLB export. The geometry is untouched (same triangles); each object gets a fresh UV atlas and one material
"turret_paint[_<group>]" with three textures:
  albedo — blotch camouflage in the plane's livery colours on the armour, dark steel fittings, gunmetal
           barrels with soot towards the muzzle; chipped edges (primer, then bare steel), AO grime in crevices,
           dirt rising from the bottom, vertical rain streaks, sand dust on upward faces, all baked in
           (the battle renderer has no AO of its own);
  metallicRoughness (glTF: G roughness, B metal, R AO) — matte paint, metallic chips and barrels;
  normal (tangent space) — rounded plate edges, panel lines, weld beads and rivet rows.
How: Cycles bakes the surface data per texel (world position, face normal, bevelled normal, AO, part id) into
float images; numpy computes every layer from those, so features follow the 3D shape and never seam at UV
island borders; one more Cycles bake turns the object-space normals into the tangent-space map.
Glass faces keep their own untextured material. Colours are sRGB 0…1.

The material name has no "body", so WeaponModels._glb_mesh does not re-tint it (the paint is final).

Own-colour mode (pal["own"], Kanta 26.10 "no model ships with flat paint", first used on the «Крепость» domes):
the camouflage is skipped and every face keeps the colour its original material gives it — a flat Base Color or
the texture behind it, sampled through the object's old UVs (a dome that wears the hull's skin keeps that skin);
the same wear, grime, dust, soot and relief go on top, so a model is weathered without leaving its palette.
bake_set() packs several objects into one atlas (one material and one texture set for all of them), and
scale gives the size of "one turret length" in world units, so panels, rivets and chips keep their size on a
model of another scale. Faces of glass or glowing ("core") materials keep their own material."""
import atexit, math, os, shutil, tempfile
import numpy as np
import bpy
from PIL import Image

# tones — camouflage colours (sRGB): base, first and second blotch colour; share — area of the two blotch colours
# (a third red-brown, a fifth olive).
# Both planes fly the default livery "sand camo" (livery.gd SAND_CAMO, Kanta 18.10): sand base,
# red-brown and olive blotches; the base is a touch darker than the plane's, because the turret paint carries
# its own grime and AO. Each class keeps its own seed, so the two turrets do not share one pattern.
_SAND = [(0.80, 0.72, 0.53), (0.58, 0.37, 0.19), (0.25, 0.23, 0.14)]
PALETTES = {
    "kit": {"tones": _SAND, "share": (0.33, 0.2), "seed": 7},
    "grach": {"tones": _SAND, "share": (0.33, 0.2), "seed": 11},
}
# Kanta 27.10 (build s13, item 4) took two more liveries, «Степь» and «Скальный осколок» (livery.gd STEPPE, ROCK);
# the turrets follow them the way they follow the sand camo: the plane's colours a touch darker, the plane's pattern
# kind. pattern — "blotch" (default, soft fields), "bands" (wavy disruptive bands; freq — bands per turret length),
# "splinter" (angular patches cut by random planes; cuts — how many planes). Files: <turret>_<livery>.glb.
_STEPPE = [(0.49, 0.48, 0.33), (0.47, 0.37, 0.24), (0.25, 0.23, 0.17)]
_ROCK = [(0.51, 0.49, 0.45), (0.43, 0.35, 0.28), (0.29, 0.28, 0.27)]
for _k, _seed in (("kit", 7), ("grach", 11)):
    PALETTES[_k + "_steppe"] = {"tones": _STEPPE, "share": (0.36, 0.22), "seed": _seed, "pattern": "bands", "freq": 1.3}
    PALETTES[_k + "_rock"] = {"tones": _ROCK, "share": (0.33, 0.33), "seed": _seed, "pattern": "splinter", "cuts": 7}
# Kanta 27.10 took all ten round-2 liveries (livery.gd FOREST … CHEQUER); the turrets follow them the same way:
# [base, colour 2, colour 3] the plane's colours about 0.93 darker, and the plane's pattern kind. More kinds:
# "mottle" — soft clouds of colour 2 and a fine speckle of colour 3; "streaks" — long streaks along the barrels (the
# flow); "dazzle" — angular pieces (random planes) each striped its own way, half colour 2, half colour 3 (freq —
# stripes per turret length); "pixel" — the blotch fields sampled on a cube grid (cell — pixel size); "tiger" —
# tapering stripes across the barrels (width — stripe width, 0…0.5); "rust" — bare steel (metal / rough of the base)
# with rust (colour 2, more on the lower faces) and whole panels in primer (colour 3); "chequer" — a chequer of
# colour 2 over the front of the turret (cell — square size, front — x where it starts). A share of 0 drops a colour.
# All of them get the same wear, grime, streaks, dust, soot and relief as every turret (_layers): matte, never flat.
_ROUND2 = {
    "forest": {"tones": [(0.31, 0.34, 0.22), (0.34, 0.27, 0.19), (0.16, 0.18, 0.13)], "share": (0.3, 0.22)},
    "sea_fog": {"tones": [(0.43, 0.46, 0.47), (0.31, 0.33, 0.36), (0.37, 0.40, 0.43)], "share": (0.36, 0.14)},
    "ash": {"tones": [(0.22, 0.22, 0.21), (0.31, 0.30, 0.28), (0.48, 0.47, 0.44)], "share": (0.32, 0.1),
            "pattern": "mottle"},
    "reed": {"tones": [(0.65, 0.57, 0.39), (0.39, 0.39, 0.25), (0.37, 0.28, 0.19)], "share": (0.3, 0.2),
             "pattern": "streaks"},
    "dazzle": {"tones": [(0.72, 0.72, 0.69), (0.08, 0.08, 0.09), (0.32, 0.37, 0.44)], "share": (0.5, 0.5),
               "pattern": "dazzle", "freq": 5.0, "cuts": 5},
    "pixel": {"tones": [(0.57, 0.54, 0.59), (0.65, 0.17, 0.44), (0.23, 0.12, 0.28)], "share": (0.33, 0.2),
              "pattern": "pixel", "cell": 0.07},
    "shark": {"tones": [(0.44, 0.46, 0.46), (0.25, 0.26, 0.26), (0.25, 0.26, 0.26)], "share": (0.25, 0.0)},
    "arctic_tiger": {"tones": [(0.68, 0.69, 0.69), (0.15, 0.16, 0.18), (0.15, 0.16, 0.18)], "share": (0.0, 0.0),
                     "pattern": "tiger", "width": 0.3},
    "rust": {"tones": [(0.51, 0.51, 0.49), (0.42, 0.22, 0.11), (0.51, 0.54, 0.28)], "share": (0.34, 0.18),
             "pattern": "rust", "metal": 0.55, "rough": 0.6},
    "chequer": {"tones": [(0.74, 0.57, 0.11), (0.06, 0.06, 0.06), (0.06, 0.06, 0.06)], "share": (0.0, 0.0),
                "pattern": "chequer", "cell": 0.09, "front": 0.18},
}
for _k, _seed in (("kit", 7), ("grach", 11)):
    for _liv, _pal in _ROUND2.items():
        PALETTES[_k + "_" + _liv] = dict(_pal, seed=_seed)


def pick(cls_key, argv):
    """Palette of a turret script: PALETTES[cls_key], or PALETTES[cls_key + "_" + x] for a "livery=x" argument;
    "livery=x,y,…" gives a list of (suffix, palette), which turret_lib.build bakes in one run (the paint-independent
    bakes are made once, see _DATA) and exports as <name>_<suffix>.glb each"""
    for a in argv:
        if a.startswith("livery="):
            ids = a.split("=", 1)[1].split(",")
            if len(ids) > 1:
                return [(i, PALETTES[cls_key + "_" + i]) for i in ids]
            return PALETTES[cls_key + "_" + ids[0]]
    return PALETTES[cls_key]

PRIMER = np.array([0.27, 0.26, 0.23], np.float32)     # under the paint where it is chipped
STEEL = np.array([0.56, 0.56, 0.54], np.float32)      # bare metal at the worn edges
DIRT = np.array([0.21, 0.18, 0.13], np.float32)
DUST = np.array([0.64, 0.57, 0.44], np.float32)       # Highland sand settled on upward faces
SOOT = np.array([0.035, 0.032, 0.03], np.float32)
FITTING = np.array([0.11, 0.11, 0.105], np.float32)   # turret_dark parts
GUNMETAL = np.array([0.16, 0.16, 0.17], np.float32)   # turret_barrel parts
GLASS = np.array([0.12, 0.2, 0.24], np.float32)

TMP = tempfile.mkdtemp(prefix="fh_tpaint_")
atexit.register(shutil.rmtree, TMP, True)   # the PNGs only live until the GLB export embeds them


# ---------------- noise in 3D (world units, turret length 1) ----------------
def _hash(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float32) / 65535.0


def vnoise(p, f, seed):
    """Value noise 0…1 at points p (n, 3) with lattice step 1/f"""
    q = p * f
    i = np.floor(q).astype(np.int64)
    t = q - i
    u = t * t * (3 - 2 * t)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p, f, seed, octaves=4):
    a, s, n = 1.0, 0.0, 0.0
    for o in range(octaves):
        s = s + a * vnoise(p, f * 2 ** o, seed + o * 17)
        n += a
        a *= 0.5
    return s / n


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------- Cycles data bakes ----------------
def _img(name, size, data=True):
    im = bpy.data.images.new(name, size, size, alpha=True, float_buffer=data)
    im.colorspace_settings.name = "Non-Color"
    return im


def _pixels(im):
    a = np.empty(im.size[0] * im.size[1] * 4, np.float32)
    im.pixels.foreach_get(a)
    return a.reshape(im.size[1], im.size[0], 4)


def _part(m):
    """Surface kind of a material by its name: 0 painted body, 1 dark fitting (or steel), 2 gun barrel,
    3 kept as it is (glass, the glowing core)"""
    n = m.name if m else ""
    return 3 if ("glass" in n or "core" in n) else 2 if "barrel" in n else 1 if ("dark" in n or "steel" in n) else 0


_SCALE = 1.0   # world units per turret length for the current bake (bake_set sets it)
_PART_FN = [None]   # bake_set: pal["part"] (material -> surface id) replaces _part for the current bake


def _bake_emit(obs, img, build):
    """Bake an emission shader built by build(nodes, links, part_id, material) -> socket into img, for every
    slot of every object in obs (they share the atlas)"""
    saved = []
    for ob in obs:
        orig = list(ob.data.materials)
        tmp = []
        for m in orig:
            t = bpy.data.materials.new("bake_tmp")
            t.use_nodes = True
            N, Lk = t.node_tree.nodes, t.node_tree.links
            N.clear()
            out = N.new("ShaderNodeOutputMaterial")
            em = N.new("ShaderNodeEmission")
            Lk.new(build(N, Lk, (_PART_FN[0] or _part)(m), m), em.inputs["Color"])
            Lk.new(em.outputs[0], out.inputs[0])
            tx = N.new("ShaderNodeTexImage")
            tx.image = img
            N.active = tx
            tmp.append(t)
        for i, t in enumerate(tmp):
            ob.data.materials[i] = t
        saved.append((ob, orig, tmp))
    bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True)
    for ob, orig, tmp in saved:
        for i, m in enumerate(orig):
            ob.data.materials[i] = m
        for t in tmp:
            bpy.data.materials.remove(t)
    return _pixels(img)


def _enc(N, Lk, sock):
    """vector * 0.5 + 0.5, so negative components survive the emission bake"""
    v = N.new("ShaderNodeVectorMath")
    v.operation = "MULTIPLY_ADD"
    Lk.new(sock, v.inputs[0])
    v.inputs[1].default_value = (0.5, 0.5, 0.5)
    v.inputs[2].default_value = (0.5, 0.5, 0.5)
    return v.outputs[0]


def _b_pos(N, Lk, pid, m=None):
    g = N.new("ShaderNodeNewGeometry")
    v = N.new("ShaderNodeVectorMath")
    v.operation = "MULTIPLY_ADD"
    Lk.new(g.outputs["Position"], v.inputs[0])
    v.inputs[1].default_value = (0.2, 0.2, 0.2)
    v.inputs[2].default_value = (0.5, 0.5, 0.5)
    return v.outputs[0]


def _b_nrm(N, Lk, pid, m=None):
    return _enc(N, Lk, N.new("ShaderNodeNewGeometry").outputs["True Normal"])


def _b_bev(N, Lk, pid, m=None):
    b = N.new("ShaderNodeBevel")
    b.samples = 8
    b.inputs["Radius"].default_value = 0.006 * _SCALE
    return _enc(N, Lk, b.outputs[0])


def _b_ao(N, Lk, pid, m=None):
    a = N.new("ShaderNodeAmbientOcclusion")
    a.samples = 16
    a.inputs["Distance"].default_value = 0.14 * _SCALE
    c = N.new("ShaderNodeCombineColor")
    Lk.new(a.outputs["AO"], c.inputs[0])
    c.inputs[1].default_value = (pid + 1) / 8.0   # G: part id (+1, so 0 is "no surface")
    return c.outputs[0]


def _b_src(N, Lk, pid, m=None):
    """The material's own base colour (linear): its Base Color texture sampled through the old UVs ("src"),
    or the flat colour; a vertex-colour multiply in front of it (fortress.py grime) is skipped, the bake has
    its own grime"""
    rgb = N.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (0.5, 0.5, 0.5, 1.0)
    b = m.node_tree.nodes.get("Principled BSDF") if m is not None and m.node_tree else None
    if b is None:
        return rgb.outputs[0]
    inp = b.inputs["Base Color"]
    rgb.outputs[0].default_value = inp.default_value[:]
    if inp.is_linked:
        src = inp.links[0].from_node
        if src.type == "TEX_IMAGE" and src.image is not None:
            tx = N.new("ShaderNodeTexImage")
            tx.image = src.image
            uv = N.new("ShaderNodeUVMap")
            uv.uv_map = "src"
            Lk.new(uv.outputs[0], tx.inputs["Vector"])
            return tx.outputs["Color"]
        if src.type == "MIX" and "A" in src.inputs:
            rgb.outputs[0].default_value = src.inputs["A"].default_value[:]
    return rgb.outputs[0]


def _to_srgb(c):
    """Linear 0…1 → sRGB 0…1 (the albedo PNG is written in sRGB)"""
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055).astype(np.float32)


# ---------------- layers ----------------
def _frame(n):
    """Tangent frame (t, b) on the surface: t horizontal on walls, along +X on roofs and floors"""
    up = np.abs(n[:, 2]) > 0.85
    t = np.cross(np.array([0.0, 0.0, 1.0], np.float32), n)
    tx = np.array([1.0, 0.0, 0.0], np.float32) - n * n[:, :1]
    t[up] = tx[up]
    t /= np.linalg.norm(t, axis=1, keepdims=True) + 1e-8
    return t, np.cross(n, t)


SU, SV, LW = 0.3, 0.21, 0.0035   # panel grid along t / b and half width of a panel line


def _height(p, t, b, armour, seed):
    """Surface relief in world units: panel grooves, weld beads, rivet rows, cast texture"""
    u = np.einsum("ij,ij->i", p, t)
    v = np.einsum("ij,ij->i", p, b)
    h = 0.00012 * fbm(p, 70.0, seed + 5, 2)
    for coord, along, sp, off in ((u, v, SU, 0.11), (v, u, SV, 0.07)):
        k = np.round((coord - off) / sp)
        d = coord - off - k * sp
        ad = np.abs(d)
        weld = _hash(k.astype(np.int64), np.zeros_like(k, np.int64), np.full(k.shape, 7, np.int64), seed) < 0.35
        groove = 1.0 - sstep(LW * 0.5, LW, ad)
        bead = (1.0 - sstep(LW * 0.3, LW * 0.9, ad)) * (0.75 + 0.25 * np.sin(along * 900.0))
        ar = along - np.round(along / 0.045) * 0.045
        rr = np.sqrt((ad - 0.014) ** 2 + ar ** 2)
        rivet = np.sqrt(np.clip(1.0 - (rr / 0.0055) ** 2, 0.0, 1.0))
        h = h + armour * np.where(weld, 0.0011 * bead, -0.0011 * groove + 0.0016 * rivet)
    return h


_CUTS = {}


def _cuts(seed, share):
    """Noise levels that give the blotch colours their share of the turret volume (value noise is not centred
    the same for every seed); measured once on a fixed point cloud, so every object of a turret agrees"""
    if seed not in _CUTS:
        q = np.random.default_rng(0).uniform((-0.6, -0.5, 0.0), (2.1, 0.5, 0.8), (120000, 3)).astype(np.float32)
        n1 = fbm(q, 2.4, seed + 20, 3)
        n2 = fbm(q, 2.8, seed + 21, 3)
        c1 = float(np.quantile(n1, 1.0 - share[0]))
        c2 = float(np.quantile(n2[n1 <= c1], 1.0 - share[1] / (1.0 - share[0])))
        _CUTS[seed] = (c1, c2)
    return _CUTS[seed]


_QCUT = {}


def _qcut(tag, fn, share):
    """Level of the field fn (points -> values) above which a share of the turret volume lies; measured once on the
    fixed point cloud of _cuts, so every object of a turret agrees"""
    if tag not in _QCUT:
        q = np.random.default_rng(0).uniform((-0.6, -0.5, 0.0), (2.1, 0.5, 0.8), (120000, 3)).astype(np.float32)
        _QCUT[tag] = float(np.quantile(fn(q), 1.0 - share)) if share > 0 else np.inf
    return _QCUT[tag]


def _cells(P, pal, n_cuts, wobble=0.04):
    """Id 0…1 of the angular piece each point falls in: the volume cut by n_cuts random planes (straight masked
    edges with a little hand wobble)"""
    seed = pal["seed"]
    rng = np.random.default_rng(seed)
    wob = np.stack([fbm(P, 3.0, seed + 40 + i, 2) for i in range(3)], 1) - 0.5
    pw = P + wob * wobble
    code = np.zeros(len(P), np.int64)
    for _ in range(n_cuts):
        n = rng.normal(size=3).astype(np.float32)
        n /= np.linalg.norm(n)
        o = rng.uniform((-0.4, -0.4, 0.0), (1.6, 0.4, 0.6)).astype(np.float32)
        code = code * 2 + ((pw - o) @ n > 0).astype(np.int64)
    return _hash(code, np.full_like(code, 3), np.full_like(code, 5), seed)


def _camo(P, pal, N=None):
    """Camouflage colours (sRGB) at points P by pal["pattern"] (see PALETTES) and the colour index k (0 base, 1 colour 2,
    2 colour 3); the colours tones[1] and tones[2] take about the shares pal["share"] of the surface"""
    seed = pal["seed"]
    tones = [np.array(t, np.float32) for t in pal["tones"]]
    k = np.zeros(len(P), np.int64)
    pat = pal.get("pattern", "blotch")
    s2, s3 = pal["share"]
    if pat == "bands":
        warp = (fbm(P, 1.6, seed + 30, 3) - 0.5) * 2.2
        d = (P @ np.array([0.75, 0.62, 0.3], np.float32)) * pal.get("freq", 1.3) + warp
        f = d - np.floor(d)
        k[f < s2] = 1
        k[(f >= s2) & (f < s2 + s3)] = 2
    elif pat == "splinter":
        h = _cells(P, pal, pal.get("cuts", 7))
        k[h < s2] = 1
        k[(h >= s2) & (h < s2 + s3)] = 2
    elif pat == "mottle":
        f1 = lambda q: fbm(q, 2.4, seed + 20, 3)
        f2 = lambda q: fbm(q, 11.0, seed + 23, 2)
        k[f1(P) > _qcut("m1", f1, s2)] = 1
        k[f2(P) > _qcut("m2", f2, s3)] = 2   # the speckle lies over the clouds too
    elif pat == "streaks":
        st = np.array([0.22, 2.6, 2.6], np.float32)   # long along the barrels (x), the flow over the turret
        f1 = lambda q: fbm(q * st, 1.6, seed + 24, 3)
        f2 = lambda q: fbm(q * st * 1.3, 1.6, seed + 25, 3)
        k[f2(P) > _qcut("s2", f2, s3)] = 2
        k[f1(P) > _qcut("s1", f1, s2)] = 1
    elif pat == "dazzle":
        cid = _cells(P, pal, pal.get("cuts", 5), 0.0)
        a = cid * 6.2832
        dirs = np.stack([np.cos(a), 0.5 * np.sin(a * 3.0), np.sin(a)], 1).astype(np.float32)
        dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
        d = np.einsum("ij,ij->i", P, dirs) * pal.get("freq", 5.0)
        stripe = np.abs(d - np.floor(d) - 0.5) > 0.25
        k[stripe & (cid < s2)] = 1
        k[stripe & (cid >= s2)] = 2
    elif pat == "pixel":
        c = pal.get("cell", 0.07)
        g1 = (np.floor(P / c) + 0.5) * c
        g2 = (np.floor(P / (c * 0.5)) + 0.5) * c * 0.5
        f1 = lambda q: fbm(q, 2.6, seed + 20, 3)
        f2 = lambda q: fbm(q, 3.4, seed + 21, 3)
        k[f2(g2) > _qcut("p2", f2, s3)] = 2
        k[f1(g1) > _qcut("p1", f1, s2)] = 1
    elif pat == "tiger":
        warp = fbm(P, 2.2, seed + 31, 3) * 1.1 + fbm(P, 6.0, seed + 32, 2) * 0.3
        s = P[:, 0] * 4.2 + np.abs(P[:, 1]) * 1.4 + P[:, 2] * 0.8 + warp
        tri = np.abs(s - np.floor(s) - 0.5)
        along = vnoise(np.stack([np.floor(s) * 5.1, np.abs(P[:, 1]) * 4.0 + P[:, 2] * 3.0, P[:, 0] * 2.0], 1), 1.0, seed + 33)
        width = pal.get("width", 0.3) * sstep(0.2, 0.7, along) + 0.03 * fbm(P, 30.0, seed + 34, 2)
        k[tri < width] = 1
    elif pat == "rust":
        f1 = lambda q: fbm(q, 2.6, seed + 20, 3)
        low = 0.0 if N is None else 0.12 * np.clip(-N[:, 2], 0.0, 1.0)   # runs gather on the lower faces
        k[_cells(P, pal, 6, 0.0) < s3] = 2   # whole repaired panels in primer
        k[f1(P) + low > _qcut("r1", f1, s2)] = 1
    elif pat == "chequer":
        c = pal.get("cell", 0.09)
        q = np.floor(P / c).astype(np.int64)
        par = (q[:, 0] + q[:, 1] + q[:, 2]) % 2 == 1
        k[par & (P[:, 0] > pal.get("front", 0.18))] = 1
    else:
        c1, cc2 = _cuts(seed, pal["share"])
        n1 = fbm(P, 2.4, seed + 20, 3)
        n2 = fbm(P, 2.8, seed + 21, 3)
        k[(n2 > cc2) & (n1 <= c1)] = 2
        k[n1 > c1] = 1
    col = np.stack(tones)[k]
    return col, k


def _layers(P, N, B, AO, part, x_tip, pal, guns, src=None, want_nrm=True):
    """Albedo (sRGB), roughness, metal, height-perturbed normal for the covered texels; src — the faces' own
    colours (sRGB) in own-colour mode, None for the camouflage"""
    seed = pal["seed"]
    n_pts = len(P)
    body, dark, barrel, glass = part == 0, part == 1, part == 2, part == 3
    if src is not None:
        return _layers_own(P, N, B, AO, part, x_tip, pal, src)   # (always with its normal)
    # --- base colour: the livery's soft-edged blotches (two noise fields over the sand base, like the plane's
    # SAND_CAMO pattern): red-brown where the first field is high, olive where the second one is
    col, ck = _camo(P, pal, N)
    col = np.where(dark[:, None], FITTING, col)
    col = np.where(barrel[:, None], GUNMETAL, col)
    col = np.where(glass[:, None], GLASS, col)
    paint = body | dark
    mott = fbm(P, 5.0, seed + 1, 4)
    col = col * (1.0 + 0.16 * (mott - 0.5))[:, None]
    col = col * (1.0 + 0.05 * (fbm(P, 22.0, seed + 2, 3) - 0.5))[:, None]
    col = np.where((paint & (N[:, 2] > 0.5))[:, None], col * 1.05 + 0.01, col)   # sun-faded roofs
    rough = np.where(body, 0.84, np.where(dark, 0.72, np.where(barrel, 0.42, 0.08))).astype(np.float32)
    rough = rough + 0.06 * (fbm(P, 30.0, seed + 3, 3) - 0.5)
    metal = np.where(barrel, 0.75, np.where(dark, 0.3, np.where(glass, 0.6, 0.0))).astype(np.float32)
    if "metal" in pal:   # "rust": the base is bare steel (matte, never polished); rust and primer are not metallic
        steel = body & (ck == 0)
        metal = np.where(steel, pal["metal"], metal).astype(np.float32)
        rough = np.where(steel, pal.get("rough", 0.6) + 0.08 * (fbm(P, 9.0, seed + 11, 3) - 0.5), rough)
        rough = np.where(body & (ck == 1), 0.93, rough).astype(np.float32)
    # --- wear: chipped convex edges (primer, then bare steel) and a few scattered chips on the faces
    edge = np.clip((1.0 - np.einsum("ij,ij->i", B, N)) * 9.0, 0.0, 1.0) * sstep(0.55, 0.85, AO)
    chipn = fbm(P, 38.0, seed + 4, 3)
    w = edge * 1.0 + (chipn - 0.5) * 1.3 - 0.52
    w = np.maximum(w, (fbm(P, 16.0, seed + 6, 3) - 0.76) * 2.5 * (chipn > 0.55))
    primer = sstep(0.0, 0.06, w) * paint
    bare = sstep(0.22, 0.34, w) * paint
    bare_b = sstep(0.1, 0.25, edge * 1.2 + (chipn - 0.5) - 0.2) * barrel   # polished barrel edges
    col = col * (1 - primer[:, None]) + PRIMER * primer[:, None]
    col = col * (1 - bare[:, None]) + STEEL * bare[:, None]
    col = col * (1 - 0.5 * bare_b[:, None]) + STEEL * 0.5 * bare_b[:, None]
    rough = rough * (1 - bare) + 0.38 * bare
    metal = metal * (1 - bare) + 0.8 * bare
    # --- grime: crevice dirt, dirt rising from below, vertical streaks on walls, dust on roofs
    cav = 1.0 - AO
    col = col * (1 - 0.55 * cav[:, None]) + DIRT * (0.55 * cav)[:, None]
    low = (1.0 - sstep(0.08, 0.45, P[:, 2])) * 0.35 * (0.6 + 0.8 * (mott - 0.5))
    col = col * (1 - low[:, None]) + DIRT * low[:, None]
    wall = 1.0 - np.abs(N[:, 2])
    st = fbm(P * np.array([1.0, 1.0, 0.07], np.float32), 34.0, seed + 8, 3)
    streak = sstep(0.55, 0.78, st) * wall * 0.32 * (glass == 0)
    col = col * (1 - streak[:, None]) + DIRT * 0.6 * streak[:, None]
    dust = np.clip(N[:, 2], 0, 1) * np.clip(cav * 1.8 + (fbm(P, 9.0, seed + 9, 3) - 0.45) * 0.9, 0, 0.75) * (glass == 0)
    col = col * (1 - dust[:, None]) + DUST * dust[:, None]
    rough = np.clip(rough + 0.1 * dust + 0.06 * cav, 0.05, 1.0)
    metal = metal * (1 - dust)
    # --- soot towards the muzzle: barrels and their fittings on the gun node
    if x_tip is not None:
        s = sstep(x_tip - 0.32, x_tip - 0.02, P[:, 0]) * (0.55 + 0.6 * (fbm(P, 14.0, seed + 10, 3) - 0.3))
        s = np.clip(s, 0, 1) * (barrel | dark)
        col = col * (1 - s[:, None]) + SOOT * s[:, None]
        rough = rough * (1 - s) + 0.9 * s
        metal = metal * (1 - s) + 0.1 * s
    # AO into the albedo (the game's renderer does not shade crevices by itself)
    col = col * (0.5 + 0.5 * AO ** 0.8)[:, None]
    nn = _relief(P, N, B, body, seed) if want_nrm else None
    return np.clip(col, 0, 1), np.clip(rough, 0, 1), np.clip(metal, 0, 1), nn


def _relief(P, N, B, body, seed):
    """Bevelled base normal tilted by the relief gradient (panel lines, welds, rivets on the painted armour; finite
    differences along the surface frame); it depends on the shape and the seed only, not on the paint colours"""
    t, b = _frame(N)
    armour = body.astype(np.float32)
    e = 0.0007
    hu = (_height(P + t * e, t, b, armour, seed) - _height(P - t * e, t, b, armour, seed)) / (2 * e)
    hv = (_height(P + b * e, t, b, armour, seed) - _height(P - b * e, t, b, armour, seed)) / (2 * e)
    nn = B - (hu[:, None] * t + hv[:, None] * b)
    nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
    return nn


def _height_box(p, ax, armour, seed):
    """_height with the panel grid laid on the two world axes across each texel's dominant normal axis ax"""
    i0 = np.where(ax == 0, 1, 0)
    i1 = np.where(ax == 2, 1, 2)
    r = np.arange(len(p))
    e0 = np.zeros_like(p)
    e1 = np.zeros_like(p)
    e0[r, i0] = 1.0
    e1[r, i1] = 1.0
    return _height(p, e0, e1, armour, seed)


def _layers_own(P, N, B, AO, part, x_tip, pal, src):
    """Own-colour weathering: the same chips, grime, streaks, dust, soot and relief as the camouflage paint,
    over each face's own colour; matte throughout (Kanta: no gloss), only bare-steel chips are metallic.
    pal: seed, and optional wear (chip amount, 1 = the turrets'), dust (1 = the turrets')"""
    seed = pal["seed"]
    wear = pal.get("wear", 1.0)
    body, dark, barrel, glass = part == 0, part == 1, part == 2, part == 3
    paint = body | dark
    col = src.copy()
    mott = fbm(P, 5.0, seed + 1, 4)
    col = col * (1.0 + 0.2 * (mott - 0.5))[:, None]
    col = col * (1.0 + 0.08 * (fbm(P, 22.0, seed + 2, 3) - 0.5))[:, None]
    col = np.where((paint & (N[:, 2] > 0.5))[:, None], col * 1.06 + 0.012, col)   # sun-faded upper faces
    rough = np.where(body, 0.86, np.where(dark, 0.8, np.where(barrel, 0.62, 0.1))).astype(np.float32)
    rough = rough + 0.1 * (fbm(P, 30.0, seed + 3, 3) - 0.5) + 0.06 * (mott - 0.5)
    metal = np.where(barrel, 0.45, np.where(dark, 0.15, 0.0)).astype(np.float32)
    # chipped convex edges: a dark primer first, bare steel only where the chip is deep
    edge = np.clip((1.0 - np.einsum("ij,ij->i", B, N)) * 9.0, 0.0, 1.0) * sstep(0.55, 0.85, AO)
    chipn = fbm(P, 38.0, seed + 4, 3)
    w = edge * wear + (chipn - 0.5) * 1.3 - 0.52
    w = np.maximum(w, (fbm(P, 16.0, seed + 6, 3) - 0.78) * 2.5 * wear * (chipn > 0.55))
    primer = sstep(0.0, 0.06, w) * paint
    bare = sstep(0.24, 0.36, w) * paint
    bare_b = sstep(0.1, 0.25, edge * 1.2 + (chipn - 0.5) - 0.2) * barrel
    col = col * (1 - 0.8 * primer[:, None]) + PRIMER * (0.8 * primer)[:, None]
    col = col * (1 - 0.8 * bare[:, None]) + STEEL * (0.8 * bare)[:, None]
    col = col * (1 - 0.4 * bare_b[:, None]) + STEEL * (0.4 * bare_b)[:, None]
    rough = rough * (1 - bare) + 0.45 * bare
    metal = metal * (1 - bare) + 0.7 * bare
    # grime in crevices, darker lower faces, rain/oil streaks down the walls, dust settled on upper faces
    cav = 1.0 - AO
    col = col * (1 - 0.5 * cav[:, None]) + DIRT * (0.5 * cav)[:, None]
    under = np.clip(-N[:, 2], 0, 1) * 0.25 * (0.6 + 0.8 * (mott - 0.5))
    col = col * (1 - under[:, None]) + DIRT * 0.6 * under[:, None]
    wall = 1.0 - np.abs(N[:, 2])
    st = fbm(P * np.array([1.0, 1.0, 0.07], np.float32), 34.0, seed + 8, 3)
    streak = sstep(0.55, 0.78, st) * wall * 0.3 * (glass == 0)
    col = col * (1 - streak[:, None]) + DIRT * 0.6 * streak[:, None]
    dust = np.clip(N[:, 2], 0, 1) * np.clip(cav * 1.6 + (fbm(P, 9.0, seed + 9, 3) - 0.5) * 0.7, 0, 0.45)
    dust = dust * pal.get("dust", 1.0) * (glass == 0)
    col = col * (1 - dust[:, None]) + DUST * dust[:, None]
    rough = np.clip(rough + 0.08 * dust + 0.06 * cav, 0.05, 1.0)
    metal = metal * (1 - dust)
    if x_tip is not None:   # powder soot towards the muzzles
        s = sstep(x_tip - 0.32, x_tip - 0.02, P[:, 0]) * (0.55 + 0.6 * (fbm(P, 14.0, seed + 10, 3) - 0.3))
        s = np.clip(s, 0, 1) * (barrel | dark)
        col = col * (1 - s[:, None]) + SOOT * s[:, None]
        rough = rough * (1 - s) + 0.92 * s
        metal = metal * (1 - s)
    col = col * (0.5 + 0.5 * AO ** 0.8)[:, None]
    # relief on a box projection (straight seams on domes and drums; the turret frame curls them into a
    # radial checker on a round surface), half the turrets' depth
    t, b = _frame(N)
    ax = np.argmax(np.abs(N), axis=1)
    armour = body.astype(np.float32) * 0.5
    e = 0.0007
    hu = (_height_box(P + t * e, ax, armour, seed) - _height_box(P - t * e, ax, armour, seed)) / (2 * e)
    hv = (_height_box(P + b * e, ax, armour, seed) - _height_box(P - b * e, ax, armour, seed)) / (2 * e)
    nn = B - (hu[:, None] * t + hv[:, None] * b)
    nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
    return np.clip(col, 0, 1), np.clip(rough, 0, 1), np.clip(metal, 0, 1), nn


def _dilate(img, mask, it=24):
    """Grow the covered texels outwards (texture filtering and mips must not pull in the background)"""
    img = img.copy()
    m = mask.copy()
    for _ in range(it):
        acc = np.zeros_like(img)
        cnt = np.zeros(m.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            mm = np.roll(m, (dy, dx), (0, 1))
            acc += np.roll(img, (dy, dx), (0, 1)) * mm[..., None]
            cnt += mm
        grow = (~m) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        m = m | grow
    return img


def _save_png(name, arr, sub=""):
    """arr (h, w, c) 0…1 with Blender's bottom-up rows → PNG on disk (in TMP/sub: the glTF export names a texture
    by its file, so each paint of a multi-paint run keeps the plain names in its own folder)"""
    os.makedirs(os.path.join(TMP, sub), exist_ok=True)
    p = os.path.join(TMP, sub, name + ".png")
    Image.fromarray((np.clip(arr[::-1], 0, 1) * 255 + 0.5).astype(np.uint8)).save(p)
    return p


def bake(ob, pal, size, mat_name, scale=1.0):
    """Unwrap ob, bake the paint layers and replace its materials with mat_name (glass faces keep theirs)"""
    bake_set([ob], pal, size, mat_name, scale)


def bake_set(obs, pal, size, mat_name, scale=1.0):
    """Unwrap the objects obs into one size x size atlas, bake the paint layers and give all of them the one
    material mat_name; faces of kept materials (glass, core) keep theirs. scale — world units per turret
    length (the noise, panel and chip sizes are tuned for a turret of length 1). pal["own"] — each face keeps
    its material's own colour (texture or flat) instead of the camouflage; the old UV layer is read for it.
    pal["part"] (material -> int) and pal["layers"] ((P, N, B, AO, part, own colours) -> albedo, roughness, metal,
    relief normal) let another kind of surface reuse the bakes with its own surface ids and layers. pal["uv_scale"]
    (material -> float, optional) gives some surfaces more texels than their area would (cloth over its poles)."""
    global _SCALE
    _SCALE = scale
    _PART_FN[0] = pal.get("part")
    own = bool(pal.get("own"))
    key = (tuple(ob.name for ob in obs), mat_name, size, scale, pal["seed"])
    hit = _DATA.get(key) if not own else None
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 0
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for ob in obs:
        ob.select_set(True)
    if hit is None:
        _unwrap(obs, own, pal.get("uv_scale"))
        data = _bake_data(obs, own, size, scale)
    else:
        data = hit   # a later paint of the same run: the same unwrap, surface data and relief normal map
    mask, sel, P, N, B, AO, part, S, x_tip = data[:9]

    H, W = mask.shape
    alb = np.zeros((H, W, 3), np.float32)
    orm = np.zeros((H, W, 3), np.float32)
    onm = np.zeros((H, W, 3), np.float32)
    CH = 400000
    for s0 in range(0, len(P), CH):
        sl = slice(s0, s0 + CH)
        if pal.get("layers") is not None:   # a caller's own layers (village_adobe.py: adobe walls, not paint)
            col, rough, metal, nn = pal["layers"](P[sl], N[sl], B[sl], AO[sl], part[sl], S[sl] if own else None)
        else:
            col, rough, metal, nn = _layers(P[sl], N[sl], B[sl], AO[sl], part[sl], x_tip, pal, obs[0].name,
                                            S[sl] if own else None, hit is None)
        ys, xs = sel[0][sl], sel[1][sl]
        alb[ys, xs] = col
        orm[ys, xs] = np.stack([AO[sl], rough, metal], 1)
        if nn is not None:
            onm[ys, xs] = nn * 0.5 + 0.5
    alb = _dilate(alb, mask)
    orm = _dilate(orm, mask)
    tag = mat_name
    sub = pal.get("suffix", "")
    i_alb = bpy.data.images.load(_save_png(tag + "_albedo", alb, sub))
    i_orm = bpy.data.images.load(_save_png(tag + "_orm", orm, sub))
    i_orm.colorspace_settings.name = "Non-Color"
    if hit is None:
        i_nrm = _bake_normal(obs, _dilate(onm, mask), size, tag)
        if not own:
            _DATA[key] = data + (i_nrm,)
    else:
        i_nrm = hit[9]
    _finish(obs, mat_name, i_alb, i_orm, i_nrm)
    print("PAINT %s: %d px, %d texels covered, %d objects%s" % (mat_name, size, int(mask.sum()), len(obs),
                                                             " (reused data)" if hit is not None else ""))


_DATA = {}   # bake_set: per objects / material / size / scale / seed, the paint-independent part of a bake


def _unwrap(obs, own, uv_scale=None):
    """Fresh UV atlas over the selected objects obs (own-colour mode keeps the old UVs as "src"). uv_scale
    (material -> float) scales the islands of some materials before a repack, so they get that many times the
    texel density of the rest; None keeps the area-proportional atlas."""
    for ob in obs:
        me = ob.data
        if own:
            # the detail boxes and cylinders come smooth-shaded without a bevel; their averaged normals would
            # read as worn edges over whole faces (and look blobby in the game): sharp edges above 40°
            me.set_sharp_from_angle(angle=math.radians(40))
        if own and me.uv_layers:
            keep = me.uv_layers.active or me.uv_layers[0]
            for l in list(me.uv_layers):
                if l != keep:
                    me.uv_layers.remove(l)
            me.uv_layers[0].name = "src"
        else:
            while me.uv_layers:
                me.uv_layers.remove(me.uv_layers[0])
        uv = me.uv_layers.new(name="UVMap")
        me.uv_layers.active = uv
        uv.active_render = True
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    if uv_scale is None:
        return
    for ob in obs:
        me = ob.data
        uvl = me.uv_layers["UVMap"].data
        for p in me.polygons:
            k = uv_scale(me.materials[p.material_index] if me.materials else None)
            if k != 1.0:
                for li in p.loop_indices:
                    uvl[li].uv = uvl[li].uv * k
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")


def _bake_data(obs, own, size, scale):
    """Cycles surface data of the atlas: (mask, texel indices, position, normal, bevelled normal, AO, part id,
    own colours or None, muzzle x or None) — everything the paint layers need that does not depend on the paint"""
    sc = bpy.context.scene
    im = _img("tp_data", size)
    sc.cycles.samples = 1   # plain surface data: one sample per texel is exact
    pos = _bake_emit(obs, im, _b_pos)
    nrm = _bake_emit(obs, im, _b_nrm)
    src = _bake_emit(obs, im, _b_src) if own else None
    sc.cycles.samples = 6
    bev = _bake_emit(obs, im, _b_bev)
    sc.cycles.samples = 16
    aop = _bake_emit(obs, im, _b_ao)
    bpy.data.images.remove(im)
    mask = aop[..., 1] > 0.05
    sel = np.nonzero(mask)
    P = (pos[sel][:, :3] - 0.5) / 0.2 / scale
    N = nrm[sel][:, :3] * 2 - 1
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-8
    B = bev[sel][:, :3] * 2 - 1
    B /= np.linalg.norm(B, axis=1, keepdims=True) + 1e-8
    AO = np.clip(aop[sel][:, 0], 0, 1)
    part = np.rint(aop[sel][:, 1] * 8 - 1).astype(np.int64)
    S = _to_srgb(src[sel][:, :3]) if own else None
    x_tip = float(P[part == 2, 0].max()) if (part == 2).any() and obs[0].name != "pods" else None
    return (mask, sel, P, N, B, AO, part, S, x_tip)


def _bake_normal(obs, onm, size, tag):
    """Object-space relief normals onm (h, w, 3, 0…1) → the tangent-space normal map image of the atlas"""
    sc = bpy.context.scene
    i_onm = bpy.data.images.load(_save_png(tag + "_objnormal", onm))
    i_onm.colorspace_settings.name = "Non-Color"

    # object-space normal → tangent-space map: bake NORMAL through a Normal Map node in object space
    # (the objects keep their transforms at identity until build() sets group origins, so object space is
    # the same for all of them up to a translation, which a normal does not see)
    i_nrm = bpy.data.images.new(tag + "_normal", size, size, alpha=False)
    i_nrm.colorspace_settings.name = "Non-Color"
    t = bpy.data.materials.new("bake_nrm")
    t.use_nodes = True
    Nd, Lk = t.node_tree.nodes, t.node_tree.links
    bsdf = Nd["Principled BSDF"]
    tx = Nd.new("ShaderNodeTexImage")
    tx.image = i_onm
    nm = Nd.new("ShaderNodeNormalMap")
    nm.space = "OBJECT"
    Lk.new(tx.outputs["Color"], nm.inputs["Color"])
    Lk.new(nm.outputs[0], bsdf.inputs["Normal"])
    tgt = Nd.new("ShaderNodeTexImage")
    tgt.image = i_nrm
    Nd.active = tgt
    origs = {}
    for ob in obs:
        origs[ob.name] = list(ob.data.materials)
        for i in range(len(origs[ob.name])):
            ob.data.materials[i] = t
    sc.cycles.samples = 1
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=16, use_clear=True)
    i_nrm.filepath_raw = os.path.join(TMP, tag + "_normal.png")
    i_nrm.file_format = "PNG"
    i_nrm.save()
    for ob in obs:
        for i, m in enumerate(origs[ob.name]):
            ob.data.materials[i] = m
    bpy.data.materials.remove(t)
    return i_nrm


def _finish(obs, mat_name, i_alb, i_orm, i_nrm):
    """Give the objects the one paint material (glass and glowing faces keep theirs)"""
    origs = {ob.name: list(ob.data.materials) for ob in obs}
    # a later paint of the same run: the previous paint's material and textures go (the relief normal map is
    # shared), so the new ones take the same names and the GLB's textures keep their file names
    for m in {m for ms in origs.values() for m in ms if m is not None and m.name.startswith(mat_name)}:
        for nd in m.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image is not None and nd.image != i_nrm:
                bpy.data.images.remove(nd.image)
        bpy.data.materials.remove(m)
    origs = {ob.name: list(ob.data.materials) for ob in obs}
    i_alb.name = mat_name + "_albedo"
    i_orm.name = mat_name + "_orm"
    i_nrm.name = mat_name + "_normal"

    # final material: one paint material, glass and glowing parts stay separate
    pm = bpy.data.materials.new(mat_name)
    pm.use_nodes = True
    Nd, Lk = pm.node_tree.nodes, pm.node_tree.links
    bsdf = Nd["Principled BSDF"]
    ta = Nd.new("ShaderNodeTexImage")
    ta.image = i_alb
    Lk.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
    to = Nd.new("ShaderNodeTexImage")
    to.image = i_orm
    sp = Nd.new("ShaderNodeSeparateColor")
    Lk.new(to.outputs["Color"], sp.inputs[0])
    Lk.new(sp.outputs["Green"], bsdf.inputs["Roughness"])
    Lk.new(sp.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = Nd.new("ShaderNodeTexImage")
    tn.image = i_nrm
    nm = Nd.new("ShaderNodeNormalMap")
    Lk.new(tn.outputs["Color"], nm.inputs["Color"])
    Lk.new(nm.outputs[0], bsdf.inputs["Normal"])
    for ob in obs:
        me = ob.data
        orig = origs[ob.name]
        kept = []
        idx = np.zeros(len(me.polygons), np.int32)
        for p in me.polygons:
            m = orig[p.material_index]
            if _part(m) == 3:
                if m not in kept:
                    kept.append(m)
                idx[p.index] = 1 + kept.index(m)
        me.materials.clear()
        me.materials.append(pm)
        for m in kept:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", idx)
        if "src" in me.uv_layers:
            me.uv_layers.remove(me.uv_layers["src"])
        me.update()
