class_name OasisBuild
extends AdobeBuild
## The Highland oasis (o_oasis) as a farmstead of the kishlak's building tradition (weak-models list item 3,
## Kanta 28.10.2026), so the biome reads as one place: houses with shaded ayvans and grapevines, a covered
## cistern and a vine pergola in the courtyard (models from tools/blender/oasis_adobe.py, drawn by
## VillageHouses), a walled pond (hauz) with steps, garden walls of real thickness with eroded coping, gates and
## collapsed stretches, and irrigation channels along the garden walls fed from the pond.
## Render3D asks AdobeBuild.oasis(variant) for the mesh and calls attach() for the models. The layout is the old
## generator's, drawn in the old order (plan()), so the houses, gardens and pond stand where they stood and the
## palms and bushes BiomeProps grows from AdobeBuild.ground_mask keep their places; the new detail has
## generators of its own. The mesh is built in the village's old units with AdobeBuild's wall, gate, ruin and heap
## functions (one look for both settlements) and then mapped onto the oasis's 1 × 1 plot (K, GROUND).
## Purely visual: the oasis has no colliders, targets or spawns.

const PLOT_PX := 420.0                 ## o_oasis nominal size in world px (Background.OBJECTS): one plot unit
const K := 640.0 / PLOT_PX             ## plot units per village old unit (V_UNIT × the village's 1650 px = 640 px)
const GROUND := 0.0101                 ## ground level on the plot: Render3D sinks the oasis mesh by 1 % of its size
const CORE := Vector2(0.06, -0.05)     ## the courtyard's centre (BiomeProps stands the well on it), plot units
const POND := Vector2(-0.04, 0.01)     ## the pond's centre, plot units (CORE + (-0.1, 0.06))
const POND_HALF := Vector2(0.05, 0.0375)   ## half the water surface, plot units
## Old units per model metre for the farmstead models: the houses fit the old box lots (3–4.5 m of the
## kishlak's scale), so the whole farmstead is about half the kishlak's scale, as the palms around it
const MODEL_M := 0.0054
const WELL_R := 0.016                 ## the courtyard well (BiomeProps "well" on CORE), its reach on the plot
const YARD_MASK := 0.6               ## courtyard pieces stand where ground_mask x is at least this: no palm (x ≤ 0.5)
const GARDEN_T := 0.0058               ## garden wall base thickness, old units (~3.7 px)
const CHANNEL_W := 0.0042              ## irrigation channel width, old units (~2.7 px)
const HOUSE_PUSH := 0.04               ## how far a house lot may move out of an overlap, plot units

static var _built := {}                ## variant → [mesh, homes]


## The old layout of variant, drawn exactly as the box oasis drew it: {"houses": [{c, s, h, intact}],
## "gardens": [{c, s, h, gate, broken}], "next": the generator's next draw}. c — centre and s — size on the
## plot, h — the old box top (plot units, the 1 % sink included); gate — the passage side (0 −z, 1 +x, 2 +z,
## 3 −x); broken — per side, whether the old wall stopped halfway. Pure: safe on any thread.
static func plan(variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4241 * (variant + 3)
	var houses: Array[Dictionary] = []
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var c := CORE + Vector2.from_angle(a) * rng.randf_range(0.06, 0.11)
		if c.distance_to(POND) < 0.085:
			continue
		var s := Vector2(rng.randf_range(0.05, 0.075), rng.randf_range(0.045, 0.065))
		var intact := rng.randf() < 0.75
		var h := rng.randf_range(0.04, 0.06)
		if intact:
			if rng.randf() < 0.4:   # the old soot patch: two draws for its place
				rng.randf_range(-0.3, 0.3)
				rng.randf_range(-0.3, 0.3)
		else:
			_skip_ruin_draws(rng)
		houses.append({"c": c, "s": s, "h": h, "intact": intact})
	var gardens: Array[Dictionary] = []
	for i in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.17, 0.28) * outline(variant, a)
		var gc := Vector2.from_angle(a) * r
		var gs := Vector2(rng.randf_range(0.08, 0.13), rng.randf_range(0.07, 0.11))
		var gh := rng.randf_range(0.01, 0.016)
		var gate := rng.randi() % 4
		var broken: Array[bool] = []
		for k in 4:
			broken.append(k != gate and rng.randf() < 0.2)
		gardens.append({"c": gc, "s": gs, "h": gh, "gate": gate, "broken": broken})
	return {"houses": houses, "gardens": gardens, "next": rng.randi()}


## Mesh of variant on the 1 × 1 plot (walls, pond, channels, ruins; adobe.gdshader), cached. Main thread only.
static func mesh(variant: int) -> ArrayMesh:
	return _built_of(variant)[0]


## Model records of variant for VillageHouses.attach (houses, cistern, pergola), old units
static func homes(variant: int) -> Array:
	return _built_of(variant)[1]


## Add the farmstead models of variant under the oasis's MeshInstance3D (scaled to the plot like the mesh).
## Main thread only (loads the models). Returns the triangles added.
static func attach(parent: Node3D, variant: int) -> int:
	return VillageHouses.attach(parent, homes(variant), K, GROUND / K)


## Model studio (tools/model_lab/studio.gd): one oasis piece for close-up review, [mesh on a plot, homes].
## kind: "garden" (a walled garden, its gate on −z, a fallen stretch on +z, channels outside), "pond" (the walled
## pond with the cistern and the pergola beside it), "ruin" (a roofless farmhouse), "v<n>" (the whole variant n).
static func studio_piece(kind: String) -> Array:
	if kind.begins_with("v"):
		return [mesh(int(kind.substr(1))), homes(int(kind.substr(1)))]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hm := []
	var dr := RandomNumberGenerator.new()
	dr.seed = 77
	match kind:
		"garden":
			var g := {"c": Vector2.ZERO, "s": Vector2(0.12, 0.095), "h": 0.014, "gate": 0,
				"broken": [false, false, true, false] as Array[bool]}
			_garden(st, g, [], dr)
			_channels(st, g, Vector2(-0.25, -0.25), [], dr)
		"pond":
			_pond(st, Vector2.ZERO, Vector2(0.0, -1.0), dr)
			hm.append([VillageHouses.CISTERN, Vector2(0.098, -0.008) / K, 0.4, Vector3.ONE * MODEL_M])
			hm.append([VillageHouses.PERGOLA, Vector2(-0.01, -0.07) / K, 0.1, Vector3.ONE * MODEL_M])
		_:
			_t_ruin(st, Vector2.ZERO, Vector2(0.032, 0.026) / K, 0.0, 0.03 / K, dr)
	return [_to_plot(st), hm]


static func _built_of(variant: int) -> Array:
	if not _built.has(variant):
		_built[variant] = _build(variant)
	return _built[variant]


## The old ruin's draws (four broken walls, then the rubble), so the gardens after it keep their places
static func _skip_ruin_draws(rng: RandomNumberGenerator) -> void:
	for side in 4:
		for k in rng.randi_range(3, 5):
			if rng.randf() < 0.15:
				continue
			rng.randf_range(0.35, 1.0)
	rng.randf_range(-0.2, 0.2)
	rng.randf_range(-0.2, 0.2)
	for k in 3:
		rng.randf()
		rng.randf()
		rng.randf_range(0.01, 0.028)
		rng.randf_range(0.01, 0.028)
		rng.randf()
		rng.randf_range(0.3, 1.0)


## Builds [mesh, homes] of variant: houses on the old lots, the pond, the courtyard pieces, the gardens and
## their channels. The old boxes could overlap: a house lot mostly inside an earlier one (the old boxes merged
## into one block there) is left out, a lot that only grazes a neighbour or the pond moves out of the overlap
## until clear (at most HOUSE_PUSH, else it is left out too). Garden walls and channels stop at house lots, the
## pond, the courtyard pieces and earlier gardens, so overlapping gardens join into one walled plot
static func _build(variant: int) -> Array:
	var p := plan(variant)
	var dr := RandomNumberGenerator.new()
	dr.seed = 9137 * (variant + 3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hm := []
	var taken: Array = [[POND, POND_HALF + Vector2(0.008, 0.008)]]   # [centre, half size] on the plot
	var last := -1
	for h: Dictionary in p["houses"]:
		var half: Vector2 = h["s"] * 0.5
		var c: Vector2 = h["c"]
		if _covered(c, half, taken) > 0.35:
			continue
		var moved := 0.0
		while _hits(c, half, taken, 0.004) and moved < HOUSE_PUSH:
			c += _away(c, half, taken) * 0.004
			moved += 0.004
		if _hits(c, half, taken, 0.0):
			continue
		taken.append([c, half])
		var vis: float = h["h"] - GROUND
		if h["intact"]:
			last = _farmhouse(hm, c, h["s"], vis, last, dr)
		else:
			_t_ruin(st, c / K, half / K, 0.0, vis * 0.8 / K, dr)
	_pond(st, POND / K, (CORE - POND).normalized(), dr)
	for piece: int in [VillageHouses.CISTERN, VillageHouses.PERGOLA]:
		_yard_piece(hm, piece, variant, taken, dr)
	var blocks: Array = taken.duplicate()
	for g: Dictionary in p["gardens"]:
		_garden(st, g, blocks, dr)
		_channels(st, g, POND, blocks, dr)
		blocks.append([g["c"], (g["s"] as Vector2) * 0.5])
	return [_to_plot(st), hm]


## Direction moving rectangle (c, half) out of the rects it overlaps: away from their centres along the axis of
## least overlap, and a little away from the courtyard so a lot never drifts into its middle
static func _away(c: Vector2, half: Vector2, rects: Array) -> Vector2:
	var push := (c - CORE).normalized() * 0.3
	for r: Array in rects:
		var d: Vector2 = c - (r[0] as Vector2)
		var hh: Vector2 = half + (r[1] as Vector2) + Vector2(0.004, 0.004)
		var over := hh - d.abs()
		if over.x <= 0.0 or over.y <= 0.0:
			continue
		push += Vector2(signf(d.x), 0.0) if over.x < over.y else Vector2(0.0, signf(d.y))
	return push.normalized()


## Share of rectangle (c, half) inside the largest overlap with any of rects (0…1)
static func _covered(c: Vector2, half: Vector2, rects: Array) -> float:
	var best := 0.0
	for r: Array in rects:
		var d: Vector2 = (c - (r[0] as Vector2)).abs()
		var hh: Vector2 = half + (r[1] as Vector2)
		var ov := Vector2(clampf(hh.x - d.x, 0.0, minf(half.x, (r[1] as Vector2).x) * 2.0),
			clampf(hh.y - d.y, 0.0, minf(half.y, (r[1] as Vector2).y) * 2.0))
		best = maxf(best, ov.x * ov.y / (half.x * half.y * 4.0))
	return best


## The parts of segment a–b (plot) outside every rectangle of rects grown by m, as [from, to] pairs; parts
## shorter than min_len are dropped
static func _clip(a: Vector2, b: Vector2, rects: Array, m: float, min_len := 0.004) -> Array:
	var cut: Array = []   # [t0, t1] along a→b inside some rectangle
	var d := b - a
	for r: Array in rects:
		var h: Vector2 = (r[1] as Vector2) + Vector2(m, m)
		var o: Vector2 = a - (r[0] as Vector2)
		var t0 := 0.0
		var t1 := 1.0
		var inside := true
		for i in 2:
			if absf(d[i]) < 1e-9:
				if absf(o[i]) >= h[i]:
					inside = false
				continue
			var ta := (-h[i] - o[i]) / d[i]
			var tb := (h[i] - o[i]) / d[i]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		if inside and t0 < t1:
			cut.append([t0, t1])
	cut.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var out: Array = []
	var t := 0.0
	var len := d.length()
	for c: Array in cut:
		if float(c[0]) > t and (float(c[0]) - t) * len >= min_len:
			out.append([a + d * t, a + d * float(c[0])])
		t = maxf(t, float(c[1]))
	if t < 1.0 and (1.0 - t) * len >= min_len:
		out.append([a + d * t, b])
	return out


## Rectangle (c, half) on the plot comes closer than m to any of rects
static func _hits(c: Vector2, half: Vector2, rects: Array, m: float) -> bool:
	for r: Array in rects:
		var d: Vector2 = (c - (r[0] as Vector2)).abs()
		var hh: Vector2 = half + (r[1] as Vector2) + Vector2(m, m)
		if d.x < hh.x and d.y < hh.y:
			return true
	return false


## A farmhouse model on the lot (c, s on the plot) with its front (ayvan) turned to the courtyard: the model
## whose footprint best fits the lot, a two-storey one for the tallest old boxes, not the same as the last one
## when another fits nearly as well; scaled to the lot (at most 20 % off the model's proportions) and to about
## the old box's height. Returns the variant
static func _farmhouse(hm: Array, c: Vector2, s: Vector2, vis: float, last: int, dr: RandomNumberGenerator) -> int:
	var to := CORE - c
	var yaw := 0.0
	var along := Vector2(s.x, s.y)   # the lot along the model's x and z
	if absf(to.x) > absf(to.y):
		yaw = -PI * 0.5 if to.x > 0.0 else PI * 0.5
		along = Vector2(s.y, s.x)
	elif to.y < 0.0:
		yaw = PI
	var two := vis > 0.044
	var best := VillageHouses.OASIS0
	var bs := INF
	for i in VillageHouses.OASIS_HOUSES:
		var v := VillageHouses.OASIS0 + i
		var ms := VillageHouses.size(v)
		if (ms.y > 5.0) != two:
			continue
		var sc := absf(log((along.x / along.y) / (ms.x / ms.z))) + dr.randf() * 0.25 + (0.3 if v == last else 0.0)
		if sc < bs:
			bs = sc
			best = v
	var ms := VillageHouses.size(best)
	var sx := along.x * 0.97 / K / ms.x
	var sz := along.y * 0.97 / K / ms.z
	var sm := minf(sx, sz)
	sx = minf(sx, sm * 1.2)
	sz = minf(sz, sm * 1.2)
	var sy := clampf(vis / K / ms.y, sm * 0.9, sm * 1.25)
	hm.append([best, c / K, yaw, Vector3(sx, sy, sz)])
	return best


## The cistern or the pergola in the courtyard: the first spot on rings round CORE clear of the well (WELL_R),
## the houses, the pond and the other piece, whose whole reach lies where AdobeBuild.ground_mask keeps palms
## and bushes away (trodden yard, x ≥ YARD_MASK); none when the courtyard is full
static func _yard_piece(hm: Array, piece: int, variant: int, taken: Array, dr: RandomNumberGenerator) -> void:
	var ms := VillageHouses.size(piece) * MODEL_M * K
	var reach := Vector2(ms.x, ms.z).length() * 0.5
	var big := Vector2(reach, reach)   # any turn fits
	var a0 := dr.randf() * TAU
	for i in 4:
		var r := reach + WELL_R + 0.004 + i * 0.006
		for k in 16:
			var c := CORE + Vector2.from_angle(a0 + TAU * k / 16.0) * r
			if _hits(c, big, taken, 0.003) or not _in_yard(variant, c, reach):
				continue
			taken.append([c, big])
			var face := (CORE - c).normalized()
			hm.append([piece, c / K, atan2(-face.x, face.y) + dr.randf_range(-0.15, 0.15), Vector3.ONE * MODEL_M])
			return


## Circle (c, r) on the plot lies in the trodden courtyard where no palm or bush is placed
static func _in_yard(variant: int, c: Vector2, r: float) -> bool:
	for k in 8:
		if ground_mask("o_oasis", variant, c + Vector2.from_angle(TAU * k / 8.0) * r).x < YARD_MASK:
			return false
	return ground_mask("o_oasis", variant, c).x >= YARD_MASK


## The walled pond (hauz) at c (old units): a low mud-brick rim with a rounded coping, a gap with a stone
## landing and steps on the side facing `front` (towards the courtyard), still water just under the rim (its
## damp dark foot is the wall's own) and clay jars by the steps
static func _pond(st: SurfaceTool, c: Vector2, front: Vector2, dr: RandomNumberGenerator) -> void:
	var hw := POND_HALF / K
	var t := 0.0045
	var rh := 0.0032
	var col := T_WALL.darkened(0.06)
	var corners := [Vector2(-hw.x, -hw.y), Vector2(hw.x, -hw.y), Vector2(hw.x, hw.y), Vector2(-hw.x, hw.y)]
	var fs := 0   # the side facing front: 0 −z, 1 +x, 2 +z, 3 −x
	if absf(front.x) > absf(front.y):
		fs = 1 if front.x > 0.0 else 3
	else:
		fs = 2 if front.y > 0.0 else 0
	for i in 4:
		var a: Vector2 = corners[i] * 1.0 + ((corners[i] as Vector2).sign() * t * 0.5)
		var b: Vector2 = corners[(i + 1) % 4] + ((corners[(i + 1) % 4] as Vector2).sign() * t * 0.5)
		if i != fs:
			_t_wall(st, c, 0.0, a, b, t, rh, col, dr)
			continue
		var m := a.lerp(b, 0.5)
		var d := (b - a).normalized()
		var gw := 0.0045
		_t_wall(st, c, 0.0, a, m - d * gw, t, rh, col, dr)
		_t_wall(st, c, 0.0, m + d * gw, b, t, rh, col, dr)
		var o := m.normalized()   # outwards from the pond
		var stone := Color(0.74, 0.71, 0.68)
		for k in 3:   # steps from the landing down into the water
			var q := c + m + o * (0.003 - k * 0.0028)
			_ob(st, q, d.angle(), 0.0, 0.0, Vector3(gw * 2.2, 0.0005, 0.0034), stone.darkened(0.08 * k), stone.darkened(0.06 * k), 0.0016 - k * 0.0005)
		for k in 2:   # water jars by the steps
			var j := c + m + o * 0.008 + d * (gw + 0.004 + k * 0.0032)
			_ob(st, j, dr.randf() * TAU, 0.0, 0.0, Vector3(0.0022, 0.0028, 0.0022), Color(0.62, 0.42, 0.3), Color(0.5, 0.33, 0.24))
	# water: a little under the rim's top, above the ground
	var y := SINK + 0.0014
	var wa := Color(0.4, 0.42, 0.4, ID_WATER)
	_quad(st, Vector3(c.x - hw.x, y, c.y - hw.y), Vector3(c.x + hw.x, y, c.y - hw.y), Vector3(c.x + hw.x, y, c.y + hw.y), Vector3(c.x - hw.x, y, c.y + hw.y), wa)


## A walled garden g (plan record): battered mud walls with a rounded eroded coping, a gate with a timber frame
## and leaves on the old passage side, the old half-walls as a ragged stretch, a heap of fallen clay and a low
## ragged stump. The walls are taller than the old one-line frames: they must read at gameplay height. Walls
## stop at blocks ([centre, half] on the plot: house lots, the pond, courtyard pieces, earlier gardens)
static func _garden(st: SurfaceTool, g: Dictionary, blocks: Array, dr: RandomNumberGenerator) -> void:
	var gc: Vector2 = g["c"]
	var hs: Vector2 = (g["s"] as Vector2) * 0.5
	var c := gc / K
	var wh := (0.016 + (float(g["h"]) - 0.01) * 0.6) / K
	var t := GARDEN_T
	var gw := 0.0052 * K   # half the passage, plot units
	var col := T_WALL.darkened(dr.randf_range(-0.02, 0.06))
	var corners := [Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y)]
	var broken: Array = g["broken"]
	var m := t * K * 0.5 + 0.002
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var dirv := (b - a).normalized()
		var runs := []   # [from, to (local, plot units), height, ragged]
		if i == int(g["gate"]):
			var gm := a.lerp(b, 0.5 + dr.randf_range(-0.12, 0.12))
			runs.append([a, gm - dirv * gw, wh, false])
			runs.append([gm + dirv * gw, b, wh, false])
			if not _hits(gc + gm, Vector2(gw, gw), blocks, 0.002):
				_gate(st, c, 0.0, gm / K, dirv, gw / K, t, wh, 0, dr.randf() < 0.4, col)
		elif broken[i]:
			runs.append([a, a.lerp(b, 0.55), wh, true])
			runs.append([a.lerp(b, 0.7), b, wh * 0.45, true])
			var hp := a.lerp(b, 0.62)
			if not _hits(gc + hp, Vector2(0.01, 0.01), blocks, 0.0):
				_heap(st, c + hp / K, 0.007, dr)
		else:
			runs.append([a, b, wh, false])
		for r: Array in runs:
			for piece: Array in _clip(gc + (r[0] as Vector2), gc + (r[1] as Vector2), blocks, m):
				_t_wall(st, c, 0.0, ((piece[0] as Vector2) - gc) / K, ((piece[1] as Vector2) - gc) / K, t, float(r[2]),
					col, dr, bool(r[3]))


## Irrigation channels of garden g: water along the outside of the wall that faces `src` (the pond), stopping
## at blocks (as _garden), and a feeder from the pond to it when the way crosses no block
static func _channels(st: SurfaceTool, g: Dictionary, src: Vector2, blocks: Array, dr: RandomNumberGenerator) -> void:
	var gc: Vector2 = g["c"]
	var hs: Vector2 = (g["s"] as Vector2) * 0.5
	var to := src - gc
	var off := (GARDEN_T + CHANNEL_W) * K * 0.75
	var a: Vector2
	var b: Vector2
	if absf(to.x) / hs.x > absf(to.y) / hs.y:
		var x := gc.x + signf(to.x) * (hs.x + off)
		a = Vector2(x, gc.y - hs.y * 0.92)
		b = Vector2(x, gc.y + hs.y * 0.92)
	else:
		var z := gc.y + signf(to.y) * (hs.y + off)
		a = Vector2(gc.x - hs.x * 0.92, z)
		b = Vector2(gc.x + hs.x * 0.92, z)
	var y := SINK + 0.0007
	var col := Color(0.62, 0.6, 0.6)
	var pieces := _clip(a, b, blocks, 0.003, 0.012)
	for piece: Array in pieces:
		_strip(st, (piece[0] as Vector2) / K, (piece[1] as Vector2) / K, CHANNEL_W, col, y, ID_WATER)
	if pieces.size() != 1:
		return
	var head := a if a.distance_to(src) < b.distance_to(src) else b
	var from := src + (head - src).normalized() * (POND_HALF.length() * 0.85)
	if from.distance_to(head) < 0.02 or from.distance_to(head) > 0.3:
		return
	for l: Array in blocks.slice(1):   # a feeder never runs under a house or through another garden
		if _seg_box(from - (l[0] as Vector2), head - (l[0] as Vector2), (l[1] as Vector2) + Vector2(0.004, 0.004)):
			return
	var mid := from.lerp(head, 0.5) + (head - from).orthogonal().normalized() * dr.randf_range(-0.012, 0.012)
	_strip(st, from / K, mid / K, CHANNEL_W, col, y, ID_WATER)
	_strip(st, mid / K, head / K, CHANNEL_W, col, y, ID_WATER)


## st (old units, ground at SINK) committed onto the plot: x and z × K, the ground moved to GROUND
static func _to_plot(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	var arr := st.commit_to_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in vs.size():
		var v := vs[i]
		vs[i] = Vector3(v.x * K, (v.y - SINK) * K + GROUND, v.z * K)
	arr[Mesh.ARRAY_VERTEX] = vs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
