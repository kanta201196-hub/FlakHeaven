"""Общие функции для моделей турелей в Blender (bpy 5.x): примитивы с фаской, сборка по материалам,
экспорт .blend + .glb и предпросмотр Cycles. Blender: Z вверх, X — вперёд по стволам."""
import math, os
import bpy, bmesh
from mathutils import Vector

sc = None


def reset():
    global sc
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    parts.clear()


# --- материалы ---
def mat(name, rgb, metal=0.0, rough=0.6):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m

#M_BODY = mat("turret_body", (0.36, 0.35, 0.33), 0.25, 0.55)
#M_DARK = mat("turret_dark", (0.12, 0.12, 0.12), 0.5, 0.5)
#M_BARREL = mat("turret_barrel", (0.3, 0.3, 0.29), 0.6, 0.4)

parts = []
group = ""          # пусто — основной корпус; иначе подвижная часть (узел с этим именем в GLB)
pivots = {}         # группа → точка вращения (x, y, z)
parents = {}        # группа → группа-родитель (по умолчанию корпус): деталь крутится вместе с ней

def finish(ob, m, bevel=0.0, seg=1):
    ob.data.materials.append(m)
    if bevel > 0:
        md = ob.modifiers.new("bev", "BEVEL")
        md.width = bevel
        md.segments = seg
        md.limit_method = "ANGLE"
    for p in ob.data.polygons:
        p.use_smooth = True
    ob["fh_group"] = group
    parts.append(ob)
    return ob

# Blender: Z вверх, X — вперёд по стволам, Y — вбок. Экспорт glTF сам переводит в Y-вверх.
def box(name, c, s, m, bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = s
    bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m, bevel)

def cyl(name, c, r, h, m, axis="Z", verts=24, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=c)
    ob = bpy.context.object
    ob.name = name
    if axis == "X":
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "Y":
        ob.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return finish(ob, m, bevel)

def prism(name, profile, width, m, bevel=0.018):
    """Профиль (x, z) сбоку, выдавлен по Y на width (по центру)"""
    me = bpy.data.meshes.new(name)
    sc = bpy.context.scene
    bm = bmesh.new()
    vs = [bm.verts.new((x, -width / 2, z)) for x, z in profile]
    f = bm.faces.new(vs)
    bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in bm.verts:
        if abs(v.co.y + width / 2) < 1e-6 and v not in vs:
            v.co.y = width / 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    return finish(ob, m, bevel, 3)

def tube(name, pts, r, m):
    """Поручень из прямых трубок по точкам"""
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        d = b - a
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r, depth=d.length, location=(a + b) / 2)
        ob = bpy.context.object
        ob.name = name
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
        bpy.ops.object.transform_apply(rotation=True)
        finish(ob, m)



def build(name, out, paint=None, tex=2048):
    """Применить фаски, слить детали в один объект, сохранить .blend и .glb.
    paint — palette from turret_paint.PALETTES: bake the textured paint (S12) before the export; the root gets a
    tex x tex atlas, the moving groups half of it (pods a quarter)"""
    os.makedirs(out, exist_ok=True)
    for ob in parts:
        bpy.context.view_layer.objects.active = ob
        for md in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
    groups = {}
    for ob in parts:
        groups.setdefault(ob["fh_group"], []).append(ob)
    tur = None
    tris = 0
    for gname, obs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for ob in obs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.join()
        j = bpy.context.object
        j.name = gname if gname else name
        tris += sum(len(p.vertices) - 2 for p in j.data.polygons)
        if gname:
            bpy.context.scene.cursor.location = pivots.get(gname, (0, 0, 0))
            bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        else:
            tur = j
    for gname, obs in groups.items():
        if gname:
            o = bpy.data.objects[gname]
            mw = o.matrix_world.copy()
            o.parent = bpy.data.objects[parents[gname]] if gname in parents else tur
            o.matrix_world = mw
    print("TRIS", tris)
    if paint is not None:
        import turret_paint
        turret_paint.bake(tur, paint, tex, "turret_paint")
        for gname in groups:
            if gname:
                turret_paint.bake(bpy.data.objects[gname], paint, tex // 4 if gname == "pods" else tex // 2,
                                  "turret_paint_" + gname)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, name + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format="GLB", use_selection=False,
                              export_image_format="JPEG" if paint is not None else "AUTO", export_jpeg_quality=90)

    return tur


def preview(out, shots):
    """shots: [(имя, позиция камеры, цель, фокус объектива)]; цель None — вид строго сверху"""
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.95, 0.95, 0.96, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    sc.world = w
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    fl = bpy.context.object
    fm = mat("floor", (0.97, 0.97, 0.97), 0, 0.9)
    fl.data.materials.append(fm)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.2
    sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(-30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.device = "CPU"
    sc.render.resolution_x = 960
    sc.render.resolution_y = 540
    sc.view_settings.view_transform = "AgX"

    for nm, pos, target, lens in shots:
        cam.data.lens = lens
        cam.location = pos
        if target is None:
            cam.rotation_mode = "XYZ"
            cam.rotation_euler = (0, 0, 0)
        else:
            cam.rotation_mode = "QUATERNION"
            cam.rotation_quaternion = (Vector(target) - Vector(pos)).to_track_quat("-Z", "Y")
        sc.render.filepath = os.path.join(out, "preview_%s.png" % nm)
        bpy.ops.render.render(write_still=True)
