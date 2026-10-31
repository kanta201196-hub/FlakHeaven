class_name WeaponProfiles
extends RefCounted
## Weapon profiles (PG-06, Kanta 2026-10-31): a fork in the weapon's growth. When a hardpoint weapon with
## profiles goes from level LEVEL - 1 to LEVEL, the upgrade card is an «or-or» screen of two profiles that
## change how the weapon fires (the third profile opens with tier THIRD_TIER of the weapon's hangar branch).
## The profile stays to the end of the sortie and into the modernization. Rule of the pair: the same damage
## per second on the typical target ±10 %, a different feel and a different enemy it is best against.
## Numbers are first guesses before the balance run (`tools/ci/balance.sh`, one pair at a time).
## Proposal: docs/progression/upgrade-variety-2026-10-31.md; plan: docs/superpowers/plans/2026-10-31-weapon-profiles.md.
## Pure data and rules; `Hardpoint` reads the multipliers, the firing code reads the behaviour keys,
## `Cards` builds the screen.

## Weapon level the fork comes at: the card that takes the weapon from LEVEL - 1 to LEVEL is the profile choice.
const LEVEL := 3
## Tier of the hangar weapon branch (`Profile.WBRANCH`) that unlocks the third profile.
const THIRD_TIER := 2

## One entry per profile: `title` and `desc` — player text (Loc.t at draw time); `vs` — the enemies it is best
## against (card line «Против кого»); `dmg`, `cd`, `range`, `spd` — multipliers on the weapon's numbers (missing
## = 1); the other keys are behaviour read by the firing code:
## `per_slot` — missiles per hardpoint slot; `splash` / `splash_k` — missile burst radius, px, and the share of
## the damage neighbours take; `turn` — homing turn multiplier; `life` — missile flight time, s; `intercept` —
## the launch goes at an enemy missile closer than this, px; `split` / `split_k` — submunitions over the target
## and their damage share; `armor_k` — extra damage to armored enemies; `antiradar` — radars and AA sites first;
## `extra` / `count` — rockets per slot added / fixed; `spread` — rocket half-cone, degrees; `ap` — rockets take
## armor as the guided missile does (×1.3); `burn` — rockets set the target on fire (incendiary ammo rules).
const DEFS := {
	"aam": {
		"pair": {"rank": "dmg", "title": "Двойной пуск", "desc": "С каждой точки две лёгкие ракеты по разным целям",
			"vs": "группы дронов и перехватчиков", "dmg": 0.55, "per_slot": 2},
		"reach": {"rank": "range", "title": "Дальний захват", "desc": "Захват цели с 1 500 пикс. (было 1 050), ракета на 30 % быстрее",
			"vs": "ракетоносцы и асы: удар первым, до их пуска", "dmg": 0.9, "range": 1.43, "spd": 1.3},
		"frag": {"rank": "splash", "title": "Осколочная", "desc": "Боевая часть рвётся облаком осколков: радиус 110 пикс., соседям 70 % урона",
			"vs": "плотные группы самолётов", "dmg": 0.85, "splash": 110.0, "splash_k": 0.7},
	},
	"srm": {
		"swarm": {"rank": "dmg", "title": "Рой", "desc": "С каждой точки три мини-ракеты по разным целям в 400 пикс.",
			"vs": "дроны", "dmg": 0.4, "range": 0.67, "per_slot": 3},
		"hound": {"rank": "turn", "title": "Гончая", "desc": "Доворот вдвое круче, дальность 800 пикс. (было 600)",
			"vs": "асы и перехватчики", "dmg": 0.85, "range": 1.33, "turn": 2.0, "life": 2.4},
		"guard": {"rank": "intercept", "title": "Перехватчик", "desc": "Если к вам идёт ракета ближе 300 пикс., пуск уходит по ней",
			"vs": "ракетоносцы и позиции ПВО", "dmg": 0.9, "intercept": 300.0},
	},
	"agm": {
		"cluster": {"rank": "split_k", "title": "Кассетная", "desc": "Над целью делится на 4 суббоеприпаса по соседним наземным целям (по 35 % урона, радиус 80)",
			"vs": "колонны и позиции ПВО", "split": 4, "split_k": 0.35},
		"bunker": {"rank": "armor_k", "title": "Бетонобой", "desc": "Один тяжёлый удар: урон ×1,6, по броне ещё ×1,5",
			"vs": "бункеры, бронетехника, «Крепость»", "dmg": 1.6, "armor_k": 1.5},
		"arm": {"rank": "dmg", "title": "Противорадарная", "desc": "Сама идёт на радар или установку ПВО с 1 400 пикс. (было 900)",
			"vs": "позиции ПВО и укрепрайоны", "range": 1.55, "antiradar": true},
	},
	"rockets": {
		"fan": {"rank": "dmg", "title": "Веер", "desc": "В залпе на две ракеты больше, конус 40°",
			"vs": "площадь: колонны, толпы дронов", "dmg": 0.75, "extra": 2, "spread": 20.0},
		"heat": {"rank": "dmg", "title": "Кумулятив", "desc": "Три тяжёлые ракеты в залпе, броня их не держит",
			"vs": "бронетехника, вертолёты, ЗРК", "dmg": 1.6, "count": 3, "ap": true},
		"inc": {"rank": "dmg", "title": "Зажигательные", "desc": "Поджигают цель: ещё 50 % урона за 2 с",
			"vs": "колонны и прочные наземные цели", "dmg": 0.8, "burn": true},
	},
}
## Profile ids per weapon in screen order; the last one is the third, opened by the hangar.
const ORDER := {
	"aam": ["pair", "reach", "frag"],
	"srm": ["swarm", "hound", "guard"],
	"agm": ["cluster", "bunker", "arm"],
	"rockets": ["fan", "heat", "inc"],
}
## PR 3 (Kanta 31.10, mastery 3b): after level 35 a weapon with a profile gets ranks of that profile instead of
## «Скорострел / Калибр»: each rank adds RANK_K to the profile's own feature (`rank` key of `DEFS`), up to
## `Cards.BRANCH_MAX` ranks. A factor the profile does not list (`dmg` of «Противорадарная») starts at 1.
const RANK_K := 0.12
## Player text of the ranked feature (Loc.t at draw time).
const RANK_TEXT := {
	"dmg": "урон", "range": "дальность захвата", "splash": "радиус осколков", "turn": "доворот",
	"intercept": "радиус перехвата", "split_k": "урон суббоеприпасов", "armor_k": "урон по броне",
}
## Factor keys that default to 1 when the profile does not list them.
const FACTOR_KEYS := ["dmg", "cd", "range", "spd"]

## Card colours by position on the screen (first, second, third profile).
const COLORS := ["missiles", "maneuver", "blast"]


## True when weapon `w` has profiles.
static func has(w: String) -> bool:
	return ORDER.has(w)


## Profile ids of weapon `w` in screen order (empty for a weapon without profiles).
static func ids(w: String) -> Array:
	return ORDER.get(w, [])


## Definition of profile `id` of weapon `w`; empty for an unknown pair.
static func def(w: String, id: String) -> Dictionary:
	return (DEFS.get(w, {}) as Dictionary).get(id, {})


## Multiplier `key` (dmg, cd, range, spd) of profile `id` of weapon `w`; 1 when missing or unknown.
static func k(w: String, id: String, key: String) -> float:
	return float(def(w, id).get(key, 1.0))


## Id of the third profile of weapon `w` (the one the hangar opens); "" without profiles.
static func third(w: String) -> String:
	var o := ids(w)
	return String(o[2]) if o.size() >= 3 else ""


## True when the next upgrade of weapon `w` at `level` with profile `profile` must be the profile choice.
static func due(level: int, profile: String, w: String) -> bool:
	return has(w) and profile == "" and level >= LEVEL - 1


## Profile ids offered on the screen: the first two, plus the third when `third_open` (hangar tier).
static func open_ids(w: String, third_open: bool) -> Array:
	var o := ids(w)
	return o if third_open or o.size() <= 2 else o.slice(0, 2)


## Behaviour value `key` of the profile of hardpoint weapon `w` (`default` when the profile has none).
static func val(w: String, id: String, key: String, default: Variant) -> Variant:
	return def(w, id).get(key, default)


## Feature that ranks of profile `id` of weapon `w` grow ("" for an unknown pair).
static func rank_key(w: String, id: String) -> String:
	return String(def(w, id).get("rank", ""))


## Profile `id` of weapon `w` at mastery `rank`: a copy of its definition with the ranked feature ×(1 + RANK_K × rank);
## rank 0 returns the definition itself, an unknown pair an empty dictionary.
static func ranked(w: String, id: String, rank: int) -> Dictionary:
	var d := def(w, id)
	if rank <= 0 or d.is_empty():
		return d
	var out := d.duplicate()
	var key := rank_key(w, id)
	if key != "":
		var base := float(d.get(key, 1.0 if key in FACTOR_KEYS else 0.0))
		out[key] = base * (1.0 + RANK_K * rank)
	return out
