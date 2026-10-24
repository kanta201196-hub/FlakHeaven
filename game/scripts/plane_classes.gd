class_name PlaneClasses
## Классы самолётов прототипа 2: по одному самолёту ур. 1 на класс.
## Названия вымышленные. Цифры — стартовые для плейтеста.
##
## groups — группы подвесов (одна настройка приоритета на группу):
##   name — где висит, slots — сколько точек в группе, weapon — стартовое оружие ("" — пусто).
## turrets — встроенные автотурели (круговой обстрел), отдельная группа без выбора оружия: сколько на старте;
##   потолок в бою, оружие, бонус ★ и ведомые — по самолёту (класс + ур. самолёта), см. `PLANES`.
## 3.5 (правки 13, 26, 27) — «ощущение» класса:
##   inertia_k — во сколько раз дольше вектор скорости догоняет нос (занос тяжёлой машины);
##   turn_accel — как быстро набирается угловая скорость (в долях полной за секунду): Оса — сразу, Кит — медленно;
##   roll_k — во сколько раз дольше переворот в бочке (неуязвимость при этом не длиннее обычной);
##   space — что на «Пробеле»: "roll" — бочка, "flares" — залп тепловых ловушек (Кит).
## Тест 3.5-s7 (полёт):
##   min_r — наименьший радиус разворота, пикс (любая прокачка и любой газ — круче не повернуть);
##   bank_rate — как быстро самолёт входит в крен (тяжёлый — медленно, видно вес);
##   bleed_k — сколько скорости теряет в крутом развороте (× turn_bleed), accel_k — как быстро её набирает обратно.

const LIST := ["fighter", "attacker", "bomber"]

const DATA := {
	"fighter": {
		"title": "Истребитель «Оса»",
		"role": "Лёгкий: скорость, манёвр, уклонение",
		"hp": 120.0, "speed": 1.0, "turn": 1.0, "gun_dmg": 0.733, "gun_rate": 1.0, "size": 1.0, "roll_cd_k": 0.75,
		"inertia_k": 0.8, "turn_accel": 9.0, "roll_k": 1.0, "space": "roll",
		"min_r": 75.0, "bank_rate": 11.0, "bleed_k": 0.8, "accel_k": 1.4,
		"groups": [
			{"name": "Крылья (пара)", "slots": 2, "weapon": "aam"},
			{"name": "Под фюзеляжем", "slots": 1, "weapon": ""},
		],
		"turrets": 0,
		"signature": "aam",
		"skill3": "combat_turn",
		"color": Color(0.55, 0.85, 1.0),
	},
	"attacker": {
		"title": "Штурмовик «Грач»",
		"role": "Средний: живучесть, усиленная пушка, турель",
		"hp": 160.0, "speed": 0.86, "turn": 0.8, "gun_dmg": 1.0, "gun_rate": 1.0, "size": 1.25,
		"inertia_k": 1.6, "turn_accel": 3.5, "roll_k": 1.45, "space": "roll",
		"min_r": 105.0, "bank_rate": 6.5, "bleed_k": 1.0, "accel_k": 1.0,
		"groups": [
			{"name": "Внутренняя пара", "slots": 2, "weapon": "rockets"},
			{"name": "Внешняя пара", "slots": 2, "weapon": ""},
		],
		"turrets": 1,
		"signature": "rockets",
		"skill3": "armor_shield",
		"color": Color(0.6, 0.95, 0.65),
	},
	"bomber": {
		"title": "Бомбардировщик «Кит»",
		"role": "Тяжёлый: прочный, кормовая турель (+ верхняя в бою), бомбы по земле, залп ловушек",
		"hp": 250.0, "speed": 0.82, "turn": 0.62, "gun_dmg": 0.5, "gun_rate": 1.0, "size": 1.6,
		"turret_k": 1.4, "turret_range_k": 1.2,
		"inertia_k": 2.6, "turn_accel": 1.8, "roll_k": 1.0, "space": "flares",
		"min_r": 150.0, "bank_rate": 4.0, "bleed_k": 1.25, "accel_k": 0.6,
		"groups": [
			{"name": "Бомбоотсек", "slots": 2, "weapon": "bombs"},
			{"name": "Крылья (пара)", "slots": 2, "weapon": ""},
		],
		"turrets": 1,
		"signature": "bombs",
		"skill3": "umbrella",
		"color": Color(0.95, 0.85, 0.55),
	},
}

## Третий навык (3.1: по 3 на класс, выбор перед вылетом). Клавиша E / X.
## lv — доводка I/II/III (карточкой), syn — связка навыка (доводка ≥ II + условие).
const CLASS_SKILLS := {
	"fighter": ["combat_turn", "yolka", "sonic"],
	"attacker": ["armor_shield", "assault", "rooks"],
	"bomber": ["umbrella", "carpet", "close_ranks"],
}

const SKILL3 := {
	"combat_turn": {
		"short": "Резкий разворот к ближайшему врагу: ракеты за вами теряют цель, 3 секунды пушка бьёт по нему вдвое чаще",
		"title": "Боевой разворот", "tags": ["maneuver"], "time": 0.35, "cd": 9.0,
		"hud": "разворот к врагу, пушка вдвое чаще",
		"desc": "Самолёт резко разворачивается носом к ближайшему вражескому самолёту (если рядом никого — к курсору). Ракеты, летящие за вами, теряют цель. 3 секунды пушка следит за этим врагом и стреляет вдвое чаще и на 30% сильнее",
		"lv": ["", "пушка следит за врагом 4 секунды", "перезарядка 7 секунд", "разворот сбивает вражеские пули и ракеты рядом"],
		"syn": {"id": "s_wheel", "title": "Чёртово колесо", "w": "aam", "lvl": 3,
			"desc": "Разворот сразу перезаряжает самонаводящиеся ракеты"},
	},
	"yolka": {
		"short": "Залп из 10 маленьких ракет: каждая сама находит своего врага вокруг вас",
		"title": "Ёлочка", "hud": "10 ракет по врагам вокруг", "tags": ["missiles"], "time": 0.0, "cd": 12.0,
		"desc": "Залп из 10 маленьких самонаводящихся ракет: каждая летит в своего врага вокруг вас (урон 30, небольшой взрыв)",
		"lv": ["", "14 ракет в залпе", "урон ракет 45", "сбив цель, ракета ищет следующую"],
		"syn": {"id": "s_newyear", "title": "Новогодняя ночь", "tag": "blast", "n": 3,
			"desc": "Там, где рвутся ракеты «Ёлочки», 3 секунды горит огонь и ранит врагов"},
	},
	"sonic": {
		"short": "Резкий разгон почти вдвое: врагов на пути сбиваете без вреда себе, в конце — ударная волна",
		"title": "Звуковой удар", "hud": "разгон и ударная волна", "tags": ["maneuver", "blast"], "time": 1.5, "cd": 14.0,
		"desc": "1,5 секунды самолёт летит почти вдвое быстрее; врезавшиеся в вас враги разбиваются, а вы не получаете урона. В конце — ударная волна: ранит (60) и отбрасывает врагов рядом",
		"lv": ["", "волна шире", "волна и в начале разгона", "перезарядка 10 секунд"],
		"syn": {"id": "s_clap", "title": "Хлопок", "tag": "armor", "n": 2,
			"desc": "Ударная волна стирает вражеские пули и ракеты вокруг"},
	},
	"armor_shield": {
		"short": "4 секунды вы получаете на 70% меньше урона, а врезавшиеся в вас самолёты разбиваются сами",
		"title": "Бронещит", "hud": "урон по вам −70%", "tags": ["armor"], "time": 4.0, "cd": 14.0,
		"desc": "4 секунды вы получаете на 70% меньше урона. Вражеские самолёты (кроме асов), врезавшиеся в вас, разбиваются сами, а вы не страдаете",
		"lv": ["", "5 секунд", "щит ранит (60) и отталкивает врагов рядом", "в конце щит выпускает волну из 30% поглощённого урона"],
		"syn": {"id": "s_iron", "title": "Утюг", "tag": "turrets", "n": 2,
			"desc": "Пока щит включён, на каждое попадание по вам вылетает ответная ракета в стрелка"},
	},
	"assault": {
		"short": "3 секунды бомбы и ракеты перезаряжаются в 3 раза быстрее, пушка бьёт по земле на 50% сильнее",
		"title": "Штурмовой заход", "hud": "бомбы и ракеты в 3 раза быстрее", "tags": ["blast", "missiles"], "time": 3.0, "cd": 15.0,
		"desc": "3 секунды бомбы и ракеты перезаряжаются в 3 раза быстрее, залпы неуправляемых ракет летят без прицеливания, а пушка наносит наземным целям на 50% больше урона",
		"lv": ["", "4 секунды", "взрывы на 25% шире во время захода", "уничтоженная наземная цель продлевает заход на 0,5 секунды (до 3)"],
		"syn": {"id": "s_conveyor", "title": "Конвейер", "w": "rockets", "lvl": 3,
			"desc": "Во время захода залпы неуправляемых ракет двойные"},
	},
	"rooks": {
		"short": "Вызов двух штурмовиков на помощь на 12 секунд: они атакуют наземные цели",
		"title": "Грачата", "hud": "2 штурмовика в помощь", "tags": ["wing"], "time": 0.0, "cd": 25.0,
		"desc": "Прилетают два штурмовика-помощника на 12 секунд: бьют ракетами по наземным целям (прочность у них вдвое меньше, чем у обычных ведомых)",
		"lv": ["", "помогают 15 секунд", "прилетают трое", "улетая, каждый сбрасывает 4 бомбы"],
		"syn": {"id": "s_nest", "title": "Гнездо", "tag": "wing", "n": 3,
			"desc": "Один из помощников остаётся в вашем звене насовсем"},
	},
	"umbrella": {
		"short": "5 секунд бортовые пулемёты стреляют вдвое чаще и дальше и сбивают летящие в вас ракеты",
		"title": "Зенитный зонтик", "hud": "пулемёты вдвое чаще, сбивают ракеты", "tags": ["turrets", "armor"], "time": 5.0, "cd": 14.0,
		"desc": "5 секунд бортовые пулемёты (турели) стреляют вдвое чаще и на 30% дальше, бьют по самолётам и сбивают вражеские ракеты рядом",
		"lv": ["", "6 секунд", "сбивают и вражеские пули", "пока включён, урон по вам −20%"],
		"syn": {"id": "s_shelter", "title": "Под одним зонтом", "tag": "wing", "n": 2,
			"desc": "Под зонтиком ваши ведомые неуязвимы и пускают по 2 самонаводящиеся ракеты"},
	},
	"carpet": {
		"short": "10 бомб рвутся спиралью вокруг самолёта прямо в воздухе, затем 3 секунды пулемёты стреляют вдвое чаще",
		"title": "Огненный ковёр", "hud": "бомбы спиралью вокруг", "tags": ["blast"], "time": 3.0, "cd": 12.0,
		"desc": "10 бомб рвутся спиралью вокруг самолёта прямо в воздухе — задевают и самолёты, и наземные цели. После этого 3 секунды бортовые пулемёты стреляют вдвое чаще",
		"lv": ["", "14 бомб", "бомбы на 40% сильнее и на 20% шире", "3 секунды самолёт летит на 30% быстрее"],
		"syn": {"id": "s_double", "title": "Двойной узор", "w": "bombs", "lvl": 3,
			"desc": "Через секунду вторая спираль бомб — в обратную сторону"},
	},
	"close_ranks": {
		"short": "6 секунд звено держится рядом и пускает самонаводящиеся ракеты; каждый ведомый рядом: урон по вам −20%",
		"title": "Сомкнуть строй", "hud": "звено рядом, урон по вам меньше", "tags": ["wing", "armor"], "time": 6.0, "cd": 18.0,
		"desc": "6 секунд ведомые прижимаются к вам и пускают по 3 самонаводящиеся ракеты (урон 40). Каждый ведомый рядом снижает урон по вам на 20% (до −60%)",
		"lv": ["", "+1 ракета каждому ведомому", "ведомые чинятся наполовину", "8 секунд"],
		"syn": {"id": "s_parade", "title": "Парад", "tag": "wing", "n": 4,
			"desc": "Раз в 20 секунд ведомые повторяют залп ракет и без навыка"},
	},
}


## Kanta 24.10: what each plane (class + plane level) carries. Overrides the class `DATA` for that plane:
## weapons — card and hangar pool; bonus — damage factor per weapon (the ★ class bonus, 15 % on plane 1,
## 20 % on plane 2, plus extras); turrets_max — turret cap reached by turret upgrades; wingmen — permanent
## wingmen cap; wing_types — allowed wingman types. Experimental weapons of the heavy hardpoint stay common.
const PLANES := {
	"fighter": {
		1: {"weapons": ["aam", "agm", "rockets", "flares"], "bonus": {"aam": 1.15},
			"turrets_max": 0, "wingmen": 1, "wing_types": ["swift"]},
		2: {"weapons": ["aam", "agm", "rockets", "flares", "srm"], "bonus": {"aam": 1.2, "agm": 1.05},
			"turrets_max": 0, "wingmen": 1, "wing_types": ["swift", "rook"]},
	},
	"attacker": {
		1: {"weapons": ["rockets", "aam", "agm", "bombs", "turret", "flares"], "bonus": {"rockets": 1.15},
			"turrets_max": 1, "wingmen": 1, "wing_types": ["swift", "rook"]},
		2: {"weapons": ["rockets", "aam", "agm", "bombs", "turret", "flares"], "bonus": {"rockets": 1.2},
			"turrets_max": 2, "wingmen": 1, "wing_types": ["swift", "rook"]},
	},
	"bomber": {
		1: {"weapons": ["bombs", "hebomb", "rockets", "turret", "flares"], "bonus": {"bombs": 1.15},
			"turrets_max": 2, "wingmen": 2, "wing_types": ["swift"]},
		2: {"weapons": ["bombs", "hebomb", "rockets", "turret", "flares"], "bonus": {"bombs": 1.2},
			"turrets_max": 3, "wingmen": 2, "wing_types": ["swift"]},
	},
}


## Class data of plane `lv` (1 or 2): `DATA` of the class with that plane's `PLANES` overrides
static func plane(cls_id: String, lv: int) -> Dictionary:
	var d: Dictionary = (DATA[cls_id] as Dictionary).duplicate(true)
	d.merge((PLANES[cls_id][clampi(lv, 1, 2)] as Dictionary).duplicate(true), true)
	d["plane_lvl"] = clampi(lv, 1, 2)
	return d


## Plane level to use when the caller gives none: the plane this class flies now
static func _lv(cls_id: String, lv: int) -> int:
	return lv if lv > 0 else Profile.plane_lvl(cls_id)


## Damage factor of weapon `w` on plane `lv` (the ★ class bonus and plane extras; 1.0 — none)
static func bonus_k(cls_id: String, lv: int, w: String) -> float:
	return float((PLANES[cls_id][clampi(_lv(cls_id, lv), 1, 2)]["bonus"] as Dictionary).get(w, 1.0))


## Whether plane `lv` may take a permanent wingman of type `t` (`Prog.WING_TYPES` id)
static func wing_type_ok(cls_id: String, lv: int, t: String) -> bool:
	return (PLANES[cls_id][clampi(_lv(cls_id, lv), 1, 2)]["wing_types"] as Array).has(t)


## Фишка 2 (Kanta 18.10, «бери в работу»): мастерство класса — одна особая карточка за вылет,
## когда оружие-особенность доходит до ур. 5. Черта самолёта, а не новое оружие.
const MASTERY := {
	"fighter": {"title": "«Охотник»",
		"desc": "Наводящиеся ракеты наносят асам и перехватчикам на 50% больше урона. Пока вы сидите у врага на хвосте, ракеты перезаряжаются вдвое быстрее."},
	"attacker": {"title": "«Штурмовка»",
		"desc": "Залп ракет наносит наземным целям (ПВО, колонна, техника) на 50% больше урона. Каждая уничтоженная наземная цель на 1 с ускоряет перезарядку навыка класса."},
	"bomber": {"title": "«Выжженная земля»",
		"desc": "После взрыва бомбы земля горит 3 с и жжёт наземные цели. Наземные цели, уничтоженные бомбами или огнём, дают на 50% больше запчастей."},
}
const MASTERY_K := 1.5
const MASTERY_FIRE_SRC := "мастерство: выжженная земля"


## Тест 3.5-s7 (Kanta): у «Кита» на старте только кормовая турель, верхняя на фюзеляже — с ур. 3 турелей
const TURRET2_LVL := 3
## Kanta 24.10: third turret mount («Кит» plane 2) at turret lvl 5
const TURRET3_LVL := 5


## Turret mounts at turret upgrade `level` on plane `lv`: the class start count, +1 at lvl 3 and +1 at lvl 5,
## capped by the plane's `turrets_max` (Kanta 24.10: «Грач» 1 / 2, «Кит» 2 / 3)
static func turret_slots(cls_id: String, level: int, lv := 0) -> int:
	var n := int(DATA[cls_id]["turrets"])
	if n <= 0:
		return 0
	if level >= TURRET2_LVL:
		n += 1
	if level >= TURRET3_LVL:
		n += 1
	return mini(n, maxi(int(DATA[cls_id]["turrets"]), int(PLANES[cls_id][clampi(_lv(cls_id, lv), 1, 2)]["turrets_max"])))


## PG-01 (Kanta 24.10): third hardpoint group, opened by hangar node «Узлы подвеса» lvl 2 of that plane.
## Appended after all other groups (turrets, heavy), so card ids, saves and 3D layout keep their indices.
## frac — where a wing pair hangs along the half-span (0 — the default by group index).
const GROUP3 := {
	"fighter": {"name": "Законцовки крыла (пара)", "slots": 2, "weapon": "", "frac": 0.85},
	"attacker": {"name": "Под фюзеляжем", "slots": 1, "weapon": ""},
	"bomber": {"name": "Внешняя пара", "slots": 2, "weapon": "", "frac": 0.82},
}


## Hardpoint group definitions of a class: the base `groups`, plus `GROUP3` when `third` is open
static func group_defs(cls_id: String, third: bool) -> Array:
	var out: Array = (DATA[cls_id]["groups"] as Array).duplicate()
	if third:
		out.append(GROUP3[cls_id])
	return out


## Whether plane `lv` of the class may carry weapon `w` (0 — the plane the class flies now)
static func allows(cls_id: String, w: String, lv := 0) -> bool:
	return Weapons.EXP.has(w) or (PLANES[cls_id][clampi(_lv(cls_id, lv), 1, 2)]["weapons"] as Array).has(w)


static func signature(cls_id: String) -> String:
	return String(DATA[cls_id].get("signature", ""))


static func get_data(id: String) -> Dictionary:
	return DATA[id]
