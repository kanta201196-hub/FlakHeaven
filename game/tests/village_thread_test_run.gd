extends Node
## Working part of village_thread_test.gd: builds a village with a stream through it on a worker thread
## and waits for it without flushing the RenderingServer, as Render3D._sync_objects does.

const TIMEOUT_MS := 20000


func _ready() -> void:
	AdobeBuild.village(1)   # the base layout is built earlier in the game (prewarm), only the wet cut is left
	var water := {"id": "unit:stream", "segs": [[Vector2(-1.5, 0.02), Vector2(1.5, -0.03)]], "w": 0.04}
	var out := []
	var id := WorkerThreadPool.add_task(func() -> void: out.append(AdobeBuild.village_at(1, water)), false, "unit village_at")
	var t0 := Time.get_ticks_msec()
	while not WorkerThreadPool.is_task_completed(id) and Time.get_ticks_msec() - t0 < TIMEOUT_MS:
		OS.delay_msec(10)
	var done := WorkerThreadPool.is_task_completed(id)
	if done:
		WorkerThreadPool.wait_for_task_completion(id)
		var core: ArrayMesh = out[0][0]
		var base := AdobeBuild.village(1)
		var cut := core != base and core.surface_get_array_len(0) < base.surface_get_array_len(0)
		print("UNIT: village_thread built in %d ms, wet yards cut: %s" % [Time.get_ticks_msec() - t0, cut])
		if not cut:
			print("FAIL village_thread: the stream did not cut any yard (test water misses the village)")
	else:
		print("FAIL village_thread: village_at on a worker did not finish in %d s (deadlock)" % (TIMEOUT_MS / 1000))
	get_tree().quit(0 if done else 1)
