extends Node
## Working part of edge_wrecks_test.gd: builds the world terrain like the game, plans the props of a block of
## chunks, then checks every chunk against its 8 neighbours: (1) BiomeProps.road_wrecks of a chunk lists exactly
## the road-column wrecks its plan() places (the other vehicle wrecks are its battle-scene items), and (2) no
## plant of a chunk reaches over any vehicle wreck its neighbours placed. Prints the neighbour query's cost.

## Blocks of chunks to plan, as Rect2i in chunk keys; the outer ring of a block is only a neighbour. The first is
## the area around the start; the second holds chunk (-30, -1), whose orchard tree stood on a tank of chunk
## (-30, 0) until _clear_wrecks asked the neighbours for their road columns (found by a 6400-chunk scan)
const BLOCKS := [Rect2i(-7, -7, 14, 14), Rect2i(-32, -3, 5, 5)]
const EPS := 0.01      # px: the query and the placed wreck must agree to rounding

var _t: Terrain3D
var _plans := {}       # chunk key → plan() result
var _ctxs := {}        # chunk key → ctx snapshot


func _ready() -> void:
	var bg: Background = load("res://scripts/background.gd").new()
	add_child(bg)
	await get_tree().process_frame
	_t = load("res://scripts/terrain3d.gd").new()
	add_child(_t)
	_t.setup(500.0, StandardMaterial3D.new(), bg)
	bg.place_filter = _t.fix_object
	_t.props = BiomeProps.new(_t)
	var keys: Array[Vector2i] = []
	for b: Rect2i in BLOCKS:
		for cx in range(b.position.x, b.end.x):
			for cy in range(b.position.y, b.end.y):
				keys.append(Vector2i(cx, cy))
	var plan_us := 0
	for k in keys:
		_ctxs[k] = _t._ctx(k)
		var t0 := Time.get_ticks_usec()
		_plans[k] = _t.props.plan(k, _ctxs[k])
		plan_us += Time.get_ticks_usec() - t0
	var failed := 0
	var road_n := 0
	for k in keys:
		failed += _check_query(k)
		road_n += _t.props.road_wrecks(k).size()
	var near := 0   # neighbour wrecks that reach within a tree crown of the chunk: the cases the test is about
	var inner := 0
	for k in keys:
		if not _all_planned(k):
			continue   # the outer ring of a block has unplanned neighbours
		inner += 1
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var nk := Vector2i(k.x + dx, k.y + dz)   # the chunk itself too: its own wrecks stay clear
				for wk: Array in _wrecks(_plans[nk]):
					if nk != k and _rect_dist(k, wk[0]) < float(wk[1]) + 30.0:
						near += 1
					failed += _check_plants(k, nk, wk)
	# cost of the neighbour query plan() makes: road_wrecks of the 8 neighbours, per chunk
	var t1 := Time.get_ticks_usec()
	for k in keys:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx != 0 or dz != 0:
					_t.props.road_wrecks(Vector2i(k.x + dx, k.y + dz))
	var q_us := float(Time.get_ticks_usec() - t1) / keys.size()
	print("UNIT: edge wrecks — %d chunks, %d road wrecks, %d neighbour wrecks at an edge of %d inner chunks" % [
		keys.size(), road_n, near, inner])
	print("UNIT: edge wrecks — neighbour query %.0f us per chunk (plan() %.0f us per chunk)" % [
		q_us, float(plan_us) / keys.size()])
	if road_n == 0 or near == 0:
		failed += 1
		print("FAIL: edge wrecks — no road wrecks near a chunk edge, the test checks nothing")
	print("UNIT: edge wrecks — %d failed" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## (1) Every road_wrecks item of chunk k is a vehicle wreck its plan placed (same kind, place and length), and
## every other placed vehicle wreck is one of the chunk's battle-scene items. Returns the number of failures.
func _check_query(k: Vector2i) -> int:
	var put: Dictionary = _plans[k]
	var road := _t.props.road_wrecks(k)
	var used := {}
	var failed := 0
	for it: Dictionary in road:
		var found := false
		for t: Transform3D in put.get(it["k"], []):
			var p := Vector2(t.origin.x, t.origin.z)
			if p.distance_to(it["p"]) < EPS and absf(t.basis.x.length() - float(it["w"])) < EPS:
				found = true
				used[p] = true
				break
		if not found:
			failed += 1
			print("FAIL: chunk %s: road wreck %s %s (w %.1f) is not in its plan" % [k, it["k"], it["p"], it["w"]])
	var scn: Array = (_ctxs[k]["scenes"] as Dictionary).get(k, [])
	for kind: String in BiomeProps.VEHICLE_KINDS:
		for t: Transform3D in put.get(kind, []):
			var p := Vector2(t.origin.x, t.origin.z)
			if used.has(p):
				continue
			var scene := false
			for it: Dictionary in scn:
				if it["k"] == kind and (it["p"] as Vector2).distance_to(p) < EPS:
					scene = true
			if not scene:
				failed += 1
				print("FAIL: chunk %s: placed %s at %s is neither a road_wrecks item nor a scene item" % [k, kind, p])
	return failed


## (2) No plant of chunk k reaches over the wreck wk ([centre, half-length]) of its neighbour nk: crown radius
## plus half-length must be at most the distance. Returns the number of failures.
func _check_plants(k: Vector2i, nk: Vector2i, wk: Array) -> int:
	var failed := 0
	var put: Dictionary = _plans[k]
	for kind: String in BiomeProps.PLANT_KINDS:
		for t: Transform3D in put.get(kind, []):
			var q := Vector2(t.origin.x, t.origin.z)
			var d := q.distance_to(wk[0])
			if d < float(wk[1]) + t.basis.x.length() * 0.5:
				failed += 1
				print("FAIL: chunk %s: %s at %s stands on a wreck of chunk %s at %s (%.0f px apart)" % [
					k, kind, q, nk, wk[0], d])
	return failed


## Vehicle and plane wrecks of a plan as [centre, half-length]
func _wrecks(put: Dictionary) -> Array:
	var out := []
	for kind: String in put:
		if kind in BiomeProps.VEHICLE_KINDS or kind in BiomeProps.PLANE_KINDS:
			for t: Transform3D in put[kind]:
				out.append([Vector2(t.origin.x, t.origin.z), t.basis.x.length() * 0.5])
	return out


## True when chunk k and all its 8 neighbours were planned
func _all_planned(k: Vector2i) -> bool:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if not _plans.has(Vector2i(k.x + dx, k.y + dz)):
				return false
	return true


## Distance in px from p to the rectangle of chunk k (0 inside)
func _rect_dist(k: Vector2i, p: Vector2) -> float:
	var r := Rect2(Vector2(k) * Terrain3D.CHUNK, Vector2.ONE * Terrain3D.CHUNK)
	var c := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return c.distance_to(p)
