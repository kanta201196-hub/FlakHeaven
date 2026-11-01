"""Clean built nacelles and junctions for the remeshed «Кит» bombers (Kanta, 01.11: crumpled, dented orange camo on the nacelles,
dark dimples on the nacelle tops of «Кит» 2; skin_refit.py barely helped, see its header).

Why skin_refit.py was not enough: it fitted a fine spline (5 mm knots round a nacelle) to the dented skin and moved
the old vertices onto it within a gate. A spline that fine follows a 10-40 mm dent, the gate left the deep dents
alone, the old dented normals and the old top-down UV (smeared on the nacelle sides) stayed, and so did the dark
dent shading baked in the paint. Here each nacelle is described as built geometry and the skin round it is rebuilt
on that description, the way intake_rebuild.py rebuilt the intakes:

1. Shape (config REGIONS, model axes, both sides mirrored):
   - the nacelle: a lofted tube r = R(s, theta) round a straight axis (s along it, theta 0 up and + outboard),
     a coarse periodic B-spline round it (KV knots: the section's own shape, a chin or a keel, but no dent) times
     a cubic spline along it, both strongly penalised, fitted robustly to the old nacelle skin away from the wing;
     a rounded cap at its front (the spinner base or where it leaves the wing glove) and at its tail;
   - the wing or body it grows out of: an upper and a lower penalised height field y(x, z), fitted to that skin
     away from the nacelle and bridging under it; their smooth max is the slab (rounded where they meet);
   - one implicit surface f = smin(tube, slab, k): the polynomial smooth minimum gives a fillet of size k round
     the whole junction, upper and lower, with no step and no crease.
2. Rebuild. Every skin vertex of the region (where the nacelle or the fillet is the nearest part of f, fading out
   over the wing; not near the slats, flaps, bay doors, wells or canopy, which stay put with their cut seams) is
   projected onto f = 0 (Newton steps along the gradient), then the region is relaxed tangentially and projected
   again, so the crumpled old triangulation becomes an even one on the clean surface. Normals come from the
   gradient of f, so the shading is as smooth as the surface itself.
3. Paint. The rebuilt faces get their own UV islands (Blender's angle-based unwrap, packed into free atlas space
   at the skin's texel density) and their colour and ORM are projection-baked from the old surface (each texel's
   point on the new surface, along its normal, onto the old skin and through the old UV). The dent shading the
   generator baked into the old paint is divided out: inside each camouflage tone, the slow luminance variation
   (the dark dimples) is evened to the tone's own level; fine detail and the camouflage edges stay. Occlusion in
   the ORM map is evened the same way.

4. Junctions that are neither tube nor slab (first used on the torn skin round the old «Грач» 2 intake ring):
   a region may be a Sheet instead, one penalised height field over a tilted plane fitted robustly to the skin
   (the torn fringes are its outliers). The intake itself is kept by its UV island (KEEP_UV); the see-through gaps
   between the skin and the intake's rim are bridged with sunk strips, and the intake body's dark wall where it
   shows through takes the skin's paint.

Status (01.11): «Кит» 1 shipped. «Грач» 2's junction regions were dropped: intake_rebuild.py now builds the
intake with its fairing, splitter and gap from the generator's skin, so there is no torn skin left to rebuild.
The «Кит» 2 config is kept for the next try but its result was not taken: the nacelle front became a blunt bulb,
the outboard shoulder boxy, and the bay side opened small holes.

  python3 -I nacelle_rebuild.py <hangar.glb> <key> <out.glb> --maps <col.jpg> <orm.jpg> [--report] [--geo-only]
The maps are rewritten in place (start from copies of the extracted maps), then tex_clean.py pads them.
Axes: glTF model space (nose +X, up +Y, right wing +Z), length 1. Needs numpy, scipy, Pillow; bpy for the unwrap."""
import argparse
import os
import sys

try:
    import bpy  # first: its TBB must load before MeshLab's (else bpy fails to import later)
except ImportError:
    bpy = None
import numpy as np
from PIL import Image
from scipy.sparse import coo_matrix
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plane_polish as pp
import skin_refit as sr

Image.MAX_IMAGE_PIXELS = None

# Regions per plane (model units, right side; the left is mirrored). Each: name; tube: front and rear axis points
# (x, y, |z|), nominal radius r0, s range of the fit data (from the front point), front and rear cap positions in s
# and their rounding, knots round (kv) and spacing along (ku), penalty (lam along, round); slab: box x0, x1, |z|0,
# |z|1, y0, y1 of its data, knot spacing (kx, kz), rounding where upper and lower meet; k: fillet size; box: the
# region's own limits (x0, x1, |z|0, |z|1, y0, y1); a junction that is no tube and slab is a sheet instead (see
# Sheet), optionally with its own projection gate and dark_out (near-black old paint replaced).
REGIONS: dict = {
    "bomber_1": [
        {"name": "nac_in", "k": 0.006, "box": (-0.11, 0.18, 0.075, 0.205, -0.115, -0.015),
         "tube": {"front": (0.170, -0.0628, 0.1395), "rear": (-0.100, -0.056, 0.139), "r0": 0.03,
                  "fit": (0.002, 0.265), "cap_front": (0.0, 0.005), "cap_rear": (0.266, 0.006), "front_keep": 0.012,
                  "kv": 20, "ku": 0.015, "lam": (0.5, 0.3)},
         "slab": {"box": (-0.12, 0.13, 0.06, 0.22, -0.10, -0.02), "kx": 0.02, "kz": 0.02, "lam": (1.0, 1.0),
                  "round": 0.003, "le": [(0.08, 0.1213), (0.10, 0.1063), (0.18, 0.0635), (0.20, 0.0509)], "le_r": 0.006,
                  "te": [(0.08, -0.0442), (0.12, -0.0612), (0.16, -0.0707), (0.20, -0.0862)], "te_r": 0.002}},
        {"name": "nac_out", "k": 0.006, "box": (-0.13, 0.125, 0.23, 0.35, -0.12, -0.03),
         "tube": {"front": (0.115, -0.0770, 0.2902), "rear": (-0.115, -0.072, 0.290), "r0": 0.026,
                  "fit": (0.002, 0.225), "cap_front": (0.0, 0.005), "cap_rear": (0.226, 0.006), "front_keep": 0.012,
                  "kv": 20, "ku": 0.015, "lam": (0.5, 0.3)},
         "slab": {"box": (-0.14, 0.08, 0.22, 0.36, -0.11, -0.04), "kx": 0.02, "kz": 0.02, "lam": (1.0, 1.0),
                  "round": 0.003, "le": [(0.20, 0.0445), (0.36, -0.0435)], "le_r": 0.005,
                  "te": [(0.20, -0.088), (0.36, -0.152)], "te_r": 0.002}},
    ],
    # «Кит» 2: jet nacelles grown into the body behind the wing-root glove, a V crotch to the spine above and to
    # the bomb bay below; the nozzle (x < -0.245) stays as it is
    "bomber_2": [
        {"name": "nac", "k": 0.006, "excl": 0.0015, "box": (-0.243, -0.085, 0.02, 0.13, -0.075, 0.03),
         "keep": [(-0.26, -0.07, 0.0, 0.033, -0.08, -0.022)],
         "tube": {"front": (-0.100, -0.025, 0.070), "rear": (-0.270, -0.025, 0.070), "r0": 0.038,
                  "fit": (0.015, 0.145), "cap_front": (0.008, 0.02), "cap_rear": (0.17, 0.004), "fac": 0.6,
                  "kv": 20, "ku": 0.015, "lam": (0.5, 0.3)},
         "slab": {"box": (-0.27, -0.06, 0.0, 0.16, -0.075, 0.04), "kx": 0.02, "kz": 0.015, "lam": (1.0, 1.0),
                  "round": 0.003}},
    ],
}
# Skin kept by its UV island (texel rectangles x0, y0, x1, y1 in a size atlas) and the fade round it, e.g. a built
# part inside a region: {"key": {"size": (w, h), "rects": [...], "near": (d0, d1), "shell": {...}, "bridge": d}}.
# Empty since the «Грач» intakes were rebuilt with a clean junction (intake_rebuild.py, 01.11).
KEEP_UV: dict = {}
SKIP_NEAR_PARTS = (0.003, 0.009)   # skin this close to slats, flaps, bay doors, wells or glass stays put (fade)
EXCL = 0.003         # data of one part closer than this to the other part's fitted surface is junction, not data
FADE = (0.004, 0.012)  # the region fades out over the slab this far past the fillet (in d = tube - slab - k)
GATE = (0.010, 0.016)  # skin this far off f before the projection is another part (antenna, stub): left alone
RELAX = 12           # tangential relaxation rounds of the rebuilt skin
H = 1e-5             # finite-difference step of the gradient
TARGET_EDGE = 0.003  # edge length of the remeshed core
TONES = 4            # camouflage tones told apart by the dent-shading pass
FLAT_SIGMA = 4.0     # texels: luminance slower than this within a tone is dent shading and evened out
FLAT_CLIP = 0.3      # largest correction of the dent-shading pass
FINE_SIGMA = 2.5     # texels: detail finer than this is kept where the crease shading is replaced
CONC = (0.0001, 0.0006)  # concavity of the old skin (vertex under its neighbours' mean) that reads as a crease
METAL_KEEP = 92      # ORM metal (0..255) over this is exhaust metal: its paint is kept (in EXHAUST_BOXES only)
# the exhaust boxes of Livery.EXHAUST (livery.gd: x0, x1, |z|0, |z|1, y0, y1): metal anywhere else is a crease streak
EXHAUST_BOXES: dict = {"bomber_1": [(-0.16, -0.01, 0.105, 0.19, -0.12, -0.02), (-0.14, 0.04, 0.24, 0.32, -0.13, -0.04)]}
CHART_GAP = 4        # texels kept free round every placed UV chart
RAY = 0.015          # the old skin is looked for this far along the new skin's normal, both ways


def smin(a, b, k):
    """Polynomial smooth minimum (fillet of size k where |a - b| < k)"""
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    """Polynomial smooth maximum"""
    return -smin(-a, -b, k)


class Tube:
    """Lofted nacelle round a straight axis from `front` to `rear` (side +1 right, -1 left mirrored): s along the
    axis from the front, theta 0 up and positive outboard, r from the axis; R(s, theta) is a penalised spline"""

    def __init__(self, cfg, side):
        f = np.array(cfg["front"], float)
        b = np.array(cfg["rear"], float)
        f[2] *= side
        b[2] *= side
        self.a0, self.side, self.cfg = f, side, cfg
        self.L = float(np.linalg.norm(b - f))
        self.ax = (b - f) / self.L
        e1 = np.array([0.0, 1.0, 0.0]) - self.ax * self.ax[1]
        self.e1 = e1 / np.linalg.norm(e1)
        e2 = np.cross(self.ax, self.e1) * -1.0   # with ax ~ -x, e1 = +y: e2 = +z
        self.e2 = e2 / np.linalg.norm(e2) * side
        self.sp = None

    def coords(self, P):
        """(s, theta, r) of points P"""
        q = P - self.a0
        s = q @ self.ax
        rel = q - s[:, None] * self.ax
        return s, np.arctan2(rel @ self.e2, rel @ self.e1), np.linalg.norm(rel, axis=1)

    def radial(self, P):
        """Unit radial direction of points P (away from the axis)"""
        q = P - self.a0
        rel = q - (q @ self.ax)[:, None] * self.ax
        return rel / np.maximum(np.linalg.norm(rel, axis=1, keepdims=True), 1e-12)

    def fit(self, P, N, use, report, tag):
        """Robust penalised fit of R(s, theta) to the points `use` that face away from the axis"""
        c = self.cfg
        s, th, r = self.coords(P)
        fac = np.einsum("ij,ij->i", N, self.radial(P))
        d = use & (fac > c.get("fac", 0.3)) & (s > c["fit"][0]) & (s < c["fit"][1]) & (r > 0.3 * c["r0"]) & (r < 1.7 * c["r0"])
        self.sp = sr.Spline2(c["fit"][0] - 0.01, c["fit"][1] + 0.01, c["ku"], -np.pi, np.pi, c["kv"], periodic=True)
        rw = self.sp.fit(s[d], th[d], r[d], prior=np.clip(fac[d] * 2 - 0.5, 0.05, 1), lam=c["lam"])
        res = r[d] - self.sp(s[d], th[d])
        report.append("%-10s tube fit: %5d points, %.0f %% kept, residual p50 %.2f p95 %.2f mm" % (
            tag, int(d.sum()), 100 * np.mean(rw > 0.5), np.median(np.abs(res)) * 1e3,
            np.percentile(np.abs(res), 95) * 1e3))

    def f(self, P):
        """Signed distance-like value of the capped tube (negative inside)"""
        c = self.cfg
        s, th, r = self.coords(P)
        v = r - self.sp(np.clip(s, c["fit"][0], c["fit"][1]), th)
        v = smax(v, c["cap_front"][0] - s, c["cap_front"][1])
        return smax(v, s - c["cap_rear"][0], c["cap_rear"][1])


class Slab:
    """A wing or body round the nacelle: upper and lower height fields y(x, |z|), smooth max of the two
    half-spaces (rounded by `round` where they meet: the leading and trailing edges)"""

    def __init__(self, cfg, side):
        self.cfg, self.side = cfg, side
        self.up = self.lo = None

    def fit(self, P, N, use, report, tag):
        """Fit both sheets to the skin `use` in the box facing up or down"""
        c = self.cfg
        x0, x1, z0, z1, y0, y1 = c["box"]
        x, y, z = P[:, 0], P[:, 1], P[:, 2] * self.side
        inb = use & (x > x0) & (x < x1) & (z > z0) & (z < z1) & (y > y0) & (y < y1)
        out = []
        for sgn in (1, -1):
            d = inb & (N[:, 1] * sgn > 0.55)
            if c.get("sheets", "both") != "both" and (c["sheets"] == "up") != (sgn > 0):
                out.append(None)
                continue
            sp = sr.Spline2(x0, x1, c["kx"], z0, z1, c["kz"])
            rw = sp.fit(x[d], z[d], y[d], prior=np.clip(np.abs(N[d, 1]) * 2 - 1.0, 0.05, 1), lam=c["lam"])
            res = y[d] - sp(x[d], z[d])
            out.append(sp)
            report.append("%-10s slab %s: %5d points, %.0f %% kept, residual p50 %.2f p95 %.2f mm" % (
                tag, "up" if sgn > 0 else "lo", int(d.sum()), 100 * np.mean(rw > 0.5),
                np.median(np.abs(res)) * 1e3, np.percentile(np.abs(res), 95) * 1e3))
        self.up, self.lo = out

    def f(self, P):
        """Signed vertical distance to the slab (negative inside)"""
        x0, x1, z0, z1 = self.cfg["box"][:4]
        x = np.clip(P[:, 0], x0, x1)
        z = np.clip(P[:, 2] * self.side, z0, z1)
        v = None
        if self.up is not None:
            v = P[:, 1] - self.up(x, z)
        if self.lo is not None:
            w = self.lo(x, z) - P[:, 1]
            v = w if v is None else smax(v, w, self.cfg.get("round", 0.002))
        # the leading and trailing edges in planform (|z|, x) points, rounded by le_r / te_r
        zs = P[:, 2] * self.side
        if "le" in self.cfg:
            le = np.array(self.cfg["le"], float)
            v = smax(v, P[:, 0] - np.interp(zs, le[:, 0], le[:, 1], left=None, right=None), self.cfg["le_r"])
        if "te" in self.cfg:
            te = np.array(self.cfg["te"], float)
            v = smax(v, np.interp(zs, te[:, 0], te[:, 1]) - P[:, 0], self.cfg["te_r"])
        return v


class Sheet:
    """A smooth patch over a concave junction that is neither tube nor slab (Грач-2 under its intake): a penalised
    height field h(a, b) over a plane through the region's box centre with normal `n` (right side; mirrored),
    fitted robustly to the skin in the box that faces that way. Coarse knots and the penalty round the corner
    of the junction into a fillet; the torn fringes are outliers of the fit."""

    def __init__(self, cfg, box, side):
        n = np.array(cfg["n"], float)
        n[2] *= side
        self.n = n / np.linalg.norm(n)
        x0, x1, z0, z1, y0, y1 = box
        self.o = np.array([(x0 + x1) / 2, (y0 + y1) / 2, side * (z0 + z1) / 2])
        u = np.array([1.0, 0.0, 0.0]) - self.n * self.n[0]
        self.u = u / np.linalg.norm(u)
        self.v = np.cross(self.n, self.u)
        self.cfg, self.sp, self.lim = cfg, None, None

    def coords(self, P):
        """(a, b, h) of points P in the sheet's frame"""
        q = P - self.o
        return q @ self.u, q @ self.v, q @ self.n

    def fit(self, P, N, use, report, tag):
        """Robust penalised fit to the points `use` that face along n"""
        c = self.cfg
        a, b, h = self.coords(P)
        fac = N @ self.n
        d = use & (fac > c.get("fac", 0.0))
        self.lim = (a[d].min(), a[d].max(), b[d].min(), b[d].max())
        self.sp = sr.Spline2(self.lim[0], self.lim[1], c["kk"], self.lim[2], self.lim[3], c["kk"])
        rw = self.sp.fit(a[d], b[d], h[d], prior=np.clip(fac[d] + 0.3, 0.05, 1), lam=c["lam"])
        res = h[d] - self.sp(a[d], b[d])
        report.append("%-10s sheet fit: %5d points, %.0f %% kept, residual p50 %.2f p95 %.2f mm" % (
            tag, int(d.sum()), 100 * np.mean(rw > 0.5), np.median(np.abs(res)) * 1e3,
            np.percentile(np.abs(res), 95) * 1e3))

    def f(self, P):
        """Signed height over the sheet (negative inside the body)"""
        a, b, h = self.coords(P)
        return h - self.sp(np.clip(a, self.lim[0], self.lim[1]), np.clip(b, self.lim[2], self.lim[3]))


class Region:
    """One nacelle with its slab (or one junction sheet) on one side: fitted parts and the implicit surface f"""

    def __init__(self, cfg, side):
        self.cfg, self.side = cfg, side
        self.tag = "%s%s" % (cfg["name"], "R" if side > 0 else "L")
        self.sheet = Sheet(cfg["sheet"], cfg["box"], side) if "sheet" in cfg else None
        self.tube = Tube(cfg["tube"], side) if "tube" in cfg else None
        self.slab = Slab(cfg["slab"], side) if "slab" in cfg else None

    def fit(self, P, N, free, report):
        """Tube and slab fitted in turn, each without the skin near the other's surface (or the sheet alone)"""
        if self.sheet is not None:
            self.sheet.fit(P, N, free & self.in_box(P, 0.004), report, self.tag)
            return
        use_t = free & self.in_box(P, 0.02)
        self.tube.fit(P, N, use_t, report, self.tag)
        if self.slab is None:
            return
        for _ in range(2):
            ex = self.cfg.get("excl", EXCL)
            self.slab.fit(P, N, free & (self.tube.f(P) > ex), report, self.tag)
            self.tube.fit(P, N, use_t & (np.abs(self.slab.f(P)) > ex), report, self.tag)

    def in_box(self, P, pad=0.0):
        """Points inside the region's box (padded)"""
        x0, x1, z0, z1, y0, y1 = self.cfg["box"]
        z = P[:, 2] * self.side
        return ((P[:, 0] > x0 - pad) & (P[:, 0] < x1 + pad) & (z > z0 - pad) & (z < z1 + pad)
                & (P[:, 1] > y0 - pad) & (P[:, 1] < y1 + pad))

    def box_weight(self, P):
        """1 inside the box, fading to 0 over 8 mm outside it"""
        x0, x1, z0, z1, y0, y1 = self.cfg["box"]
        z = P[:, 2] * self.side
        w = sr.smoothstep(x0 - 0.008, x0, P[:, 0]) * (1 - sr.smoothstep(x1, x1 + 0.008, P[:, 0]))
        w *= sr.smoothstep(z0 - 0.008, z0, z) * (1 - sr.smoothstep(z1, z1 + 0.008, z))
        return w * sr.smoothstep(y0 - 0.008, y0, P[:, 1]) * (1 - sr.smoothstep(y1, y1 + 0.008, P[:, 1]))

    def f(self, P):
        """The implicit surface: smooth union of the tube and the slab (or the sheet)"""
        if self.sheet is not None:
            return self.sheet.f(P)
        ft = self.tube.f(P)
        if self.slab is None:
            return ft
        return smin(ft, self.slab.f(P), self.cfg["k"])

    def grad(self, P):
        """Gradient of f (central differences)"""
        g = np.zeros_like(P)
        for i in range(3):
            d = np.zeros(3)
            d[i] = H
            g[:, i] = (self.f(P + d) - self.f(P - d)) / (2 * H)
        return g

    def weight(self, P):
        """How much of the region's surface a point belongs to: 1 on the nacelle and the fillet, fading out over
        the slab past the fillet and outside the box"""
        w = self.box_weight(P)
        for x0, x1, z0, z1, y0, y1 in self.cfg.get("keep", []):
            z = P[:, 2] * self.side
            inside = (sr.smoothstep(x0 - 0.006, x0, P[:, 0]) * (1 - sr.smoothstep(x1, x1 + 0.006, P[:, 0]))
                      * sr.smoothstep(z0 - 0.006, z0, z) * (1 - sr.smoothstep(z1, z1 + 0.006, z))
                      * sr.smoothstep(y0 - 0.006, y0, P[:, 1]) * (1 - sr.smoothstep(y1, y1 + 0.006, P[:, 1])))
            w = w * (1 - inside)
        if self.slab is not None:
            dd = self.tube.f(P) - self.slab.f(P) - self.cfg["k"]
            w = w * (1 - sr.smoothstep(FADE[0], FADE[1], dd))
        return w

    def project(self, P, iters=8):
        """Points moved onto f = 0 along the gradient (Newton, steps clipped to 4 mm)"""
        Q = P.copy()
        for _ in range(iters):
            v = self.f(Q)
            g = self.grad(Q)
            st = -(v / np.maximum((g * g).sum(1), 1e-12))[:, None] * g
            ln = np.linalg.norm(st, axis=1, keepdims=True)
            Q += st * np.minimum(1.0, 0.004 / np.maximum(ln, 1e-12))
        return Q


def weld(P, T):
    """Welded vertex ids (by position), welded positions and faces"""
    _, first, wid = np.unique(np.round(P / 1e-7).astype(np.int64), axis=0, return_index=True, return_inverse=True)
    wid = wid.reshape(-1)
    return wid, P[first].copy(), wid[T]


def adjacency(F, n):
    """Symmetric 0/1 adjacency of a face list"""
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    A = coo_matrix((np.ones(2 * len(e)), (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    return A


def face_normal_avg(W, F, ref):
    """Area-weighted vertex normals, faces turned to agree with the reference normals"""
    return sr.vertex_normals(W, F, ref)


def rebuild_geometry(m, key, report):
    """Fit every region, project and relax the skin; returns a dict with the main skin's arrays and the per-vertex
    region weight (welded)"""
    g = m.g
    j = g.j
    mesh = j["meshes"][j["nodes"][0]["mesh"]]
    p0 = mesh["primitives"][0]
    ai = p0["attributes"]
    e = m.acc[ai["POSITION"]]
    P = e["P"].copy()
    N = e["N"].copy()
    UV = g.accessor(ai["TEXCOORD_0"]).astype(np.float64)
    T0 = g.accessor(p0["indices"]).reshape(-1, 3).astype(np.int64)
    Tg = np.vstack([t for t, mt in zip(e["tris"], e["tri_mats"]) if mt == "glass"] or [np.zeros((0, 3), np.int64)])
    wid, W0, F = weld(P, T0)
    nw = len(W0)
    Nw = np.zeros((nw, 3))
    np.add.at(Nw, wid, N)
    Nw /= np.maximum(np.linalg.norm(Nw, axis=1, keepdims=True), 1e-12)
    Nw = face_normal_avg(W0, F, Nw)
    # parts that keep their place: every other node (slats, flaps, bay doors), the wells and the canopy glass
    others = [m.acc[a]["P"] for a in m.acc if a != ai["POSITION"]]
    if len(Tg):
        others.append(P[np.unique(Tg)])
    dist = cKDTree(np.vstack(others)).query(W0)[0] if others else np.full(nw, 1.0)
    free_w = sr.smoothstep(SKIP_NEAR_PARTS[0], SKIP_NEAR_PARTS[1], dist)
    if key in KEEP_UV:
        px = UV * np.array(KEEP_UV[key]["size"])
        kept = np.zeros(len(P), bool)
        for x0, y0, x1, y1 in KEEP_UV[key]["rects"]:
            kept |= (px[:, 0] >= x0) & (px[:, 0] <= x1) & (px[:, 1] >= y0) & (px[:, 1] <= y1)
        kd = cKDTree(W0[np.unique(wid[kept])]).query(W0)[0]
        free_w *= sr.smoothstep(KEEP_UV[key]["near"][0], KEEP_UV[key]["near"][1], kd)
        report.append("kept by UV island: %d skin vertices" % int(kept.sum()))
    regs = []
    for cfg in REGIONS[key]:
        for side in (1, -1):
            r = Region(cfg, side)
            r.fit(W0, Nw, free_w > 0.5, report)
            regs.append(r)
    # per vertex: the region with the largest weight
    wts = np.stack([r.weight(W0) for r in regs], 1)
    owner = np.argmax(wts, 1)
    inskin = np.zeros(nw, bool)
    inskin[F.reshape(-1)] = True
    w = wts[np.arange(nw), owner] * free_w * inskin
    gate = np.ones(nw)
    tgt = W0.copy()
    for k, r in enumerate(regs):
        sel = (owner == k) & (w > 0)
        if not sel.any():
            continue
        fv = np.abs(r.f(W0[sel]))
        tgt[sel] = r.project(W0[sel])
        # a point the projection carries further than the gate is another part, or f is ill-posed there
        fv = np.maximum(fv, np.linalg.norm(tgt[sel] - W0[sel], axis=1))
        gt = r.cfg.get("gate", GATE)
        gate[sel] = 1 - sr.smoothstep(gt[0], gt[1], fv)
    w = w * gate
    W = W0 + w[:, None] * (tgt - W0)
    # tangential relaxation of the core (w ~ 1) and projection back onto f
    A = adjacency(F, nw)
    deg = np.maximum(np.asarray(A.sum(1)).ravel(), 1)
    core = w > 0.98
    for _ in range(RELAX):
        L = (A @ W) / deg[:, None] - W
        for k, r in enumerate(regs):
            sel = core & (owner == k)
            if not sel.any():
                continue
            gr = r.grad(W[sel])
            gr /= np.maximum(np.linalg.norm(gr, axis=1, keepdims=True), 1e-12)
            Lt = L[sel] - np.einsum("ij,ij->i", L[sel], gr)[:, None] * gr
            W[sel] = r.project(W[sel] + 0.5 * Lt, iters=4)
    # normals: the gradient of f, blended with the old normal by the weight
    Nn = Nw.copy()
    for k, r in enumerate(regs):
        sel = (owner == k) & (w > 0)
        if not sel.any():
            continue
        gr = r.grad(W[sel])
        gr /= np.maximum(np.linalg.norm(gr, axis=1, keepdims=True), 1e-12)
        gr *= np.sign(np.einsum("ij,ij->i", gr, Nw[sel]) + 1e-9)[:, None]
        ww = w[sel, None]
        nb = (1 - ww) * Nw[sel] + ww * gr
        Nn[sel] = nb / np.maximum(np.linalg.norm(nb, axis=1, keepdims=True), 1e-12)
    mv = np.linalg.norm(W - W0, axis=1)
    report.append("rebuilt %d skin vertices (%d core), move p95 %.2f max %.2f mm" % (
        int((w > 1e-3).sum()), int(core.sum()), np.percentile(mv[w > 1e-3], 95) * 1e3, mv.max() * 1e3))
    # faces turned over by the rebuild (against the gradient)
    fn = np.cross(W[F[:, 1]] - W[F[:, 0]], W[F[:, 2]] - W[F[:, 0]])
    flip = (np.einsum("ij,ij->i", fn, Nn[F].sum(1)) < 0) & (w[F].min(1) > 0.5)
    report.append("faces against the surface normal in the region: %d" % int(flip.sum()))
    return {"P": P, "N": N, "UV": UV, "T0": T0, "wid": wid, "W0": W0, "W": W, "F": F, "Nw": Nw, "Nn": Nn, "w": w,
            "owner": owner, "regs": regs, "ai": ai, "p0": p0, "key": key}


def owner_of(geo, Q):
    """Region index and weight of points Q: those of the nearest welded vertex of the rebuilt skin"""
    _, nn = cKDTree(geo["W"]).query(Q)
    return geo["owner"][nn], geo["w"][nn]


def relax_project(geo, V, F, move, rounds):
    """Tangential relaxation of the vertices `move` of mesh (V, F), each projected back onto its region's f"""
    own, _ = owner_of(geo, V)
    A = adjacency(F, len(V))
    deg = np.maximum(np.asarray(A.sum(1)).ravel(), 1)
    for _ in range(rounds):
        L = (A @ V) / deg[:, None] - V
        for k, r in enumerate(geo["regs"]):
            sel = move & (own == k)
            if not sel.any():
                continue
            gr = r.grad(V[sel])
            gr /= np.maximum(np.linalg.norm(gr, axis=1, keepdims=True), 1e-12)
            Lt = L[sel] - np.einsum("ij,ij->i", L[sel], gr)[:, None] * gr
            V[sel] = r.project(V[sel] + 0.5 * Lt, iters=4)
    return V


def remesh_region(geo, report):
    """The region as a new mesh: faces of the old skin with any rebuilt corner; the core (every corner fully
    rebuilt) remeshed isotropically (MeshLab, the faces round it frozen so the border stays the old skin's) and
    projected onto f again. Returns region vertices, faces, weights, owners, normals and the mask of old faces
    it replaces."""
    import pymeshlab
    W, F, w = geo["W"], geo["F"], geo["w"].copy()
    fr = (w[F].max(1) > 1e-4) & (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    outside = np.zeros(len(W), bool)
    outside[F[~fr].reshape(-1)] = True
    w[outside] = 0.0          # the border is the old skin's, to the bit
    used = np.unique(F[fr])
    loc = np.full(len(W), -1)
    loc[used] = np.arange(len(used))
    V = W[used].copy()
    V[outside[used]] = geo["W0"][used][outside[used]]
    Fr = loc[F[fr]]
    wl = w[used]
    fc = wl[Fr].min(1) > 0.98
    el = np.linalg.norm(V[Fr[fc]][:, [1, 2, 0]] - V[Fr[fc]], axis=2).mean()
    tl = min(TARGET_EDGE, el)
    for it in range(2):
        ms = pymeshlab.MeshSet()
        ms.add_mesh(pymeshlab.Mesh(V, Fr, f_scalar_array=fc.astype(np.float64)))
        ms.compute_selection_by_condition_per_face(condselect="fq > 0.5")
        ms.meshing_isotropic_explicit_remeshing(iterations=4, selectedonly=True, targetlen=pymeshlab.PureValue(tl),
                                                featuredeg=70, checksurfdist=False, reprojectflag=True)
        mm = ms.current_mesh()
        V2 = mm.vertex_matrix().astype(np.float64)
        F2 = mm.face_matrix().astype(np.int64)
        fsel = mm.face_selection_array().astype(bool)
        # vertices of frozen faces keep their place and weight; the rest are core, back onto f
        frozen = np.zeros(len(V2), bool)
        frozen[F2[~fsel].reshape(-1)] = True
        _, nn = cKDTree(V).query(V2)
        w2 = np.where(frozen, wl[nn], 1.0)
        mv = ~frozen
        own, _ = owner_of(geo, V2)
        for k, r in enumerate(geo["regs"]):
            sel = mv & (own == k)
            if sel.any():
                V2[sel] = r.project(V2[sel])
        V2 = relax_project(geo, V2, F2, mv, 6)
        V, Fr, wl, fc = V2, F2, w2, fsel
    report.append("remeshed the core: %d faces, edge %.2f mm (old %.2f mm); region %d faces in all" % (
        int(fc.sum()), tl * 1e3, el * 1e3, len(Fr)))
    own, _ = owner_of(geo, V)
    # normals: gradient of f on the rebuilt skin, the old normal under the faded part (the weight)
    _, nn = cKDTree(geo["W"]).query(V)
    No = geo["Nw"][nn]
    Nn = No.copy()
    for k, r in enumerate(geo["regs"]):
        sel = (own == k) & (wl > 0)
        if not sel.any():
            continue
        gr = r.grad(V[sel])
        gr /= np.maximum(np.linalg.norm(gr, axis=1, keepdims=True), 1e-12)
        gr *= np.sign(np.einsum("ij,ij->i", gr, No[sel]) + 1e-9)[:, None]
        nb = (1 - wl[sel, None]) * No[sel] + wl[sel, None] * gr
        Nn[sel] = nb / np.maximum(np.linalg.norm(nb, axis=1, keepdims=True), 1e-12)
    # faces wound against their normals are turned (MeshLab keeps winding; the old skin has a few odd ones)
    fn = np.cross(V[Fr[:, 1]] - V[Fr[:, 0]], V[Fr[:, 2]] - V[Fr[:, 0]])
    bad = np.einsum("ij,ij->i", fn, Nn[Fr].sum(1)) < 0
    Fr[bad] = Fr[bad][:, [0, 2, 1]]
    report.append("faces turned to their normals: %d" % int(bad.sum()))
    # per vertex: fillet share (the new skin is concave there by design) and the protected front ring
    shade = np.zeros((len(V), 2))
    for k, r in enumerate(geo["regs"]):
        sel = own == k
        if not sel.any():
            continue
        if r.slab is not None:
            dd = np.abs(r.tube.f(V[sel]) - r.slab.f(V[sel]))
            shade[sel, 0] = 1 - sr.smoothstep(0.6 * r.cfg["k"], 1.5 * r.cfg["k"], dd)
        if r.tube is not None:
            s_, _, _ = r.tube.coords(V[sel])
            c0 = r.tube.cfg["cap_front"][0] + r.tube.cfg.get("front_keep", -1.0)
            shade[sel, 1] = 1 - sr.smoothstep(c0, c0 + 0.006, s_)
    return {"V": V, "F": Fr, "w": wl, "own": own, "N": Nn, "fr": fr, "shade": shade}


def dent_report(geo, reg, report):
    """Dent depth (height over a robust local quadric, skin_refit.dent_metric) of each region's rebuilt skin,
    old skin before and new skin after"""
    W0, F = geo["W0"], geo["F"]
    N0 = sr.vertex_normals(W0, F, geo["Nw"])
    for k, r in enumerate(geo["regs"]):
        pick0 = (geo["owner"] == k) & (geo["w"] > 0.9)
        pick1 = (reg["own"] == k) & (reg["w"] > 0.9)
        if pick0.sum() < 20 or pick1.sum() < 20:
            continue
        d0 = np.abs(sr.dent_metric(W0, N0, pick0))[pick0]
        d1 = np.abs(sr.dent_metric(reg["V"], reg["N"], pick1))[pick1]
        report.append("%-10s dent p95 %.2f -> %.2f mm, p99 %.2f -> %.2f mm, max %.2f -> %.2f mm (%d -> %d vertices)" % (
            r.tag, np.percentile(d0, 95) * 1e3, np.percentile(d1, 95) * 1e3, np.percentile(d0, 99) * 1e3,
            np.percentile(d1, 99) * 1e3, d0.max() * 1e3, d1.max() * 1e3, int(pick0.sum()), int(pick1.sum())))


def unwrap(V, F, margin):
    """Blender Smart UV Project of one mesh, packed into the unit square; per-corner UVs (len(F), 3, 2)"""
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    me = bpy.data.meshes.new("region")
    me.from_pydata([tuple(v) for v in V], [], [tuple(int(i) for i in f) for f in F])
    me.update()
    ob = bpy.data.objects.new("region", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=np.radians(66.0), island_margin=0.0, area_weight=0.0, correct_aspect=True,
                             scale_to_bounds=False)
    try:
        bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, rotate_method="ANY", scale=True,
                                merge_overlap=False, margin_method="FRACTION", margin=margin, shape_method="CONCAVE")
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = np.zeros(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 3, 2)
    order = np.zeros(len(me.polygons), np.int64)
    me.polygons.foreach_get("loop_start", order)
    out = uv.reshape(-1, 2)[order[:, None] + np.arange(3)[None, :]]
    out[..., 1] = 1.0 - out[..., 1]       # Blender v up -> glTF v down
    return out


def coverage_of(g, keep_faces, size):
    """UV coverage at size x size of every textured primitive, with the main skin's prim 0 limited to keep_faces"""
    from PIL import ImageDraw
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    for mi, mh in enumerate(g.j["meshes"]):
        for pi, pr in enumerate(mh["primitives"]):
            if "TEXCOORD_0" not in pr["attributes"]:
                continue
            uv = g.accessor(pr["attributes"]["TEXCOORD_0"]) * size
            T = g.accessor(pr["indices"]).reshape(-1, 3)
            if mi == g.j["nodes"][0]["mesh"] and pi == 0:
                T = keep_faces
            for t in T:
                d.polygon([tuple(uv[t[0]]), tuple(uv[t[1]]), tuple(uv[t[2]])], fill=255)
    return np.asarray(im) > 0


def charts(F, uvc):
    """UV charts of faces F with per-corner UVs uvc: connected through shared corners (same vertex, same UV);
    returns a chart id per face"""
    from scipy.sparse.csgraph import connected_components
    key = np.concatenate([F.reshape(-1, 1).astype(np.float64), np.round(uvc.reshape(-1, 2) * 1e6)], 1)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1, 3)
    n = int(inv.max()) + 1
    e = np.concatenate([inv[:, [0, 1]], inv[:, [1, 2]]])
    _, lab = connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)), directed=False)
    return lab[inv[:, 0]]


def place_charts(F, cuv, groups, cov, density, report):
    """Every UV chart of the rebuilt faces placed on its own in free atlas space (its bounding box, turned a
    quarter when that fits better), largest first, at the largest density step at which all of them find room.
    Returns the per-corner UV in texels (len(F), 3, 2)."""
    from scipy.ndimage import binary_dilation
    occ0 = binary_dilation(cov, iterations=CHART_GAP)
    allf = np.concatenate([g["faces"] for g in groups])
    scale = np.zeros(len(F))
    for g in groups:
        scale[g["faces"]] = g["scale"]
    lab = charts(F[allf], cuv[allf])
    ids = np.unique(lab)
    for f in (1.0, 0.92, 0.85, 0.78, 0.72, 0.66, 0.6):
        occ = occ0.copy()
        out = np.zeros((len(F), 3, 2))
        info = []
        for c in ids:
            fs = allf[lab == c]
            info.append((fs, cuv[fs] * scale[fs][:, None, None] * density * f))
        info.sort(key=lambda t: -np.ptp(t[1][..., 0]) * np.ptp(t[1][..., 1]))
        ok = True
        for fs, u in info:
            lo = u.reshape(-1, 2).min(0)
            u = u - lo
            wh = np.ceil(u.reshape(-1, 2).max(0)).astype(int) + 2
            best = None
            for rot in (False, True):
                w, h = (wh[1], wh[0]) if rot else (wh[0], wh[1])
                pos = _free(occ, w + 2 * CHART_GAP, h + 2 * CHART_GAP)
                if pos is not None and (best is None or pos[0] + pos[1] * 0.01 < best[0][0] + best[0][1] * 0.01):
                    best = (pos, rot, w, h)
            if best is None:
                ok = False
                break
            (y0, x0), rot, w, h = best
            uu = u[..., ::-1] if rot else u
            out[fs] = uu + np.array([x0 + CHART_GAP + 1, y0 + CHART_GAP + 1])
            occ[y0:y0 + h + 2 * CHART_GAP, x0:x0 + w + 2 * CHART_GAP] = True
        if ok:
            report.append("UV: %d charts at %.0f %% of the skin's texel density" % (len(ids), 100 * f))
            return out
    raise SystemExit("no room in the atlas for the rebuilt skin")


def _free(occ, w, h):
    """Top-left (row, col) of a free w x h rectangle in the occupancy mask (topmost, then leftmost), or None"""
    H, W = occ.shape
    if w >= W or h >= H:
        return None
    S = np.zeros((H + 1, W + 1), np.int32)
    S[1:, 1:] = np.cumsum(np.cumsum(occ, 0, dtype=np.int32), 1, dtype=np.int32)
    tot = S[h:, w:] - S[:-h, w:] - S[h:, :-w] + S[:-h, :-w]
    ys, xs = np.nonzero(tot == 0)
    if not len(ys):
        return None
    k = np.argmin(ys + xs * 0.01)
    return int(ys[k]), int(xs[k])


def raster(uvpx, tris, cb, grow=1.0):
    """For every triangle (texel-space corners), call cb(tri index, rows, cols, barycentrics) for the texels whose
    centres lie inside it or within `grow` texels of its edges (conservative, so the islands' border texels the
    coverage mask counts are baked too; barycentrics clamped onto the triangle)"""
    for k, t in enumerate(tris):
        p = uvpx[k]
        x0, y0 = np.floor(p.min(0) - grow).astype(int)
        x1, y1 = np.ceil(p.max(0) + grow).astype(int)
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a, b, c = p
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        l2 = 1 - l0 - l1
        # barycentric -> distance to the opposite edge in texels
        e0, e1, e2 = np.linalg.norm(b - c), np.linalg.norm(c - a), np.linalg.norm(a - b)
        ar = abs(den)
        m = (l0 * ar / max(e0, 1e-9) >= -grow) & (l1 * ar / max(e1, 1e-9) >= -grow) & (l2 * ar / max(e2, 1e-9) >= -grow)
        if m.any():
            L = np.clip(np.stack([l0[m], l1[m], l2[m]], 1), 0, None)
            L /= np.maximum(L.sum(1, keepdims=True), 1e-12)
            cb(k, np.floor(ys[m]).astype(int), np.floor(xs[m]).astype(int), L)


def bilinear(img, u, v):
    """Bilinear samples of img (H, W, C) at glTF UV (u right, v down)"""
    H, Wd = img.shape[:2]
    x = np.clip(u * Wd - 0.5, 0, Wd - 1.001)
    y = np.clip(v * H - 0.5, 0, H - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def old_concavity(geo):
    """Per welded vertex of the old skin: how far it lies under the mean of its neighbours along its normal
    (positive in a dent or a crease), averaged over two rings"""
    W0, F, Nw = geo["W0"], geo["F"], geo["Nw"]
    A = adjacency(F, len(W0))
    deg = np.maximum(np.asarray(A.sum(1)).ravel(), 1)
    c = np.einsum("ij,ij->i", (A @ W0) / deg[:, None] - W0, Nw)
    for _ in range(2):
        c = 0.5 * c + 0.5 * (A @ c) / deg
    return c


def bake(geo, reg, tuv, groups, col, orm, report):
    """Projection bake of the old paint and ORM onto the rebuilt faces' new UV islands (in place in col and orm,
    orm at the colour map's size), with the dent shading evened inside each camouflage tone"""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    from scipy.ndimage import gaussian_filter

    import tex_clean as tc
    P0, T0, UV0 = geo["P"], geo["T0"], geo["UV"]
    bvh = BVHTree.FromPolygons([tuple(v) for v in P0], [tuple(int(i) for i in t) for t in T0], all_triangles=True)
    V, F, Nn, wv, sh = reg["V"], reg["F"], reg["N"], reg["w"], reg["shade"]
    conc = old_concavity(geo)
    colf = col.astype(np.float32)
    ormf = orm.astype(np.float32)
    for gr in groups:
        fids = gr["faces"]
        px = tuv[fids]
        x0, y0 = np.floor(px.reshape(-1, 2).min(0)).astype(int) - 4
        sx, sy = np.ceil(px.reshape(-1, 2).max(0)).astype(int) - np.array([x0, y0]) + 6
        Q, Nq, Wq, Sq, R, C = [], [], [], [], [], []

        def cb(k, rr, cc, bc):
            t = F[fids[k]]
            Q.append(bc @ V[t])
            Nq.append(bc @ Nn[t])
            Wq.append(bc @ wv[t])
            Sq.append(bc @ sh[t])
            R.append(rr)
            C.append(cc)
        raster(px, fids, cb)
        Q = np.vstack(Q)
        Nq = np.vstack(Nq)
        Nq /= np.maximum(np.linalg.norm(Nq, axis=1, keepdims=True), 1e-12)
        Wq = np.concatenate(Wq)
        Sq = np.vstack(Sq)
        R = np.concatenate(R)
        C = np.concatenate(C)
        # old surface point under each texel: nearest hit along +-normal within 15 mm, else the nearest point
        hit = np.zeros((len(Q), 3))
        hf = np.zeros(len(Q), np.int64)
        miss = 0
        for i in range(len(Q)):
            q = Vector(Q[i])
            n = Vector(Nq[i])
            best = None
            for sgn in (1.0, -1.0):
                loc, _, fi, dist = bvh.ray_cast(q, n * sgn, RAY)
                if fi is not None and (best is None or dist < best[1]):
                    best = (loc, dist, fi)
            if best is None:
                loc, _, fi, _ = bvh.find_nearest(q)
                best = (loc, 0.0, fi)
                miss += 1
            hit[i] = best[0]
            hf[i] = best[2]
        t = T0[hf]
        a, b, c = P0[t[:, 0]], P0[t[:, 1]], P0[t[:, 2]]
        v0, v1, v2 = b - a, c - a, hit - a
        d00, d01, d11 = (v0 * v0).sum(1), (v0 * v1).sum(1), (v1 * v1).sum(1)
        d20, d21 = (v2 * v0).sum(1), (v2 * v1).sum(1)
        dn = np.where(np.abs(d00 * d11 - d01 * d01) < 1e-24, 1e-24, d00 * d11 - d01 * d01)
        l1 = np.clip((d11 * d20 - d01 * d21) / dn, 0, 1)
        l2 = np.clip((d00 * d21 - d01 * d20) / dn, 0, 1 - l1)
        hit_uv = (1 - l1 - l2)[:, None] * UV0[t[:, 0]] + l1[:, None] * UV0[t[:, 1]] + l2[:, None] * UV0[t[:, 2]]
        wt = geo["wid"][t]
        cq = (1 - l1 - l2) * conc[wt[:, 0]] + l1 * conc[wt[:, 1]] + l2 * conc[wt[:, 2]]
        rgb = bilinear(colf, hit_uv[:, 0], hit_uv[:, 1])
        om = bilinear(ormf, hit_uv[:, 0], hit_uv[:, 1])
        # dent shading: inside each tone, luminance over its local mean (4 texels) times the tone's median level
        lab = tc.lab(rgb / 255.0)
        C4 = tc.kmeans(lab[::7].copy(), TONES)
        lab_i = ((lab[:, None, :] - C4[None]) ** 2).sum(-1).argmin(1)
        box = np.zeros((sy, sx), np.float32)
        lum = rgb @ np.array([0.2126, 0.7152, 0.0722]) + 1.0
        gain = np.ones(len(Q))
        ogain = np.ones(len(Q))
        rr, cc = R - y0, C - x0
        for k in range(TONES):
            m = lab_i == k
            if m.sum() < 50:
                continue
            msk = box.copy()
            msk[rr[m], cc[m]] = 1
            val = box.copy()
            val[rr[m], cc[m]] = lum[m]
            oval = box.copy()
            oval[rr[m], cc[m]] = om[m, 0]
            den = gaussian_filter(msk, FLAT_SIGMA) + 1e-6
            lp = gaussian_filter(val, FLAT_SIGMA) / den
            olp = gaussian_filter(oval, FLAT_SIGMA) / den
            gain[m] = np.clip(np.median(lum[m]) / np.maximum(lp[rr[m], cc[m]], 1.0), 1 - FLAT_CLIP, 1 + FLAT_CLIP)
            ogain[m] = np.clip(np.median(om[m, 0]) / np.maximum(olp[rr[m], cc[m]], 1.0), 1 - FLAT_CLIP, 1 + FLAT_CLIP)
        g = 1 + (gain - 1) * Wq
        og = 1 + (ogain - 1) * Wq
        rgb = rgb * g[:, None]
        om[:, 0] *= og

        # baked crease shading: where the old skin was concave (a dent, a crumpled crease) or the new skin is a
        # fillet, the paint goes to the region's own paint colour times the fine detail (panel lines, rivets);
        # metal (exhaust) and the dark front ring are left as they are
        def grid(vals, sig):
            a_ = box.copy()
            m_ = box.copy()
            a_[rr, cc] = vals
            m_[rr, cc] = 1
            return (gaussian_filter(a_, sig) / (gaussian_filter(m_, sig) + 1e-6))[rr, cc]
        lum = rgb @ np.array([0.2126, 0.7152, 0.0722]) + 1.0
        med = np.median(lum)
        paint = (lum > 0.8 * med) & (lum < 1.25 * med)
        prgb = np.median(rgb[paint], 0)
        porm = np.median(om[paint], 0)
        fine = np.clip(lum / np.maximum(grid(lum, FINE_SIGMA), 1.0), 0.75, 1.25)
        # the generator baked dark metal streaks into the creases: metal is kept only off the fillet (exhausts)
        fil = np.clip(grid(Sq[:, 0], 3.0), 0, 1)
        cw = np.maximum(sr.smoothstep(CONC[0], CONC[1], cq), Sq[:, 0])
        inex = np.zeros(len(Q), bool)
        for x0, x1, z0, z1, y0, y1 in EXHAUST_BOXES.get(geo["key"], []):
            az = np.abs(Q[:, 2])
            inex |= (Q[:, 0] > x0) & (Q[:, 0] < x1) & (az > z0) & (az < z1) & (Q[:, 1] > y0) & (Q[:, 1] < y1)
        keep_metal = (om[:, 2] >= METAL_KEEP) & (fil < 0.3) & inex
        if gr["dark_out"]:
            # torn skin of the old intake left dark paint round the new ring: near-black texels are old duct
            cw = np.maximum(cw, 1 - sr.smoothstep(0.35 * med, 0.55 * med, grid(lum, 2.0)))
        cw = np.clip(grid(cw, 3.0), 0, 1) * Wq * (1 - Sq[:, 1]) * ~keep_metal
        rgb = rgb * (1 - cw[:, None]) + (prgb[None] * fine[:, None]) * cw[:, None]
        om = om * (1 - cw[:, None]) + porm[None] * cw[:, None]
        col[R, C] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)
        orm[R, C] = np.clip(om + 0.5, 0, 255).astype(np.uint8)
        report.append("%-10s crease shading evened on %.0f %% of the texels" % (gr["tag"], 100 * np.mean(cw > 0.5)))
        report.append("%-10s baked %d texels (%d off the old skin by more than RAY), tone gain p5..p95 %.2f..%.2f" % (
            gr["tag"], len(Q), miss, np.percentile(g, 5), np.percentile(g, 95)))


def repaint_shell(m, key, col, orm, report):
    """The kept intake's nacelle body (intake_rebuild.py: a dark wall just under the fitted cowl) shows through
    where the rebuilt junction skin lies a little lower than the cowl fit: its dark outward-facing faces round the
    intake (KEEP_UV "shell": axis (y, |z|), radius over rmin, x range) take the paint and ORM of the nearest skin
    outside the island, so what shows reads as skin, not as a torn black flap"""
    cfg = KEEP_UV.get(key, {}).get("shell")
    if cfg is None:
        return
    g = m.g
    j = g.j
    p0 = j["meshes"][j["nodes"][0]["mesh"]]["primitives"][0]
    ai = p0["attributes"]
    P = m.acc[ai["POSITION"]]["P"]
    UV = g.accessor(ai["TEXCOORD_0"]).astype(np.float64)
    T = g.accessor(p0["indices"]).reshape(-1, 3).astype(np.int64)
    S = col.shape[0]
    px = UV * np.array(KEEP_UV[key]["size"])
    isl = np.zeros(len(P), bool)
    for x0, y0, x1, y1 in KEEP_UV[key]["rects"]:
        isl |= (px[:, 0] >= x0) & (px[:, 0] <= x1) & (px[:, 1] >= y0) & (px[:, 1] <= y1)
    c = P[T].mean(1)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    uvc = np.clip((UV[T].mean(1) * S).astype(int), 0, S - 1)
    lum = col[uvc[:, 1], uvc[:, 0]] @ np.array([0.2126, 0.7152, 0.0722])
    skin_v = np.unique(T[~isl[T].any(1)])
    tree = cKDTree(P[skin_v])
    sv = np.clip((UV[skin_v] * S).astype(int), 0, S - 1)
    n = 0
    for side in (1, -1):
        ax = np.array([0.0, cfg["axis"][0], side * cfg["axis"][1]])
        rel = c - ax
        rel[:, 0] = 0
        r = np.linalg.norm(rel, axis=1)
        out = np.einsum("ij,ij->i", fn, rel / np.maximum(r[:, None], 1e-12))
        sel = (isl[T].all(1) & (lum < 40) & (out > 0.3) & (r > cfg["rmin"]) & (c[:, 0] > cfg["x"][0])
               & (c[:, 0] < cfg["x"][1]) & (c[:, 2] * side > 0))
        fids = np.nonzero(sel)[0]
        if not len(fids):
            continue
        _, nn = tree.query(c[fids], k=12)
        cc = sv[nn]
        rgb = np.median(col[cc[..., 1], cc[..., 0]].astype(np.float64), 1)
        om = np.median(orm[cc[..., 1], cc[..., 0]].astype(np.float64), 1)

        def cb(k, rr, cl, bc):
            col[rr % S, cl % S] = np.clip(rgb[k] + 0.5, 0, 255).astype(np.uint8)
            orm[rr % S, cl % S] = np.clip(om[k] + 0.5, 0, 255).astype(np.uint8)
        raster(UV[T[fids]] * S, T[fids], cb, grow=1.0)
        n += len(fids)
    report.append("intake body faces showing through, repainted as skin: %d" % n)


def skin_density(geo, T, S):
    """Median texel density of the old skin faces T (texels per model unit at S)"""
    P, UV = geo["P"], geo["UV"] * S
    a3 = np.linalg.norm(np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]]), axis=1) / 2
    d1, d2 = UV[T[:, 1]] - UV[T[:, 0]], UV[T[:, 2]] - UV[T[:, 0]]
    a2 = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]) / 2
    ok = a3 > 1e-12
    return float(np.median(np.sqrt(a2[ok] / a3[ok])))


def write_region(m, geo, reg, tuv, S, dst, report):
    """Main skin = the old faces outside the region + the rebuilt region with its own vertices (split along the
    UV seams of its islands); the canopy glass keeps its vertices"""
    g = m.g
    F = reg["F"]
    # per corner: texel-space UV -> glTF UV
    uvc = tuv / S
    key = np.concatenate([F.reshape(-1, 1).astype(np.float64), np.round(uvc.reshape(-1, 2) * S * 64)], 1)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    vi = F.reshape(-1)[first]
    Pr, Nr, UVr = reg["V"][vi], reg["N"][vi], uvc.reshape(-1, 2)[first]
    n0 = len(geo["P"])
    T = np.vstack([geo["T0"][~reg["fr"]], inv.reshape(-1, 3) + n0])
    P, N, UV = np.vstack([geo["P"], Pr]), np.vstack([geo["N"], Nr]), np.vstack([geo["UV"], UVr])
    P, N, UV, T = bridge_gaps(geo["key"], P, N, UV, T, report)
    e = m.acc[geo["ai"]["POSITION"]]
    put_vertices(g, e, geo["ai"], P, N, UV)
    g.set_indices(g.j["nodes"][0]["mesh"], 0, T)
    g.save(dst)
    report.append("main skin: %d old faces kept, %d rebuilt faces on %d new vertices" % (
        int((~reg["fr"]).sum()), len(F), len(Pr)))


def bridge_gaps(key, P, N, UV, T, report):
    """Close the see-through gaps between the skin and a kept part (KEEP_UV "bridge": largest gap): every open
    edge of the skin near the kept island's open rim gets a strip to that rim, sunk 0.5 mm under it, painted with
    the skin's own texels. The generator's torn skin round the Грач intakes left such gaps, black in the hangar."""
    cfg = KEEP_UV.get(key, {})
    if "bridge" not in cfg:
        return P, N, UV, T
    px = UV * np.array(cfg["size"])
    isl = np.zeros(len(P), bool)
    for x0, y0, x1, y1 in cfg["rects"]:
        isl |= (px[:, 0] >= x0) & (px[:, 0] <= x1) & (px[:, 1] >= y0) & (px[:, 1] <= y1)
    wid, W, F = weld(P, T)
    fisl = isl[T].all(1)
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    eo = np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]])   # the same edges on unwelded vertices
    fe = np.tile(np.arange(len(F)), 3)
    _, inv, cnt = np.unique(np.sort(e, 1), axis=0, return_inverse=True, return_counts=True)
    open_e = cnt[inv.reshape(-1)] == 1
    rim = np.unique(e[open_e & fisl[fe]])
    if not len(rim):
        return P, N, UV, T
    rim_tree = cKDTree(W[rim])
    nw = np.zeros((len(W), 3))
    np.add.at(nw, wid, N)
    nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-12)
    pick = np.nonzero(open_e & ~fisl[fe])[0]
    d, _ = rim_tree.query(W[e[pick]].reshape(-1, 3))
    d = d.reshape(-1, 2)
    pick = pick[(d.max(1) < cfg["bridge"]) & (d.max(1) > 3e-4)]
    if not len(pick):
        return P, N, UV, T
    a, b = eo[pick, 0], eo[pick, 1]
    ends = np.unique(np.r_[a, b])
    _, nn = rim_tree.query(W[wid[ends]])
    tgt = W[rim[nn]] - 0.0005 * nw[rim[nn]]
    n0 = len(P)
    newid = np.full(len(P), -1)
    newid[ends] = n0 + np.arange(len(ends))
    P = np.vstack([P, tgt])
    N = np.vstack([N, N[ends]])
    UV = np.vstack([UV, UV[ends]])
    # the skin face has a -> b; the strip runs b -> a so the winding agrees
    strip = np.vstack([np.stack([b, a, newid[a]], 1), np.stack([b, newid[a], newid[b]], 1)])
    report.append("gaps to the kept part bridged: %d open skin edges" % len(pick))
    return P, N, UV, np.vstack([T, strip])


def write_geo_only(m, geo, dst):
    """Debug output: moved positions and new normals with the old UV (no remesh, no new islands, no paint)"""
    P = geo["W"][geo["wid"]]
    N = geo["Nn"][geo["wid"]]
    e = m.acc[geo["ai"]["POSITION"]]
    put_vertices(m.g, e, geo["ai"], P, N, geo["UV"])
    m.g.save(dst)


def put_vertices(g, e, ai, P, N, UV):
    """Replace the main skin's vertex attributes (world positions back in the node's frame)"""
    Minv = np.linalg.inv(e["M"])
    loc = P @ Minv[:3, :3].T + Minv[:3, 3]
    nl = N @ e["M"][:3, :3]
    nl /= np.maximum(np.linalg.norm(nl, axis=1, keepdims=True), 1e-12)
    for key, arr in (("POSITION", loc), ("NORMAL", nl), ("TEXCOORD_0", UV)):
        acc = g.j["accessors"][ai[key]]
        a32 = np.ascontiguousarray(arr.astype(np.float32))
        while len(g.bin) % 4:
            g.bin.append(0)
        off = len(g.bin)
        g.bin += a32.tobytes()
        g.j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": int(a32.nbytes), "target": 34962})
        acc["bufferView"] = len(g.j["bufferViews"]) - 1
        acc.pop("byteOffset", None)
        acc["count"] = len(a32)
        if key == "POSITION":
            acc["min"] = [float(v) for v in a32.min(0)]
            acc["max"] = [float(v) for v in a32.max(0)]


def main() -> int:
    """Command line: rebuild the nacelle regions of one hangar plane"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    ap.add_argument("--maps", nargs=2)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--geo-only", action="store_true")
    a = ap.parse_args()
    rep = []
    m = pp.Model(a.src)
    geo = rebuild_geometry(m, a.key, rep)
    if a.geo_only:
        write_geo_only(m, geo, a.dst)
        print("\n".join(rep))
        return 0
    reg = remesh_region(geo, rep)
    if a.report:
        dent_report(geo, reg, rep)
    col = np.asarray(Image.open(a.maps[0]).convert("RGB")).copy()
    S = col.shape[0]
    orm_im = Image.open(a.maps[1]).convert("RGB")
    orm_size = orm_im.size
    orm = np.asarray(orm_im.resize((S, S), Image.BICUBIC)).copy()
    # UV: one square pack per region (the faces of one nacelle side), unwrapped in Blender
    fown = np.array([np.bincount(o, minlength=len(geo["regs"])).argmax() for o in reg["own"][reg["F"]]])
    cuv = np.zeros((len(reg["F"]), 3, 2))
    groups = []
    for k, r in enumerate(geo["regs"]):
        fids = np.nonzero(fown == k)[0]
        if not len(fids):
            continue
        used = np.unique(reg["F"][fids])
        loc = np.full(len(reg["V"]), -1)
        loc[used] = np.arange(len(used))
        uv = unwrap(reg["V"][used], loc[reg["F"][fids]], 0.006)
        cuv[fids] = uv
        V3 = reg["V"][reg["F"][fids]]
        a3 = np.linalg.norm(np.cross(V3[:, 1] - V3[:, 0], V3[:, 2] - V3[:, 0]), axis=1).sum() / 2
        d1, d2 = uv[:, 1] - uv[:, 0], uv[:, 2] - uv[:, 0]
        a2 = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]).sum() / 2
        groups.append({"tag": r.tag, "faces": fids, "scale": np.sqrt(a3 / a2), "dark_out": r.cfg.get("dark_out", False)})
    keep = geo["T0"][~reg["fr"]]
    cov = coverage_of(m.g, keep, S)
    density = skin_density(geo, keep, S)
    tuv = place_charts(reg["F"], cuv, groups, cov, density, rep)
    bake(geo, reg, tuv, groups, col, orm, rep)
    repaint_shell(m, a.key, col, orm, rep)
    write_region(m, geo, reg, tuv, S, a.dst, rep)
    Image.fromarray(col).save(a.maps[0], quality=95)
    Image.fromarray(orm).resize(orm_size, Image.LANCZOS).save(a.maps[1], quality=95)
    print("\n".join(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
