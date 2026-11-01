"""Side air intakes of the «Грач» attackers, built after the prototype's layout (Kanta, 01.11: the round pod ring
with an engine face and a spinner read as a jet pod, and torn skin hung round it).

What the intake of this aircraft type looks like (walkaround photos of museum aircraft; the notes stay outside the
repository): a rounded oval opening, taller than wide, low on the fuselage side behind the cockpit; a thick blunt
lip of even thickness, painted like the skin with a worn edge; the inboard wall of the intake is a flat splitter
that stands off the fuselage side with a narrow boundary-layer gap, closed further back by the nacelle-to-fuselage
fairing; inside, the duct is painted light grey, narrows and fades into shadow within about one opening height, so
the compressor face is not seen; behind the lip the nacelle is a little wider and blends into the fuselage.

How it is built (per side, mirrored), on the hangar GLB of the generator (before any earlier intake pass):
1. Cut: every skin face in front of the cut plane (the lip plane moved back by the fairing length, less CUT_OVER;
   its own slope cut_b may differ from the lip's) that lies outboard of the splitter plane and within reach of the
   nacelle axis goes - the generator's whole scoop, its torn lip and the ragged junction - and the skin inside the
   new duct behind it. Faces across the cut are clipped on it, so the cut edges are straight: on the splitter plane
   (closed by a flat patch, plane_patch, and covered by the plate) or on the cut plane.
2. New parts, one grid round the opening (columns round it, rows along the profile):
   - fairing: from the skin's own section at the cut (its rear band dips under the cut edge like a panel seam) to
     the lip outline (opening plus lip thickness), a smooth loft (the nacelle narrows to the lip, as on the
     prototype); clamped into the splitter plate inboard;
   - lip nose: a half round of the lip thickness;
   - duct: a loft from the opening back DEPTH to a small oval raised and inboard (DUCT_END: the duct turns towards
     the engine), its inboard side flat on the plate, closed far inside by a dark cap that leans to face down and
     forward (no engine face, no spinner, no sky reflection seen from above);
   - splitter plate: a flat slab with a rounded rim standing off the fuselage side, its front edge ahead of the
     lip, its bottom edge down to the fuselage's cut edge (the gap is the space between it and the fuselage).
3. The generator's crumpled, creased fillet in that gap (inboard of the plate) is faired (fair: weighted Laplacian
   then Taubin smoothing, no face allowed to fold over), and needle spikes round the intake are pulled in.
4. Paint: the new faces join the textured skin (primitive 0, same material; the livery, the hangar detail layer
   and battle_bake treat them as skin) with their own UV islands in free atlas space: the fairing and lip take the
   paint of the skin just behind them (column by column, so camouflage edges carry on), the lip edge a light worn
   band, the duct light grey near the lip fading to near black in its depth (Livery.INTAKE_DUCTS keeps this
   texture colour in the duct under every paint scheme), the plate the cowl paint round the intake.

  python3 -I intake_rebuild.py <hangar.glb> <key> <out.glb> --maps <col.jpg> <orm.jpg> [--report]
The maps are rewritten in place (start from copies of the extracted maps), then tex_clean.py pads them. --report
prints the cut, the plate, the cut points off every intended edge and the constants for Livery.INTAKE_DUCTS.
Set INTAKE_DEBUG=<absolute path prefix> to save a picture of each plane patch.
Axes: glTF model space (nose +X, up +Y, right wing +Z), length 1."""
import argparse
import os
import sys

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plane_polish as pp  # noqa: E402

Image.MAX_IMAGE_PIXELS = None

# Per plane, right side (mirrored), model units:
#   axis (y, |z|) and r: the nacelle axis and nominal radius (the polar frame of the joint fit and the cut reach);
#   lip: the lip plane x = a + b dy + c dz (dy, dz from the axis; b < 0: the lower lip stands further forward);
#   open: opening centre offset (dy, dz) from the axis, half height, half width, superellipse exponents of the
#         outboard and the inboard half (a higher exponent is flatter);
#   t: lip thickness; fair: fairing length behind the lip nose; depth: duct depth behind the lip;
#   plate: |z| of the splitter's inboard face and its thickness; ext: how far the plate stands ahead of the lip;
#   reach: cut reach round the axis, in r;
#   cut_b (optional, default the lip's b): slope of the cut plane x = a + cut_b dy + c dz less the fairing length
#         (a smaller slope than the lip's moves the cut back at the bottom, past the generator's ragged lower junction).
INTAKES = {
    "attacker_1": {"axis": (-0.0387, 0.0884), "r": 0.0335, "lip": (0.112, -0.35, 0.0),
                   "open": (0.0, -0.008, 0.025, 0.0205, 2.1, 2.8), "t": 0.0035, "fair": 0.042, "depth": 0.055,
                   "plate": (0.060, 0.0014), "ext": 0.0015, "reach": 1.75},
    "attacker_2": {"axis": (-0.022, 0.096), "r": 0.032, "lip": (0.0786, -0.5, 0.0),
                   "open": (-0.009, -0.0021, 0.027, 0.0195, 2.1, 2.8), "t": 0.0035, "fair": 0.040, "depth": 0.052,
                   "plate": (0.0745, 0.0014), "ext": 0.0015, "reach": 1.75, "cut_b": 0.0},
}
NT = 144          # columns round the opening
CUT_OVER = 0.004  # the skin is cut this far in front of the fairing's rear edge (the band covers the cut)
DIP = 0.0004      # the fairing's rear edge sinks this far under the joint surface
PROUD = 0.00025   # the fairing stands this far off the joint surface just in front of its rear edge (a panel seam)
SNAP = 0.005      # open edges of the cut this close to the new parts are snapped onto them
SPIKE = 0.4       # a vertex this far off its neighbours' mean (in mean edge lengths) near an intake is a spike
DUCT_END = (0.35, -0.1, 0.4, 0.36)   # the duct's far oval: centre (dy, d|z|) from the nacelle axis, half axes; in r
CAP_LEAN = 1.2   # x per unit height of the duct's end ring and cap (they face down and forward)
EVEN_BACK = (0.06, 0.10)   # the skin's paint is evened from the fairing's rear edge back this far (full, fading)
GAP_FAIR = 0.02   # the skin this far inboard of the splitter plane, beside the plate, is faired (the gap)
INSET = 0.0003    # clamps: fairing this far inside the plate, duct wall this far in front of it
# paint (sRGB)
DUCT_LIGHT = (168, 168, 162)   # duct paint near the lip
DUCT_MID = (70, 70, 68)
DUCT_DEEP = (12, 12, 13)
CAP_TONE = (7, 7, 8)
DUCT_ORM = (120, 175, 0)       # occlusion at the far end (255 at the lip), roughness, metal
WEAR = 0.32                    # strength of the worn band on the lip edge


class Frame:
    """Polar frame round the nacelle axis of one side, in mirrored coordinates (Z = |z| on that side): theta 0 up,
    positive outboard"""

    def __init__(self, yc, zc):
        self.yc, self.zc = yc, zc

    def polar(self, P):
        """(x, theta, r) of mirrored points P"""
        dy, dz = P[:, 1] - self.yc, P[:, 2] - self.zc
        return P[:, 0], np.arctan2(dz, dy), np.hypot(dy, dz)


def lip_x(c, frame, Y, Z):
    """x of the lip plane at mirrored (Y, Z)"""
    return c[0] + c[1] * (Y - frame.yc) + c[2] * (Z - frame.zc)


def opening(cfg, frame):
    """Opening outline: NT points (Y, Z) round its centre (column 0 at the top, then outboard), their outward
    unit normals and the centre"""
    dy0, dz0, ha, hb, n_out, n_in = cfg["open"]
    Yo, Zo = frame.yc + dy0, frame.zc + dz0
    ph = np.linspace(0, 2 * np.pi, NT, endpoint=False)
    c, s = np.cos(ph), np.sin(ph)
    n = np.where(s >= 0, n_out, n_in)
    Y = Yo + ha * np.sign(c) * np.abs(c) ** (2 / n)
    Z = Zo + hb * np.sign(s) * np.abs(s) ** (2 / n)
    # outward normals from the neighbours (closed loop)
    tY = np.roll(Y, -1) - np.roll(Y, 1)
    tZ = np.roll(Z, -1) - np.roll(Z, 1)
    nY, nZ = -tZ, tY
    ln = np.hypot(nY, nZ)
    nY, nZ = nY / ln, nZ / ln
    flip = (nY * (Y - Yo) + nZ * (Z - Zo)) < 0
    nY[flip], nZ[flip] = -nY[flip], -nZ[flip]
    return np.stack([Y, Z], 1), np.stack([nY, nZ], 1), np.array([Yo, Zo])


def cut_section(Pm, T, frame, cfg, xcut_of):
    """Section of the skin by the cut (the lip plane moved back by the fairing length less CUT_OVER), outboard of
    the splitter plane and within reach of the axis: segments as (Y, Z) pairs"""
    d = Pm[:, 0] - xcut_of(Pm)
    sd = d[T]
    cross = (sd.min(1) < 0) & (sd.max(1) > 0)
    segs = []
    for tri, dd in zip(T[cross], sd[cross]):
        pts = []
        for i, j in ((0, 1), (1, 2), (2, 0)):
            if (dd[i] < 0) != (dd[j] < 0):
                t = dd[i] / (dd[i] - dd[j])
                pts.append(Pm[tri[i]] + t * (Pm[tri[j]] - Pm[tri[i]]))
        if len(pts) == 2:
            segs.append(np.array(pts)[:, 1:])
    S = np.array(segs)
    r = np.hypot(S[:, :, 0] - frame.yc, S[:, :, 1] - frame.zc).max(1)
    keep = (S[:, :, 1].min(1) > cfg["plate"][0]) & (r < cfg["reach"] * cfg["r"])
    return S[keep]


def ray_radius(S, frame, dirs, fallback):
    """Outermost hit of the rays from the axis along dirs on the section segments S (fallback where none)"""
    o = np.array([frame.yc, frame.zc])
    A, B = S[:, 0] - o, S[:, 1] - o
    E = B - A
    out = np.array(fallback, float).copy()
    for i, dv in enumerate(dirs):
        den = dv[0] * E[:, 1] - dv[1] * E[:, 0]
        ok = np.abs(den) > 1e-12
        dn = np.where(ok, den, 1.0)
        u = np.where(ok, (A[:, 0] * E[:, 1] - A[:, 1] * E[:, 0]) / dn, -1.0)   # along the ray
        v = np.where(ok, (A[:, 0] * dv[1] - A[:, 1] * dv[0]) / dn, -1.0)       # along the segment
        hit = ok & (u > 0) & (v >= 0) & (v <= 1)
        if hit.any():
            out[i] = u[hit].max()
    return out


def build(frame, S, c, cfg, xcut_of):
    """The intake grid in mirrored coordinates: positions (rows x NT), a paint class per row (0 fairing, 1 lip nose,
    2 duct, 3 cap), the nose rows' angle (0 outer .. pi inner, for the wear band) and the duct rows' depth share.
    The fairing starts from the skin's own section at the cut (S), so its rear band covers the cut edge exactly."""
    t, (zp, tp) = cfg["t"], cfg["plate"]
    O2, N2, Oc = opening(cfg, frame)
    z_out = zp + tp - INSET          # fairing and the nose's outer half: inside the plate
    z_duct = zp + tp + INSET         # duct wall: just in front of the plate's outboard face
    xn = lip_x(c, frame, O2[:, 0], O2[:, 1]) - t / 2       # nose start per column
    L2 = O2 + t * N2                                        # lip outline
    # rear contour: the skin's section along the ray from the axis through the lip outline; a running maximum and
    # a light smoothing round the intake keep it a fair curve that never dips under the section
    o = np.array([frame.yc, frame.zc])
    ray = L2 - o
    th = np.arctan2(ray[:, 1], ray[:, 0])
    dirs = np.stack([np.cos(th), np.sin(th)], 1)
    rsec = ray_radius(S, frame, dirs, np.linalg.norm(ray, axis=1) + 0.002)
    w = 3
    ext = np.r_[rsec[-w:], rsec, rsec[:w]]
    rsec = np.array([ext[i:i + 2 * w + 1].max() for i in range(NT)])
    kk = np.exp(-0.5 * (np.arange(-w, w + 1) / 1.5) ** 2)
    kk /= kk.sum()
    rsec = np.convolve(np.r_[rsec[-w:], rsec, rsec[:w]], kk, "valid")
    R2 = o + rsec[:, None] * dirs
    xcut = xcut_of(np.c_[np.zeros(NT), R2])
    xr = xcut - CUT_OVER
    rows, cls, aux = [], [], []

    def put(x, YZ, k, a=0.0, zmin=None):
        YZ = YZ.copy()
        if zmin is not None:
            YZ[:, 1] = np.maximum(YZ[:, 1], zmin)
        rows.append(np.stack([np.broadcast_to(x, (NT,)), YZ[:, 0], YZ[:, 1]], 1))
        cls.append(k)
        aux.append(a)
    # 1. fairing: rear edge dipped under the skin, proud of the section at the cut, then lofted to the lip outline
    K = 16
    for k in range(K + 1):
        u = k / K
        x = xr + (xn - xr) * u
        if k == 0:
            put(x, o + (rsec - DIP)[:, None] * dirs, 0, zmin=z_out)
            continue
        uu = np.clip((x - xcut) / (xn - xcut), 0, 1)
        h = (uu * uu * (3 - 2 * uu))[:, None]
        Rj = o + (rsec + PROUD)[:, None] * dirs
        put(x, Rj + (L2 - Rj) * h, 0, zmin=z_out)
    # 2. lip nose: half round of diameter t from the lip outline to the opening
    C2 = O2 + 0.5 * t * N2
    for k in range(1, 12):
        ps = np.pi * k / 12
        x = xn + 0.5 * t * np.sin(ps)
        put(x, C2 + 0.5 * t * np.cos(ps) * N2, 1, ps, zmin=z_out if ps < np.pi / 2 else z_duct)
    # 3. duct: a loft from the opening to a small oval well inside the nacelle (raised and inboard: the duct turns
    # towards the engine, so the cap far inside hides behind the lower lip); its inboard side stays on the plate
    x_end = xn.max() - cfg["depth"]
    R = cfg["r"]
    ph = np.linspace(0, 2 * np.pi, NT, endpoint=False)
    E2 = np.stack([frame.yc + DUCT_END[0] * R + DUCT_END[2] * R * np.cos(ph),
                   frame.zc + DUCT_END[1] * R + DUCT_END[3] * R * np.sin(ph)], 1)
    # the end ring leans back at the bottom, so the cap faces down and forward: from above (the hangar and the
    # combat camera) it is seen edge-on, in the duct's shadow, and catches no sky
    ye = E2[:, 0].mean()
    x_endc = x_end + CAP_LEAN * (E2[:, 0] - ye)
    J = 16
    for j in range(J + 1):
        f = j / J
        x = xn + (x_endc - xn) * f
        h = f * f * (3 - 2 * f)
        put(x, O2 + (E2 - O2) * h, 2, f, zmin=z_duct)
    # 4. cap: closes the duct far inside, on the leaning plane of the end ring
    last = rows[-1][:, 1:]
    Cc = np.array([last[:, 0].mean(), last[:, 1].mean()])
    for s in (0.55, 0.2, 0.0):
        YZ = Cc + s * (last - Cc) + (1e-6 if s == 0 else 0)
        put(x_end + CAP_LEAN * (YZ[:, 0] - ye), YZ, 3, 1.0)
    G = np.array(rows)
    return G, np.array(cls), np.array(aux), xr, xn, x_end, O2, Oc


def duct_inside(G, cls, Oc, Pm):
    """Signed inside-ness of points in the duct (positive inside): the duct radius round the opening centre minus
    the point's, at the point's x, by its angle round the centre; -1 outside the duct's x range"""
    D = G[cls == 2]                       # duct rows x NT x 3
    out = np.full(len(Pm), -1.0)
    xs = D[:, :, 0].mean(1)               # row x (falling)
    rho = np.hypot(Pm[:, 2] - Oc[1], Pm[:, 1] - Oc[0])
    dang = np.arctan2(D[:, :, 2] - Oc[1], D[:, :, 1] - Oc[0])
    drho = np.hypot(D[:, :, 2] - Oc[1], D[:, :, 1] - Oc[0])
    m = (Pm[:, 0] < xs.max()) & (Pm[:, 0] > xs.min()) & (rho < 1.5 * drho.max())
    if not m.any():
        return out
    Q = Pm[m]
    ang = np.arctan2(Q[:, 2] - Oc[1], Q[:, 1] - Oc[0])
    # duct radius per row at the points' angles, then interpolated in x between the rows
    per_row = np.empty((len(xs), len(Q)))
    for k in range(len(xs)):
        o = np.argsort(dang[k])
        per_row[k] = np.interp(ang, dang[k][o], drho[k][o], period=2 * np.pi)
    kk = np.clip(np.searchsorted(-xs, -Q[:, 0]), 1, len(xs) - 1)
    w = (Q[:, 0] - xs[kk - 1]) / (xs[kk] - xs[kk - 1])
    i = np.arange(len(Q))
    out[m] = per_row[kk - 1, i] * (1 - w) + per_row[kk, i] * w - rho[m]
    return out


def plate_mesh(cfg, c, frame, ylo, yhi, xback):
    """Splitter plate in mirrored coordinates: a slab between |z| zp and zp + tp with a rounded rim, its front edge
    ext ahead of the lip plane (following the plane's rake), rounded corners; ylo is the bottom edge's y at the back
    and at the front. Returns positions, normals, triangles,
    planar (x, y) per vertex for its UV"""
    zp, tp = cfg["plate"]
    zp, tp = zp - 0.0002, tp + 0.0002   # the inboard face just inboard of the plane patch it covers
    rc = 0.004
    zf = zp + tp

    def xfront(y):
        return lip_x(c, frame, y, zf) + cfg["ext"]
    # corner points of the outline (x, y), anticlockwise seen from outboard: front-top, back-top, back-bottom,
    # front-bottom; inner polygon pulled in by rc, then the Minkowski sum with a circle of radius rc
    ylb, ylf = ylo
    poly = np.array([[xfront(yhi), yhi], [xback, yhi], [xback, ylb], [xfront(ylf), ylf]])
    n = len(poly)
    edges = [poly[(i + 1) % n] - poly[i] for i in range(n)]
    nrm = [np.array([e[1], -e[0]]) / np.linalg.norm(e) for e in edges]   # outward for an anticlockwise loop
    if edges[0][0] * edges[1][1] - edges[0][1] * edges[1][0] < 0:
        nrm = [-v for v in nrm]
    inner = []
    for i in range(n):
        n0, n1 = nrm[i - 1], nrm[i]
        bis = n0 + n1
        bis /= np.linalg.norm(bis)
        inner.append(poly[i] - bis * rc / max(np.dot(bis, n0), 0.2))
    out, onr = [], []
    for i in range(n):
        a0 = np.arctan2(nrm[i - 1][1], nrm[i - 1][0])
        a1 = np.arctan2(nrm[i][1], nrm[i][0])
        da = (a1 - a0 + np.pi) % (2 * np.pi) - np.pi
        for k in range(9):
            a = a0 + da * k / 8
            v = np.array([np.cos(a), np.sin(a)])
            out.append(inner[i] + rc * v)
            onr.append(v)
    out, onr = np.array(out), np.array(onr)
    m = len(out)
    P, N, T, XY = [], [], [], []
    base = 0
    # flat faces: fan from the centroid (the outline is convex)
    cen = out.mean(0)
    for z, nz in ((zp, -1.0), (zf, 1.0)):
        pts = np.vstack([cen, out])
        P.append(np.c_[pts[:, 0], pts[:, 1], np.full(len(pts), z)])
        N.append(np.tile([0.0, 0.0, nz], (len(pts), 1)))
        XY.append(pts)
        for i in range(m):
            T.append([base, base + 1 + i, base + 1 + (i + 1) % m])
        base += len(pts)
    # rim: half round from the inboard face to the outboard face
    NB = 7
    for k in range(NB):
        b = np.pi * k / (NB - 1)
        pts = out + 0.5 * tp * np.sin(b) * onr
        z = zp + 0.5 * tp * (1 - np.cos(b))
        P.append(np.c_[pts[:, 0], pts[:, 1], np.full(m, z)])
        N.append(np.c_[np.sin(b) * onr, np.full(m, -np.cos(b))])
        XY.append(pts + 0.5 * tp * np.sin(b) * onr)   # a little room for the rim in the UV
    rim0 = base
    for k in range(NB - 1):
        for i in range(m):
            a, b2 = rim0 + k * m + i, rim0 + k * m + (i + 1) % m
            cc, d = a + m, b2 + m
            T += [[a, cc, b2], [b2, cc, d]]
    P = np.vstack(P)
    N = np.vstack(N)
    T = np.array(T, np.int64)
    # wind every face along its vertex normals
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    s = np.einsum("ij,ij->i", fn, N[T].mean(1)) < 0
    T[s] = T[s][:, [0, 2, 1]]
    return P, N, T, np.vstack(XY)


def plane_patch(Pm, T, zp, xcut_of):
    """Flat patch closing the hole a plane cut left in the skin (mirrored coordinates, this side only): the open
    edges lying on |z| = zp form polylines (the cut stubs of the nacelle-to-fuselage fillet above and below); their
    loose ends at the back are joined pairwise, and the enclosed region of the plane is triangulated. Returns
    positions and triangles (winding to be set by the caller)."""
    from scipy.spatial import Delaunay
    ed = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), 1)
    ue, cnt = np.unique(ed, axis=0, return_counts=True)
    op = ue[cnt == 1]
    onp = (np.abs(Pm[:, 2] - zp) < 2e-4)
    E = op[onp[op[:, 0]] & onp[op[:, 1]]]
    if len(E) < 2:
        return np.zeros((0, 3)), np.zeros((0, 3), np.int64)
    # weld by position (seam copies) for the polyline graph
    vids = np.unique(E)
    key = {tuple(np.round(Pm[v] / 1e-7).astype(np.int64)): i for i, v in enumerate(vids)}
    wid = np.array([key[tuple(np.round(Pm[v] / 1e-7).astype(np.int64))] for v in vids])
    vmap = dict(zip(vids, wid))
    W = np.array([[vmap[a], vmap[b]] for a, b in E])
    W = W[W[:, 0] != W[:, 1]]
    nW = wid.max() + 1
    pts = np.zeros((nW, 2))
    for v, w in zip(vids, wid):
        pts[w] = Pm[v, :2]
    deg = np.bincount(W.reshape(-1), minlength=nW)
    ends = np.nonzero(deg == 1)[0]
    segs = [tuple(e) for e in W]
    # join loose ends pairwise, in order along the plane's y at the back
    ends = ends[np.argsort(pts[ends, 1])]
    for i in range(0, len(ends) - 1, 2):
        segs.append((ends[i], ends[i + 1]))
    S = np.array(segs)
    A, B = pts[S[:, 0]], pts[S[:, 1]]

    def inside(q):
        """Even-odd rule against the boundary segments"""
        c = np.zeros(len(q), bool)
        for a, b in zip(A, B):
            cond = (a[1] > q[:, 1]) != (b[1] > q[:, 1])
            xi = a[0] + (q[:, 1] - a[1]) * (b[0] - a[0]) / np.where(b[1] != a[1], b[1] - a[1], 1e-12)
            c ^= cond & (q[:, 0] < xi)
        return c
    used = np.unique(S)
    tri = Delaunay(pts[used])
    F = used[tri.simplices]
    cen = pts[F].mean(1)
    ok = inside(cen)
    bset = {(min(a, b), max(a, b)) for a, b in S}
    for i, j in ((0, 1), (1, 2), (2, 0)):
        onb = np.array([(min(a, b), max(a, b)) in bset for a, b in zip(F[:, i], F[:, j])], bool)
        ok &= inside(0.999 * 0.5 * (pts[F[:, i]] + pts[F[:, j]]) + 0.001 * cen) | onb
    F = F[ok]
    P3 = np.c_[pts, np.full(len(pts), zp)]
    if os.environ.get("INTAKE_DEBUG"):
        from PIL import ImageDraw
        lo, hi = pts[used].min(0) - 0.005, pts[used].max(0) + 0.005
        sc = 8000.0
        im = Image.new("RGB", (int((hi[0] - lo[0]) * sc), int((hi[1] - lo[1]) * sc)), "white")
        d = ImageDraw.Draw(im)

        def px(q):
            return ((q[0] - lo[0]) * sc, (hi[1] - q[1]) * sc)
        for f3 in F:
            d.polygon([px(pts[i]) for i in f3], fill=(200, 220, 255), outline=(150, 170, 220))
        for a_, b_ in segs:
            d.line([px(pts[a_]), px(pts[b_])], fill=(200, 0, 0), width=2)
        for e_ in ends:
            q = px(pts[e_])
            d.ellipse([q[0] - 4, q[1] - 4, q[0] + 4, q[1] + 4], outline=(0, 120, 0), width=2)
        im.save(os.environ["INTAKE_DEBUG"] + "_patch_%d.png" % int(zp * 1e4))
    return P3, F


def grid_tris(nr, ncol, skip_rows=()):
    """Triangles of an nr x ncol grid whose last column is the seam copy of the first"""
    idx = np.arange(nr * ncol).reshape(nr, ncol)
    tris = []
    for i in range(nr - 1):
        if i in skip_rows:
            continue
        a, b = idx[i, :-1], idx[i, 1:]
        cc, d = idx[i + 1, :-1], idx[i + 1, 1:]
        tris.append(np.stack([a, cc, b], 1))
        tris.append(np.stack([b, cc, d], 1))
    return np.vstack(tris)


def smooth_normals(P, T, weld=None):
    """Area-weighted vertex normals; weld maps seam copies onto one index so they share a normal"""
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    key = np.arange(len(P)) if weld is None else weld
    n = np.zeros((key.max() + 1, 3))
    for k in range(3):
        np.add.at(n, key[T[:, k]], fn)
    n = n[key]
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)


def clip_faces(P, N, UV, T, hot, sv, snap):
    """Remove the faces with every corner hot; the partly hot ones are clipped to sv <= 0 (vertices on cut edges
    are shared, no cracks; snap(q) puts a cut point on the surface that cut it). Returns grown P, N, UV, the new
    triangles and the cut vertices' indices."""
    cache = {}
    nP, nN, nUV = [], [], []
    n0 = len(P)
    hc = hot[T]
    part = hc.any(1) & ~hc.all(1)

    def cut(a, b):
        key = (min(a, b), max(a, b))
        if key not in cache:
            t = sv[a] / (sv[a] - sv[b])
            q = snap(P[a] + t * (P[b] - P[a]), a, b, t)
            nv = N[a] + t * (N[b] - N[a])
            nP.append(q)
            nN.append(nv / max(np.linalg.norm(nv), 1e-12))
            nUV.append(UV[a] + t * (UV[b] - UV[a]))
            cache[key] = n0 + len(nP) - 1
        return cache[key]
    out = []
    for tri in T[part]:
        poly = []
        for k in range(3):
            a, b = int(tri[k]), int(tri[(k + 1) % 3])
            ina, inb = sv[a] <= 0, sv[b] <= 0
            if ina:
                poly.append(a)
            if ina != inb:
                poly.append(cut(a, b))
        for k in range(1, len(poly) - 1):
            out.append((poly[0], poly[k], poly[k + 1]))
    keep = ~hc.any(1)
    T = np.vstack([T[keep]] + ([np.array(out, np.int64)] if out else []))
    if nP:
        P = np.vstack([P, np.array(nP)])
        N = np.vstack([N, np.array(nN)])
        UV = np.vstack([UV, np.array(nUV)])
    return P, N, UV, T, np.arange(n0, len(P)), int(part.sum()), int(hc.all(1).sum())


def despike(P, T, region, iters=15):
    """Pull needle spikes in region (a vertex off the mean of its neighbours by more than SPIKE of their mean edge
    length) back onto that mean, on the skin welded by position (seam copies move together; open edges stay).
    Returns how many vertices moved."""
    used = np.unique(T)
    _, wid = np.unique(np.round(P[used] / 1e-7).astype(np.int64), axis=0, return_inverse=True)
    wid = wid.reshape(-1)
    remap = np.full(len(P), -1)
    remap[used] = wid
    W = remap[T]
    nw = int(wid.max()) + 1
    Q = np.zeros((nw, 3))
    Q[wid] = P[used]
    reg = np.zeros(nw, bool)
    reg[wid] = region[used]
    E = np.sort(np.concatenate([W[:, [0, 1]], W[:, [1, 2]], W[:, [2, 0]]]), 1)
    E = E[E[:, 0] != E[:, 1]]
    E, cnt = np.unique(E, axis=0, return_counts=True)
    fixed = np.zeros(nw, bool)
    fixed[E[cnt == 1].reshape(-1)] = True
    moved = np.zeros(nw, bool)
    for _ in range(iters):
        s = np.zeros((nw, 3))
        cc = np.zeros(nw)
        el = np.zeros(nw)
        L = np.linalg.norm(Q[E[:, 0]] - Q[E[:, 1]], axis=1)
        for a, b in ((0, 1), (1, 0)):
            np.add.at(s, E[:, a], Q[E[:, b]])
            np.add.at(cc, E[:, a], 1)
            np.add.at(el, E[:, a], L)
        ok = cc > 0
        avg = np.zeros((nw, 3))
        avg[ok] = s[ok] / cc[ok, None]
        d = np.linalg.norm(Q - avg, axis=1)
        spk = ok & reg & ~fixed & (d > SPIKE * el / np.maximum(cc, 1))
        if not spk.any():
            break
        Q[spk] = avg[spk]
        moved |= spk
    P[used] = Q[wid]
    return int(moved.sum())


def fair(P, T, weight, zlim, rounds=30, iters=30, lam=0.5, mu=-0.53):
    """Smoothing of the skin by weight (0..1 per vertex), welded by position, open edges fixed: irons out the
    generator's crumpled, creased fillet in the gap between the splitter and the fuselage. First weighted Laplacian
    rounds (they round off the crease at the bottom of the fillet; the weight ramps to 0 at the region's border, so
    no step forms there), then Taubin passes (shrink-free) for the leftover ripples. Moved vertices stay inboard of
    |z| zlim (the splitter's plane). Returns how many vertices moved."""
    used = np.unique(T)
    _, wid = np.unique(np.round(P[used] / 1e-7).astype(np.int64), axis=0, return_inverse=True)
    wid = wid.reshape(-1)
    remap = np.full(len(P), -1)
    remap[used] = wid
    W = remap[T]
    nw = int(wid.max()) + 1
    Q = np.zeros((nw, 3))
    Q[wid] = P[used]
    wv = np.zeros(nw)
    wv[wid] = weight[used]
    E = np.sort(np.concatenate([W[:, [0, 1]], W[:, [1, 2]], W[:, [2, 0]]]), 1)
    E = E[E[:, 0] != E[:, 1]]
    E, cnt = np.unique(E, axis=0, return_counts=True)
    wv[E[cnt == 1].reshape(-1)] = 0.0
    ok = wv > 0
    Q0 = Q.copy()
    side = np.sign(Q0[ok, 2])
    steps = [lam] * rounds + [lam, mu] * iters
    Wf = W[ok[W].any(1)]                      # faces a step can move

    def fnorm(X):
        return np.cross(X[Wf[:, 1]] - X[Wf[:, 0]], X[Wf[:, 2]] - X[Wf[:, 0]])
    f0 = fnorm(Q0)
    for f in steps:
        s = np.zeros((nw, 3))
        cc = np.zeros(nw)
        for a, b in ((0, 1), (1, 0)):
            np.add.at(s, E[:, a], Q[E[:, b]])
            np.add.at(cc, E[:, a], 1)
        Qn = Q.copy()
        Qn[ok] += (f * wv[ok])[:, None] * (s[ok] / np.maximum(cc[ok], 1)[:, None] - Q[ok])
        Qn[ok, 2] = side * np.minimum(np.abs(Qn[ok, 2]), zlim)
        # a step that would fold a face over (its normal turning against the original) is not taken there
        flip = np.einsum("ij,ij->i", fnorm(Qn), f0) <= 0
        if flip.any():
            back = np.unique(Wf[flip])
            Qn[back] = Q[back]
        Q = Qn
    P[used] = Q[wid]
    return int((np.linalg.norm(Q - Q0, axis=1) > 1e-6).sum())


def open_vertices(T):
    """Vertices on open edges of triangles T"""
    ed = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), 1)
    ue, cnt = np.unique(ed, axis=0, return_counts=True)
    return np.unique(ue[cnt == 1].reshape(-1))


def tex_cov(g, S):
    """UV coverage of every textured primitive at S x S texels"""
    from PIL import ImageDraw
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    for mh in g.j["meshes"]:
        for pr in mh["primitives"]:
            if "TEXCOORD_0" not in pr["attributes"]:
                continue
            uv = g.accessor(pr["attributes"]["TEXCOORD_0"]) * S
            for t in g.accessor(pr["indices"]).reshape(-1, 3):
                d.polygon([tuple(uv[t[0]]), tuple(uv[t[1]]), tuple(uv[t[2]])], fill=255)
    return np.asarray(im) > 0


def free_rect(cov, w, h):
    """Top-left texel of a free (uncovered, with a 6 texel margin) w x h rectangle in the coverage mask"""
    from scipy.ndimage import binary_dilation
    occ = binary_dilation(cov, iterations=6)
    S = np.pad(np.cumsum(np.cumsum(occ, 0), 1), ((1, 0), (1, 0)))
    tot = S[h:, w:] - S[:-h, w:] - S[h:, :-w] + S[:-h, :-w]
    ys, xs = np.nonzero(tot == 0)
    if not len(ys):
        raise SystemExit("no free %d x %d texels in the atlas" % (w, h))
    k = np.argmin(ys + xs * 0.01)
    return int(ys[k]), int(xs[k])


def even_paint(col, UV, T, fw, sigma=10.0):
    """Even out the generator's patchwork in the paint of the skin faces with weight fw > 0 (texture patches a
    little off each other's tone, with zigzag seams; in the hangar the livery takes the texture's luminance as
    detail, so they read as cracked plates on the nacelle next to the clean new parts). In those faces' texels
    each camouflage tone (split at the Otsu threshold of their luminance) becomes its own smooth local mean
    (normalised Gaussian of the same tone's texels only), so tone edges stay where they are; the face weight fades
    the result in. Returns how many texels changed."""
    from PIL import ImageDraw
    from scipy.ndimage import binary_dilation, gaussian_filter
    S = col.shape[0]
    sel = np.nonzero(fw > 0)[0]
    if not len(sel):
        return 0
    wim = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(wim)
    for f in sel:
        d.polygon([(UV[i, 0] * S, UV[i, 1] * S) for i in T[f]], fill=int(round(255 * fw[f])))
    w = np.asarray(wim, np.float64) / 255.0
    m = binary_dilation(w > 0, iterations=2)
    w = np.maximum(w, gaussian_filter(w, 1.0)) * m
    ys, xs = np.nonzero(m)
    y0, y1 = max(ys.min() - 40, 0), min(ys.max() + 41, S)
    x0, x1 = max(xs.min() - 40, 0), min(xs.max() + 41, S)
    c = col[y0:y1, x0:x1].astype(np.float64)
    mm = m[y0:y1, x0:x1]
    L = c @ np.array([0.2126, 0.7152, 0.0722])
    hist, edges = np.histogram(L[mm], bins=64, range=(0, 255))
    p = hist / max(hist.sum(), 1)
    om = np.cumsum(p)
    mu = np.cumsum(p * (edges[:-1] + 2.0))
    between = (mu[-1] * om - mu) ** 2 / np.maximum(om * (1 - om), 1e-9)
    thr = edges[int(np.argmax(between))] + 2.0
    out = c.copy()
    for tone in (L < thr, L >= thr):
        src = (mm & tone).astype(np.float64)
        den = gaussian_filter(src, sigma)
        for ch in range(3):
            num = gaussian_filter(c[..., ch] * src, sigma)
            out[..., ch] = np.where(tone & mm & (den > 1e-3), num / np.maximum(den, 1e-6), out[..., ch])
    ww = w[y0:y1, x0:x1, None]
    col[y0:y1, x0:x1] = np.clip(c * (1 - ww) + out * ww + 0.5, 0, 255).astype(np.uint8)
    return int((ww[..., 0] > 0).sum())


def skin_paint(tree, keepv, UV, col, orm, q, k=12):
    """Median colour and ORM of the old skin nearest to point q (through the old UVs)"""
    S = col.shape[0]
    _, ii = tree.query(q, k=k)
    uv = UV[keepv[ii]]
    tx = np.clip((uv[:, 0] * S).astype(int), 0, S - 1)
    ty = np.clip((uv[:, 1] * S).astype(int), 0, S - 1)
    c, o = col[ty, tx].astype(float), orm[ty, tx].astype(float)
    lit = c @ np.array([0.2126, 0.7152, 0.0722]) > 45
    if lit.sum() >= 3:
        c, o = c[lit], o[lit]
    return np.median(c, 0), np.median(o, 0)


def paint_intake(col, orm, rect, G, cls, aux, lip_rgb, lip_orm, seed):
    """Paint one intake's rectangle (x0, y0, w, h): texel columns run round the opening, rows along the profile in
    arc length. Fairing and lip: the column's skin paint, a light worn band on the lip edge with a few chips;
    duct: light grey fading to near black with depth; cap: near black."""
    x0, y0, w, h = rect
    nr = len(G)
    seg = np.linalg.norm(np.diff(G, axis=0), axis=2).mean(1)
    vv = np.r_[0.0, np.cumsum(seg)]
    rowpix = 4 + vv / vv[-1] * (h - 8)
    yy, xx = np.mgrid[0:h, 0:w]
    colf = np.clip((xx - 4) / (w - 8) * NT, 0, NT)       # column (NT = seam copy of 0)
    ci = np.clip(np.round(colf).astype(int), 0, NT) % NT
    rowf = np.interp(yy, rowpix, np.arange(nr))
    ri = np.clip(np.round(rowf).astype(int), 0, nr - 1)
    k = cls[ri]
    a = np.interp(rowf, np.arange(nr), aux)
    rgb = lip_rgb[ci].copy()
    o = lip_orm[ci].copy()
    rng = np.random.default_rng(seed)
    noise = rng.random((h, w))
    from scipy.ndimage import gaussian_filter
    noise = gaussian_filter(noise, 1.2)
    noise = (noise - noise.mean()) / max(noise.std(), 1e-6)
    # worn band: strongest at the front of the nose (angle pi/2), a little onto both faces, chipped
    wear = np.where(k == 1, np.exp(-0.5 * ((a - np.pi / 2) / 0.55) ** 2), 0.0)
    wear = np.clip(wear * (0.6 + 0.5 * noise), 0, 1) * WEAR
    bare = np.array([150.0, 148.0, 140.0])
    rgb = rgb * (1 - wear[..., None]) + bare * wear[..., None]
    o[..., 2] = np.maximum(o[..., 2], 255 * 0.5 * wear)          # bare metal shows in the metal channel
    # duct: depth share a (0 at the lip, 1 at the cap)
    f = np.where(k == 2, a, np.where(k == 3, 1.0, 0.0))
    t1 = np.clip(f / 0.55, 0, 1)
    t2 = np.clip((f - 0.55) / 0.45, 0, 1)
    duct = (np.array(DUCT_LIGHT, float) * (1 - t1[..., None]) + np.array(DUCT_MID, float) * t1[..., None])
    duct = duct * (1 - t2[..., None]) + np.array(DUCT_DEEP, float) * t2[..., None]
    # a faint, broad mottle (texel grain read as noise in the hangar close-ups)
    mottle = gaussian_filter(rng.random((h, w)), 8.0)
    mottle = (mottle - mottle.mean()) / max(mottle.std(), 1e-6)
    duct *= (1 + 0.03 * mottle)[..., None]
    # the first duct rows still blend from the lip paint (the livery wraps a few millimetres in)
    wrap = np.clip((f - 0.03) / 0.12, 0, 1)
    dsel = (k == 2)[..., None]
    rgb = np.where(dsel, rgb * (1 - wrap[..., None]) + duct * wrap[..., None], rgb)
    rgb = np.where((k == 3)[..., None], np.array(CAP_TONE, float), rgb)
    occ = 255 - (255 - DUCT_ORM[0]) * np.clip(f, 0, 1)
    dorm = np.stack([occ, np.full_like(f, DUCT_ORM[1]), np.zeros_like(f)], -1)
    o = np.where(((k == 2) | (k == 3))[..., None], o * (1 - wrap[..., None]) + dorm * wrap[..., None], o)
    col[y0:y0 + h, x0:x0 + w] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)
    orm[y0:y0 + h, x0:x0 + w] = np.clip(o + 0.5, 0, 255).astype(np.uint8)
    return rowpix


def write(g, m, ai, nP, nN, nUV, tris, dst):
    """Replace the main skin's vertex attributes (positions back in the node's frame) and primitive 0's indices"""
    e = m.acc[ai["POSITION"]]
    Minv = np.linalg.inv(e["M"])
    loc = nP @ Minv[:3, :3].T + Minv[:3, 3]
    nl = nN @ e["M"][:3, :3]
    nl /= np.maximum(np.linalg.norm(nl, axis=1, keepdims=True), 1e-12)
    for key, arr in (("POSITION", loc), ("NORMAL", nl), ("TEXCOORD_0", nUV)):
        acc = g.j["accessors"][ai[key]]
        a32 = np.ascontiguousarray(arr.astype(np.float32))
        while len(g.bin) % 4:
            g.bin.append(0)
        off = len(g.bin)
        g.bin += a32.tobytes()
        g.j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": int(a32.nbytes), "target": 34962})
        acc["bufferView"] = len(g.j["bufferViews"]) - 1
        acc.pop("byteOffset", None)
        acc["count"] = int(len(a32))
        if key == "POSITION":
            acc["min"] = [float(v) for v in a32.min(0)]
            acc["max"] = [float(v) for v in a32.max(0)]
        else:
            acc.pop("min", None)
            acc.pop("max", None)
    g.set_indices(g.j["nodes"][0]["mesh"], 0, tris)
    g.save(dst)


def main():
    """Command line: rebuild both intakes of one plane"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    ap.add_argument("--maps", nargs=2, required=True)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    cfg = INTAKES[a.key]
    rep = []
    m = pp.Model(a.src)
    g = m.g
    j = g.j
    mesh = j["meshes"][j["nodes"][0]["mesh"]]
    p0 = mesh["primitives"][0]
    ai = p0["attributes"]
    e = m.acc[ai["POSITION"]]
    P = e["P"].copy()
    N = e["N"].copy()
    UV = g.accessor(ai["TEXCOORD_0"]).astype(np.float64)
    T = g.accessor(p0["indices"]).reshape(-1, 3).astype(np.int64)
    T_orig = T.copy()
    col = np.asarray(Image.open(a.maps[0]).convert("RGB")).copy()
    S = col.shape[0]
    orm_im = Image.open(a.maps[1]).convert("RGB")
    orm_size = orm_im.size
    orm = np.asarray(orm_im.resize((S, S), Image.BICUBIC)).copy()
    cov = tex_cov(g, S).copy()
    c = np.array(cfg["lip"], float)
    zp, tp = cfg["plate"]
    R = cfg["r"]
    parts = []        # per side: (positions, normals, triangles, uv builder)
    near_any = np.zeros(len(P), bool)
    gap_any = np.zeros(len(P), float)
    cutv_all = []
    duct_consts = None
    for side in (1, -1):
        mir = np.array([1.0, 1.0, float(side)])
        fr = Frame(cfg["axis"][0], cfg["axis"][1])

        cc = np.array([c[0], cfg.get("cut_b", c[1]), c[2]])

        def xcut_of(Q, cc=cc, fr=fr):
            return lip_x(cc, fr, Q[:, 1], Q[:, 2]) - cfg["t"] / 2 - cfg["fair"] + CUT_OVER
        Pm = P * mir
        sec = cut_section(Pm, T, fr, cfg, xcut_of)
        G, cls, aux, xr, xn, x_end, O2, Oc = build(fr, sec, c, cfg, xcut_of)
        # ---- cut
        x, _, r = fr.polar(Pm)
        xc = xcut_of(Pm)
        xmax = xn.max() + 0.06   # everything outboard of the plate ahead of the lip goes (old lip spikes)
        sa = np.minimum.reduce([x - xc, Pm[:, 2] - zp, cfg["reach"] * R - r, xmax - x])
        sb = duct_inside(G, cls, Oc, Pm)
        sb = np.where(Pm[:, 2] > zp, sb, -1.0)
        hot = (sa > 0) | (sb > 0)
        sv = np.maximum(sa, sb)

        def snap(q, ia, ib, t):
            """Cut points stay where the cut put them (the fairing starts from the same section)"""
            return q
        P2, N2, UV2, T, cutv, npart, ndrop = clip_faces(Pm, N * mir, UV, T, hot, sv, snap)
        rep.append("side %+d: %d faces removed, %d clipped; fairing rear x %.3f..%.3f, lip nose x %.3f..%.3f, "
                   "duct end %.3f" % (side, ndrop, npart, xr.min(), xr.max(), xn.min(), xn.max(), x_end))
        # cut vertices off every intended surface (the reach limit) show as torn edges: count them
        cq = P2[cutv]
        _, _, cr = fr.polar(cq)
        on_x = np.abs(cq[:, 0] - xcut_of(cq)) < 2e-4
        on_p = np.abs(cq[:, 2] - zp) < 2e-4
        on_d = np.abs(duct_inside(G, cls, Oc, cq)) < 4e-4
        stray = ~(on_x | on_p | on_d)
        rep.append("side %+d: cut vertices on the x cut %d, on the plate plane %d, on the duct %d, elsewhere %d" % (
            side, int(on_x.sum()), int(on_p.sum()), int(on_d.sum()), int(stray.sum())))
        if a.report and stray.any():
            rep.append("  stray cut points (x, y, |z|, r/R): " + " ".join(
                "(%.3f %.3f %.3f %.2f)" % (q[0], q[1], q[2], rr / R) for q, rr in zip(cq[stray][:12], cr[stray][:12])))
        # the hole the plane cut leaves where the nacelle was fused to the fuselage: a flat patch on the plane
        patch = plane_patch(P2, T, zp, xcut_of)
        rep.append("side %+d: plane patch %d faces" % (side, len(patch[1])))
        # plate: covers the cut edges on its plane and the fairing clamped into it
        # (the plane patch closes the rest of the plane, so the plate only spans the opening and the lip)
        fz = G[cls <= 1].reshape(-1, 3)
        fz = fz[fz[:, 2] < zp + tp + 1e-6]           # fairing clamped into the plate
        ys = np.r_[fz[:, 1], O2[:, 0].min() - cfg["t"] - 0.003, O2[:, 0].max() + cfg["t"] + 0.003]
        ylo, yhi = ys.min() - 0.001, ys.max() + 0.001
        xback = xr.min() - 0.008   # past the fairing's rear edge by more than the corner radius
        # the bottom edge goes down to the fuselage's cut edge on the plane (where the cut corner leaves the plane
        # under the fairing, only the plate closes the skin): at the back and at the front, so it follows the
        # fuselage's rise towards the nose without standing out under it
        xfr = lip_x(c, fr, ylo, zp + tp) + cfg["ext"]
        low = cq[on_p & (cq[:, 1] < Oc[1])]
        ylo_b, ylo_f = ylo, ylo
        for xa, xb_ in ((xback, xback + 0.03), (xfr - 0.015, xfr)):
            q = low[(low[:, 0] > xa) & (low[:, 0] < xb_)]
            if len(q):
                yy = min(ylo, q[:, 1].min() - 0.0005)
                ylo_b, ylo_f = (yy, ylo_f) if xa == xback else (ylo_b, yy)
        Pp, Np, Tp, XYp = plate_mesh(cfg, c, fr, (ylo_b, ylo_f), yhi, xback)
        rep.append("side %+d: plate y %.4f (back) %.4f (front)..%.4f, x back %.3f"
                   % (side, ylo_b, ylo_f, yhi, xback))
        # back to model space
        P = P2 * mir
        N = N2 * mir
        UV = UV2
        near_any = np.r_[near_any, np.zeros(len(P) - len(near_any), bool)]
        xx, _, rr2 = fr.polar(P2)
        near_any |= (rr2 < 2.0 * R) & (xx > xc.min() - 0.03 if len(xc) else False) & (xx < xmax)
        gap_any = np.r_[gap_any, np.zeros(len(P) - len(gap_any), float)]

        def ramp(v, lo, hi, w):
            """1 inside [lo, hi], falling to 0 over w outside"""
            return np.clip(np.minimum(v - lo, hi - v) / w + 1.0, 0.0, 1.0)
        gw = (ramp(P2[:, 2], zp - GAP_FAIR, zp - 2e-4, 0.006) * (P2[:, 2] < zp - 2e-4)
              * ramp(P2[:, 1], ylo_b - 0.004, yhi + 0.02, 0.008) * ramp(P2[:, 0], xback - 0.01, xn.max() + 0.03, 0.012))
        gap_any = np.maximum(gap_any, gw)
        cutv_all.append(cutv)
        parts.append({"G": G * mir, "cls": cls, "aux": aux, "plate": (Pp * mir, Np * mir, Tp, XYp), "side": side,
                      "frame": fr, "patch": (patch[0] * mir, patch[1]), "mir": mir, "xr": float(xr.min()),
                      "xmax": float(xmax)})
        if side == 1:
            ha, hb = cfg["open"][2], cfg["open"][3]
            Yo, Zo = Oc
            # [centre y, |z|, half height, half width, duct start x at the centre, lip slopes dx/dy dx/d|z|, depth,
            #  |z| of the duct's inboard wall (between the plate face and the wall), centre-line shift at full depth]
            dcy, dcz = fr.yc + DUCT_END[0] * R - Yo, fr.zc + DUCT_END[1] * R - Zo
            duct_consts = [round(float(v), 5) for v in (
                Yo, Zo, ha, hb, lip_x(c, fr, Yo, Zo) - cfg["t"] / 2, c[1], c[2], cfg["depth"],
                zp + tp + INSET / 2, dcy, dcz)]
    keepT = T
    P_before = P.copy()
    rep.append("despiked %d skin vertices round the intakes" % despike(P, keepT, near_any))
    rep.append("faired %d skin vertices in the splitter gaps" % fair(P, keepT, gap_any, zp - 2e-4))
    # moved skin (despiked or faired) takes fresh normals, shared over seam copies
    _, wkey = np.unique(np.round(P / 1e-7).astype(np.int64), axis=0, return_inverse=True)
    Ns = smooth_normals(P, keepT, wkey.reshape(-1))
    mv = np.linalg.norm(P - P_before, axis=1) > 1e-7
    mv &= np.linalg.norm(Ns, axis=1) > 0.5
    N[mv] = Ns[mv]           # from the faces' winding (the generator's normals were crumpled with the skin)
    # the generator's patchwork paint on the nacelle behind the fairing and in the gap, evened (see even_paint)
    C = P[keepT].mean(1)
    fw = np.zeros(len(keepT))
    for prt in parts:
        Cm = C * prt["mir"]
        xx, _, rr = prt["frame"].polar(Cm)
        w = (np.clip((xx - (prt["xr"] - EVEN_BACK[1])) / (EVEN_BACK[1] - EVEN_BACK[0]), 0, 1)
             * np.clip((2.0 * R - rr) / (0.4 * R), 0, 1) * (Cm[:, 2] > zp - GAP_FAIR) * (xx < prt["xmax"]))
        fw = np.maximum(fw, w)
    rep.append("evened the paint of %d texels round the intakes" % even_paint(col, UV, keepT, fw))
    # open edges the cut left next to the new parts: snap onto them
    allnew = np.vstack([p["G"].reshape(-1, 3) for p in parts] + [p["plate"][0] for p in parts])
    ov = np.setdiff1d(open_vertices(keepT), np.concatenate([open_vertices(T_orig)] + cutv_all))
    if len(ov):
        dd, nn = cKDTree(allnew).query(P[ov])
        sn = dd < SNAP
        P[ov[sn]] = allnew[nn[sn]]
        rep.append("snapped %d of %d new open-edge vertices onto the new parts" % (int(sn.sum()), len(ov)))
    # ---- new geometry, UV islands and paint
    keepv = np.unique(keepT)
    tree = cKDTree(P[keepv])
    outP, outN, outUV, outT = [], [], [], []
    o = len(P)
    tex_w, tex_h = 480, 200
    for k, prt in enumerate(parts):
        G = prt["G"]
        nr = len(G)
        Gs = np.concatenate([G, G[:, :1]], 1)                      # seam column
        pos = Gs.reshape(-1, 3)
        Tg = grid_tris(nr, NT + 1)
        weld = np.arange(nr * (NT + 1)).reshape(nr, NT + 1)
        weld[:, NT] = weld[:, 0]
        nrm = smooth_normals(pos, Tg, weld.reshape(-1))
        bad = np.linalg.norm(nrm, axis=1) < 0.5   # the cap's centre row has no area of its own
        # orientation: the fairing's normals point away from the opening's centre
        cen = G[0].mean(0)
        fn = np.cross(pos[Tg[:, 1]] - pos[Tg[:, 0]], pos[Tg[:, 2]] - pos[Tg[:, 0]])
        fc = pos[Tg].mean(1)
        first = np.arange(len(Tg)) < 2 * NT
        outw = fc - cen
        outw[:, 0] = 0
        if np.einsum("ij,ij->i", fn[first], outw[first]).sum() < 0:
            Tg = Tg[:, [0, 2, 1]]
            nrm = -nrm
        nrm[bad] = [1.0, 0.0, 0.0]                  # it faces the opening
        # paint: the lip paint per column from the skin just behind the fairing's rear edge
        lip_rgb = np.zeros((NT, 3))
        lip_orm = np.zeros((NT, 3))
        for q in range(NT):
            qq = G[0, q] - np.array([0.006, 0.0, 0.0])
            lip_rgb[q], lip_orm[q] = skin_paint(tree, keepv, UV, col, orm, qq)
        kk = np.exp(-0.5 * (np.arange(-3, 4) / 1.5) ** 2)
        kk /= kk.sum()
        for arr in (lip_rgb, lip_orm):
            for i in range(3):
                arr[:, i] = np.convolve(np.r_[arr[-3:, i], arr[:, i], arr[:3, i]], kk, "valid")
        y0, x0 = free_rect(cov, tex_w, tex_h)
        cov[y0:y0 + tex_h, x0:x0 + tex_w] = True
        rowpix = paint_intake(col, orm, (x0, y0, tex_w, tex_h), G, prt["cls"], prt["aux"], lip_rgb, lip_orm, 7 + k)
        U = (x0 + 4 + np.arange(NT + 1) / NT * (tex_w - 8)) / S
        V = (y0 + rowpix) / S
        uv = np.stack([np.broadcast_to(U, (nr, NT + 1)), np.broadcast_to(V[:, None], (nr, NT + 1))], -1).reshape(-1, 2)
        rep.append("intake UV island %d at texels (%d, %d), %d x %d" % (k, x0, y0, tex_w, tex_h))
        outP.append(pos)
        outN.append(nrm)
        outUV.append(uv)
        outT.append(Tg + o)
        o += len(pos)
        # plate: planar UV over (x, y), its own rectangle, painted with the fuselage paint beside it
        Pp, Np, Tp, XYp = prt["plate"]
        lo, hi = XYp.min(0), XYp.max(0)
        pw, ph = 96, 96
        y1, x1 = free_rect(cov, pw, ph)
        cov[y1:y1 + ph, x1:x1 + pw] = True
        # inboard face, outboard face and rim share the projection (they carry the same paint)
        uvp = np.stack([(x1 + 4 + (XYp[:, 0] - lo[0]) / (hi[0] - lo[0]) * (pw - 8)) / S,
                        (y1 + 4 + (XYp[:, 1] - lo[1]) / (hi[1] - lo[1]) * (ph - 8)) / S], 1)
        # the cowl paint round the intake (the skin next to the plate is the old dark junction)
        prgb, porm = np.median(lip_rgb, 0), np.median(lip_orm, 0)
        col[y1:y1 + ph, x1:x1 + pw] = np.clip(prgb + 0.5, 0, 255).astype(np.uint8)
        orm[y1:y1 + ph, x1:x1 + pw] = np.clip(porm + 0.5, 0, 255).astype(np.uint8)
        rep.append("plate UV island %d at texels (%d, %d), paint %s" % (k, x1, y1, np.round(prgb).astype(int)))
        if prt["side"] < 0:
            Tp = Tp[:, [0, 2, 1]]   # mirrored
        outP.append(Pp)
        outN.append(Np)
        outUV.append(uvp)
        outT.append(Tp + o)
        o += len(Pp)
        # plane patch: faces outboard, the plate's paint (UV clamped into the plate's rectangle)
        Pq, Tq = prt["patch"]
        if len(Tq):
            nq = np.tile([0.0, 0.0, float(np.sign(prt["side"]))], (len(Pq), 1))
            fn = np.cross(Pq[Tq[:, 1]] - Pq[Tq[:, 0]], Pq[Tq[:, 2]] - Pq[Tq[:, 0]])
            Tq = np.where((fn[:, 2] * prt["side"] < 0)[:, None], Tq[:, [0, 2, 1]], Tq)
            uq = np.stack([(x1 + 4 + np.clip((Pq[:, 0] - lo[0]) / (hi[0] - lo[0]), 0, 1) * (pw - 8)) / S,
                           (y1 + 4 + np.clip((Pq[:, 1] - lo[1]) / (hi[1] - lo[1]), 0, 1) * (ph - 8)) / S], 1)
            outP.append(Pq)
            outN.append(nq)
            outUV.append(uq)
            outT.append(Tq + o)
            o += len(Pq)
    nP = np.vstack([P] + outP)
    nN = np.vstack([N] + outN)
    nUV = np.vstack([UV] + outUV)
    tris = np.vstack([keepT] + outT)
    rep.append("skin faces kept %d (the new parts follow them in the index buffer)" % len(keepT))
    write(g, m, ai, nP, nN, nUV, tris, a.dst)
    Image.fromarray(col).save(a.maps[0], quality=95)
    Image.fromarray(orm).resize(orm_size, Image.LANCZOS).save(a.maps[1], quality=95)
    rep.append("Livery.INTAKE_DUCTS %s: %s" % (a.key, duct_consts))
    print("\n".join(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
