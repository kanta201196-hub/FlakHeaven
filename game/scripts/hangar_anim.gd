class_name HangarAnim
## Тест 3.5-s8 (Kanta: «в предпросмотре механизации — анимация: закрылки поднимались и опускались, турели вращались»).
## Только ангар (Hangar3D): в бою механизация, створки и турели управляются render3d, этот файл туда не подключён.
## Показ механизации (кнопка «▶ Механизация» на виде самолёта или курсор на узле «Крыло»):
##   закрылки и предкрылки выходят и убираются — цикл MECH_PERIOD с паузами в выпущенном и убранном положении;
##   створки бомбоотсека «Кита» закрываются и открываются (со сдвигом на полцикла);
##   турели поворачиваются по азимуту (±TURRET_YAW, кормовая — ±TAIL_YAW) и качают стволами по углу места.
## Обычный вид — «дежурная» анимация: механизация убрана, створки открыты (видно бомбы, как раньше),
## турели медленно и неглубоко поводят стволами (±IDLE_YAW за IDLE_PERIOD).
## Переход между режимами плавный (BLEND в секунду).

const MECH_PERIOD := 3.0     # с: выпуск 0,8 → пауза 0,7 → уборка 0,8 → пауза 0,7
const MECH_MOVE := 0.8
const MECH_HOLD := 0.7
const TURRET_PERIOD := 6.0   # с: полный проход по азимуту туда и обратно
const TURRET_YAW := 1.2      # рад, ±70°
const TAIL_YAW := 0.85       # рад, ±50° (в бою кормовая — в секторе ±60°)
const ELEV_MAX := 0.3        # рад, ~17° вверх: люлька не задевает бронещиток
const ELEV_MIN := -0.05
const TAIL_ELEV := 0.3       # рад, ± качание шара кормовой установки
const IDLE_PERIOD := 11.0
const IDLE_YAW := 0.3        # рад, ±17°
const IDLE_ELEV := 0.08
const BLEND := 2.0
const DEMO_MECH := 1.6       # в показе ход больше боевого (закрылки ~35°, как на посадке) — видно издалека


## Подвижные части текущей модели под pivot ангара. Турели — узлы с метой "turret" ([класс, ступень, сторона,
## эволюция, ур. самолёта]); при первом проходе делятся на корпус и узел «guns» (WeaponModels.split_turret)
static func collect(root: Node3D) -> Dictionary:
	var d := {"mech": null, "bay": null, "turrets": [], "load": [], "k": 0.0}
	for c in root.find_children("*", "Node3D", true, false):
		var n := c as Node3D
		if n.is_queued_for_deletion():
			continue
		if n.name == "wing_mech" and d["mech"] == null:
			d["mech"] = n
		elif n.name == "bay_doors" and d["bay"] == null:
			d["bay"] = n
		elif n.has_meta("bay_load"):
			d["load"].append(n)
		elif n.has_meta("turret") and n is MeshInstance3D:
			var info: Array = n.get_meta("turret")
			var guns: Node3D = null
			if not n.has_meta("anim_rest"):
				n.set_meta("anim_rest", n.basis)
				guns = WeaponModels.split_turret(n as MeshInstance3D, info[0], info[1], info[2], info[3], info[4])
			else:
				guns = n.find_child("guns", false, false) as Node3D
			# кормовая: шар качается целиком, кабина стрелка (если своя) стоит на месте
			var tail: bool = info[2] == "tail"
			d["turrets"].append({"node": n, "guns": guns, "tail": tail, "cabin": n.find_child("cabin", false, false),
				"ph": float((d["turrets"] as Array).size()) * 1.7})
	return d


## Поза на момент t (с); demo — показ механизации; delta — для плавного перехода между режимами
static func step(d: Dictionary, t: float, demo: bool, delta: float) -> void:
	var k := move_toward(float(d["k"]), 1.0 if demo else 0.0, BLEND * delta)
	d["k"] = k
	var ks := smoothstep(0.0, 1.0, k)
	var mech: Node3D = d["mech"]
	if mech != null and is_instance_valid(mech) and not WingMech._force:
		WingMech.pose(mech, ks * DEMO_MECH * mech_phase(t))
	var bay: Node3D = d["bay"]
	if bay != null and is_instance_valid(bay):
		var bt := lerpf(1.0, 1.0 - mech_phase(t + MECH_PERIOD * 0.5), ks)
		WingMech.pose_bay(bay, bt)
		# бомбы висят ниже створок: пока отсек почти закрыт, их не показываем (иначе «торчат» сквозь створки)
		for b: Node3D in d["load"]:
			if is_instance_valid(b):
				b.visible = bt > 0.55
	for tr: Dictionary in d["turrets"]:
		var n: Node3D = tr["node"]
		if not is_instance_valid(n):
			continue
		var ph: float = tr["ph"]
		var tail: bool = tr["tail"]
		var yi := sin(TAU * (t + ph) / IDLE_PERIOD) * IDLE_YAW
		var ei := (0.5 + 0.5 * sin(TAU * (t + ph) / (IDLE_PERIOD * 0.5))) * IDLE_ELEV
		var yd := sin(TAU * (t + ph) / TURRET_PERIOD) * (TAIL_YAW if tail else TURRET_YAW)
		var ed := sin(TAU * (t + ph) / (TURRET_PERIOD * 0.5))
		var guns: Node3D = tr["guns"]
		ed = ed * TAIL_ELEV if guns == null else lerpf(ELEV_MIN, ELEV_MAX, 0.5 + 0.5 * ed)
		var yaw := lerpf(yi * (0.7 if tail else 1.0), yd, ks)
		var el := lerpf(ei, ed, ks)
		var rot := Basis(Vector3.UP, yaw)
		if guns == null:
			# кормовой шар или турель без отдельных стволов — качается вся установка
			rot = rot * Basis(Vector3.BACK, el)
		elif is_instance_valid(guns):
			guns.basis = Basis(Vector3.BACK, el)   # стволы +X: поворот вокруг +Z поднимает их вверх
		n.basis = (n.get_meta("anim_rest") as Basis) * rot
		var cab: Node3D = tr["cabin"]
		if cab != null and is_instance_valid(cab):
			cab.basis = rot.inverse()


## Выпуск механизации 0…1 в цикле: плавный выпуск, пауза, плавная уборка, пауза
static func mech_phase(t: float) -> float:
	var u := fposmod(t, MECH_PERIOD)
	if u < MECH_MOVE:
		return smoothstep(0.0, 1.0, u / MECH_MOVE)
	u -= MECH_MOVE
	if u < MECH_HOLD:
		return 1.0
	u -= MECH_HOLD
	if u < MECH_MOVE:
		return 1.0 - smoothstep(0.0, 1.0, u / MECH_MOVE)
	return 0.0
