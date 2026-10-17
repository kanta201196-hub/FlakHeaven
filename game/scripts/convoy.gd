class_name Convoy
extends Node2D
## Активность «Наземный конвой» (A-03, концепция docs/activities/convoy.md; решения Kanta 17.10.2026).
## Колонна снабжения идёт по дороге вдоль реки (Terrain3D: ось дороги D_ROAD от реки) к укрытию в конце маршрута.
## Подлёт ближе 1000 пикс. или попадание — тревога: 70 с до укрытия, грузовики прибавляют ход, охрана
## съезжает вбок и стреляет, БМП ставит дым над грузовиками, пикап с ПЗРК пускает ракеты с места.
## Подбитая машина остаётся остовом: колонна объезжает его медленно — выгодно сначала сжечь голову.
## Награда: груз с каждого грузовика (ящик с запчастями на дороге), все грузовики — активность засчитана.

const ACTIVATE_R := 1000.0
const LIMIT := 70.0
const SMOKE_TIME := 8.0
const SMOKE_R := 170.0
const SMOKE_CUT := 0.4        # под дымом машины получают на 40% меньше урона
const STEP := 30.0            # шаг точек маршрута, пикс.
const CARGO := {"truck": 30.0, "light": 15.0}

var pts := PackedVector2Array()   # маршрут: точки рельефа по оси дороги
var cum := PackedFloat32Array()   # длина пути до каждой точки
var length := 0.0
var vehicles: Array = []          # ConvoyVehicle в порядке марша (живые и остовы)
var wrecks: Array = []            # [s, lane] остовов на дороге
var alarm := false
var timer := LIMIT
var ended := false                # время вышло или колонна разбита
var done := false                 # все грузовики сожжены
var failed := false
var leaderless := false           # грузовиков не осталось
var trucks_total := 0
var trucks_killed := 0
var trucks_escaped := 0
var smoke_t := 0.0
var smoke_c := Vector2.INF
var _smoke_used := false
var on_road := false              # маршрут нашёлся по дороге (иначе — прямая по дну долины)
var _t := 0.0


## center — точка, через которую пройдёт колонна; dir — примерное направление марша
func setup(center: Vector2, dir: Vector2, hp_k: float, dps: float, t: float) -> void:
	_build_route(center, dir)
	var order := ["scout", "technical", "truck", "light", "truck", "ifv", "manpads"]
	if t >= 480.0:
		order.append("ifv")       # с 8-й минуты вторая БМП
	if t >= 660.0:
		order.append("manpads")   # с 11-й — второй пикап с ПЗРК
	# машины ставим от головы назад: голова у точки 1 400 пикс. от начала маршрута
	var at := minf(1400.0, length * 0.35)
	for i in order.size():
		var r: String = order[i]
		var sp: Dictionary = ConvoyVehicle.SPEC[r]
		var v := ConvoyVehicle.new()
		v.setup(r, self, maxf(float(sp["hp"]) * hp_k, dps * float(sp["ttk"])))
		if i > 0:
			var prev: Dictionary = ConvoyVehicle.SPEC[order[i - 1]]
			at -= (float(sp["len"]) + float(prev["len"])) * 0.5 * Tuning.g("unit_scale") + 45.0
		v.place(maxf(at, 0.0))
		vehicles.append(v)
		if v.is_truck():
			trucks_total += 1
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: convoy route on_road=%s len=%d vehicles=%d trucks=%d" % [on_road, int(length), vehicles.size(), trucks_total])


func _ready() -> void:
	z_index = -3
	for v in vehicles:
		Main.I.world.add_child.call_deferred(v)


# --- маршрут ---

func _terrain() -> Terrain3D:
	if Render3D.I != null and Render3D.I.terrain != null and Render3D.I.terrain._bg != null:
		return Render3D.I.terrain
	return null


## Маршрут по оси дороги: 1 500 пикс. назад от center и 3 000 вперёд по ходу dir
func _build_route(center: Vector2, dir: Vector2) -> void:
	var tr := _terrain()
	if tr != null:
		var c := _to_road(tr, tr.find_floor(center, 900.0))
		if c != Vector2.INF:
			var fw := _march(tr, c, dir, 3000.0)
			var bk := _march(tr, c, -dir, 1500.0)
			if fw.size() * STEP > 1800.0 and bk.size() * STEP > 900.0:
				bk.reverse()
				pts = bk
				pts.append_array(fw.slice(1))
				on_road = true
	if not on_road:
		# рельефа нет (или дорога не нашлась) — прямая
		pts = PackedVector2Array()
		var d := dir.normalized()
		for i in int(4500.0 / STEP) + 1:
			pts.append(center + d * (i * STEP - 1500.0))
	cum = PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	length = cum[cum.size() - 1]


func _rf_grad(tr: Terrain3D, p: Vector2) -> Vector2:
	var e := 4.0
	var f := tr.river_field(p.x, p.y)
	return Vector2(tr.river_field(p.x + e, p.y) - f, tr.river_field(p.x, p.y + e) - f) / e


## Ньютоном на линию river_field = +D_ROAD (дорога вдоль одного берега)
func _to_road(tr: Terrain3D, p: Vector2, iters := 12) -> Vector2:
	for i in iters:
		var f := tr.river_field(p.x, p.y) - Terrain3D.D_ROAD
		if absf(f) < 1.5:
			return p
		var g := _rf_grad(tr, p)
		if g.length_squared() < 1e-6:
			return Vector2.INF
		p -= g * clampf(f, -200.0, 200.0) / g.length_squared()
	return p if absf(tr.river_field(p.x, p.y) - Terrain3D.D_ROAD) < 8.0 else Vector2.INF


## Идти вдоль дороги шагами STEP; точки от p (включительно)
func _march(tr: Terrain3D, p: Vector2, dir: Vector2, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array([p])
	var g := _rf_grad(tr, p)
	var t := Vector2(-g.y, g.x).normalized()
	if t.dot(dir) < 0.0:
		t = -t
	var walked := 0.0
	while walked < dist:
		var q := _to_road(tr, p + t * STEP, 4)
		if q == Vector2.INF or q.distance_to(p) < STEP * 0.5 or q.distance_to(p) > STEP * 2.0:
			break
		var nt := (q - p).normalized()
		if nt.dot(t) < 0.3:   # петля или развилка — дальше не идём
			break
		t = nt
		walked += q.distance_to(p)
		p = q
		out.append(p)
	return out


func _seg(s: float) -> int:
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if cum[m] <= s:
			lo = m
		else:
			hi = m
	return lo


func point_at(s: float) -> Vector2:
	if s <= 0.0:
		return pts[0] + dir_at(0.0) * s
	if s >= length:
		return pts[pts.size() - 1] + dir_at(length) * (s - length)
	var i := _seg(s)
	var k := (s - cum[i]) / maxf(cum[i + 1] - cum[i], 1e-3)
	return pts[i].lerp(pts[i + 1], k)


func dir_at(s: float) -> Vector2:
	var i := clampi(_seg(clampf(s, 0.0, length)), 0, pts.size() - 2)
	return (pts[i + 1] - pts[i]).normalized()


## Влево по ходу колонны
func normal_at(s: float) -> Vector2:
	var d := dir_at(s)
	return Vector2(d.y, -d.x)


## Где на маршруте точка p (ищем рядом с подсказкой hint)
func project(p: Vector2, hint: float) -> float:
	var i0 := clampi(_seg(clampf(hint, 0.0, length)) - 4, 0, pts.size() - 2)
	var i1 := mini(i0 + 10, pts.size() - 2)
	var best := hint
	var best_d := INF
	for i in range(i0, i1 + 1):
		var a := pts[i]
		var ab := pts[i + 1] - a
		var k := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-3), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * k)
		if d < best_d:
			best_d = d
			best = cum[i] + ab.length() * k
	return best


## Смещение точки вбок от оси дороги (+ — влево)
func lateral_of(p: Vector2, s: float) -> float:
	return (p - point_at(s)).dot(normal_at(s))


# --- колонна ---

func alive() -> Array:
	var out := []
	for v in vehicles:
		if is_instance_valid(v) and not (v as ConvoyVehicle).wreck and not (v as ConvoyVehicle).escaped:
			out.append(v)
	return out


## Ближайшая живая машина впереди по маршруту
func ahead_of(me: ConvoyVehicle) -> ConvoyVehicle:
	var best: ConvoyVehicle = null
	for v in alive():
		var c := v as ConvoyVehicle
		if c == me or c.s <= me.s:
			continue
		if best == null or c.s < best.s:
			best = c
	return best


## Середина колонны по грузовикам (куда смотрит охрана)
func middle_s() -> float:
	var sum := 0.0
	var n := 0
	for v in alive():
		if (v as ConvoyVehicle).is_truck():
			sum += (v as ConvoyVehicle).s
			n += 1
	return sum / n if n > 0 else 0.0


## Остов на дороге впереди (в пределах look пикс.) рядом с полосой lane → в какую полосу объезжать, иначе INF
func wreck_ahead(s: float, lane: float, look: float) -> float:
	for w in wrecks:
		var ds: float = float(w[0]) - s
		if ds > 0.0 and ds < look and absf(float(w[1]) - lane) < 38.0:
			return float(w[1]) + (-55.0 if float(w[1]) >= 0.0 else 55.0)
	return INF


func in_smoke(p: Vector2) -> bool:
	return smoke_t > 0.0 and smoke_c != Vector2.INF and p.distance_to(smoke_c) < SMOKE_R


## Середина колонны на экране (указатель HUD)
func focus() -> Vector2:
	var trucks := []
	for v in alive():
		if (v as ConvoyVehicle).is_truck():
			trucks.append(v)
	var arr := trucks if not trucks.is_empty() else alive()
	if arr.is_empty():
		return global_position
	var sum := Vector2.ZERO
	for v in arr:
		sum += (v as Node2D).global_position
	return sum / arr.size()


func trucks_left() -> int:
	return trucks_total - trucks_killed - trucks_escaped


func _raise_alarm() -> void:
	if alarm:
		return
	alarm = true
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: convoy alarm")
	Main.I.show_banner("Колонна обнаружила вас! Грузовики уходят к укрытию — %d с" % int(LIMIT), 3.0)
	Main.I.sfx.play("aa_alert", -2.0, 0.8)


func on_hit() -> void:
	_raise_alarm()


func on_destroyed(v: ConvoyVehicle) -> void:
	_raise_alarm()
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: convoy destroyed %s s=%d lane=%d" % [v.role, int(v.s), int(v.lane)])
	wrecks.append([v.s, v.lane])
	Main.I.tele.add("convoy_vehicles_killed")
	if v.is_truck():
		trucks_killed += 1
		Main.I.tele.add("convoy_trucks_killed")
		Main.I.pickups.drop_cargo(v.global_position, CARGO.get(v.role, 15.0) * Main.I.continue_mult())
		_check_trucks()
	elif v.role == "ifv" and smoke_t > 0.0:
		smoke_t = minf(smoke_t, 2.0)


func on_escaped(v: ConvoyVehicle) -> void:
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: convoy escaped ", v.role)
	if v.is_truck():
		trucks_escaped += 1
		Main.I.tele.add("convoy_trucks_escaped")
		Main.I.fx.text(v.global_position + Vector2(0, -30), "Грузовик ушёл в укрытие", Color(1.0, 0.6, 0.4))
		_check_trucks()
	v.remove_from_group("enemies")
	v.queue_free()


func _check_trucks() -> void:
	if trucks_left() > 0:
		return
	leaderless = true
	if trucks_killed == trucks_total and not failed and not done:
		done = true
		Main.I.tele.add("convoy_done")
		Main.I.on_activity_success("convoy")
	elif not failed and not done:
		failed = true
		Main.I.show_banner("Часть колонны ушла в укрытие — груз потерян", 3.0)
	_finish()


## Активность закончена: следующая может начаться, остатки колонны уезжают и убираются сами
func _finish() -> void:
	ended = true
	if Main.I.spawner != null and Main.I.spawner.activity_node == self:
		Main.I.spawner.activity_node = null


func _process(delta: float) -> void:
	_t += delta
	var f := focus()
	global_position = f
	var p := Main.I.player
	if p == null:
		return
	if not alarm:
		for v in alive():
			var c := v as ConvoyVehicle
			if c.global_position.distance_to(p.global_position) < ACTIVATE_R or c.hp < c.max_hp:
				_raise_alarm()
				break
	if alarm:
		if not ended:
			timer -= delta
			if timer <= 0.0:
				failed = true
				Main.I.show_banner("Колонна ушла от удара — груз потерян", 3.0)
				_finish()
		# БМП ставит дым над серединой колонны один раз за активность
		if not _smoke_used:
			for v in alive():
				if (v as ConvoyVehicle).role == "ifv":
					_smoke_used = true
					smoke_t = SMOKE_TIME
					Main.I.sfx.play("aa_intercept", -8.0, 0.6)
					break
	if smoke_t > 0.0:
		smoke_t -= delta
		var mid := point_at(middle_s())
		smoke_c = mid if smoke_c == Vector2.INF else smoke_c.lerp(mid, 1.0 - exp(-delta * 0.8))
	# ушли далеко после конца — убираем всё, включая остовы
	if ended and (alive().is_empty() or f.distance_to(p.global_position) > 2600.0):
		var far := true
		for v in vehicles:
			if is_instance_valid(v) and (v as Node2D).global_position.distance_to(p.global_position) < 2600.0:
				far = false
		if far:
			for v in vehicles:
				if is_instance_valid(v):
					(v as Node).queue_free()
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	# дымовая завеса — мягкие пятна над серединой колонны (на плоскости боя, видно и в 3D)
	if smoke_t > 0.0 and smoke_c != Vector2.INF and Fx._soft != null:
		var a := clampf(smoke_t / 1.5, 0.0, 1.0) * clampf((SMOKE_TIME - smoke_t) / 0.8, 0.0, 1.0)
		var loc := GroundTarget.air_pos(smoke_c) - global_position
		for i in 7:
			var o := Vector2.from_angle(i * 0.9 + _t * 0.15) * SMOKE_R * (0.25 + 0.1 * (i % 3))
			var r := SMOKE_R * (0.55 + 0.08 * (i % 4))
			draw_texture_rect(Fx._soft, Rect2(loc + o - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.78, 0.76, 0.7, 0.55 * a))
