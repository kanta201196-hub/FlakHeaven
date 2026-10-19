extends Node
## Настройки игры (2.8): экран, частота кадров, интерфейс и переназначение клавиш.
## Хранятся в user://settings.json. Громкости и параметры геймплея — в Tuning (user://tuning.json).

const PATH := "user://settings.json"

const WINDOW_MODES := ["В окне", "Без рамки (весь экран)", "Полный экран"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const FPS_LIMITS := [0, 60, 120, 144, 165, 240]
## T4-04 (B-33, минимум): «Качество графики». Что меняет — Render3D.apply_gfx и BiomeProps
const GFX := ["Низкое", "Среднее", "Высокое", "Максимальное"]
const GFX_MAX := 3
## U-09: шрифты интерфейса (встроенные — game/fonts/, лицензия OFL)
const FONTS := ["PT Sans", "Inter", "Exo 2", "Системный"]

## Действия, которые можно переназначить: [действие, подпись, раздел]
const REBIND := [
	["move_up", "Вверх / газ +", "Полёт"],
	["move_down", "Вниз / газ −", "Полёт"],
	["move_left", "Влево", "Полёт"],
	["move_right", "Вправо", "Полёт"],
	["afterburner", "Форсаж", "Полёт"],
	["roll", "Уклонение (у Кита — залп ловушек)", "Полёт"],
	["throttle_cut", "Сброс газа", "Полёт"],
	["dive", "Нырок", "Полёт"],
	["sharp_turn", "Навык класса", "Бой"],
	["toggle_fire_mode", "Огонь: авто / ручной", "Бой"],
	["wing_prio", "Цель звена (ведомых)", "Бой"],
	["fire", "Огонь из пушки (клавиша)", "Бой"],
	["fire_hardpoint", "Ракеты залпом / бомбы: держать — прицел, отпустить — сброс", "Бой"],
	["loadout", "Подвесы (пауза)", "Интерфейс"],
	["reroll", "Перебросить карточки / заново", "Интерфейс"],
	["toggle_scheme", "Сменить схему управления", "Интерфейс"],
]

var window_mode := 1
var resolution := 2
var vsync := true
var fps_limit := 0
var hide_hud := false
var gfx := 2               # «Высокое»; деревья полной детализации — только на «Максимальном»
var font := 0              # U-09: шрифт интерфейса — индекс в FONTS
## Перевод (docs/localization.md): язык интерфейса; -1 — по языку системы. Названия языков не переводятся
const LANGS := [["ru", "Русский"], ["en", "English"], ["zh_CN", "简体中文"]]
var lang := -1
## Правка 3.5-s4: кого звено атакует первым (клавиша G в полёте, кнопка на экране паузы)
const WING_PRIO := ["по задаче ведомого", "прикрывать меня", "крупные и асы", "наземные цели"]
var wing_prio := 0
## Правка 24: миникарта — размер (0 — выключена) и прозрачность
const MINIMAP_SIZES := [0.0, 180.0, 240.0, 320.0]
const MINIMAP_NAMES := ["выключена", "малая", "средняя", "большая"]
const MINIMAP_ALPHA := [0.4, 0.6, 0.8, 1.0]
var minimap := 2
var minimap_alpha := 2
var gfx_auto := true       # автоснижение при низком FPS, пока игрок не выбрал качество сам
var binds := {}          # действие → physical_keycode (только клавиатура)
var _defaults := {}      # исходные клавиши (для «Сбросить»)


func _ready() -> void:
	# запоминаем раскладку по умолчанию (InputSetup уже добавил действия — он раньше в автозагрузке)
	for r in REBIND:
		_defaults[r[0]] = _first_key(r[0])
	load_settings()
	apply_lang()
	apply()


func _first_key(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return (e as InputEventKey).physical_keycode
	return 0


func key_name(action: String) -> String:
	var k := _first_key(action)
	if k == 0:
		return "—"
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k))


func rebind(action: String, physical: int) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	InputMap.action_add_event(action, ev)
	binds[action] = physical
	save_settings()


func reset_binds() -> void:
	for a in _defaults:
		if int(_defaults[a]) != 0:
			rebind(a, int(_defaults[a]))
	binds.clear()
	save_settings()


func apply() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--autotest"):
		return
	match window_mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var r: Vector2i = RESOLUTIONS[resolution]
			var scr := DisplayServer.screen_get_size()
			r = Vector2i(mini(r.x, scr.x), mini(r.y, scr.y))
			DisplayServer.window_set_size(r)
			DisplayServer.window_set_position((scr - r) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_LIMITS[fps_limit]
	apply_audio()


## Язык: выбранный или по системе — русский для ru/uk/be/kk, иначе английский
func lang_index() -> int:
	if lang >= 0:
		return lang
	var l := OS.get_locale_language()
	return 0 if l in ["ru", "uk", "be", "kk"] else (2 if l == "zh" else 1)


func lang_name() -> String:
	var n: String = LANGS[lang_index()][1]
	return n if lang >= 0 else "%s (%s)" % [n, TranslationServer.translate("авто")]


func apply_lang() -> void:
	TranslationServer.set_locale(LANGS[lang_index()][0])
	Loc._out_cache.clear()


## Качество графики: свет и тени сразу, модели биома — при пересборке кусков рельефа
func apply_gfx() -> void:
	if Render3D.I != null:
		Render3D.I.apply_gfx(gfx)


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, Tuning.g("master_db"))


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"window_mode": window_mode, "resolution": resolution, "vsync": vsync, "fps_limit": fps_limit,
		"hide_hud": hide_hud, "gfx": gfx, "gfx_auto": gfx_auto, "font": font, "lang": lang, "wing_prio": wing_prio, "minimap": minimap, "minimap_alpha": minimap_alpha, "binds": binds}, "  "))
	f.close()


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not d is Dictionary:
		return
	window_mode = clampi(int(d.get("window_mode", window_mode)), 0, WINDOW_MODES.size() - 1)
	resolution = clampi(int(d.get("resolution", resolution)), 0, RESOLUTIONS.size() - 1)
	vsync = bool(d.get("vsync", vsync))
	fps_limit = clampi(int(d.get("fps_limit", fps_limit)), 0, FPS_LIMITS.size() - 1)
	hide_hud = bool(d.get("hide_hud", hide_hud))
	gfx = clampi(int(d.get("gfx", gfx)), 0, GFX_MAX)
	gfx_auto = bool(d.get("gfx_auto", gfx_auto))
	font = clampi(int(d.get("font", font)), 0, FONTS.size() - 1)
	lang = clampi(int(d.get("lang", lang)), -1, LANGS.size() - 1)
	wing_prio = clampi(int(d.get("wing_prio", wing_prio)), 0, WING_PRIO.size() - 1)
	minimap = clampi(int(d.get("minimap", minimap)), 0, MINIMAP_SIZES.size() - 1)
	minimap_alpha = clampi(int(d.get("minimap_alpha", minimap_alpha)), 0, MINIMAP_ALPHA.size() - 1)
	var b = d.get("binds", {})
	if b is Dictionary:
		for a in b:
			if InputMap.has_action(a):
				rebind(a, int(b[a]))
