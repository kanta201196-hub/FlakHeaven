extends Node
## 3.2: мета-прогрессия v0 (спецификация claude/sprint1/s3-meta-v0.md) — профиль игрока между вылетами.
## Запчасти, экипажи классов (опыт, перки, навыки, позывной), узлы самолёта, самолёт ур. 2, ветки оружия.
## Файл user://profile.json (запись через .tmp + rename). Всё, что вычисляется (уровни, очки перков), не хранится.

const PATH := "user://profile.json"
const VERSION := 1
const TEST_BUILD := true   # тестовая сборка: отладочная панель в ангаре (F9)

const NODE_COST := [80, 250, 600, 1400, 2900]
const NODES := {
	"frame": {"title": "Планер", "step": "перезарядка бочки и форсажа −4%", "note": "временно: до введения веса"},
	"engine": {"title": "Двигатель", "step": "скорость +2%", "note": ""},
	"armor": {"title": "Броня", "step": "прочность +5%", "note": ""},
	"wing": {"title": "Крыло", "step": "разворот +3%", "note": ""},
	"pylons": {"title": "Узлы подвеса", "step": "урон подвесов и турелей +4%", "note": "временно: до введения грузоподъёмности"},
	"tank": {"title": "Топливный бак", "step": "окно эвакуации +6 с, ворота +5%", "note": "временно: до введения топлива"},
}
const NODE_ORDER := ["frame", "engine", "armor", "wing", "pylons", "tank"]

const PLANE2_COST := 800
const PLANE2_CREW := 3

const TIER_COST := [400, 1200, 3000]
const REDO_COST := [100, 300, 750]
## Ветки оружия: оружие → [ступень1: [a, b], ступень2: [a, b]]; эффект — множители по ключам
const WBRANCH := {
	"aam": [[["Усиленная БЧ", "урон +20%", {"dmg": 1.2}], ["Дальнобойные", "дальность захвата +25%", {"range": 1.25}]],
		[["Форсированный РДТТ", "скорость ракеты +25%", {"spd": 1.25}], ["Быстрая перезарядка", "перезарядка −15%", {"cd": 0.85}]]],
	"rockets": [[["Фугасные", "урон +20%", {"dmg": 1.2}], ["Прицел НАР", "автопуск дальше на 25%, конус шире", {"auto_r": 1.25}]],
		[["Скоростные", "скорость ракеты +20%", {"spd": 1.2}], ["Быстрая перезарядка", "перезарядка −15%", {"cd": 0.85}]]],
	"gunpod": [[["Крупный калибр", "урон +20%", {"dmg": 1.2}], ["Длинный ствол", "дальность +20%", {"range": 1.2}]],
		[["Высокая нач. скорость", "скорость пули +25%", {"spd": 1.25}], ["Скорострельная", "темп +15%", {"cd": 0.87}]]],
	"flares": [[["Широкий веер", "радиус перехвата +20%", {"range": 1.2}], ["Быстрый отстрел", "перезарядка −15%", {"cd": 0.85}]],
		[["Ловушка с подрывом", "уведённая ракета взрывается (20, 60 пикс.)", {}], ["Запас ловушек", "20%: мгновенная перезарядка", {}]]],
	"bombs": [[["Тяжёлые", "урон +20%", {"dmg": 1.2}], ["Рассеивание", "радиус +15%", {"blast_r": 1.15}]],
		[["Короткий взрыватель", "подрыв 0,4 с (было 0,55)", {"fuse": 0.73}], ["Быстрая перезарядка", "перезарядка −15%", {"cd": 0.85}]]],
	"turret": [[["Крупный калибр", "урон +20%", {"dmg": 1.2}], ["Дальномер", "дальность +15%", {"range": 1.15}]],
		[["Высокая нач. скорость", "скорость пули +25%", {"spd": 1.25}], ["Скорострельные", "темп +15%", {"cd": 0.87}]]],
}
const WEAPON_ORDER := ["aam", "rockets", "gunpod", "flares", "bombs", "turret"]

## Экипаж: суммарный опыт до уровня (индекс 0 = ур. 1)
const CREW_CUM := [0, 70, 180, 330, 520, 820, 1220, 1730, 2360, 3130, 4050, 5130, 6390, 7840, 9490, 11360, 13460, 15810, 18420, 21310]
const CREW := {
	"fighter": {"crew": "Пилот", "stats": "разворот +0,6% и перезарядка навыков −0,6% за уровень"},
	"attacker": {"crew": "Пилот и стрелок", "stats": "прочность +0,7% и урон турели +0,7% за уровень"},
	"bomber": {"crew": "Командир, штурман, стрелки", "stats": "прочность +0,5%, подбор опыта +0,7%, темп турелей +0,6% за уровень"},
}
## 3.5: 5 позывных на класс, у каждого черта характера — плюс и минус.
## mods: множитель ключа Player.mods ("hp" — прочность). Применяется × meta_k.
const CALLSIGNS := {
	"fighter": ["Шмель", "Сокол-2", "Чиж", "Барс", "Искра"],
	"attacker": ["Утюг", "Дед", "Молот", "Бульдог", "Кочерга"],
	"bomber": ["Борода", "Маяк", "Тюлень", "Шкаф", "Дирижабль"],
}
const TRAITS := {
	"Шмель": {"title": "Торопыга", "plus": "скорость +8%", "minus": "разворот −6%", "mods": {"speed": 1.08, "turn": 0.94}},
	"Сокол-2": {"title": "Хладнокровие", "plus": "перезарядка навыков −10%", "minus": "скорость −5%", "mods": {"s3_cd": 0.9, "speed": 0.95}},
	"Чиж": {"title": "Новичок-везунчик", "plus": "подбор опыта +20%", "minus": "прочность −10%", "mods": {"pickup": 1.2, "hp": 0.9}},
	"Барс": {"title": "Ветеран", "plus": "прочность +10%", "minus": "перезарядка манёвров +10%", "mods": {"hp": 1.1, "man_cd": 1.1}},
	"Искра": {"title": "Риск", "plus": "наносимый урон +15%", "minus": "получаемый урон +15%", "mods": {"dmg_all": 1.15, "taken_k": 1.15}},
	"Утюг": {"title": "Упрямец", "plus": "получаемый урон −10%", "minus": "скорость −6%", "mods": {"taken_k": 0.9, "speed": 0.94}},
	"Дед": {"title": "Старая школа", "plus": "урон пушки +15%", "minus": "урон ракет −10%", "mods": {"gun_dmg": 1.15, "missile_dmg": 0.9}},
	"Молот": {"title": "Кувалда", "plus": "урон взрывов +12%", "minus": "подбор опыта −15%", "mods": {"blast_dmg": 1.12, "pickup": 0.85}},
	"Бульдог": {"title": "Хватка", "plus": "урон по наземным целям +15%", "minus": "разворот −5%", "mods": {"ground_dmg": 1.15, "turn": 0.95}},
	"Кочерга": {"title": "Механик", "plus": "перезарядка подвесов −8%", "minus": "прочность −8%", "mods": {"hp_cd": 0.92, "hp": 0.92}},
	"Борода": {"title": "Хозяйственный", "plus": "прочность +10%", "minus": "наносимый урон −5%", "mods": {"hp": 1.1, "dmg_all": 0.95}},
	"Маяк": {"title": "Дальнозоркий", "plus": "дальность турелей +12%", "minus": "темп турелей −8%", "mods": {"servo_range": 1.12, "turret_rate": 0.92}},
	"Тюлень": {"title": "Флегматик", "plus": "получаемый урон −8%", "minus": "перезарядка навыков +10%", "mods": {"taken_k": 0.92, "s3_cd": 1.1}},
	"Шкаф": {"title": "Бомбардир", "plus": "радиус взрывов +12%", "minus": "скорость −5%", "mods": {"blast_r": 1.12, "speed": 0.95}},
	"Дирижабль": {"title": "Азарт", "plus": "наносимый урон +12%", "minus": "прочность −12%", "mods": {"dmg_all": 1.12, "hp": 0.88}},
}
## Перки: 3 ветки × 2 ступени на класс
const PERKS := {
	"fighter": [
		["Охотник", [["f_tail1", "Цепкий", "«на хвосте» срабатывает за 0,15 с, конус 32°"], ["f_tail2", "Добивание", "сбитие с хвоста: −1 с перезарядки бочки, форсажа и навыков"]]],
		["Ракетчик", [["f_msl1", "Глазастый", "ракеты +10% урона"], ["f_msl2", "Форсированный старт", "ракеты +15% скорости и +10% урона на первой секунде полёта"]]],
		["Акробат", [["f_acro1", "На волоске", "пролёт на волоске снимает вдвое больше перезарядки"], ["f_acro2", "Двойная бочка", "бочка +0,2 с неуязвимости, перезарядка −1 с"]]],
	],
	"attacker": [
		["Броня", [["a_arm1", "Толстокожий", "входящий урон −6%"], ["a_arm2", "Второе дыхание", "раз за вылет при прочности < 25%: 2 с неуязвимости и ремонт 20%"]]],
		["Штурм", [["a_grd1", "Наводчик", "+15% урона по наземным целям"], ["a_grd2", "Трофейщик", "наземные цели дают ×1,5 запчастей"]]],
		["Стрелок", [["a_gun1", "Зоркий", "турель и гондола +12% дальности"], ["a_gun2", "Длинная очередь", "турель и гондола +15% темпа"]]],
	],
	"bomber": [
		["Зенитчики", [["b_aa1", "Сектор обстрела", "турели +12% темпа"], ["b_aa2", "Заградогонь", "каждая турель сбивает ракету раз в 4 с"]]],
		["Бомбардир", [["b_bmb1", "Тяжёлые фугасы", "+10% радиуса всех взрывов"], ["b_bmb2", "Штурманский расчёт", "перезарядка навыков класса −12%"]]],
		["Звено", [["b_wing1", "Слётанность", "ведомые +20% прочности, +10% урона"], ["b_wing2", "Старый знакомый", "вылет начинается с ведомым «Стриж»"]]],
	],
}
const PERK_T2_LVL := 6
const SKILL_UNLOCK := [1, 3, 7]   # навыки класса по порядку CLASS_SKILLS: с ур. экипажа
const SLOT2_LVL := 5
const WING_UNLOCK := {"weasel": 4, "rook": 8}
const WAGE := 50
## 3.5: звание экипажа покупается за запчасти, когда опыта хватает (цена — за новый уровень)
const PROMOTE_COST := [[5, 100], [10, 300], [15, 700], [20, 1200]]

var data := {}


func _ready() -> void:
	reset_data()
	load_profile()


func _default_class(cls: String) -> Dictionary:
	return {"crew_xp": 0, "crew_rank": 1, "callsign": CALLSIGNS[cls][0], "plane2": false,
		"nodes": {"frame": 0, "engine": 0, "armor": 0, "wing": 0, "pylons": 0, "tank": 0},
		"perks": [], "skills": [PlaneClasses.CLASS_SKILLS[cls][0], ""], "seen_unlocks": []}


func reset_data() -> void:
	data = {"version": VERSION, "parts": 0, "sorties": 0, "parts_earned_total": 0, "classes": {}, "weapons": {}}
	for c in PlaneClasses.LIST:
		data["classes"][c] = _default_class(c)
	for w in WEAPON_ORDER:
		data["weapons"][w] = {"t1": "", "t2": ""}


func load_profile() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary):
		return
	for k in ["parts", "sorties", "parts_earned_total"]:
		if d.has(k):
			data[k] = int(d[k])
	if d.get("classes") is Dictionary:
		for c in PlaneClasses.LIST:
			if (d["classes"] as Dictionary).has(c):
				var src: Dictionary = d["classes"][c]
				var dst: Dictionary = data["classes"][c]
				for k2 in dst:
					if src.has(k2):
						dst[k2] = src[k2]
				dst["crew_xp"] = int(dst["crew_xp"])
				# 3.5: старый профиль без звания — звание = уровень по опыту (прогресс не теряется)
				dst["crew_rank"] = int(src["crew_rank"]) if src.has("crew_rank") else xp_lvl_of(int(dst["crew_xp"]))
				if not (CALLSIGNS[c] as Array).has(dst["callsign"]):
					dst["callsign"] = CALLSIGNS[c][0]
	if d.get("weapons") is Dictionary:
		for w in WEAPON_ORDER:
			if (d["weapons"] as Dictionary).has(w):
				data["weapons"][w] = d["weapons"][w]


func save() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))


func wipe() -> void:
	reset_data()
	save()


# ---------- запросы ----------

func meta_k() -> float:
	return Tuning.g("meta_k")


func cls(c: String) -> Dictionary:
	return data["classes"][c]


func parts() -> int:
	return int(data["parts"])


## Уровень (звание) экипажа — то, что действует на самолёт. Повышается кнопкой «Повысить в звании».
func crew_lvl(c: String) -> int:
	return clampi(int(cls(c).get("crew_rank", 1)), 1, CREW_CUM.size())


func xp_lvl_of(xp: int) -> int:
	var lv := 1
	for i in CREW_CUM.size():
		if xp >= int(CREW_CUM[i]):
			lv = i + 1
	return lv


## Уровень, до которого хватает опыта
func xp_lvl(c: String) -> int:
	return xp_lvl_of(int(cls(c)["crew_xp"]))


## Опыт к следующему званию: [набрано, нужно] (может быть набрано > нужно; на ур. 20 — [0, 0])
func crew_progress(c: String) -> Array:
	var lv := crew_lvl(c)
	if lv >= CREW_CUM.size():
		return [0, 0]
	var xp := int(cls(c)["crew_xp"])
	return [xp - int(CREW_CUM[lv - 1]), int(CREW_CUM[lv]) - int(CREW_CUM[lv - 1])]


## Цена повышения до уровня lv
func promote_cost(lv: int) -> int:
	for row in PROMOTE_COST:
		if lv <= int(row[0]):
			return int(row[1])
	return 0


## Опыта хватает на следующее звание
func promote_ready(c: String) -> bool:
	return crew_lvl(c) < CREW_CUM.size() and xp_lvl(c) > crew_lvl(c)


func can_promote(c: String) -> bool:
	return promote_ready(c) and parts() >= promote_cost(crew_lvl(c) + 1)


## Повысить в звании: списать запчасти, +1 уровень. Возвращает, что открылось.
func promote(c: String) -> Array:
	if not can_promote(c):
		return []
	var lv := crew_lvl(c) + 1
	data["parts"] = parts() - promote_cost(lv)
	cls(c)["crew_rank"] = lv
	save()
	return unlocks_at(c, lv)


## Что открывает уровень экипажа lv
func unlocks_at(c: String, lv: int) -> Array:
	var out: Array = []
	if lv % 2 == 0:
		out.append("очко перка (ур. %d)" % lv)
	for i in SKILL_UNLOCK.size():
		if int(SKILL_UNLOCK[i]) == lv and i > 0:
			out.append("навык «%s»" % PlaneClasses.SKILL3[PlaneClasses.CLASS_SKILLS[c][i]]["title"])
	if lv == SLOT2_LVL:
		out.append("второй слот навыка [F]")
	if lv == PLANE2_CREW:
		out.append("можно купить самолёт ур. 2")
	if lv == PERK_T2_LVL:
		out.append("перки 2-й ступени")
	for t in WING_UNLOCK:
		if int(WING_UNLOCK[t]) == lv:
			out.append("ведомый %s в карточках" % Prog.WING_TYPES[t]["title"])
	return out


func trait_of(c: String) -> Dictionary:
	return TRAITS.get(cls(c)["callsign"], {})


func perk_points(c: String) -> int:
	return crew_lvl(c) / 2 - (cls(c)["perks"] as Array).size()


func has_perk(c: String, id: String) -> bool:
	return meta_k() > 0.0 and (cls(c)["perks"] as Array).has(id)


func node(c: String, id: String) -> int:
	return int(cls(c)["nodes"].get(id, 0))


func plane2(c: String) -> bool:
	return meta_k() > 0.0 and bool(cls(c)["plane2"])


func skill_unlocked(c: String, sk: String) -> bool:
	var i: int = PlaneClasses.CLASS_SKILLS[c].find(sk)
	return i >= 0 and (meta_k() <= 0.0 or crew_lvl(c) >= int(SKILL_UNLOCK[i]))


func slot2_open(c: String) -> bool:
	return crew_lvl(c) >= SLOT2_LVL and meta_k() > 0.0


func wing_ok(c: String, t: String) -> bool:
	return not WING_UNLOCK.has(t) or meta_k() <= 0.0 or crew_lvl(c) >= int(WING_UNLOCK[t])


## Выбор в ветке оружия: "a" / "b" / ""
func wbranch(w: String, tier: int) -> String:
	if meta_k() <= 0.0 or not data["weapons"].has(w):
		return ""
	var v := String(data["weapons"][w].get("t%d" % tier, ""))
	return "" if v == "?" else v


## Множитель ветки оружия по ключу (dmg, range, cd, spd, blast_r, fuse, auto_r)
func wk(w: String, key: String) -> float:
	if not WBRANCH.has(w):
		return 1.0
	var k := 1.0
	for tier in [1, 2]:
		var ch := wbranch(w, tier)
		if ch == "":
			continue
		var eff: Dictionary = WBRANCH[w][tier - 1][0 if ch == "a" else 1][2]
		if eff.has(key):
			k *= lerpf(1.0, float(eff[key]), meta_k())
	return k


func skills(c: String) -> Array:
	var s: Array = cls(c)["skills"]
	var a: String = s[0] if skill_unlocked(c, s[0]) else PlaneClasses.CLASS_SKILLS[c][0]
	var b: String = s[1] if (s.size() > 1 and s[1] != "" and s[1] != a and slot2_open(c) and skill_unlocked(c, s[1])) else ""
	return [a, b]


# ---------- покупки ----------

func can_buy_node(c: String, id: String) -> bool:
	var lv := node(c, id)
	return lv < 5 and parts() >= int(NODE_COST[lv])


func buy_node(c: String, id: String) -> bool:
	if not can_buy_node(c, id):
		return false
	data["parts"] = parts() - int(NODE_COST[node(c, id)])
	cls(c)["nodes"][id] = node(c, id) + 1
	save()
	return true


func can_buy_plane2(c: String) -> bool:
	return not bool(cls(c)["plane2"]) and parts() >= PLANE2_COST and crew_lvl(c) >= PLANE2_CREW


func buy_plane2(c: String) -> bool:
	if not can_buy_plane2(c):
		return false
	data["parts"] = parts() - PLANE2_COST
	cls(c)["plane2"] = true
	save()
	return true


func tier_state(w: String, tier: int) -> String:
	return String(data["weapons"][w].get("t%d" % tier, ""))


func can_pick_tier(w: String, tier: int) -> bool:
	if tier == 2 and tier_state(w, 1) == "":
		return false
	return tier_state(w, tier) == "" and parts() >= int(TIER_COST[tier - 1])


func pick_tier(w: String, tier: int, opt: String) -> bool:
	if not can_pick_tier(w, tier):
		return false
	data["parts"] = parts() - int(TIER_COST[tier - 1])
	data["weapons"][w]["t%d" % tier] = opt
	save()
	return true


## Переиграть ступень: выбор сбрасывается, ступень остаётся оплаченной — следующий выбор бесплатный
func redo_tier(w: String, tier: int) -> bool:
	if tier_state(w, tier) == "" or parts() < int(REDO_COST[tier - 1]):
		return false
	data["parts"] = parts() - int(REDO_COST[tier - 1])
	data["weapons"][w]["t%d" % tier] = "?" # оплачено, выбор не сделан
	save()
	return true


func choose_paid(w: String, tier: int, opt: String) -> void:
	if tier_state(w, tier) == "?":
		data["weapons"][w]["t%d" % tier] = opt
		save()


func toggle_perk(c: String, id: String) -> void:
	var perks: Array = cls(c)["perks"]
	if perks.has(id):
		# снимаем и вторую ступень той же ветки
		for br in PERKS[c]:
			if br[1][0][0] == id and perks.has(br[1][1][0]):
				perks.erase(br[1][1][0])
		perks.erase(id)
	else:
		if perk_points(c) <= 0:
			return
		for br in PERKS[c]:
			if br[1][1][0] == id:
				if crew_lvl(c) < PERK_T2_LVL or not perks.has(br[1][0][0]):
					return
		perks.append(id)
	save()


func set_skill(c: String, slot: int, sk: String) -> void:
	var s: Array = cls(c)["skills"]
	while s.size() < 2:
		s.append("")
	if slot == 1 and s[0] == sk:
		s[0] = s[1]
	if slot == 0 and s[1] == sk:
		s[1] = s[0]
	s[slot] = sk
	save()


func next_callsign(c: String) -> void:
	var arr: Array = CALLSIGNS[c]
	var i := arr.find(cls(c)["callsign"])
	cls(c)["callsign"] = arr[(i + 1) % arr.size()]
	save()


## Самая дешёвая доступная покупка класса — подсказка на экране итогов
func hint_buy(c: String) -> String:
	var best := ""
	var price := 1 << 30
	for id in NODE_ORDER:
		var lv := node(c, id)
		if lv < 5 and int(NODE_COST[lv]) <= parts() and int(NODE_COST[lv]) < price:
			price = int(NODE_COST[lv])
			best = "%s ур. %d (%d)" % [NODES[id]["title"], lv + 1, price]
	if can_buy_plane2(c) and PLANE2_COST < price:
		price = PLANE2_COST
		best = "Самолёт ур. 2 (%d)" % PLANE2_COST
	if can_promote(c) and promote_cost(crew_lvl(c) + 1) < price:
		best = "Повысить в звании до ур. %d (%d)" % [crew_lvl(c) + 1, promote_cost(crew_lvl(c) + 1)]
	return best


func any_purchase() -> bool:
	for c in PlaneClasses.LIST:
		if hint_buy(c) != "" or perk_points(c) > 0:
			return true
	return false


# ---------- начисление за вылет ----------

func award_run(s: Dictionary) -> Dictionary:
	var c: String = s["cls"]
	var out := {"parts_before": parts(), "lvl_before": crew_lvl(c), "xp_lines": [], "unlocked": [], "short": false}
	var rt: float = s["run_time"]
	if rt < 30.0:
		out["short"] = true
		out["parts_add"] = 0
		out["wage"] = 0
		out["xp_add"] = 0
		out["parts_after"] = parts()
		out["lvl_after"] = out["lvl_before"]
		return out
	var wage := WAGE
	var add := int(s["parts_kept"]) + wage
	data["parts"] = parts() + add
	data["parts_earned_total"] = int(data["parts_earned_total"]) + add
	data["sorties"] = int(data["sorties"]) + 1
	var mins := rt / 60.0
	var lines: Array = [
		["В воздухе %d:%02d" % [int(rt) / 60, int(rt) % 60], int(round(20.0 * mins))],
		["Уровень пилота %d" % int(s["level"]), 5 * int(s["level"])],
	]
	if int(s["bosses"]) > 0:
		lines.append(["Асы ×%d" % int(s["bosses"]), 60 * int(s["bosses"])])
	if int(s["activities"]) > 0:
		lines.append(["Активности ×%d" % int(s["activities"]), 20 * int(s["activities"])])
	var sum := 0
	for l in lines:
		sum += int(l[1])
	if s["outcome"] == "dead":
		var cut := -int(round(sum * 0.25))
		lines.append(["Гибель ×0,75", cut])
		sum += cut
	var cm: float = s.get("continue_mult", 1.0)
	if cm > 1.0:
		# 3.4: множитель продолжения — только к доле опыта, заработанной после 15:00 (раньше — ко всему вылету)
		var bonus := int(round(sum * (cm - 1.0) * maxf(0.0, rt - 900.0) / maxf(rt, 1.0)))
		out["xp_continue"] = bonus
		lines.append(["Продолжение ×%.1f" % cm, bonus])
		sum += bonus
	lines.append(["За вылет", 30])
	sum += 30
	var xp_before := int(cls(c)["crew_xp"])
	cls(c)["crew_xp"] = xp_before + sum
	out["xp_lines"] = lines
	out["xp_add"] = sum
	out["xp_before"] = xp_before
	out["parts_add"] = add
	out["wage"] = wage
	out["parts_after"] = parts()
	out["lvl_after"] = crew_lvl(c)
	# 3.5: уровень больше не растёт сам — опыт открывает звание, покупка в ангаре
	out["xp_lvl_before"] = xp_lvl_of(xp_before)
	out["xp_lvl"] = xp_lvl(c)
	if promote_ready(c):
		out["promote"] = [crew_lvl(c) + 1, promote_cost(crew_lvl(c) + 1)]
	out["hint_buy"] = hint_buy(c)
	save()
	return out


# ---------- применение к самолёту ----------

## В конце Player.setup(): узлы, экипаж, перки → mods / прочность. Всё × meta_k.
func apply(p: Player) -> void:
	var k := meta_k()
	if k <= 0.0:
		return
	var c := p.cls_id
	var L := crew_lvl(c) - 1
	var m: Dictionary = p.mods
	# узлы самолёта
	m["man_cd"] *= 1.0 - 0.04 * node(c, "frame") * k
	m["speed"] *= 1.0 + 0.02 * node(c, "engine") * k
	p.max_hp *= 1.0 + 0.05 * node(c, "armor") * k
	m["turn"] *= 1.0 + 0.03 * node(c, "wing") * k
	m["hp_dmg"] += 0.04 * node(c, "pylons") * k
	# экипаж
	match c:
		"fighter":
			m["turn"] *= 1.0 + 0.006 * L * k
			m["man_cd"] *= 1.0 - 0.006 * L * k
			m["s3_cd"] *= 1.0 - 0.006 * L * k
		"attacker":
			p.max_hp *= 1.0 + 0.007 * L * k
			m["turret_dmg"] *= 1.0 + 0.007 * L * k
		"bomber":
			p.max_hp *= 1.0 + 0.005 * L * k
			m["pickup"] *= 1.0 + 0.007 * L * k
			m["turret_rate"] *= 1.0 + 0.006 * L * k
	# черта позывного (плюс и минус)
	var tr: Dictionary = trait_of(c).get("mods", {})
	for key in tr:
		var v := lerpf(1.0, float(tr[key]), k)
		if key == "hp":
			p.max_hp *= v
		else:
			m[key] *= v
	# перки
	if has_perk(c, "f_msl1"):
		m["missile_dmg"] *= 1.1
	if has_perk(c, "f_msl2"): # 3.5: «Форсированный старт» вместо «Спаренного пуска»
		m["missile_spd"] *= 1.15
		m["msl_boost"] = 1.1
	if has_perk(c, "f_acro2"):
		m["roll_time"] += 0.2
		m["roll_cd"] -= 1.0
	if has_perk(c, "a_arm1"):
		m["taken_k"] *= 0.94
	if has_perk(c, "a_grd1"):
		m["ground_dmg"] *= 1.15
	if has_perk(c, "a_gun1"):
		m["servo_range"] *= 1.12
	if has_perk(c, "a_gun2"):
		m["servo_rate"] *= 1.15
	if has_perk(c, "b_aa1"):
		m["turret_rate"] *= 1.12
	if has_perk(c, "b_bmb1"):
		m["blast_r"] *= 1.1
	if has_perk(c, "b_bmb2"):
		m["s3_cd"] *= 0.88
	if has_perk(c, "b_wing1"):
		m["wing_hp"] *= 1.2
		m["wing_dmg"] *= 1.1
	p.hp = p.max_hp


## Окно эвакуации и радиус ворот (узел «Бак» — временный эффект)
func evac_window(c: String) -> float:
	return 60.0 + 6.0 * node(c, "tank") * meta_k()


func gate_r_k(c: String) -> float:
	return 1.0 + 0.05 * node(c, "tank") * meta_k()


# ---------- отладка (тестовая сборка) ----------

func debug_parts(n: int) -> void:
	data["parts"] = parts() + n
	save()


func debug_level(c: String) -> void:
	var lv := crew_lvl(c)
	if lv < CREW_CUM.size():
		cls(c)["crew_xp"] = maxi(int(cls(c)["crew_xp"]), int(CREW_CUM[lv]))
		cls(c)["crew_rank"] = lv + 1
	save()


func debug_all() -> void:
	for c in PlaneClasses.LIST:
		cls(c)["crew_xp"] = int(CREW_CUM[CREW_CUM.size() - 1])
		cls(c)["crew_rank"] = CREW_CUM.size()
	data["parts"] = parts() + 50000
	save()
