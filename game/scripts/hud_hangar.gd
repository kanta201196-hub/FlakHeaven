class_name HudHangar
extends HudKit
## 3.2: ангар — самолёт и узлы, ветки оружия, экипаж и перки, слоты навыков.


# ---------- 3.2: ангар ----------

func draw(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.05, 0.94))
	var c := m.hangar_cls
	_text(Vector2(0, 66), "АНГАР", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_text(Vector2(0, 66), Loc.t("Запчасти: %d   ") % Profile.parts(), 26, Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60)
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
		_text(Vector2(r.position.x + 16, r.position.y + 28), Loc.t(String(PlaneClasses.DATA[id]["title"])), 19, col)
		var pp := Profile.perk_points(id)
		_text(Vector2(r.position.x + 16, r.position.y + 52), Loc.t("Экипаж ур. %d%s") % [Profile.crew_lvl(id), (Loc.t("  · очков перков: %d") % pp) if pp > 0 else ""], 15, Color(0.85, 0.88, 0.95))
	# вкладки
	var tabs := [["plane", "САМОЛЁТ"], ["weapons", "ОРУЖИЕ"], ["crew", "ЭКИПАЖ"]]
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
	_button(Rect2(size.x / 2.0 - 180, size.y - 110, 360, 56), Loc.t("В ВЫЛЕТ — %s") % Loc.t(PlaneClasses.DATA[c]["title"]), "hg:fly", 20)
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
	# S9-02: узлы того самолёта, что на виде (раньше — того, что выбран в вылет: смотрели ур. 1, а улучшался ур. 2)
	var vl: int = h3.view_lvl if bought else 1
	var vr := Rect2(lx + 8, area.position.y + 8, lw - 16, 330)
	ctrl.draw_texture_rect(h3.show_plane(c, vr), vr, false)
	_text(Vector2(vr.position.x + 12, vr.end.y - 12), "Тяните мышью — вращение, колесо — приближение", 13, Color(0.7, 0.74, 0.8))
	# тест 3.5-s8: показ механизации — закрылки и предкрылки, створки отсека, турели (Hangar3D / HangarAnim)
	var mr := Rect2(vr.end.x - 196, vr.position.y + 8, 188, 30)
	var mon := h3.mech_demo
	ctrl.draw_rect(mr, Menu.C_AMBER if mon else Color(0, 0, 0, 0.45))
	ctrl.draw_rect(mr, Menu.C_AMBER, false, 1.0)
	_text(Vector2(mr.position.x, mr.position.y + 21), ("■ " if mon else "▶ ") + Loc.t("Механизация"), 15, Color(0.08, 0.07, 0.05) if mon else Color(0.95, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER, mr.size.x)
	h3.mech_rect = mr
	h3.lvl_rects.clear()
	for lv in [1, 2]:
		var br := Rect2(lx + 24 + (lv - 1) * 150, area.position.y + 348, 140, 36)
		var on: bool = h3.view_lvl == lv
		ctrl.draw_rect(br, Menu.C_AMBER if on else Color(1, 1, 1, 0.08))
		_text(Vector2(br.position.x, br.position.y + 25), Loc.t("Ур. %d") % lv, 17, Color(0.08, 0.07, 0.05) if on else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		h3.lvl_rects.append([br, lv])
	if bought:
		# 3.5: выбор самолёта на вылет — для уровня, который сейчас на виде
		var sel := Profile.plane_lvl(c)
		var sr := Rect2(lx + 330, area.position.y + 348, 210, 36)
		if h3.view_lvl == sel:
			_panel(sr, true)
			ctrl.draw_rect(sr, Color(0.5, 1.0, 0.6), false, 2.0)
			_text(Vector2(sr.position.x, sr.position.y + 25), Loc.t("✓ ур. %d — в вылет") % sel, 16, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
		else:
			_button(sr, Loc.t("ЛЕТАТЬ НА УР. %d") % h3.view_lvl, "hg:plane_sel:%d" % h3.view_lvl, 14)
	elif h3.view_lvl == 2:
		_text(Vector2(lx + 330, area.position.y + 372), "не куплен — в вылет недоступен", 15, Color(1.0, 0.75, 0.45))
	# п. 3: как оружие меняется с уровнем
	h3.tier_rects.clear()
	_text(Vector2(lx + 24, area.position.y + 414), "Вид оружия:", 15, Color(0.8, 0.84, 0.9))
	for ti in 4:
		var tr2 := Rect2(lx + 130 + ti * 100, area.position.y + 392, 92, 30)
		var on2: bool = h3.weapon_tier == ti + 1
		ctrl.draw_rect(tr2, Menu.C_AMBER if on2 else Color(1, 1, 1, 0.08))
		_text(Vector2(tr2.position.x, tr2.position.y + 21), (Loc.t("ур. %d") % [1, 3, 5][ti]) if ti < 3 else Loc.t("модерниз."), 15, Color(0.08, 0.07, 0.05) if on2 else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, tr2.size.x)
		h3.tier_rects.append([tr2, ti + 1])
	_hg_livery(c, lx, area.position.y + 432)
	var y := area.position.y + 486.0
	if bought:
		_text(Vector2(lx + 24, y), "Самолёт ур. 2 куплен — выберите, на каком лететь", 16, Color(0.6, 1.0, 0.7))
		_text(Vector2(lx + 24, y + 24), "ур. 2: прочность +15%, скорость и разворот +5%, +1 переброс, тяжёлый подвес", 15, Color(0.8, 0.85, 0.9))
		# правка 6 теста 3.5-s5: прокачка у каждого самолёта своя
		_text(Vector2(lx + 24, y + 48), Loc.t("Улучшения справа — для самолёта ур. %d; у ур. 1 и ур. 2 своя прокачка") % vl, 14, Menu.C_AMBER)
	elif Demo.on:
		_text(Vector2(lx + 24, y), "Самолёт ур. 2 — новая модель", 18, Color.WHITE)
		_text(Vector2(lx + 24, y + 24), Loc.t("Покупка — ") + Loc.t(Demo.LOCKED), 15, Menu.C_AMBER)
		_text(Vector2(lx + 24, y + 46), "даёт: прочность +15%, скорость и разворот +5%, +1 переброс, тяжёлый подвес", 14, Color(0.7, 0.74, 0.8))
	else:
		_text(Vector2(lx + 24, y), "Самолёт ур. 2 — новая модель", 18, Color.WHITE)
		_text(Vector2(lx + 24, y + 24), Loc.t("Требует: операция «Перевал»%s · экипаж ур. %d (сейчас %d) · %d запчастей") % [" ✓" if Campaign.cleared(0) else "", Profile.PLANE2_CREW, Profile.crew_lvl(c), Profile.PLANE2_COST], 15, Color(0.8, 0.85, 0.9))
		_text(Vector2(lx + 24, y + 46), "даёт: прочность +15%, скорость и разворот +5%, +1 переброс, тяжёлый подвес", 14, Color(0.7, 0.74, 0.8))
		if Profile.can_buy_plane2(c):
			_button(Rect2(lx + 24, y + 60, 320, 46), Loc.t("МОДЕРНИЗИРОВАТЬ — %d") % Profile.PLANE2_COST, "hg:plane2", 17)
	# справа — 6 узлов
	var rx := lx + lw + 30.0
	var rw := area.size.x - lw - 30.0
	var yy := area.position.y
	for id in Profile.NODE_ORDER:
		var nd: Dictionary = Profile.NODES[id]
		var lv2 := Profile.node(c, id, vl)
		var r := Rect2(rx, yy, rw, 92)
		_panel(r, false)
		if id == "wing" and r.has_point(ctrl.get_local_mouse_position()):
			h3.mech_hover = true   # тест 3.5-s8: курсор на «Крыле» — на модели идёт показ механизации
		_text(Vector2(rx + 20, yy + 30), Loc.t(String(nd["title"])), 20, Color.WHITE)
		for i in 5:
			ctrl.draw_rect(Rect2(rx + 200 + i * 30, yy + 16, 24, 14), Menu.C_AMBER if i < lv2 else Color(1, 1, 1, 0.12))
		_text(Vector2(rx + 20, yy + 58), Loc.t("за уровень: %s · сейчас ур. %d%s") % [nd["step"], lv2, (Loc.t(" (самолёт ур. %d)") % vl) if bought else ""], 15, Color(0.8, 0.84, 0.9))
		if String(nd["note"]) != "":
			_text(Vector2(rx + 20, yy + 80), Loc.t(String(nd["note"])), 12, Color(0.6, 0.62, 0.68))
		if lv2 >= 5:
			_text(Vector2(rx, yy + 52), "МАКС.", 18, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, rw - 24)
		elif lv2 >= Demo.node_cap():
			_text(Vector2(rx, yy + 52), Loc.t("ур. %d–5 — ") % (lv2 + 1) + Loc.t(Demo.LOCKED), 16, Menu.C_AMBER, HORIZONTAL_ALIGNMENT_RIGHT, rw - 24)
		else:
			var price: int = Profile.NODE_COST[lv2]
			if Profile.can_buy_node(c, id, vl):
				_button(Rect2(rx + rw - 250, yy + 24, 230, 44), Loc.t("УЛУЧШИТЬ — %d") % price, "hg:node:%s:%d" % [id, vl], 16)
			else:
				_text(Vector2(rx, yy + 52), Loc.t("%d (не хватает %d)") % [price, price - Profile.parts()], 16, Color(0.65, 0.65, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, rw - 24)
		yy += 102.0


## Тест 3.5-s4, п. 35: ряд «Окраска: …» — выбор сохраняется в профиле класса, виден в ангаре и в бою
func _hg_livery(c: String, lx: float, y: float) -> void:
	_text(Vector2(lx + 24, y + 21), "Окраска:", 15, Color(0.8, 0.84, 0.9))
	var cur := Livery.current(c)
	var lst := Livery.list(c)
	var step := minf(112.0, 452.0 / maxf(lst.size(), 1))   # 5 окрасок (С-1) — кнопки уже, ряд в ширину панели
	for i in lst.size():
		var r := Rect2(lx + 100 + i * step, y, step - 6, 30)
		var on: bool = lst[i][0] == cur
		ctrl.draw_rect(r, Menu.C_AMBER if on else Color(1, 1, 1, 0.08))
		var nm := String(lst[i][1])
		var tc := Color(0.08, 0.07, 0.05) if on else Color(0.85, 0.88, 0.95)
		if nm.contains(" ") and ui_font().get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > r.size.x - 6:
			var sp := nm.find(" ")   # длинное название — в две строки
			_text(Vector2(r.position.x, r.position.y + 13), nm.substr(0, sp), 11, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			_text(Vector2(r.position.x, r.position.y + 26), nm.substr(sp + 1), 11, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		else:
			_text(Vector2(r.position.x, r.position.y + 20), nm, 12, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_buttons.append([r, "hg:livery:" + String(lst[i][0])])


## Фишка 3 (Kanta 18.10): какое оружие стоит на втором подвесе с начала вылета
func _hg_start2(m: Main, lx: float, y: float) -> void:
	var c := m.hangar_cls
	_text(Vector2(lx, y + 16), "Второй подвес на старте", 17, Color.WHITE)
	if Profile.crew_lvl(c) < Profile.START2_LVL:
		_para(Vector2(lx, y + 28), Loc.t("Откроется на ур. экипажа %d. Пока второй подвес пустой — оружие из карточек.") % Profile.START2_LVL, 300.0, 14, Color(0.65, 0.68, 0.75))
		return
	var cur := Profile.start2(c)
	var opts: Array = [""] + Profile.start2_options(c)
	# PG-01: three columns — with the new weapons a class has up to 7 options
	for i in opts.size():
		var w := String(opts[i])
		var r := Rect2(lx + (i % 3) * 102.0, y + 28.0 + (i / 3) * 40.0, 96.0, 34.0)
		var on := cur == w
		ctrl.draw_rect(r, Menu.C_AMBER if on else Color(1, 1, 1, 0.08))
		_text(Vector2(r.position.x, r.position.y + 23), Loc.t("пусто") if w == "" else Loc.t(String(Weapons.DEFS[w]["short"])), 13, Color(0.08, 0.07, 0.05) if on else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_buttons.append([r, "hg:start2:" + w])
	_para(Vector2(lx, y + 34.0 + ceili(opts.size() / 3.0) * 40.0), "Ставится с ур. 1; улучшения — карточками в бою.", 300.0, 13, Color(0.65, 0.68, 0.75))


## PG-01 (Kanta 24.10): course gun of the class — bought once for parts, switched for free before a sortie
const GUN_TITLE := {"std": "Стандартная", "twin": "Спарка", "heavy": "Крупный калибр"}
const GUN_HINT := {
	"std": "Обычная пушка: ровный темп и урон.",
	"twin": "Темп ×1,6, урон ×0,65, лёгкий разброс — против роя дронов, быстрее разгоняет «обороты».",
	"heavy": "Темп ×0,55, урон ×2, снаряд быстрее; броню почти пробивает (×0,8 вместо ×0,5).",
}


func _hg_gun(m: Main, lx: float, y: float) -> float:
	var c := m.hangar_cls
	_text(Vector2(lx, y + 16), "Курсовая пушка", 17, Color.WHITE)
	var cur := Profile.gun(c)
	var owned := Profile.guns(c)
	for i in WeaponBalance.GUN_ORDER.size():
		var g: String = WeaponBalance.GUN_ORDER[i]
		var r := Rect2(lx + i * 102.0, y + 28.0, 96.0, 44.0)
		var on := cur == g
		var has := owned.has(g)
		var price := int(WeaponBalance.GUN_PRICE[g])
		var can := has or Profile.parts() >= price
		ctrl.draw_rect(r, Menu.C_AMBER if on else Color(1, 1, 1, 0.08 if can else 0.04))
		var tc := Color(0.08, 0.07, 0.05) if on else (Color(0.85, 0.88, 0.95) if can else Color(0.55, 0.57, 0.62))
		_text(Vector2(r.position.x, r.position.y + 19), Loc.t(String(GUN_TITLE[g])), 13, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var sub := Loc.t("✓ выбрана") if on else (Loc.t("выбрать") if has else Loc.t("%d зап.") % price)
		_text(Vector2(r.position.x, r.position.y + 37), sub, 12, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if can:
			_buttons.append([r, "hg:gun:" + g])
	_para(Vector2(lx, y + 80.0), Loc.t(String(GUN_HINT[cur])), 300.0, 13, Color(0.65, 0.68, 0.75))
	return y + 122.0


func _hg_weapons(m: Main, area: Rect2) -> void:
	var lx := area.position.x
	var y := area.position.y
	# правка 5 теста 3.5-s5: только оружие этого самолёта; особенность класса (★) отмечена
	var own: Array = Profile.WEAPON_ORDER.filter(func(x): return Weapons.in_game(x) and PlaneClasses.allows(m.hangar_cls, x))
	if not own.has(m.hangar_w) and not Weapons.EXP.has(m.hangar_w) and not own.is_empty():
		m.hangar_w = own[0]
	for w in own:
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
		_text(Vector2(lx + 60, y + 30), Loc.t(String(Weapons.DEFS[w]["short"])), 18, Color.WHITE if on else Color(0.85, 0.88, 0.95))
		var marks := ""
		for tier in [1, 2, 3]:
			var st := Profile.tier_state(w, tier)
			marks += ("●" if st != "" and st != "?" else "○") + " "
		_text(Vector2(lx + 60, y + 54), marks, 15, Menu.C_AMBER)
		if PlaneClasses.signature(m.hangar_cls) == w:
			_text(Vector2(lx + 60, y + 54), "★ особенность класса: +20%", 13, Color(0.6, 1.0, 0.65), HORIZONTAL_ALIGNMENT_RIGHT, 228.0)
		y += 80.0
	_hg_start2(m, lx, _hg_gun(m, lx, y + 6.0))
	var w2 := m.hangar_w
	var rx := lx + 340.0
	var rw := area.size.x - 340.0 - 470.0
	# тест 3.5-s3: оружие — объёмной моделью справа, как самолёт на вкладке «САМОЛЁТ»
	var vx := rx + rw + 20.0
	var vw := 450.0
	var h3 := Hangar3D.ensure(ctrl)
	_panel(Rect2(vx, area.position.y + 40, vw, 400), false)
	var vr := Rect2(vx + 8, area.position.y + 48, vw - 16, 330)
	# тест 3.5-s4 (п. 5): у «Осы» турелей нет — показываем турель «Грача», а не старую заглушку для истребителя
	var wcls := m.hangar_cls
	if w2 == "turret" and int(PlaneClasses.get_data(wcls)["turrets"]) <= 0:
		wcls = "attacker"
	if WeaponModels.WEAPON_GLB.has(w2) or w2 == "turret":
		ctrl.draw_texture_rect(h3.show_weapon(wcls, w2, vr), vr, false)
		_text(Vector2(vr.position.x + 12, vr.end.y - 12), "Тяните мышью — вращение, колесо — приближение", 13, Color(0.7, 0.74, 0.8))
		h3.lvl_rects.clear()
		h3.tier_rects.clear()
		for ti in 4:
			var tr2 := Rect2(vx + 16 + ti * 106, area.position.y + 392, 98, 32)
			var on2: bool = h3.weapon_tier == ti + 1
			ctrl.draw_rect(tr2, Menu.C_AMBER if on2 else Color(1, 1, 1, 0.08))
			_text(Vector2(tr2.position.x, tr2.position.y + 22), (Loc.t("ур. %d") % [1, 3, 5][ti]) if ti < 3 else Loc.t("модерниз."), 15, Color(0.08, 0.07, 0.05) if on2 else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, tr2.size.x)
			h3.tier_rects.append([tr2, ti + 1])
		if w2 == "turret":
			if wcls != m.hangar_cls:
				_text(Vector2(vx + 16, area.position.y + 452), Loc.t("%s: турелей нет. Показана турель: %s") % [Loc.t(PlaneClasses.DATA[m.hangar_cls]["title"]), Loc.t(PlaneClasses.DATA[wcls]["title"])], 14, Color(0.7, 0.74, 0.8))
			else:
				_text(Vector2(vx + 16, area.position.y + 452), Loc.t("Турель класса: %s") % Loc.t(PlaneClasses.DATA[m.hangar_cls]["title"]), 14, Color(0.7, 0.74, 0.8))
	else:
		_text(Vector2(vx + 24, area.position.y + 220), "Встроенное оружие — модель на самолёте", 16, Color(0.7, 0.74, 0.8))
	_text(Vector2(rx, area.position.y + 24), Loc.t("%s — ветки улучшений (действуют, пока оружие на подвесе; общие для всех классов)") % Loc.t(Weapons.DEFS[w2]["title"]), 18, Menu.C_AMBER)
	var yy := area.position.y + 50.0
	for tier in [1, 2, 3]:
		_text(Vector2(rx, yy + 20), Loc.t("Ступень %d%s") % [tier, Loc.t(" · модернизация") if tier == 3 else ""], 18, Color.WHITE)
		var st2 := Profile.tier_state(w2, tier)
		var locked: bool = (tier == 2 and Profile.tier_state(w2, 1) == "") or (tier == 3 and not Profile.tier3_open(w2))
		var why := Loc.t("сначала выберите ступень %d") % (tier - 1)
		if tier == 3 and Profile.tier_state(w2, 2) != "" and not Campaign.cleared(1):
			why = "откроется после операции 2 «Сухое русло» (кампания)"
		elif tier == 3 and Profile.tier_state(w2, 2) == "":
			why = "сначала выберите ступень 2 выше"
		if tier == 3 and not Profile.WBRANCH3.has(w2):
			break
		var demo_lock: bool = tier > Demo.tier_cap()   # демо: ступени 2–3 закрыты
		if demo_lock:
			locked = true
			why = Loc.t("Ступень %d — ") % tier + Loc.t(Demo.LOCKED)
			st2 = ""
		# правка 2 (тест 3.5-s4): как открыть ступень 3 — условия галочками прямо над вариантами
		if tier == 3 and st2 == "" and not demo_lock:
			_text(Vector2(rx + 250, yy + 20), "Нужно:", 15, Color(0.8, 0.84, 0.9))
			_cond_chips(Vector2(rx + 310, yy + 4), [["ступень 2", Profile.tier_state(w2, 2) != ""],
				["операция 2 «Сухое русло»", Campaign.cleared(1)],
				[Loc.t("%d запч.") % int(Profile.TIER_COST[2]), Profile.parts() >= int(Profile.TIER_COST[2])],
				["самолёт ур. 2", Profile.plane_lvl(m.hangar_cls) == 2]])
		for oi in 2:
			var opt: Array = Profile.WBRANCH[w2][tier - 1][oi] if tier < 3 else Profile.WBRANCH3[w2][oi]
			var key := "a" if oi == 0 else "b"
			var r2 := Rect2(rx + oi * (rw / 2.0 + 5), yy + 32, rw / 2.0 - 5, 120)
			var picked := st2 == key
			_panel(r2, picked)
			if picked:
				ctrl.draw_rect(r2, Color(0.5, 1.0, 0.6), false, 3.0)
			_text(Vector2(r2.position.x + 18, r2.position.y + 32), String(opt[0]), 19, Color(0.6, 1.0, 0.7) if picked else Color.WHITE)
			_text(Vector2(r2.position.x + 18, r2.position.y + 60), String(opt[1]), 15, Color(0.8, 0.84, 0.9))
			if locked:
				_text(Vector2(r2.position.x + 18, r2.position.y + 98), why, 14, Color(0.6, 0.62, 0.68))
			elif st2 == "?":
				_button(Rect2(r2.position.x + 18, r2.position.y + 74, 200, 38), "ВЫБРАТЬ (оплачено)", "hg:tier:%s:%d:%s" % [w2, tier, key], 14)
			elif st2 == "":
				var price: int = Profile.TIER_COST[tier - 1]
				if Profile.parts() >= price:
					_button(Rect2(r2.position.x + 18, r2.position.y + 74, 200, 38), Loc.t("ВЗЯТЬ — %d") % price, "hg:tier:%s:%d:%s" % [w2, tier, key], 14)
				else:
					_text(Vector2(r2.position.x + 18, r2.position.y + 98), Loc.t("%d запчастей") % price, 14, Color(0.65, 0.65, 0.7))
		if st2 != "" and st2 != "?" and not demo_lock:
			_button(Rect2(rx + rw - 260, yy, 260, 30), Loc.t("переиграть — %d") % Profile.REDO_COST[tier - 1], "hg:redo:%s:%d" % [w2, tier], 13)
		yy += 170.0


func _hg_crew(c: String, area: Rect2) -> void:
	var cd: Dictionary = Profile.cls(c)
	var lx := area.position.x
	var lw := 460.0
	_panel(Rect2(lx, area.position.y, lw, area.size.y), false)
	var y := area.position.y + 40.0
	_text(Vector2(lx + 24, y), Loc.t("Позывной: «%s»") % cd["callsign"], 22, Color.WHITE)
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
		_text(Vector2(lx + 24, y), Loc.t("Черта: «%s»") % Loc.t(tr["title"]), 18, Menu.C_AMBER)
		y += 24.0
		_text(Vector2(lx + 24, y), "+ " + String(tr["plus"]), 15, Color(0.6, 1.0, 0.7))
		y += 22.0
		_text(Vector2(lx + 24, y), "− " + String(tr["minus"]), 15, Color(1.0, 0.6, 0.55))
	y = maxf(y + 40.0, pr_r.end.y + 34.0) # под портретом
	var lv := Profile.crew_lvl(c)
	var pr := Profile.crew_progress(c)
	_text(Vector2(lx + 24, y), Loc.t("Экипаж ур. %d") % lv, 26, Color(0.6, 1.0, 0.7))
	y += 18.0
	ctrl.draw_rect(Rect2(lx + 24, y, lw - 48, 14), Color(0, 0, 0, 0.5))
	if int(pr[1]) > 0:
		ctrl.draw_rect(Rect2(lx + 24, y, (lw - 48) * minf(1.0, float(pr[0]) / float(pr[1])), 14), Color(0.5, 1.0, 0.6))
		var ready := Profile.promote_ready(c)
		_text(Vector2(lx + 24, y + 36), (Loc.t("опыт для ур. %d набран") % (lv + 1)) if ready else Loc.t("%d / %d опыта до ур. %d") % [pr[0], pr[1], lv + 1], 15,
			Color(1.0, 0.9, 0.4) if ready else Color(0.8, 0.84, 0.9))
		y += 50.0
		var cost := Profile.promote_cost(lv + 1)
		var can := Profile.can_promote(c)
		var br := Rect2(lx + 24, y, lw - 48, 40)
		if can:
			_button(br, Loc.t("ПОВЫСИТЬ В ЗВАНИИ — %d запчастей") % cost, "hg:promote", 15)
		else:
			_panel(br, false)
			_text(Vector2(br.position.x + 14, br.position.y + 26), (Loc.t("Повысить в звании — %d (не хватает запчастей)") % cost) if Profile.promote_ready(c) else Loc.t("Повысить в звании — %d (нужен опыт)") % cost, 14, Color(0.6, 0.62, 0.68))
		y += 40.0
	elif Demo.on and lv >= Demo.crew_cap():
		y += 36.0
		_text(Vector2(lx + 24, y), Loc.t("Следующие звания — ") + Loc.t(Demo.LOCKED), 15, Color(0.6, 0.62, 0.68))
	y += 34.0
	_para(Vector2(lx + 24, y), Loc.t("Рост показателей: ") + String(Profile.CREW[c]["stats"]), lw - 48, 15)
	y += 56.0
	_text(Vector2(lx + 24, y), "Открытия по уровню экипажа:", 16, Menu.C_AMBER)
	var unl := [[3, "2-й навык класса; самолёт ур. 2"], [4, "ведомый «Ласка»"], [5, "2-й слот навыка [F]"], [6, "перки 2-й ступени"], [7, "3-й навык класса"], [8, "ведомый «Грачонок»"]]
	for u in unl:
		y += 24.0
		_text(Vector2(lx + 24, y), ("✓ " if lv >= int(u[0]) else "· ") + Loc.t("ур. %d — %s") % [u[0], u[1]], 15, Color(0.6, 1.0, 0.7) if lv >= int(u[0]) else Color(0.7, 0.72, 0.78))
	# перки
	var px := lx + lw + 30.0
	var pw := 820.0
	_text(Vector2(px, area.position.y + 24), Loc.t("ПЕРКИ — очков: %d (на чётных уровнях)") % Profile.perk_points(c), 18, Menu.C_AMBER)
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
				_text(Vector2(r.position.x + 14, r.position.y + 60), Loc.t("ступень %d — в разработке") % (ti + 1), 14, Color(0.55, 0.57, 0.62))
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
				_text(Vector2(r.position.x + 14, r.end.y - 8), Loc.t("с экипажа ур. %d") % Profile.PERK_T2_LVL, 12, Color(0.6, 0.62, 0.68))
	# слоты навыков
	var sx := px + pw + 30.0
	var sw := area.end.x - sx
	_text(Vector2(sx, area.position.y + 24), "НАВЫКИ КЛАССА", 18, Menu.C_AMBER)
	var sks: Array = Profile.skills(c)
	var yy := area.position.y + 50.0
	for slot in 2:
		var open := slot == 0 or Profile.slot2_open(c)
		_text(Vector2(sx, yy + 18), "Слот %d [%s]%s" % [slot + 1, "E" if slot == 0 else "F", "" if open else " — экипаж ур. %d" % Profile.SLOT2_LVL], 16, Color.WHITE if open else Color(0.6, 0.62, 0.68))
		yy += 26.0
		for sk in PlaneClasses.CLASS_SKILLS[c]:
			# высота по описанию: две строки не наезжают на следующий навык
			var sh3 := ui_font().get_multiline_string_size(Loc.out(String(PlaneClasses.SKILL3[sk]["short"])), HORIZONTAL_ALIGNMENT_LEFT, sw - 28.0, 13).y
			var r3 := Rect2(sx, yy, sw, maxf(64.0, 30.0 + sh3))
			var unlocked := Profile.skill_unlocked(c, sk)
			var sel: bool = sks[slot] == sk
			# правка 7: навык из другого слота сюда не ставится — два одинаковых навыка взять нельзя
			var busy: bool = not sel and sks[1 - slot] == sk
			ctrl.draw_rect(r3, Color(0.55, 0.9, 0.55, 0.18) if sel else Color(1, 1, 1, 0.04))
			if open and unlocked and not busy:
				_buttons.append([r3, "hg:slot:%d:%s" % [slot, sk]])
			var i: int = PlaneClasses.CLASS_SKILLS[c].find(sk)
			var tail := ""
			if not unlocked:
				tail = Loc.t(" (экипаж ур. %d)") % Profile.SKILL_UNLOCK[i]
			elif busy:
				tail = Loc.t(" — уже в слоте %d") % (2 - slot)
			_text(Vector2(sx + 10, yy + 21), ("● " if sel else "○ ") + Loc.t(String(PlaneClasses.SKILL3[sk]["title"])) + tail, 15,
				Color(0.7, 1.0, 0.7) if sel else (Color(0.85, 0.88, 0.95) if unlocked and open and not busy else Color(0.55, 0.57, 0.62)))
			# правка 6: что делает навык — строкой под названием
			_para(Vector2(sx + 22, yy + 39), Loc.t(String(PlaneClasses.SKILL3[sk]["short"])), sw - 28.0, 13, Color(0.72, 0.76, 0.84) if open else Color(0.5, 0.52, 0.58))
			yy += r3.size.y + 4.0
		yy += 12.0
	_text(Vector2(sx, yy + 10), "Слот 3 — экипаж ур. 12, в разработке", 14, Color(0.55, 0.57, 0.62))
	_para(Vector2(sx, yy + 40), "Карточки «уровень навыка» улучшают навык слота 1.", sw, 13, Color(0.7, 0.72, 0.78))
