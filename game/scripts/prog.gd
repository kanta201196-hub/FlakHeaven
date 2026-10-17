class_name Prog
## 3.1: прокачка по спецификации «Прокачка и связки v1» (claude/sprint1/s2-design-progression.md):
## теги и очки тегов, нашивки (пороги тегов), эволюции оружия, типы ведомых.
## Навыки классов — в PlaneClasses.SKILL3, связки — в Cards.SYNERGIES.

const TAGS := {
	"missiles": {"title": "Ракеты", "color": Color(0.95, 0.38, 0.32)},
	"blast": {"title": "Взрыв", "color": Color(1.0, 0.6, 0.2)},
	"kinetic": {"title": "Кинетика", "color": Color(0.95, 0.85, 0.3)},
	"turrets": {"title": "Турели", "color": Color(0.3, 0.85, 0.8)},
	"wing": {"title": "Звено", "color": Color(0.75, 0.52, 1.0)},
	"maneuver": {"title": "Манёвр", "color": Color(0.5, 0.8, 1.0)},
	"armor": {"title": "Броня", "color": Color(0.72, 0.74, 0.78)},
}
const TAG_ORDER := ["missiles", "blast", "kinetic", "turrets", "wing", "maneuver", "armor"]

const WEAPON_TAGS := {
	"aam": ["missiles"], "rockets": ["missiles", "blast"], "gunpod": ["kinetic"],
	"turret": ["kinetic", "turrets"], "flares": ["maneuver", "armor"], "bombs": ["blast"],
	"railgun": ["kinetic"], "emp": ["blast"], "laser": ["turrets"], "plasma": ["blast"],
}
const MODULE_TAGS := {
	"reload": ["missiles"], "seeker": ["missiles"], "frag": ["blast"], "warhead": ["blast"],
	"msl_head": ["missiles", "blast"], "msl_motor": ["missiles"], "launcher": ["missiles"], "gun_dmg": ["kinetic"], "gun_rate": ["kinetic"],
	"servo": ["turrets"], "radio": ["wing"], "engine": ["maneuver"], "wing": ["maneuver"], "roll": ["maneuver"],
	"afterburner": ["maneuver"], "armor": ["armor"],
}

## Нашивки: очков тега 4 → I, 8 → II
const PATCH_AT := [4, 8]
const PATCHES := {
	"missiles": ["+10% урона ракет", "20% шанс пуска второй ракеты"],
	"blast": ["край взрыва бьёт на 50% (было 35%)", "враг, убитый взрывом, сам взрывается (30% урона)"],
	"kinetic": ["+10% урона по целям с прочностью > 50%", "пули гондолы и турелей пробивают ещё 1 цель"],
	"turrets": ["+10% дальности турелей", "каждая турель сбивает ракету раз в 3 с"],
	"wing": ["сбитый ведомый возвращается за 12 с (было 20)", "+1 ведомый сверх лимита"],
	"maneuver": ["перезарядка уклонения −1 с", "2 с после уклонения или форсажа: +20% урона всему"],
	"armor": ["−8% входящего урона", "раз в 12 с сильный удар (> 10% прочности) даёт 1 с неуязвимости"],
}

## Эволюции: оружие ур. 5 + модуль-катализатор ×N, с 7:00 (EVO_TIME). "gun" — курсовое.
const EVO_TIME := 420.0
const EVOS := {
	"aam": {"title": "«Шмель»", "cat": {"reload": 2},
		"desc": "2 тяжёлые ракеты каждые 4,5 с, урон 120; при попадании каждая делится на 4 самонаводящиеся боевые части (урон 40)"},
	"rockets": {"title": "«Ливень»", "cat": {"engine": 2},
		"desc": "Залп веером в 3 стороны по 5 ракет с точки, урон 22, радиус 70, перезарядка 3,5 с; цель — в секторе 50°"},
	"gunpod": {"title": "«Газонокосилка»", "cat": {"servo": 2},
		"desc": "Два ствола поочерёдно: урон 7, темп 0,12 с, дальность 520, пуля пробивает 1 цель"},
	"flares": {"title": "«Салют»", "cat": {"roll": 2},
		"desc": "Ловушки уводят 2 ракеты в 360 пикс., пули сбивают сразу; каждый перехват выпускает 3 самонаводящиеся ловушки по врагам (урон 25)"},
	"bombs": {"title": "«Бабушкин ковёр»", "cat": {"frag": 2},
		"desc": "Каждые 4 с ряд из 8 бомб поперёк пути самолёта (ширина 600), воздушный подрыв, урон 55, радиус 150"},
	"turret": {"title": "«Дикобраз»", "cat": {"armor": 3},
		"desc": "У каждой турели 2 ствола, дальность +40%, каждая турель сбивает ракету раз в 1,5 с"},
	"gun": {"title": "«Дятел»", "cat": {"gun_dmg": 5, "gun_rate": 2},
		"desc": "Пушка: каждый 4-й снаряд пробивает всё на линии 900 пикс. с уроном ×2,5; обычные −15% урона"},
}

## Ведомые
const WING_TYPES := {
	"swift": {"title": "«Стриж» — прикрытие", "short": "Стриж", "tags": ["wing", "missiles"],
		"desc": "Держит строй, бьёт самолёты из пушки, 2 наводящиеся ракеты (35) раз в 7 с",
		"lv": ["", "+40% урона, ракеты раз в 5 с", "ракеты с осколками; раз в 6 с сбивает ракету рядом с ведущим"]},
	"rook": {"title": "«Грачонок» — штурмовик", "short": "Грачонок", "tags": ["wing", "blast"],
		"desc": "Приоритет — наземные цели: залп из 6 ракет (12, взрыв 50) раз в 5 с; прочнее ×1,5",
		"lv": ["", "+40% урона", "над позицией ПВО сбрасывает кассету 4 × 30"]},
	"weasel": {"title": "«Ласка» — подавитель ПВО", "short": "Ласка", "tags": ["wing", "maneuver"],
		"desc": "Противорадарная ракета (150, ×2 по наземным) раз в 8 с; помехи — 25% шанс сорвать захват ракеты рядом с ведущим",
		"lv": ["", "шанс сорвать захват 40%", "ЭМИ раз в 15 с: ПВО в 400 пикс. молчит 3 с"]},
}

const ROMAN := ["", "I", "II", "III"]


static func tag_title(t: String) -> String:
	return TAGS[t]["title"]


## Теги карточки (для очков, подсказок и правил выдачи)
static func card_tags(p: Player, card: Dictionary) -> Array:
	match card["kind"]:
		"weapon_new":
			return WEAPON_TAGS.get(card["weapon"], [])
		"weapon_up":
			return WEAPON_TAGS.get((p.groups[int(card["group"])] as Hardpoint).weapon, [])
		"module":
			if card["id"] == "skill3":
				return PlaneClasses.SKILL3[p.skill3]["tags"]
			return MODULE_TAGS.get(card["id"], [])
		"wing_new":
			return WING_TYPES[card["wtype"]]["tags"]
		"wing_lvl":
			return WING_TYPES[(p.wingmen[int(card["wi"])] as Wingman).type]["tags"]
		"evolution":
			if card["weapon"] == "gun":
				return ["kinetic"]
			return WEAPON_TAGS.get(card["weapon"], [])
	return []


## Готова ли эволюция оружия (w — оружие или "gun")
static func evo_ready(p: Player, w: String) -> bool:
	if Main.I == null or Main.I.run_time < EVO_TIME:
		return false
	if int(p.evo_wait.get(w, 0)) > p.picks:
		return false
	if w == "gun":
		if p.gun_evo:
			return false
	else:
		var found := false
		for g in p.groups:
			var h: Hardpoint = g
			if h.weapon == w and h.level >= Weapons.MAX_LEVEL and not h.evo:
				found = true
		if not found:
			return false
	var cat: Dictionary = EVOS[w]["cat"]
	for m in cat:
		if int(p.taken.get(m, 0)) < int(cat[m]):
			return false
	return true


## Подсказка «чего не хватает до эволюции» (для карточек модулей-катализаторов)
static func evo_hint(p: Player, module_id: String) -> String:
	for w in EVOS:
		var cat: Dictionary = EVOS[w]["cat"]
		if not cat.has(module_id):
			continue
		var have: bool = w == "gun"
		if not have:
			for g in p.groups:
				if (g as Hardpoint).weapon == w and not (g as Hardpoint).evo:
					have = true
		if not have or (w == "gun" and p.gun_evo):
			continue
		var need := int(cat[module_id]) - int(p.taken.get(module_id, 0))
		if need > 0:
			var wn: String = "пушки" if w == "gun" else Weapons.DEFS[w]["short"]
			return "\nНужно для модернизации: %s → %s (ещё ×%d)" % [wn, EVOS[w]["title"], need]
	return ""
