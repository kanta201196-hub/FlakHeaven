class_name Modernizations
extends RefCounted
## Second modernizations of the weapons and the first ones for `srm`, `agm`, `hebomb` (PG-06 PR 2, Kanta
## 2026-10-31). A modernization is the end form of a hardpoint weapon: weapon level 5 + catalyst modules,
## from `Prog.EVO_TIME`. The classic ones stay in `Prog.EVOS` (id = weapon id, models and hangar views key on
## them); the ones here have their own ids. Every pool weapon in stage 1 now has two recipes with different
## catalysts: whichever is completed first is offered, both ready — both cards, the player picks one.
## Proposal: docs/progression/upgrade-variety-2026-10-31.md (option 2); plan:
## docs/superpowers/plans/2026-10-31-weapon-profiles.md. Numbers are first guesses before the balance run.

## One entry per modernization: `weapon` — the hardpoint weapon it replaces; `title`, `desc` — player text
## (Loc.t at draw time); `cat` — catalyst modules and how many of each; the rest is read by the firing code:
## `dmg` — fixed damage per missile / rocket (scaled by rarity, class, «Э+», like `Prog.EVOS`), or `dmg_k` —
## factor on the weapon's level-5 damage; `cd` — fixed reload, s (replaces the level growth); `count` — missiles
## per volley for the whole group (`aam`, `srm`) or rockets per slot (`rockets`); `retarget` — extra new targets
## after a kill; `turn` — homing turn multiplier; `dodge` — a volley on every dodge roll; `intercept` — radius,
## px, of enemy missiles shot down before the volley; `splash`, `splash_k` — burst radius and neighbours' share;
## `armor_k` — extra damage to armored enemies; `split`, `split_k` — submunitions over the target;
## `wave_r`, `wave_k`, `silence` — HE bomb shockwave radius, its damage share, and seconds the AA there is quiet;
## `fire_t`, `fire_k`, `fire_r_k` — burning pool after the HE bomb: seconds, damage per second as a share of the
## bomb damage, radius as a share of the blast.
const DEFS := {
	"aam_swarm": {"weapon": "aam", "title": "«Стая»", "cat": {"msl_motor": 2},
		"desc": "4 лёгкие ракеты каждые 3 с, урон 45; сбив цель, каждая сама ищет новую, до 2 раз",
		"dmg": 45.0, "cd": 3.0, "count": 4, "retarget": 2},
	"rockets_hammer": {"weapon": "rockets", "title": "«Молот»", "cat": {"warhead": 2},
		"desc": "С каждой точки 2 тяжёлые ракеты: урон 80, радиус 90, по броне ещё ×1,3",
		"dmg": 80.0, "count": 2, "splash": 90.0, "armor_k": 1.3},
	"srm_hornets": {"weapon": "srm", "title": "«Шершни»", "cat": {"roll": 2},
		"desc": "Залп из 4 ракет каждые 3 с и на каждое уклонение; доворот вдвое круче",
		"dmg_k": 1.0, "cd": 3.0, "count": 4, "turn": 2.0, "dodge": true},
	"srm_sentry": {"weapon": "srm", "title": "«Сторож»", "cat": {"armor": 2},
		"desc": "Каждый пуск сначала сбивает вражеские ракеты в 450 пикс. (по одной с точки), затем бьёт самолёты; урон +10%",
		"dmg_k": 1.1, "intercept": 450.0},
	"agm_sledge": {"weapon": "agm", "title": "«Кувалда»", "cat": {"warhead": 2},
		"desc": "Одна сверхтяжёлая ракета раз в 8 с: урон ×1,7, взрыв 160 пикс., по броне ещё ×1,5",
		"dmg_k": 1.7, "cd": 8.0, "splash": 160.0, "splash_k": 0.6, "armor_k": 1.5},
	"agm_cassette": {"weapon": "agm", "title": "«Кассета»", "cat": {"frag": 2},
		"desc": "Над целью делится на 6 суббоеприпасов по соседним наземным целям (по 40 % урона)",
		"dmg_k": 1.0, "split": 6, "split_k": 0.4},
	"hebomb_quake": {"weapon": "hebomb", "title": "«Землетрясение»", "cat": {"frag": 2},
		"desc": "Взрыв даёт ударную волну 300 пикс.: ещё 35 % урона по земле, ПВО в ней молчит 2 с",
		"dmg_k": 1.0, "wave_r": 300.0, "wave_k": 0.35, "silence": 2.0},
	"hebomb_napalm": {"weapon": "hebomb", "title": "«Напалм»", "cat": {"warhead": 2},
		"desc": "На месте взрыва 6 с горит пятно: 15 % урона бомбы в секунду по наземным целям",
		"dmg_k": 1.0, "fire_t": 6.0, "fire_k": 0.15, "fire_r_k": 0.9},
}

static var _all: Dictionary = {}


## Every recipe by id: the classic `Prog.EVOS` ones (id = weapon id, "gun" included) and `DEFS`; each entry
## has `weapon`, `title`, `desc`, `cat`.
static func all() -> Dictionary:
	if _all.is_empty():
		for w: String in Prog.EVOS:
			var e: Dictionary = (Prog.EVOS[w] as Dictionary).duplicate()
			e["weapon"] = w
			_all[w] = e
		for id: String in DEFS:
			_all[id] = DEFS[id]
	return _all


## Weapon that recipe `id` modernizes ("" for an unknown id).
static func weapon_of(id: String) -> String:
	return String((all().get(id, {}) as Dictionary).get("weapon", ""))


## Recipe ids of weapon `w`, the classic one first; empty when the weapon has none.
static func ids_for(w: String) -> Array:
	var out: Array = []
	for id: String in all():
		if weapon_of(id) == w:
			out.append(id)
	return out


## Definition of recipe `id` (empty for an unknown id).
static func def(id: String) -> Dictionary:
	return all().get(id, {})


## Catalyst modules of recipe `id`: module id → count.
static func cat(id: String) -> Dictionary:
	return def(id).get("cat", {})


## True when `taken` (module id → cards taken) covers every catalyst of recipe `id`.
static func cat_done(id: String, taken: Dictionary) -> bool:
	var c := cat(id)
	if c.is_empty():
		return false
	for m: String in c:
		if int(taken.get(m, 0)) < int(c[m]):
			return false
	return true


## True for the recipes added here (not the classic `Prog.EVOS` ones).
static func is_new(id: String) -> bool:
	return DEFS.has(id)
