class_name Hardpoint
extends RefCounted
## Группа подвесов: одно оружие на все точки группы, один приоритет целей.
## Логика стрельбы каждого вида оружия — здесь.

var name := ""
var slots := 1
var weapon := ""      # "" — пустая группа
var level := 1
var priority := "nearest"
var builtin := false  # встроенные турели: оружие не меняется
var heavy := false    # U-06: тяжёлый подвес самолёта ур. 2 — только экспериментальное оружие
## PG-01: where a wing pair hangs along the half-span (0 — by group index, as before)
var mount_frac := 0.0
var cd := 1.5
var bonus := 0.0         # бонус урона от редкости карточек улучшения
var trigger := "auto"    # для НАР и бомб: "auto" — сами, "button" — по кнопке (ПКМ / LT)
var evo := false         # 3.1: эволюция (оружие ур. 5 + катализатор)
var evo_plus := 0        # «Э+» из резерва: +8% урона, −4% перезарядки
var branch := ""         # S9-15: ветка мастерства с 35-го уровня — "rate" («Скорострел») или "power" («Калибр»); вторая закрыта
var branch_rank := 0
## PG-06: weapon profile chosen at the fork (`WeaponProfiles`), "" before the fork or for weapons without one
var profile := ""
var _side := 1.0
var _icd := 0.0          # турели: перехват ракет (зонтик, «Дикобраз», нашивка)
var _barrel := 0
## правка 3.5-s4 (п. 13): турель поворачивается к цели с ограниченной скоростью и стреляет, только когда
## навелась; aim — куда смотрят стволы (угол в мире, NAN — ещё не навели), 3D берёт его же
var aim := NAN
## правка 3.5-s4 (п. 27): где на крыле висят ракеты (смещения в осях самолёта, считает 3D) — пуск оттуда
var launch_offs: Array = []
var _aim_t: Enemy = null
var _aim_scan := 0.0
const TURRET_TRAVERSE := 150.0   # °/с; «Сервоприводы» — +25% за уровень
const TURRET_GATE := 0.09        # рад — стреляет, когда стволы смотрят на цель точнее
const TURRET_INTERCEPT := 0.55   # тест 3.5-s7 (Kanta): турели сбивают ракету в 55% случаев (одна попытка на ракету)
var _charge := 0.0       # рельсотрон: идёт зарядка
## тест 3.5-s7: бомбы вручную — пока зажата кнопка (ПКМ / LT / K), на земле прицел; отпустил — сброс
var aiming := false
const RAIL_CHARGE := 0.9


func _init(p_name: String, p_slots: int, p_weapon: String, p_builtin := false) -> void:
	name = p_name
	slots = p_slots
	weapon = p_weapon
	builtin = p_builtin
	cd = randf_range(0.5, 1.5)


func is_empty() -> bool:
	return weapon == ""


func label() -> String:
	if is_empty():
		return "%s: пусто%s" % [name, " (экспериментальное оружие)" if heavy else ""]
	var s := "%s ×%d: %s ур. %d" % [name, slots, Weapons.DEFS[weapon]["short"], level]
	if evo:
		s = "%s ×%d: %s (Э%s)" % [name, slots, evo_title(), ("+%d" % evo_plus) if evo_plus > 0 else ""]
	if bonus > 0.0:
		s += " (+%d%%)" % int(round(bonus * 100.0))
	if profile != "":
		s += " · %s" % WeaponProfiles.def(weapon, profile).get("title", profile)
	if branch != "":
		s += " · %s %d" % [Cards.branch_def(weapon, branch)["title"], branch_rank]
	if uses_trigger() and trigger == "button":
		s += " [прав. кн. мыши]"
	return s


func uses_trigger() -> bool:
	return not is_empty() and Weapons.DEFS[weapon].get("uses_trigger", false)


func dmg() -> float:
	return _dmg() * branch_dmg_k() * WeaponProfiles.k(weapon, profile, "dmg")


## PG-06: definition of the chosen profile (empty without one) — behaviour keys for the firing code
func prof() -> Dictionary:
	return WeaponProfiles.def(weapon, profile)


## S9-15: «Калибр» — +18% урона за ранг, «Скорострел» — −10% перезарядки за ранг (до 5 рангов)
func branch_dmg_k() -> float:
	return 1.0 + 0.18 * branch_rank if branch == "power" and not Cards.BRANCHES_W.has(weapon) else 1.0


func branch_cd_k() -> float:
	return pow(0.9, branch_rank) if branch == "rate" else 1.0


func _dmg() -> float:
	var base: float = Weapons.DEFS[weapon]["dmg"] * (1.0 + bonus) * _owner_k()
	if evo:
		var ek := (1.0 + bonus) * _owner_k() * (1.0 + 0.08 * evo_plus) * _evo_k("dmg")
		match weapon:
			"aam":
				return 120.0 * ek # «Шмель»: тяжёлая ракета; при попадании ещё 4 БЧ по 40
			"rockets":
				return 22.0 * ek
			"gunpod":
				return 7.0 * ek
			"bombs":
				return CARPET_DMG * ek
			"turret":
				return Weapons.DEFS["turret"]["dmg"] * (1.0 + 0.15 * (level - 1)) * ek
	match weapon:
		"turret":
			return base * (1.0 + 0.15 * (level - 1))
		"railgun":
			return base * (1.0 + 0.3 * (level - 1))
		"rockets": # 3.5: залп фиксирован, уровень — урон и радиус
			return base * (1.0 + Tuning.g("rocket_lvl_dmg") * (level - 1))
		"aam": # 3.5: всегда 1 ракета с точки; ур. 4 вместо второй — урон и скорость
			return base * (1.0 + Tuning.g("aam_lvl_dmg") * (level - 1)) * (1.0 + Tuning.g("aam_l4_dmg") if level >= 4 else 1.0)
		"srm", "agm", "hebomb":   # PG-01: growth in WeaponBalance
			return base * WeaponBalance.dmg_k(weapon, level)
		_:
			return base * (1.0 + 0.25 * (level - 1))


const MSL_CD_MIN := {"aam": 3.0, "rockets": 1.8}
## Hardpoint missiles: missile modules («Боевая часть», «Двигатели ракет», «Пусковое устройство») and
## crew missile damage act on them (PG-01 adds `srm`, `agm`)
const MISSILES := ["aam", "rockets", "srm", "agm"]


func reload_time(p: Player) -> float:
	var base: float = Weapons.DEFS[weapon]["cd"]
	var k := 1.0
	if evo:
		match weapon:
			"aam":
				base = 4.5
			"rockets":
				base = 3.5
			"gunpod":
				base = 0.12
			"bombs":
				base = 4.0
		k *= pow(0.96, evo_plus) * _evo_k("cd")
	match weapon:
		"aam":
			if not evo:
				k *= 1.0 - 0.1 * (level - 1)
		"flares":
			k *= pow(0.9, level - 1) * float(p.mods.get("flare_cd", 1.0))   # medal «Ловец ракет»
		"railgun", "emp", "laser", "plasma":
			k *= pow(0.92, level - 1)
		"bombs":
			if not evo:
				k *= 1.0 - 0.08 * (level - 1)
		"srm", "agm", "hebomb":
			k *= WeaponBalance.cd_k(weapon, level)
		"gunpod", "turret":
			if not (evo and weapon == "gunpod"):
				k *= 1.0 / (1.0 + 0.1 * (level - 1))
			k /= p.mods["servo_rate"]
	if weapon == "turret":
		if p.carpet_t > 0.0:
			k *= 0.5 # «Огненный ковёр»: турели в два раза чаще, пока действует
		if p.umbrella_t > 0.0:
			k *= 0.5 # «Зенитный зонтик»
	elif p.assault_t > 0.0 and not builtin:
		k /= 3.0 # «Штурмовой заход»: подвесы перезаряжаются втрое быстрее
	if weapon == "turret":
		k /= float(p.mods.get("turret_rate", 1.0))
	if weapon in MISSILES:
		k *= float(p.mods.get("msl_cd", 1.0)) # модуль «Пусковое устройство»
	k *= WeaponProfiles.k(weapon, profile, "cd")   # PG-06
	var t: float = base * k * p.mods["hp_cd"] * Profile.wk(weapon, "cd") * branch_cd_k()
	if MSL_CD_MIN.has(weapon):
		# правка 3.5-s4 (лог «Осы»: до 59 ракет в воздухе): карточки перезарядки складывались до ×0,07 —
		# ракеты шли без перерыва. Нижний предел; «Штурмовой заход» по-прежнему ускоряет втрое
		t = maxf(t, float(MSL_CD_MIN[weapon]) * branch_cd_k() / (3.0 if p.assault_t > 0.0 and not builtin else 1.0))
	elif WeaponBalance.cd_floor(weapon) > 0.0:
		t = maxf(t, WeaponBalance.cd_floor(weapon) * branch_cd_k() / (3.0 if p.assault_t > 0.0 and not builtin else 1.0))
	return t


## U-07: множитель модернизации от ступени 3 ветки (только самолёт ур. 2)
func _evo_k(key: String) -> float:
	var p := Main.I.player if Main.I != null else null
	if not evo or p == null:
		return 1.0
	return Profile.evo_k(weapon, key, p.plane_lvl)


func evo_title() -> String:
	var p := Main.I.player if Main.I != null else null
	var v := Profile.evo_variant(weapon, p.plane_lvl if p != null else 1)
	return String(Prog.EVOS[weapon]["title"]) + ("" if v == "" else " · " + v)


## Множители урона от класса самолёта и связок (2.8)
func _owner_k() -> float:
	var p := Main.I.player if Main.I != null else null
	if p == null:
		return 1.0
	var k := 1.0
	if weapon == "turret":
		k *= float(p.cls.get("turret_k", 1.0))
	if weapon == "turret":
		k *= float(p.mods.get("turret_dmg", 1.0))
	if weapon in MISSILES:
		k *= p.missile_k()
	k *= float((p.cls.get("bonus", {}) as Dictionary).get(weapon, 1.0))   # ★ class bonus and plane extras (Kanta 24.10)
	return k * (1.0 + float(p.mods.get("hp_dmg", 0.0)))


func range_px() -> float:
	var base: float = Weapons.DEFS[weapon]["range"] * _evo_k("range") * WeaponProfiles.k(weapon, profile, "range")   # PG-06
	var p := Main.I.player if Main.I != null else null
	if p != null:
		if weapon == "turret":
			base *= float(p.cls.get("turret_range_k", 1.0))
			if p.umbrella_t > 0.0:
				base *= 1.3
			if evo:
				base *= 1.4
		if weapon == "gunpod" or weapon == "turret":
			base *= p.mods["servo_range"]
		base *= Profile.wk(weapon, "range")
		if weapon == "aam":
			base *= float(p.mods.get("msl_lock", 1.0)) # «Двигатели ракет»: дальность захвата
		if evo and weapon == "gunpod":
			return 520.0 * p.mods["servo_range"] * _evo_k("range")
		if evo and weapon == "flares":
			return 360.0 * _evo_k("range")
	if weapon in ["flares", "emp"] and branch == "power":
		base *= 1.0 + 0.1 * branch_rank   # S10-09: «Яркие ловушки»; ЭМИ: «Расширенный импульс» (Kanta 25.10)
	match weapon:
		"flares", "emp", "laser", "plasma":
			return base * (1.0 + 0.08 * (level - 1))
		"gunpod", "bombs":
			return base * (1.0 + 0.1 * (level - 1))
		"srm", "agm", "hebomb":
			return base * WeaponBalance.range_k(weapon, level)
	return base


func update(delta: float, p: Player) -> void:
	if is_empty():
		return
	if weapon == "turret":
		_turret_aim(delta, p)
		_turret_intercept(delta, p)
		if p.syn.has("hedgehog"):
			_hedgehog(delta, p)
	if weapon == "railgun":
		_railgun(delta, p)
		return
	# мастерство «Охотник»: на хвосте у врага ракеты В-В перезаряжаются вдвое быстрее
	cd -= delta * (2.0 if weapon == "aam" and p.mastery and p.cls_id == "fighter" and p.on_tail() else 1.0)
	if Weapons.is_bomb(weapon) and _bomb_aim(p):
		return
	if cd > 0.0:
		return
	var manual := uses_trigger() and trigger == "button"
	if manual and not Input.is_action_pressed("fire_hardpoint"):
		return
	var fired := false
	match weapon:
		"aam":
			fired = _fire_aam(p)
		"rockets":
			fired = _fire_rockets(p, manual)
		"gunpod", "turret":
			fired = _fire_gun(p)
		"flares":
			fired = _fire_flares(p)
		"bombs":
			fired = _fire_bombs(p, manual)
		"srm":
			fired = WeaponFire.fire_srm(self, p)
		"agm":
			fired = WeaponFire.fire_agm(self, p)
		"hebomb":
			fired = WeaponFire.fire_hebomb(self, p, manual)
		"emp":
			fired = _fire_emp(p)
		"laser":
			fired = _fire_laser(p)
		"plasma":
			fired = _fire_plasma(p)
	if fired and not manual and Weapons.is_bomb(weapon):
		Hints.show("bomb_auto", "Бомбы падают сами на наземные цели рядом. Бросать вручную с прицелом: в паузе (Tab) переключите бомбы на «Пуск: правой кнопкой мыши».", 8.0, 2)
	if fired and not manual and weapon in MISSILES:
		Hints.show("auto_launch", "Ракеты и бомбы пускаются сами, когда враг рядом или впереди. Пускать вручную правой кнопкой мыши — в паузе (Tab).", 8.0, 2)
	# 3.4: после выстрела переносим опоздание (до 0,05 с) — темп меньше зависит от FPS
	cd = (minf(0.0, maxf(cd, -0.05)) + reload_time(p)) if fired else 0.2
	if _quick:
		_quick = false
		cd = 0.2


## Тест 3.5-s7 (предложение Kanta): бомбы по кнопке — зажал, на земле виден прицел (лежит по рельефу,
## render3d._sync_ground_zones), отпустил — сброс туда. Kanta 20.10 (BM-02): прицел и сброс по кнопке — только
## в режиме «по кнопке»; при «авто» бомбы падают сами, ПКМ прицел не показывает.
## true — авто-сброс в этот кадр не нужен.
func _bomb_aim(p: Player) -> bool:
	if trigger != "button":
		aiming = false
		return false
	if Input.is_action_pressed("fire_hardpoint"):
		if not aiming:
			Hints.show("bomb_aim", "Прицел бомб: держите правую кнопку мыши и ведите прицел, отпустите — бомбы сброшены. Серый прицел — бомбы ещё перезаряжаются.", 8.0, 2)
		aiming = true
		return true
	if aiming:
		aiming = false
		if cd <= 0.0 and (_fire_bombs(p, true) if weapon == "bombs" else WeaponFire.fire_hebomb(self, p, true)):
			cd = reload_time(p)
		return true
	return true


## Куда упадут бомбы по кнопке: к курсору (схема «мышью»), иначе вперёд по курсу
func aim_point(p: Player) -> Vector2:
	if int(Tuning.g("scheme")) == 2 and Render3D.I != null:
		var mp := Render3D.I.mouse_world(p.get_global_mouse_position())
		return p.global_position + (mp - p.global_position).limit_length(460.0)
	return p.global_position + Vector2.from_angle(p.heading) * 300.0


## Зоны прицела бомб на плоскости боя: [начало, конец, радиус] (круг — начало и конец совпадают)
func aim_zones(p: Player) -> Array:
	var aoe_k := Main.I.projectiles.aoe_r_k()
	if evo:
		var c := p.global_position + Vector2.from_angle(p.heading) * 220.0 + p.velocity * 0.4   # как в _fire_carpet_row по кнопке
		var side := Vector2.from_angle(p.heading + PI / 2.0) * 300.0
		return [[c - side, c + side, CARPET_R * Profile.wk("bombs", "blast_r") * aoe_k]]
	var to := aim_point(p)
	return [[to, to, range_px() * Profile.wk(weapon, "blast_r") * aoe_k]]


## U-08: рельсотрон — цель по носу (конус ±8°) → зарядка RAIL_CHARGE с прицельной линией → пробивающий выстрел
func _railgun(delta: float, p: Player) -> void:
	var fwd := Vector2.from_angle(p.heading)
	var L := range_px()
	if _charge > 0.0:
		_charge -= delta
		Main.I.fx.beam(p.global_position, p.global_position + fwd * L, Color(0.55, 0.85, 1.0, 0.18 + 0.4 * (1.0 - _charge / RAIL_CHARGE)), 1.5, 0.03)
		if _charge <= 0.0:
			# прицел по носу с допуском ±12°: луч идёт на цель в этом конусе (иначе за 0,9 с зарядки цель уходит с линии)
			var best := 12.0
			for n in p.get_tree().get_nodes_in_group("enemies"):
				var e := n as Enemy
				if e == null or e.hp <= 0.0:
					continue
				var to := e.global_position - p.global_position
				var off := rad_to_deg(absf(wrapf(to.angle() - p.heading, -PI, PI)))
				if to.length() < L and off < best:
					best = off
					fwd = to.normalized()
			_rail_shot(p, fwd, L)
			cd = reload_time(p)
		return
	cd -= delta
	if cd > 0.0:
		return
	for n in p.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var to := e.global_position - p.global_position
		if to.length() < L and absf(wrapf(to.angle() - p.heading, -PI, PI)) < deg_to_rad(8.0):
			_charge = RAIL_CHARGE
			Main.I.sfx.play("lock", -10.0, 0.7)
			return
	cd = 0.2


func _rail_shot(p: Player, fwd: Vector2, L: float) -> void:
	var a := p.global_position
	var dmg_v := dmg()
	var hits := 0
	for n in p.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var to := e.global_position - a
		var t := to.dot(fwd)
		if t < 0.0 or t > L:
			continue
		if absf(to.cross(fwd)) < e.radius + 24.0:
			e.take_hit(dmg_v, "рельсотрон")
			Main.I.fx.hit_spark(e.global_position, Color(0.6, 0.9, 1.0))
			hits += 1
	Main.I.fx.beam(a, a + fwd * L, Color(0.75, 0.92, 1.0, 0.95), 7.0, 0.3)
	Main.I.fx.beam(a, a + fwd * L, Color(1, 1, 1, 0.9), 2.0, 0.2)
	Main.I.sfx.play("pass_hit", -6.0, 0.6)
	Main.I.add_shake(4.0 if hits > 0 else 2.0)
	if Main.I._autotest and not Main.I.counters.has("rail_shots"):
		print("AUTOTEST: railgun shot at %.0f s, hits %d, dmg %.0f" % [Main.I.run_time, hits, dmg_v])
	Main.I.stats_add_counter("rail_shots", 1)


## U-08: ЭМИ-заряд — когда рядом 3+ врага или вражеская ракета. Дроны падают, остальные молчат 3 с
## (асы и «Крепость» — 1 с и половина урона), вражеские ракеты теряют цель.
const EMP_DRONE_K := 5.0


func _fire_emp(p: Player) -> bool:
	var r := range_px()
	var pos := p.global_position
	var near: Array = []
	for n in p.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e.hp > 0.0 and pos.distance_to(e.global_position) - e.radius < r:
			near.append(e)
	var msl := 0
	for m in Main.I.projectiles.missiles:
		if not m.get("lost", false) and pos.distance_to(m["p"]) < r:
			msl += 1
	if near.size() < 3 and msl == 0:
		return false
	var d := dmg()
	for e: Enemy in near:
		if e is Drone and not e.is_boss:
			# тест 3.5-s7 (Kanta, «бери в работу»): дроны больше не падают сразу при любой прочности
			# (ЭМИ давал 10% урона «Грача») — урон по ним ×EMP_DRONE_K
			e.take_hit(d * EMP_DRONE_K, "ЭМИ")
		elif e.is_boss:
			e.take_hit(d * 0.5, "ЭМИ")
			e.silence = maxf(e.silence, 1.0)
		else:
			e.take_hit(d, "ЭМИ")
			e.silence = maxf(e.silence, 3.0)
	Main.I.projectiles.break_locks(pos, r)
	Main.I.fx.emp_wave(pos, r, near)   # тест 3.5-s7: волна и молнии к заглушённым врагам
	Hints.show("emp", "ЭМИ-заряд срабатывает сам, когда в голубом круге вокруг вас 3 врага или вражеская ракета: дроны падают, остальные враги на время глохнут, ракеты теряют цель.", 9.0, 2)
	Main.I.sfx.play("shield_break", -6.0, 0.7)
	if Main.I._autotest and not Main.I.counters.has("emp_pulses"):
		print("AUTOTEST: emp pulse at %.0f s, enemies %d, missiles %d" % [Main.I.run_time, near.size(), msl])
	Main.I.stats_add_counter("emp_pulses", 1)
	return true


## U-08: лазер «Луч» — сжигает до 2 ракет и 2 пуль в радиусе, иначе слабо бьёт ближайшего врага
func _fire_laser(p: Player) -> bool:
	var r := range_px()
	var pos := p.global_position
	var n := 0
	for i in 2:
		if Main.I.projectiles.intercept_missile(pos, r):
			n += 1
	var b := 0
	for eb in Main.I.projectiles.ebullets:
		if pos.distance_to(eb["p"]) < r:
			b += 1
	if b > 0:
		# по одной ближайшей пуле за выстрел, до трёх
		for i in mini(2, b):
			var best := -1
			var bd := r
			for j in Main.I.projectiles.ebullets.size():
				var d := pos.distance_to(Main.I.projectiles.ebullets[j]["p"])
				if d < bd:
					bd = d
					best = j
			if best >= 0:
				Main.I.fx.beam(pos, Main.I.projectiles.ebullets[best]["p"], Color(1.0, 0.35, 0.3, 0.9), 2.0, 0.1)
				Main.I.projectiles.ebullets.remove_at(best)
				n += 1
	if n > 0:
		Main.I.stats_add_counter("laser_burned", n)
		return true
	var t := Weapons.pick_target(pos, r, "nearest")
	if t == null:
		return false
	t.take_hit(dmg(), "лазер")
	Main.I.fx.beam(pos, t.global_position, Color(1.0, 0.35, 0.3, 0.8), 2.5, 0.12)
	return true


## U-08: плазменная бомба — шар плазмы на наземной цели в радиусе 600 (жжёт только землю)
## S10-12 (Kanta: «часто промахивается»): раньше шар вставал там, где цель была в момент пуска, и движущаяся
## техника выезжала из него. Теперь бомба летит PLASMA_FUSE с, точка — с упреждением по скорости цели, и
## выбирается цель, рядом с которой больше всего наземных врагов (на ту же минуту упреждения)
## S10-08: бомба падает до земли и рвётся на рельефе (Boom3D «plasma»), а не кольцом в воздухе
const PLASMA_FUSE := 0.6


func _fire_plasma(p: Player) -> bool:
	var ground: Array = []
	for nd in p.get_tree().get_nodes_in_group("enemies"):
		var e := nd as Enemy
		if e != null and e.hp > 0.0 and e.is_ground:
			ground.append([e, e.global_position + e.move_vel * PLASMA_FUSE])
	var r := range_px()
	var best := Vector2.INF
	var best_n := 0
	var best_d := INF
	for c in ground:
		var at: Vector2 = c[1]
		var d := p.global_position.distance_to(at)
		if d > 600.0:
			continue
		var n := 0
		for o in ground:
			if at.distance_to(o[1]) < r * 0.8 + (o[0] as Enemy).radius:
				n += 1
		if n > best_n or (n == best_n and d < best_d):
			best_n = n
			best_d = d
			best = at
	if best_n == 0:
		return false
	Main.I.projectiles.spawn_bomb(p.global_position, PLASMA_FUSE, 0.0, r, "плазма", best, true)
	Main.I.projectiles.bombs.back()["plasma"] = {"dps": dmg(), "t": 4.0}
	Main.I.sfx.play("bomb_drop", -10.0, 0.7)
	return true


## Турели сбивают ракеты: «Зенитный зонтик» (раз в 0,5 с), «Дикобраз» (1,5 с), нашивка «Турели II» (3 с)
func _turret_intercept(delta: float, p: Player) -> void:
	var iv := INF
	if p.umbrella_t > 0.0:
		iv = 0.5
	if evo:
		iv = minf(iv, 1.5)
	if p.syn.has("hedgehog"):
		iv = minf(iv, 3.0) # «Стальной ёж»
	if p.has_perk("b_aa2"):
		iv = minf(iv, 4.0) # перк «Заградогонь»
	if iv == INF:
		return
	_icd -= delta
	if _icd > 0.0:
		return
	var r := 300.0 if p.umbrella_t > 0.0 else range_px() * 0.75
	var n := 0
	var tried := 0
	for s in slots:
		var res := Main.I.projectiles.flak_missile(p.global_position, r, TURRET_INTERCEPT)
		if res < 0:
			break
		tried += 1
		n += res
	if p.umbrella_t > 0.0 and p.lvl_of("umbrella") >= 2:
		var nb := Main.I.projectiles.intercept_bullets(p.global_position, 180.0)
		n += nb
		tried += nb
	if n > 0:
		Main.I.stats_add_counter("intercepted_turrets", n)
	if tried > 0:
		_icd = iv
	else:
		_icd = 0.1


var _hh_cd := 5.0
var _quick := false
var _salvo_n := 0
var _gun_n := 0


## «Стальной ёж»: раз в 5 с каждая турель — 3 мини-ракеты по разным целям
func _hedgehog(delta: float, p: Player) -> void:
	_hh_cd -= delta
	if _hh_cd > 0.0:
		return
	var skip: Array = []
	var targets: Array = []
	for i in slots * 3:
		var t := Weapons.pick_target(p.global_position, 900.0, "nearest", skip)
		if t == null:
			break
		targets.append(t)
		skip.append(t)
	if targets.is_empty():
		_hh_cd = 0.3
		return
	_hh_cd = 5.0
	for i in slots * 3:
		var t2: Enemy = targets[i % targets.size()]
		Main.I.projectiles.spawn_player_missile(p.global_position, p.velocity + Vector2.from_angle(TAU * i / (slots * 3.0)) * 260.0, t2,
			22.0 * _owner_k(), "связка: стальной ёж", {"splash": 45.0, "tint": Color(0.4, 0.95, 0.9)})
	Main.I.sfx.play("aam_launch", -12.0, 1.8)


## «Волчья стая»: ведомые повторяют пуск по той же цели
func _wolf(p: Player, t: Enemy, d: float) -> void:
	if not p.syn.has("wolfpack") or t == null:
		return
	for w in p.wingmen:
		var wm: Wingman = w
		if wm.alive():
			wm.mirror_launch(t, d * 0.6)


## Where shot `i` of this group leaves the plane (world) — for `WeaponFire`
func slot_pos(p: Player, i: int) -> Vector2:
	return _slot_pos(p, i)


func _slot_pos(p: Player, i: int) -> Vector2:
	if (Weapons.leaves_pylon(weapon) or weapon == "turret" or weapon == "gunpod") and not launch_offs.is_empty() and Render3D.enabled:
		return p.global_position + (launch_offs[i % launch_offs.size()] as Vector2).rotated(p.heading)
	if slots == 1:
		return p.global_position
	var side := -1.0 if i % 2 == 0 else 1.0
	return p.global_position + Vector2.from_angle(p.heading + PI / 2.0) * 12.0 * p.size * side


func _fire_aam(p: Player) -> bool:
	# 3.5: качество вместо количества — всегда 1 ракета с точки (ур. 4 усиливает ракету, а не добавляет вторую)
	var per_slot := int(prof().get("per_slot", 1))   # PG-06 «Двойной пуск»: two light missiles per slot
	if evo:
		per_slot = maxi(1, 2 / slots) # «Шмель»: 2 тяжёлые ракеты, каждая делится на 4 БЧ
	var hunter := int(p.taken.get("seeker", 0)) >= 3 # «ГСН» ×3: и по наземным
	var targets: Array = []
	var skip: Array = []
	for i in slots * per_slot:
		var t := Weapons.pick_target(p.global_position, range_px(), priority if hunter else ("nearest" if priority == "ground" else priority), skip, not hunter, false, true)
		if t == null:
			break
		targets.append(t)
		skip.append(t)
	if targets.is_empty():
		return false
	var n := slots * per_slot
	for i in n:
		var t: Enemy = targets[i % targets.size()]
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := _slot_pos(p, i)
		var vel := p.velocity + Vector2.from_angle(p.heading + side * 0.2) * 150.0   # S10-05: сход вперёд по курсу
		var opts := {}
		if evo:
			opts = {"split": 4, "split_dmg": 40.0 * (1.0 + bonus) * _owner_k() * (1.0 + 0.08 * evo_plus), "big": true}
		if hunter:
			opts["ground_k"] = 1.5
		if p.syn.has("carousel"):
			opts["carousel"] = 0
		var md := dmg() * Profile.wk("aam", "dmg")
		opts["spd_k"] = Profile.wk("aam", "spd") * (1.2 if level >= 4 and not evo else 1.0) * WeaponProfiles.k("aam", profile, "spd")
		if prof().has("splash"):   # PG-06 «Осколочная»: wider burst, neighbours take more
			opts["splash"] = float(prof()["splash"])
			opts["splash_k"] = float(prof()["splash_k"])
		Main.I.projectiles.spawn_player_missile(pos, vel, t, md, "ракеты В-В", opts)
		if Boom3D.active():
			Boom3D.ensure().launch(pos, Vector2.from_angle(p.heading), p.velocity)
		if i < slots:
			_wolf(p, t, md)
	Main.I.sfx.play("aam_launch", -16.0, 1.4)
	return true


func _fire_rockets(p: Player, manual := false) -> bool:
	# Авто: залп, только когда цель точно перед носом (узкий конус) и близко — меньше промахов
	var fwd := Vector2.from_angle(p.heading)
	var ok := manual or p.assault_t > 0.0 # «Штурмовой заход»: без прицеливания
	var cone := deg_to_rad(25.0 if evo else 10.0) * (1.3 if Profile.wbranch("rockets", 1) == "b" else 1.0)
	for n in Main.I.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.hp <= 0.0:
			continue
		var to := e.global_position - p.global_position
		if ok:
			break
		if to.length() < (700.0 if evo else 620.0) * Profile.wk("rockets", "auto_r") * float(p.mods.get("msl_lock", 1.0)) and absf(fwd.angle_to(to)) < cone + atan2(e.radius, to.length()):
			ok = true
			break
	if not ok:
		return false
	# S6-02 (решение Kanta 18.10): залп 4 с точки на ур. 1–2, 5 на ур. 3–4, 6 на ур. 5; уровень даёт ещё урон и радиус
	var per_slot := 4 if level <= 2 else (5 if level <= 4 else 6)
	# PG-06 profiles: «Веер» adds rockets and widens the cone, «Кумулятив» fires three heavy ones
	var pd := prof()
	per_slot = int(pd.get("count", per_slot + int(pd.get("extra", 0))))
	var half_spread := float(pd.get("spread", 4.5))
	var splash := 60.0 * (1.0 + Tuning.g("rocket_lvl_r") * (level - 1))
	var dirs := [0.0]
	if evo: # «Ливень»: веер в 3 стороны по 5 ракет
		per_slot = 5
		splash = 70.0
		dirs = [-deg_to_rad(25.0), 0.0, deg_to_rad(25.0)]
	var rd := dmg() * Profile.wk("rockets", "dmg")
	var rs := Profile.wk("rockets", "spd") * float(p.mods.get("missile_spd", 1.0))
	if p.mods.has("msl_boost"):
		rd *= float(p.mods["msl_boost"]) # «Форсированный старт»: НАР летит меньше секунды
	splash *= float(p.mods.get("msl_r", 1.0))
	_salvo_n += 1
	if p.syn.has("salvo") and _salvo_n % 3 == 0:
		_wall(p, fwd, rd)
		Main.I.sfx.play("rocket_launch", -10.0, 1.4)
		return true
	var ropts := {"sticky": true, "src": "связка: термобарика"} if p.syn.has("thermobaric") else {}
	ropts["ground_k"] = ROCKET_GROUND_K
	if pd.get("ap", false):
		ropts["armor_k"] = Enemy.DEF_K["armor"]["ap"]   # «Кумулятив»: armor as the guided air-to-ground missile
	if pd.get("burn", false):
		ropts["burn"] = true   # «Зажигательные»: incendiary ammo rules on every hit
	_wolf(p, Weapons.pick_target(p.global_position + fwd * 300.0, 500.0, "nearest"), rd * 3.0)
	if p.assault_t > 0.0 and p.syn.has("s_conveyor"):
		per_slot *= 2 # «Конвейер»
	for s in slots:
		for d0 in dirs:
			for i in per_slot:
				var spread := deg_to_rad(randf_range(-half_spread, half_spread)) + float(d0)
				var dir := fwd.rotated(spread)
				var pos := _slot_pos(p, s) + dir * 10.0
				Main.I.projectiles.spawn_rocket(pos, p.velocity + dir * randf_range(820.0, 980.0) * rs, rd, splash * Profile.wk("rockets", "blast_r"), i * 0.04, ropts)
	Main.I.sfx.play("rocket_launch", -14.0, 1.8)
	return true


## «Огненный вал»: три линии по 5 взрывов в 250 / 450 / 650 пикс. впереди, ширина 420
func _wall(p: Player, fwd: Vector2, d: float) -> void:
	var side := Vector2(-fwd.y, fwd.x)
	var spd := 900.0
	for li in 3:
		var dist := 250.0 + 200.0 * li
		for j in 5:
			var off := (float(j) / 4.0 - 0.5) * 420.0
			var target := p.global_position + fwd * dist + side * off
			var v := (target - p.global_position).normalized() * spd
			Main.I.projectiles.spawn_rocket(p.global_position + side * off * 0.1, p.velocity * 0.3 + v, d * 1.3, 70.0, 0.03 * j + 0.06 * li,
				{"life": p.global_position.distance_to(target) / spd, "src": "связка: огненный вал"})


func has_aim_target() -> bool:
	return not is_nan(aim) and is_instance_valid(_aim_t) and _aim_t.hp > 0.0


func _turret_aim(delta: float, p: Player) -> void:
	if is_nan(aim):
		aim = p.heading
	_aim_scan -= delta
	if _aim_scan <= 0.0 or not is_instance_valid(_aim_t) or _aim_t.hp <= 0.0:
		_aim_scan = 0.15
		_aim_t = null
		if p.umbrella_t > 0.0:
			_aim_t = Weapons.pick_target(p.global_position, range_px(), priority, [], true)
		if _aim_t == null:
			_aim_t = Weapons.pick_target(p.global_position, range_px(), priority)
	var want := p.heading if _aim_t == null else (_aim_t.global_position - p.global_position).angle()
	aim = rotate_toward(aim, want, deg_to_rad(TURRET_TRAVERSE) * float(p.mods.get("turret_traverse", 1.0)) * delta)


func _fire_gun(p: Player) -> bool:
	if weapon == "turret":
		return _fire_turret(p)
	var t: Enemy = null
	if weapon == "turret" and p.umbrella_t > 0.0:
		t = Weapons.pick_target(p.global_position, range_px(), priority, [], true) # зонтик: сначала самолёты
	if t == null:
		t = Weapons.pick_target(p.global_position, range_px(), priority)
	if t == null:
		return false
	var pierce := 0
	if weapon == "gunpod" and p.syn.has("gunner"):
		pierce += 1
	if evo and weapon == "gunpod":
		pierce += 1
	var barrels := 2 if (evo and weapon == "turret") else 1
	for s in slots:
		for b in barrels:
			var pos := _slot_pos(p, s)
			if evo and weapon == "gunpod": # «Газонокосилка»: стволы поочерёдно
				_barrel += 1
				pos += Vector2.from_angle(p.heading + PI / 2.0) * (6.0 if _barrel % 2 == 0 else -6.0)
			if barrels > 1:
				pos += Vector2.from_angle(p.heading + PI / 2.0) * (5.0 if b == 0 else -5.0)
			var to := t.global_position - pos
			var spd := 1300.0 * Profile.wk(weapon, "spd")
			var dir := (t.global_position - pos).normalized().rotated(randf_range(-0.04, 0.04))
			var gd := dmg() * Profile.wk(weapon, "dmg")
			var he := 0.0
			if weapon == "gunpod" and p.syn.has("gunner"):
				_gun_n += 1
				if _gun_n % 6 == 0: # «Пушкарь»: фугасный снаряд
					gd *= 4.0
					he = 70.0
			Main.I.projectiles.spawn_player_bullet(pos, dir * spd + p.velocity * 0.5, gd, (to.length() + 60.0) / spd, false,
				"турели" if weapon == "turret" else "гондола", pierce, he)
	Main.I.sfx.play("turret_fire" if weapon == "turret" else "gunpod_fire", -21.0)
	return true


## Турель: огонь по цели, на которую уже наведены стволы (без мгновенного разворота)
func _fire_turret(p: Player) -> bool:
	var t := _aim_t
	if t == null or not is_instance_valid(t) or t.hp <= 0.0 or is_nan(aim):
		return false
	if absf(wrapf((t.global_position - p.global_position).angle() - aim, -PI, PI)) > TURRET_GATE:
		return false
	var barrels := 2 if evo else 1
	for s in slots:
		for b in barrels:
			var pos := _slot_pos(p, s)
			if barrels > 1:
				pos += Vector2.from_angle(aim + PI / 2.0) * (5.0 if b == 0 else -5.0)
			var to := t.global_position - pos
			var spd := 1300.0 * Profile.wk(weapon, "spd")
			# стволы смотрят по aim; поправка на место турели на крыле — к цели, но не больше зазора наведения
			var da := clampf(wrapf(to.angle() - aim, -PI, PI), -TURRET_GATE, TURRET_GATE)
			var dir := Vector2.from_angle(aim + da + randf_range(-0.03, 0.03))
			Main.I.projectiles.spawn_player_bullet(pos, dir * spd + p.velocity * 0.5, dmg() * Profile.wk(weapon, "dmg"),
				(to.length() + 60.0) / spd, false, "турели", 0, 0.0)
	Main.I.sfx.play("turret_fire", -21.0)
	return true


func _fire_flares(p: Player) -> bool:
	# 3.1: ослаблены — одна ракета за срабатывание (с ур. 4 — две), пули — с ур. 4 и в малом радиусе.
	# Видно как отстрел тепловых ловушек: ракета уходит на ловушку и рвётся рядом с ней.
	var killed := 0
	var r := range_px()
	var per := (2 if level >= 4 else 1) + (1 if evo else 0)
	var any := false
	for s in per:
		var mp = Main.I.projectiles.intercept_missile_at(p.global_position, r, true, 0.1 * branch_rank if branch == "power" else 0.0)
		if mp != null:
			killed += 1
			any = true
			if Profile.wbranch("flares", 2) == "a": # «Ловушка с подрывом»
				Main.I.projectiles.aoe(mp, 60.0, 20.0, "противоракеты")
			if evo: # «Салют»: перехват выпускает 3 ловушки по врагам
				var skip: Array = []
				for j in 3:
					var t := Weapons.pick_target(mp, 700.0, "nearest", skip)
					if t != null:
						skip.append(t)
					Main.I.projectiles.spawn_player_missile(mp, Vector2.from_angle(randf() * TAU) * 200.0, t, 25.0 * (1.0 + 0.08 * evo_plus) * _owner_k(), "противоракеты")
	if level >= 4 or evo:
		killed += Main.I.projectiles.intercept_bullets(p.global_position, 200.0 if evo else 90.0 + 15.0 * (level - 4))
	if killed > 0 and Profile.wbranch("flares", 2) == "b" and randf() < 0.2:
		_quick = true # «Запас ловушек»
	if killed > 0:
		Main.I.fx.flare_burst(p.global_position, p.heading, 8, p.velocity, 1.15)
		Main.I.stats_add_counter("intercepted", killed)
		Main.I.sfx.play("flare", -12.0, 2.0)
	return killed > 0


## 3.5 (правка 8): бомбы только по наземным целям, зато вдвое сильнее
const GROUND_BOMB_K := 2.0
## S6-02: НАР по земле ×3 (стандартная цель — 3 ракеты «Грача», броня — 5, бункер — 9)
const ROCKET_GROUND_K := 3.0


func _fire_bombs(p: Player, manual := false) -> bool:
	if evo:
		return _fire_carpet_row(p, manual)
	# 3.5: бомбы бьют только по земле (урон ×GROUND_BOMB_K), самолёты не задевают.
	# Авто — по ближайшим наземным целям в радиусе 600; по кнопке — к курсору / вперёд.
	var targets: Array = []
	if not manual:
		var skip: Array = []
		for s in slots:
			var t := Weapons.pick_target(p.global_position, 600.0, "nearest", skip, false, true)
			if t == null:
				break
			targets.append(t)
			skip.append(t)
		if targets.is_empty():
			return false
	var fuse := 0.55
	for s in slots:
		var to: Vector2
		if not targets.is_empty():
			var t: Enemy = targets[s % targets.size()]
			var tv: Vector2 = t.get("velocity") if t.get("velocity") is Vector2 else Vector2.ZERO
			to = t.global_position + tv * fuse
		else:
			to = aim_point(p)
		to += Vector2(randf_range(-20, 20), randf_range(-20, 20))
		Main.I.projectiles.spawn_bomb(_slot_pos(p, s), fuse * Profile.wk("bombs", "fuse"), dmg() * Profile.wk("bombs", "dmg") * GROUND_BOMB_K,
			range_px() * Profile.wk("bombs", "blast_r"), "бомбы", to, true)
		Main.I.projectiles.bombs[-1]["vt"] = WeaponModels.bomb_t(level)   # тест 3.5-s4 (п. 10), 3.5-s8: падает бомба калибра с подвеса
		_bay_release(p, Main.I.projectiles.bombs[-1], 0.0)
		if p.syn.has("carpet_road"): # «Ковровая дорожка»: крест суббоеприпасов и огонь
			Main.I.projectiles.bombs[-1]["road"] = true
	Main.I.sfx.play("bomb_drop", -14.0, 1.2)
	return true


## Тест 3.5-s5 (п. 3), только вид: из бомбоотсека бомба уходит, когда створки уже открылись (BAY_OPEN_T),
## ряд «ковра» — по очереди (stagger); пока она в отсеке, самолёт летит — старт сдвигается вперёд с ним.
## Место и момент разрыва не меняются (projectiles._update_bombs: к концу взрывателя бомба в точке «to»).
const BAY_OPEN_T := 0.12


## Bomb `b` leaves through open bay doors (only the look) — for `WeaponFire`
func bay_release(p: Player, b: Dictionary, stagger: float) -> void:
	_bay_release(p, b, stagger)


func _bay_release(p: Player, b: Dictionary, stagger: float) -> void:
	if launch_offs.is_empty() or not Render3D.enabled or not name.begins_with("Бомбоотсек"):
		return
	var rel := minf(BAY_OPEN_T + stagger, float(b["fuse"]) * 0.6)
	b["rel"] = rel
	b["from"] = (b["from"] as Vector2) + p.velocity * rel


## «Бабушкин ковёр»: ряд из 8 бомб поперёк курса, ширина 600
## Тест 3.5-s7 (Kanta: «модернизация бомб слабее 5-го уровня»): у ур. 5 две бомбы по 55 летят прямо в цели,
## а ряд ковра падал вслепую в 220 пикс. впереди. Теперь ряд ложится на ближайшую наземную цель
## (поперёк курса, не дальше 460 пикс.), бомба — 70 (ур. 5 — 55), радиус 180 (было 150)
const CARPET_DMG := 70.0
const CARPET_R := 180.0


func _fire_carpet_row(p: Player, manual: bool) -> bool:
	var tgt: Enemy = null if manual else Weapons.pick_target(p.global_position, 700.0, "nearest", [], false, true)
	if not manual and tgt == null:
		return false
	var fwd := Vector2.from_angle(p.heading)
	var side := Vector2.from_angle(p.heading + PI / 2.0)
	var c := p.global_position + fwd * 220.0 + p.velocity * 0.4
	if tgt != null:
		c = p.global_position + (tgt.global_position - p.global_position).limit_length(460.0)
	# 3.4: ветки бомб из ангара (урон, радиус, взрыватель) и «Ковровая дорожка» действуют и после эволюции
	var road := p.syn.has("carpet_road")
	for i in 8:
		var off := (float(i) / 7.0 - 0.5) * 600.0
		# тест 3.5-s5 (п. 3): точка старта — бомба кассеты в отсеке (только вид; куда и когда рвётся — как было)
		Main.I.projectiles.spawn_bomb(_slot_pos(p, i), (0.5 + 0.04 * i) * Profile.wk("bombs", "fuse"), dmg() * Profile.wk("bombs", "dmg") * GROUND_BOMB_K,
			CARPET_R * Profile.wk("bombs", "blast_r"), "бомбы", c + side * off, true)
		Main.I.projectiles.bombs[-1]["vt"] = WeaponModels.BOMB_EVO_VT
		_bay_release(p, Main.I.projectiles.bombs[-1], 0.04 * i * Profile.wk("bombs", "fuse"))
		if road:
			Main.I.projectiles.bombs[-1]["road"] = true
	if road:
		Main.I.tele.add("carpet_road_evo")
	Main.I.sfx.play("bomb_drop", -12.0, 1.0)
	return true
