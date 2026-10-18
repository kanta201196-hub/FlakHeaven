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
const ACTIVITIES := ["ground", "dogfight", "transport", "convoy"]
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
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--fuel="): # проверка: начать с неполным баком (доля 0–1)
			fuel.left = fuel.capacity * clampf(float(String(a).substr(7)), 0.0, 1.0)
var _grid := {}
const CELL := 90.0

## 3.5: урон игрока за последние 60 с — по нему считается прочность асов и бункера.
## Иначе к 10–15-й минуте урон игрока растёт в ~30 раз, а прочность врагов — в ~3, и ас живёт 3–6 с.
var _dealt_hist := PackedFloat32Array()   # сумма урона на каждую секунду вылета
var _dealt_tick := 0.0
## Сколько секунд ас должен выдерживать сосредоточенный огонь (по номеру волны асов)
const BOSS_TTK := [25.0, 30.0, 35.0]

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
	# чем по асу волны (бот: 0,35 против 1,3–1,5), поэтому для первого аса — середина между дуэлью и ×1,6
	if not _big_boss_seen:
		k = (k + SINGLE_K_DEF) * 0.5
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
			_air_hist.append([t, air_count(get_tree().get_nodes_in_group("enemies"))])
			if _air_hist.size() > 300:
				_air_hist = _air_hist.slice(_air_hist.size() - 200)
		if _dealt_hist.size() > 120:
			_dealt_hist = _dealt_hist.slice(_dealt_hist.size() - 61)
	_pressure(t, delta)
	# Ас каждые 5 минут
	var due := int(t / Tuning.g("boss_every"))
	if due > boss_wave:
		boss_wave = due
		_spawn_bosses(p, boss_wave)

	if t >= next_activity:
		start_activity(p, t)

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
				_place(d, p, ang + randf_range(-0.2, 0.2), t)
				d.heading = (p.global_position - d.position).angle()

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


func start_activity(p: Player, t: float, force := false) -> void:
	if not force and (m_boss() or is_instance_valid(activity_node)):
		next_activity = t + 15.0
		return
	var kind_s: String = ACTIVITIES[activity_i % ACTIVITIES.size()]
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: activity start ", kind_s, " at %.0f" % t)
	activity_i += 1
	next_activity = t + Tuning.g("activity_every")
	var hp_k := hp_mult() * hp_ramp(t)
	if kind_s == "ground":
		var site := AASite.new()
		var dir := p.heading + randf_range(-1.0, 1.0)
		site.setup(p.global_position + Vector2.from_angle(dir) * 1700.0, hp_k)
		Main.I.world.add_child(site)
		activity_node = site
		Main.I.show_banner("Разведка: позиция ПВО! Награда — выбор из редких карточек", 4.0)
		Hints.show("act_aa", "Позиция ПВО: летите по голубой стрелке. Когда подлетите, пойдёт отсчёт — разбейте бункер в центре, пока он не кончился. Зенитки бьют издалека: заходите на скорости.", 9.0, 2)
	elif kind_s == "convoy":
		var cv := Convoy.new()
		# колонна пересекает курс игрока впереди: маршрут через точку в 1 300 пикс. по курсу
		var mid := p.global_position + Vector2.from_angle(p.heading + randf_range(-0.4, 0.4)) * 1300.0
		var side := 1.0 if randf() < 0.5 else -1.0
		cv.setup(mid, Vector2.from_angle(p.heading + side * PI / 2.0), hp_k, t)
		Main.I.world.add_child(cv)
		activity_node = cv
		Main.I.show_banner("Разведка: колонна снабжения идёт к укрытию! Сожгите грузовики — груз ваш", 4.0)
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
		Main.I.show_banner("Разведка: вражеский транспортник с прикрытием! Сбейте его — груз ваш", 4.0)
		Hints.show("act_transport", "Транспортник летит через район и скоро уйдёт — розовая стрелка. Прикрытие отвлекает: бейте сам транспортник, груз падает с него.", 8.0, 2)
	else:
		var ace := RivalAce.new()
		ace.setup(Tuning.g("rival_hp") * hp_k)
		var back := p.heading + PI + randf_range(-0.6, 0.6)
		ace.position = p.global_position + Vector2.from_angle(back) * 1100.0
		ace.heading = (p.global_position - ace.position).angle()
		Main.I.world.add_child(ace)
		activity_node = ace
		Main.I.show_banner("Дуэль: вражеский ас заходит вам в хвост!", 4.0)
		Hints.show("act_ace", "Дуэль с асом: он заходит в хвост. Сбросьте газ (S) или сделайте боевой разворот (E) — ас проскочит вперёд под вашу пушку.", 8.0, 2)
	Main.I.sfx.play("boss", -8.0, 1.4)


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
	var hp_dps := recent_dps() * ttk * last_single_k / 1.35 * (1.0 + (Campaign.k("hp") - 1.0) * 0.5)
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: boss wave %d hp formula %.0f, by dps %.0f (dps %.0f, single_k %.2f из %d с)" % [wave, hp, hp_dps, recent_dps(), last_single_k, _big_hist.size()])
	if not OS.get_cmdline_user_args().has("--shots"): # скриншоты: асы нарочно слабые
		hp = maxf(hp, hp_dps)
	# 3.5 (разбор каталога 16.10): третья волна — босс «Крепость» вместо пары асов
	if wave >= 3 or OS.get_cmdline_user_args().has("--fortress"):
		var f := Fortress.new()
		f.setup_fortress(hp * 2.0 * 1.35) # прочность двух асов вместе со щитами; фазы делят её на точки и корпус
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
	Main.I.on_boss_wave(wave, maxi(1, variants.size()))


func air_count(enemies: Array) -> int:
	var n := 0
	for e in enemies:
		var en := e as Enemy
		if not en.is_boss and not en.is_ground and not en.no_despawn and not en.leaving:
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
	if t > 360.0 and randf() < clampf((t - 360.0) / 1500.0, 0.0, 0.3):
		e.make_elite()


## 2.8: прочность растёт со временем, после 5:00 — быстрее (+4% в минуту сверху).
## S6-02: было +8% — к 10:00 ×3,27, стало ×2,8 (решение Kanta 18.10)
static func hp_ramp(t: float) -> float:
	return (1.0 + t / 450.0) * (1.0 + maxf(0.0, t - 300.0) / 60.0 * 0.04)


## Сбит обычный самолёт — запомнить, сколько он прожил
func note_kill(e: Enemy) -> void:
	if e.born_t < 0.0 or e.is_boss or e.is_ground or e.no_despawn or Main.I.boss_alive():
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
