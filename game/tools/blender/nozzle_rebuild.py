"""Nacelle tails and nozzles of the «Грач» attackers built as clean geometry (Kanta s15, close-ups without words
from the hangar: the nacelle tail in front of the nozzle had a ragged, lumpy dark belt with torn edges, and the
nozzle end a torn dark ring, on both «Грач» 1 and 2).

What the nacelle tail of this aircraft type looks like (walkaround photos of museum aircraft; the notes stay outside
the repository): behind the wing the engine nacelle runs on as one smooth body of revolution that tapers gently
(a boat-tail of a few degrees) towards its end; there is no step where the generator put the end of a «sleeve»
over a narrower tube. The nacelle ends in a thin, rounded rim; just inside it sits the engine's own nozzle, a short
convergent pipe of bare, heat-darkened metal, its exit a little behind the rim, and deeper inside the exhaust cone
in near black. Under the wing the nacelle belly and the wing root end at the trailing edge and the tail carries on
round; inboard the nacelle meets the fuselage side in a narrow rounded channel.

What the generator made: the nacelle is a sleeve that ends in a ragged, torn edge some 8 cm (model 0.08) ahead of
the nozzle, over a narrower tube that sticks out of it; the junctions to the wing and to the fuselage there are saw
teeth, the nozzle is a lumpy cap, and the paint of the sleeve's end and of the nozzle is a near-black band, which
every livery keeps dark. Smoothing that mesh (skin_refit.py) never gave a clean result; here the tail is built.

How it is built (per side, mirrored), with the machinery of nacelle_box.py (Kit-2's box nacelles):
1. Tail (config TAILS "tail"): a loft of sections round a straight axis along x through the nozzle centre
   (NozzleFlame.NOZZLES, so the flame stays where it was). Ahead of x_front the rows follow the old skin's own
   section (the outermost skin within reach of the axis, per angle, smoothed round), a hair under it, so the old
   nacelle in front carries on flush; behind it each column runs a Hermite curve from the old section, with the
   old skin's own slope, into the round tail (r_tail knots: a gentle boat-tail) and ends at the rim (x_exit).
2. Old skin round the tail (the region box, fading out at the front): every vertex is projected onto
   f = smin(body, tail), where the body is the wing and wing root (nacelle_box.Slab: upper and lower penalised
   height fields, cut by the planform and closed to a thin trailing edge; inboard of the nacelle axis it is a thin
   plate at the belly) joined with the fuselage side (nacelle_box.Fuselage), and the tail is the signed distance to
   the built loft (capped at the rim). The region is relaxed, its core remeshed and clipped where the built tail
   alone is f (nacelle_box.rebuild_region), so the old sleeve, its torn edge, the old tube and the old nozzle go,
   and the tail meets wing and fuselage in clean fillets. The cut is also bounded by the plane x = x_front
   (clip_plane), and the fillets inboard (k_in, and the fuselage's own k) are wide enough that the narrow channel
   between nacelle and fuselage is one rounded valley, not a slot the mesh can only follow in saw teeth.
3. Nozzle (config "nozzle"): bodies of revolution on the same columns as the loft: the rim (a half round of the
   lip thickness), the shroud's inner wall back to a dark annular floor, the engine nozzle (an outer wall, a flat
   rim at NozzleFlame.NOZZLES x and radius, and the convergent inner wall) and the exhaust cone.
4. Paint: the loft and the rebuilt region get their own UV charts at the skin's texel density and are
   projection-baked from the old surface (nacelle_rebuild.bake; near-black old paint is replaced by the skin's own
   paint, dark_out), then the bright specks, dark blots and dark faces are cleaned (nacelle_box). The nozzle parts
   are painted dark sooty metal by depth. Livery.ENGINE_HOLES darkens the rim's rear face and everything inside the
   nozzle in every livery (--report prints the row; the old row covered the whole old nacelle).

  python3 -I nozzle_rebuild.py <hangar.glb> <key> <out.glb> --maps <col.jpg> <orm.jpg> [--report]
The maps are rewritten in place (start from copies of the extracted maps), then tex_clean.py pads them.
Decision 05.11.2026 (s15): built tails replace the generator's sleeve on both «Грач»; checks and open items in
docs/tasks/3d-models-handoff.md. Axes: glTF model space (nose +X, up +Y, right wing +Z), length 1.
Needs numpy, scipy, Pillow, pymeshlab; bpy for the unwrap and the bake."""
import argparse
import os
import sys

try:
    import bpy  # noqa: F401  first: its TBB must load before MeshLab's
except ImportError:
    bpy = None
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nacelle_box as nb  # noqa: E402
import nacelle_rebuild as nr  # noqa: E402
import plane_polish as pp  # noqa: E402
import skin_refit as sr  # noqa: E402

Image.MAX_IMAGE_PIXELS = None

# Per plane, right side (mirrored), model units.
# tail: axis (y, |z|) through the nozzle centre; x_front: where the loft leaves the old nacelle's section; overlap:
#   how far ahead of x_front the loft rows lie under the old skin; morph_end: where the section is round; r_tail:
#   (x, radius) knots of the round tail (monotone cubic), the last at the rim; x_exit: the rim (rearmost point of the
#   shroud); lip: rim thickness; r_max: the old section is read within this distance of the axis.
# nozzle: x and inner radius of the engine nozzle's exit (NozzleFlame.NOZZLES), its wall, the depth of the annular
#   floor between the shroud's inner wall and the nozzle (from the rim), the nozzle's inner radius at its depth
#   (convergent), that depth, and the exhaust cone (tip depth from the nozzle exit, base radius; its base is a flat
#   ring at the convergent wall's end).
# slab: as nacelle_box (box x0, x1, |z|0, |z|1 of the data; knots, penalty, rounding, planform polygon (x, |z|),
#   trailing-edge polyline, te_len), plus thin: inboard of this |z| the slab is a plate of thickness plate on its
#   lower sheet (the belly under the nacelle; there is no upper wing skin between nacelle and fuselage); tube
#   leaves the old nacelle out of the lower sheet's data, tube_up (wider: the old sleeve's sides) out of the upper's.
# region: box (x0, x1, |z|0, |z|1, y0, y1), fade at the front and round the box, fillet k (k_in inboard of
#   the axis, the channel to the fuselage), fus: nacelle_box.Fuselage config.
TAILS: dict = {
    "attacker_1": {
        "tail": {"axis": (-0.0386, 0.0807), "x_front": -0.150, "overlap": 0.006, "morph_end": -0.205,
                 "r_tail": [(-0.205, 0.0250), (-0.225, 0.0240), (-0.2435, 0.0221)], "x_exit": -0.2435,
                 "lip": 0.0012, "r_max": 0.045},
        "nozzle": {"x": -0.2420, "r": 0.0160, "wall": 0.0008, "floor": 0.0055, "r_in": 0.0128, "depth": 0.012,
                   "cone": (0.009, 0.0110)},
        "slab": {"box": (-0.30, -0.08, 0.035, 0.26), "kx": 0.02, "kz": 0.015, "lam": (1.0, 1.0), "round": 0.003,
                 "plan_r": 0.004, "tube": (-0.0386, 0.0807, 0.027, 0.3), "tube_up": (-0.0386, 0.0807, 0.042, 0.3),
                 "thin": (0.070, 0.085), "plate": 0.004,
                 "plan": [(0.0, 0.0), (0.0, 0.30), (-0.2178, 0.30), (-0.2178, 0.16), (-0.2160, 0.14),
                          (-0.2128, 0.12), (-0.2050, 0.112), (-0.2000, 0.10), (-0.2000, 0.0)],
                 "te": [(-0.2178, 0.30), (-0.2178, 0.16), (-0.2160, 0.14), (-0.2128, 0.12), (-0.2050, 0.112),
                        (-0.2000, 0.10), (-0.2000, 0.0)], "te_len": 0.010},
        "region": {"box": (-0.252, -0.149, 0.030, 0.128, -0.080, 0.000), "fade": 0.008, "k": 0.005,
                   "k_in": 0.010,
                   "fus": {"axis_y": -0.048, "x": (-0.30, -0.12), "fade": (0.5, 0.6), "zmax": 0.056, "rmax": 0.07,
                           "theta": 1.3, "kx": 0.012, "kt": 0.18, "lam": (1.0, 1.0), "k": 0.008}},
    },
    "attacker_2": {
        "tail": {"axis": (-0.0320, 0.0880), "x_front": -0.200, "overlap": 0.006, "morph_end": -0.245,
                 "r_tail": [(-0.245, 0.0310), (-0.272, 0.0285), (-0.2935, 0.0245)], "x_exit": -0.2935,
                 "lip": 0.0013, "r_max": 0.048},
        "nozzle": {"x": -0.2920, "r": 0.0158, "wall": 0.0008, "floor": 0.0060, "r_in": 0.0126, "depth": 0.012,
                   "cone": (0.009, 0.0108)},
        "slab": {"box": (-0.33, -0.12, 0.040, 0.26), "kx": 0.02, "kz": 0.015, "lam": (1.0, 1.0), "round": 0.003,
                 "plan_r": 0.004, "tube": (-0.0320, 0.0880, 0.033, 0.3), "tube_up": (-0.0320, 0.0880, 0.044, 0.3),
                 "thin": (0.075, 0.090), "plate": 0.004,
                 "plan": [(0.0, 0.0), (0.0, 0.30), (-0.2610, 0.30), (-0.2610, 0.13), (-0.2500, 0.124),
                          (-0.2430, 0.118), (-0.2430, 0.0)],
                 "te": [(-0.2610, 0.30), (-0.2610, 0.13), (-0.2500, 0.124), (-0.2430, 0.118), (-0.2430, 0.0)],
                 "te_len": 0.010},
        "region": {"box": (-0.302, -0.199, 0.034, 0.135, -0.085, 0.010), "fade": 0.008, "k": 0.005,
                   "k_in": 0.010,
                   "fus": {"axis_y": -0.040, "x": (-0.33, -0.15), "fade": (0.5, 0.6), "zmax": 0.058, "rmax": 0.07,
                           "theta": 1.3, "kx": 0.012, "kt": 0.18, "lam": (1.0, 1.0), "k": 0.008}},
    },
}
NC = 144             # columns round the loft and the nozzle
ROW = 0.0020         # row spacing of the built loft
NC_DENSE = 512       # columns of the dense loft behind the signed distance
ROW_DENSE = 0.0004   # its row spacing
K_SEC = 720          # rays round the axis when the old section is read
DIP = 0.0003         # the loft rows ahead of x_front lie this far under the old skin
SLOPE_MAX = 0.6      # the old skin's slope dr/dx carried into the morph is held within +-this
CLIP = (0.85, 1.12)  # the old section's upper half is held within these shares of its fitted circle
# nozzle paint (sRGB grey) by depth behind the rim, and its ORM (occlusion, roughness, metal)
NOZZLE_PAINT = ((0.0, 70.0), (0.002, 52.0), (0.006, 34.0), (0.012, 18.0), (0.03, 9.0))
NOZZLE_TINT = np.array([1.0, 0.95, 0.88])   # heat-darkened steel: a little warm
NOZZLE_ORM = (170, 140, 150)


def smooth_periodic(v, sig):
    """Gaussian smoothing of a closed (periodic) sequence, sigma in samples"""
    w = int(np.ceil(3 * sig))
    k = np.exp(-0.5 * (np.arange(-w, w + 1) / sig) ** 2)
    k /= k.sum()
    return np.convolve(np.r_[v[-w:], v, v[:w]], k, "valid")


def section_radius(P, T, x, yc, zc, side, r_max, phi):
    """The old skin's section at x read round the axis (yc, |z| zc) of one side: per angle phi (in the (|z|, y)
    plane, 0 outboard, pi/2 up) the outermost crossing within r_max of the axis; NaN where a ray finds none"""
    d = P[:, 0] - x
    sd = d[T]
    cross = (sd.min(1) < 0) & (sd.max(1) > 0)
    A, B = [], []
    for tri, dd in zip(T[cross], sd[cross]):
        pts = []
        for i, j in ((0, 1), (1, 2), (2, 0)):
            if (dd[i] < 0) != (dd[j] < 0):
                t = dd[i] / (dd[i] - dd[j])
                q = P[tri[i]] + t * (P[tri[j]] - P[tri[i]])
                pts.append((q[2] * side - zc, q[1] - yc))
        if len(pts) == 2:
            A.append(pts[0])
            B.append(pts[1])
    A, B = np.array(A), np.array(B)
    E = B - A
    out = np.full(len(phi), np.nan)
    for i, a in enumerate(phi):
        dv = np.array([np.cos(a), np.sin(a)])
        den = dv[0] * E[:, 1] - dv[1] * E[:, 0]
        ok = np.abs(den) > 1e-14
        dn = np.where(ok, den, 1.0)
        u = np.where(ok, (A[:, 0] * E[:, 1] - A[:, 1] * E[:, 0]) / dn, -1.0)
        v = np.where(ok, (A[:, 0] * dv[1] - A[:, 1] * dv[0]) / dn, -1.0)
        hit = ok & (u > 0.004) & (u < r_max) & (v >= 0) & (v <= 1)
        if hit.any():
            out[i] = u[hit].max()
    return out


def fill_periodic(r, phi):
    """NaN gaps of a periodic sequence filled by periodic linear interpolation"""
    ok = ~np.isnan(r)
    return np.interp(phi, phi[ok], r[ok], period=2 * np.pi)


class Tail:
    """The built tail of one side: section loops along x round a straight axis, the dense loft behind its signed
    distance. Sections are (|z|, y) loops, counter-clockwise, starting inboard (phi = pi), like nacelle_box's."""

    def __init__(self, cfg, side):
        """Config of one plane (TAILS entry); side is +1 or -1"""
        self.c = cfg["tail"]
        self.n = cfg["nozzle"]
        self.side = side
        self.r_tail = nb.knots(self.c["r_tail"])
        self.phi = np.pi + 2 * np.pi * np.arange(K_SEC) / K_SEC
        # nacelle_box.Side reads these: the lip x (k growth, unused here) and the circle (nozzle exclusion, unused)
        self.c = dict(self.c, x_lip=self.c["x_front"], circle=(self.c["axis"][0], self.c["axis"][1], 0.0))
        self.dip = False

    def measure(self, P, T, report, tag):
        """Read the old skin's sections ahead of x_front (the rows that lie under it) and the slope at x_front.
        The circle is fitted to the upper half only (the lower half runs into the wing root and the belly); every
        ray is held within CLIP of it (rays that slip past the nacelle onto the fuselage or into the wing read far
        too long). The lower half keeps the old skin's depth: pulled up to the round tail's radius it left the
        belly plate's top exposed under the loft, a 4 mm fin along the crease."""
        c = self.c
        yc, zc = c["axis"]
        self.front_x = np.linspace(c["x_front"] + c["overlap"], c["x_front"], 5)
        d = np.stack([np.cos(self.phi), np.sin(self.phi)], 1)
        rows = []
        for x in np.r_[self.front_x, c["x_front"] - 0.004]:
            r = section_radius(P, T, x, yc, zc, self.side, c["r_max"], self.phi)
            up = (d[:, 1] > 0.0) & ~np.isnan(r)
            Q = d[up] * r[up, None]                       # (|z|, y) from the axis
            A = np.c_[2 * Q, np.ones(len(Q))]
            sol = np.linalg.lstsq(A, (Q ** 2).sum(1), rcond=None)[0]
            cen, R = sol[:2], np.sqrt(sol[2] + sol[0] ** 2 + sol[1] ** 2)
            bq = -(d @ cen)
            rc = -bq + np.sqrt(np.maximum(bq ** 2 - (cen @ cen - R * R), 0.0))   # the circle along each ray
            r = np.where(np.isnan(r), rc, np.clip(r, CLIP[0] * rc, CLIP[1] * rc))
            r = smooth_periodic(r, 8.0)
            rows.append(r)
            report.append("%-6s old section at x %.4f: circle r %.4f off the axis by %.4f; loft r %.4f..%.4f" % (
                tag, x, R, np.linalg.norm(cen), r.min(), r.max()))
        rows = np.array(rows)
        self.front_r = rows[:5]
        # slope dr/d(-x) at x_front from the section 6 mm ahead (the generator's skin just behind x_front is the
        # torn sleeve end, so the slope is read in front of it)
        self.slope = np.clip((rows[4] - rows[0]) / c["overlap"], -SLOPE_MAX, SLOPE_MAX)

    def radius(self, x):
        """Radius per angle (K_SEC) of the section at x. With self.dip the rows ahead of x_front lie DIP under the
        old skin (the built loft, hidden under it up to the cut); without it (the signed distance the old skin is
        projected onto) they are the old skin's own section."""
        c = self.c
        dip = DIP if self.dip else 0.0
        xf, xm = c["x_front"], c["morph_end"]
        if x >= xf:
            fx = self.front_x[::-1]
            fr = self.front_r[::-1]
            k = np.clip(np.searchsorted(fx, x), 1, len(fx) - 1)
            w = (x - fx[k - 1]) / (fx[k] - fx[k - 1])
            return fr[k - 1] * (1 - w) + fr[k] * w - dip
        if x <= xm:
            return np.full(K_SEC, float(self.r_tail(x)))
        span = xf - xm
        u = (xf - x) / span
        h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
        r1 = float(self.r_tail(xm))
        m1 = (float(self.r_tail(xm - 0.002)) - r1) / 0.002
        r0 = self.front_r[-1] - dip * (1 - min(u / 0.2, 1.0))   # the hair of DIP closes within the first fifth
        return h00 * r0 + h10 * self.slope * span + h01 * r1 + h11 * m1 * span

    def loop(self, x, n):
        """Section at x: n points by arc length from the inboard point at the centre's height"""
        yc, zc = self.c["axis"]
        r = self.radius(x)
        Q = np.stack([zc + r * np.cos(self.phi), yc + r * np.sin(self.phi)], 1)
        return nb.resample_closed(Q, n)

    def rows(self, step):
        """Row stations from the front of the overlap back to the rim"""
        c = self.c
        x0 = c["x_front"] + c["overlap"]
        n = int(np.ceil((x0 - c["x_exit"]) / step)) + 1
        return np.linspace(x0, c["x_exit"], n)

    def grid(self, step, nc):
        """Outer loft points (rows, nc, 3) in model axes"""
        xs = self.rows(step)
        G = np.zeros((len(xs), nc, 3))
        for k, x in enumerate(xs):
            L = self.loop(x, nc)
            G[k, :, 0] = x
            G[k, :, 1] = L[:, 1]
            G[k, :, 2] = L[:, 0] * self.side
        return G

    def build_sdf(self):
        """Dense loft samples and their outward normals: the signed distance is the offset along the nearest
        sample's normal, capped by the rim plane behind"""
        G = self.grid(ROW_DENSE, NC_DENSE)
        N = nb.grid_normals(G, self.side)
        self.S = G.reshape(-1, 3)
        self.SN = N.reshape(-1, 3)
        self.tree = cKDTree(self.S)

    def sdf(self, P):
        """Signed distance-like value of the built tail (negative inside), closed behind by the rim plane"""
        _, k = self.tree.query(P)
        d = np.einsum("ij,ij->i", P - self.S[k], self.SN[k])
        return np.maximum(d, self.c["x_exit"] - P[:, 0])


class TailSlab(nb.Slab):
    """nacelle_box.Slab whose upper sheet inboard of the nacelle axis drops onto the lower one: between the nacelle
    and the fuselage there is no upper wing skin, only the belly under them (a plate `plate` thick); the fitted
    upper sheet there was the fuselage top or the nacelle's own side"""

    def fit(self, P, N, use, report, tag):
        """Both sheets as nacelle_box, but the old nacelle is left out of the upper sheet's data within tube_up of
        the axis and of the lower sheet's only within tube: the belly under the nacelle is lower-sheet data, while
        the old sleeve's sides (out to about 40 mm from the axis) read as upper wing skin and raised the wing beside
        the tail into a 15 mm wedge"""
        c0 = self.c
        rep_up = []
        self.c = dict(c0, tube=c0["tube_up"])
        super().fit(P, N, use, rep_up, tag)
        sp_up = self.sp[0]
        self.c = c0
        rep_lo = []
        super().fit(P, N, use, rep_lo, tag)
        self.sp[0] = sp_up
        report += [rep_up[0], rep_lo[1]]

    def heights(self, x, z):
        """Upper and lower sheet at (x, |z|)"""
        up, lo = super().heights(x, z)
        z0, z1 = self.c["thin"]
        t = nb.sstep(z0, z1, z)
        return lo + self.c["plate"] + (up - lo - self.c["plate"]) * t, lo


class TailSide(nb.Side):
    """One side's region: the wing and belly slab, the fuselage side, the built tail; f = smin(body, tail)"""

    def __init__(self, cfg, side):
        """Config of one plane (TAILS entry); side is +1 or -1"""
        self.cfg, self.side = cfg, side
        self.tag = "tail" + ("R" if side > 0 else "L")
        self.nac = Tail(cfg, side)
        self.slab = TailSlab(cfg, side)
        self.r = cfg["region"]
        self.fus = nb.Fuselage(cfg, side)

    def k(self, P):
        """Fillet size at P: k, growing to k_in inboard of the axis (the channel to the fuselage)"""
        z = P[:, 2] * self.side
        zc = self.nac.c["axis"][1]
        return self.r["k"] + (self.r["k_in"] - self.r["k"]) * (1 - nb.sstep(zc - 0.01, zc, z))

    def weight(self, P):
        """1 inside the region box, fading over `fade` outside it (only forward of its front: behind and round
        it the box reaches past the old tail)"""
        x0, x1, z0, z1, y0, y1 = self.r["box"]
        fd = self.r["fade"]
        x, y, z = P[:, 0], P[:, 1], P[:, 2] * self.side
        w = (nb.sstep(x0 - 0.002, x0, x) * (1 - nb.sstep(x1, x1 + fd, x)) * nb.sstep(z0 - fd, z0, z)
             * (1 - nb.sstep(z1, z1 + fd, z)) * nb.sstep(y0 - fd, y0, y) * (1 - nb.sstep(y1, y1 + fd, y)))
        return w * (z > 0)


_SIDES: list = []   # the sides being rebuilt, for clip_plane (nacelle_box calls clip_mesh without them)
_CLIP_MESH = nb.clip_mesh


def clip_plane(V, F, sv, attrs):
    """nacelle_box.clip_mesh with the cut also bounded by the plane x = x_front: ahead of it the old skin is
    kept, behind it the loft takes over. The fillet test alone (past > 0) ends at the region's weight step, whose
    zero line follows old triangle edges, a zigzag across the loft's front; the plane gives a straight cut."""
    ol = attrs[1]
    xc = np.array([s.nac.c["x_front"] for s in _SIDES])[np.clip(ol, 0, len(_SIDES) - 1)]
    return _CLIP_MESH(V, F, np.minimum(sv, xc - V[:, 0]), attrs)


def revolve(s, prof, name, paint):
    """A body of revolution round the tail axis on the loft's columns: prof is a list of (x, r, depth) rows;
    returns a part dict (V, N, F, uv in model units, paint, depth per vertex)"""
    yc, zc = s.nac.c["axis"]
    sd = s.side
    phi = np.pi + 2 * np.pi * np.arange(NC + 1) / NC        # seam copy at the end
    prof = np.asarray(prof, float)
    nr_ = len(prof)
    X = np.repeat(prof[:, 0:1], NC + 1, 1)
    Rr = prof[:, 1:2]
    Y = yc + Rr * np.sin(phi)[None]
    Z = (zc + Rr * np.cos(phi)[None]) * sd
    G = np.stack([X, Y, Z], -1)
    V = G.reshape(-1, 3)
    idx = np.arange(nr_ * (NC + 1)).reshape(nr_, NC + 1)
    a, b, cc, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]
    F = np.vstack([np.stack([a, b, cc], -1).reshape(-1, 3), np.stack([a, cc, d], -1).reshape(-1, 3)])
    # normals: the profile's own normal turned round (outward from the material the profile bounds is set by
    # orient() from the face winding, so here the profile's left normal is used and the faces follow it)
    tx = np.gradient(prof[:, 0])
    tr = np.gradient(prof[:, 1])
    ln = np.hypot(tx, tr)
    ln = np.where(ln < 1e-12, 1.0, ln)
    nx, nrr = -tr / ln, tx / ln          # the profile's tangent (dx, dr) turned a quarter
    N = np.stack([np.repeat(nx[:, None], NC + 1, 1), nrr[:, None] * np.sin(phi)[None],
                  nrr[:, None] * np.cos(phi)[None] * sd], -1).reshape(-1, 3)
    seg = np.r_[0.0, np.cumsum(np.hypot(np.diff(prof[:, 0]), np.diff(prof[:, 1])))]
    ru = np.maximum(prof[:, 1], 0.004)
    U = ru[:, None] * (phi[None] - np.pi)
    UV = np.stack([U, np.repeat(seg[:, None], NC + 1, 1)], -1).reshape(-1, 2)
    dep = np.repeat(prof[:, 2], NC + 1)
    p = {"name": name, "V": V, "N": N, "F": F, "uv": UV[F], "paint": paint, "depth": dep}
    return nb.orient(p)


def build_parts(s, report):
    """The built tail of one side: the outer loft (baked paint) and the nozzle parts (dark metal)"""
    c, n = s.nac.c, s.nac.n
    sd = s.side
    s.nac.dip = True
    G = s.nac.grid(ROW, NC)
    s.nac.dip = False
    Nn = nb.grid_normals(G, sd)
    nr_, nc = G.shape[:2]
    parts = []
    idx = np.arange(nr_ * (nc + 1)).reshape(nr_, nc + 1)
    Gs = np.concatenate([G, G[:, :1]], 1)
    V = Gs.reshape(-1, 3)
    N = np.concatenate([Nn, Nn[:, :1]], 1).reshape(-1, 3)
    seg = np.linalg.norm(np.diff(Gs, axis=1), axis=2)
    u = np.concatenate([np.zeros((nr_, 1)), np.cumsum(seg, 1)], 1)
    v = np.concatenate([np.zeros((1, nc + 1)), np.cumsum(np.linalg.norm(np.diff(Gs, axis=0), axis=2), 0)], 0)
    UV = np.stack([u, v], -1).reshape(-1, 2)
    a, b, cc, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]
    F = np.vstack([np.stack([a, b, cc], -1).reshape(-1, 3), np.stack([a, cc, d], -1).reshape(-1, 3)])
    parts.append(nb.orient({"name": "loft", "V": V, "N": N, "F": F, "uv": UV[F], "paint": "bake"}))
    # the rim: a half round of the lip thickness from the loft's last row (round there) into the shroud
    xe, t = c["x_exit"], c["lip"]
    ro = float(s.nac.r_tail(xe))
    # the outer face of the half round starts on the loft's rim row; the round bulges behind it by t / 2
    rim = [(xe - 0.5 * t * np.sin(np.pi * k / 12), ro - 0.5 * t + 0.5 * t * np.cos(np.pi * k / 12), 0.0005 * k / 12)
           for k in range(13)]
    ri = ro - t
    xf = xe + n["floor"]
    rn_out = n["r"] + n["wall"]
    inner_wall = [(xe + f * n["floor"], ri, 0.0005 + 0.004 * f) for f in np.linspace(0, 1, 6)[1:]]
    floor = [(xf, r, 0.0045 + 0.001 * f) for f, r in zip(np.linspace(0, 1, 5)[1:], np.linspace(ri, rn_out, 5)[1:])]
    p_shroud = revolve(s, rim + inner_wall + floor, "rim", "nozzle")
    parts.append(p_shroud)
    # the engine nozzle: outer wall from the floor back to its exit, the flat exit rim, the convergent inner wall
    xn = n["x"]
    out_w = [(x, rn_out, 0.005 - 0.004 * f) for f, x in zip(np.linspace(0, 1, 5), np.linspace(xf, xn, 5))]
    exit_r = [(xn, r, 0.001) for r in np.linspace(rn_out, n["r"], 3)[1:]]
    conv = [(xn + n["depth"] * f, n["r"] + (n["r_in"] - n["r"]) * f * f * (3 - 2 * f), 0.001 + n["depth"] * f)
            for f in np.linspace(0, 1, 9)[1:]]
    parts.append(revolve(s, out_w + exit_r + conv, "nozzle", "nozzle"))
    # the exhaust cone: from the convergent wall's end in to the cone base, then to its tip pointing back
    tip, rb = n["cone"]
    xb = xn + n["depth"]
    cone = [(xb, n["r_in"], n["depth"]), (xb, rb, n["depth"] + 0.001)]
    cone += [(xb + (xn + tip - xb) * f, rb * (1 - f) + 1e-5, n["depth"] + 0.002) for f in np.linspace(0, 1, 7)[1:]]
    parts.append(revolve(s, cone, "cone", "nozzle"))
    report.append("%-6s built: loft %d x %d from x %.4f to the rim at %.4f (r %.4f), nozzle exit x %.4f r %.4f, "
                  "floor %.4f" % (s.tag, nr_, nc, c["x_front"] + c["overlap"], xe, ro, xn, n["r"], xf))
    return parts


def orient_parts(parts, s):
    """Turn every nozzle part's faces so their normals point out of the metal into the air: away from the axis on
    the outside of the rim, towards it inside the shroud and the nozzle, backwards on the floor and the cone"""
    yc, zc = s.nac.c["axis"]
    out = []
    for p in parts:
        if p["paint"] != "nozzle":
            out.append(p)
            continue
        V, F = p["V"], p["F"]
        fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        C = V[F].mean(1)
        rad = np.stack([np.zeros(len(C)), C[:, 1] - yc, C[:, 2] - zc * s.side], 1)
        rr = np.linalg.norm(rad, axis=1)
        rad /= np.maximum(rr, 1e-12)[:, None]
        # where the air is: outside the rim's outer half (r over the shroud's inner radius and behind the floor)
        if p["name"] == "rim":
            want = np.where(rr[:, None] > s.nac.c_ri + 1e-5, rad, -rad)
            flat = np.abs(fn[:, 0]) > 0.7 * np.linalg.norm(fn, axis=1)
            want[flat] = np.array([-1.0, 0.0, 0.0])
        elif p["name"] == "nozzle":
            want = np.where(rr[:, None] > s.nac.n["r"] + 0.5 * s.nac.n["wall"], rad, -rad)
            flat = np.abs(fn[:, 0]) > 0.7 * np.linalg.norm(fn, axis=1)
            want[flat] = np.array([-1.0, 0.0, 0.0])
        else:
            want = np.tile(np.array([-1.0, 0.0, 0.0]), (len(C), 1))
        bad = np.einsum("ij,ij->i", fn, want) < 0
        F = F.copy()
        F[bad] = F[bad][:, [0, 2, 1]]
        uv = p["uv"].copy()
        uv[bad] = uv[bad][:, [0, 2, 1]]
        # vertex normals from the oriented faces (area weighted, seam copies welded)
        fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        _, wk = np.unique(np.round(V / 1e-8).astype(np.int64), axis=0, return_inverse=True)
        wk = wk.reshape(-1)
        acc = np.zeros((wk.max() + 1, 3))
        for k in range(3):
            np.add.at(acc, wk[F[:, k]], fn)
        Nv = acc[wk]
        Nv /= np.maximum(np.linalg.norm(Nv, axis=1, keepdims=True), 1e-20)
        out.append(dict(p, F=F, uv=uv, N=Nv))
    return out


def paint_nozzle(parts_all, tuv, offs, col, orm):
    """Nozzle parts: heat-darkened steel by depth behind the rim (NOZZLE_PAINT), a faint mottle"""
    dk = np.array([d for d, _ in NOZZLE_PAINT])
    gv = np.array([g for _, g in NOZZLE_PAINT])
    rng = np.random.default_rng(5)
    for p, (f0, v0) in zip(parts_all, offs):
        if p["paint"] != "nozzle":
            continue
        dep = p["depth"]

        def cb(k, rr, cc, bc):
            """Texels (rr, cc) of face k, barycentric bc: grey by depth behind the rim, a little noise"""
            t = p["F"][k]
            g = np.interp(bc @ dep[t], dk, gv) * (1 + 0.04 * (rng.random(len(rr)) - 0.5))
            col[rr, cc] = np.clip(g[:, None] * NOZZLE_TINT[None] + 0.5, 0, 255).astype(np.uint8)
            occ = np.interp(bc @ dep[t], (0.0, 0.02), (NOZZLE_ORM[0], 90))
            orm[rr, cc] = np.stack([occ, np.full(len(rr), NOZZLE_ORM[1]), np.full(len(rr), NOZZLE_ORM[2])],
                                   1).astype(np.uint8)
        nr.raster(tuv[f0:f0 + len(p["F"])], np.arange(len(p["F"])), cb, grow=1.5)


def main() -> int:
    """Command line: build the nacelle tails and nozzles of one hangar plane"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    ap.add_argument("--maps", nargs=2, required=True)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    rep = []
    cfg = TAILS[a.key]
    m = pp.Model(a.src)
    geo = nb.skin_arrays(m)
    geo["key"] = a.key
    sides = [TailSide(cfg, 1), TailSide(cfg, -1)]
    _SIDES[:] = sides
    nb.clip_mesh = clip_plane
    nb.REFINE_ITERS = 2   # as nacelle_box: with one split the edge by the nacelle read as saw teeth from the side
    for s in sides:
        s.nac.measure(geo["W0"], geo["F"], rep, s.tag)
        s.nac.build_sdf()
        s.nac.c_ri = float(s.nac.r_tail(s.nac.c["x_exit"])) - s.nac.c["lip"]
        s.slab.fit(geo["W0"], geo["Nw"], geo["free"] > 0.5, rep, s.tag)
        s.fus.fit(geo["W0"], geo["Nw"], geo["free"] > 0.5, rep, s.tag)
    nb.log("fitted")
    reg = nb.rebuild_region(geo, sides, rep)
    nb.log("region rebuilt")
    if a.report:
        W0, F = geo["W0"], geo["F"]
        N0 = sr.vertex_normals(W0, F, geo["Nw"])
        pick0 = (np.stack([s.weight(W0) for s in sides], 1).max(1) > 0.9) & (geo["free"] > 0.9)
        d0 = np.abs(sr.dent_metric(W0, N0, pick0))[pick0]
        pick1 = reg["w"] > 0.9
        d1 = np.abs(sr.dent_metric(reg["V"], reg["N"], pick1))[pick1]
        rep.append("region skin dent p95 %.2f -> %.2f mm, p99 %.2f -> %.2f mm (%d -> %d vertices)" % (
            np.percentile(d0, 95) * 1e3, np.percentile(d1, 95) * 1e3, np.percentile(d0, 99) * 1e3,
            np.percentile(d1, 99) * 1e3, int(pick0.sum()), int(pick1.sum())))
    parts = []
    for s in sides:
        parts += orient_parts(build_parts(s, rep), s)
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
        groups.append({"tag": s.tag + "_skin", "faces": fids, "scale": np.sqrt(a3 / a2), "dark_out": True})
    nreg = len(groups)
    pgroups = []
    for p, (f0, _) in zip(parts, offs):
        fids = np.arange(f0, f0 + len(p["F"]))
        cuv[fids] = p["uv"]
        g = {"tag": p["name"], "faces": fids, "scale": 1.0, "dark_out": True}
        groups.append(g)
        if p["paint"] == "bake":
            pgroups.append(g)
    nb.log("unwrapped")
    keep = geo["T0"][~reg["fr"]]
    cov = nr.coverage_of(m.g, keep, S)
    density = nr.skin_density(geo, keep, S)
    tuv = nb.place_charts(allr["F"], cuv, groups, cov, density, rep)
    nb.log("charts placed")
    nr.bake(geo, allr, tuv, groups[:nreg] + pgroups, col, orm, rep)
    nb.log("baked")
    nb.clean_specks(tuv, groups[:nreg] + pgroups, col, rep)
    nb.paint_te_nose(sides, allr, tuv, col, orm, rep)
    nb.paint_dark_faces(allr, tuv, groups[:nreg] + pgroups, col, orm, rep)
    paint_nozzle(parts, tuv, offs, col, orm)
    nr.write_region(m, geo, allr, tuv, S, a.dst, rep)
    Image.fromarray(col).save(a.maps[0], quality=95)
    Image.fromarray(orm).resize(orm_size, Image.LANCZOS).save(a.maps[1], quality=95)
    if a.report:
        c, n = sides[0].nac.c, sides[0].nac.n
        ro = float(sides[0].nac.r_tail(c["x_exit"]))
        rep.append("Livery.ENGINE_HOLES row: [%.4f, %.4f, %.4f, [1.0, 1.0], [%.3f, %.3f]]" % (
            c["axis"][0], c["axis"][1], ro / 0.84, c["x_exit"] - 0.006, n["x"] + n["depth"] + 0.004))
        rep.append("NozzleFlame.NOZZLES row (unchanged when equal): [%.3f, %.4f, %.4f, %.4f]" % (
            n["x"], c["axis"][0], c["axis"][1], n["r"]))
    print("\n".join(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
