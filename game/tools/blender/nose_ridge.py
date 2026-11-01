"""Straight slat noses on a hangar plane (Kanta s14: «Кит 2» shows saw teeth along the slat edge in the hangar).

The remesh triangulated a slat's sharp nose with vertices on either side of it, never on it: the faces between an
upper and a lower vertex cut the corner, so the ridge runs in a zigzag of 1–2 mm notches, and the paint baked on
those faces carries the zigzag too (upper camouflage in triangular wedges on the light underside). plane_polish.py
(step `nose`) first moves every point of the nose onto a clean section; this tool then
1. Ridge. Splits every nose face that crosses the ridge surface (through the fitted tip line, towards the section
   centre of NOSE) and puts the new vertices exactly on the straight tip line, so the nose is one straight edge row
   with only upper faces above it and only lower faces below. New vertices take the edge's interpolated UV, so the
   texture mapping of the old faces is kept; shading normals of the nose are recomputed (welded, faces within
   60 degrees of each vertex's own side).
2. Paint (optional, --maps). Every texel of a nose face within BAND of the ridge takes the colour of its own side
   BAND behind the ridge at the same span station (sampled through the mesh's UV there), fading back to the
   source over the last 1.5 mm: upper paint on the faces that face up, lower paint on those that face down (a fold
   of the upper skin seen from below takes the underside colour), one straight border on the edge.
   Panel lines that cross the slat along the chord carry on; anything drawn along the nose itself is lost
   (there is none on «Кит» 2). The same is done to the ORM map, so roughness follows the paint.

Only the moving slat parts listed in plane_polish.NOSE are touched (nodes wing_mech/slat_*); images inside the GLB
stay byte for byte (Godot uses the extracted maps next to it, which --maps rewrites in place).
  python3 -I nose_ridge.py <hangar.glb> <key> <out.glb> [--maps <col.jpg> <orm.jpg>] [--report]
Axes: glTF model space of the hangar model (nose +X, up +Y, right wing +Z), length 1."""

import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io
from plane_polish import (
    NOSE,
    node_world,
    robust_line,
    slice_extremes,
    smoothstep,
)

Image.MAX_IMAGE_PIXELS = None

BAND = 0.006  # depth behind the ridge whose paint is redrawn from its own side
FADE = 0.0015  # last part of the band blended back to the source
REACH = 0.004  # faces with a corner this close behind the tip are the nose (split along the ridge)
SNAP = 0.002  # an edge crossing farther than this behind the tip is not the ridge: split there, not moved
ON_PLANE = 5e-5  # a vertex this close to the ridge surface counts as on it
TIP_BIN = 0.004  # span bins of the tip envelope


class Part:
    """One slat node: world positions, normals, UVs and faces of its single primitive, with its accessors"""

    def __init__(self, g, ni):
        """Read node ni's mesh (one primitive, accessors used by it alone) into world space"""
        j = g.j
        self.g, self.ni = g, ni
        self.name = j["nodes"][ni]["name"]
        self.M = node_world(j, ni)
        self.prim = j["meshes"][j["nodes"][ni]["mesh"]]["primitives"]
        assert len(self.prim) == 1, self.name
        self.prim = self.prim[0]
        at = self.prim["attributes"]
        self.P = (
            g.accessor(at["POSITION"]).astype(np.float64) @ self.M[:3, :3].T
            + self.M[:3, 3]
        )
        n = g.accessor(at["NORMAL"]).astype(np.float64) @ self.M[:3, :3].T
        self.N = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        self.UV = g.accessor(at["TEXCOORD_0"]).astype(np.float64)
        self.T = g.accessor(self.prim["indices"]).reshape(-1, 3).astype(np.int64)
        self.side = 1.0 if self.P[:, 2].mean() > 0 else -1.0

    def write(self):
        """Store the new vertices and faces in fresh buffer views (back in the node's local frame)"""
        g = self.g
        Minv = np.linalg.inv(self.M)
        loc = (self.P @ Minv[:3, :3].T + Minv[:3, 3]).astype(np.float32)
        nl = self.N @ self.M[:3, :3]
        nl = (nl / np.maximum(np.linalg.norm(nl, axis=1, keepdims=True), 1e-12)).astype(
            np.float32
        )
        at = self.prim["attributes"]
        for key, arr in (
            ("POSITION", loc),
            ("NORMAL", nl),
            ("TEXCOORD_0", self.UV.astype(np.float32)),
        ):
            _set_attr(g, at[key], arr, key == "POSITION")
        g.set_indices(self.g.j["nodes"][self.ni]["mesh"], 0, self.T)


def _set_attr(g, ai, arr, minmax):
    """Point accessor ai at a new buffer view holding arr (float32, tightly packed); the old view is dropped by
    compact() once nothing refers to it"""
    a = g.j["accessors"][ai]
    while len(g.bin) % 4:
        g.bin.append(0)
    off = len(g.bin)
    g.bin += arr.tobytes()
    g.j["bufferViews"].append(
        {"buffer": 0, "byteOffset": off, "byteLength": int(arr.nbytes), "target": 34962}
    )
    a["bufferView"] = len(g.j["bufferViews"]) - 1
    a.pop("byteOffset", None)
    a["count"] = len(arr)
    if minmax:
        a["min"] = [float(v) for v in arr.min(0)]
        a["max"] = [float(v) for v in arr.max(0)]


def fit_lines(part, spec):
    """Tip line (x and y of the most forward skin per span bin, robust straight fits) and the section centre
    height at the NOSE centre depth, as functions of the span s = |z|"""
    _, s0, s1, x0, x1, _, _, dc = spec
    s = part.P[:, 2] * part.side
    tri = part.P[part.T]
    ts, tx = tri[:, :, 2] * part.side, tri[:, :, 0]
    sq = np.arange(s0, s1, 0.0005)
    le_raw, _ = slice_extremes(ts, tx, sq, x0, x1)
    ok = ~np.isnan(le_raw)
    le_fit = robust_line(sq[ok], le_raw[ok])
    d = le_fit(s) - part.P[:, 0]
    bins = np.floor((s - s0) / TIP_BIN).astype(int)
    ts_, tx_, ty_ = [], [], []
    for b in np.unique(bins):
        m = np.nonzero(bins == b)[0]
        k = m[np.argmin(d[m])]
        if d[k] < 0.002:
            ts_.append(s[k])
            tx_.append(part.P[k, 0])
            ty_.append(part.P[k, 1])
    ts_, tx_, ty_ = map(np.array, (ts_, tx_, ty_))
    tip_x = robust_line(ts_, tx_)
    tip_y = robust_line(ts_, ty_)
    # centre height: midway between the skins where a face edge crosses the centre depth
    cs, cy = [], []
    T = part.T
    for i0, i1 in ((0, 1), (1, 2), (2, 0)):
        a, b = T[:, i0], T[:, i1]
        cr = (d[a] - dc) * (d[b] - dc) < 0
        u = (dc - d[a[cr]]) / (d[b[cr]] - d[a[cr]])
        cs.append(s[a[cr]] + u * (s[b[cr]] - s[a[cr]]))
        cy.append(part.P[a[cr], 1] + u * (part.P[b[cr], 1] - part.P[a[cr], 1]))
    cs, cy = np.concatenate(cs), np.concatenate(cy)
    mids_s, mids_y = [], []
    for b in np.unique(np.floor((cs - s0) / TIP_BIN).astype(int)):
        m = np.floor((cs - s0) / TIP_BIN).astype(int) == b
        if m.sum() >= 2:
            mids_s.append(cs[m].mean())
            mids_y.append(0.5 * (cy[m].max() + cy[m].min()))
    cen_y = robust_line(np.array(mids_s), np.array(mids_y))
    return tip_x, tip_y, cen_y


def ridge_f(part, P, tip_x, tip_y, cen_y, dc):
    """Signed height of points above the ridge surface: the plane strip through the tip line that runs back to the
    section centre (positive = upper side), and their depth behind the tip"""
    s = P[:, 2] * part.side
    d = tip_x(s) - P[:, 0]
    slope = (cen_y(s) - tip_y(s)) / dc
    return P[:, 1] - (tip_y(s) + slope * d), d


def split_ridge(part, spec, rep):
    """Split the nose faces along the ridge surface and put the new vertices on the tip line (see the module doc)"""
    dc = spec[7]
    tip_x, tip_y, cen_y = fit_lines(part, spec)
    f, d = ridge_f(part, part.P, tip_x, tip_y, cen_y, dc)
    sgn = np.where(np.abs(f) < ON_PLANE, 0, np.sign(f)).astype(int)
    T = part.T
    nose = (
        d[T].min(1) < REACH
    )  # every face that touches the nose, however far back it runs
    newv = {}  # (i, j) sorted -> new vertex index
    P, N, UV = [part.P], [part.N], [part.UV]
    nv = len(part.P)
    far = 0

    def cut(i, j):
        """Vertex where edge i–j crosses the ridge surface (shared by both faces of the edge)"""
        nonlocal nv, far
        key = (min(i, j), max(i, j))
        if key in newv:
            return newv[key]
        a, b = key
        u = f[a] / (f[a] - f[b])
        p = part.P[a] + u * (part.P[b] - part.P[a])
        dd = d[a] + u * (d[b] - d[a])
        if dd < SNAP:
            sp = p[2] * part.side
            p = np.array([tip_x(np.array([sp]))[0], tip_y(np.array([sp]))[0], p[2]])
        else:
            far += 1
        n = part.N[a] + u * (part.N[b] - part.N[a])
        P.append(p[None])
        N.append((n / max(np.linalg.norm(n), 1e-12))[None])
        UV.append((part.UV[a] + u * (part.UV[b] - part.UV[a]))[None])
        newv[key] = nv
        nv += 1
        return newv[key]

    out = [T[~nose]]
    keep = []
    n0 = 0
    for t in T[nose]:
        s3 = sgn[t]
        if (s3 >= 0).all() or (s3 <= 0).all():
            keep.append(t)
            n0 += 1
            continue
        # rotate so the cyclic order is kept and the odd one (or the vertex on the surface) comes first
        for r in range(3):
            a, b, c = t[r], t[(r + 1) % 3], t[(r + 2) % 3]
            sa, sb, sc = sgn[a], sgn[b], sgn[c]
            if sa == 0 and sb * sc < 0:
                p = cut(b, c)
                keep += [[a, b, p], [a, p, c]]
                break
            if sa != 0 and sb != 0 and sc != 0 and sb == sc and sa != sb:
                pab, pca = cut(a, b), cut(c, a)
                keep += [[a, pab, pca], [pab, b, c], [pab, c, pca]]
                break
            if sa != 0 and sa * sb < 0 and sc == 0:
                p = cut(a, b)
                keep += [[a, p, c], [p, b, c]]
                break
        else:
            keep.append(t)
            n0 += 1
    ncut = int(nose.sum()) - n0
    out.append(np.array(keep, np.int64).reshape(-1, 3))
    # vertices that already sit on the ridge surface at the tip go onto the tip line too
    on = (sgn == 0) & (d < SNAP)
    Pn = np.vstack(P)
    sp = Pn[: len(part.P)][on, 2] * part.side
    Pn[np.nonzero(on)[0], 0] = tip_x(sp)
    Pn[np.nonzero(on)[0], 1] = tip_y(sp)
    nt0 = len(T)
    part.P, part.N, part.UV, part.T = Pn, np.vstack(N), np.vstack(UV), np.vstack(out)
    part.fits = (tip_x, tip_y, cen_y, dc)
    rep.append(
        f"{part.name}: {ncut} nose faces cut, {len(newv)} ridge vertices added ({far} off the tip, left in "
        f"place), {int(on.sum())} on it already; faces {nt0} -> {len(part.T)}"
    )
    renormal(part, d_max=dc)


def renormal(part, d_max):
    """Shading normals of the nose (depth < d_max): area-weighted over the faces round each welded position whose
    normal lies within 60 degrees of the vertex's own faces, so the slat's end caps and back face stay hard"""
    tip_x = part.fits[0]
    d = tip_x(part.P[:, 2] * part.side) - part.P[:, 0]
    T = part.T
    fn = np.cross(part.P[T[:, 1]] - part.P[T[:, 0]], part.P[T[:, 2]] - part.P[T[:, 0]])
    # faces agree with the old normals (the remesh winds a few against the rest)
    sg = np.sign(np.einsum("ij,ij->i", fn, part.N[T].sum(1)))
    fn *= np.where(sg == 0, 1, sg)[:, None]
    own = np.zeros_like(part.P)
    for k in range(3):
        np.add.at(own, T[:, k], fn)
    own /= np.maximum(np.linalg.norm(own, axis=1, keepdims=True), 1e-20)
    _, inv = np.unique(
        np.round(part.P / 1e-6).astype(np.int64), axis=0, return_inverse=True
    )
    inv = inv.reshape(-1)
    faces_at = [[] for _ in range(inv.max() + 1)]
    for k in range(3):
        for fi, v in enumerate(inv[T[:, k]]):
            faces_at[v].append(fi)
    fu = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-20)
    for vi in np.nonzero(d < d_max)[0]:
        fs = np.array(faces_at[inv[vi]])
        ok = fu[fs] @ own[vi] > 0.5
        if ok.any():
            s = fn[fs[ok]].sum(0)
            part.N[vi] = s / max(np.linalg.norm(s), 1e-20)


def repaint(parts, paths, rep):
    """Redraw the paint of the nose band from each side's own paint BAND behind the ridge (module doc, step 2)"""
    for path in paths:
        im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
        H, W = im.shape[:2]
        src = im.copy()
        changed = 0
        for part in parts:
            tip_x, tip_y, cen_y, dc = part.fits
            _, d = ridge_f(part, part.P, tip_x, tip_y, cen_y, dc)
            s = part.P[:, 2] * part.side
            T = part.T
            fn = np.cross(
                part.P[T[:, 1]] - part.P[T[:, 0]], part.P[T[:, 2]] - part.P[T[:, 0]]
            )
            fn *= np.where(np.einsum("ij,ij->i", fn, part.N[T].sum(1)) < 0, -1.0, 1.0)[
                :, None
            ]
            cap = np.abs(fn[:, 2]) > 0.7 * np.linalg.norm(
                fn, axis=1
            )  # end ribs of the slat keep their paint
            # the side a face shows is where it faces, not where it sits: a fold of the upper skin that faces down
            # (seen from below) takes the lower paint. Up = the gradient of the ridge surface's height function.
            sp = s[T].mean(1)
            grad = np.stack([(cen_y(sp) - tip_y(sp)) / dc, np.ones_like(sp)], 1)
            side = np.sign(fn[:, 0] * grad[:, 0] + fn[:, 1] * grad[:, 1])
            band = (d[T].min(1) < BAND) & ~cap & (side != 0)
            for sd in (-1, 1):
                ref = _slice_uv(s, d, part.UV, T[side == sd], BAND)
                for t in T[band & (side == sd)]:
                    changed += _paint_face(im, src, part.UV[t], s[t], d[t], ref, W, H)
        Image.fromarray(np.clip(im + 0.5, 0, 255).astype(np.uint8)).save(
            path, quality=95, subsampling=0
        )
        rep.append(f"{os.path.basename(path)}: {changed} texels redrawn")


def _slice_uv(s, d, UV, T, dq):
    """The faces of one side cut at depth dq: sorted span segments with the UV at both ends, for lookup"""
    seg = []
    for i0, i1 in ((0, 1), (1, 2), (2, 0)):
        a, b = T[:, i0], T[:, i1]
        cr = (d[a] - dq) * (d[b] - dq) < 0
        u = (dq - d[a[cr]]) / (d[b[cr]] - d[a[cr]])
        seg.append(
            (
                np.nonzero(cr)[0],
                s[a[cr]] + u * (s[b[cr]] - s[a[cr]]),
                UV[a[cr]] + u[:, None] * (UV[b[cr]] - UV[a[cr]]),
            )
        )
    fi = np.concatenate([x[0] for x in seg])
    ss = np.concatenate([x[1] for x in seg])
    uu = np.concatenate([x[2] for x in seg])
    o = np.argsort(fi, kind="stable")
    fi, ss, uu = fi[o], ss[o], uu[o]
    pairs = []
    for k in range(len(fi) - 1):
        if fi[k] == fi[k + 1]:
            a, b = (k, k + 1) if ss[k] <= ss[k + 1] else (k + 1, k)
            pairs.append((ss[a], ss[b], uu[a], uu[b]))
    pairs.sort(key=lambda p: p[0])
    return (
        np.array([p[0] for p in pairs]),
        np.array([p[1] for p in pairs]),
        np.array([p[2] for p in pairs]),
        np.array([p[3] for p in pairs]),
    )


def _ref_uv(ref, sq):
    """UV of the reference slice at the span stations sq (nearest segment when a station falls in a gap)"""
    a, b, ua, ub = ref
    k = np.clip(np.searchsorted(a, sq, side="right") - 1, 0, len(a) - 1)
    t = np.clip((sq - a[k]) / np.maximum(b[k] - a[k], 1e-12), 0, 1)
    return ua[k] + t[:, None] * (ub[k] - ua[k])


def _sample(img, uv, W, H):
    """Bilinear colour of img at the UVs (texel centres at (i + 0.5) / W)"""
    x = np.clip(uv[:, 0] * W - 0.5, 0, W - 1.001)
    y = np.clip(uv[:, 1] * H - 0.5, 0, H - 1.001)
    i, j = x.astype(int), y.astype(int)
    a, b = (x - i)[:, None], (y - j)[:, None]
    return (
        img[j, i] * (1 - a) * (1 - b)
        + img[j, i + 1] * a * (1 - b)
        + img[j + 1, i] * (1 - a) * b
        + img[j + 1, i + 1] * a * b
    )


def _paint_face(im, src, uv, s, d, ref, W, H):
    """Rasterise one face in texel space (half a texel of slack, so the island border is covered) and blend the
    reference paint in by the depth of each texel behind the ridge; returns the number of texels written"""
    px = uv * [W, H]
    lo = np.floor(px.min(0) - 1).astype(int)
    hi = np.ceil(px.max(0) + 1).astype(int)
    lo = np.maximum(lo, 0)
    hi = np.minimum(hi, [W - 1, H - 1])
    if (hi <= lo).any():
        return 0
    gx, gy = np.meshgrid(
        np.arange(lo[0], hi[0] + 1) + 0.5, np.arange(lo[1], hi[1] + 1) + 0.5
    )
    q = np.stack([gx.ravel(), gy.ravel()], 1)
    v0, v1 = px[1] - px[0], px[2] - px[0]
    den = v0[0] * v1[1] - v0[1] * v1[0]
    if abs(den) < 1e-9:
        return 0
    r = q - px[0]
    b1 = (r[:, 0] * v1[1] - r[:, 1] * v1[0]) / den
    b2 = (v0[0] * r[:, 1] - v0[1] * r[:, 0]) / den
    b0 = 1 - b1 - b2
    tol = 0.5 / max(np.sqrt(abs(den)), 1e-6)
    m = (b0 > -tol) & (b1 > -tol) & (b2 > -tol)
    if not m.any():
        return 0
    bb = np.stack([b0[m], b1[m], b2[m]], 1).clip(0, 1)
    bb /= bb.sum(1, keepdims=True)
    sq, dq = bb @ s, bb @ d
    w = 1 - smoothstep(BAND - FADE, BAND, dq)
    if not (w > 0).any():
        return 0
    col = _sample(src, _ref_uv(ref, sq), W, H)
    ii = q[m].astype(int)
    old = src[ii[:, 1], ii[:, 0]]
    im[ii[:, 1], ii[:, 0]] = old * (1 - w[:, None]) + col * w[:, None]
    return int((w > 0).sum())


def main():
    """Command line: straighten the slat noses of one hangar GLB and, with --maps, redraw their paint"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    ap.add_argument(
        "--maps",
        nargs="*",
        default=[],
        help="extracted colour / ORM maps, rewritten in place",
    )
    a = ap.parse_args()
    g = glb_io.load(a.src)
    rep, parts = [], []
    for spec in NOSE.get(a.key, []):
        for ni, n in enumerate(g.j["nodes"]):
            if n.get("name", "").startswith(spec[0] + "_") and "mesh" in n:
                p = Part(g, ni)
                split_ridge(p, spec, rep)
                parts.append(p)
    for p in parts:
        p.write()
    g.save(a.dst)
    if a.maps:
        repaint(parts, a.maps, rep)
    print("\n".join(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
