class_name OpTasks
extends RefCounted
## OT-01: the side objectives of the current operation during one sortie (`OpTaskBalance.TASKS`). Counts activity
## successes and reports objectives as they complete; paying, banners and the campaign save are Main's job, so this
## stays pure and unit-tested (`op_tasks_test.gd`).

var op_id := ""
var defs: Array = []
var paid := 0.0   # parts Main paid for objectives this sortie (before the difficulty reward multiplier)
var _n := {}      # objective id → count
var _done := {}   # objective id → true


func _init(id: String) -> void:
	op_id = id
	defs = OpTaskBalance.tasks(id)
	for d: Dictionary in defs:
		_n[d["id"]] = 0


## An activity of `kind` succeeded. Returns the ids of objectives it completed just now (usually none).
func on_activity(kind: StringName) -> Array:
	var out: Array = []
	for d: Dictionary in defs:
		var id: String = d["id"]
		if _done.has(id) or String(d["act"]) != String(kind):
			continue
		_n[id] = int(_n[id]) + 1
		if int(_n[id]) >= int(d["need"]):
			_done[id] = true
			out.append(id)
	return out


func count(id: String) -> int:
	return int(_n.get(id, 0))


func is_done(id: String) -> bool:
	return _done.has(id)


func done_count() -> int:
	return _done.size()


func all_done() -> bool:
	return not defs.is_empty() and _done.size() == defs.size()


## The objective definition by id (empty if none).
func def(id: String) -> Dictionary:
	for d: Dictionary in defs:
		if d["id"] == id:
			return d
	return {}


## Combat panel rows: [done, text] per objective, text already translated.
func rows() -> Array:
	var out: Array = []
	for d: Dictionary in defs:
		var id: String = d["id"]
		out.append([is_done(id), Loc.t(String(d["hud"])) % [mini(count(id), int(d["need"])), int(d["need"])]])
	return out
