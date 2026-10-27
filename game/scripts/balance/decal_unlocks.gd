class_name DecalUnlocks
## Which decal pictures a player may put on a plane (Kanta 27.10, option 2: a start set, the rest for milestones the
## game already counts; cosmetic only — no parts cost, no balance effect). Spec 2026-10-27-plane-decals-design.md §7.
## The list is a proposal until Kanta's «ок» (each rule below says what opens a picture). Rules read the lifetime
## medal counters (Profile.medal_counters) and this class's crew rank; counters never go down, so a picture once
## open stays open and saved decals are never checked against these rules.

## Open from the first sortie: numbers, the three tally marks, the shark mouth and three neutral symbols
const START := ["number", "tally_air", "tally_ground", "tally_bomb", "shark_mouth", "bolt", "chevrons", "sun"]
## Class mascots: a class's own is open from the start; another class's opens after one sortie on that class
const MASCOTS := {"fighter": "wasp", "attacker": "rook", "bomber": "whale"}
## Picture → milestone: {"crew": rank of this class's crew} or {"c": medal counter, "n": at least} or
## {"op": operations of any kind cleared, at least}
const RULES := {
	"eye": {"crew": 5},
	"peaks": {"crew": 10},
	"skull_winged": {"crew": Insignia.ACE_RANK},   # the ace rank, where the ace claw appears today
	"cat": {"c": "evacs", "n": 1},                 # first evacuation
	"dice": {"c": "sorties", "n": 10},
	"ace_card": {"c": "aces", "n": 1},             # first rival ace downed
	"skull_flame": {"c": "fortresses", "n": 1},    # first «Крепость» downed
	"skull_wrench": {"op": 1},                     # first operation cleared
}


## True when picture `id` is open for a plane of class `cls`; `counters` — lifetime medal counters, `crew` — the
## class's crew rank
static func is_open(id: String, cls: String, counters: Dictionary, crew: int) -> bool:
	if id in START:
		return true
	for owner: String in MASCOTS:
		if MASCOTS[owner] == id:
			return owner == cls or int(counters.get("sorties_" + owner, 0)) >= 1
	var rule: Dictionary = RULES.get(id, {})
	if rule.has("crew"):
		return crew >= int(rule["crew"])
	if rule.has("c"):
		return int(counters.get(String(rule["c"]), 0)) >= int(rule["n"])
	if rule.has("op"):
		var ops := 0
		for k: String in counters:
			if k.begins_with("op_") and int(counters[k]) > 0:
				ops += 1
		return ops >= int(rule["op"])
	return false
