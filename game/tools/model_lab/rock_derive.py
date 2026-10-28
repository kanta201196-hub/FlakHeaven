"""Extra outcrop and boulder variants derived from the Highland rock scans (weak-models list, items 4 and 6;
Kanta 28.10.2026 approved replacing the weak Highland rocks).

Why: the Meshy outcrop b01 and boulder pile b02 were low-poly "potatoes" and left the variant list
(BiomeProps.ROCK_VARIANTS), so only the photo-scans b12 (outcrop_b) and b13 (boulders_b) stayed. One model per
kind repeated across a slope at gameplay height, so this makes one more of each from the same scans, without new
downloads (same textures, same look):
  b12_rock_outcrop_c - the outcrop scan mirrored and made shorter and higher, with a copy of the boulder scan's
                       light mesh (b13_boulders_b_lite) fallen against its foot; both textures go into one
                       2048 x 1024 atlas (colour and normal), so it is still one mesh and one material;
  b13_boulders_c     - the boulder scan's row folded into a pile: cut at the gap between two boulders, the far
                       half turned round behind the near one, mirrored; plus its light copy b13_boulders_c_lite
                       from the light scan mesh the same way (BiomeProps.LOW_POLY).
Every model stands on y = 0 by its lowest point, centred, largest X/Z size = 1, like rock_prep.py.

Run (repo root; trimesh, numpy, Pillow):
    python3 game/tools/model_lab/rock_derive.py   -> game/models/biome/b12_rock_outcrop_c.glb, b13_boulders_c.glb,
                                                     b13_boulders_c_lite.glb
"""
from __future__ import annotations

import io
import os
import sys

import numpy as np
import trimesh
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "models", "biome")


def load(name: str) -> trimesh.Trimesh:
    """The single textured mesh of a biome GLB"""
    s = trimesh.load(os.path.join(OUT, name + ".glb"), force="scene")
    return list(s.geometry.values())[0]


def shaped(m: trimesh.Trimesh, scale: tuple, yaw: float = 0.0, mirror: bool = True) -> trimesh.Trimesh:
    """A copy of m scaled per axis, turned about y by yaw (radians) and mirrored in x (winding flipped so the
    faces still face out), UVs and material kept"""
    v = np.asarray(m.vertices, np.float64) * np.asarray(scale)
    if mirror:
        v[:, 0] = -v[:, 0]
    c, s = np.cos(yaw), np.sin(yaw)
    v = v @ np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])
    f = np.asarray(m.faces)[:, ::-1] if mirror else np.asarray(m.faces)
    out = trimesh.Trimesh(vertices=v, faces=f, process=False)
    out.visual = trimesh.visual.TextureVisuals(uv=np.asarray(m.visual.uv), material=m.visual.material)
    return out


def _gap(m: trimesh.Trimesh) -> float:
    """x of the narrowest cross-section in the middle third of a boulder row (the gap between two boulders)"""
    lo, hi = m.bounds
    xs = np.linspace(lo[0] + (hi[0] - lo[0]) / 3, hi[0] - (hi[0] - lo[0]) / 3, 40)
    v = np.asarray(m.vertices)
    tri = np.asarray(m.triangles)
    span = [np.sum((tri[:, :, 0].min(1) < x) & (tri[:, :, 0].max(1) > x)) for x in xs]
    return float(xs[int(np.argmin(span))])


def fold(m: trimesh.Trimesh, cut: float) -> trimesh.Trimesh:
    """Faces left of x = cut stay; the rest turn 160 degrees about y and sit behind them (z), mirrored in x"""
    c = np.asarray(m.triangles_center)
    keep_a = np.nonzero(c[:, 0] < cut)[0]
    keep_b = np.nonzero(c[:, 0] >= cut)[0]
    parts = []
    for k, (yaw, dz) in ((keep_a, (0.0, 0.0)), (keep_b, (2.8, 1.0))):
        sub = m.submesh([k], append=True, repair=False)
        sub.visual = trimesh.visual.TextureVisuals(uv=sub.visual.uv, material=m.visual.material)
        sub = shaped(sub, (1.0, 1.0, 1.0), yaw=yaw)
        parts.append(sub)
    a, b = parts
    alo, ahi = a.bounds
    blo, bhi = b.bounds
    # the far half behind the near one, overlapping a third of its depth, ends roughly level
    b.apply_translation([(alo[0] + ahi[0]) / 2 - (blo[0] + bhi[0]) / 2 + 0.15 * (ahi[0] - alo[0]),
                         alo[1] - blo[1], ahi[2] - blo[2] - 0.35 * (ahi[2] - alo[2])])
    out = trimesh.util.concatenate([trimesh.Trimesh(a.vertices, a.faces, process=False),
                                    trimesh.Trimesh(b.vertices, b.faces, process=False)])
    out.visual = trimesh.visual.TextureVisuals(uv=np.concatenate([a.visual.uv, b.visual.uv]),
                                               material=m.visual.material)
    return out


def stand(m: trimesh.Trimesh) -> trimesh.Trimesh:
    """On y = 0 by the lowest point, centred in plan, largest X/Z size 1"""
    lo, hi = m.bounds
    m.apply_translation([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])
    m.apply_scale(1.0 / max(m.extents[0], m.extents[2]))
    return m


def export(m: trimesh.Trimesh, name: str) -> None:
    path = os.path.join(OUT, name + ".glb")
    trimesh.Scene(m).export(path, include_normals=True)   # without normals Godot lights it darker
    print("%s: %d triangles, height %.2f of width, %d KB" % (name, len(m.faces), m.extents[1],
                                                             os.path.getsize(path) // 1024))


def jpeg(im: Image.Image, q: int = 90) -> Image.Image:
    """The image round-tripped through JPEG, so the GLB embeds it as JPEG (as rock_prep.py does)"""
    b = io.BytesIO()
    im.convert("RGB").save(b, format="JPEG", quality=q)
    b.seek(0)
    return Image.open(b)


def atlas_pair(a: trimesh.Trimesh, b: trimesh.Trimesh) -> trimesh.Trimesh:
    """a and b in one mesh: a's textures on the left half of a 2:1 atlas, b's on the right (colour and normal)"""
    ma, mb = a.visual.material, b.visual.material
    size = max(ma.baseColorTexture.size[0], mb.baseColorTexture.size[0])

    def pair(ia, ib):
        im = Image.new("RGB", (size * 2, size))
        im.paste(ia.convert("RGB").resize((size, size), Image.LANCZOS), (0, 0))
        im.paste(ib.convert("RGB").resize((size, size), Image.LANCZOS), (size, 0))
        return jpeg(im)

    ua = np.asarray(a.visual.uv, np.float64).copy()
    ub = np.asarray(b.visual.uv, np.float64).copy()
    ua[:, 0] = np.clip(ua[:, 0], 0.0, 1.0) * 0.5
    ub[:, 0] = np.clip(ub[:, 0], 0.0, 1.0) * 0.5 + 0.5
    ma2 = trimesh.Trimesh(vertices=a.vertices, faces=a.faces, process=False)
    mb2 = trimesh.Trimesh(vertices=b.vertices, faces=b.faces, process=False)
    out = trimesh.util.concatenate([ma2, mb2])
    mat = trimesh.visual.material.PBRMaterial(baseColorTexture=pair(ma.baseColorTexture, mb.baseColorTexture),
                                              normalTexture=pair(ma.normalTexture, mb.normalTexture),
                                              metallicFactor=0.0, roughnessFactor=0.95)
    out.visual = trimesh.visual.TextureVisuals(uv=np.concatenate([ua, ub]), material=mat)
    return out


def main() -> int:
    out_b = load("b12_rock_outcrop_b")
    bld_lite = load("b13_boulders_b_lite")
    # the light copy carries no textures (the game gives it the full model's material); its UVs are the full one's
    bld_lite.visual = trimesh.visual.TextureVisuals(uv=bld_lite.visual.uv, material=load("b13_boulders_b").visual.material)
    # the outcrop shorter (x 0.78) and higher (y 1.3); the boulders at its foot on the long side, half its length
    rock = shaped(out_b, (0.78, 1.3, 1.0))
    lo, hi = rock.bounds
    pile = shaped(bld_lite, (0.5, 0.55, 0.5), yaw=0.35, mirror=False)
    plo, phi = pile.bounds
    pile.apply_translation([lo[0] + 0.32 * (hi[0] - lo[0]) - (plo[0] + phi[0]) / 2, lo[1] - plo[1],
                            hi[2] - 0.12 * (hi[2] - lo[2]) - (plo[2] + phi[2]) / 2])
    export(stand(atlas_pair(rock, pile)), "b12_rock_outcrop_c")
    # the boulder row folded into a pile: cut at the narrowest gap between boulders near the middle, the far
    # half turned round and set behind the near one; mirrored, so neither half repeats the old silhouette
    full = load("b13_boulders_b")
    cut = _gap(full)
    for src, dst in (("b13_boulders_b", "b13_boulders_c"), ("b13_boulders_b_lite", "b13_boulders_c_lite")):
        m = load(src)
        if src.endswith("_lite"):
            m.visual = trimesh.visual.TextureVisuals(uv=m.visual.uv, material=full.visual.material)
        out = stand(fold(m, cut))
        if src.endswith("_lite"):   # like biome_lite.py: no images (the game gives it the full model's material)
            out.visual = trimesh.visual.TextureVisuals(uv=out.visual.uv, material=trimesh.visual.material.PBRMaterial(
                name="lite", baseColorFactor=[255, 255, 255, 255], metallicFactor=0.0, roughnessFactor=1.0))
        export(out, dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
