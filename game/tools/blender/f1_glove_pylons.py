"""S11-07 (Kanta, playtest 3.5-s11): «Оса» lvl 1 (fighter_1) keeps the Sketchfab source's two glove pylons — thin
skin-coloured plates under the fixed wing glove (x -0.110…0.059, |z| 0.087…0.094, y -0.032…-0.005 in glTF axes:
nose +X, up +Y, length 1). The game hangs its own pylons and missiles, so the leftover plates read as a second,
empty missile mount next to the real one. They are separate loose parts of the source object `mig23mld_fuz_nab_0`;
sf_recipes.RECIPES["fighter_1"]["kill_faces"] drops them on the next full rework, and this script removes them from
a finished GLB (battle or hangar) without re-baking.

Only the triangle list changes (glb_io.py): vertices, UVs, materials and embedded images stay byte for byte, so Godot
keeps the extracted textures. A loose part (welded connected component) is removed only when every triangle centre
lies inside one of BOXES, so the glove skin around the plates is never cut.

Run: python3 -I game/tools/blender/f1_glove_pylons.py <in.glb> <out.glb>   (prints the removed parts; exit 1 if none)"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

# glTF axes (as in Godot): (x0, x1, y0, y1, z0, z1); one box per side, a little larger than the plate
BOXES = [(-0.115, 0.062, -0.036, -0.003, 0.083, 0.097), (-0.115, 0.062, -0.036, -0.003, -0.097, -0.083)]


def loose_parts(w, t):
    """Welded connected components: label per triangle (vertices closer than 1e-5 count as one)."""
    q = np.round(w / 1e-5).astype(np.int64)
    _, weld = np.unique(q, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    par = np.arange(weld.max() + 1)

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for a, b, c in weld[t]:
        ra = find(a)
        par[find(b)] = ra
        par[find(c)] = ra
    return np.array([find(v) for v in weld[t][:, 0]])


def main() -> int:
    src, dst = sys.argv[1], sys.argv[2]
    g = glb_io.load(src)
    w, t = g.mesh_world(0, 0)
    cen = w[t].mean(1)
    inside = np.zeros(len(t), bool)
    for b in BOXES:
        inside |= ((cen[:, 0] >= b[0]) & (cen[:, 0] <= b[1]) & (cen[:, 1] >= b[2]) & (cen[:, 1] <= b[3])
                   & (cen[:, 2] >= b[4]) & (cen[:, 2] <= b[5]))
    lab = loose_parts(w, t)
    kill = np.zeros(len(t), bool)
    for r in np.unique(lab[inside]):
        part = lab == r
        if inside[part].all():
            kill |= part
            p = w[t[part]].reshape(-1, 3)
            print("removed part: %d tris, min %s max %s" % (part.sum(), p.min(0).round(3), p.max(0).round(3)))
    if not kill.any():
        print("no glove pylons found")
        return 1
    print("tris %d -> %d" % (len(t), (~kill).sum()))
    g.set_indices(0, 0, t[~kill])
    g.save(dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
