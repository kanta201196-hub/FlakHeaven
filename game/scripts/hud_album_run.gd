class_name HudAlbumRun
extends HudKit
## Pause tab «АЛЬБОМ» (PG-16, sketch `genre_research/album_example_pause.jpg`, Kanta 2026-11-11). The build album
## seen from the plane in the air: on top what this sortie has already collected, then what this plane can still
## build with the recipe of each (met things green with ✓, missing ones amber with «сейчас N»), the chosen
## specialization first, then the furthest along; below, greyed, what this plane can never build and why.
## Right: the selected entry — its in-game picture (`AlbumArt`), what it does, have / need, and the parts for a
## first find. Opened from the pause tab strip (Q / E, LB / RB, or a click) and with Tab from the card pick; Esc and
## Tab go back where it came from. Rows: `AlbumNear`; names, colours, descriptions: `HudAlbum`.

const ROW_H := 78.0
const HEAD_H := 46.0
const THUMB := Vector2(112.0, 63.0)
## Section titles: collected this sortie, can collect, cannot on this plane
const SECTIONS := ["СОБРАНО В ЭТОМ ВЫЛЕТЕ", "МОЖНО СОБРАТЬ В ЭТОМ ВЫЛЕТЕ", "НА ЭТОМ САМОЛЁТЕ НЕ СОБРАТЬ"]
## Pause tabs: action and title
const TABS := [["tab_build", "СБОРКА"], ["tab_album", "АЛЬБОМ"]]

## Selected row (index into this frame's flat list) and the first visible list pixel
static var sel := 0
static var scroll := 0.0
## Ids of the rows in list order, from the last draw (keyboard navigation reads its size)
static var _ids: Array = []
## Mouse position of the last frame: hovering selects only when the mouse moves (as on the card pick)
static var _last_mp := Vector2(-1.0, -1.0)


## Draws the album tab over the frozen fight
func draw(m: Main, size: Vector2) -> void:
	var p := m.player
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.SCRIM, 0.92))
	HudPause.draw_crumb(ctrl, m)
	tabs(ctrl, _buttons, size, 1, m.album_back == "levelup")
	if not is_instance_valid(p):
		return
	var ctx := AlbumNear.ctx_of(p, m.run_time)
	var ids := Profile.album_ids()
	var sec := AlbumNear.sections(AlbumNear.rows(ctx, ids))
	var list := Rect2(40, 110, 900, size.y - 200.0)
	var flat := _list(sec, list, Profile.data["album"])
	var right := Rect2(list.end.x + 32.0, 110, size.x - list.end.x - 72.0, size.y - 200.0)
	if not flat.is_empty():
		_detail(flat[clampi(sel, 0, flat.size() - 1)], ctx, Profile.data["album"], right)
	_hints(size, m.album_back == "levelup")


## The pause tab strip at the top centre: `on` — the open tab; from the card pick the first tab reads «КАРТОЧКИ».
## Shared with `HudPause`, so both tabs look the same.
static func tabs(ci: Control, buttons: Array, size: Vector2, on: int, from_cards := false) -> void:
	var w := 210.0
	# right-aligned: the crumb on the left grows with the operation name and the language
	var x := size.x - 40.0 - 52.0 - TABS.size() * (w + 8.0)
	var f := UiStyle.head_font(700, 4)
	var mp := ci.get_local_mouse_position()
	for i in TABS.size():
		var r := Rect2(x + i * (w + 8.0), 26.0, w, 48.0)
		var hover := r.has_point(mp)
		var label := Loc.t("КАРТОЧКИ") if from_cards and i == 0 else Loc.t(String(TABS[i][1]))
		if i == on:
			ci.draw_rect(r, UiStyle.ACCENT)
			UiStyle.text(ci, f, Vector2(r.position.x, r.position.y + 32), label, UiStyle.FS_LABEL, UiStyle.ON_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, w)
		else:
			ci.draw_rect(r, Color(1, 1, 1, 0.1 if hover else 0.05))
			ci.draw_rect(r, UiStyle.LINE, false, 1.0)
			UiStyle.text(ci, f, Vector2(r.position.x, r.position.y + 32), label, UiStyle.FS_LABEL, UiStyle.TEXT if hover else UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_CENTER, w)
		buttons.append([r, String(TABS[i][0])])
	UiStyle.key_hint(ci, Vector2(x - 52.0, 60.0), key_label("tab_prev"), "")
	UiStyle.key_hint(ci, Vector2(x + TABS.size() * (w + 8.0) + 4.0, 60.0), key_label("tab_next"), "")


# ---------- list ----------

## Draws the three sections into `r` with scrolling; returns the rows in list order
func _list(sec: Array, r: Rect2, album: Dictionary) -> Array:
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	var flat: Array = []
	var tops: Array = []   # y of each row inside the list content
	var heads: Array = []  # [y, title] of each section header
	var y := 0.0
	for si in 3:
		var rows: Array = sec[si]
		if rows.is_empty():
			continue
		heads.append([y, SECTIONS[si], si])
		y += HEAD_H
		for row: Dictionary in rows:
			flat.append(row)
			tops.append(y)
			y += ROW_H
	_ids = flat.map(func(x: Dictionary) -> String: return String(x["id"]))
	if flat.is_empty():
		_text(r.position + Vector2(24, 48), Loc.t("Записей альбома для этого самолёта нет"), UiStyle.FS_BODY, UiStyle.TEXT_2)
		return flat
	sel = clampi(sel, 0, flat.size() - 1)
	# keep the selected row in view
	var view_h := r.size.y - 16.0
	var st: float = tops[sel]
	if st - HEAD_H < scroll:
		scroll = maxf(0.0, st - HEAD_H)
	elif st + ROW_H > scroll + view_h:
		scroll = st + ROW_H - view_h
	scroll = clampf(scroll, 0.0, maxf(0.0, y - view_h))
	var mp := ctrl.get_local_mouse_position()
	var moved := mp != _last_mp
	_last_mp = mp
	var top := r.position.y + 8.0 - scroll
	var clip_top := r.position.y + 4.0
	var clip_bot := r.end.y - 4.0
	for h: Array in heads:
		var hy := top + float(h[0])
		if hy < clip_top - 1.0 or hy + HEAD_H > clip_bot + 1.0:
			continue
		if float(h[0]) > 0.0:
			ctrl.draw_line(Vector2(r.position.x, hy), Vector2(r.end.x, hy), UiStyle.LINE, 1.0)
		UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(r.position.x + 22, hy + 32), Loc.t(String(h[1])), UiStyle.FS_LABEL,
			UiStyle.TEXT_2 if int(h[2]) == 2 else UiStyle.ACCENT_SOFT)
	for i in flat.size():
		var ry: float = top + float(tops[i])
		if ry < clip_top - 1.0 or ry + ROW_H > clip_bot + 1.0:
			continue
		var rr := Rect2(r.position.x + 8.0, ry, r.size.x - 16.0, ROW_H - 4.0)
		if moved and rr.has_point(mp):
			sel = i
		_buttons.append([rr, "album_sel:%d" % i])
		_row(flat[i], rr, i == sel, album)
	# scroll marks
	if scroll > 0.5:
		UiStyle.text(ctrl, UiStyle.head_font(700, 0), Vector2(r.position.x, r.position.y + 22), "▲", UiStyle.FS_CAPTION, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 18.0)
	if y - scroll > view_h + 0.5:
		UiStyle.text(ctrl, UiStyle.head_font(700, 0), Vector2(r.position.x, r.end.y - 8), "▼", UiStyle.FS_CAPTION, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 18.0)
	return flat


## One list row: picture, name · kind, and the recipe (or why this plane cannot build it)
func _row(row: Dictionary, r: Rect2, on: bool, album: Dictionary) -> void:
	var id := String(row["id"])
	var reach: bool = row["reach"] or row["done"]
	var col := HudAlbum.entry_color(id)
	if on:
		ctrl.draw_rect(r, Color(UiStyle.ACCENT, 0.1))
		UiStyle.brackets(ctrl, r, UiStyle.ACCENT)
	var th := Rect2(r.position.x + 12.0, r.position.y + (r.size.y - THUMB.y) / 2.0, THUMB.x, THUMB.y)
	AlbumArt.draw(ctrl, th, id, Color(col, 0.8) if reach else UiStyle.LINE, not reach)
	var tx := th.end.x + 18.0
	var nf := UiStyle.head_font(700, 1)
	var name := HudAlbum.entry_title(id)
	UiStyle.text(ctrl, nf, Vector2(tx, r.position.y + 28), name, UiStyle.FS_LABEL, UiStyle.TEXT if reach else UiStyle.TEXT_OFF)
	var kind := Loc.t(String(HudAlbum.KIND_TITLE[AlbumBook.kind(id)])).to_lower()
	var tags := PackedStringArray([kind])
	if row["course"]:
		tags.append(Loc.t("ваша специализация"))
	if not album.has(id):
		tags.append(Loc.t("новое для альбома"))
	var nx := tx + UiStyle.text_w(nf, name, UiStyle.FS_LABEL) + 10.0
	UiStyle.text(ctrl, ui_font(), Vector2(nx, r.position.y + 28), "· " + " · ".join(tags), UiStyle.FS_CAPTION,
		UiStyle.ACCENT if row["course"] else UiStyle.TEXT_DIM)
	var ly := r.position.y + 54.0
	var w := r.end.x - tx - 16.0
	if row["done"]:
		UiStyle.text(ctrl, ui_font(), Vector2(tx, ly), "✓ " + Loc.t("собрано в этом вылете"), UiStyle.FS_BODY, UiStyle.OK)
	elif not row["reach"]:
		UiStyle.text(ctrl, ui_font(), Vector2(tx, ly), _fit(_recipe_plain(row) + " · " + why_text(row), w, UiStyle.FS_BODY), UiStyle.FS_BODY, UiStyle.TEXT_OFF)
	else:
		recipe_line(ctrl, Vector2(tx, ly), row["things"], w, UiStyle.FS_BODY)
		if row.get("late", false):
			UiStyle.text(ctrl, ui_font(), Vector2(r.position.x, ly), Loc.t("с 7:00"), UiStyle.FS_CAPTION, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14.0)


## Recipe of a row as plain text (unreachable rows, grey): «Пушка ×2 + Турели 3»
func _recipe_plain(row: Dictionary) -> String:
	var parts := PackedStringArray()
	for t: Dictionary in row["things"]:
		parts.append(thing_text(t, false))
	return " + ".join(parts)


## One thing of a recipe: «Ракеты В-В 4 ✓» when met, «Ловушки 3 (сейчас 2)» when `live` and missing,
## «Ловушки 3» otherwise
static func thing_text(t: Dictionary, live := true) -> String:
	var name := tr_name(String(t["name"]))
	if String(t.get("fmt", "")) != "":
		name = Loc.t(String(t["fmt"])) % name
	var unit := String(t["unit"])
	var need := int(t["need"])
	var have := int(t["have"])
	var amount := ("×%d" % need) if unit == "×" else (("%d %s" % [need, Loc.t(unit)]) if unit == "оч." else str(need))
	var s := (name + " " + amount).strip_edges()
	if not live:
		return s
	if have >= need:
		return s + " ✓"
	return s + Loc.t(" (сейчас %d)") % have


## Translated reason row `row` cannot be built: its template with the translated name in it
static func why_text(row: Dictionary) -> String:
	var w := Loc.t(String(row.get("why", "")))
	return w % tr_name(String(row.get("why_arg", ""))) if w.contains("%s") else w


## Translated thing name: a joined name («Ловушки/Турели», «Двигатель + Форсаж») is translated part by part
static func tr_name(s: String) -> String:
	if s.contains(" + "):
		return " + ".join(PackedStringArray(Array(s.split(" + ")).map(func(x): return tr_name(String(x)))))
	if s.contains("/"):
		return "/".join(PackedStringArray(Array(s.split("/")).map(func(x): return Loc.t(String(x)))))
	return Loc.t(s)


## Recipe drawn as coloured pieces joined by « + »: met things green, missing ones amber. Cut with «…» at `w`.
static func recipe_line(ci: Control, pos: Vector2, things: Array, w: float, fs: int) -> void:
	var f := HudKit.ui_font()
	var x := pos.x
	for i in things.size():
		var t: Dictionary = things[i]
		var s := thing_text(t)
		if i > 0:
			s = " + " + s
		var tw := UiStyle.text_w(f, s, fs)
		var col := UiStyle.OK if int(t["have"]) >= int(t["need"]) else UiStyle.ACCENT_SOFT
		if x + tw > pos.x + w:
			UiStyle.text(ci, f, Vector2(x, pos.y), " …", fs, UiStyle.TEXT_DIM)
			return
		if i > 0:
			var pw := UiStyle.text_w(f, " + ", fs)
			UiStyle.text(ci, f, Vector2(x, pos.y), " + ", fs, UiStyle.TEXT_2)
			UiStyle.text(ci, f, Vector2(x + pw, pos.y), s.substr(3), fs, col)
		else:
			UiStyle.text(ci, f, Vector2(x, pos.y), s, fs, col)
		x += tw


# ---------- detail ----------

func _detail(row: Dictionary, ctx: Dictionary, album: Dictionary, r: Rect2) -> void:
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	var id := String(row["id"])
	var col := HudAlbum.entry_color(id)
	var x := r.position.x + 28.0
	var w := r.size.x - 56.0
	UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(x, r.position.y + 50), HudAlbum.entry_title(id), UiStyle.FS_H2, col)
	var sub := Loc.t(String(HudAlbum.KIND_TITLE[AlbumBook.kind(id)]))
	if album.has(id):
		sub += " · " + Loc.t("в альбоме: ") + HudAlbum.found_line(album[id])
	else:
		sub += " · " + Loc.t("ещё не найдена")
	UiStyle.text(ctrl, ui_font(), Vector2(x, r.position.y + 80), sub, UiStyle.FS_BODY, UiStyle.TEXT_2)
	# the picture: 16:9 across the panel, capped so the text below keeps its room
	var pw := minf(w, (r.size.y - 330.0) * AlbumArt.ASPECT)
	var pic := Rect2(x + (w - pw) / 2.0, r.position.y + 100.0, pw, pw / AlbumArt.ASPECT)
	AlbumArt.draw(ctrl, pic, id, Color(col, 0.7), not (row["reach"] or row["done"]))
	var y := pic.end.y + 36.0
	y += _para(Vector2(x, y), Loc.t("Что делает: ") + HudAlbum.entry_desc(id), w, UiStyle.FS_LABEL, UiStyle.TEXT_WARM) + 14.0
	if row["done"]:
		UiStyle.text(ctrl, ui_font(), Vector2(x, y), "✓ " + Loc.t("Собрано в этом вылете"), UiStyle.FS_LABEL, UiStyle.OK)
		y += 30.0
	elif not row["reach"]:
		UiStyle.text(ctrl, ui_font(), Vector2(x, y), Loc.t("Рецепт: ") + _recipe_plain(row), UiStyle.FS_LABEL, UiStyle.TEXT_2)
		y += 30.0
		UiStyle.text(ctrl, ui_font(), Vector2(x, y), Loc.t("На этом самолёте не собрать: ") + why_text(row), UiStyle.FS_LABEL, UiStyle.TEXT_OFF)
		y += 30.0
	else:
		var have := PackedStringArray()
		var need := PackedStringArray()
		for t: Dictionary in row["things"]:
			if int(t["have"]) >= int(t["need"]):
				have.append(thing_text(t, false))
			else:
				need.append(thing_text(t))
		if not have.is_empty():
			UiStyle.text(ctrl, ui_font(), Vector2(x, y), _fit(Loc.t("Есть: ") + ", ".join(have), w, UiStyle.FS_LABEL), UiStyle.FS_LABEL, UiStyle.OK)
			y += 30.0
		if not need.is_empty():
			UiStyle.text(ctrl, ui_font(), Vector2(x, y), _fit(Loc.t("Нужно: ") + ", ".join(need), w, UiStyle.FS_LABEL), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT)
			y += 30.0
		var note := _note(row, ctx)
		if note != "":
			UiStyle.text(ctrl, ui_font(), Vector2(x, y), _fit(note, w, UiStyle.FS_BODY), UiStyle.FS_BODY, UiStyle.TEXT_2)
			y += 28.0
	if not album.has(id):
		UiStyle.text(ctrl, ui_font(), Vector2(x, y + 8.0), Loc.t("Первая находка: +%d запчастей") % AlbumBook.PARTS_FIRST, UiStyle.FS_BODY, UiStyle.PARTS)


## How a met recipe turns into the entry: a synergy needs to be the specialization, a modernization waits for 7:00
static func _note(row: Dictionary, ctx: Dictionary) -> String:
	match String(row["kind"]):
		"syn":
			if row["course"]:
				return Loc.t("Ваша специализация: когда рецепт готов, связка придёт карточкой.")
			if String(ctx.get("course", "")) != "":
				return Loc.t("Связка придёт карточкой, если выбрать её специализацией (смена — за один переброс).")
			return Loc.t("Связка придёт карточкой, если выбрать её специализацией.")
		"evo":
			return Loc.t("Модернизация придёт карточкой с 7:00 вылета, когда рецепт готов.")
		"prof":
			return Loc.t("Профиль выбирается карточкой на ур. %d оружия.") % WeaponProfiles.LEVEL
		"arch":
			return Loc.t("Очки дают карточки этого тега.")
	return ""


func _hints(size: Vector2, from_cards: bool) -> void:
	var pairs := [["↑ ↓", Loc.t("запись")], [key_label("loadout"), Loc.t("к карточкам") if from_cards else Loc.t("к сборке")],
		[key_label("pause"), Loc.t("к карточкам") if from_cards else Loc.t("продолжить")]]
	var w := 0.0
	for pr: Array in pairs:
		w += UiStyle.text_w(UiStyle.head_font(700, 1), String(pr[0]), UiStyle.FS_CAPTION) + 18.0 + 10.0 \
			+ UiStyle.text_w(UiStyle.head_font(600, 3), String(pr[1]).to_upper(), UiStyle.FS_BODY) + 34.0
	var r := Rect2(size.x / 2.0 - w / 2.0 - 20.0, size.y - 66.0, w + 6.0, 46.0)
	ctrl.draw_rect(r, Color(0.04, 0.045, 0.04, 0.9))
	ctrl.draw_rect(r, UiStyle.LINE, false, 1.0)
	var x := r.position.x + 20.0
	for pr: Array in pairs:
		x = UiStyle.key_hint(ctrl, Vector2(x, r.position.y + 31.0), String(pr[0]), String(pr[1]).to_upper())


## ↑/↓ in the album tab
static func move(dir: int) -> void:
	if _ids.is_empty():
		return
	sel = clampi(sel + dir, 0, _ids.size() - 1)
