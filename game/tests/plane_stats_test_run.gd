extends Node
## Working part of plane_stats_test.gd. Works on an in-memory fresh profile (never saved).

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.001 * maxf(absf(b), 1.0)


func _ready() -> void:
	Profile.reset_data()
	Profile.debug_plane = 0
	_check(Profile.meta_k() > 0.0, "meta progression is on (hangar bonuses count)")
	for c: String in PlaneClasses.LIST:
		var s1 := PlaneStats.compute(c, 1)
		var s2 := PlaneStats.compute(c, 2)
		_check(_near(float(s2["hull"]), float(s1["hull"]) * 1.15), "%s: plane 2 hull +15%%" % c)
		_check(_near(float(s2["speed"]), float(s1["speed"]) * 1.05), "%s: plane 2 speed +5%%" % c)
		_check(_near(float(s2["turn"]), float(s1["turn"]) * 1.05), "%s: plane 2 turn +5%%" % c)
		_check(int(s2["groups"]) == int(s1["groups"]) + 1, "%s: plane 2 has the heavy mount group" % c)
		_check(float(s1["gun_dps"]) > 0.0, "%s: course gun has damage per second" % c)
		for row: Array in PlaneStats.ROWS:
			_check(s1.has(row[0]) and s2.has(row[0]), "%s: row %s present" % [c, row[0]])
		_check(Profile.debug_plane == 0, "%s: the flying plane override is restored" % c)
	# the «Броня» node of plane 1 raises plane 1's hull only (+5% per level)
	var base1 := float(PlaneStats.compute("fighter", 1)["hull"])
	var base2 := float(PlaneStats.compute("fighter", 2)["hull"])
	Profile.cls("fighter")["nodes"]["armor"] = 2
	_check(_near(float(PlaneStats.compute("fighter", 1)["hull"]), base1 * (1.0 + 0.1 * Profile.meta_k())), "armor node lvl 2 on plane 1: hull +10%")
	_check(_near(float(PlaneStats.compute("fighter", 2)["hull"]), base2), "plane 1's armor node leaves plane 2 alone")
	# the cached call follows a profile change
	var cached := float(PlaneStats.of("fighter", 1)["hull"])
	Profile.cls("fighter")["nodes"]["armor"] = 0
	_check(_near(float(PlaneStats.of("fighter", 1)["hull"]), base1) and not _near(cached, base1), "cache follows a node purchase")
	print("UNIT: plane_stats %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
