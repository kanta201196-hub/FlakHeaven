class_name HudPause
extends HudKit
## Pause screen, variant В «Чертёж самолёта» (combat UI v2, chosen by Kanta 2026-10-24).
## Left: hardpoints with icon, level pips, last-minute DPS and a `‹ target mode ›` selector,
## the pause menu under them. Centre: a blueprint of the plane with numbered hardpoints;
## every module taken sits on a leader line to the part of the airframe it affects, wingmen
## fly in formation beside it. Right: stats table and damage of the last minute.
## Keyboard and gamepad: ↑/↓ move between hardpoint rows and menu items, ←/→ change the
## target, Enter/A activates (MainInput calls `move_focus`, `side`, `accept`).

## Plane outline, nose up, in a 100×100 box (mockup symbol #pl)
const PLANE := [[50, 6], [54, 22], [54, 36], [90, 54], [90, 60], [54, 53], [53, 72], [65, 81], [65, 86], [50, 82],
	[35, 86], [35, 81], [47, 72], [46, 53], [10, 60], [10, 54], [46, 36], [46, 22]]
## Where each module acts on the airframe (100×100 box): engine at the nozzle, armour on the
## fuselage, flaps on the wing, gun upgrades at the nose, missile and pylon parts under the
## wings, radio by the cockpit. UI only.
const MODULE_AT := {
	"engine": Vector2(50, 84), "afterburner": Vector2(46, 80), "armor": Vector2(50, 44), "wing": Vector2(80, 57),
	"gun_dmg": Vector2(50, 10), "gun_rate": Vector2(52, 16), "reload": Vector2(30, 55), "launcher": Vector2(26, 56),
	"seeker": Vector2(70, 54), "frag": Vector2(64, 52), "servo": Vector2(50, 30), "warhead": Vector2(36, 53),
	"msl_head": Vector2(74, 55), "msl_motor": Vector2(20, 57), "radio": Vector2(50, 25), "magnet": Vector2(50, 64),
	"roll": Vector2(12, 57), "skill3": Vector2(50, 36), "repair": Vector2(50, 48),
}
## Hardpoint group label → marker position(s) on the airframe (UI only; labels come from
## PlaneClasses data). Unknown groups are spread along the fuselage.
const GROUP_AT := {
	"Крылья (пара)": [Vector2(30, 55), Vector2(70, 55)], "Под фюзеляжем": [Vector2(50, 50)],
	"Внутренняя пара": [Vector2(37, 52), Vector2(63, 52)], "Внешняя пара": [Vector2(22, 56), Vector2(78, 56)],
	"Бомбоотсек": [Vector2(50, 58)], "Тяжёлый подвес": [Vector2(50, 67)], "Турели": [Vector2(50, 31)],
}
## Weapon id → damage source label in `Main.stats["dealt"]` (the DPS of a hardpoint row)
const WEAPON_SRC := {"aam": &"ракеты В-В", "rockets": &"НАР", "bombs": &"бомбы", "gunpod": &"гондола",
	"turret": &"турели", "emp": &"ЭМИ", "laser": &"лазер", "railgun": &"рельсотрон", "plasma": &"плазма"}
const MOD_TILE := 64.0

## Focused item: "row:<i>" (hardpoint group), "wing" (wingmen target) or a menu action
static var focus := ""
## This frame's focusable items, in order: [Rect2, id]
static var _focusables: Array = []
## Selector actions of this frame's rows, by focus id: [back, forward]
static var _sides := {}


## Draws the whole pause screen over the frozen fight.
func draw(m: Main, size: Vector2) -> void:
	_focusables.clear()
	_sides.clear()
	var p := m.player
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.SCRIM, 0.9))
	var t := int(m.run_time)
	var hf := UiStyle.head_font(600, 5)
	_diamond_outline(Vector2(76, 50), 8.0, UiStyle.TEXT)
	var crumb := Loc.t("ПАУЗА  //  ВЫЛЕТ «%s»  //  %02d:%02d") % [Loc.t(Campaign.op()["title"]).to_upper(), t / 60, t % 60]
	UiStyle.text(ctrl, hf, Vector2(98, 58), crumb, 20, UiStyle.TEXT)
	var left := Rect2(40, 110, 560, 0)
	var bottom := _hardpoints(m, p, left)
	_menu(m, Vector2(56, maxf(bottom + 36.0, size.y - 340.0)))
	_blueprint(m, p, Rect2((600.0 + size.x - 480.0) / 2.0 - 250.0, 200.0, 500.0, 500.0))
	var sy := _stats(p, Rect2(size.x - 480.0, 110.0, 440.0, 0.0))
	sy = _tags(p, Rect2(size.x - 480.0, sy + 16.0, 440.0, 0.0))
	_damage(m, Rect2(size.x - 480.0, sy + 16.0, 440.0, 0.0))
	_hints(size)


func _diamond_outline(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(0, -s)])
	ctrl.draw_polyline(pts, col, 2.0)


# ---------- Hardpoints ----------

## Hardpoint rows and the wingmen target row; returns the bottom y of the panel.
func _hardpoints(m: Main, p: Player, r: Rect2) -> float:
	var rows := p.groups.size() + (1 if not p.wingmen.is_empty() else 0)
	var rh := clampf((m.get_viewport().get_visible_rect().size.y - 520.0) / maxf(rows, 1), 74.0, 96.0)
	r.size.y = 64.0 + rows * rh
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	var tf := UiStyle.head_font(700, 4)
	UiStyle.text(ctrl, tf, Vector2(r.position.x + 24, r.position.y + 38), Loc.t("ПОДВЕСЫ · ВЫБОР ЦЕЛИ"), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT)
	UiStyle.text(ctrl, UiStyle.head_font(600, 2), Vector2(r.position.x, r.position.y + 36), Loc.t("‹ › — сменить цель").to_upper(),
		UiStyle.FS_CAPTION, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24.0)
	var y := r.position.y + 56.0
	var mp := ctrl.get_local_mouse_position()
	for gi in p.groups.size():
		var row := Rect2(r.position.x + 12.0, y, r.size.x - 24.0, rh - 6.0)
		_group_row(m, p, gi, row, mp)
		y += rh
		if gi < p.groups.size() - 1 or not p.wingmen.is_empty():
			ctrl.draw_line(Vector2(r.position.x + 24, y - 4), Vector2(r.end.x - 24, y - 4), UiStyle.LINE, 1.0)
	if not p.wingmen.is_empty():
		var wr := Rect2(r.position.x + 12.0, y, r.size.x - 24.0, rh - 6.0)
		var on := focus == "wing"
		if on:
			UiStyle.brackets(ctrl, wr, UiStyle.ACCENT)
		_focusables.append([wr, "wing"])
		HudIcons.tile(ctrl, Rect2(wr.position.x + 14, wr.position.y + (wr.size.y - 56.0) / 2.0, 56, 56), "wingman", "wing", Color(1, 1, 1, 0.3))
		UiStyle.text(ctrl, UiStyle.head_font(700, 1), Vector2(wr.position.x + 86, wr.position.y + 32), Loc.t("Звено — кого атакует первым"), UiStyle.FS_LABEL, UiStyle.TEXT)
		_selector(Rect2(wr.position.x + 86, wr.position.y + 42, 250, 30), Loc.t(Settings.WING_PRIO[Settings.wing_prio]), "wprioback", "wprio", on, "wing")
	return r.end.y


func _group_row(m: Main, p: Player, gi: int, row: Rect2, mp: Vector2) -> void:
	var g: Hardpoint = p.groups[gi]
	var on := focus == "row:%d" % gi
	var tile := Rect2(row.position.x + 14, row.position.y + (row.size.y - 64.0) / 2.0, 64, 64)
	_num_badge(Vector2(tile.position.x - 4, tile.position.y - 2), gi + 1)
	var sf := UiStyle.head_font(600, 3)
	var nf := UiStyle.head_font(700, 1)
	var tx := tile.end.x + 18.0
	if g.is_empty():
		var dash := Color(1, 1, 1, 0.3)
		ctrl.draw_rect(tile, dash, false, 1.5)
		ctrl.draw_rect(Rect2(tile.get_center() - Vector2(10, 1.5), Vector2(20, 3)), dash)
		ctrl.draw_rect(Rect2(tile.get_center() - Vector2(1.5, 10), Vector2(3, 20)), dash)
		UiStyle.text(ctrl, sf, Vector2(tx, row.position.y + 28), Loc.t(g.name).to_upper(), UiStyle.FS_CAPTION, UiStyle.TEXT_OFF)
		UiStyle.text(ctrl, nf, Vector2(tx, row.position.y + 52), Loc.t("Свободно — ждёт карточку оружия"), UiStyle.FS_LABEL, UiStyle.TEXT_OFF)
		return
	if on:
		UiStyle.brackets(ctrl, row, UiStyle.ACCENT)
	_focusables.append([row, "row:%d" % gi])
	var fam := HudIcons.weapon_family(g.weapon)
	var fc := HudIcons.family_color(fam)
	var frame: Color = Cards.EVO_COLOR if g.evo else Cards.RARITY[clampi(g.level - 1, 0, 4)]["color"]
	HudIcons.tile(ctrl, tile, g.weapon, fam, frame, -1)
	UiStyle.text(ctrl, sf, Vector2(tx, row.position.y + 20), "%s ×%d" % [Loc.t(g.name).to_upper(), g.slots], UiStyle.FS_CAPTION, UiStyle.TEXT_2)
	var title := Loc.t(g.evo_title()) if g.evo else Loc.t(Weapons.title(g.weapon))
	UiStyle.text(ctrl, nf, Vector2(tx, row.position.y + 44), _fit(title, row.end.x - tx - 130.0, UiStyle.FS_LABEL, nf), UiStyle.FS_LABEL, UiStyle.TEXT)
	# level pips and DPS on the right
	var px := row.end.x - 116.0
	for i in Weapons.MAX_LEVEL:
		ctrl.draw_rect(Rect2(px + i * 20.0, row.position.y + 14, 16, 5), (Cards.EVO_COLOR if g.evo else UiStyle.ACCENT) if i < g.level else Color(1, 1, 1, 0.15))
	var src: StringName = WEAPON_SRC.get(g.weapon, &"")
	var rate := m.dps.rate(src, m.run_time) if src != &"" else 0.0
	var best := maxf(_best_rate(m), 1.0)
	var df := UiStyle.head_font(800, 1)
	UiStyle.text(ctrl, df, Vector2(px, row.position.y + 48), Loc.t("%d/с") % int(round(rate)), UiStyle.FS_H3, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, 116.0)
	ctrl.draw_rect(Rect2(px, row.position.y + 56, 116.0, 3), Color(1, 1, 1, 0.1))
	ctrl.draw_rect(Rect2(px, row.position.y + 56, 116.0 * clampf(rate / best, 0.0, 1.0), 3), fc)
	var sel := Rect2(tx, row.position.y + 54, 250, 30)
	if Weapons.DEFS[g.weapon]["uses_priority"]:
		_selector(sel, Loc.t(Weapons.PRIORITY_NAMES[g.priority]), "prioback:%d" % gi, "prio:%d" % gi, on, "row:%d" % gi)
	elif g.uses_trigger():
		var tl := Loc.t("пуск: авто") if g.trigger == "auto" else Loc.t("пуск: %s") % key_label("fire_hardpoint")
		_selector(sel, tl, "trig:%d" % gi, "trig:%d" % gi, on, "row:%d" % gi)


func _best_rate(m: Main) -> float:
	var top := m.dps.top(1, m.run_time)
	return float(top[0][1]) if not top.is_empty() else 0.0


## Amber number in a ring at the top-left corner of a hardpoint tile.
func _num_badge(c: Vector2, n: int) -> void:
	ctrl.draw_circle(c, 13.0, Color(0.05, 0.055, 0.05))
	ctrl.draw_arc(c, 13.0, 0.0, TAU, 24, UiStyle.ACCENT, 2.0)
	UiStyle.text(ctrl, UiStyle.head_font(800, 0), Vector2(c.x - 13, c.y + 5.5), str(n), UiStyle.FS_CAPTION, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 26.0)


## `‹ value ›` selector: left third steps back, the rest steps forward (separate buttons,
## the narrower one registered last so it wins the click). `focus_id` — the row it belongs
## to, so ←/→ on a focused row send the same actions.
func _selector(r: Rect2, value: String, back: String, fwd: String, on: bool, focus_id: String) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	ctrl.draw_rect(r, Color(1, 1, 1, 0.1 if (hover or on) else 0.06))
	var f := UiStyle.head_font(700, 1)
	var ac := UiStyle.ACCENT
	UiStyle.text(ctrl, f, Vector2(r.position.x + 10, r.end.y - 9), "‹", UiStyle.FS_LABEL, ac)
	UiStyle.text(ctrl, f, Vector2(r.position.x, r.end.y - 9), "›", UiStyle.FS_LABEL, ac, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10.0)
	UiStyle.text(ctrl, f, Vector2(r.position.x, r.end.y - 9), _fit(value, r.size.x - 50.0, UiStyle.FS_BODY, f), UiStyle.FS_BODY, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_buttons.append([r, fwd])
	_buttons.append([Rect2(r.position, Vector2(r.size.x / 3.0, r.size.y)), back])
	_sides[focus_id] = [back, fwd]


# ---------- Menu ----------

const MENU := [["resume", "Продолжить"], ["pause_settings", "Настройки"], ["codex", "Справочник"], ["to_menu", "Покинуть вылет"]]


func _menu(_m: Main, pos: Vector2) -> void:
	var mp := ctrl.get_local_mouse_position()
	for i in MENU.size():
		var r := Rect2(pos.x, pos.y + i * 64.0, 400.0, 58.0)
		var id: String = MENU[i][0]
		var on := focus == id or r.has_point(mp)
		var danger := id == "to_menu"
		if danger and not on:
			UiStyle.menu_item(ctrl, r, Loc.t(MENU[i][1]).to_upper(), 0.0, true, "", false, false, UiStyle.FS_H3 + 4)
			# danger item reads red when idle (mockup «ПОКИНУТЬ ВЫЛЕТ»)
			UiStyle.text(ctrl, UiStyle.head_font(700), Vector2(r.position.x + 34.0, r.position.y + r.size.y * 0.5 + 9.4),
				Loc.t(MENU[i][1]).to_upper(), UiStyle.FS_H3 + 4, UiStyle.DANGER.lightened(0.2))
		else:
			UiStyle.menu_item(ctrl, r, Loc.t(MENU[i][1]).to_upper(), 1.0 if on else 0.0, true, "", false, false, UiStyle.FS_H3 + 4)
		_buttons.append([r, id])
		_focusables.append([r, id])


# ---------- Blueprint ----------

func _blueprint(m: Main, p: Player, box: Rect2) -> void:
	# grid
	var gc := Color(UiStyle.ACCENT, 0.1)
	for i in 11:
		var k := i / 10.0
		ctrl.draw_line(Vector2(box.position.x + box.size.x * k, box.position.y), Vector2(box.position.x + box.size.x * k, box.end.y), gc, 1.0)
		ctrl.draw_line(Vector2(box.position.x, box.position.y + box.size.y * k), Vector2(box.end.x, box.position.y + box.size.y * k), gc, 1.0)
	ctrl.draw_rect(box, Color(UiStyle.ACCENT, 0.25), false, 1.0)
	var pts := PackedVector2Array()
	for xy: Array in PLANE:
		pts.append(_at(box, Vector2(float(xy[0]), float(xy[1]))))
	ctrl.draw_colored_polygon(pts, Color(UiStyle.ACCENT, 0.07))
	var outline := pts.duplicate()
	outline.append(pts[0])
	ctrl.draw_polyline(outline, UiStyle.ACCENT, 3.0, true)
	ctrl.draw_dashed_line(_at(box, Vector2(50, 4)), _at(box, Vector2(50, 92)), Color(UiStyle.ACCENT, 0.45), 1.5, 8.0)
	ctrl.draw_dashed_line(_at(box, Vector2(8, 57)), _at(box, Vector2(92, 57)), Color(UiStyle.ACCENT, 0.3), 1.5, 8.0)
	# hardpoint markers
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		for at: Vector2 in _group_points(g.name, gi, p.groups.size()):
			var c := _at(box, at)
			ctrl.draw_circle(c, 15.0, Color(0.05, 0.055, 0.05, 0.95))
			ctrl.draw_arc(c, 15.0, 0.0, TAU, 24, UiStyle.ACCENT if not g.is_empty() else Color(UiStyle.ACCENT, 0.4), 2.5)
			UiStyle.text(ctrl, UiStyle.head_font(800, 0), Vector2(c.x - 15, c.y + 6), str(gi + 1), UiStyle.FS_BODY,
				UiStyle.ACCENT if not g.is_empty() else Color(UiStyle.ACCENT, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	_modules(p, box)
	_wingmen(p, box)
	var cap := Loc.t("%s · СХЕМА ПОДВЕСОВ") % Loc.t(PlaneClasses.DATA[m.cls_id]["title"]).to_upper()
	UiStyle.text(ctrl, UiStyle.head_font(600, 4), Vector2(box.position.x, box.end.y + 30), cap, UiStyle.FS_CAPTION, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	var syn := PackedStringArray()
	for id in p.syn:
		syn.append("«%s»" % Loc.t(Cards.syn_def(p, id)["title"]))
	if not syn.is_empty():
		UiStyle.text(ctrl, UiStyle.head_font(700, 2), Vector2(box.position.x - 100, box.end.y + 58), Loc.t("СВЯЗКИ: ") + ", ".join(syn),
			UiStyle.FS_BODY, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, box.size.x + 200.0)


func _at(box: Rect2, xy: Vector2) -> Vector2:
	return box.position + xy / 100.0 * box.size


func _group_points(gname: String, gi: int, n: int) -> Array:
	if GROUP_AT.has(gname):
		return GROUP_AT[gname]
	return [Vector2(50, 40 + 30.0 * gi / maxf(n - 1, 1))]


## Modules taken: tiles in two columns beside the plane, each on a dotted leader line to
## where it acts. Centre-line parts go to the side with fewer tiles.
func _modules(p: Player, box: Rect2) -> void:
	var left: Array = []
	var right: Array = []
	var mods: Array = []
	for id in Cards.MODULES:
		if int(p.taken.get(id, 0)) > 0:
			mods.append(id)
	mods.sort_custom(func(a: String, b: String) -> bool: return _module_at(a).y < _module_at(b).y)
	for id: String in mods:
		var at := _module_at(id)
		if at.x < 50.0 or (at.x == 50.0 and left.size() <= right.size()):
			left.append(id)
		else:
			right.append(id)
	_module_column(p, box, left, box.position.x - MOD_TILE - 70.0)
	_module_column(p, box, right, box.end.x + 70.0)


func _module_at(id: String) -> Vector2:
	return MODULE_AT.get(id, Vector2(50, 46))


func _module_column(p: Player, box: Rect2, ids: Array, x: float) -> void:
	if ids.is_empty():
		return
	var step := minf(112.0, (box.size.y + 60.0) / ids.size())
	var y0 := box.position.y - 30.0 + maxf(0.0, (box.size.y + 60.0 - step * ids.size()) / 2.0)
	for i in ids.size():
		var id: String = ids[i]
		var r := Rect2(x, y0 + i * step, MOD_TILE, MOD_TILE)
		var a := _at(box, _module_at(id))
		var from := Vector2(r.end.x + 4.0 if x < box.position.x else r.position.x - 4.0, r.get_center().y)
		ctrl.draw_dashed_line(from, a, Color(UiStyle.ACCENT, 0.7), 1.5, 5.0)
		ctrl.draw_circle(a, 4.0, UiStyle.ACCENT)
		var lvl := int(p.taken.get(id, 0))
		var fam := "skill" if id == "skill3" else (String(Prog.MODULE_TAGS[id][0]) if Prog.MODULE_TAGS.has(id) else "armor")
		var key := p.skill3 if id == "skill3" else id
		HudIcons.tile(ctrl, r, key, fam, Cards.RARITY[clampi(lvl - 1, 0, 4)]["color"], lvl)
		var title := Loc.t(String(Cards.MODULES[id]["title"])) if id != "skill3" else Loc.t(PlaneClasses.SKILL3[p.skill3]["title"])
		var lines := _lines(title, MOD_TILE + 80.0, UiStyle.FS_CAPTION, UiStyle.head_font(600, 1))
		for li in lines.size():
			UiStyle.text(ctrl, UiStyle.head_font(600, 1), Vector2(r.position.x - 40.0, r.end.y + 18.0 + li * 16.0), lines[li], UiStyle.FS_CAPTION,
				UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_CENTER, MOD_TILE + 80.0)


## Wingmen in formation under the wings, outside the drawing.
func _wingmen(p: Player, box: Rect2) -> void:
	var n := 0
	for w in p.wingmen:
		if not is_instance_valid(w):
			continue
		var wm: Wingman = w
		var side := -1.0 if n % 2 == 0 else 1.0
		var row := n / 2
		var c := Vector2(box.get_center().x + side * (box.size.x * 0.36 + row * 60.0), box.end.y - 40.0 + row * 70.0)
		var r := Rect2(c - Vector2(30, 30), Vector2(60, 60))
		HudIcons.tile(ctrl, r, "wingman", "wing", Prog.TAGS["wing"]["color"] if wm.alive() else UiStyle.TEXT_OFF, wm.lvl, 0.0, not wm.alive())
		UiStyle.text(ctrl, UiStyle.head_font(600, 1), Vector2(r.position.x - 30, r.end.y + 18), "«%s»" % Loc.t(Prog.WING_TYPES[wm.type]["short"]).to_upper(),
			UiStyle.FS_CAPTION, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
		n += 1


# ---------- Stats and damage ----------

## Stats table with the change against the class base; returns the bottom y.
func _stats(p: Player, r: Rect2) -> float:
	var c := p.cls
	var rows := [
		[Loc.t("Корпус"), str(int(p.max_hp)), p.max_hp - float(c["hp"]), false, true],
		[Loc.t("Скорость"), _x(float(c["speed"]) * p.mods["speed"]), p.mods["speed"] - 1.0, false, false],
		[Loc.t("Манёвренность"), _x(float(c["turn"]) * p.mods["turn"]), p.mods["turn"] - 1.0, false, false],
		[Loc.t("Урон пушки"), _x(float(c["gun_dmg"]) * p.mods["gun_dmg"]), p.mods["gun_dmg"] - 1.0, false, false],
		[Loc.t("Темп стрельбы"), _x(float(c["gun_rate"]) * p.mods["gun_rate"]), p.mods["gun_rate"] - 1.0, false, false],
		[Loc.t("Перезарядка подвесов"), _x(p.mods["hp_cd"]), p.mods["hp_cd"] - 1.0, true, false],
		[Loc.t("Подбор запчастей"), _x(p.mods["pickup"]), p.mods["pickup"] - 1.0, false, false],
	]
	r.size.y = 64.0 + rows.size() * 34.0
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(r.position.x + 24, r.position.y + 38), Loc.t("ХАРАКТЕРИСТИКИ"), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT)
	var y := r.position.y + 72.0
	var f := ui_font()
	for row: Array in rows:
		UiStyle.text(ctrl, f, Vector2(r.position.x + 24, y), String(row[0]), UiStyle.FS_LABEL, UiStyle.TEXT)
		var d: float = row[2]
		var dt := ""
		if absf(d) > 0.005:
			dt = ("%+d" % int(round(d))) if row[4] else ("%+d %%" % int(round(d * 100.0)))
		var good := (d < 0.0) if row[3] else (d > 0.0)
		var dw := 0.0
		if dt != "":
			dw = UiStyle.text_w(f, dt, UiStyle.FS_CAPTION) + 8.0
			UiStyle.text(ctrl, f, Vector2(r.position.x, y), dt, UiStyle.FS_CAPTION, UiStyle.OK if good else UiStyle.DANGER, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24.0)
		UiStyle.text(ctrl, f, Vector2(r.position.x, y), String(row[1]), UiStyle.FS_LABEL, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24.0 - dw)
		y += 34.0
	return r.end.y


## Tag points as family discs with counts (they unlock synergies); the course's tags show
## «have/need» in amber, so the old pause's «к связке» progress stays. Returns the bottom y.
func _tags(p: Player, r: Rect2) -> float:
	var need := {}
	if p.has_course():
		var sd := Cards.syn_def(p, p.course)
		var c := Cards.slot_cost(p)
		need[String(sd.get("tag", ""))] = int(c["main"])
		need[String(sd.get("tag2", ""))] = int(c["second"])
	var n := Prog.TAG_ORDER.size()
	r.size.y = 64.0 + 78.0
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(r.position.x + 24, r.position.y + 38), Loc.t("ОЧКИ ТЕГОВ"), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT)
	var cw := (r.size.x - 32.0) / n
	for i in n:
		var t: String = Prog.TAG_ORDER[i]
		var cnt := p.tag(t)
		var c := Vector2(r.position.x + 16.0 + cw * (i + 0.5), r.position.y + 78.0)
		HudIcons.disc(ctrl, c, 15.0, t)
		if cnt == 0:
			ctrl.draw_circle(c, 15.5, Color(UiStyle.SCRIM, 0.6))
		var s := str(cnt) if not need.has(t) or int(need[t]) <= 0 else "%d/%d" % [cnt, int(need[t])]
		UiStyle.text(ctrl, UiStyle.head_font(800, 0), Vector2(c.x - cw / 2.0, c.y + 40.0), s, UiStyle.FS_BODY,
			UiStyle.ACCENT if need.has(t) else (UiStyle.TEXT if cnt > 0 else UiStyle.TEXT_OFF), HORIZONTAL_ALIGNMENT_CENTER, cw)
	return r.end.y


func _x(v: float) -> String:
	return Loc.t("×%s") % ("%.2f" % v)


## Top five damage sources of the last minute (DpsWindow), with a bar against the best.
func _damage(m: Main, r: Rect2) -> void:
	var top := m.dps.top(5, m.run_time)
	r.size.y = 64.0 + maxf(top.size(), 1) * 46.0
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(r.position.x + 24, r.position.y + 38), Loc.t("УРОН ЗА ПОСЛЕДНЮЮ МИНУТУ"), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT)
	if top.is_empty():
		UiStyle.text(ctrl, ui_font(), Vector2(r.position.x + 24, r.position.y + 84), Loc.t("пока тихо"), UiStyle.FS_BODY, UiStyle.TEXT_2)
		return
	var best := float(top[0][1])
	var y := r.position.y + 60.0
	for row: Array in top:
		var src := String(row[0])
		var ic := HudIcons.source_icon(src)
		var fc := HudIcons.family_color(String(ic[1]))
		HudIcons.tile(ctrl, Rect2(r.position.x + 22, y, 36, 36), String(ic[0]), String(ic[1]), Color(fc, 0.8))
		var nx := r.position.x + 72.0
		UiStyle.text(ctrl, UiStyle.head_font(700, 0), Vector2(nx, y + 16), HudIcons.source_name(src), UiStyle.FS_BODY, UiStyle.TEXT)
		UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(nx, y + 18), Loc.t("%d/с") % int(round(float(row[1]))), UiStyle.FS_LABEL,
			UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - nx - 24.0)
		var bw := r.end.x - nx - 24.0
		ctrl.draw_rect(Rect2(nx, y + 26, bw, 4), Color(1, 1, 1, 0.1))
		ctrl.draw_rect(Rect2(nx, y + 26, bw * float(row[1]) / maxf(best, 0.01), 4), fc)
		y += 46.0


## Key hints strip at the bottom centre.
func _hints(size: Vector2) -> void:
	var pairs := [[key_label("pause"), Loc.t("продолжить")], ["↑ ↓", Loc.t("подвес")], ["← →", Loc.t("цель подвеса")]]
	var w := 0.0
	for pr: Array in pairs:
		w += UiStyle.text_w(UiStyle.head_font(700, 1), String(pr[0]), UiStyle.FS_CAPTION) + 18.0 + 10.0 \
			+ UiStyle.text_w(UiStyle.head_font(600, 3), String(pr[1]), UiStyle.FS_BODY) + 34.0
	var r := Rect2(size.x / 2.0 - w / 2.0 - 20.0, size.y - 66.0, w + 6.0, 46.0)
	ctrl.draw_rect(r, Color(0.04, 0.045, 0.04, 0.9))
	ctrl.draw_rect(r, UiStyle.LINE, false, 1.0)
	var x := r.position.x + 20.0
	for pr: Array in pairs:
		x = UiStyle.key_hint(ctrl, Vector2(x, r.position.y + 31.0), String(pr[0]), String(pr[1]).to_upper())


# ---------- Focus (keyboard and gamepad, called by MainInput) ----------

## Moves focus up or down through hardpoint rows, the wingmen row and the menu.
static func move_focus(dir: Vector2i) -> void:
	var rects: Array[Rect2] = []
	var ids: Array[StringName] = []
	for f: Array in _focusables:
		rects.append(f[0])
		ids.append(StringName(f[1]))
	var i := UiFocus.index_of(ids, StringName(focus)) if focus != "" else -1
	var j := UiFocus.step(rects, i, dir)
	if j >= 0:
		focus = String(ids[j])


## Action for ←/→ on the focused row ("" when the focus is not on a selector row).
static func side(dir: int) -> String:
	var a: Array = _sides.get(focus, [])
	return "" if a.is_empty() else String(a[1 if dir > 0 else 0])


## Action for Enter/A on the focused item: a row steps its selector forward.
static func accept() -> String:
	var a: Array = _sides.get(focus, [])
	return focus if a.is_empty() else String(a[1])
