extends Node
## Working part of livery_turret_test.gd: Livery and WeaponModels compile against the autoloads (Profile, Tuning),
## which exist only after the SceneTree starts.

var _failed := 0
var _checks := 0


func _ready() -> void:
	var cases := [["attacker", ""], ["bomber", ""], ["bomber", "tail"], ["bomber", "cabin"]]
	for c: Array in cases:
		for t in [1, 2, 3]:
			for evo in [false, true]:
				var sand := WeaponModels.turret_file(c[0], t, c[1], evo, "sand_camo")
				_check(sand != "" and not sand.contains("_steppe") and not sand.contains("_rock"),
						"%s %s t%d evo %s: sand-camo turret %s" % [c[0], c[1], t, evo, sand])
				for id in ["steppe", "rock"]:
					var f := WeaponModels.turret_file(c[0], t, c[1], evo, id)
					_check(f == "%s_%s.glb" % [sand.get_basename(), id], "%s %s t%d evo %s: %s turret %s" % [
							c[0], c[1], t, evo, id, f])
	_check(WeaponModels.turret_file("attacker", 1, "", false, "tiger").get_file() == "turret_grach_t1.glb",
			"tiger keeps the sand turret")
	for cls in ["fighter", "attacker", "bomber"]:
		var ids: Array = Livery.VARIANTS[cls].map(func(v: Array) -> String: return v[0])
		_check(ids.has("steppe") and ids.has("rock"), "%s picker has steppe and rock" % cls)
		_check(not ids.any(func(i: String) -> bool: return i.begins_with("nat_")), "%s picker has no proposals" % cls)
	_check(Livery.VARIANTS["attacker"][0][0] == "sand_camo" and Livery.VARIANTS["bomber"][0][0] == "sand_camo"
			and Livery.VARIANTS["fighter"][0][0] == "classic", "defaults unchanged")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
