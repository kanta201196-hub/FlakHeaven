"""Village houses for the Highland kishlak from CC BY Sketchfab sources (VIS-01, Kanta 26.10.2026: village houses
from models 49, 50 and 51, model 71 may be used too, mix them).

The source textures are dropped: every face gets one of the fortified-area fort material classes (texture set Г, FortBuild
SETS: plaster, brick, wood, stone; plus flat dark openings and faded cloth), so the village and the fort read as one
place. Faces are classed by source material name, or for single-texture sources by the texture colour under the
face. Each house variant is centred on its footprint, base on z = 0, metres (≈ the fort preview's units), long side
along X, decimated, and gets box-projected UVs (metres / tile of its class, as FortBuild._tri) so the fort shader
tiles it at the fort's texel size. The well (71) keeps its scan texture, decimated.
The six model-50 houses vh_h50a…f are no longer made here: they were replaced (weak-models list, item 1, 28.10.2026)
by procedural houses from village_adobe.py, so their rows are gone and a rerun leaves those files alone.

Run (from the repo root; the sources are untrusted downloads, so -I):
  python3 -I game/tools/blender/village_houses.py <dl_dir> <out_dir>
    <dl_dir>/{h49,h51,w71}/src.glb  ->  <out_dir>/vh_<name>.glb, <out_dir>/vh_well.glb, sizes printed as
    a GDScript table for VillageHouses.VARIANTS
"""
import math
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

TILE = {"plaster": 4.6, "brick": 5.2, "wood": 5.0, "stone": 7.0, "dark": 8.0, "cloth": 2.0}   # FortBuild SETS


def load(src):
    """Fresh scene with the GLB at src; transforms baked into the meshes, non-mesh objects dropped."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obs = []
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            continue
        mw = o.matrix_world.copy()
        if o.data.users > 1:
            o.data = o.data.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = o.matrix_world.Identity(4)
        obs.append(o)
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    return obs


def _base_image(mat):
    if mat is None or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            for l in n.inputs["Base Color"].links:
                if l.from_node.type == "TEX_IMAGE" and l.from_node.image is not None:
                    return l.from_node.image
    return None


_px = {}


def _sample(img, uv):
    if img.name not in _px:
        a = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
        _px[img.name] = a
    a = _px[img.name]
    h, w = a.shape[:2]
    x = int((uv[0] % 1.0) * (w - 1))
    y = int((uv[1] % 1.0) * (h - 1))
    return a[y, x, :3]


def classify(o, rule):
    """Per-face class list. rule: {material regex: class | "tex"}; "tex" classes by the texture under the face."""
    me = o.data
    uvl = me.uv_layers.active
    out = []
    for p in me.polygons:
        mat = me.materials[p.material_index] if me.materials else None
        name = mat.name if mat else ""
        cls = "plaster"
        for pat, c in rule:
            if re.search(pat, name):
                cls = c
                break
        if cls == "tex":
            img = _base_image(mat)
            if img is None or uvl is None:
                cls = "plaster"
            else:
                u = sum((uvl.data[li].uv for li in p.loop_indices), Vector((0, 0))) / len(p.loop_indices)
                rgb = _sample(img, u)
                v = float(max(rgb))
                cls = "dark" if v < 0.16 else "plaster"
        out.append(cls)
    return out


def build_variant(obs, rule, scale, target):
    """Join obs into one object with class materials, metres, centred, decimated, box UVs. Returns (object, size)."""
    classes = ["plaster", "brick", "wood", "stone", "dark", "cloth"]
    mats = {c: bpy.data.materials.get("vh_" + c) or bpy.data.materials.new("vh_" + c) for c in classes}
    for o in obs:
        cl = classify(o, rule)
        o.data.materials.clear()
        for c in classes:
            o.data.materials.append(mats[c])
        for p, c in zip(o.data.polygons, cl):
            p.material_index = classes.index(c)
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.data.transform(Matrix.Scale(scale, 4))
    vs = [v.co for v in o.data.vertices]
    mn = Vector(map(min, *vs))
    mx = Vector(map(max, *vs))
    # long side along X
    if (mx.y - mn.y) > (mx.x - mn.x) * 1.05:
        o.data.transform(Matrix.Rotation(math.pi / 2, 4, "Z"))
        vs = [v.co for v in o.data.vertices]
        mn = Vector(map(min, *vs))
        mx = Vector(map(max, *vs))
    c = (mn + mx) / 2
    o.data.transform(Matrix.Translation(Vector((-c.x, -c.y, -mn.z))))
    # merge doubles, flatten coplanar faces, then collapse to the budget
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.004)
    bm.to_mesh(o.data)
    bm.free()
    if sum(len(p.vertices) - 2 for p in o.data.polygons) > target:
        md = o.modifiers.new("pl", "DECIMATE")
        md.decimate_type = "DISSOLVE"
        md.angle_limit = math.radians(2.0)
        md.delimit = {"MATERIAL"}
        bpy.ops.object.modifier_apply(modifier="pl")
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.quads_convert_to_tris()
        bpy.ops.object.mode_set(mode="OBJECT")
        t = sum(len(p.vertices) - 2 for p in o.data.polygons)
        if t > target:
            md = o.modifiers.new("col", "DECIMATE")
            md.ratio = target / t
            md.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier="col")
    # box UVs in metres / tile of the face's class (FortBuild._tri: top faces x,z; sides along the wall, -height)
    me = o.data
    uvl = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        n = p.normal
        k = 1.0 / TILE[classes[p.material_index]]
        for li in p.loop_indices:
            q = me.vertices[me.loops[li].vertex_index].co
            if abs(n.z) > 0.75:
                uv = (q.x, q.y)
            elif abs(n.x) >= abs(n.y):
                uv = (q.y * (1 if n.x >= 0 else -1), q.z)
            else:
                uv = (-q.x * (1 if n.y >= 0 else -1), q.z)
            uvl.data[li].uv = (uv[0] * k, uv[1] * k)
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[1] if me.uv_layers[0] == uvl else me.uv_layers[0])
    for p in me.polygons:
        p.use_smooth = False
    vs = [v.co for v in me.vertices]
    mn = Vector(map(min, *vs))
    mx = Vector(map(max, *vs))
    return o, mx - mn


def export(o, path):
    """Write o alone as a GLB (Y up) with its class materials and no images."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_image_format="NONE")


def isolate(keep):
    """Remove every object not in keep."""
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o)


# [variant name, source dir, object filter regex, drop regex, material rule, scale, triangle budget]
H49 = [("PLASTER", "plaster"), ("BRICK", "brick"), ("WOOD", "wood"), ("STONE", "stone"), ("BLACK", "dark"),
       ("FABRIC", "cloth")]
H51 = [("lambert2$|lambert15$", "plaster"), ("lambert3$|lambert4$|blinn1$|lambert11$|lambert12$|lambert13$", "wood"),
       ("lambert8$", "dark"), ("lambert10$", "cloth")]
VARIANTS = [
    ("h49", "h49", r".", r"GROUND|SAND_02", H49, 0.01, 1000),
    ("h51", "h51", r".", r"knob_ring|pCylinder", H51, 1.9, 500),
]


def main():
    """Build every house variant and the well; print the size table for VillageHouses.VARIANTS."""
    dl, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    rows = []
    for name, src, pick, drop, rule, scale, target in VARIANTS:
        obs = load(os.path.join(dl, src, "src.glb"))
        keep = [o for o in obs if re.search(pick, o.name) and not re.search(drop, o.name)]
        isolate(keep)
        o, size = build_variant(keep, rule, scale, target)
        t = sum(len(p.vertices) - 2 for p in o.data.polygons)
        export(o, os.path.join(out, "vh_%s.glb" % name))
        rows.append('\t"%s": Vector3(%.2f, %.2f, %.2f),   # %d tris' % (name, size.x, size.z, size.y, t))
        print("VARIANT", name, "size x/depth/height", tuple(round(v, 2) for v in size), "tris", t)
    # well: the scan keeps its texture, decimated; its paving is cut to the concrete slab
    obs = load(os.path.join(dl, "w71", "src.glb"))
    o = obs[0]
    md = o.modifiers.new("col", "DECIMATE")
    md.ratio = 300 / max(1, len(o.data.polygons))
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="col")
    vs = [v.co for v in o.data.vertices]
    mn = Vector(map(min, *vs))
    mx = Vector(map(max, *vs))
    c = (mn + mx) / 2
    o.data.transform(Matrix.Translation(Vector((-c.x, -c.y, -mn.z))))
    for img in bpy.data.images:
        if img.size[0] > 512:
            img.scale(512, 512)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "vh_well.glb"), export_format="GLB", use_selection=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
    print("VARIANT well size", tuple(round(v, 2) for v in mx - mn), "tris", sum(len(p.vertices) - 2 for p in o.data.polygons))
    print("\n".join(rows))


main()
