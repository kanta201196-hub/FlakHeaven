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
## 3.5: неуязвимость после выбора карточки (было 1 с — к 15-й минуте набегало больше минуты)
const CARD_INVULN := 0.5
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
const BUILD := "3.4-t1"
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
var _args: PackedStringArray
var input_ctl: MainInput   # глобальные клавиши, клики интерфейса, действия ангара
var dbg: MainDebug         # автотест, скриншоты, отладочные проверки
var tele := Telemetry.new() # 3.4: замеры для анализа правок (колонки в конце лога)


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
			Settings.gfx = clampi(int(a.substr(6)), 0, Settings.GFX_MAX)
			Settings.gfx_auto = false
		if a.begins_with("--tilt="):   # B-47: наклон камеры, град (проба; 0 — строго сверху)
			Tuning.set_param("cam_tilt", float(a.substr(7)))
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
	rerolls = 2 + Profile.extra_rerolls(cls_id) # 3.5: самолёт ур. 2 — +1 переброс
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
		player.invuln = maxf(player.invuln, CARD_INVULN)


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
		player.invuln = maxf(player.invuln, CARD_INVULN)


# ---------- 3.2: ангар ----------

## «Сменить курс» на экране выбора — за 1 переброс
func change_course() -> void:
	if state != "levelup" or rerolls <= 0:
		return
	rerolls -= 1
	player.course = ""
	_open_course()


var _slow_t := 0.0


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
	# 3.5: активности стали чаще (раз в минуту) — выбор из редких карточек за каждую вторую,
	# за остальные — ремонт 20% и запчасти, иначе сила игрока растёт ещё быстрее (лог 3.4-t1: Кит неуязвим с 12-й минуты)
	var rare := activities_done % 2 == 1
	var what := "Позиция ПВО уничтожена!" if kind == "ground" else "Ас-соперник сбит!"
	player.add_course_pts(1)
	if rare:
		pending_levels += 1
		rare_picks += 1
		rare_reasons.append("ЗА ПОЗИЦИЮ ПВО" if kind == "ground" else "ЗА АСА")
	else:
		player.heal(player.max_hp * 0.2)
	if kind == "ground":
		parts += 40.0 * continue_mult()
	if not rare:
		parts += 60.0 * continue_mult()
	show_banner("%s Награда: %s" % [what, "выбор из редких карточек" + (" и +40 запчастей" if kind == "ground" else "") if rare else "ремонт 20%% и +%d запчастей" % (100 if kind == "ground" else 60)], 4.0)
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
	# 3.5 (правка 30): время жизни аса — для лога
	for b in get_tree().get_nodes_in_group("enemies"):
		if b is Enemy and (b as Enemy).is_boss and not (b as Node).has_meta("born"):
			(b as Node).set_meta("born", run_time)
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
	RunLog.write(self, "эвакуация")
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
		if e.has_meta("born"):
			tele.boss_killed(run_time - float(e.get_meta("born")))
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
