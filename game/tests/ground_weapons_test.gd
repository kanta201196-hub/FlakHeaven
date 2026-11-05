extends SceneTree
## Unit tests for `CardBalance.offered`: a sortie without ground targets («Битва асов») does not offer
## weapons that only hit the ground (Kanta 2026-11-04: «в битве асов убери ракету В-З, там же нет наземки»).
## Rules pinned here: with no ground targets the air-to-ground missile, both bombs and the plasma bomb
## are never offered; everything that can hit a plane still is; with ground targets nothing is hidden;
## a fresh sortie has ground targets unless the mode says otherwise.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_no_ground_hides_ground_only()
	_test_no_ground_keeps_air_weapons()
	_test_ground_keeps_all()
	_test_run_default()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_no_ground_hides_ground_only() -> void:
	for w in ["agm", "bombs", "hebomb", "plasma"]:
		_check(not CardBalance.offered(w, false), "%s is not offered without ground targets" % w)


func _test_no_ground_keeps_air_weapons() -> void:
	for w in ["aam", "rockets", "flares", "srm", "railgun", "emp", "laser", "turret"]:
		_check(CardBalance.offered(w, false), "%s is still offered without ground targets" % w)


func _test_ground_keeps_all() -> void:
	# every card weapon of the game (`Weapons.POOL` + `Weapons.EXP`; `Weapons` itself needs autoloads, so the
	# list is written out here)
	var all := ["aam", "rockets", "flares", "bombs", "srm", "agm", "hebomb", "railgun", "emp", "laser", "plasma"]
	for w in all:
		_check(CardBalance.offered(w, true), "%s is offered when the sortie has ground targets" % w)
	# a typo in GROUND_ONLY would hide nothing, so every id there is a real weapon
	for w in CardBalance.GROUND_ONLY:
		_check(all.has(w), "%s in GROUND_ONLY is a weapon" % w)


func _test_run_default() -> void:
	_check(RunState.new().ground_targets, "a new sortie has ground targets by default")
