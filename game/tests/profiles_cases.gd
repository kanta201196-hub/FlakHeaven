extends RefCounted
## Unit tests for the weapon profiles (PG-06): the data table, the fork rule, the multipliers on a
## hardpoint and the hangar gate of the third profile. Same style as `progression_cases.gd`; the profile
## under test is a fresh instance writing to a test file, so a player's real profile is never touched.

const TEST_PATH := "user://test_profile_pg06.json"

var _failed := 0
var _checks := 0
var _profile_script: GDScript = load("res://scripts/profile.gd")


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_table()
	_test_due()
	_test_open_ids()
	_test_hardpoint_factors()
	_test_hangar_gate()
	_test_card_rules()
	_test_due_at_max()
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


## Stage 1: four weapons, three profiles each, every profile with player text and a target line.
func _test_table() -> void:
	for w in ["aam", "srm", "agm", "rockets"]:
		_check(WeaponProfiles.has(w), "%s has profiles" % w)
		var ids := WeaponProfiles.ids(w)
		_check(ids.size() == 3, "%s: 3 profiles" % w)
		for id in ids:
			var d := WeaponProfiles.def(w, id)
			_check(not d.is_empty(), "%s/%s defined" % [w, id])
			for key in ["title", "desc", "vs"]:
				_check(String(d.get(key, "")) != "", "%s/%s has %s" % [w, id, key])
			_check(d.has("dmg") or not d.keys().any(func(x): return x in ["per_slot", "split", "range", "count", "extra"]) or id in ["cluster", "arm"],
				"%s/%s has a damage factor" % [w, id])
		_check(WeaponProfiles.third(w) == ids[2], "%s: third is the last" % w)
	for w in ["flares", "bombs", "hebomb", "turret"]:
		_check(not WeaponProfiles.has(w) and WeaponProfiles.ids(w).is_empty() and WeaponProfiles.third(w) == "", "%s: no profiles yet" % w)
	_check(WeaponProfiles.k("aam", "pair", "dmg") == 0.55, "aam/pair dmg 0.55")
	_check(WeaponProfiles.k("aam", "pair", "cd") == 1.0, "missing multiplier is 1")
	_check(WeaponProfiles.k("aam", "none", "dmg") == 1.0 and WeaponProfiles.k("bombs", "x", "dmg") == 1.0, "unknown profile is 1")
	_check(WeaponProfiles.val("srm", "guard", "intercept", 0.0) == 300.0 and WeaponProfiles.val("srm", "swarm", "intercept", 0.0) == 0.0, "behaviour value with default")


## The fork is due at level LEVEL - 1 without a profile, for weapons with profiles only; a legendary
## new-weapon card may start above that level and still gets the choice.
func _test_due() -> void:
	_check(WeaponProfiles.due(2, "", "aam"), "aam lvl 2 due")
	_check(not WeaponProfiles.due(1, "", "aam"), "aam lvl 1 not due")
	_check(not WeaponProfiles.due(2, "pair", "aam"), "aam with profile not due")
	_check(not WeaponProfiles.due(2, "", "flares"), "flares never due")
	_check(WeaponProfiles.due(3, "", "rockets") and WeaponProfiles.due(5, "", "srm"), "due above the fork level too")


func _test_open_ids() -> void:
	_check(WeaponProfiles.open_ids("aam", false) == ["pair", "reach"], "two profiles without the hangar")
	_check(WeaponProfiles.open_ids("aam", true) == ["pair", "reach", "frag"], "three with the hangar")
	_check(WeaponProfiles.open_ids("bombs", true).is_empty(), "none for a weapon without profiles")


## `Hardpoint.dmg()` and `range_px()` take the profile multipliers (the ratio to the plain weapon).
func _test_hardpoint_factors() -> void:
	var h := Hardpoint.new("test", 2, "aam")
	h.level = 3
	var d0 := h.dmg()
	var r0 := h.range_px()
	h.profile = "pair"
	_check(is_equal_approx(h.dmg() / d0, 0.55), "aam/pair dmg ×0.55 (got %.3f)" % (h.dmg() / d0))
	_check(is_equal_approx(h.range_px() / r0, 1.0), "aam/pair range ×1")
	h.profile = "reach"
	_check(is_equal_approx(h.range_px() / r0, 1.43), "aam/reach range ×1.43 (got %.3f)" % (h.range_px() / r0))
	_check(is_equal_approx(h.dmg() / d0, 0.9), "aam/reach dmg ×0.9")
	_check(h.label().contains(WeaponProfiles.def("aam", "reach")["title"]), "label names the profile")
	var g := Hardpoint.new("test", 2, "rockets")
	g.level = 3
	var g0 := g.dmg()
	g.profile = "heat"
	_check(is_equal_approx(g.dmg() / g0, 1.6), "rockets/heat dmg ×1.6")
	g.profile = ""
	_check(is_equal_approx(g.dmg() / g0, 1.0), "no profile: ×1")


## The third profile opens with tier THIRD_TIER of the weapon's hangar branch; a weapon without a hangar
## branch (`srm`, `agm` until PR 3) keeps it closed.
func _test_hangar_gate() -> void:
	var p := _fresh_profile()
	_check(not p.profile_open("aam"), "fresh profile: third closed")
	p.data["weapons"]["aam"]["t1"] = "a"
	_check(not p.profile_open("aam"), "tier 1 alone does not open it")
	p.data["weapons"]["aam"]["t2"] = "b"
	_check(p.profile_open("aam") == (p.meta_k() > 0.0), "tier 2 opens the third (meta on)")
	_check(not p.profile_open("srm"), "srm: no hangar branch, closed")
	_check(not p.profile_open("bombs"), "bombs: no profiles, closed")
	p.free()


## Card rules: the profile card raises the level by one and sets the profile; a group that is due a profile
## gets no plain upgrade card.
func _test_card_rules() -> void:
	var h := Hardpoint.new("test", 2, "aam")
	h.level = 2
	_check(Cards.profile_due(h), "group at lvl 2 is due")
	h.level = 1
	_check(not Cards.profile_due(h), "group at lvl 1 is not due")
	h.level = 2
	h.profile = "pair"
	_check(not Cards.profile_due(h), "group with a profile is not due")
	var c := Cards.profile_card(h, 0, "reach", 1)
	_check(c["kind"] == "profile" and c["profile"] == "reach" and c["group"] == 0 and c["weapon"] == "aam", "profile card fields")
	_check(String(c["title"]).contains("Дальний захват"), "profile card title names the profile")


## A weapon at the top level never gets the fork screen (the card would read «ур. 5 → 5»).
func _test_due_at_max() -> void:
	var h := Hardpoint.new("test", 2, "aam")
	h.level = Weapons.MAX_LEVEL
	_check(not Cards.profile_due(h), "max level: not due")
