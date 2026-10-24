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
		"short": "Наводящиеся ракеты",
		"desc": "Самонаводящиеся ракеты по целям приоритета",
		"cd": 10.0, "dmg": 45.0, "range": 1050.0, "uses_priority": true,
		"lvl": "1 ракета с точки; ур. 2–5: +30% урона, −10% перезарядки; ур. 4: ещё +80% урона и +20% скорости",
	},
	"rockets": {
		"title": "Неуправляемые ракеты (залп)",
		"short": "Залп ракет",
		"desc": "Залп ракет вперёд, взрыв по площади, по наземным целям урон ×3. Пускаются сами, когда враг точно перед носом; в паузе (Tab) можно перевести на правую кнопку мыши",
		"cd": 4.0, "dmg": 12.5, "range": 750.0, "uses_priority": false, "uses_trigger": true,
		"lvl": "залп — 4 ракеты с точки, ур. 3–4 — 5, ур. 5 — 6; ур. 2–5: +25% урона, +10% радиуса; по земле урон ×3",
	},
	"gunpod": {
		"title": "Пушечная гондола",
		"short": "Гондола",
		"desc": "Поворотная пушка: сама наводится на цели приоритета вокруг самолёта",
		"cd": 0.2, "dmg": 5.0, "range": 460.0, "uses_priority": true,
		"lvl": "ур. 2–5: +25% урона, +10% темпа и дальности",
	},
	"flares": {
		"title": "Тепловые ловушки",
		"short": "Ловушки",
		"desc": "Отстрел тепловых ловушек: ракета, подошедшая близко, уходит на вспышку и рвётся возле неё; с ур. 4 — две ракеты и пули рядом",
		"cd": 4.0, "dmg": 0.0, "range": 250.0, "uses_priority": false,
		"lvl": "ур. 2–5: −10% перезарядки, +8% радиуса; ур. 4: две ракеты за раз и пули рядом",
	},
	"bombs": {
		"title": "Кассетные бомбы",
		"short": "Бомбы",
		"desc": "Бомбы по наземным целям: взрыв по площади, урон ×2 по земле; самолёты не задевают",
		"cd": 6.0, "dmg": 27.5, "range": 130.0, "uses_priority": false, "uses_trigger": true,
		"lvl": "ур. 2–5: +25% урона, +10% радиуса, −8% перезарядки",
	},
	# PG-01 (Kanta 24.10): new standard weapons, numbers of growth and floors — `WeaponBalance`
	"srm": {
		"title": "Ракеты ближнего боя",
		"short": "Ближний бой",
		"desc": "Лёгкие ракеты с тепловой головкой: по одной с точки в ближайший самолёт рядом. Быстро перезаряжаются и круто доворачивают — против дронов и вёртких истребителей",
		"cd": 4.0, "dmg": 22.0, "range": 600.0, "uses_priority": false,
		"lvl": "1 ракета с точки; ур. 2–5: +25% урона, −8% перезарядки",
	},
	"agm": {
		"title": "Управляемая ракета «воздух-земля»",
		"short": "Ракета В-З",
		"desc": "Тяжёлая ракета по наземным целям с дальней дистанции: сама выбирает бронированную или крупную цель. Броня её не останавливает — по бронированным урон выше",
		"cd": 7.0, "dmg": 90.0, "range": 900.0, "uses_priority": false,
		"lvl": "1 ракета с точки; ур. 2–5: +25% урона, −6% перезарядки",
	},
	"hebomb": {
		"title": "Фугасная авиабомба",
		"short": "Фугасная",
		"desc": "Одна тяжёлая бомба с точки: долгая перезарядка, большой взрыв по земле, урон ×2 по наземным целям; самолёты не задевает. Против бункеров и колонн",
		"cd": 9.0, "dmg": 110.0, "range": 200.0, "uses_priority": false, "uses_trigger": true,
		"lvl": "1 бомба с точки; ур. 2–5: +25% урона, +8% радиуса",
	},
	# U-08: экспериментальное оружие — только на тяжёлом подвесе самолёта ур. 2, открывается кампанией
	"railgun": {
		"title": "Рельсотрон (экспериментальный)",
		"short": "Рельсотрон",
		"desc": "Заряжается 0,9 с и бьёт по носу: снаряд пробивает всё на линии 1 200 пикс. Стреляет сам, когда враг впереди",
		"cd": 5.0, "dmg": 160.0, "range": 1200.0, "uses_priority": false, "exp": true,
		"lvl": "ур. 2–5: +30% урона, −8% перезарядки",
	},
	"emp": {
		"title": "ЭМИ-заряд (экспериментальный)",
		"short": "ЭМИ-заряд",
		"desc": "Импульс вокруг самолёта: дронам — урон ×5, остальные враги и ПВО молчат 3 с (летят по инерции, не стреляют), вражеские ракеты теряют цель. По асам и «Крепости» — слабо",
		"cd": 9.0, "dmg": 25.0, "range": 380.0, "uses_priority": false, "exp": true,
		"lvl": "ур. 2–5: +25% урона, +8% радиуса, −8% перезарядки",
	},
	"laser": {
		"title": "Лазер обороны «Луч» (экспериментальный)",
		"short": "Лазер «Луч»",
		"desc": "Сжигает вражеские ракеты и пули рядом с самолётом и подсвечивает ближайшего врага. По самолётам и земле — слабо",
		"cd": 0.9, "dmg": 6.0, "range": 250.0, "uses_priority": false, "exp": true,
		"lvl": "ур. 2–5: +8% радиуса, −8% перезарядки, +25% урона",
	},
	"plasma": {
		"title": "Плазменная бомба (экспериментальная)",
		"short": "Плазма",
		"desc": "Шар плазмы на земле 4 с: жжёт наземные цели и прожигает укрытия. Только по земле, долгая перезарядка",
		"cd": 10.0, "dmg": 70.0, "range": 160.0, "uses_priority": false, "exp": true,
		"lvl": "ур. 2–5: +25% урона в секунду, +8% радиуса, −8% перезарядки",
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
## 3.5: пушечная гондола убрана из игры решением владельца (16.10): курсовое вооружение
## заменяет огонь по прямой. Код гондолы оставлен — вернуть = добавить "gunpod" сюда.
const POOL := ["aam", "rockets", "flares", "bombs", "srm", "agm", "hebomb"]


## U-08: экспериментальное оружие — карточки только для тяжёлого подвеса; что открывает операция кампании
const EXP := ["railgun", "emp", "laser", "plasma"]
## пройти операцию N (с 0): «Перевал» — рельсотрон, «Сухое русло» — ЭМИ, «Крепости» — лазер и плазма
const EXP_OP := {"railgun": 0, "emp": 1, "laser": 2, "plasma": 2}


## Bomb family: shares aiming by button, bay doors and the "bombs fall on ground targets" rules
const BOMBS := ["bombs", "hebomb"]


## True for weapons dropped as bombs (see `BOMBS`)
static func is_bomb(id: String) -> bool:
	return BOMBS.has(id)


## True for weapons whose rounds leave the pylon (missiles, rocket pods, bombs): the model is hidden or dimmed
## while reloading and the launch point is taken from the model on the pylon
static func leaves_pylon(id: String) -> bool:
	return Hardpoint.MISSILES.has(id) or BOMBS.has(id)


static func exp_open(id: String) -> bool:
	return Campaign.cleared(int(EXP_OP.get(id, 99)))


## Оружие есть в игре (в пуле карт или встроенное) — для ангара и связок
static func in_game(id: String) -> bool:
	return POOL.has(id) or id == "turret"


static func title(id: String) -> String:
	return DEFS[id]["title"]


## Выбор цели по приоритету группы.
static func pick_target(from: Vector2, max_dist: float, prio: String, skip: Array = [], air_only := false, ground_only := false, homing := false) -> Enemy:
	var best: Enemy = null
	var best_score := INF
	for n in Main.I.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or skip.has(e) or (air_only and e.is_ground) or (ground_only and not e.is_ground):
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
		if homing and e.jammed():
			score += 100000.0   # EX-04: помехи — самонаводящиеся берут такую цель последней
		if score < best_score:
			best_score = score
			best = e
	return best
