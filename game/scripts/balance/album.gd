class_name AlbumBook
extends RefCounted
## Build album (PG-11 part B5, Kanta 2026-11-05): every synergy, modernization and weapon profile the player has
## ever found, with the class and the date of the first find. It is the reason to play again («собирательство»),
## so it is on in the demo too (medals are not). The first find of an entry gives `PARTS_FIRST` parts.
## Saved in `profile.json` as `album: {id: {"t": unix, "cls": class id}}`.
## Entry ids: "syn:<synergy id>" (weapon and class-skill synergies), "evo:<modernization id>",
## "prof:<weapon>:<profile id>". Part A adds "arch:<tag>" for rank III of an archetype through `ARCH_IDS`.
## Pure data and rules; `Profile` keeps the dictionary, `HudAlbum` draws it. Plan: docs/superpowers/plans/2026-11-05-build-depth.md.

## Parts for the first find of one entry (first guess)
const PARTS_FIRST := 15

## Archetype entries (rank III), filled by part A of PG-11; empty until then
const ARCH_IDS: Array = []


## Every entry id in album order: weapon synergies, class-skill synergies, modernizations, weapon profiles,
## archetypes. `syn_ids` — weapon synergy ids that exist under the current rules (`Cards.syn_offered`).
static func ids(syn_ids: Array, skill_syn_ids: Array, evo_ids: Array, profiles: Dictionary) -> Array:
	var out: Array = []
	for s in syn_ids:
		out.append("syn:" + String(s))
	for s in skill_syn_ids:
		out.append("syn:" + String(s))
	for e in evo_ids:
		out.append("evo:" + String(e))
	for w in profiles:
		for pid in profiles[w]:
			out.append("prof:%s:%s" % [w, pid])
	for a in ARCH_IDS:
		out.append("arch:" + String(a))
	return out


## Kind of entry `id`: "syn", "evo", "prof" or "arch"
static func kind(id: String) -> String:
	return id.get_slice(":", 0)


## A clean album from a saved value: keeps only entries with a string id and a dictionary {t, cls};
## anything else (a missing key in an old save, a broken file) gives an empty album
static func parse(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		var e: Variant = v[k]
		if k is String and String(k).contains(":") and e is Dictionary:
			out[k] = {"t": int((e as Dictionary).get("t", 0)), "cls": String((e as Dictionary).get("cls", ""))}
	return out


## Migration of a save made before the album: the synergies counted by the medals become found entries
## with no date (t = 0) and no class, and give no parts. Entries already in the album stay as they are.
static func migrate(album: Dictionary, medal_syn: Array) -> void:
	for s in medal_syn:
		var id := "syn:" + String(s)
		if not album.has(id):
			album[id] = {"t": 0, "cls": ""}


## Adds entry `id` found by class `cls` at unix time `t`; returns true on the first find
static func add(album: Dictionary, id: String, cls: String, t: int) -> bool:
	if album.has(id):
		return false
	album[id] = {"t": t, "cls": cls}
	return true


## How many of `all_ids` are found
static func found(album: Dictionary, all_ids: Array) -> int:
	return all_ids.filter(func(x): return album.has(x)).size()


## Parts for `n` first finds in one sortie
static func parts_for(n: int) -> int:
	return PARTS_FIRST * maxi(n, 0)
