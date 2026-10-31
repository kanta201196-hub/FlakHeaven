extends SceneTree
## Unit tests of the build self-check job lists (R-23); the checks are in `self_check_cases.gd`.
## Waits one frame so autoloads exist (SelfCheck reads Profile and Prog), then loads the cases.
## Run from the repository root: `tools/ci/unit.sh`.


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/self_check_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
