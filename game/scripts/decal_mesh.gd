class_name DecalMesh
extends RefCounted
## Builds the decal mesh of one plane (Kanta 27.10, free placement): every stamp's oriented box cuts the hull
## triangles inside it (Sutherland–Hodgman against the box sides), the pieces are lifted along the skin normal so
## they never z-fight, and all decals of the plane merge into one ArrayMesh — one draw call in combat. Plain
## triangles and one ShaderMaterial: works in Forward+ and GL Compatibility (Godot `Decal` nodes do not exist there).
## The hull is read once per model mesh and cached with a uniform grid, so a placement only visits nearby triangles.
## `Hull.raycast` is the editor's cursor on the skin (and places the debug samples).

const LIFT := 0.0009      ## off the skin, model units (insignia use 0.0008)
const MIN_FACING := 0.25  ## skin turned further than this from the decal (the far side of a fin) is skipped
const CELL := 0.03        ## grid cell of the hull, model units
const SKIP_NODES := ["insignia", "module_parts", "wing_kit", "decals"]

static var _hulls := {}   # first body mesh instance id → Hull


## Triangles of the hull in model axes, bucketed in a uniform grid
class Hull:
	extends RefCounted
	var pos := PackedVector3Array()   ## 3 per triangle
	var nrm := PackedVector3Array()   ## vertex normals, 3 per triangle
	var grid := {}                    ## Vector3i → Array of triangle indices

	## Hull from flat triangle arrays (tests, or arrays read from meshes)
	static func from_triangles(p: PackedVector3Array, n: PackedVector3Array) -> Hull:
		var h := Hull.new()
		h.pos = p
		h.nrm = n
		h.index()
		return h

	## Fills the grid: each triangle goes into every cell its bounding box touches
	func index() -> void:
		grid.clear()
		for t in int(pos.size() / 3.0):
			var a := pos[t * 3]
			var b := pos[t * 3 + 1]
			var c := pos[t * 3 + 2]
			var lo := DecalMesh.cell_of(a.min(b).min(c))
			var hi := DecalMesh.cell_of(a.max(b).max(c))
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var k := Vector3i(x, y, z)
						if not grid.has(k):
							grid[k] = []
						(grid[k] as Array).append(t)

	## Triangle indices in the cells of an axis-aligned box (each once)
	func near(lo: Vector3, hi: Vector3) -> PackedInt32Array:
		var out := PackedInt32Array()
		var seen := {}
		var a := DecalMesh.cell_of(lo)
		var b := DecalMesh.cell_of(hi)
		for x in range(a.x, b.x + 1):
			for y in range(a.y, b.y + 1):
				for z in range(a.z, b.z + 1):
					var k := Vector3i(x, y, z)
					if grid.has(k):
						for t: int in grid[k]:
							if not seen.has(t):
								seen[t] = true
								out.append(t)
		return out

	## First skin hit facing the ray (Möller–Trumbore): [position, smooth normal], or [] when it misses
	func raycast(origin: Vector3, dir: Vector3, max_len := 3.0) -> Array:
		var d := dir.normalized()
		var best := INF
		var hit: Array = []
		var tested := {}
		var s := 0.0
		while s <= max_len:
			var p := origin + d * s
			var k := DecalMesh.cell_of(p)
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var kk := k + Vector3i(dx, dy, dz)
						if not grid.has(kk):
							continue
						for t: int in grid[kk]:
							if tested.has(t):
								continue
							tested[t] = true
							var r := _ray_tri(origin, d, t)
							if r.size() == 3 and float(r[0]) < best:
								best = float(r[0])
								var nn: Vector3 = (nrm[t * 3] * (1.0 - r[1] - r[2]) + nrm[t * 3 + 1] * r[1]
									+ nrm[t * 3 + 2] * r[2]).normalized()
								hit = [origin + d * best, nn]
			if hit.size() > 0 and best < s - DecalMesh.CELL:
				break
			s += DecalMesh.CELL * 0.5
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


## Collected decal triangles (non-indexed); `mesh()` turns them into one ArrayMesh surface
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var paints := PackedVector2Array()   ## UV2: primary and secondary paint index

	## Cuts the hull under one stamp and appends the pieces
	func project(hull: Hull, st: DecalStamp) -> void:
		var depth := maxf(st.half_w, st.half_h) + 0.004
		var ext := (st.right.abs() * st.half_w + st.up.abs() * st.half_h + st.normal.abs() * depth)
		for t in hull.near(st.center - ext, st.center + ext):
			var na := hull.nrm[t * 3]
			var nb := hull.nrm[t * 3 + 1]
			var nc := hull.nrm[t * 3 + 2]
			if (na + nb + nc).normalized().dot(st.normal) < DecalMesh.MIN_FACING:
				continue
			var poly: Array = []   # [position, normal, Vector2(x, y) in −1…1 box units]
			var out_z := 0
			for i in 3:
				var p := hull.pos[t * 3 + i]
				var rel := p - st.center
				var z := rel.dot(st.normal)
				if absf(z) > depth:
					out_z += 1
				poly.append([p, hull.nrm[t * 3 + i], Vector2(rel.dot(st.right) / st.half_w, rel.dot(st.up) / st.half_h)])
			if out_z == 3:
				continue
			poly = DecalMesh.clip(poly)
			if poly.size() < 3:
				continue
			for i in range(1, poly.size() - 1):
				for v: Array in [poly[0], poly[i], poly[i + 1]]:
					var n: Vector3 = (v[1] as Vector3).normalized()
					var xy: Vector2 = v[2]
					var u := xy.x * 0.5 + 0.5
					if st.mirror:
						u = 1.0 - u
					verts.append((v[0] as Vector3) + n * DecalMesh.LIFT)
					normals.append(n)
					uvs.append(st.uv.position + Vector2(u, 0.5 - xy.y * 0.5) * st.uv.size)
					paints.append(Vector2(st.c1, st.c2))

	## One-surface mesh of everything projected so far (null when empty)
	func mesh() -> ArrayMesh:
		if verts.is_empty():
			return null
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = paints
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


## Grid cell of a point
static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


## Clips a polygon of [position, normal, box xy] to the box sides |x| ≤ 1, |y| ≤ 1
static func clip(poly: Array) -> Array:
	for axis in 2:
		for sgn: float in [1.0, -1.0]:
			if poly.is_empty():
				return poly
			var out: Array = []
			for i in poly.size():
				var a: Array = poly[i]
				var b: Array = poly[(i + 1) % poly.size()]
				var da := 1.0 - sgn * (a[2] as Vector2)[axis]
				var db := 1.0 - sgn * (b[2] as Vector2)[axis]
				if da >= 0.0:
					out.append(a)
				if (da >= 0.0) != (db >= 0.0):
					var k := da / (da - db)
					out.append([(a[0] as Vector3).lerp(b[0], k), (a[1] as Vector3).lerp(b[1], k),
						(a[2] as Vector2).lerp(b[2], k)])
			poly = out
	return poly


## Hull of a plane model (cached per model mesh): textured skin meshes only — no glass, no moving slats and flaps,
## no add-ons (insignia, modules, wing kit, decals)
static func hull_of(model: Node3D) -> Hull:
	var body: Array[MeshInstance3D] = []
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or _skipped(mi, model):
			continue
		var nm := String(mi.name)
		if nm.begins_with("slat") or nm.begins_with("flap"):
			continue
		var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
		if m != null and m.albedo_texture != null:
			body.append(mi)
	if body.is_empty():
		return null
	var key: int = body[0].mesh.get_instance_id()
	if _hulls.has(key):
		return _hulls[key]
	var p := PackedVector3Array()
	var n := PackedVector3Array()
	for mi in body:
		var xf := rel_transform(mi, model)
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si)
			if mat != null and String(mat.resource_name) == "glass":
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var iv: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if iv.is_empty():
				for i in vv.size():
					iv.append(i)
			for i in iv.size() - iv.size() % 3:
				p.append(xf * vv[iv[i]])
				n.append((xf.basis * (nv[iv[i]] if nv.size() > 0 else Vector3.UP)).normalized())
	var h := Hull.from_triangles(p, n)
	_hulls[key] = h
	return h


## One merged mesh for all `records` on the hull; `tally` — marks for tally decals
static func build(hull: Hull, records: Array[DecalRecord], tally: int) -> ArrayMesh:
	var b := Builder.new()
	for r in records:
		for st in DecalLoadout.stamps(r, tally):
			b.project(hull, st)
	return b.mesh()


static func _skipped(mi: Node, model: Node3D) -> bool:
	var n: Node = mi
	while n != null and n != model:
		if String(n.name) in SKIP_NODES:
			return true
		n = n.get_parent()
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
