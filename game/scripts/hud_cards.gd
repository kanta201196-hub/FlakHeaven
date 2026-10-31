class_name HudCards
extends HudKit
## Card pick on a new level (combat UI v2, step 8; Kanta's Sublight reference «описание
## умений»). Four tall cards in a row: rarity name, big icon tile (HudIcons), name in the
## rarity colour, level pips, the card text with highlighted terms and numbers, the family
## tag that starts where the bottom-left bevel ends, and the pick key. The focused card is
## lifted. Under the cards: reroll, change specialization, lock and ban for the focused
## card; next to them the explanation of a term (Terms), whose own terms open the next one.
## Keyboard and gamepad: ←/→ move the focus, Enter picks, 1–4 pick directly, R rerolls,
## lock and ban keys act on the focused card (MainInput).

## Card size: about 3/4 of the first version (S11-17, Kanta: «карточки уменьшить на 25%»)
const CARD_W := 300.0
const CARD_H := 450.0
const GAP := 24.0
const CUT := 22.0
const ICON := 132.0
const TIP_W := 480.0
## Deepest chain of nested term explanations
const TIP_DEPTH := 3

## Focused card (keyboard, gamepad or the last card under the mouse)
static var focus := 0
## Pilot level the focus belongs to: a new level starts on the first card
static var _focus_level := -1
## Mouse position of the last frame: hovering moves focus only when the mouse moves, so a
## cursor resting on a card does not undo arrow and gamepad navigation.
static var _last_mp := Vector2(-1.0, -1.0)
## Open term explanations, outermost first
static var _tip_ids: Array[StringName] = []
## Card whose term opened the first explanation (-1 — the focused card's first term)
static var _tip_card := -1
## Term hit areas of this frame: [Rect2, id, level] (level -1 — on a card, n — in tooltip n)
var _term_rects: Array = []
## Parsed card and term texts by "skip|text" (the screen redraws every frame; texts repeat)
static var _parsed := {}
## Tooltip panels drawn last frame, for keeping a chain open while the mouse moves into it
static var _tip_rects: Array[Rect2] = []
## True after ←/→ until the mouse moves: then the focused card's explanation stays open
## without the mouse over it (S11-22 hides it when the mouse leaves the cards).
static var _kbd := false


## Draws the whole screen over the paused fight.
func draw(m: Main, size: Vector2) -> void:
	_term_rects.clear()
	var p := m.player
	var n := m.offers.size()
	if m.run.level != _focus_level:
		_focus_level = m.run.level
		move_focus(-focus, n)
		_kbd = false
	focus = clampi(focus, 0, maxi(n - 1, 0))
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.SCRIM, 0.82))
	ctrl.draw_rect(Rect2(0, 0, size.x, 8), UiStyle.ACCENT)
	var pair: bool = n > 0 and ((m.offers[0]["kind"] == "branch" and bool(m.offers[0]["first"])) or m.offers[0]["kind"] == "profile")
	_header(m, size, pair)
	var gap := 110.0 if pair and n <= 2 else GAP
	var x0 := (size.x - n * CARD_W - (n - 1) * gap) / 2.0
	var top := 214.0
	var mp := ctrl.get_local_mouse_position()
	var moved := mp != _last_mp
	_last_mp = mp
	if moved:
		_kbd = false
	var over_card := false
	for i in n:
		var r := Rect2(x0 + i * (CARD_W + gap), top - 14.0, CARD_W, CARD_H + 14.0)
		if r.has_point(mp):
			over_card = true
			if moved and focus != i:
				focus = i
				_tip_card = -1
	# cards rise into place while the pick delay runs (MainInput.CARD_INPUT_DELAY)
	var k := clampf(m._state_t / MainInput.CARD_INPUT_DELAY, 0.0, 1.0)
	var rise := 28.0 * (1.0 - k) * (1.0 - k)
	var drawn: Array = []
	for i in n:
		var r := Rect2(x0 + i * (CARD_W + gap), top - (14.0 if i == focus else 0.0) + rise, CARD_W, CARD_H)
		_card(m, p, i, r, i == focus, pair)
		drawn.append(r)
	_fade_in(drawn, m._state_t)
	if pair and n == 2:
		var oc := Vector2(x0 + CARD_W + gap * 0.5, top + CARD_H * 0.5)
		ctrl.draw_circle(oc, 30.0, Color(UiStyle.SCRIM, 1.0))
		ctrl.draw_arc(oc, 30.0, 0.0, TAU, 40, UiStyle.ACCENT, 3.0)
		UiStyle.text(ctrl, UiStyle.head_font(800, 2), Vector2(oc.x - 30.0, oc.y + 7.0), Loc.t("ИЛИ"), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	var by := top + CARD_H + 26.0
	_actions(m, Vector2(x0, by), pair)
	_terms_tips(m, Vector2(x0 + 420.0, by - 4.0), size, over_card or _kbd)
	_hints(size, pair)
	_hull(p)


## S11-23: hull bar in the top-left corner, where it is in flight, so a pick can weigh repair.
## s12: on its own it looked like a leftover of the flight HUD — it sits in the same panel now.
func _hull(p: Player) -> void:
	if not is_instance_valid(p):
		return
	UiStyle.panel(ctrl, Rect2(20, 20, 440, 50), Color(1, 1, 1, 0.12), Color(0.03, 0.035, 0.035, 0.72))
	var r := Rect2(40, 32, 400, 26)
	var hk := clampf(p.hp / p.max_hp, 0.0, 1.0)
	var hc := Color(0.4, 0.85, 0.45) if hk > 0.33 else UiStyle.DANGER
	ctrl.draw_rect(r.grow(3.0), Color(0, 0, 0, 0.6))
	ctrl.draw_rect(Rect2(r.position, Vector2(r.size.x * hk, r.size.y)), hc)
	UiStyle.text(ctrl, UiStyle.head_font(700, 1), Vector2(r.position.x, r.position.y + 19.0), Loc.t("КОРПУС %d / %d") % [int(p.hp), int(p.max_hp)],
		UiStyle.FS_BODY, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _header(m: Main, size: Vector2, pair: bool) -> void:
	var small := Loc.t("НОВЫЙ УРОВЕНЬ")
	var big := Loc.t("УР %d") % m.run.level
	var col := UiStyle.ACCENT_SOFT
	var profile: bool = pair and m.offers[0]["kind"] == "profile"
	if pair:
		small = Loc.t("ПРОФИЛЬ ОРУЖИЯ") if profile else Loc.t("МАСТЕРСТВО ОРУЖИЯ")
		big = Loc.t("ИЛИ-ИЛИ")
	elif Main.aces():   # «Битва асов»: the draft before takeoff, then a card for every ace shot down
		small = Loc.t("БИТВА АСОВ")
		big = Loc.t("ПОДГОТОВКА") if m.run.aces_down == 0 else Loc.t("ЗА АСА")
	elif m.offer_rare:
		small = Loc.t("НАГРАДА %s") % (m.run.rare_reasons[0] if not m.run.rare_reasons.is_empty() else "")
		big = Loc.t("РЕДКИЕ КАРТОЧКИ")
		col = Cards.RARITY[3]["color"]
	# S11-19: the reason for rare cards («НАГРАДА ЗА ПОЗИЦИЮ ПВО») is news, so it is bright
	var scol := UiStyle.TEXT_DIM if not m.offer_rare or pair else UiStyle.TEXT
	UiStyle.text(ctrl, UiStyle.head_font(700, 6), Vector2(0, 64), small, UiStyle.FS_H3 if m.offer_rare and not pair else UiStyle.FS_H3 - 2, scol,
		HORIZONTAL_ALIGNMENT_CENTER, size.x)
	UiStyle.text(ctrl, UiStyle.head_font(800, 8), Vector2(0, 128), big, 64, col, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var sub := ""
	if profile:
		sub = Loc.t("Выберите профиль для этого оружия — остальные закроются до конца вылета.")
		var hint := Cards.profile_hint(m.player, int(m.offers[0]["group"]))
		if hint != "":
			sub += " " + hint
	elif pair:
		sub = Loc.t("Выберите одну ветку для этого оружия — вторая закроется до конца вылета.")
	elif m.levelup_intro:
		sub = Loc.t("Выберите одно улучшение — оно действует до конца вылета. Не знаете, что взять? Берите оружие, которое уже стоит на самолёте.")
	elif m.run.pending_levels > 1:
		sub = Loc.t("Ещё выборов: %d") % (m.run.pending_levels - 1)
	if sub != "":
		UiStyle.text(ctrl, ui_font(), Vector2(0, 176), sub, UiStyle.FS_BODY, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_CENTER, size.x)


# ---------- One card ----------

func _card(m: Main, p: Player, i: int, r: Rect2, on: bool, pair: bool) -> void:
	var c: Dictionary = m.offers[i]
	var kind := String(c["kind"])
	var evo := kind in ["evolution", "mastery"]
	var rc: Color = Cards.EVO_COLOR if evo else Cards.RARITY[int(c["rarity"])]["color"]
	var rname := Loc.t("МОДЕРНИЗАЦИЯ") if kind == "evolution" else Loc.t(String(Cards.RARITY[int(c["rarity"])]["name"])).to_upper()
	if kind == "profile":
		var pi := WeaponProfiles.ids(String(c["weapon"])).find(String(c["profile"]))
		rc = Prog.TAGS[WeaponProfiles.COLORS[clampi(pi, 0, WeaponProfiles.COLORS.size() - 1)]]["color"]
		rname = Loc.t("ПРОФИЛЬ ОРУЖИЯ")
	elif pair:
		rc = Prog.TAGS["maneuver"]["color"] if c["branch"] == "rate" else Prog.TAGS["blast"]["color"]
		rname = Loc.t("ВЕТКА МАСТЕРСТВА")
	var shape := HudIcons.tile_shape(r, CUT)
	if on:
		for k in 4:
			var g := shape.duplicate()
			g.append(g[0])
			_offset_outline(g, r, 3.0 + k * 4.0)
			ctrl.draw_polyline(g, Color(rc, 0.16 - k * 0.035), 4.0)
	# fill: rarity tint at the top fading to graphite by the middle; extra vertices at 48 %
	var mid := r.position.y + r.size.y * 0.48
	var c1 := Color(0.067, 0.067, 0.067).lerp(rc, 0.24)
	var c2 := Color(0.071, 0.075, 0.063)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x - CUT, r.position.y), Vector2(r.end.x, r.position.y + CUT),
		Vector2(r.end.x, mid), r.end, Vector2(r.position.x + CUT, r.end.y), Vector2(r.position.x, r.end.y - CUT), Vector2(r.position.x, mid)])
	var cols := PackedColorArray([c1, c1, c1.lerp(c2, CUT / (mid - r.position.y)), c2, c2, c2, c2, c2])
	ctrl.draw_polygon(pts, cols)
	var outline := shape.duplicate()
	outline.append(shape[0])
	ctrl.draw_polyline(outline, rc, 3.0 if on else 2.0)
	_buttons.append([r, "card:%d" % i])
	var cx := r.position.x
	var w := r.size.x
	UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(cx, r.position.y + 30), rname, UiStyle.FS_CAPTION, rc, HORIZONTAL_ALIGNMENT_CENTER, w)
	if not m.locked.is_empty() and m.locked["id"] == c["id"]:
		UiStyle.text(ctrl, UiStyle.head_font(700, 2), Vector2(cx, r.position.y + 30), "◆ " + Loc.t("ЗАКРЕПЛЕНА"), UiStyle.FS_CAPTION, UiStyle.ACCENT,
			HORIZONTAL_ALIGNMENT_RIGHT, w - CUT - 10.0)
	# big icon
	var ir := Rect2(cx + (w - ICON) / 2.0, r.position.y + 42.0, ICON, ICON)
	HudIcons.tile(ctrl, ir, HudIcons.card_key(p, c), HudIcons.card_family(p, c), Color.TRANSPARENT)
	# name in the rarity colour, centred in a fixed band: two lines at 21 px, or three at 18 px
	# for long names such as «Лазер обороны «Луч» (экспериментальный): улучшение» (S11-26)
	var nf := UiStyle.head_font(700, 1)
	var nfs := 21
	var title := _card_title(p, c)
	var lines := _lines(title, w - 32.0, nfs, nf, 2)
	if lines.size() == 2 and lines[1].ends_with("…"):
		nfs = 18
		lines = _lines(title, w - 28.0, nfs, nf, 3)
	var nlh := nfs + 4.0
	var ny := ir.end.y + 22.0 + (2.0 - lines.size()) * nlh * 0.5 + (4.0 if lines.size() == 3 else 0.0)
	for li in lines.size():
		UiStyle.text(ctrl, nf, Vector2(cx, ny + li * nlh), lines[li], nfs, rc, HORIZONTAL_ALIGNMENT_CENTER, w)
	var y := ir.end.y + 64.0 + (8.0 if lines.size() == 3 else 0.0)
	# level pips and level line
	var lv := _card_level(p, c)
	if lv.y > 0:
		var pw := 12.0
		var px := cx + (w - lv.y * (pw + 4.0) + 4.0) / 2.0
		for k in int(lv.y):
			var pr := Rect2(px + k * (pw + 4.0), y, pw, 6)
			ctrl.draw_rect(pr, UiStyle.ACCENT if k < int(lv.x) else (Color(rc, 0.9) if k == int(lv.x) else Color(1, 1, 1, 0.15)))
	UiStyle.text(ctrl, UiStyle.head_font(600, 2), Vector2(cx, y + 26.0), _fit(_level_line(p, c, lv), w - 24.0, UiStyle.FS_CAPTION, UiStyle.head_font(600, 2)),
		UiStyle.FS_CAPTION, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 40.0
	# text with terms; the "either-or" warning goes to a red box at the bottom
	var desc := Loc.out(Loc.t(String(c["desc"])))
	var warn := ""
	if pair and kind == "branch":
		warn = desc.substr(desc.get_slice("\n", 0).length()).strip_edges()
		desc = desc.get_slice("\n", 0)
	var path := _card_path(p, c)
	var bottom := r.end.y - 32.0 - (22.0 if path != "" else 0.0) - (66.0 if warn != "" else 0.0)
	var segs := _parse(desc)
	var fs := 16
	while fs > UiStyle.FS_MIN and _rich_height(segs, w - 32.0, fs) > bottom - y:
		fs -= 1
	_rich(Vector2(cx + 16.0, y + fs), segs, w - 32.0, fs, UiStyle.TEXT_WARM, int((bottom - y) / (fs * 1.38)), i)
	if warn != "":
		var wr := Rect2(cx + 12.0, r.end.y - 100.0, w - 24.0, 60.0)
		ctrl.draw_rect(wr, Color(UiStyle.DANGER, 0.16))
		ctrl.draw_rect(wr, Color(UiStyle.DANGER, 0.7), false, 1.5)
		_para(Vector2(wr.position.x + 12, wr.position.y + 24), warn, wr.size.x - 24.0, UiStyle.FS_CAPTION, UiStyle.DANGER.lightened(0.35))
	if path != "":
		UiStyle.text(ctrl, ui_font(), Vector2(cx + 16.0, r.end.y - 40.0), _fit(path, w - 32.0, UiStyle.FS_CAPTION), UiStyle.FS_CAPTION, UiStyle.ACCENT_SOFT)
	_tag(p, c, r)
	UiStyle.key_hint(ctrl, Vector2(r.end.x - 48.0, r.end.y - 9.0), str(i + 1), "")


## Grows a closed outline of `r` (last point = first) outward by `d` along every edge (glow rings of the focused
## card). S14-01 (Kanta: «торчит уголок, скос рамки выступает за рамку»): each vertex used to move by (±d, ±d), which
## keeps the sides d away but pushes the 45° bevels √2·d out, so the bevel of the glow stood off the frame. A miter
## offset keeps every edge, bevels included, exactly d away.
func _offset_outline(pts: PackedVector2Array, r: Rect2, d: float) -> void:
	var c := r.get_center()
	var n := pts.size() - 1
	if n < 3:
		return
	var src := pts.duplicate()
	for k in n:
		var a := src[(k - 1 + n) % n]
		var b := src[k]
		var e := src[(k + 1) % n]
		var n1 := _out_normal(a, b, c)
		var n2 := _out_normal(b, e, c)
		pts[k] = b + (n1 + n2) * d / maxf(1.0 + n1.dot(n2), 0.2)
	pts[n] = pts[0]


## Unit normal of edge `a`–`b` pointing away from `c` (the card's centre)
func _out_normal(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var nrm := (b - a).orthogonal().normalized()
	return -nrm if nrm.dot((a + b) * 0.5 - c) < 0.0 else nrm


## Family tag at the bottom: its left edge follows the bevel, then the card's left border, so nothing leaves the card.
func _tag(p: Player, c: Dictionary, r: Rect2) -> void:
	var fam := HudIcons.card_family(p, c)
	var tags := Prog.card_tags(p, c)
	var label := Loc.t(Prog.tag_title(String(tags[0]))) if not tags.is_empty() else Loc.t(String(c.get("cat", "")))
	label = label.to_upper()
	var fc := HudIcons.family_color(fam)
	var f := UiStyle.head_font(700, 2)
	var tw := UiStyle.text_w(f, label, UiStyle.FS_CAPTION) + 24.0
	var h := 28.0
	var x := r.position.x + 2.0
	var y := r.end.y - 2.0
	# S14-01 (Kanta: a corner sticks out of the card): the tag is taller (28) than the bevel (22), so a slanted edge
	# running the full height started 4 px left of the card's border; it now follows the bevel, then goes straight up
	var poly := PackedVector2Array([Vector2(x, y - h), Vector2(x + CUT + tw, y - h), Vector2(x + CUT + tw, y), Vector2(x + CUT, y),
		Vector2(x, y - CUT)])
	ctrl.draw_colored_polygon(poly, Color(fc, 0.22))
	UiStyle.text(ctrl, f, Vector2(x + CUT + 6.0, y - 8.0), label, UiStyle.FS_CAPTION, fc.lightened(0.25))


## «УР. 2 → 3», «НОВОЕ ОРУЖИЕ», «МОДУЛЬ 3 ИЗ 6», «МАКСИМУМ» — whatever applies to the card.
## Name shown on the card. A mastery branch shows its own name («Скорострел» / «Калибр»):
## the stored title starts with the weapon name, which is the same on both cards of the
## «или-или» pair and pushed the branch name past the ellipsis (S11-33). The weapon goes to
## the level line instead. S14-09: when two weapons' branches of the same name are on one screen
## (two «Калибр» cards), each name gets its weapon, so the player can tell them apart.
func _card_title(p: Player, c: Dictionary) -> String:
	if String(c["kind"]) == "profile":   # PG-06: the profile's own name; the weapon goes to the level line
		return Loc.t(String(WeaponProfiles.def(String(c["weapon"]), String(c["profile"]))["title"]))
	if String(c["kind"]) == "branch":
		var name := _branch_name(p, c)
		for o: Dictionary in Main.I.offers:
			if String(o["kind"]) == "branch" and int(o["group"]) != int(c["group"]) and _branch_name(p, o) == name:
				return "%s: %s" % [name, _weapon_name(p.groups[int(c["group"])])]
		return name
	return Loc.title(c["title"])


## Translated name of the mastery branch on card `c` («Скорострел», «Калибр», «Яркие ловушки»…).
func _branch_name(p: Player, c: Dictionary) -> String:
	var g: Hardpoint = p.groups[int(c["group"])]
	return Loc.t(String(Cards.branch_def(g.weapon, String(c["branch"]))["title"]))


## Short translated name of the weapon in group `g` (its evolution name once evolved).
func _weapon_name(g: Hardpoint) -> String:
	return Loc.t(g.evo_title()) if g.evo else Loc.t(String(Weapons.DEFS[g.weapon]["short"]))


## Small line under the name: level or rank with «максимум», the module slot it takes, or the
## card category; for a mastery branch it starts with the weapon the branch is for.
func _level_line(p: Player, c: Dictionary, lv: Vector2) -> String:
	var parts := PackedStringArray()
	var kind := String(c["kind"])
	if kind == "branch":
		var g: Hardpoint = p.groups[int(c["group"])]
		parts.append(_weapon_name(g).to_upper())
		parts.append(Loc.t("РАНГ %d → %d") % [lv.x, mini(int(lv.x) + 1, int(lv.y))])
		if int(lv.x) + 1 >= int(lv.y):
			parts.append(Loc.t("МАКСИМУМ"))
	elif kind == "profile":   # the weapon only: the pips above show the level, long names («Наводящиеся ракеты») must fit
		parts.append(_weapon_name(p.groups[int(c["group"])]).to_upper())
	elif kind == "weapon_new":
		parts.append(Loc.t("НОВОЕ ОРУЖИЕ"))
	elif lv.y > 0:
		parts.append(Loc.t("УР. %d → %d") % [lv.x, mini(int(lv.x) + 1, int(lv.y))])
		if int(lv.x) + 1 >= int(lv.y):
			parts.append(Loc.t("МАКСИМУМ"))
	if kind == "module" and Cards.MODULES.has(c["id"]) and not Cards.SLOT_FREE.has(c["id"]) and int(p.taken.get(c["id"], 0)) == 0:
		parts.append(Loc.t("МОДУЛЬ %d ИЗ %d") % [Cards.mod_slots_used(p) + 1, Cards.MOD_SLOTS])
	if parts.is_empty():
		parts.append(Loc.t(String(c.get("cat", ""))).to_upper())
	return " · ".join(parts)


## Level of the card: x — now, y — max (0 — no levels).
func _card_level(p: Player, c: Dictionary) -> Vector2:
	match String(c["kind"]):
		"weapon_up", "profile":
			return Vector2((p.groups[int(c["group"])] as Hardpoint).level, Weapons.MAX_LEVEL)
		"weapon_new":
			return Vector2(0, Weapons.MAX_LEVEL)
		"module":
			var id := String(c["id"])
			if id == "repair" or not Cards.MODULES.has(id):
				return Vector2.ZERO
			return Vector2(int(p.taken.get(id, 0)), int(Cards.MODULES[id]["max"]))
		"branch":
			return Vector2((p.groups[int(c["group"])] as Hardpoint).branch_rank, Cards.BRANCH_MAX)
	return Vector2.ZERO


## EX-02: where the card leads — «▲ к «Шмель»: перезарядка 1 → 2 из 2».
func _card_path(p: Player, c: Dictionary) -> String:
	match String(c["kind"]):
		"module":
			var id := String(c["id"])
			for w in Prog.EVOS:
				var cat: Dictionary = Prog.EVOS[w]["cat"]
				if not cat.has(id) or not (w == "gun" or _has_weapon(p, w)) or (w == "gun" and p.gun_evo):
					continue
				var have := int(p.taken.get(id, 0))
				if have < int(cat[id]):
					return Loc.t("▲ к %s: %d → %d из %d") % [Loc.t(Prog.EVOS[w]["title"]), have, have + 1, int(cat[id])]
		"weapon_up":
			var g: Hardpoint = p.groups[int(c["group"])]
			if Prog.EVOS.has(g.weapon) and not g.evo:
				return Loc.t("▲ ур. 5 откроет %s") % Loc.t(Prog.EVOS[g.weapon]["title"])
	return ""


func _has_weapon(p: Player, w: String) -> bool:
	for g in p.groups:
		if (g as Hardpoint).weapon == w and not (g as Hardpoint).evo:
			return true
	return false


# ---------- Rich text with terms ----------

## `Terms.parse` with a cache, so redraws do not re-scan the same texts.
func _parse(text: String, skip: StringName = &"") -> Array:
	var k := "%s|%s|%s" % [TranslationServer.get_locale(), skip, text]
	if not _parsed.has(k):
		if _parsed.size() > 200:
			_parsed.clear()
		_parsed[k] = Terms.parse(text, "", skip)
	return _parsed[k]

## Splits segments into drawable pieces: words with their trailing spaces, CJK characters
## one by one (Chinese has no spaces to break at). Each piece keeps the segment's kind and id.
func _pieces(segs: Array) -> Array:
	var out: Array = []
	for s: Dictionary in segs:
		var t := String(s["text"])
		var cur := ""
		for k in t.length():
			var ch := t[k]
			if ch == "\n":
				if cur != "":
					out.append([cur, s["kind"], s["id"]])
					cur = ""
				out.append(["\n", Terms.TEXT, &""])
				continue
			var cjk := ch.unicode_at(0) >= 0x2E80
			if cjk and cur != "" and not cur.ends_with(" "):
				out.append([cur, s["kind"], s["id"]])
				cur = ""
			cur += ch
			if ch == " " or cjk:
				if k + 1 < t.length() and t[k + 1] == " ":
					continue
				out.append([cur, s["kind"], s["id"]])
				cur = ""
		if cur != "":
			out.append([cur, s["kind"], s["id"]])
	return out


func _font_of(kind: StringName) -> Font:
	return Menu.bold() if kind == Terms.TERM or kind == Terms.NUM else ui_font()


## Height of segments wrapped to `width` at `fs`.
func _rich_height(segs: Array, width: float, fs: int) -> float:
	var x := 0.0
	var lines := 1
	for wd: Array in _words(_pieces(segs)):
		if wd[0][0] == "\n":
			lines += 1
			x = 0.0
			continue
		var wx := _word_w(wd, fs)
		if x > 0.0 and x + wx.y > width:
			lines += 1
			x = 0.0
		x += wx.x
	return lines * fs * 1.38


## Pieces glued into words that may not be split by a line break (S11-21): a break is only
## allowed after a space or a CJK character, so «(из 11)» never leaves «)» alone on the
## next line even though «11» is a number piece and «)» a text piece.
func _words(pieces: Array) -> Array:
	var out: Array = []
	var cur: Array = []
	for pc: Array in pieces:
		if pc[0] == "\n":
			if not cur.is_empty():
				out.append(cur)
				cur = []
			out.append([pc])
			continue
		cur.append(pc)
		var s := String(pc[0])
		if s.ends_with(" ") or s.unicode_at(s.length() - 1) >= 0x2E80:
			out.append(cur)
			cur = []
	if not cur.is_empty():
		out.append(cur)
	return out


## Width of a word: x — with its trailing space, y — without it (what must fit on the line).
func _word_w(wd: Array, fs: int) -> Vector2:
	var w := 0.0
	for k in wd.size():
		w += _font_of(wd[k][1]).get_string_size(String(wd[k][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var last: Array = wd[wd.size() - 1]
	var f := _font_of(last[1])
	var tail := f.get_string_size(String(last[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - f.get_string_size(String(last[0]).strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return Vector2(w, w - tail)


## Draws segments from `pos` (first baseline), wrapping at `width` between words (`_words`),
## at most `max_lines` (the last visible line ends with «…» when cut). Terms are bold amber
## with a dotted underline and register hit areas for tooltips (`level` -1 = on card
## `card`, else the tooltip level); numbers are bold green.
func _rich(pos: Vector2, segs: Array, width: float, fs: int, color: Color, max_lines := 99, card := -1, level := -1) -> float:
	var x := 0.0
	var line := 0
	var lh := fs * 1.38
	var words := _words(_pieces(segs))
	for wi in words.size():
		var wd: Array = words[wi]
		if wd[0][0] == "\n":
			line += 1
			x = 0.0
			continue
		var wx := _word_w(wd, fs)
		if x > 0.0 and x + wx.y > width:
			line += 1
			x = 0.0
		if line >= max_lines:
			break
		var cut := line == max_lines - 1 and wi + 1 < words.size() and x + wx.x + 40.0 > width
		for k in wd.size():
			var pc: Array = wd[k]
			var f := _font_of(pc[1])
			var s := String(pc[0])
			if cut and k == wd.size() - 1:
				s = s.strip_edges(false, true) + "…"
			var pw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var core := f.get_string_size(s.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(pos.x + x, pos.y + line * lh)
			var col := color
			if pc[1] == Terms.TERM:
				col = UiStyle.ACCENT_SOFT
				ctrl.draw_dashed_line(at + Vector2(0, 4), at + Vector2(core, 4), Color(UiStyle.ACCENT_SOFT, 0.8), 1.0, 3.0)
				_term_rects.append([Rect2(at.x - 2.0, at.y - fs, core + 4.0, lh), StringName(pc[2]), level, card])
			elif pc[1] == Terms.NUM:
				col = UiStyle.OK
			ctrl.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += pw
		if cut:
			break
	return (line + 1) * lh


# ---------- Actions under the cards ----------

func _actions(m: Main, pos: Vector2, pair: bool) -> void:
	var f := UiStyle.head_font(700, 3)
	var y := pos.y
	if m.rerolls > 0:
		_action_button(Rect2(pos.x, y, 360, 48), key_label("reroll"), Loc.t("ПЕРЕБРОСИТЬ · %d") % m.rerolls, "reroll", true)
		y += 58.0
		if m.player.has_course() and not pair:
			_action_button(Rect2(pos.x, y, 360, 40), "", Loc.t("СМЕНИТЬ СПЕЦИАЛИЗАЦИЮ · −1"), "change_course", false)
			y += 52.0
	else:
		UiStyle.text(ctrl, f, Vector2(pos.x, y + 28), Loc.t("ПЕРЕБРОСОВ НЕТ · +1 ЗА АСА"), UiStyle.FS_BODY, UiStyle.TEXT_OFF)
		y += 52.0
	if pair:
		return
	var x := pos.x
	var locked: bool = not m.locked.is_empty() and focus < m.offers.size() and m.locked["id"] == m.offers[focus]["id"]
	x = _key_button(Vector2(x, y + 22), key_label("card_lock"), Loc.t("ОТКРЕПИТЬ") if locked else Loc.t("ЗАКРЕПИТЬ"), "lock:%d" % focus, true)
	_key_button(Vector2(x, y + 22), key_label("card_ban"), Loc.t("ИСКЛЮЧИТЬ · %d") % m.bans, "ban:%d" % focus, m.bans > 0)
	if not m.banned.is_empty():
		var names := PackedStringArray(m.banned.values().map(func(v) -> String: return Loc.title(String(v))))
		UiStyle.text(ctrl, ui_font(), Vector2(pos.x, y + 56), _fit(Loc.t("Исключены: ") + ", ".join(names), 400.0, UiStyle.FS_CAPTION),
			UiStyle.FS_CAPTION, UiStyle.TEXT_OFF)


## Panel button with an optional key cap; amber when it is the main action.
func _action_button(r: Rect2, key: String, label: String, action: String, main: bool) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	UiStyle.panel(ctrl, r, UiStyle.ACCENT if (hover or main) else UiStyle.LINE, Color(UiStyle.ACCENT, 0.14) if hover else UiStyle.PANEL, 12.0)
	var x := r.position.x + 18.0
	var base := r.position.y + r.size.y / 2.0 + 7.0
	if key != "":
		x = UiStyle.key_hint(ctrl, Vector2(x, base), key, "") - 34.0 + 4.0
	UiStyle.text(ctrl, UiStyle.head_font(700, 3), Vector2(x, base), label, UiStyle.FS_LABEL if main else UiStyle.FS_BODY, UiStyle.TEXT if main or hover else UiStyle.TEXT_2)
	_buttons.append([r, action])


## Key cap + caption that is also clickable; returns the x after it.
func _key_button(pos: Vector2, key: String, label: String, action: String, enabled: bool) -> float:
	var end := UiStyle.key_hint(ctrl, pos, key, label)
	var r := Rect2(pos.x - 4.0, pos.y - 26.0, end - pos.x - 26.0, 34.0)
	if enabled:
		if r.has_point(ctrl.get_local_mouse_position()):
			ctrl.draw_rect(r, Color(UiStyle.ACCENT, 0.12))
		_buttons.append([r, action])
	else:
		ctrl.draw_rect(r, Color(UiStyle.SCRIM, 0.5))
	return end


# ---------- Term explanations ----------

## Explanation panels: the hovered term (or the focused card's first term), then terms
## hovered inside each panel open the next panel to the right. The chain stays open while
## the mouse is over a panel, so nested terms can be reached. `show` — the mouse is over a
## card or the last move was a key: otherwise the chain closes (S11-22).
func _terms_tips(m: Main, pos: Vector2, size: Vector2, show: bool) -> void:
	var mp := ctrl.get_local_mouse_position()
	var in_tip0 := false
	for r in _tip_rects:
		if r.grow(8.0).has_point(mp):
			in_tip0 = true
	if not show and not in_tip0:
		# S11-22: the mouse left the cards and the explanations: nothing stays on screen
		_tip_ids.clear()
		_tip_rects.clear()
		return
	# a term under the mouse on a card starts a new chain
	for t: Array in _term_rects:
		if (t[0] as Rect2).has_point(mp) and int(t[2]) == -1:
			_tip_ids.clear()
			_tip_ids.append(t[1])
			_tip_card = int(t[3])
	var in_tip := false
	for r in _tip_rects:
		if r.grow(8.0).has_point(mp):
			in_tip = true
	if _tip_ids.is_empty() or (_tip_card != focus and not in_tip):
		_tip_ids.clear()
		_tip_card = focus
		for t: Array in _term_rects:
			if int(t[3]) == focus and int(t[2]) == -1:
				_tip_ids.append(t[1])
				break
	_tip_rects.clear()
	var x := pos.x
	for lvl in _tip_ids.size():
		var id: StringName = _tip_ids[lvl]
		var segs := _parse(Terms.desc(id), id)
		var body_h := _rich_height(segs, TIP_W - 40.0, UiStyle.FS_BODY)
		var r := Rect2(minf(x, size.x - TIP_W - 24.0), pos.y, TIP_W, 62.0 + body_h)
		UiStyle.panel(ctrl, r, UiStyle.LINE, Color(UiStyle.PANEL, 0.97), 14.0)
		ctrl.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), UiStyle.ACCENT_SOFT)
		UiStyle.text(ctrl, UiStyle.head_font(700, 1), Vector2(r.position.x + 20, r.position.y + 32), Terms.title(id), UiStyle.FS_H3 - 2, UiStyle.ACCENT_SOFT)
		var before := _term_rects.size()
		_rich(Vector2(r.position.x + 20, r.position.y + 60), segs, TIP_W - 40.0, UiStyle.FS_BODY, UiStyle.TEXT_WARM, 99, -1, lvl)
		_tip_rects.append(r)
		# hovering a term in this panel opens (or replaces) the next level
		for k in range(before, _term_rects.size()):
			var t: Array = _term_rects[k]
			if (t[0] as Rect2).has_point(mp) and lvl + 1 < TIP_DEPTH:
				_tip_ids.resize(lvl + 1)
				_tip_ids.append(t[1])
		x = r.end.x + 16.0


## Key hints strip at the bottom centre.
func _hints(size: Vector2, pair: bool) -> void:
	var pairs := [["1–%d" % mini(4, Main.I.offers.size()), Loc.t("взять")], ["← →", Loc.t("карточка")]]
	if not pair:
		pairs.append([key_label("reroll"), Loc.t("перебросить")])
	var w := 0.0
	for pr: Array in pairs:
		w += UiStyle.text_w(UiStyle.head_font(700, 1), String(pr[0]), UiStyle.FS_CAPTION) + 18.0 + 10.0 \
			+ UiStyle.text_w(UiStyle.head_font(600, 3), String(pr[1]).to_upper(), UiStyle.FS_BODY) + 34.0
	var r := Rect2(size.x / 2.0 - w / 2.0 - 20.0, size.y - 66.0, w + 6.0, 46.0)
	ctrl.draw_rect(r, Color(UiStyle.SCRIM, 0.95))
	ctrl.draw_rect(r, UiStyle.LINE, false, 1.0)
	var x := r.position.x + 20.0
	for pr: Array in pairs:
		x = UiStyle.key_hint(ctrl, Vector2(x, r.position.y + 31.0), String(pr[0]), String(pr[1]).to_upper())


## ←/→ on the card pick: moves the focus and resets the explanation to that card.
static func move_focus(dir: int, n: int) -> void:
	if n <= 0:
		return
	focus = wrapi(focus + dir, 0, n)
	_tip_card = -1
	_tip_ids.clear()
	_kbd = true
