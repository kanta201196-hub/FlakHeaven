"""Renders a volume sequence (OpenVDB) into flipbook frames for GpuFx (VFX-02, 2026-10-24).

The camera is orthographic at the combat tilt (28 deg from vertical, from the south) and the sun is the game
sun (Render3D shines along Godot (0.62, -0.85, 0.75)), so the baked light matches the scene at cam_tilt 28.
Frames are straight-alpha PNGs, input for pack_atlas.py.

Source sets: CC0 VDB animations by JangaFX (https://jangafx.com/software/embergen/download/free-vdb-animations),
not kept anywhere (GBs; download again from that page). Decision: our own Mantaflow bakes in the cloud came
out smooth and detail-free; these sets carry real billowing detail.
Dependencies: Blender 4.2.3 LTS (Cycles, CPU). Run from the repo root; arguments go after "--":
  blender -b --python game/tools/vfx_bake/render_vdb.py -- SEQ_DIR OUT_DIR [options]
Bomb blast (game/art/vfx/blast_ground.png, set "Ground Explosion"):
  blender -b --python game/tools/vfx_bake/render_vdb.py -- <set>/ground_explosion_VDB frames/ \
      --first 1 --step 3 --count 64 --res 512 --samples 32 --emission 2.0 --fire-scale 0.2 \
      --size 330 --centre 0,-41,58 --rot 0,0,180
  python3 game/tools/vfx_bake/pack_atlas.py frames/ game/art/vfx/blast_ground.png
"""
import argparse
import math
import sys
import time
from pathlib import Path

import bpy
import mathutils

# Godot sun direction (Render3D) in Blender axes: Godot -Z (screen up) is Blender +Y, Godot +Y is Blender +Z
SUN_DIR = mathutils.Vector((0.62, -0.75, -0.85))
SUN_COLOR = (1.0, 0.9, 0.76)


def vec(text: str) -> tuple[float, ...]:
    """Parses "x,y,z" into floats."""
    return tuple(float(a) for a in text.split(","))


def parse() -> argparse.Namespace:
    """Arguments after Blender's "--"."""
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("seq", type=Path, help="folder with the .vdb sequence")
    ap.add_argument("out", type=Path, help="folder for the frames")
    ap.add_argument("--first", type=int, default=1, help="first simulation frame")
    ap.add_argument("--step", type=int, default=3, help="simulation frames per flipbook frame")
    ap.add_argument("--count", type=int, default=64, help="flipbook frames")
    ap.add_argument("--res", type=int, default=512, help="frame size, px")
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--density", type=float, default=2.0, help="smoke density multiplier")
    ap.add_argument("--albedo", type=vec, default=(0.42, 0.37, 0.32), help="smoke colour (dusty Нагорье grey-brown)")
    ap.add_argument("--fire-grid", default="flames", help="grid that drives the fire emission")
    ap.add_argument("--fire-scale", type=float, default=0.2, help="grid value to colour-ramp position")
    ap.add_argument("--emission", type=float, default=2.0, help="fire emission strength")
    ap.add_argument("--sun", type=float, default=5.0, help="sun strength")
    ap.add_argument("--tilt", type=float, default=28.0, help="camera tilt from vertical, deg (game cam_tilt)")
    ap.add_argument("--size", type=float, default=330.0, help="frame side, simulation units")
    ap.add_argument("--centre", type=vec, default=(0.0, 0.0, 80.0), help="frame centre, simulation units")
    ap.add_argument("--rot", type=vec, default=(0.0, 0.0, 180.0), help="set rotation, deg (drift up the screen)")
    ap.add_argument("--view", default="Standard", help="view transform")
    ap.add_argument("--prefix", default="f", help="frame file prefix")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return ap.parse_args(argv)


def volume_material(a: argparse.Namespace) -> bpy.types.Material:
    """Lit smoke from the density grid, fire emission from a colour ramp over the fire grid."""
    mat = bpy.data.materials.new("vol")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Density"].default_value = a.density
    pv.inputs["Color"].default_value = a.albedo + (1.0,)
    pv.inputs["Anisotropy"].default_value = 0.3
    pv.inputs["Density Attribute"].default_value = "density"
    fire = nt.nodes.new("ShaderNodeAttribute")
    fire.attribute_name = a.fire_grid
    scale = nt.nodes.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = a.fire_scale
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.02
    cr.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (1.0, 0.85, 0.5, 1.0)
    cr.elements.new(0.2).color = (0.6, 0.07, 0.01, 1.0)
    cr.elements.new(0.55).color = (1.0, 0.4, 0.06, 1.0)
    nt.links.new(fire.outputs["Fac"], scale.inputs[0])
    nt.links.new(scale.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], pv.inputs["Emission Color"])
    pv.inputs["Emission Strength"].default_value = a.emission
    nt.links.new(pv.outputs[0], out.inputs["Volume"])
    return mat


def main() -> int:
    a = parse()
    files = sorted(p for p in a.seq.iterdir() if p.suffix == ".vdb")
    if not files:
        print(f"no .vdb in {a.seq}", file=sys.stderr)
        return 1
    a.out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    vol = bpy.data.volumes.new("fx")
    vol.filepath = str(files[0])
    vol.is_sequence = True
    vol.frame_duration = len(files)
    vol.frame_start = 1
    vol.materials.append(volume_material(a))
    ob = bpy.data.objects.new("fx", vol)
    sc.collection.objects.link(ob)
    ob.rotation_euler = tuple(math.radians(r) for r in a.rot)

    tilt = math.radians(a.tilt)
    centre = mathutils.Vector(a.centre)
    dist = a.size * 3.0
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = a.size
    cam_data.clip_end = dist * 4.0
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = centre + mathutils.Vector((0.0, -math.sin(tilt), math.cos(tilt))) * dist
    cam.rotation_euler = (tilt, 0.0, 0.0)

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = a.sun
    sun_data.color = SUN_COLOR
    sun = bpy.data.objects.new("sun", sun_data)
    sc.collection.objects.link(sun)
    sun.rotation_euler = SUN_DIR.to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("sky")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.75, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7

    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = a.samples
    sc.cycles.volume_bounces = 1
    sc.render.resolution_x = a.res
    sc.render.resolution_y = a.res
    sc.render.film_transparent = True
    sc.view_settings.view_transform = a.view
    for i in range(a.count):
        f = a.first + a.step * i
        t = time.time()
        sc.frame_set(f)
        sc.render.filepath = str(a.out / f"{a.prefix}{f:03d}.png")
        bpy.ops.render.render(write_still=True)
        print("FRAME", f, round(time.time() - t), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
