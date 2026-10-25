class_name HudScreens
extends HudKit
## Экраны поверх игры: выбор курса и итоги вылета. Выбор карточек — HudCards, пауза — HudPause,
## выбор самолёта — на экране «В вылет» (HudCampaign).


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
	var cards: Array = []
	for i in n:
		cards.append(Rect2(x0 + i * (w + gap), 250, w, h))
	_fade_in(cards, m._state_t)
	_ctext(690, "1–3 или клик — выбрать специализацию", 17, Color(0.75, 0.8, 0.9))
