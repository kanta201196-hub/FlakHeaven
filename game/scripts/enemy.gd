class_name Enemy
extends Node2D
## Базовый враг: здоровье, вспышка при попадании, контактный урон.

var hp := 10.0
var max_hp := 10.0
## Size of the HP bar and the defence mark over the enemy, share of the hitbox: below 1 they are smaller and
## sit closer (FortArea's tower launchers and yard jeeps, Kanta 25.10: the full-size bars dwarfed the fort).
var hud_k := 1.0
var radius := 14.0
var big := false
var kill_shake := 2.0
var contact_damage := 0.0
## Multiplier of the damage this enemy's shots deal (GD-02: the first-wave ace uses 0.7)
var out_k := 1.0
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
var last_src := ""        # источник последнего попадания (мастерство «Кита»)
var born_t := -1.0       # правка 3.5-s4: когда появился (для «напряжения боя» в спавнере)
var min_life := 0.0      # правка 3.5-s4: асы — корпус не быстрее чем за min_life с (предел урона в секунду)
var _cap_budget := -1.0
var _cap_t := 0.0
var silence := 0.0
var move_vel := Vector2.ZERO   # 3.1: фактическая скорость (для пуль стрелка)
var _drift := Vector2.INF      # тест 3.5-s7: скорость, с которой заглушённый ЭМИ самолёт летит по инерции
var _prev_pos := Vector2.INF   # 3.1: ЭМИ «Ласки» — враг молчит
## 3.5: наземная цель стоит в точке рельефа (anchor). Логическая позиция — проекция этой точки
## на слой самолётов с камеры, чтобы на наклонной камере цель не «ехала» по земле.
var anchor := Vector2.INF
## 3.5: уклонение — рывок вбок с бочкой (видно в 3D), чтобы уйти с линии огня
var evade_t := 0.0
var evade_time := 0.7
var _evade_v := Vector2.ZERO
var _evade_roll := 1.0
## Тест 3.5-s7: манёвры асов разные — отворот с набором скорости, змейка, уход на скорости, изредка бочка.
## Пока идёт манёвр, курсом управляет он (поведение аса только двигает самолёт).
var man_kind := ""
var man_t := 0.0
var man_time := 1.0
var _man_h0 := 0.0
var _man_side := 1.0
var _man_spd := 0.0
var _man_last := ""
var _roll_ready := 0.0
## EX-04 (отзывы внешних тестеров 21.10, решение Kanta: А1): защита врага — против неё одно оружие слабее,
## другое сильнее, но в ноль не режется ничего («игрок не преодолевает, а кайфует»).
##   "armor" — броня (вертолёты, бронетехника, элитные): пушки и турели ×0,5, взрывы, рельсотрон, лазер ×1,3;
##   "agile" — манёвренный (перехватчики, асы): от взрывов и НАР уходит (×0,6), пушка ×1,15, лазер ×1,3;
##   помехи (ecm_t > 0) — их ставит ракетоносец вокруг себя: самонаводящиеся ракеты ×0,4 и цель выбирают
##   в последнюю очередь; ЭМИ снимает помехи на ECM_OFF секунд.
var defense := ""
var ecm_t := 0.0
var ecm_off_t := 0.0
const ECM_OFF := 8.0
const DEF_K := {
	"armor": {"gun": 0.5, "blast": 1.3, "homing": 1.0, "energy": 1.3, "ap": 1.3, "gun_ap": 1.0},
	"agile": {"gun": 1.15, "blast": 0.6, "homing": 1.0, "energy": 1.3, "ap": 1.0, "gun_ap": 1.15},
}
const DEF_HINT := {
	"armor": "Серый щит над врагом — броня: пушка и турели бьют вполовину, а НАР, бомбы, ракета «воздух-земля», рельсотрон и лазер — сильнее. Бронебойные снаряды пушки броню пробивают.",
	"agile": "Жёлтые шевроны — манёвренный враг: уходит от взрывов и НАР. Бейте его пушкой, лучше с хвоста.",
	"ecm": "Фиолетовые дуги — помехи ракетоносца: самонаводящиеся ракеты почти не попадают. Сбейте ракетоносец пушкой или снимите помехи ЭМИ.",
}
## правка 3.5-s4 (п. 26): расталкивание сглажено и уходит в курс — враги не дёргаются и не слипаются
var _sep := Vector2.ZERO


## EX-04: вид оружия по источнику урона (строки источников — как в статистике урона).
## PG-01: "ap" — guided air-to-ground missile (armor-piercing); armor-piercing course ammo — see `course_class`;
## burning from incendiary ammo ignores defences.
static func src_class(src: String) -> String:
	if src in ["ЭМИ", "лазер", "рельсотрон"]:
		return "energy"
	if src == "УР В-З":
		return "ap"
	if src in ["ракеты В-В", "ёлочка", "противоракеты", "ракеты ближнего боя"]:
		return "homing"
	if src.begins_with("курсовое") or src in ["гондола", "турели"] or src.begins_with("ведом"):
		return "gun"
	if src in ["проход на форсаже", "бронещит", "прочее", "горение"]:
		return ""
	return "blast"   # НАР, бомбы, ковровые, плазма, связки со взрывом


## PG-01 (Kanta 24.10): bullets with armor-piercing ammo are "gun_ap" (armor does not halve them). The source
## name stays «курсовое (…)», so logs, the damage report and the ace "on the tail" rule do not change.
static func course_class(c: String, src: String, ap_ammo: bool) -> String:
	return "gun_ap" if ap_ammo and c == "gun" and src.begins_with("курсовое") else c


static func _ap_ammo() -> bool:
	return Main.I != null and is_instance_valid(Main.I.player) and Main.I.player.ammo == "ap"


func jammed() -> bool:
	return ecm_t > 0.0 and ecm_off_t <= 0.0


## EX-04: множитель урона от защиты
func defense_k(src: String) -> float:
	var c := course_class(src_class(src), src, _ap_ammo())
	var k := 1.0
	if DEF_K.has(defense):
		k = float(DEF_K[defense].get(c, 1.0))
	if c == "homing" and jammed():
		k *= 0.4
	return k


## EX-04 Б2: урон в зависимости от того, откуда заходит игрок (лобовая броня у бомбардировщиков)
func aspect_k(_src: String) -> float:
	return 1.0


func make_elite() -> void:
	elite = true
	if defense == "":
		defense = "armor"   # EX-04: элитный — бронированный
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
		var mk: float = Main.I.player.mastery_k(self, source)
		if mk > 1.0:
			dmg *= mk
			Main.I.tele.add("mastery_dmg", dmg * (1.0 - 1.0 / mk))
	last_src = source
	var rc := src_class(source)
	if (rc == "gun" or rc == "blast") and is_instance_valid(Main.I.player) and not source.begins_with("ведом"):
		var rk: float = Main.I.player.run_k()
		if rk > 1.0:
			dmg *= rk
			Main.I.tele.add("run_dmg", dmg * (1.0 - 1.0 / rk))
	var dk := defense_k(source)
	if dk != 1.0:
		dmg *= dk
		var dkind := defense if DEF_K.has(defense) and DEF_K[defense].get(src_class(source), 1.0) != 1.0 else "ecm"
		Main.I.tele.add("def_" + dkind, 1.0)
		Hints.show("def_" + dkind, DEF_HINT[dkind], 9.0, 2)
	dmg *= aspect_k(source)
	if source == "ЭМИ":
		ecm_off_t = ECM_OFF
	if (is_boss or self is RivalAce) and Main.I.spawner != null:
		# тест 3.5-s5 (п. 10): урон по асу — мерило прочности следующих асов (Spawner.single_k);
		# второй список, п. 5: и по асу-сопернику в дуэли — тогда и первый ас по силам классу
		var pool := hp + float(get("shield")) if is_boss else hp
		Main.I.spawner.note_big(minf(dmg, pool), self, source)
	dmg = absorb(dmg)
	if min_life > 0.0:
		dmg = _cap_dps(dmg)
	if is_ground and not is_boss:
		dmg = _cap_burst(dmg)
	if dmg <= 0.0:
		_flash = 0.03
		return
	Main.I.add_stat("dealt", source, minf(dmg, hp))
	Main.I.tele.add("dealt_ground" if is_ground else "dealt_air", minf(dmg, hp))   # EX-08: урон по земле и по воздуху
	hp -= dmg
	_flash = 0.06
	Events.enemy_hit.emit(self, dmg)
	if hp <= 0.0:
		_die()


## Тест 3.5-s7 (Kanta: «ПВО сносится одной бомбой», «наземка — с одного залпа»): за один залп
## (BURST_WIN с первого попадания) наземная цель теряет не больше GROUND_BURST прочности —
## позицию ПВО и технику добивает только второй заход
const GROUND_BURST := 0.7
const BURST_WIN := 0.6
var _burst_t := -INF
var _burst_sum := 0.0


func _cap_burst(dmg: float) -> float:
	var now := Main.I.run_time
	if now - _burst_t > BURST_WIN:
		_burst_t = now
		_burst_sum = 0.0
	dmg = clampf(dmg, 0.0, maxf(0.0, max_hp * GROUND_BURST - _burst_sum))
	_burst_sum += dmg
	return dmg


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


## FB-01: куда пришлось попадание (мировая точка; INF — неизвестно). Ставят пули, ракеты и взрывы перед take_hit;
## пользуется «Крепость» — урон идёт в ту точку, в которую попали
var hit_at := Vector2.INF


## Попала ли пуля на отрезке a→b. У «Крепости» — своя форма (корпус, крылья, точки)
func seg_test(a: Vector2, b: Vector2) -> bool:
	return Projectiles.seg_hit(a, b, global_position, radius)


## Расстояние от взрыва до края цели (меньше нуля — внутри)
func aoe_dist(pos: Vector2) -> float:
	return pos.distance_to(global_position) - radius


## Куда наводится самонаводящаяся ракета, летящая из from, и радиус попадания вокруг этой точки
func aim_point(_from: Vector2) -> Vector2:
	return global_position


func aim_radius() -> float:
	return radius


func _die() -> void:
	hp = 0.0
	remove_from_group("enemies")
	_grant_rewards()
	queue_free()


## Reports the kill (`Events.enemy_killed`: kills, streak, parts) and drops XP and maybe a repair
## kit. XP drops after the event, so a tail kill's bonus XP is included. Bosses get full XP
## after 5:00 (S10-13). Shared by `ConvoyVehicle._die`.
func _grant_rewards() -> void:
	Events.enemy_killed.emit(self)
	Main.I.pickups.drop_xp(global_position, xp * Main.I.streak_mult() * (1.0 if is_boss else Main.I.kill_xp_k()))
	if randf() < repair_chance:
		Main.I.pickups.drop_repair(global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20)))


func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta)
	ecm_t = maxf(0.0, ecm_t - delta)
	ecm_off_t = maxf(0.0, ecm_off_t - delta)
	if _prev_pos != Vector2.INF and delta > 0.0:
		move_vel = move_vel.lerp((global_position - _prev_pos) / delta, 0.3)
	_prev_pos = global_position
	if anchor != Vector2.INF:
		global_position = GroundTarget.air_pos(anchor, anchor_lift())
	if leaving:
		_leave(delta)
		return
	if silence > 0.0:
		silence -= delta
		# тест 3.5-s7 («залипание врагов»): ЭМИ глушит оружие и автопилот, но самолёт летит дальше по инерции —
		# раньше он 3 с висел на месте
		if not is_ground:
			if _drift == Vector2.INF:
				_drift = move_vel
			position += _drift * delta
	else:
		_drift = Vector2.INF
		var h0 := heading
		behave(delta)
		if man_t > 0.0:
			heading = h0
			_maneuver(delta)
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


func maneuvering() -> bool:
	return man_t > 0.0 or evade_t > 0.0


## Тест 3.5-s7: манёвр против угрозы threat (направление огня). Вид выбирается случайно, не тот же, что
## в прошлый раз; бочка — не чаще раза в 6–9 с (раньше асы крутили её почти без перерыва).
## spd — сила манёвра, пикс/с (прибавка скорости, у бочки — смещение вбок). Вернёт вид манёвра.
func start_maneuver(threat: Vector2, spd := 320.0) -> String:
	if maneuvering():
		return ""
	var now := Main.I.run_time
	var pool := {"break": 3.0, "jink": 3.0, "extend": 2.0}
	if now >= _roll_ready:
		pool["roll"] = 2.0
	pool.erase(_man_last)
	var sum := 0.0
	for k in pool:
		sum += float(pool[k])
	var pick := randf() * sum
	var kind := "break"
	for k in pool:
		pick -= float(pool[k])
		if pick <= 0.0:
			kind = k
			break
	_man_last = kind
	if kind == "roll":
		_roll_ready = now + randf_range(6.0, 9.0)
		start_evade(threat, spd, 0.75)
		return kind
	# уходим в ту сторону, где мы и так уже от линии огня
	var perp := Vector2(-threat.y, threat.x)
	var p := Main.I.player
	if p != null and perp.dot(global_position - p.global_position) < 0.0:
		perp = -perp
	var side := signf(Vector2.from_angle(heading).cross(perp))
	_man_side = side if side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	_man_h0 = heading
	man_kind = kind
	match kind:
		"break":
			man_time = randf_range(1.1, 1.5)
			_man_h0 = heading + _man_side * deg_to_rad(randf_range(80.0, 120.0))
			_man_spd = spd * 0.4
		"jink":
			man_time = randf_range(1.4, 1.8)
			_man_spd = spd * 0.15
		_:
			man_time = randf_range(1.4, 1.9)
			_man_spd = spd * 0.7
	man_t = man_time
	Main.I.tele.add("enemy_evades")
	return kind


func _maneuver(delta: float) -> void:
	man_t -= delta
	var u := clampf(1.0 - man_t / man_time, 0.0, 1.0)
	var target := heading
	var rate := 150.0
	match man_kind:
		"break":
			target = _man_h0
		"jink":
			# змейка: ±40° от исходного курса, полтора колебания
			target = _man_h0 + _man_side * deg_to_rad(40.0) * sin(u * TAU * 1.5)
			rate = 170.0
		_:
			# уход на скорости: от игрока по прямой, разгон и сброс
			var p := Main.I.player
			if p != null:
				target = (global_position - p.global_position).angle()
			rate = 110.0
	heading = wrapf(rotate_toward(heading, target, deg_to_rad(rate) * delta), -PI, PI)
	position += Vector2.from_angle(heading) * _man_spd * sin(PI * u) * delta
	if man_t <= 0.0:
		man_t = 0.0
		man_kind = ""


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


## Height of the 3D model above the ground at `anchor` (a tower-top launcher); the logic position, hitbox
## and HP bar are projected from that height so they sit on the model, not on the ground under it.
func anchor_lift() -> float:
	return 0.0


## Полоска прочности у повреждённых крупных врагов; `hud_k` < 1 — короче и ближе к цели.
func draw_hp_bar() -> void:
	if hp >= max_hp or max_hp < 30.0:
		return
	var k := hud_k
	var w := radius * 2.0 * k
	var h := 4.0 if k >= 1.0 else 3.0
	var y := -radius - 12.0 if k >= 1.0 else -radius * k - 8.0   # a small bar sits close over its target
	draw_rect(Rect2(-w * 0.5, y, w, h), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w * 0.5, y, w * hp / max_hp, h), Color(1.0, 0.4, 0.3))


## Выстрел по игроку с упреждением.
## twin — спаренная пушка: две параллельные пули по половине урона (3.5, дрон)
## S8 «eweap»: twin у вида оружия (gun_kind) — каждая пуля с уроном вида (ЗСУ 5 + 5, истребители 3 + 3);
## у прочих (gun_kind «») — как раньше, по половине ebullet_dmg. Скорость пули — по виду оружия
func fire_at_player(spread := 0.0, twin := false) -> void:
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		return
	var gun := gun_kind()
	var spd := Projectiles.gun_speed(gun)
	var to := p.global_position - global_position
	var lead := p.global_position + p.velocity * (to.length() / spd) * 0.6
	var dir := (lead - global_position).normalized().rotated(spread)
	# 3.1: пуля летит быстрее стрелка — к её скорости добавляется скорость самолёта по курсу
	var add := maxf(0.0, move_vel.dot(dir)) * 0.6 if not is_ground else 0.0 # 3.2: пуля всё ещё быстрее стрелка, но мягче
	var at := global_position + dir * (radius + 4.0)
	var life := 3.3
	if gun == "zsu" or gun == "ifv":
		# дистанционный взрыватель: снаряд рвётся чуть дальше точки упреждения (разрыв в воздухе рядом с самолётом)
		life = clampf((lead - at).length() / (spd + add) + (0.12 if gun == "zsu" else 0.2), 0.3, 3.3)
	if twin:
		var side := Vector2(-dir.y, dir.x) * (9.0 if gun == "zsu" else 5.0)
		var k := 0.5 if gun == "" else 1.0
		Main.I.projectiles.spawn_enemy_bullet(at + side, dir * (spd + add), kind(), false, k * out_k, false, gun, life)
		Main.I.projectiles.spawn_enemy_bullet(at - side, dir * (spd + add), kind(), false, k * out_k, true, gun, life)
		return
	Main.I.projectiles.spawn_enemy_bullet(at, dir * (spd + add), kind(), false, out_k, false, gun, life)


## S8 «eweap»: вид пулемёта или пушки (Projectiles.GUN_NAMES): урон, скорость, разброс и трассер.
## «» — прочие, как было (ebullet_*)
func gun_kind() -> String:
	return ""


## Случайный разброс выстрела по виду оружия, рад
func gun_spread() -> float:
	var s := Projectiles.gun_spread(gun_kind())
	return randf_range(-s, s)


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
	draw_defense_mark()
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


## EX-04: значок защиты над врагом — броня (серый щит), манёвренный (жёлтые шевроны), помехи (фиолетовые дуги)
func draw_defense_mark() -> void:
	var y := -radius - 16.0 if hud_k >= 1.0 else -radius * hud_k - 15.0   # right over a small HP bar
	match defense:
		"armor":
			var sh := PackedVector2Array([Vector2(-6, y - 6), Vector2(6, y - 6), Vector2(6, y), Vector2(0, y + 6), Vector2(-6, y)])
			draw_colored_polygon(sh, Color(0.75, 0.8, 0.88, 0.95))
			draw_polyline(sh + PackedVector2Array([sh[0]]), Color(0.15, 0.17, 0.2, 0.9), 1.5)
		"agile":
			for i in 2:
				var yy := y - 4.0 + i * 6.0
				draw_polyline(PackedVector2Array([Vector2(-6, yy + 3), Vector2(0, yy - 2), Vector2(6, yy + 3)]), Color(1.0, 0.85, 0.2, 0.95), 2.5)
	if jammed():
		for i in 2:
			draw_arc(Vector2(0, y - 2.0 if defense != "" else y + 4.0), 6.0 + i * 5.0, -PI * 0.8, -PI * 0.2, 8, Color(0.8, 0.45, 1.0, 0.9), 2.0)
