extends RefCounted
## Free-placed plane decals (Kanta 27.10, spec 2026-10-27-plane-decals-design.md): one decal record is validated and
## survives a save round trip, a plane holds at most `DecalLoadout.MAX_DECALS`, old and unknown save formats migrate
## or are kept untouched, numbers and tallies expand into atlas stamps, and the projector cuts a hull into a decal
## that stays inside its box. The profile part uses a fresh instance writing to a test file.
## Loaded by `decals_test.gd` after the first frame (Profile needs the autoloads).

const TEST_PATH := "user://test_profile_decals.json"

var _failed := 0
var _checks := 0
var _profile_script: GDScript = load("res://scripts/profile.gd")


## Run every check; returns [checks, failed]
func run() -> Array:
	_test_record()
	_test_validation()
	_test_cap()
	_test_migration()
	_test_stamps()
	_test_projection()
	_test_profile_round_trip()
	_test_old_profile()
	_test_hull()
	_test_extra_hull()
	_test_mirror()
	_test_presets()
	_test_tally()
	_test_unlocks()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	return [_checks, _failed]


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _sample() -> DecalRecord:
	var r := DecalRecord.new()
	r.id = "skull_winged"
	r.pos = Vector3(0.3, -0.03, -0.04)
	r.normal = Vector3(0.0, 0.0, -1.0)
	r.angle = 0.5
	r.size = 0.04
	r.mirror = true
	r.c1 = "sand"
	r.c2 = "teal"
	return r


func _test_record() -> void:
	var r := _sample()
	var q := DecalRecord.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	_check(q != null, "a record read back from JSON is valid")
	if q == null:
		return
	_check(q.id == r.id and q.mirror and q.c1 == "sand" and q.c2 == "teal", "id, mirror and paints survive JSON")
	_check(q.pos.is_equal_approx(r.pos) and q.normal.is_equal_approx(r.normal), "position and normal survive JSON")
	_check(is_equal_approx(q.angle, 0.5) and is_equal_approx(q.size, 0.04), "angle and size survive JSON")
	var b := r.basis_vectors()
	_check(absf(b[0].dot(r.normal)) < 1e-4 and absf(b[1].dot(r.normal)) < 1e-4, "right and up lie in the surface")
	var w := DecalRecord.new()
	w.normal = Vector3.UP
	var bw := w.basis_vectors()
	_check(bw[1].is_equal_approx(Vector3(1, 0, 0)), "on a wing (normal up) the decal's top points to the nose")


func _test_validation() -> void:
	_check(DecalRecord.from_dict({"id": "star", "p": [0, 0, 0], "n": [0, 0, 1], "s": 0.04}) == null,
		"an unknown image is dropped")
	_check(DecalRecord.from_dict({"id": "bolt", "p": [0, 0, 0], "n": [0, 0, 0], "s": 0.04}) == null,
		"a zero normal is dropped")
	_check(DecalRecord.from_dict({"id": "bolt", "p": "x", "n": [0, 0, 1], "s": 0.04}) == null, "a broken position is dropped")
	_check(DecalRecord.from_dict({"id": "bolt", "p": [9, 0, 0], "n": [0, 0, 1], "s": 0.04}) == null,
		"a position far off the plane is dropped")
	var big := DecalRecord.from_dict({"id": "bolt", "p": [0, 0, 0], "n": [0, 0, 3], "s": 5.0, "c1": "pink"})
	_check(big != null and is_equal_approx(big.size, DecalRecord.SIZE_MAX), "size is clamped")
	_check(big != null and big.normal.is_equal_approx(Vector3(0, 0, 1)), "the normal is normalised")
	_check(big != null and big.c1 == DecalCatalog.DEFAULT_C1, "an unknown paint falls back to the default")
	var num := DecalRecord.from_dict({"id": "number", "p": [0, 0, 0], "n": [0, 0, 1], "s": 0.03, "t": "0a7"})
	_check(num != null and num.text == "07", "a number keeps only digits")
	var long := DecalRecord.from_dict({"id": "number", "p": [0, 0, 0], "n": [0, 0, 1], "s": 0.03, "t": "12345"})
	_check(long != null and long.text == "123", "a number keeps at most 3 digits")
	_check(DecalRecord.from_dict({"id": "number", "p": [0, 0, 0], "n": [0, 0, 1], "s": 0.03, "t": "x"}) == null,
		"a number without digits is dropped")
	_check(DecalRecord.from_dict("garbage") == null and DecalRecord.from_dict(null) == null, "non-dictionaries are dropped")


func _test_cap() -> void:
	var list: Array[DecalRecord] = []
	for i in DecalLoadout.MAX_DECALS:
		_check(DecalLoadout.add(list, _sample()), "decal %d fits" % (i + 1))
	_check(not DecalLoadout.add(list, _sample()), "decal %d is refused" % (DecalLoadout.MAX_DECALS + 1))
	_check(list.size() == DecalLoadout.MAX_DECALS, "the list stays at the cap")
	var items: Array = []
	for i in 15:
		items.append(_sample().to_dict())
	var parsed := DecalLoadout.parse({"v": DecalLoadout.VERSION, "items": items})
	_check(parsed.records.size() == DecalLoadout.MAX_DECALS, "a save with 15 decals loads the first 12")


func _test_migration() -> void:
	var none := DecalLoadout.parse(null)
	_check(none.records.is_empty() and not none.future, "a profile from before decals: no decals")
	var bare := DecalLoadout.parse([_sample().to_dict(), {"id": "nope"}])
	_check(bare.records.size() == 1, "an unversioned list (format 0) migrates, broken entries dropped")
	var saved: Dictionary = DecalLoadout.to_save(bare)
	_check(int(saved["v"]) == DecalLoadout.VERSION and (saved["items"] as Array).size() == 1, "saved in the current format")
	var fut := {"v": DecalLoadout.VERSION + 1, "items": [{"id": "hologram"}], "extra": true}
	var pf := DecalLoadout.parse(fut)
	_check(pf.future and pf.records.is_empty(), "a newer format is not drawn")
	_check(DecalLoadout.to_save(pf) == fut, "a newer format is written back untouched (no data loss on downgrade)")
	_check(DecalLoadout.parse({"v": DecalLoadout.VERSION, "items": "x"}).records.is_empty(), "broken items: no decals")


func _test_stamps() -> void:
	var n := DecalRecord.new()
	n.id = "number"
	n.text = "07"
	n.size = 0.03
	n.normal = Vector3(0, 0, -1)
	var st := DecalLoadout.stamps(n, 0)
	_check(st.size() == 2, "«07» gives two digit stamps")
	if st.size() == 2:
		_check(st[0].uv.is_equal_approx(DecalCatalog.digit_rect(0)) and st[1].uv.is_equal_approx(DecalCatalog.digit_rect(7)),
			"digit stamps use the cells of 0 and 7 in reading order")
		var b := n.basis_vectors()
		_check((st[1].center - st[0].center).dot(b[0]) > 0.0, "the second digit sits to the right of the first")
	var t := DecalRecord.new()
	t.id = "tally_air"
	t.size = 0.01
	t.normal = Vector3(0, 0, -1)
	_check(DecalLoadout.stamps(t, 0).is_empty(), "no kills, no marks")
	_check(DecalLoadout.stamps(t, 5).size() == 5, "five kills, five marks")
	_check(DecalLoadout.stamps(t, 99).size() == DecalCatalog.TALLY_MAX, "marks are capped")
	var s := _sample()
	s.id = "shark_mouth"
	var ss := DecalLoadout.stamps(s, 0)
	_check(ss.size() == 1 and is_equal_approx(ss[0].half_w, s.size), "a two-cell picture is twice as wide as tall")
	_check(ss.size() == 1 and ss[0].mirror, "mirror reaches the stamp")


func _test_projection() -> void:
	# a flat 0.2 × 0.2 skin facing -Z, two triangles; a 0.04 decal in the middle
	var pos := PackedVector3Array([Vector3(-0.1, -0.1, 0), Vector3(0.1, 0.1, 0), Vector3(0.1, -0.1, 0),
		Vector3(-0.1, -0.1, 0), Vector3(-0.1, 0.1, 0), Vector3(0.1, 0.1, 0)])
	var nrm := PackedVector3Array()
	for i in 6:
		nrm.append(Vector3(0, 0, -1))
	var r := DecalRecord.new()
	r.id = "bolt"
	r.size = 0.04
	r.normal = Vector3(0, 0, -1)
	var out := DecalMesh.Builder.new()
	var hull := PlaneHull.from_triangles(pos, nrm)
	for st: DecalStamp in DecalLoadout.stamps(r, 0):
		out.project(hull, st)
	_check(out.verts.size() >= 3 and out.verts.size() % 3 == 0, "the decal cuts whole triangles from the skin")
	var inside := true
	var uv_ok := true
	var rect := DecalCatalog.image_rect("bolt")
	for i in out.verts.size():
		var v := out.verts[i]
		inside = inside and absf(v.x) <= 0.0201 and absf(v.y) <= 0.0201 and v.z < 0.0
		uv_ok = uv_ok and rect.grow(1e-4).has_point(out.uvs[i])
	_check(inside, "every vertex stays in the decal's box, lifted off the skin towards the viewer")
	_check(uv_ok, "every UV stays in the image's atlas cell")
	var back := DecalMesh.Builder.new()
	var rb := DecalRecord.new()
	rb.id = "bolt"
	rb.size = 0.04
	rb.normal = Vector3(0, 0, 1)   # the decal faces the other way: the skin is its back side
	for st: DecalStamp in DecalLoadout.stamps(rb, 0):
		back.project(hull, st)
	_check(back.verts.is_empty(), "skin facing away from the decal (the far side of a fin) gets nothing")


func _fresh_profile() -> Node:
	var p: Node = _profile_script.new()
	p.path = TEST_PATH
	p.reset_data()
	return p


func _test_profile_round_trip() -> void:
	var p := _fresh_profile()
	var list: Array[DecalRecord] = [_sample()]
	p.set_decals("fighter", 1, list)
	p.save()
	var q := _fresh_profile()
	q.load_profile()
	var got: Array[DecalRecord] = q.decals("fighter", 1)
	_check(got.size() == 1 and got[0].id == "skull_winged" and got[0].mirror, "decals survive save and load")
	_check(q.decals("fighter", 2).is_empty(), "plane 2 keeps its own (empty) decals")
	q.free()
	p.free()


func _test_old_profile() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "parts": 5, "classes": {"bomber": {"crew_xp": 10, "livery": "khaki"},
		"attacker": {"decals1": {"v": 1, "items": [{"id": "bolt", "p": "broken"}, _sample().to_dict()]}}}}))
	f.close()
	var q := _fresh_profile()
	q.load_profile()
	_check(q.decals("bomber", 1).is_empty() and int(q.data["parts"]) == 5, "an old profile loads, no decals")
	_check(q.decals("attacker", 1).size() == 1, "broken decal entries are dropped on load, valid ones kept")
	q.free()


## Triangles of an axis-aligned box centred at `c` with half sizes `h`, normals outward
func _box(c: Vector3, h: Vector3) -> Array:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var f := c + n * h[axis]
			for p: Vector3 in [f - u - v, f + u - v, f + u + v, f - u - v, f + u + v, f - u + v]:
				pos.append(p)
				nrm.append(n)
	return [pos, nrm]


func _test_hull() -> void:
	# a wide floor at y 0 and a small deck at y 0.1 above its middle, both facing up
	var b1 := _box(Vector3(0, -0.05, 0), Vector3(0.5, 0.05, 0.5))
	var b2 := _box(Vector3(0, 0.05, 0), Vector3(0.05, 0.05, 0.05))
	var pos: PackedVector3Array = (b1[0] as PackedVector3Array) + (b2[0] as PackedVector3Array)
	var nrm: PackedVector3Array = (b1[1] as PackedVector3Array) + (b2[1] as PackedVector3Array)
	var h := PlaneHull.from_triangles(pos, nrm)
	_check(h.triangles() == 24, "the hull keeps every triangle")
	var top := h.top_hit(h.in_rect_xz(Rect2(-0.01, -0.01, 0.02, 0.02)), 0.0, 0.0)
	_check(not top.is_empty() and is_equal_approx(float(top["y"]), 0.1), "top_hit finds the highest skin (the deck)")
	var side := h.top_hit(h.in_rect_xz(Rect2(0.29, 0.29, 0.02, 0.02)), 0.3, 0.3)
	_check(not side.is_empty() and is_equal_approx(float(side["y"]), 0.0), "beside the deck top_hit finds the floor")
	_check(h.in_rect_xz(Rect2(2.0, 2.0, 0.1, 0.1)).is_empty(), "no triangles far off the hull")
	var hit := h.raycast(Vector3(0.0, 1.0, 0.0), Vector3.DOWN)
	_check(hit.size() == 2 and is_equal_approx((hit[0] as Vector3).y, 0.1), "a ray from above hits the deck first")
	_check(hit.size() == 2 and (hit[1] as Vector3).is_equal_approx(Vector3.UP), "the hit carries the skin normal")
	_check(h.raycast(Vector3(0.3, -1.0, 0.3), Vector3.UP).size() == 2, "a ray from below hits the floor's bottom face")
	var inside := h.raycast(Vector3(0.3, -0.05, 0.3), Vector3(0, 0, 1))
	_check(inside.size() == 0, "from inside the hull every face looks away: no hit")


func _test_extra_hull() -> void:
	# a skin at z 0 facing −Z and a small fairing plate 1 cm in front of it (like a turret fairing on a wing)
	var pos := PackedVector3Array([Vector3(-0.1, -0.1, 0), Vector3(0.1, 0.1, 0), Vector3(0.1, -0.1, 0),
		Vector3(-0.1, -0.1, 0), Vector3(-0.1, 0.1, 0), Vector3(0.1, 0.1, 0)])
	var nrm := PackedVector3Array()
	for i in 6:
		nrm.append(Vector3(0, 0, -1))
	var fpos := PackedVector3Array()
	for p in pos:
		fpos.append(Vector3(p.x * 0.05, p.y * 0.05, -0.01))
	var base := PlaneHull.from_triangles(pos, nrm)
	var r := DecalRecord.new()
	r.id = "bolt"
	r.size = 0.04
	r.normal = Vector3(0, 0, -1)
	var list: Array[DecalRecord] = [r]
	var plain := DecalMesh.build(base, list, 0)
	var with := PlaneHull.from_triangles(pos, nrm)
	with.extra = PlaneHull.from_triangles(fpos, nrm)
	var both := DecalMesh.build(with, list, 0)
	_check(plain != null and both != null and both.surface_get_array_len(0) > plain.surface_get_array_len(0),
		"the decal also covers the fairing")
	var front := false
	if both != null:
		for v: Vector3 in both.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			front = front or v.z < -0.0095
	_check(front, "the fairing's piece lies on the fairing, in front of the skin")
	var hit := with.raycast(Vector3(0, 0, -1), Vector3(0, 0, 1))
	_check(hit.size() == 2 and is_equal_approx((hit[0] as Vector3).z, -0.01), "the cursor ray stops on the fairing")
	var miss := with.raycast(Vector3(0.05, 0.05, -1), Vector3(0, 0, 1))
	_check(miss.size() == 2 and is_equal_approx((miss[0] as Vector3).z, 0.0), "beside the fairing the ray reaches the skin")


func _reflect(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, -v.z)


func _test_mirror() -> void:
	var r := _sample()
	r.pos = Vector3(0.3, -0.03, -0.05)
	r.normal = Vector3(0.1, -0.2, -1.0).normalized()
	r.angle = 0.6
	var m := DecalPresets.mirrored(r, null)
	_check(m != null and m.pos.is_equal_approx(Vector3(0.3, -0.03, 0.05)), "the copy sits on the other side")
	if m == null:
		return
	_check(m.normal.is_equal_approx(_reflect(r.normal)), "the copy's normal is reflected")
	var b := r.basis_vectors()
	var bm := m.basis_vectors()
	_check(bm[1].is_equal_approx(_reflect(b[1])), "the copy's top points the same way (reflected)")
	_check(bm[0].is_equal_approx(-_reflect(b[0])) and m.mirror != r.mirror, "the copy is a mirror image")
	_check(m.id == r.id and m.size == r.size and m.c1 == r.c1 and m.c2 == r.c2, "picture, size and paints are kept")
	_check(DecalPresets.mirrored(m, null).pos.is_equal_approx(r.pos), "mirroring twice gives the original")


func _test_presets() -> void:
	for key: String in DecalPresets.SPOTS:
		var spots: Dictionary = DecalPresets.SPOTS[key]
		var ok := true
		for spot: String in DecalPresets.NAMES:
			ok = ok and spots.has(spot) and float(spots[spot][2]) >= DecalRecord.SIZE_MIN \
				and float(spots[spot][2]) <= DecalRecord.SIZE_MAX
		_check(ok, "%s has every preset with a valid size" % key)
	var b := _box(Vector3.ZERO, Vector3(0.5, 0.2, 0.25))
	var h := PlaneHull.from_triangles(b[0], b[1])
	var right := DecalPresets.record(h, "fighter_1", "nose", 1, "shark_mouth")
	_check(right != null and right.normal.is_equal_approx(Vector3(0, 0, 1)) and is_equal_approx(right.pos.z, 0.25),
		"the nose preset lands on the right side's skin")
	_check(right != null and right.mirror, "a side picture is mirrored on the right side, so it faces the nose")
	var left := DecalPresets.record(h, "fighter_1", "nose", -1, "shark_mouth")
	_check(left != null and not left.mirror and left.normal.is_equal_approx(Vector3(0, 0, -1)), "and not on the left")
	var wing := DecalPresets.record(h, "fighter_1", "wing", 1, "bolt")
	_check(wing != null and wing.normal.is_equal_approx(Vector3.UP) and wing.pos.z > 0.0, "the wing preset lies on top, right wing")
	var num := DecalPresets.record(h, "fighter_1", "number", 1, "number")
	_check(num != null and num.text != "" and not num.mirror, "a number preset gets digits and is never mirrored")
	_check(DecalPresets.record(h, "nope_9", "nose", 1, "bolt") == null, "an unknown plane has no presets")
	var empty := PlaneHull.from_triangles(PackedVector3Array(), PackedVector3Array())
	_check(DecalPresets.record(empty, "fighter_1", "nose", 1, "bolt") == null, "a missed ray gives no record")


func _test_tally() -> void:
	var c := {"tally_fighter": 3, "aces": 50, "fortresses": 9}
	_check(DecalLoadout.tally_of(c, "fighter") == 3, "the tally counts this class's aces and «Крепости»")
	_check(DecalLoadout.tally_of(c, "bomber") == 0, "another class starts its own tally")
	_check(DecalLoadout.tally_of({}, "fighter") == 0, "no counters, no marks")


func _test_unlocks() -> void:
	var none := {}
	for id: String in DecalUnlocks.START:
		_check(DecalUnlocks.is_open(id, "fighter", none, 1), "%s is open from the start" % id)
	_check(DecalUnlocks.is_open("wasp", "fighter", none, 1) and not DecalUnlocks.is_open("whale", "fighter", none, 1),
		"a class's own mascot is open, the others are not")
	_check(DecalUnlocks.is_open("whale", "fighter", {"sorties_bomber": 1}, 1), "a mascot opens after a sortie on its class")
	_check(not DecalUnlocks.is_open("eye", "fighter", none, 4) and DecalUnlocks.is_open("eye", "fighter", none, 5),
		"crew rank milestones open at the rank")
	_check(DecalUnlocks.is_open("skull_winged", "bomber", none, Insignia.ACE_RANK), "the winged skull opens at the ace rank")
	_check(not DecalUnlocks.is_open("ace_card", "fighter", none, 1) and DecalUnlocks.is_open("ace_card", "fighter", {"aces": 1}, 1),
		"the ace card opens with the first rival ace")
	_check(DecalUnlocks.is_open("skull_wrench", "fighter", {"op_forts": 1}, 1), "an operation cleared opens its picture")
	_check(not DecalUnlocks.is_open("skull_wrench", "fighter", {"op_forts": 0, "sorties": 9}, 1), "but not before")
	_check(not DecalUnlocks.is_open("hologram", "fighter", {"aces": 99}, 20), "an unknown picture is never open")
	var all := true
	for id: String in DecalCatalog.IMAGES:
		all = all and (id in DecalUnlocks.START or (DecalUnlocks.MASCOTS.values() as Array).has(id) or DecalUnlocks.RULES.has(id))
	_check(all, "every picture has an unlock rule")
