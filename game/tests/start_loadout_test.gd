extends SceneTree
## Unit tests of S11-09 (starting loadout: one list, at most two kinds); the checks are in `start_loadout_cases.gd`.
## Waits one frame so autoloads exist, then loads the cases (see `progression_test.gd` for why).


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/start_loadout_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
