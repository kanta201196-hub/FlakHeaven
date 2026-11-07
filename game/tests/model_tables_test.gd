extends SceneTree
## Coverage of the per-model tables (PT-04): every player plane model in use (PlaneTiers.MODEL, each class) has its
## files and an entry in each table keyed by the art key «<class>_<model>». A new model key (t4, t5) fails here
## until its GLBs, sprite and measured table rows exist, instead of falling back to another plane's numbers or to
## nothing at run time. Run from the repository root: `tools/ci/unit.sh`.
## Working part — model_tables_test_run.gd (Livery and the bench tables need the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/model_tables_test_run.gd").new())
