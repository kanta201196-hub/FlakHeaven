extends Node
## Working part of fort_area_test.gd: FortArea needs the autoloads (Events, Main), which exist only
## after the SceneTree starts.

var _failed := 0
var _checks := 0


func _ready() -> void:
	_test_pick_fort()
	_test_tower_points()
	_test_yard_points()
	_test_missile_cap()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _fort(pos: Vector2, rot := 0.0, size := 760.0) -> Dictionary:
	return {"name": "o_fort", "pos": pos, "size": size, "rot": rot, "var": 0}


## Nearest fort within reach; other objects and forts out of reach are ignored.
func _test_pick_fort() -> void:
	_check(FortArea.pick_fort([], Vector2.ZERO, 3000.0).is_empty(), "no objects — no fort")
	var village := {"name": "o_village", "pos": Vector2(100, 0), "size": 1650.0, "rot": 0.0}
	_check(FortArea.pick_fort([village], Vector2.ZERO, 3000.0).is_empty(), "a village is not a fort")
	var far := _fort(Vector2(3500, 0))
	_check(FortArea.pick_fort([far], Vector2.ZERO, 3000.0).is_empty(), "fort out of reach is skipped")
	var a := _fort(Vector2(2000, 0))
	var b := _fort(Vector2(0, 900))
	var got := FortArea.pick_fort([far, village, a, b], Vector2.ZERO, 3000.0)
	_check(got.get("pos") == Vector2(0, 900), "nearest of two forts in reach")


## Tower tops: unit-mesh corners ±0.352 scaled by size and turned by rot like Render3D draws them.
func _test_tower_points() -> void:
	var c := Vector2(1000, 500)
	var pts := FortArea.tower_points(_fort(c))
	_check(pts.size() == 4, "four towers")
	var k := 0.352 * 760.0
	_check(pts[0].distance_to(c + Vector2(-k, -k)) < 0.5, "tower 0 at (-,-) with rot 0")
	_check(pts[3].distance_to(c + Vector2(k, k)) < 0.5, "tower 3 at (+,+) with rot 0")
	var turned := FortArea.tower_points(_fort(c, PI / 2.0))
	_check(turned[0].distance_to(c + Vector2(k, -k)) < 0.5, "rot PI/2 turns tower 0 to (+,-)")
	var big := FortArea.tower_points(_fort(c, 0.0, 874.0))
	_check(absf(big[3].x - c.x - 0.352 * 874.0) < 0.5, "tower offset scales with fort size")


## Two jeeps inside the walls, off the citadel, apart from each other.
func _test_yard_points() -> void:
	var c := Vector2(-400, 1200)
	var f := _fort(c, 0.7)
	var pts := FortArea.yard_points(f)
	_check(pts.size() == 2, "two jeeps")
	for p in pts:
		var u := (p - c).rotated(-0.7) / 760.0   # back to unit-mesh coordinates
		_check(absf(u.x) < 0.3 and absf(u.y) < 0.3, "jeep inside the inner yard %s" % u)
		var in_citadel := u.x > -0.06 and u.x < 0.18 and u.y > -0.12 and u.y < 0.08
		_check(not in_citadel, "jeep off the citadel %s" % u)
	_check(pts[0].distance_to(pts[1]) > 0.15 * 760.0, "jeeps apart")


## The base may start a lock only while missiles in the air plus locks in progress stay under the cap.
func _test_missile_cap() -> void:
	_check(FortBalance.MISSILE_CAP == 4, "cap is 4 (Kanta 2026-10-25)")
	_check(FortArea.can_lock(0, 0, 4), "empty sky — may lock")
	_check(FortArea.can_lock(2, 1, 4), "3 of 4 — may lock")
	_check(not FortArea.can_lock(3, 1, 4), "3 in air + 1 locking — no new lock")
	_check(not FortArea.can_lock(4, 0, 4), "4 in air — no new lock")
