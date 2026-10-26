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
	_test_to_unit()
	_test_damage_pieces()
	_test_damage_walls()
	_test_damage_gate_store()
	_test_damage_towers()
	_test_hit_weight()
	_test_damage_taken()
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


## Tower pads: unit-mesh corners ±0.42 (round towers on the wall corners, FortBuild) scaled by size and turned by rot like Render3D draws them.
func _test_tower_points() -> void:
	var c := Vector2(1000, 500)
	var pts := FortArea.tower_points(_fort(c))
	_check(pts.size() == 4, "four towers")
	var k := 0.42 * 760.0
	_check(pts[0].distance_to(c + Vector2(-k, -k)) < 0.5, "tower 0 at (-,-) with rot 0")
	_check(pts[3].distance_to(c + Vector2(k, k)) < 0.5, "tower 3 at (+,+) with rot 0")
	var turned := FortArea.tower_points(_fort(c, PI / 2.0))
	_check(turned[0].distance_to(c + Vector2(k, -k)) < 0.5, "rot PI/2 turns tower 0 to (+,-)")
	var big := FortArea.tower_points(_fort(c, 0.0, 874.0))
	_check(absf(big[3].x - c.x - 0.42 * 874.0) < 0.5, "tower offset scales with fort size")


## Two jeeps inside the walls, off the citadel, apart from each other.
func _test_yard_points() -> void:
	var c := Vector2(-400, 1200)
	var f := _fort(c, 0.7)
	var pts := FortArea.yard_points(f)
	_check(pts.size() == 2, "two jeeps")
	for p in pts:
		var u := (p - c).rotated(-0.7) / 760.0   # back to unit-mesh coordinates
		_check(absf(u.x) < 0.3 and absf(u.y) < 0.3, "jeep inside the inner yard %s" % u)
		var in_citadel := u.x > -0.21 and u.x < 0.1 and u.y > -0.26 and u.y < -0.04   # FortBuild citadel + keep
		_check(not in_citadel, "jeep off the citadel %s" % u)
	_check(pts[0].distance_to(pts[1]) > 0.15 * 760.0, "jeeps apart")


## The base may start a lock only while missiles in the air plus locks in progress stay under the cap.
func _test_missile_cap() -> void:
	_check(FortBalance.MISSILE_CAP == 4, "cap is 4 (Kanta 2026-10-25)")
	_check(FortArea.can_lock(0, 0, 4), "empty sky — may lock")
	_check(FortArea.can_lock(2, 1, 4), "3 of 4 — may lock")
	_check(not FortArea.can_lock(3, 1, 4), "3 in air + 1 locking — no new lock")
	_check(not FortArea.can_lock(4, 0, 4), "4 in air — no new lock")


## Logic point to unit-mesh space is the inverse of fort_point (size and rot).
func _test_to_unit() -> void:
	var f := _fort(Vector2(300, -200), 1.1, 874.0)
	var u := Vector2(0.17, -0.3)
	_check(FortArea.to_unit(f, FortArea.fort_point(f, u)).distance_to(u) < 1e-4, "to_unit inverts fort_point")


## FA-03: 4 towers, 8 wall sections (2 per side), gate, store, citadel; all intact at the start.
func _test_damage_pieces() -> void:
	var d := FortDamage.new()
	_check(d.state.size() == 15, "15 pieces, got %d" % d.state.size())
	for id: String in d.state:
		_check(d.state[id] == FortDamage.INTACT, "%s intact at start" % id)
	_check(d.ver == 0, "fresh record has version 0")


## A wall section breaches after its pool of explosive hits (2 bomb hits, *guess*); blasts in the yard
## or rockets alone take longer; a breached section stays breached.
func _test_damage_walls() -> void:
	var d := FortDamage.new()
	var north := Vector2(-23.0, -46.0) * FortBuild.K   # middle of the north wall's west half
	var r := 0.12   # a bomb of 130 px on a 760 px fort is ~0.17 unit; smaller keeps the hit on one section
	_check(d.apply_blast(north, r, 1.0).is_empty(), "one bomb does not breach")
	var got := d.apply_blast(north, r, 1.0)
	_check(got == ["w0"], "second bomb breaches w0, got %s" % [got])
	_check(d.state["w0"] == FortDamage.BROKEN and d.state["w1"] == FortDamage.INTACT, "only the hit section")
	_check(d.ver == 1, "version bumps on a change")
	_check(d.apply_blast(north, r, 1.0).is_empty(), "a breached section does not change again")
	var yard := FortDamage.new()
	for i in 6:
		yard.apply_blast(Vector2(0.0, 0.05), 0.12, 1.0)
	for id: String in ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7"]:
		_check(yard.state[id] == FortDamage.INTACT, "yard blasts leave %s intact" % id)
	var rk := FortDamage.new()
	var east := Vector2(46.0, 23.0) * FortBuild.K
	var n := 0
	while rk.state["w7"] == FortDamage.INTACT and n < 20:
		rk.apply_blast(east, 0.05, FortDamage.hit_weight(52.0))
		n += 1
	_check(n == 5, "rockets (0.4 of a bomb) breach w7 on the 5th hit, got %d" % n)


## The gate has its own pool; the store burns out on any explosive hit.
func _test_damage_gate_store() -> void:
	var d := FortDamage.new()
	var gate := Vector2(0.0, 47.0) * FortBuild.K
	_check(not d.apply_blast(gate, 0.05, 1.0).has("gate"), "one bomb does not blow the gate")
	_check(d.apply_blast(gate, 0.05, 1.0).has("gate"), "the second does")
	var store := Vector2(30.0, -5.0) * FortBuild.K
	_check(d.apply_blast(store, 0.03, 0.3) == ["store"], "any hit burns the store")


## Tower state follows its launcher: half HP — damaged, destroyed — crown collapsed; never goes back.
func _test_damage_towers() -> void:
	var d := FortDamage.new()
	_check(not d.set_tower(2, 0.8), "80 % HP — intact")
	_check(d.set_tower(2, 0.5) and d.state["t2"] == FortDamage.DAMAGED, "50 % — damaged")
	_check(not d.set_tower(2, 0.4), "still damaged — no change")
	_check(d.set_tower(2, 0.0) and d.state["t2"] == FortDamage.BROKEN, "destroyed — collapsed")
	_check(not d.set_tower(2, 1.0) and d.state["t2"] == FortDamage.BROKEN, "stays collapsed")
	var t := FortDamage.new()
	_check(t.set_tower(0, 0.0) and t.state["t0"] == FortDamage.BROKEN, "one big hit skips straight to collapsed")
	t.apply_blast(FortArea.tower_points(_fort(Vector2.ZERO, 0.0, 1.0))[1], 0.2, 5.0)
	_check(t.state["t1"] == FortDamage.INTACT, "blasts do not break towers")


## Explosive hit weight: a bomb (130 px) is 1, smaller blasts less, the biggest capped at 1.5.
func _test_hit_weight() -> void:
	_check(is_equal_approx(FortDamage.hit_weight(FortBalance.BOMB_R), 1.0), "bomb radius weighs 1")
	_check(is_equal_approx(FortDamage.hit_weight(FortBalance.BOMB_R * 0.4), 0.4), "rocket weighs its radius share")
	_check(is_equal_approx(FortDamage.hit_weight(1000.0), 1.5), "capped at 1.5")


## FA-04: the citadel burns when the fort is taken (spec table), once; blasts never set it off.
func _test_damage_taken() -> void:
	var d := FortDamage.new()
	d.apply_blast(Vector2(-6.0, -16.0) * FortBuild.K, 0.2, 5.0)
	_check(d.state["citadel"] == FortDamage.INTACT, "blasts do not burn the citadel")
	var v := d.ver
	_check(d.take(), "taking the fort sets the citadel burning")
	_check(d.state["citadel"] == FortDamage.BROKEN and d.ver == v + 1, "citadel burning, version bumped")
	_check(not d.take(), "taken only once")
