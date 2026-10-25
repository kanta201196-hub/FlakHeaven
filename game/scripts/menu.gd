class_name Menu
extends CanvasLayer
## Canvas layer for the main menu and the settings screen (UI-01): draws the shared header and
## shade, routes input and drawing to `MenuMain` or `MenuSettings`, keeps the flight log
## records and the key being rebound. Behind the menu runs the live biome with a slow camera
## and the title flight of three planes.

## Colour names kept for other HUD files; values come from UiStyle.
const C_LINE := UiStyle.LINE
const C_DIM := UiStyle.TEXT_DIM
const C_AMBER := UiStyle.ACCENT

static var _bold: Font

var ctrl: Control
var back_state := "menu"
var _t := 0.0
var records := {}
var main_screen: MenuMain
var settings_screen: MenuSettings
var _was_menu := false


static func bold() -> Font:
	if _bold == null:
		_bold = Hud.make_font(true)
	return _bold



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	ctrl = Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ctrl)
	ctrl.draw.connect(_draw_menu)
	main_screen = MenuMain.new(self)
	settings_screen = MenuSettings.new(self)
	load_records()
	add_child(UpdateCheck.new())


func active() -> bool:
	return Main.I != null and Main.I.state in ["menu", "settings"]


func _process(delta: float) -> void:
	_t += delta
	ctrl.visible = active()
	var on_main := ctrl.visible and Main.I.state == "menu"
	if on_main and not _was_menu:
		main_screen.reset()
	_was_menu = on_main
	if on_main:
		main_screen.process(delta)
	var on_settings := ctrl.visible and Main.I.state == "settings"
	settings_screen.list.visible = on_settings and settings_screen.list.visible
	if on_settings:
		settings_screen.process(delta)
	if ctrl.visible:
		ctrl.queue_redraw()


# ---------- Ввод ----------

func _input(event: InputEvent) -> void:
	if not active():
		return
	var m := Main.I
	if m.state == "menu":
		if m.report != null and m.report.visible:
			return   # the tester report form takes the keys
		if main_screen.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if settings_screen.handle_input(event):
		get_viewport().set_input_as_handled()


func open_settings(from: String) -> void:
	back_state = from
	settings_screen.reset()
	Main.I._set_state("settings")


func close_settings() -> void:
	Tuning.save_params()
	Settings.save_settings()
	settings_screen.cancel_capture()
	settings_screen.list.visible = false
	Main.I._set_state(back_state)


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

func _draw_menu() -> void:
	var m := Main.I
	if m == null:
		return
	var size := ctrl.size
	if m.state == "settings":   # settings: the whole frame darker, the list and panels sit on top
		ctrl.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.03, 0.5))
	# затемнение слева — читаемость кнопок; справа видно биом и звено
	var grad_w := size.x * 0.55
	var shade := Color(0.04, 0.045, 0.04, 0.75)
	ctrl.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(grad_w, 0), Vector2(grad_w, size.y), Vector2(0, size.y)]),
		PackedColorArray([shade, Color(shade, 0.0), Color(shade, 0.0), shade]))
	ctrl.draw_rect(Rect2(0, 0, size.x, 96), Color(0.04, 0.045, 0.04, 0.55))
	var hf := UiStyle.head_font(700, 5)
	var crumb := "◇ FLAK HEAVEN "
	UiStyle.text(ctrl, hf, Vector2(64, 58), crumb, UiStyle.FS_LABEL + 2, UiStyle.TEXT_WARM)
	var cx := 64.0 + UiStyle.text_w(hf, crumb, UiStyle.FS_LABEL + 2)
	UiStyle.text(ctrl, hf, Vector2(cx, 58), "// ", UiStyle.FS_LABEL + 2, UiStyle.ACCENT)
	cx += UiStyle.text_w(hf, "// ", UiStyle.FS_LABEL + 2)
	UiStyle.text(ctrl, hf, Vector2(cx, 58), "ГЛАВНЫЙ ТЕРМИНАЛ" if m.state == "menu"
		else Loc.t("НАСТРОЙКИ") + " // " + Loc.t(MenuSettings.TABS[settings_screen.tab]), UiStyle.FS_LABEL + 2, UiStyle.TEXT_WARM)
	# build number comes only from Main.BUILD
	UiStyle.text(ctrl, UiStyle.head_font(600, 4), Vector2(size.x - 64 - 600, 46), "ВЕРСИЯ", UiStyle.FS_CAPTION, UiStyle.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, 600)
	UiStyle.text(ctrl, UiStyle.head_font(800, 2), Vector2(size.x - 64 - 600, 72), Demo.tag(Main.BUILD), UiStyle.FS_LABEL + 2, UiStyle.TEXT_WARM,
		HORIZONTAL_ALIGNMENT_RIGHT, 600)
	ctrl.draw_line(Vector2(64, 96), Vector2(size.x - 64, 96), C_LINE, 1.0)
	ctrl.draw_line(Vector2(64, size.y - 70), Vector2(size.x - 64, size.y - 70), C_LINE, 1.0)
	if m.state == "menu":
		main_screen.draw(size)
	else:
		settings_screen.draw(size)


## Splits text into lines that fit `width` at font size `fsize` in `font` (the body font by
## default; Chinese breaks between characters, other languages between words).
func wrap(s: String, width: float, fsize: int, font: Font = null) -> PackedStringArray:
	s = Loc.out(s)
	var out := PackedStringArray()
	if font == null:
		font = Hud.ui_font()
	var cur := ""
	# L-05: в китайском пробелов нет — переносим между иероглифами
	var sep := "" if TranslationServer.get_locale().begins_with("zh") else " "
	var words: Array = _CJK_TOKEN.search_all(s).map(func(m): return m.get_string().strip_edges()) if sep == "" else Array(s.split(" "))
	for word in words:
		if word == "":
			continue
		var t: String = word if cur == "" else cur + sep + word
		if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = t
	if cur != "":
		out.append(cur)
	return out


## Слово для переноса в китайском: один иероглиф со знаком препинания после него или латинское слово с пробелом
static var _CJK_TOKEN := RegEx.create_from_string("[\\x{2E80}-\\x{9FFF}\\x{F900}-\\x{FAFF}][\\x{3000}-\\x{303F}\\x{FF00}-\\x{FF65}”’）]*|[^\\x{2E80}-\\x{9FFF}\\x{F900}-\\x{FAFF}]+?(?= |[\\x{2E80}-\\x{9FFF}]|$) ?")
