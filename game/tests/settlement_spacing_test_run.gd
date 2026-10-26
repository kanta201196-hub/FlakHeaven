extends Node
## Working part of settlement_spacing_test.gd: builds the world terrain like the game, places the cell objects
## of a 40 × 40 cell area (56 × 56 km) through the same filter as Render3D, and checks every pair of big objects.

const CELLS := 20
## The settle spot is checked before the river push, which may move each object a little: allow for it.
const PUSH_SLACK := 0.8

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _ready() -> void:
	var bg: Background = load("res://scripts/background.gd").new()
	add_child(bg)
	await get_tree().process_frame
	var t: Terrain3D = load("res://scripts/terrain3d.gd").new()
	add_child(t)
	t.setup(500.0, StandardMaterial3D.new(), bg)
	bg.place_filter = t.fix_object
	var big := []
	for cx in range(-CELLS, CELLS):
		for cy in range(-CELLS, CELLS):
			var o := bg.chunk_object(cx, cy)
			if not o.is_empty() and o["name"] in ["o_village", "o_fort", "o_oasis", "o_mesa"]:
				big.append(o)
	var settled := big.filter(func(o: Dictionary) -> bool: return o["name"] in Terrain3D.SETTLE)
	_check(settled.size() >= 40, "settlements left on the map: %d" % settled.size())
	var closest := INF
	for i in big.size():
		for j in range(i + 1, big.size()):
			var a: Dictionary = big[i]
			var b: Dictionary = big[j]
			var mesa: bool = a["name"] == "o_mesa" or b["name"] == "o_mesa"
			if mesa and a["name"] == b["name"]:
				continue
			var gap := (a["pos"] as Vector2).distance_to(b["pos"]) - t._settle_r(a) - t._settle_r(b)
			if mesa:
				_check(gap >= 0.0, "%s on %s at %s (gap %d px)" % [a["name"], b["name"], a["pos"], gap])
			else:
				closest = minf(closest, gap)
				_check(gap >= Terrain3D.SETTLE_GAP * PUSH_SLACK, "%s and %s %d px apart at %s" % [a["name"], b["name"], gap, a["pos"]])
	print("UNIT: settlement spacing — %d settlements, closest edges %d px, %d checks, %d failed" % [settled.size(), closest, _checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
