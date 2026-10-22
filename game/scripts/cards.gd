class_name Cards
## Карточки при повышении уровня: выбор 1 из 4.
## У каждой карточки — редкость (5 уровней), она умножает силу эффекта.
## Игрок может: перебросить выбор (ограниченно), закрепить карточку до следующего выбора,
## исключить карточку из выпадения до конца вылета (ограниченно).
## 3.1: теги и очки тегов, связки на тегах, эволюции, типы ведомых, доводка навыка I/II/III, резерв v1.

const RARITY := [
	{"name": "Базовая", "color": Color(0.72, 0.74, 0.78), "k": 1.0, "w": 50.0},
	{"name": "Обычная", "color": Color(0.45, 0.9, 0.45), "k": 1.4, "w": 28.0},
	{"name": "Уникальная", "color": Color(0.4, 0.65, 1.0), "k": 1.8, "w": 14.0},
	{"name": "Исключительная", "color": Color(0.75, 0.45, 1.0), "k": 2.3, "w": 6.0},
	{"name": "Легендарная", "color": Color(1.0, 0.6, 0.15), "k": 3.0, "w": 2.0},
]
const EVO_COLOR := Color(1.0, 0.95, 0.75)


## Правки 15–16 (тест 3.5): взятые карточки сводкой — одна строка на улучшение с итоговым уровнем
## и лучшей редкостью вместо сырого списка «(1 → 2), (2 → 3)…». Вход — Player.cards_log.
## Выход: [{title, lvl (0 — без уровней), n, r}] в порядке первого взятия.
static func log_summary(log: Array) -> Array:
	var out: Array = []
	var idx := {}
	var re_lvl := RegEx.create_from_string("\\s*\\((\\d+)\\s*→\\s*(\\d+)\\)\\s*$")
	for entry in log:
		var s := String(entry)
		var r := 0
		var b := s.rfind(" [")
		if b >= 0 and s.ends_with("]"):
			var rn := s.substr(b + 2, s.length() - b - 3)
			for i in RARITY.size():
				if RARITY[i]["name"] == rn:
					r = i
			s = s.substr(0, b)
		var lvl := 0
		var mt := re_lvl.search(s)
		if mt != null:
			lvl = int(mt.get_string(2))
			s = s.substr(0, mt.get_start())
		if not idx.has(s):
			idx[s] = out.size()
			out.append({"title": s, "lvl": 0, "n": 0, "r": 0})
		var it: Dictionary = out[idx[s]]
		it["n"] = int(it["n"]) + 1
		it["lvl"] = maxi(int(it["lvl"]), lvl)
		it["r"] = maxi(int(it["r"]), r)
	return out

const MODULES := {
	"armor": {"title": "Бронеплиты", "max": 5, "cat": "Модуль"},
	"engine": {"title": "Форсированный двигатель", "max": 5, "cat": "Модуль"},
	"wing": {"title": "Механизация крыла", "max": 5, "cat": "Модуль"},
	"gun_dmg": {"title": "Бронебойные снаряды", "max": 5, "cat": "Пушка"},
	"gun_rate": {"title": "Облегчённый затвор", "max": 5, "cat": "Пушка"},
	"reload": {"title": "Быстрая перезарядка", "max": 5, "cat": "Подвесы"},
	"seeker": {"title": "Головка наведения «Глазастик»", "max": 3, "cat": "Подвесы"},
	"frag": {"title": "Осколочная рубашка", "max": 5, "cat": "Подвесы"},
	"servo": {"title": "Сервоприводы", "max": 5, "cat": "Подвесы"},
	"warhead": {"title": "Усиленная боевая часть", "max": 5, "cat": "Подвесы"},
	# 3.5: ракеты — модули качества вместо «Спаренных направляющих» и «Кассетной БЧ»
	"msl_head": {"title": "Боевая часть", "max": 5, "cat": "Подвесы"},
	"msl_motor": {"title": "Двигатели ракет", "max": 5, "cat": "Подвесы"},
	"launcher": {"title": "Пусковое устройство", "max": 5, "cat": "Подвесы"},
	"radio": {"title": "Радиостанция «Болтушка»", "max": 5, "cat": "Звено"},
	"magnet": {"title": "Сборщик трофеев", "max": 3, "cat": "Модуль"},
	"roll": {"title": "Уклонение: тренировка", "max": 3, "cat": "Навык"},
	"afterburner": {"title": "Форсаж: тренировка", "max": 3, "cat": "Навык"},
	"skill3": {"title": "", "max": 3, "cat": "Навык"},
	"repair": {"title": "Ремонт в воздухе", "max": 99, "cat": "Ремонт"},
}

## EX-01 (отзывы внешних тестеров, решение Kanta 21.10): за вылет — не больше MOD_SLOTS разных модулей.
## Места заняты — выпадают только улучшения уже взятых. Ремонт и уровни навыка класса места не занимают.
const MOD_SLOTS := 6
const SLOT_FREE := ["repair", "skill3"]
## EX-01: «Быстрая перезарядка» — не ниже этой доли исходной (было 0,3: брали её и забывали о скорострельности)
const RELOAD_FLOOR := 0.6


## Сколько мест модулей занято
static func mod_slots_used(p: Player) -> int:
	var n := 0
	for id in MODULES:
		if not SLOT_FREE.has(id) and int(p.taken.get(id, 0)) > 0:
			n += 1
	return n


## Строка на карточке нового модуля: какое место он займёт
static func slot_hint(p: Player, id: String) -> String:
	if SLOT_FREE.has(id) or int(p.taken.get(id, 0)) > 0:
		return ""
	var n := mod_slots_used(p) + 1
	if n >= MOD_SLOTS:
		return Loc.t("\nЗаймёт последнее место модуля (%d из %d): дальше — только улучшения взятых") % [n, MOD_SLOTS]
	return Loc.t("\nЗаймёт место модуля %d из %d") % [n, MOD_SLOTS]


const CAT_COLORS := {
	"Новое оружие": Color(1.0, 0.75, 0.3),
	"Оружие": Color(1.0, 0.85, 0.5),
	"Модуль": Color(0.55, 0.85, 1.0),
	"Пушка": Color(0.95, 0.95, 0.6),
	"Подвесы": Color(0.75, 0.8, 1.0),
	"Навык": Color(0.7, 1.0, 0.7),
	"Ремонт": Color(0.6, 1.0, 0.8),
	"Звено": Color(0.85, 0.7, 1.0),
	"Связка": Color(1.0, 0.82, 0.25),
	"Модернизация": EVO_COLOR,
	"Мастерство класса": EVO_COLOR,
	"Резерв": Color(0.8, 0.8, 0.75),
}

## 3.2: связки — 3 слота за вылет, цель — «курс» (s3-upgrades-v2). Пороги — по номеру слота.
## w — оружие (любое из списка, ур. ≥ lvl слота); req_mods — сумма взятий модулей ≥ mods слота;
## wingmen — постоянных ведомых ≥ wing слота; tag — главный тег (main), tag2 — второй (second).
const SLOT_COST := [
	{"main": 11, "second": 4, "lvl": 3, "mods": 1, "wing": 1, "s3": 1},
	{"main": 18, "second": 7, "lvl": 4, "mods": 2, "wing": 1, "s3": 2},
	{"main": 25, "second": 10, "lvl": 4, "mods": 3, "wing": 2, "s3": 3},
]
const MAX_SYN := 3

const SYNERGIES := {
	"carousel": {"title": "Карусель", "w": ["aam"], "tag": "missiles", "tag2": "maneuver", "color": Color(1.0, 0.85, 0.3),
		"desc": "Наводящаяся ракета, сбившая цель, сразу пускает новую в ближайшую (до 4 перепусков, каждый +20% урона)",
		"short": "сбитие → новая ракета"},
	"thermobaric": {"title": "Термобарика", "w": ["rockets"], "tag": "blast", "tag2": "missiles", "color": Color(1.0, 0.95, 0.85),
		"desc": "Ракета залпа прилипает и через 0,5 с даёт объёмный взрыв 130 пикс. (урон ×1,5); соседние взрывы сливаются: до ×2",
		"short": "прилипающие ракеты, объёмный взрыв"},
	"salvo": {"title": "Огненный вал", "w": ["rockets"], "tag": "missiles", "tag2": "blast", "color": Color(1.0, 0.45, 0.15),
		"desc": "Каждый 3-й залп ракет — вал: три линии по 5 взрывов в 250 / 450 / 650 пикс. впереди (урон ×1,3)",
		"short": "каждый 3-й залп — три линии огня"},
	"carpet_road": {"title": "Ковровая дорожка", "w": ["bombs"], "tag": "blast", "tag2": "armor", "color": Color(1.0, 0.6, 0.2),
		"desc": "Бомба разбрасывает 4 суббоеприпаса крестом и оставляет горящее пятно на 2,5 с (12 урона/с)",
		"short": "кресты взрывов и огонь"},
	"chain": {"title": "Цепная реакция", "w": ["rockets", "bombs"], "tag": "blast", "tag2": "armor", "color": Color(1.0, 0.3, 0.2),
		"desc": "Враг, убитый взрывом ракеты залпа или бомбы, взрывается сам: 30 урона + 8% его прочности, радиус 90; цепь до 3 звеньев",
		"short": "убитые взрывом рвутся домино"},
	"wolfpack": {"title": "Волчья стая", "wingmen": true, "tag": "wing", "tag2": "missiles", "color": Color(0.75, 0.52, 1.0),
		"desc": "Когда вы пускаете ракеты, каждый ведомый дублирует пуск: 2 ракеты в вашу цель (×0,6 урона)",
		"short": "звено повторяет ваши пуски"},
	"warm": {"title": "Тёплая компания", "wingmen": true, "tag": "wing", "tag2": "blast", "color": Color(1.0, 0.55, 0.35),
		"desc": "Раз в 7 с звено выходит вперёд и стелет ряд из 5 бомб поперёк пути самолёта (45 урона, 100 пикс.)",
		"short": "звено стелет огонь впереди"},
	"mirror": {"title": "Зеркало", "w": ["flares"], "tag": "maneuver", "tag2": "missiles", "color": Color(0.3, 0.95, 0.85),
		"desc": "Уведённая ловушкой ракета разворачивается и бьёт ближайшего врага (80 урона, взрыв 90); уклонение отстреливает 6 ловушек",
		"short": "вражеские ракеты летят в своих"},
	"hedgehog": {"title": "Стальной ёж", "w": ["turret"], "tag": "turrets", "tag2": "blast", "color": Color(0.3, 0.85, 0.8),
		"desc": "Раз в 5 с каждая турель выпускает 3 мини-ракеты по разным целям (22, взрыв 45); турели раз в 3 с стреляют по ракете (сбивают в 55%)",
		"short": "залп мини-ракет из турелей"},
	"gunner": {"title": "Пушкарь", "w": ["gunpod"], "tag": "kinetic", "tag2": "blast", "color": Color(0.95, 0.85, 0.3),
		"desc": "Каждый 6-й снаряд гондолы — фугасный (урон ×4, взрыв 70); все пули гондолы пробивают 1 цель",
		"short": "фугасные снаряды гондолы"},
	"roller": {"title": "Каток", "req_mods": ["armor"], "tag": "armor", "tag2": "blast", "color": Color(0.8, 0.82, 0.88),
		"desc": "Получив удар (раз в 2,5 с), самолёт отвечает кольцом из 10 ракет (18, взрыв 60); ниже 40% прочности — 16 ракет раз в 1,5 с",
		"short": "удар по вам → кольцо ракет"},
	"jetwash": {"title": "Реактивный след", "req_mods": ["roll", "afterburner"], "tag": "maneuver", "tag2": "blast", "color": Color(0.5, 0.8, 1.0),
		"desc": "При уклонении и форсаже за самолётом каждые 50 пикс. остаётся заряд: через 0,4 с взрыв 70 пикс., 30 урона",
		"short": "огненная дорожка на манёврах"},
}


static func _has_weapon(p: Player, w: String, lvl: int) -> bool:
	for g in p.groups:
		if (g as Hardpoint).weapon == w and (g as Hardpoint).level >= lvl:
			return true
	return false


static func _equipped(p: Player, w: String) -> bool:
	return _has_weapon(p, w, 1)


static func _wlevel(p: Player, ws: Array) -> int:
	var lv := 0
	for g in p.groups:
		if ws.has((g as Hardpoint).weapon):
			lv = maxi(lv, (g as Hardpoint).level)
	return lv


## Описание связки по id (оружейная или связка навыка «s_…»)
static func syn_def(p: Player, id: String) -> Dictionary:
	if SYNERGIES.has(id):
		return SYNERGIES[id]
	for sk in PlaneClasses.SKILL3:
		var ss: Dictionary = PlaneClasses.SKILL3[sk]["syn"]
		if ss["id"] == id:
			var d := ss.duplicate()
			d["skill"] = sk
			d["tag"] = PlaneClasses.SKILL3[sk]["tags"][0]
			d["color"] = Color(0.6, 1.0, 0.6)
			d["short"] = ss["desc"]
			return d
	return {}


static func slot_cost(p: Player) -> Dictionary:
	return SLOT_COST[mini(p.syn.size(), MAX_SYN - 1)]


## Условия связки для текущего слота: [[текст, выполнено, есть, нужно], …]
static func cond_list(p: Player, id: String) -> Array:
	var s := syn_def(p, id)
	var c := slot_cost(p)
	var out: Array = []
	if s.is_empty():
		return out
	var main := p.tag(s["tag"])
	out.append(["%s %d/%d" % [Prog.tag_title(s["tag"]), main, int(c["main"])], main >= int(c["main"]), main, int(c["main"])])
	if s.has("skill"):
		var lv := p.s3_lvl()
		out.append([Loc.t("уровень навыка %d/%d") % [lv, int(c["s3"])], lv >= int(c["s3"]), lv, int(c["s3"])])
		return out
	if s.has("tag2"):
		var t2 := p.tag(s["tag2"])
		out.append(["%s %d/%d" % [Prog.tag_title(s["tag2"]), t2, int(c["second"])], t2 >= int(c["second"]), t2, int(c["second"])])
	if s.has("w"):
		var lv2 := _wlevel(p, s["w"])
		var wn := "/".join(PackedStringArray((s["w"] as Array).map(func(x): return Loc.t(String(Weapons.DEFS[x]["short"])))))
		out.append([Loc.t("%s ур. %d/%d") % [wn, lv2, int(c["lvl"])], lv2 >= int(c["lvl"]), lv2, int(c["lvl"])])
	if s.has("req_mods"):
		var n := 0
		var names := PackedStringArray()
		for m in s["req_mods"]:
			n += int(p.taken.get(m, 0))
			names.append(MODULES[m]["title"])
		out.append(["%s ×%d/%d" % [" + ".join(names), n, int(c["mods"])], n >= int(c["mods"]), n, int(c["mods"])])
	if s.get("wingmen", false):
		var wn2 := p.permanent_wingmen()
		out.append([Loc.t("ведомые %d/%d") % [wn2, int(c["wing"])], wn2 >= int(c["wing"]), wn2, int(c["wing"])])
	return out


static func conds_ok(conds: Array) -> bool:
	for c in conds:
		if not c[1]:
			return false
	return true


## Сколько карточек ещё нужно до связки (оценка для экрана курса)
static func cards_left(conds: Array) -> int:
	var n := 0
	for c in conds:
		n = maxi(n, int(c[3]) - int(c[2]))
	return n


static func course_ready(p: Player) -> bool:
	return p.has_course() and p.syn.size() < MAX_SYN and not p.syn.has(p.course) and conds_ok(cond_list(p, p.course))


static func need_course(p: Player) -> bool:
	return p.course == "" and p.syn.size() < MAX_SYN and p.picks >= 2


## Связки, доступные классу сейчас (не открыты; оружие стоит или его можно поставить)
static func _available(p: Player) -> Array:
	var out: Array = []
	var free_group := false
	for g in p.groups:
		if not (g as Hardpoint).builtin and (g as Hardpoint).is_empty():
			free_group = true
	for id in SYNERGIES:
		if p.syn.has(id):
			continue
		var s: Dictionary = SYNERGIES[id]
		var ok := true
		if s.has("w"):
			if not (s["w"] as Array).any(func(w): return Weapons.in_game(w) and PlaneClasses.allows(p.cls_id, w)):
				continue
			ok = _wlevel(p, s["w"]) > 0 or (free_group and not (s["w"] as Array).has("turret"))
		if s.get("wingmen", false):
			ok = int(p.cls["wingmen"]) > 0 or p.permanent_wingmen() > 0
		if ok:
			out.append(id)
	return out


## Экран «Выбор курса»: 3 варианта — по оружию, связка навыка, «новый путь»
static func course_options(p: Player) -> Array:
	var avail := _available(p)
	var have: Array = avail.filter(func(id):
		var s: Dictionary = SYNERGIES[id]
		if s.has("w"):
			return _wlevel(p, s["w"]) > 0
		if s.get("wingmen", false):
			return p.permanent_wingmen() > 0
		return true)
	have.sort_custom(func(a, b): return _progress(cond_list(p, a)) > _progress(cond_list(p, b)))
	var out: Array = []
	if not have.is_empty():
		out.append(have[0])
	var sid: String = PlaneClasses.SKILL3[p.skill3]["syn"]["id"]
	# 3.4: «Под одним зонтом» без живых постоянных ведомых бесполезна — не предлагаем курсом
	if sid == "s_shelter" and p.permanent_wingmen() == 0:
		Main.I.tele.add("course_shelter_skipped")
	elif not p.syn.has(sid):
		out.append(sid)
	var rest: Array = avail.filter(func(id): return not out.has(id))
	rest.shuffle()
	var fresh: Array = rest.filter(func(id): return not have.has(id))
	for id in fresh + rest + have:
		if out.size() >= 3:
			break
		if not out.has(id):
			out.append(id)
	return out


static func _progress(conds: Array) -> float:
	var k := 0.0
	for c in conds:
		k += clampf(float(c[2]) / maxf(float(c[3]), 1.0), 0.0, 1.0)
	return k / maxf(conds.size(), 1)


## Карточка двигает курс: добавляет очко его тегов (пока не выполнены) или поднимает оружие/модули/ведомых курса
static func advances_course(p: Player, card: Dictionary) -> bool:
	if not p.has_course() or card["kind"] in ["synergy", "skill_syn", "evolution", "reserve"]:
		return false
	var s := syn_def(p, p.course)
	var c := slot_cost(p)
	var tags := Prog.card_tags(p, card)
	if tags.has(s["tag"]) and p.tag(s["tag"]) < int(c["main"]):
		return true
	if s.has("tag2") and tags.has(s["tag2"]) and p.tag(s["tag2"]) < int(c["second"]):
		return true
	if s.has("skill") and card["kind"] == "module" and card["id"] == "skill3":
		return true
	if s.has("w"):
		if card["kind"] == "weapon_new" and (s["w"] as Array).has(card["weapon"]):
			return true
		if card["kind"] == "weapon_up" and (s["w"] as Array).has((p.groups[int(card["group"])] as Hardpoint).weapon) and _wlevel(p, s["w"]) < int(c["lvl"]):
			return true
	if s.has("req_mods") and card["kind"] == "module" and (s["req_mods"] as Array).has(card["id"]):
		return true
	if s.get("wingmen", false) and card["kind"] == "wing_new":
		return true
	return false


## Строка о курсе для карточки
static func course_hint(p: Player, card: Dictionary) -> String:
	if not advances_course(p, card):
		return ""
	var s := syn_def(p, p.course)
	var c := slot_cost(p)
	var tags := Prog.card_tags(p, card)
	if tags.has(s["tag"]):
		return Loc.t("\n▲ К связке «%s»: %s %d → %d (из %d)") % [Loc.t(s["title"]), Loc.t(Prog.tag_title(s["tag"])), p.tag(s["tag"]), p.tag(s["tag"]) + 1, int(c["main"])]
	return Loc.t("\n▲ К связке «%s»") % Loc.t(s["title"])


const NEW_WEAPON_LEVEL := [1, 1, 2, 2, 3]
const UP_LEVELS := [1, 1, 1, 2, 2]


static func roll_rarity(level: int, min_r := 0) -> int:
	return maxi(_roll(level), min_r)


static func _roll(level: int) -> int:
	# Чем выше уровень, тем чаще редкие (немного)
	var ws: Array = []
	var total := 0.0
	for i in RARITY.size():
		var w: float = float(RARITY[i]["w"]) * (1.0 + level * 0.03 * i)
		ws.append(w)
		total += w
	var r := randf() * total
	for i in ws.size():
		r -= float(ws[i])
		if r <= 0.0:
			return i
	return 0


static func _pct(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


## Текст эффекта модуля с учётом редкости
static func module_desc(p: Player, id: String, k: float) -> String:
	match id:
		"armor":
			return Loc.t("+%s прочности (и сразу ремонт на эту величину)") % _pct(0.2 * k)
		"engine":
			return Loc.t("+%s скорости") % _pct(0.06 * k)
		"wing":
			return Loc.t("+%s скорости разворота") % _pct(0.08 * k)
		"gun_dmg":
			return Loc.t("Пушка: +%s урона") % _pct(0.15 * k)
		"gun_rate":
			return Loc.t("Пушка: +%s скорострельности") % _pct(0.15 * k)
		"reload":
			return Loc.t("Все подвесы и турели: −%s перезарядки") % _pct(0.1 * k)
		"seeker":
			match int(p.taken.get("seeker", 0)):
				0:
					return "Ракета, потерявшая цель, наводится на новую (600 пикс., 1 раз). Без головки наведения — летит прямо и самоликвидируется"
				1:
					return "Перенацеливание: поиск 900 пикс., до 2 раз"
				_:
					return "После сбития наводящаяся ракета ищет следующую цель (1 раз); наводящиеся ракеты бьют и наземные цели (×1,5)"
		"frag":
			return Loc.t("+%s радиуса всех взрывов") % _pct(0.1 * k)
		"servo":
			return Loc.t("Гондола и турели: +%s темпа, +%s дальности; турели наводятся на %s быстрее") % [_pct(0.1 * k), _pct(0.06 * k), _pct(0.25 * k)]
		"warhead":
			return Loc.t("+%s урона всех взрывов (залпы ракет, бомбы, осколки ракет, навыки)") % _pct(0.12 * k)
		"msl_head":
			var s := Loc.t("Ракеты: +%s урона, +%s радиуса разрыва") % [_pct(0.15 * k), _pct(0.08 * k)]
			if int(p.taken.get("msl_head", 0)) + 1 == 3:
				s += "; разделяющаяся боевая часть: ракета при попадании даёт 3 суббоеприпаса"
			return s
		"msl_motor":
			return Loc.t("Ракеты: +%s скорости, +%s дальности захвата") % [_pct(0.12 * k), _pct(0.08 * k)]
		"launcher":
			return Loc.t("Все ракеты: −%s перезарядки") % _pct(0.1 * k)
		"radio":
			return Loc.t("Ведомые: +%s урона, +%s прочности") % [_pct(0.2 * k), _pct(0.15 * k)]
		"magnet":
			return Loc.t("+%s радиуса подбора опыта") % _pct(0.35 * k)
		"roll":
			if not p.has_roll():
				return Loc.t("Залп ловушек: −%.1f с перезарядки") % [1.0 * k]
			return Loc.t("Уклонение: −%.1f с перезарядки, +%.2f с неуязвимости") % [1.0 * k, 0.15 * k]
		"afterburner":
			return Loc.t("Форсаж: +%.1f с длительности, −%.1f с перезарядки") % [1.0 * k, 2.0 * k]
		"skill3":
			var d: Dictionary = PlaneClasses.SKILL3[p.skill3]
			var nl := int(p.mods["s3_lvl"]) + 1
			return "%s %s: %s" % [Loc.t(d["title"]), Prog.ROMAN[nl], Loc.t(d["lv"][nl])]
		"repair":
			return Loc.t("Восстановить %s прочности") % _pct(minf(0.4 * k, 1.0))
	return ""


## Правка 9 (3.5-s4): строка «было → станет» для модуля — сколько сейчас и сколько будет после карточки
static func module_delta(p: Player, id: String, k: float) -> String:
	var mul := {"engine": ["speed", 0.06, "Скорость"], "wing": ["turn", 0.08, "Разворот"],
		"gun_dmg": ["gun_dmg", 0.15, "Урон пушки"], "gun_rate": ["gun_rate", 0.15, "Темп пушки"],
		"frag": ["blast_r", 0.1, "Радиус взрывов"], "warhead": ["blast_dmg", 0.12, "Урон взрывов"],
		"msl_head": ["missile_dmg", 0.15, "Урон ракет"], "msl_motor": ["missile_spd", 0.12, "Скорость ракет"],
		"radio": ["wing_dmg", 0.2, "Урон ведомых"], "magnet": ["pickup", 0.35, "Радиус подбора"],
		"servo": ["servo_rate", 0.1, "Темп гондолы и турелей"]}
	if mul.has(id):
		var d: Array = mul[id]
		var v := float(p.mods.get(d[0], 1.0))
		return "%s: %s → %s" % [d[2], _pct(v), _pct(v * (1.0 + float(d[1]) * k))]
	match id:
		"armor":
			return Loc.t("Прочность: %d → %d") % [int(p.max_hp), int(p.max_hp + float(p.cls["hp"]) * 0.2 * k)]
		"reload":
			var r := float(p.mods["hp_cd"])
			return Loc.t("Перезарядка подвесов: %s → %s (предел %s)") % [_pct(r), _pct(maxf(RELOAD_FLOOR, r * (1.0 - 0.1 * k))), _pct(RELOAD_FLOOR)]
		"launcher":
			var r2 := float(p.mods.get("msl_cd", 1.0))
			return Loc.t("Перезарядка ракет: %s → %s") % [_pct(r2), _pct(maxf(0.4, r2 * (1.0 - 0.1 * k)))]
		"roll":
			if not p.has_roll():
				return ""
			var t := Tuning.g("roll_time") + float(p.mods["roll_time"])
			return Loc.t("Неуязвимость уклонения: %.2f → %.2f с") % [t, t + 0.15 * k]
		"afterburner":
			var a := Tuning.g("afterburner_time") + float(p.mods["ab_time"])
			return Loc.t("Форсаж: %.1f → %.1f с") % [a, a + 1.0 * k]
		"repair":
			return Loc.t("Прочность: %d → %d из %d") % [int(p.hp), int(minf(p.max_hp, p.hp + p.max_hp * minf(0.4 * k, 1.0))), int(p.max_hp)]
	return ""


## 3.5 (правка 24): больше двух постоянных ведомых не бывает — третий делал звено слишком сильным
const WING_MAX := 2


## Лимит ведомых класса (правка 3.5-s4, Kanta: «Оса» — 1, «Грач» и «Кит» — по 2); связки лимит больше не поднимают
static func wing_limit(p: Player) -> int:
	return mini(WING_MAX, int(p.cls["wingmen"]))


## Все возможные карточки сейчас: [вес, карточка без редкости]
static func _candidates(p: Player, banned: Dictionary) -> Array:
	var cands: Array = []
	var equipped: Array = []
	for g in p.groups:
		if not g.is_empty():
			equipped.append(g.weapon)
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		if g.builtin or not g.is_empty():
			continue
		# U-06/U-08: на тяжёлый подвес — только экспериментальное оружие, открытое кампанией; на остальные — обычное
		for w in (Weapons.EXP.filter(func(x): return Weapons.exp_open(x)) if g.heavy else Weapons.POOL.filter(func(x): return PlaneClasses.allows(p.cls_id, x))):
			if equipped.has(w) or banned.has("w:" + w):
				continue
			cands.append([1.4, {"id": "new_%s_%d" % [w, gi], "ban": "w:" + w, "kind": "weapon_new", "weapon": w, "group": gi, "cat": "Новое оружие",
				"title": Weapons.title(w)}])
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		if g.is_empty() or g.level >= Weapons.MAX_LEVEL or banned.has("up:%d" % gi):
			continue
		# фишка 1 (Kanta 18.10): в первых трёх выборах улучшение оружия-особенности класса выпадает втрое чаще
		var uw := 9.0 if p.picks < 3 and g.weapon == PlaneClasses.signature(p.cls_id) else 3.0
		cands.append([uw, {"id": "up_%d" % gi, "ban": "up:%d" % gi, "kind": "weapon_up", "group": gi, "cat": "Оружие",
			"title": "%s: улучшение" % Weapons.title(g.weapon)}])
	for id in MODULES:
		if banned.has(id):
			continue
		var m: Dictionary = MODULES[id]
		var taken := int(p.taken.get(id, 0))
		if taken >= int(m["max"]):
			continue
		if taken == 0 and not SLOT_FREE.has(id) and mod_slots_used(p) >= MOD_SLOTS:
			continue
		if id == "reload" and float(p.mods["hp_cd"]) <= RELOAD_FLOOR + 0.001:
			continue
		var w := 1.5
		var title: String = m["title"]
		match id:
			"repair":
				if p.hp > p.max_hp * 0.75:
					continue
				w = 2.5
			"radio":
				if p.wingmen.is_empty():
					continue
			"seeker":
				if not (_equipped(p, "aam") or _equipped(p, "rockets") or p.skill3 == "yolka" or p.wingmen.size() > 0):
					continue
			"servo":
				if not (_equipped(p, "gunpod") or _equipped(p, "turret")):
					continue
			"warhead":
				w = 1.8
			"msl_head", "msl_motor", "launcher":
				if not (_equipped(p, "aam") or _equipped(p, "rockets")):
					continue
				w = 1.8
			"skill3":
				title = "%s: уровень %d" % [PlaneClasses.SKILL3[p.skill3]["title"], taken + 1]
				w = 1.2
			"roll", "afterburner":
				w = 1.0
				if id == "roll" and not p.has_roll():
					title = "Залп ловушек: тренировка"
			"gun_dmg", "gun_rate":
				w = 2.0 # 2.4: карточки курсового чаще
		if taken > 0 and id != "repair" and id != "skill3":
			title += " (%d → %d)" % [taken, taken + 1]
		cands.append([w, {"id": id, "ban": id, "kind": "module", "cat": m["cat"], "title": title}])
	# ведомые: новый ведомый выбранного типа (до лимита) и «слётанность» (+1 уровень конкретному)
	if p.permanent_wingmen() < wing_limit(p):
		for t in Prog.WING_TYPES:
			if banned.has("wn:" + t) or not Profile.wing_ok(p.cls_id, t):
				continue
			cands.append([1.3, {"id": "wing_new_" + t, "ban": "wn:" + t, "kind": "wing_new", "wtype": t, "cat": "Звено",
				"title": "Ведомый: %s" % Prog.WING_TYPES[t]["title"]}])
	for wi in p.wingmen.size():
		var wm: Wingman = p.wingmen[wi]
		if wm.temp or wm.lvl >= 3:
			continue
		cands.append([1.2, {"id": "wing_lvl_%d" % wi, "ban": "wl:%d" % wi, "kind": "wing_lvl", "wi": wi, "cat": "Звено",
			"title": "Звено: слётанность — %s %d (ур. %d → %d)" % [Prog.WING_TYPES[wm.type]["short"], wi + 1, wm.lvl, wm.lvl + 1]}])
	# 3.2: вес ×1,8 карточкам курса; катализаторам эволюций — ×1,5
	for c in cands:
		if advances_course(p, c[1]):
			c[0] = float(c[0]) * Tuning.g("course_weight")
		elif c[1]["kind"] == "module" and Prog.evo_hint(p, c[1]["id"]) != "":
			c[0] = float(c[0]) * 1.5
	# Резерв v1: когда кандидатов мало или после 15:00
	if cands.size() < 10 or (Main.I != null and Main.I.run_time >= 900.0):
		_reserve(p, cands)
	return cands


static func _reserve(p: Player, cands: Array) -> void:
	var n_over := int(p.taken.get("res_overload", 0))
	cands.append([1.0 * pow(0.85, n_over), {"id": "res_overload", "ban": "res_overload", "kind": "reserve", "cat": "Резерв", "title": "Перегрузка"}])
	cands.append([0.8, {"id": "res_bounty", "ban": "res_bounty", "kind": "reserve", "cat": "Резерв", "title": "Премия"}])
	cands.append([0.8, {"id": "res_kit", "ban": "res_kit", "kind": "reserve", "cat": "Резерв", "title": "Ремкомплект"}])
	if p.has_course() and int(p.taken.get("res_course", 0)) < 3:
		cands.append([1.4, {"id": "res_course", "ban": "res_course", "kind": "reserve", "cat": "Резерв",
			"title": "Наработка: +1 к специализации"}])
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		if g.evo and g.evo_plus < 5:
			cands.append([1.5, {"id": "res_evo_%d" % gi, "ban": "res_evo_%d" % gi, "kind": "reserve", "cat": "Резерв", "group": gi,
				"title": "%s Э+ (%d → %d)" % [Prog.EVOS[g.weapon]["title"], g.evo_plus, g.evo_plus + 1]}])
	if p.gun_evo and p.gun_evo_plus < 5:
		cands.append([1.5, {"id": "res_evo_gun", "ban": "res_evo_gun", "kind": "reserve", "cat": "Резерв", "group": -1,
			"title": "«Дятел» Э+ (%d → %d)" % [p.gun_evo_plus, p.gun_evo_plus + 1]}])


## Эволюции, готовые сейчас (гарантированное место в выборе)
static func _evolutions(p: Player, banned: Dictionary) -> Array:
	var out: Array = []
	for w in Prog.EVOS:
		if banned.has("evo:" + w) or not Prog.evo_ready(p, w):
			continue
		out.append({"id": "evo_" + w, "ban": "evo:" + w, "kind": "evolution", "weapon": w, "cat": "Модернизация",
			"title": "МОДЕРНИЗАЦИЯ: %s" % Prog.EVOS[w]["title"]})
	return out


## Строка тегов на карточке: «Ракеты 3 → 4 · Взрыв 1 → 2»
static func tags_line(p: Player, card: Dictionary) -> String:
	var tags := Prog.card_tags(p, card)
	if tags.is_empty():
		return ""
	var add := 2 if card["kind"] == "evolution" else 1
	var parts := PackedStringArray()
	for t in tags:
		parts.append("%s %d → %d" % [Prog.tag_title(t), p.tag(t), p.tag(t) + add])
	return " · ".join(parts)


## Заполнить описание с учётом редкости
static func finalize(p: Player, card: Dictionary) -> Dictionary:
	var r := int(card["rarity"])
	var k: float = RARITY[r]["k"]
	var tags := Prog.card_tags(p, card)
	match card["kind"]:
		"weapon_new":
			var w: String = card["weapon"]
			var g: Hardpoint = p.groups[int(card["group"])]
			card["desc"] = Loc.t("%s\nНа подвес: %s ×%d\nСтарт с ур. %d") % [Loc.t(Weapons.DEFS[w]["desc"]), g.name, g.slots, NEW_WEAPON_LEVEL[r]]
			if Prog.EVOS.has(w):
				card["desc"] += Loc.t("\nМодернизация: ур. 5 + %s") % _cat_text(w)
		"weapon_up":
			var g2: Hardpoint = p.groups[int(card["group"])]
			var to := mini(g2.level + UP_LEVELS[r], Weapons.MAX_LEVEL)
			card["desc"] = Loc.t("%s: ур. %d → %d\n%s") % [g2.name, g2.level, to, Weapons.DEFS[g2.weapon]["lvl"]]
			if g2.builtin and g2.weapon == "turret" and PlaneClasses.turret_slots(p.cls_id, to) > g2.slots:
				card["desc"] += "\nВторая турель — сверху на фюзеляже"
			if r > 0:
				card["desc"] += Loc.t("\nБонус редкости: +%s урона группы") % _pct(0.15 * (k - 1.0))
			if g2.weapon == PlaneClasses.signature(p.cls_id):
				card["desc"] += Loc.t("\n★ Особенность класса: урон +20%")
			if to >= Weapons.MAX_LEVEL and Prog.EVOS.has(g2.weapon):
				card["desc"] += Loc.t("\nМодернизация: ур. 5 + %s, с %d:%02d") % [_cat_text(g2.weapon), int(Prog.EVO_TIME) / 60, int(Prog.EVO_TIME) % 60]
		"synergy", "skill_syn":
			card["desc"] = Loc.t(syn_def(p, card["syn"])["desc"]) + Loc.t("\nОткрывает слот %d из %d. Следующий слот дороже.") % [p.syn.size() + 1, MAX_SYN]
		"mastery":
			card["desc"] = Loc.t(String(PlaneClasses.MASTERY[p.cls_id]["desc"])) + Loc.t("\nОдна на вылет: если отказаться, больше не придёт.")
		"evolution":
			var ew: String = card["weapon"]
			card["desc"] = Loc.t(Prog.EVOS[ew]["desc"]) + Loc.t("\nЗаменяет оружие на том же подвесе. Отказ — вернётся через 3 выбора.")
		"wing_new":
			var wt: Dictionary = Prog.WING_TYPES[card["wtype"]]
			card["desc"] = Loc.t("%s\nСила ×%.1f · Ведомых: %d / %d") % [Loc.t(wt["desc"]), k, p.permanent_wingmen(), wing_limit(p)]
		"wing_lvl":
			var wm: Wingman = p.wingmen[int(card["wi"])]
			card["desc"] = Loc.t("Ур. %d: %s") % [wm.lvl + 1, Loc.t(Prog.WING_TYPES[wm.type]["lv"][wm.lvl])]
		"reserve":
			match card["id"]:
				"res_overload":
					card["desc"] = Loc.t("+%s урона всему оружию (можно брать снова)") % _pct(0.04 * k)
				"res_bounty":
					card["desc"] = Loc.t("+%d запчастей сразу") % int(20 * k)
				"res_kit":
					card["desc"] = Loc.t("+%s к максимальной прочности и полный ремонт") % _pct(0.05 * k)
				_:
					if card["id"] == "res_course":
						var cs := syn_def(p, p.course)
						card["desc"] = Loc.t("+1 очко «%s» — к связке «%s» (до 3 за вылет)") % [Loc.t(Prog.tag_title(cs["tag"])), Loc.t(cs["title"])]
					else:
						card["desc"] = "Модернизация: +8% урона, −4% перезарядки (до 5 раз)"
		_:
			card["desc"] = module_desc(p, card["id"], k)
			var dl := module_delta(p, card["id"], k)
			if dl != "":
				card["desc"] += "\n" + dl
			if card["kind"] == "module":
				card["desc"] += slot_hint(p, card["id"])
				card["desc"] += Prog.evo_hint(p, card["id"])
	card["tags"] = tags_line(p, card)
	card["course"] = advances_course(p, card)
	card["desc"] += course_hint(p, card)
	return card


static func _cat_text(w: String) -> String:
	var cat: Dictionary = Prog.EVOS[w]["cat"]
	var parts := PackedStringArray()
	for m in cat:
		parts.append("%s ×%d" % [MODULES[m]["title"], int(cat[m])])
	return ", ".join(parts)


## Карточка «чужого» тега: ни одного очка ни в одном её теге
static func _alien(p: Player, card: Dictionary) -> bool:
	var tags := Prog.card_tags(p, card)
	if tags.is_empty():
		return false
	for t in tags:
		if p.tag(t) > 0:
			return false
	return true


static func offer(p: Player, count: int, banned: Dictionary, locked: Dictionary, min_r := 0) -> Array:
	var out: Array = []
	var cands := _candidates(p, banned)
	# 3.2: связка курса — гарантированное место; эволюция — только если в этом выборе нет связки
	if course_ready(p):
		var sd := syn_def(p, p.course)
		var sc := {"id": "syn_" + p.course, "ban": "syn_" + p.course, "kind": "skill_syn" if sd.has("skill") else "synergy",
			"syn": p.course, "cat": "Связка", "rarity": 4,
			"title": "СВЯЗКА «%s» — слот %d" % [sd["title"], p.syn.size() + 1]}
		out.append(finalize(p, sc))
	else:
		var evos := _evolutions(p, banned)
		if not evos.is_empty():
			var ev: Dictionary = evos[0].duplicate()
			ev["rarity"] = 4
			out.append(finalize(p, ev))
	# фишка 2: мастерство класса — гарантированное место, если его не заняли связка или модернизация
	if out.is_empty() and mastery_ready(p, banned):
		var mc := {"id": "mastery", "ban": "mastery", "kind": "mastery", "cat": "Мастерство класса", "rarity": 4,
			"weapon": PlaneClasses.signature(p.cls_id),
			"title": "МАСТЕРСТВО: %s" % PlaneClasses.MASTERY[p.cls_id]["title"]}
		out.append(finalize(p, mc))
	# Закреплённая карточка остаётся, если ещё доступна
	if not locked.is_empty():
		for c in cands:
			if c[1]["id"] == locked["id"]:
				out.append(finalize(p, locked.duplicate()))
				break
	# «Кит»: в первых двух выборах — гарантированное улучшение турелей
	if p.cls_id == "bomber" and p.picks < 2:
		for c in cands:
			if c[1]["kind"] == "weapon_up" and (p.groups[int(c[1]["group"])] as Hardpoint).weapon == "turret":
				if not out.any(func(o): return o["id"] == c[1]["id"]):
					var tc: Dictionary = (c[1] as Dictionary).duplicate()
					tc["rarity"] = roll_rarity(Main.I.level, min_r)
					out.append(finalize(p, tc))
				break
	var taken_ids: Array = out.map(func(c): return c["id"])
	cands = cands.filter(func(c): return not taken_ids.has(c[1]["id"]))
	var late: bool = Main.I != null and Main.I.run_time >= 480.0
	var new_weapons := out.filter(func(c): return c["kind"] == "weapon_new").size()
	var aliens := 0
	while out.size() < count and not cands.is_empty():
		var total := 0.0
		for c in cands:
			total += float(c[0])
		var r := randf() * total
		var idx := 0
		for i in cands.size():
			r -= float(cands[i][0])
			if r <= 0.0:
				idx = i
				break
		var card: Dictionary = (cands[idx][1] as Dictionary).duplicate()
		var cid: String = card["id"]
		var cban: String = card["ban"]
		cands.remove_at(idx)
		# правила выдачи: не больше 1 нового оружия; после 8:00 — не больше 2 карточек «чужих» тегов
		if card["kind"] == "weapon_new":
			if new_weapons >= 1:
				continue
			new_weapons += 1
		if late and _alien(p, card):
			if aliens >= 2:
				continue
			aliens += 1
		card["rarity"] = 4 if card["kind"] in ["synergy", "skill_syn"] else roll_rarity(Main.I.level, min_r)
		out.append(finalize(p, card))
		var wpn: String = card.get("weapon", "")
		cands = cands.filter(func(c): return c[1]["id"] != cid and c[1]["ban"] != cban and (wpn == "" or c[1].get("weapon", "") != wpn))
	return out


## Мастерство класса: оружие-особенность на ур. 5, карточку ещё не брали и от неё не отказывались
static func mastery_ready(p: Player, banned: Dictionary) -> bool:
	if p.mastery or p.mastery_off or banned.has("mastery") or not PlaneClasses.MASTERY.has(p.cls_id):
		return false
	var sig := PlaneClasses.signature(p.cls_id)
	for g in p.groups:
		var h: Hardpoint = g
		if h.weapon == sig and h.level >= Weapons.MAX_LEVEL:
			return true
	return false


## Карточки, от которых отказались: эволюция вернётся через 3 выбора, мастерство — больше не придёт
static func on_declined(p: Player, offers: Array, chosen: Dictionary) -> void:
	for c in offers:
		if c["kind"] == "mastery" and c["id"] != chosen.get("id", ""):
			p.mastery_off = true
		if c["kind"] == "evolution" and c["id"] != chosen.get("id", ""):
			p.evo_wait[c["weapon"]] = p.picks + 3


static func apply(p: Player, card: Dictionary) -> void:
	var r := int(card["rarity"])
	var k: float = RARITY[r]["k"]
	var tags := Prog.card_tags(p, card)
	match card["kind"]:
		"weapon_new":
			var g: Hardpoint = p.groups[int(card["group"])]
			g.weapon = card["weapon"]
			g.level = NEW_WEAPON_LEVEL[r]
			g.bonus = 0.0
			g.cd = 0.5
			g.priority = "nearest"
			g.trigger = "auto"
		"weapon_up":
			var g2: Hardpoint = p.groups[int(card["group"])]
			g2.level = mini(g2.level + UP_LEVELS[r], Weapons.MAX_LEVEL)
			g2.bonus += 0.15 * (k - 1.0)
			if g2.builtin and g2.weapon == "turret":
				g2.slots = PlaneClasses.turret_slots(p.cls_id, g2.level)
		"module":
			var id: String = card["id"]
			p.taken[id] = int(p.taken.get(id, 0)) + 1
			match id:
				"armor":
					var add: float = float(p.cls["hp"]) * 0.2 * k
					p.max_hp += add
					p.heal(add)
				"engine":
					p.mods["speed"] *= 1.0 + 0.06 * k
				"wing":
					p.mods["turn"] *= 1.0 + 0.08 * k
				"gun_dmg":
					p.mods["gun_dmg"] *= 1.0 + 0.15 * k
				"gun_rate":
					p.mods["gun_rate"] *= 1.0 + 0.15 * k
				"reload":
					p.mods["hp_cd"] = maxf(RELOAD_FLOOR, p.mods["hp_cd"] * (1.0 - 0.1 * k))
				"seeker":
					pass # уровни ГСН читаются из p.taken (projectiles.gd)
				"frag":
					p.mods["blast_r"] *= 1.0 + 0.1 * k
				"servo":
					p.mods["servo_rate"] *= 1.0 + 0.1 * k
					p.mods["servo_range"] *= 1.0 + 0.06 * k
					p.mods["turret_traverse"] *= 1.0 + 0.25 * k
				"warhead":
					p.mods["blast_dmg"] *= 1.0 + 0.12 * k
				"msl_head":
					p.mods["missile_dmg"] *= 1.0 + 0.15 * k
					p.mods["msl_r"] = float(p.mods.get("msl_r", 1.0)) * (1.0 + 0.08 * k)
				"msl_motor":
					p.mods["missile_spd"] *= 1.0 + 0.12 * k
					p.mods["msl_lock"] = float(p.mods.get("msl_lock", 1.0)) * (1.0 + 0.08 * k)
				"launcher":
					p.mods["msl_cd"] = maxf(0.4, float(p.mods.get("msl_cd", 1.0)) * (1.0 - 0.1 * k))
				"radio":
					p.mods["wing_dmg"] *= 1.0 + 0.2 * k
					p.mods["wing_hp"] *= 1.0 + 0.15 * k
					for w in p.wingmen:
						(w as Wingman).refresh_hp()
				"magnet":
					p.mods["pickup"] *= 1.0 + 0.35 * k
				"roll":
					p.mods["roll_cd"] -= 1.0 * k
					p.mods["roll_time"] += 0.15 * k
				"afterburner":
					p.mods["ab_time"] += 1.0 * k
					p.mods["ab_cd"] -= 2.0 * k
				"skill3":
					p.mods["s3_lvl"] = mini(int(p.mods["s3_lvl"]) + 1, 3)
				"repair":
					p.heal(p.max_hp * minf(0.4 * k, 1.0))
		"wing_new":
			p.add_wingman(card["wtype"], k)
		"wing_lvl":
			var wm: Wingman = p.wingmen[int(card["wi"])]
			wm.lvl = mini(wm.lvl + 1, 3)
			wm.refresh_hp()
		"synergy", "skill_syn":
			p.open_synergy(card["syn"])
		"mastery":
			p.mastery = true
			Main.I.tele.v["mastery_t"] = Main.I.run_time
			Main.I.show_banner(Loc.t("МАСТЕРСТВО КЛАССА: %s") % Loc.t(PlaneClasses.MASTERY[p.cls_id]["title"]), 4.0)
		"evolution":
			p.evolve(card["weapon"])
			Main.I.show_banner(Loc.t("МОДЕРНИЗАЦИЯ: %s") % Loc.t(Prog.EVOS[card["weapon"]]["title"]), 4.0)
		"reserve":
			var tk: String = String(card["id"])
			p.taken[tk] = int(p.taken.get(tk, 0)) + 1
			match card["id"]:
				"res_overload":
					p.mods["dmg_all"] *= 1.0 + 0.04 * k
				"res_bounty":
					Main.I.parts += 20.0 * k
				"res_kit":
					p.max_hp *= 1.0 + 0.05 * k
					p.heal(p.max_hp)
				_:
					if card["id"] == "res_course":
						p.add_course_pts(1)
					elif int(card["group"]) >= 0:
						(p.groups[int(card["group"])] as Hardpoint).evo_plus += 1
					else:
						p.gun_evo_plus += 1
	# очки тегов: эволюция +2, остальное +1 (ремонт и резерв — без очков)
	if card["kind"] != "reserve" and card["kind"] != "synergy" and card["kind"] != "skill_syn":
		p.add_tags(tags, 2 if card["kind"] == "evolution" else 1)
	p.picks += 1
	p.cards_log.append("%s [%s]" % [card["title"], RARITY[r]["name"]])
