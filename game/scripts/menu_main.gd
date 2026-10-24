class_name MenuMain
extends RefCounted
## Main menu screen (UI-01, plan step 1): five items in the «Прицел» style on the left, the
## «Что нового» and «Отзыв» cards, theater switch and a compact flight log on the right,
## key hints at the bottom. Created and drawn by `Menu` while the game is in state "menu";
## every item works with mouse, keyboard and gamepad through `UiFocus`. Actions go to
## `Main.ui_click`, except the two cards, which open overlays owned by this screen.

## Left column: [action, label]
const ITEMS := [
	[&"menu_play", "ВЫЛЕТ"],
	[&"menu_hangar", "АНГАР"],
	[&"menu_codex", "СПРАВОЧНИК"],
	[&"menu_settings", "НАСТРОЙКИ"],
	[&"menu_quit", "ВЫХОД"],
]
## Theater switch: [biome id, label]. Archipelago is a test area for now (Kanta 2026-10-24).
const BIOMES := [["highland", "НАГОРЬЕ"], ["archipelago", "АРХИПЕЛАГ"]]
const ROW_H := 92.0
const ROW_W := 490.0
const COL_W := 500.0

var menu: Menu
var ctrl: Control
## Open overlay: &"" (none), &"whats_new" or &"feedback"
var overlay: StringName = &""
var _focus: StringName = &"menu_play"
var _focus_back: StringName = &"menu_play"
## Selection wipe-in per action id, 0…1
var _anim: Dictionary[StringName, float] = {}
## Focusable items drawn this frame, in draw order: [Rect2, StringName]
var _items: Array = []


func _init(owner: Menu) -> void:
	menu = owner
	ctrl = owner.ctrl


## Back to the default state when the menu opens again (focus on «Вылет», no overlay).
func reset() -> void:
	overlay = &""
	_focus = &"menu_play"


## Advances the selection wipe-in of every item towards its target.
func process(delta: float) -> void:
	var step := delta / UiStyle.WIPE_S
	for id: StringName in _anim.keys():
		var target := 1.0 if id == _focus else 0.0
		_anim[id] = move_toward(_anim[id], target, step)
	if not _anim.has(_focus):
		_anim[_focus] = 0.0


## Handles one input event; returns true when it was used (caller marks it handled).
func handle_input(event: InputEvent) -> bool:
	var mp := ctrl.get_local_mouse_position()
	if event is InputEventMouseMotion:
		var hover := _hit(mp)
		if hover != &"":
			_focus = hover
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit := _hit(mp)
		if hit != &"":
			_activate(hit)
			return true
		if overlay != &"":
			_close_overlay()
			return true
		return false
	if event.is_action_pressed("ui_cancel"):
		if overlay != &"":
			_close_overlay()
			return true
		return false
	var dir := UiFocus.dir_of(event)
	if dir != Vector2i.ZERO:
		_move(dir)
		return true
	if event.is_action_pressed("ui_accept"):
		_activate(_focus)
		return true
	return false


## Draws the whole screen into `ctrl`; the header line and the left shade come from `Menu`.
func draw(size: Vector2) -> void:
	_items.clear()
	_logo()
	var y0 := size.y - 70.0 - 36.0 - ITEMS.size() * ROW_H
	for i in ITEMS.size():
		_item(Rect2(96, y0 + i * ROW_H, ROW_W, ROW_H - 8.0), ITEMS[i][0], ITEMS[i][1])
	var x := size.x - UiStyle.MARGIN - COL_W
	_card(Rect2(x, 150, COL_W, 84), &"mm_whats_new", "ЧТО НОВОГО",
		Loc.t("СБОРКА %s · СПИСОК ИЗМЕНЕНИЙ") % Demo.tag(Main.BUILD), false)
	_card(Rect2(x, 252, COL_W, 84), &"mm_feedback", "ОТЗЫВ", Loc.t("СООБЩИТЬ О ПРОБЛЕМЕ · ЛОГИ"), true)
	_biomes(Rect2(x, 408, COL_W, 82))
	_flight_log(Rect2(x, 520, COL_W, 186))
	if Demo.on:   # M-07: demo — wishlist button under the log
		_card(Rect2(x, 730, COL_W, 84), &"wishlist", "В СПИСОК ЖЕЛАЕМОГО",
			Loc.t("Полная игра: Архипелаг, самолёты ур. 2, ещё 2 операции"), false)
	var hx := float(UiStyle.MARGIN)
	hx = UiStyle.key_hint(ctrl, Vector2(hx, size.y - 32), "↑↓", Loc.t("ВЫБОР"))
	hx = UiStyle.key_hint(ctrl, Vector2(hx, size.y - 32), "ENTER", Loc.t("ОТКРЫТЬ"))
	UiStyle.key_hint(ctrl, Vector2(hx, size.y - 32), "ESC", Loc.t("НАЗАД"))
	if overlay != &"":
		_items.clear()   # only the overlay's buttons take focus and clicks
		_overlay(size)
	if not _ids().has(_focus):
		_focus = _ids()[0] if not _items.is_empty() else &""


# ---------- Focus and actions ----------

func _ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for it: Array in _items:
		out.append(it[1])
	return out


func _rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for it: Array in _items:
		out.append(it[0])
	return out


## Topmost item under the mouse (searched from the end: drawn last gets the click).
func _hit(mp: Vector2) -> StringName:
	for i in range(_items.size() - 1, -1, -1):
		if (_items[i][0] as Rect2).has_point(mp):
			return _items[i][1]
	return &""


func _move(dir: Vector2i) -> void:
	var ids := _ids()
	var i := UiFocus.index_of(ids, _focus)
	var j := UiFocus.step(_rects(), i, dir)
	if j >= 0 and ids[j] != _focus:
		_focus = ids[j]
		Main.I.sfx.play("card", -24.0 + Tuning.g("ui_db"), 1.6)


func _activate(id: StringName) -> void:
	if id == &"":
		return
	var m := Main.I
	m.sfx.play("card", -16.0 + Tuning.g("ui_db"), 1.3)
	match id:
		&"mm_whats_new", &"mm_feedback":
			_focus_back = id
			overlay = &"whats_new" if id == &"mm_whats_new" else &"feedback"
			_focus = &"mm_close" if id == &"mm_whats_new" else (&"report_open" if Main.REPORT_URL != "" else &"menu_logs")
		&"mm_close":
			_close_overlay()
		_:
			var a := String(id)
			if a.begins_with("menu_biome:") and a.substr(11) == Campaign.biome_of(Campaign.index()):
				return   # already there: rebuilding the world behind the menu would only stall
			m.ui_click(a)


func _close_overlay() -> void:
	overlay = &""
	_focus = _focus_back


func _focus_k(id: StringName) -> float:
	return _anim.get(id, 0.0)


# ---------- Drawing ----------

## «FLAK HEAVEN» in one line with the red hazard stripe under it.
func _logo() -> void:
	var f := UiStyle.head_font(800, 4)
	UiStyle.text(ctrl, f, Vector2(96, 262), "FLAK", 128, UiStyle.TEXT_WARM)
	var w := UiStyle.text_w(f, "FLAK ", 128)
	UiStyle.text(ctrl, f, Vector2(96 + w, 262), "HEAVEN", 128, UiStyle.ACCENT)
	for i in 21:
		var x := 100.0 + i * 24.0
		ctrl.draw_colored_polygon(PackedVector2Array([Vector2(x + 6, 292), Vector2(x + 20, 292),
			Vector2(x + 14, 304), Vector2(x, 304)]), UiStyle.BRAND_RED)


func _item(r: Rect2, id: StringName, label: String) -> void:
	var note := ""
	var badge := false
	if id == &"menu_hangar":
		badge = Profile.any_purchase()
		note = Loc.t("ЗАПЧАСТИ %d") % Profile.parts()
		if badge:
			note += " · " + Loc.t("ЕСТЬ ЧТО КУПИТЬ")
	UiStyle.menu_item(ctrl, r, label, _focus_k(id), true, note, badge)
	_items.append([r, id])


## Right-column card: icon, title, caption; brackets and an amber border when focused.
func _card(r: Rect2, id: StringName, title: String, caption: String, bubble: bool) -> void:
	var k := _focus_k(id)
	var border := UiStyle.LINE.lerp(UiStyle.ACCENT, k)
	UiStyle.panel(ctrl, r, border, Color(0.07, 0.075, 0.07, 0.88), UiStyle.CUT, UiStyle.BORDER + k)
	var c := r.position + Vector2(46, r.size.y * 0.5)
	var ic := UiStyle.TEXT_WARM.lerp(UiStyle.ACCENT, k)
	if bubble:   # speech bubble: «Отзыв»
		ctrl.draw_rect(Rect2(c.x - 16, c.y - 13, 32, 22), ic)
		ctrl.draw_colored_polygon(PackedVector2Array([Vector2(c.x - 10, c.y + 9), Vector2(c.x - 2, c.y + 9), Vector2(c.x - 10, c.y + 16)]), ic)
		for i in 3:
			ctrl.draw_rect(Rect2(c.x - 10, c.y - 8 + i * 6, 20 - i * 6, 2.5), UiStyle.ON_ACCENT)
	else:   # envelope: «Что нового»
		var e := Rect2(c.x - 17, c.y - 12, 34, 24)
		ctrl.draw_rect(e, ic)
		ctrl.draw_polyline(PackedVector2Array([e.position, Vector2(c.x, c.y + 2), Vector2(e.end.x, e.position.y)]), UiStyle.ON_ACCENT, 2.5)
	var tx := r.position.x + 86.0
	UiStyle.text(ctrl, UiStyle.head_font(700, 4), Vector2(tx, r.position.y + 42), title, 26, UiStyle.TEXT_WARM.lerp(UiStyle.ACCENT, k))
	UiStyle.text(ctrl, UiStyle.head_font(600, 2), Vector2(tx, r.position.y + 66), caption, UiStyle.FS_CAPTION, UiStyle.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100.0)
	if k > 0.0:
		UiStyle.brackets(ctrl, r.grow(4), Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, k), k)
	_items.append([r, id])


## Theater switch: two segments, the current one filled amber. A locked demo theater is
## shown but cannot be focused.
func _biomes(r: Rect2) -> void:
	var lf := UiStyle.head_font(700, 4)
	# backing tab: on a bright frame (snow, a plane passing under) the bare caption got lost
	ctrl.draw_rect(Rect2(r.position.x, r.position.y, UiStyle.text_w(lf, "РАЙОН ВЫЛЕТА", UiStyle.FS_BODY) + 20.0, 32.0),
		Color(0.07, 0.075, 0.07, 0.88))
	UiStyle.text(ctrl, lf, Vector2(r.position.x + 10, r.position.y + 22), "РАЙОН ВЫЛЕТА", UiStyle.FS_BODY, UiStyle.TEXT_DIM)
	var cur := Campaign.biome_of(Campaign.index())
	var w := r.size.x * 0.5
	for i in BIOMES.size():
		var b: Array = BIOMES[i]
		var s := Rect2(r.position.x + i * w, r.position.y + 34, w, r.size.y - 34)
		var on: bool = b[0] == cur
		var id := StringName("menu_biome:" + String(b[0]))
		var k := _focus_k(id)
		var locked := not Demo.biome_ok(b[0])
		ctrl.draw_rect(s, UiStyle.ACCENT if on else Color(0.07, 0.075, 0.07, 0.88))
		ctrl.draw_rect(s, UiStyle.LINE.lerp(UiStyle.ACCENT, maxf(k, 1.0 if on else 0.0)), false, UiStyle.BORDER)
		var tc := UiStyle.ON_ACCENT if on else (UiStyle.TEXT_OFF if locked else UiStyle.TEXT_WARM.lerp(UiStyle.ACCENT, k))
		var f := UiStyle.head_font(700, 4)
		var tag := Loc.t(Demo.LOCKED) if locked else (Loc.t("ТЕСТ") if b[0] == "archipelago" else "")
		var lw := UiStyle.text_w(f, b[1], UiStyle.FS_LABEL)
		var tw := UiStyle.text_w(UiStyle.head_font(600, 1), tag, UiStyle.FS_CAPTION) + 12.0 if tag != "" else 0.0
		var lx := s.position.x + (s.size.x - lw - (tw + 10.0 if tag != "" else 0.0)) * 0.5
		UiStyle.text(ctrl, f, Vector2(lx, s.position.y + 31), b[1], UiStyle.FS_LABEL, tc)
		if tag != "":
			var tr := Rect2(lx + lw + 10.0, s.position.y + 13, tw, 22)
			ctrl.draw_rect(tr, Color(tc.r, tc.g, tc.b, 0.8), false, 1.0)
			UiStyle.text(ctrl, UiStyle.head_font(600, 1), Vector2(tr.position.x, tr.position.y + 16), tag, UiStyle.FS_CAPTION, tc,
				HORIZONTAL_ALIGNMENT_CENTER, tw)
		if k > 0.0 and not on:
			UiStyle.brackets(ctrl, s.grow(-3), Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, k), k)
		if not locked:
			_items.append([s, id])


## Compact flight log (Kanta 2026-10-24): four numbers and the last sortie.
func _flight_log(r: Rect2) -> void:
	UiStyle.panel(ctrl, r, UiStyle.LINE, Color(0.07, 0.075, 0.07, 0.88))
	var rec: Dictionary = menu.records
	var hf := UiStyle.head_font(700, 4)
	UiStyle.text(ctrl, hf, r.position + Vector2(28, 40), "ЖУРНАЛ ПОЛЁТОВ", UiStyle.FS_BODY, UiStyle.TEXT_DIM)
	var bt := float(rec["best_time"])
	var stats := [[str(int(rec["sorties"])), "ВЫЛЕТОВ"], [str(int(rec["evacs"])), "ЭВАКУАЦИЙ"],
		["%d:%02d" % [int(bt / 60.0), int(bt) % 60], "РЕКОРД"], [str(int(rec["best_level"])), "УР. ПИЛОТА"]]
	var cw := (r.size.x - 56.0) / stats.size()
	for i in stats.size():
		var sx := r.position.x + 28.0 + i * cw
		UiStyle.text(ctrl, UiStyle.head_font(800, 1), Vector2(sx, r.position.y + 92), stats[i][0], 32, UiStyle.ACCENT)
		# long translations («EXTRACTIONS») lose their letter spacing before they touch the next column
		var lf := UiStyle.head_font(600, 2)
		if UiStyle.text_w(lf, stats[i][1], UiStyle.FS_CAPTION) > cw - 12.0:
			lf = UiStyle.head_font(600, 0)
		UiStyle.text(ctrl, lf, Vector2(sx, r.position.y + 114), stats[i][1], UiStyle.FS_CAPTION, UiStyle.TEXT_DIM)
	ctrl.draw_line(r.position + Vector2(28, 134), Vector2(r.end.x - 28, r.position.y + 134), UiStyle.LINE, 1.0)
	var last: Array = rec["last"]
	var body := Hud.ui_font()
	var ly := r.position.y + 164.0
	if last.is_empty():
		UiStyle.text(ctrl, body, Vector2(r.position.x + 28, ly), "Пока пусто — самое время на взлёт", UiStyle.FS_BODY, UiStyle.TEXT_DIM)
		return
	var e: Dictionary = last[0]
	var t := float(e["t"])
	var ok: bool = e["o"] == "эвакуация"
	var bold := Menu.bold()
	# [text, font, colour]; the «Последний:» prefix goes first when the line does not fit
	var parts: Array = [[Loc.t("Последний: "), body, UiStyle.TEXT_DIM], [Loc.out(String(e["c"])), bold, UiStyle.TEXT_WARM],
		[Loc.t(" · %d:%02d · ур. %d · %d сбито · ") % [int(t / 60.0), int(t) % 60, int(e["l"]), int(e["k"])], body, UiStyle.TEXT_DIM],
		[Loc.out(String(e["o"])), body, UiStyle.OK if ok else UiStyle.DANGER]]
	var avail := r.size.x - 56.0
	var fs := UiStyle.FS_BODY
	if _parts_w(parts, fs) > avail:
		parts.pop_front()
	if _parts_w(parts, fs) > avail:
		fs = UiStyle.FS_MIN
	var x := r.position.x + 28.0
	for p: Array in parts:
		UiStyle.text(ctrl, p[1], Vector2(x, ly), p[0], fs, p[2])
		x += UiStyle.text_w(p[1], p[0], fs)


func _parts_w(parts: Array, fs: int) -> float:
	var w := 0.0
	for p: Array in parts:
		w += UiStyle.text_w(p[1], p[0], fs)
	return w


## «Что нового» or «Отзыв» over a dimmed menu; only its buttons take focus.
func _overlay(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), UiStyle.SCRIM)
	var w := minf(1000.0, size.x - 160.0)
	var lines: Array = []
	var title := ""
	var sub := ""
	if overlay == &"whats_new":
		title = "ЧТО НОВОГО"
		sub = Loc.t("Сборка %s") % Demo.tag(Main.BUILD)
		lines = WhatsNew.LINES
	else:
		title = "ОТЗЫВ"
		sub = Loc.t("Нашли ошибку или есть идея — напишите нам")
		lines = ["Отчёт уходит организатору теста вместе со статистикой последнего вылета; личных данных нет",
			"Файлы логов лежат в папке игры: приложите playtest_log_*.csv и logs/godot.log к письму",
			"Почта hello@flakheaven.com, сервер Discord — ссылка на flakheaven.com"]
	var body := Hud.ui_font()
	var wrapped: Array = []
	var text_h := 0.0
	for ln in lines:
		var parts := menu.wrap(String(ln), w - 120.0, UiStyle.FS_LABEL)
		wrapped.append(parts)
		text_h += parts.size() * 28.0 + 12.0
	var buttons: Array = []   # [id, label]
	if overlay == &"feedback":
		if Main.REPORT_URL != "":
			buttons.append([&"report_open", "ОТПРАВИТЬ ОТЧЁТ"])
		buttons.append([&"menu_logs", "ОТКРЫТЬ ПАПКУ С ЛОГАМИ"])
	buttons.append([&"mm_close", "ЗАКРЫТЬ"])
	var h := 150.0 + text_h + buttons.size() * 70.0 + 30.0
	var r := Rect2((size.x - w) * 0.5, maxf(110.0, (size.y - h) * 0.5), w, h)
	UiStyle.panel(ctrl, r, UiStyle.ACCENT, Color(0.07, 0.075, 0.07, 0.97), 22.0, UiStyle.BORDER)
	UiStyle.text(ctrl, UiStyle.head_font(800, 6), r.position + Vector2(56, 74), title, UiStyle.FS_H1, UiStyle.ACCENT_SOFT)
	UiStyle.text(ctrl, UiStyle.head_font(600, 3), r.position + Vector2(58, 106), sub, UiStyle.FS_BODY, UiStyle.TEXT_DIM)
	var y := r.position.y + 156.0
	for parts: PackedStringArray in wrapped:
		ctrl.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 60, y - 7), Vector2(r.position.x + 66, y - 13),
			Vector2(r.position.x + 72, y - 7), Vector2(r.position.x + 66, y - 1)]), UiStyle.ACCENT)
		for p in parts:
			UiStyle.text(ctrl, body, Vector2(r.position.x + 88, y), p, UiStyle.FS_LABEL, UiStyle.TEXT_WARM)
			y += 28.0
		y += 12.0
	y += 12.0
	for b: Array in buttons:
		var br := Rect2(r.position.x + 48, y, w - 96.0, 62)
		UiStyle.menu_item(ctrl, br, b[1], _focus_k(b[0]), true, "", false, false, UiStyle.FS_H3 + 4)
		_items.append([br, b[0]])
		y += 70.0
