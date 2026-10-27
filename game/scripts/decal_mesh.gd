class_name DecalMesh
extends RefCounted
## Builds the decal mesh of one plane (Kanta 27.10, free placement): every stamp's oriented box cuts the hull
## triangles inside it (Sutherland–Hodgman against the box sides), the pieces are lifted along the skin normal so
## they never z-fight, and all decals of the plane merge into one ArrayMesh — one draw call in combat. Plain
## triangles and one ShaderMaterial: works in Forward+ and GL Compatibility (Godot `Decal` nodes do not exist there).
## The hull (`PlaneHull`, shared with SkinPatch) is read once per model mesh; its grid makes a placement visit only
## nearby triangles, and `PlaneHull.raycast` is the editor's cursor on the skin. Turret fairings built at run time
## ride along as the hull's `extra` and get their share of a decal too.

const LIFT := 0.0009      ## off the skin, model units (insignia use 0.0008)
const MIN_FACING := 0.25  ## skin turned further than this from the decal (the far side of a fin) is skipped


## Collected decal triangles (non-indexed); `mesh()` turns them into one ArrayMesh surface
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var paints := PackedVector2Array()   ## UV2: primary and secondary paint index
	var lift := DecalMesh.LIFT           ## the editor's preview sits higher, over the committed decals

	## Cuts the hull under one stamp and appends the pieces
	func project(hull: PlaneHull, st: DecalStamp) -> void:
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
					verts.append((v[0] as Vector3) + n * lift)
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


## One merged mesh for all `records` on the hull; `tally` — marks for tally decals; `lift` — distance off the skin
static func build(hull: PlaneHull, records: Array[DecalRecord], tally: int, lift := LIFT) -> ArrayMesh:
	var b := Builder.new()
	b.lift = lift
	for r in records:
		for st in DecalLoadout.stamps(r, tally):
			b.project(hull, st)
			if hull.extra != null:
				b.project(hull.extra, st)
	return b.mesh()
