extends SceneTree
## Unit tests of free-placed plane decals; the checks are in `decals_cases.gd`.
## Waits one frame so autoloads exist, then loads the cases: the profile references autoloads and would not
## compile if this `-s` script referenced it directly.


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/decals_cases.gd").new().run()
	print("UNIT: decals %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
