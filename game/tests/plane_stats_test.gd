extends SceneTree
## Unit tests for `PlaneStats` (S16-08): the hangar's plane characteristics and the level-1 → level-2 difference.
## Working part — plane_stats_test_run.gd (PlaneClasses reads Profile, an autoload that exists only after the tree starts).
## Run from the repository root: `tools/ci/unit.sh`.


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/plane_stats_test_run.gd").new())
