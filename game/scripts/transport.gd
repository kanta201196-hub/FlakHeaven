class_name Transport
extends Enemy
## 3.5: активность «Охота на транспорт» (пункт 21 теста 3.4-t1, решение владельца 16.10.2026).
## Тяжёлый транспортник с двумя турелями и звеном прикрытия пересекает район ~60 с и уходит.
## Прикрытие держит строй, пока вы не подойдёте или не откроете огонь. Транспортник отстреливает
## тепловые ловушки против ракет. Сбит — груз: много запчастей, ремкомплекты и (через раз) выбор
## из редких карточек; ушёл — награды нет.

const LIFE := 60.0
const SPEED := 170.0

var life := LIFE
var _turret_cd := [1.2, 2.0]
var _shots := [0, 0]
var _shot_t := [0.0, 0.0]
var _flare_cd := 0.0
var _escaped := false


func setup(hp_total: float) -> void:
	hp = hp_total
	max_hp = hp_total
	radius = 46.0
	big = true
	no_despawn = true
	contact_damage = 15.0
	xp = 40
	parts = 30
	repair_chance = 1.0
	kill_shake = 12.0


func kind() -> String:
	return "транспортник"


## Прочность задаёт спавнер
func apply_hp_mult(_m: float) -> void:
	pass


## Звено прикрытия: слоты вокруг транспортника (в его осях: x — вперёд, y — вбок)
func spawn_escort(n: int, hp_k: float) -> void:
	var slots := [Vector2(40, -150), Vector2(40, 150), Vector2(-150, 0), Vector2(160, 0)]
	for i in n:
		var e := Interceptor.new()
		e.escort = self
		e.escort_slot = slots[i % slots.size()]
		e.position = global_position + (e.escort_slot as Vector2).rotated(heading)
		e.heading = heading
		Main.I.world.add_child(e)
		e.apply_hp_mult(hp_k)
		if i == 3:
			e.make_elite()


func behave(delta: float) -> void:
	life -= delta
	position += Vector2.from_angle(heading) * SPEED * (1.6 if life <= 0.0 else 1.0) * delta
	var p := Main.I.player
	if life <= 0.0:
		if not _escaped:
			_escaped = true
			Main.I.show_banner("Транспортник ушёл — груз потерян", 3.0)
			Main.I.on_activity_failed("transport")
			if Main.I.spawner != null and Main.I.spawner.activity_node == self:
				Main.I.spawner.activity_node = null
		if p == null or global_position.distance_to(p.global_position) > 2600.0:
			remove_from_group("enemies")
			queue_free()
		return
	if p == null or p.hp <= 0.0:
		return
	_flare_cd -= delta
	if _flare_cd <= 0.0 and pop_flares(420.0, 240.0, 0.6) > 0:
		_flare_cd = 6.0
	# две турели (верхняя и хвостовая): очередь из 3 пуль, если игрок ближе 650
	var d := global_position.distance_to(p.global_position)
	for i in 2:
		if _shots[i] > 0:
			_shot_t[i] -= delta
			if _shot_t[i] <= 0.0:
				fire_at_player(randf_range(-0.08, 0.08))
				_shots[i] -= 1
				_shot_t[i] = 0.11
			continue
		_turret_cd[i] -= delta
		if _turret_cd[i] <= 0.0 and d < 650.0:
			_shots[i] = 3
			_turret_cd[i] = randf_range(1.6, 2.2)


func _die() -> void:
	var m := Main.I
	m.activities_done += 1
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: activity success transport at %.0f" % m.run_time)
	# груз: запчасти и ремкомплекты; через раз — выбор из редких карточек (как у других активностей)
	m.parts += 90.0 * m.continue_mult()
	for i in 3:
		m.pickups.drop_repair(global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60)))
	var rare := m.activities_done % 2 == 1
	if rare:
		m.pending_levels += 1
		m.rare_picks += 1
		m.rare_reasons.append("ЗА ГРУЗ ТРАНСПОРТА")
	m.player.add_course_pts(1)
	m.show_banner("Транспортник сбит! Груз: +90 запчастей, ремкомплекты" + (" и выбор из редких карточек" if rare else ""), 4.0)
	m.sfx.play("evac", -4.0, 1.3)
	if m.spawner != null and m.spawner.activity_node == self:
		m.spawner.activity_node = null
	super()


func _draw() -> void:
	if not draw_enemy_sprite("e_transport", 190.0):
		var xf := Transform2D(heading, Vector2.ZERO)
		var c := body_color(Color(0.45, 0.5, 0.42))
		draw_colored_polygon(xf * PackedVector2Array([Vector2(70, 0), Vector2(50, 12), Vector2(10, 14), Vector2(0, 95), Vector2(-18, 95), Vector2(-20, 14),
			Vector2(-60, 10), Vector2(-75, 40), Vector2(-85, 40), Vector2(-80, 0), Vector2(-85, -40), Vector2(-75, -40), Vector2(-60, -10),
			Vector2(-20, -14), Vector2(-18, -95), Vector2(0, -95), Vector2(10, -14), Vector2(50, -12)]), c)
	draw_hp_bar()
	draw_string(Hud.ui_font(), Vector2(-120, -radius - 24.0), "Транспортник", HORIZONTAL_ALIGNMENT_CENTER, 240, 18, Color(1, 0.85, 0.6))
