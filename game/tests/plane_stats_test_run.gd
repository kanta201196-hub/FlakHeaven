extends Node
## Working part of plane_stats_test.gd (PlaneClasses and Cards compile against the autoloads). Unit tests for `PlaneStats` (S16-08): the hangar's plane characteristics and the level-1 → level-2 difference.
## Pinned here: numbers follow the class data and the hangar nodes, and buying plane 2 shows what it adds.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _ready() -> void:
	var f1 := PlaneStats.of("fighter", 1)
	_check(f1["hull"] == 120 and f1["speed"] == 390 and f1["turn"] == 210, "«Оса» 1: hull 120, speed 390, turn 210 (%s)" % f1)
	_check(f1["gun_dps"] == roundi(15.0 * 0.733 * 9.0), "«Оса» gun dps = bullet 15 × 0.733 × 9/s")
	_check(f1["hardpoints"] == 3 and f1["heavy"] == 0, "«Оса» 1: 3 hardpoints, no heavy pylon")
	var b1 := PlaneStats.of("bomber", 1, {"armor": 2, "engine": 5, "pylons": 2})
	_check(b1["hull"] == 275, "armor node 2: hull +10 %% (250 → %d)" % b1["hull"])
	_check(b1["speed"] == roundi(390.0 * 0.82 * 1.1), "engine node 5: speed +10 %%")
	_check(b1["hardpoints"] == 6 and b1["pylon_dmg"] == 8, "pylons 2: third group (+2) and +8 %% hardpoint damage")
	var f2 := PlaneStats.of("fighter", 2)
	var d := PlaneStats.diff(f1, f2)
	var keys := d.map(func(r: Array) -> String: return String(r[0]))
	_check(keys.has("heavy") and keys.has("star") and keys.has("weapons"), "plane 2 shows heavy pylon, ★ bonus and weapons (%s)" % [keys])
	_check(d.all(func(r: Array) -> bool: return bool(r[3])), "every change of plane 2 is an improvement")
	_check(not keys.has("hull"), "same nodes: plane 2 has the same hull as plane 1 today")
	for c in PlaneClasses.LIST:
		var s := PlaneStats.of(c, 1)
		for r: Array in PlaneStats.ROWS:
			_check(s.has(r[0]), "%s has row %s" % [c, r[0]])
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
