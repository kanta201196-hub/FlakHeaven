extends RefCounted
## S11-09 (Kanta 25.10): the hangar picks the starting weapons from one list, at most two kinds; the
## class signature is the default and can be dropped. The second place opens at crew level START2_LVL.
## Checks the pick limit, the save and the migration from the old «second hardpoint at start» key, and
## which hardpoint group each pick lands on. Same style as `progression_cases.gd`.

const TEST_PATH := "user://test_profile_s11_09.json"

var _failed := 0
var _checks := 0
var _profile_script: GDScript = load("res://scripts/profile.gd")


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_defaults()
	_test_options()
	_test_limit()
	_test_round_trip()
	_test_migration()
	_test_assign()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _fresh_profile() -> Node:
	var p: Node = _profile_script.new()
	p.path = TEST_PATH
	p.reset_data()
	return p


func _to_lvl(p: Node, c: String, lv: int) -> void:
	while p.crew_lvl(c) < lv:
		p.debug_level(c)


func _test_defaults() -> void:
	var p := _fresh_profile()
	for c in PlaneClasses.LIST:
		_check(p.start_weapons(c) == [PlaneClasses.signature(c)], "%s: default start = signature" % c)
	p.free()


func _test_options() -> void:
	var p := _fresh_profile()
	for c in PlaneClasses.LIST:
		var opts: Array = p.start_options(c)
		_check(not opts.is_empty() and opts[0] == PlaneClasses.signature(c), "%s: signature first" % c)
		_check(opts.all(func(w): return Weapons.POOL.has(w) and PlaneClasses.allows(c, w)), "%s: only this plane's pool weapons" % c)
		_check(not opts.has("turret") and not opts.has("railgun"), "%s: no turret, no experimental" % c)
	p.free()


func _test_limit() -> void:
	var p := _fresh_profile()
	var c := "fighter"
	_check(p.start_cap(c) == 1, "crew lvl 1: one place")
	_check(not p.toggle_start(c, "flares"), "lvl 1: second kind refused")
	_check(p.start_weapons(c) == ["aam"], "lvl 1: still only aam")
	_check(p.toggle_start(c, "aam") and p.start_weapons(c).is_empty(), "signature can be dropped")
	_check(p.toggle_start(c, "flares") and p.start_weapons(c) == ["flares"], "another kind instead")
	_to_lvl(p, c, p.START2_LVL)
	_check(p.start_cap(c) == 2, "crew lvl 5: two places")
	_check(p.toggle_start(c, "aam") and p.start_weapons(c) == ["flares", "aam"], "second kind appended in order")
	_check(not p.toggle_start(c, "rockets") and p.start_weapons(c).size() == 2, "third kind refused")
	_check(not p.toggle_start(c, "bombs"), "weapon of another class refused")
	_check(not p.toggle_start(c, "railgun"), "experimental refused")
	p.free()


func _test_round_trip() -> void:
	var p := _fresh_profile()
	_to_lvl(p, "attacker", p.START2_LVL)
	p.toggle_start("attacker", "flares")
	p.save()
	var q := _fresh_profile()
	q.load_profile()
	_check(q.start_weapons("attacker") == ["rockets", "flares"], "start list survives save/load in order")
	# a hand-edited save with junk keeps only valid kinds, at most the cap
	q.cls("attacker")["start"] = ["railgun", "flares", "flares", "aam", "agm"]
	_check(q.start_weapons("attacker") == ["flares", "aam"], "junk filtered, duplicates dropped, cap 2")
	p.free()
	q.free()


func _test_migration() -> void:
	var p := _fresh_profile()
	_to_lvl(p, "bomber", p.START2_LVL)
	var old: Dictionary = p.data.duplicate(true)
	for c in old["classes"]:
		old["classes"][c].erase("start")
	old["classes"]["bomber"]["start2"] = "rockets"
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var q := _fresh_profile()
	q.load_profile()
	_check(q.start_weapons("bomber") == ["bombs", "rockets"], "old save: signature + old second hardpoint")
	_check(q.start_weapons("fighter") == ["aam"], "old save without start2: signature only")
	p.free()
	q.free()


## Picks land on normal groups: the signature on its own group 0, the rest in order;
## a bomb bay (group 0 of «Кит») takes other kinds only when no other group is free.
func _test_assign() -> void:
	var f2 := ["Крылья (пара)", "Под фюзеляжем"]
	_check(_profile_script.start_assign(f2, ["aam", "flares"], "aam") == ["aam", "flares"], "fighter: signature + one")
	_check(_profile_script.start_assign(f2, ["flares", "aam"], "aam") == ["aam", "flares"], "signature keeps group 0 whatever the order")
	_check(_profile_script.start_assign(f2, ["flares", "rockets"], "aam") == ["flares", "rockets"], "no signature: in order")
	_check(_profile_script.start_assign(f2, [], "aam") == ["", ""], "empty start")
	var b3 := ["Бомбоотсек", "Крылья (пара)", "Внешняя пара"]
	_check(_profile_script.start_assign(b3, ["rockets", "flares"], "bombs") == ["", "rockets", "flares"], "bomber: bay left empty when wings are free")
	var b2 := ["Бомбоотсек", "Крылья (пара)"]
	_check(_profile_script.start_assign(b2, ["rockets", "flares"], "bombs") == ["flares", "rockets"], "bomber: bay used last")
	_check(_profile_script.start_assign(b2, ["hebomb", "bombs"], "bombs") == ["bombs", "hebomb"], "bomber: bombs in the bay")
