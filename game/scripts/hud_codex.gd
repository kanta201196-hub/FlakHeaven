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
	# U-04: в меню — пороги для первой связки, без «11/18/25»
	var out0: Array = []
	var c0: Dictionary = Cards.SLOT_COST[0]
	if skill:
		out0.append(["уровень навыка %d" % int(c0.get("s3", 1)), false])
	if s.has("tag"):
		out0.append(["%s: %d очков" % [Prog.tag_title(s["tag"]), c0["main"]], false])
	if s.has("tag2"):
		out0.append(["%s: %d очков" % [Prog.tag_title(s["tag2"]), c0["second"]], false])
	if s.has("w") and s["w"] is Array:
		out0.append(["%s ур. %d" % ["/".join(PackedStringArray((s["w"] as Array).map(func(x): return String(Weapons.DEFS[x]["short"])))), c0["lvl"]], false])
	if s.has("req_mods"):
		out0.append(["%s ×%d" % [" + ".join(PackedStringArray((s["req_mods"] as Array).map(func(x): return "«%s»" % Cards.MODULES[x]["title"]))), int(c0.get("mods", 1))], false])
	if s.get("wingmen", false):
		out0.append(["ведомые: %d" % int(c0.get("wing", 1)), false])
	return out0


func _syn_conds_old(p: Player, s: Dictionary, skill := false) -> Array:
	var out: Array = []
	if skill and p != null:
		out.append(["уровень навыка ≥ 1 (сейчас %d)" % p.s3_lvl(), p.s3_lvl() >= 1])
	elif skill:
		out.append(["уровень навыка ≥ 1", false])
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


## U-04: вкладка справочника и «показать все» (живут между открытиями)
static var tab := 0
static var show_all := false

const TABS := ["Связки оружия", "Связки навыков", "Модернизации"]


func draw(m: Main, size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.04, 0.95))
	var p: Player = m.player if (m.codex_back == "paused" and is_instance_valid(m.player)) else null
	# одна колонка по центру с полями по краям
	var cw := minf(1240.0, size.x - 200.0)
	var x := (size.x - cw) / 2.0
	_button(Rect2(40, 34, 200, 46), "‹ Назад (Esc)", "codex_back", 18)
	_text(Vector2(0, 66), "СПРАВОЧНИК", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_ctext(100, "Связка — сильный бонус, который открывается, когда собраны подходящие карточки. За вылет — до 3; условия указаны для первой, дальше — выше." if tab < 2
		else "Модернизация — оружие ур. 5 превращается в новое, если взяты нужные карточки (с 7:00 вылета).", 17, Color(0.75, 0.8, 0.9))
	var tw := (cw - 24.0) / 3.0
	for i in TABS.size():
		var r := Rect2(x + i * (tw + 12.0), 122, tw, 44)
		var on: bool = tab == i
		ctrl.draw_rect(r, Color(Menu.C_AMBER.r, Menu.C_AMBER.g, Menu.C_AMBER.b, 0.85) if on else Color(1, 1, 1, 0.06))
		ctrl.draw_rect(r, Menu.C_AMBER if on else Color(1, 1, 1, 0.2), false, 1.5)
		_text(Vector2(r.position.x, r.position.y + 29), TABS[i], 19, Color(0.08, 0.07, 0.05) if on else Color(0.9, 0.92, 0.96), HORIZONTAL_ALIGNMENT_CENTER, tw)
		_buttons.append([r, "cx_tab:%d" % i])
	var rows: Array = []   # [название, что даёт, условия [[текст, выполнено?], …], открыта?, своя?]
	match tab:
		0:
			rows = _weapon_rows(p)
		1:
			rows = _skill_rows(p)
		_:
			rows = _evo_rows(p)
	var y := 186.0
	var hidden := 0
	var rh := 58.0 if tab == 0 else 74.0
	for row in rows:
		if p != null and not show_all and not row[4]:
			hidden += 1
			continue
		_row(Rect2(x, y, cw, rh), row)
		y += rh + 6.0
	if p != null and (hidden > 0 or show_all):
		_button(Rect2(x + cw - 300, y + 6, 300, 40), ("Показать все (ещё %d)" % hidden) if not show_all else "Только доступные", "cx_all", 16)
	if p != null:
		_text(Vector2(x, y + 32), "Зелёное — уже выполнено. Открыть можно связку своей специализации; сменить её — за 1 переброс.", 15, Color(0.65, 0.7, 0.78))


## Строка: слева название и что даёт, справа — что нужно и полоска прогресса
func _row(r: Rect2, row: Array) -> void:
	var opened: bool = row[3]
	var mine: bool = row[4]
	ctrl.draw_rect(r, Color(0.45, 1.0, 0.55, 0.09) if opened else Color(1, 1, 1, 0.04 if mine else 0.02))
	var tc := Color(0.5, 1.0, 0.6) if opened else (Color(1.0, 0.85, 0.5) if mine else Color(0.62, 0.64, 0.7))
	var lw := r.size.x * 0.48
	_text(Vector2(r.position.x + 14, r.position.y + 24), ("✓ " if opened else "") + String(row[0]), 19, tc, HORIZONTAL_ALIGNMENT_LEFT, lw - 20.0)
	_para(Vector2(r.position.x + 14, r.position.y + 44), String(row[1]), lw - 24.0, 14, Color(0.82, 0.85, 0.92) if mine else Color(0.55, 0.57, 0.62))
	var conds: Array = row[2]
	var rx := r.position.x + lw
	var rw := r.size.x - lw - 14.0
	var parts := PackedStringArray()
	var ok := 0
	for c in conds:
		parts.append(("✓ " if c[1] else "") + String(c[0]))
		if c[1]:
			ok += 1
	var live: bool = Main.I != null and Main.I.codex_back == "paused"
	_para(Vector2(rx, r.position.y + 22), "Нужно: " + " · ".join(parts), rw - (110.0 if live else 0.0), 14, Color(0.8, 0.83, 0.9))
	if not conds.is_empty() and live:
		var k := float(ok) / conds.size()
		var by := r.end.y - 8.0
		ctrl.draw_rect(Rect2(rx, by, rw - 110.0, 5), Color(1, 1, 1, 0.08))
		ctrl.draw_rect(Rect2(rx, by, (rw - 110.0) * k, 5), Color(0.45, 1.0, 0.55) if ok == conds.size() else Menu.C_AMBER)
		_text(Vector2(rx + rw - 100.0, r.position.y + 22), "%d из %d" % [ok, conds.size()], 15, Color(0.8, 0.83, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 100.0)


func _weapon_rows(p: Player) -> Array:
	var ids: Array = Cards.SYNERGIES.keys()
	if p != null:
		ids.sort_custom(func(a, b):
			var oa := 2.0 if p.syn.has(a) else _progress(_syn_conds(p, Cards.SYNERGIES[a]))
			var ob := 2.0 if p.syn.has(b) else _progress(_syn_conds(p, Cards.SYNERGIES[b]))
			return oa > ob)
	var out: Array = []
	for id in ids:
		var s: Dictionary = Cards.SYNERGIES[id]
		var mine := true
		if p != null and s.has("w") and s["w"] is Array:
			mine = false
			for w in s["w"]:
				mine = mine or Cards._wlevel(p, [w]) > 0
		if p != null and s.get("wingmen", false):
			mine = mine and p.permanent_wingmen() > 0
		out.append([s["title"], s["short"], _syn_conds(p, s), p != null and p.syn.has(id), mine or (p != null and p.syn.has(id))])
	return out


func _skill_rows(p: Player) -> Array:
	var skills: Array = []
	if p != null:
		skills = PlaneClasses.CLASS_SKILLS[p.cls_id]
	else:
		for c in PlaneClasses.LIST:
			skills.append_array(PlaneClasses.CLASS_SKILLS[c])
	var out: Array = []
	for sk in skills:
		var sd: Dictionary = PlaneClasses.SKILL3[sk]
		var ss: Dictionary = sd["syn"]
		var mine: bool = p == null or p.skill3 == sk
		var conds: Array = _syn_conds(p, ss, true) if (p != null and mine) else [[_cond_text(sk), false]]
		out.append(["«%s» (навык «%s»)" % [ss["title"], sd["title"]], ss["desc"], conds, p != null and p.syn.has(ss["id"]), mine])
	return out


func _evo_rows(p: Player) -> Array:
	var out: Array = []
	for w in Prog.EVOS:
		var ev: Dictionary = Prog.EVOS[w]
		var conds: Array = []
		var wname: String = "Пушка" if w == "gun" else Weapons.DEFS[w]["short"]
		var done := false
		var mine: bool = p == null or w == "gun"
		if w != "gun":
			var lv := 0
			for g in (p.groups if p != null else []):
				if (g as Hardpoint).weapon == w:
					lv = maxi(lv, (g as Hardpoint).level)
					done = done or (g as Hardpoint).evo
			mine = mine or lv > 0
			conds.append(["%s ур. 5%s" % [wname, (" (сейчас %d)" % lv) if (p != null and lv > 0) else ""], lv >= 5])
		else:
			done = p != null and p.gun_evo
		for mid in ev["cat"]:
			var have := int(p.taken.get(mid, 0)) if p != null else 0
			conds.append(["«%s» %s" % [Cards.MODULES[mid]["title"], ("%d/%d" % [have, int(ev["cat"][mid])]) if p != null else "×%d" % int(ev["cat"][mid])], p != null and have >= int(ev["cat"][mid])])
		out.append(["%s → «%s»" % [wname, String(ev["title"]).trim_prefix("«").trim_suffix("»")], String(ev.get("short", ev.get("desc", ""))), conds, done, mine or done])
	return out


## 3.2: условие связки навыка — главный (первый) тег навыка по порогам слотов + доводка I/II/III
func _cond_text(sk: String) -> String:
	var t: String = PlaneClasses.SKILL3[sk]["tags"][0]
	return "%s: %d очков + уровень навыка %d" % [Prog.tag_title(t), Cards.SLOT_COST[0]["main"], int(Cards.SLOT_COST[0].get("s3", 1))]
