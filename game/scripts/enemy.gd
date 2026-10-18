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
var leaving := false     # уходит с поля (перед асом): не стреляет, не таранит, исчезает за краем экрана
var xp := 1          # опыт за сбитие
var parts := 1       # запчасти (валюта ангара) за сбитие
var repair_chance := 0.02
var _flash := 0.0
var elite := false
var born_t := -1.0       # правка 3.5-s4: когда появился (для «напряжения боя» в спавнере)
var min_life := 0.0      # правка 3.5-s4: асы — корпус не быстрее чем за min_life с (предел урона в секунду)
var _cap_budget := -1.0
var _cap_t := 0.0
var silence := 0.0
var move_vel := Vector2.ZERO   # 3.1: фактическая скорость (для пуль стрелка)
var _prev_pos := Vector2.INF   # 3.1: ЭМИ «Ласки» — враг молчит
## 3.5: наземная цель стоит в точке рельефа (anchor). Логическая позиция — проекция этой точки
## на слой самолётов с камеры, чтобы на наклонной камере цель не «ехала» по земле.
var anchor := Vector2.INF
## 3.5: уклонение — рывок вбок с бочкой (видно в 3D), чтобы уйти с линии огня
var evade_t := 0.0
var evade_time := 0.7
var _evade_v := Vector2.ZERO
var _evade_roll := 1.0
## правка 3.5-s4 (п. 26): расталкивание сглажено и уходит в курс — враги не дёргаются и не слипаются
var _sep := Vector2.ZERO


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
	if (is_boss or self is RivalAce) and Main.I.spawner != null:
		# тест 3.5-s5 (п. 10): урон по асу — мерило прочности следующих асов (Spawner.single_k);
		# второй список, п. 5: и по асу-сопернику в дуэли — тогда и первый ас по силам классу
		var pool := hp + float(get("shield")) if is_boss else hp
		Main.I.spawner.note_big(minf(dmg, pool), self, source)
	dmg = absorb(dmg)
	if min_life > 0.0:
		dmg = _cap_dps(dmg)
	if dmg <= 0.0:
		_flash = 0.03
		return
	Main.I.add_stat("dealt", source, minf(dmg, hp))
	hp -= dmg
	_flash = 0.06
	Main.I.on_enemy_hit(self, dmg)
	if hp <= 0.0:
		_die()


## Правка 3.5-s4 (лог «Осы»: асы падали за 10 с): корпус аса принимает не больше max_hp / min_life в секунду,
## с запасом на 1,5 с — короткий мощный залп проходит, но поток урона любой силы не убьёт аса за секунды
func _cap_dps(dmg: float) -> float:
	var rate := max_hp / min_life
	var now := Main.I.run_time
	if _cap_budget < 0.0:
		_cap_budget = rate * 1.5
	else:
		_cap_budget = minf(rate * 1.5, _cap_budget + rate * maxf(0.0, now - _cap_t))
	_cap_t = now
	var d := minf(dmg, _cap_budget)
	_cap_budget -= d
	return d


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
	if anchor != Vector2.INF:
		global_position = GroundTarget.air_pos(anchor)
	if leaving:
		_leave(delta)
		return
	if silence > 0.0:
		silence -= delta
	else:
		behave(delta)
	if evade_t > 0.0:
		evade_t -= delta
		position += _evade_v * delta * clampf(evade_t / evade_time * 1.6, 0.0, 1.0)
	if not is_boss and not is_ground and Main.I.spawner != null:
		_sep = _sep.lerp(Main.I.spawner.separation(self), 1.0 - exp(-delta * 5.0))
		if _sep.length_squared() > 1e-4:
			position += _sep * 150.0 * delta
			# отвернуть от соседа, а не скользить боком — курс плавный, крен в 3D без дрожи
			var fw := Vector2.from_angle(heading)
			heading = rotate_toward(heading, (fw + _sep * 1.2).angle(), deg_to_rad(50.0) * delta)
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


## Уйти с поля: разворот от игрока, разгон и исчезновение, когда уже не видно (без награды)
func leave() -> void:
	if is_boss or is_ground or no_despawn:
		return
	leaving = true


func _leave(delta: float) -> void:
	var p := Main.I.player
	var away := Vector2.from_angle(heading)
	if p != null:
		away = global_position - p.global_position
	heading = rotate_toward(heading, away.angle(), deg_to_rad(120.0) * delta)
	position += Vector2.from_angle(heading) * 380.0 * delta
	var far := 1500.0 * (1.0 + 0.5 * sin(deg_to_rad(Tuning.g("cam_tilt"))))
	if p == null or global_position.distance_to(p.global_position) > far:
		remove_from_group("enemies")
		queue_free()
		return
	queue_redraw()


# ---------- 3.5: уклонение и ловушки ----------

## Крен для 3D: полный оборот за время рывка
func roll_angle() -> float:
	if evade_t <= 0.0:
		return 0.0
	return (1.0 - evade_t / evade_time) * TAU * _evade_roll


## Рывок вбок от линии огня threat (направление полёта пуль / ракет). side 0 — выбрать самому.
func start_evade(threat: Vector2, spd := 300.0, time := 0.7) -> void:
	if evade_t > 0.0:
		return
	var perp := Vector2(-threat.y, threat.x).normalized()
	var p := Main.I.player
	# уходим в ту сторону, где мы и так уже от линии огня
	if p != null and perp.dot(global_position - p.global_position) < 0.0:
		perp = -perp
	if randf() < 0.2:
		perp = -perp # иногда — в неожиданную сторону
	evade_time = time
	evade_t = time
	_evade_v = perp * spd
	_evade_roll = signf(perp.cross(Vector2.from_angle(heading))) if absf(perp.cross(Vector2.from_angle(heading))) > 0.01 else 1.0
	Main.I.tele.add("enemy_evades")


## Летят ли в нас пули игрока: вернёт направление огня (или ZERO). Дорого — только для асов и элиты.
func incoming_fire(look := 0.45, min_n := 2) -> Vector2:
	var n := 0
	var dir := Vector2.ZERO
	var pos := global_position
	var rr := (radius + 45.0) * (radius + 45.0)
	for b in Main.I.projectiles.bullets:
		var bp: Vector2 = b["p"]
		var rel := pos - bp
		if rel.length_squared() > 360000.0:
			continue
		var v: Vector2 = b["v"]
		var vv := v.length_squared()
		if vv < 1.0:
			continue
		var t := rel.dot(v) / vv
		if t < 0.0 or t > look:
			continue
		if (bp + v * t).distance_squared_to(pos) < rr:
			n += 1
			dir += v
	return dir.normalized() if n >= min_n else Vector2.ZERO


## Нос игрока смотрит на нас (дешёвая проверка для обычных врагов)
func player_aiming(cone_deg := 9.0, dist := 700.0) -> Vector2:
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return Vector2.ZERO
	var to := global_position - p.global_position
	if to.length() > dist:
		return Vector2.ZERO
	if absf(wrapf(to.angle() - p.heading, -PI, PI)) > deg_to_rad(cone_deg):
		return Vector2.ZERO
	return to.normalized()


## Правка 3.5-s4: ловушки зарядами. Ракета подошла ближе trigger_r — тратится заряд, и cover секунд
## вокруг аса горят ловушки: каждая наша ракета ближе r уходит на них с шансом chance.
## Заряды восстанавливаются по одному за recharge с. Против потока ракет ас держится, пока есть заряды.
var flare_charges := 3
var _fl_on := 0.0
var _fl_tick := 0.0
var _fl_rech := 0.0


func flare_defense(delta: float, r: float, trigger_r: float, chance: float, cover := 2.5, recharge := 7.0, charges_max := 3) -> void:
	if flare_charges < charges_max:
		_fl_rech -= delta
		if _fl_rech <= 0.0:
			flare_charges += 1
			_fl_rech = recharge
	if _fl_on > 0.0:
		_fl_on -= delta
		_fl_tick -= delta
		if _fl_tick <= 0.0:
			_fl_tick = 0.25
			pop_flares(r, r, chance)
		return
	if flare_charges > 0 and pop_flares(r, trigger_r, chance) > 0:
		flare_charges -= 1
		if _fl_rech <= 0.0:
			_fl_rech = recharge
		_fl_on = cover
		_fl_tick = 0.25


## Тепловые ловушки: ракеты игрока, которые идут в нас ближе r, с шансом chance уходят на ловушки и рвутся.
## Вернёт число уведённых ракет. Ловушки отстреливаются, только если ракета уже близко (видно, что сработало).
func pop_flares(r := 420.0, trigger_r := 230.0, chance := 0.8) -> int:
	var pr := Main.I.projectiles
	var close := false
	for m in pr.pmissiles:
		if (m["t"] as WeakRef).get_ref() == self and (m["p"] as Vector2).distance_to(global_position) < trigger_r:
			close = true
			break
	if not close:
		return 0
	var fl: Array = Main.I.fx.flare_burst(global_position, heading, 8, move_vel)
	var n := 0
	for i in range(pr.pmissiles.size() - 1, -1, -1):
		var m: Dictionary = pr.pmissiles[i]
		if (m["t"] as WeakRef).get_ref() != self:
			continue
		var mp: Vector2 = m["p"]
		if mp.distance_to(global_position) > r or randf() > chance:
			continue
		var f: Dictionary = fl[n % fl.size()]
		var at := mp.lerp(f["p"] as Vector2 + (f["v"] as Vector2) * 0.25, 0.6)
		Main.I.fx.explosion(at, 14.0, true, true, "flak")
		pr.pmissiles.remove_at(i)
		n += 1
	Main.I.tele.add("enemy_flares")
	Main.I.tele.add("enemy_flared_missiles", n)
	return n


func _check_contact() -> void:
	if contact_damage <= 0.0 or is_ground:
		return
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return
	if p.dive_t > 0.0:
		return   # правка 3.5-s4: в нырке игрок проходит под самолётами — ни урона, ни столкновения
	if global_position.distance_to(p.global_position) < radius + p.radius:
		# второй список 3.5-s5, п. 7: ас-соперник в дуэли и транспортник от столкновения не падают, как и асы
		var tough := is_boss or self is RivalAce or self is Transport
		if (p.shield_t > 0.0 or p.ram_t > 0.0) and not tough:
			# Бронещит: таран без урона себе
			Main.I.add_stat("dealt", "бронещит", hp)
			_die()
		elif not p.is_invulnerable():
			# на форсаже самолёт проходит строй: столкновение бьёт втрое слабее
			p.damage(contact_damage * (0.3 if p.ab_t > 0.0 else 1.0), "таран", kind())
			if not tough:
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
## twin — спаренная пушка: две параллельные пули по половине урона (3.5, дрон)
func fire_at_player(spread := 0.0, twin := false) -> void:
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return
	var spd := Tuning.g("ebullet_speed")
	var to := p.global_position - global_position
	var lead := p.global_position + p.velocity * (to.length() / spd) * 0.6
	var dir := (lead - global_position).normalized().rotated(spread)
	# 3.1: пуля летит быстрее стрелка — к её скорости добавляется скорость самолёта по курсу
	var add := maxf(0.0, move_vel.dot(dir)) * 0.6 if not is_ground else 0.0 # 3.2: пуля всё ещё быстрее стрелка, но мягче
	var at := global_position + dir * (radius + 4.0)
	if twin:
		var side := Vector2(-dir.y, dir.x) * 5.0
		Main.I.projectiles.spawn_enemy_bullet(at + side, dir * (spd + add), kind(), false, 0.5)
		Main.I.projectiles.spawn_enemy_bullet(at - side, dir * (spd + add), kind(), false, 0.5, true)
		return
	Main.I.projectiles.spawn_enemy_bullet(at, dir * (spd + add), kind())


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
