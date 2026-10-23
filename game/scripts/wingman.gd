class_name Wingman
extends Node2D
## Ведомый (3.1): тип — «Стриж» (прикрытие), «Грачонок» (штурмовик), «Ласка» (подавитель ПВО).
## Держит место в строю, у каждого своя задача, уровень 1–3 («слётанность»), прочность.
## Сбитый возвращается через 20 с (12 с с нашивкой «Звено I»); временные («Грачата») — уходят.

var slot := 0
var k := 1.0          # сила ведомого (редкость карточки)
var type := "swift"
var lvl := 1
var temp := false     # временный («Грачата»)
var life := 0.0       # сколько осталось временному
var heading := 0.0
var velocity := Vector2.ZERO
var max_hp := 60.0
var hp := 60.0
var dead_t := 0.0     # > 0 — сбит, вернётся
var _fire_cd := 0.0
var _aam_cd := 3.0
var _special_cd := 4.0
var _guard_cd := 0.0
var _emp_cd := 15.0
var _bomb_cd := 6.0   # «Тёплая компания»
var _salvo_left := 0
var _salvo_dmg := 40.0
var _salvo_iv := 0.3
var _salvo_t := 0.0
var _flash := 0.0


func _ready() -> void:
	z_index = 2
	refresh_hp()
	hp = max_hp


func setup(p_type: String, p_k: float, p_temp := false, p_life := 0.0) -> void:
	type = p_type
	k = p_k
	temp = p_temp
	life = p_life


func alive() -> bool:
	return dead_t <= 0.0 and visible


func refresh_hp() -> void:
	var p := Main.I.player if Main.I != null else null
	var base := 60.0 * (1.5 if type == "rook" else 1.0) * (0.5 if temp else 1.0)
	if p != null:
		base *= float(p.mods.get("wing_hp", 1.0))
	var old := max_hp
	max_hp = base * (1.0 + 0.2 * (lvl - 1))
	hp = minf(max_hp, hp + maxf(0.0, max_hp - old))


func dmg_k() -> float:
	var p := Main.I.player
	var d := k * float(p.mods.get("wing_dmg", 1.0)) if p != null else k
	if lvl >= 2:
		d *= 1.4
	return d


func src() -> String:
	return "ведомые: " + String(Prog.WING_TYPES[type]["short"]).to_lower()


func repair(frac: float) -> void:
	if alive():
		hp = minf(max_hp, hp + max_hp * frac)


func damage(amount: float) -> void:
	var p := Main.I.player
	if not alive() or Main.I.god_mode:
		return
	if p != null and p.umbrella_t > 0.0 and p.syn.has("s_shelter"):
		return # «Под одним зонтом»
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		Main.I.fx.explosion(global_position, 22.0)
		Main.I.stats_add_counter("wingmen_lost", 1)
		if temp:
			_leave()
			return
		dead_t = 20.0
		visible = false
		# S9-12: потеря ведомого — в эфир (очередью, не перебивая), замена — через 20 с
		Story.say(String(Prog.WING_TYPES[type]["short"]), "Подбит, выхожу из боя! Замена через 20 секунд.")
		Story.say(Story.DISPATCH, "Ведомый сбит. Держитесь, замена на подходе.")


## Залп ракет В-В: n ракет за время over (навыки «Сомкнуть строй», «Под одним зонтом», «Парад»)
func salvo(n: int, dmg: float, over := 0.4) -> void:
	if not alive():
		return
	_salvo_left += n
	_salvo_dmg = dmg
	_salvo_iv = maxf(0.08, over / maxf(n, 1))
	_salvo_t = 0.0


func _slot_offset(p: Player) -> Vector2:
	# 3.5 (правка 23): сначала места по бокам (крыло к крылу), следующие — впереди-сбоку
	# («Грачата» сверх двух постоянных); «Сомкнуть строй» — ближе.
	# правка 3.5-s4 (п. 23): просвет считается по размаху моделей — ведомый не залезает в самолёт ведущего
	var side := -1.0 if slot % 2 == 0 else 1.0
	var row := slot / 2
	var span := clear_r(p)
	var lat := span + (10.0 if p.ranks_t > 0.0 else 40.0)
	var base := Vector2(-20.0, side * lat) if row == 0 else Vector2(span * 0.6 + 40.0 * (row - 1), side * (lat + 30.0 * row))
	var off := base.rotated(_form_h if not is_nan(_form_h) else p.heading)
	if _run_t > 0.0: # «Тёплая компания»: заход вперёд
		off += Vector2.from_angle(p.heading) * 330.0 * sin(clampf(1.0 - _run_t / 1.2, 0.0, 1.0) * PI)
	return off


## Ближе этого (центр к центру) ведомый к ведущему не подходит: половины размахов обоих самолётов
func clear_r(p: Player) -> float:
	return Tuning.g("plane_len") * (p.size + 0.85) * 0.5 + 8.0


func _leave() -> void:
	var p := Main.I.player
	if p != null:
		# «Грачата» III: уходя, сбрасывает 4 бомбы
		if type == "rook" and temp and p.lvl_of("rooks") >= 3:
			for i in 4:
				var to := global_position + Vector2.from_angle(heading + (i - 1.5) * 0.5) * 180.0
				Main.I.projectiles.spawn_bomb(global_position, 0.5 + 0.06 * i, 35.0 * dmg_k(), 110.0, src(), to)
		p.wingmen.erase(self)
		p.reslot_wingmen()
	queue_free()


func _process(delta: float) -> void:
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta)
	if temp:
		life -= delta
		if life <= 0.0:
			_leave()
			return
	if dead_t > 0.0:
		dead_t -= delta
		if dead_t <= 0.0:
			# правка 3.5-s4 (п. 21): замена прилетает из-за края экрана сзади-сбоку и догоняет строй
			visible = true
			hp = max_hp
			var side := -1.0 if slot % 2 == 0 else 1.0
			global_position = p.global_position + Vector2(-1250.0, side * 450.0).rotated(p.heading)
			heading = p.heading
			velocity = p.velocity
			_fly_w = 1.0
			Events.radio.emit("Ведомый", "Иду к вам, займу место в строю!", false)
		return
	_sortie(p, delta)
	_fly(p, delta)
	_gun(p, delta)
	match type:
		"swift":
			_swift(p, delta)
		"rook":
			_rook(p, delta)
		"weasel":
			_weasel(p, delta)
	_salvos(delta)
	if p.syn.has("warm"):
		_warm(p, delta)
	queue_redraw()


func _gun(p: Player, delta: float) -> void:
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	var t := _sortie_tgt if _sortie_t > 0.0 and is_instance_valid(_sortie_tgt) else _target(650.0)
	if t and absf(Vector2.from_angle(heading).angle_to(t.global_position - global_position)) < deg_to_rad(40.0):
		_fire_cd = 1.0 / (Tuning.g("fire_rate") * 0.667)   # S6-02: темп пушки 10 → 9, у ведомых прежние 6 в секунду
		var dir := (t.global_position - global_position).normalized()
		Main.I.projectiles.spawn_player_bullet(global_position + dir * 14.0, dir * Tuning.g("bullet_speed") + velocity,
			Tuning.g("bullet_damage") * 0.327 * dmg_k() * p.mods["gun_dmg"], 0.5, false, src())


func _missile(p: Player, t: Enemy, dmg: float, opts := {}) -> void:
	var side := -1.0 if slot % 2 == 0 else 1.0
	Main.I.projectiles.spawn_player_missile(global_position, velocity + Vector2.from_angle(heading + side * 0.2) * 150.0, t,
		dmg * p.missile_k(), src(), opts)


## «Стриж»: ракеты В-В по воздуху; ур. 3 — сбивает ракеты рядом с ведущим
## 3.5 (правка 23): ведомый летит как самолёт. Рядом со своим местом — держит строй (как раньше),
## вдали — летит носом вперёд с ограниченным разворотом и меняет скорость в пределах 75–145% скорости
## ведущего: отставший догоняет, а проскочивший вперёд не «тормозит в воздухе», а уходит в разворот
## и заходит на место сзади.
const WING_TURN := 160.0   # °/с
var _fly_w := 0.0          # 0 — держит строй, 1 — летит сам (плавный переход)
## S9-06 (Kanta: на резком вираже ведомый замирает и втыкается носом в ведущего): строй поворачивается
## вслед за ведущим не мгновенно, а FORM_TURN °/с — ведомый проходит вираж по своей, более широкой дуге;
## путь к месту в строю огибает ведущего; нос смотрит туда, куда ведомый летит
const FORM_TURN := 75.0
var _form_h := NAN


func _fly(p: Player, delta: float) -> void:
	if _sortie_t > 0.0 and is_instance_valid(_sortie_tgt):
		_attack_run(p, delta)
		_keep_clear(p, delta)
		return
	_form_h = p.heading if is_nan(_form_h) else rotate_toward(_form_h, p.heading, deg_to_rad(FORM_TURN) * delta)
	var target := p.global_position + _slot_offset(p)
	# путь к месту проходит сквозь ведущего — заходим в обход, с внешней стороны
	var seg := target - global_position
	var t_c := clampf((p.global_position - global_position).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
	var near := global_position + seg * t_c
	var gap := clear_r(p) * 1.7
	var nd := near.distance_to(p.global_position)
	if nd < gap and t_c > 0.05 and t_c < 0.95:
		var out := (near - p.global_position) / nd if nd > 1.0 else Vector2.from_angle(p.heading + (PI / 2.0 if slot % 2 else -PI / 2.0))
		target += out * (gap - nd) * 1.5
	var to := target - global_position
	var dist := to.length()
	var pv := p.velocity
	var ps := maxf(pv.length(), 1.0)
	var fwd := Vector2.from_angle(p.heading)
	# держим строй, пока близко; летим сами, если отнесло дальше 140 (с запасом, чтобы не дёргалось)
	if dist > 140.0:
		_fly_w = minf(1.0, _fly_w + delta * 2.0)
	elif dist < 60.0:
		_fly_w = maxf(0.0, _fly_w - delta * 2.0)
	var station := pv + to * 3.0
	# точка захода — место в строю с упреждением по движению ведущего
	var aim := to + pv * clampf(dist / ps, 0.2, 1.2)
	var face := p.heading if velocity.length() < 40.0 else velocity.angle()
	heading = rotate_toward(heading, aim.angle() if _fly_w > 0.5 else face, deg_to_rad(WING_TURN) * delta)
	var along := to.dot(fwd)
	var spd := ps * clampf(1.0 + along / 350.0, 0.75, 1.45 if dist < 500.0 else 1.8)
	var flying := Vector2.from_angle(heading) * spd
	velocity = velocity.lerp(station.lerp(flying, _fly_w), 1.0 - exp(-delta * 4.0))
	position += velocity * delta
	_keep_clear(p, delta)


## Не влезать в самолёт ведущего (на подлёте и при «Сомкнуть строй»): мягко отжимает в сторону своего места
func _keep_clear(p: Player, delta: float) -> void:
	var rel := global_position - p.global_position
	var r := clear_r(p)
	var l := rel.length()
	if l >= r:
		return
	var side := -1.0 if slot % 2 == 0 else 1.0
	var away := rel / l if l > 1.0 else Vector2.from_angle(p.heading + side * PI / 2.0)
	position += away * (r - l) * minf(1.0, delta * 10.0)
	velocity -= away * minf(0.0, velocity.dot(away) - p.velocity.dot(away))


func _swift(p: Player, delta: float) -> void:
	_aam_cd -= delta
	if _aam_cd <= 0.0:
		var wolf := false
		var tt := _target(900.0)
		if tt != null:
			_aam_cd = (5.0 if lvl >= 2 else 7.0) * (0.5 if wolf else 1.0) * randf_range(0.9, 1.1)
			for i in 2:
				_missile(p, tt, 35.0 * dmg_k() * (1.5 if wolf else 1.0), {"splash": 70.0} if lvl >= 3 else {})
			Main.I.sfx.play("aam_launch", -20.0, 1.5)
		else:
			_aam_cd = 0.5
	if lvl >= 3:
		_guard_cd -= delta
		if _guard_cd <= 0.0:
			_guard_cd = 0.2
			if Main.I.projectiles.intercept_missile(p.global_position, 200.0):
				_guard_cd = 6.0
				Main.I.stats_add_counter("intercepted_wingmen", 1)


## «Грачонок»: НАР по наземным (или ближайшим), ур. 3 — кассета над ПВО
func _rook(p: Player, delta: float) -> void:
	_special_cd -= delta
	if _special_cd <= 0.0:
		var t := _target(700.0)
		if t == null:
			_special_cd = 0.5
			return
		_special_cd = 5.0 * randf_range(0.9, 1.1)
		var dir := (t.global_position - global_position).normalized()
		for i in 6:
			var d := dir.rotated(deg_to_rad(randf_range(-5.0, 5.0)))
			Main.I.projectiles.spawn_rocket(global_position, velocity + d * randf_range(820.0, 960.0), 12.0 * dmg_k() * p.missile_k(), 50.0, i * 0.05, {"src": src()})
		Main.I.sfx.play("rocket_launch", -20.0, 1.8)
		if lvl >= 3 and t.is_ground and global_position.distance_to(t.global_position) < 320.0:
			for j in 4:
				Main.I.projectiles.spawn_bomb(global_position, 0.45 + 0.05 * j, 30.0 * dmg_k(), 90.0, src(),
					t.global_position + Vector2.from_angle(j * TAU / 4.0) * 60.0)


## «Ласка»: противорадарная ракета; помехи — в Projectiles (Player.jam_chance); ур. 3 — ЭМИ по ПВО
func _weasel(p: Player, delta: float) -> void:
	_special_cd -= delta
	if _special_cd <= 0.0:
		var t := _target(1000.0)
		if t == null:
			_special_cd = 0.5
		else:
			_special_cd = 8.0
			_missile(p, t, 150.0 * dmg_k() * (2.0 if t.is_ground else 1.0))
			Main.I.sfx.play("aam_launch", -18.0, 0.9)
	if lvl >= 3:
		_emp_cd -= delta
		if _emp_cd <= 0.0:
			_emp_cd = 15.0
			var n := 0
			for e in get_tree().get_nodes_in_group("enemies"):
				var en := e as Enemy
				if en != null and en.is_ground and en.global_position.distance_to(global_position) < 400.0:
					en.silence = 3.0
					n += 1
			if n > 0:
				Main.I.fx.ring(global_position, 400.0, Color(0.6, 0.8, 1.0))


func _salvos(delta: float) -> void:
	if _salvo_left <= 0:
		return
	_salvo_t -= delta
	if _salvo_t > 0.0:
		return
	_salvo_t = _salvo_iv
	var t := _target(900.0)
	if t == null and type != "swift":   # истребители — только по воздуху (правка 3.5-s4)
		t = Weapons.pick_target(global_position, 900.0, "nearest")
	_salvo_left -= 1
	if t == null:
		return
	_missile(Main.I.player, t, _salvo_dmg * dmg_k())


var _run_t := 0.0
var _dropped := false


# ---------- Правка 3.5-s4: цель по приоритету звена и самостоятельные заходы ----------

var _sortie_t := 0.0          # > 0 — ведомый вышел из строя и атакует сам
var _sortie_cd := 4.0
var _sortie_tgt: Enemy = null
var _break := 0.0             # направление отворота после атаки (−1 / +1)


## Цель с учётом настройки звена (Settings.wing_prio). «Стриж» — истребитель: только воздушные цели.
func _target(rng: float) -> Enemy:
	var air := type == "swift"
	var natural := "nearest" if air else "ground"
	match Settings.wing_prio:
		1:
			var p := Main.I.player
			var t := Weapons.pick_target(p.global_position, rng * 0.8, "nearest", [], air)
			if t != null and t.global_position.distance_to(global_position) < rng * 1.3:
				return t
			return Weapons.pick_target(global_position, rng, natural, [], air)
		2:
			return Weapons.pick_target(global_position, rng, "big", [], air)
		3:
			return Weapons.pick_target(global_position, rng, natural if air else "ground", [], air)
	return Weapons.pick_target(global_position, rng, natural, [], air)


## Заход: раз в 3–6 с ведомый отрывается от строя к цели (до 3,5 с), стреляет и отворачивает обратно.
## Строй держит при «Сомкнуть строй» и когда ведущий далеко (поводок 700 пикс.).
func _sortie(p: Player, delta: float) -> void:
	_sortie_cd -= delta
	var leash := global_position.distance_to(p.global_position)
	if _sortie_t > 0.0:
		_sortie_t -= delta
		if not is_instance_valid(_sortie_tgt) or _sortie_tgt.hp <= 0.0 or leash > 700.0 or p.ranks_t > 0.0:
			_sortie_t = 0.0
		if _sortie_t <= 0.0:
			_sortie_tgt = null
			_sortie_cd = randf_range(3.0, 6.0)
		return
	if _sortie_cd > 0.0 or p.ranks_t > 0.0 or leash > 300.0:
		return
	var t := _target(620.0)
	if t == null or t.is_boss and type != "swift" and not t.is_ground:
		_sortie_cd = 1.0
		return
	_sortie_tgt = t
	_sortie_t = randf_range(2.5, 3.5)
	_break = -1.0 if slot % 2 == 0 else 1.0
	_aam_cd = minf(_aam_cd, 0.4)   # заход начинается с пуска


func _attack_run(p: Player, delta: float) -> void:
	var to_t := _sortie_tgt.global_position + _sortie_tgt.move_vel * 0.4 - global_position
	var d := to_t.length()
	var aim := to_t.angle()
	if d < 170.0:
		aim += _break * 1.3   # проскочил цель — отворот, не таран
	heading = rotate_toward(heading, aim, deg_to_rad(WING_TURN * 1.25) * delta)
	var spd := maxf(p.velocity.length(), 200.0) * 1.3
	velocity = velocity.lerp(Vector2.from_angle(heading) * spd, 1.0 - exp(-delta * 3.0))
	position += velocity * delta


## «Тёплая компания»: раз в 7 с — заход вперёд и ряд из 5 бомб поперёк курса
func _warm(p: Player, delta: float) -> void:
	if _run_t > 0.0:
		_run_t -= delta
		if not _dropped and _run_t < 0.6:
			_dropped = true
			if type == "swift":
				var at := _target(900.0)
				if at != null:
					for i in 2:
						_missile(p, at, 40.0 * dmg_k())
					Main.I.sfx.play("aam_launch", -20.0, 1.4)
				return
			var fwd := Vector2.from_angle(p.heading)
			var side := Vector2(-fwd.y, fwd.x)
			for j in 5:
				var to := global_position + fwd * 160.0 + side * (float(j) / 4.0 - 0.5) * 360.0
				Main.I.projectiles.spawn_bomb(global_position, 0.45 + 0.05 * j, 45.0 * dmg_k(), 100.0, "связка: тёплая компания", to)
			Main.I.sfx.play("bomb_drop", -14.0, 1.1)
		return
	_bomb_cd -= delta
	if _bomb_cd <= 0.0:
		_bomb_cd = 7.0 + slot * 0.4
		_run_t = 1.2
		_dropped = false


## «Волчья стая»: повторить пуск ведущего — 2 ракеты в ту же цель
func mirror_launch(t: Enemy, d: float) -> void:
	for i in 2:
		Main.I.projectiles.spawn_player_missile(global_position, velocity + Vector2.from_angle(heading + (i - 0.5) * 0.8) * 160.0, t, d,
			"связка: волчья стая", {"splash": 80.0, "tint": Color(0.8, 0.6, 1.0)})


func plane_tex() -> Texture2D:
	match type:
		"rook":
			return PlaneArt.plane_tex("attacker", 1)
	return PlaneArt.plane_tex("fighter", 1)


func tint() -> Color:
	match type:
		"rook":
			return Color(0.9, 1.0, 0.85)
		"weasel":
			return Color(0.9, 0.85, 1.0)
	return Color(0.85, 0.9, 1.0)


func _draw() -> void:
	var xf := Transform2D(heading, Vector2.ZERO).scaled(Vector2(0.8, 0.8))
	var wt := plane_tex()
	if wt != null and Tuning.g("sprites") >= 1:
		if hp < max_hp:
			draw_rect(Rect2(-18, -30, 36, 4), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(-18, -30, 36 * hp / max_hp, 4), Color(0.7, 0.6, 1.0))
		if temp:
			draw_arc(Vector2.ZERO, 26.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(life / 15.0, 0.0, 1.0), 24, Color(0.7, 1.0, 0.6, 0.5), 2.0)
		if Render3D.enabled:
			return
		var kk := Tuning.g("plane_len") * 0.85 / float(PlaneArt.plane_tex("fighter", 1).get_width())
		draw_set_transform(Vector2(14, 22), heading, Vector2(kk, kk))
		draw_texture(wt, -wt.get_size() / 2.0, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, heading, Vector2(kk, kk))
		draw_texture(wt, -wt.get_size() / 2.0, Color(4, 4, 4, 1) if _flash > 0.0 else tint())
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_colored_polygon(xf * PackedVector2Array([Vector2(20, 0), Vector2(-14, 15), Vector2(-8, 0), Vector2(-14, -15)]), Color(0.75, 0.7, 1.0))
