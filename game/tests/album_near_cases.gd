extends RefCounted
## PG-16 album in combat: rows per kind, reachability on a plane, nearest recipes, what a card opens or advances.
## Loaded by `album_near_test.gd` after the first frame.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_syn_rows()
	_test_evo_rows()
	_test_prof_arch()
	_test_nearest()
	_test_card_effect()
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## A plane that carries missiles, flares and rockets, no wingmen; «Карусель» half done
func _ctx() -> Dictionary:
	return {"snap": {"w": {"aam": 4, "flares": 2}, "taken": {"reload": 1}, "wing": 0, "s3": 1},
		"weapons": ["aam", "flares", "rockets"], "wing_cap": 0, "skill_syn": "s_wheel", "skill_title": "Карусель",
		"owned": [], "course": "", "evo_done": [], "evo_time": false, "profiles": {}, "third_open": {},
		"tags": {"missiles": 12}, "arch_on": true, "pairs_on": true}


func _test_syn_rows() -> void:
	var c := _ctx()
	var r := AlbumNear.row(c, "syn:carousel")
	_check(r["reach"] and not r["done"], "«Карусель» reachable, not done")
	_check(r["things"].size() == 2 and int(r["things"][0]["have"]) == 4 and int(r["things"][0]["need"]) == 3, "AAM 4 of 3")
	_check(int(r["things"][1]["have"]) == 2 and int(r["things"][1]["need"]) == 3, "flares 2 of 3")
	_check(AlbumNear.met(r["things"]) == 1 and is_equal_approx(float(r["prog"]), (1.0 + 2.0 / 3.0) / 2.0), "one thing met, progress the mean share")
	var cross := AlbumNear.row(c, "syn:crossfire")
	_check(not cross["reach"] and String(cross["why_arg"]).contains("Турел"), "no turret on the plane: «Перекрёстный огонь» cannot be built, says why")
	_check(not AlbumNear.row(c, "syn:wolfpack")["reach"], "no wingmen allowed: «Волчья стая» cannot be built")
	_check(AlbumNear.row(c, "syn:s_newyear").is_empty(), "another class's skill synergy is left out")
	_check(AlbumNear.row(c, "syn:s_wheel")["reach"], "own skill synergy is in")
	c["class_syns"] = ["s_wheel", "s_newyear"]
	var other := AlbumNear.row(c, "syn:s_newyear")
	_check(not other.is_empty() and not other["reach"] and String(other["why"]) != "", "another skill of the same class: shown, not reachable, says why")
	c.erase("class_syns")
	c["owned"] = ["carousel"]
	_check(AlbumNear.row(c, "syn:carousel")["done"], "an open synergy is done")
	_check(int(AlbumNear.row(c, "syn:decoy")["things"][0]["need"]) == 4, "the second slot asks level 4")
	c["pairs_on"] = false
	_check(AlbumNear.row(c, "syn:carousel").is_empty(), "with tag synergies (F1 off) synergy rows are left out")
	_check(AlbumNear.row(c, "syn:gunner").is_empty() or not AlbumNear.row(_ctx(), "syn:gunner")["reach"], "a retired synergy is never reachable")


func _test_evo_rows() -> void:
	var c := _ctx()
	var r := AlbumNear.row(c, "evo:aam")
	_check(r["reach"] and int(r["things"][0]["need"]) == Weapons.MAX_LEVEL, "«Шмель» asks AAM at the top level")
	_check(int(r["things"][1]["have"]) == 1 and int(r["things"][1]["need"]) == 2, "reload 1 of 2")
	_check(r["late"], "before 7:00 the row says it is too early")
	_check(not AlbumNear.row(c, "evo:bombs")["reach"], "no bombs on the plane")
	var gun := AlbumNear.row(c, "evo:gun")
	_check(gun["reach"] and gun["things"].size() == 2, "«Дятел» needs only the gun modules")
	c["evo_done"] = ["aam"]
	_check(AlbumNear.row(c, "evo:aam")["done"], "a done modernization")


func _test_prof_arch() -> void:
	var c := _ctx()
	var w := "aam"
	var ids := WeaponProfiles.ids(w)
	_check(ids.size() >= 2, "AAM has profiles")
	var r := AlbumNear.row(c, "prof:%s:%s" % [w, ids[0]])
	_check(r["reach"] and float(r["prog"]) >= 1.0, "AAM 4: the profile choice is due")
	c["profiles"] = {w: ids[0]}
	_check(AlbumNear.row(c, "prof:%s:%s" % [w, ids[0]])["done"], "the chosen profile is done")
	_check(not AlbumNear.row(c, "prof:%s:%s" % [w, ids[1]])["reach"], "another profile of the same weapon is closed")
	if ids.size() >= 3:
		_check(not AlbumNear.row(_ctx(), "prof:%s:%s" % [w, ids[2]])["reach"], "the third profile is closed without the hangar branch")
	var a := AlbumNear.row(c, "arch:missiles")
	_check(a["reach"] and int(a["things"][0]["need"]) == int(ArchBalance.at_of("missiles")[2]), "archetype asks rank III points")
	c["arch_on"] = false
	_check(AlbumNear.row(c, "arch:missiles").is_empty(), "archetypes off: no rows")


func _test_nearest() -> void:
	var c := _ctx()
	var rows := AlbumNear.rows(c, ["syn:carousel", "syn:decoy", "syn:crossfire", "evo:aam", "evo:rockets", "prof:aam:" + String(WeaponProfiles.ids("aam")[0]), "arch:missiles"])
	var near := AlbumNear.nearest(rows)
	_check(near.size() == 3, "three nearest")
	_check(String(near[0]["id"]) == "syn:carousel", "«Карусель» first (furthest along)")
	_check(not near.any(func(r): return r["id"] == "syn:crossfire"), "unreachable ones are not near")
	_check(not near.any(func(r): return r["kind"] in ["prof", "arch"]), "profiles and archetypes are not recipes")
	c["course"] = "salvo"
	rows = AlbumNear.rows(c, ["syn:carousel", "syn:salvo", "syn:crossfire", "syn:decoy"])
	var sec := AlbumNear.sections(rows)
	_check(sec[1].size() == 2 and String(sec[1][0]["id"]) == "syn:salvo", "album tab: the course goes first")
	_check(sec[2].size() == 2 and String(sec[2][0]["id"]) == "syn:crossfire", "album tab: unreachable below")


func _test_card_effect() -> void:
	var c := _ctx()
	var rows := AlbumNear.rows(c, ["syn:carousel", "syn:decoy", "evo:aam", "evo:flares"])
	var e := AlbumNear.card_effect(c, rows, {"weapon": "flares", "add": 1})
	_check(not e.is_empty() and String(e["row"]["id"]) == "syn:carousel" and e["opens"], "flares 2 → 3 completes «Карусель»")
	e = AlbumNear.card_effect(c, rows, {"mod": "reload"})
	_check(not e.is_empty() and String(e["row"]["id"]) == "evo:aam" and not e["opens"], "reload advances «Шмель» (AAM still 4 of 5)")
	_check(AlbumNear.card_effect(c, rows, {"mod": "magnet"}).is_empty(), "a magnet moves nothing")
	_check(AlbumNear.card_effect(c, rows, {}).is_empty(), "an empty card moves nothing")
	e = AlbumNear.card_effect(c, rows, {"weapon": "aam", "add": 1})
	_check(not e.is_empty() and String(e["row"]["id"]) == "evo:aam", "AAM 4 → 5 goes to «Шмель», not the met AAM of «Карусель»")
	c["snap"]["w"]["aam"] = 0
	rows = AlbumNear.rows(c, ["syn:carousel"])
	e = AlbumNear.card_effect(c, rows, {"weapon": "aam", "add": 2, "new": true})
	_check(not e.is_empty() and int(e["after"][0]["have"]) == 2 and not e["opens"], "a new AAM at level 2 advances, does not open")
