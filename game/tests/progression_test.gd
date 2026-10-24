extends SceneTree
## Unit tests of PG-01 (deeper upgrades, stage 1); the checks are in `progression_cases.gd`.
## Waits one frame so autoloads exist, then loads the cases: game scripts reference autoloads and would
## not compile if this `-s` script referenced them directly.


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/progression_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
