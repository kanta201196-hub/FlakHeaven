"""Ремеш модели ангара (тест 3.5-s4, п. 34): ровная сетка из одних квадратов вместо «каши» треугольников Meshy
и новая текстура, запечённая с исходной модели на новую развёртку. Форма и габариты остаются прежними
(длина 1, нос +X): новая сетка притянута к исходной поверхности, отклонение печатается в конце.

Нужно: bpy (Blender 4.x/5.x как модуль) и pymeshlab (`pip install pymeshlab`).
Запуск (из game/tools/blender), результат сразу в игру — рядом кладутся картинки <модель>_col.jpg / _orm.jpg,
старые <модель>_0.png… удаляются; потом `godot --headless --path game --import`:
  python3 remesh_hangar.py <in.glb> <out.glb> [--faces 32000] [--tex 4096] [--jpeg 92] [--voxel 0.0025]
        [--sharp 38] [--smooth 0.5] [--normal none|geo|full] [--samples 4] [--drop x0,x1,y0,y1,z0,z1 ...]
        [--blend path.blend] [--stages папка]
Исходник берётся вместе с картинками, которые Godot извлёк рядом с ним (<in>_0.png, <in>_Image_0.png…):
окраску правили в них (splinter_camo.py), а не в GLB. Поэтому <in.glb> — НЕ тот же файл, что <out.glb>,
а копия старой модели с её PNG (исходники лежат в /mnt/project-files/models_src/remesh_hangar/orig/).
  «Кит 1» после замены винтов (лопасти и коки Meshy вырезаны, дыры в мотогондолах закрываются сами):
  python3 remesh_hangar.py <папка>/fh_hangar_bomber_1.glb ../../models/hangar/fh_hangar_bomber_1.glb
  (в <папке> рядом с GLB — fh_hangar_bomber_1_0.png, _1.png, _2.png той же версии).

Шаги: импорт → сварка, дыры закрываются «веером» → voxel remesh (шаг 0.0025: замкнутая оболочка без внутренних
граней Meshy; тонкие антенны и штыри могут пропасть) → изотропная сетка MeshLab (ровные треугольники, острые
кромки по углу --sharp) → пары треугольников в квадраты → одно деление (квадрат → 4, треугольник → 3):
только квадраты → притяжка к оболочке (shrinkwrap) и выравнивание (relax) с повторной притяжкой; острые
кромки сглаживание не трогает → Smart UV Project с запасом ~10 пикселей → запекание Cycles на CPU
(selected-to-active) цвета и карты ORM (шероховатость G / металл B) из исходного материала через эмиссию —
без света и теней → экспорт GLB (PBR: цвет + ORM, как у исходника).
QuadriFlow (bpy.ops.object.quadriflow_remesh) пробовали: на тонких крыльях и стыках килей рвёт поверхность
и «съедает» нос, а с use_preserve_sharp считает полчаса — поэтому сетка строится через MeshLab.
--normal: none — без карты нормалей (по умолчанию: шум и «пузыри» Meshy не переносятся), geo — нормали
с исходной геометрии, full — с геометрии и исходной карты нормалей.
--drop: удалить части исходника в рамке (координаты Blender: X нос, Y левое крыло, Z верх) до ремеша;
при запекании исходник остаётся целым.
"""
import argparse
import math
import os
import sys
import time

import bpy  # noqa: I001 — bpy первым: он регистрирует bmesh и mathutils
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("dst")
ap.add_argument("--faces", type=int, default=32000)
ap.add_argument("--tex", type=int, default=4096)
ap.add_argument("--voxel", type=float, default=0.0025)
ap.add_argument("--normal", default="none", choices=["none", "geo", "full"])
ap.add_argument("--smooth", type=float, default=0.5)
ap.add_argument("--sharp", type=float, default=38.0)
ap.add_argument("--samples", type=int, default=4)
ap.add_argument("--jpeg", type=int, default=92, help="0 — PNG")
ap.add_argument("--drop", nargs="*", default=[])
ap.add_argument("--blend", default="")
ap.add_argument("--iso-iters", dest="iso_iters", type=int, default=12)
ap.add_argument("--quad-level", dest="quad_level", type=int, default=1)
ap.add_argument("--stages", default="", help="папка: .blend после каждого шага (отладка)")
A = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])

T0 = time.time()


def log(*a):
    print("[remesh %5.0fs]" % (time.time() - T0), *a, flush=True)


def stage(name):
    if A.stages:
        os.makedirs(A.stages, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.abspath(A.stages), name + ".blend"), copy=True)


def activate(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def apply_mod(o, m):
    activate(o)
    bpy.ops.object.modifier_apply(modifier=m.name)


# ---------- импорт ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(A.src))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:   # всё в мировые координаты: у GLB из Godot вложенные узлы с масштабом и поворотом
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
    activate(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in [o for o in bpy.context.scene.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o)
if len(meshes) > 1:
    activate(meshes[0])
    for o in meshes[1:]:
        o.select_set(True)
    bpy.ops.object.join()
src = meshes[0]
src.name = "src"
# Godot извлекает встроенные картинки GLB в PNG рядом (<имя>_<N или имя картинки>.png) и дальше берёт их,
# не перезаписывая; окраску правили в этих PNG (splinter_camo.py, clean_camo.py) — печём с них
src_base = os.path.splitext(os.path.abspath(A.src))[0]
for im in list(bpy.data.images):
    cands = [src_base + "_" + im.name + ".png"]
    if im.name.startswith("Image_") and im.name[6:].isdigit():
        cands.append(src_base + "_" + im.name[6:] + ".png")
    f = [c for c in cands if os.path.exists(c)]
    if f:
        ni = bpy.data.images.load(f[0])
        ni.colorspace_settings.name = im.colorspace_settings.name
        for m in bpy.data.materials:
            if m.node_tree:
                for n in m.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image == im:
                        n.image = ni
        log("картинка %s ← %s %s" % (im.name, os.path.basename(f[0]), tuple(ni.size)))
smat = src.data.materials[0]
bb = [src.matrix_world @ Vector(c) for c in src.bound_box]
lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
log("исходник: %d граней, габарит %s .. %s" % (len(src.data.polygons), tuple(round(v, 4) for v in lo), tuple(round(v, 4) for v in hi)))

# ---------- рабочая копия: чистка ----------
rm = src.copy()
rm.data = src.data.copy()
rm.name = "remesh"
bpy.context.scene.collection.objects.link(rm)
bm = bmesh.new()
bm.from_mesh(rm.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
for box in A.drop:
    x0, x1, y0, y1, z0, z1 = [float(t) for t in box.split(",")]
    kill = [f for f in bm.faces if all(x0 <= v.co.x <= x1 and y0 <= v.co.y <= y1 and z0 <= v.co.z <= z1 for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    log("--drop %s: удалено %d граней" % (box, len(kill)))
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context="VERTS")
# дыры (срезанные винты, щели Meshy) — заделать, иначе voxel remesh «протекает»
# каждый замкнутый контур открытых рёбер закрывается «веером» к его центру (контур бывает неплоским)
bnd = set(e for e in bm.edges if e.is_boundary)
holes = 0
while bnd:
    e0 = bnd.pop()
    loop = [e0.verts[0], e0.verts[1]]
    ok = False
    while True:
        nxt = [e for e in loop[-1].link_edges if e in bnd]
        if not nxt:
            ok = nxt == [] and loop[-1] in e0.verts and len(loop) > 2
            break
        e = nxt[0]
        bnd.discard(e)
        w = e.other_vert(loop[-1])
        if w == loop[0]:
            ok = True
            break
        loop.append(w)
    if not ok or len(loop) < 3:
        continue
    c = bm.verts.new(sum((v.co for v in loop), Vector()) / len(loop))
    for i in range(len(loop)):
        a, b = loop[i], loop[(i + 1) % len(loop)]
        try:
            bm.faces.new((b, a, c))
        except ValueError:
            pass
    holes += 1
if holes:
    log("заделано дыр: %d" % holes)
# нормали наружу у каждой части: вывернутая часть Meshy (фонарь «Грача») voxel remesh считает «дыркой» и выбрасывает
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(rm.data)
bm.free()
rm.data.materials.clear()

# ---------- voxel remesh: замкнутая равномерная оболочка ----------
rm.data.remesh_voxel_size = A.voxel
rm.data.remesh_voxel_adaptivity = 0.0
rm.data.use_remesh_fix_poles = True
activate(rm)
bpy.ops.object.voxel_remesh()
# мелкие «острова» (обрывки, пузыри внутри) — убрать, оставить крупные части
bm = bmesh.new()
bm.from_mesh(rm.data)
bm.verts.ensure_lookup_table()
seen = set()
parts = []
for v0 in bm.verts:
    if v0.index in seen:
        continue
    stack = [v0]
    comp = []
    seen.add(v0.index)
    while stack:
        v = stack.pop()
        comp.append(v)
        for e in v.link_edges:
            w = e.other_vert(v)
            if w.index not in seen:
                seen.add(w.index)
                stack.append(w)
    parts.append(comp)
parts.sort(key=len, reverse=True)
small = [v for c in parts if len(c) < max(200, len(parts[0]) * 0.002) for v in c]
if small:
    bmesh.ops.delete(bm, geom=small, context="VERTS")
bm.to_mesh(rm.data)
bm.free()
log("voxel %.4f: %d граней, частей %d (убрано мелких вершин %d)" % (A.voxel, len(rm.data.polygons), len(parts), len(small)))

# оболочка voxel — цель притяжки: только наружная поверхность, без внутренних граней Meshy
shell = rm.copy()
shell.data = rm.data.copy()
shell.name = "shell"
bpy.context.scene.collection.objects.link(shell)
stage("1_voxel")


def area(me):
    return sum(p.area for p in me.polygons)


# Изотропная сетка (MeshLab): ровные треугольники вдвое крупнее итоговых квадратов, острые кромки — по углу;
# пары треугольников → квадраты; одно деление (каждый квадрат → 4, треугольник → 3) — только квадраты
import numpy as np  # noqa: E402
import pymeshlab  # noqa: E402  (pip install pymeshlab)
ar = area(rm.data)
edge = math.sqrt(ar / A.faces)   # сторона итогового квадрата
coarse = edge * 2.75   # из пары крупных треугольников после деления выходит ~6 квадратов; подобрано на «Осе 1»
tri = rm.modifiers.new("tri", "TRIANGULATE")
apply_mod(rm, tri)
me = rm.data
V = np.array([v.co[:] for v in me.vertices], dtype=np.float64)
F = np.array([p.vertices[:] for p in me.polygons], dtype=np.int32)
ms = pymeshlab.MeshSet()
ms.add_mesh(pymeshlab.Mesh(vertex_matrix=V, face_matrix=F))
ms.meshing_isotropic_explicit_remeshing(iterations=A.iso_iters, adaptive=False, targetlen=pymeshlab.PureValue(coarse),
                                        featuredeg=A.sharp, checksurfdist=True,
                                        maxsurfdist=pymeshlab.PureValue(edge * 0.25), splitflag=True, collapseflag=True,
                                        swapflag=True, smoothflag=True, reprojectflag=True)
ms.meshing_tri_to_quad_dominant(level=A.quad_level)
mm = ms.current_mesh()
V2 = mm.vertex_matrix()
try:
    polys = mm.polygonal_face_list()
except Exception:  # noqa: BLE001
    polys = None
if not polys:
    polys = [list(f) for f in mm.face_matrix()]
me2 = bpy.data.meshes.new("iso")
me2.from_pydata([tuple(v) for v in V2], [], [list(map(int, f)) for f in polys])
me2.validate()
old = rm.data
rm.data = me2
bpy.data.meshes.remove(old)
nq = sum(1 for p in me2.polygons if len(p.vertices) == 4)
log("изотропная сетка: шаг %.4f, %d граней (квадратов %d)" % (coarse, len(me2.polygons), nq))
stage("2a_quad_dominant")
sd = rm.modifiers.new("sd", "SUBSURF")
sd.subdivision_type = "SIMPLE"
sd.levels = 1
apply_mod(rm, sd)
nq = sum(1 for p in rm.data.polygons if len(p.vertices) == 4)
log("новая сетка: %d граней, из них квадратов %d" % (len(rm.data.polygons), nq))
stage("2_quads")
if len(rm.data.polygons) < A.faces * 0.3:
    sys.exit("ремеш не сработал (граней %d)" % len(rm.data.polygons))



# ---------- притяжка к исходнику и выравнивание ----------
def shrink():
    m = rm.modifiers.new("sw", "SHRINKWRAP")
    m.target = shell
    m.wrap_method = "NEAREST_SURFACEPOINT"
    apply_mod(rm, m)


def sharp_group():
    """вершины острых кромок (двугранный угол больше --sharp) и их соседи — сглаживание их не двигает"""
    bm = bmesh.new()
    bm.from_mesh(rm.data)
    lim = math.radians(A.sharp)
    hard = set()
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
            hard.add(e.verts[0].index)
            hard.add(e.verts[1].index)
    bm.free()
    vg = rm.vertex_groups.get("soft") or rm.vertex_groups.new(name="soft")
    vg.add(list(range(len(rm.data.vertices))), 1.0, "REPLACE")
    if hard:
        vg.add(list(hard), 0.0, "REPLACE")
    return len(hard)


def relax(factor, iters):
    if factor <= 0:
        return
    m = rm.modifiers.new("sm", "SMOOTH")
    m.factor = factor
    m.iterations = iters
    m.vertex_group = "soft"
    apply_mod(rm, m)


shrink()
stage("3_shrink")
for _ in range(3):   # relax + притяжка: квадраты выравниваются по размеру, поверхность остаётся исходной
    nh = sharp_group()
    relax(0.5, 4)
    shrink()
nh = sharp_group()
relax(A.smooth * 0.5, 2)   # последний мягкий проход: гладкость без «перепадов» исходника
log("острых вершин %d, сглаживание %.2f" % (nh, A.smooth))
stage("4_relax")

# отклонение от исходника
bm = bmesh.new()
bm.from_mesh(src.data)
bvh = BVHTree.FromBMesh(bm)
bm.free()
d = sorted((bvh.find_nearest(v.co)[3] or 0.0) for v in rm.data.vertices)
dev = (sum(d) / len(d), d[int(len(d) * 0.99)], d[-1])
# и обратно: точки исходника до новой сетки — так видно потерянные части (нос, кромки)
bm = bmesh.new()
bm.from_mesh(rm.data)
bvh2 = BVHTree.FromBMesh(bm)
bm.free()
d2 = sorted((bvh2.find_nearest(v.co)[3] or 0.0) for v in src.data.vertices)
cov = (d2[int(len(d2) * 0.99)], d2[int(len(d2) * 0.999)], d2[-1])
log("исходник → новая сетка: 99%% %.5f, 99.9%% %.5f, макс %.5f" % cov)
bb = [Vector(c) for c in rm.bound_box]
lo2 = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
hi2 = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
log("отклонение от исходника: среднее %.5f, 99%% %.5f, макс %.5f; габарит %s .. %s" % (
    dev[0], dev[1], dev[2], tuple(round(v, 4) for v in lo2), tuple(round(v, 4) for v in hi2)))

# гладкие нормали, острые кромки — жёсткие
activate(rm)
bpy.ops.object.shade_smooth()
try:
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(max(A.sharp, 50.0)), keep_sharp_edges=True)
except Exception as e:  # noqa: BLE001
    log("shade_smooth_by_angle:", e)

# ---------- развёртка ----------
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.0, area_weight=0.0, correct_aspect=True,
                         scale_to_bounds=False)
margin = 10.0 / A.tex   # ~10 пикселей между островами
try:
    bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, rotate_method="ANY", scale=True,
                            merge_overlap=False, margin_method="FRACTION", margin=margin, shape_method="CONCAVE")
except TypeError:
    bpy.ops.uv.pack_islands(rotate=True, margin=margin)
bpy.ops.object.mode_set(mode="OBJECT")
log("UV: островов развёрнуто, запас %.4f" % margin)

# ---------- запекание ----------
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = A.samples
sc.cycles.use_denoising = False
sc.render.bake.use_selected_to_active = True
sc.render.bake.use_cage = False
sc.render.bake.cage_extrusion = 0.006
sc.render.bake.max_ray_distance = 0.02
sc.render.bake.margin = 16
sc.render.bake.margin_type = "EXTEND"
sc.render.bake.use_clear = True

tmat = bpy.data.materials.new(rm.name + "_mat")
tmat.use_nodes = True
rm.data.materials.append(tmat)
tn = tmat.node_tree.nodes
tl = tmat.node_tree.links
bsdf = tn["Principled BSDF"]


def new_img(name, srgb, size=None):
    s = size or A.tex
    im = bpy.data.images.new(name, s, s, alpha=False, float_buffer=False)
    im.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    return im


def target_node(img):
    n = tn.new("ShaderNodeTexImage")
    n.image = img
    for x in tn:
        x.select = False
    n.select = True
    tn.active = n
    return n


sn = smat.node_tree.nodes
sl = smat.node_tree.links
sbsdf = [n for n in sn if n.type == "BSDF_PRINCIPLED"][0]


def src_img_node(socket_name):
    """узел картинки исходника, который (через Separate Color / Normal Map) питает вход BSDF"""
    sock = sbsdf.inputs[socket_name]
    if not sock.is_linked:
        return None
    n = sock.links[0].from_node
    while n.type != "TEX_IMAGE":
        ins = [i for i in n.inputs if i.is_linked]
        if not ins:
            return None
        n = ins[0].links[0].from_node
    return n


col_node = src_img_node("Base Color")
orm_node = src_img_node("Roughness") or src_img_node("Metallic")
nrm_link = sbsdf.inputs["Normal"].links[0] if sbsdf.inputs["Normal"].is_linked else None
nrm_from = nrm_link.from_socket if nrm_link else None


def bake_emit(img_src_node, img):
    """запечь картинку исходника как эмиссию: чистый цвет без света, теней и шума"""
    em = sbsdf.inputs["Emission Color"]
    for lk in list(em.links):
        sl.remove(lk)
    sl.new(img_src_node.outputs["Color"], em)
    sbsdf.inputs["Emission Strength"].default_value = 1.0
    target_node(img)
    activate(rm)
    src.select_set(True)
    bpy.context.view_layer.objects.active = rm
    bpy.ops.object.bake(type="EMIT")
    for lk in list(em.links):
        sl.remove(lk)
    sbsdf.inputs["Emission Strength"].default_value = 0.0


img_col = new_img(rm.name + "_col", True)
if col_node is not None:
    bake_emit(col_node, img_col)
    log("запечён цвет %d" % A.tex)
else:
    img_col.generated_color = tuple(sbsdf.inputs["Base Color"].default_value)
img_orm = None
if orm_node is not None:
    img_orm = new_img(rm.name + "_orm", False, max(1024, A.tex // 2))
    bake_emit(orm_node, img_orm)
    log("запечена карта шероховатость/металл %d" % img_orm.size[0])
img_nrm = None
if A.normal != "none":
    if A.normal == "geo" and nrm_link is not None:
        sl.remove(nrm_link)
    img_nrm = new_img(rm.name + "_nrm", False, max(1024, A.tex // 2))
    target_node(img_nrm)
    activate(rm)
    src.select_set(True)
    bpy.context.view_layer.objects.active = rm
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
    log("запечена карта нормалей (%s) %d" % (A.normal, img_nrm.size[0]))
    if A.normal == "geo" and nrm_from is not None:
        sl.new(nrm_from, sbsdf.inputs["Normal"])

# ---------- материал новой модели ----------
for n in list(tn):
    if n.type == "TEX_IMAGE":
        tn.remove(n)
nc = tn.new("ShaderNodeTexImage")
nc.image = img_col
tl.new(nc.outputs["Color"], bsdf.inputs["Base Color"])
if img_orm is not None:
    no = tn.new("ShaderNodeTexImage")
    no.image = img_orm
    sep = tn.new("ShaderNodeSeparateColor")
    tl.new(no.outputs["Color"], sep.inputs["Color"])
    tl.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    tl.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
else:
    bsdf.inputs["Roughness"].default_value = sbsdf.inputs["Roughness"].default_value
    bsdf.inputs["Metallic"].default_value = sbsdf.inputs["Metallic"].default_value
if img_nrm is not None:
    nn = tn.new("ShaderNodeTexImage")
    nn.image = img_nrm
    nm = tn.new("ShaderNodeNormalMap")
    tl.new(nn.outputs["Color"], nm.inputs["Color"])
    tl.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
tmat.use_backface_culling = False

# картинки — внутрь GLB и рядом файлом с тем именем, под которым их извлечёт Godot (<модель>_<имя картинки>.png|.jpg):
# Godot уже существующие извлечённые файлы не перезаписывает, поэтому кладём их сами и старые убираем
import re  # noqa: E402
import shutil  # noqa: E402
import tempfile  # noqa: E402
base = os.path.splitext(os.path.basename(A.dst))[0]
dst_base = os.path.splitext(os.path.abspath(A.dst))[0]
ddir = os.path.dirname(dst_base)
os.makedirs(ddir, exist_ok=True)
for f in os.listdir(ddir):
    # старые картинки исходника (<модель>_0.png, _Image_1.png…) под новую развёртку не подходят; свои — пишем заново
    if re.fullmatch(re.escape(base) + r"_((Image_)?\d+|col|orm|nrm)\.(png|jpg)(\.import)?", f):
        os.remove(os.path.join(ddir, f))
        log("удалён старый", f)
tmpd = tempfile.mkdtemp()
for im, suf in [(img_col, "col"), (img_orm, "orm"), (img_nrm, "nrm")]:
    if im is None:
        continue
    im.filepath_raw = os.path.join(tmpd, suf + ".png")   # экспортёр называет картинку по имени файла: «col»
    im.file_format = "PNG"
    im.save()
    path = im.filepath_raw
    if A.jpeg > 0 and suf != "nrm":   # карту нормалей JPEG портит — она всегда PNG
        from PIL import Image as PILImage  # noqa: E402
        path = os.path.join(tmpd, suf + ".jpg")
        PILImage.open(im.filepath_raw).convert("RGB").save(path, quality=A.jpeg, subsampling=0, optimize=True)
    ni = bpy.data.images.load(path)
    ni.colorspace_settings.name = im.colorspace_settings.name
    ni.name = suf
    ni.pack()
    for n in tn:
        if n.type == "TEX_IMAGE" and n.image == im:
            n.image = ni
    shutil.copyfile(path, dst_base + "_" + os.path.basename(path))
    log("картинка %s: %s, %.1f МБ" % (suf, os.path.basename(path), os.path.getsize(path) / 1e6))

if A.blend:
    for im in bpy.data.images:
        if im.size[0] > 0 and not im.packed_file:
            im.pack()
    os.makedirs(os.path.dirname(os.path.abspath(A.blend)), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.blend), compress=True)
    log("сохранён", A.blend)

# ---------- экспорт ----------
bpy.data.objects.remove(src)
bpy.data.objects.remove(shell)
rm.name = base
rm.data.name = base
rm.vertex_groups.clear()
activate(rm)
kw = dict(filepath=os.path.abspath(A.dst), export_format="GLB", use_selection=True, export_tangents=img_nrm is not None,
          export_normals=True, export_texcoords=True, export_materials="EXPORT", export_yup=True)
kw.update(export_image_format="AUTO")   # картинки уже в нужном формате (PNG или JPEG) — без пережатия
bpy.ops.export_scene.gltf(**kw)
tris = sum(len(p.vertices) - 2 for p in rm.data.polygons)
log("готово %s: %d граней (%d квадратов), %d треугольников, %.1f МБ" % (
    A.dst, len(rm.data.polygons), sum(1 for p in rm.data.polygons if len(p.vertices) == 4), tris,
    os.path.getsize(A.dst) / 1e6))
print("REMESH_OK dev_mean=%.5f dev99=%.5f dev_max=%.5f cov99=%.5f cov999=%.5f cov_max=%.5f" % (dev + cov))
