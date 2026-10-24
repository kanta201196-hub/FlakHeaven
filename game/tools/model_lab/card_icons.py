# Volumetric card icons of weapons (PG-01, Kanta 24.10 «Значки ок»): Blender render of the hangar model
# + glow in the weapon family colour + a round chip with the family glyph, so look-alike missiles differ
# even at medal size. Output: game/art/icons/<id>.png (256 px, RGBA), drawn by CardIcons.draw.
#   python3 -I game/tools/model_lab/card_icons.py [id ...]       (bpy 5.2 as a module, PIL)
# Run from the repository root. Without ids — all of FAM.
import math, os, sys, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.getcwd()
HQ = os.path.join(ROOT, "game/models/weapons/hq/")
OUT = os.path.join(ROOT, "game/art/icons/")
# id: (model file, family rgb, glyph, camera yaw, roll, elevation in degrees)
FAM = {
	"aam": (HQ + "aam_2.glb", (70, 150, 255), "lock", 35, -45, 25),
	"srm": (HQ + "srm_2.glb", (255, 130, 40), "heat", 35, -45, 25),
	"agm": (HQ + "agm_2.glb", (235, 60, 50), "ground", 35, -45, 25),
	"rockets": (HQ + "rockets_2.glb", (255, 190, 40), "salvo", 35, -25, 25),
	"bombs": (HQ + "bombs_3.glb", (200, 110, 60), "cluster", 35, -40, 25),
	"hebomb": (HQ + "hebomb_2.glb", (255, 80, 40), "blast", 35, -40, 25),
	"flares": (HQ + "flares_2.glb", (255, 230, 80), "spark", 35, 0, 35),
	"turret": (os.path.join(ROOT, "game/models/turrets/turret_grach_t2.glb"), (150, 200, 120), "aim", 40, 0, 30),
}

RENDER = r'''
import sys, math, bpy
from mathutils import Vector, Quaternion
src, out, size, yaw, roll, elev = sys.argv[-6:]
size = int(size); yaw = float(yaw); roll = float(roll); elev = float(elev)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for o in objs:
	n = o.name.lower()
	if "pylon" in n:
		o.hide_render = True
objs = [o for o in objs if not o.hide_render]
mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
for o in objs:
	for c in o.bound_box:
		w = o.matrix_world @ Vector(c)
		mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
ctr = (mn + mx) / 2; rad = (mx - mn).length / 2
sc = bpy.context.scene
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = rad * 2.05
el = math.radians(elev); az = math.radians(yaw)
d = Vector((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el)))
cam.location = ctr + d * rad * 6
q = (ctr - cam.location).to_track_quat('-Z', 'Y')
cam.rotation_euler = (q @ Quaternion((0, 0, 1), math.radians(roll))).to_euler()
def light(name, energy, loc, size_, color):
	l = bpy.data.objects.new(name, bpy.data.lights.new(name, 'AREA'))
	l.data.energy = energy; l.data.color = color; l.data.size = rad * size_
	l.location = ctr + Vector(loc) * rad
	l.rotation_euler = (ctr - l.location).to_track_quat('-Z', 'Y').to_euler()
	sc.collection.objects.link(l)
light("key", 900 * rad * rad, (-2.5, -3, 4), 3, (1, 0.96, 0.9))
light("fill", 300 * rad * rad, (3.5, -2, 1.5), 3, (0.85, 0.9, 1))
light("rim", 900 * rad * rad, (1, 4, 2.5), 2, (1, 1, 1))
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.37, 0.4, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
sc.render.engine = 'CYCLES'; sc.cycles.samples = 48; sc.cycles.device = 'CPU'; sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = size
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'Medium High Contrast'
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
'''


def render(key: str, tmp: str) -> Image.Image:
	"""Renders the model in a fresh interpreter (bpy keeps state between imports) and crops it to a square."""
	src, _, _, yaw, roll, elev = FAM[key]
	raw = os.path.join(tmp, key + ".png")
	script = os.path.join(tmp, "render.py")
	with open(script, "w") as f:
		f.write(RENDER)
	subprocess.run([sys.executable, "-I", script, src, raw, "512", str(yaw), str(roll), str(elev)],
		check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
	im = Image.open(raw).convert("RGBA")
	im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
	side = int(max(im.size) * 1.12)
	sq = Image.new("RGBA", (side, side))
	sq.paste(im, ((side - im.size[0]) // 2, (side - im.size[1]) // 2))
	sh = Image.new("RGBA", sq.size)
	sh.putalpha(sq.getchannel("A").point(lambda v: int(v * 0.55)).filter(ImageFilter.GaussianBlur(side * 0.02)))
	out = Image.new("RGBA", sq.size)
	out.alpha_composite(sh, (int(side * 0.015), int(side * 0.025)))
	out.alpha_composite(sq)
	return out


def glyph(dr: ImageDraw.ImageDraw, c, r: float, kind: str, col) -> None:
	"""Family glyph: lock (radar homing), heat, ground target, salvo, cluster, blast, sparks, gun sight."""
	w = max(2, int(r * 0.16)); x, y = c
	if kind in ("lock", "aim"):
		dr.ellipse((x - r * .6, y - r * .6, x + r * .6, y + r * .6), outline=col, width=w)
		for a in range(4):
			t = a * math.pi / 2
			dr.line((x + math.cos(t) * r * .3, y + math.sin(t) * r * .3, x + math.cos(t) * r * .85, y + math.sin(t) * r * .85), fill=col, width=w)
		if kind == "aim":
			dr.ellipse((x - r * .14, y - r * .14, x + r * .14, y + r * .14), fill=col)
	elif kind == "heat":
		for i in range(3):
			o = (i - 1) * r * .45
			pts = [(x + o + math.sin(k / 4 * math.pi) * r * .15, y + r * .7 - k * r * .2) for k in range(8)]
			dr.line(pts, fill=col, width=w, joint="curve")
	elif kind == "ground":
		dr.line((x - r * .8, y + r * .55, x + r * .8, y + r * .55), fill=col, width=w)
		dr.polygon([(x - r * .3, y + r * .5), (x + r * .3, y + r * .5), (x + r * .2, y + r * .15), (x - r * .2, y + r * .15)], fill=col)
		dr.ellipse((x - r * .55, y - r * .55, x + r * .55, y + r * .55), outline=col, width=w)
	elif kind == "salvo":
		for i in range(3):
			o = (i - 1) * r * .45
			dr.line((x + o, y + r * .7, x + o, y - r * .3), fill=col, width=w)
			dr.polygon([(x + o - r * .15, y - r * .3), (x + o + r * .15, y - r * .3), (x + o, y - r * .7)], fill=col)
	elif kind == "cluster":
		for i in range(7):
			t = i / 7 * math.tau; rr = r * (.15 if i == 0 else .55)
			px, py = (x, y) if i == 0 else (x + math.cos(t) * rr, y + math.sin(t) * rr)
			dr.ellipse((px - r * .14, py - r * .14, px + r * .14, py + r * .14), fill=col)
	elif kind == "blast":
		pts = [(x + math.cos(i / 16 * math.tau) * r * (.8 if i % 2 == 0 else .35),
			y + math.sin(i / 16 * math.tau) * r * (.8 if i % 2 == 0 else .35)) for i in range(16)]
		dr.polygon(pts, fill=col)
	elif kind == "spark":
		for i in range(8):
			t = i / 8 * math.tau
			dr.line((x + math.cos(t) * r * .2, y + math.sin(t) * r * .2, x + math.cos(t) * r * .8, y + math.sin(t) * r * .8), fill=col, width=w)


def icon(key: str, model: Image.Image, S: int = 256) -> Image.Image:
	"""Glow plate in the family colour, the rendered weapon over it, family chip bottom-left."""
	_, rgb, g = FAM[key][:3]
	if key == "turret":   # the turret model is white: the game paints it in the plane's colour at run time
		r_, g_, b_, a_ = model.split()
		model = Image.merge("RGBA", (r_.point(lambda v: int(v * .62)), g_.point(lambda v: int(v * .64)), b_.point(lambda v: int(v * .5)), a_))
	im = Image.new("RGBA", (S, S))
	plate = Image.new("RGBA", (S, S))
	ImageDraw.Draw(plate).ellipse((S * .1, S * .1, S * .9, S * .9), fill=rgb + (150,))
	im.alpha_composite(plate.filter(ImageFilter.GaussianBlur(S * .08)))
	im.alpha_composite(model.resize((int(S * .92), int(S * .92)), Image.LANCZOS), (int(S * .04), int(S * .02)))
	cr = S * .17; cx, cy = S * .2, S * .8
	dr = ImageDraw.Draw(im)
	dr.ellipse((cx - cr - 3, cy - cr - 3, cx + cr + 3, cy + cr + 3), fill=(15, 18, 16, 255))
	dr.ellipse((cx - cr, cy - cr, cx + cr, cy + cr), fill=rgb + (255,))
	glyph(dr, (cx, cy), cr * .85, g, (15, 18, 16, 255))
	return im


if __name__ == "__main__":
	keys = sys.argv[1:] or list(FAM)
	os.makedirs(OUT, exist_ok=True)
	with tempfile.TemporaryDirectory() as tmp:
		for k in keys:
			icon(k, render(k, tmp)).save(OUT + k + ".png")
			print("icon", k)
