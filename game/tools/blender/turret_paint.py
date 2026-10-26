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

The material name has no "body", so WeaponModels._glb_mesh does not re-tint it (the paint is final)."""
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
    n = m.name if m else ""
    return 3 if "glass" in n else 2 if "barrel" in n else 1 if "dark" in n else 0


def _bake_emit(ob, img, build):
    """Bake an emission shader built by build(nodes, links, part_id) -> socket into img (all slots)"""
    orig = list(ob.data.materials)
    tmp = []
    for m in orig:
        t = bpy.data.materials.new("bake_tmp")
        t.use_nodes = True
        N, Lk = t.node_tree.nodes, t.node_tree.links
        N.clear()
        out = N.new("ShaderNodeOutputMaterial")
        em = N.new("ShaderNodeEmission")
        Lk.new(build(N, Lk, _part(m)), em.inputs["Color"])
        Lk.new(em.outputs[0], out.inputs[0])
        tx = N.new("ShaderNodeTexImage")
        tx.image = img
        N.active = tx
        tmp.append(t)
    for i, t in enumerate(tmp):
        ob.data.materials[i] = t
    bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True)
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


def _b_pos(N, Lk, pid):
    g = N.new("ShaderNodeNewGeometry")
    v = N.new("ShaderNodeVectorMath")
    v.operation = "MULTIPLY_ADD"
    Lk.new(g.outputs["Position"], v.inputs[0])
    v.inputs[1].default_value = (0.2, 0.2, 0.2)
    v.inputs[2].default_value = (0.5, 0.5, 0.5)
    return v.outputs[0]


def _b_nrm(N, Lk, pid):
    return _enc(N, Lk, N.new("ShaderNodeNewGeometry").outputs["True Normal"])


def _b_bev(N, Lk, pid):
    b = N.new("ShaderNodeBevel")
    b.samples = 8
    b.inputs["Radius"].default_value = 0.006
    return _enc(N, Lk, b.outputs[0])


def _b_ao(N, Lk, pid):
    a = N.new("ShaderNodeAmbientOcclusion")
    a.samples = 16
    a.inputs["Distance"].default_value = 0.14
    c = N.new("ShaderNodeCombineColor")
    Lk.new(a.outputs["AO"], c.inputs[0])
    c.inputs[1].default_value = (pid + 1) / 8.0   # G: part id (+1, so 0 is "no surface")
    return c.outputs[0]


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


def _layers(P, N, B, AO, part, x_tip, pal, guns):
    """Albedo (sRGB), roughness, metal, height-perturbed normal for the covered texels"""
    seed = pal["seed"]
    n_pts = len(P)
    body, dark, barrel, glass = part == 0, part == 1, part == 2, part == 3
    # --- base colour: the livery's soft-edged blotches (two noise fields over the sand base, like the plane's
    # SAND_CAMO pattern): red-brown where the first field is high, olive where the second one is
    base, brown, olive = (np.array(t, np.float32) for t in pal["tones"])
    c1, c2 = _cuts(seed, pal["share"])
    n1 = fbm(P, 2.4, seed + 20, 3)
    n2 = fbm(P, 2.8, seed + 21, 3)
    col = np.tile(base, (n_pts, 1))
    col[(n2 > c2) & (n1 <= c1)] = olive
    col[n1 > c1] = brown
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
    # --- normal: bevelled base normal tilted by the relief gradient (finite differences along t, b)
    t, b = _frame(N)
    armour = body.astype(np.float32)   # panel lines, welds and rivets only on the painted armour
    e = 0.0007
    hu = (_height(P + t * e, t, b, armour, seed) - _height(P - t * e, t, b, armour, seed)) / (2 * e)
    hv = (_height(P + b * e, t, b, armour, seed) - _height(P - b * e, t, b, armour, seed)) / (2 * e)
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


def _save_png(name, arr):
    """arr (h, w, c) 0…1 with Blender's bottom-up rows → PNG on disk, loaded back as a Blender image"""
    p = os.path.join(TMP, name + ".png")
    Image.fromarray((np.clip(arr[::-1], 0, 1) * 255 + 0.5).astype(np.uint8)).save(p)
    return p


def bake(ob, pal, size, mat_name):
    """Unwrap ob, bake the paint layers and replace its materials with mat_name (glass faces keep theirs)"""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 0
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")

    im = _img("tp_data", size)
    sc.cycles.samples = 1   # plain surface data: one sample per texel is exact
    pos = _bake_emit(ob, im, _b_pos)
    nrm = _bake_emit(ob, im, _b_nrm)
    sc.cycles.samples = 6
    bev = _bake_emit(ob, im, _b_bev)
    sc.cycles.samples = 16
    aop = _bake_emit(ob, im, _b_ao)
    bpy.data.images.remove(im)
    mask = aop[..., 1] > 0.05
    sel = np.nonzero(mask)
    P = (pos[sel][:, :3] - 0.5) / 0.2
    N = nrm[sel][:, :3] * 2 - 1
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-8
    B = bev[sel][:, :3] * 2 - 1
    B /= np.linalg.norm(B, axis=1, keepdims=True) + 1e-8
    AO = np.clip(aop[sel][:, 0], 0, 1)
    part = np.rint(aop[sel][:, 1] * 8 - 1).astype(np.int64)
    x_tip = float(P[part == 2, 0].max()) if (part == 2).any() and ob.name != "pods" else None

    H, W = mask.shape
    alb = np.zeros((H, W, 3), np.float32)
    orm = np.zeros((H, W, 3), np.float32)
    onm = np.zeros((H, W, 3), np.float32)
    CH = 400000
    for s0 in range(0, len(P), CH):
        sl = slice(s0, s0 + CH)
        col, rough, metal, nn = _layers(P[sl], N[sl], B[sl], AO[sl], part[sl], x_tip, pal, ob.name)
        ys, xs = sel[0][sl], sel[1][sl]
        alb[ys, xs] = col
        orm[ys, xs] = np.stack([AO[sl], rough, metal], 1)
        onm[ys, xs] = nn * 0.5 + 0.5
    alb = _dilate(alb, mask)
    orm = _dilate(orm, mask)
    onm = _dilate(onm, mask)
    tag = mat_name
    i_alb = bpy.data.images.load(_save_png(tag + "_albedo", alb))
    i_orm = bpy.data.images.load(_save_png(tag + "_orm", orm))
    i_orm.colorspace_settings.name = "Non-Color"
    i_onm = bpy.data.images.load(_save_png(tag + "_objnormal", onm))
    i_onm.colorspace_settings.name = "Non-Color"

    # object-space normal → tangent-space map: bake NORMAL through a Normal Map node in object space
    i_nrm = bpy.data.images.new(tag + "_normal", size, size, alpha=False)
    i_nrm.colorspace_settings.name = "Non-Color"
    orig = list(me.materials)
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
    for i in range(len(orig)):
        me.materials[i] = t
    sc.cycles.samples = 1
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=16, use_clear=True)
    i_nrm.filepath_raw = os.path.join(TMP, tag + "_normal.png")
    i_nrm.file_format = "PNG"
    i_nrm.save()

    # final material: one paint material, glass stays separate
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
    glass_m = next((m for m in orig if _part(m) == 3), None)
    gl = np.array([_part(orig[p.material_index]) == 3 for p in me.polygons], bool)
    me.materials.clear()
    me.materials.append(pm)
    if glass_m is not None and gl.any():
        me.materials.append(glass_m)
    me.polygons.foreach_set("material_index", gl.astype(np.int32) if glass_m is not None else np.zeros(len(gl), np.int32))
    me.update()
    bpy.data.materials.remove(t)
    print("PAINT %s: %d px, %d texels covered" % (mat_name, size, int(mask.sum())))
