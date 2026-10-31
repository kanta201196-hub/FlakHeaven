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
The GLB is read only for its UVs; images inside it are not touched (Godot uses the extracted files next to it).

  python3 -I tex_clean.py <model.glb> <map.jpg> <out.jpg> [--pad 24] [--camo 2 [--sigma 3.5] [--detail 0.7] [--wear 0.35]]"""
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


def crisp_camo(img, cov, ntones, sigma, detail_k, report, size_k=1.0, wear=0.35):
    """Redraw the camouflage borders of a baked colour map as anti-aliased curves, keeping detail and some wear"""
    rgb = img.astype(np.float32) / 255.0
    F = lab(rgb)
    lum = F[..., 0]
    # paint candidates: covered, not near-black (intakes, nozzles, gaps) and not near-white
    cand = cov & (lum > 0.06) & (lum < 0.85)
    idx = np.flatnonzero(cand)
    rng = np.random.default_rng(3)
    sub = F.reshape(-1, 3)[rng.choice(idx, min(len(idx), 200000), replace=False)]
    # the tones and the «other» stuff: cluster with spare centres, keep the ntones biggest saturated-ish ones
    C = kmeans(sub, ntones + 3)
    d = ((sub[:, None, :] - C[None]) ** 2).sum(-1)
    cnt = np.bincount(d.argmin(1), minlength=len(C))
    order = np.argsort(-cnt)
    tones = C[order[:ntones]]
    report.append("tones (L,a,b): " + "; ".join("%.3f %.3f %.3f (%.0f%%)" % (*t, 100 * cnt[o] / len(sub))
                                               for t, o in zip(tones, order[:ntones])))
    # distance of every texel to each tone; painted = close to a tone
    D = np.stack([((F - t) ** 2).sum(-1) for t in tones], 0)
    dmin = D.min(0)
    spread = np.median(np.sqrt(dmin[cand]))
    painted = cand & (np.sqrt(dmin) < 3.0 * spread + 0.03)
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
    a = ap.parse_args()
    im = Image.open(a.src).convert("RGB")
    arr = np.asarray(im).copy()
    size = arr.shape[0]
    cov = coverage(a.glb, size)
    rep = ["%s: %dx%d, islands %.1f%% of the atlas" % (os.path.basename(a.src), size, size, 100 * cov.mean())]
    if a.camo:
        arr = crisp_camo(arr, cov, a.camo, a.sigma * size / 4096.0, a.detail, rep, size / 4096.0, a.wear)
    arr = pad(arr, cov, a.pad)
    Image.fromarray(arr).save(a.dst, quality=a.quality, subsampling=0)
    print("\n".join(rep))


if __name__ == "__main__":
    main()
