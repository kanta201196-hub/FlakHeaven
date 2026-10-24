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
	["skill_2", "Второй навык", "Бой"],
	["toggle_fire_mode", "Огонь: авто / ручной", "Бой"],
	["wing_prio", "Цель звена (ведомых)", "Бой"],
	["fire", "Огонь из пушки (клавиша)", "Бой"],
	["fire_hardpoint", "Ракеты залпом / бомбы", "Бой"],
	["loadout", "Подвесы (пауза)", "Интерфейс"],
	["reroll", "Перебросить карточки / заново", "Интерфейс"],
	["card_lock", "Закрепить карточку", "Интерфейс"],
	["card_ban", "Убрать карточку", "Интерфейс"],
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
## UI-01 step 3: per-option graphics (GfxPresets.IDS → value index). `gfx` stays the last preset
## picked; the options equal that preset until the player changes one («Своё»)
var gfx_opts := GfxPresets.preset(2)
## FPS counter in the corner of the flight screen
var show_fps := true
## UI-01 step 4: action → [key, alternative key, gamepad] tokens (`Binds`); `_defaults` is the
## same table read from InputSetup's events, for «reset» and for broken saves
var binds := {}
var _defaults := {}
## Stick dead zone for every action (InputMap deadzone), index into DEADZONES
const DEADZONES := [0.1, 0.15, 0.2, 0.25, 0.3, 0.4]
var deadzone := 3
## Gamepad glyphs: 0 by the connected controller, then a fixed family
const GLYPH_SETS := ["Автоматически", "Xbox", "PlayStation", "Steam Deck"]
const GLYPH_FAMILIES := ["", "xbox", "ps", "deck"]
var glyphs := 0
## Glyph textures by path, loaded in `_ready`: a texture first loaded inside a draw call came out
## as a plain white square under GL Compatibility (seen in the controls tab shots)
var _glyph_tex := {}


func _ready() -> void:
	# InputSetup is earlier in autoload, so its events are the defaults
	for r in REBIND:
		var a: String = r[0]
		_defaults[a] = Binds.from_events(InputMap.action_get_events(a)) if InputMap.has_action(a) else ["", "", ""]
		# three slots hold two keys and one gamepad input; more defaults would be dropped by apply_binds
		var kept := 3 - (_defaults[a] as Array).count("")
		if InputMap.has_action(a) and InputMap.action_get_events(a).size() > kept:
			push_warning("Settings: %s has more default inputs than the controls tab can show" % a)
	binds = _defaults.duplicate(true)
	for fam: String in GLYPH_FAMILIES:
		if fam == "":
			continue
		for g: String in Binds.glyph_names():
			var path := "res://art/glyphs/%s/%s.png" % [fam, g]
			_glyph_tex[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	load_settings()
	apply_binds()
	apply_lang()
	apply()


## Controller family whose glyphs and names to show ("xbox", "ps", "deck").
func pad_family() -> String:
	if glyphs > 0:
		return GLYPH_FAMILIES[glyphs]
	var pads := Input.get_connected_joypads()
	return Binds.family_of(Input.get_joy_name(pads[0]) if pads.size() > 0 else "")


## Readable name of a token (keyboard layout aware for keys).
func token_text(t: String) -> String:
	if t == "":
		return "—"
	if Binds.is_pad(t):
		return Binds.pad_text(t, pad_family())
	var ev := Binds.event_of(t)
	if ev is InputEventKey:
		var k := ev as InputEventKey
		match k.physical_keycode:
			KEY_UP:
				return "↑"
			KEY_DOWN:
				return "↓"
			KEY_LEFT:
				return "←"
			KEY_RIGHT:
				return "→"
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)).to_upper()
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return Loc.t("ЛКМ")
			MOUSE_BUTTON_RIGHT:
				return Loc.t("ПКМ")
			MOUSE_BUTTON_MIDDLE:
				return Loc.t("СКМ")
		return Loc.t("Мышь %d") % (ev as InputEventMouseButton).button_index
	return "?"


## Glyph texture for a gamepad token in the current family, null when there is none.
func pad_icon(t: String) -> Texture2D:
	var g := Binds.pad_glyph(t)
	if g == "":
		return null
	var path := "res://art/glyphs/%s/%s.png" % [pad_family(), g]
	if not _glyph_tex.has(path):
		_glyph_tex[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _glyph_tex[path]


## Sets one slot, without resolving conflicts (the controls tab asks first).
func set_bind(action: String, slot: int, token: String, swap := false) -> void:
	binds = Binds.swapped(binds, action, slot, token) if swap else Binds.with(binds, action, slot, token)
	apply_binds()
	save_settings()


## All bindings back to InputSetup's layout.
func reset_binds() -> void:
	binds = _defaults.duplicate(true)
	apply_binds()
	save_settings()


## Writes the table into InputMap: each rebindable action loses its key, mouse and gamepad events
## and gets the slot events back. The dead zone applies to every action.
func apply_binds() -> void:
	for a: String in binds:
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			InputMap.action_erase_event(a, e)
		for t: String in binds[a]:
			var ev := Binds.event_of(t)
			if ev != null:
				InputMap.action_add_event(a, ev)
	var dz: float = DEADZONES[deadzone]
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			InputMap.action_set_deadzone(a, dz)


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


## True under the Forward+ renderer; Forward+-only graphics values fall back otherwise.
static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Effective value of graphics option `id` (GfxPresets.IDS) for the running renderer. Systems
## read this instead of `gfx`, so a custom mix (say, low effects with high terrain) works.
func gopt(id: String) -> int:
	return GfxPresets.fallback(id, int(gfx_opts.get(id, 0)), forward_plus())


## Picks quality preset `i`: every option takes its value (also used by the low-FPS auto-drop).
func set_preset(i: int) -> void:
	gfx = clampi(i, 0, GFX_MAX)
	gfx_opts = GfxPresets.preset(gfx)


## Index of the preset the options match, −1 for «Своё».
func preset_now() -> int:
	return GfxPresets.preset_of(gfx_opts)


## Качество графики: свет и тени сразу, модели биома — при пересборке кусков рельефа
func apply_gfx() -> void:
	if Render3D.I != null:
		Render3D.I.apply_gfx()


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, Tuning.g("master_db"))


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"window_mode": window_mode, "resolution": resolution, "vsync": vsync, "fps_limit": fps_limit,
		"hide_hud": hide_hud, "gfx": gfx, "gfx_auto": gfx_auto, "gfx_opts": gfx_opts, "show_fps": show_fps, "font": font, "lang": lang, "wing_prio": wing_prio, "minimap": minimap, "minimap_alpha": minimap_alpha, "binds_v2": binds, "deadzone": deadzone, "glyphs": glyphs}, "  "))
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
	var go = d.get("gfx_opts", null)
	gfx_opts = GfxPresets.sanitize(go if go is Dictionary else {}, gfx)   # older saves: the preset of «gfx»
	show_fps = bool(d.get("show_fps", show_fps))
	font = clampi(int(d.get("font", font)), 0, FONTS.size() - 1)
	lang = clampi(int(d.get("lang", lang)), -1, LANGS.size() - 1)
	wing_prio = clampi(int(d.get("wing_prio", wing_prio)), 0, WING_PRIO.size() - 1)
	minimap = clampi(int(d.get("minimap", minimap)), 0, MINIMAP_SIZES.size() - 1)
	minimap_alpha = clampi(int(d.get("minimap_alpha", minimap_alpha)), 0, MINIMAP_ALPHA.size() - 1)
	deadzone = clampi(int(d.get("deadzone", deadzone)), 0, DEADZONES.size() - 1)
	glyphs = clampi(int(d.get("glyphs", glyphs)), 0, GLYPH_SETS.size() - 1)
	var b2 = d.get("binds_v2", null)
	var b1 = d.get("binds", null)
	if b2 is Dictionary:
		binds = Binds.sanitize(b2, _defaults)
	elif b1 is Dictionary:
		binds = Binds.migrate(_defaults, b1)   # saves before step 4: one key per action