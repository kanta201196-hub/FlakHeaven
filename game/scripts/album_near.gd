class_name AlbumNear
extends RefCounted
## The build album during a sortie (PG-16, genre research item 8, Kanta 2026-11-11 «1, только сразу нормально с
## картинками и хорошей визуализацией»). The hangar album (`HudAlbum`) says what was ever found; this says, for the
## plane in the air right now, how far each entry is: what is already on the plane, what is still missing, and what
## this plane can never build. The card screen, its «nearest recipes» panel and the pause tab «АЛЬБОМ» read it.
## Presentation only: no rule or number changes; synergies follow `SynPairs`, modernizations `Modernizations`.
##
## Pure rules over a context dictionary, so the unit tests need no Player (`ctx_of` builds it from one):
##   snap      — `Cards.pair_snap`: {"w": {weapon: level}, "taken": {module: picks}, "wing": n, "s3": n}
##   weapons   — hardpoint weapons this plane may carry (`PlaneClasses.PLANES[...]["weapons"]`, in-game ones)
##   wing_cap  — permanent wingmen limit of the plane
##   skill_syn — id of the skill synergy of the skill flown; skill_title — its skill name;
##   class_syns — skill synergy ids of the class's other skills (chosen in the hangar), shown as not on this plane
##   owned     — synergies already open this sortie (ids); course — the chosen specialization ("" — none)
##   evo_done  — modernization ids done this sortie; evo_time — true from `Prog.EVO_TIME`
##   profiles  — {weapon: chosen profile id}; third_open — {weapon: true} when the hangar opened the third profile
##   tags      — {tag: points}; arch_on — archetype ranks exist (F1 `build_arch`)
##   pairs_on  — synergies use pair recipes (F1 `build_pairs`); with it off synergies follow tag points and are left out
##
## A row: {"id": album id, "kind": "syn"|"evo"|"prof"|"arch", "things": [{"name", "have", "need", "unit"}],
## "done": collected this sortie, "reach": this plane can collect it, "why": what blocks it, "prog": 0…1,
## "course": the chosen specialization}. "why" is a source-text template (the translation key, maybe with %s) and
## "why_arg" the untranslated name that fills it ("" — none); a thing may carry "fmt", a template for its name.

## How many recipes the card screen lists
const NEAR_N := 3


## Every row of the album for the plane in `ctx`, in album order (`ids` — `Profile.album_ids()`)
static func rows(ctx: Dictionary, ids: Array) -> Array:
	var out: Array = []
	for id: String in ids:
		var r := row(ctx, id)
		if not r.is_empty():
			out.append(r)
	return out


## One row for album entry `id`; {} for an entry that does not apply (another class's skill synergy, tag synergies)
static func row(ctx: Dictionary, id: String) -> Dictionary:
	match AlbumBook.kind(id):
		"syn":
			return _syn_row(ctx, id.get_slice(":", 1))
		"evo":
			return _evo_row(ctx, id.get_slice(":", 1))
		"prof":
			return _prof_row(ctx, id.get_slice(":", 1), id.get_slice(":", 2))
		"arch":
			return _arch_row(ctx, id.get_slice(":", 1))
	return {}


## Progress of `things` as the mean share of each one met, 0…1
static func progress(things: Array) -> float:
	if things.is_empty():
		return 0.0
	var k := 0.0
	for t: Dictionary in things:
		k += clampf(float(t["have"]) / maxf(float(t["need"]), 1.0), 0.0, 1.0)
	return k / things.size()


## How many of `things` are met
static func met(things: Array) -> int:
	return things.filter(func(t: Dictionary) -> bool: return int(t["have"]) >= int(t["need"])).size()


## The `n` synergies and modernizations this plane can still collect, the furthest along first; the course wins a tie
static func nearest(rows_: Array, n := NEAR_N) -> Array:
	var open: Array = rows_.filter(func(r: Dictionary) -> bool: return r["kind"] in ["syn", "evo"] and r["reach"] and not r["done"])
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["prog"]), float(b["prog"])):
			return float(a["prog"]) > float(b["prog"])
		if a["course"] != b["course"]:
			return a["course"]
		return String(a["id"]) < String(b["id"]))
	return open.slice(0, n)


## Rows grouped for the album tab: [collected this sortie, can collect (furthest first), cannot on this plane]
static func sections(rows_: Array) -> Array:
	var done: Array = rows_.filter(func(r: Dictionary) -> bool: return r["done"])
	var can: Array = rows_.filter(func(r: Dictionary) -> bool: return r["reach"] and not r["done"])
	can.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["course"] != b["course"]:
			return a["course"]
		if not is_equal_approx(float(a["prog"]), float(b["prog"])):
			return float(a["prog"]) > float(b["prog"])
		return false)
	var no: Array = rows_.filter(func(r: Dictionary) -> bool: return not r["reach"] and not r["done"])
	return [done, can, no]


## What card `pc` does to the album: the synergy or modernization it completes, or else the one it moves furthest.
## `pc` is the card in `SynPairs.advances` terms plus how much it adds: {"weapon": id, "add": levels, "new": a new mount},
## {"mod": id}, {"wing": true}, {"skill": true}. Returns {} when it moves nothing, else
## {"row": the row before the card, "after": its things after, "opens": every thing met after the card}.
static func card_effect(ctx: Dictionary, rows_: Array, pc: Dictionary) -> Dictionary:
	if pc.is_empty():
		return {}
	var best := {}
	var best_score := -1.0
	for r: Dictionary in rows_:
		if not (r["kind"] in ["syn", "evo"]) or not r["reach"] or r["done"]:
			continue
		var after := _after(r, pc)
		if after.is_empty():
			continue
		var opens := met(after) == after.size()
		var score := (4.0 if opens else 0.0) + (2.0 if r["course"] else 0.0) + (1.0 if r["kind"] == "syn" else 0.0) + progress(after)
		if score > best_score:
			best_score = score
			best = {"row": r, "after": after, "opens": opens}
	return best


## Things of row `r` after card `pc`, or [] when the card raises no unmet thing of it
static func _after(r: Dictionary, pc: Dictionary) -> Array:
	var moved := false
	var out: Array = []
	for t: Dictionary in r["things"]:
		var t2 := t.duplicate()
		if int(t["have"]) < int(t["need"]) and _hits(t, pc):
			# a new weapon on another mount does not stack with the same family already carried
			t2["have"] = maxi(int(t["have"]), int(pc.get("add", 1))) if pc.get("new", false) else int(t["have"]) + int(pc.get("add", 1))
			moved = true
		out.append(t2)
	return out if moved else []


## Whether card `pc` raises thing `t` (a thing keeps the `SynPairs` key it came from in "src")
static func _hits(t: Dictionary, pc: Dictionary) -> bool:
	var src: Dictionary = t.get("src", {})
	if pc.has("weapon") and src.has("w"):
		return (src["w"] as Array).has(pc["weapon"])
	if pc.has("mod") and src.has("mods"):
		return (src["mods"] as Array).has(pc["mod"])
	if pc.get("wing", false) and src.has("wing"):
		return true
	if pc.get("skill", false) and src.has("skill"):
		return true
	return false


# ---------- rows by kind ----------

static func _syn_row(ctx: Dictionary, sid: String) -> Dictionary:
	if not bool(ctx.get("pairs_on", true)):
		return {}
	var skill := String(ctx.get("skill_syn", ""))
	var is_skill := SynPairs.SKILL_REQ.has(sid)
	if is_skill and sid != skill and not (ctx.get("class_syns", []) as Array).has(sid):
		return {}
	if not is_skill and not SynPairs.REQ.has(sid):
		return {}
	var owned: Array = ctx.get("owned", [])
	var things: Array = []
	for st: Array in SynPairs.state(sid, ctx.get("snap", {}), owned.size()):
		var t: Dictionary = st[0]
		things.append({"name": _thing_name(ctx, t), "fmt": "навык «%s»" if t.has("skill") else "", "have": int(st[1]), "need": int(st[2]),
			"unit": "ур." if (t.has("w") or t.has("skill")) else ("" if t.has("wing") else "×"), "src": t})
	var weapons: Array = ctx.get("weapons", [])
	var reach := (is_skill and sid == skill) or (not is_skill and SynPairs.reachable(sid, weapons, int(ctx.get("wing_cap", 0))))
	var why := ""
	var why_arg := ""
	if is_skill and not reach:
		why = "в ангаре выбран другой навык класса"
	elif not reach:
		var miss := SynPairs.weapons_missing(sid, weapons)
		if not miss.is_empty():
			why = "нет на самолёте: %s"
			why_arg = _thing_name(ctx, miss[0])
		else:
			why = "самолёту не положены ведомые"
	return {"id": "syn:" + sid, "kind": "syn", "things": things, "done": owned.has(sid), "reach": reach, "why": why, "why_arg": why_arg,
		"prog": progress(things), "course": String(ctx.get("course", "")) == sid}


static func _evo_row(ctx: Dictionary, eid: String) -> Dictionary:
	var w := Modernizations.weapon_of(eid)
	if w == "":
		return {}
	var things: Array = []
	var snap: Dictionary = ctx.get("snap", {})
	if w != "gun":
		var lv := int((snap.get("w", {}) as Dictionary).get(w, 0))
		things.append({"name": String(Weapons.DEFS[w]["short"]), "have": lv, "need": Weapons.MAX_LEVEL, "unit": "ур.", "src": {"w": [w]}})
	var c := Modernizations.cat(eid)
	var taken: Dictionary = snap.get("taken", {})
	for mk: String in c:
		things.append({"name": String(Cards.MODULES[mk]["title"]), "have": int(taken.get(mk, 0)), "need": int(c[mk]), "unit": "×",
			"src": {"mods": [mk]}})
	var weapons: Array = ctx.get("weapons", [])
	var reach := w == "gun" or (Weapons.in_game(w) and weapons.has(w))
	return {"id": "evo:" + eid, "kind": "evo", "things": things, "done": (ctx.get("evo_done", []) as Array).has(eid), "reach": reach,
		"why": "" if reach else "нет на самолёте: %s", "why_arg": "" if reach else String(Weapons.DEFS[w]["short"]), "prog": progress(things), "course": false,
		"late": not bool(ctx.get("evo_time", false))}


static func _prof_row(ctx: Dictionary, w: String, pid: String) -> Dictionary:
	var lv := int(((ctx.get("snap", {}) as Dictionary).get("w", {}) as Dictionary).get(w, 0))
	var chosen := String((ctx.get("profiles", {}) as Dictionary).get(w, ""))
	var things: Array = [{"name": String(Weapons.DEFS[w]["short"]), "have": lv, "need": WeaponProfiles.LEVEL, "unit": "ур.", "src": {"w": [w]}}]
	var reach := (ctx.get("weapons", []) as Array).has(w) and Weapons.in_game(w)
	var why := "" if reach else "нет на самолёте: %s"
	if reach and chosen != "" and chosen != pid:
		reach = false
		why = "в этом вылете выбран другой профиль"
	elif reach and pid == WeaponProfiles.third(w) and not bool((ctx.get("third_open", {}) as Dictionary).get(w, false)):
		reach = false
		why = "третий профиль открывает ветка оружия в ангаре"
	return {"id": "prof:%s:%s" % [w, pid], "kind": "prof", "things": things, "done": chosen == pid, "reach": reach, "why": why,
		"why_arg": String(Weapons.DEFS[w]["short"]),
		"prog": progress(things), "course": false}


static func _arch_row(ctx: Dictionary, tg: String) -> Dictionary:
	if not bool(ctx.get("arch_on", true)) or not ArchBalance.ARCH_AT.has(tg):
		return {}
	var pts := int((ctx.get("tags", {}) as Dictionary).get(tg, 0))
	var need := int(ArchBalance.at_of(tg)[2])
	var things: Array = [{"name": Prog.tag_title(tg), "have": pts, "need": need, "unit": "оч.", "src": {}}]
	return {"id": "arch:" + tg, "kind": "arch", "things": things, "done": pts >= need, "reach": true, "why": "", "why_arg": "", "prog": progress(things),
		"course": false}


## Player name (untranslated source text) of one `SynPairs` thing; a skill gives its bare title (the thing's "fmt"
## wraps it as «навык «…»»)
static func _thing_name(ctx: Dictionary, t: Dictionary) -> String:
	if t.has("skill"):
		return String(ctx.get("skill_title", ""))
	if t.has("wing"):
		return "ведомые"
	if t.has("mods") and t.has("t"):
		return String(t["t"])
	if t.has("mods"):
		return " + ".join(PackedStringArray((t["mods"] as Array).map(func(x): return String(Cards.MODULES[x]["title"]))))
	if t.has("w"):
		# only the families this plane carries, when it carries any («Ракеты В-В», not the whole missile list)
		var ws: Array = (t["w"] as Array).filter(func(x): return (ctx.get("weapons", []) as Array).has(x))
		if ws.is_empty():
			ws = t["w"]
		return "/".join(PackedStringArray(ws.map(func(x): return String(Weapons.DEFS[x]["short"]))))
	return ""


# ---------- from the live plane ----------

## Context of player `p` at sortie time `run_time` (see the class doc)
static func ctx_of(p: Player, run_time: float) -> Dictionary:
	var pd: Dictionary = PlaneClasses.PLANES[p.cls_id][int(p.cls["tier"])]
	var weapons: Array = (pd["weapons"] as Array).filter(func(w): return Weapons.in_game(w))
	for g in p.groups:   # class weapons on built-in mounts (turrets) and experimental ones already carried
		var h: Hardpoint = g
		if h.weapon != "" and not weapons.has(h.weapon):
			weapons.append(h.weapon)
	var evo_done: Array = []
	var profiles := {}
	var third := {}
	for g in p.groups:
		var h: Hardpoint = g
		if h.evo:
			evo_done.append(h.evo_id if h.evo_id != "" else h.weapon)
		if h.profile != "":
			profiles[h.weapon] = h.profile
	if p.gun_evo:
		evo_done.append("gun")
	for w in WeaponProfiles.DEFS:
		third[w] = Profile.profile_open(w)
	var tags := {}
	for tg: String in Prog.TAG_ORDER:
		tags[tg] = p.tag(tg)
	return {"snap": Cards.pair_snap(p), "weapons": weapons, "wing_cap": Cards.wing_limit(p),
		"skill_syn": String(PlaneClasses.SKILL3[p.skill3]["syn"]["id"]), "skill_title": String(PlaneClasses.SKILL3[p.skill3]["title"]),
		"class_syns": (PlaneClasses.CLASS_SKILLS.get(p.cls_id, []) as Array).map(func(sk): return String(PlaneClasses.SKILL3[sk]["syn"]["id"])),
		"owned": p.syn.keys(), "course": p.course, "evo_done": evo_done, "evo_time": run_time >= Prog.EVO_TIME,
		"profiles": profiles, "third_open": third, "tags": tags, "arch_on": Tuning.g("build_arch") >= 0.5, "pairs_on": Cards.pairs_on()}


## Card `card` (a finalized offer) in `card_effect` terms for player `p`
static func card_of(p: Player, card: Dictionary) -> Dictionary:
	var r := clampi(int(card.get("rarity", 0)), 0, Cards.UP_LEVELS.size() - 1)
	match String(card["kind"]):
		"weapon_new":
			return {"weapon": card["weapon"], "add": Cards.NEW_WEAPON_LEVEL[r], "new": true}
		"weapon_up":
			return {"weapon": (p.groups[int(card["group"])] as Hardpoint).weapon, "add": Cards.UP_LEVELS[r]}
		"profile":
			return {"weapon": (p.groups[int(card["group"])] as Hardpoint).weapon, "add": 1}
		"module":
			if card["id"] == "skill3":
				return {"skill": true}
			return {"mod": card["id"]}
		"wing_new":
			return {"wing": true}
	return {}
