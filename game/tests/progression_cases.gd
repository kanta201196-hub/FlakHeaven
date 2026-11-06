extends RefCounted
## Unit tests for the deeper upgrades of stage 1 (PG-01): class weapon lists, level scaling of the
## new weapons, course gun variants and ammo types, the third hardpoint group and the profile keys behind them.
## Same style as `run_state_test.gd`: each check prints FAIL with a message, exit code 1 on failure.
## The profile is a fresh instance writing to a test file, so a player's real profile is never touched.
## Loaded by `progression_test.gd` after the first frame: game scripts use autoloads (`Tuning`,
## `Profile`), which do not exist yet when a `-s` script is compiled.

const TEST_PATH := "user://test_profile_pg01.json"

var _failed := 0
var _checks := 0
var _profile_script: GDScript = load("res://scripts/profile.gd")


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_class_lists()
	_test_pool_and_bombs()
	_test_level_scaling()
	_test_gun_variants()
	_test_ammo_types()
	_test_group_defs()
	_test_defence_classes()
	_test_profile_guns()
	_test_profile_ammo()
	_test_profile_third_group()
	_test_profile_round_trip()
	_test_profile_tiers()
	_test_profile_tier_migration()
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


## Kanta 24.10: weapon sets, class bonus, turrets and wingmen are per plane (class + tier; tiers 2 and 3 are the old
## planes 1 and 2, PT-04).
func _test_class_lists() -> void:
	var f1 := ["aam", "agm", "rockets", "flares"]
	var a1 := ["rockets", "aam", "agm", "bombs", "turret", "flares"]
	var b1 := ["bombs", "hebomb", "rockets", "turret", "flares"]
	var want := {"fighter": [f1, f1 + ["srm"]], "attacker": [a1, a1], "bomber": [b1, b1]}
	for c in want:
		for lv in [2, 3]:   # PT-04: tier 2 is the old plane 1, tier 3 the old plane 2
			var got: Array = PlaneClasses.plane(c, lv)["weapons"]
			var need: Array = want[c][lv - 2]
			_check(got.size() == need.size() and need.all(func(w): return got.has(w)), "%s %d: weapon set" % [c, lv])
			for w in Weapons.POOL:
				_check(PlaneClasses.allows(c, w, lv) == need.has(w), "%s %d allows %s" % [c, lv, w])
	_check(not PlaneClasses.allows("fighter", "srm", 2) and PlaneClasses.allows("fighter", "srm", 3), "srm unique to fighter 2")
	_check(not PlaneClasses.allows("bomber", "agm", 2), "bomber: no agm")
	# class bonus 15 % on plane 1, 20 % on plane 2; fighter 2 also +5 % on agm (test with and without)
	_check(is_equal_approx(PlaneClasses.bonus_k("fighter", 2, "aam"), 1.15), "fighter 1 aam +15%")
	_check(is_equal_approx(PlaneClasses.bonus_k("fighter", 3, "aam"), 1.2), "fighter 2 aam +20%")
	_check(is_equal_approx(PlaneClasses.bonus_k("fighter", 3, "agm"), 1.05), "fighter 2 agm +5%")
	_check(is_equal_approx(PlaneClasses.bonus_k("fighter", 2, "agm"), 1.0), "fighter 1 agm no bonus")
	_check(is_equal_approx(PlaneClasses.bonus_k("attacker", 2, "rockets"), 1.15) and is_equal_approx(PlaneClasses.bonus_k("attacker", 3, "rockets"), 1.2), "attacker rockets 15/20")
	_check(is_equal_approx(PlaneClasses.bonus_k("bomber", 2, "bombs"), 1.15) and is_equal_approx(PlaneClasses.bonus_k("bomber", 3, "bombs"), 1.2), "bomber bombs 15/20")
	# turrets: start 1, +1 at turret lvl 3 and lvl 5, up to the plane's max
	_check(PlaneClasses.turret_slots("attacker", 5, 2) == 1 and PlaneClasses.turret_slots("attacker", 3, 3) == 2, "attacker turrets 1 / 2")
	_check(PlaneClasses.turret_slots("attacker", 2, 3) == 1, "attacker 2: second turret from lvl 3")
	_check(PlaneClasses.turret_slots("bomber", 2, 2) == 1 and PlaneClasses.turret_slots("bomber", 3, 2) == 2 and PlaneClasses.turret_slots("bomber", 5, 2) == 2, "bomber 1 turrets up to 2")
	_check(PlaneClasses.turret_slots("bomber", 3, 3) == 2 and PlaneClasses.turret_slots("bomber", 5, 3) == 3, "bomber 2 turrets up to 3")
	# wingmen: count and types
	_check(PlaneClasses.plane("fighter", 2)["wingmen"] == 1 and PlaneClasses.wing_type_ok("fighter", 2, "swift") and not PlaneClasses.wing_type_ok("fighter", 2, "rook"), "fighter 1: 1 fighter wingman")
	_check(PlaneClasses.wing_type_ok("fighter", 3, "rook"), "fighter 2: fighter or attacker")
	_check(PlaneClasses.plane("attacker", 2)["wingmen"] == 1 and PlaneClasses.plane("attacker", 3)["wingmen"] == 1, "attacker: 1 wingman")
	_check(PlaneClasses.plane("bomber", 3)["wingmen"] == 2 and not PlaneClasses.wing_type_ok("bomber", 3, "rook"), "bomber: 2 fighters only")
	# PT-04 tier 1: simpler — fewer weapon kinds, «Грач» without a turret, «Кит» with one wingman
	_check(PlaneClasses.plane("fighter", 1)["weapons"] == ["aam", "rockets", "flares"], "fighter 1: aam, rockets, flares")
	_check(PlaneClasses.turret_slots("attacker", 5, 1) == 0 and PlaneClasses.turrets_start("attacker", 1) == 0, "attacker 1: no turret")
	_check(not PlaneClasses.allows("attacker", "turret", 1), "attacker 1: no turret cards")
	_check(PlaneClasses.plane("bomber", 1)["wingmen"] == 1 and PlaneClasses.turret_slots("bomber", 5, 1) == 2, "bomber 1: one wingman, turrets up to 2")
	for c in PlaneClasses.LIST:
		_check(PlaneClasses.allows(c, PlaneClasses.signature(c), 1), "%s 1 carries its signature" % c)
		_check(is_equal_approx(PlaneClasses.bonus_k(c, 5, PlaneClasses.signature(c)), 1.25), "%s 5: ★ +25%%" % c)
	for c in PlaneClasses.LIST:
		_check(PlaneClasses.signature(c) in ["aam", "rockets", "bombs"], "signature unchanged for %s" % c)


func _test_pool_and_bombs() -> void:
	for w in ["srm", "agm", "hebomb"]:
		_check(Weapons.POOL.has(w), "%s in the card pool" % w)
		_check(Weapons.DEFS.has(w) and not Weapons.DEFS[w].get("exp", false), "%s is standard, not experimental" % w)
		_check(Weapons.in_game(w), "%s is in the game" % w)
		_check(Prog.WEAPON_TAGS.has(w), "%s has course tags" % w)
	_check(Weapons.is_bomb("bombs") and Weapons.is_bomb("hebomb"), "bomb family")
	_check(not Weapons.is_bomb("agm") and not Weapons.is_bomb("plasma"), "not bombs")
	_check(Weapons.DEFS["hebomb"].get("uses_trigger", false), "HE bomb has the manual trigger")


## Level 2–5 factors and reload floors (spec table).
func _test_level_scaling() -> void:
	_check(is_equal_approx(WeaponBalance.dmg_k("srm", 1), 1.0), "srm dmg lvl 1")
	_check(is_equal_approx(WeaponBalance.dmg_k("srm", 3), 1.5), "srm dmg lvl 3")
	_check(is_equal_approx(WeaponBalance.cd_k("srm", 5), 1.0 - 0.08 * 4), "srm cd lvl 5")
	_check(is_equal_approx(WeaponBalance.cd_k("agm", 5), 1.0 - 0.06 * 4), "agm cd lvl 5")
	_check(is_equal_approx(WeaponBalance.range_k("hebomb", 2), 1.08), "hebomb radius lvl 2")
	_check(is_equal_approx(WeaponBalance.cd_k("hebomb", 4), 1.0), "hebomb cd does not scale")
	_check(is_equal_approx(WeaponBalance.range_k("srm", 5), 1.0), "srm range does not scale")
	_check(is_equal_approx(WeaponBalance.cd_floor("srm"), 2.0) and is_equal_approx(WeaponBalance.cd_floor("agm"), 3.5), "reload floors")
	_check(WeaponBalance.cd_floor("hebomb") == 0.0, "no floor for the HE bomb")


func _test_gun_variants() -> void:
	var std := WeaponBalance.gun_k("std")
	var twin := WeaponBalance.gun_k("twin")
	var heavy := WeaponBalance.gun_k("heavy")
	_check(is_equal_approx(std["rate"], 1.0) and is_equal_approx(std["dmg"], 1.0), "std neutral")
	_check(is_equal_approx(twin["rate"], 1.6) and is_equal_approx(twin["dmg"], 0.65), "twin rate and damage")
	_check(is_equal_approx(heavy["rate"], 0.55) and is_equal_approx(heavy["dmg"], 2.0) and is_equal_approx(heavy["speed"], 1.15), "heavy")
	_check(WeaponBalance.gun_k("nope") == std, "unknown gun → std")
	_check(WeaponBalance.GUN_PRICE["std"] == 0 and WeaponBalance.GUN_PRICE["heavy"] > WeaponBalance.GUN_PRICE["twin"], "prices")
	# DPS stays close to the standard gun (choice by feel, not by power): within ±15 %
	for g in [twin, heavy]:
		_check(absf(g["rate"] * g["dmg"] - 1.0) <= 0.15, "gun DPS near standard")


## The third group is appended after everything else: old indices never shift.
## Ammo types (Kanta 24.10, numbers are his first guess): AP — single target, HE — groups, incendiary — bosses.
func _test_ammo_types() -> void:
	var ap := WeaponBalance.ammo_k("ap")
	var he := WeaponBalance.ammo_k("he")
	var inc := WeaponBalance.ammo_k("inc")
	_check(WeaponBalance.ammo_k("nope") == WeaponBalance.ammo_k("std"), "unknown ammo → std")
	_check(is_equal_approx(ap["dmg"], 0.75) and is_equal_approx(ap["speed"], 1.0) and ap["ap"], "AP numbers")
	_check(is_equal_approx(he["dmg"], 1.0) and is_equal_approx(he["speed"], 0.75) and float(he["splash_r"]) > 0.0, "HE numbers")
	_check(is_equal_approx(inc["dmg"], 0.85) and is_equal_approx(inc["speed"], 0.8) and float(inc["burn"]) > 0.0, "incendiary numbers")
	_check(WeaponBalance.AMMO_ORDER == ["std", "ap", "he", "inc"] and WeaponBalance.AMMO_PRICE["std"] == 0, "ammo list")
	# burn: one stack per hit up to the cap, damage per second grows with stacks, time refreshes
	var b := {}
	for i in 8:
		b = WeaponBalance.burn_add(b, 10.0)
	_check(int(b["n"]) == WeaponBalance.BURN_STACKS, "burn stacks are capped")
	_check(is_equal_approx(float(b["dps"]), 10.0 * float(inc["burn"]) / WeaponBalance.BURN_TIME * WeaponBalance.BURN_STACKS), "burn dps at cap")
	_check(is_equal_approx(float(b["t"]), WeaponBalance.BURN_TIME), "burn time refreshed")


func _test_group_defs() -> void:
	for c in PlaneClasses.LIST:
		var base: Array = PlaneClasses.group_defs(c, false)
		var more: Array = PlaneClasses.group_defs(c, true)
		_check(base == PlaneClasses.get_data(c)["groups"], "%s: no third group without unlock" % c)
		_check(more.size() == base.size() + 1 and more.slice(0, base.size()) == base, "%s: third group appended" % c)
		_check(String(more[-1]["weapon"]) == "" and int(more[-1]["slots"]) >= 1, "%s: third group starts empty" % c)


func _test_defence_classes() -> void:
	_check(Enemy.src_class("УР В-З") == "ap", "guided missile is armor-piercing")
	_check(Enemy.course_class("gun", "курсовое (авто)", true) == "gun_ap", "armor-piercing ammo class")
	_check(Enemy.course_class("gun", "курсовое (ручн.)", false) == "gun", "standard ammo unchanged")
	_check(Enemy.course_class("gun", "турели", true) == "gun", "turrets are not the course gun")
	_check(Enemy.src_class("горение") == "", "burning ignores defences")
	_check(Enemy.src_class("курсовое (авто)") == "gun", "course gun source class")
	_check(Enemy.src_class("ракеты ближнего боя") == "homing", "short-range missile is homing")
	_check(Enemy.src_class("фугасные бомбы") == "blast", "HE bomb is blast")
	_check(is_equal_approx(Enemy.DEF_K["armor"]["ap"], 1.3) and is_equal_approx(Enemy.DEF_K["armor"]["gun_ap"], 1.0), "armor factors")
	_check(is_equal_approx(Enemy.DEF_K["agile"]["gun_ap"], 1.15), "agile vs armor-piercing ammo")


func _test_profile_guns() -> void:
	var p := _fresh_profile()
	_check(p.gun("fighter") == "std" and p.guns("fighter") == ["std"], "defaults")
	p.set_gun("fighter", "twin")
	_check(p.gun("fighter") == "std", "unowned gun cannot be selected")
	p.data["parts"] = WeaponBalance.GUN_PRICE["twin"] - 1
	_check(not p.buy_gun("fighter", "twin") and p.parts() == WeaponBalance.GUN_PRICE["twin"] - 1, "not enough parts")
	p.data["parts"] = WeaponBalance.GUN_PRICE["twin"] + 10
	_check(p.buy_gun("fighter", "twin") and p.parts() == 10, "bought for the price")
	_check(p.guns("fighter").has("twin") and p.gun("fighter") == "twin", "bought gun is owned and selected")
	_check(not p.buy_gun("fighter", "twin"), "cannot buy twice")
	p.set_gun("fighter", "std")
	_check(p.gun("fighter") == "std", "switch back is free")
	_check(p.gun("bomber") == "std", "other classes keep their own guns")
	_check(p.gun("fighter", 2) == "std" and p.guns("fighter", 2) == ["std"], "plane lvl 2 buys its own guns (Kanta 24.10)")
	p.data["parts"] = WeaponBalance.GUN_PRICE["heavy"]
	_check(p.buy_gun("fighter", "heavy", 2) and p.gun("fighter", 2) == "heavy", "buy for plane lvl 2")
	_check(not p.guns("fighter", 1).has("heavy"), "plane lvl 1 does not get it")
	p.free()


## PG-01 (Kanta 24.10): ammo of the course gun, bought per plane like the guns.
func _test_profile_ammo() -> void:
	var p := _fresh_profile()
	_check(p.ammo("attacker") == "std" and p.ammos("attacker") == ["std"], "ammo defaults")
	p.set_ammo("attacker", "he")
	_check(p.ammo("attacker") == "std", "unowned ammo cannot be selected")
	p.data["parts"] = WeaponBalance.AMMO_PRICE["he"] - 1
	_check(not p.buy_ammo("attacker", "he"), "not enough parts for ammo")
	p.data["parts"] = WeaponBalance.AMMO_PRICE["he"]
	_check(p.buy_ammo("attacker", "he") and p.parts() == 0 and p.ammo("attacker") == "he", "ammo bought and selected")
	_check(p.ammo("attacker", 2) == "std", "ammo is per plane")
	_check(not p.buy_ammo("attacker", "nope"), "unknown ammo")
	p.free()


func _test_profile_third_group() -> void:
	var p := _fresh_profile()
	_check(not p.third_group("attacker", 1), "no third group at pylons 0")
	p.cls("attacker")["nodes_t1"]["pylons"] = 1
	_check(not p.third_group("attacker", 1), "no third group at pylons 1")
	p.cls("attacker")["nodes_t1"]["pylons"] = 2
	_check(p.third_group("attacker", 1), "third group at pylons 2")
	_check(not p.third_group("attacker", 2), "tier 2 has its own nodes")
	p.free()


## New keys survive save → load; an old save without them loads with defaults.
func _test_profile_round_trip() -> void:
	var p := _fresh_profile()
	p.data["parts"] = 1000
	p.buy_gun("bomber", "heavy")
	p.buy_ammo("bomber", "inc")
	p.save()
	var q := _fresh_profile()
	q.load_profile()
	_check(q.gun("bomber") == "heavy" and q.guns("bomber").has("heavy"), "gun survives save/load")
	_check(q.ammo("bomber") == "inc", "ammo survives save/load")
	var old: Dictionary = q.data.duplicate(true)
	for c in old["classes"]:
		for t in range(1, PlaneTiers.MAX + 1):
			old["classes"][c].erase("kit_t%d" % t)
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var r := _fresh_profile()
	r.load_profile()
	_check(r.gun("bomber") == "std" and r.guns("bomber") == ["std"] and r.ammo("bomber") == "std", "old save → defaults")
	for x in [p, q, r]:
		x.free()


## PT-04: a fresh profile owns tier 1 only; tier 2 is sold after «Перевал» with crew and parts; nodes are per tier
func _test_profile_tiers() -> void:
	var p := _fresh_profile()
	_check(p.tiers_owned("fighter") == [1] and p.tier("fighter") == 1, "fresh profile: tier 1 owned and flown")
	_check(p.plane_lvl("fighter") == PlaneTiers.model(1), "plane_lvl is the model generation of the tier")
	p.set_plane("fighter", 2)
	_check(p.tier("fighter") == 1, "an unowned tier cannot be selected")
	p.cls("fighter")["tiers"] = [1, 2]
	p.set_plane("fighter", 2)
	_check(p.tier("fighter") == 2, "an owned tier is selected")
	p.cls("fighter")["nodes_t2"]["armor"] = 3
	_check(p.node("fighter", "armor", 2) == 3 and p.node("fighter", "armor", 1) == 0, "nodes are per tier")
	p.cls("fighter")["nodes_t1"]["armor"] = 9
	_check(p.node("fighter", "armor", 1) == PlaneTiers.cap(1), "a node level is capped by its tier")
	_check(not p.can_buy_node("fighter", "wing", 1), "tier 1 has no wing node")
	p.data["parts"] = 999999
	_check(not p.can_buy_node("fighter", "armor", 3), "no node purchase on an unowned tier")
	_check(p.extra_rerolls("fighter") == 0, "no extra reroll below tier 3")
	p.free()


## PT-04: a version-1 save with plane 2 bought loads as tiers 1–3, flies tier 3, nodes and kits moved
func _test_profile_tier_migration() -> void:
	var p := _fresh_profile()
	var old: Dictionary = {"version": 1, "parts": 5, "classes": {"bomber": {"crew_xp": 0, "plane2": true, "plane_sel": 2,
		"nodes": {"frame": 2, "engine": 0, "armor": 4, "wing": 0, "pylons": 0, "tank": 1},
		"nodes2": {"frame": 0, "engine": 0, "armor": 1, "wing": 0, "pylons": 2, "tank": 0},
		"kit1": {"gun": "std", "guns": ["std"], "ammo": "std", "ammos": ["std"]},
		"kit2": {"gun": "heavy", "guns": ["std", "heavy"], "ammo": "std", "ammos": ["std"]}}}}
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	p.load_profile()
	_check(p.tiers_owned("bomber") == [1, 2, 3], "old plane 2 owner owns tiers 1–3")
	_check(p.tier("bomber") == 3, "flew old plane 2 → flies tier 3")
	_check(p.node("bomber", "armor", 2) == 4 and p.node("bomber", "tank", 2) == 1, "old plane 1 nodes → tier 2")
	_check(p.node("bomber", "pylons", 3) == 2 and p.third_group("bomber", 3), "old plane 2 nodes → tier 3")
	_check(p.gun("bomber", 3) == "heavy" and p.gun("bomber", 2) == "std", "kits move with their plane")
	_check(p.tiers_owned("fighter") == [1], "a class missing from the save starts fresh")
	_check(int(p.data["version"]) == 2, "the profile is version 2 now")
	_check(p.extra_rerolls("bomber") == 1, "tier 3 keeps the old plane 2 extra reroll")
	p.free()
