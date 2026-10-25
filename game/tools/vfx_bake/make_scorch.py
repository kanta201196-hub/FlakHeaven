"""Bakes the blast scorch decal (VFX-06, 2026-10-24): game/art/vfx/scorch.png.

A real blast mark is not a soft disc: it is near-black in the middle, turns to burnt brown soil outward and
ends in a ragged rim with soot rays thrown out along the ground and loose specks beyond. The mask here is
built the same way:
  - radius warped by low-frequency noise over the angle (lumpy, never a circle);
  - thin radial rays (high-frequency noise over the angle) that reach further out than the body;
  - fbm breakup near the rim and scattered specks outside it.
Colour: Poly Haven "Burned Ground 01" (CC0, Rob Tuytel) for the detail, darkened toward the centre; its pale
straw blades are filtered out (they looked like hay on large marks).
Straight alpha, RGBA 1024 px, transparent border so the decal never shows its box edge.

Run from the repo root:
  python3 game/tools/vfx_bake/make_scorch.py BURNED_GROUND_DIFF.jpg game/art/vfx/scorch.png [--seed 7]
Source: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/burned_ground_01/burned_ground_01_diff_1k.jpg
Dependencies: Pillow, numpy.
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter

SIZE = 1024
STRAW_PX = 9   # odd filter size in px; straw blades in the 1k source are 2-6 px wide


def periodic_noise(rng: np.random.Generator, theta: np.ndarray, harmonics: int, falloff: float) -> np.ndarray:
    """Smooth noise over the angle, seamless at 2*pi: a sum of sines with random phases, amplitude 1/k^falloff."""
    out = np.zeros_like(theta)
    for k in range(1, harmonics + 1):
        out += np.sin(k * theta + rng.uniform(0, 2 * np.pi)) / k ** falloff
    return out / np.abs(out).max()


def fbm(rng: np.random.Generator, size: int, octaves: int, base: int) -> np.ndarray:
    """Value-noise fbm in 0..1 from upscaled random grids (bicubic), octave weights halving."""
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = base * 2 ** o
        grid = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
        out += amp * np.asarray(grid.resize((size, size), Image.BICUBIC), dtype=np.float64) / 255.0
        total += amp
        amp *= 0.5
    return out / total


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def bake(src: str, out: str, seed: int) -> None:
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    c = (SIZE - 1) / 2.0
    dx, dy = (xx - c) / c, (yy - c) / c
    d = np.hypot(dx, dy)                     # 0 centre, 1 edge midpoint
    theta = np.arctan2(dy, dx)

    lumps = periodic_noise(rng, theta, 9, 1.1)       # body outline
    rays = np.clip(periodic_noise(rng, theta, 140, 0.25), 0, 1) ** 1.8  # thin soot rays
    grain = fbm(rng, SIZE, 6, 4)
    rim = fbm(rng, SIZE, 4, 24)                      # mid-size bites out of the rim
    specks = fbm(rng, SIZE, 3, 96)

    body_r = 0.58 + 0.12 * lumps                     # body radius 0.46..0.70
    dn = d / body_r + (rim - 0.5) * 0.55             # 1 at the ragged rim
    body = 1.0 - smoothstep(0.82, 1.02, dn)
    # rays: start inside the body, run out to ~0.92, thinning and fading with distance
    ray_len = body_r + 0.36 * rays * (0.7 + 0.6 * grain)
    ray = smoothstep(ray_len, body_r * 0.9, d) * (rays > 0.04) * smoothstep(0.0, 0.25, rays)
    ray *= 0.7 + 0.3 * rim
    # loose specks in a band just outside the rim
    band = smoothstep(1.35, 1.0, d / body_r) * smoothstep(0.85, 1.0, dn)
    speck = (specks > 0.70).astype(np.float64) * band
    alpha = np.maximum.reduce([body, ray, speck * 0.9])
    alpha *= smoothstep(0.98, 0.9, d)                # transparent box border
    alpha = np.clip(alpha, 0, 1)

    tex = Image.open(src).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    # the photo has pale burnt straw blades; on a large mark they read as hay lying on the ground (s11 note 27),
    # so a grey opening (min, then max filter) wipes out every bright stroke thinner than STRAW_PX
    tex = tex.filter(ImageFilter.MinFilter(STRAW_PX)).filter(ImageFilter.MaxFilter(STRAW_PX))
    rgb = np.asarray(tex, dtype=np.float64) / 255.0
    lum = rgb.mean(axis=2, keepdims=True)
    detail = 0.35 * rgb + 0.65 * lum                 # mostly luminance: soot, not straw
    # darkness: near-black in the middle, burnt soil toward the rim
    core = smoothstep(1.0, 0.1, np.clip(dn, 0, 2))[..., None]
    rgb = detail * (0.42 - 0.38 * core) + np.array([0.010, 0.008, 0.006]) * core
    rgb = np.clip(rgb * (0.8 + 0.4 * grain[..., None]), 0, 1)
    # alpha is strongest in the core: a solid black middle and a thinner broken edge
    alpha = alpha * (0.5 + 0.5 * core[..., 0])

    rgba = np.dstack([rgb, alpha])
    Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBA").save(out, optimize=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    bake(a.src, a.out, a.seed)


if __name__ == "__main__":
    main()
