class_name Drone
extends Enemy
## Дрон-стрелок: держит дистанцию 380–480 пикс, заходит цепью (у каждого своё место
## в строю «фронтом»), кружит и стреляет — перед выстрелом мигает жёлтым;
## вплотную не лезет — при сближении отваливает в сторону.
## 3.5 (разбор каталога 16.10): камикадзе выведен из игры (модель — основа для ракеты);
## у модели спаренная пушка — стреляет парой пуль из двух стволов, урон каждой вдвое меньше.
## EX-03 (отзывы внешних тестеров 21.10, «кружат вальс-бостон»): дрон больше не кружит рядом. Ждёт поодаль
## (hold, не стреляет), по разрешению спавнера (очередь на атаку) заходит на игрока с упреждением (run),
## даёт очередь, проскакивает мимо по прямой (exit) и возвращается в ожидание.

var lane := 0.0          # смещение в цепи поперёк направления на игрока
var _standoff := 430.0
var _gun_cd := 3.0
var _aim := 0.0
var _orbit := 1.0
var _mode := "hold"
var _mode_t := 0.0
var _fired := false
const HOLD_R := 560.0    # ждёт за дальностью пушки игрока (460)


func kind() -> String:
	return "дроны"


## S8 «eweap»: курсовые пушки истребителя (спаренная пушка: две пули по 3)
func gun_kind() -> String:
	return "fighter"


func _ready() -> void:
	super()
	hp = 12.0
	radius = 11.0
	contact_damage = 6.0
	xp = 1
	parts = 1
	repair_chance = 0.012
	kill_shake = 2.0
	_gun_cd = randf_range(1.5, 3.5)
	_standoff = randf_range(HOLD_R, HOLD_R + 120.0)
	_orbit = 1.0 if randf() < 0.5 else -1.0


func behave(delta: float) -> void:
	var p := Main.I.player
	var spd := Tuning.g("drone_speed")
	if p == null or p.hp <= 0.0:
		heading += delta
		position += Vector2.from_angle(heading) * spd * delta
		return
	var to := p.global_position - global_position
	var d := to.length()
	var dir := to / maxf(d, 1.0)
	var side := Vector2(-dir.y, dir.x)
	var desired := heading
	var turn := deg_to_rad(Tuning.g("drone_turn"))
	_mode_t -= delta
	match _mode:
		"run":
			# заход: курс на точку упреждения, очередь один раз, когда игрок впереди
			var lead := p.global_position + p.velocity * clampf(d / 600.0, 0.2, 0.8) + side * lane * 0.25
			desired = (lead - global_position).angle()
			spd *= 1.25
			if not _fired and _aim <= 0.0 and d < 620.0 and absf(angle_difference(heading, to.angle())) < 0.45:
				_aim = 0.4
			if d < 170.0 or _mode_t <= 0.0 or (_fired and Vector2.from_angle(heading).dot(dir) < 0.3):
				_mode = "exit"
				_mode_t = randf_range(1.0, 1.6)
		"exit":
			# проскакивает мимо по прямой, не доворачивая на игрока
			spd *= 1.15
			if _mode_t <= 0.0:
				_mode = "hold"
				if Main.I.spawner != null:
					Main.I.spawner.release_attack(self)
				_gun_cd = randf_range(2.5, 5.0)
		_:
			# ожидание: место в цепи на дистанции, у места — плавный облёт; вплотную не лезет
			var slot := p.global_position - dir * _standoff + side * lane
			var want := slot - global_position
			var k := clampf((want.length() - 60.0) / 140.0, 0.0, 1.0)
			desired = (want.normalized() * k + side * _orbit * (1.0 - k)).angle()
			if d < _standoff - 160.0:
				desired = (-dir + side * _orbit * 0.6).angle()
			_gun_cd -= delta
			if _gun_cd <= 0.0 and d < 1000.0 and not leaving:
				if Main.I.spawner == null or Main.I.spawner.request_attack(self):
					_mode = "run"
					_mode_t = 6.0
					_fired = false
				else:
					_gun_cd = randf_range(0.5, 1.0)
	heading = rotate_toward(heading, desired, turn * delta)
	position += Vector2.from_angle(heading) * spd * delta
	if _aim > 0.0:
		_aim -= delta
		if _aim <= 0.0:
			fire_at_player(gun_spread(), true) # спаренная пушка: две пули (S8: по eb_fighter_dmg)
			_fired = true


func _draw() -> void:
	var c := body_color(Color(0.95, 0.35, 0.3))
	if _aim > 0.0 and _flash <= 0.0:
		c = Color(1.0, 0.9, 0.3)
	if draw_enemy_sprite("e_drone_sea" if Biome.sea() else "e_drone", 34.0, Color(1.6, 1.4, 0.4) if (_aim > 0.0 and int(_aim * 12.0) % 2 == 0) else Color.WHITE):
		return
	var pts := Transform2D(heading, Vector2.ZERO) * PackedVector2Array([Vector2(12, 0), Vector2(0, 8), Vector2(-8, 0), Vector2(0, -8)])
	draw_colored_polygon(pts, c)
