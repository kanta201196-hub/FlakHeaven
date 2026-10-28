extends SceneTree
## Weak-models list item 3 (Kanta 28.10.2026): the oasis farmstead replaced the box houses without moving the
## layout. OasisBuild.plan must give the old generator's houses, gardens and end state (values printed by the
## box version on main before the change), and the new build must be the same on every run, keep its models on
## the plot and its courtyard pieces where no palm grows. Runs from tools/ci/unit.sh. Working part —
## oasis_layout_test_run.gd (needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/oasis_layout_test_run.gd").new())
