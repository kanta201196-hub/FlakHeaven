class_name Main
extends Node2D
## Корень прототипа 2 «Вылет»: выбор класса, вылет с опытом и карточками, асы каждые 5 минут,
## окна эвакуации, итоги вылета, лог плейтеста, отладочные клавиши, автотест и скриншоты.

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

## Состояния: menu, settings, class_select, playing, levelup, paused, dead, evac
var state := "menu"
var cls_id := "fighter"
var skill_pick := {}
var codex_back := "menu"
var result_t := 0.0
var hangar_cls := "fighter"
var hangar_tab := "plane"
var hangar_w := "aam"
var hangar_back := "menu"        # анимация итогов для ангара   # 3.1: справочник связок — откуда открыт   # 3.1: выбранный навык класса: класс → id

var run_time := 0.0
var kills := 0
var restarts := 0
var level := 1
var xp := 0.0
var pending_levels := 0
var offers: Array = []
const OFFER_COUNT := 4
var rerolls := 2        # переброс выбора (базово 2 за вылет, +1 за каждого аса)
var bans := 2           # исключение карточки до конца вылета (базово 2, +1 за аса)
var banned := {}        # ключи исключённых карточек
var locked: Dictionary = {}  # закреплённая карточка — появится в следующем выборе
var streak := 0         # серия сбитий без паузы > 2,5 с
var streak_t := 0.0
var best_streak := 0
var near_misses := 0
var rare_picks := 0        # выборы из редких карточек (награда за аса-соперника)
var offer_rare := false
var rare_reasons: Array = []  # 3.1: за что награда («ЗА ПОЗИЦИЮ ПВО», «ЗА АСА»)
var activities_done := 0
var radio_from := ""
var radio_text := ""
var radio_t := 0.0
var tail_kills := 0
var level_at_5 := 0   # уровень на 5:00 — для баланса кривой опыта
var parts := 0.0        # запчасти (валюта ангара), набранные за вылет
var parts_kept := 0     # сколько сохранено по итогам (100% при эвакуации, 50% при гибели)
var stats := {}
var counters := {}
var shots := 0
var hits := 0
var peak_rev := 0.0
var is_dead := false
var shake := 0.0
var god_mode := false
## Тестовая сборка для внешних тестеров: экспорт с фичей «tester» или флаг --tester → без отладки
static var DEBUG := true
const BUILD := "3.3-t2"
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
var banner := ""
var banner_t := 0.0
var bosses_killed := 0
var evac_windows := 0

var _autotest := false
var _autotest_t := 0.0
var _args: PackedStringArray


func _ready() -> void:
	I = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args = OS.get_cmdline_user_args()
	REPORT_URL = REPORT_URL_BUILTIN
	for a in _args:
		if a.begins_with("--report-url="):
			REPORT_URL = a.substr(13)
	DEBUG = not (OS.has_feature("tester") or _args.has("--tester"))
	_autotest = _args.has("--autotest")
	god_mode = _args.has("--god")
	if _args.has("--fast"):
		base_ts = 3.0
	if _args.has("--turbo"):
		base_ts = 6.0
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
	state = s
	_state_t = 0.0
	get_tree().paused = s != "playing"
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
	player.setup(cls_id, skill_pick.get(cls_id, sks[0]), sks[1])
	world.add_child(player)
	if Profile.has_perk(cls_id, "b_wing2") and int(player.cls["wingmen"]) > 0:
		player.add_wingman("swift", 1.0) # перк «Старый знакомый»
	projectiles = Projectiles.new()
	world.add_child(projectiles)
	fx = Fx.new()
	world.add_child(fx)

	run_time = 0.0
	kills = 0
	level = 1
	xp = 0.0
	pending_levels = 0
	parts = 0.0
	parts_kept = 0
	is_dead = false
	stats = {"taken": {}, "taken_by": {}, "dealt": {}, "kills_by": {}}
	counters = {}
	shots = 0
	hits = 0
	peak_rev = 0.0
	report_sent = false
	_fps_acc = 0.0
	_fps_n = 0
	banner = ""
	show_banner("%s · %s" % [Background.BIOME_NAME.to_upper(), Background.BIOME_SUB], 4.0)
	bosses_killed = 0
	evac_windows = 0
	rerolls = 2
	bans = 2
	banned = {}
	locked = {}
	streak = 0
	streak_t = 0.0
	best_streak = 0
	near_misses = 0
	rare_picks = 0
	rare_reasons = []
	course_log = []
	meta_award = {}
	_slow_t = 0.0
	offer_rare = false
	activities_done = 0
	radio_t = 0.0
	tail_kills = 0
	level_at_5 = 0
	camera.global_position = Vector2.ZERO
	camera.reset_smoothing()


func _process(delta: float) -> void:
	_handle_global_input()
	if _autotest:
		_run_autotest(delta)
	if _args.has("--shots"):
		_debug_screenshots(delta)

	if _args.has("--fxtest") and state == "playing" and is_instance_valid(player):
		_fx_t += delta
		if _fx_t > 1.0 and not _shots_done.has("fx_a"):
			if not _fx_fired:
				_fx_fired = true
				_fx_at = _fx_t
				var c := player.global_position + Vector2(260, -120)
				fx.explosion(c, 34.0)
				fx.explosion(c + Vector2(-420, 160), 16.0)
				projectiles.aoe(c + Vector2(120, 260), 130.0, 0.0, "тест")
			elif _fx_t - _fx_at > 0.12:
				_shot("fx_a")
		elif _shots_done.has("fx_a") and not _shots_done.has("fx_b") and _fx_t - _fx_at > 0.45:
			_shot("fx_b")
		elif _shots_done.has("fx_b") and not _shots_done.has("fx_c") and _fx_t - _fx_at > 1.1:
			_shot("fx_c")
			get_tree().quit()
	if state in ["dead", "evac"]:
		result_t += delta / maxf(Engine.time_scale, 0.01)
	if _slow_t > 0.0 and state == "playing":
		_slow_t -= delta / maxf(Engine.time_scale, 0.01)
		Engine.time_scale = base_ts * (0.3 if _slow_t > 0.0 else 1.0)
	if state == "playing" and not is_dead:
		_fps_acc += Engine.get_frames_per_second()
		_fps_n += 1
		run_time += delta
		if level_at_5 == 0 and run_time >= 300.0:
			level_at_5 = level
		streak_t -= delta
		if streak_t <= 0.0:
			streak = 0
		if pending_levels > 0:
			_open_levelup()
	banner_t = maxf(0.0, banner_t - delta / maxf(Engine.time_scale, 0.01))
	radio_t = maxf(0.0, radio_t - delta / maxf(Engine.time_scale, 0.01))
	_state_t += delta / maxf(Engine.time_scale, 0.01)

	if state in ["menu", "settings"] and menu.back_state == "menu":
		# фон меню: камера медленно плывёт над биомом
		camera.global_position += Vector2(70.0, -30.0) * delta / maxf(Engine.time_scale, 0.01)
		camera.zoom = camera.zoom.lerp(Vector2(0.75, 0.75), 0.05)
		sfx.music("menu")
		return
	# Музыка: меню / бой / ас (если файлы есть в audio/)
	if state == "class_select":
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
		# сглаживание камеры расходится при низком FPS (шаг > 1) — тогда без сглаживания
		camera.position_smoothing_enabled = delta * camera.position_smoothing_speed < 0.5
		# Камера чуть отъезжает на скорости — ощущение разгона
		var f := clampf(player.velocity.length() / maxf(player.cruise_speed(), 1.0), 0.5, 1.8)
		var z := Tuning.g("camera_zoom") / lerpf(1.0, player.size, 0.35) / (1.0 + maxf(0.0, f - 1.0) * 0.3)
		camera.zoom = camera.zoom.lerp(Vector2(z, z), 1.0 - exp(-delta * 3.0))
		sfx.set_engine(player.velocity.length() / player.cruise_speed(), player.hp > 0.0 and state == "playing")

	if shake > 0.0 and state == "playing":
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		shake = maxf(0.0, shake - 40.0 * delta)
	else:
		camera.offset = Vector2.ZERO


func _handle_global_input() -> void:
	if report != null and report.visible:
		return
	match state:
		"menu", "settings":
			return
		"codex":
			if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("loadout"):
				_set_state(codex_back)
			return
		"hangar":
			if Input.is_action_just_pressed("pause"):
				start_run()
				_set_state("menu")
			return
		"class_select":
			if Input.is_action_just_pressed("pause"):
				_set_state("menu")
				return
			for i in 3:
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					select_class(PlaneClasses.LIST[i])
					return
			if Input.is_action_just_pressed("toggle_scheme"):
				_cycle_scheme()
			return
		"course_pick":
			for i in course_offers.size():
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					choose_course(i)
					return
			return
		"levelup":
			for i in offers.size():
				if Input.is_action_just_pressed("choose_%d" % (i + 1)):
					choose_card(i)
					return
			if Input.is_action_just_pressed("reroll"):
				reroll()
			return
		"dead", "evac":
			if Input.is_action_just_pressed("restart") and result_t < 0.5:
				return
			if Input.is_action_just_pressed("ui_hangar"):
				ui_click("to_hangar")
				return
			if Input.is_action_just_pressed("restart"):
				restart()
			elif Input.is_action_just_pressed("change_class"):
				restarts += 1
				start_run()
				_set_state("class_select")
			return
	if Input.is_action_just_pressed("toggle_tuning") and DEBUG:
		tuning_panel.toggle()
	if Input.is_action_just_pressed("toggle_numbers"):
		Tuning.set_param("damage_numbers", 1.0 - Tuning.g("damage_numbers"))
	if Input.is_action_just_pressed("toggle_sprites") and DEBUG:
		Tuning.set_param("sprites", 1.0 - Tuning.g("sprites"))
	if Input.is_action_just_pressed("toggle_scheme"):
		_cycle_scheme()
	if (Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("loadout")) and not tuning_panel.visible:
		_set_state("paused" if state == "playing" else "playing")
	if state == "playing" and DEBUG:
		# Отладка для плейтеста
		if Input.is_action_just_pressed("debug_level"):
			pending_levels += 1
		if Input.is_action_just_pressed("debug_skip"):
			var nb := (floorf(run_time / Tuning.g("boss_every")) + 1.0) * Tuning.g("boss_every")
			run_time = maxf(run_time, nb - 10.0)
			show_banner("Отладка: перемотка к следующему асу")
		if Input.is_action_just_pressed("debug_activity"):
			spawner.start_activity(player, run_time, true)
		if Input.is_action_just_pressed("debug_god"):
			god_mode = not god_mode
			show_banner("Отладка: неуязвимость %s" % ("ВКЛ" if god_mode else "ВЫКЛ"))


func _cycle_scheme() -> void:
	Tuning.set_param("scheme", float((int(Tuning.g("scheme")) + 1) % 3))


func ui_click(action: String) -> void:
	# Клики мышью по интерфейсу (HUD передаёт сюда)
	if action == "menu_play":
		_set_state("class_select")
	elif action == "menu_hangar" or action == "to_hangar":
		hangar_back = "menu"
		if state in ["dead", "evac"]:
			start_run()
		hangar_cls = cls_id if action == "to_hangar" else hangar_cls
		_set_state("hangar")
	elif action.begins_with("hg:"):
		_hangar_action(action.substr(3))
	elif action == "menu_codex" or action == "codex":
		codex_back = "menu" if state == "menu" else "paused"
		_set_state("codex")
	elif action == "codex_back":
		_set_state(codex_back)
	elif action == "menu_settings":
		menu.open_settings("menu")
	elif action == "pause_settings":
		menu.open_settings("paused")
	elif action == "report_open":
		report.open()
	elif action == "menu_logs":
		OS.shell_open(ProjectSettings.globalize_path("user://"))
	elif action == "menu_howto":
		menu.howto = true
	elif action == "menu_quit":
		get_tree().quit()
	elif action == "to_menu":
		start_run()
		_set_state("menu")
	elif action == "class_back":
		_set_state("menu")
	elif action.begins_with("skill:"):
		var parts := action.split(":")
		if not Profile.skill_unlocked(parts[1], parts[2]):
			return
		skill_pick[parts[1]] = parts[2]
		Profile.set_skill(parts[1], 0, parts[2])
		sfx.play("card", -12.0, 1.4)
	elif action.begins_with("class:"):
		select_class(action.substr(6))
	elif action.begins_with("course:"):
		choose_course(int(action.substr(7)))
	elif action == "change_course":
		change_course()
	elif action.begins_with("card:"):
		choose_card(int(action.substr(5)))
	elif action.begins_with("prio:"):
		cycle_priority(int(action.substr(5)))
	elif action.begins_with("trig:"):
		var g: Hardpoint = player.groups[int(action.substr(5))]
		g.trigger = "button" if g.trigger == "auto" else "auto"
		sfx.play("card", -14.0, 1.3)
	elif action.begins_with("lock:"):
		lock_card(int(action.substr(5)))
	elif action.begins_with("ban:"):
		ban_card(int(action.substr(4)))
	elif action == "reroll":
		reroll()
	elif action == "resume":
		_set_state("playing")
	elif action == "restart":
		restart()
	elif action == "change_class":
		restarts += 1
		start_run()
		_set_state("class_select")


func cycle_priority(gi: int) -> void:
	var g: Hardpoint = player.groups[gi]
	if g.is_empty() or not Weapons.DEFS[g.weapon]["uses_priority"]:
		return
	var i := Weapons.PRIORITIES.find(g.priority)
	g.priority = Weapons.PRIORITIES[(i + 1) % Weapons.PRIORITIES.size()]
	sfx.play("card", -14.0, 1.3)


func restart() -> void:
	restarts += 1
	start_run()
	_set_state("playing")


# ---------- Опыт и карточки ----------

func xp_need() -> float:
	# 2.8: кривая круче — к 15:00 ~35-й уровень (было 60–70)
	# 3.1: мягче — к 15:00 ~35-й уровень и больше выборов в первой половине (было 4 + 3k + 0,25k²)
	return 4.0 + (level - 1) * 2.0 + 0.07 * pow(level - 1, 2.0)


func add_xp(v: float) -> void:
	if is_dead:
		return
	xp += v * Tuning.g("xp_mult")
	while xp >= xp_need():
		xp -= xp_need()
		level += 1
		pending_levels += 1


func _open_levelup() -> void:
	# 3.2: сначала — выбор курса (на 3-м повышении и после каждой открытой связки)
	if Cards.need_course(player):
		_open_course()
		return
	offer_rare = rare_picks > 0
	offers = Cards.offer(player, OFFER_COUNT, banned, locked, 2 if offer_rare else 0)
	if offers.is_empty():
		pending_levels = 0
		return
	_set_state("levelup")
	sfx.play("levelup", -8.0)


func choose_card(i: int) -> void:
	if state != "levelup" or i < 0 or i >= offers.size():
		return
	var c: Dictionary = offers[i]
	if not locked.is_empty() and c["id"] == locked["id"]:
		locked = {}
	Cards.on_declined(player, offers, c)
	Cards.apply(player, c)
	sfx.play("card", -8.0)
	pending_levels -= 1
	if offer_rare:
		rare_picks -= 1
		if not rare_reasons.is_empty():
			rare_reasons.pop_front()
	if Cards.need_course(player):
		_open_course()
	elif pending_levels > 0:
		offer_rare = rare_picks > 0
		offers = Cards.offer(player, OFFER_COUNT, banned, locked, 2 if offer_rare else 0)
	else:
		_set_state("playing")
		player.invuln = maxf(player.invuln, 1.0)


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
	if state != "course_pick" or i < 0 or i >= course_offers.size():
		return
	player.course = course_offers[i]
	course_log.append("%d:%s>%s" % [int(run_time), "/".join(PackedStringArray(course_offers)), course_offers[i]])
	sfx.play("card", -8.0, 0.9)
	if pending_levels > 0:
		offer_rare = rare_picks > 0
		offers = Cards.offer(player, OFFER_COUNT, banned, locked, 2 if offer_rare else 0)
		_set_state("levelup")
	else:
		_set_state("playing")
		player.invuln = maxf(player.invuln, 1.0)


# ---------- 3.2: ангар ----------

func _hangar_action(a: String) -> void:
	var p := a.split(":")
	var c := hangar_cls
	var ok := true
	match p[0]:
		"cls":
			hangar_cls = p[1]
		"tab":
			hangar_tab = p[1]
		"node":
			ok = Profile.buy_node(c, p[1])
		"plane2":
			ok = Profile.buy_plane2(c)
		"wsel":
			hangar_w = p[1]
		"tier":
			var w := p[1]
			var t := int(p[2])
			if Profile.tier_state(w, t) == "?":
				Profile.choose_paid(w, t, p[3])
			else:
				ok = Profile.pick_tier(w, t, p[3])
		"redo":
			ok = Profile.redo_tier(p[1], int(p[2]))
		"perk":
			Profile.toggle_perk(c, p[1])
		"perk_reset":
			Profile.cls(c)["perks"] = []
			Profile.save()
		"slot":
			Profile.set_skill(c, int(p[1]), p[2])
			if int(p[1]) == 0:
				skill_pick[c] = p[2]
		"callsign":
			Profile.next_callsign(c)
		"fly":
			skill_pick[c] = Profile.skills(c)[0]
			select_class(c)
			return
		"back":
			start_run()
			_set_state("menu")
			return
		"dbg_parts":
			Profile.debug_parts(1000)
		"dbg_lvl":
			Profile.debug_level(c)
		"dbg_all":
			Profile.debug_all()
		"dbg_wipe":
			Profile.wipe()
	sfx.play("card" if ok else "ui_ban", -10.0, 1.2 if ok else 0.8)


## «Сменить курс» на экране выбора — за 1 переброс
func change_course() -> void:
	if state != "levelup" or rerolls <= 0:
		return
	rerolls -= 1
	player.course = ""
	_open_course()


var _slow_t := 0.0
var _fx_t := 0.0
var _fx_at := 0.0
var _fx_fired := false


## Замедление времени (открытие связки) — срабатывает, когда игра снова идёт
func slowmo(t: float) -> void:
	_slow_t = t


func reroll() -> void:
	if state != "levelup" or rerolls <= 0:
		return
	rerolls -= 1
	offers = Cards.offer(player, OFFER_COUNT, banned, locked, 2 if offer_rare else 0)
	sfx.play("card", -10.0, 0.8)


## Закрепить карточку: она гарантированно будет в следующем выборе (и переживёт переброс).
## Повторный клик — открепить.
func lock_card(i: int) -> void:
	if state != "levelup" or i < 0 or i >= offers.size():
		return
	if not locked.is_empty() and locked["id"] == offers[i]["id"]:
		locked = {}
	else:
		locked = offers[i].duplicate()
	sfx.play("card", -12.0, 1.5)


## Исключить карточку из выпадения до конца вылета; на её место — новая.
func ban_card(i: int) -> void:
	if state != "levelup" or bans <= 0 or i < 0 or i >= offers.size():
		return
	var c: Dictionary = offers[i]
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


func radio(from: String, text: String) -> void:
	radio_from = from
	radio_text = text
	radio_t = 3.5
	sfx.play("radio", -18.0, 2.2)


func on_activity_success(kind: String) -> void:
	activities_done += 1
	if _autotest:
		print("AUTOTEST: activity success ", kind, " at %.0f" % run_time)
	if kind == "ground":
		# 3.1: награда понятнее — внеочередной выбор из редких карточек (как за аса)
		pending_levels += 1
		rare_picks += 1
		rare_reasons.append("ЗА ПОЗИЦИЮ ПВО")
		player.add_course_pts(1)
		parts += 40.0 * continue_mult()
		show_banner("Позиция ПВО уничтожена! Награда: выбор из редких карточек и +40 запчастей", 4.0)
	else:
		pending_levels += 1
		rare_picks += 1
		rare_reasons.append("ЗА АСА")
		player.add_course_pts(1)
		show_banner("Ас-соперник сбит! Выбор из редких карточек", 4.0)
	sfx.play("evac", -4.0, 1.3)


func on_activity_failed(kind: String, who := "") -> void:
	if _autotest:
		print("AUTOTEST: activity failed ", kind, " at %.0f" % run_time)
	if kind == "dogfight":
		show_banner("Ас «%s» ушёл — награды нет" % who, 3.0)


func streak_mult() -> float:
	return 1.0 + minf(streak, 30) * 0.03


func on_near_miss(kind: String) -> void:
	near_misses += 1
	streak_t = maxf(streak_t, 1.5) # пролёт на волоске поддерживает серию
	fx.text(player.global_position + Vector2(0, -50), "На волоске!" if kind == "пуля" else "Ракета мимо!", Color(0.6, 0.95, 1.0))
	sfx.play("near_miss", -16.0, 1.6)


# ---------- Асы и эвакуация ----------

func boss_alive() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if (n as Enemy).is_boss:
			return true
	return false


func on_boss_wave(wave: int, n: int) -> void:
	show_banner("АС НА ПОДХОДЕ!  (%d)" % n if n > 1 else "АС НА ПОДХОДЕ!", 4.0)
	sfx.play("boss", -2.0)
	add_shake(6.0)


func show_banner(text: String, dur := 3.0) -> void:
	if _autotest:
		print("BANNER %.0f: %s" % [run_time, text])
	banner = text
	banner_t = dur


func _open_evac() -> void:
	if is_instance_valid(evac):
		return
	evac = EvacZone.new()
	evac.setup(player.global_position, player.heading)
	world.add_child(evac)
	evac_windows += 1
	show_banner("Эвакуация: пролетите через 3 ворот по порядку", 5.0)
	sfx.play("evac", -6.0)


func on_evac_success() -> void:
	parts_kept = int(parts)
	_award("evac")
	_log_run("эвакуация")
	_set_state("evac")
	sfx.play("evac", -2.0, 1.2)


func on_evac_closed() -> void:
	show_banner("Окно эвакуации закрыто — следующее после следующего аса", 4.0)


func continue_mult() -> float:
	# Продолжение после 15-й минуты: +10% к добыче за каждую минуту
	return 1.0 + 0.1 * maxf(0.0, (run_time - 900.0) / 60.0)


# ---------- Статистика ----------

func add_stat(group: String, key: String, v: float) -> void:
	var d: Dictionary = stats[group]
	d[key] = float(d.get(key, 0.0)) + v


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

func on_enemy_hit(e: Enemy, dmg: float) -> void:
	fx.hit_spark(e.global_position)
	if Tuning.g("damage_numbers") > 0.5:
		fx.number(e.global_position + Vector2(0, -e.radius), dmg)
	sfx.play("hit", -18.0)


func on_enemy_killed(e: Enemy) -> void:
	kills += 1
	if is_instance_valid(player):
		player.on_kill(e)
	add_stat("kills_by", e.kind(), 1.0)
	streak += 1
	streak_t = 2.5
	best_streak = maxi(best_streak, streak)
	if is_instance_valid(player) and player.on_tail() and player.tail_target == e:
		tail_kills += 1
		e.xp = int(ceil(e.xp * 1.5))
		fx.text(e.global_position + Vector2(0, -30), "Сбит с хвоста!", Color(1.0, 0.9, 0.4))
	parts += e.parts * continue_mult() * streak_mult() * (1.5 if (e.is_ground and is_instance_valid(player) and player.has_perk("a_grd2")) else 1.0)
	fx.explosion(e.global_position, e.radius * (1.3 if e.big else 1.0), not e.is_ground)
	sfx.play("explode_big" if e.big else "explode", -4.0 if e.big else -12.0)
	add_shake(e.kill_shake)
	if e.big:
		hitstop()
	if e.is_boss:
		bosses_killed += 1
		if is_instance_valid(player):
			player.add_course_pts(2) # 3.2: ас — +2 к курсу
		rerolls += 1
		bans += 1
		fx.text(e.global_position, "АС СБИТ!", Color(1.0, 0.8, 0.4))
		if not boss_alive():
			_open_evac()


func on_player_damaged(_amount: float) -> void:
	add_shake(10.0)
	hitstop()
	sfx.play("player_hit", -4.0)
	hud.flash_damage()


## 3.2: начисление в профиль (запчасти + жалованье, опыт экипажа) — сразу при конце вылета
var meta_award := {}


func _award(outcome: String) -> void:
	meta_award = Profile.award_run({"cls": cls_id, "outcome": outcome, "run_time": run_time, "level": level,
		"bosses": bosses_killed, "activities": activities_done, "parts_kept": parts_kept, "continue_mult": continue_mult()})
	result_t = 0.0


func on_player_dead() -> void:
	is_dead = true
	parts_kept = int(parts * 0.5)
	_award("dead")
	fx.explosion(player.global_position, 40.0)
	sfx.play("player_explode", 0.0, 0.7)
	add_shake(16.0)
	_log_run("гибель")
	_set_state_deferred_dead()


func _set_state_deferred_dead() -> void:
	# Даём взрыву доиграть, затем экран итогов
	await get_tree().create_timer(1.2, true, false, true).timeout
	if is_dead and state == "playing":
		_set_state("dead")


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount * Tuning.g("shake_mult"))


func hitstop() -> void:
	var ms := Tuning.g("hitstop_ms")
	if ms <= 0.0:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
	Engine.time_scale = base_ts


# ---------- Лог плейтеста ----------
## Каждый вылет (гибель или эвакуация) дописывается в user://playtest_log_v2.csv

## Источники нанесённого урона — отдельной колонкой каждый (2.4)
const LOG_DEALT := ["курсовое (авто)", "курсовое (ручн.)", "турели", "ракеты В-В", "НАР", "гондола", "бомбы",
	"огненный ковёр", "ведомые", "проход на форсаже", "бронещит", "щит аса", "противоракеты"]


func _log_run(outcome: String) -> void:
	menu.add_record(PlaneClasses.DATA[cls_id]["title"], outcome, run_time, level, kills)
	var path := "user://playtest_log_%s.csv" % BUILD
	var exists := FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	var head := "datetime;class;scheme;outcome;run_seconds;level;level_at_5min;kills;bosses;activities;parts_kept;restart_index"
	head += ";taken_ram;taken_bullets;taken_missiles;missile_hits;healed;dealt_total"
	for k in ["gun_auto", "gun_manual", "turrets", "aam", "rockets", "gunpod", "bombs", "carpet", "wingmen", "afterburner_pass", "shield_ram", "ace_shield", "flares_mirror"]:
		head += ";dealt_" + k
	head += ";shots;hits;peak_rev;near_misses;best_streak;tail_kills;banned;cards;synergies;max_hp"
	head += ";skill3;skill3_lvl;skill3_uses;tags;patches;evolutions;wingmen;intercepted;dealt_detail;taken_by"
	head += ";skill2;course_log;syn_open;course_pts;crew_lvl;crew_xp_gain;parts_total;nodes;plane2;perks;wbranch;meta_k"
	last_log_header = head
	if exists:
		f.seek_end()
	else:
		f.store_line(head)
	var row := PackedStringArray([Time.get_datetime_string_from_system(), cls_id, str(int(Tuning.g("scheme"))), outcome,
		"%.1f" % run_time, str(level), str(level_at_5), str(kills), str(bosses_killed), str(activities_done), str(parts_kept), str(restarts),
		str(stat("taken", "таран")), str(stat("taken", "пули")), str(stat("taken", "ракеты")),
		str(int(counters.get("missile_hits", 0))), str(int(counters.get("healed", 0))), str(total("dealt"))])
	for k in LOG_DEALT:
		row.append(str(stat("dealt", k)))
	row.append_array(PackedStringArray([str(shots), str(hits), str(int(round(peak_rev * 100.0))), str(near_misses), str(best_streak),
		str(tail_kills), " | ".join(PackedStringArray(banned.values())), " | ".join(PackedStringArray(player.cards_log)),
		_kv(player.syn), str(int(player.max_hp))]))
	# 3.1: навык, теги, нашивки (время), эволюции (время), ведомые, перехваты, урон по всем источникам
	var wl := PackedStringArray()
	for w in player.wingmen:
		wl.append("%s%d%s" % [(w as Wingman).type, (w as Wingman).lvl, "t" if (w as Wingman).temp else ""])
	var icp := int(counters.get("intercepted", 0)) + int(counters.get("intercepted_turrets", 0)) + int(counters.get("intercepted_skill", 0)) + int(counters.get("intercepted_wingmen", 0))
	row.append_array(PackedStringArray([player.skill3, str(player.s3_lvl()), str(int(counters.get("skill3_uses", 0))),
		_kv(player.tags), _kv(player.patch_times), _kv(player.evo_times), " ".join(wl), str(icp),
		_kv(stats["dealt"]), _kv(stats["taken_by"])]))
	var wb := PackedStringArray()
	for w in Profile.WEAPON_ORDER:
		wb.append("%s=%s%s" % [w, Profile.tier_state(w, 1), Profile.tier_state(w, 2)])
	row.append_array(PackedStringArray([player.skill_b, " | ".join(PackedStringArray(course_log)), _kv(player.syn), str(player.course_pts),
		str(Profile.crew_lvl(cls_id)), str(int(meta_award.get("xp_add", 0))), str(Profile.parts()), _kv(Profile.cls(cls_id)["nodes"]),
		str(Profile.plane2(cls_id)), ",".join(PackedStringArray(Profile.cls(cls_id)["perks"])), " ".join(wb), str(Tuning.g("meta_k"))]))
	last_log_row = ";".join(row)
	last_outcome = outcome
	f.store_line(last_log_row)
	f.close()


func _kv(d: Dictionary) -> String:
	var out := PackedStringArray()
	for k in d:
		var v = d[k]
		out.append("%s=%s" % [k, str(int(round(float(v)))) if (v is float or v is int) else str(v)])
	return " | ".join(out)


func _exit_tree() -> void:
	I = null


# ---------- Скриншоты для проверки сборки (-- --autotest --god --fast --shots) ----------

var _shot_t := 0.0
var _shots_done := {}


func _shot(name: String) -> void:
	if not _args.has("--shots") or _shots_done.has(name):
		return
	_shots_done[name] = true
	get_viewport().get_texture().get_image().save_png("user://shot_%s.png" % name)
	print("SHOT ", name)


var _rep_phase := 0

## 3.3-t2: отладка — заполнить и отправить отчёт с экрана итогов
func _report_test() -> void:
	if _rep_phase == 0:
		_shot("results_report_btn")
		report.open()
		report._set_rating(4)
		report._set_again("Да")
		report._boring.text = "Тест: середина вылета однообразная"
		report._unclear.text = "Тест: что даёт курс"
		report._comment.text = "Тест отправки, кириллица ёЁ, кавычки \" ; и перевод\nстроки"
		_rep_phase = 1
	elif _rep_phase == 1:
		_shot("report_form")
		report._send()
		_rep_phase = 2
	elif _rep_phase == 2 and not report._busy:
		_shot("report_done")
		print("REPORT status: ", report._status.text, " sent=", report_sent)
		_rep_phase = 3


var _mesa_phase := 0
var _mesa_at := 0.0

## 3.3: отладка — ставим самолёт прямо над горой и снимаем кадр (гора не должна пересекать самолёт)
func _mesa_test() -> void:
	if _mesa_phase == 0 and run_time > 4.0:
		var CH := Background.CHUNK
		for r in range(0, 12):
			for cx in range(-r, r + 1):
				for cy in range(-r, r + 1):
					var o := background.chunk_object(cx, cy)
					if not o.is_empty() and o["name"] == "o_mesa":
						player.global_position = o["pos"]
						camera.global_position = o["pos"]
						_mesa_phase = 1
						_mesa_at = run_time
						print("MESA at ", o["pos"], " size ", o["size"])
						return
	elif _mesa_phase == 1 and run_time - _mesa_at > 0.4:
		_shot("mesa_over")
		_mesa_phase = 2


func _debug_screenshots(delta: float) -> void:
	_shot_t += delta / maxf(Engine.time_scale, 0.01)
	if _state_t < 0.6:
		return
	if state == "menu" and _state_t > 1.0 and menu.howto:
		_shot("howto")
		menu.close_howto()
	elif state == "menu" and _state_t > 1.0:
		_shot("menu")
	if state == "settings":
		_shot("settings")
	if state == "class_select":
		_shot("class")
	if state == "levelup" and level >= 4:
		_shot("levelup")
	if state == "paused":
		_shot("loadout")
	if state == "codex":
		_shot("codex")
	if state == "playing" and run_time > 1.0 and run_time < 3.0:
		_shot("biome_banner")
	if _args.has("--reporttest") and state in ["dead", "evac"] and result_t > 1.5:
		_report_test()
	if state == "playing" and _args.has("--mesatest"):
		_mesa_test()
	if state == "playing" and run_time > 25.0:
		_shot("game_early")
	if state == "playing" and run_time > 100.0:
		_shot("game")
	if state == "playing" and player.plane_lvl == 2 and player._upgrade_flash > 0.6:
		_shot("upgrade")
	if state == "playing" and boss_alive() and run_time > Tuning.g("boss_every") + 6.0:
		_shot("boss")
	if state == "playing" and is_instance_valid(evac) and evac.passed >= 1:
		_shot("evac_zone")
	if state == "playing" and is_instance_valid(spawner.activity_node):
		var an: Node = spawner.activity_node
		if an is AASite and (an as AASite).active and (an as AASite).left() < 5:
			_shot("aa_site")
		if an is RivalAce and (an as Node2D).global_position.distance_to(player.global_position) < 500.0:
			_shot("dogfight")
	if (state == "evac" or state == "dead") and result_t > 3.5:
		_shot("result")
		get_tree().quit()


# ---------- Автотест (-- --autotest): бот летает, берёт карточки, умирает/эвакуируется и начинает заново ----------

var _bot_wait := 0.0
var _loadout_opened := false


func _run_autotest(delta: float) -> void:
	_autotest_t += delta
	_bot_wait -= delta / maxf(Engine.time_scale, 0.01)
	if _args.has("--shots") and state != "playing" and _state_t < 1.0:
		return # в режиме скриншотов даём экрану постоять
	match state:
		"menu":
			if _bot_wait <= 0.0:
				_bot_wait = 1.5
				if _args.has("--shots") and not _shots_done.has("hangar_crew"):
					Profile.debug_parts(3000)
					Profile.debug_level("fighter")
					Profile.debug_level("fighter")
					ui_click("menu_hangar")
				elif _args.has("--shots") and not _shots_done.has("settings"):
					menu.tab = 1
					menu.open_settings("menu")
				else:
					ui_click("menu_play")
			return
		"settings":
			if _bot_wait <= 0.0:
				_bot_wait = 1.0
				menu.close_settings()
			return
		"hangar":
			if _bot_wait <= 0.0:
				_bot_wait = 1.0
				if not _shots_done.has("hangar_plane"):
					if hangar_tab != "plane":
						hangar_tab = "plane"
						_hangar_action("node:armor")
						return
					_shot("hangar_plane")
					hangar_tab = "weapons"
					_hangar_action("tier:aam:1:a")
				elif not _shots_done.has("hangar_weapons"):
					_shot("hangar_weapons")
					hangar_tab = "crew"
					_hangar_action("perk:f_msl1")
				elif not _shots_done.has("hangar_crew"):
					_shot("hangar_crew")
				else:
					_hangar_action("back")
			return
		"class_select":
			if _bot_wait <= 0.0:
				_bot_wait = 1.5
				var forced := ""
				for a in _args:
					if String(a).begins_with("--class="):
						forced = String(a).substr(8)
				var cid: String = forced if forced != "" else PlaneClasses.LIST[restarts % 3]
				var sk := ""
				for a in _args:
					if String(a).begins_with("--skill="):
						sk = String(a).substr(8)
				if sk == "":
					sk = PlaneClasses.CLASS_SKILLS[cid][randi() % 3]
				skill_pick[cid] = sk
				print("AUTOTEST: class %s skill %s" % [cid, sk])
				select_class(cid)
			return
		"course_pick":
			if _bot_wait <= 0.0:
				_bot_wait = 0.3
				_shot("course")
				choose_course(0)
			return
		"levelup":
			if _bot_wait <= 0.0:
				_bot_wait = 0.3
				if _args.has("--bot=course"):
					for ci in offers.size():
						if offers[ci].get("course", false) or offers[ci]["kind"] in ["synergy", "skill_syn"]:
							choose_card(ci)
							return
				if _args.has("--shots") and level >= 6 and not _shots_done.has("loadout") and not _loadout_opened:
					_loadout_opened = true
					# один раз заглянуть в подвесы для скриншота
					choose_card(randi() % offers.size())
					_set_state("paused")
					return
				# проверка переброса / закрепления / исключения
				if level == 3 and bans > 0:
					ban_card(0)
				elif level == 4 and rerolls > 0:
					reroll()
				elif level == 5:
					lock_card(1)
				choose_card(randi() % offers.size())
			return
		"paused":
			if _bot_wait <= 0.0 and _shots_done.has("loadout"):
				if _args.has("--shots") and not _shots_done.has("codex"):
					ui_click("codex")
					return
				cycle_priority(0)
				_set_state("playing")
			return
		"codex":
			if _shots_done.has("codex"):
				ui_click("codex_back")
			return
		"dead", "evac":
			if _bot_wait <= 0.0:
				_bot_wait = 1.0
				print("AUTOTEST: %s at %.1f s, class %s, level %d, kills %d, bosses %d" % [state, run_time, cls_id, level, kills, bosses_killed])
				if not _args.has("--shots"):
					ui_click("change_class") # следующий вылет — другим классом
			return
	if int(_autotest_t * 10.0) % 100 == 0 and _args.has("--verbose-bot"):
		for n in get_tree().get_nodes_in_group("enemies"):
			if (n as Enemy).is_boss:
				print("BOSS hp %.0f shield %.0f dist %.0f t=%.0f" % [n.hp, n.shield, n.global_position.distance_to(player.global_position), run_time])
	# Короткая проверка РУД в схеме «влево/вправо»: 20–22 с держим W
	if run_time > 20.0 and run_time < 22.0:
		Tuning.set_param("scheme", 1)
		Input.action_press("move_up")
		return
	if run_time >= 22.0 and run_time < 22.1:
		print("AUTOTEST: throttle after W = %.2f" % player.throttle)
	Tuning.set_param("scheme", 0)
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	var phase := int(_autotest_t * 2.0) % 12
	var goal := Vector2.ZERO
	if is_instance_valid(evac) and not _args.has("--noevac"):
		goal = evac.target_pos() # бот летит через ворота эвакуации
	elif is_instance_valid(spawner.activity_node) and spawner.activity_node is AASite:
		goal = (spawner.activity_node as Node2D).global_position # бот летит штурмовать ПВО
	elif boss_alive():
		for n in get_tree().get_nodes_in_group("enemies"):
			if (n as Enemy).is_boss:
				goal = (n as Node2D).global_position # бот атакует аса
	elif int(_autotest_t) % 6 < 4:
		# бот собирает опыт: летит к ближайшему ромбу
		var best := 1200.0
		for it in pickups.items:
			var d := player.global_position.distance_to(it["p"])
			if d < best:
				best = d
				goal = it["p"]
	if goal != Vector2.ZERO:
		var to := goal - player.global_position
		Input.action_press("move_right" if to.x > 0 else "move_left", minf(1.0, absf(to.x) / 200.0))
		Input.action_press("move_down" if to.y > 0 else "move_up", minf(1.0, absf(to.y) / 200.0))
	elif phase < 6:
		Input.action_press("move_left")
	else:
		Input.action_press("move_up")
	_tap("roll", phase == 2)
	_tap("afterburner", phase == 5)
	_tap("sharp_turn", phase == 8)
	_tap("toggle_fire_mode", phase == 9 and int(_autotest_t) % 24 == 4)
	if phase >= 9:
		Input.action_press("fire")
	else:
		Input.action_release("fire")
	if _args.has("--shots") and run_time < Tuning.g("boss_every") - 20.0 and run_time > 110.0:
		run_time = Tuning.g("boss_every") - 20.0


func _tap(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func avg_fps() -> float:
	return _fps_acc / float(_fps_n) if _fps_n > 0 else 0.0
