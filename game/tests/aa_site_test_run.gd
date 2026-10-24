extends Node
## Working part of aa_site_test.gd: builds the world terrain like the game (same seed) and checks
## AASite.place for many centres spread over 80 × 80 km, for both relief styles.

const N := 60

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
	for style in [1, 0]:
		var t: Terrain3D = load("res://scripts/terrain3d.gd").new()
		add_child(t)
		t.setup(500.0, StandardMaterial3D.new(), bg)
		t.relief_style = style
		_check_style(t, style)
		t.queue_free()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Every placed point: far enough from the river line, outside river and stream water.
func _check_style(t: Terrain3D, style: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 24102026 + style
	var near_b := 0
	var near_c := 0
	var wet := 0
	var worst_b := INF
	var worst_c := INF
	for i in N:
		var c := Vector2(rng.randf_range(-40000.0, 40000.0), rng.randf_range(-40000.0, 40000.0))
		var spots := AASite.place(t, c, rng.randf() * TAU, rng.randf_range(0.9, 1.2))
		for k in spots.size():
			var p := spots[k]
			var d := absf(t.river_field(p.x, p.y))
			if k == 0:
				worst_b = minf(worst_b, d)
				if d < AASite.RIVER_MIN - 5.0:
					near_b += 1
			else:
				worst_c = minf(worst_c, d)
				if d < AASite.CAR_RIVER_MIN - 5.0:
					near_c += 1
			if t.in_water(p, 10.0):
				wet += 1
	print("UNIT: relief %d — closest bunker %.0f px, closest vehicle %.0f px from the river" % [style, worst_b, worst_c])
	_check(near_b == 0, "relief %d: bunkers closer than %d px to the river: %d" % [style, AASite.RIVER_MIN, near_b])
	_check(near_c == 0, "relief %d: vehicles closer than %d px to the river: %d" % [style, AASite.CAR_RIVER_MIN, near_c])
	_check(wet == 0, "relief %d: AA points in water: %d" % [style, wet])
