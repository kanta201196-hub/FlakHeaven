class_name Hud
extends CanvasLayer
## Интерфейс прототипа 2: опыт и уровень, прочность, навыки, подвесы, асы, эвакуация,
## экраны выбора класса, карточек, подвесов (пауза) и итогов вылета.
## Всё рисуется кодом; кнопки — прямоугольники, по которым можно кликнуть мышью.
## Здесь — слой, клики и выбор экрана; сама отрисовка — в модулях hud_*.gd (HudKit — общие примитивы).

const SCHEMES := ["по направлению (WASD / стик)", "влево / вправо (A / D)", "мышью (самолёт летит за курсором)"]

static var _font: Font

var ctrl: Control
var _dmg_flash := 0.0
var _buttons: Array = [] # [Rect2, action]

# Модули отрисовки (рисуют в ctrl, кнопки складывают в общий _buttons)
var _flight_ui: HudFlight
var _screens_ui: HudScreens
var _codex_ui: HudCodex
var _hangar_ui: HudHangar


static func ui_font() -> Font:
	if _font == null:
		_font = make_font(false)
	return _font


## U-09: шрифт интерфейса по настройке (Settings.font): встроенные PT Sans / Inter / Exo 2 или системный.
## Встроенные одинаково выглядят на Windows и Mac; лицензии — game/fonts/README.md.
static func make_font(bold: bool) -> Font:
	match Settings.font:
		0:
			return load("res://fonts/pt_sans_bold.ttf" if bold else "res://fonts/pt_sans_regular.ttf")
		1, 2:
			var fv := FontVariation.new()
			fv.base_font = load("res://fonts/inter_variable.ttf" if Settings.font == 1 else "res://fonts/exo2_variable.ttf")
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700 if bold else (450 if Settings.font == 1 else 500)}
			return fv
	var sf := SystemFont.new()
	if bold:
		sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Roboto", "Noto Sans", "DejaVu Sans"])
		sf.font_weight = 700
	else:
		sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Roboto", "Noto Sans", "DejaVu Sans", "Ubuntu", "Helvetica"])
	return sf


## Сменили шрифт в настройках — пересоздать при следующей отрисовке
static func reset_fonts() -> void:
	_font = null
	Menu._bold = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	ctrl = Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ctrl)
	ctrl.draw.connect(_draw_hud)
	_flight_ui = HudFlight.new(ctrl, _buttons)
	_screens_ui = HudScreens.new(ctrl, _buttons)
	_codex_ui = HudCodex.new(ctrl, _buttons)
	_hangar_ui = HudHangar.new(ctrl, _buttons)


func flash_damage() -> void:
	_dmg_flash = 0.3


func _process(delta: float) -> void:
	_dmg_flash = maxf(0.0, _dmg_flash - delta)
	ctrl.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := Main.I
		if m == null or m.state == "playing" or m.tuning_panel.visible or m.report.visible:
			return
		var mp := ctrl.get_local_mouse_position()
		for b in _buttons:
			if (b[0] as Rect2).has_point(mp):
				get_viewport().set_input_as_handled()
				m.ui_click(b[1])
				return


# ---------- Главная отрисовка ----------

func _draw_hud() -> void:
	_buttons.clear()
	var m := Main.I
	if m == null or m.tuning_panel.visible:
		return
	var size := ctrl.size

	if m.state in ["menu", "settings"]:
		return
	if m.state == "codex":
		_codex_ui.draw(m, size)
		return
	if m.state == "hangar":
		_hangar_ui.draw(m, size)
		return
	if m.state == "class_select":
		_screens_ui.class_select(size)
		return

	_flight_ui.draw(m, size, _dmg_flash)

	match m.state:
		"course_pick":
			_screens_ui.course_pick(m, size)
		"levelup":
			_screens_ui.levelup(m, size)
		"paused":
			_screens_ui.loadout(m, size)
		"dead", "evac":
			_screens_ui.result(m, size)
