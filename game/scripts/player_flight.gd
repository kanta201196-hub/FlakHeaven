class_name PlayerFlight
extends RefCounted
## Полёт: таймеры, РУД, руление, «на хвосте», движение.
## Вынесено из player.gd без изменения поведения: состояние (переменные) живёт в Player, здесь только код.

var pl: Player


func _init(p: Player) -> void:
	pl = p


func _tick_timers(delta: float) -> void:
	pl.roll_t = maxf(0.0, pl.roll_t - delta)
	pl.roll_inv = maxf(0.0, pl.roll_inv - delta)
	pl.salvo_t = maxf(0.0, pl.salvo_t - delta)
	pl.skills.salvo_waves()
	pl.dive_t = maxf(0.0, pl.dive_t - delta)
	pl.dive_cd = maxf(0.0, pl.dive_cd - delta)
	pl.roll_cd = maxf(0.0, pl.roll_cd - delta)
	pl.ab_t = maxf(0.0, pl.ab_t - delta)
	pl.ab_cd = maxf(0.0, pl.ab_cd - delta)
	pl.s3_t = maxf(0.0, pl.s3_t - delta)
	pl.sb_cd = maxf(0.0, pl.sb_cd - delta)
	pl.turn_t = maxf(0.0, pl.turn_t - delta)
	pl.carpet_t = maxf(0.0, pl.carpet_t - delta)
	pl.s3_cd = maxf(0.0, pl.s3_cd - delta)
	pl.combat_t = maxf(0.0, pl.combat_t - delta)
	pl.shield_t = maxf(0.0, pl.shield_t - delta)
	pl.ram_t = maxf(0.0, pl.ram_t - delta)
	pl.assault_t = maxf(0.0, pl.assault_t - delta)
	pl.umbrella_t = maxf(0.0, pl.umbrella_t - delta)
	pl.ranks_t = maxf(0.0, pl.ranks_t - delta)
	pl.man_buff_t = maxf(0.0, pl.man_buff_t - delta)
	pl.roller_t = maxf(0.0, pl.roller_t - delta)
	pl._roller_cd = maxf(0.0, pl._roller_cd - delta)
	pl._armor2_cd = maxf(0.0, pl._armor2_cd - delta)
	pl._speed_buff_t = maxf(0.0, pl._speed_buff_t - delta)
	pl.invuln = maxf(0.0, pl.invuln - delta)
	pl._blink += delta
	pl._near_miss_cd = maxf(0.0, pl._near_miss_cd - delta)
	# «Обороты» ручного огня: без попаданий шкала падает
	pl._since_hit += delta
	if pl.manual_mode and pl._since_hit > Tuning.g("manual_grace"):
		pl.manual_bonus = maxf(0.0, pl.manual_bonus - Tuning.g("manual_decay") * delta)


func _steer(delta: float) -> void:
	var tr := pl.turn_rate()
	var prev := pl.heading
	# 3.5 (правка 13): угловая скорость набирается и гасится с ускорением класса — Оса вертится сразу,
	# Кит раскачивается и тормозит разворот заранее (без перелёта мимо цели).
	# Тест 3.5-s7: ускорение — от скорости разворота без предела радиуса, сам предел — в tr
	var accel := pl.turn_rate_free() * float(pl.cls.get("turn_accel", 6.0))
	var want := 0.0
	if pl.turn_t > 0.0:
		# Боевой разворот: рывок носом к цели в 4 раза быстрее обычного; цель движется — догоняем её
		if pl.lock_ok():
			pl._turn_target = (pl.turn_lock.global_position - pl.global_position).angle()
		pl.heading = rotate_toward(pl.heading, pl._turn_target, tr * 4.0 * delta + PI / float(pl.s3_def()["time"]) * delta)
		pl._turn_vel = 0.0
	else:
		if int(Tuning.g("scheme")) == 2:
			var to_mouse := Render3D.I.mouse_world(pl.get_global_mouse_position()) - pl.global_position
			if to_mouse.length() > 30.0:
				want = _turn_to(to_mouse.angle(), tr, accel, delta)
		elif int(Tuning.g("scheme")) == 0:
			# 3.4: мёртвая зона одна — у действий (0,25); get_vector уже пересчитал длину после неё
			var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if dir != Vector2.ZERO:
				want = _turn_to(dir.angle(), tr, accel, delta)
		else:
			want = Input.get_axis("move_left", "move_right") * tr
		pl._turn_vel = move_toward(pl._turn_vel, want, accel * delta)
		pl.heading += pl._turn_vel * delta
	pl.heading = wrapf(pl.heading, -PI, PI)
	var ang_vel := wrapf(pl.heading - prev, -PI, PI) / maxf(delta, 0.0001)
	# тест 3.5-s7: тяжёлый самолёт входит в крен и выходит из него медленнее — видно вес
	var want_bank := clampf(ang_vel / tr, -1.0, 1.0)
	var bank_rate := AcesBalance.bank_rate(pl.bank, want_bank, Tuning.g("aces_roll_in"), Tuning.g("aces_roll_out")) if Main.aces() else float(pl.cls.get("bank_rate", 12.0))
	pl.bank = lerpf(pl.bank, want_bank, 1.0 - exp(-delta * bank_rate))


## Желаемая угловая скорость к курсу target: не больше, чем успеем погасить до него (без перелёта)
func _turn_to(target: float, tr: float, accel: float, delta: float) -> float:
	var diff := wrapf(target - pl.heading, -PI, PI)
	var v := minf(minf(tr, sqrt(2.0 * accel * absf(diff))), absf(diff) / maxf(delta, 0.0001))
	return signf(diff) * v


## 3.5 (правка 11): разгон и торможение — манёвр, а не режим. Держишь W/S — РУД уходит от крейсерской,
## отпустил — плавно возвращается; дольше throttle_hold с — возвращается сам, пока не отпустишь клавишу.
## Сброс газа (Ctrl) — так же, не дольше throttle_cut_hold с.
func _throttle(delta: float) -> void:
	pl._cut_hold = pl._cut_hold + delta if Input.is_action_pressed("throttle_cut") and not pl._cut_lock else 0.0
	if pl._cut_hold > Tuning.g("throttle_cut_hold"):
		pl._cut_lock = true
		pl._cut_hold = 0.0
	if pl._cut_lock and not Input.is_action_pressed("throttle_cut"):
		pl._cut_lock = false
	if int(Tuning.g("scheme")) == 0:
		pl.throttle = 1.0 # в схеме «по направлению» W/S — это курс
		return
	var a := Input.get_axis("move_down", "move_up")
	if absf(a) <= 0.1:
		pl._thr_lock = false
	if absf(a) > 0.1 and not pl._thr_lock:
		pl.throttle = clampf(pl.throttle + a * 1.2 * delta, Tuning.g("throttle_min"), Tuning.g("throttle_max"))
		pl._thr_hold += delta
		if pl._thr_hold > Tuning.g("throttle_hold"):
			pl._thr_lock = true
			Main.I.tele.add("throttle_locks")
	else:
		pl.throttle = move_toward(pl.throttle, 1.0, Tuning.g("throttle_return") * delta)
		if is_equal_approx(pl.throttle, 1.0):
			pl._thr_hold = 0.0


func throttle_cut_on() -> bool:
	return Input.is_action_pressed("throttle_cut") and not pl._cut_lock


## «На хвосте»: вражеский самолёт впереди в узком конусе, мы у него в задней полусфере.
## Держишься 0,3 с — курсовое +50% урона и автоогонь цепляется за него.
func _track_tail(delta: float) -> void:
	var best: Enemy = null
	var best_d := 520.0
	var fwd := Vector2.from_angle(pl.heading)
	for n in pl.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or e is Drone or e.is_ground:
			continue
		var to := e.global_position - pl.global_position
		var d := to.length()
		if d > best_d or d < 40.0:
			continue
		if absf(fwd.angle_to(to)) > deg_to_rad(32.0 if pl.has_perk("f_tail1") else 26.0):
			continue
		# мы в задней полусфере цели
		if absf(Vector2.from_angle(e.heading).angle_to(-to)) < deg_to_rad(110.0):
			continue
		best = e
		best_d = d
	if best != null and best == pl.tail_target:
		pl.tail_t += delta
	elif best != null:
		pl.tail_target = best
		pl.tail_t = 0.0
	else:
		pl.tail_t = maxf(0.0, pl.tail_t - delta * 2.0)
		if pl.tail_t <= 0.0:
			pl.tail_target = null


func _move(delta: float) -> void:
	var speed := pl.cruise_speed() * pl.throttle
	if throttle_cut_on():
		speed *= Tuning.g("throttle_cut_mult")
	if pl.ab_t > 0.0:
		speed *= Tuning.g("afterburner_mult")
	if pl.ram_t > 0.0:
		speed *= 1.8 # «Звуковой удар»
	if pl._speed_buff_t > 0.0:
		speed *= 1.3 # «Ковёр-самолёт»
	if pl.cls_id == "bomber":
		# 3.1: черта «Кита» — разбег: прямой полёт дольше 1,2 с → до +20% скорости за 1 с
		if absf(pl.bank) < 0.3:
			pl._straight_t += delta
		else:
			pl._straight_t = 0.0
		speed *= 1.0 + 0.2 * clampf(pl._straight_t - 1.2, 0.0, 1.0)
	# Тест 3.5-s7 (инерция): крутой разворот съедает скорость (тяжёлый — больше), на прямой она
	# набирается обратно с разгоном класса: «Оса» быстро, «Кит» долго. Боевой разворот — без потери.
	var bleed := Tuning.g("turn_bleed") * (Tuning.g("aces_bleed") if Main.aces() else 1.0)
	var want_e := 1.0 - bleed * float(pl.cls.get("bleed_k", 1.0)) * absf(pl.bank)
	if pl.turn_t > 0.0:
		want_e = pl._energy
	var rate := Tuning.g("speed_regain") * float(pl.cls.get("accel_k", 1.0))
	pl._energy = move_toward(pl._energy, want_e, (rate * 1.5 if want_e < pl._energy else rate) * delta)
	speed *= pl._energy
	var target := Vector2.from_angle(pl.heading) * speed
	var inertia := Tuning.g("inertia") * (Tuning.g("aces_slide") if Main.aces() else 1.0)
	var k := 1.0 - exp(-delta / maxf(inertia * float(pl.cls.get("inertia_k", 1.0)), 0.001))
	pl.velocity = pl.velocity.lerp(target, k)
	var step := pl.velocity * delta
	if pl.roll_t > 0.0:
		var side := Vector2.from_angle(pl.heading + PI / 2.0) * pl.roll_dir
		step += side * Tuning.g("roll_distance") / pl.roll_time() * delta
	pl.position += step # карта бесконечная — границ нет
