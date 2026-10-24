class_name Hud
extends CanvasLayer
## Интерфейс прототипа 2: опыт и уровень, прочность, навыки, подвесы, асы, эвакуация,
## экраны выбора класса, карточек, подвесов (пауза) и итогов вылета.
## Всё рисуется кодом; кнопки — прямоугольники, по которым можно кликнуть мышью.
## Здесь — слой, клики и выбор экрана; сама отрисовка — в модулях hud_*.gd (HudKit — общие примитивы).

const SCHEMES := ["по направлению (WASD / стик)", "влево / вправо (A / D)", "мышью (самолёт летит за курсором)"]

static var _font: Font

var ctrl: Control
## Top banner (`Events.banner`) and seconds of real time it stays on screen.
var banner := ""
var banner_t := 0.0
## Radio panel (`Events.radio`): sender, text, real seconds left, enemy chatter (red frame).
var radio_from := ""
var radio_text := ""
var radio_t := 0.0
var radio_enemy := false
var _radio_at := 0
var _autotest := false
var _dmg_flash := 0.0
var _buttons: Array = [] # [Rect2, action]

# Модули отрисовки (рисуют в ctrl, кнопки складывают в общий _buttons)
var _flight_ui: HudFlight
var _screens_ui: HudScreens
var _pause_ui: HudPause
var _cards_ui: HudCards
var _result_ui: HudResult
var _codex_ui: HudCodex
var _hangar_ui: HudHangar
var _campaign_ui: HudCampaign


static func ui_font() -> Font:
	if _font == null:
		_font = make_font(false)
	return _font


## U-09: шрифт интерфейса по настройке (Settings.font): встроенные PT Sans / Inter / Exo 2 или системный.
## Встроенные одинаково выглядят на Windows и Mac; лицензии — game/fonts/README.md.
static func make_font(bold: bool) -> Font:
	var f := _base_font(bold)
	f.fallbacks = [_cjk_font()]
	return f


## L-05: иероглифы берутся из урезанного Noto Sans SC (tools/i18n/subset_font.py), если в основном шрифте их нет.
## Подключён всегда: название «简体中文» в меню видно и на русском
static func _cjk_font() -> Font:
	return load("res://fonts/noto_sans_sc_subset.ttf")


static func _base_font(bold: bool) -> Font:
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
	_pause_ui = HudPause.new(ctrl, _buttons)
	_cards_ui = HudCards.new(ctrl, _buttons)
	_result_ui = HudResult.new(ctrl, _buttons)
	_codex_ui = HudCodex.new(ctrl, _buttons)
	_hangar_ui = HudHangar.new(ctrl, _buttons)
	_campaign_ui = HudCampaign.new(ctrl, _buttons)
	_autotest = OS.get_cmdline_user_args().has("--autotest")
	HudIcons.warm()
	Events.banner.connect(_on_banner)
	Events.radio.connect(_on_radio)


## Clears the banner and radio panel (new sortie).
func clear_messages() -> void:
	banner = ""
	banner_t = 0.0
	radio_t = 0.0


## Seconds since the current radio message arrived (panel slide-in and flash).
func radio_age() -> float:
	return (Time.get_ticks_msec() - _radio_at) / 1000.0


## `Events.banner`: shows `text` for `dur` real seconds; the autotest log gets a BANNER line.
func _on_banner(text: String, dur: float) -> void:
	if _autotest:
		print("BANNER %.0f: %s" % [Main.I.run_time, text])
	banner = text
	banner_t = dur


## `Events.radio`: shows the message (longer text stays longer), first-time hint and sound.
func _on_radio(from: String, text: String, enemy: bool) -> void:
	if _autotest:
		print("RADIO %.0f %s: %s" % [Main.I.run_time, from, text])
	radio_from = from
	radio_text = text
	radio_enemy = enemy
	radio_t = 3.5 + text.length() * 0.03
	_radio_at = Time.get_ticks_msec()
	Hints.show("radio", "Справа внизу — радиоэфир: ведомые отвечают на приказы, штаб предупреждает о задании. Красная рамка — перехват вражеского эфира, жди аса или босса.", 8.0, 2)
	Main.I.sfx.play("radio", -18.0, 2.2)


func flash_damage() -> void:
	_dmg_flash = 0.3


func _process(delta: float) -> void:
	_dmg_flash = maxf(0.0, _dmg_flash - delta)
	var real := delta / maxf(Engine.time_scale, 0.01)   # messages count real time (slow-mo, hit-stop)
	banner_t = maxf(0.0, banner_t - real)
	radio_t = maxf(0.0, radio_t - real)
	ctrl.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := Main.I
		if m == null or m.state == "playing" or m.tuning_panel.visible or m.report.visible:
			return
		var act := button_at(ctrl.get_local_mouse_position())
		if act != "":
			get_viewport().set_input_as_handled()
			m.ui_click(act)


## Action of the topmost button under `pos` ("" if none). Buttons drawn later sit on top, so the
## search runs from the end (CR-01: "Pin"/"Ban" inside a level-up card used to pick the card).
func button_at(pos: Vector2) -> String:
	for i in range(_buttons.size() - 1, -1, -1):
		if (_buttons[i][0] as Rect2).has_point(pos):
			return _buttons[i][1]
	return ""


## Screen rect of the bottom-bar tile of the skill bound to `action` (debug frames).
func skill_tile_rect(action: String) -> Rect2:
	return _flight_ui.skill_rect(action)


## Screen rect of the button with this action (empty Rect2 if it is not on screen).
func button_rect(action: String) -> Rect2:
	for b in _buttons:
		if b[1] == action:
			return b[0]
	return Rect2()


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
	if m.state == "campaign":
		_campaign_ui.draw(size)
		return

	# pause, card pick and results cover the whole fight, so the flight HUD would only show through them
	if m.state not in ["paused", "levelup", "dead", "evac"]:
		_flight_ui.draw(m, size, _dmg_flash)

	match m.state:
		"course_pick":
			_screens_ui.course_pick(m, size)
		"levelup":
			_cards_ui.draw(m, size)
		"paused":
			_pause_ui.draw(m, size)
		"dead", "evac":
			_result_ui.result(m, size)
