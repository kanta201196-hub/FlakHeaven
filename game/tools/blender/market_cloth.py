"""Cloth of the Highland kishlak market: three market tents, the shop awning and the ring stall (weak-props list,
2026-10-29: "the market tents and awnings are flat pale sheets with hard triangle facets and look like crumpled
paper from above"). Replaces vc_tent_a/b/c (flat quads, 164 triangles), vc_awning and vc_stall (decimated
Sketchfab models with one flat cloth class) with code-built cloth of a fictional mountain bazaar:

  tent_a — gabled tent: a ridge pole on two end posts, four eave posts; the two slopes sag between the ridge and
           the eaves, the free eave edge droops between posts, tension folds fan out from every post top; a
           scalloped valance with vertical folds; faded madder-red canvas with cream stripes; guy ropes to stakes;
           a trestle counter with produce, crates and a sack.
  tent_b — sunshade: four corner posts and a centre post that lifts the canvas into a soft peak, the canvas
           sagging into the four edges, valances all round; undyed cream canvas with an indigo trim and patches;
           a counter with pots and baskets.
  tent_c — lean-to: canvas from two tall back posts down to two front posts, sagging between three rafters,
           the front edge pulled out by guy ropes; a side curtain hanging in folds; washed indigo with thin pale
           stripes; a low counter with sacks and baskets.
  awning — shop awning: a ledger beam on the wall (+y, Godot −z), rafters to four front posts, the canvas sagging
           between the rafters and drooping at the front, a scalloped valance and one curtain let down at a bay;
           faded saffron canvas with brown stripes.
  stall  — ring stall: a square sunshade on four posts with a soft peak, a valance, a counter with pots, baskets
           and fruit; faded olive-green canvas.
Footprints and heights are the old models' (VillageHouses.PROPS), so the market layout does not move.

Surfaces: every face gets a class (canvas, trim, wood, rope, clay, produce, wicker, burlap) with a flat colour.
turret_paint.bake_set (own-colour mode, as village_adobe.py) unwraps the prop into one atlas and bakes the
surface data; this file's layers turn it into matte, used cloth (no flat paint, Kanta 26.10): stripes and trims
woven into the canvas, sun bleaching on what faces the sky, dust settled on top and splashed up the hems, damp
tide marks where rain pooled in the sag, sewn panel seams and patches with stitched borders, a fine weave relief,
grimy folds from the baked AO; grey weathered timber with grain, fibrous rope, clay, wicker and burlap goods.
Roughness 0.8-1.0. Cloth is smooth-shaded (no triangle facets) and the game draws it two-sided
(adobe_baked.gdshader, VillageHouses BAKED prefix "cloth_"). One mesh and one material per prop: one draw call
per variant in a village (the old ones had two or three surfaces).

Run (repo root; bpy 5.2 pip module, numpy, Pillow; no network; ~1-2 min a prop on 2 threads):
  python3 game/tools/blender/market_cloth.py [--out=game/models/village] [--only=tent_a,awning] [--size=1024]
      [--threads=2]
  -> <out>/vc_<name>.glb and a printed size table for VillageHouses.PROPS. Godot's import extracts the textures
     next to the GLB (vc_<name>_cloth_<name>_{albedo,orm,normal}.jpg).
"""
import argparse
import math
import os
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402,I001  (bpy first: it makes bmesh and mathutils importable)
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

import hq_lib as H  # noqa: E402
import turret_paint as TP  # noqa: E402

GAME = Path(__file__).resolve().parents[2]
BAKE_SCALE = 5.0   # turret_paint units per metre: bevel radius 3 cm, AO reach 0.7 m

# class -> flat sRGB colour. Order = surface id in the bake. "canvas" and "trim" take each prop's own colours.
CLASSES = {
    "canvas": (0.6, 0.55, 0.45),
    "trim": (0.3, 0.3, 0.35),
    "wood": (0.36, 0.28, 0.2),
    "rope": (0.56, 0.49, 0.37),
    "clay": (0.62, 0.4, 0.27),
    "fruit_r": (0.6, 0.17, 0.09),
    "fruit_o": (0.78, 0.5, 0.15),
    "fruit_g": (0.36, 0.44, 0.17),
    "wicker": (0.62, 0.5, 0.31),
    "burlap": (0.58, 0.5, 0.38),
    "dark": (0.08, 0.07, 0.06),
}
CID = {k: i for i, k in enumerate(CLASSES)}
(CANVAS, TRIM, WOOD, ROPE, CLAY, FRUIT_R, FRUIT_O, FRUIT_G, WICKER, BURLAP, DARK) = range(len(CLASSES))
SMOOTH = {"canvas", "trim", "rope", "clay", "fruit_r", "fruit_o", "fruit_g", "burlap"}

# per prop: canvas colour, trim colour, stripes (stripe colour, period m, stripe share, axis 0 = x / 1 = y) or None,
# target footprint (x, depth) and height in metres (VillageHouses.PROPS), seed
PROPS = {
    "tent_a": {"canvas": (0.6, 0.27, 0.2), "trim": (0.72, 0.64, 0.5), "stripes": ((0.78, 0.7, 0.55), 0.62, 0.32, 0),
               "size": (3.6, 3.2, 2.55), "seed": 11},
    "tent_b": {"canvas": (0.74, 0.68, 0.56), "trim": (0.24, 0.27, 0.4), "stripes": None,
               "size": (3.6, 3.2, 2.55), "seed": 23},
    "tent_c": {"canvas": (0.33, 0.37, 0.45), "trim": (0.68, 0.62, 0.5), "stripes": ((0.66, 0.63, 0.56), 0.38, 0.14, 0),
               "size": (3.6, 3.2, 2.55), "seed": 37},
    "awning": {"canvas": (0.68, 0.56, 0.36), "trim": (0.44, 0.3, 0.21), "stripes": ((0.47, 0.33, 0.23), 0.9, 0.3, 0),
               "size": (10.24, 4.78, 4.62), "seed": 41},
    "stall": {"canvas": (0.48, 0.5, 0.33), "trim": (0.62, 0.36, 0.2), "stripes": None,
              "size": (3.86, 3.89, 3.01), "seed": 53},
}

R = random.Random(1)


# ------------------------------------------------------------------ geometry
def rod(cls, p0, p1, r, seg=6):
    """Round bar from p0 to p1 (poles, ropes, rafters)"""
    d = Vector(p1) - Vector(p0)
    if d.length < 1e-6:
        return
    H.emit(H.cyl(r, d.length, seg), cls, H.T(*((Vector(p0) + Vector(p1)) / 2)) @ H.AX(d))


def box(cls, c, s, rz=0.0, bevel=0.0):
    """Box of size s centred on c, turned rz about Z"""
    H.emit(H.box(s, bevel=bevel, segs=1), cls, H.T(*c) @ H.RZ(rz))


def lump(cls, c, s, seed, rings=5, segs=8, rough=0.12):
    """Round lump of size s (fruit, a sack, a pile): a squashed sphere with a little noise"""
    bm = bmesh.new()
    rows = []
    for i in range(rings + 1):
        th = math.pi * i / rings
        row = []
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            d = Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
            k = 1.0 + rough * noise.noise(d * 2.3 + Vector((seed, seed * 0.7, 0)))
            row.append(bm.verts.new((c[0] + d.x * s[0] * k, c[1] + d.y * s[1] * k, c[2] + (d.z + 1) * s[2] * k)))
        rows.append(row)
    for i in range(rings):
        for j in range(segs):
            j1 = (j + 1) % segs
            if i == 0:
                bm.faces.new((rows[0][j], rows[1][j1], rows[1][j]))
            elif i == rings - 1:
                bm.faces.new((rows[i][j], rows[i][j1], rows[i + 1][j]))
            else:
                bm.faces.new((rows[i][j], rows[i][j1], rows[i + 1][j1], rows[i + 1][j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    H.emit(bm, cls)


def pot(c, h, r, seed):
    """Clay pot: a lathe body with a lip"""
    prof = [(0.0, r * 0.55), (h * 0.08, r * 0.8), (h * 0.45, r), (h * 0.8, r * 0.7), (h * 0.9, r * 0.5), (h, r * 0.6)]
    bm = bmesh.new()
    n = 10
    rings = [[bm.verts.new((c[0] + rr * math.cos(2 * math.pi * k / n), c[1] + rr * math.sin(2 * math.pi * k / n),
                            c[2] + z)) for k in range(n)] for z, rr in prof]
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    H.emit(bm, "clay")
    rod("dark", (c[0], c[1], c[2] + h - 0.02), (c[0], c[1], c[2] + h + 0.002), r * 0.5, 10)


def basket(c, r, h, cls_in="fruit_o", seed=0):
    """Wicker basket with a heap of produce"""
    bm = bmesh.new()
    n = 12
    prof = [(0.0, r * 0.8), (h, r)]
    rings = [[bm.verts.new((c[0] + rr * math.cos(2 * math.pi * k / n), c[1] + rr * math.sin(2 * math.pi * k / n),
                            c[2] + z)) for k in range(n)] for z, rr in prof]
    for k in range(n):
        bm.faces.new((rings[0][k], rings[0][(k + 1) % n], rings[1][(k + 1) % n], rings[1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    H.emit(bm, "wicker")
    lump(cls_in, (c[0], c[1], c[2] + h * 0.55), (r * 0.92, r * 0.92, h * 0.3), seed, 4, 10, 0.25)


def sack(c, s, seed, rz=0.0):
    """Burlap sack standing, its neck rolled down"""
    lump("burlap", c, s, seed, 6, 10, 0.1)
    rod("burlap", (c[0], c[1], c[2] + s[2] * 1.9), (c[0], c[1], c[2] + s[2] * 2.05), min(s[0], s[1]) * 0.75, 10)


def grid(cls, fn, nu, nv):
    """Quad grid surface p = fn(u, v), u, v in 0..1 (canvas, curtains, valances): one-sided, the game draws it
    both ways; returns the rows of points for hems"""
    bm = bmesh.new()
    rows = [[bm.verts.new(fn(i / nu, j / nv)) for i in range(nu + 1)] for j in range(nv + 1)]
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    pts = [[Vector(v.co) for v in row] for row in rows]
    H.emit(bm, cls)
    return pts


def hem(cls, pts, r=0.018):
    """Rolled hem along a canvas edge (gives the sheet a thickness where it ends)"""
    for a, b in zip(pts[:-1], pts[1:]):
        rod(cls, a, b, r, 5)


def nz(p, f, seed):
    """Smooth noise -1..1 at p (metres) with frequency f"""
    return noise.noise(Vector(p) * f + Vector((seed * 1.7, seed * 0.3, seed * 2.1)))


def folds(x, y, posts, seed, amp=0.05, reach=0.9, n=7):
    """Tension folds fanning out from the post tops: ridges along the pull, fading with distance"""
    dz = 0.0
    for k, (px, py) in enumerate(posts):
        dx, dy = x - px, y - py
        d = math.hypot(dx, dy)
        if d < 1e-4:
            continue
        a = math.atan2(dy, dx)
        dz += amp * math.exp(-d / reach) * min(1.0, d / 0.15) * math.sin(n * a + seed + k * 1.3)
    return dz


def valance(cls, edge, drop, seed, out, scallop=0.45):
    """Hanging strip under an edge (points along it): vertical folds bulge out along `out` (horizontal vector or a
    function of the point), a scalloped hem"""
    m = len(edge) - 1

    def fn(u, v):
        i = min(m - 1, int(u * m))
        t = u * m - i
        p = edge[i].lerp(edge[i + 1], t)
        s = u * m
        o = out(p) if callable(out) else Vector(out)
        bulge = 0.035 * math.sin(s * 2.2 + seed) * v + 0.012 * nz((p.x, p.y, 0), 3.0, seed)
        hang = drop * v * (1.0 - 0.18 * abs(math.sin(math.pi * p.x / scallop + p.y)) * v)
        return p + o * bulge + Vector((0, 0, -hang))
    rows = grid(cls, fn, m * 2, 3)
    hem(cls, rows[-1], 0.012)


def guy(top, ground, r=0.008):
    """Guy rope from a post top to a stake"""
    mid = (Vector(top) + Vector(ground)) / 2 + Vector((0, 0, -0.04))
    rod("rope", top, mid, r, 4)
    rod("rope", mid, ground, r, 4)
    rod("wood", ground, Vector(ground) + Vector((0, 0, 0.22)), 0.025, 5)


def post(x, y, z, r=0.045, lean=(0.0, 0.0)):
    """Timber post from the ground to z, a rope lashing at the top"""
    top = Vector((x + lean[0], y + lean[1], z))
    rod("wood", (x, y, -0.15), top, r, 7)
    rod("rope", top - Vector((0, 0, 0.12)), top - Vector((0, 0, 0.02)), r * 1.35, 7)
    return top


def counter(y, w, h=0.82, d=0.65, goods="produce", seed=0):
    """Trestle counter along x at depth y: plank top on two trestles, goods on it"""
    rr = random.Random(seed)
    for k in range(4):   # top planks, each a little different
        box("wood", (rr.uniform(-0.02, 0.02), y - d / 2 + d * (k + 0.5) / 4, h - 0.025),
            (w - rr.uniform(0, 0.08), d / 4 - 0.015, 0.05), rr.uniform(-0.01, 0.01))
    for sx in (-1, 1):
        x = sx * (w / 2 - 0.2)
        for sy in (-1, 1):
            rod("wood", (x, y + sy * (d / 2 - 0.05), 0), (x, y + sy * 0.05, h - 0.05), 0.03, 5)
        box("wood", (x, y, h - 0.07), (0.08, d - 0.05, 0.06))
    top = h
    if goods == "produce":
        for k, x in enumerate(np.linspace(-w / 2 + 0.35, w / 2 - 0.35, 4)):
            cls = ("fruit_r", "fruit_o", "fruit_g", "fruit_o")[k]
            box("wood", (x, y, top + 0.06), (0.5, 0.4, 0.12), rr.uniform(-0.1, 0.1))
            lump(cls, (x, y, top + 0.1), (0.22, 0.17, 0.08), seed + k, 4, 10, 0.3)
    elif goods == "pots":
        for k, x in enumerate(np.linspace(-w / 2 + 0.3, w / 2 - 0.3, 5)):
            if k % 2:
                basket((x, y + rr.uniform(-0.1, 0.1), top), 0.17, 0.16, ("fruit_g", "fruit_r")[k // 2 % 2], seed + k)
            else:
                pot((x, y + rr.uniform(-0.1, 0.1), top), rr.uniform(0.3, 0.42), rr.uniform(0.12, 0.16), seed + k)
    else:   # sacks and baskets
        for k, x in enumerate(np.linspace(-w / 2 + 0.3, w / 2 - 0.3, 4)):
            if k % 2:
                basket((x, y, top), 0.2, 0.18, "fruit_o", seed + k)
            else:
                sack((x, y, top), (0.2, 0.17, 0.16), seed + k)


# ------------------------------------------------------------------ the props
def tent_a(seed):
    """Gabled market tent, 3.6 x 3.2 m, ridge 2.55 m, eaves 1.95 m"""
    W, D, E, RZ = 1.8, 1.6, 1.95, 2.55
    posts = [(-W + 0.1, -D + 0.12), (W - 0.1, -D + 0.12), (-W + 0.1, D - 0.12), (W - 0.1, D - 0.12)]
    for x, y in posts:
        post(x, y, E - 0.02)
    for sx in (-1, 1):
        post(sx * (W - 0.1), 0.0, RZ - 0.04)
    rod("wood", (-W, 0, RZ - 0.05), (W, 0, RZ - 0.05), 0.04, 7)   # ridge pole
    for sy in (-1, 1):
        # slope from the ridge (v = 0) to the eave (v = 1): sag between ridge and eave, the eave drooping
        # between the end posts, folds from the post tops
        tops = [(x, y) for x, y in posts if y * sy > 0] + [(-W + 0.1, 0.0), (W - 0.1, 0.0)]

        def slope(u, v, sy=sy, tops=tops):
            x = -W + 2 * W * u
            y = sy * D * v
            z = RZ + (E - RZ) * v
            droop = 0.14 * math.sin(math.pi * u) * v ** 1.5
            sag = 0.09 * math.sin(math.pi * v) * (0.55 + 0.45 * math.sin(math.pi * u))
            z += -droop - sag + folds(x, y, tops, seed + sy, 0.035, 0.7, 6)
            z += 0.012 * nz((x, y, 0), 1.6, seed + sy)
            return (x, y, z)
        rows = grid("canvas", slope, 28, 14)
        edge = rows[-1]
        hem("trim", edge, 0.02)
        valance("trim", edge[::2], 0.3, seed + sy, (0, sy, 0))
        guy((-W + 0.1, sy * (D - 0.12), E - 0.04), (-W + 0.05, sy * (D + 0.35), 0.0))
        guy((W - 0.1, sy * (D - 0.12), E - 0.04), (W - 0.05, sy * (D + 0.35), 0.0))
    for sx in (-1, 1):   # gable ends: a triangle panel, slack, bellied in
        def gable(u, v, sx=sx):
            y = (-1 + 2 * u) * D * (1 - v)
            z = E + (RZ - E) * v - 0.08 * math.sin(math.pi * u) * (1 - v)
            return (sx * (W - 0.02 - 0.05 * math.sin(math.pi * u) * math.sin(math.pi * v)), y, z)
        grid("canvas", gable, 10, 4)
    # back curtain, rolled up and tied under the back eave
    rod("canvas", (-W + 0.15, D - 0.1, E - 0.18), (W - 0.15, D - 0.1, E - 0.18), 0.07, 10)
    for x in (-1.0, 0.0, 1.0):
        rod("rope", (x, D - 0.1, E - 0.06), (x, D - 0.1, E - 0.3), 0.012, 4)
    counter(-D + 0.6, 3.0, goods="produce", seed=seed)
    box("wood", (0.7, 0.75, 0.25), (0.6, 0.45, 0.5), 0.15)
    box("wood", (0.75, 0.7, 0.62), (0.5, 0.4, 0.24), -0.1)
    sack((-0.7, 0.6, 0.0), (0.26, 0.22, 0.24), seed + 9)
    sack((-1.15, 0.85, 0.0), (0.24, 0.2, 0.2), seed + 10)


def _peak_canvas(W, D, E, top, seed, posts, nu=26, sag=0.12):
    """Square canvas on corner posts at E, lifted by a centre post to `top`: a soft peak, the edges sagging between
    the corners; returns the four edge point lists (front -y, right +x, back +y, left -x)"""
    def fn(u, v):
        x = -W + 2 * W * u
        y = -D + 2 * D * v
        rr = math.hypot(x / W, y / D)
        z = E + (top - E) * math.exp(-(rr / 0.55) ** 1.6)
        su = math.sin(math.pi * u)
        sv = math.sin(math.pi * v)
        # each free edge droops between its two corner posts; the field between peak and edges bellies down
        z -= sag * max(su * abs(2 * v - 1) ** 6, sv * abs(2 * u - 1) ** 6)
        z -= 0.05 * su * sv * (1 - math.exp(-(rr / 0.5) ** 2))
        z += folds(x, y, posts, seed, 0.03, 0.6, 7) + 0.01 * nz((x, y, 0), 1.8, seed)
        return (x, y, z)
    rows = grid("canvas", fn, nu, nu)
    front = rows[0]
    back = list(reversed(rows[-1]))
    right = [rows[j][-1] for j in range(len(rows))]
    left = list(reversed([rows[j][0] for j in range(len(rows))]))
    return front, right, back, left


def tent_b(seed):
    """Sunshade tent, 3.6 x 3.2 m: four corner posts at 2.05 m, a centre post lifting the peak to 2.55 m"""
    W, D, E, TOP = 1.8, 1.6, 2.05, 2.55
    posts = [(-W, -D), (W, -D), (W, D), (-W, D)]
    for x, y in posts:
        post(x * 0.97, y * 0.96, E - 0.01)
    rod("wood", (0, 0.35, -0.1), (0, 0.05, TOP - 0.06), 0.04, 7)   # the centre post, propped off the counter
    edges = _peak_canvas(W, D, E, TOP, seed, posts)
    outs = [(0, -1, 0), (1, 0, 0), (0, 1, 0), (-1, 0, 0)]
    for k, (e, o) in enumerate(zip(edges, outs)):
        hem("trim", e, 0.02)
        valance("trim", e[::2], 0.26 if k != 2 else 0.5, seed + k, o)
    for x, y in posts:
        guy((x * 0.97, y * 0.96, E - 0.03), (x * 1.0, y * 1.2, 0.0))
    counter(-D + 0.55, 3.0, goods="pots", seed=seed)
    for k in range(3):
        pot((0.9 - k * 0.42, 0.9, 0.0), 0.45 + 0.05 * k, 0.18, seed + 20 + k)
    basket((-0.9, 0.8, 0.0), 0.24, 0.22, "fruit_r", seed + 30)
    sack((-1.3, 1.05, 0.0), (0.24, 0.2, 0.22), seed + 31)


def tent_c(seed):
    """Lean-to tent, 3.6 x 3.2 m: back posts 2.55 m, front posts 1.9 m, three rafters; a side curtain"""
    W, D, BZ, FZ = 1.8, 1.6, 2.55, 1.9
    yb, yf = D - 0.15, -D + 0.25
    xs = (-W + 0.1, 0.0, W - 0.1)
    for x in (-W + 0.1, W - 0.1):
        post(x, yb, BZ - 0.02)
        post(x, yf, FZ - 0.02, lean=(0.0, -0.05))
    for x in xs:
        rod("wood", (x, yb + 0.1, BZ), (x, yf - 0.2, FZ - 0.08), 0.035, 6)   # rafters
    tops = [(x, yb) for x in (-W + 0.1, W - 0.1)] + [(x, yf) for x in (-W + 0.1, W - 0.1)]

    def roof(u, v):
        x = -W + 2 * W * u
        y = yb + 0.12 + (yf - 0.3 - yb - 0.12) * v
        z = BZ + 0.03 + (FZ - 0.06 - BZ - 0.03) * v
        bay = abs(math.sin(math.pi * 2 * u))           # sag between the three rafters
        z -= 0.08 * bay * math.sin(math.pi * v) ** 0.8
        z -= 0.11 * bay * v ** 3                        # the free front edge droops between rafters
        z += folds(x, y, tops, seed, 0.025, 0.6, 6) + 0.01 * nz((x, y, 0), 2.0, seed)
        return (x, y, z)
    rows = grid("canvas", roof, 32, 14)
    front = rows[-1]
    hem("trim", front, 0.02)
    valance("trim", front[::2], 0.28, seed, (0, -1, 0))
    hem("trim", rows[0], 0.02)
    for x in (-W + 0.1, W - 0.1):   # the front pulled out by guy ropes
        guy((x, yf - 0.28, FZ - 0.1), (x * 0.98, yf - 0.6, 0.0))

    def side(u, v):   # side curtain from the roof edge down to 0.35 m, hanging in vertical folds
        y = yb + (yf - yb) * u
        top = BZ + (FZ - BZ) * u - 0.05
        z = top - (top - 0.35) * v
        x = -W + 0.02 - 0.06 * math.sin(u * 15.0 + seed) * v ** 0.7 - 0.03 * v
        return (x, y, z)
    rows2 = grid("canvas", side, 18, 6)
    hem("trim", rows2[-1], 0.015)
    counter(yf + 0.55, 2.9, h=0.6, goods="sacks", seed=seed)
    for k in range(3):
        sack((0.9 - k * 0.5, 0.9 + 0.12 * (k % 2), 0.0), (0.27, 0.23, 0.26), seed + 40 + k)
    box("wood", (-1.0, 0.85, 0.22), (0.55, 0.45, 0.44), 0.3)


def awning(seed):
    """Shop awning, 10.24 x 4.78 m: ledger on the wall at 4.3 m (+y), four front posts at 2.5 m (-y)"""
    W, yw, yp = 5.1, 2.3, -2.05
    ZW, ZP = 4.32, 2.5
    box("wood", (0, yw + 0.05, ZW - 0.05), (2 * W, 0.16, 0.2))   # ledger beam on the shop wall
    px = (-W + 0.15, -W / 3, W / 3, W - 0.15)
    for x in px:
        post(x, yp, ZP - 0.03, 0.06)
    rod("wood", (-W, yp, ZP - 0.05), (W, yp, ZP - 0.05), 0.05, 7)   # front beam
    rx = np.linspace(-W + 0.15, W - 0.15, 7)
    for x in rx:   # rafters from the ledger to the front beam
        rod("wood", (x, yw, ZW - 0.12), (x, yp - 0.2, ZP - 0.02), 0.04, 6)
    tops = [(x, yp) for x in px]
    bays = len(rx) - 1

    def roof(u, v):
        x = -W + 2 * W * u
        y = yw - 0.05 + (yp - 0.35 - yw + 0.05) * v
        z = ZW + (ZP - ZW) * v + 0.05
        b = abs(math.sin(math.pi * bays * (x - rx[0]) / (rx[-1] - rx[0]))) if rx[0] < x < rx[-1] else 0.0
        z -= 0.26 * b * math.sin(math.pi * min(1.0, v * 1.1)) ** 0.8 + 0.14 * b * v ** 4
        z += folds(x, y, tops, seed, 0.04, 0.8, 6) + 0.03 * nz((x, y, 0), 1.2, seed) + 0.008 * nz((x, y, 0), 4.0, seed + 5)
        return (x, y, z)
    rows = grid("canvas", roof, 60, 16)
    front = rows[-1]
    hem("trim", front, 0.022)
    valance("trim", front[::2], 0.36, seed, (0, -1, 0), 0.55)
    for x in px:
        rod("rope", (x, yp - 0.3, ZP - 0.1), (x, yp - 0.3, ZP - 0.4), 0.015, 4)

    def curtain(u, v):   # one bay's curtain let down at the end, hanging in folds to the ground
        x = px[-1] - 0.1 - (px[-1] - px[-2] - 0.4) * 0.45 * u
        z = ZP - 0.25 - (ZP - 0.3) * v
        y = yp - 0.38 - 0.07 * math.sin(u * 11.0 + seed) * (0.3 + v) - 0.05 * v
        return (x, y, z)
    rows2 = grid("trim", curtain, 12, 6)
    hem("trim", rows2[-1], 0.015)
    # the shop's goods out under the awning: a bench, sacks, baskets, crates
    box("wood", (-2.6, 0.6, 0.42), (2.2, 0.5, 0.06))
    for x in (-3.5, -1.7):
        box("wood", (x, 0.6, 0.2), (0.08, 0.4, 0.4))
    for k in range(3):
        basket((-3.2 + k * 0.55, 0.6, 0.45), 0.2, 0.17, ("fruit_o", "fruit_r", "fruit_g")[k], seed + k)
    for k in range(4):
        sack((0.4 + k * 0.5, 0.9 - 0.15 * (k % 2), 0.0), (0.26, 0.22, 0.26), seed + 10 + k)
    box("wood", (3.0, 1.0, 0.25), (0.7, 0.55, 0.5), 0.2)
    box("wood", (3.05, 1.0, 0.7), (0.55, 0.45, 0.4), -0.1)
    pot((3.9, 0.5, 0.0), 0.6, 0.22, seed + 30)
    pot((4.3, 0.8, 0.0), 0.5, 0.2, seed + 31)


def stall(seed):
    """Ring stall, 3.86 x 3.89 m: a square sunshade on four posts at 2.55 m with a peak at 3.0 m"""
    W, D, E, TOP = 1.93, 1.94, 2.55, 3.0
    posts = [(-W, -D), (W, -D), (W, D), (-W, D)]
    for x, y in posts:
        post(x * 0.9, y * 0.9, E - 0.02)
    edges = _peak_canvas(W, D, E, TOP, seed, [(x * 0.9, y * 0.9) for x, y in posts], 26, 0.14)
    rod("wood", (0, 0.2, -0.1), (0, 0.05, TOP - 0.06), 0.04, 7)
    outs = [(0, -1, 0), (1, 0, 0), (0, 1, 0), (-1, 0, 0)]
    for k, (e, o) in enumerate(zip(edges, outs)):
        hem("trim", e, 0.02)
        valance("trim", e[::2], 0.3, seed + k, o)
    counter(-D + 0.75, 3.0, goods="pots", seed=seed)
    for k in range(4):
        pot((1.05, 1.1 - k * 0.5, 0.0), 0.55 + 0.08 * (k % 2), 0.2, seed + 50 + k)
    box("wood", (-1.0, 1.0, 0.25), (0.6, 0.5, 0.5), 0.2)
    box("wood", (-0.4, 1.2, 0.2), (0.5, 0.4, 0.4), -0.3)
    basket((-1.0, 0.25, 0.0), 0.25, 0.25, "fruit_g", seed + 60)
    basket((-0.45, 0.3, 0.0), 0.22, 0.22, "fruit_r", seed + 61)


BUILD = {"tent_a": tent_a, "tent_b": tent_b, "tent_c": tent_c, "awning": awning, "stall": stall}


# ------------------------------------------------------------------ assembly
def _srgb_to_lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def _material(cls, spec):
    """Bake-source material: the class's flat colour (canvas and trim: the prop's own) into Base Color"""
    m = bpy.data.materials.new("mc_" + cls)
    m.use_nodes = True
    rgb = spec.get(cls, CLASSES[cls]) if cls in ("canvas", "trim") else CLASSES[cls]
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*_srgb_to_lin(rgb), 1.0)
    return m


def assemble(name, spec):
    """Join the accumulated faces into one object with class materials, welded, centred on the canvas"""
    verts, faces, mids, names = [], [], [], []
    for mi, (cls, (vs, fs)) in enumerate(H.G.items()):
        off = len(verts)
        verts.extend(vs)
        faces.extend([[off + i for i in f] for f in fs])
        mids.extend([mi] * len(fs))
        names.append(cls)
    co = np.array([tuple(v) for v in verts], np.float64)
    # built in metres to the old model's size: centred on the canvas footprint, ground at z = 0 (posts and
    # stakes go 15 cm into it, which the game's ground covers)
    cv = np.concatenate([np.array([tuple(v) for v in H.G["canvas"][0]], np.float64)])
    c = (cv.min(0) + cv.max(0)) / 2
    co[:, 0] -= c[0]
    co[:, 1] -= c[1]
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in co], [], faces)
    me.update(calc_edges=True)
    for n in names:
        me.materials.append(_material(n, spec))
    me.polygons.foreach_set("material_index", mids)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    return ob


# ------------------------------------------------------------------ weathering layers
DUST = np.array([0.68, 0.6, 0.48], np.float32)
DIRT = np.array([0.27, 0.22, 0.17], np.float32)
TIDE = np.array([0.36, 0.3, 0.22], np.float32)
WOOD_GREY = np.array([0.42, 0.38, 0.33], np.float32)


def make_layers(spec, seed):
    """The cloth weathering function for turret_paint.bake_set (pal["layers"]) of one prop"""
    stripes = spec.get("stripes")
    patches = []
    rr = random.Random(seed)
    sx, sy, sz = spec["size"]
    for _ in range(2 if sx < 5 else 3):   # a few sewn patches: (centre x, y, half sizes, tone)
        patches.append((rr.uniform(-sx / 2.4, sx / 2.4), rr.uniform(-sy / 2.4, sy / 2.4), rr.uniform(0.1, 0.24),
                        rr.uniform(0.08, 0.2), rr.choice((rr.uniform(0.86, 0.94), rr.uniform(1.03, 1.08)))))

    def height(Pm, part):
        """Relief in metres: weave, seams and stitched patch borders on cloth, grain on wood"""
        cloth = (part == CANVAS) | (part == TRIM)
        # coarse weave as fine noise: a thread-scale sine aliases into ripples at 4 mm a texel
        weave = 0.0004 * (TP.fbm(Pm, 45.0, seed + 29, 2) - 0.5)
        seam_u = np.abs(((Pm[:, 0] + 0.45) % 0.9) - 0.45)
        seam = 0.0012 * (1 - TP.sstep(0.004, 0.016, seam_u))
        h = cloth * (weave + seam + 0.0006 * TP.fbm(Pm, 6.0, seed + 30, 2))
        for px, py, hx, hy, _t in patches:
            d = np.maximum(np.abs(Pm[:, 0] - px) - hx, np.abs(Pm[:, 1] - py) - hy)
            h = h + (part == CANVAS) * 0.0008 * (d < 0) - (part == CANVAS) * 0.0006 * (np.abs(d) < 0.008)
        grain = TP.fbm(Pm * np.array([6.0, 6.0, 0.4], np.float32), 4.0, seed + 31, 3)
        h = h + (part == WOOD) * (0.0015 * grain - 0.0012 * TP.sstep(0.62, 0.7, grain))
        h = h + (part == WICKER) * 0.0012 * np.sin(Pm[:, 2] * 160.0) * np.sin(np.arctan2(Pm[:, 1], Pm[:, 0]) * 40.0)
        h = h + (part == BURLAP) * 0.0008 * (TP.fbm(Pm, 40.0, seed + 32, 2) - 0.5)
        return h

    def layers(P, N, B, AO, part, S):
        Pm = (P * BAKE_SCALE).astype(np.float32)   # bake units -> metres
        z = Pm[:, 2]
        up = np.clip(N[:, 2], 0, 1)
        t, b = TP._frame(N)
        canvas, trim, wood, rope = part == CANVAS, part == TRIM, part == WOOD, part == ROPE
        cloth = canvas | trim
        col = S.copy()
        mott = TP.fbm(Pm, 0.8, seed + 1, 4)
        col = col * (1.0 + 0.16 * (mott - 0.5))[:, None]
        # woven stripes in the canvas (warp threads along the slope), soft-edged as dyed yarn
        if stripes is not None:
            scol, period, share, axis = stripes
            s = (Pm[:, axis] / period) % 1.0
            st = TP.sstep(0.0, 0.03, s) * (1 - TP.sstep(share, share + 0.03, s))
            stc = np.array(scol, np.float32) * (1.0 + 0.1 * (mott - 0.5))[:, None]
            col = np.where(canvas[:, None], col * (1 - st[:, None]) + stc * st[:, None], col)
        # patches: another bolt of cloth, a little lighter or darker, with a stitched border
        for px, py, hx, hy, tone in patches:
            d = np.maximum(np.abs(Pm[:, 0] - px) - hx, np.abs(Pm[:, 1] - py) - hy)
            inside = (d < 0) & canvas
            col = np.where(inside[:, None], col * tone * np.array([1.0, 0.97, 0.92], np.float32), col)
            stitch = (np.abs(d) < 0.01) & canvas & (np.sin((Pm[:, 0] + Pm[:, 1]) * 260.0) > 0)
            col = np.where(stitch[:, None], col * 0.8, col)
        # sewn seams between canvas bolts (0.9 m), a darker line with a lighter fold beside it
        seam_u = np.abs(((Pm[:, 0] + 0.45) % 0.9) - 0.45)
        sm = (1 - TP.sstep(0.004, 0.012, seam_u)) * canvas
        col = col * (1 - 0.28 * sm[:, None]) + col * (0.1 * ((seam_u > 0.012) & (seam_u < 0.03)) * canvas)[:, None]
        # sun: the sky side bleaches, loses colour and lightens; underside and inside stay rich and darker
        lum = col @ np.array([0.3, 0.59, 0.11], np.float32)
        bleach = cloth * (0.22 + 0.5 * up * (0.75 + 0.5 * TP.fbm(Pm, 0.5, seed + 2, 3)))
        col = col * (1 - bleach[:, None] * 0.5) + (lum[:, None] * 1.15 + 0.06) * (bleach[:, None] * 0.5)
        # rain stains where water pooled in the sag: soft blotches with a slightly darker, ragged edge (one edge
        # only, a contour band of a slow noise reads as a map's height lines)
        tn = TP.fbm(Pm, 0.9, seed + 3, 3) + 0.06 * (TP.fbm(Pm, 7.0, seed + 9, 2) - 0.5)
        pool = TP.sstep(0.56, 0.6, tn) * up * cloth
        edge = (TP.sstep(0.55, 0.58, tn) - TP.sstep(0.6, 0.66, tn)).clip(0, 1) * up * cloth
        col = col * (1 - 0.14 * pool[:, None]) + DIRT * (0.14 * pool)[:, None]
        col = col * (1 - 0.12 * edge[:, None]) + TIDE * (0.12 * edge)[:, None]
        # dust: settled on what faces up, splashed up the hems near the ground, grime in the folds (AO)
        cav = 1.0 - AO
        dust = up * np.clip(0.25 + (TP.fbm(Pm, 1.3, seed + 4, 3) - 0.45) * 0.8, 0, 0.55)
        foot = (1 - TP.sstep(0.0, 0.5 + 0.3 * TP.fbm(Pm, 2.0, seed + 5, 2), z)) * 0.6
        dust = np.clip(np.maximum(dust, foot), 0, 0.7)
        col = col * (1 - dust[:, None]) + DUST * dust[:, None]
        grime = np.clip(cav * 1.4, 0, 1) * (0.5 + 0.5 * TP.fbm(Pm, 2.5, seed + 6, 2))
        col = col * (1 - 0.4 * grime[:, None]) + DIRT * (0.4 * grime)[:, None]
        hems = trim * (1 - TP.sstep(0.0, 0.06, np.abs(N[:, 2]))) * 0.15
        col = col * (1 - hems[:, None])
        # timber: weathered grey over the brown, darker grain lines, end-grain darker near the ground
        grain = TP.fbm(Pm * np.array([6.0, 6.0, 0.4], np.float32), 4.0, seed + 31, 3)
        c_w = col * 0.78 + WOOD_GREY * (0.22 * (0.6 + 0.4 * up))[:, None]
        c_w = c_w * (0.72 + 0.3 * grain)[:, None] * (0.8 + 0.2 * TP.sstep(0.0, 0.6, z))[:, None]
        col = np.where(wood[:, None], c_w, col)
        col = np.where(rope[:, None], col * (0.8 + 0.35 * TP.fbm(Pm, 30.0, seed + 7, 2))[:, None], col)
        col = col * (0.62 + 0.38 * AO ** 0.7)[:, None]
        rough = np.select([cloth, wood, rope, part == CLAY, part == FRUIT_R, part == FRUIT_O, part == FRUIT_G],
                          [0.96, 0.9, 0.97, 0.9, 0.62, 0.66, 0.6], 0.93).astype(np.float32)
        rough = np.clip(rough + 0.05 * (TP.fbm(Pm, 3.0, seed + 8, 2) - 0.5) + 0.05 * dust, 0.55, 1.0)
        metal = np.zeros(len(P), np.float32)
        e2 = 0.002
        hu = (height(Pm + t * e2, part) - height(Pm - t * e2, part)) / (2 * e2)
        hv = (height(Pm + b * e2, part) - height(Pm - b * e2, part)) / (2 * e2)
        nn = B - (hu[:, None] * t + hv[:, None] * b) * 1.2
        nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
        return np.clip(col, 0, 1), rough, metal, nn

    return layers


def part_of(m):
    """Surface id of a bake-source material: its class index"""
    return CID.get(m.name[3:], 0) if m is not None else 0


def uv_scale_of(m):
    """Texel share of a bake-source material: the canvas is what the camera sees, so it gets 2.2 times the
    density of the poles, ropes, hems and goods (which would otherwise take most of the atlas by their many small
    islands)"""
    return 2.2 if m is not None and m.name[3:] == "canvas" else 1.0


def build(name, out, size, threads):
    """Model one prop, bake its weathered atlas and export vc_<name>.glb; returns (size, triangles)"""
    spec = PROPS[name]
    H.reset(True)
    R.seed(spec["seed"])
    sc = bpy.context.scene
    sc.render.threads_mode = "FIXED"
    sc.render.threads = threads
    BUILD[name](spec["seed"])
    ob = assemble("vc_" + name, spec)
    smooth = [ob.data.materials[p.material_index].name[3:] in SMOOTH for p in ob.data.polygons]
    tris = len(ob.data.polygons)
    dims = ob.dimensions.copy()
    ob.select_set(True)
    pal = {"own": True, "seed": spec["seed"], "part": part_of, "layers": make_layers(spec, spec["seed"]),
           "uv_scale": uv_scale_of}
    TP.bake_set([ob], pal, size, "cloth_" + name, scale=BAKE_SCALE)
    for p, s in zip(ob.data.polygons, smooth):   # cloth and goods round, timber flat
        p.use_smooth = s
    path = os.path.join(out, "vc_%s.glb" % name)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_tangents=True, export_image_format="JPEG", export_jpeg_quality=90)
    return dims, tris


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(GAME / "models" / "village"))
    ap.add_argument("--only", default="")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--threads", type=int, default=2, help="Cycles CPU threads")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rows = []
    for n in BUILD:
        if a.only and n not in a.only.split(","):
            continue
        dims, tris = build(n, a.out, a.size, a.threads)
        print("CLOTH %s size %.2f x %.2f x %.2f tris %d" % (n, dims[0], dims[1], dims[2], tris))
        rows.append('\t["vc_%s", Vector3(%.2f, %.2f, %.2f)],   # %d tris' % (n, dims[0], dims[2], dims[1], tris))
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
