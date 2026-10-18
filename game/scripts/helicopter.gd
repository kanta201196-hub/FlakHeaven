class_name Helicopter
extends Enemy
## Вертолёт огневой поддержки «Сарыч» (модель — tools/blender/helicopter.py): медленный и прочный.
## Подходит на дистанцию залпа, зависает и разворачивается носом к игроку, скользя вбок.
## Перед залпом — предупреждение (веер красных линий + звук захвата), затем залп НАР веером из шести блоков.
## Где он появляется в игре, ещё не решено: пока только по флагу --heli (проверка).

const LEN := 60.0            # длина фюзеляжа на картинке до unit_scale (≈ 18 м при масштабе «2–4 км»)
const SALVO := 6
const FAN := 0.42            # ширина веера залпа, рад
var _cd := 4.0
var _aim := 0.0              # идёт предупреждение перед залпом
var _aim_dir := 0.0
var _side := 1.0
var _t := 0.0
var _vel := Vector2.ZERO


func kind() -> String:
	return "вертолёты"


func _ready() -> void:
	super()
	hp = 110.0
	radius = 26.0
	big = true
	xp = 10
	parts = 6
	repair_chance = 0.2
	kill_shake = 7.0
	_side = 1.0 if randf() < 0.5 else -1.0
	_cd = randf_range(3.0, 5.0)


func behave(delta: float) -> void:
	_t += delta
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		_vel = _vel.lerp(Vector2.from_angle(heading) * 150.0, 1.0 - exp(-delta))
		position += _vel * delta
		return
	var to := p.global_position - global_position
	var d := to.length()
	var dir := to / maxf(d, 1.0)
	# скорость: далеко — летит к игроку, на дистанции залпа — скользит вбок, слишком близко — отходит
	var want := dir * 170.0
	if d < 700.0:
		want = dir.orthogonal() * _side * 70.0 + dir * (d - 600.0) * 0.6
	if _aim > 0.0:
		want *= 0.3          # зависает на время прицеливания
	_vel = _vel.lerp(want, 1.0 - exp(-delta * 1.2))
	position += _vel * delta
	# нос — к игроку (вертолёт может лететь боком); во время прицеливания нос держит направление залпа
	var face := _aim_dir if _aim > 0.0 else to.angle()
	heading = rotate_toward(heading, face, deg_to_rad(70.0) * delta)
	if randf() < delta * 0.08:
		_side = -_side

	if _aim > 0.0:
		_aim -= delta
		if _aim <= 0.0:
			_salvo()
	else:
		_cd -= delta
		if _cd <= 0.0 and d < 850.0 and silence <= 0.0:
			_aim = 1.1
			_aim_dir = to.angle()
			Main.I.sfx.play("lock", -8.0, 0.8)


func _salvo() -> void:
	_cd = randf_range(5.0, 7.0)
	var k := Tuning.g("unit_scale") * LEN / 18.2   # метры модели → пиксели
	for i in SALVO:
		# блоки НАР: по три на ферме с каждого борта (2,3 / 2,88 / 3,46 м от оси)
		var side := -1.0 if i < 3 else 1.0
		var off := Vector2(3.2 * k, side * [2.3, 2.88, 3.46][i % 3] * k).rotated(heading)
		var a := _aim_dir + (float(i) / (SALVO - 1) - 0.5) * FAN
		Main.I.projectiles.spawn_enemy_bullet(global_position + off, Vector2.from_angle(a) * 400.0, kind(), true, 1.0, true)
	Main.I.sfx.play("rocket_launch", -9.0, 0.7)
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: heli salvo at %.0f" % Main.I.run_time)


func _draw() -> void:
	var xf := Transform2D(heading, Vector2.ZERO)
	if not draw_enemy_sprite("e_helicopter", LEN):
		var body := xf * PackedVector2Array([Vector2(26, 0), Vector2(16, 9), Vector2(-6, 9), Vector2(-30, 3), Vector2(-30, -3), Vector2(-6, -9), Vector2(16, -9)])
		draw_colored_polygon(body, body_color(Color(0.45, 0.5, 0.4)))
	if not Render3D.enabled:
		# 2D: несущий винт — полупрозрачный диск с красной кромкой
		var r := LEN * 0.585 * Tuning.g("unit_scale")
		var c := xf * Vector2(LEN * 0.21 * Tuning.g("unit_scale"), 0)
		draw_circle(c, r, Color(0.1, 0.1, 0.1, 0.16))
		draw_arc(c, r, 0.0, TAU, 40, Color(0.7, 0.17, 0.13, 0.5), 2.0)
		for i in 5:
			draw_line(c, c + Vector2.from_angle(-_t * 9.0 + TAU * i / 5.0) * r, Color(0.1, 0.1, 0.1, 0.35), 2.0)
	draw_hp_bar()
	# предупреждение о залпе: веер мигающих линий
	if _aim > 0.0:
		var al := 0.3 + 0.5 * absf(sin(_t * 26.0))
		for i in 3:
			var a := _aim_dir + (float(i) / 2.0 - 0.5) * FAN
			draw_line(Vector2.ZERO, Vector2.from_angle(a) * 520.0, Color(1, 0.15, 0.1, al * (1.0 if i == 1 else 0.6)), 2.0)
