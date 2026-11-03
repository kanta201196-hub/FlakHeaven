"""Hangar plane textures (Kanta s14: «окраска посредственная… чётко и красиво, как настоящий камуфляж, со следами
эксплуатации, а не пиксели»): island padding for every map and crisp camouflage edges on the baked paint.

1. Padding. The UV atlases of the remeshed planes are cut into many islands on a black gutter; with mipmaps the
   gutter bleeds into the island borders, so every seam reads as a dark hairline or a grimy fringe at a distance.
   Every texel outside the islands (coverage rasterised from the GLB's own UV triangles) takes the colour of the
   nearest island texel, out to --pad texels (colour, ORM and normal maps alike).
2. Crisp camouflage (--camo N, colour map only). The baked paint has N camouflage tones whose borders are soft,
   torn or smeared (painted at a low effective resolution, then upscaled). Each painted texel is given to its
   nearest tone (k-means on the painted texels, so the tones are the plane's own), the tone fields are smoothed
   inside the islands, and the borders are redrawn as anti-aliased curves one texel wide. Each tone is then one
   flat colour times the fine detail of the source (panel lines, rivets, grime: the source luminance against its
   local mean) and a faint large-scale wear (the source's own slow variation, at a fraction). Texels far from
   every tone (canopy frame, intakes, nozzles, metal, the belly colour) keep the source.
3. Even patches (--even K, colour or ORM map). A generator texture («Оса» 2, Meshy) is a patchwork: every
   texture patch got its own tone, roughness and metalness, so the skin reads as a quilt of polygonal patches in
   the hangar light. On the paint (texels within a band round the common paint tone of the colour map, --ref for
   the ORM map; intakes, nozzles and gaps are left alone) each channel becomes its common median plus the
   source's fine detail and a share of its slow variation (even_patches).
4. Dent shading (--dents <mask.png>, colour map). The generator baked light and shadow over the dents of its
   remesh into the paint; once skin_refit.py has rebuilt that skin, the old shading reads as dents again. Inside
   the mask (skin_refit.py --mask) the luminance band of a dent's size is divided out (flatten_dents).
The GLB is read only for its UVs; images inside it are not touched (Godot uses the extracted files next to it).

  python3 -I tex_clean.py <model.glb> <map.jpg> <out.jpg> [--pad 24] [--camo 2 [--sigma 3.5] [--detail 0.7] [--wear 0.35]]
      [--even 1 [--ref <colour map.jpg>] [--even-detail 1] [--even-wear 0.3]] [--dents <mask.png>]
On a normal map --even with a small --even-detail and no wear keeps the panel relief and drops the generator's
crinkle and the tilt of every patch (each patch shaded a little differently).
Recipe of «Оса» 2 (31.10): colour --even 0.9 --even-detail 0.7; ORM --even 1 --ref <colour>; normal --even 1
--ref <colour> --even-detail 0.4 --even-wear 0."""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

Image.MAX_IMAGE_PIXELS = None


def coverage(glb_path, size):
    """Texels covered by any UV triangle of the skin (every primitive and node with TEXCOORD_0), dilated 1 texel"""
    g = glb_io.load(glb_path)
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    for m in g.j["meshes"]:
        for pr in m["primitives"]:
            if "TEXCOORD_0" not in pr["attributes"]:
                continue
            uv = g.accessor(pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
            T = g.accessor(pr["indices"]).reshape(-1, 3)
            px = np.stack([uv[:, 0] * size, uv[:, 1] * size], 1)   # glTF UV: v down from the top = image rows
            for t in T:
                d.polygon([tuple(px[t[0]]), tuple(px[t[1]]), tuple(px[t[2]])], fill=255)
    cov = np.asarray(im) > 0
    return _grow(cov, 1)


def even_patches(img, cov, k, report, ref=None, band=(0.5, 2.0), med=7, wear=0.3, detail=1.0):
    """Even out the patchwork of a generator texture on the paint: per channel, the paint becomes its common median
    plus the source's own fine detail (the source minus its median-filtered self: panel lines, rivets and grime
    stay, the flat offset of every patch goes, and a median follows a patch border without ringing) plus a share
    `wear` of the source's slow variation, so the paint reads used, not new; `detail` scales the fine detail (the
    generator's crinkle noise is part of it). k blends the result over the source. ref: the colour map that tells
    paint from intakes and gaps (img itself when None). The median runs at 4K (an 8K map is halved for it).
    Every size is in texels of a 4K map."""
    from scipy.ndimage import median_filter  # noqa: PLC0415

    a = img.astype(np.float32)
    col = (ref if ref is not None else img).astype(np.float32) / 255.0
    lum = col[..., :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    gl = np.median(lum[cov])
    paint = cov & (lum > band[0] * gl) & (lum < band[1] * gl)
    f = max(a.shape[0] // 4096, 1)
    if f > 1:
        ps = paint.reshape(paint.shape[0] // f, f, paint.shape[1] // f, f).mean((1, 3)).astype(np.float32)
    # soft paint weight: no hard border where paint meets an intake or a gap
    w = np.clip(nblur(paint.astype(np.float32), cov.astype(np.float32), 2.0), 0, 1) * paint
    out = a.copy()
    sh = []
    for c in range(a.shape[2]):
        ch = a[..., c]
        base = np.median(ch[paint])
        if f > 1:
            def up(x):
                return np.asarray(Image.fromarray(x.astype(np.float32)).resize(ch.shape[::-1], Image.BILINEAR))
            small = ch.reshape(ch.shape[0] // f, f, ch.shape[1] // f, f).mean((1, 3))
            mf = up(median_filter(small, size=med, mode="nearest"))
            slow = up(nblur(small, ps, 20.0)) - base
        else:
            mf = median_filter(ch, size=med, mode="nearest")
            slow = nblur(ch, paint.astype(np.float32), 20.0) - base
        fine = ch - mf
        new = base + detail * fine + wear * slow
        out[..., c] = ch + (new - ch) * (k * w)
        sh.append(float(np.abs(new - ch)[paint].mean()))
    report.append("even patches: paint %.0f%% of the islands, mean change per channel %s" % (
        100 * paint.sum() / max(cov.sum(), 1), " ".join("%.1f" % v for v in sh)))
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def _shift(a, dy, dx, fill):
    """a moved by (dy, dx) texels, the uncovered border set to fill"""
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    ys, yd = (slice(dy, h), slice(0, h - dy)) if dy >= 0 else (slice(0, h + dy), slice(-dy, h))
    xs, xd = (slice(dx, w), slice(0, w - dx)) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
    out[ys, xs] = a[yd, xd]
    return out


def _grow(mask, n):
    """Mask dilated by n texels (4-neighbourhood)"""
    m = mask.copy()
    for _ in range(n):
        m = m | _shift(m, 1, 0, False) | _shift(m, -1, 0, False) | _shift(m, 0, 1, False) | _shift(m, 0, -1, False)
    return m


def pad(img, cov, n):
    """Fill up to n texels round the islands with the nearest island colour (mean of covered neighbours)"""
    a = img.astype(np.float32)
    m = cov.copy()
    for _ in range(n):
        acc = np.zeros_like(a)
        cnt = np.zeros(m.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            sm = _shift(m, dy, dx, False)
            acc += _shift(a, dy, dx, 0) * sm[..., None]
            cnt += sm
        new = (~m) & (cnt > 0)
        a[new] = acc[new] / cnt[new][:, None]
        m |= new
        if not new.any():
            break
    return np.clip(a + 0.5, 0, 255).astype(np.uint8)


def gauss1d(s):
    """Normalised 1D gaussian kernel of sigma s (3 sigma radius)"""
    r = int(3 * s + 1)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
    return k / k.sum()


def blur(a, s):
    """Separable gaussian (reflect) on a 2D float array"""
    k = gauss1d(s)
    r = len(k) // 2
    p = np.pad(a, ((r, r), (0, 0)), mode="reflect")
    o = np.zeros_like(a)
    for i, kv in enumerate(k):
        o += kv * p[i:i + a.shape[0]]
    p = np.pad(o, ((0, 0), (r, r)), mode="reflect")
    o2 = np.zeros_like(a)
    for i, kv in enumerate(k):
        o2 += kv * p[:, i:i + a.shape[1]]
    return o2


def nblur(a, w, s):
    """Normalised blur: mean of a over the weight w (islands only), so the gutter does not leak in"""
    return blur(a * w, s) / np.maximum(blur(w, s), 1e-4)


def flatten_dents(img, mask, cov, report, small=4.0, large=40.0, clip=0.12):
    """Take the shading the generator baked over its dents out of the paint where the skin was refitted
    (skin_refit.py --mask): the luminance band between `small` and `large` texels (a dent's light and shadow) is
    divided out, the fine detail (panel lines, rivets, grime) under `small` and the slow variation over `large`
    stay. The correction is clipped to +-clip, so a camouflage edge in the band leaves only a faint halo."""
    from scipy.ndimage import gaussian_filter
    f = img.astype(np.float32) / 255.0
    w = cov.astype(np.float32)
    lum = f @ np.array([0.2126, 0.7152, 0.0722], np.float32) + 1e-3

    def nb(a, s):
        return gaussian_filter(a * w, s) / np.maximum(gaussian_filter(w, s), 1e-4)
    ratio = np.clip(nb(lum, large) / np.maximum(nb(lum, small), 1e-3), 1 - clip, 1 + clip)
    m = np.clip(gaussian_filter(mask.astype(np.float32), small), 0, 1) * w
    gain = 1 + (ratio - 1) * m
    report.append("dent shading: %.1f%% of the islands, mean |gain-1| %.3f there" % (
        100 * (m > 0.5).sum() / max(cov.sum(), 1), float(np.abs(gain - 1)[m > 0.5].mean()) if (m > 0.5).any() else 0))
    return np.clip(f * gain[..., None] * 255 + 0.5, 0, 255).astype(np.uint8)


def lab(rgb):
    """Rough perceptual space (sRGB 0..1 -> L, a, b-like opponent channels) for tone clustering"""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    L = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return np.stack([L * 1.0, (r - g) * 1.6, (0.5 * (r + g) - b) * 1.6], -1)


def kmeans(X, k, it=25, seed=1):
    """k centres of the rows of X (median update, robust to the panel-line outliers)"""
    rng = np.random.default_rng(seed)
    C = X[rng.choice(len(X), k, replace=False)]
    for _ in range(it):
        d = ((X[:, None, :] - C[None]) ** 2).sum(-1)
        lab_ = d.argmin(1)
        for j in range(k):
            if (lab_ == j).any():
                C[j] = np.median(X[lab_ == j], 0)
    return C


def crisp_camo(img, cov, ntones, sigma, detail_k, report, size_k=1.0, wear=0.35, tones=None, keep=None, thr=0.0):
    """Redraw the camouflage borders of a baked colour map as anti-aliased curves, keeping detail and some wear.

    tones: explicit camo tones (rows of L, a, b in the lab() space) instead of k-means; needed when the paint
    shares the map with large non-camo parts (metal, dark machinery) that k-means would take for camo.
    keep: tones that are never repainted (a texel nearest to one of them keeps the source).
    thr: fixed distance to the nearest camo tone under which a texel counts as paint (0 = adaptive)."""
    rgb = img.astype(np.float32) / 255.0
    F = lab(rgb)
    lum = F[..., 0]
    # paint candidates: covered, not near-black (intakes, nozzles, gaps) and not near-white
    cand = cov & (lum > 0.06) & (lum < 0.85)
    idx = np.flatnonzero(cand)
    rng = np.random.default_rng(3)
    sub = F.reshape(-1, 3)[rng.choice(idx, min(len(idx), 200000), replace=False)]
    # the tones and the «other» stuff: cluster with spare centres, keep the ntones biggest saturated-ish ones
    if tones is None:
        C = kmeans(sub, ntones + 3)
        d = ((sub[:, None, :] - C[None]) ** 2).sum(-1)
        cnt = np.bincount(d.argmin(1), minlength=len(C))
        order = np.argsort(-cnt)
        tones = C[order[:ntones]]
        report.append("tones (L,a,b): " + "; ".join("%.3f %.3f %.3f (%.0f%%)" % (*t, 100 * cnt[o] / len(sub))
                                                   for t, o in zip(tones, order[:ntones])))
    else:
        tones = np.asarray(tones, np.float32)
        ntones = len(tones)
        report.append("given tones (L,a,b): " + "; ".join("%.3f %.3f %.3f" % tuple(t) for t in tones))
    # distance of every texel to each tone; painted = close to a camo tone and closer to it than to any kept one
    D = np.stack([((F - t) ** 2).sum(-1) for t in tones], 0)
    dmin = D.min(0)
    if thr > 0:
        painted = cand & (np.sqrt(dmin) < thr)
    else:
        spread = np.median(np.sqrt(dmin[cand]))
        painted = cand & (np.sqrt(dmin) < 3.0 * spread + 0.03)
    if keep is not None:
        K = np.stack([((F - np.asarray(t, np.float32)) ** 2).sum(-1) for t in keep], 0).min(0)
        painted &= dmin < K
    w = painted.astype(np.float32)
    # smoothed tone fields inside the paint
    P = np.stack([nblur((D.argmin(0) == j).astype(np.float32), w, sigma) for j in range(ntones)], 0)
    best = P.argmax(0)
    # anti-aliased borders: margin of the best field over the runner-up, against its own slope (one texel ramp)
    Ps = np.sort(P, 0)
    marg = Ps[-1] - Ps[-2]
    gy, gx = np.gradient(marg)
    slope = np.sqrt(gx * gx + gy * gy) + 1e-4
    a_best = np.clip(0.5 + 0.5 * marg / slope, 0.5, 1.0)
    second = np.argsort(P, 0)[-2]
    # flat tone colours (sRGB) from the source texels firmly inside each tone
    flat = []
    for j in range(ntones):
        m = painted & (best == j) & (marg > 0.5)
        flat.append(np.median(rgb[m], 0) if m.any() else np.median(rgb[painted], 0))
    flat = np.array(flat)
    report.append("flat tones sRGB: " + "; ".join("%.3f %.3f %.3f" % tuple(f) for f in flat))
    base = flat[best] * a_best[..., None] + flat[second] * (1 - a_best[..., None])
    # fine detail (panel lines, rivets, grime) and slow wear from the source luminance within the paint
    mean_s = nblur(lum, w, 2.0 * size_k)
    det = np.clip(lum / np.maximum(mean_s, 1e-3), 0.55, 1.35)
    det = 1.0 + (det - 1.0) * detail_k
    tone_l = np.array([lab(f[None, None])[0, 0, 0] for f in flat])
    tl = np.maximum(tone_l[best] * a_best + tone_l[second] * (1 - a_best), 1e-3)
    # wear: the source's own mottling (fading, grime, touch-ups) kept at a fraction, so the paint reads used, not new
    slow = 1.0 + np.clip(nblur(lum, w, 12 * sigma) / tl - 1.0, -0.25, 0.25) * 0.35
    slow *= 1.0 + np.clip(nblur(lum, w, 5.0 * size_k) / tl - 1.0, -0.2, 0.2) * wear
    new = base * (det * slow)[..., None]
    # soft hand-over to the untouched source at the edge of the painted area
    wp = np.clip(nblur(w, cov.astype(np.float32), 1.0), 0, 1) * w
    out = rgb * (1 - wp[..., None]) + new * wp[..., None]
    report.append("painted texels %.1f%% of the islands" % (100 * painted.sum() / max(cov.sum(), 1)))
    return np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8)


def main():
    """Command line: one map in, one map out"""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("glb")
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--pad", type=int, default=24)
    ap.add_argument("--camo", type=int, default=0)
    ap.add_argument("--sigma", type=float, default=3.5)
    ap.add_argument("--detail", type=float, default=0.7)
    ap.add_argument("--wear", type=float, default=0.35)
    ap.add_argument("--quality", type=int, default=94)
    ap.add_argument("--tones", default="", help="camo tones 'L,a,b;L,a,b;...' in the lab() space (else k-means)")
    ap.add_argument("--keep", default="", help="non-camo tones 'L,a,b;...' that are never repainted")
    ap.add_argument("--paint-thr", dest="paint_thr", type=float, default=0.0)
    ap.add_argument("--even", type=float, default=0.0)
    ap.add_argument("--ref", default="", help="colour map that tells the paint apart (for --even on ORM)")
    ap.add_argument("--even-detail", dest="even_detail", type=float, default=1.0)
    ap.add_argument("--even-wear", dest="even_wear", type=float, default=0.3)
    ap.add_argument("--dents", default="", help="UV mask of the refitted skin (skin_refit.py --mask): flatten the "
                    "baked dent shading there")
    a = ap.parse_args()
    im = Image.open(a.src).convert("RGB")
    arr = np.asarray(im).copy()
    size = arr.shape[0]
    cov = coverage(a.glb, size)
    rep = ["%s: %dx%d, islands %.1f%% of the atlas" % (os.path.basename(a.src), size, size, 100 * cov.mean())]
    if a.even:
        ref = None
        if a.ref:
            ref = np.asarray(Image.open(a.ref).convert("RGB").resize((size, size), Image.BILINEAR))
        arr = even_patches(arr, cov, a.even, rep, ref, detail=a.even_detail, wear=a.even_wear)
    if a.dents:
        mk = np.asarray(Image.open(a.dents).convert("L").resize((size, size), Image.BILINEAR)) > 127
        k = size / 4096.0
        arr = flatten_dents(arr, mk, cov, rep, small=4.0 * k, large=40.0 * k)
    if a.camo:
        def tl(t):
            return [[float(v) for v in r.split(",")] for r in t.split(";")] if t else None
        arr = crisp_camo(arr, cov, a.camo, a.sigma * size / 4096.0, a.detail, rep, size / 4096.0, a.wear,
                         tl(a.tones), tl(a.keep), a.paint_thr)
    arr = pad(arr, cov, a.pad)
    Image.fromarray(arr).save(a.dst, quality=a.quality, subsampling=0)
    print("\n".join(rep))


if __name__ == "__main__":
    main()
