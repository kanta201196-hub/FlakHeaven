"""Weathered surface maps for the Archipelago scenery props (game/models/biome2), Kanta 06.11: «проверяй модели и
исправляй их». Rule S3 of docs/standards/art-quality-bar.md: every scenery model carries colour + normal + ORM
(roughness) maps; the biome 2 props had only a colour map, so they read flat and evenly shiny next to the
Highland props.

Each prop goes through enemy_weather.weather_set (the "set" mode built for code-made enemies): a fresh UV atlas
over every face, the face's own colour (its old texture or flat colour) baked into it, then the house weathering —
cavity grime, dirt and rain runs down the walls, sun fading, dust on top, salt and a dark waterline on sea props,
edge chips where a material chips — plus a roughness map with variation (matte, Kanta: no gloss) and a relief
normal map. The geometry, node and the colour identity stay; only the surface changes.

Kinds (the `kind` of enemy_weather.layers, plus how much of each layer):
  wall   — plaster, stone, concrete buildings: dirt runs, dust, light chips (plaster off the stone), no panel seams
  metal  — guns, crane, mast: chips to primer and steel, panel seams, rust runs
  sea    — piers, boats, buoys, wrecks, breakwater: salt, waterline grime, rust runs
  rock   — cliffs and rocks: grime in cracks, dust on ledges, no chips or seams
  plant  — trees, reeds, shrubs: only a light grime, AO and roughness; no chips, seams or dust
Real size: the model is 1 long; its length in metres comes from SeaProps.KINDS (width px / 6 px per metre,
docs/biome2/models-pipeline.md), so chips and streaks keep a real size.

Not here: a37_pine_b and a38_tree_leaf (alpha cut-out cards, they are replaced instead, backlog B2-Q07);
a32_cliff_b is not placed (Kanta 19.10); a31_cliff_a and a33_rock are rebuilt with their own maps by shore_cliffs.py (B2-Q04).

Run from the repo root (bpy 5.2 module, numpy, Pillow, scipy):
  python3 -I game/tools/blender/prop_weather.py <prop|all> [...] [--from=<rev>] [--dry=/abs/dir]
--from reads each source GLB from that git revision (the unweathered one), so a rerun never weathers twice;
--dry writes the GLB and its pictures there instead of game/models/biome2. Then `godot --headless --path game
--import`. The old single colour map (<prop>_paint_<prop>.jpg) is removed with its .import; the new maps get
BC7 imports (rule T3)."""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import enemy_weather as ew  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
BIOME2 = os.path.join(ROOT, "game", "models", "biome2")
SEA_PROPS = os.path.join(ROOT, "game", "scripts", "sea_props.gd")
PX_PER_M = 6.0

# layer strengths per kind on top of enemy_weather.layers (1 = the enemy default)
KIND = {
    "wall": {"kind": "ground", "wear": 0.45, "seam": 0.0, "grime": 1.0, "dust": 0.7, "fade": 0.6, "relief": 0.8,
             "bevel_m": 0.05, "ao_m": 1.5},
    "metal": {"kind": "ground", "wear": 0.9, "grime": 1.0, "dust": 0.6, "salt": 0.5, "panel_m": 1.0},
    "sea": {"kind": "sea", "wear": 0.7, "seam": 0.05, "grime": 1.0, "salt": 0.9, "panel_m": 1.2, "ao_m": 1.0},
    "rock": {"kind": "ground", "wear": 0.0, "seam": 0.0, "grime": 0.8, "dust": 0.5, "fade": 0.4, "relief": 1.4,
             "bevel_m": 0.12, "ao_m": 3.0},
    "plant": {"kind": "ground", "wear": 0.0, "seam": 0.0, "grime": 0.35, "dust": 0.15, "fade": 0.3, "relief": 0.5,
              "bevel_m": 0.03, "ao_m": 1.2},
}

# prop file → (kind, atlas size); the model's metres come from SeaProps.KINDS
PROPS = {
    "a01_battery_gun": ("metal", 1024), "a01_battery_gun_broken": ("metal", 1024),
    "a02_bunker_coast": ("wall", 1024), "a03_radar_mast": ("metal", 1024), "a04_lighthouse": ("wall", 1024),
    "a05_pier_a": ("sea", 2048), "a06_pier_b": ("sea", 2048), "a07_tetrapod": ("sea", 512),
    "a08_warehouse_a": ("wall", 1024), "a09_warehouse_b": ("wall", 1024), "a10_crane": ("metal", 1024),
    "a11_tower_ruins": ("wall", 2048), "a20_bell_tower": ("wall", 1024), "a21_terrace_wall": ("wall", 1024),
    "a22_buoy_red": ("sea", 512), "a23_buoy_green": ("sea", 512), "a24_boat_a": ("sea", 1024),
    "a25_boat_b": ("sea", 1024), "a26_wreck_a": ("sea", 1024), "a27_wreck_b": ("sea", 1024),
    "a28_wreck_plane_sea": ("sea", 1024), "a29_hedgehog": ("metal", 512), "a30_boom_net": ("sea", 512),
    "a34_olive_a": ("plant", 512), "a35_olive_b": ("plant", 512), "a36_pine_a": ("plant", 512),
    "a39_reed": ("plant", 256), "a40_shrub": ("plant", 512),
}
for _i in range(1, 9):
    PROPS["a%d_house_%d" % (11 + _i, _i)] = ("wall", 1024)


def metres():
    """Prop file → real length in metres, from the width ranges in SeaProps.KINDS"""
    out = {}
    for f, lo, hi in re.findall(r'"res://models/biome2/(\w+)",\s*([\d.]+),\s*([\d.]+)', open(SEA_PROPS).read()):
        out[f] = (float(lo) + float(hi)) * 0.5 / PX_PER_M
    return out


def source(name, rev):
    """Path of the prop's GLB: the working copy, or a temp copy from git revision rev"""
    path = os.path.join(BIOME2, name + ".glb")
    if not rev:
        return path
    data = subprocess.check_output(["git", "show", "%s:game/models/biome2/%s.glb" % (rev, name)], cwd=ROOT)
    f = tempfile.NamedTemporaryFile(prefix="fh_pw_", suffix=".glb", delete=False)
    f.write(data)
    f.close()
    return f.name


def import_file(pic, template):
    """A BC7 .import for a new map, from an existing biome2 texture .import (uid and paths dropped: Godot writes
    them on import)"""
    keep = []
    for line in open(template).read().splitlines():
        if line.startswith(("uid=", "path.", "source_file=", "dest_files=")) or line.startswith('"md5"'):
            continue
        keep.append(line)
    txt = "\n".join(keep)
    txt = txt.replace("compress/mode=0", "compress/mode=2").replace("compress/high_quality=false",
                                                                   "compress/high_quality=true")
    rel = os.path.relpath(pic, os.path.join(ROOT, "game")).replace(os.sep, "/")
    txt = txt.replace("[deps]\n", '[deps]\n\nsource_file="res://%s"\n' % rel)
    open(pic + ".import", "w").write(txt + "\n")


def weather(name, out_dir, rev):
    """Weather one prop into out_dir/<name>.glb with its three maps written next to it"""
    kind, size = PROPS[name]
    m = metres().get(name)
    if m is None:
        raise SystemExit("%s: not in SeaProps.KINDS" % name)
    rec = dict(KIND[kind])
    rec.update({"m": m, "seed": 100 + sorted(PROPS).index(name), "mode": "set", "size": size})
    src = source(name, rev)
    ew.RECIPES[name] = rec
    ew.source = lambda glb: src
    tmp = tempfile.mkdtemp(prefix="fh_pw_out_")
    built = ew.weather_set(name, tmp)
    out = os.path.join(out_dir, name + ".glb")
    template = os.path.join(BIOME2, "%s_paint_%s.jpg.import" % (name, name))
    if not os.path.exists(template):
        template = sorted(glob.glob(os.path.join(BIOME2, "*_paint_*.jpg.import")))[0]
    tpl_copy = os.path.join(tmp, "template.import")
    shutil.copy(template, tpl_copy)
    for old in glob.glob(os.path.join(out_dir, name + "_*")):   # this prop's old extracted pictures
        if re.match(re.escape(name) + r"_(paint|Image|buoy|debris|material|Material|fh_)", os.path.basename(old)):
            os.remove(old)
    shutil.move(built, out)
    ew.extract(out)
    for pic in glob.glob(os.path.join(out_dir, name + "_*.jpg")):
        if not os.path.exists(pic + ".import"):
            import_file(pic, tpl_copy)
    shutil.rmtree(tmp, ignore_errors=True)
    if rev:
        os.remove(src)
    print("PROP %s: %s, %.1f m, %d px -> %s" % (name, kind, m, size, out))


def main(argv):
    names = [a for a in argv if not a.startswith("--")]
    opt = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    out = opt.get("dry", BIOME2)
    os.makedirs(out, exist_ok=True)
    if names == ["all"]:
        names = sorted(PROPS)
    if len(names) > 1:   # one process per prop: Blender memory goes back to the system between them
        bad = [n for n in names if subprocess.call([sys.executable, "-I", os.path.abspath(__file__), n]
                                                   + [a for a in argv if a.startswith("--")]) != 0]
        if bad:
            raise SystemExit("failed: %s" % " ".join(bad))
        return
    for n in names:
        weather(n, out, opt.get("from"))


if __name__ == "__main__":
    main(sys.argv[1:])
