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

## Intros and outros by operation id (`Campaign.OPS` "id"); steps 5–8 add one operation each.
## Op 1 «Перевал» (step 5): dawn, the flight climbs over the first ridge with the road below; dusk at the end,
## the camera pulls back from the flight over the pass.
const INTRO := {
	"riverbed": {
		"dur": 10.0,
		"cam": [[0.0, Vector2(-900.0, 700.0), 0.62], [10.0, Vector2(500.0, -500.0), 0.74]],
		"flight": true,
		"heading": H_UP,
		"light": "day",
		"lines": [
			[0.5, 3.6, "", "Сухое русло · они строят"],
			[3.9, 9.6, StoryText.DISPATCH, "Позиции в руслах — по чертежу. Где-то над ними тот, кто чертит."],
		],
	},
	"pass": {
		"dur": 8.0,
		"cam": [[0.0, Vector2(0.0, 1100.0), 0.58], [8.0, Vector2(0.0, -600.0), 0.78]],
		"flight": true,
		"heading": H_UP,
		"light": "dawn",
		"lines": [
			[0.5, 3.4, "", "Перевал Шахрисанг · неделя после пропажи «Грома»"],
			[3.7, 7.6, StoryText.DISPATCH, "Колонна под вами. Пятнадцать минут над ней должно быть пусто."],
		],
	},
}
const OUTRO := {
	"riverbed": {
		"dur": 8.0,
		"cam": [[0.0, Vector2(0.0, -200.0), 0.95], [8.0, Vector2(300.0, 500.0), 0.55]],
		"flight": true,
		"heading": H_UP,
		"light": "dusk",
		"lines": [
			[0.4, 2.8, "", "Первая «Крепость» сбита"],
			[3.0, 7.6, StoryText.DISPATCH, "Первая. Не последняя: перехват говорит о «программе»."],
		],
	},
	"pass": {
		"dur": 6.5,
		"cam": [[0.0, Vector2(0.0, -250.0), 0.9], [6.5, Vector2(0.0, 700.0), 0.5]],
		"flight": true,
		"heading": H_UP,
		"light": "dusk",
		"lines": [
			[0.4, 2.4, "", "Перевал пройден"],
			[2.6, 6.1, StoryText.DISPATCH, "Колонна прошла. О «Громе» — ничего. Пока."],
		],
	},
}


## Scene for the start of an operation, {} when the operation has none.
static func intro(op_id: String) -> Dictionary:
	return INTRO.get(op_id, {})


## Scene after the evacuation, {} when the operation has none.
static func outro(op_id: String) -> Dictionary:
	return OUTRO.get(op_id, {})
