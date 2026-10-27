class_name HudHangar
extends HudKit
## 3.2: ангар — самолёт и узлы, ветки оружия, экипаж и перки, слоты навыков.


# ---------- 3.2: ангар ----------

## Drawer of the «НАГРАДЫ» tab (created on first use)
var _medals: HudMedals
## Decal editor panel (created on first use)
var _decals: HudDecals

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
	if not Demo.on:
		tabs.append(["medals", "НАГРАДЫ"])   # Kanta 27.10: medals with small bonuses, not in the demo
	for i in tabs.size():
		var r2 := Rect2(size.x / 2.0 - tabs.size() * 150.0 + i * 300.0, 182, 290, 44)
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
		"medals":
			if _medals == null:
				_medals = HudMedals.new(ctrl, _buttons)
			_medals.draw(m, area)
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
	var lw := 680.0   # s13: wider (was 560), the 3D view gets the room; the node cards still fit on the right
	_panel(Rect2(lx, area.position.y, lw, area.size.y), false)
	var bought: bool = bool(Profile.cls(c)["plane2"])
	# 3.4-t1 (п. 1): объёмная модель — тянуть мышью, колесо — приближение; ур. 2 виден и не купленным
	var h3 := Hangar3D.ensure(ctrl)
	# S9-02: узлы того самолёта, что на виде (раньше — того, что выбран в вылет: смотрели ур. 1, а улучшался ур. 2)
	var vl: int = h3.view_lvl if bought else 1
	# s13 (Kanta's video: a small model window top left, the panel's bottom empty): the view takes all the height
	# the controls below leave free (434 px at 1080p instead of 330); dy moves the controls down with it
	var vh := maxf(330.0, area.size.y - 266.0)   # 266: the controls and the «buy» button under the view
	var dy := vh - 330.0
	var vr := Rect2(lx + 8, area.position.y + 8, lw - 16, vh)
	ctrl.draw_texture_rect(h3.show_plane(c, vr), vr, false)
	var editing := Main.I.decal_edit != null
	if editing:
		_text(Vector2(vr.position.x + 12, vr.end.y - 12), "Щёлкните по самолёту — поставить знак; правая кнопка — вращение", 14, Color(0.85, 0.88, 0.95))
		if h3.decal_pad and vr.has_point(h3.decal_cursor):   # the gamepad cursor
			var cp := h3.decal_cursor
			for d: Vector2 in [Vector2(1, 0), Vector2(0, 1)]:
				ctrl.draw_line(cp - d * 14, cp + d * 14, Color(0, 0, 0, 0.7), 4.0)
				ctrl.draw_line(cp - d * 14, cp + d * 14, Color.WHITE, 2.0)
	else:
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
		var br := Rect2(lx + 24 + (lv - 1) * 150, area.position.y + dy + 348, 140, 36)
		var on: bool = h3.view_lvl == lv
		ctrl.draw_rect(br, Menu.C_AMBER if on else Color(1, 1, 1, 0.08))
		_text(Vector2(br.position.x, br.position.y + 25), Loc.t("Ур. %d") % lv, 17, Color(0.08, 0.07, 0.05) if on else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		h3.lvl_rects.append([br, lv])
	if bought:
		# 3.5: выбор самолёта на вылет — для уровня, который сейчас на виде
		var sel := Profile.plane_lvl(c)
		var sr := Rect2(lx + 330, area.position.y + dy + 348, 210, 36)
		if h3.view_lvl == sel:
			_panel(sr, true)
			ctrl.draw_rect(sr, Color(0.5, 1.0, 0.6), false, 2.0)
			_text(Vector2(sr.position.x, sr.position.y + 25), Loc.t("✓ ур. %d — в вылет") % sel, 16, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
		else:
			_button(sr, Loc.t("ЛЕТАТЬ НА УР. %d") % h3.view_lvl, "hg:plane_sel:%d" % h3.view_lvl, 14)
	elif h3.view_lvl == 2:
		_text(Vector2(lx + 330, area.position.y + dy + 372), "не куплен — в вылет недоступен", 15, Color(1.0, 0.75, 0.45))
	# п. 3: как оружие меняется с уровнем
	h3.tier_rects.clear()
	_text(Vector2(lx + 24, area.position.y + dy + 414), "Вид оружия:", 15, Color(0.8, 0.84, 0.9))
	for ti in 4:
		var tr2 := Rect2(lx + 130 + ti * 100, area.position.y + dy + 392, 92, 30)
		var on2: bool = h3.weapon_tier == ti + 1
		ctrl.draw_rect(tr2, Menu.C_AMBER if on2 else Color(1, 1, 1, 0.08))
		_text(Vector2(tr2.position.x, tr2.position.y + 21), (Loc.t("ур. %d") % [1, 3, 5][ti]) if ti < 3 else Loc.t("модерниз."), 15, Color(0.08, 0.07, 0.05) if on2 else Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER, tr2.size.x)
		h3.tier_rects.append([tr2, ti + 1])
	_hg_livery(c, lx, area.position.y + dy + 432)
	# decal editor (spec 2026-10-27-plane-decals-design.md §6): opens in place of the node cards
	var dr := Rect2(lx + 556, area.position.y + dy + 432, lw - 580, 30)
	ctrl.draw_rect(dr, Menu.C_AMBER if editing else Color(1, 1, 1, 0.08))
	ctrl.draw_rect(dr, Menu.C_AMBER, false, 1.0)
	_text(Vector2(dr.position.x, dr.position.y + 21), Loc.t("‹ Знаки") if editing else Loc.t("Знаки ›"), 15, Color(0.08, 0.07, 0.05) if editing else Color(0.95, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER, dr.size.x)
	_buttons.append([dr, "hg:dc:close" if editing else "hg:dc:open"])
	var y := area.position.y + dy + 486.0
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
	if editing:
		if _decals == null:
			_decals = HudDecals.new(ctrl, _buttons)
		_decals.draw(Main.I, Rect2(rx, yy, rw, area.size.y))
		return
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


## Тест 3.5-s4, п. 35: ряд «Окраска: …» — выбор сохраняется в профиле класса, виден в ангаре и в бою.
## Kanta 27.10 took ten more liveries (17 per class): a row of buttons left ~26 px each, so the row is an option
## «‹ value ›» (ui-design-system.md §3): ‹ and › step to the previous / next paint (wrapping round), the middle shows
## the current one and its place in the list, a click on it steps forward. Every part is a button, so the gamepad
## focus reaches them as before.
func _hg_livery(c: String, lx: float, y: float) -> void:
	_text(Vector2(lx + 24, y + 21), "Окраска:", 15, Color(0.8, 0.84, 0.9))
	var lst := Livery.list(c)
	if lst.is_empty():
		return
	var cur := Livery.current(c)
	var i := 0
	for k in lst.size():
		if lst[k][0] == cur:
			i = k
	var prev := String(lst[(i - 1 + lst.size()) % lst.size()][0])
	var next := String(lst[(i + 1) % lst.size()][0])
	var rl := Rect2(lx + 100, y, 40, 30)
	var rm := Rect2(lx + 146, y, 360, 30)
	var rr := Rect2(lx + 512, y, 40, 30)
	var tc := Color(0.85, 0.88, 0.95)
	for b: Array in [[rl, "‹", prev], [rr, "›", next]]:
		var br: Rect2 = b[0]
		ctrl.draw_rect(br, Color(1, 1, 1, 0.08))
		ctrl.draw_rect(br, Menu.C_AMBER, false, 1.0)
		_text(Vector2(br.position.x, br.position.y + 23), String(b[1]), 20, Menu.C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		_buttons.append([br, "hg:livery:" + String(b[2])])
	ctrl.draw_rect(rm, Color(1, 1, 1, 0.08))
	_text(Vector2(rm.position.x + 12, rm.position.y + 21), Loc.t(String(lst[i][1])), 15, Color.WHITE)
	_text(Vector2(rm.position.x, rm.position.y + 21), "%d / %d" % [i + 1, lst.size()], 13, tc, HORIZONTAL_ALIGNMENT_RIGHT, rm.size.x - 12)
	_buttons.append([rm, "hg:livery:" + next])


## S11-09 (Kanta 25.10): heading and counter of the starting-weapons list; returns the y below them
func _hg_start_head(m: Main, lx: float, y: float, w: float) -> float:
	var c := m.hangar_cls
	_text(Vector2(lx, y + 18), Loc.t("Выбор стартового вооружения (не более 2 видов)"), 17, Menu.C_AMBER)
	var n := Profile.start_weapons(c).size()
	var cap := Profile.start_cap(c)
	var line := Loc.t("На старте %d из %d.") % [n, cap]
	if n >= cap and cap >= 2:
		line += " " + Loc.t("Чтобы поставить другое, сначала снимите одно.")
	elif cap < 2:
		line += " " + Loc.t("Второе место — с ур. экипажа %d.") % Profile.START2_LVL
	var h := _para(Vector2(lx, y + 40), line, w, 13, Color(0.65, 0.68, 0.75))
	return y + 30.0 + h + 10.0


## PG-01 (Kanta 24.10): course gun of the plane (class + plane level) — bought once for parts, switched for free before a sortie
const LEFT_W := 420.0   # S11-04: left column of the weapons tab (gun, ammo, start list)
const GUN_TITLE := {"std": "Стандартная", "twin": "Спарка", "heavy": "Крупный калибр"}
const GUN_HINT := {
	"std": "Обычная пушка: ровный темп и урон.",
	"twin": "Темп ×1,6, урон ×0,65, лёгкий разброс — против роя дронов, быстрее разгоняет «обороты».",
	"heavy": "Темп ×0,55, урон ×2, снаряд быстрее.",
}
const AMMO_TITLE := {"std": "Обычные", "ap": "Бронебойные", "he": "Осколочные", "inc": "Зажигательные"}
const AMMO_HINT := {
	"std": "Обычные снаряды: полный урон и скорость.",
	"ap": "Бронебойные: урон ×0,75, скорость ×1; пробивают броню. Лучше всего по одной крепкой цели.",
	"he": "Осколочно-фугасные: урон ×1, скорость ×0,75; осколки задевают соседей. Лучше всего по группе.",
	"inc": "Зажигательные: урон ×0,85, скорость ×0,8; цель горит, огонь копится. Лучше всего по боссам.",
}


func _hg_gun(m: Main, lx: float, y: float, w: float) -> float:
	var c := m.hangar_cls
	_text(Vector2(lx, y + 14), Loc.t("Курсовая пушка этого самолёта"), 16, Color.WHITE)
	var cur := Profile.gun(c)
	_kit_row(WeaponBalance.GUN_ORDER, GUN_TITLE, WeaponBalance.GUN_PRICE, cur, Profile.guns(c), "hg:gun:", lx, y + 22.0, w, "✓ выбрана")
	var h := _para(Vector2(lx, y + 80.0), Loc.t(String(GUN_HINT[cur])), w, 13, Color(0.65, 0.68, 0.75))   # S11-05: its own text
	return y + 68.0 + h + 14.0


## PG-01 (Kanta 24.10): ammo type of the plane's course gun — same buy-once, switch-free rule as the gun.
## S11-05: the ammo hint sits under the ammo row only (the gun has its own); returns the y below it.
func _hg_ammo(m: Main, lx: float, y: float, w: float) -> float:
	var c := m.hangar_cls
	_text(Vector2(lx, y + 14), Loc.t("Снаряды"), 16, Color.WHITE)
	var cur := Profile.ammo(c)
	_kit_row(WeaponBalance.AMMO_ORDER, AMMO_TITLE, WeaponBalance.AMMO_PRICE, cur, Profile.ammos(c), "hg:ammo:", lx, y + 22.0, w, "✓ выбраны")
	var h := _para(Vector2(lx, y + 80.0), Loc.t(String(AMMO_HINT[cur])), w, 13, Color(0.65, 0.68, 0.75))
	return y + 68.0 + h + 20.0


## One row of buy-once / select-free buttons (course guns or ammo) across width `w`
func _kit_row(order: Array, titles: Dictionary, prices: Dictionary, cur: String, owned: Array, act: String, lx: float, y: float, w: float, sel: String) -> void:
	var step := w / order.size()
	for i in order.size():
		var id: String = order[i]
		var r := Rect2(lx + i * step, y, step - 6.0, 40.0)
		var on := cur == id
		var has := owned.has(id)
		var price := int(prices[id])
		var can := has or Profile.parts() >= price
		ctrl.draw_rect(r, Menu.C_AMBER if on else Color(1, 1, 1, 0.08 if can else 0.04))
		var tc := Color(0.08, 0.07, 0.05) if on else (Color(0.85, 0.88, 0.95) if can else Color(0.55, 0.57, 0.62))
		_text(Vector2(r.position.x, r.position.y + 17), Loc.t(String(titles[id])), 13, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var sub := Loc.t(sel) if on else (Loc.t("выбрать") if has else Loc.t("%d зап.") % price)
		_text(Vector2(r.position.x, r.position.y + 34), sub, 12, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if can:
			_buttons.append([r, act + id])


## Weapons tab. S11-04/05/09 (Kanta 25.10): the left column holds all weapon setup — course gun and ammo on top,
## then one list of this plane's weapons with a «На старт» toggle each (at most two kinds start);
## a click on a card shows its upgrade branches in the middle, the 3D model stays on the right.
func _hg_weapons(m: Main, area: Rect2) -> void:
	var lx := area.position.x
	var lw := LEFT_W
	var c := m.hangar_cls
	var opts: Array = Profile.start_options(c)
	var own: Array = opts.duplicate()
	if PlaneClasses.allows(c, "turret") and Weapons.in_game("turret"):
		own.append("turret")   # turrets are fixed on the plane: branches only, no start toggle
	if not own.has(m.hangar_w) and not Weapons.EXP.has(m.hangar_w) and not own.is_empty():
		m.hangar_w = own[0]
	if Hangar3D.bench_tab_w != "":
		m.hangar_w = Hangar3D.bench_tab_w
	_text(Vector2(lx, area.position.y + 20), Loc.t("КУРСОВАЯ ПУШКА"), 17, Menu.C_AMBER)
	var y := _hg_ammo(m, lx, _hg_gun(m, lx, area.position.y + 26.0, lw), lw)
	y = _hg_start_head(m, lx, y, lw)
	var picks := Profile.start_weapons(c)
	var full := picks.size() >= Profile.start_cap(c)
	for w: String in own:
		var r := Rect2(lx, y, lw, 56)
		var on: bool = m.hangar_w == w
		_panel(r, on)
		_buttons.append([r, "hg:wsel:" + w])
		var t := PlaneArt.weapon_tex(w)
		if t != null:
			var k := 44.0 / t.get_height()
			ctrl.draw_set_transform(Vector2(lx + 26, y + 28), 0.0, Vector2(k, k))
			ctrl.draw_texture(t, -t.get_size() / 2.0)
			ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(Vector2(lx + 54, y + 24), Loc.t(String(Weapons.DEFS[w]["short"])), 17, Color.WHITE if on else Color(0.85, 0.88, 0.95))
		var sub := ""
		if Profile.WBRANCH.has(w):
			for tier in [1, 2, 3]:
				var st := Profile.tier_state(w, tier)
				sub += ("●" if st != "" and st != "?" else "○") + " "
		_text(Vector2(lx + 54, y + 46), sub, 14, Menu.C_AMBER)
		var bk := PlaneClasses.bonus_k(c, 0, w)
		if bk > 1.0:
			_text(Vector2(lx + 54 + (52.0 if sub != "" else 0.0), y + 46), Loc.t("★ бонус самолёта: +%d%%") % roundi((bk - 1.0) * 100.0), 12, Color(0.6, 1.0, 0.65))
		var br := Rect2(lx + lw - 138, y + 12, 126, 32)
		if opts.has(w):
			var picked := picks.has(w)
			var can := picked or not full
			ctrl.draw_rect(br, Menu.C_AMBER if picked else Color(1, 1, 1, 0.08 if can else 0.03))
			if not picked:
				ctrl.draw_rect(br, Color(1, 1, 1, 0.25 if can else 0.08), false, 1.0)
			var lbl := (Loc.t("✓ подвес %d") % (picks.find(w) + 1)) if picked else Loc.t("На старт")
			_text(Vector2(br.position.x, br.position.y + 22), lbl, 14, Color(0.08, 0.07, 0.05) if picked else (Color(0.85, 0.88, 0.95) if can else Color(0.45, 0.47, 0.52)), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
			if can:
				_buttons.append([br, "hg:start:" + w])
		else:
			_text(Vector2(br.position.x, br.position.y + 22), Loc.t("всегда на самолёте"), 12, Color(0.6, 0.62, 0.68), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		y += 62.0
	var w2 := m.hangar_w
	var rx := lx + lw + 36.0
	var rw := area.size.x - lw - 36.0 - 470.0
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
		# «модерниз.» only for weapons that evolve in battle (Prog.EVOS); agm, srm, hebomb have no evolution
		var tiers := 4 if Prog.EVOS.has(w2) else 3
		if h3.weapon_tier > tiers:
			h3.weapon_tier = tiers
		for ti in tiers:
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
	if not Profile.WBRANCH.has(w2):   # PG-01: new weapons get hangar branches in PG-03 — say so instead of an empty panel
		_para(Vector2(rx, yy + 30), Loc.t("У этого оружия веток улучшений в ангаре пока нет: они появятся в следующем этапе прокачки. В бою оно растёт по уровням 1–5 карточками, как и остальное оружие."), rw, 16, Color(0.75, 0.78, 0.84))
	for tier in ([1, 2, 3] if Profile.WBRANCH.has(w2) else []):   # PG-01: new weapons get hangar branches in PG-03
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
