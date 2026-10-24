class_name HudIcons
extends RefCounted
## Icon tiles of the combat UI (HUD bar, pause blueprint, card pick, results build grid):
## a dark tile with a family-coloured glow, the picture, a round family disc bottom-left,
## an optional level number top-right and a frame that follows bevelled corners (combat UI
## mockup v2, Kanta 2026-10-24). Pictures: 3D weapon renders `art/ui_icons/w_*.jpg` (glow and
## disc already inside), schematic module and skill pictures `art/ui_icons/s_*.png`
## (tools/ui/render_icons.cjs), the in-game weapon sprites, and the vector `CardIcons` as the
## last resort. Final art comes from thread «Углубить прокачку для демо»; only the tables
## below change then. Static only; callers pass their Control.

## Full tiles with glow and family disc baked in, by weapon id
const WEAPON_TILES := {"aam": "w_aam", "rockets": "w_rockets", "bombs": "w_hebomb", "flares": "w_flares"}
## Schematic pictures by icon key (module id, skill id or "wingman")
const SCHEMATIC := {
	"engine": "s_engine", "wing": "s_flaps", "armor": "s_armor", "reload": "s_reload",
	"magnet": "s_magnet", "gun_dmg": "s_cannon", "radio": "s_radio", "repair": "s_hull",
	"res_kit": "s_hull", "afterburner": "s_ab", "roll": "s_evade", "dive": "s_dive",
	"combat_turn": "s_turn", "wingman": "s_wing",
}
## Class skill id → picture key until the skills get their own art (thread «Углубить
## прокачку для демо»); `tile()` resolves it, so every caller passes the skill id
const SKILL_ICON := {
	"yolka": "rockets", "carpet": "bombs", "sonic": "afterburner", "armor_shield": "armor",
	"assault": "dive", "rooks": "wingman", "umbrella": "wingman", "close_ranks": "wingman",
}
## Disc symbol of each family (tag ids from `Prog.TAGS` plus "skill" for class skills)
const DISC := {
	"missiles": &"crosshair", "blast": &"burst", "kinetic": &"bullet", "turrets": &"gear",
	"wing": &"star", "maneuver": &"chevron", "armor": &"shield", "skill": &"bolt", "maneuver_skill": &"bolt",
}
## Damage source prefix → icon key and family, checked in order (`source_icon`)
const SOURCE_ICONS := [
	["ракеты в-в", "aam", "missiles"], ["нар", "rockets", "missiles"], ["разделяющаяся", "aam", "missiles"],  # i18n-skip
	["бомбы", "bombs", "blast"], ["связка: ковров", "bombs", "blast"], ["курсовое", "gun_dmg", "kinetic"],  # i18n-skip
	["гондола", "gunpod", "kinetic"], ["турел", "turret", "turrets"], ["ведом", "wingman", "wing"],  # i18n-skip
	["эми", "emp", "blast"], ["лазер", "laser", "turrets"], ["рельсотрон", "railgun", "kinetic"],  # i18n-skip
	["плазма", "plasma", "blast"], ["ёлочка", "skill", "skill"], ["проход на форсаже", "afterburner", "maneuver_skill"],  # i18n-skip
	["бронещит", "armor", "skill"], ["связка", "synergy", "skill"],  # i18n-skip
]
## Tile background under the glow (mockup #1b1c19)
const TILE_BG := Color(0.106, 0.11, 0.098)
## Dark ink of disc symbols and outlines
const INK := Color(0.067, 0.067, 0.067)

static var _tex := {}
static var _glow: GradientTexture2D


## Loads every picture once; Hud calls it on creation so nothing loads mid-combat (code.md §7.5).
static func warm() -> void:
	for f: String in WEAPON_TILES.values():
		_load("res://art/ui_icons/%s.jpg" % f)
	for f: String in SCHEMATIC.values():
		_load("res://art/ui_icons/%s.png" % f)
	glow_texture()


## Colour of a family: tag colour, amber for class skills, maneuver blue for basic skills.
static func family_color(fam: String) -> Color:
	if fam == "skill":
		return UiStyle.ACCENT
	if fam == "maneuver_skill":
		return Prog.TAGS["maneuver"]["color"]
	if Prog.TAGS.has(fam):
		return Prog.TAGS[fam]["color"]
	return UiStyle.TEXT_2


## Family of a weapon id (its first tag), "kinetic" for the built-in gun.
static func weapon_family(w: String) -> String:
	var tags: Array = Prog.WEAPON_TAGS.get(w, ["kinetic"])
	return String(tags[0]) if not tags.is_empty() else "kinetic"


## Family of a level-up card: its first tag, "skill" for class skill cards.
static func card_family(p: Player, c: Dictionary) -> String:
	if String(c.get("id", "")) == "skill3":
		return "skill"
	var tags := Prog.card_tags(p, c)
	if not tags.is_empty():
		return String(tags[0])
	match String(c.get("kind", "")):
		"wing_new", "wing_lvl":
			return "wing"
		"evolution", "mastery", "synergy":
			return "skill"
	return "armor"


## Icon key of a level-up card: weapon id, module id, "wingman", or the `CardIcons` key.
static func card_key(p: Player, c: Dictionary) -> String:
	match String(c.get("kind", "")):
		"wing_new", "wing_lvl":
			return "wingman"
	if String(c.get("id", "")) == "skill3" and p != null:
		return p.skill3
	return CardIcons.key(c, p)


## Icon key and family of a damage source from `Main.stats["dealt"]` (pause screen
## «Урон за последнюю минуту», results damage list): [key, family] for `tile()`.
## Sources are Russian ids written by the combat code, so match by prefix.
static func source_icon(src: String) -> Array:
	var s := src.to_lower()
	for pair: Array in SOURCE_ICONS:
		if s.begins_with(String(pair[0])):
			return [pair[1], pair[2]]
	return ["module", "armor"]


## Player-facing name of a damage source, translated, with a capital first letter.
static func source_name(src: String) -> String:
	var s := Loc.t(String(HudResult.SRC_NAMES.get(src, src)))
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


## Radial glow, white in the centre; tiles tint it with the family colour.
static func glow_texture() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.42, Color(1, 1, 1, 0.45))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.48, 0.48)
		_glow.fill_to = Vector2(0.98, 0.48)
		_glow.width = 128
		_glow.height = 128
	return _glow


## Outline of a tile with the top-right and bottom-left corners cut by `cut` px
## (0 — plain square). Same shape for fill and frame, so the frame follows the cut.
static func tile_shape(r: Rect2, cut: float) -> PackedVector2Array:
	if cut <= 0.0:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	return PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut),
		r.end, Vector2(r.position.x + cut, r.end.y), Vector2(r.position.x, r.end.y - cut)])


## One icon tile in `r`. `key` — weapon id, module or skill id, "wingman" or a `CardIcons`
## key; `fam` — family (glow and disc); `frame` — border colour (rarity, level or
## Color.TRANSPARENT for none); `num` > 0 draws the level number top-right; `cut` bevels
## the corners; `dim` greys the picture (locked, on cooldown).
static func tile(ci: Control, r: Rect2, key: String, fam: String, frame: Color, num := -1,
		cut := 0.0, dim := false) -> void:
	key = SKILL_ICON.get(key, key)
	var shape := tile_shape(r, cut)
	ci.draw_colored_polygon(shape, TILE_BG)
	var fc := family_color(fam)
	var mod := Color(1, 1, 1, 0.45) if dim else Color.WHITE
	if WEAPON_TILES.has(key):
		_draw_clipped(ci, r, _load("res://art/ui_icons/%s.jpg" % WEAPON_TILES[key]), cut, mod)
	else:
		ci.draw_texture_rect(glow_texture(), r.grow(-r.size.x * 0.02), false, Color(fc.r, fc.g, fc.b, 0.9 * mod.a))
		if SCHEMATIC.has(key):
			ci.draw_texture_rect(_load("res://art/ui_icons/%s.png" % SCHEMATIC[key]), r, false, mod)
		else:
			var spr := PlaneArt.weapon_tex(key) if Weapons.DEFS.has(key) else null
			if spr != null:
				var k := r.size.x * 0.62 / maxf(spr.get_width(), spr.get_height())
				ci.draw_set_transform(r.get_center() + Vector2(r.size.x * 0.06, -r.size.y * 0.06), -PI / 4.0, Vector2(k, k))
				ci.draw_texture(spr, -spr.get_size() / 2.0, mod)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				CardIcons.draw(ci, r.get_center() + Vector2(r.size.x * 0.06, -r.size.y * 0.06), r.size.x * 0.56, key,
					Color(0.93, 0.93, 0.9, mod.a), false)
		disc(ci, r.position + Vector2(r.size.x * 0.215, r.size.y * 0.755), r.size.x * 0.155, fam)
	if dim:
		ci.draw_colored_polygon(shape, Color(0, 0, 0, 0.35))
	if frame.a > 0.0:
		var outline := shape.duplicate()
		outline.append(shape[0])
		ci.draw_polyline(outline, frame, maxf(1.5, r.size.x / 32.0))
	if num > 0:
		number(ci, Vector2(r.end.x - r.size.x * 0.09, r.position.y + r.size.y * 0.3), str(num), maxi(14, int(r.size.x * 0.3)))


## Level number with a dark outline, right-aligned at `pos` (baseline).
static func number(ci: Control, pos: Vector2, s: String, size: int) -> void:
	var f := UiStyle.head_font(800, 0)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string_outline(f, Vector2(pos.x - w, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, size / 5), Color(0, 0, 0, 0.85))
	ci.draw_string(f, Vector2(pos.x - w, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


## Round family disc with its symbol: lit from top-left like the mockup (darker rim, light
## spot), dark outline, symbol in INK.
static func disc(ci: Control, c: Vector2, rad: float, fam: String) -> void:
	var col := family_color(fam)
	ci.draw_circle(c + Vector2(0, rad * 0.12), rad + 2.5, Color(0, 0, 0, 0.55))
	ci.draw_circle(c, rad + 1.5, INK)
	ci.draw_circle(c, rad, col.darkened(0.4))
	ci.draw_circle(c + Vector2(-rad * 0.08, -rad * 0.1), rad * 0.86, col)
	ci.draw_circle(c + Vector2(-rad * 0.3, -rad * 0.35), rad * 0.38, col.lerp(Color.WHITE, 0.45))
	symbol(ci, c, rad * 0.62, DISC.get(fam, &"chevron"))


## Disc symbol of size ~2·`s` centred at `c` (24-unit drawings from the mockup's discs).
static func symbol(ci: Control, c: Vector2, s: float, sym: StringName) -> void:
	var u := s / 10.0
	match sym:
		&"chevron":
			ci.draw_colored_polygon(_pts(c, u, [[-8, 2], [0, -6], [8, 2], [5, 5], [0, 0], [-5, 5]]), INK)
		&"shield":
			ci.draw_colored_polygon(_pts(c, u, [[0, -10], [8, -7], [8, -1], [6, 5], [0, 10], [-6, 5], [-8, -1], [-8, -7]]), INK)
		&"star":
			var pts := PackedVector2Array()
			for i in 10:
				pts.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (s if i % 2 == 0 else s * 0.45))
			ci.draw_colored_polygon(pts, INK)
		&"bullet":
			ci.draw_colored_polygon(_pts(c, u, [[-3, 9], [-3, -3], [-2, -7], [0, -9], [2, -7], [3, -3], [3, 9]]), INK)
		&"bolt":
			ci.draw_colored_polygon(_pts(c, u, [[1, -10], [-8, 2], [-1, 2], [-3, 10], [6, -2], [-1, -2]]), INK)
		&"gear":
			ci.draw_arc(c, s * 0.5, 0.0, TAU, 20, INK, s * 0.28)
			for i in 8:
				var d := Vector2.from_angle(i * PI / 4.0)
				ci.draw_line(c + d * s * 0.62, c + d * s * 0.98, INK, s * 0.24)
		&"crosshair":
			ci.draw_arc(c, s * 0.62, 0.0, TAU, 24, INK, s * 0.2)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * s * 0.3, c + d * s, INK, s * 0.18)
			ci.draw_circle(c, s * 0.12, INK)
		&"burst":
			var pts2 := PackedVector2Array()
			for i in 16:
				pts2.append(c + Vector2.from_angle(i * PI / 8.0) * (s if i % 2 == 0 else s * 0.42))
			ci.draw_colored_polygon(pts2, INK)


static func _pts(c: Vector2, u: float, xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in xy:
		out.append(c + Vector2(float(p[0]), float(p[1])) * u)
	return out


## Square picture drawn into `r` through the tile outline, so cut corners stay cut.
static func _draw_clipped(ci: Control, r: Rect2, t: Texture2D, cut: float, mod: Color) -> void:
	if t == null:
		return
	var shape := tile_shape(r, cut)
	var uvs := PackedVector2Array()
	for p: Vector2 in shape:
		uvs.append((p - r.position) / r.size)
	ci.draw_colored_polygon(shape, mod, uvs, t)


static func _load(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]
