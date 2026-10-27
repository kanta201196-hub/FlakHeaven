class_name DecalEditor
extends RefCounted
## Editing state of the hangar decal editor (spec 2026-10-27-plane-decals-design.md §4, §6): the plane's decal list,
## the selected decal, the picture being placed («tool») and its settings. Every rule of the editor lives here —
## what a click places, what a bumper turns, what the cap refuses — so HudDecals only draws and MainInput only routes
## input. Pure logic on `DecalRecord`s and a `PlaneHull`; unit-tested in tests/decals_cases.gd.
##
## Edits act on the selected decal and also become the tool's settings, so the next stamp matches the last one.
## The caller writes `records` to the profile after every change (`changed`) and saves the file when it closes.

const ROT_STEP := PI / 12.0   ## one bumper / Q / E press: 15°
const ROT_FINE := PI / 90.0   ## with Shift or a held bumper: 2°
const SCALE_STEP := 1.1       ## one trigger / wheel step
const PREVIEW_TALLY := 5      ## marks a tally shows in the editor while the plane has none yet
const GRAB_K := 0.6           ## a click this close to a decal's centre (× its size) picks it up

var cls := ""
var lvl := 1
var records: Array[DecalRecord] = []
var sel := -1                 ## selected record, -1 none
var tool := ""                ## picture being placed, "" none
var moving := false           ## the selected record follows the cursor
var size := 0.04
var angle := 0.0
var mirror := false
var c1 := DecalCatalog.DEFAULT_C1
var c2 := DecalCatalog.DEFAULT_C2
var text := DecalPresets.NUMBER_TEXT
var changed := false          ## records differ from what the caller last stored


## Starts editing plane `lv` of class `c` with copies of `list`
func open(c: String, lv: int, list: Array[DecalRecord]) -> void:
	cls = c
	lvl = lv
	records.clear()
	for r in list:
		var copy := DecalRecord.from_dict(r.to_dict())
		if copy != null:
			DecalLoadout.add(records, copy)
	sel = -1
	tool = ""
	moving = false
	changed = false


## Takes picture `id` as the tool; "" when done, else why not: "unknown", "locked" (`is_open` false), "cap"
func pick(id: String, is_open: bool) -> String:
	if not DecalCatalog.has_image(id):
		return "unknown"
	if not is_open:
		return "locked"
	if records.size() >= DecalLoadout.MAX_DECALS:
		return "cap"
	tool = id
	sel = -1
	moving = false
	return ""


## The record a click at `hit` ([position, normal] on the skin) would place, or where the moving decal would land;
## null when the hit is empty or there is nothing to place or move
func preview(hit: Array) -> DecalRecord:
	if hit.size() != 2:
		return null
	var r: DecalRecord = null
	if moving and sel >= 0:
		r = DecalRecord.from_dict(records[sel].to_dict())
	elif tool != "":
		r = DecalRecord.new()
		r.id = tool
		r.size = size
		r.angle = angle
		r.c1 = c1
		r.c2 = c2
		if DecalCatalog.kind(tool) == "number":
			r.text = text
		else:
			r.mirror = mirror
	if r != null:
		r.pos = hit[0]
		r.normal = (hit[1] as Vector3).normalized()
	return r


## Places the tool at `hit` and selects the new decal (the tool stays for the next stamp)
func place(hit: Array) -> bool:
	if moving:
		return false
	var r := preview(hit)
	if r == null or not DecalLoadout.add(records, r):
		return false
	sel = records.size() - 1
	changed = true
	return true


## Selects the topmost decal whose centre is near `pos` (the last drawn wins); the tool is put away
func select_at(pos: Vector3) -> int:
	sel = -1
	for i in range(records.size() - 1, -1, -1):
		if records[i].pos.distance_to(pos) <= maxf(records[i].size * GRAB_K, 0.006):
			sel = i
			break
	if sel >= 0:
		tool = ""
	return sel


## Picks up the selected decal to move it
func grab() -> bool:
	if sel < 0:
		return false
	moving = true
	return true


## Puts the moving decal down at `hit`; false (still moving) off the plane
func drop(hit: Array) -> bool:
	if not moving or sel < 0 or hit.size() != 2:
		return false
	records[sel].pos = hit[0]
	records[sel].normal = (hit[1] as Vector3).normalized()
	moving = false
	changed = true
	return true


## Gamepad B / Esc: stops a move, else puts the tool away and drops the selection; false when there was nothing to
## drop (then B leaves the editor)
func cancel() -> bool:
	var had := moving or sel >= 0 or tool != ""
	moving = false
	sel = -1
	tool = ""
	return had


## Scales by SCALE_STEP^steps within the record limits
func scale_by(steps: int) -> void:
	size = clampf(size * pow(SCALE_STEP, steps), DecalRecord.SIZE_MIN, DecalRecord.SIZE_MAX)
	if sel >= 0:
		records[sel].size = clampf(records[sel].size * pow(SCALE_STEP, steps), DecalRecord.SIZE_MIN, DecalRecord.SIZE_MAX)
		size = records[sel].size
		changed = true


## Turns around the skin normal by `steps` × 15° (2° when `fine`)
func rotate_by(steps: int, fine := false) -> void:
	var d := steps * (ROT_FINE if fine else ROT_STEP)
	angle = wrapf(angle + d, -PI, PI)
	if sel >= 0:
		records[sel].angle = wrapf(records[sel].angle + d, -PI, PI)
		angle = records[sel].angle
		changed = true


## Mirrors the picture (a number stays readable)
func toggle_mirror() -> void:
	mirror = not mirror
	if sel >= 0 and DecalCatalog.kind(records[sel].id) != "number":
		records[sel].mirror = not records[sel].mirror
		mirror = records[sel].mirror
		changed = true


## Paint `id` into slot 1 (primary) or 2 (secondary); unknown paints are ignored
func set_paint(slot: int, id: String) -> void:
	if not DecalCatalog.PAINTS.has(id):
		return
	if slot == 1:
		c1 = id
	else:
		c2 = id
	if sel >= 0:
		if slot == 1:
			records[sel].c1 = id
		else:
			records[sel].c2 = id
		changed = true


## The next palette paint in slot 1 or 2 (gamepad Y)
func next_paint(slot: int) -> void:
	var keys: Array = DecalCatalog.PAINTS.keys()
	var cur := (records[sel].c1 if slot == 1 else records[sel].c2) if sel >= 0 else (c1 if slot == 1 else c2)
	set_paint(slot, String(keys[(keys.find(cur) + 1) % keys.size()]))


## Digits of a number decal (1–3; anything else is dropped; empty input changes nothing)
func set_text(s: String) -> void:
	var d := DecalRecord.digits_of(s)
	if d == "":
		return
	text = d
	if sel >= 0 and DecalCatalog.kind(records[sel].id) == "number":
		records[sel].text = d
		changed = true


## Deletes the selected decal
func remove() -> void:
	if sel < 0:
		return
	records.remove_at(sel)
	sel = -1
	moving = false
	changed = true


## Moves the selected decal `delta` places in the draw order (later ones are drawn over earlier ones)
func order(delta: int) -> void:
	if sel < 0:
		return
	var to := clampi(sel + delta, 0, records.size() - 1)
	if to == sel:
		return
	var r := records[sel]
	records.remove_at(sel)
	records.insert(to, r)
	sel = to
	changed = true


## «На другой борт»: adds the mirror copy of the selected decal and selects it
func other_side(hull: PlaneHull) -> bool:
	if sel < 0 or moving:
		return false
	var m := DecalPresets.mirrored(records[sel], hull)
	if m == null or not DecalLoadout.add(records, m):
		return false
	sel = records.size() - 1
	changed = true
	return true


## Places the tool at preset `spot` of plane `key` on `side` (−1 left, +1 right) with the tool's paints
func preset(hull: PlaneHull, key: String, spot: String, side: int) -> bool:
	if tool == "" or moving:
		return false
	var r := DecalPresets.record(hull, key, spot, side, tool)
	if r == null:
		return false
	r.c1 = c1
	r.c2 = c2
	r.angle = angle
	if DecalCatalog.kind(tool) == "number":
		r.text = text
	if not DecalLoadout.add(records, r):
		return false
	sel = records.size() - 1
	size = r.size
	changed = true
	return true


## The decals to draw on the plane now (the moving one is drawn as the preview instead)
func shown() -> Array[DecalRecord]:
	var out: Array[DecalRecord] = []
	for i in records.size():
		if not (moving and i == sel):
			out.append(records[i])
	return out
