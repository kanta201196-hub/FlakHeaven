extends SceneTree
## Unit tests for MountCheck (R-23 build self-check): closest point on a triangle, the near-face filter, the
## gap of a point and of a sample to a surface, rings and mesh samples. No framework: each check prints FAIL with
## a message; the process exits with code 1 if any check failed. Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_closest()
	_test_gaps()
	_test_near_faces()
	_test_ring()
	_test_mesh_points()
	_test_grid()
	_test_faces_of()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## A 2 × 2 floor at y = 0 centred on the origin, two triangles
func _floor() -> PackedVector3Array:
	return PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1),
		Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)])


func _test_closest() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0, 0)
	var c := Vector3(0, 0, 1)
	_check(MountCheck.closest_on_triangle(Vector3(0.2, 1, 0.2), a, b, c).is_equal_approx(Vector3(0.2, 0, 0.2)), "inside: straight down")
	_check(MountCheck.closest_on_triangle(Vector3(-1, 0, -1), a, b, c).is_equal_approx(a), "vertex region a")
	_check(MountCheck.closest_on_triangle(Vector3(2, 0, -0.5), a, b, c).is_equal_approx(b), "vertex region b")
	_check(MountCheck.closest_on_triangle(Vector3(0.5, 0, -1), a, b, c).is_equal_approx(Vector3(0.5, 0, 0)), "edge ab")
	_check(MountCheck.closest_on_triangle(Vector3(1, 0, 1), a, b, c).is_equal_approx(Vector3(0.5, 0, 0.5)), "edge bc")


func _test_gaps() -> void:
	var f := _floor()
	_check(is_equal_approx(MountCheck.point_gap(f, Vector3(0.3, 0.25, 0.1), 1.0), 0.25), "point 0.25 above the floor")
	_check(is_equal_approx(MountCheck.point_gap(f, Vector3(0.3, -0.1, 0.1), 1.0), 0.1), "point below counts too")
	_check(is_inf(MountCheck.point_gap(f, Vector3(0, 5, 0), 1.0)), "out of reach is INF")
	_check(is_inf(MountCheck.point_gap(PackedVector3Array(), Vector3.ZERO, 1.0)), "no faces is INF")
	var pts := PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0.2, 0.05, 0), Vector3(0.4, 0.3, 0)])
	_check(is_equal_approx(MountCheck.points_gap(f, pts, 1.0), 0.05), "sample gap is its lowest point")
	pts.append(Vector3(0.1, -0.02, 0.1))
	_check(MountCheck.points_gap(f, pts, 1.0) < 0.021, "a point through the floor gives a small gap")
	var two := PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0.5, 0.3, 0)])
	_check(is_equal_approx(MountCheck.mean_gap(f, two, 1.0), 0.2), "mean gap of two points")
	_check(is_inf(MountCheck.mean_gap(f, PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0, 9, 0)]), 1.0)), "mean gap INF if one is out of reach")


func _test_near_faces() -> void:
	var f := _floor()
	f.append_array(PackedVector3Array([Vector3(10, 0, 10), Vector3(11, 0, 10), Vector3(10, 0, 11)]))
	var near := MountCheck.near_faces(f, AABB(Vector3(0, 0.1, 0), Vector3.ZERO), 0.2)
	_check(near.size() == 6, "far triangle filtered out (got %d points)" % near.size())
	_check(MountCheck.near_faces(f, AABB(Vector3(0, 3, 0), Vector3.ZERO), 0.2).is_empty(), "nothing near a point high above")


func _test_ring() -> void:
	var r := MountCheck.ring(Vector3(1, 2, 3), Vector3(-1, 0, 0), 0.5, 6)
	_check(r.size() == 6, "six ring points")
	var ok := true
	for p in r:
		var d := p - Vector3(1, 2, 3)
		ok = ok and is_equal_approx(d.length(), 0.5) and absf(d.x) < 1e-5
	_check(ok, "ring points at radius 0.5 in the plane normal to the axis")
	var up := MountCheck.ring(Vector3.ZERO, Vector3.UP, 1.0, 4)
	_check(absf(up[0].y) < 1e-5 and is_equal_approx(up[0].length(), 1.0), "ring round the vertical axis")


func _test_mesh_points() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var pts := MountCheck.mesh_points(bm, Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), 1000)
	_check(not pts.is_empty(), "box gives points")
	var lo := INF
	for p in pts:
		lo = minf(lo, p.y)
	_check(is_equal_approx(lo, 1.5), "box moved up 2: its bottom at 1.5")
	_check(MountCheck.mesh_points(bm, Transform3D.IDENTITY, 4).size() <= 4, "sample is capped at max_n")
	_check(MountCheck.mesh_points(null, Transform3D.IDENTITY).is_empty(), "no mesh, no points")
	# a box sitting on the floor touches it; lifted by 0.3 it floats 0.3
	var f := _floor()
	_check(MountCheck.points_gap(f, MountCheck.mesh_points(bm, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))), 1.0) < 1e-4,
		"box on the floor touches it")
	_check(is_equal_approx(MountCheck.points_gap(f, MountCheck.mesh_points(bm, Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0))), 1.0), 0.3),
		"box lifted 0.3 floats 0.3")


## The grid finds the same gaps as the plain search, and nothing beyond its cell
func _test_grid() -> void:
	var f := _floor()
	var g := MountCheck.build_grid(f, 0.5)
	_check(is_equal_approx(MountCheck.grid_gap(g, PackedVector3Array([Vector3(0.3, 0.25, 0.1)])), 0.25), "grid: 0.25 above")
	var two := PackedVector3Array([Vector3(0.9, 0.4, -0.9), Vector3(-0.7, 0.1, 0.7)])
	_check(is_equal_approx(MountCheck.grid_gap(g, two), 0.1), "grid: best of two points")
	_check(is_inf(MountCheck.grid_gap(g, PackedVector3Array([Vector3(0, 2, 0)]))), "grid: farther than a cell is INF")
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.4, 0.4)
	var box := MountCheck.mesh_points(bm, Transform3D(Basis.IDENTITY, Vector3(0.5, 0.3, 0.5)))
	_check(is_equal_approx(MountCheck.grid_gap(g, box), 0.1), "grid: box 0.1 over the floor")
	_check(MountCheck.grid_gap(g, two, 0.5) <= 0.5, "grid: stops at the first gap under `enough`")


func _test_faces_of() -> void:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	body.mesh = pm
	body.position = Vector3(0, 1, 0)
	root.add_child(body)
	var skipped := MeshInstance3D.new()
	skipped.name = "nozzle_flame"
	skipped.mesh = BoxMesh.new()
	body.add_child(skipped)
	root.position = Vector3(5, 5, 5)   # the root's own place does not count: faces are in its axes
	var faces := MountCheck.faces_of(root, root, PackedStringArray(["nozzle_flame"]))
	_check(faces.size() == pm.get_faces().size(), "only the plane mesh, flame skipped (got %d)" % faces.size())
	_check(faces.size() > 0 and is_equal_approx(faces[0].y, 1.0), "faces moved into the root's axes")
	var low := MountCheck.faces_of(body, root)
	_check(low.size() > 0 and is_equal_approx(low[0].y, 1.0), "a child's faces in its ancestor's axes")
	_check(MountCheck.rel_xf(skipped, root).origin.is_equal_approx(Vector3(0, 1, 0)), "rel_xf chains local transforms")
	# a weapon with its pylon child: the pylon's points count, a hidden child's do not
	var w := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(0.2, 0.2, 0.2)
	w.mesh = wb
	w.position = Vector3(0, 0.5, 0)
	var pylon := MeshInstance3D.new()
	pylon.mesh = wb
	pylon.position = Vector3(0, 0.2, 0)
	w.add_child(pylon)
	var hidden := MeshInstance3D.new()
	hidden.mesh = wb
	hidden.position = Vector3(0, -3, 0)
	hidden.visible = false
	w.add_child(hidden)
	root.add_child(w)
	var pts := MountCheck.node_points(w, root)
	var top := -INF
	var bottom := INF
	for p in pts:
		top = maxf(top, p.y)
		bottom = minf(bottom, p.y)
	_check(is_equal_approx(top, 0.8), "pylon top counts (got %f)" % top)
	_check(is_equal_approx(bottom, 0.4), "hidden child left out (got %f)" % bottom)
	root.free()
