"""Осмотр GLB-моделей: треугольники, отдельные куски, мелкий мусор, открытые края; три ракурса.
Запуск: python3 audit_models.py <out_dir> <model.glb> [...] → <out>/<имя>_{top,iso,side}.png и stats.tsv"""
import sys, os, math
import bpy, bmesh
from mathutils import Vector

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
rows = []
for path in sys.argv[2:]:
    name = os.path.splitext(os.path.basename(path))[0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in sc.objects if o.type == "MESH"]
    tris = parts = tiny = openedges = 0
    lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
    for o in obs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    diag = (hi - lo).length
    for o in obs:
        bm = bmesh.new(); bm.from_mesh(o.data)
        bm.transform(o.matrix_world)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=diag * 1e-5)
        tris += sum(len(f.verts) - 2 for f in bm.faces)
        openedges += sum(1 for e in bm.edges if len(e.link_faces) == 1)
        seen = set()
        for f in bm.faces:
            if f.index in seen: continue
            stack = [f]; comp = []; seen.add(f.index)
            while stack:
                g = stack.pop(); comp.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h.index not in seen:
                            seen.add(h.index); stack.append(h)
            parts += 1
            vs = [v.co for g in comp for v in g.verts]
            ext = (Vector(map(max, *vs)) - Vector(map(min, *vs))).length if vs else 0
            if ext < diag * 0.02: tiny += 1
        bm.free()
    rows.append("%s\t%d\t%d\t%d\t%d\t%.2f×%.2f×%.2f" % (name, tris, parts, tiny, openedges, *(hi - lo)))
    # рендер
    ctr = (lo + hi) / 2
    w = bpy.data.worlds.new("w"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.58, 0.62, 1)
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
    sun.rotation_euler = (math.radians(35), math.radians(10), math.radians(-30)); sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = diag * 0.95
    sc.render.engine = "CYCLES"; sc.cycles.samples = 12; sc.cycles.device = "CPU"
    sc.render.resolution_x = 520; sc.render.resolution_y = 360
    for vn, d in (("top", Vector((0, 0.001, 1))), ("iso", Vector((-0.8, -1.0, 0.7))), ("side", Vector((0, -1, 0.05))), ("under", Vector((0.3, -0.5, -1)))):
        d.normalize()
        cam.location = ctr + d * diag * 2
        cam.rotation_mode = "QUATERNION"
        cam.rotation_quaternion = (-d).to_track_quat("-Z", "Y")
        sc.render.filepath = os.path.join(out, "%s_%s.png" % (name, vn))
        bpy.ops.render.render(write_still=True)
open(os.path.join(out, "stats.tsv"), "a").write("\n".join(rows) + "\n")
print("AUDIT DONE")
