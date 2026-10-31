class_name HudDecals
extends HudKit
## The hangar decal editor panel (spec 2026-10-27-plane-decals-design.md §6), drawn in the plane tab in place of the
## node cards while «Знаки ›» is open: the plane's decal list, the picture grid (locked pictures dimmed, with what
## opens them), preset spots, two paint rows, number digits, turn / size / mirror / other side / delete, key help.
## Only draws and lists its buttons (`hg:dc:...`); DecalEditInput does what they say.
## Gamepad: the d-pad walks `focus` over the panel's buttons (nearest one in that direction), A presses it.

const THUMB := 48            ## grid picture, px per atlas cell
const CELL := 64.0           ## grid cell with its gap
const ROW_H := 38.0          ## decal list row
const LIST_W := 330.0
## Picture names (the list rows, the locked caption)
const NAMES := {
	"skull_winged": "Крылатый череп", "skull_wrench": "Череп с ключами", "skull_flame": "Огненный череп",
	"bolt": "Молния", "ace_card": "Туз пик", "dice": "Кости", "chevrons": "Шевроны", "sun": "Солнце",
	"wasp": "Оса", "rook": "Грач", "whale": "Кит", "cat": "Чёрный кот", "shark_mouth": "Акулья пасть",
	"eye": "Глаз", "peaks": "Горы", "number": "Номер", "tally_air": "Счёт: воздух", "tally_ground": "Счёт: земля",
	"tally_bomb": "Счёт: бомбы", "shark_eye": "Акулий глаз",
}
## Preset spots (DecalPresets.NAMES) and their buttons
const SPOT_TITLE := {"nose": "Нос", "number": "Номер", "tally": "Счёт", "fin": "Киль", "wing": "Крыло"}

## Focused panel button for the gamepad (index into `_items`), -1 — none (the cursor is on the view)
static var focus := -1
static var _items: Array = []   ## [Rect2, action] of this frame's panel buttons
static var _atlas: Image
static var _thumbs := {}


## Action of the focused button ("" none)
static func focused_action() -> String:
	return String(_items[focus][1]) if focus >= 0 and focus < _items.size() else ""


## Moves the gamepad focus to the nearest button in direction `d` (the first button when nothing is focused)
static func move_focus(d: Vector2i) -> void:
	if _items.is_empty():
		focus = -1
		return
	if focus < 0 or focus >= _items.size():
		focus = 0
		return
	var from := (_items[focus][0] as Rect2).get_center()
	var dir := Vector2(d)
	var best := -1
	var best_score := INF
	for i in _items.size():
		if i == focus:
			continue
		var off := (_items[i][0] as Rect2).get_center() - from
		var along := off.dot(dir)
		if along < 4.0:
			continue
		var score := along + absf(off.dot(Vector2(-dir.y, dir.x))) * 2.5   # stay in the row / column
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		focus = best


## What opens a locked picture, for «откроется: …» (DecalUnlocks rules, translated)
static func need_text(id: String, cls: String) -> String:
	for owner: String in DecalUnlocks.MASCOTS:
		if DecalUnlocks.MASCOTS[owner] == id and owner != cls:
			return Loc.t("1 вылет — %s") % Loc.t(String(PlaneClasses.DATA[owner]["title"]))
	var rule: Dictionary = DecalUnlocks.RULES.get(id, {})
	if rule.has("crew"):
		return Loc.t("экипаж ур. %d") % int(rule["crew"])
	if rule.has("op"):
		return Loc.t("первая пройденная операция")
	match String(rule.get("c", "")):
		"evacs":
			return Loc.t("первая эвакуация")
		"sorties":
			return Loc.t("%d вылетов") % int(rule["n"])
		"aces":
			return Loc.t("первый сбитый ас")
		"fortresses":
			return Loc.t("первая сбитая «Крепость»")
	return "?"


## Draws the panel into `r` (the plane tab's right column)
func draw(m: Main, r: Rect2) -> void:
	var e := m.decal_edit
	if e == null:
		return
	_items.clear()
	var h3 := Hangar3D.I
	_panel(r, false)
	var x := r.position.x + 18.0
	var y := r.position.y
	_text(Vector2(x, y + 32), "ЗНАКИ НА САМОЛЁТЕ", 20, Color.WHITE)
	_text(Vector2(x + 260, y + 32), Loc.t("%d из %d") % [e.records.size(), DecalLoadout.MAX_DECALS], 16,
		Menu.C_AMBER if e.records.size() >= DecalLoadout.MAX_DECALS else Color(0.8, 0.84, 0.9))
	_btn(Rect2(r.end.x - 214, y + 10, 196, 38), "‹ Назад (Esc)", "hg:dc:close", 16)
	_list(e, Rect2(x, y + 62, LIST_W, r.size.y - 140))
	var rx := x + LIST_W + 24.0
	var rw := r.end.x - 18.0 - rx
	var gy := _grid(e, rx, y + 62, rw)
	gy = _presets(rx, gy + 8, rw)
	gy = _paints(e, rx, gy + 10)
	gy = _kind_row(e, rx, gy + 10, rw)
	_actions(e, rx, gy + 12, rw)
	var hy := r.end.y - 62.0
	if m.input_ctl.dc.note_t > 0.0:
		_text(Vector2(x, hy), m.input_ctl.dc.note, 15, Menu.C_AMBER)
	var pad := h3 != null and h3.decal_pad
	var help := Loc.t("Геймпад: стик — курсор, A — поставить / взять, B — снять выбор, LT / RT — размер, LB / RB — поворот, X — отразить, Y — цвет, крестовина — панель, правый стик — вид") if pad \
		else Loc.t("ЛКМ — поставить / взять и тащить, колесо — размер, Q / E — поворот (Shift — точно), F — отразить, Del — удалить, ПКМ — вращать вид")
	_para(Vector2(x, hy + 22), help, r.size.x - 36, 14, Color(0.7, 0.74, 0.8))
	if focus >= _items.size():
		focus = -1
	if focus >= 0:
		var fr: Rect2 = (_items[focus][0] as Rect2).grow(3)
		ctrl.draw_rect(fr, Color.WHITE, false, 2.0)


## A button that the gamepad focus can reach too
func _btn(r: Rect2, label: String, action: String, size := 15) -> void:
	_button(r, label, action, size)
	_items.append([r, action])


## A custom-drawn clickable area (picture cell, swatch, list row)
func _hot(r: Rect2, action: String) -> bool:
	_buttons.append([r, action])
	_items.append([r, action])
	var i := _items.size() - 1
	return r.has_point(ctrl.get_local_mouse_position()) or i == focus


## The plane's decals in draw order (later ones lie over earlier ones), the selected one lit
func _list(e: DecalEditor, r: Rect2) -> void:
	_text(Vector2(r.position.x, r.position.y + 14), "Порядок: нижние строки лежат поверх", 14, Color(0.65, 0.68, 0.75))
	var yy := r.position.y + 26.0
	if e.records.is_empty():
		_para(Vector2(r.position.x, yy + 24), "Пока пусто: выберите картинку справа и щёлкните по самолёту.", r.size.x, 15, Color(0.8, 0.84, 0.9))
		return
	for i in e.records.size():
		var rec := e.records[i]
		var row := Rect2(r.position.x, yy, r.size.x - 110, ROW_H - 4)
		var on := i == e.sel
		var hot := _hot(row, "hg:dc:sel:%d" % i)
		ctrl.draw_rect(row, Color(Menu.C_AMBER, 0.35) if on else Color(1, 1, 1, 0.1 if hot else 0.05))
		if on:
			ctrl.draw_rect(row, Menu.C_AMBER, false, 2.0)
		_thumb_at(rec.id, rec.c1, rec.c2, Rect2(row.position + Vector2(4, 3), Vector2(28, 28)), rec.text)
		var label := Loc.t(String(NAMES.get(rec.id, rec.id)))
		if DecalCatalog.kind(rec.id) == "number":
			label += " " + rec.text
		_text(Vector2(row.position.x + 40, row.position.y + 23), _fit(label, row.size.x - 46, 15), 15, Color.WHITE)
		var bx := row.end.x + 6.0
		_btn(Rect2(bx, yy, 32, ROW_H - 4), "▲", "hg:dc:up:%d" % i, 14)
		_btn(Rect2(bx + 36, yy, 32, ROW_H - 4), "▼", "hg:dc:down:%d" % i, 14)
		_btn(Rect2(bx + 72, yy, 32, ROW_H - 4), "✕", "hg:dc:del:%d" % i, 14)
		yy += ROW_H


## Picture grid; locked pictures dimmed, the hovered locked one says what opens it. Returns the y below it.
func _grid(e: DecalEditor, x: float, y: float, w: float) -> float:
	_text(Vector2(x, y + 14), "Картинка", 15, Color(0.8, 0.84, 0.9))
	var per := maxi(1, int(w / CELL))
	var col := 0
	var row := 0
	var gy := y + 24.0
	var why := ""
	for id: String in DecalCatalog.IMAGES:
		var cw := int(DecalCatalog.aspect(id))
		if col + cw > per:
			col = 0
			row += 1
		var cr := Rect2(x + col * CELL, gy + row * CELL, CELL * cw - 8, CELL - 8)
		var open := Profile.decal_open(id, e.cls)
		var hot := _hot(cr, "hg:dc:pic:" + id)
		var on := e.tool == id
		ctrl.draw_rect(cr, Color(Menu.C_AMBER, 0.3) if on else Color(1, 1, 1, 0.1 if hot else 0.04))
		_thumb_at(id, e.c1, e.c2, cr.grow(-4), e.text)
		if not open:
			ctrl.draw_rect(cr, Color(0.02, 0.025, 0.03, 0.62))
			_lock(cr.end - Vector2(12, 12))
		ctrl.draw_rect(cr, Menu.C_AMBER if on or hot else Color(1, 1, 1, 0.12), false, 2.0 if on else 1.0)
		if hot:
			why = Loc.t(String(NAMES.get(id, id))) + ("" if open else " — " + Loc.t("откроется: %s") % need_text(id, e.cls))
		col += cw
	var end := gy + (row + 1) * CELL
	if why != "":
		_text(Vector2(x, end + 12), _fit(why, w, 14), 14, Color(0.85, 0.88, 0.95))
	return end + 20.0


## Preset spots, left and right side. Returns the y below them.
func _presets(x: float, y: float, w: float) -> float:
	_text(Vector2(x, y + 14), "Готовое место (для выбранной картинки)", 15, Color(0.8, 0.84, 0.9))
	var bw := (w - 4 * 6.0) / 5.0
	var i := 0
	for spot: String in DecalPresets.NAMES:
		for side: int in [-1, 1]:
			var br := Rect2(x + i * (bw + 6), y + 22 + (0 if side < 0 else 36), bw, 30)
			_btn(br, Loc.t(String(SPOT_TITLE[spot])) + " " + (Loc.t("Л") if side < 0 else Loc.t("П")), "hg:dc:preset:%s:%d" % [spot, side], 14)
		i += 1
	return y + 22 + 66.0


## Two rows of paint swatches; the current paints (of the selected decal, else the tool) framed. Returns the y below.
func _paints(e: DecalEditor, x: float, y: float) -> float:
	var cur1 := e.records[e.sel].c1 if e.sel >= 0 else e.c1
	var cur2 := e.records[e.sel].c2 if e.sel >= 0 else e.c2
	for slot: int in [1, 2]:
		var yy := y + (slot - 1) * 40.0
		_text(Vector2(x, yy + 22), Loc.t("Цвет %d") % slot, 15, Color(0.8, 0.84, 0.9))
		var i := 0
		for id: String in DecalCatalog.PAINTS:
			var sr := Rect2(x + 76 + i * 40, yy, 34, 32)
			var hot := _hot(sr, "hg:dc:c%d:%s" % [slot, id])
			ctrl.draw_rect(sr, DecalCatalog.PAINTS[id])
			ctrl.draw_rect(sr, Color(1, 1, 1, 0.25), false, 1.0)   # black and gunmetal on the dark panel
			var on := id == (cur1 if slot == 1 else cur2)
			if on or hot:
				ctrl.draw_rect(sr.grow(2), Menu.C_AMBER if on else Color.WHITE, false, 2.0)
			i += 1
	return y + 78.0


## Number digits, or what the tally shows; nothing for a picture. Returns the y below.
func _kind_row(e: DecalEditor, x: float, y: float, w: float) -> float:
	var id := e.records[e.sel].id if e.sel >= 0 else e.tool
	match DecalCatalog.kind(id):
		"number":
			var t := DecalEditInput._text_now(e)
			_text(Vector2(x, y + 24), "Цифры", 15, Color(0.8, 0.84, 0.9))
			for i in t.length():
				var dx := x + 76 + i * 104.0
				_btn(Rect2(dx, y, 30, 34), "−", "hg:dc:digit:%d:-1" % i, 16)
				_text(Vector2(dx + 30, y + 26), t[i], 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 34)
				_btn(Rect2(dx + 64, y, 30, 34), "+", "hg:dc:digit:%d:1" % i, 16)
			var ax := x + 76 + 3 * 104.0
			_btn(Rect2(ax, y, 92, 34), Loc.t("+ цифра"), "hg:dc:digits:1", 14)
			_btn(Rect2(ax + 98, y, 92, 34), Loc.t("− цифра"), "hg:dc:digits:-1", 14)
			return y + 42.0
		"tally":
			var real := Main.I.input_ctl.dc.tally
			var s := Loc.t("Счёт побед класса: %d") % real
			if real < DecalEditor.PREVIEW_TALLY:
				s += " " + Loc.t("(в ангаре для примера %d)") % DecalEditor.PREVIEW_TALLY
			_text(Vector2(x, y + 22), _fit(s, w, 15), 15, Color(0.85, 0.88, 0.95))
			_text(Vector2(x, y + 42), _fit(Loc.t("Отметка — за каждого сбитого аса и «Крепость»"), w, 14), 14, Color(0.65, 0.68, 0.75))
			return y + 50.0
	return y


## Turn, size, mirror, other side, delete
func _actions(e: DecalEditor, x: float, y: float, w: float) -> void:
	var bw := (w - 3 * 6.0) / 4.0
	_btn(Rect2(x, y, bw, 34), Loc.t("↺ поворот"), "hg:dc:rot:1", 14)
	_btn(Rect2(x + bw + 6, y, bw, 34), Loc.t("↻ поворот"), "hg:dc:rot:-1", 14)
	_btn(Rect2(x + 2 * (bw + 6), y, bw, 34), Loc.t("Меньше"), "hg:dc:size:-1", 14)
	_btn(Rect2(x + 3 * (bw + 6), y, bw, 34), Loc.t("Больше"), "hg:dc:size:1", 14)
	var bw2 := (w - 2 * 6.0) / 3.0
	_btn(Rect2(x, y + 40, bw2, 34), Loc.t("Отразить"), "hg:dc:mirror", 14)
	if e.sel >= 0:
		_btn(Rect2(x + bw2 + 6, y + 40, bw2, 34), Loc.t("На другой борт"), "hg:dc:other", 14)
		_btn(Rect2(x + 2 * (bw2 + 6), y + 40, bw2, 34), Loc.t("Удалить"), "hg:dc:remove", 14)


## Small padlock drawn at `c` (locked picture)
func _lock(c: Vector2) -> void:
	var col := Color(0.9, 0.9, 0.92, 0.9)
	ctrl.draw_arc(c + Vector2(0, -4), 4.5, PI, TAU, 10, col, 2.0)
	ctrl.draw_rect(Rect2(c + Vector2(-6, -4), Vector2(12, 9)), col)


## The picture in the given paints inside `r` (aspect kept); a number shows `text`
func _thumb_at(id: String, c1: String, c2: String, r: Rect2, text: String) -> void:
	if DecalCatalog.kind(id) == "number":
		_text(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 8), text, int(clampf(r.size.y * 0.55, 14, 26)),
			DecalCatalog.PAINTS.get(c1, Color.WHITE), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var tex := _thumb(id, c1, c2)
	if tex == null:
		return
	var a := float(tex.get_width()) / float(tex.get_height())
	var sz := Vector2(r.size.y * a, r.size.y)
	if sz.x > r.size.x:
		sz = Vector2(r.size.x, r.size.x / a)
	ctrl.draw_texture_rect(tex, Rect2(r.get_center() - sz * 0.5, sz), false)


## The atlas mask of `id` coloured like the shader does (primary, secondary, ink by the R/G/B weights), cached
static func _thumb(id: String, c1: String, c2: String) -> Texture2D:
	var k := "%s|%s|%s" % [id, c1, c2]
	if _thumbs.has(k):
		return _thumbs[k]
	if _atlas == null:
		var src := load(DecalCatalog.ATLAS_PATH) as Texture2D
		if src == null:
			return null
		_atlas = src.get_image()
		if _atlas.is_compressed():
			_atlas.decompress()
		_atlas.clear_mipmaps()
		_atlas.convert(Image.FORMAT_RGBA8)
	if _thumbs.size() > 160:
		_thumbs.clear()
	var ur := DecalCatalog.image_rect(id)
	var full := Vector2(_atlas.get_size())
	var im := _atlas.get_region(Rect2i(Vector2i((ur.position * full).round()), Vector2i((ur.size * full).round())))
	var cells := int(DecalCatalog.aspect(id))
	im.resize(THUMB * 2 * cells, THUMB * 2, Image.INTERPOLATE_BILINEAR)
	im.resize(THUMB * cells, THUMB, Image.INTERPOLATE_BILINEAR)
	var p1: Color = DecalCatalog.PAINTS.get(c1, Color.WHITE)
	var p2: Color = DecalCatalog.PAINTS.get(c2, Color.WHITE)
	for py in im.get_height():
		for px in im.get_width():
			var c := im.get_pixel(px, py)
			var s := maxf(c.r + c.g + c.b, 1e-3)
			var col := (p1 * c.r + p2 * c.g + DecalCatalog.INK * c.b) / s
			im.set_pixel(px, py, Color(col.r, col.g, col.b, c.a))
	var tex := ImageTexture.create_from_image(im)
	_thumbs[k] = tex
	return tex
