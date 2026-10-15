class_name Weapons
## Подвесное вооружение и встроенные турели.
## Каждое оружие — 5 уровней. Оружие висит на группе подвесов; у группы — приоритет целей.
## Боеприпасов нет: только перезарядка (решение по концепту).

const MAX_LEVEL := 5

const PRIORITIES := ["nearest", "strongest", "weakest", "big", "ground"]
const PRIORITY_NAMES := {
	"nearest": "ближайшие",
	"strongest": "самые прочные",
	"weakest": "добивать слабых",
	"big": "крупные и асы",
	"ground": "наземные цели",
}

const DEFS := {
	"aam": {
		"title": "Ракеты «воздух-воздух»",
		"short": "Ракеты В-В",
		"desc": "Самонаводящиеся ракеты по целям приоритета",
		"cd": 10.0, "dmg": 45.0, "range": 1050.0, "uses_priority": true,
		"lvl": "1 ракета с точки; ур. 2–5: +30% урона, −10% перезарядки; ур. 4: ещё +80% урона и +20% скорости",
	},
	"rockets": {
		"title": "Блок НАР",
		"short": "НАР",
		"desc": "Залп неуправляемых ракет вперёд, взрыв по площади. Авто — когда цель точно перед носом; можно перевести на ПКМ",
		"cd": 4.0, "dmg": 14.0, "range": 750.0, "uses_priority": false, "uses_trigger": true,
		"lvl": "залп — 4 ракеты с точки; ур. 2–5: +40% урона, +10% радиуса",
	},
	"gunpod": {
		"title": "Пушечная гондола",
		"short": "Гондола",
		"desc": "Поворотная пушка: сама наводится на цели приоритета вокруг самолёта",
		"cd": 0.2, "dmg": 5.0, "range": 460.0, "uses_priority": true,
		"lvl": "ур. 2–5: +25% урона, +10% темпа и дальности",
	},
	"flares": {
		"title": "Противоракеты",
		"short": "Противоракеты",
		"desc": "Тепловые ловушки: уводят ракету, которая подошла близко; с ур. 4 — две ракеты и пули рядом",
		"cd": 4.0, "dmg": 0.0, "range": 250.0, "uses_priority": false,
		"lvl": "ур. 2–5: −10% перезарядки, +8% радиуса; ур. 4: две ракеты за раз и пули рядом",
	},
	"bombs": {
		"title": "Кассетные бомбы",
		"short": "Бомбы",
		"desc": "Сброс позади самолёта: взрыв по площади — против погони",
		"cd": 6.0, "dmg": 30.0, "range": 130.0, "uses_priority": false, "uses_trigger": true,
		"lvl": "ур. 2–5: +25% урона, +10% радиуса, −8% перезарядки",
	},
	"turret": {
		"title": "Автотурели",
		"short": "Турели",
		"desc": "Встроенные турели кругового обстрела",
		"cd": 0.3, "dmg": 3.0, "range": 420.0, "uses_priority": true,
		"lvl": "ур. 2–5: +15% урона, +10% темпа",
	},
}

## Оружие, которое может выпасть картой «новое оружие» (турели — встроенные).
const POOL := ["aam", "rockets", "gunpod", "flares", "bombs"]


static func title(id: String) -> String:
	return DEFS[id]["title"]


## Выбор цели по приоритету группы.
static func pick_target(from: Vector2, max_dist: float, prio: String, skip: Array = [], air_only := false) -> Enemy:
	var best: Enemy = null
	var best_score := INF
	for n in Main.I.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or skip.has(e) or (air_only and e.is_ground):
			continue
		var d := from.distance_to(e.global_position)
		if d > max_dist:
			continue
		var score := d
		match prio:
			"strongest":
				score = -e.hp * 10.0 + d * 0.01
			"weakest":
				score = e.hp * 10.0 + d * 0.01
			"big":
				score = d - (5000.0 if e.big else 0.0) - (20000.0 if e.is_boss else 0.0)
			"ground":
				score = d - (20000.0 if e.is_ground else 0.0)
		if score < best_score:
			best_score = score
			best = e
	return best
