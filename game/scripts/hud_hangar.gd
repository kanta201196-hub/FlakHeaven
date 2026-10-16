class_name HudHangar
extends HudKit
## 3.2: ангар — самолёт и узлы, ветки оружия, экипаж и перки, слоты навыков.


# ---------- 3.2: ангар ----------

func draw(m: Main, size: Vector2) -> void:
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
	# 3.4-t1 (п. 1): объёмная модель — тянуть мышью, колесо — приближение; ур. 2 виден и не купленным
	var h3 := Hangar3D.ensure(ctrl)
	var vr := Rect2(lx + 8, area.position.y + 8, lw - 16, 330)
	ctrl.draw_texture_rect(h3.show_plane(c, vr), vr, false)
	_text(Vector2(vr.position.x + 12, vr.end.y - 12), "Тяните мышью — вращение, колесо — приближение", 13, Color(0.7, 0.74, 0.8))
	h3.lvl_rects.clear()
	for lv in [1, 2]:
		var br := Rect2(lx + 24 + (lv - 1) * 150, area.position.y + 348, 140, 36)
		var on: bool = h3.view_lvl == lv
		ctrl.draw_rect(br, Menu.C_AMBER if on else Color(1, 1, 1, 0.08))
		_text(Vector2(br.position.x, br.position.y + 25), "Ур. %d" % lv, 17, Color(0.08, 0.07, 0.05) if on else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		h3.lvl_rects.append([br, lv])
	if bought:
		# 3.5: выбор самолёта на вылет — для уровня, который сейчас на виде
		var sel := Profile.plane_lvl(c)
		var sr := Rect2(lx + 330, area.position.y + 348, 210, 36)
		if h3.view_lvl == sel:
			_panel(sr, true)
			ctrl.draw_rect(sr, Color(0.5, 1.0, 0.6), false, 2.0)
			_text(Vector2(sr.position.x, sr.position.y + 25), "✓ ур. %d — в вылет" % sel, 16, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
		else:
			_button(sr, "ЛЕТАТЬ НА УР. %d" % h3.view_lvl, "hg:plane_sel:%d" % h3.view_lvl, 14)
	elif h3.view_lvl == 2:
		_text(Vector2(lx + 330, area.position.y + 372), "не куплен — в вылет недоступен", 15, Color(1.0, 0.75, 0.45))
	# п. 3: как оружие меняется с уровнем
	h3.tier_rects.clear()
	_text(Vector2(lx + 24, area.position.y + 414), "Вид оружия:", 15, Color(0.8, 0.84, 0.9))
	for ti in 3:
		var tr2 := Rect2(lx + 130 + ti * 100, area.position.y + 392, 92, 30)
		var on2: bool = h3.weapon_tier == ti + 1
		ctrl.draw_rect(tr2, Menu.C_AMBER if on2 else Color(1, 1, 1, 0.08))
		_text(Vector2(tr2.position.x, tr2.position.y + 21), "ур. %d" % [1, 3, 5][ti], 15, Color(0.08, 0.07, 0.05) if on2 else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, tr2.size.x)
		h3.tier_rects.append([tr2, ti + 1])
	var y := area.position.y + 446.0
	if bought:
		_text(Vector2(lx + 24, y), "Самолёт ур. 2 куплен — выберите, на каком лететь", 16, Color(0.6, 1.0, 0.7))
		_text(Vector2(lx + 24, y + 24), "ур. 2: прочность +15%, скорость и разворот +5%, +1 переброс", 15, Color(0.8, 0.85, 0.9))
	else:
		_text(Vector2(lx + 24, y), "Самолёт ур. 2 — комплект модернизации", 18, Color.WHITE)
		_text(Vector2(lx + 24, y + 24), "Требует: экипаж ур. %d (сейчас %d) · %d запчастей" % [Profile.PLANE2_CREW, Profile.crew_lvl(c), Profile.PLANE2_COST], 15, Color(0.8, 0.85, 0.9))
		_text(Vector2(lx + 24, y + 46), "даёт: прочность +15%, скорость и разворот +5%, +1 переброс", 14, Color(0.7, 0.74, 0.8))
		if Profile.can_buy_plane2(c):
			_button(Rect2(lx + 24, y + 60, 320, 46), "МОДЕРНИЗИРОВАТЬ — %d" % Profile.PLANE2_COST, "hg:plane2", 17)
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
	# 3.5: портрет (пока нет арта — силуэт)
	var pr_r := Rect2(lx + lw - 124, y + 18, 100, 150)
	var ptex := Profile.portrait(c)
	if ptex != null:
		ctrl.draw_texture_rect(ptex, pr_r, false)
	else:
		ctrl.draw_rect(pr_r, Color(0, 0, 0, 0.45))
		ctrl.draw_circle(pr_r.position + Vector2(50, 58), 26, Color(0.35, 0.37, 0.42))
		ctrl.draw_rect(Rect2(pr_r.position + Vector2(14, 92), Vector2(72, 58)), Color(0.35, 0.37, 0.42))
	ctrl.draw_rect(pr_r, Menu.C_AMBER, false, 1.5)
	y += 30.0
	_text(Vector2(lx + 24, y), String(Profile.CREW[c]["crew"]), 16, Color(0.8, 0.84, 0.9))
	# 3.5: черта характера — плюс и минус
	var tr := Profile.trait_of(c)
	if not tr.is_empty():
		y += 30.0
		_text(Vector2(lx + 24, y), "Черта: «%s»" % tr["title"], 18, Menu.C_AMBER)
		y += 24.0
		_text(Vector2(lx + 24, y), "+ " + String(tr["plus"]), 15, Color(0.6, 1.0, 0.7))
		y += 22.0
		_text(Vector2(lx + 24, y), "− " + String(tr["minus"]), 15, Color(1.0, 0.6, 0.55))
	y = maxf(y + 40.0, pr_r.end.y + 34.0) # под портретом
	var lv := Profile.crew_lvl(c)
	var pr := Profile.crew_progress(c)
	_text(Vector2(lx + 24, y), "Экипаж ур. %d" % lv, 26, Color(0.6, 1.0, 0.7))
	y += 18.0
	ctrl.draw_rect(Rect2(lx + 24, y, lw - 48, 14), Color(0, 0, 0, 0.5))
	if int(pr[1]) > 0:
		ctrl.draw_rect(Rect2(lx + 24, y, (lw - 48) * minf(1.0, float(pr[0]) / float(pr[1])), 14), Color(0.5, 1.0, 0.6))
		var ready := Profile.promote_ready(c)
		_text(Vector2(lx + 24, y + 36), ("опыт для ур. %d набран" % (lv + 1)) if ready else "%d / %d опыта до ур. %d" % [pr[0], pr[1], lv + 1], 15,
			Color(1.0, 0.9, 0.4) if ready else Color(0.8, 0.84, 0.9))
		y += 50.0
		var cost := Profile.promote_cost(lv + 1)
		var can := Profile.can_promote(c)
		var br := Rect2(lx + 24, y, lw - 48, 40)
		if can:
			_button(br, "ПОВЫСИТЬ В ЗВАНИИ — %d запчастей" % cost, "hg:promote", 15)
		else:
			_panel(br, false)
			_text(Vector2(br.position.x + 14, br.position.y + 26), ("Повысить в звании — %d (не хватает запчастей)" % cost) if Profile.promote_ready(c) else "Повысить в звании — %d (нужен опыт)" % cost, 14, Color(0.6, 0.62, 0.68))
		y += 40.0
	y += 34.0
	_para(Vector2(lx + 24, y), "Рост показателей: " + String(Profile.CREW[c]["stats"]), lw - 48, 15)
	y += 56.0
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
