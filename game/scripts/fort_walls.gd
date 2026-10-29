class_name FortWalls
extends FortYard
## The Highland fort's curtain walls: battered rammed-earth sections on a rubble-stone plinth that wander with the
## ground, their parapets, buttresses, balconies and repairs, and the breach a broken section opens (FortBuild
## extends it and lays the fort out; split from FortBuild for size). Preview units, ground at GROUND; the
## sections are FortBuild.WALLS, passed in as `w` = [id, a, b].

## Wall section profile (_wall_prm, _wall_prof): half bases at the ground, inner and outer, and the faces' top
const W_BI := 4.2
const W_BO := 4.6
const W_TI := 2.1
const W_TO := 2.35
const W_STEP := 1.2              ## wall sections are this long along the path


# ---------- curtain walls ----------

## Coordinate along the fort's side of section `w` at t (x on the north and south sides, z on the west and
## east) and that side's seed: the two sections of a side share both, so their shape runs on across the joint
## and the intact and broken meshes of a section match.
func _side(w: Array, t: float) -> Vector2:
	var a: Vector2 = w[1]
	var b: Vector2 = w[2]
	var p := a.lerp(b, t)
	var along_x := absf(b.y - a.y) < 0.01
	return Vector2(p.x if along_x else p.y, (11.0 if along_x else 23.0) + (a.y if along_x else a.x) * 0.13 + 7.0)


## Distance along section `w` from t to the nearest tower or gate bastion it runs into (the joint of a side's
## two sections in the middle is not an end).
func _end_dist(w: Array, t: float) -> float:
	var a: Vector2 = w[1]
	var b: Vector2 = w[2]
	var len := a.distance_to(b)
	var d := INF
	if _is_end(a):
		d = t * len
	if _is_end(b):
		d = minf(d, (1.0 - t) * len)
	return d


## A wall end that runs into a tower (fort corner) or a gate bastion (x ±12 on the gate side).
func _is_end(p: Vector2) -> bool:
	return (absf(p.x) == S and absf(p.y) == S) or (absf(p.x) == 12.0 and p.y == S)


## Point of section `w`'s wall line at t (0…1 from a to b), xz: the logic line, wandering up to ~2 units off it
## the way a wall laid along the ground does; on the line itself at the towers.
func _wall_at(w: Array, t: float) -> Vector2:
	var a: Vector2 = w[1]
	var b: Vector2 = w[2]
	var d := (b - a).normalized()
	var us := _side(w, t)
	var env := smoothstep(0.0, 16.0, _end_dist(w, t))
	var wob := (_n1(us.x / 15.0, us.y) - 0.5) * 3.8 + (_n1(us.x / 5.5, us.y + 3.0) - 0.5) * 0.9
	return a + (b - a) * t + Vector2(-d.y, d.x) * wob * env


## Unit direction of section `w`'s wall line at t, and its outward normal: [along, out] (Vector2, xz).
func _wall_dir(w: Array, t: float) -> Array:
	var d := (_wall_at(w, t + 0.004) - _wall_at(w, t - 0.004)).normalized()
	return [d, Vector2(-d.y, d.x) * float(w[3])]


## Shape numbers of section `w` at t: walk height hw, parapet crest hp, plinth tops pl (outside) and pi
## (inside), the inner face's bulge and the depth of a rain gully cut into the outer face (0…1).
func _wall_prm(w: Array, t: float) -> Dictionary:
	var us := _side(w, t)
	var sd := us.y
	var x := us.x
	var g := smoothstep(0.7, 0.86, _n1(x / 3.4, sd + 19.0)) * smoothstep(3.0, 6.0, _end_dist(w, t))
	var hw := 13.4 + (_n1(x / 17.0, sd + 5.0) - 0.5) * 1.8
	var hp := hw + 1.9 + (_n1(x / 4.5, sd + 11.0) - 0.5) * 1.3 - g * 1.3
	hp -= smoothstep(0.74, 0.9, _n1(x / 9.0, sd + 13.0)) * 0.9   # eroded stretches of parapet
	return {"hw": hw, "hp": maxf(hp, hw + 0.6), "g": g,
		"pl": GROUND + 2.0 + 1.6 * _n1(x / 21.0, sd + 7.0), "pi": GROUND + 0.9 + 0.8 * _n1(x / 13.0, sd + 8.0),
		"bulge": (_n1(x / 8.0, sd + 17.0) - 0.5) * 0.6}


## Outer face of a wall section `across` from its line at height y (battered, a gully dents it by g).
func _w_out(p: Dictionary, y: float) -> float:
	var hw: float = p["hw"]
	return W_BO - (W_BO - W_TO) * y / hw - float(p["g"]) * 0.9 * smoothstep(hw * 0.15, hw, y)


## Inner face of a wall section `across` from its line at height y, under a walk at hw (negative: inwards).
func _w_in(hw: float, y: float) -> float:
	return -(W_BI - (W_BI - W_TI) * y / hw)


## The wall's slope of the outer face (across per unit up)
func _w_slope() -> float:
	return (W_BO - W_TO) / 13.4


## Wall profile at shape numbers p: (across, y) from the inner foot over the walk and the parapet's rounded,
## eroded crest down the outer face to the outer foot (across > 0 outwards).
func _wall_prof(p: Dictionary) -> PackedVector2Array:
	var hw: float = p["hw"]
	var hp: float = p["hp"]
	var g: float = p["g"]
	var bu: float = p["bulge"]
	return PackedVector2Array([Vector2(_w_in(hw, 0.0), 0.0), Vector2(_w_in(hw, hw * 0.5) - bu, hw * 0.5),
		Vector2(_w_in(hw, hw - 0.7), hw - 0.7), Vector2(-2.25, hw + 0.25), Vector2(-1.8, hw + 0.45),
		Vector2(-1.45, hw), Vector2(0.9, hw), Vector2(1.0, hp - 0.35), Vector2(1.35, hp), Vector2(1.95, hp + 0.02),
		Vector2(2.3 - g * 0.9, hp - 0.4), Vector2(_w_out(p, hw), hw), Vector2(_w_out(p, hw * 0.7), hw * 0.7),
		Vector2(_w_out(p, hw * 0.35), hw * 0.35), Vector2(W_BO, 0.0)])


## Section `w`: whole, or blown through the middle (a gap ~20 wide whose stubs crumble into it with torn,
## irregular tops, slabs thrown both ways, a slumped cone of earth). Shape and dressing come from the
## section's own seed, so the two stubs of a breach are the wall that stood there.
func _wall(w: Array, broken: bool) -> void:
	var a: Vector2 = w[1]
	var len := a.distance_to(w[2])
	var runs := [[0.0, 1.0]]
	var gh := minf(22.0, len * 0.55) * 0.5 / len
	if broken:   # the full wall stops BREAK_BACK short of the gap; _crumble carries it on, falling
		runs = [[0.0, 0.5 - gh - BREAK_BACK / len], [0.5 + gh + BREAK_BACK / len, 1.0]]
	var feats := _wall_feats(w)
	for r: Array in runs:
		_wall_run(w, r[0], r[1], broken)
		var edge := (3.5 + BREAK_BACK if broken else 1.5) / len
		_wall_dress(w, feats, r[0] + edge, r[1] - edge)
	if broken:
		_rng.seed = hash(w[0]) + 9
		_crumble(w, 0.5 - gh - BREAK_BACK / len, 1.0)
		_crumble(w, 0.5 + gh + BREAK_BACK / len, -1.0)
		_rng.seed = hash(w[0]) + 5
		var c := _wall_at(w, 0.5)
		var dv: Array = _wall_dir(w, 0.5)
		var d: Vector2 = dv[0]
		var keep := _xf
		_xf = Transform3D(Basis(Vector3(d.x, 0, d.y), Vector3.UP, Vector3(-d.y, 0, d.x)), Vector3(c.x, 0.0, c.y))
		_breach(minf(22.0, len * 0.55), float(w[3]))
		_xf = keep


## Body (rammed earth) and the stone plinth skirts of section `w` from t0 to t1; `caps` closes the ends.
func _wall_run(w: Array, t0: float, t1: float, caps: bool) -> void:
	var a: Vector2 = w[1]
	var len := a.distance_to(w[2])
	var n := maxi(2, ceili((t1 - t0) * len / W_STEP)) + 1
	var path := PackedVector2Array()
	var body := []
	var po := []
	var pin := []
	for i in n:
		var t := lerpf(t0, t1, float(i) / (n - 1))
		var p := _wall_prm(w, t)
		path.append(_wall_at(w, t))
		body.append(_wall_prof(p))
		var pl: float = p["pl"]
		var pi: float = p["pi"]
		var hw: float = p["hw"]
		var xo := W_BO - (W_BO - W_TO) * pl / hw
		po.append(PackedVector2Array([Vector2(xo - 0.3, pl + 0.05), Vector2(xo + 0.45, pl), Vector2(W_BO + 0.95, GROUND - 0.7)]))
		var xi := -(W_BI - (W_BI - W_TI) * pi / hw)
		pin.append(PackedVector2Array([Vector2(-W_BI - 0.8, GROUND - 0.7), Vector2(xi - 0.4, pi), Vector2(xi + 0.25, pi + 0.05)]))
	var side := float(w[3])
	_sweep(M.MUD, path, body, side, caps)
	_sweep(M.STONE, path, po, side, caps)
	_sweep(M.STONE, path, pin, side, caps)


## Dressing of section `w`, planned for the whole section from its seed: [kind, t, size…]. Kinds: buttress,
## balcony, beam (outer / inner beam ends), loop (parapet loophole), slot (a low loophole), spout, patch,
## repair, scree.
func _wall_feats(w: Array) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash(w[0]) + 11
	var a: Vector2 = w[1]
	var len := a.distance_to(w[2])
	var out := []
	var x := r.randf_range(5.0, 9.0)
	var balc := []
	for k in (2 if len > 40.0 else 1):   # timber machicolation balconies
		var t := (k + 0.5) / (2.0 if len > 40.0 else 1.0) + r.randf_range(-0.12, 0.12)
		balc.append(t)
		out.append(["balcony", t, r.randf_range(4.0, 5.2)])
	while x < len - 6.0:   # semi-round buttresses, clear of the balconies
		var t := x / len
		var near := false
		for b: float in balc:
			near = near or absf(b - t) * len < 5.5
		if not near:
			out.append(["buttress", t, r.randf_range(1.7, 2.4), r.randf_range(0.5, 0.78)])
		x += r.randf_range(8.5, 13.0)
	for s: float in [1.0, -1.0]:   # beam ends of the walk's joists, both faces
		x = r.randf_range(1.5, 3.0)
		while x < len - 1.5:
			if r.randf() < 0.75:
				out.append(["beam", x / len, s, r.randf_range(-0.25, 0.25)])
			x += r.randf_range(2.1, 3.1)
	x = r.randf_range(2.0, 3.5)
	while x < len - 2.0:
		out.append(["loop", x / len])
		x += r.randf_range(2.4, 4.2)
	for k in r.randi_range(2, 4):
		out.append(["slot", r.randf_range(0.1, 0.9), r.randf_range(5.0, 9.0)])
	for k in r.randi_range(2, 3):
		out.append(["spout", r.randf_range(0.12, 0.88)])
	for p: Array in w[4]:
		out.append(["patch", 0.5 + float(p[0]) / len, p])
	for k in r.randi_range(1, 2):   # fallen plaster showing mud brick
		out.append(["patch", r.randf_range(0.15, 0.85), [0.0, r.randf_range(4.0, 9.0), r.randf_range(2.5, 5.0), r.randf_range(1.8, 3.5), M.BRICK]])
	for k in r.randi_range(1, 3):   # mud repairs: fresher, lighter plaster
		out.append(["repair", r.randf_range(0.1, 0.9), r.randf_range(1.5, 10.0), r.randf_range(3.0, 7.0), r.randf_range(2.0, 4.5)])
	for k in r.randi_range(2, 4):   # scree slumped at the foot, mostly outside
		out.append(["scree", r.randf_range(0.1, 0.9), 1.0 if r.randf() < 0.7 else -1.0, r.randf_range(2.5, 4.5), r.randf_range(1.0, 2.2)])
	return out


## Builds the features of `feats` whose t lies in [t0, t1].
func _wall_dress(w: Array, feats: Array, t0: float, t1: float) -> void:
	for f: Array in feats:
		var t: float = f[1]
		if t < t0 or t > t1:
			continue
		var c := _wall_at(w, t)
		var dv: Array = _wall_dir(w, t)
		var along: Vector2 = dv[0]
		var outv: Vector2 = dv[1]
		var p := _wall_prm(w, t)
		var hw: float = p["hw"]
		var zf := Vector3(outv.x, 0.0, outv.y)
		var xa := Vector3.UP.cross(zf)
		var fb := Basis(xa, Vector3.UP, zf)
		var at := func(across: float, y: float) -> Vector3: return Vector3(c.x + outv.x * across, y, c.y + outv.y * across)
		var tilt := fb * Basis(Vector3.RIGHT, -atan(_w_slope()))
		match String(f[0]):
			"buttress":
				_buttress(c, outv, float(f[2]), hw * float(f[3]))
			"balcony":
				if float(p["g"]) < 0.2:
					_balcony(at.call(_w_out(p, hw - 1.6), hw - 1.6), fb, float(f[2]), 2.0)
			"beam":
				var s: float = f[2]
				var y := hw - 2.3 + float(f[3])
				var face := _w_out(p, y) if s > 0.0 else -(W_BI - (W_BI - W_TI) * y / hw) - float(p["bulge"]) * 0.4
				_beam(at.call(face + s * 0.05, y), 1.4, zf * s, _r(-0.08, 0.04), M.WOOD, 0.24)
			"loop":
				if float(p["hp"]) > hw + 1.6:
					_boxr(M.DARK, Vector3(0.42, 0.95, 2.0), at.call(1.65, hw + 0.95), fb)
			"slot":
				var y: float = f[2]
				_boxr(M.DARK, Vector3(0.4, 1.3, 0.9), at.call(_w_out(p, y) - 0.25, y), tilt)
			"spout":
				_boxr(M.WOOD, Vector3(0.45, 0.32, 2.4), at.call(_w_out(p, hw) + 0.3, hw + 0.15), fb)
				_streak(at.call(_w_out(p, hw - 0.3), hw - 0.3), xa, zf, hw * _r(0.45, 0.7), 0.45)
			"patch":
				var pd: Array = f[2]
				if float(p["g"]) < 0.15:
					var y := float(pd[1]) + float(pd[3]) * 0.5
					var o: Vector3 = at.call(_w_out(p, y), y)
					var m: int = pd[4]
					_face_slab(m, o, xa, zf, _ragged(Vector2(pd[2], pd[3]) * 0.5, 10, 0.25), 0.05 if m == M.BRICK else 0.12)
			"repair":
				if float(p["g"]) < 0.15:
					var y: float = f[2] + float(f[4]) * 0.5
					_tint = Color(1.14, 1.1, 1.02)
					_face_slab(M.MUD, at.call(_w_out(p, y), y), xa, zf, _ragged(Vector2(f[3], f[4]) * 0.5, 8, 0.3), 0.1)
					_tint = Color.WHITE
			"scree":
				var s: float = f[2]
				var across := (W_BO + 1.2) if s > 0.0 else -(W_BI + 1.0)
				_tint = Color(0.92, 0.88, 0.84)
				_heap(M.MUD, c + outv * across, Vector2(float(f[3]), float(f[3]) * 0.55), float(f[4]), GROUND - 0.4, atan2(along.y, along.x))
				_tint = Color.WHITE


## Slab on a battered outer face (slope _w_slope) at o: u along the wall, zf outwards; outline pts in (u, up).
func _face_slab(m: int, o: Vector3, xa: Vector3, zf: Vector3, pts: PackedVector2Array, t: float) -> void:
	var s := _w_slope()
	var v := (Vector3.UP - zf * s).normalized()
	var n := (zf + Vector3.UP * s).normalized()
	_slab(m, o, xa, v, n, pts, t)


## Dark rain streak down a face from o (its top), `len` long, `wd` wide at the top, tapering: xa along the face,
## zf its outward normal (battered by the wall's slope).
func _streak(o: Vector3, xa: Vector3, zf: Vector3, len: float, wd: float) -> void:
	_tint = Color(0.74, 0.7, 0.66)
	var j := _r(-0.3, 0.3)
	_face_slab(M.MUD, o, xa, zf, PackedVector2Array([Vector2(-wd, 0.0), Vector2(wd, 0.0), Vector2(wd * 0.5 + j, -len * 0.6),
		Vector2(wd * 0.15 + j, -len), Vector2(-wd * 0.3 + j * 0.5, -len * 0.75)]), 0.07)
	_tint = Color.WHITE


## Semi-round buttress against a wall's outer face at c (wall line), `outv` outwards: radius rb at the foot,
## tapering and leaning with the face up to hb, a rounded, eroded top.
func _buttress(c: Vector2, outv: Vector2, rb: float, hb: float) -> void:
	var slope := _w_slope()
	var base := c + outv * (W_BO - rb * 0.35)
	var sd := c.x * 0.31 + c.y * 0.57   # from the place: the same buttress in the intact and broken wall
	var plan := func(a: float, y: float) -> Vector2:
		var rr := lerpf(rb, rb * 0.62, clampf(y / hb, 0.0, 1.0))
		if y > hb:
			var e := (y - hb) / (rb * 0.62)
			rr = rb * 0.62 * sqrt(maxf(0.0, 1.0 - e * e))
		rr *= 1.0 + 0.12 * _pn(a, y * 0.2, sd)
		return Vector2.from_angle(a) * rr - outv * slope * y
	var ys := PackedFloat32Array([GROUND - 0.6, GROUND + 1.5, hb * 0.35, hb * 0.7, hb])
	for e: float in [0.4, 0.7, 0.9, 0.99]:
		ys.append(hb + rb * 0.62 * e)
	_loft(M.MUD, base, plan, ys, 14, true)


## How far back from the gap a breached section's full wall stops; its broken end (_crumble) falls from there
const BREAK_BACK := 3.0
## How far into the gap the broken end reaches past the gap's edge
const BREAK_INTO := 6.5


## Broken end of a breached section `w`: from t0 (where the full wall stops) `dir` (+1 towards larger t) over
## BREAK_BACK + BREAK_INTO, the wall's own battered faces under a torn top that falls into the gap unevenly —
## shoulders, notches and a slumped tongue, never regular steps — with clods and a joist on the broken top.
func _crumble(w: Array, t0: float, dir: float) -> void:
	var len := (w[1] as Vector2).distance_to(w[2])
	var span := BREAK_BACK + BREAK_INTO
	var n := 22
	var sd := _rng.randf() * 30.0
	var hw: float = _wall_prm(w, t0)["hw"]
	var path := PackedVector2Array()
	var hs := PackedFloat32Array()
	for k in n + 1:
		var s := float(k) / n
		path.append(_wall_at(w, t0 + dir * s * span / len))
		var fall := pow(s, 1.25) * 0.9
		var rough := (_n1(s * 4.5, sd) - 0.5) * 0.42 + (_n1(s * 11.0, sd + 3.0) - 0.5) * 0.18
		var f := clampf(1.0 - fall + rough * smoothstep(0.0, 0.18, s), 0.07, 1.0)
		hs.append(maxf(hw * f, GROUND + 0.5))
	if dir < 0.0:   # the sweep runs from the gap towards the wall either way: keep the path in t order
		path.reverse()
		hs.reverse()
	_broken_end(M.MUD, path, hs, W_BI, W_BO, _w_slope(), float(w[3]))
	for j in 7:   # clods and chipped bricks lying on the torn top
		var s := _r(0.15, 0.95)
		var k := clampi(roundi(s * n), 0, n)
		var kk := k if dir > 0.0 else n - k
		var p := path[kk]
		var off: Vector2 = (_wall_dir(w, t0)[1] as Vector2) * _r(-1.6, 1.6)
		var y := hs[kk] + 0.2
		if _rng.randf() < 0.5:
			_chunk(M.RUB_BRICK if _rng.randf() < 0.6 else M.RUB_PLASTER, _r(0.35, 0.7), Vector3(p.x + off.x, y, p.y + off.y))
		else:
			_shard(M.RUB_BRICK, Vector3(0.62, 0.3, 0.32), Vector3(p.x + off.x, y, p.y + off.y), _tumble(0.4), 6)
	if _rng.randf() < 0.75:   # a joist of the walk snapped where the wall broke
		var p := path[n / 2]
		var d: Vector2 = _wall_dir(w, t0)[0]
		_beam(Vector3(p.x, hs[n / 2] - 0.4, p.y), _r(2.4, 3.8), Vector3(d.x * dir, 0, d.y * dir).rotated(Vector3.UP, _r(-0.5, 0.5)),
			_r(-0.2, 0.5))


## The hole of a blown wall section, `g` wide, in the section's own frame (x along, z the line's left normal;
## `out` — which z side faces outwards): stone stumps of the plinth, slabs thrown out and in, snapped joists, a
## slumped cone of earth and scattered debris (the stubs' broken ends are _crumble's).
func _breach(g: float, out: float) -> void:
	var x := -g * 0.5 + 0.6
	while x < g * 0.5 - 0.6:   # plinth stumps, broken off unevenly
		var sh := _r(GROUND + 0.4, GROUND + 2.2)
		_shard(M.STONE, Vector3(1.6, sh, 2.0 * W_BO + 0.6), Vector3(x, sh * 0.5, 0), Basis(Vector3.UP, _r(-0.1, 0.1)), 8)
		x += 1.4
	_tint = Color(0.95, 0.9, 0.84)
	_heap(M.MUD, Vector2(0.0, out * 2.5), Vector2(g * 0.5, 7.5), 4.2)   # the wall slumped into a cone of earth
	_heap(M.MUD, Vector2(_r(-4.0, 4.0), out * 9.0), Vector2(g * 0.35, 4.0), 2.0)
	_tint = Color.WHITE
	for i in 6:   # big slabs thrown outwards and inwards
		var sz := out * _r(5.0, 13.0) * (1.0 if i < 4 else -1.0)
		_shard(M.MUD if _rng.randf() < 0.7 else M.BRICK, Vector3(_r(3.0, 5.0), _r(0.8, 1.3), _r(4.0, 7.0)), Vector3(_r(-8.0, 8.0), GROUND + 0.2, sz), _tumble(0.35))
	for i in 5:   # parapet chunks
		_shard(M.MUD, Vector3(_r(2.0, 3.4), 1.8, 1.3), Vector3(_r(-10.0, 10.0), GROUND + 0.5, out * _r(-6.0, 14.0)), _tumble(1.0))
	_rubble(Vector3(0, GROUND + 1.0, out * 3.0), 130, 11.0, 2.2)
	_rubble(Vector3(0, GROUND, -out * 2.0), 60, 8.0, 1.8)
