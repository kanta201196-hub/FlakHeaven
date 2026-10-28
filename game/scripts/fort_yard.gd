class_name FortYard
extends FortKit
## The Highland fort's gate, fuel store, citadel and rooms, and the timber balconies and eroded parapets every
## part of the fort shares (FortWalls, then FortBuild, extend it; split from FortBuild for size). Preview
## units, gate in +z, ground at GROUND; the same mud, plaster, timber and stone as the curtain walls.

const TANKS_Z := [-12.0, -5.0, 2.0]   ## the fuel store's three tanks along z at x 30 (FortBuild.STORE_C)


## Timber machicolation balcony on a face: o — the face at the balcony's floor, fb — basis (x along the face, z
## outwards), `wdt` wide, `dep` deep. Corbel beams under a plank floor, mud-plastered front and sides with
## slits, a mud roof on poles. `burnt` leaves the charred corbels and a few planks.
func _balcony(o: Vector3, fb: Basis, wdt: float, dep: float, burnt := false) -> void:
	var keep := _xf
	_xf = _xf * Transform3D(fb, o)
	var wm := M.CHAR if burnt else M.WOOD
	for k in 3:
		var x := lerpf(-wdt * 0.5 + 0.4, wdt * 0.5 - 0.4, k / 2.0)
		_beam(Vector3(x, -0.35, dep * 0.5 - 0.5), dep + 1.2, Vector3.BACK, _r(-0.04, 0.02), wm, 0.26)
	if burnt:
		for k in 3:
			_boxr(M.CHAR, Vector3(_r(1.0, 2.5), 0.2, 0.35), Vector3(_r(-wdt, wdt) * 0.4, 0.0, _r(0.3, dep)), Basis(Vector3.UP, _r(-0.4, 0.4)))
		_xf = keep
		return
	_box(M.WOOD, Vector3(wdt + 0.3, 0.25, dep + 0.2), Vector3(0, -0.05, dep * 0.5 - 0.1))
	_box(M.PLASTER, Vector3(wdt, 2.3, 0.45), Vector3(0, 0.2, dep - 0.2))
	for s: float in [-1.0, 1.0]:
		_box(M.PLASTER, Vector3(0.4, 2.3, dep + 0.8), Vector3(s * (wdt * 0.5 - 0.2), 0.2, (dep - 0.8) * 0.5))
	_box(M.WOOD, Vector3(wdt + 0.7, 0.18, dep + 1.6), Vector3(0, 2.5, dep * 0.5 - 0.3), 0.0, 0.06)
	_box(M.PLASTER, Vector3(wdt + 0.5, 0.32, dep + 1.3), Vector3(0, 2.66, dep * 0.5 - 0.35), 0.0, 0.06)
	for x: float in [-wdt * 0.25, wdt * 0.25]:
		_box(M.DARK, Vector3(0.36, 0.95, 0.6), Vector3(x, 0.8, dep - 0.2))
	_xf = keep


## Eroded parapet along a path on an outer face line: `thick` thick inwards (across −), from y0 up to a wavy crest
## between hmin and hmax with a rounded top and notches; `side` as in _sweep (which way the left normal of the
## path points relative to outwards).
func _parapet(m: int, path: PackedVector2Array, side: float, y0: float, thick: float, hmin: float, hmax: float, sd: float, closed: bool) -> void:
	var profs := []
	var cum := 0.0
	for i in path.size():
		if i > 0:
			cum += path[i].distance_to(path[i - 1])
		var u := cum
		if closed and i == path.size() - 1:
			u = 0.0
		var hp := lerpf(hmin, hmax, _n1(u / 3.2, sd + 2.0))
		hp -= smoothstep(0.75, 0.9, _n1(u / 2.1, sd + 5.0)) * 0.8   # notches the rain has cut
		profs.append(PackedVector2Array([Vector2(-thick, y0 - 0.3), Vector2(-thick + 0.05, hp - 0.3), Vector2(-thick + 0.35, hp),
			Vector2(-0.3, hp + 0.03), Vector2(0.0, hp - 0.32), Vector2(0.03, y0 - 0.3)]))
	_sweep(m, path, profs, side, not closed, closed)


# ---------- gate ----------

## Gate bastion on side sx (base: stands in every state): a squat rounded-square tower either side of the
## passage, stone plinth, battered body, beam ends, an eroded parapet, loopholes, scree at its foot.
func _bastion(sx: float) -> void:
	var c := Vector2(sx * 10.5, S + 1.5)
	var top := 18.0
	var plan := func(a: float, y: float) -> Vector2:
		var f := clampf((y - GROUND) / (top - GROUND), 0.0, 1.0)
		return _rrect(a, lerpf(6.0, 4.9, f), lerpf(6.8, 5.6, f), 2.4) * (1.0 + 0.04 * _pn(a, y * 0.15, sx * 3.0))
	var grow := func(a: float, y: float) -> Vector2:
		var e := 0.9 - 0.5 * clampf((y - GROUND + 0.8) / 3.8, 0.0, 1.0)
		var o: Vector2 = plan.call(a, GROUND)
		return o + o.normalized() * e
	_loft(M.STONE, c, grow, PackedFloat32Array([GROUND - 0.8, GROUND + 1.2, GROUND + 3.0]), 48, false)
	var ys := PackedFloat32Array()
	var y := GROUND + 2.8
	while y < top:
		ys.append(y)
		y += 1.5
	ys.append(top)
	_loft(M.PLASTER, c, plan, ys, 48, false)
	var path := PackedVector2Array()
	var fill := PackedVector2Array()
	for k in 49:
		var a := float(k % 48) / 48.0 * TAU
		var o: Vector2 = plan.call(a, top)
		path.append(c + o + o.normalized() * 0.25)
		fill.append(c + o - o.normalized() * 0.9)
	var band := func(a: float, yy: float) -> Vector2:
		var o: Vector2 = plan.call(a, top)
		return o + o.normalized() * (0.0 if yy < top - 0.1 else 0.45)
	_loft(M.PLASTER, c, band, PackedFloat32Array([top - 1.2, top - 0.2, top, top + 0.6]), 48, false)
	_parapet(M.PLASTER, path, -1.0, top + 0.6, 1.1, top + 1.6, top + 2.6, sx * 7.0, true)
	var up := Vector3.UP
	for k in 48:
		_tri_n(M.PLASTER, Vector3(c.x, top, c.y), Vector3(fill[k].x, top, fill[k].y), Vector3(fill[k + 1].x, top, fill[k + 1].y), up, up, up)
	for k in 18:   # beam ends
		var a := (k + 0.5) / 18.0 * TAU
		var o: Vector2 = plan.call(a, top - 1.6)
		var n := o.normalized()
		_beam(Vector3(c.x + o.x, top - 1.6, c.y + o.y), 1.4, Vector3(n.x, 0, n.y), _r(-0.1, 0.03), M.WOOD, 0.24)
	for k in 5:   # loopholes
		var a := (k + _r(0.2, 0.8)) / 5.0 * TAU
		for yy: float in [7.0, 13.0]:
			var o: Vector2 = plan.call(a, yy)
			var n := o.normalized()
			var zf := Vector3(n.x, 0, n.y)
			_boxr(M.DARK, Vector3(0.5, 1.5, 1.0), Vector3(c.x + o.x - n.x * 0.3, yy, c.y + o.y - n.y * 0.3),
				Basis(Vector3.UP.cross(zf), Vector3.UP, zf) * Basis(Vector3.RIGHT, -0.12))
	_tint = Color(0.92, 0.88, 0.84)
	_heap(M.MUD, c + Vector2(sx * 5.0, 7.5), Vector2(3.0, 2.0), 1.4, GROUND - 0.4, 0.3 * sx)
	_tint = Color.WHITE


## The gate (breakable): a mud gatehouse over the passage between the bastions, a timber frame (posts and a
## lintel of three squared beams), two plank leaves with battens, a machicolation balcony over the gate and a
## parapet. `blown` — the gatehouse front collapsed into the passage, the lintel snapped, one leaf hanging off its
## hinge, the other flat, charred planks, soot and a cone of rubble spilling out.
func _gate(blown := false) -> void:
	var zf := S + 5.2   # the gatehouse's front face at the bottom
	var fbz := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	if not blown:
		var keep := _xf
		_prism(M.MUD, PackedVector2Array([Vector2(S - 4.0, 9.6), Vector2(S - 3.8, 17.4), Vector2(zf - 0.6, 17.4), Vector2(zf, 9.6)]), 10.8)
		_xf = keep
		_parapet(M.MUD, PackedVector2Array([Vector2(-5.6, zf - 0.55), Vector2(-2.0, zf - 0.6), Vector2(2.0, zf - 0.6), Vector2(5.6, zf - 0.55)]),
			1.0, 17.4, 1.1, 18.6, 19.6, 4.0, false)
		for x in range(-5, 6, 2):   # beam ends under the parapet
			_beam(Vector3(x + 0.3, 16.6, zf - 0.6), 1.3, Vector3.BACK, 0.0, M.WOOD, 0.24)
		_balcony(Vector3(0.0, 12.2, zf - 0.3), fbz, 6.0, 2.0)
		for s: float in [-1.0, 1.0]:   # posts against the bastions
			_box(M.WOOD, Vector3(0.75, 9.0, 0.75), Vector3(s * 4.4, GROUND - 0.5, zf + 0.15))
		for k in 3:   # the lintel: three squared beams, ends sticking out
			_box(M.WOOD, Vector3(11.6 - k * 0.6, 0.55, 0.75), Vector3(_r(-0.2, 0.2), 8.5 + k * 0.56, zf + 0.15))
		for s: float in [-1.0, 1.0]:   # the leaves, battens on the outside
			_box(M.WOOD, Vector3(4.1, 8.0, 0.4), Vector3(s * 2.1, GROUND - 0.4, zf - 0.1))
			for y: float in [2.6, 5.0, 7.4]:
				_box(M.WOOD, Vector3(3.8, 0.35, 0.16), Vector3(s * 2.1, y, zf + 0.15))
		_box(M.DARK, Vector3(0.14, 8.0, 0.46), Vector3(0.0, GROUND - 0.4, zf - 0.1))
		return
	_box(M.DARK, Vector3(8.2, 8.6, 8.0), Vector3(0.0, GROUND - 0.6, S + 1.0))   # the passage, open now
	for s: float in [-1.0, 1.0]:   # stubs of the gatehouse front either side
		var h := _r(13.0, 16.5)
		_boxr(M.MUD, Vector3(2.6, h - 9.6, 8.6), Vector3(s * 4.0, 9.6 + (h - 9.6) * 0.5, S + 0.9), Basis(Vector3.BACK, s * _r(0.02, 0.08)))
		_boxr(M.BRICK, Vector3(0.6, h - 10.4, 7.6), Vector3(s * 2.65, 9.6 + (h - 10.4) * 0.5, S + 0.9), Basis(Vector3.BACK, s * 0.05))
	_box(M.CHAR, Vector3(0.75, 9.0, 0.75), Vector3(-4.4, GROUND - 0.5, zf + 0.15))
	_boxr(M.CHAR, Vector3(0.75, 8.6, 0.75), Vector3(4.9, 4.6, zf + 0.9), Basis(Vector3.BACK, -0.22))
	_boxr(M.CHAR, Vector3(6.4, 0.55, 0.75), Vector3(-2.2, 8.4, zf + 0.15), Basis(Vector3.BACK, -0.28))   # lintel snapped and sagging
	_boxr(M.CHAR, Vector3(5.8, 0.55, 0.75), Vector3(3.0, 3.0, zf + 2.0), Basis(Vector3.UP, 0.4) * Basis(Vector3.BACK, 0.9))
	_boxr(M.CHAR, Vector3(4.1, 8.0, 0.4), Vector3(-4.6, 4.2, zf + 2.0), Basis(Vector3.UP, -0.95) * Basis(Vector3.BACK, 0.06))   # hanging leaf
	_boxr(M.CHAR, Vector3(4.1, 0.4, 8.0), Vector3(1.8, GROUND + 0.5, zf + 4.5), Basis(Vector3.UP, 0.25))   # leaf flat
	for k in 10:
		_boxr(M.CHAR, Vector3(_r(1.2, 3.0), 0.3, _r(0.4, 0.7)), Vector3(_r(-7.0, 7.0), GROUND + 0.3, zf + _r(1.0, 13.0)), Basis(Vector3.UP, _rng.randf() * 3.0))
	for k in 4:   # balcony corbels and the gatehouse's beams thrown out
		_beam(Vector3(_r(-5.0, 5.0), GROUND + 0.8, zf + _r(2.0, 8.0)), _r(2.0, 4.0), Vector3(_r(-1, 1), 0, _r(-1, 1)), _r(-0.2, 0.3), M.CHAR)
	_tint = Color(0.95, 0.9, 0.84)
	_heap(M.MUD, Vector2(0.0, S + 1.0), Vector2(4.6, 5.0), 3.2)
	_heap(M.MUD, Vector2(0.5, zf + 4.0), Vector2(6.0, 4.0), 2.0)
	_tint = Color.WHITE
	_rubble(Vector3(0, GROUND + 1.0, S + 2.0), 50, 6.0, 1.4)
	_rubble(Vector3(0, GROUND, zf + 5.0), 40, 7.0, 1.2)
	for s: float in [-1.0, 1.0]:   # soot up the bastions' faces by the passage
		var o := Vector3(s * 4.62, 10.0, S + 2.5)
		_slab(M.SOOT, o, Vector3.BACK, Vector3.UP, Vector3(-s, 0, 0), _ragged(Vector2(2.6, 5.0), 9, 0.3), 0.05)
		var p := Vector3(s * 6.5, 9.0, S + 1.5 + 6.3)
		_slab(M.SOOT, p, Vector3.RIGHT, Vector3.UP, Vector3.BACK, _ragged(Vector2(1.6, 4.5), 8, 0.35), 0.15)


# ---------- store ----------

## Fuel store: three tanks on saddles under a camouflage net, earth berms on its open sides. `burnt` — went up:
## two soot-black tanks left, one burst and tipped onto its saddle, the net gone, the ground charred.
func _store(burnt: bool) -> void:
	_tint = Color(0.9, 0.86, 0.82)
	_heap(M.MUD, Vector2(39.0, -5.0), Vector2(2.4, 11.5), 2.2)
	_heap(M.MUD, Vector2(30.0, -18.0), Vector2(8.0, 2.2), 2.0)
	_tint = Color.WHITE
	if not burnt:
		for z: float in TANKS_Z:
			_fuel_tank(30.0, z, 0.1)
		_camo_net(31.0, -5.0, 0.1)
		return
	_fuel_tank(30.0, -12.0, 0.1, M.SOOT)
	_fuel_tank(31.0, -4.0, 0.5, M.SOOT, 0.35, 1.2)
	_slab(M.CHAR, Vector3(30.0, GROUND + 0.02, -5.0), Vector3.RIGHT, Vector3.BACK, Vector3.UP, _ragged(Vector2(8.0, 12.0), 12, 0.25), 0.05)
	_rubble(Vector3(30, GROUND, 1), 25, 5.0, 1.2)
	for k in 8:
		_boxr(M.SOOT, Vector3(_r(1.0, 2.6), 0.15, _r(0.6, 1.4)), Vector3(30.0 + _r(-6.0, 6.0), GROUND + 0.2, -5.0 + _r(-10.0, 10.0)), _tumble(0.5))


## Fuel store tank on two steel saddles; `m` OLIVE, or SOOT when burnt out; `tip` rolls it about its long axis
## and `lift` raises it (a burst tank half off its saddle).
func _fuel_tank(x: float, z: float, ry: float, m := M.OLIVE, tip := 0.0, lift := 0.0) -> void:
	var keep := _xf
	_xf = _xf * Transform3D(Basis(Vector3.UP, ry), Vector3(x, GROUND - 0.3, z))
	var body := _xf
	_xf = body * Transform3D(Basis(Vector3.BACK, tip), Vector3(0, lift, 0))
	_cyl(m, 2.1, 2.1, 8.0, 20, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(4.0, 2.9, 0)))
	for s: float in [-1.0, 1.0]:
		_half_dome(m, 2.1, Vector3(s * 4.0, 2.9, 0), s)
	_cyl(M.STEEL if m == M.OLIVE else m, 0.5, 0.5, 0.8, 10, _at(1.0, 4.8, 0.0))
	_xf = body
	for s: float in [-1.0, 1.0]:
		_box(M.STEEL if m == M.OLIVE else m, Vector3(0.7, 2.2, 3.6), Vector3(s * 3.0, 0, 0))
	_xf = keep


## Camouflage net over the store: sags between its poles, edges hanging down to ~0.7 m over the ground.
func _camo_net(x: float, z: float, ry: float) -> void:
	var nx := 16
	var nz := 12
	var keep := _xf
	_xf = _xf * Transform3D(Basis(Vector3.UP, ry), Vector3(x, GROUND - 0.3, z))
	var g := []
	for i in nx + 1:
		var col := []
		for j in nz + 1:
			var px := -11.0 + 22.0 * i / nx
			var pz := -8.0 + 16.0 * j / nz
			var e := minf(1.0, minf(11.0 - absf(px), 8.0 - absf(pz)) / 3.5)
			col.append(_xf * Vector3(px, 6.2 - (1.0 - e) * 5.5 + sin(px * 0.8) * cos(pz * 0.7) * 0.35, pz))
		g.append(col)
	var below := _xf * Vector3(0, -40.0, 0)
	for i in nx:
		for j in nz:
			_quad(M.NET, g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j + 1], below)
	_xf = keep


## Three courses of sandbags in a ring at height y, open towards `gap_a` (the yard side).
func _sandbag_ring(x: float, y: float, z: float, r: float, gap_a: float) -> void:
	var n := roundi(r * TAU / 1.7)
	for k in 3:
		for i in n:
			var a := (i + (k % 2) * 0.5) / n * TAU
			if absf(wrapf(a - gap_a, -PI, PI)) < 0.45:
				continue
			var rr := r - k * 0.15
			var yaw := -a + PI * 0.5 + _rng.randf_range(-0.15, 0.15)
			var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, 0.62, 0.95))
			var c := Vector3(x + cos(a) * rr, y + 0.36 + k * 0.66, z + sin(a) * rr) + b * Vector3(0.95, 0, 0)   # centre the bag
			_cyl(M.BAG, 0.55, 0.55, 1.9, 8, Transform3D(b * Basis(Vector3.BACK, PI * 0.5), c))


# ---------- citadel and rooms ----------

## Citadel and the rooms along the inner walls: a lower hall with a roof terrace (pergola, firewood, jars, a
## hatch), an ayvan porch at its door and an outside stair up to the terrace; an upper hall with a rooftop room
## reached by a ladder; the keep with two machicolation balconies. `burnt` (FA-04, the fort taken): the upper
## hall gutted — roof fallen in, ragged walls, charred beams sticking out — soot over every opening, char on the
## roofs, the porch and balconies burnt.
func _citadel(burnt := false) -> void:
	_hall(Vector2(-6, -16), 16.0, 11.0, 12.0, 0.0, M.PLASTER, [0, 1, 2], 1, -2.0, burnt)
	_porch(Vector2(-2.0, -1.4), 13.0, 3.6, 4.6, Vector3.BACK, burnt)
	_stair(burnt)
	if burnt:
		_hall_ruin(Vector2(-10, -18), 8.0, 6.0, 12.0)
	else:
		_hall(Vector2(-10, -18), 8.0, 6.0, 6.0, 12.0, M.PLASTER, [1, 2], 0, 1.5, false)
		_hall(Vector2(-13.5, -20.0), 2.6, 2.4, 2.6, 18.0, M.MUD, [0], 1, 0.0, false)
		_ladder(Vector3(0.4, 12.0, -15.0), Vector3(-1.9, 18.0, -15.0))
	_terrace(burnt)
	_keep(burnt)
	_hall(Vector2(-30, 32), 9.0, 4.5, 7.0, 0.0, M.MUD, [3], 3, 2.0, burnt)
	_hall(Vector2(28, -34), 11.0, 4.5, 8.0, 0.0, M.MUD, [1], 1, -4.0, burnt)
	if not burnt:
		_hall(Vector2(33.0, -35.0), 4.0, 3.2, 3.0, 8.0, M.MUD, [1], 1, 0.0, false)
	_porch(Vector2(24.0, -26.5), 12.0, 3.0, 4.0, Vector3.BACK, burnt)
	_hall(Vector2(34, 18), 4.5, 10.0, 6.0, 0.0, M.MUD, [2], 2, -3.0, burnt)


## Offset of a hall's outline (rounded rectangle, half sizes hx, hz at its foot, battered by `bat` per unit up)
## at angle a and height y above its foot.
func _hp(a: float, y: float, hx: float, hz: float, sd: float) -> Vector2:
	var bat := 0.055
	return _rrect(a, hx - bat * y, hz - bat * y, 1.2) * (1.0 + 0.012 * _pn(a, y * 0.2, sd))


## Flat-roofed adobe hall at c, half sizes hx, hz, h high from y0, in material m: battered rounded body on a stone
## plinth (on the ground), an eroded parapet round the roof, beam ends of the roof joists, windows with timber
## lintels on the faces in `wins` (0 +x, 1 +z, 2 −x, 3 −z), a door on face `door` at `du` along it. `burnt` —
## soot licking up over the openings, char on the roof.
func _hall(c: Vector2, hx: float, hz: float, h: float, y0: float, m: int, wins: Array, door: int, du: float, burnt: bool) -> void:
	var sd := c.x * 0.37 + c.y * 0.11
	var seg := 64
	var body := func(a: float, y: float) -> Vector2: return _hp(a, y - y0, hx, hz, sd)
	if y0 < GROUND:
		var pl := func(a: float, y: float) -> Vector2:
			var o := _hp(a, 0.0, hx, hz, sd)
			return o + o.normalized() * (0.55 - 0.3 * clampf((y - GROUND + 0.6) / 2.4, 0.0, 1.0))
		_loft(M.STONE, c, pl, PackedFloat32Array([GROUND - 0.6, GROUND + 1.8]), seg, false)
	var ys := PackedFloat32Array()
	var y := maxf(y0, GROUND + 1.6)
	while y < y0 + h:
		ys.append(y)
		y += 2.0
	ys.append(y0 + h)
	_loft(m, c, body, ys, seg, false)
	var top := y0 + h
	var path := PackedVector2Array()
	var fill := PackedVector2Array()
	for k in seg + 1:
		var a := float(k % seg) / seg * TAU
		var o := _hp(a, h, hx, hz, sd)
		path.append(c + o + o.normalized() * 0.12)
		fill.append(c + o - o.normalized() * 0.6)
	_parapet(m, path, -1.0, top, 0.8, top + 0.7, top + 1.4, sd, true)
	var up := Vector3.UP
	var rm := M.CHAR if burnt else m
	for k in seg:
		_tri_n(m, Vector3(c.x, top, c.y), Vector3(fill[k].x, top, fill[k].y), Vector3(fill[k + 1].x, top, fill[k + 1].y), up, up, up)
	if burnt:
		_slab(rm, Vector3(c.x + _r(-2.0, 2.0), top + 0.02, c.y), Vector3.RIGHT, Vector3.BACK, Vector3.UP, _ragged(Vector2(hx, hz) * 0.6, 11, 0.3), 0.04)
	for f in 4:
		var n := Vector2.from_angle(f * PI * 0.5)
		var dist := hx if f % 2 == 0 else hz
		var side := hz if f % 2 == 0 else hx
		var xa := Vector3(-n.y, 0.0, n.x)
		var zf := Vector3(n.x, 0.0, n.y)
		var fb := Basis(Vector3.UP.cross(zf), Vector3.UP, zf)
		var face := func(u: float, yy: float) -> Vector3:
			var d := dist - 0.055 * (yy - y0)
			var q := c + n * d + Vector2(xa.x, xa.z) * u
			return Vector3(q.x, yy, q.y)
		var u := -side + 1.6
		while u < side - 1.2:   # beam ends of the roof joists
			if _rng.randf() < 0.85:
				_beam(face.call(u, top - 0.9) + zf * 0.1, 1.3, zf, _r(-0.08, 0.03), M.CHAR if burnt else M.WOOD, 0.22)
			u += _r(1.4, 2.0)
		if f in wins:
			u = -side + 2.5
			while u < side - 2.0:
				if f == door and absf(u - du) < 2.5:
					u += 3.6
					continue
				var wy := y0 + minf(h * 0.55, 5.0)
				_boxr(M.DARK, Vector3(1.1, 1.6, 0.8), face.call(u, wy) - zf * 0.25, fb)
				_boxr(M.WOOD, Vector3(1.8, 0.3, 0.6), face.call(u, wy + 1.0) - zf * 0.1, fb)
				if burnt:
					_soot(face.call(u, wy + 0.8), xa, zf, minf(h - (wy - y0) - 0.5, 4.0))
				u += _r(3.4, 4.6)
		if f == door:
			var dy := maxf(y0, GROUND - 0.2)
			_boxr(M.DARK, Vector3(2.2, 3.4, 0.8), face.call(du, dy + 1.7) - zf * 0.25, fb)
			_boxr(M.CHAR if burnt else M.WOOD, Vector3(3.4, 0.42, 0.7), face.call(du, dy + 3.6) - zf * 0.05, fb)
			for s: float in [-1.0, 1.0]:
				_boxr(M.CHAR if burnt else M.WOOD, Vector3(0.34, 3.4, 0.5), face.call(du + s * 1.25, dy + 1.7) - zf * 0.05, fb)
			if burnt:
				_soot(face.call(du, dy + 3.4), xa, zf, 4.0)


## Soot licking up a battered face from o (over an opening), `len` high: xa along the face, zf outwards.
func _soot(o: Vector3, xa: Vector3, zf: Vector3, len: float) -> void:
	var s := 0.055
	var v := (Vector3.UP - zf * s).normalized()
	var n := (zf + Vector3.UP * s).normalized()
	var w := _r(0.9, 1.3)
	_slab(M.SOOT, o, xa, v, n, PackedVector2Array([Vector2(-w, 0.0), Vector2(w, 0.0), Vector2(w * 0.8, len * 0.5), Vector2(w * 0.3, len),
		Vector2(-w * 0.2, len * 0.75), Vector2(-w * 0.7, len * 0.55)]), 0.06)


## The upper hall gutted by fire: its walls standing to ragged heights round a heap of fallen roof, charred
## beams sticking out over them.
func _hall_ruin(c: Vector2, hx: float, hz: float, y0: float) -> void:
	var sd := c.x * 0.37 + c.y * 0.11
	var path := PackedVector2Array()
	var profs := []
	for k in 49:
		var a := float(k % 48) / 48.0 * TAU
		path.append(c + _hp(a, 0.0, hx, hz, sd))
		var top := y0 + 6.0 * (0.55 + 0.45 * _n1(float(k % 48) / 3.0, 7.0))
		profs.append(PackedVector2Array([Vector2(-1.1, y0 - 0.2), Vector2(-1.0, top - 0.2), Vector2(-0.5, top + 0.15),
			Vector2(-0.05, top - 0.25), Vector2(0.0, y0 - 0.2)]))
	_sweep(M.PLASTER, path, profs, -1.0, false, true)
	_tint = Color(0.6, 0.55, 0.5)
	_heap(M.RUB_PLASTER, c, Vector2(hx - 1.0, hz - 1.0), 3.5, y0 - 0.2)
	_tint = Color.WHITE
	_rubble(Vector3(c.x, y0 + 2.0, c.y), 45, 5.0, 1.2)
	for k in 6:
		var a := _rng.randf() * TAU
		_beam(Vector3(c.x + cos(a) * hx * 0.6, y0 + _r(3.0, 5.5), c.y + sin(a) * hz * 0.6), _r(3.5, 6.0), Vector3(cos(a), 0, sin(a)), _r(-0.5, 0.4), M.CHAR)
	_slab(M.CHAR, Vector3(c.x, y0 + 0.03, c.y + 3.0), Vector3.RIGHT, Vector3.BACK, Vector3.UP, _ragged(Vector2(hx + 3.0, hz + 4.0), 12, 0.3), 0.04)
	for k in 4:
		var p := Vector3(c.x + _r(-hx, hx), y0 + 0.05 + 0.01 * k, c.y + _r(-hz, hz) + 6.0)
		_slab(M.SOOT, p, Vector3.RIGHT, Vector3.BACK, Vector3.UP, _ragged(Vector2(_r(2.0, 4.0), _r(1.5, 3.0)), 9, 0.3), 0.04)


## Ayvan: a timber porch roof on posts at c (front edge centre), `wdt` wide, `dep` deep, h high, in front of the face
## whose outward normal is `n`. `burnt` — charred posts, the roof slumped off one side.
func _porch(c: Vector2, wdt: float, dep: float, h: float, n: Vector3, burnt: bool) -> void:
	var zf := n
	var xa := Vector3.UP.cross(zf)
	var keep := _xf
	_xf = _xf * Transform3D(Basis(xa, Vector3.UP, zf), Vector3(c.x, 0.0, c.y))
	var wm := M.CHAR if burnt else M.WOOD
	var np := 4 if wdt > 10.0 else 3
	for k in np:
		var x := lerpf(-wdt * 0.5 + 0.5, wdt * 0.5 - 0.5, float(k) / (np - 1))
		if burnt and k == np - 1:
			_boxr(wm, Vector3(0.45, h, 0.45), Vector3(x + 1.0, GROUND + 0.4, 0.8), Basis(Vector3.BACK, PI * 0.47))
			continue
		_box(wm, Vector3(0.45, h + 0.6, 0.45), Vector3(x, GROUND - 0.5, 0.0))
		_box(wm, Vector3(0.9, 0.35, 0.9), Vector3(x, GROUND + h - 0.2, 0.0))   # capital block
	_box(wm, Vector3(wdt + 0.6, 0.5, 0.55), Vector3(0, GROUND + h + 0.1, 0.0))
	for k in int(wdt / 1.2):
		_box(wm, Vector3(0.26, 0.26, dep + 0.7), Vector3(-wdt * 0.5 + 0.5 + k * 1.2, GROUND + h + 0.6, -dep * 0.5 + 0.3))
	if burnt:
		_boxr(M.MUD, Vector3(wdt * 0.6, 0.4, dep + 0.6), Vector3(wdt * 0.15, GROUND + h * 0.55, -dep * 0.4), Basis(Vector3.BACK, -0.45))
	else:
		_box(M.MUD, Vector3(wdt + 0.8, 0.45, dep + 0.9), Vector3(0, GROUND + h + 0.86, -dep * 0.5 + 0.25), 0.0, -0.03)
	_xf = keep


## Outside stair up the lower hall's west face to its roof terrace: solid mud steps with a low side wall.
func _stair(burnt: bool) -> void:
	var x0 := -22.2
	var z0 := -4.0
	var z1 := -25.0
	var n := 16
	for k in n:
		var top := GROUND + (12.0 - GROUND) * (k + 1) / n
		var z := lerpf(z0, z1, (k + 0.5) / n)
		_box(M.MUD, Vector3(4.2, top + 0.5, (z0 - z1) / n + 0.05), Vector3(x0 - 1.1, -0.5, z))
	var keep := _xf
	var ang := atan2(12.0 - GROUND, z0 - z1)
	var len := Vector2(z0 - z1, 12.0 - GROUND).length()
	_xf = _xf * Transform3D(Basis(Vector3.RIGHT, ang), Vector3(x0 - 3.3, GROUND + (12.0 - GROUND) * 0.5 + 0.6, (z0 + z1) * 0.5))
	_boxr(M.MUD, Vector3(0.6, 1.5, len), Vector3.ZERO, Basis.IDENTITY)
	_xf = keep
	if burnt:
		_soot(Vector3(x0 - 3.6, 6.0, -12.0), Vector3.BACK, Vector3.LEFT, 4.0)


## Ladder leaning from a to b.
func _ladder(a: Vector3, b: Vector3) -> void:
	var d := b - a
	for s: float in [-0.45, 0.45]:
		_beam((a + b) * 0.5 + Vector3(0, 0, s), d.length() + 0.6, Vector3(d.x, 0, d.z) if absf(d.x) + absf(d.z) > 0.01 else Vector3.RIGHT,
			atan2(d.y, Vector2(d.x, d.z).length()), M.WOOD, 0.12)
	for k in 9:
		var p := a.lerp(b, (k + 0.5) / 9.0)
		_boxr(M.WOOD, Vector3(0.14, 0.14, 1.0), p, Basis.IDENTITY)


## The lower hall's roof terrace: a pergola, firewood, water jars and a hatch (char and soot when burnt).
func _terrace(burnt: bool) -> void:
	var y := 12.0
	var wm := M.CHAR if burnt else M.WOOD
	for p: Vector2 in [Vector2(1.0, -6.5), Vector2(7.0, -6.5), Vector2(1.0, -10.5), Vector2(7.0, -10.5)]:
		_box(wm, Vector3(0.3, 2.7, 0.3), Vector3(p.x, y, p.y))
	if not burnt:
		for z: float in [-6.5, -10.5]:
			_box(wm, Vector3(6.6, 0.25, 0.3), Vector3(4.0, y + 2.7, z))
		for k in 6:
			_box(wm, Vector3(0.18, 0.18, 5.0), Vector3(1.2 + k * 1.15, y + 2.95, -8.5))
	for k in 9:   # firewood stack
		_beam(Vector3(2.5, y + 0.3 + floorf(k / 3.0) * 0.38, -14.0 + (k % 3) * 0.4), 2.6, Vector3.RIGHT, 0.0, wm, 0.18)
	if not burnt:
		for k in 3:   # water jars
			var jar := func(a: float, yy: float) -> Vector2:
				var f := (yy - y) / 1.0
				return Vector2.from_angle(a) * (0.32 + 0.22 * sin(clampf(f, 0.0, 1.0) * PI * 0.9))
			_loft(M.BRICK, Vector2(5.5 + k * 0.9, -13.0 + (k % 2) * 0.7), jar, PackedFloat32Array([y, y + 0.3, y + 0.6, y + 0.95, y + 1.05]), 10, true)
	_box(M.DARK, Vector3(1.4, 0.06, 1.4), Vector3(-18.0, y + 0.01, -10.0))
	_box(wm, Vector3(1.9, 0.18, 1.9), Vector3(-18.0, y, -10.0))


## The keep: a tall battered rounded-square tower on the citadel, three rows of beam ends, loopholes, two timber
## balconies (+z and +x), an eroded parapet round its roof. `burnt` — balconies burnt to their corbels, soot.
func _keep(burnt: bool) -> void:
	var c := Vector2(6, -22)
	var top := 27.0
	var plan := func(a: float, y: float) -> Vector2:
		var f := clampf(y / top, 0.0, 1.0)
		return _rrect(a, lerpf(4.9, 3.8, f), lerpf(4.9, 3.8, f), 1.3) * (1.0 + 0.02 * _pn(a, y * 0.2, 5.0))
	var ys := PackedFloat32Array()
	var y := GROUND - 0.5
	while y < top:
		ys.append(y)
		y += 1.6
	ys.append(top)
	_loft(M.PLASTER, c, plan, ys, 48, false)
	var path := PackedVector2Array()
	var fill := PackedVector2Array()
	for k in 49:
		var a := float(k % 48) / 48.0 * TAU
		var o: Vector2 = plan.call(a, top)
		path.append(c + o + o.normalized() * 0.3)
		fill.append(c + o - o.normalized() * 0.5)
	var band := func(a: float, yy: float) -> Vector2:
		var o: Vector2 = plan.call(a, top)
		return o + o.normalized() * (0.0 if yy < top - 0.1 else 0.4)
	_loft(M.PLASTER, c, band, PackedFloat32Array([top - 1.0, top - 0.2, top, top + 0.5]), 48, false)
	_parapet(M.PLASTER, path, -1.0, top + 0.5, 0.9, top + 1.3, top + 2.2, 9.0, true)
	var up := Vector3.UP
	for k in 48:
		_tri_n(M.CHAR if burnt else M.PLASTER, Vector3(c.x, top, c.y), Vector3(fill[k].x, top, fill[k].y), Vector3(fill[k + 1].x, top, fill[k + 1].y), up, up, up)
	for yy: float in [17.2, 25.8]:
		for k in 16:
			var a := (k + 0.5) / 16.0 * TAU
			var o: Vector2 = plan.call(a, yy)
			var n := o.normalized()
			if _rng.randf() < 0.85:
				_beam(Vector3(c.x + o.x, yy, c.y + o.y), 1.3, Vector3(n.x, 0, n.y), _r(-0.08, 0.03), M.CHAR if burnt else M.WOOD, 0.22)
	for k in 8:
		var a := (k + _r(0.2, 0.8)) / 8.0 * TAU
		var yy := _r(14.0, 24.0)
		var o: Vector2 = plan.call(a, yy)
		var n := o.normalized()
		var zf := Vector3(n.x, 0, n.y)
		var p := Vector3(c.x + o.x - n.x * 0.3, yy, c.y + o.y - n.y * 0.3)
		_boxr(M.DARK, Vector3(0.45, 1.4, 1.0), p, Basis(Vector3.UP.cross(zf), Vector3.UP, zf) * Basis(Vector3.RIGHT, -0.04))
		if burnt:
			_soot(p + zf * 0.3 + Vector3.UP * 0.6, Vector3.UP.cross(zf), zf, 3.0)
	for b: Array in [[Vector3.BACK, 20.0, 4.2], [Vector3.RIGHT, 14.5, 3.4]]:
		var zf: Vector3 = b[0]
		var yy: float = b[1]
		var o: Vector2 = plan.call(atan2(zf.z, zf.x), yy)
		_balcony(Vector3(c.x + o.x, yy, c.y + o.y) - zf * 0.1, Basis(Vector3.UP.cross(zf), Vector3.UP, zf), float(b[2]), 1.8, burnt)
