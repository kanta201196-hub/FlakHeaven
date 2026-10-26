"""Pack downloaded CC0 maps into the game's layout: <set>_albedo.jpg and <set>_nh.jpg
(R,G = OpenGL normal, B = height), 1024 px. Sources: Poly Haven 2k Diffuse, nor_gl, Displacement
(credits: game/art/LICENSES.md). Planks only need colour (the trench shader uses the soil normal).
Usage: python3 -I prep_road.py <download_dir> <out_dir>"""
import sys
import numpy as np
from PIL import Image

D, OUT = sys.argv[1].rstrip("/") + "/", sys.argv[2].rstrip("/") + "/"
S = 1024
SETS = {
    "road_tracks": "dirt_aerial_02",
    "road_gravel": "sandy_gravel_02",
    "road_sand": "red_sand",
    "lane_flag": "stone_pathway",
    "lane_cobble": "cobblestone_large_01",
    "trench_soil": "excavated_soil_wall",
    "trench_planks": "brown_planks_04",
    "bag_hessian": "hessian_230",
}


def load(path, mode="RGB"):
    return Image.open(path).convert(mode).resize((S, S), Image.LANCZOS)


for name, src in SETS.items():
    alb = np.asarray(load(D + src + "__Diffuse.jpg")).astype(np.float32)
    if name == "lane_cobble":
        # grass tufts between the stones: dry them to soil colour (arid highlands, no green)
        r, g, b = alb[..., 0], alb[..., 1], alb[..., 2]
        green = np.clip((g - np.maximum(r, b) * 0.97) / 6.0, 0.0, 1.0)[..., None]
        lum = (0.3 * r + 0.59 * g + 0.11 * b)[..., None]
        soil = lum * np.array([1.12, 0.98, 0.8])
        alb = alb * (1.0 - green) + soil * green
    Image.fromarray(np.clip(alb, 0, 255).astype(np.uint8)).save(OUT + name + "_albedo.jpg", quality=90)
    if name == "trench_planks":
        print(name, "ok")
        continue
    nrm = np.asarray(load(D + src + "__nor_gl.jpg"))
    hgt = np.asarray(load(D + src + "__Displacement.jpg", "L"))
    nh = np.dstack([nrm[..., 0], nrm[..., 1], hgt])
    Image.fromarray(nh.astype(np.uint8)).save(OUT + name + "_nh.jpg", quality=92)
    print(name, "ok")
