"""Village clutter and market props for the Highland kishlak (VIS-01, Kanta 26.10.2026: «Все по твоим рекомендациям -
ок»; «В кишлаке в центре предлагаю поставить палатки какие-нибудь, имитировать рынок»).

Sources are CC BY Sketchfab models (game/models/CREDITS.md) plus a few props built here in the «Укрепрайон» manner
(texture set Г classes and faded cloth): market tents in three cloth colours, a tandoor, a rug hung on a frame.
Two kinds of output, both metres, long side along X, centred on the footprint, base on z = 0, matte:
  class props — every face gets a material class (vh_wood, vh_plaster, vh_cloth…; VillageHouses.material paints
    them), so the stall, the awning and the cart read as the same timber and cloth as the houses;
  textured props — one texture per prop, desaturated toward the village's dust, normal/roughness maps dropped,
    downscaled (bags, pots, hay, woodpile, trough, rug): their own pattern is what reads at 10–20 px.
Each prop is decimated to a budget for a 5–25 px object (1 m ≈ 6.94 px at zoom 1).

Run (from the repo root; the sources are untrusted downloads, so -I):
  python3 -I game/tools/blender/village_props.py <dl_dir> <out_dir>
    <dl_dir>/{stall,awning,cart,bags,pots,rug,hay,wood,trough}/src.glb -> <out_dir>/vc_<name>.glb, sizes printed as
    a GDScript table for VillageHouses.PROPS
"""
import math
import os
import re
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

TILE = {"plaster": 4.6, "wood": 5.0, "dark": 8.0}   # FortBuild SETS tile, metres; flat classes use any
CLASSES = ["plaster", "wood", "dark", "cloth", "cloth2", "cloth3", "clay", "straw", "bag"]
DUST = np.array([0.62, 0.55, 0.46], dtype=np.float32)   # the village's dry clay, linear-ish albedo


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
        o.matrix_world = Matrix.Identity(4)
        obs.append(o)
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    return obs


def base_image(mat):
    """Image linked to the base colour of a Principled material, or None."""
    if mat is None or mat.node_tree is None:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            for l in n.inputs["Base Color"].links:
                if l.from_node.type == "TEX_IMAGE" and l.from_node.image is not None:
                    return l.from_node.image
    return None


def uses_alpha(mat):
    """The material's alpha comes from its texture (straw cards)."""
    if mat is None or mat.node_tree is None:
        return False
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return bool(n.inputs["Alpha"].links)
    return False


def grade(img, size, desat=0.45, tint=(1.0, 0.95, 0.86), dust=0.18):
    """Downscale img to size and pull it toward the village's faded, dusty palette (matte look comes from the
    material: roughness 1, no maps). Keeps alpha."""
    if img.size[0] > size or img.size[1] > size:
        img.scale(size, size)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(-1, 4)
    rgb = a[:, :3]
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    rgb = rgb + (lum[:, None] - rgb) * desat
    rgb = rgb * np.array(tint, dtype=np.float32)
    rgb = rgb + (DUST - rgb) * dust
    a[:, :3] = np.clip(rgb, 0.0, 1.0)
    img.pixels.foreach_set(a.ravel())
    img.update()


def new_mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    return m


def tex_mat(name, img, alpha):
    """Matte material with only a base colour texture (and its alpha when the source used it)."""
    m = new_mat(name)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"])
    if alpha:
        nt.links.new(tx.outputs["Alpha"], bs.inputs["Alpha"])
        try:
            m.surface_render_method = "DITHERED"
        except AttributeError:
            pass
    bs.inputs["Roughness"].default_value = 1.0
    bs.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bs.inputs:
        bs.inputs["Specular IOR Level"].default_value = 0.2
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return m


def class_mats():
    return [new_mat("vh_" + c) for c in CLASSES]


def join(obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def normalize(o, scale, turn=True):
    """Scale to metres, long side along X, centred on the footprint, base on z = 0."""
    o.data.transform(Matrix.Scale(scale, 4))
    vs = [v.co for v in o.data.vertices]
    mn = Vector(map(min, *vs))
    mx = Vector(map(max, *vs))
    if turn and (mx.y - mn.y) > (mx.x - mn.x) * 1.05:
        o.data.transform(Matrix.Rotation(math.pi / 2, 4, "Z"))
        vs = [v.co for v in o.data.vertices]
        mn = Vector(map(min, *vs))
        mx = Vector(map(max, *vs))
    c = (mn + mx) / 2
    o.data.transform(Matrix.Translation(Vector((-c.x, -c.y, -mn.z))))


def decimate(o, target, planar=True):
    """Collapse to the triangle budget; class props first merge doubles and flatten coplanar faces (textured ones
    skip that: merging across their UV seams tore the collapse, a burlap pile kept 1400 triangles and lost a third
    of its size)."""
    if planar:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)
        bm.to_mesh(o.data)
        bm.free()
    bpy.context.view_layer.objects.active = o
    if tris(o) > target and planar:
        md = o.modifiers.new("pl", "DECIMATE")
        md.decimate_type = "DISSOLVE"
        md.angle_limit = math.radians(2.0)
        md.delimit = {"MATERIAL", "UV"}
        bpy.ops.object.modifier_apply(modifier="pl")
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.quads_convert_to_tris()
        bpy.ops.object.mode_set(mode="OBJECT")
    t = tris(o)
    if t > target:
        md = o.modifiers.new("col", "DECIMATE")
        md.ratio = target / t
        md.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="col")


def box_uvs(o):
    """Box-projected UVs in metres / tile of the face's class (as FortBuild._tri), one UV layer."""
    me = o.data
    uvl = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        n = p.normal
        cls = me.materials[p.material_index].name[3:] if me.materials else "plaster"
        k = 1.0 / TILE.get(cls, 2.0)
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


def flat_shade(o):
    for p in o.data.polygons:
        p.use_smooth = False


def export(o, path, images):
    """Write o alone as a GLB (Y up); textured props embed their images (JPEG, PNG where alpha is used)."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    for im in bpy.data.images:
        im.file_format = "PNG" if im.get("alpha") else "JPEG"
    fmt = "NONE" if not images else ("AUTO" if any(im.get("alpha") for im in bpy.data.images) else "JPEG")
    kw = {}
    if fmt != "NONE":
        kw["export_jpeg_quality"] = 85
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_materials="EXPORT", export_image_format=fmt, **kw)


def size_of(o):
    vs = [v.co for v in o.data.vertices]
    return Vector(map(max, *vs)) - Vector(map(min, *vs))


# ---- source props -------------------------------------------------------------------------------------------------

def class_prop(obs, rule):
    """Join obs and give each face a material class by its source material name (first matching regex)."""
    mats = class_mats()
    for o in obs:
        idx = []
        for p in o.data.polygons:
            m = o.data.materials[p.material_index] if o.data.materials else None
            name = m.name if m else ""
            cls = "wood"
            for pat, c in rule:
                if re.search(pat, name):
                    cls = c
                    break
            idx.append(CLASSES.index(cls))
        o.data.materials.clear()
        for m in mats:
            o.data.materials.append(m)
        for p, i in zip(o.data.polygons, idx):
            p.material_index = i
    return join(obs)


def drop_unused_slots(o):
    """Remove material slots no face uses (each slot is a surface: a draw call per MultiMesh)."""
    used = {p.material_index for p in o.data.polygons}
    bpy.context.view_layer.objects.active = o
    for i in reversed(range(len(o.material_slots))):
        if i not in used:
            o.active_material_index = i
            bpy.ops.object.material_slot_remove()


def two_sided(o):
    """Add a reversed copy of every face, so open sheets show from both sides under back-face culling."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    faces = list(bm.faces)
    r = bmesh.ops.duplicate(bm, geom=faces)
    dup = [g for g in r["geom"] if isinstance(g, bmesh.types.BMFace)]
    bmesh.ops.reverse_faces(bm, faces=dup)
    bm.to_mesh(o.data)
    bm.free()


def tex_prop(name, obs, size, k):
    """Join obs with one graded, matte texture material per distinct source image; k scales its brightness."""
    by_img = {}
    for o in obs:
        for m in o.data.materials:
            img = base_image(m)
            if img is not None and img.name not in by_img:
                alpha = uses_alpha(m)
                grade(img, size, tint=(k, k * 0.95, k * 0.86))
                img["alpha"] = alpha
                by_img[img.name] = tex_mat("vt_%s_%d" % (name, len(by_img)), img, alpha)
    for o in obs:
        remap = []
        for m in o.data.materials:
            img = base_image(m)
            remap.append(by_img[img.name] if img is not None else list(by_img.values())[0])
        idx = [p.material_index for p in o.data.polygons]
        o.data.materials.clear()
        uniq = []
        for m in remap:
            if m not in uniq:
                uniq.append(m)
        for m in uniq:
            o.data.materials.append(m)
        for p, i in zip(o.data.polygons, idx):
            p.material_index = uniq.index(remap[i])
    o = join(obs)
    # unify slots that point at the same material after the join
    me = o.data
    first = {}
    idx = []
    for p in me.polygons:
        m = me.materials[p.material_index]
        first.setdefault(m.name, len(first))
        idx.append(first[m.name])
    order = sorted(first, key=first.get)
    me.materials.clear()
    for n in order:
        me.materials.append(bpy.data.materials[n])
    for p, i in zip(me.polygons, idx):
        p.material_index = i
    for im in list(bpy.data.images):
        if im.users == 0 or im.name not in by_img:
            if im.name not in by_img:
                bpy.data.images.remove(im)
    return o


STALL_KEEP = r"tenda\.012_leather|tenda\.012_pole|Crate_low\.15[36]|Terakota|Wicker-non-pbr|Kursi"
STALL_RULE = [("leather", "cloth"), ("Terakota", "clay"), (".", "wood")]   # wicker as wood: a surface is a draw call
AWNING_RULE = [("tarp", "cloth"), (".", "wood")]
CART_RULE = [(".", "wood")]   # iron bindings read as dark wood at 15 px; one surface

# [name, source dir, keep regex, drop regex, class rule | (texture size, brightness), scale to metres, triangle
# budget]. Class props are made two-sided afterwards (their tarps, planks and cloths are open sheets: the class
# materials cull back faces), so they end at twice the budget
SOURCES = [
    ("stall", "stall", STALL_KEEP, r"^$", STALL_RULE, 1.0, 300),
    ("awning", "awning", r".", r"^$", AWNING_RULE, 1.0, 200),
    ("cart", "cart", r".", r"^$", CART_RULE, 0.01, 150),
    ("bags", "bags", r".", r"^$", (256, 0.78), 1.0, 300),
    ("pots", "pots", r".", r"^$", (256, 0.95), 0.01, 350),
    ("rug", "rug", r".", r"^$", (512, 0.85), 2.5, 60),
    ("hay", "hay", r".", r"^$", (256, 0.9), 1.0, 300),
    ("wood", "wood", r".", r"^$", (256, 0.8), 0.02, 300),
    ("trough", "trough", r".", r"Anvil", (256, 0.9), 0.01, 300),
]


def build_source(dl, out, row):
    name, src, keep, drop, rule, scale, target = row
    obs = load(os.path.join(dl, src, "src.glb"))
    keepo = [o for o in obs if re.search(keep, o.name) and not re.search(drop, o.name)]
    for o in list(bpy.data.objects):
        if o not in keepo:
            bpy.data.objects.remove(o)
    if isinstance(rule, list):
        # each part to its share of the budget: one collapse over the whole prop ate the awning's thin frame
        total = sum(tris(p) for p in keepo)
        for p in keepo:
            decimate(p, max(12, int(target * tris(p) / total)))
        o = class_prop(keepo, rule)
        normalize(o, scale)
        drop_unused_slots(o)
        two_sided(o)
        box_uvs(o)
        flat_shade(o)
        images = False
    else:
        o = tex_prop(name, keepo, rule[0], rule[1])
        normalize(o, scale)
        decimate(o, target, planar=name == "rug")   # the flat rug dissolves to a few faces
        images = True
    export(o, os.path.join(out, "vc_%s.glb" % name), images)
    return o


# ---- props built here ---------------------------------------------------------------------------------------------

def _box(bm, c, s, mi):
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]:
        v.co = Vector((c[0] + v.co.x * s[0], c[1] + v.co.y * s[1], c[2] + v.co.z * s[2]))
    for f in {f for v in r["verts"] for f in v.link_faces}:
        f.material_index = mi


def _quad(bm, pts, mi, both=True):
    vs = [bm.verts.new(p) for p in pts]
    f = bm.faces.new(vs)
    f.material_index = mi
    if both:
        vs2 = [bm.verts.new(p) for p in reversed(pts)]
        f2 = bm.faces.new(vs2)
        f2.material_index = mi
    return f


def _mesh_object(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def build_tent(out, cloth):
    """Market tent: a gabled cloth canopy (3.6 × 3.2 m, eaves 2 m) on six poles over a timber counter with a few
    goods. One GLB per cloth colour class, so a row of tents gets two or three faded colours."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = class_mats()
    W, D, E, R = 1.8, 1.6, 1.95, 2.55
    ci = CLASSES.index(cloth)
    wi = CLASSES.index("wood")
    bm = bmesh.new()
    for sy in (-1, 1):   # roof slopes and the valance along the eaves
        _quad(bm, [(-W, 0, R), (W, 0, R), (W, sy * D, E), (-W, sy * D, E)], ci)
        _quad(bm, [(-W, sy * D, E), (W, sy * D, E), (W, sy * D, E - 0.32), (-W, sy * D, E - 0.32)], ci)
    for sx in (-1, 1):   # gable ends
        f = [bm.verts.new(p) for p in [(sx * W, -D, E), (sx * W, D, E), (sx * W, 0, R)]]
        bm.faces.new(f).material_index = ci
        f = [bm.verts.new(p) for p in [(sx * W, 0, R), (sx * W, D, E), (sx * W, -D, E)]]
        bm.faces.new(f).material_index = ci
    for sx in (-1, 1):
        for sy in (-1, 1):
            _box(bm, (sx * (W - 0.12), sy * (D - 0.15), E / 2), (0.08, 0.08, E), wi)
        _box(bm, (sx * (W - 0.12), 0, R / 2), (0.08, 0.08, R), wi)
    _box(bm, (0, -D + 0.55, 0.4), (3.0, 0.7, 0.8), wi)   # counter
    for k, x in enumerate((-1.0, -0.3, 0.45, 1.1)):   # goods: crates (timber, as the frame: a surface is a draw call)
        _box(bm, (x, -D + 0.55, 0.92), (0.45, 0.4, 0.24 + 0.06 * (k % 2)), wi)
    _box(bm, (0.6, 0.6, 0.35), (0.9, 0.7, 0.7), wi)   # crates at the back
    o = _mesh_object("tent", bm, mats)
    drop_unused_slots(o)
    box_uvs(o)
    flat_shade(o)
    name = {"cloth": "tent_a", "cloth2": "tent_b", "cloth3": "tent_c"}[cloth]
    export(o, os.path.join(out, "vc_%s.glb" % name), False)
    return name, o


def build_tandoor(out):
    """Tandoor: a clay oven (truncated cone, open mouth on top) on a plastered plinth."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = class_mats()
    pi = CLASSES.index("plaster")
    di = CLASSES.index("dark")
    bm = bmesh.new()
    _box(bm, (0, 0, 0.14), (1.5, 1.5, 0.28), pi)
    n = 12
    z0, z1, r0, r1, rm = 0.28, 1.15, 0.62, 0.36, 0.22
    lo = [bm.verts.new((r0 * math.cos(a), r0 * math.sin(a), z0)) for a in (2 * math.pi * k / n for k in range(n))]
    hi = [bm.verts.new((r1 * math.cos(a), r1 * math.sin(a), z1)) for a in (2 * math.pi * k / n for k in range(n))]
    mo = [bm.verts.new((rm * math.cos(a), rm * math.sin(a), z1)) for a in (2 * math.pi * k / n for k in range(n))]
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new([lo[k], lo[j], hi[j], hi[k]]).material_index = pi
        bm.faces.new([hi[k], hi[j], mo[j], mo[k]]).material_index = pi
    bm.faces.new(list(reversed([bm.verts.new((v.co.x, v.co.y, z1 - 0.08)) for v in mo]))).material_index = di
    bm.normal_update()
    o = _mesh_object("tandoor", bm, mats)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    drop_unused_slots(o)
    box_uvs(o)
    flat_shade(o)
    export(o, os.path.join(out, "vc_tandoor.glb"), False)
    return o


def build_rug_frame(dl, out):
    """Rugs hung out on a timber frame (two posts and a bar): the rug's own graded texture on a two-sided sheet."""
    obs = load(os.path.join(dl, "rug", "src.glb"))
    img = base_image(obs[0].data.materials[0])
    grade(img, 512, tint=(0.85, 0.85 * 0.95, 0.85 * 0.86))   # as the rug on the ground (SOURCES)
    img["alpha"] = False
    rug = tex_mat("vt_rugframe_0", img, False)
    for o in obs:
        bpy.data.objects.remove(o)
    mats = class_mats() + [rug]
    ri = len(mats) - 1
    wi = CLASSES.index("wood")
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    for sx in (-1, 1):
        _box(bm, (sx * 1.35, 0, 1.1), (0.09, 0.09, 2.2), wi)
    _box(bm, (0, 0, 2.12), (2.9, 0.08, 0.08), wi)
    for x0, x1, z0, side in ((-1.2, 0.05, 0.45, 0.03), (0.1, 1.2, 0.8, -0.03)):   # two rugs side by side
        pts = [(x0, side, z0), (x1, side, z0), (x1, side, 2.08), (x0, side, 2.08)]
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for order in (pts, list(reversed(pts))):
            f = bm.faces.new([bm.verts.new(p) for p in order])
            f.material_index = ri
            for lp in f.loops:
                q = lp.vert.co
                lp[uvl].uv = ((q.x - x0) / (x1 - x0), (q.z - z0) / (2.08 - z0))
    o = _mesh_object("rugframe", bm, mats)
    # box UVs for the wood only; the rug sheet keeps its 0..1 mapping
    me = o.data
    uv = me.uv_layers.active
    for p in me.polygons:
        if p.material_index == ri:
            continue
        n = p.normal
        for li in p.loop_indices:
            q = me.vertices[me.loops[li].vertex_index].co
            u = (q.x, q.y) if abs(n.z) > 0.75 else ((q.y, q.z) if abs(n.x) >= abs(n.y) else (q.x, q.z))
            uv.data[li].uv = (u[0] / TILE["wood"], u[1] / TILE["wood"])
    drop_unused_slots(o)
    flat_shade(o)
    export(o, os.path.join(out, "vc_rugframe.glb"), True)
    return o


def main():
    """Build every prop; print the size table for VillageHouses.PROPS."""
    dl, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    rows = []

    def row(name, o):
        s = size_of(o)
        t = tris(o)
        rows.append('\t"vc_%s": Vector3(%.2f, %.2f, %.2f),   # %d tris, %d surfaces' % (name, s.x, s.z, s.y, t, len(o.data.materials)))
        print("PROP", name, "size x/depth/height", tuple(round(v, 2) for v in s), "tris", t, "surfaces", len(o.data.materials))

    for r in SOURCES:
        row(r[0], build_source(dl, out, r))
    for cl in ("cloth", "cloth2", "cloth3"):
        n, o = build_tent(out, cl)
        row(n, o)
    row("tandoor", build_tandoor(out))
    row("rugframe", build_rug_frame(dl, out))
    print("\n".join(rows))


main()
