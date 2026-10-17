class_name PlayerGuns
extends RefCounted
## Курсовое оружие: урон, темп, стрельба, упреждение, выбор цели.
## Вынесено из player.gd без изменения поведения: состояние (переменные) живёт в Player, здесь только код.

var pl: Player


func _init(p: Player) -> void:
	pl = p


func gun_range() -> float:
	return Tuning.g("bullet_speed") * Player.GUN_LIFE


func gun_damage() -> float:
	var d := Tuning.g("bullet_damage") * float(pl.cls["gun_dmg"]) * float(pl.mods["gun_dmg"])
	# 2.4: курсовое растёт вместе с пилотом (+3% за уровень, до +60%)
	d *= minf(1.0 + 0.03 * (Main.I.level - 1), 1.4) # 2.8: потолок +40% (было +60%)
	if pl.manual_mode:
		d *= 1.0 + pl.manual_bonus
	if pl.combat_t > 0.0:
		d *= 1.3
	if pl.on_tail():
		d *= 1.5
	if pl.gun_evo:
		d *= 0.85 * (1.0 + 0.08 * pl.gun_evo_plus) # «Дятел»: обычные снаряды −15%
	return d


func gun_rate() -> float:
	var r := Tuning.g("fire_rate") * float(pl.cls["gun_rate"]) * float(pl.mods["gun_rate"])
	if pl.combat_t > 0.0:
		r *= 2.0
	return r


func _shoot(delta: float) -> void:
	pl._fire_cd -= delta
	var fwd := Vector2.from_angle(pl.heading)
	var range_px := gun_range()
	var want := false
	var aim := fwd
	var lead := false
	if pl.manual_mode:
		want = Input.is_action_pressed("fire")
		var t := _find_target(deg_to_rad(Tuning.g("assist_cone")), range_px)
		if t:
			aim = _lead_dir(t)
			lead = true
	else:
		var t2 := _find_target(deg_to_rad(Tuning.g("auto_cone")), range_px)
		if pl.on_tail():
			t2 = pl.tail_target
		# боевой режим: пушка держится на цели разворота, пока она в дальности и не дальше 40° от носа
		elif pl.combat_t > 0.0 and pl.lock_ok():
			var tl := pl.turn_lock.global_position - pl.global_position
			if tl.length() < range_px and absf(wrapf(tl.angle() - pl.heading, -PI, PI)) < deg_to_rad(40.0):
				t2 = pl.turn_lock
		want = t2 != null
		if t2 and (pl.combat_t > 0.0 or pl.on_tail()):
			aim = _lead_dir(t2)
			lead = true
	if not want:
		pl._fire_cd = maxf(pl._fire_cd, 0.0) # остаток таймера не копится, пока не стреляем
		return
	# 3.4: темп не зависит от FPS — остаток таймера переносится, за кадр до 4 выстрелов
	var rate := gun_rate()
	Main.I.tele.maxv("gun_rate_max", rate)
	var n := 0
	while pl._fire_cd <= 0.0 and n < 4:
		pl._fire_cd += 1.0 / rate
		n += 1
		_fire_one(fwd, aim, lead, maxf(0.0, -(pl._fire_cd - 1.0 / rate)))
	if n > 1:
		Main.I.tele.add("gun_multi_frames")
	pl._fire_cd = maxf(pl._fire_cd, -1.0 / rate)


func _fire_one(fwd: Vector2, aim: Vector2, lead: bool, age := 0.0) -> void:
	pl._gun_side = -pl._gun_side
	var muzzle := pl.global_position + fwd * 16.0 * pl.size + Vector2.from_angle(pl.heading + PI / 2.0) * 7.0 * pl.size * pl._gun_side
	Main.I.shots += 1
	pl._gun_n += 1
	var src := "курсовое (ручн.)" if pl.manual_mode else "курсовое (авто)"
	var every := 3 if (pl.manual_mode and pl.manual_bonus >= 0.4) else 4
	if pl.gun_evo and pl._gun_n % every == 0:
		# «Дятел»: пробивающий снаряд — всё на линии 900 пикс., урон ×2,5
		var spd := Tuning.g("bullet_speed") * 1.3
		Main.I.projectiles.spawn_player_bullet(muzzle, aim * spd + pl.velocity, gun_damage() / 0.85 * 2.5, 900.0 / spd, pl.manual_mode, src, 99)
	else:
		Main.I.projectiles.spawn_player_bullet(muzzle, aim * Tuning.g("bullet_speed") + pl.velocity, gun_damage(), Player.GUN_LIFE, pl.manual_mode, src)
	var bl: Dictionary = Main.I.projectiles.bullets[-1]
	if age > 0.0: # выстрел «опоздал» на часть кадра — первый шаг пули длиннее на это время
		bl["lag"] = age
	if lead:
		bl["lead"] = true
		Main.I.tele.add("shots_lead")
	if pl._gun_side > 0.0:
		Main.I.sfx.play("gun_fire", -15.0)


## Направление с упреждением: куда стрелять, чтобы снаряд встретил цель
## 3.4: учитывает скорость самолёта, которую наследует пуля, и решает время встречи (ближайшее t > 0 в пределах жизни пули)
func _lead_dir(t: Enemy) -> Vector2:
	var s := Tuning.g("bullet_speed")
	var r := t.global_position - pl.global_position
	var w := t.move_vel - pl.velocity # движение цели относительно точки вылета пули
	# |r + w·τ| = s·τ  →  (w·w − s²)τ² + 2(r·w)τ + r·r = 0
	var a := w.dot(w) - s * s
	var b := 2.0 * r.dot(w)
	var c := r.dot(r)
	var tau := -1.0
	if absf(a) < 0.001:
		if absf(b) > 0.001:
			tau = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			for x in [minf(t1, t2), maxf(t1, t2)]:
				if x > 0.0:
					tau = x
					break
	if tau <= 0.0 or tau > Player.GUN_LIFE:
		Main.I.tele.add("lead_nosol")
		return r.normalized() # встречи нет — стреляем прямо по цели
	return ((r + w * tau) / (s * tau)).normalized()


func _find_target(cone: float, max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_ang := cone
	for n in pl.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var to := e.global_position - pl.global_position
		var d := to.length()
		if d > max_dist or d < 1.0:
			continue
		var ang := absf(wrapf(to.angle() - pl.heading, -PI, PI)) - atan2(e.radius, d)
		if ang <= best_ang:
			best_ang = ang
			best = e
	return best
