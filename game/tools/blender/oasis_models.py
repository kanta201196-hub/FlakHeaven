"""Highlands oasis models from CC BY Sketchfab sources (VIS-01, Kanta 26.10: «Оазис: 66 … 70»).
  b12_date_palm  — date palm (Date Palm, evolveduk): the frond cards keep their alpha texture, the trunk is
                   decimated; fronds toned to the dusty olive of the Highlands orchards, bark warm grey-brown;
  b13_oasis_well — well (Desert Environment Well, Bhaddou): stone ring and plank cover, toned to the stone and
                   wood textures of the fortified area (art/fort) so the oasis matches it.
Everything matte (roughness 1, metallic 0). Units as the other biome models (tools/model_lab/biome_prep.py):
standing on z = 0 (y = 0 in Godot), centred, the largest size in plan = 1; biome_props.gd scales by width.
Run (bpy 5.x): python3 -I oasis_models.py <palm.glb> <well.glb> <out_dir>
  → <out_dir>/b12_date_palm.glb, b13_oasis_well.glb
The palm's light cards for presets below «Максимальное»: tools/model_lab/bake_impostor.gd -- b12_date_palm."""
import sys, os
import numpy as np
import bpy
from mathutils import Vector, Matrix

PALM, WELL, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
FROND_RGB = (88, 96, 52)      # mean of the orchard leaves (b05) — the same dusty olive in the light of the game
BARK_RGB = (112, 96, 78)
STONE_RGB = (135, 119, 99)    # art/fort/stone_color.jpg mean
WOOD_RGB = (98, 85, 71)       # art/fort/wood_color.jpg mean


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


def tone(img, rgb, size, alpha=False):
    """Scale the texture so its mean colour (opaque pixels) becomes `rgb`; slightly desaturated; resized"""
    if max(img.size) > size:
        k = size / max(img.size)
        img.scale(max(1, round(img.size[0] * k)), max(1, round(img.size[1] * k)))
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    m = a[..., 3] > 0.5 if alpha else np.ones((h, w), bool)
    # Image.pixels of a colour texture are in its own (sRGB) colour space
    srgb = np.clip(a[..., :3], 0, 1)
    grey = srgb.mean(axis=2, keepdims=True)
    srgb = grey + (srgb - grey) * 0.85
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


def export(obs, name):
    for o in bpy.context.scene.objects:
        o.select_set(o in obs)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    print("TRIS", name, sum(len(p.vertices) - 2 for p in ob.data.polygons))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_image_format="JPEG")   # the frond texture keeps its alpha as PNG


os.makedirs(OUT, exist_ok=True)

# --- date palm: Tree_0 trunk core, Tree_1 frond cards (alpha), Tree_2 trunk bark shell, Tree_3 crown base ---
obs = load(PALM)
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
export(obs, "b12_date_palm")

# --- well: Object_2 stone ring, Object_3 plank cover ---
obs = load(WELL)
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
export(obs, "b13_oasis_well")
print("DONE")
