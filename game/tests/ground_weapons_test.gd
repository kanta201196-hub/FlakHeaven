extends SceneTree
## Unit tests for `Weapons.offered`: a sortie without ground targets («Битва асов») does not offer
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
		_check(not Weapons.offered(w, false), "%s is not offered without ground targets" % w)


func _test_no_ground_keeps_air_weapons() -> void:
	for w in ["aam", "rockets", "flares", "srm", "railgun", "emp", "laser", "turret"]:
		_check(Weapons.offered(w, false), "%s is still offered without ground targets" % w)


func _test_ground_keeps_all() -> void:
	for w in Weapons.POOL + Weapons.EXP:
		_check(Weapons.offered(w, true), "%s is offered when the sortie has ground targets" % w)
	# every ground-only weapon is a real weapon of the game, so a typo in the list cannot hide nothing
	for w in Weapons.GROUND_ONLY:
		_check(Weapons.DEFS.has(w), "%s in GROUND_ONLY is a weapon" % w)


func _test_run_default() -> void:
	_check(RunState.new().ground_targets, "a new sortie has ground targets by default")
