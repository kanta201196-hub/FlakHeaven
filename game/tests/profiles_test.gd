extends SceneTree
## Unit tests of the weapon profiles (PG-06); the checks are in `profiles_cases.gd`.
## Waits one frame so autoloads exist (same reason as `progression_test.gd`).


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/profiles_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
