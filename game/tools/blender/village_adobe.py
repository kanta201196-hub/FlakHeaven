"""Procedural adobe houses for the Highland kishlak (weak-models list, item 1; Kanta 28.10.2026 approved replacing
the whole list: "размер не экономить", detail over the triangle budget). Replaces the six shoebox houses
vh_h50a…f (decimated Sketchfab boxes, 200–350 triangles) with mud-brick houses of a fictional mountain village
inspired by Central Asian highland settlements: thick battered walls, flat mud roofs behind parapets with a
rounded coping, protruding roof beams (vigas) and water spouts, timber lintels, recessed doors and small deep
windows with shutters, one and two storeys, roof terraces, mud stairs and ladders, verandas on timber posts,
a timber gallery; roof clutter that reads at a few pixels (hay, firewood, rugs over the parapet, water jugs,
hatches, stovepipes). The footprints stay those of the old variants (VillageHouses.VARIANTS sizes, ±2 %), so
the village layout, lot fitting and pick() do not change.

Surfaces: each face gets a class material whose colour is a CC0 texture already in the game (fort set Г
plaster, brick, stone, wood under art/fort; the clay ground for roofs) or a flat colour. turret_paint.bake_set
(own-colour mode) then unwraps the house into one 1024 atlas and bakes the surface data; this file's layers turn
it into weathered adobe (no flat paint, Kanta 26.10): the plaster graded to a warm mud tone with mottling and
fresh patches, plaster fallen off at the base, corners and under the roof showing mud-brick courses, hairline
cracks, rain streaks running down from the roof edge, drip stains under beams and spouts (ray cast up the wall),
damp dirt and splash at the base, sun-bleached tops, cavity grime from baked AO; bleached grey timber; striped
faded rugs; roughness 0.85–1.0 (matte) and a relief normal map (trowel undulation, the plaster lip, mortar
joints, cracks). Every house is one mesh with one material (one draw call per variant, the old ones had 4–6).

Run (repo root; bpy 5.2 pip module, numpy, Pillow; no network; ~1–2 min per house on 4 cores):
  python3 game/tools/blender/village_adobe.py [--out=game/models/village] [--only=h50a,h50c] [--size=1024]
  -> <out>/vh_<name>.glb and a printed VillageHouses.VARIANTS size table. The GLB textures are extracted by
     Godot's import next to it (vh_<name>_adobe_<name>_{albedo,orm,normal}.jpg).
"""
import argparse
import math
import os
import random
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402,I001  (bpy first: it makes bmesh and mathutils importable)
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import hq_lib as H  # noqa: E402
import turret_paint as TP  # noqa: E402

GAME = Path(__file__).resolve().parents[2]
FORT = GAME / "art" / "fort"
GROUND = GAME / "art" / "ground" / "pbr"
BAKE_SCALE = 5.0   # turret_paint units per metre: bevel radius 3 cm, AO reach 0.7 m

# class -> (texture or None, flat sRGB colour, metres per texture repeat). Order = surface id in the bake.
CLASSES = {
    "plaster": (FORT / "plaster_color.jpg", (0.6, 0.53, 0.44), 2.4),
    "brick": (FORT / "brick_color.jpg", (0.62, 0.5, 0.38), 2.4),
    "stone": (FORT / "stone_color.jpg", (0.52, 0.46, 0.39), 3.2),
    "wood": (FORT / "wood_color.jpg", (0.38, 0.33, 0.28), 2.2),
    "roof": (GROUND / "clay_albedo.jpg", (0.6, 0.52, 0.42), 3.5),
    "dark": (None, (0.075, 0.064, 0.055), 1.0),
    "straw": (None, (0.74, 0.58, 0.31), 1.0),
    "clay": (None, (0.6, 0.38, 0.25), 1.0),
    "rug_r": (None, (0.52, 0.17, 0.12), 1.0),
    "rug_b": (None, (0.2, 0.24, 0.36), 1.0),
    "metal": (None, (0.24, 0.23, 0.22), 1.0),
}
CID = {k: i for i, k in enumerate(CLASSES)}
PLASTER, BRICK, STONE, WOOD, ROOF, DARK, STRAW, CLAY, RUG_R, RUG_B, METAL = range(len(CLASSES))

# target footprint (x, depth) of each variant: the old models' sizes (VillageHouses.VARIANTS)
TARGET = {"h50a": (8.49, 8.08), "h50b": (9.57, 4.25), "h50c": (8.51, 8.08), "h50d": (7.78, 5.64),
          "h50e": (8.51, 4.26), "h50f": (8.50, 8.08)}

R = random.Random(1)


# ------------------------------------------------------------------ geometry primitives
def face(cls, pts, out=None):
    """One flat face of class cls through pts; out — a direction the face must look towards (winding fixed)"""
    pts = [Vector(p) for p in pts]
    if out is not None:
        n = Vector((0.0, 0.0, 0.0))
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
        if n.dot(Vector(out)) < 0:
            pts.reverse()
    vs, fs = H.G.setdefault(cls, ([], []))
    M = H.XF[-1]
    off = len(vs)
    vs.extend(M @ p for p in pts)
    fs.append(list(range(off, off + len(pts))))


def box(cls, c, s, rot=0.0, bevel=0.0):
    """Box of size s centred on c (base centre if c has a 4th value 'base'), turned rot about Z"""
    bm = H.box(s, bevel=bevel, segs=1)
    H.emit(bm, cls, H.T(*c) @ H.RZ(rot))


def bbox(cls, x0, y0, z0, x1, y1, z1, bevel=0.0):
    """Axis-aligned box between two corners"""
    box(cls, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), bevel=bevel)


def log(cls, p0, p1, r, seg=6):
    """Round timber from p0 to p1"""
    d = Vector(p1) - Vector(p0)
    H.emit(H.cyl(r, d.length, seg), cls, H.T(*((Vector(p0) + Vector(p1)) / 2)) @ H.AX(d))


def lump(cls, c, s, seed, n=10, rings=4, rough=0.18):
    """Irregular dome (hay, a heap): rings of n points squashed to size s (x, y, height), jittered"""
    rr = random.Random(seed)
    bm = bmesh.new()
    rows = []
    for j in range(rings):
        t = j / rings
        rad = math.cos(t * math.pi * 0.5)
        z = math.sin(t * math.pi * 0.5)
        row = []
        for i in range(n):
            a = 2 * math.pi * (i + 0.5 * (j % 2)) / n
            k = 1.0 + rr.uniform(-rough, rough)
            row.append(bm.verts.new((math.cos(a) * rad * k * s[0] / 2, math.sin(a) * rad * k * s[1] / 2,
                                     (z + rr.uniform(-0.05, 0.05)) * s[2])))
        rows.append(row)
    top = bm.verts.new((rr.uniform(-0.1, 0.1) * s[0], rr.uniform(-0.1, 0.1) * s[1], s[2]))
    for j in range(rings - 1):
        for i in range(n):
            bm.faces.new((rows[j][i], rows[j][(i + 1) % n], rows[j + 1][(i + 1) % n], rows[j + 1][i]))
    for i in range(n):
        bm.faces.new((rows[-1][i], rows[-1][(i + 1) % n], top))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    H.emit(bm, cls, H.T(*c))


# ------------------------------------------------------------------ the adobe block
class Block:
    """A battered mud-brick volume: footprint x0..x1 × y0..y1 from z0 (below ground) up to the roof z1, the
    parapet ph above it. Walls lean in by `bat` over their height. Sides: 0 front (-Y), 1 right (+X),
    2 back (+Y), 3 left (-X). Openings per side: (kind, u from the side's start corner, width, sill, height);
    kinds: door, door_open, window, vent, arch (an open recess)."""

    def __init__(self, x0, y0, x1, y1, z0, z1, ph=0.45, bat=0.1, pt=0.32):
        self.x0, self.y0, self.x1, self.y1, self.z0, self.z1 = x0, y0, x1, y1, z0, z1
        self.ph, self.bat, self.pt = ph, bat, pt
        self.ops = {0: [], 1: [], 2: [], 3: []}
        self.ztop = z1 + ph

    def corners(self):
        return [Vector((self.x0, self.y0)), Vector((self.x1, self.y0)), Vector((self.x1, self.y1)),
                Vector((self.x0, self.y1))]

    def ins(self, z):
        """Inset of the wall face at height z (batter)"""
        return self.bat * max(0.0, (z - self.z0)) / (self.ztop - self.z0)

    def side(self, i):
        """Start corner, unit direction, outward normal (2D) and length of side i"""
        c = self.corners()
        a, b = c[i], c[(i + 1) % 4]
        d = (b - a)
        L = d.length
        d = d / L
        return a, d, Vector((d.y, -d.x)), L

    def P(self, i, u, z):
        """Point on side i's face: u metres from its start corner (on the ground line), height z"""
        a, d, n, L = self.side(i)
        k = self.ins(z)
        along = k + u * (L - 2 * k) / L
        q = a + d * along - n * k
        return Vector((q.x, q.y, z))

    def build(self, vigas=(0, 2), viga_z=None, spouts=1, coping_seed=0):
        """Walls with their openings, roof, parapet with a rounded coping, vigas and spouts"""
        for i in range(4):
            self._wall(i)
        self._roof_and_parapet()
        vz = self.z1 - 0.18 if viga_z is None else viga_z
        for i in vigas:
            self.vigas(i, vz)
        for k in range(spouts):
            i = (0, 2, 1, 3)[k % 4]
            a, d, n, L = self.side(i)
            u = L * (0.2 + 0.6 * R.random())
            p = self.P(i, u, self.z1 + 0.06)
            o = Vector((n.x, n.y, 0))
            box("wood", p + o * 0.25 + Vector((0, 0, 0.06)), (0.6, 0.2, 0.12), math.atan2(n.y, n.x))

    def _wall(self, i):
        a, d, n, L = self.side(i)
        ops = self.ops[i]
        us = {0.0, L}
        zs = {self.z0, self.ztop}
        for (_kind, u, w, sill, h) in ops:
            us |= {u - w / 2, u + w / 2}
            zs |= {sill, sill + h}
        us = sorted(us)
        zs = sorted(zs)
        out = (n.x, n.y, 0.0)

        def inside(uc, zc):
            for (_k, u, w, sill, h) in ops:
                if u - w / 2 < uc < u + w / 2 and sill < zc < sill + h:
                    return True
            return False
        for j in range(len(zs) - 1):
            for k in range(len(us) - 1):
                uc, zc = (us[k] + us[k + 1]) / 2, (zs[j] + zs[j + 1]) / 2
                if inside(uc, zc):
                    continue
                face("plaster", [self.P(i, us[k], zs[j]), self.P(i, us[k + 1], zs[j]),
                                 self.P(i, us[k + 1], zs[j + 1]), self.P(i, us[k], zs[j + 1])], out)
        for op in ops:
            self._opening(i, *op)

    def _opening(self, i, kind, u, w, sill, h):
        a, d, n, L = self.side(i)
        nn = Vector((n.x, n.y, 0.0))
        dep = {"door": 0.32, "door_open": 0.32, "window": 0.36, "vent": 0.22, "arch": 0.9}[kind]
        q = [self.P(i, u - w / 2, sill), self.P(i, u + w / 2, sill), self.P(i, u + w / 2, sill + h),
             self.P(i, u - w / 2, sill + h)]
        b = [p - nn * dep for p in q]
        dd = Vector((d.x, d.y, 0.0))
        face("stone" if kind.startswith("door") else "plaster", [q[0], q[1], b[1], b[0]], (0, 0, 1))
        face("plaster", [q[2], q[3], b[3], b[2]], (0, 0, -1))
        face("plaster", [q[0], b[0], b[3], q[3]], tuple(dd))
        face("plaster", [q[1], q[2], b[2], b[1]], tuple(-dd))
        back = {"door": "wood", "door_open": "dark", "window": "dark", "vent": "dark", "arch": "plaster"}[kind]
        face(back, b, tuple(nn))
        rot = math.atan2(d.y, d.x)
        mid = (b[0] + b[2]) / 2
        if kind == "door":   # planks in a frame at the back of the recess, two cross rails
            for s in (-1, 1):
                box("wood", mid + dd * s * (w / 2 - 0.05) + nn * 0.04, (0.09, 0.08, h), rot)
            for f in (-0.3, 0.3):
                box("wood", mid + nn * 0.05 + Vector((0, 0, h * f)), (w * 0.86, 0.04, 0.08), rot)
        if kind == "door_open":   # one leaf swung back against the reveal, the room dark behind it
            box("wood", mid - dd * (w / 2 - 0.04) + nn * dep * 0.5, (0.06, dep * 0.85, h * 0.96), rot)
        if kind == "window":   # frame, a mullion and shutters folded back against the wall
            box("wood", (b[0] + b[1]) / 2 + nn * 0.06, (w, 0.08, 0.06), rot)
            box("wood", (b[2] + b[3]) / 2 + nn * 0.06 - Vector((0, 0, 0.03)), (w, 0.08, 0.06), rot)
            box("wood", mid + nn * 0.06, (0.05, 0.06, h), rot)
            if R.random() < 0.7:
                for s in (-1, 1):
                    p = (q[0] if s < 0 else q[1]) + Vector((0, 0, h / 2)) + nn * 0.06 + dd * s * (w * 0.25)
                    box("wood", p, (w * 0.48, 0.04, h * 0.9), rot + s * R.uniform(0.15, 0.6))
        if kind in ("door", "door_open", "window", "arch"):   # timber lintel, a touch proud of the wall
            lt = self.P(i, u, sill + h) + Vector((0, 0, 0.08)) - nn * ((dep + 0.08) / 2 - 0.05)
            box("wood", lt, (w + 0.4, dep + 0.08, 0.16), rot, bevel=0.015)

    def _roof_and_parapet(self):
        """Roof slab at z1; parapet ring of thickness pt with a rounded coping up to ztop"""
        zt, pt = self.ztop, self.pt
        k = self.ins(zt)
        o = [Vector((self.x0 + k, self.y0 + k)), Vector((self.x1 - k, self.y0 + k)),
             Vector((self.x1 - k, self.y1 - k)), Vector((self.x0 + k, self.y1 - k))]
        cen = sum(o, Vector((0, 0))) / 4

        def ring(off, z):
            out = []
            for p in o:
                dx = -off if p.x > cen.x else off
                dy = -off if p.y > cen.y else off
                out.append(Vector((p.x + dx, p.y + dy, z)))
            return out
        if self.ph <= 0.01:   # no parapet: a rounded roof edge
            r0 = ring(0.0, zt)
            r1 = ring(0.12, zt + 0.06)
            rings = [r0, r1]
            inner = r1
        else:
            r0 = ring(0.0, zt)
            r1 = ring(pt * 0.22, zt + 0.07)
            r2 = ring(pt * 0.78, zt + 0.07)
            r3 = ring(pt, zt)
            r4 = ring(pt, self.z1)
            rings = [r0, r1, r2, r3, r4]
            inner = r4
        for a, b in zip(rings[:-1], rings[1:]):
            for i in range(4):
                j = (i + 1) % 4
                mid = (a[i] + a[j] + b[i] + b[j]) / 4
                outv = (mid.x - cen.x, mid.y - cen.y, 2.0) if a is r0 else (0, 0, 1)
                if b is rings[-1] and len(rings) > 2:
                    outv = (cen.x - mid.x, cen.y - mid.y, 0.0)
                face("plaster", [a[i], a[j], b[j], b[i]], outv)
        face("roof", inner, (0, 0, 1))

    def vigas(self, i, z, step=0.62, out=0.42, r=0.085):
        """Protruding roof beams along side i at height z"""
        a, d, n, L = self.side(i)
        nn = Vector((n.x, n.y, 0.0))
        cnt = max(2, int((L - 0.6) / step))
        for k in range(cnt):
            u = 0.3 + (L - 0.6) * (k + 0.5) / cnt + R.uniform(-0.06, 0.06)
            p = self.P(i, u, z)
            ln = out + R.uniform(-0.1, 0.12)
            tilt = Vector((R.uniform(-0.03, 0.03), R.uniform(-0.03, 0.03), R.uniform(-0.04, 0.02)))
            log("wood", p - nn * 0.25, p + (nn + tilt) * ln, r * R.uniform(0.85, 1.15))

    def vents(self, i, z, n_=5):
        """A row of small square vents under the roof (added before build())"""
        a, d, n, L = self.side(i)
        for k in range(n_):
            u = L * (k + 0.5) / n_
            self.ops[i].append(("vent", u, 0.16, z, 0.16))


# ------------------------------------------------------------------ attachments
def stair(x, y0, y1, z_top, width=0.9, along="y", sign=1, cls="plaster"):
    """Solid mud stair: steps from the ground (at y0) up to z_top (at y1), width across, against a wall"""
    n = max(4, int(z_top / 0.24))
    run = abs(y1 - y0) / n
    for k in range(n):   # each step a solid block from its front edge to the stair's top end
        zt = z_top * (k + 1) / n
        p0 = y0 + (y1 - y0) * k / n
        if y1 > y0:
            a, b = p0, y1
        else:
            a, b = y1, p0
        if along == "y":
            bbox(cls, x - width / 2, a, -0.3, x + width / 2, b, zt, bevel=0.03)
        else:
            bbox(cls, a, x - width / 2, -0.3, b, x + width / 2, zt, bevel=0.03)
    return run


def ladder(p0, p1, w=0.5):
    """Timber ladder from p0 (foot) to p1 (top)"""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    side = d.cross(Vector((0, 0, 1))).normalized() * (w / 2)
    for s in (-1, 1):
        log("wood", p0 + side * s, p1 + side * s, 0.04, 5)
    n = int(d.length / 0.32)
    for k in range(1, n):
        q = p0 + d * (k / n)
        log("wood", q - side, q + side, 0.025, 4)


def rug_over(p, nrm, width, hang, inner=0.5, cls="rug_r", wall_t=0.32, z=0.0):
    """A rug draped over a parapet: inner drop, over the coping, outer drop; p — the coping's outer edge middle"""
    p = Vector(p)
    n = Vector((nrm[0], nrm[1], 0.0)).normalized()
    t = Vector((-n.y, n.x, 0.0)) * (width / 2)
    o = p + n * 0.03
    ii = p - n * (wall_t + 0.03)
    top_o = o + Vector((0, 0, 0.09))
    top_i = ii + Vector((0, 0, 0.09))
    face(cls, [o - t + Vector((0, 0, -hang)), o + t + Vector((0, 0, -hang)), top_o + t, top_o - t], tuple(n))
    face(cls, [top_o - t, top_o + t, top_i + t, top_i - t], (0, 0, 1))
    face(cls, [top_i - t, top_i + t, ii + t - Vector((0, 0, inner)), ii - t - Vector((0, 0, inner))], tuple(-n))


def jug(c, h=0.5, seed=0):
    """Water jug (lathe), standing at c"""
    prof = [(0.0, 0.0), (0.0, 0.12), (0.1, 0.19), (0.3, 0.2), (0.62, 0.15), (0.82, 0.07), (0.92, 0.065),
            (1.0, 0.08), (1.0, 0.0)]
    bm = H.lathe([(x * h, r * h * 1.6) for x, r in prof], seg=8)
    H.emit(bm, "clay", H.T(*c) @ H.RY(-math.pi / 2))


def firewood(c, rot, seed, n=9):
    """A stack of split logs"""
    rr = random.Random(seed)
    rows = [4, 3, 2]
    k = 0
    for j, m in enumerate(rows):
        for i in range(m):
            if k >= n:
                return
            x = (i - (m - 1) / 2) * 0.15
            z = 0.07 + j * 0.12
            p = Vector((x, 0, z))
            M = H.T(*c) @ H.RZ(rot)
            q0 = M @ (p + Vector((0, -0.6 + rr.uniform(-0.05, 0.05), 0)))
            q1 = M @ (p + Vector((0, 0.6 + rr.uniform(-0.05, 0.05), 0)))
            log("wood", q0, q1, 0.065, 5)
            k += 1


def hatch(c, s=0.8):
    """Roof hatch: timber frame round a dark opening"""
    x, y, z = c
    bbox("wood", x - s / 2, y - s / 2, z, x + s / 2, y + s / 2, z + 0.1)
    face("dark", [(x - s / 2 + 0.1, y - s / 2 + 0.1, z + 0.105), (x + s / 2 - 0.1, y - s / 2 + 0.1, z + 0.105),
                  (x + s / 2 - 0.1, y + s / 2 - 0.1, z + 0.105), (x - s / 2 + 0.1, y + s / 2 - 0.1, z + 0.105)],
         (0, 0, 1))


def stovepipe(c, h=0.9):
    log("metal", c, (c[0], c[1], c[2] + h), 0.07, 8)
    box("metal", (c[0], c[1], c[2] + h + 0.02), (0.26, 0.26, 0.04))


def chimney(c, h=0.7):
    x, y, z = c
    bbox("plaster", x - 0.25, y - 0.25, z - 0.1, x + 0.25, y + 0.25, z + h, bevel=0.04)
    face("dark", [(x - 0.13, y - 0.13, z + h + 0.002), (x + 0.13, y - 0.13, z + h + 0.002),
                  (x + 0.13, y + 0.13, z + h + 0.002), (x - 0.13, y + 0.13, z + h + 0.002)], (0, 0, 1))


def hay(c, s, seed):
    """A heap of loose hay on a roof: a soft, rounded loaf (many rings, little jitter: the old coarse 12-gon
    read as a crumpled sheet) with a few flat tufts spilled round its foot"""
    lump("straw", c, s, seed, n=16, rings=6, rough=0.06)
    rr = random.Random(seed + 7)
    for k in range(3):
        a = rr.uniform(0, 2 * math.pi)
        d = rr.uniform(0.4, 0.55)
        p = (c[0] + math.cos(a) * s[0] * d, c[1] + math.sin(a) * s[1] * d, c[2])
        w = rr.uniform(0.35, 0.55)
        lump("straw", p, (w, w * rr.uniform(0.6, 0.9), rr.uniform(0.08, 0.14)), seed + 20 + k, n=9, rings=3,
             rough=0.2)


def rug_flat(c, s, rot, cls):
    """A rug laid out on a roof to dry"""
    x, y, z = c
    M = H.T(x, y, z + 0.025) @ H.RZ(rot)
    face(cls, [M @ Vector((-s[0] / 2, -s[1] / 2, 0)), M @ Vector((s[0] / 2, -s[1] / 2, 0)),
               M @ Vector((s[0] / 2, s[1] / 2, 0)), M @ Vector((-s[0] / 2, s[1] / 2, 0))], (0, 0, 1))


def posts(x0, x1, y, z0, z1, n, r=0.1):
    """A row of timber posts with a capital block each"""
    for k in range(n):
        x = x0 + (x1 - x0) * k / (n - 1)
        log("wood", (x, y, z0), (x, y, z1 - 0.14), r, 8)
        box("wood", (x, y, z1 - 0.07), (0.42, 0.26, 0.14), bevel=0.02)


def canopy(x0, x1, y0, y1, z, beams_along_y=True, roof=True):
    """A flat timber-and-mud roof on beams (veranda, gallery): main beam over the posts, joists, a mud slab"""
    box("wood", ((x0 + x1) / 2, y0 + 0.13, z + 0.08), (x1 - x0 + 0.3, 0.26, 0.16))
    n = max(3, int((x1 - x0) / 0.55))
    for k in range(n):
        x = x0 + 0.2 + (x1 - x0 - 0.4) * k / (n - 1)
        log("wood", (x, y0 - 0.22, z + 0.24), (x, y1, z + 0.24), 0.07, 6)
    if roof:
        bbox("plaster", x0 - 0.1, y0 - 0.05, z + 0.3, x1 + 0.1, y1, z + 0.5, bevel=0.06)
        face("roof", [(x0 - 0.05, y0, z + 0.505), (x1 + 0.05, y0, z + 0.505), (x1 + 0.05, y1, z + 0.505),
                      (x0 - 0.05, y1, z + 0.505)], (0, 0, 1))


def railing(x0, x1, y, z, h=0.85):
    """Timber balcony railing along x at y"""
    n = max(3, int((x1 - x0) / 0.9) + 1)
    for k in range(n):
        x = x0 + (x1 - x0) * k / (n - 1)
        box("wood", (x, y, z + h / 2), (0.08, 0.08, h))
    box("wood", ((x0 + x1) / 2, y, z + h), (x1 - x0 + 0.1, 0.12, 0.08), bevel=0.01)
    box("wood", ((x0 + x1) / 2, y, z + h * 0.45), (x1 - x0, 0.05, 0.06))


# ------------------------------------------------------------------ the six houses
def house_a():
    """L-shaped two-storey house: a full ground floor, an upper room at the back left, a roof terrace with a
    mud stair up the right side, hay and a rug on the terrace"""
    W, D = 8.3, 7.7
    x0, y0, x1, y1 = -W / 2, -D / 2 + 0.25, W / 2 - 1.0, D / 2
    g = Block(x0, y0, x1, y1, -0.3, 3.15, ph=0.5)
    g.ops[0] = [("door", 1.6, 0.95, 0.0, 1.9), ("window", 3.9, 0.55, 1.15, 0.65), ("window", 5.6, 0.55, 1.15, 0.65)]
    g.ops[3] = [("window", 2.2, 0.5, 1.2, 0.6)]
    g.ops[1] = [("window", 5.0, 0.5, 1.2, 0.6)]
    g.vents(2, 2.55, 6)
    g.build(vigas=(0,), spouts=2)
    u = Block(x0 + 0.35, y0 + 3.6, x0 + 4.6, y1 - 0.35, 3.15, 5.85, ph=0.42, bat=0.06)
    u.ops[0] = [("door_open", 1.2, 0.85, 3.15, 1.8), ("window", 3.1, 0.5, 4.0, 0.6)]
    u.ops[1] = [("window", 1.8, 0.5, 4.0, 0.6)]
    u.build(vigas=(0, 1), spouts=1)
    stair(x1 + 0.5, y0 + 0.3, y1 - 1.6, 3.15, width=0.95)
    bbox("plaster", x1 + 0.02, y1 - 1.62, -0.3, x1 + 0.98, y1 - 0.2, 3.15, bevel=0.05)   # landing
    hay((x0 + 6.0, y0 + 1.6, 3.15), (1.5, 1.2, 0.7), 11)
    rug_over(g.P(0, 3.0, g.ztop), (0, -1), 1.3, 0.5, cls="rug_r")
    jug((x0 + 5.2, y0 + 3.2, 3.15), 0.45)
    jug((x0 + 5.6, y0 + 3.4, 3.15), 0.38)
    stovepipe((x0 + 1.3, y1 - 1.1, 5.85))
    firewood((x0 + 6.3, y1 - 1.2, 3.15), 0.0, 3, n=7)
    hatch((x0 + 5.0, y1 - 1.0, 3.15))


def house_b():
    """Narrow house: a two-storey tower block on the left, a one-storey wing on the right with a terrace,
    a mud stair along the front to the terrace and a ladder to the upper roof; beam rows at both floors"""
    W, D = 9.2, 3.85
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    t = Block(x0, y0, x0 + 5.0, y1, -0.3, 5.8, ph=0.45)
    t.ops[0] = [("door", 1.3, 0.95, 0.0, 1.9), ("window", 3.4, 0.55, 1.2, 0.65), ("window", 1.4, 0.5, 3.9, 0.6),
                ("window", 3.5, 0.5, 3.9, 0.6)]
    t.ops[3] = [("window", 1.9, 0.45, 4.0, 0.55)]
    t.ops[2] = [("window", 2.5, 0.45, 4.0, 0.55)]
    t.build(vigas=(0, 2), spouts=2)
    t.vigas(0, 2.95, out=0.32)
    w = Block(x0 + 5.0, y0 + 0.15, x1 - 0.95, y1, -0.3, 3.0, ph=0.4, bat=0.08)
    w.ops[0] = [("window", 1.6, 0.5, 1.2, 0.6)]
    w.ops[1] = [("door_open", 1.9, 0.9, 0.0, 1.85)]
    w.build(vigas=(2,), spouts=1)
    stair(x1 - 0.48, y0 + 0.2, y1 - 0.7, 3.0, width=0.9)
    bbox("plaster", x1 - 0.95, y1 - 0.75, -0.3, x1, y1, 3.0, bevel=0.05)
    ladder((x0 + 5.6, y0 + 1.6, 3.0), (x0 + 5.05, y0 + 1.6, 6.35))
    hay((x0 + 6.8, y0 + 1.9, 3.0), (1.4, 1.1, 0.6), 21)
    rug_over(t.P(0, 2.4, t.ztop), (0, -1), 1.1, 0.42, cls="rug_b")
    chimney((x0 + 3.8, y1 - 0.9, 5.8))
    firewood((x0 + 1.4, y0 + 1.6, 5.8), 1.57, 5, n=6)


def house_c():
    """Square one-storey house with a deep loggia (iwan) across the front on two timber posts; hay, firewood
    and a hatch on the roof"""
    W, D = 8.3, 7.85
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    back = Block(x0, y0 + 2.4, x1, y1, -0.3, 3.0, ph=0.36)
    back.ops[0] = [("door", 2.0, 0.95, 0.0, 1.9), ("window", 4.3, 0.6, 1.1, 0.7), ("door_open", 6.2, 0.9, 0.0, 1.85)]
    back.ops[1] = [("window", 2.6, 0.5, 1.2, 0.6)]
    back.ops[3] = [("window", 3.0, 0.5, 1.2, 0.6)]
    back.vents(2, 2.45, 7)
    back.build(vigas=(1, 3), spouts=2)
    for s in (-1, 1):   # loggia side walls
        xa, xb = (x0, x0 + 1.1) if s < 0 else (x1 - 1.1, x1)
        sw = Block(xa, y0, xb, y0 + 2.45, -0.3, 3.0, ph=0.36, bat=0.06)
        sw.build(vigas=(), spouts=0)
    posts(x0 + 2.6, x1 - 2.6, y0 + 0.35, 0.0, 2.85, 2, r=0.12)
    canopy(x0 + 1.05, x1 - 1.05, y0 + 0.2, y0 + 2.5, 2.85)
    hay((x0 + 2.0, y1 - 1.8, 3.0), (1.7, 1.3, 0.75), 31)
    firewood((x1 - 1.8, y1 - 1.2, 3.0), 0.3, 7, n=9)
    hatch((x1 - 2.4, y0 + 4.0, 3.0))
    jug((x0 + 4.0, y0 + 1.2, 3.35), 0.42)
    rug_flat((x0 + 4.2, y1 - 2.0, 3.0), (2.0, 1.3), 0.2, "rug_b")
    stovepipe((x0 + 3.0, y1 - 0.8, 3.0), 0.7)


def house_d():
    """Two rooms of different heights on a stone plinth, small deep windows, vents and spouts; a rug drying on
    the lower roof, jugs and a chimney"""
    W, D = 7.5, 5.4
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    bbox("stone", x0 - 0.06, y0 - 0.06, -0.3, x0 + 4.36, y1 + 0.06, 0.42, bevel=0.04)
    bbox("stone", x0 + 4.3, y0 + 0.44, -0.3, x1 + 0.06, y1 - 0.24, 0.38, bevel=0.04)
    a = Block(x0, y0, x0 + 4.3, y1, -0.3, 3.05, ph=0.32)
    a.ops[0] = [("door", 1.4, 0.95, 0.42, 1.8), ("window", 3.2, 0.5, 1.3, 0.6)]
    a.ops[3] = [("window", 2.6, 0.45, 1.3, 0.55)]
    a.ops[2] = [("window", 2.0, 0.45, 1.3, 0.55)]
    a.build(vigas=(0, 2), spouts=2)
    b = Block(x0 + 4.3, y0 + 0.5, x1, y1 - 0.3, -0.3, 2.45, ph=0.0, bat=0.07)
    b.ops[0] = [("door_open", 1.6, 0.9, 0.38, 1.7)]
    b.ops[1] = [("window", 2.2, 0.45, 1.1, 0.5)]
    b.vents(2, 1.9, 4)
    b.build(vigas=(0, 1, 2), viga_z=2.3, spouts=1)
    rug_flat((x0 + 5.85, y0 + 2.3, 2.51), (1.9, 1.4), 0.1, "rug_r")
    jug((x0 + 5.3, y1 - 0.75, 2.51), 0.4)
    chimney((x0 + 1.0, y1 - 0.8, 3.05), 0.6)
    hatch((x0 + 3.0, y0 + 2.4, 3.05), 0.7)
    rug_over(a.P(1, 1.4, a.ztop), (1, 0), 1.0, 0.7, cls="rug_b")


def house_e():
    """Long low house with a veranda (aivan) on four timber posts along the front, beam ends over it, firewood
    under it and hay on the roof"""
    W, D = 8.3, 4.1
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    m = Block(x0, y0 + 1.55, x1, y1, -0.3, 3.15, ph=0.38)
    m.ops[0] = [("door", 1.7, 0.95, 0.0, 1.9), ("window", 3.6, 0.55, 1.1, 0.65), ("door_open", 5.4, 0.9, 0.0, 1.85),
                ("window", 7.1, 0.5, 1.1, 0.65)]
    m.ops[1] = [("window", 1.2, 0.45, 1.2, 0.55)]
    m.vents(2, 2.6, 7)
    m.build(vigas=(), spouts=2)
    bbox("stone", x0 + 0.1, y0 + 0.05, -0.3, x1 - 0.1, y0 + 1.6, 0.18, bevel=0.04)   # veranda platform
    posts(x0 + 0.4, x1 - 0.4, y0 + 0.3, 0.18, 2.95, 4, r=0.11)
    canopy(x0 + 0.2, x1 - 0.2, y0 + 0.1, y0 + 1.6, 2.95)
    firewood((x1 - 1.0, y0 + 0.95, 0.18), 1.57, 9, n=8)
    jug((x0 + 1.2, y0 + 1.0, 0.18), 0.5)
    jug((x0 + 1.6, y0 + 1.15, 0.18), 0.42)
    hay((x0 + 2.2, y1 - 1.0, 3.15), (1.4, 1.2, 0.6), 41)
    rug_over(m.P(2, 4.0, m.ztop), (0, 1), 1.4, 0.9, cls="rug_r")
    chimney((x1 - 1.2, y1 - 0.75, 3.15), 0.55)


def house_f():
    """Two-storey house with an open timber gallery: posts along the ground-floor front carry a balcony with a
    railing in front of the upper floor; a terrace corner, ladder and roof clutter"""
    W, D = 8.3, 7.85
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    g = Block(x0, y0 + 1.7, x1, y1, -0.3, 3.05, ph=0.0, bat=0.08)
    g.ops[0] = [("door", 2.2, 0.95, 0.0, 1.9), ("window", 4.4, 0.55, 1.1, 0.65), ("door_open", 6.4, 0.9, 0.0, 1.85)]
    g.ops[3] = [("window", 3.0, 0.5, 1.2, 0.6)]
    g.ops[1] = [("window", 2.4, 0.5, 1.2, 0.6)]
    g.build(vigas=(), spouts=0)
    u = Block(x0 + 0.1, y0 + 1.95, x1 - 2.4, y1 - 0.1, 3.05, 5.9, ph=0.42, bat=0.06)
    u.ops[0] = [("door_open", 1.5, 0.85, 3.05, 1.85), ("window", 3.6, 0.5, 3.95, 0.6)]
    u.ops[3] = [("window", 2.8, 0.45, 4.0, 0.55)]
    u.ops[2] = [("window", 3.0, 0.45, 4.0, 0.55)]
    u.build(vigas=(0, 2), spouts=2)
    posts(x0 + 0.35, x1 - 0.35, y0 + 0.3, 0.0, 2.9, 5, r=0.1)
    canopy(x0 + 0.15, x1 - 0.15, y0 + 0.1, y0 + 1.75, 2.9, roof=False)
    bbox("wood", x0 + 0.1, y0 + 0.05, 3.08, x1 - 0.1, y0 + 1.8, 3.18)   # balcony floor
    railing(x0 + 0.15, x1 - 0.15, y0 + 0.12, 3.18)
    # a low parapet round the terrace corner on the right
    for (a, b) in (((x1 - 2.4, y0 + 1.75), (x1 - 0.05, y0 + 1.75)), ((x1 - 0.05, y0 + 1.75), (x1 - 0.05, y1 - 0.05)),
                   ((x1 - 2.4, y1 - 0.05), (x1 - 0.05, y1 - 0.05))):
        bbox("plaster", min(a[0], b[0]) - 0.14, min(a[1], b[1]) - 0.14, 3.05, max(a[0], b[0]) + 0.14,
             max(a[1], b[1]) + 0.14, 3.45, bevel=0.07)
    ladder((x1 - 1.0, y1 - 0.6, 3.05), (x1 - 2.35, y1 - 0.6, 6.25))
    hay((x1 - 1.2, y0 + 3.2, 3.05), (1.3, 1.2, 0.65), 51)
    jug((x1 - 0.7, y0 + 4.6, 3.05), 0.42)
    stovepipe((x0 + 1.4, y1 - 1.0, 5.9))
    rug_over((x0 + 4.2, y0 + 0.12, 3.18 + 0.85), (0, -1), 1.4, 1.0, inner=0.4, cls="rug_b", wall_t=0.12)
    firewood((x0 + 3.0, y1 - 2.2, 5.9), 0.0, 13, n=6)


HOUSES = {"h50a": house_a, "h50b": house_b, "h50c": house_c, "h50d": house_d, "h50e": house_e, "h50f": house_f}
TINTS = {   # mud plaster tone per house (sRGB): fresh, old and darker re-plastered walls side by side
    "h50a": (0.68, 0.54, 0.39), "h50b": (0.64, 0.5, 0.36), "h50c": (0.7, 0.57, 0.42),
    "h50d": (0.62, 0.49, 0.35), "h50e": (0.69, 0.56, 0.41), "h50f": (0.65, 0.52, 0.38)}


# ------------------------------------------------------------------ assembly
def _srgb_to_lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def _material(cls):
    """Bake-source material: the class texture (src UVs) or its flat colour into Base Color"""
    tex, flat, _tile = CLASSES[cls]
    m = bpy.data.materials.new("vx_" + cls)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*_srgb_to_lin(flat), 1.0)
    if tex is not None:
        im = bpy.data.images.load(str(tex), check_existing=True)
        tx = m.node_tree.nodes.new("ShaderNodeTexImage")
        tx.image = im
        m.node_tree.links.new(tx.outputs["Color"], b.inputs["Base Color"])
    return m


def assemble(name):
    """Join the accumulated faces into one object with class materials, src UVs (metres / tile), welded"""
    verts, faces, mids, names = [], [], [], []
    for mi, (cls, (vs, fs)) in enumerate(H.G.items()):
        off = len(verts)
        verts.extend(vs)
        faces.extend([[off + i for i in f] for f in fs])
        mids.extend([mi] * len(fs))
        names.append(cls)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update(calc_edges=True)
    for n in names:
        me.materials.append(_material(n))
    me.polygons.foreach_set("material_index", mids)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(me)
    bm.free()
    uvl = me.uv_layers.new(name="src")
    for p in me.polygons:
        n = p.normal
        k = 1.0 / CLASSES[names[p.material_index]][2]
        for li in p.loop_indices:
            q = me.vertices[me.loops[li].vertex_index].co
            if abs(n.z) > 0.7:
                uv = (q.x, q.y)
            elif abs(n.x) >= abs(n.y):
                uv = (q.y * (1 if n.x >= 0 else -1), q.z)
            else:
                uv = (-q.x * (1 if n.y >= 0 else -1), q.z)
            uvl.data[li].uv = (uv[0] * k, uv[1] * k)
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    return ob


def fit(ob, target):
    """Scale x/y so the footprint (walls, beams and all) is the old variant's; returns the final size"""
    me = ob.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mn, mx = co.min(0), co.max(0)
    sx = target[0] / (mx[0] - mn[0])
    sy = target[1] / (mx[1] - mn[1])
    c = (mn + mx) / 2
    co[:, 0] = (co[:, 0] - c[0]) * sx
    co[:, 1] = (co[:, 1] - c[1]) * sy
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    mn, mx = co.min(0), co.max(0)
    return mx - mn, mn[2]


# ------------------------------------------------------------------ weathering layers
SB = np.array([0.55, 0.43, 0.31], np.float32)    # mud brick under the plaster
MORTAR = np.array([0.46, 0.38, 0.3], np.float32)
DIRT = np.array([0.3, 0.24, 0.18], np.float32)
DUST = np.array([0.7, 0.62, 0.5], np.float32)
# dry straw (hay on the roofs): sun-bleached gold on top, warm tan strands, deep brown where it is packed and
# shaded; a muted gold, not lemon, under the game's strong sun. Kept apart from the dust and grime, whose
# grey-beige turned the old pale yellow khaki-green in game light
STRAW_LIT = np.array([0.8, 0.64, 0.38], np.float32)
STRAW_MID = np.array([0.63, 0.47, 0.26], np.float32)
STRAW_DEEP = np.array([0.36, 0.25, 0.13], np.float32)


def make_layers(ob, tint, seed, loss=1.0):
    """The weathering function for turret_paint.bake_set (pal["layers"]) of one house: needs the object for
    the drip and roof-edge ray casts"""
    me = ob.data
    vs = [v.co.copy() for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    pmat = np.array([p.material_index for p in me.polygons])
    names = [m.name[3:] for m in me.materials]
    pcls = np.array([CID[names[i]] for i in pmat])
    bvh = BVHTree.FromPolygons(vs, polys)
    tint = np.array(tint, np.float32)
    up = Vector((0, 0, 1))

    def rays(Pm, Nm, wall):
        """Distance up to the wall's top (cast from inside the wall) and to the nearest timber overhead
        (cast from just outside it): rain runs down from the first, drips fall from the second"""
        d_top = np.full(len(Pm), 9.0, np.float32)
        d_drip = np.full(len(Pm), 9.0, np.float32)
        for i in np.nonzero(wall)[0]:
            p = Vector(Pm[i])
            nh = Vector((Nm[i, 0], Nm[i, 1], 0.0))
            loc, _n, idx, dist = bvh.ray_cast(p - nh * 0.04, up, 9.0)
            if loc is not None:
                d_top[i] = dist
            loc, _n, idx, dist = bvh.ray_cast(p + nh * 0.03, up, 3.0)
            if loc is not None and pcls[idx] in (WOOD, METAL):
                d_drip[i] = dist
        return d_top, d_drip

    def height(Pm, N, part, t):
        """Relief height (metres) and the masks the colour needs: plaster loss, mortar, cracks"""
        z = Pm[:, 2]
        wall = (np.abs(N[:, 2]) < 0.5)
        plaster = (part == PLASTER)
        ln = TP.fbm(Pm, 0.8, seed + 20, 4)
        lowb = 1.0 - TP.sstep(0.25, 1.3, z)
        score = (ln - 0.5) * 1.7 + 0.75 * lowb * loss - 0.3 + 0.12 * (TP.fbm(Pm, 3.0, seed + 21, 2) - 0.5)
        lost = TP.sstep(0.0, 0.035, score) * (plaster & wall)
        lip = (TP.sstep(-0.05, 0.0, score) - TP.sstep(0.0, 0.035, score)) * (plaster & wall)
        u = np.einsum("ij,ij->i", Pm, t)
        row = np.floor(z / 0.115)
        bu = (u + (row % 2) * 0.17) / 0.34
        dv = np.abs(z / 0.115 - np.round(z / 0.115)) * 0.115
        du = np.abs(bu - np.round(bu)) * 0.34
        mortar = 1.0 - TP.sstep(0.006, 0.014, np.minimum(dv, du))
        brick_id = TP._hash(np.floor(bu).astype(np.int64), row.astype(np.int64), np.zeros(len(z), np.int64), seed)
        c1 = np.abs(TP.fbm(Pm * np.array([1.0, 1.0, 0.7], np.float32), 0.55, seed + 30, 4) - 0.5)
        crack = (1.0 - TP.sstep(0.0012, 0.0035, c1)) * TP.sstep(0.5, 0.62, TP.fbm(Pm, 0.4, seed + 31, 2))
        crack = crack * plaster * (1 - lost)
        h = 0.004 * TP.fbm(Pm, 1.6, seed + 40, 3) + 0.0015 * TP.fbm(Pm, 9.0, seed + 41, 2)
        h = h - 0.018 * lost - 0.006 * mortar * lost + 0.003 * lip - 0.004 * crack
        h = h + ((part == STRAW) * 0.01 * TP.fbm(Pm * np.array([6.0, 6.0, 1.0], np.float32), 4.0, seed + 42, 2))
        h = h + (part == WOOD) * 0.002 * np.sin(u * 60.0 + 5 * TP.fbm(Pm, 2.0, seed + 43, 2))
        return h, lost, lip, mortar, brick_id, crack

    def layers(P, N, B, AO, part, S):
        Pm = P * BAKE_SCALE
        z = Pm[:, 2]
        t, b = TP._frame(N)
        h, lost, lip, mortar, brick_id, crack = height(Pm, N, part, t)
        wall = np.abs(N[:, 2]) < 0.5
        upf = np.clip(N[:, 2], 0, 1)
        col = S.copy()
        lum = S.mean(1, keepdims=True)
        plaster = part == PLASTER
        # plaster: the texture's light and shade over the house's mud tone; roofs the same over a drier tone
        col = np.where(plaster[:, None], tint * np.power(np.clip(lum / 0.53, 0.2, 2.0), 0.75), col)
        roofc = tint * np.array([0.98, 0.97, 0.95], np.float32)
        col = np.where((part == ROOF)[:, None], roofc * np.power(np.clip(lum / 0.5, 0.2, 2.0), 0.6), col)
        col = np.where((part == BRICK)[:, None], S * np.array([0.88, 0.8, 0.72], np.float32), col)
        mott = TP.fbm(Pm, 0.35, seed + 1, 4)
        col = col * (1.0 + 0.2 * (mott - 0.5))[:, None]
        col = col * (1.0 + 0.08 * (TP.fbm(Pm, 2.5, seed + 2, 3) - 0.5))[:, None]
        fresh = TP.sstep(0.6, 0.66, TP.fbm(Pm, 0.3, seed + 3, 3)) * plaster * wall
        col = col * (1 - 0.6 * fresh[:, None]) + (tint * 1.1 + 0.03) * (0.6 * fresh)[:, None]
        old = TP.sstep(0.6, 0.65, TP.fbm(Pm, 0.25, seed + 5, 3)) * plaster * (1 - fresh)   # darker old daub
        col = col * (1 - 0.18 * old[:, None])
        # fallen plaster: mud-brick courses, a darker broken lip round them
        brick = SB * (0.82 + 0.36 * brick_id)[:, None] * (1.0 + 0.15 * (TP.fbm(Pm, 6.0, seed + 4, 2) - 0.5))[:, None]
        brick = brick * (1 - mortar[:, None]) + MORTAR * mortar[:, None]
        col = col * (1 - lost[:, None]) + brick * lost[:, None]
        col = col * (1 - 0.18 * lip[:, None])
        col = col * (1 - 0.4 * crack[:, None])
        # rain from the roof edge and drips from beams and spouts (ray casts), then damp dirt at the base
        d_top, d_drip = rays(Pm, N, wall)
        st = TP.fbm(Pm * np.array([1.0, 1.0, 0.06], np.float32), 5.0, seed + 8, 3)
        rain = TP.sstep(0.45, 0.7, st) * np.exp(-d_top / 2.2) * wall * 0.8
        drip = TP.sstep(1.8, 0.1, d_drip) * wall * (0.6 + 0.4 * TP.fbm(Pm, 4.0, seed + 9, 2))
        rain = np.clip(rain + drip * 0.7, 0, 0.85)
        col = col * (1 - 0.42 * rain[:, None]) + DIRT * (0.42 * rain)[:, None]
        base = 1.0 - TP.sstep(0.0, 0.55 + 0.35 * TP.fbm(Pm, 1.3, seed + 10, 3), z)
        base = base * (part != DARK) * (0.55 + 0.45 * wall)
        col = col * (1 - 0.55 * base[:, None]) + DIRT * (0.55 * base)[:, None]
        splash = TP.sstep(0.62, 0.75, TP.fbm(Pm, 14.0, seed + 11, 2)) * (1 - TP.sstep(0.0, 0.4, z)) * wall
        col = col * (1 - 0.3 * splash[:, None])
        # timber: sun-greyed on top, dark in the end grain and joints
        wood = part == WOOD
        grey = lum * np.array([1.02, 0.98, 0.92], np.float32) * 1.15
        col = np.where(wood[:, None], col * (1 - 0.35 * upf[:, None]) + grey * (0.35 * upf)[:, None], col)
        # straw: strands laid roughly one way (stretched noise), tufts, the packed underside deep brown
        straw = part == STRAW
        sn = TP.fbm(Pm * np.array([3.0, 3.0, 1.0], np.float32), 6.0, seed + 12, 3)
        strand = TP.fbm(Pm * np.array([9.0, 1.2, 4.0], np.float32), 5.0, seed + 15, 3)
        tuft = TP.fbm(Pm, 1.6, seed + 16, 2)
        lit = np.clip(0.35 + 0.65 * upf + 0.35 * (tuft - 0.5), 0.0, 1.0)
        sc = STRAW_MID * (1 - lit[:, None]) + STRAW_LIT * lit[:, None]
        sc = sc * (0.7 + 0.6 * strand)[:, None] * (0.88 + 0.24 * sn)[:, None]
        deep = np.clip((0.25 - N[:, 2]) * 1.2, 0.0, 0.7)   # the overhanging, packed underside
        sc = sc * (1 - deep[:, None]) + STRAW_DEEP * deep[:, None]
        col = np.where(straw[:, None], sc, col)
        rug = (part == RUG_R) | (part == RUG_B)
        ru = np.einsum("ij,ij->i", Pm, b)
        stripe = (np.sin(ru * 18.0) > 0.55) | (np.abs(np.sin(ru * 4.0)) > 0.93)
        rugc = np.where(stripe[:, None], np.array([0.72, 0.62, 0.42], np.float32), col)
        col = np.where(rug[:, None], rugc * 0.92 + 0.04, col)
        # cavity grime from AO, sun-bleached tops, dust on what faces up
        cav = 1.0 - AO
        grime = np.where(straw[:, None], STRAW_DEEP, DIRT)   # straw darkens warm in its hollows, not grey
        col = col * (1 - 0.45 * cav[:, None]) + grime * (0.45 * cav)[:, None]
        bleach = upf * (part != DARK) * 0.12
        col = col * (1 + bleach[:, None]) + 0.02 * bleach[:, None]
        dust = upf * np.clip(cav * 1.4 + (TP.fbm(Pm, 1.2, seed + 13, 3) - 0.5) * 0.6, 0, 0.4)
        dust = dust * ((part != PLASTER) & (part != ROOF) & ~straw) + 0.08 * (part == DARK)
        col = col * (1 - dust[:, None]) + DUST * dust[:, None]
        col = col * (0.6 + 0.4 * AO ** 0.8)[:, None]
        rough = np.select([plaster, part == BRICK, part == STONE, wood, part == ROOF, part == DARK, straw,
                           part == CLAY, rug, part == METAL],
                          [0.93, 0.96, 0.9, 0.86, 0.97, 1.0, 0.95, 0.88, 0.97, 0.78], 0.95).astype(np.float32)
        rough = np.clip(rough + 0.05 * (TP.fbm(Pm, 3.0, seed + 14, 2) - 0.5) + 0.04 * lost + 0.05 * dust, 0.7, 1.0)
        metal = np.zeros(len(P), np.float32)
        # relief normal: finite differences of the height along the surface frame (lengths in bake units)
        e = 0.004
        hu = (height(Pm + t * e, N, part, t)[0] - height(Pm - t * e, N, part, t)[0]) / (2 * e)
        hv = (height(Pm + b * e, N, part, t)[0] - height(Pm - b * e, N, part, t)[0]) / (2 * e)
        nn = B - (hu[:, None] * t + hv[:, None] * b) * 1.6
        nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
        return np.clip(col, 0, 1), rough, metal, nn

    return layers


def part_of(m):
    """Surface id of a bake-source material: its class index"""
    return CID.get(m.name[3:], 0) if m is not None else 0


def build(name, out, size):
    """Model one house, bake its weathered atlas and export vh_<name>.glb; returns (size, triangles)"""
    H.reset(True)
    R.seed(zlib.crc32(name.encode()) & 0xFFFF)   # stable across runs (str hash() is salted per process)
    HOUSES[name]()
    ob = assemble("vh_" + name)
    dims, zmin = fit(ob, TARGET[name])
    ob.select_set(True)
    smooth = [ob.data.materials[p.material_index].name[3:] in ("straw", "clay") for p in ob.data.polygons]
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    seed = (sum(map(ord, name)) * 7) % 1000
    pal = {"own": True, "seed": seed, "part": part_of,
           "layers": make_layers(ob, TINTS[name], seed, loss=1.0)}
    TP.bake_set([ob], pal, size, "adobe_" + name, scale=BAKE_SCALE)
    for p, sm in zip(ob.data.polygons, smooth):   # hay and jugs round, the rest flat
        p.use_smooth = sm
    path = os.path.join(out, "vh_%s.glb" % name)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_tangents=True, export_image_format="JPEG", export_jpeg_quality=90)
    return dims, tris, zmin


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(GAME / "models" / "village"))
    ap.add_argument("--only", default="")
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    names = [n for n in HOUSES if not a.only or n in a.only.split(",")]
    os.makedirs(a.out, exist_ok=True)
    rows = []
    for n in names:
        dims, tris, zmin = build(n, a.out, a.size)
        print("HOUSE %s size %.2f x %.2f x %.2f (base %.2f) tris %d" % (n, dims[0], dims[1], dims[2], zmin, tris))
        rows.append('\t["vh_%s", Vector3(%.2f, %.2f, %.2f), ...],   # %d tris' % (n, dims[0], dims[2] + zmin, dims[1],
                                                                          tris))
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
