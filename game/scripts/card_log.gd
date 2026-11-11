class_name CardLog
extends RefCounted
## PG-12 card telemetry (genre research 11.11, item 2; Kanta «да»): every card screen of a sortie as one compact
## entry — the cards offered, their rarity and which one was taken — for the sortie log column `card_offers`.
## Why: to see which cards players take when offered and which builds evacuate (the two Slay the Spire metrics,
## `tools/reports/card_stats.py`), instead of guessing card value from damage alone.
##
## Pure: no Player, no scene. A key drops the hardpoint and wingman indexes so the same card adds up across sorties.


## Stable key of card `card`; `group_weapon` — the weapon on the card's hardpoint group ("" if none)
static func key(card: Dictionary, group_weapon: String) -> String:
	match String(card.get("kind", "")):
		"weapon_new":
			return "new:" + String(card["weapon"])
		"weapon_up":
			return "up:" + group_weapon
		"profile":
			return "pr:%s:%s" % [String(card.get("weapon", group_weapon)), String(card["profile"])]
		"branch":
			return "br:%s:%s" % [group_weapon, String(card["branch"])]
		"wing_new":
			return "wing:" + String(card["wtype"])
		"wing_lvl":
			return "wing_lvl"
		"synergy", "skill_syn":
			return "syn:" + String(card["syn"])
		"evolution":
			return "evo:" + String(card["evo"])
	var id := String(card.get("id", "?"))
	if id.begins_with("res_evo"):
		return "res_evo"
	return id


## One card screen: «<second> L<level>: key/rarity, key/rarity*, …»; `taken` — index of the taken card,
## −1 when the screen was left by a reroll (the entry then ends with « ~»)
static func entry(t: float, level: int, keys: Array, rarities: Array, taken: int) -> String:
	var parts := PackedStringArray()
	for i in keys.size():
		parts.append("%s/%d%s" % [keys[i], int(rarities[i]), "*" if i == taken else ""])
	return "%d L%d: %s%s" % [int(t), level, ", ".join(parts), " ~" if taken < 0 else ""]


## Reads an `entry` back: {t, lvl, keys, taken} (taken "" for a reroll screen); the report script reads the same format
static func parse(s: String) -> Dictionary:
	var head := s.get_slice(": ", 0)
	var body := s.substr(head.length() + 2).trim_suffix(" ~")
	var keys: Array = []
	var taken := ""
	for part in body.split(", ", false):
		var k := part.substr(0, part.rfind("/"))
		keys.append(k)
		if part.ends_with("*"):
			taken = k
	return {"t": int(head.get_slice(" ", 0)), "lvl": int(head.get_slice(" L", 1)), "keys": keys, "taken": taken}
