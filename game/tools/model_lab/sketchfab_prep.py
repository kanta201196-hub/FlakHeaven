# Подготовка корабля из Sketchfab для игры (Blender, bpy):
#   python3 -I ship_prep.py in.glb out.glb --target=20000 --bow=-y --water=-77 [--atlas=new.png] [--drop=LADDERS,WIPERS] [--mindiag=8] [--cut=x0,x1,y0,y1,z0]
# нос → +X, вверх → +Y (glTF), длина по X = 1, ватерлиния на y = 0, центр по X/Z в нуле
import sys, math, bpy, bmesh
from mathutils import Vector, Matrix
a = sys.argv[1:]
src, dst = a[0], a[1]
opt = dict(x[2:].split('=', 1) for x in a[2:] if x.startswith('--') and '=' in x)
target = int(opt.get('target', 20000)); bow = opt.get('bow', '+x'); water = float(opt.get('water', 'nan'))
drop = [s.strip().upper() for s in opt.get('drop', '').split(',') if s.strip()]
mindiag = float(opt.get('mindiag', 0))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
objs = [o for o in sc.objects if o.type == 'MESH']
for o in list(objs):
    bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
    diag = (Vector(map(max, *bb)) - Vector(map(min, *bb))).length
    if any(k in o.name.upper() for k in drop) or diag < mindiag:
        bpy.data.objects.remove(o); objs.remove(o)
# бюджет треугольников делим по видимой площади детали (габарит), а не по числу её треугольников:
# корпус и надстройка остаются гладкими, мелочь упрощается сильнее; сначала — плоские грани (limited dissolve)
def area(o):
    bb = [o.matrix_world @ Vector(v) for v in o.bound_box]; d = Vector(map(max, *bb)) - Vector(map(min, *bb))
    return d.x * d.y + d.y * d.z + d.x * d.z
tot = sum(area(o) for o in objs)
for o in (objs if opt.get('mode', 'global') == 'area' else []):
    for q in sc.objects: q.select_set(False)
    o.select_set(True); bpy.context.view_layer.objects.active = o
    t = sum(len(p.vertices) - 2 for p in o.data.polygons)
    want = max(24, target * area(o) / tot)
    if t > want:
        m = o.modifiers.new('dc', 'DECIMATE'); m.ratio = want / t; m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier='dc')
for o in sc.objects: o.select_set(o in objs)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
mw = ob.matrix_world.copy(); ob.parent = None; ob.data.transform(mw); ob.matrix_world = Matrix.Identity(4)
for o in list(sc.objects):
    if o != ob: bpy.data.objects.remove(o)
ob.select_set(True); bpy.context.view_layer.objects.active = ob
me = ob.data
for k in [k for k in ('cut', 'cut2', 'cut3') if k in opt]:   # убрать кусок (кран и т. п.): x0,x1,y0,y1,z0 в исходных координатах Blender
    x0, x1, y0, y1, z0 = map(float, opt[k].split(','))
    bm = bmesh.new(); bm.from_mesh(me)
    kill = [f for f in bm.faces if all(x0 <= v.co.x <= x1 and y0 <= v.co.y <= y1 and v.co.z >= z0 for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context='FACES'); bm.to_mesh(me); bm.free()
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
vs = [v.co for v in me.vertices]; ext = max(max(c[i] for c in vs) - min(c[i] for c in vs) for i in range(3))
bpy.ops.mesh.remove_doubles(threshold=ext * 1e-5); bpy.ops.object.mode_set(mode='OBJECT')
tris = sum(len(p.vertices) - 2 for p in me.polygons)
for it in range(4):   # мелкие отдельные детали упрощаются хуже — повторяем, пока не уложимся
    if tris <= target * 1.05: break
    m = ob.modifiers.new('dec', 'DECIMATE'); m.ratio = max(0.02, target / tris * (0.9 ** it)); m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='dec')
    tris = sum(len(p.vertices) - 2 for p in me.polygons); print("DEC", it, tris)
# поворот: нос на +X (в Blender, вверх +Z)
rot = {'+x': 0, '-y': 90, '-x': 180, '+y': -90}[bow]
me.transform(Matrix.Rotation(math.radians(rot), 4, 'Z')); me.update()
bb = [v.co for v in me.vertices]; mn = Vector(map(min, *bb)); mx = Vector(map(max, *bb))
wz = water if not math.isnan(water) else mn.z
me.transform(Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -wz)))
s = 1.0 / (mx.x - mn.x); me.transform(Matrix.Scale(s, 4)); me.update()
if 'atlas' in opt:
    img = bpy.data.images.load(opt['atlas'])
    for mat in me.materials:
        bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        for l in bsdf.inputs['Base Color'].links:
            if l.from_node.type == 'TEX_IMAGE': l.from_node.image = img
    if 'noemit' in opt:   # подсветка из исходника (окна, огни) в игре не нужна
        for mat in me.materials:
            bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
            for l in list(bsdf.inputs['Emission Color'].links): mat.node_tree.links.remove(l)
            bsdf.inputs['Emission Strength'].default_value = 0.0
for im in bpy.data.images:   # текстуры не больше 1024
    if im.size[0] > 1024: im.scale(1024, im.size[1] * 1024 // im.size[0])
ob.name = 'body'
tris = sum(len(p.vertices) - 2 for p in me.polygons)
bb = [v.co for v in me.vertices]; mn = Vector(map(min, *bb)); mx = Vector(map(max, *bb))
print("PREP tris", tris, "size", tuple(round(x, 3) for x in (mx - mn)), "zmin", round(mn.z, 3))
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=90, use_selection=False)
