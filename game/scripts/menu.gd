class_name Menu
extends CanvasLayer
## Главное меню и настройки (2.8). Свой стиль Flak Heaven — «приборная панель»:
## графит, янтарная подсветка шкал, красные метки как на вражеских машинах, трафаретные заголовки.
## За меню — живой биом с медленно плывущей камерой и звено самолётов на переднем плане.

const C_BG := Color(0.07, 0.08, 0.07, 0.92)
const C_PANEL := Color(0.11, 0.12, 0.105, 0.94)
const C_LINE := Color(0.85, 0.82, 0.72, 0.22)
const C_TEXT := Color(0.92, 0.9, 0.84)
const C_DIM := Color(0.62, 0.62, 0.56)
const C_AMBER := Color(0.95, 0.66, 0.2)
const C_AMBER_D := Color(0.55, 0.36, 0.1)
const C_RED := Color(0.85, 0.24, 0.18)
const TABS := ["ИГРА", "ГРАФИКА", "ЗВУК", "УПРАВЛЕНИЕ"]
const HOWTO_FLAG := "user://howto_seen"
var howto := false

static var _bold: Font

var ctrl: Control
var tab := 0
var back_state := "menu"
var capturing := ""        # действие, ждущее новую клавишу
var _buttons: Array = []   # [Rect2, action]
var _sliders: Array = []   # [Rect2, key, min, max]
var _drag := ""
var _t := 0.0
var _saved_t := 0.0
var records := {}


static func bold() -> Font:
	if _bold == null:
		_bold = Hud.make_font(true)
	return _bold


var _wipe_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	ctrl = Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ctrl)
	ctrl.draw.connect(_draw_menu)
	load_records()
	howto = false # U-03: при первом запуске вместо экрана «Как играть» — подсказки по ходу первого вылета


func active() -> bool:
	return Main.I != null and Main.I.state in ["menu", "settings"]


func _process(delta: float) -> void:
	_t += delta
	_saved_t = maxf(0.0, _saved_t - delta)
	_wipe_t = maxf(0.0, _wipe_t - delta)
	ctrl.visible = active()
	if ctrl.visible:
		ctrl.queue_redraw()


# ---------- Ввод ----------

func _input(event: InputEvent) -> void:
	if not active():
		return
	var m := Main.I
	if capturing != "":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode != KEY_ESCAPE:
				Settings.rebind(capturing, event.physical_keycode)
			capturing = ""
			get_viewport().set_input_as_handled()
		return
	if howto and m.state == "menu" and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		close_howto()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if m.state == "settings":
				close_settings()
		elif event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and m.state == "menu":
			get_viewport().set_input_as_handled()
			m.ui_click("menu_play")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := ctrl.get_local_mouse_position()
		if event.pressed:
			for s in _sliders:
				if (s[0] as Rect2).grow(8.0).has_point(mp):
					_drag = s[1]
					_set_slider(s, mp.x)
					get_viewport().set_input_as_handled()
					return
			for b in _buttons:
				if (b[0] as Rect2).has_point(mp):
					get_viewport().set_input_as_handled()
					_click(b[1], mp, b[0])
					return
		else:
			if _drag != "":
				Tuning.save_params()
			_drag = ""
	if event is InputEventMouseMotion and _drag != "":
		for s in _sliders:
			if s[1] == _drag:
				_set_slider(s, ctrl.get_local_mouse_position().x)


func _set_slider(s: Array, x: float) -> void:
	var r: Rect2 = s[0]
	var k := clampf((x - r.position.x) / r.size.x, 0.0, 1.0)
	var key: String = s[1]
	var step: float = Tuning.RANGES[key][2]
	var v := lerpf(float(s[2]), float(s[3]), k)
	v = snappedf(v, step)
	Tuning.set_param(key, v)
	if key == "master_db":
		Settings.apply_audio()
	elif key == "music_db":
		Main.I.sfx.apply_music_volume()


func _click(action: String, mp: Vector2, r: Rect2) -> void:
	var m := Main.I
	m.sfx.play("card", -16.0 + Tuning.g("ui_db"), 1.3)
	var right := mp.x > r.get_center().x
	match action:
		"settings_back":
			close_settings()
		"reset_binds":
			Settings.reset_binds()
		"save_apply":
			Tuning.save_params()
			Settings.apply()
			Settings.save_settings()
			_saved_t = 2.0
		"wipe":
			if _wipe_t > 0.0:
				Profile.wipe()
				_wipe_t = 0.0
			else:
				_wipe_t = 3.0
		"howto_close":
			close_howto()
		"hints_reset":
			Hints.reset()
			_saved_t = 2.0
		"reset_all":
			Tuning.reset()
			Tuning.save_params()
			Settings.apply_audio()
		_:
			if action.begins_with("tab:"):
				tab = int(action.substr(4))
			elif action.begins_with("bind:"):
				capturing = action.substr(5)
			elif action.begins_with("chk:"):
				_toggle(action.substr(4))
			elif action.begins_with("opt:"):
				_option(action.substr(4), 1 if right else -1)
			else:
				m.ui_click(action)


func open_settings(from: String) -> void:
	back_state = from
	Main.I._set_state("settings")


func close_settings() -> void:
	Tuning.save_params()
	Settings.save_settings()
	capturing = ""
	Main.I._set_state(back_state)


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
		"font":
			Settings.font = wrapi(Settings.font + dir, 0, Settings.FONTS.size())
			Hud.reset_fonts()
		"gfx":
			Settings.gfx = wrapi(Settings.gfx + dir, 0, Settings.GFX_MAX + 1)
			Settings.gfx_auto = false   # выбрал сам — автоснижение больше не трогает
			Settings.apply_gfx()
	Settings.save_settings()


# ---------- Журнал полётов (рекорды) ----------

const RECORDS := "user://records.json"


func load_records() -> void:
	records = {"sorties": 0, "evacs": 0, "best_time": 0.0, "best_level": 0, "best_kills": 0, "last": []}
	if FileAccess.file_exists(RECORDS):
		var f := FileAccess.open(RECORDS, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary:
				records.merge(d, true)


func add_record(cls_title: String, outcome: String, t: float, lvl: int, kills: int) -> void:
	records["sorties"] = int(records["sorties"]) + 1
	if outcome == "эвакуация":
		records["evacs"] = int(records["evacs"]) + 1
	records["best_time"] = maxf(float(records["best_time"]), t)
	records["best_level"] = maxi(int(records["best_level"]), lvl)
	records["best_kills"] = maxi(int(records["best_kills"]), kills)
	var last: Array = records["last"]
	last.push_front({"c": cls_title, "o": outcome, "t": t, "l": lvl, "k": kills})
	records["last"] = last.slice(0, 7)
	var f := FileAccess.open(RECORDS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(records, "  "))
		f.close()


# ---------- Примитивы стиля ----------

func _txt(pos: Vector2, s: String, size := 20, color := C_TEXT, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ctrl.draw_string(font if font else Hud.ui_font(), pos, TranslationServer.translate(s), align, width, size, color)


## Панель со срезанным углом и «заклёпками»
func _panel(r: Rect2, accent := C_LINE, fill := C_PANEL, cut := 18.0) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut), r.end,
		Vector2(r.position.x, r.end.y)])
	ctrl.draw_colored_polygon(pts, fill)
	pts.append(r.position)
	ctrl.draw_polyline(pts, accent, 1.5)
	for c in [r.position + Vector2(8, 8), Vector2(r.position.x + 8, r.end.y - 8), r.end - Vector2(8, 8)]:
		ctrl.draw_circle(c, 2.0, Color(accent.r, accent.g, accent.b, 0.6))


## Кнопка главного меню: янтарная при наведении, слева — полоса-индикатор
func _menu_button(r: Rect2, label: String, action: String, primary := false, enabled := true, note := "") -> void:
	var hover := enabled and r.has_point(ctrl.get_local_mouse_position())
	var cut := 22.0
	var pts := PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut), r.end, Vector2(r.position.x, r.end.y)])
	if primary or hover:
		ctrl.draw_colored_polygon(pts, C_AMBER if (hover or primary) else C_PANEL)
		if primary and not hover:
			ctrl.draw_colored_polygon(pts, Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, 0.85))
	else:
		ctrl.draw_colored_polygon(pts, Color(0.1, 0.11, 0.1, 0.75))
	ctrl.draw_rect(Rect2(r.position.x, r.position.y, 6, r.size.y), C_RED if enabled else C_DIM)
	var tc := Color(0.08, 0.07, 0.05) if (hover or primary) else (C_TEXT if enabled else C_DIM)
	var fs := 34 if r.size.x > 400.0 else 26
	_txt(Vector2(r.position.x + 34, r.position.y + r.size.y * 0.66), label, fs, tc, bold())
	if fs == 34:
		_txt(Vector2(r.end.x - 50, r.position.y + r.size.y * 0.66), "›", fs, tc, bold())
	if note != "":
		_txt(Vector2(r.position.x + 34, r.end.y + 20), note, 15, C_DIM)
	if enabled:
		_buttons.append([r, action])


## Линейка-шкала (как на приборе) — декор
func _ruler(x: float, y: float, w: float) -> void:
	ctrl.draw_line(Vector2(x, y), Vector2(x + w, y), C_LINE, 1.0)
	var i := 0
	var step := 12.0
	var xx := x
	while xx < x + w:
		var h := 10.0 if i % 5 == 0 else 5.0
		ctrl.draw_line(Vector2(xx, y), Vector2(xx, y - h), C_LINE, 1.0)
		xx += step
		i += 1


# ---------- Отрисовка ----------

func _draw_menu() -> void:
	_buttons.clear()
	_sliders.clear()
	var m := Main.I
	if m == null:
		return
	var size := ctrl.size
	# затемнение слева — читаемость кнопок; справа видно биом и звено
	var grad_w := size.x * 0.55
	var steps := int(grad_w / 4.0)
	for i in steps:
		var a := 0.75 * (1.0 - float(i) / steps)
		ctrl.draw_rect(Rect2(grad_w * i / steps, 0, grad_w / steps + 1.0, size.y), Color(0.04, 0.045, 0.04, a))
	ctrl.draw_rect(Rect2(0, 0, size.x, 96), Color(0.04, 0.045, 0.04, 0.7))
	_txt(Vector2(64, 58), "◇ FLAK HEAVEN  //  " + ("ГЛАВНЫЙ ТЕРМИНАЛ" if m.state == "menu" else "НАСТРОЙКИ"), 22, C_TEXT, bold())
	# С-5: номер версии — из BUILD (main.gd), а не отдельной устаревшей строкой
	_txt(Vector2(size.x - 64 - 800, 58), "ВЕРСИЯ: " + Main.BUILD, 20, C_DIM, bold(), HORIZONTAL_ALIGNMENT_RIGHT, 800)
	ctrl.draw_line(Vector2(64, 96), Vector2(size.x - 64, 96), C_LINE, 1.0)
	ctrl.draw_line(Vector2(64, size.y - 70), Vector2(size.x - 64, size.y - 70), C_LINE, 1.0)
	if m.state == "menu":
		_main(m, size)
		if howto:
			_howto(size)
	else:
		_settings(size)


func _main(m: Main, size: Vector2) -> void:
	# звено на заставке — 3D-модели в сцене (TitleFlight) на любом качестве графики; старые картинки
	# art/planes (другая форма и окраска) больше не рисуются (С-5, аудит 3.5-s6)
	# Заголовок
	_txt(Vector2(100, 290), "FLAK", 150, C_TEXT, bold())
	_txt(Vector2(100, 430), "HEAVEN", 150, C_AMBER, bold())
	for i in 14:
		var x := 106.0 + i * 26.0
		ctrl.draw_colored_polygon(PackedVector2Array([Vector2(x, 462), Vector2(x + 14, 462), Vector2(x + 6, 476), Vector2(x - 8, 476)]), C_RED)
	_txt(Vector2(106, 512), "Авиа-roguelike: 15 минут вылета, звено, подвесы и асы", 20, C_DIM)
	var x0 := 96.0
	var y := 600.0
	_menu_button(Rect2(x0, y, 560, 78), "ВЫЛЕТ", "menu_play", true)
	_menu_button(Rect2(x0, y + 96, 560, 62), "СПРАВОЧНИК", "menu_codex")
	_menu_button(Rect2(x0, y + 172, 560, 62), "АНГАР" + ("  !" if Profile.any_purchase() else ""), "menu_hangar", false, true,
		"Запчасти: %d · экипажи: Оса %d · Грач %d · Кит %d" % [Profile.parts(), Profile.crew_lvl("fighter"), Profile.crew_lvl("attacker"), Profile.crew_lvl("bomber")])
	_menu_button(Rect2(x0, y + 256, 272, 62), "НАСТРОЙКИ", "menu_settings")
	_menu_button(Rect2(x0 + 288, y + 256, 272, 62), "КАК ИГРАТЬ", "menu_howto")
	_menu_button(Rect2(x0, y + 336, 272, 62), "ЛОГИ", "menu_logs")
	_menu_button(Rect2(x0 + 288, y + 336, 272, 62), "ВЫХОД", "menu_quit")
	_records_panel(Rect2(size.x - 64 - 520, 150, 520, 520))
	_txt(Vector2(64, size.y - 32), "ENTER — вылет    ESC — назад    F2 — схема управления", 18, C_DIM)


func _records_panel(r: Rect2) -> void:
	_panel(r)
	_txt(r.position + Vector2(28, 44), "ЖУРНАЛ ПОЛЁТОВ", 28, C_TEXT, bold())
	_txt(r.position + Vector2(28, 72), "лучшие результаты на этом компьютере", 15, C_DIM)
	var y := r.position.y + 120.0
	var bt := float(records["best_time"])
	var rows := [["Вылетов", str(int(records["sorties"]))], ["Эвакуаций", str(int(records["evacs"]))],
		["Дольше всего в воздухе", "%d:%02d" % [int(bt / 60.0), int(bt) % 60]], ["Лучший уровень пилота", str(int(records["best_level"]))],
		["Больше всего сбито", str(int(records["best_kills"]))]]
	for row in rows:
		_txt(Vector2(r.position.x + 28, y), row[0], 19, C_DIM)
		_txt(Vector2(r.position.x + 28, y), row[1], 21, C_AMBER, bold(), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 56)
		y += 34.0
	y += 10.0
	_ruler(r.position.x + 28, y, r.size.x - 56)
	y += 34.0
	_txt(Vector2(r.position.x + 28, y), "ПОСЛЕДНИЕ ВЫЛЕТЫ", 17, C_TEXT, bold())
	y += 30.0
	var last: Array = records["last"]
	if last.is_empty():
		_txt(Vector2(r.position.x + 28, y), "пока пусто — самое время на взлёт", 17, C_DIM)
	for e in last.slice(0, 6):
		var ok: bool = e["o"] == "эвакуация"
		var tt := float(e["t"])
		_txt(Vector2(r.position.x + 28, y), "%s" % e["c"], 17, C_TEXT)
		_txt(Vector2(r.position.x + 230, y), "%d:%02d · ур. %d · %d сбито" % [int(tt / 60.0), int(tt) % 60, int(e["l"]), int(e["k"])], 16, C_DIM)
		_txt(Vector2(r.position.x + 28, y), "✔" if ok else "✖", 18, Color(0.5, 0.9, 0.5) if ok else C_RED, null, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 56)
		y += 27.0


# ---------- Настройки ----------

func _settings(size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.03, 0.55))
	# вкладки
	var tx := 460.0
	for i in TABS.size():
		var label: String = TABS[i]
		var w := 250.0
		var r := Rect2(tx, 112, w, 56)
		var on := i == tab
		var pts := PackedVector2Array([Vector2(r.position.x + 14, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x - 14, r.end.y), Vector2(r.position.x, r.end.y)])
		if on:
			ctrl.draw_colored_polygon(pts, C_AMBER)
		elif r.has_point(ctrl.get_local_mouse_position()):
			ctrl.draw_colored_polygon(pts, Color(1, 1, 1, 0.06))
		_txt(Vector2(r.position.x, r.position.y + 37), label, 21, Color(0.08, 0.07, 0.05) if on else C_TEXT, bold(), HORIZONTAL_ALIGNMENT_CENTER, w)
		_buttons.append([r, "tab:%d" % i])
		tx += w + 8.0
	var panel := Rect2(360, 190, size.x - 720, size.y - 330)
	_panel(panel, Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, 0.45), Color(0.08, 0.09, 0.08, 0.96))
	var x := panel.position.x + 60
	var w2 := panel.size.x - 120
	var y := panel.position.y + 70
	match tab:
		0:
			y = _section(x, y, w2, "Игра")
			y = _check(x, y, w2, "Показывать цифры урона (F3)", Tuning.g("damage_numbers") > 0.5, "damage_numbers")
			y = _check(x, y, w2, "Скрыть интерфейс в полёте", Settings.hide_hud, "hide_hud")
			y = _opt(x, y, w2, "Схема управления", Hud.SCHEMES[int(Tuning.g("scheme"))], "scheme")
			y = _opt(x, y, w2, "Язык", "Русский", "lang")
			y = _opt(x, y, w2, "Шрифт интерфейса", Settings.FONTS[Settings.font], "font")
			y = _section(x, y + 10, w2, "Камера и масштаб")
			y = _opt(x, y, w2, "Наклон камеры (F9)", MainInput.tilt_name(), "cam_tilt")
			y = _slider(x, y, w2, "Масштаб камеры", "camera_zoom", "%.2f")
			y = _slider(x, y, w2, "Размер самолётов", "plane_len", "%d")
			y = _slider(x, y, w2, "Размер врагов", "unit_scale", "×%.2f")
			y = _slider(x, y, w2, "Тряска камеры", "shake_mult", "×%.1f")
			y = _section(x, y + 10, w2, "Прогресс")
			var wr := Rect2(x, y, w2, 46)
			var hv := wr.has_point(ctrl.get_local_mouse_position())
			ctrl.draw_rect(wr, Color(C_RED.r, C_RED.g, C_RED.b, 0.35 if (hv or _wipe_t > 0.0) else 0.15))
			_txt(Vector2(x + 16, y + 30), "ТОЧНО? Нажмите ещё раз — профиль (ангар, экипажи) будет удалён" if _wipe_t > 0.0
				else "Сбросить прогресс (ангар, экипажи, запчасти)", 18, C_TEXT)
			_buttons.append([wr, "wipe"])
			y += 56.0
		1:
			y = _section(x, y, w2, "Экран")
			y = _opt(x, y, w2, "Режим окна", Settings.WINDOW_MODES[Settings.window_mode], "window_mode")
			var res: Vector2i = Settings.RESOLUTIONS[Settings.resolution]
			y = _opt(x, y, w2, "Размер окна (для режима «В окне»)", "%d × %d" % [res.x, res.y], "resolution")
			y = _check(x, y, w2, "Вертикальная синхронизация", Settings.vsync, "vsync")
			var fl: int = Settings.FPS_LIMITS[Settings.fps_limit]
			y = _opt(x, y, w2, "Ограничение кадров", "без ограничения" if fl == 0 else "%d к/с" % fl, "fps_limit")
			y = _section(x, y + 10, w2, "Картинка")
			y = _opt(x, y, w2, "Качество графики", Settings.GFX[Settings.gfx] + (" (авто)" if Settings.gfx_auto else ""), "gfx")
			y = _check(x, y, w2, "Объёмная 3D-картинка (выкл. — старая 2D)", Tuning.g("render3d") > 0.5, "render3d")
			y = _check(x, y, w2, "Спрайты (выкл. — схематичные фигуры, F4)", Tuning.g("sprites") > 0.5, "sprites")
			y = _check(x, y, w2, "Круги дальности оружия (пунктир)", Tuning.g("range_rings") > 0.5, "range_rings")
			y = _section(x, y + 10, w2, "Интерфейс в полёте")
			y = _opt(x, y, w2, "Миникарта", Settings.MINIMAP_NAMES[Settings.minimap], "minimap")
			y = _opt(x, y, w2, "Прозрачность миникарты", "%d%%" % int(Settings.MINIMAP_ALPHA[Settings.minimap_alpha] * 100.0), "minimap_alpha")
		2:
			y = _section(x, y, w2, "Громкость")
			y = _slider(x, y, w2, "Общая", "master_db", "", -1.0)
			y = _slider(x, y, w2, "Музыка", "music_db", "", -1.0)
			y = _slider(x, y, w2, "Эффекты", "sfx_db", "", -1.0)
			y = _slider(x, y, w2, "Двигатель", "engine_db", "", -1.0)
			y = _slider(x, y, w2, "Интерфейс", "ui_db", "", -1.0)
		3:
			y = _section(x, y, w2, "Клавиатура")
			var col_w := (w2 - 40.0) / 2.0
			var yy := y
			for i in Settings.REBIND.size():
				var rb: Array = Settings.REBIND[i]
				var cx := x + (0.0 if i < 7 else col_w + 40.0)
				if i == 7:
					yy = y
				var r2 := Rect2(cx, yy, col_w, 46)
				var cap: bool = capturing == rb[0]
				ctrl.draw_rect(Rect2(cx, yy, col_w * 0.55, 46), Color(1, 1, 1, 0.06))
				_txt(Vector2(cx + 16, yy + 30), rb[1], 18, C_TEXT)
				var kr := Rect2(cx + col_w * 0.57, yy, col_w * 0.43, 46)
				var hover := kr.has_point(ctrl.get_local_mouse_position())
				ctrl.draw_rect(kr, C_AMBER if cap else (Color(0.95, 0.93, 0.88, 0.95) if hover else Color(0.85, 0.83, 0.78, 0.9)))
				_txt(Vector2(kr.position.x, yy + 31), "нажмите клавишу…" if cap else Settings.key_name(rb[0]), 19, Color(0.08, 0.07, 0.05), bold(),
					HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)
				_buttons.append([kr, "bind:" + String(rb[0])])
				yy += 56.0
			y = y + 7 * 56.0 + 10.0
			_txt(Vector2(x, y + 20), "Мышь: левая кнопка — огонь из пушки, правая — ракеты и бомбы вручную. Геймпад — стандартная раскладка. Esc — отменить ввод.", 16, C_DIM)
			var rr := Rect2(x + w2 - 300, y + 40, 300, 46)
			_small_button(rr, "СБРОСИТЬ КЛАВИШИ", "reset_binds")
	# низ
	_txt(Vector2(64, size.y - 32), "Esc — назад (сохраняет)    левая кнопка мыши — выбрать / тянуть ползунок    ‹ › — листать вариант", 18, C_DIM)
	_small_button(Rect2(size.x - 64 - 300, size.y - 64 - 50, 300, 50), "‹  НАЗАД", "settings_back")
	_small_button(Rect2(size.x - 64 - 640, size.y - 64 - 50, 320, 50), "СОХРАНИТЬ И ПРИМЕНИТЬ", "save_apply")
	_small_button(Rect2(size.x - 64 - 940, size.y - 64 - 50, 280, 50), "СБРОСИТЬ ВСЁ", "reset_all")
	if _saved_t > 0.0:
		_txt(Vector2(size.x - 64 - 940, size.y - 64 - 64), "✔ Настройки сохранены", 18, Color(0.5, 0.9, 0.5, minf(_saved_t, 1.0)), bold())


func _small_button(r: Rect2, label: String, action: String) -> void:
	var hover := r.has_point(ctrl.get_local_mouse_position())
	_panel(r, C_AMBER if hover else C_LINE, Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, 0.9) if hover else C_PANEL, 12.0)
	_txt(Vector2(r.position.x, r.position.y + r.size.y * 0.66), label, 18, Color(0.08, 0.07, 0.05) if hover else C_TEXT, bold(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_buttons.append([r, action])


func _section(x: float, y: float, w: float, title: String) -> float:
	_txt(Vector2(x, y), title, 28, C_TEXT, bold())
	ctrl.draw_line(Vector2(x, y + 14), Vector2(x + w, y + 14), C_LINE, 1.0)
	ctrl.draw_rect(Rect2(x, y + 12, 60, 4), C_AMBER)
	return y + 62.0


func _row_bg(x: float, y: float, w: float) -> Rect2:
	var r := Rect2(x, y - 34, w, 52)
	if r.has_point(ctrl.get_local_mouse_position()):
		ctrl.draw_rect(r, Color(1, 1, 1, 0.04))
	return r


func _check(x: float, y: float, w: float, label: String, on: bool, key: String) -> float:
	var r := _row_bg(x, y, w)
	var box := Rect2(x + 4, y - 22, 26, 26)
	ctrl.draw_rect(box, Color(0.85, 0.83, 0.78, 0.15))
	ctrl.draw_rect(box, C_LINE, false, 1.5)
	if on:
		ctrl.draw_rect(box.grow(-5), C_AMBER)
	_txt(Vector2(x + 46, y), label, 21, C_TEXT)
	_buttons.append([r, "chk:" + key])
	return y + 58.0


func _opt(x: float, y: float, w: float, label: String, value: String, key: String) -> float:
	_row_bg(x, y, w)
	_txt(Vector2(x + 4, y), label, 21, C_TEXT)
	var r := Rect2(x + w * 0.5, y - 32, w * 0.5, 46)
	var hover := r.has_point(ctrl.get_local_mouse_position())
	ctrl.draw_rect(r, Color(0.85, 0.83, 0.78, 0.18 if hover else 0.1))
	ctrl.draw_rect(r, C_LINE, false, 1.0)
	_txt(Vector2(r.position.x + 18, y), "‹", 26, C_AMBER, bold())
	_txt(Vector2(r.end.x - 34, y), "›", 26, C_AMBER, bold())
	_txt(Vector2(r.position.x, y), value, 20, C_TEXT, bold(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_buttons.append([r, "opt:" + key])
	return y + 58.0


## Ползунок параметра Tuning. fmt: формат значения; mul — множитель для показа; mul < 0 — громкость в %.
func _slider(x: float, y: float, w: float, label: String, key: String, fmt: String, mul := 1.0) -> float:
	_row_bg(x, y, w)
	_txt(Vector2(x + 4, y), label, 21, C_TEXT)
	var rg: Array = Tuning.RANGES[key]
	var lo := float(rg[0])
	var hi := float(rg[1])
	var v := Tuning.g(key)
	var k := clampf((v - lo) / (hi - lo), 0.0, 1.0)
	var r := Rect2(x + w * 0.5, y - 14, w * 0.5 - 110, 8)
	ctrl.draw_rect(r, Color(0.85, 0.83, 0.78, 0.25))
	ctrl.draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), C_AMBER)
	for i in 11:
		var tx := r.position.x + r.size.x * i / 10.0
		ctrl.draw_line(Vector2(tx, r.end.y + 4), Vector2(tx, r.end.y + (9 if i % 5 == 0 else 6)), C_LINE, 1.0)
	ctrl.draw_circle(Vector2(r.position.x + r.size.x * k, r.get_center().y), 12.0, C_TEXT)
	ctrl.draw_circle(Vector2(r.position.x + r.size.x * k, r.get_center().y), 6.0, C_AMBER_D)
	var shown: String
	if mul < 0.0:
		shown = "выкл." if k <= 0.001 else "%d%%" % int(round(k * 100.0))
	else:
		shown = fmt % (v * mul)
	_txt(Vector2(r.end.x + 20, y), shown, 20, C_AMBER, bold(), HORIZONTAL_ALIGNMENT_RIGHT, 90)
	_sliders.append([r, key, lo, hi])
	return y + 58.0


# ---------- «Как играть» (3.3-t1: показывается при первом запуске, потом — из меню) ----------

func close_howto() -> void:
	howto = false
	var f := FileAccess.open(HOWTO_FLAG, FileAccess.WRITE)
	if f:
		f.store_string("1")


const HOWTO_COLS := [
	["УПРАВЛЕНИЕ", [
		"Мышь — куда лететь, W / S — газ",
		"Пушка стреляет сама; Q — ручной огонь левой кнопкой мыши (до +50% урона)",
		"Ракеты и бомбы пускаются сами; правая кнопка мыши — пуск вручную",
		"Space — уклонение (переворот, пули не попадают)",
		"Shift — форсаж, E / F — навыки самолёта",
		"Tab — оружие на подвесах и пауза",
		"F2 — сменить управление",
		"Геймпад: только в бою — стик (сначала F2), курки — огонь, A — уклонение, X / B — навыки; меню и ангар — мышью",
	]],
	["ВЫЛЕТ", [
		"Цель — продержаться 15 минут и улететь через ворота эвакуации",
		"Всех врагов не перебить: они прилетают всё время",
		"Сбитые враги дают опыт; новый уровень — выбор 1 из 3 улучшений",
		"Каждые 5 минут — вражеский ас, после него можно улететь",
		"После 15:00 можно остаться: добыча +10% за каждую минуту",
		"Погибли — часть запчастей сохраняется",
	]],
	["ПРОКАЧКА", [
		"На 3-м уровне выберите специализацию — какую связку собирать",
		"Связка — сильный бонус; подходящие карточки отмечены «▲»",
		"За вылет — до 3 связок; список — в справочнике (меню и пауза)",
		"Между вылетами — АНГАР: самолёт, оружие, экипаж",
		"Экипаж растёт с каждым вылетом и открывает навыки",
	]],
]


func _howto(size: Vector2) -> void:
	_buttons.clear()
	ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.02, 0.82))
	var w := minf(1500.0, size.x - 120.0)
	var r := Rect2((size.x - w) / 2.0, 120, w, size.y - 220)
	_panel(r, C_AMBER)
	_txt(r.position + Vector2(48, 70), "КАК ИГРАТЬ", 40, C_AMBER, bold())
	_txt(r.position + Vector2(48, 108), "Спасибо, что тестируете Flak Heaven! Это ранний прототип: графика и баланс временные.", 18, C_DIM)
	var cw := (r.size.x - 96.0 - 64.0) / 3.0
	for i in HOWTO_COLS.size():
		var col: Array = HOWTO_COLS[i]
		var x := r.position.x + 48.0 + i * (cw + 32.0)
		var y := r.position.y + 170.0
		_txt(Vector2(x, y), col[0], 24, C_TEXT, bold())
		ctrl.draw_line(Vector2(x, y + 14), Vector2(x + cw, y + 14), C_LINE, 1.0)
		y += 52.0
		for line in col[1]:
			var lines := _wrap(String(line), cw - 24.0, 19)
			_txt(Vector2(x, y), "•", 19, C_AMBER)
			for ln in lines:
				_txt(Vector2(x + 20, y), ln, 19, C_TEXT)
				y += 27.0
			y += 9.0
	_txt(Vector2(r.position.x + 48, r.end.y - 40), ("После вылета нажмите «ОТПРАВИТЬ ОТЧЁТ» на экране итогов — это займёт минуту и очень нам поможет." if Main.REPORT_URL != "" else "После 3–5 вылетов: меню → ЛОГИ → отправьте файлы playtest_log_*.csv и logs/godot.log вместе с ответами на анкету."), 17, C_DIM)
	_menu_button(Rect2(r.end.x - 48 - 300, r.end.y - 96, 300, 62), "ПОНЯТНО", "howto_close", true)
	_menu_button(Rect2(r.end.x - 48 - 300 - 24 - 420, r.end.y - 96, 420, 62), "ПОДСКАЗКИ ЗАНОВО" if _saved_t <= 0.0 else "ПОДСКАЗКИ ВКЛЮЧЕНЫ", "hints_reset")


func _wrap(s: String, width: float, fsize: int) -> PackedStringArray:
	var out := PackedStringArray()
	var font := Hud.ui_font()
	var cur := ""
	for word in s.split(" "):
		var t := word if cur == "" else cur + " " + word
		if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = t
	if cur != "":
		out.append(cur)
	return out
