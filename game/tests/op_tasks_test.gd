extends SceneTree
## Unit tests for operation objectives (OT-01): the checks are in op_tasks_test_run.gd, run from a node so the
## autoloads exist. Run from the repository root: `tools/ci/unit.sh`.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/op_tasks_test_run.gd").new())
