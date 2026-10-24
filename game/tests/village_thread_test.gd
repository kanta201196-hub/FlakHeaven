extends SceneTree
## Regression test: a riverside village is built on a worker thread (Render3D prefetch) while the main
## thread waits for that task. Before the fix village_core read the base mesh back with
## ArrayMesh.surface_get_arrays, which waits for the main thread's RenderingServer flush — a deadlock
## (the sortie froze near a village whose yards touch a stream, 2026-10-24).
## Runs from tools/ci/unit.sh. Working part — village_thread_test_run.gd (needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/village_thread_test_run.gd").new())
