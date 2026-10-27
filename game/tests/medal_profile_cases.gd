extends RefCounted
## Medals in the profile (Kanta 2026-10-27, «Наградная планка»): a sortie's counters add up, a new tier is reported
## once, collections count distinct cards, bonuses follow the tiers, and the counters survive save and load.
## The profile is a fresh instance writing to a test file, so a player's real profile is never touched.
## Loaded by `medal_profile_test.gd` after the first frame (game scripts use autoloads).

const TEST_PATH := "user://test_profile_medals.json"

var _failed := 0
var _checks := 0
var _profile_script: GDScript = load("res://scripts/profile.gd")


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_award()
	_test_round_trip()
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


func _test_award() -> void:
	var p := _fresh_profile()
	var nt: Array = p.medals_award({"kills": 600, "evacs": 1, "sorties_bomber": 1}, 4000, ["w:aam", "m:armor"], ["carousel"])
	_check(nt.size() == 1 and nt[0][0] == "tough", "first evacuation: «Живучий» bronze, nothing else (got %s)" % str(nt))
	_check(is_equal_approx(p.medal_bonus("hp"), 0.02), "«Живучий» tier 1: +2 % HP")
	nt = p.medals_award({"kills": 600}, 7000, ["w:aam", "m:armor", "m:engine"], ["carousel"])
	var ids := nt.map(func(x): return x[0])
	_check(ids.has("fighter") and ids.has("scrap"), "1 200 kills and 11 000 parts: «Истребитель» and «Сборщик мусора»")
	_check(int(p.medal_counters()["sorties"]) == 2, "two sorties counted")
	_check(int(p.medal_counters()["cards_seen"]) == 3, "cards counted once each")
	_check(int(p.medal_counters()["syn_seen"]) == 1, "synergies counted once each")
	_check(p.medals_award({}, 0, [], []).is_empty(), "an empty sortie gives no new tier")
	_check(is_equal_approx(p.medal_parts_k("pass"), 1.02), "parts bonus +2 % from «Сборщик мусора»")


func _test_round_trip() -> void:
	var p := _fresh_profile()
	p.medals_award({"kills": 1500, "ram_drones": 120}, 100, ["w:aam"], [])
	p.save()
	var q := _fresh_profile()
	q.load_profile()
	_check(int(q.medal_counters()["kills"]) == 1500, "kills survive save and load")
	_check(int(q.medal_tiers()["ram"]) == 1, "hidden «Таран» survives save and load")
	_check((q.data["medals"]["cards"] as Array).has("w:aam"), "cards taken survive save and load")
