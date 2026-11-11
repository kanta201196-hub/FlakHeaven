extends SceneTree
## Unit tests for the lighter first sortie (PG-17): the checks are in first_sortie_test_run.gd, run from a node so the
## autoloads FirstSortie refers to exist. Run from the repository root: `tools/ci/unit.sh`.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/first_sortie_test_run.gd").new())
