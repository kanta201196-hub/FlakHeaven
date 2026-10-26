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
    "lane_flag": "stone_pathway",
    "trench_soil": "excavated_soil_wall",
    "trench_planks": "brown_planks_04",
    "bag_hessian": "hessian_230",
}


def load(path, mode="RGB"):
    return Image.open(path).convert(mode).resize((S, S), Image.LANCZOS)


for name, src in SETS.items():
    alb = np.asarray(load(D + src + "__Diffuse.jpg")).astype(np.float32)
    Image.fromarray(np.clip(alb, 0, 255).astype(np.uint8)).save(OUT + name + "_albedo.jpg", quality=90)
    if name == "trench_planks":
        print(name, "ok")
        continue
    nrm = np.asarray(load(D + src + "__nor_gl.jpg"))
    hgt = np.asarray(load(D + src + "__Displacement.jpg", "L"))
    nh = np.dstack([nrm[..., 0], nrm[..., 1], hgt])
    Image.fromarray(nh.astype(np.uint8)).save(OUT + name + "_nh.jpg", quality=92)
    print(name, "ok")
