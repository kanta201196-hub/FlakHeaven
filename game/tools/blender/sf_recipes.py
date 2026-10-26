"""Recipes for sf_rework.py: one entry per game model made from a Sketchfab source (VIS-01, Kanta 24.10.2026).

Keys (coordinates are Blender, after placing: nose +X, up +Z, left +Y, length 1):
  root       name of the root node (as in the previous game GLB)
  rot        source rotation, degrees (X, Y, Z), applied before scaling
  ground     True: lowest point on z = 0 (vehicles); False: centred (aircraft)
  len_exclude  regex of objects ignored when measuring length (rotor blades)
  drop       regex of source objects to delete
  split      regex of objects to split into loose parts (single-mesh sources) before grouping
  wheels     road wheel search (sf_rework.find_wheels): match, steer (front steered axles), rmin, rmax, ymin
  groups     node -> rules [("name", regex) | ("box", (x0, x1, y0, y1, z0, z1))] on the part centre
  pivots     node -> (x, y, z) | "center" | "base"   (where the game rotates the node)
  parents    node -> parent node (default: root)
  materials  [(regex on source material name, rule)]; rule: mode auto|paint|keep|glass, hue ranges, smin,
             color (force flat sRGB), desat, tint, rough, metal, nstr
  erase      source material name -> [(u0, v0, u1, v1)] glTF UV rectangles painted over (markings, lettering)
  paint      camo (sRGB palette), scale, stretch, belly, marks [(box, colour)], dust, rough (lo, hi), wear, fade
  tris       battle triangle budget; weight: node -> budget weight; fixed: node -> exact budget
Source credits: game/models/CREDITS.md."""

# Нагорье convoy and ground AA: sand / ochre / brown spots (Kanta 17.10, convoy_kit.CAMO), matte with satin sheen
SAND = {"camo": [(0.62, 0.52, 0.36), (0.50, 0.40, 0.27), (0.36, 0.30, 0.21)], "scale": 1.0,
        "rough": (0.76, 0.84), "wear": 0.6, "detail": 0.85, "dust": 0.6}
# enemy helicopter: sandy khaki and grey-green spots, blue-grey belly (helicopter.py, Kanta 18.10)
HELI = {"camo": [(0.33, 0.38, 0.335), (0.6, 0.585, 0.44), (0.3, 0.35, 0.31)], "scale": 1.9, "stretch": (0.75, 1.0, 1.3),
        "belly": (0.46, 0.51, 0.55), "dust": 0.25, "rough": (0.76, 0.84), "wear": 0.5, "detail": 0.8}
# enemy jets: dark grey two-tone, lighter belly, muted red tips (enemy_air.py scheme())
JET_RED = (0.55, 0.15, 0.11)
JET = {"camo": [(0.25, 0.255, 0.265), (0.31, 0.315, 0.32), (0.2, 0.205, 0.215)], "scale": 1.5, "stretch": (0.6, 1.0, 1.0),
       "belly": (0.42, 0.43, 0.44), "dust": 0.0, "rough": (0.74, 0.82), "wear": 0.45, "detail": 0.75,
       "wear_col": (0.5, 0.5, 0.5), "fade": 0.04, "fade_col": (0.6, 0.6, 0.6)}

# player fighter «Оса» lvl 1 for the Highlands (Kanta 24.10: "repaint Osa 1 for the Highlands"): the light grey read
# almost white on the beige sand, so the upper surfaces get a matte disruptive desert camo clearly darker and more
# saturated than the ground: dark olive-brown, sand-brown (the most area), grey-tan spots; light blue-grey belly.
# Same family as the attacker / bomber «Песочный камуфляж» (livery.gd SAND_CAMO: light belly) but darker and browner,
# so the fighter is told apart from them. Order matters: camo[1] covers ~45 %, camo[0] ~35 %, camo[2] ~20 %.
HIGHLAND = {"camo": [(0.21, 0.20, 0.135), (0.40, 0.30, 0.20), (0.36, 0.34, 0.29)], "scale": 1.1,
            "stretch": (0.6, 1.0, 1.0), "belly": (0.58, 0.62, 0.66), "dust": 0.0, "rough": (0.76, 0.84),
            "wear": 0.3, "detail": 0.8, "wear_col": (0.50, 0.46, 0.38), "fade": 0.04, "fade_col": (0.62, 0.56, 0.45),
            "streak": 0.08}
# previous «Оса» lvl 1 paint (VIS-01 first install): clean light / medium grey two-tone, lighter belly, no marks
GREY = {"camo": [(0.50, 0.52, 0.54), (0.61, 0.63, 0.65)], "scale": 1.3, "stretch": (0.6, 1.0, 1.0),
        "belly": (0.72, 0.73, 0.74), "dust": 0.0, "rough": (0.62, 0.72), "wear": 0.25, "detail": 0.8,
        "wear_col": (0.66, 0.67, 0.68), "fade": 0.03, "fade_col": (0.75, 0.76, 0.77), "streak": 0.08}

# vehicle olive paint (most sources): green-yellow hues
OLIVE = {"mode": "auto", "hue": [(38, 150)], "smin": 0.12}
TYRE = {"mode": "keep", "rough": 0.92, "desat": 0.6}
GLASS = {"mode": "glass", "rough": 0.3, "color": (0.06, 0.075, 0.085)}
STEEL = {"mode": "keep", "rough": 0.6, "metal": 0.4, "desat": 0.5}

def _flat_mat(name, rgb, rough, metal):
    """Plain glTF-like material for parts made in code (sf_rework.repaint reads base colour like an import)."""
    import bpy
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[((c + 0.055) / 1.055) ** 2.4 for c in rgb], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def technical_hmg():
    """Heavy machine gun on a pintle in the pickup bed (Kanta 24.10: "add a mounted HMG").
    Fictional 12.7 mm class gun, sized for a 5.2 m pickup (length 1 = 5.2 m): finned barrel jacket, muzzle brake,
    receiver with spade grips, ammo box on the left, small bent gun shield. Pintle post with three braces stands on the
    bed floor (z = 0.151) at x = -0.25, top at z = 0.35 — the turret pivot; the gun axis is at z = 0.378, over the cab
    roof (z = 0.33), so the gun can fire forward. Objects named hmg_b_* (fixed, root) and hmg_t_* (node turret)."""
    import math
    import bpy
    import convoy_kit as K
    from convoy_kit import box, cyl, tube
    K.parts.clear()
    px, pz, gz = -0.25, 0.35, 0.378
    steel = _flat_mat("hmg_steel", (0.13, 0.13, 0.125), 0.55, 0.6)
    olive = _flat_mat("hmg_olive", (0.30, 0.30, 0.22), 0.8, 0.0)
    paint = _flat_mat("hmg_paint", (0.40, 0.42, 0.26), 0.8, 0.0)
    base = [cyl("hmg_b_plate", (px, 0, 0.154), 0.028, 0.006, "steel", n=16),
            cyl("hmg_b_post", (px, 0, (0.151 + pz) / 2), 0.0085, pz - 0.151, "steel", n=12)]
    for i, a in enumerate((90.0, 210.0, 330.0)):
        dx, dy = math.cos(math.radians(a)) * 0.075, math.sin(math.radians(a)) * 0.075
        base.append(tube("hmg_b_leg%d" % i, [(px, 0, 0.25), (px + dx, dy, 0.153)], 0.0045, "steel", n=6))
    top = [cyl("hmg_t_swivel", (px, 0, pz + 0.008), 0.0135, 0.016, "steel", n=14),
           box("hmg_t_yoke_l", (px + 0.004, 0.019, gz - 0.008), (0.045, 0.006, 0.036), "steel", bevel=0.0),
           box("hmg_t_yoke_r", (px + 0.004, -0.019, gz - 0.008), (0.045, 0.006, 0.036), "steel", bevel=0.0),
           box("hmg_t_receiver", (px - 0.008, 0, gz), (0.095, 0.029, 0.034), "steel", bevel=0.002),
           box("hmg_t_cover", (px - 0.004, 0, gz + 0.019), (0.07, 0.024, 0.006), "steel", bevel=0.0),
           cyl("hmg_t_jacket", (px + 0.075, 0, gz + 0.002), 0.0115, 0.075, "steel", axis="X", n=14),
           cyl("hmg_t_barrel", (px + 0.165, 0, gz + 0.002), 0.0062, 0.13, "steel", axis="X", n=10),
           cyl("hmg_t_brake", (px + 0.235, 0, gz + 0.002), 0.0105, 0.02, "steel", axis="X", n=12),
           box("hmg_t_sight", (px + 0.03, 0, gz + 0.026), (0.006, 0.004, 0.014), "steel", bevel=0.0),
           box("hmg_t_ammo", (px - 0.004, 0.034, gz - 0.006), (0.05, 0.024, 0.034), "olive", bevel=0.002),
           box("hmg_t_shield", (px + 0.05, 0, gz + 0.004), (0.005, 0.1, 0.058), "paint", bevel=0.0),
           box("hmg_t_shield_l", (px + 0.041, 0.056, gz + 0.004), (0.02, 0.005, 0.058), "paint", bevel=0.0,
               rot=("Z", -30.0)),
           box("hmg_t_shield_r", (px + 0.041, -0.056, gz + 0.004), (0.02, 0.005, 0.058), "paint", bevel=0.0,
               rot=("Z", 30.0))]
    for k in range(6):   # cooling fins on the jacket
        top.append(cyl("hmg_t_fin%d" % k, (px + 0.045 + k * 0.012, 0, gz + 0.002), 0.0145, 0.003, "steel", axis="X", n=14))
    for s in (1, -1):
        top.append(tube("hmg_t_grip%d" % (s > 0), [(px - 0.055, s * 0.01, gz), (px - 0.07, s * 0.012, gz - 0.012)],
                        0.0035, "steel", n=6))
    obs = base + top
    for o in obs:
        bpy.context.view_layer.objects.active = o
        for md in list(o.modifiers):
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.ops.object.modifier_apply(modifier=md.name)
        o.data.materials.clear()
        o.data.materials.append(olive if "ammo" in o.name else paint if "shield" in o.name else steel)
    return obs


def pickup_tent_cover():
    """Canvas tilt over the bed of the light pickup (Kanta 26.10: the tent pickup on the same base as the technical,
    so the two read as one family). Bed of the 00amza pickup (length 1 = 5.2 m): floor z = 0.151, x -0.464…-0.094,
    sides at |y| = 0.15 with the rail at z ≈ 0.21 (cab roof 0.33), cab back wall at x ≈ -0.08. The tilt stands on the
    rails: straight walls up to z 0.33, arched roof to z 0.40, sagging a little between four hoops; the hoops and
    lashing straps are darker.
    Objects named tent_* (node tent: hidden on a wreck, render3d.gd)."""
    import math
    import bpy
    import convoy_kit as K
    from convoy_kit import loft, tube
    K.parts.clear()
    canvas = _flat_mat("tent_canvas", (0.44, 0.40, 0.29), 0.95, 0.0)
    strap = _flat_mat("tent_strap", (0.27, 0.25, 0.19), 0.95, 0.0)
    x0, x1, w, zw, zr = -0.468, -0.088, 0.155, 0.33, 0.40
    hoops = [x0 + (x1 - x0) * k / 3 for k in range(4)]

    def section(x, sag):
        pts = [(x, -w, 0.205), (x, -w, zw - sag)]
        for i in range(1, 8):   # arch from wall top to wall top
            a = math.pi * i / 8
            pts.append((x, -w * math.cos(a), zw - sag + (zr - zw) * math.sin(a)))
        pts += [(x, w, zw - sag), (x, w, 0.205)]
        return pts

    secs = []
    for k in range(13):
        x = x0 + (x1 - x0) * k / 12
        d = min(abs(x - h) for h in hoops) / ((x1 - x0) / 6)   # 0 at a hoop, 1 midway
        secs.append(section(x, 0.008 * math.sin(math.pi * d / 2)))
    obs = [loft("tent_canvas", secs, "olive")]
    for h in hoops:   # hoop bands just outside the canvas
        pts = [(h, p[1] * 1.03, p[2] + (0.003 if p[2] > zw else 0.0)) for p in section(h, 0.0)]
        obs.append(tube("tent_hoop", pts, 0.004, "olive", n=6))
    for s in (1, -1):   # lashing rail along the bed side
        obs.append(tube("tent_rail", [(x0, s * w * 1.02, 0.215), (x1, s * w * 1.02, 0.215)], 0.004, "olive", n=6))
    for o in obs:
        bpy.context.view_layer.objects.active = o
        for md in list(o.modifiers):
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.ops.object.modifier_apply(modifier=md.name)
        o.data.materials.clear()
        o.data.materials.append(canvas if o.name.startswith("tent_canvas") else strap)
    return obs


def manpads_crew():
    """MANPADS gunner in the bed of the light pickup (Kanta 26.10, shortlist 95: the launcher model on the same truck
    as the technical and the tent pickup). Kanta 26.10: the old two-man crew of tube figures read as crude, so the bed
    carries ONE properly proportioned soldier (1.8 m, built in metres and scaled to the truck: length 1 = 5.2 m):
    braced stance with the left foot forward, boots, knee pad, belt, plate carrier with pouches, a small pack, a
    shemagh round the neck and a helmet; the launcher lies on his RIGHT shoulder with the cheek against it, the right
    hand on the gripstock and the left hand under the tube in front of it, pointing forward over the cab. Missile
    cases, a spare tube and ammo boxes lie in the bed. Bed of the 00amza pickup: floor z = 0.151,
    x -0.464…-0.094, |y| < 0.15. Uniform sand, vest and helmet olive, no markings.
    The launcher is the shortlisted Sketchfab model (path in env FH_MANPADS_TUBE; CREDITS.md): the display missile
    and its fins are dropped, the front end (-X in the source) turned to +X, scaled to a 1.6 m tube (0.31) and put on
    the shoulder point. Paint is flat (recipe), so no stencils of the source survive.
    Objects mpl_* (tube, both arms and gloves) form the node launcher, pivot = the shoulder point (gx, 0, sh) where
    render3d.gd raises it when locking; the shoulders sit near that axis, so the arms stay attached; mpc_* stay on
    the root."""
    import math
    import os
    import re
    import bpy
    from mathutils import Matrix, Vector
    import convoy_kit as K
    from convoy_kit import box, cyl
    K.parts.clear()
    M = 1.0 / 5.2                       # metres -> truck units
    tz = 0.155                          # standing surface (bed floor + liner)
    gx, ty = -0.34, 0.0                 # shoulder rest of the tube (launcher pivot x, y)
    sh = tz + 1.525 * M                 # tube axis height = pivot z (recipe "pivots")
    bx, by = gx - 0.04 * M, ty + 0.13 * M
    kinds = {}

    def W(p):
        return Vector((bx + p[0] * M, by + p[1] * M, tz + p[2] * M))

    def tag(o, kind):
        kinds[o.name] = kind
        return o

    def limb(name, pts, radii, kind, n=10):
        """A tapered sleeve along a polyline (parallel-transport rings), radii per point, in metres."""
        P = [W(p) for p in pts]
        T = [(P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized() for i in range(len(P))]
        u = T[0].orthogonal().normalized()
        vs = []
        for i, c in enumerate(P):
            u = (u - T[i] * u.dot(T[i])).normalized()
            v = T[i].cross(u)
            for j in range(n):
                a = 2 * math.pi * j / n
                vs.append(c + (u * math.cos(a) + v * math.sin(a)) * radii[i] * M)
        f = [(i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j)
             for i in range(len(P) - 1) for j in range(n)]
        f += [tuple(range(n))[::-1], tuple(range((len(P) - 1) * n, len(P) * n))]
        return tag(K._obj(name, vs, f, "olive"), kind)

    def trunk(name, rings, kind, n=14, sq=0.25):
        """Loft of rounded rings (x, z, half depth, half width) in metres; sq pushes the ellipse towards a box."""
        secs = []
        for x, z, rx, ry in rings:
            ring = []
            for j in range(n):
                a = 2 * math.pi * j / n
                k = 1.0 + sq * abs(math.sin(2 * a)) * 0.3
                ring.append(W((x + rx * math.cos(a) * k, ry * math.sin(a) * k, z)))
            secs.append(ring)
        return tag(K.loft(name, secs, "olive"), kind)

    def blob(name, c, r, kind, n=10, m=6):
        """Ellipsoid (radii r = (rx, ry, rz) in metres) for the head, hands, shoulders and pads."""
        c = W(c)
        vs = [c + Vector((0, 0, -r[2] * M))]
        for i in range(1, m):
            t = math.pi * i / m
            for j in range(n):
                a = 2 * math.pi * j / n
                vs.append(c + Vector((r[0] * math.sin(t) * math.cos(a), r[1] * math.sin(t) * math.sin(a),
                                      -r[2] * math.cos(t))) * M)
        vs.append(c + Vector((0, 0, r[2] * M)))
        f = [(0, 1 + (j + 1) % n, 1 + j) for j in range(n)]
        for i in range(m - 2):
            a0, a1 = 1 + i * n, 1 + (i + 1) * n
            f += [(a0 + j, a0 + (j + 1) % n, a1 + (j + 1) % n, a1 + j) for j in range(n)]
        top = len(vs) - 1
        f += [(top, 1 + (m - 2) * n + j, 1 + (m - 2) * n + (j + 1) % n) for j in range(n)]
        return tag(K._obj(name, vs, f, "olive"), kind)

    def mbox(name, c, s, kind, yaw=0.0, bevel=0.01):
        rot = Matrix.Rotation(math.radians(yaw), 3, "Z")
        return tag(box(name, tuple(W(c)), tuple(v * M for v in s), "olive", bevel * M, rot=rot), kind)

    # legs: braced stance, left foot forward, right foot back; boots
    for side, ank, knee, hip in ((1, (0.15, 0.12, 0.1), (0.19, 0.11, 0.52), (0.0, 0.095, 0.93)),
                                 (-1, (-0.16, -0.13, 0.1), (-0.07, -0.115, 0.5), (0.0, -0.095, 0.93))):
        th = tuple((h + k) / 2 for h, k in zip(hip, knee))
        ca = tuple((k + a) / 2 for k, a in zip(knee, ank))
        limb("mpc_leg", [hip, th, knee, ca, ank], [0.095, 0.085, 0.066, 0.06, 0.05], "cloth")
        yaw = 8.0 * side
        mbox("mpc_boot", (ank[0] + 0.05, ank[1], 0.055), (0.28, 0.105, 0.11), "boot", yaw, 0.03)
        mbox("mpc_sole", (ank[0] + 0.05, ank[1], 0.012), (0.29, 0.11, 0.024), "black", yaw, 0.008)
    blob("mpc_kneepad", (0.24, 0.11, 0.52), (0.05, 0.06, 0.07), "olive")
    mbox("mpc_thigh_pouch", (0.02, -0.18, 0.72), (0.12, 0.05, 0.16), "olive", 0.0, 0.02)
    # torso leaning into the tube, belt, plate carrier, pack
    trunk("mpc_torso", [(0.0, 0.86, 0.11, 0.17), (0.0, 0.98, 0.105, 0.165), (0.01, 1.08, 0.1, 0.155),
                        (0.025, 1.22, 0.115, 0.175), (0.03, 1.36, 0.11, 0.19), (0.035, 1.44, 0.08, 0.16),
                        (0.04, 1.49, 0.05, 0.07)], "cloth")
    trunk("mpc_belt", [(0.0, 0.94, 0.118, 0.176), (0.0, 1.0, 0.115, 0.174)], "dark", sq=0.6)
    trunk("mpc_vest", [(0.012, 1.02, 0.13, 0.17), (0.022, 1.16, 0.135, 0.18), (0.03, 1.34, 0.128, 0.182),
                       (0.034, 1.4, 0.11, 0.15)], "olive", sq=1.0)
    for yy in (-0.09, 0.0, 0.09):
        mbox("mpc_pouch", (0.17, yy, 1.1), (0.05, 0.075, 0.12), "olive", 0.0, 0.015)
    mbox("mpc_radio", (-0.12, 0.12, 1.06), (0.07, 0.07, 0.15), "dark", 0.0, 0.015)
    mbox("mpc_pack", (-0.17, 0.0, 1.22), (0.12, 0.28, 0.3), "olive", 0.0, 0.04)
    tag(cyl("mpc_canteen", tuple(W((-0.06, 0.17, 0.9))), 0.045 * M, 0.15 * M, "olive", "Z", 10), "olive")
    for s in (1, -1):
        blob("mpc_shoulder", (0.04, s * 0.19, 1.4), (0.08, 0.075, 0.075), "cloth")
    # neck, shemagh, head (cheek on the tube), helmet
    tag(cyl("mpc_neck", tuple(W((0.045, 0.01, 1.52))), 0.055 * M, 0.1 * M, "olive", "Z", 10), "skin")
    trunk("mpc_shemagh", [(0.04, 1.45, 0.095, 0.11), (0.045, 1.5, 0.085, 0.095), (0.05, 1.56, 0.07, 0.075)],
          "scarf", sq=0.0)
    hx, hy, hz = 0.07, 0.03, 1.64
    blob("mpc_head", (hx, hy, hz), (0.1, 0.085, 0.12), "skin", 14, 8)
    blob("mpc_nose", (hx + 0.1, hy, hz - 0.01), (0.02, 0.016, 0.03), "skin", 6, 4)
    blob("mpc_helmet", (hx - 0.005, hy, hz + 0.035), (0.13, 0.115, 0.11), "helmet", 16, 8)
    trunk("mpc_helmet_rim", [(hx - 0.005, hz + 0.03, 0.135, 0.12), (hx - 0.005, hz + 0.045, 0.133, 0.118)],
          "helmet", 16, 0.0)
    mbox("mpc_goggles", (hx + 0.06, hy, hz + 0.1), (0.07, 0.17, 0.04), "dark", 0.0, 0.015)
    trunk("mpc_strap", [(hx, hz - 0.11, 0.095, 0.06), (hx, hz - 0.08, 0.1, 0.09)], "dark", 12, 0.0)
    # arms with the launcher (node launcher): right hand on the gripstock, left hand under the tube ahead of it
    for nm, pts, hand in (
            ("mpl_arm_r", [(0.04, -0.2, 1.41), (0.09, -0.25, 1.29), (0.14, -0.29, 1.18), (0.25, -0.21, 1.27),
                           (0.33, -0.14, 1.35)], (0.36, -0.13, 1.37)),
            ("mpl_arm_l", [(0.07, 0.18, 1.41), (0.2, 0.12, 1.34), (0.33, 0.06, 1.27), (0.45, -0.04, 1.36),
                           (0.54, -0.12, 1.43)], (0.57, -0.13, 1.455))):
        limb(nm, pts, [0.078, 0.068, 0.056, 0.05, 0.042], "cloth")
        blob(nm.replace("arm", "glove"), hand, (0.055, 0.045, 0.05), "glove")
    # props in the bed: missile cases and a spare tube by the cab, ammo boxes at the tailgate
    for k in range(2):
        tag(box("mpc_case", (-0.19, 0.112, tz + 0.02 + k * 0.04), (0.18, 0.05, 0.04), "olive", 0.003), "olive")
    tag(cyl("mpc_spare_tube", (-0.2, 0.112, tz + 0.096), 0.009, 0.24, "olive", "X", 10), "olive")
    for k in range(2):
        tag(box("mpc_ammo_box", (-0.43, -0.11 + k * 0.05, tz + 0.02), (0.05, 0.04, 0.04), "olive", 0.003), "olive")
    obs = list(K.parts)
    flat = {"cloth": (0.47, 0.41, 0.29), "skin": (0.52, 0.37, 0.27), "olive": (0.33, 0.35, 0.24),
            "helmet": (0.37, 0.37, 0.27), "scarf": (0.66, 0.6, 0.48), "boot": (0.2, 0.15, 0.1),
            "glove": (0.16, 0.15, 0.12), "dark": (0.14, 0.14, 0.12), "black": (0.06, 0.06, 0.06)}
    for o in obs:
        kind = kinds.get(o.name, "olive")
        bpy.context.view_layer.objects.active = o
        for md in list(o.modifiers):
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.ops.object.modifier_apply(modifier=md.name)
        o.data.materials.clear()
        o.data.materials.append(_flat_mat("mp_" + kind, flat[kind], 0.9, 0.0))
    # the launcher: source tube axis on x (front -X), y = 0, z = 0; shoulder rest at x = 10 (behind the grip)
    old = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.environ["FH_MANPADS_TUBE"])
    s = 0.31 / 36.5
    m = Matrix.Translation((gx, ty, sh)) @ Matrix.Scale(s, 4) @ Matrix.Rotation(math.pi, 4, "Z") \
        @ Matrix.Translation((-10.0, 0.0, 0.0))
    for o in [o for o in bpy.data.objects if o not in old]:
        if o.type != "MESH" or re.search(r"(?i)rocket|stab", o.name) or not o.data.polygons:
            continue
        mw = o.matrix_world.copy()
        if o.data.users > 1:
            o.data = o.data.copy()
        o.parent = None
        o.data.transform(m @ mw)
        o.matrix_world = Matrix.Identity(4)
        o.name = "mpl_" + o.name
        obs.append(o)
    for o in [o for o in bpy.data.objects if o not in old and o not in obs]:
        bpy.data.objects.remove(o)
    return obs


def fighter_1_bay_covers():
    """Closed gear doors for «Оса» lvl 1: the source is modelled gear down, with open wells under the nose and on
    both sides of the belly; the game shows the plane in flight, so the wells get flush covers (measured by vertical
    rays on the placed source: nose well x 0.142…0.248, |y| < 0.014; main wells x -0.16…-0.088, |y| 0.015…0.05).
    Each cover is a slightly curved plate following the belly next to the well, painted like the skin."""
    import bpy
    import bmesh
    mat = _flat_mat("f1_bay_paint", (0.55, 0.56, 0.57), 0.7, 0.0)
    obs = []

    def plate(name, x0, x1, y0, y1, zf, nx=8, ny=4, out=(0.0, 0.0, -1.0), pt=None):
        """Grid plate over x and a second coordinate; pt(x, t) -> (x, y, z) for t in y0..y1 (default (x, t, zf));
        faces turned toward the outward direction `out`."""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        pt = pt or (lambda x, t: (x, t, zf(x, t)))
        grid = [[bm.verts.new(pt(x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny))
                 for j in range(ny + 1)] for i in range(nx + 1)]
        for i in range(nx):
            for j in range(ny):
                f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
                f.normal_update()
                if f.normal.dot(out) < 0:
                    f.normal_flip()
        bm.to_mesh(me)
        bm.free()
        me.uv_layers.new(name="UVMap")
        me.materials.append(mat)
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        obs.append(o)

    # nose well: belly beside it falls from z -0.060 (x 0.25) to -0.066 (x 0.14) at |y| 0.02, centre 0.004 lower
    plate("f1_cover_nose", 0.138, 0.252, -0.019, 0.019,
          lambda x, y: -0.060 - (0.252 - x) * 0.053 - 0.004 * (1.0 - (y / 0.02) ** 2))
    for s in (1, -1):   # main wells: belly z -0.081 at |y| 0.015 up to -0.067 at |y| 0.05
        plate("f1_cover_main_%s" % ("l" if s > 0 else "r"), -0.164, -0.084, s * 0.013, s * 0.052,
              lambda x, y: -0.081 + (abs(y) - 0.015) * 0.4 - (-0.084 - x) * 0.05)
        # the wells are open on the fuselage side too, between the cover and the wing glove (z -0.068 … -0.018)
        plate("f1_cover_side_%s" % ("l" if s > 0 else "r"), -0.164, -0.084, -0.0685, -0.016, None, ny=3,
              out=(0.0, float(s), 0.0), pt=lambda x, t, s=s: (x, s * 0.0515, t))
    return obs


# «Оса» lvl 1 source parts left out: the cockpit interior (the canopy glass shader is opaque, so it is never seen),
# the landing gear with its open doors (the game shows the plane in flight), the source's own missiles, belly tank
# and its pylon (the game hangs its own stores), the ventral fin folded for landing and the duplicate windscreen pane
DROP_F1 = (r"^kabina_|^OBJ0290_|^OBJ381_|^OBJ144_|^[a-z0-9]+_fuz_(017sini|010panel|upl|005bl|014roz)|^OBJ019[2-6]_"
           r"|^OBJ185_|^OBJ0308_|^Plane001_|^OBJ097_|^OBJ088_"
           r"|^OBJ0041_|^stoykanos_|^nos_|^OBJ0355_|^OBJ004[367]_|^OBJ006[13]_"
           r"|^OBJ01(0[89]|1\d|2[0-5]|3\d|4\d|5\d|6\d|7[0-7]|8[12])_"
           r"|^r\d+_r\d+_\d|^OBJ0204_|^Object002_|^OBJ0024_|^OBJ0277_|^OBJ00(44|62)_")
# markings on the fuselage atlas (glTF UV of the source "fuzcamo" image): fin stars and numbers, side numbers,
# nose art, unit badges, wing stars top and bottom
ERASE_F1 = [(0.064, 0.102, 0.122, 0.162), (0.066, 0.425, 0.122, 0.484),       # fin stars
            (0.113, 0.088, 0.137, 0.117), (0.05, 0.479, 0.068, 0.502),       # fin numbers
            (0.278, 0.052, 0.334, 0.097), (0.28, 0.654, 0.332, 0.7),         # side numbers
            (0.206, 0.034, 0.28, 0.07), (0.206, 0.682, 0.28, 0.718),         # nose art and its eyes
            (0.382, 0.05, 0.43, 0.106), (0.382, 0.642, 0.432, 0.702),        # unit badges
            (0.83, 0.161, 0.867, 0.198), (0.83, 0.559, 0.867, 0.595),        # wing stars, top
            (0.453, 0.158, 0.496, 0.198), (0.453, 0.558, 0.494, 0.597),      # wing stars, bottom
            (0.058, 0.578, 0.1, 0.638),                                       # dark placard
            (0.122, 0.125, 0.146, 0.141), (0.044, 0.461, 0.07, 0.477)]        # fin stencil bars

RECIPES = {
    "fighter_1": {
        "root": "fighter_1", "rot": (0, 0, 90), "ground": False,
        "drop": DROP_F1, "build": fighter_1_bay_covers,
        "materials": [(r"glass$|014roz", GLASS),
                      (r"fuzcamo", {"mode": "paint", "flatten": 13}), (r"f1_bay_paint", {"mode": "paint"}),
                      # dark grey skin pieces (radome, overlays lying on the wing and glove) take the paint too:
                      # left dark, the bake picks them or the skin under them at random and the wing gets blotches
                      (r"nosser", {"mode": "paint"}),
                      (r".", {"mode": "keep", "desat": 0.75, "rough": 0.6})],
        "erase": {"fuzcamo": ERASE_F1}, "mat_names": {"glass": "glass"}, "img_plain": True,
        # S11-07: the source's own glove pylons (loose plates inside the composite "mig23mld_fuz_nab" object) read
        # as an empty second missile mount next to the game's pylon; f1_glove_pylons.py cuts them from a finished GLB
        "kill_faces": [(r"_fuz_nab_", (-0.115, 0.062, 0.083, 0.097, -0.036, -0.003)),
                       (r"_fuz_nab_", (-0.115, 0.062, -0.097, -0.083, -0.036, -0.003))],
        "uv_split_x": [-0.3, -0.1, 0.1, 0.3],   # fuselage-long islands would leave half the atlas empty
        "paint": HIGHLAND, "tris": 12000,
    },
    "e_zsu": {
        "root": "ground_zsu", "rot": (0, 0, 0), "ground": True,
        "materials": [(r"(?i)glass|lens|stek", GLASS), (r".", OLIVE)],
        "groups": {"turret": [("box", (-0.32, 0.55, -0.24, 0.24, 0.255, 1.0))]},
        "pivots": {"turret": (0.035, -0.004, 0.25)},
        # track runs are hundreds of loose links, grilles are perforated plates: both floor collapse
        # decimation near 75k tris, so the low mesh gets stand-ins and the bake keeps their detail
        "low_voxel": r"^G_M-", "low_hull": r"^(K_B_U|K_U_V|D_S_P|Material_018)-",
        "paint": SAND, "tris": 18000,
    },
    "e_convoy_truck": {
        "root": "convoy_truck", "rot": (0, 0, 90), "ground": True,
        "wheel_cyl": {"steer": 1, "axles": [0.295, -0.17, -0.35], "z": 0.076, "r": 0.079, "y": (0.115, 0.2)},
        "materials": [(r"material_1$", GLASS), (r".", dict(OLIVE, hue=[(44, 150)], smin=0.13, vmax=0.5))],
        "keep": {"material_0": [(0.40, 0.19, 1.0, 0.435), (0.65, 0.43, 0.985, 0.545)]},   # canvas cover stays canvas
        "erase": {"material_0": [(0.285, 0.77, 0.43, 0.82)]},   # maker's name plate on the bonnet sides
        "paint": SAND, "tris": 13000,
    },
    "e_convoy_ifv": {
        "root": "convoy_ifv", "rot": (0, 0, -90), "ground": True, "split": ".",
        "wheels": {"steer": 2, "rmax": 0.12, "rmin": 0.06},
        "materials": [(r"(?i)tire", TYRE), (r"(?i)50cal", STEEL), (r".", dict(OLIVE, hue=[(30, 170)], smin=0.06))],
        "groups": {"turret": [("mat", r"(?i)^turret$|50cal")]},
        "pivots": {"turret": "base"},
        "paint": SAND, "tris": 14000,
    },
    "e_convoy_scout": {
        "root": "convoy_scout", "rot": (0, 0, -90), "ground": True, "split": "(?i)tyre|rim|nut|gauge",
        "wheels": {"steer": 2, "rmax": 0.12, "match": "(?i)tyre"},
        "materials": [(r".", OLIVE)],
        # turret = the remote weapon station on the roof only. The first build took "camera|lenses" too: the
        # head lamps and the driver's cameras at both ends went into the turret and would swing round with it,
        # while the gun stayed on the hull. The installed GLB was re-split by part with this box and pivot
        # (VIS-01, 24.10); the source now lives on Kanta's PC, so this rule has not been re-run in Blender.
        "groups": {"turret": [("box", (-0.11, 0.2, -0.135, 0.01, 0.33, 0.47))]},
        "pivots": {"turret": (0.024, -0.064, 0.337)},
        "paint": SAND, "tris": 13000,
    },
    "e_convoy_technical": {
        "root": "convoy_technical", "rot": (0, 0, 90), "ground": True, "split": ".",
        "wheels": {"steer": 1, "rmax": 0.12}, "build": technical_hmg,
        "materials": [(r"(?i)window", GLASS), (r"hmg_steel", STEEL), (r"hmg_olive", {"mode": "keep", "rough": 0.8}),
                      (r"hmg_paint", {"mode": "paint"}), (r".", OLIVE)],
        "groups": {"turret": [("name", r"^hmg_t_")]},
        "pivots": {"turret": (-0.25, 0.0, 0.35)}, "fixed": {"turret": 1400},
        "paint": SAND, "tris": 9000,
    },
    # light pickup with a canvas tilt: the technical's truck without the gun (pickup_tent_cover above)
    "e_convoy_pickup_tent": {
        "root": "convoy_pickup_tent", "rot": (0, 0, 90), "ground": True, "split": ".",
        "wheels": {"steer": 1, "rmax": 0.12}, "build": pickup_tent_cover,
        "materials": [(r"(?i)window", GLASS), (r"^tent_", {"mode": "keep", "rough": 0.95}), (r".", OLIVE)],
        "groups": {"tent": [("name", r"^tent_")]},
        "pivots": {"tent": "center"}, "fixed": {"tent": 900},
        "paint": SAND, "tris": 8000,
    },
    # MANPADS team: the technical's truck with one gunner and the launcher in the bed (manpads_crew above)
    "e_convoy_manpads": {
        "root": "convoy_manpads", "rot": (0, 0, 90), "ground": True, "split": "^(?!mp)",
        "wheels": {"steer": 1, "rmax": 0.12, "match": "^(?!mp)"}, "build": manpads_crew,
        "materials": [(r"(?i)window", GLASS), (r"^mp_", {"mode": "keep", "rough": 0.9, "desat": 0.0}),
                      (r"^PZRC", {"mode": "keep", "color": (0.33, 0.35, 0.24), "rough": 0.7}),
                      (r"^(trigger|battery|material|switch|button)", {"mode": "keep", "color": (0.12, 0.12, 0.11),
                                                                       "rough": 0.6}),
                      (r".", OLIVE)],
        "groups": {"launcher": [("name", r"^mpl_")]},
        "pivots": {"launcher": (-0.34, 0.0, 0.448)}, "fixed": {"launcher": 2000},
        "paint": SAND, "tris": 9000,
    },
    # radar truck (Kanta 26.10, shortlist 88): a 6x6 truck with a lattice search antenna on a mast at the rear.
    # The tan factory paint becomes the sand camo; the antenna head (dish, feed, mast head) is the node render3d
    # spins about the mast axis
    "e_radar": {
        "root": "ground_radar", "rot": (0, 0, 90), "ground": True, "split": ".",
        "materials": [(r".", {"mode": "auto", "hue": [(15, 170)], "smin": 0.06, "gray": (0.3, 0.95)})],
        "groups": {"antenna": [("box", (-0.5, -0.05, -0.35, 0.35, 0.57, 1.0))]},
        "pivots": {"antenna": (-0.143, -0.066, 0.6)},
        "paint": SAND, "tris": 12000,
    },
    "e_helicopter": {
        "root": "helicopter", "rot": (0, 0, 90), "ground": True, "len_exclude": r"(?i)^rotorblades",
        # camo greens/olive, light khaki-grey and the blue belly are paint; yellow parts (blade tips) stay
        "materials": [(r".", {"mode": "auto", "hue": [(60, 235)], "smin": 0.08, "gray": (0.3, 0.95)})],
        "erase": {"Scene_-_Root": [
            (0.105, 0.35, 0.178, 0.418), (0.655, 0.0, 0.745, 0.042),      # stars
            (0.10, 0.525, 0.158, 0.598),                                   # side number
            (0.128, 0.0, 0.208, 0.082),                                    # nose art
            (0.413, 0.0, 0.447, 0.152), (0.418, 0.108, 0.607, 0.158),       # stencil arrows and lettering
            (0.103, 0.843, 0.147, 0.937), (0.585, 0.035, 0.61, 0.065)]},     # lettering, small red mark
        "groups": {"rotor": [("name", r"(?i)^rotor")], "tail_rotor": [("name", r"(?i)^tailrotor(?!stub)")]},
        "pivots": {"rotor": (0.126, -0.005, 0.226), "tail_rotor": (-0.433, 0.022, 0.199)},
        "paint": HELI, "tris": 18000, "weight": {"rotor": 0.6},
    },
    "e_interceptor": {
        "root": "interceptor", "rot": (0, 0, 90), "ground": False,
        "materials": [(r"(?i)glass", GLASS),
                      (r"(?i)^black|int_cab|pribor|panel|gyro", {"mode": "keep", "rough": 0.7, "color": (0.1, 0.1, 0.1)}),
                      (r"(?i)roket", {"mode": "keep", "rough": 0.8, "color": (0.58, 0.58, 0.55)}),
                      (r"(?i)pric", {"mode": "keep", "rough": 0.8, "color": (0.15, 0.15, 0.15)}),
                      (r".", {"mode": "paint"})],
        "erase": {"body": [(0.072, 0.385, 0.148, 0.455), (0.497, 0.385, 0.573, 0.455),     # wing stars
                           (0.072, 0.885, 0.148, 0.955), (0.497, 0.885, 0.573, 0.955),
                           (0.698, 0.215, 0.772, 0.285), (0.793, 0.215, 0.865, 0.285),     # side number
                           (0.598, 0.275, 0.692, 0.392), (0.598, 0.765, 0.692, 0.882)],    # warning stencils
                  "material": [(0.705, 0.07, 0.785, 0.135), (0.685, 0.255, 0.755, 0.325),     # fin stars
                               (0.715, 0.535, 0.815, 0.755), (0.575, 0.935, 0.705, 0.985),     # text plates
                               (0.265, 0.095, 0.41, 0.175), (0.175, 0.575, 0.265, 0.615)]},   # red covers
        # enemy marks (fictional, as code-built enemies): red nose tip, wingtips, fin top
        "paint": dict(JET, marks=[((0.455, 1, -1, 1, -1, 1), JET_RED), ((-1, 1, 0.165, 1, -1, 1), JET_RED),
                                  ((-1, 1, -1, -0.165, -1, 1), JET_RED), ((-1, -0.2, -1, 1, 0.075, 1), JET_RED)]),
        # landing gear and its doors hang below the belly: the game shows the jet in flight
        "kill_faces": [(0.10, 0.16, -0.013, 0.013, -1, -0.036),
                       (-0.19, -0.12, 0.085, 0.12, -1, -0.036), (-0.19, -0.12, -0.12, -0.085, -1, -0.036)],
        "tris": 12000,
    },
    "e_sam": {
        # 8x8 launcher truck (Kanta 24.10: box folded flat on the move, raises at a stop, turns, tracks, launches).
        # The source is grey: neutral greys are paint, saturated parts (extinguishers, lamps, crates, glass) stay.
        "root": "sam", "rot": (0, 0, 90), "ground": True, "len_exclude": "Gun", "cy_ref": True,
        "launcher": {"match": "Gun", "heading": 90.0, "el": 30.0, "box_len": 0.472, "base_z": 0.25, "cell_depth": 0.004},
        "wheel_cyl": {"steer": 2, "axles": [0.262, 0.062, -0.202, -0.400], "z": 0.098, "r": 0.102, "y": (0.09, 0.2), "match": "Wheels"},
        "materials": [(r"Wheels", {"mode": "auto", "hue": [], "gray": (0.42, 0.9), "rough": 0.92, "desat": 0.6,
                                   "nstr": 0.0}),   # flat normals: no moulded tyre lettering
                      (r".", {"mode": "auto", "hue": [(60, 170)], "smin": 0.12, "gray": (0.16, 0.86)})],
        "erase": {"Body": [(0.505, 0.775, 0.553, 0.828)],                                  # hull number, stripes
                  "material": [(0.059, 0.18, 0.104, 0.23), (0.315, 0.18, 0.359, 0.23)],   # box numbers, stripes
                  "Details": [(0.094, 0.559, 0.135, 0.602)]},                              # door roundel
        "paint": SAND, "tris": 17500,   # wheels get more: decimated tread blocks turn into spikes
        "weight": {"launcher_pitch": 1.3, **{"wheel_%s%s" % (a, s): 1.7 for a in ("f", "f2", "1", "2") for s in "lr"}},
    },
    # VIS-01 (Kanta 25.10.2026, picks from the Sketchfab shortlist): flying enemies rebuilt from CC BY sources.
    # All of them wear the same dark grey enemy scheme (JET) as the interceptor so the enemy air force reads as one.
    "e_drone": {
        # pusher-prop recon drone; the source is plain light grey. The propeller is its own node (prop_1, axis X):
        # Render3D._props spins every prop_* node of a battle model
        "root": "drone", "rot": (0, 0, 180), "ground": False,
        "materials": [(r"^10_Fuselage", {"mode": "paint"}),
                      (r".", {"mode": "keep", "desat": 0.5, "rough": 0.6})],
        "groups": {"prop_1": [("name", r"^defaultMaterial\.002$")]},
        "pivots": {"prop_1": "center"},
        "paint": JET, "tris": 6000, "weight": {"prop_1": 0.4},
    },
    "e_carrier": {
        # two-engine missile carrier; light grey skin with red stars, a red side number and a green tail band
        "root": "carrier", "rot": (0, 0, 90), "ground": False,
        "materials": [(r"Material_381", GLASS),
                      (r"^(material|Panel)$", {"mode": "keep", "rough": 0.7, "color": (0.1, 0.1, 0.1)}),
                      # light grey skin is paint; the dark radome, intakes and nozzles stay
                      (r".", {"mode": "auto", "hue": [], "gray": (0.45, 1.0)})],
        "erase": {k: [(0.46, 0.05, 0.58, 0.137),                                        # side number
                      (0.558, 0.215, 0.832, 0.301), (0.769, 0.5, 1.0, 0.617),          # fin band, fin star
                      (0.578, 0.785, 0.649, 0.856), (0.254, 0.789, 0.324, 0.856),      # wing stars
                      (0.394, 0.418, 0.578, 0.434), (0.867, 0.422, 0.93, 0.434)]        # red stencil lines
                  for k in ("BODY1", "BODY2", "BODY2_0", "003l.paa")},
        # landing gear, its doors and the wingtip outriggers hang below the belly: the game shows it in flight
        "drop_box": [(-1, 1, -1, 1, -1, -0.045)],
        "paint": dict(JET, marks=[((0.46, 1, -1, 1, -1, 1), JET_RED), ((-1, 1, 0.245, 1, -1, 1), JET_RED),
                                  ((-1, 1, -1, -0.245, -1, 1), JET_RED), ((-1, -0.25, -1, 1, 0.075, 1), JET_RED)]),
        "tris": 12000,
    },
    "e_transport": {
        # four-engine turboprop; a sand/green camouflage with a tail emblem, serial and faded wing roundels.
        # The single-mesh source is split into loose parts so each propeller becomes a prop_N node (axis X)
        "root": "transport", "rot": (0, 0, 90), "ground": False, "split": r"^Object_",
        "materials": [(r"Cockpit", {"mode": "auto", "hue": [(25, 170)], "smin": 0.1}),
                      # whole skin textures are paint: an "auto" mask leaves light pixels out, and the camouflage
                      # flattening (which brightens the dark blobs) would show them as white specks
                      (r"Fuselage|Wings|^plane_body", {"mode": "paint", "flatten": 15}),
                      (r".", {"mode": "keep", "desat": 0.6, "rough": 0.7})],
        "erase": {"C130_Wings_Left.002": [(0.78, 0.77, 0.96, 0.97), (0.25, 0.04, 0.37, 0.16), (0.57, 0.19, 0.69, 0.31)],
                  "C130_Wings_Right.002": [(0.76, 0.77, 0.94, 0.97), (0.25, 0.04, 0.37, 0.16), (0.57, 0.19, 0.69, 0.31)]},
        "drop_box": [(-1, 1, -1, 1, -1, -0.15)],   # wheels and gear legs
        "groups": {"prop_%d" % (i + 1): [("box", (0.19, 0.22, y - 0.035, y + 0.035, -0.14, 0.0))]
                   for i, y in enumerate((0.341, 0.171, -0.171, -0.342))},
        "pivots": {"prop_1": (0.203, 0.341, -0.061), "prop_2": (0.203, 0.171, -0.072),
                   "prop_3": (0.203, -0.171, -0.072), "prop_4": (0.203, -0.342, -0.061)},
        "paint": dict(JET, marks=[((0.47, 1, -1, 1, -1, 1), JET_RED), ((-1, -0.3, -1, 1, 0.15, 1), JET_RED)]),
        "tris": 16000, "weight": {"prop_%d" % i: 0.3 for i in range(1, 5)},
    },
    "e_rival": {
        # fictional concept fighter: its grey digital camo becomes the enemy scheme; the gold canopy, the yellow
        # stencil lines and the blue nozzle glow (saturated) stay
        "root": "rival", "rot": (0, 0, 90), "ground": False,
        "materials": [(r".", {"mode": "auto", "hue": [], "gray": (0.03, 1.0), "flatten": 15})],
        "paint": dict(JET, marks=[((0.46, 1, -1, 1, -1, 1), JET_RED), ((-1, 1, 0.3, 1, -1, 1), JET_RED),
                                  ((-1, 1, -1, -0.3, -1, 1), JET_RED), ((-1, -0.25, -1, 1, 0.08, 1), JET_RED)]),
        "tris": 12000,
    },
}

# «Оса» lvl 1 hangar close-up: the same rework without decimation, subdivided once (the source has ~11k visible
# triangles; the hangar camera comes close) and baked at 4096
RECIPES["fighter_1_hangar"] = dict(RECIPES["fighter_1"], root="fh_hangar_fighter_1", tris=80000, subdiv=1)
