class_name Ekranoplan
extends Enemy
## Экраноплан «Крачка» («Архипелаг», E-07; решение Kanta 18.10 — вместо подлодки): несётся над самой водой
## вдоль пролива (маршрут — Convoy.sea_route) со шлейфом брызг, пускает веер ракет, когда игрок впереди.
## В конце маршрута разворачивается и сбрасывает ход — окно для сбития; после второго прохода уходит.
## Цель наземная (is_ground): бомбы, НАР и пушка — да, ракеты В-В — нет.

const LEN := 130.0           # длина на картинке до unit_scale (70 м — крупный, ×1,8 ≈ 235 пикс.)
const SPEED := 270.0
const SLOW := 70.0           # ход на развороте
const FAN := 5

var _route: Convoy
var _s := 0.0
var _dir := 1.0
var _hdg := 0.0
var _spd := SPEED
var _turns := 0
var _cd := 3.0
var _turning := 0.0


func kind() -> String:
	return "экранопланы"


func setup_run(near: Vector2) -> void:
	is_ground = true
	big = true
	hp = 420.0
	max_hp = hp
	radius = 34.0
	xp = 18
	parts = 14
	repair_chance = 0.5
	kill_shake = 10.0
	contact_damage = 0.0
	no_despawn = true
	_route = Convoy.sea_route(near, Vector2.from_angle(randf() * TAU))
	var s0 := _route._s_of(near)
	_dir = 1.0 if s0 > 2600.0 else -1.0
	_s = clampf(s0 - _dir * 2600.0, 0.0, _route.length)   # из-за края экрана, навстречу игроку
	anchor = _route.point_at(_s)
	position = anchor
	_hdg = (_route.dir_at(_s) * _dir).angle()
	heading = _hdg


func _exit_tree() -> void:
	if _route != null and is_instance_valid(_route):
		_route.free()
		_route = null


func behave(delta: float) -> void:
	if _route == null:
		return
	var end := _s <= 40.0 if _dir < 0.0 else _s >= _route.length - 40.0
	if end and _turning <= 0.0:
		_turns += 1
		if _turns >= 2:
			anchor = Vector2.INF
			remove_from_group("enemies")
			queue_free()   # ушёл дальше по проливу — без награды
			return
		_turning = 6.0
		_dir = -_dir
	if _turning > 0.0:
		_turning -= delta
		_spd = move_toward(_spd, SLOW, 160.0 * delta)
	else:
		_spd = move_toward(_spd, SPEED, 60.0 * delta)
	_s = clampf(_s + _dir * _spd * delta, 0.0, _route.length)
	anchor = _route.point_at(_s)
	_hdg = rotate_toward(_hdg, (_route.dir_at(_s) * _dir).angle(), deg_to_rad(40.0 if _turning > 0.0 else 18.0) * delta)
	heading = _hdg
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return
	_cd -= delta
	var to := p.global_position - global_position
	var ahead := absf(wrapf(to.angle() - heading, -PI, PI)) < 0.7
	if _cd <= 0.0 and to.length() < 800.0 and ahead:
		_cd = 5.5
		for i in FAN:
			Main.I.projectiles.spawn_missile(global_position + Vector2.from_angle(heading) * 40.0, Vector2.from_angle(heading + (i - (FAN - 1) * 0.5) * 0.2), "aam", kind(), Projectiles.MSL_FREE)
		Main.I.sfx.play("missile_enemy", -5.0, 1.1, global_position)


func _draw() -> void:
	if not draw_enemy_sprite("e_ekranoplan", LEN):
		draw_colored_polygon(Transform2D(heading, Vector2.ZERO) * PackedVector2Array([Vector2(60, 0), Vector2(-50, 14), Vector2(-50, -14)]), Color(0.6, 0.62, 0.66))
	draw_hp_bar()
