"""Prepare a raw Meshy GLB for sf_rework (PT-02, tier 4-5 planes).

Why: Meshy output faces -X, has arbitrary scale, bakes the canopy into the camo texture and sometimes grows spikes
or extra fins. sf_rework needs nose +X, length 1, centred, and separate materials so it repaints only the skin.
Materials this script leaves: "paint" (repainted in the class camo), "keep" (texture kept: nozzles, tank noses),
"dark" (plain dark metal: fans, sensor domes), "glass" (canopy).

usage: python3 meshy_prep.py cfg.json in.glb out.glb   (configs: meshy_prep_cfg/<art key>.json)
Config keys (boxes are [x0,x1,y0,y1,z0,z1] in prepared axes, all optional):
  glass_box + glass_v / glass_blue / glass_smooth / glass_lo / glass_hi - canopy by texture colour inside the box
  glass_geom [[box..., nz_min]]   - canopy by geometry (upward faces in the box) when its texture is silver
  uv_patch [[box..., vmax]]       - dark faces take the UV of the nearest light face (camo spots on a fin)
  keep_box [[box..., vmax?]]      - faces become "keep"; dark_box [[box...]] - faces become "dark"
  bisect / bisect_sub [pco, pno, ymin, ymax] - cut and drop the outer side, holes filled (trailing-edge spikes)
  kill_box [[box...]]             - delete faces and fill holes (an extra fin); drop_small N - drop islands < N faces
  domes [[cx,cy,cz,rx,ry,rz]]     - add a dark dome; caps [[x,y0,y1,z0,z1]] - dark plate, mirrored to -y
  debug_glass                     - paint the glass red to check the split on renders"""
import sys, json, math, bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix
def dark_mat():
    if "dark" in bpy.data.materials:
        return bpy.data.materials["dark"]
    dk = bpy.data.materials.new("dark"); dk.use_nodes = True
    b = dk.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.035, 0.035, 0.038, 1)
    b.inputs["Metallic"].default_value = 0.6; b.inputs["Roughness"].default_value = 0.55
    return dk


cfg = json.load(open(sys.argv[1])); src, out = sys.argv[2], sys.argv[3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obs = [o for o in bpy.data.objects if o.type == "MESH"]
for o in bpy.data.objects:
    if o.type != "MESH":
        bpy.data.objects.remove(o)
ob = obs[0]
if len(obs) > 1:
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs: o.select_set(True)
    bpy.context.view_layer.objects.active = ob; bpy.ops.object.join()
ob.data.transform(ob.matrix_world); ob.matrix_world = Matrix.Identity(4)
me = ob.data
me.transform(Matrix.Rotation(math.pi, 4, "Z"))   # Meshy nose -X -> +X
co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
mn, mx = co.min(0), co.max(0); c = (mn + mx) / 2; L = mx[0] - mn[0]
co = (co - c) / L; me.vertices.foreach_set("co", co.ravel()); me.update()
print("len", L, "ext", (mx - mn) / L)
# ---- glass by texture colour
mat = me.materials[0]
img = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and "Base" in str([l.to_socket.name for l in n.outputs[0].links])) if any(n.type == "TEX_IMAGE" for n in mat.node_tree.nodes) else None
bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
PX = None
if img is not None:
    _s = img.copy(); _s.scale(1024, 1024)
    PX = np.empty(1024 * 1024 * 4, np.float32); _s.pixels.foreach_get(PX); PX = PX.reshape(1024, 1024, 4)
UVL = bm.loops.layers.uv.active


def face_v(f):
    """Brightest channel of the texture under the face (corners and centre, median), 1.0 without a texture."""
    if PX is None:
        return 1.0
    uvs = [l[UVL].uv for l in f.loops]
    uvs.append(sum(uvs, Vector((0, 0))) / len(uvs))
    return float(np.median([PX[int(min(max(u.y, 0), 0.999) * 1024), int(min(max(u.x, 0), 0.999) * 1024), :3].max() for u in uvs]))


if img is not None and cfg.get("glass_box"):
    small = img.copy(); small.scale(1024, 1024)
    px = np.empty(1024 * 1024 * 4, np.float32); small.pixels.foreach_get(px); px = px.reshape(1024, 1024, 4)
    uvl = bm.loops.layers.uv.active
    gmat = mat.copy(); gmat.name = "glass"; me.materials.append(gmat)
    mat.name = "paint"
    gb = cfg["glass_box"]; ng = 0
    vmax = cfg.get("glass_v", 0.33); bmin = cfg.get("glass_blue", 0.02)
    for f in bm.faces:
        p = f.calc_center_median()
        if not (gb[0] <= p.x <= gb[1] and gb[2] <= p.y <= gb[3] and gb[4] <= p.z <= gb[5]):
            continue
        uvs = [l[uvl].uv for l in f.loops]
        uvs.append(sum(uvs, Vector((0, 0))) / len(uvs))
        cs = [px[int(min(max(u.y, 0), 0.999) * 1024), int(min(max(u.x, 0), 0.999) * 1024), :3] for u in uvs]
        dark = sum(1 for (r, g, b) in cs if max(r, g, b) < vmax and b - r > bmin)
        if dark * 2 >= len(cs):
            f.material_index = 1; ng += 1
    # grow/shrink once to drop speckles
    for _ in range(cfg.get("glass_smooth", 2)):
        flip = []
        for f in bm.faces:
            nb = [e.link_faces for e in f.edges]
            ns = [g.material_index for l in nb for g in l if g is not f]
            if ns and f.material_index == 1 and sum(ns) < len(ns) * cfg.get("glass_lo", 0.34): flip.append((f, 0))
            elif ns and f.material_index == 0 and sum(ns) > len(ns) * cfg.get("glass_hi", 0.66): flip.append((f, 1))
        for f, m in flip: f.material_index = m
    print("glass faces", ng, sum(1 for f in bm.faces if f.material_index == 1))
elif cfg.get("glass_geom"):
    # untextured model: the canopy is the skin inside the box(es) that faces up or out (normal z >= nz)
    gmat = bpy.data.materials.new("glass"); gmat.use_nodes = True; me.materials.append(gmat)
    mat.name = "paint"
    for f in bm.faces:
        p = f.calc_center_median()
        for gb in cfg["glass_geom"]:
            if gb[0] <= p.x <= gb[1] and gb[2] <= p.y <= gb[3] and gb[4] <= p.z <= gb[5] and f.normal.z >= gb[6]:
                f.material_index = 1
                break
    print("glass faces", sum(1 for f in bm.faces if f.material_index == 1))
else:
    mat.name = "paint"
# ---- uv_patch: [x0,x1,y0,y1,z0,z1, vmax] dark texels in the box (painted roundel-like spots) take the UV of the
# nearest light face, so the repaint keeps no dark mark there
for b in cfg.get("uv_patch", []):
    inb = [f for f in bm.faces if f.material_index == 0 and b[0] <= f.calc_center_median().x <= b[1]
           and b[2] <= f.calc_center_median().y <= b[3] and b[4] <= f.calc_center_median().z <= b[5]]
    dark = [f for f in inb if face_v(f) < b[6]]; light = [f for f in inb if face_v(f) >= b[6] + 0.08]
    if not light:
        continue
    lc = np.array([f.calc_center_median() for f in light])
    for f in dark:
        j = int(np.argmin(((lc - np.array(f.calc_center_median())) ** 2).sum(1)))
        uv = sum((l[UVL].uv for l in light[j].loops), Vector((0, 0))) / len(light[j].loops)
        for l in f.loops:
            l[UVL].uv = uv
    print("uv patched", len(dark))
# ---- keep_box: [x0,x1,y0,y1,z0,z1] faces keep the generator's texture (nozzles, tank noses): material "keep"
if cfg.get("keep_box"):
    km = me.materials[0].copy(); km.name = "keep"; me.materials.append(km); ki = len(me.materials) - 1
    nk = 0
    for f in bm.faces:
        if f.material_index != 0:
            continue
        c = f.calc_center_median()
        for b in cfg["keep_box"]:
            if b[0] <= c.x <= b[1] and b[2] <= c.y <= b[3] and b[4] <= c.z <= b[5] and (len(b) < 7 or face_v(f) < b[6]):
                f.material_index = ki; nk += 1
                break
    print("keep faces", nk)
# ---- dark_box: [x0,x1,y0,y1,z0,z1] faces get the plain dark metal (untextured models: fans, nozzles)
for b in cfg.get("dark_box", []):
    if "dark" not in [m.name for m in me.materials]:
        me.materials.append(dark_mat())
    di = [m.name for m in me.materials].index("dark")
    for f in bm.faces:
        c = f.calc_center_median()
        if f.material_index == 0 and b[0] <= c.x <= b[1] and b[2] <= c.y <= b[3] and b[4] <= c.z <= b[5]:
            f.material_index = di
# ---- bisect: [[px,py,pz],[nx,ny,nz]] keeps the side against the normal, fills the cut
for pco, pno in cfg.get("bisect", []):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    r = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=pco, plane_no=pno, clear_outer=True)
    edges = [e for e in r["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if cfg.get("bisect_fill", True) and edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
# ---- bisect_sub: [[px,py,pz],[nx,ny,nz], ymin, ymax] cut only the faces whose centre has ymin <= y <= ymax
for pco, pno, y0, y1 in cfg.get("bisect_sub", []):
    sub = [f for f in bm.faces if y0 <= f.calc_center_median().y <= y1]
    vs = {v for f in sub for v in f.verts}; es = {e for f in sub for e in f.edges}
    bmesh.ops.bisect_plane(bm, geom=list(vs) + list(es) + sub, plane_co=pco, plane_no=pno)
    pn = Vector(pno).normalized(); pc = Vector(pco)
    kill = [f for f in bm.faces if y0 <= f.calc_center_median().y <= y1 and (f.calc_center_median() - pc).dot(pn) > 1e-6]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bnd = [e for e in bm.edges if e.is_boundary]
    if bnd:
        bmesh.ops.holes_fill(bm, edges=bnd, sides=0)
    print("cut", len(kill))
# ---- kill_box: [x0,x1,y0,y1,z0,z1] delete faces whose centre is inside, cap the hole left in the skin
for b in cfg.get("kill_box", []):
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        if b[0] <= c.x <= b[1] and b[2] <= c.y <= b[3] and b[4] <= c.z <= b[5]:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bnd = [e for e in bm.edges if e.is_boundary]
    if bnd:
        bmesh.ops.holes_fill(bm, edges=bnd, sides=0)
    print("killed", len(kill))
bm.faces.index_update()
# ---- drop_small: delete loose islands with fewer faces than this (bits left by cuts)
if cfg.get("drop_small"):
    seen = set(); nd = 0
    for f0 in bm.faces:
        if f0.index in seen or not f0.is_valid:
            continue
        isl = []; st = [f0]; seen.add(f0.index)
        while st:
            f = st.pop(); isl.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index); st.append(g)
        if len(isl) < cfg["drop_small"]:
            bmesh.ops.delete(bm, geom=isl, context="FACES"); nd += len(isl)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    print("dropped small", nd)
bm.to_mesh(me); bm.free(); me.update()
# ---- domes: [cx,cy,cz, rx,ry,rz]
for d in cfg.get("domes", []):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=d[:3])
    s = bpy.context.active_object; s.scale = d[3:6]
    bpy.ops.object.transform_apply(scale=True)
    s.data.materials.append(dark_mat() if cfg.get("dome_dark", True) else bpy.data.materials["paint"])
    if s.data.uv_layers:   # uniform paint texel: all UVs to one point of plain paint
        uv = cfg.get("dome_uv", [0.5, 0.5])
        for l in s.data.uv_layers.active.data: l.uv = uv
    bpy.ops.object.select_all(action="DESELECT"); s.select_set(True); ob.select_set(True)
    bpy.context.view_layer.objects.active = ob; bpy.ops.object.join()
# ---- caps: [x, y0, y1, z0, z1] dark plate across an open duct (facing -X), mirrored to -y when "mirror"
if cfg.get("caps"):
    me.materials.append(dark_mat()); mi = len(me.materials) - 1
    bm = bmesh.new(); bm.from_mesh(me)
    for c in cfg["caps"]:
        for sgn in ((1, -1) if cfg.get("mirror", True) else (1,)):
            x, y0, y1, z0, z1 = c
            ys = sorted((y0 * sgn, y1 * sgn))
            vs = [bm.verts.new((x, ys[0], z0)), bm.verts.new((x, ys[0], z1)), bm.verts.new((x, ys[1], z1)), bm.verts.new((x, ys[1], z0))]
            f = bm.faces.new(vs); f.material_index = mi
            f.normal_update()
            if f.normal.x > 0: f.normal_flip()
    bm.to_mesh(me); bm.free(); me.update()
if cfg.get("debug_glass") and "glass" in bpy.data.materials:
    g = bpy.data.materials["glass"]; nt = g.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for l in list(b.inputs["Base Color"].links): nt.links.remove(l)
    b.inputs["Base Color"].default_value = (1, 0, 0, 1)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="AUTO")
print("ok", out)
