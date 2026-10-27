class_name Medals
extends RefCounted
## Medals at the end of a sortie (Kanta 2026-10-27, «Наградная планка»): turns what the sortie kept in Main, RunState
## and Telemetry into medal counter increments for Profile.medals_award. Rules and numbers: MedalBalance.


## Every card «Коллекционер» asks for: each hardpoint weapon ("w:id") and each module ("m:id") a card can give;
## the free repair and skill-slot cards are not modules a player collects
static func card_set() -> Array:
	var out: Array = []
	for w in Weapons.POOL + Weapons.EXP:
		out.append("w:" + w)
	for k in Cards.MODULES:
		if not Cards.SLOT_FREE.has(k):
			out.append("m:" + k)
	return out


## Sizes of the «all of them» sets: every card of card_set («Коллекционер»), every synergy («Мастер связок»)
static func sets() -> Dictionary:
	return {"cards_seen": card_set().size(), "syn_seen": Cards.SYNERGIES.size()}


## Medal counters of the sortie that ends now with `outcome` ("evac" / "dead"); parts and sorties are added by Profile
static func run_counters(m: Main, outcome: String) -> Dictionary:
	var tv: Dictionary = m.tele.v
	var evac := outcome == "evac"
	var wing := 0.0
	for k in m.stats["dealt"]:
		if String(k).begins_with("ведомые"):  # i18n-skip: damage source key
			wing += float(m.stats["dealt"][k])
	var r := {
		"kills": m.run.kills, "aces": m.run.bosses_killed, "tail_kills": m.run.tail_kills, "near_misses": m.run.near_misses,
		"blast_dmg": MedalBalance.blast_of(m.stats["dealt"]), "gun_hits": m.hits, "turret_dmg": m.stat("dealt", "турели"),
		"wing_dmg": int(wing), "convoys": int(tv.get("convoy_done", 0)), "dive_dodged": int(tv.get("dive_dodged", 0)),
		"dives": int(tv.get("dive_uses", 0)), "healed": int(m.counters.get("healed", 0)), "refuels": int(tv.get("fuel_refuels", 0)),
		"evacs": 1 if evac else 0, "lvl20_early": 1 if m.level_at_5 >= 20 else 0, "sorties_" + m.cls_id: 1,
		"kills_minute": MedalBalance.best_minute(m.medal_kill_t),
	}
	for k in m.medal_run:
		r[k] = int(r.get(k, 0)) + int(m.medal_run[k])
	if evac and bool(m.op_result.get("done", false)):
		r["op_" + String(Campaign.op()["id"])] = 1
	if Campaign.flag("grom_free"):
		r["grom"] = 1
	if evac and is_instance_valid(m.player):
		var bare := true
		for g: Hardpoint in m.player.groups:
			if not g.builtin and not g.is_empty():
				bare = false
		r["gun_only_evacs"] = 1 if bare else 0
		r["last_breath"] = 1 if m.player.hp < m.player.max_hp * 0.05 else 0
	return r
