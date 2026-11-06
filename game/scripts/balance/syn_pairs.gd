class_name SynPairs
extends RefCounted
## Synergies from two different things (PG-11 part B1, Kanta 2026-11-05 «делать все рекомендованные»).
## Under the F1 toggle `build_pairs` a synergy no longer opens from tag points: it needs two different things,
## each at the level of the slot it would take. Tag points stay with the archetypes (part A). Why: tag points
## made missiles the fastest road to every synergy (5 of 12 synergies keyed on missiles), so a sortie collapsed
## into «pump the missiles». A recipe of two different families gives a reason to take a second weapon.
## Plan: docs/superpowers/plans/2026-11-05-build-depth.md, part B. Numbers are first guesses before the balance run.
##
## Pure data and rules: no Player, no scene. `Cards` builds the snapshot from the player and draws the texts.
##
## A «thing» is one Dictionary with one key:
## `w` — any of these hardpoint weapons at level `lvl` of the slot;
## `mods` — these modules taken `mods` times in total (`t` — the player name of the group, e.g. the course gun);
## `wing` — permanent wingmen, at least `wing` of the slot;
## `skill` — level `s3` of the class skill (only the skill synergies).

## Per synergy slot (0 — first): weapon level, module picks, wingmen, class-skill level.
## The first slot asks two weapons at level 3 (≈ 5 cards from nothing, as 11 tag points did with one family);
## each next slot asks one level / one pick more. Wingmen stay at 1: fighter and attacker may keep only one.
const COST := [
	{"lvl": 3, "mods": 2, "wing": 1, "s3": 1},
	{"lvl": 4, "mods": 3, "wing": 1, "s3": 2},
	{"lvl": 5, "mods": 4, "wing": 1, "s3": 3},
]

const GUN_MODS := ["gun_dmg", "gun_rate"]
const MISSILE_W := ["aam", "srm", "agm", "rockets"]
const BOMB_W := ["bombs", "hebomb"]

## Recipe of every weapon synergy (`Cards.SYNERGIES`). Each pairs two different families: missiles with
## defence, blast with kinetic, and so on. `gunner` (gun pod, out of the game) has no recipe and is never offered.
const REQ := {
	"carousel": [{"w": ["aam"]}, {"w": ["flares"]}],
	"thermobaric": [{"w": ["rockets"]}, {"mods": GUN_MODS, "t": "Пушка"}],
	"salvo": [{"w": ["rockets"]}, {"mods": ["engine", "afterburner"]}],
	"carpet_road": [{"w": BOMB_W}, {"w": ["turret"]}],
	"chain": [{"w": ["rockets", "bombs", "hebomb"]}, {"mods": ["armor"]}],
	"wolfpack": [{"wing": 1}, {"w": MISSILE_W}],
	"warm": [{"wing": 1}, {"w": BOMB_W}],
	"mirror": [{"w": ["flares"]}, {"mods": GUN_MODS, "t": "Пушка"}],
	"hedgehog": [{"w": ["turret"]}, {"mods": ["armor"]}],
	"roller": [{"mods": ["armor"]}, {"w": ["flares", "turret"]}],
	"jetwash": [{"mods": ["roll", "afterburner"]}, {"w": ["rockets", "bombs", "hebomb"]}],
	# new in PG-11 (only with the toggle on)
	"crossfire": [{"mods": GUN_MODS, "t": "Пушка"}, {"w": ["turret"]}],
	"hunter": [{"mods": GUN_MODS, "t": "Пушка"}, {"w": ["agm"]}],
	"decoy": [{"w": ["flares"]}, {"w": ["srm", "agm"]}],
	"corridor": [{"w": ["rockets"]}, {"w": BOMB_W}],
	"glow": [{"w": ["flares"]}, {"w": BOMB_W}],
	"ironclad": [{"mods": ["armor"]}, {"mods": GUN_MODS, "t": "Пушка"}],
}

## Recipe of the class-skill synergies (`PlaneClasses.SKILL3[...]["syn"]["id"]`): the skill plus one more thing.
const SKILL_REQ := {
	"s_wheel": [{"skill": 1}, {"w": ["aam"]}],
	"s_newyear": [{"skill": 1}, {"w": ["rockets"]}],
	"s_clap": [{"skill": 1}, {"w": ["flares"]}],
	"s_iron": [{"skill": 1}, {"w": ["turret"]}],
	"s_conveyor": [{"skill": 1}, {"w": ["rockets"]}],
	"s_nest": [{"skill": 1}, {"mods": ["radio"]}],
	"s_shelter": [{"skill": 1}, {"wing": 1}],
	"s_double": [{"skill": 1}, {"w": BOMB_W}],
	"s_parade": [{"skill": 1}, {"wing": 1}],
}


# ---------- numbers of the six new pair synergies (effects: PairFx; first guesses before the balance run) ----------

## «Перекрёстный огонь» / «Загонщик»: damage factor on a marked target, and how long a course gun hit marks it, s
const MARK_K := 1.5
const CROSS_T := 2.0
const HUNT_T := 3.0
## «Обманка»: damage of the answering missile; «Зарево»: bomb damage, radius and search range, px
const DECOY_DMG := 40.0
const DECOY_RANGE := 900.0
const DECOY_SPD := 250.0
const GLOW_DMG := 50.0
const GLOW_R := 90.0
const GLOW_RANGE := 600.0
## «Огненный коридор»: fire left by a volley rocket (radius px, damage per s, time s) and the bomb radius factor in it
const CORRIDOR_R := 45.0
const CORRIDOR_DPS := 10.0
const CORRIDOR_T := 2.0
const CORRIDOR_R_K := 1.5
## a bomb counts as «in the fire» this far past the fire's edge, px
const CORRIDOR_BOMB_PAD := 40.0
const CORRIDOR_SRC := "связка: огненный коридор"
## «Броневой бой»: course gun damage per stack, stacks cap, how long the stacks hold after the last hit, s
const IRONCLAD_K := 0.08
const IRONCLAD_MAX := 5
const IRONCLAD_T := 5.0


## Recipe of synergy `id` ([] — none: unknown id or a retired synergy)
static func req(id: String) -> Array:
	if REQ.has(id):
		return REQ[id]
	return SKILL_REQ.get(id, [])


## Cost row of synergy slot `slot` (0-based; past the last slot — the last row)
static func cost(slot: int) -> Dictionary:
	return COST[clampi(slot, 0, COST.size() - 1)]


## How much of `thing` the slot `c` (a `COST` row) asks
static func need(thing: Dictionary, c: Dictionary) -> int:
	if thing.has("w"):
		return int(c["lvl"])
	if thing.has("mods"):
		return int(c["mods"])
	if thing.has("wing"):
		return int(c["wing"])
	if thing.has("skill"):
		return int(c["s3"])
	return 0


## How much of `thing` the plane has. `snap`: {"w": {weapon: level}, "taken": {module: picks}, "wing": n, "s3": n}
static func have(thing: Dictionary, snap: Dictionary) -> int:
	if thing.has("w"):
		var lv := 0
		var wl: Dictionary = snap.get("w", {})
		for w in thing["w"]:
			lv = maxi(lv, int(wl.get(w, 0)))
		return lv
	if thing.has("mods"):
		var n := 0
		var tk: Dictionary = snap.get("taken", {})
		for m in thing["mods"]:
			n += int(tk.get(m, 0))
		return n
	if thing.has("wing"):
		return int(snap.get("wing", 0))
	if thing.has("skill"):
		return int(snap.get("s3", 0))
	return 0


## State of every thing of synergy `id` for slot `slot`: [[thing, have, need], …]
static func state(id: String, snap: Dictionary, slot: int) -> Array:
	var c := cost(slot)
	var out: Array = []
	for t in req(id):
		out.append([t, have(t, snap), need(t, c)])
	return out


## Whether synergy `id` is ready for slot `slot`
static func is_ready(id: String, snap: Dictionary, slot: int) -> bool:
	var st := state(id, snap, slot)
	if st.is_empty():
		return false
	for s in st:
		if int(s[1]) < int(s[2]):
			return false
	return true


## Whether a card raises an unmet thing of synergy `id`. `card`: {"weapon": id} for a new weapon or a weapon
## upgrade, {"mod": id} for a module, {"wing": true} for a new permanent wingman, {"skill": true} for the skill.
static func advances(id: String, card: Dictionary, snap: Dictionary, slot: int) -> bool:
	for s in state(id, snap, slot):
		if int(s[1]) >= int(s[2]):
			continue
		var t: Dictionary = s[0]
		if card.has("weapon") and t.has("w") and (t["w"] as Array).has(card["weapon"]):
			return true
		if card.has("mod") and t.has("mods") and (t["mods"] as Array).has(card["mod"]):
			return true
		if card.get("wing", false) and t.has("wing"):
			return true
		if card.get("skill", false) and t.has("skill"):
			return true
	return false


## Whether a plane can ever complete weapon synergy `id`: `weapons` — the hardpoint weapons it may carry,
## `wing_cap` — its permanent wingmen limit. Modules are always on offer (radio only with wingmen).
static func reachable(id: String, weapons: Array, wing_cap: int) -> bool:
	var r := req(id)
	if r.is_empty():
		return false
	for t in r:
		if t.has("w") and not (t["w"] as Array).any(func(w): return weapons.has(w)):
			return false
		if t.has("wing") and wing_cap <= 0:
			return false
		if t.has("mods") and (t["mods"] as Array).has("radio") and wing_cap <= 0:
			return false
	return true


## Ids of the weapon synergies a plane can complete (see `reachable`)
static func reachable_ids(weapons: Array, wing_cap: int) -> Array:
	return REQ.keys().filter(func(id): return reachable(id, weapons, wing_cap))


## Hardpoint weapon things of `id` that none of `weapons` (the families on the plane) covers.
## Modules, wingmen and the skill are left out: they never need a mount.
static func weapons_missing(id: String, weapons: Array) -> Array:
	return req(id).filter(func(t): return t.has("w") and not (t["w"] as Array).any(func(w): return weapons.has(w)))


## Whether putting weapon `new_w` on a mount closes synergy `id` for good: after it the recipe still misses
## more weapon families than the `free_after` normal mounts left. Flights review 06.11, item 1.4 (Kanta «да»):
## in s16 the «Оса» filled both mounts with weapons outside its course recipe and the synergy silently died.
static func closes(id: String, weapons: Array, new_w: String, free_after: int) -> bool:
	if req(id).is_empty():
		return false
	var miss := weapons_missing(id, weapons + [new_w])
	return not miss.is_empty() and miss.size() > free_after


## Whether the recipe of `id` uses two different hardpoint weapon families (telemetry: share of mixed builds)
static func two_weapons(id: String) -> bool:
	var n := 0
	for t in req(id):
		if t.has("w"):
			n += 1
	return n >= 2
