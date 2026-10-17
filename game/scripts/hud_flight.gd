class_name HudFlight
extends HudKit
## Интерфейс в полёте: опыт, прочность, навыки, подвесы, время и асы, указатели угроз,
## эвакуация, активности, радио, полоса подвесов, строка курса.


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
	_fx_texts(m)
	_boss_bars(m, size)
	_threat_markers(size)
	if m.state == "playing":
		_evac_marker(m, size)

	if Hints.t > 0.0 and Hints.text != "" and m.state == "playing":
		_hint_box(Hints.text, size, clampf(Hints.t * 2.0, 0.0, 1.0))
	if m.banner_t > 0.0 and m.state == "playing":
		var a := clampf(m.banner_t, 0.0, 1.0)
		_ctext(170, m.banner, 30, Color(1.0, 0.85, 0.5, a))

	var hint := "Мышь — куда лететь · Space — уклонение · Shift — форсаж · E — навык · Tab — пауза" + (" · F5/F6/F7 — отладка" if Main.DEBUG else "")
	_text(Vector2(0, size.y - 20), hint, 15, Color(0.75, 0.78, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)


## U-02: подсказка новичку — рамка над нижней строкой клавиш
func _hint_box(s: String, size: Vector2, a: float) -> void:
	var w := minf(1100.0, size.x - 80.0)
	var r := Rect2((size.x - w) / 2.0, size.y - 220.0, w, 86.0)
	ctrl.draw_rect(r, Color(0.04, 0.05, 0.06, 0.82 * a))
	ctrl.draw_rect(r, Color(1.0, 0.85, 0.4, 0.8 * a), false, 2.0)
	_text(Vector2(r.position.x + 16, r.position.y + 26), "ПОДСКАЗКА", 13, Color(1.0, 0.85, 0.4, a))
	_para(Vector2(r.position.x + 16, r.position.y + 50), s, w - 32.0, 18, Color(1, 1, 1, a))


func _skill(y: float, title: String, key: String, cd: float, active: float, note := "") -> void:
	var s: String
	var c := Color(0.6, 1.0, 0.7)
	if active > 0.0:
		s = "%s [%s]: действует %.1f с" % [title, key, active]
		c = Color(1.0, 0.85, 0.4)
	elif cd > 0.0:
		s = "%s [%s]: %.1f с" % [title, key, cd]
		c = Color(0.7, 0.72, 0.78)
	else:
		s = "%s [%s]: готово" % [title, key]
	_text(Vector2(24, y), s, 18, c)
	# правка 14: что делает навык — коротко, серым, следом за строкой
	if note != "" and active <= 0.0 and cd <= 0.0:
		var tw := ui_font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_text(Vector2(24 + tw + 10, y), "· " + note, 14, Color(0.7, 0.78, 0.88, 0.85))


func _left_panel(m: Main, p: Player) -> void:
	# 3.1: подложка под левой панелью — светлая земля не «съедает» текст
	var ph := 324.0 + p.groups.size() * 22.0 + (22.0 if p.wingmen.size() > 0 else 0.0) + (24.0 if p.skill_b != "" else 0.0)
	_backing(Rect2(10, 14, 480, ph))
	ctrl.draw_rect(Rect2(24, 24, 320, 20), Color(0, 0, 0, 0.55))
	ctrl.draw_rect(Rect2(24, 24, 320.0 * p.hp / p.max_hp, 20), Color(0.4, 0.9, 0.5))
	_text(Vector2(30, 40), "Прочность %d / %d" % [int(p.hp), int(p.max_hp)], 16, Color(0.05, 0.1, 0.05))
	_text(Vector2(356, 40), "Ур. %d" % m.level, 20, Color(0.6, 1.0, 0.7))
	# 3.5: топливо — полоска под прочностью и остаток в минутах
	var fu := Fuel.current()
	if fu != null:
		var fc := Color(1.0, 0.35, 0.3) if fu.frac() < 0.1 else (Color(1.0, 0.8, 0.35) if fu.frac() <= Fuel.CALL_AT else Color(0.95, 0.85, 0.55))
		ctrl.draw_rect(Rect2(24, 48, 320, 8), Color(0, 0, 0, 0.55))
		ctrl.draw_rect(Rect2(24, 48, 320.0 * fu.frac(), 8), fc)
		var fs := "БАК ПУСТ" if fu.empty() else "Топливо %d:%02d" % [int(fu.left) / 60, int(fu.left) % 60]
		_text(Vector2(356, 58), fs, 15, fc)
	if p.manual_mode:
		_text(Vector2(24, 76), "Пушка: РУЧНОЙ огонь — разгон +%d%% урона  [Q]" % int(round(p.manual_bonus * 100.0)), 19, Color(1.0, 0.82, 0.35))
	else:
		_text(Vector2(24, 76), "Пушка: стреляет сама  [Q — ручной огонь, до +50% урона]", 19)
	_skill(104, "Уклонение" if p.has_roll() else "Залп ловушек", "Space", p.roll_cd, p.roll_t if p.has_roll() else p.salvo_t)
	_skill(128, "Форсаж", "Shift", p.ab_cd, p.ab_t)
	_skill(152, "Нырок", "V", p.dive_cd, p.dive_t)
	var s3: Dictionary = p.s3_def()
	_skill(176, "%s %s" % [s3["title"], Prog.ROMAN[p.s3_lvl()]], "E", p.s3_cd, p.s3_active(), String(s3.get("hud", "")))
	if p.skill_b != "":
		_skill(200, PlaneClasses.SKILL3[p.skill_b]["title"], "F", p.sb_cd, p.s3_active(p.skill_b), String(PlaneClasses.SKILL3[p.skill_b].get("hud", "")))
	var y := 234.0 if p.skill_b != "" else 210.0
	for g in p.groups:
		var h := g as Hardpoint
		var c := Color(0.75, 0.85, 0.95)
		var s := h.label()
		if h.is_empty():
			c = Color(0.55, 0.58, 0.65)
		else:
			if Weapons.DEFS[h.weapon]["uses_priority"]:
				s += " · %s" % Weapons.PRIORITY_NAMES[h.priority]
			if h.cd > 0.25:
				s += " · %.1f с" % h.cd
		_text(Vector2(24, y), s, 17, c)
		y += 22.0
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
		_text(Vector2(24, y), "Звено: " + ", ".join(wl), 17, Color(0.8, 0.75, 1.0))
		y += 22.0
	_text(Vector2(24, y + 6), "Управление: %s  [F2]" % Hud.SCHEMES[int(Tuning.g("scheme"))], 16, Color(0.7, 0.78, 0.9))
	_course_bar(p, Vector2(24, y + 22))
	if m.god_mode:
		_text(Vector2(24, y + 30), "ОТЛАДКА: неуязвимость (F7)", 16, Color(1, 0.5, 0.5))
	if int(Tuning.g("scheme")) == 2 and m.state == "playing":
		var mp := ctrl.get_local_mouse_position()
		ctrl.draw_arc(mp, 12.0, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 2.0)
		ctrl.draw_circle(mp, 2.0, Color(1, 1, 1, 0.9))


func _right_panel(m: Main, size: Vector2) -> void:
	var t := int(m.run_time)
	var w := size.x - 24.0
	_backing(Rect2(size.x - 340, 14, 330, 172), true)
	_text(Vector2(0, 46), "%02d:%02d" % [t / 60, t % 60], 28, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w)
	# U-02: цель вылета рядом с таймером (U-05: словами операции кампании)
	var left := maxi(0, 900 - t)
	var goal := ""
	if Campaign.goal_done(m.run_time, m.op_flags):
		goal = "задание выполнено"
	elif left > 0:
		goal = "%s %d:%02d" % [Campaign.op()["hud"], left / 60, left % 60]
	else:
		goal = "сбейте " + ("«Барона»" if not m.op_flags.get("baron", false) and (Campaign.op()["need"] as Array).has("baron") else "«Крепость»")
	_text(Vector2(0, 46), goal + "   ", 16, Color(0.6, 1.0, 0.7) if goal == "задание выполнено" else Color(0.75, 0.8, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, w - 90.0)
	if (Campaign.op()["need"] as Array).has("baron"):
		_text(Vector2(size.x - 326, 174), "«Барон»: %s" % ("сбит ✓" if m.op_flags.get("baron", false) else "не сбит"), 15, Color(0.6, 1.0, 0.7) if m.op_flags.get("baron", false) else Color(1.0, 0.75, 0.6))
	_text(Vector2(0, 74), "Сбито: %d" % m.kills, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(0, 100), "Запчасти: %d" % int(m.parts), 20, Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, w)
	var every := Tuning.g("boss_every")
	var next := (floorf(m.run_time / every) + 1.0) * every - m.run_time
	if m.boss_alive():
		_text(Vector2(0, 126), "Ас в бою!", 18, Color(1.0, 0.5, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, w)
	else:
		_text(Vector2(0, 126), "Следующий ас через %d:%02d" % [int(next) / 60, int(next) % 60], 18, Color(0.85, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, w)
	if m.run_time > 900.0:
		_text(Vector2(0, 150), "Задержались: добыча ×%.1f" % m.continue_mult(), 18, Color(1.0, 0.8, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(0, 174), "FPS: %d" % Engine.get_frames_per_second(), 15, Color(0.7, 0.7, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, w)


func _boss_bars(m: Main, size: Vector2) -> void:
	var y := 30.0
	for n in m.get_tree().get_nodes_in_group("enemies"):
		var b := n as Boss
		if b == null:
			continue
		var w := 560.0
		var x := (size.x - w) / 2.0
		_text(Vector2(x, y + 2), b.title, 18, Color(1, 0.85, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)
		ctrl.draw_rect(Rect2(x, y + 10, w, 14), Color(0, 0, 0, 0.6))
		ctrl.draw_rect(Rect2(x, y + 10, w * b.hp / b.max_hp, 14), Color(1.0, 0.35, 0.3))
		if b.shield > 0.0:
			ctrl.draw_rect(Rect2(x, y + 25, w * b.shield / b.shield_max, 5), Color(0.5, 0.8, 1.0))
		y += 48.0


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
	_edge_arrow(sp, rect, size, Color(0.4, 1.0, 0.5), 1.8)
	var d := int(m.player.global_position.distance_to(m.evac.target_pos()))
	_ctext(246, "ЭВАКУАЦИЯ: ворота %d / %d · %d м · окно %d с" % [m.evac.passed + 1, EvacZone.GATES, d / 10, int(ceil(m.evac.time_left))], 22, Color(0.6, 1.0, 0.7))


func _edge_arrow(sp: Vector2, rect: Rect2, size: Vector2, col: Color, scale := 1.0) -> void:
	if rect.has_point(sp):
		return
	var c := size / 2.0
	var dir := (sp - c).normalized()
	var tx := INF if absf(dir.x) < 0.001 else (rect.size.x / 2.0) / absf(dir.x)
	var ty := INF if absf(dir.y) < 0.001 else (rect.size.y / 2.0) / absf(dir.y)
	var pos := c + dir * minf(tx, ty)
	var a := dir.angle()
	var pts := PackedVector2Array([pos + Vector2.from_angle(a) * 18.0 * scale, pos + Vector2.from_angle(a + 2.5) * 14.0 * scale, pos + Vector2.from_angle(a - 2.5) * 14.0 * scale])
	ctrl.draw_colored_polygon(pts, col)


## Газ (РУД), «на хвосте», серия сбитий
func _flight_panel(m: Main, p: Player, size: Vector2) -> void:
	if p.hp <= 0.0:
		return
	var x := 24.0
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
		_text(Vector2(0, 220), "Серия ×%d · опыт ×%.2f" % [m.streak, m.streak_mult()], 22, Color(1.0, 0.75, 0.4, a), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 24.0)


## Активности: указатели на позицию ПВО и аса-соперника, радиопереговоры, «ХВОСТ!»
func _activity_panel(m: Main, p: Player, size: Vector2) -> void:
	var xf := m.get_viewport().get_canvas_transform()
	var rect := Rect2(Vector2.ZERO, size).grow(-60.0)
	var node: Node = m.spawner.activity_node if m.spawner != null else null
	if is_instance_valid(node):
		if node is AASite:
			var site := node as AASite
			_edge_arrow(_ws(xf, site.global_position), rect, size, Color(1.0, 0.85, 0.3), 1.8)
			var d := int(p.global_position.distance_to(site.global_position))
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
			_edge_arrow(_ws(xf, cv.global_position), rect, size, Color(1.0, 0.7, 0.35), 1.8)
			var cs: String
			if cv.alarm:
				cs = "КОЛОННА: до укрытия %d с · грузовиков: %d из %d" % [int(ceil(maxf(cv.timer, 0.0))), cv.trucks_left(), cv.trucks_total]
			else:
				cs = "Колонна снабжения: %d м — подлетите и сожгите грузовики" % (int(p.global_position.distance_to(cv.global_position)) / 10)
			_ctext(276, cs, 22, Color(1.0, 0.78, 0.45))
			_ctext(302, "Подбейте головную машину — колонна встанет · награда: груз с каждого грузовика", 17, Color(0.85, 0.75, 1.0))
		elif node is Transport:
			var tr := node as Transport
			_edge_arrow(_ws(xf, tr.global_position), rect, size, Color(1.0, 0.6, 0.25), 1.8)
			_ctext(276, "ОХОТА: транспортник уйдёт через %d с · прочность %d%%" % [int(ceil(maxf(tr.life, 0.0))), int(ceil(tr.hp / tr.max_hp * 100.0))], 22, Color(1.0, 0.75, 0.45))
			_ctext(302, "Награда: груз — запчасти и ремкомплекты", 17, Color(0.85, 0.75, 1.0))
		elif node is RivalAce:
			var ace := node as RivalAce
			_edge_arrow(_ws(xf, ace.global_position), rect, size, Color(1.0, 0.25, 0.3), 1.8)
			_ctext(276, "ДОГФАЙТ: ас «%s» · уйдёт через %d с" % [ace.callsign, int(ceil(ace.life))], 22, Color(1.0, 0.6, 0.6))
			_ctext(302, "Награда: выбор из редких карточек", 17, Color(0.85, 0.75, 1.0))
			if ace.threatening() and int(Time.get_ticks_msec() / 200) % 2 == 0:
				_ctext(size.y / 2.0 - 110.0, "ХВОСТ! Сбрось газ (S) или манёвр", 30, Color(1.0, 0.3, 0.25))
	# 3.5: свой заправщик
	var tk: Tanker = m.spawner.fuel.tanker if m.spawner != null and m.spawner.fuel != null else null
	if is_instance_valid(tk) and tk.alive() and not tk.leaving:
		_edge_arrow(_ws(xf, tk.global_position), rect, size, Color(0.45, 1.0, 0.55), 1.8)
		var ts := "СТЫКОВКА — ЗАПРАВКА ИДЁТ" if tk.filling else ("ШТАНГА ВЫДВИГАЕТСЯ — держитесь ровно" if tk.in_cone else "ЗАПРАВЩИК: зайдите ему в хвост")
		_ctext(328, "%s · уйдёт через %d с · прочность %d%%" % [ts, int(ceil(tk.life)), int(ceil(tk.hp / tk.max_hp * 100.0))], 20, Color(0.55, 1.0, 0.65))
	if m.radio_t > 0.0:
		var a := clampf(m.radio_t, 0.0, 1.0)
		var w := 760.0
		var r := Rect2((size.x - w) / 2.0, size.y - 200.0, w, 56)
		ctrl.draw_rect(r, Color(0.05, 0.06, 0.08, 0.8 * a))
		ctrl.draw_rect(r, Color(1.0, 0.4, 0.4, 0.6 * a), false, 2.0)
		_text(Vector2(r.position.x + 16, r.position.y + 24), "Радио · «%s»:" % m.radio_from, 16, Color(1.0, 0.6, 0.6, a))
		_text(Vector2(r.position.x + 16, r.position.y + 46), m.radio_text, 19, Color(1, 1, 1, a))


## 2.8: полоса подвесов внизу экрана — картинка оружия, уровень, перезарядка, связки
func _loadout_strip(p: Player, size: Vector2) -> void:
	var items: Array = []
	for g in p.groups:
		if not g.is_empty():
			items.append(g)
	if items.is_empty():
		return
	var cw := 150.0
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
		_text(Vector2(x + 50, y + 24), Weapons.DEFS[hp.weapon]["short"], 15, Color(0.92, 0.9, 0.84))
		_text(Vector2(x + 50, y + 42), "×%d" % hp.slots, 13, Color(0.62, 0.62, 0.56))
		for i in Weapons.MAX_LEVEL:
			ctrl.draw_rect(Rect2(x + 50 + i * 17, y + 50, 13, 6), (Cards.EVO_COLOR if hp.evo else Menu.C_AMBER) if i < hp.level else Color(1, 1, 1, 0.12))
		if hp.evo:
			_text(Vector2(x + 112, y + 42), "Э%s" % (("+%d" % hp.evo_plus) if hp.evo_plus > 0 else ""), 14, Cards.EVO_COLOR)
		# перезарядка
		var full := maxf(hp.reload_time(p), 0.01)
		var k2 := 1.0 - clampf(hp.cd / full, 0.0, 1.0)
		ctrl.draw_rect(Rect2(x + 50, y + 64, 85, 4), Color(1, 1, 1, 0.1))
		ctrl.draw_rect(Rect2(x + 50, y + 64, 85 * k2, 4), Color(0.5, 0.95, 0.6) if k2 >= 1.0 else Color(0.85, 0.83, 0.78))
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
	for i in Cards.MAX_SYN:
		var r := Rect2(x, pos.y, 132, 26)
		var ids: Array = p.syn.keys()
		if i < ids.size():
			var sd := Cards.syn_def(p, ids[i])
			var col: Color = sd.get("color", Menu.C_AMBER)
			ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.35))
			ctrl.draw_rect(r, col, false, 2.0)
			_text(Vector2(x + 6, pos.y + 19), "◆ " + String(sd["title"]), 13, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 124)
		else:
			ctrl.draw_rect(r, Color(1, 1, 1, 0.06))
			ctrl.draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
			_text(Vector2(x + 6, pos.y + 19), "слот %d" % (i + 1), 13, Color(0.6, 0.62, 0.68))
		x += 140.0
	if not p.has_course():
		return
	var sd2 := Cards.syn_def(p, p.course)
	var conds := Cards.cond_list(p, p.course)
	var k := Cards._progress(conds)
	var ready := Cards.conds_ok(conds)
	var y := pos.y + 34.0
	var col2: Color = sd2.get("color", Menu.C_AMBER)
	_text(Vector2(pos.x, y + 14), "К связке «%s»" % sd2["title"], 14, col2.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT, 236)
	ctrl.draw_rect(Rect2(pos.x + 240, y + 2, 170, 14), Color(0, 0, 0, 0.5))
	var a := 1.0 if not ready else (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01))
	ctrl.draw_rect(Rect2(pos.x + 240, y + 2, 170 * k, 14), Color(col2.r, col2.g, col2.b, a))
	var parts := PackedStringArray()
	for c in conds:
		parts.append(("✓" if c[1] else "") + String(c[0]))
	_text(Vector2(pos.x, y + 36), "Связка придёт в следующем выборе!" if ready else " · ".join(parts), 14,
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
