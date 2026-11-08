# B2-A01 (Kanta 08.11, «Береговая батарея»): the coast gun as an enemy needs a turret that turns and a barrel that
# rises. The scenery site a01_battery_gun.glb (b2_shore.py::_gun_site) is one joined, baked mesh; this tool cuts it
# into three nodes without re-baking, so the look stays exactly the scenery one:
#   body   — pit, parapet, berm, pedestal and clutter (stands still);
#   turret — turntable ring, shield, breech, cradle, sights, platform, seats (Render3D._ground_parts turns it);
#   barrel — tube, jacket, hoops, brake, mantlet, recoil cylinders; child of turret, pivot on the trunnions.
#   ../bv/bin/python -I game/tools/model_lab/gun_split.py <in a01_battery_gun.glb> <out fh_battle_e_coast_gun.glb>
# Needs `pip install bpy` (5.1, Python 3.13). Parts are told apart by their loose pieces' place in the recipe's
# metres (see the numbers in _gun_site): the mount is the recipe × GUN_K about the origin, the barrel's axis runs
# through (0, 0, 2.0) raised 4°.
import math
import sys

import bpy  # first: bmesh and mathutils come with it
import bmesh
import numpy as np
from mathutils import Matrix

GUN_REF = 13.95   # b2_shore.GUN_REF: 1 model unit = 13.95 m
GUN_K = 1.45      # b2_shore.GUN_K: the mount is drawn 1.45× bigger
PIVOT_Z = 2.0     # recipe metres: barrel pieces are moved by Translation((0, 0, 2.0)) @ Rotation(-4°, Y)
EL = math.radians(4.0)


def recipe(co):
    """Model units → the recipe's metres before GUN_K (mount space)."""
    return co * GUN_REF / GUN_K


def components(bm):
    """Loose pieces of the mesh as lists of face indices."""
    seen = set()
    out = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        comp = []
        while stack:
            a = stack.pop()
            comp.append(a.index)
            for e in a.edges:
                for b in e.link_faces:
                    if b.index not in seen:
                        seen.add(b.index)
                        stack.append(b)
        out.append(comp)
    return out


def classify(pts):
    """'barrel', 'turret' or 'body' for a loose piece given its vertices in recipe metres (n, 3)."""
    x, y, z = pts[:, 0], pts[:, 1], pts[:, 2]
    axis_z = PIVOT_Z + x * math.tan(EL)
    if x.min() > 0.55 and np.abs(y).max() < 0.5 and np.abs(z - axis_z).max() < 0.55:
        return 'barrel'
    r = np.hypot(x, y)
    # mount pieces stand on the turntable (z > 0.84 m before ×1.45 is ~0.58 here) and keep within the platform's
    # corner (r 3.1 m); ammo boxes and lids lie on the floor (top < 0.6), clutter and parapet are farther out
    zm = pts[:, 2] * GUN_K   # back to real metres for the floor test
    if r.max() < 3.15 and zm.min() > 0.3 and zm.max() > 0.9:
        return 'turret'
    return 'body'


def split(src, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    ob = next(o for o in bpy.data.objects if o.type == 'MESH')
    bpy.context.view_layer.objects.active = ob
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    co = np.array([v.co[:] for v in bm.verts])
    tag = {}
    count = {'body': 0, 'turret': 0, 'barrel': 0}
    for comp in components(bm):
        vids = sorted({v.index for fi in comp for v in bm.faces[fi].verts})
        k = classify(recipe(co[vids]))
        count[k] += 1
        for fi in comp:
            tag[fi] = k
    print("SPLIT pieces", count)
    parts = {}
    for k in ('turret', 'barrel'):
        b2 = bm.copy()
        b2.faces.ensure_lookup_table()
        bmesh.ops.delete(b2, geom=[f for f in b2.faces if tag[f.index] != k], context='FACES')
        m2 = bpy.data.meshes.new(k)
        b2.to_mesh(m2)
        for mat in me.materials:
            m2.materials.append(mat)
        o2 = bpy.data.objects.new(k, m2)
        bpy.context.scene.collection.objects.link(o2)
        parts[k] = o2
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if tag[f.index] != 'body'], context='FACES')
    bm.to_mesh(me)
    ob.name = 'body'
    # pivots: the turret turns about the vertical through the origin, the barrel about the trunnion axis (Y)
    piv = np.array([0.0, 0.0, PIVOT_Z * GUN_K / GUN_REF])
    bar = parts['barrel']
    bar.data.transform(Matrix.Translation((-piv).tolist()))
    bar.location = piv.tolist()
    parts['turret'].parent = ob
    bar.parent = parts['turret']
    print("SPLIT tris", {o.name: len(o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'})
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_image_format='JPEG',
                              export_jpeg_quality=88, use_selection=False, export_yup=True)


if __name__ == '__main__':
    split(sys.argv[1], sys.argv[2])
