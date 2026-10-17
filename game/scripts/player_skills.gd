class_name PlayerSkills
extends RefCounted
## Навыки и манёвры: бочка, нырок, форсаж, навыки 3-го и 2-го слота, ловушки, связки.
## Вынесено из player.gd без изменения поведения: состояние (переменные) живёт в Player, здесь только код.

var pl: Player


func _init(p: Player) -> void:
	pl = p


func _afterburner_pass() -> void:
	var r := pl.radius * 1.9
	for n in pl.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or e.is_boss or e.is_ground:
			continue
		var id := e.get_instance_id()
		if pl._pass_hit.has(id):
			continue
		if pl.global_position.distance_to(e.global_position) < r + e.radius:
			pl._pass_hit[id] = true
			Main.I.fx.ring(e.global_position, 40.0, Color(1.0, 0.8, 0.4))
			e.take_hit(pl.pass_damage(), "проход на форсаже")
			Main.I.sfx.play("pass_hit", -8.0)
			Main.I.add_shake(3.0)


func _turn_side() -> float:
	if absf(pl.bank) > 0.1:
		return signf(pl.bank)
	var t := Input.get_axis("move_left", "move_right")
	if absf(t) > 0.1:
		return signf(t)
	return 1.0


func _handle_skills() -> void:
	if Input.is_action_just_pressed("roll") and pl.roll_cd <= 0.0 and pl.roll_t <= 0.0 and not pl.has_roll():
		_flare_salvo()
	elif Input.is_action_just_pressed("roll") and pl.roll_cd <= 0.0 and pl.roll_t <= 0.0:
		pl.roll_t = pl.roll_time()
		pl.roll_inv = Tuning.g("roll_time") + pl.mods["roll_time"]
		# 3.4: перезарядка не короче бочки + 1 с — без непрерывной неуязвимости при прокачке
		pl.roll_cd = maxf(maxf(2.0, pl.roll_t + 1.0), (Tuning.g("roll_cd") + pl.mods["roll_cd"]) * float(pl.cls.get("roll_cd_k", 1.0)) * float(pl.mods["man_cd"]))
		Main.I.tele.add("roll_uses")
		pl.roll_dir = _turn_side()
		if pl.syn.has("mirror"):
			_mirror_fan()
		if pl.patch("maneuver") >= 2:
			pl.man_buff_t = 2.0
		Main.I.sfx.play("roll", -10.0)
	if Input.is_action_just_pressed("dive") and pl.dive_cd <= 0.0 and pl.dive_t <= 0.0:
		pl.dive_t = Tuning.g("dive_time")
		pl.dive_cd = maxf(pl.dive_t + 1.0, Tuning.g("dive_cd") * float(pl.mods["man_cd"]))
		Main.I.tele.add("dive_uses")
		Main.I.sfx.play("dive", -12.0, 0.6)
	if Input.is_action_just_pressed("afterburner") and pl.ab_cd <= 0.0 and Fuel.can_afterburn(): # 3.5: без топлива форсажа нет
		pl.ab_t = Tuning.g("afterburner_time") + pl.mods["ab_time"]
		pl._pass_hit.clear()
		pl.ab_cd = maxf(4.0, (Tuning.g("afterburner_cd") + pl.mods["ab_cd"]) * float(pl.mods["man_cd"]))
		if pl.patch("maneuver") >= 2:
			pl.man_buff_t = 2.0
		Main.I.sfx.play("afterburner", -8.0)
	if Input.is_action_just_pressed("sharp_turn") and pl.s3_cd <= 0.0 and pl.s3_active() <= 0.0:
		_activate_skill3(pl.skill3, 0)
	if pl.skill_b != "" and Input.is_action_just_pressed("skill_2") and pl.sb_cd <= 0.0 and pl.s3_active(pl.skill_b) <= 0.0:
		_activate_skill3(pl.skill_b, 1)
	if Input.is_action_just_pressed("toggle_fire_mode"):
		pl.manual_mode = not pl.manual_mode
		pl.manual_bonus = 0.0


func _activate_skill3(id := "", slot := 0) -> void:
	if id == "":
		id = pl.skill3
	var d: Dictionary = PlaneClasses.SKILL3[id]
	var lvl := pl.lvl_of(id)
	if slot == 0:
		pl.s3_cd = pl.cd_of(id)
	else:
		pl.sb_cd = pl.cd_of(id)
	Main.I.stats_add_counter("skill3_uses" if slot == 0 else "skill2_uses", 1)
	match id:
		"combat_turn":
			pl.s3_t = float(d["time"])
			pl.turn_t = pl.s3_t
			if int(Tuning.g("scheme")) == 2:
				pl._turn_target = (Render3D.I.mouse_world(pl.get_global_mouse_position()) - pl.global_position).angle()
			else:
				pl._turn_target = wrapf(pl.heading + PI, -PI, PI)
			pl.combat_t = pl.s3_t + 3.0 + (1.0 if lvl >= 1 else 0.0)
			var n := Main.I.projectiles.break_locks(pl.global_position, 1100.0)
			Main.I.stats_add_counter("locks_broken", n)
			if lvl >= 3:
				_intercept_all(250.0)
			if pl.syn.has("s_wheel"): # «Чёртово колесо»: ракеты В-В сразу готовы
				for g in pl.groups:
					if (g as Hardpoint).weapon == "aam":
						(g as Hardpoint).cd = 0.0
			Main.I.fx.ring(pl.global_position, 90.0, Color(0.6, 0.9, 1.0))
			Main.I.sfx.play("combat_turn", -6.0, 0.7)
		"yolka":
			_fire_yolka(lvl)
		"sonic":
			pl.ram_t = float(d["time"])
			pl.s3_t = pl.ram_t
			pl._ram_prev = pl.ram_t
			if lvl >= 2:
				_sonic_wave()
			Main.I.sfx.play("afterburner", -4.0, 1.4)
		"armor_shield":
			pl.s3_t = float(d["time"]) + (1.0 if lvl >= 1 else 0.0)
			pl.shield_t = pl.s3_t
			pl._shield_prev = pl.shield_t
			pl._shield_absorbed = 0.0
			pl._shield_tick = 0.0
			Main.I.sfx.play("shield", -8.0, 0.5)
		"assault":
			pl.assault_t = float(d["time"]) + (1.0 if lvl >= 1 else 0.0)
			pl.s3_t = pl.assault_t
			pl._assault_ext = 0.0
			for g in pl.groups:
				if not (g as Hardpoint).builtin:
					(g as Hardpoint).cd = minf((g as Hardpoint).cd, 0.2)
			Main.I.sfx.play("combat_turn", -6.0, 0.9)
		"rooks":
			var n2 := 3 if lvl >= 2 else 2
			var life := 15.0 if lvl >= 1 else 12.0
			for i in n2:
				var keep := pl.syn.has("s_nest") and not pl._nest_done and i == 0 and pl.permanent_wingmen() < Cards.WING_MAX
				if keep:
					pl._nest_done = true # «Гнездо»: один остаётся насовсем
				pl.add_wingman("rook", 1.0, not keep, life)
			Main.I.radio("Грачата", "Звено на подходе, работаем по земле!")
		"umbrella":
			pl.umbrella_t = float(d["time"]) + (1.0 if lvl >= 1 else 0.0)
			pl.s3_t = pl.umbrella_t
			if pl.syn.has("s_shelter"):
				for w in pl.wingmen:
					(w as Wingman).salvo(2, 35.0, 0.5)
			Main.I.fx.ring(pl.global_position, 300.0, Color(0.4, 0.95, 0.9))
			Main.I.sfx.play("shield", -8.0, 0.9)
		"carpet":
			pl.carpet_t = float(d["time"])
			pl._carpet_left = 14 if lvl >= 1 else 10
			pl._carpet_tick = 0.0
			pl._carpet_i = 0
			pl._carpet_dir = 1.0
			if pl.syn.has("s_double"):
				pl._carpet2_delay = 1.0
			if lvl >= 3:
				pl._speed_buff_t = 3.0
			Main.I.sfx.play("bomb_drop", -8.0, 0.6)
		"close_ranks":
			pl.ranks_t = 8.0 if lvl >= 3 else float(d["time"])
			pl.s3_t = pl.ranks_t
			for w in pl.wingmen:
				var wm: Wingman = w
				wm.salvo(4 if lvl >= 1 else 3, 40.0, pl.ranks_t * 0.6)
				if lvl >= 2:
					wm.repair(0.5)
			Main.I.radio("Звено", "Смыкаем строй!")


## «Ёлочка»: мини-ракеты по разным целям
func _fire_yolka(lvl: int) -> void:
	var n := 14 if lvl >= 1 else 10
	var dmg := (45.0 if lvl >= 2 else 30.0) * pl.missile_k()
	var targets: Array = []
	var skip: Array = []
	for i in n:
		var t := Weapons.pick_target(pl.global_position, 700.0, "nearest", skip)
		if t == null:
			break
		targets.append(t)
		skip.append(t)
	var opts := {"splash": 40.0, "bounce": 1 if lvl >= 3 else 0, "fire": pl.syn.has("s_newyear")}
	for i in n:
		var t: Enemy = targets[i % targets.size()] if not targets.is_empty() else null
		var a := pl.heading + (float(i) / maxf(n - 1, 1) - 0.5) * 2.6
		Main.I.projectiles.spawn_player_missile(pl.global_position, pl.velocity * 0.5 + Vector2.from_angle(a) * 300.0, t, dmg, "ёлочка", opts)
	Main.I.sfx.play("aam_launch", -8.0, 1.6)


func _sonic_wave() -> void:
	var r := 320.0 if pl.lvl_of("sonic") >= 1 else 260.0
	Main.I.projectiles.aoe(pl.global_position, r, 60.0, "звуковой удар", false)
	_knockback(r, 90.0)
	if pl.syn.has("s_clap"):
		_intercept_all(r)
	Main.I.fx.ring(pl.global_position, r, Color(0.75, 0.9, 1.0))
	Main.I.add_shake(4.0)


func _knockback(r: float, dist: float) -> void:
	for n in pl.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or e.is_boss or e.is_ground:
			continue
		var to := e.global_position - pl.global_position
		if to.length() < r + e.radius:
			e.position += to.normalized() * dist


func _intercept_all(r: float) -> void:
	var n := 0
	while n < 20 and Main.I.projectiles.intercept_missile(pl.global_position, r):
		n += 1
	n += Main.I.projectiles.intercept_bullets(pl.global_position, r)
	Main.I.stats_add_counter("intercepted_skill", n)


## Таймеры навыков: волна в конце «Звукового удара», импульсы и волна «Бронещита», «Двойной узор», «Парад»
func _skill_tick(delta: float) -> void:
	if pl.has_skill("sonic") and pl._ram_prev > 0.0 and pl.ram_t <= 0.0:
		_sonic_wave()
	pl._ram_prev = pl.ram_t
	if pl.has_skill("armor_shield"):
		if pl.shield_t > 0.0 and pl.lvl_of("armor_shield") >= 2:
			pl._shield_tick -= delta
			if pl._shield_tick <= 0.0:
				pl._shield_tick = 0.5
				for n in pl.get_tree().get_nodes_in_group("enemies"):
					var e := n as Enemy
					if e != null and e.hp > 0.0 and not e.is_ground and e.global_position.distance_to(pl.global_position) < pl.radius + e.radius + 60.0:
						e.take_hit(60.0, "бронещит")
						if not e.is_boss:
							e.position += (e.global_position - pl.global_position).normalized() * 50.0
		if pl._shield_prev > 0.0 and pl.shield_t <= 0.0 and pl.lvl_of("armor_shield") >= 3 and pl._shield_absorbed > 1.0:
			Main.I.projectiles.aoe(pl.global_position, 220.0, pl._shield_absorbed * 0.3, "бронещит")
			Main.I.fx.ring(pl.global_position, 220.0, Color(0.5, 1.0, 0.6))
		pl._shield_prev = pl.shield_t
	if pl._carpet2_delay > 0.0:
		pl._carpet2_delay -= delta
		if pl._carpet2_delay <= 0.0:
			pl._carpet_left = 14 if pl.lvl_of("carpet") >= 1 else 10
			pl._carpet_i = 0
			pl._carpet_tick = 0.0
			pl._carpet_dir = -1.0
	if pl.syn.has("s_parade"):
		pl._parade_t -= delta
		if pl._parade_t <= 0.0:
			pl._parade_t = 20.0
			for w in pl.wingmen:
				(w as Wingman).salvo(3, 40.0, 1.5)


func _carpet(delta: float) -> void:
	if pl._carpet_left <= 0:
		return
	pl._carpet_tick -= delta
	if pl._carpet_tick > 0.0:
		return
	pl._carpet_tick = 1.0 / 12.0
	pl._carpet_left -= 1
	pl._carpet_i += 1
	var lvl := pl.lvl_of("carpet")
	# спираль вокруг самолёта: радиус растёт 160 → 360, угол шаг 72° («Двойной узор» — в обратную сторону)
	var ang := pl.heading + pl._carpet_i * deg_to_rad(72.0) * pl._carpet_dir
	var rad := 160.0 + 20.0 * pl._carpet_i
	var to := pl.global_position + pl.velocity * 0.5 + Vector2.from_angle(ang) * rad
	var dmg := 55.0 * (1.4 if lvl >= 2 else 1.0)
	var r := 120.0 * (1.2 if lvl >= 2 else 1.0)
	Main.I.projectiles.spawn_bomb(pl.global_position, 0.5, dmg, r, "огненный ковёр", to)


## «Каток»: кольцо НАР во все стороны
func roller_ring(n: int) -> void:
	for i in n:
		var d := Vector2.from_angle(TAU * i / n + randf() * 0.2)
		Main.I.projectiles.spawn_rocket(pl.global_position + d * 20.0, pl.velocity * 0.5 + d * 800.0, 18.0, 60.0, 0.0, {"src": "связка: каток", "life": 0.45})
	Main.I.sfx.play("rocket_launch", -8.0, 1.4)


func _flare_salvo() -> void:
	pl.roll_cd = maxf(3.0, (Tuning.g("roll_cd") + pl.mods["roll_cd"]) * float(pl.cls.get("roll_cd_k", 1.0)) * float(pl.mods["man_cd"]))
	pl.salvo_t = 0.6
	Main.I.tele.add("roll_uses")
	Main.I.tele.add("flare_salvos")
	Main.I.fx.flare_burst(pl.global_position, pl.heading, 14, pl.velocity, 1.6)
	var n := 0
	for i in 12:
		if Main.I.projectiles.intercept_missile_at(pl.global_position, Player.SALVO_R, true) == null:
			break
		n += 1
	n += Main.I.projectiles.break_locks(pl.global_position, Player.SALVO_R * 2.2)
	Main.I.stats_add_counter("intercepted", n)
	if pl.syn.has("mirror"):
		_mirror_fan()
	if pl.patch("maneuver") >= 2:
		pl.man_buff_t = 2.0
	Main.I.sfx.play("flare", -6.0, 1.4)


func _mirror_fan() -> void:
	Main.I.fx.flare_burst(pl.global_position, pl.heading, 6, pl.velocity)
	for i in 6:
		if Main.I.projectiles.intercept_missile_at(pl.global_position, 300.0, true) == null:
			break


## «Реактивный след»: заряды за самолётом на бочке и форсаже
func _jetwash() -> void:
	if not pl.syn.has("jetwash") or (pl.roll_t <= 0.0 and pl.ab_t <= 0.0):
		pl._jet_last = Vector2.INF
		return
	if pl._jet_last == Vector2.INF or pl._jet_last.distance_to(pl.global_position) >= 50.0:
		pl._jet_last = pl.global_position
		var k := 1.0 + 0.1 * (int(pl.taken.get("roll", 0)) + int(pl.taken.get("afterburner", 0)))
		Main.I.projectiles.spawn_bomb(pl.global_position, 0.4, 30.0 * k, 70.0, "связка: реактивный след", pl.global_position)
