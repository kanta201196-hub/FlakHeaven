class_name StoryScenes
extends RefCounted
## Scene definitions of the Highlands story (plan step 2: the runtime and one test scene; steps 5–8 add the
## intros and outros of the operations). A scene is a Dictionary the `Cutscene` runtime plays:
##   dur    — seconds of real time
##   cam    — camera keys [[t, offset: Vector2, zoom], …]; offsets are world px from the anchor
##            (the player's position when the scene starts), so one definition works on any map
##   flight — true: the player's flight (hangar models, player livery) flies at the screen anchor, as on the menu
##   heading — course of the flight, rad (TitleFlight.H0 points up the screen)
##   light  — "day" | "dawn" | "dusk" | "night" (Render3D light preset, restored after the scene)
##   lines  — captions [[t0, t1, speaker, text], …]; speaker "" draws a title instead of a radio line
## Design: docs/story/cutscenes-and-presentation.md §3.4.

## Course «up the screen» (= TitleFlight.H0; repeated here so the table has no engine dependency and unit tests load it).
const H_UP := -PI / 2.0 - 0.2

## `--cutscene` flag: a fly-over for checking the runtime and the frame on both renderers.
const TEST := {
	"dur": 9.0,
	"cam": [[0.0, Vector2(0.0, 1400.0), 0.55], [9.0, Vector2(0.0, -900.0), 0.72]],
	"flight": true,
	"heading": H_UP,
	"light": "dawn",
	"lines": [
		[0.6, 3.6, "", "Нагорье Шахрисанг"],
		[3.8, 8.6, StoryText.DISPATCH, "Звено, небо ваше. Колонна идёт по графику — не дайте её тронуть."],
	],
}

## Intros and outros by operation id (`Campaign.OPS` "id"); filled in steps 5–8.
const INTRO := {}
const OUTRO := {}


## Scene for the start of an operation, {} when the operation has none.
static func intro(op_id: String) -> Dictionary:
	return INTRO.get(op_id, {})


## Scene after the evacuation, {} when the operation has none.
static func outro(op_id: String) -> Dictionary:
	return OUTRO.get(op_id, {})
