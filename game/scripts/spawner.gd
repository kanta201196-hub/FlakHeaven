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
## «охота на транспорт». Не стартуют, пока жив ас или идёт прошлая активность.
var next_activity := 60.0
var activity_i := 0
var activity_node: Node = null
var fuel: Fuel = null   # 3.5: топливо и свой заправщик
const ACTIVITIES := ["ground", "dogfight", "transport"]
const TRANSPORT_TTK := 12.0


func _ready() -> void:
	fuel = Fuel.new()
	add_child(fuel)
	if OS.get_cmdline_user_args().has("--dogfight"):
		activity_i = 1      # проверка: сразу догфайт
		next_activity = 20.0
	if OS.get_cmdline_user_args().has("--transport"):
		activity_i = 2      # проверка: сразу транспорт
		next_activity = 20.0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--fuel="): # проверка: начать с неполным баком (доля 0–1)
			fuel.left = Fuel.CAPACITY * clampf(float(String(a).substr(7)), 0.0, 1.0)
var _grid := {}
const CELL := 90.0

## 3.5: урон игрока за последние 60 с — по нему считается прочность асов и бункера.
## Иначе к 10–15-й минуте урон игрока растёт в ~30 раз, а прочность врагов — в ~3, и ас живёт 3–6 с.
var _dealt_hist := PackedFloat32Array()   # сумма урона на каждую секунду вылета
var _dealt_tick := 0.0
## Сколько секунд ас должен выдерживать сосредоточенный огонь (по номеру волны асов)
const BOSS_TTK := [25.0, 30.0, 35.0]
const BUNKER_TTK := 9.0


func dealt_total() -> float:
	var sum := 0.0
	for v in (Main.I.stats["dealt"] as Dictionary).values():
		sum += float(v)
	return sum


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
		if _dealt_hist.size() > 120:
			_dealt_hist = _dealt_hist.slice(_dealt_hist.size() - 61)
	# Ас каждые 5 минут
	var due := int(t / Tuning.g("boss_every"))
	if due > boss_wave:
		boss_wave = due
		_spawn_bosses(p, boss_wave)

	if t >= next_activity:
		start_activity(p, t)

	# 3.1: пока жив ас — мелочи втрое меньше, чтобы до него можно было добраться
	var boss_on := m.boss_alive()
	var mult := Tuning.g("spawn_rate_mult") * (0.3 if boss_on else 1.0)
	mult *= 1.0 + maxf(0.0, t - 300.0) / 60.0 * 0.05 # 2.8: после 5:00 — плотнее (+5% в минуту)
	var enemies := get_tree().get_nodes_in_group("enemies")

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
	var hp_k := Tuning.g("enemy_hp_mult") * hp_ramp(t)
	if kind_s == "ground":
		var site := AASite.new()
		var dir := p.heading + randf_range(-1.0, 1.0)
		site.setup(p.global_position + Vector2.from_angle(dir) * 1700.0, hp_k, recent_dps() * BUNKER_TTK)
		Main.I.world.add_child(site)
		activity_node = site
		Main.I.show_banner("Разведка: позиция ПВО! Награда — выбор из редких карточек", 4.0)
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
	else:
		var ace := RivalAce.new()
		ace.setup(Tuning.g("rival_hp") * hp_k)
		var back := p.heading + PI + randf_range(-0.6, 0.6)
		ace.position = p.global_position + Vector2.from_angle(back) * 1100.0
		ace.heading = (p.global_position - ace.position).angle()
		Main.I.world.add_child(ace)
		activity_node = ace
		Main.I.show_banner("Дуэль: вражеский ас заходит вам в хвост!", 4.0)
	Main.I.sfx.play("boss", -8.0, 1.4)


func m_boss() -> bool:
	return Main.I.boss_alive()


func _spawn_bosses(p: Player, wave: int) -> void:
	var variants: Array = ["carrier"] if wave == 1 else (["interceptor"] if wave == 2 else ["carrier", "interceptor"])
	# 3.1: асы прочнее и растут вместе со временем вылета (как обычные враги)
	var hp := Tuning.g("boss_hp") * Tuning.g("enemy_hp_mult") * 0.6 * hp_ramp(Main.I.run_time)
	# 3.5: не меньше, чем урон игрока за BOSS_TTK секунд (щит +35% сверху — поэтому делим)
	var ttk: float = BOSS_TTK[mini(wave - 1, BOSS_TTK.size() - 1)]
	var hp_dps := recent_dps() * ttk / 1.35
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: boss wave %d hp formula %.0f, by dps %.0f (dps %.0f)" % [wave, hp, hp_dps, recent_dps()])
	if not OS.get_cmdline_user_args().has("--shots"): # скриншоты: асы нарочно слабые
		hp = maxf(hp, hp_dps)
	# 3.5 (разбор каталога 16.10): третья волна — босс «Крепость» вместо пары асов
	if wave >= 3 or OS.get_cmdline_user_args().has("--fortress"):
		var f := Fortress.new()
		f.setup_fortress(hp * 2.0 * 1.35) # прочность двух асов вместе со щитами; фазы делят её на точки и корпус
		f.position = p.global_position + Vector2.from_angle(randf() * TAU) * 1100.0
		f.heading = (p.global_position - f.position).angle() + PI / 2.0
		Main.I.world.add_child(f)
		variants = []
	for v in variants:
		var b := Boss.new()
		b.setup(v, hp)
		b.position = p.global_position + Vector2.from_angle(randf() * TAU) * 1100.0
		b.heading = (p.global_position - b.position).angle()
		Main.I.world.add_child(b)
	# мелочь расступается: дальние дроны уходят, освобождая подход к асу
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Drone and (n as Node2D).global_position.distance_to(p.global_position) > 600.0:
			(n as Enemy).remove_from_group("enemies")
			(n as Node).queue_free()
	Main.I.on_boss_wave(wave, maxi(1, variants.size()))


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
				var min_d: float = e.radius + (o as Enemy).radius + 24.0
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
	e.apply_hp_mult(Tuning.g("enemy_hp_mult") * hp_ramp(t))
	# 2.8: с 10-й минуты — элитные варианты (прочнее ×3, крупнее, больше опыта)
	# 3.1: элитные — с 6:00 и чаще (до 30%)
	if t > 360.0 and randf() < clampf((t - 360.0) / 1500.0, 0.0, 0.3):
		e.make_elite()


## 2.8: прочность растёт со временем, после 5:00 — быстрее (+8% в минуту сверху)
static func hp_ramp(t: float) -> float:
	return (1.0 + t / 450.0) * (1.0 + maxf(0.0, t - 300.0) / 60.0 * 0.08)
