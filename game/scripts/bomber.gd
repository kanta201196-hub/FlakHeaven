class_name Bomber
extends Enemy
## EX-04 Б2: звено бомбардировщиков «Буйвол» — цель, которую кружением не взять.
## Три бомбардировщика строем «клин» проходят район по прямой ~45 с и уходят (награды за ушедших нет, штрафа тоже).
## Лобовая броня: пока игрок впереди (в конусе FRONT_DEG от носа), урон по бомбардировщику ×FRONT_K.
## Кормовая турель бьёт очередями только в задний сектор TAIL_DEG. Бока — мёртвая зона:
## выгодно зайти сбоку по прямой. Сектор турели и лобовая броня нарисованы под самолётом.

const LIFE := 45.0
const SPEED := 150.0
const FRONT_DEG := 55.0
const FRONT_K := 0.5
const TAIL_DEG := 65.0
const TAIL_R := 620.0
const LEN := 120.0

var life := LIFE
var lead: Bomber = null          # ведущий звена (у ведущего — null)
var slot := Vector2.ZERO          # место в строю в осях ведущего
var _cd := 1.5
var _shots := 0
var _shot_t := 0.0


func kind() -> String:
	return "бомбардировщики"


## Кормовой пулемёт
func gun_kind() -> String:
	return "fighter"


func _ready() -> void:
	super()
	hp = 140.0
	radius = 30.0
	big = true
	no_despawn = true
	contact_damage = 14.0
	xp = 14
	parts = 10
	repair_chance = 0.25
	kill_shake = 8.0
	_cd = randf_range(0.8, 1.6)


## Угол игрока от носа, рад (0 — прямо по курсу, PI — строго с хвоста)
func _aspect(p: Vector2) -> float:
	return absf(wrapf((p - global_position).angle() - heading, -PI, PI))


func aspect_k(_src: String) -> float:
	var p := Main.I.player
	if p == null or _aspect(p.global_position) > deg_to_rad(FRONT_DEG):
		return 1.0
	Main.I.tele.add("def_front", 1.0)
	Hints.show("def_front", "Синяя дуга у носа бомбардировщика — лобовая броня: спереди урон вдвое меньше. Сзади бьёт турель (красный сектор). Заходите сбоку.", 9.0, 2)
	return FRONT_K


func behave(delta: float) -> void:
	life -= delta
	if is_instance_valid(lead) and lead.hp > 0.0 and life > 0.0:
		# держим строй: место в клину за ведущим
		var at := lead.global_position + slot.rotated(lead.heading)
		var to := at - global_position
		heading = rotate_toward(heading, to.angle() if to.length() > 30.0 else lead.heading, deg_to_rad(60.0) * delta)
		position += Vector2.from_angle(heading) * clampf(to.length() * 1.2, SPEED * 0.8, SPEED * 1.4) * delta
	else:
		position += Vector2.from_angle(heading) * SPEED * (1.6 if life <= 0.0 else 1.0) * delta
	var p := Main.I.player
	if life <= 0.0:
		if p == null or global_position.distance_to(p.global_position) > 2600.0:
			remove_from_group("enemies")
			queue_free()
		return
	if p == null or p.hp <= 0.0:
		return
	# кормовая турель: очередь из 4 пуль, только по заднему сектору
	if _shots > 0:
		_shot_t -= delta
		if _shot_t <= 0.0:
			fire_at_player(gun_spread())
			_shots -= 1
			_shot_t = 0.12
		return
	_cd -= delta
	var d := global_position.distance_to(p.global_position)
	if _cd <= 0.0 and d < TAIL_R and _aspect(p.global_position) > PI - deg_to_rad(TAIL_DEG):
		_shots = 4
		_cd = randf_range(1.4, 2.0)


func _die() -> void:
	Main.I.tele.add("bomber_kills", 1.0)
	super()


func _draw() -> void:
	_draw_sectors()
	if not draw_enemy_sprite("e_transport", LEN):
		var xf := Transform2D(heading, Vector2.ZERO)
		var c := body_color(Color(0.42, 0.45, 0.4))
		draw_colored_polygon(xf * PackedVector2Array([Vector2(48, 0), Vector2(34, 8), Vector2(8, 9), Vector2(0, 62), Vector2(-12, 62), Vector2(-14, 9),
			Vector2(-40, 7), Vector2(-50, 26), Vector2(-56, 26), Vector2(-54, 0), Vector2(-56, -26), Vector2(-50, -26), Vector2(-40, -7),
			Vector2(-14, -9), Vector2(-12, -62), Vector2(0, -62), Vector2(8, -9), Vector2(34, -8)]), c)
	draw_hp_bar()


## Задний сектор турели — красный, лобовая броня — синяя дуга у носа
func _draw_sectors() -> void:
	var tail := heading + PI
	var a := deg_to_rad(TAIL_DEG)
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 13:
		pts.append(Vector2.from_angle(tail - a + 2.0 * a * i / 12.0) * TAIL_R)
	draw_colored_polygon(pts, Color(1.0, 0.2, 0.15, 0.05))
	draw_arc(Vector2.ZERO, TAIL_R, tail - a, tail + a, 24, Color(1.0, 0.3, 0.2, 0.35), 3.0)
	var f := deg_to_rad(FRONT_DEG)
	draw_arc(Vector2.ZERO, radius + 18.0, heading - f, heading + f, 16, Color(0.45, 0.75, 1.0, 0.85), 4.0)
