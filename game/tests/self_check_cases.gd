extends RefCounted
## Checks of the build self-check job lists (SelfCheck, R-23): which planes, weapons and tiers the sheet covers,
## the single-weapon hangar loadout and the combat loadout. Run by `self_check_test.gd` once the autoloads exist.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_planes()
	_test_tiers()
	_test_hangar_jobs()
	_test_store_jobs()
	_test_loadout()
	_test_combat()
	_test_tip_group()
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_planes() -> void:
	var pl := SelfCheck.planes()
	var n_planes := PlaneClasses.LIST.size() * PlaneTiers.model_keys().size()
	_check(pl.size() == n_planes, "every class × every model key t1 / 1 / 2 / t4 / t5 (got %d)" % pl.size())
	_check(pl.has(["bomber", "2"]) and pl.has(["fighter", "1"]) and pl.has(["attacker", "t1"]), "bomber 2, fighter 1, attacker t1 are there")
	var w := SelfCheck.plane_weapons("fighter", "2")
	_check(w.has("srm") and not SelfCheck.plane_weapons("fighter", "1").has("srm"), "srm only on «Оса» 2")
	_check(SelfCheck.tier_of("t1") == 1 and SelfCheck.tier_of("1") == 2 and SelfCheck.tier_of("2") == 3,
		"each model is checked with the tier it was made for")
	_check(not SelfCheck.plane_weapons("attacker", "t1").has("turret"), "«Грач» tier 1 has no turret")
	_check(not w.has("railgun"), "no experimental weapons")


func _test_tiers() -> void:
	_check(SelfCheck.tiers("aam") == [1, 2, 3, 4], "aam evolves: four tiers")
	_check(SelfCheck.tiers("agm") == [1, 2, 3], "agm has no modernisation")


## Every plane × weapon at four tiers; a weapon without modernisation keeps an empty ("na") cell
func _test_hangar_jobs() -> void:
	var jobs := SelfCheck.hangar_jobs()
	var combos := 0
	for pl: Array in SelfCheck.planes():
		combos += SelfCheck.plane_weapons(pl[0], pl[1]).size()
	_check(jobs.size() == combos * 4, "4 cells per plane × weapon (%d, %d combos)" % [jobs.size(), combos])
	var na := jobs.filter(func(j: Dictionary) -> bool: return j["na"])
	_check(na.all(func(j: Dictionary) -> bool: return j["tier"] == 4 and not Prog.EVOS.has(j["weapon"])), "only modernised cells of non-evolving weapons are empty")
	_check(jobs.any(func(j: Dictionary) -> bool: return j["cls"] == "bomber" and j["lvl"] == "2" and j["weapon"] == "turret" and j["tier"] == 4),
		"«Кит» 2 turret modernised is shot")


func _test_store_jobs() -> void:
	var jobs := SelfCheck.store_jobs()
	var turrets := jobs.filter(func(j: Dictionary) -> bool: return j["weapon"] == "turret")
	_check(turrets.size() == 8, "turret store for attacker and bomber, 4 tiers each (got %d)" % turrets.size())
	_check(jobs.filter(func(j: Dictionary) -> bool: return j["weapon"] == "aam").size() == 4, "aam once in the store")


## The weapon goes where the game would put it as the only start weapon; other groups are emptied
func _test_loadout() -> void:
	var e := Hangar3D.BENCH_EMPTY
	_check(SelfCheck.loadout("fighter", "aam") == ["aam", e], "signature on the wing pair")
	_check(SelfCheck.loadout("bomber", "bombs") == ["bombs", e], "bombs in the bay")
	_check(SelfCheck.loadout("bomber", "rockets") == [e, "rockets"], "rockets on the bomber's wings, not in the bay")
	_check(SelfCheck.loadout("attacker", "turret") == [e, e], "turret alone: every group empty")


func _test_combat() -> void:
	var b := SelfCheck.combat_loadout("bomber", "1")
	_check(b.size() == PlaneClasses.group_defs("bomber", true).size(), "one weapon per bomber group")
	_check(b[0] == "bombs", "bombs in the bay group (got %s)" % b[0])
	_check(not b.has("turret") and not b.has("flares"), "no turret or flares on a hardpoint")
	var pts := SelfCheck.combat_points(Vector2(10, 20))
	var pods := SelfCheck.planes().filter(func(pl: Array) -> bool: return SelfCheck.combat_loadout(pl[0], pl[1]).has("rockets"))
	var n_planes := SelfCheck.planes().size()
	_check(pts.size() == n_planes * 5 + pods.size(), "five shots per plane, a salvo on each with rocket pods (got %d)" % pts.size())
	var salvo := pts.filter(func(p: Dictionary) -> bool: return p["sc_shot"] == "salvo")
	_check(salvo.size() == pods.size() and pods.size() > 0, "a salvo shot per rocket-pod plane (got %d)" % salvo.size())
	_check(salvo.all(func(p: Dictionary) -> bool: return p.get("sc_salvo", false) and not p.has("sc_fill")), "salvo at the gameplay camera")
	_check(pts.filter(func(p: Dictionary) -> bool: return p.get("sc_check", false)).size() == n_planes, "one checked shot per plane")
	_check(pts.all(func(p: Dictionary) -> bool: return p["pos"] == Vector2(10, 20)), "all at the given spot")
	var close := pts.filter(func(p: Dictionary) -> bool: return p["sc_shot"] in ["nozzles", "muzzles", "stores"])
	_check(close.all(func(p: Dictionary) -> bool: return p.has("sc_fill") and not p.has("zoom")), "close-ups sized by plane length, not a fixed zoom")


## The «Оса» wing-tip group: missiles ride the tip rail; a rocket pod (Kanta, «Оса» 2: it stood half off the
## wing tip) hangs under the outer wing at PlaneArt.OUTER_PAIR, inside the half-span and outboard of the inner pair
func _test_tip_group() -> void:
	_check(WeaponModels.on_tip_rail("aam") and WeaponModels.on_tip_rail("srm"), "missiles ride the tip rail")
	_check(not WeaponModels.on_tip_rail("rockets") and not WeaponModels.on_tip_rail("bombs"), "pods and bombs do not")
	var g3: Dictionary = PlaneClasses.GROUP3["fighter"]
	for lv in PlaneTiers.model_keys():
		var gi := PlaneClasses.group_defs("fighter", true).size() - 1
		var h := Hardpoint.new(g3["name"], int(g3["slots"]), "aam")
		h.mount_frac = float(g3["frac"])
		var rail: Array = WeaponModels.mounts("fighter", lv, gi, h)
		_check(rail.size() == 2 and rail.all(func(m: Dictionary) -> bool: return m["side"] == "tip"), "fighter_%s: aam on the tip rail" % lv)
		h.weapon = "rockets"
		var pods: Array = WeaponModels.mounts("fighter", lv, gi, h)
		var tw := float(PlaneArt.plane_tex("fighter", lv).get_width())
		var st: Vector2 = PlaneArt.OUTER_PAIR[PlaneTiers.art_key("fighter", lv)]
		_check(pods.size() == 2 and pods.all(func(m: Dictionary) -> bool: return m["side"] == "under"), "fighter_%s: rocket pods under the wing" % lv)
		_check(pods.all(func(m: Dictionary) -> bool: return absf(absf((m["p"] as Vector2).y) / tw - st.y) < 0.001 and absf((m["p"] as Vector2).x / tw - st.x) < 0.001), "fighter_%s: pods at the outer station" % lv)
		var inner: Vector2 = PlaneArt.WING_PAIR[PlaneTiers.art_key("fighter", lv)]
		var half := float(PlaneArt.shape_info("fighter", lv)["half"]) / tw
		_check(st.y > inner.y and st.y < half, "fighter_%s: outer station between the inner pair and the tip" % lv)
