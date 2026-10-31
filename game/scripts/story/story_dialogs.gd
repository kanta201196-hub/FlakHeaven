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

## Scene id → definition; a missing id means «no scene», and the flow goes on. Op 1 (step 5): H0 prologue, H1
## briefing with the first choice (Monolith or Grom first), H1′ debrief (Baron knows the callsign, the rescuers joke).
const SCENES := {
	"hangar_prologue": {"steps": [
		{"who": "Купол", "text": "Неделю назад над перевалом пропал «Гром». Последнее, что было в эфире, — позывной «Барон»."},
		{"who": "Купол", "text": "Те, кто его сбил, — не банда. Компания «Монолит»: строят дорогу, ПВО и всё, что закажет клиент. Их правило — «Дорога, потом подпись»."},
		{"who": "Купол", "text": "Пока дорога через перевал наша, их контракт не закрыт. Поэтому летаем мы — больше некому."},
		{"who": "crew", "text": "Понял, «Купол». Когда вылет?", "trait": true},
		{"who": "Купол", "text": "Как только колонна выйдет. Самолёт готов — «Ключ» клянётся, что в этот раз закрылки держатся."},
	]},
	"hangar_pass": {"steps": [
		{"who": "Купол", "text": "Колонна выходит на перевал через час. Ваша задача — чтобы над ней пятнадцать минут было пусто."},
		{"choice": "ask_pass", "prompt": "Есть минута на вопрос.", "options": [["Спросить о «Монолите»", "monolith"], ["Спросить о «Громе»", "grom"]]},
		{"who": "Купол", "text": "Инженеры с охраной. Приходят с контрактом клиента и строят, пока долина не подпишет. Их асы — тоже по контракту.", "only": ["ask_pass", "monolith"]},
		{"who": "Купол", "text": "Парашюта никто не видел. Перехватов с его именем — тоже. Для меня это значит «ищем».", "only": ["ask_pass", "grom"]},
		{"who": "crew", "text": "Принято. Работаем над дорогой."},
	]},
	"hangar_riverbed": {"steps": [
		{"who": "Купол", "text": "Сухие русла за перевалом. Разведка насчитала шесть позиций ПВО — ровные, как по линейке. Их строят под кого-то в воздухе."},
		{"who": "Купол", "text": "Их курьер в эфире называет это «штаб». Что он имеет в виду, узнаем к пятнадцатой минуте."},
		{"choice": "ask_riverbed", "prompt": "Один вопрос до вылета.", "options": [["Спросить о «штабе в воздухе»", "fortress"], ["Спросить о порядке спасения", "beacon"]]},
		{"who": "Купол", "text": "Перехваты говорят о программе «Крепость»: летающий командный пункт с турелями. Если он есть — он придёт к нам сам.", "only": ["ask_riverbed", "fortress"]},
		{"who": "Купол", "text": "Сбитый включает аварийный маяк. Вертолёт идёт на него, но ему нужно полминуты чистого неба. Услышите маяк — держитесь рядом.", "only": ["ask_riverbed", "beacon"]},
		{"who": "crew", "text": "Понял. Русла, ПВО, пятнадцатая минута.", "trait": true},
	]},
	"hangar_riverbed_after": {"steps": [
		{"who": "Купол", "text": "Первая «Крепость» на склоне. Их штаб в эфире назвал это «не по плану». Хорошо, когда у них есть план."},
		{"who": "Купол", "text": "«Иволга» дома. Её слова: парашют «Грома» видели у старых крепостей. Это единственная ниточка.", "flag": ["rescued", true]},
		{"choice": "lead", "prompt": "Что делаем с ниточкой?", "options": [["Передать разведке — пусть ищут", "recon"], ["Пока молчать — «Барон» не должен знать", "quiet"]], "flag": ["rescued", true]},
		{"who": "Купол", "text": "Передаю. К «Крепостям» полетите с меткой на карте — разведка покажет, где смотреть.", "only": ["lead", "recon"]},
		{"who": "Купол", "text": "Молчим. «Барон» в эфире болтлив — пусть думает, что мы ничего не знаем.", "only": ["lead", "quiet"]},
		{"who": "Купол", "text": "Вертолёт ушёл без пилота. О «Громе» по-прежнему ничего — разведка смотрит на старые крепости наугад.", "flag": ["rescued", false]},
		{"who": "crew", "text": "Тогда дальше. К крепостям.", "trait": true},
	]},
	"hangar_pass_after": {"steps": [
		{"who": "Купол", "text": "Колонна прошла, перевал наш. «Барон» в эфире назвал ваш позывной — теперь это личное."},
		{"who": "crew", "text": "Пусть называет. Хоть познакомимся.", "trait": true},
		{"who": "Купол", "text": "Их асы прыгают с парашютом и назавтра снова в строю. У компании хорошие спасатели."},
		{"who": "Купол", "text": "Разведка: в сухих руслах за перевалом копают позиции. По чертежу. Это ваша следующая операция."},
	]},
}

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
