"""Hangar skin refit (Kanta, 01.11: «Кит» bombers still crumpled after several smoothing passes): rebuild the dented
skin of the remeshed hangar planes on fitted smooth surfaces, without touching topology, UVs or textures.

Why not another smoothing pass: the dents of the generator remesh are broad (10-40 mm across, 1-10 mm deep, model
length 1000 mm) and sit on curved shapes (nacelles, wing-root blends, the body of «Кит» 2). A local filter
(Taubin, the normal filter of plane_polish.denoise) only takes the facet noise off them: a dent that wide is
smooth at the filter's scale, so it stayed. Here each part of the skin is described by a smooth surface fitted to
it, and the skin is moved onto that surface:

1. Fitted surfaces (config FITS, model axes):
   - "tube": a nacelle or a fuselage as r(x, theta) round a straight axis: cubic B-spline in x (knots KU apart)
     times a periodic cubic B-spline in theta (KV knots round), with a second-difference penalty in both
     directions (a fair surface: no curvature wobble), fitted to the skin that faces outwards;
   - "height": a broad top or bottom skin (the blended body and wing roots of «Кит» 2, wing tops) as y(x, z),
     the same penalised spline on a (x, z) grid; cylinders round the nacelles are left out of its data.
   The fit is robust (Tukey reweighting, scale floor FIT_FLOOR): a dent or a bulge is an outlier and does not pull
   the surface, so it is cut out rather than averaged in.
2. Projection. Each skin vertex of a fit's box that faces along the fit's value direction and lies within GATE of
   the surface gets the target move onto it (radial for tubes, vertical for heights); farther points are other
   parts (a wing through a nacelle, a pylon, an antenna) and are left alone.
3. Blend. The moves are one displacement field on the welded skin: targets where a vertex was projected, zero
   outside every box and on the canopy glass, and in between (junctions, fillets, the vertices a gate rejected)
   the smoothest field (a thin-plate solve on the mesh graph, so its slope has no kink either). So a nacelle junction blends from the nacelle's
   surface into the wing's with no step, and a crease (wing edge, mechanisation cut, intake lip) is carried along
   with its neighbours and stays as sharp as it was.
The skin, the cut-out slats, flaps and bay doors are one welded mesh (cut seams move together); the dark wells
take the move of the nearest skin vertices. Moved vertices get fresh normals: area-weighted over the welded faces
(the old normals followed the dents).

The dent metric (--report): per vertex, the height over a robust local quadric fitted over radius DENT_R (normals
agreeing) — a dent or bulge reads as its depth — p95 / p99 / max per fit box, before and after.

  python3 -I skin_refit.py <hangar.glb> <key> <out.glb> [--report] [--mask <out_mask.png> [--mask-size 4096]]
--mask writes the UV coverage of the moved skin (white where a vertex moved more than 0.15 mm) for tex_clean.py
--even --mask (the dent shading baked in the paint is evened out there only).
Axes: glTF model space of the hangar model (nose +X, up +Y, right wing +Z), length 1."""
import argparse
import os
import sys

import numpy as np
from scipy.sparse import coo_matrix, csr_matrix, diags, identity
from scipy.sparse.linalg import spsolve
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plane_polish as pp  # noqa: E402

# Fitted surfaces per plane (model units). Every entry is fitted on each side (z < 0 and z > 0) separately; a tube
# on the centre line (fuselage) has zc 0 and is fitted once.
# ("tube", name, x0, x1, yc0, zc0, yc1, zc1, rmax, ku, kv): axis from (x0, yc0, zc0) to (x1, yc1, zc1), skin
#   within rmax of it; ku knot spacing along x, kv knots round.
# ("height", name, x0, x1, |z|0, |z|1, y0, y1, side, ku, kv, holes): skin between y0 and y1 facing up (side +1)
#   or down (-1); ku, kv knot spacing in x and z; holes: (yc, |zc|, r) cylinders along x left out.
FITS: dict = {
    "bomber_1": [
        ("tube", "fuselage", 0.30, -0.22, -0.062, 0.0, -0.056, 0.0, 0.05, 0.025, 36),
        ("tube", "nac_in", 0.145, -0.07, -0.066, 0.139, -0.066, 0.139, 0.045, 0.025, 36, {"skip": [(-60, 60)]}),
        ("tube", "nac_out", 0.095, -0.10, -0.079, 0.290, -0.079, 0.295, 0.045, 0.025, 36, {"skip": [(-60, 60)]}),
    ],
    "bomber_2": [
        ("tube", "nac", -0.105, -0.235, -0.023, 0.07, -0.023, 0.07, 0.05, 0.025, 36, {"skip": [(-125, -55), (55, 125)]}),
    ],
}
MARGIN = 0.010      # the projection fades to nothing over this round a fit's box
GATE = (0.003, 0.005)  # off the fitted surface by more than this: another part, not skin of this surface
FIT_FLOOR = 0.0004  # robust scale floor of the fits: deviations well over it are dents, not skin
LAM = (4.0, 0.5)   # penalty of the fits along u (x) and v (round / z): second differences of the coefficients,
# relative to the data. Dents are short along the flow, the sections' own shape (a chin, a fairing) runs along it
BLEND = 0.003       # thin-plate weight of the blend solve against a projected vertex's own target
ANCHOR = 0.01       # weak pull to zero of the blended skin without a target (the thin plate would extrapolate)
SKIP_FADE = np.radians(20.0)  # fade of a tube's skipped sector
SEAM_TIE = 0.004    # open edges this close are tied across a cut in the blend
JUNCTION_ITERS = 4  # Taubin steps on the junction skin the fits did not reach
SEAM = 0.002        # open-edge vertices this close share their move (unwelded cut seams)
REACH = 24          # rings round the projected skin over which the blend may move the skin
DENT_R = 0.016      # radius of the local quadric of the dent metric


def smoothstep(a, b, x):
    """Hermite step from 0 at a to 1 at b"""
    return pp.smoothstep(a, b, x)


def vertex_normals(W, F, ref):
    """Area-weighted vertex normals with every face turned to agree with the reference normals of its corners
    (the remesh has a few faces wound against the rest)"""
    fn = np.cross(W[F[:, 1]] - W[F[:, 0]], W[F[:, 2]] - W[F[:, 0]])
    s = np.sign(np.einsum("ij,ij->i", fn, ref[F].sum(1)))
    fn *= np.where(s == 0, 1, s)[:, None]
    n = np.zeros_like(W)
    for k in range(3):
        np.add.at(n, F[:, k], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)


def _bspline_rows(t, n, periodic):
    """Uniform cubic B-spline basis at parameter t (in knot units, 0..n-? for open, 0..n for periodic): column
    indices (m, 4) and weights (m, 4). Open splines have n coefficients covering t in [0, n - 3]."""
    i = np.floor(t).astype(np.int64)
    f = t - i
    w = np.stack([(1 - f) ** 3 / 6, (3 * f ** 3 - 6 * f ** 2 + 4) / 6, (-3 * f ** 3 + 3 * f ** 2 + 3 * f + 1) / 6,
                  f ** 3 / 6], 1)
    cols = i[:, None] + np.arange(4)[None, :]
    if periodic:
        cols = (cols - 1) % n
    else:
        cols = np.clip(cols, 0, n - 1)
    return cols, w


class Spline2:
    """Penalised tensor cubic B-spline value(u, v) on [u0, u1] x [v0, v1] (v periodic when asked), fitted robustly
    by fit(); __call__ evaluates it"""

    def __init__(self, u0, u1, ku, v0, v1, kv, periodic=False):
        self.u0, self.ku = u0 - ku, ku
        self.nu = int(np.ceil((u1 - u0) / ku)) + 3
        self.periodic = periodic
        if periodic:
            self.v0, self.nv = v0, int(kv)
            self.kv = (v1 - v0) / self.nv
        else:
            self.v0, self.kv = v0 - kv, kv
            self.nv = int(np.ceil((v1 - v0) / kv)) + 3
        self.c = np.zeros(self.nu * self.nv)

    def design(self, u, v):
        """Sparse design matrix of the points (u, v)"""
        cu, wu = _bspline_rows(np.clip((u - self.u0) / self.ku, 0, self.nu - 3 - 1e-9), self.nu, False)
        tv = (v - self.v0) / self.kv
        if self.periodic:
            cv, wv = _bspline_rows(np.mod(tv, self.nv), self.nv, True)
        else:
            cv, wv = _bspline_rows(np.clip(tv, 0, self.nv - 3 - 1e-9), self.nv, False)
        m = len(u)
        cols = (cu[:, :, None] * self.nv + cv[:, None, :]).reshape(m, 16)
        vals = (wu[:, :, None] * wv[:, None, :]).reshape(m, 16)
        rows = np.repeat(np.arange(m), 16)
        return csr_matrix((vals.reshape(-1), (rows, cols.reshape(-1))), shape=(m, self.nu * self.nv))

    def penalty(self, lu=1.0, lv=1.0):
        """Second differences of the coefficient grid along u (weight lu) and along v (lv, wrapping when
        periodic)"""
        nu, nv = self.nu, self.nv
        idx = np.arange(nu * nv).reshape(nu, nv)
        r, c, d = [], [], []
        k = 0
        for a, b, cc in ((idx[:-2], idx[1:-1], idx[2:]),):
            for x in zip(a.reshape(-1), b.reshape(-1), cc.reshape(-1)):
                r += [k, k, k]
                c += list(x)
                d += [lu, -2.0 * lu, lu]
                k += 1
        if self.periodic:
            a, b, cc = idx, np.roll(idx, -1, 1), np.roll(idx, -2, 1)
        else:
            a, b, cc = idx[:, :-2], idx[:, 1:-1], idx[:, 2:]
        for x in zip(a.reshape(-1), b.reshape(-1), cc.reshape(-1)):
            r += [k, k, k]
            c += list(x)
            d += [lv, -2.0 * lv, lv]
            k += 1
        return csr_matrix((d, (r, c)), shape=(k, nu * nv))

    def fit(self, u, v, val, prior=None, iters=8, lam=(1.0, 1.0)):
        """Robust penalised least squares (lam: penalty along u and along v); returns the final robust weights"""
        B = self.design(u, v)
        D = self.penalty(np.sqrt(lam[0]), np.sqrt(lam[1]))
        P = (D.T @ D) * max(len(u), 1) / (self.nu * self.nv) + identity(self.nu * self.nv) * 1e-8
        w = np.ones(len(u)) if prior is None else prior.copy()
        for _ in range(iters):
            Bw = B.multiply(w[:, None]).tocsr()
            self.c = spsolve((B.T @ Bw + P).tocsc(), Bw.T @ val)
            r = val - B @ self.c
            sc = 4.685 * max(np.median(np.abs(r[w > 0.5])) * 1.4826 if (w > 0.5).any() else FIT_FLOOR, FIT_FLOOR)
            tw = np.where(np.abs(r) < sc, (1 - (r / sc) ** 2) ** 2, 0.0)
            w = tw if prior is None else tw * prior
        return w

    def __call__(self, u, v):
        return self.design(u, v) @ self.c


def box_weight(x, lo, hi):
    """1 inside [lo, hi], fading to 0 over MARGIN outside"""
    return smoothstep(lo - MARGIN, lo, x) * (1 - smoothstep(hi, hi + MARGIN, x))


def fit_tube(W, N, spec, side, report):
    """One "tube" entry on one side: targets (index array, displacement vectors, weights)"""
    _, name, x0, x1, yc0, zc0, yc1, zc1, rmax, ku, kv = spec[:11]
    opt = spec[11] if len(spec) > 11 else {}
    lam = opt.get("lam", LAM)
    zc0, zc1 = zc0 * side, zc1 * side
    a0, a1 = np.array([x0, yc0, zc0]), np.array([x1, yc1, zc1])
    ax = (a1 - a0) / np.linalg.norm(a1 - a0)
    s = (W - a0) @ ax
    L = np.linalg.norm(a1 - a0)
    rel = W - a0 - s[:, None] * ax[None, :]
    r = np.linalg.norm(rel, axis=1)
    e1 = np.array([0.0, 1.0, 0.0]) - ax * ax[1]
    e1 /= np.linalg.norm(e1)
    e2 = np.array([0.0, 0.0, 1.0 if side > 0 else -1.0])   # theta > 0: outboard
    e2 -= ax * (ax @ e2) + e1 * (e1 @ e2)
    e2 /= np.linalg.norm(e2)
    th = np.arctan2(rel @ e2, rel @ e1)
    rd = rel / np.maximum(r[:, None], 1e-12)
    facing = np.einsum("ij,ij->i", N, rd)
    # sectors where another part grows out of the tube (a wing over a nacelle): no data, no projection there
    keep = np.ones(len(W))
    for a, b in opt.get("skip", []):
        ta, tb = np.radians(a), np.radians(b)
        keep *= 1 - smoothstep(ta - SKIP_FADE, ta, th) * (1 - smoothstep(tb, tb + SKIP_FADE, th))
    sel = (s > -MARGIN) & (s < L + MARGIN) & (r < rmax) & (r > 0.2 * rmax) & (facing > 0.45) & (keep > 0)
    if sel.sum() < 100:
        report.append("%s%s: %d points, skipped" % (name, "LR"[side > 0] if zc0 or zc1 else "", int(sel.sum())))
        return None
    sp = Spline2(-MARGIN, L + MARGIN, ku, -np.pi, np.pi, kv, periodic=True)
    core = sel
    rw = sp.fit(s[core], th[core], r[core], prior=np.clip(facing[core] * 2 - 0.9, 0, 1) * keep[core], lam=lam)
    rf = sp(s[sel], th[sel])
    dlt = rf - r[sel]
    g = (1 - smoothstep(GATE[0], GATE[1], np.abs(dlt))) * box_weight(s[sel], MARGIN, L - MARGIN) * smoothstep(0.45, 0.75, facing[sel]) * keep[sel]
    idx = np.nonzero(sel)[0]
    ok = g > 0
    tag = "%s%s" % (name, ("L" if side < 0 else "R") if zc0 or zc1 else "")
    report.append("%-12s tube: %5d points fitted (%.0f %% kept by the robust fit), %5d projected, move p95 %.2f "
                  "max %.2f mm" % (tag, int(core.sum()), 100 * np.mean(rw > 0.5), int(ok.sum()),
                                   np.percentile(np.abs(dlt[ok]), 95) * 1e3, np.abs(dlt[ok]).max() * 1e3))
    return idx[ok], (dlt[ok][:, None] * rd[idx[ok]]), g[ok]


def fit_height(W, N, spec, side, report):
    """One "height" entry on one side: targets (index array, displacement vectors, weights)"""
    _, name, x0, x1, z0, z1, y0, y1, up, ku, kv, holes = spec[:12]
    lam = spec[12] if len(spec) > 12 else LAM
    x, y, z = W[:, 0], W[:, 1], W[:, 2] * side
    facing = N[:, 1] * up
    sel = (x > x0 - MARGIN) & (x < x1 + MARGIN) & (z > z0 - MARGIN) & (z < z1 + MARGIN) & (y > y0) & (y < y1) \
        & (facing > 0.35)
    for hy, hz, hr in holes:
        sel &= np.hypot(y - hy, z - hz) > hr
    if sel.sum() < 100:
        report.append("%s: %d points, skipped" % (name, int(sel.sum())))
        return None
    sp = Spline2(x0 - MARGIN, x1 + MARGIN, ku, z0 - MARGIN, z1 + MARGIN, kv)
    rw = sp.fit(x[sel], z[sel], y[sel], prior=np.clip(facing[sel] * 2 - 0.7, 0, 1), lam=lam)
    yf = sp(x[sel], z[sel])
    dlt = yf - y[sel]
    g = ((1 - smoothstep(GATE[0], GATE[1], np.abs(dlt))) * box_weight(x[sel], x0, x1) * box_weight(z[sel], z0, z1)
         * smoothstep(0.35, 0.6, facing[sel]))
    idx = np.nonzero(sel)[0]
    ok = g > 0
    tag = "%s%s" % (name, "L" if side < 0 else "R")
    report.append("%-12s height: %5d points fitted (%.0f %% kept by the robust fit), %5d projected, move p95 %.2f "
                  "max %.2f mm" % (tag, int(sel.sum()), 100 * np.mean(rw > 0.5), int(ok.sum()),
                                   np.percentile(np.abs(dlt[ok]), 95) * 1e3, np.abs(dlt[ok]).max() * 1e3))
    D = np.zeros((int(ok.sum()), 3))
    D[:, 1] = dlt[ok]
    return idx[ok], D, g[ok]


def refit(W0, F, Nref, fixed, fits, report, rounds=2):
    """Fit every entry, collect the targets, blend them into one displacement field (thin-plate solve on the mesh
    graph, zero on fixed vertices and outside every box); `rounds` times on the moved skin. Returns positions."""
    n = len(W0)
    e = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), 1)
    e, cnt = np.unique(e, axis=0, return_counts=True)
    # the cut-out parts are separate pieces of the weld: tie their open edges to the skin's across the cut, so
    # the blend moves both sides of a seam alike
    ov = np.unique(e[cnt == 1].reshape(-1))
    tie = cKDTree(W0[ov]).query_pairs(SEAM_TIE, output_type="ndarray")
    Ar = coo_matrix((np.ones(2 * len(e)), (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(n, n)).tocsr()
    Ar.data[:] = 1.0
    # the Taubin pass of the junctions stays off edges, creases and thin plates (their neighbours are the other
    # skin of the plate)
    calm = np.ones(n, bool)
    calm[ov] = False
    calm[pp._creases(W0, F, 35.0, 0.004).reshape(-1)] = False
    calm &= ~(Ar @ (~calm).astype(float) > 0)
    e = np.vstack([e, ov[tie]]) if len(tie) else e
    A = coo_matrix((np.ones(2 * len(e)), (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    Lap = diags(np.asarray(A.sum(1)).ravel()) - A
    W = W0.copy()
    for rnd in range(rounds):
        report.append("round %d" % rnd)
        N = vertex_normals(W, F, Nref)
        T = np.zeros_like(W)
        C = np.zeros(n)
        inbox = np.zeros(n, bool)
        for spec in fits:
            sides = (-1, 1) if not (spec[0] == "tube" and spec[5] == 0 and spec[7] == 0) else (1,)
            for side in sides:
                res = (fit_tube if spec[0] == "tube" else fit_height)(W, N, spec, side, report)
                if res is None:
                    continue
                idx, D, g = res
                T[idx] += D * g[:, None]
                C[idx] += g
                inbox[idx] = True
        tgt = T / np.maximum(C, 1e-9)[:, None]
        c = np.minimum(C, 1.0)
        # free: in reach of a box (within a few rings of a projected vertex); everything else is held at zero
        reach = inbox.copy()
        for _ in range(REACH):
            reach = reach | (A @ reach.astype(float) > 0)
        hold = (~reach) | fixed
        c = np.where(hold, 1e3, np.maximum(c, ANCHOR))
        tgt[hold] = 0
        M = (diags(c) + BLEND * (Lap.T @ Lap)).tocsc()
        Dn = np.stack([spsolve(M, c * tgt[:, k]) for k in range(3)], 1)
        W = W + Dn
        # junctions: the skin the fits did not reach (fillets between a nacelle and the wing, the root of a fin)
        # keeps the generator's facet noise; a few normal-direction Taubin steps there, nowhere else
        jn = reach & ~hold & (c < 0.5) & calm
        W = _taubin(W, F, Ar, jn, Nref)
        mv = np.linalg.norm(Dn, axis=1)
        report.append("  blended move: %d vertices over 0.05 mm, p95 %.2f max %.2f mm" % (
            int((mv > 5e-5).sum()), np.percentile(mv[mv > 5e-5], 95) * 1e3 if (mv > 5e-5).any() else 0, mv.max() * 1e3))
    return W


def _taubin(W, F, A, sel, Nref, iters=JUNCTION_ITERS):
    """Taubin smoothing (lambda 0.5, mu -0.53) of the selected vertices along their normals only (the paint does
    not slide); returns new positions"""
    deg = np.maximum(np.asarray(A.sum(1)).ravel(), 1)
    W = W.copy()
    for _ in range(iters):
        for f in (0.5, -0.53):
            N = vertex_normals(W, F, Nref)
            d = (A @ W) / deg[:, None] - W
            dn = np.einsum("ij,ij->i", d, N)
            W[sel] += f * dn[sel, None] * N[sel]
    return W


def dent_metric(W, N, pick, R=DENT_R):
    """Height of each picked vertex over a robust local quadric (radius R, neighbours facing the same way)"""
    tree = cKDTree(W)
    idx = np.nonzero(pick)[0]
    dev = np.zeros(len(W))
    for i, nb in zip(idx, tree.query_ball_point(W[idx], R)):
        nb = np.asarray(nb)
        nb = nb[N[nb] @ N[i] > 0.3]
        if len(nb) < 12:
            continue
        Q = W[nb] - W[i]
        nr = N[nb].mean(0)
        nr /= np.linalg.norm(nr)
        a = np.cross(nr, [1, 0, 0] if abs(nr[0]) < 0.9 else [0, 1, 0])
        a /= np.linalg.norm(a)
        b = np.cross(nr, a)
        u, v, h = Q @ a, Q @ b, Q @ nr
        G = np.stack([u * u, u * v, v * v, u, v, np.ones_like(u)], 1)
        g0 = np.exp(-0.5 * (np.hypot(u, v) / (0.5 * R)) ** 2)
        w = g0
        for _ in range(3):
            s = np.sqrt(w)
            c, *_ = np.linalg.lstsq(G * s[:, None], h * s, rcond=None)
            r = h - G @ c
            sc = 4.685 * max(np.median(np.abs(r)) * 1.4826, 1e-4)
            w = g0 * np.where(np.abs(r) < sc, (1 - (r / sc) ** 2) ** 2, 0) + 1e-9
        dev[i] = -c[5]
    return dev


def fit_box(W, N, spec):
    """Vertices inside a fit entry's box on either side (for the dent report)"""
    x, y, z = W[:, 0], W[:, 1], np.abs(W[:, 2])
    if spec[0] == "tube":
        _, name, x0, x1, yc0, zc0, yc1, zc1, rmax = spec[:9]
        t = np.clip((x - x0) / (x1 - x0), 0, 1)
        return (x > min(x0, x1)) & (x < max(x0, x1)) & (np.hypot(y - (yc0 + t * (yc1 - yc0)), z - (zc0 + t * (zc1 - zc0))) < rmax)
    _, name, x0, x1, z0, z1, y0, y1, up = spec[:9]
    return (x > x0) & (x < x1) & (z > z0) & (z < z1) & (y > y0) & (y < y1) & (N[:, 1] * up > 0.35)


def main():
    """Command line: refit the zones of one hangar GLB and write the result"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--mask")
    ap.add_argument("--mask-size", type=int, default=4096)
    a = ap.parse_args()
    m = pp.Model(a.src)
    keys, offs, inv, W0, F = pp._skin_weld(m)
    # reference normals per welded vertex from the GLB (skin accessors only)
    Nref = np.zeros_like(W0)
    glass = np.zeros(len(W0), bool)
    for k in keys:
        e = m.acc[k]
        ii = inv[offs[k]:offs[k] + len(e["P"])]
        if "N" in e:
            np.add.at(Nref, ii, e["N"])
        for t, mt in zip(e["tris"], e["tri_mats"]):
            if mt == "glass":
                glass[ii[t.reshape(-1)]] = True
    Nref /= np.maximum(np.linalg.norm(Nref, axis=1, keepdims=True), 1e-20)
    used = np.zeros(len(W0), bool)
    used[F.reshape(-1)] = True
    fixed = glass | ~used
    fits = FITS[a.key]
    rep = ["%s: %d welded skin vertices, %d fixed (canopy glass)" % (a.key, len(W0), int(fixed.sum()))]
    W = refit(W0, F, Nref, fixed, fits, rep)
    mv = np.linalg.norm(W - W0, axis=1)
    rep.append("moved %d vertices, max %.2f mm, p95 %.2f mm" % (
        int((mv > 1e-6).sum()), mv.max() * 1e3, np.percentile(mv[mv > 1e-6], 95) * 1e3 if (mv > 1e-6).any() else 0))
    if a.report:
        N0 = vertex_normals(W0, F, Nref)
        N1 = vertex_normals(W, F, Nref)
        for spec in fits:
            pick = fit_box(W0, N0, spec) & ~fixed
            if pick.sum() < 20:
                continue
            d0 = np.abs(dent_metric(W0, N0, pick))[pick]
            d1 = np.abs(dent_metric(W, N1, pick))[pick]
            rep.append("%-14s dent p95 %.2f -> %.2f mm, p99 %.2f -> %.2f mm, max %.2f -> %.2f mm (%d vertices)" % (
                spec[1], np.percentile(d0, 95) * 1e3, np.percentile(d1, 95) * 1e3, np.percentile(d0, 99) * 1e3,
                np.percentile(d1, 99) * 1e3, d0.max() * 1e3, d1.max() * 1e3, int(pick.sum())))
    write_back(m, keys, offs, inv, W0, W, F, Nref, fixed)
    m.write(a.dst)
    if a.mask:
        write_mask(m, keys, offs, inv, mv, a.mask, a.mask_size)
    print("\n".join(rep))
    return 0


def write_back(m, keys, offs, inv, W0, W, F, Nref, fixed):
    """Moved welded positions back into every accessor; the wells (not in the weld) follow the nearest skin
    vertices. Moved vertices get fresh normals: the area-weighted normals of the welded faces round them that lie
    within 50 degrees of the vertex's own old normal (a vertex on one side of a hard edge takes only its side),
    blended in over the first 0.3 mm of the move so no shading seam marks where the refit fades out."""
    D = W - W0
    # cut seams whose two sides are not welded (slat, flap and bay door edges a hair off the skin's edge): the
    # open-edge vertices within SEAM of each other take one common move, so no crack opens
    e = np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), 1)
    ue, cnt = np.unique(e, axis=0, return_counts=True)
    ov = np.unique(ue[cnt == 1].reshape(-1))
    if len(ov):
        Do = D[ov].copy()
        for i, nb in enumerate(cKDTree(W0[ov]).query_ball_point(W0[ov], SEAM)):
            Do[i] = D[ov[nb]].mean(0)
        D[ov] = Do
        W = W0 + D
    mv = np.linalg.norm(D, axis=1)
    fn = np.cross(W[F[:, 1]] - W[F[:, 0]], W[F[:, 2]] - W[F[:, 0]])   # length = 2 x area
    vf = coo_matrix((np.ones(3 * len(F)), (F.reshape(-1), np.repeat(np.arange(len(F)), 3))),
                    shape=(len(W), len(F))).tocsr()
    tree = cKDTree(W0)
    for k in keys:
        e = m.acc[k]
        cnt = len(e["P"])
        ii = inv[offs[k]:offs[k] + cnt]
        if e["kinds"] == {"mech_well"}:
            dd, j = tree.query(e["P"], k=4)
            w = 1.0 / np.maximum(dd, 1e-5)
            e["P"] = e["P"] + (D[j] * w[:, :, None]).sum(1) / w.sum(1, keepdims=True)
            continue
        e["P"] = W[ii].copy()
        if "N" not in e:
            continue
        sel = np.nonzero((mv[ii] > 1e-6) & ~fixed[ii])[0]
        for vi in sel:
            no = e["N"][vi]
            fs = vf.indices[vf.indptr[ii[vi]]:vf.indptr[ii[vi] + 1]]
            if not len(fs):
                continue
            f = fn[fs]
            f = f * np.sign(f @ no + 1e-30)[:, None]
            ln = np.linalg.norm(f, axis=1)
            ok = f @ no > 0.64 * ln
            if not ok.any():
                continue
            nn = f[ok].sum(0)
            nn /= max(np.linalg.norm(nn), 1e-20)
            t = smoothstep(0.0, 0.0003, mv[ii[vi]])
            nb = (1 - t) * no + t * nn
            e["N"][vi] = nb / max(np.linalg.norm(nb), 1e-20)
    # write() adds a normal delta for every accessor; the normals set here are final
    m._normal_deltas = lambda: {k: np.zeros_like(m.acc[k]["P"]) for k in m.acc if m.acc[k]["nrm"] is not None}


def write_mask(m, keys, offs, inv, mv, path, size):
    """UV coverage of the moved skin triangles (white where any corner moved over 0.15 mm), slightly grown"""
    from PIL import Image, ImageDraw, ImageFilter
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    g = m.g
    for ni, nd in enumerate(g.j["nodes"]):
        if "mesh" not in nd:
            continue
        for pr in g.j["meshes"][nd["mesh"]]["primitives"]:
            a = pr["attributes"]["POSITION"]
            if "TEXCOORD_0" not in pr["attributes"] or a not in offs:
                continue
            uv = g.accessor(pr["attributes"]["TEXCOORD_0"]) * size
            T = g.accessor(pr["indices"]).reshape(-1, 3)
            ii = inv[offs[a]:offs[a] + len(uv)]
            hot = (mv[ii] > 0.00015)[T].any(1)
            for t in T[hot]:
                d.polygon([tuple(uv[t[0]]), tuple(uv[t[1]]), tuple(uv[t[2]])], fill=255)
    im.filter(ImageFilter.MaxFilter(9)).save(path)


if __name__ == "__main__":
    sys.exit(main())
