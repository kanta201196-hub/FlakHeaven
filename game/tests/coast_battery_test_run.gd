extends Node
## Working part of coast_battery_test.gd: the pure checks of CoastBattery (pick, cap, lead, hit) and, on the
## Archipelago terrain built like the game, the share of points along the strait where a full battery fits.

var _failed := 0
var _checks := 0


func _ready() -> void:
	_test_pick_spacing()
	_test_pick_fails()
	_test_pick_nearest_first()
	_test_cap()
	_test_lead()
	_test_hit()
	await _test_real_coast()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## A dense line of candidates along a coast: 4 guns, every pair at least GAP_MIN apart, each within GAP_MAX of
## another one (a battery, not 4 lone guns), all within SEARCH_R of the centre.
func _test_pick_spacing() -> void:
	var cands := PackedVector2Array()
	for i in range(-40, 41):
		cands.append(Vector2(i * 25.0, 30.0 * sin(i * 0.3)))
	var g := CoastBattery.pick(cands, Vector2.ZERO)
	_check(g.size() == BatteryBalance.GUNS, "4 guns on a long coast (got %d)" % g.size())
	for i in g.size():
		var near := INF
		for j in g.size():
			if i != j:
				_check(g[i].distance_to(g[j]) >= BatteryBalance.GAP_MIN - 0.01, "pair %d-%d at least GAP_MIN apart" % [i, j])
				near = minf(near, g[i].distance_to(g[j]))
		_check(near <= BatteryBalance.GAP_MAX + 0.01, "gun %d has a neighbour within GAP_MAX" % i)
		_check(g[i].length() <= BatteryBalance.SEARCH_R + 0.01, "gun %d within SEARCH_R" % i)


## Too little coast for 4 spread guns: empty, so the spawner tries another place (or skips the slot).
func _test_pick_fails() -> void:
	var cands := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(400, 0)])
	_check(CoastBattery.pick(cands, Vector2.ZERO).is_empty(), "3 spots in a short strip → none")
	_check(CoastBattery.pick(PackedVector2Array(), Vector2.ZERO).is_empty(), "no candidates → none")
	# two far clusters: each gun is spaced, but the clusters are farther than GAP_MAX apart
	var far := PackedVector2Array([Vector2(-800, 0), Vector2(-450, 0), Vector2(800, 0), Vector2(450, 0)])
	_check(CoastBattery.pick(far, Vector2.ZERO).is_empty(), "900 px gap between pairs → not one battery")


## The first gun is the candidate nearest the centre (the battery sits where the spawner wanted it).
func _test_pick_nearest_first() -> void:
	var cands := PackedVector2Array()
	for i in range(0, 60):
		cands.append(Vector2(-700.0 + i * 25.0, 0.0))
	var g := CoastBattery.pick(cands, Vector2(10, 0))
	_check(not g.is_empty() and g[0].distance_to(Vector2(10, 0)) < 13.0, "first gun nearest the centre")


## At most RING_CAP shells on the ground at once for the whole battery.
func _test_cap() -> void:
	_check(CoastBattery.can_fire(0), "no rings → may fire")
	_check(CoastBattery.can_fire(BatteryBalance.RING_CAP - 1), "one under the cap → may fire")
	_check(not CoastBattery.can_fire(BatteryBalance.RING_CAP), "at the cap → holds fire")


## The shell aims where the player will be when it bursts.
func _test_lead() -> void:
	var at := CoastBattery.lead(Vector2(100, 0), Vector2(200, 0), 1.0)
	_check(at.is_equal_approx(Vector2(300, 0)), "1 s ahead at 200 px/s")
	_check(CoastBattery.lead(Vector2(5, 5), Vector2.ZERO, 1.0).is_equal_approx(Vector2(5, 5)), "standing still")


## A burst hurts the plane when its hitbox touches the burst circle.
func _test_hit() -> void:
	var r := BatteryBalance.BURST_R
	_check(CoastBattery.hits(Vector2.ZERO, Vector2(r + 9.0, 0), 10.0), "hitbox edge inside → hit")
	_check(not CoastBattery.hits(Vector2.ZERO, Vector2(r + 11.0, 0), 10.0), "just outside → miss")


## The Archipelago as in the game: centres along both shores of the strait; a battery must fit at most of them
## (each spot real: on land within SHORE_MIN–SHORE_MAX of the water), else the slot would mostly be skipped.
func _test_real_coast() -> void:
	Biome.id = Biome.ARCHIPELAGO
	var bg: Background = load("res://scripts/background.gd").new()
	add_child(bg)
	await get_tree().process_frame
	var t: Terrain3D = load("res://scripts/terrain3d.gd").new()
	add_child(t)
	t.setup(500.0, StandardMaterial3D.new(), bg)
	var ok := 0
	var n := 0
	var t0 := Time.get_ticks_msec()
	for i in 24:
		var c := Vector2(randf_range(-40000.0, 40000.0), randf_range(-40000.0, 40000.0))
		n += 1
		var g := CoastBattery.pick(CoastBattery.candidates(t, c), c)
		if g.is_empty():
			continue
		ok += 1
		for q in g:
			var s := absf(t.river_field(q.x, q.y)) - Terrain3D.SEA_W
			_check(s >= BatteryBalance.SHORE_MIN and s <= BatteryBalance.SHORE_MAX, "gun on the shore strip (%.0f px)" % s)
	var ms := float(Time.get_ticks_msec() - t0) / n
	print("UNIT: coast battery fits at %d of %d random points, %.0f ms per search" % [ok, n, ms])
	_check(ok > 0, "a battery fits somewhere on the Archipelago")
