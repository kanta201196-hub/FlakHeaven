class_name PlaneStats
extends RefCounted
## S16-08 (Kanta 05.11): plane characteristics the hangar shows, and their difference when buying the level-2 plane
## («было → стало»). One pure function so the hangar card, the purchase panel and tests all use the same numbers.
## Only the plane and its hangar nodes count here: crew rank, medals and in-sortie cards are the same for both planes
## of a class, so they would not change the comparison.
##
## `tun` carries the F1 values the numbers scale with (`Tuning.g` of the keys in TUNING_DEF); the caller passes them,
## which keeps this file free of autoloads and testable. Missing keys fall back to TUNING_DEF.

## F1 sliders the stats depend on, with their defaults (tuning.gd RANGES, version 16).
const TUNING_DEF := {"cruise_speed": 390.0, "turn_rate": 210.0, "bullet_damage": 15.0, "fire_rate": 9.0, "roll_cd": 8.0}
## Hangar node steps per level (Profile.apply): speed, hull, turn, hardpoint damage, fuel.
const NODE_STEP := {"engine": 0.02, "armor": 0.05, "wing": 0.03, "pylons": 0.04, "tank": 0.08}
## «Узлы подвеса» level that opens the third hardpoint group (same as Profile.GROUP3_PYLONS; Profile is an autoload).
const GROUP3_PYLONS := 2
## Fuel tank of every plane, s (Fuel.CAPACITY, before the tank node).
const FUEL_S := Fuel.CAPACITY
## Order and kind of the rows for the UI: [key, label, unit, «more is better»]. The interface thread draws these.
const ROWS := [
	["hull", "Прочность", "", true],
	["speed", "Скорость", "пикс/с", true],
	["turn", "Разворот", "°/с", true],
	["min_r", "Радиус виража", "пикс", false],
	["gun_dps", "Пушка, урон в секунду", "", true],
	["hardpoints", "Точек подвеса", "", true],
	["heavy", "Тяжёлый подвес", "", true],
	["turrets", "Турелей в бою, до", "", true],
	["wingmen", "Ведомых", "", true],
	["star", "Бонус ★ к оружию класса", "%", true],
	["pylon_dmg", "Урон подвесов и турелей", "%", true],
	["weapons", "Видов оружия", "", true],
	["modules", "Мест модулей", "", true],
	["skill_cd", "Перезарядка уклонения", "с", false],
	["fuel", "Бак", "мин", true],
]


## Stats of plane `lv` (1 or 2) of class `cls` with hangar node levels `nodes` ({"engine": 2, ...}; missing = 0).
## Keys are those of ROWS; numbers are rounded the way the hangar shows them.
static func of(cls: String, lv: int, nodes: Dictionary = {}, tun: Dictionary = {}) -> Dictionary:
	var d := PlaneClasses.plane(cls, lv)
	var t := TUNING_DEF.duplicate()
	t.merge(tun, true)
	var n := func(k: String) -> float: return float(nodes.get(k, 0)) * float(NODE_STEP.get(k, 0.0))
	var slots := 0
	for g: Dictionary in PlaneClasses.group_defs(cls, int(nodes.get("pylons", 0)) >= GROUP3_PYLONS):
		slots += int(g["slots"])
	var bonus: Dictionary = d["bonus"]
	var sig := String(d["signature"])
	return {
		"hull": roundi(float(d["hp"]) * (1.0 + n.call("armor"))),
		"speed": roundi(float(t["cruise_speed"]) * float(d["speed"]) * (1.0 + n.call("engine"))),
		"turn": roundi(float(t["turn_rate"]) * float(d["turn"]) * (1.0 + n.call("wing"))),
		"min_r": roundi(float(d["min_r"])),
		"gun_dps": roundi(float(t["bullet_damage"]) * float(d["gun_dmg"]) * float(t["fire_rate"]) * float(d["gun_rate"])),
		"hardpoints": slots,
		"heavy": 1 if int(d["plane_lvl"]) == 2 else 0,
		"turrets": int(d["turrets_max"]),
		"wingmen": int(d["wingmen"]),
		"star": roundi((float(bonus.get(sig, 1.0)) - 1.0) * 100.0),
		"pylon_dmg": roundi(n.call("pylons") * 100.0),
		"weapons": (d["weapons"] as Array).size(),
		"modules": Cards.MOD_SLOTS,
		"skill_cd": snappedf(float(t["roll_cd"]) * float(d.get("roll_cd_k", 1.0)) * (1.0 - 0.04 * float(nodes.get("frame", 0))), 0.1),
		"fuel": snappedf(FUEL_S * (1.0 + n.call("tank")) / 60.0, 0.1),
	}


## Rows that differ between `a` and `b` (results of `of`): [key, from, to, better]; `better` says the change helps.
static func diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for r: Array in ROWS:
		var k := String(r[0])
		if not is_equal_approx(float(a[k]), float(b[k])):
			out.append([k, a[k], b[k], (float(b[k]) > float(a[k])) == bool(r[3])])
	return out
