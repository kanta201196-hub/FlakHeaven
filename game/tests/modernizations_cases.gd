extends RefCounted
## Unit tests for the modernizations (PG-06 PR 2): the recipe table, the catalyst rule and the numbers a
## modernized hardpoint reports. Same style as `profiles_cases.gd`; outside a sortie (`Main.I` is null), so
## class, crew and hangar factors are 1.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_table()
	_test_cat_done()
	_test_hardpoint_numbers()
	_test_classic_untouched()
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Two recipes for each stage-1 pool weapon that has profiles plus `hebomb`, different catalysts within one
## weapon, every catalyst a real module, player text everywhere; classic ids keep their weapon.
func _test_table() -> void:
	for w in ["aam", "rockets", "srm", "agm", "hebomb"]:
		var ids := Modernizations.ids_for(w)
		_check(ids.size() == 2, "%s: two recipes (got %d)" % [w, ids.size()])
		if ids.size() == 2:
			_check(Modernizations.cat(ids[0]).keys() != Modernizations.cat(ids[1]).keys(), "%s: different catalysts" % w)
		for id in ids:
			var d := Modernizations.def(id)
			_check(String(d.get("title", "")) != "" and String(d.get("desc", "")) != "", "%s: text" % id)
			for m in Modernizations.cat(id):
				_check(Cards.MODULES.has(m), "%s: catalyst %s is a module" % [id, m])
	_check(Modernizations.ids_for("aam")[0] == "aam" and Modernizations.ids_for("rockets")[0] == "rockets", "classic recipe first")
	_check(Modernizations.ids_for("gunpod") == ["gunpod"] and Modernizations.ids_for("gun") == ["gun"], "one recipe where nothing new")
	_check(Modernizations.ids_for("laser").is_empty(), "no recipe for experimental weapons")
	_check(Modernizations.weapon_of("srm_sentry") == "srm" and Modernizations.weapon_of("bombs") == "bombs", "weapon_of")
	_check(Modernizations.weapon_of("nope") == "" and Modernizations.def("nope").is_empty(), "unknown id")
	_check(Modernizations.is_new("agm_sledge") and not Modernizations.is_new("aam"), "is_new")


func _test_cat_done() -> void:
	_check(not Modernizations.cat_done("srm_hornets", {}), "nothing taken")
	_check(not Modernizations.cat_done("srm_hornets", {"roll": 1}), "one of two")
	_check(Modernizations.cat_done("srm_hornets", {"roll": 2}), "two of two")
	_check(Modernizations.cat_done("gun", {"gun_dmg": 5, "gun_rate": 2}) and not Modernizations.cat_done("gun", {"gun_dmg": 5}), "two-module recipe")
	_check(not Modernizations.cat_done("nope", {"roll": 9}), "unknown id never ready")


## A modernized hardpoint: fixed damage or a factor on level 5, fixed reload replaces the level growth.
func _test_hardpoint_numbers() -> void:
	var h := Hardpoint.new("test", 2, "agm")
	h.level = 5
	var d5 := h.dmg()
	h.evo = true
	h.evo_id = "agm_sledge"
	_check(is_equal_approx(h.dmg() / d5, 1.7), "agm_sledge dmg ×1.7 of level 5 (got %.3f)" % (h.dmg() / d5))
	_check(h.evo_def().get("splash", 0.0) == 160.0, "evo_def reads the recipe")
	_check(h.evo_title() == "«Кувалда»", "title of the recipe (got %s)" % h.evo_title())
	h.evo_plus = 1
	_check(is_equal_approx(h.dmg() / d5, 1.7 * 1.08), "«Э+» adds 8 %")
	var a := Hardpoint.new("test", 2, "aam")
	a.level = 5
	a.evo = true
	a.evo_id = "aam_swarm"
	_check(is_equal_approx(a.dmg(), 45.0), "aam_swarm fixed 45 (got %.1f)" % a.dmg())
	var s := Hardpoint.new("test", 2, "srm")
	s.level = 5
	_check(s.evo_def().is_empty() and not s.classic_evo(), "not modernized: no recipe")
	s.evo = true
	s.evo_id = "srm_hornets"
	_check(not s.classic_evo(), "new recipe is not the classic one")


## The classic modernization keeps its numbers: «Шмель» 120 per missile.
func _test_classic_untouched() -> void:
	var a := Hardpoint.new("test", 2, "aam")
	a.level = 5
	a.evo = true
	_check(a.classic_evo() and a.evo_id == "", "classic: empty evo_id")
	_check(is_equal_approx(a.dmg(), 120.0), "«Шмель» 120 (got %.1f)" % a.dmg())
	_check(a.evo_title() == "«Шмель»", "classic title")
