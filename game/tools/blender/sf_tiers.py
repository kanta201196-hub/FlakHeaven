"""Tiers 2 and 3 of the Sketchfab weapons (3.5-s12, Kanta: "the air-to-ground missile does not change when
upgraded in the hangar", "the HE bomb looks the same at every level"). In PG-01 one Sketchfab model
(sf_weapon_prep.py) became all three tiers; here parts are added to the tier-1 model in code (hq_lib), so the
tier reads from a distance. S14-16 (self-check of 3.5-s14: srm lvl 1 and 3, hebomb lvl 3 and 5 still looked the
same): srm and hebomb tiers now also grow the body itself, the way aam and the bomb calibres grow with the tier
(WeaponModels.tier), and each tier gets parts of its own:
  srm    2 - body 1.18x thicker, motor section in dark grey (two-tone), bands, ring at the nose, cable raceway;
         3 - body 1.34x thicker, long strakes along the body, dark ogive seeker fairing, double yellow band,
             copper motor ring
  agm    2 - bands, front control fins, raceway; 3 - also strakes, laser seeker window and data-link antenna
  hebomb 2 - body 1.1x thicker, fuze extender rod with a disc (bursts above the ground) and two bands;
         3 - body 1.3x thicker, extender with an arming vane and a pointed tip, ballistic ring on struts at
             the nose, three bands, strongback with two lugs on top
The extenders of both tiers end at the same x, so the store view (scaled by the model's length) shows the
thicker tier 3 bigger, not smaller
Length and axes stay (nose +X, length 1); sizes come from measuring the tier-1 models (body radius, fin place).
"Inspired by": no lettering or emblems, bands are only markings.
Run (bpy 5.x): python3 sf_tiers.py <srm|agm|hebomb> <2|3> <in tier-1 .glb> <out_dir> [--battle]
(hangar version from models/weapons/hq/<kind>_1.glb into models/weapons/hq/, the battle one with --battle from
models/weapons/<kind>_1.glb into models/weapons/)"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import hq_lib as H
from hq_lib import *

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
kind, tier, src, OUT = ARGS[0], int(ARGS[1]), ARGS[2], ARGS[3]
BATTLE = "--battle" in sys.argv
H.reset(not BATTLE)
bpy.ops.import_scene.gltf(filepath=src)
base = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(False)


def thicken(k):
    """Scale the imported tier-1 model across its axis (Blender Y and Z) by k, length unchanged"""
    for o in base:
        mw = o.matrix_world
        o.data.transform(mw.inverted() @ Matrix.Diagonal((1.0, k, k, 1.0)) @ mw)
        o.data.update()

M_YELLOW = paint("t_yellow", (0.56, 0.43, 0.045), 0.84, ao=0.4, grime=0.12)
M_BROWN = paint("t_brown", (0.33, 0.2, 0.09), 0.84, ao=0.4, grime=0.1)
M_DARK = paint("t_dark", (0.05, 0.05, 0.055), 0.86, ao=0.4, grime=0.05, dust=0.05)
M_BODY = paint("t_body", (0.085, 0.08, 0.045), 0.86, ao=0.5, grime=0.15, dust=0.2)   # тон корпуса Sketchfab-модели
M_WHITE = paint("t_white", (0.55, 0.56, 0.54), 0.84, ao=0.5, grime=0.12, dust=0.2)   # тон корпуса srm
M_OLIVE = paint("t_olive", (0.17, 0.18, 0.12), 0.87, ao=0.5, grime=0.2, dust=0.3)
M_MOTOR = paint("t_motor", (0.2, 0.21, 0.2), 0.86, ao=0.5, grime=0.2, dust=0.2)   # srm motor case
M_STEEL = metal("t_steel", (0.36, 0.36, 0.37), 0.48, 0.7)
M_GLASS = glass("t_glass", (0.08, 0.12, 0.14))


def band(x0, x1, r, m):
    """Цветной пояс поверх корпуса"""
    emit(lathe([(x0, r + 0.0008), (x1, r + 0.0008)], S(56), False, False), m)


def fin(outline, thick, ang, m):
    """Перо: контур (x, s) — s от оси наружу; поворот вокруг оси X"""
    emit(prism(outline, thick, thick * 0.4, 2), m, RX(ang))


def raceway(x0, x1, r, m):
    """Гаргрот кабелей сверху (сторона пилона — +Z)"""
    emit(box((x1 - x0, r * 0.32, r * 0.22), r * 0.05), m, T((x0 + x1) / 2, 0, r + r * 0.08))


def nose_ring(x, r, m):
    """Кольцо-обойма корпуса (стык отсеков)"""
    emit(tube_shell(r * 1.06, r * 0.98, 0.012, S(48)), m, T(x, 0, 0))


if kind == "agm":
    R = 0.060
    band(0.12, 0.138, R, M_YELLOW)
    band(0.15, 0.168, R, M_YELLOW)
    raceway(-0.36, 0.22, R, M_BODY)
    for k in range(4):   # передние рули у головки
        fin([(0.3, R * 0.85), (0.37, R * 0.85), (0.33, R + 0.035)], 0.004, math.pi / 4 + k * math.pi / 2, M_BODY)
    if tier == 3:
        band(-0.27, -0.25, R, M_BROWN)
        for k in range(4):   # длинные гребни вдоль корпуса между крыльями
            fin([(-0.42, R * 0.9), (-0.33, R * 0.9), (-0.36, R + 0.018), (-0.41, R + 0.018)], 0.004, k * math.pi / 2, M_BODY)
            fin([(0.16, R * 0.9), (0.28, R * 0.9), (0.26, R + 0.014), (0.18, R + 0.014)], 0.003, k * math.pi / 2, M_BODY)
        # лазерная головка вместо телевизионной: тёмный гранёный обтекатель поверх носа и окно
        emit(lathe([(0.38, R * 1.06), (0.44, R * 1.06), (0.48, R * 0.92), (0.5, R * 0.68), (0.514, R * 0.36), (0.514, 0)], 8), M_DARK)
        emit(box((0.004, R * 0.5, R * 0.36), 0.0008), M_GLASS, T(0.5155, 0, 0))
        emit(cyl(0.004, 0.06, S(12)), M_STEEL, T(-0.44, 0, R + 0.03) @ RY(-math.pi / 2))   # антенна линии связи
        emit(box((0.03, 0.012, 0.008), 0.002), M_DARK, T(-0.44, 0, R + 0.062))
elif kind == "srm":
    k = {2: 1.18, 3: 1.34}[tier]
    thicken(k)
    R = 0.0361 * k   # tier-1 body radius 0.0361 (measured), times the tier's thickening
    # motor section in dark grey: the two-tone body reads from afar (the tail fins stand out of it)
    emit(lathe([(-0.47, R * 1.006), (-0.12, R * 1.006)], S(48), False, False), M_MOTOR)
    band(-0.12, -0.105, R * 1.006, M_BROWN)
    band(0.2, 0.215, R, M_YELLOW)
    nose_ring(0.33, R, M_STEEL)
    raceway(-0.28, 0.3, R, M_WHITE)
    if tier == 3:
        for j in range(4):   # long strakes: the missile turns harder
            fin([(-0.1, R * 0.9), (0.26, R * 0.9), (0.22, R + 0.02), (-0.06, R + 0.02)], 0.003, math.pi / 4 + j * math.pi / 2, M_WHITE)
        emit(lathe(ogive(0.42, 0.5, R * 0.86, R * 0.28, 10) + [(0.5, 0)], S(40), False, True), M_DARK)   # dark seeker fairing
        band(0.23, 0.245, R, M_YELLOW)
        emit(lathe([(-0.32, R * 1.016), (-0.3, R * 1.016)], S(48), False, False), M_STEEL)   # dual-pulse motor ring
else:   # hebomb
    k = {2: 1.1, 3: 1.3}[tier]
    thicken(k)
    R = 0.138 * k   # tier-1 body radius 0.138 (measured)
    x_nose = 0.5
    band(0.12, 0.15, R, M_YELLOW)
    band(-0.17, -0.14, R * 1.03, M_YELLOW)
    emit(cyl(0.018 * k, 0.02, S(20), 0.002), M_DARK, T(x_nose + 0.005, 0, 0))
    if tier == 2:
        # fuze extender rod with a disc at its end
        rod((x_nose - 0.02, 0, 0), (x_nose + 0.13, 0, 0), 0.011, M_STEEL, S(16))
        emit(cyl(0.032, 0.008, S(24), 0.0015), M_STEEL, T(x_nose + 0.13, 0, 0))
    else:
        # extender with a two-blade arming vane and a pointed tip (ends where tier 2's disc does)
        rod((x_nose - 0.02, 0, 0), (x_nose + 0.11, 0, 0), 0.013, M_STEEL, S(16))
        emit(lathe([(x_nose + 0.11, 0.02), (x_nose + 0.115, 0.02), (x_nose + 0.135, 0.0)], S(24), True, False), M_STEEL)
        emit(cyl(0.02, 0.016, S(20), 0.002), M_DARK, T(x_nose + 0.06, 0, 0))   # vane hub
        for a in (0.0, math.pi):
            emit(box((0.006, 0.07, 0.022), 0.001), M_STEEL, T(x_nose + 0.06, 0, 0) @ RX(a + 0.5) @ T(0, 0.042, 0) @ RY(0.45))
        # ballistic ring on four struts round the nose (body radius there 0.076 at tier 1)
        xr, rb = 0.4, 0.076 * k
        rr = rb + 0.032
        emit(tube_shell(rr + 0.01, rr, 0.034, S(48)), M_BODY, T(xr, 0, 0))
        for j in range(4):
            a = math.pi / 4 + j * math.pi / 2
            mid = (rb + rr) / 2
            emit(box((0.024, 0.005, rr - rb + 0.006), 0.0008), M_BODY, T(xr, math.cos(a) * mid, math.sin(a) * mid) @ RX(a - math.pi / 2))
        # strongback with two lugs on top
        emit(box((0.32, R * 0.42, 0.01), 0.002), M_STEEL, T(0.0, 0, R + 0.003))
        for x0 in (-0.09, 0.09):
            lug(x0, R + 0.008, M_STEEL, 1.8)
        band(-0.02, 0.012, R, M_BROWN)   # third band mid-body

build("%s_%d" % (kind, tier), OUT, 512, join=base)


def strip_bad_texcoord(path):
    """bpy 5.2's glTF exporter writes "texCoord": -1 on the joined Sketchfab material's textures, which is not a
    valid UV set index; drop the key so importers use UV set 0, as the tier-1 file does"""
    import json, struct
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    hits = 0
    for m in doc.get("materials", []):
        refs = [m.get("normalTexture"), m.get("occlusionTexture"), m.get("emissiveTexture")]
        pbr = m.get("pbrMetallicRoughness", {})
        refs += [pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture")]
        for r in refs:
            if r is not None and r.get("texCoord", 0) < 0:
                del r["texCoord"]
                hits += 1
    if not hits:
        return
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    rest = data[20 + jlen:]
    out = data[:12] + struct.pack("<I", len(js)) + data[16:20] + js + rest
    out = out[:8] + struct.pack("<I", len(out)) + out[12:]
    with open(path, "wb") as f:
        f.write(out)


strip_bad_texcoord(os.path.join(OUT, "%s_%d.glb" % (kind, tier)))
