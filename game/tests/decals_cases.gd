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
	_test_editor()
	_test_glass()
	_test_slab()
	_test_winding()
	_test_fade()
	_test_seat()
	_test_lift_order()
	_test_blockers()
	_test_parts()
	_test_fit()
	_test_editor_fit()
	_test_audit()
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


func _test_editor() -> void:
	var e := DecalEditor.new()
	var given: Array[DecalRecord] = [_sample()]
	e.open("fighter", 1, given)
	_check(e.records.size() == 1 and e.records[0] != given[0], "the editor works on copies of the plane's decals")
	_check(e.sel == -1 and e.tool == "" and not e.changed, "nothing is selected or changed on open")
	var hit := [Vector3(0.1, 0.0, -0.05), Vector3(0, 0, -1)]
	_check(e.preview(hit) == null and not e.place(hit), "without a picture nothing is previewed or placed")
	_check(e.pick("eye", false) == "locked" and e.tool == "", "a locked picture cannot be picked")
	_check(e.pick("hologram", true) == "unknown", "an unknown picture cannot be picked")
	_check(e.pick("bolt", true) == "", "an open picture becomes the tool")
	var pv := e.preview(hit)
	_check(pv != null and pv.id == "bolt" and pv.pos == hit[0] and pv.normal == hit[1], "the preview lies where the cursor hits")
	_check(e.preview([]) == null and not e.place([]), "a cursor off the plane places nothing")
	_check(e.place(hit) and e.records.size() == 2 and e.sel == 1 and e.changed, "a click places the decal and selects it")
	_check(e.tool == "bolt", "the tool stays for the next stamp")
	e.scale_by(100)
	_check(is_equal_approx(e.records[1].size, DecalRecord.SIZE_MAX), "scaling stops at the largest size")
	e.scale_by(-200)
	_check(is_equal_approx(e.records[1].size, DecalRecord.SIZE_MIN), "and at the smallest")
	e.rotate_by(1)
	_check(is_equal_approx(e.records[1].angle, DecalEditor.ROT_STEP), "a bumper turns by one step")
	e.rotate_by(-24)
	_check(absf(e.records[1].angle) <= PI + 1e-5, "the angle wraps")
	e.toggle_mirror()
	_check(e.records[1].mirror, "mirror flips the selected decal")
	e.set_paint(1, "teal")
	e.set_paint(2, "nope")
	_check(e.records[1].c1 == "teal" and e.records[1].c2 == DecalCatalog.DEFAULT_C2, "paints take only known ids")
	e.next_paint(1)
	_check(e.records[1].c1 != "teal" and DecalCatalog.PAINTS.has(e.records[1].c1), "next paint cycles through the palette")
	# select, move, drop
	e.cancel()
	_check(e.sel == -1 and e.tool == "", "cancel drops the tool and the selection")
	_check(not e.cancel(), "with nothing to drop cancel says so (B then leaves the editor)")
	_check(e.select_at(Vector3(0.1, 0.0, -0.051)) == 1, "a click on a decal selects the topmost one there")
	_check(e.select_at(Vector3(0.9, 0.9, 0.9)) == -1 and e.sel == -1, "a click beside the decals selects nothing")
	e.select_at(Vector3(0.1, 0.0, -0.05))
	_check(e.grab() and e.shown().size() == 1, "a grabbed decal is hidden from the plane while it moves")
	var to := [Vector3(-0.2, 0.05, -0.04), Vector3(0, 0, -1)]
	_check(e.preview(to) != null and e.preview(to).id == "bolt", "the moving decal follows the cursor")
	_check(not e.drop([]) and e.moving, "it cannot be dropped off the plane")
	_check(e.drop(to) and not e.moving and e.records[1].pos == to[0] and e.shown().size() == 2, "it lands where it is dropped")
	# number
	e.pick(DecalCatalog.NUMBER, true)
	e.set_text("4a2")
	e.place(hit)
	var num := e.records[e.sel]
	_check(num.text == "42", "the number takes the typed digits")
	e.toggle_mirror()
	_check(not num.mirror, "a number never mirrors")
	e.set_text("")
	_check(num.text == "42", "an empty number keeps its digits")
	# order and remove
	e.order(-5)
	_check(e.sel == 0 and e.records[0] == num, "a decal moves back in the draw order, to the bottom at most")
	e.order(1)
	_check(e.sel == 1 and e.records[1] == num, "and forward")
	e.remove()
	_check(e.records.size() == 2 and e.sel == -1 and not e.records.has(num), "remove deletes the selected decal")
	# other side and presets on a box
	var b := _box(Vector3.ZERO, Vector3(0.5, 0.2, 0.25))
	var h := PlaneHull.from_triangles(b[0], b[1])
	e.pick("bolt", true)
	_check(e.preset(h, "fighter_1", "nose", 1) and e.records[e.sel].normal.is_equal_approx(Vector3(0, 0, 1)), "a preset places the tool there")
	var n0 := e.records.size()
	_check(e.other_side(h) and e.records.size() == n0 + 1 and e.records[e.sel].normal.is_equal_approx(Vector3(0, 0, -1)),
		"«на другой борт» adds the mirror copy and selects it")
	# cap
	while e.records.size() < DecalLoadout.MAX_DECALS:
		e.place(hit)
	_check(e.pick("bolt", true) == "cap" and not e.place(hit), "a full plane takes no more decals")
	_check(not e.other_side(h), "nor a mirror copy")


func _test_glass() -> void:
	# skin: a plate at y 0 facing up; glass: a small plate 5 cm above its middle (a canopy over the cockpit)
	var b := _box(Vector3(0, -0.05, 0), Vector3(0.5, 0.05, 0.5))
	var skin := PlaneHull.from_triangles(b[0], b[1])
	var g := _box(Vector3(0, 0.05, 0), Vector3(0.05, 0.002, 0.05))
	var glass := PlaneHull.from_triangles(g[0], g[1])
	var through := skin.raycast_clear(Vector3(0, 1, 0), Vector3.DOWN, 2.0, glass)
	_check(through.is_empty(), "a ray through the glass finds no skin (nothing is placed under a canopy)")
	var beside := skin.raycast_clear(Vector3(0.3, 1, 0.3), Vector3.DOWN, 2.0, glass)
	_check(beside.size() == 2 and is_equal_approx((beside[0] as Vector3).y, 0.0), "beside the glass the skin is hit")
	var none := skin.raycast_clear(Vector3(0.3, 1, 0.3), Vector3.DOWN, 2.0, null)
	_check(none.size() == 2, "without glass it is a plain raycast")



# ---------- geometry rules from the decal audit (--decalaudit) ----------

## Two triangles of a flat skin facing −Z at depth `z`, `k` units across, with Godot's winding (the cross product of
## the edges points into the skin) unless `ccw`
func _plate(k: float, z := 0.0, ccw := false) -> Array:
	var a := [Vector3(-k, -k, z), Vector3(k, k, z), Vector3(k, -k, z), Vector3(-k, -k, z), Vector3(-k, k, z),
		Vector3(k, k, z)]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in 6:
		pos.append(a[i] if ccw else a[[0, 2, 1, 3, 5, 4][i]])
		nrm.append(Vector3(0, 0, -1))
	return [pos, nrm]


func _bolt(size: float, n := Vector3(0, 0, -1), at := Vector3.ZERO) -> DecalRecord:
	var r := DecalRecord.new()
	r.id = "bolt"
	r.size = size
	r.normal = n
	r.pos = at
	return r


## Godot front faces seen from the decal: every emitted triangle's edge cross product points away from the viewer
func _faces_decal(verts: PackedVector3Array, n: Vector3) -> bool:
	for t in range(0, verts.size(), 3):
		if (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).dot(n) >= -1e-12:
			return false
	return verts.size() > 0


func _project(hull: PlaneHull, r: DecalRecord) -> DecalMesh.Builder:
	var b := DecalMesh.Builder.new()
	for st in DecalLoadout.stamps(r, 0):
		b.project(hull, st)
	return b


func _test_slab() -> void:
	# one big skin triangle tilted 30° about X: its corners lie far outside a small decal's depth, its middle crosses it
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(30.0))
	var pl := _plate(0.4)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in 3:
		pos.append(tilt * (pl[0] as PackedVector3Array)[i])
		nrm.append(tilt * Vector3(0, 0, -1))
	var hull := PlaneHull.from_triangles(pos, nrm)
	var r := _bolt(0.01, tilt * Vector3(0, 0, -1), tilt * Vector3(0.1, -0.1, 0.0))
	var b := _project(hull, r)
	_check(b.verts.size() >= 3, "a big skin triangle crossing a small decal is cut, not dropped (battle hulls)")
	var inside := true
	for v in b.verts:
		inside = inside and absf((v - r.pos).dot(r.normal)) <= 0.0091
	_check(inside, "the piece stays inside the box depth")


func _test_winding() -> void:
	var godot := _plate(0.1)
	var ccw := _plate(0.1, 0.0, true)
	_check(PlaneHull.from_triangles(godot[0], godot[1]).winding() == -1, "Godot meshes wind inwards (winding −1)")
	_check(PlaneHull.from_triangles(ccw[0], ccw[1]).winding() == 1, "counter-clockwise meshes wind outwards (+1)")
	for pl: Array in [godot, ccw]:
		var b := _project(PlaneHull.from_triangles(pl[0], pl[1]), _bolt(0.04))
		_check(_faces_decal(b.verts, Vector3(0, 0, -1)), "pieces face the decal whatever the skin's winding")
	# a flipped triangle among Godot ones (the bodies are double-sided): it still gets its piece
	var pos: PackedVector3Array = (godot[0] as PackedVector3Array).duplicate()
	var t := pos[1]
	pos[1] = pos[2]
	pos[2] = t
	var bf := _project(PlaneHull.from_triangles(pos, godot[1]), _bolt(0.04))
	var full := _project(PlaneHull.from_triangles(godot[0], godot[1]), _bolt(0.04))
	_check(bf.verts.size() == full.verts.size() and _faces_decal(bf.verts, Vector3(0, 0, -1)),
		"a flipped skin triangle gets its piece, wound to face the decal")
	# a thin part: its near face and, 2 mm behind, its far face (outward +Z) whose normals were smoothed across the
	# edge (they point along the edge, a little towards the decal): the far face gets no piece
	var near := _plate(0.1)
	var side := _plate(0.1, -0.3)   # more skin elsewhere, as in a real model, so the winding vote is clear
	var far := _plate(0.1, 0.002)
	var tp := PackedVector3Array()
	var tn := PackedVector3Array()
	tp.append_array(near[0])
	tp.append_array(side[0])
	tn.append_array(near[1])
	tn.append_array(side[1])
	for i in [0, 2, 1, 3, 5, 4]:
		tp.append((far[0] as PackedVector3Array)[i])   # wound the Godot way for an outward +Z
		tn.append(Vector3(0.0, 0.95, -0.3).normalized())
	var bl := _project(PlaneHull.from_triangles(tp, tn), _bolt(0.04))
	var on_near := bl.verts.size() > 0
	for v in bl.verts:
		on_near = on_near and v.z < 0.0005
	_check(on_near, "the far face of a thin part gets nothing even when its smoothed normals lean over")


func _test_seat() -> void:
	# a fuselage 30 cm across (a cylinder about Y) and a full row of tally marks across its side: every mark lands on
	# the skin, though the row's far end lies ~4 cm off the flat plane of the record
	var rad := 0.15
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var seg := 48
	for i in seg:
		var a0 := deg_to_rad(-60.0 + 120.0 * i / seg)
		var a1 := deg_to_rad(-60.0 + 120.0 * (i + 1) / seg)
		var q: Array[Vector3] = []
		var o: Array[Vector3] = []
		for a: float in [a0, a1]:
			for y: float in [-0.03, 0.03]:
				q.append(Vector3(rad * sin(a), y, rad - rad * cos(a)))
				o.append(Vector3(sin(a), 0.0, -cos(a)))
		for tri: Array in [[0, 1, 3], [0, 3, 2]]:
			var t: Array = tri
			var c := (q[t[1]] - q[t[0]]).cross(q[t[2]] - q[t[0]])
			if c.dot(o[t[0]]) > 0.0:   # Godot winding: the cross product points inward
				t = [t[0], t[2], t[1]]
			for k: int in t:
				pos.append(q[k])
				nrm.append(o[k])
	var hull := PlaneHull.from_triangles(pos, nrm)
	var r := DecalRecord.new()
	r.id = "tally_air"
	r.size = 0.01
	r.normal = Vector3(0, 0, -1)
	var sts := DecalLoadout.stamps(r, DecalLoadout.TALLY_ROW, hull)
	var flat := DecalLoadout.stamps(r, DecalLoadout.TALLY_ROW)
	var drawn := 0
	for st in sts:
		var b := DecalMesh.Builder.new()
		b.project(hull, st)
		drawn += int(b.verts.size() > 0)
	var far_off := absf((flat[-1].center - sts[-1].center).length()) > 0.005
	_check(drawn == sts.size() and far_off, "every tally mark of a long row lands on a curved fuselage (%d of %d)" % [
		drawn, sts.size()])


func _test_fade() -> void:
	# a skin bent along x = 0: the left half faces the decal, the right half turns 70° away
	var n1 := Vector3(0, 0, -1)
	var n2 := Vector3(sin(deg_to_rad(70.0)), 0, -cos(deg_to_rad(70.0)))
	var e := Vector3(-n2.z, 0, n2.x)   # along the right half, away from the bend
	var lo := Vector3(0, -0.05, 0)
	var hi := Vector3(0, 0.05, 0)
	var pos := PackedVector3Array([Vector3(-0.05, -0.05, 0), hi, lo, Vector3(-0.05, -0.05, 0), Vector3(-0.05, 0.05, 0), hi,
		lo, e * 0.05 + hi, e * 0.05 + lo, lo, hi, e * 0.05 + hi])
	var nrm := PackedVector3Array()
	for i in 12:
		nrm.append(n1 if i < 6 else n2)
	var b := _project(PlaneHull.from_triangles(pos, nrm), _bolt(0.06))
	var flat := 1.0
	var steep := 0.0
	var n_steep := 0
	for i in b.verts.size():
		if b.normals[i].dot(n1) > 0.99:
			flat = minf(flat, b.colors[i].a)
		else:
			steep = maxf(steep, b.colors[i].a)
			n_steep += 1
	_check(b.verts.size() > 0 and is_equal_approx(flat, 1.0), "skin facing the decal shows it whole")
	_check(n_steep > 0 and steep < 0.5, "skin turned 70° away fades it out (no stretching round the edge)")


func _test_lift_order() -> void:
	var pl := _plate(0.1)
	var hull := PlaneHull.from_triangles(pl[0], pl[1])
	var two: Array[DecalRecord] = [_bolt(0.04), _bolt(0.04)]
	two[1].c1 = "white"
	var m := DecalMesh.build(hull, two, 0)
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var u2: PackedVector2Array = m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	var z0 := 0.0
	var z1 := 0.0
	for i in vs.size():
		if is_equal_approx(u2[i].x, float(DecalCatalog.paint_index("white"))):
			z1 = vs[i].z
		else:
			z0 = vs[i].z
	_check(z1 < z0 - DecalMesh.LIFT_STEP * 0.5, "a later decal lies over an earlier one (drawn in list order)")
	_check(DecalMesh.LIFT + DecalMesh.LIFT_STEP * (DecalLoadout.MAX_DECALS - 1) < 0.0008 - 0.0001,
		"even the last of 12 decals lies under the roundels (insignia 0.8 mm off the skin)")


func _test_blockers() -> void:
	var pl := _plate(0.1)
	var hull := PlaneHull.from_triangles(pl[0], pl[1])
	var flap := _plate(0.045, -0.004)   # a plate 4 mm over the lower half of the skin, like a battle flap plate
	var fp := PackedVector3Array()
	for v: Vector3 in flap[0]:
		fp.append(v + Vector3(0, -0.05, 0))
	var blk: Array[PlaneHull] = [PlaneHull.from_triangles(fp, flap[1])]
	var one: Array[DecalRecord] = [_bolt(0.06)]
	var plain := DecalMesh.build(hull, one, 0)
	var cut := DecalMesh.build(hull, one, 0, DecalMesh.LIFT, blk)
	_check(cut != null and cut.surface_get_array_len(0) < plain.surface_get_array_len(0),
		"no piece of the decal under a moving part lying over the skin")
	var moved := DecalMesh.build(hull, one, 0, DecalMesh.LIFT, [] as Array[PlaneHull],
		Transform3D(Basis(), Vector3(1, 0, 0)))
	var mv: PackedVector3Array = moved.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(mv[0].x > 0.9, "a moving part's piece is built in the part's own axes")


func _mesh(pl: Array) -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pl[0]
	arr[Mesh.ARRAY_NORMAL] = pl[1]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _test_parts() -> void:
	var model := Node3D.new()
	var mech := Node3D.new()
	mech.name = "wing_mech"
	model.add_child(mech)
	var flap := MeshInstance3D.new()
	flap.name = "flap_l"
	flap.mesh = _mesh(_plate(0.02))
	flap.position = Vector3(-0.3, 0.0, 0.0)
	flap.set_meta("rest", flap.transform)
	mech.add_child(flap)
	flap.rotation = Vector3(0, 0, -0.4)   # posed down: the decal is still measured at rest
	var parts := PlaneHull.parts_of(model)
	_check(parts.size() == 1 and parts[0]["node"] == flap, "a flap is a moving part a decal can lie on")
	if parts.size() == 1:
		var h: PlaneHull = parts[0]["hull"]
		_check(absf(h.bounds().get_center().x + 0.3) < 1e-4 and absf(h.bounds().get_center().y) < 1e-4,
			"its skin is in model axes at rest, whatever its pose")
		var one: Array[DecalRecord] = [_bolt(0.02, Vector3(0, 0, -1), Vector3(-0.3, 0, 0))]
		var m := DecalMesh.build(h, one, 0, DecalMesh.LIFT, [] as Array[PlaneHull], parts[0]["to_local"])
		var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if m != null else PackedVector3Array()
		_check(vs.size() > 0 and absf(vs[0].x) < 0.03, "its decal piece is in the flap's own axes (hangs under it)")
	model.free()


func _test_fit() -> void:
	var b := _box(Vector3.ZERO, Vector3(0.05, 0.05, 0.02))   # a 10 cm square slab: its faces at z = ±0.02
	var hull := PlaneHull.from_triangles(b[0], b[1])
	var r := _bolt(0.04, Vector3(0, 0, 1), Vector3(0, 0, 0.02))
	_check(is_equal_approx(DecalPresets.fit(hull, r, 0), 1.0), "a small decal in the middle of a face fits")
	r.size = DecalRecord.SIZE_MAX
	_check(DecalPresets.fit(hull, r, 0) < DecalPresets.FIT_SHARE, "a decal larger than the face does not")
	var s := DecalPresets.fit_size(hull, r, 0)
	r.size = s
	_check(s < DecalRecord.SIZE_MAX and DecalPresets.fit(hull, r, 0) >= DecalPresets.FIT_SHARE,
		"fit_size gives the largest size that fits there")
	var edge := _bolt(0.06, Vector3(0, 0, 1), Vector3(0.045, 0, 0.02))
	_check(DecalPresets.fit(hull, edge, 0) < DecalPresets.FIT_SHARE, "half off the edge does not fit")


func _test_editor_fit() -> void:
	var b := _box(Vector3.ZERO, Vector3(0.05, 0.05, 0.02))
	var e := DecalEditor.new()
	var none: Array[DecalRecord] = []
	e.open("fighter", 1, none)
	e.hull = PlaneHull.from_triangles(b[0], b[1])
	e.pick("bolt", true)
	e.size = DecalRecord.SIZE_MAX
	var hit := [Vector3(0, 0, 0.02), Vector3(0, 0, 1)]
	_check(e.place(hit) and e.records[0].size < DecalRecord.SIZE_MAX and e.note == "shrunk",
		"a decal too big for the spot is placed smaller, and the editor says why")
	var fitted := e.records[0].size
	e.scale_by(3)
	_check(e.records[0].size <= fitted + 1e-6 and e.note == "max", "it does not grow past what fits")
	e.scale_by(-2)
	_check(e.records[0].size < fitted and e.note == "", "it still shrinks")


## Triangles of `pl` as audit triangles tagged `tag` (normals −Z)
func _audit_tris(into: DecalAudit.Tris, pos: PackedVector3Array, tag: int) -> void:
	for t in range(0, pos.size(), 3):
		for k in 3:
			into.pos.append(pos[t + k])
			into.nrm.append(Vector3(0, 0, -1))
			into.fade.append(1.0)
		into.gn.append(Vector3(0, 0, -1))
		into.tag.append(tag)
		into.owner.append(0)
		into.paint.append(0.0)
	if into.names.is_empty():
		into.names.append("mesh")
	into.done()


func _test_audit() -> void:
	# the audit's own rules on a plate: a decal on it is fine; a second plate in front hides it
	var pl := _plate(0.1)
	var scene := DecalAudit.Tris.new()
	_audit_tris(scene, pl[0], DecalAudit.Tag.SKIN)
	var r := _bolt(0.04)
	var one: Array[DecalRecord] = [r]
	var m := DecalMesh.build(PlaneHull.from_triangles(pl[0], pl[1]), one, 0)
	var dec := DecalAudit.Tris.new()
	_audit_tris(dec, m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], DecalAudit.Tag.SKIN)
	var res := DecalAudit.audit(scene, null, dec, r, 0)
	_check(int(res["opaque"]) > 0 and DecalAudit.problems(res).is_empty(), "a decal on a flat plate has no problems")
	_audit_tris(scene, _plate(0.1, -0.01)[0], DecalAudit.Tag.ADDON)
	var hid := DecalAudit.audit(scene, null, dec, r, 0)
	_check(float(hid.get("hidden_addon", 0.0)) > 0.9, "a plate 1 cm in front of the decal hides it")
	var empty := DecalAudit.Tris.new()
	empty.done()
	var gap := DecalAudit.audit(scene, null, empty, r, 0)
	_check(float(gap.get("hidden_addon", 0.0)) > 0.9, "and with no decal at all the plate is what shows")
	var st := DecalAudit.area_stats(dec, Vector3(0, 0, -1))
	_check(is_zero_approx(float(st.get("stretch", 0.0))) and is_zero_approx(float(st.get("back_leak", 0.0))),
		"a flat decal is not stretched and faces its viewer")
