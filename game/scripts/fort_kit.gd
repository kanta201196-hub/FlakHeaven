class_name FortKit
extends RefCounted
## Geometry kit of the Highland fort (FortBuild extends it): surfaces per piece and material, primitives in the
## fort's preview units (≈ metres) through a group transform, hand-built shapes (lofted rings, swept wall
## profiles, earth heaps) and the destruction kit (rubble, chunks, snapped beams). Split out of FortBuild so the
## fort's layout reads apart from the mesh plumbing. Every vertex carries a colour: a tone the builder sets
## (_tint, patches and repairs) times a damp, darker foot on the earthen materials, read by fort.gdshader.

## Surface materials of the fort (FortBuild.material). MUD — rammed earth and mud-brick walls (the plaster set
## graded darker, with earth courses); PLASTER — the lighter mud-lime plaster of towers, citadel and rooms.
enum M { PLASTER, STONE, BRICK, CONC, WOOD, DARK, BAG, OLIVE, STEEL, RUB_PLASTER, RUB_BRICK, RUB_STONE, SOOT, CHAR, NET, MUD }

## Preview unit → unit mesh (the fort's wall line ±46 is ±0.42 of the map object's size)
const K := 0.42 / 46.0
## The ground under the fort, preview units: Render3D sinks the mesh by 1 % of its size (1.1 units)
const GROUND := 1.1
## Wall line, half side: tower centres at (±S, ±S), the gate in the +z side (FortBuild.WALLS)
const S := 46.0
## Tone of a wet, dirty wall foot (vertex colour at the ground, fading out by DAMP_H above it)
const DAMP_TONE := Color(0.7, 0.63, 0.56)
const DAMP_H := 2.6
## Materials whose foot gets the damp tone
const DAMP_MATS := [M.MUD, M.PLASTER, M.STONE, M.BRICK]

var _st := {}                    # piece → {material → SurfaceTool}
var _piece := "base"
var _xf := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()
## Vertex tone of the next primitives (white = the material as it is): repairs, patches, soot
var _tint := Color.WHITE
## The damp, darker foot is drawn on the earthen materials (off for heaps: loose earth dries out)
var _damp := true


## Starts piece `id`: the next primitives go into its mesh, with its own random stream, so a piece looks the
## same whichever order the pieces are built in.
func _begin(id: String) -> void:
	_piece = id
	_xf = Transform3D.IDENTITY
	_tint = Color.WHITE
	_rng.seed = hash(id) ^ 7


## Tile size of a material's box-projected UVs, preview units per texture repeat (FortBuild overrides it).
func _uv_tile(_m: int) -> float:
	return 8.0


func _r(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


## Random yaw with a tilt of up to ±t on both horizontal axes (a piece lying where it fell).
func _tumble(t: float) -> Basis:
	return Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _r(-t, t)) * Basis(Vector3.BACK, _r(-t, t))


## Smooth value noise, 0…1, of one coordinate and a seed (no generator: same in any thread and order).
static func _n1(x: float, sd: float) -> float:
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_h1(i + sd * 17.13), _h1(i + 1.0 + sd * 17.13), f)


static func _h1(x: float) -> float:
	var s := sin(x * 12.9898 + 4.1) * 43758.5453
	return s - floorf(s)


## Point at angle a (0…TAU, from +x towards +z) round a rounded rectangle of half sizes hx, hz and corner radius
## rc, spaced evenly along its outline (a superellipse would bunch the points at the corners).
static func _rrect(a: float, hx: float, hz: float, rc: float) -> Vector2:
	rc = minf(rc, minf(hx, hz) - 0.01)
	var sx := 2.0 * (hx - rc)
	var sz := 2.0 * (hz - rc)
	var q := PI * 0.5 * rc
	var s := fposmod(a, TAU) / TAU * (2.0 * sx + 2.0 * sz + 4.0 * q)
	# runs: right side (upper half), corner, top, corner, left, corner, bottom, corner, right side (lower half)
	var runs := [sz * 0.5, q, sx, q, sz, q, sx, q, sz * 0.5]
	var k := 0
	while k < runs.size() - 1 and s > runs[k]:
		s -= runs[k]
		k += 1
	var cx := hx - rc
	var cz := hz - rc
	match k:
		0: return Vector2(hx, s)
		1: return Vector2(cx, cz) + Vector2.from_angle(s / rc) * rc
		2: return Vector2(cx - s, hz)
		3: return Vector2(-cx, cz) + Vector2.from_angle(PI * 0.5 + s / rc) * rc
		4: return Vector2(-hx, cz - s)
		5: return Vector2(-cx, -cz) + Vector2.from_angle(PI + s / rc) * rc
		6: return Vector2(-cx + s, -hz)
		7: return Vector2(cx, -cz) + Vector2.from_angle(PI * 1.5 + s / rc) * rc
	return Vector2(hx, -cz + s)


# ---------- hand-built shapes ----------

## Lofted ring: closed outlines stacked at heights `ys`, the outline at angle a and height y is
## c + plan.call(a, y) (a Vector2 offset in the xz plane), `seg` points round. Smooth normals from the grid.
## `cap` closes the top with a fan (the outline must be star-shaped round c). For towers, bastions,
## buttresses, keeps and heaps whose walls lean, bulge and erode.
func _loft(m: int, c: Vector2, plan: Callable, ys: PackedFloat32Array, seg: int, cap := true) -> void:
	var grid := []
	for j in ys.size():
		var ring := []
		for i in seg:
			var a := float(i) / seg * TAU
			var o: Vector2 = plan.call(a, ys[j])
			ring.append(Vector3(c.x + o.x, ys[j], c.y + o.y))
		grid.append(ring)
	var rows := ys.size()
	var nrm := []
	for j in rows:
		var nr := []
		for i in seg:
			var ta: Vector3 = grid[j][(i + 1) % seg] - grid[j][(i - 1 + seg) % seg]
			var ty: Vector3 = grid[mini(j + 1, rows - 1)][i] - grid[maxi(j - 1, 0)][i]
			var n := ty.cross(ta)
			if n.length_squared() < 1e-10:
				n = Vector3.UP
			nr.append(n.normalized())
		nrm.append(nr)
	for j in rows - 1:
		for i in seg:
			var k := (i + 1) % seg
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][k]
			var cc: Vector3 = grid[j + 1][k]
			var d: Vector3 = grid[j + 1][i]
			var xa := _xf.basis
			_tri_n(m, _xf * a, _xf * b, _xf * cc, xa * nrm[j][i], xa * nrm[j][k], xa * nrm[j + 1][k])
			_tri_n(m, _xf * a, _xf * cc, _xf * d, xa * nrm[j][i], xa * nrm[j + 1][k], xa * nrm[j + 1][i])
	if not cap:
		return
	var top: Array = grid[rows - 1]
	var mid := Vector3.ZERO
	for p: Vector3 in top:
		mid += p / seg
	var up := _xf.basis * Vector3.UP
	for i in seg:
		_tri_n(m, _xf * mid, _xf * top[i], _xf * top[(i + 1) % seg], up, up, up)


## Wall profile swept along a ground path: path[i] — a point in the xz plane (Vector2), profs[i] — the profile
## there as (across, y) points from the inner foot over the top to the outer foot (across > 0 = the `side`
## of the path's left normal). Sections are joined by quads with the profile's own normals (smooth along the
## path, sharp at the profile's corners); `caps` closes both ends with the profile polygon. A `closed` path
## repeats its first point at the end (a ring round a tower or a roof).
func _sweep(m: int, path: PackedVector2Array, profs: Array, side: float, caps := false, closed := false) -> void:
	var n := path.size()
	var cols := []
	var nrms := []
	for i in n:
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		if closed and (i == 0 or i == n - 1):
			t = (path[1] - path[n - 2]).normalized()
		var across := Vector3(-t.y, 0.0, t.x) * side
		var prof: PackedVector2Array = profs[i]
		var col := []
		var nc := []
		for j in prof.size():
			col.append(Vector3(path[i].x, 0.0, path[i].y) + across * prof[j].x + Vector3.UP * prof[j].y)
		for j in prof.size() - 1:
			var d := prof[j + 1] - prof[j]
			nc.append((across * -d.y + Vector3.UP * d.x).normalized())
		cols.append(col)
		nrms.append(nc)
	var xa := _xf.basis
	for i in n - 1:
		var p: Array = cols[i]
		var q: Array = cols[i + 1]
		for j in p.size() - 1:
			var na: Vector3 = xa * nrms[i][j]
			var nb: Vector3 = xa * nrms[i + 1][j]
			_tri_n(m, _xf * p[j], _xf * q[j], _xf * q[j + 1], na, nb, nb)
			_tri_n(m, _xf * p[j], _xf * q[j + 1], _xf * p[j + 1], na, nb, na)
	if not caps:
		return
	for e: int in [0, n - 1]:
		var prof: PackedVector2Array = profs[e]
		var idx := Geometry2D.triangulate_polygon(prof)
		var t := (path[mini(e + 1, n - 1)] - path[maxi(e - 1, 0)]).normalized()
		var outn := Vector3(t.x, 0.0, t.y) * (1.0 if e == n - 1 else -1.0)
		for k in range(0, idx.size(), 3):
			var c: Array = cols[e]
			_tri_n(m, _xf * c[idx[k]], _xf * c[idx[k + 1]], _xf * c[idx[k + 2]], xa * outn, xa * outn, xa * outn)


## Soft heap of earth or fallen mud at c (ground level y0): radii rad, height h, lumpy, smooth-shaded. Talus at a
## wall's foot, berms, the cone of a collapse.
func _heap(m: int, c: Vector2, rad: Vector2, h: float, y0 := GROUND - 0.4, yaw := 0.0) -> void:
	var sd := _rng.randf() * 50.0
	var plan := func(a: float, y: float) -> Vector2:
		var f := clampf((y - y0) / h, 0.0, 1.0)
		var k := pow(1.0 - f, 1.2) * (1.0 + 0.35 * _pn(a, y * 0.3, sd))
		return Vector2(cos(a) * rad.x * k, sin(a) * rad.y * k).rotated(yaw)
	var ys := PackedFloat32Array()
	for j in 6:
		ys.append(y0 + h * float(j) / 5.0 * (0.97 if j == 5 else 1.0))
	_damp = false
	_loft(m, c, plan, ys, 16, true)
	_damp = true


## Noise round a ring, −0.5…0.5 and periodic in the angle a (no seam where a wraps), drifting with y.
static func _pn(a: float, y: float, sd: float) -> float:
	return 0.25 * sin(3.0 * a + sd + y * 0.7) + 0.15 * sin(5.0 * a + sd * 1.7 - y * 0.5) \
		+ 0.1 * sin(8.0 * a + sd * 2.3 + y * 1.1)


# ---------- destruction kit ----------

## Debris pile heaped in a cone around c: broken slabs of plaster and rammed earth, lumpy clods and stones,
## chipped bricks and splinters, in the fort's earthen materials, half sunk into a low skirt of fines (crumbled
## mud and dust) so the pile reads as one heap rather than blocks laid on the ground. No piece is a plain box:
## at gameplay height raw boxes read as building blocks, not rubble.
func _rubble(c: Vector3, n: int, spread: float, s: float) -> void:
	if n >= 20:   # the fines the pieces lie in: a low, wide, lumpy skirt
		var keep := _tint
		_tint = keep * Color(0.92, 0.88, 0.84)
		_heap(M.RUB_PLASTER, Vector2(c.x, c.z), Vector2(spread * 0.95, spread * 0.8), s * 0.9, c.y - 0.5, _rng.randf() * TAU)
		_tint = keep
	for i in n:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * spread
		var cone := 1.0 - d / spread
		var p := c + Vector3(cos(a) * d, cone * s * 1.6 * _r(0.6, 1.3), sin(a) * d)
		var t := _rng.randf()
		if t < 0.22:
			_shard(M.RUB_PLASTER if _rng.randf() < 0.7 else M.RUB_BRICK, Vector3(_r(1.2, 2.6) * s, _r(0.35, 0.7), _r(1.0, 2.0) * s), p, _tumble(0.6))
		elif t < 0.62:
			var q := _rng.randf()
			_chunk(M.RUB_PLASTER if q < 0.5 else (M.RUB_BRICK if q < 0.8 else M.RUB_STONE), _r(0.25, 0.7) * s, p)
		elif t < 0.92:
			_shard(M.RUB_BRICK, Vector3(0.62, 0.3, 0.32), Vector3(p.x, c.y + (p.y - c.y) * 0.7 + 0.15, p.z), _tumble(0.5), 6)
		else:
			_boxr(M.WOOD, Vector3(_r(1.5, 3.5), 0.22, 0.32), p, _tumble(0.5))


## Broken slab of size s (x, thickness y, z) centred at c, turned by b: an irregular outline of `n` points (a
## ragged break, not a rectangle) in three rings — a narrower bottom, the full outline jittered in height, a
## narrower top — so its edges are chipped and its faces uneven. Flat-shaded. Fallen plaster, rammed-earth
## and parapet blocks, chipped bricks (n = 6 keeps a brick's shape).
func _shard(m: int, s: Vector3, c: Vector3, b: Basis, n := 9) -> void:
	var xf := _xf * Transform3D(b, c)
	var hy := s.y * 0.5
	var bot := []
	var mid := []
	var top := []
	var a0 := _rng.randf() * TAU
	for i in n:
		var a := a0 + (float(i) + _r(-0.3, 0.3)) / n * TAU
		var k := _r(0.62, 1.08) if n > 6 else _r(0.9, 1.05)
		var q := Vector2(cos(a) * s.x * 0.5 * k, sin(a) * s.z * 0.5 * k)
		if n <= 6:   # a brick: the outline pushed out to its corners
			q = Vector2(signf(q.x) * maxf(absf(q.x), s.x * 0.36), signf(q.y) * maxf(absf(q.y), s.z * 0.3))
		var yj := hy * _r(-0.3, 0.3)
		bot.append(xf * Vector3(q.x * _r(0.7, 0.88), -hy + yj * 0.3, q.y * _r(0.7, 0.88)))
		mid.append(xf * Vector3(q.x, yj, q.y))
		top.append(xf * Vector3(q.x * _r(0.68, 0.86), hy + hy * _r(-0.35, 0.25), q.y * _r(0.68, 0.86)))
	var o := xf.origin
	for i in n:
		var j := (i + 1) % n
		_quad(m, bot[i], bot[j], mid[j], mid[i], o)
		_quad(m, mid[i], mid[j], top[j], top[i], o)
	for i in range(1, n - 1):
		_tri(m, top[0], top[i], top[i + 1], o)
		_tri(m, bot[0], bot[i + 1], bot[i], o)


## Broken end of a rammed-earth wall along `path` (xz, from where it still stands full towards the gap),
## heights hs (the top's centre at each path point, preview units above 0): the battered faces of the wall
## (half bases bi inside, bo outside at the ground, their slope `slope` across per unit up) under a torn top
## that rises and falls across the thickness and along the path. side — which way of the path's left normal is
## outside; y0 — the foot (the ground by default, or the top of what the wall stands on). Closed at both ends.
## One sweep in `m`.
func _broken_end(m: int, path: PackedVector2Array, hs: PackedFloat32Array, bi: float, bo: float, slope: float,
		side: float, y0 := GROUND - 0.6) -> void:
	var profs := []
	var sd := _rng.randf() * 40.0
	for k in path.size():
		var dh := maxf(hs[k] - y0, 0.6)
		var hl := y0 + dh * (1.0 + (_n1(float(k) * 0.7, sd) - 0.5) * 0.3)
		var hr := y0 + dh * (1.0 + (_n1(float(k) * 0.6, sd + 4.0) - 0.5) * 0.3)
		var hm1 := y0 + dh * (1.0 + (_n1(float(k) * 0.9, sd + 8.0) - 0.5) * 0.22) + 0.25
		var hm2 := y0 + dh * (1.0 + (_n1(float(k) * 1.1, sd + 12.0) - 0.5) * 0.22) + 0.15
		var xi := -(bi - slope * (hl - y0))
		var xo := bo - slope * (hr - y0)
		profs.append(PackedVector2Array([Vector2(-bi, y0), Vector2(xi, hl), Vector2(lerpf(xi, xo, 0.33), hm1),
			Vector2(lerpf(xi, xo, 0.68), hm2), Vector2(xo, hr), Vector2(bo, y0)]))
	_sweep(m, path, profs, side, true)


const _ICO_F := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
	[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]


## Lumpy stone/adobe chunk of size s at p: an icosahedron bent by three sines and flattened, flat-shaded.
func _chunk(m: int, s: float, p: Vector3) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := Vector3(_r(2.0, 4.0), _r(2.0, 4.0), _r(2.0, 4.0))
	var ph := Vector3(_rng.randf() * 6.0, _rng.randf() * 6.0, _rng.randf() * 6.0)
	var fl := _r(0.5, 0.85)
	var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf() * 3.0)
	var v := []
	for q: Vector3 in raw:
		var u := q.normalized()
		var k := 1.0 + 0.22 * sin(u.x * f.x + ph.x) + 0.2 * sin(u.y * f.y + ph.y) + 0.18 * sin(u.z * f.z + ph.z)
		k *= _r(0.8, 1.12)   # each corner its own: no two chunks share the sines' smooth symmetry
		v.append(_xf * (p + b * (Vector3(u.x, u.y * fl, u.z) * s * k)))
	var c := _xf * p
	for fc: Array in _ICO_F:
		_tri(m, v[fc[0]], v[fc[1]], v[fc[2]], c)


## Beam through c, `len` long, along the horizontal direction `dir` tilted up by `pitch` (a snapped joist, a
## corbel, a beam end). `m` — WOOD, or CHAR when burnt.
func _beam(c: Vector3, len: float, dir: Vector3, pitch: float, m := M.WOOD, r := 0.3) -> void:
	var ax := (dir.normalized() * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var b := Basis(Quaternion(Vector3.UP, ax))
	_cyl(m, r * 0.87, r * 1.13, len, 7, Transform3D(b, c - ax * len * 0.5))


# ---------- primitives (preview units, through the current group transform _xf) ----------

func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## Box of size s, its base centred at p, turned by ry about y then rx about x.
func _box(m: int, s: Vector3, p: Vector3, ry := 0.0, rx := 0.0) -> void:
	var b := Basis(Vector3.UP, ry) * Basis(Vector3.RIGHT, rx)
	_boxr(m, s, p + b * Vector3(0, s.y * 0.5, 0), b)


## Box of size s centred at c, turned by b.
func _boxr(m: int, s: Vector3, c: Vector3, b: Basis) -> void:
	var xf := _xf * Transform3D(b, c)
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for f: Array in [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3], [0, 1, 5, 4]]:
		_quad(m, xf * v[f[0]], xf * v[f[1]], xf * v[f[2]], xf * v[f[3]], xf.origin)


## Flat irregular slab on a face: outline `pts` (Vector2 in the face's (u, v) axes), pushed `t` proud of it.
## o — a point of the face, u/v — unit axes in the face, n — its outward normal (all in group space). Fallen
## plaster showing brick, mud repairs, soot and char stains, streaks.
func _slab(m: int, o: Vector3, u: Vector3, v: Vector3, n: Vector3, pts: PackedVector2Array, t: float) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var top := []
	var bot := []
	for p in pts:
		var q := o + u * p.x + v * p.y
		top.append(_xf * (q + n * t))
		bot.append(_xf * (q - n * 0.05))
	var nn := (_xf.basis * n).normalized()
	for k in range(0, idx.size(), 3):
		_tri_n(m, top[idx[k]], top[idx[k + 1]], top[idx[k + 2]], nn, nn, nn)
	var mid := Vector3.ZERO
	for p: Vector3 in bot:
		mid += p / bot.size()
	for i in pts.size():
		var j := (i + 1) % pts.size()
		_quad(m, bot[i], bot[j], top[j], top[i], mid - nn * 2.0)


## Ragged outline round the origin for _slab: `n` points on an ellipse of half sizes s, jittered.
func _ragged(s: Vector2, n := 9, jit := 0.3) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := float(i) / n * TAU + _r(-0.2, 0.2)
		var k := 1.0 + _r(-jit, jit)
		out.append(Vector2(cos(a) * s.x * k, sin(a) * s.y * k))
	return out


## Wall profile (local z across, y up) extruded along local x over len, flat-shaded, capped.
func _prism(m: int, prof: PackedVector2Array, len: float) -> void:
	var n := prof.size()
	var x0 := -len * 0.5
	var x1 := len * 0.5
	var mid := Vector2.ZERO
	for q in prof:
		mid += q / n
	var inside := _xf * Vector3(0, mid.y, mid.x)
	for i in n:
		var a := prof[i]
		var b := prof[(i + 1) % n]
		_quad(m, _xf * Vector3(x0, a.y, a.x), _xf * Vector3(x0, b.y, b.x), _xf * Vector3(x1, b.y, b.x), _xf * Vector3(x1, a.y, a.x), inside)
	for i in range(1, n - 1):
		for x: float in [x0, x1]:
			_tri(m, _xf * Vector3(x, prof[0].y, prof[0].x), _xf * Vector3(x, prof[i + 1].y, prof[i + 1].x), _xf * Vector3(x, prof[i].y, prof[i].x), inside)


## Truncated cone along local y from 0 to h (rt top, rb bottom radius), smooth sides and both caps,
## placed by `place` inside the current group.
func _cyl(m: int, rt: float, rb: float, h: float, seg: int, place: Transform3D) -> void:
	var xf := _xf * place
	var slope := (rb - rt) / h
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var p := [xf * (d0 * rb), xf * (d1 * rb), xf * (d1 * rt + Vector3(0, h, 0)), xf * (d0 * rt + Vector3(0, h, 0))]
		var nn := [xf.basis * n0, xf.basis * n1, xf.basis * n1, xf.basis * n0]
		_tri_n(m, p[0], p[2], p[1], nn[0], nn[2], nn[1])
		_tri_n(m, p[0], p[3], p[2], nn[0], nn[3], nn[2])
		_tri(m, xf * Vector3(0, h, 0), xf * (d1 * rt + Vector3(0, h, 0)), xf * (d0 * rt + Vector3(0, h, 0)), xf * Vector3(0, h * 0.5, 0))
		_tri(m, xf * Vector3.ZERO, xf * (d0 * rb), xf * (d1 * rb), xf * Vector3(0, h * 0.5, 0))


## Tank end: a quarter-sphere-ish dome closing a horizontal cylinder of radius r at p, bulging to side s.
func _half_dome(m: int, r: float, p: Vector3, s: float) -> void:
	var seg := 16
	var rings := 4
	for j in rings:
		var b0 := float(j) / rings * PI * 0.5
		var b1 := float(j + 1) / rings * PI * 0.5
		for i in seg:
			var a0 := float(i) / seg * TAU
			var a1 := float(i + 1) / seg * TAU
			var v := [_dome(a0, b0, s), _dome(a1, b0, s), _dome(a1, b1, s), _dome(a0, b1, s)]
			var w := []
			for d: Vector3 in v:
				w.append(_xf * (p + d * r))
			var nb := _xf.basis
			_tri_n(m, w[0], w[1], w[2], nb * v[0], nb * v[1], nb * v[2])
			_tri_n(m, w[0], w[2], w[3], nb * v[0], nb * v[2], nb * v[3])


## Unit direction on the tank's end hemisphere: a around the axis, b from the rim (0) to the pole (PI/2).
func _dome(a: float, b: float, s: float) -> Vector3:
	return Vector3(s * sin(b), cos(b) * sin(a), cos(b) * cos(a))


func _quad(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	_tri(m, a, b, c, inside)
	_tri(m, a, c, d, inside)


## Flat triangle facing away from `inside` (a point inside the convex piece it bounds), so the vertex order
## written above never decides which side is lit.
func _tri(m: int, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	_tri_n(m, a, b, c, n, n, n)


## Triangle with per-vertex normals; positions already in fort space (preview units). The UV of all three
## vertices comes from the face's dominant axis (box projection), so a face never smears its texture. The
## vertex colour is _tint, darkened towards the ground on the earthen materials (damp foot).
func _tri_n(m: int, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if not _st.has(_piece):
		_st[_piece] = {}
	var sts: Dictionary = _st[_piece]
	if not sts.has(m):
		var nst := SurfaceTool.new()
		nst.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[m] = nst
	var st: SurfaceTool = sts[m]
	var fn := (na + nb + nc).normalized()
	var k := 1.0 / _uv_tile(m)
	var damp := _damp and m in DAMP_MATS
	# Godot's front faces are clockwise seen from outside: the winding's cross product points away from fn
	var order := [[a, na], [c, nc], [b, nb]] if (b - a).cross(c - a).dot(fn) > 0.0 else [[a, na], [b, nb], [c, nc]]
	for v: Array in order:
		var p: Vector3 = v[0]
		var uv: Vector2
		if absf(fn.y) > 0.75:
			uv = Vector2(p.x, p.z)
		elif absf(fn.x) >= absf(fn.z):
			uv = Vector2(p.z * signf(fn.x if fn.x != 0.0 else 1.0), -p.y)
		else:
			uv = Vector2(-p.x * signf(fn.z if fn.z != 0.0 else 1.0), -p.y)
		var col := _tint
		if damp:
			col *= DAMP_TONE.lerp(Color.WHITE, smoothstep(GROUND, GROUND + DAMP_H, p.y))
		st.set_color(col)
		st.set_normal(v[1])
		st.set_uv(uv * k)
		st.add_vertex(p * K)


## Surface arrays of every piece built so far: piece → {material → arrays}, tangents generated.
func _arrays() -> Dictionary:
	var out := {}
	for id: String in _st:
		var sts: Dictionary = _st[id]
		var per := {}
		for m: int in sts:
			var st: SurfaceTool = sts[m]
			st.generate_tangents()
			per[m] = st.commit_to_arrays()
		out[id] = per
	return out
