# Drop loose parts of a ready game model (Blender, bpy; 3.5-s12).
#   python3.11 -I glb_drop_parts.py in.glb out.glb --above=0.115
# Kanta 26.10: two discs and two red reflectors hung in the air over the bomb cart (stand_cart.glb, Sketchfab №23):
# leftovers of the source scene that sf_weapon_prep.py kept. --above=z drops every loose part whose lowest point
# (model units, the model's up axis +Z in Blender) is above z, so nothing floats over the cart's cradles.
import sys, bpy, bmesh

a = sys.argv[1:]
src, dst = a[0], a[1]
opt = dict(x[2:].split('=', 1) for x in a[2:] if x.startswith('--') and '=' in x)
above = float(opt['above'])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for ob in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seen, drop = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        comp, stack = [], [v]
        seen.add(v.index)
        while stack:
            p = stack.pop()
            comp.append(p)
            for e in p.link_edges:
                q = e.other_vert(p)
                if q.index not in seen:
                    seen.add(q.index)
                    stack.append(q)
        if min((ob.matrix_world @ u.co).z for u in comp) > above:
            drop += comp
    print("DROP", ob.name, len(drop), "verts")
    bmesh.ops.delete(bm, geom=drop, context='VERTS')
    bm.to_mesh(me)
    bm.free()
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=False, export_apply=True,
    export_image_format='JPEG', export_jpeg_quality=90)
print("OK", dst)
