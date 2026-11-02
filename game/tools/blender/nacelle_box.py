"""Built box nacelles under the wing glove for «Кит» 2 (Kanta, 01.11: dented, lumpy skin on and round its engine
nacelles, dark dimples on the nacelle tops; skin_refit.py deepened the dimples, nacelle_rebuild.py gave a blunt bulb
at the nacelle front, a boxy shoulder into the wing and small holes by the bomb bay).

What the nacelle of this aircraft type looks like (walkaround photos and a three-view of the prototype; the notes
stay outside the repository): one box per side hung under the fixed wing glove, beside the fuselage belly with a
channel between them; wider than tall, flat vertical side walls, a flat bottom, rounded lower corners; the front of
the box is the intake: a rectangular opening split by a thin vertical plate, thin sharp lips, a dark duct with no
engine face; from above the glove stays smooth over the box, and only towards the glove's trailing edge does the
nacelle top rise out of it as a long low rounded fairing that runs back into the nozzle shroud.

Why a new tool: nacelle_rebuild.py moves the old skin onto a fitted surface. Where the new shape differs a lot from
the generator's (a box where there was a round tube, an intake where there was a closed pocket) the old triangles
have to travel far, crowd and fold, and an opening cannot be made at all. Here the nacelle is built outright and the
old skin only has to follow a smooth surface where it stays visible:

1. Nacelle (config NACELLES, model axes, right side; the left is mirrored): sections along x. In front of the morph
   the section is a box (inboard and outboard walls z_in, z_out, bottom y_b(x) with corner radii r_bi, r_bo, walls
   up to y_mid) under a half-ellipse cap up to y_top(x) (inside the glove at the front, the fairing hump further
   back); behind it the section morphs (matched by angle round the centre) into the round shroud in front of the
   kept nozzle. The outer loft is a structured grid (rows along x, columns by arc length round the section) with
   normals from the grid, its own UV chart (arc length round, length along). The front is the intake: a flat lip
   face from the outer section to the opening (a rounded rectangle inset by the lip thickness, its top just under
   the glove), the duct straight back `depth` to a dark end cap, a thin splitter plate in the middle. A flat ring at
   the rear closes the shroud onto the kept nozzle ring.
2. Old skin (the region box round each nacelle, fading out over `fade`; kept boxes, the nozzle's inside and the skin
   near slats, flaps, bay doors and wells stay put): every vertex is projected onto f = smin(slab, nacelle, k), where
   the slab is the glove and fuselage round the nacelle (upper and lower penalised height fields fitted robustly to
   the skin away from the old tube, cut by a planform polygon) and the nacelle is the signed distance to the built
   loft. The fillet k fades to 0 at the intake (the box meets the glove with a clean edge, as on the prototype). The
   region is relaxed, its core remeshed (MeshLab) and projected again. Faces left inside the built nacelle or lying
   on it beyond the fillet are dropped: there the built loft is the surface, the fillet runs out tangent onto it.
3. Paint: the rebuilt region and the built loft and lip get their own UV charts in free atlas space at the skin's
   texel density, projection-baked from the old surface with the generator's dent shading evened out
   (nacelle_rebuild.bake); the duct is light grey at the lip fading to near black, the splitter and cap dark.
   Livery.INTAKE_DUCTS keeps the duct's texture paint under every livery (--report prints the row).

  python3 -I nacelle_box.py <hangar.glb> <key> <out.glb> --maps <col.jpg> <orm.jpg> [--report]
The maps are rewritten in place (start from copies of the extracted maps), then tex_clean.py pads them.
Axes: glTF model space (nose +X, up +Y, right wing +Z), length 1. Needs numpy, scipy, Pillow, pymeshlab; bpy for the
unwrap and the bake."""
import argparse
import os
import sys

try:
    import bpy  # noqa: F401  first: its TBB must load before MeshLab's
except ImportError:
    bpy = None
import numpy as np
from PIL import Image
from scipy.interpolate import PchipInterpolator
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nacelle_rebuild as nr  # noqa: E402
import plane_polish as pp  # noqa: E402
import skin_refit as sr  # noqa: E402

Image.MAX_IMAGE_PIXELS = None

# Per plane, right side (mirrored), model units. nac: lip plane x at the box bottom and its rake (dx per unit of
# height, + leans the top back), rear end x of the built shroud, walls, corner radii, bottom y_b(x) and cap top
# y_top(x) as (x, value) knots (monotone cubic), y_mid where the walls meet the cap, the morph span into the round
# shroud (circle: centre y, |z|, radius), the shroud radius tapering to the nozzle exit (r_tail knots, so the rear
# face is a thin boat-tail lip, not a flat ring) and the inner radius of the rear ring; intake: lip thickness, opening top,
# top corner radius, duct depth, splitter half thickness; slab: data box (x0, x1, |z|0, |z|1), knot spacing, penalty,
# rounding of its edges, planform polygon (x, |z|) and the old tube left out of its data (axis y, |z|, radius, from
# x); region: box (x0, x1, |z|0, |z|1, y0, y1), fade, kept boxes, the nozzle's inside kept (behind x, within r of the
# shroud axis), fillet k and the length over which it grows from the lip; the strake box flattened into the slab.
NACELLES: dict = {
    "bomber_2": {
        "nac": {"x_lip": -0.112, "rake": 0.08, "x_end": -0.2742, "z_in": 0.037, "z_out": 0.104,
                "r_bi": 0.008, "r_bo": 0.012, "y_mid": -0.040,
                "y_b": [(-0.112, -0.066), (-0.185, -0.066), (-0.205, -0.0652), (-0.222, -0.0630)],
                "y_top": [(-0.112, -0.024), (-0.13, -0.012), (-0.15, 0.0), (-0.17, 0.0075), (-0.19, 0.0115),
                          (-0.21, 0.0132), (-0.222, 0.0135)],
                "morph": (-0.222, -0.252), "circle": (-0.0154, 0.0702, 0.0250), "ring_in": 0.0172,
            "r_tail": [(-0.256, 0.0250), (-0.266, 0.0236), (-0.2742, 0.0200)]},
        "intake": {"t": 0.0015, "y_ot": -0.0500, "r_top": 0.002, "depth": 0.03, "split": 0.0006},
        "slab": {"box": (-0.30, -0.05, 0.02, 0.17), "kx": 0.02, "kz": 0.015, "lam": (1.0, 1.0), "round": 0.003,
                 "plan_r": 0.005, "tube": (-0.022, 0.0705, 0.046, -0.096),
                 "plan": [(0.2, -0.05), (0.2, 0.30), (-0.187, 0.30), (-0.1815, 0.150), (-0.1855, 0.140),
                          (-0.193, 0.133), (-0.21, 0.126), (-0.224, 0.118), (-0.232, 0.108), (-0.236, 0.098),
                          (-0.236, 0.05), (-0.24, 0.034), (-0.30, 0.034), (-0.30, -0.05)]},
        "region": {"box": (-0.28, -0.074, 0.022, 0.16, -0.085, 0.035), "fade": 0.008,
                   "keep": [(-0.32, -0.233, 0.0, 0.034, -0.09, 0.05), (-0.32, -0.17, 0.152, 0.25, -0.09, 0.05)],
                   "nozzle": (-0.245, 0.019),
                   "k": 0.006, "k_grow": 0.025,
                   "strake": (-0.135, -0.07, 0.034, 0.058, -0.075, -0.046)},
    },
}
NC = 112             # columns round the built section
ROW = 0.0022         # row spacing of the built loft
NC_DENSE = 512       # columns of the dense loft behind the signed distance
ROW_DENSE = 0.0004   # its row spacing
GATE_FAR = 0.04      # a vertex the projection would carry further than this is left alone (another part)
RELAX = 10           # tangential relaxation rounds of the rebuilt region
TARGET_EDGE = 0.0025 # edge length of the remeshed core
DROP_IN = 0.0008     # a region face this far inside the built nacelle is dropped
DROP_ON = 0.0005     # ... or lying on it (within DROP_IN) this far past the fillet
SINK = 0.002         # kept vertices on the built nacelle past the fillet are sunk this deep into it
SPECK_WIN = 11       # neighbourhood (texels) of the bright-speck clean-up of the baked paint
SPECK_DL = 22        # ... a texel this much lighter (0..255 luminance) than its neighbourhood's median is a speck
BLOT_SIZE = 61       # dark-blot clean-up: dark features narrower than this (texels, ~2 cm) are blot candidates,
BLOT_DL = 18         # ... a blot this much darker (0..255 luminance) than the light level round it,
BLOT_AREA = (150, 6000)  # ... and of this size (texels; rivets are smaller, camouflage patches larger)
H = 1e-5             # finite-difference step of the gradient
DUCT_PAINT = ((0.0, 178.0), (0.003, 150.0), (0.008, 60.0), (0.016, 18.0), (1.0, 10.0))   # depth -> grey 0..255


def log(msg):
    """Progress line on stderr"""
    print(msg, file=sys.stderr, flush=True)


def sstep(a, b, x):
    """Hermite step from 0 at a to 1 at b (either order)"""
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def knots(pairs):
    """Monotone cubic through (x, value) pairs, held flat past both ends"""
    p = sorted(pairs)
    xs = np.array([a for a, _ in p])
    vs = np.array([b for _, b in p])
    f = PchipInterpolator(xs, vs, extrapolate=False)
    return lambda x: np.where(np.asarray(x) <= xs[0], vs[0], np.where(np.asarray(x) >= xs[-1], vs[-1],
                                                                      np.nan_to_num(f(np.clip(x, xs[0], xs[-1])))))


def resample_closed(Q, n):
    """n points spaced evenly by arc length round the closed polyline Q (first point kept)"""
    R = np.vstack([Q, Q[:1]])
    s = np.r_[0, np.cumsum(np.linalg.norm(np.diff(R, axis=0), axis=1))]
    t = np.linspace(0, s[-1], n + 1)[:-1]
    return np.stack([np.interp(t, s, R[:, 0]), np.interp(t, s, R[:, 1])], 1)


class Nacelle:
    """The built nacelle of one side: section loops along x, the dense loft behind its signed distance, the
    output meshes. Sections are (|z|, y) loops, counter-clockwise, starting inboard."""

    def __init__(self, cfg, side):
        self.c, self.i = cfg["nac"], cfg["intake"]
        self.side = side
        self.y_b = knots(self.c["y_b"])
        self.y_top = knots(self.c["y_top"])
        self.r_tail = knots(self.c.get("r_tail", [(0.0, self.c["circle"][2])]))

    def box_loop(self, x, n=1600):
        """Dense box-and-cap section at x"""
        c = self.c
        zi, zo, ym = c["z_in"], c["z_out"], c["y_mid"]
        yb, yt = float(self.y_b(x)), float(self.y_top(x))
        rbi, rbo = c["r_bi"], c["r_bo"]
        zm, a = (zi + zo) / 2, (zo - zi) / 2

        def arc(cz, cy, r, a0, a1, k=40):
            t = np.linspace(a0, a1, k)
            return np.stack([cz + r * np.cos(t), cy + r * np.sin(t)], 1)

        def line(p, q, k=40):
            t = np.linspace(0, 1, k)[:, None]
            return np.array(p)[None] * (1 - t) + np.array(q)[None] * t
        parts = [line((zi, ym), (zi, yb + rbi)), arc(zi + rbi, yb + rbi, rbi, np.pi, 1.5 * np.pi),
                 line((zi + rbi, yb), (zo - rbo, yb)), arc(zo - rbo, yb + rbo, rbo, 1.5 * np.pi, 2 * np.pi),
                 line((zo, yb + rbo), (zo, ym))]
        t = np.linspace(0, np.pi, 160)
        parts.append(np.stack([zm + a * np.cos(t), ym + (yt - ym) * np.sin(t)], 1))
        Q = np.vstack([p[:-1] for p in parts])
        return resample_closed(Q, n)

    def loop(self, x, n):
        """Section at x: n points by arc length from the inboard point at the centre's height"""
        c = self.c
        m = float(sstep(c["morph"][0], c["morph"][1], x))
        yc, zc, rc = c["circle"]
        K = 2048
        phi = np.pi + 2 * np.pi * np.arange(K) / K
        out = np.zeros((K, 2))
        if m < 1:
            B = self.box_loop(x)
            cb = np.array([(c["z_in"] + c["z_out"]) / 2, (float(self.y_b(x)) + float(self.y_top(x))) / 2])
            d = B - cb
            ang = np.arctan2(d[:, 1], d[:, 0])
            rb = np.interp(phi, ang, np.linalg.norm(d, axis=1), period=2 * np.pi)
            out += (1 - m) * (cb[None] + rb[:, None] * np.stack([np.cos(phi), np.sin(phi)], 1))
        if m > 0:
            rc = float(self.r_tail(x))
            out += m * (np.array([zc, yc])[None] + rc * np.stack([np.cos(phi), np.sin(phi)], 1))
        return resample_closed(out, n)

    def rows(self, step):
        """Row stations from the lip (bottom) back to the shroud's end"""
        c = self.c
        n = int(np.ceil((c["x_lip"] - c["x_end"]) / step)) + 1
        return np.linspace(c["x_lip"], c["x_end"], n)

    def lip_x(self, y):
        """The lip plane: x at height y"""
        return self.c["x_lip"] - self.c["rake"] * (y - float(self.y_b(self.c["x_lip"])))

    def grid(self, step, nc):
        """Outer loft points (rows, nc, 3) in model axes; the front rows lean onto the raked lip plane"""
        xs = self.rows(step)
        G = np.zeros((len(xs), nc, 3))
        for k, x in enumerate(xs):
            L = self.loop(x, nc)
            G[k, :, 0] = x
            G[k, :, 1] = L[:, 1]
            G[k, :, 2] = L[:, 0] * self.side
        lean = 1 - sstep(0.0, 0.008, self.c["x_lip"] - xs)
        G[:, :, 0] += lean[:, None] * (self.lip_x(G[:, :, 1]) - self.c["x_lip"])
        return G

    def build_sdf(self):
        """Dense loft samples and their outward normals: the signed distance is the offset along the nearest
        sample's normal (smooth: the samples are dense), capped by the lip plane"""
        G = self.grid(ROW_DENSE, NC_DENSE)
        N = grid_normals(G, self.side)
        self.S = G.reshape(-1, 3)
        self.SN = N.reshape(-1, 3)
        self.tree = cKDTree(self.S)

    def sdf(self, P):
        """Signed distance-like value of the built nacelle (negative inside)"""
        _, k = self.tree.query(P)
        d = np.einsum("ij,ij->i", P - self.S[k], self.SN[k])
        front = P[:, 0] - self.lip_x(P[:, 1])
        return np.maximum(d, front / np.sqrt(1 + self.c["rake"] ** 2))


def grid_normals(G, side):
    """Normals of a loft grid (rows, cols closed round), turned away from each row's centroid"""
    dr = np.gradient(G, axis=0)
    dc = np.roll(G, -1, axis=1) - np.roll(G, 1, axis=1)
    n = np.cross(dr, dc)
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-12)
    cen = G.mean(1, keepdims=True)
    out = G - cen
    out[..., 0] = 0
    s = np.sign(np.einsum("ijk,ijk->ij", n, out))
    return n * np.where(s == 0, 1, s)[..., None]


def poly_sdf(Q, poly):
    """Signed distance of 2D points Q to a closed polygon (negative inside)"""
    A = np.asarray(poly, float)
    B = np.roll(A, -1, 0)
    best = np.full(len(Q), np.inf)
    inside = np.zeros(len(Q), bool)
    for a, b in zip(A, B):
        e = b - a
        t = np.clip(((Q - a) @ e) / max(e @ e, 1e-20), 0, 1)
        best = np.minimum(best, np.linalg.norm(Q - a - t[:, None] * e, axis=1))
        c1 = (a[1] > Q[:, 1]) != (b[1] > Q[:, 1])
        xi = a[0] + (Q[:, 1] - a[1]) * e[0] / np.where(e[1] == 0, 1e-20, e[1])
        inside ^= c1 & (Q[:, 0] < xi)
    return np.where(inside, -best, best)


class Slab:
    """The glove and fuselage round the nacelle: upper and lower penalised height fields y(x, |z|) fitted to the
    skin away from the old tube, their smooth max, cut by the planform polygon"""

    def __init__(self, cfg, side):
        self.c, self.side = cfg["slab"], side
        self.strake = cfg["region"].get("strake")

    def fit(self, P, N, use, report, tag):
        """Robust fits of both sheets"""
        c = self.c
        x0, x1, z0, z1 = c["box"]
        x, y, z = P[:, 0], P[:, 1], P[:, 2] * self.side
        ty, tz, tr, tx = c["tube"]
        tube = (np.hypot(y - ty, z - tz) < tr) & (x < tx)
        inb = use & (x > x0) & (x < x1) & (z > z0) & (z < z1) & ~tube
        if self.strake is not None:
            a = self.strake
            inb &= ~((x > a[0]) & (x < a[1]) & (z > a[2]) & (z < a[3]) & (y > a[4]) & (y < a[5]))
        self.sp = []
        for sgn in (1, -1):
            d = inb & (N[:, 1] * sgn > 0.5)
            sp = sr.Spline2(x0, x1, c["kx"], z0, z1, c["kz"])
            rw = sp.fit(x[d], z[d], y[d], prior=np.clip(np.abs(N[d, 1]) * 2 - 0.8, 0.05, 1), lam=c["lam"])
            res = y[d] - sp(x[d], z[d])
            self.sp.append(sp)
            report.append("%-6s slab %s: %5d points, %.0f %% kept, residual p50 %.2f p95 %.2f mm" % (
                tag, "up" if sgn > 0 else "lo", int(d.sum()), 100 * np.mean(rw > 0.5),
                np.median(np.abs(res)) * 1e3, np.percentile(np.abs(res), 95) * 1e3))

    def heights(self, x, z):
        """Upper and lower sheet at (x, |z|)"""
        x0, x1, z0, z1 = self.c["box"]
        x = np.clip(x, x0, x1)
        z = np.clip(z, z0, z1)
        return self.sp[0](x, z), self.sp[1](x, z)

    def f(self, P):
        """Signed distance-like value of the slab (negative inside)"""
        z = P[:, 2] * self.side
        up, lo = self.heights(P[:, 0], z)
        v = nr.smax(P[:, 1] - up, lo - P[:, 1], self.c["round"])
        return nr.smax(v, poly_sdf(np.stack([P[:, 0], z], 1), self.c["plan"]), self.c["plan_r"])


class Side:
    """One side's region: the slab, the built nacelle and the implicit surface the old skin goes onto"""

    def __init__(self, cfg, side):
        self.cfg, self.side = cfg, side
        self.tag = "nac" + ("R" if side > 0 else "L")
        self.nac = Nacelle(cfg, side)
        self.slab = Slab(cfg, side)
        self.r = cfg["region"]

    def k(self, x):
        """Fillet size at x: none at the lip, full k_grow behind it"""
        return self.r["k"] * sstep(self.nac.c["x_lip"], self.nac.c["x_lip"] - self.r["k_grow"], x)

    def f(self, P):
        """The surface the old skin goes onto: smooth union of slab and nacelle"""
        a, b = self.nac.sdf(P), self.slab.f(P)
        k = np.maximum(self.k(P[:, 0]), 1e-6)
        h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
        return b * (1 - h) + a * h - k * h * (1 - h)

    def grad(self, P):
        """Central-difference gradient of f"""
        g = np.zeros_like(P)
        for i in range(3):
            d = np.zeros(3)
            d[i] = H
            g[:, i] = (self.f(P + d) - self.f(P - d)) / (2 * H)
        return g

    def project(self, P, iters=10):
        """Newton steps onto f = 0 along the gradient, each clipped to 4 mm"""
        Q = P.copy()
        for _ in range(iters):
            v = self.f(Q)
            g = self.grad(Q)
            st = -(v / np.maximum((g * g).sum(1), 1e-12))[:, None] * g
            ln = np.linalg.norm(st, axis=1, keepdims=True)
            Q += st * np.minimum(1.0, 0.004 / np.maximum(ln, 1e-12))
        return Q

    def weight(self, P):
        """1 inside the region box, fading over `fade` outside it; 0 in kept boxes and inside the nozzle"""
        x0, x1, z0, z1, y0, y1 = self.r["box"]
        fd = self.r["fade"]
        x, y, z = P[:, 0], P[:, 1], P[:, 2] * self.side
        w = (sstep(x0 - 0.002, x0, x) * (1 - sstep(x1, x1 + fd, x)) * sstep(z0 - fd, z0, z)
             * (1 - sstep(z1, z1 + fd, z)) * sstep(y0 - fd, y0, y) * (1 - sstep(y1, y1 + fd, y)))
        for a in self.r.get("keep", []):
            inside = (sstep(a[0] - 0.004, a[0], x) * (1 - sstep(a[1], a[1] + 0.004, x)) * sstep(a[2] - 0.004, a[2], z)
                      * (1 - sstep(a[3], a[3] + 0.004, z)) * sstep(a[4] - 0.004, a[4], y) * (1 - sstep(a[5], a[5] + 0.004, y)))
            w = w * (1 - inside)
        xn, rn = self.r["nozzle"]
        yc, zc, _ = self.nac.c["circle"]
        inner = (x < xn) & (np.hypot(y - yc, z - zc) < rn)
        return w * ~inner * (z > 0)


def skin_arrays(m):
    """Main skin of the hangar GLB (node 0, primitive 0): positions, normals, UV, faces, welded copies"""
    g = m.g
    j = g.j
    p0 = j["meshes"][j["nodes"][0]["mesh"]]["primitives"][0]
    ai = p0["attributes"]
    e = m.acc[ai["POSITION"]]
    P, N = e["P"].copy(), e["N"].copy()
    UV = g.accessor(ai["TEXCOORD_0"]).astype(np.float64)
    T0 = g.accessor(p0["indices"]).reshape(-1, 3).astype(np.int64)
    Tg = np.vstack([t for t, mt in zip(e["tris"], e["tri_mats"]) if mt == "glass"] or [np.zeros((0, 3), np.int64)])
    wid, W0, F = nr.weld(P, T0)
    Nw = np.zeros((len(W0), 3))
    np.add.at(Nw, wid, N)
    Nw /= np.maximum(np.linalg.norm(Nw, axis=1, keepdims=True), 1e-12)
    Nw = sr.vertex_normals(W0, F, Nw)
    others = [m.acc[a]["P"] for a in m.acc if a != ai["POSITION"]]
    if len(Tg):
        others.append(P[np.unique(Tg)])
    dist = cKDTree(np.vstack(others)).query(W0)[0]
    return {"P": P, "N": N, "UV": UV, "T0": T0, "wid": wid, "W0": W0, "F": F, "Nw": Nw, "ai": ai, "p0": p0,
            "free": sr.smoothstep(0.003, 0.009, dist)}


def rebuild_region(geo, sides, report):
    """Project the old skin of every side onto its f, relax, remesh the core, drop the faces the built nacelle
    covers. Returns the region mesh (V, F, w, owner, normals) and the mask of old faces it replaces."""
    import pymeshlab
    W0, F, free = geo["W0"], geo["F"], geo["free"]
    nw = len(W0)
    wts = np.stack([s.weight(W0) for s in sides], 1)
    own = np.argmax(wts, 1)
    w = wts[np.arange(nw), own] * free
    inskin = np.zeros(nw, bool)
    inskin[F.reshape(-1)] = True
    w *= inskin
    tgt = W0.copy()
    for k, s in enumerate(sides):
        sel = (own == k) & (w > 0)
        tgt[sel] = s.project(W0[sel])
        far = np.linalg.norm(tgt[sel] - W0[sel], axis=1)
        ws = w[sel]
        ws[far > GATE_FAR] = 0.0
        w[sel] = ws
    W = W0 + w[:, None] * (tgt - W0)
    report.append("projected %d skin vertices (%d core), move p95 %.2f max %.2f mm" % (
        int((w > 1e-3).sum()), int((w > 0.98).sum()), np.percentile(np.linalg.norm(W - W0, axis=1)[w > 1e-3], 95) * 1e3,
        np.linalg.norm(W - W0, axis=1).max() * 1e3))
    log("projected")
    W = relax(sides, W, F, own, w > 0.98, RELAX)
    log("relaxed")
    # the region as its own mesh: old faces with any moved corner; the core remeshed with the border frozen
    fr = (w[F].max(1) > 1e-4) & (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    outside = np.zeros(nw, bool)
    outside[F[~fr].reshape(-1)] = True
    w = w.copy()
    w[outside] = 0.0
    used = np.unique(F[fr])
    loc = np.full(nw, -1)
    loc[used] = np.arange(len(used))
    V = W[used].copy()
    V[outside[used]] = W0[used][outside[used]]
    Fr = loc[F[fr]]
    wl = w[used]
    ol = own[used]
    fc = wl[Fr].min(1) > 0.98
    el = np.linalg.norm(V[Fr[fc]][:, [1, 2, 0]] - V[Fr[fc]], axis=2).mean()
    tl = min(TARGET_EDGE, el)
    for _ in range(2):
        ms = pymeshlab.MeshSet()
        ms.add_mesh(pymeshlab.Mesh(V, Fr, f_scalar_array=fc.astype(np.float64)))
        ms.compute_selection_by_condition_per_face(condselect="fq > 0.5")
        ms.meshing_isotropic_explicit_remeshing(iterations=4, selectedonly=True, targetlen=pymeshlab.PureValue(tl),
                                                featuredeg=60, checksurfdist=False, reprojectflag=True)
        mm = ms.current_mesh()
        V2 = mm.vertex_matrix().astype(np.float64)
        F2 = mm.face_matrix().astype(np.int64)
        fsel = mm.face_selection_array().astype(bool)
        frozen = np.zeros(len(V2), bool)
        frozen[F2[~fsel].reshape(-1)] = True
        _, nn = cKDTree(V).query(V2)
        w2 = np.where(frozen, wl[nn], 1.0)
        o2 = ol[nn]
        mv = ~frozen
        for k, s in enumerate(sides):
            sel = mv & (o2 == k)
            if sel.any():
                V2[sel] = s.project(V2[sel])
        V2 = relax(sides, V2, F2, o2, mv, 6)
        V, Fr, wl, ol, fc = V2, F2, w2, o2, fsel
    report.append("remeshed the core: %d faces, edge %.2f mm (old %.2f mm)" % (int(fc.sum()), tl * 1e3, el * 1e3))
    # faces the built nacelle covers: inside it, or on it past the fillet
    drop = np.zeros(len(Fr), bool)
    nd = np.zeros(len(V))
    past = np.zeros(len(V))
    for k, s in enumerate(sides):
        sel = ol == k
        if not sel.any():
            continue
        a = s.nac.sdf(V[sel])
        b = s.slab.f(V[sel])
        nd[sel] = a
        past[sel] = (b - a) - s.k(V[sel, 0])
    vin = (nd < -DROP_IN) | ((np.abs(nd) <= DROP_IN) & (past > DROP_ON))
    vin &= wl > 0.5
    drop = vin[Fr].all(1)
    report.append("region faces under the built nacelle dropped: %d of %d" % (int(drop.sum()), len(Fr)))
    keepf = ~drop
    used = np.unique(Fr[keepf])
    loc = np.full(len(V), -1)
    loc[used] = np.arange(len(used))
    V, Fr, wl, ol, nd, past = V[used], loc[Fr[keepf]], wl[used], ol[used], nd[used], past[used]
    # the kept faces that straddle the crease between glove and built nacelle would cut across the inside corner
    # (a sawtooth standing proud of the lip face and walls); their vertices on the nacelle are sunk into it so the
    # visible seam is the surfaces' own intersection
    sink = np.zeros(len(V))
    for k, s in enumerate(sides):
        sel = (ol == k) & (wl > 0.5) & (np.abs(nd) <= 4 * DROP_IN)
        if not sel.any():
            continue
        d = SINK * sr.smoothstep(DROP_ON, DROP_ON + 0.002, past[sel])
        g = np.stack([(s.nac.sdf(V[sel] + e) - s.nac.sdf(V[sel] - e)) / (2 * H) for e in np.eye(3) * H], 1)
        g /= np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)
        V[sel] -= g * d[:, None]
        sink[sel] = d
    report.append("crease vertices sunk into the built nacelle: %d" % int((sink > 1e-5).sum()))
    # normals: gradient of f, the old normal under the faded part
    _, nn = cKDTree(W).query(V)
    No = geo["Nw"][nn]
    Nn = No.copy()
    for k, s in enumerate(sides):
        sel = (ol == k) & (wl > 0)
        if not sel.any():
            continue
        gr = s.grad(V[sel])
        gr /= np.maximum(np.linalg.norm(gr, axis=1, keepdims=True), 1e-12)
        # f grows outward, so its gradient is the outward normal; an old normal against it is turned
        no = No[sel] * np.sign(np.einsum("ij,ij->i", gr, No[sel]) + 1e-9)[:, None]
        nb = (1 - wl[sel, None]) * no + wl[sel, None] * gr
        Nn[sel] = nb / np.maximum(np.linalg.norm(nb, axis=1, keepdims=True), 1e-12)
    fn = np.cross(V[Fr[:, 1]] - V[Fr[:, 0]], V[Fr[:, 2]] - V[Fr[:, 0]])
    bad = np.einsum("ij,ij->i", fn, Nn[Fr].sum(1)) < 0
    Fr[bad] = Fr[bad][:, [0, 2, 1]]
    report.append("region faces turned to their normals: %d" % int(bad.sum()))
    shade = np.zeros((len(V), 2))
    shade[:, 0] = (1 - sr.smoothstep(0.0, 0.004, np.abs(past))) * (np.abs(nd) < 0.004)
    return {"V": V, "F": Fr, "w": wl, "own": ol, "N": Nn, "fr": fr, "shade": shade, "W": W}


def relax(sides, V, F, own, move, rounds):
    """Tangential relaxation of the vertices `move`, each projected back onto its side's f"""
    A = nr.adjacency(F, len(V))
    deg = np.maximum(np.asarray(A.sum(1)).ravel(), 1)
    for _ in range(rounds):
        L = (A @ V) / deg[:, None] - V
        for k, s in enumerate(sides):
            sel = move & (own == k)
            if not sel.any():
                continue
            gr = s.grad(V[sel])
            gr /= np.maximum(np.linalg.norm(gr, axis=1, keepdims=True), 1e-12)
            Lt = L[sel] - np.einsum("ij,ij->i", L[sel], gr)[:, None] * gr
            V[sel] = s.project(V[sel] + 0.5 * Lt, iters=4)
    return V


def opening(s, n):
    """Intake opening outline in the lip plane: (n, 3) points by angle round the opening centre, matched to the
    outer section's columns later"""
    c, it = s.nac.c, s.nac.i
    t = it["t"]
    yb = float(s.nac.y_b(c["x_lip"])) + t
    yt = it["y_ot"]
    zi, zo = c["z_in"] + t, c["z_out"] - t
    rbi, rbo, rt = c["r_bi"] - t, c["r_bo"] - t, it["r_top"]

    def arc(cz, cy, r, a0, a1, k=60):
        u = np.linspace(a0, a1, k)
        return np.stack([cz + r * np.cos(u), cy + r * np.sin(u)], 1)
    Q = np.vstack([arc(zi + rbi, yb + rbi, rbi, np.pi, 1.5 * np.pi), arc(zo - rbo, yb + rbo, rbo, 1.5 * np.pi, 2 * np.pi),
                   arc(zo - rt, yt - rt, rt, 0.0, 0.5 * np.pi), arc(zi + rt, yt - rt, rt, 0.5 * np.pi, np.pi)])
    return resample_closed(Q, n), np.array([(zi + zo) / 2, (yb + yt) / 2])


def by_angle(Q, cen, ang):
    """Points of the closed loop Q at the angles `ang` round cen (polar interpolation; Q star-shaped round cen)"""
    d = Q - cen
    a = np.arctan2(d[:, 1], d[:, 0])
    r = np.linalg.norm(d, axis=1)
    rr = np.interp(ang, a, r, period=2 * np.pi)
    return cen[None] + rr[:, None] * np.stack([np.cos(ang), np.sin(ang)], 1)


def build_parts(s, report):
    """The built nacelle of one side as meshes with per-corner UVs in model units: list of dicts (name, V, N, F,
    uv (len(F), 3, 2), paint: "bake" | "duct" | "dark")"""
    c, it = s.nac.c, s.nac.i
    sd = s.side
    G = s.nac.grid(ROW, NC)
    Nn = grid_normals(G, sd)
    nr_, nc = G.shape[:2]
    parts = []
    # outer loft: columns closed round, a duplicate seam column for the UV
    idx = np.arange(nr_ * (nc + 1)).reshape(nr_, nc + 1)
    V = np.concatenate([G, G[:, :1]], 1).reshape(-1, 3)
    N = np.concatenate([Nn, Nn[:, :1]], 1).reshape(-1, 3)
    seg = np.linalg.norm(np.diff(np.concatenate([G, G[:, :1]], 1), axis=1), axis=2)
    u = np.concatenate([np.zeros((nr_, 1)), np.cumsum(seg, 1)], 1)
    v = np.concatenate([np.zeros((1, nc + 1)), np.cumsum(np.linalg.norm(np.diff(np.concatenate([G, G[:, :1]], 1),
                                                                                 axis=0), axis=2), 0)], 0)
    UV = np.stack([u, v], -1).reshape(-1, 2)
    a, b, cc, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]
    F = np.vstack([np.stack([a, b, cc], -1).reshape(-1, 3), np.stack([a, cc, d], -1).reshape(-1, 3)])
    parts.append(orient({"name": "loft", "V": V, "N": N, "F": F, "uv": UV[F], "paint": "bake"}))
    # lip face: outer front row to the opening, matched by angle round the opening centre
    front = G[0]
    op, oc = opening(s, 512)
    ang = np.arctan2(front[:, 1] - oc[1], front[:, 2] * sd - oc[0])
    inner2 = by_angle(op, oc, ang)
    inner = np.stack([s.nac.lip_x(inner2[:, 1]), inner2[:, 1], inner2[:, 0] * sd], 1)
    V = np.vstack([front, inner])
    nf = np.array([1.0, s.nac.c["rake"], 0.0])
    nf /= np.linalg.norm(nf)
    N = np.tile(nf, (len(V), 1))
    i0 = np.arange(nc)
    i1 = (i0 + 1) % nc
    F = np.vstack([np.stack([i0, i1, nc + i1], 1), np.stack([i0, nc + i1, nc + i0], 1)])
    uvp = np.stack([V[:, 2], V[:, 1]], 1)
    parts.append(orient({"name": "lip", "V": V, "N": N, "F": F, "uv": uvp[F], "paint": "bake"}))
    # duct: the opening carried straight back, then the end cap (fan)
    depths = np.array([0.0, 0.0015, 0.004, 0.008, 0.013, 0.019, 0.025, it["depth"]])
    D = np.stack([inner + np.array([-dd, 0, 0]) for dd in depths])
    cen_y, cen_z = oc[1], oc[0] * sd
    dn = np.stack([np.zeros(nc), cen_y - inner[:, 1], cen_z - inner[:, 2]], 1)
    dn /= np.maximum(np.linalg.norm(dn, axis=1, keepdims=True), 1e-12)
    nd_ = len(depths)
    idx = np.arange(nd_ * nc).reshape(nd_, nc)
    V = D.reshape(-1, 3)
    N = np.tile(dn, (nd_, 1))
    a, b = idx[:-1], np.roll(idx, -1, 1)[:-1]
    cc, d = np.roll(idx, -1, 1)[1:], idx[1:]
    F = np.vstack([np.stack([a, b, cc], -1).reshape(-1, 3), np.stack([a, cc, d], -1).reshape(-1, 3)])
    per = np.r_[0, np.cumsum(np.linalg.norm(np.diff(np.vstack([inner, inner[:1]]), axis=0), axis=1))][:-1]
    uvd = np.stack([np.tile(per, nd_), np.repeat(depths, nc)], 1)
    duct = {"name": "duct", "V": V, "N": N, "F": F, "uv": uvd[F], "paint": "duct", "depth": np.repeat(depths, nc)}
    # wrap the seam: give the faces that cross from the last column to the first a continued u
    wrap = (F % nc == nc - 1).any(1) & (F % nc == 0).any(1)
    ufix = duct["uv"][wrap]
    lo = ufix[..., 0] < per[-1] * 0.5
    ufix[..., 0] = np.where(lo, ufix[..., 0] + per[-1] + np.linalg.norm(inner[0] - inner[-1]), ufix[..., 0])
    duct["uv"][wrap] = ufix
    parts.append(orient(duct, inward=True))
    capc = D[-1].mean(0)
    V = np.vstack([D[-1], capc])
    N = np.tile(np.array([1.0, 0.0, 0.0]), (len(V), 1))
    F = np.stack([np.full(nc, nc), i1, i0], 1)
    uvc = np.stack([V[:, 2], V[:, 1]], 1)
    parts.append(orient({"name": "cap", "V": V, "N": N, "F": F, "uv": uvc[F], "paint": "dark",
                         "depth": np.full(len(V), it["depth"])}))
    # splitter plate in the middle of the opening, from the lip plane to the cap
    zs, hs = (c["z_in"] + c["z_out"]) / 2, it["split"]
    y0, y1 = float(s.nac.y_b(c["x_lip"])) + it["t"] - 0.0003, it["y_ot"] + 0.0003
    xa0, xa1 = s.nac.lip_x(y0), s.nac.lip_x(y1)
    xb = c["x_lip"] - it["depth"] + 0.0002
    box = []
    for zz in (zs - hs, zs + hs):
        box += [(xa0, y0, zz), (xa1, y1, zz), (xb, y1, zz), (xb, y0, zz)]
    Vb = np.array(box)
    Vb[:, 2] *= sd
    quads = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (3, 2, 6, 7), (1, 5, 6, 2), (0, 3, 7, 4)]
    V, N, F, uvs = [], [], [], []
    for q in quads:
        pts = Vb[list(q)]
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        n /= np.linalg.norm(n)
        if n @ (pts.mean(0) - Vb.mean(0)) < 0:
            n = -n
        k0 = len(V)
        for p in pts:
            V.append(p)
            N.append(n)
        F += [(k0, k0 + 1, k0 + 2), (k0, k0 + 2, k0 + 3)]
        ax = np.argmax(np.abs(n))
        keep = [i for i in range(3) if i != ax]
        uvs += [pts[[0, 1, 2]][:, keep], pts[[0, 2, 3]][:, keep]]
    parts.append(orient({"name": "splitter", "V": np.array(V), "N": np.array(N), "F": np.array(F),
                         "uv": np.array(uvs), "paint": "dark", "depth": np.full(len(V), 0.01)}))
    # rear ring: the shroud's last row in to just inside the kept nozzle ring
    back = G[-1]
    yc, zc, _ = c["circle"]
    cen = np.array([back[:, 0].mean(), yc, zc * sd])
    dirr = back - cen
    dirr[:, 0] = 0
    dirr /= np.maximum(np.linalg.norm(dirr, axis=1, keepdims=True), 1e-12)
    innr = cen + dirr * c["ring_in"]
    innr[:, 0] = back[:, 0]
    V = np.vstack([back, innr])
    N = np.tile(np.array([-1.0, 0.0, 0.0]), (len(V), 1))
    F = np.vstack([np.stack([i0, i1, nc + i1], 1), np.stack([i0, nc + i1, nc + i0], 1)])
    uvr = np.stack([V[:, 2], V[:, 1]], 1)
    parts.append(orient({"name": "ring", "V": V, "N": N, "F": F, "uv": uvr[F], "paint": "bake"}))
    zz = np.linspace(c["z_in"], c["z_out"], 9)
    up, lo = s.slab.heights(np.full(9, c["x_lip"]), zz)
    report.append("%-6s glove at the lip: lower %.4f..%.4f, upper %.4f..%.4f (opening top %.4f, cap top %.4f)" % (
        s.tag, lo.min(), lo.max(), up.min(), up.max(), it["y_ot"], float(s.nac.y_top(c["x_lip"]))))
    report.append("%-6s built: loft %d x %d, lip at x %.4f, opening y %.4f..%.4f |z| %.4f..%.4f, duct %.3f" % (
        s.tag, nr_, nc, c["x_lip"], float(s.nac.y_b(c["x_lip"])) + it["t"], it["y_ot"], c["z_in"] + it["t"],
        c["z_out"] - it["t"], it["depth"]))
    return parts


def clean_specks(tuv, groups, col, report):
    """Bright specks out of the baked paint (in place in col): the old skin was torn where the glove trailing
    edge met the nacelle and its light inner faces left scratch marks in the projection bake. A texel much lighter
    than the median of its neighbourhood takes the median texel's colour; dark panel lines stay, and a straight
    camouflage edge is kept by the median (only its sharp corners round off by a few texels)."""
    from scipy.ndimage import median_filter
    msk = np.zeros(col.shape[:2], bool)
    for gr in groups:
        def cb(k, rr, cc, bc):
            ok = (rr >= 0) & (rr < msk.shape[0]) & (cc >= 0) & (cc < msk.shape[1])
            msk[rr[ok], cc[ok]] = True
        nr.raster(tuv[gr["faces"]], gr["faces"], cb)
    ys, xs = np.nonzero(msk)
    if not len(ys):
        return
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    m = msk[y0:y1, x0:x1]
    sub = col[y0:y1, x0:x1].astype(np.float32)
    lum = sub @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    med = median_filter(lum, SPECK_WIN)
    bad = m & (lum > med + SPECK_DL)
    n = int(bad.sum())
    if n:
        r, c = np.nonzero(bad)
        h = SPECK_WIN // 2
        for i, j in zip(r, c):
            win = sub[max(i - h, 0):i + h + 1, max(j - h, 0):j + h + 1].reshape(-1, 3)
            wl = lum[max(i - h, 0):i + h + 1, max(j - h, 0):j + h + 1].ravel()
            sub[i, j] = win[np.argsort(wl)[len(wl) // 2]]
        col[y0:y1, x0:x1] = np.clip(sub, 0, 255).astype(np.uint8)
    report.append("bright specks taken out of the baked paint: %d texels" % n)
    # dark blots: the old dimples left soft dark smudges in the light camouflage tone that the dent evening could
    # not lift (its tone split takes a smudge for a tone of its own; a livery then maps it to its dark tone: dark
    # spots on the nacelle top). The light level round a blot is the grey closing of the chart's luminance (dark
    # features narrower than BLOT_SIZE filled in); a compact component well below it (panel lines are thinner than
    # the opening, camouflage patches larger or elongated) takes the closing's colour, feathered at its rim.
    from scipy.ndimage import binary_dilation, binary_opening, find_objects, gaussian_filter, grey_closing, label
    lum = sub @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    mf = m.astype(np.float32)
    clo = np.stack([grey_closing(sub[..., c] * mf, size=(BLOT_SIZE, BLOT_SIZE)) for c in range(3)], -1)
    depth = (clo @ np.array([0.2126, 0.7152, 0.0722], np.float32) - lum) * m
    dark = binary_opening(depth > BLOT_DL, iterations=2)
    lab, _ = label(dark)
    fix = np.zeros_like(dark)
    nb_ = 0
    for k, sl in enumerate(find_objects(lab)):
        h_, w_ = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        cm = lab[sl] == k + 1
        area = int(cm.sum())
        if (BLOT_AREA[0] <= area <= BLOT_AREA[1] and max(h_, w_) <= 2.5 * min(h_, w_) and area >= 0.3 * h_ * w_
                and depth[sl][cm].mean() > 1.3 * BLOT_DL):
            fix[sl] |= cm
            nb_ += 1
    fix = binary_dilation(fix, iterations=4) & m
    if fix.any():
        wf = np.clip(gaussian_filter(fix.astype(np.float32), 2.0) * 1.5, 0, 1) * m
        sub += (clo - sub) * wf[..., None]
        col[y0:y1, x0:x1] = np.clip(sub, 0, 255).astype(np.uint8)
    report.append("dark blots taken out of the baked paint: %d (%d texels)" % (nb_, int(fix.sum())))


def orient(p, inward=False):
    """Turn faces whose winding disagrees with their vertex normals"""
    V, F, N = p["V"], p["F"], p["N"]
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    bad = np.einsum("ij,ij->i", fn, N[F].sum(1)) < 0
    p["F"] = F.copy()
    p["F"][bad] = F[bad][:, [0, 2, 1]]
    p["uv"] = p["uv"].copy()
    p["uv"][bad] = p["uv"][bad][:, [0, 2, 1]]
    return p


def paint_built(parts_all, tuv, offs, col, orm):
    """Duct, cap and splitter paint: grey by depth behind the lip (DUCT_PAINT), matt, no metal"""
    dk = np.array([d for d, _ in DUCT_PAINT])
    gv = np.array([g for _, g in DUCT_PAINT])
    for p, (f0, v0) in zip(parts_all, offs):
        if p["paint"] == "bake":
            continue
        dep = p["depth"]

        def cb(k, rr, cc, bc):
            t = p["F"][k]
            g = np.interp(bc @ dep[t], dk, gv)
            col[rr, cc] = np.clip(np.stack([g, g * 1.0, g * 1.02], 1) + 0.5, 0, 255).astype(np.uint8)
            orm[rr, cc] = np.array([150, 235, 0], np.uint8)
        nr.raster(tuv[f0:f0 + len(p["F"])], np.arange(len(p["F"])), cb, grow=1.5)


def place_charts(F, cuv, groups, cov, density, report, cell=4):
    """nacelle_rebuild.place_charts on a coarse occupancy grid (cell x cell texel blocks): the same packing rule
    (largest chart first, topmost-leftmost free box, a quarter turn when that fits better, the largest density
    step at which all charts fit), fast enough for the hundreds of charts of a large region"""
    from scipy.ndimage import binary_dilation
    gap = nr.CHART_GAP
    occ_t = binary_dilation(cov, iterations=gap)
    S = occ_t.shape[0] // cell
    occ0 = occ_t[:S * cell, :S * cell].reshape(S, cell, S, cell).any(axis=(1, 3))
    allf = np.concatenate([g["faces"] for g in groups])
    scale = np.zeros(len(F))
    for g in groups:
        scale[g["faces"]] = g["scale"]
    lab = nr.charts(F[allf], cuv[allf])
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
            u = u - u.reshape(-1, 2).min(0)
            wh = u.reshape(-1, 2).max(0) + 2 + 2 * gap
            best = None
            for rot in (False, True):
                w, h = (wh[1], wh[0]) if rot else (wh[0], wh[1])
                cw, ch = int(np.ceil(w / cell)), int(np.ceil(h / cell))
                pos = nr._free(occ, cw, ch)
                if pos is not None and (best is None or pos[0] + pos[1] * 0.01 < best[0][0] + best[0][1] * 0.01):
                    best = (pos, rot, cw, ch)
            if best is None:
                ok = False
                break
            (r0, c0), rot, cw, ch = best
            uu = u[..., ::-1] if rot else u
            out[fs] = uu + np.array([c0 * cell + gap + 1, r0 * cell + gap + 1])
            occ[r0:r0 + ch, c0:c0 + cw] = True
        if ok:
            report.append("UV: %d charts at %.0f %% of the skin's texel density" % (len(ids), 100 * f))
            return out
    raise SystemExit("no room in the atlas for the rebuilt skin")


def main() -> int:
    """Command line: build the box nacelles of one hangar plane"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    ap.add_argument("--maps", nargs=2, required=True)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    rep = []
    cfg = NACELLES[a.key]
    m = pp.Model(a.src)
    geo = skin_arrays(m)
    geo["key"] = a.key
    sides = [Side(cfg, 1), Side(cfg, -1)]
    for s in sides:
        s.nac.build_sdf()
        s.slab.fit(geo["W0"], geo["Nw"], geo["free"] > 0.5, rep, s.tag)
    log('fitted')
    reg = rebuild_region(geo, sides, rep)
    log('region rebuilt')
    if a.report:
        W0, F = geo["W0"], geo["F"]
        N0 = sr.vertex_normals(W0, F, geo["Nw"])
        pick0 = (np.stack([s.weight(W0) for s in sides], 1).max(1) > 0.9) & (geo["free"] > 0.9)
        d0 = np.abs(sr.dent_metric(W0, N0, pick0))[pick0]
        pick1 = reg["w"] > 0.9
        d1 = np.abs(sr.dent_metric(reg["V"], reg["N"], pick1))[pick1]
        rep.append("region skin dent p95 %.2f -> %.2f mm, p99 %.2f -> %.2f mm, max %.2f -> %.2f mm (%d -> %d vertices)" % (
            np.percentile(d0, 95) * 1e3, np.percentile(d1, 95) * 1e3, np.percentile(d0, 99) * 1e3,
            np.percentile(d1, 99) * 1e3, d0.max() * 1e3, d1.max() * 1e3, int(pick0.sum()), int(pick1.sum())))
    log('dent report')
    # the built parts join the region mesh
    parts = []
    for s in sides:
        parts += build_parts(s, rep)
    V, Fa, Nn, wl, sh = [reg["V"]], [reg["F"]], [reg["N"]], [reg["w"]], [reg["shade"]]
    nv, nf = len(reg["V"]), len(reg["F"])
    offs = []
    for p in parts:
        offs.append((nf, nv))
        V.append(p["V"])
        Fa.append(p["F"] + nv)
        Nn.append(p["N"])
        wl.append(np.ones(len(p["V"])))
        sh.append(np.zeros((len(p["V"]), 2)))
        nv += len(p["V"])
        nf += len(p["F"])
    allr = {"V": np.vstack(V), "F": np.vstack(Fa), "N": np.vstack(Nn), "w": np.concatenate(wl), "shade": np.vstack(sh),
            "fr": reg["fr"]}
    col = np.asarray(Image.open(a.maps[0]).convert("RGB")).copy()
    S = col.shape[0]
    orm_im = Image.open(a.maps[1]).convert("RGB")
    orm_size = orm_im.size
    orm = np.asarray(orm_im.resize((S, S), Image.BICUBIC)).copy()
    cuv = np.zeros((len(allr["F"]), 3, 2))
    groups = []
    for k, s in enumerate(sides):
        fown = np.array([np.bincount(o, minlength=2).argmax() for o in reg["own"][reg["F"]]])
        fids = np.nonzero(fown == k)[0]
        if not len(fids):
            continue
        used = np.unique(reg["F"][fids])
        loc = np.full(len(reg["V"]), -1)
        loc[used] = np.arange(len(used))
        uv = nr.unwrap(reg["V"][used], loc[reg["F"][fids]], 0.006)
        cuv[fids] = uv
        V3 = reg["V"][reg["F"][fids]]
        a3 = np.linalg.norm(np.cross(V3[:, 1] - V3[:, 0], V3[:, 2] - V3[:, 0]), axis=1).sum() / 2
        d1, d2 = uv[:, 1] - uv[:, 0], uv[:, 2] - uv[:, 0]
        a2 = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]).sum() / 2
        groups.append({"tag": s.tag + "_skin", "faces": fids, "scale": np.sqrt(a3 / a2), "dark_out": False})
    pgroups = []
    for p, (f0, _) in zip(parts, offs):
        fids = np.arange(f0, f0 + len(p["F"]))
        cuv[fids] = p["uv"]
        g = {"tag": p["name"], "faces": fids, "scale": 1.0, "dark_out": False}
        groups.append(g)
        if p["paint"] == "bake":
            pgroups.append(g)
    log('unwrapped')
    keep = geo["T0"][~reg["fr"]]
    cov = nr.coverage_of(m.g, keep, S)
    density = nr.skin_density(geo, keep, S)
    tuv = place_charts(allr["F"], cuv, groups, cov, density, rep)
    log('charts placed')
    nr.bake(geo, allr, tuv, groups[:len(groups) - len(parts)] + pgroups, col, orm, rep)
    log('baked')
    clean_specks(tuv, groups[:len(groups) - len(parts)] + pgroups, col, rep)
    paint_built(parts, tuv, offs, col, orm)
    nr.write_region(m, geo, allr, tuv, S, a.dst, rep)
    Image.fromarray(col).save(a.maps[0], quality=95)
    Image.fromarray(orm).resize(orm_size, Image.LANCZOS).save(a.maps[1], quality=95)
    if a.report:
        s = sides[0]
        c, it = s.nac.c, s.nac.i
        yb = float(s.nac.y_b(c["x_lip"])) + it["t"]
        hh, hw = (it["y_ot"] - yb) / 2, (c["z_out"] - c["z_in"]) / 2 - it["t"]
        rep.append("Livery.INTAKE_DUCTS row: [%.4f, %.4f, %.4f, %.4f, %.4f, %.2f, 0.0, %.3f, %.4f, 0.0, 0.0]" % (
            (it["y_ot"] + yb) / 2, (c["z_in"] + c["z_out"]) / 2, hh * 1.45, hw * 1.45, c["x_lip"] - c["rake"] * hh,
            -c["rake"], it["depth"], c["z_in"] + 0.0005))
    print("\n".join(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
