"""Archipelago sea surface maps (Kanta 06.11, «да на план по воде»): a seamless, time-looping wave animation made
by the Tessendorf FFT method (the way ocean sims do it) and baked into a Texture2DArray, one layer per frame.

Why baked: the ground shader runs on every preset, Compatibility included, so it samples a texture instead of
computing the FFT on the GPU. The waves tile in space (FFT is periodic over the tile) and loop in time (every
wave frequency is rounded to a multiple of 2*pi/LOOP), so neither a seam nor a jump shows.

Channels of each layer (RGBA8):
  R, G  wave slope dh/dx, dh/dz, 0.5 + slope * SLOPE_K (the shader turns it into a normal)
  B     height 0..1 (crest lighting)
  A     foam: where the choppy surface folds (Jacobian < threshold), built up and decaying over time, like
        whitecaps that linger after the crest passes

Units: one tile is TILE px of the game world (6 px per metre, docs/biome2/models-pipeline.md), wavelengths
from ~8 px ripples up to the tile; the wind blows along WIND. Wave speed follows deep-water dispersion scaled to
the old analytic waves of ground3d.gdshader (omega = 2.2 * sqrt(k), k in rad/px).

Run (repo root; numpy, Pillow):  python3 -I game/tools/water/water_maps.py [--preview=/abs/dir]
-> game/art/water/sea_waves.png (TILE x TILE*FRAMES, imported as a Texture2DArray with FRAMES vertical slices).
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "game", "art", "water", "sea_waves.png")

N = 256            # texels per tile side
TILE = 256.0       # tile size in world px (texel = 1 px)
FRAMES = 64        # layers of the array
LOOP = 24.0        # seconds of one loop
WIND = np.array([0.82, 0.57])
PEAK = 70.0        # wavelength of the spectrum peak, px
SPREAD = 10.0      # directional spreading exponent (cos^SPREAD around the wind)
SLOPE_RMS = 0.13   # target rms slope of the whole surface
CHOP = 1.0         # horizontal displacement strength (sharper crests, folds -> foam)
SLOPE_K = 1.6      # slope encoding: channel = 0.5 + slope * SLOPE_K
SEED = 11


def spectrum():
    """Initial spectrum h0(k) and its frequencies: a Phillips-like spectrum with a peak at PEAK px, cos^SPREAD
    spreading around the wind, waves against the wind weak, ripples under 8 px cut"""
    rng = np.random.default_rng(SEED)
    f = np.fft.fftfreq(N, TILE / N) * 2 * np.pi
    kx, kz = np.meshgrid(f, f)
    k = np.hypot(kx, kz)
    k[0, 0] = 1e-9
    kp = 2 * np.pi / PEAK
    amp = np.exp(-1.25 * (kp / k) ** 2) / k ** 4          # Pierson-Moskowitz shape, rises to the peak, then falls
    cosw = (kx * WIND[0] + kz * WIND[1]) / k
    amp *= np.where(cosw > 0, np.abs(cosw) ** SPREAD, 0.08 * np.abs(cosw) ** SPREAD)
    amp *= np.exp(-(k / (2 * np.pi / 8.0)) ** 4)          # no waves shorter than ~8 px (texel size)
    amp[0, 0] = 0.0
    h0 = (rng.normal(size=(N, N)) + 1j * rng.normal(size=(N, N))) * np.sqrt(amp / 2.0)
    step = 2 * np.pi / LOOP
    om = np.maximum(np.round(2.2 * np.sqrt(k) / step), 1.0) * step   # loop in time; nothing frozen
    return kx, kz, k, h0, om


def fields(kx, kz, k, h0, om, t):
    """Height, slopes and Jacobian of the choppy surface at time t"""
    neg = np.conj(np.roll(np.flip(h0), 1, axis=(0, 1)))   # h0(-k)
    e = np.exp(1j * om * t)
    H = h0 * e + neg * np.conj(e)
    ifft = lambda a: np.real(np.fft.ifft2(a))
    h = ifft(H)
    sx = ifft(1j * kx * H)
    sz = ifft(1j * kz * H)
    jxx = 1.0 - CHOP * ifft(kx * kx / k * H)
    jzz = 1.0 - CHOP * ifft(kz * kz / k * H)
    jxz = -CHOP * ifft(kx * kz / k * H)
    return h, sx, sz, jxx * jzz - jxz * jxz


def blur(a):
    """Soft 5-tap blur, wrapping (the tile is periodic): a fold is one or two texels wide, and magnified on screen
    it read as a hard white square; blurred it reads as a streak of foam"""
    for ax in (0, 1):
        a = (np.roll(a, -2, ax) + 4 * np.roll(a, -1, ax) + 6 * a + 4 * np.roll(a, 1, ax) + np.roll(a, 2, ax)) / 16.0
    return np.clip(a * 1.6, 0.0, 1.0)


def build():
    """All FRAMES layers as one RGBA strip; foam accumulates over two loops so the first frame already carries
    the foam left by the last one"""
    kx, kz, k, h0, om = spectrum()
    h, sx, sz, _ = fields(kx, kz, k, h0, om, 0.0)
    scale = SLOPE_RMS / np.sqrt(np.mean(sx ** 2 + sz ** 2))
    h0 = h0 * scale
    # choppiness relative to the scaled waves: fold where the surface is steep
    hs, ss, js = [], [], []
    for i in range(FRAMES):
        h, sx, sz, J = fields(kx, kz, k, h0, om, LOOP * i / FRAMES)
        hs.append(h)
        ss.append((sx, sz))
        js.append(J)
    hmin = min(a.min() for a in hs)
    hmax = max(a.max() for a in hs)
    jq = np.quantile(np.stack(js), 0.003)   # the 0.3 % most folded texels start foam
    foam = np.zeros((N, N))
    out = []
    dt = LOOP / FRAMES
    for rnd in range(2):
        for i in range(FRAMES):
            new = blur(np.clip((jq + 0.03 - js[i]) / 0.06, 0.0, 1.0))
            foam = np.maximum(foam * np.exp(-dt / 1.0), new)   # whitecaps fade in ~1 s
            if rnd == 1:
                sx, sz = ss[i]
                px = np.dstack([0.5 + sx * SLOPE_K, 0.5 + sz * SLOPE_K, (hs[i] - hmin) / (hmax - hmin), foam])
                out.append(np.clip(px * 255.0 + 0.5, 0, 255).astype(np.uint8))
    print("slope rms %.3f, slope max %.3f, foam cover %.1f %%" % (
        np.sqrt(np.mean(np.stack([s[0] for s in ss]) ** 2) * 2), max(np.abs(s[0]).max() for s in ss),
        100.0 * np.mean(np.stack(out)[..., 3] > 64)))
    return np.concatenate(out, axis=0)


def preview(strip, out_dir):
    """Top-down shaded frames (sun, sky gradient, foam) as a GIF and a 2x2 tile check, for the review page"""
    os.makedirs(out_dir, exist_ok=True)
    frames = strip.reshape(FRAMES, N, N, 4).astype(np.float32) / 255.0
    sun = np.array([-0.5, 0.62, -0.6])
    sun /= np.linalg.norm(sun)
    imgs = []
    for f in frames:
        sx, sz = (f[..., 0] - 0.5) / SLOPE_K, (f[..., 1] - 0.5) / SLOPE_K
        n = np.dstack([-sx, np.ones_like(sx), -sz])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        v = np.array([0.0, 0.88, 0.47])
        r = 2 * (n @ v)[..., None] * n - v
        fr = 0.02 + 0.98 * (1 - np.clip(n @ v, 0, 1)) ** 5
        sky = np.array([0.35, 0.55, 0.8]) * (0.7 + 0.5 * (1 - r[..., 1:2]))
        base = np.array([0.08, 0.32, 0.38]) * (0.75 + 0.5 * np.clip(n @ sun, 0, 1))[..., None]
        sp = np.clip(n @ (sun + v) / np.linalg.norm(sun + v), 0, 1) ** 300 * 3
        c = base * (1 - fr[..., None]) + sky * fr[..., None] * 1.5 + sp[..., None]
        c = c * (1 - f[..., 3:4] * 0.85) + 0.9 * f[..., 3:4] * 0.85
        imgs.append(Image.fromarray((np.clip(c, 0, 1) ** (1 / 1.2) * 255).astype(np.uint8)))
    tiled = [Image.fromarray(np.tile(np.asarray(im), (2, 2, 1))) for im in imgs]
    tiled[0].save(os.path.join(out_dir, "waves_tile2x2.png"))
    tiled[0].save(os.path.join(out_dir, "waves.gif"), save_all=True, append_images=tiled[1:],
                  duration=int(LOOP / FRAMES * 1000), loop=0)


def main(argv):
    strip = build()
    opt = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    if "preview" in opt:
        preview(strip, opt["preview"])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(strip, "RGBA").save(OUT, optimize=True)
    print("wrote %s (%d x %d, %d frames, %.0f s loop)" % (OUT, N, N * FRAMES, FRAMES, LOOP))


if __name__ == "__main__":
    main(sys.argv[1:])
