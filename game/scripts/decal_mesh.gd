class_name DecalMesh
extends RefCounted
## Builds the decal mesh of one plane (Kanta 27.10, free placement): every stamp's oriented box cuts the hull
## triangles inside it (Sutherland–Hodgman against the box sides and its depth), the pieces are lifted off the skin
## so they never z-fight, and all decals of the plane merge into one ArrayMesh — one draw call in combat. Plain
## triangles and one ShaderMaterial: works in Forward+ and GL Compatibility (Godot `Decal` nodes do not exist there).
## The hull (`PlaneHull`, shared with SkinPatch) is read once per model mesh; its grid makes a placement visit only
## nearby triangles, and `PlaneHull.raycast` is the editor's cursor on the skin. Turret fairings, silhouette details
## and the tail cabin ride along as the hull's `extra`; moving parts get meshes of their own (`PlaneDecals`).
##
## Geometry rules, measured by the decal audit (`--decalaudit`, DecalAudit):
## - a triangle counts by its own face, not its smoothed normals: the plane bodies are double-sided and carry flipped
##   and sharp-edged triangles, whose vertex normals point away from the face; pieces are always wound to face the
##   decal, so the decal material can cull back faces;
## - the decal fades out where the skin turns more than ~60° from it (per-vertex `COLOR.a`, cut by the alpha scissor
##   along a smooth line) instead of stretching round a nose or over an edge onto the other side;
## - the depth slab is clipped too: one large triangle of a battle hull crossing the box is cut, not dropped;
## - decals lie under the roundels (insignia sit 0.8 mm off the skin), and each later decal a hair higher than the
##   one before, so overlapping decals draw in list order instead of z-fighting.

const LIFT := 0.00025       ## off the skin, model units (insignia 0.0008: the roundels stay on top, spec §2.4)
const LIFT_STEP := 0.00003  ## each later decal of the list lies this much higher: overlaps draw in list order
const MIN_FACING := 0.3     ## skin turned further than ~72° from the decal gets no piece at all
const FADE_FROM := 0.42     ## facing (cos) where the decal starts to fade …
const FADE_TO := 0.58       ## … and where it is whole; the alpha scissor cuts at ~60°
const DEPTH_PAD := 0.004    ## the box reaches this much deeper than half the decal's size, model units


## Collected decal triangles (non-indexed); `mesh()` turns them into one ArrayMesh surface
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var paints := PackedVector2Array()   ## UV2: primary and secondary paint index
	var colors := PackedColorArray()     ## alpha: the fade at a steep skin
	var lift := DecalMesh.LIFT           ## the editor's preview sits higher, over the committed decals
	var blockers: Array[PlaneHull] = []  ## moving parts lying over the skin: no piece under them (battle flaps)
	var to_local := Transform3D.IDENTITY ## pieces go out in these axes (a moving part's own)

	## Cuts the hull under one stamp and appends the pieces
	func project(hull: PlaneHull, st: DecalStamp) -> void:
		var depth := maxf(st.half_w, st.half_h) + DecalMesh.DEPTH_PAD
		var ext := (st.right.abs() * st.half_w + st.up.abs() * st.half_h + st.normal.abs() * depth)
		var wind := float(hull.winding())
		for t in hull.near(st.center - ext, st.center + ext):
			var gn := DecalMesh.face_normal(hull, t, wind)
			if gn == Vector3.ZERO:
				continue
			var facing := gn.dot(st.normal)
			if facing < DecalMesh.MIN_FACING:
				continue
			var poly: Array = []   # [position, normal, Vector3(x, y, z) in −1…1 box units]
			var above := 0
			var below := 0
			for i in 3:
				var p := hull.pos[t * 3 + i]
				var rel := p - st.center
				var z := rel.dot(st.normal) / depth
				above += int(z > 1.0)
				below += int(z < -1.0)
				poly.append([p, hull.nrm[t * 3 + i], Vector3(rel.dot(st.right) / st.half_w, rel.dot(st.up) / st.half_h, z)])
			if above == 3 or below == 3:
				continue
			poly = DecalMesh.clip(poly)
			if poly.size() < 3 or _blocked(poly, st, depth):
				continue
			var flip := (hull.pos[t * 3 + 1] - hull.pos[t * 3]).cross(hull.pos[t * 3 + 2] - hull.pos[t * 3]).dot(gn) > 0.0
			for i in range(1, poly.size() - 1):
				var tri: Array = [poly[0], poly[i + 1], poly[i]] if flip else [poly[0], poly[i], poly[i + 1]]
				var p0: Vector3 = tri[0][0]
				if ((tri[1][0] as Vector3) - p0).cross((tri[2][0] as Vector3) - p0).length_squared() < 1e-18:
					continue   # a sliver left where a corner lay on a box side
				for v: Array in tri:
					_vertex(v, gn, st)

	## One vertex of a piece: lifted along its smooth normal (along the face where that normal lies), faded by how
	## far the skin there turns from the decal
	func _vertex(v: Array, gn: Vector3, st: DecalStamp) -> void:
		var n: Vector3 = (v[1] as Vector3).normalized()
		var p: Vector3 = v[0]
		var xyz: Vector3 = v[2]
		var sharp := n.dot(gn) < 0.5   # a sharp edge or a flipped triangle: the smoothed normal says nothing
		if sharp:
			n = gn
		var u := xyz.x * 0.5 + 0.5
		if st.mirror:
			u = 1.0 - u
		verts.append(to_local * (p + n * lift))
		normals.append((to_local.basis * n).normalized())
		uvs.append(st.uv.position + Vector2(u, 0.5 - xyz.y * 0.5) * st.uv.size)
		paints.append(Vector2(st.c1, st.c2))
		colors.append(Color(1, 1, 1, smoothstep(DecalMesh.FADE_FROM, DecalMesh.FADE_TO, n.dot(st.normal))))

	## True when a moving part lies over the piece (its centre seen along the decal's normal within the box depth):
	## the piece would show as a ghost on the wing when the flap goes down
	func _blocked(poly: Array, st: DecalStamp, depth: float) -> bool:
		if blockers.is_empty():
			return false
		var c := Vector3.ZERO
		for v: Array in poly:
			c += v[0]
		c /= poly.size()
		for b in blockers:
			if not b.bounds().grow(depth).has_point(c):
				continue
			# shot from the viewer's side towards the piece: a part's outer face in between hides it
			if b.raycast(c + st.normal * depth * 2.0, -st.normal, depth * 2.0 - 0.0005).size() == 2:
				return true
		return false

	## One-surface mesh of everything projected so far (null when empty)
	func mesh() -> ArrayMesh:
		if verts.is_empty():
			return null
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = paints
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


## Outward face normal of triangle `t`: its winding normal turned to the side its smooth normals point to; where
## they disagree with the face (a sharp edge, a crease) the model's own winding (`wind`, PlaneHull.winding) decides.
## Zero for a degenerate triangle.
static func face_normal(hull: PlaneHull, t: int, wind: float) -> Vector3:
	var a := hull.pos[t * 3]
	var cr := (hull.pos[t * 3 + 1] - a).cross(hull.pos[t * 3 + 2] - a)
	if cr.length_squared() < 1e-20:
		return Vector3.ZERO
	cr = cr.normalized()
	var sm := hull.nrm[t * 3] + hull.nrm[t * 3 + 1] + hull.nrm[t * 3 + 2]
	var d := cr.dot(sm.normalized()) if sm.length_squared() > 1e-12 else 0.0
	return cr * (signf(d) if absf(d) >= 0.5 else wind)


## Clips a polygon of [position, normal, box xyz] to the box |x| ≤ 1, |y| ≤ 1, |z| ≤ 1
static func clip(poly: Array) -> Array:
	for axis in 3:
		for sgn: float in [1.0, -1.0]:
			if poly.is_empty():
				return poly
			var out: Array = []
			for i in poly.size():
				var a: Array = poly[i]
				var b: Array = poly[(i + 1) % poly.size()]
				var da := 1.0 - sgn * (a[2] as Vector3)[axis]
				var db := 1.0 - sgn * (b[2] as Vector3)[axis]
				if da >= 0.0:
					out.append(a)
				if (da >= 0.0) != (db >= 0.0):
					var k := da / (da - db)
					out.append([(a[0] as Vector3).lerp(b[0], k), (a[1] as Vector3).lerp(b[1], k),
						(a[2] as Vector3).lerp(b[2], k)])
			poly = out
	return poly


## One merged mesh for all `records` on the hull (and its `extra`); `tally` — marks for tally decals; `lift` —
## distance off the skin of the first decal (each later one a LIFT_STEP higher); `blockers` — moving parts over the
## skin; `to_local` — the axes the mesh is built in (a moving part's: `hull` is then that part, in model axes)
static func build(hull: PlaneHull, records: Array[DecalRecord], tally: int, lift := LIFT,
		blockers: Array[PlaneHull] = [], to_local := Transform3D.IDENTITY) -> ArrayMesh:
	var b := Builder.new()
	b.blockers = blockers
	b.to_local = to_local
	for i in records.size():
		b.lift = lift + LIFT_STEP * i
		for st in DecalLoadout.stamps(records[i], tally, hull):
			b.project(hull, st)
			if hull.extra != null:
				b.project(hull.extra, st)
	return b.mesh()
