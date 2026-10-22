class_name Demo
extends RefCounted
## Демо для Steam Next Fest (M-07, решение Kanta 19.10.2026, `docs/demo-next-fest.md`, вариант А):
## Нагорье, операции «Перевал» и «Сухое русло», три класса только на самолётах ур. 1, ангар с потолком.
## Закрытое видно с пометкой «в полной игре». Финал демо — первый проход «Сухого русла»: экран «Конец демо»
## с кнопкой списка желаемого. Сохранения те же, что у полной игры (user://, то же имя проекта) — прогресс переносится.
## Включается признаком экспорта `demo` (пресет «Windows Demo») или ключом `--demo` при запуске.

## Номер игры в Steam (не демо) — вписать, когда откроется страница; пока 0 — кнопка ведёт на сайт
const STEAM_APP_ID := 0
const SITE_URL := "https://flakheaven.com"

const OPS := ["pass", "riverbed"]   # открытые операции (id из Campaign.OPS)
const FINAL_OP := "riverbed"        # первый проход — конец демо
const NODE_MAX := 2                 # узлы самолёта — до ур. 2
const TIER_MAX := 1                 # ветки оружия — только ступень 1
const CREW_MAX := 5                 # экипаж — до ур. 5 (второй слот навыка)

const LOCKED := "в полной игре"
## Что открывает первый проход операции — в демо вместо Campaign.OPS[i]["opens"]
const OPENS := {
	"pass": ["Операция 2 «Сухое русло»", "Самолёт ур. 2 — в полной игре"],
	"riverbed": ["Конец демо: операции 3–4, Архипелаг Таласора и самолёты ур. 2 — в полной игре"],
}

static var on := OS.has_feature("demo") or OS.get_cmdline_user_args().has("--demo")
## Экран «Конец демо» поверх итогов вылета
static var end_open := false


static func op_ok(i: int) -> bool:
	return not on or OPS.has(String(Campaign.OPS[i]["id"]))


static func biome_ok(b: String) -> bool:
	return not on or b == Biome.HIGHLAND


static func node_cap() -> int:
	return NODE_MAX if on else 5


static func tier_cap() -> int:
	return TIER_MAX if on else 3


static func crew_cap() -> int:
	return CREW_MAX if on else Profile.CREW_CUM.size()


static func opens(o: Dictionary) -> Array:
	return OPENS.get(String(o["id"]), o["opens"]) if on else o["opens"]


## Версия для меню и отчёта: «3.5-s8 · демо»
static func tag(build: String) -> String:
	return build + ("-demo" if on else "")


## Campaign.on_evac: засчитан первый проход финальной операции демо
static func on_op_cleared(id: String) -> void:
	if on and id == FINAL_OP:
		end_open = true


## Кнопка «В список желаемого»: страница игры в клиенте Steam, пока её нет — сайт игры
static func open_store() -> void:
	if STEAM_APP_ID > 0:
		OS.shell_open("steam://store/%d" % STEAM_APP_ID)
	else:
		OS.shell_open(SITE_URL)
