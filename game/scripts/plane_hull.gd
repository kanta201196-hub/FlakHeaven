class_name PlaneHull
extends RefCounted
## The skin of a plane model as triangles in model axes (nose +X, up +Y, left wing −Z, length 1), read once per model
## mesh and shared by everything laid onto the skin: SkinPatch (flare panels, turret fairings) and DecalMesh (the
## player's decals and the editor's cursor). One cache, so the hangar model is read once however many systems use it.
##
## The skin is the model's own body mesh: its textured surfaces (no glass, no wheel wells), without the parts that
## move (slats, flaps, bay doors) or are added on top (insignia, modules, wing kit, decals, fairings). Two lookups:
## `in_rect_xz` + `top_hit` — the highest skin under a point seen from above (a linear scan, cheap for a few calls);
## `near` + `raycast` — a uniform grid, built on first use, for the many lookups of decal cutting and the cursor.
## `extra` chains a second, uncached hull (the turret fairings built at run time) into `raycast` and the decal cutter.

const CELL := 0.03   ## grid cell, model units
## Nodes whose meshes are never skin: moving parts and everything other systems add to the model
const SKIP_NODES := ["wing_mech", "bay_doors", "insignia", "module_parts", "wing_kit", "decals"]

static var _cache := {}   # body Mesh → PlaneHull

var pos := PackedVector3Array()   ## 3 per triangle
var nrm := PackedVector3Array()   ## vertex normals, 3 per triangle
var uv := PackedVector2Array()    ## skin texture UV, 3 per triangle (empty when unknown)
var tex: Texture2D = null         ## the skin's albedo texture
var extra: PlaneHull = null       ## more skin built at run time (turret fairings); not cached
var _grid := {}                   # Vector3i → Array of triangle indices; built on first `near` / `raycast`
var _indexed := false


## Hull from flat triangle arrays (tests, fairing meshes)
static func from_triangles(p: PackedVector3Array, n: PackedVector3Array, t_uv := PackedVector2Array(),
		texture: Texture2D = null) -> PlaneHull:
	var h := PlaneHull.new()
	h.pos = p
	h.nrm = n
	h.uv = t_uv
	h.tex = texture
	return h


## The cached skin of `model` (null when it has no textured body mesh)
static func of(model: Node3D) -> PlaneHull:
	var mi := body(model)
	if mi == null:
		return null
	if _cache.has(mi.mesh):
		return _cache[mi.mesh]
	var h := from_meshes([mi], model, true)
	_cache[mi.mesh] = h
	return h


## The canopy glass of `model`'s body mesh (its surfaces with the «glass» material), cached like the skin; an
## empty hull when the model has none. The decal cursor stops on it (`raycast_clear`).
static func glass_of(model: Node3D) -> PlaneHull:
	var mi := body(model)
	if mi == null:
		return null
	if _glass_cache.has(mi.mesh):
		return _glass_cache[mi.mesh]
	var h := PlaneHull.new()
	var xf := rel_transform(mi, model)
	for si in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(si)   # the glass is a ShaderMaterial (canopy_glass.tres)
		if m != null and String(m.resource_name) == "glass":
			_append_surface(h, mi.mesh, si, xf)
	_glass_cache[mi.mesh] = h
	return h


static var _glass_cache := {}   # body Mesh → its glass as a PlaneHull


## The body mesh of `model`: the first mesh with a textured first surface that is not a moving or added part
static func body(model: Node3D) -> MeshInstance3D:
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0 or under(mi, model, SKIP_NODES):
			continue
		var nm := String(mi.name)
		if nm.begins_with("slat") or nm.begins_with("flap"):
			continue
		var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
		if m != null and m.albedo_texture != null and String(m.resource_name) != "glass":
			return mi
	return null


## Hull of the given meshes in `model` axes; `textured_only` keeps only surfaces with an albedo texture (the skin),
## otherwise every surface but glass (vertex-coloured fairings)
static func from_meshes(meshes: Array[MeshInstance3D], model: Node3D, textured_only: bool) -> PlaneHull:
	var h := PlaneHull.new()
	for mi in meshes:
		var xf := rel_transform(mi, model)
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m != null and String(m.resource_name) == "glass":
				continue
			if textured_only and (m == null or m.albedo_texture == null):
				continue
			if h.tex == null and m != null:
				h.tex = m.albedo_texture
			_append_surface(h, mi.mesh, si, xf)
	return h


## Appends the triangles of surface `si` of `mesh`, moved by `xf` into model axes
static func _append_surface(h: PlaneHull, mesh: Mesh, si: int, xf: Transform3D) -> void:
	var arr := mesh.surface_get_arrays(si)
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var iv: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var n := iv.size() if iv.size() > 0 else vv.size()
	n -= n % 3
	for i in n:
		var k := iv[i] if iv.size() > 0 else i
		h.pos.append(xf * vv[k])
		h.nrm.append((xf.basis * (nv[k] if nv.size() > k else Vector3.UP)).normalized())
		h.uv.append(tv[k] if tv.size() > k else Vector2.ZERO)


## This hull plus `more` skin, without touching the cached hull (other planes share it): a view that shares the
## triangles and the grid
func with_extra(more: PlaneHull) -> PlaneHull:
	_index()
	var h := PlaneHull.new()
	h.pos = pos
	h.nrm = nrm
	h.uv = uv
	h.tex = tex
	h._grid = _grid
	h._indexed = true
	h.extra = more
	return h


## Number of triangles (without `extra`)
func triangles() -> int:
	return int(pos.size() / 3.0)


## Triangles whose x/z box overlaps `r` (x along r.position.x, z along r.position.y)
func in_rect_xz(r: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	for t in triangles():
		var a := pos[t * 3]
		var b := pos[t * 3 + 1]
		var c := pos[t * 3 + 2]
		if maxf(a.x, maxf(b.x, c.x)) < x0 or minf(a.x, minf(b.x, c.x)) > x1:
			continue
		if maxf(a.z, maxf(b.z, c.z)) < z0 or minf(a.z, minf(b.z, c.z)) > z1:
			continue
		out.append(t)
	return out


## Highest of the triangles `cand` straight under (x, z): {"y", "n" (geometric normal, facing up), "uv"}; {} on a miss
func top_hit(cand: PackedInt32Array, x: float, z: float) -> Dictionary:
	var best := {}
	var p := Vector2(x, z)
	for t in cand:
		var a := pos[t * 3]
		var b := pos[t * 3 + 1]
		var c := pos[t * 3 + 2]
		var a2 := Vector2(a.x, a.z)
		var v0 := Vector2(b.x, b.z) - a2
		var v1 := Vector2(c.x, c.z) - a2
		var v2 := p - a2
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-14:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u < 0.0 or w < 0.0 or u + w > 1.0:
			continue
		var y := a.y + u * (b.y - a.y) + w * (c.y - a.y)
		if best.is_empty() or y > float(best["y"]):
			var n := (b - a).cross(c - a).normalized()
			if n.y < 0.0:
				n = -n
			var tuv := Vector2.ZERO
			if uv.size() > t * 3 + 2:
				tuv = uv[t * 3] + u * (uv[t * 3 + 1] - uv[t * 3]) + w * (uv[t * 3 + 2] - uv[t * 3])
			best = {"y": y, "n": n, "uv": tuv}
	return best


## Triangle indices in the grid cells of an axis-aligned box (each once)
func near(lo: Vector3, hi: Vector3) -> PackedInt32Array:
	_index()
	var out := PackedInt32Array()
	var seen := {}
	var a := cell_of(lo)
	var b := cell_of(hi)
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				var k := Vector3i(x, y, z)
				if _grid.has(k):
					for t: int in _grid[k]:
						if not seen.has(t):
							seen[t] = true
							out.append(t)
	return out


## First skin hit facing the ray (Möller–Trumbore), `extra` included: [position, smooth normal], or [] on a miss
func raycast(origin: Vector3, dir: Vector3, max_len := 3.0) -> Array:
	var hit := _raycast_own(origin, dir, max_len).slice(0, 2)
	if extra != null:
		var e := extra.raycast(origin, dir, max_len)
		if e.size() == 2 and (hit.is_empty() or origin.distance_to(e[0]) < origin.distance_to(hit[0])):
			hit = e
	return hit


## `raycast`, but [] when `blocker` (the canopy glass) is hit first: the cursor must not reach the skin under the
## glass, where a decal would be hidden. A null blocker gives the plain raycast.
func raycast_clear(origin: Vector3, dir: Vector3, max_len: float, blocker: PlaneHull) -> Array:
	var hit := raycast(origin, dir, max_len)
	if hit.is_empty() or blocker == null:
		return hit
	var b := blocker.raycast(origin, dir, max_len)
	if b.size() == 2 and origin.distance_to(b[0]) < origin.distance_to(hit[0]) - 0.001:
		return []
	return hit


## First own hit facing the ray (no `extra`) with the triangle it hit: [position, smooth normal, triangle], or []
## on a miss. The decal audit uses the triangle to tell which part of the model the cursor would land on.
func ray_hit(origin: Vector3, dir: Vector3, max_len := 3.0) -> Array:
	return _raycast_own(origin, dir, max_len)


func _raycast_own(origin: Vector3, dir: Vector3, max_len: float) -> Array:
	_index()
	var d := dir.normalized()
	var best := INF
	var hit: Array = []
	var tested := {}
	var s := 0.0
	while s <= max_len:
		var k := cell_of(origin + d * s)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var kk := k + Vector3i(dx, dy, dz)
					if not _grid.has(kk):
						continue
					for t: int in _grid[kk]:
						if tested.has(t):
							continue
						tested[t] = true
						var r := _ray_tri(origin, d, t)
						if r.size() == 3 and float(r[0]) < best:
							best = float(r[0])
							var nn: Vector3 = (nrm[t * 3] * (1.0 - r[1] - r[2]) + nrm[t * 3 + 1] * r[1]
								+ nrm[t * 3 + 2] * r[2]).normalized()
							hit = [origin + d * best, nn, t]
		if hit.size() > 0 and best < s - CELL:
			break
		s += CELL * 0.5
	return hit


func _ray_tri(o: Vector3, d: Vector3, t: int) -> Array:
	var a := pos[t * 3]
	var e1 := pos[t * 3 + 1] - a
	var e2 := pos[t * 3 + 2] - a
	var fn := nrm[t * 3] + nrm[t * 3 + 1] + nrm[t * 3 + 2]
	if fn.dot(d) >= 0.0:
		return []   # back side
	var pv := d.cross(e2)
	var det := e1.dot(pv)
	if absf(det) < 1e-12:
		return []
	var inv := 1.0 / det
	var tv := o - a
	var u := tv.dot(pv) * inv
	if u < 0.0 or u > 1.0:
		return []
	var qv := tv.cross(e1)
	var v := d.dot(qv) * inv
	if v < 0.0 or u + v > 1.0:
		return []
	var dist := e2.dot(qv) * inv
	return [dist, u, v] if dist > 0.0 else []


## Fills the grid once: each triangle goes into every cell its bounding box touches
func _index() -> void:
	if _indexed:
		return
	_indexed = true
	for t in triangles():
		var a := pos[t * 3]
		var b := pos[t * 3 + 1]
		var c := pos[t * 3 + 2]
		var lo := cell_of(a.min(b).min(c))
		var hi := cell_of(a.max(b).max(c))
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var k := Vector3i(x, y, z)
					if not _grid.has(k):
						_grid[k] = []
					(_grid[k] as Array).append(t)


## Grid cell of a point
static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


## True when a parent of `n` below `model` has one of the `names`
static func under(n: Node, model: Node, names: Array) -> bool:
	var p := n.get_parent()
	while p != null and p != model:
		if String(p.name) in names:
			return true
		p = p.get_parent()
	return false


## Transform of a mesh in model axes (without the model root's own transform)
static func rel_transform(mi: Node3D, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
