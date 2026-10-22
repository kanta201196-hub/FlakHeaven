class_name MissileCarrier
extends Enemy
## Ракетоносец: держит дистанцию, кружит вокруг игрока.
## Перед пуском — предупреждение (красная линия захвата + звук), затем самонаводящаяся ракета.
## Тест уклонения: бочка (неуязвимость), форсаж (оторваться), резкий разворот (ракета проскакивает).
## EX-03 (отзывы внешних тестеров 21.10): держится дальше (520–850 пикс.) и пускает ракету только по очереди
## на атаку (спавнер), а не все разом.

var _cd := 3.0
var _lock := 0.0
var _orbit := 1.0
var _t := 0.0


func kind() -> String:
	return "ракетоносцы"


func _ready() -> void:
	super()
	hp = 60.0
	radius = 22.0
	big = true
	xp = 8
	parts = 5
	repair_chance = 0.15
	kill_shake = 6.0
	_orbit = 1.0 if randf() < 0.5 else -1.0
	_cd = randf_range(2.0, 4.0)


func behave(delta: float) -> void:
	_t += delta
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		position += Vector2.from_angle(heading) * 200.0 * delta
		return
	var to := p.global_position - global_position
	var d := to.length()
	var desired := to.angle()
	if d < 520.0:
		desired = to.angle() + PI
	elif d < 850.0:
		desired = to.angle() + PI / 2.0 * _orbit
	heading = rotate_toward(heading, desired, deg_to_rad(90.0) * delta)
	position += Vector2.from_angle(heading) * 200.0 * delta

	if _lock > 0.0:
		_lock -= delta
		if _lock <= 0.0:
			Main.I.projectiles.spawn_missile(global_position, to.normalized(), "aam", kind())
			Main.I.sfx.play("missile_enemy", -8.0)
			_cd = 4.5
			if Main.I.spawner != null:
				Main.I.spawner.release_attack(self)
	else:
		_cd -= delta
		if _cd <= 0.0 and d < 1000.0 and not leaving:
			if Main.I.spawner == null or Main.I.spawner.request_attack(self):
				_lock = Tuning.g("missile_telegraph")
				Main.I.sfx.play("lock", -6.0)
			else:
				_cd = randf_range(0.5, 1.0)


func _draw() -> void:
	var c := body_color(Color(1.0, 0.6, 0.2))
	var xf := Transform2D(heading, Vector2.ZERO)
	if not draw_enemy_sprite("e_seaplane" if Biome.sea() else "e_carrier", 60.0):   # «Архипелаг»: гидросамолёт «Буревестник» (E-07)
		var body := xf * PackedVector2Array([Vector2(24, 0), Vector2(4, 8), Vector2(-6, 24), Vector2(-14, 8), Vector2(-18, 0), Vector2(-14, -8), Vector2(-6, -24), Vector2(4, -8)])
		draw_colored_polygon(body, c)
	draw_hp_bar()
	# Предупреждение о пуске: пульсирующая линия захвата и метка на игроке
	if _lock > 0.0:
		var p := Main.I.player
		if p != null and p.hp > 0.0:
			var a := 0.35 + 0.5 * absf(sin(_t * 30.0))
			var target := to_local(p.global_position)
			draw_line(Vector2.ZERO, target, Color(1, 0.15, 0.1, a), 2.0)
			draw_arc(target, 26.0, 0.0, TAU, 32, Color(1, 0.15, 0.1, a), 2.0)
