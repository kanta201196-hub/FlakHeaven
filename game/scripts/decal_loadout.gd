class_name DecalLoadout
extends RefCounted
## The decals of one plane (Kanta 27.10, free placement): a capped list of `DecalRecord` with a versioned save
## format and migrations. Saved per plane in the profile (`classes.<class>.decals1` / `decals2`) as
## {"v": VERSION, "items": [record, …]}. Pure logic, no autoloads — unit-tested in tests/decals_cases.gd.
##
## Formats: 0 — a bare list of records (early builds of the editor); 1 — {"v": 1, "items": […]}.
## A save from a newer build (v > VERSION) is not drawn and is written back untouched, so moving between the demo
## and the full game never wipes decals.

const VERSION := 1
const MAX_DECALS := 12   ## per plane: keeps the merged decal mesh and the editor list small
const TALLY_ROW := 10    ## marks in one tally row before the next row starts

var records: Array[DecalRecord] = []
var future := false      ## loaded from a newer format: keep `raw`, draw nothing
var raw: Variant = null


## Loadout from a saved value (null, an old format, the current one or a newer one); broken entries are dropped
static func parse(saved: Variant) -> DecalLoadout:
	var lo := DecalLoadout.new()
	var items: Variant = null
	if saved is Array:
		items = saved   # format 0
	elif saved is Dictionary:
		var v: Variant = (saved as Dictionary).get("v", 0)
		var ver := int(v) if (v is float or v is int) else 0
		if ver > VERSION:
			lo.future = true
			lo.raw = (saved as Dictionary).duplicate(true)
			return lo
		items = (saved as Dictionary).get("items")
	if items is Array:
		for e: Variant in items:
			var r := DecalRecord.from_dict(e)
			if r != null:
				add(lo.records, r)
	return lo


## Saved form of a loadout: the current format, or a newer one exactly as it was read
static func to_save(lo: DecalLoadout) -> Variant:
	if lo.future:
		return lo.raw
	var items: Array = []
	for r in lo.records:
		items.append(r.to_dict())
	return {"v": VERSION, "items": items}


## Adds `r` unless the plane already carries MAX_DECALS; returns whether it was added
static func add(list: Array[DecalRecord], r: DecalRecord) -> bool:
	if list.size() >= MAX_DECALS or r == null:
		return false
	list.append(r)
	return true


## Atlas stamps of one record: a picture is one stamp, a number one stamp per digit, a tally one per mark
## (`tally` marks, at most DecalCatalog.TALLY_MAX, rows of TALLY_ROW starting at the record's position)
static func stamps(r: DecalRecord, tally: int) -> Array[DecalStamp]:
	var out: Array[DecalStamp] = []
	var b := r.basis_vectors()
	var kind := DecalCatalog.kind(r.id)
	var ci := DecalCatalog.paint_index(r.c1)
	var cj := DecalCatalog.paint_index(r.c2)
	if kind == "number":
		var n := r.text.length()
		var w := r.size * DecalCatalog.DIGIT_W
		for i in n:
			var off := (float(i) - (n - 1) * 0.5) * w
			out.append(_stamp(r.pos + b[0] * off, r, b, w * 0.5, r.size * 0.5,
				DecalCatalog.digit_rect(r.text.unicode_at(i) - 48), false, ci, cj))
	elif kind == "tally":
		var count := clampi(tally, 0, DecalCatalog.TALLY_MAX)
		var step := r.size * 1.1
		var dir := -1.0 if r.mirror else 1.0   # mirror: the row grows the other way (towards the nose on the right side)
		for i in count:
			var col := i % TALLY_ROW
			var row := floori(i / float(TALLY_ROW))
			var c := r.pos + b[0] * (dir * col * step) - b[1] * (row * step)
			out.append(_stamp(c, r, b, r.size * 0.5, r.size * 0.5, DecalCatalog.image_rect(r.id), r.mirror, ci, cj))
	elif kind == "pic":
		out.append(_stamp(r.pos, r, b, r.size * 0.5 * DecalCatalog.aspect(r.id), r.size * 0.5,
			DecalCatalog.image_rect(r.id), r.mirror, ci, cj))
	return out


static func _stamp(c: Vector3, r: DecalRecord, b: Array[Vector3], hw: float, hh: float, uv: Rect2, mirror: bool,
		ci: int, cj: int) -> DecalStamp:
	var s := DecalStamp.new()
	s.center = c
	s.normal = r.normal
	s.right = b[0]
	s.up = b[1]
	s.half_w = hw
	s.half_h = hh
	s.uv = uv
	s.mirror = mirror
	s.c1 = ci
	s.c2 = cj
	return s
