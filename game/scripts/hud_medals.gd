class_name HudMedals
extends HudKit
## Hangar tab «НАГРАДЫ» (Kanta 2026-10-27, «Наградная планка»): every medal as a board — the picture in the metal of
## the reached tier (grey before the first), the name, ribbon of tiers and a bar to the next one. The medal under
## the cursor (or the one clicked) is explained below the board: condition, bonus now, bonus of the next tier.
## Also draws the «new medal» strip of the result screen. Data: MedalBalance, counters: Profile.

static var _tex := {}


## Picture of medal `id` in `metal` (art/medals/<id>_<metal>.svg, made by tools/medals/make_medals.py)
static func tex(id: String, metal: String) -> Texture2D:
	var key := id + "_" + metal
	if not _tex.has(key):
		var path := "res://art/medals/%s.svg" % key
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]


## Player text of a medal's bonus at tier `n` ("" for picture-only medals)
static func bonus_text(md: Dictionary, n: int) -> String:
	var tpl: String = md["bonus"]
	if tpl == "" or n <= 0 or is_zero_approx(float(md["v"][n - 1])):
		return ""   # tiers below the first bonus (e.g. operation medals 1–3, «Мастер связок» 1) add nothing
	var t := Loc.t(tpl)
	if t.contains("%s"):
		return t % MedalBalance.value_text(md["b"], float(md["v"][n - 1]))
	return t.replace("%%", "%")


## Player text of what tier `n` asks for
static func cond_text(md: Dictionary, n: int) -> String:
	var t := Loc.t(String(md["cond"]))
	if not t.contains("%s"):
		return t.replace("%%", "%")
	var th := int(md["t"][clampi(n, 1, (md["t"] as Array).size()) - 1])
	return t % (Loc.t("все") if th < 0 else MedalBalance.grouped(th))


func draw(m: Main, area: Rect2) -> void:
	var tiers := Profile.medal_tiers()
	var cnt := Profile.medal_counters()
	var sets := Medals.sets()
	var list: Array = MedalBalance.LIST
	var detail_h := 118.0
	var cols := maxi(6, int(area.size.x / 150.0))
	var rows := int(ceil(list.size() / float(cols)))
	var cw := area.size.x / cols
	var ch := minf(170.0, (area.size.y - detail_h - 12.0) / rows)
	var icon := minf(cw - 30.0, ch - 46.0)
	var mouse := ctrl.get_local_mouse_position()
	var show_id: String = m.hangar_medal
	var earned := 0
	var all_tiers := 0
	for i in list.size():
		var md: Dictionary = list[i]
		var id: String = md["id"]
		var n := int(tiers.get(id, 0))
		var count := (md["t"] as Array).size()
		earned += n
		all_tiers += count
		var cell := Rect2(area.position.x + (i % cols) * cw, area.position.y + (i / cols) * ch, cw, ch)
		var hover := cell.has_point(mouse)
		if hover:
			show_id = id
		var sel := id == m.hangar_medal
		if hover or sel:
			ctrl.draw_rect(cell.grow(-3.0), Color(1, 1, 1, 0.07 if hover else 0.04))
			ctrl.draw_rect(cell.grow(-3.0), Menu.C_AMBER if sel else Color(1, 1, 1, 0.2), false, 1.5)
		_buttons.append([cell, "hg:medal:" + id])
		var hidden: bool = md.get("hide", false) and n == 0
		var ir := Rect2(cell.position.x + (cw - icon) / 2.0, cell.position.y + 4.0, icon, icon)
		var t := tex(id, MedalBalance.metal(n, count))
		if hidden:
			ctrl.draw_circle(ir.get_center(), icon * 0.38, Color(1, 1, 1, 0.06))
			_text(Vector2(ir.position.x, ir.get_center().y + 14), "?", 36, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER, icon)
		elif t != null:
			ctrl.draw_texture_rect(t, ir, false, Color(1, 1, 1, 1.0 if n > 0 else 0.55))
		var title := "???" if hidden else Loc.t(String(md["title"]))
		var fs := _title_size(title, cw - 8)
		_text(Vector2(cell.position.x + 4, ir.end.y + 16), _fit(title, cw - 8, fs), fs, UiStyle.TEXT if n > 0 else UiStyle.TEXT_OFF, HORIZONTAL_ALIGNMENT_CENTER, cw - 8)
		# tier pips and a bar to the next tier
		var pw := 10.0
		var px := cell.get_center().x - (count * (pw + 4.0) - 4.0) / 2.0
		for k in count:
			ctrl.draw_rect(Rect2(px + k * (pw + 4.0), ir.end.y + 22, pw, 5), Menu.C_AMBER if k < n else Color(1, 1, 1, 0.15))
		if n < count and not hidden:
			var need := int(md["t"][n])
			need = int(sets.get(md["c"], 0)) if need < 0 else need
			var have := int(cnt.get(md["c"], 0))
			var f := clampf(float(have) / maxf(float(need), 1.0), 0.0, 1.0)
			var br := Rect2(cell.position.x + 18, ir.end.y + 31, cw - 36, 3)
			ctrl.draw_rect(br, Color(1, 1, 1, 0.08))
			ctrl.draw_rect(Rect2(br.position, Vector2(br.size.x * f, br.size.y)), UiStyle.OK)
	_text(Vector2(area.position.x, area.position.y - 8), Loc.t("Ступеней получено: %d из %d") % [earned, all_tiers], 15, UiStyle.TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, area.size.x)
	_detail(show_id, tiers, cnt, sets, Rect2(area.position.x, area.end.y - detail_h, area.size.x, detail_h))


## S14-17 (self-check: «Небо над Шахрисангом» was cut to «Небо над Шахри…»): the largest of 14…11 px at which the
## medal name fits its cell, so long names shrink a little instead of losing their end; 11 px still cuts with «…»
func _title_size(title: String, width: float) -> int:
	var f := ui_font()
	var s := Loc.out(title)
	for fs in [14, 13, 12]:
		if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
			return fs
	return 11


func _detail(id: String, tiers: Dictionary, cnt: Dictionary, sets: Dictionary, r: Rect2) -> void:
	_panel(r, false)
	var md := MedalBalance.by_id(id)
	if md.is_empty():
		_text(Vector2(r.position.x + 20, r.position.y + 40), Loc.t("Наведите на медаль — здесь условие и бонус. Бонусы медалей действуют всегда и складываются до +10 %."), 16, UiStyle.TEXT_2)
		return
	var n := int(tiers.get(id, 0))
	var count := (md["t"] as Array).size()
	var hidden: bool = md.get("hide", false) and n == 0
	var t := tex(id, MedalBalance.metal(n, count))
	var ir := Rect2(r.position.x + 12, r.position.y + 9, r.size.y - 18, r.size.y - 18)
	if t != null and not hidden:
		ctrl.draw_texture_rect(t, ir, false)
	var x := ir.end.x + 18
	var title := "???" if hidden else Loc.t(String(md["title"]))
	var tier_s := Loc.t("ступень %d из %d") % [n, count] if count > 1 else (Loc.t("получена") if n > 0 else Loc.t("не получена"))
	_text(Vector2(x, r.position.y + 32), "%s · %s" % [title, tier_s], 22, Menu.C_AMBER)
	if hidden:
		_text(Vector2(x, r.position.y + 62), Loc.t("Скрытая медаль: условие откроется, когда она будет получена."), 16, UiStyle.TEXT_2)
		return
	var y := r.position.y + 60
	var now := bonus_text(md, n)
	if n < count:
		var need := int(md["t"][n])
		need = int(sets.get(md["c"], 0)) if need < 0 else need
		var nxt := bonus_text(md, n + 1)
		_text(Vector2(x, y), cond_text(md, n + 1) + Loc.t(" — сейчас %s из %s") % [MedalBalance.grouped(int(cnt.get(md["c"], 0))), MedalBalance.grouped(need)], 17, UiStyle.TEXT)
		if nxt != "":
			_text(Vector2(x, y + 26), Loc.t("Следующая ступень: %s") % nxt, 16, UiStyle.OK)
	else:
		_text(Vector2(x, y), cond_text(md, count) + Loc.t(" — выполнено"), 17, UiStyle.TEXT)
	if now != "":
		_text(Vector2(x, y + 48), Loc.t("Действует: %s") % now, 16, UiStyle.ACCENT_SOFT)


## Result screen: the medals that reached a new tier in this sortie, pictures in a row with names; returns the height
func new_strip(list: Array, pos: Vector2, w: float) -> float:
	if list.is_empty():
		return 0.0
	_text(Vector2(pos.x, pos.y + 18), Loc.t("НОВЫЕ МЕДАЛИ"), UiStyle.FS_CAPTION, UiStyle.ACCENT_SOFT)
	var n := mini(list.size(), 4)
	var cw := w / 4.0
	for i in n:
		var md := MedalBalance.by_id(String(list[i][0]))
		var tier := int(list[i][1])
		var t := tex(md["id"], MedalBalance.metal(tier, (md["t"] as Array).size()))
		var ir := Rect2(pos.x + i * cw + (cw - 56.0) / 2.0, pos.y + 26, 56, 56)
		if t != null:
			ctrl.draw_texture_rect(t, ir, false)
		_text(Vector2(pos.x + i * cw, ir.end.y + 14), _fit(Loc.t(String(md["title"])), cw - 4, 12), 12, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cw - 4)
	if list.size() > n:
		_text(Vector2(pos.x, pos.y + 18), Loc.t("+ ещё %d в ангаре") % (list.size() - n), UiStyle.FS_CAPTION, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w)
	return 104.0
