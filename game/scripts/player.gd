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
	"missile_dmg": 1.0, "missile_spd": 1.0, "blast_r": 1.0, "servo_rate": 1.0, "servo_range": 1.0, "turret_traverse": 1.0,
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
var mastery := false        # фишка 2: мастерство класса взято
## PG-01: course gun variant for this sortie (`WeaponBalance.GUNS` id), chosen in the hangar
var gun_variant := "std"
var ammo := "std"   # PG-01 (Kanta 24.10): course gun ammo type (`WeaponBalance.AMMO`)
var mastery_off := false    # от карточки мастерства отказались — больше не придёт
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
var _energy := 1.0         # тест 3.5-s7: доля скорости — крутой разворот её съедает, на прямой набирается
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
var turn_lock: Enemy = null  # цель «Боевого разворота»: нос и пушка держатся на ней весь боевой режим
var _carpet_left := 0
var _carpet_tick := 0.0
var _carpet_i := 0

var throttle := 1.0    # РУД: W/S в схемах «мышь» и «влево/вправо», 55%…130% крейсерской
## EX-04 (Б1, отзывы внешних тестеров: «можно крутиться на месте»): заход на атаку — после ~1 с прямого
## полёта пушка, НАР и бомбы бьют сильнее (до +30%); крутой вираж бонус сбрасывает
var straight_t := 0.0
var _h_prev := INF
const RUN_BONUS := 0.3
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

# модули (код вынесен из этого файла, состояние — здесь)
var flight: PlayerFlight
var guns: PlayerGuns
var skills: PlayerSkills
var drawer: PlayerDraw


func _init() -> void:
	flight = PlayerFlight.new(self)
	guns = PlayerGuns.new(self)
	skills = PlayerSkills.new(self)
	drawer = PlayerDraw.new(self)


func setup(id: String, sk := "", sk2 := "") -> void:
	cls_id = id
	cls = PlaneClasses.plane(id, Profile.plane_lvl(id))   # Kanta 24.10: weapons, ★ bonus, turrets, wingmen per plane
	for arg in OS.get_cmdline_user_args():   # check flag --bonus=<weapon>:<k>, e.g. --bonus=agm:1.0 (A/B of a plane bonus)
		if String(arg).begins_with("--bonus=") and String(arg).contains(":"):
			var kv := String(arg).substr(8).split(":")
			cls["bonus"][kv[0]] = float(kv[1])
	size = float(cls["size"])
	radius = 12.0 * size
	max_hp = float(cls["hp"])
	hp = max_hp
	skill3 = sk if PlaneClasses.CLASS_SKILLS[id].has(sk) else cls["skill3"]
	gun_variant = Profile.gun(id)
	ammo = Profile.ammo(id)
	for arg in OS.get_cmdline_user_args():   # PG-01 check flags --gun=twin|heavy, --ammo=ap|he|inc
		if String(arg).begins_with("--gun=") and WeaponBalance.GUNS.has(String(arg).substr(6)):
			gun_variant = String(arg).substr(6)
		if String(arg).begins_with("--ammo=") and WeaponBalance.AMMO.has(String(arg).substr(7)):
			ammo = String(arg).substr(7)
	for gd in cls["groups"]:
		groups.append(Hardpoint.new(gd["name"], int(gd["slots"]), gd["weapon"]))
	# U-06: самолёт ур. 2 — тяжёлый подвес под экспериментальное оружие (после турелей: номера групп моделей не сдвигаются)
	var heavy: Hardpoint = null
	if Profile.plane_lvl(id) == 2:
		heavy = Hardpoint.new("Тяжёлый подвес", 1, "")
		heavy.heavy = true
	for arg in OS.get_cmdline_user_args():   # проверка: --heavy=railgun / emp — тяжёлый подвес с оружием сразу; --mastery — мастерство с начала
		if arg == "--mastery":
			mastery = true
		if String(arg).begins_with("--heavy="):
			heavy = Hardpoint.new("Тяжёлый подвес", 1, String(arg).substr(8))
			heavy.heavy = true
	var turrets := int(cls["turrets"])
	if turrets > 0:
		var tg := Hardpoint.new("Турели", turrets, "turret", true)
		if id == "bomber":
			tg.level = 2 # 3.1: «Кит» стартует с турелями ур. 2
		tg.slots = PlaneClasses.turret_slots(id, tg.level, int(cls["plane_lvl"]))
		groups.append(tg)
	if heavy != null:
		groups.append(heavy)
	# PG-01: third group (hangar node «Узлы подвеса» lvl 2) goes last, so no other group index shifts;
	# check flag --group3 opens it without the node
	if Profile.third_group(id) or OS.get_cmdline_user_args().has("--group3"):
		var g3: Dictionary = PlaneClasses.GROUP3[id]
		var h3 := Hardpoint.new(g3["name"], int(g3["slots"]), g3["weapon"])
		h3.mount_frac = float(g3.get("frac", 0.0))
		groups.append(h3)
	# фишка 3: оружие, выбранное в ангаре, — на первый пустой обычный подвес, ур. 1
	var s2 := Profile.start2(id)
	if s2 != "":
		for g in groups:
			var h: Hardpoint = g
			if not h.builtin and not h.heavy and h.is_empty():
				h.weapon = s2
				h.level = 1
				h.cd = 0.5
				break
	# PG-01 check flag --weapon=<id>: that weapon on the last empty normal group from the start
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--weapon="):
			var w0 := String(arg).substr(9)
			for gi in range(groups.size() - 1, -1, -1):
				var h0: Hardpoint = groups[gi]
				if Weapons.DEFS.has(w0) and not h0.builtin and not h0.heavy and h0.is_empty():
					h0.weapon = w0
					h0.level = 1
					h0.cd = 0.5
					break
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
	Main.I.fx.text(global_position + Vector2(0, -70), "+%d к специализации «%s»" % [n, sd["title"]], Color(1.0, 0.85, 0.35))


func open_synergy(id: String) -> void:
	syn[id] = Main.I.run_time
	syn_dmg[id] = 0.0
	if course == id:
		course = ""
	var sd := Cards.syn_def(self, id)
	Events.banner.emit("СВЯЗКА «%s» — СЛОТ %d" % [String(sd["title"]).to_upper(), syn.size()], 4.5)
	Main.I.sfx.play("synergy", -6.0, 1.6)
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
			skills._mirror_fan()


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
	return Tuning.g("cruise_speed") * float(cls["speed"]) * mods["speed"] * Fuel.speed_k() # 3.5: пустой бак −30%


func turn_rate() -> float:
	return minf(turn_rate_free(), turn_cap())


## Скорость разворота без предела радиуса: от неё же — как быстро набирается крен (карточки «Крыло» не пропадают)
func turn_rate_free() -> float:
	# Чем медленнее летим, тем круче разворот (до ×1,4), на форсаже — шире (до ×0,75)
	var f := velocity.length() / maxf(cruise_speed(), 1.0)
	var k := clampf(1.0 + (1.0 - f) * 0.8, 0.75, 1.4)
	return deg_to_rad(Tuning.g("turn_rate")) * float(cls["turn"]) * mods["turn"] * k


## Тест 3.5-s7: предел по радиусу разворота класса — угловая скорость не больше скорость / радиус.
## Сброс газа и прокачка разворота больше не дают крутиться на месте; «Кит» разворачивается широко.
func turn_cap() -> float:
	var r := float(cls.get("min_r", 0.0)) * Tuning.g("turn_radius_k")
	if r <= 0.0:
		return INF
	return maxf(velocity.length(), cruise_speed() * 0.3) / r


func lock_ok() -> bool:
	return is_instance_valid(turn_lock) and turn_lock.hp > 0.0


## EX-04: множитель урона «заход на атаку» (1,0…1,3)
func run_k() -> float:
	return 1.0 + RUN_BONUS * clampf((straight_t - 0.5) / 0.7, 0.0, 1.0)


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
	flight._tick_timers(delta)
	_upgrade_flash = maxf(0.0, _upgrade_flash - delta * 0.8)
	check_upgrade()
	flight._throttle(delta)
	flight._track_tail(delta)
	if _h_prev != INF and delta > 0.0:
		if absf(angle_difference(_h_prev, heading)) / delta < 0.6:
			straight_t += delta
		else:
			straight_t = maxf(0.0, minf(straight_t, 1.2) - delta * 3.0)
	_h_prev = heading
	if straight_t > 1.3 and Main.I.run_time > 40.0:
		Hints.show("run", "Заход на атаку: летите прямо секунду — пушка, НАР и бомбы бьют до +30% сильнее. На крутом вираже бонус пропадает.", 8.0, 2)
	skills._handle_skills()
	flight._steer(delta)
	flight._move(delta)
	guns._shoot(delta)
	for g in groups:
		(g as Hardpoint).update(delta, self)
	skills._carpet(delta)
	skills._skill_tick(delta)
	skills._jetwash()
	_iron_cd = maxf(0.0, _iron_cd - delta)
	if ab_t > 0.0:
		skills._afterburner_pass()
	queue_redraw()


## Проход на форсаже: врезаясь в строй, самолёт бьёт каждого врага, через которого прошёл.
## Урон растёт с уровнем и размером самолёта (бомбардировщик — «таран»), асы и наземные не в счёт.
func pass_damage() -> float:
	return Tuning.g("pass_dmg") * (1.0 + 0.06 * (Main.I.run.level - 1)) * size


## Сбит враг (Main сообщает): «Штурмовой заход» III продлевается за наземные цели
func on_kill(e: Enemy) -> void:
	if mastery and cls_id == "attacker" and e.is_ground: # «Штурмовка»
		s3_cd = maxf(0.0, s3_cd - 1.0)
	if has_perk("f_tail2") and on_tail() and tail_target == e:
		roll_cd = maxf(0.0, roll_cd - 1.0)
		ab_cd = maxf(0.0, ab_cd - 1.0)
		s3_cd = maxf(0.0, s3_cd - 1.0)
		sb_cd = maxf(0.0, sb_cd - 1.0)
	if assault_t > 0.0 and e.is_ground and lvl_of("assault") >= 3 and _assault_ext < 3.0:
		assault_t += 0.5
		_assault_ext += 0.5


## Мастерство класса: множитель урона по цели (src — источник урона, как в статистике)
func mastery_k(e: Enemy, src: String) -> float:
	if not mastery:
		return 1.0
	match cls_id:
		"fighter":
			if src == "ракеты В-В" and (e.is_boss or e is RivalAce or e is Interceptor):
				return PlaneClasses.MASTERY_K
		"attacker":
			if src == "НАР" and e.is_ground:
				return PlaneClasses.MASTERY_K
	return 1.0


## «Выжженная земля»: запчасти за наземную цель, добитую бомбами или огнём
func mastery_parts_k(e: Enemy) -> float:
	if mastery and cls_id == "bomber" and e.is_ground and e.last_src in ["бомбы", PlaneClasses.MASTERY_FIRE_SRC]:
		return PlaneClasses.MASTERY_K
	return 1.0


func throttle_cut_on() -> bool:
	return flight.throttle_cut_on()


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
	Events.near_miss.emit(&"bullet" if kind == "пуля" else &"missile")


const GUN_LIFE := 0.8 # 3.1: дальность курсового +33% (было 0,6 с полёта пули)


func gun_range() -> float:
	return guns.gun_range()


func gun_damage() -> float:
	return guns.gun_damage()


func gun_rate() -> float:
	return guns.gun_rate()


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


## 3.5 (правка 29): глубина нырка 0…1 — плавный спуск и подъём (по 40% времени нырка, без рывка)
## Правка 3.5-s4 (п. 19): нырок плавнее — спуск и подъём по кривой без рывков в начале и в конце
## (smootherstep), каждый — 45% длительности; тангаж — по скорости спуска, нос опускается и поднимается постепенно
const DIVE_EDGE := 0.45


static func _ss(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


static func _dss(x: float) -> float:   # производная _ss, нормирована к 1 в середине
	x = clampf(x, 0.0, 1.0)
	return 16.0 * x * x * (1.0 - x) * (1.0 - x)


func dive_k() -> float:
	if dive_t <= 0.0:
		return 0.0
	var dur := Tuning.g("dive_time")
	var edge := dur * DIVE_EDGE
	return _ss((dur - dive_t) / edge) * _ss(dive_t / edge)


## Тангаж в нырке: +1 нос вниз на спуске … −1 нос вверх на подъёме
func dive_pitch() -> float:
	if dive_t <= 0.0:
		return 0.0
	var dur := Tuning.g("dive_time")
	var edge := dur * DIVE_EDGE
	var gone := dur - dive_t
	if gone < edge:
		return _dss(gone / edge)
	if dive_t < edge:
		return -_dss(dive_t / edge)
	return 0.0


## В нырке пули и таран вражеских самолётов проходят выше; ПВО, ракеты и земля — бьют
func dodges(source: String, who: String) -> bool:
	return dive_t > 0.0 and who != "ПВО" and (source == "пули" or source == "таран")


func is_invulnerable() -> bool:
	return roll_inv > 0.0 or invuln > 0.0 or Main.I.god_mode


func heal(amount: float, src := "прочее") -> void:
	var before := hp
	hp = minf(max_hp, hp + amount)
	Main.I.stats_add_counter("healed", int(round(hp - before)))
	Main.I.tele.add("heal_" + src, hp - before)   # EX-10: откуда приходит ремонт


func damage(amount: float, source := "прочее", who := "") -> void:
	if is_invulnerable() or hp <= 0.0:
		return
	if dodges(source, who):
		return
	amount *= Campaign.k("dmg") # U-05: урон врагов по сложности операции
	amount *= Spawner.dmg_ramp(Main.I.run_time) # правка 3.5-s4: поздний бой опаснее
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
		heal(max_hp * 0.2, "perk")
		Main.I.fx.text(global_position + Vector2(0, -60), "Второе дыхание!", Color(0.6, 1.0, 0.7))
		invuln = 2.0
		Events.player_damaged.emit(amount)
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
	Events.player_damaged.emit(amount)
	if hp <= 0.0 and OS.is_debug_build() and Main.I._args.has("--nodie"):
		hp = 1.0   # EX-10: долгий тест живучести — смерть считается, вылет идёт дальше
		Main.I.tele.add("nodie", 1)
		return
	if hp <= 0.0:
		hp = 0.0
		visible = false
		for w in wingmen:
			if is_instance_valid(w):
				w.queue_free()
		wingmen.clear()
		Events.player_died.emit()


## «Каток»: кольцо НАР во все стороны
func roller_ring(n: int) -> void:
	skills.roller_ring(n)


## «Зеркало»: веер из 6 ловушек на бочке — каждая уводит ракету в 300 пикс.
## 3.5 (правки 12, 26): «Кит» на «Пробеле» отстреливает веер тепловых ловушек.
## Все вражеские ракеты рядом уходят на ловушки и рвутся возле них, дальние теряют захват. Неуязвимости нет.
const SALVO_R := 420.0


func _draw() -> void:
	drawer._draw()


func has_perk(id: String) -> bool:
	return Profile.has_perk(cls_id, id)


## 3.5: самолёт ур. 2 выбирается в ангаре до вылета (Profile.apply); в вылете модернизации нет
func check_upgrade() -> void:
	pass

