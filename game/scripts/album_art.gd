class_name AlbumArt
extends RefCounted
## Icon of a build album entry: the result tile of a recipe formula (`RecipeArt`), the album list and the hangar
## album. In-game frames of the effects were tried first (PG-16) and dropped: on 3.5-s19 Kanta found they read as
## terrain screenshots that say nothing (2026-11-17), so every entry is shown by the cards it is built from.


## Icon key of entry `id` for `HudIcons.tile`
static func icon_key(id: String) -> String:
	match AlbumBook.kind(id):
		"syn":
			return "synergy"
		"evo":
			var w := Modernizations.weapon_of(id.get_slice(":", 1))
			return "gun" if w == "gun" else w
		"prof":
			return id.get_slice(":", 1)
		"arch":
			return id.get_slice(":", 1)
	return "synergy"


## Icon family of entry `id`
static func icon_family(id: String) -> String:
	match AlbumBook.kind(id):
		"evo":
			var w := Modernizations.weapon_of(id.get_slice(":", 1))
			return "kinetic" if w == "gun" else HudIcons.weapon_family(w)
		"prof":
			return HudIcons.weapon_family(id.get_slice(":", 1))
		"arch":
			return id.get_slice(":", 1)
	return "skill"
