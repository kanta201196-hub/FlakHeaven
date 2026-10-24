"""Renders a volume sequence (OpenVDB, e.g. the CC0 JangaFX/EmberGen sets) into flipbook frames (VFX-02).

The camera is orthographic at the combat tilt (28 deg from vertical, from the south), the sun is the game sun
(Render3D), so the baked light matches the scene; frames are straight-alpha PNGs for pack_atlas.py.

Run with Blender 4.2 in the background, settings through environment variables:
  SEQ=<folder with .vdb>  OUT=<frames folder>  FRAMES=1,4,7,...  RES=512  SAMPLES=32
  EMI=2.2 FSCALE=0.3 (fire brightness)  SIZE=330 CTR=0,0,80 (frame size and centre, sim units)
  ROT=0,0,180 (turn the set so its drift goes up the screen)  VIEW=Standard  TAG=f (file prefix)
  blender -b --python render_vdb.py
Bomb blast (game/art/vfx/blast_ground.png): Ground Explosion set, FRAMES 1..190 step 3 (64 frames), values above,
then pack_atlas.py. Dependencies: Blender 4.2.3 LTS (Cycles, CPU). Sets: CC0 VDB animations by JangaFX
(https://jangafx.com/software/embergen/download/free-vdb-animations: Ground Explosion), not kept anywhere
(GBs; download again from that page). Decision: VFX-02, 2026-10-24 (our own Mantaflow bakes in the cloud
came out smooth and detail-free; the CC0 sets carry real billowing detail).
"""
import bpy, os, math, mathutils
SEQ = os.environ['SEQ']; OUT = os.environ['OUT']; FR = [int(x) for x in os.environ.get('FRAMES','10,20,30,45,60,90,130,180').split(',')]
RES = int(os.environ.get('RES','384'))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
files = sorted(f for f in os.listdir(SEQ) if f.endswith('.vdb'))
vol = bpy.data.volumes.new('fx'); vol.filepath = os.path.join(SEQ, files[0])
vol.is_sequence = True; vol.frame_duration = len(files); vol.frame_start = 1
ob = bpy.data.objects.new('fx', vol); sc.collection.objects.link(ob)
ob.rotation_euler = tuple(math.radians(float(a)) for a in os.environ.get('ROT', '0,0,0').split(','))
sc.frame_set(FR[len(FR)//2]); vol.grids.load()
print('GRIDS', [g.name for g in vol.grids])
dg = bpy.context.evaluated_depsgraph_get(); ev = ob.evaluated_get(dg)
bb = [ev.matrix_world @ mathutils.Vector(c) for c in ev.bound_box]
lo = mathutils.Vector([min(v[i] for v in bb) for i in range(3)]); hi = mathutils.Vector([max(v[i] for v in bb) for i in range(3)])
print('BOUNDS', lo, hi)
ctr = (lo + hi) / 2; size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) * float(os.environ.get('FIT','1.0'))
if 'CTR' in os.environ: ctr = mathutils.Vector([float(a) for a in os.environ['CTR'].split(',')])   # bound_box of a VDB sequence is not reliable
if 'SIZE' in os.environ: size = float(os.environ['SIZE'])
mat = bpy.data.materials.new('vol'); mat.use_nodes = True; nt = mat.node_tree; nt.nodes.clear()
out = nt.nodes.new('ShaderNodeOutputMaterial'); pv = nt.nodes.new('ShaderNodeVolumePrincipled')
pv.inputs['Density'].default_value = float(os.environ.get('DENS','2.0'))
pv.inputs['Color'].default_value = tuple(float(a) for a in os.environ.get('ALB','0.42,0.37,0.32').split(',')) + (1,); pv.inputs['Anisotropy'].default_value = 0.3
pv.inputs['Density Attribute'].default_value = 'density'
fa = nt.nodes.new('ShaderNodeAttribute'); fa.attribute_name = os.environ.get('FIRE','flames')
mul = nt.nodes.new('ShaderNodeMath'); mul.operation='MULTIPLY'; mul.inputs[1].default_value = float(os.environ.get('FSCALE','1.0'))
ramp = nt.nodes.new('ShaderNodeValToRGB'); cr = ramp.color_ramp
cr.elements[0].position = 0.02; cr.elements[0].color = (0,0,0,1)
cr.elements[1].position = 1.0; cr.elements[1].color = (1.0,0.85,0.5,1)
e = cr.elements.new(0.2); e.color = (0.6,0.07,0.01,1); e = cr.elements.new(0.55); e.color = (1.0,0.4,0.06,1)
nt.links.new(fa.outputs['Fac'], mul.inputs[0]); nt.links.new(mul.outputs[0], ramp.inputs[0])
nt.links.new(ramp.outputs[0], pv.inputs['Emission Color'])
pv.inputs['Emission Strength'].default_value = float(os.environ.get('EMI','8'))
nt.links.new(pv.outputs[0], out.inputs['Volume']); vol.materials.append(mat)
tilt = math.radians(float(os.environ.get('TILT','28'))); dist = size * 3
cam_d = bpy.data.cameras.new('c'); cam_d.type = 'ORTHO'; cam_d.ortho_scale = size; cam_d.clip_end = dist * 4
cam = bpy.data.objects.new('c', cam_d); sc.collection.objects.link(cam); sc.camera = cam
cam.location = ctr + mathutils.Vector((0, -math.sin(tilt), math.cos(tilt))) * dist
cam.rotation_euler = (tilt, 0, 0)
sun_d = bpy.data.lights.new('s', 'SUN'); sun_d.energy = float(os.environ.get('SUN','5')); sun = bpy.data.objects.new('s', sun_d)
sc.collection.objects.link(sun)
# game sun (Render3D: shines along Godot (0.62, -0.85, 0.75)); Godot -Z (screen up) is Blender +Y
sun.rotation_euler = mathutils.Vector((0.62, -0.75, -0.85)).to_track_quat('-Z', 'Y').to_euler()
sun_d.color = (1.0, 0.9, 0.76)
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (0.55,0.62,0.75,1); w.node_tree.nodes['Background'].inputs[1].default_value = 0.7
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = int(os.environ.get('SAMPLES','32'))
sc.cycles.volume_bounces = 1; sc.cycles.volume_step_rate = float(os.environ.get('STEP','1.0'))
sc.render.resolution_x = RES; sc.render.resolution_y = RES; sc.render.film_transparent = True
sc.view_settings.view_transform = os.environ.get('VIEW', 'AgX')
import time
for f in FR:
    t = time.time(); sc.frame_set(f); sc.render.filepath = f'{OUT}/{os.environ.get("TAG","v")}{f:03d}.png'
    bpy.ops.render.render(write_still=True); print('FRAME', f, round(time.time() - t))
