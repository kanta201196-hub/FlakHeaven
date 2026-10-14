class_name Drone
extends Enemy
## Дроны — два подвида:
##  • стрелок (основной): держит дистанцию 380–480 пикс, заходит цепью (у каждого своё место
##    в строю «фронтом»), кружит и стреляет одиночными — перед выстрелом мигает жёлтым;
##    вплотную не лезет — при сближении отваливает в сторону;
##  • камикадзе (единственный подкласс, который таранит): оранжевый «шип», быстрее, без оружия,
##    летит прямо на игрока; его можно перехитрить манёвром или пропустить бочкой.

var kamikaze := false
var lane := 0.0          # смещение в цепи поперёк направления на игрока
var _standoff := 430.0
var _gun_cd := 3.0
var _aim := 0.0
var _orbit := 1.0
var _beep := 0.0


func kind() -> String:
	return "камикадзе" if kamikaze else "дроны"


func _ready() -> void:
	super()
	hp = 12.0
	radius = 11.0
	contact_damage = 18.0 if kamikaze else 6.0
	xp = 1
	parts = 1
	repair_chance = 0.012
	kill_shake = 2.0
	_gun_cd = randf_range(1.5, 3.5)
	_standoff = randf_range(380.0, 480.0)
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
	if kamikaze:
		heading = rotate_toward(heading, to.angle(), deg_to_rad(Tuning.g("drone_turn")) * delta)
		position += Vector2.from_angle(heading) * spd * 1.25 * delta
		_beep -= delta
		return
	# Стрелок: точка в цепи на дистанции от игрока
	var dir := to / maxf(d, 1.0)
	var side := Vector2(-dir.y, dir.x)
	var slot := p.global_position - dir * _standoff + side * lane
	var want := (slot - global_position)
	var desired := want.angle()
	if d < 220.0:
		# слишком близко — отваливаем в сторону, не тараним
		desired = (-dir + side * _orbit).angle()
	elif want.length() < 90.0:
		# на месте — кружим вокруг игрока
		desired = (side * _orbit).angle()
	heading = rotate_toward(heading, desired, deg_to_rad(Tuning.g("drone_turn")) * delta)
	position += Vector2.from_angle(heading) * spd * delta
	if _aim > 0.0:
		_aim -= delta
		if _aim <= 0.0:
			fire_at_player()
			_gun_cd = randf_range(3.0, 5.0)
	else:
		_gun_cd -= delta
		if _gun_cd <= 0.0 and d < 700.0 and d > 160.0:
			_aim = 0.4


func _draw() -> void:
	if kamikaze:
		if draw_enemy_sprite("e_kamikaze", 28.0, Color(1.6, 1.3, 0.6) if int(_beep * -6.0) % 2 == 0 else Color.WHITE):
			return
		var kc := body_color(Color(1.0, 0.5, 0.1))
		if int(_beep * -6.0) % 2 == 0 and _flash <= 0.0:
			kc = Color(1.0, 0.75, 0.3)
		var kp := Transform2D(heading, Vector2.ZERO) * PackedVector2Array([Vector2(15, 0), Vector2(-6, 7), Vector2(-2, 0), Vector2(-6, -7)])
		draw_colored_polygon(kp, kc)
		return
	var c := body_color(Color(0.95, 0.35, 0.3))
	if _aim > 0.0 and _flash <= 0.0:
		c = Color(1.0, 0.9, 0.3)
	if draw_enemy_sprite("e_drone", 34.0, Color(1.6, 1.4, 0.4) if (_aim > 0.0 and int(_aim * 12.0) % 2 == 0) else Color.WHITE):
		return
	var pts := Transform2D(heading, Vector2.ZERO) * PackedVector2Array([Vector2(12, 0), Vector2(0, 8), Vector2(-8, 0), Vector2(0, -8)])
	draw_colored_polygon(pts, c)
