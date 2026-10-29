"""Battle model of a player plane baked from its hangar model (weak-models list, Kanta 28.10: «Оса 2», «Кит 1»
and «Кит 2» in battle must read as the same aircraft as in the hangar, without melted or wavy skin).

Why not battle_lod.py: that one collapses the whole mesh to a budget and keeps the old UV. On the remeshed hangar
models the UV is cut into thousands of islands, so a decimation that keeps it either ignores the seams (texture
smears) or spends the budget on them; and the old battle «Кит» models still came from the pre-remesh Meshy mesh
with its wavy texture. Here the battle model is a new, clean low mesh with its own UV, and the paint, roughness
and the shape's fine relief are baked onto it from the hangar model:

1. Import the hangar GLB with the textures Godot extracted next to it (<model>_col.jpg …: paint was edited there).
   Slats, flaps (`wing_mech`) and bay doors (`bay_doors`) are moved into the hull at rest and welded back where
   they were cut out; the dark wells under them (material `mech_well`) are dropped. The battle game hangs its
   own plates GLBs (fh_mech_*, fh_bay_*) over the closed wing and belly, as before.
2. Low mesh: MeshLab quadric edge collapse of the welded hull to the budget (skin and canopy glass apart; the
   glass, the skin round its rim and the skin along the top-view outline are not collapsed, so the glass edge and
   the wing and tail edges stay where they were), edges sharper than --sharp shaded hard.
3. Shading normals: the hangar's smooth normal under each corner where it agrees with the low face (ray along the
   face normal, moving sections and bent normals skipped, see _hangar_normals), elsewhere from an evened-out copy
   of the low mesh itself, corner by corner (see shade_low: a plain nearest-face copy of the hangar's normals
   flipped ~9 % of the corners). Smart UV Project, then
   Cycles (CPU) selected-to-active from the hangar mesh: paint and ORM through emission (no light, no shadow); a
   tangent-space normal map only with --normal geo|full (the remeshed hangar models have none: their panel lines
   are in the paint, and a baked map brought back bake noise).
4. Export one mesh node `fh_battle_<key>`, length 1, nose +X, the same axes, scale and origin as the hangar model
   (so the mech, bay, tail cabin, insignia, decals, nozzles and module anchors sit where they did); materials
   `skin` (surface 0, textured: Livery and PlaneHull take it as the skin) and `glass` (the .import maps it to
   shaders/canopy_glass.tres). The images are written next to the GLB under the names Godot extracts them to
   (<model>_col.jpg, _orm.jpg, _nrm.png); old extracted images of the model are removed.

Needs bpy (Blender 5.x as a module, tested 5.2.3) and pymeshlab (2025.7). Run from the repo root, then
`godot --headless --path game --import`:
  python3 game/tools/blender/battle_bake.py game/models/hangar/fh_hangar_bomber_1.glb \
      game/models/battle/fh_battle_bomber_1.glb [--tris 30000] [--tex 2048] [--normal geo|full] [--sharp 40] \
      [--outline 2] [--glass 1] [--shade hangar|even] [--threads 2]
Recipe of the shipped models: docs/tasks/3d-models-handoff.md («Боевые модели из ангарных»).
"""
import argparse
import math
import os
import re
import shutil
import sys
import tempfile
import time

import bpy  # noqa: I001 — bpy first: it registers bmesh and mathutils
import bmesh
import numpy as np
from mathutils import Matrix
from mathutils.bvhtree import BVHTree

T0 = time.time()
HN_DIST = 0.003   # farthest hangar point a low corner takes its shading normal from (_hangar_normals), model units
LOST = 0.004   # a hangar vertex farther than this from the collapsed skin marks a thin part to keep, model units


def log(*a: object) -> None:
    """Progress line with the elapsed time."""
    print("[battle_bake %5.0fs]" % (time.time() - T0), *a, flush=True)


def activate(o: bpy.types.Object) -> None:
    """Make `o` the only selected and the active object (bake and UV operators work on it)."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def load_hangar(src: str) -> bpy.types.Object:
    """Import the hangar GLB and join every mesh into one object `hi` in model axes (Blender: X nose, Z up).
    Textures are swapped for the files Godot extracted next to the GLB when they exist."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(src))
    base = os.path.splitext(os.path.abspath(src))[0]
    for im in list(bpy.data.images):
        for ext in (".jpg", ".png"):
            f = base + "_" + im.name + ext
            if os.path.exists(f):
                ni = bpy.data.images.load(f)
                ni.colorspace_settings.name = im.colorspace_settings.name
                for m in bpy.data.materials:
                    if m.node_tree:
                        for n in m.node_tree.nodes:
                            if n.type == "TEX_IMAGE" and n.image == im:
                                n.image = ni
                log("image %s <- %s %s" % (im.name, os.path.basename(f), tuple(ni.size)))
                break
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bm = bmesh.new()
    mats: list = []
    part = bm.faces.layers.int.new("part")   # 1: a moving section (slat, flap, bay door), see _hangar_normals
    for o in meshes:
        me = o.data.copy()
        me.transform(o.matrix_world)
        n0 = len(bm.faces)
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        part = bm.faces.layers.int["part"]
        for f in bm.faces[n0:]:
            f[part] = 0 if o.parent is None else 1
        remap = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        for f in bm.faces[n0:]:
            f.material_index = remap[f.material_index] if remap else 0
        bpy.data.meshes.remove(me)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o)
    me = bpy.data.meshes.new("hi")
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    hi = bpy.data.objects.new("hi", me)
    bpy.context.scene.collection.objects.link(hi)
    log("hangar: %d meshes, %d faces, materials %s" % (len(meshes), len(me.polygons), [m.name for m in mats]))
    return hi


def clean_hi(hi: bpy.types.Object) -> None:
    """Drop the dark wells under the moving sections and weld the sections back into the hull."""
    bm = bmesh.new()
    bm.from_mesh(hi.data)
    names = [m.name for m in hi.data.materials]
    well = [i for i, n in enumerate(names) if n.startswith("mech_well")]
    kill = [f for f in bm.faces if f.material_index in well]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-5)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    nb = sum(1 for e in bm.edges if e.is_boundary)
    bm.to_mesh(hi.data)
    bm.free()
    log("hi: wells dropped %d faces, %d faces left, open edges after weld %d" % (len(kill), len(hi.data.polygons), nb))


def decimate(hi: bpy.types.Object, tris: int, glass_ratio: float, sharp: float,
             outline_px: float = 2.0) -> bpy.types.Object:
    """Low mesh `lo`: quadric edge collapse (MeshLab) of the skin and of the glass apart. The skin faces along the
    top-view outline (`outline_px`, see _frozen_skin) and round the canopy are left as they are, so the wing and
    tail edges stay straight and the skin meets the glass without a gap; `glass_ratio` >= 1 keeps the glass whole."""
    import pymeshlab  # noqa: PLC0415 — only this step needs it

    me = hi.data
    gi = [i for i, m in enumerate(me.materials) if m.name.startswith("glass")]
    V = np.array([v.co[:] for v in me.vertices], dtype=np.float64)
    parts = []
    for is_glass in (False, True):
        F = []
        for p in me.polygons:
            if (p.material_index in gi) != is_glass:
                continue
            vs = list(p.vertices)
            for k in range(1, len(vs) - 1):
                F.append((vs[0], vs[k], vs[k + 1]))
        if not F:
            continue
        F = np.array(F, dtype=np.int32)
        used = np.unique(F)
        idx = np.full(len(V), -1, dtype=np.int32)
        idx[used] = np.arange(len(used), dtype=np.int32)
        parts.append((is_glass, V[used], idx[F]))
    nglass = sum(len(f) for g, _, f in parts if g)
    glass_pts = np.vstack([pv for g, pv, _ in parts if g]) if nglass else np.zeros((0, 3))
    out_v: list = []
    out_f: list = []
    out_m: list = []
    for is_glass, pv, pf in parts:
        if is_glass:
            n_glass = len(pf) if glass_ratio >= 1.0 else max(64, int(len(pf) * glass_ratio))
            target = n_glass
        else:
            target = max(500, tris - (nglass if glass_ratio >= 1.0 else int(nglass * glass_ratio)))
        if is_glass and glass_ratio >= 1.0:
            # the canopy stays as the hangar cut it: a collapsed glass pulled its outline inward (preserveboundary
            # does not pin open-edge vertices) and the skin under it showed through as pale triangles
            v2, f2 = pv, pf
        else:
            keep = _frozen_skin(pv, pf, glass_pts, outline_px) if not is_glass else None
            # with a selection MeshLab collapses the selected faces down to the target and adds the frozen ones
            v2, f2 = _collapse(pymeshlab, pv, pf, _sel_target(target, keep), keep)
        if not is_glass:
            # thin parts the collapse folds away (the nose probe, aerials): hangar vertices left far from the new
            # skin; the faces round them are kept as they are and the rest is collapsed again
            tree = BVHTree.FromPolygons([tuple(v) for v in v2], [tuple(int(i) for i in f) for f in f2])
            far = np.array([(tree.find_nearest(tuple(v))[3] or 0.0) > LOST for v in pv])
            if far.any():
                lost = far[pf].any(axis=1)
                from scipy.spatial import cKDTree  # noqa: PLC0415

                near = cKDTree(pv[pf].mean(axis=1)).query_ball_point(pv[far], LOST * 1.5)
                for ids in near:   # grow the kept patch a little round each lost vertex
                    lost[ids] = True
                log("skin: %d hangar vertices lost (> %.3f), %d faces kept as they are" % (far.sum(), LOST, lost.sum()))
                keep = lost if keep is None else (keep | lost)
                v2, f2 = _collapse(pymeshlab, pv, pf, _sel_target(target, keep), keep)
        base = sum(len(v) for v in out_v)
        out_v.append(v2)
        out_f.append(f2 + base)
        out_m += [1 if is_glass else 0] * len(f2)
        log("%s: %d -> %d tris" % ("glass" if is_glass else "skin", len(pf), len(f2)))
    V2 = np.vstack(out_v)
    F2 = np.vstack(out_f)
    lme = bpy.data.meshes.new("lo")
    lme.from_pydata([tuple(v) for v in V2], [], [tuple(int(i) for i in f) for f in F2])
    # material index before validate(): validate drops duplicate and degenerate faces, and an index list zipped on
    # after it slid by the dropped count, so the first glass faces came out as skin (painted triangles on the canopy)
    # (kept in a face attribute while validating: validate also resets indices past the slots, none exist yet)
    fm = lme.attributes.new("fmat", "INT", "FACE")
    fm.data.foreach_set("value", np.array(out_m, dtype=np.int32))
    nf = len(lme.polygons)
    lme.validate()
    if len(lme.polygons) != nf:
        log("lo: validate dropped %d faces" % (nf - len(lme.polygons)))
    mi = np.empty(len(lme.polygons), dtype=np.int32)
    lme.attributes["fmat"].data.foreach_get("value", mi)
    lme.polygons.foreach_set("material_index", mi)
    lme.attributes.remove(lme.attributes["fmat"])
    lo = bpy.data.objects.new("lo", lme)
    bpy.context.scene.collection.objects.link(lo)
    bm = bmesh.new()
    bm.from_mesh(lme)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    nb = sum(1 for e in bm.edges if e.is_boundary)
    bm.to_mesh(lme)
    bm.free()
    # the collapse keeps each face's winding, so the low mesh faces out wherever the hangar mesh did
    skin = bpy.data.materials.new("skin")
    if skin.name != "skin":   # the hangar material may be called "skin" too; the battle GLB keeps the plain name
        bpy.data.materials["skin"].name = "skin_hangar"
        skin.name = "skin"
    lme.materials.append(skin)
    lme.materials.append(next(m for m in me.materials if m.name.startswith("glass")) if gi else bpy.data.materials.new("glass"))
    activate(lo)
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(sharp), keep_sharp_edges=False)
    except Exception as e:  # noqa: BLE001
        log("shade_smooth_by_angle:", e)
    log("lo: %d tris, open edges %d" % (len(lme.polygons), nb))
    return lo


def _sel_target(target: int, keep) -> int:
    """Face target for a collapse of the selected (not frozen) faces, so the result with the frozen ones lands on
    `target`; never under a fifth of the selected faces (pushed harder, the collapse next to a frozen band folds
    faces outward)."""
    if keep is None:
        return target
    n_sel = int((~keep).sum())
    return max(500, n_sel // 5, target - int(keep.sum()))


def _frozen_skin(pv: np.ndarray, pf: np.ndarray, glass_pts: np.ndarray, outline_px: float, res: int = 2000):
    """Skin faces the collapse must leave as they are (bool per face), or None when there are none:

    * the top-view outline: faces with two vertices within `outline_px` pixels (at `res` per model unit) of the
      edge of the planform. The wing and tailplane edges are thin folds, not open edges, so preserveboundary does
      not hold them; collapsed, their vertices slid inward and cut notches into the outline seen from above;
    * the canopy rim: faces with a vertex on the glass (the glass outline must not move, or the two parts part).
    `outline_px` <= 0 turns the outline lock off."""
    from PIL import Image, ImageDraw  # noqa: PLC0415
    from scipy import ndimage  # noqa: PLC0415

    keep = np.zeros(len(pf), dtype=bool)
    if len(glass_pts):
        from scipy.spatial import cKDTree  # noqa: PLC0415

        on_glass = np.array([len(x) > 0 for x in cKDTree(glass_pts).query_ball_point(pv, 1e-6)])
        rim = on_glass[pf].any(axis=1)
        keep |= rim
        log("skin: %d faces round the canopy rim kept" % rim.sum())
    if outline_px > 0:
        lo = pv[:, :2].min(axis=0) - 0.01
        size = np.ceil((pv[:, :2].max(axis=0) + 0.01 - lo) * res).astype(int)
        img = Image.new("1", (int(size[0]), int(size[1])), 0)
        d = ImageDraw.Draw(img)
        p2 = (pv[:, :2] - lo) * res
        for f in pf:
            d.polygon([tuple(p2[i]) for i in f], fill=1, outline=1)
        inside = np.array(img, dtype=bool)   # rows = y (span), cols = x (length)
        dist = ndimage.distance_transform_edt(inside)
        px = np.clip(p2.astype(int), 0, [size[0] - 1, size[1] - 1])
        edge_v = dist[px[:, 1], px[:, 0]] <= outline_px
        edge_f = edge_v[pf].sum(axis=1) >= 2
        keep |= edge_f
        log("skin: %d vertices on the top-view outline, %d faces along it kept" % (edge_v.sum(), edge_f.sum()))
    return keep if keep.any() else None


def _collapse(pymeshlab, pv: np.ndarray, pf: np.ndarray, target: int, keep) -> tuple:
    """MeshLab quadric edge collapse to `target` faces; faces where `keep` is set are left as they are.
    Open edges keep their vertices (preserveboundary), so separately collapsed parts still meet."""
    ms = pymeshlab.MeshSet()
    if keep is None:
        ms.add_mesh(pymeshlab.Mesh(vertex_matrix=pv, face_matrix=pf))
    else:
        ms.add_mesh(pymeshlab.Mesh(vertex_matrix=pv, face_matrix=pf, f_scalar_array=keep.astype(np.float64)))
        ms.compute_selection_by_condition_per_face(condselect="fq < 0.5")
    ms.meshing_decimation_quadric_edge_collapse(targetfacenum=target, qualitythr=0.4, preserveboundary=True,
                                                boundaryweight=2.0, preservenormal=True, preservetopology=False,
                                                optimalplacement=True, planarquadric=True, planarweight=0.002,
                                                qualityweight=False, autoclean=True, selected=keep is not None)
    mm = ms.current_mesh()
    return mm.vertex_matrix(), mm.face_matrix()


def deviation(hi: bpy.types.Object, lo: bpy.types.Object) -> tuple:
    """Distances lo → hi (how far the new skin strays) and hi → lo (what the new skin lost), model units."""
    out = []
    for a, b in ((lo, hi), (hi, lo)):
        bm = bmesh.new()
        bm.from_mesh(b.data)
        t = BVHTree.FromBMesh(bm)
        bm.free()
        d = sorted((t.find_nearest(v.co)[3] or 0.0) for v in a.data.vertices)
        out += [d[int(len(d) * 0.99)], d[-1]]
    return tuple(out)


def even_out(lo: bpy.types.Object, sharp: float, iters: int, factor: float) -> int:
    """Laplacian smoothing (volume kept) of a mesh's broad surfaces: the hangar skin was voxel-remeshed from a
    Meshy scan and its wings and fuselage undulate, and the low mesh collapsed from it keeps the long waves; shaded
    as they are, they show as blotchy light and dark patches. Vertices
    on open edges, on hard edges (sharper than `sharp`) and next to them do not move, so the outline, the canopy
    edge, wing edges and fin edges stay where they were. Returns the number of vertices held."""
    if iters <= 0:
        return 0
    bm = bmesh.new()
    bm.from_mesh(lo.data)
    lim = math.radians(sharp)
    hold = set()
    for e in bm.edges:
        if e.is_boundary or (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim) or \
                len({f.material_index for f in e.link_faces}) > 1:
            for v in e.verts:
                hold.add(v.index)
                for e2 in v.link_edges:
                    hold.add(e2.other_vert(v).index)
    bm.free()
    vg = lo.vertex_groups.new(name="even")
    vg.add(list(range(len(lo.data.vertices))), 1.0, "REPLACE")
    if hold:
        vg.add(list(hold), 0.0, "REPLACE")
    m = lo.modifiers.new("even", "LAPLACIANSMOOTH")
    m.iterations = iters
    m.lambda_factor = factor
    m.lambda_border = 0.0
    m.use_volume_preserve = True
    m.use_normalized = True
    m.vertex_group = "even"
    activate(lo)
    bpy.ops.object.modifier_apply(modifier=m.name)
    lo.vertex_groups.clear()
    return len(hold)




def _hangar_normals(lo: bpy.types.Object, hi: bpy.types.Object, cn: np.ndarray, fnl: np.ndarray) -> np.ndarray:
    """Corner normals of `lo` replaced by the hangar skin's smooth normal under the corner, where that is
    trustworthy: the outermost hangar face within HN_DIST along the low face's normal, its interpolated normal within
    45 deg of both the low face and the evened normal `cn` and within 30 deg of the hit face itself (so the far side
    of a fin, a coincident inner face of the welded sections or a crease the low mesh does not have never lend a
    normal); the other corners keep `cn`. Each corner is sampled a little inside its
    face, so a corner on a ridge takes the side of the ridge its face lies on.

    Why: the evened copy rounds off crisp narrow features the low mesh only follows in a zigzag, such as the spine
    ridge of «Кит-2» between the engines, which shaded as a row of light and dark lumps; the hangar normals there
    are smooth along the ridge and match the hangar model."""
    bm = bmesh.new()
    bm.from_mesh(hi.data)
    glass = {i for i, m in enumerate(hi.data.materials) if m.name.startswith("glass")}
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    vn = np.array([v.normal[:] for v in bm.verts])
    part = bm.faces.layers.int.get("part")
    me = lo.data
    co = np.array([v.co[:] for v in me.vertices])
    lv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)
    cen = np.array([p.center[:] for p in me.polygons])
    lp = np.repeat(np.arange(len(me.polygons)), [p.loop_total for p in me.polygons])
    pts = co[lv] * 0.85 + cen[lp] * 0.15
    out = cn.copy()
    took = 0
    for i, pt in enumerate(pts):
        # the outermost hangar surface along the low face's normal: the one seen, not an inner face behind it
        loc, fno, fi, _ = tree.ray_cast(tuple(pt + fnl[i] * HN_DIST), tuple(-fnl[i]), 2.0 * HN_DIST)
        if fi is None or bm.faces[fi].material_index in glass or fnl[i] @ np.array(fno[:]) < 0.0:
            continue
        if part is not None and bm.faces[fi][part]:
            continue   # a moving section welded into its cut-out: its rim vertices carry bent normals
        f = bm.faces[fi]
        vs = [v.index for v in f.verts]
        # inverse-distance weights of the face's vertex normals at the hit point
        w = np.array([1.0 / (1e-6 + (bm.verts[j].co - loc).length) for j in vs])
        n = (vn[vs] * w[:, None]).sum(axis=0)
        n /= np.linalg.norm(n) + 1e-12
        # a vertex shared with welded inner faces (moving sections, nacelle joins) has a bent normal: then the hit
        # face's normal and the low face disagree with it, and the corner keeps the evened normal
        if n @ fnl[i] > 0.707 and n @ cn[i] > 0.707 and n @ np.array(fno[:]) > 0.866:
            out[i] = n
            took += 1
    bm.free()
    log("shading: %d of %d corners took the hangar normal" % (took, len(pts)))
    return out


def shade_low(lo: bpy.types.Object, sharp: float, iters: int, factor: float, hi=None) -> tuple:
    """Shading normals of the low mesh: the smooth normals (hard past `sharp`) of an evened-out copy of the low
    mesh itself, handed over corner by corner (the copy has the same topology, so each corner gets the normal of
    the very same corner, never of a neighbour or of the far side of a fin). A corner whose evened normal would
    lie more than 60° from its own face keeps its plain smooth normal. The shape itself is not moved.

    Why not the hangar's normals: the welded hangar mesh has coincident inner faces where the moving sections and
    the nacelles meet the hull (1.8k non-manifold edges on «Кит-1»). A nearest-face copy (DATA_TRANSFER,
    POLYINTERP_NEAREST) took those, or the far side of thin fins, for 5-15 % of the low mesh's corners and gave them
    a normal more than 90° from their own face: dark creases, specks and faceted triangles in the game.
    Returns (evened vertices held, corners that kept their plain normal)."""
    activate(lo)
    bpy.ops.object.shade_smooth()
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(sharp), keep_sharp_edges=True)
    if iters <= 0:
        return 0, 0
    ev = lo.copy()
    ev.data = lo.data.copy()
    bpy.context.scene.collection.objects.link(ev)
    held = even_out(ev, sharp, iters, factor)
    n = len(lo.data.loops)
    cn = np.empty(n * 3)
    ev.data.corner_normals.foreach_get("vector", cn)
    cn = cn.reshape(-1, 3)
    own = np.empty(n * 3)
    lo.data.corner_normals.foreach_get("vector", own)
    own = own.reshape(-1, 3)
    fn = np.empty(len(lo.data.polygons) * 3)
    lo.data.polygons.foreach_get("normal", fn)
    fn = fn.reshape(-1, 3)
    lp = np.repeat(np.arange(len(lo.data.polygons)), [p.loop_total for p in lo.data.polygons])
    bad = np.einsum("ij,ij->i", cn, fn[lp]) < 0.5
    cn[bad] = own[bad]
    if hi is not None:
        cn = _hangar_normals(lo, hi, cn, fn[lp])
    lo.data.normals_split_custom_set([tuple(v) for v in cn])
    me = ev.data
    bpy.data.objects.remove(ev)
    bpy.data.meshes.remove(me)
    return held, int(bad.sum())


def normal_report(lo: bpy.types.Object) -> tuple:
    """Share of the low mesh's corners whose shading normal is more than 60° / 90° from their own face (a corner
    that far shades as a dark crease or speck); returned for the log and the final OK line."""
    me = lo.data
    cn = np.empty(len(me.loops) * 3)
    me.corner_normals.foreach_get("vector", cn)
    cn = cn.reshape(-1, 3)
    fn = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", fn)
    fn = fn.reshape(-1, 3)
    lp = np.repeat(np.arange(len(me.polygons)), [p.loop_total for p in me.polygons])
    d = np.einsum("ij,ij->i", cn, fn[lp])
    return float((d < 0.5).mean()), float((d < 0.0).mean())


def unwrap(lo: bpy.types.Object, tex: int) -> None:
    """Smart UV Project with ~8 px between islands at `tex`."""
    activate(lo)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.0, area_weight=0.0, correct_aspect=True,
                             scale_to_bounds=False)
    margin = 8.0 / tex
    try:
        bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, rotate_method="ANY", scale=True,
                                merge_overlap=False, margin_method="FRACTION", margin=margin, shape_method="CONCAVE")
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def fill_misses(mask: bpy.types.Image, imgs: list) -> int:
    """Give every texel the mask marks as uncovered (< 0.5) the value of the nearest covered texel in each image;
    returns how many texels were filled. Fixes black bake-miss patches without a longer ray, which would pick up
    the far side of thin parts."""
    from scipy import ndimage
    w, h = mask.size
    m = np.empty(w * h * 4, dtype=np.float32)
    mask.pixels.foreach_get(m)
    miss = m.reshape(h, w, 4)[:, :, 0] < 0.5
    n = int(miss.sum())
    if n == 0 or n == miss.size:
        return 0
    _, (iy, ix) = ndimage.distance_transform_edt(miss, return_indices=True)
    for im in imgs:
        px = np.empty(w * h * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        px = px[iy, ix]
        im.pixels.foreach_set(px.ravel())
        im.update()
    log("filled %d uncovered texels (%.1f%% of the atlas)" % (n, 100.0 * n / miss.size))
    return n


def bake(hi: bpy.types.Object, lo: bpy.types.Object, tex: int, normal: str, samples: int, threads: int = 0) -> dict:
    """Paint, ORM and tangent normals of `hi` onto `lo`'s UV with `threads` CPU threads (0: all); returns
    {suffix: image}."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    if threads > 0:
        sc.render.threads_mode = "FIXED"
        sc.render.threads = threads
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    rb = sc.render.bake
    rb.use_selected_to_active = True
    rb.use_cage = False
    rb.cage_extrusion = 0.008
    rb.max_ray_distance = 0.02
    rb.margin = 16
    rb.margin_type = "EXTEND"
    rb.use_clear = True
    skin_src = next(m for m in hi.data.materials if not m.name.startswith("glass"))
    sn = skin_src.node_tree.nodes
    sl = skin_src.node_tree.links
    sbsdf = next(n for n in sn if n.type == "BSDF_PRINCIPLED")

    def src_img(socket: str):
        s = sbsdf.inputs[socket]
        if not s.is_linked:
            return None
        n = s.links[0].from_node
        while n.type != "TEX_IMAGE":
            ins = [i for i in n.inputs if i.is_linked]
            if not ins:
                return None
            n = ins[0].links[0].from_node
        return n

    col_node = src_img("Base Color")
    orm_node = src_img("Roughness") or src_img("Metallic")
    # one bake material on every face of lo while baking; the final materials come back after
    keep = [p.material_index for p in lo.data.polygons]
    final = list(lo.data.materials)
    bmat = bpy.data.materials.new("bake")
    bmat.use_nodes = True
    lo.data.materials.clear()
    lo.data.materials.append(bmat)
    for p in lo.data.polygons:
        p.material_index = 0
    tn = bmat.node_tree.nodes

    def target(img):
        n = tn.new("ShaderNodeTexImage")
        n.image = img
        for x in tn:
            x.select = False
        n.select = True
        tn.active = n

    def new_img(name: str, srgb: bool):
        im = bpy.data.images.new(name, tex, tex, alpha=False, float_buffer=False)
        im.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
        return im

    def run(kind: str, **kw) -> None:
        activate(lo)
        hi.select_set(True)
        bpy.context.view_layer.objects.active = lo
        t = time.time()
        bpy.ops.object.bake(type=kind, **kw)
        log("baked %s in %.0fs" % (kind, time.time() - t))

    out = {}
    if normal != "none":
        img = new_img("nrm", False)
        target(img)
        nrm_link = sbsdf.inputs["Normal"].links[0] if sbsdf.inputs["Normal"].is_linked else None
        nrm_from = nrm_link.from_socket if nrm_link else None
        if normal == "geo" and nrm_link is not None:
            sl.remove(nrm_link)
        run("NORMAL", normal_space="TANGENT")
        if normal == "geo" and nrm_from is not None:
            sl.new(nrm_from, sbsdf.inputs["Normal"])
        out["nrm"] = img
    for suf, node, srgb in (("col", col_node, True), ("orm", orm_node, False)):
        if node is None:
            continue
        em = sbsdf.inputs["Emission Color"]
        for lk in list(em.links):
            sl.remove(lk)
        sl.new(node.outputs["Color"], em)
        sbsdf.inputs["Emission Strength"].default_value = 1.0
        img = new_img(suf, srgb)
        target(img)
        run("EMIT")
        for lk in list(em.links):
            sl.remove(lk)
        sbsdf.inputs["Emission Strength"].default_value = 0.0
        out[suf] = img
    # coverage: white where a ray found the hangar skin. Texels whose ray missed (or hit hangar glass) bake black
    # and show as black holes in the paint, so they take the colour of the nearest covered texel instead.
    em = sbsdf.inputs["Emission Color"]
    for lk in list(em.links):
        sl.remove(lk)
    old_em = tuple(em.default_value)
    em.default_value = (1.0, 1.0, 1.0, 1.0)
    sbsdf.inputs["Emission Strength"].default_value = 1.0
    mask = new_img("mask", False)
    target(mask)
    run("EMIT")
    em.default_value = old_em
    sbsdf.inputs["Emission Strength"].default_value = 0.0
    fill_misses(mask, [im for k, im in out.items() if k != "nrm"])
    bpy.data.images.remove(mask)
    lo.data.materials.clear()
    for m in final:
        lo.data.materials.append(m)
    for p, k in zip(lo.data.polygons, keep):
        p.material_index = k
    return out


def write_images(imgs: dict, dst: str, jpeg: int) -> tuple:
    """Save the baked images next to the GLB under Godot's extracted names and pack them for the export;
    remove the model's old extracted images. Returns ({suffix: packed image}, the temp folder to remove after
    the export)."""
    base = os.path.splitext(os.path.basename(dst))[0]
    dst_base = os.path.splitext(os.path.abspath(dst))[0]
    ddir = os.path.dirname(dst_base)
    for f in os.listdir(ddir):
        if re.fullmatch(re.escape(base) + r"_((Image_)?\d+|col|orm|nrm|color|normal)\.(png|jpg)(\.import)?", f):
            os.remove(os.path.join(ddir, f))
            log("removed old", f)
    tmpd = tempfile.mkdtemp()
    out = {}
    from PIL import Image as PILImage  # noqa: PLC0415

    for suf, im in imgs.items():
        im.filepath_raw = os.path.join(tmpd, suf + ".png")
        im.file_format = "PNG"
        im.save()
        path = im.filepath_raw
        if suf != "nrm":   # JPEG blocks show on a normal map: it stays PNG
            path = os.path.join(tmpd, suf + ".jpg")
            PILImage.open(im.filepath_raw).convert("RGB").save(path, quality=jpeg, subsampling=0, optimize=True)
        ni = bpy.data.images.load(path)
        ni.colorspace_settings.name = im.colorspace_settings.name
        ni.name = suf
        ni.pack()
        out[suf] = ni
        shutil.copyfile(path, dst_base + "_" + os.path.basename(path))
        log("image %s: %.1f MB" % (os.path.basename(path), os.path.getsize(path) / 1e6))
    return out, tmpd


def skin_material(m: bpy.types.Material, imgs: dict) -> None:
    """glTF-shaped PBR skin: paint, ORM (roughness G, metal B) through Separate Color, tangent normal map if baked."""
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for n in list(nt.nodes):
        if n.type == "TEX_IMAGE":
            nt.nodes.remove(n)
    nc = nt.nodes.new("ShaderNodeTexImage")
    nc.image = imgs["col"]
    nt.links.new(nc.outputs["Color"], bsdf.inputs["Base Color"])
    if "orm" in imgs:
        no = nt.nodes.new("ShaderNodeTexImage")
        no.image = imgs["orm"]
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(no.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    if "nrm" in imgs:
        nn = nt.nodes.new("ShaderNodeTexImage")
        nn.image = imgs["nrm"]
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    m.use_backface_culling = False


def main() -> int:
    """Hangar GLB → battle GLB, see the module docstring."""
    ap = argparse.ArgumentParser(description="Battle model of a player plane baked from its hangar model")
    ap.add_argument("src", help="hangar GLB (its extracted *_col.jpg … next to it)")
    ap.add_argument("dst", help="battle GLB, fh_battle_<class>_<level>.glb")
    ap.add_argument("--tris", type=int, default=12000, help="triangle budget of the whole model")
    ap.add_argument("--tex", type=int, default=2048, help="baked texture size")
    ap.add_argument("--normal", default="none", choices=["none", "geo", "full"],
                    help="none: no normal map, the hangar's shading normals are copied onto the low mesh (the "
                         "remeshed hangar models carry no normal map either); geo / full: a baked normal map "
                         "from the hangar geometry / and its normal map")
    ap.add_argument("--sharp", type=float, default=40.0, help="edges sharper than this (degrees) are shaded hard")
    ap.add_argument("--smooth", type=int, default=40,
                    help="Laplacian iterations evening out the copy of the low mesh its shading normals come from")
    ap.add_argument("--smooth-factor", dest="smooth_factor", type=float, default=0.5)
    ap.add_argument("--glass", type=float, default=1.0,
                    help="share of the canopy glass triangles kept (1: the hangar glass as it is)")
    ap.add_argument("--outline", type=float, default=2.0,
                    help="skin faces within this many pixels (2000 px per model length) of the top-view outline are "
                         "not collapsed; 0: off")
    ap.add_argument("--shade", default="hangar", choices=["hangar", "even"],
                    help="shading normals: hangar — the hangar's smooth normals where they agree with the low face, "
                         "the evened copy elsewhere; even — the evened copy only")
    ap.add_argument("--threads", type=int, default=0, help="Cycles CPU threads (0: all)")
    ap.add_argument("--samples", type=int, default=4)
    ap.add_argument("--jpeg", type=int, default=90)
    a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    if os.path.abspath(a.src) == os.path.abspath(a.dst):
        sys.exit("input and output must differ")
    hi = load_hangar(a.src)
    clean_hi(hi)
    lo = decimate(hi, a.tris, a.glass, a.sharp, a.outline)
    held, kept = shade_low(lo, a.sharp, a.smooth, a.smooth_factor, hi if a.shade == "hangar" else None)
    log("shading: evened copy %d iterations, %d vertices held, %d corners kept their plain normal" % (a.smooth, held, kept))
    bad60, bad90 = normal_report(lo)
    log("shading normals > 60deg from their face: %.3f%%, > 90deg: %.3f%%" % (100 * bad60, 100 * bad90))
    dev = deviation(hi, lo)
    log("deviation lo->hi 99%% %.5f max %.5f; hi->lo 99%% %.5f max %.5f" % dev)

    unwrap(lo, a.tex)
    imgs, tmpd = write_images(bake(hi, lo, a.tex, a.normal, a.samples, a.threads), a.dst, a.jpeg)
    skin_material(lo.data.materials[0], imgs)
    bpy.data.objects.remove(hi)
    base = os.path.splitext(os.path.basename(a.dst))[0]
    lo.name = base
    lo.data.name = base
    lo.matrix_world = Matrix.Identity(4)
    activate(lo)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(a.dst), export_format="GLB", use_selection=True,
                              export_tangents="nrm" in imgs, export_normals=True, export_texcoords=True,
                              export_materials="EXPORT", export_yup=True, export_image_format="AUTO")
    shutil.rmtree(tmpd, ignore_errors=True)   # the images are packed into the GLB and copied next to it
    tris = sum(len(p.vertices) - 2 for p in lo.data.polygons)
    log("done %s: %d tris, %.1f MB" % (a.dst, tris, os.path.getsize(a.dst) / 1e6))
    print("BATTLE_BAKE_OK tris=%d dev99=%.5f devmax=%.5f lost99=%.5f lostmax=%.5f" % ((tris,) + dev))
    return 0


if __name__ == "__main__":
    sys.exit(main())
