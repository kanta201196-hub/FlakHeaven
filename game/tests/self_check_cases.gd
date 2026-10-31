extends RefCounted
## Checks of the build self-check job lists (SelfCheck, R-23): which planes, weapons and tiers the sheet covers,
## the single-weapon hangar loadout and the combat loadout. Run by `self_check_test.gd` once the autoloads exist.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_planes()
	_test_tiers()
	_test_hangar_jobs()
	_test_store_jobs()
	_test_loadout()
	_test_combat()
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_planes() -> void:
	var pl := SelfCheck.planes()
	_check(pl.size() == 6, "three classes × two planes (got %d)" % pl.size())
	_check(pl.has(["bomber", 2]) and pl.has(["fighter", 1]), "bomber 2 and fighter 1 are there")
	var w := SelfCheck.plane_weapons("fighter", 2)
	_check(w.has("srm") and not SelfCheck.plane_weapons("fighter", 1).has("srm"), "srm only on «Оса» 2")
	_check(not w.has("railgun"), "no experimental weapons")


func _test_tiers() -> void:
	_check(SelfCheck.tiers("aam") == [1, 2, 3, 4], "aam evolves: four tiers")
	_check(SelfCheck.tiers("agm") == [1, 2, 3], "agm has no modernisation")


## Every plane × weapon at four tiers; a weapon without modernisation keeps an empty ("na") cell
func _test_hangar_jobs() -> void:
	var jobs := SelfCheck.hangar_jobs()
	var combos := 0
	for pl: Array in SelfCheck.planes():
		combos += SelfCheck.plane_weapons(pl[0], pl[1]).size()
	_check(jobs.size() == combos * 4, "4 cells per plane × weapon (%d, %d combos)" % [jobs.size(), combos])
	var na := jobs.filter(func(j: Dictionary) -> bool: return j["na"])
	_check(na.all(func(j: Dictionary) -> bool: return j["tier"] == 4 and not Prog.EVOS.has(j["weapon"])), "only modernised cells of non-evolving weapons are empty")
	_check(jobs.any(func(j: Dictionary) -> bool: return j["cls"] == "bomber" and j["lvl"] == 2 and j["weapon"] == "turret" and j["tier"] == 4),
		"«Кит» 2 turret modernised is shot")


func _test_store_jobs() -> void:
	var jobs := SelfCheck.store_jobs()
	var turrets := jobs.filter(func(j: Dictionary) -> bool: return j["weapon"] == "turret")
	_check(turrets.size() == 8, "turret store for attacker and bomber, 4 tiers each (got %d)" % turrets.size())
	_check(jobs.filter(func(j: Dictionary) -> bool: return j["weapon"] == "aam").size() == 4, "aam once in the store")


## The weapon goes where the game would put it as the only start weapon; other groups are emptied
func _test_loadout() -> void:
	var e := Hangar3D.BENCH_EMPTY
	_check(SelfCheck.loadout("fighter", "aam") == ["aam", e], "signature on the wing pair")
	_check(SelfCheck.loadout("bomber", "bombs") == ["bombs", e], "bombs in the bay")
	_check(SelfCheck.loadout("bomber", "rockets") == [e, "rockets"], "rockets on the bomber's wings, not in the bay")
	_check(SelfCheck.loadout("attacker", "turret") == [e, e], "turret alone: every group empty")


func _test_combat() -> void:
	var b := SelfCheck.combat_loadout("bomber", 1)
	_check(b.size() == PlaneClasses.group_defs("bomber", true).size(), "one weapon per bomber group")
	_check(b[0] == "bombs", "bombs in the bay group (got %s)" % b[0])
	_check(not b.has("turret") and not b.has("flares"), "no turret or flares on a hardpoint")
	var pts := SelfCheck.combat_points(Vector2(10, 20))
	_check(pts.size() == 6 * 5, "five shots per plane (got %d)" % pts.size())
	_check(pts.filter(func(p: Dictionary) -> bool: return p.get("sc_check", false)).size() == 6, "one checked shot per plane")
	_check(pts.all(func(p: Dictionary) -> bool: return p["pos"] == Vector2(10, 20)), "all at the given spot")
	var close := pts.filter(func(p: Dictionary) -> bool: return p["sc_shot"] in ["nozzles", "muzzles", "stores"])
	_check(close.all(func(p: Dictionary) -> bool: return p.has("sc_fill") and not p.has("zoom")), "close-ups sized by plane length, not a fixed zoom")
