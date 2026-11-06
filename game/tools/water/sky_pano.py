"""Sky panorama the Archipelago sea reflects (Kanta 06.11, water plan step 2): without a sky the water only had
its own colour and read as paint. The ground shader samples this picture along the reflected view ray and adds
it by Fresnel, so slopes facing the horizon turn pale and the clouds slide over the waves.

Source: Poly Haven «Kloofendal 48d Partly Cloudy (Pure Sky)», CC0 (game/art/LICENSES.md), 1k HDR. Only the upper
hemisphere is kept (the sea never reflects the ground), tone mapped to LDR so it works on every preset.

Run (repo root; bpy 5.2 pip module for the HDR reader, numpy, Pillow; network for the download):
  python3 -I game/tools/water/sky_pano.py [--hdr=/abs/file.hdr]
-> game/art/water/sea_sky.png (512 x 128, equirect, rows from zenith to horizon)."""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "game", "art", "water", "sea_sky.png")
URL = "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/kloofendal_48d_partly_cloudy_puresky_1k.hdr"
EXPOSURE = 0.55   # the sun disc and bright clouds stay under white after Reinhard


def load_hdr(path):
    """Linear float RGB of an HDR file, top row = zenith (Blender's image loader stores rows bottom-up)"""
    import bpy
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], np.float32).reshape(h, w, 4)[::-1, :, :3]
    return px


def main(argv):
    opt = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    path = opt.get("hdr")
    if not path:
        path = os.path.join(tempfile.mkdtemp(prefix="fh_sky_"), "sky.hdr")
        subprocess.check_call(["curl", "-sfL", "-o", path, URL])
    px = load_hdr(path)
    h = px.shape[0]
    up = px[: h // 2]                                   # upper hemisphere
    c = up * EXPOSURE
    c = c / (1.0 + c.max(axis=2, keepdims=True))        # Reinhard on the max channel keeps the sky's hue
    c = np.clip(c, 0, 1) ** (1 / 2.2)                   # sRGB-ish for an 8-bit picture
    im = Image.fromarray((c * 255 + 0.5).astype(np.uint8)).resize((512, 128), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im.save(OUT, optimize=True)
    print("wrote %s" % OUT)


if __name__ == "__main__":
    main(sys.argv[1:])
