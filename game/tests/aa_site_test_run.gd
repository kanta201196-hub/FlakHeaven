extends Node
## Working part of aa_site_test.gd: builds the world terrain like the game (same seed) and checks
## AASite.place for many centres spread over 80 × 80 km, for both relief styles, by real distance to
## the river line (Terrain3D.river_dist), which is itself checked against a brute-force scan first.

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
	var t0: Terrain3D = load("res://scripts/terrain3d.gd").new()
	add_child(t0)
	t0.setup(500.0, StandardMaterial3D.new(), bg)
	_check_river_dist(t0)
	t0.queue_free()
	for style in [1, 0]:
		var t: Terrain3D = load("res://scripts/terrain3d.gd").new()
		add_child(t)
		t.setup(500.0, StandardMaterial3D.new(), bg)
		t.relief_style = style
		_check_style(t, style)
		t.queue_free()
	var td: Terrain3D = load("res://scripts/terrain3d.gd").new()
	add_child(td)
	td.setup(500.0, StandardMaterial3D.new(), bg)
	_check_drawn(td)
	_check_ctx_split(td)
	td.queue_free()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## river_dist agrees with a dense scan for sign changes of river_field (the river line) within 6 px
## grid + bisection tolerance, at points where the field is a poor distance (far from the bed).
func _check_river_dist(t: Terrain3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2410
	var worst := 0.0
	for i in 12:
		var c := Vector2(rng.randf_range(-40000.0, 40000.0), rng.randf_range(-40000.0, 40000.0))
		var p := t._field_point(c, rng.randf_range(100.0, 450.0) * (1.0 if rng.randf() < 0.5 else -1.0))
		var real := _scan(t, p, 600.0)
		var got := t.river_dist(p, 600.0)
		worst = maxf(worst, absf(real - got))
	print("UNIT: river_dist vs scan — worst difference %.0f px" % worst)
	_check(worst <= 16.0, "river_dist differs from the scan by %.0f px" % worst)


## Distance from p to the nearest sign change of river_field on a 6 px grid within R (R if none)
func _scan(t: Terrain3D, p: Vector2, R: float) -> float:
	var best := R
	var st := 6.0
	var y := -R
	while y <= R:
		var x := -R
		var prev := signf(t.river_field(p.x + x, p.y + y))
		while x <= R:
			var s := signf(t.river_field(p.x + x, p.y + y))
			if s != prev:
				best = minf(best, Vector2(x, y).length())
			prev = s
			x += st
		y += st
	return best


## Every placed point: far enough from the river line (real distance), outside river and stream water.
func _check_style(t: Terrain3D, style: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 24102026 + style
	var near_b := 0
	var near_c := 0
	var wet := 0
	var worst_b := INF
	var worst_c := INF
	var us_sum := 0
	var us_max := 0
	for i in N:
		var c := Vector2(rng.randf_range(-40000.0, 40000.0), rng.randf_range(-40000.0, 40000.0))
		var u0 := Time.get_ticks_usec()
		var spots := AASite.place(t, c, rng.randf() * TAU, rng.randf_range(0.9, 1.2))
		var u := Time.get_ticks_usec() - u0
		us_sum += u
		us_max = maxi(us_max, u)
		for k in spots.size():
			var p := spots[k]
			var d := t.river_dist(p, 1000.0)
			if k == 0:
				worst_b = minf(worst_b, d)
				if not t.river_clear(p, AASite.RIVER_REAL):
					near_b += 1
			else:
				worst_c = minf(worst_c, d)
				if not t.river_clear(p, AASite.CAR_RIVER_REAL):
					near_c += 1
			if t.in_water(p, 10.0):
				wet += 1
	print("UNIT: relief %d — closest bunker %.0f px, closest vehicle %.0f px from the river; place() %.1f ms avg, %.1f ms max" % [style, worst_b, worst_c, us_sum / 1000.0 / N, us_max / 1000.0])
	_check(near_b == 0, "relief %d: bunkers closer than %d px to the river: %d" % [style, AASite.RIVER_REAL, near_b])
	_check(near_c == 0, "relief %d: vehicles closer than %d px to the river: %d" % [style, AASite.CAR_RIVER_REAL, near_c])
	_check(wet == 0, "relief %d: AA points in water: %d" % [style, wet])


## RV-03: in the game the site is placed over built chunks, and the flatness checks read the drawn
## grid (Terrain3D.height_drawn) instead of the exact height: the rules must hold there too, and it
## must be cheaper than the exact path (it is the main-thread hitch when a site appears).
func _check_drawn(t: Terrain3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var cs := []
	var keys: Array[Vector2i] = []
	for i in 4:
		var c := Vector2(rng.randf_range(-30000.0, 30000.0), rng.randf_range(-30000.0, 30000.0))
		cs.append(c)
		var k := Vector2i(int(floorf(c.x / Terrain3D.CHUNK)), int(floorf(c.y / Terrain3D.CHUNK)))
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if not keys.has(k + Vector2i(dx, dz)):
					keys.append(k + Vector2i(dx, dz))
	t._build_now(keys)
	var bad := 0
	var us := [0, 0]
	for pass_i in 2:   # 0 — over the drawn grid, 1 — exact heights (grid dropped)
		for c: Vector2 in cs:
			var u0 := Time.get_ticks_usec()
			var spots := AASite.place(t, c, 0.7)
			us[pass_i] += Time.get_ticks_usec() - u0
			if pass_i == 0:
				for k in spots.size():
					var need := AASite.RIVER_REAL if k == 0 else AASite.CAR_RIVER_REAL
					if not t.river_clear(spots[k], need) or t.in_water(spots[k], 10.0):
						bad += 1
		t._hgrid.clear()
	print("UNIT: AA place over built chunks %.1f ms avg, exact heights %.1f ms avg" % [us[0] / 1000.0 / cs.size(), us[1] / 1000.0 / cs.size()])
	_check(bad == 0, "AA points over built chunks too close to the river or in water: %d" % bad)
	_check(us[0] < us[1], "placement over built chunks is cheaper than with exact heights")


## RV-05: the chunk snapshot splits side valleys and near streams per cell (ctx vsides/streams) only to
## save time; chunks built with and without the split must match exactly, also at village streams and
## for the coarse placeholder grid.
func _check_ctx_split(t: Terrain3D) -> void:
	var keys: Array[Vector2i] = []
	var r := 0
	while keys.size() < 3 and r < 40:
		for kx in range(-r, r + 1):
			for kz in range(-r, r + 1):
				if maxi(absi(kx), absi(kz)) != r:
					continue   # only the ring at distance r
				var k := Vector2i(kx, kz)
				var o := t._obj(k)
				if keys.size() < 3 and not o.is_empty() and o["name"] == "o_village":
					keys.append(k)
		r += 1
	_check(keys.size() == 3, "found 3 village chunks (%d)" % keys.size())
	var near := 0
	var same := 0
	for k in keys:
		var ctx := t._ctx(k)
		if not (ctx["streams"][k] as Array).is_empty():
			near += 1
		var old := ctx.duplicate()
		old.erase("vsides")
		old.erase("streams")
		var ok := true
		for lod in [0, Terrain3D.LOD_N]:
			var a := t._compute(k, ctx, t._gen, lod)
			var b := t._compute(k, old, t._gen, lod)
			for f in ["hs", "verts", "uv1", "uv2", "cols", "c0"]:
				ok = ok and a[f] == b[f]
		if ok:
			same += 1
	print("UNIT: ctx split — %d village chunks, %d with streams, %d identical" % [keys.size(), near, same])
	_check(near > 0, "a village chunk has its stream in the split list")
	_check(same == keys.size(), "chunks with the split ctx match the old build")
