"""Clean air intakes for the remeshed hangar planes (Kanta, 01.11: «Грач» intakes crude, lumpy and torn after the
smoothing passes): the generator's intake (a torn lip, a shallow lumpy scoop closed by a cap a few millimetres
in) is cut out of the skin and replaced by built geometry:

- a lip ring: the cowl's own outer surface (a robust penalised spline r(x, theta) fitted to the nacelle skin
  behind the intake, skin_refit.Spline2) carried forward to the lip plane, a rounded nose of the lip's thickness,
  and the inner surface of the lip turning into the duct; its rear edge dips under the cowl skin, so the joint
  reads as a panel seam and no crack can open;
- a duct going back DEPTH behind the top of the lip, narrowing a little, closed by a dark engine face with a
  spinner cone;
- the cowl skin round the joint is moved onto the fitted surface (no torn lip left under the ring) and the open
  edges the cut leaves next to the ring are snapped onto it.
The lip plane is fitted to the front of the old lip (robust plane x = a + b y + c z), so the scarf of the intake
and the outer silhouette stay. The new faces join the textured skin (primitive 0, same material: the livery,
the hangar detail layer and battle_bake treat them as skin) with their own UV island in a free corner of the
atlas, painted there: the lip in the paint sampled from the cowl just behind it, the duct and the engine face
dark (below the livery's keep threshold, so every paint scheme leaves them dark).

  python3 -I intake_rebuild.py <hangar.glb> <key> <out.glb> --maps <col.jpg> <orm.jpg> [--debug <prefix>]
The maps are rewritten in place (start from copies of the extracted maps), then tex_clean.py pads them.
Axes: glTF model space (nose +X, up +Y, right wing +Z), length 1."""
import argparse
import os
import sys

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402
import plane_polish as pp  # noqa: E402
import skin_refit as sr  # noqa: E402

Image.MAX_IMAGE_PIXELS = None

# Per plane (model units, z of the right side; mirrored): nacelle axis (y, z) and radius as in Livery.ENGINE_HOLES,
# x range of the cowl skin the outer surface is fitted on, the lip plane (x = a + b dy + c dz, read off sections
# of the old intake: its foremost points at the bottom and the sides, the top closed over the old slot), lip thickness, length of the lip ring, duct depth
# behind the top of the lip, sectors (degrees, 0 up, + outboard) where the nacelle grows into the fuselage and
# its skin is not cowl, the nacelle's width over its height where it is oval (sz), the angular smoothing of the cowl
# fit (lam) and sectors where torn flaps of the old intake stand off the cowl and are laid onto it (trim: degrees,
# reach, length behind the cut).
INTAKES = {
    "attacker_1": {"axis": (-0.0387, 0.0884), "r": 0.0335, "fit": (0.0, 0.075), "lip": (0.112, -0.35, 0.0), "t": 0.0028, "band": 0.006,
                   "depth": 0.035, "skip": [(-150, -75)]},
    "attacker_2": {"axis": (-0.022, 0.096), "r": 0.032, "fit": (0.0, 0.07), "lip": (0.0786, -0.5, 0.0), "sz": 0.85, "t": 0.006, "band": 0.006, "lam": (2.0, 8.0),
                   "depth": 0.035, "skip": []},
}
NT = 120          # samples round the intake
CUT_OVER = 0.004  # the skin is cut this far in front of the ring's rear edge (the ring covers the jagged cut)
SNAP = 0.005      # open edges of the cut this close to the ring are snapped onto it
SUNK = 0.0008     # outward-facing skin sunk this far under the fitted cowl near the lip is old slot (the band covers it)
BAND_MAX = 0.025  # longest band
SPIKE = 0.4       # a vertex this far off its neighbours' mean (in mean edge lengths) near an intake is a spike
SHELL = 0.0008    # the nacelle body's wall sits this far under the fitted cowl (holes in the old skin show it)
TAIL = 1.0        # length of its elliptic tail, in intake radii
DIP = 0.0004      # how far the lip ring's rear edge sinks under the cowl skin
PROUD = 0.00025   # how far the lip ring stands off the cowl skin (a panel seam, not a step)
DUCT_TONE = (14, 14, 15)    # sRGB of the duct and engine face: luminance under the livery's keep threshold
FACE_TONE = (24, 24, 26)
DUCT_ORM = (200, 150, 60)   # occlusion, roughness, metal of the duct


class Ring:
    """Cylindrical frame of one intake: axis parallel to x through (yc, zc), theta 0 up and positive outboard.
    sz squeezes the frame sideways (an oval nacelle is round in it): r is measured in the squeezed frame."""

    def __init__(self, yc, zc, side, sz=1.0):
        self.yc, self.zc, self.side, self.sz = yc, zc, side, sz

    def polar(self, P):
        """(x, theta, r) of points P"""
        dy, dz = P[:, 1] - self.yc, (P[:, 2] - self.zc) * self.side / self.sz
        return P[:, 0], np.arctan2(dz, dy), np.hypot(dy, dz)

    def point(self, x, th, r):
        """Points from (x, theta, r)"""
        return np.stack([x, self.yc + r * np.cos(th), self.zc + self.side * self.sz * r * np.sin(th)], -1)


def in_skip(th, skip, pad=0.0):
    """True where theta lies in one of the skipped sectors (degrees), widened by pad radians"""
    m = np.zeros(th.shape, bool)
    for a, b in skip:
        m |= (th > np.radians(a) - pad) & (th < np.radians(b) + pad)
    return m


def fit_cowl(P, N, ring, cfg, report):
    """Outer cowl surface r(x, theta) and the lip plane; returns (spline, plane coefficients a, b, c)"""
    x, th, r = ring.polar(P)
    R = cfg["r"]
    rd = ring.point(np.zeros(len(P)), th, np.ones(len(P))) - np.array([0.0, ring.yc, ring.zc])
    rd[:, 0] = 0
    facing = np.einsum("ij,ij->i", N, rd)
    near = (r > 0.55 * R) & (r < 1.35 * R) & ~in_skip(th, cfg["skip"])
    # the lip plane: x = a + b dy + c dz round the axis (dy up, dz outboard), from the config: the generator's lip
    # front is torn (a slot over the top, notches at the sides), so it is set by hand to the old outline's extremes
    c = np.array(cfg["lip"], float)
    report.append("lip plane: x = %.4f %+.3f*dy %+.3f*dz" % (c[0], c[1], c[2]))
    # cowl data: outward-facing skin near the radius, from the fit range up to 4 mm short of the lip plane
    xl = c[0] + c[1] * (r * np.cos(th)) + c[2] * (r * np.sin(th))
    data = near & (facing > 0.5) & (x > cfg["fit"][0]) & (x < xl - 0.004)
    sp = sr.Spline2(cfg["fit"][0] - 0.01, c[0] + 0.03, 0.012, -np.pi, np.pi, 24, periodic=True)
    rw = sp.fit(x[data], th[data], r[data], lam=cfg.get("lam", (2.0, 0.5)))
    report.append("cowl fit: %d points, %.0f %% kept by the robust fit" % (int(data.sum()), 100 * np.mean(rw > 0.5)))
    return sp, c


def band_at(band, th):
    """Band length (per theta sample of the ring) at angles th"""
    g = np.linspace(-np.pi, np.pi, NT, endpoint=False)
    return np.interp(th, g, band, period=2 * np.pi)


def band_cover(P, N, ring, sp, c, cfg, report):
    """Length of the lip ring's band per angle: the configured band, longer where the old intake's slot or dents
    run further back (outward-facing skin sunk under the fitted cowl), so the band covers them; a running max
    and a smoothing round the intake keep its rear edge a fair curve"""
    x, th, r = ring.polar(P)
    rob = sp(x, th)
    rd = ring.point(np.zeros(len(P)), th, np.ones(len(P))) - np.array([0.0, ring.yc, ring.zc])
    facing = np.einsum("ij,ij->i", N, rd)
    xl = lip_x(c, th, r)
    front = xl - cfg["t"] / 2
    bad = ((r < rob - SUNK) & (r > rob - 0.012) & (facing > 0.3) & (x > front - BAND_MAX) & (x < xl)
           & ~in_skip(th, cfg["skip"]))
    g = np.linspace(-np.pi, np.pi, NT, endpoint=False)
    need = np.full(NT, cfg["band"])
    k = np.round((th[bad] + np.pi) / (2 * np.pi) * NT).astype(int) % NT
    np.maximum.at(need, k, front[bad] - x[bad] + 0.003)
    need = np.minimum(need, BAND_MAX)
    w = 6
    ext = np.r_[need[-w:], need, need[:w]]
    need = np.array([ext[i:i + 2 * w + 1].max() for i in range(NT)])
    kk = np.exp(-0.5 * (np.arange(-w, w + 1) / (w / 2)) ** 2)
    kk /= kk.sum()
    need = np.convolve(np.r_[need[-w:], need, need[:w]], kk, "valid")
    report.append("band: %.1f..%.1f mm (longest at theta %.0f deg)" % (need.min() * 1e3, need.max() * 1e3,
                                                                      np.degrees(g[np.argmax(need)])))
    return need


def lip_x(c, th, r):
    """x of the lip plane at (theta, r)"""
    return c[0] + c[1] * r * np.cos(th) + c[2] * r * np.sin(th)


def build(ring, sp, c, cfg):
    """The new intake mesh: positions, triangles, UV (unit square, packed later) and a paint class per vertex
    (0 lip paint, 1 duct, 2 engine face). Grid rows run round the intake (NT columns, closed)."""
    t, band, R = cfg["t"], cfg["band_th"], cfg["r"]
    th = np.linspace(-np.pi, np.pi, NT, endpoint=False)
    rows = []   # (x, r, v, cls) per row, each an array over theta

    def ro(xq):
        return sp(xq, th)
    # lip plane x at the outer radius, iterated (the plane is tilted)
    r0 = ro(np.full(NT, c[0]))
    for _ in range(4):
        xf = lip_x(c, th, r0)
        r0 = ro(xf)
    x_top = xf.max()
    v = 0.0
    # 1. ring band: rear edge dipped under the skin, then proud of it, up to the start of the nose
    xs = np.linspace(0.0, 1.0, 9)
    for k, f in enumerate(xs):
        xq = xf - t / 2 - band * (1 - f)
        rr = ro(xq) + (-DIP if k == 0 else PROUD * min(1.0, k / 2.0))
        rows.append((xq, rr, 0))
    # 2. rounded nose: half circle of diameter t from the outer to the inner surface
    for k in range(1, 12):
        ph = np.pi * k / 12
        xq = xf - t / 2 + (t / 2) * np.sin(ph)
        rr = ro(xf - t / 2) + PROUD - (t / 2) * (1 - np.cos(ph))
        rows.append((xq, rr, 0 if k <= 7 else 1))
    # 3. duct: inner surface back to DEPTH behind the top of the lip, narrowing by 8 %
    x_end = x_top - cfg["depth"]
    for k in range(13):
        f = k / 12
        xq = (xf - t / 2) * (1 - f) + x_end * f
        rin = ro(xf - t / 2) + PROUD - t
        rr = rin * (1 - 0.08 * f * f)
        rows.append((xq, rr, 1))
    # 4. engine face: annulus to a hub, then a spinner cone
    rh = rows[-1][1]
    for k, (fr, dx) in enumerate([(0.8, 0.0), (0.45, 0.0), (0.38, 0.002), (0.2, 0.008), (0.0, 0.012)]):
        rows.append((np.full(NT, x_end + dx), rh * fr + (1e-5 if fr == 0 else 0), 2))
    # 5. the nacelle body round the duct: the duct's outer wall (SHELL under the fitted cowl skin, so a hole in the
    # old skin shows a smooth nacelle) closed by an elliptic tail; where the nacelle grows into the fuselage the old fillet skin inside it is
    # clipped on it, so the fillet runs into a clean round nacelle instead of a hole
    brk = len(rows)
    duct = rows[brk - 5 - 13:brk - 5]
    for xq, rr, _ in duct:
        rows.append((xq, np.maximum(rr + 0.3 * t, ro(xq) - SHELL), 3))
    r_end = rows[-1][1]
    for k in range(1, 11):
        ph = np.pi / 2 * k / 10
        rows.append((np.full(NT, x_end - TAIL * R * np.sin(ph)), np.maximum(r_end * np.cos(ph), 1e-5), 3))
    X = np.array([rw[0] for rw in rows])          # rows x NT
    Rr = np.array([rw[1] for rw in rows])
    cls = np.array([rw[2] for rw in rows])
    nr = len(rows)
    TH = np.broadcast_to(th, X.shape)
    pos = ring.point(X.reshape(-1), TH.reshape(-1), Rr.reshape(-1))
    # v along the profile by arc length, u round the intake (an extra seam column so the UV wraps cleanly)
    seg = np.linalg.norm(np.diff(pos.reshape(nr, NT, 3), axis=0), axis=2).mean(1)
    vv = np.r_[0.0, np.cumsum(seg)]
    pos = np.concatenate([pos.reshape(nr, NT, 3), pos.reshape(nr, NT, 3)[:, :1]], 1)   # nr x (NT+1)
    U = np.broadcast_to(np.arange(NT + 1) / NT, (nr, NT + 1))
    V = np.broadcast_to(vv[:, None], (nr, NT + 1))
    idx = np.arange(nr * (NT + 1)).reshape(nr, NT + 1)
    tris = []
    for i in range(nr - 1):
        if i == brk - 1:
            continue
        a, b = idx[i, :-1], idx[i, 1:]
        cc, d = idx[i + 1, :-1], idx[i + 1, 1:]
        tris.append(np.stack([a, cc, b], 1))
        tris.append(np.stack([b, cc, d], 1))
    T = np.vstack(tris)
    C = np.broadcast_to(cls[:, None], (nr, NT + 1)).reshape(-1)
    body = (X[brk:], Rr[brk:])
    return pos.reshape(-1, 3), T, np.stack([U.reshape(-1), V.reshape(-1)], 1), C, xf, x_end, body


def body_r(body, x, th):
    """Radius of the nacelle body (shell and tail, rows of x falling) at points (x, theta); -1 off its x range"""
    X, Rr = body
    g = (th + np.pi) / (2 * np.pi) * NT
    i0 = np.floor(g).astype(int) % NT
    w = g - np.floor(g)
    out = np.zeros(len(x))
    for k in range(NT):
        m0 = i0 == k
        if not m0.any():
            continue
        k1 = (k + 1) % NT
        r0 = np.interp(x[m0], X[::-1, k], Rr[::-1, k], left=-1, right=-1)
        r1 = np.interp(x[m0], X[::-1, k1], Rr[::-1, k1], left=-1, right=-1)
        out[m0] = np.where((r0 < 0) | (r1 < 0), -1.0, r0 * (1 - w[m0]) + r1 * w[m0])
    return out


def orient_outward(pos, T, ring, inner_cls, C):
    """Wind the faces so their normals point away from the axis on the lip outside and towards it in the duct
    (the duct is seen from inside); returns T and smooth vertex normals"""
    fn = np.cross(pos[T[:, 1]] - pos[T[:, 0]], pos[T[:, 2]] - pos[T[:, 0]])
    cen = pos[T].mean(1)
    rd = cen - np.c_[cen[:, 0], np.full(len(cen), ring.yc), np.full(len(cen), ring.zc)]
    rd[:, 0] = 0
    want = np.where(np.isin(C[T].max(1), inner_cls), -1.0, 1.0)
    # engine face: faces +x (towards the opening)
    face = C[T].min(1) == 2
    s = np.where(face, np.sign(fn[:, 0]), np.sign(np.einsum("ij,ij->i", fn, rd)) * want)
    T = np.where((s < 0)[:, None], T[:, [0, 2, 1]], T)
    fn = np.cross(pos[T[:, 1]] - pos[T[:, 0]], pos[T[:, 2]] - pos[T[:, 0]])
    n = np.zeros_like(pos)
    for k in range(3):
        np.add.at(n, T[:, k], fn)
    # the seam column shares its normals with column 0
    return T, n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)


def free_rect(cov, w, h):
    """Top-left texel of a free (uncovered, with a 6 texel margin) w x h rectangle in the coverage mask"""
    from scipy.ndimage import binary_dilation
    occ = binary_dilation(cov, iterations=6)
    S = np.pad(np.cumsum(np.cumsum(occ, 0), 1), ((1, 0), (1, 0)))
    H, W = occ.shape
    tot = S[h:, w:] - S[:-h, w:] - S[h:, :-w] + S[:-h, :-w]
    ys, xs = np.nonzero(tot == 0)
    if not len(ys):
        raise SystemExit("no free %d x %d texels in the atlas" % (w, h))
    k = np.argmin(ys + xs * 0.01)
    return int(ys[k]), int(xs[k])


def main():
    """Command line: rebuild both intakes of one plane"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("key")
    ap.add_argument("dst")
    ap.add_argument("--maps", nargs=2, required=True)
    ap.add_argument("--debug")
    a = ap.parse_args()
    cfg = INTAKES[a.key]
    rep = []
    m = pp.Model(a.src)
    g = m.g
    j = g.j
    # the main skin: node 0's mesh, primitive 0 (textured), sharing its vertex buffer with the glass
    mesh = j["meshes"][j["nodes"][0]["mesh"]]
    p0 = mesh["primitives"][0]
    ai = p0["attributes"]
    e = m.acc[ai["POSITION"]]
    P = e["P"].copy()
    N = e["N"].copy()
    UV = g.accessor(ai["TEXCOORD_0"]).astype(np.float64)
    T0 = g.accessor(p0["indices"]).reshape(-1, 3).astype(np.int64)
    col = np.asarray(Image.open(a.maps[0]).convert("RGB")).copy()
    S = col.shape[0]
    orm_im = Image.open(a.maps[1]).convert("RGB")
    orm_size = orm_im.size
    orm = np.asarray(orm_im.resize((S, S), Image.BICUBIC)).copy()   # painted at the colour map's size
    cov = tex_cov(g, S).copy()
    newP, newN, newUV, newT = [], [], [], []
    base = len(P)
    T_orig = T0.copy()
    near_any = np.zeros(len(P), bool)
    clipv = []
    for side in (1, -1):
        ring = Ring(cfg["axis"][0], cfg["axis"][1] * side, side, cfg.get("sz", 1.0))
        sp, c = fit_cowl(P, N, ring, cfg, rep)
        cfg = dict(cfg, band_th=band_cover(P, N, ring, sp, c, cfg, rep))
        pos, T, uv, C, xf, x_end, body = build(ring, sp, c, cfg)
        T, nrm = orient_outward(pos, T, ring, (1,), C)
        # cut: skin faces with a corner inside the new intake's reach
        x, th, r = ring.polar(P)
        rob = sp(x, th)
        xl = lip_x(c, th, r)
        # the ring starts at ring_rear; the skin is cut CUT_OVER in front of that, so the jagged edge of the cut
        # (whole faces go) stays under the ring
        bnd = band_at(cfg["band_th"], th)
        band_rear = xl - cfg["t"] / 2 - bnd + CUT_OVER
        # off the fillet sectors the old lip may stand a little proud of the fit; in them the fillet skin stays
        # outside the ring (the ring runs through it)
        reach = np.where(in_skip(th, cfg["skip"], np.radians(15)), PROUD, 0.0015)
        # torn flaps of the old intake standing off the cowl (config "trim": sector, reach, how far behind the cut)
        # are laid down onto the fitted cowl, fading out in reach and towards the back
        for a0, a1, rch, back in cfg.get("trim", []):
            w = (in_skip(th, [(a0, a1)]) * (1 - sr.smoothstep(0.7 * rch, rch, r - rob))
                 * sr.smoothstep(band_rear - back, band_rear - 0.5 * back, x) * (r > rob) * (x < xl + 0.01))
            mk = w > 0
            P[mk] = ring.point(x[mk], th[mk], r[mk] + (rob[mk] - r[mk]) * w[mk])
            rep.append("side %+d: %d flap vertices laid onto the cowl" % (side, int(mk.sum())))
        x, th, r = ring.polar(P)
        cowl = (r < rob + reach) & (x > band_rear)
        near_any |= (r < 2.0 * cfg["r"]) & (x > band_rear - 0.03) & (x < xl + 0.015)
        # the old scoop and anything else inside the new nacelle body (duct wall and tail)
        in_body = body_r(body, x, th) - r > 0
        hot = cowl | in_body
        # the cowl skin behind the ring onto the fitted surface (fading out over 15 mm), no torn lip under it
        zone = (x > band_rear - 0.015) & (x <= band_rear + 0.002) & (np.abs(r - rob) < 0.003) & ~in_skip(th, cfg["skip"])
        f = sr.smoothstep(band_rear - 0.015, band_rear - 0.004, x)
        sel = zone & ~hot
        P[sel] = ring.point(x[sel], th[sel], r[sel] + (rob[sel] - r[sel]) * f[sel])
        mv = np.abs((rob - r) * f)[sel].max() * 1e3 if sel.any() else 0.0
        # faces across the cut line are clipped on it (a clean edge under the ring band, not a jagged hole);
        # faces wholly inside go
        x, th, r = ring.polar(P)
        sv = x - (lip_x(c, th, r) - cfg["t"] / 2 - band_at(cfg["band_th"], th) + CUT_OVER)
        # kept corners off the cowl (skin standing out past the reach) count as just behind the cut line
        sv = np.where(~hot & (sv > 0), -0.001, sv)
        sb = body_r(body, x, th) - r
        hc = hot[T0]
        part = hc.any(1) & ~hc.all(1)
        dd = hc.any(1)
        P, N, UV, T0, cutv = clip_faces(P, N, UV, T0, dd, part, sv, sb, ring, sp, body)
        near_any = np.r_[near_any, np.zeros(len(P) - len(near_any), bool)]
        clipv.append(cutv)
        drop = np.zeros(len(T0), bool)
        rep.append("side %+d: %d faces clipped on the cut line" % (side, int(part.sum())))
        rep.append("side %+d: lip x %.3f..%.3f, duct end %.3f, %d skin faces cut, %d cowl vertices refitted, "
                   "cowl move max %.2f mm" % (side, xf.min(), xf.max(), x_end, int(dd.sum()), int(sel.sum()), mv))
        newP.append(pos)
        newN.append(nrm)
        newUV.append((uv, C))
        newT.append(T)
    keepT = T0[~drop]
    rep.append("despiked %d skin vertices round the intakes" % despike(P, keepT, near_any))
    # snap open edges the cut left next to a ring onto the ring's outer surface
    ed = np.sort(np.concatenate([keepT[:, [0, 1]], keepT[:, [1, 2]], keepT[:, [2, 0]]]), 1)
    ue, cnt = np.unique(ed, axis=0, return_counts=True)
    ov = np.unique(ue[cnt == 1].reshape(-1))
    oldov = np.unique(_open(T_orig))
    ov = np.setdiff1d(ov, np.concatenate([oldov] + clipv))
    allpos = np.vstack(newP)
    tree = cKDTree(allpos)
    dd, nn = tree.query(P[ov])
    snap = dd < SNAP
    P[ov[snap]] = allpos[nn[snap]]
    rep.append("snapped %d of %d new open-edge vertices onto the lip rings" % (int(snap.sum()), len(ov)))
    # UV islands: one rectangle per intake, side by side, in a free corner of the atlas
    tex_w, tex_h = 480, 200
    uv_all = []
    for k, ((uv, C), pos, T) in enumerate(zip(newUV, newP, newT)):
        y0, x0 = free_rect(cov, tex_w, tex_h)
        cov[y0:y0 + tex_h, x0:x0 + tex_w] = True
        rep.append("UV island %d at texels (%d, %d), %d x %d" % (k, x0, y0, tex_w, tex_h))
        vmax = uv[:, 1].max()
        px = x0 + 4 + uv[:, 0] * (tex_w - 8)
        py = y0 + 4 + uv[:, 1] / vmax * (tex_h - 8)
        uv_all.append(np.stack([px / S, py / S], 1))
        paint(col, orm, px, py, C, pos, T, P, UV, keepT, tex_w, tex_h, x0, y0)
    # write: extended vertex buffer (positions, normals, UV), new primitive-0 indices
    nP = np.vstack([P] + newP)
    nN = np.vstack([N] + newN)
    nUV = np.vstack([UV] + uv_all)
    T_new, o = [], len(P)
    for pos, T in zip(newP, newT):
        T_new.append(T + o)
        o += len(pos)
    tris = np.vstack([keepT] + T_new)
    write(g, m, ai, p0, nP, nN, nUV, tris, a.dst)
    Image.fromarray(col).save(a.maps[0], quality=95)
    Image.fromarray(orm).resize(orm_size, Image.LANCZOS).save(a.maps[1], quality=95)
    print("\n".join(rep))
    return 0


def clip_faces(P, N, UV, T, hot_face, part, sa, sb, ring, sp, body):
    """Remove hot faces; the partly hot ones (part) are clipped to the side max(sa, sb) <= 0 instead (sa: the cut
    line under the ring band, sb: the nacelle body). Vertices on cut edges are shared between neighbouring faces
    (no cracks) and put on the surface that cut them (the fitted cowl sp or the body) when that is within 3 mm.
    Returns the grown P, N, UV, the new triangle list and the indices of the cut vertices."""
    sv = np.maximum(sa, sb)
    cache = {}
    nP, nN, nUV = [], [], []
    n0 = len(P)
    nb = len(sv)

    def cut(a, b):
        key = (min(a, b), max(a, b))
        if key not in cache:
            t = sv[a] / (sv[a] - sv[b])
            q = P[a] + t * (P[b] - P[a])
            qx, qt, qr = ring.polar(q[None])
            on_body = sb[a] + t * (sb[b] - sb[a]) >= sa[a] + t * (sa[b] - sa[a])
            rt = body_r(body, qx, qt) if on_body else sp(qx, qt)
            if rt[0] > 0 and abs(rt[0] - qr[0]) < 0.003:
                q = ring.point(qx, qt, rt)[0]
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
            ina = a < nb and sv[a] <= 0
            inb = b < nb and sv[b] <= 0
            if ina:
                poly.append(a)
            if ina != inb:
                poly.append(cut(a, b))
        for k in range(1, len(poly) - 1):
            out.append((poly[0], poly[k], poly[k + 1]))
    T = np.vstack([T[~hot_face]] + ([np.array(out, np.int64)] if out else []))
    if nP:
        P = np.vstack([P, np.array(nP)])
        N = np.vstack([N, np.array(nN)])
        UV = np.vstack([UV, np.array(nUV)])
    return P, N, UV, T, np.arange(n0, len(P))


def despike(P, T, region, iters=15):
    """Pull the generator's needle spikes in region (vertices standing off the mean of their neighbours by more
    than SPIKE of their mean edge length) back onto that mean. The graph is welded by position first (the skin is
    split along its UV seams), so seam copies move together; edges open after the weld stay. Returns how many
    vertices moved."""
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
        c = np.zeros(nw)
        el = np.zeros(nw)
        L = np.linalg.norm(Q[E[:, 0]] - Q[E[:, 1]], axis=1)
        for a, b in ((0, 1), (1, 0)):
            np.add.at(s, E[:, a], Q[E[:, b]])
            np.add.at(c, E[:, a], 1)
            np.add.at(el, E[:, a], L)
        ok = c > 0
        avg = np.zeros((nw, 3))
        avg[ok] = s[ok] / c[ok, None]
        d = np.linalg.norm(Q - avg, axis=1)
        spk = ok & reg & ~fixed & (d > SPIKE * el / np.maximum(c, 1))
        if not spk.any():
            break
        Q[spk] = avg[spk]
        moved |= spk
    P[used] = Q[wid]
    return int(moved.sum())


def _open(T):
    """Vertices on open edges of triangles T"""
    ed = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), 1)
    ue, cnt = np.unique(ed, axis=0, return_counts=True)
    return ue[cnt == 1].reshape(-1)


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


def paint(col, orm, px, py, C, pos, T, P, UV, keepT, w, h, rx, ry):
    """Paint one intake's rectangle: per texel column (round the intake) the lip takes the median paint of the
    cowl skin just behind the ring at that angle (sampled through the old UVs), the duct and the face are dark;
    the lip's inner half fades into the duct tone over its last rows"""
    S = col.shape[0]
    tree = cKDTree(P[np.unique(keepT)])
    keepv = np.unique(keepT)
    # rows of the grid: px, py are per vertex on an (nr x NT+1) grid
    ncol = NT + 1
    nr = len(px) // ncol
    gx, gy = px.reshape(nr, ncol), py.reshape(nr, ncol)
    gc = C.reshape(nr, ncol)
    gp = pos.reshape(nr, ncol, 3)
    # paint sample per column: skin points 2..7 mm behind the ring's rear row at that angle
    lip_rgb = np.zeros((ncol, 3))
    lip_orm = np.zeros((ncol, 3))
    for k in range(ncol):
        q = gp[0, k] - np.array([0.004, 0.0, 0.0])
        _, ii = tree.query(q, k=12)
        vi = keepv[ii]
        uv = UV[vi]
        tx = np.clip((uv[:, 0] * S).astype(int), 0, S - 1)
        ty = np.clip((uv[:, 1] * S).astype(int), 0, S - 1)
        lip_rgb[k] = np.median(col[ty, tx].astype(float), 0)
        lip_orm[k] = np.median(orm[ty, tx].astype(float), 0)
    # smooth the lip paint round the intake a little (camouflage edges stay, speckle goes)
    kk = np.exp(-0.5 * (np.arange(-3, 4) / 1.5) ** 2)
    kk /= kk.sum()
    lip_rgb = np.stack([np.convolve(np.r_[lip_rgb[-3:, i], lip_rgb[:, i], lip_rgb[:3, i]], kk, "valid")
                        for i in range(3)], 1)
    lip_orm = np.stack([np.convolve(np.r_[lip_orm[-3:, i], lip_orm[:, i], lip_orm[:3, i]], kk, "valid")
                        for i in range(3)], 1)
    yy, xx = np.mgrid[ry:ry + h, rx:rx + w]
    # texel -> (column, row) of the grid: columns are uniform in x, rows by their v
    colf = np.clip((xx - gx[0, 0]) / (gx[0, -1] - gx[0, 0]) * (ncol - 1), 0, ncol - 1)
    rowv = gy[:, 0]
    rowf = np.interp(yy, rowv, np.arange(nr))
    ci = np.clip(np.round(colf).astype(int), 0, ncol - 1)
    ri = np.clip(np.floor(rowf).astype(int), 0, nr - 1)
    cl = gc[ri, 0]
    # duct share: 0 on the lip paint, 1 in the duct; the last lip rows blend
    dark_row = np.isin(gc[:, 0], (1, 2)).astype(float)
    duct = np.interp(rowf, np.arange(nr), dark_row)
    rgb = lip_rgb[ci] * (1 - duct[..., None]) + np.array(DUCT_TONE, float) * duct[..., None]
    rgb = np.where((cl == 2)[..., None], np.array(FACE_TONE, float), rgb)
    o = lip_orm[ci] * (1 - duct[..., None]) + np.array(DUCT_ORM, float) * duct[..., None]
    col[ry:ry + h, rx:rx + w] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)
    orm[ry:ry + h, rx:rx + w] = np.clip(o + 0.5, 0, 255).astype(np.uint8)


def write(g, m, ai, p0, nP, nN, nUV, tris, dst):
    """Replace the main skin's vertex attributes (positions back in the node's frame) and primitive 0's indices;
    every other node keeps its moved positions from the Model (write() of plane_polish for those)"""
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


if __name__ == "__main__":
    sys.exit(main())
