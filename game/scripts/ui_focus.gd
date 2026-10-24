class_name UiFocus
extends RefCounted
## Gamepad and keyboard focus for screens drawn in code (CS-11c, design system §4 pattern 2).
## Screens rebuild their buttons every frame, so focus is kept as an action id and resolved
## to an index in the current frame's list. Pure logic, no nodes: unit tests in
## `game/tests/ui_focus_test.gd`.

## How much sideways offset counts against a candidate compared with distance along the
## pressed direction: 2 keeps focus in the same row or column unless nothing is there.
const CROSS_WEIGHT := 2.0
## Overlap in pixels still treated as "next to" when checking which items lie past an edge.
const EDGE_TOL := 4.0


## Index of the item focus moves to from `current` when `dir` is pressed (one of
## Vector2i.UP/DOWN/LEFT/RIGHT). Only items lying fully past the current item's edge in that
## direction count (a narrow item inside a wide card's span is not "to its left"); the
## nearest one by "distance along + CROSS_WEIGHT × distance across" wins. Returns `current`
## when nothing lies that way, 0 when there is no focus yet, -1 for an empty list.
static func step(rects: Array[Rect2], current: int, dir: Vector2i) -> int:
	if rects.is_empty():
		return -1
	if current < 0 or current >= rects.size():
		return 0
	var cur := rects[current]
	var from := cur.get_center()
	var d := Vector2(dir)
	var best := current
	var best_score := INF
	for i in rects.size():
		if i == current:
			continue
		if not _beyond(cur, rects[i], dir):
			continue
		var delta := rects[i].get_center() - from
		var along := delta.dot(d)
		var across := absf(delta.dot(Vector2(-d.y, d.x)))
		var score := along + CROSS_WEIGHT * across
		if score < best_score:
			best_score = score
			best = i
	return best


## Index of `id` in this frame's focusable ids; 0 when the id is gone (screen changed),
## -1 when the screen has nothing to focus.
static func index_of(ids: Array[StringName], id: StringName) -> int:
	if ids.is_empty():
		return -1
	var i := ids.find(id)
	return i if i >= 0 else 0


## Direction pressed in this input event (ui_up/down/left/right: arrows, d-pad, left stick),
## or Vector2i.ZERO when the event is not a navigation press.
static func dir_of(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("ui_up", true):
		return Vector2i.UP
	if event.is_action_pressed("ui_down", true):
		return Vector2i.DOWN
	if event.is_action_pressed("ui_left", true):
		return Vector2i.LEFT
	if event.is_action_pressed("ui_right", true):
		return Vector2i.RIGHT
	return Vector2i.ZERO


## True when `cand` starts past `cur`'s edge in direction `dir` (EDGE_TOL px of overlap
## allowed, so touching or hairline-overlapping neighbours still count).
static func _beyond(cur: Rect2, cand: Rect2, dir: Vector2i) -> bool:
	match dir:
		Vector2i.RIGHT:
			return cand.position.x >= cur.end.x - EDGE_TOL
		Vector2i.LEFT:
			return cand.end.x <= cur.position.x + EDGE_TOL
		Vector2i.DOWN:
			return cand.position.y >= cur.end.y - EDGE_TOL
		Vector2i.UP:
			return cand.end.y <= cur.position.y + EDGE_TOL
	return false
