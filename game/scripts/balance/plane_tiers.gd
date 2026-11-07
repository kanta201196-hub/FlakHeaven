class_name PlaneTiers
extends RefCounted
## Plane tiers 1–5 per class (PT-04, Kanta 06.11.2026 «Супер, запускай все в работу»). Plan and reasons:
## `docs/superpowers/plans/2026-11-06-plane-tiers.md` (§3.2–3.6). Tier 2 is the old plane 1 and tier 3 the old
## plane 2, unchanged, so a carried-over save flies the same; tier 1 is a new, simpler start plane; tiers 4–5 carry
## the experimental hardware (heavy hardpoint, future systems — stages C and D of the plan).
## Each tier keeps its own nodes from zero and has its own node catalog: one generation of hardware per tier, the
## same hangar places (frame, engine, …), so the third hardpoint group and the hangar layout stay keyed by place.
## Pure data and rules over plain values, so they are unit-tested without the profile (`tests/plane_tiers_test.gd`).
## Every number except the prices is a guess until measured in builds (CLAUDE.md rule 2).

const MAX := 5
## Demo (Kanta 06.11): tier 2 is the last playable tier; tiers 3–5 are shown locked
const DEMO_MAX := 2
## Parts per tier, Kanta 06.11 18:19 UTC
const COST := [0, 20000, 50000, 120000, 250000]
## Crew level needed per tier (guess)
const CREW := [0, 2, 4, 8, 12]
## Campaign operation (index in `Campaign.OPS`) that must be cleared per tier; -1 — none.
## Tier 2 after «Перевал» (Kanta 06.11), then one operation per tier
const GATE := [-1, 0, 1, 2, 3]
## Hull / speed / turn factor of the plane itself. Tier 3 keeps the old plane 2 step; tiers 4–5 get their own step
## after a measurement (plan §3.4, last paragraph), until then the tier 3 step
const BASE := [
	{"hp": 1.0, "speed": 1.0, "turn": 1.0},
	{"hp": 1.0, "speed": 1.0, "turn": 1.0},
	{"hp": 1.15, "speed": 1.05, "turn": 1.05},
	{"hp": 1.15, "speed": 1.05, "turn": 1.05},
	{"hp": 1.15, "speed": 1.05, "turn": 1.05},
]
## Model key a tier is drawn with (plan §3.5, stage B): every art path and per-model table is keyed
## `<class>_<model>` — battle and hangar GLBs `fh_battle_<class>_<model>.glb` / `fh_hangar_…`, the top-down sprite
## `art/planes/<class>_<model>.png`, and the mount, flame, livery, decal and camera tables. "1" and "2" are the old
## planes 1 and 2, now tiers 2 and 3 (their paths unchanged); "t1", "t4", "t5" are the new tier models.
## Tiers 4–5 borrow the tier 3 model until theirs ship: then add their table entries (`tests/model_tables_test.gd`
## lists the tables) and set MODEL to "t4" / "t5" and OWN_MODEL to true here.
const MODEL := ["t1", "1", "2", "2", "2"]
const OWN_MODEL := [true, true, true, false, false]
## Node price ladder of tier 2 (the old one, flights review 06.11) and the factor per tier
const NODE_COST := [160, 500, 1200, 2800, 5800]
const PRICE_K := [0.5, 1.0, 1.25, 1.5, 2.0]
## What a tier gives, one line for the hangar card (player text, Russian source of the .po keys)
const BLURB := [
	"простой и надёжный: меньше видов оружия, 4 узла до ур. 3",
	"больше видов оружия, 6 узлов до ур. 4, у «Кита» второй ведомый",
	"прочность +15%, скорость и разворот +5%, ★ +20%, +1 переброс, ступень 3 веток оружия, 7 узлов до ур. 5",
	"тяжёлый подвес для экспериментального оружия; новые узлы: энергоустановка, радар с АФАР",
	"★ +25%; внутренний отсек, компактный реактор; новые системы — в работе",
]
## Highest node level per tier
const CAP := [3, 4, 5, 5, 5]
## Hangar places in display order; a tier lists the ones it has
const PLACES := ["frame", "engine", "armor", "wing", "pylons", "tank", "avionics", "power"]
## Node level of the pylons place that opens the third hardpoint group (PG-01), on every tier
const GROUP3_LVL := 2
## Effect keys the game applies per node level: `Player.mods` keys, plus "hp" (hull) and "fuel" (tank volume).
## man_cd, speed, turn, hp_cd multiply (1 + v·lvl); hp_dmg adds v·lvl, as before tiers
const FX_KEYS := ["man_cd", "speed", "turn", "hp", "hp_dmg", "hp_cd", "fuel"]
const ADDITIVE := ["hp_dmg"]

## Node catalog per tier: place → {title, step (what one level gives, shown in the hangar), fx (applied per level),
## wip (the part of the step the game does not apply yet; shown as «в работе»), note}.
## A node whose whole step is still in work has empty fx and cannot be bought yet.
const NODES := {
	1: {
		"frame": {"title": "Клёпаный планер", "step": "перезарядка уклонения и форсажа −4%", "fx": {"man_cd": -0.04}},
		"engine": {"title": "Первый двигатель", "step": "скорость +2%", "fx": {"speed": 0.02}},
		"armor": {"title": "Бронеплиты", "step": "прочность +5%", "fx": {"hp": 0.05}},
		"pylons": {"title": "Пилоны", "step": "урон подвесов и турелей +4%", "fx": {"hp_dmg": 0.04},
			"note": "ур. 2 — третья группа подвеса"},
	},
	2: {
		"frame": {"title": "Планер", "step": "перезарядка уклонения и форсажа −4%", "fx": {"man_cd": -0.04}},
		"engine": {"title": "Двигатель", "step": "скорость +2%", "fx": {"speed": 0.02}},
		"armor": {"title": "Броня", "step": "прочность +5%", "fx": {"hp": 0.05}},
		"wing": {"title": "Крыло", "step": "разворот +3%", "fx": {"turn": 0.03}},
		"pylons": {"title": "Узлы подвеса", "step": "урон подвесов и турелей +4%", "fx": {"hp_dmg": 0.04},
			"note": "ур. 2 — третья группа подвеса"},
		"tank": {"title": "Топливный бак", "step": "объём бака +8% (≈ +43 с полёта)", "fx": {"fuel": 0.08}},
	},
	3: {
		"frame": {"title": "Композитный планер", "step": "перезарядка уклонения и форсажа −4%, прочность +2%",
			"fx": {"man_cd": -0.04, "hp": 0.02}},
		"engine": {"title": "Двигатель с форсажной камерой", "step": "скорость +2%, форсаж дольше на 10%",
			"fx": {"speed": 0.02}, "wip": "форсаж дольше"},
		"armor": {"title": "Композитная броня", "step": "прочность +5%, урон от ПВО −3%",
			"fx": {"hp": 0.05}, "wip": "урон от ПВО"},
		"wing": {"title": "Крыло с механизацией", "step": "разворот +3%", "fx": {"turn": 0.03}},
		"pylons": {"title": "Многозамковые держатели", "step": "урон подвесов и турелей +4%, перезарядка −2%",
			"fx": {"hp_dmg": 0.04, "hp_cd": -0.02}, "note": "ур. 2 — третья группа подвеса"},
		"tank": {"title": "Подвесные баки", "step": "объём бака +8%", "fx": {"fuel": 0.08}},
		"avionics": {"title": "Радар", "step": "дальность захвата +5%", "fx": {}, "wip": "дальность захвата"},
	},
	4: {
		"frame": {"title": "Малозаметный планер", "step": "ракеты врага захватывают вас на 6% дольше", "fx": {},
			"wip": "захват ракет врага"},
		"engine": {"title": "Управляемый вектор тяги", "step": "скорость +2%, разворот +2%",
			"fx": {"speed": 0.02, "turn": 0.02}},
		"armor": {"title": "Керамическая броня", "step": "прочность +6%", "fx": {"hp": 0.06}},
		"wing": {"title": "Крыло нового профиля", "step": "разворот +3%", "fx": {"turn": 0.03}},
		"pylons": {"title": "Тяжёлый подвес", "step": "ур. 1 открывает тяжёлый подвес, дальше урон экспериментального оружия +6%",
			"fx": {}, "wip": "тяжёлый подвес на ур. 4", "note": "ур. 2 — третья группа подвеса"},
		"avionics": {"title": "Радар с АФАР", "step": "дальность захвата +5%, поворот ракет +4%", "fx": {},
			"wip": "захват и поворот ракет"},
		"power": {"title": "Энергоустановка", "step": "урон лазеров и запас щитов +8%", "fx": {},
			"wip": "лазеры и щиты"},
	},
	5: {
		"frame": {"title": "Планер из метаматериалов", "step": "фазовый щит в бочке дольше", "fx": {},
			"wip": "фазовый щит"},
		"engine": {"title": "Адаптивный двигатель", "step": "скорость +2%, объём бака +6%",
			"fx": {"speed": 0.02, "fuel": 0.06}},
		"armor": {"title": "Активная защита", "step": "прочность +6%", "fx": {"hp": 0.06}},
		"pylons": {"title": "Внутренний отсек", "step": "урон подвесов и турелей +4%, перезарядка −3%",
			"fx": {"hp_dmg": 0.04, "hp_cd": -0.03}, "note": "ур. 2 — третья группа подвеса"},
		"avionics": {"title": "Сетевая авионика", "step": "ведомые +6% урона по вашей цели", "fx": {},
			"wip": "урон ведомых"},
		"power": {"title": "Компактный реактор", "step": "урон лазеров и запас щитов +8%, перезарядка новых систем −4%",
			"fx": {}, "wip": "лазеры, щиты, новые системы"},
	},
}


static func _i(tier: int) -> int:
	return clampi(tier, 1, MAX) - 1


## Parts to buy `tier` (0 for tier 1)
static func cost(tier: int) -> int:
	return int(COST[_i(tier)])


## Crew level `tier` needs
static func crew(tier: int) -> int:
	return int(CREW[_i(tier)])


## Index of the campaign operation that must be cleared before `tier` is sold; -1 — none
static func gate_op(tier: int) -> int:
	return int(GATE[_i(tier)])


## Base hull / speed / turn factor of `tier` (keys hp, speed, turn)
static func base(tier: int) -> Dictionary:
	return BASE[_i(tier)]


## Model key ("t1", "1", "2", …) that draws `tier`: art, hangar model, mounts and sprites are keyed by it
static func model(tier: int) -> String:
	return String(MODEL[_i(tier)])


## Every model key some tier is drawn with, in tier order, each once: what benches and the self-check walk over and
## what every per-model table must cover
static func model_keys() -> Array[String]:
	var out: Array[String] = []
	for k in MODEL:
		if not out.has(String(k)):
			out.append(String(k))
	return out


## First tier drawn with model `key` (the tier the model was made for; 0 for an unknown key): the self-check and
## benches show a model with that tier's weapons
static func model_tier(key: String) -> int:
	var i := MODEL.find(key)
	return i + 1 if i >= 0 else 0


## Art key of class `cls` drawn with model `key` («fighter_t1», «bomber_2»): the basename of its GLBs and sprite and
## the key of every per-model table
static func art_key(cls: String, key: String) -> String:
	return "%s_%s" % [cls, key]


## One line on what `tier` gives (hangar card)
static func blurb(tier: int) -> String:
	return String(BLURB[_i(tier)])


## Whether `tier` carries the heavy hardpoint for experimental weapons (the old plane 2 rule moved to tier 4, plan
## §3.2; stage C ties it to the tier 4 «Тяжёлый подвес» node)
static func heavy(tier: int) -> bool:
	return tier >= 4


## Whether `tier` is drawn with a model of its own (false — borrowed, the hangar says «модель в работе»)
static func has_own_model(tier: int) -> bool:
	return bool(OWN_MODEL[_i(tier)])


## Why `tier` cannot be bought now: "demo", "prev" (previous tier not owned), "gate" (operation not cleared),
## "crew", "parts", "owned", "none" (tier 1 or out of range); "" — it can be bought. Checked in this order so the
## hangar names the first thing to do.
static func lock_reason(tier: int, owned: Array, parts: int, crew_lvl: int, gate_cleared: bool, demo: bool) -> String:
	if tier < 2 or tier > MAX:
		return "none"
	if owned.has(tier):
		return "owned"
	if demo and tier > DEMO_MAX:
		return "demo"
	if not owned.has(tier - 1):
		return "prev"
	if not gate_cleared:
		return "gate"
	if crew_lvl < crew(tier):
		return "crew"
	if parts < cost(tier):
		return "parts"
	return ""


## Whether `tier` can be bought with these plain values (see `lock_reason`)
static func can_buy(tier: int, owned: Array, parts: int, crew_lvl: int, gate_cleared: bool, demo: bool) -> bool:
	return lock_reason(tier, owned, parts, crew_lvl, gate_cleared, demo) == ""


## Hangar places of `tier`, in display order
static func nodes(tier: int) -> Array:
	var d: Dictionary = NODES[_i(tier) + 1]
	return PLACES.filter(func(p): return d.has(p))


## Highest node level on `tier`
static func cap(tier: int) -> int:
	return int(CAP[_i(tier)])


## Price of node level `lvl` + 1 on `tier` (`lvl` — the level owned now, 0-based), rounded to 10 parts
static func node_cost(tier: int, lvl: int) -> int:
	return int(round(float(NODE_COST[clampi(lvl, 0, NODE_COST.size() - 1)]) * float(PRICE_K[_i(tier)]) / 10.0)) * 10


## Catalog entry of place `id` on `tier`; empty when the tier has no such node
static func node_def(tier: int, id: String) -> Dictionary:
	return (NODES[_i(tier) + 1] as Dictionary).get(id, {})


## Effects of one level of node `id` on `tier` (FX_KEYS → value); empty when none works yet
static func fx(tier: int, id: String) -> Dictionary:
	return node_def(tier, id).get("fx", {})


## Whether node `id` on `tier` can be bought: it exists and some of its step already works
static func node_live(tier: int, id: String) -> bool:
	return not fx(tier, id).is_empty()


## Factor of effect `key` from node levels `levels` (place → level) on `tier`, scaled by `k` (meta_k):
## (1 + v·lvl·k) multiplied over nodes; for ADDITIVE keys the sum v·lvl·k
static func fx_total(tier: int, levels: Dictionary, key: String, k: float) -> float:
	var add := ADDITIVE.has(key)
	var out := 0.0 if add else 1.0
	for id in nodes(tier):
		var v := float(fx(tier, id).get(key, 0.0))
		if v == 0.0:
			continue
		var t := v * float(mini(int(levels.get(id, 0)), cap(tier))) * k
		out = out + t if add else out * (1.0 + t)
	return out


## Save keys of the two-plane game moved to tiers: old plane 1 → tier 2, old plane 2 → tier 3, tier 1 free for
## everyone. Returns only the new keys (tiers, plane_sel, nodes_t*, kit_t*) for the keys `src` has. Decals stay keyed
## by model (`decals1` / `decals2`, `Profile.decal_key`): they sit on the model's surface, and tiers 2 and 3 keep
## those models
static func migrate_class(src: Dictionary) -> Dictionary:
	var had2 := bool(src.get("plane2", false))
	var out := {"tiers": [1, 2, 3] if had2 else [1, 2]}
	out["plane_sel"] = 3 if had2 and int(src.get("plane_sel", 2)) == 2 else 2
	for pair in [["nodes", "nodes_t2"], ["nodes2", "nodes_t3"], ["kit1", "kit_t2"], ["kit2", "kit_t3"]]:
		if src.has(pair[0]):
			out[pair[1]] = src[pair[0]]
	return out
