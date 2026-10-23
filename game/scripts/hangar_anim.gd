class_name HangarAnim
## Тест 3.5-s8 (Kanta: «в предпросмотре механизации — анимация: закрылки поднимались и опускались»).
## Только ангар (Hangar3D): в бою механизация, створки и турели управляются render3d, этот файл туда не подключён.
## Показ механизации (кнопка «▶ Механизация» на виде самолёта или курсор на узле «Крыло»):
##   закрылки и предкрылки выходят и убираются — цикл MECH_PERIOD с паузами в выпущенном и убранном положении;
##   створки бомбоотсека «Кита» закрываются и открываются (со сдвигом на полцикла);
## Обычный вид — механизация убрана, створки открыты (видно бомбы, как раньше).
## S9-04 (Kanta 23.10): турели в ангаре НЕ вращаются и не качают стволами — ни на самолёте, ни на вкладке
## «ОРУЖИЕ»: стоят в походном положении, стволами по оси. Вращается турель только в бою (render3d).
## Переход между режимами плавный (BLEND в секунду).

const MECH_PERIOD := 3.0     # с: выпуск 0,8 → пауза 0,7 → уборка 0,8 → пауза 0,7
const MECH_MOVE := 0.8
const MECH_HOLD := 0.7
const BLEND := 2.0
const DEMO_MECH := 1.6       # в показе ход больше боевого (закрылки ~35°, как на посадке) — видно издалека


## Подвижные части текущей модели под pivot ангара: механизация, створки и бомбы в отсеке (турели — нет, S9-04)
static func collect(root: Node3D) -> Dictionary:
	var d := {"mech": null, "bay": null, "load": [], "k": 0.0}
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
