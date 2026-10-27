class_name SkinPatch
extends RefCounted
## Small meshes laid onto a plane model's own skin (S13, Kanta 27.10: anything placed on a plane follows its
## geometry — flush or with a fairing, never a box on top).
## Hangar3D and Render3D build them on the hangar or battle model of the player's plane, in model axes (nose +X,
## up +Y, length 1), and add them as children of that model: a regular grid over a footprint on the skin, every
## grid point dropped onto the highest skin triangle under it, so the patch follows the camber, sweep and
## curvature of the wing or fuselage there. Two kinds:
##   panel()   — a flush plate (lifted a hair along the skin normal) with UV 0..1 over it, for a shader to draw on:
##               the flare dispensers (FLARE_ROWS, shaders/flare_dispenser.gdshader);
##   blister() — a smooth teardrop fairing rising out of the skin, coloured from the skin texture under it
##               (vertex colours, material «mech_skin…» so Livery repaints it with the plane): the wing turret
##               barbettes of «Грач» 2.
## The skin is `PlaneHull.of(model)`: read once per body mesh, shared with the decals.

## Flare dispensers per plane: a row of flush panels on each side of the rear fuselage top, one more panel per
## flare tier (1–3), in model axes: [x of the first panel, step along x to the next one, |z| of the row].
## On the spine or tail boom just aft of the wing, where real aircraft carry them, clear of turrets, fins and
## moving surfaces; small next to the plane (PANEL), so they read as part of the airframe.
const FLARE_ROWS := {
	"fighter_1": [-0.27, -0.042, 0.033],
	"fighter_2": [-0.25, -0.042, 0.04],
	"attacker_1": [-0.275, -0.042, 0.024],
	"attacker_2": [-0.29, -0.036, 0.026],
	"bomber_1": [-0.14, -0.038, 0.013],
	"bomber_2": [-0.29, -0.042, 0.018],
}
## Flare panel length and width (model units, plane length 1)
const PANEL := Vector2(0.034, 0.013)
## Lift of a flush panel off the skin along its normal (model units): enough to win the depth test, too little to see
const LIFT := 0.0007
const DISPENSER_SHADER := preload("res://shaders/flare_dispenser.gdshader")

static var _images := {}
static var _panel_mats := {}
static var _fairings := {}


## Flush flare-dispenser panel at (x, z) on the top of `model`'s skin, with the dispenser shader; null when the
## skin is not under the whole panel. `seed` varies the spent cartridges between panels.
static func flare_panel(model: Node3D, x: float, z: float, seed: float) -> MeshInstance3D:
	var mesh := panel(model, Vector2(x, z), PANEL, 0.0, LIFT)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "flare_panel"
	mi.mesh = mesh
	if not _panel_mats.has(seed):
		var sm := ShaderMaterial.new()
		sm.shader = DISPENSER_SHADER
		sm.set_shader_parameter("seed", seed)
		sm.set_shader_parameter("aspect", PANEL.x / PANEL.y)
		_panel_mats[seed] = sm
	mi.material_override = _panel_mats[seed]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Flare panel centres for a plane key («attacker_2») at flare tier `tier` (1–3): Vector2(x, z) in model axes
static func flare_spots(key: String, tier: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var row: Array = FLARE_ROWS.get(key, [])
	if row.is_empty():
		return out
	for i in clampi(tier, 1, 3):
		for sd in [-1.0, 1.0]:
			out.append(Vector2(float(row[0]) + float(row[1]) * i, float(row[2]) * sd))
	return out


## Flush plate of `size` (length along x turned by `yaw`, width) centred at (x, z) on the top skin, lifted `lift`
## along the skin normal. UV.x runs from the aft end (0) to the front (1). A grid point over a small hole or crack
## of the remeshed skin takes the nearest hit of its row; null when more than a sixth of the points miss.
static func panel(model: Node3D, centre: Vector2, size: Vector2, yaw: float, lift: float) -> ArrayMesh:
	var h := PlaneHull.of(model)
	if h == null:
		return null
	var nu := 12
	var nv := 5
	var ax := Vector2(cos(yaw), sin(yaw))
	var az := Vector2(-ax.y, ax.x)
	var cand := h.in_rect_xz(Rect2(centre - Vector2.ONE * size.x, Vector2.ONE * size.x * 2.0))
	var hits: Array = []
	var miss := 0
	for j in nv + 1:
		for i in nu + 1:
			var p := centre + ax * (float(i) / nu - 0.5) * size.x + az * (float(j) / nv - 0.5) * size.y
			var hit := h.top_hit(cand, p.x, p.y)
			hits.append(hit)
			miss += 1 if hit.is_empty() else 0
	if miss * 6 > hits.size():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nv + 1:
		for i in nu + 1:
			var u := float(i) / nu
			var v := float(j) / nv
			var p := centre + ax * (u - 0.5) * size.x + az * (v - 0.5) * size.y
			var hit: Dictionary = hits[j * (nu + 1) + i]
			var k := 1
			while hit.is_empty() and k <= nu:
				for i2 in [i - k, i + k]:
					if hit.is_empty() and i2 >= 0 and i2 <= nu:
						hit = hits[j * (nu + 1) + i2]
				k += 1
			if hit.is_empty():
				return null
			var nrm: Vector3 = hit["n"]
			st.set_uv(Vector2(u, v))
			st.set_normal(nrm)
			st.add_vertex(Vector3(p.x, float(hit["y"]), p.y) + nrm * lift)
	_grid_indices(st, nu, nv)
	st.generate_normals()
	return st.commit()


## Teardrop fairing rising `height` out of the top skin at (x, z): `front` and `back` — its reach ahead of and behind
## the centre, `half_w` — half its width, `flat_r` — radius of its level crown, where a turret ring sits (model
## units). Outside the crown it falls smoothly to the skin, with zero slope where it meets it. Vertex colours come
## from the skin texture under each point (linear, the base seam and the aft end a little darker); the material is
## named «mech_skin_fairing» so Livery repaints it with the plane. A spot where the body skin has a hole (a slat or
## flap cut out of the hangar model, the part itself lies there) keeps the height of the point inside it.
## Returns {"mesh": ArrayMesh, "crown": y of its top} or {} when the skin is not under its centre.
static func blister(model: Node3D, centre: Vector2, front: float, back: float, half_w: float, height: float,
		flat_r := 0.0) -> Dictionary:
	var h := PlaneHull.of(model)
	if h == null:
		return {}
	var img := _image(h.tex)
	var nr := 12
	var na := 32
	var reach := maxf(maxf(front, back), half_w) * 1.1
	var cand := h.in_rect_xz(Rect2(centre - Vector2.ONE * reach, Vector2.ONE * reach * 2.0))
	var c0 := h.top_hit(cand, centre.x, centre.y)
	if c0.is_empty():
		return {}
	var crown := float(c0["y"]) + height
	var last: Array = []   # per spoke: the skin hit of the previous ring
	last.resize(na)
	last.fill(c0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in nr + 1:
		var r := float(ri) / nr
		for ai in (na if ri > 0 else 1):
			var a := TAU * float(ai) / na
			var ext := Vector2(cos(a) * (front if cos(a) > 0.0 else back), sin(a) * half_w)
			var p := centre + ext * r
			var hit := h.top_hit(cand, p.x, p.y)
			if hit.is_empty():
				hit = last[ai]
			else:
				last[ai] = hit
			var skin_y := float(hit["y"])
			# level crown out to flat_r, then a smooth fall to the skin
			var d := ext.length() * r
			var e := maxf(ext.length() - flat_r, 1e-5)
			var s := clampf((d - flat_r) / e, 0.0, 1.0)
			var y := maxf(skin_y + (crown - skin_y) * pow(1.0 - s * s, 1.5), skin_y) + LIFT
			var col := _sample(img, hit["uv"]).srgb_to_linear()
			col = col.darkened(0.22 * smoothstep(0.82, 1.0, r) + 0.12 * clampf(-ext.x * r / maxf(back, 1e-4), 0.0, 1.0))
			st.set_color(col)
			st.add_vertex(Vector3(p.x, y, p.y))
	# indices: centre fan, then ring strips; clockwise seen from above (Godot's front face)
	for ai in na:
		st.add_index(0)
		st.add_index(1 + ai)
		st.add_index(1 + (ai + 1) % na)
	for ri in range(1, nr):
		var b0 := 1 + (ri - 1) * na
		var b1 := 1 + ri * na
		for ai in na:
			var a0 := ai
			var a1 := (ai + 1) % na
			st.add_index(b0 + a0)
			st.add_index(b1 + a1)
			st.add_index(b0 + a1)
			st.add_index(b0 + a0)
			st.add_index(b1 + a0)
			st.add_index(b1 + a1)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.resource_name = "mech_skin_fairing"
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.82   # matte paint, like the skin around it (Livery keeps it as src_rough)
	mat.metallic = 0.08
	st.set_material(mat)
	return {"mesh": st.commit(), "crown": crown}


## Fairing of a wing turret of collar radius `rb` at (x, z) (model units): a teardrop blister longer behind the
## ring than ahead of it, as a barbette faired into the airflow, tall enough to hide the collar's skirt, sized for
## the largest turret tier so it does not change with the upgrade. MeshInstance3D named «turret_fairing» with
## meta «crown» (y of its top, where the turret ring sits); null when the skin is not under it.
## Cached per model mesh and spot: the battle model is rebuilt from a pool, the blister is not.
static func turret_fairing(model: Node3D, x: float, z: float, rb: float) -> MeshInstance3D:
	var d := _fairing(model, x, z, rb)
	if d.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = "turret_fairing"
	mi.mesh = d["mesh"]
	mi.set_meta("crown", d["crown"])
	return mi


## Crown height of the fairing turret_fairing() builds there (model units), NAN when it cannot be built
static func fairing_crown(model: Node3D, x: float, z: float, rb: float) -> float:
	var d := _fairing(model, x, z, rb)
	return NAN if d.is_empty() else float(d["crown"])


static func _fairing(model: Node3D, x: float, z: float, rb: float) -> Dictionary:
	var h := PlaneHull.of(model)
	if h == null:
		return {}
	var key := "%d_%.4f_%.4f_%.4f" % [h.pos.size(), x, z, rb]
	if not _fairings.has(key):
		_fairings[key] = blister(model, Vector2(x, z), rb * 1.4, rb * 2.2, rb * 1.45, rb * 0.45, rb * 1.05)
	return _fairings[key]


## Height of the top skin of `model` at (x, z) (model axes), NAN on a miss
static func top_y(model: Node3D, x: float, z: float) -> float:
	var h := PlaneHull.of(model)
	if h == null:
		return NAN
	var hit := h.top_hit(h.in_rect_xz(Rect2(Vector2(x, z) - Vector2.ONE * 0.01, Vector2.ONE * 0.02)), x, z)
	return NAN if hit.is_empty() else float(hit["y"])


static func _grid_indices(st: SurfaceTool, nu: int, nv: int) -> void:
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var c := a + nu + 1
			var d := c + 1
			# clockwise seen from above (Godot's front face, the skin normal side)
			st.add_index(a)
			st.add_index(b)
			st.add_index(d)
			st.add_index(a)
			st.add_index(d)
			st.add_index(c)


static func _image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	if not _images.has(tex):
		var img := tex.get_image()
		if img != null and img.is_compressed():
			img.decompress()
		_images[tex] = img
	return _images[tex]


static func _sample(img: Image, uv: Vector2) -> Color:
	if img == null:
		return Color(0.5, 0.5, 0.5)
	var w := img.get_width()
	var hh := img.get_height()
	var c := img.get_pixel(clampi(int(fposmod(uv.x, 1.0) * w), 0, w - 1), clampi(int(fposmod(uv.y, 1.0) * hh), 0, hh - 1))
	return Color(c.r, c.g, c.b, 1.0)
