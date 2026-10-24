extends SceneTree
## Unit tests for `UiFocus` (CS-11c): which item gets gamepad/keyboard focus when the player
## presses a direction. Rules pinned here: move only to items that lie in that direction,
## prefer the item closest along the direction and best aligned across it, keep focus when
## nothing lies that way, and fall back to the first item when the focus id is gone.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_vertical_list()
	_test_edges_stay()
	_test_cross_column()
	_test_prefers_aligned()
	_test_index_of()
	_test_empty()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Five main menu rows stacked 92 px apart.
func _menu_rows() -> Array[Rect2]:
	var rows: Array[Rect2] = []
	for i in 5:
		rows.append(Rect2(96, 520 + i * 92, 490, 84))
	return rows


func _test_vertical_list() -> void:
	var r := _menu_rows()
	_check(UiFocus.step(r, 0, Vector2i.DOWN) == 1, "down from first goes to second")
	_check(UiFocus.step(r, 2, Vector2i.UP) == 1, "up from third goes to second")
	_check(UiFocus.step(r, 3, Vector2i.DOWN) == 4, "down from fourth goes to last")


func _test_edges_stay() -> void:
	var r := _menu_rows()
	_check(UiFocus.step(r, 0, Vector2i.UP) == 0, "up from first stays")
	_check(UiFocus.step(r, 4, Vector2i.DOWN) == 4, "down from last stays")
	_check(UiFocus.step(r, 2, Vector2i.LEFT) == 2, "left with nothing there stays")


## Menu rows on the left, two cards on the right: right moves across, left comes back.
func _test_cross_column() -> void:
	var r := _menu_rows()
	r.append(Rect2(1356, 150, 500, 84))   # 5: «Что нового»
	r.append(Rect2(1356, 252, 500, 84))   # 6: «Отзыв»
	r.append(Rect2(1356, 442, 250, 48))   # 7: Нагорье
	_check(UiFocus.step(r, 0, Vector2i.RIGHT) == 7, "right from first row picks the nearest card by distance")
	_check(UiFocus.step(r, 5, Vector2i.LEFT) == 0, "left from top card goes to the closest row")
	_check(UiFocus.step(r, 5, Vector2i.DOWN) == 6, "down inside the right column")


## Of two items to the right, the one level with the current item wins over a closer
## diagonal one, so focus does not jump rows unexpectedly.
func _test_prefers_aligned() -> void:
	var r: Array[Rect2] = [Rect2(0, 0, 100, 40), Rect2(160, 120, 100, 40), Rect2(260, 0, 100, 40)]
	_check(UiFocus.step(r, 0, Vector2i.RIGHT) == 2, "aligned item beats a diagonal one")


func _test_index_of() -> void:
	var ids: Array[StringName] = [&"menu_play", &"menu_hangar", &"menu_quit"]
	_check(UiFocus.index_of(ids, &"menu_hangar") == 1, "known id")
	_check(UiFocus.index_of(ids, &"gone") == 0, "unknown id falls back to the first item")
	var none: Array[StringName] = []
	_check(UiFocus.index_of(none, &"x") == -1, "empty list has no focus")


func _test_empty() -> void:
	var r: Array[Rect2] = []
	_check(UiFocus.step(r, -1, Vector2i.DOWN) == -1, "empty list stays without focus")
	var one: Array[Rect2] = [Rect2(0, 0, 10, 10)]
	_check(UiFocus.step(one, -1, Vector2i.DOWN) == 0, "no focus yet takes the first item")
