class_name HudCampaign
extends HudKit
## «Подготовка и вылет», step 2 (Kanta 06.11): the mission screen. The plane is set up in the hangar, its
## «Приготовиться к вылету» button opens this screen: pick the theater (the second one opens after
## `CampaignGates.BIOME_UNLOCK_OPS` Highlands operations), pick the operation, «ВЫЛЕТ ▶». Each operation card has a
## slot for its art (`ART_DIR`/<op id>.png, drawn when the file exists) and a task list: the main task plus the
## operation's own objectives (`Campaign.tasks_of`, ✓ for the ones ever done).

const C_DONE := Color(0.5, 1.0, 0.6)
const C_LOCK := Color(0.45, 0.47, 0.5)


## Тред «Второй биом»: вкладки биомов над картой — у каждого своя цепочка операций (Campaign.OPS, поле "biome")
const BIOMES := [Biome.HIGHLAND, Biome.ARCHIPELAGO]


## Switches the theater on the mission screen (empty — the next one) and selects its last open operation. A theater
## that is not open yet (`Campaign.biome_open`) is not switched to.
static func switch_biome(to := "") -> void:
	var cur := Campaign.biome_of(Campaign.index())
	if to == "":
		to = BIOMES[(BIOMES.find(cur) + 1) % BIOMES.size()]
	if to == cur or not Campaign.biome_open(to):
		return
	var pick := -1
	for i in Campaign.ops_of(to):
		if Campaign.is_open(i):
			pick = i
	if pick >= 0:
		Campaign.select(pick)


## Before the mission screen opens: an operation left selected in a theater that is closed now (an old save, a demo)
## falls back to the first theater, and the operation art is loaded outside drawing (a texture first loaded inside a
## draw call drew as a white square in GL Compatibility).
static func prepare() -> void:
	var cur := Campaign.biome_of(Campaign.index())
	if not Campaign.biome_open(cur):
		switch_biome(Biome.HIGHLAND)
	for o: Dictionary in Campaign.OPS:
		var id := String(o["id"])
		if not _art.has(id):
			_art[id] = null
			for ext: String in [".jpg", ".png"]:
				var path := ART_DIR + id + ext
				if ResourceLoader.exists(path):
					_art[id] = load(path)
					break


## Folder with one picture per operation, named by its id (`pass.jpg`, `riverbed.jpg` …; .png also read). The operation art work
## drops files here; without a file the card shows the live vignette or a plain frame.
const ART_DIR := "res://art/ops/"
static var _art: Dictionary = {}



const C_TITLE := Color(1.0, 0.82, 0.29)
const C_SUB := Color(0.78, 0.82, 0.76)

## The story log («Журнал», step 3) is open over the screen: played scenes and choices, replay of hangar scenes.
static var log_open := false


## Story step 9 (F1 `story_vignette`): the operation card opens with a live window on the biome — the menu world
## behind the screen shows through a hole in the backdrop, the camera drifts as on the menu with the flight anchored
## in the window (`TitleFlight.ov_anchor`), the light preset and zoom follow the selected operation (`Main._process`).
static var vignette := Rect2()   # the window on screen this frame, Rect2() when off
var _brief_core_h := 0.0          # set by a measuring `_brief`: text height that must fit under the window
const ART_H := 300.0   # the operation art on top of the briefing, when the text leaves room
const VIGNETTE_MIN_H := 70.0   # a thinner window reads as a stripe, not a view: below this the card has none
const VIGNETTE_ZOOM := [0.95, 0.85, 0.75, 0.62]        # by operation index in the biome: closer first
const VIGNETTE_LIGHT := ["dawn", "day", "day", "dusk"]  # the operations' hours (intro presets)


static func vignette_on() -> bool:
	return Tuning.g("story_vignette") > 0.0 and Render3D.enabled


func draw(size: Vector2) -> void:
	var bd := Color(0.035, 0.04, 0.032, 0.9)
	if vignette.size.x > 0.0:   # the backdrop around the vignette window, the window itself only slightly dimmed
		var vg := vignette
		ctrl.draw_rect(Rect2(0, 0, size.x, vg.position.y), bd)
		ctrl.draw_rect(Rect2(0, vg.end.y, size.x, size.y - vg.end.y), bd)
		ctrl.draw_rect(Rect2(0, vg.position.y, vg.position.x, vg.size.y), bd)
		ctrl.draw_rect(Rect2(vg.end.x, vg.position.y, size.x - vg.end.x, vg.size.y), bd)
		ctrl.draw_rect(vg, Color(0.0, 0.0, 0.0, 0.12))
	else:
		ctrl.draw_rect(Rect2(Vector2.ZERO, size), bd)
	var m := Main.I
	_button(Rect2(64, 32, 220, 42), "‹ Ангар (Esc)", "campaign_back", 17)
	_button(Rect2(300, 32, 170, 42), "Журнал", "log_toggle", 17)
	_text(Vector2(64, 134), "РЕЖИМ ВЫЛЕТА", 50, C_TITLE)
	_text(Vector2(500, 132), "Выберите район и операцию — и в бой.", 19, C_SUB)
	_text(Vector2(0, 66), Loc.t("Запчасти: %d   ") % Profile.parts(), 22, Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 40)
	var bio := Campaign.biome_of(Campaign.index())
	var col_r := 400.0
	_biomes(Rect2(64, 170, 470, 96), bio)
	_ops(Rect2(64, 290, 470, size.y - 290 - 70), bio)
	_detail(Rect2(566, 170, size.x - 64 - col_r - 32 - 566, size.y - 170 - 70))
	_plane(m, Rect2(size.x - 64 - col_r, 170, col_r, size.y - 170 - 70))
	_text(Vector2(64, size.y - 26), Loc.t("Enter — вылет · ↑ / ↓ — операция · ← / → — район · Esc — ангар · управление: %s [F2]") % Loc.t(Hud.SCHEMES[int(Tuning.g("scheme"))]), 17, C_SUB)
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


## Step 1 of the screen: the theaters. A closed one shows what opens it (Kanta 06.11: after 3 Highlands operations).
func _biomes(r: Rect2, bio: String) -> void:
	_text(r.position + Vector2(0, 22), "1 · РАЙОН", 19, C_SUB)
	var gap := 12.0
	var w := (r.size.x - gap * (BIOMES.size() - 1)) / BIOMES.size()
	var mp := ctrl.get_local_mouse_position()
	for j in BIOMES.size():
		var b: String = BIOMES[j]
		var tr := Rect2(r.position.x + j * (w + gap), r.position.y + 34, w, r.size.y - 34)
		var bname := Loc.t(String(Biome.DATA[b]["name"]))
		var open := Campaign.biome_open(b)
		var on := b == bio
		if not open:
			_panel(tr, false, C_LOCK)
			_text(Vector2(tr.position.x, tr.position.y + 26), "🔒 " + bname, 16, C_LOCK, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
			var why := Loc.t(Demo.LOCKED) if not Demo.biome_ok(b) else Loc.t("после %d операций · осталось %d") % [CampaignGates.BIOME_UNLOCK_OPS, CampaignGates.left(Campaign.cleared_in(Biome.HIGHLAND))]
			_text(Vector2(tr.position.x, tr.position.y + 48), why, 14, C_LOCK, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
			continue
		var hover := tr.has_point(mp)
		ctrl.draw_rect(tr, Color(C_TITLE, 0.9) if on else Color(0.05, 0.06, 0.05, 0.8))
		ctrl.draw_rect(tr, C_TITLE if on or hover else Color(0.3, 0.36, 0.28), false, 2.0)
		var tc := Color(0.1, 0.08, 0.02) if on else Color(0.92, 0.9, 0.82)
		_text(Vector2(tr.position.x, tr.position.y + 26), bname, 17, tc, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
		var done := Campaign.cleared_in(b)
		_text(Vector2(tr.position.x, tr.position.y + 48), Loc.t("пройдено %d из %d") % [done, Campaign.ops_of(b).size()], 14, Color(tc, 0.75), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
		if not on:
			_buttons.append([tr, "biome:" + b])


## Step 2: the theater's operations in order. Each card has a small art slot (the operation picture when there is
## one), the name, difficulty and state.
func _ops(r: Rect2, bio: String) -> void:
	_text(r.position + Vector2(0, 22), "2 · ОПЕРАЦИЯ", 19, C_SUB)
	var mp := ctrl.get_local_mouse_position()
	var y := r.position.y + 40.0
	var ids := Campaign.ops_of(bio)
	var rh := minf(110.0, (r.end.y - y) / maxf(1.0, ids.size()) - 10.0)
	for j in ids.size():
		var i: int = ids[j]
		var o: Dictionary = Campaign.OPS[i]
		var avail := Campaign.is_open(i)
		var on := i == Campaign.index()
		var row := Rect2(r.position.x, y, r.size.x, rh)
		var hover := avail and row.has_point(mp)
		var a := 1.0 if avail else 0.5
		ctrl.draw_rect(row, Color(1.0, 0.82, 0.29, 0.2) if on else Color(0.05, 0.06, 0.05, 0.75))
		ctrl.draw_rect(row, Color(C_TITLE, a) if on or hover else Color(0.3, 0.36, 0.28, a), false, 2.0)
		var thumb := Rect2(row.position.x + 8, row.position.y + 8, rh * 1.6 - 16.0, rh - 16.0)
		_art_slot(thumb, String(o["id"]), j + 1, a)
		var tx := thumb.end.x + 16.0
		_text(Vector2(tx, y + rh * 0.5 - 6.0), "«%s»" % Loc.t(String(o["title"])), 21, Color(1, 1, 1, a))
		var sub := Loc.t(String(Campaign.DIFF[int(o["diff"])]["title"])) if avail else Loc.t("закрыта" if Demo.op_ok(i) else Demo.LOCKED)
		_text(Vector2(tx, y + rh * 0.5 + 20.0), sub, 15, Color(0.85, 0.83, 0.75, a))
		_text(Vector2(row.end.x - 50, y + rh * 0.5 + 10.0), "✓" if Campaign.cleared(i) else ("" if avail else "🔒"), 24, C_DONE if Campaign.cleared(i) else C_LOCK, HORIZONTAL_ALIGNMENT_CENTER, 40)
		if avail:
			_buttons.append([row, "op:%d" % i])
		y += rh + 10.0


## The operation picture in `r` (cover-fit and clipped) or, until the art exists, a plain frame with the operation
## number. `a` dims a closed operation.
func _art_slot(r: Rect2, id: String, n: int, a: float) -> void:
	var t: Texture2D = _art.get(id, null)
	if t != null:
		var ts := t.get_size()
		var k := maxf(r.size.x / ts.x, r.size.y / ts.y)
		var src := Rect2((ts - r.size / k) * 0.5, r.size / k)
		ctrl.draw_texture_rect_region(t, r, src, Color(1, 1, 1, a))
	else:
		ctrl.draw_rect(r, Color(0.1, 0.12, 0.09, a))
		for s in range(0, int(r.size.x + r.size.y), 14):   # diagonal hatching: reads as «picture goes here»
			var p0 := Vector2(r.position.x + minf(s, r.size.x), r.position.y + maxf(0.0, s - r.size.x))
			var p1 := Vector2(r.position.x + maxf(0.0, s - r.size.y), r.position.y + minf(s, r.size.y))
			ctrl.draw_line(p0, p1, Color(0.2, 0.24, 0.18, a), 1.0)
		_text(Vector2(r.position.x, r.get_center().y + 10.0), "%d" % n, 28, Color(0.85, 0.83, 0.75, a * 0.8), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	ctrl.draw_rect(r, Color(0.3, 0.36, 0.28, a), false, 1.0)


## The selected operation: a big art slot on top (the picture; without one the live vignette window on the biome, or
## the plain frame), then the name, the brief, the task list, the class task and the first-pass rewards.
func _detail(r: Rect2) -> void:
	_text(r.position + Vector2(0, 22), "3 · БРИФИНГ", 19, C_SUB)
	var box := Rect2(r.position.x, r.position.y + 34.0, r.size.x, r.size.y - 34.0)
	ctrl.draw_rect(box, Color(0.04, 0.055, 0.045, 0.75))
	ctrl.draw_rect(box, Color(0.24, 0.3, 0.23), false, 2.0)
	var x := box.position.x + 24.0
	var w := box.size.x - 48.0
	# The text sets the art's height, not the other way round (Kanta 04.11: long briefs ran out of the box): the art
	# shrinks to fit the whole text; if even ART_MIN_H leaves no room, it keeps that height and the tail of the rewards
	# list is cut; if the core text does not fit either, the art is dropped.
	var full_h := _brief(x, 0.0, w, INF, false)
	var pad := 18.0 + 20.0 + 2.0   # gap under the art, bottom padding, the art's frame line
	var vh := minf(ART_H, box.size.y - full_h - pad)
	if vh < VIGNETTE_MIN_H and box.size.y - _brief_core_h - pad >= VIGNETTE_MIN_H:
		vh = VIGNETTE_MIN_H
	vignette = Rect2()
	var y := box.position.y + 18.0
	if vh >= VIGNETTE_MIN_H:
		var ar := Rect2(box.position.x + 2.0, box.position.y + 2.0, box.size.x - 4.0, vh)
		var o := Campaign.op()
		if _art.get(String(o["id"]), null) == null and vignette_on():
			vignette = ar   # no picture yet: the live window on the biome (story step 9)
		else:
			_art_slot(ar, String(o["id"]), Campaign.num(), 1.0)
		ctrl.draw_rect(Rect2(ar.position.x, ar.end.y, ar.size.x, 2.0), Color(0.24, 0.3, 0.23))
		y = ar.end.y + 18.0
	_brief(x, y, w, box.end.y - 10.0, true)



## The selected operation's text under the art: name, brief, task list, first-pass rewards or the «cleared» line.
## `y` is the top of the text. With `paint` off nothing is drawn and the result is only the height, so `_ops` can size
## the window to what is left. The rewards list stops at `bottom` (it can be long); the rest is never cut, `_ops` makes
## room for it. A measuring pass also leaves `_brief_core_h`: the height through the spare-parts line, without the list.
func _brief(x: float, y: float, w: float, bottom: float, paint: bool) -> float:
	var top := y
	var o := Campaign.op()
	var d := Campaign.diff()
	_bt(Vector2(x, y + 30.0), Loc.t("Операция %d · «%s»") % [Campaign.num(), Loc.t(String(o["title"]))], 30, Color.WHITE, paint)
	y += 48.0
	y += _bp(Vector2(x, y + 14.0), Loc.t(String(o["brief"])), w, 16, Color(0.86, 0.88, 0.84), paint) + 26.0
	_bt(Vector2(x, y), "ЗАДАЧИ", 16, C_TITLE, paint)
	y += 12.0
	# the main task first, then the operation's own objectives (`OpTaskBalance`, F1 op_tasks): ✓ once ever done
	y += _bp(Vector2(x, y + 14.0), "◆ " + Loc.t(String(o["task"])), w, 18, Color.WHITE, paint) + 8.0
	var tasks := Campaign.tasks_of(Campaign.index())
	if OpTaskBalance.on() and not tasks.is_empty():
		y += 14.0
		_bt(Vector2(x, y), Loc.t("ЗАДАНИЯ ОПЕРАЦИИ · +%d запчастей за каждое") % int(OpTaskBalance.PARTS), 15, C_TITLE, paint)
		y += 10.0
		for t: Dictionary in tasks:
			var done := Campaign.task_done(Campaign.index(), String(t["id"]))
			y += _bp(Vector2(x, y + 14.0), ("✓ " if done else "• ") + Loc.t(String(t["brief"])), w, 17, C_DONE if done else Color(0.9, 0.92, 0.86), paint) + 6.0
	if int(o["diff"]) > 0:
		y += _bp(Vector2(x, y + 14.0), Loc.t("Сложность «%s»: враги прочнее ×%s, бьют сильнее ×%s, добыча ×%s") % [Loc.t(d["title"]), _k(d["hp"]), _k(d["dmg"]), _k(d["reward"])], w, 15, Color(1.0, 0.75, 0.55), paint) + 8.0
	y += 26.0
	if Campaign.cleared(Campaign.index()):
		# the first line's baseline sits at `y`, like the headings above
		y += _bp(Vector2(x, y), "✓ Пройдена — повторный вылет ради запчастей и опыта экипажа", w, 16, C_DONE, paint) - 12.0
		_brief_core_h = y - top
		return y - top
	_bt(Vector2(x, y), "ЗА ПЕРВЫЙ ПРОХОД", 16, C_TITLE, paint)
	y += 26.0
	_bt(Vector2(x, y), Loc.t("• +%d запчастей") % int(o["parts"]), 16, Color(0.95, 0.85, 0.55), paint)
	y += 4.0
	_brief_core_h = y - top + 6.0
	for s in Demo.opens(o):
		var line := Loc.t("• Откроется: ") + Loc.t(String(s))
		var h := _bp(Vector2(x, y + 18.0), line, w, 16, Color.WHITE, false)
		if y + 4.0 + h > bottom:
			break   # what does not fit is cut whole, never drawn over the frame
		y += _bp(Vector2(x, y + 18.0), line, w, 16, Color(1.0, 0.85, 0.4), paint) + 2.0
	return y - top + 6.0


## `_para` that only measures when `paint` is off (same font, width and size, so the height matches the drawing).
func _bp(pos: Vector2, s: String, width: float, size: int, color: Color, paint: bool) -> float:
	if paint:
		return _para(pos, s, width, size, color)
	return ui_font().get_multiline_string_size(Loc.out(s), HORIZONTAL_ALIGNMENT_LEFT, width, size).y


## `_text` that draws only when `paint` is on.
func _bt(pos: Vector2, s: String, size: int, color: Color, paint: bool) -> void:
	if paint:
		_text(pos, s, size, color)


## Right column: the plane set up in the hangar (picture, level, skill, starting weapons) with a way back to change
## it, and the big «ВЫЛЕТ ▶». The plane is picked in the hangar only, so this screen never disagrees with it.
func _plane(m: Main, r: Rect2) -> void:
	_text(r.position + Vector2(0, 22), "САМОЛЁТ", 19, C_SUB)
	var id := m.cls_id
	var d: Dictionary = PlaneClasses.DATA[id]
	var col: Color = d["color"]
	var card := Rect2(r.position.x, r.position.y + 34.0, r.size.x, r.size.y - 34.0 - 130.0)
	ctrl.draw_rect(card, Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.9))
	ctrl.draw_rect(card, Color(col, 0.8), false, 2.0)
	var band := Rect2(card.position, Vector2(card.size.x, 36))
	ctrl.draw_rect(band, col)
	_text(Vector2(band.position.x + 14, band.position.y + 25), Loc.t(String(d["title"])), 15, Color(0.06, 0.08, 0.06))
	var t := PlaneArt.plane_tex(id, Profile.plane_model(id))
	var pic := Rect2(card.position.x, band.end.y + 6.0, card.size.x, 190.0)
	if t != null:
		var k := minf(pic.size.y / t.get_width(), (card.size.x * 0.8) / t.get_height())
		ctrl.draw_set_transform(pic.get_center(), -PI / 2.0, Vector2(k, k))
		ctrl.draw_texture(t, -t.get_size() / 2.0)
		ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var x := card.position.x + 18.0
	var tw := card.size.x - 36.0
	var y := pic.end.y + 28.0
	_text(Vector2(x, y), Loc.t("Самолёт ур. %d · экипаж ур. %d") % [Profile.tier(id), Profile.crew_lvl(id)], 17, Color.WHITE)
	y += 30.0
	var sk: String = m.skill_pick.get(id, Profile.skills(id)[0])
	y += _para(Vector2(x, y), Loc.t("Навык [E]: %s") % Loc.t(String(PlaneClasses.SKILL3[sk]["title"])), tw, 16, Color(0.7, 1.0, 0.7)) + 8.0
	var start := PackedStringArray()
	for w in Profile.start_weapons(id):
		start.append(Loc.t(String(Weapons.DEFS[w]["short"])))
	if not start.is_empty():
		y += _para(Vector2(x, y), Loc.t("На старте: %s") % ", ".join(start), tw, 16, C_SUB) + 8.0
	y += 10.0
	_text(Vector2(x, y), "ЗАДАНИЕ КЛАССА · награда — редкая карточка", 15, C_TITLE)
	y += 8.0
	_para(Vector2(x, y + 14.0), Loc.t(String(ClassTask.DEFS[id]["brief"])), tw, 15, Color(1.0, 0.88, 0.55))
	if Profile.upgrade_hint(id):   # 06.11 review, point 4: the plane goes up with zero upgrades while parts lie unspent
		var hr := Rect2(card.position.x + 12, card.end.y - 58.0 - 70.0, card.size.x - 24, 60.0)
		ctrl.draw_rect(hr, Color(1.0, 0.6, 0.15, 0.16))
		ctrl.draw_rect(hr, Color(1.0, 0.72, 0.35), false, 1.5)
		_para(Vector2(hr.position.x + 12, hr.position.y + 24), Loc.t("Можно улучшить самолёт: узлы без улучшений, запчастей хватает (%d)") % Profile.parts(), hr.size.x - 24, 15, Color(1.0, 0.8, 0.5))
		_button(Rect2(card.position.x + 12, card.end.y - 58.0, card.size.x - 24, 46.0), Loc.t("‹ Улучшить в ангаре"), "campaign_back", 17)
	else:
		_button(Rect2(card.position.x + 12, card.end.y - 58.0, card.size.x - 24, 46.0), Loc.t("‹ Изменить в ангаре") + ("  !" if Profile.any_purchase() else ""), "campaign_back", 17)
	_go(Rect2(r.position.x, r.end.y - 110.0, r.size.x, 110.0))


## The big «ВЫЛЕТ ▶» button (Enter / gamepad A do the same).
func _go(b: Rect2) -> void:
	_buttons.append([b, "op_go"])
	var hot := b.has_point(ctrl.get_local_mouse_position())
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	for k in 4:
		ctrl.draw_rect(b.grow(3.0 + k * 4.0), Color(1.0, 0.65, 0.15, 0.06 + 0.04 * pulse), false, 4.0)
	for k in 10:   # градиент сверху вниз: жёлтый → оранжевый
		ctrl.draw_rect(Rect2(b.position.x, b.position.y + k * b.size.y / 10.0, b.size.x, b.size.y / 10.0), Color(1.0, 0.82, 0.29).lerp(Color(1.0, 0.6, 0.12), k / 9.0).lightened(0.1 if hot else 0.0))
	ctrl.draw_string(ui_font(), Vector2(b.position.x, b.position.y + b.size.y * 0.5 + 14.0), Loc.out("ВЫЛЕТ ▶"), HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 40, Color(0.1, 0.08, 0.02))


static func _k(v) -> String:
	return ("%.1f" % float(v)).replace(".", ",")
