extends Node
## Working part of convoy_road_test.gd: builds the world terrain like the game (same seed), finds
## mountain points on a grid (a bomber patrol there gets no road: the road search near the point finds
## nothing — the case where columns used to drive a straight line over the ridges), and routes columns
## through them and through random points over 60 × 60 km; checks that lanes stay near the road axis.

const N := 12            # random points
const MOUNTAINS := 3     # mountain points to find
const FLOOR_H := 20.0    # px above the valley floor: the road bed is ~0–4
const NEAR := 5000.0     # a patrol's road point is at most this far: offsets 1 600 + floor search 900 + Newton 2 400 px

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _ready() -> void:
	var bg: Background = load("res://scripts/background.gd").new()
	add_child(bg)
	await get_tree().process_frame
	var t: Terrain3D = load("res://scripts/terrain3d.gd").new()
	add_child(t)
	t.setup(500.0, StandardMaterial3D.new(), bg)
	var mountains: Array[Vector2] = []
	for k in 900:
		var q := Vector2(k % 30 - 15, floori(k / 30.0) - 15) * 1900.0
		if absf(t.river_field(q.x, q.y)) < 1500.0:
			continue
		var pv := _route(t, q, Vector2.RIGHT, true)
		if not pv.on_road:
			mountains.append(q)
		pv.free()
		if mountains.size() >= MOUNTAINS:
			break
	_check(mountains.size() == MOUNTAINS, "found %d mountain points (no road near them)" % mountains.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var centers: Array[Vector2] = mountains.duplicate()
	for i in N:
		centers.append(Vector2(rng.randf_range(-30000.0, 30000.0), rng.randf_range(-30000.0, 30000.0)))
	var off_road := 0
	var high := 0.0
	var patrol_far := 0
	for c in centers:
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var cv := _route(t, c, dir, false)
		if not cv.on_road:
			off_road += 1
			print("UNIT: no road for a column through ", c)
		else:
			high = maxf(high, _max_h(t, cv.pts))
		cv.free()
		var pv := _route(t, c, dir, true)
		if pv.on_road:
			high = maxf(high, _max_h(t, pv.pts))
			if pv._center_road.distance_to(c) > NEAR:
				patrol_far += 1
		pv.free()
	print("UNIT: %d columns (%d over the mountains): off road %d, highest route point %.1f px, patrols far off their point %d" % [centers.size(), mountains.size(), off_road, high, patrol_far])
	_check(off_road == 0, "every column found a road (%d did not)" % off_road)
	_check(high < FLOOR_H, "routes stay on the valley floor (highest point %.1f px)" % high)
	_check(patrol_far == 0, "a patrol never takes a far road (%d did)" % patrol_far)
	_check_lanes()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## A column's route through c along dir on terrain t (patrol: the bomber's small column)
func _route(t: Terrain3D, c: Vector2, dir: Vector2, patrol: bool) -> Convoy:
	var cv := Convoy.new()
	cv.patrol = patrol
	cv._build_route(c, dir, t)
	return cv


## Highest terrain under a route, px above the valley floor
func _max_h(t: Terrain3D, pts: PackedVector2Array) -> float:
	var h := 0.0
	for p in pts:
		h = maxf(h, t.height(p.x, p.y))
	return h


## Kanta 25.10: «держать их надо на дороге, максимум небольшие отклонения» — a lane on land is held
## within ROAD_DEV of the road axis on the dry side and at the shoulder on the river side
func _check_lanes() -> void:
	var cv := Convoy.new()
	cv.on_road = true
	cv.river_sign = 1.0
	_check(is_equal_approx(cv.safe_lane(150.0), Convoy.ROAD_DEV), "guard pulling 150 px aside stays at ROAD_DEV (%.0f)" % cv.safe_lane(150.0))
	_check(cv.safe_lane(-150.0) >= -(Terrain3D.D_ROAD - Convoy.RIVER_SAFE) - 0.01, "no lane towards the river past the shoulder (%.0f)" % cv.safe_lane(-150.0))
	_check(is_equal_approx(cv.safe_lane(30.0), 30.0), "a small offset is kept")
	cv.free()
