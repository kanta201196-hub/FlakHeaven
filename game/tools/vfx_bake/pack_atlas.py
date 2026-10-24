"""Packs flipbook frames into one atlas for GpuFx (VFX-02, 2026-10-24).

Cells are COLS x COLS, row by row from the top left, in frame-name order. Frames keep straight alpha. Each
frame is scaled to CELL - 4 px with a 2 px transparent border, so mipmaps do not bleed between neighbouring
frames (GpuFx.FLIP_SH samples 0.2 % inside the cell).

--clip-x MIN,MAX (frame px) fades alpha to zero over 24 px inside those columns: some sets end at the edge of
their simulation box, and the smoke would show a straight cut there (mid-air set: --clip-x 142,370).

Run from the repo root:
  python3 game/tools/vfx_bake/pack_atlas.py FRAMES_DIR OUT.png [--cols 8] [--cell 512] [--prefix f] [--clip-x A,B]
Dependencies: Pillow. Frames come from render_vdb.py.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops


def clip_mask(size: tuple[int, int], x0: int, x1: int, ramp: int = 24) -> Image.Image:
    """Alpha multiplier: 1 between x0 + ramp and x1 - ramp, falling to 0 at x0 and x1."""
    row = [max(0.0, min(1.0, (x - x0) / ramp, (x1 - x) / ramp)) for x in range(size[0])]
    line = Image.new("L", (size[0], 1))
    line.putdata([int(v * 255) for v in row])
    return line.resize(size)


def pack(frames: list[Path], out: Path, cols: int, cell: int, clip: tuple[int, int] | None = None) -> None:
    """Writes the atlas of `frames` (exactly cols * cols files) to `out`."""
    atlas = Image.new("RGBA", (cols * cell, cols * cell), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        im = Image.open(f).convert("RGBA")
        if clip is not None:
            r, g, b, a = im.split()
            a = ImageChops.multiply(a, clip_mask(im.size, clip[0], clip[1]))
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
    a = ap.parse_args()
    frames = sorted(a.frames.glob(f"{a.prefix}*.png"))
    if len(frames) != a.cols * a.cols:
        print(f"need {a.cols * a.cols} frames, found {len(frames)}", file=sys.stderr)
        return 1
    if a.out.resolve().parent == a.frames.resolve():
        print("write the atlas outside the frames folder", file=sys.stderr)
        return 1
    clip = tuple(int(v) for v in a.clip_x.split(",")) if a.clip_x else None
    pack(frames, a.out, a.cols, a.cell, clip)
    print(f"{a.out}: {len(frames)} frames, {a.cols * a.cell} px")
    return 0


if __name__ == "__main__":
    sys.exit(main())
