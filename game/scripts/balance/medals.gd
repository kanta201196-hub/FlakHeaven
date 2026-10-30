class_name MedalBalance
extends RefCounted
## Medals with small bonuses («Наградная планка»). Kanta 2026-10-27, option 1 of the card: achievements count over
## the whole game, each tier gives a small permanent bonus, all bonuses always on, a cap per kind of bonus so a player
## who has everything is about one crew level stronger, not a different game. Plan:
## docs/superpowers/plans/2026-10-27-medals.md. Pure data and rules here; the profile keeps the counters (Profile),
## the run feeds them (Medals), the hangar draws them (HudMedals).

## Frames of the pictures: round medal on a ribbon, gear-edged patch, shield, class badge, order (story)
const FRAMES := ["medal", "patch", "shield", "badge", "order"]
## Tier metals in order; a medal with one tier is gold
const METALS := ["bronze", "silver", "gold", "banner"]

## One entry per medal. `c` — lifetime counter (Profile), `t` — tier thresholds, `b` — bonus key (Player.mods-like,
## read by Profile.medal_bonus), `v` — bonus per tier (fraction, seconds or a count, by key), `f` — frame,
## `g` — group on the hangar tab, `hide` — hidden until earned (only a picture), `max` — the counter keeps the best
## single sortie instead of a sum. Titles and conditions are player text (Loc.t at draw time).
const LIST := [
	# --- бой ---
	{"id": "fighter", "g": "combat", "f": "medal", "title": "Истребитель", "c": "kills", "t": [1000, 10000, 50000, 200000],
		"b": "dmg", "v": [0.01, 0.02, 0.03, 0.04], "cond": "Сбить %s врагов", "bonus": "урон +%s"},
	{"id": "ace_hunter", "g": "combat", "f": "shield", "title": "Гроза асов", "c": "aces", "t": [10, 50, 200],
		"b": "boss_dmg", "v": [0.03, 0.06, 0.1], "cond": "Сбить %s асов", "bonus": "урон по асам +%s"},
	{"id": "fortress_fall", "g": "combat", "f": "medal", "title": "Крепость пала", "c": "fortresses", "t": [1, 10, 50],
		"b": "boss_parts", "v": [0.1, 0.2, 0.3], "cond": "Сбить «Крепость» %s раз", "bonus": "запчасти за асов +%s"},
	{"id": "stormer", "g": "combat", "f": "patch", "title": "Штурмовик", "c": "ground", "t": [500, 5000, 25000],
		"b": "ground_dmg", "v": [0.02, 0.04, 0.06], "cond": "Уничтожить %s наземных целей", "bonus": "урон по земле +%s"},
	{"id": "demolition", "g": "combat", "f": "medal", "title": "Подрывник", "c": "blast_dmg", "t": [1000000, 10000000, 50000000],
		"b": "blast", "v": [0.03, 0.06, 0.09], "cond": "Нанести %s урона взрывами", "bonus": "радиус взрывов +%s, урон взрывов +2/4/6 %%"},
	{"id": "marksman", "g": "combat", "f": "patch", "title": "Меткий глаз", "c": "gun_hits", "t": [50000, 500000],
		"b": "spread", "v": [0.05, 0.1], "cond": "Попасть из пушки %s раз", "bonus": "разброс пушки −%s"},
	{"id": "on_tail", "g": "combat", "f": "medal", "title": "На хвосте", "c": "tail_kills", "t": [500, 5000],
		"b": "tail_dmg", "v": [0.05, 0.1], "cond": "Сбить %s врагов с хвоста", "bonus": "урон «на хвосте» +%s"},
	{"id": "rocketeer", "g": "combat", "f": "patch", "title": "Ракетчик", "c": "msl_kills", "t": [1000, 10000],
		"b": "msl_cd", "v": [0.03, 0.06], "cond": "Сбить %s врагов ракетами", "bonus": "перезарядка ракет −%s"},
	{"id": "flak", "g": "combat", "f": "patch", "title": "Зенитчик", "c": "turret_dmg", "t": [1000000, 10000000],
		"b": "traverse", "v": [0.05, 0.1], "cond": "Нанести %s урона турелями", "bonus": "поворот турелей +%s"},
	{"id": "leader", "g": "combat", "f": "medal", "title": "Ведущий", "c": "wing_dmg", "t": [500000, 5000000],
		"b": "wing_hp", "v": [0.1, 0.2], "cond": "Ведомые наносят %s урона", "bonus": "прочность ведомых +%s"},
	{"id": "convoy", "g": "combat", "f": "patch", "title": "Колонна не прошла", "c": "convoys", "t": [10, 100],
		"b": "convoy_dmg", "v": [0.05, 0.1], "cond": "Разбить %s колонн", "bonus": "урон по колоннам +%s"},
	{"id": "no_retreat", "g": "combat", "f": "medal", "title": "Ни шагу назад", "c": "fort_clean", "t": [5, 25],
		"b": "fortress_slow", "v": [0.05, 0.1], "cond": "Сбить «Крепость», не дав ей ударить по базе, %s раз", "bonus": "«Крепость» медленнее на %s"},
	{"id": "umbrella", "g": "combat", "f": "patch", "title": "Под зонтиком", "c": "dive_dodged", "t": [50, 500],
		"b": "dive_time", "v": [0.1, 0.2], "cond": "Пройти нырком под %s ракетами", "bonus": "нырок длиннее на %s с"},
	{"id": "fort_area", "g": "combat", "f": "patch", "title": "Укрепрайон взят", "c": "fort_areas", "t": [5, 50],
		"b": "fort_area_dmg", "v": [0.05, 0.1], "cond": "Взять %s укрепрайонов", "bonus": "урон по укрепрайону +%s"},
	# --- выживание ---
	{"id": "tough", "g": "survive", "f": "medal", "title": "Живучий", "c": "evacs", "t": [1, 10, 30],
		"b": "hp", "v": [0.02, 0.04, 0.06], "cond": "Эвакуироваться %s раз", "bonus": "прочность +%s"},
	{"id": "close_call", "g": "survive", "f": "patch", "title": "На волоске", "c": "near_misses", "t": [1000, 10000, 50000],
		"b": "roll_time", "v": [0.1, 0.2, 0.3], "cond": "Пролететь «на волоске» %s раз", "bonus": "бочка: неуязвимость +%s с"},
	{"id": "decoy", "g": "survive", "f": "patch", "title": "Ловец ракет", "c": "flared", "t": [100, 1000],
		"b": "flare_cd", "v": [0.05, 0.1], "cond": "Увести ловушками %s ракет", "bonus": "перезарядка ловушек −%s"},
	{"id": "diver", "g": "survive", "f": "patch", "title": "Ныряльщик", "c": "dives", "t": [100, 1000],
		"b": "dive_cd", "v": [0.05, 0.1], "cond": "Нырнуть %s раз", "bonus": "перезарядка нырка −%s"},
	{"id": "mechanic", "g": "survive", "f": "patch", "title": "Механик", "c": "healed", "t": [10000, 100000],
		"b": "heal", "v": [0.05, 0.1], "cond": "Починить в воздухе %s прочности", "bonus": "ремонт +%s"},
	{"id": "long_haul", "g": "survive", "f": "patch", "title": "Дальний рейс", "c": "refuels", "t": [10, 100],
		"b": "fuel", "v": [0.03, 0.06], "cond": "Дозаправиться %s раз", "bonus": "топливо +%s"},
	# --- хозяйство и опыт ---
	{"id": "scrap", "g": "economy", "f": "patch", "title": "Сборщик мусора", "c": "parts", "t": [10000, 50000, 200000, 1000000],
		"b": "parts", "v": [0.02, 0.04, 0.06, 0.08], "cond": "Собрать %s запчастей", "bonus": "запчасти +%s"},
	{"id": "veteran", "g": "economy", "f": "medal", "title": "Ветеран", "c": "sorties", "t": [10, 50, 200],
		"b": "crew_xp", "v": [0.03, 0.06, 0.1], "cond": "Совершить %s вылетов", "bonus": "опыт экипажа +%s"},
	{"id": "quick", "g": "economy", "f": "patch", "title": "Быстрый взлёт", "c": "lvl20_early", "t": [5, 25],
		"b": "xp", "v": [0.02, 0.04], "cond": "Взять 20-й уровень к 5:00 %s раз", "bonus": "опыт в вылете +%s"},
	{"id": "collector", "g": "economy", "f": "medal", "title": "Коллекционер", "c": "cards_seen", "t": [-1],
		"b": "rerolls", "v": [1], "cond": "Взять каждую карточку хоть раз", "bonus": "+%s переброс карточек за вылет"},
	{"id": "synergy", "g": "economy", "f": "medal", "title": "Мастер связок", "c": "syn_seen", "t": [5, -1],
		"b": "bans", "v": [0, 1], "cond": "Открыть %s связок", "bonus": "+1 изгнание карточки за вылет (ступень 2)"},
	# --- классы и кампания ---
	{"id": "cls_fighter", "g": "class", "f": "badge", "title": "Крылья «Осы»", "c": "sorties_fighter", "t": [25, 100, 300],
		"b": "fighter_turn", "v": [0.02, 0.04, 0.06], "cond": "Совершить %s вылетов на «Осе»", "bonus": "разворот «Осы» +%s"},
	{"id": "cls_attacker", "g": "class", "f": "badge", "title": "Броня «Грача»", "c": "sorties_attacker", "t": [25, 100, 300],
		"b": "attacker_hp", "v": [0.02, 0.04, 0.06], "cond": "Совершить %s вылетов на «Граче»", "bonus": "прочность «Грача» +%s"},
	{"id": "cls_bomber", "g": "class", "f": "badge", "title": "Бомбы «Кита»", "c": "sorties_bomber", "t": [25, 100, 300],
		"b": "bomber_bombs", "v": [0.03, 0.06, 0.09], "cond": "Совершить %s вылетов на «Ките»", "bonus": "урон взрывов «Кита» +%s"},
	{"id": "op_pass", "g": "class", "f": "medal", "title": "Перевал", "c": "op_pass", "t": [1, 5, 20, 50],
		"b": "op_parts:pass", "v": [0.0, 0.0, 0.0, 0.03], "cond": "Пройти операцию «Перевал» %s раз", "bonus": "ступень 4: запчасти в этой операции +3 %%"},
	{"id": "op_riverbed", "g": "class", "f": "medal", "title": "Сухое русло", "c": "op_riverbed", "t": [1, 5, 20, 50],
		"b": "op_parts:riverbed", "v": [0.0, 0.0, 0.0, 0.03], "cond": "Пройти операцию «Сухое русло» %s раз", "bonus": "ступень 4: запчасти в этой операции +3 %%"},
	{"id": "op_forts", "g": "class", "f": "medal", "title": "Крепости", "c": "op_forts", "t": [1, 5, 20, 50],
		"b": "op_parts:forts", "v": [0.0, 0.0, 0.0, 0.03], "cond": "Пройти операцию «Крепости» %s раз", "bonus": "ступень 4: запчасти в этой операции +3 %%"},
	{"id": "op_sky", "g": "class", "f": "medal", "title": "Небо над Шахрисангом", "c": "op_sky", "t": [1, 5, 20, 50],
		"b": "op_parts:sky", "v": [0.0, 0.0, 0.0, 0.03], "cond": "Пройти операцию «Небо над Шахрисангом» %s раз", "bonus": "ступень 4: запчасти в этой операции +3 %%"},
	{"id": "grom", "g": "class", "f": "order", "title": "Гром жив", "c": "grom", "t": [1],
		"b": "", "v": [0], "cond": "Пройти историю «Где Гром?»", "bonus": ""},
	# --- шуточные и скрытые ---
	{"id": "ram", "g": "hidden", "f": "patch", "hide": true, "max": true, "title": "Таран", "c": "ram_drones", "t": [100],
		"b": "", "v": [0], "cond": "Сбить таранами 100 дронов за один вылет", "bonus": ""},
	{"id": "gun_only", "g": "hidden", "f": "patch", "hide": true, "title": "Только пушка", "c": "gun_only_evacs", "t": [1],
		"b": "", "v": [0], "cond": "Эвакуироваться без подвесного оружия", "bonus": ""},
	{"id": "last_breath", "g": "hidden", "f": "patch", "hide": true, "title": "На честном слове", "c": "last_breath", "t": [1],
		"b": "", "v": [0], "cond": "Эвакуироваться с прочностью ниже 5 %", "bonus": ""},
	{"id": "carousel", "g": "hidden", "f": "medal", "hide": true, "max": true, "title": "Карусель", "c": "kills_minute", "t": [300],
		"b": "", "v": [0], "cond": "Сбить 300 врагов за одну минуту", "bonus": ""},
	{"id": "clean_sky", "g": "hidden", "f": "patch", "hide": true, "max": true, "title": "Ни царапины", "c": "clean_s", "t": [300],
		"b": "", "v": [0], "cond": "5 минут подряд без урона после 10:00", "bonus": ""},
]

## Caps over all medals together (Kanta's proposal page): bonus group → most it may add
const CAPS := {"dmg": 0.1, "hp": 0.1, "parts": 0.1, "cd": 0.1}
## Which bonus keys share a cap: damage-like, HP-like, parts-like, cooldown-like
const CAP_OF := {"dmg": "dmg", "boss_dmg": "dmg", "ground_dmg": "dmg", "tail_dmg": "dmg", "convoy_dmg": "dmg",
	"fort_area_dmg": "dmg", "bomber_bombs": "dmg", "hp": "hp", "attacker_hp": "hp", "parts": "parts", "msl_cd": "cd",
	"flare_cd": "cd", "dive_cd": "cd"}
## «Подрывник»: explosion damage per tier alongside the radius (one medal, two numbers)
const BLAST_DMG := [0.02, 0.04, 0.06]
## Damage sources that count as explosions for «Подрывник» (Main.stats["dealt"] keys)
const BLAST_SRC := ["бомбы", "НАР", "УР В-З", "фугасные бомбы", "огненный ковёр", "разделяющаяся БЧ", "кассетные бомбы",  # i18n-skip
	"связка: огненный вал", "плазменная бомба"]  # i18n-skip
## Kill sources that count as missiles for «Ракетчик» (Enemy.last_src)
const MSL_SRC := ["ракеты В-В", "ракеты ближнего боя", "УР В-З", "разделяющаяся БЧ", "НАР"]  # i18n-skip


## The medal with id `id`, {} if none
static func by_id(id: String) -> Dictionary:
	for m: Dictionary in LIST:
		if m["id"] == id:
			return m
	return {}


## Tier reached by a counter value: 0 — none, 1 — first threshold … A threshold of −1 means «all of `of`»
## (collections: every card, every synergy), so `of` is the size of the full set.
static func tier(value: int, thresholds: Array, of := 0) -> int:
	var n := 0
	for th in thresholds:
		var need := of if int(th) < 0 else int(th)
		if need > 0 and value >= need:
			n += 1
		else:
			break
	return n


## Tiers of every medal for lifetime counters `c` (`sets` — sizes of the full card and synergy sets)
static func tiers(c: Dictionary, sets := {}) -> Dictionary:
	var out := {}
	for m: Dictionary in LIST:
		out[m["id"]] = tier(int(c.get(m["c"], 0)), m["t"], int(sets.get(m["c"], 0)))
	return out


## Sum of bonuses for tiers `t` (medal id → tier), each kind capped (CAPS): bonus key → value.
## Tier values are not cumulative: tier 3 of «Истребитель» gives +3 %, not 1+2+3.
static func bonuses(t: Dictionary) -> Dictionary:
	var out := {}
	var used := {}
	for m: Dictionary in LIST:
		var n := int(t.get(m["id"], 0))
		var key: String = m["b"]
		if n <= 0 or key == "":
			continue
		var v := float(m["v"][n - 1])
		if key == "blast":   # the radius is free; the damage half shares the dmg cap (review 2026-10-30, R-07)
			var room_d := float(CAPS["dmg"]) - float(used.get("dmg", 0.0))
			var bd := clampf(BLAST_DMG[n - 1], 0.0, maxf(room_d, 0.0))
			used["dmg"] = float(used.get("dmg", 0.0)) + bd
			out["blast_dmg"] = float(out.get("blast_dmg", 0.0)) + bd
		var cap_k: String = CAP_OF.get(key, "")
		if cap_k != "":
			var room := float(CAPS[cap_k]) - float(used.get(cap_k, 0.0))
			v = clampf(v, 0.0, maxf(room, 0.0))
			used[cap_k] = float(used.get(cap_k, 0.0)) + v
		out[key] = float(out.get(key, 0.0)) + v
	return out


## Medals whose tier went up between `before` and `after` (both medal id → tier): [[id, new tier], …] in LIST order
static func new_tiers(before: Dictionary, after: Dictionary) -> Array:
	var out := []
	for m: Dictionary in LIST:
		var a := int(after.get(m["id"], 0))
		if a > int(before.get(m["id"], 0)):
			out.append([m["id"], a])
	return out


## Adds one sortie's counters `run` to lifetime counters `c` in place: sums, or the best sortie for `max` medals
static func add_run(c: Dictionary, run: Dictionary) -> void:
	var maxed := {}
	for m: Dictionary in LIST:
		if m.get("max", false):
			maxed[m["c"]] = true
	for k in run:
		if maxed.has(k):
			c[k] = maxi(int(c.get(k, 0)), int(run[k]))
		else:
			c[k] = int(c.get(k, 0)) + int(run[k])


## Tally marks one sortie earns from its kill counters: each rival ace and each «Крепость» once (a fortress is a
## Boss too, so it must not be counted through a boss total as well — review 2026-10-30, R-01)
static func tally(counters: Dictionary) -> int:
	return int(counters.get("aces", 0)) + int(counters.get("fortresses", 0))


## Explosion damage of one sortie from its damage-by-source table
static func blast_of(dealt: Dictionary) -> int:
	var s := 0.0
	for k in BLAST_SRC:
		s += float(dealt.get(k, 0.0))
	return int(s)


## Most kills inside any 60 s window, from kill times `times` (sorted, seconds)
static func best_minute(times: Array) -> int:
	var best := 0
	var lo := 0
	for hi in times.size():
		while float(times[hi]) - float(times[lo]) > 60.0:
			lo += 1
		best = maxi(best, hi - lo + 1)
	return best


## Bonus keys counted in seconds and in pieces; the rest are fractions shown as percent
const SECONDS := ["dive_time", "roll_time"]
const PIECES := ["rerolls", "bans"]


## Picture metal of tier `n` for a medal with `count` tiers: "none" before the first, gold for a single-tier medal
static func metal(n: int, count: int) -> String:
	if n <= 0:
		return "none"
	return "gold" if count == 1 else String(METALS[mini(n, METALS.size()) - 1])


## Number for player text: 1 000, 10 000, 1 000 000 (thin groups like the rest of the result screen)
static func grouped(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## Value of a bonus for player text: "3 %", "0,2", "1"
static func value_text(key: String, v: float) -> String:
	if SECONDS.has(key):
		return ("%.1f" % v).replace(".", ",")
	if PIECES.has(key):
		return str(int(v))
	var pct := v * 100.0
	return ("%d %%" % int(round(pct))) if is_equal_approx(pct, round(pct)) else ("%.1f %%" % pct).replace(".", ",")
