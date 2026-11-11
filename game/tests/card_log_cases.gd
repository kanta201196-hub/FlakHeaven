extends RefCounted
## PG-12 card telemetry: stable keys of offered cards (no hardpoint index, so cards of the same weapon add up across
## sorties) and the compact entry of one card screen. Loaded by `card_log_test.gd` after the first frame.

var _failed := 0
var _checks := 0


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_keys()
	_test_entry()
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_keys() -> void:
	_check(CardLog.key({"kind": "weapon_new", "id": "new_aam_1", "weapon": "aam"}, "") == "new:aam", "new weapon: new:<weapon>")
	_check(CardLog.key({"kind": "weapon_up", "id": "up_0", "group": 0}, "rockets") == "up:rockets", "upgrade: up:<weapon of the group>")
	_check(CardLog.key({"kind": "profile", "id": "pr_swarm_1", "profile": "swarm", "weapon": "aam"}, "aam") == "pr:aam:swarm", "profile: pr:<weapon>:<profile>")
	_check(CardLog.key({"kind": "branch", "id": "br_a_0", "branch": "a", "group": 0}, "bombs") == "br:bombs:a", "mastery branch: br:<weapon>:<branch>")
	_check(CardLog.key({"kind": "module", "id": "armor"}, "") == "armor", "module: its id")
	_check(CardLog.key({"kind": "wing_new", "id": "wing_new_cover", "wtype": "cover"}, "") == "wing:cover", "new wingman: wing:<type>")
	_check(CardLog.key({"kind": "wing_lvl", "id": "wing_lvl_1", "wi": 1}, "") == "wing_lvl", "wingman level: one key")
	_check(CardLog.key({"kind": "reserve", "id": "res_evo_2", "group": 2}, "") == "res_evo", "reserve Э+: no group index")
	_check(CardLog.key({"kind": "reserve", "id": "res_evo_gun", "group": -1}, "") == "res_evo", "reserve Э+ of the gun: same key")
	_check(CardLog.key({"kind": "reserve", "id": "res_kit"}, "") == "res_kit", "other reserve: its id")
	_check(CardLog.key({"kind": "synergy", "id": "syn_carousel", "syn": "carousel"}, "") == "syn:carousel", "synergy: syn:<id>")
	_check(CardLog.key({"kind": "evolution", "id": "evo_x", "evo": "aam_swarm"}, "") == "evo:aam_swarm", "modernization: evo:<recipe>")
	_check(CardLog.key({"kind": "trade", "id": "t_glass"}, "") == "t_glass", "trade-off card: its id")


func _test_entry() -> void:
	var keys := ["up:aam", "armor", "new:flares"]
	var rar := [0, 2, 1]
	_check(CardLog.entry(125.4, 6, keys, rar, 1) == "125 L6: up:aam/0, armor/2*, new:flares/1", "taken card marked with *")
	_check(CardLog.entry(30.0, 2, ["armor"], [0], -1) == "30 L2: armor/0 ~", "screen left by a reroll: no * and a trailing ~")
	var p := CardLog.parse("125 L6: up:aam/0, armor/2*, new:flares/1")
	_check(p["t"] == 125 and p["lvl"] == 6 and p["taken"] == "armor" and (p["keys"] as Array).size() == 3, "parse reads time, level, taken card, keys")
	_check(String((p["keys"] as Array)[2]) == "new:flares", "parse keeps keys with a colon")
	_check(CardLog.parse("30 L2: armor/0 ~")["taken"] == "", "parse: a reroll screen has no taken card")
