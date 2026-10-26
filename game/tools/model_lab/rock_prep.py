"""Rock and spire variants for the Highlands from photo-scans (VIS-01, Kanta 26.10.2026).

Why: the Highlands had one outcrop, one boulder pile and one spire model, so every rock group on the map
looked the same ("compose them so it does not look monotonous"). This turns CC0 / CC BY scans (Poly Haven,
Sketchfab; authors in game/models/CREDITS.md) into biome models the way biome_prep.py does for Meshy ones:

1. load the source with node transforms applied; several meshes with their own textures go into one
   texture atlas, so the game draws the model with one material (one MultiMesh surface);
2. cut away what is not rock: the scan's ground plate (faces below a height fraction), vegetation
   (green texels under the face) and the small loose bits these cuts leave;
3. decimate to the budget with UVs kept (biome_lite.decimate);
4. grade the colour to the Highlands rocks already in the game (mean and spread per channel of
   b01_rock_outcrop's texture, mixed with the scan's own so variants stay told apart), matte;
5. stand on y = 0, centred, largest X/Z size = 1 (BiomeProps scales to pixels), JPEG textures.

Run (from the repo root; the sources are untrusted downloads, so -I):
    python3 -I game/tools/model_lab/rock_prep.py <name> <source .glb/.gltf> [<name> <source> ...]
    -> game/models/biome/<name>.glb ; recipes below (MODELS).
Dependencies: trimesh, pymeshlab, numpy, Pillow (see decimate_glb.py).
"""
from __future__ import annotations

import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
import trimesh  # noqa: E402
from PIL import Image  # noqa: E402

from biome_lite import decimate  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "models", "biome")
REF = os.path.join(OUT, "b01_rock_outcrop_0.jpg")   # the colour the player already knows as Highlands rock

# name: tris, texture px, ground cut (fraction of height), cut vegetation, keep own colour (0..1),
#       around the top (fraction of the source width: keep only faces this close to the highest point in plan,
#       for a lone rock in a wide terrain scan; 0: all)
MODELS = {
    # Namaqualand Cliff 02 (Poly Haven): broken blocky outcrop
    "b12_rock_outcrop_b": (3000, 1024, 0.02, True, 0.35, 0.0),
    # Namaqualand Boulder 02 (Poly Haven): a row of big split boulders
    "b13_boulders_b": (3000, 1024, 0.03, True, 0.35, 0.0),
    # Desert Cliff 6 (WireframeArt): a stepped sandstone "pagoda" spire
    "b14_rock_spire_b": (3000, 1024, 0.0, False, 0.3, 0.0),
}


def _tex_of(g) -> Image.Image | None:
    m = getattr(g.visual, "material", None)
    img = getattr(m, "baseColorTexture", None) if m is not None else None
    if img is None and m is not None:
        img = getattr(m, "image", None)
    return img


def load_one(src: str, around: float, ground: float) -> trimesh.Trimesh:
    """All meshes of the source in world space, merged into one textured mesh (a texture atlas if several).
    The ground cut runs first, on every part against the whole model's height: a raw scan is mostly ground
    plate in many texture chunks, and only the chunks with rock left go into the atlas."""
    scene = trimesh.load(src, force="scene")
    parts = []
    for node in scene.graph.nodes_geometry:
        xf, gname = scene.graph[node]
        g = scene.geometry[gname].copy()
        g.apply_transform(xf)
        parts.append(g)
    if ground > 0 or around > 0:
        allv = np.concatenate([g.vertices for g in parts])
        top = allv[np.argmax(allv[:, 1])]
        r = around * float(np.max(np.ptp(allv[:, [0, 2]], axis=0)))
        near = [np.ones(len(g.faces), bool) if around <= 0 else
                np.hypot(g.triangles_center[:, 0] - top[0], g.triangles_center[:, 2] - top[2]) < r for g in parts]
        ys = np.concatenate([g.triangles_center[k, 1] for g, k in zip(parts, near)])
        lo, hi = ys.min(), ys.max()
        cut_parts = []
        for g, k in zip(parts, near):
            keep = np.nonzero(k & (g.triangles_center[:, 1] > lo + ground * (hi - lo)))[0]
            if len(keep) == 0:
                continue
            mat = g.visual.material
            sub = g.submesh([keep], append=True, repair=False)
            sub.visual = trimesh.visual.TextureVisuals(uv=sub.visual.uv, material=mat)
            cut_parts.append(sub)
        parts = cut_parts
    if len(parts) == 1:
        return parts[0]
    n = int(np.ceil(np.sqrt(len(parts))))
    cell = max(max(_tex_of(g).size) for g in parts)
    atlas = Image.new("RGB", (cell * n, cell * n), (128, 110, 90))
    meshes = []
    for i, g in enumerate(parts):
        ox, oy = i % n, i // n
        atlas.paste(_tex_of(g).convert("RGB").resize((cell, cell), Image.LANCZOS), (ox * cell, oy * cell))
        uv = np.asarray(g.visual.uv, dtype=np.float64).copy()
        # glTF v runs down the image: atlas cell (ox, oy) from the top-left
        uv[:, 0] = (np.clip(uv[:, 0], 0.0, 1.0) + ox) / n
        uv[:, 1] = (np.clip(uv[:, 1], 0.0, 1.0) + (n - 1 - oy)) / n
        m = trimesh.Trimesh(vertices=g.vertices, faces=g.faces, process=False)
        m.visual = trimesh.visual.TextureVisuals(uv=uv)
        meshes.append(m)
    out = trimesh.util.concatenate(meshes)
    mat = trimesh.visual.material.PBRMaterial(baseColorTexture=atlas, metallicFactor=0.0, roughnessFactor=1.0)
    out.visual = trimesh.visual.TextureVisuals(uv=out.visual.uv, material=mat)
    return out


def face_colors(m: trimesh.Trimesh) -> np.ndarray:
    """Texture colour (0..1 RGB) under each face centre"""
    img = np.asarray(_tex_of(m).convert("RGB"), dtype=np.float32) / 255.0
    h, w = img.shape[:2]
    uv = np.asarray(m.visual.uv)[m.faces].mean(axis=1)
    x = np.clip((np.mod(uv[:, 0], 1.0) * (w - 1)).astype(int), 0, w - 1)
    y = np.clip(((1.0 - np.mod(uv[:, 1], 1.0)) * (h - 1)).astype(int), 0, h - 1)
    return img[y, x]


def cut(m: trimesh.Trimesh, ground: float, veg: bool) -> trimesh.Trimesh:
    keep = np.ones(len(m.faces), bool)
    c = m.triangles_center
    lo, hi = m.bounds
    if ground > 0:
        keep &= c[:, 1] > lo[1] + ground * (hi[1] - lo[1])
    if veg:
        col = face_colors(m)
        r, g, b = col[:, 0], col[:, 1], col[:, 2]
        green = (g > r * 1.02) & (g > b * 1.08) & (col.max(axis=1) - col.min(axis=1) > 0.05)
        keep &= ~green
    mat = m.visual.material
    sub = m.submesh([np.nonzero(keep)[0]], append=True, repair=False)
    # drop the loose bits the cuts leave (tufts, ground crumbs): keep pieces with >= 2 % of the faces
    lab = components(sub)
    cnt = np.bincount(lab)
    big = np.nonzero(cnt[lab] >= 0.02 * len(sub.faces))[0]
    out = sub.submesh([big], append=True, repair=False)
    out.visual = trimesh.visual.TextureVisuals(uv=out.visual.uv, material=mat)
    return out


def components(m: trimesh.Trimesh) -> np.ndarray:
    """Connected piece of each face, vertices joined by position (UV seams split them in GLB); no scipy here"""
    key = np.round(m.vertices / (m.scale * 1e-5)).astype(np.int64)
    _, vid = np.unique(key, axis=0, return_inverse=True)
    vid = vid.reshape(-1)
    parent = np.arange(vid.max() + 1)

    def find(a: np.ndarray) -> np.ndarray:
        while True:
            pa = parent[a]
            if np.array_equal(pa, a):
                return a
            parent[a] = parent[pa]
            a = parent[a]

    f = vid[m.faces]
    for _ in range(64):   # union the corners of every face until nothing changes
        r = find(f.copy())
        lo = r.min(axis=1)
        changed = False
        for k in range(3):
            diff = r[:, k] != lo
            if diff.any():
                changed = True
                np.minimum.at(parent, r[diff, k], lo[diff])
        if not changed:
            break
    return np.unique(find(f[:, 0].copy()), return_inverse=True)[1]


def grade(img: Image.Image, own: float, used: np.ndarray) -> Image.Image:
    """Mean/spread per channel moved to the game's rock texture; `own` keeps part of the scan's colour.
    `used`: colours (0..1) under the model's faces, so empty atlas space does not skew the statistics"""
    ref = np.asarray(Image.open(REF).convert("RGB"), dtype=np.float32)
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    rm, rs = ref.reshape(-1, 3).mean(0), ref.reshape(-1, 3).std(0)
    am, as_ = used.mean(0) * 255.0, used.std(0) * 255.0 + 1e-3
    # own 0: the game rock's mean and spread; 1: the scan's own colour (the spread stays the scan's when it
    # is the smaller one, so a smooth scan does not get blotchy)
    tm = rm * (1.0 - own) + am * own
    ts = np.minimum(rs, as_) * (1.0 - own) + as_ * own
    t = (a - am) / as_ * ts + tm
    return Image.fromarray(np.clip(t, 0, 255).astype(np.uint8))


def jpeg(im: Image.Image, q: int = 90) -> Image.Image:
    b = io.BytesIO()
    im.convert("RGB").save(b, format="JPEG", quality=q)
    b.seek(0)
    return Image.open(b)


def prep(name: str, src: str) -> None:
    tris, tex, ground, veg, own, around = MODELS[name]
    m = load_one(src, around, ground)
    n0 = len(m.faces)
    m = cut(m, 0.0, veg)
    n1 = len(m.faces)
    src_mat = m.visual.material
    low = decimate(m, tris)
    col = _tex_of(m).convert("RGB")
    if max(col.size) > tex:
        col = col.resize((tex, tex * col.size[1] // col.size[0]), Image.LANCZOS)
    nrm = getattr(src_mat, "normalTexture", None)
    mat = trimesh.visual.material.PBRMaterial(baseColorTexture=jpeg(grade(col, own, face_colors(m))), metallicFactor=0.0,
                                              roughnessFactor=0.95)
    if nrm is not None:
        mat.normalTexture = jpeg(nrm.convert("RGB").resize(col.size, Image.LANCZOS))
    low.visual = trimesh.visual.TextureVisuals(uv=low.visual.uv, material=mat)
    lo, hi = low.bounds
    low.apply_translation([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])
    ext = low.extents
    low.apply_scale(1.0 / max(ext[0], ext[2]))
    out = os.path.join(OUT, name + ".glb")
    trimesh.Scene(low).export(out, include_normals=True)   # without normals Godot lights it darker
    print("%s: %d -> cut %d -> %d triangles, height %.2f of width, %d KB" % (
        name, n0, n1, len(low.faces), low.extents[1], os.path.getsize(out) // 1024))


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or len(a) % 2:
        print(__doc__)
        sys.exit(1)
    for i in range(0, len(a), 2):
        prep(a[i], a[i + 1])
