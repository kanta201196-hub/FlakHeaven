class_name RecipeArt
extends RefCounted
## A build album recipe drawn as a formula: the ingredient cards as icons with their progress, then «→» and
## the result (Kanta 2026-11-17 on 3.5-s19: «по картинкам ничего не понятно» about the in-game frames of the
## effects). The player already knows these icons from the level-up cards, so the recipe reads as «take this
## card and this card», with the pips showing how far each one is. Used by the card screen panel and the album tab.

## Ingredient met / missing / raised by the focused card
const MET := UiStyle.OK
const MISS := Color(0.85, 0.82, 0.72, 0.35)


## Hover hint panel width, px
const TIP_W := 380.0


## Draws `row` (an `AlbumNear` row) as «[icon] + [icon] → [result]» inside `r`, icons `s` px high, labels under
## each icon. `ctx` — the `AlbumNear` context (which weapon of a choice this plane carries); `hot` — the thing
## index the focused card raises (-1 none), framed in the accent colour with «▲». `hits` (optional) collects
## [icon rect, row, thing index or -1 for the result] for `tooltip` (Kanta 2026-11-17: names and explanations
## on mouse hover, so the screen stays clean).
static func draw(ci: Control, r: Rect2, row: Dictionary, ctx: Dictionary, s: float, hot := -1, hits: Array = []) -> void:
	var things: Array = row["things"]
	var n := things.size()
	var f := HudKit.ui_font()
	var fs := UiStyle.FS_CAPTION if s < 80.0 else UiStyle.FS_BODY
	var sign_w := s * 0.42
	var slot := (r.size.x - s - sign_w * n) / maxf(1.0, float(n))   # each ingredient: icon + its label width
	slot = minf(slot, s * 2.6)
	var x := r.position.x
	var y := r.position.y
	for i in n:
		var t: Dictionary = things[i]
		var ok := int(t["have"]) >= int(t["need"])
		var ic := AlbumNear.thing_icon(ctx, t.get("src", {}))
		var frame := UiStyle.ACCENT if i == hot else (MET if ok else MISS)
		var tr := Rect2(x + (slot - s) / 2.0, y, s, s)
		hits.append([tr, row, i])
		HudIcons.tile(ci, tr, String(ic[0]), String(ic[1]), frame, -1, s * 0.16, int(t["have"]) == 0 and i != hot)
		if ok:
			_check(ci, tr.end - Vector2(s * 0.2, s * 0.2), s * 0.17)
		if i == hot:
			UiStyle.text(ci, UiStyle.head_font(700, 0), Vector2(tr.end.x - s * 0.22, tr.position.y + s * 0.3), "▲", int(s * 0.28), UiStyle.ACCENT)
		var label := HudAlbumRun.tr_name(AlbumNear.thing_short(ctx, t.get("src", {})))
		if label == "":
			label = HudAlbumRun.tr_name(String(t["name"]))
		_center(ci, f, Vector2(x + slot / 2.0, y + s + fs + 6.0), _fit(f, label, slot - 4.0, fs), fs, UiStyle.TEXT_2)
		_pips(ci, Vector2(x + slot / 2.0, y + s + fs + 14.0), int(t["have"]), int(t["need"]), String(t["unit"]), s, ok, i == hot)
		x += slot
		_center(ci, UiStyle.head_font(700, 0), Vector2(x + sign_w / 2.0, y + s * 0.62), "→" if i == n - 1 else "+", int(s * 0.42),
			UiStyle.TEXT_DIM)
		x += sign_w
	var id := String(row["id"])
	var col := HudAlbum.entry_color(id)
	var rr := Rect2(x, y, s, s)
	hits.append([rr, row, -1])
	HudIcons.tile(ci, rr, AlbumArt.icon_key(id), AlbumArt.icon_family(id), Color(col, 0.95 if row.get("done", false) else 0.6), -1,
		s * 0.16, not bool(row.get("reach", true)))
	ci.draw_rect(rr.grow(3.0), Color(col, 0.25), false, 2.0)


## Hover hint for the icon under the mouse `mp` among `hits` (from `draw`): what the ingredient is and how far it
## is, or what the result does and how it arrives. Placed left of the icon (the recipe panels sit on the right),
## kept on screen. Returns whether a hint is shown.
static func tooltip(ci: Control, hits: Array, ctx: Dictionary, mp: Vector2, screen: Vector2) -> bool:
	for h: Array in hits:
		var ir: Rect2 = h[0]
		if not ir.has_point(mp):
			continue
		var row: Dictionary = h[1]
		var i := int(h[2])
		var lines := _tip_lines(row, ctx, i)
		var f := HudKit.ui_font()
		var bw := TIP_W - 40.0
		var hgt := 54.0
		for ln: Array in lines:
			hgt += f.get_multiline_string_size(String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, bw, UiStyle.FS_BODY).y + 8.0
		var x := ir.position.x - TIP_W - 14.0
		if x < 16.0:
			x = ir.end.x + 14.0
		var tr := Rect2(x, clampf(ir.position.y - 10.0, 16.0, screen.y - hgt - 16.0), TIP_W, hgt)
		UiStyle.panel(ci, tr, UiStyle.LINE, Color(UiStyle.PANEL, 0.98), 14.0)
		ci.draw_rect(Rect2(tr.position, Vector2(4, tr.size.y)), UiStyle.ACCENT_SOFT)
		UiStyle.text(ci, UiStyle.head_font(700, 1), Vector2(tr.position.x + 20, tr.position.y + 32), _tip_title(row, ctx, i), UiStyle.FS_LABEL,
			UiStyle.ACCENT_SOFT)
		var y := tr.position.y + 58.0
		for ln: Array in lines:
			var t := String(ln[0])
			ci.draw_multiline_string(f, Vector2(tr.position.x + 20, y), t, HORIZONTAL_ALIGNMENT_LEFT, bw, UiStyle.FS_BODY, -1, ln[1])
			y += f.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, bw, UiStyle.FS_BODY).y + 8.0
		return true
	return false


## Title of the hint: the ingredient's full name, or the entry's name with its kind
static func _tip_title(row: Dictionary, ctx: Dictionary, i: int) -> String:
	var id := String(row["id"])
	if i < 0:
		return "%s · %s" % [HudAlbum.entry_title(id), Loc.t(String(HudAlbum.KIND_TITLE[AlbumBook.kind(id)])).to_lower()]
	var t: Dictionary = (row["things"] as Array)[i]
	var name := HudAlbumRun.tr_name(String(t["name"]))
	if String(t.get("fmt", "")) != "":
		name = Loc.t(String(t["fmt"])) % name
	return name.substr(0, 1).to_upper() + name.substr(1)


## Lines of the hint: [text, colour]
static func _tip_lines(row: Dictionary, ctx: Dictionary, i: int) -> Array:
	if i < 0:
		var out := [[HudAlbum.entry_desc(String(row["id"])), UiStyle.TEXT_WARM]]
		if row["done"]:
			out.append(["✓ " + Loc.t("Собрано в этом вылете"), MET])
		elif not row["reach"]:
			out.append([Loc.t("На этом самолёте не собрать: ") + HudAlbumRun.why_text(row), UiStyle.TEXT_OFF])
		else:
			out.append([HudAlbumRun.note(row, ctx), UiStyle.TEXT_2])
		return out
	var t: Dictionary = (row["things"] as Array)[i]
	var ok := int(t["have"]) >= int(t["need"])
	var unit := String(t["unit"])
	var need := (Loc.t("ур. %d") if unit == "ур." else ("×%d" if unit == "×" else ("%d " + Loc.t("оч.") if unit == "оч." else "%d"))) % int(t["need"])
	var st := (Loc.t("Нужно: %s — уже есть") % need) if ok else (Loc.t("Нужно: %s, сейчас %d") % [need, int(t["have"])])
	return [[st, MET if ok else UiStyle.ACCENT_SOFT],
		[Loc.t("Берите карточки с этим значком: каждая продвигает рецепт."), UiStyle.TEXT_2]]


## Level pips under an icon: `need` small bars, `have` of them lit. A count above 5 (archetype points) is written.
static func _pips(ci: Control, c: Vector2, have: int, need: int, unit: String, s: float, ok: bool, hot: bool) -> void:
	var on := MET if ok else (UiStyle.ACCENT if hot else UiStyle.ACCENT_SOFT)
	if need > 6 or unit == "оч.":
		var t := "%d / %d" % [mini(have, need), need]
		_center(ci, HudKit.ui_font(), c + Vector2(0, 12), t, UiStyle.FS_CAPTION, on)
		return
	var w := clampf(s * 0.16, 7.0, 16.0)
	var gap := 3.0
	var x := c.x - (w * need + gap * (need - 1)) / 2.0
	for k in need:
		ci.draw_rect(Rect2(x + k * (w + gap), c.y, w, 4.0), on if k < have else Color(1, 1, 1, 0.14))


## Green tick in a dark circle at `c`
static func _check(ci: Control, c: Vector2, rad: float) -> void:
	ci.draw_circle(c, rad, Color(0.05, 0.12, 0.07, 0.95))
	ci.draw_arc(c, rad, 0.0, TAU, 20, MET, 1.5)
	ci.draw_polyline(PackedVector2Array([c + Vector2(-rad * 0.45, 0), c + Vector2(-rad * 0.1, rad * 0.38), c + Vector2(rad * 0.5, -rad * 0.38)]),
		MET, maxf(2.0, rad * 0.22))


## `s` centred on x at baseline `pos.y`
static func _center(ci: Control, f: Font, pos: Vector2, s: String, fs: int, col: Color) -> void:
	UiStyle.text(ci, f, Vector2(pos.x - UiStyle.text_w(f, s, fs) / 2.0, pos.y), s, fs, col)


## `s` cut with «…» to `w` px
static func _fit(f: Font, s: String, w: float, fs: int) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
		return s
	while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		s = s.substr(0, s.length() - 1)
	return s + "…"
