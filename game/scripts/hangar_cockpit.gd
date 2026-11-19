class_name HangarCockpit
extends RefCounted
## Glazed cockpit of the hangar plane (owner's ask 31.10: canopy glass that reads as glass, with the seat and the
## frame visible under it). The models' canopy is a cut-out of the skin (tools/blender/canopy_glass.py, material
## «glass») with nothing under it, drawn with the opaque dark shaders/canopy_glass.gdshader that battle keeps.
## In the hangar Hangar3D calls attach() after the livery: the GLB glass surface is hidden and a node «cockpit»
## takes its place under the model root, in model axes (nose +X, up +Y, length 1):
##   • the same glass triangles with clear, fresnel-tinted glass (shaders/canopy_glass_hangar.gdshader) whose
##     frame — the sill along the cut edge, bows across and ribs along (FRAMES) — is opaque painted metal;
##   • a tub that closes the hole in the skin: walls from every edge of the cut down and in, and a floor;
##   • the seat (pan, back, headrest, belts), the instrument panel with its coaming and gauges, side consoles and the
##     stick, sized from the glass loop so they fit every canopy.
## Glass loops and rim distances are computed once per plane and cached; the cockpit has its own materials, which
## Livery leaves alone (no texture, names outside its list).

const NODE := "cockpit"
## Per plane: bows — canopy frame bows across the glass, as fractions of each glass loop's length from its front;
## ribs — frame ribs along it at these fractions of the loop's half-width (0 — on the centre line); seats —
## [fraction of the loop length from its front, z as a fraction of the half-width] per seat in the main loop;
## own_pit — the model has its own cockpit tub and frame under thick glass panes (the source model of «Оса» 1): no
## tub and no painted frame; the glass is smoked (its tub texture is smeared since the UV rebake) and a seat and a
## panel stand in `pit` = [front x, length, floor y, half-width] of the space under the canopy; tub — the tub depth in
## half-widths of the glass loop where TUB_DEPTH would push its floor out through a shallow fuselage (wide or low glass:
## «Оса» 4/5, «Кит» 4/5; measured as glass bottom − depth × half-width against the belly under the canopy);
## main — [centre z, half-width] of the main glass loop where the welded glass falls apart into many small loops and
## the longest one is lopsided: «Кит» 5's framed glasshouse gives a main loop centred at z 0.027 with a half-width
## of 0.108 (the glass spans |z| ≤ 0.08), which dropped the tub floor through the belly and stood the seats and side
## consoles outside the hull side under the nose.
## liner — a glazed nose or glasshouse (3.5-s19, Kanta: «Кит 1 — кусков не хватает», «дыра в модели Кит 5»): the
## glass wraps the nose down to the belly, so a tub dropped from its rim hung below the nose as black slabs and left
## the sky showing through the far side; such a plane gets a dark liner a little inside the glass instead (the glass
## shows depth and the cabin's dark inside, never the sky), and no seats. Their glass comes in many small panes cut
## out between the model's own frame strips (Kanta 18.11: «Кит 1 — всё равно видны дыры», «Кит 5 — закрашено стекло
## кабины»): the painted sill is off, so are the bows on «Кит» 1 (its glazing has frames of its own), the glass
## normals are rebuilt to point out of the fuselage (_outward_normals), and the liner closes every pane edge with a
## fan towards the glass centre (gaps between panes and skin showed the sky). «Кит» 5's canopy is one fitted shell
## (kit5_fix.py glaze) with bows across its main loop only.
## cabin — [x0, floor, sight x, seat x, (dome x0, dome x1, dome y0)] (Kanta 18.11 on «Кит» 1's nose: «что за тёмная сфера внутри?», «если там
## стекло, почему оно закрашено?»): the liner shell under every pane read as a dark ball and turned the glazing into
## a dark painted surface. A lined plane with `cabin` gets a see-through cabin instead: the glass is drawn from both
## sides, the inside of the hull skin ahead of x0 (frames, the skin round the glazing) gets an inner face in cockpit
## paint, a bulkhead closes the hull at x0, a floor runs at `floor` (fraction of the glazing's height from its
## bottom), with a bombsight at `sight x` and the bombardier's seat at `seat x`. Through the glass you see the
## cabin, the far frames and the far panes, as through a real glazed nose. The optional dome triple turns the glass
## dome over the cabin into a gunner's turret (_dome_turret).
## frame_uv — the glass is a fitted shell with a modelled sill round it, whose vertices carry U = 1 (the glazing's
## U = 0): «Кит» 5's canopy (kit5_fix.py glaze) ends in a thin rail and a collar of hull round it (in the body
## primitive, hull paint; Kanta 19.11: «она должна стать частью самолета»); only the inner face down into the
## cockpit is in the glass primitive. The frame is painted from U, not from the
## distance to the cut edge: that distance, measured to the edge's vertices, painted a sawtooth strip on the steep
## glass next to the inner face.
## Read off the canopy shapes: bubble canopies have a windscreen bow only, the attackers a windscreen and a hood
## bow, the bombers a framed glasshouse.
const FRAMES := {
	"fighter_t1": {"bows": [0.3], "ribs": [], "seats": [[0.62, 0.0]]},
	"attacker_t1": {"bows": [0.32], "ribs": [], "seats": [[0.6, -0.42], [0.6, 0.42]]},   # side by side
	"bomber_t1": {"bows": [], "ribs": [], "seats": [], "liner": true, "cabin": [0.335, 0.3, 0.45, 0.415, 0.36, 0.401, 0.0105]},
	"fighter_1": {"bows": [], "ribs": [], "seats": [[0.62, 0.0]], "own_pit": true, "pit": [0.25, 0.085, -0.02, 0.019]},
	"fighter_2": {"bows": [0.3], "ribs": [], "seats": [[0.62, 0.0]]},
	"attacker_1": {"bows": [], "ribs": [], "seats": [[0.6, 0.0]]},   # 3.5-s19 hulls: the frames are modelled
	"attacker_2": {"bows": [], "ribs": [], "seats": [[0.6, 0.0]]},
	"bomber_1": {"bows": [0.22, 0.45, 0.7], "ribs": [0.0], "seats": [[0.6, -0.42], [0.6, 0.42]]},
	"bomber_2": {"bows": [0.24, 0.5, 0.76], "ribs": [0.0], "seats": [[0.6, -0.42], [0.6, 0.42]]},
	"fighter_t4": {"bows": [0.3], "ribs": [], "seats": [[0.62, 0.0]], "tub": 1.0},
	"fighter_t5": {"bows": [0.3], "ribs": [], "seats": [[0.6, 0.0]], "tub": 1.2},
	"attacker_t4": {"bows": [0.3, 0.62], "ribs": [], "seats": [[0.28, 0.0], [0.7, 0.0]]},   # tandem two-seater
	"attacker_t5": {"bows": [0.33, 0.66], "ribs": [], "seats": [[0.25, 0.0], [0.58, 0.0]]},   # three-pane canopy
	"bomber_t4": {"bows": [0.25, 0.5, 0.75], "ribs": [0.0], "seats": [[0.55, -0.42], [0.55, 0.42]], "tub": 1.0},
	"bomber_t5": {"bows": [0.3, 0.62], "ribs": [0.0], "seats": [[0.42, -0.45], [0.42, 0.45]], "tub": 0.7, "frame_uv": true},
}
## Frame paint when the livery has no colours of its own (the source paint): a dark worn grey
const FRAME_DEFAULT := Color(0.22, 0.23, 0.22)
## Liner (FRAMES «liner»): how far inside the glass it sits, model units (about 12 cm on a 25 m bomber)
const LINER_D := 0.005
## Cabin (FRAMES «cabin»): the inner face of the hull skin sits this far inside it; the floor's station step
const CABIN_SKIN := 0.0006
const CABIN_STEP := 0.004
## Tub depth below the sill, in half-widths of the glass loop, and how far its floor draws in towards the middle
const TUB_DEPTH := 1.5
const TUB_INSET := 0.25
## Interior colours (sRGB): cockpit paint, seat cushion, black panel, gauge rims, belts
const C_TUB := Color(0.30, 0.32, 0.30)
const C_SEAT := Color(0.12, 0.12, 0.12)
const C_CUSHION := Color(0.30, 0.26, 0.19)
const C_PANEL := Color(0.05, 0.05, 0.055)
const C_GAUGE := Color(0.36, 0.37, 0.35)
const C_BELT := Color(0.42, 0.38, 0.27)
# the bombardier's station (glazed noses): warm leather and khaki against the dark cabin, so the figure reads
const C_JACKET := Color(0.45, 0.33, 0.2)
const C_HELMET := Color(0.24, 0.16, 0.1)
const C_FACE := Color(0.72, 0.55, 0.43)
const C_GOGGLES := Color(0.55, 0.6, 0.62)
const C_COLLAR := Color(0.62, 0.55, 0.42)
const C_GUN := Color(0.09, 0.09, 0.1)
const C_DRUM := Color(0.2, 0.21, 0.2)
const C_DIAL := Color(0.8, 0.78, 0.68)
const C_OXYGEN := Color(0.3, 0.4, 0.5)
## Glass opacity looking straight through on an own_pit model (smoked, the tub under it is not ours)
const OWN_PIT_ALPHA := 0.4
const GLASS_SHADER := preload("res://shaders/canopy_glass_hangar.gdshader")

static var _cache := {}
static var _hide_mat: StandardMaterial3D
static var _tub_mat: StandardMaterial3D


## Builds the glazed cockpit of plane `key` («fighter_1» …) under `model` and hides the GLB glass; `frame` — the
## frame paint (the livery's main tone, or FRAME_DEFAULT). Returns the «cockpit» node, or null when the model has no
## glass surface. Replaces a cockpit built earlier on the same model.
static func attach(model: Node3D, key: String, frame: Color) -> Node3D:
	var old := model.get_node_or_null(NODE)
	if old != null:
		model.remove_child(old)
		old.queue_free()
	var data: Dictionary = _cache.get(key, {})
	if data.is_empty():
		data = _measure(model, key)
		_cache[key] = data
	if (data["glass"] as ArrayMesh) == null:
		return null
	_hide_glass(model)
	var root := Node3D.new()
	root.name = NODE
	var gl := MeshInstance3D.new()
	gl.name = "glass"
	gl.mesh = data["glass"]
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := ShaderMaterial.new()
	gm.resource_name = "cockpit_glass"
	gm.shader = GLASS_SHADER
	gm.set_shader_parameter("frame_col", frame)
	var bows: PackedFloat32Array = data["bows"]
	var ribs: PackedFloat32Array = data["ribs"]
	gm.set_shader_parameter("bows", bows)
	gm.set_shader_parameter("bow_count", bows.size())
	gm.set_shader_parameter("ribs", ribs)
	gm.set_shader_parameter("rib_count", ribs.size())
	if data["own_pit"] or data.get("liner", false):
		gm.set_shader_parameter("rim_w", 0.0)
	if data.get("frame_uv", false):
		gm.set_shader_parameter("rim_w", 0.5)   # UV2.x = 1 − U: 0 on the frame, 1 on the glazing
	if data["own_pit"]:
		gm.set_shader_parameter("alpha_min", OWN_PIT_ALPHA)
	gl.material_override = gm
	root.add_child(gl)
	for part: String in ["tub", "interior"]:
		if data[part] == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = data[part]
		mi.material_override = _interior_material()
		root.add_child(mi)
	model.add_child(root)
	return root


## Frame paint for a livery: its main tone, or FRAME_DEFAULT for the source paint
static func frame_colour(cls: String, livery_id: String) -> Color:
	return Livery.main_tone(cls, livery_id, FRAME_DEFAULT)


## Overrides every GLB «glass» surface under `model` with an invisible material (the hangar glass replaces it)
static func _hide_glass(model: Node3D) -> void:
	if _hide_mat == null:
		_hide_mat = StandardMaterial3D.new()
		_hide_mat.resource_name = "cockpit_hidden"
		_hide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_hide_mat.alpha_scissor_threshold = 0.5
		_hide_mat.albedo_color = Color(0, 0, 0, 0)
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or _under_cockpit(mi, model):
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m != null and String(m.resource_name) == "glass":
				mi.set_surface_override_material(si, _hide_mat)


static func _under_cockpit(n: Node, model: Node3D) -> bool:
	while n != null and n != model:
		if n.name == NODE:
			return true
		n = n.get_parent()
	return false


static func _interior_material() -> StandardMaterial3D:
	if _tub_mat == null:
		_tub_mat = StandardMaterial3D.new()
		_tub_mat.resource_name = "cockpit_interior"
		_tub_mat.vertex_color_use_as_albedo = true
		_tub_mat.vertex_color_is_srgb = true
		_tub_mat.roughness = 0.75
		_tub_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _tub_mat


## Transform of `n` into the axes of `model` (the model root's own scale left out, as Livery does)
static func _rel(n: Node, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Reads the glass of `model` once: the glass mesh with rim distances, its loops, frames, the tub and the furnishing.
## {glass: ArrayMesh or null, bows, ribs: PackedFloat32Array, tub, interior: ArrayMesh or null, own_pit: bool}
static func _measure(model: Node3D, key: String) -> Dictionary:
	var pos := PackedVector3Array()   # welded vertices, model axes
	var nrm := PackedVector3Array()
	var uvx := PackedFloat32Array()   # U of each welded vertex (FRAMES «frame_uv»)
	var tris := PackedInt32Array()
	var weld := {}
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or _under_cockpit(mi, model):
			continue
		var xf := _rel(mi, model)
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m == null or String(m.resource_name) != "glass":
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ids.is_empty():
				ids.resize(vs.size())
				for i in vs.size():
					ids[i] = i
			var local: Array[int] = []
			local.resize(vs.size())
			for i in vs.size():
				var p := xf * vs[i]
				var k := Vector3i(roundi(p.x * 1e5), roundi(p.y * 1e5), roundi(p.z * 1e5))
				if not weld.has(k):
					weld[k] = pos.size()
					pos.append(p)
					nrm.append((xf.basis * ns[i]).normalized() if i < ns.size() else Vector3.UP)
					uvx.append(uvs[i].x if i < uvs.size() else 0.0)
				local[i] = weld[k]
			for i in ids.size():
				tris.append(local[ids[i]])
	if tris.size() < 9:
		return {"glass": null, "tub": null, "interior": null, "own_pit": false}
	var loops := _loops(tris)
	var spec: Dictionary = FRAMES.get(key, {"bows": [0.3], "ribs": [], "seats": [[0.6, 0.0]]})
	var rim := _rim_distance(pos, loops)
	if spec.get("frame_uv", false):
		for i in rim.size():
			rim[i] = 1.0 - uvx[i]
	var own: bool = spec.get("own_pit", false)
	var liner: bool = spec.get("liner", false)
	if liner:
		nrm = _outward_normals(pos, tris)
	var bows := PackedFloat32Array()
	var ribs := PackedFloat32Array()
	var tub := SurfaceTool.new()
	tub.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main_i := 0
	var main_len := -1.0
	var boxes: Array[Dictionary] = []
	for li in loops.size():
		var b := _loop_box(pos, loops[li])
		b["depth"] = float(spec.get("tub", TUB_DEPTH))
		boxes.append(b)
		if float(b["len"]) > main_len:
			main_len = b["len"]
			main_i = li
	if spec.get("frame_uv", false):
		# a fitted canopy has three open edges: the glazing's own edge, the sill's foot outside the glass and its inner
		# face's foot under the glass edge; the tub hangs from the inner face's foot (from the outer one its walls showed through the glass above the sill)
		var shortest := INF
		for li in boxes.size():
			if uvx[loops[li][0]] < 0.5:
				continue   # the glazing's own edge (the frame starts on a copy of it): not a cut edge
			if float(boxes[li]["len"]) < shortest:
				shortest = boxes[li]["len"]
				main_i = li
	if spec.has("main") and not boxes.is_empty():
		var mb: Dictionary = boxes[main_i]
		var mc: Vector3 = mb["c"]
		mb["c"] = Vector3(mc.x, mc.y, float(spec["main"][0]))
		mb["hw"] = float(spec["main"][1])
	for li in loops.size():
		var b: Dictionary = boxes[li]
		if (liner or spec.get("frame_uv", false)) and li != main_i:
			continue   # one glazed shell (a liner, or a fitted canopy with its sill): bows across its main loop only
		for f: float in spec["bows"]:
			bows.append(float(b["front"]) - f * float(b["len"]))
		if li == main_i:
			for f: float in spec["ribs"]:
				ribs.append(f * float(b["hw"]))
		if own or liner:
			continue
		_tub(tub, pos, loops[li], b)
		if li == main_i:
			_furnish(st, pos, loops[li], b, spec["seats"])
	var tub_mesh: ArrayMesh = null
	if liner and spec.has("cabin"):
		_cabin(tub, model, pos, spec["cabin"])
		tub.generate_normals()
		tub_mesh = tub.commit()
	elif liner:
		_liner(tub, pos, nrm, tris, loops)
		tub.generate_normals()
		tub_mesh = tub.commit()
	elif not own:
		tub.generate_normals()
		tub_mesh = tub.commit()
	elif spec.has("pit"):
		var pit: Array = spec["pit"]
		var hw := float(pit[3])
		var pb := {"front": float(pit[0]), "len": float(pit[1]), "c": Vector3(float(pit[0]) - float(pit[1]) * 0.5, 0.0, 0.0),
			"hw": hw, "sill": float(pit[2]) + TUB_DEPTH * hw * 0.8, "low": float(pit[2]) + TUB_DEPTH * hw}
		_furnish(st, pos, PackedInt32Array(), pb, spec["seats"])
	var interior: ArrayMesh = null
	if (not own and not liner) or spec.has("pit"):
		st.generate_normals()
		interior = st.commit()
	return {"glass": _glass_mesh(pos, nrm, tris, rim, spec.has("cabin")), "bows": bows, "ribs": ribs, "tub": tub_mesh,
		"interior": interior, "own_pit": own, "liner": liner, "frame_uv": spec.get("frame_uv", false)}


## Boundary loops of a triangle list (edges used by one triangle), each as an ordered list of vertex indices
static func _loops(tris: PackedInt32Array) -> Array[PackedInt32Array]:
	var count := {}
	for t in range(0, tris.size(), 3):
		for e in 3:
			var a := tris[t + e]
			var b := tris[t + (e + 1) % 3]
			var k := Vector2i(mini(a, b), maxi(a, b))
			count[k] = int(count.get(k, 0)) + 1
	var nb := {}
	for k: Vector2i in count:
		if int(count[k]) == 1:
			(nb.get_or_add(k.x, []) as Array).append(k.y)
			(nb.get_or_add(k.y, []) as Array).append(k.x)
	var seen := {}
	var out: Array[PackedInt32Array] = []
	for s: int in nb:
		if seen.has(s):
			continue
		var loop := PackedInt32Array([s])
		seen[s] = true
		var prev := -1
		var cur := s
		while true:
			var nxt := -1
			for v: int in nb[cur]:
				if v != prev and not seen.has(v):
					nxt = v
					break
			if nxt < 0:
				break
			loop.append(nxt)
			seen[nxt] = true
			prev = cur
			cur = nxt
		if loop.size() >= 6:
			out.append(loop)
	return out


## Distance of every glass vertex to the nearest cut edge (straight line, model units): the canopy sill frame
## is drawn where it is small
static func _rim_distance(pos: PackedVector3Array, loops: Array[PackedInt32Array]) -> PackedFloat32Array:
	var segs := PackedVector3Array()
	for loop in loops:
		for i in loop.size():
			segs.append(pos[loop[i]])
			segs.append(pos[loop[(i + 1) % loop.size()]])
	var out := PackedFloat32Array()
	out.resize(pos.size())
	for vi in pos.size():
		var p := pos[vi]
		var best := INF
		for si in range(0, segs.size(), 2):
			var q := Geometry3D.get_closest_point_to_segment(p, segs[si], segs[si + 1])
			best = minf(best, p.distance_squared_to(q))
		out[vi] = sqrt(best)
	return out


## Footprint of one glass loop: front (largest x), length along x, centre, half-width, sill height (mean y of the
## loop) and the lowest loop point
static func _loop_box(pos: PackedVector3Array, loop: PackedInt32Array) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var sum := Vector3.ZERO
	for i in loop:
		var p := pos[i]
		lo = lo.min(p)
		hi = hi.max(p)
		sum += p
	var c := sum / float(loop.size())
	return {"front": hi.x, "len": hi.x - lo.x, "c": c, "hw": maxf(hi.z - c.z, c.z - lo.z), "sill": c.y, "low": lo.y}


## Hangar glass mesh: the welded glass triangles, wound outwards (away from the loop centre below them), with the
## rim distance in UV2.x for the frame; `both` adds every triangle again wound inwards with the normal turned, so a
## see-through cabin (FRAMES «cabin») shows its far panes from inside
static func _glass_mesh(pos: PackedVector3Array, nrm: PackedVector3Array, tris: PackedInt32Array,
		rim: PackedFloat32Array, both := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		var avg := nrm[a] + nrm[b] + nrm[c]
		var order := PackedInt32Array([a, b, c]) if fn.dot(avg) <= 0.0 else PackedInt32Array([a, c, b])
		for v in order:
			st.set_normal(nrm[v])
			st.set_uv2(Vector2(rim[v], 0.0))
			st.add_vertex(pos[v])
		if both:
			for i in [0, 2, 1]:
				st.set_normal(-nrm[order[i]])
				st.set_uv2(Vector2(rim[order[i]], 0.0))
				st.add_vertex(pos[order[i]])
	return st.commit()


## Smooth glass normals pointing out of the fuselage: away from a point on the model axis (y = z = 0) a little behind
## each triangle, so the nose tip faces forward and a dome on the spine faces up. The generated glazing of «Кит» 1
## and 5 comes with vertex normals that point in and out at random, and the hangar glass turns a pane whose normal
## faces away from the camera into an opaque mirror (fresnel at grazing): such panes read as painted over, the
## others as holes
static func _outward_normals(pos: PackedVector3Array, tris: PackedInt32Array) -> PackedVector3Array:
	var acc := PackedVector3Array()
	acc.resize(pos.size())
	for t in range(0, tris.size(), 3):
		var a := pos[tris[t]]
		var b := pos[tris[t + 1]]
		var c := pos[tris[t + 2]]
		var fn := (b - a).cross(c - a)
		var ct := (a + b + c) / 3.0
		if fn.dot(ct - Vector3(ct.x - 0.05, 0.0, 0.0)) < 0.0:
			fn = -fn
		for k in 3:
			acc[tris[t + k]] += fn
	for i in acc.size():
		acc[i] = acc[i].normalized() if acc[i].length_squared() > 0.0 else Vector3.UP
	return acc


## Liner under a glazed nose: the glass triangles moved LINER_D inwards along their normals, facing out (seen through
## the glass), in the dark cabin paint, and from every cut edge (`loops`) a two-sided fan to the centre of the glass,
## so a look through any gap between a pane and the skin ends on the dark cabin, not on the sky behind the plane
static func _liner(st: SurfaceTool, pos: PackedVector3Array, nrm: PackedVector3Array, tris: PackedInt32Array,
		loops: Array) -> void:
	var col := C_TUB.darkened(0.45)
	var mid := Vector3.ZERO
	for p in pos:
		mid += p
	mid /= maxf(1.0, float(pos.size()))
	for lp: PackedInt32Array in loops:
		for i in lp.size():
			var a := lp[i]
			var b := lp[(i + 1) % lp.size()]
			var pa := pos[a] - nrm[a] * LINER_D
			var pb := pos[b] - nrm[b] * LINER_D
			_tri(st, pa, pb, mid, col, col, col)
			_tri(st, pb, pa, mid, col, col, col)
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var pa := pos[a] - nrm[a] * LINER_D
		var pb := pos[b] - nrm[b] * LINER_D
		var pc := pos[c] - nrm[c] * LINER_D
		if (pb - pa).cross(pc - pa).dot(nrm[a] + nrm[b] + nrm[c]) > 0.0:
			_tri(st, pa, pb, pc, col, col, col)
		else:
			_tri(st, pa, pc, pb, col, col, col)


## See-through cabin of a glazed nose (FRAMES «cabin» = [x0, floor, sight x, seat x]): an inner face in cockpit paint
## for every hull skin triangle ahead of x0 (offset CABIN_SKIN inwards, wound to face the inside), a bulkhead across
## the hull at x0 (the convex outline of the skin there), a floor across the hull at the given fraction of the glass
## height (its half-width at each station read off the skin and glass there), a bombsight on the floor and a seat
static func _cabin(st: SurfaceTool, model: Node3D, glass: PackedVector3Array, cabin: Array) -> void:
	var x0 := float(cabin[0])
	var wall := C_TUB.darkened(0.15)
	var pts := PackedVector3Array()   # skin and glass ahead of x0: the hull's inside surface
	for p in glass:
		if p.x > x0:
			pts.append(p)
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or _under_cockpit(mi, model):
			continue
		var xf := _rel(mi, model)
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m == null or not String(m.resource_name).ends_with("_body"):
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ids.is_empty():
				ids.resize(vs.size())
				for i in vs.size():
					ids[i] = i
			for t in range(0, ids.size(), 3):
				var a := xf * vs[ids[t]]
				var b := xf * vs[ids[t + 1]]
				var d := xf * vs[ids[t + 2]]
				if a.x < x0 - 0.004 or b.x < x0 - 0.004 or d.x < x0 - 0.004:
					continue
				var n := (xf.basis * (ns[ids[t]] + ns[ids[t + 1]] + ns[ids[t + 2]])).normalized()
				var off := -n * CABIN_SKIN
				pts.append(a)
				pts.append(b)
				pts.append(d)
				_tri(st, a + off, d + off, b + off, wall, wall, wall)   # wound against the skin: faces the inside
	if pts.is_empty():
		return
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in glass:
		if p.x > x0:
			lo = lo.min(p)
			hi = hi.max(p)
	# bulkhead: the convex outline (y, z) of the hull points within 4 mm of x0
	var ring := PackedVector2Array()
	for p in pts:
		if absf(p.x - x0) < 0.004:
			ring.append(Vector2(p.z, p.y))
	var hull := Geometry2D.convex_hull(ring)
	if hull.size() >= 3:
		var mid := Vector2.ZERO
		for q in hull:
			mid += q
		mid /= float(hull.size())
		var bc := C_TUB.darkened(0.35)
		for i in hull.size() - 1:
			var qa := mid + (hull[i] - mid) * 0.97
			var qb := mid + (hull[i + 1] - mid) * 0.97
			_tri(st, Vector3(x0, mid.y, mid.x), Vector3(x0, qa.y, qa.x), Vector3(x0, qb.y, qb.x), bc, bc, bc)
	# floor: half-width at each 4 mm station from the hull points within 8 mm of its height
	var fy := lo.y + (hi.y - lo.y) * float(cabin[1])
	var fc := C_TUB.darkened(0.3)
	var prev := Vector2.INF
	var x := x0
	while x < hi.x:
		var zl := INF
		var zr := -INF
		for p in pts:
			if absf(p.x - x) < 0.003 and absf(p.y - fy) < 0.008:
				zl = minf(zl, p.z)
				zr = maxf(zr, p.z)
		if zl < zr:
			var cur := Vector2(zl + 0.002, zr - 0.002)
			if prev != Vector2.INF:
				var px := x - CABIN_STEP
				_tri(st, Vector3(px, fy, prev.x), Vector3(px, fy, prev.y), Vector3(x, fy, cur.y), fc, fc, fc)
				_tri(st, Vector3(px, fy, prev.x), Vector3(x, fy, cur.y), Vector3(x, fy, cur.x), fc, fc, fc)
			prev = cur
		x += CABIN_STEP
	_bombardier(st, pts, lo, hi, fy, float(cabin[2]), float(cabin[3]))
	if cabin.size() > 4:
		_dome_turret(st, glass, float(cabin[4]), float(cabin[5]), float(cabin[6]))


## A gunner's turret in the glass dome over the cabin (Kanta 19.11: «над кабиной у тебя стеклянный колпак, давай
## сделаем из него турель»): the dome is the glass between x0 and x1 above the cabin; inside it a turret ring on
## its base, the gunner (helmet, goggles, shoulders) facing aft, and twin guns on a cradle, their barrels out through
## the glass towards the tail and a little up, as a dorsal turret covers the rear hemisphere. The dome is the glass
## between x0 and x1 above y0 (the side windows below it are glass too)
static func _dome_turret(st: SurfaceTool, glass: PackedVector3Array, x0: float, x1: float, y0: float) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in glass:
		if p.x >= x0 and p.x <= x1 and p.y > y0:
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x == INF:
		return
	var c := (lo + hi) * 0.5
	var r := maxf(hi.x - lo.x, hi.z - lo.z) * 0.5
	var h := hi.y - lo.y
	var base := Vector3(c.x, lo.y, c.z)
	_box(st, base + Vector3(0.0, h * 0.06, 0.0), Vector3(r * 1.7, h * 0.12, r * 1.7), Basis.IDENTITY, C_PANEL)
	# the gunner, looking aft over the guns
	var head := base + Vector3(r * 0.25, h * 0.5, 0.0)
	_box(st, head - Vector3(0.0, h * 0.32, 0.0), Vector3(r * 0.5, h * 0.3, r * 0.9), Basis.IDENTITY, C_JACKET)
	_box(st, head, Vector3(r * 0.5, h * 0.36, r * 0.46), Basis.IDENTITY, C_HELMET)
	_box(st, head + Vector3(-r * 0.24, -h * 0.02, 0.0), Vector3(r * 0.06, h * 0.18, r * 0.36), Basis.IDENTITY, C_FACE)
	_box(st, head + Vector3(-r * 0.26, h * 0.06, 0.0), Vector3(r * 0.05, h * 0.08, r * 0.44), Basis.IDENTITY, C_GOGGLES)
	# the guns: cradle, two receivers and barrels running aft through the glass
	var pivot := base + Vector3(-r * 0.2, h * 0.42, 0.0)
	_box(st, pivot, Vector3(r * 0.5, h * 0.16, r * 0.7), Basis.IDENTITY, C_GUN)
	for side in [-1.0, 1.0]:
		var zo: float = side * r * 0.24
		var recv := pivot + Vector3(-r * 0.1, h * 0.08, zo)
		_box(st, recv, Vector3(r * 0.6, h * 0.16, r * 0.14), Basis.IDENTITY, C_GUN)
		_beam(st, recv, recv + Vector3(-r * 3.2, h * 0.35, 0.0), r * 0.08, C_GUN)


## The bombardier's station in a glazed nose, sized from the glazing's height so it reads through the glass (Kanta
## 18.11: «проработай внутреннее убранство, сейчас не пойму что там»): a seat with the navigator on it, leaning to a
## bombsight column on the floor, hands on its head; a flexible gun in a ball mount at the nose tip, with its drum and
## grips; an instrument panel with gauges on the left wall, an oxygen bottle and a map case on the bulkhead side
## (a red bomb-release box on the right wall stuck out through a side window, Kanta 19.11: «что торчит из окна?»). `pts` is the hull's inside surface (for the wall positions), `fy` the floor height
static func _bombardier(st: SurfaceTool, pts: PackedVector3Array, lo: Vector3, hi: Vector3, fy: float, sx: float,
		tx: float) -> void:
	var h := hi.y - lo.y
	var u := h * 0.4   # the navigator's seated height
	# seat: pan, back and post
	var pan_y := fy + u * 0.3
	_box(st, Vector3(tx, pan_y - u * 0.04, 0.0), Vector3(u * 0.36, u * 0.08, u * 0.42), Basis.IDENTITY, C_CUSHION)
	_box(st, Vector3(tx - u * 0.2, pan_y + u * 0.2, 0.0), Vector3(u * 0.06, u * 0.5, u * 0.42), Basis.IDENTITY, C_SEAT)
	_beam(st, Vector3(tx, fy, 0.0), Vector3(tx, pan_y - u * 0.08, 0.0), u * 0.1, C_SEAT)
	# the bombsight: a base, a column and the optic head with its eyepiece towards the navigator
	var head_y := pan_y + u * 0.62
	var sight_top := pan_y + u * 0.4
	_box(st, Vector3(sx, fy + u * 0.02, 0.0), Vector3(u * 0.3, u * 0.04, u * 0.3), Basis.IDENTITY, C_PANEL)
	_beam(st, Vector3(sx, fy, 0.0), Vector3(sx, sight_top, 0.0), u * 0.1, C_PANEL.lightened(0.1))
	_box(st, Vector3(sx, sight_top + u * 0.06, 0.0), Vector3(u * 0.22, u * 0.14, u * 0.14), Basis.IDENTITY, C_GAUGE)
	_beam(st, Vector3(sx - u * 0.1, sight_top + u * 0.08, 0.0), Vector3(sx - u * 0.2, sight_top + u * 0.12, 0.0),
			u * 0.06, C_PANEL)
	for side in [-1.0, 1.0]:   # the sight's two handwheels
		_box(st, Vector3(sx, sight_top + u * 0.04, side * u * 0.1), Vector3(u * 0.1, u * 0.1, u * 0.02),
				Basis.IDENTITY, C_GAUGE.lightened(0.25))
	# the navigator: thighs and shins, the torso leaning to the eyepiece, the head in a leather helmet with goggles,
	# the arms down to the handwheels
	var hip := Vector3(tx + u * 0.02, pan_y + u * 0.06, 0.0)
	var lean := Basis(Vector3(0.0, 0.0, 1.0), -0.55)
	var torso_c := hip + lean * Vector3(0.0, u * 0.26, 0.0)
	_box(st, torso_c, Vector3(u * 0.24, u * 0.52, u * 0.4), lean, C_JACKET)
	var neck := hip + lean * Vector3(0.0, u * 0.54, 0.0)
	var head := neck + Vector3(u * 0.06, u * 0.1, 0.0)
	_box(st, head, Vector3(u * 0.22, u * 0.24, u * 0.2), Basis.IDENTITY, C_HELMET)
	_box(st, head + Vector3(u * 0.1, -u * 0.03, 0.0), Vector3(u * 0.04, u * 0.12, u * 0.16), Basis.IDENTITY, C_FACE)
	_box(st, head + Vector3(u * 0.11, u * 0.04, 0.0), Vector3(u * 0.04, u * 0.05, u * 0.2), Basis.IDENTITY, C_GOGGLES)
	_box(st, neck + lean * Vector3(0.0, -u * 0.02, 0.0), Vector3(u * 0.26, u * 0.06, u * 0.44), lean, C_COLLAR)
	for side in [-1.0, 1.0]:
		var z: float = side * u * 0.11
		var knee := Vector3(tx + u * 0.4, pan_y + u * 0.1, z)
		_beam(st, hip + Vector3(0.0, 0.0, z), knee, u * 0.13, C_JACKET.darkened(0.2))
		_beam(st, knee, Vector3(tx + u * 0.46, fy + u * 0.04, z), u * 0.11, C_JACKET.darkened(0.2))
		_box(st, Vector3(tx + u * 0.5, fy + u * 0.03, z), Vector3(u * 0.16, u * 0.06, u * 0.09), Basis.IDENTITY, C_SEAT)
		var shoulder := neck + lean * Vector3(0.0, -u * 0.06, 0.0) + Vector3(0.0, 0.0, side * u * 0.21)
		var hand := Vector3(sx - u * 0.02, sight_top + u * 0.04, side * u * 0.13)
		var elbow := (shoulder + hand) * 0.5 + Vector3(-u * 0.04, -u * 0.08, side * u * 0.03)
		_beam(st, shoulder, elbow, u * 0.1, C_JACKET)
		_beam(st, elbow, hand, u * 0.09, C_JACKET)
		_box(st, hand, Vector3(u * 0.07, u * 0.07, u * 0.06), Basis.IDENTITY, C_HELMET)
	# the flexible gun in a ball mount at the nose tip: barrel out through the glazing, receiver, drum and grips
	var tip := Vector3(hi.x, 0.0, 0.0)
	var tip_y := -INF
	var tip_lo := INF
	for p in pts:
		if p.x > hi.x - 0.01:
			tip_y = maxf(tip_y, p.y)
			tip_lo = minf(tip_lo, p.y)
	if tip_y > -INF:
		tip.y = (tip_y + tip_lo) * 0.5
	var mount := tip - Vector3(u * 0.12, 0.0, 0.0)
	_box(st, mount, Vector3(u * 0.16, u * 0.2, u * 0.2), Basis.IDENTITY, C_PANEL.lightened(0.15))
	var recv := mount - Vector3(u * 0.36, -u * 0.02, 0.0)
	_beam(st, recv, tip + Vector3(u * 0.3, 0.0, 0.0), u * 0.05, C_GUN)
	_beam(st, mount, tip + Vector3(u * 0.08, 0.0, 0.0), u * 0.1, C_GUN)
	_box(st, recv, Vector3(u * 0.34, u * 0.1, u * 0.09), Basis.IDENTITY, C_GUN)
	_box(st, recv + Vector3(u * 0.02, u * 0.1, 0.0), Vector3(u * 0.22, u * 0.05, u * 0.22), Basis.IDENTITY, C_DRUM)
	_beam(st, recv - Vector3(u * 0.17, 0.0, 0.0), recv - Vector3(u * 0.24, u * 0.12, 0.0), u * 0.05, C_HELMET)
	# the walls: half-width of the hull at a station and height, from the inside surface
	var walls := func(x: float, y: float) -> Vector2:
		var zl := 0.0
		var zr := 0.0
		for p in pts:
			if absf(p.x - x) < 0.004 and absf(p.y - y) < 0.006:
				zl = minf(zl, p.z)
				zr = maxf(zr, p.z)
		return Vector2(zl, zr)
	# instrument panel on the left wall: a board and four gauges facing the navigator's side
	var px := tx + u * 0.15
	var py := pan_y + u * 0.35
	var w: Vector2 = walls.call(px, py)
	if w.x < -u * 0.3:
		var z := w.x + u * 0.16   # well inside the wall: it curves in above and below the panel
		_box(st, Vector3(px, py, z), Vector3(u * 0.5, u * 0.3, u * 0.04), Basis.IDENTITY, C_PANEL)
		for i in 4:
			var g := Vector3(px + (float(i % 2) - 0.5) * u * 0.22, py + (0.06 if i < 2 else -0.07) * u, z + u * 0.03)
			_box(st, g, Vector3(u * 0.09, u * 0.09, u * 0.02), Basis.IDENTITY, C_DIAL)
	# oxygen bottle and map case behind the seat, against the bulkhead
	_beam(st, Vector3(tx - u * 0.42, fy, -u * 0.2), Vector3(tx - u * 0.42, fy + u * 0.5, -u * 0.2), u * 0.14, C_OXYGEN)
	_box(st, Vector3(tx - u * 0.42, fy + u * 0.2, u * 0.2), Vector3(u * 0.1, u * 0.4, u * 0.3), Basis.IDENTITY,
			C_CUSHION.darkened(0.2))


## A square bar of width `w` from `a` to `b`, flat-coloured
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	if d.length() < 1e-6:
		return
	var xa := d.normalized()
	var up := Vector3.UP if absf(xa.y) < 0.9 else Vector3.RIGHT
	var za := xa.cross(up).normalized()
	_box(st, (a + b) * 0.5, Vector3(d.length(), w, w), Basis(xa, za.cross(xa), za), col)


## Tub under one glass loop: a wall from every cut edge down and in towards the loop's middle, and a floor
static func _tub(st: SurfaceTool, pos: PackedVector3Array, loop: PackedInt32Array, b: Dictionary) -> void:
	var c: Vector3 = b["c"]
	var hw: float = b["hw"]
	var floor_y: float = float(b["low"]) - float(b.get("depth", TUB_DEPTH)) * hw
	var bottom := PackedVector3Array()
	for i in loop:
		var p := pos[i]
		var q := Vector3(p.x + (c.x - p.x) * TUB_INSET * 0.4, floor_y, p.z + (c.z - p.z) * TUB_INSET)
		bottom.append(q)
	var dark := C_TUB.darkened(0.3)
	var n := loop.size()
	for i in n:
		var j := (i + 1) % n
		var a := pos[loop[i]]
		var bb := pos[loop[j]]
		_tri(st, a, bb, bottom[j], C_TUB, C_TUB, dark)
		_tri(st, a, bottom[j], bottom[i], C_TUB, dark, dark)
	var fc := Vector3(c.x, floor_y, c.z)
	for i in n:
		_tri(st, fc, bottom[i], bottom[(i + 1) % n], dark, dark, dark)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


## Highest glass point near x (local canopy height above the seat), or the loop's sill when none is near
static func _glass_top(pos: PackedVector3Array, x: float, fallback: float) -> float:
	var top := -INF
	for p in pos:
		if absf(p.x - x) < 0.01:
			top = maxf(top, p.y)
	return top if top > -INF else fallback


## Cut edge of a glass loop near x: x — its half-width there, y — its lowest point there (the sill); the loop's
## own half-width and mean sill when no edge point is that close
static func _loop_at(pos: PackedVector3Array, loop: PackedInt32Array, b: Dictionary, x: float) -> Vector2:
	var c: Vector3 = b["c"]
	var hw := 0.0
	var low := INF
	var reach := maxf(float(b["len"]) * 0.06, 0.004)
	for i in loop:
		var p := pos[i]
		if absf(p.x - x) < reach:
			hw = maxf(hw, absf(p.z - c.z))
			low = minf(low, p.y)
	if low == INF:
		return Vector2(b["hw"], b["sill"])
	return Vector2(hw, low)


## Seats, instrument panel, coaming, gauges, consoles and stick in the main glass loop, sized from it.
## `seats` — FRAMES[...]["seats"]
static func _furnish(st: SurfaceTool, pos: PackedVector3Array, loop: PackedInt32Array, b: Dictionary,
		seats: Array) -> void:
	var c: Vector3 = b["c"]
	var hw: float = b["hw"]
	var front: float = b["front"]
	var length: float = b["len"]
	var sill: float = b["sill"]
	var floor_y: float = float(b["low"]) - float(b.get("depth", TUB_DEPTH)) * hw
	var two := seats.size() > 1
	var sw := hw * (0.62 if two else 1.0)   # seat width
	for s: Array in seats:
		var sx := front - float(s[0]) * length
		var sz := c.z + float(s[1]) * _loop_at(pos, loop, b, sx).x
		# the glass over the seat and over its headrest (further aft, where a canopy is lower): the headrest stays
		# a little under the lower of the two
		var top := minf(_glass_top(pos, sx, sill + hw), _glass_top(pos, sx - sw * 0.7, sill + hw))
		var room := top - floor_y
		var pan_y := floor_y + room * 0.28
		_box(st, Vector3(sx + sw * 0.15, pan_y, sz), Vector3(sw * 0.95, sw * 0.16, sw), Basis.IDENTITY, C_CUSHION)
		_box(st, Vector3(sx + sw * 0.15, (floor_y + pan_y) * 0.5, sz), Vector3(sw * 0.8, pan_y - floor_y, sw * 0.9),
				Basis.IDENTITY, C_SEAT)
		# back, tilted 14° aft, up to under the glass
		var back_h := maxf(floor_y + room * 0.8 - sw * 0.45 - pan_y, room * 0.22)
		var tilt := Basis(Vector3.BACK, 0.24)
		var back_c := Vector3(sx - sw * 0.38, pan_y + back_h * 0.5, sz)
		_box(st, back_c, Vector3(sw * 0.2, back_h, sw * 1.05), tilt, C_SEAT)
		_box(st, back_c + Vector3(sw * 0.12, -back_h * 0.06, 0.0), Vector3(sw * 0.06, back_h * 0.78, sw * 0.82), tilt,
				C_CUSHION)
		var head := back_c + tilt * Vector3(0.0, back_h * 0.5 + sw * 0.18, 0.0)
		_box(st, head, Vector3(sw * 0.24, sw * 0.42, sw * 0.62), tilt, C_SEAT)
		_box(st, head + tilt * Vector3(sw * 0.13, 0.0, 0.0), Vector3(sw * 0.04, sw * 0.32, sw * 0.5), tilt, C_CUSHION)
		# shoulder belts over the cushion
		for side in [-1.0, 1.0]:
			_box(st, back_c + Vector3(sw * 0.17, back_h * 0.05, side * sw * 0.2), Vector3(sw * 0.03, back_h * 0.7, sw * 0.12),
					tilt, C_BELT)
		# stick between the knees
		var stick_x := sx + sw * 0.75
		_box(st, Vector3(stick_x, floor_y + room * 0.3, sz), Vector3(sw * 0.07, room * 0.5, sw * 0.07),
				Basis(Vector3.BACK, -0.2), C_SEAT)
		_box(st, Vector3(stick_x + room * 0.05, floor_y + room * 0.56, sz), Vector3(sw * 0.13, sw * 0.2, sw * 0.12),
				Basis.IDENTITY, C_PANEL)
	# instrument panel across the front of the loop, just under the sill, with a coaming over it and gauges on it
	var px := front - length * (0.17 if not two else 0.2)
	var at := _loop_at(pos, loop, b, px)
	var ptop := at.y - hw * 0.04
	var pw := at.x * 1.75
	var ph := ptop - (floor_y + (sill - floor_y) * 0.35)
	_box(st, Vector3(px, ptop - ph * 0.5, c.z), Vector3(hw * 0.12, ph, pw), Basis(Vector3.BACK, -0.12), C_PANEL)
	_box(st, Vector3(px + hw * 0.08, ptop + hw * 0.04, c.z), Vector3(hw * 0.4, hw * 0.08, pw * 0.92), Basis.IDENTITY,
			C_SEAT)
	var cols := 3 if not two else 5
	for row in 2:
		for col in cols:
			var gz := c.z + (float(col) - float(cols - 1) * 0.5) * pw / float(cols + 0.6)
			var gy := ptop - ph * (0.3 + 0.32 * float(row))
			_disc(st, Vector3(px - hw * 0.075, gy, gz), hw * 0.1, C_GAUGE)
			_disc(st, Vector3(px - hw * 0.08, gy, gz), hw * 0.075, C_PANEL.lightened(0.06))
	# side consoles along the tub walls between the panel and the seats
	var cx0 := px - hw * 0.1
	var cx1 := front - length * float((seats[0] as Array)[0]) + hw * 0.2
	for side in [-1.0, 1.0]:
		_box(st, Vector3((cx0 + cx1) * 0.5, floor_y + (sill - floor_y) * 0.42, c.z + side * hw * 0.82),
				Vector3(maxf(cx0 - cx1, hw * 0.3), (sill - floor_y) * 0.18, hw * 0.3), Basis.IDENTITY, C_PANEL.lightened(0.08))


## A box at `c` of `size`, turned by `b`, flat-coloured
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, b: Basis, col: Color) -> void:
	var h := size * 0.5
	var v: Array[Vector3] = []
	for i in 8:
		v.append(c + b * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for q: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri(st, v[q[0]], v[q[1]], v[q[2]], col, col, col)
		_tri(st, v[q[0]], v[q[2]], v[q[3]], col, col, col)


## A flat disc facing −X (towards the pilot) — a gauge face or its rim
static func _disc(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var n := 14
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		_tri(st, c, c + Vector3(0.0, cos(a0) * r, sin(a0) * r), c + Vector3(0.0, cos(a1) * r, sin(a1) * r), col, col, col)
