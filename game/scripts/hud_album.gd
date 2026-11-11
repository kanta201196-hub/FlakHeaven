class_name HudAlbum
extends HudKit
## Hangar tab «АЛЬБОМ» (PG-11 B5, Kanta 2026-11-05): every synergy, modernization and weapon profile as a grid.
## Found entries are lit in their colour and show the class and the date of the first find; unfound ones are
## silhouettes with the recipe as a hint. The entry under the cursor (or the one clicked) is explained below.
## On in the demo too: collecting is the reason to play again. Data: `AlbumBook`, entries: `Profile`. PG-16: the
## detail shows the entry's in-game picture (`AlbumArt`); the same album is open in combat (`HudAlbumRun`).

const KIND_TITLE := {"syn": "Связка", "evo": "Модернизация", "prof": "Профиль оружия", "arch": "Архетип"}
const KIND_COLOR := {"syn": Color(1.0, 0.82, 0.25), "evo": Color(0.75, 0.55, 1.0), "prof": Color(0.55, 0.85, 1.0), "arch": Color(0.6, 1.0, 0.7)}


## Draws the album grid and the card of the entry under the cursor (or the selected one) inside `area`
func draw(m: Main, area: Rect2) -> void:
	var ids := Profile.album_ids()
	var album: Dictionary = Profile.data["album"]
	var detail_h := 110.0
	var cols := maxi(6, int(area.size.x / 200.0))
	var rows := int(ceil(ids.size() / float(cols)))
	var cw := area.size.x / cols
	var ch := minf(72.0, (area.size.y - detail_h - 12.0) / maxf(rows, 1))
	var mouse := ctrl.get_local_mouse_position()
	var show_id: String = m.hangar_album
	for i in ids.size():
		var id: String = ids[i]
		var cell := Rect2(area.position.x + (i % cols) * cw, area.position.y + (i / cols) * ch, cw, ch).grow(-3.0)
		var hover := cell.has_point(mouse)
		if hover:
			show_id = id
		var have := album.has(id)
		var col := entry_color(id)
		ctrl.draw_rect(cell, Color(col.r, col.g, col.b, 0.16) if have else Color(1, 1, 1, 0.03))
		var sel := id == m.hangar_album
		ctrl.draw_rect(cell, Menu.C_AMBER if sel else (col if have else Color(1, 1, 1, 0.12 + (0.15 if hover else 0.0))), false, 2.0 if sel else 1.0)
		_buttons.append([cell, "hg:album:" + id])
		var fs := 15 if ch >= 60.0 else 13
		_text(Vector2(cell.position.x + 8, cell.position.y + fs + 6), _fit(entry_title(id) if have else "? " + entry_title(id), cell.size.x - 16, fs), fs,
			UiStyle.TEXT if have else UiStyle.TEXT_OFF)
		if ch >= 48.0:
			var sub := found_line(album[id]) if have else Loc.t(String(KIND_TITLE[AlbumBook.kind(id)]))
			_text(Vector2(cell.position.x + 8, cell.position.y + fs + 26), _fit(sub, cell.size.x - 16, 12), 12, col if have else UiStyle.TEXT_DIM)
	_text(Vector2(area.position.x, area.position.y - 8), Loc.t("Найдено: %d из %d · первая находка: +%d запчастей") % [AlbumBook.found(album, ids), ids.size(), AlbumBook.PARTS_FIRST],
		15, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, area.size.x)
	_detail(show_id, album, Rect2(area.position.x, area.end.y - detail_h, area.size.x, detail_h))


## «Оса · 05.11.2026» — class and date of the first find (an entry migrated from an old save has neither)
static func found_line(e: Dictionary) -> String:
	var parts := PackedStringArray()
	var c := String(e.get("cls", ""))
	if PlaneClasses.DATA.has(c):
		parts.append(Loc.t(String(PlaneClasses.DATA[c]["title"])))
	var t := int(e.get("t", 0))
	if t > 0:
		var d := Time.get_date_dict_from_unix_time(t)
		parts.append("%02d.%02d.%d" % [int(d["day"]), int(d["month"]), int(d["year"])])
	return " · ".join(parts) if not parts.is_empty() else Loc.t("найдено раньше")


func _detail(id: String, album: Dictionary, r: Rect2) -> void:
	_panel(r, false)
	if id == "":
		_text(Vector2(r.position.x + 20, r.position.y + 40), Loc.t("Наведите на клетку — здесь, что это и как его собрать. Каждая первая находка даёт запчасти."), 16, UiStyle.TEXT_2)
		return
	var have := album.has(id)
	var col := entry_color(id)
	var head := "%s · %s" % [Loc.t(String(KIND_TITLE[AlbumBook.kind(id)])), entry_title(id)]
	if have:
		head += " · " + found_line(album[id])
	# PG-16: the entry's in-game picture on the left (greyed until found)
	var ph := minf(r.size.y - 16.0, r.size.x * 0.25 / AlbumArt.ASPECT)   # a short wide box keeps room for the text
	AlbumArt.draw(ctrl, Rect2(r.position.x + 8.0, r.position.y + 8.0, ph * AlbumArt.ASPECT, ph), id, Color(col, 0.7) if have else UiStyle.LINE, not have)
	var tx := r.position.x + 24.0 + ph * AlbumArt.ASPECT
	_text(Vector2(tx, r.position.y + 32), head, 21, col if have else UiStyle.TEXT)
	_para(Vector2(tx, r.position.y + 56), entry_desc(id), r.size.x * 0.6 - (tx - r.position.x), 15, UiStyle.TEXT_2)
	var rx := r.position.x + r.size.x * 0.6
	_text(Vector2(rx, r.position.y + 62), Loc.t("Как собрать:"), 15, UiStyle.TEXT_DIM)
	_para(Vector2(rx, r.position.y + 84), recipe(id), r.size.x * 0.38, 15, UiStyle.ACCENT_SOFT)


## Colour of an entry: the synergy's own colour, otherwise the colour of its kind
static func entry_color(id: String) -> Color:
	var k := AlbumBook.kind(id)
	if k == "syn":
		var sid := id.get_slice(":", 1)
		if Cards.SYNERGIES.has(sid):
			return Cards.SYNERGIES[sid]["color"]
		return Color(0.6, 1.0, 0.6)
	return KIND_COLOR.get(k, UiStyle.TEXT)


## Player name of an entry
static func entry_title(id: String) -> String:
	match AlbumBook.kind(id):
		"syn":
			var sk := _skill_of(id.get_slice(":", 1))
			if sk != "":
				return Loc.t(String(PlaneClasses.SKILL3[sk]["syn"]["title"]))
			return Loc.t(String(Cards.SYNERGIES.get(id.get_slice(":", 1), {}).get("title", id)))
		"evo":
			return Loc.t(String(Modernizations.def(id.get_slice(":", 1)).get("title", id)))
		"prof":
			var w := id.get_slice(":", 1)
			return "%s: %s" % [Loc.t(String(Weapons.DEFS[w]["short"])), Loc.t(String(WeaponProfiles.def(w, id.get_slice(":", 2)).get("title", id)))]
		"arch":
			return "%s III" % Loc.t(String(ArchBalance.DEFS.get(id.get_slice(":", 1), {}).get("title", id)))
	return id


## What an entry does
static func entry_desc(id: String) -> String:
	match AlbumBook.kind(id):
		"syn":
			var sk := _skill_of(id.get_slice(":", 1))
			if sk != "":
				return Loc.t(String(PlaneClasses.SKILL3[sk]["syn"]["desc"]))
			return Loc.t(String(Cards.SYNERGIES.get(id.get_slice(":", 1), {}).get("desc", "")))
		"evo":
			return Loc.t(String(Modernizations.def(id.get_slice(":", 1)).get("desc", "")))
		"prof":
			return Loc.t(String(WeaponProfiles.def(id.get_slice(":", 1), id.get_slice(":", 2)).get("desc", "")))
		"arch":
			var ad: Dictionary = ArchBalance.DEFS.get(id.get_slice(":", 1), {})
			return Loc.t(String(ad["ranks"][2]["desc"])) if not ad.is_empty() else ""
	return ""


## Recipe of an entry, as a hint for the silhouette
static func recipe(id: String) -> String:
	match AlbumBook.kind(id):
		"syn":
			var sid := id.get_slice(":", 1)
			var sk := _skill_of(sid)
			if not Cards.pairs_on() or SynPairs.req(sid).is_empty():
				return Loc.t("Связка за очки тегов (справочник в бою)")
			var parts := PackedStringArray()
			for t in SynPairs.req(sid):
				if t.has("skill"):
					parts.append(Loc.t("навык «%s»") % Loc.t(String(PlaneClasses.SKILL3[sk]["title"])))
				else:
					parts.append(Cards.pair_thing_title(null, t))
			var c0 := SynPairs.cost(0)
			return Loc.t("%s — в одном вылете; первый слот связки — ур. %d / ×%d у каждого") % [" + ".join(parts), int(c0["lvl"]), int(c0["mods"])]
		"evo":
			var eid := id.get_slice(":", 1)
			var w := Modernizations.weapon_of(eid)
			var cat := PackedStringArray()
			var c: Dictionary = Modernizations.cat(eid)
			for mk in c:
				cat.append("«%s» ×%d" % [Loc.t(String(Cards.MODULES[mk]["title"])), int(c[mk])])
			var wn := Loc.t("Пушка") if w == "gun" else Loc.t(String(Weapons.DEFS[w]["short"]))
			return Loc.t("%s ур. 5 + %s, с 7:00 вылета") % [wn, ", ".join(cat)]
		"prof":
			return Loc.t("%s: выбор профиля на ур. %d") % [Loc.t(String(Weapons.DEFS[id.get_slice(":", 1)]["short"])), WeaponProfiles.LEVEL]
		"arch":
			var tg := id.get_slice(":", 1)
			if not ArchBalance.ARCH_AT.has(tg):
				return ""
			return Loc.t("%d очков «%s» за вылет — карточки этого тега") % [int(ArchBalance.at_of(tg)[2]), Loc.t(Prog.tag_title(tg))]
	return ""


## Class skill whose synergy is `sid` ("" — a weapon synergy)
static func _skill_of(sid: String) -> String:
	for sk in PlaneClasses.SKILL3:
		if PlaneClasses.SKILL3[sk]["syn"]["id"] == sid:
			return sk
	return ""
