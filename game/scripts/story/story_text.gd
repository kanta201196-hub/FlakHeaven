class_name StoryText
extends RefCounted
## All story strings of the Highlands campaign in one table (plan step 1: skeleton; steps 5–8 fill the operations).
## Keys follow `StoryFlags.line_key` (speaker.op.moment). Russian is the source language; the HUD translates at
## draw time (`Loc.out`), so the lines stay plain Russian here and in `.po`. Design: `docs/story/highlands-storyline.md`.

const DISPATCH := "Купол"
## The Fortress controller: an enemy voice (red frame), unlike «Купол» who talks for our base.
const ENEMY_HQ := "Штаб «Монолита»"

## Radio of `story.gd` (EX-09 «Где Гром?»), by moment.
const RADIO := {
	"start.pass": "Звено, небо ваше. Колонна идёт по графику — не дайте её тронуть.",
	"start.other": "Разведка видит движение у перевала. Держитесь выше хребта.",
	"task": "Задание для вас: %s.",
	"baron.taunt": "Ваш ведущий падал красиво. Посмотрим, как упадёте вы.",
	"grom.join": "Звено, я снова в строю. Должок за мной.",
	"grom.finale": "Небо над Шахрисангом наше. Спасибо, что не бросили.",
	"grom.alive": "Перехват из крепости: «Гром» жив! Наземные идут за ним.",
	"ground.pass": "Это не ПВО кочевников. Кто-то строит здесь позиции по чертежу.",
	"fortress.sight.riverbed": "Вот она. Летающий штаб. Так вот кто чертит их позиции.",
}

## One story line under the operation title on the results screen, by operation id (first clear and replays alike).
## A key with a suffix is a variant picked by a campaign flag: `result()` tries "<op>.<flag>" first.
const RESULT := {
	"pass": "Перевал открыт. «Барон» знает ваш позывной.",
	"riverbed": "«Крепость» № 1 сбита. О «Громе» по-прежнему ничего.",
	"riverbed.rescued": "«Крепость» № 1 сбита. «Гром» — у старых крепостей?",
}

## Banners of the three in-combat accents (`Cinematic.accent`), by accent id.
const ACCENTS := {
	"fortress": "«Крепость» идёт на нашу базу! Перехватите её, пока не дошла",
	"baron": "«Барон» сбит! Небо над крепостями наше",
	"grom": "«Гром» в строю!",
}


## Banner of an in-combat accent, or "" for an unknown id.
static func accent(id: String) -> String:
	return String(ACCENTS.get(id, ""))


## Per-operation lines of recurring enemy pilots («Почтальон» = postman, «Сквозняк» = draft) and the Fortress
## controller: key → Array of lines; index by `StoryFlags.line_index(met, n)`: the first line is for the first
## meeting, the rest cycle on replays. A missing key means «use the generic line of the unit» (`Boss.LINES`).
## Op 1 (step 5): Postman is pure business, Draft echoes Baron.
const OP_LINES := {
	"postman.pass.spawn": ["Доставка по адресу. Принимайте, «Вершина».", "Опять вы на маршруте. Доставлю всё равно.", "Тот же адрес, тот же курьер."],
	"postman.pass.run": ["Посылка пошла.", "Распишитесь в получении."],
	"postman.pass.down": ["Груз сброшен… катапульта. Спасатели знают, где искать."],
	"draft.pass.spawn": ["Сквозит у вас в строю, новичок. Ведущего-то нет.", "Снова вы? «Барон» будет рад.", "Заткну сквозняк. Второй раз проще."],
	"draft.pass.angry": ["Повреждения! Ну всё, без вежливости."],
	"draft.pass.down": ["Выхожу… Это не считается, слышите? Не считается!"],
	# op 2 «Сухое русло»: Postman lets slip that the headquarters is in the air; the Fortress controller is surprised
	"postman.riverbed.spawn": ["Штаб видит вас с высоты. Доставлю.", "Опять вы. Штаб уже в курсе — он всё видит.", "Маршрут согласован со штабом. Сверху."],
	"postman.riverbed.run": ["Отправление по расписанию.", "Адресат — вы."],
	"postman.riverbed.down": ["Штаб, курьер выбыл… Катапульта."],
	"draft.riverbed.spawn": ["«Барон» просил передать: он вас помнит.", "Сквозняк вернулся. Соскучились?", "В руслах тесно, новичок. Уступите небо."],
	"draft.riverbed.down": ["Передайте «Барону»… а, сам скажу. Выхожу."],
	"hq.riverbed.arrive": ["Воздушный объект на маршруте штаба. Вы серьёзно? Отойдите от трассы.", "Штаб на маршруте. Повторяю: отойдите от трассы."],
	"hq.riverbed.wing": ["Потеря крыла. Штаб запрашивает резерв. Это… не по плану."],
}


## Radio line by key, or "" when the table has none (callers fall back to their generic lines).
static func radio(key: String) -> String:
	return String(RADIO.get(key, ""))


## Story line of the results screen for `op_id`; `flags` are the campaign flags that pick a variant (e.g. "rescued").
## "" when the operation has none.
static func result(op_id: String, flags: Array = []) -> String:
	for f in flags:
		if RESULT.has("%s.%s" % [op_id, String(f)]):
			return String(RESULT["%s.%s" % [op_id, String(f)]])
	return String(RESULT.get(op_id, ""))


## Line of a recurring pilot for this operation and moment, chosen by how often the player met them.
static func op_line(speaker: String, op_id: String, moment: String, met: int) -> String:
	var arr: Array = OP_LINES.get(StoryFlags.line_key(speaker, op_id, moment), [])
	if arr.is_empty():
		return ""
	return String(arr[StoryFlags.line_index(met, arr.size())])
