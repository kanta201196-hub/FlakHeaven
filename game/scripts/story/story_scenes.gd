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
##   lines  — captions [[t0, t1, speaker, text(, enemy)], …]; speaker "" draws a title instead of a radio line;
##            a fifth element `true` marks an enemy voice (red plate, like enemy radio in the sortie)
##   black  — true: a card over black (the epilogue hook), no world behind the captions
##   stinger — optional sound played when the scene starts (`Sfx.FILE_ONLY`)
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
## the camera pulls back from the flight over the pass. Op 3 «Крепости» (step 7): Baron's challenge on the open
## channel over the forts; "forts.recon" is the variant after the H2′ choice «передать разведке» (a marker caption);
## the outro is night, a green flare from the walls — Grom is ours. Op 4 «Небо над Шахрисангом» (step 8): the base at
## first light, everything the company has is in the air; the outro at sunset over the pass road, then the epilogue card.
const INTRO := {
	"sky": {
		"dur": 12.0,
		"cam": [[0.0, Vector2(-400.0, 1300.0), 0.52], [12.0, Vector2(200.0, -700.0), 0.74]],
		"flight": true,
		"heading": H_UP,
		"light": "dawn",
		"lines": [
			[0.5, 3.4, "", "База «Вершины» · первый свет"],
			[3.7, 8.0, StoryText.DISPATCH, "Все их звенья в воздухе. Курс «Крепости» — на нас."],
			[8.3, 11.6, StoryText.DISPATCH, "Поднимаемся всем, что есть."],
		],
	},
	"forts": {
		"dur": 10.0,
		"cam": [[0.0, Vector2(600.0, 900.0), 0.6], [10.0, Vector2(-300.0, -500.0), 0.76]],
		"flight": true,
		"heading": H_UP,
		"light": "day",
		"lines": [
			[0.5, 3.2, "", "Старые крепости · теперь это их позиции"],
			[3.5, 6.4, "Барон", "Один на один. Без ваших нянек.", true],
			[6.8, 9.6, StoryText.DISPATCH, "Не отвечайте. Пусть ищет."],
		],
	},
	"forts.recon": {
		"dur": 10.0,
		"cam": [[0.0, Vector2(600.0, 900.0), 0.6], [10.0, Vector2(-300.0, -500.0), 0.76]],
		"flight": true,
		"heading": H_UP,
		"light": "day",
		"lines": [
			[0.5, 3.2, "", "Старые крепости · метка разведки: восточная кала"],
			[3.5, 6.4, "Барон", "Один на один. Без ваших нянек.", true],
			[6.8, 9.6, StoryText.DISPATCH, "Не отвечайте. Пусть ищет. Метка на карте — ваша, не его."],
		],
	},
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
	"sky": {
		"dur": 12.0,
		"cam": [[0.0, Vector2(0.0, -300.0), 0.95], [12.0, Vector2(400.0, 900.0), 0.45]],
		"flight": true,
		"heading": H_UP,
		"light": "dusk",
		"lines": [
			[0.4, 3.0, "", "Дорога через перевал · колонна идёт"],
			[3.2, 7.6, StoryText.DISPATCH, "Колонна идёт. «Крепость» догорает на хребте. Дорога живёт."],
			[8.0, 11.6, "", "Кампания Нагорья завершена"],
		],
	},
	"forts": {
		"dur": 8.0,
		"cam": [[0.0, Vector2(0.0, -300.0), 0.9], [8.0, Vector2(-200.0, 600.0), 0.52]],
		"flight": true,
		"heading": H_UP,
		"light": "night",
		"lines": [
			[0.4, 2.8, "", "Ночь над крепостями"],
			[3.0, 7.6, StoryText.DISPATCH, "Зелёная ракета со стены. Зелёная. Он наш."],
		],
	},
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


## Scene for the start of an operation, {} when the operation has none. `variant` (e.g. a hangar choice) picks
## "<op>.<variant>" when such a scene exists, else the plain one.
static func intro(op_id: String, variant: String = "") -> Dictionary:
	if variant != "" and INTRO.has("%s.%s" % [op_id, variant]):
		return INTRO["%s.%s" % [op_id, variant]]
	return INTRO.get(op_id, {})


## Scene after the evacuation, {} when the operation has none.
static func outro(op_id: String) -> Dictionary:
	return OUTRO.get(op_id, {})


## Epilogue cards over black after an outro, by "<op>.<variant>": the op 4 hook to the south when the Archipelago is
## live ("south"), the promise until then ("later"). The stinger plays under the card.
const EPILOGUE := {
	"sky.south": {
		"dur": 7.0,
		"cam": [[0.0, Vector2.ZERO, 0.7], [7.0, Vector2.ZERO, 0.7]],
		"flight": false,
		"black": true,
		"light": "night",
		"stinger": "sting_epilogue",
		"lines": [[1.0, 6.4, StoryText.DISPATCH, StoryText.RADIO["hook.south"]]],
	},
	"sky.later": {
		"dur": 7.0,
		"cam": [[0.0, Vector2.ZERO, 0.7], [7.0, Vector2.ZERO, 0.7]],
		"flight": false,
		"black": true,
		"light": "night",
		"stinger": "sting_epilogue",
		"lines": [[1.0, 6.4, StoryText.DISPATCH, StoryText.RADIO["hook.later"]]],
	},
}


## Epilogue card of an operation, {} when it has none; `south_live` — whether the next biome can be played.
static func epilogue(op_id: String, south_live: bool) -> Dictionary:
	return EPILOGUE.get("%s.%s" % [op_id, "south" if south_live else "later"], {})
