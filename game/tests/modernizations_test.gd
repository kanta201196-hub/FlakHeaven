extends SceneTree
## Unit tests of the modernizations (PG-06 PR 2); the checks are in `modernizations_cases.gd`.
## Waits one frame so autoloads exist (same reason as `progression_test.gd`).


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/modernizations_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
