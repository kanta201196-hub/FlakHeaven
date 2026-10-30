class_name Main
extends Node2D
## Корень прототипа 2 «Вылет»: выбор класса, вылет с опытом и карточками, асы каждые 5 минут,
## окна эвакуации, итоги вылета, лог плейтеста, отладочные клавиши, автотест и скриншоты.
## Модули: MainInput — клавиши и клики интерфейса, RunLog — лог плейтеста, MainDebug — автотест и скриншоты.

static var I: Main

var world: Node2D
var player: Player
var projectiles: Projectiles
var fx: Fx
var spawner: Spawner
var pickups: Pickups
var evac: EvacZone
var camera: Camera2D
var hud: Hud
var tuning_panel: TuningPanel
var sfx: Sfx
var menu: Menu
var background: Background
var clouds: Clouds
var render3d: Render3D

## Состояния: menu, settings, campaign («В вылет»), playing, levelup, paused, dead, evac
var state := "menu"
## Game mode of the sortie: "campaign" or "aces" (the «Битва асов» test mode, AB-01). Set by the menu
## (`MainInput.ui_click`); a restart from the result screen keeps it.
var mode := "campaign"
var cls_id := "fighter"
var skill_pick := {}
var codex_back := "menu"
var result_t := 0.0
var result_tab := 0 # правка 30: вкладка итогов — 0 обзор, 1 урон, 2 сборка
var hangar_cls := "fighter"
var hangar_tab := "plane"
var hangar_medal := ""   # medal picked on the «НАГРАДЫ» tab (its card stays under the board)
var hangar_w := "aam"
var decal_edit: DecalEditor   ## the hangar decal editor while «Знаки ›» is open (DecalEditInput drives it), else null
var hangar_back := "menu"        # анимация итогов для ангара   # 3.1: справочник связок — откуда открыт   # 3.1: выбранный навык класса: класс → id

var ace_log: Array = []   # тест 3.5-s5 (п. 10): асы вылета — прочность, урон по оружию, время жизни (колонка aces лога)
var restarts := 0
var offers: Array = []
const OFFER_COUNT := 4
## 3.5: неуязвимость после выбора карточки (было 1 с — к 15-й минуте набегало больше минуты)
const CARD_INVULN := 0.5
var rerolls := 2        # переброс выбора (базово 2 за вылет, +1 за каждого аса)
var bans := 2           # исключение карточки до конца вылета (базово 2, +1 за аса)
## тест 3.5-s7 (Kanta): на время тестов — по 10 перебросов и блоков за вылет (в игре было по 2)
const TEST_PICKS := 10
var banned := {}        # ключи исключённых карточек
var locked: Dictionary = {}  # закреплённая карточка — появится в следующем выборе
var offer_rare := false
var class_task: ClassTask = null   # EX-07: задание класса на вылет
var level_at_5 := 0   # уровень на 5:00 — для баланса кривой опыта
var stats := {}
## Damage per second by source over the last minute (pause screen, combat UI v2)
var dps := DpsWindow.new()
var counters := {}
var shots := 0
var hits := 0
var peak_rev := 0.0
var is_dead := false
var shake := 0.0
var god_mode := false
## Тестовая сборка для внешних тестеров: экспорт с фичей «tester» или флаг --tester → без отладки
static var DEBUG := true
## Build number shown in the menu, logs and reports; bump by commit before each export (code.md §11)
const BUILD := "3.5-s13"
## 3.3-t2: отчёты тестеров уходят в Google Таблицу через веб-приложение Apps Script (пусто — кнопки нет)
const REPORT_URL_BUILTIN := "https://script.google.com/macros/s/AKfycbxUYjbaKRdhawZJqQp52ZlEnh2LoAxDyEf-PefnyF_90ssskJgmcnFrTGJ0P7Y9PHrw/exec"
static var REPORT_URL := ""
var report: ReportPanel
var last_log_header := ""
var last_log_row := ""
var last_outcome := ""
var report_sent := false
var _fps_acc := 0.0
var _fps_n := 0
var base_ts := 1.0
var levelup_intro := false
## U-05: что сделано для задачи операции кампании («fortress», «baron») и итог на экране результатов
var op_flags := {}
var op_result := {}
var evac_windows := 0

var _autotest := false
var _args: PackedStringArray
var input_ctl: MainInput   # глобальные клавиши, клики интерфейса, действия ангара
var dbg: MainDebug         # автотест, скриншоты, отладочные проверки
var tele := Telemetry.new() # 3.4: замеры для анализа правок (колонки в конце лога)

## State of the current sortie (CS-03): read `run.*`, change it only through `RunState` methods
## (`tools/ci/smoke.sh` fails on direct writes). `run_time` (the sortie clock, read everywhere)
## and `parts_kept` (set at the end of the sortie) forward to it.
var run := RunState.new()
var run_time: float:
	get: return run.run_time
	set(v): run.run_time = v
var parts_kept: int:
	get: return run.parts_kept
	set(v): run.parts_kept = v


## True while the sortie is the «Битва асов» test mode: «Оса», rival aces, realistic damage (`AcesBalance`).
static func aces() -> bool:
	return I != null and I.mode == "aces"


func _ready() -> void:
	I = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	input_ctl = MainInput.new(self)
	dbg = MainDebug.new(self)
	_args = OS.get_cmdline_user_args()
	REPORT_URL = REPORT_URL_BUILTIN
	for a in _args:
		if a.begins_with("--report-url="):
			REPORT_URL = a.substr(13)
		if a.begins_with("--gfx="):    # T4-04: качество графики 0–3 на этот запуск (стенд, сравнение пресетов)
			Settings.set_preset(int(a.substr(6)))
			Settings.gfx_auto = false
		if a.begins_with("--tilt="):   # B-47: наклон камеры, град (проба; 0 — строго сверху)
			Tuning.set_param("cam_tilt", float(a.substr(7)))
		if a.begins_with("--capseed="):   # trailer capture: same seed + args = same sortie
			seed(int(a.substr(10)))
	if _args.has("--trailercap"):
		add_child(load("res://scripts/trailer_cap.gd").new(self))
	DEBUG = not (OS.has_feature("tester") or _args.has("--tester"))
	Events.activity_succeeded.connect(_on_activity_succeeded)
	Events.activity_failed.connect(_on_activity_failed)
	Events.enemy_hit.connect(_on_enemy_hit)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(_on_player_died)
	Events.near_miss.connect(_on_near_miss)
	Events.boss_wave.connect(_on_boss_wave)
	Events.evac_reached.connect(_on_evac_reached)
	Events.evac_closed.connect(_on_evac_closed)
	Events.evac_point_lost.connect(_on_evac_point_lost)
	_autotest = _args.has("--autotest")
	if _args.has("--aces"):   # check: the sortie is the «Битва асов» test mode
		mode = "aces"
		cls_id = "fighter"
	god_mode = _args.has("--god")
	if _args.has("--fast"):
		base_ts = 3.0
	if _args.has("--turbo"):
		base_ts = 6.0
	if _args.has("--perf"):
		Perf.on = true
		add_child(Perf.new())
	if _args.has("--shots"):
		Tuning.set_param("boss_hp", 300.0) # быстрее дойти до эвакуации при проверке сборки

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	camera.make_current()

	sfx = Sfx.new()
	add_child(sfx)
	hud = Hud.new()
	add_child(hud)
	tuning_panel = TuningPanel.new()
	add_child(tuning_panel)
	menu = Menu.new()
	add_child(menu)
	report = ReportPanel.new()
	add_child(report)
	# 2.8: атмосфера — свет, дымка, виньетка поверх мира, под интерфейсом
	# (рисуется первым слоем интерфейса — см. Hud._draw_hud)

	start_run()
	_set_state("menu")


var _state_t := 0.0 # сколько реального времени прошло с последней смены состояния


func _set_state(s: String) -> void:
	# combat UI v2: screens opened from combat start on their safe default, never on a focus
	# left from the last time (a remembered «Покинуть вылет» must not take one press)
	if s == "paused" and state == "playing":
		HudPause.focus = "resume"
	elif s == "dead" or s == "evac":
		HudResult.focus = "restart"
	state = s
	_state_t = 0.0
	if s in ["menu", "campaign", "hangar"] and not _args.has("--aces"):
		mode = "campaign"   # leaving «Битва асов» by any screen: the next sortie is a campaign one unless picked again
	get_tree().paused = s != "playing"
	Settings.set_screen_cap(s != "playing")
	if is_instance_valid(player) and menu != null:
		player.visible = not (s == "menu" or s == "hangar" or (s == "settings" and menu.back_state == "menu") or (s == "codex" and codex_back == "menu"))
	Engine.time_scale = base_ts


func select_class(id: String) -> void:
	cls_id = id
	start_run()
	_set_state("playing")


func start_run() -> void:
	if world:
		world.queue_free()
	evac = null
	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	move_child(world, 0)

	Biome.id = Biome.HIGHLAND if aces() else Campaign.biome_of(Campaign.index())   # тред «Второй биом»: биом мира — по операции, до создания фона
	if sfx != null:
		sfx.set_ambient("sea" if Biome.sea() else "highland")   # фон биома: прибой или горный ветер (PR #186)
	background = Background.new()
	world.add_child(background)
	clouds = Clouds.new()
	world.add_child(clouds)
	if render3d == null:
		render3d = Render3D.new()
		add_child(render3d)
	world.add_child(clouds.shadows)
	pickups = Pickups.new()
	world.add_child(pickups)
	spawner = Spawner.new()
	world.add_child(spawner)
	player = Player.new()
	var sks: Array = Profile.skills(cls_id)
	var sk1: String = skill_pick.get(cls_id, sks[0])
	player.setup(cls_id, sk1, sks[1] if sks[1] != sk1 else (sks[0] if sks[0] != sk1 else ""))
	world.add_child(player)
	class_task = null if aces() else ClassTask.new(cls_id)
	if not aces():
		Story.start(self)   # EX-09: «Купол», задание класса, в финале — «Гром» в звене
	projectiles = Projectiles.new()
	world.add_child(projectiles)
	fx = Fx.new()
	world.add_child(fx)

	run = RunState.new()
	run.parts_k = 1.0 if aces() else Profile.medal_parts_k(String(Campaign.op()["id"]))   # medals: parts bonus
	medal_run = {}
	medal_kill_t = []
	_hurt_t = 600.0
	is_dead = false
	dps.reset()
	stats = {"taken": {}, "taken_by": {}, "dealt": {}, "kills_by": {}, "taken_kind": {}, "raw_in": {}}   # S8: taken_kind — урон по видам оружия врагов, raw_in — «сырой» урон с --god
	ace_log = []
	counters = {}
	shots = 0
	hits = 0
	peak_rev = 0.0
	report_sent = false
	_fps_acc = 0.0
	_fps_n = 0
	hud.clear_messages()
	op_flags = {}
	op_result = {}
	Hints.clear()
	if aces():
		Events.banner.emit(Loc.t("БИТВА АСОВ · ТЕСТ"), 4.0)
		run.add_picks(AcesBalance.DRAFT_PICKS)   # option 1 (Kanta 26.10): the build is drafted before takeoff
		Hints.show("aces_goal2", "Битва асов: асы взлетают один за другим. Три ракеты или пара очередей аса — и самолёт сбит, у них так же. От ракет: F — ловушки, E — разворот сбивает наведение, Пробел — бочка. F1 — настройка полёта.", 10.0, 3)
	else:
		Events.banner.emit(Loc.t("%s · ОПЕРАЦИЯ «%s» · %s") % [Loc.t(Biome.title()).to_upper(), Loc.t(String(Campaign.op()["title"])).to_upper(), Loc.t(String(Campaign.diff()["title"])).to_upper()], 4.0)
		# U-02: цель вылета — первые 3 вылета (U-05: задача операции кампании)
		Hints.show("goal", Loc.t("Задача: %s. Всех врагов не перебить — они прилетают всё время.") % String(Campaign.op()["task"]).to_lower(), 9.0, 3)
	# U-03: первый вылет — подсказки по одной вместо стены текста «Как играть»
	Hints.show("controls", "Мышь — куда лететь: самолёт поворачивает за курсором. Пушка стреляет сама по врагам впереди.", 7.0, 2)
	if not aces():   # no XP cards in «Битва асов»
		Hints.show("xp", "Зелёные ромбы со сбитых врагов — опыт: пролетайте рядом, они притянутся. Новый уровень — выбор улучшения.", 7.0, 2)
	if Settings.minimap > 0:
		Hints.show("minimap", "Слева внизу — миникарта: север сверху, белая стрелка — вы, красные точки — враги, розовые — асы, цветной ромб — задание, зелёный ромб — ворота эвакуации, фиолетовые точки — звено. Размер и прозрачность — в «Настройки → Графика».", 8.0, 2)
	evac_windows = 0
	evac_lost = false
	rerolls = TEST_PICKS + Profile.extra_rerolls(cls_id) + int(Profile.medal_bonus("rerolls")) # 3.5: самолёт ур. 2 — +1 переброс; медаль «Коллекционер»
	bans = TEST_PICKS + int(Profile.medal_bonus("bans"))   # медаль «Мастер связок»
	banned = {}
	locked = {}
	course_log = []
	meta_award = {}
	_slow_t = 0.0
	offer_rare = false
	level_at_5 = 0
	tele.reset()
	camera.global_position = Vector2.ZERO
	camera.reset_smoothing()


func _process(delta: float) -> void:
	input_ctl.handle_global_input()
	dbg.process(delta)
	if state in ["dead", "evac"]:
		result_t += delta / maxf(Engine.time_scale, 0.01)
	if _slow_t > 0.0 and state == "playing":
		_slow_t -= delta / maxf(Engine.time_scale, 0.01)
		if not _hitstop: # 3.4: стоп-кадр не перебивается замедлением
			Engine.time_scale = _base_scale()
	if state == "playing" and not is_dead:
		tele.frame(delta, self)
		_fps_acc += Engine.get_frames_per_second()
		_fps_n += 1
		run_time += delta
		if class_task != null:
			class_task.update(self)
		if not aces():
			Story.tick(self)
		if level_at_5 == 0 and run_time >= 300.0:
			level_at_5 = run.level
		run.tick(delta)
		if run.pending_levels > 0:
			_open_levelup()
	if state == "playing":
		Hints.tick(delta / maxf(Engine.time_scale, 0.01))
	_state_t += delta / maxf(Engine.time_scale, 0.01)

	if state in ["menu", "settings"] and menu.back_state == "menu":
		# фон меню: камера медленно плывёт над биомом
		# тест 3.5-s5 (п. 1): по курсу звена заставки — самолёты летят носом вперёд, а не боком
		camera.global_position += TitleFlight.advance(delta / maxf(Engine.time_scale, 0.01), camera.global_position)
		camera.zoom = camera.zoom.lerp(Vector2(0.75, 0.75), 0.05)
		sfx.music("menu")
		return
	# Музыка: меню / бой / ас (если файлы есть в audio/)
	if state == "campaign":
		sfx.music("menu")
	elif state in ["dead", "evac"]:
		sfx.music("result")
	elif state == "playing":
		var hot := boss_alive() or (spawner != null and is_instance_valid(spawner.activity_node) and spawner.activity_node is RivalAce)
		sfx.music("boss" if hot else "battle")

	if _args.has("--dbg") and state == "playing" and int(run_time * 10) % 30 == 0:
		print("DBG p=", player.global_position, " vis=", player.is_visible_in_tree(), " cam=", camera.global_position, " zoom=", camera.zoom, " enemies=", get_tree().get_nodes_in_group("enemies").size(), " world_vis=", world.visible, " mod=", player.modulate)
	if is_instance_valid(player):
		var target := player.global_position + player.velocity * Tuning.g("camera_lookahead")
		camera.global_position = target
		# S9-09 (Ж1 «показать вес», числа полёта те же): камера догоняет тяжёлый самолёт медленнее —
		# «Оса» 7,6, «Грач» 5,8, «Кит» 4,8; в крутом вираже тяжёлого потряхивает (бафтинг)
		var ik := float(player.cls.get("inertia_k", 1.0))
		camera.position_smoothing_speed = 7.0 / pow(maxf(ik, 0.5), 0.4)
		if state == "playing" and ik > 1.0 and absf(player.bank) > 0.75 and player.ab_t <= 0.0:
			shake = maxf(shake, (absf(player.bank) - 0.75) * 4.0 * (ik - 1.0))
		# сглаживание камеры расходится при низком FPS (шаг > 1) — тогда без сглаживания
		camera.position_smoothing_enabled = delta * camera.position_smoothing_speed < 0.5
		# Камера чуть отъезжает на скорости — ощущение разгона
		var f := clampf(player.velocity.length() / maxf(player.cruise_speed(), 1.0), 0.5, 1.8)
		var z := Tuning.g("camera_zoom") / lerpf(1.0, player.size, 0.35) / (1.0 + maxf(0.0, f - 1.0) * 0.3)
		if aces():
			z *= AcesBalance.ZOOM_K   # faster planes: see the ace a little further out
		camera.zoom = camera.zoom.lerp(Vector2(z, z), 1.0 - exp(-delta * 3.0))
		_ab_snd = move_toward(_ab_snd, 1.0 if player.ab_t > 0.0 else 0.0, delta * 3.0)
		sfx.set_engine(player.velocity.length() / player.cruise_speed(), player.hp > 0.0 and state == "playing",
			_ab_snd, player.cls_id == "bomber" and player.plane_lvl <= 1, delta)
	else:
		sfx.set_engine(0.0, false)

	if shake > 0.0 and state == "playing":
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		shake = maxf(0.0, shake - 40.0 * delta)
	else:
		camera.offset = Vector2.ZERO


func ui_click(action: String) -> void:
	# Клики мышью по интерфейсу (HUD и меню передают сюда)
	input_ctl.ui_click(action)


func restart() -> void:
	restarts += 1
	start_run()
	_set_state("playing")


# ---------- Опыт и карточки ----------

## XP needed for the next level (`XpCurve`).
func xp_need() -> float:
	return run.xp_need()


## Kill XP multiplier at the current sortie time (S10-13, `XpCurve`).
func kill_xp_k() -> float:
	return run.kill_xp_k()


## Adds XP from pickups (times the F1 `xp_mult` slider); nothing after death.
func add_xp(v: float) -> void:
	if is_dead or aces():   # «Битва асов»: the hangar setup is the build, no cards
		return
	run.add_xp(v * Tuning.g("xp_mult") * (float(player.mods["xp_k"]) if is_instance_valid(player) else 1.0))   # medal «Быстрый взлёт»


func _open_levelup() -> void:
	# 3.2: сначала — выбор курса (на 3-м повышении и после каждой открытой связки)
	if Cards.need_course(player):
		_open_course()
		return
	if not refill_offers():
		return
	levelup_intro = Hints.bump("levelup_intro") <= 3 # U-03: первые 3 выбора — с объяснением
	_set_state("levelup")
	sfx.play("levelup", -8.0)


## Deals cards for the next pending level into `offers`. When nothing is left to offer, pays every
## pending level as repair + spare parts and returns false (CR-02: an empty offer after a pick,
## course choice, reroll or ban used to leave the game stuck on an empty level-up screen).
func refill_offers() -> bool:
	offer_rare = run.rare_picks > 0
	offers = Cards.offer(player, OFFER_COUNT, banned, locked, 2 if offer_rare else 0)
	_state_t = 0.0   # CR-05: new cards on screen restart the input delay
	if not offers.is_empty():
		return true
	# правка 3.5-s4: все улучшения собраны — награда за уровень и аса не пропадает молча
	var r := run.pay_all_cards_taken()
	player.heal(player.max_hp * float(r["heal"]), "allcards")
	Events.banner.emit(Loc.t("Все улучшения собраны — вместо карточки ремонт и +%d запчастей") % int(r["parts"]), 3.0)
	return false


## Leaves a card screen back to the fight with the usual short invulnerability.
func _resume_after_cards() -> void:
	_set_state("playing")
	player.invuln = maxf(player.invuln, CARD_INVULN)


## True once the card or course screen has been open for MainInput.CARD_INPUT_DELAY: picks,
## rerolls, locks and bans before that are ignored whatever sent them (key, gamepad, mouse
## click), so input from the fight cannot take a card the player has not seen (Kanta 25.10).
func cards_live() -> bool:
	return _state_t >= MainInput.CARD_INPUT_DELAY


func choose_card(i: int) -> void:
	if state != "levelup" or i < 0 or i >= offers.size() or not cards_live():
		return
	var c: Dictionary = offers[i]
	if not locked.is_empty() and c["id"] == locked["id"]:
		locked = {}
	Cards.on_declined(player, offers, c)
	Cards.apply(player, c)
	sfx.play("card", -8.0)
	run.take_pick(offer_rare)
	if Cards.need_course(player):
		_open_course()
	elif run.pending_levels <= 0 or not refill_offers():
		_resume_after_cards()


# ---------- 3.2: курс ----------

var course_offers: Array = []
var course_log: Array = []   # [время, варианты, выбор] — для лога


func _open_course() -> void:
	course_offers = Cards.course_options(player)
	if course_offers.is_empty():
		player.course = "-"
		_set_state("playing")
		return
	_set_state("course_pick")
	sfx.play("levelup", -8.0, 0.8)


func choose_course(i: int) -> void:
	if state != "course_pick" or i < 0 or i >= course_offers.size() or not cards_live():
		return
	player.course = course_offers[i]
	course_log.append("%d:%s>%s" % [int(run_time), "/".join(PackedStringArray(course_offers)), course_offers[i]])
	sfx.play("card", -8.0, 0.9)
	if run.pending_levels > 0 and refill_offers():
		_set_state("levelup")
	else:
		_resume_after_cards()


# ---------- 3.2: ангар ----------

## «Сменить курс» на экране выбора — за 1 переброс
func change_course() -> void:
	if state != "levelup" or rerolls <= 0 or not cards_live():
		return
	rerolls -= 1
	player.course = ""
	_open_course()


var _slow_t := 0.0
var _ab_snd := 0.0   # форсаж для гула двигателя (плавно 0…1)


## Замедление времени (открытие связки) — срабатывает, когда игра снова идёт
func slowmo(t: float) -> void:
	_slow_t = t


func reroll() -> void:
	if state != "levelup" or rerolls <= 0 or not cards_live():
		return
	rerolls -= 1
	sfx.play("card", -10.0, 0.8)
	if not refill_offers():
		_resume_after_cards()


## Закрепить карточку: она гарантированно будет в следующем выборе (и переживёт переброс).
## Повторный клик — открепить.
func lock_card(i: int) -> void:
	if state != "levelup" or i < 0 or i >= offers.size() or not cards_live():
		return
	if not locked.is_empty() and locked["id"] == offers[i]["id"]:
		locked = {}
	else:
		locked = offers[i].duplicate()
	sfx.play("card", -12.0, 1.5)


## Исключить карточку из выпадения до конца вылета; на её место — новая.
func ban_card(i: int) -> void:
	if state != "levelup" or bans <= 0 or i < 0 or i >= offers.size() or not cards_live():
		return
	var c: Dictionary = offers[i]
	if c["kind"] == "branch" and bool(c["first"]):
		return   # S9-15: «или-или» не исключается
	banned[c["ban"]] = c["title"]
	bans -= 1
	if not locked.is_empty() and locked["id"] == c["id"]:
		locked = {}
	offers.remove_at(i)
	# добрать одну новую карточку, не повторяя оставшиеся
	var extra := Cards.offer(player, OFFER_COUNT + 4, banned, {}, 2 if offer_rare else 0)
	var have: Array = offers.map(func(o): return o["id"])
	for e in extra:
		if not have.has(e["id"]):
			offers.insert(i, e)
			break
	sfx.play("ui_ban", -14.0, 1.6)
	if offers.is_empty() and not refill_offers():   # CR-02: the banned card was the last one
		_resume_after_cards()


## Banner headline per activity kind; the reward part is built from what `RunState` paid.
const ACTIVITY_TITLE := {
	&"ground": "Позиция ПВО уничтожена!", &"convoy": "Колонна разбита!", &"dogfight": "Ас-соперник сбит!",
	&"fort": "База противника разгромлена!",
}


## `Events.activity_succeeded`: pays the reward through `RunState.award_activity` (the only
## place that changes parts and the card queue for activities), then repair, course points,
## banner and sound. Activity-specific lines (story, radio, pickups) stay in the activity.
func _on_activity_succeeded(kind: StringName) -> void:
	if _autotest:
		print("AUTOTEST: activity success ", kind, " at %.0f" % run_time)
	if aces():   # «Битва асов»: a downed ace is the score, no parts or cards
		if kind == &"dogfight":
			run.on_rival_down()
			run.add_picks(AcesBalance.ace_picks(run.aces_down))   # option 1: a card for every ace
			Events.banner.emit(Loc.t("Ас сбит! Всего: %d") % run.aces_down, 2.5)
		return
	if kind == &"fort":
		medal_add("fort_areas")
	var r := run.award_activity(kind)
	if r.is_empty():
		return
	var rare: bool = r["rare"]
	var paid := int(r["parts"])
	if is_instance_valid(player):
		player.add_course_pts(int(r["course_pts"]))
		if float(r["heal"]) > 0.0:
			player.heal(player.max_hp * float(r["heal"]), "activity")
	match kind:
		&"transport":
			Events.banner.emit(Loc.t("Транспортник сбит! Груз: +%d запчастей, ремкомплекты") % paid
				+ (Loc.t(" и выбор из редких карточек") if rare else ""), 4.0)
			sfx.play("cargo", -4.0, 1.3)
		&"rescue":
			Events.banner.emit(Loc.t("Пилот спасён! Награда: выбор из редких карточек и +%d запчастей") % paid, 4.0)
			sfx.play("evac", -4.0, 1.3)
		&"class_task":
			Events.banner.emit(Loc.t("Задание класса выполнено! Награда: выбор из редких карточек и +%d запчастей") % paid, 4.0)
			sfx.play("evac", -4.0, 1.3)
		_:
			Story.say(Story.DISPATCH, "Чисто сработано. Награда ваша.")
			var reward := (Loc.t("выбор из редких карточек") + (Loc.t(" и +%d запчастей") % paid if paid > 0 else "")) \
				if rare else Loc.t("ремонт 20%% и +%d запчастей") % paid
			Events.banner.emit(Loc.t("%s Награда: %s") % [Loc.t(ACTIVITY_TITLE.get(kind, "")), reward], 4.0)
			sfx.play("evac", -4.0, 1.3)


## `Events.activity_failed`: dispatcher line and, for an escaped ace, a banner. No reward.
func _on_activity_failed(kind: StringName, who: String) -> void:
	if _autotest:
		print("AUTOTEST: activity failed ", kind, " at %.0f" % run_time)
	if kind != &"rescue":
		Story.say(Story.DISPATCH, "Ушли. Ничего, следующих встретим.")
	if kind == &"dogfight":
		if aces():
			run.on_rival_gone()
		Events.banner.emit(Loc.t("Ас «%s» ушёл — награды нет") % who, 3.0)


## Streak multiplier for kill parts and XP (`RunState.streak_mult`).
func streak_mult() -> float:
	return run.streak_mult()


var _near_text_ms := -100000   # when the last "close call" text went up (Time.get_ticks_msec)


## `Events.near_miss`: counts it (keeps the streak) and shows the "close call" text. Kanta s13: three texts at
## once stacked over the plane and hid it, so a new one waits 1.5 s after the last and stands clear of the plane
func _on_near_miss(kind: StringName) -> void:
	run.on_near_miss()
	var now := Time.get_ticks_msec()
	if now - _near_text_ms >= 1500:
		_near_text_ms = now
		fx.text(player.global_position + Vector2(0, -85), "На волоске!" if kind == &"bullet" else "Ракета мимо!", Color(0.6, 0.95, 1.0))
	sfx.play("near_miss", -16.0, 1.6)


# ---------- Асы и эвакуация ----------

func boss_alive() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if (n as Enemy).is_boss:
			return true
	return false


## `Events.boss_wave`: banner, enemy radio, hint, boss birth time for the log, sound and shake.
func _on_boss_wave(wave: int, n: int) -> void:
	if Biome.sea():
		Events.banner.emit(Loc.t(["«АЛЬБАТРОС» НА ПОДХОДЕ!", "КРЕЙСЕР «СТОРОЖ» В ПРОЛИВЕ!", "«ЛЕВИАФАН» В ПРОЛИВЕ!"][clampi(wave - 1, 0, 2)]), 4.0)
	else:
		Events.banner.emit(Loc.t("АС НА ПОДХОДЕ!  (%d)") % n if n > 1 else Loc.t("АС НА ПОДХОДЕ!"), 4.0)
	# правка 20: ас выходит в эфир — перехват его переговоров справа внизу
	Events.radio.emit("Перехват", ["Цель вижу. Захожу с солнца.", "Это наше небо. Уходи, пока цел.", "Звено, прикрыть меня — работаю по одиночке.",
		"Ещё один охотник? Посмотрим, сколько продержишься."][randi() % 4], true)
	Hints.show("ace", "Ас — сильный враг. Собьёте его — откроются ворота эвакуации и добавится переброс карточек.", 8.0, 2)
	# 3.5 (правка 30): время жизни аса — для лога
	for b in get_tree().get_nodes_in_group("enemies"):
		if b is Enemy and (b as Enemy).is_boss and not (b as Node).has_meta("born"):
			(b as Node).set_meta("born", run_time)
	sfx.play("boss", -2.0)
	add_shake(6.0)


func _open_evac() -> void:
	if is_instance_valid(evac):
		return
	evac = EvacZone.new()
	evac.setup(player.global_position, player.heading)
	world.add_child(evac)
	evac_windows += 1
	Events.banner.emit(Loc.t("Эвакуация: пролетите через 3 ворот по порядку") + ("" if Campaign.goal_done(run_time, op_flags) else Loc.t(" · задача операции ещё не выполнена")), 5.0)
	if run_time < 890.0:
		Hints.show("evac_early", "Улететь можно уже сейчас — или остаться до 15:00 и заработать больше запчастей.", 8.0, 2)
	else:
		Hints.show("evac_stay", "Задание выполнено! Улетайте через ворота — или оставайтесь: добыча +10% за каждую минуту после 15:00.", 9.0, 3)
	sfx.play("evac", -6.0)


## `Events.evac_reached`: the sortie ends with evacuation; parts kept, profile award, log.
func _on_evac_reached() -> void:
	parts_kept = int(run.parts * Campaign.k("reward"))
	op_result = Campaign.on_evac(run_time, op_flags)
	_award("evac")
	RunLog.write(self, "эвакуация")
	_set_state("evac")
	sfx.play("evac", -2.0, 1.2)


## «Левиафан» разбил точку эвакуации (5 залпов): открытое окно закрывается, после его гибели — не откроется
var evac_lost := false

## `Events.evac_point_lost`: a boss destroyed the evacuation point; the open window closes.
func _on_evac_point_lost(who: String) -> void:
	evac_lost = true
	if is_instance_valid(evac):
		evac.queue_free()
		evac = null
	Events.banner.emit(Loc.t("%s разбил точку эвакуации — эвакуация закрыта до следующего аса") % who, 4.5)
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: evac point lost")


## `Events.evac_closed`: the window ran out.
func _on_evac_closed() -> void:
	Events.banner.emit("Окно эвакуации закрыто — следующее после следующего аса", 4.0)


## Reward multiplier for staying after 15:00 (`RunState.continue_mult`).
func continue_mult() -> float:
	return run.continue_mult()


# ---------- Статистика ----------

## Adds `v` to stat `key` of `group` ("dealt", "taken", …) for the results screen and the log;
## dealt damage also feeds the last-minute DPS window of the pause screen.
func add_stat(group: String, key: String, v: float) -> void:
	var d: Dictionary = stats[group]
	d[key] = float(d.get(key, 0.0)) + v
	if group == "dealt":
		dps.add(StringName(key), v, run_time)


func stats_add_counter(key: String, v: int) -> void:
	counters[key] = int(counters.get(key, 0)) + v


func stat(group: String, key: String) -> int:
	return int(round(float((stats[group] as Dictionary).get(key, 0.0))))


func total(group: String) -> int:
	var s := 0.0
	for v in (stats[group] as Dictionary).values():
		s += float(v)
	return int(round(s))


# ---------- События боя ----------

## `Events.enemy_hit`: spark, damage number, hit sound.
func _on_enemy_hit(e: Enemy, dmg: float) -> void:
	fx.hit_spark(e.global_position)
	if e.is_ground and randf() < 0.35 and Boom3D.active():   # VFX-04: rounds around a ground target throw up dirt
		Boom3D.ensure().ground_hit(e.global_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * e.radius * 1.4)
	if Tuning.g("damage_numbers") > 0.5:
		fx.number(e.global_position + Vector2(0, -e.radius), dmg)
	sfx.play("hit", -18.0, 1.0, e.global_position)


## `Events.enemy_killed`: the one handler that changes state on a kill, in a fixed order —
## spawner flow, player perks, class task, then `RunState.on_kill` (kills, streak, parts) before
## the enemy drops XP; then effects, operation flags and boss handling.
func _on_enemy_killed(e: Enemy) -> void:
	if is_instance_valid(spawner):
		spawner.note_kill(e)
	if is_instance_valid(player):
		player.on_kill(e)
	add_stat("kills_by", e.kind(), 1.0)
	_medal_kill(e)
	if class_task != null:
		class_task.on_kill(self, e)
	var from_tail := is_instance_valid(player) and player.on_tail() and player.tail_target == e
	if from_tail:
		e.xp = int(ceil(e.xp * 1.5))
		fx.text(e.global_position + Vector2(0, -30), "Сбит с хвоста!", Color(1.0, 0.9, 0.4))
	run.on_kill(e.parts * (1.5 if (e.is_ground and is_instance_valid(player) and player.has_perk("a_grd2")) else 1.0) \
		* (player.mastery_parts_k(e) if is_instance_valid(player) else 1.0) \
		* (float(player.mods["boss_parts"]) if e.is_boss and is_instance_valid(player) else 1.0), from_tail)   # medal «Крепость пала»
	fx.explosion(e.global_position, e.radius * (1.3 if e.big else 1.0), not e.is_ground)
	sfx.play("explode_big" if e.big else "explode", -4.0 if e.big else -12.0, 1.0, e.global_position)
	add_shake(e.kill_shake)
	if e.big:
		hitstop()
	if e is Fortress:
		op_flags["fortress"] = true
	if e is RivalAce and (e as RivalAce).callsign == "Барон" and Campaign.baron():
		op_flags["baron"] = true
		Story.on_baron_down()
		fx.text(e.global_position + Vector2(0, -60), "«Барон» сбит!", Color(1.0, 0.85, 0.4))
	if e.is_boss:
		run.on_boss_killed()
		if e.has_meta("born"):
			tele.boss_killed(run_time - float(e.get_meta("born")))
		if is_instance_valid(player):
			player.add_course_pts(2) # 3.2: ас — +2 к курсу
		rerolls += 1
		bans += 1
		fx.text(e.global_position, "ПОТОПЛЕН!" if e is Warship else "АС СБИТ!", Color(1.0, 0.8, 0.4))
		if not boss_alive():
			if evac_lost and e is Warship:
				evac_lost = false   # точку разбил этот корабль: окна нет до следующего аса
				Events.banner.emit(Loc.t("Точка эвакуации разбита — окно откроется после следующего аса"), 4.0)
			else:
				evac_lost = false
				_open_evac()


## `Events.player_damaged`: shake, hint, hit-stop, sound, red flash.
func _on_player_damaged(_amount: float) -> void:
	_clean_mark()
	add_shake(10.0)
	if is_instance_valid(player) and player.has_roll():
		Hints.show("roll", "Space — уклонение: короткий переворот, во время которого пули и ракеты не попадают.", 7.0, 2)
	hitstop()
	sfx.play("player_hit", -4.0)
	hud.flash_damage()


# ---------- медали: счётчики вылета (Medals.run_counters) ----------

## This sortie's medal counters that nothing else keeps (rival aces, fortresses, warships, ground kills, missile
## kills, rams, flared missiles, fortified areas, the best clean stretch after 10:00). RunState.bosses_killed counts
## every Boss, so the ace and fortress medals keep their own counters here (review 2026-10-30, R-01).
var medal_run := {}
## Kill times of this sortie, s — the «Карусель» medal looks for the best minute
var medal_kill_t: Array = []
var _hurt_t := 600.0


## +`n` to this sortie's medal counter `key`
func medal_add(key: String, n := 1) -> void:
	medal_run[key] = int(medal_run.get(key, 0)) + n


func _medal_kill(e: Enemy) -> void:
	medal_kill_t.append(run_time)
	if e.is_ground:
		medal_add("ground")
	if e is RivalAce:
		medal_add("aces")
	if e is Warship:
		medal_add("warships")
	if e is Fortress:
		medal_add("fortresses")
		if (e as Fortress).base_hits == 0:
			medal_add("fort_clean")
	if MedalBalance.MSL_SRC.has(e.last_src):
		medal_add("msl_kills")
	if e is Drone and e.rammed:
		medal_add("ram_drones")


## Weapons and modules of this sortie for «Коллекционер»: cards taken plus the weapons the plane flew with from the start
## (a class's signature weapon never comes as a «new weapon» card to that class)
func _medal_cards() -> Array:
	if not is_instance_valid(player):
		return []
	var out: Array = player.medal_cards.duplicate()
	for g: Hardpoint in player.groups:
		if not g.builtin and not g.is_empty() and not out.has("w:" + g.weapon):
			out.append("w:" + g.weapon)
	return out


## Closes the stretch without damage that ends now (after 10:00 only) — medal «Ни царапины»
func _clean_mark() -> void:
	if run_time > 600.0:
		medal_run["clean_s"] = maxi(int(medal_run.get("clean_s", 0)), int(run_time - maxf(_hurt_t, 600.0)))
		_hurt_t = run_time


## 3.2: начисление в профиль (запчасти + жалованье, опыт экипажа) — сразу при конце вылета
var meta_award := {}


func _award(outcome: String) -> void:
	_clean_mark()
	meta_award = Profile.award_run({"cls": cls_id, "outcome": outcome, "run_time": run_time, "level": run.level,
		"bosses": run.bosses_killed, "activities": run.activities_done, "parts_kept": parts_kept, "continue_mult": continue_mult(),
		"op_parts": int(op_result.get("parts", 0)), "medals": Medals.run_counters(self, outcome),
		"cards_taken": _medal_cards(), "syn_taken": player.syn.keys() if is_instance_valid(player) else []})
	result_t = 0.0
	result_tab = 0


## `Events.player_died`: the sortie ends; half the parts kept, profile award, log.
func _on_player_died() -> void:
	is_dead = true
	if aces():   # test mode: no parts, crew XP or campaign progress (cannot be farmed)
		parts_kept = 0
		op_result = {}
		meta_award = {}
		result_t = 0.0
		result_tab = 0
	else:
		parts_kept = int(run.parts * 0.5 * Campaign.k("reward"))
		op_result = Campaign.result_base(run_time, op_flags)
		op_result["done"] = false
		_award("dead")
	fx.explosion(player.global_position, 40.0)
	sfx.play("player_explode", 0.0, 0.7)
	add_shake(16.0)
	RunLog.write(self, "гибель")
	_set_state_deferred_dead()


func _set_state_deferred_dead() -> void:
	# Даём взрыву доиграть, затем экран итогов
	await get_tree().create_timer(1.2, true, false, true).timeout
	if is_dead and state == "playing":
		_set_state("dead")


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount * Tuning.g("shake_mult"))


var _hitstop := false


## Обычная скорость времени с учётом замедления открытия связки
func _base_scale() -> float:
	return base_ts * (0.3 if _slow_t > 0.0 else 1.0)


func hitstop() -> void:
	var ms := Tuning.g("hitstop_ms")
	if ms <= 0.0 or _hitstop:
		return
	tele.add("hitstops")
	if _slow_t > 0.0:
		tele.add("hitstop_in_slowmo")
	_hitstop = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
	_hitstop = false
	# 3.4: после стоп-кадра возвращаем замедление связки, если оно ещё идёт (раньше сбрасывалось в 1,0)
	if state == "playing":
		Engine.time_scale = _base_scale()


func _input(event: InputEvent) -> void:
	tele.input(event)


func _exit_tree() -> void:
	I = null


func avg_fps() -> float:
	return _fps_acc / float(_fps_n) if _fps_n > 0 else 0.0
