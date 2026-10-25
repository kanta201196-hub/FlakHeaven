class_name FortBuild
extends RefCounted
## Highland fort model, texture set Г (FA-02, Kanta 2026-10-25; spec docs/superpowers/specs/2026-10-25-fortified-area-design.md).
## Built in code at first use, ported from the approved three.js preview
## (/mnt/project-files/visual/fort_rework/hq/hq_scene.html), so the numbers below are the preview's units:
## wall line ±46, round corner towers r 10.5 × 23, gate in +z. The mesh is returned in unit space (wall line ±0.42,
## like the old AdobeBuild.fort), Render3D scales it by the map object's size. One surface per material.
## Box-projected UVs are baked here in preview units, so the texel size does not change with the fort's size.

const K := 0.42 / 46.0          ## preview unit → unit mesh (the old fort's wall line was 0.42)
const S := 46.0                 ## wall line, half side
const WH := 15.0                ## wall height
const WT := 7.0                 ## wall base thickness
const TOWER_R := 10.5
const TOWER_H := 23.0
const PAD_H := 0.6              ## concrete turntable pad on each tower
const TOWER_C := S * K          ## tower centre, ±share of the size on both axes
const TOWER_TOP := (TOWER_H + PAD_H) * K   ## pad top above the ground, share of the size (FortArea launchers)
## Jeep spots in the yard (preview props), unit space: by the citadel's door and by the gate road.
const YARD := [Vector2(8.0 * K, 6.0 * K), Vector2(2.0 * K, 28.0 * K)]

enum M { PLASTER, STONE, BRICK, CONC, WOOD, DARK, BAG, OLIVE, STEEL }

## Textured sets: [file prefix in game/art/fort, gain, gamma, tile (preview units per repeat), normal depth, grime, bleach].
## Plaster gain a touch paler than the preview's (the game's sun is warmer). Tiles are twice the preview's: the game camera is far higher, at the preview's size stones melt into a flat tone.
const SETS := {
	M.PLASTER: ["plaster", Vector3(1.0, 0.92, 0.8), 1.05, 4.6, 0.42, 5.0, 12.0],
	M.STONE: ["stone", Vector3(1.05, 0.98, 0.88), 1.0, 7.0, 1.3, 4.0, 12.0],
	M.BRICK: ["brick", Vector3(0.95, 0.86, 0.74), 1.0, 5.2, 1.3, 5.0, 12.0],
	M.CONC: ["conc", Vector3(0.98, 0.84, 0.66), 1.0, 10.0, 1.3, 5.0, 12.0],
	M.WOOD: ["wood", Vector3(0.8, 0.72, 0.62), 1.0, 5.0, 1.3, 0.01, 12.0],
}
const BAG_TEX := "res://models/biome/b10_sandbag_post_sandbag_burlap_color.jpg"

static var _mesh: ArrayMesh
static var _task := -1

var _st := {}
var _xf := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()


## The fort mesh, built once per run (~25k triangles, ~0.25 s on the cloud CPU). Waits for prefetch() if
## it is still building, otherwise builds here.
static func mesh() -> ArrayMesh:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _mesh == null:
		_make()
	return _mesh


## Starts building the mesh in the background (Render3D, as soon as the Highland is on), so the first fort
## on screen does not stall a frame. Does nothing once started.
static func prefetch() -> void:
	if _mesh == null and _task < 0:
		_task = WorkerThreadPool.add_task(_make, false, "fort_build")


static func _make() -> void:
	var b := FortBuild.new()
	b._rng.seed = 7
	b._build()
	_mesh = b._commit()


## Material of one surface: the fort shader for the textured sets, plain lit colours for the rest.
static func material(m: int) -> Material:
	if SETS.has(m):
		var s: Array = SETS[m]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/fort.gdshader")
		var dir := "res://art/fort/%s_" % s[0]
		sm.set_shader_parameter("color_tex", load(dir + "color.jpg"))
		sm.set_shader_parameter("normal_tex", load(dir + "normal.jpg"))
		sm.set_shader_parameter("arm_tex", load(dir + "arm.jpg"))
		sm.set_shader_parameter("gain", s[1])
		sm.set_shader_parameter("gamma", s[2])
		sm.set_shader_parameter("normal_depth", s[4])
		sm.set_shader_parameter("grime", s[5])
		sm.set_shader_parameter("bleach", s[6])
		sm.set_shader_parameter("unit", 1.0 / K)
		return sm
	var f := StandardMaterial3D.new()
	f.metallic_specular = 0.2
	f.roughness = 0.95
	match m:
		M.DARK:
			f.albedo_color = Color(0.118, 0.102, 0.086)
		M.OLIVE:
			f.albedo_color = Color(0.29, 0.3, 0.21)   # darker than the preview: the warm sun tint turned it lime
		M.STEEL:
			f.albedo_color = Color(0.357, 0.365, 0.361)
			f.roughness = 0.75
		M.BAG:
			f.albedo_color = Color(0.85, 0.78, 0.65)
			if ResourceLoader.exists(BAG_TEX):
				f.albedo_texture = load(BAG_TEX)
			f.roughness = 1.0
	return f


## Tile size of a surface's UVs, preview units per texture repeat.
static func _tile(m: int) -> float:
	if SETS.has(m):
		return float(SETS[m][3])
	return 2.0 if m == M.BAG else 8.0


func _build() -> void:
	_walls()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_tower(s.x * S, s.y * S)
	_gate()
	_citadel()
	for z: float in [-12.0, -5.0, 2.0]:
		_fuel_tank(30.0, z, 0.1)


# ---------- layout (preview «live» state; gate in the south, +z) ----------

func _walls() -> void:
	_wall_run(-S, -S, S, -S, -1.0, [[-12.0, 5.0, 6.0, 4.0, M.BRICK], [16.0, 3.0, 8.0, 5.0, M.BRICK]])
	_wall_run(-S, S, -12.0, S, 1.0, [[-10.0, 6.0, 5.0, 3.0, M.BRICK]])
	_wall_run(12.0, S, S, S, 1.0, [[-20.0, 4.0, 7.0, 4.0, M.BRICK], [8.0, 7.0, 5.0, 3.0, M.BRICK]])
	_wall_run(-S, -S, -S, S, 1.0, [[0.0, 2.0, 12.0, 10.0, M.CONC], [24.0, 6.0, 6.0, 4.0, M.BRICK]])
	_wall_run(S, -S, S, S, -1.0, [[-15.0, 5.0, 7.0, 4.0, M.BRICK]])


## One wall run from a to b: battered plastered core on a stone plinth, outer parapet with rounded merlons
## and embrasures, low inner lip, beam ends on both faces, drain spouts, patches where the plaster fell off.
## `out` — which local z side faces outwards.
func _wall_run(ax: float, az: float, bx: float, bz: float, out: float, patches: Array) -> void:
	var len := Vector2(bx - ax, bz - az).length()
	var ang := atan2(bz - az, bx - ax)
	var keep := _xf
	_xf = Transform3D(Basis(Vector3.UP, -ang), Vector3((ax + bx) * 0.5, 0.0, (az + bz) * 0.5))
	_prism(M.PLASTER, PackedVector2Array([Vector2(-WT * 0.5, 0), Vector2(WT * 0.5, 0), Vector2(WT * 0.33, WH), Vector2(-WT * 0.33, WH)]), len)
	_prism(M.STONE, PackedVector2Array([Vector2(-WT * 0.5 - 0.6, 0), Vector2(WT * 0.5 + 0.6, 0), Vector2(WT * 0.5 + 0.1, 3.2), Vector2(-WT * 0.5 - 0.1, 3.2)]), len)
	var po := out * WT * 0.28
	_box(M.PLASTER, Vector3(len, 1.2, 1.2), Vector3(0, WH, po))
	_box(M.PLASTER, Vector3(len, 0.7, 0.9), Vector3(0, WH, -po))
	var x := -len * 0.5 + 2.2
	while x < len * 0.5 - 1.5:
		var mh := _rng.randf_range(1.6, 2.2)
		_box(M.PLASTER, Vector3(2.0, mh, 1.3), Vector3(x, WH + 1.2, po))
		_half_cyl(M.PLASTER, 0.65, 2.0, Vector3(x, WH + 1.2 + mh, po))
		if _rng.randf() < 0.5:
			_box(M.DARK, Vector3(0.5, 0.9, 1.4), Vector3(x + 1.7, WH + 1.6, po))   # embrasure
		x += 3.4
	x = -len * 0.5 + 3.0
	while x < len * 0.5 - 2.0:
		for s: float in [1.0, -1.0]:
			_cyl(M.WOOD, 0.32, 0.36, 1.6, 7, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, WH - 2.2, s * (WT * 0.36 + 0.5))))
		x += 3.8
	x = -len * 0.5 + 9.0
	while x < len * 0.5 - 6.0:
		_box(M.WOOD, Vector3(0.7, 0.35, 2.6), Vector3(x, WH - 0.4, out * (WT * 0.34 + 1.1)))   # drain spout
		x += 17.0
	for p: Array in patches:
		var py: float = p[1]
		var ph: float = p[3]
		var z := out * (WT * 0.5 - (py + ph * 0.5) / WH * WT * 0.17 - 0.05)
		_box(int(p[4]), Vector3(p[2], ph, 0.5), Vector3(p[0], py, z), 0.0, -out * 0.18)
	_xf = keep


## Round corner tower: tapering plastered shaft on a stone ring, machicolation ring on wooden corbels,
## crenels, two rows of loopholes; a concrete pad with a sandbag nest on top for the launcher.
func _tower(x: float, z: float) -> void:
	var r := TOWER_R
	var h := TOWER_H
	_cyl(M.PLASTER, r * 0.84, r, h, 40, _at(x, 0.0, z))
	_cyl(M.STONE, r + 0.5, r + 0.7, 3.4, 40, _at(x, 0.0, z))
	_cyl(M.PLASTER, r * 0.92, r * 0.86, 1.6, 40, _at(x, h - 1.4, z))
	var n := 14
	for i in n:
		var a := float(i) / n * TAU
		_box(M.WOOD, Vector3(0.8, 1.2, 0.9), Vector3(x + cos(a) * r * 0.9, h - 2.5, z + sin(a) * r * 0.9), -a)   # corbels
		if i % 2 == 0:
			_box(M.PLASTER, Vector3(2.6, 2.2, 1.4), Vector3(x + cos(a) * r * 0.86, h + 0.2, z + sin(a) * r * 0.86), -a + PI * 0.5)
	for i in 6:
		var a := float(i) / 6.0 * TAU + 0.3
		for yy: float in [7.0, 14.0]:
			var rr := r * (1.0 - yy / h * 0.16) - 0.05
			_box(M.DARK, Vector3(0.55, 2.4, 0.6), Vector3(x + cos(a) * rr, yy, z + sin(a) * rr), -a + PI * 0.5)
	_cyl(M.CONC, r * 0.8, r * 0.82, PAD_H, 32, _at(x, h, z))
	_sandbag_ring(x, h + PAD_H, z, r * 0.66, atan2(z, x) + PI)


## Gate: two half-towers, arched lintel, wooden doors and the deck over the passage.
func _gate() -> void:
	for sx: float in [-1.0, 1.0]:
		_cyl(M.PLASTER, 5.6, 6.4, 19.0, 28, _at(sx * 10.0, 0.0, S + 1.0))
		_cyl(M.STONE, 6.8, 7.0, 3.2, 28, _at(sx * 10.0, 0.0, S + 1.0))
		_box(M.PLASTER, Vector3(3, 1.6, 3), Vector3(sx * 10.0, 19.0, S + 1.0))
	_box(M.PLASTER, Vector3(14, 4, 8), Vector3(0, 12, S + 1.0))
	_box(M.WOOD, Vector3(8.4, 11.6, 0.6), Vector3(0, 0, S + 3.9))
	_box(M.WOOD, Vector3(8.8, 0.8, 8.4), Vector3(0, 11.2, S + 1.0))


## Citadel (two stepped blocks and the keep) and the rooms along the inner walls.
func _citadel() -> void:
	_block(-6, -16, 32, 22, 12)
	_block(-10, -18, 16, 12, 7, 12.8)
	_box(M.PLASTER, Vector3(9, 27, 9), Vector3(6, 0, -22))
	_box(M.PLASTER, Vector3(9.6, 0.8, 9.6), Vector3(6, 27, -22))
	for d: Vector2 in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]:
		_box(M.PLASTER, Vector3(1.6, 2, 1.6), Vector3(6 + d.x * 0.95, 27.8, -22 + d.y * 0.95))
	_box(M.DARK, Vector3(1.2, 3, 0.5), Vector3(6, 18, -17.4))
	_box(M.DARK, Vector3(1.2, 3, 0.5), Vector3(6, 10, -17.4))
	_block(-30, 32, 18, 9, 7)
	_block(28, -34, 22, 9, 8)
	_block(34, 18, 9, 20, 6)


## Flat-roofed adobe block: parapet with merlons on the long sides, windows and beam ends on the +z face, stone base.
func _block(x: float, z: float, w: float, d: float, h: float, y0 := 0.0) -> void:
	_box(M.PLASTER, Vector3(w, h, d), Vector3(x, y0, z))
	_box(M.PLASTER, Vector3(w + 0.4, 0.8, d + 0.4), Vector3(x, y0 + h, z))
	var i := -w * 0.5 + 2.0
	while i < w * 0.5 - 1.0:
		_box(M.PLASTER, Vector3(1.6, 1.4, 0.9), Vector3(x + i, y0 + h + 0.8, z - d * 0.5))
		_box(M.PLASTER, Vector3(1.6, 1.4, 0.9), Vector3(x + i, y0 + h + 0.8, z + d * 0.5))
		i += 3.2
	i = -w * 0.5 + 3.0
	while i < w * 0.5 - 2.0:
		_box(M.DARK, Vector3(1.2, 2.2, 0.5), Vector3(x + i, y0 + h * 0.55, z + d * 0.5 + 0.05))
		_cyl(M.WOOD, 0.3, 0.3, 1.4, 6, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x + i + 1.6, y0 + h - 1.4, z + d * 0.5 + 0.5)))
		i += 4.5
	_box(M.STONE, Vector3(w, 3, d), Vector3(x, y0 - 0.01, z))


## Fuel store tank on two steel saddles.
func _fuel_tank(x: float, z: float, ry: float) -> void:
	var keep := _xf
	_xf = _xf * Transform3D(Basis(Vector3.UP, ry), Vector3(x, 0, z))
	_cyl(M.OLIVE, 2.1, 2.1, 8.0, 20, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(4.0, 2.9, 0)))
	for s: float in [-1.0, 1.0]:
		_half_dome(M.OLIVE, 2.1, Vector3(s * 4.0, 2.9, 0), s)
		_box(M.STEEL, Vector3(0.7, 2.2, 3.6), Vector3(s * 3.0, 0, 0))
	_cyl(M.STEEL, 0.5, 0.5, 0.8, 10, _at(1.0, 4.8, 0.0))
	_xf = keep


## Three courses of sandbags around a tower pad, open towards `gap_a` (the yard side).
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


# ---------- primitives (preview units, through the current group transform _xf) ----------

func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## Box of size s, its base centred at p (like the preview's `box`), turned by ry about y then rx about x.
func _box(m: int, s: Vector3, p: Vector3, ry := 0.0, rx := 0.0) -> void:
	var b := Basis(Vector3.UP, ry) * Basis(Vector3.RIGHT, rx)
	var xf := _xf * Transform3D(b, p + b * Vector3(0, s.y * 0.5, 0))
	var h := s * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for f: Array in [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3], [0, 1, 5, 4]]:
		_quad(m, xf * c[f[0]], xf * c[f[1]], xf * c[f[2]], xf * c[f[3]], xf.origin)


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
## placed by xf inside the current group.
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


## Rounded merlon cap: half cylinder of radius r along local x (length len), dome up, base at p.
func _half_cyl(m: int, r: float, len: float, p: Vector3) -> void:
	var seg := 6
	for i in seg:
		var a0 := float(i) / seg * PI
		var a1 := float(i + 1) / seg * PI
		var d0 := Vector3(0, sin(a0), cos(a0))
		var d1 := Vector3(0, sin(a1), cos(a1))
		var q := [p + d0 * r + Vector3(-len * 0.5, 0, 0), p + d1 * r + Vector3(-len * 0.5, 0, 0), p + d1 * r + Vector3(len * 0.5, 0, 0), p + d0 * r + Vector3(len * 0.5, 0, 0)]
		_tri_n(m, _xf * q[0], _xf * q[2], _xf * q[1], _xf.basis * d0, _xf.basis * d1, _xf.basis * d1)
		_tri_n(m, _xf * q[0], _xf * q[3], _xf * q[2], _xf.basis * d0, _xf.basis * d0, _xf.basis * d1)
		_tri(m, _xf * (p + Vector3(len * 0.5, 0, 0)), _xf * q[3], _xf * q[2], _xf * p)
		_tri(m, _xf * (p - Vector3(len * 0.5, 0, 0)), _xf * q[1], _xf * q[0], _xf * p)


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
## vertices comes from the face's dominant axis (the preview's boxUV), so a face never smears its texture.
func _tri_n(m: int, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if not _st.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[m] = st
	var st: SurfaceTool = _st[m]
	var fn := (na + nb + nc).normalized()
	var k := 1.0 / _tile(m)
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
		st.set_normal(v[1])
		st.set_uv(uv * k)
		st.add_vertex(p * K)


func _commit() -> ArrayMesh:
	var out := ArrayMesh.new()
	for m: int in _st.keys():
		var st: SurfaceTool = _st[m]
		st.generate_tangents()
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, material(m))
	return out
