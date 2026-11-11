class_name AlbumArt
extends RefCounted
## Pictures of the build album entries (PG-16, Kanta 2026-11-11: «сразу нормально с картинками»). One in-game frame
## per entry, shot by `AlbumShots` (`-- --albumshots`) on the gameplay camera with the effect at work, saved as
## `res://art/album/<kind>_<id>.jpg` (the album id with ':' → '_'). A missing picture falls back to the entry's icon
## tile, so a new synergy shows before its frame is shot. Used by the card screen panel and the album tab.

const DIR := "res://art/album/"
## Picture aspect (frames are 16:9)
const ASPECT := 16.0 / 9.0

static var _tex := {}


## File name of entry `id`, without the folder: "syn_carousel.jpg", "prof_aam_pair.jpg"
static func file_of(id: String) -> String:
	return id.replace(":", "_") + ".jpg"


## Picture of entry `id`, or null when it is not shot yet
static func tex(id: String) -> Texture2D:
	if not _tex.has(id):
		var p := DIR + file_of(id)
		_tex[id] = load(p) if ResourceLoader.exists(p) else null
	return _tex[id]


## Draws the picture of `id` filling `r` (cropped to its aspect, never stretched), with a thin frame in `frame`.
## `dim` greys it (an entry this plane cannot build). Without a picture: the entry's icon on a dark tile.
static func draw(ci: Control, r: Rect2, id: String, frame: Color, dim := false) -> void:
	var t := tex(id)
	var mod := Color(0.55, 0.55, 0.58, 1.0) if dim else Color.WHITE
	if t != null:
		var ts := t.get_size()
		var k := maxf(r.size.x / ts.x, r.size.y / ts.y)
		var src := Rect2((ts - r.size / k) / 2.0, r.size / k)
		ci.draw_texture_rect_region(t, r, src, mod)
	else:
		ci.draw_rect(r, Color(0.05, 0.055, 0.05))
		var s := minf(r.size.y * 0.9, r.size.x * 0.5)
		HudIcons.tile(ci, Rect2(r.get_center() - Vector2(s, s) / 2.0, Vector2(s, s)), icon_key(id), icon_family(id), Color.TRANSPARENT, -1, 0.0, dim)
	if dim:
		ci.draw_rect(r, Color(0.02, 0.025, 0.03, 0.35))
	if frame.a > 0.0:
		ci.draw_rect(r, frame, false, 1.5)


## Icon key of entry `id` for `HudIcons.tile` (the fallback picture)
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
