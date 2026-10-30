extends SceneTree
## Unit tests for `MedalBalance` (Kanta 2026-10-27, medals with small bonuses). Rules pinned here: tiers come from
## lifetime counters and stop at the first threshold not reached; «all of the set» thresholds need the full set;
## a tier's bonus is that tier's value, not a sum; each kind of bonus is capped over all medals together; best-sortie
## medals keep the best sortie, the rest sum; the minute window counts kills inside any 60 s.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_tier()
	_test_bonuses()
	_test_caps()
	_test_add_run()
	_test_helpers()
	_test_data()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_tier() -> void:
	var th := [1000, 10000, 50000]
	_check(MedalBalance.tier(999, th) == 0, "below the first threshold: no tier")
	_check(MedalBalance.tier(1000, th) == 1, "first threshold reached: tier 1")
	_check(MedalBalance.tier(60000, th) == 3, "past the last threshold: top tier")
	_check(MedalBalance.tier(30, [-1], 31) == 0 and MedalBalance.tier(31, [-1], 31) == 1, "«all of the set» needs the whole set")
	_check(MedalBalance.tier(5, [5, -1], 0) == 1, "a set of unknown size never completes the «all» tier")


func _test_bonuses() -> void:
	var b := MedalBalance.bonuses({"fighter": 3, "scrap": 1})
	_check(is_equal_approx(float(b["dmg"]), 0.03), "«Истребитель» tier 3 is +3 %, not 1+2+3")
	_check(is_equal_approx(float(b["parts"]), 0.02), "«Сборщик мусора» tier 1 is +2 % parts")
	var d := MedalBalance.bonuses({"demolition": 2})
	_check(is_equal_approx(float(d["blast"]), 0.06) and is_equal_approx(float(d["blast_dmg"]), 0.04), "«Подрывник» gives radius and damage")
	_check(MedalBalance.bonuses({"ram": 1}).is_empty(), "picture-only medals give nothing")


func _test_caps() -> void:
	# every damage medal at its top tier: 4 + 10 + 6 + 10 + 10 + 10 + 9 % — far over the 10 % cap
	var all := {}
	for m: Dictionary in MedalBalance.LIST:
		all[m["id"]] = (m["t"] as Array).size()
	var b := MedalBalance.bonuses(all)
	var dmg := 0.0
	for k in b:
		if MedalBalance.CAP_OF.get(k, "") == "dmg":
			dmg += float(b[k])
	_check(dmg <= 0.1 + 1e-6, "all damage bonuses together stay within +10 %% (got %.3f)" % dmg)
	var hp := float(b.get("hp", 0.0)) + float(b.get("attacker_hp", 0.0))
	_check(hp <= 0.1 + 1e-6, "HP bonuses together stay within +10 %")
	_check(float(b.get("parts", 0.0)) <= 0.1 + 1e-6, "parts bonus within +10 %")


func _test_add_run() -> void:
	var c := {"kills": 100, "ram_drones": 40}
	MedalBalance.add_run(c, {"kills": 50, "ram_drones": 30})
	_check(int(c["kills"]) == 150, "sums add up")
	_check(int(c["ram_drones"]) == 40, "best-sortie counters keep the best sortie")
	MedalBalance.add_run(c, {"ram_drones": 120})
	_check(int(c["ram_drones"]) == 120, "a better sortie replaces the best")
	var t0 := MedalBalance.tiers({"kills": 900})
	var t1 := MedalBalance.tiers({"kills": 1200})
	var nt := MedalBalance.new_tiers(t0, t1)
	_check(nt.size() == 1 and nt[0][0] == "fighter" and int(nt[0][1]) == 1, "new tiers list the medal that went up")


func _test_helpers() -> void:
	_check(MedalBalance.best_minute([0.0, 10.0, 59.0, 61.0, 62.0, 200.0]) == 4, "60 s window: 10, 59, 61, 62")
	_check(MedalBalance.best_minute([]) == 0, "no kills: 0")
	_check(MedalBalance.blast_of({"бомбы": 100.0, "НАР": 50.5, "курсовое (ручн.)": 999.0}) == 150, "explosions only")
	_check(MedalBalance.tally({"aces": 2, "fortresses": 1, "warships": 3}) == 3, "tally: aces and fortresses once, no warships")
	_check(MedalBalance.tally({}) == 0, "tally: nothing downed")


func _test_data() -> void:
	var ids := {}
	for m: Dictionary in MedalBalance.LIST:
		_check(not ids.has(m["id"]), "unique id " + m["id"])
		ids[m["id"]] = true
		_check((m["t"] as Array).size() == (m["v"] as Array).size(), "tiers and bonuses line up: " + m["id"])
		_check(MedalBalance.FRAMES.has(m["f"]), "known frame: " + m["id"])
	_check(MedalBalance.LIST.size() == 38, "38 medals: every row of the proposal page (its header said 39) (got %d)" % MedalBalance.LIST.size())
