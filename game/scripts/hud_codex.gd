class_name HudCodex
extends HudKit
## 3.1: справочник связок и эволюций (из главного меню и с паузы).


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


func draw(m: Main, size: Vector2) -> void:
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
			_text(Vector2(x + 860, y + 24), _cond_text(sk), 13, Color(0.7, 0.72, 0.78), HORIZONTAL_ALIGNMENT_RIGHT, 0)
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


## 3.2: условие связки навыка — главный (первый) тег навыка по порогам слотов + доводка I/II/III
func _cond_text(sk: String) -> String:
	var t: String = PlaneClasses.SKILL3[sk]["tags"][0]
	return "%s %d/%d/%d + доводка I/II/III" % [Prog.tag_title(t), Cards.SLOT_COST[0]["main"], Cards.SLOT_COST[1]["main"], Cards.SLOT_COST[2]["main"]]
