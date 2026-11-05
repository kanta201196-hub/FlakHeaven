extends SceneTree
## Unit tests for the liveries Kanta took out of the game on 04.11 («Чёрный с красным» of «Кит», «Гоночная
## шахматка» of all three planes). Rules pinned here: neither id is in any class's picker, in the turret paints or in
## the round-2 list; a profile saved with one of them still loads, and the plane wears its class's default paint.
## Run from the repository root: `tools/ci/unit.sh`.
## Working part — livery_removed_test_run.gd (Livery and Profile need the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/livery_removed_test_run.gd").new())
