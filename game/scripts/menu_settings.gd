class_name MenuSettings
extends RefCounted
## Settings screen (UI-01, plan step 2): sections on the left in the «Прицел» style, a
## scrolling list of rows in the centre, a description of the focused row on the right, key
## hints and two buttons at the bottom. Created and drawn by `Menu` while the game is in state
## "settings". Mouse, keyboard and gamepad all work: ↑↓ row, ←→ value, Enter/A toggles or
## starts rebinding, Q/E or the shoulder buttons switch section, Esc/B goes back (saves).
## Options are the same as before step 2; graphics presets and full rebinding come in steps 3–4.

const TABS := ["ИГРА", "ГРАФИКА", "ЗВУК", "УПРАВЛЕНИЕ", "ИНТЕРФЕЙС"]
const TAB_H := 76.0
const TAB_W := 330.0
const ROW_H := 46.0
const SEC_H := 66.0
## Value control width on the right of a row
const CTL_W := 330.0
const DESC_W := 404.0
const LIST_PAD := 36.0

## Row descriptions for the right panel, by row id (bind rows share «bind»)
const DESCS := {
	"damage_numbers": "Цифры урона над целями. В полёте переключается клавишей F3.",
	"scheme": "Как самолёт слушается клавиш и мыши: летит по направлению, поворачивает влево-вправо или следует за курсором.",
	"lang": "Язык меню и подсказок. «Авто» берёт язык системы.",
	"cam_tilt": "Наклон камеры над полем боя. В полёте — клавиша F9.",
	"camera_zoom": "Насколько далеко камера. Меньше — видно больше поля.",
	"plane_len": "Размер вашего самолёта на экране.",
	"unit_scale": "Размер врагов и наземных целей на экране.",
	"shake_mult": "Тряска камеры от взрывов и попаданий. 0 — без тряски.",
	"wipe": "Удаляет ангар, экипажи и запчасти. Отменить нельзя, поэтому нужно нажать два раза.",
	"window_mode": "В окне, без рамки на весь экран или полный экран.",
	"resolution": "Размер окна в режиме «В окне».",
	"vsync": "Убирает разрывы картинки, но может добавить небольшую задержку управления.",
	"fps_limit": "Верхний предел кадров в секунду: меньше нагрев и шум видеокарты.",
	"gfx": "Тени, сглаживание, детали рельефа и растительность разом. Если выбрать вручную, игра перестанет снижать качество сама.",
	"render3d": "Объёмная 3D-картинка. Если выключить, вернётся старая плоская 2D.",
	"sprites": "Картинки самолётов и техники. Если выключить, будут схематичные фигуры (F4).",
	"range_rings": "Пунктирные круги дальности вашего оружия.",
	"hide_hud": "Убирает интерфейс в полёте — для красивых кадров и видео.",
	"font": "Шрифт подсказок и текста интерфейса.",
	"minimap": "Размер миникарты в углу экрана.",
	"minimap_alpha": "Насколько миникарта закрывает поле боя.",
	"master_db": "Громкость всей игры.",
	"music_db": "Громкость музыки.",
	"sfx_db": "Выстрелы, взрывы, попадания.",
	"engine_db": "Гул двигателя вашего самолёта.",
	"ui_db": "Щелчки меню и сигналы интерфейса.",
	"bind": "Нажмите Enter или щёлкните, затем нужную клавишу. Esc — отмена.",
	"reset_binds": "Вернуть все клавиши, как было по умолчанию.",
}

var menu: Menu
var ctrl: Control
var tab := 0
## Clipped child control the list is drawn into (rows scroll under the panel edges)
var list: Control
var _focus := ""
var _tab_anim: Array[float] = [1.0, 0.0, 0.0, 0.0, 0.0]
var _scroll := 0.0
var _content_h := 0.0
## Rows of the current tab, rebuilt every frame: Dictionary {kind, id, label, value, on, sec, y}
var _rows: Array = []
## Mouse targets drawn this frame, in `ctrl` coordinates: [Rect2, kind, id]
var _hits: Array = []
var _drag := ""
var _wipe_t := 0.0
var _saved_t := 0.0
var _want_follow := false


func _init(owner: Menu) -> void:
	menu = owner
	ctrl = owner.ctrl
	list = Control.new()
	list.clip_contents = true
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.visible = false
	ctrl.add_child(list)
	list.draw.connect(_draw_list)


## Back to the first row of the current tab when settings open.
func reset() -> void:
	_focus = ""
	_scroll = 0.0
	_drag = ""


func process(delta: float) -> void:
	_saved_t = maxf(0.0, _saved_t - delta)
	_wipe_t = maxf(0.0, _wipe_t - delta)
	for i in TABS.size():
		_tab_anim[i] = move_toward(_tab_anim[i], 1.0 if i == tab else 0.0, delta / UiStyle.WIPE_S)
	list.queue_redraw()


## Handles one input event; returns true when it was used.
func handle_input(event: InputEvent) -> bool:
	var mp := ctrl.get_local_mouse_position()
	if event is InputEventMouseMotion:
		if _drag != "":
			_drag_to(mp.x)
			return true
		var h := _hit(mp)
		if not h.is_empty() and h[1] != &"tab" and h[1] != &"button":
			_focus = h[2]
		return false
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_scroll += 60.0 * (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				if _drag != "":
					Tuning.save_params()
					_drag = ""
					return true
				return false
			var h := _hit(mp)
			if not h.is_empty():
				_click(h, mp)
				return true
		return false
	if event.is_action_pressed("ui_cancel"):
		menu.close_settings()
		return true
	if _tab_key(event) != 0:
		_set_tab(wrapi(tab + _tab_key(event), 0, TABS.size()))
		return true
	var dir := UiFocus.dir_of(event)
	if dir.y != 0:
		_move(dir.y)
		return true
	if dir.x != 0:
		var r := _row(_focus)
		if not r.is_empty():
			_change(r, dir.x)
		return true
	if event.is_action_pressed("ui_accept"):
		var r := _row(_focus)
		if not r.is_empty():
			_change(r, 0)
		return true
	return false


## Draws the screen; `Menu` has drawn the header line and the shade already.
func draw(size: Vector2) -> void:
	_hits.clear()
	_rows = _build()
	if _row(_focus).is_empty():
		_focus = _first_row()
	# section tabs
	var ts := _tab_size()
	for i in TABS.size():
		var r := Rect2(96, 170 + i * TAB_H, TAB_W, TAB_H - 6.0)
		UiStyle.menu_item(ctrl, r, TABS[i], _tab_anim[i], true, "", false, false, ts)
		_hits.append([r, &"tab", str(i)])
	# list panel
	var lp := Rect2(540, 150, size.x - UiStyle.MARGIN - DESC_W - 32.0 - 540.0, size.y - 112.0 - 150.0)
	UiStyle.panel(ctrl, lp, UiStyle.LINE, Color(0.07, 0.075, 0.07, 0.9), 0.0)
	list.visible = true
	list.position = lp.position + Vector2(LIST_PAD, 12.0)
	list.size = lp.size - Vector2(LIST_PAD * 2.0, 24.0)
	_layout()
	if _want_follow:
		var fr := _row(_focus)
		if not fr.is_empty():
			_scroll = SettingsRows.follow(_scroll, fr["y"], fr["y"] + ROW_H, list.size.y, _content_h, 52.0)
		_want_follow = false
	_scroll = SettingsRows.clamp_scroll(_scroll, list.size.y, _content_h)
	_collect_hits()
	_scrollbar(lp)
	_description(Rect2(size.x - UiStyle.MARGIN - DESC_W, 150, DESC_W, lp.size.y))
	# bottom: hints and buttons
	var hx := float(UiStyle.MARGIN)
	var hy := size.y - 32.0
	hx = UiStyle.key_hint(ctrl, Vector2(hx, hy), "↑↓", Loc.t("ПУНКТ"))
	hx = UiStyle.key_hint(ctrl, Vector2(hx, hy), "←→", Loc.t("ЗНАЧЕНИЕ"))
	hx = UiStyle.key_hint(ctrl, Vector2(hx, hy), "Q E", Loc.t("РАЗДЕЛ"))
	UiStyle.key_hint(ctrl, Vector2(hx, hy), "ESC", Loc.t("НАЗАД"))
	var br := Rect2(size.x - UiStyle.MARGIN - 200.0, size.y - 64.0 - 8.0, 200.0, 52.0)
	_button(br, "ПРИМЕНИТЬ", "save_apply", true)
	_button(Rect2(br.position.x - 24.0 - 250.0, br.position.y, 250.0, 52.0), "ПО УМОЛЧАНИЮ", "reset_all", false)
	if _saved_t > 0.0:
		UiStyle.text(ctrl, UiStyle.head_font(600, 2), Vector2(br.position.x - 274.0, br.position.y - 14.0), "✔ Настройки сохранены",
			UiStyle.FS_BODY, Color(UiStyle.OK, minf(_saved_t, 1.0)))


## Tab label size: 34 px, smaller when the longest translated label would run into the chevron.
func _tab_size() -> int:
	var f := UiStyle.head_font(700)
	var size := 34
	for t: String in TABS:
		while size > UiStyle.FS_H3 and UiStyle.text_w(f, t, size) > TAB_W - 96.0:
			size -= 2
	return size


# ---------- Rows ----------

## Rows of the current tab with their current values; same options as before step 2.
func _build() -> Array:
	var rows: Array = []
	match tab:
		0:
			_sec(rows, "Игра")
			_opt(rows, "scheme", "Схема управления", Loc.t(Hud.SCHEMES[int(Tuning.g("scheme"))]))
			_opt(rows, "lang", "Язык", Settings.lang_name())
			_sec(rows, "Камера и масштаб")
			_opt(rows, "cam_tilt", "Наклон камеры (F9)", MainInput.tilt_name())
			_slider(rows, "camera_zoom", "Масштаб камеры", "%.2f")
			_slider(rows, "plane_len", "Размер самолётов", "%d")
			_slider(rows, "unit_scale", "Размер врагов", "×%.2f")
			_slider(rows, "shake_mult", "Тряска камеры", "×%.1f")
			_sec(rows, "Прогресс")
			rows.append({kind = &"danger", id = "wipe", label = "ТОЧНО? Нажмите ещё раз — профиль (ангар, экипажи) будет удалён"
				if _wipe_t > 0.0 else "Сбросить прогресс (ангар, экипажи, запчасти)"})
		1:
			_sec(rows, "Экран")
			_opt(rows, "window_mode", "Режим окна", Settings.WINDOW_MODES[Settings.window_mode])
			var res: Vector2i = Settings.RESOLUTIONS[Settings.resolution]
			_opt(rows, "resolution", "Размер окна (для режима «В окне»)", "%d × %d" % [res.x, res.y])
			_chk(rows, "vsync", "Вертикальная синхронизация", Settings.vsync)
			var fl: int = Settings.FPS_LIMITS[Settings.fps_limit]
			_opt(rows, "fps_limit", "Ограничение кадров", "без ограничения" if fl == 0 else "%d к/с" % fl)
			_sec(rows, "Картинка")
			_opt(rows, "gfx", "Качество графики", Loc.t(Settings.GFX[Settings.gfx]) + (Loc.t(" (авто)") if Settings.gfx_auto else ""))
			_chk(rows, "render3d", "Объёмная 3D-картинка (выкл. — старая 2D)", Tuning.g("render3d") > 0.5)
			_chk(rows, "sprites", "Спрайты (выкл. — схематичные фигуры, F4)", Tuning.g("sprites") > 0.5)
		2:
			_sec(rows, "Громкость")
			_slider(rows, "master_db", "Общая", "", true)
			_slider(rows, "music_db", "Музыка", "", true)
			_slider(rows, "sfx_db", "Эффекты", "", true)
			_slider(rows, "engine_db", "Двигатель", "", true)
			_slider(rows, "ui_db", "Интерфейс", "", true)
		3:
			var sec := ""
			for rb: Array in Settings.REBIND:
				if rb[2] != sec:
					sec = rb[2]
					_sec(rows, sec)
				rows.append({kind = &"bind", id = String(rb[0]), label = rb[1],
					value = "нажмите клавишу…" if menu.capturing == rb[0] else Settings.key_name(rb[0])})
			_sec(rows, "Мышь и геймпад")
			rows.append({kind = &"note", id = "", label = "Мышь: левая кнопка — огонь из пушки, правая — ракеты и бомбы вручную. Геймпад — стандартная раскладка. Esc — отменить ввод."})
			rows.append({kind = &"button", id = "reset_binds", label = "СБРОСИТЬ КЛАВИШИ"})
		4:
			_sec(rows, "Интерфейс в полёте")
			_chk(rows, "damage_numbers", "Показывать цифры урона (F3)", Tuning.g("damage_numbers") > 0.5)
			_chk(rows, "hide_hud", "Скрыть интерфейс в полёте", Settings.hide_hud)
			_chk(rows, "range_rings", "Круги дальности оружия (пунктир)", Tuning.g("range_rings") > 0.5)
			_opt(rows, "font", "Шрифт интерфейса", Settings.FONTS[Settings.font])
			_sec(rows, "Миникарта")
			_opt(rows, "minimap", "Миникарта", Settings.MINIMAP_NAMES[Settings.minimap])
			_opt(rows, "minimap_alpha", "Прозрачность миникарты", "%d%%" % int(Settings.MINIMAP_ALPHA[Settings.minimap_alpha] * 100.0))
	return rows


func _sec(rows: Array, title: String) -> void:
	rows.append({kind = &"sec", id = "", label = title})


func _opt(rows: Array, id: String, label: String, value: String) -> void:
	rows.append({kind = &"opt", id = id, label = label, value = value})


func _chk(rows: Array, id: String, label: String, on: bool) -> void:
	rows.append({kind = &"chk", id = id, label = label, on = on})


## Slider over a Tuning parameter. `fmt` formats the value; `volume` shows 0–100 % instead.
func _slider(rows: Array, id: String, label: String, fmt: String, volume := false) -> void:
	var rg: Array = Tuning.RANGES[id]
	var v := Tuning.g(id)
	var k := clampf((v - float(rg[0])) / (float(rg[1]) - float(rg[0])), 0.0, 1.0)
	var shown: String
	if volume:
		shown = Loc.t("выкл.") if k <= 0.001 else "%d%%" % int(round(k * 100.0))
	else:
		shown = fmt % v
	rows.append({kind = &"slider", id = id, label = label, value = shown, k = k})


## Content y of every row (sections take more room than rows); sets `_content_h`.
func _layout() -> void:
	var y := 0.0
	for r: Dictionary in _rows:
		if r["kind"] == &"sec":
			if y > 0.0:
				y += 14.0
			r["y"] = y
			y += SEC_H - 14.0
		elif r["kind"] == &"note":
			r["lines"] = menu.wrap(Loc.t(r["label"]), list.size.x - 24.0, UiStyle.FS_BODY)
			r["y"] = y
			y += 24.0 * r["lines"].size() + 16.0
		else:
			r["y"] = y
			y += ROW_H
	_content_h = y + 12.0


func _focusable(r: Dictionary) -> bool:
	return not (r["kind"] in [&"sec", &"note"])


func _row(id: String) -> Dictionary:
	if id == "":
		return {}
	for r: Dictionary in _rows:
		if _focusable(r) and r["id"] == id:
			return r
	return {}


func _first_row() -> String:
	for r: Dictionary in _rows:
		if _focusable(r):
			return r["id"]
	return ""


func _move(d: int) -> void:
	var ids: Array[String] = []
	for r: Dictionary in _rows:
		if _focusable(r):
			ids.append(r["id"])
	if ids.is_empty():
		return
	var i := ids.find(_focus)
	var j := clampi(i + d, 0, ids.size() - 1) if i >= 0 else 0
	if ids[j] != _focus:
		_focus = ids[j]
		_want_follow = true
		Main.I.sfx.play("card", -24.0 + Tuning.g("ui_db"), 1.6)


func _set_tab(i: int) -> void:
	if i == tab:
		return
	tab = i
	_focus = ""
	_scroll = 0.0
	_wipe_t = 0.0
	Main.I.sfx.play("card", -20.0 + Tuning.g("ui_db"), 1.4)


## -1 / +1 for the section-switch keys (Q/E, gamepad shoulders), 0 otherwise.
func _tab_key(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			return -1
		if event.physical_keycode == KEY_E:
			return 1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			return -1
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			return 1
	return 0


# ---------- Changing values ----------

## Applies one press to a row: `dir` −1/+1 from ←→ or a click on a side, 0 from Enter/A.
func _change(r: Dictionary, dir: int) -> void:
	var id: String = r["id"]
	match r["kind"]:
		&"opt":
			_option(id, dir if dir != 0 else 1)
		&"chk":
			if dir == 0 or (dir > 0) != r["on"]:
				_toggle(id)
		&"slider":
			if dir == 0:
				return
			var rg: Array = Tuning.RANGES[id]
			_set_param(id, SettingsRows.step_value(Tuning.g(id), float(rg[0]), float(rg[1]), float(rg[2]), dir))
			Tuning.save_params()
		&"bind":
			if dir == 0:
				menu.capturing = id
		&"button":
			if dir == 0:
				Settings.reset_binds()
		&"danger":
			if dir == 0:
				if _wipe_t > 0.0:
					Profile.wipe()
					_wipe_t = 0.0
				else:
					_wipe_t = 3.0
	Main.I.sfx.play("card", -16.0 + Tuning.g("ui_db"), 1.3)


func _set_param(key: String, v: float) -> void:
	Tuning.set_param(key, v)
	if key == "master_db":
		Settings.apply_audio()
	elif key == "music_db":
		Main.I.sfx.apply_music_volume()


func _drag_to(x: float) -> void:
	for h: Array in _hits:
		if h[1] == &"track" and h[2] == _drag:
			var tr: Rect2 = h[0]
			var rg: Array = Tuning.RANGES[_drag]
			var k := clampf((x - tr.position.x) / tr.size.x, 0.0, 1.0)
			_set_param(_drag, snappedf(lerpf(float(rg[0]), float(rg[1]), k), float(rg[2])))
			return


func _toggle(key: String) -> void:
	match key:
		"hide_hud":
			Settings.hide_hud = not Settings.hide_hud
		"vsync":
			Settings.vsync = not Settings.vsync
			Settings.apply()
		_:
			Tuning.set_param(key, 1.0 - Tuning.g(key))
			Tuning.save_params()
	Settings.save_settings()


func _option(key: String, dir: int) -> void:
	match key:
		"window_mode":
			Settings.window_mode = wrapi(Settings.window_mode + dir, 0, Settings.WINDOW_MODES.size())
			Settings.apply()
		"resolution":
			Settings.resolution = wrapi(Settings.resolution + dir, 0, Settings.RESOLUTIONS.size())
			Settings.apply()
		"fps_limit":
			Settings.fps_limit = wrapi(Settings.fps_limit + dir, 0, Settings.FPS_LIMITS.size())
			Settings.apply()
		"scheme":
			Tuning.set_param("scheme", float(wrapi(int(Tuning.g("scheme")) + dir, 0, 3)))
			Tuning.save_params()
		"cam_tilt":
			Main.I.input_ctl.cycle_tilt(dir)
		"minimap":
			Settings.minimap = wrapi(Settings.minimap + dir, 0, Settings.MINIMAP_SIZES.size())
		"minimap_alpha":
			Settings.minimap_alpha = wrapi(Settings.minimap_alpha + dir, 0, Settings.MINIMAP_ALPHA.size())
		"lang":
			# cycles auto → Russian → English → Chinese → auto
			Settings.lang = wrapi(Settings.lang + dir, -1, Settings.LANGS.size())
			Settings.apply_lang()
		"font":
			Settings.font = wrapi(Settings.font + dir, 0, Settings.FONTS.size())
			Hud.reset_fonts()
		"gfx":
			Settings.gfx = wrapi(Settings.gfx + dir, 0, Settings.GFX_MAX + 1)
			Settings.gfx_auto = false   # picked by hand: auto-lowering stops touching it
			Settings.apply_gfx()
	Settings.save_settings()


# ---------- Mouse ----------

## Topmost target under the mouse (searched from the end: drawn last gets the click).
func _hit(mp: Vector2) -> Array:
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i][0] as Rect2).has_point(mp):
			return _hits[i]
	return []


func _click(h: Array, mp: Vector2) -> void:
	var kind: StringName = h[1]
	var id: String = h[2]
	match kind:
		&"tab":
			_set_tab(int(id))
		&"button":
			Main.I.sfx.play("card", -16.0 + Tuning.g("ui_db"), 1.3)
			if id == "save_apply":
				Tuning.save_params()
				Settings.apply()
				Settings.save_settings()
				_saved_t = 2.0
			elif id == "reset_all":
				Tuning.reset()
				Tuning.save_params()
				Settings.apply_audio()
				Main.I.sfx.apply_music_volume()
		&"track":
			_focus = id
			_drag = id
			_drag_to(mp.x)
		&"row":
			_focus = id
			var r := _row(id)
			if r.is_empty():
				return
			var ctl := _ctl_rect(h[0])
			match r["kind"]:
				&"opt":
					if ctl.has_point(mp):
						_change(r, 1 if mp.x > ctl.get_center().x else -1)
				&"chk":
					if ctl.has_point(mp):
						_change(r, 1 if mp.x > ctl.get_center().x else -1)
					else:
						_change(r, 0)
				&"bind":
					if ctl.has_point(mp):
						_change(r, 0)
				&"button", &"danger":
					_change(r, 0)


## Value control rect at the right end of a row rect.
func _ctl_rect(row: Rect2) -> Rect2:
	return Rect2(row.end.x - CTL_W - 14.0, row.position.y + 4.0, CTL_W, row.size.y - 8.0)


## Row and slider-track targets of the visible rows, in `ctrl` coordinates.
func _collect_hits() -> void:
	var view := Rect2(list.position, list.size)
	for r: Dictionary in _rows:
		if not _focusable(r):
			continue
		var rr := Rect2(list.position.x, list.position.y + r["y"] - _scroll, list.size.x, ROW_H)
		if not view.intersects(rr):
			continue
		_hits.append([rr.intersection(view), &"row", r["id"]])
		if r["kind"] == &"slider":
			var tr := _track_rect(_ctl_rect(rr))
			if view.has_point(tr.get_center()):
				_hits.append([tr.grow_individual(10, 14, 10, 14), &"track", r["id"]])


func _track_rect(ctl: Rect2) -> Rect2:
	return Rect2(ctl.position.x + 8.0, ctl.get_center().y - 3.0, ctl.size.x - 100.0, 6.0)


# ---------- Drawing ----------

## Draws the rows into the clipped `list` control (its own coordinates, shifted by the scroll).
func _draw_list() -> void:
	if not list.visible:
		return
	var w := list.size.x
	var body := Hud.ui_font()
	var bold := Menu.bold()
	for r: Dictionary in _rows:
		var y: float = r["y"] - _scroll
		if y > list.size.y or y + SEC_H < 0.0:
			continue
		var kind: StringName = r["kind"]
		if kind == &"sec":
			UiStyle.text(list, UiStyle.head_font(800, 4), Vector2(0, y + 34), Loc.t(r["label"]).to_upper(), UiStyle.FS_LABEL + 2, UiStyle.ACCENT)
			list.draw_line(Vector2(0, y + 46), Vector2(w, y + 46), UiStyle.LINE, 1.0)
			continue
		if kind == &"note":
			var ly := y + 18.0
			for line: String in r["lines"]:
				list.draw_string(body, Vector2(14, ly), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_BODY, UiStyle.TEXT_DIM)
				ly += 24.0
			continue
		var rr := Rect2(0, y, w, ROW_H)
		var on: bool = r["id"] == _focus
		var danger := kind == &"danger"
		if on:
			var c := UiStyle.DANGER if danger else UiStyle.ACCENT
			list.draw_rect(rr, Color(c.r, c.g, c.b, 0.22))
			list.draw_rect(Rect2(0, y, 4, ROW_H), c)
		elif danger:
			list.draw_rect(rr, Color(UiStyle.DANGER.r, UiStyle.DANGER.g, UiStyle.DANGER.b, 0.1))
		var lc := UiStyle.TEXT_WARM
		if kind == &"button":
			UiStyle.text(list, UiStyle.head_font(700, 3), Vector2(14, y + 30), r["label"], UiStyle.FS_BODY, UiStyle.ACCENT if on else lc)
			UiStyle.text(list, UiStyle.head_font(700, 3), Vector2(w - 40, y + 30), "›", UiStyle.FS_LABEL, UiStyle.ACCENT if on else lc)
			continue
		var lw := w - CTL_W - 48.0 if kind != &"danger" else w - 28.0
		UiStyle.text(list, body, Vector2(14, y + 30), r["label"], _fit(body, r["label"], UiStyle.FS_LABEL, lw), lc)
		var ctl := _ctl_rect(rr)
		match kind:
			&"opt", &"bind":
				var capt: bool = kind == &"bind" and menu.capturing == r["id"]
				list.draw_rect(ctl, UiStyle.ACCENT if (on or capt) else Color(0.03, 0.035, 0.03, 0.7))
				var tc := UiStyle.ON_ACCENT if (on or capt) else UiStyle.TEXT_WARM
				if kind == &"opt":
					UiStyle.text(list, bold, Vector2(ctl.position.x + 14, y + 30), "‹", UiStyle.FS_LABEL, tc)
					UiStyle.text(list, bold, Vector2(ctl.end.x - 24, y + 30), "›", UiStyle.FS_LABEL, tc)
				UiStyle.text(list, bold, Vector2(ctl.position.x + 30, y + 30), r["value"],
					_fit(bold, r["value"], UiStyle.FS_BODY + 1, ctl.size.x - 64.0), tc, HORIZONTAL_ALIGNMENT_CENTER, ctl.size.x - 60.0)
			&"chk":
				var half := ctl.size.x * 0.5
				for s in 2:
					var sr := Rect2(ctl.position.x + s * half, ctl.position.y, half, ctl.size.y)
					var lit := (s == 1) == bool(r["on"])
					list.draw_rect(sr, Color(0.03, 0.035, 0.03, 0.7))
					if lit:
						list.draw_rect(sr, Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 1.0 if on else 0.28))
						list.draw_rect(Rect2(sr.position.x, sr.end.y - 3.0, sr.size.x, 3.0), UiStyle.ACCENT)
					var sc := (UiStyle.ON_ACCENT if on else UiStyle.ACCENT_SOFT) if lit else UiStyle.TEXT_DIM
					UiStyle.text(list, UiStyle.head_font(700, 3), Vector2(sr.position.x, y + 30), "ВКЛ" if s == 1 else "ВЫКЛ",
						UiStyle.FS_CAPTION + 1, sc, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
			&"slider":
				var tr := _track_rect(ctl)
				var k: float = r["k"]
				list.draw_rect(tr, Color(UiStyle.TEXT_WARM.r, UiStyle.TEXT_WARM.g, UiStyle.TEXT_WARM.b, 0.2))
				list.draw_rect(Rect2(tr.position, Vector2(tr.size.x * k, tr.size.y)), UiStyle.ACCENT)
				var kx := tr.position.x + tr.size.x * k
				list.draw_rect(Rect2(kx - 4.0, tr.get_center().y - 11.0, 8.0, 22.0), UiStyle.TEXT_WARM if not on else UiStyle.ACCENT_SOFT)
				UiStyle.text(list, bold, Vector2(tr.end.x + 12.0, y + 30), r["value"], UiStyle.FS_BODY + 1,
					UiStyle.ACCENT_SOFT if on else UiStyle.TEXT_WARM, HORIZONTAL_ALIGNMENT_RIGHT, ctl.end.x - tr.end.x - 12.0)


## Largest size from `size` down to FS_MIN at which `s` fits in `w` (long translations).
func _fit(font: Font, s: String, size: int, w: float) -> int:
	while size > UiStyle.FS_MIN and UiStyle.text_w(font, s, size) > w:
		size -= 1
	return size


func _scrollbar(lp: Rect2) -> void:
	if _content_h <= list.size.y:
		return
	var track := Rect2(lp.end.x - 14.0, lp.position.y + 24.0, 3.0, lp.size.y - 48.0)
	ctrl.draw_rect(track, Color(UiStyle.TEXT_WARM.r, UiStyle.TEXT_WARM.g, UiStyle.TEXT_WARM.b, 0.12))
	var h := track.size.y * list.size.y / _content_h
	var t := (track.size.y - h) * _scroll / (_content_h - list.size.y)
	ctrl.draw_rect(Rect2(track.position.x, track.position.y + t, track.size.x, h), UiStyle.TEXT_DIM)


## Right panel: name of the focused row, its section and what it does.
func _description(r: Rect2) -> void:
	UiStyle.panel(ctrl, r, UiStyle.LINE, Color(0.07, 0.075, 0.07, 0.9))
	var row := _row(_focus)
	if row.is_empty():
		return
	var x := r.position.x + 28.0
	var w := r.size.x - 56.0
	var title: String = Loc.t(row["label"])
	var hf := UiStyle.head_font(700, 2)
	var y := r.position.y + 50.0
	for line in menu.wrap(title, w, UiStyle.FS_H3 + 4, hf):
		ctrl.draw_string(hf, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_H3 + 4, UiStyle.TEXT_WARM)
		y += 34.0
	# section chip
	var sec := Loc.t(_section_of(row)).to_upper()
	if sec != "":
		var cf := UiStyle.head_font(700, 3)
		var cw := UiStyle.text_w(cf, sec, UiStyle.FS_CAPTION) + 20.0
		var cr := Rect2(x, y - 8.0, cw, 26.0)
		ctrl.draw_rect(cr, UiStyle.ACCENT, false, 1.5)
		UiStyle.text(ctrl, cf, Vector2(x, y + 11.0), sec, UiStyle.FS_CAPTION, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, cw)
		y += 52.0
	var key: String = "bind" if row["kind"] == &"bind" else row["id"]
	var desc: String = DESCS.get(key, "")
	if desc != "":
		var body := Hud.ui_font()
		for line in menu.wrap(Loc.t(desc), w, UiStyle.FS_BODY + 1):
			ctrl.draw_string(body, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_BODY + 1, UiStyle.TEXT_2)
			y += 26.0


func _section_of(row: Dictionary) -> String:
	var sec := ""
	for r: Dictionary in _rows:
		if r["kind"] == &"sec":
			sec = r["label"]
		if r == row:
			return sec
	return ""


## Bottom button: slanted plate; `primary` is filled amber, the other one outlined.
func _button(r: Rect2, label: String, id: String, primary: bool) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	var s := 16.0
	var pts := PackedVector2Array([Vector2(r.position.x + s, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x - s, r.end.y), Vector2(r.position.x, r.end.y)])
	var fill := UiStyle.ACCENT.lightened(0.12 if hover else 0.0) if primary else Color(0.05, 0.055, 0.05, 0.9)
	ctrl.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ctrl.draw_polyline(pts, UiStyle.ACCENT if (hover or primary) else UiStyle.LINE, 1.5)
	UiStyle.text(ctrl, UiStyle.head_font(800, 4), Vector2(r.position.x, r.position.y + 34.0), label, UiStyle.FS_LABEL,
		UiStyle.ON_ACCENT if primary else (UiStyle.ACCENT if hover else UiStyle.TEXT_WARM), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_hits.append([r, &"button", id])
