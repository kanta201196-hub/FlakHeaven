"""Plane decal slots (prototype, spec docs/superpowers/specs/2026-10-27-plane-decals-design.md).

Same technique as insignia.py: every slot is a small grid of points shot onto the hangar model's skin
by rays and lifted along the normal, so the decal follows the airframe's shape. Output is one small GLB
in model axes, models/mech/fh_dec_<class>_<lvl>.glb, attached by PlaneDecals next to the insignia
(the battle models share the hangar axes, as with insignia).

Slots, both sides (_l = +Y in Blender, _r = -Y):
  nose_*   nose art (shark mouth, eye, mascot) forward of the windscreen
  kills_*  kill tally row under the canopy sill
  num_*    side number on the fuselage aft of the cockpit
Wing roundels and the fin badge stay in fh_ins_* (insignia.py); PlaneDecals re-skins the fin badge.
UV: u along the fuselage (u = 0 at the nose on the left side, at the tail on the right side, so text
reads correctly on both; directional art is flipped in the shader), v up.

Run (bpy 5.x): python3 decal_slots.py <hangar model.glb> <class_lvl> <out.glb>
"""
import sys  # noqa: I001 (bpy must be imported before bmesh)

import bpy  # bpy first: it registers bmesh and mathutils
import bmesh
import numpy as np
from mathutils import Vector

# key → slot → (x, z, width, height) in model units (length 1, nose +X, up +Z), measured on the hangar
# models (canopy glass span and fuselage profile, probe in the spec's appendix)
SLOTS = {
    "fighter_1": {"nose": (0.365, -0.032, 0.075, 0.034), "kills": (0.225, -0.022, 0.065, 0.014),
                  "num": (0.03, -0.035, 0.06, 0.03)},
    "fighter_2": {"nose": (0.425, -0.036, 0.06, 0.03), "kills": (0.29, -0.008, 0.08, 0.014),
                  "num": (0.12, -0.05, 0.06, 0.024)},
    "attacker_1": {"nose": (0.385, -0.067, 0.06, 0.03), "kills": (0.245, -0.03, 0.08, 0.016),
                   "num": (-0.16, -0.05, 0.07, 0.03)},
    "attacker_2": {"nose": (0.415, -0.072, 0.056, 0.028), "kills": (0.25, -0.07, 0.08, 0.016),
                   "num": (-0.22, -0.035, 0.065, 0.026)},
    "bomber_1": {"nose": (0.42, -0.066, 0.05, 0.026), "kills": (0.30, -0.045, 0.06, 0.014),
                 "num": (-0.18, -0.058, 0.08, 0.035)},
    "bomber_2": {"nose": (0.425, -0.046, 0.05, 0.026), "kills": (0.33, -0.025, 0.06, 0.014),
                 "num": (0.19, -0.018, 0.06, 0.028)},
}
NU, NV = 16, 6   # grid per slot
LIFT = 0.0009    # above the skin (insignia use 0.0008: decals sit on top of them where they meet)
STEP = 0.006     # neighbouring rays further apart in depth than this landed on different surfaces

src, key, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
plane = [o for o in bpy.context.scene.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene


def side_hit(px: float, pz: float, side: int):
    """First skin point that faces sideways, seen from the plane's side: rays pass wings, pylons and
    flaps (normals up or down) and stop on the fuselage, intake or nacelle wall."""
    o = Vector((px, side * 2.0, pz))
    for _ in range(6):
        ok, loc, nrm, _i, _ob, _mw = sc.ray_cast(dg, o, Vector((0, -side, 0)))
        if not ok or loc.y * side < 0:
            return None
        if nrm.y * side > 0.7:   # outward, not the far side of a wing or a duct
            return loc, nrm
        o = loc + Vector((0, -side * 0.0005, 0))
    return None


# nudges tried around the table position before the slot shrinks (wing roots and intake lips move a
# number slot by a centimetre or two on the real skin)
NUDGE = sorted(((dx, dz) for dx in (0.0, -0.02, 0.02, -0.04, 0.04) for dz in (0.0, -0.008, 0.008, -0.016, 0.016)),
               key=lambda d: abs(d[0]) + 2.0 * abs(d[1]))


def slot(name: str, x: float, z: float, w: float, h: float, side: int):
    """Grid shot from the side at the fuselage: the largest size (down to 0.6 of the table) and the
    nearest nudge at which every ray lands on one smooth surface."""
    step = 0.012 if name.startswith("nose") else STEP   # a nose is round: depth changes fast near its edge
    for _ in range(6):
        for dx, dz in NUDGE:
            ob = _slot(name, x + dx, z + dz, w, h, side, step)
            if ob is not None:
                return ob
        w *= 0.9
        h *= 0.9
    print(f"DEC {name}: no fit")
    return None


def _slot(name: str, x: float, z: float, w: float, h: float, side: int, step: float):
    pts = []
    for j in range(NV + 1):
        row = []
        for i in range(NU + 1):
            u, v = i / NU, j / NV
            px = x + side * (0.5 - u) * w   # left side: u runs nose → tail; right side: tail → nose
            pz = z + (v - 0.5) * h
            hit = side_hit(px, pz, side)
            if hit is None:
                return None
            row.append((hit, (u, v)))
        pts.append(row)
    ys = np.array([[abs(p[0][0].y) for p in r] for r in pts])
    jump = max(np.abs(np.diff(ys, axis=0)).max(), np.abs(np.diff(ys, axis=1)).max())
    if jump > step:   # neighbours on different surfaces: an intake lip, a pylon, the wing root
        return None
    bm = bmesh.new()
    uvk = bm.loops.layers.uv.new("UVMap")
    grid = []
    for r in pts:
        grow = []
        for (loc, nrm), uv in r:
            n = nrm if nrm.y * side > 0 else -nrm
            grow.append((bm.verts.new(loc + n * LIFT), uv))
        grid.append(grow)
    for j in range(NV):
        for i in range(NU):
            quad = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
            f = bm.faces.new([q[0] for q in quad])
            for lp, q in zip(f.loops, quad):
                lp[uvk].uv = q[1]
    bm.normal_update()
    for f in bm.faces:
        if f.normal.y * side < 0:
            f.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.new("decal_" + name)
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    print(f"DEC {name}: x {x:.3f} z {z:.3f} w {w:.3f} h {h:.3f}")
    return ob


out = []
for nm, (x, z, w, h) in SLOTS[key].items():
    for side, s in ((1, "l"), (-1, "r")):
        out.append(slot(f"{nm}_{s}", x, z, w, h, side))

for o in plane:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(sc.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_materials="EXPORT")
print(f"DEC {dst}: {len([o for o in out if o])} slots")
