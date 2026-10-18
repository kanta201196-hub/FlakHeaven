class_name HudScreens
extends HudKit
## Экраны поверх игры: выбор самолёта, выбор карточек и курса, пауза (подвесы), итоги вылета.


# ---------- Экран выбора класса ----------

func class_select(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.04, 0.86))
	_text(Vector2(0, 120), "ВЫБЕРИТЕ САМОЛЁТ", 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_button(Rect2(64, 60, 260, 46), "‹ Операция (Esc)", "class_back", 18)
	_ctext(162, "Операция %d «%s» · сложность «%s» · клавиши 1 / 2 / 3 или клик мышью" % [Campaign.index() + 1, Campaign.op()["title"], Campaign.diff()["title"]], 20, Color(0.7, 0.75, 0.85))
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
		y += 24.0 # свежий взгляд: строка экипажа отдельно — раньше наезжала на описание класса
		var sb: String = Profile.skills(id)[1]
		_text(Vector2(x, y), "Экипаж ур. %d%s%s" % [Profile.crew_lvl(id), " · самолёт ур. 2 ✓" if Profile.plane_lvl(id) == 2 else "",
			(" · навык F: " + String(PlaneClasses.SKILL3[sb]["title"])) if sb != "" else ""], 15, Color(0.6, 1.0, 0.7))
		y += 32.0
		_stat_bar(x, y, "Прочность", float(d["hp"]) / 240.0, "%d" % int(d["hp"]))
		y += 26.0
		_stat_bar(x, y, "Скорость", float(d["speed"]), "%d%%" % int(float(d["speed"]) * 100.0))
		y += 26.0
		_stat_bar(x, y, "Манёвр", float(d["turn"]), "%d%%" % int(float(d["turn"]) * 100.0))
		y += 26.0
		_stat_bar(x, y, "Пушка", float(d["gun_dmg"]) * float(d["gun_rate"]) / 1.3, "×%.2f" % (float(d["gun_dmg"]) * float(d["gun_rate"])))
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
		if Profile.plane_lvl(id) == 2:   # U-06
			_text(Vector2(x + 12, y), "• Тяжёлый подвес ×1: экспериментальное оружие из карточек", 17, Color(0.6, 0.85, 1.0))
			y += 24.0
		_text(Vector2(x + 12, y), "• Ведомые: до %d" % int(d["wingmen"]) if int(d["wingmen"]) > 0 else "• Ведомых нет", 17, Color(0.85, 0.88, 0.95))
		y += 24.0
		# правка 5 теста 3.5-s5: какое оружие бывает у самолёта и его «конёк»
		var wl := PackedStringArray()
		for wid in d["weapons"]:
			wl.append(String(Weapons.DEFS[wid]["short"]) + (" ★" if wid == d["signature"] else ""))
		y += _para(Vector2(x + 12, y), "• Оружие: %s  (★ конёк: урон +20%%)" % ", ".join(wl).to_lower(), w - 56.0, 15, Color(0.6, 1.0, 0.65)) + 12.0
		# 3.1: выбор навыка класса (3 варианта)
		_text(Vector2(x, y), "Навык класса [E] — выберите:", 18, Color(0.7, 1.0, 0.7))
		y += 10.0
		var cur: String = Main.I.skill_pick.get(id, Profile.skills(id)[0])
		for sk in PlaneClasses.CLASS_SKILLS[id]:
			var sd: Dictionary = PlaneClasses.SKILL3[sk]
			# высота строки — по описанию: длинное в две строки не вылезает за рамку
			var ph := ui_font().get_multiline_string_size(sd["short"], HORIZONTAL_ALIGNMENT_LEFT, w - 56.0, 13).y
			var sr := Rect2(x - 8, y, w - 40, maxf(58.0, 34.0 + ph))
			var on: bool = sk == cur
			var sh := sr.has_point(mp)
			ctrl.draw_rect(sr, Color(0.55, 0.9, 0.55, 0.16) if on else Color(1, 1, 1, 0.05 if sh else 0.02))
			ctrl.draw_rect(sr, Color(0.6, 1.0, 0.6, 0.9) if on else Color(1, 1, 1, 0.25 if sh else 0.1), false, 2.0)
			var unl := Profile.skill_unlocked(id, sk)
			if unl:
				_buttons.append([sr, "skill:%s:%s" % [id, sk]])
			var si: int = PlaneClasses.CLASS_SKILLS[id].find(sk)
			_text(Vector2(x + 4, y + 20), ("● " if on else "○ ") + "%s · %d с%s%s" % [sd["title"], int(sd["cd"]), "" if unl else "  — экипаж ур. %d" % Profile.SKILL_UNLOCK[si],
				"  · стоит в слоте 2 [F]" if not on and Profile.skills(id)[1] == sk else ""], 17,
				Color(0.85, 1.0, 0.85) if on else (Color(0.85, 0.88, 0.95) if unl else Color(0.5, 0.52, 0.56)))
			_para(Vector2(x + 4, y + 40), sd["short"], w - 56.0, 13, Color(0.75, 0.8, 0.88))
			y += sr.size.y + 4.0
		# картинки самолёта: ур. 1 и ур. 2 (покупка в ангаре), носом вверх
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
				_text(Vector2(c.x - 130.0, r.end.y - 14.0), "ур. %d%s" % [lv, (" ✓ в вылет" if Profile.plane_lvl(id) == lv else "") if Profile.plane2(id) else ("" if lv == 1 else " (в ангаре)")], 15, Color(0.7, 0.75, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 260.0)
	_ctext(932, "Управление: %s   [F2 — сменить]" % Hud.SCHEMES[int(Tuning.g("scheme"))], 20, Color(0.75, 0.85, 1.0))
	_ctext(964, "Опыт с врагов подбирается сам рядом с самолётом. Каждые 5 минут — ас (мини-босс), после него — окно эвакуации.", 18, Color(0.8, 0.85, 0.9))
	_ctext(992, "Угрозы: дроны — держат дистанцию и бьют парой пуль (мигают жёлтым) · перехватчики — заходы с очередью · ракетоносцы — ракеты после красной линии", 18, Color(0.95, 0.75, 0.75))
	_ctext(1020, "Мышь — куда лететь · W/S — газ (держаться за целью) · сядь врагу на хвост — пушка +50% · пролёт на волоске перезаряжает навыки · серия сбитий — больше опыта", 18, Color(0.7, 0.95, 1.0))


func _stat_bar(x: float, y: float, label: String, frac: float, val: String) -> void:
	_text(Vector2(x, y), label, 17, Color(0.8, 0.85, 0.95))
	ctrl.draw_rect(Rect2(x + 120, y - 13, 260, 12), Color(1, 1, 1, 0.08))
	ctrl.draw_rect(Rect2(x + 120, y - 13, 260 * clampf(frac, 0.0, 1.0), 12), Color(0.55, 0.8, 1.0))
	_text(Vector2(x + 392, y), val, 17, Color.WHITE)


# ---------- Карточки ----------

func levelup(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	if m.offer_rare:
		_ctext(150, "НАГРАДА %s: ВЫБОР ИЗ РЕДКИХ КАРТОЧЕК" % (m.rare_reasons[0] if not m.rare_reasons.is_empty() else ""), 38, Color(0.75, 0.5, 1.0))
	else:
		_ctext(150, "НОВЫЙ УРОВЕНЬ: %d" % m.level if m.pending_levels <= 1 else "НОВЫЙ УРОВЕНЬ (ещё выборов: %d)" % m.pending_levels, 40, Color(0.6, 1.0, 0.7))
	if m.levelup_intro:
		# U-03: первые выборы — что это и как выбирать
		_ctext(188, "Выберите одно улучшение — оно действует до конца вылета. Не знаете, что взять? Берите оружие, которое уже стоит на самолёте.", 19, Color(1.0, 0.9, 0.6))
		_ctext(212, "1–4 или клик — выбрать · «Переброс» — показать другие карточки · «Закрепить» — оставить на следующий раз · «Исключить» — больше не предлагать", 16, Color(0.75, 0.8, 0.9))
	else:
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
		# U-09: значок оружия или раздела слева от названия
		CardIcons.draw(ctrl, r.position + Vector2(44, 76), 52.0, CardIcons.key(c, m.player), cc)
		CardIcons.badge(ctrl, r.position + Vector2(44, 76), 52.0, String(c["kind"]), cc)
		_para(Vector2(r.position.x + 82, r.position.y + 66), c["title"], w - 100.0 - (52.0 if c.get("course", false) else 0.0), 22, Color.WHITE)
		if c.get("course", false): # 3.2: карточка ведёт к курсу
			ctrl.draw_colored_polygon(PackedVector2Array([r.position + Vector2(w - 70, 34), r.position + Vector2(w, 34), r.position + Vector2(w, 104)]), Color(1.0, 0.8, 0.25, 0.9))
			_text(Vector2(r.position.x + w - 46, r.position.y + 56), "▲", 18, Color(0.15, 0.1, 0.02))
			_text(Vector2(r.position.x, r.position.y + h - 14), "▲ к специализации", 15, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, w - 14.0)
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
			_button(Rect2(size.x / 2.0 + 10, ry, 460, 46), "Сменить специализацию (−1 переброс)", "change_course", 19)
	else:
		_ctext(ry + 30, "Перебросов не осталось (+1 за каждого аса)", 18, Color(0.6, 0.62, 0.7))
	_ctext(ry + 76, "Исключений осталось: %d (+1 за аса)%s" % [m.bans, ("   ·   Исключены: " + ", ".join(PackedStringArray(m.banned.values()))) if not m.banned.is_empty() else ""], 16, Color(0.75, 0.75, 0.85))
	# 3.1: ближайшие связки — что добрать, чтобы открыть
	var y := ry + 112.0
	if m.player.has_course():
		var sd := Cards.syn_def(m.player, m.player.course)
		_ctext(y, "Специализация: «%s» (связка %d из 3) — %s" % [sd["title"], m.player.syn.size() + 1, sd["short"]], 18, Menu.C_AMBER)
		y += 30.0
		_cond_line(Vector2(size.x / 2.0, y), {"title": "нужно", "conds": Cards.cond_list(m.player, m.player.course)})


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


## Пауза: очки тегов, прогресс курса, связки, эволюции
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
		# 3.2: нашивок нет — под тегом курса показываем прогресс к связке
		if p.has_course():
			var sd := Cards.syn_def(p, p.course)
			var c := Cards.slot_cost(p)
			var need := 0
			if sd.get("tag", "") == t:
				need = int(c["main"])
			elif sd.get("tag2", "") == t:
				need = int(c["second"])
			if need > 0:
				_text(Vector2(r.position.x + 8, r.position.y + 42), "▲ к связке: %d/%d" % [n, need], 13, Color(1.0, 0.85, 0.35))
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
	ctrl.draw_rect(Rect2(pos.x, pos.y + 116, w, 62), Color(0.05, 0.055, 0.06, 0.8))
	_para(Vector2(pos.x + 8, pos.y + 138), "Связки: %s   ·   Модернизации: %s   ·   Навык: %s%s" % [
		", ".join(extra) if not extra.is_empty() else "нет", ", ".join(ev) if not ev.is_empty() else "нет",
		p.s3_def()["title"], (", ур. " + Prog.ROMAN[p.s3_lvl()]) if p.s3_lvl() > 0 else ""], w - 16.0, 16, Menu.C_AMBER)


# ---------- Подвесы и пауза ----------

func loadout(m: Main, size: Vector2) -> void:
	# правка 15 (тест 3.5): фон плотнее — бой под паузой не мешает читать
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.84))
	_ctext(110, "ПАУЗА · ПОДВЕСЫ", 40, Color.WHITE)
	_ctext(146, "Клик по приоритету — сменить, по какой цели стреляет группа", 20, Color(0.75, 0.8, 0.9))
	var p := m.player
	# слева подвесы и теги, справа — взятые карточки сводкой
	var w := 1000.0
	var x := 90.0
	var y := 176.0
	# подвесов бывает до 7 — строки ужимаются, чтобы всё влезло над теговой панелью
	var rh := clampf(440.0 / maxf(p.groups.size(), 1), 50.0, 64.0)
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		var r := Rect2(x, y, w, rh)
		_panel(r, false)
		_text(Vector2(x + 20, y + rh * 0.44), g.label(), 20, Color.WHITE if not g.is_empty() else Color(0.6, 0.62, 0.7))
		if not g.is_empty():
			_text(Vector2(x + 20, y + rh * 0.44 + 20), Weapons.DEFS[g.weapon]["desc"], 14, Color(0.75, 0.8, 0.9))
			var by := y + (rh - 36.0) / 2.0
			if Weapons.DEFS[g.weapon]["uses_priority"]:
				_button(Rect2(x + w - 290, by, 270, 36), "Цель: %s" % Weapons.PRIORITY_NAMES[g.priority], "prio:%d" % gi, 17)
			if g.uses_trigger():
				_button(Rect2(x + w - 290, by, 270, 36), "Пуск: %s" % ("авто" if g.trigger == "auto" else "правой кнопкой мыши"), "trig:%d" % gi, 17)
		y += rh + 8.0
	if not p.wingmen.is_empty():
		var wr := Rect2(x, y, w, 48)
		_panel(wr, false)
		_text(Vector2(x + 20, y + 31), "Звено — кого атакует первым [G]", 20, Color(0.8, 0.75, 1.0))
		_button(Rect2(x + w - 330, y + 6, 310, 36), "Цель: %s" % Settings.WING_PRIO[Settings.wing_prio], "wprio", 17)
		y += 56.0
	y += 4.0
	_text(Vector2(x, y + 10), "Пушка: урон ×%.2f · темп ×%.2f   ·   Подвесы: перезарядка ×%.2f   ·   Скорость ×%.2f · Манёвр ×%.2f · Подбор ×%.2f" % [
		float(p.cls["gun_dmg"]) * p.mods["gun_dmg"], float(p.cls["gun_rate"]) * p.mods["gun_rate"], p.mods["hp_cd"],
		float(p.cls["speed"]) * p.mods["speed"], float(p.cls["turn"]) * p.mods["turn"], p.mods["pickup"]], 16, Color(0.85, 0.88, 0.95))
	_tags_panel(p, Vector2(x, y + 36), w)
	var cx := x + w + 40.0
	var cw := size.x - cx - 60.0
	_text(Vector2(cx, 200), "ВЗЯТЫЕ КАРТОЧКИ (%d)" % p.cards_log.size(), 20, Menu.C_AMBER)
	_text(Vector2(cx, 222), "цвет — лучшая редкость, «ур.» — до какого уровня улучшено", 14, Color(0.65, 0.7, 0.8))
	if p.cards_log.is_empty():
		_text(Vector2(cx, 256), "пока ни одной", 16, Color(0.6, 0.62, 0.7))
	else:
		_card_chips(Rect2(cx, 238, cw, size.y - 238 - 180), Cards.log_summary(p.cards_log), 15)
	var bx := (size.x - 960) / 2.0
	_button(Rect2(bx - 165, size.y - 150, 300, 50), "Продолжить (Esc / Tab)", "resume")
	_button(Rect2(bx + 165, size.y - 150, 300, 50), "Связки и модернизации", "codex")
	_button(Rect2(bx + 495, size.y - 150, 300, 50), "Настройки", "pause_settings")
	_button(Rect2(bx + 825, size.y - 150, 300, 50), "В главное меню", "to_menu")


# ---------- Итоги вылета ----------

func result(m: Main, size: Vector2) -> void:
	# правка 16 (тест 3.5): фон плотнее — интерфейс боя под итогами не просвечивает
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.03, 0.93))
	var t := int(m.run_time)
	var top := 100.0
	if m.state == "evac":
		_ctext(top, "ЭВАКУАЦИЯ УСПЕШНА", 46, Color(0.5, 1.0, 0.6))
	else:
		_ctext(top, "САМОЛЁТ СБИТ", 46, Color(1, 0.5, 0.4))
	_ctext(top + 42, "%s · время %02d:%02d · уровень %d · сбито %d · асов %d" % [PlaneClasses.DATA[m.cls_id]["title"], t / 60, t % 60, m.level, m.kills, m.bosses_killed], 23, Color.WHITE)
	var kept_note := "100% — эвакуация" if m.state == "evac" else "50% — гибель без эвакуации"
	_ctext(top + 74, "Запчасти: %d из %d (%s)" % [m.parts_kept, int(m.parts), kept_note], 21, Color(0.95, 0.85, 0.55))
	_op_line(m, top + 104)
	# правка 30 (тест 3.5-s4): итоги на вкладках — «Обзор» с выводами, «Урон» с долями и уроном в секунду, «Сборка»
	var tabs := ["1 · Обзор", "2 · Урон", "3 · Сборка"]
	for i in tabs.size():
		var r := Rect2(90 + i * 230, top + 124, 220, 38)
		var on := m.result_tab == i
		ctrl.draw_rect(r, Menu.C_AMBER if on else Color(1, 1, 1, 0.07))
		_text(Vector2(r.position.x, r.position.y + 26), tabs[i], 18, Color(0.08, 0.07, 0.05) if on else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_buttons.append([r, "rtab:%d" % i])
	var y0 := top + 196.0
	match m.result_tab:
		0:
			_res_overview(m, y0)
			_meta_panel(m, Rect2(1220, y0 - 30, 620, 560))
		1:
			_res_damage(m, y0, size)
		2:
			_res_build(m, y0, size)
	# кнопки одной строкой, отчёт — пятой кнопкой, ничего не перекрывает
	var n_btn := 5 if Main.REPORT_URL != "" and not m.report_sent else 4
	var bw := 300.0
	var bx := size.x / 2.0 - (n_btn * bw + (n_btn - 1) * 20.0) / 2.0
	var by := size.y - 120.0
	_button(Rect2(bx, by, bw, 54), "R — ещё вылет", "restart", 22)
	_button(Rect2(bx + 320, by, bw, 54), "H — в ангар", "to_hangar", 22)
	_button(Rect2(bx + 640, by, bw, 54), "C — сменить самолёт", "change_class", 22)
	_button(Rect2(bx + 960, by, bw, 54), "В главное меню", "to_menu", 22)
	if Main.REPORT_URL != "":
		if m.report_sent:
			_text(Vector2(0, by + 80), "✓ Отчёт принят — спасибо!", 19, Color(0.6, 1.0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		else:
			_button(Rect2(bx + 1280, by, bw, 54), "ОТПРАВИТЬ ОТЧЁТ", "report_open", 22)


## «Обзор»: выводы словами и плитки ключевых цифр
func _res_overview(m: Main, y: float) -> void:
	var x := 90.0
	_text(Vector2(x, y), "ГЛАВНОЕ ЗА ВЫЛЕТ", 22, Menu.C_AMBER)
	y += 14.0
	for ins in result_insights(m):
		y += 34.0
		ctrl.draw_rect(Rect2(x, y - 16, 6, 20), ins[1])
		_para(Vector2(x + 18, y), String(ins[0]), 1060.0, 19, Color(0.92, 0.94, 0.98))
		if ui_font().get_multiline_string_size(String(ins[0]), HORIZONTAL_ALIGNMENT_LEFT, 1060.0, 19).y > 30.0:
			y += 24.0
	# плитки: ключевые цифры для сравнения вылетов между собой
	var rt := maxf(m.run_time, 1.0)
	var acc := 0 if m.shots == 0 else int(100.0 * m.hits / m.shots)
	var tiles := [
		["урон в секунду", "%d" % int(m.total("dealt") / rt), Color(0.6, 1.0, 0.7)],
		["получено урона", "%d" % m.total("taken"), Color(1.0, 0.7, 0.65)],
		["сбито в минуту", "%.0f" % (m.kills / rt * 60.0), Color.WHITE],
		["точность пушки", "%d%%" % acc, Color(0.85, 0.9, 1.0)],
		["связок", "%d" % m.player.syn.size(), Menu.C_AMBER],
		["активностей", "%d" % m.activities_done, Color(0.7, 0.95, 1.0)],
	]
	var ty := y + 50.0
	for i in tiles.size():
		var r := Rect2(x + (i % 3) * 360, ty + (i / 3) * 96, 340, 84)
		_panel(r, false)
		_text(Vector2(r.position.x + 18, r.position.y + 50), String(tiles[i][1]), 34, tiles[i][2])
		_text(Vector2(r.position.x + 18, r.position.y + 74), String(tiles[i][0]), 15, Color(0.72, 0.76, 0.84))


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
		var s := "Главный урон — %s: %d%% всего урона" % [SRC_NAMES.get(k0, k0), share]
		if keys.size() > 1:
			s += ", дальше %s — %d%%" % [SRC_NAMES.get(keys[1], keys[1]), int(round(100.0 * float(dealt[keys[1]]) / dt))]
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
		out.append(["Больше всего урона вы получили от врагов «%s» (%d%%), в основном — %s." % [bk, int(round(100.0 * float(by.get(bk, 0)) / tk)), kk], Color(1.0, 0.55, 0.45)])
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
		out.append(["Связок: %d, первая — на %d:%02d." % [m.player.syn.size(), int(first) / 60, int(first) % 60], Menu.C_AMBER])
	if m.shots > 50 and m.hits * 100 < m.shots * 30:
		out.append(["Пушка попадала только в %d%% выстрелов: держите нос на цели или включите ручной огонь (Q) — он сильнее." % int(100.0 * m.hits / m.shots), Color(0.75, 0.85, 1.0)])
	if m.bosses_killed == 0 and m.run_time > 200.0:
		out.append(["Ни одного сбитого аса — без него не открываются ворота эвакуации.", Color(1.0, 0.55, 0.45)])
	return out.slice(0, 6)


## «Урон»: нанесённый с долей и уроном в секунду, полученный — по видам и по врагам
func _res_damage(m: Main, y0: float, size: Vector2) -> void:
	var lx := 90.0
	var rx := 700.0
	var hc := Color(0.95, 0.95, 1.0)
	var rt := maxf(m.run_time, 1.0)
	_text(Vector2(lx, y0), "ПОЛУЧЕНО УРОНА: %d" % m.total("taken"), 22, Color(1.0, 0.72, 0.68))
	var y := y0 + 36.0
	for k in ["таран", "пули", "ракеты"]:
		_row(lx, y, 520.0, k, m.stat("taken", k), m.total("taken"), Color(1.0, 0.45, 0.4))
		y += 30.0
	y += 14.0
	_text(Vector2(lx, y), "От кого:", 19, hc)
	y += 30.0
	for k in ["дроны", "перехватчики", "ракетоносцы", "ПВО", "ас-соперник", "асы"]:
		_row(lx, y, 520.0, k, m.stat("taken_by", k), m.total("taken"), Color(1.0, 0.6, 0.4))
		y += 30.0
	_text(Vector2(rx, y0), "НАНЕСЕНО УРОНА: %d  ·  %d в секунду" % [m.total("dealt"), int(m.total("dealt") / rt)], 22, Color(0.72, 1.0, 0.78))
	_text(Vector2(rx + 300, y0 + 30), "доля", 14, Color(0.65, 0.7, 0.78))
	_text(Vector2(rx + 940, y0 + 30), "урон · в сек.", 14, Color(0.65, 0.7, 0.78), HORIZONTAL_ALIGNMENT_RIGHT, 160)
	y = y0 + 58.0
	var dealt: Dictionary = m.stats["dealt"]
	var keys := dealt.keys()
	keys.sort_custom(func(a, b): return float(dealt[a]) > float(dealt[b]))
	var tot := float(maxi(m.total("dealt"), 1))
	for k in keys.slice(0, 12):
		var v := float(dealt[k])
		_text(Vector2(rx, y), SRC_NAMES.get(k, k), 17, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_LEFT, 290)
		ctrl.draw_rect(Rect2(rx + 300, y - 13, 560, 13), Color(1, 1, 1, 0.08))
		ctrl.draw_rect(Rect2(rx + 300, y - 13, 560 * v / tot, 13), Color(0.45, 0.9, 0.55))
		_text(Vector2(rx + 870, y), "%d%%" % int(round(100.0 * v / tot)), 16, Color(0.8, 1.0, 0.85))
		_text(Vector2(rx + 940, y), "%d · %d" % [int(v), int(v / rt)], 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 160)
		y += 28.0
	y += 16.0
	var acc := 0.0 if m.shots == 0 else 100.0 * m.hits / m.shots
	var lines := [
		"Сбито: дроны %d · перехватчики %d · ракетоносцы %d · асы %d" % [m.stat("kills_by", "дроны"), m.stat("kills_by", "перехватчики"), m.stat("kills_by", "ракетоносцы"), m.stat("kills_by", "асы")],
		"Точность пушки: %d%% · пик «оборотов»: +%d%% · сбито с хвоста: %d" % [int(acc), int(round(m.peak_rev * 100.0)), m.tail_kills],
		"Уведено ракет ловушками: %d · срывов захвата: %d · на волоске: %d" % [int(m.counters.get("intercepted", 0)), int(m.counters.get("locks_broken", 0)), m.near_misses],
		"Лучшая серия: %d · активностей: %d · проход на форсаже: %d урона" % [m.best_streak, m.activities_done, m.stat("dealt", "проход на форсаже")],
	]
	for l in lines:
		if y > size.y - 150.0:
			break
		_text(Vector2(rx, y), l, 17, hc)
		y += 26.0


## «Сборка»: все взятые карточки сводкой, связки с временем и уроном, модернизации
func _res_build(m: Main, y0: float, size: Vector2) -> void:
	var x := 90.0
	var y := y0
	var p := m.player
	_text(Vector2(x, y), "СВЯЗКИ", 20, Menu.C_AMBER)
	if p.syn.is_empty():
		_text(Vector2(x + 120, y), "нет", 18, Color(0.65, 0.68, 0.75))
	for id in p.syn:
		y += 26.0
		var sd := Cards.syn_def(p, id)
		var sdmg := m.stat("dealt", "связка: " + String(sd["title"]).to_lower())
		var tt := int(float(p.syn[id]))
		_text(Vector2(x + 12, y), "«%s» — с %d:%02d · урон %d" % [sd["title"], tt / 60, tt % 60, sdmg], 18, Color(1.0, 0.9, 0.6))
	y += 40.0
	var ev := PackedStringArray()
	for wv in p.evo_times:
		var et := int(float(p.evo_times[wv]))
		ev.append("%s (%d:%02d)" % [Prog.EVOS[wv]["title"], et / 60, et % 60])
	_text(Vector2(x, y), "МОДЕРНИЗАЦИИ: " + (", ".join(ev) if not ev.is_empty() else "нет"), 18, Cards.EVO_COLOR)
	y += 34.0
	var gl := PackedStringArray()
	for g in p.groups:
		var h := g as Hardpoint
		if not h.is_empty():
			gl.append("%s ур. %d ×%d" % [Weapons.DEFS[h.weapon]["short"], h.level, h.slots])
	_para(Vector2(x, y), "ПОДВЕСЫ: " + (" · ".join(gl) if not gl.is_empty() else "пусто"), size.x - 2.0 * x, 18, Color(0.85, 0.9, 1.0))
	y += 46.0
	_text(Vector2(x, y), "КАРТОЧКИ ВЫЛЕТА: %d" % p.cards_log.size(), 20, Menu.C_AMBER)
	_text(Vector2(x + 300, y), "цвет — лучшая редкость, «ур.» — до какого уровня улучшено", 14, Color(0.65, 0.7, 0.8))
	if not p.cards_log.is_empty():
		_card_chips(Rect2(x, y + 16, size.x - 2.0 * x, size.y - 150.0 - (y + 16)), Cards.log_summary(p.cards_log), 16)


## U-01: внутренние имена источников урона (их пишет лог l5) → понятные игроку
const SRC_NAMES := {
	"курсовое (авто)": "пушка (сама)", "курсовое (ручн.)": "пушка (ручной огонь)",
	"ракеты В-В": "наводящиеся ракеты", "НАР": "залп ракет", "разделяющаяся БЧ": "разделяющиеся ракеты",
	"ЭМИ": "ЭМИ-заряд", "лазер": "лазер «Луч»", "плазма": "плазменная бомба",
}


func _row(x: float, y: float, w: float, label: String, v: int, tot: int, col: Color) -> void:
	var frac := 0.0 if tot <= 0 else float(v) / float(tot)
	_text(Vector2(x, y), label, 18, Color(0.85, 0.88, 0.95))
	var bx := x + 180.0
	var bw := w - 180.0 - 70.0
	ctrl.draw_rect(Rect2(bx, y - 14.0, bw, 14.0), Color(1, 1, 1, 0.08))
	ctrl.draw_rect(Rect2(bx, y - 14.0, bw * frac, 14.0), col)
	_text(Vector2(bx + bw + 10.0, y), str(v), 18, Color.WHITE)


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


func course_pick(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.72))
	var p := m.player
	var slot := p.syn.size() + 1
	_ctext(150, "ВЫБОР СПЕЦИАЛИЗАЦИИ — СВЯЗКА %d ИЗ 3" % slot, 40, Menu.C_AMBER)
	_ctext(192, "Связка — сильный бонус, который меняет оружие или навык. Выберите, какую собирать: карточки к ней отмечены «▲» и выпадают чаще.", 17, Color(0.8, 0.84, 0.92))
	_ctext(218, "Нужно набрать очки цветных меток на карточках: для 1-й связки — %d, 2-й — %d, 3-й — %d. Сменить специализацию можно позже за 1 переброс." % [
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
		_text(Vector2(r.position.x + 18, r.position.y + 262), "Что нужно собрать:", 16, Color(0.8, 0.82, 0.88))
		var yy := r.position.y + 272.0
		for c in conds:
			_cond_chips(Vector2(r.position.x + 18, yy), [c])
			yy += 28.0
		_text(Vector2(r.position.x + 18, r.end.y - 16), "≈ ещё %d подходящих карточек" % Cards.cards_left(conds), 16, Menu.C_AMBER)
	_ctext(690, "1–3 или клик — выбрать специализацию", 17, Color(0.75, 0.8, 0.9))


## U-05: итог операции кампании — пройдена (и что открыто) или чего не хватило
func _op_line(m: Main, y: float) -> void:
	var o: Dictionary = m.op_result
	if o.is_empty():
		return
	var s := ""
	var col := Color(0.8, 0.82, 0.88)
	if o["first"]:
		s = "Операция %d «%s» пройдена! Открыто: %s" % [int(o["n"]), o["title"], ", ".join(PackedStringArray(o["opens"]))]
		col = Color(1.0, 0.85, 0.4)
	elif o["done"]:
		s = "Операция %d «%s» выполнена (уже была пройдена)" % [int(o["n"]), o["title"]]
		col = Color(0.5, 1.0, 0.6)
	else:
		s = "Операция %d «%s» не засчитана: не удалось %s" % [int(o["n"]), o["title"], ", ".join(PackedStringArray(o["miss"])) if not (o["miss"] as Array).is_empty() else "вернуться на базу"]
	_ctext(y, s, 19, col)


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
	var rk := Campaign.k("reward")
	rows.append(["Добыча вылета (%s%s)" % ["100%" if m.state == "evac" else "50%", "" if rk <= 1.0 else ", сложность ×" + HudCampaign._k(rk)], "+%d" % m.parts_kept, Color(0.95, 0.85, 0.55)])
	rows.append(["Жалованье техникам", "+%d" % int(a["wage"]), Color(0.95, 0.85, 0.55)])
	if int(a.get("op_parts", 0)) > 0:
		rows.append(["Операция пройдена впервые", "+%d" % int(a["op_parts"]), Color(1.0, 0.85, 0.4)])
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
	var frac := clampf(float(pr[0]) / maxf(float(pr[1]), 1.0), 0.0, 1.0) if int(pr[1]) > 0 else 1.0
	ctrl.draw_rect(Rect2(x, y, w * frac * k, 16), Color(0.5, 1.0, 0.6))
	y += 40.0
	_text(Vector2(x, y), "Экипаж ур. %d" % lv, 20, Color.WHITE)
	if int(pr[1]) > 0 and not a.has("promote"):
		_text(Vector2(x, y), "до ур. %d: %d" % [lv + 1, int(pr[1]) - int(pr[0])], 16, Color(0.75, 0.8, 0.88), HORIZONTAL_ALIGNMENT_RIGHT, w)
	# 3.5: уровень покупается в ангаре — «Повысить в звании»
	if a.has("promote"):
		y += 28.0
		var pv: Array = a["promote"]
		_text(Vector2(x, y), "Опыта хватает на ур. %d: «Повысить в звании» в ангаре — %d" % [int(pv[0]), int(pv[1])], 16,
			Color(1.0, 0.9, 0.4))
	for u in a["unlocked"]:
		y += 26.0
		_text(Vector2(x, y), "ОТКРЫТО: " + String(u), 16, Color(1.0, 0.85, 0.4))
	if String(a.get("tech", "")) != "":
		y += 28.0
		_text(Vector2(x, y), "Техник: «%s»" % String(a["tech"]), 16, Color(0.95, 0.85, 0.55))
	if String(a.get("hint_buy", "")) != "":
		y += 30.0
		_text(Vector2(x, y), "Можно купить: " + String(a["hint_buy"]), 17, Color(0.6, 0.95, 1.0))
