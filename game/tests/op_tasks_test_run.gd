extends Node
## Unit tests for operation objectives (OT-01): every Highlands operation has two objectives built on its
## activity queue, counting moves only on matching activities, an objective completes once, and the queue
## of an operation gives its objectives enough slots. Working part of op_tasks_test.gd: Spawner and Loc need the
## autoloads, which exist only after the SceneTree has started, so the checks run from `_ready`.

var _failed := 0
var _checks := 0


func _ready() -> void:
	for id in ["pass", "riverbed", "forts", "sky"]:
		var defs := OpTaskBalance.tasks(id)
		_check(defs.size() == 2, "%s: two objectives" % id)
		var q := OpTaskBalance.queue(id)
		for d: Dictionary in defs:
			_check(Spawner.ACTIVITIES.has(String(d["act"])), "%s/%s: counts a real activity" % [id, d["id"]])
			# an objective's activity comes twice a round (other kinds once), at least 2 slots of 7
			var slots := q.count(String(d["act"]))
			_check(slots >= 2 and slots * 7 >= q.size() * 2, "%s/%s: %d of %d queue slots" % [id, d["id"], slots, q.size()])
			_check(int(d["need"]) >= 1 and int(d["need"]) <= 4, "%s/%s: need 1–4" % [id, d["id"]])
		for k: String in q:
			_check(Spawner.ACTIVITIES.has(k), "%s: queue kind %s exists" % [id, k])
	# the sea biome is on hold: no objectives, the common queue
	_check(OpTaskBalance.tasks("strait").is_empty(), "Archipelago: no objectives yet")
	_check(OpTaskBalance.queue("strait") == Spawner.ACTIVITIES, "Archipelago: the common queue")
	_check(OpTaskBalance.queue("nope") == Spawner.ACTIVITIES, "unknown operation: the common queue")

	var t := OpTasks.new("pass")
	_check(t.defs.size() == 2 and t.done_count() == 0, "pass: starts with nothing done")
	_check(t.on_activity(&"dogfight").is_empty(), "a duel does not count on «Перевал»")
	_check(t.count("convoys") == 0, "duel left the convoy counter at 0")
	var done: Array = []
	for i in 3:
		done.append_array(t.on_activity(&"convoy"))
	_check(done == ["convoys"], "third convoy completes «convoys» once (%s)" % [done])
	_check(t.on_activity(&"convoy").is_empty() and t.count("convoys") == 3, "a fourth convoy changes nothing")
	_check(t.is_done("convoys") and not t.is_done("aa"), "convoys done, AA not")
	t.on_activity(&"ground")
	_check(t.on_activity(&"ground") == ["aa"] and t.done_count() == 2 and t.all_done(), "two AA sites: all done")
	var rows := t.rows()
	_check(rows.size() == 2 and bool(rows[0][0]) and bool(rows[1][0]), "rows show both done")

	var none := OpTasks.new("strait")
	_check(none.defs.is_empty() and none.on_activity(&"convoy").is_empty() and not none.all_done(), "no objectives: inert")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
