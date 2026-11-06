class_name MouseView
extends RefCounted
## When the system mouse arrow shows. In flight the mouse steers and the HUD draws its own marker, and a story
## cutscene is watched, so the arrow is hidden there. A hangar dialogue scene is read with the keyboard but its options
## can be clicked: the arrow shows while the mouse moves and hides again after IDLE_HIDE s (S16-28: it sat over every
## dialogue). Pure rule here (unit-tested in `tests/mouse_view_test.gd`); `Main` applies it each frame.

const IDLE_HIDE := 1.5   # s without mouse movement before the arrow hides in a dialogue scene


## Whether the arrow is hidden in game state `state` when the mouse last moved `idle` real seconds ago.
static func hidden(state: String, idle: float) -> bool:
	if state in ["playing", "cutscene"]:
		return true
	if state == "dialog":
		return idle >= IDLE_HIDE
	return false


## The mouse mode for `hidden` — HIDDEN still reports motion and clicks, so steering and option clicks keep working.
static func mode(is_hidden: bool) -> Input.MouseMode:
	return Input.MOUSE_MODE_HIDDEN if is_hidden else Input.MOUSE_MODE_VISIBLE
