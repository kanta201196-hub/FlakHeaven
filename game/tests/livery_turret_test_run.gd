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
				_check(sand != "" and not Livery.TURRET_PAINT.keys().any(func(id: String) -> bool: return sand.contains("_" + id)),
						"%s %s t%d evo %s: sand-camo turret %s" % [c[0], c[1], t, evo, sand])
				for id: String in Livery.TURRET_PAINT:
					var f := WeaponModels.turret_file(c[0], t, c[1], evo, id)
					_check(f == "%s_%s.glb" % [sand.get_basename(), id], "%s %s t%d evo %s: %s turret %s" % [
							c[0], c[1], t, evo, id, f])
	_check(WeaponModels.turret_file("attacker", 1, "", false, "tiger").get_file() == "turret_grach_t1.glb",
			"tiger keeps the sand turret")
	for id: String in Livery.TURRET_PAINT:
		var tp: Array = Livery.TURRET_PAINT[id]
		_check(tp.size() == 2 and tp[1] is Color, "%s turret paint has a suffix and a collar colour" % id)
	for v: Array in Livery.ROUND2:
		_check(Livery.TURRET_PAINT.has(v[0]), "round-2 %s has a baked turret paint" % v[0])
		_check(v.size() == 11 and int(v[7]) == 7, "round-2 %s is a pattern 7 paint with params" % v[0])
	for cls in ["fighter", "attacker", "bomber"]:
		var ids: Array = Livery.VARIANTS[cls].map(func(v: Array) -> String: return v[0])
		_check(ids.has("steppe") and ids.has("rock"), "%s picker has steppe and rock" % cls)
		for v: Array in Livery.ROUND2:
			_check(ids.has(v[0]), "%s picker has %s" % [cls, v[0]])
		var seen := {}
		for i: String in ids:
			seen[i] = true
		_check(seen.size() == ids.size(), "%s picker ids are unique" % cls)
		_check(not ids.any(func(i: String) -> bool: return i.begins_with("nat_")), "%s picker has no proposals" % cls)
	_check(Livery.VARIANTS["attacker"][0][0] == "sand_camo" and Livery.VARIANTS["bomber"][0][0] == "sand_camo"
			and Livery.VARIANTS["fighter"][0][0] == "classic", "defaults unchanged")
	# the shark mouth is placed by each plane's own nose: every plane model has one, inside its length
	for key in ["fighter_1", "fighter_2", "attacker_1", "attacker_2", "bomber_1", "bomber_2"]:
		var n: Array = Livery.NOSE.get(key, [])
		_check(n.size() == 4 and n[0] > n[1] and n[0] < 0.5 and n[1] > 0.0 and n[3] > 0.0, "%s nose for the shark mouth" % key)
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
