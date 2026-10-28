"""Burnt-out vehicle hulks for the Highland roads (weak-models list, Kanta 28.10.2026: replace the Meshy wrecks
b08_wreck_tank and b07_wreck_truck, which were faceted low-poly with a smeared texture and no tracks). Fictional
vehicles "inspired by" mid-century hardware, no real names, markings or insignia (CLAUDE.md hard rule 1).

tank  — a welded medium tank knocked out on the road: hull with a sloped glacis and sponsons over the tracks,
        five road wheels, a drive sprocket with teeth, an idler and return rollers on each side, tracks of single
        links (the left track is broken: its top run droops off the wheels and lies on the ground, a few links
        are thrown, the front road wheel lies against the hull); the turret is blown off its ring, sits askew
        and tilted with the gun traversed to the rear and drooping over the engine deck; hatches open, the
        engine hatch blown off and hanging, torn and bent fenders, exhausts, a stowage box, spare links.
truck — a three-axle cargo truck burnt out: bare wheel rims (the tyres burnt off, wire rings left), one rear
        wheel gone; a bent chassis (the rear sags behind the cab), the cab with empty window frames, a dented
        roof, one door gone and the other hanging open, seat frames and the steering wheel inside; the engine
        bay open, the grille and a bumper bent down, torn mudguards; the cargo bed collapsed (floor broken and
        tilted to the ground, a side board hanging, the other fallen on the ground, canopy bows bent and fallen,
        charred crates).
Both carry drifted sand and dust baked into the texture, heaviest at the foot of the hull and wheels (separate
sand mounds were tried: lit, they read as pale flaps against the varied Highland ground).

Surfaces: each face gets a class (paint, bare steel, track, rubber, wood, interior dark) with a flat colour.
turret_paint.bake_set (own-colour mode, as village_adobe.py) unwraps the hulk into one 1024 atlas and bakes the
surface data; this file's layers turn it into a burnt hulk (no flat paint, Kanta 26.10): the paint survives low
down and at the far end from the fire as faded, blistered paint; towards the fire (engine deck, cab, cargo bed,
turret ring) it scorches through a dark ring to rust-brown burnt metal and grey-white ash oxide; soot plumes
above the openings, rust runs down the walls, sand and ash dust on what faces up, drifted sand at the foot,
charred and cracked wood, burnt-off rubber, rusty track links worn bright only where they touched the road;
roughness 0.82–1.0 (matte), a relief normal map (rust pitting, paint blisters, wood char cracks).
One mesh, one material: one draw call per kind in a terrain chunk, as before.

Units: built in metres (+X forward, +Z up), then normalised like every biome model (tools/model_lab/biome_prep.py):
standing on z = 0, centred, the largest size in plan = 1 (the game scales it to KINDS width in px, length along
the road, biome_props.gd _add_vehicle).

Run (repo root; bpy 5.2 pip module, numpy, Pillow; no network; ~2 min per hulk on 4 cores):
  python3 game/tools/blender/vehicle_wreck.py [--out=game/models/biome] [--only=tank,truck] [--size=1024]
  -> <out>/b08_wreck_tank.glb, <out>/b07_wreck_truck.glb; Godot's import extracts the textures next to them
     (b08_wreck_tank_wreck_tank_{albedo,orm,normal}.jpg).
"""
import argparse
import itertools
import math
import os
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: I001  (bpy first: it makes bmesh and mathutils importable)
import bmesh
import numpy as np
from mathutils import Matrix, Vector

import hq_lib as H
import turret_paint as TP

GAME = Path(__file__).resolve().parents[2]
BAKE_SCALE = 5.0   # turret_paint units per metre: bevel radius 3 cm, AO reach 0.7 m

# class -> flat sRGB colour. Order = surface id in the bake.
CLASSES = {
    "paint": (0.4, 0.39, 0.3),      # the hull paint (each vehicle sets its own, see PAINT)
    "steel": (0.3, 0.27, 0.24),     # bare or burnt steel: interior walls, rims, frames, exhausts
    "track": (0.27, 0.23, 0.2),     # cast track links and sprocket teeth
    "rubber": (0.09, 0.09, 0.09),   # what is left of the road-wheel tyres
    "wood": (0.22, 0.18, 0.14),     # cargo bed planks, crates (charred)
    "dark": (0.05, 0.045, 0.04),    # the burnt-out inside seen through openings
}
CID = {k: i for i, k in enumerate(CLASSES)}
PAINT, STEEL, TRACK, RUBBER, WOOD, DARK = range(len(CLASSES))
PAINT_RGB = {"tank": (0.32, 0.32, 0.25), "truck": (0.42, 0.39, 0.29)}   # olive-grey hull, faded khaki truck

R = random.Random(1)


# ------------------------------------------------------------------ geometry
def M(x=0.0, y=0.0, z=0.0, rz=0.0, ry=0.0, rx=0.0):
    """Placement matrix: move to (x, y, z), turn rz about Z, then ry about Y, then rx about X (radians)"""
    return H.T(x, y, z) @ H.RZ(rz) @ H.RY(ry) @ H.RX(rx)


def box(cls, c, s, rz=0.0, ry=0.0, rx=0.0, bevel=0.0):
    """Box of size s centred on c, turned rz, ry, rx"""
    H.emit(H.box(s, bevel=bevel, segs=1), cls, M(*c, rz, ry, rx))


def cyl_y(cls, c, r, w, seg=12, rz=0.0, rx=0.0):
    """Cylinder of radius r and width w with its axis along Y (a wheel), centred on c"""
    H.emit(H.cyl(r, w, seg), cls, M(*c, rz, 0.0, rx) @ H.RZ(math.pi / 2))


def rod(cls, p0, p1, r, seg=6):
    """Round bar from p0 to p1"""
    d = Vector(p1) - Vector(p0)
    H.emit(H.cyl(r, d.length, seg), cls, H.T(*((Vector(p0) + Vector(p1)) / 2)) @ H.AX(d))


def prism(cls, outline, width, Mx):
    """Side profile [(x, z)] extruded across Y (width, centred), placed by Mx"""
    H.emit(H.prism(outline, width), cls, Mx)


def loft(cls, rings, Mx=None, caps=(True, True)):
    """Solid between closed rings of equal point counts [(x, y, z)], bottom ring first"""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for a, b in itertools.pairwise(vs):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    if caps[0]:
        bm.faces.new(list(reversed(vs[0])))
    if caps[1]:
        bm.faces.new(vs[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    H.emit(bm, cls, Mx if Mx is not None else Matrix.Identity(4))


def plate(cls, pts, thick=0.03):
    """Flat plate through the points pts (a polygon, any outline: torn edges) with a thickness"""
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    bm.normal_update()
    n = f.normal.copy()
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co += n * thick
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    H.emit(bm, cls)


def torn(p0, p1, n, amp, rng, normal):
    """Points from p0 to p1 with a ragged edge: offsets of up to amp along `normal` (a torn sheet's edge)"""
    p0, p1, nv = Vector(p0), Vector(p1), Vector(normal)
    out = []
    for i in range(n + 1):
        t = i / n
        k = 0.0 if i in (0, n) else rng.uniform(-amp, amp)
        out.append(p0.lerp(p1, t) + nv * k)
    return out


def resample(pts, step):
    """Points every `step` metres along the polyline pts (with the tangent at each)"""
    pts = [Vector(p) for p in pts]
    out = []
    acc = 0.0
    for a, b in itertools.pairwise(pts):
        seg = (b - a).length
        if seg < 1e-6:
            continue
        d = (b - a) / seg
        while acc <= seg:
            out.append((a + d * acc, d))
            acc += step
        acc -= seg
    return out


def chain(cls, pts, centre=None, step=0.17, size=(0.15, 0.5, 0.05), horn=True):
    """Track links along the polyline pts: each a plate size (along, across, thick) laid along the path, its
    outer face away from `centre` (x, z) of a track loop, or facing up for a track lying loose; every other link
    has a guide horn on its inner face"""
    for i, (p, d) in enumerate(resample(pts, step)):
        if centre is not None:
            o = Vector((p.x - centre[0], 0.0, p.z - centre[1]))
        else:
            o = Vector((0.0, 0.0, 1.0))
        o = (o - d * o.dot(d)).normalized()
        if o.length < 0.5:
            o = Vector((0.0, 0.0, 1.0))
        rot = Matrix((d, o.cross(d), o)).transposed().to_4x4()
        H.emit(H.box(size), cls, H.T(*p) @ rot)
        if horn and i % 2 == 0:   # guide horns on the inner face
            H.emit(H.box((0.05, 0.05, 0.08)), cls, H.T(*(p - o * 0.05)) @ rot)


def arc(c, r, a0, a1, n):
    """Points on a circle in the XZ plane round c (x, z) from angle a0 to a1 (radians, 0 = +X, π/2 = up)"""
    return [(c[0] + math.cos(a0 + (a1 - a0) * i / n) * r, c[1] + math.sin(a0 + (a1 - a0) * i / n) * r)
            for i in range(n + 1)]


def sprocket(c, r, w, teeth=12):
    """Drive sprocket with its axis along Y at c: hub disc and a ring of teeth"""
    cyl_y("steel", c, r * 0.8, w * 0.7, 14)
    cyl_y("steel", c, r * 0.35, w * 1.05, 8)
    for k in range(teeth):
        a = math.tau * k / teeth
        box("track", (c[0] + math.cos(a) * r * 0.9, c[1], c[2] + math.sin(a) * r * 0.9), (0.08, w * 0.6, 0.1),
            ry=-a)


def road_wheel(c, r, w, burnt=0.5, seg=14):
    """Road wheel with its axis along Y at c: steel disc, what is left of the rubber tyre, hub"""
    cyl_y("rubber" if burnt < 0.8 else "steel", c, r, w, seg)
    cyl_y("steel", (c[0], c[1] + math.copysign(0.02, c[1]), c[2]), r * 0.78, w * 1.1, seg)
    cyl_y("steel", (c[0], c[1] + math.copysign(0.05, c[1]), c[2]), r * 0.25, w * 1.2, 8)


# ------------------------------------------------------------------ tank
def tank():
    """The knocked-out medium tank (see the module docstring); returns the fire sources for the burn layer"""
    rng = random.Random(8)
    # lower hull between the tracks and the upper hull with sponsons over them
    prism("paint", [(-3.0, 0.5), (2.5, 0.5), (3.12, 0.98), (3.12, 1.08), (-3.05, 1.08)], 2.2, M())
    prism("paint", [(-3.08, 1.08), (3.12, 1.08), (2.12, 1.72), (-2.95, 1.72), (-3.1, 1.45)], 3.08, M())
    # glacis details: spare track links, headlight guards, tow hooks, bow gun ball, driver hatch open
    for k in range(4):
        box("track", (2.58 - k * 0.0, -0.75 + k * 0.17, 1.42 - k * 0.0), (0.15, 0.45, 0.05), ry=-0.57, rz=math.pi / 2)
    for sy in (-1, 1):
        box("steel", (2.95, sy * 1.25, 1.18), (0.14, 0.2, 0.16))
        box("steel", (3.18, sy * 0.75, 0.82), (0.16, 0.08, 0.14))
    H.emit(H.sphere(0.16, 10), "paint", M(2.62, 0.75, 1.38))
    box("dark", (2.35, -0.55, 1.61), (0.5, 0.55, 0.06), ry=-0.57)                      # driver hatch opening
    plate("paint", [(2.05, -0.82, 1.78), (2.05, -0.28, 1.78), (2.0, -0.28, 2.28), (2.0, -0.82, 2.28)], 0.05)
    # engine deck: grille slats, the access hatch blown off and hanging over the side, exhausts, stowage box
    for k in range(9):
        box("steel", (-2.6 + k * 0.17, 0.35, 1.74), (0.07, 1.3, 0.04))
    box("dark", (-1.7, -0.8, 1.725), (0.95, 0.75, 0.02))                                # the hatch's hole
    plate("paint", [(-2.2, -1.56, 1.72), (-1.2, -1.56, 1.72), (-1.25, -1.62, 1.0), (-2.15, -1.62, 0.98)], 0.04)
    for sy in (-1, 1):
        rod("steel", (-3.2, sy * 0.55, 1.25), (-3.2, sy * 1.0, 1.25), 0.11, 10)
        box("steel", (-3.13, sy * 0.78, 1.25), (0.06, 0.55, 0.3))
    box("paint", (-1.0, 1.42, 1.88), (1.1, 0.3, 0.32), rz=0.03, rx=0.12)                 # stowage box, burst
    box("dark", (-1.0, 1.42, 2.04), (1.0, 0.24, 0.02), rz=0.03, rx=0.12)
    # running gear on both sides
    for sy in (-1, 1):
        y = sy * 1.36
        left = sy > 0   # the broken side
        wheels = [-2.2, -1.1, 0.0, 1.1, 2.2]
        for i, x in enumerate(wheels):
            if left and i == 4:
                continue    # this one lies against the hull (below)
            road_wheel((x, y, 0.42), 0.36, 0.42, burnt=rng.random())
        sprocket((-2.82, y, 0.74), 0.34, 0.42)
        cyl_y("steel", (2.92, y, 0.7), 0.3, 0.38, 14)
        cyl_y("steel", (2.92, y + sy * 0.03, 0.7), 0.12, 0.44, 8)
        for x in (-1.25, 0.0, 1.25):
            cyl_y("steel", (x, y, 1.1), 0.09, 0.35, 8)
        # suspension arms and bump stops
        for x in wheels:
            box("steel", (x + 0.25, sy * 1.12, 0.62), (0.55, 0.12, 0.12), ry=0.45)
        # the track loop: bottom run, round the idler, top run over the return rollers, round the sprocket
        lz = 0.03
        loop = [(-2.35, lz), (2.35, lz)]
        loop += arc((2.92, 0.7), 0.36, -math.pi / 2 - 0.55, math.pi / 2, 7)[0:]
        loop += [(1.25, 1.21), (0.0, 1.19), (-1.25, 1.21)]
        loop += arc((-2.82, 0.74), 0.38, math.pi / 2, math.pi * 1.5 - 0.55, 7)
        loop += [(-2.35, lz)]
        pts = [(x, y, z) for x, z in loop]
        if not left:
            chain("track", pts, (0.0, 0.62))
        else:
            # broken: the bottom run stops short of the idler, the top run stops over the middle roller;
            # the loose end hangs off the wheels and lies on the ground beside them
            chain("track", [(-2.35, y, lz), (1.55, y, lz)], (0.0, 0.62))
            back = [(x, y, z) for x, z in [(0.2, 1.19), (-1.25, 1.21)]]
            back += [(x, y, z) for x, z in arc((-2.82, 0.74), 0.38, math.pi / 2, math.pi * 1.5 - 0.55, 7)]
            back += [(-2.35, y, lz)]
            chain("track", back, (0.0, 0.62))
            hang = [(0.2, y, 1.19), (0.75, y + 0.14, 1.0), (1.2, y + 0.3, 0.45), (1.55, y + 0.4, 0.05),
                    (2.3, y + 0.42, 0.03), (3.0, y + 0.3, 0.03), (3.35, y + 0.08, 0.03)]
            chain("track", hang, None)
            for k in range(5):   # thrown links
                x = 1.8 + rng.uniform(-0.3, 1.4)
                box("track", (x, y + 0.55 + rng.uniform(-0.1, 0.1), 0.03), (0.15, 0.5, 0.05), rz=rng.uniform(-1.2, 1.2))
            # the knocked-off front road wheel leans on the hull, the idler stands bare
            road_wheel((2.1, y + 0.4, 0.37), 0.36, 0.42, burnt=0.9)
    # fenders: right front bent up and torn, left front gone (torn stub), rear right crumpled down
    plate("paint", torn((2.55, -1.62, 1.1), (3.4, -1.62, 1.38), 5, 0.06, rng, (0, 0, 1))
          + [(3.38, -1.08, 1.4), (2.55, -1.1, 1.1)], 0.025)
    plate("paint", [(2.45, 1.1, 1.09), (2.75, 1.1, 1.1)] + torn((2.75, 1.62, 1.12), (2.45, 1.62, 1.08), 4, 0.07, rng,
                                                                (1, 0, 0)), 0.025)
    plate("paint", [(-3.1, -1.1, 1.1), (-3.1, -1.62, 1.1), (-3.45, -1.62, 0.78), (-3.42, -1.1, 0.8)], 0.025)
    # the turret, blown off its ring: shifted, tilted, gun to the rear and drooping
    box("dark", (-0.25, 0.0, 1.73), (1.9, 1.9, 0.02))                                   # the open ring
    with H.xf(M(-0.32, 0.22, 1.83, rz=math.radians(168), ry=0.07, rx=-0.11)):
        lo = [(1.3, -0.5), (0.95, -1.05), (-0.85, -1.12), (-1.55, -0.72), (-1.6, 0.0), (-1.55, 0.72),
              (-0.85, 1.12), (0.95, 1.05), (1.3, 0.5)]
        hi = [(x * 0.84 - 0.06, y * 0.8) for x, y in lo]
        loft("paint", [[(x, y, 0.0) for x, y in lo], [(x, y, 0.72) for x, y in hi]])
        box("paint", (1.32, 0.0, 0.36), (0.32, 0.95, 0.55))                                # mantlet
        with H.xf(M(1.45, 0.0, 0.4, ry=0.12)):
            H.emit(H.lathe([(0.0, 0.13), (0.55, 0.11), (0.6, 0.09), (1.6, 0.08), (1.6, 0.11), (1.95, 0.11),
                            (1.95, 0.075), (3.0, 0.07), (3.0, 0.1), (3.25, 0.1)], 12), "steel")
        H.emit(H.cyl(0.33, 0.24, 14), "paint", M(-0.45, -0.45, 0.8) @ H.RY(math.pi / 2))   # cupola
        H.emit(H.cyl(0.32, 0.04, 14), "paint", M(-0.78, -0.45, 1.1) @ H.RY(math.pi / 2 - 1.35))   # lid open
        box("dark", (-0.45, -0.45, 0.925), (0.48, 0.48, 0.02))
        box("dark", (-0.3, 0.5, 0.73), (0.55, 0.45, 0.02))                                 # loader's hatch, gone
        plate("paint", [(-0.6, 0.27, 0.73), (-0.6, 0.73, 0.73), (-1.0, 0.75, 0.95), (-1.0, 0.28, 0.95)], 0.04)
        box("paint", (-1.65, 0.0, 0.36), (0.25, 1.1, 0.4))                                 # bustle box
        rod("steel", (-1.2, 0.75, 0.72), (-1.5, 0.95, 1.9), 0.012, 4)                      # antenna, bent
    return {"fire": [((-1.7, -0.6, 1.72), 1.7, 1.0), ((-0.3, 0.2, 1.8), 1.5, 0.9), ((2.3, -0.55, 1.6), 0.9, 0.5)],
            "plume": [(-1.7, -0.8, 1.72), (-0.3, 0.0, 1.75), (-0.45, -0.45, 2.7), (2.35, -0.55, 1.62)],
            "ground": 0.0}


# ------------------------------------------------------------------ truck
def rim(c, r, w, seg=14):
    """Bare wheel rim (axis along Y): the dished disc, the rim lip, the hub and its nuts, a ring of tyre wire"""
    s = math.copysign(1, c[1])
    cyl_y("steel", c, r, w, seg)
    cyl_y("steel", (c[0], c[1] + s * w * 0.5, c[2]), r * 1.08, 0.04, seg)
    cyl_y("steel", (c[0], c[1] + s * (w * 0.5 + 0.04), c[2]), r * 0.35, 0.1, 8)
    H.emit(H.torus(r * 1.18, 0.012, seg, 3), "steel", M(c[0], c[1] - s * w * 0.2, c[2] - 0.03, rz=math.pi / 2, rx=0.25))


def truck():
    """The burnt-out cargo truck (see the module docstring); returns the fire sources for the burn layer"""
    rng = random.Random(5)
    hub = 0.36                    # rims stand on the ground: the tyres burnt off
    sag = math.radians(6.5)       # the chassis bent behind the cab, the rear sinks
    bend_x = -0.6

    def bent(x, z):
        """(x, z) of a chassis point after the bend"""
        if x >= bend_x:
            return x, z
        dx = x - bend_x
        return bend_x + dx * math.cos(sag), z + dx * math.sin(sag)

    # frame rails and cross members
    for sy in (-1, 1):
        for x0, x1 in ((bend_x, 3.3), (-3.45, bend_x)):
            xa, za = bent(x0, 0.68)
            xb, zb = bent(x1, 0.68)
            rod("steel", (xa, sy * 0.45, za), (xb, sy * 0.45, zb), 0.1, 4)
    for x in (2.9, 1.0, -0.2, -1.4, -2.6, -3.35):
        xb, zb = bent(x, 0.68)
        box("steel", (xb, 0.0, zb), (0.1, 0.92, 0.12))
    # axles and rims: front, two rear (one rear rim gone, its axle stub bare)
    for x in (2.4, -1.45, -2.65):
        xb, zb = bent(x, 0.68)
        rod("steel", (xb, -0.95, hub), (xb, 0.95, hub), 0.07, 6)
        box("steel", (xb, 0.0, (hub + zb) / 2), (0.25, 1.0, max(zb - hub, 0.05)))
        for sy in (-1, 1):
            if x == -2.65 and sy > 0:
                continue
            rim((xb, sy * 1.02, hub), hub, 0.3 if x > 0 else 0.42)
    # cab: shell panels with empty windows, dented roof, one door gone, the other hanging open
    cx0, cx1, cy, cz0, cz1 = 0.95, 2.15, 1.12, 0.85, 2.5
    box("paint", ((cx0 + cx1) / 2, 0.0, cz0 + 0.04), (cx1 - cx0, 2 * cy, 0.08))                  # floor
    box("paint", (cx0 + 0.03, 0.0, (cz0 + cz1) / 2), (0.06, 2 * cy, cz1 - cz0))                   # back wall
    box("dark", (cx0 + 0.07, 0.0, 2.05), (0.02, 1.4, 0.4))                                         # rear window
    box("paint", (cx1 - 0.03, 0.0, 1.35), (0.06, 2 * cy, 1.0))                                    # front wall
    for y in (-cy + 0.05, 0.0, cy - 0.05):                                                        # windscreen posts
        box("paint", (cx1 - 0.08, y, 2.12), (0.06, 0.08, 0.78), ry=0.12)
    roof = [(cx0, -cy, cz1), (cx1 - 0.15, -cy, cz1 - 0.04), (cx1 - 0.15, cy, cz1 - 0.03), (cx0, cy, cz1),
            (cx0 + 0.55, 0.15, cz1 - 0.22)]
    plate("paint", roof[:3] + [roof[4]], 0.035)
    plate("paint", [roof[0], roof[4], roof[2], roof[3]], 0.035)
    for sy in (-1, 1):
        y = sy * cy
        box("paint", ((cx0 + cx1) / 2, y, 1.05), (cx1 - cx0, 0.05, 0.4))                         # sill
        box("paint", (cx0 + 0.04, y, 1.7), (0.08, 0.05, 1.6))                                     # B post
        if sy < 0:   # the right door hangs open on its front hinges, the window frame empty
            with H.xf(M(cx1 - 0.05, y, 1.0, rz=-1.1)):
                plate("paint", [(0.0, 0.0, 0.0), (-1.05, 0.0, 0.0), (-1.05, 0.0, 0.7), (0.0, 0.0, 0.7)], 0.04)
                for z, h in ((0.72, 0.04), (1.32, 0.04)):
                    box("paint", (-0.52, 0.0, z), (1.05, 0.04, h))
                box("paint", (-1.03, 0.0, 1.02), (0.04, 0.04, 0.6))
    # inside: seat frames, steering wheel, the dash
    for y in (-0.5, 0.45):
        box("steel", (1.3, y, 1.25), (0.55, 0.5, 0.05))
        box("steel", (1.07, y, 1.6), (0.05, 0.5, 0.6), ry=-0.2)
        for k in range(4):
            rod("steel", (1.05, y - 0.22 + k * 0.15, 1.25), (1.55, y - 0.22 + k * 0.15, 1.25), 0.012, 4)
    box("dark", (2.0, 0.0, 1.85), (0.2, 2.1, 0.12))
    rod("steel", (1.95, 0.45, 1.4), (1.65, 0.45, 1.85), 0.025, 6)
    H.emit(H.torus(0.2, 0.018, 14, 4), "steel", M(1.65, 0.45, 1.86, ry=-0.9))
    # the bonnet: sides with louvres, the lid gone, the engine inside, the grille, bent bumper, mudguards
    for sy in (-1, 1):
        plate("paint", [(2.15, sy * 0.55, 0.85), (3.45, sy * 0.55, 0.85), (3.45, sy * 0.55, 1.75),
                        (2.15, sy * 0.55, 1.78)], 0.035)
        for k in range(5):
            box("dark", (2.45 + k * 0.17, sy * 0.58, 1.45), (0.07, 0.02, 0.3))
    box("dark", (2.8, 0.0, 1.05), (1.25, 1.0, 0.4))
    box("steel", (2.75, 0.0, 1.32), (0.95, 0.55, 0.45))                                         # engine block
    for k in range(6):
        H.emit(H.cyl(0.07, 0.12, 8), "steel", M(2.4 + k * 0.14, 0.0, 1.6) @ H.RY(math.pi / 2))
    box("steel", (3.5, 0.0, 1.3), (0.08, 1.15, 0.95))                                           # grille frame
    for k in range(9):
        box("dark", (3.55, -0.44 + k * 0.11, 1.3), (0.02, 0.05, 0.8))
    box("steel", (3.66, 0.1, 0.66), (0.16, 2.3, 0.18), rz=0.03, rx=0.14)                       # bumper, bent down
    for sy in (-1, 1):
        # mudguard over the front rim: a bent arch of three plates; the left one torn and folded down
        y0, y1 = sy * 0.72, sy * 1.25
        k = 1.0 if sy < 0 else 0.0
        segs = [(1.85, 0.95), (2.05, 1.32), (2.75, 1.4), (3.0, 1.15 - 0.3 * (1 - k))]
        for (xa, za), (xb, zb) in itertools.pairwise(segs):
            plate("paint", [(xa, y0, za), (xb, y0, zb), (xb, y1, zb - 0.05 * (1 - k)), (xa, y1, za)], 0.03)
        H.emit(H.cyl(0.11, 0.12, 10), "steel", M(3.45, sy * 0.85, 1.6) @ H.RY(math.pi / 2))      # lamp shell
    # fuel tank, exhaust, spare rim behind the cab
    rod("paint", (0.4, -0.75, 0.62), (1.4, -0.75, 0.62), 0.24, 12)
    rod("steel", (0.85, 0.75, 0.55), (0.85, 0.95, 2.6), 0.05, 6)
    rim((0.6, 0.0, 1.45), 0.36, 0.3)
    # cargo bed: cross members, planks (some gone, the floor broken and tilted down at the back), boards
    bx0, bx1, by = -3.55, 0.75, 1.15

    def bed(x, y, z):
        """A bed point: past the break it follows the chassis bend and droops more towards the tail"""
        xb, zb = bent(x, z)
        if x < -1.8:
            zb -= (-1.8 - x) * 0.14
        return xb, y, zb

    planks = 14
    for k in range(planks):
        y = -by + (k + 0.5) * 2 * by / planks
        if k in (4, 9, 10):
            continue
        cut = -1.8 + rng.uniform(-0.3, 0.3) if k % 3 == 1 else bx0
        a = bed(bx1, y, 0.82)
        b = bed(cut, y, 0.82)
        rod("wood", a, b, 0.07, 4)
    for y in (-by, by):
        plate("wood", [bed(bx0, y, 0.85), bed(bx1, y, 0.85), bed(bx1, y, 0.88), bed(bx0, y, 0.88)], 0.05)
    # front board stands; the left board hangs down on its hinges, the right one fell flat on the ground
    plate("wood", [(bx1, -by, 0.85), (bx1, by, 0.85), (bx1, by, 1.55), (bx1, -by, 1.55)], 0.06)
    for k, (xa, xb) in enumerate(((bx0 + 0.2, -1.6), (-1.5, bx1 - 0.1))):
        pa, pb = bed(xa, by + 0.04, 0.85), bed(xb, by + 0.04, 0.85)
        plate("wood", [pa, pb, (pb[0], pb[1] + 0.08, pb[2] - 0.6), (pa[0], pa[1] + 0.12, pa[2] - 0.6)], 0.05)
    for k in range(3):
        x0 = bx0 + 0.2 + k * 1.35
        plate("wood", [(x0, -by - 0.4 - k * 0.05, 0.03), (x0 + 1.25, -by - 0.35, 0.03),
                       (x0 + 1.25, -by - 0.95, 0.03), (x0, -by - 0.98 + k * 0.04, 0.03)], 0.05)
    plate("wood", [bed(bx0, -by, 0.86), bed(bx0, by, 0.86), (bx0 - 0.4, by, 0.12), (bx0 - 0.4, -by, 0.1)], 0.05)
    # canopy bows: two still up, bent; two fallen across the bed
    for k, x in enumerate((0.4, -0.8, -2.0, -3.2)):
        if k < 2:
            lean = 0.25 * k
            pts = [bed(x, -by, 0.88), (x - lean, -by, 2.35), (x - lean - 0.1, -0.5, 2.55),
                   (x - lean - 0.05, 0.6, 2.5 - 0.3 * k), (x - lean * 1.5, by, 2.2 - 0.4 * k), bed(x, by, 0.88)]
        else:
            z = bed(x, 0.0, 0.95)[2]
            pts = [(x, -by - 0.1, z), (x - 0.4, -0.5, z + 0.12), (x - 0.5, 0.6, z + 0.08), (x - 0.3, by + 0.6, 0.2)]
        for a, b in itertools.pairwise(pts):
            rod("steel", a, b, 0.025, 4)
    # charred crates in the bed and one fallen off
    for c, s, rz in [((-0.4, -0.35, 0.0), (0.7, 0.55, 0.45), 0.2), ((-1.1, 0.4, 0.0), (0.6, 0.6, 0.4), -0.4),
                     ((-2.3, -0.2, 0.0), (0.8, 0.5, 0.35), 0.5)]:
        z = bed(c[0], c[1], 0.9)[2] + s[2] / 2
        box("wood", (c[0], c[1], z), s, rz=rz, ry=0.05)
    box("wood", (-3.5, 1.55, 0.18), (0.6, 0.5, 0.36), rz=0.7, rx=0.3)
    return {"fire": [((1.5, 0.0, 1.6), 1.6, 1.0), ((-1.6, 0.0, 1.0), 2.4, 1.0), ((2.8, 0.0, 1.3), 1.1, 0.8)],
            "plume": [(1.5, 0.0, 2.5), (2.8, 0.0, 1.6), (-1.0, 0.0, 1.0), (-2.4, 0.0, 0.9)],
            "ground": 0.0}


# ------------------------------------------------------------------ assembly
def _srgb_to_lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def _material(cls, kind):
    """Bake-source material: the class's flat colour into Base Color (the paint is the vehicle's own)"""
    m = bpy.data.materials.new("vw_" + cls)
    m.use_nodes = True
    rgb = PAINT_RGB[kind] if cls == "paint" else CLASSES[cls]
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*_srgb_to_lin(rgb), 1.0)
    return m


def assemble(name, kind):
    """Join the accumulated faces into one object with class materials, welded and normalised to the biome
    model frame (centred, standing on z = 0, largest size in plan = 1); returns (object, scale applied, the
    build-frame point moved to the origin)"""
    verts, faces, mids, names = [], [], [], []
    for mi, (cls, (vs, fs)) in enumerate(H.G.items()):
        off = len(verts)
        verts.extend(vs)
        faces.extend([[off + i for i in f] for f in fs])
        mids.extend([mi] * len(fs))
        names.append(cls)
    co = np.array([tuple(v) for v in verts], np.float64)
    lo, hi = co.min(0), co.max(0)
    k = 1.0 / max(hi[0] - lo[0], hi[1] - lo[1])
    off = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
    co = (co - off) * k
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in co], [], faces)
    me.update(calc_edges=True)
    for n in names:
        me.materials.append(_material(n, kind))
    me.polygons.foreach_set("material_index", mids)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    return ob, k, off


# ------------------------------------------------------------------ burnt-hulk layers
SCORCH = np.array([0.1, 0.075, 0.06], np.float32)     # the dark ring where the paint burnt through
RUST = np.array([0.42, 0.23, 0.12], np.float32)       # burnt steel turned rust-brown
RUST_D = np.array([0.24, 0.14, 0.09], np.float32)
ASH = np.array([0.5, 0.48, 0.45], np.float32)         # grey-white oxide and ash where it burnt hottest
SOOT = np.array([0.04, 0.036, 0.033], np.float32)
DUST = np.array([0.64, 0.57, 0.45], np.float32)       # Highland sand (turret_paint.DUST, a touch lighter)
CHAR = np.array([0.07, 0.06, 0.055], np.float32)


def make_layers(fires, k, off, seed):
    """The burnt-hulk function for turret_paint.bake_set (pal["layers"]). fires: {"fire": [(centre, radius,
    weight)], "plume": [opening]} in metres as built; k — the normalising scale (metres → model units), off —
    the build-frame point that became the model's origin (assemble)"""
    off = np.array(off, np.float32)
    src = [((np.array(c, np.float32) - off) * k, r * k, w) for c, r, w in fires["fire"]]
    plumes = [np.array(c, np.float32) - off for c in fires["plume"]]   # metres, in the centred frame

    def height(Pm, part, burn):
        """Relief in metres: rust pitting and paint blisters on steel, char cracks on wood"""
        pit = TP.fbm(Pm, 9.0, seed + 20, 3)
        steel_like = (part == PAINT) | (part == STEEL) | (part == TRACK)
        h = steel_like * (0.0012 * pit + 0.0015 * TP.sstep(0.62, 0.72, TP.fbm(Pm, 5.0, seed + 21, 2))
                          * TP.sstep(0.25, 0.45, burn) * (1 - TP.sstep(0.6, 0.8, burn)))
        cell = TP.fbm(Pm, 7.0, seed + 22, 2)
        h = h - (part == WOOD) * 0.004 * TP.sstep(0.45, 0.5, np.abs(cell - 0.5) * 2) \
            + (part == WOOD) * 0.002 * np.sin(Pm[:, 0] * 40.0 + 6 * TP.fbm(Pm, 1.5, seed + 23, 2))
        return h

    def burn_of(P, Pm):
        b = np.zeros(len(P), np.float32)
        for c, r, w in src:
            d = np.linalg.norm(P - c, axis=1)
            b = np.maximum(b, w * np.exp(-(d / r) ** 1.6))
        b = b + 0.4 * (TP.fbm(Pm, 0.45, seed + 1, 3) - 0.5) + 0.15 * (TP.fbm(Pm, 2.0, seed + 2, 2) - 0.5)
        b = b + 0.12 * np.clip(Pm[:, 2] - 1.0, 0, 1.5) + 0.18   # heat rises: tops burn more; the whole hulk burnt
        return np.clip(b, 0.0, 1.0)

    def layers(P, N, B, AO, part, S):
        Pm = (P * BAKE_SCALE).astype(np.float32)   # bake units (scale = BAKE_SCALE * k) → metres
        Pk = Pm * k                                 # model units, as the fire sources
        z = Pm[:, 2]
        up = np.clip(N[:, 2], 0, 1)
        wall = 1.0 - np.abs(N[:, 2])
        t, b = TP._frame(N)
        burn = burn_of(Pk, Pm)
        paint, steel, track, rubber, wood, dark = [part == i for i in range(6)]
        col = S.copy()
        mott = TP.fbm(Pm, 0.6, seed + 3, 4)
        col = col * (1.0 + 0.22 * (mott - 0.5))[:, None]
        # paint: faded and sun-bleached where it survived, blistered near the fire, then the burn gradient:
        # dark scorch ring → rust-brown burnt steel → grey-white ash oxide at the hottest
        faded = col * (1.0 + 0.06 * up)[:, None] * 0.92
        blist = TP.sstep(0.6, 0.7, TP.fbm(Pm, 6.0, seed + 4, 2)) * TP.sstep(0.22, 0.4, burn)
        faded = faded * (1 - 0.45 * blist[:, None])
        rust = RUST * (0.75 + 0.5 * TP.fbm(Pm, 1.6, seed + 5, 3))[:, None]
        rust = rust * (1 - 0.5 * TP.sstep(0.5, 0.7, TP.fbm(Pm, 4.0, seed + 6, 2)))[:, None] \
            + RUST_D * (0.5 * TP.sstep(0.5, 0.7, TP.fbm(Pm, 4.0, seed + 6, 2)))[:, None]
        ash = ASH * (0.8 + 0.35 * TP.fbm(Pm, 2.5, seed + 7, 3))[:, None]
        e = burn + 0.12 * (TP.fbm(Pm, 3.0, seed + 8, 2) - 0.5)
        c_p = faded
        c_p = c_p * (1 - TP.sstep(0.3, 0.42, e)[:, None]) + SCORCH * TP.sstep(0.3, 0.42, e)[:, None]
        c_p = c_p * (1 - TP.sstep(0.44, 0.6, e)[:, None]) + rust * TP.sstep(0.44, 0.6, e)[:, None]
        c_p = c_p * (1 - (0.7 * TP.sstep(0.72, 0.9, e))[:, None]) + ash * (0.7 * TP.sstep(0.72, 0.9, e))[:, None]
        col = np.where(paint[:, None], c_p, col)
        # bare steel: dark burnt steel with rust; track links: rust-brown, worn bright where they met the road
        c_s = col * 0.8 + rust * (0.2 + 0.5 * burn)[:, None] * 0.8
        col = np.where(steel[:, None], c_s, col)
        wear = TP.sstep(0.4, 0.9, -N[:, 2]) * (z < 0.25)
        c_t = rust * 0.75 * (0.8 + 0.4 * TP.fbm(Pm, 8.0, seed + 9, 2))[:, None]
        c_t = c_t * (1 - 0.4 * wear[:, None]) + np.array([0.42, 0.4, 0.37], np.float32) * (0.4 * wear)[:, None]
        col = np.where(track[:, None], c_t, col)
        # rubber burnt off to grey ash and cracked black; wood charred with alligator cracks, raw at the ends
        crack = TP.sstep(0.47, 0.5, np.abs(TP.fbm(Pm, 7.0, seed + 22, 2) - 0.5) * 2)
        c_r = col * (1 - 0.6 * burn[:, None]) + ASH * 0.55 * (0.6 * burn)[:, None]
        col = np.where(rubber[:, None], c_r, col)
        raw = (1 - TP.sstep(0.35, 0.6, burn)) * 0.6
        c_w = CHAR * (0.8 + 0.6 * TP.fbm(Pm, 3.0, seed + 10, 2))[:, None]
        c_w = c_w * (1 - raw[:, None]) + np.array([0.4, 0.33, 0.25], np.float32) * raw[:, None]
        c_w = c_w * (1 - 0.6 * crack[:, None]) + (ASH * 0.7) * (0.25 * up * (1 - crack))[:, None]
        col = np.where(wood[:, None], c_w, col)
        col = np.where(dark[:, None], CHAR * (0.7 + 0.6 * mott)[:, None], col)
        # soot plumes above the openings: stronger close and just above, spreading as they rise
        soot = np.zeros(len(P), np.float32)
        for c in plumes:
            dz = Pm[:, 2] - c[2]
            dh = np.linalg.norm(Pm[:, :2] - c[:2], axis=1)
            soot = np.maximum(soot, np.exp(-dh / (0.35 + 0.45 * np.clip(dz, 0, 3))) * TP.sstep(-0.4, 0.3, dz)
                              * np.exp(-np.clip(dz, 0, 9) / 2.5))
        soot = np.clip(soot * (0.6 + 0.8 * (TP.fbm(Pm, 1.5, seed + 12, 3) - 0.3)), 0, 0.9)
        col = col * (1 - soot[:, None]) + SOOT * soot[:, None]
        # rust runs down the walls from edges and bolts
        st = TP.fbm(Pm * np.array([1.0, 1.0, 0.08], np.float32), 6.0, seed + 13, 3)
        run = TP.sstep(0.58, 0.75, st) * wall * (paint | steel) * (0.25 + 0.5 * burn)
        col = col * (1 - 0.5 * run[:, None]) + RUST * (0.5 * run)[:, None]
        # cavity grime, sand settled on top faces and drifted at the foot, ash speckles where it burnt
        cav = 1.0 - AO
        col = col * (1 - 0.45 * cav[:, None]) + SOOT * 2.5 * (0.45 * cav)[:, None]
        dust = up * np.clip(cav * 1.3 + (TP.fbm(Pm, 1.1, seed + 14, 3) - 0.45) * 0.9, 0, 0.6)
        foot = (1.0 - TP.sstep(0.05, 0.55 + 0.35 * TP.fbm(Pm, 1.4, seed + 15, 3), z)) * 0.75
        dust = np.clip(np.maximum(dust, foot), 0, 0.85)
        col = col * (1 - dust[:, None]) + DUST * dust[:, None]
        speck = TP.sstep(0.68, 0.74, TP.fbm(Pm, 11.0, seed + 16, 2)) * up * TP.sstep(0.5, 0.8, burn)
        col = col * (1 - 0.6 * speck[:, None]) + ASH * 1.1 * (0.6 * speck)[:, None]
        col = col * (0.55 + 0.45 * AO ** 0.8)[:, None]
        rough = np.select([paint, steel, track, rubber, wood, dark], [0.9, 0.86, 0.84, 0.95, 0.97, 1.0],
                          0.92).astype(np.float32)
        rough = np.clip(rough + 0.06 * (TP.fbm(Pm, 3.0, seed + 17, 2) - 0.5) + 0.06 * dust + 0.05 * soot, 0.82, 1.0)
        metal = (0.12 * steel * (1 - dust) * (1 - soot)).astype(np.float32)
        e2 = 0.004
        hu = (height(Pm + t * e2, part, burn) - height(Pm - t * e2, part, burn)) / (2 * e2)
        hv = (height(Pm + b * e2, part, burn) - height(Pm - b * e2, part, burn)) / (2 * e2)
        nn = B - (hu[:, None] * t + hv[:, None] * b) * 1.5
        nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
        return np.clip(col, 0, 1), rough, metal, nn

    return layers


def part_of(m):
    """Surface id of a bake-source material: its class index"""
    return CID.get(m.name[3:], 0) if m is not None else 0


MODELS = {"tank": ("b08_wreck_tank", tank, 31), "truck": ("b07_wreck_truck", truck, 47)}


def build(kind, out, size):
    """Model one hulk, bake its burnt atlas and export it; returns (size in model units, triangles)"""
    name, fn, seed = MODELS[kind]
    H.reset(True)
    R.seed(seed)
    fires = fn()
    ob, k, off = assemble(name, kind)
    tris = len(ob.data.polygons)
    dims = ob.dimensions.copy()
    ob.select_set(True)
    # bake in metres (BAKE_SCALE units per metre) on the model scaled to 1: one model unit = 1/k metres
    pal = {"own": True, "seed": seed, "part": part_of, "layers": make_layers(fires, k, off, seed)}
    TP.bake_set([ob], pal, size, "wreck_" + kind, scale=BAKE_SCALE * k)
    path = os.path.join(out, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_tangents=True, export_image_format="JPEG", export_jpeg_quality=90)
    return dims, tris


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(GAME / "models" / "biome"))
    ap.add_argument("--only", default="")
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for kind in MODELS:
        if a.only and kind not in a.only.split(","):
            continue
        dims, tris = build(kind, a.out, a.size)
        print(f"WRECK {kind} size {dims[0]:.3f} x {dims[1]:.3f} x {dims[2]:.3f} tris {tris}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
