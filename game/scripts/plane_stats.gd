class_name PlaneStats
extends RefCounted
## Concrete numbers of a plane for the hangar (S16-08, Kanta 06.11): hull, cruise speed in km/h, turn rate, dodge
## cooldown, fuel, damage per second of the starting kit with its air and ground factors, course-gun damage per
## second, hardpoint groups, turret mounts and wingmen — for plane 1 and plane 2 side by side, so buying plane 2
## shows what changes.
## The numbers come from the same code the sortie uses: a throwaway `Player` goes through `Player.setup` (class data,
## starting weapons on their groups, `Profile.apply` with hangar nodes, crew level, callsign trait, perks, medals),
## with `Profile.debug_plane` set to the plane asked for. Nothing here changes a number in flight.
##
## Kanta 06.11 («привязать к реальным цифрам, не шкалы»): «Урон в секунду» is the nominal damage per second on one
## plain target of everything that fires by itself at the start — course gun, starting weapons at level 1, turrets —
## and «по воздуху» / «по земле» are the factors on it against planes and against ground targets: a weapon that can't
## hit one kind adds nothing there, NAR, bombs and guided air-to-ground missiles count their ground multipliers, the
## «Хватка» trait and medals their ground bonus. Splash on neighbours, the straight-run bonus, archetypes, armor and
## wingmen are left out (they depend on the fight).

## Row order, titles and formats (keys of `of`): "n" — whole number, "kmh" — speed in km/h, "deg" — «168 °/с»,
## "s" — seconds, "min" — minutes of flight, "x" — factor «×1,2». Every hangar node moves one of these rows, so a
## hover over a node card can show its gain (`NODE_ROW`). The «dodge» title is swapped for the flare salvo on a plane
## whose space key fires flares (`dodge_title`).
const ROWS := [
	["hull", "Прочность", "n"],
	["speed", "Скорость", "kmh"],
	["turn", "Разворот", "deg"],
	["dodge", "Перезарядка уклонения", "s"],
	["dps", "Урон в секунду", "n"],
	["air_k", "по воздуху", "x"],
	["ground_k", "по земле", "x"],
	["fuel", "Топливо", "min"],
	["gun_dps", "Пушка, урон/с", "n"],
	["groups", "Группы подвеса", "n"],
	["turrets", "Турели (макс.)", "n"],
	["wingmen", "Ведомые", "n"],
]

## Hangar node → the row it improves (`Profile.NODES`): «Планер» the dodge cooldown, «Узлы подвеса» the damage.
const NODE_ROW := {"frame": "dodge", "engine": "speed", "armor": "hull", "wing": "turn", "pylons": "dps", "tank": "fuel"}

## Weapon → [shots per mount in one volley at level 1, factor on planes, factor on ground targets], as the firing code
## does it: `Hardpoint._fire_aam` (1, planes only), `_fire_rockets` (4 per mount on levels 1–2, ground ×3),
## `_fire_bombs` and `WeaponFire.fire_hebomb` (ground only, ×2), `WeaponFire.fire_srm` (planes only),
## `WeaponFire.fire_agm` (ground only, ×2), `_fire_gun` / `_fire_turret` (one round per mount, both kinds).
## Flares only intercept missiles: no damage.
const HIT := {
	"aam": [1, 1.0, 0.0],
	"srm": [1, 1.0, 0.0],
	"rockets": [4, 1.0, Hardpoint.ROCKET_GROUND_K],
	"bombs": [1, 0.0, Hardpoint.GROUND_BOMB_K],
	"hebomb": [1, 0.0, Hardpoint.GROUND_BOMB_K],
	"agm": [1, 0.0, WeaponBalance.AGM_GROUND_K],
	"gunpod": [1, 1.0, 1.0],
	"turret": [1, 1.0, 1.0],
}

static var _cache := {}


## Stats of class `c` on plane `lv` (1 or 2) with the current profile. Cached on the class's profile record, so the
## hangar can ask every frame.
static func of(c: String, lv: int) -> Dictionary:
	var key := "%s|%d|%s|%s" % [c, lv, str(Profile.cls(c)), str(Profile.data.get("medals", {}))]
	if _cache.has(key):
		return _cache[key]
	var out := compute(c, lv)
	if _cache.size() > 16:
		_cache.clear()
	_cache[key] = out
	return out


## Uncached `of` (unit tests call it directly).
static func compute(c: String, lv: int) -> Dictionary:
	lv = clampi(lv, 1, 2)
	var keep := Profile.debug_plane
	Profile.debug_plane = lv
	var p := Player.new()
	p.setup(c)
	var v := p.guns.variant()
	var a := p.guns.ammo_k()
	var gun := Tuning.g("bullet_damage") * float(p.cls["gun_dmg"]) * float(p.mods["gun_dmg"]) * float(v["dmg"]) * float(a["dmg"]) \
		* Tuning.g("fire_rate") * float(p.cls["gun_rate"]) * float(p.mods["gun_rate"]) * float(v["rate"])
	var d := kit_dps(p, gun)
	var out := {
		"hull": p.max_hp,
		"speed": Tuning.g("cruise_speed") * float(p.cls["speed"]) * float(p.mods["speed"]),
		"turn": Tuning.g("turn_rate") * float(p.cls["turn"]) * float(p.mods["turn"]),
		"dps": d["dps"],
		"air_k": d["air_k"],
		"ground_k": d["ground_k"],
		"gun_dps": gun,
		"dodge": p.salvo_cd_full() if String(p.cls.get("space", "roll")) == "flares" else p.roll_cd_full(),
		"fuel": Fuel.CAPACITY * Profile.fuel_k(c),
		"groups": (p.cls["groups"] as Array).size() + (1 if lv == 2 else 0) + (1 if Profile.third_group(c, lv) else 0),
		"turrets": int(p.cls["turrets_max"]),
		"wingmen": int(p.cls["wingmen"]),
	}
	p.free()
	Profile.debug_plane = keep
	return out


## Damage per second of `p`'s starting kit on one plain target: `gun` (course gun, per second) plus every armed group
## of `HIT` — damage of one round × rounds per volley ÷ reload, read from the group itself (`Hardpoint.dmg`,
## `reload_time`, hangar branch factor), so class bonus, missile modules and reload perks count. Returns
## {dps, air_k, ground_k}; the factors are the share of `dps` that reaches planes / ground targets, ground with the
## player's ground-damage bonus. `dmg_all` scales every number.
static func kit_dps(p: Player, gun: float) -> Dictionary:
	var raw := gun
	var air := gun
	var ground := gun
	for g in p.groups:
		var h: Hardpoint = g
		if h.is_empty() or not HIT.has(h.weapon):
			continue
		h.stats_owner = p
		var hit: Array = HIT[h.weapon]
		var s := h.dmg() * Profile.wk(h.weapon, "dmg") * float(h.slots * int(hit[0])) / maxf(h.reload_time(p), 0.05)
		raw += s
		air += s * float(hit[1])
		ground += s * float(hit[2])
	var all := float(p.mods.get("dmg_all", 1.0))
	var gk := float(p.mods.get("ground_dmg", 1.0))
	return {"dps": raw * all, "air_k": air / raw if raw > 0.0 else 0.0, "ground_k": ground * gk / raw if raw > 0.0 else 0.0}


## Stats of class `c` on plane `lv` as they would be with hangar node `node_id` one level higher — the hover preview
## of a node card. The profile is changed in memory only and put back (nothing saved); a node at the top returns the
## stats as they are.
static func with_node(c: String, lv: int, node_id: String) -> Dictionary:
	var nodes: Dictionary = Profile.nodes_of(c, lv)
	var was := int(nodes.get(node_id, 0))
	if was >= 5:
		return of(c, lv)
	nodes[node_id] = was + 1
	var out := of(c, lv)
	nodes[node_id] = was
	return out


## Title of row `key` for class `c`: «Перезарядка ловушек» instead of the dodge on a flare-salvo plane.
static func title(c: String, key: String, base: String) -> String:
	if key == "dodge" and String(PlaneClasses.DATA[c].get("space", "roll")) == "flares":
		return "Перезарядка ловушек"
	return base


## Text of value `v` in the row format `fmt` of `ROWS`: «842 км/ч», «168 °/с», «7,5 с», «9,7 мин», «×1,2» (decimal
## comma, as the rest of the Russian UI), or a whole number.
static func text(v: float, fmt: String) -> String:
	match fmt:
		"kmh":
			return Loc.t("%d км/ч") % DistText.kmh(v)
		"x":
			return "×" + CardText.dec("%.1f" % v)
		"deg":
			return Loc.t("%d °/с") % roundi(v)
		"s":
			return CardText.sec(v)
		"min":
			return Loc.t("%s мин") % CardText.dec(("%.1f" % (v / 60.0)).trim_suffix(".0"))
	return "%d" % roundi(v)
