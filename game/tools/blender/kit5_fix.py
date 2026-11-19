"""3.5-s19 (Kanta 17.11, «Кит» 5 = bomber_t5): «двигатели не вертятся, а должны» and «что у него сверху на
фюзеляже? какие-то бугры». The Meshy hull has its four lift fans fused into the ducts, and a grid of 32 raised
blocks behind the top turret: generator noise with no part behind it (open-bottomed boxes, 25 mm proud of the skin).

Step 1 (`cut`, glb_io: only the triangle list changes, vertices, UV and the embedded images stay byte for byte, so
Godot keeps the extracted maps): removes every triangle inside each duct (rotor, hub, the fused stator) and the
block grid.
Step 2 (`parts`, Blender): writes
  models/mech/fh_prop_bomber_t5.glb — four rotors prop_fl/fr/rl/rr (hub spinner and 7 twisted blades, dark metal);
      origin on the duct axis, local X along that axis (up), so WingMech.spin_props turns them like «Кит» 1's
      propellers;
  models/mech/fh_detail_bomber_t5.glb — what does not turn: each duct's motor pod under the rotor with three
      stator struts to the duct wall (dark metal), and the drone-bay doors over the hole of the block grid
      (PT-05: «Кит» 5 carries a drone bay): a flush plate on the fuselage crown, two doors with dark seams,
      «mech_skin» vertex colour of the skin round it (WingMech.attach_skin paints it like the slats).

Axes: glTF/Godot — nose +X, up +Y, right wing +Z; model length 1. Blender — X nose, Y = -Z glTF, Z = Y glTF.
Run from the repo root (bpy 5.x as a module):
  python3 game/tools/blender/kit5_fix.py cut game/models/hangar/fh_hangar_bomber_t5.glb <out.glb>
  python3 game/tools/blender/kit5_fix.py parts <original hangar glb, before cut> game/models/mech
  python3 game/tools/blender/kit5_fix.py glaze game/models/hangar/fh_hangar_bomber_t5.glb <out.glb>
then rebake the battle model from the cut hangar model (battle_bake.py)."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_io  # noqa: E402

# duct axes (x, z glTF), measured on the hangar model: the bbox centre of each fan's dark box
FANS = {"fr": (0.2601, 0.2305), "fl": (0.2600, -0.2303), "rr": (-0.3100, 0.2334), "rl": (-0.3100, -0.2334)}
DUCT_R = 0.064         # cut radius: the fused blades reach the duct wall, which starts at about 0.065
DUCT_Y = (-0.097, 0.002)
ROTOR_R = 0.0605
SLEEVE_R = 0.0645     # new inner duct wall (the cut leaves the Meshy wall torn)
SLEEVE_Y = (-0.094, -0.0025)
LIP_R = 0.0695        # metal lip ring over the duct's rim, hides the torn top edge of the old wall
ROTOR_Y = -0.036       # blade plane (the Meshy blades sat between y -0.06 and -0.024)
HUB_R = 0.019
MOTOR_Y = (-0.088, -0.046)
# block grid: x, z box (glTF) and the height above which everything in it goes
BLOCKS = (-0.205, -0.012, -0.085, 0.078, 0.03)
PLATE_PAD = 0.006      # the plate reaches this far past the hole
SEAM_W = 0.0012


def cut(src, dst):
    g = glb_io.load(src)
    w, t = g.mesh_world(0, 0)
    c = w[t].mean(1)
    kill = np.zeros(len(t), bool)
    for cx, cz in FANS.values():
        r = np.hypot(c[:, 0] - cx, c[:, 2] - cz)
        kill |= (r < DUCT_R) & (c[:, 1] > DUCT_Y[0]) & (c[:, 1] < DUCT_Y[1])
        # long slivers of the fused blade roots: centroid on the wall, a corner deep inside the duct
        vr = np.hypot(w[t][:, :, 0] - cx, w[t][:, :, 2] - cz).min(1)
        kill |= (vr < DUCT_R - 0.003) & (c[:, 1] > DUCT_Y[0]) & (c[:, 1] < DUCT_Y[1])
    x0, x1, z0, z1, y0 = BLOCKS
    kill |= (c[:, 0] > x0) & (c[:, 0] < x1) & (c[:, 2] > z0) & (c[:, 2] < z1) & (c[:, 1] > y0)
    print("cut %d of %d triangles" % (kill.sum(), len(t)))
    g.set_indices(0, 0, t[~kill])
    g.save(dst)


def parts(src, out_dir):
    import bpy  # noqa: I001
    import bmesh
    from mathutils import Matrix, Vector, geometry

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    hull = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("fh_hangar"))
    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    img = next(n.image for n in hull.data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image
               and any(lk.to_socket.name == "Base Color" for lk in n.outputs[0].links))
    W, H = img.size
    PX = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)

    def skin_down(x, y):
        """Top skin under (x, y) Blender: point, normal, colour; None on a miss"""
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, Vector((x, y, 1.0)), Vector((0, 0, -1)))
        if not ok or ob != hull:
            return None
        me = ob.data
        poly = me.polygons[idx]
        uvl = me.uv_layers.active.data
        vs = [ob.matrix_world @ me.vertices[v].co for v in poly.vertices[:3]]
        uv = [Vector((*uvl[li].uv, 0)) for li in poly.loop_indices[:3]]
        b = geometry.barycentric_transform(loc, vs[0], vs[1], vs[2], uv[0], uv[1], uv[2])
        px, py = int((b.x % 1.0) * (W - 1)), int((b.y % 1.0) * (H - 1))
        return loc, nrm, PX[py, px, :3]

    def mat(name, rgb, metal, rough, vcol=False):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*rgb, 1)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        if vcol:
            vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "Col"
            m.node_tree.links.new(vc.outputs["Color"], b.inputs["Base Color"])
        return m

    dark = mat("fan_metal", (0.03, 0.032, 0.035), 0.6, 0.5)
    hubm = mat("fan_hub", (0.06, 0.06, 0.065), 0.5, 0.45)
    skin = mat("mech_skin", (1, 1, 1), 0.2, 0.6, vcol=True)

    # --- drone-bay plate: crown fitted to the top skin round the hole (the cut model has the hole; here the
    # original still has the blocks, so only the ring outside the block box is sampled)
    x0, x1, z0, z1, _y0 = BLOCKS
    bx0, bx1, by0, by1 = x0, x1, -z1, -z0          # Blender y = -z
    ring, cols = [], []
    for i in range(41):
        for j in range(41):
            x = bx0 - 0.03 + (bx1 - bx0 + 0.06) * i / 40
            y = by0 - 0.03 + (by1 - by0 + 0.06) * j / 40
            if bx0 - 0.004 < x < bx1 + 0.004 and by0 - 0.004 < y < by1 + 0.004:
                continue
            h = skin_down(x, y)
            if h is not None and h[1].z > 0.5:
                ring.append((x, y, h[0].z))
                cols.append(h[2])
    ring_xy = np.array([(r[0], r[1]) for r in ring])
    ring_col = np.array(cols)
    ring = np.array(ring)
    A = np.c_[np.ones(len(ring)), ring[:, 0], ring[:, 1], ring[:, 0] ** 2, ring[:, 0] * ring[:, 1], ring[:, 1] ** 2]
    keep = np.ones(len(ring), bool)
    for _ in range(4):   # robust: drop points off the crown (fin roots, the turret ring, panel steps)
        coef = np.linalg.lstsq(A[keep], ring[keep, 2], rcond=None)[0]
        res = ring[:, 2] - A @ coef
        keep = np.abs(res) < max(0.0015, 2.5 * res[keep].std())
    res = res[keep]
    print("crown fit: %d points, residual rms %.4f max %.4f" % (len(ring), res.std(), np.abs(res).max()))
    tone = np.median(np.array(cols), axis=0)

    def paint(x, y):
        """Skin colour under (x, y): the texture where the real skin is, else the ring colours by inverse distance
        (the camouflage closes over the doors instead of a one-tone patch)"""
        if not (bx0 < x < bx1 and by0 < y < by1):
            h = skin_down(x, y)
            if h is not None and h[1].z > 0.5:
                return h[2]
        d2 = (ring_xy[:, 0] - x) ** 2 + (ring_xy[:, 1] - y) ** 2
        wgt = 1.0 / (d2 ** 2 + 1e-12)
        return (ring_col * wgt[:, None]).sum(0) / wgt.sum()

    def crown(x, y):
        return float(coef @ [1, x, y, x * x, x * y, y * y])

    px0, px1, py0, py1 = bx0 - PLATE_PAD, bx1 + PLATE_PAD, by0 - PLATE_PAD, by1 + PLATE_PAD
    xm = (px0 + px1) / 2
    NXp, NYp = 48, 36
    bm = bmesh.new()
    colk = bm.loops.layers.color.new("Col")
    vcl = bm.verts.layers.float_color.new("c")
    top = []
    for i in range(NXp + 1):
        row = []
        for j in range(NYp + 1):
            x = px0 + (px1 - px0) * i / NXp
            y = py0 + (py1 - py0) * j / NYp
            z = crown(x, y)
            if not (bx0 < x < bx1 and by0 < y < by1):   # over the real skin round the hole: follow it
                h = skin_down(x, y)
                if h is not None and h[1].z > 0.5 and abs(h[0].z - z) < 0.006:
                    z = h[0].z
            v = bm.verts.new((x, y, z + 0.0004))
            v[vcl] = (*paint(x, y), 1.0)
            row.append(v)
        top.append(row)

    def shade(v):
        x, y = v.co.x, v.co.y
        k = 1.0
        inner = (px0 + 0.004, px1 - 0.004, py0 + 0.004, py1 - 0.004)
        on_frame = min(abs(x - inner[0]), abs(x - inner[1])) < SEAM_W and inner[2] <= y <= inner[3] or \
            min(abs(y - inner[2]), abs(y - inner[3])) < SEAM_W and inner[0] <= x <= inner[1]
        on_split = abs(y - (py0 + py1) / 2) < SEAM_W * 0.8 and inner[0] <= x <= inner[1]
        on_hinge = abs(x - xm) < SEAM_W * 0.5 and inner[2] <= y <= inner[3]
        if on_frame or on_split:
            k = 0.35
        elif on_hinge:
            k = 0.7
        edge = min(x - px0, px1 - x, y - py0, py1 - y)
        if edge < 0.0015:
            k *= 0.85
        base = np.array(v[vcl][:3])
        return (*(base * k), 1.0)

    for i in range(NXp):
        for j in range(NYp):
            f = bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
            for lp in f.loops:
                lp[colk] = shade(lp.vert)
    # skirt: the plate's rim bent down into the skin so no gap shows from a low angle
    rim = [top[0][j] for j in range(NYp + 1)] + [top[i][NYp] for i in range(1, NXp + 1)] + \
          [top[NXp][j] for j in range(NYp - 1, -1, -1)] + [top[i][0] for i in range(NXp - 1, 0, -1)]
    low = [bm.verts.new(v.co - Vector((0, 0, 0.003))) for v in rim]
    skirt = []
    for k in range(len(rim)):
        f = bm.faces.new((rim[k], low[k], low[(k + 1) % len(rim)], rim[(k + 1) % len(rim)]))
        skirt.append(f)
        for lp in f.loops:
            lp[colk] = (*(tone * 0.6), 1.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("drone_bay")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(skin)
    plate = bpy.data.objects.new("drone_bay", me)
    sc.collection.objects.link(plate)
    nsk = len(skirt)
    for i, p in enumerate(me.polygons):
        p.use_smooth = i < len(me.polygons) - nsk   # the skirt is shaded flat: no rounded dark rim

    # --- fans: rotors (spin) and motor pods with stator struts (static)
    def rotor(name, cx, cy):
        bm = bmesh.new()
        # spinner: a low dome on the hub disc
        seg = 20
        rings = [(HUB_R, 0.0), (HUB_R, 0.006), (HUB_R * 0.85, 0.011), (HUB_R * 0.55, 0.0145), (0.0, 0.016)]
        vs = []
        for r, h in rings:
            vs.append([bm.verts.new((r * np.cos(2 * np.pi * k / seg), r * np.sin(2 * np.pi * k / seg), h)) for k in range(seg)])
        for a in range(len(vs) - 1):
            for k in range(seg):
                bm.faces.new((vs[a][k], vs[a][(k + 1) % seg], vs[a + 1][(k + 1) % seg], vs[a + 1][k]))
        bm.faces.new(list(reversed(vs[0])))
        # 7 blades, twisted (pitch 38° at the root to 18° at the tip), slight sweep
        NB, NS = 7, 6
        for b in range(NB):
            a0 = 2 * np.pi * b / NB
            sec = []
            for s in range(NS + 1):
                f = s / NS
                r = HUB_R * 0.95 + (ROTOR_R - HUB_R * 0.95) * f
                chord = 0.017 - 0.004 * f
                pitch = np.radians(38 - 20 * f)
                th = 0.0016 * (1 - 0.6 * f)
                ang = a0 + 0.12 * f
                d = np.array([np.cos(ang), np.sin(ang), 0])
                tdir = np.array([-np.sin(ang), np.cos(ang), 0])
                ch = tdir * np.cos(pitch) + np.array([0, 0, 1]) * np.sin(pitch)
                nrm = np.cross(d, ch)
                ctr = d * r + np.array([0, 0, 0.006])
                le, te = ctr + ch * chord * 0.5, ctr - ch * chord * 0.5
                sec.append([bm.verts.new(tuple(le)), bm.verts.new(tuple(ctr + nrm * th)),
                            bm.verts.new(tuple(te)), bm.verts.new(tuple(ctr - nrm * th))])
            for s in range(NS):
                for k in range(4):
                    bm.faces.new((sec[s][k], sec[s][(k + 1) % 4], sec[s + 1][(k + 1) % 4], sec[s + 1][k]))
            bm.faces.new(sec[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(dark)
        for p in me.polygons:
            p.use_smooth = True
        ob = bpy.data.objects.new(name, me)
        sc.collection.objects.link(ob)
        # mesh built round +Z (Blender up); the node's local X is that axis: rotate the mesh so its axis is local X
        rot = Matrix.Rotation(np.radians(-90), 4, "Y")    # local X -> world +Z
        me.transform(rot.inverted())
        ob.matrix_world = Matrix.Translation((cx, cy, ROTOR_Y)) @ rot
        return ob

    def stator(name, cx, cy):
        bm = bmesh.new()
        seg = 16
        r0 = HUB_R * 0.9
        lo, hi = MOTOR_Y
        prof = [(r0 * 0.4, lo - 0.004), (r0 * 0.85, lo), (r0, lo + 0.008), (r0, hi), (r0 * 0.95, hi + 0.004)]
        vs = [[bm.verts.new((cx + r * np.cos(2 * np.pi * k / seg), cy + r * np.sin(2 * np.pi * k / seg), z)) for k in range(seg)]
              for r, z in prof]
        for a in range(len(vs) - 1):
            for k in range(seg):
                bm.faces.new((vs[a][k], vs[a][(k + 1) % seg], vs[a + 1][(k + 1) % seg], vs[a + 1][k]))
        bm.faces.new(list(reversed(vs[0])))
        bm.faces.new(vs[-1])
        for s in range(3):   # struts: thin aerofoil bars from the pod to the wall, below the rotor
            ang = 2 * np.pi * s / 3 + 0.5
            d = Vector((np.cos(ang), np.sin(ang), 0))
            t = Vector((-np.sin(ang), np.cos(ang), 0))
            z = (lo + hi) / 2
            pts = []
            for rr in (r0 * 0.8, SLEEVE_R + 0.001):
                c = Vector((cx, cy, z)) + d * rr
                pts.append([bm.verts.new(c + t * 0.0012 + Vector((0, 0, 0.006))), bm.verts.new(c + t * 0.0012 - Vector((0, 0, 0.006))),
                            bm.verts.new(c - t * 0.0012 - Vector((0, 0, 0.006))), bm.verts.new(c - t * 0.0012 + Vector((0, 0, 0.006)))])
            for k in range(4):
                bm.faces.new((pts[0][k], pts[0][(k + 1) % 4], pts[1][(k + 1) % 4], pts[1][k]))
            bm.faces.new(list(reversed(pts[0])))
            bm.faces.new(pts[1])
        # inner duct wall: a clean sleeve over the torn Meshy wall, open both ends (the fan draws air through)
        sl = [[bm.verts.new((cx + SLEEVE_R * np.cos(2 * np.pi * k / 48), cy + SLEEVE_R * np.sin(2 * np.pi * k / 48), z))
               for k in range(48)] for z in SLEEVE_Y]
        for k in range(48):
            bm.faces.new((sl[0][k], sl[1][k], sl[1][(k + 1) % 48], sl[0][(k + 1) % 48]))
        lip = [bm.verts.new((cx + LIP_R * np.cos(2 * np.pi * k / 48), cy + LIP_R * np.sin(2 * np.pi * k / 48), SLEEVE_Y[1] - 0.0008))
               for k in range(48)]
        lip_faces = [bm.faces.new((sl[1][k], lip[k], lip[(k + 1) % 48], sl[1][(k + 1) % 48])) for k in range(48)]
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for f in list(bm.faces)[-96:-48]:   # the sleeve faces inward, to the rotor
            if (f.calc_center_median() - Vector((cx, cy, f.calc_center_median().z))).dot(f.normal) > 0:
                f.normal_flip()
        for f in lip_faces:   # the lip faces up
            if f.normal.z < 0:
                f.normal_flip()
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(hubm)
        ob = bpy.data.objects.new(name, me)
        sc.collection.objects.link(ob)
        return ob

    rotors, statics = [], [plate]
    for k, (fx, fz) in FANS.items():
        rotors.append(rotor("prop_" + k, fx, -fz))
        statics.append(stator("stator_" + k, fx, -fz))
    for o in list(sc.objects):
        if o not in rotors and o not in statics:
            bpy.data.objects.remove(o, do_unlink=True)

    def export(objs, path):
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="EXPORT",
                                  export_vertex_color="MATERIAL")
    export(rotors, os.path.join(out_dir, "fh_prop_bomber_t5.glb"))
    export(statics, os.path.join(out_dir, "fh_detail_bomber_t5.glb"))
    print("parts written")


GLAZE_DROP = 0.006   # a skin triangle up to this far below the nearest glass vertex still counts as canopy
GLAZE_CLEAR = 0.045  # under the footprint the skin goes down to this far below the glazing: the hangar's cockpit tub
                     # (HangarCockpit, floor about 0.06 under the sill) takes its place, and skin left there showed
                     # through the clear glass as a jagged cream edge
GLAZE_STEP = 0.003   # grid step of the new glazing, model units
GLAZE_LIFT = 0.0015  # the new glazing sits this far over the fit
COLLAR_W = 0.04      # the collar: hull rebuilt this wide round the glazing, from a thin rail over the glass edge
                     # down to the hull, so the canopy sits in the skin (Kanta 19.11: «должна стать частью самолета»)
COLLAR_LIP = 0.0012  # the rail stands this far over the glass edge
COLLAR_RINGS = 5     # rings across the collar
COLLAR_CAP = 0.03    # skin more than this over the glass edge is not the hull the collar runs down to (torn teeth)
COLLAR_NEAR = 0.004  # skin under the collar's span within this of it goes
COLLAR_SINK = 0.0008  # the collar's outer edge runs this far under the skin, so the skin draws over it there
SILL_WELL = 0.02     # and its inner face runs this far down into the cockpit (the cut skin edge stays behind it)


def _crown(x, z):
    """Terms of the canopy surface fit y(x, z): symmetric in z (the glasshouse is), cubic along x"""
    return np.stack([np.ones_like(x), x, z * z, x * x, x * z * z, x ** 3, z ** 4, x * x * z * z], 1)


def _cast_down(tris, centres, reach, p, cap):
    """Height of the highest triangle of `tris` (n, 3, 3) under the point p (x, z) and below `cap`, or None.
    `centres` is a cKDTree of the triangles' (x, z) centres and `reach` the largest centre-to-corner distance."""
    ids = centres.query_ball_point(p, reach)
    if not ids:
        return None
    t = tris[ids]
    a, b, c = t[:, 0], t[:, 1], t[:, 2]
    d = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2])
    good = np.abs(d) > 1e-14
    d = np.where(good, d, 1.0)
    l1 = ((b[:, 2] - c[:, 2]) * (p[0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (p[1] - c[:, 2])) / d
    l2 = ((c[:, 2] - a[:, 2]) * (p[0] - c[:, 0]) + (a[:, 0] - c[:, 0]) * (p[1] - c[:, 2])) / d
    l3 = 1.0 - l1 - l2
    y = l1 * a[:, 1] + l2 * b[:, 1] + l3 * c[:, 1]
    hit = good & (l1 >= 0) & (l2 >= 0) & (l3 >= 0) & (y < cap)
    return float(y[hit].max()) if hit.any() else None


def _outward(ring):
    """Unit outward normals (x, z) at the vertices of a counter-clockwise or clockwise convex ring"""
    c = ring.mean(0)
    e = np.roll(ring, -1, 0) - ring
    en = np.stack([e[:, 1], -e[:, 0]], 1)
    en /= np.linalg.norm(en, axis=1, keepdims=True) + 1e-12
    mid = (ring + np.roll(ring, -1, 0)) * 0.5
    en[np.einsum("ij,ij->i", en, mid - c) < 0] *= -1
    n = en + np.roll(en, 1, 0)   # vertex normal: mean of the two edges' normals
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)


def glaze(src, dst):
    """3.5-s19 recheck (Kanta 18.11, «Кит 5 — закрашено стекло кабины», «посмотри края остекления. Ты не можешь
    определить где заканчивается стекло?», then «а че она не симметричная такая?» and «торчит над контуром корпуса»):
    the Meshy canopy glass is a lopsided, jagged patch of shards with skin shards between and over its panes, and the
    skin round it is torn into teeth. The whole canopy is replaced by one clean, symmetric glazed surface set into a
    rebuilt hull collar:
      1. the surface: a robust least-squares fit y(x, z) (_crown, symmetric in z) to the upper envelope of the old
         glass (the highest vertex in each 4 mm cell; median miss about 1 mm), its crown lowered at the aft end to
         the old glass's height there (the cubic ran 2.8 cm over it, over the fairing behind the canopy);
      2. the footprint: the convex hull, seen from above (x, z), of the glass vertices within GLAZE_DROP of the raw
         fit and their mirror images (z -> -z); inside it every skin and old glass triangle whose centre is less than
         GLAZE_CLEAR under the raw fit is removed, and every skin triangle with two corners above it;
      3. a GLAZE_STEP grid over the footprint, triangulated, at the surface plus GLAZE_LIFT;
      4. the collar (Kanta 19.11: «всё ещё очень толстая рамка у кабины ... смотрится как будто ты просто налепил
         её грубо сверху. Она должна стать частью самолета»): no frame stands on the hull; the hull itself is rebuilt
         COLLAR_W wide round the outline, from a thin rail COLLAR_LIP over the glass edge down to the top skin
         surface just past it (cast down through the skin, the same at an outline point and its mirror image,
         smoothed, COLLAR_SINK under it), its outer edge tucked under the skin. Skin wholly under its span and near
         it, skin rising through it and folded flaps go; skin straddling its outer edge stays. The rail, collar and
         tuck are body triangles, each with the hull's UV at its spot, so they carry the hull's paint; only an inner
         face SILL_WELL down into the cockpit under the glass edge stays in the glass primitive with U = 1, for the
         hangar's frame paint (HangarCockpit, FRAMES «frame_uv»).
    The body's vertices, UV and the embedded images stay byte for byte; the body gains the collar's triangles."""
    from scipy.spatial import ConvexHull, Delaunay, cKDTree
    g = glb_io.load(src)
    prims = g.j["meshes"][0]["primitives"]
    names = [g.j["materials"][p["material"]]["name"] for p in prims]
    bi = next(i for i, n in enumerate(names) if n.endswith("_body"))
    gi = names.index("glass")
    bp, bt = g.mesh_world(0, bi)
    gp, gt = g.mesh_world(0, gi)
    gv = gp[np.unique(gt)]
    # upper envelope of the old glass and the robust fit
    cell = {}
    for i, k in enumerate(map(tuple, np.floor(gv[:, [0, 2]] / 0.004).astype(int))):
        if k not in cell or gv[i, 1] > gv[cell[k], 1]:
            cell[k] = i
    u = gv[list(cell.values())]
    w = np.ones(len(u))
    for _ in range(6):
        co, *_ = np.linalg.lstsq(_crown(u[:, 0], u[:, 2]) * w[:, None], u[:, 1] * w, rcond=None)
        r = u[:, 1] - _crown(u[:, 0], u[:, 2]) @ co
        w = 1.0 / np.maximum(1.0, np.abs(r) / (np.median(np.abs(r)) * 1.5 + 1e-4))

    # the cubic runs away past the old glass at the aft end (2.8 cm over it, over the fairing behind the canopy,
    # Kanta 18.11: «торчит над контуром корпуса»): the crown is lowered there, the same at every z so it keeps its
    # shape, to the upper envelope of the old glass along x
    xb = np.arange(u[:, 0].min(), u[:, 0].max() + 0.01, 0.01)
    tops = np.array([u[np.abs(u[:, 0] - x) < 0.01, 1].max(initial=-1.0) for x in xb])
    xb, tops = xb[tops > -1.0], tops[tops > -1.0]
    tops = np.maximum.accumulate(tops[::-1])[::-1] if xb[0] < xb[-1] else tops   # never dips aft of a higher pane

    def fit_raw(x, z):
        return _crown(np.atleast_1d(x), np.atleast_1d(z)) @ co

    def fit(x, z):
        x, z = np.atleast_1d(x), np.atleast_1d(z)
        return fit_raw(x, z) - np.maximum(0.0, fit_raw(x, 0.0 * x) - (np.interp(x, xb, tops) + 0.002))

    # footprint: the glass that lies on that surface (the side windows lower down keep their old glass)
    top = gv[np.abs(gv[:, 1] - fit_raw(gv[:, 0], gv[:, 2])) < GLAZE_DROP]
    # mirrored about the centre plane (z = 0): the old glass was lopsided (z −0.071…+0.079) and so was the canopy
    # (Kanta 18.11: «а че она не симметричная такая?»)
    xz = np.vstack([top[:, [0, 2]], top[:, [0, 2]] * np.array([1.0, -1.0])])
    hull = ConvexHull(xz)
    tri = Delaunay(xz[hull.vertices])
    fit_b = fit_raw(bp[:, 0], bp[:, 2])
    cen = bp[bt].mean(1)
    sel = (tri.find_simplex(cen[:, [0, 2]]) >= 0) & (cen[:, 1] > fit_raw(cen[:, 0], cen[:, 2]) - GLAZE_CLEAR)
    # skin shards that reach over the new surface inside the footprint go too
    over = (tri.find_simplex(bp[:, [0, 2]]) >= 0) & (bp[:, 1] > fit_b + 0.0005)
    sel |= over[bt].sum(1) >= 2
    gcen = gp[gt].mean(1)
    # inside the (mirrored) footprint the old glass goes as deep as the skin does: on the narrow side the lower
    # old panes showed as dark shards between the new glazing and its frame
    keep_glass = (tri.find_simplex(gcen[:, [0, 2]]) < 0) | (gcen[:, 1] < fit_raw(gcen[:, 0], gcen[:, 2]) - GLAZE_CLEAR)
    # the outline resampled at GLAZE_STEP, and the grid inside it
    ring = xz[hull.vertices]
    out = []
    for i in range(len(ring)):
        p0, p1 = ring[i], ring[(i + 1) % len(ring)]
        n = max(1, int(np.ceil(np.linalg.norm(p1 - p0) / GLAZE_STEP)))
        out += [p0 + (p1 - p0) * t / n for t in range(n)]
    out = np.array(out)
    k = len(out)
    lo, hi = ring.min(0), ring.max(0)
    gx, gz = np.meshgrid(np.arange(lo[0], hi[0], GLAZE_STEP), np.arange(lo[1], hi[1], GLAZE_STEP))
    inner = np.stack([gx.ravel(), gz.ravel()], 1)
    inner = inner[tri.find_simplex(inner) >= 0]
    inner = inner[cKDTree(out).query(inner)[0] > GLAZE_STEP * 0.5]
    pts = np.vstack([out, inner])
    faces = Delaunay(pts).simplices
    pos = np.stack([pts[:, 0], fit(pts[:, 0], pts[:, 1]) + GLAZE_LIFT, pts[:, 1]], 1)
    # normals from the fit's gradient (numeric), pointing up
    e = 1e-4
    dx = (fit(pts[:, 0] + e, pts[:, 1]) - fit(pts[:, 0], pts[:, 1])) / e
    dz = (fit(pts[:, 0], pts[:, 1] + e) - fit(pts[:, 0], pts[:, 1])) / e
    nrm = np.stack([-dx, np.ones_like(dx), -dz], 1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    fn = np.cross(pos[faces[:, 1]] - pos[faces[:, 0]], pos[faces[:, 2]] - pos[faces[:, 0]])
    flip = fn[:, 1] < 0
    faces[flip] = faces[flip][:, [0, 2, 1]]
    # the sill: height over the highest skin under the band (skin vertices and triangle centres that remain)
    on = _outward(out)
    rest = ~sel
    sk = np.vstack([bp[np.unique(bt[rest])], cen[rest]])
    st = cKDTree(sk[:, [0, 2]])
    edge_h = fit(out[:, 0], out[:, 1]) + GLAZE_LIFT
    mirror = cKDTree(out).query(out * np.array([1.0, -1.0]))[1]

    def along(v, n):
        """Running mean over ±n outline points (the outline is closed)"""
        pad = np.concatenate([v[-n:], v, v[:n]])
        return np.convolve(pad, np.ones(2 * n + 1) / (2 * n + 1), "valid")
    # the collar's outer edge sits on the hull: the TOP skin surface just past it, found by casting down through the
    # remaining skin (a median over every skin layer under a point took the belly and the inner faces too, and the
    # collar stood out over the flanks as a shelf with nothing under it), skin teeth well over the glass edge
    # ignored; the median of 9 casts, the higher of each point and its mirror image, smoothed along the outline
    rest_t = np.flatnonzero(~sel)
    tri3 = bp[bt[rest_t]]
    tc = cKDTree(tri3.mean(1)[:, [0, 2]])
    reach = float(np.linalg.norm(tri3[:, :, [0, 2]] - tri3.mean(1)[:, None, [0, 2]], axis=2).max())
    tang = np.stack([-on[:, 1], on[:, 0]], 1)
    hull_h = np.full(k, np.nan)
    for i in range(k):
        hs = []
        for t in (COLLAR_W, COLLAR_W + 0.003, COLLAR_W + 0.006):
            for o in (-0.003, 0.0, 0.003):
                h = _cast_down(tri3, tc, reach, out[i] + on[i] * t + tang[i] * o, edge_h[i] + COLLAR_CAP)
                if h is not None:
                    hs.append(h)
        if hs:
            hull_h[i] = np.median(hs)
    ok = ~np.isnan(hull_h)
    idx = np.arange(k)
    hull_h = np.interp(idx, idx[ok], hull_h[ok], period=k)
    hull_h = along(np.maximum(hull_h, hull_h[mirror]), 4) - COLLAR_SINK
    lip_h = edge_h + COLLAR_LIP
    # skin straddling the collar's outer edge stays unless it rises through the collar (taking it away opened holes
    # past the collar), and folded flaps (facing down) that reach up to it go
    d_c, i_c = cKDTree(out).query(cen[:, [0, 2]])
    outside = tri.find_simplex(cen[:, [0, 2]]) < 0
    near = np.flatnonzero(~sel & outside & (d_c < COLLAR_W + 0.012))
    tv = bp[bt[near]]                                             # (m, 3, 3)
    dv, iv = cKDTree(out).query(tv[:, :, [0, 2]].reshape(-1, 2))
    dv, iv = dv.reshape(-1, 3), iv.reshape(-1, 3)
    tt = np.clip(dv / COLLAR_W, 0.0, 1.0)
    ch = lip_h[iv] + (hull_h[iv] - lip_h[iv]) * tt * tt * (3 - 2 * tt)
    # skin wholly under the collar's span and within COLLAR_NEAR under it goes (the collar is the hull there; left
    # in, it drew through the collar in a sawtooth; deeper skin stays, or the flanks under the collar opened), and
    # straddling skin whose inner corners rise over the collar
    inside_all = (dv < COLLAR_W).all(1) & (tv[:, :, 1] > ch - COLLAR_NEAR).any(1)
    poke = near[inside_all | ((dv < COLLAR_W) & (tv[:, :, 1] > ch + 0.0003)).any(1)]
    tn = np.cross(tv[:, 1] - tv[:, 0], tv[:, 2] - tv[:, 0])
    tn /= np.maximum(np.linalg.norm(tn, axis=1, keepdims=True), 1e-12)
    flaps = near[(tn[:, 1] < 0.0) & ((dv < COLLAR_W) & (tv[:, :, 1] > ch - 0.002)).any(1)]
    print("glaze: %d skin triangles under or through the collar and %d folded flaps removed" % (len(poke), len(flaps)))
    sel[poke] = True
    sel[flaps] = True
    band_h = lip_h
    up = np.array([0.0, 1.0, 0.0])
    side = np.zeros((k, 3))
    side[:, [0, 2]] = on
    well = pos[:k] - up * SILL_WELL                                          # inside the glass edge, down into the pit
    # the hull starts on its own copy of the glass edge, 0.05 mm under it: welded to the glazing's edge it took the
    # glazing's normals and U, and the hangar drew a sawtooth of glass and frame
    edge = pos[:k] - up * 0.00005
    rings = [edge, np.stack([out[:, 0], lip_h, out[:, 1]], 1)]               # the thin rail over the glass edge
    rn = [-side, -side]
    for t in np.linspace(0.0, 1.0, COLLAR_RINGS):                             # the collar, rail -> hull
        e = t * t * (3 - 2 * t)
        q = out + on * (COLLAR_W * t)
        h = lip_h + (hull_h - lip_h) * e
        slope = (hull_h - lip_h) * 6 * t * (1 - t) / COLLAR_W
        n = up[None, :] - side * slope[:, None]
        rings.append(np.stack([q[:, 0], h, q[:, 1]], 1))
        rn.append(n / np.linalg.norm(n, axis=1, keepdims=True))
    foot = rings[-1] + side * 0.004 - up * 0.006                              # tucked under the skin's edge
    wall_n = side * 0.006 + up * 0.004
    rings.append(foot)
    rn.append(wall_n / np.linalg.norm(wall_n, axis=1, keepdims=True))
    rings += [edge - side * 0.00005, well]                                    # inner face: glass edge -> well
    rn += [-side, -side]
    n0 = len(pos)
    pos = np.vstack([pos] + rings)
    nrm = np.vstack([nrm] + rn)
    ri = [n0 + r * k + np.arange(k) for r in range(len(rings))]
    pairs = [(ri[r], ri[r + 1], rn[r], True) for r in range(len(rings) - 3)]  # rail, collar, tuck: the hull
    pairs.append((ri[-2], ri[-1], -side, False))                              # inner face: frame (glass primitive)
    strips = []
    body_strips = []
    for a, b, want, to_body in pairs:
        for i in range(k):
            j = (i + 1) % k
            for t3 in ([a[i], a[j], b[i]], [a[j], b[j], b[i]]):
                t3 = np.array(t3)
                fnn = np.cross(pos[t3[1]] - pos[t3[0]], pos[t3[2]] - pos[t3[0]])
                (body_strips if to_body else strips).append(t3 if fnn @ want[i] >= 0 else t3[[0, 2, 1]])
    # old glass shards under the collar or just past it go too: each was a loop of its own, and the hangar's frame paint
    # (distance to the nearest cut edge) turned them into cream blobs on the new glazing
    d_g = cKDTree(out).query(gcen[:, [0, 2]])[0]
    keep_glass &= (tri.find_simplex(gcen[:, [0, 2]]) < 0) & (d_g > COLLAR_W + 0.004)
    tris = np.vstack([faces, np.array(strips)])
    # into the glass primitive's local space (the hull mesh node may carry a transform)
    m = g.world_of_mesh(0)
    inv = np.linalg.inv(m)
    lpos = pos @ inv[:3, :3].T + inv[:3, 3]
    lnrm = nrm @ m[:3, :3]
    lnrm /= np.linalg.norm(lnrm, axis=1, keepdims=True)
    attrs = {"POSITION": lpos, "NORMAL": lnrm}
    for name in prims[gi]["attributes"]:
        if name not in attrs:
            ncomp = g.accessor(prims[gi]["attributes"][name]).shape[1]
            attrs[name] = np.zeros((len(lpos), ncomp))
    # the frame's vertices carry U = 1 (the glazing's 0): HangarCockpit (FRAMES «frame_uv») paints the frame from it
    attrs["TEXCOORD_0"][n0:, 0] = 1.0
    # the band and its chamfer belong to the hull (Kanta 19.11: «смотрится как будто ты просто налепил её грубо
    # сверху. Она должна стать частью самолета»): body primitive, each vertex with the UV of the nearest remaining
    # skin vertex, so they carry the hull's own paint and panel texture up to the glass
    # each triangle has vertices of its own, all with the UV of the skin vertex nearest its centre: neighbouring
    # skin vertices at the torn rim sit on different atlas islands, and a UV per vertex smeared the atlas across the
    # band in stripes; one UV per triangle gives each the hull's paint colour at that spot
    bs = np.array(body_strips)
    keep_v = np.unique(bt[~sel])
    buv = g.accessor(prims[bi]["attributes"]["TEXCOORD_0"])
    near_v = keep_v[cKDTree(bp[keep_v]).query(pos[bs].mean(1))[1]]
    flat = bs.reshape(-1)
    battrs = {"POSITION": lpos[flat], "NORMAL": lnrm[flat], "TEXCOORD_0": np.repeat(buv[near_v], 3, axis=0)}
    for name in prims[bi]["attributes"]:
        if name not in battrs:
            battrs[name] = np.zeros((len(flat), g.accessor(prims[bi]["attributes"][name]).shape[1]))
    g.set_indices(0, bi, bt[~sel])
    g.append_tris(0, bi, battrs, np.arange(len(flat)).reshape(-1, 3))
    base = len(g.accessor(prims[gi]["attributes"]["POSITION"]))
    g.append_tris(0, gi, attrs, tris)
    g.set_indices(0, gi, np.vstack([gt[keep_glass], tris + base]))   # old glass on the surface goes
    g.save(dst)
    print("glaze: %d skin and %d old glass triangles removed, new glazing %d triangles (fit median miss %.4f), "
          "rail %.1f..%.1f mm over the glass edge"
          % (int(sel.sum()), int((~keep_glass).sum()), len(tris), float(np.median(np.abs(r))),
             float((band_h - pos[:k, 1]).min() * 1000), float((band_h - pos[:k, 1]).max() * 1000)))


if __name__ == "__main__":
    if sys.argv[1] == "glaze":
        glaze(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3])
    else:
        parts(sys.argv[2], sys.argv[3])
