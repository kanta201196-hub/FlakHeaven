class_name Boss
extends Enemy
## Мини-босс — «ас»: элитная версия обычного врага (по концепту).
## Крупнее, прочность ×N, щит (восстанавливается, если ~4 с не получать урон), новые атаки.
##   «Почтальон» — ас-ракетоносец: залп из 3 ракет после захвата + кольцо из крупных пуль.
##   «Сквозняк» — ас-перехватчик: быстрые заходы, очереди из 5 пуль, вызывает звено перехватчиков.
## 3.5: асы сопротивляются: уходят рывком с бочкой из-под очередей, отстреливают тепловые ловушки
## против наших ракет, сбрасывают с хвоста резким отворотом, «Почтальон» сам заходит в атаку.
## Прочность — не меньше урона игрока за 25–35 с (считает спавнер), ниже половины — злее (чаще атаки и манёвры).
## Правка 3.5-s4 (п. 25, отчёт с «Кита»): скорость от крейсерской игрока — ас не отстаёт; «Сквозняк» заходит
## сбоку-сзади, бьёт на встречном курсе и уходит отворотом с набором скорости (не таранит); «Почтальон» чаще
## заходит в атаку и после неё уходит; оба чаще уклоняются; живут не меньше 26 с; говорят по радио.

const LINES := {
	"spawn": ["Вижу цель. Работаем.", "Ты в моём небе, новичок.", "Звено, не мешать — этот мой."],
	"run": ["Захожу!", "Держись, сейчас прошью!", "Атакую!"],
	"angry": ["Ах ты… Ну держись!", "Повреждения! Злее будем.", "Теперь без шуток."],
	"down": ["Подбит! Катапультируюсь!", "Горю… выхожу из боя!"],
}

var variant := "carrier"
var title := ""
var shield := 0.0
var shield_max := 0.0
var _since_hit := 0.0
var _t := 0.0
var _a_cd := 3.0   # основная атака
var _b_cd := 4.0   # дополнительная атака
var _lock := 0.0
var _shots := 0
var _shot_t := 0.0
var _orbit := 1.0
var _mode := "setup"    # у «Сквозняка»: выход на позицию / атака / отворот
var _mode_t := 0.0
var _break_dir := 0.0
# 3.5: сопротивление
var _born := 0.0
var _evade_cd := 1.0
var _scan_t := 0.0
var _flare_cd := 0.0
var _tailed := 0.0
var _run := false        # «Почтальон»: заход в атаку
var _run_cd := 6.0
var _run_t := 0.0
var _run_shot := 0.0
var _said_angry := false
var _say_t := 0.0
var _side := 1.0          # «Сквозняк»: с какой стороны заходит
var log_entry := {}       # тест 3.5-s5 (п. 10): строка аса в Main.ace_log


func setup(v: String, hp_total: float) -> void:
	variant = v
	is_boss = true
	big = true
	radius = 40.0
	kill_shake = 14.0
	xp = 60
	parts = 100
	repair_chance = 1.0
	contact_damage = 20.0 # таранить не стремится — урон только при случайном столкновении
	hp = hp_total
	max_hp = hp_total
	shield_max = hp_total * 0.35
	shield = shield_max
	title = "Ас «Почтальон»" if v == "carrier" else "Ас «Сквозняк»"
	_orbit = 1.0 if randf() < 0.5 else -1.0
	_born = Main.I.run_time
	min_life = 26.0   # правка 3.5-s4 (было 16 — в логе «Кита» асы жили 10–47 с)
	_side = _orbit
	log_entry = {"v": v, "t": _born, "hp": hp_total * 1.35, "k": Main.I.spawner.last_single_k if Main.I.spawner != null else 0.0, "dmg": {}, "life": -1.0}
	Main.I.ace_log.append(log_entry)


func kind() -> String:
	return "асы"


func _ready() -> void:
	super()
	say("spawn")


func say(key: String) -> void:
	if _say_t > 0.0 and key != "down":
		return
	_say_t = 6.0
	var arr: Array = LINES[key]
	Main.I.radio(title.trim_prefix("Ас "), arr[randi() % arr.size()])


## Скорость аса от крейсерской игрока (k — доля), не ниже base
func _spd(base: float, k: float, p: Player) -> float:
	return maxf(base, p.cruise_speed() * k)


## Спавнер не умножает прочность асов — она задаётся в setup().
func apply_hp_mult(_m: float) -> void:
	pass


func absorb(dmg: float) -> float:
	_since_hit = 0.0
	if shield <= 0.0:
		return dmg
	var s := minf(shield, dmg)
	shield -= s
	Main.I.add_stat("dealt", "щит аса", s)
	if shield <= 0.0:
		Main.I.fx.ring(global_position, radius * 2.0, Color(0.5, 0.8, 1.0))
		Main.I.sfx.play("shield_break", -6.0, 1.6)
	return dmg - s


func behave(delta: float) -> void:
	_t += delta
	_since_hit += delta
	if _since_hit > 4.0 and shield < shield_max:
		shield = minf(shield_max, shield + shield_max * 0.15 * delta)
	_say_t -= delta
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		position += Vector2.from_angle(heading) * 200.0 * delta
		return
	if not _said_angry and angry() < 1.0:
		_said_angry = true
		_say_t = 0.0
		say("angry")
	if variant == "carrier":
		_behave_carrier(delta, p)
	else:
		_behave_interceptor(delta, p)
	_resist(delta, p)


## Ниже половины прочности — злее
func angry() -> float:
	return 0.7 if hp < max_hp * 0.5 else 1.0


## 3.5: уклонение от очередей, ловушки от ракет, сброс игрока с хвоста
func _resist(delta: float, p: Player) -> void:
	_evade_cd -= delta
	_flare_cd -= delta
	_scan_t -= delta
	flare_defense(delta, 440.0, 260.0, 0.85, 2.5 if angry() >= 1.0 else 3.0, 7.0)
	if _evade_cd > 0.0 or maneuvering() or _scan_t > 0.0:
		return
	_scan_t = 0.12
	var threat := incoming_fire()
	if threat == Vector2.ZERO:
		threat = player_aiming(7.0, 650.0)
	if threat != Vector2.ZERO:
		# тест 3.5-s7: разные манёвры и реже (было 1,2–2 с, почти всегда бочка)
		start_maneuver(threat, 380.0 if variant == "interceptor" else 340.0)
		_evade_cd = randf_range(2.6, 4.0) * angry()
		return
	# игрок сел на хвост — резкий отворот (раньше — бочка и мгновенный поворот носа на 70°)
	if p.on_tail() and p.tail_target == self:
		_tailed += 0.12
		if _tailed > 0.8:
			_tailed = 0.0
			start_maneuver(Vector2.from_angle(heading), 340.0)
			_evade_cd = 2.5 * angry()
	else:
		_tailed = 0.0


func _die() -> void:
	log_entry["life"] = Main.I.run_time - _born
	say("down")
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: boss %s down in %.1f s (hp %.0f)" % [variant, Main.I.run_time - _born, max_hp])
	super()


func _behave_carrier(delta: float, p: Player) -> void:
	var to := p.global_position - global_position
	var d := to.length()
	var desired := to.angle()
	if d < 450.0:
		desired = to.angle() + PI
	elif d < 700.0:
		desired = to.angle() + PI / 2.0 * _orbit
	# 3.5: заход в атаку — разгон на игрока, очереди крупными пулями в лоб, отворот у 280 пикс.
	var spd := _spd(230.0, 0.9, p)
	_run_cd -= delta
	if not _run and _run_cd <= 0.0 and d < 1000.0 and _lock <= 0.0:
		_run = true
		_run_t = 0.0
		Main.I.sfx.play("lock", -6.0, 0.6)
		say("run")
	if _run:
		_run_t += delta
		# упреждение: заходит туда, где игрок будет
		desired = (to + p.velocity * clampf(d / 700.0, 0.0, 0.8)).angle()
		spd = _spd(380.0, 1.3, p)
		_run_shot -= delta
		var off := absf(wrapf(to.angle() - heading, -PI, PI))
		if _run_shot <= 0.0 and off < 0.35 and d < 700.0:
			_run_shot = 0.45
			for j in 3:
				var dj := Vector2.from_angle(heading).rotated((j - 1) * 0.09)
				Main.I.projectiles.spawn_enemy_bullet(global_position + dj * radius, dj * 480.0, kind(), true)
			Main.I.sfx.play("enemy_fire", -9.0, 0.5)
		if d < 300.0 or _run_t > 4.0:
			_run = false
			_run_cd = randf_range(5.0, 7.0) * angry()
			_orbit = -_orbit
			# уход после атаки: манёвр в сторону от курса игрока
			start_maneuver(to, 360.0)
	heading = rotate_toward(heading, desired, deg_to_rad(110.0 if _run else 80.0) * delta)
	position += Vector2.from_angle(heading) * _speed(spd, d, p) * delta
	# Залп ракет после захвата
	if _lock > 0.0:
		_lock -= delta
		if _lock <= 0.0:
			# 3.1: залп из 5 ракет веером
			for i in 5:
				Main.I.projectiles.spawn_missile(global_position, to.normalized().rotated((i - 2) * 0.35))
			Main.I.sfx.play("missile_enemy", -4.0, 0.8)
			_a_cd = 4.5 * angry()
	else:
		_a_cd -= delta
		if _a_cd <= 0.0 and d < 1000.0:
			_lock = 1.0
			Main.I.sfx.play("lock", -4.0, 0.8)
	# Кольцо из крупных пуль
	_b_cd -= delta
	if _b_cd <= 0.0 and d < 900.0:
		_b_cd = 2.6 * angry()
		var off := randf() * TAU
		for i in 18:
			var dir := Vector2.from_angle(off + TAU * i / 18.0)
			Main.I.projectiles.spawn_enemy_bullet(global_position + dir * radius, dir * 280.0, kind(), true)
		# и прицельная очередь из 3 крупных пуль по игроку
		for j in 3:
			var dj := to.normalized().rotated((j - 1) * 0.12)
			Main.I.projectiles.spawn_enemy_bullet(global_position + dj * radius, dj * 440.0, kind(), true)
		Main.I.sfx.play("enemy_fire", -8.0, 0.4)


func _behave_interceptor(delta: float, p: Player) -> void:
	# Правка 3.5-s4: заход сбоку-сзади («setup») → атака на сближении с упреждением и очередями («attack»)
	# → отворот с набором скорости («break»), потом заход с другой стороны. Не таранит: отворот за 330 пикс.
	var to := p.global_position - global_position
	var d := to.length()
	var pf := Vector2.from_angle(p.heading)
	_mode_t += delta
	var spd := _spd(320.0, 1.05, p)
	match _mode:
		"setup":
			var spot := p.global_position + (-pf).rotated(_side * deg_to_rad(50.0)) * 750.0
			var ts := spot - global_position
			heading = rotate_toward(heading, ts.angle(), deg_to_rad(100.0) * delta)
			spd = _spd(320.0, 1.15, p)
			if ts.length() < 220.0 or _mode_t > 3.5:
				_mode = "attack"
				_mode_t = 0.0
				say("run")
		"attack":
			var lead := to + p.velocity * clampf(d / 900.0, 0.0, 0.6)
			heading = rotate_toward(heading, lead.angle(), deg_to_rad(95.0) * delta)
			spd = _spd(360.0, 1.35, p)
			if d < 330.0 or _mode_t > 5.0:
				_boss_break(to)
		_:
			heading = rotate_toward(heading, _break_dir, deg_to_rad(120.0) * delta)
			spd = _spd(360.0, 1.4, p)
			if _mode_t > 1.6:
				_mode = "setup"
				_mode_t = 0.0
				_side = -_side
	position += Vector2.from_angle(heading) * _speed(spd, d, p) * delta
	if _shots > 0:
		_shot_t -= delta
		if _shot_t <= 0.0:
			for k in 3: # 3.1: очередь веером
				fire_at_player((k - 1) * 0.12 + randf_range(-0.04, 0.04))
			_shots -= 1
			_shot_t = 0.08
			if _shots == 0:
				_boss_break(to)
	elif _lock > 0.0:
		_lock -= delta
		if _lock <= 0.0:
			_shots = 7
	else:
		_a_cd -= delta
		var off := absf(wrapf(to.angle() - heading, -PI, PI))
		if _mode == "attack" and _a_cd <= 0.0 and d < 750.0 and off < 0.5:
			_lock = 0.3
			_a_cd = 1.2 * angry()
	# Вызов звена
	_b_cd -= delta
	if _b_cd <= 0.0:
		_b_cd = 10.0
		for i in 3:
			var f := Interceptor.new()
			f.position = global_position + Vector2.from_angle(heading + PI / 2.0 * (i - 1)) * 80.0 - Vector2.from_angle(heading) * 40.0 * absf(i - 1)
			f.heading = heading
			Main.I.world.add_child(f)
			f.apply_hp_mult(Tuning.g("enemy_hp_mult"))


func _boss_break(to: Vector2) -> void:
	if _mode == "break":
		return
	_mode = "break"
	_mode_t = 0.0
	_break_dir = to.angle() + (1.0 if randf() < 0.5 else -1.0) * deg_to_rad(120.0)


## Ас не теряется: если игрок совсем далеко (>1300), подтягивается чуть быстрее него.
## Ближе — летит своей скоростью, от него можно оторваться форсажем.
func _speed(base: float, d: float, p: Player) -> float:
	if d > 1300.0:
		return maxf(base, p.velocity.length() * 1.05)
	return base


func _draw() -> void:
	var xf := Transform2D(heading, Vector2.ZERO)
	var c := body_color(Color(1.0, 0.55, 0.15) if variant == "carrier" else Color(0.95, 0.25, 0.55))
	var body: PackedVector2Array
	if variant == "carrier":
		body = xf * PackedVector2Array([Vector2(44, 0), Vector2(8, 14), Vector2(-10, 44), Vector2(-26, 14), Vector2(-34, 0), Vector2(-26, -14), Vector2(-10, -44), Vector2(8, -14)])
	else:
		body = xf * PackedVector2Array([Vector2(40, 0), Vector2(-6, 10), Vector2(-20, 36), Vector2(-30, 8), Vector2(-30, -8), Vector2(-20, -36), Vector2(-6, -10)])
	if not draw_enemy_sprite("e_postman" if variant == "carrier" else "e_draft", 92.0 if variant == "carrier" else 84.0):
		draw_colored_polygon(body, c)
	draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 48, Color(1, 0.3, 0.3, 0.5), 2.0)
	if shield > 0.0:
		draw_arc(Vector2.ZERO, radius + 14.0, 0.0, TAU * shield / shield_max, 48, Color(0.5, 0.8, 1.0, 0.8), 4.0)
	if (_lock > 0.0 or _shots > 0) and variant == "interceptor":
		draw_circle(xf * Vector2(55, 0), 8.0, Color(1.0, 0.9, 0.3))
	if _lock > 0.0 and variant == "carrier":
		var p := Main.I.player
		if p != null and p.hp > 0.0:
			var a := 0.35 + 0.5 * absf(sin(_t * 30.0))
			var target := to_local(p.global_position)
			draw_line(Vector2.ZERO, target, Color(1, 0.15, 0.1, a), 3.0)
			draw_arc(target, 30.0, 0.0, TAU, 32, Color(1, 0.15, 0.1, a), 3.0)
	draw_string(Hud.ui_font(), Vector2(-120, -radius - 24.0), title, HORIZONTAL_ALIGNMENT_CENTER, 240, 18, Color(1, 0.85, 0.7))
