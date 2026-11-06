"""Limestone shore rocks of the Archipelago: the cliff a31_cliff_a and the rock a33_rock (Kanta's weak-models list
28.10.2026, deferred until biome 2 came back on 06.11: the old ones read as «надутые шары» — inflated balls
without layers; rule G7 of docs/standards/art-quality-bar.md).

What a Mediterranean limestone coast shows, and what is built here: thick near-horizontal beds that stand out as
broken ledges, vertical joints that split the face into blocks, a wave-cut notch along the foot, fallen blocks at
the waterline, a pale grey-cream stone with grey karst streaks under the ledges, a dark wet tide band with a
green-black film low down and white salt crust just above it. Generic forms, no real landmark.

The machinery is rock_spires.py (signed-distance field → surface nets → quadric decimation → Cycles data bakes →
numpy layers → GLB with albedo, ORM and normal maps). This file adds the shore shapes (SHORE) and the limestone
layers (limestone_layers replaces rock_spires.layers for these models); everything else is shared, so a fix in
the bake reaches both biomes.

Run (repo root; bpy 5.2 pip module, numpy, Pillow, pymeshlab, scipy; no network; ~2-4 min a rock on 4 cores):
  python3 -I game/tools/blender/shore_cliffs.py [--out=game/models/biome2] [--only=a31_cliff_a] [--size=1024]
  python3 -I game/tools/blender/shore_cliffs.py --preview=/abs/dir   (shape only, no Blender)
-> <out>/<name>.glb; Godot's import extracts <name>_<name>_{albedo,orm,normal}.jpg next to it (BC7, rule T3).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402

import rock_spires as rs  # noqa: E402
from rock_spires import Column, Spire, fbm, sstep  # noqa: E402

# profiles (t = y / h, radius factor): a block of the cliff — wave-cut notch at the foot (0.04-0.12), a straight
# jointed face, a rounded, weathered top edge
BLOCK = [(0.0, 0.96), (0.04, 0.84), (0.1, 0.82), (0.16, 0.95), (0.4, 0.96), (0.7, 0.93), (0.86, 0.88), (0.95, 0.76),
         (1.0, 0.5)]
# a lone shore rock: notched foot, ledged flanks, a low rounded crown
ROCK = [(0.0, 1.0), (0.06, 0.82), (0.16, 0.88), (0.4, 0.86), (0.62, 0.78), (0.8, 0.62), (0.92, 0.42), (1.0, 0.12)]

SHORE = {
    # a stretch of cliff: five jointed blocks of different height in a slightly curved row, flat-bedded, ledges
    # strong, few deep alcoves (sea caves), fallen blocks at the foot
    "a31_cliff_a": Spire(seed=53, cols=[
        Column(-0.36, 0.05, 0.62, 0.17, BLOCK, lean=(0.01, 0.0), ell=0.28, ell_a=0.1, ledge=0.035, flute=0.012,
               bump=0.02, cap_top=0.03, alcoves=3),
        Column(-0.16, -0.02, 0.74, 0.19, BLOCK, lean=(0.0, -0.01), ell=0.3, ell_a=0.0, ledge=0.04, flute=0.01,
               bump=0.02, cap_top=0.03, alcoves=3),
        Column(0.06, -0.05, 0.68, 0.18, BLOCK, lean=(-0.01, 0.0), ell=0.26, ell_a=-0.05, ledge=0.035, flute=0.012,
               bump=0.02, cap_top=0.035, alcoves=2),
        Column(0.27, -0.02, 0.55, 0.17, BLOCK, lean=(0.0, 0.01), ell=0.3, ell_a=0.1, ledge=0.04, flute=0.01,
               bump=0.022, cap_top=0.03, alcoves=3),
        Column(0.44, 0.06, 0.38, 0.13, BLOCK, lean=(0.01, 0.0), ell=0.25, ell_a=0.25, ledge=0.03, flute=0.01,
               bump=0.02, cap_top=0.03, alcoves=1)],
        bed=0.085, tilt=(0.015, -0.01), warp=0.025, apron_h=0.06, apron_r=0.5, blocks=26, big_blocks=4,
        fillet=0.05),
    # a single shore rock: a broad low stack, two beds visible, notched at the water
    "a33_rock": Spire(seed=61, cols=[
        Column(0.0, 0.0, 0.4, 0.36, ROCK, lean=(0.03, 0.01), ell=0.3, ell_a=0.4, ledge=0.055, flute=0.015,
               bump=0.025, cap_top=0.035, alcoves=2),
        Column(0.22, 0.14, 0.24, 0.18, ROCK, lean=(0.02, 0.02), ell=0.2, ell_a=1.2, ledge=0.03, flute=0.015,
               bump=0.03, alcoves=1)],
        bed=0.075, tilt=(0.03, 0.02), warp=0.03, apron_h=0.05, apron_r=0.48, blocks=14, big_blocks=2, fillet=0.06),
}

LIME = np.array([0.65, 0.62, 0.56], np.float32)     # pale grey-cream limestone (biome rock_tint 0.8/0.78/0.72)
KARST = np.array([0.36, 0.36, 0.35], np.float32)    # grey solution streaks under ledges
WET = np.array([0.21, 0.22, 0.2], np.float32)       # wet tide band
FILM = np.array([0.12, 0.14, 0.1], np.float32)      # green-black biofilm at the waterline
SALT = np.array([0.86, 0.85, 0.8], np.float32)
TIDE = 0.07                                          # tide band height (model units above the foot)


def limestone_layers(P, N, AOs, AOl, sp: Spire, rock, nh, scan_mean, scan_std, sand):
    """rock_spires.layers for limestone: the same cliff photo along the beds, graded pale grey-cream, grey karst
    streaks, a dark wet tide band with biofilm and a salt line above it, light dust on tops (no desert varnish)"""
    k, f, hard = rs.strata(P, sp)
    yw = rs.strata_y(P, sp)
    col, w = rs._triplanar(rock, P, N, yw, rs.TEX_TILE)
    lum = col @ np.array([0.299, 0.587, 0.114], np.float32)
    col = col + (0.42 - lum[:, None]) * 0.35
    m, s = col.mean(0), col.std(0) + 1e-4
    col = (col - m) / s * np.minimum(scan_std * 0.9, s) + LIME
    lum = col @ np.array([0.299, 0.587, 0.114], np.float32)
    col = col * 0.55 + lum[:, None] * 0.45          # limestone is nearly grey
    tints = np.array([[1.04, 1.02, 0.97], [0.97, 0.96, 0.94], [1.06, 1.03, 0.95], [0.93, 0.93, 0.92],
                      [1.02, 0.99, 0.92]], np.float32)
    ti = rs._hash(k.astype(np.int64), np.full(k.shape, 9, np.int64), np.zeros(k.shape, np.int64), sp.seed) * 4.999
    col = col * (tints[ti.astype(int)] * 0.8 + 0.2) * (0.96 + 0.08 * hard[:, None])
    vert = 1.0 - np.abs(N[:, 1])
    streak = sstep(0.55, 0.82, fbm(P, (30.0, 1.4, 30.0), sp.seed + 61, 3)) * sstep(0.2, 0.6, vert)
    streak *= 0.5 + 0.5 * sstep(0.5, 0.0, f)
    col = col * (1.0 - 0.35 * streak[:, None]) + KARST * 0.35 * streak[:, None]
    col *= (1.0 + 0.14 * (fbm(P, 3.0, sp.seed + 71, 3) - 0.5))[:, None]
    # tide: wet dark band with a ragged top, biofilm lowest, salt crust in a thin line above
    edge = TIDE * (0.75 + 0.5 * fbm(P, (14.0, 1.0, 14.0), sp.seed + 81, 3))
    wet = sstep(edge + 0.012, edge - 0.012, P[:, 1])
    film = sstep(edge * 0.55, edge * 0.2, P[:, 1])
    salt = sstep(edge - 0.004, edge + 0.006, P[:, 1]) * sstep(edge + 0.05, edge + 0.015, P[:, 1]) * vert
    salt *= sstep(0.4, 0.7, fbm(P, 22.0, sp.seed + 83, 2))
    col = col * (1 - 0.65 * wet[:, None]) + WET * 0.65 * wet[:, None]
    col = col * (1 - 0.6 * film[:, None]) + FILM * 0.6 * film[:, None]
    col = col * (1 - 0.5 * salt[:, None]) + SALT * 0.5 * salt[:, None]
    # light dust and dry grass seeds on tops, lichen-grey crowns
    up = sstep(0.45, 0.9, N[:, 1])
    dust = np.clip(up * (0.03 + 0.25 * (1.0 - AOs)), 0, 0.35) * (0.6 + 0.4 * fbm(P, 18.0, sp.seed + 73, 2))
    col = col * (1 - dust[:, None]) + sand * dust[:, None]
    col *= (1.0 - 0.12 * up * sstep(0.3, 0.6, P[:, 1]))[:, None]
    col *= (0.45 + 0.55 * AOs ** 1.3)[:, None] * (0.74 + 0.26 * AOl)[:, None]
    col = np.clip(col, 0.02, 0.93)
    rough = np.clip(0.9 + 0.06 * (fbm(P, 9.0, sp.seed + 77, 2) - 0.5) + 0.04 * dust - 0.2 * wet * (1 - film * 0.3),
                    0.62, 1.0)   # wet stone is a little smoother; never glossy
    nx = rs._sample(nh, P[:, 2] / rs.TEX_TILE, -yw / rs.TEX_TILE)[:, :2] * 2 - 1
    ny = rs._sample(nh, P[:, 0] / rs.TEX_TILE + 0.37, P[:, 2] / rs.TEX_TILE + 0.21)[:, :2] * 2 - 1
    nz = rs._sample(nh, P[:, 0] / rs.TEX_TILE + 0.53, -yw / rs.TEX_TILE)[:, :2] * 2 - 1
    g = np.zeros_like(N)
    g[:, 2] += nx[:, 0] * w[:, 0]
    g[:, 1] += nx[:, 1] * w[:, 0]
    g[:, 0] += ny[:, 0] * w[:, 1]
    g[:, 2] -= ny[:, 1] * w[:, 1]
    g[:, 0] += nz[:, 0] * w[:, 2]
    g[:, 1] += nz[:, 1] * w[:, 2]
    g -= N * (g * N).sum(1, keepdims=True)
    nn = N + 0.9 * g
    nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-8
    return col, rough, nn


def main() -> int:
    rs.SPIRES.clear()
    rs.SPIRES.update(SHORE)
    rs.layers = limestone_layers
    rs.TRIS = 5000   # the old cliff had 5k, the rock 4k
    if not any(a.startswith("--out") for a in sys.argv[1:]):
        sys.argv.append("--out=" + str(rs.GAME / "models" / "biome2"))
    return rs.main()


if __name__ == "__main__":
    sys.exit(main())
