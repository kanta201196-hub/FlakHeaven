class_name HudFlight
extends HudKit
## In-flight HUD (combat UI v2, Sublight-style, Kanta 2026-10-24): XP line on top, hull and
## fuel top-left, level and timer framed top centre, parts and kills with sortie goals
## top-right, bottom bar with the skills as icon tiles (key, cooldown, name, one-line hint,
## tooltip on hover) and a column on the left edge with weapon groups, course gun and wingmen
## (Kanta 25.10: the bottom bar keeps only skills, so the radio has its corner back).
## Also threat and task arrows, activities, radio, hints.


var _mini: HudMinimap = null
## Skill columns of this frame for the hover tooltip: [Rect2, title, body, action]
var _skill_tips: Array = []
## Top of the bottom bar this frame (hints and radio sit above it)
var bar_top := 0.0
## Hint box of this frame and of the last one (the radio is drawn before the hint and steps
## above last frame's box instead of covering it)
var _hint_rect := Rect2()
var _hint_prev := Rect2()
## Bottom bar rect this frame (empty when not drawn)
var _bar_rect := Rect2()
## Left weapon column rect this frame (empty when there is nothing in it); `_side_top` — where
## it may start, under the hull panel, set by `_left_panel`
var _side_rect := Rect2()
var _side_top := 200.0
## Left column row height this frame
var _side_row := SIDE_ROW
## Bottom of the goals panel this frame (streak line sits under it)
var _goals_bottom := 0.0
## Process frame in which `draw` last ran: the layers draw only what this frame's pass laid out.
## `_hide` — HUD hidden by the setting (read again by `draw_post`)
var _drawn_frame := -1
var _hide := false
## Layers Hud puts above its own drawing (children of ctrl, drawn in this order after ctrl):
## "bar_s" — the bar's static part, redrawn only when `_bar_sig` changes; "bar_d" — cooldowns,
## reload bars and key caps, every frame; "post" — `draw_post`.
var layers: Dictionary[String, Control] = {}
## Bottom bar and left column of this frame for the bar layers: player, columns (skills on the
## bar, `row` ones in the left column); `_bar_sig` — everything the static part shows,
## compared each frame
var _bar_p: Player = null
var _bar_cols: Array[BarCol] = []
var _bar_sig: Array = []


## One HUD tile as laid out this frame: a weapon group (`hp`, with its target or trigger line
## `sub`) or a skill / course gun / wingmen (`sk`, its tile frame, dimming and key cap).
## `row` — a row of the left column (tile on the left, text beside it) instead of a bottom-bar
## column (tile on top, text under it).
class BarCol extends RefCounted:
	var pos: Vector2
	var row := false
	var hp: Hardpoint = null
	var sub := ""
	var sk: Dictionary = {}
	var frame := Color.WHITE
	var dim := false
	var key := ""

## Size of icon tiles in the bottom bar and the column each tile takes
const BAR_TILE := 56.0
const BAR_COL := 112.0
## Left column: width, row height (shrinks down to SIDE_ROW_MIN when many rows must fit above
## the minimap) and tile size
const SIDE_W := 250.0
const SIDE_ROW := 60.0
const SIDE_ROW_MIN := 50.0
const SIDE_TILE := 44.0


## Draws the in-flight HUD panels (XP line, hull and fuel, activities, timer, goals and
## currency) and lays out the bottom bar. The bar itself and everything that sits above it
## (minimap, radio, hints, tooltip) are drawn by Hud's layers: `draw_bar_static`,
## `draw_bar_dyn`, `draw_post`.
func draw(m: Main, size: Vector2, dmg_flash: float) -> void:
	var p := m.player
	_skill_tips.clear()
	_hint_prev = _hint_rect
	_hint_rect = Rect2()
	bar_top = size.y - 12.0
	_bars_last = [_bar_rect, _side_rect]
	_bar_rect = Rect2()
	_side_rect = Rect2()
	if dmg_flash > 0.0:
		ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0, 0, dmg_flash * 0.5))

	# XP: thin amber line across the top
	ctrl.draw_rect(Rect2(0, 0, size.x, 6), Color(0, 0, 0, 0.55))
	ctrl.draw_rect(Rect2(0, 0, size.x * clampf(m.run.xp / m.xp_need(), 0.0, 1.0), 6), UiStyle.ACCENT)

	var hide := Settings.hide_hud and m.state == "playing"
	var pt := Time.get_ticks_usec() if Perf.on else 0
	if is_instance_valid(p) and not hide:
		_left_panel(m, p)
		if Perf.on: pt = Perf.sub("hud.left", pt)
		_flight_panel(m, p, size)
		if Perf.on: pt = Perf.sub("hud.flight", pt)
		if m.state == "playing":
			_activity_panel(m, p, size)
		if Perf.on: pt = Perf.sub("hud.activity", pt)
	_top_center(m, size)
	if Perf.on: pt = Perf.sub("hud.top_center", pt)
	_top_right(m, size)
	if Perf.on: pt = Perf.sub("hud.top_right", pt)
	if is_instance_valid(p) and m.state == "playing":
		_action_bar(m, p, size)
		if Perf.on: pt = Perf.sub("hud.action_bar", pt)
	_drawn_frame = Engine.get_process_frames()
	_hide = hide


## True when `draw` ran in this process frame, so the layers have fresh layout to draw.
func drawn_now() -> bool:
	return _drawn_frame == Engine.get_process_frames()


## Makes the next bar layout redraw the static layer (it was cleared without drawing).
func forget_bar() -> void:
	_bar_sig = []


## True when this frame's pass laid out the bottom bar (its layers have something to draw).
func bar_now() -> bool:
	return drawn_now() and (_bar_rect.has_area() or _side_rect.has_area())


## The flight HUD above the bottom bar, in the order it always had: minimap, combat texts,
## boss bars, markers, radio, hints, the skill tooltip, banner and first-minute key hints.
## Hud draws it on its own layer after the bar layers, so the bar can sit between the panels
## drawn by `draw` and these without being redrawn every frame.
func draw_post(m: Main, size: Vector2) -> void:
	var p := m.player
	var pt := Time.get_ticks_usec() if Perf.on else 0
	if is_instance_valid(p) and m.state == "playing" and not _hide:
		if _mini == null:
			_mini = HudMinimap.new(ctrl)
		_mini.ctrl = ctrl
		_mini.draw(m, size)
	if Perf.on: pt = Perf.sub("hud.minimap", pt)
	_fx_texts(m)
	if Perf.on: pt = Perf.sub("hud.fx_texts", pt)
	_boss_bars(m, size)
	_threat_markers(size)
	if m.state == "playing":
		_evac_marker(m, size)
		if m.hud.radio_t > 0.0 and is_instance_valid(p) and not _hide:
			_radio_box(m, size)
	if Perf.on: pt = Perf.sub("hud.markers", pt)

	if Hints.t > 0.0 and Hints.text != "" and m.state == "playing":
		_hint_box(Hints.text, size, clampf(Hints.t * 2.0, 0.0, 1.0))
	if m.state == "playing":
		_skill_tooltip(size)   # last: the hovered skill's explanation covers hints and radio
	if m.hud.banner_t > 0.0 and m.state == "playing":
		var a := clampf(m.hud.banner_t, 0.0, 1.0)
		# dark plate under the banner: yellow text on bright sand is unreadable without it
		var bw := ui_font().get_string_size(Loc.out(m.hud.banner), HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 40.0
		var by := maxf(186.0, _boss_bottom + 20.0)   # under the boss bars when an ace is up, with a gap (s12)
		ctrl.draw_rect(Rect2((size.x - bw) / 2.0, by, bw, 44), Color(0.02, 0.025, 0.03, 0.6 * a))
		_ctext(by + 32.0, m.hud.banner, 30, Color(1.0, 0.85, 0.5, a))

	if m.run_time > 180.0 or m.state != "playing":
		return
	# first minutes: how to steer and pause (skill keys are on the bar tiles)
	var hx := size.x / 2.0
	var tw := 0.0
	var pairs := [[Loc.t("МЫШЬ"), Loc.t("куда лететь")], [key_label("pause"), Loc.t("пауза")]]
	if Main.DEBUG:
		pairs.append(["F5–F7", Loc.t("отладка")])
	for pr: Array in pairs:
		tw += UiStyle.text_w(UiStyle.head_font(700, 1), String(pr[0]), UiStyle.FS_CAPTION) + 18.0 + 10.0 \
			+ UiStyle.text_w(UiStyle.head_font(600, 3), String(pr[1]), UiStyle.FS_BODY) + 34.0
	var hy := bar_top - 14.0
	ctrl.draw_rect(Rect2(hx - tw / 2.0 - 12.0, hy - 28.0, tw + 0.0, 38.0), Color(0.02, 0.025, 0.03, 0.62))
	var kx := hx - tw / 2.0
	for pr: Array in pairs:
		kx = UiStyle.key_hint(ctrl, Vector2(kx, hy), String(pr[0]), String(pr[1]))


## U-02: подсказка новичку — рамка над нижней строкой клавиш
func _hint_box(s: String, size: Vector2, a: float) -> void:
	var w := minf(1100.0, size.x - 80.0)
	# высота по тексту: длинная подсказка в три строки не вылезает из рамки
	var th := ui_font().get_multiline_string_size(Loc.out(s), HORIZONTAL_ALIGNMENT_LEFT, w - 32.0, 18).y
	var bh := maxf(86.0, th + 44.0)
	var r := Rect2((size.x - w) / 2.0, bar_top - 70.0 - bh, w, bh)
	_hint_rect = r
	ctrl.draw_rect(r, Color(0.04, 0.05, 0.06, 0.82 * a))
	ctrl.draw_rect(r, Color(1.0, 0.85, 0.4, 0.8 * a), false, 2.0)
	_text(Vector2(r.position.x + 16, r.position.y + 26), "ПОДСКАЗКА", 13, Color(1.0, 0.85, 0.4, a))
	_para(Vector2(r.position.x + 16, r.position.y + 50), s, w - 32.0, 18, Color(1, 1, 1, a))


## Dark plate under HUD text so it reads on bright ground.
func _hud_back(r: Rect2) -> void:
	ctrl.draw_rect(r, Color(0.02, 0.025, 0.03, 0.58))


## Top-left: hull and fuel bars only (Sublight reference: the corner panel is just the
## hull). Synergy slots and the course progress sit in a small plate under it; manual fire
## and wingmen moved to the bottom bar.
func _left_panel(m: Main, p: Player) -> void:
	var x := 20.0
	var pw := 440.0
	var y := 20.0
	UiStyle.panel(ctrl, Rect2(x, y, pw, 84.0), Color(1, 1, 1, 0.12), Color(0.03, 0.035, 0.035, 0.72))
	var bx := x + 40.0
	var bw := pw - 56.0
	# hull: big bar with the numbers on it; red under a third
	var hk := clampf(p.hp / p.max_hp, 0.0, 1.0)
	var hc := Color(0.4, 0.85, 0.45) if hk > 0.33 else UiStyle.DANGER
	_glyph_plus(Vector2(x + 20.0, y + 27.0), hc)
	ctrl.draw_rect(Rect2(bx, y + 16, bw, 22), Color(0, 0, 0, 0.6))
	ctrl.draw_rect(Rect2(bx, y + 16, bw * hk, 22), hc)
	UiStyle.text(ctrl, UiStyle.head_font(700, 1), Vector2(bx, y + 33), Loc.t("КОРПУС %d / %d") % [int(p.hp), int(p.max_hp)],
		UiStyle.FS_BODY, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bw)
	# fuel: thin bar, minutes left on the right
	var fu := Fuel.current()
	if fu != null:
		var fc := UiStyle.DANGER if fu.frac() < 0.1 else (Color(1.0, 0.8, 0.35) if fu.frac() <= Fuel.CALL_AT else Color(0.95, 0.85, 0.4))
		UiStyle.text(ctrl, UiStyle.head_font(800, 0), Vector2(x + 14.0, y + 66.0), "F", UiStyle.FS_BODY, fc)
		ctrl.draw_rect(Rect2(bx, y + 54, bw - 130.0, 10), Color(0, 0, 0, 0.6))
		ctrl.draw_rect(Rect2(bx, y + 54, (bw - 130.0) * fu.frac(), 10), fc)
		var fs := Loc.t("БАК ПУСТ") if fu.empty() else Loc.t("ТОПЛИВО %d:%02d") % [int(fu.left) / 60, int(fu.left) % 60]
		UiStyle.text(ctrl, UiStyle.head_font(600, 2), Vector2(bx, y + 65), fs, UiStyle.FS_CAPTION, fc, HORIZONTAL_ALIGNMENT_RIGHT, bw)
	y += 92.0
	var extra := 0.0
	if not p.syn.is_empty() or p.has_course():
		extra = 42.0 + (30.0 if p.has_course() else 0.0)
		UiStyle.panel(ctrl, Rect2(x, y, pw, extra), Color(1, 1, 1, 0.08), Color(0.03, 0.035, 0.035, 0.6))
		_course_bar(p, Vector2(x + 14, y + 8))
	if m.god_mode:
		_text(Vector2(x, y + extra + 24), "ОТЛАДКА: неуязвимость (F7)", 16, Color(1, 0.5, 0.5))
	_side_top = y + extra + (40.0 if m.god_mode else 12.0)
	if int(Tuning.g("scheme")) == 2 and m.state == "playing":
		var mp := ctrl.get_local_mouse_position()
		ctrl.draw_arc(mp, 12.0, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 2.0)
		ctrl.draw_circle(mp, 2.0, Color(1, 1, 1, 0.9))


## Green "+" of the hull row
func _glyph_plus(c: Vector2, col: Color) -> void:
	ctrl.draw_rect(Rect2(c.x - 8, c.y - 2.5, 16, 5), col)
	ctrl.draw_rect(Rect2(c.x - 2.5, c.y - 8, 5, 16), col)


## Top centre: pilot level over the sortie timer in a bevelled frame.
func _top_center(m: Main, size: Vector2) -> void:
	var cx := size.x / 2.0
	var t := int(m.run_time)
	var lf := UiStyle.head_font(700, 3)
	var lv := Loc.t("УР %d") % m.run.level
	var lw := UiStyle.text_w(lf, lv, UiStyle.FS_LABEL)
	ctrl.draw_rect(Rect2(cx - lw / 2.0 - 26.0, 16.0, lw + 44.0, 28.0), Color(0.02, 0.025, 0.03, 0.6))
	_diamond(Vector2(cx - lw / 2.0 - 12.0, 30.0), 6.0, UiStyle.ACCENT)
	UiStyle.text(ctrl, lf, Vector2(cx - lw / 2.0 + 2.0, 37.0), lv, UiStyle.FS_LABEL, UiStyle.ACCENT)
	var r := Rect2(cx - 92.0, 46.0, 184.0, 56.0)
	var k := 14.0
	var hexa := PackedVector2Array([Vector2(r.position.x + k, r.position.y), Vector2(r.end.x - k, r.position.y),
		Vector2(r.end.x, r.position.y + r.size.y / 2.0), Vector2(r.end.x - k, r.end.y), Vector2(r.position.x + k, r.end.y),
		Vector2(r.position.x, r.position.y + r.size.y / 2.0)])
	ctrl.draw_colored_polygon(hexa, Color(0.03, 0.035, 0.035, 0.82))
	hexa.append(hexa[0])
	ctrl.draw_polyline(hexa, UiStyle.ACCENT, 2.0)
	var tf := UiStyle.head_font(700, 4)
	var ts := "%02d:%02d" % [t / 60, t % 60]
	ctrl.draw_string(tf, Vector2(r.position.x, r.end.y - 13.0), ts, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 40, UiStyle.ACCENT_SOFT)


func _diamond(c: Vector2, s: float, col: Color) -> void:
	ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)


## Number with thin-space thousands groups: 1284 → "1 284".
static func grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Top-right: parts and kills counters, the sortie goals panel under them, FPS in the corner (setting «Счётчик кадров»).
func _top_right(m: Main, size: Vector2) -> void:
	var x := size.x - 20.0
	x = _counter(Rect2(x, 20.0, 0.0, 56.0), grouped(m.run.kills), Loc.t("СБИТО"), Color.WHITE) - 10.0
	_counter(Rect2(x, 20.0, 0.0, 56.0), grouped(int(m.run.parts)), Loc.t("ЗАПЧАСТИ"), UiStyle.PARTS)
	_goals(m, Rect2(size.x - 460.0, 88.0, 440.0, 0.0))
	if Settings.show_fps:
		_text(Vector2(0, size.y - 6), "FPS %d" % Engine.get_frames_per_second(), 14, Color(0.7, 0.7, 0.7, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8.0)


## Counter box right-aligned at r.position.x: big number and a caption. Returns its left x.
func _counter(r: Rect2, value: String, caption: String, col: Color) -> float:
	var nf := UiStyle.head_font(800, 1)
	var cf := UiStyle.head_font(600, 3)
	var w := UiStyle.text_w(nf, value, 34) + UiStyle.text_w(cf, caption, UiStyle.FS_CAPTION) + 44.0
	var box := Rect2(r.position.x - w, r.position.y, w, r.size.y)
	UiStyle.panel(ctrl, box, Color(1, 1, 1, 0.14), Color(0.03, 0.035, 0.035, 0.78), 10.0)
	UiStyle.text(ctrl, nf, Vector2(box.position.x + 16.0, box.end.y - 15.0), value, 34, col)
	UiStyle.text(ctrl, cf, Vector2(box.position.x + 16.0, box.end.y - 22.0), caption, UiStyle.FS_CAPTION, UiStyle.TEXT_2,
		HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 30.0)
	return box.position.x


## Sortie goals: operation goal, «Барон», class task, next ace, late bonus. A row is
## [done, text, reward] — reward shows only numbers the game really pays.
func _goal_rows(m: Main) -> Array:
	var rows: Array = []
	if Main.aces():   # «Битва асов»: the score instead of operation goals
		rows.append([false, Loc.t("асов сбито: %d") % m.run.aces_down, ""])
		if m.run.aces_gone > 0:
			rows.append([false, Loc.t("асов ушло: %d") % m.run.aces_gone, ""])
		var nx := int(ceilf(m.spawner.ace_next_in())) if m.spawner != null else 0
		rows.append([false, Loc.t("ас через %d:%02d") % [nx / 60, nx % 60] if nx > 0 else Loc.t("ас в бою!"), ""])
		return rows
	var t := int(m.run_time)
	var left := maxi(0, 900 - t)
	var op := Campaign.op()
	var op_reward := "" if Campaign.cleared(Campaign.index()) else "+%d" % int(op.get("parts", 0))
	if Campaign.goal_done(m.run_time, m.op_flags):
		rows.append([true, Loc.t("задание выполнено — к эвакуации"), op_reward])
	elif left > 0:
		rows.append([false, "%s %d:%02d" % [Loc.t(op["hud"]), left / 60, left % 60], op_reward])
	else:
		rows.append([false, Loc.t("сбейте ") + (Loc.t("«Барона»") if not m.op_flags.get("baron", false) and (op["need"] as Array).has("baron") else Loc.t("«Крепость»")), op_reward])
	if (op["need"] as Array).has("baron"):
		var bd: bool = m.op_flags.get("baron", false)
		rows.append([bd, Loc.t("«Барон»: %s") % (Loc.t("сбит") if bd else Loc.t("не сбит")), ""])
	var task := m.class_task.hud_line() if m.class_task != null else ""
	if task != "":
		rows.append([m.class_task.state == "done", task.trim_prefix("✓ "), "+%d" % int(Rewards.ACTIVITY[&"class_task"]["parts"])])
	var every := Tuning.g("boss_every")
	var next := (floorf(m.run_time / every) + 1.0) * every - m.run_time
	rows.append([false, Loc.t("ас в бою!") if m.boss_alive() else Loc.t("ас через %d:%02d") % [int(next) / 60, int(next) % 60], ""])
	if m.run_time > 900.0:
		rows.append([false, Loc.t("задержались: добыча ×%.1f") % m.continue_mult(), ""])
	return rows


func _goals(m: Main, r: Rect2) -> void:
	var rows := _goal_rows(m)
	r.size.y = 46.0 + rows.size() * 28.0
	UiStyle.panel(ctrl, r, Color(1, 1, 1, 0.14), Color(0.03, 0.035, 0.035, 0.78))
	UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(r.position.x + 20, r.position.y + 30), Loc.t("ЦЕЛИ ВЫЛЕТА"), UiStyle.FS_BODY, UiStyle.ACCENT_SOFT)
	var y := r.position.y + 58.0
	var f := UiStyle.head_font(700, 1)
	for row: Array in rows:
		var done: bool = row[0]
		var col := UiStyle.OK if done else UiStyle.TEXT
		var box := Rect2(r.position.x + 20, y - 12, 11, 11)
		if done:
			ctrl.draw_rect(box, UiStyle.OK)
		else:
			ctrl.draw_rect(box, Color(col, 0.8), false, 1.5)
		UiStyle.text(ctrl, f, Vector2(r.position.x + 40, y), String(row[1]).to_upper(), UiStyle.FS_CAPTION + 1, col, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 120.0)
		if String(row[2]) != "":
			UiStyle.text(ctrl, f, Vector2(r.position.x, y), String(row[2]), UiStyle.FS_CAPTION + 1, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 20.0)
		y += 28.0
	_goals_bottom = r.end.y


## Bottom centre bar: weapon groups (picture, level, reload, target mode), a divider, then
## skills (key cap, cooldown, name, hint). Hovering a skill shows its tooltip.
## Lays out the bottom bar for this frame: columns, tooltip rects, `bar_top`. Drawing is split
## between two layers: the static part (panel, tiles, names, hints) is redrawn only when what it
## shows changes — re-drawing ten tiles with their captions every frame was ~1–2 ms; cooldown
## sweeps, reload bars and key caps go to the layer above it every frame. Nothing static overlaps
## the dynamic part except the tile under its sweep, so the picture is the same as one pass.
func _action_bar(m: Main, p: Player, size: Vector2) -> void:
	var weps: Array = []
	for g in p.groups:
		if not (g as Hardpoint).is_empty():
			weps.append(g)
	var skills := _skill_list(p)
	var extras := _extra_list(p)
	var cols: Array[BarCol] = []
	var sig: Array = [size, _side_top, TranslationServer.get_locale(), Settings.font]
	# left column: weapon groups, then course gun and wingmen, top to bottom above the minimap
	var rows := weps.size() + extras.size()
	var mm := HudMinimap.rect(size)
	var low := (mm.position.y if mm.has_area() else size.y) - 16.0
	var rh := clampf((low - _side_top - 16.0) / maxf(rows, 1), SIDE_ROW_MIN, SIDE_ROW)
	_side_rect = Rect2(20.0, _side_top, SIDE_W, rows * rh + 16.0) if rows > 0 else Rect2()
	_side_row = rh
	sig.append_array([_side_rect, rh])
	var y := _side_top + 8.0
	for g in weps:
		var hp := g as Hardpoint
		var sub := ""
		if Weapons.DEFS[hp.weapon]["uses_priority"]:
			sub = Loc.t("цель: %s") % Loc.t(Weapons.PRIORITY_NAMES[hp.priority])
		elif hp.uses_trigger():
			sub = Loc.t("пуск: %s") % (Loc.t("авто") if hp.trigger == "auto" else key_labels("fire_hardpoint"))
		var c := BarCol.new()
		c.hp = hp
		c.row = true
		c.pos = Vector2(_side_rect.position.x, y)
		c.sub = sub
		cols.append(c)
		sig.append_array([hp.weapon, hp.level, hp.evo, sub])
		y += rh
	for ex: Dictionary in extras:
		var c := _skill_layout(ex, Vector2(_side_rect.position.x, y), sig, true, rh)
		cols.append(c)
		y += rh
	# bottom bar: skills only
	var w := skills.size() * BAR_COL + 20.0
	var r := Rect2((size.x - w) / 2.0, size.y - 158.0, w, 146.0)
	bar_top = r.position.y
	_bar_rect = r
	sig.append(r)
	var x := r.position.x + 10.0
	for sk: Dictionary in skills:
		cols.append(_skill_layout(sk, Vector2(x, r.position.y + 26.0), sig))
		x += BAR_COL
	_bar_p = p
	_bar_cols = cols
	if sig != _bar_sig:
		_bar_sig = sig
		if layers.has("bar_s"):
			layers["bar_s"].queue_redraw()


## Static look of a skill column or left-column row (`row`, height `rh`) — frame, dim, key —
## for the signature, plus its tooltip rect.
func _skill_layout(sk: Dictionary, pos: Vector2, sig: Array, row := false, rh := SIDE_ROW) -> BarCol:
	var cd: float = sk["cd"]
	var active: float = sk["active"]
	var fam: String = sk["fam"]
	var frame := Color(1, 1, 1, 0.35)
	if active > 0.0 or (cd <= 0.0 and fam == "skill"):
		frame = UiStyle.ACCENT
	var dim := cd > 0.0 and active <= 0.0
	var key := key_label(String(sk["action"]))
	sig.append_array([sk["key"], fam, frame, dim, sk["title"], sk["hint"]])
	var tip := Rect2(pos.x, pos.y, SIDE_W, rh) if row else Rect2(pos.x, pos.y - 16.0, BAR_COL, 136.0)
	_skill_tips.append([tip, "%s · %s" % [String(sk["title"]).to_upper(), key], String(sk["desc"]), String(sk["action"]), row])
	var c := BarCol.new()
	c.sk = sk
	c.pos = pos
	c.row = row
	c.frame = frame
	c.dim = dim
	c.key = key
	return c


## "bar_s" layer: bar and column panels, tiles, names, hints.
func draw_bar_static() -> void:
	if not bar_now():
		return
	if _bar_rect.has_area():
		UiStyle.panel(ctrl, _bar_rect, Color(1, 1, 1, 0.1), Color(0.03, 0.035, 0.035, 0.42))
	if _side_rect.has_area():
		UiStyle.panel(ctrl, _side_rect, Color(1, 1, 1, 0.1), Color(0.03, 0.035, 0.035, 0.38))
	for c in _bar_cols:
		if c.hp != null:
			_weapon_static(c)
		elif c.row:
			_row_static(c)
		else:
			_skill_static(c)


## "bar_d" layer: reload bars, active glow, cooldown sweeps and seconds, key caps.
func draw_bar_dyn() -> void:
	if not bar_now() or not is_instance_valid(_bar_p):
		return
	for c in _bar_cols:
		if c.hp != null:
			_weapon_dyn(_bar_p, c)
		else:
			_skill_dyn(c)


## Icon tile of the bar column at `pos` (centred in the column).
func _tile_rect(pos: Vector2) -> Rect2:
	return Rect2(pos.x + (BAR_COL - BAR_TILE) / 2.0, pos.y, BAR_TILE, BAR_TILE)


## Icon tile of `c`: centred in its bar column, or at the left of its left-column row.
func _tile_of(c: BarCol) -> Rect2:
	if not c.row:
		return _tile_rect(c.pos)
	return Rect2(c.pos.x + 16.0, c.pos.y + (_side_row - SIDE_TILE) / 2.0 - 2.0, SIDE_TILE, SIDE_TILE)


## Name and one-line hint beside a left-column tile (weapon short name with its target or
## trigger, gun mode, wingmen target).
func _row_text(tr: Rect2, title: String, sub: String, col: Color, sub_col: Color) -> void:
	var tx := tr.end.x + 12.0
	var tw := _side_rect.end.x - tx - 12.0
	var nf := UiStyle.head_font(700, 1)
	var cy := tr.get_center().y
	var name_y := cy - 2.0 if sub != "" else cy + 5.0
	UiStyle.text(ctrl, nf, Vector2(tx, name_y), _fit(title, tw, UiStyle.FS_CAPTION, nf), UiStyle.FS_CAPTION, col)
	if sub != "":
		var sf := UiStyle.head_font(600, 0)
		UiStyle.text(ctrl, sf, Vector2(tx, name_y + 17.0), _fit(sub, tw, UiStyle.FS_CAPTION, sf), UiStyle.FS_CAPTION, sub_col)


## Weapon group, static part: tile with level frame and the name with its target or trigger
## line — under the tile in a bar column, beside it in a left-column row.
func _weapon_static(c: BarCol) -> void:
	var hp := c.hp
	var pos := c.pos
	var sub := c.sub
	var tr := _tile_of(c)
	var fam := HudIcons.weapon_family(hp.weapon)
	var fc := HudIcons.family_color(fam)
	var frame: Color = Cards.EVO_COLOR if hp.evo else Cards.RARITY[clampi(hp.level - 1, 0, 4)]["color"]
	HudIcons.tile(ctrl, tr, hp.weapon, fam, frame, hp.level if not hp.evo else -1)
	if hp.evo:
		HudIcons.number(ctrl, Vector2(tr.end.x - 6.0, tr.position.y + 22.0), "★", 20)
	if c.row:
		_row_text(tr, Loc.t(Weapons.DEFS[hp.weapon]["short"]).to_upper(), sub, UiStyle.TEXT, fc.lightened(0.2))
		return
	var nf := UiStyle.head_font(700, 1)
	var nl := _lines(Loc.t(Weapons.DEFS[hp.weapon]["short"]).to_upper(), BAR_COL - 6.0, UiStyle.FS_CAPTION, nf)
	var ny := tr.end.y + 24.0 - (8.0 if nl.size() > 1 else 0.0)
	for i in nl.size():
		UiStyle.text(ctrl, nf, Vector2(pos.x, ny + i * 17.0), nl[i], UiStyle.FS_CAPTION, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, BAR_COL)
	if sub != "":
		UiStyle.text(ctrl, UiStyle.head_font(600, 0), Vector2(pos.x, ny + (nl.size() - 1) * 17.0 + 17.0), _fit(sub, BAR_COL - 4.0, UiStyle.FS_CAPTION, UiStyle.head_font(600, 0)),
			UiStyle.FS_CAPTION, fc.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER, BAR_COL)


## Weapon group, every frame: the reload bar in family colour under the tile.
func _weapon_dyn(p: Player, c: BarCol) -> void:
	var hp := c.hp
	var tr := _tile_of(c)
	var fc := HudIcons.family_color(HudIcons.weapon_family(hp.weapon))
	var full := maxf(hp.reload_time(p), 0.01)
	var k := 1.0 - clampf(hp.cd / full, 0.0, 1.0)
	var by := tr.end.y + (3.0 if c.row else 5.0)
	ctrl.draw_rect(Rect2(tr.position.x, by, tr.size.x, 4.0), Color(1, 1, 1, 0.12))
	ctrl.draw_rect(Rect2(tr.position.x, by, tr.size.x * k, 4.0), fc if k >= 1.0 else fc.darkened(0.25))


## Course gun and wingmen as rows under the weapons in the left column (they used to be text
## lines in the corner panel): skill-like tiles, the key cap is the toggle key.
func _extra_list(p: Player) -> Array:
	var out: Array = []
	var mode := (Loc.t("ручной +%d%%") % int(round(p.manual_bonus * 100.0))) if p.manual_mode else Loc.t("огонь: авто")
	out.append({"key": "gun_dmg", "action": "toggle_fire_mode", "title": Loc.t("Пушка"), "hint": mode,
		"desc": Loc.t("Курсовая пушка стреляет сама. Клавиша переключает ручной огонь: стреляете сами, и урон растёт до +%d%%.") % int(round(Tuning.g("manual_max") * 100.0)),
		"cd": 0.0, "full": 1.0, "active": 0.0, "fam": "kinetic"})
	if p.wingmen.is_empty():
		return out
	var wl := PackedStringArray()
	var back := 0.0
	for w in p.wingmen:
		if not is_instance_valid(w):
			continue
		var wm: Wingman = w
		wl.append("%s %d" % [Loc.t(Prog.WING_TYPES[wm.type]["short"]), wm.lvl])
		if not wm.temp and not wm.alive():
			back = maxf(back, wm.dead_t)
	var hint := (Loc.t("вернётся %d с") % int(ceil(back))) if back > 0.0 else (Loc.t("цель: %s") % Loc.t(Settings.WING_PRIO[Settings.wing_prio]))
	out.append({"key": "wingman", "action": "wing_prio", "title": Loc.t("Звено"), "hint": hint,
		"desc": Loc.t("В звене: %s. Ведомые держат строй и бьют сами. Клавиша меняет, кого они атакуют первым.") % ", ".join(wl),
		"cd": 0.0, "full": 1.0, "active": 0.0, "fam": "wing"})
	return out


## Skills on the bar: [{key (icon), action, title, hint, desc, cd, full, active, fam}].
func _skill_list(p: Player) -> Array:
	var out: Array = []
	if p.has_roll():
		out.append({"key": "roll", "action": "roll", "title": Loc.t("Уклонение"), "hint": Loc.t("бочка: уход от ракет"),
			"desc": Loc.t("Бочка вбок: на время манёвра по вам не попадают, ракеты за вами теряют цель. Перезарядка %d с.") % int(round(p.roll_cd_full())),
			"cd": p.roll_cd, "full": p.roll_cd_full(), "active": p.roll_t, "fam": "maneuver_skill"})
	else:
		out.append({"key": "flares", "action": "roll", "title": Loc.t("Ловушки"), "hint": Loc.t("уводят ракеты"),
			"desc": Loc.t("Залп тепловых ловушек: уводит ракеты, летящие к вам. Перезарядка %d с.") % int(round(p.salvo_cd_full())),
			"cd": p.roll_cd, "full": p.salvo_cd_full(), "active": p.salvo_t, "fam": "maneuver_skill"})
	out.append({"key": "afterburner", "action": "afterburner", "title": Loc.t("Форсаж"), "hint": Loc.t("рывок вперёд"),
		"desc": Loc.t("Рывок на скорости %.1f с, таранит мелких врагов на пути. Тратит топливо. Перезарядка %d с.") % [p.ab_time_full(), int(round(p.ab_cd_full()))],
		"cd": p.ab_cd, "full": p.ab_cd_full(), "active": p.ab_t, "fam": "maneuver_skill"})
	out.append({"key": "dive", "action": "dive", "title": Loc.t("Нырок"), "hint": Loc.t("вниз, под огнём ПВО"),
		"desc": Loc.t("Самолёт уходит к земле на %.1f с: ПВО и ракеты его теряют. Перезарядка %d с.") % [p.dive_time(), int(round(p.dive_cd_full()))],
		"cd": p.dive_cd, "full": p.dive_cd_full(), "active": p.dive_t, "fam": "maneuver_skill"})
	var s3: Dictionary = p.s3_def()
	out.append({"key": p.skill3, "action": "sharp_turn", "title": Loc.t(s3["title"]) + ("" if p.s3_lvl() <= 0 else " " + Prog.ROMAN[p.s3_lvl()]),
		"hint": Loc.t(String(s3.get("hud", ""))), "desc": Loc.t(String(s3.get("short", ""))) + Loc.t(". Перезарядка %d с.") % int(round(p.cd_of(p.skill3))),
		"cd": p.s3_cd, "full": p.cd_of(p.skill3), "active": p.s3_active(), "fam": "skill"})
	if Main.aces():
		out.append({"key": "flares", "action": "skill_2", "title": Loc.t("Ловушки"), "hint": Loc.t("уводят ракеты"),
			"desc": Loc.t("Залп тепловых ловушек: уводит ракеты, летящие к вам. Перезарядка %d с.") % int(round(AcesBalance.FLARE_CD)),
			"cd": p.sb_cd, "full": AcesBalance.FLARE_CD, "active": p.salvo_t, "fam": "maneuver_skill"})
	elif p.skill_b != "":
		var sb: Dictionary = PlaneClasses.SKILL3[p.skill_b]
		out.append({"key": p.skill_b, "action": "skill_2", "title": Loc.t(sb["title"]), "hint": Loc.t(String(sb.get("hud", ""))),
			"desc": Loc.t(String(sb.get("short", ""))) + Loc.t(". Перезарядка %d с.") % int(round(p.cd_of(p.skill_b))),
			"cd": p.sb_cd, "full": p.cd_of(p.skill_b), "active": p.s3_active(p.skill_b), "fam": "skill"})
	return out


## Course gun or wingmen row of the left column, static part: tile, name and hint beside it.
func _row_static(c: BarCol) -> void:
	var tr := _tile_of(c)
	HudIcons.tile(ctrl, tr, String(c.sk["key"]), String(c.sk["fam"]), c.frame, -1, 0.0, c.dim)
	_row_text(tr, String(c.sk["title"]).to_upper(), String(c.sk["hint"]), UiStyle.TEXT, UiStyle.TEXT_2)


## Skill column, static part: tile (amber frame when active or a ready skill, grey otherwise,
## dimmed while cooling down), name and hint. The active glow is per-frame (`_skill_dyn`).
func _skill_static(c: BarCol) -> void:
	var sk := c.sk
	var pos := c.pos
	var tr := _tile_rect(pos)
	var fam: String = sk["fam"]
	HudIcons.tile(ctrl, tr, String(sk["key"]), fam, c.frame, -1, 0.0, c.dim)
	var nc := UiStyle.ACCENT if fam == "skill" else UiStyle.TEXT
	var title := String(sk["title"]).to_upper()
	var nf := UiStyle.head_font(700, 1)
	var ny := tr.end.y + 24.0
	if UiStyle.text_w(nf, title, UiStyle.FS_CAPTION) > BAR_COL - 6.0 and title.contains(" "):
		# two-word names («БОЕВОЙ РАЗВОРОТ») go on two lines rather than shrink
		var sp := title.find(" ")
		UiStyle.text(ctrl, nf, Vector2(pos.x, ny - 8.0), title.left(sp), UiStyle.FS_CAPTION, nc, HORIZONTAL_ALIGNMENT_CENTER, BAR_COL)
		UiStyle.text(ctrl, nf, Vector2(pos.x, ny + 9.0), title.substr(sp + 1), UiStyle.FS_CAPTION, nc, HORIZONTAL_ALIGNMENT_CENTER, BAR_COL)
		ny += 9.0
	else:
		UiStyle.text(ctrl, nf, Vector2(pos.x, ny), title, UiStyle.FS_CAPTION, nc, HORIZONTAL_ALIGNMENT_CENTER, BAR_COL)
	var hint := String(sk["hint"])
	if hint != "":
		# two-line names leave room for one hint line inside the bar
		var hl := _lines(hint, BAR_COL - 6.0, UiStyle.FS_CAPTION, null, 1 if ny > tr.end.y + 24.0 else 2)
		for i in hl.size():
			UiStyle.text(ctrl, ui_font(), Vector2(pos.x, ny + 17.0 + i * 15.0), hl[i], UiStyle.FS_CAPTION, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_CENTER, BAR_COL)


## Skill column, every frame: glow while active, cooldown sweep and seconds, key cap on the
## tile's top-left corner (over the sweep, as before the split).
func _skill_dyn(c: BarCol) -> void:
	var sk := c.sk
	var tr := _tile_of(c)
	var cd: float = sk["cd"]
	var active: float = sk["active"]
	var full: float = maxf(float(sk["full"]), 0.01)
	if active > 0.0:
		for i in 3:
			ctrl.draw_rect(tr.grow(3.0 + i * 3.0), Color(UiStyle.ACCENT, 0.22 - i * 0.06), false, 3.0)
	if cd > 0.0 and active <= 0.0:
		# sweep: the part still cooling down stays dark, clockwise from 12 o'clock
		var ctr := tr.get_center()
		var pts := PackedVector2Array([ctr])
		var frac := clampf(cd / full, 0.0, 1.0)
		var steps := 24
		for i in steps + 1:
			var a := -PI / 2.0 + TAU * (1.0 - frac) + TAU * frac * float(i) / steps
			var d := Vector2.from_angle(a)
			var t := minf(tr.size.x / 2.0 / maxf(absf(d.x), 0.001), tr.size.y / 2.0 / maxf(absf(d.y), 0.001))
			pts.append(ctr + d * t)
		# the last frames of a cooldown give a sliver of sub-pixel width that the renderer cannot
		# triangulate («Invalid polygon data, triangulation failed» in s11–s13 logs): skip it
		if frac > 0.005:
			ctrl.draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
		var cs := ("%.1f" % cd) if cd < 10.0 else str(int(ceil(cd)))
		var f := UiStyle.head_font(800, 0)
		var cfs := int(clampf(tr.size.x * 0.5, 22.0, 30.0))
		ctrl.draw_string_outline(f, Vector2(tr.position.x, ctr.y + cfs * 0.37), cs, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, cfs, 5, Color(0, 0, 0, 0.9))
		ctrl.draw_string(f, Vector2(tr.position.x, ctr.y + cfs * 0.37), cs, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, cfs, Color.WHITE)
	elif active > 0.0:
		var f2 := UiStyle.head_font(800, 0)
		var as_ := "%.1f" % active
		ctrl.draw_string_outline(f2, Vector2(tr.position.x, tr.position.y + 22.0), as_, HORIZONTAL_ALIGNMENT_RIGHT, tr.size.x - 5.0, 20, 4, Color(0, 0, 0, 0.9))
		ctrl.draw_string(f2, Vector2(tr.position.x, tr.position.y + 22.0), as_, HORIZONTAL_ALIGNMENT_RIGHT, tr.size.x - 5.0, 20, UiStyle.ACCENT_SOFT)
	var kf := UiStyle.head_font(700, 1)
	var key := c.key
	var kw := maxf(28.0, UiStyle.text_w(kf, key, UiStyle.FS_CAPTION) + 14.0)
	# key cap on the tile's top-left corner; in a left-column row it hangs off the left edge
	# instead, so it stays inside the row
	var kr := Rect2(tr.position.x - 6.0, tr.position.y - 16.0, kw, 24.0) if not c.row else Rect2(tr.position.x - 12.0, tr.position.y - 6.0, kw, 24.0)
	ctrl.draw_rect(kr, Color(0.05, 0.055, 0.05, 0.95))
	ctrl.draw_rect(kr, Color(1, 1, 1, 0.55), false, 1.5)
	UiStyle.text(ctrl, kf, Vector2(kr.position.x, kr.end.y - 6.0), key, UiStyle.FS_CAPTION, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, kw)


## Rect of the skill column bound to `action` in the last frame (empty if not drawn).
func skill_rect(action: String) -> Rect2:
	for t: Array in _skill_tips:
		if String(t[3]) == action:
			return t[0]
	return Rect2()


## Tooltip over the bar for the skill under the mouse (hover only: holding a key fires it).
func _skill_tooltip(size: Vector2) -> void:
	var mp := ctrl.get_local_mouse_position()
	for t: Array in _skill_tips:
		var r0: Rect2 = t[0]
		if not r0.has_point(mp):
			continue
		var w := 380.0
		var body := Loc.out(String(t[2]))
		var bh := ui_font().get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, w - 32.0, UiStyle.FS_BODY).y
		var r := Rect2(clampf(r0.get_center().x - w / 2.0, 12.0, size.x - w - 12.0), bar_top - bh - 64.0, w, bh + 52.0)
		if t.size() > 4 and bool(t[4]):
			# left-column row: the tooltip opens to the right of the column
			r.position = Vector2(_side_rect.end.x + 12.0, clampf(r0.position.y, 12.0, size.y - r.size.y - 12.0))
		UiStyle.panel(ctrl, r, Color(UiStyle.ACCENT, 0.6), Color(0.04, 0.045, 0.04, 0.95))
		ctrl.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), UiStyle.ACCENT)
		UiStyle.text(ctrl, UiStyle.head_font(700, 3), Vector2(r.position.x + 18, r.position.y + 28), String(t[1]), UiStyle.FS_BODY, UiStyle.ACCENT_SOFT)
		ctrl.draw_multiline_string(ui_font(), Vector2(r.position.x + 18, r.position.y + 52), body, HORIZONTAL_ALIGNMENT_LEFT, w - 32.0, UiStyle.FS_BODY, -1, UiStyle.TEXT)
		return


## Boss bars under the level and timer frame, Sublight-style (reference frames 24.10): the
## boss name in big heading letters over a thick red bar with the hull numbers inside, the
## shield as a blue strip under it. Several bosses stack downwards.
func _boss_bars(m: Main, size: Vector2) -> void:
	var y := 116.0
	_boss_bottom = 0.0
	for n in m.get_tree().get_nodes_in_group("enemies"):
		var b := n as Boss
		if b == null:
			continue
		var w := BOSS_W
		var x := (size.x - w) / 2.0
		if b is Fortress:
			y = _fortress_bar(b as Fortress, x, y, w)
			_boss_bottom = y
			continue
		var hp := minf(b.hp, b.max_hp)
		_boss_head(b.title, hp / b.max_hp, "%s / %s" % [grouped(int(ceil(hp))), grouped(int(ceil(b.max_hp)))], x, y, w)
		if b.shield > 0.0:
			ctrl.draw_rect(Rect2(x, y + BOSS_BAR_Y + BOSS_BAR_H + 3.0, w * b.shield / b.shield_max, 6), Color(0.5, 0.8, 1.0))
		_boss_bottom = y + BOSS_BAR_Y + BOSS_BAR_H + 9.0
		y += BOSS_STEP


const BOSS_W := 760.0
## Lowest y of this frame's boss bars (0 with no boss), so the banner goes under them
var _boss_bottom := 0.0
## Bar offset under the boss name, bar height and the step to the next boss
const BOSS_BAR_Y := 42.0
const BOSS_BAR_H := 30.0
const BOSS_STEP := 94.0


## Boss name and its thick hull bar with `value` written inside; `frac` is the hull left.
func _boss_head(title: String, frac: float, value: String, x: float, y: float, w: float) -> void:
	var hf := UiStyle.head_font(800, 2)
	UiStyle.text(ctrl, hf, Vector2(x - 2.0, y + 34.0), Loc.out(title).to_upper(), 40, Color(0, 0, 0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, w)
	UiStyle.text(ctrl, hf, Vector2(x, y + 32.0), Loc.out(title).to_upper(), 40, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	var bar := Rect2(x, y + BOSS_BAR_Y, w, BOSS_BAR_H)
	ctrl.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.6))
	ctrl.draw_rect(Rect2(bar.position, Vector2(w * clampf(frac, 0.0, 1.0), BOSS_BAR_H)), UiStyle.DANGER.darkened(0.3))
	ctrl.draw_rect(Rect2(bar.position, Vector2(w * clampf(frac, 0.0, 1.0), 4.0)), UiStyle.DANGER.lightened(0.3))
	UiStyle.text(ctrl, hf, Vector2(x, y + BOSS_BAR_Y + 24.0), value, UiStyle.FS_H3, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)


## Правка 3.5-s4: полоса «Крепости» — общая прочность, под ней — значки точек: 4 турели и 2 двигателя, сбитые перечёркнуты.
## FB-01: справа от значков — сколько осталось до нашей базы
## s12: the phase title is a whole sentence («… — правое крыло 1 из 3, бейте в открытый люк») and
## was cut at the dash in the 40 px heading; the part after the dash goes to a smaller line under
## the point icons.
func _fortress_bar(f: Fortress, x: float, y: float, w: float) -> float:
	var fr := f.total_frac()
	var full := Loc.out(f.title)
	var sep := " — " if full.contains(" — ") else "——"   # zh_CN writes the dash without spaces
	var dash := full.find(sep)
	var head := full if dash < 0 else full.left(dash)
	var task := "" if dash < 0 else full.substr(dash + sep.length())
	_boss_head(head, fr, "%d%%" % int(ceil(fr * 100.0)), x, y, w)
	y += BOSS_BAR_Y + BOSS_BAR_H - 6.0   # point icons and the base distance go under the bar
	var ix := x + w / 2.0 - 6 * 28.0 / 2.0
	for pt in f.points:
		var down := float(pt["hp"]) <= 0.0
		var r := Rect2(ix, y + 32, 22, 14)
		var col := Color(1.0, 0.85, 0.3) if pt["kind"] == "turret" else Color(1.0, 0.5, 0.25)
		ctrl.draw_rect(r, Color(0.2, 0.2, 0.2, 0.7) if down else Color(col, 0.85))
		if down:
			ctrl.draw_line(r.position, r.end, Color(1, 0.3, 0.25), 2.0)
			ctrl.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(1, 0.3, 0.25), 2.0)
		else:
			ctrl.draw_rect(Rect2(ix, y + 44, 22.0 * float(pt["hp"]) / float(pt["max"]), 3), Color(0.4, 1.0, 0.5))
		ix += 28.0
	if f.base_pos != Vector2.INF and f.phase < 3:
		var d := int(f.global_position.distance_to(f.base_pos)) / 10
		var s := ("до базы %d м" % d) if f.base_hits == 0 else ("отбомбилась · до базы %d м" % d)
		_text(Vector2(ix + 8, y + 45), s, 15, Color(0.6, 0.9, 1.0) if f.base_hits == 0 else Color(1.0, 0.55, 0.45))
	if task != "":
		_ptext(y + 78.0, task.left(1).to_upper() + task.substr(1), UiStyle.FS_LABEL, Color(1.0, 0.85, 0.55))
		return y + 92.0
	return y + 62.0


# ---------- Указатели у края экрана ----------

func _threat_markers(size: Vector2) -> void:
	var m := Main.I
	if m.projectiles == null:
		return
	var xf := m.get_viewport().get_canvas_transform()
	var rect := Rect2(Vector2.ZERO, size).grow(-40.0)
	for mi in m.projectiles.missiles:
		if not mi["lost"]:
			_edge_arrow(_ws(xf, (mi["p"] as Vector2)), rect, size, Color(1.0, 0.2, 0.15))
	for n in m.get_tree().get_nodes_in_group("enemies"):
		if n is MissileCarrier and n._lock > 0.0:
			_edge_arrow(_ws(xf, (n as Node2D).global_position), rect, size, Color(1.0, 0.6, 0.2))
		elif n is Boss:
			_edge_arrow(_ws(xf, (n as Node2D).global_position), rect, size, Color(1.0, 0.3, 0.6), 1.6)
			if n is Fortress and (n as Fortress).base_pos != Vector2.INF and (n as Fortress).phase < 3:
				var bp: Vector2 = (n as Fortress).base_pos
				_edge_arrow(_ws(xf, bp), rect, size, Color(0.4, 0.8, 1.0), 1.6, Loc.t("база %d м") % (int(m.player.global_position.distance_to(bp)) / 10) if is_instance_valid(m.player) else Loc.t("база"))


func _evac_marker(m: Main, size: Vector2) -> void:
	if not is_instance_valid(m.evac) or not is_instance_valid(m.player):
		return
	var xf := m.get_viewport().get_canvas_transform()
	var rect := Rect2(Vector2.ZERO, size).grow(-60.0)
	var sp := _ws(xf, m.evac.target_pos())
	var d := int(m.player.global_position.distance_to(m.evac.target_pos()))
	_edge_arrow(sp, rect, size, Color(0.4, 1.0, 0.5), 1.8, Loc.t("эвакуация %d м") % (d / 10))
	_ctext(246, Loc.t("ЭВАКУАЦИЯ: ворота %d / %d · %d м · окно %d с") % [m.evac.passed + 1, EvacZone.GATES, d / 10, int(ceil(m.evac.time_left))], 22, Color(0.6, 1.0, 0.7))


## True when `r` touches the bottom bar or the weapons column — this frame's, or the last
## frame's for arrows drawn before the bar is laid out (`_activity_panel`).
func _on_bars(r: Rect2) -> bool:
	for b: Rect2 in [_bar_rect, _side_rect] + _bars_last:
		if b.has_area() and r.intersects(b.grow(6.0)):
			return true
	return false


## Bar and column rects of the previous frame (`_on_bars`)
var _bars_last: Array = []


## Правка 28 (тест 3.5-s4): стрелка с тёмной обводкой и подписью — видна и на жёлтой земле.
## Отзыв 3.5-s7: стрелки заданий, ворот, заправщика и аса — не у края, а на кольце вокруг центра, где их видно.
## S11-38: a point next to the camera plane projects to an infinite or NaN screen position; an
## arrow built from it is a NaN polygon, which Godot reports as «triangulation failed», so such
## points are skipped.
func _edge_arrow(sp: Vector2, rect: Rect2, size: Vector2, col: Color, scale := 1.0, label := "") -> void:
	if not sp.is_finite() or rect.has_point(sp):
		return
	var c := size / 2.0
	var dir := (sp - c).normalized()
	var pos: Vector2
	if label != "" or scale >= 1.6:   # задания, ворота, заправщик и ас
		var rx := size.x * RING_X
		var ry := size.y * RING_Y
		pos = c + dir / sqrt(pow(dir.x / rx, 2.0) + pow(dir.y / ry, 2.0))
	else:
		var tx := INF if absf(dir.x) < 0.001 else (rect.size.x / 2.0) / absf(dir.x)
		var ty := INF if absf(dir.y) < 0.001 else (rect.size.y / 2.0) / absf(dir.y)
		pos = c + dir * minf(tx, ty)
	if not pos.is_finite():
		return
	var a := dir.angle()
	var k := 18.0 * scale
	var pts := PackedVector2Array([pos + Vector2.from_angle(a) * k, pos + Vector2.from_angle(a + 2.5) * k * 0.8, pos + Vector2.from_angle(a - 2.5) * k * 0.8])
	var outl := PackedVector2Array([pos + Vector2.from_angle(a) * (k + 5.0), pos + Vector2.from_angle(a + 2.5) * (k * 0.8 + 5.0), pos + Vector2.from_angle(a - 2.5) * (k * 0.8 + 5.0)])
	ctrl.draw_colored_polygon(outl, Color(0.02, 0.025, 0.03, 0.85))
	ctrl.draw_colored_polygon(pts, col)
	if label != "":
		# подпись — за остриём стрелки (наружу от самолёта), на тёмной плашке
		var lp := pos + dir * (k + 30.0)
		var fs := 15
		var tw := ui_font().get_string_size(Loc.out(label), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(lp.x - tw / 2.0 - 6.0, lp.y - 11.0, tw + 12.0, 22.0)
		if _on_bars(r):
			# s13: past the arrow the label ran onto the skills bar — put it on the inner side
			lp = pos - dir * (k + 30.0)
			r.position = Vector2(lp.x - tw / 2.0 - 6.0, lp.y - 11.0)
		ctrl.draw_rect(r, Color(0.02, 0.025, 0.03, 0.7))
		ctrl.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), col)
		_text(Vector2(r.position.x + 6, lp.y + 5), label, fs, col.lightened(0.25))


## Газ (РУД), «на хвосте», серия сбитий
func _flight_panel(m: Main, p: Player, size: Vector2) -> void:
	if p.hp <= 0.0:
		return
	var x := 24.0 + HudMinimap.rect(size).size.x + (16.0 if Settings.minimap > 0 else 0.0) # газ — правее миникарты
	var y := size.y - 74.0
	var sch := int(Tuning.g("scheme"))
	if sch != 0:
		var lo := Tuning.g("throttle_min")
		var hi := Tuning.g("throttle_max")
		var w := 260.0
		# s12: thin text over light sand — a dark plate under the label
		ctrl.draw_rect(Rect2(x - 8.0, y - 30.0, w + 16.0, 48.0), Color(0.02, 0.025, 0.03, 0.55))
		_text(Vector2(x, y - 8), Loc.t("Газ [W/S]: %d%%%s") % [int(round(p.throttle * 100.0)), Loc.t("  ФОРСАЖ") if p.ab_t > 0.0 else ""], 17, Color(0.85, 0.9, 1.0))
		ctrl.draw_rect(Rect2(x, y, w, 10), Color(1, 1, 1, 0.08))
		ctrl.draw_rect(Rect2(x, y, w * (p.throttle - lo) / (hi - lo), 10), Color(0.55, 0.8, 1.0) if p.throttle <= 1.0 else Color(1.0, 0.7, 0.35))
		var mid := x + w * (1.0 - lo) / (hi - lo)
		ctrl.draw_line(Vector2(mid, y - 3), Vector2(mid, y + 13), Color.WHITE, 2.0)
	if p.combat_t > 0.0:
		# U-02: боевой режим после разворота — полоска под самолётом
		_ptext(size.y / 2.0 + 96.0, Loc.t("БОЕВОЙ РЕЖИМ: пушка ×2 · %.1f с") % p.combat_t, 20, Color(0.6, 0.9, 1.0))
	if p.on_tail():
		_ptext(size.y / 2.0 + 122.0, "НА ХВОСТЕ: пушка +50%", 22, Color(1.0, 0.9, 0.4))
	var rk := p.run_k()
	if rk > 1.05:
		# EX-04: заход на атаку — прямой полёт усиливает пушку, НАР и бомбы
		_ptext(size.y / 2.0 + 150.0, Loc.t("ЗАХОД: пушка и взрывы +%d%%") % int(round((rk - 1.0) * 100.0)), 20, Color(1.0, 0.75, 0.4, clampf((rk - 1.0) / Player.RUN_BONUS, 0.4, 1.0)))
	if m.run.streak >= 3:
		var a := clampf(m.run.streak_t, 0.0, 1.0)
		var stt := Loc.t("Серия ×%d · опыт ×%.2f") % [m.run.streak, m.streak_mult()]
		var stw := ui_font().get_string_size(Loc.out(stt), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0
		ctrl.draw_rect(Rect2(size.x - 20.0 - stw, _goals_bottom + 10.0, stw, 30.0), Color(0.02, 0.025, 0.03, 0.55 * a))
		_text(Vector2(0, _goals_bottom + 32.0), stt, 20, Color(1.0, 0.75, 0.4, a), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 32.0)


## Правка 28: цвета активностей — без жёлтого, он теряется на песке Нагорья
const RING_X := 0.30   # отзыв 3.5-s7: кольцо стрелок заданий — доля ширины и высоты экрана от центра
const RING_Y := 0.32
const C_AA := Color(0.35, 0.85, 1.0)
const C_CONVOY := Color(1.0, 0.5, 0.25)
const C_TRANSPORT := Color(1.0, 0.55, 0.95)
const C_RESCUE := Color(0.45, 1.0, 0.55)
const C_FORT := Color(1.0, 0.42, 0.32)   # FA-01: the enemy base — red, apart from the AA site's blue


## Caption of an activity target, drawn on the HUD over the world: above the target, or under it
## when the task plate `avoid` covers that spot (s12: «Транспортник» hid under «ОХОТА»).
func _world_caption(xf: Transform2D, wp: Vector2, radius: float, s: String, col: Color, avoid: Rect2) -> void:
	var top := _ws(xf, wp + Vector2(0.0, -radius - 24.0))
	var bot := _ws(xf, wp + Vector2(0.0, radius + 40.0))
	if not top.is_finite() or not bot.is_finite():
		return
	var pos := top
	if Rect2(top.x - 120.0, top.y - 20.0, 240.0, 26.0).intersects(avoid):
		pos = bot
	_text(Vector2(pos.x - 120.0, pos.y), s, 18, col, HORIZONTAL_ALIGNMENT_CENTER, 240.0)


## Task plate of the activity under way: the y set by `_activity_panel`, the one-line form while
## boss bars are up, and the plate drawn this frame (world captions step out from under it).
var _task_y := 250.0
var _task_compact := false
var _task_rect := Rect2()


## Activity task line on its dark plate: full width with room for the reward line, or (boss up)
## a plate just around the line.
func _task(s: String, col: Color) -> void:
	var w := 980.0
	var h := 62.0
	if _task_compact:
		w = ui_font().get_string_size(Loc.out(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 40.0
		h = 34.0
	_task_rect = Rect2((ctrl.size.x - w) / 2.0, _task_y, w, h)
	ctrl.draw_rect(_task_rect, Color(0.02, 0.025, 0.03, 0.78))   # s12: dense, red text read poorly on brown
	_ctext(_task_y + (24.0 if _task_compact else 26.0), s, 20 if _task_compact else 22, col)


## Reward line under the task; left out of the one-line form.
func _task_sub(s: String) -> void:
	if not _task_compact:
		_ctext(_task_y + 52.0, s, 17, Color(0.85, 0.75, 1.0))


## Активности: указатели на позицию ПВО и аса-соперника, радиопереговоры, «ХВОСТ!»
func _activity_panel(m: Main, p: Player, size: Vector2) -> void:
	var xf := m.get_viewport().get_canvas_transform()
	var rect := Rect2(Vector2.ZERO, size).grow(-60.0)
	var node: Node = m.spawner.activity_node if m.spawner != null else null
	# s12: with boss bars up, the task plate goes under them and the banner slot (it overlapped them);
	# s13: there it shrinks to one line, so the top of the field is not three plates deep
	_task_compact = _boss_bottom > 0.0
	var ay := 250.0 if not _task_compact else maxf(250.0, _boss_bottom + 72.0)
	_task_y = ay
	if is_instance_valid(node):
		if node is FortArea:
			var base := node as FortArea
			var db := int(p.global_position.distance_to(base.global_position))
			_edge_arrow(_ws(xf, base.global_position), rect, size, C_FORT, 1.8, Loc.t("база %d м") % (db / 10))
			var bs: String
			if base.failed:
				bs = Loc.t("База противника устояла · пусковых осталось: %d") % base.launchers_left()
			elif base.active:
				bs = Loc.t("УКРЕПРАЙОН: %d с · пусковых на башнях: %d из %d") % [int(ceil(base.timer)), base.launchers_left(), base.launchers.size()]
			else:
				bs = Loc.t("База противника: %d м — подлетите, чтобы начать") % (db / 10)
			_task(bs, Color(1.0, 0.7, 0.55))
			if not base.failed:
				_task_sub("Награда: выбор из редких карточек + 60 запчастей")
		elif node is AASite:
			var site := node as AASite
			var d := int(p.global_position.distance_to(site.global_position))
			_edge_arrow(_ws(xf, site.global_position), rect, size, C_AA, 1.8, Loc.t("ПВО %d м") % (d / 10))
			var s: String
			if site.failed:
				s = Loc.t("Позиция ПВО устояла · бункер: %d%%") % int(ceil(site.bunker_frac() * 100.0))
			elif site.active:
				s = Loc.t("ПОЗИЦИЯ ПВО: %d с · уничтожьте бункер: %d%%") % [int(ceil(site.timer)), int(ceil(site.bunker_frac() * 100.0))]
			else:
				s = Loc.t("Позиция ПВО: %d м — подлетите, чтобы начать") % (d / 10)
			_task(s, Color(1.0, 0.85, 0.4))
			if not site.failed:
				_task_sub("Награда: выбор из редких карточек + 40 запчастей")
		elif node is Rescue:
			var rs := node as Rescue
			var dr := int(p.global_position.distance_to(rs.global_position)) / 10
			_edge_arrow(_ws(xf, rs.global_position), rect, size, C_RESCUE, 1.8, Loc.t("маяк %d м") % dr)
			var rt: String
			if rs.done:
				rt = Loc.t("Пилот спасён!")
			elif rs.failed:
				rt = Loc.t("Вертолёт ушёл без пилота")
			elif rs.active:
				rt = Loc.t("СБИТЫЙ ПИЛОТ: держите небо над маяком ещё %d с") % int(ceil(rs.timer)) + ("" if p.global_position.distance_to(rs.global_position) < Rescue.HOLD_R else Loc.t(" · вернитесь к маяку!"))
			else:
				rt = Loc.t("Аварийный маяк: %d м · вертолёт ждёт ещё %d с") % [dr, int(ceil(rs.life))]
			_task(rt, Color(0.55, 1.0, 0.65))
			if not rs.done and not rs.failed:
				_task_sub("Награда: выбор из редких карточек + 40 запчастей")
		elif node is Convoy:
			var cv := node as Convoy
			var sea := Biome.sea()
			var dm := int(p.global_position.distance_to(cv.global_position)) / 10
			_edge_arrow(_ws(xf, cv.global_position), rect, size, C_CONVOY, 1.8, Loc.t("караван %d м" if sea else "колонна %d м") % dm)
			var cs: String
			if cv.alarm:
				cs = Loc.t("КАРАВАН: до гавани %d с · сухогрузов: %d из %d" if sea else "КОЛОННА: до укрытия %d с · грузовиков: %d из %d") % [int(ceil(maxf(cv.timer, 0.0))), cv.trucks_left(), cv.trucks_total]
			else:
				cs = Loc.t("Караван снабжения: %d м — подлетите и потопите сухогрузы" if sea else "Колонна снабжения: %d м — подлетите и сожгите грузовики") % dm
			_task(cs, Color(1.0, 0.78, 0.45))
			_task_sub("Подбейте головное судно — караван встанет · награда: груз с каждого сухогруза" if sea else "Подбейте головную машину — колонна встанет · награда: груз с каждого грузовика")
		elif node is Transport:
			var tr := node as Transport
			_edge_arrow(_ws(xf, tr.global_position), rect, size, C_TRANSPORT, 1.8, Loc.t("транспортник %d м") % (int(p.global_position.distance_to(tr.global_position)) / 10))
			_world_caption(xf, tr.global_position, tr.radius, "Транспортник", Color(1, 0.85, 0.6), _task_rect)
			_task(Loc.t("ОХОТА: транспортник уйдёт через %d с · прочность %d%%") % [int(ceil(maxf(tr.life, 0.0))), int(ceil(tr.hp / tr.max_hp * 100.0))], Color(1.0, 0.75, 0.45))
			_task_sub("Награда: груз — запчасти и ремкомплекты")
		elif node is RivalAce:
			var ace := node as RivalAce
			_edge_arrow(_ws(xf, ace.global_position), rect, size, Color(1.0, 0.3, 0.35), 1.8, Loc.t("ас %d м") % (int(p.global_position.distance_to(ace.global_position)) / 10))
			_task(Loc.t("ДОГФАЙТ: ас «%s» · уйдёт через %d с") % [ace.callsign, int(ceil(ace.life))], Color(1.0, 0.72, 0.7))
			_task_sub("Награда: выбор из редких карточек")
			if ace.threatening() and int(Time.get_ticks_msec() / 200) % 2 == 0:
				_ptext(size.y / 2.0 + 196.0, "ХВОСТ! Сбрось газ (S) или манёвр", 30, Color(1.0, 0.42, 0.36), 0.75)   # under the plane: above it the boss and task plates stack
	# 3.5: свой заправщик
	var tk: Tanker = m.spawner.fuel.tanker if m.spawner != null and m.spawner.fuel != null else null
	if is_instance_valid(tk) and tk.alive() and not tk.leaving:
		_edge_arrow(_ws(xf, tk.global_position), rect, size, Color(0.45, 1.0, 0.55), 1.8, Loc.t("заправщик %d м") % (int(p.global_position.distance_to(tk.global_position)) / 10))
		var ts := Loc.t("СТЫКОВКА — ЗАПРАВКА ИДЁТ") if tk.filling else (Loc.t("ШТАНГА ВЫДВИГАЕТСЯ — держитесь ровно") if tk.in_cone else Loc.t("ЗАПРАВЩИК: зайдите ему в хвост"))
		_ctext(ay + (52.0 if _task_compact else 78.0), Loc.t("%s · уйдёт через %d с · прочность %d%%") % [ts, int(ceil(tk.life)), int(ceil(tk.hp / tk.max_hp * 100.0))], 20, Color(0.55, 1.0, 0.65))


## Правка 20 (тест 3.5-s4): радиоэфир — справа внизу, значок рации, позывной, полупрозрачная плашка.
## S9-14 (Kanta: «почти незаметна»): крупнее — шрифт 22/17 вместо 17/14, плотнее фон, рамка цветом эфира,
## новое сообщение въезжает справа и вспыхивает
func _radio_box(m: Main, size: Vector2) -> void:
	var a := clampf(m.hud.radio_t, 0.0, 1.0)
	var w := 620.0
	var lines := ui_font().get_multiline_string_size(Loc.out(m.hud.radio_text), HORIZONTAL_ALIGNMENT_LEFT, w - 112.0, 22).y
	var h := maxf(96.0, 54.0 + lines)
	var age := m.hud.radio_age()
	var slide := 1.0 - clampf(age / 0.25, 0.0, 1.0)
	var r := Rect2(size.x - w - 20.0 + slide * slide * 160.0, size.y - h - 40.0, w, h)
	if _bar_rect.size.x > 0.0 and r.position.x < _bar_rect.end.x + 12.0:
		# narrower first, so it keeps its bottom-right corner beside the skills bar; lift it
		# above the bar only when that would make it too narrow
		var room := size.x - 20.0 - (_bar_rect.end.x + 12.0)
		if room >= 480.0:
			r.position.x += r.size.x - room
			r.size.x = room
			w = room
			lines = ui_font().get_multiline_string_size(Loc.out(m.hud.radio_text), HORIZONTAL_ALIGNMENT_LEFT, w - 112.0, 22).y
			h = maxf(96.0, 54.0 + lines)
			r.size.y = h
			r.position.y = size.y - h - 40.0
		else:
			r.position.y = minf(r.position.y, _bar_rect.position.y - h - 12.0)
	if _hint_prev.size.x > 0.0 and r.intersects(_hint_prev):
		r.position.y = _hint_prev.position.y - h - 12.0
	var col := Color(1.0, 0.5, 0.45) if m.hud.radio_enemy else Color(0.55, 0.95, 0.7)
	var flash := 1.0 - clampf(age / 0.6, 0.0, 1.0)
	ctrl.draw_rect(r, Color(0.02, 0.03, 0.035, 0.86 * a))
	ctrl.draw_rect(r, Color(col.r, col.g, col.b, (0.45 + 0.5 * flash) * a), false, 2.0 + 2.0 * flash)
	ctrl.draw_rect(Rect2(r.position, Vector2(6, r.size.y)), Color(col.r, col.g, col.b, a))
	# значок рации: корпус, антенна и волны эфира (мигают, пока сообщение свежее)
	var ic := r.position + Vector2(48, 50)
	ctrl.draw_rect(Rect2(ic.x - 16, ic.y - 10, 32, 40), Color(col.r, col.g, col.b, 0.9 * a))
	ctrl.draw_rect(Rect2(ic.x - 10, ic.y - 4, 20, 10), Color(0.03, 0.04, 0.05, a))
	ctrl.draw_line(Vector2(ic.x + 9, ic.y - 10), Vector2(ic.x + 9, ic.y - 28), Color(col.r, col.g, col.b, a), 2.5)
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	for i in 2:
		ctrl.draw_arc(Vector2(ic.x + 9, ic.y - 28), 8.0 + i * 8.0, -PI * 0.85, -PI * 0.15, 8, Color(col.r, col.g, col.b, a * blink * (1.0 - i * 0.3)), 2.0)
	# s13: ace names come quoted already («Сквозняк») — no second pair of quotes
	_text(Vector2(r.position.x + 92, r.position.y + 28), Loc.t("РАДИОЭФИР · «%s»") % m.hud.radio_from.trim_prefix("«").trim_suffix("»"), 18, Color(col.r, col.g, col.b, a))
	_para(Vector2(r.position.x + 92, r.position.y + 56), m.hud.radio_text, w - 112.0, 22, Color(1, 1, 1, a))


# ---------- 3.2: курс ----------

## Course plate under the hull panel: synergy slots, then one line with the progress to the
## course synergy (its conditions are on the pause screen, tag points).
func _course_bar(p: Player, pos: Vector2, width := 412.0) -> void:
	var x := pos.x
	var sw := (width - 8.0 * (Cards.MAX_SYN - 1)) / Cards.MAX_SYN
	for i in Cards.MAX_SYN:
		var r := Rect2(x, pos.y, sw, 26)
		var ids: Array = p.syn.keys()
		if i < ids.size():
			var sd := Cards.syn_def(p, ids[i])
			var col: Color = sd.get("color", Menu.C_AMBER)
			ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.35))
			ctrl.draw_rect(r, col, false, 2.0)
			_text(Vector2(x + 6, pos.y + 19), "◆ " + Loc.t(String(sd["title"])), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, sw - 8.0)
		else:
			ctrl.draw_rect(r, Color(1, 1, 1, 0.06))
			ctrl.draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
			_text(Vector2(x + 6, pos.y + 19), Loc.t("связка %d") % (i + 1), 14, Color(0.62, 0.64, 0.7))
		x += sw + 8.0
	if not p.has_course():
		return
	var sd2 := Cards.syn_def(p, p.course)
	var conds := Cards.cond_list(p, p.course)
	var k := Cards._progress(conds)
	var ready := Cards.conds_ok(conds)
	var y := pos.y + 32.0
	var col2: Color = sd2.get("color", Menu.C_AMBER)
	_text(Vector2(pos.x, y + 14), Loc.t("К связке «%s»") % Loc.t(sd2["title"]), 16, col2.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT, width * 0.5)
	var bw := width * 0.45
	ctrl.draw_rect(Rect2(pos.x + width - bw, y + 2, bw, 14), Color(0, 0, 0, 0.5))
	var a := 1.0 if not ready else (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01))
	ctrl.draw_rect(Rect2(pos.x + width - bw, y + 2, bw * k, 14), Color(col2.r, col2.g, col2.b, a))
	if ready:
		_text(Vector2(pos.x + width - bw, y + 15), Loc.t("в следующем выборе!"), 14, Color(1.0, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, bw)


## Мир → экран: с наклонной камерой (B-47) через 3D-камеру, иначе через 2D-трансформ
func _ws(xf: Transform2D, p: Vector2) -> Vector2:
	return Render3D.I.world_to_screen(p, xf * p) if Render3D.I != null else xf * p


## Правка 3.5-s4: цифры урона и надписи боя («Сбит с хвоста!», «АС СБИТ!») — в экранных координатах
## над точкой мира, с обводкой; размер не зависит от высоты камеры и качества слоя боя
func _fx_texts(m: Main) -> void:
	if m.fx == null or not Fx.texts_in_hud():
		return
	var xf := m.get_viewport().get_canvas_transform()
	var f := Hud.ui_font()
	for n in m.fx.numbers:
		var a := clampf(float(n["life"]) * 2.0, 0.0, 1.0)
		var c: Color = n["c"]
		c.a = a
		var sz := int(n["size"]) + 4
		var s: String = n["t"]
		var sp := _ws(xf, n["p"]) - Vector2(f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x / 2.0, 0.0)
		ctrl.draw_string_outline(f, sp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.7 * a))
		ctrl.draw_string(f, sp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)
