"""S13-5 (Kanta 27.10: «Кит 2» flies with its nose-gear bay open): close the nose-gear bay Meshy baked into the
belly of «Кит» 2, in the hangar and the battle model.

remove_gear.py (T-2) dropped the gear legs and wheels but left the bay: a cavity going up into the belly with its two
doors hanging open below it, and mech_cut.py --close (S11-10) only closed the main-gear wells in the nacelles. Here the
bay is shut by moving vertices, without cutting: everything inside the bay outline is laid onto the belly surface
that the clean sections just ahead of and behind the bay describe (a ruled surface between them), the doors fold up
onto the line where they meet the belly, so their outer faces become zero-area and their inner faces, the floor and
the walls form a flush door panel. The panel keeps its own triangles but takes the UVs the belly just ahead of the
bay would have there (an affine fit of that skin, per side), so it carries the belly's paint, panel detail and
grime, and the cut of the old opening reads as the door outline. Normals follow the new surface.

Geometry is edited with numpy straight in the GLB (glb_io): vertex count, triangles and the embedded images stay as
they are, so Godot keeps the extracted textures (and livery.gd SRC tones).

Run from game/tools/blender (no Blender needed), in place is allowed:
  python3 -I gear_bay_close.py ../../models/hangar/fh_hangar_bomber_2.glb ../../models/hangar/fh_hangar_bomber_2.glb
  python3 -I gear_bay_close.py ../../models/battle/fh_battle_bomber_2.glb ../../models/battle/fh_battle_bomber_2.glb
Then `godot --headless --path game --import`."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

# bay of «Кит» 2 in Godot model axes (nose +X, up +Y, length 1): clean belly sections at XA (ahead) and XB (behind),
# the doors' hinge line |z| = ZJ, the region the doors reach (|z| < ZW) and how high the bay goes (Y_TOP)
XA, XB = 0.149, 0.2125
ZJ, ZW = 0.0205, 0.031
Y_TOP = -0.044
HULL_TOL = 0.0025   # a vertex outside the hinge line this close to the belly is belly skin, not a door
FIT_X = (0.085, 0.147)   # belly skin used for the UV fit


def write_accessor(g, i, arr):
    """Overwrite accessor i in place (same count and type), keeping min/max right for POSITION"""
    a = g.j["accessors"][i]
    bv = g.j["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    data = np.ascontiguousarray(arr, dtype=np.float32)
    stride = bv.get("byteStride", 0)
    isz = data.shape[1] * 4
    if stride and stride != isz:
        for k in range(len(data)):
            g.bin[off + k * stride:off + k * stride + isz] = data[k].tobytes()
    else:
        g.bin[off:off + data.nbytes] = data.tobytes()
    if "min" in a:
        a["min"] = [float(v) for v in data.min(0)]
        a["max"] = [float(v) for v in data.max(0)]


def belly_section(P, T, x):
    """Lowest skin point at each |z| of the cross-section x = const: (z samples 0..ZW+, y)"""
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    pts = []
    for p, q in ((a, b), (b, c), (c, a)):
        s, t = p[:, 0] - x, q[:, 0] - x
        cr = (s * t) < 0
        k = s[cr] / (s[cr] - t[cr])
        pts.append(p[cr] + (q[cr] - p[cr]) * k[:, None])
    pts = np.vstack(pts)
    pts = pts[pts[:, 1] < -0.03]
    zs = np.linspace(0.0, ZW + 0.004, 40)
    ys = np.full(len(zs), np.nan)
    for i, z in enumerate(zs):
        near = pts[np.abs(np.abs(pts[:, 2]) - z) < 0.0015, 1]
        if len(near):
            ys[i] = near.min()
    ok = ~np.isnan(ys)
    return zs, np.interp(zs, zs[ok], ys[ok])


def _islands(T, n):
    """Connected component of every vertex over the triangles (= UV island: seams are split vertices)"""
    par = np.arange(n)

    def root(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for a, b, c in T:
        ra, rb, rc = root(a), root(b), root(c)
        par[rb] = ra
        par[rc] = ra
    return np.array([root(i) for i in range(n)])


def main() -> int:
    src, dst = sys.argv[1], sys.argv[2]
    g = glb_io.load(src)
    prim = g.j["meshes"][0]["primitives"][0]
    at = prim["attributes"]
    M = g.world_of_mesh(0)
    Minv = np.linalg.inv(M)
    P, T = g.mesh_world(0, 0)
    N = g.accessor(at["NORMAL"]).astype(np.float64) @ np.linalg.inv(M[:3, :3])   # normals: inverse transpose
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    UV = g.accessor(at["TEXCOORD_0"]).astype(np.float64)
    za, ya = belly_section(P, T, XA)
    zb, yb = belly_section(P, T, XB)

    def belly(x, z):
        t = np.clip((x - XA) / (XB - XA), 0.0, 1.0)
        az = np.abs(z)
        return (1 - t) * np.interp(az, za, ya) + t * np.interp(az, zb, yb)

    inb = (P[:, 0] > XA) & (P[:, 0] < XB) & (np.abs(P[:, 2]) < ZW) & (P[:, 1] < Y_TOP)
    yb_at = belly(P[:, 0], P[:, 2])
    hull = inb & (np.abs(P[:, 2]) >= ZJ) & (P[:, 1] >= yb_at - HULL_TOL)
    inside = inb & (np.abs(P[:, 2]) < ZJ)
    door = inb & ~hull & ~inside
    moved = inside | door
    print("%s: %d in the bay box: %d inside the hinge lines, %d door, %d belly kept"
          % (os.path.basename(src), int(inb.sum()), int(inside.sum()), int(door.sum()), int(hull.sum())))
    Q = P.copy()
    Q[door, 2] = np.sign(P[door, 2]) * ZJ
    Q[moved, 1] = belly(Q[moved, 0], Q[moved, 2])
    # surface normal of y = belly(x, z), facing down
    e = 1e-4
    dx = (belly(Q[moved, 0] + e, Q[moved, 2]) - belly(Q[moved, 0] - e, Q[moved, 2])) / (2 * e)
    dz = (belly(Q[moved, 0], Q[moved, 2] + e) - belly(Q[moved, 0], Q[moved, 2] - e)) / (2 * e)
    n = np.stack([dx, -np.ones_like(dx), dz], 1)
    N[moved] = n / np.linalg.norm(n, axis=1, keepdims=True)
    # UVs of the belly skin just ahead of the bay, per side, from one UV island: the battle LOD splits the belly
    # into several islands (seams are duplicated vertices), and a fit across them would smear the atlas
    island = _islands(T, len(P))
    for sd in (-1.0, 1.0):
        fit = ((P[:, 0] > FIT_X[0]) & (P[:, 0] < FIT_X[1]) & (P[:, 2] * sd > -0.004) & (np.abs(P[:, 2]) < ZW)
               & (N[:, 1] < -0.5) & (P[:, 1] < Y_TOP) & ~moved)
        ids, cnt = np.unique(island[fit], return_counts=True)
        fit &= island == ids[np.argmax(cnt)]
        A = np.c_[P[fit, 0], P[fit, 2], np.ones(int(fit.sum()))]
        coef, *_ = np.linalg.lstsq(A, UV[fit], rcond=None)
        res = np.abs(A @ coef - UV[fit]).max(0)
        tgt = moved & (Q[:, 2] * sd >= 0.0)
        UV[tgt] = np.c_[Q[tgt, 0], Q[tgt, 2], np.ones(int(tgt.sum()))] @ coef
        print("  side %+d: UV fit on %d belly vertices, max residual %s, %d vertices remapped"
              % (sd, int(fit.sum()), res.round(4), int(tgt.sum())))
    local = Q @ Minv[:3, :3].T + Minv[:3, 3]
    write_accessor(g, at["POSITION"], local)
    write_accessor(g, at["NORMAL"], (N @ M[:3, :3]) / np.linalg.norm(N @ M[:3, :3], axis=1, keepdims=True))
    write_accessor(g, at["TEXCOORD_0"], UV)
    g.save(dst)
    print("saved", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
