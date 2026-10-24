"""Rework a downloaded Sketchfab model into a battle GLB for the game (VIS-01, Kanta 24.10.2026).

Pipeline (Blender as the `bpy` module, 5.2):
  1. import the source GLB, drop lights/cameras/empties, bake every transform into the mesh data;
  2. orient (recipe `rot`), scale to length 1 along X (nose +X, up +Z in Blender = +Y in glTF), ground on z = 0
     (or centred for aircraft), as in tools/model_lab/model_lab.gd;
  3. split into the game's moving nodes (wheel_*, turret, rotor, tail_rotor ...) by object name or by loose parts
     inside boxes, with pivots where the game rotates them (render3d.gd: _convoy_parts, _ground_parts, _rotors);
  4. repaint the high-poly source: every source material becomes an emission shader where "paint" pixels (by hue mask,
     whole material, or erased marking rectangles) get the game's camouflage in object space (convoy_kit palette),
     keeping the source luminance as detail (dirt, panel lines); then edge wear, dust, sun fade and AO;
     markings (stars, numbers, lettering) are painted over with the paint colour before the mask is built;
  5. decimate a copy per node to the triangle budget, one shared UV atlas, and bake high -> low
     (selected to active): colour, roughness, metallic and tangent-space normal (source normal maps + rounded edges);
  6. two materials like the code-built models (<root>_body, <root>_glass), ORM texture, export GLB, merge primitives.

Run (from the repo root; source files are untrusted downloads, so -I):
  python3 -I game/tools/blender/sf_rework.py <recipe> <src.glb> <out_dir> [--tex=2048] [--tris=12000] [--samples=16]
  -> <out_dir>/<recipe>.glb (+ _color/_normal/_orm .png for review).  Recipes: sf_recipes.py.
Dependencies: bpy 5.2.2 (pip module), numpy. No network.
"""
import argparse
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

import convoy_kit as K  # noqa: E402
from convoy_kit import _band, _m, _mix, _n, _noise, _sock  # noqa: E402
import sf_recipes  # noqa: E402

TOOLS = Path(__file__).resolve().parents[1]


# ---------------------------------------------------------------- scene helpers
def _select(obs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or obs[0]


def tris(obs) -> int:
    """Triangle count of mesh objects (n-gons counted as fans)."""
    return sum(len(p.vertices) - 2 for o in obs for p in o.data.polygons)


def bounds(obs):
    """World-space bounding box (min, max) of mesh objects."""
    vs = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    return Vector(map(min, *vs)), Vector(map(max, *vs))


def load(src: str):
    """Import a GLB, keep meshes only, bake world transforms into mesh data (identity objects)."""
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
    # degenerate / empty meshes break baking
    for o in list(obs):
        if not o.data.polygons:
            obs.remove(o)
            bpy.data.objects.remove(o)
    return obs


def xform(obs, m):
    for o in obs:
        o.data.transform(m)
        o.data.update()


def place(obs, R):
    """Rotate (recipe rot, degrees XYZ), scale length along X to 1, centre X/Y, ground or centre Z."""
    if R.get("rot"):
        rx, ry, rz = (math.radians(a) for a in R["rot"])
        xform(obs, Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X"))
    ref = [o for o in obs if not re.search(R.get("len_exclude", "^$"), o.name)] or obs
    mn, mx = bounds(ref)
    s = 1.0 / (mx.x - mn.x)
    xform(obs, Matrix.Scale(s, 4))
    mn, mx = bounds(ref)
    amn, amx = bounds(obs)
    cx = (mn.x + mx.x) / 2
    cy = (amn.y + amx.y) / 2
    cz = amn.z if R.get("ground", True) else (amn.z + amx.z) / 2
    xform(obs, Matrix.Translation((-cx, -cy, -cz)))
    if R.get("mirror_y"):
        pass
    mn, mx = bounds(obs)
    print("PLACE size", tuple(round(v, 3) for v in (mx - mn)), "min", tuple(round(v, 3) for v in mn))


def split_loose(obs, pattern):
    """Separate objects whose name matches pattern into loose parts (to assign them by position)."""
    out = []
    for o in obs:
        if not re.search(pattern, o.name):
            out.append(o)
            continue
        _select([o])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="LOOSE")
        bpy.ops.object.mode_set(mode="OBJECT")
        out.extend([x for x in bpy.context.selected_objects])
    return out


def _center(o):
    mn, mx = bounds([o])
    return (mn + mx) / 2


def _in_box(p, b):
    return b[0] <= p.x <= b[1] and b[2] <= p.y <= b[3] and b[4] <= p.z <= b[5]


def kill_box_faces(obs, boxes):
    """Delete faces whose centre lies in any of the boxes (x0, x1, y0, y1, z0, z1), normalised coordinates."""
    for o in obs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        dead = [f for f in bm.faces if any(_in_box(f.calc_center_median(), b) for b in boxes)]
        if dead:
            bmesh.ops.delete(bm, geom=dead, context="FACES")
            bm.to_mesh(o.data)
        bm.free()


def _make_proxies(obs, R):
    """Build simple stand-ins for the low mesh of parts that collapse decimation cannot shrink.

    Collapse stops at open borders and loose islands, so a track run made of hundreds of separate
    links, or a perforated grille plate, keeps tens of thousands of triangles whatever the ratio.
    R["low_voxel"] (name regex): those objects are fused by a voxel remesh (links become one belt);
    R["low_hull"] (name regex): those objects become their convex hull (a grille becomes a slab).
    The high objects stay untouched and are marked with the face attribute "fh_nolow", so the bake
    still projects their full detail onto the stand-in. Returns the list of proxy objects.
    """
    out = []
    for o in obs:
        how = None
        if R.get("low_voxel") and re.search(R["low_voxel"], o.name):
            how = "voxel"
        elif R.get("low_hull") and re.search(R["low_hull"], o.name):
            how = "hull"
        if not how:
            continue
        p = o.copy()
        p.data = o.data.copy()
        bpy.context.scene.collection.objects.link(p)
        if how == "hull":
            bm = bmesh.new()
            bm.from_mesh(p.data)
            hull = bmesh.ops.convex_hull(bm, input=bm.verts)
            keep = set(hull["geom"])
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES_ONLY")
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
            bm.to_mesh(p.data)
            bm.free()
        else:
            _select([p])
            md = p.modifiers.new("vx", "REMESH")
            md.mode = "VOXEL"
            md.voxel_size = R.get("voxel", 0.004)
            bpy.ops.object.modifier_apply(modifier="vx")
        p.data.attributes.new("fh_nolow", "BOOLEAN", "FACE")   # proxies are low-only, all False
        o.data.attributes.new("fh_nolow", "BOOLEAN", "FACE")
        o.data.attributes["fh_nolow"].data.foreach_set("value", [True] * len(o.data.polygons))
        p.name = "PROXY_" + o.name
        print("PROXY", how, o.name, tris([o]), "->", tris([p]))
        out.append(p)
    return out


def assign_groups(obs, R):
    """Map objects to game nodes: rule ("name", regex) or ("box", (x0,x1,y0,y1,z0,z1)) on the object centre."""
    groups = {g: [] for g in R.get("groups", {})}
    groups[""] = []
    for o in obs:
        c = _center(o)
        hit = ""
        for g, rules in R.get("groups", {}).items():
            for kind, arg in rules:
                mats = [m.name for m in o.data.materials if m]
                if (kind == "name" and re.search(arg, o.name)) or (kind == "box" and _in_box(c, arg)) \
                        or (kind == "mat" and any(re.search(arg, n) for n in mats)):
                    hit = g
                    break
            if hit:
                break
        o["fh_group"] = hit
        groups[hit].append(o)
    for g, v in groups.items():
        print("GROUP", g or "<root>", len(v), "objects", tris(v), "tris")
    R["_proxies"] = {g: _make_proxies(v, R) for g, v in groups.items()}
    # one high object per node: bake time grows with the number of selected source objects
    for g, v in groups.items():
        if len(v) > 1:
            _select(v)
            bpy.ops.object.join()
            groups[g] = [bpy.context.object]
    return {g: v for g, v in groups.items() if v}


def cut_wheels(obs, R):
    """Cut road wheels out of meshes whose faces are not connected parts (e.g. one welded-free shell):
    recipe wheel_cyl = {"steer": n, "axles": [x...], "z": zc, "r": radius, "y": (y_in, y_out)}; a face goes to a wheel
    when all its vertices are inside the cylinder (axis along Y) of that axle and side."""
    W = R["wheel_cyl"]
    axles = sorted(W["axles"], reverse=True)
    specs = []
    for ai, x in enumerate(axles):
        for side, sg in (("l", 1), ("r", -1)):
            nm = ("wheel_f%s" % ("" if ai == 0 else ai + 1) if ai < W["steer"] else "wheel_%d" % (ai - W["steer"] + 1)) + side
            specs.append((nm, x, sg))
    y0, y1 = W["y"]
    r = W["r"]
    zc = W["z"]
    out = []
    for o in obs:
        out.append(o)
        for nm, x, sg in specs:
            bm = bmesh.new()
            bm.from_mesh(o.data)

            def inside(v):
                return (v.co.x - x) ** 2 + (v.co.z - zc) ** 2 <= r * r and y0 <= v.co.y * sg <= y1
            idx = {f.index for f in bm.faces if all(inside(v) for v in f.verts)}
            bm.free()
            if not idx:
                continue
            _select([o])
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="DESELECT")
            bpy.ops.object.mode_set(mode="OBJECT")
            for p in o.data.polygons:
                p.select = p.index in idx
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.separate(type="SELECTED")
            bpy.ops.object.mode_set(mode="OBJECT")
            new = next(s for s in bpy.context.selected_objects if s != o)
            new.name = "WHEEL_" + nm
            out.append(new)
            R["groups"] = {nm: [("name", "^WHEEL_%s$" % nm)], **R.get("groups", {})}
            R.setdefault("pivots", {})[nm] = (x, sg * (y0 + y1) / 2, zc)
            print("WHEEL", nm, "faces", len(idx))
    return out


def find_wheels(obs, R):
    """Find road wheels among loose parts and name them for render3d.gd (_convoy_parts):
    tyres are disks standing on the ground (x and z size close, centre height ~ radius, off the centre line);
    hub parts (rims, nuts) that share a tyre's axis join it. Axles front to back: the first W["steer"] axles are
    wheel_f<n><side> (steered: begins with "wheel_f"), the rest wheel_<n><side>; side l = +Y (left), r = -Y."""
    W = R["wheels"]
    cand = [o for o in obs if re.search(W.get("match", "."), o.name)]
    tyres = []
    for o in cand:
        mn, mx = bounds([o])
        d = mx - mn
        c = (mn + mx) / 2
        r = max(d.x, d.z) / 2
        if r < W.get("rmin", 0.03) or r > W.get("rmax", 0.2):
            continue
        if abs(d.x - d.z) > 0.25 * 2 * r or d.y > 1.2 * r or abs(c.z - r) > 0.35 * r or abs(c.y) < W.get("ymin", 0.08):
            continue
        tyres.append([o, c, r])
    # merge tyre pieces sharing one axis (tread and sidewall as separate parts)
    wheels = []
    for o, c, r in sorted(tyres, key=lambda t: -t[2]):
        for w in wheels:
            if (Vector((c.x, c.z)) - Vector((w["c"].x, w["c"].z))).length < 0.4 * w["r"] and abs(c.y - w["c"].y) < w["r"]:
                w["parts"].append(o)
                break
        else:
            wheels.append({"c": c, "r": r, "parts": [o]})
    taken = {id(p) for w in wheels for p in w["parts"]}
    for o in obs:
        if id(o) in taken:
            continue
        mn, mx = bounds([o])
        c = (mn + mx) / 2
        d = mx - mn
        for w in wheels:
            near = (Vector((c.x, c.z)) - Vector((w["c"].x, w["c"].z))).length < 0.3 * w["r"]
            if near and abs(c.y - w["c"].y) < 0.8 * w["r"] and max(d.x, d.z) <= 2.05 * w["r"]:
                w["parts"].append(o)
                taken.add(id(o))
                break
    xs = sorted({round(w["c"].x, 2) for w in wheels}, reverse=True)
    axles = []
    for x in xs:
        if not axles or abs(axles[-1] - x) > 0.05:
            axles.append(x)
    steer = W.get("steer", 1)
    out = [o for o in obs if id(o) not in taken]
    for w in wheels:
        ai = min(range(len(axles)), key=lambda i: abs(axles[i] - w["c"].x))
        side = "l" if w["c"].y > 0 else "r"
        nm = ("wheel_f%s" % ("" if ai == 0 else ai + 1) if ai < steer else "wheel_%d" % (ai - steer + 1)) + side
        _select(w["parts"])
        bpy.ops.object.join()
        j = bpy.context.object
        j.name = "WHEEL_" + nm
        out.append(j)
        R["groups"] = {nm: [("name", "^WHEEL_%s$" % nm)], **R.get("groups", {})}   # wheels before box rules
        R.setdefault("pivots", {})[nm] = tuple(w["c"])
        print("WHEEL", nm, "c=(%.3f %.3f %.3f) r=%.3f parts=%d" % (w["c"].x, w["c"].y, w["c"].z, w["r"], len(w["parts"])))
    return out


# ---------------------------------------------------------------- source textures: markings and paint mask
def _px(img):
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def _hsv(rgb):
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 1e-4, d / np.maximum(mx, 1e-4), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, ((g - b) / dd) % 6, h)
    h = np.where(mx == g, (b - r) / dd + 2, h)
    h = np.where(mx == b, (r - g) / dd + 4, h)
    return h * 60.0, s, mx


def paint_mask(rgb, rule):
    """Pixels that are vehicle paint (to be repainted). rule: dict(hue=(lo, hi)..., smin, vmin, vmax)."""
    h, s, v = _hsv(rgb)
    m = np.zeros(h.shape, bool)
    for lo, hi in rule.get("hue", [(40, 170)]):
        m |= (h >= lo) & (h <= hi)
    m &= (s >= rule.get("smin", 0.12)) & (v >= rule.get("vmin", 0.08)) & (v <= rule.get("vmax", 1.0))
    if rule.get("gray"):   # grey paint (aircraft): low saturation, mid value
        g0, g1 = rule["gray"]
        m |= (s < 0.14) & (v >= g0) & (v <= g1)
    # soften 1 px so the camo/keep border is not aliased
    f = m.astype(np.float32)
    f = (f + np.roll(f, 1, 0) + np.roll(f, -1, 0) + np.roll(f, 1, 1) + np.roll(f, -1, 1)) / 5.0
    return f


def _rect_px(r, w, h):
    """glTF UV rectangle (v down) -> Blender pixel slice bounds (rows bottom-up)."""
    u0, v0, u1, v1 = r
    return int(u0 * w), math.ceil(u1 * w), int((1 - v1) * h), math.ceil((1 - v0) * h)


def flat_normals(img, rects, tag):
    """Copy of a normal map with rectangles made flat (embossed lettering, plates)."""
    a = _px(img)
    h, w = a.shape[:2]
    for r in rects:
        x0, x1, y0, y1 = _rect_px(r, w, h)
        a[y0:y1, x0:x1, :3] = (0.5, 0.5, 1.0)
    out = bpy.data.images.new("prepn_" + tag, w, h, alpha=False)
    out.colorspace_settings.name = "Non-Color"
    out.pixels.foreach_set(a.ravel())
    out.pack()
    return out


def prep_image(img, mat_rule, erase, tag, keep=()):
    """Make the masked copy of a base-colour image: RGB = source with markings painted over, A = paint mask.
    erase: list of (u0, v0, u1, v1) in glTF UV (v down) — filled with the surrounding colour, mask 1;
    keep: rectangles never repainted (canvas, tyres in a shared atlas). Returns (new image, paint luminance)."""
    a = _px(img)
    h, w = a.shape[:2]
    rgb = a[..., :3].copy()
    mode = mat_rule.get("mode", "auto")
    if mode == "paint":
        m = np.ones((h, w), np.float32)
    elif mode == "auto":
        m = paint_mask(rgb, mat_rule)
    else:
        m = np.zeros((h, w), np.float32)
    sel = m > 0.5
    ref = np.median(rgb[sel], axis=0) if sel.sum() > 50 else np.median(rgb.reshape(-1, 3), axis=0)
    for r in keep:
        x0, x1, y0, y1 = _rect_px(r, w, h)
        m[y0:y1, x0:x1] = 0.0
    for r in erase:
        # Blender pixel rows go bottom-up; glTF v goes top-down
        x0, x1, y0, y1 = _rect_px(r, w, h)
        patch = rgb[y0:y1, x0:x1]
        # keep the low-frequency shading of the panel, drop the marking: blend toward the ring median
        ring = np.concatenate([rgb[max(0, y0 - 3):y0, x0:x1].reshape(-1, 3), rgb[y1:y1 + 3, x0:x1].reshape(-1, 3),
                               rgb[y0:y1, max(0, x0 - 3):x0].reshape(-1, 3), rgb[y0:y1, x1:x1 + 3].reshape(-1, 3)])
        fill = np.median(ring, axis=0) if len(ring) > 8 else ref
        rng = np.random.default_rng(7)
        noise = 1.0 + 0.04 * (rng.random(patch.shape[:2]) - 0.5)
        rgb[y0:y1, x0:x1] = fill[None, None, :] * noise[..., None]
        m[y0:y1, x0:x1] = 1.0 if mode != "keep" else 0.0
    lum = (rgb * np.array([0.2126, 0.7152, 0.0722])).sum(-1)
    ref_l = float(np.median(lum[m > 0.5])) if (m > 0.5).sum() > 50 else float(np.median(lum))
    out = bpy.data.images.new("prep_" + tag, w, h, alpha=True)
    out.colorspace_settings.name = img.colorspace_settings.name
    out.alpha_mode = "CHANNEL_PACKED"
    b = np.concatenate([rgb, m[..., None]], -1).astype(np.float32)
    out.pixels.foreach_set(b.ravel())
    out.pack()
    return out, max(ref_l, 0.02)


# ---------------------------------------------------------------- repaint shader (high poly)
def _srgb_lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def _src_parts(mat):
    """(base colour image node or None, factor RGBA, normal map image or None, alpha mode) of a glTF-imported material."""
    nt = mat.node_tree
    b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:
        return None, (0.5, 0.5, 0.5, 1), None
    img = None
    fac = tuple(b.inputs["Base Color"].default_value)

    def up(sock, depth=0):
        if depth > 6 or not sock.links:
            return None
        n = sock.links[0].from_node
        if n.type == "TEX_IMAGE":
            return n
        for s in n.inputs:
            r = up(s, depth + 1)
            if r is not None:
                return r
        return None
    tn = up(b.inputs["Base Color"])
    if tn is not None:
        img = tn.image
        # glTF importer puts the colour factor into a Mix/Multiply node; read it if present
        for n in nt.nodes:
            if n.type == "MIX" and n.blend_type == "MULTIPLY":
                fac = tuple([s for s in n.inputs if s.type == "RGBA"][1].default_value)
    nimg = up(b.inputs["Normal"])
    return img, fac, (nimg.image if nimg is not None else None)


def _lin2srgb(x):
    return x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055


def rule_of(R, mat_name):
    for pat, rule in R.get("materials", []):
        if re.search(pat, mat_name):
            return rule
    return R.get("default_mat", {"mode": "auto"})


def camo_color(nt, pos, nz, P):
    """Camouflage in object space (spots run across parts), palette and spot size from the recipe."""
    cam = P["camo"]
    st = tuple(P.get("stretch", (1, 1, 1)))
    sc = P.get("scale", 1.0)
    n1 = _noise(nt, pos, 4.4 * sc, 3.0, stretch=st)
    n2 = _noise(nt, pos, 5.0 * sc, 3.0, (5.3, 1.7, 9.1), st)
    m1 = _band(nt, n1, 0.525, 0.532)
    m2 = _m(nt, "MULTIPLY", _band(nt, n2, 0.56, 0.567), _m(nt, "SUBTRACT", 1.0, m1))
    col = _mix(nt, m1, cam[0], cam[1])
    col = _mix(nt, m2, col, cam[2]) if len(cam) > 2 else col
    if P.get("belly"):
        col = _mix(nt, _band(nt, _m(nt, "MULTIPLY", nz, -1.0), 0.35, 0.55), col, P["belly"])
    for box, c in P.get("marks", []):   # enemy marks (fictional): wingtips, fin bands — boxes in object space
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(pos, sep.inputs[0])
        f = 1.0
        for i, ax in enumerate("XYZ"):
            lo, hi = box[2 * i], box[2 * i + 1]
            a = _m(nt, "GREATER_THAN", sep.outputs[ax], lo)
            b = _m(nt, "LESS_THAN", sep.outputs[ax], hi)
            f = _m(nt, "MULTIPLY", f, _m(nt, "MULTIPLY", a, b))
        col = _mix(nt, f, col, c)
    return col


def repaint(mat, R, cache):
    """Turn a source material into the bake shader: nodes 'emit_col', 'emit_rough', 'emit_metal', 'bsdf', 'out'."""
    if mat.get("fh_done"):
        return
    rule = rule_of(R, mat.name)
    P = R["paint"]
    img, fac, nimg = _src_parts(mat)
    nt = mat.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    sz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(pos, sz.inputs[0])
    nn = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], nn.inputs[0])
    nz = nn.outputs["Z"]
    up = _m(nt, "MAXIMUM", nz, 0.0)
    side = _m(nt, "SUBTRACT", 1.0, _m(nt, "ABSOLUTE", nz))
    uv = nt.nodes.new("ShaderNodeUVMap")
    mode = rule.get("mode", "auto")
    force = rule.get("color")
    if img is not None and force is None:
        key = (img.name, mat.name if R.get("erase", {}).get(mat.name) else "", mode, str(rule))
        if key not in cache:
            erase = R.get("erase", {}).get(mat.name, [])
            cache[key] = prep_image(img, rule, erase, re.sub(r"\W", "_", mat.name), R.get("keep", {}).get(mat.name, []))
        pimg, ref = cache[key]
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = pimg
        nt.links.new(uv.outputs[0], tn.inputs[0])
        src = tn.outputs["Color"]
        if fac[:3] != (1.0, 1.0, 1.0):
            src = _mix(nt, 1.0, src, tuple(_lin2srgb(x) for x in fac[:3]), "MULTIPLY")
        mask = tn.outputs["Alpha"]
        ref_l = ref * _srgb_lum(fac)
    else:
        c = force if force is not None else tuple(_lin2srgb(x) for x in fac[:3])
        src = _sock(nt, tuple(c))
        if mode == "paint":
            mask = 1.0
        elif mode == "auto" and force is None:
            a = np.array(c, np.float32).reshape(1, 1, 3)
            mask = float(paint_mask(a, rule)[0, 0] > 0.2)
        else:
            mask = 0.0
        ref_l = max(_srgb_lum(c), 0.02)
    # detail: source luminance around the paint reference (dirt, panel lines, AO painted in the source)
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(_sock(nt, src), bw.inputs[0])
    k = P.get("detail", 0.85)
    det = _m(nt, "DIVIDE", bw.outputs[0], ref_l)
    det = _m(nt, "ADD", 1.0 - k, _m(nt, "MULTIPLY", det, k))
    det = _m(nt, "MINIMUM", _m(nt, "MAXIMUM", det, 0.45), 1.45)
    cam = camo_color(nt, pos, nz, P)
    painted = _mix(nt, 1.0, cam, _n(nt, "ShaderNodeCombineXYZ", X=det, Y=det, Z=det).outputs[0], "MULTIPLY")
    keep = src
    if rule.get("desat", P.get("keep_desat", 0.25)) > 0 and mode != "glass":
        h = nt.nodes.new("ShaderNodeHueSaturation")
        h.inputs["Saturation"].default_value = 1.0 - rule.get("desat", P.get("keep_desat", 0.25))
        nt.links.new(_sock(nt, keep), h.inputs["Color"])
        keep = h.outputs[0]
    if rule.get("tint"):
        keep = _mix(nt, rule.get("tint_k", 0.6), keep, rule["tint"], "MULTIPLY")
    col = _mix(nt, mask, keep, painted)
    pmask = mask
    # weathering: sun fade on top, streaks on sides, worn edges, dust low and in crevices, occlusion
    col = _mix(nt, _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", up, P.get("fade", 0.10)), pmask), col, P.get("fade_col", (0.8, 0.74, 0.62)))
    stn = _noise(nt, pos, 9.0, 2.0, (0, 0, 0), (6.0, 6.0, 0.6))
    col = _mix(nt, _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", _band(nt, stn, 0.56, 0.72), side), P.get("streak", 0.18)), col, (0.2, 0.17, 0.12))
    bev = _n(nt, "ShaderNodeBevel", Radius=0.004)
    bev.samples = 6
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs[0], dot.inputs[0])
    nt.links.new(geo.outputs["True Normal"], dot.inputs[1])
    edge = _band(nt, _m(nt, "SUBTRACT", 1.0, dot.outputs["Value"]), 0.01, 0.08)
    wn = _noise(nt, pos, 30.0, 3.0, (3.3, 0.0, 1.1))
    wear = _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", edge, _band(nt, wn, 0.4, 0.6)), P.get("wear", 0.6))
    col = _mix(nt, _m(nt, "MULTIPLY", wear, pmask), col, P.get("wear_col", (0.72, 0.66, 0.55)))
    ao = _n(nt, "ShaderNodeAmbientOcclusion", Distance=P.get("ao_dist", 0.03))
    ao.samples = 12
    if P.get("dust", 0.0) > 0:
        dn = _noise(nt, pos, 14.0, 3.0, (1.1, 2.2, 3.3))
        low = _m(nt, "MULTIPLY", _m(nt, "SUBTRACT", 1.0, _band(nt, sz.outputs["Z"], 0.03, 0.16)), _m(nt, "ADD", 0.1, _m(nt, "MULTIPLY", dn, 0.6)))
        crev = _m(nt, "MULTIPLY", _m(nt, "SUBTRACT", 1.0, ao.outputs["AO"]), 0.3)
        d = _m(nt, "MULTIPLY", _m(nt, "ADD", low, crev), P["dust"], True)
        col = _mix(nt, _m(nt, "MINIMUM", d, 0.55), col, P.get("dust_col", K.DUST))
    occl = _m(nt, "ADD", 1.0 - P.get("ao", 0.5), _m(nt, "MULTIPLY", ao.outputs["AO"], P.get("ao", 0.5)))
    col = _mix(nt, 1.0, col, _n(nt, "ShaderNodeCombineXYZ", X=occl, Y=occl, Z=occl).outputs[0], "MULTIPLY")
    e1 = _n(nt, "ShaderNodeEmission", Color=col, Strength=1.0)
    e1.name = "emit_col"
    # roughness: satin paint (0.75–0.85 by recipe) with slight variation, polished worn edges; kept parts by rule
    pr0, pr1 = P.get("rough", (0.76, 0.84))
    rv = _noise(nt, pos, 22.0, 3.0, (2.0, 5.0, 1.0))
    prough = _m(nt, "ADD", pr0, _m(nt, "MULTIPLY", rv, pr1 - pr0))
    prough = _m(nt, "SUBTRACT", prough, _m(nt, "MULTIPLY", wear, 0.15))
    krough = rule.get("rough", 0.8)
    rough = _m(nt, "ADD", _m(nt, "MULTIPLY", prough, pmask), _m(nt, "MULTIPLY", krough, _m(nt, "SUBTRACT", 1.0, pmask)))
    e2 = _n(nt, "ShaderNodeEmission", Color=_n(nt, "ShaderNodeCombineXYZ", X=rough, Y=rough, Z=rough).outputs[0], Strength=1.0)
    e2.name = "emit_rough"
    kmet = rule.get("metal", 0.0)
    met = _m(nt, "ADD", _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", wear, 0.35), pmask), _m(nt, "MULTIPLY", kmet, _m(nt, "SUBTRACT", 1.0, pmask)))
    e3 = _n(nt, "ShaderNodeEmission", Color=_n(nt, "ShaderNodeCombineXYZ", X=met, Y=met, Z=met).outputs[0], Strength=1.0)
    e3.name = "emit_metal"
    # normal: source normal map (if any) through rounded edges
    nsock = None
    if nimg is not None:
        nimg.colorspace_settings.name = "Non-Color"
        if R.get("erase", {}).get(mat.name):
            nk = ("n", nimg.name, mat.name)
            if nk not in cache:
                cache[nk] = flat_normals(nimg, R["erase"][mat.name], re.sub(r"\W", "_", mat.name))
            nimg = cache[nk]
        ti = nt.nodes.new("ShaderNodeTexImage")
        ti.image = nimg
        nt.links.new(uv.outputs[0], ti.inputs[0])
        nm = _n(nt, "ShaderNodeNormalMap", Color=ti.outputs["Color"], Strength=rule.get("nstr", 1.0))
        nsock = nm.outputs[0]
    nb = nt.nodes.new("ShaderNodeBevel")
    nb.inputs["Radius"].default_value = P.get("round", 0.003)
    nb.samples = 8
    if nsock is not None:
        nt.links.new(nsock, nb.inputs["Normal"])
    bs = _n(nt, "ShaderNodeBsdfPrincipled", Normal=nb.outputs[0])
    bs.name = "bsdf"
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.name = "out"
    nt.links.new(e1.outputs[0], out.inputs[0])
    mat["fh_done"] = True
    mat["fh_glass"] = mode == "glass"
    mat.blend_method = "OPAQUE" if hasattr(mat, "blend_method") else None


# ---------------------------------------------------------------- low poly per node
def make_low(groups, R, budget):
    """Join a copy of each node's sources, weld and decimate; budget split by visible area (bounding box)."""
    def area(obs):
        mn, mx = bounds(obs)
        d = mx - mn
        return d.x * d.y + d.y * d.z + d.x * d.z
    weights = {g: area(v) * R.get("weight", {}).get(g or "<root>", 1.0) for g, v in groups.items() if v}
    tot = sum(weights.values())
    lows = {}
    for g, obs in groups.items():
        if not obs:
            continue
        cps = []
        for o in obs:
            c = o.copy()
            c.data = o.data.copy()
            bpy.context.scene.collection.objects.link(c)
            cps.append(c)
        _select(cps)
        bpy.ops.object.join()
        lo = bpy.context.object
        lo.name = "LOW_" + (g or "root")
        me = lo.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-4)
        lay = bm.faces.layers.bool.get("fh_nolow")
        if lay is not None:   # parts replaced by stand-ins (see _make_proxies)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[lay]], context="FACES")
        bm.to_mesh(me)
        bm.free()
        prox = R.get("_proxies", {}).get(g, [])
        if prox:
            cps = []
            for p in prox:
                c = p.copy()
                c.data = p.data.copy()
                bpy.context.scene.collection.objects.link(c)
                cps.append(c)
            _select([lo] + cps, lo)
            bpy.ops.object.join()
            lo = bpy.context.object
            me = lo.data
        want = max(200, int(budget * weights[g] / tot))
        if g in R.get("fixed", {}):
            want = R["fixed"][g]
        t = tris([lo])
        if t > want:
            # flat areas first (keeps silhouettes), then collapse
            md = lo.modifiers.new("pl", "DECIMATE")
            md.decimate_type = "DISSOLVE"
            md.angle_limit = math.radians(R.get("planar_deg", 1.5))
            md.delimit = {"SHARP"}
            bpy.ops.object.modifier_apply(modifier="pl")
            md = lo.modifiers.new("tri", "TRIANGULATE")
            bpy.ops.object.modifier_apply(modifier="tri")
            for it in range(4):
                t = tris([lo])
                if t <= want * 1.04:
                    break
                md = lo.modifiers.new("dc", "DECIMATE")
                md.ratio = max(0.01, want / t * (0.92 ** it))
                md.use_collapse_triangulate = True
                bpy.ops.object.modifier_apply(modifier="dc")
        print("LOW", g or "<root>", t, "->", tris([lo]), "budget", want)
        for p in me.polygons:
            p.use_smooth = True
        lows[g] = lo
    return lows


def unwrap(lows, R):
    obs = list(lows.values())
    _select(obs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    # keep only one UV layer on lows (the bake target)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in obs:
        while len(o.data.uv_layers) > 0:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
    _select(obs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.002, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=0.002, rotate=True, scale=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in obs:   # smooth normals on lows: auto smooth by angle so hard edges stay
        _select([o])
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(R.get("smooth_deg", 40)))


def bake(groups, lows, R, tex, samples, out_dir, name):
    """Bake every node's sources onto its low mesh into shared images (colour, roughness, metal, normal)."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    bk = sc.render.bake
    bk.use_selected_to_active = True
    bk.use_cage = False
    bk.cage_extrusion = R.get("cage", 0.006)
    bk.max_ray_distance = R.get("ray", 0.03)
    bk.margin = 8
    bk.margin_type = "EXTEND"
    imgs = {}
    for key, nc in (("color", False), ("rough", True), ("metal", True), ("normal", True)):
        im = bpy.data.images.new("%s_%s" % (name, key), tex, tex, alpha=False)
        im.colorspace_settings.name = "Non-Color" if nc else "sRGB"
        imgs[key] = im
    bake_mat = bpy.data.materials.new("bake_target")
    bake_mat.use_nodes = True
    tnode = bake_mat.node_tree.nodes.new("ShaderNodeTexImage")
    bake_mat.node_tree.nodes.active = tnode
    for lo in lows.values():   # slots keep their polygons; only the material in each slot changes
        lo["fh_slots"] = [s.material.name if s.material else "" for s in lo.material_slots]
        if not lo.material_slots:
            lo.data.materials.append(bake_mat)
        for s in lo.material_slots:
            s.material = bake_mat
    srcs = {m for obs in groups.values() for o in obs for m in o.data.materials if m}
    for key, typ, node in (("color", "EMIT", "emit_col"), ("rough", "EMIT", "emit_rough"), ("metal", "EMIT", "emit_metal"),
                           ("normal", "NORMAL", "bsdf")):
        tnode.image = imgs[key]
        for m in srcs:
            nt = m.node_tree
            nt.links.new(nt.nodes[node].outputs[0], nt.nodes["out"].inputs[0])
        first_g = True
        for g, lo in lows.items():
            _select(groups[g] + [lo], lo)
            bpy.ops.object.bake(type=typ, normal_space="TANGENT", use_clear=first_g, margin=8,
                                use_selected_to_active=True, cage_extrusion=R.get("cage", 0.006),
                                max_ray_distance=R.get("ray", 0.03))
            first_g = False
        print("BAKED", key)
    return imgs


def finish(groups, lows, imgs, R, out_dir, name, tex):
    """Pack ORM, build body/glass materials, set pivots and parents, export GLB, merge primitives."""
    w = tex
    rough = _px(imgs["rough"])[..., 0]
    metal = _px(imgs["metal"])[..., 0]
    orm = np.ones((w, w, 4), np.float32)
    orm[..., 1] = rough
    orm[..., 2] = metal
    imo = bpy.data.images.new(name + "_orm", w, w, alpha=False)
    imo.colorspace_settings.name = "Non-Color"
    imo.pixels.foreach_set(orm.ravel())
    for k, im in (("color", imgs["color"]), ("normal", imgs["normal"]), ("orm", imo)):
        im.filepath_raw = os.path.join(out_dir, "%s_%s.png" % (name, k))
        im.file_format = "PNG"
        im.save()
    root_name = R.get("root", name)
    fin = {}
    for key in ("body", "glass"):
        m = bpy.data.materials.new("%s_%s" % (root_name, key))
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = imgs["color"]
        nt.links.new(tc.outputs["Color"], b.inputs["Base Color"])
        if key == "body":   # glass stays flat: baked normals on thin panes give smeared reflections
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = imgs["normal"]
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
            to = nt.nodes.new("ShaderNodeTexImage")
            to.image = imo
            sp = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(to.outputs["Color"], sp.inputs[0])
            nt.links.new(sp.outputs["Green"], b.inputs["Roughness"])
            nt.links.new(sp.outputs["Blue"], b.inputs["Metallic"])
        else:
            b.inputs["Roughness"].default_value = R.get("glass_rough", 0.3)
            b.inputs["Metallic"].default_value = 0.05
        fin[key] = m
    for g, lo in lows.items():
        slots = list(lo["fh_slots"])
        for i, s in enumerate(lo.material_slots):
            src = slots[i] if i < len(slots) else ""
            s.material = fin["glass"] if src and bpy.data.materials[src].get("fh_glass") else fin["body"]
        _select([lo])
        bpy.ops.object.material_slot_remove_unused()   # duplicate slots merge later (glb_merge_prims)
    # pivots: recipe gives a point or "center" (bbox centre: wheels) / "base" (bbox centre x,y; min z: turrets)
    for g, lo in lows.items():
        lo.name = g if g else root_name
        lo.data.name = lo.name
        if not g:
            continue
        pv = R.get("pivots", {}).get(g, "center")
        mn, mx = bounds([lo])
        if pv == "center":
            p = (mn + mx) / 2
        elif pv == "base":
            p = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
        else:
            p = Vector(pv)
        lo.data.transform(Matrix.Translation(-p))
        lo.location = p
    root = lows.get("")
    bpy.context.view_layer.update()   # matrix_world is stale after setting location
    for g, lo in lows.items():
        if g:
            par = lows.get(R.get("parents", {}).get(g, ""), root)
            mw = lo.matrix_world.copy()
            lo.parent = par
            lo.matrix_world = mw
    for obs in groups.values():
        for o in obs:
            bpy.data.objects.remove(o)
    for o in list(bpy.data.objects):
        if o.name not in [lo.name for lo in lows.values()]:
            bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    total = tris(list(lows.values()))
    mn, mx = bounds(list(lows.values()))
    print("FINAL tris", total, "size", tuple(round(v, 3) for v in (mx - mn)), "min", tuple(round(v, 3) for v in mn))
    out = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_yup=True,
                              export_image_format="AUTO", export_apply=True)
    import importlib.util
    spec = importlib.util.spec_from_file_location("glb_merge_prims", str(TOOLS / "glb_merge_prims.py"))
    gm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gm)
    gm.merge(out)
    print("EXPORT", out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("recipe")
    ap.add_argument("src")
    ap.add_argument("out_dir")
    ap.add_argument("--tex", type=int, default=2048)
    ap.add_argument("--tris", type=int, default=0)
    ap.add_argument("--samples", type=int, default=16)
    ap.add_argument("--probe", action="store_true", help="only place, list parts (centre, size, tris), export placed GLB")
    a = ap.parse_args()
    R = sf_recipes.RECIPES[a.recipe]
    os.makedirs(a.out_dir, exist_ok=True)
    obs = load(a.src)
    print("SOURCE objects", len(obs), "tris", tris(obs))
    drop = R.get("drop")
    if drop:
        for o in list(obs):
            if re.search(drop, o.name):
                obs.remove(o)
                bpy.data.objects.remove(o)
    place(obs, R)
    if R.get("split"):
        obs = split_loose(obs, R["split"])
    if R.get("drop_box"):
        for o in list(obs):
            if any(_in_box(_center(o), b) for b in R["drop_box"]):
                obs.remove(o)
                bpy.data.objects.remove(o)
    if R.get("kill_faces"):
        kill_box_faces(obs, R["kill_faces"])
        for o in list(obs):
            if not o.data.polygons:
                obs.remove(o)
                bpy.data.objects.remove(o)
    if R.get("build"):   # parts made in code (e.g. the technical's machine gun)
        obs += R["build"]()
    if R.get("wheels"):
        obs = find_wheels(obs, R)
    if R.get("wheel_cyl"):
        obs = cut_wheels(obs, R)
    if a.probe:
        for o in sorted(obs, key=lambda o: -tris([o])):
            c = _center(o)
            mn, mx = bounds([o])
            d = mx - mn
            print("PART %-40s c=(%.3f %.3f %.3f) d=(%.3f %.3f %.3f) tris=%d mats=%s" % (
                o.name[:40], c.x, c.y, c.z, d.x, d.y, d.z, tris([o]), [m.name for m in o.data.materials if m][:3]))
        bpy.ops.export_scene.gltf(filepath=os.path.join(a.out_dir, a.recipe + "_probe.glb"), export_format="GLB",
                                  use_selection=False, export_yup=True)
        return 0
    groups = assign_groups(obs, R)
    cache = {}
    for o in (o for v in groups.values() for o in v):
        for m in o.data.materials:
            if m is not None:
                repaint(m, R, cache)
    lows = make_low(groups, R, a.tris or R.get("tris", 12000))
    unwrap(lows, R)
    imgs = bake(groups, lows, R, a.tex, a.samples, a.out_dir, a.recipe)
    finish(groups, lows, imgs, R, a.out_dir, a.recipe, a.tex)
    return 0


if __name__ == "__main__":
    sys.exit(main())
