class_name Interceptor
extends Enemy
## Перехватчик: атакует заходами, а не тараном.
##  1) заход: доворачивает на игрока, с 650 пикс — очередь из 3 пуль (перед ней нос горит жёлтым);
##  2) отворот: после очереди или если подошёл ближе 250 пикс — уходит в сторону и вытягивает;
##  3) разворот на новый заход.
## От него можно уйти манёвром, а можно сесть ему на хвост во время отворота.
## 3.5: видит, что игрок взял его на прицел (нос на нём), и иногда уходит рывком с бочкой.
## Элитный — следит за самими очередями и уходит чаще.

var _state := "attack"
var _state_t := 0.0
var _break_dir := 0.0
var _burst_cd := 2.0
var _aim := 0.0
var _shots := 0
var _shot_t := 0.0
var _evade_cd := 1.5
var _scan_t := 0.0


func kind() -> String:
	return "перехватчики"


func _ready() -> void:
	super()
	hp = 30.0
	radius = 15.0
	contact_damage = 8.0
	xp = 4
	parts = 3
	repair_chance = 0.04
	kill_shake = 4.0
	_burst_cd = randf_range(1.0, 2.0)


func speed() -> float:
	return Tuning.g("interceptor_speed")


func turn_deg() -> float:
	return 95.0


func burst_size() -> int:
	return 3


func behave(delta: float) -> void:
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		position += Vector2.from_angle(heading) * speed() * delta
		return
	var to := p.global_position - global_position
	var d := to.length()
	_state_t += delta
	_burst_cd -= delta
	var spd := speed()
	match _state:
		"attack":
			heading = rotate_toward(heading, to.angle(), deg_to_rad(turn_deg()) * delta)
			if d > 1100.0:
				spd = maxf(spd, p.velocity.length() * 1.1) # догоняет, если игрок далеко
			if d < 250.0:
				_start_break(to)
		"break":
			heading = rotate_toward(heading, _break_dir, deg_to_rad(turn_deg() * 1.2) * delta)
			if _state_t > 1.8:
				_state = "attack"
				_state_t = 0.0
	position += Vector2.from_angle(heading) * spd * delta
	_try_evade(delta)

	# Стрельба
	if _shots > 0:
		_shot_t -= delta
		if _shot_t <= 0.0:
			fire_at_player(randf_range(-0.06, 0.06))
			_shots -= 1
			_shot_t = 0.1
			if _shots == 0:
				_start_break(to)
		return
	if _aim > 0.0:
		_aim -= delta
		if _aim <= 0.0:
			_shots = burst_size()
			_shot_t = 0.0
			_burst_cd = randf_range(2.5, 3.5)
		return
	var off := absf(wrapf(to.angle() - heading, -PI, PI))
	if _state == "attack" and _burst_cd <= 0.0 and d < 650.0 and d > 200.0 and off < 0.4:
		_aim = 0.35


## 3.5: уход из-под огня (не во время своей очереди)
func _try_evade(delta: float) -> void:
	_evade_cd -= delta
	_scan_t -= delta
	if _evade_cd > 0.0 or _scan_t > 0.0 or evade_t > 0.0 or _shots > 0:
		return
	_scan_t = 0.25
	var threat := incoming_fire(0.4, 2) if elite else player_aiming(8.0, 650.0)
	if threat == Vector2.ZERO:
		return
	if randf() < (0.7 if elite else 0.35):
		start_evade(threat, 300.0, 0.65)
		_evade_cd = randf_range(2.0, 3.0) if elite else randf_range(3.0, 5.0)
	else:
		_evade_cd = 1.0


func _start_break(to: Vector2) -> void:
	if _state == "break":
		return
	_state = "break"
	_state_t = 0.0
	var side := 1.0 if randf() < 0.5 else -1.0
	_break_dir = (to.angle() + side * deg_to_rad(randf_range(100.0, 140.0)))


func _draw() -> void:
	var c := body_color(Color(0.85, 0.3, 0.55))
	var xf := Transform2D(heading, Vector2.ZERO)
	if draw_enemy_sprite("e_interceptor", 46.0):
		if _aim > 0.0 or _shots > 0:
			draw_circle(xf * Vector2(30, 0), 6.0, Color(1.0, 0.9, 0.3))
		draw_hp_bar()
		return
	var body := xf * PackedVector2Array([Vector2(18, 0), Vector2(-4, 5), Vector2(-10, 16), Vector2(-14, 4), Vector2(-14, -4), Vector2(-10, -16), Vector2(-4, -5)])
	draw_colored_polygon(body, c)
	if _aim > 0.0 or _shots > 0:
		draw_circle(xf * Vector2(18, 0), 5.0, Color(1.0, 0.9, 0.3))
	draw_hp_bar()
