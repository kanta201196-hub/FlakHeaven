extends SceneTree
## Unit tests for `RadioPick` (s15 review п. 13, radio lines repeat): a table of N lines never repeats a line
## within N picks under the same key; keys do not share memory; a one-line table still answers.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_no_repeat_in_cycle()
	_test_keys_apart()
	_test_small_tables()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_no_repeat_in_cycle() -> void:
	RadioPick.reset()
	var lines := ["a", "b", "c", "d", "e", "f"]
	var said: Array = []
	for i in 300:
		said.append(RadioPick.pick("spawn", lines))
	var bad := 0
	for i in range(1, said.size()):
		for j in range(maxi(0, i - (lines.size() - 1)), i):
			if said[i] == said[j]:
				bad += 1
	_check(bad == 0, "no line repeats within %d picks (%d repeats)" % [lines.size() - 1, bad])
	_check(_uniq(said.slice(0, 6)) == 6, "the first six picks are six different lines")


func _test_keys_apart() -> void:
	RadioPick.reset()
	var a := RadioPick.pick("hit", ["x", "y"])
	var b := RadioPick.pick("down", ["x", "y"])
	var a2 := RadioPick.pick("hit", ["x", "y"])
	_check(a2 != a, "the same key alternates two lines")
	_check(b in ["x", "y"], "another key picks from its own table")


func _test_small_tables() -> void:
	RadioPick.reset()
	_check(RadioPick.pick("one", ["only"]) == "only" and RadioPick.pick("one", ["only"]) == "only", "a one-line table repeats its line")
	_check(RadioPick.pick("none", []) == "", "an empty table gives an empty line")


func _uniq(a: Array) -> int:
	var d := {}
	for x in a:
		d[x] = true
	return d.size()
