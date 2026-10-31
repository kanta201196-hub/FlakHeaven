class_name Spawner
extends Node
## Волны врагов по времени вылета (время берётся у Main — его можно перемотать клавишей F6).
## Враги появляются за краем экрана. Прочность растёт со временем: ×1,7 к 5-й минуте, ×2,3 к 10-й.
## Каждые 5 минут — ас (мини-босс); пока он жив, обычных врагов вдвое меньше.

var _drone_cd := 3.0
var _carrier_cd := 25.0
var _icpt_cd := 40.0
var boss_wave := 0
## Активности: с 1:00 каждую минуту (3.5, было 2,5 мин), по очереди «позиция ПВО», «догфайт»,
## «охота на транспорт», «наземный конвой» (A-03, решение Kanta 17.10: четвёртая в очереди).
## Не стартуют, пока жив ас или идёт прошлая активность.
var next_activity := 60.0
var activity_i := 0
var activity_node: Node = null
var fuel: Fuel = null   # 3.5: топливо и свой заправщик
const ACTIVITIES := ["ground", "dogfight", "transport", "convoy", "fort"]
## EX-03 (отзывы внешних тестеров 21.10): «очередь на атаку» — одновременно заходят не больше attack_slots()
## дронов и ракетоносцев, остальные ждут поодаль и не стреляют. Толпа вокруг игрока не кружит «вальс».
var _attackers: Array = []
const TRANSPORT_TTK := 12.0


func _ready() -> void:
	fuel = Fuel.new()
	fuel.capacity = Fuel.CAPACITY * Profile.fuel_k(Main.I.cls_id)
	fuel.left = fuel.capacity
	add_child(fuel)
	if OS.get_cmdline_user_args().has("--dogfight"):
		activity_i = 1      # проверка: сразу догфайт
		next_activity = 20.0
	if OS.get_cmdline_user_args().has("--transport"):
		activity_i = 2      # проверка: сразу транспорт
		next_activity = 20.0
	if OS.get_cmdline_user_args().has("--convoy"):
		activity_i = 3      # проверка: сразу конвой
		next_activity = 10.0
	if OS.get_cmdline_user_args().has("--fort"):
		activity_i = 4      # check: the fortified area first (FA-01)
		next_activity = 10.0
	if OS.get_cmdline_user_args().has("--warship"):   # проверка «Архипелага»: корабль-босс на 1:00 (--leviathan — «Левиафан»)
		Tuning.set_param("boss_every", 60.0)
	_heli_test = OS.get_cmdline_user_args().has("--heli")   # проверка: вертолёты «Сарыч» без конвоя (в игре — прикрытие конвоя, M-41)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--fuel="): # проверка: начать с неполным баком (доля 0–1)
			fuel.left = fuel.capacity * clampf(float(String(a).substr(7)), 0.0, 1.0)
var _heli_test := false
var _ekr_test := OS.get_cmdline_user_args().has("--ekr")
var _ekr_cd := 0.0
var _gull_cd := 6.0
var _heli_cd := 8.0
var _grid := {}
const CELL := 90.0

## 3.5: урон игрока за последние 60 с — по нему считается прочность асов и бункера.
## Иначе к 10–15-й минуте урон игрока растёт в ~30 раз, а прочность врагов — в ~3, и ас живёт 3–6 с.
var _dealt_hist := PackedFloat32Array()   # сумма урона на каждую секунду вылета
var _dealt_tick := 0.0
## Сколько секунд ас должен выдерживать сосредоточенный огонь (по номеру волны асов)
const BOSS_TTK := [14.0, 24.0, 28.0]   # EX-06: было 25/30/35 — щит теперь держит «не тот» урон втрое лучше
## S9-24 (Kanta: первого аса не пройти на «Осе» и «Ките»; замер 23.10, по 2 вылета на класс): бой с первым асом
## шёл 28–83 с вместо ~27, «Оса» теряла за него 43–190% прочности. Первый ас: 20 → 14 с урона игрока,
## у «Кита» поправка — в single_k (лог Kanta s9: доля урона по асу 0,3 вместо 0,98 по формуле)

## Правка 3.5-s4 «напряжение боя» (лог «Осы» 3.5-s3: урон игрока за минуту вырос в 900 раз, прочность врагов —
## в 8; после 8-й минуты враги гибли, не долетев, прочность 100%): спавнер подстраивает прочность новых врагов.
## Тест 3.5-s6 («Грач» Kanta): старый замер (медиана жизни сбитых) видел только тех, кого успели сбить, —
## недобитые толстые в него не попадали, и множитель дошёл до ×24, хотя сбитых в минуту стало втрое меньше.
## Теперь замер по закону Литтла: время до сбития = (среднее число врагов в воздухе) / (сбитых в секунду) —
## он учитывает и недобитых. Врагов в воздухе почти всегда у предела (enemy_cap), так что по сути это
## скорость сбития: сбивают медленнее цели — прочность вниз, быстрее — вверх. Прочнее не больше ×4:
## дальше сильный билд получает больше врагов (до ×1,5 плотности), а не толще.
const PRESSURE_FROM := 240.0      # с 4:00
const PRESSURE_STEP := 5.0
const PRESSURE_WIN := 30.0        # окно замера, с
const PRESSURE_MAX := 4.0
const PRESSURE_UP := 1.1          # за шаг (5 с) не быстрее
const PRESSURE_DOWN := 0.85
## Цель: время до сбития 12 с в начале, 15,6 с к 14:00 (поздние враги держатся дольше ранних).
## При ~60 врагах в воздухе это ~5 сбитых в секунду в начале и ~4 к концу. Эталон по 2–4-й минуте не годится:
## в начале врагов уже у предела, а сбивают по 0,2–1 в секунду — эталон выходил бы за минуту.
const TTK_TARGET := 12.0
const DENS_MAX := 1.5
var pressure_k := 1.0
var pressure_dens := 1.0          # множитель плотности волн, когда прочность упёрлась в потолок
var _lives: Array = []            # [время гибели, сколько жил]
var _air_hist: Array = []         # [время, врагов в воздухе] раз в секунду, пока нет аса
var _press_t := 0.0


func dealt_total() -> float:
	var sum := 0.0
	for v in (Main.I.stats["dealt"] as Dictionary).values():
		sum += float(v)
	return sum


## Тест 3.5-s5 (п. 10, лог «Грача 2»): сколько урона игрок на деле кладёт в аса.
## Средний урон за минуту «Грач» набирает по толпе (залпы НАР, ведомые, связки), а по одному вёрткому асу бьёт
## в разы слабее — прочность аса от среднего урона выходила ему не по силам. Каждую секунду, пока ас рядом,
## пишем [урон по асу за секунду, средний урон в секунду]; их отношение — доля урона, которая достаётся асу
## (у «Осы» с самонаводящимися ракетами ~1,6, у «Грача» меньше). Первый ас — по-старому (×1,6), следующие —
## по тому, как шёл бой с прошлыми.
const SINGLE_K_DEF := 1.6     # данных мало — как было (подобрано по логу «Осы»)
const SINGLE_K_MIN := 0.35
const SINGLE_K_FIRST := 1.4   # первый ас: по асу волны попадают лучше, чем по асу-сопернику в дуэли
const SINGLE_K_SECS := 15     # сколько секунд рядом с асом нужно для оценки
var _big_dmg := 0.0
var _big_hist: Array = []
var last_single_k := SINGLE_K_DEF
var _big_boss_seen := false   # в замере уже есть бой с асом волны (не только дуэль)


func note_big(d: float, e: Enemy, source: String) -> void:
	if not e is Fortress:   # у «Крепости» фазы с неуязвимым корпусом и свой предел боя — не мерило
		_big_dmg += d
	if e is Boss:
		var dm: Dictionary = (e as Boss).log_entry.get("dmg", {})
		dm[source] = float(dm.get(source, 0.0)) + d


## Доля среднего урона, которая ложится в аса (за последние 4 минуты боя с асами и асом-соперником в дуэли:
## дуэль на 2:00 идёт раньше первого аса, и его прочность тоже считается по силе класса против одиночной цели)
func single_k() -> float:
	var s_d := 0.0
	var s_r := 0.0
	for e in _big_hist:
		s_d += float(e[0])
		s_r += float(e[1])
	if _big_hist.size() < SINGLE_K_SECS or s_r <= 0.0:
		return SINGLE_K_DEF
	var k := clampf(s_d / s_r, SINGLE_K_MIN, SINGLE_K_DEF)
	# только дуэль, асов ещё не было: ас-соперник вёрткий и уходит рывками — по нему попадают в разы хуже,
	# чем по асу волны (бот: 0,35 против 1,3–1,5), поэтому для первого аса — дуэль ×1,4 (не больше ×1,6).
	# S9-24, лог Kanta s9 («Кит», 5:00): было — середина между дуэлью и ×1,6 = 0,98, а по асу легло 0,3 среднего
	# урона (залпы НАР и бомбы — по толпе и земле): ас прожил 106 с и снял 370 прочности. Стало 0,35 × 1,4 = 0,49
	if not _big_boss_seen:
		k = minf(k * SINGLE_K_FIRST, SINGLE_K_DEF)
	return k


func _big_tick(p: Player) -> void:
	var near := false
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and ((e.is_boss and not e is Fortress) or e is RivalAce) and e.hp > 0.0 and e.global_position.distance_squared_to(p.global_position) < 900.0 * 900.0:
			near = true
			if e.is_boss:
				_big_boss_seen = true
			break
	var r := recent_dps()
	if near and r > 0.0:
		_big_hist.append([_big_dmg, r])
		if _big_hist.size() > 240:
			_big_hist.pop_front()
	_big_dmg = 0.0


## Средний урон игрока в секунду за последние 60 с
func recent_dps() -> float:
	var n := _dealt_hist.size()
	if n < 2:
		return 0.0
	var back := mini(60, n - 1)
	return (_dealt_hist[n - 1] - _dealt_hist[n - 1 - back]) / float(back)


func _process(delta: float) -> void:
	var m := Main.I
	var p := m.player
	if p == null or p.hp <= 0.0:
		return
	var t := m.run_time
	_build_grid()
	_dealt_tick += delta
	if _dealt_tick >= 1.0 or _dealt_hist.is_empty():
		_dealt_tick = 0.0
		_dealt_hist.append(dealt_total())
		_big_tick(p)
		if not m.boss_alive():
			_air_hist.append([t, air_count(get_tree().get_nodes_in_group("enemies"), true)])
			if _air_hist.size() > 300:
				_air_hist = _air_hist.slice(_air_hist.size() - 200)
		if _dealt_hist.size() > 120:
			_dealt_hist = _dealt_hist.slice(_dealt_hist.size() - 61)
	if Main.aces():
		_aces_tick(p, t, delta)
		return
	_pressure(t, delta)
	# Ас каждые 5 минут
	var due := int(t / Tuning.g("boss_every"))
	if due > boss_wave:
		boss_wave = due
		_spawn_bosses(p, boss_wave)

	if t >= next_activity:
		start_activity(p, t)
	_patrol(p, t, delta)

	# 3.1: пока жив ас — мелочи втрое меньше, чтобы до него можно было добраться
	var boss_on := m.boss_alive()
	var mult := Tuning.g("spawn_rate_mult") * Campaign.k("dens") * (0.3 if boss_on else 1.0) # U-05: плотность по сложности
	mult *= 1.0 + maxf(0.0, t - 300.0) / 60.0 * 0.05 # 2.8: после 5:00 — плотнее (+5% в минуту)
	mult *= pressure_dens
	var enemies := get_tree().get_nodes_in_group("enemies")
	# предел врагов в воздухе одновременно (без асов, наземных целей и целей активностей):
	# больше — экран превращается в кашу и проседает FPS
	if air_count(enemies) >= int(Tuning.g("enemy_cap")):
		return

	_drone_cd -= delta * mult
	if _drone_cd <= 0.0:
		_drone_cd = maxf(0.7, 2.6 - t * 0.008)
		if enemies.size() < 60:
			# 3.1: мелочи ~на 35% меньше (было 1+t/120 … 2+t/50)
			var count := randi_range(1 + int(t / 160.0), 2 + int(t / 75.0))
			var ang := randf() * TAU
			for i in count:
				var d := Drone.new()
				# 3.5: камикадзе выведен из игры (разбор каталога 16.10) — все дроны заходят цепью
				d.lane = (i - (count - 1) / 2.0) * 70.0
				_place(d, p, ang + randf_range(-0.2, 0.2), t)   # HP: DroneBalance via Drone.apply_hp_mult
				d.heading = (p.global_position - d.position).angle()

	# «Архипелаг» (E-07): экраноплан «Крачка» проходит по проливу раз в ~1,5 мин после 2:00 (--ekr — сразу)
	if Biome.sea() and t > (10.0 if _ekr_test else 110.0) and not Main.I.boss_alive():
		_ekr_cd -= delta
		if _ekr_cd <= 0.0:
			_ekr_cd = 25.0 if _ekr_test else randf_range(70.0, 95.0)
			var ek := Ekranoplan.new()
			ek.setup_run(p.global_position)
			Main.I.world.add_child(ek)
			ek.apply_hp_mult(hp_mult() * hp_ramp(t) * pressure_k)
			Events.banner.emit("Экраноплан «Крачка» идёт по проливу!", 2.5)
	# «Архипелаг»: чайки над берегом раз в 10–20 с (звуки PR #211)
	if Biome.sea():
		_gull_cd -= delta
		if _gull_cd <= 0.0:
			_gull_cd = randf_range(10.0, 20.0)
			var tr := Render3D.I.terrain if Render3D.I != null else null
			if tr != null:
				var rf := absf(tr.river_field(p.global_position.x, p.global_position.y))
				if rf > Terrain3D.SEA_W * 0.5 and rf < Terrain3D.SEA_W + 500.0:
					Main.I.sfx.play("gulls")
	_icpt_cd -= delta * mult
	if _icpt_cd <= 0.0:
		_icpt_cd = maxf(4.0, 11.0 - t * 0.02)
		var icpts := 0
		for n in enemies:
			if n is Interceptor:
				icpts += 1
		if icpts < mini(3 + int(t / 50.0), 14):
			var ang2 := randf() * TAU
			for i in randi_range(1, 2 + int(t / 240.0)):
				var f := Interceptor.new()
				_place(f, p, ang2 + randf_range(-0.2, 0.2), t)
				f.heading = (p.global_position - f.position).angle()

	# EX-04 Б2: звено бомбардировщиков проходит район раз в 100–130 с после 3:00 (--bombers — сразу)
	_bomber_cd -= delta
	if _bomber_cd <= 0.0 and t > (5.0 if _bomber_test else BOMBER_FROM) and not boss_on:
		_bomber_cd = 40.0 if _bomber_test else randf_range(100.0, 130.0)
		spawn_bombers(p, t)

	_carrier_cd -= delta * mult
	if _carrier_cd <= 0.0:
		_carrier_cd = 12.0
		var carriers := 0
		for n in enemies:
			if n is MissileCarrier:
				carriers += 1
		if carriers < mini(1 + int(t / 70.0), 7):
			var c := MissileCarrier.new()
			_place(c, p, randf() * TAU, t)
			c.heading = (p.global_position - c.position).angle()

	if _heli_test:
		_heli_cd -= delta
		if _heli_cd <= 0.0:
			_heli_cd = 14.0
			var helis := 0
			for n in enemies:
				if n is Helicopter:
					helis += 1
			if helis < 2:
				var h := Helicopter.new()
				_place(h, p, randf() * TAU, t)
				h.heading = (p.global_position - h.position).angle()


## «Битва асов» (AB-01): when the next rival ace takes off and the top-up timer of interceptors and carriers
var _ace_next := AcesBalance.ACE_FIRST
var _autotest := OS.get_cmdline_user_args().has("--autotest")
var _topup_cd := 1.0


## «Битва асов» spawn rules instead of the campaign ones: a few interceptors, more missile carriers, a rival ace
## every AcesBalance.ACE_EVERY s; fixed HP, no ramps, waves, activities or evacuation.
func _aces_tick(p: Player, t: float, delta: float) -> void:
	var icpts := 0
	var carriers := 0
	var rivals := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is RivalAce:
			rivals += 1
		elif n is Interceptor:
			icpts += 1
		elif n is MissileCarrier:
			carriers += 1
	if AcesBalance.ace_due(t, _ace_next, rivals):
		_ace_next = t + AcesBalance.ACE_EVERY
		var ace := RivalAce.new()
		ace.setup(AcesBalance.ACE_HP)
		ace.min_life = 0.0   # realistic damage: three missiles bring it down, no per-second cap
		var back := p.heading + PI + randf_range(-0.6, 0.6)
		ace.position = p.global_position + Vector2.from_angle(back) * 1100.0
		ace.heading = (p.global_position - ace.position).angle()
		Main.I.world.add_child(ace)
		if _autotest:
			print("AUTOTEST: aces mode — rival ace %s at %.0f (%d up)" % [ace.callsign, t, rivals + 1])
		Events.banner.emit(Loc.t("Вражеский ас «%s» заходит вам в хвост!") % Loc.t(ace.callsign), 3.0)
		Main.I.sfx.play("boss", -8.0, 1.4)
	_topup_cd -= delta
	if _topup_cd > 0.0:
		return
	_topup_cd = AcesBalance.TOPUP_EVERY
	if AcesBalance.needs("interceptor", icpts):
		_aces_place(Interceptor.new(), p, AcesBalance.INTERCEPTOR_HP, t)
	if AcesBalance.needs("carrier", carriers):
		_aces_place(MissileCarrier.new(), p, AcesBalance.CARRIER_HP, t)


## «Битва асов»: seconds until the next rival ace may take off (0 — it waits for a free slot).
func ace_next_in() -> float:
	return maxf(0.0, _ace_next - Main.I.run_time)


## Places `e` off screen like `_place`, with fixed `hp`: the mode has no HP ramp, difficulty or elite variants.
func _aces_place(e: Enemy, p: Player, hp: float, t: float) -> void:
	var far := 1.0 + 0.5 * sin(deg_to_rad(Tuning.g("cam_tilt")))
	e.position = p.global_position + Vector2.from_angle(randf() * TAU) * randf_range(1150.0, 1350.0) * far
	Main.I.world.add_child(e)
	e.hp = hp
	e.max_hp = hp
	e.born_t = t
	e.heading = (p.global_position - e.position).angle()


const BOMBER_FROM := 180.0
var _bomber_cd := 0.0
var _bomber_test := OS.get_cmdline_user_args().has("--bombers")


## EX-04 Б2: клин из трёх «Буйволов» проходит мимо игрока по прямой
func spawn_bombers(p: Player, t: float) -> void:
	var ang := randf() * TAU
	var far := 1.0 + 0.5 * sin(deg_to_rad(Tuning.g("cam_tilt")))
	var start := p.global_position + Vector2.from_angle(ang) * 1300.0 * far
	var aim := p.global_position + Vector2.from_angle(ang + PI / 2.0) * randf_range(-350.0, 350.0)
	var hd := (aim - start).angle()
	var lead: Bomber = null
	for slot in [Vector2.ZERO, Vector2(-170, -180), Vector2(-170, 180)]:
		var b := Bomber.new()
		b.heading = hd
		b.slot = slot
		b.lead = lead
		b.position = start + (slot as Vector2).rotated(hd)
		Main.I.world.add_child(b)
		b.apply_hp_mult(hp_mult() * hp_ramp(t) * pressure_k)
		b.born_t = t
		if lead == null:
			lead = b
	Events.banner.emit("Звено бомбардировщиков! Броня спереди, турель сзади — заходите сбоку", 3.0)
	Story.say(Story.DISPATCH, "Бомбардировщики идут к колонне! Броня спереди — заходите сбоку.")
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: bombers at %.0f" % t)


## Тест 3.5-s7 (Kanta, «бери в работу»): у «Кита» бомбы давали 1,5% урона — наземных целей на пути мало.
## Ему вне активностей раз в PATROL_EVERY с курс пересекает малая колонна (пикап, грузовик, техничка) —
## без баннера и таймера, груз с грузовиков как у конвоя
const PATROL_EVERY := 35.0
const PATROL_FROM := 45.0
const PATROL_RETRY := 6.0   # s: next try after a patrol found no road near the bomber's path
var _patrol_cd := PATROL_FROM
var _patrol_cv: Convoy = null


func _patrol(p: Player, t: float, delta: float) -> void:
	if p.cls_id != "bomber" or m_boss():
		return
	_patrol_cd -= delta
	if _patrol_cd > 0.0 or is_instance_valid(_patrol_cv):
		return
	_patrol_cd = PATROL_EVERY
	var cv := Convoy.new()
	cv.patrol = true
	var mid := p.global_position + Vector2.from_angle(p.heading + randf_range(-0.5, 0.5)) * 1100.0
	var side := 1.0 if randf() < 0.5 else -1.0
	cv.setup(mid, Vector2.from_angle(p.heading + side * PI / 2.0), hp_mult() * hp_ramp(t), recent_dps(), t)
	if cv.vehicles.is_empty():   # no road near the bomber's path (mountains): try again soon
		cv.free()
		_patrol_cd = PATROL_RETRY
		return
	Main.I.world.add_child(cv)
	_patrol_cv = cv
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: patrol column at %.0f" % t)


func start_activity(p: Player, t: float, force := false) -> void:
	if not force and (m_boss() or is_instance_valid(activity_node)):
		next_activity = t + 15.0
		return
	var kind_s: String = ACTIVITIES[activity_i % ACTIVITIES.size()]
	if Story.wants_rescue():
		kind_s = "rescue"   # EX-09: «Сухое русло» — первая активность вылета: сбитый пилот
		Story.rescue_done = true
		activity_i -= 1
	# FA-01: «Укрепрайон» takes a real map fort ahead; none in reach (or the sea biome) — next kind this round.
	# Kanta s13: the fort shows only for the activity (Render3D draws forts in forts_hit), so never one already
	# used this sortie and never one on screen, where it would pop up
	var fort: Dictionary = {}
	if kind_s == "fort":
		if not Biome.sea():
			var bg: Background = Main.I.background
			var min_d := ActivityBalance.min_dist(_screen_rect())
			var want := p.global_position + Vector2.from_angle(p.heading) * maxf(FortBalance.AHEAD, min_d + ActivityBalance.EXTRA)
			fort = FortArea.pick_fort(FortArea.forts_near(bg, want, FortBalance.REACH), want, FortBalance.REACH, bg.forts_hit,
				_view_rect(), p.global_position, min_d)
		if fort.is_empty():
			activity_i += 1
			kind_s = ACTIVITIES[activity_i % ACTIVITIES.size()]
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: activity start ", kind_s, " at %.0f" % t)
	activity_i += 1
	next_activity = t + Tuning.g("activity_every")
	var hp_k := hp_mult() * hp_ramp(t)
	if kind_s == "rescue":
		var rs := Rescue.new()
		rs.setup(p.global_position + Vector2.from_angle(p.heading + randf_range(-0.8, 0.8)) * 1500.0)
		Main.I.world.add_child(rs)
		activity_node = rs
		Events.banner.emit("Аварийный маяк! Наш пилот внизу — летите к нему", 4.0)
		Hints.show("act_rescue", "Сбитый пилот: летите по зелёной стрелке к маяку. Держитесь рядом 30 с, пока вертолёт его забирает. Отлетите — отсчёт встанет.", 9.0, 2)
	elif kind_s == "ground":
		var site := AASite.new()
		_place_aa(site, p, hp_k)
		Main.I.world.add_child(site)
		activity_node = site
		Events.banner.emit("Разведка: позиция ПВО! Награда — выбор из редких карточек", 4.0)
		Story.say(Story.DISPATCH, "Позиция ПВО ожила. Подавите — и небо станет тише.")
		Hints.show("act_aa", "Позиция ПВО: летите по голубой стрелке. Когда подлетите, пойдёт отсчёт — разбейте бункер в центре, пока он не кончился. Зенитки бьют издалека: заходите на скорости.", 9.0, 2)
	elif kind_s == "fort":
		var base := FortArea.new()
		base.setup_fort(fort, hp_k, recent_dps())
		Main.I.world.add_child(base)
		activity_node = base
		Events.banner.emit("Разведка: в старой крепости база противника! Награда — выбор из редких карточек", 4.0)
		Story.say(Story.DISPATCH, "В крепости засели зенитчики. Пусковые на башнях — снесите их.")
		Hints.show("act_fort", "Укрепрайон: летите по стрелке к крепости. На четырёх башнях пусковые ЗРК — разбейте все четыре, пока идёт отсчёт. Тепловые ловушки уводят их ракеты, джипы во дворе бьют из пулемётов.", 9.0, 2)
	elif kind_s == "convoy":
		var cv := Convoy.new()
		# колонна пересекает курс игрока впереди: маршрут через точку в 1 300 пикс. по курсу
		var mid := p.global_position + Vector2.from_angle(p.heading + randf_range(-0.4, 0.4)) * 1300.0
		var side := 1.0 if randf() < 0.5 else -1.0
		cv.setup(mid, Vector2.from_angle(p.heading + side * PI / 2.0), hp_k, recent_dps(), t)
		Main.I.world.add_child(cv)
		activity_node = cv
		if Biome.sea():
			Events.banner.emit("Разведка: караван снабжения идёт в гавань! Топите сухогрузы — груз ваш", 4.0)
			Hints.show("act_convoy_sea", "Караван: летите по оранжевой стрелке. Подбейте головное судно — караван встанет. С каждого потопленного сухогруза всплывает груз: запчасти и ремкомплекты.", 9.0, 2)
		else:
			Events.banner.emit("Разведка: колонна снабжения идёт к укрытию! Сожгите грузовики — груз ваш", 4.0)
			Story.say(Story.DISPATCH, "Колонна противника на дороге. Сожгите грузовики — груз наш.")
			Hints.show("act_convoy", "Конвой: летите по оранжевой стрелке. Подбейте головную машину — колонна встанет. С каждого сожжённого грузовика падает груз: запчасти и ремкомплекты.", 9.0, 2)
	elif kind_s == "transport":
		var tr := Transport.new()
		tr.setup(maxf(700.0 * hp_k, recent_dps() * TRANSPORT_TTK))
		# пересекает район впереди игрока поперёк курса
		var side := 1.0 if randf() < 0.5 else -1.0
		var mid := p.global_position + Vector2.from_angle(p.heading) * randf_range(500.0, 800.0)
		tr.heading = p.heading - side * PI / 2.0 + randf_range(-0.3, 0.3)
		tr.position = mid - Vector2.from_angle(tr.heading) * 1500.0
		Main.I.world.add_child(tr)
		tr.spawn_escort(3 + (1 if t > 480.0 else 0), hp_k)
		activity_node = tr
		Events.banner.emit("Разведка: вражеский транспортник с прикрытием! Сбейте его — груз ваш", 4.0)
		Hints.show("act_transport", "Транспортник летит через район и скоро уйдёт — розовая стрелка. Прикрытие отвлекает: бейте сам транспортник, груз падает с него.", 8.0, 2)
	else:
		var ace := RivalAce.new()
		ace.setup(Tuning.g("rival_hp") * hp_k)
		var back := p.heading + PI + randf_range(-0.6, 0.6)
		ace.position = p.global_position + Vector2.from_angle(back) * 1100.0
		ace.heading = (p.global_position - ace.position).angle()
		Main.I.world.add_child(ace)
		activity_node = ace
		Events.banner.emit("Дуэль: вражеский ас заходит вам в хвост!", 4.0)
		Hints.show("act_ace", "Дуэль с асом: он заходит в хвост. Сбросьте газ (S) или сделайте боевой разворот (E) — ас проскочит вперёд под вашу пушку.", 8.0, 2)
	Main.I.sfx.play("boss", -8.0, 1.4)


## S14-04 (Kanta 31.10): the AA site appears out of view and at least two screens from the player
## (ActivityBalance). Tries centres ahead and to the sides; none passes — the try whose nearest point is
## farthest from the player (the search for level ground can drag a site back toward the player).
func _place_aa(site: AASite, p: Player, hp_k: float) -> void:
	var min_d := ActivityBalance.min_dist(_screen_rect())
	var view := _view_rect()
	var tr := Terrain3D.active()
	var turn := randf_range(-0.3, 0.3)
	var best := PackedVector2Array()
	var best_d := -1.0
	for want in ActivityBalance.wants(p.global_position, p.heading + turn, min_d):
		var spots := AASite.place(tr, want, randf() * TAU, randf_range(0.9, 1.2))
		if ActivityBalance.far_ok(spots, p.global_position, min_d, view):
			best = spots
			break
		var d := ActivityBalance.near_dist(spots, p.global_position)
		if d > best_d:
			best_d = d
			best = spots
	site.setup_spots(best, hp_k, recent_dps())


## The visible screen in world px (2D camera; with the tilted 3D camera the ground seen is larger, see _view_rect).
func _screen_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()


## What the camera may show, with margins (the 3D view with tilt, else the 2D view).
func _view_rect() -> Rect2:
	if Render3D.enabled and Render3D.I != null and Render3D.view_now.has_area():
		return Render3D.view_now
	return Main.I.background._view()


## Прочность врагов: настройка × сложность операции кампании (U-05)
func hp_mult() -> float:
	return Tuning.g("enemy_hp_mult") * Campaign.k("hp")


func m_boss() -> bool:
	return Main.I.boss_alive()


func _spawn_bosses(p: Player, wave: int) -> void:
	var variants: Array = ["carrier"] if wave == 1 else (["interceptor"] if wave == 2 else ["carrier", "interceptor"])
	# 3.1: асы прочнее и растут вместе со временем вылета (как обычные враги)
	var hp := Tuning.g("boss_hp") * hp_mult() * 0.6 * hp_ramp(Main.I.run_time)
	# 3.5: не меньше, чем урон игрока за BOSS_TTK секунд (щит +35% сверху — поэтому делим)
	var ttk: float = BOSS_TTK[mini(wave - 1, BOSS_TTK.size() - 1)]
	# U-05: на сложных операциях асы держатся дольше (половина множителя прочности — иначе бой с асом затягивается)
	# правка 3.5-s4: ×1,6 — по асу бьёт всё сразу (лог «Осы»: 10–33 с вместо 25–35);
	# тест 3.5-s5 (п. 10): множитель — доля урона, что реально ложится в одиночную цель (single_k), у каждого свой
	last_single_k = single_k()
	var hp_formula := hp
	var hp_dps_k1 := recent_dps() * ttk / 1.35 * (1.0 + (Campaign.k("hp") - 1.0) * 0.5)
	var hp_dps := hp_dps_k1 * last_single_k
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: boss wave %d hp formula %.0f, by dps %.0f (dps %.0f, single_k %.2f из %d с)" % [wave, hp, hp_dps, recent_dps(), last_single_k, _big_hist.size()])
	if not OS.get_cmdline_user_args().has("--shots"): # скриншоты: асы нарочно слабые
		hp = maxf(hp, hp_dps)
	# «Архипелаг» (E-07, E-08): 10:00 — крейсер «Сторож», 15:00 — «Левиафан»; оба идут по фарватеру
	if Biome.sea() and (wave >= 2 or OS.get_cmdline_user_args().has("--warship")):
		var ws := Warship.new()
		var lev := wave >= 3 or OS.get_cmdline_user_args().has("--leviathan")
		ws.setup_ship("leviathan" if lev else "cruiser", hp * (2.0 if lev else 1.3) * 1.35, p.global_position)
		Main.I.world.add_child(ws)
		variants = []
	# 3.5 (разбор каталога 16.10): третья волна — босс «Крепость» вместо пары асов
	elif wave >= 3 or OS.get_cmdline_user_args().has("--fortress"):
		var f := Fortress.new()
		# GD-08: one landing share for every class instead of the duel share (see AceBalance.fortress_hp)
		var fhp := hp_formula if OS.get_cmdline_user_args().has("--shots") else AceBalance.fortress_hp(hp_formula, hp_dps_k1)
		last_single_k = AceBalance.FORTRESS_SINGLE_K   # the sortie log shows the share the Fortress was built with
		f.setup_fortress(fhp * 2.0 * 1.35) # прочность двух асов вместе со щитами; фазы делят её на точки и корпус
		f.position = p.global_position + Vector2.from_angle(randf() * TAU) * boss_dist()
		f.heading = (p.global_position - f.position).angle() + PI / 2.0
		Main.I.world.add_child(f)
		variants = []
	for v in variants:
		var b := Boss.new()
		b.setup(v, hp)
		b.position = p.global_position + Vector2.from_angle(randf() * TAU) * boss_dist()
		b.heading = (p.global_position - b.position).angle()
		Main.I.world.add_child(b)
	# мелочь расступается: дальние дроны разворачиваются и улетают (раньше пропадали на месте)
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Drone and (n as Node2D).global_position.distance_to(p.global_position) > 600.0:
			(n as Enemy).leave()
	Events.boss_wave.emit(wave, maxi(1, variants.size()))


## Planes in the air that count against enemy_cap; `no_drones` — for the pressure measure, which leaves drones out
## (Kanta 27.10: their HP follows the player's gun, so their kill rate says nothing about the others' strength)
func air_count(enemies: Array, no_drones := false) -> int:
	var n := 0
	for e in enemies:
		var en := e as Enemy
		if not en.is_boss and not en.is_ground and not en.no_despawn and not en.leaving and not (no_drones and en is Drone):
			n += 1
	return n


## Ас появляется за краем экрана (с наклоном камеры вверх видно дальше) и подлетает —
## у края экрана на него указывает стрелка
func boss_dist() -> float:
	return 1500.0 * (1.0 + 0.5 * sin(deg_to_rad(Tuning.g("cam_tilt"))))


## Сетка для расталкивания: враги держат вокруг себя небольшое пространство и не слипаются
func _build_grid() -> void:
	_grid.clear()
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		var key := Vector2i(int(floorf(e.global_position.x / CELL)), int(floorf(e.global_position.y / CELL)))
		if _grid.has(key):
			(_grid[key] as Array).append(e)
		else:
			_grid[key] = [e]


func separation(e: Enemy) -> Vector2:
	var push := Vector2.ZERO
	var c := Vector2i(int(floorf(e.global_position.x / CELL)), int(floorf(e.global_position.y / CELL)))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell: Array = _grid.get(c + Vector2i(dx, dy), [])
			for o in cell:
				if o == e or not is_instance_valid(o):
					continue
				var d: Vector2 = e.global_position - (o as Enemy).global_position
				# 3D-модели крупнее хитбокса (unit_scale) — держим просвет по картинке
				var min_d: float = (e.radius + (o as Enemy).radius) * 1.35 + 34.0
				var l := d.length()
				if l < min_d:
					if l < 0.01:
						d = Vector2.from_angle(randf() * TAU)
						l = 1.0
					var w := 1.0 if not (o as Enemy).is_boss else 2.5
					push += d / l * (min_d - l) / min_d * w
	return push


func _place(e: Enemy, p: Player, ang: float, t: float) -> void:
	# B-47: с наклоном камеры вверх по экрану видно дальше — появляемся дальше, чтобы не «возникать» в кадре
	var far := 1.0 + 0.5 * sin(deg_to_rad(Tuning.g("cam_tilt")))
	e.position = p.global_position + Vector2.from_angle(ang) * randf_range(1150.0, 1350.0) * far
	Main.I.world.add_child(e)
	e.apply_hp_mult(hp_mult() * hp_ramp(t) * pressure_k)
	e.born_t = t
	# 2.8: с 10-й минуты — элитные варианты (прочнее ×3, крупнее, больше опыта)
	# 3.1: элитные — с 6:00 и чаще (до 30%)
	if not e is Drone and t > 360.0 and randf() < clampf((t - 360.0) / 1500.0, 0.0, 0.3):
		e.make_elite()


## 2.8: прочность растёт со временем, после 5:00 — быстрее (+4% в минуту сверху).
## S6-02: было +8% — к 10:00 ×3,27, стало ×2,8 (решение Kanta 18.10)
static func hp_ramp(t: float) -> float:
	return (1.0 + t / 450.0) * (1.0 + maxf(0.0, t - 300.0) / 60.0 * 0.04)


## Сбит обычный самолёт — запомнить, сколько он прожил (дроны — нет: их прочность идёт от пушки игрока, DroneBalance)
func note_kill(e: Enemy) -> void:
	if e is Drone or e.born_t < 0.0 or e.is_boss or e.is_ground or e.no_despawn or Main.I.boss_alive():
		return
	var t := Main.I.run_time
	_lives.append([t, t - e.born_t])
	if _lives.size() > 400:
		_lives = _lives.slice(_lives.size() - 300)


## Сбитых в секунду и среднее число врагов в воздухе за [from_t, to_t]; [-1, -1], если окно почти всё шло с асом
func _flow(from_t: float, to_t: float) -> Vector2:
	var kills := 0
	for l in _lives:
		if float(l[0]) >= from_t and float(l[0]) <= to_t:
			kills += 1
	var n := 0
	var sum := 0.0
	for h in _air_hist:
		if float(h[0]) >= from_t and float(h[0]) <= to_t:
			n += 1
			sum += float(h[1])
	# окно с асом выпадает (замеры стоят): секунд без аса должно быть хотя бы две трети
	if n < int((to_t - from_t) * 0.66):
		return Vector2(-1.0, -1.0)
	return Vector2(float(kills) / float(n), sum / float(n))


func _pressure(t: float, delta: float) -> void:
	# второй список 3.5-s5, п. 5: пока жив ас, напряжение стоит. В бою с асом мелочи втрое меньше и её сбивают
	# мимоходом — по такой жизни «Грачу» Kanta за 50 с подняли прочность новых врагов с ×1 до ×3,2
	if Main.I.boss_alive():
		return
	_press_t -= delta
	if _press_t > 0.0:
		return
	_press_t = PRESSURE_STEP
	if t < PRESSURE_FROM:
		return
	var f := _flow(t - PRESSURE_WIN, t)
	if f.x < 0.0:
		return
	var ttk := f.y / maxf(f.x, 0.01)      # никого не сбили — прочность вниз на полный шаг
	var target := TTK_TARGET * lerpf(1.0, 1.3, clampf((t - PRESSURE_FROM) / 600.0, 0.0, 1.0))
	var step := clampf(pow(target / ttk, 0.5), PRESSURE_DOWN, PRESSURE_UP)
	if step > 1.0 and pressure_k >= PRESSURE_MAX:
		pressure_dens = minf(pressure_dens * 1.03, DENS_MAX)
	elif step < 1.0 and pressure_dens > 1.0:
		pressure_dens = maxf(pressure_dens * step, 1.0)      # сперва убираем добавленную плотность
		step = 1.0
	pressure_k = clampf(pressure_k * step, 1.0, PRESSURE_MAX)
	if OS.get_cmdline_user_args().has("--autotest") and int(t) % 60 < int(PRESSURE_STEP):
		print("AUTOTEST: pressure %.0f s: ttk %.1f / target %.1f, kills/s %.2f, air %.0f, k %.2f, dens %.2f" % [
			t, ttk, target, f.x, f.y, pressure_k, pressure_dens])
	Main.I.tele.maxv("pressure_max", pressure_k)


## Правка 3.5-s4: урон врагов растёт после 7:00 (к 15:00 — ×2, к 20:00 — ×2,6), иначе поздний бой не опасен
static func dmg_ramp(t: float) -> float:
	return 1.0 + maxf(0.0, t - 420.0) / 480.0


## EX-03: сколько врагов заходят в атаку одновременно (4 в начале, 8 к 10-й минуте)
func attack_slots() -> int:
	return 4 + mini(int(Main.I.run_time / 150.0), 4)


## EX-03: враг просит разрешения на заход; true — можно атаковать
func request_attack(e: Enemy) -> bool:
	_attackers = _attackers.filter(func(x): return is_instance_valid(x) and (x as Enemy).hp > 0.0)
	if _attackers.has(e):
		return true
	if _attackers.size() >= attack_slots():
		return false
	_attackers.append(e)
	return true


func release_attack(e: Enemy) -> void:
	_attackers.erase(e)
