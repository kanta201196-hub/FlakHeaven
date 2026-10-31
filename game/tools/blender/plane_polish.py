"""Hangar plane polish (Kanta s14: «опять вижу проблемы с крыльями в ангаре»): straight, clean wing and tail edges
and an even skin on the lifting surfaces of the remeshed player planes, without touching topology, UVs or textures.

The generator remesh left the thin parts ragged: the leading and trailing edges of the wings, tailplanes and fins
run in saw teeth and notches of 2–25 mm (model length 1000 mm), folded slivers stick out of them, and the thin
skin is lumpy. The mechanisation cut (mech_cut.py) kept those edges, so the slats and flaps carried them too.

What it does, per lifting surface (config SURF: a box in model axes that holds only that surface, optionally a wider edge gate):
1. Outline. The raw leading and trailing edge along the span (extremes of the skin in a narrow running window)
   and a robust straight or two-segment fit of each (real wings have straight edges). Every point near an edge is
   moved along the chord by how far the raw edge at its span station is from the fitted line, fading to nothing
   a quarter chord inside; so teeth are cut back and notches filled out to the line.
2. Skin. The upper and lower surface as smooth grids over (span, chord) — medians, smoothed along the span — and
   every point of the surface pulled towards its side's grid: hard near the edges (the ragged lips and slivers),
   gently in the middle (lumps); points far off the grid (pylons, fairings, actuator pods) are left alone.
The deformation is one function of the position, so the skin, the cut-out slats and flaps (node frames applied),
their caps and the dark wells move together and stay crack-free; normals of moved vertices are recomputed.

Input and output are the same kind of GLB (glb_io: images and every node stay byte for byte), e.g.
  python3 -I plane_polish.py ../../models/hangar/fh_hangar_attacker_1.glb attacker_1 /tmp/out.glb [--report]
Axes: glTF model space of the hangar model (nose +X, up +Y, right wing +Z), length 1."""
import argparse
import os
import sys

import numpy as np
from scipy.ndimage import gaussian_filter
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

# Lifting surfaces per plane: name, span axis ("z": wings and tailplanes, both sides; "y": fins), span range s0..s1
# (|z| or y), chord-axis range x0..x1 and thickness-axis range t0..t1 (y for wings, z for fins) that hold only this
# surface at those stations, edge fit segments (1 straight, 2 with a kink), and which edges to straighten
# ("le", "te"). Ranges were read off spanwise cross-sections of each hangar model (stations of the skin).
SURF = {
    "attacker_1": [
        ("wing", "z", 0.135, 0.445, -0.30, 0.05, -0.095, -0.040, 1, ("le", "te")),
        ("htail", "z", 0.11, 0.205, -0.47, -0.27, -0.075, -0.045, 1, ("le", "te")),
        ("fin", "y", 0.025, 0.095, -0.51, -0.24, -0.012, 0.012, 1, ("le", "te")),
    ],
    "attacker_2": [
        ("wing", "z", 0.16, 0.455, -0.32, 0.03, -0.095, -0.040, 1, ("le", "te")),
        ("htail", "z", 0.135, 0.21, -0.49, -0.25, -0.085, -0.045, 1, ("le", "te")),
        ("fin", "y", 0.035, 0.115, -0.51, -0.25, -0.012, 0.012, 1, ("le", "te")),
    ],
    # «Оса» 1 (Sketchfab, clean low-poly hand model) and «Оса» 2 (Meshy at 100k, flat facets) have straight,
    # clean edges already; the grid pull bent their sparse flat panels, so they are left as they are
    "fighter_1": [],
    "fighter_2": [],
    "bomber_1": [
        ("wing_mid", "z", 0.20, 0.27, -0.12, 0.10, -0.080, -0.045, 1, ("le", "te")),
        ("wing_out", "z", 0.335, 0.49, -0.24, 0.02, -0.100, -0.060, 1, ("le", "te")),
        ("htail", "z", 0.04, 0.19, -0.48, -0.24, -0.050, -0.018, 1, ("le", "te")),
        ("fin", "y", 0.0, 0.125, -0.48, -0.24, -0.010, 0.010, 1, ("le", "te")),
    ],
    "bomber_2": [
        ("wing", "z", 0.19, 0.525, -0.34, 0.02, -0.042, -0.018, 1, ("le", "te"), 0.009, 0.9),
        ("htail", "z", 0.125, 0.20, -0.50, -0.30, -0.035, -0.012, 1, ("le", "te")),
        ("fin", "y", 0.02, 0.125, -0.45, -0.27, -0.008, 0.008, 1, ("le", "te")),
    ],
}
# Broad top skins evened by smooth_top (S14-02 autotest: bumps on the fuselage top and the wing root of bomber_2):
# name, x0, x1, z0, z1 (|z| when mirrored), mirrored, smoothing sigma along x and across z (model units).
TOPS = {
    "bomber_2": [
        ("spine", -0.30, 0.24, -0.06, 0.06, False, 0.010, 0.004),
        ("glove", -0.32, 0.12, 0.05, 0.215, True, 0.008, 0.006),
    ],
}
# Planes whose moved skin takes the smooth welded normal outright (their own normals are jagged along the edges,
# S14-02 «Кит-2» leading edge); the rest keep their normals plus the change of shape.
RENORMAL = ("bomber_2",)

WIN = 0.0016     # running window of the raw edge along the span
BROAD_R = 0.003   # radius of the broad-deviation median (spike vs pylon)
TOP_CELL = 0.003  # height-field cell of smooth_top
TOP_DIP = 0.003   # deepest dimple smooth_top fills; anything lower is another surface
GATE = 0.005     # 5 mm: farther off the fitted edge is shape, not noise
EDGE_BAND = 0.25  # chord share over which the edge correction fades out
GRID_S = 0.004
GRID_C = 0.025


def _quat_mat(q):
    return glb_io._quat_mat(q)


def node_world(j, ni):
    """World matrix of node ni (parents applied)"""
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


class Model:
    """Every POSITION accessor of the GLB with its world matrix; triangles per accessor for normals"""

    def __init__(self, path):
        self.g = glb_io.load(path)
        j = self.g.j
        self.acc = {}    # position accessor -> dict(M, P(world), N acc, tris list, kind)
        self.prims = []  # (index accessor, position accessor, material name, slot in that accessor's tris)
        self.rewound = set()
        self.renormal = bool(os.environ.get("POLISH_RENORMAL")) or any(k in path for k in RENORMAL)
        for ni, n in enumerate(j["nodes"]):
            if "mesh" not in n:
                continue
            M = node_world(j, ni)
            for pr in j["meshes"][n["mesh"]]["primitives"]:
                a = pr["attributes"]["POSITION"]
                mat = j["materials"][pr["material"]].get("name", "") if "material" in pr else ""
                e = self.acc.setdefault(a, {"M": M, "tris": [], "nrm": pr["attributes"].get("NORMAL"), "kinds": set()})
                e["tris"].append(self.g.accessor(pr["indices"]).reshape(-1, 3).astype(np.int64))
                e["kinds"].add(mat)
                self.prims.append((pr["indices"], a, mat, len(e["tris"]) - 1))
        for a, e in self.acc.items():
            p = self.g.accessor(a).astype(np.float64)
            e["P0"] = p @ e["M"][:3, :3].T + e["M"][:3, 3]
            e["P"] = e["P0"].copy()
            if e["nrm"] is not None:
                n = self.g.accessor(e["nrm"]).astype(np.float64) @ e["M"][:3, :3].T
                e["N"] = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
            used = np.zeros(len(p), bool)
            for t in e["tris"]:
                used[t.reshape(-1)] = True
            e["used"] = used

    def pool(self, pick):
        """World positions of every vertex (all accessors, wells too) that pick(P) selects, as one array, so that a
        deformation computed on it is one function of position (a cut edge's skin and part vertices move alike);
        unpool() writes the moved array back. None when nothing is selected."""
        self._pool = []
        out = []
        for a, e in self.acc.items():
            sel = pick(e["P"])
            if sel.any():
                self._pool.append((a, sel))
                out.append(e["P"][sel])
        return np.vstack(out) if out else None

    def unpool(self, P):
        """Write the positions of the last pool() back to their accessors"""
        off = 0
        for a, sel in self._pool:
            n = int(sel.sum())
            self.acc[a]["P"][sel] = P[off:off + n]
            off += n

    def analysis_points(self):
        """World positions and normals of the painted skin and glass (not the dark wells)"""
        P, N = [], []
        for a, e in self.acc.items():
            if e["kinds"] == {"mech_well"} or "N" not in e:
                continue
            P.append(e["P"][e["used"]])
            N.append(e["N"][e["used"]])
        return np.vstack(P), np.vstack(N)

    def analysis_tris(self):
        """World triangles (n, 3, 3) of the painted skin and glass (not the dark wells)"""
        out = []
        for a, e in self.acc.items():
            if e["kinds"] == {"mech_well"}:
                continue
            out.append(e["P"][np.vstack(e["tris"])])
        return np.concatenate(out)

    def fix_winding(self, report):
        """Turn every skin and glass triangle whose winding disagrees with its own vertex normals. The livery
        shader culls back faces, so such a triangle is a hole where the sky shows through (or a dark pit where the
        inside shows): the remesh left a few hundred of them on some planes. The normals are what the surface is
        shaded with and agree with their neighbours, so the winding is the one turned. The dark single-sided wells
        are left as they are (their winding is deliberate)."""
        total = 0
        for ia, a, mat, k in self.prims:
            e = self.acc[a]
            if mat == "mech_well" or "N" not in e:
                continue
            T = e["tris"][k]
            P, N = e["P"], e["N"]
            fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
            area2 = np.linalg.norm(fn, axis=1)
            nsum = N[T].sum(1)
            agree = np.einsum("ij,ij->i", fn, nsum) / np.maximum(area2 * np.linalg.norm(nsum, axis=1), 1e-20)
            bad = (agree < -0.2) & (area2 > 1e-12)
            if bad.any():
                T[bad] = T[bad][:, [0, 2, 1]]
                self.rewound.add(ia)
                total += int(bad.sum())
        report.append("winding: %d triangles turned to face along their normals" % total)

    def write(self, path):
        g = self.g
        for ia, a, mat, k in self.prims:
            if ia in self.rewound:
                acc = g.j["accessors"][ia]
                dt = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32}[acc["componentType"]]
                _put(g, ia, self.acc[a]["tris"][k].reshape(-1, 1).astype(dt))
        dn = self._normal_deltas()
        for a, e in self.acc.items():
            Minv = np.linalg.inv(e["M"])
            loc = (e["P"] @ Minv[:3, :3].T + Minv[:3, 3]).astype(np.float32)
            _put(g, a, loc)
            acc = g.j["accessors"][a]
            acc["min"] = [float(v) for v in loc.min(0)]
            acc["max"] = [float(v) for v in loc.max(0)]
            if e["nrm"] is not None and a in dn:
                nn = e["N"] + dn[a]
                nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-12)
                nl = nn @ e["M"][:3, :3]    # back to local (rotation only; parts have no scale)
                nl /= np.maximum(np.linalg.norm(nl, axis=1, keepdims=True), 1e-12)
                _put(g, e["nrm"], nl.astype(np.float32))
        g.save(path)

    def _normal_deltas(self):
        """Change of the smooth surface normal at every moved vertex: (after - before) of the area-weighted face
        normals round its welded position, over the skin and the parts together (a cut edge sees both sides) and
        with every face turned to agree with the vertex normals it has. Added to the old normal, so the remesh's
        own shading (seams, deliberately hard spots) is kept where nothing moved."""
        keys = [a for a, e in self.acc.items() if e["nrm"] is not None and e["kinds"] != {"mech_well"}
                and "glass" not in e["kinds"]]
        P0 = np.vstack([self.acc[a]["P0"] for a in keys])
        P1 = np.vstack([self.acc[a]["P"] for a in keys])
        N0 = np.vstack([self.acc[a]["N"] for a in keys])
        T, off = [], 0
        for a in keys:
            T.append(np.vstack(self.acc[a]["tris"]) + off)
            off += len(self.acc[a]["P0"])
        T = np.vstack(T)
        moved = np.linalg.norm(P1 - P0, axis=1) > 1e-7
        _, inv = np.unique(np.round(P0 / 1e-6).astype(np.int64), axis=0, return_inverse=True)
        inv = inv.reshape(-1)

        def acc_n(P):
            fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
            sgn = np.sign(np.einsum("ij,ij->i", fn, N0[T].sum(1)))
            fn *= np.where(sgn == 0, 1, sgn)[:, None]
            out = np.zeros((inv.max() + 1, 3))
            for k in range(3):
                np.add.at(out, inv[T[:, k]], fn)
            n = out[inv]
            return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)
        if self.renormal:
            # the remesh's own normals are jagged here too: the moved skin takes the smooth welded normal
            d = acc_n(P1) - N0
        else:
            d = acc_n(P1) - acc_n(P0)
        d[~moved] = 0
        res, off = {}, 0
        for a in keys:
            n = len(self.acc[a]["P0"])
            res[a] = d[off:off + n]
            off += n
        return res


def _put(g, ai, arr):
    """Overwrite accessor ai's data in place (same count and type)"""
    a = g.j["accessors"][ai]
    bv = g.j["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    isz = arr.dtype.itemsize * arr.shape[1]
    if stride and stride != isz:
        for i in range(len(arr)):
            g.bin[off + i * stride:off + i * stride + isz] = arr[i].tobytes()
    else:
        g.bin[off:off + arr.nbytes] = arr.tobytes()


def _normals(P, T, N_old):
    """Smooth vertex normals, area weighted over every face at the same position (seams welded); a vertex keeps
    the side of its old normal (double-sided skin, a few faces wound against the rest)"""
    q = np.round(P / 1e-6).astype(np.int64)
    _, inv = np.unique(q, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    acc = np.zeros((inv.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, inv[T[:, k]], fn)
    n = acc[inv]
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)
    flip = np.einsum("ij,ij->i", n, N_old) < 0
    n[flip] *= -1
    return n


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def robust_line(s, x, w=None, segs=1, it=8):
    """Robust fit x(s): one straight line or two segments joined at the best knot; Tukey reweighting so teeth and
    notches do not pull it. Returns a callable."""
    def fit1(ss, xx, ww):
        A = np.stack([ss, np.ones_like(ss)], 1)
        for _ in range(it):
            W = np.sqrt(ww)
            c, *_ = np.linalg.lstsq(A * W[:, None], xx * W, rcond=None)
            r = xx - A @ c
            sc = 4.685 * max(np.median(np.abs(r)) * 1.4826, 4e-4)
            ww = np.where(np.abs(r) < sc, (1 - (r / sc) ** 2) ** 2, 0.0) + 1e-6
        return c, float(np.sum(ww * r * r)), ww
    w = np.ones_like(s) if w is None else w
    c, err, ww = fit1(s, x, w)
    if segs == 1:
        return lambda v: c[0] * v + c[1]
    best = (err, None)
    for k in np.linspace(s.min() + 0.25 * np.ptp(s), s.max() - 0.25 * np.ptp(s), 12):
        h = np.maximum(s - k, 0)
        A = np.stack([s, h, np.ones_like(s)], 1)
        ww2 = w.copy()
        for _ in range(it):
            W = np.sqrt(ww2)
            cc, *_ = np.linalg.lstsq(A * W[:, None], x * W, rcond=None)
            r = x - A @ cc
            sc = 4.685 * max(np.median(np.abs(r)) * 1.4826, 4e-4)
            ww2 = np.where(np.abs(r) < sc, (1 - (r / sc) ** 2) ** 2, 0.0) + 1e-6
        e2 = float(np.sum(ww2 * r * r))
        if e2 < best[0] * 0.7:
            best = (e2, (k, cc))
    if best[1] is None:
        return lambda v: c[0] * v + c[1]
    k, cc = best[1]
    return lambda v: cc[0] * v + cc[1] * np.maximum(v - k, 0) + cc[2]


def slice_extremes(ts, tx, sq, x0, x1):
    """Max and min chord coordinate of the triangle slices at the span stations sq (NaN where none)"""
    le = np.full(len(sq), np.nan)
    te = np.full(len(sq), np.nan)
    smin, smax = ts.min(1), ts.max(1)
    o = np.argsort(smin)
    ts, tx, smin, smax = ts[o], tx[o], smin[o], smax[o]
    for i, v in enumerate(sq):
        hi = np.searchsorted(smin, v, side="right")
        m = smax[:hi] >= v
        if not m.any():
            continue
        a, b = ts[:hi][m], tx[:hi][m]
        xs = []
        for i0, i1 in ((0, 1), (1, 2), (2, 0)):
            sa, sb = a[:, i0], a[:, i1]
            cr = (sa - v) * (sb - v) <= 0
            den = np.where(np.abs(sb - sa) < 1e-12, 1e-12, sb - sa)
            tpar = np.clip((v - sa) / den, 0, 1)
            xs.append(np.where(cr, b[:, i0] + tpar * (b[:, i1] - b[:, i0]), np.nan))
        xs = np.concatenate(xs)
        xs = xs[~np.isnan(xs) & (xs > x0) & (xs < x1)]
        if len(xs):
            le[i], te[i] = xs.max(), xs.min()
    return le, te


def running_extreme(s_pts, x_pts, s_query, win, fn):
    """fn (max/min) of x over points with |s - s_query| < win/2, for every query (NaN where empty)"""
    o = np.argsort(s_pts)
    ss, xx = s_pts[o], x_pts[o]
    lo = np.searchsorted(ss, s_query - win / 2)
    hi = np.searchsorted(ss, s_query + win / 2)
    out = np.full(len(s_query), np.nan)
    for i in range(len(s_query)):
        if hi[i] > lo[i]:
            out[i] = fn(xx[lo[i]:hi[i]])
    return out


def grid_surface(s, c, t, s0, s1):
    """Median grid of t over (s, c), smoothed along the span, NaNs filled from neighbours; returns evaluator"""
    ns = max(int((s1 - s0) / GRID_S) + 1, 2)
    nc = int(1.2 / GRID_C) + 1
    G = np.full((ns, nc), np.nan)
    si = np.clip(((s - s0) / GRID_S).round().astype(int), 0, ns - 1)
    ci = np.clip(((c + 0.1) / GRID_C).round().astype(int), 0, nc - 1)
    key = si * nc + ci
    o = np.argsort(key)
    ks, ts = key[o], t[o]
    u, st = np.unique(ks, return_index=True)
    en = np.append(st[1:], len(ks))
    for k, a, b in zip(u, st, en):
        G[k // nc, k % nc] = np.median(ts[a:b])
    # fill holes: iterative neighbour mean
    for _ in range(60):
        nanm = np.isnan(G)
        if not nanm.any():
            break
        P = np.pad(G, 1, constant_values=np.nan)
        stack = np.stack([P[:-2, 1:-1], P[2:, 1:-1], P[1:-1, :-2], P[1:-1, 2:]])
        cnt = (~np.isnan(stack)).sum(0)
        m = np.nansum(stack, 0) / np.maximum(cnt, 1)
        G = np.where(nanm & (cnt > 0), m, G)
    G = np.nan_to_num(G, nan=np.nanmean(G))
    # smoothing: gaussian along the span (sigma 2 cells), light along the chord
    k1 = np.exp(-0.5 * (np.arange(-5, 6) / 2.0) ** 2)
    k1 /= k1.sum()
    Gp = np.pad(G, ((5, 5), (0, 0)), mode="edge")
    G = np.stack([np.convolve(Gp[:, j], k1, mode="valid") for j in range(nc)], 1)
    k2 = np.array([0.25, 0.5, 0.25])
    Gp = np.pad(G, ((0, 0), (1, 1)), mode="edge")
    G = np.stack([np.convolve(Gp[i], k2, mode="valid") for i in range(ns)], 0)

    def ev(sq, cq):
        fs = np.clip((sq - s0) / GRID_S, 0, ns - 1.001)
        fc = np.clip((cq + 0.1) / GRID_C, 0, nc - 1.001)
        i0, j0 = fs.astype(int), fc.astype(int)
        a, b = fs - i0, fc - j0
        return (G[i0, j0] * (1 - a) * (1 - b) + G[i0 + 1, j0] * a * (1 - b) + G[i0, j0 + 1] * (1 - a) * b
                + G[i0 + 1, j0 + 1] * a * b)
    return ev


def _debug_plot(path, S, X, Tt, sq, le_raw, te_raw, le_fit, te_fit):
    """Planform of the surface box (points coloured by thickness coordinate), raw edges red, fits green"""
    from PIL import Image, ImageDraw
    k = 3000.0
    s_lo, x_lo = S.min(), X.min()
    W, H = int(np.ptp(S) * k) + 20, int(np.ptp(X) * k) + 20
    im = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(im)
    tn = (Tt - Tt.min()) / max(np.ptp(Tt), 1e-6)
    for a, b, c in zip(S, X, tn):
        px, py = (a - s_lo) * k + 10, H - ((b - x_lo) * k + 10)
        d.point((px, py), fill=(int(255 * c), 0, int(255 * (1 - c))))
    for arr in (le_raw, te_raw):
        d.line([((a - s_lo) * k + 10, H - ((b - x_lo) * k + 10)) for a, b in zip(sq, arr)], fill=(255, 0, 0))
    for f in (le_fit, te_fit):
        d.line([((a - s_lo) * k + 10, H - ((f(np.array([a]))[0] - x_lo) * k + 10)) for a in sq], fill=(0, 170, 0))
    im.save(path)


def polish_surface(model, spec, side, report):
    name, ax, s0, s1, x0, x1, t0, t1, segs, edges = spec[:10]
    gmax = spec[10] if len(spec) > 10 else GATE   # a long, wavy edge may need a wider gate
    a_mid = spec[11] if len(spec) > 11 else 0.55  # pull of the mid-chord skin (lumps, slat and flap seams)
    AP, AN = model.analysis_points()
    if ax == "z":
        sa, ta = 2, 1
    else:
        sa, ta = 1, 2

    def coords(P):
        s = P[:, sa] * (side if ax == "z" else 1.0)
        t = P[:, ta]
        if ax == "y":
            t = t * 1.0
        return s, P[:, 0], t
    s, x, t = coords(AP)
    if ax == "y" and side != 0:
        pass
    m = (s > s0) & (s < s1) & (x > x0) & (x < x1) & (t > t0) & (t < t1)
    if m.sum() < 50:
        report.append("%s%s: only %d points, skipped" % (name, "LR"[side > 0] if ax == "z" else "", m.sum()))
        return
    S, X, Tt, NT = s[m], x[m], t[m], AN[m][:, ta]
    # raw edges on a fine station grid, then the fit
    # the true outline: slices of the triangles at fine span stations (points alone miss the edge row between
    # stations and read as false notches)
    TR = model.analysis_tris()
    ts_, tx_, tt_ = coords(TR.reshape(-1, 3))
    ts_, tx_, tt_ = ts_.reshape(-1, 3), tx_.reshape(-1, 3), tt_.reshape(-1, 3)
    tm = ((ts_.max(1) > s0) & (ts_.min(1) < s1) & (tx_.max(1) > x0) & (tx_.min(1) < x1)
          & (tt_.min(1) > t0) & (tt_.max(1) < t1))
    sq = np.arange(s0, s1, 0.0005)
    le_raw, te_raw = slice_extremes(ts_[tm], tx_[tm], sq, x0, x1)
    ok = ~np.isnan(le_raw) & ~np.isnan(te_raw)
    sq, le_raw, te_raw = sq[ok], le_raw[ok], te_raw[ok]
    le_fit = robust_line(sq, le_raw, segs=segs)
    te_fit = robust_line(sq, te_raw, segs=segs)
    dle = le_fit(sq) - le_raw
    dte = te_fit(sq) - te_raw
    # a station farther than GATE from the fitted line is a real shape (rounded tip, kink, tail cone, a box edge),
    # not saw teeth: the correction fades out there, and an edge that is mostly off its line is left alone
    gate = lambda d: 1.0 - smoothstep(gmax * 0.6, gmax, np.abs(d))  # noqa: E731
    raw_le, raw_te = dle.copy(), dte.copy()
    dle = dle * gate(dle) * (np.mean(np.abs(dle) < gmax) > 0.6)
    dte = dte * gate(dte) * (np.mean(np.abs(dte) < gmax) > 0.6)
    tag = "%s%s" % (name, ("L" if side < 0 else "R") if ax == "z" else "")
    report.append("%s: LE raw dev p95 %.2f mm max %.2f mm | TE raw dev p95 %.2f mm max %.2f mm (1 unit = 1000 mm)"
                  % (tag, np.percentile(np.abs(raw_le), 95) * 1e3, np.abs(raw_le).max() * 1e3,
                     np.percentile(np.abs(raw_te), 95) * 1e3, np.abs(raw_te).max() * 1e3))
    report.append("%s: corrected LE max %.2f mm, TE max %.2f mm" % (tag, np.abs(dle).max() * 1e3, np.abs(dte).max() * 1e3))

    if os.environ.get("POLISH_DEBUG"):
        _debug_plot(os.environ["POLISH_DEBUG"] + "_%s.png" % tag, S, X, Tt, sq, le_raw, te_raw, le_fit, te_fit)

    def interp(v, arr):
        return np.interp(v, sq, arr)
    # skin grids (after the outline step, chord share by the fitted edges)
    chord = lambda v: np.maximum(le_fit(v) - te_fit(v), 1e-4)  # noqa: E731

    def outline_dx(sp, xp):
        cr = (xp - interp(sp, te_raw)) / np.maximum(interp(sp, le_raw) - interp(sp, te_raw), 1e-4)
        dx = np.zeros_like(xp)
        if "le" in edges:
            dx += interp(sp, dle) * smoothstep(1 - EDGE_BAND, 1.0, cr)
        if "te" in edges:
            dx += interp(sp, dte) * smoothstep(EDGE_BAND, 0.0, cr)
        return dx
    Xn = X + outline_dx(S, X)
    C = (Xn - te_fit(S)) / chord(S)
    up = NT > 0.45
    lo = NT < -0.45
    U0 = grid_surface(S[up], C[up], Tt[up], s0, s1)
    L0 = grid_surface(S[lo], C[lo], Tt[lo], s0, s1)

    # near the edges the skin grids are the ragged lips themselves: there the section is drawn from the clean
    # interior instead — camber carried on straight, thickness tapering to a thin trailing edge and closing as a
    # rounded nose (half-ellipse) at the leading edge
    def half_and_camber(sp, cq):
        ci = np.clip(cq, 0.15, 0.85)
        m = 0.5 * (U0(sp, ci) + L0(sp, ci))
        h = 0.5 * (U0(sp, ci) - L0(sp, ci))
        h_te = np.minimum(h, 0.0004)
        h = np.where(cq < 0.15, h_te + (h - h_te) * np.clip(cq / 0.15, 0, 1), h)
        h = np.where(cq > 0.85, h * np.sqrt(np.clip(1 - ((cq - 0.85) / 0.15) ** 2, 0, 1)), h)
        # camber slope from the interior, carried on to the edges
        m1 = 0.5 * (U0(sp, np.full_like(cq, 0.85)) + L0(sp, np.full_like(cq, 0.85)))
        m0 = 0.5 * (U0(sp, np.full_like(cq, 0.15)) + L0(sp, np.full_like(cq, 0.15)))
        m = np.where(cq > 0.85, m1 + (m1 - m0) / 0.7 * (cq - 0.85), np.where(cq < 0.15, m0 + (m1 - m0) / 0.7 * (cq - 0.15), m))
        return m, np.maximum(h, 0.0)

    def U(sp, cq):
        m, h = half_and_camber(sp, cq)
        edge = np.maximum(smoothstep(0.2, 0.1, cq), smoothstep(0.8, 0.9, cq))
        return U0(sp, cq) * (1 - edge) + (m + h) * edge

    def L(sp, cq):
        m, h = half_and_camber(sp, cq)
        edge = np.maximum(smoothstep(0.2, 0.1, cq), smoothstep(0.8, 0.9, cq))
        return L0(sp, cq) * (1 - edge) + (m - h) * edge
    thick_med = np.median(U(S, C) - L(S, C))
    report.append("%s: chord at root %.3f tip %.3f, median thickness %.2f mm" % (
        tag, chord(np.array([s0]))[0], chord(np.array([s1]))[0], thick_med * 1e3))
    mg = 0.012

    def in_box(P):
        sp, xp, tp = coords(P)
        return (sp > s0 - mg) & (sp < s1 + mg) & (xp > x0 - mg) & (xp < x1 + mg) & (tp > t0 - mg) & (tp < t1 + mg)
    pool = model.pool(in_box)
    if pool is None:
        return
    sp, xp, tp = coords(pool)
    # fades: span ends, out of the thickness box
    ws = smoothstep(s0, s0 + 0.015, sp) * (1 - smoothstep(s1 - 0.015, s1, sp))
    wt = smoothstep(t0 - 0.004, t0 + 0.002, tp) * (1 - smoothstep(t1 - 0.002, t1 + 0.004, tp))
    wx = smoothstep(x0 - 0.004, x0 + 0.004, xp) * (1 - smoothstep(x1 - 0.004, x1 + 0.004, xp))
    w = ws * wt * wx
    dx = outline_dx(sp, xp) * w
    xn = xp + dx
    cn = (xn - te_fit(sp)) / chord(sp)
    u, l_ = U(sp, cn), L(sp, cn)
    mid = 0.5 * (u + l_)
    tgt = np.where(tp >= mid, u, l_)
    dev = tp - tgt
    edge_w = np.maximum(smoothstep(0.12, 0.02, cn), smoothstep(0.88, 0.98, cn))
    alpha = np.maximum(a_mid, 0.95 * edge_w)
    keep = 1 - smoothstep(0.0025, 0.007, broad_dev(pool, dev))   # pylons, fairings: broad, far off the grid
    inside = smoothstep(-0.12, -0.03, cn) * (1 - smoothstep(1.03, 1.12, cn))
    if os.environ.get("POLISH_DEBUG"):
        kp = (keep < 0.5) & (inside * w > 0.5)
        report.append("%s: kept off-skin points %d, chord share hist %s, dev mm p50 %.1f" % (
            tag, int(kp.sum()), np.histogram(cn[kp], bins=10, range=(0, 1))[0].tolist(),
            np.median(np.abs(dev[kp])) * 1e3 if kp.any() else 0))
    dt = -dev * alpha * keep * inside * w
    newP = pool.copy()
    newP[:, 0] = xn
    newP[:, ta] = tp + dt
    d = np.linalg.norm(newP - pool, axis=1)
    model.unpool(newP)
    report.append("%s: moved %d of %d points in the box, max %.2f mm" % (tag, int((d > 1e-6).sum()), len(pool),
                                                                         d.max() * 1e3))


def broad_dev(P, dev, r=None):
    """Median |dev| over the points within r of each point. A lump or spike a few millimetres across (remesh noise)
    has a small broad deviation and is smoothed away; a pylon, hatch, antenna or fairing is broad and is kept."""
    nb = cKDTree(P).query_ball_point(P, BROAD_R if r is None else r)
    a = np.abs(dev)
    return np.array([np.median(a[i]) for i in nb])


def smooth_top(model, spec, report):
    """Even out the upper skin of a broad, gently curved body part (fuselage spine, wing glove): the skin as a
    height field y(x, z) (medians of the upward-facing skin in 3 mm cells, smoothed more along the body than
    across, so crowns keep their curvature) and every top-skin point pulled towards it. Bumps and dimples of a few
    millimetres go; broad shapes (canopy, hatches, fairings, the fin root) are left alone by broad_dev; the lower
    skin of a thin part is told apart from the top by the height of the downward-facing skin in the same cell, so a
    thin sheet is never squeezed. Pure function of the position, like polish_surface."""
    name, x0, x1, z0, z1, mirror, sig_x, sig_z = spec
    AP, AN = model.analysis_points()

    def zc(P):
        return np.abs(P[:, 2]) if mirror else P[:, 2]
    x, y, z = AP[:, 0], AP[:, 1], zc(AP)
    m = (x > x0) & (x < x1) & (z > z0) & (z < z1)
    nx, nz = int((x1 - x0) / TOP_CELL) + 1, int((z1 - z0) / TOP_CELL) + 1
    ix = np.clip(((x - x0) / TOP_CELL).astype(int), 0, nx - 1)
    iz = np.clip(((z - z0) / TOP_CELL).astype(int), 0, nz - 1)
    H = np.full((nx, nz), np.nan)
    B = np.full((nx, nz), -np.inf)
    up = m & (AN[:, 1] > 0.35)
    key = ix[up] * nz + iz[up]
    o = np.argsort(key)
    ks, ys = key[o], y[up][o]
    u, st = np.unique(ks, return_index=True)
    for k, a, b in zip(u, st, np.append(st[1:], len(ks))):
        c = ys[a:b]
        # the uppermost layer only: a nacelle or store top under a glove faces up too
        H[k // nz, k % nz] = np.median(c[c >= c.max() - TOP_DIP])
    dn = m & (AN[:, 1] < -0.35)
    np.maximum.at(B, (ix[dn], iz[dn]), y[dn])
    have = ~np.isnan(H)
    if have.sum() < 20:
        report.append("%s: too few top cells, skipped" % name)
        return
    # normalised gaussian: holes and box edges do not pull the surface down
    sg = (sig_x / TOP_CELL, sig_z / TOP_CELL)
    wgt = gaussian_filter(have.astype(float), sg, mode="nearest")
    Hs = gaussian_filter(np.where(have, H, 0.0), sg, mode="nearest")
    Hs = np.where(wgt > 0.2, Hs / np.maximum(wgt, 1e-6), np.nan)

    def ev(G, xq, zq):
        fx = np.clip((xq - x0) / TOP_CELL - 0.5, 0, nx - 1.001)
        fz = np.clip((zq - z0) / TOP_CELL - 0.5, 0, nz - 1.001)
        i0, j0 = fx.astype(int), fz.astype(int)
        a, b = fx - i0, fz - j0
        return (G[i0, j0] * (1 - a) * (1 - b) + G[i0 + 1, j0] * a * (1 - b) + G[i0, j0 + 1] * (1 - a) * b
                + G[i0 + 1, j0 + 1] * a * b)
    mg = 0.006

    def in_box(P):
        xx, zz = P[:, 0], zc(P)
        return (xx > x0 - mg) & (xx < x1 + mg) & (zz > z0 - mg) & (zz < z1 + mg)
    pool = model.pool(in_box)
    if pool is None:
        return
    xp, yp, zp = pool[:, 0], pool[:, 1], zc(pool)
    tgt = ev(Hs, xp, zp)
    ok = ~np.isnan(tgt)
    tgt = np.where(ok, tgt, yp)
    ix = np.clip(((xp - x0) / TOP_CELL).astype(int), 0, nx - 1)
    iz = np.clip(((zp - z0) / TOP_CELL).astype(int), 0, nz - 1)
    bot = B[ix, iz]
    dev = yp - tgt
    # top skin only: nearer the top height than the downward-facing skin of the cell, and within a dimple's depth
    # below it (deeper is another surface: the lower skin, a well, a nacelle)
    fin = np.isfinite(bot)
    rel = np.where(fin, (yp - np.where(fin, bot, 0.0)) / np.maximum(tgt - np.where(fin, bot, 0.0), 1e-5), 1.0)
    on_top = smoothstep(0.55, 0.75, rel) * smoothstep(-TOP_DIP, -0.5 * TOP_DIP, dev)
    keep = 1 - smoothstep(0.0015, 0.004, broad_dev(pool, dev))
    w = (smoothstep(x0 - mg, x0 + 0.01, xp) * (1 - smoothstep(x1 - 0.01, x1 + mg, xp))
         * smoothstep(z0 - mg, z0 + 0.008, zp) * (1 - smoothstep(z1 - 0.008, z1 + mg, zp)))
    dy = -dev * 0.85 * keep * on_top * w * ok
    if os.environ.get("POLISH_DEBUG"):
        deep = (rel > 0.75) & (w > 0.5) & ok
        report.append("%s: top points %d, dev mm percentiles 1/5/50/95/99 %s, broad>1.5mm %d" % (
            name, int(deep.sum()), np.round(np.percentile(dev[deep], [1, 5, 50, 95, 99]) * 1e3, 2).tolist(),
            int((keep[deep] < 0.5).sum())))
    newP = pool.copy()
    newP[:, 1] = yp + dy
    model.unpool(newP)
    mv = np.abs(dy) > 1e-6
    report.append("%s: top skin %d cells, moved %d of %d points, max %.2f mm, p95 %.2f mm" % (
        name, int(have.sum()), int(mv.sum()), len(pool), np.abs(dy).max() * 1e3,
        np.percentile(np.abs(dy[mv]), 95) * 1e3 if mv.any() else 0.0))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    a = ap.parse_args()
    m = Model(a.src)
    rep = []
    m.fix_winding(rep)
    for spec in TOPS.get(a.key, []):
        smooth_top(m, spec, rep)
    for spec in SURF[a.key]:
        if spec[1] == "z":
            for side in (-1, 1):
                polish_surface(m, spec, side, rep)
        else:
            polish_surface(m, spec, 0, rep)
    m.write(a.dst)
    print("\n".join(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
