"""Light copy of a prepared biome model for mass placement (VIS-01, 2026-10-25).

Why: boulders are placed by the hundred (one MultiMesh per terrain chunk) and
each copy is only 10-30 px wide on screen at zoom 1.0, yet the prepared model
(biome_prep.py) has 3000 triangles. Godot's automatic LOD helps little: the
mesh has many UV seams, so the import stops at one LOD level (~1600
triangles), and a MultiMesh picks one LOD for the whole chunk.
This tool writes a decimated copy of an already prepared GLB:

- same coordinate frame as the input (no re-centering or re-scaling), so the
  game places the light copy exactly where the full model would be;
- UVs kept by texture-aware quadric decimation, so the full model's
  material and textures fit it (the game reuses that material; the output
  carries a plain white material and no images, so Godot extracts no
  duplicate textures).

Run (from the repo root):
    python3 game/tools/model_lab/biome_lite.py \
        game/models/biome/b02_boulders.glb \
        game/models/biome/b02_boulders_lite.glb --tris 600
Dependencies: pymeshlab, trimesh, numpy (see decimate_glb.py).
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

import numpy as np
import pymeshlab
import trimesh


def decimate(mesh: trimesh.Trimesh, target: int) -> trimesh.Trimesh:
    """Return a copy of a textured mesh with about `target` triangles and UVs kept."""
    ms = pymeshlab.MeshSet()
    uv = np.asarray(mesh.visual.uv, dtype=np.float64)
    ms.add_mesh(
        pymeshlab.Mesh(
            vertex_matrix=mesh.vertices, face_matrix=mesh.faces, v_tex_coords_matrix=uv
        )
    )
    # per-vertex UV -> per-corner UV, then weld the GLB seam split so seams
    # are not treated as borders that cannot be simplified
    ms.compute_texcoord_transfer_vertex_to_wedge()
    ms.meshing_merge_close_vertices(threshold=pymeshlab.PercentageValue(0.01))
    ms.meshing_decimation_quadric_edge_collapse_with_texture(
        targetfacenum=target,
        qualitythr=0.5,
        extratcoordw=1.0,
        preserveboundary=False,
        optimalplacement=True,
        preservenormal=True,
        planarquadric=True,
    )
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "m.obj"
        ms.save_current_mesh(str(path), save_wedge_texcoord=True, save_textures=False)
        out = trimesh.load(path, process=False, force="mesh")
    plain = trimesh.visual.material.PBRMaterial(
        baseColorFactor=[255, 255, 255, 255], metallicFactor=0.0, roughnessFactor=1.0
    )
    out.visual = trimesh.visual.TextureVisuals(uv=out.visual.uv, material=plain)
    out.vertex_attributes.clear()  # OBJ adds vertex colours; the game does not use them
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("src", type=Path, help="prepared GLB (output of biome_prep.py)")
    ap.add_argument("dst", type=Path, help="light GLB to write")
    ap.add_argument("--tris", type=int, default=600, help="target triangle count")
    args = ap.parse_args()
    if args.src.resolve() == args.dst.resolve():
        print("biome_lite: output must differ from input")
        return 1
    scene = trimesh.load(args.src, force="scene")
    if len(scene.geometry) != 1:
        print(f"biome_lite: expected one mesh, got {len(scene.geometry)}")
        return 1
    mesh = next(iter(scene.geometry.values()))
    lite = decimate(mesh, args.tris)
    lo0, hi0 = mesh.bounds
    lo1, hi1 = lite.bounds
    out = trimesh.Scene()
    out.add_geometry(lite, node_name="lite", geom_name="lite")
    out.export(args.dst, include_normals=True)  # without normals Godot lights it darker
    print(
        f"{args.dst.name}: {len(mesh.faces)} -> {len(lite.faces)} triangles, "
        f"bounds {np.round(lo0, 3)}..{np.round(hi0, 3)} -> {np.round(lo1, 3)}..{np.round(hi1, 3)}, "
        f"{args.dst.stat().st_size // 1024} KB"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
