"""Procedural rock spires of the Highlands: eroded sandstone hoodoos and pinnacles (weak-models list, items 4 and 6;
Kanta 28.10.2026 approved replacing the Highland weak models). Replaces the Meshy spire b03 (a column of stacked
"pancakes" under a low-poly egg) and the scan b14 (a stepped cairn) with three spires that read as natural rock
from the combat camera: irregular vertical fluting, a hard caprock overhanging a narrowed neck, undercut bases,
wavy broken strata (hard beds stick out as broken ledges, soft beds and bedding planes are recessed), erosion
alcoves, and talus scree with fallen blocks at the foot. No real landmark: generic arid badland forms.

How:
1. The rock is a signed distance field on a voxel grid (numpy): columns are radial profiles around a leaning
   axis, displaced by shared world-space strata (a warped height, so beds are wavy and run through every column
   of a cluster at the same level), ridged vertical noise (fluting) and fbm bumps; alcoves are subtracted
   ellipsoids (boolean erosion); the scree apron is a noisy cone smoothly joined to the base, and the fallen
   blocks are rounded noisy boxes on it. Detail is evaluated only in a narrow band around the coarse surface.
2. Surface nets turn the field into a high-poly mesh (~200k triangles); pymeshlab's quadric collapse makes the
   game mesh (TRIS), whose unseen underside is dropped; Blender unwraps it into one tightly packed 1024 atlas.
3. Cycles bakes, per texel of the low mesh: position and normal, the high mesh's object-space normal and two
   ambient-occlusion reaches (cavities and broad shading) from the high mesh.
4. numpy layers turn that into the textures. Albedo: the terrain's own cliff photo (Cliff Side, CC0, the
   ground3d.gdshader rock, game/art/LICENSES.md) projected triplanar with its v along the same warped strata
   height, so the photo's layers follow the sculpted beds; graded towards the photo-scanned rocks b12/b13 (their
   mean and spread) with per-bed tints, dark desert-varnish streaks under ledges, sand dust on upward faces and
   in the scree, damp dirt at the foot and baked AO (the battle renderer has no AO of its own on low presets).
   Roughness 0.85-1.0 (matte, a bit lower on varnish), metal 0. Normal: the high mesh's normals tilted by the
   cliff photo's own normal map (triplanar), turned into a tangent-space map by one more Cycles bake.
5. Stand on y = 0 by the lowest point, centred, largest X/Z size = 1 (BiomeProps scales to pixels), GLB with
   JPEG textures; one mesh, one material.

Run (repo root; bpy 5.2 pip module, numpy, Pillow, pymeshlab; no network; ~2-4 min per spire on 4 cores):
  python3 game/tools/blender/rock_spires.py [--out=game/models/biome] [--only=b15_rock_spire_c] [--size=1024]
  python3 game/tools/blender/rock_spires.py --preview=/abs/dir   (shape only, no Blender: shaded point renders)
  -> <out>/<name>.glb; Godot's import extracts <name>_<name>_{albedo,orm,normal}.jpg next to it.
"""
from __future__ import annotations

import argparse
import math
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

GAME = Path(__file__).resolve().parents[2]
PBR = GAME / "art" / "ground" / "pbr"
SCANS = [GAME / "models" / "biome" / "b12_rock_outcrop_b_0.jpg", GAME / "models" / "biome" / "b13_boulders_b_0.jpg"]
TRIS = 4500          # game mesh budget per spire (the old ones had 3000; spires are few per chunk)
VOXEL = 1.0 / 150.0  # grid step in model units (the footprint is about 1 across before normalisation)
BAND = 0.13          # narrow band around the coarse surface where the detail is evaluated
TEX_TILE = 1.1       # model units per repeat of the cliff photo (about 6-7 photo beds per spire height)


# ---------------- noise (model units) ----------------
def _hash(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float32) / 65535.0


def vnoise(p: np.ndarray, f, seed: int) -> np.ndarray:
    """Value noise 0..1 at points p (n, 3); f is a scalar or a per-axis (3,) lattice frequency"""
    q = p * np.asarray(f, np.float32)
    i = np.floor(q).astype(np.int64)
    t = (q - i).astype(np.float32)
    u = t * t * (3 - 2 * t)
    out = np.zeros(len(p), np.float32)
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = wx * (u[:, 1] if dy else 1 - u[:, 1])
            for dz in (0, 1):
                w = wy * (u[:, 2] if dz else 1 - u[:, 2])
                out += w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p: np.ndarray, f, seed: int, octaves: int = 4) -> np.ndarray:
    """Fractal sum of vnoise, 0..1"""
    a, s, n = 1.0, 0.0, 0.0
    f = np.asarray(f, np.float32)
    for o in range(octaves):
        s = s + a * vnoise(p, f * 2 ** o, seed + o * 17)
        n += a
        a *= 0.5
    return s / n


def ridged(p: np.ndarray, f, seed: int, octaves: int = 3) -> np.ndarray:
    """Ridged noise 0..1: sharp crests where the value noise crosses its middle (gullies and ribs)"""
    a, s, n = 1.0, 0.0, 0.0
    f = np.asarray(f, np.float32)
    for o in range(octaves):
        s = s + a * (1.0 - np.abs(2.0 * vnoise(p, f * 2 ** o, seed + 31 * o) - 1.0))
        n += a
        a *= 0.5
    return s / n


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def smin(a, b, k):
    """Polynomial smooth minimum: a union with a fillet of about k"""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


# ---------------- the shapes ----------------
@dataclass
class Column:
    """One rock column: plan position, height, radius and its profile (fraction of height, radius factor)"""
    x: float
    z: float
    h: float
    r: float
    prof: list
    lean: tuple = (0.0, 0.0)   # axis offset at the top (model units), grows as t^1.6
    ell: float = 0.1           # cross-section ellipticity
    ell_a: float = 0.0
    ledge: float = 0.03        # strata relief (radius change between a soft and a hard bed)
    flute: float = 0.035       # depth of the vertical gullies
    bump: float = 0.03         # irregular bulges
    cap_top: float = 0.045     # roughness of the top
    alcoves: int = 5           # erosion hollows cut into the face


@dataclass
class Spire:
    """A spire model: its columns, strata, scree apron and fallen blocks"""
    seed: int
    cols: list
    bed: float = 0.12          # mean bed thickness
    tilt: tuple = (0.04, -0.02)   # dip of the beds (dy per unit x, z)
    warp: float = 0.07         # waviness of the beds
    apron_h: float = 0.14      # scree cone height at the base
    apron_r: float = 0.5       # scree reach from the centre of the cluster
    blocks: int = 34           # fallen blocks and scree stones
    big_blocks: int = 3        # fallen cap pieces
    fillet: float = 0.07       # how softly the scree meets the rock
    extra: dict = field(default_factory=dict)


# profiles: (t = y / h, radius factor); below 0 the first radius holds (the base continues under the scree)
HOODOO = [(0.0, 1.0), (0.06, 0.86), (0.12, 0.9), (0.3, 0.84), (0.5, 0.74), (0.66, 0.6), (0.76, 0.5), (0.8, 0.52),
          (0.83, 0.76), (0.9, 0.8), (0.96, 0.74), (1.0, 0.56)]
PINNACLE = [(0.0, 1.0), (0.08, 0.84), (0.2, 0.86), (0.4, 0.7), (0.6, 0.55), (0.78, 0.42), (0.9, 0.3), (0.97, 0.18),
            (1.0, 0.05)]
PINNACLE_CAP = [(0.0, 1.0), (0.07, 0.82), (0.25, 0.8), (0.5, 0.66), (0.68, 0.5), (0.76, 0.42), (0.8, 0.64),
                (0.92, 0.66), (1.0, 0.4)]
TOWER = [(0.0, 1.0), (0.05, 0.84), (0.1, 0.9), (0.35, 0.88), (0.55, 0.82), (0.7, 0.74), (0.78, 0.7), (0.82, 0.86),
         (0.94, 0.88), (1.0, 0.7)]

# The scree stays close to the rock: the game scales a model by its widest plan size (BiomeProps KINDS width), so a
# wide apron (sand-coloured, hardly seen from above) would only shrink the column on screen.
SPIRES = {
    # a lone hoodoo: hard caprock over a waisted neck, strong ledges, scree with a fallen cap piece
    "b15_rock_spire_c": Spire(seed=11, cols=[
        Column(0.0, 0.0, 1.9, 0.3, HOODOO, lean=(0.06, -0.03), ell=0.14, ell_a=0.6, alcoves=6)],
        apron_h=0.18, apron_r=0.31, blocks=30, big_blocks=2),
    # a cluster of three pinnacles of different height sharing the beds, fluted deep
    "b15_rock_spire_d": Spire(seed=23, cols=[
        Column(-0.05, 0.02, 1.75, 0.2, PINNACLE_CAP, lean=(-0.05, 0.02), ell=0.18, ell_a=0.2, flute=0.045),
        Column(0.15, -0.11, 1.25, 0.16, PINNACLE, lean=(0.05, -0.03), ell=0.15, ell_a=1.4, flute=0.04, alcoves=3),
        Column(0.13, 0.17, 0.85, 0.15, PINNACLE, lean=(0.03, 0.05), ell=0.2, ell_a=2.2, flute=0.04, alcoves=2)],
        bed=0.1, tilt=(-0.03, 0.05), apron_h=0.17, apron_r=0.33, blocks=32, big_blocks=2, fillet=0.09),
    # a broad, squat eroded tower (a butte remnant): elongated plan, heavy ledges, deep alcoves, big blocks
    "b15_rock_spire_e": Spire(seed=37, cols=[
        Column(0.0, 0.0, 1.15, 0.33, TOWER, lean=(0.03, 0.02), ell=0.3, ell_a=0.3, ledge=0.04, flute=0.04,
               bump=0.035, alcoves=8),
        Column(0.22, 0.12, 0.62, 0.16, PINNACLE, lean=(0.04, 0.02), ell=0.2, ell_a=1.0, alcoves=1)],
        bed=0.13, tilt=(0.05, 0.03), apron_h=0.15, apron_r=0.42, blocks=30, big_blocks=3),
}


def strata_y(P: np.ndarray, sp: Spire) -> np.ndarray:
    """Warped height whose integer steps of sp.bed are the bed boundaries (wavy, dipping, same for all columns)"""
    return (P[:, 1] + sp.tilt[0] * P[:, 0] + sp.tilt[1] * P[:, 2]
            + sp.warp * (fbm(P, (1.4, 0.5, 1.4), sp.seed + 3, 3) - 0.5) * 2.0)


def strata(P: np.ndarray, sp: Spire) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(bed id, position 0..1 inside the bed, hardness 0..1 of the bed) at points P. Bed thickness varies."""
    yw = strata_y(P, sp) / sp.bed
    u = yw + 0.85 * (vnoise(np.stack([yw * 0.37, np.zeros_like(yw), np.zeros_like(yw)], 1), 1.0, sp.seed + 5) - 0.5)
    k = np.floor(u)
    f = u - k
    hard = _hash(k.astype(np.int64), np.full(k.shape, 3, np.int64), np.zeros(k.shape, np.int64), sp.seed)
    return k, f, hard


def _profile(t: np.ndarray, prof: list) -> np.ndarray:
    pt = np.array([p[0] for p in prof], np.float32)
    pr = np.array([p[1] for p in prof], np.float32)
    return np.interp(t, pt, pr).astype(np.float32)


def column_coarse(P: np.ndarray, c: Column) -> np.ndarray:
    """Distance-like field of the column's plain profile (no noise); negative inside"""
    t = P[:, 1] / c.h
    tt = np.clip(t, 0.0, 1.0) ** 1.6
    dx = P[:, 0] - (c.x + c.lean[0] * tt)
    dz = P[:, 2] - (c.z + c.lean[1] * tt)
    rho = np.sqrt(dx * dx + dz * dz)
    th = np.arctan2(dz, dx)
    R = c.r * _profile(t, c.prof) * (1.0 + c.ell * np.cos(2.0 * (th - c.ell_a)))
    return np.maximum(rho - R, P[:, 1] - c.h)


def column_detail(P: np.ndarray, c: Column, sp: Spire, ci: int) -> np.ndarray:
    """The column's field with lobes, vertical gullies, a few broken hard ledges, recessed soft beds, bulges,
    a lumpy rounded top and alcoves"""
    s = sp.seed + 101 * ci
    t = P[:, 1] / c.h
    tt = np.clip(t, 0.0, 1.0) ** 1.6
    wob = (fbm(P[:, 1:2] * np.ones((1, 3), np.float32), (0.0, 2.5, 0.0), s + 1, 2) - 0.5) * 0.05
    dx = P[:, 0] - (c.x + c.lean[0] * tt + wob)
    dz = P[:, 2] - (c.z + c.lean[1] * tt - wob)
    rho = np.sqrt(dx * dx + dz * dz)
    th = np.arctan2(dz, dx)
    # angle/height coordinates: the plan's lobes and the gullies follow the column, not the world grid
    q = np.stack([np.cos(th), P[:, 1], np.sin(th)], 1).astype(np.float32)
    R = c.r * _profile(t, c.prof) * (1.0 + c.ell * np.cos(2.0 * (th - c.ell_a)))
    R = R * (1.0 + 0.24 * (fbm(q, (1.3, 0.9, 1.3), s + 3, 3) - 0.5) * 2.0)
    k, f, hard = strata(P, sp)
    # only the hard beds stand out, as rounded lips broken along their run; soft beds recede; some bedding
    # planes are notched, each over part of the circumference
    brk = sstep(0.4, 0.68, vnoise(q, (2.6, 3.0, 2.6), s + 7))
    lip = 1.0 - (2.0 * f - 1.0) ** 4
    ledge = sstep(0.6, 0.85, hard)
    R = R + c.ledge * (1.5 * ledge * lip * brk - 0.5 * (1.0 - hard))
    notch_on = _hash(k.astype(np.int64), np.full(k.shape, 5, np.int64), np.zeros(k.shape, np.int64), s) > 0.55
    notch = np.exp(-(f / 0.06) ** 2) * notch_on * sstep(0.35, 0.6, vnoise(q, (2.0, 1.0, 2.0), s + 9))
    R = R - c.ledge * 0.6 * notch
    # vertical fluting: ridged noise around the column, stretched down it; ~10-14 gullies, deeper in soft beds
    fl = ridged(q, (2.1, 0.35, 2.1), s + 11, 3)
    # (shallower where the column thins to a point, so a tip does not split into blades)
    thin = np.clip(_profile(t, c.prof) / 0.6, 0.25, 1.0) * (1.0 - 0.75 * sstep(0.8, 0.9, t))   # caprock: few gullies
    R = R - c.flute * 1.4 * sstep(0.45, 1.0, fl) * (1.1 - 0.35 * ledge) * thin
    R = R + c.bump * (fbm(P, 6.0, s + 13, 4) - 0.5) * 2.4
    top = c.h * 0.97 + c.cap_top * 2.0 * (fbm(P, (5.0, 0.0, 5.0), s + 17, 3) - 0.5) * 2.0
    # joints and solution pits on the top: what the combat camera mostly sees of a spire
    top = top - c.cap_top * 1.6 * sstep(0.55, 1.0, ridged(P, (7.0, 0.0, 7.0), s + 21, 2))
    d = -smin(-(rho - R), -(P[:, 1] - top), 0.04)   # rounded rim of the top
    # alcoves (boolean erosion): ellipsoids centred on the face, wider than tall, more in the lower half
    rng = np.random.default_rng(s + 19)
    for _ in range(c.alcoves):
        ty = rng.uniform(0.08, 0.7) ** 1.2
        ang = rng.uniform(0, 2 * math.pi)
        rr = c.r * float(_profile(np.array([ty], np.float32), c.prof)[0])
        tt0 = ty ** 1.6
        cen = np.array([c.x + c.lean[0] * tt0 + math.cos(ang) * rr * 1.02, ty * c.h,
                        c.z + c.lean[1] * tt0 + math.sin(ang) * rr * 1.02], np.float32)
        ax = np.array([rng.uniform(0.06, 0.11), rng.uniform(0.035, 0.07), rng.uniform(0.06, 0.11)], np.float32)
        q = (P - cen) / ax
        e = (np.sqrt((q * q).sum(1)) - 1.0) * ax.min()
        d = np.maximum(d, -e)
    return d


def apron(P: np.ndarray, sp: Spire) -> np.ndarray:
    """Scree cone around the base of the columns: a noisy height field (distance-like, negative under it)"""
    hf = np.zeros(len(P), np.float32)
    for c in sp.cols:
        rb = np.hypot(P[:, 0] - c.x, P[:, 2] - c.z)
        reach = sp.apron_r * (0.55 + 0.45 * min(1.0, c.h / 1.5))
        k = np.clip(1.0 - (rb - c.r * 0.6) / max(reach - c.r * 0.6, 1e-3), 0.0, 1.0)
        hf = np.maximum(hf, sp.apron_h * min(1.0, c.h / 1.4) * k ** 1.7)
    lumpy = (fbm(P, (14.0, 0.0, 14.0), sp.seed + 41, 4) - 0.5) * 0.05
    hf = hf + lumpy * sstep(0.0, 0.05, hf)
    # the cone's rim sinks just under the ground plane, so it thins out to nothing instead of a sheet at y = 0
    return (P[:, 1] - (hf - 0.006)) * 0.7


def apron_height(x: float, z: float, sp: Spire) -> float:
    """Scree height at a plan point without the lumps (where to bed a fallen block)"""
    h = 0.0
    for c in sp.cols:
        rb = math.hypot(x - c.x, z - c.z)
        reach = sp.apron_r * (0.55 + 0.45 * min(1.0, c.h / 1.5))
        k = min(max(1.0 - (rb - c.r * 0.6) / max(reach - c.r * 0.6, 1e-3), 0.0), 1.0)
        h = max(h, sp.apron_h * min(1.0, c.h / 1.4) * k ** 1.7)
    return h


def block_list(sp: Spire) -> list:
    """Fallen blocks: (centre, half sizes, rotation matrix, rounding) on the scree, denser near the rock"""
    rng = np.random.default_rng(sp.seed + 53)
    out = []
    main = max(sp.cols, key=lambda c: c.h)
    for i in range(sp.blocks + sp.big_blocks):
        big = i < sp.big_blocks
        c = sp.cols[rng.integers(len(sp.cols))] if not big else main
        ang = rng.uniform(0, 2 * math.pi)
        rad = c.r * 0.85 + (sp.apron_r - c.r * 0.6) * (rng.uniform(0.1, 1.0) ** (1.6 if not big else 1.0))
        x, z = c.x + math.cos(ang) * rad, c.z + math.sin(ang) * rad
        if math.hypot(x, z) > sp.apron_r + 0.06:
            continue
        s = rng.uniform(0.06, 0.1) if big else rng.uniform(0.015, 0.045)
        half = np.array([s * rng.uniform(0.8, 1.4), s * rng.uniform(0.4, 0.75), s * rng.uniform(0.6, 1.1)], np.float32)
        a, b, g = rng.uniform(-0.6, 0.6), rng.uniform(0, 2 * math.pi), rng.uniform(-0.6, 0.6)
        ca, sa, cb, sb, cg, sg = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(g), math.sin(g)
        rx = np.array([[1, 0, 0], [0, ca, -sa], [0, sa, ca]], np.float32)
        ry = np.array([[cb, 0, sb], [0, 1, 0], [-sb, 0, cb]], np.float32)
        rz = np.array([[cg, -sg, 0], [sg, cg, 0], [0, 0, 1]], np.float32)
        y = apron_height(x, z, sp) + half[1] * 0.2
        out.append((np.array([x, y, z], np.float32), half, rx @ ry @ rz, s * 0.3))
    return out


def block_sdf(P: np.ndarray, blk, seed: int) -> np.ndarray:
    """A broken stone: a rounded box cut by two random planes (fresh fracture faces), with a noisy surface"""
    cen, half, rot, rnd = blk
    lp = (P - cen) @ rot
    q = np.abs(lp) - (half - rnd)
    d = np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(1), 0.0) - rnd
    rng = np.random.default_rng(seed)
    for _ in range(2):
        n = rng.normal(size=3)
        n /= np.linalg.norm(n)
        d = np.maximum(d, lp @ n.astype(np.float32) - float(half.min()) * rng.uniform(0.35, 0.8))
    return d + (fbm(P, 16.0, seed, 3) - 0.5) * 0.7 * float(half.min())


# ---------------- field -> mesh ----------------
def build_field(sp: Spire, h: float = VOXEL):
    """The spire's field on a grid: (F (nx, ny, nz) negative inside, origin, step)"""
    top = max(c.h for c in sp.cols) + 0.08
    lo = np.array([-0.6, -h * 2, -0.6], np.float32)
    hi = np.array([0.6, top, 0.6], np.float32)
    n = np.ceil((hi - lo) / h).astype(int) + 1
    xs, ys, zs = (lo[i] + h * np.arange(n[i], dtype=np.float32) for i in range(3))
    F = np.empty(n, np.float32)
    blocks = block_list(sp)
    for j0 in range(0, n[1], 24):   # in slabs of y, so the point arrays stay small
        ysl = ys[j0:j0 + 24]
        X, Y, Z = np.meshgrid(xs, ysl, zs, indexing="ij")
        P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
        coarse = np.full(len(P), 1e3, np.float32)
        for c in sp.cols:
            coarse = np.minimum(coarse, column_coarse(P, c))
        d = coarse.copy()
        band = np.nonzero(np.abs(coarse) < BAND)[0]
        if len(band):
            Pb = P[band]
            db = np.full(len(band), 1e3, np.float32)
            for ci, c in enumerate(sp.cols):
                near = np.abs(column_coarse(Pb, c)) < BAND
                dc = np.full(len(band), 1e3, np.float32)
                dc[near] = column_detail(Pb[near], c, sp, ci)
                db = smin(db, dc, 0.03) if ci else dc
            d[band] = db
        ap_band = np.nonzero(P[:, 1] < sp.apron_h + 0.08)[0]
        if len(ap_band):
            d[ap_band] = smin(d[ap_band], apron(P[ap_band], sp), sp.fillet)
        for bi, blk in enumerate(blocks):
            m = np.nonzero(np.linalg.norm(P - blk[0], axis=1) < float(blk[1].max()) * 1.9 + 0.02)[0]
            if len(m):
                d[m] = np.minimum(d[m], block_sdf(P[m], blk, sp.seed + 200 + bi))
        d = np.maximum(d, -P[:, 1])   # flat underside at the ground plane (hidden in the ground)
        F[:, j0:j0 + 24, :] = d.reshape(len(xs), len(ysl), len(zs))
    return F, lo, h


_CORNERS = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]])
_EDGES = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]


def surface_nets(F: np.ndarray, lo: np.ndarray, h: float) -> tuple[np.ndarray, np.ndarray]:
    """Naive surface nets: one vertex per cell the surface crosses (mean of its edge crossings), one quad per grid
    edge with a sign change. Returns (vertices (n, 3), triangles (m, 3)) with outward winding."""
    ins = F < 0
    nx, ny, nz = F.shape
    act = np.zeros((nx - 1, ny - 1, nz - 1), bool)
    allin = np.ones_like(act)
    for c in _CORNERS:
        s = ins[c[0]:nx - 1 + c[0], c[1]:ny - 1 + c[1], c[2]:nz - 1 + c[2]]
        act |= s
        allin &= s
    act &= ~allin
    ci = np.argwhere(act)
    idx = np.full(act.shape, -1, np.int64)
    idx[tuple(ci.T)] = np.arange(len(ci))
    fv = np.stack([F[ci[:, 0] + c[0], ci[:, 1] + c[1], ci[:, 2] + c[2]] for c in _CORNERS], 1)
    acc = np.zeros((len(ci), 3), np.float32)
    cnt = np.zeros(len(ci), np.float32)
    for a, b in _EDGES:
        fa, fb = fv[:, a], fv[:, b]
        x = (fa < 0) != (fb < 0)
        t = np.where(x, fa / np.where(x, fa - fb, 1.0), 0.0)
        p = _CORNERS[a] + t[:, None] * (_CORNERS[b] - _CORNERS[a])
        acc[x] += p[x]
        cnt += x
    verts = (ci + acc / np.maximum(cnt, 1)[:, None]) * h + lo
    quads = []
    for ax in range(3):
        o1, o2 = [(1, 2), (0, 2), (0, 1)][ax]
        e = np.zeros(3, int)
        e[ax] = 1
        a = ins[:nx - e[0], :ny - e[1], :nz - e[2]]
        b = ins[e[0]:, e[1]:, e[2]:]
        crs = np.argwhere(a != b)
        ok = (crs[:, o1] >= 1) & (crs[:, o2] >= 1) & (crs[:, o1] < act.shape[o1]) & (crs[:, o2] < act.shape[o2])
        ok &= crs[:, ax] < act.shape[ax]
        crs = crs[ok]
        flip = a[tuple(crs.T)]   # inside -> outside along +axis
        d1 = np.zeros(3, int)
        d1[o1] = 1
        d2 = np.zeros(3, int)
        d2[o2] = 1
        c00, c10, c11, c01 = crs - d1 - d2, crs - d2, crs, crs - d1
        q = np.stack([idx[tuple(c.T)] for c in (c00, c10, c11, c01)], 1)
        # c00 c10 c11 c01 turn counter-clockwise in the (o1, o2) plane, so the quad faces o1 x o2: +ax for the x
        # and z edges, -ax for the y edges; the outside is +ax where the edge leaves the rock (flip)
        q = np.where((flip == (ax != 1))[:, None], q, q[:, ::-1])
        quads.append(q[(q >= 0).all(1)])
    q = np.concatenate(quads)
    tris = np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])
    return verts.astype(np.float32), tris


def normalise(v: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    """Translation and scale that put the model on y = 0, centred in plan, largest X/Z size 1"""
    lo, hi = v.min(0), v.max(0)
    off = np.array([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2], np.float32)
    k = 1.0 / max(hi[0] - lo[0], hi[2] - lo[2])
    return (v + off) * k, off, k


# ---------------- preview without Blender ----------------
def preview(v: np.ndarray, t: np.ndarray, path: str, size: int = 900) -> None:
    """Shaded point render (3/4 view and from above) of a mesh, for shape iteration without Blender"""
    fn = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    vn = np.zeros_like(v)
    for k in range(3):
        np.add.at(vn, t[:, k], fn)
    vn /= np.linalg.norm(vn, axis=1, keepdims=True) + 1e-9
    sun = np.array([0.5, 0.75, 0.35], np.float32)
    sun /= np.linalg.norm(sun)
    shade = 0.25 + 0.75 * np.clip(vn @ sun, 0, 1)
    pts = np.concatenate([v, (v[t[:, 0]] + v[t[:, 1]] + v[t[:, 2]]) / 3])
    sh = np.concatenate([shade, shade[t[:, 0]]])
    panels = []
    for yaw, pitch in ((35.0, 25.0), (20.0, 62.0), (0.0, 89.0)):
        ya, pa = math.radians(yaw), math.radians(pitch)
        ry = np.array([[math.cos(ya), 0, -math.sin(ya)], [0, 1, 0], [math.sin(ya), 0, math.cos(ya)]], np.float32)
        rx = np.array([[1, 0, 0], [0, math.cos(pa), -math.sin(pa)], [0, math.sin(pa), math.cos(pa)]], np.float32)
        p = pts @ ry.T @ rx.T
        img = np.full((size, size), 0.85, np.float32)
        zb = np.full((size, size), -1e9, np.float32)
        span = max(np.ptp(p[:, 0]), np.ptp(p[:, 1])) * 1.1
        cx, cy = p[:, 0].mean(), (p[:, 1].min() + p[:, 1].max()) / 2
        ix = ((p[:, 0] - cx) / span * size + size / 2).astype(int)
        iy = (size / 2 - (p[:, 1] - cy) / span * size).astype(int)
        order = np.argsort(p[:, 2])
        for dx in (0, 1):
            for dy in (0, 1):
                xx, yy = np.clip(ix[order] + dx, 0, size - 1), np.clip(iy[order] + dy, 0, size - 1)
                img[yy, xx] = sh[order]
                zb[yy, xx] = p[order, 2]
        panels.append(img)
    Image.fromarray((np.concatenate(panels, 1) * 255).astype(np.uint8)).save(path)


def make_mesh(name: str) -> tuple[np.ndarray, np.ndarray]:
    """High-poly mesh of the spire `name`, normalised (y = 0 at its lowest point, largest plan size 1)"""
    F, lo, h = build_field(SPIRES[name])
    v, t = surface_nets(F, lo, h)
    v, _, _ = normalise(v)
    return v, t


def decimate(v: np.ndarray, t: np.ndarray, tris: int) -> tuple[np.ndarray, np.ndarray]:
    """Quadric edge collapse (pymeshlab) to about `tris` triangles, keeping well-shaped triangles: Blender's
    collapse decimator turns the pinnacle cluster's noisy surface into long slivers, which no unwrap can pack"""
    import pymeshlab

    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=v.astype(np.float64), face_matrix=t.astype(np.int32)))
    ms.meshing_merge_close_vertices()
    ms.meshing_decimation_quadric_edge_collapse(targetfacenum=tris, qualitythr=0.6, preservenormal=True,
                                                preservetopology=False, optimalplacement=True, planarquadric=True)
    ms.meshing_remove_unreferenced_vertices()
    m = ms.current_mesh()
    return m.vertex_matrix().astype(np.float32), m.face_matrix().astype(np.int64)


# ---------------- Blender: decimate, unwrap, bake, export ----------------
def _blender_mesh(bpy, name: str, v: np.ndarray, t: np.ndarray):
    me = bpy.data.meshes.new(name)
    vv = v[:, [0, 2, 1]] * np.array([1, -1, 1], np.float32)   # model y-up -> Blender z-up (glTF export turns it back)
    me.vertices.add(len(vv))
    me.vertices.foreach_set("co", vv.ravel())
    me.loops.add(t.size)
    me.loops.foreach_set("vertex_index", t.ravel().astype(np.int32))
    me.polygons.add(len(t))
    me.polygons.foreach_set("loop_start", np.arange(0, t.size, 3, dtype=np.int32))
    me.update()
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _tex(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), np.float32) / 255.0


def _sample(img: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Bilinear, repeating sample of img (h, w, c) at texture coordinates u, v (v down the image)"""
    h, w = img.shape[:2]
    x = (u % 1.0) * w - 0.5
    y = (v % 1.0) * h - 0.5
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    x0 %= w
    y0 %= h
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    return ((img[y0, x0] * (1 - fx) + img[y0, x1] * fx) * (1 - fy)
            + (img[y1, x0] * (1 - fx) + img[y1, x1] * fx) * fy)


def _triplanar(img: np.ndarray, P: np.ndarray, N: np.ndarray, yw: np.ndarray, tile: float):
    """Triplanar sample (model y-up coordinates): the side projections run v along the warped strata height yw, so
    the photo's beds follow the sculpted ones. Returns (colour, per-axis weights)."""
    w = np.abs(N) ** 4
    w /= w.sum(1, keepdims=True)
    cx = _sample(img, P[:, 2] / tile, -yw / tile)
    cy = _sample(img, P[:, 0] / tile + 0.37, P[:, 2] / tile + 0.21)
    cz = _sample(img, P[:, 0] / tile + 0.53, -yw / tile)
    return cx * w[:, :1] + cy * w[:, 1:2] + cz * w[:, 2:3], w


def layers(P, N, AOs, AOl, sp: Spire, rock, nh, scan_mean, scan_std, sand):
    """Albedo (sRGB), roughness and the detail-tilted object normal at texels with model-space position P and
    high-poly normal N (both y-up), AO with a short and a long reach"""
    k, f, hard = strata(P, sp)
    yw = strata_y(P, sp)
    col, w = _triplanar(rock, P, N, yw, TEX_TILE)
    # the terrain shader softens the photo's dark cracks (they read as soot); the same here, then grade towards the
    # scans' mean and spread so the spires sit with the outcrops and boulders
    lum = col @ np.array([0.299, 0.587, 0.114], np.float32)
    col = col + (0.42 - lum[:, None]) * 0.3
    m, s = col.mean(0), col.std(0) + 1e-4
    target_mean = scan_mean * 0.55 + np.array([0.5, 0.37, 0.26], np.float32) * 0.45   # a touch warmer: sandstone
    col = (col - m) / s * np.minimum(scan_std * 1.1, s) + target_mean
    lum = col @ np.array([0.299, 0.587, 0.114], np.float32)
    col = col * 0.8 + lum[:, None] * 0.2
    # bed tints: pale buff, rusty, grey-brown, by bed id (hard beds a little paler)
    tints = np.array([[1.08, 1.04, 0.98], [1.04, 0.9, 0.8], [0.92, 0.9, 0.88], [1.0, 0.95, 0.9], [1.1, 0.98, 0.86]],
                     np.float32)
    ti = (_hash(k.astype(np.int64), np.full(k.shape, 9, np.int64), np.zeros(k.shape, np.int64), sp.seed) * 4.999)
    tint = tints[ti.astype(int)]
    col = col * (tint * 0.7 + 0.3) * (0.97 + 0.08 * hard[:, None])
    # desert varnish: dark streaks hanging down vertical faces, starting under ledges
    vert = 1.0 - np.abs(N[:, 1])
    streak = sstep(0.55, 0.8, fbm(P, (26.0, 1.6, 26.0), sp.seed + 61, 3)) * sstep(0.2, 0.6, vert)
    streak *= 0.55 + 0.45 * sstep(0.5, 0.0, f)   # strongest just under a bed's top
    col = col * (1.0 - 0.38 * streak[:, None]) + np.array([0.08, 0.05, 0.035], np.float32) * 0.38 * streak[:, None]
    # mottling at two scales (the photo repeats; this breaks it)
    mot = fbm(P, 3.0, sp.seed + 71, 3) - 0.5
    col *= (1.0 + 0.16 * mot)[:, None]
    # sand dust on upward faces and in the scree, thicker in the crevices of up-facing surfaces
    up = sstep(0.45, 0.9, N[:, 1])
    low = sstep(0.2, 0.02, P[:, 1])
    dust = np.clip(up * (0.04 + 0.4 * (1.0 - AOs)) + low * 0.3, 0, 0.6)
    # weathered, darker tops (lichen and varnish): the top must stand out against the sand seen from above
    col *= (1.0 - 0.22 * up * sstep(0.3, 0.6, P[:, 1]))[:, None]
    dust *= 0.7 + 0.3 * fbm(P, 18.0, sp.seed + 73, 2)
    col = col * (1 - dust[:, None]) + sand * dust[:, None]
    # damp dirt at the foot and cavity grime from the baked AO
    foot = sstep(0.05, 0.0, P[:, 1])
    col *= (1.0 - 0.18 * foot)[:, None]
    col *= (0.42 + 0.58 * AOs ** 1.3)[:, None] * (0.72 + 0.28 * AOl)[:, None]
    col = np.clip(col, 0.02, 0.95)
    rough = np.clip(0.9 + 0.06 * (fbm(P, 9.0, sp.seed + 77, 2) - 0.5) + 0.05 * dust - 0.07 * streak, 0.82, 1.0)
    # detail normal: the photo's own normal map (OpenGL, R/G) as slopes in each projection plane
    nx = _sample(nh, P[:, 2] / TEX_TILE, -yw / TEX_TILE)[:, :2] * 2 - 1
    ny = _sample(nh, P[:, 0] / TEX_TILE + 0.37, P[:, 2] / TEX_TILE + 0.21)[:, :2] * 2 - 1
    nz = _sample(nh, P[:, 0] / TEX_TILE + 0.53, -yw / TEX_TILE)[:, :2] * 2 - 1
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


def bake_and_export(name: str, v: np.ndarray, t: np.ndarray, out: str, size: int, tmp: str) -> tuple[int, float]:
    """Decimate, unwrap, bake and export one spire. Returns (game triangles, height of the normalised model)."""
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sp = SPIRES[name]
    hi = _blender_mesh(bpy, name + "_hi", v, t)
    lv, lt = decimate(v, t, TRIS)
    lo = _blender_mesh(bpy, name, lv, lt)
    # the flat underside on the ground plane is never seen: drop it (fewer triangles, no texture space)
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(lo.data)
    bm.faces.ensure_lookup_table()
    under = [f for f in bm.faces if f.normal.z < -0.95 and f.calc_center_median().z < 0.004]
    bmesh.ops.delete(bm, geom=under, context="FACES")
    # the scree is a ring round the rock: as one UV island its box would take most of the atlas, so it is cut
    # into quarters (edges crossing the x = 0 and y = 0 planes near the ground are split)
    cut = [e for e in bm.edges if max(v.co.z for v in e.verts) < 0.35
           and any((e.verts[0].co[k] < 0) != (e.verts[1].co[k] < 0) for k in (0, 1))]
    bmesh.ops.split_edges(bm, edges=cut)
    bm.to_mesh(lo.data)
    bm.free()
    for p in lo.data.polygons:
        p.use_smooth = True
    for p in hi.data.polygons:
        p.use_smooth = True
    ntri = len(lo.data.polygons)
    # unwrap
    bpy.ops.object.select_all(action="DESELECT")
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    lo.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(88), island_margin=0.003, area_weight=0.0, scale_to_bounds=True)
    # smart project packs a noisy rock loosely (a fifth of the atlas on the pinnacle cluster): repack tightly
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 0
    world = bpy.data.worlds.new("w")
    sc.world = world

    def img(nm, data=True):
        im = bpy.data.images.new(nm, size, size, alpha=True, float_buffer=data)
        im.colorspace_settings.name = "Non-Color"
        return im

    def pixels(im):
        a = np.empty(size * size * 4, np.float32)
        im.pixels.foreach_get(a)
        return a.reshape(size, size, 4)

    def mat_for(ob, build, im):
        m = bpy.data.materials.new("bake_" + ob.name)
        m.use_nodes = True
        N, L = m.node_tree.nodes, m.node_tree.links
        N.clear()
        o = N.new("ShaderNodeOutputMaterial")
        sock = build(N, L)
        if sock is not None:
            em = N.new("ShaderNodeEmission")
            L.new(sock, em.inputs["Color"])
            L.new(em.outputs[0], o.inputs[0])
        else:
            bs = N.new("ShaderNodeBsdfDiffuse")
            L.new(bs.outputs[0], o.inputs[0])
        tx = N.new("ShaderNodeTexImage")
        tx.image = im
        N.active = tx
        ob.data.materials.clear()
        ob.data.materials.append(m)

    def enc(N, L, sock):
        vm = N.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY_ADD"
        L.new(sock, vm.inputs[0])
        vm.inputs[1].default_value = (0.5, 0.5, 0.5)
        vm.inputs[2].default_value = (0.5, 0.5, 0.5)
        return vm.outputs[0]

    def emit_bake(build, from_hi=False):
        im = img("data")
        mat_for(lo, build, im)
        mat_for(hi, build, im)
        bpy.ops.object.select_all(action="DESELECT")
        if from_hi:
            hi.select_set(True)
        lo.select_set(True)
        bpy.context.view_layer.objects.active = lo
        bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True, use_selected_to_active=from_hi,
                            cage_extrusion=0.04, max_ray_distance=0.15)
        a = pixels(im)
        bpy.data.images.remove(im)
        return a

    def b_pos(N, L):
        g = N.new("ShaderNodeNewGeometry")
        vm = N.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY_ADD"
        L.new(g.outputs["Position"], vm.inputs[0])
        vm.inputs[1].default_value = (0.25, 0.25, 0.25)
        vm.inputs[2].default_value = (0.5, 0.5, 0.1)
        return vm.outputs[0]

    def b_nrm(N, L):
        return enc(N, L, N.new("ShaderNodeNewGeometry").outputs["Normal"])

    def b_ao(dist):
        def b(N, L):
            a = N.new("ShaderNodeAmbientOcclusion")
            a.samples = 24
            a.inputs["Distance"].default_value = dist
            c = N.new("ShaderNodeCombineColor")
            L.new(a.outputs["AO"], c.inputs[0])
            c.inputs[1].default_value = 1.0   # G marks covered texels
            return c.outputs[0]
        return b

    sc.cycles.samples = 1
    pos = emit_bake(b_pos)
    nrm = emit_bake(b_nrm, from_hi=True)
    sc.cycles.samples = 24
    aos = emit_bake(b_ao(0.05), from_hi=True)
    aol = emit_bake(b_ao(0.3), from_hi=True)
    nrm_lo = emit_bake(b_nrm)
    # every texel of the low mesh has a position; where a ray from it missed the high mesh (a rare spot where
    # the decimated surface strays), its own normal and an open AO stand in
    mask = pos[..., 1] > 0.1
    miss = mask & (aos[..., 1] < 0.5)
    nrm[miss] = nrm_lo[miss]
    aos[miss, 0] = 1.0
    aol[miss, 0] = 1.0
    print("%s: %d of %d texels missed the high mesh" % (name, int(miss.sum()), int(mask.sum())))
    sel = np.nonzero(mask)
    pb = (pos[sel][:, :3] - np.array([0.5, 0.5, 0.1])) / 0.25   # Blender z-up
    P = pb[:, [0, 2, 1]] * np.array([1, 1, -1])                  # -> model y-up
    nb = nrm[sel][:, :3] * 2 - 1
    N = nb[:, [0, 2, 1]] * np.array([1, 1, -1])
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-8
    P = P.astype(np.float32)
    N = N.astype(np.float32)
    # back to the field's units (the layers' noise and strata were defined before normalisation)
    v0 = make_mesh_raw_bounds(name)
    Pm = P / v0[1] - v0[0]
    rock = _tex(PBR / "rock_albedo.jpg")
    nh = _tex(PBR / "rock_nh.jpg")
    sand = _tex(PBR / "sand_albedo.jpg").reshape(-1, 3).mean(0) * np.array([1.02, 1.0, 0.97], np.float32)
    scans = np.concatenate([_tex(s).reshape(-1, 3) for s in SCANS])
    col, rough, nn = layers(Pm, N, np.clip(aos[sel][:, 0], 0, 1), np.clip(aol[sel][:, 0], 0, 1), sp, rock, nh,
                            scans.mean(0), scans.std(0), sand)
    alb = np.zeros((size, size, 3), np.float32)
    orm = np.zeros((size, size, 3), np.float32)
    onm = np.zeros((size, size, 3), np.float32)
    alb[sel] = col
    orm[sel] = np.stack([np.ones(len(rough)), rough, np.zeros(len(rough))], 1)
    nb2 = nn[:, [0, 2, 1]] * np.array([1, -1, 1])   # model y-up -> Blender z-up
    onm[sel] = nb2 * 0.5 + 0.5
    alb, orm, onm = (_dilate(a, mask) for a in (alb, orm, onm))

    def save(nm, arr):
        p = os.path.join(tmp, nm + ".png")
        Image.fromarray((np.clip(arr[::-1], 0, 1) * 255 + 0.5).astype(np.uint8)).save(p)
        return p

    i_alb = bpy.data.images.load(save(name + "_albedo", alb))
    i_orm = bpy.data.images.load(save(name + "_orm", orm))
    i_orm.colorspace_settings.name = "Non-Color"
    i_onm = bpy.data.images.load(save(name + "_objnormal", onm))
    i_onm.colorspace_settings.name = "Non-Color"
    # object-space normals -> tangent-space map of the low mesh
    i_nrm = bpy.data.images.new(name + "_normal", size, size, alpha=False)
    i_nrm.colorspace_settings.name = "Non-Color"
    m = bpy.data.materials.new("bake_nrm")
    m.use_nodes = True
    Nd, Lk = m.node_tree.nodes, m.node_tree.links
    bsdf = Nd["Principled BSDF"]
    tx = Nd.new("ShaderNodeTexImage")
    tx.image = i_onm
    nmn = Nd.new("ShaderNodeNormalMap")
    nmn.space = "OBJECT"
    Lk.new(tx.outputs["Color"], nmn.inputs["Color"])
    Lk.new(nmn.outputs[0], bsdf.inputs["Normal"])
    tg = Nd.new("ShaderNodeTexImage")
    tg.image = i_nrm
    Nd.active = tg
    lo.data.materials.clear()
    lo.data.materials.append(m)
    bpy.ops.object.select_all(action="DESELECT")
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    sc.cycles.samples = 1
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=16, use_clear=True)
    i_nrm.filepath_raw = os.path.join(tmp, name + "_normal.png")
    i_nrm.file_format = "PNG"
    i_nrm.save()
    # final material: albedo, roughness/metal, normal
    pm = bpy.data.materials.new(name)
    pm.use_nodes = True
    Nd, Lk = pm.node_tree.nodes, pm.node_tree.links
    bsdf = Nd["Principled BSDF"]
    ta = Nd.new("ShaderNodeTexImage")
    ta.image = i_alb
    Lk.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
    to = Nd.new("ShaderNodeTexImage")
    to.image = i_orm
    spn = Nd.new("ShaderNodeSeparateColor")
    Lk.new(to.outputs["Color"], spn.inputs[0])
    Lk.new(spn.outputs["Green"], bsdf.inputs["Roughness"])
    Lk.new(spn.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = Nd.new("ShaderNodeTexImage")
    tn.image = i_nrm
    nmm = Nd.new("ShaderNodeNormalMap")
    Lk.new(tn.outputs["Color"], nmm.inputs["Color"])
    Lk.new(nmm.outputs[0], bsdf.inputs["Normal"])
    lo.data.materials.clear()
    lo.data.materials.append(pm)
    i_alb.name = name + "_albedo"
    i_orm.name = name + "_orm"
    i_nrm.name = name + "_normal"
    path = os.path.join(out, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    lo.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_tangents=True, export_image_format="JPEG", export_jpeg_quality=90)
    return ntri, float(v[:, 1].max())


_RAW = {}


def make_mesh_raw_bounds(name: str) -> tuple[np.ndarray, float]:
    """(offset, scale) normalise() used for spire `name` (cached by main)"""
    return _RAW[name]


def _dilate(img: np.ndarray, mask: np.ndarray, it: int = 24) -> np.ndarray:
    """Grow the covered texels outwards (texture filtering and mips must not pull in the background)"""
    img = img.copy()
    m = mask.copy()
    for _ in range(it):
        acc = np.zeros_like(img)
        cnt = np.zeros(m.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            mm = np.roll(m, (dy, dx), (0, 1))
            acc += np.roll(img, (dy, dx), (0, 1)) * mm[..., None]
            cnt += mm
        grow = (~m) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        m = m | grow
    return img


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(GAME / "models" / "biome"))
    ap.add_argument("--only", default="")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--preview", default="", help="directory for shape previews (no Blender, no GLB)")
    a = ap.parse_args()
    names = [n for n in SPIRES if not a.only or n in a.only.split(",")]
    tmp = tempfile.mkdtemp(prefix="fh_spires_")
    try:
        for n in names:
            F, lo, h = build_field(SPIRES[n])
            v, t = surface_nets(F, lo, h)
            del F
            vn, off, k = normalise(v)
            _RAW[n] = (off, k)
            print("%s: %d high-poly triangles, height %.2f of width" % (n, len(t), float(vn[:, 1].max())))
            if a.preview:
                os.makedirs(a.preview, exist_ok=True)
                preview(vn, t, os.path.join(a.preview, n + ".png"))
                continue
            ntri, hgt = bake_and_export(n, vn, t, a.out, a.size, tmp)
            print("%s: %d game triangles, height %.2f, %d KB" % (n, ntri, hgt,
                                                                os.path.getsize(os.path.join(a.out, n + ".glb")) // 1024))
    finally:
        shutil.rmtree(tmp, True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
