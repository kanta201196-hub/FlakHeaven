"""Weathered paint for the enemy battle models (Kanta 27.10: "check the enemy models, textures and paint: they must
look natural, worn, chipped"). House rule (working-rules.md): no model ships with flat paint.

Two modes, both on the finished battle GLB under game/models/battle/ (the sources are not needed):

atlas — a model whose painted faces already share one texture atlas (the sf_rework / convoy_kit / Meshy models).
    The UVs, geometry, nodes and material names stay exactly as they are; only the pictures inside the GLB change.
    Blender bakes the surface data (world position, true and bevelled normal, AO, part id) into the model's own UV
    layout with turret_paint's emission bakes; numpy weathers the old albedo per texel (so every feature follows
    the 3D shape and never seams at island borders) and writes a new albedo, metallicRoughness (G rough, B metal)
    and normal map; the GLB images are swapped with glb_io (geometry bytes untouched). A body material without a
    metallicRoughness or normal texture gets one.
    The relief (panel seams, chip edges) is turned into normals in UV space: the slope along a texel row is the
    slope along the tangent, so it needs no tangent frame and mirrored islands come out right; it is blended
    over the model's own normal map (whiteout blend), so the source's panel detail stays.
vcol  — a code-built model painted with vertex colours and one flat material (the Leviathan's parts): Blender
    gives it a fresh UV atlas and turret_paint.bake_set's own-colour weathering, then exports the GLB again.

What the weathering adds (per kind): edge chips on convex edges and leading edges, showing primer and then bare
metal; cavity grime; soot from exhausts (recipe points) and guns; streaks along the airflow (aircraft), rain and
dirt down the walls (ground), rust and salt (ships); sun fading on upper faces; panel seams; matte roughness with
variation (Kanta: no gloss). The model's colour identity stays: every layer is a blend over its own colours.

Run (repo root): python3 -I game/tools/blender/enemy_weather.py <recipe|all> [...] [--from=<rev>] [--dry=/abs/dir]
    --from reads each source GLB from that git revision (the unweathered one), so a rerun does not weather twice;
    --dry writes the new GLB and its extracted pictures into that folder instead of game/models/battle.
Dependencies: bpy 5.2 (pip module), numpy, Pillow. No network."""
import io
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import glb_io  # noqa: E402

BATTLE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "models", "battle"))
SOURCE = {"rev": None}   # --from=<git revision>: read the unweathered GLB from git, so a rerun never bakes twice


def source(glb):
    """Path of the GLB to weather: game/models/battle/fh_battle_<glb>.glb, or its copy at revision --from"""
    path = os.path.join(BATTLE, "fh_battle_" + glb + ".glb")
    if not SOURCE["rev"]:
        return path
    import subprocess
    import tempfile
    rel = os.path.relpath(path, os.path.join(BATTLE, "..", "..", ".."))
    data = subprocess.check_output(["git", "show", "%s:%s" % (SOURCE["rev"], rel)], cwd=os.path.dirname(path))
    f = tempfile.NamedTemporaryFile(prefix="fh_ew_", suffix=".glb", delete=False)
    f.write(data)
    f.close()
    import atexit
    atexit.register(os.remove, f.name)
    return f.name

# Recipes. kind: air | ground | sea; m — the model's real length in metres (the GLB is 1 long), so chips, panels,
# streaks and soot keep a real size on every model; panel_m — panel size (default 1.3 m); wear, grime, fade, dust,
# salt, seam — layer strengths (1 = default); bevel_m / ao_m — the edge and occlusion radii of the bake.
# Propeller nodes (prop_*) add exhaust soot behind them; rear-facing occluded faces (jet nozzles) are burnt dark.
RECIPES = {
    # ---- air: Highland (drone, interceptor, missile carrier, bomber, transport, helicopter, rival ace, aces
    # «Почтальон» and «Сквозняк») and Archipelago (drone «Чайка», seaplane «Буревестник», ekranoplan) ----
    "e_drone": {"kind": "air", "m": 9.0, "seed": 3},
    "e_drone_sea": {"kind": "air", "m": 9.0, "seed": 4, "salt": 0.5, "upscale": 2},
    "e_interceptor": {"kind": "air", "m": 20.0, "seed": 5},
    "e_carrier": {"kind": "air", "m": 22.0, "seed": 6},
    "e_seaplane": {"kind": "air", "m": 18.0, "seed": 7, "salt": 0.6},
    "e_bomber": {"kind": "air", "m": 34.0, "seed": 8},
    "e_transport": {"kind": "air", "m": 30.0, "seed": 9},
    "e_helicopter": {"kind": "air", "m": 18.0, "seed": 10},
    "e_ekranoplan": {"kind": "air", "m": 60.0, "seed": 11, "salt": 0.8},
    "e_rival": {"kind": "air", "m": 18.0, "seed": 12},
    "e_postman": {"kind": "air", "m": 17.0, "seed": 13},
    "e_draft": {"kind": "air", "m": 16.0, "seed": 14},
    # ---- ground: Highland convoy and AA position ----
    "e_zsu": {"kind": "ground", "m": 7.0, "seed": 20},
    "e_sam": {"kind": "ground", "m": 12.0, "seed": 21},
    "e_radar": {"kind": "ground", "m": 10.0, "seed": 22},
    "e_convoy_truck": {"kind": "ground", "m": 8.0, "seed": 23},
    "e_convoy_pickup_tent": {"kind": "ground", "m": 5.5, "seed": 24},
    "e_convoy_scout": {"kind": "ground", "m": 7.0, "seed": 25},
    "e_convoy_technical": {"kind": "ground", "m": 5.5, "seed": 26},
    "e_convoy_manpads": {"kind": "ground", "m": 5.5, "seed": 27},
    "e_convoy_ifv": {"kind": "ground", "m": 7.5, "seed": 28},
    # ---- sea: Archipelago ----
    "e_cruiser": {"kind": "sea", "m": 180.0, "seed": 40},
    "e_ship_aa": {"kind": "sea", "m": 50.0, "seed": 41},
    "e_ship_cargo": {"kind": "sea", "m": 120.0, "seed": 42},
    "e_ship_tanker": {"kind": "sea", "m": 120.0, "seed": 43},
    # ---- Fortress dome turrets (fortress.py weather(): turret_paint own-colour bake of the hull skin under the
    # dome); the skin sampled onto the crown came out as faint radial rays: its tone is smoothed over the crowns
    # and a light extra wear goes on top (the dome paint already carries chips and rivets) ----
    "e_fortress_dome": {"glb": "e_fortress", "mat": "fortress_dome_paint", "kind": "air", "m": 50.0, "seed": 16,
                        "blur": 14, "blur_keep": 0.15, "wear": 0.5, "fade": 0.6, "grime": 0.6, "seam": 0.08,
                        "panel_m": 0.7, "bevel_m": 0.02, "ao_m": 0.5},
    # ---- set mode: several flat or vertex-colour materials, one new atlas ----
    "e_albatross": {"kind": "air", "m": 30.0, "seed": 15, "mode": "set", "size": 2048, "salt": 0.6},
    "e_ship_escort": {"kind": "sea", "m": 25.0, "seed": 44, "mode": "set", "size": 1024},
    "e_ship_landing": {"kind": "sea", "m": 20.0, "seed": 45, "mode": "set", "size": 2048},
    "e_leviathan": {"kind": "sea", "m": 250.0, "seed": 46, "mode": "set", "size": 2048},
}
# the Leviathan's knock-out parts (b2_leviathan.py REF: model length 1 = that many metres), whole and broken
for _i, (_p, _m) in enumerate((("e_lev_turret", 26.0), ("e_lev_launcher", 10.0), ("e_lev_radar", 10.0), ("e_lev_zsu", 7.0))):
    for _b in ("", "_broken"):
        RECIPES[_p + _b] = {"kind": "sea", "m": _m, "seed": 50 + _i, "mode": "set", "size": 1024, "vcol": True}

PRIMER = {"air": (0.36, 0.37, 0.31), "ground": (0.30, 0.27, 0.22), "sea": (0.36, 0.22, 0.15)}
BARE = {"air": (0.47, 0.48, 0.49), "ground": (0.36, 0.36, 0.35), "sea": (0.34, 0.32, 0.30)}
DIRT = np.array([0.20, 0.17, 0.13], np.float32)
DUST = np.array([0.62, 0.55, 0.43], np.float32)
SOOT = np.array([0.04, 0.037, 0.035], np.float32)
RUST = np.array([0.36, 0.19, 0.09], np.float32)
SALT = np.array([0.74, 0.74, 0.71], np.float32)
OIL = np.array([0.10, 0.09, 0.075], np.float32)


# ---------------------------------------------------------------- GLB pictures (no Blender)
def _tex_img(g, ti):
    """Image index behind texture ti"""
    return g.j["textures"][ti]["source"]


def read_image(g, ii):
    """Decoded image ii of the GLB as (PIL image, mime type)"""
    im = g.j["images"][ii]
    bv = g.j["bufferViews"][im["bufferView"]]
    o = bv.get("byteOffset", 0)
    return Image.open(io.BytesIO(bytes(g.bin[o:o + bv["byteLength"]]))), im.get("mimeType", "image/jpeg")


def put_image(g, ii, pil, mime):
    """Replace image ii with pil (encoded as mime) and drop the old bytes"""
    b = io.BytesIO()
    if mime == "image/png":
        pil.save(b, "PNG", optimize=True)
    else:
        pil.convert("RGB").save(b, "JPEG", quality=90, optimize=True)
    data = b.getvalue()
    while len(g.bin) % 4:
        g.bin.append(0)
    g.j["bufferViews"].append({"buffer": 0, "byteOffset": len(g.bin), "byteLength": len(data)})
    g.bin += data
    g.j["images"][ii]["bufferView"] = len(g.j["bufferViews"]) - 1
    g.j["images"][ii]["mimeType"] = mime
    g.compact()


def add_image(g, name, pil, mime, sampler_from):
    """New image + texture (same sampler as texture sampler_from); returns the texture index"""
    g.j["images"].append({"name": name, "mimeType": mime, "bufferView": 0})
    ii = len(g.j["images"]) - 1
    put_image(g, ii, pil, mime)
    t = {"source": ii}
    if "sampler" in g.j["textures"][sampler_from]:
        t["sampler"] = g.j["textures"][sampler_from]["sampler"]
    g.j["textures"].append(t)
    return len(g.j["textures"]) - 1


def _is_glass(m):
    n = m.get("name", "")
    return "glass" in n or "core" in n


# ---------------------------------------------------------------- weathering layers (numpy)
def _tp():
    import turret_paint
    return turret_paint


def _seams(P, N, panel, seed, lw):
    """Panel seam depth 0…1 at points P: a staggered grid on the two world axes across each texel's dominant
    normal axis (box projection), long panels along the fuselage axis x"""
    tp = _tp()
    ax = np.argmax(np.abs(N), axis=1)
    i0 = np.where(ax == 0, 1, 0)
    i1 = np.where(ax == 2, 1, 2)
    r = np.arange(len(P))
    a = P[r, i0]
    b = P[r, i1]
    # panels: along x 1.6 x panel, across 1 x panel; every second row shifted by half a panel
    sa = np.where(i0 == 0, panel * 1.6, panel)
    sb = np.where(i1 == 0, panel * 1.6, panel)
    rows = np.floor(b / sb)
    a2 = a + (tp._hash(rows.astype(np.int64), i1.astype(np.int64), np.full(len(P), 3, np.int64), seed) * sa)
    da = np.abs(a2 / sa - np.round(a2 / sa)) * sa
    db = np.abs(b / sb - np.round(b / sb)) * sb
    d = np.minimum(da, db)
    return 1.0 - tp.sstep(lw * 0.4, lw, d)


def _soot(P, pts, length):
    """Soot behind points (x, y, z, r): a plume widening and fading towards -x"""
    s = np.zeros(len(P), np.float32)
    for x, y, z, rad in pts:
        along = x - P[:, 0]
        lat = np.hypot(P[:, 1] - y, P[:, 2] - z)
        w = rad * (1.0 + np.clip(along, 0, None) * 4.0)
        k = np.exp(-(lat / w) ** 2) * np.exp(-np.clip(along, 0, None) / length) * (along > -rad * 0.6)
        s = np.maximum(s, k)
    return s


def layers(P, N, Bd, AO, glass, src, srough, rec, texel):
    """Weathered albedo (sRGB), roughness, metal and relief height for covered texels.
    P model units (length 1), N true normal, Bd dot(bevelled, shading normal), AO 0…1, glass bool (kept as it is), src the old
    albedo (sRGB 0…1), srough the old roughness (None: none). Noise sizes are in metres (rec["m"])."""
    tp = _tp()
    fbm, sstep = tp.fbm, tp.sstep
    kind = rec["kind"]
    seed = rec["seed"]
    wear = rec.get("wear", 1.0)
    L = rec["m"]
    Pm = P * L                        # metres
    paint = ~glass
    col = src.copy()
    lum = (col @ np.array([0.3, 0.59, 0.11], np.float32))[:, None]
    mott = fbm(Pm, 0.45, seed + 1, 4)
    up = np.clip(N[:, 2], 0, 1)
    # --- sun fade on upper faces: paler and greyer, in broad patches
    fade = sstep(0.15, 0.9, up) * (0.55 + 0.9 * (fbm(Pm, 0.25, seed + 2, 3) - 0.5)) * 0.3 * rec.get("fade", 1.0)
    pale = (col * 0.6 + lum * 0.4) * 1.16 + 0.03
    col = col + (pale - col) * (fade * paint)[:, None]
    # --- tonal variation: touched-up panels and a fine grain
    col = col * (1.0 + 0.1 * (mott - 0.5))[:, None]
    col = col * (1.0 + 0.05 * (fbm(Pm, 4.0, seed + 3, 2) - 0.5))[:, None]
    # --- panel seams (about a texel wide, at least 1.2 cm), a little grime in them
    panel = rec.get("panel_m", 1.3) / L
    sm = _seams(P, N, panel, seed, max(texel * 1.15, 0.012 / L)) * paint
    col = col * (1.0 - rec.get("seam", 0.14 if kind != "sea" else 0.08) * sm)[:, None]
    # --- streaks: thin grime lines along the airflow (air); rain and dirt runs down the walls (ground, sea)
    wall = 1.0 - np.abs(N[:, 2])
    if kind == "air":
        st = fbm(Pm * np.array([0.04, 1.0, 1.0], np.float32), 3.5, seed + 4, 3)
        streak = sstep(0.55, 0.8, st) * (0.5 + 0.5 * (1 - np.abs(N[:, 0]))) * 0.3 * rec.get("grime", 1.0)
        col = col * (1 - streak[:, None]) + OIL * streak[:, None]
    else:
        st = fbm(Pm * np.array([1.0, 1.0, 0.06], np.float32), 4.0, seed + 4, 3)
        streak = sstep(0.56, 0.8, st) * wall * (0.2 if kind == "sea" else 0.28) * rec.get("grime", 1.0)
        tone = RUST if kind == "sea" else DIRT
        col = col * (1 - streak[:, None]) + tone * 0.8 * streak[:, None]
    streak = streak * paint
    # --- edge chips: convex edges (bevel vs true normal), aircraft leading edges; small chips (a few cm)
    # showing primer, bare metal only in the deepest ones
    edge = np.clip((1.0 - Bd) * 6.0 - 0.12, 0.0, 1.0) * sstep(0.5, 0.85, AO)
    lead = sstep(0.25, 0.85, N[:, 0]) * (1 - 0.5 * up) if kind == "air" else np.zeros(len(P), np.float32)
    chipn = fbm(Pm, 9.0, seed + 5, 3)
    w = edge * wear * 1.3 + (chipn - 0.5) * 1.4 - 0.5
    w = np.maximum(w, lead * wear * (fbm(Pm * np.array([1.0, 0.3, 1.0], np.float32), 14.0, seed + 6, 2) - 0.5) * 2.2)
    # scattered chips away from edges: small, primer only (on canvas or a broad hood a big bare patch reads fake)
    w = np.maximum(w, np.minimum((fbm(Pm, 9.0, seed + 7, 3) - 0.8) * 2.2 * wear * (chipn > 0.58), 0.25))
    primer = sstep(0.0, 0.05, w) * paint
    # bare metal only in the deepest chips, broken up by the chip noise so thin parts (flap gaps, track
    # teeth) never turn into one continuous bright line
    bare = sstep(0.36, 0.5, w) * sstep(0.45, 0.6, chipn) * paint
    col = col * (1 - 0.8 * primer[:, None]) + np.array(PRIMER[kind], np.float32) * (0.8 * primer)[:, None]
    col = col * (1 - 0.85 * bare[:, None]) + np.array(BARE[kind], np.float32) * (0.85 * bare)[:, None]
    # --- cavity grime (the old albedo already has some AO, so this is light)
    cav = 1.0 - AO
    col = col * (1 - 0.35 * cav[:, None]) + DIRT * (0.35 * cav)[:, None]
    # --- kind-specific dirt
    rough_add = np.zeros(len(P), np.float32)
    if kind == "air":   # undersides: exhaust film and dirt thrown up on take-off, in patches
        under = np.clip(-N[:, 2], 0, 1) * 0.22 * (0.5 + fbm(Pm, 0.8, seed + 15, 3)) * paint * rec.get("grime", 1.0)
        col = col * (1 - under[:, None]) + DIRT * under[:, None]
    if kind == "ground":
        zmin, zmax = rec["_z"]
        hm = (P[:, 2] - zmin) * L          # metres above the lowest point
        mud = (1.0 - sstep(0.15, 0.9, hm)) * (0.45 + 0.6 * (fbm(Pm, 2.0, seed + 8, 3) - 0.5)) * rec.get("dust", 1.0)
        mud = np.clip(mud, 0, 0.75) * paint
        col = col * (1 - mud[:, None]) + (DUST * 0.75) * mud[:, None]
        dust = up * np.clip(cav * 1.5 + (fbm(Pm, 1.5, seed + 9, 3) - 0.5) * 0.8, 0, 0.45) * paint * rec.get("dust", 1.0)
        col = col * (1 - dust[:, None]) + DUST * dust[:, None]
        rough_add += 0.1 * (mud + dust)
    if kind == "sea" or rec.get("salt"):
        zmin = rec["_z"][0]
        salt = up * np.clip(cav * 1.4 + (fbm(Pm, 1.2, seed + 10, 3) - 0.55) * 0.9, 0, 0.4) * paint
        salt = salt * rec.get("salt", 1.0)
        col = col * (1 - salt[:, None]) + SALT * salt[:, None]
        if kind == "sea":
            # dark grime band at the waterline, thin rust runs from the deck edges and fittings down the hull
            wl = (1.0 - sstep(0.0, 0.7, (P[:, 2] - zmin) * L)) * 0.5 * wall
            col = col * (1 - wl[:, None]) + OIL * wl[:, None]
            rb = sstep(0.6, 0.85, fbm(Pm * np.array([1.0, 1.0, 0.05], np.float32), 5.0, seed + 11, 3)) * wall * 0.22
            col = col * (1 - rb[:, None] * paint[:, None]) + RUST * (rb * paint)[:, None]
        rough_add += 0.06 * salt
    # --- soot: behind propellers (exhaust over the nacelles and wings), jet nozzles, gun muzzles
    s = np.zeros(len(P), np.float32)
    if rec.get("props"):
        pts = [(x - 0.8 / L, y, z, 0.5 / L) for x, y, z in rec["props"]]
        s = np.maximum(s, _soot(P, pts, 4.0 / L) * 0.7 * (0.6 + 0.8 * (fbm(Pm, 2.5, seed + 12, 3) - 0.35)))
    if kind == "air":   # rear-facing occluded faces: nozzles and tail pipes burnt dark
        s = np.maximum(s, sstep(0.6, 0.95, -N[:, 0]) * sstep(0.3, 0.9, 1.0 - AO + 0.4) * 0.6)
    if rec.get("guns"):
        s = np.maximum(s, _soot(P, rec["guns"], 0.5 / L) * 0.8)
    s = np.clip(s, 0, 0.9) * paint
    col = col * (1 - s[:, None]) + SOOT * s[:, None]
    # --- roughness: matte paint with variation, rougher dust and soot, smoother bare metal
    base = np.full(len(P), 0.8, np.float32) if srough is None else np.clip(srough, 0.72, 0.92)
    rough = base + 0.1 * (fbm(Pm, 1.5, seed + 13, 3) - 0.5) + 0.05 * (mott - 0.5) + 0.06 * fade + 0.05 * sm
    rough = rough + 0.05 * streak + rough_add + 0.08 * s
    rough = rough * (1 - bare) + 0.6 * bare    # worn, oxidised metal: dull, so it never mirrors the sky
    metal = 0.35 * bare * (1.0 if kind == "air" else 0.8)
    # --- relief: seams sunk, chips sunk a little below the paint, fine orange-peel
    height = -0.5 * sm - 0.35 * primer + 0.08 * (fbm(Pm, 30.0, seed + 14, 2) - 0.5)
    return np.clip(col, 0, 1), np.clip(rough, 0.05, 1), np.clip(metal, 0, 1), height


def layers_chunked(P, N, B, AO, glass, src, srough, rec, texel, chunk=300000):
    """layers() in slices (the noise temporaries of millions of texels do not fit in memory at once); the
    model's height range, which some layers need, is measured on the whole set first"""
    rec["_z"] = (float(P[:, 2].min()), float(P[:, 2].max()))
    outs = [[], [], [], []]
    for a in range(0, len(P), chunk):
        sl = slice(a, a + chunk)
        r = layers(P[sl], N[sl], B[sl], AO[sl], glass[sl], src[sl], None if srough is None else srough[sl], rec, texel)
        for o, v in zip(outs, r):
            o.append(v)
    return [np.concatenate(o) for o in outs]


def _relief_normal(height, mask, step, strength):
    """Tangent-space normals (bottom-up rows, x = +u, y = +v) from a texel height map; differences only between
    covered texels of the same surface (step: world size of a texel, per texel), so island borders stay flat"""
    hp = np.pad(height, 1, mode="edge")
    mp = np.pad(mask, 1)
    def d(a, b, ma, mb):
        return np.where(ma & mb, a - b, 0.0)
    c = hp[1:-1, 1:-1]
    mc = mp[1:-1, 1:-1]
    gx = (d(hp[1:-1, 2:], c, mp[1:-1, 2:], mc) + d(c, hp[1:-1, :-2], mc, mp[1:-1, :-2])) * 0.5
    gy = (d(hp[2:, 1:-1], c, mp[2:, 1:-1], mc) + d(c, hp[:-2, 1:-1], mc, mp[:-2, 1:-1])) * 0.5
    n = np.stack([-gx * strength / step, -gy * strength / step, np.ones_like(gx)], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def _whiteout(a, b):
    """Detail normal b over base normal a (both unit, tangent space)"""
    n = np.stack([a[..., 0] + b[..., 0], a[..., 1] + b[..., 1], a[..., 2] * b[..., 2]], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


# ---------------------------------------------------------------- Blender data bakes
def _bake_data(path, size, rec):
    """Import the GLB, bake position, normals, bevel and AO into its own UV layout; returns float arrays
    (bottom-up rows)"""
    import bpy
    tp = _tp()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    src = [o for o in bpy.data.objects if o.type == "MESH"]
    rec["props"] = [tuple(o.matrix_world.translation) for o in src if o.name.startswith("prop_")]
    proxies = []
    for o in src:
        me = o.data.copy()
        me.transform(o.matrix_world)
        p = bpy.data.objects.new(o.name + "_px", me)
        bpy.context.scene.collection.objects.link(p)
        proxies.append(p)
    for o in list(bpy.data.objects):
        if o not in proxies:
            bpy.data.objects.remove(o)
    if rec.get("mat"):   # one atlas of a model with several: only the faces of that material are baked
        import bmesh
        for p in list(proxies):
            bm = bmesh.new()
            bm.from_mesh(p.data)
            names = [m.name if m else "" for m in p.data.materials]
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if not names or names[f.material_index] != rec["mat"]],
                             context="FACES")
            bm.to_mesh(p.data)
            bm.free()
            if not p.data.polygons:
                proxies.remove(p)
                bpy.data.objects.remove(p)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 0
    bpy.ops.object.select_all(action="DESELECT")
    for p in proxies:
        p.select_set(True)
    bpy.context.view_layer.objects.active = proxies[0]
    bev_r = rec.get("bevel_m", 0.035) / rec["m"]   # edge radius: a few cm
    ao_d = rec.get("ao_m", 1.2) / rec["m"]         # occlusion reach: about a metre

    def b_bev(N, Lk, pid, m=None):
        """dot(bevelled normal, smooth shading normal): 1 on flat or evenly curved skin, lower on edges (against
        the true face normal a smooth low-poly wing would read as one big edge)"""
        b = N.new("ShaderNodeBevel")
        b.samples = 8
        b.inputs["Radius"].default_value = bev_r
        g = N.new("ShaderNodeNewGeometry")
        d = N.new("ShaderNodeVectorMath")
        d.operation = "DOT_PRODUCT"
        Lk.new(b.outputs[0], d.inputs[0])
        Lk.new(g.outputs["Normal"], d.inputs[1])
        return d.outputs["Value"]

    def b_ao(N, Lk, pid, m=None):
        a = N.new("ShaderNodeAmbientOcclusion")
        a.samples = 8
        a.inputs["Distance"].default_value = ao_d
        c = N.new("ShaderNodeCombineColor")
        Lk.new(a.outputs["AO"], c.inputs[0])
        c.inputs[1].default_value = (3 if (m is not None and ("glass" in m.name or "core" in m.name)) else 0) / 8.0 + 0.125
        return c.outputs[0]

    im = tp._img("ew_data", size)
    sc.cycles.samples = 1
    pos = tp._bake_emit(proxies, im, tp._b_pos)
    nrm = tp._bake_emit(proxies, im, tp._b_nrm)
    sc.cycles.samples = 2   # bevel: 2 x 8 rays per texel are plenty for an edge mask
    bev = tp._bake_emit(proxies, im, b_bev)
    sc.cycles.samples = 4   # AO: 4 x 8 rays; its grain is lost under the noise layers
    aop = tp._bake_emit(proxies, im, b_ao)
    return pos, nrm, bev, aop


def weather_atlas(name, out_dir):
    """Atlas mode for battle model `name` (see the module doc); writes <out_dir>/fh_battle_<name>.glb"""
    rec = RECIPES[name]
    glb = rec.get("glb", name)
    path = source(glb)
    g = glb_io.load(path)
    mats = g.j["materials"]
    body = [i for i, m in enumerate(mats) if not _is_glass(m) and "baseColorTexture" in m.get("pbrMetallicRoughness", {})
            and m.get("name") == rec.get("mat", m.get("name"))]
    if not body:
        raise SystemExit("%s: no textured body material" % name)
    bm = mats[body[0]]
    pb = bm["pbrMetallicRoughness"]
    t_alb = pb["baseColorTexture"]["index"]
    i_alb = _tex_img(g, t_alb)
    alb_pil, alb_mime = read_image(g, i_alb)
    # upscale: a small atlas (the 512 px drone) is redrawn larger, so chips and seams get texels of their own
    size = alb_pil.size[0] * rec.get("upscale", 1)
    # every material on this atlas (body and glass) — the bake covers them all
    pos, nrm, bev, aop = _bake_data(path, size, rec)
    H, W = pos.shape[:2]
    mask = aop[..., 1] > 0.05
    glass_px = np.rint(aop[..., 1] * 8 - 1) == 3
    sel = np.nonzero(mask)
    P = (pos[sel][:, :3] - 0.5) / 0.2
    N = nrm[sel][:, :3] * 2 - 1
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-8
    Bv = np.clip(bev[sel][:, 0], -1.0, 1.0)
    AO = np.clip(aop[sel][:, 0], 0, 1)
    glass = glass_px[sel]
    # world size of a texel: distance to the right-hand neighbour where both are covered
    Pw = (pos[..., :3] - 0.5) / 0.2
    dx = np.linalg.norm(Pw[:, 1:] - Pw[:, :-1], axis=-1)
    ok = mask[:, 1:] & mask[:, :-1]
    texel = float(np.median(dx[ok])) if ok.any() else 1.0 / size
    step = np.full((H, W), texel, np.float32)
    # old pictures, as bottom-up arrays like the bakes
    def arr(pil, mode="RGB"):
        return np.asarray(pil.convert(mode).resize((W, H), Image.BICUBIC), np.float32)[::-1] / 255.0
    alb = arr(alb_pil)
    rgh = None
    i_mr = None
    if "metallicRoughnessTexture" in pb:
        i_mr = _tex_img(g, pb["metallicRoughnessTexture"]["index"])
        mr_pil, mr_mime = read_image(g, i_mr)
        mr = arr(mr_pil)
        rgh = mr[..., 1][sel] * pb.get("roughnessFactor", 1.0)
    else:
        mr = np.zeros((H, W, 3), np.float32)
        mr[..., 0] = 1.0
        mr[..., 1] = pb.get("roughnessFactor", 0.9)
        mr[..., 2] = pb.get("metallicFactor", 0.0)
        mr_mime = alb_mime
    i_nm = None
    if "normalTexture" in bm:
        i_nm = _tex_img(g, bm["normalTexture"]["index"])
        nm_pil, nm_mime = read_image(g, i_nm)
        nm = arr(nm_pil) * 2 - 1
        nm /= np.linalg.norm(nm, axis=-1, keepdims=True) + 1e-8
    else:
        nm = np.zeros((H, W, 3), np.float32)
        nm[..., 2] = 1.0
        nm_mime = alb_mime

    src_c = alb[sel]
    if "occlusionTexture" in bm:   # the source's own AO darkened the paint in the game: keep that tone
        oc_pil, _ = read_image(g, _tex_img(g, bm["occlusionTexture"]["index"]))
        oc = arr(oc_pil)[..., 0][sel]
        src_c = src_c * (1.0 - 0.75 * (1.0 - oc))[:, None]
    if rec.get("blur"):   # smear in the old paint (the Fortress domes' radial rays): keep only its broad tone
        from scipy.ndimage import gaussian_filter
        # only the upward faces (the crowns), among themselves: dark fittings next to them do not bleed in
        crown = mask & (nrm[..., 2] * 2 - 1 > 0.55) & (alb.mean(-1) > 0.18)
        mk = crown.astype(np.float32)
        den = gaussian_filter(mk, rec["blur"]) + 1e-6
        soft = np.stack([gaussian_filter(alb[..., c] * mk, rec["blur"]) / den for c in range(3)], -1)[sel]
        k = np.where(crown[sel], rec.get("blur_keep", 0.2), 1.0)[:, None]
        src_c = soft * (1 - k) + src_c * k
    col, rough, metal, height = layers_chunked(P, N, Bv, AO, glass, src_c, rgh, rec, texel)
    new_alb = alb.copy()
    new_alb[sel] = col
    new_mr = mr.copy()
    new_mr[sel] = np.stack([np.ones(len(P), np.float32), rough, metal], 1)
    gl = sel[0][glass], sel[1][glass]
    new_mr[gl] = mr[gl]        # glass texels keep what they had
    hmap = np.zeros((H, W), np.float32)
    hmap[sel] = height * texel * 0.9   # world units: a seam is about a texel deep
    det = _relief_normal(hmap, mask & ~glass_px, step, rec.get("relief", 1.0))
    new_nm = nm.copy()
    new_nm[mask] = _whiteout(nm[mask], det[mask])
    tp = _tp()
    new_alb = tp._dilate(new_alb, mask, 8)
    new_mr = tp._dilate(new_mr, mask, 8)

    def pil(a):
        return Image.fromarray((np.clip(a[::-1], 0, 1) * 255 + 0.5).astype(np.uint8))
    put_image(g, i_alb, pil(new_alb), alb_mime)
    nm_out = pil(new_nm * 0.5 + 0.5)
    if i_nm is not None:
        put_image(g, i_nm, nm_out, nm_mime)
    else:
        bm["normalTexture"] = {"index": add_image(g, "%s_normal" % name, nm_out, nm_mime, t_alb)}
    if i_mr is not None:
        put_image(g, i_mr, pil(new_mr), mr_mime)
    else:
        ti = add_image(g, "%s_orm" % name, pil(new_mr), mr_mime, t_alb)
        for i in body:
            mp = mats[i]["pbrMetallicRoughness"]
            if mp.get("baseColorTexture", {}).get("index") == t_alb:
                mp["metallicRoughnessTexture"] = {"index": ti}
                mp["roughnessFactor"] = 1.0
                mp["metallicFactor"] = 1.0
    for i in body:   # a model on its own atlas: other body materials sharing it get the same normal map
        m = mats[i]
        if m["pbrMetallicRoughness"].get("baseColorTexture", {}).get("index") == t_alb and i != body[0]:
            m["normalTexture"] = dict(bm["normalTexture"])
    out = os.path.join(out_dir, "fh_battle_%s.glb" % glb)
    g.save(out)
    extract(out)
    print("WEATHER %s: %d px, %d texels, texel %.5f -> %s (%.1f MB)" % (name, size, len(P), texel, out,
                                                                       os.path.getsize(out) / 1e6))
    return out


def weather_set(name, out_dir):
    """Set mode for battle model `name`: a fresh UV atlas over every painted face, each face's own colour (its
    texture through the old UVs, its flat colour, or its vertex colour) baked into it, weathered, one paint
    material per model (glass and glowing parts keep theirs); nodes, names and transforms stay, the GLB is
    exported again by Blender. Writes <out_dir>/fh_battle_<name>.glb"""
    import bpy
    tp = _tp()
    rec = RECIPES[name]
    size = rec.get("size", 1024)
    path = source(rec.get("src", name))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    orig = [o for o in bpy.data.objects if o.type == "MESH"]
    # faces of a fully transparent cut-out material are not drawn in the game (the landing craft's source hull
    # shell "NEUTRE"): painting them would show them, so they go
    j = glb_io.load(path).j
    hidden = {m.get("name") for m in j.get("materials", []) if m.get("alphaMode") in ("MASK", "BLEND")
              and m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[3] < m.get("alphaCutoff", 0.5)}
    if hidden:
        import bmesh
        for o in orig:
            names = [m.name if m else "" for m in o.data.materials]
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if names and names[f.material_index] in hidden], context="FACES")
            bm.to_mesh(o.data)
            bm.free()
        print("dropped invisible faces of", sorted(hidden))
    rec["props"] = [tuple(o.matrix_world.translation) for o in orig if o.name.startswith("prop_")]
    vcol = orig[0].data.color_attributes[0].name if rec.get("vcol") and orig[0].data.color_attributes else None
    proxies = []
    for o in orig:
        me = o.data.copy()
        me.transform(o.matrix_world)
        p = bpy.data.objects.new(o.name + "_px", me)
        bpy.context.scene.collection.objects.link(p)
        proxies.append(p)
        o.hide_render = True
        # the old UV layer stays first ("src"), textures sample it; the new atlas is the bake target
        if me.uv_layers:
            for l in list(me.uv_layers)[1:]:
                me.uv_layers.remove(l)
            me.uv_layers[0].name = "src"
            me.uv_layers[0].active_render = True
        uv = me.uv_layers.new(name="UVMap")
        me.uv_layers.active = uv
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 0
    bpy.ops.object.select_all(action="DESELECT")
    for p in proxies:
        p.select_set(True)
    bpy.context.view_layer.objects.active = proxies[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in proxies:   # the src layer drives the textures (unlinked texture nodes read the render UV)
        if "src" in p.data.uv_layers:
            p.data.uv_layers["src"].active_render = True
        p.data.uv_layers.active = p.data.uv_layers["UVMap"]
    bev_r = rec.get("bevel_m", 0.035) / rec["m"]   # edge radius: a few cm
    ao_d = rec.get("ao_m", 1.2) / rec["m"]         # occlusion reach: about a metre

    def b_vcol(N, Lk, pid, m=None):
        v = N.new("ShaderNodeVertexColor")
        v.layer_name = vcol
        return v.outputs["Color"]

    def b_occ(N, Lk, pid, m=None):
        """The material's glTF occlusion texture (R) through the old UVs, 1 where it has none"""
        one = N.new("ShaderNodeRGB")
        one.outputs[0].default_value = (1, 1, 1, 1)
        if m is None or not m.use_nodes:
            return one.outputs[0]
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None and any(
                    lk.to_socket.name == "Occlusion" for lk in n.outputs["Color"].links):
                tx = N.new("ShaderNodeTexImage")
                tx.image = n.image
                uv = N.new("ShaderNodeUVMap")
                uv.uv_map = "src"
                Lk.new(uv.outputs[0], tx.inputs["Vector"])
                return tx.outputs["Color"]
        return one.outputs[0]

    def b_bev(N, Lk, pid, m=None):
        """dot(bevelled normal, smooth shading normal): 1 on flat or evenly curved skin, lower on edges (against
        the true face normal a smooth low-poly wing would read as one big edge)"""
        b = N.new("ShaderNodeBevel")
        b.samples = 8
        b.inputs["Radius"].default_value = bev_r
        g = N.new("ShaderNodeNewGeometry")
        d = N.new("ShaderNodeVectorMath")
        d.operation = "DOT_PRODUCT"
        Lk.new(b.outputs[0], d.inputs[0])
        Lk.new(g.outputs["Normal"], d.inputs[1])
        return d.outputs["Value"]

    def b_ao(N, Lk, pid, m=None):
        a = N.new("ShaderNodeAmbientOcclusion")
        a.samples = 8
        a.inputs["Distance"].default_value = ao_d
        c = N.new("ShaderNodeCombineColor")
        Lk.new(a.outputs["AO"], c.inputs[0])
        c.inputs[1].default_value = (3 if tp._part(m) == 3 else 0) / 8.0 + 0.125
        return c.outputs[0]

    im = tp._img("ew_data", size)
    sc.cycles.samples = 1
    pos = tp._bake_emit(proxies, im, tp._b_pos)
    nrm = tp._bake_emit(proxies, im, tp._b_nrm)
    occ = tp._bake_emit(proxies, im, b_occ)[..., 0].copy()
    vc = tp._bake_emit(proxies, im, b_vcol).copy() if vcol else None
    # each face's own albedo: Cycles' diffuse colour pass reads textures and flat colours alike
    for p in proxies:
        for m in p.data.materials:
            if m is None or not m.use_nodes:
                continue
            tx = m.node_tree.nodes.new("ShaderNodeTexImage")
            tx.image = im
            m.node_tree.nodes.active = tx
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE", margin=0, use_clear=True)
    src = tp._pixels(im).copy()
    sc.cycles.samples = 2   # bevel: 2 x 8 rays per texel are plenty for an edge mask
    bev = tp._bake_emit(proxies, im, b_bev)
    sc.cycles.samples = 4   # AO: 4 x 8 rays; its grain is lost under the noise layers
    aop = tp._bake_emit(proxies, im, b_ao)
    H, W = pos.shape[:2]
    mask = aop[..., 1] > 0.05
    glass_px = np.rint(aop[..., 1] * 8 - 1) == 3
    sel = np.nonzero(mask)
    P = (pos[sel][:, :3] - 0.5) / 0.2
    N = nrm[sel][:, :3] * 2 - 1
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-8
    Bv = np.clip(bev[sel][:, 0], -1.0, 1.0)
    AO = np.clip(aop[sel][:, 0], 0, 1)
    glass = glass_px[sel]
    Pw = (pos[..., :3] - 0.5) / 0.2
    dx = np.linalg.norm(Pw[:, 1:] - Pw[:, :-1], axis=-1)
    ok = mask[:, 1:] & mask[:, :-1]
    texel = float(np.median(dx[ok]))
    # vertex colours of the Leviathan parts were written as sRGB values (b2_leviathan.py), the rest is linear
    S = np.clip(vc[sel][:, :3], 0, 1) if vc is not None else tp._to_srgb(src[sel][:, :3])
    S = S * (1.0 - 0.75 * (1.0 - np.clip(occ[sel], 0, 1)))[:, None]
    col, rough, metal, height = layers_chunked(P, N, Bv, AO, glass, S, None, rec, texel)
    alb = np.zeros((H, W, 3), np.float32)
    orm = np.zeros((H, W, 3), np.float32)
    alb[sel] = col
    orm[sel] = np.stack([np.ones(len(P), np.float32), rough, metal], 1)
    hmap = np.zeros((H, W), np.float32)
    hmap[sel] = height * texel * 0.9
    det = _relief_normal(hmap, mask & ~glass_px, np.full((H, W), texel, np.float32), rec.get("relief", 1.0))
    alb = tp._dilate(alb, mask, 12)
    orm = tp._dilate(orm, mask, 12)
    det = tp._dilate(det, mask, 12)
    tag = "%s_paint" % name

    def save(a, kind, data):
        p = os.path.join(tp.TMP, "%s_%s.png" % (tag, kind))
        Image.fromarray((np.clip(a[::-1], 0, 1) * 255 + 0.5).astype(np.uint8)).save(p)
        i = bpy.data.images.load(p)
        if data:
            i.colorspace_settings.name = "Non-Color"
        return i
    i_alb = save(alb, "albedo", False)
    i_orm = save(orm, "orm", True)
    i_nrm = save(det * 0.5 + 0.5, "normal", True)
    pm = bpy.data.materials.new(tag)
    pm.use_nodes = True
    Nd, Lk = pm.node_tree.nodes, pm.node_tree.links
    bsdf = Nd["Principled BSDF"]
    ta = Nd.new("ShaderNodeTexImage")
    ta.image = i_alb
    Lk.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
    to = Nd.new("ShaderNodeTexImage")
    to.image = i_orm
    sp = Nd.new("ShaderNodeSeparateColor")
    Lk.new(to.outputs["Color"], sp.inputs[0])
    Lk.new(sp.outputs["Green"], bsdf.inputs["Roughness"])
    Lk.new(sp.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = Nd.new("ShaderNodeTexImage")
    tn.image = i_nrm
    nm = Nd.new("ShaderNodeNormalMap")
    Lk.new(tn.outputs["Color"], nm.inputs["Color"])
    Lk.new(nm.outputs[0], bsdf.inputs["Normal"])
    # back onto the original objects: same topology as the proxies, so the new UVs copy loop by loop
    for o, p in zip(orig, proxies):
        me, pme = o.data, p.data
        uvs = np.empty(len(pme.loops) * 2, np.float32)
        pme.uv_layers["UVMap"].data.foreach_get("uv", uvs)
        while me.uv_layers:
            me.uv_layers.remove(me.uv_layers[0])
        me.uv_layers.new(name="UVMap").data.foreach_set("uv", uvs)
        mats = list(me.materials)
        kept = []
        idx = np.zeros(len(me.polygons), np.int32)
        for f in me.polygons:
            m = mats[f.material_index] if mats else None
            if tp._part(m) == 3:
                if m not in kept:
                    kept.append(m)
                idx[f.index] = 1 + kept.index(m)
        me.materials.clear()
        me.materials.append(pm)
        for m in kept:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", idx)
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        me.update()
        o.hide_render = False
    for p in proxies:
        bpy.data.objects.remove(p)
    out = os.path.join(out_dir, "fh_battle_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_image_format="JPEG",
                              export_jpeg_quality=90, export_vertex_color="NONE", use_selection=False)
    extract(out)
    print("WEATHER %s (set): %d px, %d texels, texel %.5f -> %s (%.1f MB)" % (name, size, len(P), texel, out,
                                                                             os.path.getsize(out) / 1e6))
    return out


def extract(glb):
    """Write the GLB's pictures next to it the way Godot extracts them (<glb>_<image name>.<ext>): Godot keeps an
    extracted file that already exists, and the imported scene uses that file, not the bytes in the GLB"""
    g = glb_io.load(glb)
    base = os.path.splitext(glb)[0]
    for i, im in enumerate(g.j.get("images", [])):
        bv = g.j["bufferViews"][im["bufferView"]]
        o = bv.get("byteOffset", 0)
        ext = ".png" if im.get("mimeType") == "image/png" else ".jpg"
        with open("%s_%s%s" % (base, im.get("name", "Image_%d" % i), ext), "wb") as f:
            f.write(bytes(g.bin[o:o + bv["byteLength"]]))


def main(argv):
    names = [a for a in argv if not a.startswith("--")]
    opt = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    out = opt.get("dry", BATTLE)
    SOURCE["rev"] = opt.get("from")
    os.makedirs(out, exist_ok=True)
    if names == ["all"]:
        names = list(RECIPES)
    if len(names) > 1:   # one process per model: memory goes back to the system between them
        import subprocess
        bad = [n for n in names if subprocess.call([sys.executable, "-I", os.path.abspath(__file__), n]
                                                   + [a for a in argv if a.startswith("--")]) != 0]
        if bad:
            raise SystemExit("failed: %s" % " ".join(bad))
        return
    for n in names:
        if RECIPES[n].get("mode") == "set":
            weather_set(n, out)
        else:
            weather_atlas(n, out)


if __name__ == "__main__":
    main(sys.argv[1:])
