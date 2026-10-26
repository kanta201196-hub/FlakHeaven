"""AA-site bunker of the Highlands in the «Укрепрайон» look (VIS-01, Kanta 26.10.2026: «Бункер очень плохой, переделывай»).

Why: the scan bunker (#94) read as a shapeless blob with a hole in its face. This one is built from data like
ground_models.py, but its surfaces use the fort's texture set Г (game/art/fort: concrete, stone, planks; the
fort's burlap for the bags), so the bunker and the «Укрепрайон» read as one army's work.

What: a concrete casemate dug into an earth berm up to its roof slab, facing +X: a wide embrasure with a dark interior and a
twin MG under the slab edge, a thick roof slab with chipped edges and bent rebar, a sandbag rim on the roof, a rear
entrance trench with plank revetment and steps, a periscope, an antenna stub and a vent. Weathering is baked:
dust low and in crevices, rain streaks, chipped concrete edges, soot above the embrasure.

Length 1 = the game sprite's length (GroundTarget "bunker", 59 px), width 0.83 (sprite 256x212), ground at z = 0.
The model is one node, like the scan was (render3d.gd has no moving parts for the bunker).

Run (Blender's bpy from pip):
    python3 game/tools/blender/bunker_fort.py <out_dir>
    -> <out_dir>/e_bunker.glb, then copy to game/models/battle/fh_battle_e_bunker.glb
Sprite: python3 game/tools/blender/plane_sprite.py <glb> 256 game/art/enemies/e_bunker.png --height=212"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import convoy_kit as K  # noqa: E402
from convoy_kit import _band, _m, _mix, _n, _noise, _sock, box, cyl, prism_z, tube  # noqa: E402

OUT = sys.argv[-1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FORT = os.path.join(ROOT, "art", "fort")
GROUND = os.path.join(ROOT, "art", "ground", "pbr")
BAG = os.path.join(ROOT, "models", "biome", "b10_sandbag_post_sandbag_burlap_color.jpg")
DUST = (0.66, 0.55, 0.42)
K.reset()
K.EDGE_K = 0.8


# ---------------------------------------------------------------- materials (texture set Г)
def _img(path):
    im = bpy.data.images.load(path, check_existing=True)
    return im


def _boxtex(nt, path, tile, colorspace="sRGB"):
    """Image box-projected in object space, one repeat per `tile` model units (no UV seams to hide)"""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sc = nt.nodes.new("ShaderNodeVectorMath")
    sc.operation = "SCALE"
    nt.links.new(tc.outputs["Object"], sc.inputs[0])
    sc.inputs["Scale"].default_value = 1.0 / tile
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = _img(path)
    t.image.colorspace_settings.name = colorspace
    t.projection = "BOX"
    t.projection_blend = 0.3
    nt.links.new(sc.outputs[0], t.inputs["Vector"])
    return t.outputs["Color"]


def fmat(kind, tex, tile, gain, dust=0.5, soot=False, chips=False, streaks=False, rock="", bump=0.6, low=""):
    """A baked material in the convoy_kit contract (EMIT colour, node "bsdf" for the normal, node "out").
    tex: image path; gain: sRGB-ish multiplier towards the Highlands' sand-ochre (FortBuild.SETS gains);
    rock: path of the ground texture for the gentle faces (tex then shows only on steep ones);
    low: path of the texture near z = 0 (the berm's toe takes the terrain's own sand)."""
    m = bpy.data.materials.new(kind)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    z = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(pos, z.inputs[0])
    nz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], nz.inputs[0])
    up = _m(nt, "MAXIMUM", nz.outputs["Z"], 0.0)
    side = _m(nt, "SUBTRACT", 1.0, _m(nt, "ABSOLUTE", nz.outputs["Z"]))
    col = _boxtex(nt, tex, tile)
    col = _mix(nt, 1.0, col, _sock(nt, gain), "MULTIPLY")
    if rock:
        # sandstone knoll: steep faces show the stone, gentle ones are sand and grit of the same tone
        flat = _band(nt, nz.outputs["Z"], 0.6, 0.86)
        sand = _mix(nt, 1.0, _boxtex(nt, rock, 1.4), (0.92, 0.84, 0.76), "MULTIPLY")
        col = _mix(nt, _m(nt, "MULTIPLY", flat, 0.85), col, sand)
    if rock:
        # the raw gravel and rock albedos read dark orange next to the lit terrain (bench 26.10, the ground shader
        # lifts and greys its sand): less saturated and lighter
        col = _n(nt, "ShaderNodeHueSaturation", Color=col, Saturation=0.8, Value=1.25).outputs["Color"]
    if low:   # the toe: the terrain's own sand, greyed and lifted the way the ground shader shows it on the flats
        ground = _n(nt, "ShaderNodeHueSaturation", Color=_boxtex(nt, low, 1.2), Saturation=0.75, Value=1.55).outputs["Color"]
        col = _mix(nt, _m(nt, "SUBTRACT", 1.0, _band(nt, z.outputs["Z"], 0.004, 0.045)), col, ground)
    # large blotches: sun bleach and damp, so a big face is not one flat tone
    big = _noise(nt, pos, 4.0, 3.0, (4.0, 2.0, 7.0))
    col = _mix(nt, _m(nt, "MULTIPLY", _band(nt, big, 0.45, 0.66), 0.35), col, (0.8, 0.72, 0.6), "MULTIPLY")
    if not rock:   # sun bleach on top faces; the knoll keeps the terrain textures' own tone so it does not read as a pale plate
        col = _mix(nt, _m(nt, "MULTIPLY", up, 0.12), col, (0.82, 0.74, 0.62))
    if streaks:
        st = _noise(nt, pos, 9.0, 2.0, (0, 0, 0), (7.0, 7.0, 0.5))
        col = _mix(nt, _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", _band(nt, st, 0.55, 0.72), side), 0.4), col, (0.3, 0.27, 0.22))
    bev = _n(nt, "ShaderNodeBevel", Radius=0.006)
    bev.samples = 6
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs[0], dot.inputs[0])
    nt.links.new(geo.outputs["True Normal"], dot.inputs[1])
    edge = _band(nt, _m(nt, "SUBTRACT", 1.0, dot.outputs["Value"]), 0.01, 0.07)
    if chips:
        # chipped concrete edges: fresh, paler aggregate where the corner broke off
        cn = _noise(nt, pos, 34.0, 3.0, (3.3, 0.0, 1.1))
        col = _mix(nt, _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", edge, _band(nt, cn, 0.42, 0.58)), 0.8), col, (0.74, 0.68, 0.57))
    if soot:
        # soot above the embrasure: an upward plume from the slit, broken by noise
        d = nt.nodes.new("ShaderNodeVectorMath")
        d.operation = "SUBTRACT"
        nt.links.new(pos, d.inputs[0])
        d.inputs[1].default_value = (0.26, 0.0, 0.085)
        st = nt.nodes.new("ShaderNodeVectorMath")
        st.operation = "MULTIPLY"
        nt.links.new(d.outputs[0], st.inputs[0])
        st.inputs[1].default_value = (3.0, 0.9, 1.6)
        ln = nt.nodes.new("ShaderNodeVectorMath")
        ln.operation = "LENGTH"
        nt.links.new(st.outputs[0], ln.inputs[0])
        rise = _band(nt, _m(nt, "SUBTRACT", z.outputs["Z"], 0.07), -0.02, 0.03)   # soot climbs, little below the slit
        sn = _noise(nt, pos, 22.0, 4.0, (7.0, 1.0, 3.0))
        k = _m(nt, "MULTIPLY", _m(nt, "SUBTRACT", 1.0, _band(nt, ln.outputs["Value"], 0.05, 0.24)), rise)
        k = _m(nt, "MULTIPLY", k, _m(nt, "ADD", 0.45, _m(nt, "MULTIPLY", sn, 0.8)), True)
        col = _mix(nt, _m(nt, "MULTIPLY", k, 0.85), col, (0.07, 0.065, 0.06))
    ao = _n(nt, "ShaderNodeAmbientOcclusion", Distance=0.03)
    ao.samples = 16
    ao.only_local = False
    if dust > 0:
        dn = _noise(nt, pos, 14.0, 3.0, (1.1, 2.2, 3.3))
        low = _m(nt, "MULTIPLY", _m(nt, "SUBTRACT", 1.0, _band(nt, z.outputs["Z"], 0.01, 0.09)), _m(nt, "ADD", 0.1, _m(nt, "MULTIPLY", dn, 0.6)))
        crev = _m(nt, "MULTIPLY", _m(nt, "SUBTRACT", 1.0, ao.outputs["AO"]), 0.35)
        top = _m(nt, "MULTIPLY", _m(nt, "MULTIPLY", up, up), _m(nt, "MULTIPLY", _band(nt, dn, 0.5, 0.75), 0.25))
        dd = _m(nt, "MULTIPLY", _m(nt, "ADD", _m(nt, "ADD", low, crev), top), dust, True)
        col = _mix(nt, _m(nt, "MINIMUM", dd, 0.55), col, DUST)
    occl = _m(nt, "ADD", 0.4, _m(nt, "MULTIPLY", ao.outputs["AO"], 0.6))
    col = _mix(nt, 1.0, col, occl, "MULTIPLY")
    em = _n(nt, "ShaderNodeEmission", Color=col, Strength=1.0)
    # normal: rounded edges plus relief from the texture's own shading (box projection has no tangents to reuse a normal map)
    nrm = _n(nt, "ShaderNodeBevel", Radius=0.004)
    nrm.samples = 8
    h = _boxtex(nt, tex, tile)
    hl = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(h, hl.inputs[0])
    bp = _n(nt, "ShaderNodeBump", Strength=bump, Distance=0.004, Height=hl.outputs[0], Normal=nrm.outputs[0])
    bs = _n(nt, "ShaderNodeBsdfPrincipled", Normal=bp.outputs[0])
    bs.name = "bsdf"
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.name = "out"
    nt.links.new(em.outputs[0], out.inputs[0])
    m["emit"] = em.name
    K._mats[kind] = m
    return m


fmat("conc", os.path.join(FORT, "conc_color.jpg"), 0.2, (0.98, 0.84, 0.66), 0.5, soot=True, chips=True, streaks=True)
# the roof slab is what the combat camera sees: the fort's concrete, only lightly dusted (0.9 hid it under flat sand)
fmat("slab", os.path.join(FORT, "conc_color.jpg"), 0.2, (0.92, 0.86, 0.76), 0.3, chips=True, streaks=True)
# the berm wears the terrain's own textures (art/ground/pbr): spoil of gravel and rock up the slope, the plain sand
# of the flats at the toe, so it fades into the map; tiles a few times finer than the terrain's (300 px = 5 units),
# which would leave the close-up a flat smear
fmat("knoll", os.path.join(GROUND, "rock_albedo.jpg"), 1.0, (0.9, 0.84, 0.8), 0.15, rock=os.path.join(GROUND, "gravel_albedo.jpg"),
     bump=0.9, low=os.path.join(GROUND, "sand_albedo.jpg"))
fmat("plank", os.path.join(FORT, "wood_color.jpg"), 0.14, (0.8, 0.7, 0.58), 0.6, bump=0.8)
fmat("bag", BAG, 0.06, (0.95, 0.86, 0.7), 0.4, bump=0.7)
fmat("trench", os.path.join(FORT, "stone_color.jpg"), 0.2, (0.62, 0.48, 0.36), 0.8, bump=0.5)

# ---------------------------------------------------------------- earth berm
# Coordinator review 26.10: the round knoll read as a pale plate under a box. The casemate is now dug in: an
# irregular berm of spoil is heaped against its sides and back up to the roof slab and slopes out into the ground
# with a soft toe (cosine profile, zero slope where it meets the terrain, then sinks under it), so only the slab,
# the embrasure face and the rear trench show.
FRONT = 0.19               # casemate face
REAR = -0.2                # casemate back wall
HB = 0.17                  # body half width
TOP = 0.12                 # body top (low profile: the berm covers the walls)
TR_Y = 0.058               # trench half width
EZ0, EZ1, EW = 0.035, 0.088, 0.11   # embrasure sill, lintel and half width
HW = TOP - 0.008           # berm height against the walls


def _hash(i, j):
    v = math.sin(i * 127.1 + j * 311.7) * 43758.5453
    return v - math.floor(v)


def _vnoise(x, y, f):
    x, y = x * f, y * f
    i, j = math.floor(x), math.floor(y)
    fx, fy = x - i, y - j
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b, c, d = _hash(i, j), _hash(i + 1, j), _hash(i, j + 1), _hash(i + 1, j + 1)
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy


def _rect_d(x, y):
    """Distance from (x, y) to the casemate's footprint (0 inside)"""
    dx = max(REAR - x, 0.0, x - FRONT)
    dy = max(abs(y) - HB, 0.0)
    return math.hypot(dx, dy)


def berm_w(x, y):
    """Berm width round the walls: irregular, wider at the back, narrower on the sides (sprite canvas 256x212)"""
    w = 0.13 + 0.09 * _vnoise(x + 5.3, y - 2.1, 4.5)
    if x < REAR:
        w += 0.05
    return w


def knoll_h(x, y):
    """Ground height of the bunker model: the berm against the walls, a glacis under the embrasure, the trench"""
    d = _rect_d(x, y)
    w = berm_w(x, y)
    t = d / w
    if t >= 1.0:   # past the toe the berm dips just under the terrain (deeper would lift it: the studio and the
        return -0.004 * min(1.0, (t - 1.0) / 0.2)   # sprite ground a model on its lowest point)
    s = 0.5 * (1.0 + math.cos(math.pi * t))
    h = HW * s
    # spoil lumps and a ragged crest
    h += s * (0.012 * (_vnoise(x + 3.1, y, 9.0) - 0.5) + 0.004 * (_vnoise(x, y + 1.7, 31.0) - 0.5))
    # glacis in front of the face: the earth stops under the sill and falls away forward; the berm wraps the
    # front corners, so the face shows only between them
    if x > FRONT - 0.03:
        k = min(1.0, (x - FRONT + 0.03) / 0.04) * max(0.0, min(1.0, 1.0 - (abs(y) - HB + 0.01) / 0.07))
        gl = max(0.0, EZ0 - 0.014 - 0.45 * max(0.0, x - FRONT)) * (0.5 + 0.5 * math.cos(math.pi * min(1.0, max(0.0, x - FRONT) / 0.16)))
        h = h * (1.0 - k) + min(h, gl) * k
    # rear trench to the door, cut through the berm
    if x < REAR + 0.01:
        tw = TR_Y + 0.012 + (REAR - x) * 0.04
        if abs(y) < tw:
            h = min(h, 0.004)
        elif abs(y) < tw + 0.03:
            k = (abs(y) - tw) / 0.03
            h = min(h, 0.004 + (h - 0.004) * k)
    return h


# rays from the casemate's centre: each starts inside the footprint (hidden under the casemate) and ends past the
# berm's toe, so the sheet's outer edge is a smooth curve just under the ground, not a grid's staircase
NA, NR = 120, 26
XC = (FRONT + REAR) / 2
vs, fs = [], []
for i in range(NA):
    a = 2 * math.pi * i / NA
    ca, sa = math.cos(a), math.sin(a)
    # where the ray leaves the footprint
    r0 = min((FRONT - XC) / ca if ca > 1e-6 else (REAR - XC) / ca if ca < -1e-6 else 9.0,
             HB / abs(sa) if abs(sa) > 1e-6 else 9.0)
    ex, ey = XC + ca * r0, sa * r0
    r1 = r0 + 1.25 * berm_w(ex, ey)
    if abs(sa) > 1e-6:
        r1 = min(r1, 0.405 / abs(sa))   # the sprite canvas (256x212)
    r1 = min(r1, (0.4 - XC) / ca if ca > 1e-6 else (-0.52 - XC) / ca if ca < -1e-6 else 9.0)
    for j in range(NR + 1):
        u = j / NR
        r = r0 - 0.02 + (r1 - r0 + 0.02) * (u ** 1.15)
        x, y = XC + ca * r, sa * r
        h = knoll_h(x, y)
        if j == NR:
            h = min(h, -0.004)
        vs.append((x, y, h))
for i in range(NA):
    i1 = (i + 1) % NA
    for j in range(NR):
        fs.append((i * (NR + 1) + j, i * (NR + 1) + j + 1, i1 * (NR + 1) + j + 1, i1 * (NR + 1) + j))
kn = K._obj("knoll", vs, fs, "knoll")
# convoy_kit recalculates normals "outside", which on an open sheet can turn it face-down (the bake then saw every
# face as steep); a ground sheet always faces up
import bmesh  # noqa: E402
bm = bmesh.new()
bm.from_mesh(kn.data)
bm.normal_update()
bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.normal.z < 0.0])
bm.to_mesh(kn.data)
bm.free()

# ---------------------------------------------------------------- casemate


def rr(a, b, r, cx=0.0, n=3):
    pts = []
    for qx, qy, a0 in ((a - r, b - r, 0), (-a + r, b - r, 90), (-a + r, -b + r, 180), (a - r, -b + r, 270)):
        for k in range(n + 1):
            t = math.radians(a0 + 90 * k / n)
            pts.append((cx + qx + r * math.cos(t), qy + r * math.sin(t)))
    return pts


bx = (FRONT + REAR) / 2
bh = (FRONT - REAR) / 2
prism_z("casemate", rr(bh, HB, 0.02, bx), -0.01, TOP, "conc", 0.006, 2)
# battered front: a sloped concrete apron at the foot of the face
K._obj("face_batter", [(FRONT, -HB, -0.01), (FRONT, HB, -0.01), (FRONT + 0.035, HB, -0.01), (FRONT + 0.035, -HB, -0.01),
                       (FRONT, -HB, 0.02), (FRONT, HB, 0.02)],
       [(0, 3, 2, 1), (0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5)], "conc", 0.004)

# roof slab: thick, overhanging, with chipped corners and edges (a jagged outline, not a clean rounded box)
SX0, SX1, SY = REAR - 0.04, FRONT + 0.015, HB + 0.045   # little overhang at the front: it shaded the embrasure
outline = []
P = [(SX1, -SY), (SX1, SY), (SX0, SY), (SX0, -SY)]
chips = []
for e in range(4):
    a, b = P[e], P[(e + 1) % 4]
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(4, int(L / 0.03))
    nx_, ny_ = (b[1] - a[1]) / L, -(b[0] - a[0]) / L   # outward
    for k in range(n):
        t = k / n
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        cut = 0.0
        hh = _hash(e * 31 + k, 7)
        if k == 0:
            cut = 0.012 + 0.02 * hh          # broken corner
        elif hh > 0.78:
            cut = 0.008 + 0.018 * _hash(k, e)
            chips.append((x - nx_ * cut, y - ny_ * cut, nx_, ny_))
        outline.append((x - nx_ * cut, y - ny_ * cut))
prism_z("roof_slab", outline, TOP - 0.005, TOP + 0.04, "slab", 0.005, 2)
# exposed rebar in the chips, bent outwards
for (x, y, nx_, ny_) in chips[:6]:
    for s in (-0.006, 0.006):
        px, py = x - ny_ * s, y + nx_ * s
        tube("rebar", [(px - nx_ * 0.01, py - ny_ * 0.01, TOP + 0.017), (px + nx_ * 0.006, py + ny_ * 0.006, TOP + 0.018),
                       (px + nx_ * 0.016, py + ny_ * 0.016, TOP + 0.03)], 0.0014, "steel", 4)

# embrasure: a wide slit with a dark interior, splayed cheeks, a sloped sill and a twin MG
box("emb_dark", (FRONT + 0.001, 0, (EZ0 + EZ1) / 2), (0.004, 2 * EW, EZ1 - EZ0), "black", 0.0)
for s in (1, -1):
    K._obj("emb_cheek", [(FRONT, s * EW, EZ0 - 0.012), (FRONT, s * EW, EZ1 + 0.012), (FRONT + 0.03, s * (EW + 0.03), EZ1 + 0.02),
                         (FRONT + 0.03, s * (EW + 0.03), EZ0 - 0.02), (FRONT + 0.03, s * (EW + 0.055), EZ1 + 0.02),
                         (FRONT + 0.03, s * (EW + 0.055), EZ0 - 0.02), (FRONT, s * (EW + 0.055), EZ1 + 0.02), (FRONT, s * (EW + 0.055), EZ0 - 0.02)],
           [(0, 1, 2, 3), (3, 2, 4, 5), (5, 4, 6, 7), (1, 6, 4, 2), (0, 3, 5, 7)], "conc", 0.003)
K._obj("emb_sill", [(FRONT, -EW, EZ0), (FRONT, EW, EZ0), (FRONT + 0.035, EW + 0.02, EZ0 - 0.022), (FRONT + 0.035, -EW - 0.02, EZ0 - 0.022),
                    (FRONT, -EW, EZ0 - 0.03), (FRONT, EW, EZ0 - 0.03)],
       [(0, 3, 2, 1), (0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5)], "conc", 0.003)
box("mantlet", (FRONT + 0.004, 0.0, 0.061), (0.016, 0.05, 0.03), "dark", 0.003)
for s in (-0.011, 0.011):
    cyl("barrel", (FRONT + 0.045, s, 0.062), 0.0038, 0.075, "steel", "X", 8)
    cyl("muzzle", (FRONT + 0.084, s, 0.062), 0.0055, 0.012, "dark", "X", 8)

# rear wall: steel door, frame, steps down from the trench
box("door", (REAR - 0.002, 0, 0.05), (0.006, 0.075, 0.095), "dark", 0.002)
box("door_frame", (REAR - 0.006, 0, 0.104), (0.012, 0.1, 0.014), "conc", 0.003)
for s in (1, -1):
    box("door_post", (REAR - 0.006, s * 0.044, 0.05), (0.012, 0.012, 0.1), "conc", 0.002)
cyl("door_wheel", (REAR - 0.008, 0.016, 0.052), 0.012, 0.004, "steel", "X", 10)

# ---------------------------------------------------------------- rear trench with plank revetment
TX0 = -0.5
for s in (1, -1):
    y = s * (TR_Y + 0.004)
    x = TX0 + 0.02
    while x < REAR - 0.01:
        x1 = min(x + 0.075, REAR - 0.005)
        top = max(0.03, min(0.11, knoll_h((x + x1) / 2, s * (TR_Y + 0.05)) + 0.01))
        for k in range(int(top / 0.022) + 1):
            z0 = 0.002 + k * 0.022
            if z0 > top:
                break
            box("revet_plank", ((x + x1) / 2, y, z0 + 0.01), (x1 - x - 0.003, 0.006, 0.019), "plank", 0.0015, 1,
                rot=("X", s * 2.0 + 3 * (_hash(k, x * 100) - 0.5)))
        box("revet_post", (x1, y + s * 0.004, top / 2), (0.012, 0.012, top + 0.01), "plank", 0.002, 1)
        x = x1
box("trench_floor", ((TX0 + REAR) / 2, 0, 0.005), (REAR - TX0, 2 * TR_Y, 0.004), "trench", 0.0)
for i in range(3):   # steps down to the door: duckboards
    box("duckboard", (REAR - 0.03 - i * 0.07, 0, 0.007), (0.06, 2 * TR_Y - 0.012, 0.006), "plank", 0.0015, 1)

# ---------------------------------------------------------------- sandbags: a rim on the roof (sides and back) and at the trench mouth


def bag(x, y, z, yaw, tilt=0.0):
    box("sandbag", (x, y, z), (0.044, 0.024, 0.016), "bag", 0.0065, 2, rot=("Z", yaw))


ZR = TOP + 0.048
for row in range(2):
    zz = ZR + row * 0.014
    off = 0.022 * (row % 2)
    # back
    y = -SY + 0.03 + off
    while y < SY - 0.03:
        bag(SX0 + 0.022, y, zz, 90 + 8 * (_hash(y * 50, row) - 0.5))
        y += 0.046
    # sides, from the back to two thirds forward
    for s in (1, -1):
        x = SX0 + 0.05 + off
        while x < FRONT - 0.07:
            bag(x, s * (SY - 0.02), zz, 8 * (_hash(x * 50, row + s) - 0.5))
            x += 0.046
for s in (1, -1):
    for i in range(3):
        bag(TX0 + 0.06 + i * 0.046, s * (TR_Y + 0.03), knoll_h(TX0 + 0.06 + i * 0.046, s * (TR_Y + 0.03)) + 0.01, 6 * (i - 1))

# ---------------------------------------------------------------- roof kit: periscope, antenna stub, vent
cyl("periscope", (FRONT - 0.06, 0.09, TOP + 0.07), 0.006, 0.05, "dark", "Z", 8)
box("periscope_head", (FRONT - 0.055, 0.09, TOP + 0.1), (0.022, 0.014, 0.014), "dark", 0.002)
cyl("antenna_base", (bx - 0.06, -0.11, TOP + 0.05), 0.011, 0.016, "dark", "Z", 8, 0.002)
tube("antenna", [(bx - 0.06, -0.11, TOP + 0.055), (bx - 0.062, -0.11, TOP + 0.2)], 0.0022, "steel", 4)
cyl("vent", (bx - 0.1, 0.06, TOP + 0.065), 0.012, 0.04, "steel", "Z", 10)
cyl("vent_cap", (bx - 0.1, 0.06, TOP + 0.088), 0.02, 0.008, "dark", "Z", 10, 0.002)
# roof hatch and the ammo boxes by it: the roof is what the player sees from the combat camera
cyl("hatch", (bx - 0.02, -0.04, TOP + 0.043), 0.028, 0.008, "dark", "Z", 16, 0.002)
cyl("hatch_rim", (bx - 0.02, -0.04, TOP + 0.04), 0.034, 0.006, "slab", "Z", 16, 0.002)
box("hatch_handle", (bx - 0.02, -0.04, TOP + 0.05), (0.03, 0.004, 0.004), "steel", 0.0)
box("ammo_box", (bx + 0.07, -0.1, TOP + 0.053), (0.04, 0.022, 0.018), "olive", 0.002)
box("ammo_box", (bx + 0.074, -0.074, TOP + 0.053), (0.04, 0.022, 0.018), "olive", 0.002, rot=("Z", 8))
box("ammo_box", (bx + 0.072, -0.087, TOP + 0.071), (0.04, 0.022, 0.018), "olive", 0.002, rot=("Z", -5))
# camouflage net on three poles over the back corner of the roof and the knoll, sagging onto both
def surf(x, y):
    if SX0 < x < SX1 and abs(y) < SY:
        return TOP + 0.04
    return max(0.0, knoll_h(x, y))


poles = [(SX0 + 0.03, -SY - 0.03, 0.19), (bx - 0.04, -SY - 0.04, 0.185), (SX0 + 0.11, -0.07, 0.215)]
for (x, y, zt) in poles:
    tube("net_pole", [(x, y, surf(x, y) - 0.01), (x, y, zt)], 0.004, "wood", 5)
NX_, NY_ = 16, 10
NX0, NX1, NY0, NY1 = SX0 - 0.06, bx + 0.02, -SY - 0.09, -0.03
nv, nf = [], []


def net_h(x, y):
    h = 0.0
    for (px, py, pz) in poles:
        d = math.hypot((x - px) / 0.22, (y - py) / 0.18)
        h = max(h, pz * math.exp(-d * d * 0.8))
    return max(h, surf(x, y) + 0.01) + 0.004 * math.sin(x * 61 + y * 37)


for j in range(NY_ + 1):
    for i in range(NX_ + 1):
        x = NX0 + (NX1 - NX0) * i / NX_ + 0.01 * math.sin(j * 2.3 + i)   # ragged edge
        y = NY0 + (NY1 - NY0) * j / NY_ + 0.008 * math.sin(i * 1.7 + j)
        nv.append((x, y, net_h(x, y)))
for j in range(NY_):
    for i in range(NX_):
        a = j * (NX_ + 1) + i
        nf.append((a, a + 1, a + NX_ + 2, a + NX_ + 1))
K._obj("camo_net", nv, nf, "net")
# broken concrete lumps in front and at the trench
for i, (x, y, sz) in enumerate([(FRONT + 0.11, 0.17, 0.03), (FRONT + 0.14, -0.2, 0.022), (FRONT + 0.08, -0.25, 0.018), (TX0 + 0.04, 0.12, 0.02)]):
    box("rubble", (x, y, sz * 0.3 + max(0.0, knoll_h(x, y))), (sz, sz * 0.8, sz * 0.6), "slab", 0.004, 1, rot=("Z", 37 * i))

# named e_bunker so the game's extracted textures keep their names (fh_battle_e_bunker_e_bunker_*.jpg)
name = "e_bunker"
root, tris = K.bake_export(name, OUT, tex=2048, glass_kinds=())
# bake_export writes PNG textures into the GLB; the battle models carry JPEG (a quarter of the size)
glb = os.path.join(OUT, name + ".glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_image_format="JPEG",
                          export_jpeg_quality=90)
import importlib.util  # noqa: E402
spec = importlib.util.spec_from_file_location("glb_merge_prims", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "glb_merge_prims.py"))
gm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gm)
gm.merge(glb)
print("DONE", name, tris)
