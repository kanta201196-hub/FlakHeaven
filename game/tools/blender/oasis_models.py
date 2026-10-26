"""Highlands oasis models from CC BY Sketchfab sources (VIS-01, Kanta 26.10: oasis from models 66 to 70).
  b12_date_palm  — date palm (Date Palm, evolveduk): the frond cards keep their alpha texture, the trunk is
                   decimated; fronds toned to the dusty olive of the Highlands orchards, bark warm grey-brown;
  b13_oasis_well — well (Desert Environment Well, Bhaddou): stone ring and plank cover, toned to the stone and
                   wood textures of the fortified area (art/fort) so the oasis matches it;
  b14_oasis_bush — tamarisk bush (Realistic HD French tamarisk 11/20, PlantCatalog; Kanta 26.10): its alpha leaf
                   cards become alpha-scissor (glTF MASK) so they cut out the same way in Forward+ and in the GL
                   Compatibility fallback; foliage toned to the palms' dusty olive with a vertex-colour height
                   gradient (lower leaves paler and dustier), bark decimated.
Everything matte (roughness 1, metallic 0). Units as the other biome models (tools/model_lab/biome_prep.py):
standing on z = 0 (y = 0 in Godot), centred, the largest size in plan = 1; biome_props.gd scales by width.
Run (bpy 5.x; sources are untrusted downloads, so -I):
  python3 -I oasis_models.py <palm.glb> <well.glb> <out_dir>  → <out_dir>/b12_date_palm.glb, b13_oasis_well.glb
  python3 -I oasis_models.py --bush <tamarisk.glb> <out_dir>  → <out_dir>/b14_oasis_bush.glb
The palm's light cards for presets below Maximum: tools/model_lab/bake_impostor.gd -- b12_date_palm."""
import sys, os
import numpy as np
import bpy
from mathutils import Vector, Matrix

FROND_RGB = (88, 96, 52)      # mean of the orchard leaves (b05) — the same dusty olive in the light of the game
BARK_RGB = (112, 96, 78)
STONE_RGB = (135, 119, 99)    # art/fort/stone_color.jpg mean
WOOD_RGB = (98, 85, 71)       # art/fort/wood_color.jpg mean
# tamarisk: the leaf texture is toned to the pale dust of the lower leaves; the vertex colour (linear, multiplied
# by the albedo in Godot) darkens the upper leaves by BUSH_TOP (sRGB ratio) to the palms' olive, 12 % darker:
# the bush's up-leaning card normals (two_sided_cards) catch more sun than the palm fronds
BUSH_TOP = (0.80, 0.88, 0.70)
BUSH_DUST_RGB = tuple(round(c * 0.88 / k) for c, k in zip(FROND_RGB, BUSH_TOP))   # ≈ (97, 96, 65): dusty khaki
BUSH_BARK_RGB = (104, 86, 72)  # tamarisk bark: a little redder than the palm's
LEAF_CUTOFF = 0.25            # alpha-scissor threshold of the leaf cards: low, so the mip levels (alpha averaged
                              # to the leaf cover, ~0.35) still draw a bush at game distance instead of nothing


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in obs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    return obs


def bounds(obs):
    vs = [v.co for o in obs for v in o.data.vertices]
    return Vector([min(v[i] for v in vs) for i in range(3)]), Vector([max(v[i] for v in vs) for i in range(3)])


def normalize(obs, centre=None):
    """Stand on z = 0, centre in plan at `centre` (or the bounds centre), largest plan size = 1"""
    mn, mx = bounds(obs)
    c = centre if centre is not None else (mn + mx) / 2
    s = 1.0 / max(mx.x - mn.x, mx.y - mn.y)
    m = Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-c.x, -c.y, -mn.z)))
    for o in obs:
        o.data.transform(m)


def decimate(o, tris):
    t = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if t <= tris:
        return
    bpy.context.view_layer.objects.active = o
    md = o.modifiers.new("dc", "DECIMATE")
    md.ratio = tris / t
    md.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=md.name)


def tone(img, rgb, size, alpha=False, sat=0.85):
    """Scale the texture so its mean colour (opaque pixels) becomes `rgb`; desaturated to `sat`; resized"""
    if max(img.size) > size:
        k = size / max(img.size)
        img.scale(max(1, round(img.size[0] * k)), max(1, round(img.size[1] * k)))
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    m = a[..., 3] > 0.5 if alpha else np.ones((h, w), bool)
    # Image.pixels of a colour texture are in its own (sRGB) colour space
    srgb = np.clip(a[..., :3], 0, 1)
    grey = srgb.mean(axis=2, keepdims=True)
    srgb = grey + (srgb - grey) * sat
    mean = srgb[m].mean(axis=0)
    srgb = np.clip(srgb * (np.array(rgb) / 255.0) / np.maximum(mean, 1e-3), 0, 1)
    a[..., :3] = srgb
    img.pixels[:] = a.ravel()
    img.update()
    img.pack()


def matte(mat):
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    for sock in ("Metallic", "Roughness", "Specular Tint"):
        for l in list(nt.links):
            if l.to_node == b and l.to_socket.name == sock:
                nt.links.remove(l)
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.15


def base_image(mat):
    b = mat.node_tree.nodes["Principled BSDF"]
    for l in mat.node_tree.links:
        if l.to_node == b and l.to_socket.name == "Base Color":
            return getattr(l.from_node, "image", None)
    return None


def shrink_normals(mat, size):
    for n in mat.node_tree.nodes:
        img = getattr(n, "image", None)
        if img is not None and img != base_image(mat) and max(img.size) > size:
            img.scale(size, size)
            img.pack()


def export(obs, name, out, colors=False):
    """Join `obs` into one object called `name` and write <out>/<name>.glb (JPEG colour, alpha textures stay PNG);
    colors: also write the active colour attribute as COLOR_0 (the bush's dust gradient)"""
    for o in bpy.context.scene.objects:
        o.select_set(o in obs)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    print("TRIS", name, sum(len(p.vertices) - 2 for p in ob.data.polygons))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format="GLB", use_selection=True,
                              export_image_format="JPEG",   # the frond texture keeps its alpha as PNG
                              export_vertex_color="ACTIVE" if colors else "MATERIAL")


def alpha_clip(mat, cutoff):
    """Turn the source's blended alpha into a clip: alpha > cutoff, which the glTF exporter writes as alphaMode MASK
    (Godot: alpha scissor, drawn the same in Forward+ and Compatibility, no sorting, casts cut-out shadows)"""
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    for l in list(nt.links):
        if l.to_node == b and l.to_socket.name == "Alpha":
            src = l.from_socket
            nt.links.remove(l)
            gt = nt.nodes.new("ShaderNodeMath")
            gt.operation = "GREATER_THAN"
            gt.inputs[1].default_value = cutoff
            nt.links.new(src, gt.inputs[0])
            nt.links.new(gt.outputs[0], b.inputs["Alpha"])
            return


def dust_gradient(obs, top_srgb, z0, z1):
    """Colour attribute "Color" (linear, per corner): white up to z0 (dusty lower leaves keep the texture's pale
    khaki), the sRGB ratio top_srgb from z1 up (the olive crown), smooth in between; every object gets it so the
    joined mesh has no black (missing) corners"""
    top = [c ** 2.2 for c in top_srgb]
    for o in obs:
        me = o.data
        attr = me.color_attributes.get("Color") or me.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
        me.color_attributes.active_color = attr
        leafy = any("brch" in m.name for m in me.materials)
        for li in me.loops:
            z = me.vertices[li.vertex_index].co.z
            t = min(max((z - z0) / (z1 - z0), 0.0), 1.0) if leafy else 0.0
            t = t * t * (3 - 2 * t)
            attr.data[li.index].color = (*[1.0 + (k - 1.0) * t for k in top], 1.0)


def palm(src, out):
    """b12_date_palm from the Date Palm source"""
    # --- date palm: Tree_0 trunk core, Tree_1 frond cards (alpha), Tree_2 trunk bark shell, Tree_3 crown base ---
    obs = load(src)
    base =[v.co for o in obs if o.data.materials[0].name.startswith("Tree_0") for v in o.data.vertices]
    mn_z = min(v.z for v in base)
    foot = [v for v in base if v.z < mn_z + 0.3]
    centre = Vector((sum(v.x for v in foot) / len(foot), sum(v.y for v in foot) / len(foot), 0))
    for o in obs:
        nm = o.data.materials[0].name
        if nm.startswith("Tree_2"):
            decimate(o, 700)
        elif nm.startswith("Tree_0"):
            decimate(o, 300)
        elif nm.startswith("Tree_3"):
            decimate(o, 300)
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        matte(m)
        img = base_image(m)
        if img is None:
            continue
        if m.name.startswith("Tree_1"):
            tone(img, FROND_RGB, 1024, alpha=True)
            m.use_backface_culling = False
        elif m.name.startswith("Tree_3"):
            tone(img, FROND_RGB, 512)
        else:
            tone(img, BARK_RGB, 512)
        shrink_normals(m, 512)
    normalize(obs, centre)
    export(obs, "b12_date_palm", out)


def well(src, out):
    """b13_oasis_well from the Desert Environment Well source"""
    # --- well: Object_2 stone ring, Object_3 plank cover ---
    obs = load(src)
    for o in obs:
        decimate(o, 2600 if o.data.materials[0].name.startswith("Brunnen") else 600)
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        matte(m)
        img = base_image(m)
        if img is not None:
            tone(img, STONE_RGB if m.name.startswith("Brunnen") else WOOD_RGB, 1024)
        shrink_normals(m, 1024)
    normalize(obs)
    export(obs, "b13_oasis_well", out)


def fatten_alpha(img, px):
    """Grow the opaque part of a leaf texture by `px` pixels (max filter), new pixels take the mean colour of their
    opaque neighbours; then every clear pixel gets the mean leaf colour. The tamarisk's leaves are thin: a bush is
    ~20 px wide in the game, and mip levels average the alpha (and the colour of clear pixels) of the whole sprig,
    so thin or dark-filled cards faded to a few dark specks"""
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    for _ in range(px):
        m = (a[..., 3] > LEAF_CUTOFF).astype(np.float32)
        acc = np.zeros((h, w, 3), np.float32)
        cnt = np.zeros((h, w), np.float32)
        amax = a[..., 3].copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh = np.roll(np.roll(a, dy, 0), dx, 1)
            shm = np.roll(np.roll(m, dy, 0), dx, 1)
            acc += sh[..., :3] * shm[..., None]
            cnt += shm
            amax = np.maximum(amax, sh[..., 3])
        grow = (m == 0) & (cnt > 0)
        a[grow, :3] = acc[grow] / cnt[grow, None]
        a[grow, 3] = amax[grow]
    # the clear pixels take the mean leaf colour: mip levels average them in, and the source's dark fill turned
    # distant bushes into black specks
    m = a[..., 3] > LEAF_CUTOFF
    a[~m, :3] = a[m, :3].mean(axis=0)
    img.pixels[:] = a.ravel()
    img.update()


def two_sided_cards(o, centre):
    """Leaf cards as two one-sided layers (the faces duplicated with reversed winding) with custom normals leaning
    up and out from the bush axis. A double-sided card flips its normal on the back face, so with up-leaning normals
    half the cards went dark under the high sun; one-sided pairs light every card like the top of a crown, the same
    way in Forward+ and Compatibility. Doubles the card triangles"""
    import bmesh
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    dup = bmesh.ops.duplicate(bm, geom=list(bm.faces))
    bmesh.ops.reverse_faces(bm, faces=[g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)])
    bm.to_mesh(me)
    bm.free()
    rmax = max((Vector((v.co.x - centre.x, v.co.y - centre.y)).length for v in me.vertices), default=1.0)
    ns = []
    for li in me.loops:
        co = me.vertices[li.vertex_index].co
        rad = Vector((co.x - centre.x, co.y - centre.y, 0.0)) / max(rmax, 1e-6)
        ns.append((rad * 0.6 + Vector((0.0, 0.0, 0.8))).normalized())
    me.normals_split_custom_set(ns)


def bush(src, out):
    """b14_oasis_bush from the tamarisk source: Tamarix_bark_0* trunk and branches (decimated), Tamarix_brch_*
    alpha leaf cards (kept whole: decimating a card breaks its UVs; made two-sided, two_sided_cards), all six
    objects joined into one mesh. Its Godot import keeps meshes/generate_lods off: the automatic LOD collapsed the
    leaf cards, and at game distance only the bare branches were drawn"""
    obs = load(src)
    mn, mx = bounds(obs)
    centre = (mn + mx) / 2
    for o in obs:
        if o.data.materials[0].name.startswith("Tamarix_bark"):
            decimate(o, 220)
        else:
            two_sided_cards(o, centre)
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        matte(m)
        img = base_image(m)
        if img is None:
            continue
        if "brch" in m.name:
            fatten_alpha(img, 2)
            tone(img, BUSH_DUST_RGB, 1024, alpha=True, sat=0.4)   # the source green is lush; dusty shrub
            alpha_clip(m, LEAF_CUTOFF)
            m.use_backface_culling = True
        else:
            tone(img, BUSH_BARK_RGB, 512)
        shrink_normals(m, 512)
    for o in obs:   # the source carries 2-3 UV sets (lightmap, wind data); the textures use the render one
        for uv in [u for u in o.data.uv_layers if not u.active_render]:
            o.data.uv_layers.remove(uv)
    normalize(obs)
    _, mx = bounds(obs)
    dust_gradient(obs, BUSH_TOP, 0.15 * mx.z, 0.7 * mx.z)
    export(obs, "b14_oasis_bush", out, colors=True)


def main(argv):
    """Command line: palm and well (two sources) or --bush (one source); see the module docstring"""
    if argv[:1] == ["--bush"]:
        os.makedirs(argv[2], exist_ok=True)
        bush(argv[1], argv[2])
    else:
        os.makedirs(argv[2], exist_ok=True)
        palm(argv[0], argv[2])
        well(argv[1], argv[2])
    print("DONE")


if __name__ == "__main__":
    main(sys.argv[1:])
