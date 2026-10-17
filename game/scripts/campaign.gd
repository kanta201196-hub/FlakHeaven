class_name Campaign
extends RefCounted
## U-05: кампания Нагорья Шахрисанг — 4 операции по порядку, у каждой брифинг, сложность и условие прохождения
## (решение Kanta 17.10.2026, вариант А «Поколения техники», `docs/progression/generations-and-campaign.md`).
## Первый проход операции открывает следующую и даёт запчасти; пройденные можно повторять ради добычи.
## Прогресс — user://campaign.cfg (секции «done», «state»).

const PATH := "user://campaign.cfg"

## Сложности по концепту v1: прочность и урон врагов, плотность волн, награда (запчасти)
const DIFF := [
	{"title": "Учебный", "hp": 1.0, "dmg": 1.0, "dens": 1.0, "reward": 1.0},
	{"title": "Боевой", "hp": 1.4, "dmg": 1.2, "dens": 1.2, "reward": 1.3},
	{"title": "Тяжёлый", "hp": 2.0, "dmg": 1.4, "dens": 1.4, "reward": 1.7},
	{"title": "Ас", "hp": 2.8, "dmg": 1.6, "dens": 1.6, "reward": 2.2},
]

## need: что нужно для прохождения кроме эвакуации — "time" (15:00), "fortress", "baron"
const OPS := [
	{"id": "pass", "title": "Перевал", "diff": 0, "need": ["time"], "parts": 300,
		"brief": "Колонна снабжения идёт через перевал Шахрисанг. Держите небо над дорогой 15 минут, потом уходите на базу через ворота эвакуации.",
		"task": "Продержаться до 15:00 и улететь через ворота",
		"hud": "колонна пройдёт через",
		"opens": ["Операция 2 «Сухое русло»", "Покупка самолёта ур. 2 в ангаре: тяжёлый подвес и рельсотрон"]},
	{"id": "riverbed", "title": "Сухое русло", "diff": 1, "need": ["fortress"], "parts": 500,
		"brief": "Противник ставит ПВО в руслах рек. К 15-й минуте подойдёт «Крепость» — тяжёлый самолёт-штаб. Разведка видела аса с позывным «Барон».",
		"task": "Сбить «Крепость» (появится в 15:00) и улететь",
		"hud": "«Крепость» через",
		"opens": ["Операция 3 «Крепости»", "ЭМИ-заряд для тяжёлого подвеса", "Ступень 3 веток оружия для самолёта ур. 2 (готовится)"]},
	{"id": "forts", "title": "Крепости", "diff": 2, "need": ["baron", "fortress"], "parts": 800,
		"brief": "Старые горные крепости стали опорными пунктами. «Барон» ищет вас лично: примите дуэль и не дайте ему уйти. В 15:00 — снова «Крепость».",
		"task": "Сбить «Барона» в дуэли и «Крепость», затем улететь",
		"hud": "«Крепость» через",
		"opens": ["Операция 4 «Небо над Шахрисангом»", "Лазер «Луч» и плазменная бомба для тяжёлого подвеса"]},
	{"id": "sky", "title": "Небо над Шахрисангом", "diff": 3, "need": ["fortress"], "parts": 1200,
		"brief": "Последний рывок: всё, что осталось у противника, поднято в воздух. Сбейте «Крепость» и возвращайтесь.",
		"task": "Сбить «Крепость» на сложности «Ас» и улететь",
		"hud": "«Крепость» через",
		"opens": ["Второй биом (готовится)"]},
]

const NEED_TEXT := {"time": "продержаться до 15:00", "fortress": "сбить «Крепость»", "baron": "сбить «Барона» в дуэли"}

## Выбранная операция (на следующий вылет и в текущем вылете)
static var sel := -1
static var _cfg: ConfigFile = null


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	_cfg.load(PATH)
	if sel < 0:
		sel = clampi(int(_cfg.get_value("state", "sel", 0)), 0, unlocked() - 1)


static func _save() -> void:
	_cfg.save(PATH)


static func cleared(i: int) -> bool:
	_load()
	return bool(_cfg.get_value("done", OPS[i]["id"], false))


## Сколько операций открыто (первая — всегда)
static func unlocked() -> int:
	_load()
	var n := 1
	for i in OPS.size() - 1:
		if bool(_cfg.get_value("done", OPS[i]["id"], false)):
			n = i + 2
	return n


## Номер выбранной операции (0–3)
static func index() -> int:
	_load()
	return sel


static func select(i: int) -> void:
	_load()
	if i < 0 or i >= unlocked():
		return
	sel = i
	_cfg.set_value("state", "sel", i)
	_save()


static func op() -> Dictionary:
	_load()
	return OPS[sel]


static func diff() -> Dictionary:
	return DIFF[int(op()["diff"])]


## Множитель сложности текущей операции: "hp", "dmg", "dens", "reward"
static func k(key: String) -> float:
	return float(diff()[key])


## В операциях 2–4 ас-соперник в дуэли — «Барон»
static func baron() -> bool:
	return index() >= 1


static func baron_met() -> int:
	_load()
	return int(_cfg.get_value("state", "baron_met", 0))


static func on_baron_met() -> void:
	_cfg.set_value("state", "baron_met", baron_met() + 1)
	_save()


## Выполнено ли условие need в вылете (flags — Main.op_flags)
static func need_done(need: String, run_time: float, flags: Dictionary) -> bool:
	if need == "time":
		return run_time >= 900.0
	return bool(flags.get(need, false))


static func goal_done(run_time: float, flags: Dictionary) -> bool:
	for n in op()["need"]:
		if not need_done(n, run_time, flags):
			return false
	return true


## Итог операции без начисления (гибель или до засчёта): название, выполнено ли, чего не хватило
static func result_base(run_time: float, flags: Dictionary) -> Dictionary:
	var o := op()
	var miss: Array = []
	for n in o["need"]:
		if not need_done(n, run_time, flags):
			miss.append(NEED_TEXT[n])
	return {"title": o["title"], "n": index() + 1, "done": miss.is_empty(), "miss": miss, "first": false, "parts": 0, "opens": []}


## Конец вылета эвакуацией: засчитать операцию. Возвращает {"done", "first", "parts", "opens"}
static func on_evac(run_time: float, flags: Dictionary) -> Dictionary:
	var o := op()
	var out := result_base(run_time, flags)
	if out["done"] and not cleared(sel):
		_cfg.set_value("done", o["id"], true)
		out["first"] = true
		out["parts"] = int(o["parts"])
		out["opens"] = o["opens"]
		# следующая операция становится выбранной
		if sel + 1 < OPS.size():
			sel += 1
			_cfg.set_value("state", "sel", sel)
		_save()
	return out


static func wipe() -> void:
	_load()
	_cfg.clear()
	_save()
	sel = 0


## Отладка и скриншоты: открыть все операции
static func debug_open_all() -> void:
	_load()
	for i in OPS.size() - 1:
		_cfg.set_value("done", OPS[i]["id"], true)
	_save()
