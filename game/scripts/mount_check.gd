class_name MountCheck
extends RefCounted
## Cheap geometry checks for the build self-check (R-23, tools/ci/selfcheck.sh): does a mounted part (a weapon on
## its pylon, a turret on its ring, a nozzle flame, a muzzle point) touch the plane it belongs to, or does it
## float beside it? Everything works on plain triangle soups (3 Vector3 per face) in one set of axes, so the same
## code serves the hangar model (length 1) and the battle model (picture pixels): the caller scales the limits.
## No physics and no rendering: the hangar and Render3D hand over their nodes, SelfCheck reads the results.


## Triangles of every MeshInstance3D under `root` (root included) in the axes of `space`, 3 points per face.
## Nodes named in `skip` are left out with everything under them (the weapons hanging on the model, its flames).
## `space` is `root` itself or one of its ancestors; the local transforms are chained, so no tree is needed.
static func faces_of(root: Node3D, space: Node3D, skip: PackedStringArray = PackedStringArray()) -> PackedVector3Array:
	var out := PackedVector3Array()
	_collect(root, rel_xf(root, space), skip, out)
	return out


## Transform from the axes of node `n` to those of its ancestor `space`: identity when n is space, the chain of
## local transforms from n up to (not including) space otherwise.
static func rel_xf(n: Node, space: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != space:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Adds the faces of `n` (its axes → space is `xf`) and of everything under it.
static func _collect(n: Node, xf: Transform3D, skip: PackedStringArray, out: PackedVector3Array) -> void:
	if skip.has(String(n.name)):
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		for v in (n as MeshInstance3D).mesh.get_faces():
			out.append(xf * v)
	for c in n.get_children():
		_collect(c, xf * (c as Node3D).transform if c is Node3D else xf, skip, out)


## Up to `max_n` vertices of `mesh` (every k-th of its surfaces' vertex arrays), moved by `xf`: the sample a part's
## gap to the plane is measured from. Dense enough that a pylon's top face is in it (the hangar weapons have a few
## thousand vertices).
static func mesh_points(mesh: Mesh, xf: Transform3D, max_n := 4000) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh == null:
		return out
	var all := PackedVector3Array()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			all.append_array(arr[Mesh.ARRAY_VERTEX])
	var step := maxi(1, ceili(float(all.size()) / float(maxi(1, max_n))))
	for i in range(0, all.size(), step):
		out.append(xf * all[i])
	return out


## Vertex sample (mesh_points) of `node` and of its visible mesh children in the axes of its ancestor `space`: a
## weapon with its pylon, a tail turret with its cabin. Hidden parts (turret launch pods before their card) are left out.
static func node_points(node: Node3D, space: Node3D, max_n := 4000) -> PackedVector3Array:
	var out := PackedVector3Array()
	if node is MeshInstance3D:
		out = mesh_points((node as MeshInstance3D).mesh, rel_xf(node, space), max_n)
	for c in node.get_children():
		if c is Node3D and (c as Node3D).visible:
			out.append_array(node_points(c as Node3D, space, max_n))
	return out


## Spatial hash of `faces` in cubes of side `cell`: each face is listed in every cube its bounds touch. grid_gap
## then looks only at the faces round each point, so thousands of points cost little against a 50k-face model.
static func build_grid(faces: PackedVector3Array, cell: float) -> Dictionary:
	var map: Dictionary = {}
	var inv := 1.0 / cell
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var lo := Vector3i((a.min(b).min(c) * inv).floor())
		var hi := Vector3i((a.max(b).max(c) * inv).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var k := Vector3i(x, y, z)
					if not map.has(k):
						map[k] = PackedInt32Array()
					var ids: PackedInt32Array = map[k]
					ids.append(i)
					map[k] = ids   # packed arrays are values: store the grown copy back
	return {"cell": cell, "faces": faces, "map": map}


## Smallest distance from any of `points` to the faces of `grid` (build_grid); INF when none lies within the grid's
## cell size of them (the search covers only the 27 cubes round each point, so farther means "more than a cell").
## `enough`: stop as soon as a gap this small is found (the caller only asks "within the limit?"; a part that
## touches the skin then costs a few points instead of thousands).
static func grid_gap(grid: Dictionary, points: PackedVector3Array, enough := 0.0) -> float:
	var cell: float = grid["cell"]
	var faces: PackedVector3Array = grid["faces"]
	var map: Dictionary = grid["map"]
	var inv := 1.0 / cell
	var best := INF
	for p in points:
		var c := Vector3i((p * inv).floor())
		for x in range(c.x - 1, c.x + 2):
			for y in range(c.y - 1, c.y + 2):
				for z in range(c.z - 1, c.z + 2):
					var k := Vector3i(x, y, z)
					if not map.has(k):
						continue
					var ids: PackedInt32Array = map[k]
					for i in ids:
						var d := p.distance_to(closest_on_triangle(p, faces[i], faces[i + 1], faces[i + 2]))
						if d < best:
							best = d
							if best <= enough:
								return best
	return best if best <= cell else INF


## Points on a circle of radius `r` round `centre`, in the plane normal to `axis` (a nozzle lip).
static func ring(centre: Vector3, axis: Vector3, r: float, n := 8) -> PackedVector3Array:
	var a := axis.normalized()
	var u := a.cross(Vector3.UP if absf(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var v := a.cross(u).normalized()
	var out := PackedVector3Array()
	for i in n:
		var t := TAU * float(i) / float(n)
		out.append(centre + (u * cos(t) + v * sin(t)) * r)
	return out


## Closest point to `p` on triangle a-b-c (Ericson, «Real-Time Collision Detection» 5.1.5).
static func closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## The faces of `faces` whose bounds come within `reach` of box `box`: one cheap pass, so the exact distances
## below run over a few hundred triangles instead of the whole 50-thousand-face hangar model.
static func near_faces(faces: PackedVector3Array, box: AABB, reach: float) -> PackedVector3Array:
	var lo := box.position - Vector3.ONE * reach
	var hi := box.end + Vector3.ONE * reach
	var out := PackedVector3Array()
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if maxf(a.x, maxf(b.x, c.x)) < lo.x or minf(a.x, minf(b.x, c.x)) > hi.x:
			continue
		if maxf(a.y, maxf(b.y, c.y)) < lo.y or minf(a.y, minf(b.y, c.y)) > hi.y:
			continue
		if maxf(a.z, maxf(b.z, c.z)) < lo.z or minf(a.z, minf(b.z, c.z)) > hi.z:
			continue
		out.append(a)
		out.append(b)
		out.append(c)
	return out


## Distance from point `p` to the nearest face; INF when no face lies within `reach` (then the exact value does not
## matter: the part floats farther than any limit the caller uses).
static func point_gap(faces: PackedVector3Array, p: Vector3, reach: float) -> float:
	return points_gap(faces, PackedVector3Array([p]), reach)


## Smallest distance from any of `points` to the nearest face (0 when a point lies on the surface or the sample
## pierces it); INF when nothing lies within `reach` of them. Plain search: for a handful of points.
static func points_gap(faces: PackedVector3Array, points: PackedVector3Array, reach: float) -> float:
	if points.is_empty() or faces.is_empty():
		return INF
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	var near := near_faces(faces, box, reach)
	var best := INF
	for p in points:
		for i in range(0, near.size() - 2, 3):
			var d := p.distance_to(closest_on_triangle(p, near[i], near[i + 1], near[i + 2]))
			if d < best:
				best = d
				if best <= 0.0:
					return 0.0
	return best if best <= reach else INF


## Mean distance of `points` to the nearest face (INF when one of them has nothing within `reach`): how well a ring
## of points (a flame's nozzle lip) sits on the surface as a whole, not only its best point.
static func mean_gap(faces: PackedVector3Array, points: PackedVector3Array, reach: float) -> float:
	if points.is_empty():
		return INF
	var sum := 0.0
	for p in points:
		var g := point_gap(faces, p, reach)
		if is_inf(g):
			return INF
		sum += g
	return sum / float(points.size())
