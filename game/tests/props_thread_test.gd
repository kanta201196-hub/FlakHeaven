extends SceneTree
## Regression test: BiomeProps.plan runs on worker threads (Terrain3D chunk tasks) and must give the same
## placement as on the main thread. GDScript const Arrays are read-only, and Godot 4.4 returns an element of a
## read-only Array through one scratch slot per array, so worker threads reading the same const list clobbered
## each other: a rock drew the wrong variant, and once the kind came out empty (SCRIPT ERROR in BiomeProps._row,
## Forward+ bench 28.10). Runs from tools/ci/unit.sh. Working part: props_thread_test_run.gd (needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/props_thread_test_run.gd").new())
