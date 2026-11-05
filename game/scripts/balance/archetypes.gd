class_name ArchBalance
extends RefCounted
## Archetypes with rule ranks (PG-11 part A, Б3, Kanta 05.11.2026 «Давай все предложения, которые ты рекомендуешь,
## сразу»). Every tag (`Prog.TAGS`) is an archetype the player sees in combat. Tag points from cards raise its rank at
## ARCH_AT; each rank changes a rule of how the plane fights, not only a number. The old «нашивки» (`Prog.PATCHES`,
## off since 3.2) are the first two ranks, except where their effect now lives in a synergy (`Cards.SYNERGIES`).
## Turrets stay a separate archetype from «Стрелок»: their points come from different cards (turret upgrades, servo,
## «Погонное кольцо») and only «Грач» and «Кит» carry turrets, so a merged archetype would fill twice as fast on them.
## Also the trade-off cards (Б4): a rare card with a plus and a minus, no module slot.
## Numbers are first guesses before the balance run (`tools/ci/balance.sh`). F1 toggle `build_arch` (0 — s15 rules).
## Plan: docs/superpowers/plans/2026-11-05-build-depth.md, part A. Pure data and rules; `Player` keeps the points,
## the combat code reads the rank through `Player.arch_rank`.

## Tag points for ranks I, II, III
const ARCH_AT := [4, 8, 12]
const MAX_RANK := 3

## Archetype per tag: `title` — name in combat; `ranks` — [I, II, III], each {`desc` full text (card, banner),
## `short` — pause screen line (≤ 36 characters)}
const DEFS := {
	"missiles": {"title": "Ракетчик", "ranks": [
		{"desc": "+10% урона ракет", "short": "+10% урона ракет"},
		{"desc": "20% шанс сразу пустить ракеты ещё раз", "short": "20%: второй пуск сразу"},
		{"desc": "Ракета помечает цель на 3 с: всё остальное оружие и звено бьют её на 20% сильнее", "short": "метка: остальным +20% урона"},
	]},
	"blast": {"title": "Бомбёр", "ranks": [
		{"desc": "Край взрыва бьёт на 50% (было 35%)", "short": "край взрыва 50%"},
		{"desc": "Взрыв сбивает одну вражескую ракету в своём радиусе", "short": "взрыв сбивает ракету"},
		{"desc": "Наземные цели, задетые взрывом, молчат 1,5 с", "short": "взрыв глушит землю 1,5 с"},
	]},
	"kinetic": {"title": "Стрелок", "ranks": [
		{"desc": "+10% урона пуль по целям с прочностью больше половины", "short": "+10% по целым целям"},
		{"desc": "Снаряды курсовой пушки пробивают ещё 1 цель", "short": "пушка пробивает 1 цель"},
		{"desc": "Каждый 5-й снаряд пушки фугасный (урон ×3, взрыв 60 пикс.); «обороты» ручного огня растут вдвое быстрее", "short": "5-й снаряд фугасный"},
	]},
	"turrets": {"title": "Турельщик", "ranks": [
		{"desc": "+10% дальности турелей", "short": "+10% дальности турелей"},
		{"desc": "Раз в 2,5 с турели сбивают вражеские пули в 110 пикс. от самолёта", "short": "сбивают пули рядом"},
		{"desc": "Каждая 4-я очередь турели трассирующая: пробивает всё на линии 650 пикс., урон ×1,5", "short": "4-я очередь пробивает всё"},
	]},
	"wing": {"title": "Командир звена", "ranks": [
		{"desc": "Сбитый ведомый возвращается за 12 с (было 20)", "short": "ведомый вернётся за 12 с"},
		{"desc": "Ведомые: +30% урона и прочности", "short": "ведомые +30%"},
		{"desc": "+1 ведомый сверх лимита класса (если звено уже полное — ведомые ещё +30% урона)", "short": "+1 ведомый сверх лимита"},
	]},
	"maneuver": {"title": "Манёвренный", "ranks": [
		{"desc": "Перезарядка уклонения −1 с", "short": "уклонение −1 с"},
		{"desc": "2 с после уклонения или форсажа: +20% урона всему", "short": "после манёвра +20% урона"},
		{"desc": "Уклонение или форсаж вдвое сокращают перезарядку всех подвесов (не чаще раза в 3 с)", "short": "манёвр перезаряжает подвесы"},
	]},
	"armor": {"title": "Броненосец", "ranks": [
		{"desc": "−8% входящего урона", "short": "−8% входящего урона"},
		{"desc": "Раз в 12 с сильный удар (больше 10% прочности) даёт 1 с неуязвимости", "short": "сильный удар: 1 с неуязвимости"},
		{"desc": "4 с без попаданий — корпус чинится на 0,6% в секунду", "short": "самопочинка 0,6%/с"},
	]},
}

## Rank effect numbers (read by the combat code)
const MSL_K := 1.1            # I: missile damage
const MSL_AGAIN := 0.2        # II: chance of an immediate second launch
const MARK_TIME := 3.0        # III: seconds a missile mark lasts
const MARK_K := 1.2           # III: damage of every non-missile source on a marked target
const BLAST_EDGE := 0.5       # I: share of the damage at the blast edge (base 0.35)
const BLAST_SILENCE := 1.5    # III: seconds a ground target hit by a blast stays silent
const KIN_K := 1.1            # I: bullets on targets above half HP (course gun gets half of the bonus)
const KIN_PIERCE := 1         # II: extra targets a course-gun shell goes through
const KIN_HE_EVERY := 5       # III: every n-th course-gun shell is HE
const KIN_HE_K := 3.0
const KIN_HE_R := 60.0
const KIN_REV_K := 2.0        # III: «обороты» step multiplier
const TUR_RANGE := 1.1        # I
const TUR_CLEAR_CD := 2.5     # II: seconds between bullet sweeps
const TUR_CLEAR_R := 110.0
const TUR_TRACER_EVERY := 4   # III
const TUR_TRACER_LEN := 650.0
const TUR_TRACER_K := 1.5
const WING_BACK := 12.0       # I: seconds until a downed wingman returns (base 20)
const WING_BACK_BASE := 20.0
const WING_K := 1.3           # II: wingmen damage and HP; III: damage again when the flight is full
const MAN_ROLL_CD := 1.0      # I: dodge cooldown, s
const MAN_BUFF_K := 1.2       # II: damage during the 2 s after a manoeuvre
const MAN_BUFF_T := 2.0
const MAN_RELOAD_K := 0.5     # III: hardpoint cooldown left after a manoeuvre
const MAN_RELOAD_CD := 3.0
const ARMOR_K := 0.92         # I: incoming damage
const ARMOR_INV := 1.0        # II
const ARMOR_INV_CD := 12.0
const ARMOR_REGEN := 0.006    # III: share of max HP per second
const ARMOR_REGEN_AFTER := 4.0


## Rank 0…3 for `pts` tag points
static func rank(pts: int) -> int:
	var r := 0
	for at: int in ARCH_AT:
		if pts >= at:
			r += 1
	return r


## Points of the next rank, or -1 at rank III
static func next_at(pts: int) -> int:
	for at: int in ARCH_AT:
		if pts < at:
			return at
	return -1


## Ranks crossed going from `before` to `after` points, in order (for banners and telemetry)
static func ranks_crossed(before: int, after: int) -> Array:
	var out: Array = []
	for r in range(rank(before) + 1, rank(after) + 1):
		out.append(r)
	return out


## Up to `n` tags with points, most points first; ties keep `order` (the tag order of `Prog.TAG_ORDER`)
static func top(tags: Dictionary, order: Array, n: int) -> Array:
	var have: Array = order.filter(func(t): return int(tags.get(t, 0)) > 0)
	var idx := {}
	for i in order.size():
		idx[order[i]] = i
	have.sort_custom(func(a, b):
		var pa := int(tags.get(a, 0))
		var pb := int(tags.get(b, 0))
		return pa > pb if pa != pb else int(idx[a]) < int(idx[b]))
	return have.slice(0, n)


## Card line: «▲ Стрелок 5 → 6 (ранг II на 8)»; reaching a rank — «▲ Стрелок 7 → 8: ранг II!»; at rank III — no
## rank part. Russian template; the caller translates it (Loc.t) before the numbers go in.
static func hint_parts(pts: int, add: int) -> Dictionary:
	var after := pts + add
	var r_after := rank(after)
	if r_after > rank(pts):
		return {"kind": "reach", "rank": r_after}
	var nx := next_at(after)
	if nx < 0:
		return {"kind": "max", "rank": r_after}
	return {"kind": "next", "rank": r_after + 1, "at": nx}


## Which tag of a card to hint: the one that reaches a rank with this card, else the one closest to its next rank
## (fewest points missing), ties by order in `tags`; tags already at rank III last. "" when `tags` is empty.
static func hint_tag(points: Dictionary, tags: Array, add: int) -> String:
	var best := ""
	var best_gap := 1 << 30
	for t: String in tags:
		var pts := int(points.get(t, 0))
		var nx := next_at(pts)
		var gap := (1 << 29) if nx < 0 else maxi(0, nx - pts - add)
		if gap < best_gap:
			best_gap = gap
			best = t
	return best


# ---------- Б4: trade-off cards ----------

## From this pilot level, at most TRADE_MAX per sortie, each id once. `mods` — multipliers on `Player.mods`
## (`hp` — max HP); `plus` / `minus` — card text (two colours on the card).
const TRADE_LEVEL := 10
const TRADE_MAX := 2
const TRADE_W := 0.6   # weight in the card pool (a module card is 1.5)
const TRADES := {
	"trade_bare": {"title": "Без брони", "plus": "+25% урона всему оружию", "minus": "ремонт вдвое слабее",
		"mods": {"dmg_all": 1.25, "heal_k": 0.5}},
	"trade_msl": {"title": "Фанатик ракет", "plus": "ракеты: +40% урона", "minus": "курсовая пушка: −50% урона",
		"mods": {"missile_dmg": 1.4, "gun_dmg": 0.5}},
	"trade_light": {"title": "Облегчённый планер", "plus": "+15% скорости, +10% разворота", "minus": "−20% прочности",
		"mods": {"speed": 1.15, "turn": 1.1, "hp": 0.8}},
	"trade_ammo": {"title": "Двойной боезапас", "plus": "перезарядка подвесов −20%", "minus": "−12% скорости",
		"mods": {"hp_cd": 0.8, "speed": 0.88}},
}
## Floors the trade-offs respect: reload as `Cards.RELOAD_FLOOR` (EX-01); HP never below this share of the class base
const HP_FLOOR := 0.5


## May trade card `id` come now: level, how many trade-offs this sortie, whether this one was taken, and for
## «Двойной боезапас» whether the reload is above the floor (else its plus is lost)
static func trade_ok(id: String, level: int, taken: Dictionary, hp_cd: float, reload_floor: float) -> bool:
	if not TRADES.has(id) or level < TRADE_LEVEL or int(taken.get(id, 0)) > 0:
		return false
	var n := 0
	for t: String in TRADES:
		n += int(taken.get(t, 0))
	if n >= TRADE_MAX:
		return false
	if id == "trade_ammo" and hp_cd <= reload_floor + 0.001:
		return false
	return true


## `mods` after trade card `id`: multipliers applied, reload kept at or above `reload_floor`. Returns a new dictionary;
## the key "hp" is the max-HP multiplier for the caller (it is not a `Player.mods` key).
static func trade_mods(mods: Dictionary, id: String, reload_floor: float) -> Dictionary:
	var out := mods.duplicate()
	var d: Dictionary = TRADES[id]["mods"]
	for k: String in d:
		out[k] = float(out.get(k, 1.0)) * float(d[k])
	if out.has("hp_cd"):
		out["hp_cd"] = maxf(reload_floor, float(out["hp_cd"]))
	return out


## Wingman limit: the class limit capped at `wing_max` (`Cards.WING_MAX`, правка 3.5 п. 24); «Командир звена» III
## adds one over the class limit, still within `wing_max`
static func wing_limit(class_limit: int, wing_max: int, wing_rank: int) -> int:
	return mini(wing_max, class_limit + (1 if wing_rank >= 3 else 0))


## «Командир звена» III with a flight that is full anyway (class limit already at `wing_max`): the rank gives
## wingmen damage instead of a slot
static func wing_full(class_limit: int, wing_max: int) -> bool:
	return class_limit >= wing_max
