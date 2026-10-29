"""Procedural farmstead models of the Highland oasis (weak-models list, item 3; Kanta 28.10.2026 approved replacing
the whole list: "размер не экономить"). Replaces the oasis's orange box houses (AdobeBuild.oasis) with the adobe
houses of a fictional oasis farmstead in the same building tradition as the kishlak (village_adobe.py) and the
fort: battered mud walls, flat mud roofs behind rounded parapets, roof beams, deep openings with timber lintels.
What makes them the oasis's own is shade and water: every house has an ayvan (a deep porch on carved timber
posts under a mud roof on joists) with a raised clay platform, grapevines climb trellises and drape over the
porch roofs, and the courtyard gets a covered cistern (a mud-brick dome over a sunken tank, steps down to its
door) and a free-standing vine pergola over a platform. No real country, script or landmark: the forms are
generic arid-oasis vernacular.

The geometry helpers, the per-house weathered bake (plaster tone patches, fallen plaster over mud-brick
courses, cracks, rain streaks and drips, damp dirt at the base, AO grime, roughness 0.85-1.0, relief normal)
and the GLB export are village_adobe.py's, so the oasis and the kishlak read as one place; this file adds a
"leaf" surface class (vine foliage: mottled dusty green, yellowing leaves, dark gaps) on top of its layers and
a damper, darker foot for the cistern that stands by the pond. One mesh and one material per model.

Run (repo root; bpy 5.2 pip module, numpy, Pillow; no network; ~1-2 min per model on 4 cores):
  python3 game/tools/blender/oasis_adobe.py [--out=game/models/village] [--only=oh_a,oh_cistern] [--size=1024]
  -> <out>/<name>.glb and a printed VillageHouses.OASIS size table (x, height above ground, depth in metres).
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
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import hq_lib as H  # noqa: E402
import turret_paint as TP  # noqa: E402
import village_adobe as V  # noqa: E402

GAME = Path(__file__).resolve().parents[2]

# vine foliage: one more surface class after the village's (their ids are unchanged)
V.CLASSES["leaf"] = (None, (0.3, 0.36, 0.17), 1.0)
V.CID["leaf"] = len(V.CLASSES) - 1
LEAF = V.CID["leaf"]

box, bbox, log, lump, face = V.box, V.bbox, V.log, V.lump, V.face


# ------------------------------------------------------------------ oasis pieces
def platform(x0, y0, x1, y1, h=0.32, rug=None):
    """Raised clay platform (supa) to sit and sleep on in the shade, a rug on it"""
    bbox("plaster", x0, y0, -0.3, x1, y1, h, bevel=0.06)
    if rug:
        V.rug_flat(((x0 + x1) / 2, (y0 + y1) / 2, h), (min(2.2, (x1 - x0) * 0.8), min(1.6, (y1 - y0) * 0.75)),
                   random.Random(int(x0 * 100)).uniform(-0.1, 0.1), rug)


def carved_post(x, y, z0, z1, r=0.11):
    """Timber ayvan post: a stone base, an octagonal shaft, a thicker collar and a wide bracket capital"""
    box("stone", (x, y, z0 + 0.12), (0.34, 0.34, 0.24), bevel=0.03)
    log("wood", (x, y, z0 + 0.24), (x, y, z1 - 0.32), r, 8)
    log("wood", (x, y, z1 - 0.4), (x, y, z1 - 0.3), r * 1.35, 8)
    box("wood", (x, y, z1 - 0.2), (0.28, 0.28, 0.2), bevel=0.02)
    box("wood", (x, y, z1 - 0.06), (0.75, 0.3, 0.12), bevel=0.02)   # bracket under the main beam


def ayvan(x0, x1, y0, y1, z, n_posts, roof=True):
    """Porch along x: carved posts on the front line y0 + 0.3, the village canopy (main beam, joists, mud slab)
    reaching back to the wall at y1"""
    for k in range(n_posts):
        x = x0 + 0.35 + (x1 - x0 - 0.7) * k / max(1, n_posts - 1)
        carved_post(x, y0 + 0.3, 0.0, z)
    V.canopy(x0, x1, y0, y1, z, roof=roof)


def foliage(cx, cy, z, sx, sy, seed, cover=0.75, droop=0.5):
    """Vine canopy over a trellis: overlapping flat leaf mounds over the joists (some gaps where the light falls
    through), bunches hanging over the front edge, the vine's twisted stems up the posts are the caller's"""
    rr = random.Random(seed)
    n = max(5, int(sx * sy * 3.2))
    for k in range(n):
        if rr.random() > cover:
            continue
        x = cx + rr.uniform(-0.5, 0.5) * sx
        y = cy + rr.uniform(-0.5, 0.5) * sy
        s = rr.uniform(0.55, 1.05)
        lump("leaf", (x, y, z + rr.uniform(-0.04, 0.1)), (s * rr.uniform(1.0, 1.4), s, rr.uniform(0.18, 0.34)),
             rr.randrange(9999), n=10, rings=3, rough=0.38)
    for k in range(int(sx / 0.7)):   # bunches hanging over the front edge
        if rr.random() > droop:
            continue
        x = cx - sx / 2 + (k + 0.5) * sx / int(sx / 0.7)
        lump("leaf", (x, cy - sy / 2 + rr.uniform(-0.1, 0.15), z - rr.uniform(0.35, 0.6)),
             (rr.uniform(0.4, 0.7), rr.uniform(0.3, 0.45), rr.uniform(0.4, 0.65)), rr.randrange(9999), n=7, rings=3,
             rough=0.25)


def vine_stem(x, y, z1, seed):
    """Old grapevine stem twisting up a post to the trellis"""
    rr = random.Random(seed)
    p = Vector((x + 0.12, y - 0.08, 0.0))
    n = 5
    for k in range(n):
        q = Vector((x + 0.12 * math.cos(k * 1.7), y - 0.12 * math.sin(k * 1.7), z1 * (k + 1) / n))
        q.x += rr.uniform(-0.04, 0.04)
        log("wood", p, q, 0.05 - 0.006 * k, 5)
        p = q


def trellis(x0, x1, y0, y1, z, seed, posts_n=3, cover=0.75):
    """Free grapevine trellis: posts on both long sides, a beam on each, thin poles across, vine foliage on top"""
    for y in (y0, y1):
        for k in range(posts_n):
            x = x0 + (x1 - x0) * k / (posts_n - 1)
            log("wood", (x, y, -0.2), (x, y, z), 0.075, 6)
        log("wood", (x0 - 0.2, y, z + 0.05), (x1 + 0.2, y, z + 0.05), 0.08, 6)
    m = max(4, int((x1 - x0) / 0.45))
    for k in range(m):
        x = x0 + (x1 - x0) * (k + 0.5) / m
        log("wood", (x, y0 - 0.25, z + 0.16), (x, y1 + 0.25, z + 0.16), 0.035, 4)
    vine_stem(x0, y0, z, seed)
    vine_stem(x1, y1, z, seed + 1)
    foliage((x0 + x1) / 2, (y0 + y1) / 2, z + 0.22, x1 - x0 + 0.4, y1 - y0 + 0.4, seed, cover)


def tandoor(c):
    """Clay bread oven on a mud plinth"""
    x, y = c
    bbox("plaster", x - 0.6, y - 0.6, -0.3, x + 0.6, y + 0.6, 0.35, bevel=0.06)
    prof = [(0.0, 0.0), (0.0, 0.42), (0.55, 0.44), (0.85, 0.32), (0.86, 0.0)]
    H.emit(H.lathe(prof, seg=10), "clay", H.T(x, y, 0.35) @ H.RY(-math.pi / 2))
    face("dark", [(x - 0.17, y - 0.17, 1.215), (x + 0.17, y - 0.17, 1.215), (x + 0.17, y + 0.17, 1.215),
                  (x - 0.17, y + 0.17, 1.215)], (0, 0, 1))


# ------------------------------------------------------------------ the models
def oh_a():
    """Ayvan house: two rooms behind a deep porch on three carved posts across most of the front, a clay platform
    with a rug in its shade, a grapevine trellis over the rest of the front; hay, firewood and a stovepipe on the
    roof, a rug over the back parapet"""
    W, D = 7.6, 6.2
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    yb = y0 + 2.3   # the rooms' front wall
    g = V.Block(x0, yb, x1, y1, -0.3, 3.0, ph=0.38)
    g.ops[0] = [("door", 1.5, 0.95, 0.0, 1.9), ("window", 3.1, 0.55, 1.1, 0.65), ("door_open", 4.4, 0.9, 0.0, 1.85),
                ("window", 6.4, 0.5, 1.1, 0.65)]
    g.ops[1] = [("window", 2.0, 0.45, 1.2, 0.55)]
    g.ops[3] = [("window", 1.9, 0.45, 1.2, 0.55)]
    g.vents(2, 2.45, 6)
    g.build(vigas=(2,), spouts=2)
    side = V.Block(x0, y0 + 0.05, x0 + 0.75, yb + 0.02, -0.3, 2.95, ph=0.3, bat=0.06)   # the porch's end wall
    side.build(vigas=(), spouts=0)
    ax1 = x0 + 5.0
    ayvan(x0 + 0.7, ax1, y0 + 0.05, yb + 0.05, 2.75, 3)
    platform(x0 + 0.85, yb - 1.55, x0 + 3.3, yb - 0.05, rug="rug_r")
    V.jug((x0 + 3.7, yb - 0.4, 0.0), 0.5)
    V.jug((x0 + 4.05, yb - 0.3, 0.0), 0.42)
    trellis(ax1 + 0.35, x1 - 0.25, y0 + 0.25, yb - 0.25, 2.35, 7, posts_n=2)
    foliage(x0 + 3.0, y0 + 1.1, 3.35, 2.6, 1.8, 17, cover=0.5, droop=0.8)   # the vine reaching over the porch roof
    V.hay((x0 + 2.0, y1 - 1.3, 3.0), (1.6, 1.2, 0.65), 61)
    V.firewood((x1 - 1.3, y1 - 1.2, 3.0), 0.0, 63, n=8)
    V.stovepipe((x0 + 4.4, y1 - 0.9, 3.0), 0.75)
    V.hatch((x0 + 4.0, yb + 1.3, 3.0), 0.7)
    V.rug_over(g.P(2, 3.0, g.ztop), (0, 1), 1.3, 0.6, cls="rug_b")


def oh_b():
    """L-shaped house round a corner ayvan on two posts: a long back wing and a lower front room on the left,
    a mud stair up the right side to the roof, a bread oven and jugs in front, hay and drying rugs on the roofs"""
    W, D = 7.4, 6.6
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    yb = y0 + 3.4
    a = V.Block(x0, yb, x1 - 0.95, y1, -0.3, 3.05, ph=0.4)
    a.ops[0] = [("window", 3.0, 0.5, 1.15, 0.6), ("door", 4.3, 0.95, 0.0, 1.9), ("window", 5.6, 0.5, 1.15, 0.6)]
    a.ops[2] = [("window", 2.2, 0.45, 1.2, 0.55)]
    a.vents(2, 2.5, 5)
    a.build(vigas=(2,), spouts=2)
    b = V.Block(x0, y0 + 0.2, x0 + 2.5, yb + 0.02, -0.3, 2.75, ph=0.0, bat=0.08)
    b.ops[0] = [("door", 1.2, 0.9, 0.0, 1.85)]
    b.ops[1] = [("window", 1.6, 0.5, 1.1, 0.6)]
    b.ops[3] = [("vent", 1.6, 0.16, 2.2, 0.16)]
    b.build(vigas=(0, 3), viga_z=2.6, spouts=1)
    ayvan(x0 + 2.45, x1 - 0.95, yb - 1.9, yb + 0.05, 2.7, 2)
    platform(x0 + 2.65, yb - 1.4, x0 + 4.6, yb - 0.05, rug="rug_b")
    V.stair(x1 - 0.48, y0 + 0.5, yb + 0.6, 3.05, width=0.9)
    bbox("plaster", x1 - 0.95, yb + 0.55, -0.3, x1, y1, 3.05, bevel=0.05)   # landing
    tandoor((x0 + 3.9, y0 + 0.75))
    V.jug((x0 + 5.0, y0 + 1.0, 0.0), 0.5)
    V.hay((x0 + 1.25, y0 + 1.6, 2.75), (1.4, 1.3, 0.6), 71)
    V.rug_flat((x0 + 3.6, y1 - 1.4, 3.05), (1.9, 1.2), 0.15, "rug_r")
    V.firewood((x0 + 5.5, y1 - 1.0, 3.05), 1.57, 73, n=7)
    V.chimney((x0 + 0.8, y1 - 0.7, 3.05), 0.55)
    foliage(x0 + 4.0, yb - 1.3, 3.25, 2.4, 1.4, 77, cover=0.55, droop=0.9)   # vine over the corner porch


def oh_c():
    """Long low house: an ayvan on four posts along the whole front, its roof half buried under a grapevine that
    climbs two posts, a long clay platform with rugs, firewood stacked at one end; hay and a hatch on the roof"""
    W, D = 8.4, 5.6
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    yb = y0 + 2.2
    m = V.Block(x0, yb, x1, y1, -0.3, 3.05, ph=0.36)
    m.ops[0] = [("window", 1.3, 0.5, 1.1, 0.65), ("door", 2.8, 0.95, 0.0, 1.9), ("window", 4.4, 0.55, 1.1, 0.65),
                ("door_open", 5.9, 0.9, 0.0, 1.85), ("window", 7.3, 0.5, 1.1, 0.65)]
    m.ops[1] = [("window", 1.7, 0.45, 1.2, 0.55)]
    m.vents(2, 2.5, 7)
    m.build(vigas=(2,), spouts=2)
    bbox("stone", x0 + 0.05, y0 + 0.05, -0.3, x1 - 0.05, yb + 0.05, 0.16, bevel=0.04)   # porch floor
    ayvan(x0 + 0.1, x1 - 0.1, y0 + 0.05, yb + 0.05, 2.8, 4)
    platform(x0 + 0.5, yb - 1.45, x0 + 4.2, yb - 0.1, rug="rug_r")
    vine_stem(x0 + 0.45, y0 + 0.35, 2.8, 81)
    vine_stem(x1 - 0.45, y0 + 0.35, 2.8, 82)
    foliage(x0 + 2.4, y0 + 1.0, 3.45, 4.2, 1.9, 83, cover=0.7, droop=0.9)
    foliage(x1 - 1.6, y0 + 0.9, 3.45, 2.6, 1.5, 84, cover=0.6, droop=0.9)
    V.firewood((x1 - 1.0, yb - 0.7, 0.16), 1.57, 85, n=9)
    V.jug((x0 + 4.7, yb - 0.5, 0.16), 0.48)
    V.hay((x0 + 2.0, y1 - 1.2, 3.05), (1.6, 1.3, 0.7), 87)
    V.hatch((x1 - 2.6, y1 - 1.5, 3.05), 0.7)
    V.chimney((x1 - 1.0, y1 - 0.7, 3.05), 0.5)
    V.rug_over(m.P(2, 5.0, m.ztop), (0, 1), 1.4, 0.8, cls="rug_b")


def oh_d():
    """Two-storey farmhouse: rooms below, an upper room and an open summer ayvan beside it on the roof (posts,
    a mud roof, a low railing), a small porch on two posts over the door below and a ladder up; vine on the
    ground porch, rugs and jugs on the roof terrace"""
    W, D = 7.0, 6.4
    x0, y0, x1, y1 = -W / 2, -D / 2, W / 2, D / 2
    yb = y0 + 1.7
    g = V.Block(x0, yb, x1, y1, -0.3, 3.0, ph=0.0, bat=0.08)
    g.ops[0] = [("window", 1.0, 0.5, 1.1, 0.6), ("door", 3.0, 0.95, 0.0, 1.9), ("window", 5.4, 0.55, 1.1, 0.65)]
    g.ops[1] = [("window", 2.4, 0.5, 1.2, 0.6)]
    g.ops[3] = [("window", 2.0, 0.45, 1.2, 0.55)]
    g.build(vigas=(), spouts=1)
    u = V.Block(x0 + 0.1, yb + 1.3, x0 + 3.9, y1 - 0.1, 3.0, 5.5, ph=0.36, bat=0.06)
    u.ops[0] = [("door_open", 1.0, 0.85, 3.0, 1.8), ("window", 2.6, 0.5, 3.9, 0.6)]
    u.ops[3] = [("window", 1.8, 0.45, 3.9, 0.55)]
    u.ops[2] = [("window", 2.0, 0.45, 3.9, 0.55)]
    u.build(vigas=(0, 2), spouts=2)
    with H.xf(H.T(0, 0, 3.0)):   # the summer ayvan on the roof, beside the upper room
        for (x, y) in ((x1 - 0.35, yb + 1.6), (x1 - 0.35, y1 - 0.4), (x0 + 4.2, yb + 1.6)):
            carved_post(x, y, 0.0, 2.35, r=0.09)
        V.canopy(x0 + 3.85, x1 - 0.1, yb + 1.3, y1 - 0.1, 2.35)
        V.railing(x0 + 3.95, x1 - 0.2, yb + 1.25, 0.0, h=0.7)
        platform(x0 + 4.3, yb + 2.0, x1 - 0.4, y1 - 0.5, h=0.25, rug="rug_b")
    ayvan(x0 + 1.9, x0 + 4.4, y0 + 0.05, yb + 0.05, 2.6, 2)
    vine_stem(x0 + 2.25, y0 + 0.35, 2.6, 91)
    foliage(x0 + 3.1, y0 + 0.95, 3.25, 2.4, 1.5, 92, cover=0.75, droop=0.9)
    V.ladder((x0 + 0.9, y0 + 0.6, 0.0), (x0 + 0.9, yb + 0.1, 3.3))
    V.jug((x0 + 1.5, yb - 0.4, 0.0), 0.5)
    V.rug_flat((x1 - 1.5, yb + 0.6, 3.0), (1.8, 1.0), 0.05, "rug_r")
    V.jug((x0 + 4.4, yb + 0.6, 3.0), 0.42)
    V.stovepipe((x0 + 1.2, y1 - 0.9, 5.5), 0.7)
    V.hay((x0 + 2.0, yb + 0.6, 3.0), (1.3, 0.9, 0.5), 93)


def oh_cistern():
    """Covered cistern: a mud-brick dome on a low drum over a sunken tank, a vent lantern on the crown, a portal
    with a deep arched recess where steps go down to the water, a trough and jugs by the door; its foot dark and
    damp, mud brick showing where the plaster fell"""
    R0 = 2.45
    prof = [(-0.3, R0), (1.05, R0), (1.12, R0 + 0.1), (1.24, R0 + 0.1), (1.3, R0 - 0.08)]
    for k in range(1, 7):   # the dome: a slightly pointed profile up to the lantern's ring
        a = k / 8.0 * math.pi / 2
        prof.append((1.3 + 2.0 * math.sin(a) ** 0.9, (R0 - 0.08) * math.cos(a) ** 1.15))
    prof.append((3.25, 0.42))
    H.emit(H.lathe(prof, seg=28, cap0=False, cap1=True), "plaster", H.RY(-math.pi / 2))
    ztop = prof[-1][0]
    log("plaster", (0, 0, ztop - 0.05), (0, 0, ztop + 0.38), 0.4, 10)   # the vent lantern
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        face("dark", [(math.cos(a) * 0.405 - math.sin(a) * 0.1, math.sin(a) * 0.405 + math.cos(a) * 0.1, ztop + 0.08),
                      (math.cos(a) * 0.405 + math.sin(a) * 0.1, math.sin(a) * 0.405 - math.cos(a) * 0.1, ztop + 0.08),
                      (math.cos(a) * 0.405 + math.sin(a) * 0.1, math.sin(a) * 0.405 - math.cos(a) * 0.1, ztop + 0.3),
                      (math.cos(a) * 0.405 - math.sin(a) * 0.1, math.sin(a) * 0.405 + math.cos(a) * 0.1, ztop + 0.3)],
             (math.cos(a), math.sin(a), 0))
    H.emit(H.lathe([(0.0, 0.46), (0.12, 0.46), (0.2, 0.0)], seg=10), "plaster", H.T(0, 0, ztop + 0.38) @ H.RY(-math.pi / 2))
    p = V.Block(-1.2, -R0 - 1.0, 1.2, -R0 + 0.9, -0.3, 2.35, ph=0.0, bat=0.08)   # the portal, a rounded top
    p.ops[0] = [("arch", 1.2, 1.2, 0.0, 1.85)]
    p.build(vigas=(), spouts=0)
    yr = -R0 - 0.1   # the recess's back wall: a dark doorway where the steps go down to the tank
    face("dark", [(-0.42, yr - 0.02, 0.0), (0.42, yr - 0.02, 0.0), (0.42, yr - 0.02, 1.55), (-0.42, yr - 0.02, 1.55)],
         (0, -1, 0))
    for k in range(3):   # worn stone steps in the recess, the lowest at the door
        bbox("stone", -0.62, yr - 0.9 + k * 0.28, -0.3, 0.62, yr - 0.62 + k * 0.28, 0.12 - k * 0.04, bevel=0.03)
    bbox("stone", -2.3, -R0 - 1.45, -0.3, -1.35, -R0 - 0.65, 0.42, bevel=0.04)   # stone trough by the door
    face("dark", [(-2.18, -R0 - 1.33, 0.425), (-1.47, -R0 - 1.33, 0.425), (-1.47, -R0 - 0.77, 0.425),
                  (-2.18, -R0 - 0.77, 0.425)], (0, 0, 1))
    V.jug((1.6, -R0 - 0.9, 0.0), 0.55)
    V.jug((1.95, -R0 - 0.65, 0.0), 0.45)
    V.jug((1.75, -R0 - 0.35, 0.0), 0.5)
    for k in range(5):   # rows of buttress-like mud pads round the drum, where it was patched
        a = -math.pi / 2 + (k + 1) * 2 * math.pi / 6
        box("plaster", (math.cos(a) * (R0 + 0.12), math.sin(a) * (R0 + 0.12), 0.35), (0.5, 0.6, 1.3), a, bevel=0.08)


def oh_pergola():
    """Free-standing grapevine pergola over a clay platform: six posts, beams and poles, a thick vine canopy with
    bunches hanging, rugs, a low table and jugs on the platform"""
    x0, x1, y0, y1 = -2.2, 2.2, -1.6, 1.6
    platform(x0 + 0.35, y0 + 0.35, x1 - 0.35, y1 - 0.35, h=0.42, rug="rug_r")
    bbox("wood", -0.45, -0.3, 0.42, 0.45, 0.3, 0.68, bevel=0.03)   # low table
    V.jug((x1 - 0.1, y0 + 0.05, 0.0), 0.5)
    V.jug((x1 + 0.05, y0 + 0.4, 0.0), 0.42)
    trellis(x0, x1, y0, y1, 2.45, 101, posts_n=3, cover=0.85)
    V.rug_flat((0.0, 0.7, 0.42), (2.0, 0.8), 0.02, "rug_b")


MODELS = {"oh_a": oh_a, "oh_b": oh_b, "oh_c": oh_c, "oh_d": oh_d, "oh_cistern": oh_cistern, "oh_pergola": oh_pergola}
TINTS = {   # mud plaster tone per model (sRGB): a little warmer and redder than the kishlak's dust-grey highland mud
    "oh_a": (0.7, 0.55, 0.39), "oh_b": (0.66, 0.51, 0.36), "oh_c": (0.72, 0.58, 0.42), "oh_d": (0.67, 0.53, 0.38),
    "oh_cistern": (0.64, 0.5, 0.36), "oh_pergola": (0.68, 0.54, 0.38)}
DAMP = {"oh_cistern": 1.0}   # by the pond: a taller, darker damp foot


def make_layers(ob, tint, seed, damp=0.0):
    """village_adobe.make_layers plus the vine foliage (mottled leaves, yellowing patches, dark gaps between the
    mounds from AO, dust on top) and, with damp, a darker wet foot rising higher up the walls"""
    base = V.make_layers(ob, tint, seed, loss=1.0)

    def layers(P, N, B, AO, part, S):
        col, rough, metal, nn = base(P, N, B, AO, part, S)
        Pm = P * V.BAKE_SCALE
        leaf = part == LEAF
        if leaf.any():
            n1 = TP.fbm(Pm, 7.0, seed + 50, 3)
            n2 = TP.fbm(Pm, 1.2, seed + 51, 3)
            g = np.array([0.24, 0.31, 0.13], np.float32) * (0.62 + 0.75 * n1)[:, None]
            yel = TP.sstep(0.58, 0.72, n2)
            g = g * (1 - 0.45 * yel[:, None]) + np.array([0.46, 0.43, 0.2], np.float32) * (0.45 * yel)[:, None]
            g = g * (0.35 + 0.65 * AO ** 1.2)[:, None]
            upf = np.clip(N[:, 2], 0, 1)
            g = g * (1 - 0.12 * upf[:, None]) + np.array([0.5, 0.46, 0.36], np.float32) * (0.12 * upf)[:, None]
            col = np.where(leaf[:, None], g, col)
            rough = np.where(leaf, 0.88 + 0.08 * n1, rough).astype(np.float32)
        if damp > 0.0:
            z = Pm[:, 2] / V.BAKE_SCALE
            wall = np.abs(N[:, 2]) < 0.5
            wet = (1.0 - TP.sstep(0.0, 0.9 + 0.5 * TP.fbm(Pm, 1.0, seed + 60, 3), z)) * damp * (part != LEAF)
            wet = wet * (0.6 + 0.4 * wall)
            col = col * (1 - 0.35 * wet[:, None])
            rough = np.clip(rough - 0.08 * wet, 0.7, 1.0).astype(np.float32)
        return col, rough, metal, nn

    return layers


def build(name, out, size):
    """Model one piece, bake its weathered atlas and export <name>.glb; returns (size, triangles, base z)"""
    H.reset(True)
    V.R.seed(zlib.crc32(name.encode()) & 0xFFFF)   # stable across runs (str hash() is salted per process)
    MODELS[name]()
    ob = V.assemble(name)
    me = ob.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mn, mx = co.min(0), co.max(0)
    c = (mn + mx) / 2
    co[:, 0] -= c[0]
    co[:, 1] -= c[1]
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    dims, zmin = mx - mn, mn[2]
    # hay, jugs and leaves round; the cistern's dome too (curved plaster faces above the drum)
    smooth = [me.materials[p.material_index].name[3:] in ("straw", "clay", "leaf")
              or (name == "oh_cistern" and p.center.z > 1.2 and 0.05 < abs(p.normal.z) < 0.995
                  and me.materials[p.material_index].name[3:] == "plaster") for p in me.polygons]
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    seed = (sum(map(ord, name)) * 7) % 1000
    pal = {"own": True, "seed": seed, "part": V.part_of,
           "layers": make_layers(ob, TINTS[name], seed, DAMP.get(name, 0.0))}
    TP.bake_set([ob], pal, size, "adobe_" + name, scale=V.BAKE_SCALE)
    for p, sm in zip(me.polygons, smooth):   # hay, jugs and leaves round, the rest flat
        p.use_smooth = sm
    path = os.path.join(out, "%s.glb" % name)
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
    names = [n for n in MODELS if not a.only or n in a.only.split(",")]
    os.makedirs(a.out, exist_ok=True)
    rows = []
    for n in names:
        dims, tris, zmin = build(n, a.out, a.size)
        print("OASIS %s size %.2f x %.2f x %.2f (base %.2f) tris %d" % (n, dims[0], dims[1], dims[2], zmin, tris))
        rows.append('\t["%s", Vector3(%.2f, %.2f, %.2f)],   # %d tris' % (n, dims[0], dims[2] + zmin, dims[1], tris))
    print("\n".join(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
