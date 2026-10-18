class_name HudCampaign
extends HudKit
## U-05: экран кампании — карта Нагорья с 4 операциями, брифинг выбранной, сложность и что откроет первый проход.
## Порядок: «Вылет» в меню → кампания → выбор самолёта → бой.

const C_DONE := Color(0.5, 1.0, 0.6)
const C_LOCK := Color(0.45, 0.47, 0.5)
## Точки операций на карте (доли области карты): путь снизу слева вверх направо — вглубь гор
const POINTS := [Vector2(0.14, 0.78), Vector2(0.38, 0.56), Vector2(0.62, 0.66), Vector2(0.84, 0.28)]


func draw(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.04, 0.88))
	_button(Rect2(64, 60, 220, 46), "‹ Меню (Esc)", "campaign_back", 18)
	_text(Vector2(0, 100), "КАМПАНИЯ: НАГОРЬЕ ШАХРИСАНГ", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_ctext(140, "Выберите операцию: клавиши 1–4 или клик. Пройденную можно повторить ради добычи.", 18, Color(0.7, 0.75, 0.85))
	var map := Rect2(80, 180, 900, 760)
	_map(map)
	_brief(Rect2(1020, 180, size.x - 1020 - 80, 760))


func _map(r: Rect2) -> void:
	_panel(r, false, Color(0.6, 0.62, 0.55))
	var mp := ctrl.get_local_mouse_position()
	# хребты: ломаные линии-горизонтали
	for j in 7:
		var pts := PackedVector2Array()
		var base := r.position.y + r.size.y * (0.18 + j * 0.12)
		for i in 25:
			var x := r.position.x + 20.0 + (r.size.x - 40.0) * i / 24.0
			var hgt := sin(i * 0.9 + j * 1.7) * 18.0 + sin(i * 2.3 + j) * 9.0 - (30.0 if (i + j * 3) % 7 == 0 else 0.0)
			pts.append(Vector2(x, base + hgt))
		ctrl.draw_polyline(pts, Color(0.75, 0.72, 0.6, 0.10 + 0.03 * (j % 3)), 1.5)
	# сухое русло
	var river := PackedVector2Array()
	for i in 30:
		var t := i / 29.0
		river.append(r.position + Vector2(r.size.x * t, r.size.y * (0.92 - 0.55 * t) + sin(t * 11.0) * 24.0))
	ctrl.draw_polyline(river, Color(0.55, 0.65, 0.75, 0.18), 6.0)
	var open := Campaign.unlocked()
	var pos: Array = []
	for p in POINTS:
		pos.append(r.position + r.size * (p as Vector2))
	# путь между точками: пройденный — сплошной, дальше — пунктир
	for i in pos.size() - 1:
		var a: Vector2 = pos[i]
		var b: Vector2 = pos[i + 1]
		var col := C_DONE if Campaign.cleared(i) else C_LOCK
		if Campaign.cleared(i):
			ctrl.draw_line(a, b, Color(col.r, col.g, col.b, 0.6), 3.0)
		else:
			ctrl.draw_dashed_line(a, b, Color(col.r, col.g, col.b, 0.6), 2.0, 12.0)
	for i in pos.size():
		var c: Vector2 = pos[i]
		var o: Dictionary = Campaign.OPS[i]
		var avail := i < open
		var on := i == Campaign.index()
		var hover := avail and c.distance_to(mp) < 60.0
		var col := Menu.C_AMBER if on else (C_DONE if Campaign.cleared(i) else (Color(0.85, 0.88, 0.95) if avail else C_LOCK))
		if on:
			ctrl.draw_arc(c, 46.0 + sin(Time.get_ticks_msec() / 300.0) * 3.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.5), 2.0)
		ctrl.draw_circle(c, 32.0, Color(0.06, 0.07, 0.06, 0.95))
		ctrl.draw_arc(c, 32.0, 0.0, TAU, 40, col, 4.0 if (on or hover) else 2.5)
		var mark := "✓" if Campaign.cleared(i) else ("%d" % (i + 1) if avail else "—")
		_text(Vector2(c.x - 40.0, c.y + 11.0), mark, 30, col, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
		# подпись под точкой; у последней — над ней, чтобы путь к ней не перечёркивал текст
		var ly := c.y + (66.0 if i < pos.size() - 1 else -80.0)
		_text(Vector2(c.x - 160.0, ly), "%d. «%s»" % [i + 1, o["title"]], 19, col, HORIZONTAL_ALIGNMENT_CENTER, 320.0)
		var sub := String(Campaign.DIFF[int(o["diff"])]["title"]) if avail else "закрыта"
		var sub_col := Color(col.r, col.g, col.b, 0.8)
		# открыта, но ещё не пройдена и не выбрана — подсказать, что она новая и сложнее
		if avail and not on and not Campaign.cleared(i) and i > 0:
			sub = "новая · сложнее: " + sub
			sub_col = Color(1.0, 0.75, 0.55)
		_text(Vector2(c.x - 160.0, ly + 24.0), sub, 16, sub_col, HORIZONTAL_ALIGNMENT_CENTER, 320.0)
		if avail:
			_buttons.append([Rect2(c - Vector2(70, 50), Vector2(140, 150)), "op:%d" % i])


func _brief(r: Rect2) -> void:
	_panel(r, false)
	var o := Campaign.op()
	var d := Campaign.diff()
	var x := r.position.x + 32.0
	var w := r.size.x - 64.0
	var y := r.position.y + 54.0
	_text(Vector2(x, y), "ОПЕРАЦИЯ %d" % (Campaign.index() + 1), 20, Color(0.7, 0.75, 0.85))
	y += 44.0
	_text(Vector2(x, y), "«%s»" % String(o["title"]).to_upper(), 36, Menu.C_AMBER)
	y += 44.0
	var diff_line := "Сложность: %s" % d["title"]
	if int(o["diff"]) > 0:
		diff_line += " — враги прочнее ×%s, бьют сильнее ×%s, волны гуще +%d%%, добыча ×%s" % [_k(d["hp"]), _k(d["dmg"]), int(round((float(d["dens"]) - 1.0) * 100.0)), _k(d["reward"])]
	else:
		diff_line += " — обычные враги и добыча"
	y += _para(Vector2(x, y), diff_line, w, 17, Color(1.0, 0.75, 0.55) if int(o["diff"]) > 0 else Color(0.75, 0.9, 0.8))
	y += 26.0
	_text(Vector2(x, y), "БРИФИНГ", 18, Color(0.7, 0.75, 0.85))
	y += 32.0
	y += _para(Vector2(x, y), o["brief"], w, 22, Color(0.92, 0.94, 0.98))
	y += 24.0
	_text(Vector2(x, y), "ЗАДАЧА", 18, Color(0.7, 0.75, 0.85))
	y += 30.0
	y += _para(Vector2(x, y), "• " + String(o["task"]), w, 20, Color.WHITE)
	y += 24.0
	if Campaign.cleared(Campaign.index()):
		_text(Vector2(x, y), "✓ Операция пройдена — повторный вылет ради запчастей и опыта экипажа", 18, C_DONE)
		y += 30.0
	else:
		_text(Vector2(x, y), "ЗА ПЕРВЫЙ ПРОХОД", 18, Color(0.7, 0.75, 0.85))
		y += 30.0
		_text(Vector2(x, y), "• +%d запчастей" % int(o["parts"]), 19, Color(0.95, 0.85, 0.55))
		y += 28.0
		for s in o["opens"]:
			_text(Vector2(x, y), "• Откроется: " + String(s), 19, Color(1.0, 0.85, 0.4))
			y += 28.0
	_button(Rect2(r.position.x + 32.0, r.end.y - 100.0, w, 68), "ВЫБРАТЬ САМОЛЁТ ›   (Enter)", "op_go", 24)


static func _k(v) -> String:
	return ("%.1f" % float(v)).replace(".", ",")
