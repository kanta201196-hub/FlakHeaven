"""Stands of the hangar weapon store that carry a weapon along its whole length (s16 review S16-11..14).
Ground handling kit for stores is a low steel trailer with rails on its deck: long bodies rest on chocks or shaped
timber bolsters laid across (or along) the rails, racks and pod clusters lie on the deck on bolsters, flat items lie
on a flat deck. So the store gets:
  stand_trailer_long.glb  - long narrow munitions trailer (the 8-bomb rack, laid lengthwise)
  stand_trailer_mid.glb   - medium trailer (the high-explosive bomb with its big fins)
  stand_trailer_wide.glb  - short wide trailer (the cluster of three rocket pods)
  stand_platform.glb      - flat platform trolley with a rubber mat and a push handle (the flare dispensers)
The bolsters under each weapon are not in these models: Hangar3D shapes them to the weapon's underside.
Run (bpy 5.x):  python3 store_stands.py [nopreview] <out_dir>
  -> out_dir/<name>.glb (+ .blend, preview_*.png); copy the .glb files to game/models/hangar/.
Units: metres. The deck is centred on the origin (X along the deck, Y across, Z up in Blender, glTF Y up), its top
is at DECK_Z, wheels stand on z = 0; Hangar3D reads the deck size and height from STAND_DECKS (keep in sync).
Matte paint (Kanta 19.10): roughness 0.8-0.9, metal only on the bolts, rails and hubs. No textures: the store's
service-paint shader (weapon_paint.gdshader) lays the wear, so nothing is pixelated close up."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L

DECK_Z = 0.62        # trailer deck top (rails and cross members) over the floor
PLAT_Z = 0.5         # platform trolley mat top over the floor
TRAILERS = {         # name: (deck length, deck width)
    "stand_trailer_long": (3.4, 1.3),
    "stand_trailer_mid": (2.8, 1.5),
    "stand_trailer_wide": (2.2, 1.9),
}
PLATFORM = (1.6, 0.9)


def wheel(x, y, r, w, M_TYRE, M_HUB):
    """Tyre with a hub along Y at (x, y), standing on the floor"""
    cyl("tyre", (x, y, r), r, w, M_TYRE, "Y", 28, 0.03)
    cyl("rim", (x, y, r), r * 0.62, w + 0.012, M_HUB, "Y", 20, 0.01)
    cyl("hub", (x, y, r), r * 0.25, w + 0.04, M_HUB, "Y", 12)
    for i in range(5):   # wheel nuts
        a = i * math.tau / 5
        s = 1.0 if y > 0 else -1.0
        cyl("nut", (x + math.cos(a) * r * 0.36, y + s * (w / 2 + 0.012), r + math.sin(a) * r * 0.36), 0.018, 0.02,
            M_HUB, "Y", 6)


def trailer(L_, W, M):
    """Munitions trailer: two channel side members and cross members under four deck rails (slotted tracks the
    chocks bolt to), two axles on leaf-spring hangers, tow bar with a lunette ring resting on a stand leg"""
    hx, hy = L_ / 2, W / 2
    ch = 0.16                                       # channel depth
    # side members (channels) and their stake pockets
    for y in (-hy + 0.05, hy - 0.05):
        box("side", (0, y, DECK_Z - ch / 2), (L_, 0.1, ch), M["frame"], 0.012)
        box("side_lip", (0, y + (0.045 if y > 0 else -0.045), DECK_Z - ch + 0.015), (L_ - 0.02, 0.03, 0.03), M["frame"], 0.006)
        for i in range(int(L_ / 0.55)):
            x = -hx + 0.3 + i * 0.55
            box("pocket", (x, y + (0.07 if y > 0 else -0.07), DECK_Z - 0.06), (0.08, 0.05, 0.1), M["frame"], 0.008)
    # cross members, flush with the deck top
    n = max(3, int(L_ / 0.6) + 1)
    for i in range(n):
        x = -hx + 0.06 + i * (L_ - 0.12) / (n - 1)
        box("cross", (x, 0, DECK_Z - 0.06), (0.1, W - 0.12, 0.12), M["frame"], 0.01)
    # deck rails (slotted tracks): top at DECK_Z, bolts along them
    rails = [-hy * 0.72, -hy * 0.26, hy * 0.26, hy * 0.72]
    for y in rails:
        box("rail", (0, y, DECK_Z - 0.035), (L_ - 0.04, 0.09, 0.07), M["rail"], 0.008)
        box("slot", (0, y, DECK_Z - 0.002), (L_ - 0.14, 0.024, 0.006), M["dark"], 0.0)
        for i in range(int(L_ / 0.4)):
            cyl("bolt", (-hx + 0.25 + i * 0.4, y + 0.032, DECK_Z), 0.012, 0.012, M["metal"], "Z", 6)
    # end beams with tie-down rings
    for x in (-hx + 0.02, hx - 0.02):
        box("end", (x, 0, DECK_Z - ch / 2), (0.06, W, ch), M["frame"], 0.01)
        for y in (-hy * 0.8, hy * 0.8):
            cyl("tie_ring", (x + (0.05 if x > 0 else -0.05), y, DECK_Z - 0.08), 0.035, 0.012, M["metal"], "Y", 12)
    # running gear: two axles under the deck, spring hangers, wheels inside the side members
    r = 0.22
    ax = hx - max(0.38, L_ * 0.17)
    for x in (-ax, ax):
        cyl("axle", (x, 0, r), 0.035, W - 0.2, M["dark"], "Y", 12)
        for y in (-hy + 0.24, hy - 0.24):
            box("spring", (x, y, r + 0.11), (0.5, 0.06, 0.035), M["dark"], 0.008)
            box("hanger", (x - 0.22, y, (r + 0.11 + DECK_Z - ch) / 2), (0.05, 0.06, DECK_Z - ch - r - 0.1), M["frame"], 0.006)
            box("hanger", (x + 0.22, y, (r + 0.11 + DECK_Z - ch) / 2), (0.05, 0.06, DECK_Z - ch - r - 0.1), M["frame"], 0.006)
            wheel(x, y + (0.1 if y > 0 else -0.1), r, 0.13, M["tyre"], M["metal"])
    # tow bar: A-frame from the front cross member to a lunette ring, resting on a stand leg
    tip = hx + 0.95
    tube("tow", [(hx - 0.05, -hy * 0.55, DECK_Z - 0.1), (tip - 0.1, 0, 0.36)], 0.035, M["frame"])
    tube("tow", [(hx - 0.05, hy * 0.55, DECK_Z - 0.1), (tip - 0.1, 0, 0.36)], 0.035, M["frame"])
    tube("tow", [(tip - 0.12, 0, 0.36), (tip, 0, 0.36)], 0.03, M["frame"])
    cyl("lunette", (tip + 0.06, 0, 0.36), 0.065, 0.03, M["metal"], "Z", 18)
    box("leg", (tip - 0.25, 0, 0.18), (0.04, 0.04, 0.36), M["dark"], 0.004)
    box("foot", (tip - 0.25, 0, 0.012), (0.12, 0.12, 0.024), M["dark"], 0.004)
    # hand brake lever and a blank data plate
    tube("brake", [(hx - 0.25, hy - 0.02, DECK_Z - 0.1), (hx - 0.1, hy + 0.05, DECK_Z + 0.08)], 0.015, M["dark"])
    box("plate", (hx - 0.7, hy + 0.002, DECK_Z - 0.08), (0.18, 0.006, 0.09), M["dark"], 0.002)


def platform(L_, W, M):
    """Flat platform trolley: a steel deck with a low lip and a rubber mat, four casters (two swivel),
    a tubular push handle at the back end"""
    hx, hy = L_ / 2, W / 2
    t = 0.05
    box("deck", (0, 0, PLAT_Z - 0.012 - t / 2), (L_, W, t), M["frame"], 0.01)
    box("mat", (0, 0, PLAT_Z - 0.006), (L_ - 0.1, W - 0.1, 0.012), M["tyre"], 0.003)
    for y in (-hy + 0.012, hy - 0.012):
        box("lip", (0, y, PLAT_Z), (L_, 0.024, 0.04), M["frame"], 0.006)
    for x in (-hx + 0.012, hx - 0.012):
        box("lip", (x, 0, PLAT_Z), (0.024, W, 0.04), M["frame"], 0.006)
    # frame under the deck
    for y in (-hy + 0.08, hy - 0.08):
        box("runner", (0, y, PLAT_Z - 0.1), (L_ - 0.06, 0.06, 0.08), M["frame"], 0.008)
    for x in (-hx + 0.1, 0.0, hx - 0.1):
        box("cross", (x, 0, PLAT_Z - 0.1), (0.06, W - 0.1, 0.07), M["frame"], 0.008)
    # legs to the casters (a load table is higher than a floor trolley: the store shows the weapon at eye level)
    r = 0.09
    for x in (-hx + 0.14, hx - 0.14):
        for y in (-hy + 0.12, hy - 0.12):
            top = PLAT_Z - 0.14
            box("leg", (x, y, (top + 2 * r + 0.06) / 2), (0.06, 0.06, top - 2 * r - 0.06), M["frame"], 0.006)
            box("fork", (x, y, 2 * r + 0.03), (0.1, 0.09, 0.05), M["dark"], 0.006)
            cyl("caster", (x, y, r), r, 0.06, M["tyre"], "Y", 20, 0.012)
            cyl("caster_hub", (x, y, r), 0.03, 0.075, M["metal"], "Y", 10)
        tube("brace", [(x, -hy + 0.12, 2 * r + 0.12), (x, hy - 0.12, 2 * r + 0.12)], 0.018, M["frame"])
    # push handle at the back
    x = -hx - 0.03
    tube("handle", [(x, -hy + 0.08, PLAT_Z - 0.02), (x - 0.05, -hy + 0.08, PLAT_Z + 0.5), (x - 0.05, hy - 0.08, PLAT_Z + 0.5),
                    (x, hy - 0.08, PLAT_Z - 0.02)], 0.018, M["metal"])
    cyl("grip", (x - 0.05, 0, PLAT_Z + 0.5), 0.026, W * 0.5, M["tyre"], "Y", 12)


def materials():
    return {
        "frame": mat("stand_frame", (0.27, 0.29, 0.22), 0.1, 0.84),    # faded olive-drab painted steel
        "rail": mat("stand_rail", (0.33, 0.33, 0.31), 0.45, 0.7),     # worn steel tracks
        "dark": mat("stand_dark", (0.07, 0.07, 0.075), 0.1, 0.85),
        "metal": mat("stand_metal", (0.42, 0.42, 0.41), 0.6, 0.55),
        "tyre": mat("stand_tyre", (0.05, 0.05, 0.05), 0.0, 0.92),
    }


if __name__ == "__main__":
    OUT = sys.argv[-1] if len(sys.argv) > 1 else "."
    for name, (l, w) in list(TRAILERS.items()) + [("stand_platform", PLATFORM)]:
        L.reset()
        M = materials()
        L.group = ""
        if name == "stand_platform":
            platform(l, w, M)
        else:
            trailer(l, w, M)
        build(name, OUT)
        if "nopreview" not in sys.argv:
            preview(OUT + "/" + name, [("iso", (l * 1.6, -l * 1.9, l * 1.3), (0, 0, 0.4), 50)])
    print("DONE")
