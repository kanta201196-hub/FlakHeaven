class_name PlaneStats
extends RefCounted
## Concrete numbers of a plane for the hangar (S16-08, Kanta 06.11): hull, cruise speed, turn rate, course-gun damage
## per second, hardpoint groups, turret mounts and wingmen — for plane 1 and plane 2 side by side, so buying plane 2
## shows what changes. The numbers come from the same code the sortie uses: a throwaway `Player` gets the class data
## and `Profile.apply` (hangar nodes of that plane, crew level, callsign trait, perks, medals), with
## `Profile.debug_plane` set to the plane asked for. Nothing here changes a number in flight.

## Row order and titles (keys of `of`); "°/с" rows carry their unit in the title
const ROWS := [
	["hull", "Прочность"],
	["speed", "Скорость"],
	["turn", "Разворот, °/с"],
	["gun_dps", "Пушка, урон/с"],
	["groups", "Группы подвеса"],
	["turrets", "Турели (макс.)"],
	["wingmen", "Ведомые"],
]

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
	p.cls_id = c
	p.cls = PlaneClasses.plane(c, lv)
	p.max_hp = float(p.cls["hp"])
	p.gun_variant = Profile.gun(c, lv)
	p.ammo = Profile.ammo(c, lv)
	Profile.apply(p)
	var v := p.guns.variant()
	var a := p.guns.ammo_k()
	var out := {
		"hull": p.max_hp,
		"speed": Tuning.g("cruise_speed") * float(p.cls["speed"]) * float(p.mods["speed"]),
		"turn": Tuning.g("turn_rate") * float(p.cls["turn"]) * float(p.mods["turn"]),
		"gun_dps": Tuning.g("bullet_damage") * float(p.cls["gun_dmg"]) * float(p.mods["gun_dmg"]) * float(v["dmg"]) * float(a["dmg"])
			* Tuning.g("fire_rate") * float(p.cls["gun_rate"]) * float(p.mods["gun_rate"]) * float(v["rate"]),
		"groups": (p.cls["groups"] as Array).size() + (1 if lv == 2 else 0) + (1 if Profile.third_group(c, lv) else 0),
		"turrets": int(p.cls["turrets_max"]),
		"wingmen": int(p.cls["wingmen"]),
	}
	p.free()
	Profile.debug_plane = keep
	return out
