class_name StoryDialogs
extends RefCounted
## Hangar dialogue scenes of the Highlands story (plan step 3: registry and a test scene; steps 5–8 fill the
## operations). Scene ids are campaign flag names: "hangar_<op id>" before an operation, "hangar_<op id>_after"
## after it, "hangar_prologue" (H0) and "hangar_aces" (HX). Format: `DialogFlow` docstring. Russian is the source
## language; the HUD translates at draw time (`Loc.out`). Design: `docs/story/highlands-storyline.md` §11.

## Every story scene in campaign order, for the «Журнал» panel of the campaign screen: [id, title, kind].
## Kind "dlg" is a hangar dialogue (replayable from the log), "cut" an in-engine cutscene (listed only).
const ORDER := [
	["hangar_prologue", "Пролог: неделя после «Грома»", "dlg"],
	["hangar_pass", "Перед операцией «Перевал»", "dlg"],
	["intro_pass", "Заставка: «Перевал»", "cut"],
	["outro_pass", "Финал: «Перевал»", "cut"],
	["hangar_pass_after", "После операции «Перевал»", "dlg"],
	["hangar_riverbed", "Перед операцией «Сухое русло»", "dlg"],
	["intro_riverbed", "Заставка: «Сухое русло»", "cut"],
	["outro_riverbed", "Финал: «Сухое русло»", "cut"],
	["hangar_riverbed_after", "После операции «Сухое русло»", "dlg"],
	["hangar_forts", "Перед операцией «Крепости»", "dlg"],
	["intro_forts", "Заставка: «Крепости»", "cut"],
	["outro_forts", "Финал: «Крепости»", "cut"],
	["hangar_forts_after", "После операции «Крепости»", "dlg"],
	["hangar_sky", "Перед операцией «Небо над Шахрисангом»", "dlg"],
	["intro_sky", "Заставка: «Небо над Шахрисангом»", "cut"],
	["outro_sky", "Финал: «Небо над Шахрисангом»", "cut"],
	["hangar_sky_after", "Эпилог", "dlg"],
	["hangar_aces", "Учебный полигон «Вершины»", "dlg"],
]

## Scene id → definition. Empty until the content steps; a missing id means «no scene», and the flow goes on.
const SCENES := {}

## `--dialog`: a test scene for the runtime (one crew line with the trait colour, a guest line, a choice and a line
## per option), played before the sortie. Not part of the campaign; not listed in the log.
const TEST := {"steps": [
	{"who": "Купол", "text": "Звено, проверка связи. Ангар слышит вас, картинка идёт."},
	{"who": "crew", "text": "Слышу чисто. Когда вылет?", "trait": true},
	{"choice": "test", "prompt": "Купол ждёт ответа.", "options": [["Спросить о погоде", "weather"], ["Спросить о колонне", "convoy"]]},
	{"who": "Купол", "text": "Над перевалом ясно, ветер с юга. Хороший день для работы.", "only": ["test", "weather"]},
	{"who": "Купол", "text": "Колонна вышла в срок. Ваше дело — чтобы она пришла.", "only": ["test", "convoy"]},
]}


## Definition of scene `id`, or an empty Dictionary when the content is not written yet.
static func scene(id: String) -> Dictionary:
	return SCENES.get(id, {})


## Title of a scene for the story log ("" for ids outside `ORDER`).
static func title(id: String) -> String:
	for row: Array in ORDER:
		if String(row[0]) == id:
			return String(row[1])
	return ""
