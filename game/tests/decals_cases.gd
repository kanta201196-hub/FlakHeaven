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
	var hull := DecalMesh.Hull.from_triangles(pos, nrm)
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
