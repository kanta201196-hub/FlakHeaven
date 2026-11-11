"""Deluxe-pack stickers for the plane decal atlas (ED-04, ED-08; Kanta 2026-11-06, two editions at launch).

Ten author stickers per class («Оса», «Грач», «Кит») and twenty «Хулиганский ящик» meme stickers, drawn with
the same helpers and mask channels as decal_atlas.py (R primary paint, G secondary, B ink, A coverage).
Every shape is an own drawing: no copyrighted meme pictures, no real people, no insignia, flags or stars.
Words inside pictures are avoided (the editor names are translated); the only letters are the universal gamer
marks «F», «GG», «Zz» and digits.

EDITIONS lists [id, drawing] in atlas order from cell FIRST; decal_atlas.build() places them,
DecalCatalog.IMAGES maps the ids to the same cells.
"""

import math

from PIL import Image, ImageDraw, ImageFont

import decal_atlas as A

PRIM, SEC, INK, CLEAR = A.PRIM, A.SEC, A.INK, (0, 0, 0, 0)
FIRST = 32   # first atlas cell of the pack (cells 0-31 hold the base set)


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(A.ROOT / "fonts" / "pt_sans_bold.ttf"), size)


def _line(d: ImageDraw.ImageDraw, pts: list, fill: tuple, w: int) -> None:
    """Thick line with an ink edge under it."""
    d.line(pts, fill=INK, width=w + A.OUT_W * 2, joint="curve")
    for p in (pts[0], pts[-1]):
        r = (w + A.OUT_W * 2) / 2
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=INK)
    d.line(pts, fill=fill, width=w, joint="curve")
    for p in (pts[0], pts[-1]):
        r = w / 2
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=fill)


def _star_pts(cx: float, cy: float, r0: float, r1: float, n: int, rot: float = 0.0) -> list:
    """Burst outline with n points (n >= 7, so it never reads as a five-pointed military star)."""
    pts = []
    for k in range(n * 2):
        a = rot + k * math.pi / n
        r = r1 if k % 2 == 0 else r0
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def _missile(d, x0, x1, y, h, fill=SEC):
    body = [(x0, y - h), (x1 - 120, y - h), (x1, y), (x1 - 120, y + h), (x0, y + h)]
    A._poly(d, body, fill)
    for s in (-1, 1):
        d.polygon([(x0, y + s * h), (x0 + 110, y + s * h), (x0 - 20, y + s * (h + 90))], fill=INK)


def _goggles(d, cx, cy, s=1.0):
    d.rectangle((cx - 230 * s, cy - 22 * s, cx + 230 * s, cy + 22 * s), fill=INK)
    for sx in (-1, 1):
        x = cx + sx * 95 * s
        d.ellipse((x - 85 * s, cy - 75 * s, x + 85 * s, cy + 75 * s), fill=INK)
        d.ellipse((x - 60 * s, cy - 52 * s, x + 60 * s, cy + 52 * s), fill=SEC)
        d.ellipse((x - 35 * s, cy - 40 * s, x - 5 * s, cy - 12 * s), fill=PRIM)


# ---- «Оса» ---------------------------------------------------------------------------------------------------

def wasp_missile() -> Image.Image:
    img, d = A._cell()
    _missile(d, 110, 930, 650, 85)
    for box in ((300, 250, 520, 420), (500, 230, 720, 400)):
        A._ellipse(d, box, SEC)
    A._ellipse(d, (300, 380, 560, 560), PRIM)
    for k in range(2):
        d.rectangle((340 + k * 90, 390, 380 + k * 90, 555), fill=INK)
    A._ellipse(d, (540, 330, 700, 490), PRIM)
    d.ellipse((610, 370, 650, 420), fill=INK)
    d.line([(600, 340), (650, 220)], fill=INK, width=22)
    d.line([(640, 350), (730, 250)], fill=INK, width=22)
    return img


def honeycomb() -> Image.Image:
    img, d = A._cell()
    r = 120
    for row in range(-1, 3):
        for col in range(-1, 5):
            cx = 180 + col * r * 1.5
            cy = 330 + row * r * 1.732 + (col % 2) * r * 0.866
            if not (150 < cy < 880):
                continue
            hexa = [(cx + r * math.cos(k * math.pi / 3), cy + r * math.sin(k * math.pi / 3)) for k in range(6)]
            d.polygon(hexa, fill=INK)
            inner = [(cx + (r - 26) * math.cos(k * math.pi / 3), cy + (r - 26) * math.sin(k * math.pi / 3))
                     for k in range(6)]
            d.polygon(inner, fill=PRIM if (row + col) % 3 else SEC)
    return img


def sting_arrow() -> Image.Image:
    img, d = A._cell()
    A._poly(d, [(512, 80), (760, 520), (590, 470), (590, 940), (434, 940), (434, 470), (264, 520)], PRIM)
    d.polygon([(512, 200), (640, 440), (512, 410), (384, 440)], fill=SEC)
    return img


def winged_bolt() -> Image.Image:
    img, d = A._cell()
    for sx in (-1, 1):
        for k in range(3):
            y = 430 + k * 70
            tip = (512 + sx * (470 - k * 70), y - 80 + k * 20)
            A._poly(d, [(512 + sx * 90, y), tip, (tip[0] - sx * 50, y + 60), (512 + sx * 90, y + 70)], SEC)
    A._poly(d, [(560, 120), (380, 560), (500, 560), (450, 900), (650, 430), (530, 430), (620, 120)], PRIM)
    return img


def wasp_ace() -> Image.Image:
    img, d = A._cell()
    A._ellipse(d, (230, 220, 794, 820), PRIM)   # head
    d.chord((210, 160, 814, 640), 180, 360, fill=INK)   # leather flying helmet
    d.chord((240, 190, 784, 610), 180, 360, fill=SEC)
    for sx in (-1, 1):   # ear flaps
        x = 512 + sx * 250
        d.rounded_rectangle((x - 70, 400, x + 70, 690), 50, fill=INK)
        d.rounded_rectangle((x - 48, 420, x + 48, 670), 40, fill=SEC)
    _goggles(d, 512, 380, 1.0)
    for sx in (-1, 1):
        d.ellipse((512 + sx * 120 - 55, 520, 512 + sx * 120 + 55, 620), fill=INK)
    d.arc((400, 600, 624, 740), 20, 160, fill=INK, width=24)   # grin
    d.line([(450, 190), (380, 60)], fill=INK, width=26)
    d.line([(574, 190), (644, 60)], fill=INK, width=26)
    return img


def reticle() -> Image.Image:
    img, d = A._cell()
    for r, fill in ((400, INK), (360, CLEAR), (240, INK), (205, CLEAR)):
        d.ellipse((512 - r, 512 - r, 512 + r, 512 + r), fill=fill)
    for r, fill in ((375, PRIM), (220, SEC)):
        d.ellipse((512 - r, 512 - r, 512 + r, 512 + r), outline=fill, width=22)
    for a in range(4):
        x, y = math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
        _line(d, [(512 + x * 120, 512 + y * 120), (512 + x * 460, 512 + y * 460)], PRIM, 34)
    d.ellipse((482, 482, 542, 542), fill=SEC)
    return img


def swallow() -> Image.Image:
    img, d = A._cell()
    body = [(512, 230), (580, 330), (600, 520), (700, 860), (560, 680), (512, 760), (464, 680), (324, 860),
            (424, 520), (444, 330)]
    for sx in (-1, 1):
        wing = [(512 + sx * 60, 420), (512 + sx * 460, 300), (512 + sx * 380, 420), (512 + sx * 90, 560)]
        A._poly(d, wing, INK, outline=False)
    A._poly(d, body, INK, outline=False)
    d.polygon([(480, 380), (544, 380), (560, 560), (464, 560)], fill=PRIM)   # light throat and belly
    d.polygon([(495, 250), (529, 250), (512, 200)], fill=SEC)
    return img


def daredevil() -> Image.Image:
    img, d = A._cell()
    A._skull(d, 512, 560, 0.85)
    d.chord((300, 250, 724, 650), 190, 350, fill=SEC)   # helmet cap
    _goggles(d, 512, 380, 1.05)
    return img


def nose_flames() -> Image.Image:
    img, d = A._cell()
    for k, (y, ln) in enumerate(((250, 820), (420, 940), (590, 900), (760, 760))):
        pts = [(80, y - 70)]
        for i in range(1, 7):
            x = 80 + ln * i / 7
            pts.append((x, y - 70 + (40 if i % 2 else -10) - i * 6))
        pts += [(80 + ln, y), (80 + ln * 0.8, y + 40)]
        for i in range(6, 0, -1):
            x = 80 + ln * i / 7
            pts.append((x, y + 70 - (40 if i % 2 else -10) + i * 6))
        pts.append((80, y + 70))
        A._poly(d, pts, PRIM if k % 2 else SEC)
    return img


def tally_wasp() -> Image.Image:
    img, d = A._cell()
    for box in ((180, 280, 480, 470), (544, 280, 844, 470)):
        A._ellipse(d, box, PRIM)
    A._ellipse(d, (400, 400, 624, 900), PRIM)
    for k in range(3):
        d.rectangle((395, 520 + k * 110, 629, 565 + k * 110), fill=INK)
    A._ellipse(d, (430, 190, 594, 380), PRIM)
    return img


# ---- «Грач» --------------------------------------------------------------------------------------------------

def rook_bomb() -> Image.Image:
    img = A.rook()
    d = ImageDraw.Draw(img)
    A._ellipse(d, (370, 760, 640, 960), SEC)   # bomb held in the claws
    d.polygon([(330, 830), (370, 860), (370, 790)], fill=INK)
    d.rectangle((500, 770, 520, 950), fill=INK)
    return img


def feather_dagger() -> Image.Image:
    img, d = A._cell()
    blade = [(512, 70), (610, 260), (600, 620), (424, 620), (414, 260)]
    A._poly(d, blade, PRIM)
    for k in range(7):   # barbs: the blade is a feather
        y = 200 + k * 60
        d.line([(512, y + 40), (612, y - 10)], fill=INK, width=12)
        d.line([(512, y + 40), (412, y - 10)], fill=INK, width=12)
    d.line([(512, 120), (512, 620)], fill=INK, width=20)
    A._poly(d, [(300, 620), (724, 620), (724, 690), (300, 690)], SEC)
    A._poly(d, [(470, 690), (554, 690), (554, 900), (470, 900)], SEC)
    A._ellipse(d, (440, 880, 584, 1000), PRIM)
    return img


def horseshoe() -> Image.Image:
    img, d = A._cell()
    d.ellipse((150, 120, 874, 844), fill=INK)
    d.ellipse((190, 160, 834, 804), fill=PRIM)
    d.ellipse((330, 300, 694, 664), fill=INK)
    d.ellipse((370, 340, 654, 624), fill=CLEAR)
    d.rectangle((300, 560, 724, 980), fill=CLEAR)
    for sx in (-1, 1):
        x = 512 + sx * 260
        d.rounded_rectangle((x - 110, 520, x + 110, 900), 40, fill=INK)
        d.rounded_rectangle((x - 70, 520, x + 70, 860), 30, fill=PRIM)
    for a in range(7):   # nail holes
        ang = math.pi * (0.95 + a * 0.185)
        x, y = 512 + 290 * math.cos(ang), 482 + 290 * math.sin(ang)
        d.ellipse((x - 26, y - 26, x + 26, y + 26), fill=SEC)
    return img


def sledgehammer() -> Image.Image:
    img, d = A._cell()
    ang = math.radians(-35)
    A._poly(d, A._rot([(480, 380), (544, 380), (544, 960), (480, 960)], ang, 512, 600), SEC)
    head = [(300, 180), (724, 180), (724, 420), (300, 420)]
    A._poly(d, A._rot(head, ang, 512, 600), PRIM)
    d.polygon(A._rot([(300, 240), (724, 240), (724, 270), (300, 270)], ang, 512, 600), fill=INK)
    return img


def raven_skull() -> Image.Image:
    img, d = A._cell()
    A._skull(d, 512, 650, 0.72)
    bird = [(250, 360), (400, 250), (560, 240), (700, 280), (800, 230), (760, 330), (650, 380), (420, 400)]
    A._poly(d, bird, INK, outline=False)
    d.polygon([(780, 250), (950, 280), (790, 310)], fill=PRIM)
    d.ellipse((690, 255, 730, 295), fill=SEC)
    d.polygon([(260, 360), (90, 420), (120, 470), (300, 400)], fill=INK)
    return img


def wolf_jaw() -> Image.Image:
    img, d = A._cell()
    jaw = [(80, 330), (940, 380), (900, 640), (520, 860), (120, 700)]
    A._poly(d, jaw, SEC)
    for k in range(7):   # fangs, two long ones in front
        x = 140 + k * 110
        ln = 210 if k in (0, 6) else 130
        d.polygon([(x, 350 + k * 6), (x + 90, 355 + k * 6), (x + 45, 350 + ln + k * 6)], fill=PRIM)
        d.polygon([(x + 20, 770 - k * 25), (x + 100, 750 - k * 25), (x + 55, 650 - k * 25 - (60 if k == 0 else 0))],
                  fill=PRIM)
    d.ellipse((800, 230, 900, 320), fill=INK)
    d.ellipse((830, 250, 860, 280), fill=PRIM)
    return img


def wrench_bolt() -> Image.Image:
    img, d = A._cell()
    ang = math.radians(40)
    A._poly(d, A._rot([(470, 200), (554, 200), (554, 900), (470, 900)], ang, 512, 512), SEC)
    for end in (190, 910):
        cx, cy = A._rot([(512, end)], ang, 512, 512)[0]
        A._ellipse(d, (cx - 110, cy - 110, cx + 110, cy + 110), SEC)
        d.polygon(A._rot([(477, end - 130 if end < 500 else end + 130), (547, end - 130 if end < 500 else end + 130),
                          (547, end), (477, end)], ang, 512, 512), fill=CLEAR)
    A._poly(d, [(590, 110), (330, 540), (500, 540), (420, 920), (720, 420), (545, 420), (650, 110)], PRIM)
    return img


def tank_reticle() -> Image.Image:
    img = A.tally_ground()
    d = ImageDraw.Draw(img)
    for r in (470, 440):
        d.arc((512 - r, 560 - r, 512 + r, 560 + r), 0, 360, fill=INK if r == 470 else SEC, width=30)
    for a in range(4):
        x, y = math.cos(a * math.pi / 2 + 0.785), math.sin(a * math.pi / 2 + 0.785)
        d.line([(512 + x * 380, 560 + y * 380), (512 + x * 500, 560 + y * 500)], fill=SEC, width=40)
    return img


def jester() -> Image.Image:
    img, d = A._cell()
    d.rounded_rectangle((220 - A.OUT_W, 90 - A.OUT_W, 804 + A.OUT_W, 934 + A.OUT_W), 70, fill=INK)
    d.rounded_rectangle((220, 90, 804, 934), 50, fill=PRIM)
    for k, (tx, ty) in enumerate(((330, 300), (512, 220), (694, 300))):   # three-horned cap
        A._poly(d, [(400, 560), (tx, ty), (624, 560)], SEC if k != 1 else PRIM)
        A._ellipse(d, (tx - 50, ty - 50, tx + 50, ty + 50), SEC)
    A._ellipse(d, (400, 520, 624, 760), PRIM)
    d.ellipse((450, 590, 490, 640), fill=INK)
    d.ellipse((534, 590, 574, 640), fill=INK)
    d.arc((440, 620, 584, 730), 10, 170, fill=INK, width=20)
    return img


def hourglass() -> Image.Image:
    img, d = A._cell()
    for y in (120, 840):
        A._poly(d, [(250, y), (774, y), (774, y + 70), (250, y + 70)], SEC)
    glass = [(320, 190), (704, 190), (550, 512), (704, 840), (320, 840), (474, 512)]
    A._poly(d, glass, PRIM)
    d.polygon([(390, 260), (634, 260), (540, 450), (484, 450)], fill=SEC)   # sand on top
    d.polygon([(512, 540), (660, 820), (364, 820)], fill=SEC)                # and below
    d.line([(512, 450), (512, 760)], fill=SEC, width=14)
    return img


# ---- «Кит» ---------------------------------------------------------------------------------------------------

def whale_bomb() -> Image.Image:
    img = A.whale()
    d = ImageDraw.Draw(img)
    A._ellipse(d, (420, 700, 700, 900), SEC)
    d.polygon([(700, 800), (780, 740), (780, 860)], fill=INK)
    d.rectangle((560, 700, 580, 900), fill=INK)
    return img


def spout() -> Image.Image:
    img, d = A._cell()
    for k, fill in enumerate((SEC, PRIM, SEC)):
        x0 = 330 + k * 180
        _line(d, [(512, 880), (512 + (k - 1) * 90, 520), (x0, 240)], fill, 70)
    for x, y in ((230, 230), (512, 150), (800, 230), (330, 380), (700, 380)):
        A._ellipse(d, (x - 55, y - 75, x + 55, y + 55), PRIM)
    return img


def anchor() -> Image.Image:
    img, d = A._cell()
    d.ellipse((422, 80, 602, 260), fill=INK)
    d.ellipse((462, 120, 562, 220), fill=CLEAR)
    d.arc((432, 90, 592, 250), 0, 360, fill=SEC, width=24)
    A._poly(d, [(470, 250), (554, 250), (554, 880), (470, 880)], PRIM)
    A._poly(d, [(300, 330), (724, 330), (724, 400), (300, 400)], PRIM)
    d.arc((160, 380, 864, 940), 20, 160, fill=INK, width=110)
    d.arc((180, 400, 844, 920), 22, 158, fill=PRIM, width=70)
    for sx in (-1, 1):
        x = 512 + sx * 320
        A._poly(d, [(x - sx * 10, 600), (x + sx * 90, 560), (x + sx * 40, 700)], PRIM)
    return img


def wave() -> Image.Image:
    img, d = A._cell()
    crest = [(80, 840), (120, 560), (250, 330), (450, 220), (650, 240), (780, 340), (720, 420), (600, 380),
             (520, 430), (560, 560), (700, 640), (940, 640), (940, 840)]
    A._poly(d, crest, PRIM)
    d.polygon([(120, 840), (200, 620), (330, 500), (430, 600), (560, 700), (900, 720), (900, 840)], fill=SEC)
    for k in range(4):
        x = 600 + k * 80
        d.ellipse((x, 250 + k * 20, x + 50, 300 + k * 20), fill=PRIM)
    return img


def compass_rose() -> Image.Image:
    img, d = A._cell()
    d.ellipse((140, 140, 884, 884), fill=INK)
    d.ellipse((180, 180, 844, 844), fill=CLEAR)
    d.arc((170, 170, 854, 854), 0, 360, fill=SEC, width=30)
    for a in range(8):   # eight thin needles, two lengths
        ang = a * math.pi / 4
        r = 420 if a % 2 == 0 else 280
        tip = (512 + r * math.cos(ang), 512 + r * math.sin(ang))
        l = (512 + 70 * math.cos(ang - 0.785), 512 + 70 * math.sin(ang - 0.785))
        rr = (512 + 70 * math.cos(ang + 0.785), 512 + 70 * math.sin(ang + 0.785))
        A._poly(d, [l, tip, rr, (512, 512)], PRIM if a % 2 == 0 else SEC)
    d.ellipse((472, 472, 552, 552), fill=INK)
    return img


def lighthouse() -> Image.Image:
    img, d = A._cell()
    for sx in (-1, 1):   # beams
        d.polygon([(512, 260), (512 + sx * 480, 120), (512 + sx * 480, 330)], fill=SEC)
    tower = [(420, 330), (604, 330), (680, 900), (344, 900)]
    A._poly(d, tower, PRIM)
    for y in (460, 640):
        d.polygon([(405, y), (619, y), (630, y + 70), (394, y + 70)], fill=INK)
    A._poly(d, [(400, 200), (624, 200), (624, 330), (400, 330)], SEC)
    A._poly(d, [(380, 200), (512, 90), (644, 200)], PRIM)
    A._poly(d, [(200, 890), (824, 890), (824, 960), (200, 960)], SEC)
    return img


def bomb_bow() -> Image.Image:
    img = A.tally_bomb()
    d = ImageDraw.Draw(img)
    for sx in (-1, 1):
        A._poly(d, [(512, 360), (512 + sx * 260, 220), (512 + sx * 260, 480)], SEC)
    A._ellipse(d, (452, 300, 572, 420), SEC)
    for sx in (-1, 1):
        A._poly(d, [(512 + sx * 20, 400), (512 + sx * 150, 640), (512 + sx * 60, 620)], SEC)
    return img


def owl() -> Image.Image:
    img, d = A._cell()
    A._ellipse(d, (230, 200, 794, 900), PRIM)
    for sx in (-1, 1):   # ear tufts
        A._poly(d, [(512 + sx * 140, 260), (512 + sx * 280, 90), (512 + sx * 260, 330)], PRIM)
    for sx in (-1, 1):
        x = 512 + sx * 125
        d.ellipse((x - 120, 300, x + 120, 540), fill=INK)
        d.ellipse((x - 95, 325, x + 95, 515), fill=SEC)
        d.ellipse((x - 45, 375, x + 45, 465), fill=INK)
    d.polygon([(470, 520), (554, 520), (512, 620)], fill=SEC)
    for k in range(3):   # belly feathers
        y = 680 + k * 60
        for i in range(-2, 3):
            d.arc((482 + i * 80 - 40, y - 30, 482 + i * 80 + 40, y + 30), 20, 160, fill=INK, width=14)
    return img


def bear() -> Image.Image:
    img, d = A._cell()
    for sx in (-1, 1):
        A._ellipse(d, (512 + sx * 230 - 100, 160, 512 + sx * 230 + 100, 360), PRIM)
        d.ellipse((512 + sx * 230 - 50, 210, 512 + sx * 230 + 50, 310), fill=SEC)
    A._ellipse(d, (200, 220, 824, 860), PRIM)
    A._ellipse(d, (380, 520, 644, 760), SEC)
    d.ellipse((470, 540, 554, 610), fill=INK)
    for sx in (-1, 1):   # stern brows: a heavyweight
        x = 512 + sx * 130
        d.ellipse((x - 35, 430, x + 35, 500), fill=INK)
        d.line([(x - sx * 70, 380), (x + sx * 70, 410)], fill=INK, width=26)
    d.arc((450, 600, 574, 720), 200, 340, fill=INK, width=18)
    return img


def turtle() -> Image.Image:
    img, d = A._cell()
    A._ellipse(d, (440, 100, 584, 260), SEC)   # head
    for x, y in ((280, 330), (744, 330), (290, 750), (734, 750)):
        A._ellipse(d, (x - 80, y - 60, x + 80, y + 60), SEC)
    A._ellipse(d, (250, 220, 774, 870), PRIM)
    cx, cy, r = 512, 545, 120   # armour plates
    for ox, oy in ((0, 0), (0, -200), (0, 200), (-170, -100), (170, -100), (-170, 100), (170, 100)):
        hexa = [(cx + ox + r * math.cos(k * math.pi / 3), cy + oy + r * 0.9 * math.sin(k * math.pi / 3))
                for k in range(6)]
        d.polygon(hexa, outline=INK, width=20)
    return img


# ---- «Хулиганский ящик»: gamer jokes -------------------------------------------------------------------------

def key_f() -> Image.Image:
    img, d = A._cell()
    d.rounded_rectangle((170 - A.OUT_W, 170 - A.OUT_W, 854 + A.OUT_W, 900 + A.OUT_W), 90, fill=INK)
    d.rounded_rectangle((170, 170, 854, 900), 70, fill=SEC)
    d.rounded_rectangle((230, 200, 794, 780), 50, fill=PRIM)
    d.text((512, 480), "F", font=_font(520), fill=INK, anchor="mm")
    return img


def gg() -> Image.Image:
    img, d = A._cell()
    A._poly(d, _star_pts(512, 512, 330, 470, 12, 0.13), SEC)
    d.text((512, 520), "GG", font=_font(380), fill=PRIM, anchor="mm", stroke_width=A.OUT_W, stroke_fill=INK)
    return img


def three_am() -> Image.Image:
    img, d = A._cell()
    for sx in (-1, 1):   # alarm bells
        A._ellipse(d, (512 + sx * 260 - 110, 90, 512 + sx * 260 + 110, 290), SEC)
    A._ellipse(d, (150, 170, 874, 894), PRIM)
    for h in range(12):
        a = h * math.pi / 6
        d.line([(512 + 300 * math.cos(a), 532 + 300 * math.sin(a)), (512 + 340 * math.cos(a), 532 + 340 * math.sin(a))],
               fill=INK, width=22)
    d.line([(512, 532), (712, 532)], fill=INK, width=44)   # three o'clock, small hand
    d.line([(512, 532), (512, 250)], fill=INK, width=28)   # and the big one on twelve
    d.ellipse((482, 502, 542, 562), fill=SEC)
    return img


def pixel_shades() -> Image.Image:
    img, d = A._cell()
    px = 64
    rows = ["XXXXXXXXXXXXXXX", "XXWWXXXXXXWWXXX", "XWWXXX.XXWWXXX.", ".XXXX...XXXXX..", "..XX.....XXX..."]
    x0, y0 = 512 - len(rows[0]) * px // 2, 360
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            box = (x0 + c * px, y0 + r * px, x0 + (c + 1) * px, y0 + (r + 1) * px)
            d.rectangle(box, fill=INK if ch == "X" else PRIM)
    return img


def bug_feature() -> Image.Image:
    img, d = A._cell()
    for sx in (-1, 1):
        for k in range(3):
            y = 460 + k * 130
            d.line([(512 + sx * 120, y), (512 + sx * 300, y - 40 + k * 40), (512 + sx * 360, y + 40)], fill=INK, width=24)
    A._ellipse(d, (330, 330, 694, 860), PRIM)
    d.line([(512, 360), (512, 850)], fill=INK, width=18)
    for x, y in ((430, 520), (600, 600), (450, 720), (590, 770)):
        d.ellipse((x - 30, y - 30, x + 30, y + 30), fill=INK)
    A._ellipse(d, (420, 220, 604, 380), PRIM)
    A._poly(d, [(430, 250), (512, 40), (594, 250)], SEC)   # party hat: it is a feature
    A._poly(d, _star_pts(800, 220, 40, 110, 8), SEC)
    A._poly(d, _star_pts(220, 260, 30, 80, 8, 0.3), SEC)
    return img


def dumbbell_wings() -> Image.Image:
    img, d = A._cell()
    for sx in (-1, 1):
        for k in range(3):
            y = 360 + k * 60
            tip = (512 + sx * (480 - k * 60), y - 140 + k * 40)
            A._poly(d, [(512 + sx * 60, y), tip, (tip[0] - sx * 40, y + 50), (512 + sx * 60, y + 60)], SEC)
    A._poly(d, [(300, 600), (724, 600), (724, 660), (300, 660)], PRIM)
    for sx in (-1, 1):
        A._poly(d, [(512 + sx * 200, 470), (512 + sx * 290, 470), (512 + sx * 290, 790), (512 + sx * 200, 790)], PRIM)
        A._poly(d, [(512 + sx * 300, 520), (512 + sx * 360, 520), (512 + sx * 360, 740), (512 + sx * 300, 740)], PRIM)
    return img


def snail_ping() -> Image.Image:
    img, d = A._cell()
    A._poly(d, [(100, 840), (180, 730), (760, 730), (900, 650), (950, 700), (880, 840)], SEC)   # foot
    A._ellipse(d, (180, 330, 640, 790), PRIM)
    spiral = [(410 + 200 * (1 - t / 40) * math.cos(t * 0.42), 560 + 200 * (1 - t / 40) * math.sin(t * 0.42))
              for t in range(0, 36)]   # a real spiral, so the shell never reads as a © sign
    d.line(spiral, fill=INK, width=24, joint="curve")
    for x in (830, 900):   # eye stalks, one is an antenna
        d.line([(860, 700), (x, 520)], fill=INK, width=22)
    d.ellipse((800, 490, 860, 550), fill=INK)
    for r in (80, 140, 200):
        d.arc((900 - r, 520 - r, 900 + r, 520 + r), 280, 350, fill=SEC, width=20)
    return img


def loading_bar() -> Image.Image:
    img, d = A._cell()
    d.rounded_rectangle((100 - A.OUT_W, 400 - A.OUT_W, 924 + A.OUT_W, 624 + A.OUT_W), 60, fill=INK)
    d.rounded_rectangle((100, 400, 924, 624), 40, fill=SEC)
    d.rounded_rectangle((140, 440, 860, 584), 25, fill=PRIM)   # 99 %: one sliver left
    for k in range(4):
        x = 200 + k * 170
        d.polygon([(x, 440), (x + 70, 440), (x - 10, 584), (x - 80, 584)], fill=SEC)
    return img


def afk_zzz() -> Image.Image:
    img, d = A._cell()
    A._ellipse(d, (100, 420, 600, 920), PRIM)   # a sleeping face
    d.chord((100, 420, 600, 920), 180, 360, fill=SEC)
    d.rectangle((100, 640, 600, 690), fill=CLEAR)
    d.arc((190, 640, 330, 740), 0, 180, fill=INK, width=22)
    d.arc((370, 640, 510, 740), 0, 180, fill=INK, width=22)
    d.ellipse((310, 800, 390, 860), fill=INK)
    for k, (x, y, s) in enumerate(((620, 380, 220), (760, 220, 170), (870, 100, 120))):
        d.text((x, y), "Z", font=_font(s), fill=PRIM, anchor="mm", stroke_width=A.OUT_W // 2, stroke_fill=INK)
    return img


def pixel_heart() -> Image.Image:
    img, d = A._cell()
    rows = [".XX...XX.", "XPPX.XPPX", "XPWPXPPPX", "XPPPPPPPX", ".XPPPPPX.", "..XPPPX..", "...XPX...", "....X...."]
    px = 100
    x0, y0 = 512 - 9 * px // 2, 512 - 8 * px // 2 - 40
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch != ".":
                d.rectangle((x0 + c * px, y0 + r * px, x0 + (c + 1) * px, y0 + (r + 1) * px),
                            fill={"X": INK, "P": SEC, "W": PRIM}[ch])
    d.text((840, 860), "+1", font=_font(260), fill=PRIM, anchor="mm", stroke_width=A.OUT_W // 2, stroke_fill=INK)
    return img


# ---- «Хулиганский ящик»: internet and animals ----------------------------------------------------------------

def capybara() -> Image.Image:
    img, d = A._cell()
    # side view, facing right: the long blunt box of a head on a round body, goggles up on the forehead
    A._ellipse(d, (90, 420, 640, 900), PRIM)   # body
    head = [(380, 330), (720, 300), (880, 360), (940, 470), (930, 600), (860, 660), (560, 680), (420, 600)]
    A._poly(d, head, PRIM)
    A._ellipse(d, (430, 250, 530, 350), PRIM)   # small round ear
    d.ellipse((455, 275, 505, 325), fill=SEC)
    d.ellipse((700, 400, 750, 450), fill=INK)   # sleepy calm eye
    d.line([(690, 395), (760, 400)], fill=INK, width=18)
    d.ellipse((890, 470, 925, 505), fill=INK)   # nostril
    d.line([(860, 590), (920, 575)], fill=INK, width=14)
    for x in (200, 470):   # short legs
        d.rounded_rectangle((x - 50, 820, x + 50, 960), 30, fill=INK)
        d.rounded_rectangle((x - 30, 820, x + 30, 940), 20, fill=PRIM)
    d.rectangle((560, 330, 850, 365), fill=INK)   # goggles strap and lenses on the forehead
    for x in (640, 790):
        d.ellipse((x - 70, 270, x + 70, 400), fill=INK)
        d.ellipse((x - 48, 292, x + 48, 378), fill=SEC)
        d.ellipse((x - 30, 300, x - 5, 325), fill=PRIM)
    return img


def goose_wrench() -> Image.Image:
    img, d = A._cell()
    neck = [(380, 860), (330, 560), (360, 330), (430, 200), (560, 170), (640, 240), (600, 300), (500, 300),
            (470, 420), (520, 640), (600, 860)]
    A._poly(d, neck, PRIM)
    A._poly(d, [(620, 230), (860, 270), (630, 310)], SEC)   # beak holding a wrench
    d.ellipse((520, 215, 565, 260), fill=INK)
    d.line([(530, 200), (600, 190)], fill=INK, width=20)   # angry brow
    ang = math.radians(-10)
    A._poly(d, A._rot([(720, 250), (980, 250), (980, 300), (720, 300)], ang, 760, 275), SEC)
    A._ellipse(d, (920, 220, 1010, 330), SEC)
    return img


def rubber_duck() -> Image.Image:
    img, d = A._cell()
    A._ellipse(d, (130, 480, 870, 900), PRIM)
    A._ellipse(d, (400, 170, 780, 550), PRIM)
    A._poly(d, [(740, 360), (960, 380), (930, 440), (740, 450)], SEC)
    d.ellipse((620, 280, 680, 340), fill=INK)
    d.ellipse((635, 290, 655, 310), fill=PRIM)
    d.arc((260, 560, 600, 800), 200, 330, fill=INK, width=22)   # wing
    return img


def cute_bomb() -> Image.Image:
    img = A.tally_bomb()
    d = ImageDraw.Draw(img)
    for sx in (-1, 1):
        x = 512 + sx * 70
        d.ellipse((x - 40, 450, x + 40, 560), fill=INK)
        d.ellipse((x - 20, 465, x + 5, 495), fill=PRIM)
    d.arc((450, 540, 574, 640), 20, 160, fill=INK, width=18)
    for sx in (-1, 1):   # bow on top
        A._poly(d, [(512, 200), (512 + sx * 170, 110), (512 + sx * 170, 290)], SEC)
    A._ellipse(d, (467, 155, 557, 245), SEC)
    return img


def baguette() -> Image.Image:
    img, d = A._cell()
    ang = math.radians(-30)
    loaf = [(140, 440), (820, 440), (900, 512), (820, 584), (140, 584), (100, 512)]
    A._poly(d, A._rot(loaf, ang, 512, 512), PRIM)
    for k in range(5):
        x = 240 + k * 130
        d.line(A._rot([(x, 470), (x + 70, 555)], ang, 512, 512), fill=SEC, width=26)
    for sx in (-1, 1):   # missile fins
        d.polygon(A._rot([(150, 512 + sx * 72), (260, 512 + sx * 72), (100, 512 + sx * 200)], ang, 512, 512), fill=INK)
    return img


def arrow_gear() -> Image.Image:
    img, d = A._cell()
    for k in range(10):   # gear
        a = k * math.tau / 10
        cx, cy = 330 + 230 * math.cos(a), 690 + 230 * math.sin(a)
        A._ellipse(d, (cx - 60, cy - 60, cx + 60, cy + 60), SEC)
    A._ellipse(d, (130, 490, 530, 890), SEC)
    d.ellipse((260, 620, 400, 760), fill=INK)
    pts = [(200, 760), (420, 520), (560, 620), (780, 330), (700, 290), (900, 140), (880, 380), (830, 330),
           (580, 700), (440, 600), (260, 820)]
    A._poly(d, pts, PRIM)
    return img


def grumpy_navigator() -> Image.Image:
    img = A.cat()
    d = ImageDraw.Draw(img)
    for sx in (-1, 1):   # angry brows over the eyes
        x = 512 + sx * 120
        d.polygon([(x - sx * 110, 430), (x + sx * 90, 480), (x + sx * 90, 510), (x - sx * 110, 470)], fill=INK)
    d.arc((200, 200, 824, 820), 200, 340, fill=SEC, width=40)   # headset band
    for sx in (-1, 1):
        A._ellipse(d, (512 + sx * 300 - 70, 480, 512 + sx * 300 + 70, 640), SEC)
    _line(d, [(800, 600), (760, 760), (640, 800)], SEC, 22)   # microphone
    return img


def fine_smile() -> Image.Image:
    img, d = A._cell()
    for k in range(9):   # fire all round
        a = math.pi * (0.95 + k * 0.14)
        r0, r1 = 300, 470 + (k % 2) * 40
        A._poly(d, [(512 + r0 * math.cos(a - 0.18), 560 + r0 * math.sin(a - 0.18)),
                    (512 + r1 * math.cos(a), 560 + r1 * math.sin(a)),
                    (512 + r0 * math.cos(a + 0.18), 560 + r0 * math.sin(a + 0.18))], SEC)
    A._ellipse(d, (232, 280, 792, 840), PRIM)
    for sx in (-1, 1):
        x = 512 + sx * 110
        d.ellipse((x - 35, 450, x + 35, 540), fill=INK)
    d.arc((340, 470, 684, 740), 20, 160, fill=INK, width=30)
    A._ellipse(d, (640, 380, 700, 460), SEC)   # one drop of sweat
    return img


def bang() -> Image.Image:
    img, d = A._cell()
    A._poly(d, _star_pts(512, 512, 260, 480, 11, 0.2), SEC)
    A._poly(d, _star_pts(512, 512, 150, 300, 9, 0.5), PRIM)
    return img


def no_feed_whale() -> Image.Image:
    img, d = A._cell()
    d.rounded_rectangle((120 - A.OUT_W, 160 - A.OUT_W, 904 + A.OUT_W, 760 + A.OUT_W), 50, fill=INK)
    d.rounded_rectangle((120, 160, 904, 760), 35, fill=PRIM)
    A._poly(d, [(470, 760), (554, 760), (554, 960), (470, 960)], PRIM)
    fish = [(300, 460), (420, 360), (620, 380), (700, 460), (620, 540), (420, 560)]
    d.polygon(fish, fill=SEC)
    d.polygon([(700, 460), (790, 380), (790, 540)], fill=SEC)
    d.ellipse((380, 425, 420, 465), fill=INK)
    d.ellipse((260, 230, 764, 690), outline=INK, width=46)   # the «no» ring and bar
    d.line([(330, 300), (694, 620)], fill=INK, width=46)
    return img


EDITIONS = [
    ("wasp_missile", wasp_missile), ("honeycomb", honeycomb), ("sting_arrow", sting_arrow),
    ("winged_bolt", winged_bolt), ("wasp_ace", wasp_ace), ("reticle", reticle), ("swallow", swallow),
    ("daredevil", daredevil), ("nose_flames", nose_flames), ("tally_wasp", tally_wasp),
    ("rook_bomb", rook_bomb), ("feather_dagger", feather_dagger), ("horseshoe", horseshoe),
    ("sledgehammer", sledgehammer), ("raven_skull", raven_skull), ("wolf_jaw", wolf_jaw),
    ("wrench_bolt", wrench_bolt), ("tank_reticle", tank_reticle), ("jester", jester), ("hourglass", hourglass),
    ("whale_bomb", whale_bomb), ("spout", spout), ("anchor", anchor), ("wave", wave),
    ("compass_rose", compass_rose), ("lighthouse", lighthouse), ("bomb_bow", bomb_bow), ("owl", owl),
    ("bear", bear), ("turtle", turtle),
    ("key_f", key_f), ("gg", gg), ("three_am", three_am), ("pixel_shades", pixel_shades),
    ("bug_feature", bug_feature), ("dumbbell_wings", dumbbell_wings), ("snail_ping", snail_ping),
    ("loading_bar", loading_bar), ("afk_zzz", afk_zzz), ("pixel_heart", pixel_heart),
    ("capybara", capybara), ("goose_wrench", goose_wrench), ("rubber_duck", rubber_duck),
    ("cute_bomb", cute_bomb), ("baguette", baguette), ("arrow_gear", arrow_gear),
    ("grumpy_navigator", grumpy_navigator), ("fine_smile", fine_smile), ("bang", bang),
    ("no_feed_whale", no_feed_whale),
]
