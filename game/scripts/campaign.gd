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
		"brief": "Неделю назад над перевалом пропал ведущий звена «Гром». Последнее, что слышали, — позывной «Барон». Колонна снабжения идёт через перевал Шахрисанг. Держите небо над дорогой 15 минут, потом уходите на базу через ворота эвакуации.",
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
		"brief": "Последний рывок: всё, что осталось у противника, поднято в воздух. «Гром» догонит звено на третьей минуте — ему дали первый исправный самолёт. Сбейте «Крепость» и возвращайтесь.",
		"task": "Сбить «Крепость» на сложности «Ас» и улететь",
		"hud": "«Крепость» через",
		"opens": ["Второй биом (готовится)"]},
	# Второй биом «Архипелаг Таласора» (тред «Второй биом», 18.10.2026): своя цепочка операций, первая открыта сразу
	{"id": "strait", "biome": "archipelago", "title": "Пролив", "diff": 0, "need": ["time"], "parts": 400,
		"brief": "Морской конвой противника идёт проливом между островами Таласоры. Береговые батареи и катера ПВО прикрывают фарватер. Держите небо 15 минут и уходите через ворота эвакуации.",
		"task": "Продержаться до 15:00 и улететь через ворота",
		"hud": "конвой пройдёт пролив через",
		"opens": ["Операция «Маяк»"]},
	{"id": "lighthouse", "biome": "archipelago", "title": "Маяк", "diff": 1, "need": ["time"], "parts": 600,
		"brief": "На мысах у входа в бухты противник поставил посты наблюдения и батареи. Над водой ходят экранопланы «Крачка». Продержитесь до 15:00.",
		"task": "Продержаться до 15:00 и улететь",
		"hud": "до эвакуации",
		"opens": ["Операция «Затонувший порт»"]},
	{"id": "port", "biome": "archipelago", "title": "Затонувший порт", "diff": 2, "need": ["time"], "parts": 900,
		"brief": "Порт в глубине залива — склад и ремонтная база флота противника. Его прикрывает крейсер «Сторож». Продержитесь до 15:00.",
		"task": "Продержаться до 15:00 и улететь",
		"hud": "до эвакуации",
		"opens": ["Операция «Левиафан»"]},
	{"id": "leviathan", "biome": "archipelago", "title": "Левиафан", "diff": 3, "need": ["time"], "parts": 1400,
		"brief": "В открытом море — «Левиафан», корабль-носитель противника. Всё, что у него есть, поднято в воздух.",
		"task": "Продержаться до 15:00 на сложности «Ас» и улететь",
		"hud": "до эвакуации",
		"opens": []},
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
		sel = clampi(int(_cfg.get_value("state", "sel", 0)), 0, OPS.size() - 1)
		if not is_open(sel):
			sel = 0


static func _save() -> void:
	_cfg.save(PATH)


static func cleared(i: int) -> bool:
	_load()
	if not Demo.op_ok(i):   # демо: операции полной игры не показываются пройденными (сохранение не трогаем)
		return false
	return bool(_cfg.get_value("done", OPS[i]["id"], false))


## Биом операции i (Biome.HIGHLAND, если не указан)
static func biome_of(i: int) -> String:
	return String(OPS[i].get("biome", Biome.HIGHLAND))


## Операции биома по порядку (номера в OPS)
static func ops_of(biome: String) -> Array:
	var r := []
	for i in OPS.size():
		if biome_of(i) == biome:
			r.append(i)
	return r


## Открыта ли операция: первая в своём биоме — всегда, дальше — после прохождения предыдущей того же биома
static func is_open(i: int) -> bool:
	_load()
	if not Demo.op_ok(i):
		return false
	var ids := ops_of(biome_of(i))
	var k := ids.find(i)
	return k <= 0 or cleared(ids[k - 1])


## Сколько операций открыто подряд в биоме выбранной операции (для старого кода с номерами 0…n−1)
static func unlocked() -> int:
	_load()
	var n := 0
	for i in OPS.size():
		if is_open(i):
			n = i + 1
	return n


## Номер операции в своём биоме, с 1 (для подписей «Операция N»)
static func num(i := -1) -> int:
	if i < 0:
		i = index()
	return ops_of(biome_of(i)).find(i) + 1


## Номер выбранной операции (0–3)
static func index() -> int:
	_load()
	return sel


static func select(i: int) -> void:
	_load()
	if i < 0 or i >= OPS.size() or not is_open(i):
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


## В операциях 2–4 Нагорья ас-соперник в дуэли — «Барон»
static func baron() -> bool:
	return biome_of(index()) == Biome.HIGHLAND and index() >= 1


static func baron_met() -> int:
	_load()
	return int(_cfg.get_value("state", "baron_met", 0))


static func on_baron_met() -> void:
	_cfg.set_value("state", "baron_met", baron_met() + 1)
	_save()


## EX-09: флаги сюжетной линии «Где Гром?» (rescued, grom_free)
static func flag(key: String) -> bool:
	_load()
	return bool(_cfg.get_value("story", key, false))


static func set_flag(key: String) -> void:
	_load()
	_cfg.set_value("story", key, true)
	_save()


## Highlands story (plan step 1). A scene id is "<intro|outro|hangar>_<op id>" (e.g. "intro_pass", "hangar_riverbed_after").
## Whether the scene plays now: the «Заставки» setting against the seen flag (`StoryFlags.scene_due`).
static func story_scene_due(scene: String, mode: int) -> bool:
	return StoryFlags.scene_due(mode, flag("seen_" + scene))


## Remember that a scene was shown (the «при первом прохождении» setting skips it next time).
static func mark_story_scene(scene: String) -> void:
	set_flag("seen_" + scene)


## The option the player picked in a hangar dialogue ("" — not asked yet). Choices change text and presentation only.
static func story_choice(id: String) -> String:
	_load()
	return String(_cfg.get_value("story", "choice_" + id, ""))


static func set_story_choice(id: String, option: String) -> void:
	_load()
	_cfg.set_value("story", "choice_" + id, option)
	_save()


## How many sorties the player has already met a recurring enemy pilot in («Почтальон», «Сквозняк», «Граф»);
## picks their «again» line (`StoryFlags.line_index`). «Барон» keeps his own counter (`baron_met`).
static func met(callsign: String) -> int:
	_load()
	return int(_cfg.get_value("story", "met_" + callsign, 0))


static func on_met(callsign: String) -> void:
	_load()
	_cfg.set_value("story", "met_" + callsign, met(callsign) + 1)
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
		out["opens"] = Demo.opens(o)
		Demo.on_op_cleared(String(o["id"]))
		# тест 3.5-s5: следующая операция сама не выбирается — в меню она отмечена «новая, сложнее».
		# Раньше после «Перевала» вылет молча шёл на «Боевом», и тест баланса шёл не на той сложности.
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
