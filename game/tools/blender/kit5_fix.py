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


if __name__ == "__main__":
    if sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3])
    else:
        parts(sys.argv[2], sys.argv[3])
