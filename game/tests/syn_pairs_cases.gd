extends RefCounted
## Synergies from two different things (PG-11 B1): every recipe has two different things, slot costs grow,
## a card advances only an unmet thing, and every class (plane 1 and 2) can reach at least 4 weapon synergies.
## Loaded by `syn_pairs_test.gd` after the first frame.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_recipes()
	_test_state()
	_test_advances()
	_test_classes()
	_test_closes()
	_test_first()
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_recipes() -> void:
	for id in Cards.SYNERGIES:
		if id == "gunner":
			_check(SynPairs.req(id).is_empty(), "«Пушкарь» (gun pod, out of the game) has no recipe")
			continue
		var r := SynPairs.req(id)
		_check(r.size() == 2, "%s: two things (got %d)" % [id, r.size()])
		if r.size() == 2:
			_check(str(r[0]) != str(r[1]), "%s: the two things differ" % id)
			if r[0].has("w") and r[1].has("w"):
				var shared := (r[0]["w"] as Array).filter(func(w): return (r[1]["w"] as Array).has(w))
				_check(shared.is_empty(), "%s: no weapon fills both things" % id)
	for id in SynPairs.REQ:
		_check(Cards.SYNERGIES.has(id), "recipe %s has a synergy definition" % id)
	for sk in PlaneClasses.SKILL3:
		var sid: String = PlaneClasses.SKILL3[sk]["syn"]["id"]
		_check(SynPairs.req(sid).size() == 2 and SynPairs.req(sid)[0].has("skill"), "%s: skill plus one thing" % sid)
	for i in SynPairs.COST.size() - 1:
		_check(int(SynPairs.COST[i + 1]["lvl"]) >= int(SynPairs.COST[i]["lvl"]) and int(SynPairs.COST[i + 1]["mods"]) > int(SynPairs.COST[i]["mods"]), "slot %d costs no less than slot %d" % [i + 2, i + 1])


func _test_state() -> void:
	var snap := {"w": {"aam": 4, "flares": 2}, "taken": {"gun_dmg": 1, "gun_rate": 1}, "wing": 0, "s3": 1}
	_check(not SynPairs.is_ready("carousel", snap, 0), "aam 4 + flares 2: «Карусель» not ready for slot 1 (flares < 3)")
	snap["w"]["flares"] = 3
	_check(SynPairs.is_ready("carousel", snap, 0), "aam 4 + flares 3: ready for slot 1")
	_check(not SynPairs.is_ready("carousel", snap, 1), "aam 4 + flares 3: not ready for slot 2 (needs 4)")
	_check(SynPairs.is_ready("thermobaric", {"w": {"rockets": 3}, "taken": {"gun_dmg": 2}}, 0), "rockets 3 + two gun cards: «Термобарика»")
	_check(SynPairs.have({"mods": SynPairs.GUN_MODS}, {"taken": {"gun_dmg": 1, "gun_rate": 2}}) == 3, "gun modules add up")
	_check(not SynPairs.is_ready("gunner", snap, 0), "a synergy with no recipe is never ready")
	_check(SynPairs.state("wolfpack", {"wing": 1}, 2)[0][2] == 1, "wingmen asked stay at 1 on slot 3")
	_check(SynPairs.cost(9) == SynPairs.COST[-1], "past the last slot — the last row")
	_check(SynPairs.two_weapons("carousel") and not SynPairs.two_weapons("thermobaric"), "two-weapon recipes are told apart")


func _test_advances() -> void:
	var snap := {"w": {"aam": 3, "flares": 1}, "taken": {}, "wing": 0, "s3": 0}
	_check(SynPairs.advances("carousel", {"weapon": "flares"}, snap, 0), "flares card advances «Карусель» (flares 1/3)")
	_check(not SynPairs.advances("carousel", {"weapon": "aam"}, snap, 0), "aam card does not: aam is already 3/3")
	_check(not SynPairs.advances("carousel", {"mod": "reload"}, snap, 0), "a missile module does not advance «Карусель»")
	_check(SynPairs.advances("wolfpack", {"wing": true}, snap, 0), "a new wingman advances «Волчья стая»")
	_check(SynPairs.advances("s_wheel", {"skill": true}, snap, 0), "the skill card advances its skill synergy")
	_check(SynPairs.advances("ironclad", {"mod": "gun_rate"}, snap, 0), "a gun card advances «Броневой бой»")


func _test_classes() -> void:
	# every plane tier (PT-04). Tier 1 is the simpler start plane with fewer weapon kinds (Kanta 06.11): «Оса» 1
	# (aam, rockets, flares) has one two-weapon recipe («Карусель»), so tier 1 needs one, the other tiers two
	for c in PlaneClasses.LIST:
		for lv in range(1, PlaneTiers.MAX + 1):
			var pd: Dictionary = PlaneClasses.PLANES[c][lv]
			var ids := SynPairs.reachable_ids(pd["weapons"], int(pd["wingmen"]))
			_check(ids.size() >= 4, "%s tier %d: at least 4 reachable synergies (got %d: %s)" % [c, lv, ids.size(), str(ids)])
			var mixed := ids.filter(func(id): return SynPairs.two_weapons(id))
			var need := 1 if lv == 1 else 2
			_check(mixed.size() >= need, "%s tier %d: at least %d two-weapon synergies (got %s)" % [c, lv, need, str(mixed)])


func _test_closes() -> void:
	# flights review 06.11, item 1.4: a new weapon on the last free mount must not hide that the recipe is lost
	_check(SynPairs.weapons_missing("carousel", ["aam"]).size() == 1, "aam only: «Карусель» still misses flares")
	_check(SynPairs.weapons_missing("carousel", ["aam", "flares"]).is_empty(), "aam + flares: nothing missing")
	_check(SynPairs.weapons_missing("carousel", ["aam", "rockets"]).size() == 1, "aam + rockets: flares still missing")
	_check(SynPairs.weapons_missing("thermobaric", ["rockets"]).is_empty(), "«Термобарика»: modules do not count as a missing weapon")
	_check(SynPairs.closes("carousel", ["aam"], "rockets", 0), "rockets on the last mount close «Карусель»")
	_check(not SynPairs.closes("carousel", ["aam"], "rockets", 1), "one mount left after rockets: «Карусель» stays open")
	_check(not SynPairs.closes("carousel", ["aam"], "flares", 0), "flares on the last mount complete the recipe")
	_check(not SynPairs.closes("gunner", ["aam"], "rockets", 0), "a synergy with no recipe is never reported")


## PG-14: steps left to a recipe, the nearest recipe, and the weight factor of the first synergy
func _test_first() -> void:
	var snap := {"w": {"aam": 2, "flares": 1}, "taken": {"gun_dmg": 1}, "wing": 0, "s3": 0}
	_check(SynPairs.steps_left("carousel", snap, 0) == 3, "aam 2/3 + flares 1/3: 3 steps to «Карусель»")
	_check(SynPairs.steps_left("mirror", snap, 0) == 3, "flares 1/3 + gun 1/2: 3 steps to «Зеркало»")
	_check(SynPairs.steps_left("corridor", snap, 0) == 6, "no rockets, no bombs: 6 steps to «Огненный коридор»")
	_check(SynPairs.steps_left("gunner", snap, 0) < 0, "a synergy with no recipe has no steps (−1)")
	snap["w"]["flares"] = 3
	snap["w"]["aam"] = 3
	_check(SynPairs.steps_left("carousel", snap, 0) == 0, "a ready recipe has 0 steps")
	snap["w"] = {"aam": 2, "flares": 1}
	_check(SynPairs.nearest(["corridor", "carousel", "mirror"], snap, 0) == "carousel", "nearest: the first of the equal ones in list order")
	_check(SynPairs.nearest(["corridor", "mirror"], snap, 0) == "mirror", "nearest: fewer steps wins")
	_check(SynPairs.nearest(["gunner"], snap, 0) == "", "nearest: no recipe — none")
	_check(SynPairs.nearest([], snap, 0) == "", "nearest: empty list — none")
	_check(is_equal_approx(SynPairs.first_k(0, 3.0), 3.0), "no synergy yet: the first-synergy factor applies")
	_check(is_equal_approx(SynPairs.first_k(1, 3.0), 1.0), "after the first synergy: factor 1")
	_check(is_equal_approx(SynPairs.first_k(0, 0.5), 1.0), "a factor below 1 never lowers weights")
