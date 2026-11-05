extends RefCounted
## Unit tests for `ArchBalance` (PG-11 part A): rank thresholds, the combat strip order, the card hint,
## the wingman limit of «Командир звена» III and the trade-off card rules with their floors.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_table()
	_test_ranks()
	_test_top()
	_test_hint()
	_test_wing()
	_test_trade_rules()
	_test_trade_stack()
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_table() -> void:
	for t: String in Prog.TAG_ORDER:
		_check(ArchBalance.DEFS.has(t), "archetype for tag %s" % t)
		var ranks: Array = ArchBalance.DEFS[t]["ranks"]
		_check(ranks.size() == ArchBalance.MAX_RANK, "%s has %d ranks" % [t, ArchBalance.MAX_RANK])
		for r: Dictionary in ranks:
			_check(String(r["short"]).length() <= 36, "%s short line fits the pause row: %s" % [t, r["short"]])
			_check(String(r["desc"]) != "", "%s rank text" % t)
	_check(ArchBalance.DEFS.size() == Prog.TAG_ORDER.size(), "no archetype without a tag")
	for t: String in Prog.TAG_ORDER:
		var at: Array = ArchBalance.at_of(t)
		_check(at.size() == ArchBalance.MAX_RANK and int(at[0]) < int(at[1]) and int(at[1]) < int(at[2]), "%s: three rising thresholds" % t)
	_check(ArchBalance.at_of("missiles")[2] > ArchBalance.at_of("kinetic")[2], "missiles fill fastest, so their ranks cost more")


func _test_ranks() -> void:
	# thresholds come from the table; the checks use a fake tag-free table so they do not pin the numbers
	var at := [4, 8, 12]
	_check(ArchBalance.rank_at(at, 0) == 0 and ArchBalance.rank_at(at, 3) == 0, "below the first threshold — no rank")
	_check(ArchBalance.rank_at(at, 4) == 1 and ArchBalance.rank_at(at, 7) == 1, "rank I band")
	_check(ArchBalance.rank_at(at, 8) == 2 and ArchBalance.rank_at(at, 12) == 3 and ArchBalance.rank_at(at, 40) == 3, "II, then III and beyond")
	_check(ArchBalance.next_at_of(at, 0) == 4 and ArchBalance.next_at_of(at, 4) == 8 and ArchBalance.next_at_of(at, 11) == 12, "next rank points")
	_check(ArchBalance.next_at_of(at, 12) == -1, "no next rank after III")
	_check(ArchBalance.crossed_at(at, 3, 9) == [1, 2], "an evolution (+2) can cross two ranks in one go")
	_check(ArchBalance.crossed_at(at, 8, 9).is_empty(), "no rank crossed inside a band")
	_check(ArchBalance.crossed_at(at, 11, 12) == [3], "rank III reached")
	var m: Array = ArchBalance.at_of("missiles")
	_check(ArchBalance.rank("missiles", int(m[1])) == 2 and ArchBalance.rank("missiles", int(m[1]) - 1) == 1, "per-tag rank uses the tag's table")
	_check(ArchBalance.ranks_crossed("missiles", int(m[2]) - 1, int(m[2])) == [3], "per-tag crossing")


func _test_top() -> void:
	var order := Prog.TAG_ORDER
	var tags := {"missiles": 9, "kinetic": 9, "armor": 2, "wing": 0, "blast": 5}
	# kinetic 9 has a rank (its first threshold is lower), missiles 9 not yet: rank first, then points, then the tag order
	_check(ArchBalance.top(tags, order, 3) == ["kinetic", "missiles", "blast"], "top 3 by rank, then points")
	_check(ArchBalance.top({"missiles": 3, "blast": 3}, order, 3) == ["missiles", "blast"], "ties keep the tag order")
	_check(ArchBalance.top({"armor": 1}, order, 3) == ["armor"], "only tags with points")
	_check(ArchBalance.top({}, order, 3).is_empty(), "nothing at the start")


func _test_hint() -> void:
	var at := [4, 8, 12]
	var h := ArchBalance.hint_at(at, 5, 1)
	_check(h["kind"] == "next" and int(h["rank"]) == 2 and int(h["at"]) == 8, "5 → 6: rank II at 8")
	h = ArchBalance.hint_at(at, 7, 1)
	_check(h["kind"] == "reach" and int(h["rank"]) == 2, "7 → 8 reaches rank II")
	h = ArchBalance.hint_at(at, 12, 1)
	_check(h["kind"] == "max", "past rank III: no next rank")
	h = ArchBalance.hint_at(at, 2, 2)
	_check(h["kind"] == "reach" and int(h["rank"]) == 1, "an evolution 2 → 4 reaches rank I")
	var k1 := int(ArchBalance.at_of("kinetic")[0])
	var m1 := int(ArchBalance.at_of("missiles")[0])
	_check(ArchBalance.hint_tag({"missiles": 0, "kinetic": k1 - 1}, ["missiles", "kinetic"], 1) == "kinetic", "the tag that reaches a rank wins")
	_check(ArchBalance.hint_tag({"missiles": m1 - 2, "kinetic": 0}, ["missiles", "kinetic"], 1) == "missiles", "else the closest to its next rank")
	_check(ArchBalance.hint_tag({"missiles": 999, "kinetic": 0}, ["missiles", "kinetic"], 1) == "kinetic", "a maxed tag goes last")
	_check(ArchBalance.hint_tag({}, [], 1) == "", "no tags — no hint")


func _test_wing() -> void:
	_check(ArchBalance.wing_limit(1, 2, 2) == 1, "rank II keeps the class limit")
	_check(ArchBalance.wing_limit(1, 2, 3) == 2, "rank III: +1 over the class limit")
	_check(ArchBalance.wing_limit(2, 2, 3) == 2, "never above WING_MAX")
	_check(ArchBalance.wing_full(2, 2) and not ArchBalance.wing_full(1, 2), "a full flight gets damage instead")


func _test_trade_rules() -> void:
	var floor_r := 0.6
	_check(not ArchBalance.trade_ok("trade_bare", 9, {}, 1.0, floor_r), "not before level 10")
	_check(ArchBalance.trade_ok("trade_bare", 10, {}, 1.0, floor_r), "from level 10")
	_check(not ArchBalance.trade_ok("trade_bare", 12, {"trade_bare": 1}, 1.0, floor_r), "each trade-off once")
	_check(not ArchBalance.trade_ok("trade_light", 12, {"trade_bare": 1, "trade_msl": 1}, 1.0, floor_r), "at most 2 per sortie")
	_check(ArchBalance.trade_ok("trade_light", 12, {"trade_bare": 1}, 1.0, floor_r), "a second one is fine")
	_check(not ArchBalance.trade_ok("trade_ammo", 12, {}, 0.6, floor_r), "«Двойной боезапас» not at the reload floor (its plus would be lost)")
	_check(not ArchBalance.trade_ok("nope", 20, {}, 1.0, floor_r), "unknown id")
	for id: String in ArchBalance.TRADES:
		var d: Dictionary = ArchBalance.TRADES[id]
		_check(String(d["plus"]) != "" and String(d["minus"]) != "", "%s has a plus and a minus" % id)


func _test_trade_stack() -> void:
	var floor_r := 0.6
	var base := {"dmg_all": 1.0, "heal_k": 1.0, "missile_dmg": 1.0, "gun_dmg": 1.0, "speed": 1.0, "turn": 1.0, "hp_cd": 0.7}
	var m := ArchBalance.trade_mods(base, "trade_ammo", floor_r)
	_check(is_equal_approx(float(m["hp_cd"]), floor_r), "reload never below the floor (0.7 × 0.8 → 0.6)")
	_check(is_equal_approx(float(base["hp_cd"]), 0.7), "the input is not changed")
	# three trade-offs at once (more than the cap allows, the stacking check of the plan): none useless, none broken
	var s := ArchBalance.trade_mods(base, "trade_bare", floor_r)
	s = ArchBalance.trade_mods(s, "trade_msl", floor_r)
	s = ArchBalance.trade_mods(s, "trade_light", floor_r)
	_check(is_equal_approx(float(s["dmg_all"]), 1.25) and is_equal_approx(float(s["missile_dmg"]), 1.4), "plusses stay")
	_check(float(s["gun_dmg"]) > 0.0 and float(s["heal_k"]) > 0.0, "minuses leave the gun and repair working")
	_check(is_equal_approx(float(s["hp"]), 0.8) and 0.8 >= ArchBalance.HP_FLOOR, "hull −20%, above the HP floor")
	_check(is_equal_approx(float(s["speed"]), 1.15), "speed plus")
	var all4 := ArchBalance.trade_mods(s, "trade_ammo", floor_r)
	_check(float(all4["speed"]) > 1.0, "light airframe + double ammo still faster than the base (1.15 × 0.88)")
