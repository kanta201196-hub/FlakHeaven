extends Node
## Working part of livery_removed_test.gd: Livery reads the saved choice from the Profile autoload, which exists only
## after the SceneTree starts. The profile is changed in memory only (never saved), and restored at the end.

const REMOVED := ["black_red", "chequer"]

var _failed := 0
var _checks := 0


func _ready() -> void:
	for cls in ["fighter", "attacker", "bomber"]:
		var ids: Array = Livery.list(cls).map(func(v: Array) -> String: return v[0])
		for id: String in REMOVED:
			_check(not ids.has(id), "%s picker has no %s" % [cls, id])
	for id: String in REMOVED:
		_check(not Livery.TURRET_PAINT.has(id), "no turret paint for %s" % id)
		_check(not Livery.ROUND2.any(func(v: Array) -> bool: return v[0] == id), "round 2 has no %s" % id)
	# an old save that chose a removed paint: the plane falls back to the class default
	for cls in ["fighter", "attacker", "bomber"]:
		var keep := Profile.livery(cls)
		var default := String(Livery.VARIANTS[cls][0][0])
		for id: String in REMOVED:
			Profile.cls(cls)["livery"] = id
			_check(Livery.current(cls) == default, "%s saved with %s wears %s, got %s" % [cls, id, default, Livery.current(cls)])
			_check(Livery.turret_paint(cls).is_empty(), "%s saved with %s keeps the default turrets" % [cls, id])
		Profile.cls(cls)["livery"] = keep
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
