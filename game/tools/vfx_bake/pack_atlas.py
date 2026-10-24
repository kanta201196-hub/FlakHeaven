"""Packs flipbook frames into one atlas for GpuFx (VFX-02, 2026-10-24).

Cells are COLS x COLS, row by row from the top left, in frame-name order. Frames keep straight alpha. Each
frame is scaled to CELL - 4 px with a 2 px transparent border, so mipmaps do not bleed between neighbouring
frames (GpuFx.FLIP_SH samples 0.2 % inside the cell).

--clip-x MIN,MAX (frame px) fades alpha to zero inside those columns, --clip-top Y also below that row: some sets
end at the edge of their simulation box, and dense smoke would show a straight cut there. The fade is wide
(--ramp, 80 px) and its edge is broken by fixed low-frequency noise, so the border reads as a ragged puff
edge, not a line; the noise is the same in every frame, so it does not flicker (mid-air set: --clip-x 142,370;
own flak bake: --clip-x 142,370 --clip-top 84).

Run from the repo root:
  python3 game/tools/vfx_bake/pack_atlas.py FRAMES_DIR OUT.png [--cols 8] [--cell 512] [--prefix f] [--clip-x A,B] [--clip-top Y] [--ramp 80]
Dependencies: Pillow, NumPy. Frames come from render_vdb.py.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops


def clip_mask(size: tuple[int, int], x0: int, x1: int, top: int | None = None, ramp: int = 80) -> Image.Image:
    """Alpha multiplier: 1 deep inside the box, 0 at its sides (and top), with a noisy smoothstep in between."""
    w, h = size
    xs = np.arange(w, dtype=np.float32)[None, :]
    ys = np.arange(h, dtype=np.float32)[:, None]
    d = np.minimum(xs - x0, x1 - xs) * np.ones((h, 1), np.float32)
    if top is not None:
        d = np.minimum(d, ys - top)
    rng = np.random.default_rng(7)
    noise = np.zeros((h, w), np.float32)
    for cells, amp in ((6, 0.6), (14, 0.3), (32, 0.15)):
        layer = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        noise += (np.asarray(layer, np.float32) / 255.0 - 0.5) * amp
    t = np.clip((d / ramp) + noise, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    t[d <= 0] = 0.0
    return Image.fromarray((t * 255).astype(np.uint8))


def pack(frames: list[Path], out: Path, cols: int, cell: int, clip: tuple[int, int] | None = None,
         top: int | None = None, ramp: int = 80) -> None:
    """Writes the atlas of `frames` (exactly cols * cols files) to `out`."""
    atlas = Image.new("RGBA", (cols * cell, cols * cell), (0, 0, 0, 0))
    mask = None
    for i, f in enumerate(frames):
        im = Image.open(f).convert("RGBA")
        if clip is not None:
            if mask is None:
                mask = clip_mask(im.size, clip[0], clip[1], top, ramp)
            r, g, b, a = im.split()
            a = ImageChops.multiply(a, mask)
            im = Image.merge("RGBA", (r, g, b, a))
        im = im.resize((cell - 4, cell - 4), Image.LANCZOS)
        atlas.paste(im, ((i % cols) * cell + 2, (i // cols) * cell + 2))
    atlas.save(out, optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("frames", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--cell", type=int, default=512)
    ap.add_argument("--prefix", default="f")
    ap.add_argument("--clip-x", default=None, help="MIN,MAX frame columns where the simulation box ends")
    ap.add_argument("--clip-top", type=int, default=None, help="frame row where the box ends at the top (needs --clip-x)")
    ap.add_argument("--ramp", type=int, default=80, help="fade width in frame px")
    a = ap.parse_args()
    frames = sorted(a.frames.glob(f"{a.prefix}*.png"))
    if len(frames) != a.cols * a.cols:
        print(f"need {a.cols * a.cols} frames, found {len(frames)}", file=sys.stderr)
        return 1
    if a.out.resolve().parent == a.frames.resolve():
        print("write the atlas outside the frames folder", file=sys.stderr)
        return 1
    clip = tuple(int(v) for v in a.clip_x.split(",")) if a.clip_x else None
    pack(frames, a.out, a.cols, a.cell, clip, a.clip_top, a.ramp)
    print(f"{a.out}: {len(frames)} frames, {a.cols * a.cell} px")
    return 0


if __name__ == "__main__":
    sys.exit(main())
