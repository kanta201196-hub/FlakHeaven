class_name Player
extends Node2D
## Самолёт игрока. Класс (истребитель / штурмовик / бомбардировщик) задаёт прочность,
## скорость, курсовое оружие, группы подвесов, турели, лимит ведомых и третий навык.
## Полёт: нельзя остановиться, разворот ограничен, вектор скорости догоняет нос (инерция).

var cls_id := "fighter"
var cls: Dictionary = {}
var size := 1.0
var velocity := Vector2.ZERO
var heading := -PI / 2.0
var max_hp := 100.0
var hp := 100.0
var radius := 12.0 # хитбокс ~60% от размера спрайта
var bank := 0.0

## Множители и прибавки от карточек
var mods := {
	"speed": 1.0, "turn": 1.0, "gun_dmg": 1.0, "gun_rate": 1.0, "hp_cd": 1.0, "pickup": 1.0,
	"roll_cd": 0.0, "roll_time": 0.0, "ab_time": 0.0, "ab_cd": 0.0, "s3_cd": 1.0, "s3_lvl": 0,
	"dmg_all": 1.0, "hp_dmg": 0.0,
	"missile_dmg": 1.0, "missile_spd": 1.0, "blast_r": 1.0, "servo_rate": 1.0, "servo_range": 1.0,
	"wing_dmg": 1.0, "wing_hp": 1.0,
	"blast_dmg": 1.0, "twin": 0.0, "cluster_dmg": 0.0,
	"man_cd": 1.0, "taken_k": 1.0, "ground_dmg": 1.0, "turret_dmg": 1.0, "turret_rate": 1.0,
}
var skill_b := ""          # 3.2: навык во 2-м слоте (F), с экипажа ур. 5
var sb_cd := 0.0
var turn_t := 0.0          # таймер рывка «Боевого разворота»
var carpet_t := 0.0        # «Огненный ковёр»: турели ×2
var _second_wind := false  # перк «Второе дыхание» (раз за вылет)
var _upgrade_teased := false
## 3.1: прокачка
var tags := {}             # очки тегов: тег → число
var patches := {}          # нашивки: тег → 0/1/2
var picks := 0             # сколько карточек выбрано за вылет
var evo_wait := {}         # отказ от эволюции: оружие → номер выбора, с которого вернётся
var evo_times := {}        # когда получены эволюции (лог)
var patch_times := {}      # когда получены нашивки (лог)
var gun_evo := false       # «Дятел»
var course := ""           # 3.2: цель — связка, к которой идём
var course_pts := 0        # очки курса от активностей
var syn_dmg := {}          # урон по связкам
var _jet_last := Vector2.INF # «Реактивный след»
var _iron_cd := 0.0
var gun_evo_plus := 0
var _gun_n := 0
var ram_t := 0.0           # «Звуковой удар»: таран
var assault_t := 0.0       # «Штурмовой заход»
var umbrella_t := 0.0      # «Зенитный зонтик»
var ranks_t := 0.0         # «Сомкнуть строй»
var man_buff_t := 0.0      # нашивка «Манёвр II»
var roller_t := 0.0        # связка «Каток»
var _roller_cd := 0.0
var _armor2_cd := 0.0
var _straight_t := 0.0     # «Кит»: разбег
var _speed_buff_t := 0.0   # «Огненный ковёр» III
var _carpet_dir := 1.0
var _carpet2_delay := 0.0
var _shield_absorbed := 0.0
var _shield_tick := 0.0
var _shield_prev := 0.0
var _ram_prev := 0.0
var _assault_ext := 0.0
var _parade_t := 20.0
var _nest_done := false
var taken := {}            # сколько раз взята каждая карточка-модуль
var syn := {}              # открытые связки (2.8): id → true
var cards_log: Array = []  # названия взятых карточек — для итогов вылета
var groups: Array = []     # Hardpoint
var wingmen: Array = []    # Wingman
var skill3 := "combat_turn"

var manual_mode := false
var manual_bonus := 0.0
var invuln := 0.0

var roll_t := 0.0
var roll_cd := 0.0
var roll_dir := 1.0
var roll_inv := 0.0        # 3.5: неуязвимость бочки — у «Грача» переворот длиннее, а окно то же
var salvo_t := 0.0         # 3.5: «Кит» — залп ловушек (для индикатора)
var dive_t := 0.0          # 3.5 (правка 29): «Нырок» — самолёт ниже, пули и таран самолётов проходят над ним
var dive_cd := 0.0
var _turn_vel := 0.0       # 3.5: угловая скорость — набирается с ускорением класса
var _thr_hold := 0.0       # 3.5: сколько секунд РУД не на крейсерской
var _thr_lock := false     # 3.5: РУД вернули принудительно — ждём, пока отпустят W/S
var _cut_hold := 0.0       # 3.5: сколько секунд держат сброс газа
var _cut_lock := false
var ab_t := 0.0
var ab_cd := 0.0
var s3_t := 0.0
var s3_cd := 0.0
var combat_t := 0.0   # «боевой режим» после боевого разворота
var shield_t := 0.0   # бронещит
var _turn_target := 0.0
var _carpet_left := 0
var _carpet_tick := 0.0
var _carpet_i := 0

var throttle := 1.0    # РУД: W/S в схемах «мышь» и «влево/вправо», 55%…130% крейсерской
var tail_target: Enemy = null # враг, у которого мы «на хвосте»
var tail_t := 0.0
var _near_miss_cd := 0.0
var _pass_hit := {}   # кого уже задели за текущий форсаж
var _since_hit := 99.0
var _fire_cd := 0.0
var _gun_side := 1.0
var _blink := 0.0
var plane_lvl := 1       # внешний вид: ур. 1 → ур. 2 (модернизация по уровню пилота)
var _upgrade_flash := 0.0


func setup(id: String, sk := "", sk2 := "") -> void:
	cls_id = id
	cls = PlaneClasses.get_data(id)
	size = float(cls["size"])
	radius = 12.0 * size
	max_hp = float(cls["hp"])
	hp = max_hp
	skill3 = sk if PlaneClasses.CLASS_SKILLS[id].has(sk) else cls["skill3"]
	for gd in cls["groups"]:
		groups.append(Hardpoint.new(gd["name"], int(gd["slots"]), gd["weapon"]))
	var turrets := int(cls["turrets"])
	if turrets > 0:
		var tg := Hardpoint.new("Турели", turrets, "turret", true)
		if id == "bomber":
			tg.level = 2 # 3.1: «Кит» стартует с турелями ур. 2
		groups.append(tg)
	# стартовое оружие и навык дают очки тегов
	for g in groups:
		if not (g as Hardpoint).is_empty():
			add_tags(Prog.WEAPON_TAGS.get((g as Hardpoint).weapon, []), 1, true)
	add_tags(s3_def()["tags"], 1, true)
	if sk2 != "" and sk2 != skill3 and PlaneClasses.CLASS_SKILLS[id].has(sk2):
		skill_b = sk2
	Profile.apply(self)


# ---------- 3.1: теги, нашивки, эволюции ----------

func tag(t: String) -> int:
	return int(tags.get(t, 0))


## 3.2: нашивок больше нет (их заметные эффекты перешли в связки) — всегда 0
func patch(_t: String) -> int:
	return 0


func add_tags(arr: Array, n := 1, _quiet := false) -> void:
	for t in arr:
		tags[t] = tag(t) + n


# ---------- 3.2: курс и связки ----------

## +n очков главному тегу курса (активности, асы, «Наработка»)
func has_course() -> bool:
	return course != "" and course != "-"


func add_course_pts(n: int) -> void:
	if not has_course():
		return
	var sd := Cards.syn_def(self, course)
	add_tags([sd["tag"]], n)
	course_pts += n
	Main.I.fx.text(global_position + Vector2(0, -70), "+%d к курсу «%s»" % [n, sd["title"]], Color(1.0, 0.85, 0.35))


func open_synergy(id: String) -> void:
	syn[id] = Main.I.run_time
	syn_dmg[id] = 0.0
	if course == id:
		course = ""
	var sd := Cards.syn_def(self, id)
	Main.I.show_banner("СВЯЗКА «%s» — СЛОТ %d" % [String(sd["title"]).to_upper(), syn.size()], 4.5)
	Main.I.sfx.play("boss", -6.0, 1.6)
	Main.I.slowmo(0.6)
	Main.I.fx.ring(global_position, 260.0, sd.get("color", Color(1, 0.85, 0.3)))
	# первое срабатывание сразу — связку видно в ту же секунду
	match id:
		"hedgehog":
			for g in groups:
				(g as Hardpoint)._hh_cd = 0.0
		"warm":
			for w in wingmen:
				(w as Wingman)._bomb_cd = 0.0
		"roller":
			_roller_cd = 0.0
			roller_ring(10)
		"mirror":
			_mirror_fan()


## Главные теги (по очкам), для резервной карточки «Нашивка»
func top_tags(n: int) -> Array:
	var arr: Array = Prog.TAG_ORDER.duplicate()
	arr.sort_custom(func(a, b): return tag(a) > tag(b))
	return arr.slice(0, n)


func permanent_wingmen() -> int:
	var c := 0
	for w in wingmen:
		if not (w as Wingman).temp:
			c += 1
	return c


func reslot_wingmen() -> void:
	for i in wingmen.size():
		(wingmen[i] as Wingman).slot = i


func evolve(w: String) -> void:
	evo_times[w] = Main.I.run_time
	if w == "gun":
		gun_evo = true
		return
	for g in groups:
		var h: Hardpoint = g
		if h.weapon == w and h.level >= Weapons.MAX_LEVEL and not h.evo:
			h.evo = true
			h.cd = 0.3
			return


## Множитель урона ракет: «Глазастик», нашивка «Ракеты I»
func missile_k() -> float:
	return float(mods["missile_dmg"]) * (1.1 if patch("missiles") >= 1 else 1.0)


## «Ласка»: шанс сорвать захват вражеской ракеты рядом с ведущим
func jam_chance() -> float:
	var best := 0.0
	for w in wingmen:
		var wm: Wingman = w
		if wm.type == "weasel" and wm.alive():
			best = maxf(best, 0.4 if wm.lvl >= 2 else 0.25)
	return best


func s3_lvl() -> int:
	return int(mods["s3_lvl"])


## Уровень доводки навыка: карточки доводки действуют только на навык слота 1
func lvl_of(id: String) -> int:
	return s3_lvl() if id == skill3 else 0


func has_skill(id: String) -> bool:
	return skill3 == id or skill_b == id


func cd_of(id: String) -> float:
	var cd := float(PlaneClasses.SKILL3[id]["cd"])
	if id == "combat_turn" and lvl_of(id) >= 2:
		cd = 7.0
	if id == "sonic" and lvl_of(id) >= 3:
		cd = 10.0
	return cd * mods["s3_cd"]


func s3_cd_base() -> float:
	return cd_of(skill3)


## Сколько ещё действует навык (для интерфейса)
func s3_active(id := "") -> float:
	if id == "":
		id = skill3
	match id:
		"combat_turn":
			return combat_t
		"armor_shield":
			return shield_t
		"sonic":
			return ram_t
		"assault":
			return assault_t
		"umbrella":
			return umbrella_t
		"close_ranks":
			return ranks_t
		"carpet":
			return carpet_t
	return 0.0


func _ready() -> void:
	z_index = 2
	if cls.is_empty():
		setup("fighter")
	velocity = Vector2.from_angle(heading) * cruise_speed()


func cruise_speed() -> float:
	return Tuning.g("cruise_speed") * float(cls["speed"]) * mods["speed"]


func turn_rate() -> float:
	# Чем медленнее летим, тем круче разворот (до ×1,4), на форсаже — шире (до ×0,75)
	var f := velocity.length() / maxf(cruise_speed(), 1.0)
	var k := clampf(1.0 + (1.0 - f) * 0.8, 0.75, 1.4)
	return deg_to_rad(Tuning.g("turn_rate")) * float(cls["turn"]) * mods["turn"] * k


func on_tail() -> bool:
	return tail_t >= (0.15 if has_perk("f_tail1") else 0.3) and is_instance_valid(tail_target)


func pickup_radius() -> float:
	# «4 корпуса»: длина корпуса ~34 пикс × размер класса
	return Tuning.g("pickup_hulls") * 34.0 * size * mods["pickup"]


func roll_time() -> float:
	return (Tuning.g("roll_time") + mods["roll_time"]) * float(cls.get("roll_k", 1.0))


## 3.5: на «Пробеле» у «Кита» залп ловушек вместо бочки
func has_roll() -> bool:
	return String(cls.get("space", "roll")) == "roll"


func s3_def() -> Dictionary:
	return PlaneClasses.SKILL3[skill3]


func _process(delta: float) -> void:
	if hp <= 0.0:
		return
	_tick_timers(delta)
	_upgrade_flash = maxf(0.0, _upgrade_flash - delta * 0.8)
	check_upgrade()
	_throttle(delta)
	_track_tail(delta)
	_handle_skills()
	_steer(delta)
	_move(delta)
	_shoot(delta)
	for g in groups:
		(g as Hardpoint).update(delta, self)
	_carpet(delta)
	_skill_tick(delta)
	_jetwash()
	_iron_cd = maxf(0.0, _iron_cd - delta)
	if ab_t > 0.0:
		_afterburner_pass()
	queue_redraw()


## Проход на форсаже: врезаясь в строй, самолёт бьёт каждого врага, через которого прошёл.
## Урон растёт с уровнем и размером самолёта (бомбардировщик — «таран»), асы и наземные не в счёт.
func pass_damage() -> float:
	return Tuning.g("pass_dmg") * (1.0 + 0.06 * (Main.I.level - 1)) * size


func _afterburner_pass() -> void:
	var r := radius * 1.9
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or e.is_boss or e.is_ground:
			continue
		var id := e.get_instance_id()
		if _pass_hit.has(id):
			continue
		if global_position.distance_to(e.global_position) < r + e.radius:
			_pass_hit[id] = true
			Main.I.fx.ring(e.global_position, 40.0, Color(1.0, 0.8, 0.4))
			e.take_hit(pass_damage(), "проход на форсаже")
			Main.I.sfx.play("pass_hit", -8.0)
			Main.I.add_shake(3.0)


func _tick_timers(delta: float) -> void:
	roll_t = maxf(0.0, roll_t - delta)
	roll_inv = maxf(0.0, roll_inv - delta)
	salvo_t = maxf(0.0, salvo_t - delta)
	dive_t = maxf(0.0, dive_t - delta)
	dive_cd = maxf(0.0, dive_cd - delta)
	roll_cd = maxf(0.0, roll_cd - delta)
	ab_t = maxf(0.0, ab_t - delta)
	ab_cd = maxf(0.0, ab_cd - delta)
	s3_t = maxf(0.0, s3_t - delta)
	sb_cd = maxf(0.0, sb_cd - delta)
	turn_t = maxf(0.0, turn_t - delta)
	carpet_t = maxf(0.0, carpet_t - delta)
	s3_cd = maxf(0.0, s3_cd - delta)
	combat_t = maxf(0.0, combat_t - delta)
	shield_t = maxf(0.0, shield_t - delta)
	ram_t = maxf(0.0, ram_t - delta)
	assault_t = maxf(0.0, assault_t - delta)
	umbrella_t = maxf(0.0, umbrella_t - delta)
	ranks_t = maxf(0.0, ranks_t - delta)
	man_buff_t = maxf(0.0, man_buff_t - delta)
	roller_t = maxf(0.0, roller_t - delta)
	_roller_cd = maxf(0.0, _roller_cd - delta)
	_armor2_cd = maxf(0.0, _armor2_cd - delta)
	_speed_buff_t = maxf(0.0, _speed_buff_t - delta)
	invuln = maxf(0.0, invuln - delta)
	_blink += delta
	_near_miss_cd = maxf(0.0, _near_miss_cd - delta)
	# «Обороты» ручного огня: без попаданий шкала падает
	_since_hit += delta
	if manual_mode and _since_hit > Tuning.g("manual_grace"):
		manual_bonus = maxf(0.0, manual_bonus - Tuning.g("manual_decay") * delta)


func _turn_side() -> float:
	if absf(bank) > 0.1:
		return signf(bank)
	var t := Input.get_axis("move_left", "move_right")
	if absf(t) > 0.1:
		return signf(t)
	return 1.0


func _handle_skills() -> void:
	if Input.is_action_just_pressed("roll") and roll_cd <= 0.0 and roll_t <= 0.0 and not has_roll():
		_flare_salvo()
	elif Input.is_action_just_pressed("roll") and roll_cd <= 0.0 and roll_t <= 0.0:
		roll_t = roll_time()
		roll_inv = Tuning.g("roll_time") + mods["roll_time"]
		# 3.4: перезарядка не короче бочки + 1 с — без непрерывной неуязвимости при прокачке
		roll_cd = maxf(maxf(2.0, roll_t + 1.0), (Tuning.g("roll_cd") + mods["roll_cd"]) * float(cls.get("roll_cd_k", 1.0)) * float(mods["man_cd"]))
		Main.I.tele.add("roll_uses")
		roll_dir = _turn_side()
		if syn.has("mirror"):
			_mirror_fan()
		if patch("maneuver") >= 2:
			man_buff_t = 2.0
		Main.I.sfx.play("roll", -10.0)
	if Input.is_action_just_pressed("dive") and dive_cd <= 0.0 and dive_t <= 0.0:
		dive_t = Tuning.g("dive_time")
		dive_cd = maxf(dive_t + 1.0, Tuning.g("dive_cd") * float(mods["man_cd"]))
		Main.I.tele.add("dive_uses")
		Main.I.sfx.play("roll", -12.0, 0.6)
	if Input.is_action_just_pressed("afterburner") and ab_cd <= 0.0:
		ab_t = Tuning.g("afterburner_time") + mods["ab_time"]
		_pass_hit.clear()
		ab_cd = maxf(4.0, (Tuning.g("afterburner_cd") + mods["ab_cd"]) * float(mods["man_cd"]))
		if patch("maneuver") >= 2:
			man_buff_t = 2.0
		Main.I.sfx.play("afterburner", -8.0)
	if Input.is_action_just_pressed("sharp_turn") and s3_cd <= 0.0 and s3_active() <= 0.0:
		_activate_skill3(skill3, 0)
	if skill_b != "" and Input.is_action_just_pressed("skill_2") and sb_cd <= 0.0 and s3_active(skill_b) <= 0.0:
		_activate_skill3(skill_b, 1)
	if Input.is_action_just_pressed("toggle_fire_mode"):
		manual_mode = not manual_mode
		manual_bonus = 0.0


func _activate_skill3(id := "", slot := 0) -> void:
	if id == "":
		id = skill3
	var d: Dictionary = PlaneClasses.SKILL3[id]
	var lvl := lvl_of(id)
	if slot == 0:
		s3_cd = cd_of(id)
	else:
		sb_cd = cd_of(id)
	Main.I.stats_add_counter("skill3_uses" if slot == 0 else "skill2_uses", 1)
	match id:
		"combat_turn":
			s3_t = float(d["time"])
			turn_t = s3_t
			if int(Tuning.g("scheme")) == 2:
				_turn_target = (Render3D.I.mouse_world(get_global_mouse_position()) - global_position).angle()
			else:
				_turn_target = wrapf(heading + PI, -PI, PI)
			combat_t = s3_t + 3.0 + (1.0 if lvl >= 1 else 0.0)
			var n := Main.I.projectiles.break_locks(global_position, 1100.0)
			Main.I.stats_add_counter("locks_broken", n)
			if lvl >= 3:
				_intercept_all(250.0)
			if syn.has("s_wheel"): # «Чёртово колесо»: ракеты В-В сразу готовы
				for g in groups:
					if (g as Hardpoint).weapon == "aam":
						(g as Hardpoint).cd = 0.0
			Main.I.fx.ring(global_position, 90.0, Color(0.6, 0.9, 1.0))
			Main.I.sfx.play("combat_turn", -6.0, 0.7)
		"yolka":
			_fire_yolka(lvl)
		"sonic":
			ram_t = float(d["time"])
			s3_t = ram_t
			_ram_prev = ram_t
			if lvl >= 2:
				_sonic_wave()
			Main.I.sfx.play("afterburner", -4.0, 1.4)
		"armor_shield":
			s3_t = float(d["time"]) + (1.0 if lvl >= 1 else 0.0)
			shield_t = s3_t
			_shield_prev = shield_t
			_shield_absorbed = 0.0
			_shield_tick = 0.0
			Main.I.sfx.play("shield", -8.0, 0.5)
		"assault":
			assault_t = float(d["time"]) + (1.0 if lvl >= 1 else 0.0)
			s3_t = assault_t
			_assault_ext = 0.0
			for g in groups:
				if not (g as Hardpoint).builtin:
					(g as Hardpoint).cd = minf((g as Hardpoint).cd, 0.2)
			Main.I.sfx.play("combat_turn", -6.0, 0.9)
		"rooks":
			var n2 := 3 if lvl >= 2 else 2
			var life := 15.0 if lvl >= 1 else 12.0
			for i in n2:
				var keep := syn.has("s_nest") and not _nest_done and i == 0 and permanent_wingmen() < Cards.WING_MAX
				if keep:
					_nest_done = true # «Гнездо»: один остаётся насовсем
				add_wingman("rook", 1.0, not keep, life)
			Main.I.radio("Грачата", "Звено на подходе, работаем по земле!")
		"umbrella":
			umbrella_t = float(d["time"]) + (1.0 if lvl >= 1 else 0.0)
			s3_t = umbrella_t
			if syn.has("s_shelter"):
				for w in wingmen:
					(w as Wingman).salvo(2, 35.0, 0.5)
			Main.I.fx.ring(global_position, 300.0, Color(0.4, 0.95, 0.9))
			Main.I.sfx.play("shield", -8.0, 0.9)
		"carpet":
			carpet_t = float(d["time"])
			_carpet_left = 14 if lvl >= 1 else 10
			_carpet_tick = 0.0
			_carpet_i = 0
			_carpet_dir = 1.0
			if syn.has("s_double"):
				_carpet2_delay = 1.0
			if lvl >= 3:
				_speed_buff_t = 3.0
			Main.I.sfx.play("bomb_drop", -8.0, 0.6)
		"close_ranks":
			ranks_t = 8.0 if lvl >= 3 else float(d["time"])
			s3_t = ranks_t
			for w in wingmen:
				var wm: Wingman = w
				wm.salvo(4 if lvl >= 1 else 3, 40.0, ranks_t * 0.6)
				if lvl >= 2:
					wm.repair(0.5)
			Main.I.radio("Звено", "Смыкаем строй!")


## «Ёлочка»: мини-ракеты по разным целям
func _fire_yolka(lvl: int) -> void:
	var n := 14 if lvl >= 1 else 10
	var dmg := (45.0 if lvl >= 2 else 30.0) * missile_k()
	var targets: Array = []
	var skip: Array = []
	for i in n:
		var t := Weapons.pick_target(global_position, 700.0, "nearest", skip)
		if t == null:
			break
		targets.append(t)
		skip.append(t)
	var opts := {"splash": 40.0, "bounce": 1 if lvl >= 3 else 0, "fire": syn.has("s_newyear")}
	for i in n:
		var t: Enemy = targets[i % targets.size()] if not targets.is_empty() else null
		var a := heading + (float(i) / maxf(n - 1, 1) - 0.5) * 2.6
		Main.I.projectiles.spawn_player_missile(global_position, velocity * 0.5 + Vector2.from_angle(a) * 300.0, t, dmg, "ёлочка", opts)
	Main.I.sfx.play("aam_launch", -8.0, 1.6)


func _sonic_wave() -> void:
	var r := 320.0 if lvl_of("sonic") >= 1 else 260.0
	Main.I.projectiles.aoe(global_position, r, 60.0, "звуковой удар", false)
	_knockback(r, 90.0)
	if syn.has("s_clap"):
		_intercept_all(r)
	Main.I.fx.ring(global_position, r, Color(0.75, 0.9, 1.0))
	Main.I.add_shake(4.0)


func _knockback(r: float, dist: float) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or e.is_boss or e.is_ground:
			continue
		var to := e.global_position - global_position
		if to.length() < r + e.radius:
			e.position += to.normalized() * dist


func _intercept_all(r: float) -> void:
	var n := 0
	while n < 20 and Main.I.projectiles.intercept_missile(global_position, r):
		n += 1
	n += Main.I.projectiles.intercept_bullets(global_position, r)
	Main.I.stats_add_counter("intercepted_skill", n)


## Таймеры навыков: волна в конце «Звукового удара», импульсы и волна «Бронещита», «Двойной узор», «Парад»
func _skill_tick(delta: float) -> void:
	if has_skill("sonic") and _ram_prev > 0.0 and ram_t <= 0.0:
		_sonic_wave()
	_ram_prev = ram_t
	if has_skill("armor_shield"):
		if shield_t > 0.0 and lvl_of("armor_shield") >= 2:
			_shield_tick -= delta
			if _shield_tick <= 0.0:
				_shield_tick = 0.5
				for n in get_tree().get_nodes_in_group("enemies"):
					var e := n as Enemy
					if e != null and e.hp > 0.0 and not e.is_ground and e.global_position.distance_to(global_position) < radius + e.radius + 60.0:
						e.take_hit(60.0, "бронещит")
						if not e.is_boss:
							e.position += (e.global_position - global_position).normalized() * 50.0
		if _shield_prev > 0.0 and shield_t <= 0.0 and lvl_of("armor_shield") >= 3 and _shield_absorbed > 1.0:
			Main.I.projectiles.aoe(global_position, 220.0, _shield_absorbed * 0.3, "бронещит")
			Main.I.fx.ring(global_position, 220.0, Color(0.5, 1.0, 0.6))
		_shield_prev = shield_t
	if _carpet2_delay > 0.0:
		_carpet2_delay -= delta
		if _carpet2_delay <= 0.0:
			_carpet_left = 14 if lvl_of("carpet") >= 1 else 10
			_carpet_i = 0
			_carpet_tick = 0.0
			_carpet_dir = -1.0
	if syn.has("s_parade"):
		_parade_t -= delta
		if _parade_t <= 0.0:
			_parade_t = 20.0
			for w in wingmen:
				(w as Wingman).salvo(3, 40.0, 1.5)


## Сбит враг (Main сообщает): «Штурмовой заход» III продлевается за наземные цели
func on_kill(e: Enemy) -> void:
	if has_perk("f_tail2") and on_tail() and tail_target == e:
		roll_cd = maxf(0.0, roll_cd - 1.0)
		ab_cd = maxf(0.0, ab_cd - 1.0)
		s3_cd = maxf(0.0, s3_cd - 1.0)
		sb_cd = maxf(0.0, sb_cd - 1.0)
	if assault_t > 0.0 and e.is_ground and lvl_of("assault") >= 3 and _assault_ext < 3.0:
		assault_t += 0.5
		_assault_ext += 0.5


func _carpet(delta: float) -> void:
	if _carpet_left <= 0:
		return
	_carpet_tick -= delta
	if _carpet_tick > 0.0:
		return
	_carpet_tick = 1.0 / 12.0
	_carpet_left -= 1
	_carpet_i += 1
	var lvl := lvl_of("carpet")
	# спираль вокруг самолёта: радиус растёт 160 → 360, угол шаг 72° («Двойной узор» — в обратную сторону)
	var ang := heading + _carpet_i * deg_to_rad(72.0) * _carpet_dir
	var rad := 160.0 + 20.0 * _carpet_i
	var to := global_position + velocity * 0.5 + Vector2.from_angle(ang) * rad
	var dmg := 55.0 * (1.4 if lvl >= 2 else 1.0)
	var r := 120.0 * (1.2 if lvl >= 2 else 1.0)
	Main.I.projectiles.spawn_bomb(global_position, 0.5, dmg, r, "огненный ковёр", to)


func _steer(delta: float) -> void:
	var tr := turn_rate()
	var prev := heading
	# 3.5 (правка 13): угловая скорость набирается и гасится с ускорением класса — Оса вертится сразу,
	# Кит раскачивается и тормозит разворот заранее (без перелёта мимо цели)
	var accel := tr * float(cls.get("turn_accel", 6.0))
	var want := 0.0
	if turn_t > 0.0:
		# Боевой разворот: рывок носом к цели в 4 раза быстрее обычного
		heading = rotate_toward(heading, _turn_target, tr * 4.0 * delta + PI / float(s3_def()["time"]) * delta)
		_turn_vel = 0.0
	else:
		if int(Tuning.g("scheme")) == 2:
			var to_mouse := Render3D.I.mouse_world(get_global_mouse_position()) - global_position
			if to_mouse.length() > 30.0:
				want = _turn_to(to_mouse.angle(), tr, accel, delta)
		elif int(Tuning.g("scheme")) == 0:
			# 3.4: мёртвая зона одна — у действий (0,25); get_vector уже пересчитал длину после неё
			var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if dir != Vector2.ZERO:
				want = _turn_to(dir.angle(), tr, accel, delta)
		else:
			want = Input.get_axis("move_left", "move_right") * tr
		_turn_vel = move_toward(_turn_vel, want, accel * delta)
		heading += _turn_vel * delta
	heading = wrapf(heading, -PI, PI)
	var ang_vel := wrapf(heading - prev, -PI, PI) / maxf(delta, 0.0001)
	bank = lerpf(bank, clampf(ang_vel / tr, -1.0, 1.0), 1.0 - exp(-delta * 12.0))


## Желаемая угловая скорость к курсу target: не больше, чем успеем погасить до него (без перелёта)
func _turn_to(target: float, tr: float, accel: float, delta: float) -> float:
	var diff := wrapf(target - heading, -PI, PI)
	var v := minf(minf(tr, sqrt(2.0 * accel * absf(diff))), absf(diff) / maxf(delta, 0.0001))
	return signf(diff) * v


## 3.5 (правка 11): разгон и торможение — манёвр, а не режим. Держишь W/S — РУД уходит от крейсерской,
## отпустил — плавно возвращается; дольше throttle_hold с — возвращается сам, пока не отпустишь клавишу.
## Сброс газа (Ctrl) — так же, не дольше throttle_cut_hold с.
func _throttle(delta: float) -> void:
	_cut_hold = _cut_hold + delta if Input.is_action_pressed("throttle_cut") and not _cut_lock else 0.0
	if _cut_hold > Tuning.g("throttle_cut_hold"):
		_cut_lock = true
		_cut_hold = 0.0
	if _cut_lock and not Input.is_action_pressed("throttle_cut"):
		_cut_lock = false
	if int(Tuning.g("scheme")) == 0:
		throttle = 1.0 # в схеме «по направлению» W/S — это курс
		return
	var a := Input.get_axis("move_down", "move_up")
	if absf(a) <= 0.1:
		_thr_lock = false
	if absf(a) > 0.1 and not _thr_lock:
		throttle = clampf(throttle + a * 1.2 * delta, Tuning.g("throttle_min"), Tuning.g("throttle_max"))
		_thr_hold += delta
		if _thr_hold > Tuning.g("throttle_hold"):
			_thr_lock = true
			Main.I.tele.add("throttle_locks")
	else:
		throttle = move_toward(throttle, 1.0, Tuning.g("throttle_return") * delta)
		if is_equal_approx(throttle, 1.0):
			_thr_hold = 0.0


func throttle_cut_on() -> bool:
	return Input.is_action_pressed("throttle_cut") and not _cut_lock


## «На хвосте»: вражеский самолёт впереди в узком конусе, мы у него в задней полусфере.
## Держишься 0,3 с — курсовое +50% урона и автоогонь цепляется за него.
func _track_tail(delta: float) -> void:
	var best: Enemy = null
	var best_d := 520.0
	var fwd := Vector2.from_angle(heading)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0 or e is Drone or e.is_ground:
			continue
		var to := e.global_position - global_position
		var d := to.length()
		if d > best_d or d < 40.0:
			continue
		if absf(fwd.angle_to(to)) > deg_to_rad(32.0 if has_perk("f_tail1") else 26.0):
			continue
		# мы в задней полусфере цели
		if absf(Vector2.from_angle(e.heading).angle_to(-to)) < deg_to_rad(110.0):
			continue
		best = e
		best_d = d
	if best != null and best == tail_target:
		tail_t += delta
	elif best != null:
		tail_target = best
		tail_t = 0.0
	else:
		tail_t = maxf(0.0, tail_t - delta * 2.0)
		if tail_t <= 0.0:
			tail_target = null


## Пролёт на волоске от вражеской пули или ракеты: навыки перезаряжаются быстрее.
func on_near_miss(kind: String) -> void:
	if _near_miss_cd > 0.0:
		return
	_near_miss_cd = 0.35
	var cut := (0.6 if kind == "ракета" else 0.3) * (2.0 if has_perk("f_acro1") else 1.0)
	sb_cd = maxf(0.0, sb_cd - cut)
	roll_cd = maxf(0.0, roll_cd - cut)
	ab_cd = maxf(0.0, ab_cd - cut)
	s3_cd = maxf(0.0, s3_cd - cut)
	Main.I.on_near_miss(kind)


func _move(delta: float) -> void:
	var speed := cruise_speed() * throttle
	if throttle_cut_on():
		speed *= Tuning.g("throttle_cut_mult")
	if ab_t > 0.0:
		speed *= Tuning.g("afterburner_mult")
	if ram_t > 0.0:
		speed *= 1.8 # «Звуковой удар»
	if _speed_buff_t > 0.0:
		speed *= 1.3 # «Ковёр-самолёт»
	if cls_id == "bomber":
		# 3.1: черта «Кита» — разбег: прямой полёт дольше 1,2 с → до +20% скорости за 1 с
		if absf(bank) < 0.3:
			_straight_t += delta
		else:
			_straight_t = 0.0
		speed *= 1.0 + 0.2 * clampf(_straight_t - 1.2, 0.0, 1.0)
	var target := Vector2.from_angle(heading) * speed
	var k := 1.0 - exp(-delta / maxf(Tuning.g("inertia") * float(cls.get("inertia_k", 1.0)), 0.001))
	velocity = velocity.lerp(target, k)
	var step := velocity * delta
	if roll_t > 0.0:
		var side := Vector2.from_angle(heading + PI / 2.0) * roll_dir
		step += side * Tuning.g("roll_distance") / roll_time() * delta
	position += step # карта бесконечная — границ нет


const GUN_LIFE := 0.8 # 3.1: дальность курсового +33% (было 0,6 с полёта пули)


func gun_range() -> float:
	return Tuning.g("bullet_speed") * GUN_LIFE


func gun_damage() -> float:
	var d := Tuning.g("bullet_damage") * float(cls["gun_dmg"]) * float(mods["gun_dmg"])
	# 2.4: курсовое растёт вместе с пилотом (+3% за уровень, до +60%)
	d *= minf(1.0 + 0.03 * (Main.I.level - 1), 1.4) # 2.8: потолок +40% (было +60%)
	if manual_mode:
		d *= 1.0 + manual_bonus
	if combat_t > 0.0:
		d *= 1.3
	if on_tail():
		d *= 1.5
	if gun_evo:
		d *= 0.85 * (1.0 + 0.08 * gun_evo_plus) # «Дятел»: обычные снаряды −15%
	return d


func gun_rate() -> float:
	var r := Tuning.g("fire_rate") * float(cls["gun_rate"]) * float(mods["gun_rate"])
	if combat_t > 0.0:
		r *= 2.0
	return r


func _shoot(delta: float) -> void:
	_fire_cd -= delta
	var fwd := Vector2.from_angle(heading)
	var range_px := gun_range()
	var want := false
	var aim := fwd
	var lead := false
	if manual_mode:
		want = Input.is_action_pressed("fire")
		var t := _find_target(deg_to_rad(Tuning.g("assist_cone")), range_px)
		if t:
			aim = _lead_dir(t)
			lead = true
	else:
		var t2 := _find_target(deg_to_rad(Tuning.g("auto_cone")), range_px)
		if on_tail():
			t2 = tail_target
		want = t2 != null
		if t2 and (combat_t > 0.0 or on_tail()):
			aim = _lead_dir(t2)
			lead = true
	if not want:
		_fire_cd = maxf(_fire_cd, 0.0) # остаток таймера не копится, пока не стреляем
		return
	# 3.4: темп не зависит от FPS — остаток таймера переносится, за кадр до 4 выстрелов
	var rate := gun_rate()
	Main.I.tele.maxv("gun_rate_max", rate)
	var n := 0
	while _fire_cd <= 0.0 and n < 4:
		_fire_cd += 1.0 / rate
		n += 1
		_fire_one(fwd, aim, lead, maxf(0.0, -(_fire_cd - 1.0 / rate)))
	if n > 1:
		Main.I.tele.add("gun_multi_frames")
	_fire_cd = maxf(_fire_cd, -1.0 / rate)


func _fire_one(fwd: Vector2, aim: Vector2, lead: bool, age := 0.0) -> void:
	_gun_side = -_gun_side
	var muzzle := global_position + fwd * 16.0 * size + Vector2.from_angle(heading + PI / 2.0) * 7.0 * size * _gun_side
	Main.I.shots += 1
	_gun_n += 1
	var src := "курсовое (ручн.)" if manual_mode else "курсовое (авто)"
	var every := 3 if (manual_mode and manual_bonus >= 0.4) else 4
	if gun_evo and _gun_n % every == 0:
		# «Дятел»: пробивающий снаряд — всё на линии 900 пикс., урон ×2,5
		var spd := Tuning.g("bullet_speed") * 1.3
		Main.I.projectiles.spawn_player_bullet(muzzle, aim * spd + velocity, gun_damage() / 0.85 * 2.5, 900.0 / spd, manual_mode, src, 99)
	else:
		Main.I.projectiles.spawn_player_bullet(muzzle, aim * Tuning.g("bullet_speed") + velocity, gun_damage(), GUN_LIFE, manual_mode, src)
	var bl: Dictionary = Main.I.projectiles.bullets[-1]
	if age > 0.0: # выстрел «опоздал» на часть кадра — первый шаг пули длиннее на это время
		bl["lag"] = age
	if lead:
		bl["lead"] = true
		Main.I.tele.add("shots_lead")
	if _gun_side > 0.0:
		Main.I.sfx.play("gun_fire", -15.0)


## Направление с упреждением: куда стрелять, чтобы снаряд встретил цель
## 3.4: учитывает скорость самолёта, которую наследует пуля, и решает время встречи (ближайшее t > 0 в пределах жизни пули)
func _lead_dir(t: Enemy) -> Vector2:
	var s := Tuning.g("bullet_speed")
	var r := t.global_position - global_position
	var w := t.move_vel - velocity # движение цели относительно точки вылета пули
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
	if tau <= 0.0 or tau > GUN_LIFE:
		Main.I.tele.add("lead_nosol")
		return r.normalized() # встречи нет — стреляем прямо по цели
	return ((r + w * tau) / (s * tau)).normalized()


func _find_target(cone: float, max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_ang := cone
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var to := e.global_position - global_position
		var d := to.length()
		if d > max_dist or d < 1.0:
			continue
		var ang := absf(wrapf(to.angle() - heading, -PI, PI)) - atan2(e.radius, d)
		if ang <= best_ang:
			best_ang = ang
			best = e
	return best


func add_wingman(type := "swift", k := 1.0, temp := false, life := 0.0) -> void:
	var w := Wingman.new()
	w.setup(type, k, temp, life)
	w.slot = wingmen.size()
	w.global_position = global_position - Vector2.from_angle(heading) * 60.0
	w.heading = heading
	wingmen.append(w)
	Main.I.world.add_child(w)


func on_bullet_hit() -> void:
	if manual_mode:
		manual_bonus = minf(Tuning.g("manual_max"), manual_bonus + Tuning.g("manual_step"))
		_since_hit = 0.0
		Main.I.peak_rev = maxf(Main.I.peak_rev, manual_bonus)


func on_bullet_miss() -> void:
	if manual_mode:
		manual_bonus = maxf(0.0, manual_bonus - Tuning.g("manual_miss"))


## 3.5 (правка 29): глубина нырка 0…1 — плавно вниз за 0,25 с, вверх за 0,35 с (для картинки)
func dive_k() -> float:
	if dive_t <= 0.0:
		return 0.0
	var gone := Tuning.g("dive_time") - dive_t
	return clampf(minf(gone / 0.25, dive_t / 0.35), 0.0, 1.0)


## В нырке пули и таран вражеских самолётов проходят выше; ПВО, ракеты и земля — бьют
func dodges(source: String, who: String) -> bool:
	return dive_t > 0.0 and who != "ПВО" and (source == "пули" or source == "таран")


func is_invulnerable() -> bool:
	return roll_inv > 0.0 or invuln > 0.0 or Main.I.god_mode


func heal(amount: float) -> void:
	var before := hp
	hp = minf(max_hp, hp + amount)
	Main.I.stats_add_counter("healed", int(round(hp - before)))


func damage(amount: float, source := "прочее", who := "") -> void:
	if is_invulnerable() or hp <= 0.0:
		return
	if dodges(source, who):
		return
	if dive_t > 0.0 and who == "ПВО":
		amount *= Tuning.g("dive_aa_k")
	if shield_t > 0.0:
		_shield_absorbed += amount * 0.7
		amount *= 0.3
	if patch("armor") >= 1:
		amount *= 0.92
	if umbrella_t > 0.0 and lvl_of("umbrella") >= 3:
		amount *= 0.8
	if ranks_t > 0.0:
		var near := 0
		for w in wingmen:
			if (w as Wingman).alive() and (w as Wingman).global_position.distance_to(global_position) < 240.0:
				near += 1
		amount *= 1.0 - minf(0.6, 0.2 * near)
	if syn.has("roller") and _roller_cd <= 0.0:
		var low := hp < max_hp * 0.4
		_roller_cd = 1.5 if low else 2.5
		roller_ring(16 if low else 10)
	if syn.has("s_iron") and shield_t > 0.0 and _iron_cd <= 0.0:
		_iron_cd = 0.25
		var t := Weapons.pick_target(global_position, 800.0, "nearest")
		if t != null:
			var d := (t.global_position - global_position).normalized()
			Main.I.projectiles.spawn_rocket(global_position, velocity + d * 900.0, 30.0, 60.0, 0.0, {"src": "связка: утюг"})
	amount *= float(mods["taken_k"])
	var big_hit := amount > max_hp * 0.1
	hp -= amount
	if has_perk("a_arm2") and not _second_wind and hp > 0.0 and hp < max_hp * 0.25:
		_second_wind = true # перк «Второе дыхание»
		heal(max_hp * 0.2)
		Main.I.fx.text(global_position + Vector2(0, -60), "Второе дыхание!", Color(0.6, 1.0, 0.7))
		invuln = 2.0
		Main.I.on_player_damaged(amount)
		return
	Main.I.add_stat("taken", source, amount)
	if who != "":
		Main.I.add_stat("taken_by", who, amount)
	invuln = 0.7
	if big_hit and patch("armor") >= 2 and _armor2_cd <= 0.0:
		invuln = 1.0
		_armor2_cd = 12.0
	if manual_mode:
		manual_bonus = maxf(0.0, manual_bonus - Tuning.g("manual_hit_penalty"))
	Main.I.on_player_damaged(amount)
	if hp <= 0.0:
		hp = 0.0
		visible = false
		for w in wingmen:
			if is_instance_valid(w):
				w.queue_free()
		wingmen.clear()
		Main.I.on_player_dead()


## «Каток»: кольцо НАР во все стороны
func roller_ring(n: int) -> void:
	for i in n:
		var d := Vector2.from_angle(TAU * i / n + randf() * 0.2)
		Main.I.projectiles.spawn_rocket(global_position + d * 20.0, velocity * 0.5 + d * 800.0, 18.0, 60.0, 0.0, {"src": "связка: каток", "life": 0.45})
	Main.I.sfx.play("rocket_launch", -8.0, 1.4)


## «Зеркало»: веер из 6 ловушек на бочке — каждая уводит ракету в 300 пикс.
## 3.5 (правки 12, 26): «Кит» на «Пробеле» отстреливает веер тепловых ловушек.
## Все вражеские ракеты рядом уходят на ловушки и рвутся возле них, дальние теряют захват. Неуязвимости нет.
const SALVO_R := 420.0


func _flare_salvo() -> void:
	roll_cd = maxf(3.0, (Tuning.g("roll_cd") + mods["roll_cd"]) * float(cls.get("roll_cd_k", 1.0)) * float(mods["man_cd"]))
	salvo_t = 0.6
	Main.I.tele.add("roll_uses")
	Main.I.tele.add("flare_salvos")
	Main.I.fx.flare_burst(global_position, heading, 14, velocity, 1.6)
	var n := 0
	for i in 12:
		if Main.I.projectiles.intercept_missile_at(global_position, SALVO_R, true) == null:
			break
		n += 1
	n += Main.I.projectiles.break_locks(global_position, SALVO_R * 2.2)
	Main.I.stats_add_counter("intercepted", n)
	if syn.has("mirror"):
		_mirror_fan()
	if patch("maneuver") >= 2:
		man_buff_t = 2.0
	Main.I.sfx.play("flare", -6.0, 1.4)


func _mirror_fan() -> void:
	Main.I.fx.flare_burst(global_position, heading, 6, velocity)
	for i in 6:
		if Main.I.projectiles.intercept_missile_at(global_position, 300.0, true) == null:
			break


## «Реактивный след»: заряды за самолётом на бочке и форсаже
func _jetwash() -> void:
	if not syn.has("jetwash") or (roll_t <= 0.0 and ab_t <= 0.0):
		_jet_last = Vector2.INF
		return
	if _jet_last == Vector2.INF or _jet_last.distance_to(global_position) >= 50.0:
		_jet_last = global_position
		var k := 1.0 + 0.1 * (int(taken.get("roll", 0)) + int(taken.get("afterburner", 0)))
		Main.I.projectiles.spawn_bomb(global_position, 0.4, 30.0 * k, 70.0, "связка: реактивный след", global_position)


func _draw() -> void:
	var w := 1.0 - 0.45 * absf(bank)
	if roll_t > 0.0:
		var p := 1.0 - roll_t / roll_time()
		w = maxf(0.15, absf(cos(p * TAU)))
	var xf := Transform2D(heading, Vector2.ZERO).scaled(Vector2(size, size))
	if Tuning.g("sprites") >= 1 and PlaneArt.plane_tex(cls_id, plane_lvl) != null:
		if Render3D.enabled:
			_draw_3d_extras(w)
		else:
			_draw_sprite(w)
		_draw_overlays()
		return
	var shape: PackedVector2Array
	var ww := maxf(w, 0.35) # не даём крылу «схлопнуться» в бочке — иначе полигон самопересекается
	match cls_id:
		"attacker":
			shape = PackedVector2Array([Vector2(20, 0), Vector2(4, 4), Vector2(-2, 17 * ww), Vector2(-10, 17 * ww), Vector2(-8, 4),
				Vector2(-16, 8 * ww), Vector2(-16, -8 * ww), Vector2(-8, -4), Vector2(-10, -17 * ww), Vector2(-2, -17 * ww), Vector2(4, -4)])
		"bomber":
			shape = PackedVector2Array([Vector2(18, 0), Vector2(6, 4), Vector2(-4, 20 * ww), Vector2(-10, 20 * ww), Vector2(-8, 4),
				Vector2(-16, 4), Vector2(-16, -4), Vector2(-8, -4), Vector2(-10, -20 * ww), Vector2(-4, -20 * ww), Vector2(6, -4)])
		_:
			shape = PackedVector2Array([Vector2(20, 0), Vector2(-14, 15 * w), Vector2(-8, 0), Vector2(-14, -15 * w)])
	var body := xf * shape
	var col: Color = cls["color"]
	if roll_t > 0.0:
		col = Color(0.85, 0.97, 1.0)
	elif invuln > 0.0 and int(_blink * 20.0) % 2 == 0:
		col.a = 0.35
	if ab_t > 0.0:
		var fl := xf * PackedVector2Array([Vector2(-9, 4), Vector2(-30 - randf() * 10.0, 0), Vector2(-9, -4)])
		draw_colored_polygon(fl, Color(1.0, 0.6, 0.2, 0.9))
	draw_colored_polygon(body, col)
	_draw_overlays()


func _sprite_scale() -> float:
	var s := PlaneArt.shape_info(cls_id, plane_lvl)
	if s.is_empty():
		return 1.0
	# длина на экране: истребитель plane_len, остальные × size; ур. 2 чуть крупнее по пропорции картинок
	var base_len := Tuning.g("plane_len") * size
	var s1 := PlaneArt.shape_info(cls_id, 1)
	var k_lvl := float(s["w"]) / float(s1["w"]) if not s1.is_empty() else 1.0
	return base_len * k_lvl / float(s["w"])


func _draw_sprite(w: float) -> void:
	var tex := PlaneArt.plane_tex(cls_id, plane_lvl)
	var k := _sprite_scale()
	var sc := Vector2(k, k * w)
	var col := Color(1, 1, 1, 1)
	if invuln > 0.0 and roll_t <= 0.0 and int(_blink * 20.0) % 2 == 0:
		col.a = 0.4
	var half := tex.get_size() / 2.0
	# тень на земле: сдвиг вниз-вправо, тёмная и полупрозрачная
	draw_set_transform(Vector2(10.0, 16.0) * size, heading, sc * 0.92)
	draw_texture(tex, -half, Color(0, 0, 0, 0.28 * col.a))
	# форсаж — пламя за соплами
	if ab_t > 0.0:
		var s := PlaneArt.shape_info(cls_id, plane_lvl)
		var tx: float = s.get("tail", -half.x)
		draw_set_transform(Vector2.ZERO, heading, sc)
		var fl := PackedVector2Array([Vector2(tx + 3, 3.0 / maxf(w, 0.3)), Vector2(tx - 14.0 - randf() * 8.0, 0), Vector2(tx + 3, -3.0 / maxf(w, 0.3))])
		draw_colored_polygon(fl, Color(1.0, 0.6, 0.2, 0.9))
	var base := Transform2D(heading, sc, 0.0, Vector2.ZERO)
	draw_set_transform_matrix(base)
	draw_texture(tex, -half, col)
	# подвесы: видны на точках подвеса, на перезарядке — полупрозрачные
	for gi in groups.size():
		var g: Hardpoint = groups[gi]
		if g.is_empty():
			continue
		var pts := PlaneArt.slot_points(cls_id, plane_lvl, gi, g)
		var a := 1.0
		if g.weapon in ["aam", "rockets", "bombs"] and g.cd > 0.3:
			a = 0.4
		var wk := 1.0 / maxf(k, 0.01) # оружие в экранных пикселях, независимо от масштаба картинки
		for pt in pts:
			PlaneArt.draw_weapon(self, g.weapon, pt, wk, a * col.a, base)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if roll_t > 0.0:
		draw_set_transform(Vector2.ZERO, heading, sc)
		draw_texture(tex, -half, Color(0.8, 0.95, 1.0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _upgrade_flash > 0.0:
		draw_circle(Vector2.ZERO, 40.0 * size * (1.6 - _upgrade_flash), Color(1.0, 0.95, 0.6, 0.35 * _upgrade_flash))


## 3.0: модель в 3D — здесь только пламя форсажа и вспышка модернизации
func _draw_3d_extras(w: float) -> void:
	var tex := PlaneArt.plane_tex(cls_id, plane_lvl)
	var k := _sprite_scale()
	if ab_t > 0.0:
		var s := PlaneArt.shape_info(cls_id, plane_lvl)
		var tx: float = s.get("tail", -tex.get_width() / 2.0)
		draw_set_transform(Vector2.ZERO, heading, Vector2(k, k * w))
		var fl := PackedVector2Array([Vector2(tx + 3, 3.0 / maxf(w, 0.3)), Vector2(tx - 14.0 - randf() * 8.0, 0), Vector2(tx + 3, -3.0 / maxf(w, 0.3))])
		draw_colored_polygon(fl, Color(1.0, 0.6, 0.2, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _upgrade_flash > 0.0:
		draw_circle(Vector2.ZERO, 40.0 * size * (1.6 - _upgrade_flash), Color(1.0, 0.95, 0.6, 0.35 * _upgrade_flash))


func has_perk(id: String) -> bool:
	return Profile.has_perk(cls_id, id)


## 3.5: самолёт ур. 2 выбирается в ангаре до вылета (Profile.apply); в вылете модернизации нет
func check_upgrade() -> void:
	pass


func _draw_overlays() -> void:
	if on_tail():
		var tp := to_local(tail_target.global_position)
		draw_arc(tp, tail_target.radius + 12.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.3, 0.9), 2.0)
		draw_line(Vector2.from_angle(heading) * 30.0, tp, Color(1.0, 0.9, 0.3, 0.25), 1.0)
	if combat_t > 0.0:
		draw_arc(Vector2.ZERO, 24.0 * size, 0.0, TAU, 32, Color(0.6, 0.9, 1.0, 0.5 + 0.3 * sin(_blink * 20.0)), 2.0)
	if shield_t > 0.0:
		draw_arc(Vector2.ZERO, 30.0 * size, 0.0, TAU, 40, Color(0.5, 1.0, 0.6, 0.8), 4.0)
		draw_circle(Vector2.ZERO, 30.0 * size, Color(0.5, 1.0, 0.6, 0.12))
	# 3.1: дальность курсового и ракет В-В — пунктирные круги (можно выключить в настройках)
	if Tuning.g("range_rings") > 0.5:
		_dashed_circle(gun_range(), Color(1.0, 0.95, 0.75, 0.26))
		for g in groups:
			var h: Hardpoint = g
			if h.weapon == "aam" or (h.weapon == "turret" and h.slots > 0):
				_dashed_circle(h.range_px(), Color(1.0, 0.5, 0.4, 0.2) if h.weapon == "aam" else Color(0.4, 0.9, 0.85, 0.16), 2.0, 72 if h.weapon == "aam" else 56)
	# Радиус подбора опыта — еле заметный круг
	draw_arc(Vector2.ZERO, pickup_radius(), 0.0, TAU, 64, Color(0.5, 1.0, 0.6, 0.06), 1.0)
	if manual_mode:
		var f := Vector2.from_angle(heading)
		draw_line(f * 26.0 * size, f * 90.0, Color(1, 1, 1, 0.25), 1.0)
		var frac := manual_bonus / maxf(Tuning.g("manual_max"), 0.01)
		var rr := 30.0 * size + 8.0
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 3.0)
		var tc := Color(0.4, 1.0, 0.5).lerp(Color(1.0, 0.85, 0.3), clampf(frac * 2.0, 0.0, 1.0))
		if frac > 0.5:
			tc = tc.lerp(Color(1.0, 0.3, 0.2), (frac - 0.5) * 2.0)
		draw_arc(Vector2.ZERO, rr, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, tc, 4.0)


func _dashed_circle(r: float, col: Color, width := 2.0, dashes := 64) -> void:
	var step := TAU / dashes
	for i in dashes:
		var a0 := i * step
		draw_arc(Vector2.ZERO, r, a0, a0 + step * 0.5, 4, col, width)
