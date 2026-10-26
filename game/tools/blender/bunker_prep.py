"""Prep the bunker scan (shortlist 94, Kanta 26.10) for sf_rework recipe e_bunker.

The scan is one unlit photogrammetry mesh: casemate, sandstone knoll, ground plate and shrubs in one texture, with
graffiti on the concrete. This keeps the casemate and the top of its knoll (the box CROP, source units, z up),
gives faces above Z_CON a separate 'concrete' material so the recipe can repaint the casemate apart from the rock,
and swaps the emission shader for a Principled BSDF because sf_rework reads base colour from one.

Run (source is an untrusted download, so -I; bpy 5.x as a module):
  python3 -I game/tools/blender/bunker_prep.py <src.glb> <prepped.glb>
  python3 -I game/tools/blender/sf_rework.py e_bunker <prepped.glb> <out_dir> --tex=2048 --jpeg=90
  cp <out_dir>/e_bunker.glb game/models/battle/fh_battle_e_bunker.glb
  python3 -I game/tools/blender/plane_sprite.py game/models/battle/fh_battle_e_bunker.glb 256 \
      game/art/enemies/e_bunker.png --height=212
"""
import sys

import bpy  # bpy first: bmesh is only importable once bpy is loaded
import bmesh  # noqa: E402

Z_CON = -1.9                                   # concrete starts above this height (the knoll is below)
CROP = (-3.5, 8.5, -13.3, 4.0, -4.2, 99.0)     # x0 x1 y0 y1 z0 z1: casemate plus the upper knoll as its rock base


def crop(o) -> None:
    """Delete faces of a mesh object whose centre lies outside CROP."""
    mw = o.matrix_world
    bm = bmesh.new()
    bm.from_mesh(o.data)
    x0, x1, y0, y1, z0, z1 = CROP
    dead = [f for f in bm.faces if not (x0 <= (mw @ f.calc_center_median()).x <= x1
                                        and y0 <= (mw @ f.calc_center_median()).y <= y1
                                        and z0 <= (mw @ f.calc_center_median()).z <= z1)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(o.data)
    bm.free()


def split_concrete(o) -> int:
    """Give faces above Z_CON a copy of the material named 'concrete'; returns how many faces moved."""
    mw = o.matrix_world
    con = bpy.data.materials.get("concrete") or o.data.materials[0].copy()
    con.name = "concrete"
    o.data.materials.append(con)
    k = len(o.data.materials) - 1
    n = 0
    for p in o.data.polygons:
        if (mw @ p.center).z > Z_CON:
            p.material_index = k
            n += 1
    return n


def principled(m) -> None:
    """Replace an unlit textured material with a Principled BSDF fed by the same image."""
    if not m.use_nodes:
        return
    nt = m.node_tree
    img = next((n.image for n in nt.nodes if n.type == "TEX_IMAGE" and n.image), None)
    if img is None:
        return
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(b.outputs[0], out.inputs[0])
    b.inputs["Roughness"].default_value = 0.9


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=sys.argv[1])
    for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        crop(o)
        print(o.name, "concrete faces", split_concrete(o), "of", len(o.data.polygons))
    for m in bpy.data.materials:
        principled(m)
    bpy.ops.export_scene.gltf(filepath=sys.argv[2], export_format="GLB")


main()
