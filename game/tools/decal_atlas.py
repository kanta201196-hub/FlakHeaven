"""Plane decal atlas (prototype, spec docs/superpowers/specs/2026-10-27-plane-decals-design.md).

Draws the decal set procedurally with PIL (no downloaded art) into one mask atlas:
8 x 4 cells of 256 px, 2048 x 1024. Each pixel stores which paint it takes, not a colour:
R = primary paint, G = secondary paint, B = ink (outline, dark details), A = coverage.
RGB is normalised (R + G + B = 255 where A > 0), so mipmaps and the importer's alpha-border
fix keep the weights; the shader tints the three weights with the player's colours.

Cells (index = row * 8 + column):
 0 skull_winged  1 skull_wrench  2 skull_flame  3 bolt  4 ace_card  5 dice  6 chevrons  7 sun
 8 wasp  9 rook  10 whale  11 cat  12-13 shark_mouth (two cells wide)  14 eye  15 peaks
 16-25 digits 0-9 (PT Sans Bold, game/fonts, OFL)  26 tally_air  27 tally_ground  28 tally_bomb

All shapes are fictional and neutral: no stars, national roundels, flags, eagles or unit marks.

Run: python3 game/tools/decal_atlas.py [--out game/art/decals/decal_atlas.png] [--preview x.png]
Dependencies: Pillow 12. Decision: Kanta 2026-10-27 asked for a decal system proposal.
"""

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CELL = 256
SS = 4  # supersampling
C = CELL * SS
COLS, ROWS = 8, 4
PRIM, SEC, INK = (255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255)
OUT_W = 40  # ink outline width in supersampled pixels


def _cell(w: int = 1) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (C * w, C), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _poly(d: ImageDraw.ImageDraw, pts: list, fill: tuple, outline: bool = True) -> None:
    """Filled polygon with an ink outline drawn first, so the fill sits inside it."""
    if outline:
        d.polygon(pts, fill=INK)
        d.line(pts + [pts[0]], fill=INK, width=OUT_W * 2, joint="curve")
    d.polygon(pts, fill=fill)


def _ellipse(d: ImageDraw.ImageDraw, box: tuple, fill: tuple, outline: bool = True) -> None:
    if outline:
        x0, y0, x1, y1 = box
        d.ellipse((x0 - OUT_W, y0 - OUT_W, x1 + OUT_W, y1 + OUT_W), fill=INK)
    d.ellipse(box, fill=fill)


def _rot(pts: list, ang: float, cx: float, cy: float) -> list:
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def _skull(d: ImageDraw.ImageDraw, cx: float = 512, cy: float = 500, s: float = 1.0) -> None:
    """Bone skull: cranium, jaw, ink eye sockets, nose and teeth lines."""
    _ellipse(d, (cx - 220 * s, cy - 250 * s, cx + 220 * s, cy + 160 * s), PRIM)
    jaw = [(cx - 135 * s, cy + 60 * s), (cx + 135 * s, cy + 60 * s), (cx + 120 * s, cy + 250 * s),
           (cx - 120 * s, cy + 250 * s)]
    _poly(d, jaw, PRIM)
    d.ellipse((cx - 220 * s, cy - 250 * s, cx + 220 * s, cy + 160 * s), fill=PRIM)
    d.polygon(jaw, fill=PRIM)
    for sx in (-1, 1):
        d.ellipse((cx + sx * 95 * s - 70 * s, cy - 70 * s, cx + sx * 95 * s + 70 * s, cy + 70 * s), fill=INK)
    d.polygon([(cx, cy + 80 * s), (cx - 38 * s, cy + 150 * s), (cx + 38 * s, cy + 150 * s)], fill=INK)
    d.line([(cx - 110 * s, cy + 190 * s), (cx + 110 * s, cy + 190 * s)], fill=INK, width=int(18 * s))
    for i in range(-3, 4):
        x = cx + i * 32 * s
        d.line([(x, cy + 165 * s), (x, cy + 245 * s)], fill=INK, width=int(14 * s))


def skull_winged() -> Image.Image:
    img, d = _cell()
    for sx in (-1, 1):
        for k in range(4):   # feathers, longest at the top
            y0 = 360 + k * 85
            length = 330 - k * 55
            x_root = 512 + sx * 150
            tip = (512 + sx * (150 + length), y0 - 60 + k * 10)
            pts = [(x_root, y0), tip, (tip[0] - sx * 60, y0 + 70), (x_root, y0 + 80)]
            _poly(d, pts, SEC)
    _skull(d, 512, 520, 0.8)
    return img


def skull_wrench() -> Image.Image:
    img, d = _cell()
    for ang in (math.radians(45), math.radians(-45)):
        handle = [(470, 120), (554, 120), (554, 900), (470, 900)]
        _poly(d, _rot(handle, ang, 512, 512), SEC)
        for end in (110, 914):   # open jaws at both ends
            _ellipse_r = 95
            cx, cy = _rot([(512, end)], ang, 512, 512)[0]
            _ellipse(d, (cx - _ellipse_r, cy - _ellipse_r, cx + _ellipse_r, cy + _ellipse_r), SEC)
            notch = [(482, end - 120 if end < 500 else end + 120), (542, end - 120 if end < 500 else end + 120),
                     (542, end), (482, end)]
            d.polygon(_rot(notch, ang, 512, 512), fill=(0, 0, 0, 0))
    _skull(d, 512, 500, 0.82)
    return img


def skull_flame() -> Image.Image:
    img, d = _cell()
    pts = [(250, 640), (200, 420), (290, 470), (270, 230), (380, 360), (420, 90), (512, 300), (600, 60),
           (640, 330), (760, 200), (750, 450), (840, 400), (780, 640)]
    _poly(d, pts, SEC)
    inner = [(330, 620), (320, 480), (390, 520), (400, 360), (470, 450), (520, 290), (570, 440), (640, 350),
             (650, 520), (700, 490), (690, 620)]
    d.polygon(inner, fill=PRIM)
    _skull(d, 512, 600, 0.72)
    return img


def bolt() -> Image.Image:
    img, d = _cell()
    _ellipse(d, (130, 130, 894, 894), SEC)
    pts = [(590, 140), (330, 560), (500, 560), (420, 890), (720, 420), (545, 420), (650, 140)]
    _poly(d, pts, PRIM)
    return img


def ace_card() -> Image.Image:
    img, d = _cell()
    d.rounded_rectangle((210 - OUT_W, 90 - OUT_W, 814 + OUT_W, 934 + OUT_W), 70, fill=INK)
    d.rounded_rectangle((210, 90, 814, 934), 50, fill=PRIM)
    # spade: heart turned upside down + stem
    d.ellipse((350, 420, 530, 600), fill=INK)
    d.ellipse((494, 420, 674, 600), fill=INK)
    d.polygon([(358, 540), (666, 540), (512, 300)], fill=INK)
    d.polygon([(512, 520), (450, 720), (574, 720)], fill=INK)
    font = ImageFont.truetype(str(ROOT / "fonts" / "pt_sans_bold.ttf"), 190)
    d.text((300, 230), "A", font=font, fill=SEC, anchor="mm")
    d.text((724, 800), "A", font=font, fill=SEC, anchor="mm")
    return img


def dice() -> Image.Image:
    img, d = _cell()
    for cx, cy, ang, pips in ((370, 600, -0.25, 5), (660, 420, 0.3, 3)):
        sq = [(cx - 190, cy - 190), (cx + 190, cy - 190), (cx + 190, cy + 190), (cx - 190, cy + 190)]
        _poly(d, _rot(sq, ang, cx, cy), PRIM)
        spots = {5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)]}[pips]
        for px, py in spots:
            x, y = _rot([(cx + px * 105, cy + py * 105)], ang, cx, cy)[0]
            d.ellipse((x - 42, y - 42, x + 42, y + 42), fill=INK)
    return img


def chevrons() -> Image.Image:
    img, d = _cell()
    for k, fill in enumerate((PRIM, SEC, PRIM)):
        y = 130 + k * 220
        pts = [(170, y + 240), (512, y), (854, y + 240), (854, y + 370), (512, y + 130), (170, y + 370)]
        _poly(d, pts, fill)
    return img


def sun() -> Image.Image:
    img, d = _cell()
    for k in range(10):   # short wavy-free triangular rays, kept inside the cell (not a rayed flag)
        a = k * math.tau / 10
        tip = (512 + 430 * math.cos(a), 512 + 430 * math.sin(a))
        l = (512 + 300 * math.cos(a - 0.2), 512 + 300 * math.sin(a - 0.2))
        r = (512 + 300 * math.cos(a + 0.2), 512 + 300 * math.sin(a + 0.2))
        _poly(d, [l, tip, r], SEC)
    _ellipse(d, (232, 232, 792, 792), PRIM)
    # a face makes it a mascot, not an emblem
    d.ellipse((400, 430, 450, 500), fill=INK)
    d.ellipse((574, 430, 624, 500), fill=INK)
    d.arc((390, 470, 634, 680), 20, 160, fill=INK, width=26)
    return img


def wasp() -> Image.Image:
    img, d = _cell()
    for box in ((150, 250, 500, 470), (524, 250, 874, 470)):   # wings
        _ellipse(d, box, SEC)
    _ellipse(d, (380, 430, 644, 900), PRIM)   # abdomen
    for k in range(3):
        y = 540 + k * 110
        d.rectangle((370, y, 654, y + 50), fill=INK)
    d.polygon([(480, 880), (544, 880), (512, 990)], fill=INK)   # sting
    _ellipse(d, (420, 280, 604, 450), PRIM)   # thorax
    _ellipse(d, (440, 150, 584, 290), INK, outline=False)   # head
    d.line([(470, 170), (380, 50)], fill=INK, width=24)
    d.line([(554, 170), (644, 50)], fill=INK, width=24)
    d.ellipse((455, 185, 495, 235), fill=PRIM)
    d.ellipse((529, 185, 569, 235), fill=PRIM)
    return img


def rook() -> Image.Image:
    img, d = _cell()
    body = [(220, 620), (330, 460), (520, 400), (690, 430), (760, 520), (720, 640), (560, 720), (380, 720)]
    tail = [(240, 600), (90, 720), (110, 790), (330, 700)]
    _poly(d, tail, INK, outline=False)
    _poly(d, body, INK, outline=False)
    _ellipse(d, (620, 260, 860, 500), INK, outline=False)   # head
    d.polygon([(840, 330), (990, 400), (835, 440)], fill=PRIM)   # pale beak base of a rook
    d.ellipse((730, 330, 780, 380), fill=SEC)   # eye
    wing = [(340, 520), (560, 470), (660, 560), (420, 650)]
    d.polygon(wing, fill=SEC)
    d.line(wing + [wing[0]], fill=INK, width=20)
    for x in (460, 600):   # legs
        d.line([(x, 710), (x - 20, 860)], fill=INK, width=26)
        d.line([(x - 20, 860), (x - 80, 880)], fill=INK, width=22)
        d.line([(x - 20, 860), (x + 40, 880)], fill=INK, width=22)
    return img


def whale() -> Image.Image:
    img, d = _cell()
    body = [(110, 560), (180, 420), (340, 360), (560, 380), (720, 450), (800, 520), (860, 470), (940, 330),
            (990, 360), (930, 520), (980, 640), (930, 650), (850, 590), (700, 640), (500, 690), (280, 680),
            (150, 640)]
    _poly(d, body, PRIM)
    belly = [(140, 610), (300, 600), (520, 630), (700, 610), (520, 680), (290, 675)]
    d.polygon(belly, fill=SEC)
    d.ellipse((250, 470, 300, 520), fill=INK)   # eye
    d.arc((120, 520, 360, 640), 10, 80, fill=INK, width=18)   # smile
    for k in range(3):   # spout
        d.line([(330, 340), (260 + k * 70, 170)], fill=SEC, width=34)
    return img


def cat() -> Image.Image:
    img, d = _cell()
    _poly(d, [(250, 420), (300, 130), (470, 330)], INK, outline=False)
    _poly(d, [(774, 420), (724, 130), (554, 330)], INK, outline=False)
    d.ellipse((220, 260, 804, 860), fill=INK)
    d.polygon([(300, 210), (330, 330), (400, 300)], fill=SEC)
    d.polygon([(724, 210), (694, 330), (624, 300)], fill=SEC)
    for sx in (-1, 1):
        cx = 512 + sx * 120
        d.ellipse((cx - 75, 470, cx + 75, 600), fill=PRIM)
        d.ellipse((cx - 16, 478, cx + 16, 592), fill=INK)
    d.polygon([(485, 650), (539, 650), (512, 690)], fill=SEC)
    for sx in (-1, 1):
        for k in range(3):
            d.line([(512 + sx * 90, 690 + k * 22), (512 + sx * 300, 650 + k * 50)], fill=PRIM, width=10)
    return img


def shark_mouth() -> Image.Image:
    """Two cells wide; the nose is at u = 0 (left), the mouth corner at the right."""
    img, d = _cell(2)
    w = 2 * C
    n = 16

    def top_y(t: float) -> float:   # upper jaw: rises towards the nose
        return 470 - 120 * (1 - t) ** 2

    def bot_y(t: float) -> float:   # lower jaw: deep sag, closes at both ends
        return 480 + 470 * math.sin(math.pi * t) * (1 - 0.45 * t)

    xs = [80 + i * (w - 380) / n for i in range(n + 1)]
    top = [(x, top_y(i / n)) for i, x in enumerate(xs)]
    bot = [(x, bot_y(i / n)) for i, x in enumerate(xs)]
    mouth = top + [(w - 200, 470)] + bot[::-1]
    _poly(d, mouth, SEC)
    for i in range(n):   # teeth on both jaws
        x0, x1 = xs[i], xs[i + 1]
        t0, t1 = i / n, (i + 1) / n
        yt0, yt1 = top_y(t0), top_y(t1)
        d.polygon([(x0, yt0), (x1, yt1), ((x0 + x1) / 2, (yt0 + yt1) / 2 + 170)], fill=PRIM)
        if 0 < i < n - 1:
            yb0, yb1 = bot_y(t0), bot_y(t1)
            d.polygon([(x0, yb0), (x1, yb1), ((x0 + x1) / 2, (yb0 + yb1) / 2 - 150)], fill=PRIM)
    d.line(mouth + [mouth[0]], fill=INK, width=36, joint="curve")
    d.ellipse((w - 700, 130, w - 520, 310), fill=INK)   # eye
    d.ellipse((w - 650, 165, w - 590, 235), fill=PRIM)
    return img


def eye() -> Image.Image:
    img, d = _cell()
    almond = [(130, 560)] + [(130 + 764 * t / 20, 560 - 260 * math.sin(math.pi * t / 20)) for t in range(1, 20)] + \
        [(894, 560)] + [(894 - 764 * t / 20, 560 + 200 * math.sin(math.pi * t / 20)) for t in range(1, 20)]
    _poly(d, almond, PRIM)
    d.ellipse((380, 380, 640, 640), fill=SEC)
    d.ellipse((460, 460, 560, 560), fill=INK)
    d.ellipse((500, 440, 540, 480), fill=PRIM)
    d.polygon([(110, 300), (900, 170), (920, 260), (140, 380)], fill=INK)   # brow
    return img


def peaks() -> Image.Image:
    img, d = _cell()
    _ellipse(d, (520, 170, 860, 510), SEC)
    _poly(d, [(80, 860), (380, 330), (560, 620), (690, 420), (950, 860)], PRIM)
    d.polygon([(380, 330), (300, 470), (350, 450), (390, 490), (440, 430)], fill=INK)
    return img


def digit(n: int) -> Image.Image:
    img, d = _cell()
    font = ImageFont.truetype(str(ROOT / "fonts" / "pt_sans_bold.ttf"), 900)
    d.text((512, 540), str(n), font=font, fill=PRIM, anchor="mm", stroke_width=OUT_W, stroke_fill=INK)
    return img


def tally_air() -> Image.Image:
    """Fictional drone silhouette seen from above: swept delta and a short tail."""
    img, d = _cell()
    _poly(d, [(512, 120), (880, 760), (600, 680), (512, 900), (424, 680), (144, 760)], PRIM)
    return img


def tally_ground() -> Image.Image:
    img, d = _cell()
    d.rounded_rectangle((170 - OUT_W, 380 - OUT_W, 854 + OUT_W, 760 + OUT_W), 60, fill=INK)
    d.rounded_rectangle((170, 380, 854, 760), 40, fill=PRIM)
    _ellipse(d, (380, 300, 640, 520), PRIM)
    d.rectangle((600, 380, 940, 430), fill=INK)
    for k in range(5):
        d.ellipse((220 + k * 125, 640, 300 + k * 125, 720), fill=INK)
    return img


def tally_bomb() -> Image.Image:
    img, d = _cell()
    _ellipse(d, (360, 180, 664, 800), PRIM)
    _poly(d, [(420, 760), (604, 760), (660, 940), (364, 940)], SEC)
    d.rectangle((360, 330, 664, 370), fill=INK)
    return img


def build() -> Image.Image:
    cells: list[tuple[int, Image.Image]] = [
        (0, skull_winged()), (1, skull_wrench()), (2, skull_flame()), (3, bolt()), (4, ace_card()),
        (5, dice()), (6, chevrons()), (7, sun()), (8, wasp()), (9, rook()), (10, whale()), (11, cat()),
        (12, shark_mouth()), (14, eye()), (15, peaks()), (26, tally_air()), (27, tally_ground()),
        (28, tally_bomb()),
    ] + [(16 + n, digit(n)) for n in range(10)]
    atlas = Image.new("RGBA", (COLS * CELL, ROWS * CELL), (0, 0, 0, 0))
    for idx, img in cells:
        small = img.resize((img.width // SS, img.height // SS), Image.Resampling.BOX)
        atlas.alpha_composite(small, ((idx % COLS) * CELL, (idx // COLS) * CELL))
    return _normalise(atlas)


def _normalise(img: Image.Image) -> Image.Image:
    """R + G + B = 255 wherever A > 0: weights stay weights after mipmapping."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            s = r + g + b
            if a == 0 or s == 0:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = (round(r * 255 / s), round(g * 255 / s), round(b * 255 / s), a)
    return img


def preview(atlas: Image.Image, colours: tuple, bg: tuple = (58, 60, 56)) -> Image.Image:
    """Tinted sheet for review: the mask atlas with one primary / secondary / ink set."""
    out = Image.new("RGB", atlas.size, bg)
    src = atlas.load()
    dst = out.load()
    p, s, k = colours
    for y in range(atlas.height):
        for x in range(atlas.width):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            w = (r + g + b) or 1
            col = [(r * p[i] + g * s[i] + b * k[i]) / w for i in range(3)]
            dst[x, y] = tuple(int(bg[i] + (col[i] - bg[i]) * a / 255) for i in range(3))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=str(ROOT / "art" / "decals" / "decal_atlas.png"))
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    atlas = build()
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    atlas.save(a.out, optimize=True)
    if a.preview:
        preview(atlas, ((222, 210, 178), (196, 72, 40), (22, 22, 24))).save(a.preview, quality=90)
    print("decal atlas:", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
