class_name HudResult
extends HudKit
## Sortie results (combat UI v2, step 9; Kanta's Sublight reference «финальный экран»).
## Title «ЭВАКУАЦИЯ» or «САМОЛЁТ СБИТ» with the operation line; left — damage summary with
## shares and a bar per source (a toggle shows damage taken instead); centre — kills, time,
## pilot level and aces in big numbers, the sortie's key takeaways under them; right — the
## build as an icon grid, then rewards by line, total and the crew experience bar. Bottom
## right: report, menu, change plane, hangar and «Ещё вылет»; keys on the left.

const LEFT_W := 600.0
const MID_W := 400.0
const RIGHT_W := 620.0
const TOP := 300.0
const BUILD_TILE := 72.0


## Draws the whole results screen (and the demo-end overlay over it when it is open).
func result(m: Main, size: Vector2) -> void:
	if Demo.end_open:
		_demo_end(size)
		return
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.SCRIM, 0.93))
	var hf := UiStyle.head_font(600, 5)
	UiStyle.text(ctrl, hf, Vector2(64, 58), "◇ FLAK HEAVEN  //  " + Loc.t("ОТЧЁТ О ВЫЛЕТЕ"), 20, UiStyle.TEXT)
	ctrl.draw_line(Vector2(64, 96), Vector2(size.x - 64, 96), UiStyle.LINE, 1.0)
	var evac := m.state == "evac"
	UiStyle.text(ctrl, UiStyle.head_font(800, 12), Vector2(0, 204), Loc.t("ЭВАКУАЦИЯ") if evac else Loc.t("САМОЛЁТ СБИТ"), 84,
		UiStyle.OK if evac else UiStyle.DANGER, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var sub := Loc.t("ОПЕРАЦИЯ «%s» · «%s» · ЭКИПАЖ «%s»") % [Loc.t(Campaign.op()["title"]).to_upper(),
		Loc.t(PlaneClasses.DATA[m.cls_id]["title"]).to_upper(), String(Profile.cls(m.cls_id)["callsign"]).to_upper()]
	UiStyle.text(ctrl, UiStyle.head_font(700, 6), Vector2(0, 240), sub, UiStyle.FS_LABEL, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var op := op_line(m)
	if not op.is_empty():
		UiStyle.text(ctrl, ui_font(), Vector2(0, 272), String(op[0]), UiStyle.FS_BODY, op[1], HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var gap := (size.x - 128.0 - LEFT_W - MID_W - RIGHT_W) / 2.0
	var lx := 64.0
	var mx := lx + LEFT_W + gap
	var rx := mx + MID_W + gap
	var bottom := size.y - 120.0
	if m.result_tab == 0:
		_dealt(m, Rect2(lx, TOP, LEFT_W, 0))
	else:
		_taken(m, Rect2(lx, TOP, LEFT_W, 0), bottom)
	var ny := _numbers(m, Rect2(mx, TOP, MID_W, 0))
	_takeaways(m, Rect2(mx, ny + 18.0, MID_W, bottom - ny - 18.0))
	var by := _build(m, Rect2(rx, TOP, RIGHT_W, 0))
	_rewards(m, Rect2(rx, by + 18.0, RIGHT_W, 0))
	ctrl.draw_line(Vector2(64, size.y - 96), Vector2(size.x - 64, size.y - 96), UiStyle.LINE, 1.0)
	_bottom(m, size)


# ---------- Damage ----------

## «Сводка урона»: top sources with rank, icon, share, total and a bar against the best.
func _dealt(m: Main, r: Rect2) -> void:
	var dealt: Dictionary = m.stats["dealt"]
	var keys := _top_keys(dealt, 7)
	r.size.y = 150.0 + maxf(keys.size(), 1) * 58.0
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	var tf := UiStyle.head_font(700, 4)
	UiStyle.text(ctrl, tf, Vector2(r.position.x + 28, r.position.y + 42), Loc.t("СВОДКА УРОНА"), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT)
	var tot := float(maxi(m.total("dealt"), 1))
	var best := float(dealt[keys[0]]) if not keys.is_empty() else 1.0
	var y := r.position.y + 66.0
	var x := r.position.x + 28.0
	var w := r.size.x - 56.0
	if keys.is_empty():
		UiStyle.text(ctrl, ui_font(), Vector2(x, y + 24), Loc.t("Урона не нанесено"), UiStyle.FS_BODY, UiStyle.TEXT_2)
	for i in keys.size():
		var k: String = keys[i]
		var v := float(dealt[k])
		var ic := HudIcons.source_icon(k)
		var fc := HudIcons.family_color(String(ic[1]))
		UiStyle.text(ctrl, UiStyle.head_font(600, 0), Vector2(x, y + 24), "%02d" % (i + 1), UiStyle.FS_CAPTION, UiStyle.TEXT_DIM)
		HudIcons.tile(ctrl, Rect2(x + 30, y, 40, 40), String(ic[0]), String(ic[1]), Color(fc, 0.8))
		var nx := x + 84.0
		UiStyle.text(ctrl, UiStyle.head_font(700, 0), Vector2(nx, y + 20), _fit(HudIcons.source_name(k), w - 84.0 - 190.0, UiStyle.FS_LABEL, UiStyle.head_font(700, 0)),
			UiStyle.FS_LABEL, UiStyle.TEXT)
		UiStyle.text(ctrl, UiStyle.head_font(600, 0), Vector2(nx, y + 20), "%s %%" % _dec(100.0 * v / tot), UiStyle.FS_CAPTION, UiStyle.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT, w - 84.0 - 110.0)
		UiStyle.text(ctrl, UiStyle.head_font(800, 0), Vector2(nx, y + 21), _short(v), UiStyle.FS_LABEL + 1, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, w - 84.0)
		ctrl.draw_rect(Rect2(nx, y + 32, w - 84.0, 5), Color(1, 1, 1, 0.1))
		ctrl.draw_rect(Rect2(nx, y + 32, (w - 84.0) * v / best, 5), fc)
		y += 58.0
	ctrl.draw_line(Vector2(x, y + 8), Vector2(x + w, y + 8), UiStyle.LINE, 1.0)
	var rt := maxf(m.run_time, 1.0)
	UiStyle.text(ctrl, tf, Vector2(x, y + 46), Loc.t("ВСЕГО · %s В СЕКУНДУ") % _grouped(int(tot / rt)), UiStyle.FS_LABEL, UiStyle.TEXT)
	UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(x, y + 48), _short(tot), 34, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_toggle(Rect2(x, r.end.y + 14.0, 360.0, 40.0), Loc.t("▸ ПОДРОБНОСТИ · ПОЛУЧЕННЫЙ УРОН"), "rtab:1")


## Damage taken: by kind and by whom, with bars, and the sortie's flight numbers under them.
func _taken(m: Main, r: Rect2, bottom: float) -> void:
	r.size.y = bottom - r.position.y - 60.0
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	var tf := UiStyle.head_font(700, 4)
	var x := r.position.x + 28.0
	var w := r.size.x - 56.0
	var tk := m.total("taken")
	UiStyle.text(ctrl, tf, Vector2(x, r.position.y + 42), Loc.t("ПОЛУЧЕННЫЙ УРОН"), UiStyle.FS_LABEL, UiStyle.ACCENT_SOFT)
	UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(x, r.position.y + 44), _grouped(tk), UiStyle.FS_H2, UiStyle.DANGER.lightened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, w)
	var y := r.position.y + 76.0
	for k in ["таран", "пули", "ракеты"]:
		y = _bar_row(Vector2(x, y), w, Loc.t(k), m.stat("taken", k), tk, UiStyle.DANGER)
	var tkind: Dictionary = m.stats.get("taken_kind", {})
	if not tkind.is_empty():
		y += 10.0
		UiStyle.text(ctrl, UiStyle.head_font(700, 3), Vector2(x, y + 14), Loc.t("ЧЕМ"), UiStyle.FS_CAPTION, UiStyle.TEXT_DIM)
		y += 24.0
		for k in _top_keys(tkind, 4):
			y = _bar_row(Vector2(x, y), w, Loc.t(String(k)), m.stat("taken_kind", k), tk, UiStyle.DANGER.lerp(UiStyle.ACCENT, 0.3))
	y += 10.0
	UiStyle.text(ctrl, UiStyle.head_font(700, 3), Vector2(x, y + 14), Loc.t("ОТ КОГО"), UiStyle.FS_CAPTION, UiStyle.TEXT_DIM)
	y += 24.0
	for k in _top_keys(m.stats["taken_by"], 5):
		y = _bar_row(Vector2(x, y), w, Loc.t(String(k)), m.stat("taken_by", k), tk, UiStyle.DANGER.lerp(UiStyle.ACCENT, 0.5))
	var acc := 0.0 if m.shots == 0 else 100.0 * m.hits / m.shots
	var lines := [
		Loc.t("Точность пушки: %d%% · пик «оборотов»: +%d%% · сбито с хвоста: %d") % [int(acc), int(round(m.peak_rev * 100.0)), m.run.tail_kills],
		Loc.t("Уведено ракет ловушками: %d · срывов захвата: %d · на волоске: %d") % [int(m.counters.get("intercepted", 0)), int(m.counters.get("locks_broken", 0)), m.run.near_misses],
		Loc.t("Лучшая серия: %d · активностей: %d · проход на форсаже: %d урона") % [m.run.best_streak, m.run.activities_done, m.stat("dealt", "проход на форсаже")],
	]
	y += 12.0
	for l: String in lines:
		if y + 22.0 > r.end.y - 8.0:
			break
		y += _para(Vector2(x, y + 16), l, w, UiStyle.FS_CAPTION, UiStyle.TEXT_2) + 6.0
	_toggle(Rect2(x, r.end.y + 14.0, 300.0, 40.0), Loc.t("◂ СВОДКА УРОНА"), "rtab:0")


## One «label ▬▬▬ value» row; returns the next y.
func _bar_row(pos: Vector2, w: float, label: String, v: int, tot: int, col: Color) -> float:
	var f := ui_font()
	UiStyle.text(ctrl, f, Vector2(pos.x, pos.y + 18), _fit(label, 190.0, UiStyle.FS_BODY), UiStyle.FS_BODY, UiStyle.TEXT)
	var bx := pos.x + 200.0
	var bw := w - 200.0 - 70.0
	ctrl.draw_rect(Rect2(bx, pos.y + 8, bw, 10), Color(1, 1, 1, 0.08))
	ctrl.draw_rect(Rect2(bx, pos.y + 8, bw * (0.0 if tot <= 0 else float(v) / float(tot)), 10), col)
	UiStyle.text(ctrl, UiStyle.head_font(700, 0), Vector2(pos.x, pos.y + 18), _grouped(v), UiStyle.FS_BODY, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	return pos.y + 28.0


## Small outlined switch under the damage panel.
func _toggle(r: Rect2, label: String, action: String) -> void:
	r.size.x = UiStyle.text_w(UiStyle.head_font(700, 3), label, UiStyle.FS_CAPTION) + 36.0
	var hover := r.has_point(ctrl.get_local_mouse_position())
	ctrl.draw_rect(r, Color(UiStyle.ACCENT, 0.12) if hover else Color(UiStyle.PANEL, 0.6))
	ctrl.draw_rect(r, UiStyle.ACCENT if hover else UiStyle.LINE, false, 1.0)
	UiStyle.text(ctrl, UiStyle.head_font(700, 3), Vector2(r.position.x + 16, r.position.y + 26), label, UiStyle.FS_CAPTION, UiStyle.TEXT)
	_buttons.append([r, action])


# ---------- Centre ----------

## Big numbers in an amber frame; returns the bottom y.
func _numbers(m: Main, r: Rect2) -> float:
	var t := int(m.run_time)
	var rows := [[Loc.t("СБИТО"), _grouped(m.run.kills)], [Loc.t("ВРЕМЯ"), "%d:%02d" % [t / 60, t % 60]],
		[Loc.t("УР. ПИЛОТА"), str(m.run.level)], [Loc.t("АСОВ"), str(m.run.bosses_killed)]]
	r.size.y = 36.0 + rows.size() * 56.0
	UiStyle.panel(ctrl, r, UiStyle.ACCENT, UiStyle.PANEL, 18.0)
	var y := r.position.y + 62.0
	for row: Array in rows:
		UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(r.position.x + 28, y), String(row[0]), UiStyle.FS_H3, UiStyle.TEXT)
		UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(r.position.x, y + 4), String(row[1]), 42, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28.0)
		y += 56.0
	return r.end.y


## «Главное за вылет»: what dealt the damage, what hurt, what did not work.
func _takeaways(m: Main, r: Rect2) -> void:
	var x := r.position.x + 4.0
	var y := r.position.y + 22.0
	UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(x, y), Loc.t("ГЛАВНОЕ ЗА ВЫЛЕТ"), UiStyle.FS_BODY, UiStyle.ACCENT_SOFT)
	y += 14.0
	for ins: Array in result_insights(m):
		var h := ui_font().get_multiline_string_size(Loc.out(String(ins[0])), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 18.0, UiStyle.FS_CAPTION).y
		if y + h > r.end.y:
			break
		ctrl.draw_rect(Rect2(x, y + 6, 4, h - 4), ins[1])
		_para(Vector2(x + 14, y + 18), String(ins[0]), r.size.x - 18.0, UiStyle.FS_CAPTION, UiStyle.TEXT_WARM)
		y += h + 10.0


# ---------- Right: build and rewards ----------

## The build as an icon grid: weapons, modules (with levels), wingmen, synergies. Returns
## the bottom y.
func _build(m: Main, r: Rect2) -> float:
	var p := m.player
	var items: Array = []   # [key, family, frame, number]
	for g in p.groups:
		var h := g as Hardpoint
		if not h.is_empty():
			items.append([h.weapon, HudIcons.weapon_family(h.weapon), Cards.EVO_COLOR if h.evo else Cards.RARITY[clampi(h.level - 1, 0, 4)]["color"], h.level])
	for id in Cards.MODULES:
		var lvl := int(p.taken.get(id, 0))
		if lvl <= 0 or id == "repair":
			continue
		var fam := "skill" if id == "skill3" else (String(Prog.MODULE_TAGS[id][0]) if Prog.MODULE_TAGS.has(id) else "armor")
		items.append([p.skill3 if id == "skill3" else id, fam, Cards.RARITY[clampi(lvl - 1, 0, 4)]["color"], lvl])
	for w in p.wingmen:
		if is_instance_valid(w):
			items.append(["wingman", "wing", Prog.TAGS["wing"]["color"], (w as Wingman).lvl])
	for id in p.syn:
		items.append(["synergy", "skill", UiStyle.ACCENT, -1])
	var cols := 6
	var rows := maxi(1, int(ceil(items.size() / float(cols))))
	var gap := (r.size.x - 28.0 - cols * BUILD_TILE) / (cols - 1)
	r.size.y = 28.0 + rows * BUILD_TILE + (rows - 1) * 10.0
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	for i in items.size():
		var it: Array = items[i]
		var tr := Rect2(r.position.x + 14.0 + (i % cols) * (BUILD_TILE + gap), r.position.y + 14.0 + (i / cols) * (BUILD_TILE + 10.0), BUILD_TILE, BUILD_TILE)
		HudIcons.tile(ctrl, tr, String(it[0]), String(it[1]), it[2], int(it[3]), 12.0)
	return r.end.y


## Rewards by line (parts), total, crew experience with its bar and what opened.
func _rewards(m: Main, r: Rect2) -> void:
	var a: Dictionary = m.meta_award
	var lines: Array = []   # [label, value]
	var short: bool = a.is_empty() or a.get("short", false)
	if not short:
		var rk := Campaign.k("reward")
		lines.append([Loc.t("ДОБЫЧА ВЫЛЕТА · %s") % ("100%" if m.state == "evac" else "50%") + ("" if rk <= 1.0 else " · ×" + HudCampaign._k(rk)), int(m.parts_kept)])
		lines.append([Loc.t("ЖАЛОВАНЬЕ ТЕХНИКАМ"), int(a["wage"])])
		if int(a.get("op_parts", 0)) > 0:
			lines.append([Loc.t("ОПЕРАЦИЯ ПРОЙДЕНА ВПЕРВЫЕ"), int(a["op_parts"])])
	var extra: Array = []   # [text, colour]
	if not short:
		if a.has("promote"):
			var pv: Array = a["promote"]
			extra.append([Loc.t("Опыта хватает на ур. %d: «Повысить в звании» в ангаре — %d") % [int(pv[0]), int(pv[1])], UiStyle.ACCENT_SOFT])
		for u in a["unlocked"]:
			extra.append([Loc.t("ОТКРЫТО: ") + String(u), UiStyle.ACCENT_SOFT])
		if String(a.get("tech", "")) != "":
			extra.append([Loc.t("Техник: «%s»") % String(a["tech"]), UiStyle.PARTS])
		if String(a.get("hint_buy", "")) != "":
			extra.append([Loc.t("Можно купить: ") + String(a["hint_buy"]), UiStyle.TEXT_2])
	r.size.y = 48.0 + (60.0 if short else lines.size() * 36.0 + 54.0 + 70.0) + extra.size() * 24.0
	UiStyle.panel(ctrl, r, UiStyle.LINE, UiStyle.PANEL, 18.0)
	var hr := Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 20.0, 42.0)
	ctrl.draw_rect(hr, UiStyle.ACCENT)
	var hf := UiStyle.head_font(700, 4)
	UiStyle.text(ctrl, hf, Vector2(hr.position.x + 20, hr.position.y + 28), "◆ " + Loc.t("НАГРАДА"), UiStyle.FS_LABEL, UiStyle.ON_ACCENT)
	UiStyle.text(ctrl, hf, Vector2(hr.position.x, hr.position.y + 28), Loc.t("ЗАПЧАСТИ"), UiStyle.FS_LABEL, UiStyle.ON_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, hr.size.x - 20.0)
	var x := r.position.x + 20.0
	var w := r.size.x - 40.0
	var y := r.position.y + 48.0
	if short:
		UiStyle.text(ctrl, ui_font(), Vector2(x, y + 34), Loc.t("Слишком короткий вылет — без начисления"), UiStyle.FS_BODY, UiStyle.TEXT_2)
		return
	var lf := UiStyle.head_font(700, 3)
	for l: Array in lines:
		UiStyle.text(ctrl, lf, Vector2(x, y + 26), "◇ " + String(l[0]), UiStyle.FS_LABEL, UiStyle.TEXT)
		UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(x, y + 26), "+%s" % _grouped(int(l[1])), UiStyle.FS_LABEL + 2, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, w)
		ctrl.draw_line(Vector2(x, y + 34), Vector2(x + w, y + 34), UiStyle.LINE, 1.0)
		y += 36.0
	UiStyle.text(ctrl, UiStyle.head_font(800, 3), Vector2(x, y + 36), Loc.t("ИТОГО"), UiStyle.FS_H3 + 2, UiStyle.TEXT)
	UiStyle.text(ctrl, UiStyle.head_font(600, 1), Vector2(x, y + 36), Loc.t("всего %s") % _grouped(int(a["parts_after"])), UiStyle.FS_BODY, UiStyle.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, w - 110.0)
	UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(x, y + 38), "+%s" % _grouped(int(a["parts_add"])), UiStyle.FS_H2 + 2, UiStyle.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 54.0
	# crew experience: the bar fills up to the new value over the first second on screen
	var lv := Profile.crew_lvl(m.cls_id)
	var pr := Profile.crew_progress(m.cls_id)
	var cf := UiStyle.head_font(700, 3)
	UiStyle.text(ctrl, cf, Vector2(x, y + 24), Loc.t("ЭКИПАЖ «%s» · УР. %d") % [String(Profile.cls(m.cls_id)["callsign"]).to_upper(), lv], UiStyle.FS_BODY, UiStyle.TEXT_DIM)
	UiStyle.text(ctrl, cf, Vector2(x, y + 24), Loc.t("+%d ОПЫТА") % int(a["xp_add"]), UiStyle.FS_BODY, UiStyle.OK, HORIZONTAL_ALIGNMENT_RIGHT, w)
	var frac := clampf(float(pr[0]) / maxf(float(pr[1]), 1.0), 0.0, 1.0) if int(pr[1]) > 0 else 1.0
	var k := clampf(m.result_t / 0.8, 0.0, 1.0)
	ctrl.draw_rect(Rect2(x, y + 36, w, 8), Color(1, 1, 1, 0.1))
	ctrl.draw_rect(Rect2(x, y + 36, w * frac * k, 8), UiStyle.OK)
	y += 66.0
	for e: Array in extra:
		UiStyle.text(ctrl, ui_font(), Vector2(x, y + 16), _fit(String(e[0]), w, UiStyle.FS_CAPTION), UiStyle.FS_CAPTION, e[1])
		y += 24.0


# ---------- Bottom ----------

## Key hints on the left, buttons on the right; «Ещё вылет» is the main action.
func _bottom(m: Main, size: Vector2) -> void:
	var y := size.y - 34.0
	var x := 64.0
	x = UiStyle.key_hint(ctrl, Vector2(x, y), key_label("restart"), Loc.t("ЕЩЁ ВЫЛЕТ"))
	x = UiStyle.key_hint(ctrl, Vector2(x, y), key_label("ui_hangar"), Loc.t("АНГАР"))
	x = UiStyle.key_hint(ctrl, Vector2(x, y), key_label("change_class"), Loc.t("САМОЛЁТ"))
	UiStyle.key_hint(ctrl, Vector2(x, y), "1 · 2", Loc.t("УРОН"))
	var bh := 52.0
	var by := size.y - 78.0
	var rx := size.x - 64.0
	var specs := [["◆ " + Loc.t("ЕЩЁ ВЫЛЕТ") + " ›", "restart", true], [Loc.t("АНГАР"), "to_hangar", false],
		[Loc.t("СМЕНИТЬ САМОЛЁТ"), "change_class", false], [Loc.t("В МЕНЮ"), "to_menu", false]]
	var f := UiStyle.head_font(700, 4)
	for s: Array in specs:
		var bw := UiStyle.text_w(f, String(s[0]), UiStyle.FS_LABEL) + 56.0
		rx -= bw
		var r := Rect2(rx, by, bw, bh)
		var hover := r.has_point(ctrl.get_local_mouse_position())
		var main: bool = s[2]
		ctrl.draw_rect(r, Color(UiStyle.ACCENT, 0.18 if hover else 0.12) if main else (Color(1, 1, 1, 0.08) if hover else UiStyle.PANEL))
		ctrl.draw_rect(r, UiStyle.ACCENT if main or hover else UiStyle.LINE, false, 2.0 if main else 1.0)
		UiStyle.text(ctrl, f, Vector2(r.position.x, r.position.y + 34), String(s[0]), UiStyle.FS_LABEL, UiStyle.ACCENT if main else UiStyle.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_buttons.append([r, String(s[1])])
		rx -= 14.0
	if Main.REPORT_URL != "":
		if m.report_sent:
			UiStyle.text(ctrl, ui_font(), Vector2(rx - 300.0, by + 33), "✓ " + Loc.t("Отчёт принят — спасибо!"), UiStyle.FS_BODY, UiStyle.OK, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		else:
			_report_button(Rect2(rx - 300.0, by, 300.0, bh), m.result_t)


## Report button stands out from the rest without popups or sound (Kanta, 18.10): amber
## fill, a caption above it and a soft breathing frame for the first seconds on screen.
func _report_button(r: Rect2, shown_t: float) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	ctrl.draw_rect(r, UiStyle.ACCENT.lightened(0.15) if hover else UiStyle.ACCENT)
	if shown_t < 6.0:
		var k := 0.5 + 0.5 * sin(shown_t * 3.0)
		ctrl.draw_rect(r.grow(4.0 + 4.0 * k), Color(UiStyle.ACCENT, 0.55 * (1.0 - shown_t / 6.0)), false, 2.0)
	UiStyle.text(ctrl, UiStyle.head_font(800, 4), Vector2(r.position.x, r.position.y + 34), Loc.t("ОТПРАВИТЬ ОТЧЁТ"), UiStyle.FS_LABEL, UiStyle.ON_ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UiStyle.text(ctrl, ui_font(), Vector2(r.position.x, r.position.y - 10), Loc.t("1 минута — очень поможет игре"), UiStyle.FS_CAPTION, UiStyle.ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_buttons.append([r, "report_open"])


# ---------- Numbers ----------

## 581 300 → «581 тыс.», 1 900 000 → «1,9 млн»; small values as they are, grouped.
func _short(v: float) -> String:
	if v >= 1000000.0:
		return Loc.t("%s млн") % _dec(v / 1000000.0)
	if v >= 10000.0:
		return Loc.t("%s тыс.") % _dec(v / 1000.0)
	return _grouped(int(v))


## One decimal for values under 100 («45,3»), none above; decimal comma in Russian.
func _dec(v: float) -> String:
	var s := ("%.1f" % v) if v < 100.0 else str(int(round(v)))
	return s.replace(".", ",") if TranslationServer.get_locale().begins_with("ru") else s


## Thousands separated by a thin space: 12 345.
func _grouped(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## Campaign operation result: [text, colour] or [] when the sortie was not an operation run.
static func op_line(m: Main) -> Array:
	var o: Dictionary = m.op_result
	if o.is_empty():
		return []
	if o["first"]:
		return [Loc.t("Операция %d «%s» пройдена! Открыто: %s") % [int(o["n"]), Loc.t(o["title"]), ", ".join(PackedStringArray(o["opens"]))], UiStyle.ACCENT_SOFT]
	if o["done"]:
		return [Loc.t("Операция %d «%s» выполнена (уже была пройдена)") % [int(o["n"]), Loc.t(o["title"])], UiStyle.OK]
	return [Loc.t("Операция %d «%s» не засчитана: не удалось %s") % [int(o["n"]), Loc.t(o["title"]),
		", ".join(PackedStringArray(o["miss"])) if not (o["miss"] as Array).is_empty() else Loc.t("вернуться на базу")], UiStyle.TEXT_2]


# ---------- Demo end, takeaways, source names ----------

## M-07: «Конец демо» поверх итогов после первого прохода «Сухого русла» — что дальше в полной игре и кнопка
## списка желаемого. Итоги вылета под ним не теряются: «К итогам вылета» (Enter / Esc) закрывает окно.
const DEMO_NEXT := [
	["Операция 3 «Крепости»", "«Барон» ищет вас лично: дуэль с асом-соперником и снова «Крепость»."],
	["Самолёты ур. 2", "Новая модель у каждого класса: тяжёлый подвес, прочность и манёвр выше."],
	["Экспериментальное оружие", "Рельсотрон, ЭМИ-заряд, лазер «Луч» и плазменная бомба."],
	["Архипелаг Таласора", "Второй район: пролив, острова, морские конвои и крейсер «Сторож»."],
	["Полная прокачка", "Узлы самолёта до ур. 5, три ступени веток оружия, экипаж до ур. 20."],
]


func _demo_end(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.03, 0.9))
	var r := Rect2(size.x / 2.0 - 640, 180, 1280, 660)
	_panel(r, false, Menu.C_AMBER)
	_ctext(r.position.y + 80, "КОНЕЦ ДЕМО", 54, Menu.C_AMBER)
	_ctext(r.position.y + 126, "«Сухое русло» пройдено, «Крепость» сбита. Спасибо, что сыграли!", 24, Color.WHITE)
	_ctext(r.position.y + 162, "Обе операции демо можно повторять любым классом. В полной игре дальше:", 19, Color(0.75, 0.8, 0.9))
	var y := r.position.y + 220.0
	for row in DEMO_NEXT:
		_text(Vector2(r.position.x + 90, y), "• " + Loc.t(String(row[0])), 22, Color(1.0, 0.85, 0.4))
		_text(Vector2(r.position.x + 470, y), Loc.t(String(row[1])), 18, Color(0.85, 0.88, 0.95))
		y += 56.0
	var bw := 520.0
	var by := r.end.y - 130.0
	_button(Rect2(size.x / 2.0 - bw - 20, by, bw, 70), "В СПИСОК ЖЕЛАЕМОГО", "wishlist", 26)
	_button(Rect2(size.x / 2.0 + 20, by, bw, 70), "К итогам вылета (Enter)", "demo_end_close", 22)
	_ctext(by + 104, "Прогресс демо переносится в полную игру", 17, Color(0.6, 1.0, 0.7))


## Выводы по вылету: что дало урон, откуда прилетало, что не сработало. [текст, цвет]
static func result_insights(m: Main) -> Array:
	var out: Array = []
	var dealt: Dictionary = m.stats["dealt"]
	var dt := float(maxi(m.total("dealt"), 1))
	if not dealt.is_empty():
		var keys := dealt.keys()
		keys.sort_custom(func(a, b): return float(dealt[a]) > float(dealt[b]))
		var k0: String = keys[0]
		var share := int(round(100.0 * float(dealt[k0]) / dt))
		var s := Loc.t("Главный урон — %s: %d%% всего урона") % [SRC_NAMES.get(k0, k0), share]
		if keys.size() > 1:
			s += Loc.t(", дальше %s — %d%%") % [SRC_NAMES.get(keys[1], keys[1]), int(round(100.0 * float(dealt[keys[1]]) / dt))]
		out.append([s + ".", Color(0.45, 0.9, 0.55)])
		if share >= 60:
			out.append(["Почти всё держится на одном оружии. Если его урон просядет, вылет тоже просядет: возьмите второе оружие или связку к нему.", Color(1.0, 0.85, 0.4)])
	var tk := m.total("taken")
	if tk > 0:
		var by: Dictionary = m.stats["taken_by"]
		var kind: Dictionary = m.stats["taken"]
		var bk := ""
		for k in by.keys():
			if bk == "" or float(by[k]) > float(by[bk]):
				bk = k
		var kk := ""
		for k in kind.keys():
			if kk == "" or float(kind[k]) > float(kind[kk]):
				kk = k
		if bk != "":
			out.append([Loc.t("Больше всего урона вы получили от врагов «%s» (%d%%), в основном — %s.") % [bk, int(round(100.0 * float(by.get(bk, 0)) / tk)), kk], Color(1.0, 0.55, 0.45)])
		if kk == "ракеты" and int(m.counters.get("intercepted", 0)) == 0:
			out.append(["Ловушки не увели ни одной ракеты. Уклонение (Space) и боевой разворот сбивают захват — жмите, когда слышите сигнал пуска.", Color(1.0, 0.75, 0.4)])
		elif kk == "таран":
			out.append(["Много урона от столкновений: не влетайте в строй врагов, уходите уклонением (Space) или берите броню; у «Грача» под «Бронещитом» врезавшиеся враги разбиваются сами.", Color(1.0, 0.75, 0.4)])
	if m.player.syn.is_empty():
		out.append(["Ни одной связки за вылет. Слева в бою полоса «К связке» показывает, каких карточек не хватает.", Color(1.0, 0.85, 0.4)])
	else:
		var first := 1e9
		for id in m.player.syn:
			first = minf(first, float(m.player.syn[id]))
		out.append([Loc.t("Связок: %d, первая — на %d:%02d.") % [m.player.syn.size(), int(first) / 60, int(first) % 60], Menu.C_AMBER])
	if m.shots > 50 and m.hits * 100 < m.shots * 30:
		out.append([Loc.t("Пушка попадала только в %d%% выстрелов: держите нос на цели или включите ручной огонь (Q) — он сильнее.") % int(100.0 * m.hits / m.shots), Color(0.75, 0.85, 1.0)])
	if m.run.bosses_killed == 0 and m.run_time > 200.0:
		out.append(["Ни одного сбитого аса — без него не открываются ворота эвакуации.", Color(1.0, 0.55, 0.45)])
	return out.slice(0, 6)


## U-01: внутренние имена источников урона (их пишет лог l5) → понятные игроку
const SRC_NAMES := {
	"курсовое (авто)": "пушка (сама)", "курсовое (ручн.)": "пушка (ручной огонь)",
	"ракеты В-В": "наводящиеся ракеты", "НАР": "залп ракет", "разделяющаяся БЧ": "разделяющиеся ракеты",
	"ЭМИ": "ЭМИ-заряд", "лазер": "лазер «Луч»", "плазма": "плазменная бомба",
}


## Ключи словаря по убыванию значения, не больше n (нулевые — нет)
static func _top_keys(d: Dictionary, n: int) -> Array:
	var keys := d.keys().filter(func(k) -> bool: return float(d[k]) >= 0.5)
	keys.sort_custom(func(a, b) -> bool: return float(d[a]) > float(d[b]))
	return keys.slice(0, n)
