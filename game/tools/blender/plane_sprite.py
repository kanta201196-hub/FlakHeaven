"""2D plane sprite (game/art/planes/<class>_<lvl>.png) rendered from the plane's 3D model (Kanta 24.10: redraw the
fighter sprites from their new models).

The game ties sprite pixels to model length: the 3D model (length 1, nose +X) is scaled by the sprite width
(render3d.gd _ensure), PlaneFx jets, WeaponModels.wing_point and PlaneArt.shape_info / slot_points read the sprite in
pixels from its centre. So the sprite is a top-down orthographic view whose width is exactly the model length (the
width of the old sprite is kept), height = the model's span at that scale (+2 px), the model's origin at the image
centre, nose to the right (+X), transparent background. The sprite is also the plane's ground shadow
(Render3D._make_shadow) and the whole plane on «Низкое» graphics (Settings.gfx == 0).

Look like the other sprites in art/planes: soft top light from the front left, a slightly darker rim instead of an outline.
Rendered at SS× in Cycles (CPU), downscaled with Lanczos on premultiplied alpha.

Enemy sprites (art/enemies/e_<name>.png, VIS-01, Kanta 24.10) use the same renderer from the battle models
(models/battle/fh_battle_e_<name>.glb). Enemy scripts give the unit length in game pixels and Render3D scales the model
by the sprite width, so the old width is kept; hitboxes are fixed radii in the scripts and never read the sprite.
--height keeps the old canvas height when the model fits in it (the shadow quad and the low-preset relief keep their
proportions); a model wider than that canvas grows it instead of being clipped. --hub cuts a spinning part down to its
hub: the helicopter's blades are drawn in battle as a blur disc (RotorBlur), so the sprite (= ground shadow, and the
whole helicopter on «Низкое», as before) shows no static blades.

Run (bpy 5.x as a module): python3 -I plane_sprite.py <model.glb> <width px> <out.png> [--ss=4] [--samples=64]
    [--height=<px>] [--hub=<mesh name>:<radius>]...
  e.g. python3 -I game/tools/blender/plane_sprite.py game/models/hangar/fh_hangar_fighter_1.glb 170 game/art/planes/fighter_1.png
  enemies (width = old sprite width, --height = old sprite height):
    B=game/models/battle; E=game/art/enemies; S="python3 -I game/tools/blender/plane_sprite.py"
    $S $B/fh_battle_e_zsu.glb 256 $E/e_zsu.png --height=96
    for k in truck ifv scout technical; do $S $B/fh_battle_e_convoy_$k.glb 256 $E/e_convoy_$k.png --height=128; done
    $S $B/fh_battle_e_helicopter.glb 256 $E/e_helicopter.png --height=128 --hub=rotor:0.05 --hub=tail_rotor:0.03
    $S $B/fh_battle_e_interceptor.glb 150 $E/e_interceptor.png --height=125
"""

import argparse
import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

RIM = 0.35  # how much the outermost pixel ring is darkened


def scene_bounds(obs: list) -> tuple:
    """World-space (min, max) of mesh objects."""
    vs = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    return Vector(map(min, *vs)), Vector(map(max, *vs))


def cut_to_hub(ob: "bpy.types.Object", radius: float) -> None:
    """Delete the vertices of `ob` farther than `radius` (model lengths) from its origin: the blades of a rotor whose
    origin is the hub, the way RotorBlur cuts them in battle (Render3D.ROTOR_HUB / TAIL_HUB)."""
    import bmesh  # exists only once bpy is loaded, so not at the top (isort would put it first)

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    m = ob.matrix_world
    o = m.translation
    far = [v for v in bm.verts if (m @ v.co - o).length > radius]
    bmesh.ops.delete(bm, geom=far, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()


def setup_light(sc: "bpy.types.Scene") -> None:
    """Sun from above, a little from the nose and the left wing (the old sprites' highlight side), plus soft sky."""
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.0
    sun.angle = math.radians(12.0)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(-28.0), math.radians(-22.0), 0.0)
    sc.collection.objects.link(so)
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.62,
        0.64,
        0.68,
        1.0,
    )
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6


def main() -> int:
    """Render the sprite: top orthographic Cycles view at SS x, downscale, darker rim, save RGBA PNG."""
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("width", type=int)
    ap.add_argument("out")
    ap.add_argument("--ss", type=int, default=4)
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument(
        "--height",
        type=int,
        default=0,
        help="canvas height px (kept if the model fits)",
    )
    ap.add_argument(
        "--hub",
        action="append",
        default=[],
        help="<mesh>:<radius>: keep only the hub of a rotor (repeatable)",
    )
    a = ap.parse_args(
        sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    )
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(a.glb))
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for spec in a.hub:
        name, r = spec.rsplit(":", 1)
        hub = [o for o in obs if o.name == name]
        if not hub:
            print(f"no mesh {name!r} in {a.glb}")
            return 1
        cut_to_hub(hub[0], float(r))
    lo, hi = scene_bounds(obs)
    # the model is centred on its origin by the pipelines; the sprite centre is the origin, so the half span is the
    # larger side (keeps shape_info's |row - h/2| symmetric)
    half = max(abs(lo.y), abs(hi.y))
    w = a.width
    h = math.ceil(2.0 * half * w) + 2
    if (
        (h - w) % 2
    ):  # same parity as the width: the centre falls on the same pixel grid in both axes
        h += 1
    if a.height:
        if a.height >= h:
            h = a.height
        else:
            print(
                f"model span {h} px does not fit --height={a.height}: canvas grows to {h}"
            )
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = a.samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = w * a.ss
    sc.render.resolution_y = h * a.ss
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Standard"
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    # ortho_scale spans the wider image side; the width must cover exactly 1 model length
    cam.ortho_scale = max(w, h) / w
    co = bpy.data.objects.new("cam", cam)
    co.location = (0.0, 0.0, 5.0)
    co.rotation_euler = (
        0.0,
        0.0,
        0.0,
    )  # looking down -Z: +X right, +Y (left wing) up = Godot -Z up
    cam.clip_end = 20.0
    sc.collection.objects.link(co)
    sc.camera = co
    setup_light(sc)
    tmp = os.path.join(tempfile.mkdtemp(), "big.png")
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    from PIL import Image, ImageFilter

    big = np.asarray(Image.open(tmp)).astype(np.float64) / 255.0
    # Lanczos on premultiplied colour so the transparent edge does not bleed black
    rgb = big[..., :3] * big[..., 3:4]
    chans = [
        Image.fromarray(np.float32(c)).resize((w, h), Image.LANCZOS)
        for c in (rgb[..., 0], rgb[..., 1], rgb[..., 2], big[..., 3])
    ]
    r, g, b, al = (np.clip(np.asarray(c, np.float64), 0.0, 1.0) for c in chans)
    al[al < 1.0 / 255.0] = 0.0
    safe = np.maximum(al, 1e-6)
    col = np.dstack([r / safe, g / safe, b / safe])
    # thin darker rim along the silhouette, like the painted sprites: the plane reads on light sand
    er = np.asarray(
        Image.fromarray(np.float32(al)).filter(ImageFilter.MinFilter(3)), np.float64
    )
    col *= (1.0 - RIM * np.clip(al - er, 0.0, 1.0))[..., None]
    out = np.dstack([col, al])
    out = np.clip(out, 0.0, 1.0)
    Image.fromarray(np.uint8(np.round(out * 255.0)), "RGBA").save(a.out, optimize=True)
    print(
        f"SPRITE {a.out} {w}x{h} half span {half:.4f} (px {half * w:.1f}) x {lo.x:.4f}..{hi.x:.4f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
