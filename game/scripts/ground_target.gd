class_name GroundTarget
extends Enemy
## Наземная цель (позиция ПВО). Не таранит, ракеты «воздух-воздух» её не берут —
## работают курсовое, НАР, бомбы, гондолы, турели и навыки.
##   zsu    — зенитная установка: очереди по 4 снаряда с упреждением, вспышка перед очередью;
##   sam    — зенитный ракетный комплекс: захват (красная линия) → ракета;
##   radar  — РЛС: пока жива, ЗСУ и ЗРК стреляют дальше (+30%);
##   bunker — командный бункер: прочный, без оружия.

var variant := "zsu"
var site: AASite
var _cd := 2.0
var _aim := 0.0
var _shots := 0
var _shot_t := 0.0
var _lock := 0.0
var _t := 0.0
var _spin := 0.0


var _body_angle := 0.0


func setup(v: String, s: AASite, hp_mult: float) -> void:
	variant = v
	site = s
	_body_angle = randf() * TAU
	is_ground = true
	no_despawn = true
	big = v != "zsu"
	match v:
		"zsu":
			hp = 90.0
			radius = 20.0
			xp = 4
			parts = 4
		"sam":
			hp = 120.0
			radius = 24.0
			xp = 5
			parts = 5
		"radar":
			hp = 80.0
			radius = 22.0
			xp = 3
			parts = 3
		"bunker":
			hp = 260.0
			radius = 32.0
			xp = 8
			parts = 10
	hp *= hp_mult
	max_hp = hp
	repair_chance = 0.15
	kill_shake = 6.0
	_cd = randf_range(1.0, 2.5)


func kind() -> String:
	return "ПВО"


## Наземные цели не масштабируются спавнером
func apply_hp_mult(_m: float) -> void:
	pass


func _ready() -> void:
	super()
	z_index = -2


func _range() -> float:
	var r := 650.0 if variant == "zsu" else 900.0
	if site != null and site.radar_alive():
		r *= 1.3
	return r


func behave(delta: float) -> void:
	_t += delta
	_spin += delta * 1.5
	var p := Main.I.player
	if p == null or p.hp <= 0.0 or site == null or not site.active:
		return
	var to := p.global_position - global_position
	var d := to.length()
	heading = rotate_toward(heading, to.angle(), deg_to_rad(120.0) * delta)
	match variant:
		"zsu":
			if _shots > 0:
				_shot_t -= delta
				if _shot_t <= 0.0:
					fire_at_player(randf_range(-0.07, 0.07))
					_shots -= 1
					_shot_t = 0.09
			elif _aim > 0.0:
				_aim -= delta
				if _aim <= 0.0:
					_shots = 4
			else:
				_cd -= delta
				if _cd <= 0.0 and d < _range():
					_aim = 0.4
					_cd = randf_range(1.8, 2.6)
		"sam":
			if _lock > 0.0:
				_lock -= delta
				if _lock <= 0.0:
					Main.I.projectiles.spawn_missile(global_position, to.normalized())
					Main.I.sfx.play("missile_enemy", -6.0, 0.9)
			else:
				_cd -= delta
				if _cd <= 0.0 and d < _range():
					_lock = 1.2
					_cd = randf_range(5.0, 6.5)
					Main.I.sfx.play("lock", -6.0, 1.2)


func _die() -> void:
	if site != null:
		site.on_target_destroyed(self)
	super()


func _draw() -> void:
	# тень-подложка, чтобы наземное читалось «ниже» самолётов
	var spr := {"zsu": ["e_zsu", 44.0], "sam": ["e_sam", 54.0], "radar": ["e_radar", 50.0], "bunker": ["e_bunker", 66.0]}
	var ba: float = heading if variant in ["zsu", "sam"] else _body_angle
	if draw_enemy_sprite(spr[variant][0], spr[variant][1], Color.WHITE, ba):
		if variant == "zsu" and (_aim > 0.0 or _shots > 0):
			draw_circle(Vector2.from_angle(heading) * 30.0, 6.0, Color(1.0, 0.9, 0.3))
		if variant == "sam" and _lock > 0.0:
			var pl := Main.I.player
			if pl != null and pl.hp > 0.0:
				var al := 0.35 + 0.5 * absf(sin(_t * 30.0))
				draw_line(Vector2.ZERO, to_local(pl.global_position), Color(1, 0.15, 0.1, al), 2.0)
		draw_hp_bar()
		return
	draw_circle(Vector2(4, 5), radius + 4.0, Color(0, 0, 0, 0.25))
	var base := Color(0.45, 0.5, 0.38)
	match variant:
		"zsu":
			draw_rect(Rect2(-16, -12, 32, 24), body_color(base))
			var tip := Vector2.from_angle(heading) * 24.0
			draw_line(Vector2.ZERO, tip, body_color(Color(0.3, 0.33, 0.27)), 5.0)
			if _aim > 0.0 or _shots > 0:
				draw_circle(tip, 6.0, Color(1.0, 0.9, 0.3))
		"sam":
			draw_rect(Rect2(-20, -16, 40, 32), body_color(base))
			var xf := Transform2D(heading, Vector2.ZERO)
			for i in 2:
				var off := Vector2(0, -7 + 14 * i)
				draw_line(xf * (off + Vector2(-10, 0)), xf * (off + Vector2(18, 0)), body_color(Color(0.85, 0.85, 0.8)), 4.0)
			if _lock > 0.0:
				var p := Main.I.player
				if p != null and p.hp > 0.0:
					var a := 0.35 + 0.5 * absf(sin(_t * 30.0))
					draw_line(Vector2.ZERO, to_local(p.global_position), Color(1, 0.15, 0.1, a), 2.0)
		"radar":
			draw_circle(Vector2.ZERO, 14.0, body_color(base))
			var dish := Vector2.from_angle(_spin) * 20.0
			draw_line(-dish, dish, body_color(Color(0.8, 0.85, 0.8)), 4.0)
		"bunker":
			draw_rect(Rect2(-28, -22, 56, 44), body_color(Color(0.4, 0.42, 0.38)))
			draw_rect(Rect2(-28, -22, 56, 44), Color(0.2, 0.22, 0.2), false, 3.0)
			draw_rect(Rect2(-12, -4, 24, 8), Color(0.15, 0.15, 0.12))
	draw_hp_bar()
