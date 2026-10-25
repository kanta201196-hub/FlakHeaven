"""Turret mount stand for the hangar weapon store (S11-13, Kanta: turrets "hang in the air").
A turret is shown seated on its ring mount in a fuselage skin section, the way it is fitted to the plane:
a curved skin panel with stringers and a rivet seam, a raised mounting collar (the turret ring) with a
bolted flange on top, carried by a welded steel frame on four caster wheels.
Run (bpy 5.x):  python3 turret_stand.py [nopreview] <out_dir>
  -> out_dir/stand_turret.glb (+ .blend, preview_*.png); copy the .glb to game/models/hangar/.
Units: the turret seat (flange top) is the circle of radius SEAT_R = 1 at height SEAT_Z, X along the barrels,
Z up (glTF Y up), wheels stand on z = 0. Hangar3D scales it so the seat fits the turret's own base ring.
Matte paint (Kanta 19.10): roughness 0.8-0.9, metal only on the bolts and wheel hubs."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from turret_lib import *
import turret_lib as L
import bmesh

SEAT_R = 1.0       # flange top radius: the turret base sits inside it
SEAT_Z = 1.75      # flange top height over the floor
RF = 3.0           # skin section radius (the fuselage the turret is fitted to)
ARC = math.radians(36)   # half-angle of the skin panel
SKIN_TOP = SEAT_Z - 0.2  # top of the curved skin, the collar rises above it
HALF_X = 2.1       # half-length of the skin section


def skin_z(y, r=RF):
    """Height of the skin arc of radius r over the floor at the across offset y"""
    return SKIN_TOP - RF + math.sqrt(max(0.0, r * r - y * y))


def arc_panel(name, x0, x1, r_out, r_in, a0, a1, m, seg=28):
    """Curved panel: a slice of the skin cylinder (axis along X) between angles a0..a1 from the top"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    zc = SKIN_TOP - RF
    rows = []
    for x in (x0, x1):
        ring = []
        for r in (r_out, r_in):
            line = []
            for i in range(seg + 1):
                a = a0 + (a1 - a0) * i / seg
                line.append(bm.verts.new((x, math.sin(a) * r, zc + math.cos(a) * r)))
            ring.append(line)
        rows.append(ring)
    for i in range(seg):
        for (xa, ra), (xb, rb) in (((0, 0), (1, 0)), ((1, 1), (0, 1))):   # outer and inner surfaces
            bm.faces.new((rows[xa][ra][i], rows[xb][rb][i], rows[xb][rb][i + 1], rows[xa][ra][i + 1]))
        bm.faces.new((rows[0][0][i], rows[0][0][i + 1], rows[0][1][i + 1], rows[0][1][i]))   # front edge
        bm.faces.new((rows[1][0][i + 1], rows[1][0][i], rows[1][1][i], rows[1][1][i + 1]))   # back edge
    for k in (0, seg):   # side edges
        bm.faces.new((rows[0][0][k], rows[0][1][k], rows[1][1][k], rows[1][0][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    return finish(ob, m)


def build_stand(M_SKIN, M_FRAME, M_DARK, M_METAL):
    """Geometry of the stand in its own units (see the module docstring)"""
    L.group = ""
    # --- skin section with stringers, frame seams and rivets ---
    arc_panel("skin", -HALF_X, HALF_X, RF, RF - 0.07, -ARC, ARC, M_SKIN, 36)
    for a in (-0.75, -0.42, 0.42, 0.75):   # stringers outside the collar
        aa = a * ARC
        y = math.sin(aa) * (RF + 0.01)
        z = SKIN_TOP - RF + math.cos(aa) * (RF + 0.01)
        ob = box("stringer", (0.0, y, z), (2 * HALF_X - 0.1, 0.05, 0.03), M_SKIN, 0.008)
        ob.rotation_euler = (-aa, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
    for x in (-HALF_X + 0.25, HALF_X - 0.25):   # frame seams across the skin, with rivets
        arc_panel("frame_seam", x - 0.035, x + 0.035, RF + 0.012, RF - 0.02, -ARC + 0.02, ARC - 0.02, M_DARK, 28)
        for i in range(15):
            a = -ARC * 0.92 + 2 * ARC * 0.92 * i / 14
            if abs(math.sin(a) * RF) < 1.35:
                continue   # under the collar
            cyl("rivet", (x + 0.09, math.sin(a) * (RF + 0.01), SKIN_TOP - RF + math.cos(a) * (RF + 0.01)),
                0.022, 0.02, M_METAL, "Z", 8)
    # --- turret ring mount: doubler plate, collar, flange with bolts ---
    cyl("doubler", (0, 0, SKIN_TOP - 0.19), 1.42, 0.42, M_SKIN, "Z", 48, 0.02)   # reaches into the curved skin
    cyl("collar", (0, 0, SEAT_Z - 0.3), 1.12, 0.6, M_SKIN, "Z", 48, 0.015)
    cyl("collar_seam", (0, 0, SEAT_Z - 0.29), 1.135, 0.03, M_DARK, "Z", 48)
    cyl("flange", (0, 0, SEAT_Z - 0.035), SEAT_R + 0.2, 0.07, M_FRAME, "Z", 48, 0.012)
    cyl("race", (0, 0, SEAT_Z + 0.004), SEAT_R + 0.04, 0.012, M_DARK, "Z", 48)
    for i in range(20):
        a = i * math.tau / 20
        cyl("bolt", (math.cos(a) * (SEAT_R + 0.13), math.sin(a) * (SEAT_R + 0.13), SEAT_Z + 0.01), 0.03, 0.04, M_METAL, "Z", 8)
    for i in range(12):   # doubler rivets
        a = i * math.tau / 12 + 0.13
        cyl("rivet", (math.cos(a) * 1.3, math.sin(a) * 1.3, SKIN_TOP + 0.025), 0.022, 0.02, M_METAL, "Z", 8)
    # data plate on the collar (blank: no markings)
    box("plate", (1.12, 0.0, SEAT_Z - 0.17), (0.02, 0.32, 0.16), M_DARK, 0.004)

    # --- welded frame: saddles under the skin, legs, base rails, casters ---
    LX, LY, BASE_Z = HALF_X - 0.3, 1.45, 0.34
    for x in (-LX, LX):
        # saddle beam across, following the skin underside
        for y0, y1 in ((-LY - 0.1, -0.5), (0.5, LY + 0.1)):
            ym = (y0 + y1) / 2
            box("saddle", (x, ym, skin_z(abs(ym), RF - 0.07) - 0.09), (0.14, y1 - y0, 0.12), M_FRAME, 0.01)
        box("cross", (x, 0, BASE_Z + 0.05), (0.12, 2 * LY, 0.12), M_FRAME, 0.01)
    for x in (-LX, LX):
        for y in (-LY, LY):
            top = skin_z(LY, RF - 0.07) - 0.14
            box("leg", (x, y, (BASE_Z + top) / 2), (0.13, 0.13, top - BASE_Z), M_FRAME, 0.01)
            tube("brace", [(x * 0.55, y, BASE_Z + 0.08), (x * 0.97, y, top - 0.1)], 0.035, M_FRAME)
            # caster: fork, wheel, hub
            box("fork", (x, y, BASE_Z - 0.07), (0.16, 0.18, 0.06), M_DARK, 0.01)
            cyl("wheel", (x, y, 0.17), 0.17, 0.11, M_DARK, "Y", 20, 0.02)
            cyl("hub", (x, y, 0.17), 0.07, 0.125, M_METAL, "Y", 12)
    for y in (-LY, LY):
        box("rail", (0, y, BASE_Z), (2 * LX + 0.13, 0.13, 0.13), M_FRAME, 0.01)
    # tow bar in front, folded up
    tube("tow", [(LX + 0.07, -0.45, BASE_Z + 0.02), (LX + 0.42, -0.25, BASE_Z + 0.25),
                 (LX + 0.42, 0.25, BASE_Z + 0.25), (LX + 0.07, 0.45, BASE_Z + 0.02)], 0.04, M_FRAME)


if __name__ == "__main__":
    OUT = sys.argv[-1] if len(sys.argv) > 1 else "."
    L.reset()
    M_SKIN = mat("stand_skin", (0.34, 0.35, 0.31), 0.06, 0.88)     # primer-grey skin section
    M_FRAME = mat("stand_frame", (0.5, 0.42, 0.18), 0.12, 0.82)    # workshop-yellow painted steel, faded
    M_DARK = mat("stand_dark", (0.07, 0.07, 0.075), 0.1, 0.85)
    M_METAL = mat("stand_metal", (0.42, 0.42, 0.41), 0.6, 0.55)
    build_stand(M_SKIN, M_FRAME, M_DARK, M_METAL)
    build("stand_turret", OUT)
    if "nopreview" not in sys.argv:
        preview(OUT, [("iso", (7.5, -8.5, 6.0), (0, 0, 1.0), 50), ("side", (0, -11.0, 1.2), (0, 0, 1.0), 50)])
    print("DONE")
