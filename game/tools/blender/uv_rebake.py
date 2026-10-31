"""New UV atlas for a hangar plane and its paint, normal and ORM maps re-baked onto it (Kanta s14, «Оса» 1: the
camouflage could not be redrawn crisp on its atlas).

Why: the hand-made «Оса» 1 skin is cut into ~7000 thin UV strips that cover a quarter of the 4K atlas. A camouflage
border crosses hundreds of strip seams, so any redraw of the paint in the atlas (tex_clean.py --camo) shifts the
pattern from strip to strip, and the black gutter between strips bleeds into the paint on the mipmaps.

What it does:
1. Every textured primitive of the GLB (skin, slats and flaps, canopy glass) becomes one Blender object in model
   axes, its vertices welded by position, the old UV kept as a second UV map. Faces keep their glTF order.
2. New UV: Smart UV Project (--angle), islands scaled to one texel density and packed with --margin texels between
   them, rotated freely, so the skin lies in a few hundred large islands over most of the atlas.
3. Each map is baked from the old UV onto the new one by Cycles on the same mesh (no rays to another object, so
   nothing misses): paint and ORM as emission, the normal map as a tangent-space normal bake of the old map, so
   the panel lines and rivets stay exactly where they were on the skin. The bake margin extends every island.
4. The GLB is rewritten with glb_io: each glTF vertex is split where the new UV needs a seam (position, normal and
   every other attribute copied), new index buffers, and the new JPEG maps both embedded and written next to the
   GLB under the names Godot extracts them to (<model>_<image name>.jpg), so the two never disagree.
Nodes, materials, node frames, the dark wells (no UV) and the triangle order are kept.

Run from the repo root (needs bpy 5.x as a module), then `godot --headless --path game --import`:
  python3 game/tools/blender/uv_rebake.py game/models/hangar/fh_hangar_fighter_1.glb /tmp/out_dir \
      [--tex 4096] [--angle 60] [--margin 8] [--samples 4] [--threads 2]
Output: /tmp/out_dir/<same name>.glb and its maps; copy them over the originals. After it, tex_clean.py for the
crisp camouflage (docs/tasks/3d-models-handoff.md).
"""
import argparse
import math
import os
import shutil
import sys
import tempfile
import time

import bpy  # noqa: I001 — bpy first: it registers mathutils
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

T0 = time.time()


def log(*a: object) -> None:
    """Progress line with the elapsed time."""
    print("[uv_rebake %5.0fs]" % (time.time() - T0), *a, flush=True)


def node_world(j: dict, ni: int) -> np.ndarray:
    """World matrix of node ni (parents applied)."""
    parent = {}
    for i, n in enumerate(j["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    m = glb_io._node_mat(j["nodes"][ni])
    k = ni
    while k in parent:
        k = parent[k]
        m = glb_io._node_mat(j["nodes"][k]) @ m
    return m


def textured_prims(g: glb_io.Glb) -> list:
    """Every (mesh, primitive) with a TEXCOORD_0, with its node's world matrix: the surfaces on the atlas."""
    out = []
    for ni, n in enumerate(g.j["nodes"]):
        if "mesh" not in n:
            continue
        M = node_world(g.j, ni)
        for pi, pr in enumerate(g.j["meshes"][n["mesh"]]["primitives"]):
            if "TEXCOORD_0" in pr["attributes"]:
                out.append((n["mesh"], pi, M))
    return out


def build_object(g: glb_io.Glb, prims: list) -> tuple:
    """One Blender mesh of all textured primitives in model axes (glTF y-up kept: only UVs and baking matter here).
    Vertices welded by position within each primitive; per-loop old UV ("old") and glTF normals (custom split
    normals, so the bake's tangent frames are the ones Godot builds). Returns (object, [(mesh, prim, face range)])."""
    verts, faces, uvs, nrms, spans = [], [], [], [], []
    voff = 0
    foff = 0
    for mi, pi, M in prims:
        pr = g.j["meshes"][mi]["primitives"][pi]
        P = g.accessor(pr["attributes"]["POSITION"]).astype(np.float64) @ M[:3, :3].T + M[:3, 3]
        N = g.accessor(pr["attributes"]["NORMAL"]).astype(np.float64) @ M[:3, :3].T
        UV = g.accessor(pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
        T = g.accessor(pr["indices"]).reshape(-1, 3).astype(np.int64)
        q = np.round(P / 1e-6).astype(np.int64)
        _, first, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        Fp = inv[T]
        V = P[first]
        # a triangle whose corners weld into one point would be an invalid face: it keeps its own vertices
        bad = np.nonzero((Fp[:, 0] == Fp[:, 1]) | (Fp[:, 1] == Fp[:, 2]) | (Fp[:, 0] == Fp[:, 2]))[0]
        if len(bad):
            Fp[bad] = len(V) + np.arange(3 * len(bad)).reshape(-1, 3)
            V = np.vstack([V, P[T[bad]].reshape(-1, 3)])
        verts.append(V)
        faces.append(Fp + voff)
        uvs.append(UV[T].reshape(-1, 2))
        nrms.append(N[T].reshape(-1, 3))
        spans.append((mi, pi, foff, foff + len(T)))
        voff += len(V)
        foff += len(T)
    V = np.vstack(verts)
    F = np.vstack(faces)
    me = bpy.data.meshes.new("skin")
    me.vertices.add(len(V))
    me.vertices.foreach_set("co", V.astype(np.float32).ravel())
    me.loops.add(F.size)
    me.loops.foreach_set("vertex_index", F.astype(np.int32).ravel())
    me.polygons.add(len(F))
    me.polygons.foreach_set("loop_start", np.arange(0, F.size, 3, dtype=np.int32))
    me.polygons.foreach_set("loop_total", np.full(len(F), 3, np.int32))
    me.update(calc_edges=True)
    old = me.uv_layers.new(name="old")
    UVo = np.vstack(uvs).copy()
    UVo[:, 1] = 1.0 - UVo[:, 1]   # glTF v runs down the image, Blender's up
    old.data.foreach_set("uv", UVo.astype(np.float32).ravel())
    me.uv_layers.new(name="new")
    me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    N = np.vstack(nrms)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    me.normals_split_custom_set(N.astype(np.float32).tolist())
    ob = bpy.data.objects.new("skin", me)
    bpy.context.scene.collection.objects.link(ob)
    log("mesh: %d faces, %d welded vertices from %d primitives" % (len(F), len(V), len(prims)))
    return ob, spans


def unwrap(ob: bpy.types.Object, tex: int, angle: float, margin_px: float) -> None:
    """Smart UV Project into the "new" map, one texel density, packed with `margin_px` texels between islands."""
    me = ob.data
    me.uv_layers.active = me.uv_layers["new"]
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, rotate_method="ANY", scale=True,
                            merge_overlap=False, margin_method="FRACTION", margin=margin_px / tex,
                            shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")


def uv_report(ob: bpy.types.Object, layer: str, tex: int) -> str:
    """Islands, atlas coverage and texel density spread (texels per model unit, p10/p50/p90) of a UV map."""
    me = ob.data
    n = len(me.polygons)
    uv = np.empty(n * 6, np.float32)
    me.uv_layers[layer].data.foreach_get("uv", uv)
    uv = uv.reshape(n, 3, 2).astype(np.float64)
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    vi = np.empty(n * 3, np.int32)
    me.polygons.foreach_get("vertices", vi)
    P = co[vi.reshape(n, 3)].astype(np.float64)
    a3 = 0.5 * np.linalg.norm(np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0]), axis=1)
    d1, d2 = uv[:, 1] - uv[:, 0], uv[:, 2] - uv[:, 0]
    auv = 0.5 * np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0])
    ok = a3 > 1e-10
    dens = np.sqrt(auv[ok] / a3[ok]) * tex
    # islands: faces joined by edges whose two UV corners agree
    q = np.round(uv.reshape(-1, 2) * 1e5).astype(np.int64)
    vid = vi.astype(np.int64)
    corner = np.stack([vid, q[:, 0], q[:, 1]], 1)
    _, cid = np.unique(corner, axis=0, return_inverse=True)
    cid = cid.reshape(n, 3)
    r = np.concatenate([cid[:, 0], cid[:, 1], cid[:, 2]])
    c = np.concatenate([cid[:, 1], cid[:, 2], cid[:, 0]])
    m = cid.max() + 1
    k, _ = connected_components(coo_matrix((np.ones(len(r)), (r, c)), shape=(m, m)), directed=False)
    return ("%s: %d islands, atlas covered %.1f%%, texels per unit p10/p50/p90 %d/%d/%d"
            % (layer, k, 100 * auv.sum(), *np.percentile(dens, [10, 50, 90])))


def bake_maps(ob: bpy.types.Object, maps: dict, tex: int, samples: int, threads: int) -> dict:
    """Bake every source map {name: (path, kind)} (kind: "color", "data" or "normal") from the "old" UV onto the
    "new" one; returns {name: bpy image}."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    if threads > 0:
        sc.render.threads_mode = "FIXED"
        sc.render.threads = threads
    rb = sc.render.bake
    rb.use_selected_to_active = False
    rb.margin = 16
    rb.margin_type = "EXTEND"
    rb.use_clear = True
    me = ob.data
    me.uv_layers.active = me.uv_layers["new"]
    me.uv_layers["new"].active_render = True
    mat = bpy.data.materials.new("bake")
    mat.use_nodes = True
    me.materials.clear()
    me.materials.append(mat)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "old"
    out = {}
    for name, (path, kind) in maps.items():
        src = nt.nodes.new("ShaderNodeTexImage")
        src.image = bpy.data.images.load(os.path.abspath(path))
        src.image.colorspace_settings.name = "sRGB" if kind == "color" else "Non-Color"
        src.interpolation = "Cubic"
        nt.links.new(uvn.outputs["UV"], src.inputs["Vector"])
        img = bpy.data.images.new(name, tex, tex, alpha=False, float_buffer=kind == "normal")
        img.colorspace_settings.name = "sRGB" if kind == "color" else "Non-Color"
        dst = nt.nodes.new("ShaderNodeTexImage")
        dst.image = img
        for x in nt.nodes:
            x.select = False
        dst.select = True
        nt.nodes.active = dst
        links = []
        if kind == "normal":
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.space = "TANGENT"
            nm.uv_map = "old"
            links.append(nt.links.new(src.outputs["Color"], nm.inputs["Color"]))
            links.append(nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"]))
            kw = {"type": "NORMAL", "normal_space": "TANGENT"}
        else:
            links.append(nt.links.new(src.outputs["Color"], bsdf.inputs["Emission Color"]))
            bsdf.inputs["Emission Strength"].default_value = 1.0
            kw = {"type": "EMIT"}
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        t = time.time()
        bpy.ops.object.bake(**kw)
        log("baked %s (%s) in %.0fs" % (name, kw["type"], time.time() - t))
        for lk in links:
            nt.links.remove(lk)
        bsdf.inputs["Emission Strength"].default_value = 0.0
        out[name] = img
    return out


def save_jpeg(img: bpy.types.Image, path: str, quality: int, tmpd: str) -> None:
    """Write a baked image as an RGB JPEG (4:4:4) through a PNG."""
    from PIL import Image as PILImage  # noqa: PLC0415

    img.filepath_raw = os.path.join(tmpd, img.name + ".png")
    img.file_format = "PNG"
    if img.is_float:
        img.use_half_precision = False
    img.save()
    PILImage.open(img.filepath_raw).convert("RGB").save(path, quality=quality, subsampling=0, optimize=True)


def new_corner_uvs(ob: bpy.types.Object) -> np.ndarray:
    """New UV per face corner (faces in build order), glTF convention (v down)."""
    me = ob.data
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers["new"].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2).astype(np.float64)
    uv[:, 1] = 1.0 - uv[:, 1]
    return uv.reshape(-1, 3, 2)


def _append_view(g: glb_io.Glb, arr: np.ndarray, target: int | None) -> int:
    """Append raw bytes of arr as a new bufferView; returns its index."""
    while len(g.bin) % 4:
        g.bin.append(0)
    off = len(g.bin)
    g.bin += arr.tobytes()
    bv = {"buffer": 0, "byteOffset": off, "byteLength": int(arr.nbytes)}
    if target:
        bv["target"] = target
    g.j["bufferViews"].append(bv)
    return len(g.j["bufferViews"]) - 1


def _new_accessor(g: glb_io.Glb, arr: np.ndarray, kind: str, index: bool = False) -> int:
    """New accessor over a fresh bufferView holding arr (float32 attributes or uint32/uint16 indices)."""
    if index:
        arr = arr.astype(np.uint16 if arr.max() < 65535 else np.uint32).reshape(-1)
        ct = 5123 if arr.dtype == np.uint16 else 5125
    else:
        arr = arr.astype(np.float32)
        ct = 5126
    bv = _append_view(g, arr, 34963 if index else 34962)
    a = {"bufferView": bv, "componentType": ct, "count": int(len(arr)), "type": kind}
    if kind == "VEC3" and not index:
        a["min"] = [float(v) for v in arr.min(0)]
        a["max"] = [float(v) for v in arr.max(0)]
    g.j["accessors"].append(a)
    return len(g.j["accessors"]) - 1


def rewrite_glb(g: glb_io.Glb, spans: list, cuv: np.ndarray, images: dict, dst: str) -> str:
    """Split every textured primitive's vertices by the new UV, give it new accessors and indices, embed the new
    images (name -> JPEG path) and save; returns a one-line summary."""
    NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    before = after = 0
    for mi, pi, f0, f1 in spans:
        pr = g.j["meshes"][mi]["primitives"][pi]
        T = g.accessor(pr["indices"]).reshape(-1, 3).astype(np.int64)
        uv = cuv[f0:f1].reshape(-1, 2)
        q = np.round(uv * 2 ** 20).astype(np.int64)
        key = np.stack([T.reshape(-1), q[:, 0], q[:, 1]], 1)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        src_v = T.reshape(-1)[first]
        before += len(np.unique(T))
        after += len(first)
        attrs = {}
        for an, ai in pr["attributes"].items():
            acc = g.j["accessors"][ai]
            if an == "TEXCOORD_0":
                data = uv[first]
            else:
                data = g.accessor(ai).astype(np.float64)[src_v]
            if acc["componentType"] != 5126:
                raise SystemExit("attribute %s is not float: not supported" % an)
            attrs[an] = _new_accessor(g, data.reshape(len(first), NC[acc["type"]]), acc["type"])
        pr["attributes"] = attrs
        pr["indices"] = _new_accessor(g, inv, "SCALAR", index=True)
    for im in g.j.get("images", []):
        if im.get("name") in images:
            data = np.frombuffer(open(images[im["name"]], "rb").read(), np.uint8)
            im["bufferView"] = _append_view(g, data, None)
            im["mimeType"] = "image/jpeg"
    # accessors nobody uses any more (old attributes) would keep their bytes: drop them before compacting
    used = set()
    for m in g.j["meshes"]:
        for pr in m["primitives"]:
            used.update(pr["attributes"].values())
            if "indices" in pr:
                used.add(pr["indices"])
    remap, acc = {}, []
    for i, a in enumerate(g.j["accessors"]):
        if i in used:
            remap[i] = len(acc)
            acc.append(a)
    g.j["accessors"] = acc
    for m in g.j["meshes"]:
        for pr in m["primitives"]:
            pr["attributes"] = {k: remap[v] for k, v in pr["attributes"].items()}
            if "indices" in pr:
                pr["indices"] = remap[pr["indices"]]
    g.compact()
    g.save(dst)
    return "textured vertices %d -> %d (split along the new seams)" % (before, after)


def main() -> int:
    """Command line: re-unwrap one hangar GLB and re-bake its maps into an output folder."""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src", help="hangar GLB; its maps are the extracted <model>_<image name>.jpg next to it")
    ap.add_argument("out_dir")
    ap.add_argument("--tex", type=int, default=4096)
    ap.add_argument("--angle", type=float, default=60.0, help="Smart UV Project angle limit, degrees")
    ap.add_argument("--margin", type=float, default=8.0, help="texels between islands")
    ap.add_argument("--samples", type=int, default=4)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--quality", type=int, default=94)
    ap.add_argument("--dry", action="store_true", help="unwrap and report only, no bake")
    a = ap.parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    g = glb_io.load(a.src)
    base = os.path.splitext(os.path.abspath(a.src))[0]
    maps = {}
    for mt in g.j["materials"]:
        pbr = mt.get("pbrMetallicRoughness", {})
        for slot, kind in ((pbr.get("baseColorTexture"), "color"), (pbr.get("metallicRoughnessTexture"), "data"),
                           (mt.get("normalTexture"), "normal")):
            if slot is None:
                continue
            name = g.j["images"][g.j["textures"][slot["index"]]["source"]]["name"]
            path = base + "_" + name + ".jpg"
            if not os.path.exists(path):
                raise SystemExit("missing extracted map " + path)
            maps[name] = (path, kind)
    log("maps:", ", ".join("%s (%s)" % (k, v[1]) for k, v in maps.items()))
    prims = textured_prims(g)
    ob, spans = build_object(g, prims)
    log(uv_report(ob, "old", a.tex))
    unwrap(ob, a.tex, a.angle, a.margin)
    log(uv_report(ob, "new", a.tex))
    if a.dry:
        return 0
    imgs = bake_maps(ob, maps, a.tex, a.samples, a.threads)
    os.makedirs(a.out_dir, exist_ok=True)
    dst = os.path.join(a.out_dir, os.path.basename(a.src))
    dbase = os.path.splitext(dst)[0]
    tmpd = tempfile.mkdtemp()
    paths = {}
    for name, img in imgs.items():
        paths[name] = dbase + "_" + name + ".jpg"
        save_jpeg(img, paths[name], a.quality, tmpd)
        log("wrote", paths[name])
    shutil.rmtree(tmpd, ignore_errors=True)
    log(rewrite_glb(g, spans, new_corner_uvs(ob), paths, dst))
    log("wrote", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
