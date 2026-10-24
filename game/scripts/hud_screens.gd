class_name HudScreens
extends HudKit
## Экраны поверх игры: выбор карточек и курса, пауза (подвесы), итоги вылета. Выбор самолёта — на экране «В вылет» (HudCampaign).


# ---------- Карточки ----------

## S9-05: подсказки при наведении на значки «Оснащения» — [Rect2, заголовок, текст]
var _tips: Array = []


func levelup(m: Main, size: Vector2) -> void:
	# EX-12 (вариант «Яркая аркада», Kanta 22.10): сочные карточки 2×2 слева, справа — «Оснащение» (EX-02)
	_tips.clear()
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.025, 0.88))
	var right_w := 440.0
	var lx := 48.0
	var lw := size.x - right_w - lx - 40.0
	var pair: bool = not m.offers.is_empty() and m.offers[0]["kind"] == "branch" and bool(m.offers[0]["first"])
	if pair:
		# S9-15: мастерство оружия «или-или»
		_text(Vector2(lx, 120), Loc.t("МАСТЕРСТВО ОРУЖИЯ: ИЛИ-ИЛИ"), 40, Color(1.0, 0.82, 0.29))
	elif m.offer_rare:
		_text(Vector2(lx, 120), Loc.t("НАГРАДА %s: ВЫБОР ИЗ РЕДКИХ КАРТОЧЕК") % (m.run.rare_reasons[0] if not m.run.rare_reasons.is_empty() else ""), 38, Color(0.8, 0.55, 1.0))
	else:
		_text(Vector2(lx, 120), Loc.t("НОВЫЙ УРОВЕНЬ: %d") % m.run.level if m.run.pending_levels <= 1 else Loc.t("НОВЫЙ УРОВЕНЬ (ещё выборов: %d)") % m.run.pending_levels, 40, Color(1.0, 0.82, 0.29))
	if pair:
		_text(Vector2(lx, 158), "Выберите одну ветку для этого оружия — вторая закроется до конца вылета. 1 или 2 — выбрать", 16, Color(1.0, 0.9, 0.6))
	elif m.levelup_intro:
		# U-03: первые выборы — что это и как выбирать
		_text(Vector2(lx, 156), "Выберите одно улучшение — оно действует до конца вылета. Не знаете, что взять? Берите оружие, которое уже стоит на самолёте.", 16, Color(1.0, 0.9, 0.6))
		_text(Vector2(lx, 178), "1–4 или клик — выбрать · «Переброс» — показать другие карточки · «Закрепить» — оставить на следующий раз · «Исключить» — больше не предлагать", 14, Color(0.75, 0.8, 0.9))
	else:
		_text(Vector2(lx, 158), "1–4 или клик — выбрать · R — переброс · «Закрепить» — будет в следующем выборе · «Исключить» — не выпадет до конца вылета", 16, Color(0.75, 0.8, 0.9))
	var n := m.offers.size()
	var rows := maxi(1, int(ceil(n / 2.0)))
	var gap := 60.0 if pair else 18.0
	var top := 196.0
	var cw := (lw - gap) / 2.0
	var ch := minf(360.0 if pair else 290.0, (size.y - top - 120.0 - gap * (rows - 1)) / rows)
	var mp := ctrl.get_local_mouse_position()
	for i in n:
		var r := Rect2(lx + (i % 2) * (cw + gap), top + (i / 2) * (ch + gap), cw, ch)
		_card(m, i, r, r.has_point(mp))
	if pair and n == 2:
		var oc := Vector2(lx + cw + gap * 0.5, top + ch * 0.5)
		ctrl.draw_circle(oc, 27.0, Color(0.06, 0.08, 0.06))
		ctrl.draw_arc(oc, 27.0, 0.0, TAU, 40, Color(1.0, 0.82, 0.29), 3.0)
		_text(Vector2(oc.x - 27.0, oc.y + 7.0), Loc.t("ИЛИ"), 18, Color(1.0, 0.86, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 54.0)
	var ry := top + rows * (ch + gap) + 4.0
	if m.rerolls > 0:
		_button(Rect2(lx, ry, 330, 46), Loc.t("Переброс (R) — осталось %d") % m.rerolls, "reroll", 18)
		if m.player.has_course():
			_button(Rect2(lx + 344, ry, 420, 46), "Сменить специализацию (−1 переброс)", "change_course", 18)
	else:
		_text(Vector2(lx, ry + 30), "Перебросов не осталось (+1 за каждого аса)", 17, Color(0.6, 0.62, 0.7))
	_para(Vector2(lx, ry + 74), Loc.t("Исключений осталось: %d (+1 за аса)%s") % [m.bans, (Loc.t("   ·   Исключены: ") + ", ".join(PackedStringArray(m.banned.values().map(func(x): return Loc.title(String(x)))))) if not m.banned.is_empty() else ""], lw, 15, Color(0.75, 0.75, 0.85))
	_kit_panel(m, Rect2(size.x - right_w - 24.0, 96.0, right_w, size.y - 130.0))
	_tooltip(mp, size)


## S9-05: плашка подсказки у курсора — что это за оружие, модуль или модернизация
func _tooltip(mp: Vector2, size: Vector2) -> void:
	for t in _tips:
		if not (t[0] as Rect2).has_point(mp):
			continue
		var w := 380.0
		var body := Loc.out(String(t[2]))
		var bh := ui_font().get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, w - 28.0, 15).y
		var r := Rect2(mp + Vector2(-w - 18.0, 18.0), Vector2(w, 50.0 + bh))
		r.position.x = maxf(12.0, r.position.x)
		r.position.y = minf(r.position.y, size.y - r.size.y - 12.0)
		ctrl.draw_rect(r, Color(0.03, 0.04, 0.035, 0.96))
		ctrl.draw_rect(r, Color(1.0, 0.82, 0.29), false, 2.0)
		_text(Vector2(r.position.x + 14, r.position.y + 28), String(t[1]), 18, Color(1.0, 0.86, 0.45))
		_para(Vector2(r.position.x + 14, r.position.y + 50), String(t[2]), w - 28.0, 15, Color(0.9, 0.92, 0.88))
		return


func _weapon_tip(w: String) -> String:
	return Loc.t(String(Weapons.DEFS[w].get("desc", ""))) if Weapons.DEFS.has(w) else ""


## EX-12: одна карточка — заливка по редкости, свечение, полоса редкости, медаль со значком, деления уровня, путь к модернизации
func _card(m: Main, i: int, r: Rect2, hover: bool) -> void:
	var c: Dictionary = m.offers[i]
	var rar: Dictionary = Cards.RARITY[int(c["rarity"])]
	var evo: bool = c["kind"] in ["evolution", "mastery"]
	var rc: Color = Color(1.0, 0.82, 0.29) if evo else rar["color"]
	# S10-01: «или-или» — каждая ветка своего цвета: скорострел синий, калибр оранжевый
	var either: bool = c["kind"] == "branch" and bool(c["first"])
	if either:
		rc = Color(0.4, 0.75, 1.0) if c["branch"] == "rate" else Color(1.0, 0.6, 0.2)
	var dark := rc.darkened(0.45)
	var lift := -6.0 if hover else 0.0
	r.position.y += lift
	# свечение: несколько рамок с убывающей прозрачностью
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004) if (hover or evo) else 0.35
	for k in 4:
		var g := 3.0 + k * 4.0
		ctrl.draw_rect(r.grow(g), Color(rc.r, rc.g, rc.b, (0.16 - k * 0.035) * (0.6 + pulse)), false, 4.0)
	# заливка: сверху цвет редкости, книзу графит
	var base := Color(0.09, 0.11, 0.09, 0.97)
	ctrl.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([Color(dark, 0.98), Color(dark.lerp(base, 0.3), 0.98), base.lerp(dark, 0.25), base]))
	ctrl.draw_rect(r, rc, false, 3.0)
	_buttons.append([r, "card:%d" % i])
	# полоса редкости
	ctrl.draw_rect(Rect2(r.position, Vector2(r.size.x, 32)), rc)
	_text(Vector2(r.position.x + 16, r.position.y + 23), "%d · %s" % [i + 1, Loc.t("ВЕТКА МАСТЕРСТВА") if either else Loc.t("МОДЕРНИЗАЦИЯ") if c["kind"] == "evolution" else Loc.t(rar["name"]).to_upper()], 17, Color(0.06, 0.08, 0.06))
	_text(Vector2(r.position.x, r.position.y + 23), Loc.t(String(c["cat"])).to_upper(), 15, Color(0.06, 0.08, 0.06), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16.0)
	# медаль со значком
	var mc := r.position + Vector2(62, 92)
	ctrl.draw_circle(mc, 46.0, Color(rc.r, rc.g, rc.b, 0.25 + 0.15 * pulse))
	ctrl.draw_circle(mc, 40.0, dark)
	ctrl.draw_circle(mc + Vector2(-8, -10), 26.0, Color(rc.r, rc.g, rc.b, 0.45))
	ctrl.draw_arc(mc, 40.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.5)
	CardIcons.draw(ctrl, mc, 44.0, CardIcons.key(c, m.player), Color.WHITE)
	CardIcons.badge(ctrl, mc, 44.0, String(c["kind"]), rc)
	# название и уровень делениями
	var tx := r.position.x + 124.0
	var tw := r.size.x - 140.0
	var th := _para(Vector2(tx, r.position.y + 70), Loc.title(c["title"]), tw, 23, Color.WHITE)
	var lv := _card_level(m.player, c)
	var py := r.position.y + 70 + maxf(th, 26.0) + 2.0
	if lv.y > 0:
		for k in int(lv.y):
			var pr := Rect2(tx + k * 28.0, py - 8, 22, 8)
			ctrl.draw_rect(pr, rc if k < int(lv.x) else Color(1, 1, 1, 0.18))
			if k == int(lv.x):
				ctrl.draw_rect(pr.grow(1.5), Color.WHITE, false, 2.0)
		_text(Vector2(tx + lv.y * 28.0 + 6.0, py), Loc.t("ур. %d → %d") % [lv.x, mini(int(lv.x) + 1, int(lv.y))], 14, Color(0.9, 0.88, 0.8))
	var ty := maxf(py + 14.0, r.position.y + 146.0)
	if c.get("tags", "") != "":
		_tag_chips(Vector2(r.position.x + 18, ty), Prog.card_tags(m.player, c), c["kind"] == "evolution")
		ty += 28.0
	# путь к модернизации — жёлтая плашка внизу; длинное описание ужимаем, чтобы не залезало на неё
	var path := _card_path(m.player, c)
	var bottom := r.end.y - 40.0
	var desc := Loc.out(Loc.t(c["desc"]))
	if either:
		# главное — крупно, «вторая ветка закроется» — красной плашкой внизу
		var main_txt := desc.get_slice("\n", 0)
		var warn := desc.substr(main_txt.length()).strip_edges()
		_para(Vector2(r.position.x + 18, ty + 18), main_txt, r.size.x - 36.0, 22, Color(1.0, 0.98, 0.9))
		if warn != "":
			var wr := Rect2(r.position.x + 14, r.end.y - 74.0, r.size.x - 28.0, 58.0)
			ctrl.draw_rect(wr, Color(0.85, 0.2, 0.15, 0.22))
			ctrl.draw_rect(wr, Color(1.0, 0.45, 0.35, 0.8), false, 2.0)
			_para(Vector2(wr.position.x + 12, wr.position.y + 22), warn, wr.size.x - 24.0, 16, Color(1.0, 0.78, 0.7))
		return
	var fs := 15
	while fs > 12 and ui_font().get_multiline_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0, fs).y > bottom - ty - 8.0:
		fs -= 1
	_para(Vector2(r.position.x + 18, ty + 12), desc, r.size.x - 36.0, fs, Color(1.0, 0.98, 0.9))
	if path != "":
		ctrl.draw_rect(Rect2(r.position.x + 14, bottom, r.size.x - 250, 28), Color(1.0, 0.82, 0.29, 0.18))
		_text(Vector2(r.position.x + 24, bottom + 20), path, 15, Color(1.0, 0.85, 0.35))
	if c["kind"] == "branch" and bool(c["first"]):
		return   # «или-или»: закреплять и исключать нечего — выбор из двух веток одного оружия
	var is_locked: bool = not m.locked.is_empty() and m.locked["id"] == c["id"]
	_button(Rect2(r.end.x - 226, bottom - 2, 104, 32), Loc.t("Открепить") if is_locked else Loc.t("Закрепить"), "lock:%d" % i, 14)
	if m.bans > 0:
		_button(Rect2(r.end.x - 116, bottom - 2, 104, 32), "Исключить", "ban:%d" % i, 14)


## Уровень карточки: x — сейчас, y — максимум (0 — без уровней)
func _card_level(p: Player, c: Dictionary) -> Vector2:
	match String(c["kind"]):
		"weapon_up":
			return Vector2((p.groups[int(c["group"])] as Hardpoint).level, Weapons.MAX_LEVEL)
		"weapon_new":
			return Vector2(0, Weapons.MAX_LEVEL)
		"module":
			var id := String(c["id"])
			if id == "repair" or not Cards.MODULES.has(id):
				return Vector2.ZERO
			return Vector2(int(p.taken.get(id, 0)), int(Cards.MODULES[id]["max"]))
		"branch":
			return Vector2((p.groups[int(c["group"])] as Hardpoint).branch_rank, Cards.BRANCH_MAX)
	return Vector2.ZERO


## EX-02: куда ведёт карточка — «▲ к «Шмель»: перезарядка 1 → 2 из 2»
func _card_path(p: Player, c: Dictionary) -> String:
	match String(c["kind"]):
		"module":
			var id := String(c["id"])
			for w in Prog.EVOS:
				var cat: Dictionary = Prog.EVOS[w]["cat"]
				if not cat.has(id) or not (w == "gun" or _has_weapon(p, w)) or (w == "gun" and p.gun_evo):
					continue
				var have := int(p.taken.get(id, 0))
				if have < int(cat[id]):
					return Loc.t("▲ к %s: %d → %d из %d") % [Loc.t(Prog.EVOS[w]["title"]), have, have + 1, int(cat[id])]
		"weapon_up":
			var g: Hardpoint = p.groups[int(c["group"])]
			if Prog.EVOS.has(g.weapon) and not g.evo:
				return Loc.t("▲ ур. 5 откроет %s") % Loc.t(Prog.EVOS[g.weapon]["title"])
	return ""


func _has_weapon(p: Player, w: String) -> bool:
	for g in p.groups:
		if (g as Hardpoint).weapon == w and not (g as Hardpoint).evo:
			return true
	return false


## EX-02: «Оснащение» — подвесы, места модулей, модернизации «оружие + модуль = результат»
func _kit_panel(m: Main, r: Rect2) -> void:
	var p := m.player
	ctrl.draw_rect(r, Color(0.04, 0.055, 0.05, 0.86))
	ctrl.draw_rect(r, Color(0.24, 0.3, 0.23), false, 2.0)
	var x := r.position.x + 20.0
	var w := r.size.x - 40.0
	var y := r.position.y + 34.0
	var amber := Color(1.0, 0.82, 0.29)
	_text(Vector2(x, y), "ОСНАЩЕНИЕ", 21, amber)
	y += 26.0
	_text(Vector2(x, y), "ПОДВЕСЫ", 14, Color(0.72, 0.77, 0.7))
	y += 8.0
	var gn := p.groups.size()
	var per := maxi(4, gn)
	var tw := (w - 8.0 * (per - 1)) / per
	for gi in gn:
		var g: Hardpoint = p.groups[gi]
		var tr := Rect2(x + gi * (tw + 8.0), y, tw, 62)
		if g.is_empty():
			ctrl.draw_rect(tr, Color(1, 1, 1, 0.04))
			ctrl.draw_rect(tr, Color(0.35, 0.4, 0.33), false, 1.5)
			_text(Vector2(tr.position.x, tr.end.y - 10), "пусто", 12, Color(0.55, 0.6, 0.55), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
		else:
			var col: Color = Cards.EVO_COLOR if g.evo else Cards.RARITY[mini(g.level - 1, 4)]["color"]
			ctrl.draw_rect(tr, Color(col.r, col.g, col.b, 0.22))
			ctrl.draw_rect(tr, col, false, 2.0)
			CardIcons.draw(ctrl, tr.get_center() + Vector2(0, -8), minf(30.0, tw - 10.0), g.weapon, Color.WHITE)
			_text(Vector2(tr.position.x, tr.end.y - 6), ("★" if g.evo else Loc.t("ур. %d") % g.level), 12, Color(1.0, 0.92, 0.66), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
			_tips.append([tr, g.label(), (Loc.t(String(Prog.EVOS[g.weapon]["desc"])) if g.evo and Prog.EVOS.has(g.weapon) else _weapon_tip(g.weapon))])
	y += 86.0
	var used := Cards.mod_slots_used(p)
	_text(Vector2(x, y), "МОДУЛИ", 14, Color(0.72, 0.77, 0.7))
	_text(Vector2(x, y), Loc.t("%d из %d") % [used, Cards.MOD_SLOTS], 15, Color(1.0, 0.7, 0.4) if used >= Cards.MOD_SLOTS else Color(0.5, 0.82, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 8.0
	var mods: Array = []
	for id in Cards.MODULES:
		if not Cards.SLOT_FREE.has(id) and int(p.taken.get(id, 0)) > 0:
			mods.append(id)
	var mw := (w - 6.0 * (Cards.MOD_SLOTS - 1)) / Cards.MOD_SLOTS
	for k in Cards.MOD_SLOTS:
		var mr := Rect2(x + k * (mw + 6.0), y, mw, 58)
		if k < mods.size():
			var id: String = mods[k]
			var cc: Color = Cards.CAT_COLORS.get(Cards.MODULES[id]["cat"], Color.WHITE)
			ctrl.draw_rect(mr, Color(cc.r, cc.g, cc.b, 0.22))
			ctrl.draw_rect(mr, cc, false, 2.0)
			CardIcons.draw(ctrl, mr.get_center() + Vector2(0, -7), minf(26.0, mw - 10.0), id, Color.WHITE)
			var lvl := int(p.taken.get(id, 0))
			var mx := int(Cards.MODULES[id]["max"])
			for d in mx:
				ctrl.draw_circle(Vector2(mr.get_center().x - (mx - 1) * 3.5 + d * 7.0, mr.end.y - 7), 2.4, cc if d < lvl else Color(1, 1, 1, 0.2))
			_tips.append([mr, Loc.t("%s · ур. %d из %d") % [Loc.t(String(Cards.MODULES[id]["title"])), lvl, mx], Cards.module_desc(p, id, 1.0) + Loc.t(" за уровень")])
		else:
			ctrl.draw_rect(mr, Color(1, 1, 1, 0.03))
			ctrl.draw_rect(mr, Color(0.33, 0.38, 0.31), false, 1.5)
	y += 84.0
	ctrl.draw_line(Vector2(x, y - 10), Vector2(x + w, y - 10), Color(0.24, 0.3, 0.23), 1.0)
	_text(Vector2(x, y + 10), "МОДЕРНИЗАЦИИ", 19, amber)
	_text(Vector2(x, y + 10), "все связки — Tab", 13, Color(0.65, 0.7, 0.64), HORIZONTAL_ALIGNMENT_RIGHT, w)
	y += 24.0
	var shown := 0
	for wv in Prog.EVOS:
		if shown >= 4 or not (wv == "gun" and not p.gun_evo or wv != "gun" and _has_weapon(p, wv)):
			continue
		shown += 1
		y = _evo_row(p, wv, Vector2(x, y), w) + 6.0
	if shown == 0:
		y += _para(Vector2(x, y + 18), "Возьмите оружие — здесь появятся его модернизации и что для них нужно", w, 15, Color(0.7, 0.74, 0.7))
	if p.has_course():
		var sd := Cards.syn_def(p, p.course)
		var by := r.end.y - 52.0
		ctrl.draw_line(Vector2(x, by - 14), Vector2(x + w, by - 14), Color(0.24, 0.3, 0.23), 1.0)
		_para(Vector2(x, by + 4), Loc.t("Специализация: «%s» (связка %d из 3) — %s") % [Loc.t(sd["title"]), p.syn.size() + 1, Loc.t(sd["short"])], w, 14, amber)


## Строка «оружие + модуль = модернизация»: заполненный квадрат — есть, пунктир — нужно
func _evo_row(p: Player, wv: String, pos: Vector2, w: float) -> float:
	var ready := Prog.evo_ready(p, wv)
	var h := 52.0
	if ready:
		ctrl.draw_rect(Rect2(pos, Vector2(w, h)), Color(1.0, 0.82, 0.29, 0.13))
	var bx := pos.x + 6.0
	var by := pos.y + 6.0
	var s := 38.0
	var lvl_ok := wv == "gun" or _weapon_max(p, wv)
	_evo_box(Vector2(bx, by), s, "gun" if wv == "gun" else wv, Color(1.0, 0.75, 0.3), lvl_ok)
	if wv != "gun":
		_tips.append([Rect2(bx, by, s, s), Loc.t(Weapons.title(wv)) + (Loc.t(" · нужен ур. 5") if not lvl_ok else " ✓"), _weapon_tip(wv)])
	else:
		_tips.append([Rect2(bx, by, s, s), Loc.t("Курсовая пушка"), Loc.t("Встроенная пушка самолёта — есть всегда")])
	bx += s + 4.0
	var cat: Dictionary = Prog.EVOS[wv]["cat"]
	var need := PackedStringArray()
	if wv != "gun" and not lvl_ok:
		need.append(Loc.t("оружие ур. 5"))
	for mid in cat:
		_text(Vector2(bx, by + 27), "+", 18, Color(0.7, 0.75, 0.7))
		bx += 14.0
		var have := int(p.taken.get(mid, 0))
		_evo_box(Vector2(bx, by), s, mid, Cards.CAT_COLORS.get(Cards.MODULES[mid]["cat"], Color.WHITE), have >= int(cat[mid]))
		_tips.append([Rect2(bx, by, s, s), Loc.t("%s · %d из %d") % [Loc.t(String(Cards.MODULES[mid]["title"])), have, int(cat[mid])], Cards.module_desc(p, mid, 1.0) + Loc.t(" за уровень")])
		bx += s + 4.0
		if have < int(cat[mid]):
			need.append("%s %d/%d" % [Loc.t(Cards.MODULES[mid]["title"]), have, int(cat[mid])])
	_text(Vector2(bx, by + 27), "=", 18, Color(0.7, 0.75, 0.7))
	bx += 16.0
	var rr := Rect2(bx, by, s, s)
	_tips.append([Rect2(rr.position.x, pos.y, pos.x + w - rr.position.x, h), Loc.t("Модернизация %s") % Loc.t(Prog.EVOS[wv]["title"]), Loc.t(String(Prog.EVOS[wv]["desc"]))])
	if ready:
		ctrl.draw_rect(rr, Color(1.0, 0.82, 0.29))
		_text(Vector2(rr.position.x, rr.position.y + 25), "✓", 20, Color(0.1, 0.08, 0.02), HORIZONTAL_ALIGNMENT_CENTER, s)
	else:
		ctrl.draw_rect(rr, Color(0.45, 0.5, 0.43), false, 2.0)
	bx += s + 10.0
	var tx := maxf(bx, pos.x + w * 0.55)
	_text(Vector2(tx, by + 15), Loc.t(Prog.EVOS[wv]["title"]), 15, Color(1.0, 0.98, 0.9))
	_para(Vector2(tx, by + 32), Loc.t("готова — ждите карточку") if ready else Loc.t("нужно: ") + ", ".join(need), pos.x + w - tx, 12, Color(0.72, 0.77, 0.7))
	return pos.y + h


func _evo_box(pos: Vector2, s: float, icon: String, col: Color, have: bool) -> void:
	var r := Rect2(pos, Vector2(s, s))
	if have:
		ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.75))
		ctrl.draw_rect(r, Color(1, 1, 1, 0.4), false, 1.5)
	else:
		ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.08))
		ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.55), false, 1.5)
	CardIcons.draw(ctrl, r.get_center(), s - 12.0, icon, Color.WHITE if have else Color(1, 1, 1, 0.5))


func _weapon_max(p: Player, w: String) -> bool:
	for g in p.groups:
		if (g as Hardpoint).weapon == w and (g as Hardpoint).level >= Weapons.MAX_LEVEL:
			return true
	return false


## Чипы тегов карточки: цвет тега, «Ракеты 3 → 4»
func _tag_chips(pos: Vector2, tags: Array, evo := false) -> void:
	var x := pos.x
	var p := Main.I.player
	for t in tags:
		var col: Color = Prog.TAGS[t]["color"]
		var label := "%s %d → %d" % [Prog.tag_title(t), p.tag(t), p.tag(t) + (2 if evo else 1)]
		var tw := ui_font().get_string_size(Loc.out(label), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0
		ctrl.draw_rect(Rect2(x, pos.y, tw, 22), Color(col.r, col.g, col.b, 0.2))
		ctrl.draw_rect(Rect2(x, pos.y, 4, 22), col)
		_text(Vector2(x + 10, pos.y + 16), label, 14, col.lightened(0.3))
		x += tw + 8.0


## Пауза: очки тегов сеткой 4 × 2 (S9-10: раньше 7 узких колонок в строку), прогресс курса, связки, эволюции.
## Вернёт высоту панели
func _tags_panel(p: Player, pos: Vector2, w: float) -> float:
	var cols := 4
	var cw := w / cols
	var chh := 58.0
	for i in Prog.TAG_ORDER.size():
		var t: String = Prog.TAG_ORDER[i]
		var col: Color = Prog.TAGS[t]["color"]
		var n := p.tag(t)
		var r := Rect2(pos.x + (i % cols) * cw + 3, pos.y + (i / cols) * (chh + 6.0), cw - 6, chh)
		ctrl.draw_rect(r, Color(0.05, 0.055, 0.06, 0.88))
		ctrl.draw_rect(r, Color(col.r, col.g, col.b, 0.12 if n > 0 else 0.04))
		ctrl.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), col if n > 0 else Color(1, 1, 1, 0.1))
		_text(Vector2(r.position.x + 12, r.position.y + 24), "%s  %d" % [Loc.t(Prog.tag_title(t)), n], 17, col.lightened(0.25) if n > 0 else Color(0.5, 0.52, 0.58))
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
				_text(Vector2(r.position.x + 12, r.position.y + 46), Loc.t("▲ к связке: %d/%d") % [n, need], 14, Color(1.0, 0.85, 0.35))
	var rows := int(ceil(Prog.TAG_ORDER.size() / float(cols)))
	var y := pos.y + rows * (chh + 6.0) + 6.0
	var extra := PackedStringArray()
	for id in p.syn:
		if Cards.SYNERGIES.has(id):
			extra.append("«%s»" % Cards.SYNERGIES[id]["title"])
		else:
			extra.append("«%s»" % PlaneClasses.SKILL3[p.skill3]["syn"]["title"])
	var ev := PackedStringArray()
	for wv in p.evo_times:
		ev.append(Prog.EVOS[wv]["title"])
	var lines := [Loc.t("Связки: %s") % (", ".join(extra) if not extra.is_empty() else Loc.t("нет")),
		Loc.t("Модернизации: %s") % (", ".join(ev) if not ev.is_empty() else Loc.t("нет")),
		Loc.t("Навык: %s%s") % [Loc.t(p.s3_def()["title"]), (Loc.t(", ур. ") + Prog.ROMAN[p.s3_lvl()]) if p.s3_lvl() > 0 else ""]]
	for l in lines:
		y += _para(Vector2(pos.x + 4, y + 18), l, w - 8.0, 16, Menu.C_AMBER) + 4.0
	return y - pos.y


# ---------- Подвесы и пауза ----------

## S9-10 (скриншот Kanta: текст налезал): слева подвесы — описание оружия переносится в своей строке и не заходит
## под кнопку цели, высота строк по месту над кнопками; справа — характеристики, теги сеткой, связки и карточки
func loadout(m: Main, size: Vector2) -> void:
	# правка 15 (тест 3.5): фон плотнее — бой под паузой не мешает читать
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.86))
	_ctext(96, "ПАУЗА · ПОДВЕСЫ", 40, Color.WHITE)
	_ctext(132, "Клик по приоритету — сменить, по какой цели стреляет группа", 19, Color(0.75, 0.8, 0.9))
	var p := m.player
	var bottom := size.y - 176.0
	var w := 940.0
	var x := 70.0
	var y := 160.0
	var tw := w - 340.0   # текст строки — левее кнопки
	var room := bottom - y - (56.0 if not p.wingmen.is_empty() else 0.0)
	var rh := clampf(room / maxf(p.groups.size(), 1) - 8.0, 52.0, 84.0)
	for gi in p.groups.size():
		var g: Hardpoint = p.groups[gi]
		var r := Rect2(x, y, w, rh)
		_panel(r, false)
		_para(Vector2(x + 18, y + 24), g.label(), tw, 18, Color.WHITE if not g.is_empty() else Color(0.6, 0.62, 0.7))
		if not g.is_empty():
			var dsz := 14 if rh >= 64.0 else 13
			var desc := Loc.t(Weapons.DEFS[g.weapon]["desc"])
			# описание — сколько влезает строк под названием
			var maxh := rh - 34.0
			if ui_font().get_multiline_string_size(Loc.out(desc), HORIZONTAL_ALIGNMENT_LEFT, tw, dsz).y <= maxh:
				_para(Vector2(x + 18, y + 46), desc, tw, dsz, Color(0.75, 0.8, 0.9))
			else:
				_text(Vector2(x + 18, y + 46), _fit(desc, tw, dsz), dsz, Color(0.75, 0.8, 0.9))
			var by := y + (rh - 38.0) / 2.0
			if Weapons.DEFS[g.weapon]["uses_priority"]:
				_button(Rect2(x + w - 316, by, 300, 38), Loc.t("Цель: %s") % Weapons.PRIORITY_NAMES[g.priority], "prio:%d" % gi, 16)
			if g.uses_trigger():
				_button(Rect2(x + w - 316, by, 300, 38), "Пуск: %s" % ("авто" if g.trigger == "auto" else "правой кнопкой мыши"), "trig:%d" % gi, 16)
		y += rh + 8.0
	if not p.wingmen.is_empty():
		var wr := Rect2(x, y, w, 48)
		_panel(wr, false)
		_text(Vector2(x + 18, y + 31), "Звено — кого атакует первым [G]", 19, Color(0.8, 0.75, 1.0))
		_button(Rect2(x + w - 316, y + 5, 300, 38), Loc.t("Цель: %s") % Settings.WING_PRIO[Settings.wing_prio], "wprio", 16)
	# справа: характеристики, теги, связки, взятые карточки
	var cx := x + w + 40.0
	var cw := size.x - cx - 60.0
	var cy := 160.0
	cy += _para(Vector2(cx, cy + 16), Loc.t("Пушка: урон ×%.2f · темп ×%.2f · Подвесы: перезарядка ×%.2f · Скорость ×%.2f · Манёвр ×%.2f · Подбор ×%.2f") % [
		float(p.cls["gun_dmg"]) * p.mods["gun_dmg"], float(p.cls["gun_rate"]) * p.mods["gun_rate"], p.mods["hp_cd"],
		float(p.cls["speed"]) * p.mods["speed"], float(p.cls["turn"]) * p.mods["turn"], p.mods["pickup"]], cw, 16, Color(0.85, 0.88, 0.95)) + 10.0
	cy += _tags_panel(p, Vector2(cx, cy), cw) + 18.0
	_text(Vector2(cx, cy + 20), Loc.t("ВЗЯТЫЕ КАРТОЧКИ (%d)") % p.cards_log.size(), 20, Menu.C_AMBER)
	_text(Vector2(cx, cy + 42), "цвет — лучшая редкость, «ур.» — до какого уровня улучшено", 14, Color(0.65, 0.7, 0.8))
	if p.cards_log.is_empty():
		_text(Vector2(cx, cy + 76), "пока ни одной", 16, Color(0.6, 0.62, 0.7))
	elif bottom - cy - 58.0 > 30.0:
		_card_chips(Rect2(cx, cy + 58, cw, bottom - cy - 58.0), Cards.log_summary(p.cards_log), 15)
	var bx := (size.x - 1280) / 2.0
	_button(Rect2(bx, size.y - 140, 300, 52), "Продолжить (Esc / Tab)", "resume")
	_button(Rect2(bx + 326, size.y - 140, 300, 52), "Связки и модернизации", "codex")
	_button(Rect2(bx + 652, size.y - 140, 300, 52), "Настройки", "pause_settings")
	_button(Rect2(bx + 978, size.y - 140, 300, 52), "В главное меню", "to_menu")


## Строка, обрезанная многоточием по ширине
func _fit(s: String, width: float, fsize: int) -> String:
	s = Loc.out(s)
	if ui_font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= width:
		return s
	while s.length() > 1 and ui_font().get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width:
		s = s.substr(0, s.length() - 1)
	return s + "…"


# ---------- Итоги вылета ----------

func result(m: Main, size: Vector2) -> void:
	if Demo.end_open:
		_demo_end(size)
		return
	# правка 16 (тест 3.5): фон плотнее — интерфейс боя под итогами не просвечивает
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.03, 0.93))
	var t := int(m.run_time)
	var top := 100.0
	if m.state == "evac":
		_ctext(top, "ЭВАКУАЦИЯ УСПЕШНА", 46, Color(0.5, 1.0, 0.6))
	else:
		_ctext(top, "САМОЛЁТ СБИТ", 46, Color(1, 0.5, 0.4))
	_ctext(top + 42, Loc.t("%s · время %02d:%02d · уровень %d · сбито %d · асов %d") % [Loc.t(PlaneClasses.DATA[m.cls_id]["title"]), t / 60, t % 60, m.run.level, m.run.kills, m.run.bosses_killed], 23, Color.WHITE)
	var kept_note := "100% — эвакуация" if m.state == "evac" else "50% — гибель без эвакуации"
	_ctext(top + 74, Loc.t("Запчасти: %d из %d (%s)") % [m.parts_kept, int(m.run.parts), kept_note], 21, Color(0.95, 0.85, 0.55))
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
			_report_button(Rect2(bx + 1280, by, bw, 54), m.result_t)


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


## Кнопка отчёта заметнее остальных, но без всплывающих окон и звука (Kanta, 18.10):
## янтарная заливка, подпись под кнопкой и мягкое «дыхание» рамки первые секунды на экране итогов
func _report_button(r: Rect2, shown_t: float) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	var cut := minf(14.0, r.size.y * 0.3)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut), r.end, Vector2(r.position.x, r.end.y)])
	ctrl.draw_colored_polygon(pts, Menu.C_AMBER.lightened(0.15) if hover else Menu.C_AMBER)
	if shown_t < 6.0:
		var k := 0.5 + 0.5 * sin(shown_t * 3.0)
		var g := r.grow(4.0 + 4.0 * k)
		var gc := minf(18.0, g.size.y * 0.3)
		var gp := PackedVector2Array([g.position, Vector2(g.end.x - gc, g.position.y), Vector2(g.end.x, g.position.y + gc), g.end, Vector2(g.position.x, g.end.y), g.position])
		ctrl.draw_polyline(gp, Color(Menu.C_AMBER.r, Menu.C_AMBER.g, Menu.C_AMBER.b, 0.55 * (1.0 - shown_t / 6.0)), 2.0)
	_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0 + 22 * 0.35), "ОТПРАВИТЬ ОТЧЁТ", 22, Color(0.08, 0.07, 0.05), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(Vector2(r.position.x, r.end.y + 24), "1 минута — очень поможет игре", 16, Menu.C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_buttons.append([r, "report_open"])


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
		["сбито в минуту", "%.0f" % (m.run.kills / rt * 60.0), Color.WHITE],
		["точность пушки", "%d%%" % acc, Color(0.85, 0.9, 1.0)],
		["связок", "%d" % m.player.syn.size(), Menu.C_AMBER],
		["активностей", "%d" % m.run.activities_done, Color(0.7, 0.95, 1.0)],
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


## «Урон»: нанесённый с долей и уроном в секунду, полученный — по видам и по врагам
func _res_damage(m: Main, y0: float, size: Vector2) -> void:
	var lx := 90.0
	var rx := 700.0
	var hc := Color(0.95, 0.95, 1.0)
	var rt := maxf(m.run_time, 1.0)
	_text(Vector2(lx, y0), Loc.t("ПОЛУЧЕНО УРОНА: %d") % m.total("taken"), 22, Color(1.0, 0.72, 0.68))
	var y := y0 + 36.0
	for k in ["таран", "пули", "ракеты"]:
		_row(lx, y, 520.0, k, m.stat("taken", k), m.total("taken"), Color(1.0, 0.45, 0.4))
		y += 30.0
	# S8 «eweap»: чем — вид оружия врагов (ПЗРК, ЗРК, пулемёт пикапа, пушка БМП…), больше всего урона сверху
	var tkind: Dictionary = m.stats.get("taken_kind", {})
	if not tkind.is_empty():
		y += 14.0
		_text(Vector2(lx, y), "Чем:", 19, hc)
		y += 30.0
		for k in _top_keys(tkind, 5):
			_row(lx, y, 520.0, k, m.stat("taken_kind", k), m.total("taken"), Color(1.0, 0.52, 0.42))
			y += 30.0
	y += 14.0
	_text(Vector2(lx, y), "От кого:", 19, hc)
	y += 30.0
	# S8: кто нанёс урон — по убыванию (с колонной и ПЗРК); пока урона нет — прежний список
	var by_keys := _top_keys(m.stats["taken_by"], 6)
	if by_keys.is_empty():
		by_keys = ["дроны", "перехватчики", "ракетоносцы", "ПВО", "ас-соперник", "асы"]
	for k in by_keys:
		_row(lx, y, 520.0, k, m.stat("taken_by", k), m.total("taken"), Color(1.0, 0.6, 0.4))
		y += 30.0
	_text(Vector2(rx, y0), Loc.t("НАНЕСЕНО УРОНА: %d  ·  %d в секунду") % [m.total("dealt"), int(m.total("dealt") / rt)], 22, Color(0.72, 1.0, 0.78))
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
		Loc.t("Сбито: дроны %d · перехватчики %d · ракетоносцы %d · асы %d") % [m.stat("kills_by", "дроны"), m.stat("kills_by", "перехватчики"), m.stat("kills_by", "ракетоносцы"), m.stat("kills_by", "асы")],
		Loc.t("Точность пушки: %d%% · пик «оборотов»: +%d%% · сбито с хвоста: %d") % [int(acc), int(round(m.peak_rev * 100.0)), m.run.tail_kills],
		Loc.t("Уведено ракет ловушками: %d · срывов захвата: %d · на волоске: %d") % [int(m.counters.get("intercepted", 0)), int(m.counters.get("locks_broken", 0)), m.run.near_misses],
		Loc.t("Лучшая серия: %d · активностей: %d · проход на форсаже: %d урона") % [m.run.best_streak, m.run.activities_done, m.stat("dealt", "проход на форсаже")],
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
		_text(Vector2(x + 12, y), Loc.t("«%s» — с %d:%02d · урон %d") % [Loc.t(sd["title"]), tt / 60, tt % 60, sdmg], 18, Color(1.0, 0.9, 0.6))
	y += 40.0
	var ev := PackedStringArray()
	for wv in p.evo_times:
		var et := int(float(p.evo_times[wv]))
		ev.append("%s (%d:%02d)" % [Prog.EVOS[wv]["title"], et / 60, et % 60])
	_text(Vector2(x, y), Loc.t("МОДЕРНИЗАЦИИ: ") + (", ".join(ev) if not ev.is_empty() else Loc.t("нет")), 18, Cards.EVO_COLOR)
	y += 34.0
	var gl := PackedStringArray()
	for g in p.groups:
		var h := g as Hardpoint
		if not h.is_empty():
			gl.append(Loc.t("%s ур. %d ×%d") % [Loc.t(Weapons.DEFS[h.weapon]["short"]), h.level, h.slots])
	_para(Vector2(x, y), Loc.t("ПОДВЕСЫ: ") + (" · ".join(gl) if not gl.is_empty() else Loc.t("пусто")), size.x - 2.0 * x, 18, Color(0.85, 0.9, 1.0))
	y += 46.0
	_text(Vector2(x, y), Loc.t("КАРТОЧКИ ВЫЛЕТА: %d") % p.cards_log.size(), 20, Menu.C_AMBER)
	_text(Vector2(x + 300, y), "цвет — лучшая редкость, «ур.» — до какого уровня улучшено", 14, Color(0.65, 0.7, 0.8))
	if not p.cards_log.is_empty():
		_card_chips(Rect2(x, y + 16, size.x - 2.0 * x, size.y - 150.0 - (y + 16)), Cards.log_summary(p.cards_log), 16)


## U-01: внутренние имена источников урона (их пишет лог l5) → понятные игроку
const SRC_NAMES := {
	"курсовое (авто)": "пушка (сама)", "курсовое (ручн.)": "пушка (ручной огонь)",
	"ракеты В-В": "наводящиеся ракеты", "НАР": "залп ракет", "разделяющаяся БЧ": "разделяющиеся ракеты",
	"ЭМИ": "ЭМИ-заряд", "лазер": "лазер «Луч»", "плазма": "плазменная бомба",
	"УР В-З": "ракета «воздух-земля»",
}


## Ключи словаря по убыванию значения, не больше n (нулевые — нет)
static func _top_keys(d: Dictionary, n: int) -> Array:
	var keys := d.keys().filter(func(k) -> bool: return float(d[k]) >= 0.5)
	keys.sort_custom(func(a, b) -> bool: return float(d[a]) > float(d[b]))
	return keys.slice(0, n)


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
		total += ui_font().get_string_size(Loc.out(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var x := center.x - total / 2.0
	for pt in parts:
		_text(Vector2(x, center.y), pt[0], 16, pt[1])
		x += ui_font().get_string_size(Loc.out(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x


func course_pick(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.72))
	var p := m.player
	var slot := p.syn.size() + 1
	_ctext(150, Loc.t("ВЫБОР СПЕЦИАЛИЗАЦИИ — СВЯЗКА %d ИЗ 3") % slot, 40, Menu.C_AMBER)
	_ctext(192, "Связка — сильный бонус, который меняет оружие или навык. Выберите, какую собирать: карточки к ней отмечены «▲» и выпадают чаще.", 17, Color(0.8, 0.84, 0.92))
	_ctext(218, Loc.t("Нужно набрать очки цветных меток на карточках: для 1-й связки — %d, 2-й — %d, 3-й — %d. Сменить специализацию можно позже за 1 переброс.") % [
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
		_text(Vector2(r.position.x + 18, r.position.y + 80), Loc.t(String(sd["title"])), 30, Color.WHITE)
		_para(Vector2(r.position.x + 18, r.position.y + 118), Loc.t(sd["desc"]), w - 36.0, 17)
		var conds := Cards.cond_list(p, id)
		_text(Vector2(r.position.x + 18, r.position.y + 262), "Что нужно собрать:", 16, Color(0.8, 0.82, 0.88))
		var yy := r.position.y + 272.0
		for c in conds:
			_cond_chips(Vector2(r.position.x + 18, yy), [c])
			yy += 28.0
		_text(Vector2(r.position.x + 18, r.end.y - 16), Loc.t("≈ ещё %d подходящих карточек") % Cards.cards_left(conds), 16, Menu.C_AMBER)
	_ctext(690, "1–3 или клик — выбрать специализацию", 17, Color(0.75, 0.8, 0.9))


## U-05: итог операции кампании — пройдена (и что открыто) или чего не хватило
func _op_line(m: Main, y: float) -> void:
	var o: Dictionary = m.op_result
	if o.is_empty():
		return
	var s := ""
	var col := Color(0.8, 0.82, 0.88)
	if o["first"]:
		s = Loc.t("Операция %d «%s» пройдена! Открыто: %s") % [int(o["n"]), Loc.t(o["title"]), ", ".join(PackedStringArray(o["opens"]))]
		col = Color(1.0, 0.85, 0.4)
	elif o["done"]:
		s = Loc.t("Операция %d «%s» выполнена (уже была пройдена)") % [int(o["n"]), Loc.t(o["title"])]
		col = Color(0.5, 1.0, 0.6)
	else:
		s = Loc.t("Операция %d «%s» не засчитана: не удалось %s") % [int(o["n"]), Loc.t(o["title"]), ", ".join(PackedStringArray(o["miss"])) if not (o["miss"] as Array).is_empty() else Loc.t("вернуться на базу")]
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
	rows.append(["Итого", Loc.t("+%d   (всего %d)") % [int(a["parts_add"]), int(a["parts_after"])], Color.WHITE])
	rows.append([Loc.t("ОПЫТ ЭКИПАЖА «%s»") % Profile.cls(m.cls_id)["callsign"], "", Color(0.6, 1.0, 0.7)])
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
	_text(Vector2(x, y), Loc.t("Экипаж ур. %d") % lv, 20, Color.WHITE)
	if int(pr[1]) > 0 and not a.has("promote"):
		_text(Vector2(x, y), Loc.t("до ур. %d: %d") % [lv + 1, int(pr[1]) - int(pr[0])], 16, Color(0.75, 0.8, 0.88), HORIZONTAL_ALIGNMENT_RIGHT, w)
	# 3.5: уровень покупается в ангаре — «Повысить в звании»
	if a.has("promote"):
		y += 28.0
		var pv: Array = a["promote"]
		_text(Vector2(x, y), Loc.t("Опыта хватает на ур. %d: «Повысить в звании» в ангаре — %d") % [int(pv[0]), int(pv[1])], 16,
			Color(1.0, 0.9, 0.4))
	for u in a["unlocked"]:
		y += 26.0
		_text(Vector2(x, y), Loc.t("ОТКРЫТО: ") + String(u), 16, Color(1.0, 0.85, 0.4))
	if String(a.get("tech", "")) != "":
		y += 28.0
		_text(Vector2(x, y), Loc.t("Техник: «%s»") % String(a["tech"]), 16, Color(0.95, 0.85, 0.55))
	if String(a.get("hint_buy", "")) != "":
		y += 30.0
		_text(Vector2(x, y), Loc.t("Можно купить: ") + String(a["hint_buy"]), 17, Color(0.6, 0.95, 1.0))
