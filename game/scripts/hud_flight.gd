class_name HudFlight
extends HudKit
## Интерфейс в полёте: опыт, прочность, навыки, подвесы, время и асы, указатели угроз,
## эвакуация, активности, радио, полоса подвесов, строка курса.


var _mini: HudMinimap = null


func draw(m: Main, size: Vector2, dmg_flash: float) -> void:
	var p := m.player
	if dmg_flash > 0.0:
		ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0, 0, dmg_flash * 0.5))

	# Опыт и уровень — полоса во всю ширину сверху
	ctrl.draw_rect(Rect2(0, 0, size.x, 10), Color(0, 0, 0, 0.6))
	ctrl.draw_rect(Rect2(0, 0, size.x * clampf(m.xp / m.xp_need(), 0.0, 1.0), 10), Color(0.4, 1.0, 0.55))

	var hide := Settings.hide_hud and m.state == "playing"
	if is_instance_valid(p) and not hide:
		_left_panel(m, p)
		_flight_panel(m, p, size)
		if m.state == "playing":
			_activity_panel(m, p, size)
	_right_panel(m, size)
	if is_instance_valid(p) and m.state == "playing":
		_loadout_strip(p, size)
		if not hide:
			if _mini == null:
				_mini = HudMinimap.new(ctrl)
			_mini.draw(m, size)
	_fx_texts(m)
	_boss_bars(m, size)
	_threat_markers(size)
	if m.state == "playing":
		_evac_marker(m, size)

	if Hints.t > 0.0 and Hints.text != "" and m.state == "playing":
		_hint_box(Hints.text, size, clampf(Hints.t * 2.0, 0.0, 1.0))
	if m.banner_t > 0.0 and m.state == "playing":
		var a := clampf(m.banner_t, 0.0, 1.0)
		# тёмная плашка под баннером — на светлом песке жёлтый текст терялся
		var bw := ui_font().get_string_size(m.banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 40.0
		ctrl.draw_rect(Rect2((size.x - bw) / 2.0, 138, bw, 44), Color(0.02, 0.025, 0.03, 0.6 * a))
		_ctext(170, m.banner, 30, Color(1.0, 0.85, 0.5, a))

	if m.run_time > 180.0 and m.state == "playing":
		return
	var hint := "Мышь — куда лететь · Space — уклонение · Shift — форсаж · E — навык · Tab — пауза" + (" · F5/F6/F7 — отладка" if Main.DEBUG else "")
	# свежий взгляд: без плашки строка клавиш терялась на песке
	var hw := ui_font().get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 32.0
	ctrl.draw_rect(Rect2((size.x - hw) / 2.0, size.y - 38.0, hw, 28.0), Color(0.02, 0.025, 0.03, 0.62))
	_text(Vector2(0, size.y - 18), hint, 16, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, size.x)


## U-02: подсказка новичку — рамка над нижней строкой клавиш
func _hint_box(s: String, size: Vector2, a: float) -> void:
	var w := minf(1100.0, size.x - 80.0)
	# высота по тексту: длинная подсказка в три строки не вылезает из рамки
	var th := ui_font().get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, w - 32.0, 18).y
	var bh := maxf(86.0, th + 44.0)
	var r := Rect2((size.x - w) / 2.0, size.y - 134.0 - bh, w, bh)
	ctrl.draw_rect(r, Color(0.04, 0.05, 0.06, 0.82 * a))
	ctrl.draw_rect(r, Color(1.0, 0.85, 0.4, 0.8 * a), false, 2.0)
	_text(Vector2(r.position.x + 16, r.position.y + 26), "ПОДСКАЗКА", 13, Color(1.0, 0.85, 0.4, a))
	_para(Vector2(r.position.x + 16, r.position.y + 50), s, w - 32.0, 18, Color(1, 1, 1, a))


## Читаемость HUD (17.10): навык — плашка с клавишей; готов — зелёная рамка, действует — янтарная, перезарядка — серая с секундами
func _skill(pos: Vector2, w: float, title: String, key: String, cd: float, active: float) -> void:
	var r := Rect2(pos, Vector2(w, 30))
	var c := Color(0.55, 1.0, 0.65)
	var state := "готов"
	if active > 0.0:
		c = Color(1.0, 0.82, 0.35)
		state = "%.1f с" % active
	elif cd > 0.0:
		c = Color(0.62, 0.65, 0.72)
		state = "%d с" % int(ceil(cd))
	ctrl.draw_rect(r, Color(0.03, 0.04, 0.05, 0.72))
	ctrl.draw_rect(r, Color(c.r, c.g, c.b, 0.9 if cd <= 0.0 else 0.35), false, 2.0 if cd <= 0.0 else 1.0)
	# клавиша — светлый квадратик слева
	var kw := ui_font().get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0
	ctrl.draw_rect(Rect2(pos.x + 4, pos.y + 4, kw, 22), Color(c.r, c.g, c.b, 0.22))
	_text(Vector2(pos.x + 10, pos.y + 20), key, 14, c.lightened(0.3))
	_text(Vector2(pos.x + kw + 10, pos.y + 21), title, 16, Color.WHITE if cd <= 0.0 else Color(0.78, 0.8, 0.86), HORIZONTAL_ALIGNMENT_LEFT, w - kw - 58.0)
	_text(Vector2(pos.x, pos.y + 21), state + " ", 15, c, HORIZONTAL_ALIGNMENT_RIGHT, w - 4.0)


## Тёмная подложка панели HUD: текст читается и на светлой земле
func _hud_back(r: Rect2) -> void:
	ctrl.draw_rect(r, Color(0.02, 0.025, 0.03, 0.58))


func _left_panel(m: Main, p: Player) -> void:
	var x := 20.0
	var pw := 460.0
	var y := 18.0
	var h := 150.0 + (24.0 if p.wingmen.size() > 0 else 0.0) + (30.0 if not p.syn.is_empty() or p.has_course() else 0.0) + (80.0 if p.has_course() else 0.0)
	_hud_back(Rect2(x - 8, y - 6, pw + 16, h))
	# прочность — крупная полоса; меньше трети — красная
	var hk := clampf(p.hp / p.max_hp, 0.0, 1.0)
	var hc := Color(0.4, 0.9, 0.5) if hk > 0.33 else Color(1.0, 0.35, 0.3)
	ctrl.draw_rect(Rect2(x, y, 300, 24), Color(0, 0, 0, 0.6))
	ctrl.draw_rect(Rect2(x, y, 300.0 * hk, 24), hc)
	_text(Vector2(x + 8, y + 18), "Прочность %d / %d" % [int(p.hp), int(p.max_hp)], 17, Color.WHITE)
	_text(Vector2(x + 312, y + 19), "Ур. %d" % m.level, 20, Color(0.6, 1.0, 0.7))
	y += 30.0
	# 3.5: топливо — полоска под прочностью и остаток в минутах
	var fu := Fuel.current()
	if fu != null:
		var fc := Color(1.0, 0.35, 0.3) if fu.frac() < 0.1 else (Color(1.0, 0.8, 0.35) if fu.frac() <= Fuel.CALL_AT else Color(0.95, 0.85, 0.55))
		ctrl.draw_rect(Rect2(x, y + 2, 300, 10), Color(0, 0, 0, 0.6))
		ctrl.draw_rect(Rect2(x, y + 2, 300.0 * fu.frac(), 10), fc)
		var fs := "БАК ПУСТ" if fu.empty() else "Топливо %d:%02d" % [int(fu.left) / 60, int(fu.left) % 60]
		_text(Vector2(x + 312, y + 13), fs, 15, fc)
	y += 22.0
	# навыки — плашки в две колонки
	var cw := (pw - 8.0) / 2.0
	var sk: Array = []
	sk.append(["Уклонение" if p.has_roll() else "Ловушки", "Space", p.roll_cd, p.roll_t if p.has_roll() else p.salvo_t])
	sk.append(["Форсаж", "Shift", p.ab_cd, p.ab_t])
	sk.append(["Нырок", "V", p.dive_cd, p.dive_t])
	var s3: Dictionary = p.s3_def()
	sk.append(["%s %s" % [s3["title"], Prog.ROMAN[p.s3_lvl()]], "E", p.s3_cd, p.s3_active()])
	if p.skill_b != "":
		sk.append([PlaneClasses.SKILL3[p.skill_b]["title"], "F", p.sb_cd, p.s3_active(p.skill_b)])
	for i in sk.size():
		var it: Array = sk[i]
		_skill(Vector2(x + (i % 2) * (cw + 8.0), y + (i / 2) * 34.0), cw, it[0], it[1], it[2], it[3])
	y += ceil(sk.size() / 2.0) * 34.0
	# правка 14: что делает навык E — коротко, пока он готов
	var note := String(s3.get("hud", ""))
	if p.s3_cd <= 0.0 and p.s3_active() <= 0.0 and note != "":
		_text(Vector2(x, y + 12), "E — " + note, 14, Color(0.7, 0.8, 0.9))
	if p.manual_mode:
		_text(Vector2(x, y + 12), "Пушка: ручной +%d%% [Q]" % int(round(p.manual_bonus * 100.0)), 14, Color(1.0, 0.82, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, pw)
	y += 20.0
	if p.wingmen.size() > 0:
		var wl := PackedStringArray()
		for w in p.wingmen:
			if not is_instance_valid(w):
				continue
			var wm: Wingman = w
			var st: String = "%s %d" % [Prog.WING_TYPES[wm.type]["short"], wm.lvl]
			if wm.temp:
				st += " (%d с)" % int(ceil(wm.life))
			elif not wm.alive():
				st += " (вернётся %d с)" % int(ceil(wm.dead_t))
			wl.append(st)
		_text(Vector2(x, y + 14), "Звено: %s · цель: %s [G]" % [", ".join(wl), Settings.WING_PRIO[Settings.wing_prio]], 16, Color(0.82, 0.78, 1.0))
		y += 24.0
	# подвесы — только полосой внизу экрана; здесь связки и специализация
	if not p.syn.is_empty() or p.has_course():
		_course_bar(p, Vector2(x, y + 2))
	if m.god_mode:
		_text(Vector2(x, 18 + h + 14), "ОТЛАДКА: неуязвимость (F7)", 16, Color(1, 0.5, 0.5))
	if int(Tuning.g("scheme")) == 2 and m.state == "playing":
		var mp := ctrl.get_local_mouse_position()
		ctrl.draw_arc(mp, 12.0, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 2.0)
		ctrl.draw_circle(mp, 2.0, Color(1, 1, 1, 0.9))


func _right_panel(m: Main, size: Vector2) -> void:
	var t := int(m.run_time)
	var w := size.x - 28.0
	var rows := 4 + (1 if m.run_time > 900.0 else 0) + (1 if (Campaign.op()["need"] as Array).has("baron") else 0)
	_hud_back(Rect2(size.x - 320, 12, 308, 64 + rows * 26))
	_text(Vector2(0, 50), "%02d:%02d" % [t / 60, t % 60], 34, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w)
	# U-02: цель вылета под таймером (U-05: словами операции кампании)
	var left := maxi(0, 900 - t)
	var goal := ""
	if Campaign.goal_done(m.run_time, m.op_flags):
		goal = "✓ задание выполнено — к эвакуации"
	elif left > 0:
		goal = "%s %d:%02d" % [Campaign.op()["hud"], left / 60, left % 60]
	else:
		goal = "сбейте " + ("«Барона»" if not m.op_flags.get("baron", false) and (Campaign.op()["need"] as Array).has("baron") else "«Крепость»")
	var y := 80.0
	_text(Vector2(0, y), goal, 17, Color(0.6, 1.0, 0.7) if goal.begins_with("✓") else Color(0.9, 0.92, 0.98), HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 26.0
	if (Campaign.op()["need"] as Array).has("baron"):
		_text(Vector2(0, y), "«Барон»: %s" % ("сбит ✓" if m.op_flags.get("baron", false) else "не сбит"), 17, Color(0.6, 1.0, 0.7) if m.op_flags.get("baron", false) else Color(1.0, 0.75, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, w)
		y += 26.0
	var every := Tuning.g("boss_every")
	var next := (floorf(m.run_time / every) + 1.0) * every - m.run_time
	if m.boss_alive():
		_text(Vector2(0, y), "Ас в бою!", 19, Color(1.0, 0.5, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, w)
	else:
		_text(Vector2(0, y), "Ас через %d:%02d" % [int(next) / 60, int(next) % 60], 18, Color(0.9, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 26.0
	_text(Vector2(0, y), "Сбито %d" % m.kills, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 26.0
	_text(Vector2(0, y), "Запчасти %d" % int(m.parts), 18, Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 26.0
	if m.run_time > 900.0:
		_text(Vector2(0, y), "Задержались: добыча ×%.1f" % m.continue_mult(), 18, Color(1.0, 0.8, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, w)
	# FPS — мелко в углу, не в панели
	_text(Vector2(0, size.y - 6), "FPS %d" % Engine.get_frames_per_second(), 12, Color(0.7, 0.7, 0.7, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8.0)


func _boss_bars(m: Main, size: Vector2) -> void:
	var y := 30.0
	for n in m.get_tree().get_nodes_in_group("enemies"):
		var b := n as Boss
		if b == null:
			continue
		var w := 560.0
		var x := (size.x - w) / 2.0
		if b is Fortress:
			y = _fortress_bar(b as Fortress, x, y, w)
			continue
		ctrl.draw_rect(Rect2(x, y - 16, w, 22), Color(0.02, 0.025, 0.03, 0.55))
		_text(Vector2(x, y + 2), b.title, 18, Color(1, 0.9, 0.78), HORIZONTAL_ALIGNMENT_CENTER, w)
		ctrl.draw_rect(Rect2(x, y + 10, w, 14), Color(0, 0, 0, 0.6))
		ctrl.draw_rect(Rect2(x, y + 10, w * b.hp / b.max_hp, 14), Color(1.0, 0.35, 0.3))
		if b.shield > 0.0:
			ctrl.draw_rect(Rect2(x, y + 25, w * b.shield / b.shield_max, 5), Color(0.5, 0.8, 1.0))
		y += 48.0


## Правка 3.5-s4: полоса «Крепости» — общая прочность с отметками приёмов (66% и 33%),
## под ней — значки точек: 4 турели и 2 двигателя, сбитые перечёркнуты
func _fortress_bar(f: Fortress, x: float, y: float, w: float) -> float:
	ctrl.draw_rect(Rect2(x, y - 16, w, 22), Color(0.02, 0.025, 0.03, 0.55))
	_text(Vector2(x, y + 2), f.title, 18, Color(1, 0.9, 0.78), HORIZONTAL_ALIGNMENT_CENTER, w)
	var fr := f.total_frac()
	ctrl.draw_rect(Rect2(x, y + 10, w, 16), Color(0, 0, 0, 0.6))
	ctrl.draw_rect(Rect2(x, y + 10, w * fr, 16), Color(1.0, 0.35, 0.3))
	for th in [0.66, 0.33]:
		var tx: float = x + w * th
		ctrl.draw_line(Vector2(tx, y + 6), Vector2(tx, y + 30), Color(1.0, 0.9, 0.5, 0.9), 2.0)
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


func _evac_marker(m: Main, size: Vector2) -> void:
	if not is_instance_valid(m.evac) or not is_instance_valid(m.player):
		return
	var xf := m.get_viewport().get_canvas_transform()
	var rect := Rect2(Vector2.ZERO, size).grow(-60.0)
	var sp := _ws(xf, m.evac.target_pos())
	var d := int(m.player.global_position.distance_to(m.evac.target_pos()))
	_edge_arrow(sp, rect, size, Color(0.4, 1.0, 0.5), 1.8, "эвакуация %d м" % (d / 10))
	_ctext(246, "ЭВАКУАЦИЯ: ворота %d / %d · %d м · окно %d с" % [m.evac.passed + 1, EvacZone.GATES, d / 10, int(ceil(m.evac.time_left))], 22, Color(0.6, 1.0, 0.7))


## Правка 28 (тест 3.5-s4): стрелка с тёмной обводкой и подписью — видна и на жёлтой земле.
## Отзыв 3.5-s7: стрелки заданий, ворот, заправщика и аса — не у края, а на кольце вокруг центра, где их видно.
func _edge_arrow(sp: Vector2, rect: Rect2, size: Vector2, col: Color, scale := 1.0, label := "") -> void:
	if rect.has_point(sp):
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
		var tw := ui_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(lp.x - tw / 2.0 - 6.0, lp.y - 11.0, tw + 12.0, 22.0)
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
		_text(Vector2(x, y - 8), "Газ [W/S]: %d%%%s" % [int(round(p.throttle * 100.0)), "  ФОРСАЖ" if p.ab_t > 0.0 else ""], 17, Color(0.85, 0.9, 1.0))
		ctrl.draw_rect(Rect2(x, y, w, 10), Color(1, 1, 1, 0.08))
		ctrl.draw_rect(Rect2(x, y, w * (p.throttle - lo) / (hi - lo), 10), Color(0.55, 0.8, 1.0) if p.throttle <= 1.0 else Color(1.0, 0.7, 0.35))
		var mid := x + w * (1.0 - lo) / (hi - lo)
		ctrl.draw_line(Vector2(mid, y - 3), Vector2(mid, y + 13), Color.WHITE, 2.0)
	if p.combat_t > 0.0:
		# U-02: боевой режим после разворота — полоска под самолётом
		_ctext(size.y / 2.0 + 96.0, "БОЕВОЙ РЕЖИМ: пушка ×2 · %.1f с" % p.combat_t, 20, Color(0.6, 0.9, 1.0))
	if p.on_tail():
		_ctext(size.y / 2.0 + 120.0, "НА ХВОСТЕ: пушка +50%", 22, Color(1.0, 0.9, 0.4))
	if m.streak >= 3:
		var a := clampf(m.streak_t, 0.0, 1.0)
		var stt := "Серия ×%d · опыт ×%.2f" % [m.streak, m.streak_mult()]
		var stw := ui_font().get_string_size(stt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0
		ctrl.draw_rect(Rect2(size.x - 16.0 - stw, 246.0, stw, 30.0), Color(0.02, 0.025, 0.03, 0.55 * a))
		_text(Vector2(0, 268), stt, 20, Color(1.0, 0.75, 0.4, a), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 28.0)


## Правка 28: цвета активностей — без жёлтого, он теряется на песке Нагорья
const RING_X := 0.30   # отзыв 3.5-s7: кольцо стрелок заданий — доля ширины и высоты экрана от центра
const RING_Y := 0.32
const C_AA := Color(0.35, 0.85, 1.0)
const C_CONVOY := Color(1.0, 0.5, 0.25)
const C_TRANSPORT := Color(1.0, 0.55, 0.95)


## Активности: указатели на позицию ПВО и аса-соперника, радиопереговоры, «ХВОСТ!»
func _activity_panel(m: Main, p: Player, size: Vector2) -> void:
	var xf := m.get_viewport().get_canvas_transform()
	var rect := Rect2(Vector2.ZERO, size).grow(-60.0)
	var node: Node = m.spawner.activity_node if m.spawner != null else null
	if is_instance_valid(node):
		# свежий взгляд: задача активности на песке не читалась — тёмная плашка
		ctrl.draw_rect(Rect2((size.x - 980.0) / 2.0, 250.0, 980.0, 62.0), Color(0.02, 0.025, 0.03, 0.55))
		if node is AASite:
			var site := node as AASite
			var d := int(p.global_position.distance_to(site.global_position))
			_edge_arrow(_ws(xf, site.global_position), rect, size, C_AA, 1.8, "ПВО %d м" % (d / 10))
			var s: String
			if site.failed:
				s = "Позиция ПВО устояла · бункер: %d%%" % int(ceil(site.bunker_frac() * 100.0))
			elif site.active:
				s = "ПОЗИЦИЯ ПВО: %d с · уничтожьте бункер: %d%%" % [int(ceil(site.timer)), int(ceil(site.bunker_frac() * 100.0))]
			else:
				s = "Позиция ПВО: %d м — подлетите, чтобы начать" % (d / 10)
			_ctext(276, s, 22, Color(1.0, 0.85, 0.4))
			if not site.failed:
				_ctext(302, "Награда: выбор из редких карточек + 40 запчастей", 17, Color(0.85, 0.75, 1.0))
		elif node is Convoy:
			var cv := node as Convoy
			var sea := Biome.sea()
			var dm := int(p.global_position.distance_to(cv.global_position)) / 10
			_edge_arrow(_ws(xf, cv.global_position), rect, size, C_CONVOY, 1.8, ("караван %d м" if sea else "колонна %d м") % dm)
			var cs: String
			if cv.alarm:
				cs = ("КАРАВАН: до гавани %d с · сухогрузов: %d из %d" if sea else "КОЛОННА: до укрытия %d с · грузовиков: %d из %d") % [int(ceil(maxf(cv.timer, 0.0))), cv.trucks_left(), cv.trucks_total]
			else:
				cs = ("Караван снабжения: %d м — подлетите и потопите сухогрузы" if sea else "Колонна снабжения: %d м — подлетите и сожгите грузовики") % dm
			_ctext(276, cs, 22, Color(1.0, 0.78, 0.45))
			_ctext(302, "Подбейте головное судно — караван встанет · награда: груз с каждого сухогруза" if sea else "Подбейте головную машину — колонна встанет · награда: груз с каждого грузовика", 17, Color(0.85, 0.75, 1.0))
		elif node is Transport:
			var tr := node as Transport
			_edge_arrow(_ws(xf, tr.global_position), rect, size, C_TRANSPORT, 1.8, "транспортник %d м" % (int(p.global_position.distance_to(tr.global_position)) / 10))
			_ctext(276, "ОХОТА: транспортник уйдёт через %d с · прочность %d%%" % [int(ceil(maxf(tr.life, 0.0))), int(ceil(tr.hp / tr.max_hp * 100.0))], 22, Color(1.0, 0.75, 0.45))
			_ctext(302, "Награда: груз — запчасти и ремкомплекты", 17, Color(0.85, 0.75, 1.0))
		elif node is RivalAce:
			var ace := node as RivalAce
			_edge_arrow(_ws(xf, ace.global_position), rect, size, Color(1.0, 0.3, 0.35), 1.8, "ас %d м" % (int(p.global_position.distance_to(ace.global_position)) / 10))
			_ctext(276, "ДОГФАЙТ: ас «%s» · уйдёт через %d с" % [ace.callsign, int(ceil(ace.life))], 22, Color(1.0, 0.6, 0.6))
			_ctext(302, "Награда: выбор из редких карточек", 17, Color(0.85, 0.75, 1.0))
			if ace.threatening() and int(Time.get_ticks_msec() / 200) % 2 == 0:
				_ctext(size.y / 2.0 - 110.0, "ХВОСТ! Сбрось газ (S) или манёвр", 30, Color(1.0, 0.3, 0.25))
	# 3.5: свой заправщик
	var tk: Tanker = m.spawner.fuel.tanker if m.spawner != null and m.spawner.fuel != null else null
	if is_instance_valid(tk) and tk.alive() and not tk.leaving:
		_edge_arrow(_ws(xf, tk.global_position), rect, size, Color(0.45, 1.0, 0.55), 1.8, "заправщик %d м" % (int(p.global_position.distance_to(tk.global_position)) / 10))
		var ts := "СТЫКОВКА — ЗАПРАВКА ИДЁТ" if tk.filling else ("ШТАНГА ВЫДВИГАЕТСЯ — держитесь ровно" if tk.in_cone else "ЗАПРАВЩИК: зайдите ему в хвост")
		_ctext(328, "%s · уйдёт через %d с · прочность %d%%" % [ts, int(ceil(tk.life)), int(ceil(tk.hp / tk.max_hp * 100.0))], 20, Color(0.55, 1.0, 0.65))
	if m.radio_t > 0.0:
		_radio_box(m, size)


## Правка 20 (тест 3.5-s4): радиоэфир — справа внизу, значок рации, позывной, полупрозрачная плашка
func _radio_box(m: Main, size: Vector2) -> void:
	var a := clampf(m.radio_t, 0.0, 1.0)
	var w := 470.0
	var lines := ui_font().get_multiline_string_size(m.radio_text, HORIZONTAL_ALIGNMENT_LEFT, w - 92.0, 17).y
	var h := maxf(70.0, 40.0 + lines)
	var r := Rect2(size.x - w - 20.0, size.y - h - 40.0, w, h)
	var col := Color(1.0, 0.5, 0.45) if m.radio_enemy else Color(0.55, 0.95, 0.7)
	ctrl.draw_rect(r, Color(0.03, 0.04, 0.05, 0.72 * a))
	ctrl.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(col.r, col.g, col.b, a))
	# значок рации: корпус, антенна и волны эфира (мигают, пока сообщение свежее)
	var ic := r.position + Vector2(38, 36)
	ctrl.draw_rect(Rect2(ic.x - 12, ic.y - 8, 24, 30), Color(col.r, col.g, col.b, 0.85 * a))
	ctrl.draw_rect(Rect2(ic.x - 7, ic.y - 3, 14, 8), Color(0.03, 0.04, 0.05, a))
	ctrl.draw_line(Vector2(ic.x + 7, ic.y - 8), Vector2(ic.x + 7, ic.y - 22), Color(col.r, col.g, col.b, a), 2.0)
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	for i in 2:
		ctrl.draw_arc(Vector2(ic.x + 7, ic.y - 22), 6.0 + i * 6.0, -PI * 0.85, -PI * 0.15, 8, Color(col.r, col.g, col.b, a * blink * (1.0 - i * 0.3)), 1.5)
	_text(Vector2(r.position.x + 72, r.position.y + 22), "РАДИОЭФИР · «%s»" % m.radio_from, 14, Color(col.r, col.g, col.b, a))
	_para(Vector2(r.position.x + 72, r.position.y + 44), m.radio_text, w - 92.0, 17, Color(1, 1, 1, a))


## 2.8: полоса подвесов внизу экрана — картинка оружия, уровень, перезарядка, связки
func _loadout_strip(p: Player, size: Vector2) -> void:
	var items: Array = []
	for g in p.groups:
		if not g.is_empty():
			items.append(g)
	if items.is_empty():
		return
	var cw := 212.0
	var total := cw * items.size() + 12.0 * (items.size() - 1)
	var x := (size.x - total) / 2.0
	var y := size.y - 118.0
	for g in items:
		var hp: Hardpoint = g
		var r := Rect2(x, y, cw, 78)
		_panel(r, false)
		var t := PlaneArt.weapon_tex(hp.weapon)
		if t != null:
			var k := 60.0 / t.get_height()
			ctrl.draw_set_transform(Vector2(x + 26, y + 39), 0.0, Vector2(k, k))
			ctrl.draw_texture(t, -t.get_size() / 2.0)
			ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:   # U-08: у экспериментального оружия пока нет картинки — значок
			CardIcons.draw(ctrl, Vector2(x + 26, y + 39), 36.0, hp.weapon, Color(0.6, 0.85, 1.0))
		_text(Vector2(x + 50, y + 24), Weapons.DEFS[hp.weapon]["short"], 16, Color(0.95, 0.93, 0.88), HORIZONTAL_ALIGNMENT_LEFT, cw - 56.0)
		# читаемость HUD: под названием — число и по какой цели бьёт (подвесы больше не дублируются в левой панели)
		var sub := "×%d" % hp.slots
		if Weapons.DEFS[hp.weapon]["uses_priority"]:
			sub += " · " + String(Weapons.PRIORITY_NAMES[hp.priority])
		if hp.uses_trigger() and hp.trigger != "auto":
			sub += " · ПКМ"
		_text(Vector2(x + 50, y + 42), sub, 13, Color(0.72, 0.72, 0.66), HORIZONTAL_ALIGNMENT_LEFT, cw - 56.0)
		for i in Weapons.MAX_LEVEL:
			ctrl.draw_rect(Rect2(x + 50 + i * 17, y + 52, 13, 6), (Cards.EVO_COLOR if hp.evo else Menu.C_AMBER) if i < hp.level else Color(1, 1, 1, 0.12))
		if hp.evo:
			_text(Vector2(x + 50 + Weapons.MAX_LEVEL * 17 + 4, y + 59), "М%s" % (("+%d" % hp.evo_plus) if hp.evo_plus > 0 else ""), 14, Cards.EVO_COLOR)
		# перезарядка
		var full := maxf(hp.reload_time(p), 0.01)
		var k2 := 1.0 - clampf(hp.cd / full, 0.0, 1.0)
		ctrl.draw_rect(Rect2(x + 50, y + 66, cw - 62.0, 5), Color(1, 1, 1, 0.1))
		ctrl.draw_rect(Rect2(x + 50, y + 66, (cw - 62.0) * k2, 5), Color(0.5, 0.95, 0.6) if k2 >= 1.0 else Color(0.85, 0.83, 0.78))
		x += cw + 12.0
	if not p.syn.is_empty():
		var names := PackedStringArray()
		for id in p.syn:
			names.append(Cards.SYNERGIES[id]["title"] if Cards.SYNERGIES.has(id) else PlaneClasses.SKILL3[p.skill3]["syn"]["title"])
		_text(Vector2(0, y - 10), "Связки: " + ", ".join(names), 16, Menu.C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, size.x)


# ---------- 3.2: курс ----------

## Строка курса в левой панели: слоты связок и прогресс к курсу
func _course_bar(p: Player, pos: Vector2) -> void:
	var x := pos.x
	var sw := 148.0
	for i in Cards.MAX_SYN:
		var r := Rect2(x, pos.y, sw, 26)
		var ids: Array = p.syn.keys()
		if i < ids.size():
			var sd := Cards.syn_def(p, ids[i])
			var col: Color = sd.get("color", Menu.C_AMBER)
			ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.35))
			ctrl.draw_rect(r, col, false, 2.0)
			_text(Vector2(x + 6, pos.y + 19), "◆ " + String(sd["title"]), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, sw - 8.0)
		else:
			ctrl.draw_rect(r, Color(1, 1, 1, 0.06))
			ctrl.draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
			_text(Vector2(x + 6, pos.y + 19), "связка %d" % (i + 1), 14, Color(0.62, 0.64, 0.7))
		x += sw + 8.0
	if not p.has_course():
		return
	var sd2 := Cards.syn_def(p, p.course)
	var conds := Cards.cond_list(p, p.course)
	var k := Cards._progress(conds)
	var ready := Cards.conds_ok(conds)
	var y := pos.y + 34.0
	var col2: Color = sd2.get("color", Menu.C_AMBER)
	_text(Vector2(pos.x, y + 14), "К связке «%s»" % sd2["title"], 16, col2.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT, 236)
	ctrl.draw_rect(Rect2(pos.x + 240, y + 2, 220, 14), Color(0, 0, 0, 0.5))
	var a := 1.0 if not ready else (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01))
	ctrl.draw_rect(Rect2(pos.x + 240, y + 2, 220 * k, 14), Color(col2.r, col2.g, col2.b, a))
	var parts := PackedStringArray()
	for c in conds:
		parts.append(("✓" if c[1] else "") + String(c[0]))
	# свежий взгляд: длинный список условий переносится, а не вылезает за панель
	_para(Vector2(pos.x, y + 36), "Связка придёт в следующем выборе!" if ready else " · ".join(parts), 460.0, 14,
		Color(1.0, 0.9, 0.4) if ready else Color(0.85, 0.87, 0.92))


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
