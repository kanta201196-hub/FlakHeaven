class_name Hud
extends CanvasLayer
## Интерфейс прототипа 2: опыт и уровень, прочность, навыки, подвесы, асы, эвакуация,
## экраны выбора класса, карточек, подвесов (пауза) и итогов вылета.
## Всё рисуется кодом; кнопки — прямоугольники, по которым можно кликнуть мышью.

const SCHEMES := ["по направлению (WASD / стик)", "влево / вправо (A / D)", "мышью (самолёт летит за курсором)"]

static var _font: Font

var ctrl: Control
var _dmg_flash := 0.0
var _buttons: Array = [] # [Rect2, action]


static func ui_font() -> Font:
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Roboto", "Noto Sans", "DejaVu Sans", "Ubuntu", "Helvetica"])
		_font = sf
	return _font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	ctrl = Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ctrl)
	ctrl.draw.connect(_draw_hud)


func flash_damage() -> void:
	_dmg_flash = 0.3


func _process(delta: float) -> void:
	_dmg_flash = maxf(0.0, _dmg_flash - delta)
	ctrl.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := Main.I
		if m == null or m.state == "playing" or m.tuning_panel.visible or m.report.visible:
			return
		var mp := ctrl.get_local_mouse_position()
		for b in _buttons:
			if (b[0] as Rect2).has_point(mp):
				get_viewport().set_input_as_handled()
				m.ui_click(b[1])
				return


# ---------- Примитивы ----------

## 3.1: у всего текста интерфейса тёмная обводка — читается на светлой земле
func _text(pos: Vector2, s: String, size := 20, color := Color(0.92, 0.95, 1.0), align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ctrl.draw_string_outline(ui_font(), pos, s, align, width, size, maxi(3, size / 5), Color(0.02, 0.025, 0.03, 0.85 * color.a))
	ctrl.draw_string(ui_font(), pos, s, align, width, size, color)


func _ctext(y: float, s: String, size: int, color: Color) -> void:
	_text(Vector2(0, y), s, size, color, HORIZONTAL_ALIGNMENT_CENTER, ctrl.size.x)


## Многострочный текст с переносом по ширине
func _para(pos: Vector2, s: String, width: float, size := 18, color := Color(0.85, 0.88, 0.95)) -> float:
	ctrl.draw_multiline_string_outline(ui_font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, maxi(3, size / 5), Color(0.02, 0.025, 0.03, 0.8 * color.a))
	ctrl.draw_multiline_string(ui_font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, color)
	var lines := ui_font().get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size).y
	return lines


## 2.8: стиль Flak Heaven — графит, янтарная подсветка, срезанный угол
func _panel(r: Rect2, hover: bool, accent := Menu.C_AMBER) -> void:
	var cut := minf(14.0, r.size.y * 0.3)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut), r.end, Vector2(r.position.x, r.end.y)])
	ctrl.draw_colored_polygon(pts, Color(0.085, 0.095, 0.085, 0.95))
	pts.append(r.position)
	ctrl.draw_polyline(pts, accent if hover else Color(accent.r, accent.g, accent.b, 0.4), 2.5 if hover else 1.5)


func _button(r: Rect2, label: String, action: String, size := 20) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	_panel(r, hover)
	_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0 + size * 0.35), label, size, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_buttons.append([r, action])


func _skill(y: float, title: String, key: String, cd: float, active: float) -> void:
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


## Подложка панели: тёмная, с мягким краем в сторону центра экрана
func _backing(r: Rect2, right := false) -> void:
	var steps := 6
	for i in steps:
		var k := float(i) / steps
		var rr := r
		var cut := r.size.x * 0.25 * k
		if right:
			rr.position.x += cut
		rr.size.x -= cut
		ctrl.draw_rect(rr, Color(0.03, 0.035, 0.04, 0.09))


# ---------- Главная отрисовка ----------

func _draw_hud() -> void:
	_buttons.clear()
	var m := Main.I
	if m == null or m.tuning_panel.visible:
		return
	var size := ctrl.size
	var p := m.player

	if m.state in ["menu", "settings"]:
		return
	if m.state == "codex":
		_codex(m, size)
		return
	if m.state == "hangar":
		_hangar(m, size)
		return
	if m.state == "class_select":
		_class_select(size)
		return

	if _dmg_flash > 0.0:
		ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0, 0, _dmg_flash * 0.5))

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
	_boss_bars(m, size)
	_threat_markers(size)
	if m.state == "playing":
		_evac_marker(m, size)

	if m.banner_t > 0.0 and m.state == "playing":
		var a := clampf(m.banner_t, 0.0, 1.0)
		_ctext(170, m.banner, 30, Color(1.0, 0.85, 0.5, a))

	var hint := "Мышь — курс · W/S — газ · ЛКМ — огонь (ручн.) · ПКМ — НАР/бомбы (по кнопке) · Q — авто/ручной · Space — бочка · Shift — форсаж · E — навык класса · Tab/Esc — подвесы · F2 — схема" + (" · F5/F6/F7 — отладка" if Main.DEBUG else "")
	_text(Vector2(0, size.y - 20), hint, 15, Color(0.75, 0.78, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)

	match m.state:
		"course_pick":
			_course_pick(m, size)
		"levelup":
			_levelup(m, size)
		"paused":
			_loadout(m, size)
		"dead", "evac":
			_result(m, size)


func _left_panel(m: Main, p: Player) -> void:
	# 3.1: подложка под левой панелью — светлая земля не «съедает» текст
	var ph := 300.0 + p.groups.size() * 22.0 + (22.0 if p.wingmen.size() > 0 else 0.0) + (24.0 if p.skill_b != "" else 0.0)
	_backing(Rect2(10, 14, 480, ph))
	ctrl.draw_rect(Rect2(24, 24, 320, 20), Color(0, 0, 0, 0.55))
	ctrl.draw_rect(Rect2(24, 24, 320.0 * p.hp / p.max_hp, 20), Color(0.4, 0.9, 0.5))
	_text(Vector2(30, 40), "Прочность %d / %d" % [int(p.hp), int(p.max_hp)], 16, Color(0.05, 0.1, 0.05))
	_text(Vector2(356, 40), "Ур. %d" % m.level, 20, Color(0.6, 1.0, 0.7))
	if p.manual_mode:
		_text(Vector2(24, 76), "Курсовое: РУЧНОЕ — обороты +%d%% урона  [Q]" % int(round(p.manual_bonus * 100.0)), 19, Color(1.0, 0.82, 0.35))
	else:
		_text(Vector2(24, 76), "Курсовое: АВТО  [Q — ручное, до +50% урона]", 19)
	_skill(104, "Бочка", "Space", p.roll_cd, p.roll_t)
	_skill(128, "Форсаж", "Shift", p.ab_cd, p.ab_t)
	var s3: Dictionary = p.s3_def()
	_skill(152, "%s %s" % [s3["title"], Prog.ROMAN[p.s3_lvl()]], "E", p.s3_cd, p.s3_active())
	if p.skill_b != "":
		_skill(176, PlaneClasses.SKILL3[p.skill_b]["title"], "F", p.sb_cd, p.s3_active(p.skill_b))
	var y := 210.0 if p.skill_b != "" else 186.0
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
	_text(Vector2(24, y + 6), "Управление: %s  [F2]" % SCHEMES[int(Tuning.g("scheme"))], 16, Color(0.7, 0.78, 0.9))
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
	_text(Vector2(0, 74), "Сбито: %d" % m.kills, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(0, 100), "Запчасти: %d" % int(m.parts), 20, Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, w)
	var every := Tuning.g("boss_every")
	var next := (floorf(m.run_time / every) + 1.0) * every - m.run_time
	if m.boss_alive():
		_text(Vector2(0, 126), "Ас в бою!", 18, Color(1.0, 0.5, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, w)
	else:
		_text(Vector2(0, 126), "Следующий ас через %d:%02d" % [int(next) / 60, int(next) % 60], 18, Color(0.85, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, w)
	if m.run_time > 900.0:
		_text(Vector2(0, 150), "Продолжение: добыча ×%.1f" % m.continue_mult(), 18, Color(1.0, 0.8, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, w)
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
			_edge_arrow(xf * (mi["p"] as Vector2), rect, size, Color(1.0, 0.2, 0.15))
	for n in m.get_tree().get_nodes_in_group("enemies"):
		if n is MissileCarrier and n._lock > 0.0:
			_edge_arrow(xf * (n as Node2D).global_position, rect, size, Color(1.0, 0.6, 0.2))
		elif n is Boss:
			_edge_arrow(xf * (n as Node2D).global_position, rect, size, Color(1.0, 0.3, 0.6), 1.6)


func _evac_marker(m: Main, size: Vector2) -> void:
	if not is_instance_valid(m.evac) or not is_instance_valid(m.player):
		return
	var xf := m.get_viewport().get_canvas_transform()
	var rect := Rect2(Vector2.ZERO, size).grow(-60.0)
	var sp := xf * m.evac.target_pos()
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


# ---------- Экран выбора класса ----------

func _class_select(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.04, 0.86))
	_text(Vector2(0, 120), "ВЫБЕРИТЕ САМОЛЁТ", 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_button(Rect2(64, 60, 220, 46), "‹ Меню (Esc)", "class_back", 18)
	_ctext(162, "Клавиши 1 / 2 / 3 или клик мышью", 20, Color(0.7, 0.75, 0.85))
	var w := 520.0
	var h := 700.0
	var gap := 40.0
	var x0 := (size.x - (w * 3 + gap * 2)) / 2.0
	var mp := ctrl.get_local_mouse_position()
	for i in 3:
		var id: String = PlaneClasses.LIST[i]
		var d: Dictionary = PlaneClasses.DATA[id]
		var r := Rect2(x0 + i * (w + gap), 200, w, h)
		var hover := r.has_point(mp)
		_panel(r, hover, d["color"])
		_buttons.append([r, "class:" + id])
		var x := r.position.x + 28.0
		var y := r.position.y + 50.0
		_text(Vector2(x, y), "%d — %s" % [i + 1, d["title"]], 26, d["color"])
		y += 32.0
		_text(Vector2(x, y), d["role"], 18, Color(0.8, 0.85, 0.95))
		var sb: String = Profile.skills(id)[1]
		_text(Vector2(x, y), "Экипаж ур. %d%s%s" % [Profile.crew_lvl(id), " · самолёт ур. 2 ✓" if Profile.plane2(id) else "",
			(" · навык F: " + String(PlaneClasses.SKILL3[sb]["title"])) if sb != "" else ""], 15, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, w - 56.0)
		y += 44.0
		_stat_bar(x, y, "Прочность", float(d["hp"]) / 240.0, "%d" % int(d["hp"]))
		y += 26.0
		_stat_bar(x, y, "Скорость", float(d["speed"]), "%d%%" % int(float(d["speed"]) * 100.0))
		y += 26.0
		_stat_bar(x, y, "Манёвр", float(d["turn"]), "%d%%" % int(float(d["turn"]) * 100.0))
		y += 26.0
		_stat_bar(x, y, "Курсовое", float(d["gun_dmg"]) * float(d["gun_rate"]) / 1.3, "×%.2f" % (float(d["gun_dmg"]) * float(d["gun_rate"])))
		y += 36.0
		_text(Vector2(x, y), "Подвесы:", 19, Color.WHITE)
		y += 26.0
		for g in d["groups"]:
			var wname: String = "пусто — оружие из карточек" if g["weapon"] == "" else Weapons.title(g["weapon"])
			_text(Vector2(x + 12, y), "• %s ×%d: %s" % [g["name"], g["slots"], wname], 17, Color(0.85, 0.88, 0.95))
			y += 24.0
		if int(d["turrets"]) > 0:
			_text(Vector2(x + 12, y), "• Автотурели: %d (круговой обстрел)" % int(d["turrets"]), 17, Color(0.85, 0.88, 0.95))
			y += 24.0
		_text(Vector2(x + 12, y), "• Ведомые: до %d" % int(d["wingmen"]) if int(d["wingmen"]) > 0 else "• Ведомых нет", 17, Color(0.85, 0.88, 0.95))
		y += 34.0
		# 3.1: выбор навыка класса (3 варианта)
		_text(Vector2(x, y), "Навык класса [E] — выберите:", 18, Color(0.7, 1.0, 0.7))
		y += 10.0
		var cur: String = Main.I.skill_pick.get(id, Profile.skills(id)[0])
		for sk in PlaneClasses.CLASS_SKILLS[id]:
			var sd: Dictionary = PlaneClasses.SKILL3[sk]
			var sr := Rect2(x - 8, y, w - 40, 58)
			var on: bool = sk == cur
			var sh := sr.has_point(mp)
			ctrl.draw_rect(sr, Color(0.55, 0.9, 0.55, 0.16) if on else Color(1, 1, 1, 0.05 if sh else 0.02))
			ctrl.draw_rect(sr, Color(0.6, 1.0, 0.6, 0.9) if on else Color(1, 1, 1, 0.25 if sh else 0.1), false, 2.0)
			var unl := Profile.skill_unlocked(id, sk)
			if unl:
				_buttons.append([sr, "skill:%s:%s" % [id, sk]])
			var si: int = PlaneClasses.CLASS_SKILLS[id].find(sk)
			_text(Vector2(x + 4, y + 20), ("● " if on else "○ ") + "%s · %d с%s" % [sd["title"], int(sd["cd"]), "" if unl else "  — экипаж ур. %d" % Profile.SKILL_UNLOCK[si]], 17,
				Color(0.85, 1.0, 0.85) if on else (Color(0.85, 0.88, 0.95) if unl else Color(0.5, 0.52, 0.56)))
			_para(Vector2(x + 4, y + 40), sd["short"], w - 40.0, 13, Color(0.75, 0.8, 0.88))
			y += 62.0
		# картинки самолёта: ур. 1 и ур. 2 (модернизация в полёте), носом вверх
		var area_top := y + 4.0
		var area_h := r.end.y - area_top - 34.0
		if area_h > 40.0:
			for lv in [1, 2]:
				var t := PlaneArt.plane_tex(id, lv)
				if t == null:
					continue
				var k := minf(area_h / t.get_width(), (w * 0.42) / t.get_height())
				var c := Vector2(r.position.x + w * (0.3 if lv == 1 else 0.7), area_top + area_h / 2.0)
				ctrl.draw_set_transform(c, -PI / 2.0, Vector2(k, k))
				ctrl.draw_texture(t, -t.get_size() / 2.0)
				ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				_text(Vector2(c.x - 130.0, r.end.y - 14.0), "ур. %d%s" % [lv, "" if lv == 1 else " (с ур. пилота %d)" % int(Tuning.g("plane_lvl2_at"))], 15, Color(0.7, 0.75, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 260.0)
	_ctext(932, "Управление: %s   [F2 — сменить]" % SCHEMES[int(Tuning.g("scheme"))], 20, Color(0.75, 0.85, 1.0))
	_ctext(964, "Опыт с врагов подбирается сам рядом с самолётом. Каждые 5 минут — ас (мини-босс), после него — окно эвакуации.", 18, Color(0.8, 0.85, 0.9))
	_ctext(992, "Угрозы: дроны — держат дистанцию и стреляют (мигают жёлтым) · оранжевые камикадзе — таран · перехватчики — заходы с очередью · ракетоносцы — ракеты после красной линии", 18, Color(0.95, 0.75, 0.75))
	_ctext(1020, "Мышь — курс · W/S — газ (держаться за целью) · сядь врагу на хвост — курсовое +50% · пролёт на волоске перезаряжает навыки · серия сбитий — больше опыта", 18, Color(0.7, 0.95, 1.0))


func _stat_bar(x: float, y: float, label: String, frac: float, val: String) -> void:
	_text(Vector2(x, y), label, 17, Color(0.8, 0.85, 0.95))
	ctrl.draw_rect(Rect2(x + 120, y - 13, 260, 12), Color(1, 1, 1, 0.08))
	ctrl.draw_rect(Rect2(x + 120, y - 13, 260 * clampf(frac, 0.0, 1.0), 12), Color(0.55, 0.8, 1.0))
	_text(Vector2(x + 392, y), val, 17, Color.WHITE)


# ---------- Карточки ----------

func _levelup(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	if m.offer_rare:
		_ctext(150, "НАГРАДА %s: ВЫБОР ИЗ РЕДКИХ КАРТОЧЕК" % (m.rare_reasons[0] if not m.rare_reasons.is_empty() else ""), 38, Color(0.75, 0.5, 1.0))
	else:
		_ctext(150, "НОВЫЙ УРОВЕНЬ: %d" % m.level if m.pending_levels <= 1 else "НОВЫЙ УРОВЕНЬ (ещё выборов: %d)" % m.pending_levels, 40, Color(0.6, 1.0, 0.7))
	_ctext(190, "1–4 или клик — выбрать · R — переброс · «Закрепить» — будет в следующем выборе · «Исключить» — не выпадет до конца вылета", 17, Color(0.75, 0.8, 0.9))
	var w := 400.0
	var h := 330.0
	var gap := 28.0
	var x0 := (size.x - (w * 4 + gap * 3)) / 2.0
	var mp := ctrl.get_local_mouse_position()
	for i in m.offers.size():
		var c: Dictionary = m.offers[i]
		var r := Rect2(x0 + i * (w + gap), 220, w, h)
		var rar: Dictionary = Cards.RARITY[int(c["rarity"])]
		var rc: Color = Cards.EVO_COLOR if c["kind"] == "evolution" else rar["color"]
		var hover := r.has_point(mp)
		ctrl.draw_rect(r, Color(0.07, 0.09, 0.13, 0.96))
		ctrl.draw_rect(Rect2(r.position, Vector2(w, 34)), Color(rc.r, rc.g, rc.b, 0.25))
		ctrl.draw_rect(r, rc if hover else Color(rc.r, rc.g, rc.b, 0.7), false, 4.0 if hover else 3.0)
		_buttons.append([r, "card:%d" % i])
		_text(Vector2(r.position.x + 16, r.position.y + 24), "%d · %s" % [i + 1, rar["name"]], 18, rc)
		var cc: Color = Cards.CAT_COLORS.get(c["cat"], Color.WHITE)
		_text(Vector2(r.position.x, r.position.y + 24), c["cat"], 16, cc, HORIZONTAL_ALIGNMENT_RIGHT, w - 16.0)
		_para(Vector2(r.position.x + 18, r.position.y + 66), c["title"], w - 36.0, 22, Color.WHITE)
		if c.get("course", false): # 3.2: карточка ведёт к курсу
			ctrl.draw_colored_polygon(PackedVector2Array([r.position + Vector2(w - 70, 34), r.position + Vector2(w, 34), r.position + Vector2(w, 104)]), Color(1.0, 0.8, 0.25, 0.9))
			_text(Vector2(r.position.x + w - 46, r.position.y + 56), "▲", 18, Color(0.15, 0.1, 0.02))
			_text(Vector2(r.position.x, r.position.y + h - 14), "▲ КУРС +1", 15, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, w - 14.0)
		var ty := r.position.y + 136.0
		if c.get("tags", "") != "":
			_tag_chips(Vector2(r.position.x + 18, ty), Prog.card_tags(m.player, c), c["kind"] == "evolution")
			ty += 26.0
		_para(Vector2(r.position.x + 18, ty + 8), c["desc"], w - 36.0, 16)
		var is_locked: bool = not m.locked.is_empty() and m.locked["id"] == c["id"]
		if is_locked:
			_text(Vector2(r.position.x, r.position.y + h - 14), "ЗАКРЕПЛЕНА", 16, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)
		# кнопки под карточкой
		var by := r.position.y + h + 10
		_button(Rect2(r.position.x, by, w / 2.0 - 5, 40), "Открепить" if is_locked else "Закрепить", "lock:%d" % i, 17)
		if m.bans > 0:
			_button(Rect2(r.position.x + w / 2.0 + 5, by, w / 2.0 - 5, 40), "Исключить", "ban:%d" % i, 17)
	var ry := 640.0
	if m.rerolls > 0:
		_button(Rect2(size.x / 2.0 - 370, ry, 360, 46), "Переброс (R) — осталось %d" % m.rerolls, "reroll", 19)
		if m.player.has_course():
			_button(Rect2(size.x / 2.0 + 10, ry, 360, 46), "Сменить курс (−1 переброс)", "change_course", 19)
	else:
		_ctext(ry + 30, "Перебросов не осталось (+1 за каждого аса)", 18, Color(0.6, 0.62, 0.7))
	_ctext(ry + 76, "Исключений осталось: %d (+1 за аса)%s" % [m.bans, ("   ·   Исключены: " + ", ".join(PackedStringArray(m.banned.values()))) if not m.banned.is_empty() else ""], 16, Color(0.75, 0.75, 0.85))
	# 3.1: ближайшие связки — что добрать, чтобы открыть
	var y := ry + 112.0
	if m.player.has_course():
		var sd := Cards.syn_def(m.player, m.player.course)
		_ctext(y, "Курс: «%s» (слот %d из 3) — %s" % [sd["title"], m.player.syn.size() + 1, sd["short"]], 18, Menu.C_AMBER)
		y += 30.0
		_cond_line(Vector2(size.x / 2.0, y), {"title": "условия", "conds": Cards.cond_list(m.player, m.player.course)})


## Чипы тегов карточки: цвет тега, «Ракеты 3 → 4»
func _tag_chips(pos: Vector2, tags: Array, evo := false) -> void:
	var x := pos.x
	var p := Main.I.player
	for t in tags:
		var col: Color = Prog.TAGS[t]["color"]
		var label := "%s %d → %d" % [Prog.tag_title(t), p.tag(t), p.tag(t) + (2 if evo else 1)]
		var tw := ui_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.2))
		ctrl.draw_rect(Rect2(x, pos.y, 4, 22), col)
		_text(Vector2(x + 10, pos.y + 16), label, 14, col.lightened(0.3))
		x += tw + 8.0


## Пауза: очки тегов, нашивки, связки, эволюции
func _tags_panel(p: Player, pos: Vector2, w: float) -> void:
	var x := pos.x
	var cw := w / Prog.TAG_ORDER.size()
	for t in Prog.TAG_ORDER:
		var col: Color = Prog.TAGS[t]["color"]
		var n := p.tag(t)
		var r := Rect2(x + 4, pos.y, cw - 8, 112)
		ctrl.draw_rect(r, Color(0.05, 0.055, 0.06, 0.88))
		ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.12 if n > 0 else 0.04))
		ctrl.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), col if n > 0 else Color(1, 1, 1, 0.1))
		_text(Vector2(r.position.x + 8, r.position.y + 22), "%s  %d" % [Prog.tag_title(t), n], 16, col.lightened(0.25) if n > 0 else Color(0.5, 0.52, 0.58))
		var pl := p.patch(t)
		var nxt: int = Prog.PATCH_AT[pl] if pl < 2 else -1
		var line := ("нашивка %s" % Prog.ROMAN[pl]) if pl > 0 else ""
		if nxt > 0:
			line += (" · " if pl > 0 else "") + "%s на %d" % [Prog.ROMAN[pl + 1], nxt]
		_text(Vector2(r.position.x + 8, r.position.y + 42), line, 13, Color(0.8, 0.82, 0.88))
		if pl > 0:
			_para(Vector2(r.position.x + 8, r.position.y + 54), Prog.PATCHES[t][pl - 1], r.size.x - 14, 11, Color(0.7, 0.72, 0.78))
		x += cw
	var extra := PackedStringArray()
	for id in p.syn:
		if Cards.SYNERGIES.has(id):
			extra.append("«%s»" % Cards.SYNERGIES[id]["title"])
		else:
			extra.append("«%s»" % PlaneClasses.SKILL3[p.skill3]["syn"]["title"])
	var ev := PackedStringArray()
	for wv in p.evo_times:
		ev.append(Prog.EVOS[wv]["title"])
	ctrl.draw_rect(Rect2(pos.x, pos.y + 116, w, 96), Color(0.05, 0.055, 0.06, 0.8))
	_text(Vector2(pos.x + 8, pos.y + 138), "Связки: %s   ·   Эволюции: %s   ·   Навык: %s %s" % [
		", ".join(extra) if not extra.is_empty() else "нет", ", ".join(ev) if not ev.is_empty() else "нет",
		p.s3_def()["title"], Prog.ROMAN[p.s3_lvl()]], 16, Menu.C_AMBER)


# ---------- Подвесы и пауза ----------

func _loadout(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.65))
	_ctext(180, "ПАУЗА · ПОДВЕСЫ", 40, Color.WHITE)
	_ctext(220, "Клик по приоритету — сменить, по какой цели стреляет группа", 20, Color(0.75, 0.8, 0.9))
	var p := m.player
	var w := 1000.0
	var x := (size.x - w) / 2.0
	var y := 260.0
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		var r := Rect2(x, y, w, 64)
		_panel(r, false)
		_text(Vector2(x + 20, y + 28), g.label(), 22, Color.WHITE if not g.is_empty() else Color(0.6, 0.62, 0.7))
		if not g.is_empty():
			_text(Vector2(x + 20, y + 52), Weapons.DEFS[g.weapon]["desc"], 15, Color(0.75, 0.8, 0.9))
			if Weapons.DEFS[g.weapon]["uses_priority"]:
				_button(Rect2(x + w - 290, y + 12, 270, 40), "Цель: %s" % Weapons.PRIORITY_NAMES[g.priority], "prio:%d" % gi, 18)
			if g.uses_trigger():
				_button(Rect2(x + w - 290, y + 12, 270, 40), "Пуск: %s" % ("авто" if g.trigger == "auto" else "по кнопке (ПКМ)"), "trig:%d" % gi, 18)
		y += 76.0
	y += 10.0
	_ctext(y + 10, "Курсовое: урон ×%.2f · темп ×%.2f   ·   Подвесы: перезарядка ×%.2f   ·   Скорость ×%.2f · Манёвр ×%.2f · Подбор ×%.2f" % [
		float(p.cls["gun_dmg"]) * p.mods["gun_dmg"], float(p.cls["gun_rate"]) * p.mods["gun_rate"], p.mods["hp_cd"],
		float(p.cls["speed"]) * p.mods["speed"], float(p.cls["turn"]) * p.mods["turn"], p.mods["pickup"]], 17, Color(0.85, 0.88, 0.95))
	_tags_panel(p, Vector2(x, y + 36), w)
	if not p.cards_log.is_empty():
		_para(Vector2(x + 8, y + 186), "Карточки: " + ", ".join(PackedStringArray(p.cards_log)), w, 15, Color(0.7, 0.75, 0.85))
	var bx := (size.x - 960) / 2.0
	_button(Rect2(bx - 165, size.y - 150, 300, 50), "Продолжить (Esc / Tab)", "resume")
	_button(Rect2(bx + 165, size.y - 150, 300, 50), "Связки и эволюции", "codex")
	_button(Rect2(bx + 495, size.y - 150, 300, 50), "Настройки", "pause_settings")
	_button(Rect2(bx + 825, size.y - 150, 300, 50), "В главное меню", "to_menu")


# ---------- Итоги вылета ----------

func _result(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.78))
	var t := int(m.run_time)
	var top := 110.0
	if m.state == "evac":
		_ctext(top, "ЭВАКУАЦИЯ УСПЕШНА", 48, Color(0.5, 1.0, 0.6))
	else:
		_ctext(top, "САМОЛЁТ СБИТ", 48, Color(1, 0.5, 0.4))
	_ctext(top + 44, "%s · время %02d:%02d · уровень %d · сбито %d · асов %d" % [PlaneClasses.DATA[m.cls_id]["title"], t / 60, t % 60, m.level, m.kills, m.bosses_killed], 24, Color.WHITE)
	var kept_note := "100% — эвакуация" if m.state == "evac" else "50% — гибель без эвакуации"
	_ctext(top + 80, "Запчасти: %d из %d (%s)" % [m.parts_kept, int(m.parts), kept_note], 22, Color(0.95, 0.85, 0.55))

	var colw := 500.0
	var lx := 90.0
	var rx := 650.0
	var y0 := top + 140.0
	var hc := Color(0.95, 0.95, 1.0)
	_text(Vector2(lx, y0), "ПОЛУЧЕНО УРОНА: %d" % m.total("taken"), 24, Color(1.0, 0.72, 0.68))
	var y := y0 + 36.0
	for k in ["таран", "пули", "ракеты"]:
		_row(lx, y, colw, k, m.stat("taken", k), m.total("taken"), Color(1.0, 0.45, 0.4))
		y += 30.0
	y += 12.0
	_text(Vector2(lx, y), "От кого:", 19, hc)
	y += 28.0
	for k in ["дроны", "камикадзе", "перехватчики", "ракетоносцы", "ПВО", "ас-соперник", "асы"]:
		_row(lx, y, colw, k, m.stat("taken_by", k), m.total("taken"), Color(1.0, 0.6, 0.4))
		y += 30.0

	_text(Vector2(rx, y0), "НАНЕСЕНО УРОНА: %d" % m.total("dealt"), 24, Color(0.72, 1.0, 0.78))
	y = y0 + 36.0
	var dealt: Dictionary = m.stats["dealt"]
	var keys := dealt.keys()
	keys.sort_custom(func(a, b): return float(dealt[a]) > float(dealt[b]))
	for k in keys.slice(0, 8):
		_row(rx, y, colw, k, m.stat("dealt", k), m.total("dealt"), Color(0.45, 0.9, 0.55))
		y += 30.0
	y += 12.0
	var acc := 0.0 if m.shots == 0 else 100.0 * m.hits / m.shots
	_text(Vector2(rx, y), "Точность курсового: %d%%  ·  пик «оборотов»: +%d%%" % [int(acc), int(round(m.peak_rev * 100.0))], 18, hc)
	y += 26.0
	_text(Vector2(rx, y), "Сбито: дроны %d · камик. %d · перехв. %d · ракетон. %d · асы %d" % [m.stat("kills_by", "дроны"), m.stat("kills_by", "камикадзе"), m.stat("kills_by", "перехватчики"), m.stat("kills_by", "ракетоносцы"), m.stat("kills_by", "асы")], 18, hc)
	y += 26.0
	_text(Vector2(rx, y), "Сбито ракет противоракетами: %d · срывов захвата: %d" % [int(m.counters.get("intercepted", 0)), int(m.counters.get("locks_broken", 0))], 18, hc)
	y += 26.0
	_text(Vector2(rx, y), "На волоске: %d · лучшая серия: %d · сбито с хвоста: %d" % [m.near_misses, m.best_streak, m.tail_kills], 18, Color(0.7, 0.95, 1.0))
	y += 26.0
	_text(Vector2(rx, y), "Активности выполнены: %d · проход на форсаже: %d урона" % [m.activities_done, m.stat("dealt", "проход на форсаже")], 18, Color(0.7, 0.95, 1.0))

	y += 34.0
	# 3.2: связки вылета — время открытия и урон
	if not m.player.syn.is_empty():
		_text(Vector2(rx, y), "Связки:", 19, Menu.C_AMBER)
		for id in m.player.syn:
			y += 24.0
			var sd := Cards.syn_def(m.player, id)
			var sdmg := m.stat("dealt", "связка: " + String(sd["title"]).to_lower())
			var tt := int(float(m.player.syn[id]))
			_text(Vector2(rx + 12, y), "«%s» — %d:%02d · урон %d" % [sd["title"], tt / 60, tt % 60, sdmg], 17, Color(1.0, 0.9, 0.6))
	_meta_panel(m, Rect2(1220, top + 130, 620, 560))
	var cy := 780.0
	_para(Vector2(90, cy), "Карточки: " + (", ".join(PackedStringArray(m.player.cards_log)) if not m.player.cards_log.is_empty() else "—"), 1740.0, 15, Color(0.75, 0.8, 0.9))
	var bx := size.x / 2.0 - 690.0
	_button(Rect2(bx, size.y - 150, 320, 54), "R — ещё вылет", "restart", 22)
	_button(Rect2(bx + 350, size.y - 150, 320, 54), "H — в ангар", "to_hangar", 22)
	_button(Rect2(bx + 700, size.y - 150, 320, 54), "C — сменить самолёт", "change_class", 22)
	_button(Rect2(bx + 1050, size.y - 150, 320, 54), "В главное меню", "to_menu", 22)
	if Main.REPORT_URL != "":
		if m.report_sent:
			_text(Vector2(bx + 1050, size.y - 172), "✓ Отчёт принят — спасибо!", 19, Color(0.6, 1.0, 0.6))
		else:
			_button(Rect2(bx + 1050, size.y - 222, 320, 54), "ОТПРАВИТЬ ОТЧЁТ", "report_open", 22)


func _row(x: float, y: float, w: float, label: String, v: int, tot: int, col: Color) -> void:
	var frac := 0.0 if tot <= 0 else float(v) / float(tot)
	_text(Vector2(x, y), label, 18, Color(0.85, 0.88, 0.95))
	var bx := x + 180.0
	var bw := w - 180.0 - 70.0
	ctrl.draw_rect(Rect2(bx, y - 14.0, bw, 14.0), Color(1, 1, 1, 0.08))
	ctrl.draw_rect(Rect2(bx, y - 14.0, bw * frac, 14.0), col)
	_text(Vector2(bx + bw + 10.0, y), str(v), 18, Color.WHITE)


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
	if p.on_tail():
		_ctext(size.y / 2.0 + 120.0, "НА ХВОСТЕ: курсовое +50%", 22, Color(1.0, 0.9, 0.4))
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
			_edge_arrow(xf * site.global_position, rect, size, Color(1.0, 0.85, 0.3), 1.8)
			var d := int(p.global_position.distance_to(site.global_position))
			var s: String
			if site.failed:
				s = "Позиция ПВО устояла · осталось целей: %d" % site.left()
			elif site.active:
				s = "ПОЗИЦИЯ ПВО: %d с · целей: %d" % [int(ceil(site.timer)), site.left()]
			else:
				s = "Позиция ПВО: %d м — подлетите, чтобы начать" % (d / 10)
			_ctext(276, s, 22, Color(1.0, 0.85, 0.4))
			if not site.failed:
				_ctext(302, "Награда: выбор из редких карточек + 40 запчастей", 17, Color(0.85, 0.75, 1.0))
		elif node is RivalAce:
			var ace := node as RivalAce
			_edge_arrow(xf * ace.global_position, rect, size, Color(1.0, 0.25, 0.3), 1.8)
			_ctext(276, "ДОГФАЙТ: ас «%s» · уйдёт через %d с" % [ace.callsign, int(ceil(ace.life))], 22, Color(1.0, 0.6, 0.6))
			_ctext(302, "Награда: выбор из редких карточек", 17, Color(0.85, 0.75, 1.0))
			if ace.threatening() and int(Time.get_ticks_msec() / 200) % 2 == 0:
				_ctext(size.y / 2.0 - 110.0, "ХВОСТ! Сбрось газ (S) или манёвр", 30, Color(1.0, 0.3, 0.25))
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


# ---------- 3.1: справочник связок и эволюций ----------

## Условия связки: [[текст, выполнено?], …]; p == null — без прогресса (из главного меню)
func _syn_conds(p: Player, s: Dictionary, skill := false) -> Array:
	if p != null:
		var sid: String = s.get("id", "")
		if sid == "":
			for k in Cards.SYNERGIES:
				if Cards.SYNERGIES[k] == s:
					sid = k
		return Cards.cond_list(p, sid)
	var out0: Array = []
	var c0: Dictionary = Cards.SLOT_COST[0]
	if skill:
		out0.append(["доводка I/II/III", false])
	if s.has("tag"):
		out0.append(["%s %d/%d/%d" % [Prog.tag_title(s["tag"]), Cards.SLOT_COST[0]["main"], Cards.SLOT_COST[1]["main"], Cards.SLOT_COST[2]["main"]], false])
	if s.has("tag2"):
		out0.append(["%s %d/%d/%d" % [Prog.tag_title(s["tag2"]), Cards.SLOT_COST[0]["second"], Cards.SLOT_COST[1]["second"], Cards.SLOT_COST[2]["second"]], false])
	if s.has("w") and s["w"] is Array:
		out0.append(["%s ур. %d/%d/%d" % ["/".join(PackedStringArray((s["w"] as Array).map(func(x): return String(Weapons.DEFS[x]["short"])))), c0["lvl"], Cards.SLOT_COST[1]["lvl"], Cards.SLOT_COST[2]["lvl"]], false])
	if s.has("req_mods"):
		out0.append(["%s ×1/2/3" % " + ".join(PackedStringArray((s["req_mods"] as Array).map(func(x): return String(Cards.MODULES[x]["title"])))), false])
	if s.get("wingmen", false):
		out0.append(["ведомые 1/1/2", false])
	return out0


func _syn_conds_old(p: Player, s: Dictionary, skill := false) -> Array:
	var out: Array = []
	if skill and p != null:
		out.append(["доводка навыка ≥ I (сейчас %s)" % (Prog.ROMAN[p.s3_lvl()] if p.s3_lvl() > 0 else "0"), p.s3_lvl() >= 1])
	elif skill:
		out.append(["доводка навыка ≥ I", false])
	if s.has("w"):
		var lv := 0
		if p != null:
			for g in p.groups:
				if (g as Hardpoint).weapon == s["w"]:
					lv = maxi(lv, (g as Hardpoint).level)
		var txt := "%s ур. %d" % [Weapons.DEFS[s["w"]]["short"], int(s["lvl"])]
		if p != null:
			txt += " (нет)" if lv == 0 else " (ур. %d)" % lv
		out.append([txt, p != null and lv >= int(s["lvl"])])
	if s.get("wingmen", false):
		var n := p.permanent_wingmen() if p != null else 0
		out.append(["ведомый" + ((" (%d)" % n) if p != null else ""), n > 0])
	for pair in [["tag", "n"], ["tag2", "n2"]]:
		if s.has(pair[0]):
			var have := p.tag(s[pair[0]]) if p != null else 0
			var t2 := "%s %d" % [Prog.tag_title(s[pair[0]]), int(s[pair[1]])]
			if p != null:
				t2 = "%s %d/%d" % [Prog.tag_title(s[pair[0]]), have, int(s[pair[1]])]
			out.append([t2, p != null and have >= int(s[pair[1]])])
	return out


func _progress(conds: Array) -> float:
	if conds.is_empty():
		return 0.0
	var ok := 0
	for c in conds:
		if c[1]:
			ok += 1
	return float(ok) / conds.size()


## Ближайшие к открытию связки (у которых есть оружие/ведомые), по доле выполненных условий
func _near_synergies(p: Player, n: int) -> Array:
	var arr: Array = []
	for id in Cards.SYNERGIES:
		var s: Dictionary = Cards.SYNERGIES[id]
		if p.syn.has(id):
			continue
		var conds := _syn_conds(p, s)
		if s.has("w") and not conds[0][1] and String(conds[0][0]).ends_with("(нет)"):
			continue
		arr.append({"title": s["title"], "conds": conds, "k": _progress(conds)})
	var ss: Dictionary = PlaneClasses.SKILL3[p.skill3]["syn"]
	if not p.syn.has(ss["id"]):
		var c2 := _syn_conds(p, ss, true)
		arr.append({"title": ss["title"], "conds": c2, "k": _progress(c2)})
	arr.sort_custom(func(a, b): return float(a["k"]) > float(b["k"]))
	return arr.slice(0, n)


## Строка «Название: условие ✓ · условие 2/3» по центру
func _cond_line(center: Vector2, e: Dictionary) -> void:
	var parts: Array = [["«%s»: " % e["title"], Menu.C_AMBER]]
	for c in e["conds"]:
		parts.append([("✓ " if c[1] else "") + String(c[0]) + "   ", Color(0.5, 1.0, 0.6) if c[1] else Color(0.8, 0.82, 0.88)])
	var total := 0.0
	for pt in parts:
		total += ui_font().get_string_size(pt[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var x := center.x - total / 2.0
	for pt in parts:
		_text(Vector2(x, center.y), pt[0], 16, pt[1])
		x += ui_font().get_string_size(pt[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x


## Чипы условий в строку; вернёт x после последнего
func _cond_chips(pos: Vector2, conds: Array) -> float:
	var x := pos.x
	for c in conds:
		var label := ("✓ " if c[1] else "") + String(c[0])
		var tw := ui_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0
		var col := Color(0.45, 1.0, 0.55) if c[1] else Color(0.75, 0.78, 0.85)
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.14))
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.5), false, 1.0)
		_text(Vector2(x + 8, pos.y + 16), label, 14, col)
		x += tw + 6.0
	return x


func _codex(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.04, 0.93))
	var p: Player = m.player if (m.codex_back == "paused" and is_instance_valid(m.player)) else null
	_text(Vector2(0, 70), "СПРАВОЧНИК: СВЯЗКИ И ЭВОЛЮЦИИ", 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_ctext(104, "За вылет — до 3 связок. Цель выбирается курсом; пороги растут по слотам (слот 1 / 2 / 3). Полное описание — на экране выбора курса." if p == null
		else "Зелёное — выполнено (для текущего слота %d). Открыть можно только связку курса; сменить курс — за 1 переброс." % (p.syn.size() + 1), 17, Color(0.75, 0.8, 0.9))
	_button(Rect2(64, 40, 220, 46), "‹ Назад (Esc)", "codex_back", 18)
	# левая колонка: связки оружия
	var x := 70.0
	var y := 150.0
	_text(Vector2(x, y), "СВЯЗКИ ОРУЖИЯ", 22, Menu.C_AMBER)
	y += 14.0
	var ids: Array = Cards.SYNERGIES.keys()
	if p != null:
		ids.sort_custom(func(a, b):
			var oa := 2.0 if p.syn.has(a) else _progress(_syn_conds(p, Cards.SYNERGIES[a]))
			var ob := 2.0 if p.syn.has(b) else _progress(_syn_conds(p, Cards.SYNERGIES[b]))
			return oa > ob)
	for id in ids:
		var s: Dictionary = Cards.SYNERGIES[id]
		var opened: bool = p != null and p.syn.has(id)
		ctrl.draw_rect(Rect2(x - 8, y + 4, 860, 70), Color(0.45, 1.0, 0.55, 0.08) if opened else Color(1, 1, 1, 0.03))
		_text(Vector2(x, y + 26), ("✓ " if opened else "") + s["title"], 19, Color(0.5, 1.0, 0.6) if opened else Color(1.0, 0.85, 0.5))
		_text(Vector2(x + 230, y + 26), String(s["short"]).capitalize() if false else String(s["short"]), 15, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_LEFT, 620)
		_cond_chips(Vector2(x + 230, y + 40), _syn_conds(p, s))
		y += 76.0
	# правая колонка: связки навыков и эволюции
	x = 990.0
	y = 150.0
	_text(Vector2(x, y), "СВЯЗКИ НАВЫКОВ" + (" — %s" % PlaneClasses.DATA[p.cls_id]["title"] if p != null else ""), 22, Menu.C_AMBER)
	y += 14.0
	var skills: Array = []
	if p != null:
		skills = PlaneClasses.CLASS_SKILLS[p.cls_id]
	else:
		for c in PlaneClasses.LIST:
			skills.append_array(PlaneClasses.CLASS_SKILLS[c])
	for sk in skills:
		var sd: Dictionary = PlaneClasses.SKILL3[sk]
		var ss: Dictionary = sd["syn"]
		var mine: bool = p != null and p.skill3 == sk
		var opened2: bool = p != null and p.syn.has(ss["id"])
		var hh := 62.0 if p != null else 40.0
		ctrl.draw_rect(Rect2(x - 8, y + 4, 860, hh - 4), Color(0.45, 1.0, 0.55, 0.08) if opened2 else Color(1, 1, 1, 0.03 if mine or p == null else 0.015))
		var head := "%s → «%s»: %s" % [sd["title"], ss["title"], ss["desc"]]
		_text(Vector2(x, y + 24), ("✓ " if opened2 else "") + head, 15, (Color(0.5, 1.0, 0.6) if opened2 else Color(1.0, 0.85, 0.5)) if (mine or p == null) else Color(0.55, 0.57, 0.62), HORIZONTAL_ALIGNMENT_LEFT, 850)
		if p != null:
			if mine:
				_cond_chips(Vector2(x, y + 32), _syn_conds(p, ss, true))
			else:
				_text(Vector2(x, y + 48), "другой навык — выбирается перед вылетом", 13, Color(0.5, 0.52, 0.58))
		else:
			_text(Vector2(x + 860, y + 24), _cond_text(ss), 13, Color(0.7, 0.72, 0.78), HORIZONTAL_ALIGNMENT_RIGHT, 0)
		y += hh
	y += 20.0
	_text(Vector2(x, y), "ЭВОЛЮЦИИ (оружие ур. 5 + модуль-катализатор, с 7:00)", 22, Cards.EVO_COLOR)
	y += 14.0
	for w in Prog.EVOS:
		var ev: Dictionary = Prog.EVOS[w]
		var conds: Array = []
		var wname: String = "Курсовое" if w == "gun" else Weapons.DEFS[w]["short"]
		var done := false
		if w != "gun":
			var lv := 0
			for g in (p.groups if p != null else []):
				if (g as Hardpoint).weapon == w:
					lv = maxi(lv, (g as Hardpoint).level)
					done = done or (g as Hardpoint).evo
			conds.append(["%s ур. 5%s" % [wname, (" (ур. %d)" % lv) if (p != null and lv > 0) else (" (нет)" if p != null else "")], lv >= 5])
		else:
			done = p != null and p.gun_evo
		for mid in ev["cat"]:
			var have := int(p.taken.get(mid, 0)) if p != null else 0
			conds.append(["%s %s" % [Cards.MODULES[mid]["title"], ("%d/%d" % [have, int(ev["cat"][mid])]) if p != null else "×%d" % int(ev["cat"][mid])], p != null and have >= int(ev["cat"][mid])])
		ctrl.draw_rect(Rect2(x - 8, y + 4, 860, 56), Color(1.0, 0.95, 0.7, 0.08) if done else Color(1, 1, 1, 0.03))
		_text(Vector2(x, y + 24), ("✓ " if done else "") + "%s → %s" % [wname, ev["title"]], 16, Cards.EVO_COLOR if not done else Color(0.5, 1.0, 0.6))
		_cond_chips(Vector2(x + 330, y + 8), conds)
		y += 60.0


func _cond_text(s: Dictionary) -> String:
	var parts := PackedStringArray(["доводка ≥ I"])
	if s.has("w"):
		parts.append("%s ур. %d" % [Weapons.DEFS[s["w"]]["short"], int(s["lvl"])])
	if s.has("tag"):
		parts.append("%s %d" % [Prog.tag_title(s["tag"]), int(s["n"])])
	return " + ".join(parts)



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
	_text(Vector2(pos.x, y + 14), "Курс: «%s»" % sd2["title"], 16, col2.lightened(0.2))
	ctrl.draw_rect(Rect2(pos.x + 190, y + 2, 220, 14), Color(0, 0, 0, 0.5))
	var a := 1.0 if not ready else (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01))
	ctrl.draw_rect(Rect2(pos.x + 190, y + 2, 220 * k, 14), Color(col2.r, col2.g, col2.b, a))
	var parts := PackedStringArray()
	for c in conds:
		parts.append(("✓" if c[1] else "") + String(c[0]))
	_text(Vector2(pos.x, y + 36), "Связка придёт в следующем выборе!" if ready else " · ".join(parts), 14,
		Color(1.0, 0.9, 0.4) if ready else Color(0.85, 0.87, 0.92))


func _course_pick(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.72))
	var p := m.player
	var slot := p.syn.size() + 1
	_ctext(150, "ВЫБОР КУРСА — СВЯЗКА %d ИЗ 3" % slot, 40, Menu.C_AMBER)
	_ctext(192, "Курс — цель вылета: карточки, которые к нему ведут, отмечены «▲ КУРС» и выпадают чаще. Открыть можно только связку курса.", 17, Color(0.8, 0.84, 0.92))
	_ctext(218, "Пороги растут: слот 1 — %d / слот 2 — %d / слот 3 — %d очков главного тега. Курс можно сменить позже за 1 переброс." % [
		Cards.SLOT_COST[0]["main"], Cards.SLOT_COST[1]["main"], Cards.SLOT_COST[2]["main"]], 16, Color(0.7, 0.74, 0.82))
	var w := 520.0
	var h := 400.0
	var gap := 36.0
	var n := m.course_offers.size()
	var x0 := (size.x - (w * n + gap * (n - 1))) / 2.0
	var mp := ctrl.get_local_mouse_position()
	var kinds := ["По вашему оружию", "Связка навыка", "Новый путь"]
	for i in n:
		var id: String = m.course_offers[i]
		var sd := Cards.syn_def(p, id)
		var col: Color = sd.get("color", Menu.C_AMBER)
		var r := Rect2(x0 + i * (w + gap), 250, w, h)
		var hover := r.has_point(mp)
		ctrl.draw_rect(r, Color(0.07, 0.08, 0.1, 0.96))
		ctrl.draw_rect(Rect2(r.position, Vector2(w, 40)), Color(col.r, col.g, col.b, 0.3))
		ctrl.draw_rect(r, col if hover else Color(col.r, col.g, col.b, 0.6), false, 4.0 if hover else 2.0)
		_buttons.append([r, "course:%d" % i])
		var kind: String = "Связка навыка" if sd.has("skill") else ("По вашему оружию" if i == 0 else "Новый путь")
		_text(Vector2(r.position.x + 18, r.position.y + 28), "%d · %s" % [i + 1, kind], 17, col.lightened(0.3))
		_text(Vector2(r.position.x + 18, r.position.y + 80), String(sd["title"]), 30, Color.WHITE)
		_para(Vector2(r.position.x + 18, r.position.y + 118), sd["desc"], w - 36.0, 17)
		var conds := Cards.cond_list(p, id)
		_text(Vector2(r.position.x + 18, r.position.y + 262), "Условия (слот %d):" % slot, 16, Color(0.8, 0.82, 0.88))
		var yy := r.position.y + 272.0
		for c in conds:
			_cond_chips(Vector2(r.position.x + 18, yy), [c])
			yy += 28.0
		_text(Vector2(r.position.x + 18, r.end.y - 16), "≈ %d карточек по курсу" % Cards.cards_left(conds), 16, Menu.C_AMBER)
	_ctext(690, "1–3 или клик — выбрать курс", 17, Color(0.75, 0.8, 0.9))


# ---------- 3.2: итоги для ангара ----------

func _meta_panel(m: Main, r: Rect2) -> void:
	var a: Dictionary = m.meta_award
	_panel(r, false)
	if a.is_empty():
		return
	var x := r.position.x + 24.0
	var y := r.position.y + 40.0
	var w := r.size.x - 48.0
	var t := m.result_t
	_text(Vector2(x, y), "ИТОГИ ДЛЯ АНГАРА", 24, Menu.C_AMBER)
	if a.get("short", false):
		_text(Vector2(x, y + 40), "Слишком короткий вылет — без начисления", 18, Color(0.8, 0.8, 0.85))
		return
	var rows: Array = []
	rows.append(["ЗАПЧАСТИ", "", Menu.C_AMBER])
	rows.append(["Добыча вылета (%s)" % ("100%" if m.state == "evac" else "50%"), "+%d" % m.parts_kept, Color(0.95, 0.85, 0.55)])
	rows.append(["Жалованье техникам", "+%d" % int(a["wage"]), Color(0.95, 0.85, 0.55)])
	rows.append(["Итого", "+%d   (всего %d)" % [int(a["parts_add"]), int(a["parts_after"])], Color.WHITE])
	rows.append(["ОПЫТ ЭКИПАЖА «%s»" % Profile.cls(m.cls_id)["callsign"], "", Color(0.6, 1.0, 0.7)])
	for l in a["xp_lines"]:
		rows.append([l[0], ("%+d" % int(l[1])), Color(0.75, 0.95, 0.8)])
	rows.append(["Итого опыта", "+%d" % int(a["xp_add"]), Color.WHITE])
	var shown := int(t / 0.18) + 1
	for i in mini(shown, rows.size()):
		y += 28.0
		var row: Array = rows[i]
		var head: bool = row[1] == ""
		_text(Vector2(x, y), row[0], 18 if head else 16, row[2])
		if not head:
			_text(Vector2(x, y), row[1], 16, row[2], HORIZONTAL_ALIGNMENT_RIGHT, w)
	if shown < rows.size():
		return
	# полоса опыта экипажа: заполняется до нового значения
	y += 40.0
	var lv := Profile.crew_lvl(m.cls_id)
	var pr := Profile.crew_progress(m.cls_id)
	var k := clampf((t - rows.size() * 0.18) / 0.6, 0.0, 1.0)
	ctrl.draw_rect(Rect2(x, y, w, 16), Color(0, 0, 0, 0.5))
	var frac := float(pr[0]) / maxf(float(pr[1]), 1.0) if int(pr[1]) > 0 else 1.0
	ctrl.draw_rect(Rect2(x, y, w * frac * k, 16), Color(0.5, 1.0, 0.6))
	y += 40.0
	var up: bool = int(a["lvl_after"]) > int(a["lvl_before"])
	_text(Vector2(x, y), ("Экипаж ур. %d → %d!" % [a["lvl_before"], a["lvl_after"]]) if up else "Экипаж ур. %d" % lv, 20,
		Color(1.0, 0.9, 0.4) if up else Color.WHITE)
	if int(pr[1]) > 0:
		_text(Vector2(x, y), "до ур. %d: %d" % [lv + 1, int(pr[1]) - int(pr[0])], 16, Color(0.75, 0.8, 0.88), HORIZONTAL_ALIGNMENT_RIGHT, w)
	for u in a["unlocked"]:
		y += 26.0
		_text(Vector2(x, y), "ОТКРЫТО: " + String(u), 16, Color(1.0, 0.85, 0.4))
	if String(a.get("hint_buy", "")) != "":
		y += 30.0
		_text(Vector2(x, y), "Можно купить: " + String(a["hint_buy"]), 17, Color(0.6, 0.95, 1.0))


# ---------- 3.2: ангар ----------

func _hangar(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.05, 0.94))
	var c := m.hangar_cls
	_text(Vector2(0, 66), "АНГАР", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_text(Vector2(0, 66), "Запчасти: %d   " % Profile.parts(), 26, Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60)
	_button(Rect2(60, 34, 200, 46), "‹ Меню (Esc)", "hg:back", 18)
	# классы
	var bx := size.x / 2.0 - 3 * 190.0
	for i in 3:
		var id: String = PlaneClasses.LIST[i]
		var r := Rect2(bx + i * 390.0, 100, 370, 64)
		var on := id == c
		var col: Color = PlaneClasses.DATA[id]["color"]
		ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.22 if on else 0.06))
		ctrl.draw_rect(r, col if on else Color(1, 1, 1, 0.15), false, 3.0 if on else 1.0)
		_buttons.append([r, "hg:cls:" + id])
		_text(Vector2(r.position.x + 16, r.position.y + 28), String(PlaneClasses.DATA[id]["title"]), 19, col)
		var pp := Profile.perk_points(id)
		_text(Vector2(r.position.x + 16, r.position.y + 52), "Экипаж ур. %d%s" % [Profile.crew_lvl(id), ("  · очков перков: %d" % pp) if pp > 0 else ""], 15, Color(0.85, 0.88, 0.95))
	# вкладки
	var tabs := [["plane", "САМОЛЁТ"], ["weapons", "ОРУЖИЕ (общее)"], ["crew", "ЭКИПАЖ"]]
	for i in tabs.size():
		var r2 := Rect2(size.x / 2.0 - 450 + i * 300.0, 182, 290, 44)
		var on2: bool = m.hangar_tab == tabs[i][0]
		ctrl.draw_rect(r2, Menu.C_AMBER if on2 else Color(1, 1, 1, 0.06))
		_text(Vector2(r2.position.x, r2.position.y + 30), tabs[i][1], 18, Color(0.08, 0.07, 0.05) if on2 else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
		_buttons.append([r2, "hg:tab:" + tabs[i][0]])
	var area := Rect2(120, 250, size.x - 240, size.y - 380)
	match m.hangar_tab:
		"plane":
			_hg_plane(c, area)
		"weapons":
			_hg_weapons(m, area)
		"crew":
			_hg_crew(c, area)
	_button(Rect2(size.x / 2.0 - 180, size.y - 110, 360, 56), "В ВЫЛЕТ — %s" % PlaneClasses.DATA[c]["title"], "hg:fly", 20)
	if Main.DEBUG:
		var dy := size.y - 110
		_text(Vector2(60, dy - 10), "ОТЛАДКА (тестовая сборка):", 14, Color(0.7, 0.7, 0.7))
		_button(Rect2(60, dy, 150, 40), "+1000 запч.", "hg:dbg_parts", 15)
		_button(Rect2(220, dy, 150, 40), "+1 ур. экипажа", "hg:dbg_lvl", 15)
		_button(Rect2(380, dy, 150, 40), "Открыть всё", "hg:dbg_all", 15)
		_button(Rect2(540, dy, 150, 40), "Сброс профиля", "hg:dbg_wipe", 15)


func _hg_plane(c: String, area: Rect2) -> void:
	# слева — самолёт ур. 1 / ур. 2
	var lx := area.position.x
	var lw := 560.0
	_panel(Rect2(lx, area.position.y, lw, area.size.y), false)
	var bought: bool = bool(Profile.cls(c)["plane2"])
	for lv in [1, 2]:
		var t := PlaneArt.plane_tex(c, lv)
		if t == null:
			continue
		var cx := lx + lw * (0.28 if lv == 1 else 0.72)
		var cy := area.position.y + 210.0
		var k := minf(300.0 / t.get_width(), 220.0 / t.get_height())
		ctrl.draw_set_transform(Vector2(cx, cy), -PI / 2.0, Vector2(k, k))
		ctrl.draw_texture(t, -t.get_size() / 2.0, Color(1, 1, 1, 1) if (lv == 1 or bought) else Color(0.25, 0.25, 0.28, 0.9))
		ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(Vector2(cx - 120, area.position.y + 390), "ур. %d" % lv, 18, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 240)
	var y := area.position.y + 430.0
	if bought:
		_text(Vector2(lx + 24, y), "Самолёт ур. 2 куплен: модернизация в полёте на %d-м уровне пилота" % int(Tuning.g("plane_lvl2_at")), 16, Color(0.6, 1.0, 0.7))
		_text(Vector2(lx + 24, y + 24), "даёт +20% прочности, +5% скорости и разворота, +1 переброс", 15, Color(0.8, 0.85, 0.9))
	else:
		_text(Vector2(lx + 24, y), "Самолёт ур. 2 — комплект модернизации", 18, Color.WHITE)
		_text(Vector2(lx + 24, y + 24), "Требует: экипаж ур. %d (сейчас %d) · %d запчастей" % [Profile.PLANE2_CREW, Profile.crew_lvl(c), Profile.PLANE2_COST], 15, Color(0.8, 0.85, 0.9))
		if Profile.can_buy_plane2(c):
			_button(Rect2(lx + 24, y + 40, 320, 46), "МОДЕРНИЗИРОВАТЬ — %d" % Profile.PLANE2_COST, "hg:plane2", 17)
	# справа — 6 узлов
	var rx := lx + lw + 30.0
	var rw := area.size.x - lw - 30.0
	var yy := area.position.y
	for id in Profile.NODE_ORDER:
		var nd: Dictionary = Profile.NODES[id]
		var lv2 := Profile.node(c, id)
		var r := Rect2(rx, yy, rw, 92)
		_panel(r, false)
		_text(Vector2(rx + 20, yy + 30), String(nd["title"]), 20, Color.WHITE)
		for i in 5:
			ctrl.draw_rect(Rect2(rx + 200 + i * 30, yy + 16, 24, 14), Menu.C_AMBER if i < lv2 else Color(1, 1, 1, 0.12))
		_text(Vector2(rx + 20, yy + 58), "за уровень: %s · сейчас ур. %d" % [nd["step"], lv2], 15, Color(0.8, 0.84, 0.9))
		if String(nd["note"]) != "":
			_text(Vector2(rx + 20, yy + 80), String(nd["note"]), 12, Color(0.6, 0.62, 0.68))
		if lv2 >= 5:
			_text(Vector2(rx, yy + 52), "МАКС.", 18, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, rw - 24)
		else:
			var price: int = Profile.NODE_COST[lv2]
			if Profile.can_buy_node(c, id):
				_button(Rect2(rx + rw - 250, yy + 24, 230, 44), "УЛУЧШИТЬ — %d" % price, "hg:node:" + id, 16)
			else:
				_text(Vector2(rx, yy + 52), "%d (не хватает %d)" % [price, price - Profile.parts()], 16, Color(0.65, 0.65, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, rw - 24)
		yy += 102.0


func _hg_weapons(m: Main, area: Rect2) -> void:
	var lx := area.position.x
	var y := area.position.y
	for w in Profile.WEAPON_ORDER:
		var r := Rect2(lx, y, 300, 70)
		var on: bool = m.hangar_w == w
		_panel(r, on)
		_buttons.append([r, "hg:wsel:" + w])
		var t := PlaneArt.weapon_tex(w)
		if t != null:
			var k := 54.0 / t.get_height()
			ctrl.draw_set_transform(Vector2(lx + 30, y + 35), 0.0, Vector2(k, k))
			ctrl.draw_texture(t, -t.get_size() / 2.0)
			ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(Vector2(lx + 60, y + 30), String(Weapons.DEFS[w]["short"]), 18, Color.WHITE if on else Color(0.85, 0.88, 0.95))
		var marks := ""
		for tier in [1, 2]:
			var st := Profile.tier_state(w, tier)
			marks += ("●" if st != "" and st != "?" else "○") + " "
		_text(Vector2(lx + 60, y + 54), marks + "○", 15, Menu.C_AMBER)
		y += 80.0
	var w2 := m.hangar_w
	var rx := lx + 340.0
	var rw := area.size.x - 340.0
	_text(Vector2(rx, area.position.y + 24), "%s — ветки улучшений (действуют, пока оружие на подвесе; общие для всех классов)" % Weapons.DEFS[w2]["title"], 18, Menu.C_AMBER)
	var yy := area.position.y + 50.0
	for tier in [1, 2, 3]:
		_text(Vector2(rx, yy + 20), "Ступень %d" % tier, 18, Color.WHITE)
		if tier == 3:
			_panel(Rect2(rx, yy + 32, rw, 90), false)
			_text(Vector2(rx + 20, yy + 84), "Особенность оружия — в разработке", 17, Color(0.6, 0.62, 0.68))
			break
		var st2 := Profile.tier_state(w2, tier)
		var locked: bool = tier == 2 and Profile.tier_state(w2, 1) == ""
		for oi in 2:
			var opt: Array = Profile.WBRANCH[w2][tier - 1][oi]
			var key := "a" if oi == 0 else "b"
			var r2 := Rect2(rx + oi * (rw / 2.0 + 5), yy + 32, rw / 2.0 - 5, 120)
			var picked := st2 == key
			_panel(r2, picked)
			if picked:
				ctrl.draw_rect(r2, Color(0.5, 1.0, 0.6), false, 3.0)
			_text(Vector2(r2.position.x + 18, r2.position.y + 32), String(opt[0]), 19, Color(0.6, 1.0, 0.7) if picked else Color.WHITE)
			_text(Vector2(r2.position.x + 18, r2.position.y + 60), String(opt[1]), 15, Color(0.8, 0.84, 0.9))
			if locked:
				_text(Vector2(r2.position.x + 18, r2.position.y + 98), "сначала выберите ступень 1", 14, Color(0.6, 0.62, 0.68))
			elif st2 == "?":
				_button(Rect2(r2.position.x + 18, r2.position.y + 74, 200, 38), "ВЫБРАТЬ (оплачено)", "hg:tier:%s:%d:%s" % [w2, tier, key], 14)
			elif st2 == "":
				var price: int = Profile.TIER_COST[tier - 1]
				if Profile.parts() >= price:
					_button(Rect2(r2.position.x + 18, r2.position.y + 74, 200, 38), "ВЗЯТЬ — %d" % price, "hg:tier:%s:%d:%s" % [w2, tier, key], 14)
				else:
					_text(Vector2(r2.position.x + 18, r2.position.y + 98), "%d запчастей" % price, 14, Color(0.65, 0.65, 0.7))
		if st2 != "" and st2 != "?":
			_button(Rect2(rx + rw - 260, yy, 260, 30), "переиграть — %d" % Profile.REDO_COST[tier - 1], "hg:redo:%s:%d" % [w2, tier], 13)
		yy += 170.0


func _hg_crew(c: String, area: Rect2) -> void:
	var cd: Dictionary = Profile.cls(c)
	var lx := area.position.x
	var lw := 460.0
	_panel(Rect2(lx, area.position.y, lw, area.size.y), false)
	var y := area.position.y + 40.0
	_text(Vector2(lx + 24, y), "Позывной: «%s»" % cd["callsign"], 22, Color.WHITE)
	_button(Rect2(lx + lw - 150, y - 28, 130, 38), "СМЕНИТЬ", "hg:callsign", 14)
	y += 34.0
	_text(Vector2(lx + 24, y), String(Profile.CREW[c]["crew"]), 17, Color(0.8, 0.84, 0.9))
	y += 40.0
	var lv := Profile.crew_lvl(c)
	var pr := Profile.crew_progress(c)
	_text(Vector2(lx + 24, y), "Экипаж ур. %d" % lv, 26, Color(0.6, 1.0, 0.7))
	y += 18.0
	ctrl.draw_rect(Rect2(lx + 24, y, lw - 48, 14), Color(0, 0, 0, 0.5))
	if int(pr[1]) > 0:
		ctrl.draw_rect(Rect2(lx + 24, y, (lw - 48) * float(pr[0]) / float(pr[1]), 14), Color(0.5, 1.0, 0.6))
		_text(Vector2(lx + 24, y + 36), "%d / %d до ур. %d" % [pr[0], pr[1], lv + 1], 15, Color(0.8, 0.84, 0.9))
	y += 70.0
	_para(Vector2(lx + 24, y), "Рост показателей: " + String(Profile.CREW[c]["stats"]), lw - 48, 15)
	y += 70.0
	_text(Vector2(lx + 24, y), "Открытия по уровню экипажа:", 16, Menu.C_AMBER)
	var unl := [[3, "2-й навык класса; самолёт ур. 2"], [4, "ведомый «Ласка»"], [5, "2-й слот навыка [F]"], [6, "перки 2-й ступени"], [7, "3-й навык класса"], [8, "ведомый «Грачонок»"]]
	for u in unl:
		y += 24.0
		_text(Vector2(lx + 24, y), ("✓ " if lv >= int(u[0]) else "· ") + "ур. %d — %s" % [u[0], u[1]], 15, Color(0.6, 1.0, 0.7) if lv >= int(u[0]) else Color(0.7, 0.72, 0.78))
	# перки
	var px := lx + lw + 30.0
	var pw := 820.0
	_text(Vector2(px, area.position.y + 24), "ПЕРКИ — очков: %d (на чётных уровнях)" % Profile.perk_points(c), 18, Menu.C_AMBER)
	_button(Rect2(px + pw - 200, area.position.y, 200, 34), "СБРОСИТЬ ПЕРКИ", "hg:perk_reset", 13)
	var cw := pw / 3.0
	for bi in 3:
		var br: Array = Profile.PERKS[c][bi]
		var bxx := px + bi * cw
		_text(Vector2(bxx + 10, area.position.y + 64), String(br[0]), 19, Color.WHITE)
		for ti in 4:
			var r := Rect2(bxx + 6, area.position.y + 80 + ti * 118, cw - 12, 108)
			if ti >= 2:
				_panel(r, false)
				_text(Vector2(r.position.x + 14, r.position.y + 60), "ступень %d — в разработке" % (ti + 1), 14, Color(0.55, 0.57, 0.62))
				continue
			var pk: Array = br[1][ti]
			var has: bool = (cd["perks"] as Array).has(pk[0])
			var can := not has and Profile.perk_points(c) > 0 and (ti == 0 or ((cd["perks"] as Array).has(br[1][0][0]) and lv >= Profile.PERK_T2_LVL))
			_panel(r, has)
			if has:
				ctrl.draw_rect(r, Color(0.5, 1.0, 0.6), false, 3.0)
			_buttons.append([r, "hg:perk:" + String(pk[0])])
			_text(Vector2(r.position.x + 14, r.position.y + 28), ("✓ " if has else "") + String(pk[1]), 17, Color(0.6, 1.0, 0.7) if has else (Color.WHITE if can else Color(0.65, 0.67, 0.72)))
			_para(Vector2(r.position.x + 14, r.position.y + 50), String(pk[2]), cw - 40, 13, Color(0.8, 0.84, 0.9))
			if ti == 1 and lv < Profile.PERK_T2_LVL:
				_text(Vector2(r.position.x + 14, r.end.y - 8), "с экипажа ур. %d" % Profile.PERK_T2_LVL, 12, Color(0.6, 0.62, 0.68))
	# слоты навыков
	var sx := px + pw + 30.0
	var sw := area.end.x - sx
	_text(Vector2(sx, area.position.y + 24), "НАВЫКИ КЛАССА", 18, Menu.C_AMBER)
	var sks: Array = cd["skills"]
	var yy := area.position.y + 50.0
	for slot in 2:
		var open := slot == 0 or Profile.slot2_open(c)
		_text(Vector2(sx, yy + 18), "Слот %d [%s]%s" % [slot + 1, "E" if slot == 0 else "F", "" if open else " — экипаж ур. %d" % Profile.SLOT2_LVL], 16, Color.WHITE if open else Color(0.6, 0.62, 0.68))
		yy += 26.0
		for sk in PlaneClasses.CLASS_SKILLS[c]:
			var r3 := Rect2(sx, yy, sw, 36)
			var unlocked := Profile.skill_unlocked(c, sk)
			var sel: bool = sks.size() > slot and sks[slot] == sk
			ctrl.draw_rect(r3, Color(0.55, 0.9, 0.55, 0.18) if sel else Color(1, 1, 1, 0.04))
			if open and unlocked:
				_buttons.append([r3, "hg:slot:%d:%s" % [slot, sk]])
			var i: int = PlaneClasses.CLASS_SKILLS[c].find(sk)
			_text(Vector2(sx + 10, yy + 24), ("● " if sel else "○ ") + String(PlaneClasses.SKILL3[sk]["title"]) + ("" if unlocked else " (экипаж ур. %d)" % Profile.SKILL_UNLOCK[i]), 15,
				Color(0.7, 1.0, 0.7) if sel else (Color(0.85, 0.88, 0.95) if unlocked and open else Color(0.55, 0.57, 0.62)))
			yy += 40.0
		yy += 16.0
	_text(Vector2(sx, yy + 10), "Слот 3 — экипаж ур. 12, в разработке", 14, Color(0.55, 0.57, 0.62))
	_para(Vector2(sx, yy + 40), "Карточки доводки действуют на навык слота 1.", sw, 13, Color(0.7, 0.72, 0.78))
