extends Node
## Working part of plane_stats_test.gd. Works on an in-memory fresh profile (never saved).

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.001 * maxf(absf(b), 1.0)


func _ready() -> void:
	Profile.reset_data()
	TranslationServer.set_locale("ru")   # number texts with the decimal comma (CardText.dec)
	Profile.debug_plane = 0
	_check(Profile.meta_k() > 0.0, "meta progression is on (hangar bonuses count)")
	for c: String in PlaneClasses.LIST:
		# PT-04: tier 2 is the old plane 1, tier 3 the old plane 2 (its base step), tier 4 carries the heavy hardpoint
		var s1 := PlaneStats.compute(c, 2)
		var s2 := PlaneStats.compute(c, 3)
		var s4 := PlaneStats.compute(c, 4)
		_check(_near(float(s2["hull"]), float(s1["hull"]) * 1.15), "%s: tier 3 hull +15%%" % c)
		_check(_near(float(s2["speed"]), float(s1["speed"]) * 1.05), "%s: tier 3 speed +5%%" % c)
		_check(_near(float(s2["turn"]), float(s1["turn"]) * 1.05), "%s: tier 3 turn +5%%" % c)
		_check(int(s2["groups"]) == int(s1["groups"]), "%s: tier 3 has no heavy mount group any more" % c)
		_check(int(s4["groups"]) == int(s2["groups"]) + 1, "%s: tier 4 has the heavy mount group" % c)
		var t1 := PlaneStats.compute(c, 1)
		_check(_near(float(t1["hull"]), float(s1["hull"])) and _near(float(t1["speed"]), float(s1["speed"])),
			"%s: tier 1 is simpler, not weaker — hull and speed of tier 2" % c)
		_check(float(s1["gun_dps"]) > 0.0, "%s: course gun has damage per second" % c)
		for row: Array in PlaneStats.ROWS:
			_check(s1.has(row[0]) and s2.has(row[0]) and t1.has(row[0]), "%s: row %s present" % [c, row[0]])
		_check(Profile.debug_plane == 0, "%s: the flying plane override is restored" % c)
	# Kanta 06.11: damage per second of the starting kit and its air / ground factors, from each class's signature
	var f1 := PlaneStats.compute("fighter", 2)
	var a1 := PlaneStats.compute("attacker", 2)
	var b1 := PlaneStats.compute("bomber", 2)
	for s: Dictionary in [f1, a1, b1]:
		_check(float(s["dps"]) > float(s["gun_dps"]), "starting weapons add to the course gun's damage per second")
	_check(_near(float(f1["air_k"]), 1.0) and float(f1["ground_k"]) < 1.0, "fighter: air-to-air missiles count on planes only")
	_check(_near(float(a1["air_k"]), 1.0) and float(a1["ground_k"]) > 1.0, "attacker: NAR hit both, ground ×3")
	_check(float(b1["air_k"]) < 1.0 and float(b1["ground_k"]) > 1.0, "bomber: bombs reach ground only, ×2")
	# kit_dps on a hand-made kit: one group of 2 bombs and a course gun of 10 per second
	var p := Player.new()
	p.setup("bomber")
	p.groups.clear()
	var h := Hardpoint.new("test", 2, "bombs")
	p.groups.append(h)
	h.stats_owner = p
	var bomb := h.dmg() * Profile.wk("bombs", "dmg") * 2.0 / h.reload_time(p)
	var k := PlaneStats.kit_dps(p, 10.0)
	var all := float(p.mods.get("dmg_all", 1.0))
	_check(_near(float(k["dps"]), (10.0 + bomb) * all), "kit_dps sums gun and bombs per second")
	_check(_near(float(k["air_k"]), 10.0 / (10.0 + bomb)), "kit_dps: bombs add nothing on planes")
	_check(_near(float(k["ground_k"]), (10.0 + bomb * 2.0) * float(p.mods.get("ground_dmg", 1.0)) / (10.0 + bomb)), "kit_dps: bombs ×2 on ground")
	p.free()
	_check(PlaneStats.text(1.25, "x") == "×1,2" or PlaneStats.text(1.25, "x") == "×1,3", "factor text has a decimal comma")
	_check(PlaneStats.text(119.6, "n") == "120", "whole numbers are rounded")
	# hover preview of a node card: one level more on that node, the profile left as it was
	for t in range(1, PlaneTiers.MAX + 1):
		var nodes_before := str(Profile.nodes_of("fighter", t))
		for nid: String in PlaneTiers.nodes(t):
			var key := PlaneStats.row_of(t, nid)
			if key == "":
				_check(not PlaneTiers.node_live(t, nid) or PlaneTiers.fx(t, nid).keys().all(func(k): return not PlaneStats.FX_ROW.has(k)),
					"tier %d node %s: no row only while it is in work" % [t, nid])
				continue
			var now := float(PlaneStats.compute("fighter", t)[key])
			var nxt := float(PlaneStats.with_node("fighter", t, nid)[key])
			_check(nxt < now if key == "dodge" else nxt > now, "tier %d node %s moves row %s: %s → %s" % [t, nid, key, now, nxt])
		_check(str(Profile.nodes_of("fighter", t)) == nodes_before, "tier %d: with_node leaves the profile's nodes as they were" % t)
	_check(PlaneStats.title("bomber", "dodge", "x") == "Перезарядка ловушек", "the bomber's dodge row names the flare salvo")
	_check(PlaneStats.text(540.0, "min") == "9 мин" and PlaneStats.text(583.2, "min") == "9,7 мин", "fuel in minutes")
	# the «Броня» node of tier 2 raises tier 2's hull only (+5% per level)
	var base1 := float(PlaneStats.compute("fighter", 2)["hull"])
	var base2 := float(PlaneStats.compute("fighter", 3)["hull"])
	Profile.cls("fighter")["nodes_t2"]["armor"] = 2
	_check(_near(float(PlaneStats.compute("fighter", 2)["hull"]), base1 * (1.0 + 0.1 * Profile.meta_k())), "armor node lvl 2 on tier 2: hull +10%")
	_check(_near(float(PlaneStats.compute("fighter", 3)["hull"]), base2), "tier 2's armor node leaves tier 3 alone")
	# the cached call follows a profile change
	var cached := float(PlaneStats.of("fighter", 2)["hull"])
	Profile.cls("fighter")["nodes_t2"]["armor"] = 0
	_check(_near(float(PlaneStats.of("fighter", 2)["hull"]), base1) and not _near(cached, base1), "cache follows a node purchase")
	print("UNIT: plane_stats %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
