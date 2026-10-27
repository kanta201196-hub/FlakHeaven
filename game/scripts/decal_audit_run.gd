class_name DecalAuditRun
extends RefCounted
## Bench driver of the decal geometry audit (`--visual --hangarbench --decalaudit`, headless; VisualBench feeds it the
## hangar model of every class, plane level and weapon tier, then builds the battle models itself): generates the
## decals to try on one model — every preset spot on both sides with its mirrored copy, sizes from min to max and
## several turns per spot, free placements shot at curved and awkward places (nose cone, fuselage rings, wing roots,
## tips and leading edges, the fin, the belly, flaps and slats and their seams, bay doors, fairings, silhouette
## details, the wing roundels), every picture kind — audits each with DecalAudit and keeps the counts.
## Prints `DAUDIT` lines (one per decal with a problem, a summary at the end) and writes user://decal_audit.json.

const PICS := ["shark_mouth", "number:123", "tally_air", "skull_winged", "bolt", "cat", "number:7", "tally_bomb",
	"eye", "chevrons", "number:45", "wasp"]
const SIZES := [0.02, 0.035, 0.05, 0.03, 0.08, 0.012, 0.045]
const ANGLES := [0.0, 0.6, -1.2, PI / 2.0, PI, 0.3, -2.4]
const TALLY := DecalCatalog.TALLY_MAX
## Pictures tried at every preset spot (the first one also gets the size and turn sweep)
const SPOT_PICS := {
	"nose": ["shark_mouth", "eye"], "number": ["number:888", "number:1"], "tally": ["tally_air", "tally_ground"],
	"fin": ["skull_winged", "wasp"], "wing": ["bolt", "shark_mouth"],
}

## Fairing spots (x, z, collar radius) seen on the hangar models, per plane: the battle model gets the same fairings
static var fairing_spots := {}

var cases := 0
var counts := {}          # "<kind>|<category>" → decals with that problem
var totals := {}          # kind → decals audited
var bad: Array = []       # problem cases for the JSON (record dicts, so frames can show the same decal later)
var notes: Array[String] = []
var _pic := 0


## Audits plane `key` (`kind` «hangar» or «battle», `variant` — what else is on it) under `root` (the hangar pivot
## or the battle model's holder). Leaves the model without decals.
func run_model(root: Node3D, model: Node3D, key: String, kind: String, variant: String) -> void:
	var t0 := Time.get_ticks_msec()
	_pose(model, 0.0, 0.0)
	var none: Array[DecalRecord] = []
	PlaneDecals.show(model, key, none, 0)
	var hull := PlaneDecals.hull_of(model)
	if hull == null:
		notes.append("%s/%s/%s: no hull" % [kind, key, variant])
		return
	var glass := PlaneHull.glass_of(model)
	var scene := DecalAudit.collect(root, model, false)
	var tag_tris := {}
	for t in scene.count():
		tag_tris[scene.tag[t]] = int(tag_tris.get(scene.tag[t], 0)) + 1
	var fairings := 0
	for c in model.get_children():
		if c.has_meta(PlaneDecals.FAIRING):
			fairings += 1
			if kind == "hangar" and c.has_meta("spot"):
				var sp: Array = fairing_spots.get(key, [])
				if not sp.has(c.get_meta("spot")):
					sp.append(c.get_meta("spot"))
				fairing_spots[key] = sp
	print("DAUDIT model %s/%s/%s: scene %d triangles %s, hull %d (+%d extra), fairings %d" % [kind, key, variant,
		scene.count(), str(tag_tris), hull.triangles(), hull.extra.triangles() if hull.extra != null else 0, fairings])
	var list := _cases(hull, glass, scene, model, key)
	var part_cases: Array = []
	for cs: Dictionary in list:
		var res := _one(root, model, scene, hull, glass, key, cs)
		_count(kind, key, variant, cs, res)
		if String(cs["group"]).begins_with("part"):
			part_cases.append(cs)
	# the same decals with the flaps down and the bay open: what lies on a moving part has to move with it
	if not part_cases.is_empty():
		_pose(model, 1.0, 1.0)
		var posed := DecalAudit.collect(root, model, false)
		for cs: Dictionary in part_cases:
			var pc := cs.duplicate()
			pc["group"] = "posed_" + String(cs["group"])
			pc.erase("probe")
			var res := _one(root, model, posed, hull, glass, key, pc, false)
			_count(kind, key, variant, pc, res)
		_pose(model, 0.0, 0.0)
	_symmetry_pass(root, model, scene, hull, key, kind, variant)
	_overlap_pass(root, model, hull, key, kind, variant)
	PlaneDecals.show(model, key, none, 0)
	print("DAUDIT model %s/%s/%s done: %d decals, %.1f s" % [kind, key, variant, list.size(),
		(Time.get_ticks_msec() - t0) / 1000.0])


## Every livery of the class on the hangar model: the hull, the glass and a preset decal must not change with it
func run_liveries(model: Node3D, key: String) -> void:
	var cls := key.get_slice("_", 0)
	var lvl := int(key.get_slice("_", 1))
	var ref := -1
	for lv: Array in Livery.list(cls):
		Livery.apply(model, cls, lvl, String(lv[0]))
		var hull := PlaneDecals.hull_of(model)
		var glass := PlaneHull.glass_of(model)
		var recs: Array[DecalRecord] = []
		for spot in ["nose", "wing", "fin"]:
			var r := DecalPresets.record(hull, key, spot, -1, String(SPOT_PICS[spot][0]).get_slice(":", 0)) if hull != null else null
			if r != null:
				recs.append(r)
		PlaneDecals.show(model, key, recs, TALLY)
		var mi := (model.get_node_or_null("insignia/decals") as MeshInstance3D)
		var n: int = mi.mesh.surface_get_array_len(0) if mi != null and mi.mesh != null else 0
		if ref < 0:
			ref = n
		var ok: bool = hull != null and glass != null and glass.triangles() > 0 and n == ref and n > 0
		print("DAUDIT livery %s %s: %s (decal vertices %d, glass %d)" % [key, lv[0], "ok" if ok else "FAIL", n,
			glass.triangles() if glass != null else 0])
		if not ok:
			notes.append("livery %s %s changes the decals" % [key, lv[0]])
	var none: Array[DecalRecord] = []
	PlaneDecals.show(model, key, none, 0)


## Summary lines and the JSON file
func finish(path: String) -> void:
	var kinds: Array = totals.keys()
	print("DAUDIT summary: %d decals audited (%s)" % [cases, str(totals)])
	for cat: String in DecalAudit.LIMITS.keys() + ["cursor_miss"]:
		var row := "DAUDIT sum %-16s" % cat
		for k: String in kinds:
			row += "  %s %d/%d" % [k, int(counts.get(k + "|" + cat, 0)), int(totals[k])]
		print(row)
	for n in notes:
		print("DAUDIT note ", n)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"totals": totals, "counts": counts, "bad": bad, "notes": notes}, "\t"))
		f.close()


# ---------- one decal ----------

func _one(root: Node3D, model: Node3D, scene: DecalAudit.Tris, hull: PlaneHull, glass: PlaneHull, key: String,
		cs: Dictionary, rebuild := true) -> Dictionary:
	var r: DecalRecord = cs["rec"]
	var tally: int = cs.get("tally", TALLY)
	if rebuild:
		var one: Array[DecalRecord] = [r]
		PlaneDecals.show(model, key, one, tally)
	var dec := DecalAudit.collect(root, model, true)
	var ins := DecalAudit.collect(root, model, false, true)
	var res := DecalAudit.audit(scene, ins, dec, r, tally)
	if cs.has("probe"):   # the editor's cursor: where would a click on what the player sees land?
		var pr: Array = cs["probe"]
		var o: Vector3 = pr[0]
		var d: Vector3 = pr[1]
		var seen := scene.hull.ray_hit(o, d, 3.0)
		var cur := hull.raycast_clear(o, d, 3.0, glass)
		if seen.size() == 3 and cur.size() == 2:
			var tg := scene.tag[int(seen[2])]
			if o.distance_to(cur[0]) > o.distance_to(seen[0]) + 0.002 and tg in [DecalAudit.Tag.PART,
					DecalAudit.Tag.ADDON, DecalAudit.Tag.WELL]:
				res["cursor_behind"] = 1.0
	return res


func _count(kind: String, key: String, variant: String, cs: Dictionary, res: Dictionary) -> void:
	cases += 1
	totals[kind] = int(totals.get(kind, 0)) + 1
	var probs := DecalAudit.problems(res)
	if probs.is_empty():
		return
	var r: DecalRecord = cs["rec"]
	var vals := {}
	var txt := ""
	for p in probs:
		counts[kind + "|" + p] = int(counts.get(kind + "|" + p, 0)) + 1
		vals[p] = snappedf(float(res[p]), 0.001)
		txt += " %s=%.3f" % [p, float(res[p])]
	var by: Dictionary = res.get("by", {})
	if not by.is_empty():
		var names: Array = by.keys()
		names.sort_custom(func(x: String, y: String) -> bool: return int(by[x]) > int(by[y]))
		txt += " by=" + ",".join(PackedStringArray(names.slice(0, 3)))
	print("DAUDIT bad %s/%s/%s %s:%s %s s=%.3f a=%.2f%s" % [kind, key, variant, cs["group"], cs["label"], r.id,
		r.size, r.angle, txt])
	bad.append({"kind": kind, "key": key, "variant": variant, "group": cs["group"], "label": cs["label"],
		"rec": r.to_dict(), "tally": cs.get("tally", TALLY), "probs": vals})


## A preset on the left and its mirrored copy (the editor's «на другой борт»), and the left and the right preset:
## both pairs must cover the same skin, reflected
func _symmetry_pass(root: Node3D, model: Node3D, scene: DecalAudit.Tris, hull: PlaneHull, key: String, kind: String,
		variant: String) -> void:
	for spot: String in DecalPresets.NAMES:
		var a := _preset(hull, key, spot, -1, String(SPOT_PICS[spot][0]))
		if a == null:
			continue
		var right := _preset(hull, key, spot, 1, String(SPOT_PICS[spot][0]))
		for pair in [["mirror", DecalPresets.mirrored(a, hull)], ["preset_lr", right]]:
			var b: DecalRecord = pair[1]
			if b == null:
				continue
			a.c1 = "bone"
			b.c1 = "white"
			var two: Array[DecalRecord] = [a, b]
			PlaneDecals.show(model, key, two, TALLY)
			var dec := DecalAudit.collect(root, model, true)
			var sym := DecalAudit.symmetry(scene, dec, a, b, TALLY)
			var res := {"asym": 1.0 if (float(sym[0]) < 0.85 or float(sym[1]) > 0.01 or float(sym[2]) > 0.17) else 0.0,
				"iou": sym[0], "dpos": sym[1], "dang": sym[2]}
			var cs := {"group": "sym_" + String(pair[0]), "label": spot, "rec": b, "tally": TALLY}
			if float(res["asym"]) > 0.0:
				print("DAUDIT asym %s/%s/%s %s %s: IoU %.2f, centre off %.4f, up off %.1f°" % [kind, key, variant,
					pair[0], spot, sym[0], sym[1], rad_to_deg(float(sym[2]))])
			_count(kind, key, variant, cs, res)


## Two decals overlapping on the wing preset and on the nose preset: the later one has to draw over the earlier one
func _overlap_pass(root: Node3D, model: Node3D, hull: PlaneHull, key: String, kind: String, variant: String) -> void:
	for spot in ["wing", "nose", "fin"]:
		var a := _preset(hull, key, spot, -1, "bolt")
		if a == null:
			continue
		var b := DecalRecord.from_dict(a.to_dict())
		var bb := a.basis_vectors()
		var hit := hull.raycast(a.pos + bb[0] * a.size * 0.35 + a.normal * 0.03, -a.normal, 0.06)
		if hit.size() != 2:
			continue
		b.pos = hit[0]
		b.normal = hit[1]
		a.c1 = "bone"
		b.c1 = "white"
		var two: Array[DecalRecord] = [a, b]
		PlaneDecals.show(model, key, two, TALLY)
		var dec := DecalAudit.collect(root, model, true)
		var z := DecalAudit.overlap_zfight(dec, a, b, TALLY)
		_count(kind, key, variant, {"group": "overlap", "label": spot, "rec": b, "tally": TALLY}, {"zfight_pair": z})


# ---------- the decals to try ----------

func _cases(hull: PlaneHull, glass: PlaneHull, scene: DecalAudit.Tris, model: Node3D, key: String) -> Array:
	var out: Array = []
	# every preset spot on both sides, every picture kind
	for spot: String in DecalPresets.NAMES:
		for side in [-1, 1]:
			for pic: String in SPOT_PICS[spot]:
				var r := _preset(hull, key, spot, side, pic)
				if r != null:
					out.append({"group": "preset", "label": "%s_%s" % [spot, "L" if side < 0 else "R"], "rec": r})
				else:
					notes.append("%s: preset %s side %d misses the skin" % [key, spot, side])
		# sizes from min to max and turns, on the left spot
		var base := _preset(hull, key, spot, -1, String(SPOT_PICS[spot][0]))
		if base == null:
			continue
		for s: float in [DecalRecord.SIZE_MIN, base.size * 2.5, base.size * 5.0, DecalRecord.SIZE_MAX]:
			var r := DecalRecord.from_dict(base.to_dict())
			r.size = clampf(s, DecalRecord.SIZE_MIN, DecalRecord.SIZE_MAX)
			out.append({"group": "size", "label": "%s_%.3f" % [spot, r.size], "rec": r})
		for a: float in [PI / 4.0, PI / 2.0, PI, -PI / 3.0]:
			var r := DecalRecord.from_dict(base.to_dict())
			r.size = base.size * 1.5
			r.angle = a
			out.append({"group": "turn", "label": "%s_%d" % [spot, roundi(rad_to_deg(a))], "rec": r})
	# free placements: rays at the places a player would try, as the editor's cursor sees them
	var bb := AABB()
	for i in hull.triangles():
		bb = AABB(hull.pos[i * 3], Vector3.ZERO) if i == 0 else bb.expand(hull.pos[i * 3])
	var half := maxf(absf(bb.position.z), absf(bb.end.z))
	var probes: Array = []   # [group, label, origin, dir]
	for x: float in [0.46, 0.4, 0.3, 0.18, 0.06, -0.06, -0.18, -0.3, -0.4, -0.46]:
		for deg: float in [0.0, 40.0, 90.0, 140.0, 180.0]:
			var d := Vector3(0.0, cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)))
			probes.append(["ring", "x%.2f_%d" % [x, deg], Vector3(x, 0.0, 0.0) + d * 1.2, -d])
	for yz: Vector2 in [Vector2.ZERO, Vector2(0.015, 0.0), Vector2(-0.015, 0.0), Vector2(0.0, -0.015)]:
		probes.append(["nose", "front_%.3f_%.3f" % [yz.x, yz.y], Vector3(1.2, yz.x, yz.y), Vector3(-1, 0, 0)])
	probes.append(["nose", "front45", Vector3(1.2, 0.0, -1.2), Vector3(-1, 0, 1).normalized()])
	probes.append(["nose", "front_up45", Vector3(1.2, 1.2, 0.0), Vector3(-1, -1, 0).normalized()])
	for k: float in [0.12, 0.25, 0.45, 0.7, 0.9, 0.98]:
		for x: float in [0.3, 0.2, 0.1, 0.0, -0.1, -0.2, -0.3, -0.4]:
			probes.append(["wing", "top_%.2f_%.1f" % [k, x], Vector3(x, 1.2, -half * k), Vector3.DOWN])
			probes.append(["belly" if k < 0.15 else "wing", "under_%.2f_%.1f" % [k, x], Vector3(x, -1.2, -half * k), Vector3.UP])
	for k: float in [0.3, 0.55, 0.8, 0.95]:
		probes.append(["edge", "lead_%.2f" % k, Vector3(1.2, 0.72, -half * k), Vector3(-1, -0.6, 0).normalized()])
		for y: float in [-0.05, -0.03, -0.01, 0.01]:
			probes.append(["edge", "front_%.2f_%.2f" % [k, y], Vector3(1.2, y, -half * k), Vector3(-1, 0, 0)])
	for x: float in [0.1, 0.0, -0.1, -0.2, -0.3]:
		for y: float in [-0.07, -0.04, -0.01, 0.02]:
			probes.append(["tip", "side_%.1f_%.2f" % [x, y], Vector3(x, y, -1.2), Vector3(0, 0, 1)])
	for x: float in [-0.47, -0.42, -0.36, -0.3]:
		for y: float in [0.03, 0.06, 0.09, 0.12]:
			probes.append(["fin", "side_%.2f_%.2f" % [x, y], Vector3(x, y, -1.2), Vector3(0, 0, 1)])
	# moving parts, their seams with the wing, and everything laid on the model (details, fairings, the tail cabin)
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or String(mi.name).begins_with("decal"):
			continue
		var part := PlaneHull.under(mi, model, ["wing_mech", "bay_doors"])
		var addon := PlaneHull.under(mi, model, ["detail", "tail_cabin"]) or mi.has_meta(PlaneDecals.FAIRING)
		var ins := PlaneHull.under(mi, model, ["insignia"]) and String(mi.name).begins_with("wing") \
			or (PlaneHull.under(mi, model, ["insignia"]) and String(mi.get_parent().name).begins_with("wing"))
		if not (part or addon or ins) or String(mi.name).begins_with("bay_well"):
			continue
		var ab := PlaneHull.rel_transform(mi, model) * mi.mesh.get_aabb()
		var cc := ab.get_center()
		if cc.z > 0.004 and not ins:
			continue   # left side only; the right side is the mirror pass
		var grp := "part" if part else ("ins" if ins else "addon")
		var nm := String(mi.name) if not ins else String(mi.get_parent().name) + "/" + String(mi.name)
		var spots := [cc]
		if part:   # the seams: the part's front, inner and outer edges
			spots.append(Vector3(ab.end.x - 0.004, cc.y, cc.z))
			spots.append(Vector3(cc.x, cc.y, ab.end.z - 0.004))
			spots.append(Vector3(cc.x, cc.y, ab.position.z + 0.004))
		for i in spots.size():
			var p: Vector3 = spots[i]
			probes.append([grp, "%s_%d_top" % [nm, i], Vector3(p.x, 1.2, p.z), Vector3.DOWN])
			probes.append([grp, "%s_%d_under" % [nm, i], Vector3(p.x, -1.2, p.z), Vector3.UP])
			if addon:
				probes.append([grp, "%s_%d_side" % [nm, i], Vector3(p.x, p.y, -1.2), Vector3(0, 0, 1)])
	for pr: Array in probes:
		var o: Vector3 = pr[2]
		var d: Vector3 = pr[3]
		var hit := hull.raycast_clear(o, d, 3.0, glass)
		if hit.size() != 2:
			var seen := scene.hull.ray_hit(o, d, 3.0)
			if seen.size() == 3 and scene.tag[int(seen[2])] in [DecalAudit.Tag.PART, DecalAudit.Tag.ADDON]:
				# visible, but the cursor cannot put a decal there
				notes.append("%s: cursor misses %s %s (%s)" % [key, pr[0], pr[1], scene.names[scene.owner[int(seen[2])]]])
				counts["cursor_miss"] = int(counts.get("cursor_miss", 0)) + 1
			continue
		var r := _free(hit)
		out.append({"group": pr[0], "label": pr[1], "rec": r, "probe": [o, d]})
	return out


## A preset record with picture `pic` («number:888» — a number with those digits)
func _preset(hull: PlaneHull, key: String, spot: String, side: int, pic: String) -> DecalRecord:
	var r := DecalPresets.record(hull, key, spot, side, pic.get_slice(":", 0))
	if r != null and pic.contains(":"):
		r.text = pic.get_slice(":", 1)
	return r


## A free-placed record at `hit`: picture, size and turn cycle through PICS, SIZES and ANGLES
func _free(hit: Array) -> DecalRecord:
	var pic: String = PICS[_pic % PICS.size()]
	var r := DecalRecord.new()
	r.id = pic.get_slice(":", 0)
	if pic.contains(":"):
		r.text = pic.get_slice(":", 1)
	r.pos = hit[0]
	r.normal = (hit[1] as Vector3).normalized()
	r.size = SIZES[_pic % SIZES.size()]
	r.angle = ANGLES[_pic % ANGLES.size()]
	r.mirror = _pic % 5 == 3 and r.id != DecalCatalog.NUMBER
	_pic += 1
	return r


## Poses the flaps and slats (`mech` 0 up … 1 down) and the bay doors (`bay` 0 closed … 1 open)
static func _pose(model: Node3D, mech: float, bay: float) -> void:
	var m := model.find_child("wing_mech", true, false) as Node3D
	if m != null:
		WingMech.pose(m, mech)
	var b := model.find_child("bay_doors", true, false) as Node3D
	if b != null:
		WingMech.pose_bay(b, bay)


## The battle model of plane `key` under a new holder, built as Render3D builds the player's unit (module parts at
## `modules` level, slats and flaps, details, insignia with decals, bay doors, tail cabin) plus the hangar's turret
## fairings; the holder is added under `parent` (in the tree, so the decal watcher sees late fairings)
static func battle_model(parent: Node, key: String, modules: int) -> Node3D:
	var path := "res://models/battle/fh_battle_%s.glb" % key
	if not ResourceLoader.exists(path):
		return null
	var holder := Node3D.new()
	holder.name = "daudit_" + key
	parent.add_child(holder)
	var model: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(model)
	var modp := ModuleParts.attach(model, key)
	if modules > 0:
		ModuleParts.update(modp, {"engine": modules, "armor": modules, "gun_dmg": modules, "radio": modules})
	WingMech.attach(model, key)
	WingMech.attach_detail(model, key)
	Insignia.attach(model, key, "player")
	WingMech.attach_bay(model, key)
	WingMech.attach_tail(model, key)
	for sp: Vector3 in fairing_spots.get(key, []):
		var fr := SkinPatch.turret_fairing(model, sp.x, sp.y, sp.z)
		if fr != null:
			model.add_child(fr)
	return holder
