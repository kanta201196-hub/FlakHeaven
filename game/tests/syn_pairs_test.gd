extends SceneTree
## Unit tests of PG-11 part B1 (synergies from two different things); the checks are in `syn_pairs_cases.gd`.
## Waits one frame so autoloads exist, then loads the cases: game scripts reference autoloads and would
## not compile if this `-s` script referenced them directly.


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/syn_pairs_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
