class_name Enemy
extends Node2D
## Базовый враг: здоровье, вспышка при попадании, контактный урон.

var hp := 10.0
var max_hp := 10.0
var radius := 14.0
var big := false
var kill_shake := 2.0
var contact_damage := 0.0
var heading := 0.0
var is_boss := false
var is_ground := false   # наземная цель: не таранит, ракеты В-В по ней не стреляют
var no_despawn := false  # не исчезает вдали (цели активностей)
var xp := 1          # опыт за сбитие
var parts := 1       # запчасти (валюта ангара) за сбитие
var repair_chance := 0.02
var _flash := 0.0
var elite := false
var silence := 0.0
var move_vel := Vector2.ZERO   # 3.1: фактическая скорость (для пуль стрелка)
var _prev_pos := Vector2.INF   # 3.1: ЭМИ «Ласки» — враг молчит


func make_elite() -> void:
	elite = true
	hp *= 3.0
	max_hp = hp
	xp *= 3
	parts *= 3
	radius *= 1.15


func _ready() -> void:
	add_to_group("enemies")
	z_index = 1
	_scale_hitbox.call_deferred()


## 2.7: картинки врагов крупнее (unit_scale) — хитбокс растёт мягче (корень), чтобы попадания совпадали с картинкой
func _scale_hitbox() -> void:
	radius *= sqrt(Tuning.g("unit_scale"))


## Название типа для статистики после вылета.
func kind() -> String:
	return "враг"


func take_hit(dmg: float, source := "прочее") -> void:
	if hp <= 0.0:
		return
	if is_instance_valid(Main.I.player):
		dmg *= float(Main.I.player.mods.get("dmg_all", 1.0))
		if is_ground:
			dmg *= float(Main.I.player.mods.get("ground_dmg", 1.0)) # перк «Наводчик»
	dmg = absorb(dmg)
	if dmg <= 0.0:
		_flash = 0.03
		return
	Main.I.add_stat("dealt", source, minf(dmg, hp))
	hp -= dmg
	_flash = 0.06
	Main.I.on_enemy_hit(self, dmg)
	if hp <= 0.0:
		_die()


## Щит (у асов): поглощает урон до того, как он дойдёт до корпуса.
func absorb(dmg: float) -> float:
	return dmg


func _die() -> void:
	hp = 0.0
	remove_from_group("enemies")
	Main.I.on_enemy_killed(self)
	Main.I.pickups.drop_xp(global_position, xp * Main.I.streak_mult())
	if randf() < repair_chance:
		Main.I.pickups.drop_repair(global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
	queue_free()


func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta)
	if _prev_pos != Vector2.INF and delta > 0.0:
		move_vel = move_vel.lerp((global_position - _prev_pos) / delta, 0.3)
	_prev_pos = global_position
	if silence > 0.0:
		silence -= delta
	else:
		behave(delta)
	if not is_boss and not is_ground and Main.I.spawner != null:
		position += Main.I.spawner.separation(self) * 220.0 * delta
	_check_contact()
	# Карта бесконечная: отставших далеко позади тихо убираем (без награды)
	var p := Main.I.player
	if not is_boss and not is_ground and not no_despawn and p != null and global_position.distance_to(p.global_position) > 2800.0:
		remove_from_group("enemies")
		queue_free()
		return
	queue_redraw()


func behave(_delta: float) -> void:
	pass


func _check_contact() -> void:
	if contact_damage <= 0.0 or is_ground:
		return
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return
	if global_position.distance_to(p.global_position) < radius + p.radius:
		if (p.shield_t > 0.0 or p.ram_t > 0.0) and not is_boss:
			# Бронещит: таран без урона себе
			Main.I.add_stat("dealt", "бронещит", hp)
			_die()
		elif not p.is_invulnerable():
			# на форсаже самолёт проходит строй: столкновение бьёт втрое слабее
			p.damage(contact_damage * (0.3 if p.ab_t > 0.0 else 1.0), "таран", kind())
			if not is_boss:
				_die()


func body_color(base: Color) -> Color:
	return Color.WHITE if _flash > 0.0 else base


## Вызывает спавнер после появления: прочность × множитель.
func apply_hp_mult(m: float) -> void:
	hp *= m
	max_hp = hp


## Полоска прочности у повреждённых крупных врагов.
func draw_hp_bar() -> void:
	if hp >= max_hp or max_hp < 30.0:
		return
	var w := radius * 2.0
	draw_rect(Rect2(-radius, -radius - 12.0, w, 4.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-radius, -radius - 12.0, w * hp / max_hp, 4.0), Color(1.0, 0.4, 0.3))


## Выстрел по игроку с упреждением.
func fire_at_player(spread := 0.0) -> void:
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return
	var spd := Tuning.g("ebullet_speed")
	var to := p.global_position - global_position
	var lead := p.global_position + p.velocity * (to.length() / spd) * 0.6
	var dir := (lead - global_position).normalized().rotated(spread)
	# 3.1: пуля летит быстрее стрелка — к её скорости добавляется скорость самолёта по курсу
	var add := maxf(0.0, move_vel.dot(dir)) * 0.6 if not is_ground else 0.0 # 3.2: пуля всё ещё быстрее стрелка, но мягче
	Main.I.projectiles.spawn_enemy_bullet(global_position + dir * (radius + 4.0), dir * (spd + add), kind())


## Спрайт врага (2.6): res://art/enemies/<name>.png, нос ВПРАВО. Нет файла — вернёт false (рисуем фигуру).
## Тень на земле, светлый контур (чтобы тёмный корпус читался на любом фоне), вспышка при попадании.
static var _etex := {}
var _spr := {}   # 3.0: что рисовать в 3D (заполняет draw_enemy_sprite)


static func etex(tex_name: String) -> Texture2D:
	if not _etex.has(tex_name):
		var p := "res://art/enemies/%s.png" % tex_name
		_etex[tex_name] = load(p) if ResourceLoader.exists(p) else null
	return _etex[tex_name]


## Для 3D: {tex, len, angle}
func sprite_info() -> Dictionary:
	return _spr


func draw_enemy_sprite(tex_name: String, length: float, tint := Color.WHITE, angle := INF) -> bool:
	var t: Texture2D = etex(tex_name)
	if t == null or Tuning.g("sprites") < 1:
		return false
	var ang := heading if angle == INF else angle
	_spr = {"tex": tex_name, "len": length, "angle": ang}
	if Render3D.enabled:
		return true
	var k := length * Tuning.g("unit_scale") * (1.2 if elite else 1.0) / float(t.get_width())
	var half := t.get_size() / 2.0
	draw_set_transform(Vector2(5.0, 8.0) if is_ground else Vector2(16.0, 24.0), ang, Vector2(k, k) * (1.0 if is_ground else 0.92))
	draw_texture(t, -half, Color(0, 0, 0, 0.3))
	var rim := Color(1.0, 0.75, 0.2, 0.9) if elite else Color(1.0, 0.85, 0.8, 0.55)
	for o in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		draw_set_transform(o, ang, Vector2(k, k))
		draw_texture(t, -half, rim * Color(10, 10, 10, 1)) # силуэт, высветленный до белого
	draw_set_transform(Vector2.ZERO, ang, Vector2(k, k))
	draw_texture(t, -half, Color(4, 4, 4, 1) if _flash > 0.0 else tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
