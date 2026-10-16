class_name HudScreens
extends HudKit
## Экраны поверх игры: выбор самолёта, выбор карточек и курса, пауза (подвесы), итоги вылета.


# ---------- Экран выбора класса ----------

func class_select(size: Vector2) -> void:
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
		_text(Vector2(x, y), "Экипаж ур. %d%s%s" % [Profile.crew_lvl(id), " · самолёт ур. 2 ✓" if Profile.plane_lvl(id) == 2 else "",
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
	_ctext(1020, "Мышь — курс · W/S — газ (держаться за целью) · сядь врагу на хвост — курсовое +50% · пролёт на волоске перезаряжает навыки · серия сбитий — больше опыта", 18, Color(0.7, 0.95, 1.0))


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
				_text(Vector2(r.position.x + 8, r.position.y + 42), "▲ курс: %d/%d" % [n, need], 13, Color(1.0, 0.85, 0.35))
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

func loadout(m: Main, size: Vector2) -> void:
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

func result(m: Main, size: Vector2) -> void:
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
	for k in ["дроны", "перехватчики", "ракетоносцы", "ПВО", "ас-соперник", "асы"]:
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
	_text(Vector2(rx, y), "Сбито: дроны %d · перехв. %d · ракетон. %d · асы %d" % [m.stat("kills_by", "дроны"), m.stat("kills_by", "перехватчики"), m.stat("kills_by", "ракетоносцы"), m.stat("kills_by", "асы")], 18, hc)
	y += 26.0
	_text(Vector2(rx, y), "Уведено ракет ловушками: %d · срывов захвата: %d" % [int(m.counters.get("intercepted", 0)), int(m.counters.get("locks_broken", 0))], 18, hc)
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
