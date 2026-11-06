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
		var s1 := PlaneStats.compute(c, 1)
		var s2 := PlaneStats.compute(c, 2)
		_check(_near(float(s2["hull"]), float(s1["hull"]) * 1.15), "%s: plane 2 hull +15%%" % c)
		_check(_near(float(s2["speed"]), float(s1["speed"]) * 1.05), "%s: plane 2 speed +5%%" % c)
		_check(_near(float(s2["turn"]), float(s1["turn"]) * 1.05), "%s: plane 2 turn +5%%" % c)
		_check(int(s2["groups"]) == int(s1["groups"]) + 1, "%s: plane 2 has the heavy mount group" % c)
		_check(float(s1["gun_dps"]) > 0.0, "%s: course gun has damage per second" % c)
		for row: Array in PlaneStats.ROWS:
			_check(s1.has(row[0]) and s2.has(row[0]), "%s: row %s present" % [c, row[0]])
		_check(Profile.debug_plane == 0, "%s: the flying plane override is restored" % c)
	# Kanta 06.11: damage per second of the starting kit and its air / ground factors, from each class's signature
	var f1 := PlaneStats.compute("fighter", 1)
	var a1 := PlaneStats.compute("attacker", 1)
	var b1 := PlaneStats.compute("bomber", 1)
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
	var nodes_before := str(Profile.nodes_of("fighter", 1))
	for nid: String in PlaneStats.NODE_ROW:
		var key := String(PlaneStats.NODE_ROW[nid])
		var now := float(PlaneStats.compute("fighter", 1)[key])
		var nxt := float(PlaneStats.with_node("fighter", 1, nid)[key])
		_check(nxt < now if key == "dodge" else nxt > now, "node %s moves row %s: %s → %s" % [nid, key, now, nxt])
	_check(str(Profile.nodes_of("fighter", 1)) == nodes_before, "with_node leaves the profile's nodes as they were")
	_check(PlaneStats.title("bomber", "dodge", "x") == "Перезарядка ловушек", "the bomber's dodge row names the flare salvo")
	_check(PlaneStats.text(540.0, "min") == "9 мин" and PlaneStats.text(583.2, "min") == "9,7 мин", "fuel in minutes")
	# the «Броня» node of plane 1 raises plane 1's hull only (+5% per level)
	var base1 := float(PlaneStats.compute("fighter", 1)["hull"])
	var base2 := float(PlaneStats.compute("fighter", 2)["hull"])
	Profile.cls("fighter")["nodes"]["armor"] = 2
	_check(_near(float(PlaneStats.compute("fighter", 1)["hull"]), base1 * (1.0 + 0.1 * Profile.meta_k())), "armor node lvl 2 on plane 1: hull +10%")
	_check(_near(float(PlaneStats.compute("fighter", 2)["hull"]), base2), "plane 1's armor node leaves plane 2 alone")
	# the cached call follows a profile change
	var cached := float(PlaneStats.of("fighter", 1)["hull"])
	Profile.cls("fighter")["nodes"]["armor"] = 0
	_check(_near(float(PlaneStats.of("fighter", 1)["hull"]), base1) and not _near(cached, base1), "cache follows a node purchase")
	print("UNIT: plane_stats %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
