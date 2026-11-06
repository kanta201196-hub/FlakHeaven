extends SceneTree
## Regression test: SeaProps.plan (Archipelago props) runs on Terrain3D's worker threads like BiomeProps.plan and
## must give the same placement as on the main thread. It indexed const Arrays (HOUSES) there, the race fixed for
## the Highlands in #488 (see props_thread_test.gd). Runs from tools/ci/unit.sh; working part props_thread_test_run.gd.


func _initialize() -> void:
	var run: Node = load("res://tests/props_thread_test_run.gd").new()
	run.sea = true
	root.add_child.call_deferred(run)
