# Weapon or hangar stand from Sketchfab → game model (Blender, bpy; PG-01, Kanta 24.10).
#   python3 -I sf_weapon_prep.py in.glb out.glb --nose=+y [--pick=x,-0.1,0.3] [--keep=NAME,..] [--drop=NAME,..]
#       [--target=30000] [--median=9] [--len=1] [--up=+z] [--tint=r,g,b,k] [--keepparts=x,-0.45,0.5]
# Output axes as every weapon model of the game: nose → +X, up → +Y (glTF), length along X = --len (1),
# centred on the origin. Stands (--stand) keep their own up axis and sit on y = 0, longest side along X.
#   --pick=axis,lo,hi  keep only parts whose bounding-box centre on that axis (source Blender coords) is in [lo, hi]
#                      (a file with several missiles side by side → one of them)
#   --keep / --drop    keep / drop parts whose object or material name contains one of the words
#   --median=N         median filter of N px over albedo textures: wipes stencilled text and real markings
#                      (fictional world, CLAUDE.md rule 1) while keeping colour bands; 0 — off
#   --tint=r,g,b,k     mix albedo towards a matte colour by k (0..1), e.g. repaint a white missile olive
# Materials become matte (roughness ≥ 0.75, metallic ≤ 0.3): Kanta's rule of 19.10 — no glossy models.
import sys, math, bpy
from mathutils import Vector, Matrix

a = sys.argv[1:]
src, dst = a[0], a[1]
opt = dict(x[2:].split('=', 1) for x in a[2:] if x.startswith('--') and '=' in x)
flags = {x[2:] for x in a[2:] if x.startswith('--') and '=' not in x}
target = int(opt.get('target', 30000))
median = int(opt.get('median', 9))
length = float(opt.get('len', 1.0))
words = lambda k: [s.strip().upper() for s in opt.get(k, '').split(',') if s.strip()]
keep, drop = words('keep'), words('drop')

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene


def bbox(o):
    w = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return Vector(map(min, *w)), Vector(map(max, *w))


def names(o):
    return (o.name + ' ' + ' '.join(s.material.name for s in o.material_slots if s.material)).upper()


objs = [o for o in sc.objects if o.type == 'MESH']
if 'pick' in opt:
    ax, lo, hi = opt['pick'].split(',')
    i = 'xyz'.index(ax)
    objs = [o for o in objs if float(lo) <= ((bbox(o)[0] + bbox(o)[1]) / 2)[i] <= float(hi)]
if keep:
    objs = [o for o in objs if any(k in names(o) for k in keep)]
objs = [o for o in objs if not any(k in names(o) for k in drop)]
for o in [o for o in sc.objects if o.type == 'MESH' and o not in objs]:
    bpy.data.objects.remove(o)

# one mesh in world space
for o in sc.objects:
    o.select_set(o in objs)
bpy.context.view_layer.objects.active = objs[0]
for o in objs:
    mw = o.matrix_world.copy(); o.parent = None; o.data = o.data.copy(); o.data.transform(mw); o.matrix_world = Matrix.Identity(4)
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
for o in list(sc.objects):
    if o != ob:
        bpy.data.objects.remove(o)
me = ob.data
# neutral names: source object, mesh and material names often carry real hardware names (CLAUDE.md rule 1)
ob.name = me.name = "weapon"
for i, mat in enumerate(me.materials):
    if mat is not None:
        mat.name = "mat%d" % i

# orientation: given nose axis → +X; given up axis → +Z (Blender), which glTF export turns into +Y
AX = {'+x': Vector((1, 0, 0)), '-x': Vector((-1, 0, 0)), '+y': Vector((0, 1, 0)), '-y': Vector((0, -1, 0)),
    '+z': Vector((0, 0, 1)), '-z': Vector((0, 0, -1))}
nose = AX[opt.get('nose', '+x')]
up = AX[opt.get('up', '+z' if abs(nose.z) < 0.5 else '+y')]
side = up.cross(nose)
basis = Matrix((nose, side, up)).to_4x4()   # rows: new X, Y, Z in old coords
me.transform(basis)
if 'roll' in opt:
    me.transform(Matrix.Rotation(math.radians(float(opt['roll'])), 4, 'X'))
# --keepparts=axis,lo,hi: after orientation, keep only loose parts whose bounding-box centre on that axis
# (share of the length, the model centred on 0) is in [lo, hi] — e.g. drop the tow bar of a cart
if 'keepparts' in opt:
    import bmesh
    ax, lo, hi = opt['keepparts'].split(',')
    i = 'xyz'.index(ax)
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4 * max(ob.dimensions))
    bm.verts.ensure_lookup_table()
    co = [v.co[i] for v in bm.verts]
    c0, span = (max(co) + min(co)) / 2, max(1e-6, max(co) - min(co))
    seen, drop = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        comp, stack = [], [v]
        seen.add(v.index)
        while stack:
            a = stack.pop(); comp.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index); stack.append(b)
        cc = (max(u.co[i] for u in comp) + min(u.co[i] for u in comp)) / 2
        if not float(lo) <= (cc - c0) / span <= float(hi):
            drop += comp
    bmesh.ops.delete(bm, geom=drop, context='VERTS')
    bm.to_mesh(me); bm.free()
mn = Vector(map(min, *[v.co for v in me.vertices])); mx = Vector(map(max, *[v.co for v in me.vertices]))
k = length / max(1e-6, (mx.x - mn.x))
me.transform(Matrix.Scale(k, 4))
mn *= k; mx *= k
c = (mn + mx) / 2
if 'stand' in flags:
    me.transform(Matrix.Translation(Vector((-c.x, -c.y, -mn.z))))   # stands on the floor
else:
    me.transform(Matrix.Translation(-c))
me.update()

# triangle budget
tris = sum(len(p.vertices) - 2 for p in me.polygons)
if tris > target:
    m = ob.modifiers.new('dec', 'DECIMATE'); m.ratio = target / tris; m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier='dec')
print("TRIS", tris, "->", sum(len(p.vertices) - 2 for p in me.polygons))

# matte materials; albedo cleaned of markings
tint = [float(v) for v in opt['tint'].split(',')] if 'tint' in opt else None
done = set()
for mat in me.materials:
    if mat is None or not mat.use_nodes:
        continue
    bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        continue
    r = bsdf.inputs['Roughness']; mt = bsdf.inputs['Metallic']
    if not r.is_linked:
        r.default_value = max(0.75, r.default_value)
    if not mt.is_linked:
        mt.default_value = min(0.3, mt.default_value)
    bsdf.inputs['Specular IOR Level'].default_value = 0.35
    col = bsdf.inputs['Base Color']
    if not col.is_linked:
        if tint:
            cv = col.default_value
            col.default_value = [cv[i] * (1 - tint[3]) + tint[i] * tint[3] for i in range(3)] + [1.0]
        continue
    img_node = col.links[0].from_node
    img = getattr(img_node, 'image', None)
    if img is None or img.name in done:
        continue
    done.add(img.name)
    if median > 1 or tint:
        from PIL import Image, ImageFilter
        import numpy as np
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        pil = Image.fromarray((px[:, :, :3] * 255).astype(np.uint8))
        if median > 1:
            pil = pil.filter(ImageFilter.MedianFilter(median | 1))
        arr = np.asarray(pil).astype(np.float32) / 255.0
        if tint:
            arr = arr * (1 - tint[3]) + np.array(tint[:3], dtype=np.float32) * tint[3]
        px[:, :, :3] = arr
        img.pixels[:] = px.ravel()
        img.pack()

bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=False, export_apply=True,
    export_image_format='JPEG', export_jpeg_quality=90)
print("OK", dst, "len", length)
