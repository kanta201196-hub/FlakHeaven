extends Node
## Working part of props_thread_test.gd: builds the world terrain like the game, plans the props of a block of
## chunks on the main thread, then plans them again many times at once on worker threads and compares every kind,
## count and transform. Any difference, or a kind BiomeProps does not know, fails the test.

const SIDE := 6        # chunks from -SIDE to SIDE - 1 on each axis
const ROUNDS := 6      # parallel passes over the block; the race showed in 2–4 of 6 before the fix

var _keys: Array[Vector2i] = []
var _ctxs: Array = []
var _res: Array = []
var _t: Terrain3D


func _ready() -> void:
	var bg: Background = load("res://scripts/background.gd").new()
	add_child(bg)
	await get_tree().process_frame
	_t = load("res://scripts/terrain3d.gd").new()
	add_child(_t)
	_t.setup(500.0, StandardMaterial3D.new(), bg)
	bg.place_filter = _t.fix_object
	_t.props = BiomeProps.new(_t)
	for cx in range(-SIDE, SIDE):
		for cy in range(-SIDE, SIDE):
			_keys.append(Vector2i(cx, cy))
	for k in _keys:
		_ctxs.append(_t._ctx(k))
	var ref := []
	for i in _keys.size():
		ref.append(_sig(_t.props.plan(_keys[i], _ctxs[i])))
	print("UNIT: props thread — main-thread plan hash %d" % hash(ref))
	var failed := 0
	var rocks := 0
	for r in ROUNDS:
		_res.clear()
		_res.resize(_keys.size())
		var gid := WorkerThreadPool.add_group_task(_one, _keys.size(), -1, true, "props thread test")
		WorkerThreadPool.wait_for_group_task_completion(gid)
		for i in _keys.size():
			var put: Dictionary = _res[i]
			for kind: String in put:
				if kind == "" or not BiomeProps.KINDS.has(kind):
					failed += 1
					print("FAIL: unknown kind '%s' in chunk %s, round %d" % [kind, _keys[i], r])
				elif kind in BiomeProps.ROCK_KINDS:
					rocks += (put[kind] as Array).size()
			var sig := _sig(put)
			if sig != ref[i]:
				failed += 1
				print("FAIL: chunk %s, round %d: worker plan differs\n  worker %s\n  main   %s" % [_keys[i], r, sig, ref[i]])
	print("UNIT: props thread — %d chunks × %d rounds, %d rocks placed, %d failed" % [_keys.size(), ROUNDS, rocks, failed])
	get_tree().quit(1 if failed > 0 or rocks == 0 else 0)


func _one(i: int) -> void:
	_res[i] = _t.props.plan(_keys[i], _ctxs[i])


## Kinds in name order, each with its count and a hash of its transforms (rounded, so only real moves count)
func _sig(put: Dictionary) -> String:
	var ks := put.keys()
	ks.sort()
	var out := ""
	for k in ks:
		var h := 0
		for t: Transform3D in put[k]:
			h = hash([h, snappedf(t.origin.x, 0.01), snappedf(t.origin.y, 0.01), snappedf(t.origin.z, 0.01),
				snappedf(t.basis.x.x, 0.001), snappedf(t.basis.x.z, 0.001)])
		out += "%s:%d:%d " % [k, (put[k] as Array).size(), h]
	return out
