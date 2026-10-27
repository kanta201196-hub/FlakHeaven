#!/usr/bin/env python3
"""Draws the medal pictures of «Наградная планка» (Kanta 2026-10-27) as vector SVGs.

One emblem per medal on one of five frames (round medal on a ribbon, gear-edged patch, shield, class badge,
story order), in each metal the medal can reach plus a grey «not earned» copy:
game/art/medals/<id>_<metal>.svg. The medal list and its tiers live in game/scripts/balance/medals.gd; this
script reads ids, frames and tier counts from there so the two cannot drift apart.
Fictional world: no real orders, stars, flags or insignia.

Run from the repository root: python3 tools/medals/make_medals.py  (then Godot imports the SVGs).
"""
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "art", "medals")
BALANCE = os.path.join(ROOT, "game", "scripts", "balance", "medals.gd")

METALS = {
    # light, mid, dark, engraving
    "bronze": ("#f2c08a", "#c27a3e", "#6e3a14", "#4a250b"),
    "silver": ("#ffffff", "#c3ccd6", "#6b7684", "#3a414b"),
    "gold": ("#fff3b0", "#e9b93a", "#8a5a08", "#5a3a04"),
    "banner": ("#fff3b0", "#e9b93a", "#8a5a08", "#5a1010"),
    "none": ("#d0d0d0", "#8f8f8f", "#4c4c4c", "#3a3a3a"),
}
# ribbon stripes by group (outer, inner, centre)
RIBBONS = {
    "combat": ("#7a1c1c", "#d9c27a", "#7a1c1c"),
    "survive": ("#1f4f7a", "#e8e8e8", "#1f4f7a"),
    "economy": ("#3e5a24", "#d9a441", "#3e5a24"),
    "class": ("#2a2a2a", "#d9c27a", "#2a2a2a"),
    "hidden": ("#4a2a5a", "#c9b0d9", "#4a2a5a"),
}
CLOTH = {"combat": "#4a4f2a", "survive": "#23384f", "economy": "#3a3a2a", "class": "#2a2a33", "hidden": "#3a2a40"}


def read_medals():
    """Medal id, group, frame and tier count from the GDScript list (one dict per line group)."""
    src = open(BALANCE, encoding="utf-8").read()
    body = src[src.index("const LIST := ["):src.index("## Caps over all medals")]
    out = []
    for m in re.finditer(r'\{"id": "([a-z_]+)", "g": "([a-z]+)", "f": "([a-z]+)".*?"t": \[([^\]]*)\]', body, re.S):
        out.append({"id": m.group(1), "g": m.group(2), "f": m.group(3), "n": len(m.group(4).split(","))})
    return out


# ---------- emblems: drawn in a 100×100 box centred at (50, 50), engraving colour `c`, highlight `h` ----------

def plane(x, y, s, ang, c, extra=""):
    """A generic straight-wing fighter seen from above, nose up before rotation."""
    return (f'<g transform="translate({x} {y}) rotate({ang}) scale({s})" fill="{c}" {extra}>'
            '<path d="M0,-30 L4,-20 L4,-6 L28,4 L28,9 L4,6 L3,20 L11,26 L11,30 L0,27 L-11,30 L-11,26 L-3,20 L-4,6 '
            'L-28,9 L-28,4 L-4,-6 L-4,-20 Z"/></g>')


def wings(c, y=50, span=46):
    pts = []
    for side in (-1, 1):
        d = (f"M{50 + side * 6},{y} C{50 + side * 20},{y - 14} {50 + side * 34},{y - 16} {50 + side * span},{y - 22} "
             f"C{50 + side * 38},{y - 8} {50 + side * 30},{y - 4} {50 + side * 24},{y - 2} "
             f"C{50 + side * 30},{y + 2} {50 + side * 22},{y + 6} {50 + side * 6},{y + 6} Z")
        pts.append(f'<path d="{d}" fill="{c}"/>')
        for k in range(3):
            yy = y - 6 - k * 4
            pts.append(f'<path d="M{50 + side * (14 + k * 6)},{yy + 4} L{50 + side * (30 + k * 5)},{yy - 4}" '
                       f'stroke="{c}" stroke-width="1.6" opacity="0.5"/>')
    return "".join(pts)


def star_burst(cx, cy, r1, r2, n, c, rot=0):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append(f"{cx + r * math.sin(a):.1f},{cy - r * math.cos(a):.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{c}"/>'


def ring(cx, cy, r, c, w=3):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{c}" stroke-width="{w}"/>'


def missile(x, y, ang, c, s=1.0):
    return (f'<g transform="translate({x} {y}) rotate({ang}) scale({s})" fill="{c}">'
            '<path d="M0,-26 L4,-18 L4,16 L9,24 L4,22 L0,26 L-4,22 L-9,24 L-4,16 L-4,-18 Z"/></g>')


def gear(cx, cy, r, teeth, c, hole="#0000", tw=0.35):
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4)
        rr = r if (i % 4) in (1, 2) else r * (1 - tw * 0.5)
        pts.append(f"{cx + rr * math.cos(a):.1f},{cy + rr * math.sin(a):.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{c}"/><circle cx="{cx}" cy="{cy}" r="{r * 0.35:.1f}" fill="{hole}"/>'


def wrench(x, y, ang, c, s=1.0):
    return (f'<g transform="translate({x} {y}) rotate({ang}) scale({s})" fill="{c}">'
            '<path d="M-4,-14 L-4,26 Q0,30 4,26 L4,-14 Q12,-18 12,-28 L6,-24 L0,-28 L-6,-24 L-12,-28 Q-12,-18 -4,-14 Z"/></g>')


def emblem(mid, c, h):
    """The picture inside the frame for medal `mid`."""
    E = {
        "fighter": lambda: wings(c, 58) + f'<g stroke="{c}" stroke-width="5" stroke-linecap="round">'
        '<path d="M30,28 L70,64"/><path d="M70,28 L30,64"/></g>' + f'<circle cx="50" cy="46" r="7" fill="{h}" stroke="{c}" stroke-width="3"/>',
        "ace_hunter": lambda: ring(50, 50, 30, c, 3) + ring(50, 50, 19, c, 3) + ring(50, 50, 8, c, 3)
        + f'<path d="M24,62 L50,40 L76,62 L76,72 L50,52 L24,72 Z" fill="{c}"/>',
        "fortress_fall": lambda: plane(52, 44, 1.25, 140, c) + f'<path d="M38,58 Q24,70 18,86" stroke="{c}" stroke-width="6" '
        'fill="none" stroke-linecap="round" opacity="0.7"/>' + star_burst(40, 56, 11, 5, 7, h),
        "stormer": lambda: f'<rect x="24" y="58" width="52" height="14" rx="6" fill="{c}"/><rect x="34" y="48" width="26" height="12" rx="3" fill="{c}"/>'
        f'<path d="M58,52 L80,46" stroke="{c}" stroke-width="5"/>' + f'<path d="M50,14 L50,38 M42,30 L50,40 L58,30" stroke="{c}" stroke-width="5" fill="none" stroke-linecap="round"/>',
        "demolition": lambda: star_burst(50, 52, 36, 18, 10, c) + star_burst(50, 52, 20, 10, 8, h, 20)
        + f'<ellipse cx="50" cy="52" rx="7" ry="11" fill="{c}"/>',
        "marksman": lambda: ring(50, 50, 28, c, 4) + f'<g stroke="{c}" stroke-width="4" stroke-linecap="round">'
        '<path d="M50,14 L50,36"/><path d="M50,64 L50,86"/><path d="M14,50 L36,50"/><path d="M64,50 L86,50"/></g>'
        + f'<circle cx="50" cy="50" r="4" fill="{c}"/>',
        "on_tail": lambda: plane(50, 34, 0.9, 0, c) + ring(50, 66, 16, c, 3) + f'<path d="M50,52 L50,80 M36,66 L64,66" stroke="{c}" stroke-width="3"/>',
        "rocketeer": lambda: missile(38, 50, -30, c) + missile(62, 50, 30, c) + star_burst(50, 22, 8, 4, 6, h),
        "flak": lambda: f'<path d="M26,78 L74,78 L68,60 L32,60 Z" fill="{c}"/><circle cx="50" cy="58" r="12" fill="{c}"/>'
        f'<g stroke="{c}" stroke-width="5" stroke-linecap="round"><path d="M44,52 L30,20"/><path d="M56,52 L70,20"/></g>'
        + star_burst(28, 16, 6, 3, 6, h) + star_burst(72, 16, 6, 3, 6, h),
        "leader": lambda: plane(50, 34, 0.75, 0, c) + plane(28, 62, 0.6, 0, c) + plane(72, 62, 0.6, 0, c),
        "convoy": lambda: f'<rect x="18" y="50" width="40" height="20" rx="3" fill="{c}"/><path d="M58,56 L72,56 L82,64 L82,70 L58,70 Z" fill="{c}"/>'
        f'<circle cx="30" cy="74" r="6" fill="{c}"/><circle cx="70" cy="74" r="6" fill="{c}"/>'
        f'<g stroke="{h}" stroke-width="6" stroke-linecap="round"><path d="M30,20 L70,46"/><path d="M70,20 L30,46"/></g>',
        "no_retreat": lambda: f'<path d="M20,80 L20,58 L30,58 L30,64 L40,64 L40,58 L60,58 L60,64 L70,64 L70,58 L80,58 L80,80 Z" fill="{c}"/>'
        + plane(50, 34, 0.7, 180, c) + f'<path d="M14,48 L86,48" stroke="{h}" stroke-width="4" stroke-dasharray="6 4"/>',
        "umbrella": lambda: f'<path d="M14,48 Q50,4 86,48 Q77,42 68,48 Q59,42 50,48 Q41,42 32,48 Q23,42 14,48 Z" fill="{c}"/>'
        f'<path d="M50,48 L50,74 Q50,82 42,80" stroke="{c}" stroke-width="4" fill="none"/>' + missile(80, 20, 200, h, 0.5) + missile(20, 20, 160, h, 0.5),
        "fort_area": lambda: f'<path d="M30,84 L30,40 L26,40 L26,30 L34,30 L34,36 L42,36 L42,30 L58,30 L58,36 L66,36 L66,30 L74,30 L74,40 L70,40 L70,84 Z" fill="{c}"/>'
        f'<path d="M50,30 L50,8" stroke="{c}" stroke-width="3"/><path d="M50,8 L68,14 L50,20 Z" fill="{h}"/>'
        f'<rect x="44" y="60" width="12" height="24" rx="6" fill="{h}"/>',
        "tough": lambda: f'<path d="M22,84 L22,42 Q50,8 78,42 L78,84 L66,84 L66,46 Q50,24 34,46 L34,84 Z" fill="{c}"/>' + plane(50, 60, 0.7, 0, c),
        "close_call": lambda: plane(44, 52, 0.95, 0, c) + f'<path d="M66,84 L80,16" stroke="{h}" stroke-width="4" stroke-linecap="round"/>'
        f'<ellipse cx="80" cy="16" rx="3" ry="6" fill="{c}" transform="rotate(12 80 16)"/>'
        f'<g stroke="{c}" stroke-width="2" opacity="0.6"><path d="M72,70 L78,72"/><path d="M74,56 L80,58"/><path d="M76,42 L82,44"/></g>',
        "decoy": lambda: plane(50, 30, 0.7, 0, c) + "".join(
            f'<path d="M50,46 Q{50 + dx * 0.5},{62} {50 + dx},{84}" stroke="{c}" stroke-width="3" fill="none"/>'
            + star_burst(50 + dx, 84, 6, 3, 6, h) for dx in (-30, -12, 12, 30)),
        "diver": lambda: plane(50, 44, 1.0, 180, c) + f'<g stroke="{c}" stroke-width="3" opacity="0.6"><path d="M38,12 L38,24"/><path d="M50,8 L50,20"/>'
        '<path d="M62,12 L62,24"/></g>' + f'<path d="M18,84 Q50,70 82,84" stroke="{c}" stroke-width="4" fill="none"/>',
        "mechanic": lambda: gear(50, 50, 32, 10, c, h) + wrench(50, 50, 45, h, 1.0),
        "long_haul": lambda: f'<path d="M50,14 Q72,44 72,58 A22,22 0 0 1 28,58 Q28,44 50,14 Z" fill="{c}"/>'
        f'<path d="M40,60 Q50,48 60,60 Q50,72 40,60" fill="{h}"/>',
        "scrap": lambda: gear(50, 52, 24, 8, c, h) + wrench(40, 46, -40, c, 0.9) + f'<circle cx="74" cy="24" r="6" fill="{c}"/><circle cx="74" cy="24" r="2.5" fill="{h}"/>',
        "veteran": lambda: "".join(f'<ellipse cx="{50 + side * (26 - k * 2)}" cy="{78 - k * 12}" rx="5" ry="9" fill="{c}" '
                                   f'transform="rotate({side * (30 + k * 10)} {50 + side * (26 - k * 2)} {78 - k * 12})"/>'
                                   for side in (-1, 1) for k in range(5))
        + f'<g fill="{c}"><ellipse cx="50" cy="30" rx="5" ry="18"/><ellipse cx="50" cy="30" rx="5" ry="18" transform="rotate(120 50 42)"/>'
        '<ellipse cx="50" cy="30" rx="5" ry="18" transform="rotate(240 50 42)"/></g>' + f'<circle cx="50" cy="42" r="6" fill="{h}"/>',
        "quick": lambda: f'<path d="M58,10 L30,54 L48,54 L40,90 L72,40 L54,40 Z" fill="{c}"/>',
        "collector": lambda: "".join(f'<rect x="38" y="22" width="26" height="40" rx="3" fill="{c if k % 2 else h}" stroke="{c}" stroke-width="2" '
                                     f'transform="rotate({-30 + k * 20} 50 80)"/>' for k in range(4)),
        "synergy": lambda: ring(38, 50, 18, c, 6) + ring(62, 50, 18, c, 6) + f'<path d="M50,36 A18,18 0 0 1 50,64" stroke="{h}" stroke-width="2" fill="none"/>',
        "cls_fighter": lambda: f'<ellipse cx="50" cy="60" rx="9" ry="20" fill="{c}"/><circle cx="50" cy="34" r="8" fill="{c}"/>'
        f'<g fill="{h}" stroke="{c}" stroke-width="2"><ellipse cx="34" cy="44" rx="16" ry="7" transform="rotate(-25 34 44)"/>'
        '<ellipse cx="66" cy="44" rx="16" ry="7" transform="rotate(25 66 44)"/></g>'
        f'<g stroke="{h}" stroke-width="3"><path d="M42,56 L58,56"/><path d="M42,64 L58,64"/><path d="M44,72 L56,72"/></g>'
        f'<path d="M46,28 L40,16 M54,28 L60,16" stroke="{c}" stroke-width="2"/>',
        "cls_attacker": lambda: f'<path d="M28,70 Q24,40 46,30 Q60,24 70,34 L90,40 L72,46 Q74,62 60,72 Z" fill="{c}"/>'
        f'<circle cx="62" cy="38" r="4" fill="{h}"/><path d="M30,70 L22,84 M40,72 L36,86" stroke="{c}" stroke-width="3"/>',
        "cls_bomber": lambda: f'<path d="M12,56 Q20,30 52,32 Q78,34 84,50 Q90,46 94,36 Q96,52 90,58 Q80,72 50,72 Q22,72 12,56 Z" fill="{c}"/>'
        f'<circle cx="26" cy="50" r="3" fill="{h}"/><path d="M40,24 Q44,14 48,24 M44,22 L44,12" stroke="{c}" stroke-width="2" fill="none"/>',
        "op_pass": lambda: f'<path d="M8,80 L34,30 L50,54 L62,38 L92,80 Z" fill="{c}"/><path d="M50,80 Q44,68 54,60 Q62,54 56,46" stroke="{h}" stroke-width="4" fill="none"/>',
        "op_riverbed": lambda: f'<path d="M8,80 L30,46 L46,62 L66,40 L92,80 Z" fill="{c}"/>'
        f'<path d="M20,80 Q40,70 34,62 Q28,54 50,52 Q72,50 66,42" stroke="{h}" stroke-width="5" fill="none" stroke-dasharray="6 3"/>',
        "op_forts": lambda: f'<path d="M8,84 L30,52 L70,52 L92,84 Z" fill="{c}"/>'
        f'<path d="M32,54 L32,30 L38,30 L38,36 L46,36 L46,24 L54,24 L54,36 L62,36 L62,30 L68,30 L68,54 Z" fill="{c}"/>'
        f'<rect x="47" y="42" width="6" height="12" fill="{h}"/>',
        "op_sky": lambda: star_burst(50, 50, 40, 26, 12, h) + f'<circle cx="50" cy="50" r="20" fill="{c}"/>'
        f'<path d="M8,84 L32,56 L46,70 L64,52 L92,84 Z" fill="{c}"/>' + plane(50, 46, 0.45, 0, h),
        "grom": lambda: wings(c, 52, 46) + f'<path d="M56,14 L38,50 L50,50 L42,86 L66,42 L54,42 Z" fill="{h}" stroke="{c}" stroke-width="2"/>',
        "ram": lambda: plane(50, 54, 1.1, 0, c) + f'<path d="M44,22 L50,28 L56,22" stroke="{h}" stroke-width="3" fill="none"/>'
        + star_burst(50, 14, 10, 4, 7, h),
        "gun_only": lambda: f'<rect x="20" y="44" width="56" height="12" rx="3" fill="{c}"/><rect x="74" y="40" width="10" height="20" rx="2" fill="{c}"/>'
        f'<rect x="12" y="46" width="10" height="8" fill="{c}"/>' + f'<g stroke="{c}" stroke-width="3"><path d="M28,62 L28,74"/><path d="M40,62 L40,74"/><path d="M52,62 L52,74"/></g>',
        "last_breath": lambda: plane(56, 40, 0.9, 20, c) + f'<path d="M48,62 Q30,74 22,90" stroke="{c}" stroke-width="8" fill="none" opacity="0.5" stroke-linecap="round"/>'
        f'<path d="M30,34 L40,40 L34,44 Z" fill="{h}"/>',
        "carousel": lambda: f'<path d="M50,16 A34,34 0 1 1 18,40" stroke="{c}" stroke-width="7" fill="none"/>'
        f'<path d="M10,30 L22,46 L30,30 Z" fill="{c}"/>' + plane(50, 50, 0.55, 45, c),
        "clean_sky": lambda: f'<path d="M20,64 Q14,48 30,46 Q32,30 50,32 Q64,22 72,38 Q88,38 86,54 Q90,66 76,66 L28,66 Q20,68 20,64 Z" fill="{c}"/>'
        + star_burst(70, 20, 12, 3, 4, h) + star_burst(24, 26, 7, 2, 4, h),
    }
    return E[mid]()


# ---------- frames (256×256 canvas) ----------

def defs(metal):
    l, m, d, _ = METALS[metal]
    return (f'<defs><radialGradient id="mt" cx="38%" cy="32%" r="75%"><stop offset="0" stop-color="{l}"/>'
            f'<stop offset="0.55" stop-color="{m}"/><stop offset="1" stop-color="{d}"/></radialGradient>'
            f'<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{l}"/>'
            f'<stop offset="0.5" stop-color="{d}"/><stop offset="1" stop-color="{m}"/></linearGradient></defs>')


def ribbon(group, metal, bars):
    a, b, c = RIBBONS[group]
    if metal == "none":
        a, b, c = "#555", "#888", "#555"
    s = (f'<path d="M78,0 L178,0 L178,96 L128,120 L78,96 Z" fill="{a}"/>'
         f'<rect x="100" y="0" width="56" height="100" fill="{b}"/><rect x="118" y="0" width="20" height="108" fill="{c}"/>')
    for i in range(bars):
        y = 14 + i * 14
        s += f'<rect x="92" y="{y}" width="72" height="8" rx="2" fill="url(#rim)" stroke="#0006" stroke-width="1"/>'
    return s


def frame(fr, group, metal, inner, bars):
    eng = METALS[metal][3]
    cloth = CLOTH[group] if metal != "none" else "#3a3a3a"
    if fr == "medal":
        body = (ribbon(group, metal, bars) + '<circle cx="128" cy="160" r="86" fill="url(#rim)"/>'
                '<circle cx="128" cy="160" r="76" fill="url(#mt)"/>'
                + ('<circle cx="128" cy="160" r="71" fill="none" stroke="#9a1c1c" stroke-width="9"/>' if metal == "banner" else "")
                + f'<circle cx="128" cy="160" r="64" fill="none" stroke="{eng}" stroke-width="2" opacity="0.6"/>'
                f'<g transform="translate(70.5 102.5) scale(1.15)">{inner}</g>')
    elif fr == "patch":
        body = (gear(128, 128, 120, 16, "url(#rim)", tw=0.18) + f'<circle cx="128" cy="128" r="98" fill="{cloth}"/>'
                '<circle cx="128" cy="128" r="92" fill="none" stroke="url(#mt)" stroke-width="5" stroke-dasharray="7 5"/>'
                + "".join(f'<circle cx="{128 + 106 * math.cos(math.radians(a)):.1f}" cy="{128 + 106 * math.sin(math.radians(a)):.1f}" '
                          f'r="5" fill="url(#mt)"/>' for a in range(-90, 270, int(360 / max(bars, 1))))
                + f'<g transform="translate(64 64) scale(1.28)">{inner}</g>')
    elif fr == "shield":
        body = ('<path d="M128,10 L232,40 Q232,170 128,246 Q24,170 24,40 Z" fill="url(#rim)"/>'
                '<path d="M128,24 L218,50 Q216,160 128,230 Q40,160 38,50 Z" fill="url(#mt)"/>'
                f'<path d="M128,24 L128,230" stroke="{eng}" stroke-width="1.5" opacity="0.3"/>'
                + "".join(f'<path d="M{70 + i * 20},212 L{80 + i * 20},200 L{90 + i * 20},212" stroke="{eng}" stroke-width="3" fill="none"/>'
                          for i in range(bars) if bars > 1)
                + f'<g transform="translate(68 54) scale(1.2)">{inner}</g>')
    elif fr == "badge":
        hexa = " ".join(f"{128 + 112 * math.cos(math.radians(30 + 60 * i)):.1f},{128 + 112 * math.sin(math.radians(30 + 60 * i)):.1f}" for i in range(6))
        hexi = " ".join(f"{128 + 96 * math.cos(math.radians(30 + 60 * i)):.1f},{128 + 96 * math.sin(math.radians(30 + 60 * i)):.1f}" for i in range(6))
        body = (f'<g transform="translate(-50 -40) scale(3.56 2.4)">{wings("url(#rim)", 70, 50)}</g>'
                 f'<polygon points="{hexa}" fill="url(#rim)"/><polygon points="{hexi}" fill="{cloth}"/>'
                 f'<polygon points="{hexi}" fill="none" stroke="url(#mt)" stroke-width="4"/>'
                 + "".join(f'<circle cx="{108 + i * 20}" cy="214" r="5" fill="url(#mt)"/>' for i in range(bars) if bars > 1)
                 + f'<g transform="translate(66 62) scale(1.24)">{inner}</g>')
    else:  # order: eight-ray star of the story medal
        body = (star_burst(128, 128, 122, 70, 8, "url(#rim)", 22.5) + star_burst(128, 128, 108, 64, 8, "url(#mt)", 22.5)
                + '<circle cx="128" cy="128" r="62" fill="#7a1c1c"/><circle cx="128" cy="128" r="62" fill="none" stroke="url(#rim)" stroke-width="6"/>'
                + f'<g transform="translate(78 78)">{inner}</g>')
    return body


def svg(m, metal, bars):
    eng, hi = METALS[metal][3], METALS[metal][0]
    if m["f"] in ("patch", "badge"):
        eng, hi = METALS[metal][1], METALS[metal][0]   # light metal emblem on dark cloth
    if m["f"] == "order":
        eng, hi = METALS[metal][0], METALS[metal][1]
    inner = emblem(m["id"], eng, hi)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">{defs(metal)}'
            f'{frame(m["f"], m["g"], metal, inner, bars)}</svg>\n')


def main():
    os.makedirs(OUT, exist_ok=True)
    medals = read_medals()
    if len(medals) < 30:
        sys.exit("medals.gd list not parsed: %d medals" % len(medals))
    names = []
    for m in medals:
        metals = ["gold"] if m["n"] == 1 else ["bronze", "silver", "gold", "banner"][:m["n"]]
        for i, metal in enumerate(metals + ["none"]):
            bars = (i + 1) if metal != "none" else 0
            name = f'{m["id"]}_{metal}.svg'
            with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
                f.write(svg(m, metal, bars))
            names.append(name)
    print("medals: %d medals, %d pictures in %s" % (len(medals), len(names), OUT))


if __name__ == "__main__":
    main()
