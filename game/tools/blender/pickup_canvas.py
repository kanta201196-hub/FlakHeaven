"""Canvas cover of the convoy's light truck (fh_battle_e_convoy_pickup_tent.glb, node "tent"): real canvas over
hoops instead of a smooth loft with a 3 cm sag (weak-props list, 2026-10-29: "the pickup's tent is the same flat
sheet problem"). A fictional light truck "inspired by" mid-century 4x4s; no markings.

What is built, in the place and size of the old cover (OLD_LO / OLD_HI):
  four steel hoops under the canvas, which is pulled taut over each of them (a ridge across the roof) and sags
  between them (the roof bellies down ~7 cm, the sides draw in); tension folds fan out from the hoop tops and from
  every tie-down point; the side curtains hang to the bed rail, their hem lifting and bulging between the ties;
  rope ties in loops from the hem to the rail, the rail rope along each side; the front end closed against the
  cab with a slack panel; the rear flap rolled up under the last hoop and tied, the inside open; rolled hems.
Paint (turret_paint own-colour bake, as market_cloth.py): faded olive canvas, sun-bleached on the roof, sewn
panel seams and two patches, soft rain stains in the sag pockets, road dust and mud splashed up the lower sides,
dirt rubbed in at the ties, a fine weave relief; matte (roughness 0.9-1.0). Smooth-shaded, two-sided.

The rest of the GLB is not re-exported: this script swaps only the tent node's mesh, material and three textures
in the file (glb_io-style merge), so the body, wheels and their weathered textures stay byte for byte. The old
cover's place is fixed in OLD_LO / OLD_HI, so a rerun replaces the cover again in the same place.

Run (repo root; bpy 5.2 pip module, numpy, Pillow; ~1 min on 2 threads):
  python3 game/tools/blender/pickup_canvas.py [--glb=game/models/battle/fh_battle_e_convoy_pickup_tent.glb]
      [--out=<same>] [--size=1024] [--threads=2]
Then `godot --headless --path game --import` extracts the new textures next to the GLB
(fh_battle_e_convoy_pickup_tent_convoy_pickup_tent_canvas_{albedo,orm,normal}.jpg).
"""
import argparse
import copy
import math
import os
import random
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402,I001
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

import glb_io  # noqa: E402
import hq_lib as H  # noqa: E402
import turret_paint as TP  # noqa: E402

GAME = Path(__file__).resolve().parents[2]
GLB = GAME / "models" / "battle" / "fh_battle_e_convoy_pickup_tent.glb"
TRUCK_M = 5.5           # the truck's real length: the GLB is 1 long
BSC = 0.19               # turret_paint scale (model units per turret unit): bevel ~6 mm, AO reach ~15 cm
# The old loft cover (convoy_models.py light_truck, revision dde7ae6) in glTF axes (x, y up, z), and the tent
# node's translation: the new cover takes its place. Constants, so a rerun on the new GLB builds the same cover
OLD_LO = (-0.4719, 0.205, -0.1637)
OLD_HI = (-0.0841, 0.407, 0.1636)
NODE_T = (-0.278, 0.30599886, -6.760657e-05)
MAT = "convoy_pickup_tent_canvas"
CLASSES = {"canvas": (0.4, 0.41, 0.3), "rope": (0.34, 0.3, 0.22), "steel": (0.22, 0.21, 0.19),
           "dark": (0.06, 0.055, 0.05)}
CID = {k: i for i, k in enumerate(CLASSES)}
CANVAS, ROPE, STEEL, DARK = range(len(CLASSES))
SEED = 24


def rod(cls, p0, p1, r, seg=5):
    d = Vector(p1) - Vector(p0)
    if d.length < 1e-7:
        return
    H.emit(H.cyl(r, d.length, seg), cls, H.T(*((Vector(p0) + Vector(p1)) / 2)) @ H.AX(d))


def poly(cls, pts, r, seg=5):
    for a, b in zip(pts[:-1], pts[1:]):
        rod(cls, a, b, r, seg)


def nz(p, f, s=0.0):
    return noise.noise(Vector(p) * f + Vector((SEED + s, SEED * 0.4, s * 1.3)))


def build(x0, x1, hw, z0, zs, zt):
    """The cover in Blender axes (x forward, y left, z up), model units. x0 rear end, x1 front end, hw half width,
    z0 the curtains' foot (bed rail), zs where the roof arc starts, zt the roof top"""
    L = x1 - x0
    bows = [x1 - 0.012, x1 - L * 0.36, x0 + L * 0.3, x0 + 0.018]
    na = 10   # roof arc segments
    prof = [(hw, zs)]
    for i in range(1, na):
        a = math.pi * i / na
        prof.append((hw * math.cos(a), zs + (zt - zs) * math.sin(a)))
    prof.append((-hw, zs))
    # arc-length parameter s of the roof profile, and the side drops
    nx = 64
    ties = np.linspace(x0 + 0.02, x1 - 0.02, 9)

    def taut(x):
        """1 on a hoop, falling to 0 midway between hoops"""
        d = min(abs(x - b) for b in bows)
        gap = L * 0.33
        return math.exp(-(d / (gap * 0.18)) ** 2)

    def slack(x):
        """0 on a hoop, 1 midway between: sin² over the bay"""
        xs = sorted(bows)
        for a, b in zip(xs[:-1], xs[1:]):
            if a <= x <= b:
                return math.sin(math.pi * (x - a) / (b - a)) ** 2
        return 0.0

    def tie_lift(x):
        """0 at a tie, 1 midway between ties (the hem lifts between the ties)"""
        d = np.abs(ties - x).min()
        return math.sin(math.pi * min(1.0, d / ((ties[1] - ties[0]) / 2)) / 2) ** 2

    def p_roof(x, j):
        y, z = prof[j]
        s = slack(x)
        top = math.sin(math.pi * j / na)            # 1 at the crown, 0 at the eaves
        dz = -0.013 * s * (0.35 + 0.65 * top)       # the roof bellies down between hoops
        dy = -math.copysign(0.006 * s, y) * (1 - top)   # and the shoulders draw in
        # tension folds: diagonal ridges from the hoop tops into each bay, fading toward mid-bay
        f = 0.0016 * math.sin(38.0 * (x + 0.6 * y) + 1.3) * s * (1 - s) * 4
        f += 0.0012 * math.sin(55.0 * (x - 0.7 * y)) * s * (1 - s) * 4
        f += 0.0015 * nz((x, y, 0), 30.0)
        n = Vector((0, y / hw * (1 - top), top)).normalized() if abs(y) > 1e-6 or top > 0 else Vector((0, 0, 1))
        return Vector((x, y + dy, z + dz)) + n * (f + 0.0012 * taut(x))

    def p_side(x, v, sgn):
        """Side curtain from the eave (v = 0) down to the rail (v = 1)"""
        lift = tie_lift(x) * 0.012                          # hem lifts between the ties
        z = zs + (z0 + lift * v - zs) * v
        s = slack(x)
        bulge = 0.006 * math.sin(math.pi * v) * (0.5 + 0.5 * tie_lift(x)) + 0.004 * v * tie_lift(x)
        fold = 0.0025 * math.sin(ties.size * 2 * math.pi * (x - x0) / L * 1.0 + 0.5) * v
        fold += 0.0012 * nz((x, sgn, v), 25.0, 3)
        y = sgn * (hw + bulge + fold - 0.006 * s * (1 - v))
        return Vector((x, y, z))

    xs = np.linspace(x0, x1, nx + 1)
    bm = bmesh.new()
    roof = [[bm.verts.new(p_roof(x, j)) for j in range(len(prof))] for x in xs]
    for i in range(nx):
        for j in range(len(prof) - 1):
            bm.faces.new((roof[i][j], roof[i + 1][j], roof[i + 1][j + 1], roof[i][j + 1]))
    nv = 6
    hems = {}
    for sgn, j_edge in ((1, 0), (-1, len(prof) - 1)):
        rows = [[roof[i][j_edge]] + [bm.verts.new(p_side(x, (k + 1) / nv, sgn)) for k in range(nv)]
                for i, x in enumerate(xs)]
        for i in range(nx):
            for k in range(nv):
                bm.faces.new((rows[i][k], rows[i + 1][k], rows[i + 1][k + 1], rows[i][k + 1]))
        hems[sgn] = [Vector(r[-1].co) for r in rows]
    front = [Vector(v.co) for v in roof[-1]]
    rear = [Vector(v.co) for v in roof[0]]
    H.emit(bm, "canvas")
    # front end: a slack panel closing the cover against the cab, bellied out a little
    bm = bmesh.new()
    ring = [Vector((x1, hw, z0))] + front + [Vector((x1, -hw, z0))]
    c = Vector((x1 + 0.004, 0, (z0 + zt) / 2))
    cv = bm.verts.new(c)
    vs = [bm.verts.new(p + Vector((0.002 * math.sin(i), 0, 0))) for i, p in enumerate(ring)]
    for a, b in zip(vs[:-1], vs[1:]):
        bm.faces.new((cv, a, b))
    bm.faces.new((cv, vs[-1], vs[0]))
    H.emit(bm, "canvas")
    # rear: the flap rolled up under the last hoop and tied; the inside open
    roll_z = zs + (zt - zs) * 0.55
    rod("canvas", (x0 - 0.004, hw * 0.85, roll_z), (x0 - 0.004, -hw * 0.85, roll_z), 0.011, 10)
    for y in (hw * 0.55, -hw * 0.55):
        poly("rope", [(x0 - 0.004, y, zt - 0.004), (x0 - 0.017, y, roll_z), (x0 - 0.004, y, roll_z - 0.014)],
             0.0016, 4)
    # hems along the curtains' feet and round the rear opening
    for sgn in (1, -1):
        poly("canvas", hems[sgn][::2], 0.0022, 5)
    poly("canvas", rear, 0.0022, 5)
    # hoops under the canvas (seen through the open rear and as ridges)
    for b in bows:
        pts = [Vector((b, hw - 0.004, z0 + 0.01))] + [Vector((b, y * 0.965, z - 0.0035)) for y, z in prof] \
            + [Vector((b, -hw + 0.004, z0 + 0.01))]
        poly("steel", pts, 0.0028, 5)
    # rail rope along each side of the bed, and the ties from the hem to it
    for sgn in (1, -1):
        rail = [Vector((x, sgn * (hw + 0.004), z0 - 0.006)) for x in np.linspace(x0, x1, 12)]
        poly("rope", rail, 0.0018, 4)
        for x in ties:
            h = hems[sgn][int(round((x - x0) / L * nx))]
            poly("rope", [h, h + Vector((0.002, sgn * 0.004, -0.006)), Vector((x + 0.004, sgn * (hw + 0.005),
                  z0 - 0.006))], 0.0015, 4)
    # the open rear shows the dark load space
    bm = bmesh.new()
    q = [bm.verts.new(p) for p in [(x0 + 0.02, hw - 0.01, z0), (x0 + 0.02, -hw + 0.01, z0),
                                   (x0 + 0.02, -hw + 0.01, zs), (x0 + 0.02, hw - 0.01, zs)]]
    bm.faces.new(q)
    H.emit(bm, "dark")
    return bows


def assemble():
    verts, faces, mids, names = [], [], [], []
    for mi, (cls, (vs, fs)) in enumerate(H.G.items()):
        off = len(verts)
        verts.extend(vs)
        faces.extend([[off + i for i in f] for f in fs])
        mids.extend([mi] * len(fs))
        names.append(cls)
    me = bpy.data.meshes.new("tent")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update(calc_edges=True)
    for n in names:
        m = bpy.data.materials.new("pc_" + n)
        m.use_nodes = True
        rgb = CLASSES[n]
        lin = tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in rgb)
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*lin, 1.0)
        me.materials.append(m)
    me.polygons.foreach_set("material_index", mids)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    # the cover is one-sided and its strips come out wound either way: face every canvas face away from the
    # bed (bbox centre at bed level), so the bake's "up" (sun bleach, dust, rain pools) and its AO see the
    # outside of the roof and Godot lights the outer side, not the underside's noisy AO
    bm.normal_update()
    ci = names.index("canvas")
    cf = [f for f in bm.faces if f.material_index == ci]
    cv = np.array([v.co[:] for f in cf for v in f.verts])
    ctr = Vector(((cv[:, 0].min() + cv[:, 0].max()) * 0.5, (cv[:, 1].min() + cv[:, 1].max()) * 0.5, cv[:, 2].min()))
    bmesh.ops.reverse_faces(bm, faces=[f for f in cf if f.normal.dot(f.calc_center_median() - ctr) < 0.0])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new("tent", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    return ob


DUST = np.array([0.62, 0.55, 0.43], np.float32)
MUD = np.array([0.3, 0.25, 0.19], np.float32)


def make_layers(z0, zt):
    rr = random.Random(SEED)
    patches = [(rr.uniform(-0.4, -0.15), rr.choice((-1, 1)) * rr.uniform(0.0, 0.12), 0.018, 0.012, 0.86),
               (rr.uniform(-0.4, -0.15), rr.uniform(-0.05, 0.05), 0.022, 0.015, 1.1)]

    def height(Pk, part):
        cloth = part == CANVAS
        Pm = Pk * TRUCK_M
        weave = 0.0003 * (TP.fbm(Pm, 45.0, SEED + 29, 2) - 0.5)   # a thread-scale sine aliases into ripples
        su = np.abs(((Pm[:, 0] + 0.5) % 1.0) - 0.5)
        seam = 0.001 * (1 - TP.sstep(0.004, 0.016, su))
        h = cloth * (weave + seam + 0.0005 * TP.fbm(Pm, 5.0, SEED + 30, 2))
        h = h + (part == ROPE) * 0.0006 * np.sin((Pm[:, 0] + Pm[:, 1] + Pm[:, 2]) * 300.0)
        return h / TRUCK_M

    def layers(P, N, B, AO, part, S):
        # the roof's baked AO is sampling noise (the hoops and the bed under the one-sided canvas catch its
        # rays; a sixth of the roof texels come out near 0): it read as a field of specks, so the sky-facing
        # canvas drops it entirely and only the walls keep it
        keep = 1.0 - TP.sstep(0.2, 0.6, np.clip(N[:, 2], 0, 1))
        AO = np.where(part == CANVAS, 1.0 - (1.0 - AO) * keep, AO)
        Pk = P * BSC                            # model units
        Pm = (Pk * TRUCK_M).astype(np.float32)  # metres
        up = np.clip(N[:, 2], 0, 1)
        t, b = TP._frame(N)
        canvas = part == CANVAS
        col = S.copy()
        mott = TP.fbm(Pm, 0.9, SEED + 1, 4)
        blot = TP.fbm(Pm, 2.0, SEED + 11, 2)   # dye unevenness at hand size: the cover is never one flat tone
        col = col * (1 + 0.14 * (mott - 0.5) + 0.1 * (blot - 0.5))[:, None]
        for px, py, hx, hy, tone in patches:   # sewn patches on the roof
            d = np.maximum(np.abs(Pk[:, 0] - px) - hx, np.abs(Pk[:, 1] - py) - hy)
            inside = (d < 0) & canvas & (up > 0.3)
            col = np.where(inside[:, None], col * tone, col)
            st = (np.abs(d) < 0.0012) & canvas & (up > 0.3) & (np.sin((Pk[:, 0] + Pk[:, 1]) * 3000) > 0)
            col = np.where(st[:, None], col * 0.68, col)
        su = np.abs(((Pm[:, 0] + 0.5) % 1.0) - 0.5)   # seams across the cover, a bolt every metre
        sm = (1 - TP.sstep(0.004, 0.012, su)) * canvas
        col = col * (1 - 0.3 * sm[:, None])
        lum = col @ np.array([0.3, 0.59, 0.11], np.float32)
        bleach = canvas * (0.1 + 0.3 * up * (0.6 + 0.8 * TP.fbm(Pm, 0.6, SEED + 2, 3)))
        col = col * (1 - 0.5 * bleach[:, None]) + (lum[:, None] * 1.12 + 0.05) * (0.5 * bleach[:, None])
        # rain stains: soft blotches where water stood in the sag (wide thresholds: a narrow one turns the noise
        # into a field of specks)
        tn = TP.fbm(Pm, 1.6, SEED + 3, 3)
        pool = TP.sstep(0.52, 0.66, tn) * up * canvas
        col = col * (1 - 0.14 * pool[:, None]) + MUD * (0.14 * pool)[:, None]
        # road dust and mud splashed up the lower sides (thickest at the rear, behind the wheels)
        hgt = (Pk[:, 2] - z0) / (zt - z0)
        rear = TP.sstep(-0.1, -0.45, Pk[:, 0])
        splash = (1 - TP.sstep(0.0, 0.55 + 0.25 * TP.fbm(Pm, 2.2, SEED + 4, 2), hgt)) * (0.45 + 0.35 * rear)
        col = col * (1 - splash[:, None] * 0.6) + (MUD * 0.5 + DUST * 0.5) * (splash[:, None] * 0.6)
        # an even film with a gentle swell: a wide swing against the dark olive reads as camouflage blots
        dust = up * (0.15 + 0.16 * (TP.fbm(Pm, 0.7, SEED + 5, 3) - 0.5))
        col = col * (1 - dust[:, None]) + DUST * dust[:, None]
        # the sides: rain and dust streaks running down from the roof edge, and the hoops' rust bleeding through
        side = canvas * (1 - TP.sstep(0.3, 0.7, up))
        streak = TP.fbm(Pm * np.array([1.0, 1.0, 0.08], np.float32), 14.0, SEED + 12, 2)
        top_band = TP.sstep(0.35, 0.95, hgt)
        sd = side * TP.sstep(0.45, 0.75, streak) * (0.35 + 0.65 * top_band)
        col = col * (1 - 0.35 * sd[:, None]) + DUST * (0.35 * sd)[:, None]
        sk = side * TP.sstep(0.55, 0.8, 1.0 - streak) * 0.25
        col = col * (1 - sk[:, None])
        cav = 1.0 - AO
        grime = np.clip(cav * 1.5, 0, 1) * (0.5 + 0.5 * TP.fbm(Pm, 3.0, SEED + 6, 2))
        col = col * (1 - 0.45 * grime[:, None]) + MUD * 0.6 * (0.45 * grime)[:, None]
        col = np.where((part == STEEL)[:, None], col * (0.8 + 0.4 * mott)[:, None], col)
        col = col * (0.62 + 0.38 * AO ** 0.7)[:, None]
        rough = np.select([canvas, part == ROPE, part == STEEL], [0.96, 0.97, 0.8], 1.0).astype(np.float32)
        rough = np.clip(rough + 0.04 * (TP.fbm(Pm, 3.0, SEED + 7, 2) - 0.5) + 0.04 * dust, 0.7, 1.0)
        metal = (0.2 * (part == STEEL)).astype(np.float32)
        e2 = 0.0004
        hu = (height(Pk + t * e2, part) - height(Pk - t * e2, part)) / (2 * e2)
        hv = (height(Pk + b * e2, part) - height(Pk - b * e2, part)) / (2 * e2)
        nn = B - (hu[:, None] * t + hv[:, None] * b) * 1.2
        nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
        return np.clip(col, 0, 1), rough, metal, nn

    return layers


def part_of(m):
    return CID.get(m.name[3:].split(".")[0], 0) if m is not None else 0


# ------------------------------------------------------------------ GLB merge (no re-export of the truck)
def _walk_tex(o, fn):
    """Call fn on every texture reference ({"index": n} under a ...Texture key) of a glTF material"""
    for k, v in o.items():
        if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
            fn(v)
        elif isinstance(v, dict):
            _walk_tex(v, fn)


def _prune(dj, node_name, mat_name):
    """Drop what a previous run of this script left in dst: the node's old primitives, every material named
    mat_name, then every accessor, texture and image nothing references any more (glb_io.compact then drops their
    buffer views), so a rerun replaces the cover instead of stacking a second one in the file"""
    node = next(n for n in dj["nodes"] if n.get("name") == node_name)
    dj["meshes"][node["mesh"]]["primitives"] = []
    keep_m = [i for i, m in enumerate(dj["materials"]) if m.get("name") != mat_name]
    m_map = {o: n for n, o in enumerate(keep_m)}
    dj["materials"] = [dj["materials"][i] for i in keep_m]
    used_acc, used_tex = set(), set()
    for me in dj["meshes"]:
        for pr in me["primitives"]:
            if "material" in pr:
                pr["material"] = m_map[pr["material"]]
            used_acc.update(pr["attributes"].values())
            if "indices" in pr:
                used_acc.add(pr["indices"])
            for t in pr.get("targets", []):
                used_acc.update(t.values())
    for sk in dj.get("skins", []):
        if "inverseBindMatrices" in sk:
            used_acc.add(sk["inverseBindMatrices"])
    for an in dj.get("animations", []):
        for smp in an["samplers"]:
            used_acc.update((smp["input"], smp["output"]))
    for m in dj["materials"]:
        _walk_tex(m, lambda v: used_tex.add(v["index"]))
    a_map = {o: n for n, o in enumerate(sorted(used_acc))}
    dj["accessors"] = [dj["accessors"][i] for i in sorted(used_acc)]
    for me in dj["meshes"]:
        for pr in me["primitives"]:
            pr["attributes"] = {k: a_map[v] for k, v in pr["attributes"].items()}
            if "indices" in pr:
                pr["indices"] = a_map[pr["indices"]]
            pr["targets"] = [{k: a_map[v] for k, v in t.items()} for t in pr.get("targets", [])] or None
            if pr["targets"] is None:
                del pr["targets"]
    for sk in dj.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = a_map[sk["inverseBindMatrices"]]
    for an in dj.get("animations", []):
        for smp in an["samplers"]:
            smp["input"], smp["output"] = a_map[smp["input"]], a_map[smp["output"]]
    t_keep = sorted(used_tex)
    t_map = {o: n for n, o in enumerate(t_keep)}
    dj["textures"] = [dj["textures"][i] for i in t_keep]
    for m in dj["materials"]:
        def re_t(v):
            v["index"] = t_map[v["index"]]
        _walk_tex(m, re_t)
    i_keep = sorted({t["source"] for t in dj["textures"]})
    i_map = {o: n for n, o in enumerate(i_keep)}
    dj["images"] = [dj["images"][i] for i in i_keep]
    for t in dj["textures"]:
        t["source"] = i_map[t["source"]]


def merge(dst_path, src_path, node_name, out_path):
    """Put the first mesh, material and textures of src (a one-node GLB) on node `node_name` of dst; everything
    else in dst stays as it is (bytes of its other buffer views and images untouched). A cover left by an earlier
    run (the node's primitives and the material of the same name) is pruned first."""
    d = glb_io.load(str(dst_path))
    s = glb_io.load(str(src_path))
    dj, sj = d.j, s.j
    _prune(dj, node_name, sj["materials"][0].get("name"))
    while len(d.bin) % 4:
        d.bin.append(0)
    bv_map = {}
    for i, bv in enumerate(sj["bufferViews"]):
        o = bv.get("byteOffset", 0)
        chunk = s.bin[o:o + bv["byteLength"]]
        while len(d.bin) % 4:
            d.bin.append(0)
        nbv = dict(bv)
        nbv["byteOffset"] = len(d.bin)
        d.bin += chunk
        bv_map[i] = len(dj["bufferViews"])
        dj["bufferViews"].append(nbv)
    acc_map = {}
    for i, a in enumerate(sj["accessors"]):
        na = dict(a)
        if "bufferView" in na:
            na["bufferView"] = bv_map[na["bufferView"]]
        acc_map[i] = len(dj["accessors"])
        dj["accessors"].append(na)
    img_map = {}
    for i, im in enumerate(sj.get("images", [])):
        ni = dict(im)
        ni["bufferView"] = bv_map[ni["bufferView"]]
        img_map[i] = len(dj.setdefault("images", []))
        dj["images"].append(ni)
    smp_map = {}
    for i, smp in enumerate(sj.get("samplers", [])):
        smp_map[i] = len(dj.setdefault("samplers", []))
        dj["samplers"].append(dict(smp))
    tex_map = {}
    for i, tx in enumerate(sj.get("textures", [])):
        nt = dict(tx)
        nt["source"] = img_map[nt["source"]]
        if "sampler" in nt:
            nt["sampler"] = smp_map[nt["sampler"]]
        tex_map[i] = len(dj["textures"])
        dj["textures"].append(nt)

    def retex(v):
        v["index"] = tex_map[v["index"]]
    mat = copy.deepcopy(sj["materials"][0])
    _walk_tex(mat, retex)
    mat_i = len(dj["materials"])
    dj["materials"].append(mat)
    prims = []
    for p in sj["meshes"][0]["primitives"]:
        np_ = copy.deepcopy(p)
        np_["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
        np_["indices"] = acc_map[p["indices"]]
        np_["material"] = mat_i
        prims.append(np_)
    node = next(n for n in dj["nodes"] if n.get("name") == node_name)
    dj["meshes"][node["mesh"]]["primitives"] = prims
    d.compact()
    d.save(str(out_path))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--glb", default=str(GLB))
    ap.add_argument("--out", default="")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--threads", type=int, default=2)
    a = ap.parse_args()
    lo, hi, tr = OLD_LO, OLD_HI, NODE_T
    H.reset(True)
    sc = bpy.context.scene
    sc.render.threads_mode = "FIXED"
    sc.render.threads = a.threads
    # glTF (x, y up, z) -> Blender (x, -z, y)
    x0, x1 = float(lo[0]), float(hi[0])
    hw = float(max(-lo[2], hi[2]))
    z0, zt = float(lo[1]), float(hi[1])
    zs = z0 + (zt - z0) * 0.77
    build(x0, x1, hw, z0, zs, zt)
    ob = assemble()
    tris = len(ob.data.polygons)
    smooth = [ob.data.materials[p.material_index].name[3:].split(".")[0] in ("canvas", "rope")
              for p in ob.data.polygons]
    ob.select_set(True)
    pal = {"own": True, "seed": SEED, "part": part_of, "layers": make_layers(z0, zt),
           "uv_scale": lambda m: 2.0 if m is not None and m.name[3:].split(".")[0] == "canvas" else 1.0}
    TP.bake_set([ob], pal, a.size, MAT, scale=BSC)
    for p, s in zip(ob.data.polygons, smooth):
        p.use_smooth = s
    # into the tent node's own frame (its translation, glTF -> Blender axes)
    ob.data.transform(Matrix.Translation((-tr[0], tr[2], -tr[1])))
    tmp = os.path.join(tempfile.mkdtemp(prefix="fh_pc_"), "tent.glb")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLB", use_selection=True, export_yup=True,
                              export_tangents=True, export_image_format="JPEG", export_jpeg_quality=90)
    merge(a.glb, tmp, "tent", a.out or a.glb)
    print("CANVAS bounds x %.3f..%.3f half width %.3f z %.3f..%.3f, %d triangles -> %s"
          % (x0, x1, hw, z0, zt, tris, a.out or a.glb))
    return 0


if __name__ == "__main__":
    sys.exit(main())
