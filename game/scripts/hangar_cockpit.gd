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
## panel stand in `pit` = [front x, length, floor y, half-width] of the space under the canopy.
## Read off the canopy shapes: bubble canopies have a windscreen bow only, the attackers a windscreen and a hood
## bow, the bombers a framed glasshouse.
const FRAMES := {
	"fighter_1": {"bows": [], "ribs": [], "seats": [[0.62, 0.0]], "own_pit": true, "pit": [0.25, 0.085, -0.02, 0.019]},
	"fighter_2": {"bows": [0.3], "ribs": [], "seats": [[0.62, 0.0]]},
	"attacker_1": {"bows": [0.3, 0.7], "ribs": [], "seats": [[0.58, 0.0]]},
	"attacker_2": {"bows": [0.26, 0.62], "ribs": [], "seats": [[0.56, 0.0]]},
	"bomber_1": {"bows": [0.22, 0.45, 0.7], "ribs": [0.0], "seats": [[0.6, -0.42], [0.6, 0.42]]},
	"bomber_2": {"bows": [0.24, 0.5, 0.76], "ribs": [0.0], "seats": [[0.6, -0.42], [0.6, 0.42]]},
}
## Frame paint when the livery has no colours of its own (the source paint): a dark worn grey
const FRAME_DEFAULT := Color(0.22, 0.23, 0.22)
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
	if data["own_pit"]:
		gm.set_shader_parameter("rim_w", 0.0)
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
				local[i] = weld[k]
			for i in ids.size():
				tris.append(local[ids[i]])
	if tris.size() < 9:
		return {"glass": null, "tub": null, "interior": null, "own_pit": false}
	var loops := _loops(tris)
	var rim := _rim_distance(pos, loops)
	var spec: Dictionary = FRAMES.get(key, {"bows": [0.3], "ribs": [], "seats": [[0.6, 0.0]]})
	var own: bool = spec.get("own_pit", false)
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
		boxes.append(b)
		if float(b["len"]) > main_len:
			main_len = b["len"]
			main_i = li
	for li in loops.size():
		var b: Dictionary = boxes[li]
		for f: float in spec["bows"]:
			bows.append(float(b["front"]) - f * float(b["len"]))
		if li == main_i:
			for f: float in spec["ribs"]:
				ribs.append(f * float(b["hw"]))
		if own:
			continue
		_tub(tub, pos, loops[li], b)
		if li == main_i:
			_furnish(st, pos, loops[li], b, spec["seats"])
	var tub_mesh: ArrayMesh = null
	if not own:
		tub.generate_normals()
		tub_mesh = tub.commit()
	elif spec.has("pit"):
		var pit: Array = spec["pit"]
		var hw := float(pit[3])
		var pb := {"front": float(pit[0]), "len": float(pit[1]), "c": Vector3(float(pit[0]) - float(pit[1]) * 0.5, 0.0, 0.0),
			"hw": hw, "sill": float(pit[2]) + TUB_DEPTH * hw * 0.8, "low": float(pit[2]) + TUB_DEPTH * hw}
		_furnish(st, pos, PackedInt32Array(), pb, spec["seats"])
	var interior: ArrayMesh = null
	if not own or spec.has("pit"):
		st.generate_normals()
		interior = st.commit()
	return {"glass": _glass_mesh(pos, nrm, tris, rim), "bows": bows, "ribs": ribs, "tub": tub_mesh, "interior": interior,
		"own_pit": own}


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
## rim distance in UV2.x for the frame
static func _glass_mesh(pos: PackedVector3Array, nrm: PackedVector3Array, tris: PackedInt32Array,
		rim: PackedFloat32Array) -> ArrayMesh:
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
	return st.commit()


## Tub under one glass loop: a wall from every cut edge down and in towards the loop's middle, and a floor
static func _tub(st: SurfaceTool, pos: PackedVector3Array, loop: PackedInt32Array, b: Dictionary) -> void:
	var c: Vector3 = b["c"]
	var hw: float = b["hw"]
	var floor_y: float = float(b["low"]) - TUB_DEPTH * hw
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
	var floor_y: float = float(b["low"]) - TUB_DEPTH * hw
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
