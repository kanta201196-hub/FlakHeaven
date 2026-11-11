extends SceneTree
## Unit tests of PG-16 (the build album during a sortie); the checks are in `album_near_cases.gd`.
## Waits one frame so autoloads exist, then loads the cases (game scripts reference autoloads).


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/album_near_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
