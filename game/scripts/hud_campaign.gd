class_name HudCampaign
extends HudKit
## U-05 → EX-08: экран «В вылет» — операции района, задача, самолёт и навык, кнопка вылета на одном экране.
## Порядок: «Вылет» в меню → «В ВЫЛЕТ ▶» → бой.

const C_DONE := Color(0.5, 1.0, 0.6)
const C_LOCK := Color(0.45, 0.47, 0.5)


## Тред «Второй биом»: вкладки биомов над картой — у каждого своя цепочка операций (Campaign.OPS, поле "biome")
const BIOMES := [Biome.HIGHLAND, Biome.ARCHIPELAGO]


## Переключить биом на экране кампании (пусто — следующий): выбирается последняя открытая операция биома
static func switch_biome(to := "") -> void:
	var cur := Campaign.biome_of(Campaign.index())
	if to == "":
		to = BIOMES[(BIOMES.find(cur) + 1) % BIOMES.size()]
	if to == cur:
		return
	var pick := -1
	for i in Campaign.ops_of(to):
		if Campaign.is_open(i):
			pick = i
	if pick >= 0:
		Campaign.select(pick)


## EX-08 (макет «В вылет», Kanta 22.10): операция, самолёт и кнопка на одном экране.
## От запуска до боя — два нажатия: «ВЫЛЕТ» в меню и «В ВЫЛЕТ ▶» здесь. Самолёт и навык выбираются кликом,
## ангар — по кнопке «Улучшить самолёт». Характеристики — честные: скорость, манёвр и прочность из PlaneClasses,
## урон по воздуху и по земле — замер 22.10 (10-минутные вылеты, по 2 на класс), доли от лучшего.
const DMG := {"fighter": [63.0, 5.2], "attacker": [53.0, 5.3], "bomber": [42.0, 5.8]}

const C_TITLE := Color(1.0, 0.82, 0.29)
const C_SUB := Color(0.78, 0.82, 0.76)

## The story log («Журнал», step 3) is open over the screen: played scenes and choices, replay of hangar scenes.
static var log_open := false


func draw(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.04, 0.032, 0.9))
	var m := Main.I
	_button(Rect2(64, 32, 200, 42), "‹ Меню (Esc)", "campaign_back", 17)
	_button(Rect2(280, 32, 170, 42), "Журнал", "log_toggle", 17)
	_text(Vector2(64, 134), "В ВЫЛЕТ", 50, C_TITLE)
	_text(Vector2(330, 132), "Выберите операцию и самолёт — и в бой. Всё остальное по желанию.", 19, C_SUB)
	var bio := Campaign.biome_of(Campaign.index())
	for j in BIOMES.size():
		var b: String = BIOMES[j]
		var tr := Rect2(size.x - 64 - (BIOMES.size() - j) * 290 + 10, 32, 280, 42)
		var bname := Loc.t(String(Biome.DATA[b]["name"]))
		if not Demo.biome_ok(b):   # демо: второй биом виден, но закрыт
			_panel(tr, false, C_LOCK)
			_text(Vector2(tr.position.x, tr.position.y + 27), bname + " · " + Loc.t(Demo.LOCKED), 15, C_LOCK, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
			continue
		if b == bio:
			ctrl.draw_rect(tr, Color(C_TITLE, 0.9))
			_text(Vector2(tr.position.x, tr.position.y + 28), bname, 18, Color(0.1, 0.08, 0.02), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
		else:
			_button(tr, bname, "biome:" + b, 17)
	_ops(Rect2(64, 170, 470, 840), bio)
	_planes(m, Rect2(566, 170, size.x - 64 - 300 - 44 - 566, 840))
	_go(m, Rect2(size.x - 64 - 300, 170, 300, 840))
	_text(Vector2(64, size.y - 26), Loc.t("Enter — в вылет · ↑ / ↓ — операция · 1 / 2 / 3 — самолёт · Esc — меню · управление: %s [F2]") % Loc.t(Hud.SCHEMES[int(Tuning.g("scheme"))]), 17, C_SUB)
	if log_open:
		_log(size)


## «Журнал»: every story scene in campaign order with its state — played (with the choice made), or not yet; a played
## hangar scene can be watched again (nothing is saved on a replay). Drawn over the screen; its buttons are added
## last, so they win over the screen's own (`Hud.button_at` picks the last match).
func _log(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), UiStyle.SCRIM)
	_buttons.append([Rect2(Vector2.ZERO, size), "log_toggle"])   # a click outside the panel closes it
	var pr := Rect2((size.x - 900.0) * 0.5, 96.0, 900.0, size.y - 192.0)
	_panel(pr, false)
	_buttons.append([pr, "log_noop"])
	_text(Vector2(pr.position.x + 32.0, pr.position.y + 50.0), "ЖУРНАЛ", 30, C_TITLE)
	_text(Vector2(pr.position.x + 190.0, pr.position.y + 48.0), "сцены кампании и ваши ответы", 17, C_SUB)
	_button(Rect2(pr.end.x - 212.0, pr.position.y + 18.0, 190.0, 40.0), "Закрыть (Esc)", "log_toggle", 16)
	var y := pr.position.y + 96.0
	var x := pr.position.x + 32.0
	for row: Array in StoryDialogs.ORDER:
		if y > pr.end.y - 40.0:
			break
		var sid := String(row[0])
		var kind := String(row[2])
		var def := StoryDialogs.scene(sid) if kind == "dlg" else (StoryScenes.intro(sid.substr(6)) if sid.begins_with("intro_") else StoryScenes.outro(sid.substr(6)))
		if def.is_empty():
			continue   # not written yet: no row, the log never promises a scene
		var seen := Campaign.flag("seen_" + sid)
		var col := Color.WHITE if seen else C_LOCK
		_text(Vector2(x, y), ("✓  " if seen else "○  ") + Loc.t(String(row[1])), 19, col)
		var ch := ""
		if seen and kind == "dlg":
			for s: Dictionary in def.get("steps", []):
				if s.has("choice"):
					var opt := Campaign.story_choice(String(s["choice"]))
					if opt != "":
						ch = Loc.t("— ответ: %s") % Loc.t(DialogFlow.option_label(def, String(s["choice"]), opt))
			_button(Rect2(pr.end.x - 212.0, y - 26.0, 180.0, 36.0), "Повторить", "replay:" + sid, 15)
		elif not seen:
			ch = Loc.t("ещё не было")
		if ch != "":
			_text(Vector2(x + 36.0, y + 22.0), ch, 15, C_SUB if seen else C_LOCK)
			y += 22.0
		y += 40.0
	if y == pr.position.y + 96.0:
		_para(Vector2(x, y), "Сцены появятся по ходу кампании.", pr.size.x - 64.0, 18, C_SUB)


## Колонка 1: операции района и задача выбранной
func _ops(r: Rect2, bio: String) -> void:
	_text(r.position + Vector2(0, 22), "1 · ОПЕРАЦИЯ", 19, C_SUB)
	var mp := ctrl.get_local_mouse_position()
	var y := r.position.y + 40.0
	var ids := Campaign.ops_of(bio)
	for j in ids.size():
		var i: int = ids[j]
		var o: Dictionary = Campaign.OPS[i]
		var avail := Campaign.is_open(i)
		var on := i == Campaign.index()
		var row := Rect2(r.position.x, y, r.size.x, 72)
		var hover := avail and row.has_point(mp)
		var a := 1.0 if avail else 0.5
		ctrl.draw_rect(row, Color(1.0, 0.82, 0.29, 0.2) if on else Color(0.05, 0.06, 0.05, 0.75))
		ctrl.draw_rect(row, Color(C_TITLE, a) if on or hover else Color(0.3, 0.36, 0.28, a), false, 2.0)
		var c := row.position + Vector2(36, 36)
		ctrl.draw_circle(c, 19.0, Color(C_TITLE, a) if on else Color(0.17, 0.21, 0.16, a))
		_text(Vector2(c.x - 20, c.y + 8), "%d" % (j + 1), 20, Color(0.1, 0.08, 0.02) if on else Color(0.85, 0.83, 0.75, a), HORIZONTAL_ALIGNMENT_CENTER, 40)
		_text(Vector2(row.position.x + 70, y + 31), "«%s»" % Loc.t(String(o["title"])), 21, Color(1, 1, 1, a))
		var sub := Loc.t(String(Campaign.DIFF[int(o["diff"])]["title"])) if avail else Loc.t("закрыта" if Demo.op_ok(i) else Demo.LOCKED)
		_text(Vector2(row.position.x + 70, y + 56), sub, 15, Color(0.85, 0.83, 0.75, a))
		_text(Vector2(row.end.x - 50, y + 46), "✓" if Campaign.cleared(i) else ("" if avail else "🔒"), 24, C_DONE if Campaign.cleared(i) else C_LOCK, HORIZONTAL_ALIGNMENT_CENTER, 40)
		if avail:
			_buttons.append([row, "op:%d" % i])
		y += 82.0
	# задача операции, задание класса и награда за первый проход
	var box := Rect2(r.position.x, y + 8.0, r.size.x, r.end.y - y - 8.0)
	ctrl.draw_rect(box, Color(0.04, 0.055, 0.045, 0.75))
	ctrl.draw_rect(box, Color(0.24, 0.3, 0.23), false, 2.0)
	var o := Campaign.op()
	var d := Campaign.diff()
	var x := box.position.x + 20.0
	var w := box.size.x - 40.0
	y = box.position.y + 18.0
	y += _para(Vector2(x, y + 14.0), Loc.t(String(o["brief"])), w, 16, Color(0.86, 0.88, 0.84)) + 26.0
	_text(Vector2(x, y), "ЗАДАЧА", 16, C_TITLE)
	y += 12.0
	y += _para(Vector2(x, y + 14.0), Loc.t(String(o["task"])), w, 18, Color.WHITE) + 8.0
	if int(o["diff"]) > 0:
		y += _para(Vector2(x, y + 14.0), Loc.t("Сложность «%s»: враги прочнее ×%s, бьют сильнее ×%s, добыча ×%s") % [Loc.t(d["title"]), _k(d["hp"]), _k(d["dmg"]), _k(d["reward"])], w, 15, Color(1.0, 0.75, 0.55)) + 8.0
	y += 26.0
	_text(Vector2(x, y), "ЗАДАНИЕ КЛАССА · награда — редкая карточка", 16, C_TITLE)
	y += 12.0
	y += _para(Vector2(x, y + 14.0), Loc.t(String(ClassTask.DEFS[Main.I.cls_id]["brief"])), w, 18, Color(1.0, 0.88, 0.55)) + 8.0
	y += 26.0
	if Campaign.cleared(Campaign.index()):
		_para(Vector2(x, y), "✓ Пройдена — повторный вылет ради запчастей и опыта экипажа", w, 16, C_DONE)
		return
	_text(Vector2(x, y), "ЗА ПЕРВЫЙ ПРОХОД", 16, C_TITLE)
	y += 26.0
	_text(Vector2(x, y), Loc.t("• +%d запчастей") % int(o["parts"]), 16, Color(0.95, 0.85, 0.55))
	y += 4.0
	for s in Demo.opens(o):
		if y > box.end.y - 30.0:
			break
		y += _para(Vector2(x, y + 18.0), Loc.t("• Откроется: ") + Loc.t(String(s)), w, 16, Color(1.0, 0.85, 0.4)) + 2.0


## Колонка 2: три самолёта, выбранный подсвечен; у выбранного — выбор навыка класса
func _planes(m: Main, r: Rect2) -> void:
	_text(r.position + Vector2(0, 22), "2 · САМОЛЁТ", 19, C_SUB)
	var gap := 18.0
	var w := (r.size.x - gap * 2.0) / 3.0
	var mp := ctrl.get_local_mouse_position()
	var best := {"hp": 0.0, "speed": 0.0, "turn": 0.0, "air": 0.0, "ground": 0.0}
	for id in PlaneClasses.LIST:
		var dd: Dictionary = PlaneClasses.DATA[id]
		best["hp"] = maxf(best["hp"], float(dd["hp"]))
		best["speed"] = maxf(best["speed"], float(dd["speed"]))
		best["turn"] = maxf(best["turn"], float(dd["turn"]))
		best["air"] = maxf(best["air"], DMG[id][0])
		best["ground"] = maxf(best["ground"], DMG[id][1])
	for i in 3:
		var id: String = PlaneClasses.LIST[i]
		var d: Dictionary = PlaneClasses.DATA[id]
		var col: Color = d["color"]
		var on := id == m.cls_id
		var card := Rect2(r.position.x + i * (w + gap), r.position.y + 40.0 - (8.0 if on else 0.0), w, r.size.y - 40.0)
		var hover := card.has_point(mp)
		if on:
			for k in 4:   # свечение выбранного
				ctrl.draw_rect(card.grow(4.0 + k * 4.0), Color(col, 0.08), false, 4.0)
		ctrl.draw_rect(card, Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.95 if on else 0.8))
		ctrl.draw_rect(card, Color(col, 1.0 if on or hover else 0.55), false, 3.0)
		var band := Rect2(card.position, Vector2(w, 36))
		ctrl.draw_rect(band, col if on else Color(col, 0.6))
		var full: String = Loc.t(String(d["title"]))
		var cut := full.find(" «")
		var role := full.substr(0, cut) if cut > 0 else full
		var pname := full.substr(cut + 1) if cut > 0 else ""
		_text(Vector2(band.position.x + 14, band.position.y + 25), "%d · %s" % [i + 1, role.to_upper()], 15, Color(0.06, 0.08, 0.06))
		_text(Vector2(band.position.x, band.position.y + 25), Loc.t("самолёт ур. %d") % Profile.plane_lvl(id), 14, Color(0.06, 0.08, 0.06), HORIZONTAL_ALIGNMENT_RIGHT, w - 14.0)
		_buttons.append([card, "class:" + id])
		# картинка самолёта носом вверх
		var t := PlaneArt.plane_tex(id, Profile.plane_lvl(id))
		var pic := Rect2(card.position.x, band.end.y + 6.0, w, 170.0)
		if t != null:
			var k := minf(pic.size.y / t.get_width(), (w * 0.8) / t.get_height())
			ctrl.draw_set_transform(pic.get_center(), -PI / 2.0, Vector2(k, k))
			ctrl.draw_texture(t, -t.get_size() / 2.0)
			ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var x := card.position.x + 18.0
		var tw := w - 36.0
		var y := pic.end.y + 30.0
		_text(Vector2(x, y), pname if pname != "" else full, 30, Color.WHITE)
		y += 8.0
		y += _para(Vector2(x, y + 16.0), Loc.t(String(d["role"])), tw, 15, Color(0.9, 0.88, 0.8)) + 14.0
		var rows := [["Скорость", float(d["speed"]) / best["speed"]], ["Манёвр", float(d["turn"]) / best["turn"]],
			["Прочность", float(d["hp"]) / best["hp"]], ["Урон по воздуху", DMG[id][0] / best["air"]], ["Урон по земле", DMG[id][1] / best["ground"]]]
		for row in rows:
			_text(Vector2(x, y + 14.0), row[0], 15, C_SUB)
			var bar := Rect2(x + 132.0, y + 4.0, tw - 132.0, 10.0)
			ctrl.draw_rect(bar, Color(1, 1, 1, 0.12))
			ctrl.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(row[1]), 0.0, 1.0), bar.size.y)), col)
			y += 24.0
		y += 10.0
		y += _para(Vector2(x, y + 12.0), Loc.t("Экипаж ур. %d · ★ %s +%d%%") % [Profile.crew_lvl(id), Loc.t(String(Weapons.DEFS[d["signature"]]["short"])), roundi((PlaneClasses.bonus_k(id, 0, String(d["signature"])) - 1.0) * 100.0)], tw, 15, Color(0.65, 1.0, 0.72)) + 10.0
		# навык класса [E]: у выбранного самолёта — три варианта, у остальных — текущий
		var cur: String = m.skill_pick.get(id, Profile.skills(id)[0])
		if not on:
			_para(Vector2(x, y + 12.0), Loc.t("Навык [E]: %s") % Loc.t(String(PlaneClasses.SKILL3[cur]["title"])), tw, 15, C_SUB)
			continue
		_text(Vector2(x, y + 12.0), "Навык класса [E]:", 15, Color(0.7, 1.0, 0.7))
		y += 22.0
		for sk in PlaneClasses.CLASS_SKILLS[id]:
			var sd: Dictionary = PlaneClasses.SKILL3[sk]
			# S9-01: под названием — что делает навык; высота строки — по описанию
			var ph := ui_font().get_multiline_string_size(Loc.out(Loc.t(String(sd["short"]))), HORIZONTAL_ALIGNMENT_LEFT, tw - 8.0, 13).y
			var sr := Rect2(x - 6.0, y, tw + 12.0, 30.0 + ph)
			if sr.end.y > card.end.y - 6.0:
				break
			var sel: bool = sk == cur
			var unl := Profile.skill_unlocked(id, sk)
			ctrl.draw_rect(sr, Color(0.55, 0.9, 0.55, 0.2) if sel else Color(1, 1, 1, 0.08 if sr.has_point(mp) and unl else 0.03))
			ctrl.draw_rect(sr, Color(0.6, 1.0, 0.6, 0.9) if sel else Color(1, 1, 1, 0.18), false, 1.5)
			var si: int = PlaneClasses.CLASS_SKILLS[id].find(sk)
			_text(Vector2(sr.position.x + 10, sr.position.y + 21), ("● " if sel else "○ ") + Loc.t(String(sd["title"])) + (Loc.t(" · %d с") % int(sd["cd"]) if unl else Loc.t("  — экипаж ур. %d") % Profile.SKILL_UNLOCK[si]),
				15, Color(0.85, 1.0, 0.85) if sel else (Color(0.88, 0.9, 0.95) if unl else Color(0.5, 0.52, 0.56)))
			_para(Vector2(sr.position.x + 10, sr.position.y + 40), Loc.t(String(sd["short"])), tw - 8.0, 13, Color(0.75, 0.8, 0.86) if unl else Color(0.5, 0.52, 0.56))
			if unl:
				# S9-01: the skill button sits on top of the plane card; Hud.button_at picks the last-added match (CR-01)
				_buttons.append([sr, "skill:%s:%s" % [id, sk]])
			y += sr.size.y + 6.0


## Колонка 3: что откроется, ангар и большая кнопка вылета
func _go(m: Main, r: Rect2) -> void:
	var by := r.end.y - 110.0
	_buttons.append([Rect2(r.position.x, by, r.size.x, 110.0), "op_go"])
	var hot := Rect2(r.position.x, by, r.size.x, 110.0).has_point(ctrl.get_local_mouse_position())
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	for k in 4:
		ctrl.draw_rect(Rect2(r.position.x, by, r.size.x, 110.0).grow(3.0 + k * 4.0), Color(1.0, 0.65, 0.15, 0.06 + 0.04 * pulse), false, 4.0)
	for k in 10:   # градиент сверху вниз: жёлтый → оранжевый
		ctrl.draw_rect(Rect2(r.position.x, by + k * 11.0, r.size.x, 11.0), Color(1.0, 0.82, 0.29).lerp(Color(1.0, 0.6, 0.12), k / 9.0).lightened(0.1 if hot else 0.0))
	ctrl.draw_string(ui_font(), Vector2(r.position.x, by + 70.0), Loc.out("В ВЫЛЕТ ▶"), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 36, Color(0.1, 0.08, 0.02))
	_button(Rect2(r.position.x, by - 80.0, r.size.x, 64.0), Loc.t("Улучшить самолёт (ангар)") + ("  !" if Profile.any_purchase() else ""), "sortie_hangar", 18)
	_text(Vector2(r.position.x, by - 94.0), Loc.t("Запчасти: %d") % Profile.parts(), 16, C_SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


static func _k(v) -> String:
	return ("%.1f" % float(v)).replace(".", ",")
