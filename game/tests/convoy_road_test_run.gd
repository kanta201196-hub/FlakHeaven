extends Node
## Working part of convoy_road_test.gd: builds the world terrain like the game (same seed) and
## routes columns through random points over 60 × 60 km and through MOUNTAIN, points over the
## mountains 0.7–2.7 km from any river where the old search found no road (straight line over the ridges).

const N := 16
const MOUNTAIN := [Vector2(7043.4, 2534.6), Vector2(6958.4, 3421.2), Vector2(21634.0, 26801.5)]
const FLOOR_H := 20.0   # px above the valley floor: the road bed is ~0–4

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
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var off_road := 0
	var high := 0.0
	var far := 0
	var patrol_dropped := 0
	var centers: Array = MOUNTAIN.duplicate()
	for i in N:
		centers.append(Vector2(rng.randf_range(-30000.0, 30000.0), rng.randf_range(-30000.0, 30000.0)))
	for c: Vector2 in centers:
		var dir := Vector2.from_angle(rng.randf() * TAU)
		if absf(t.river_field(c.x, c.y)) > 600.0:
			far += 1
		var cv := Convoy.new()
		cv._build_route(c, dir, t)
		if not cv.on_road:
			off_road += 1
			print("UNIT: no road for a column through ", c)
		else:
			high = maxf(high, _max_h(t, cv.pts))
		cv.free()
		var pv := Convoy.new()
		pv.patrol = true
		pv._build_route(c, dir, t)
		if pv.on_road:
			high = maxf(high, _max_h(t, pv.pts))
		else:
			patrol_dropped += 1
		pv.free()
	print("UNIT: %d columns (%d far from a river): off road %d, highest route point %.1f px; patrols dropped %d" % [centers.size(), far, off_road, high, patrol_dropped])
	_check(far > 0, "the sample has points far from any river (the mountain case)")
	_check(off_road == 0, "every column found a road (%d did not)" % off_road)
	_check(high < FLOOR_H, "routes stay on the valley floor (highest point %.1f px)" % high)
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Highest terrain under a route, px above the valley floor
func _max_h(t: Terrain3D, pts: PackedVector2Array) -> float:
	var h := 0.0
	for p in pts:
		h = maxf(h, t.height(p.x, p.y))
	return h
