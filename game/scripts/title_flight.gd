class_name TitleFlight
extends Node3D
## Тест 3.5-s5 (п. 1): заставка главного меню — звено «Оса», «Грач», «Кит» 3D-моделями ангара
## (models/hangar, как после переделки M-34) прямо в 3D-сцене над живым биомом.
## Камера меню плывёт по курсу звена (main.gd берёт шаг из advance()), поэтому самолёты стоят в кадре,
## а земля уходит назад под ними — звено летит носом вперёд, а не ползёт боком, как плоские картинки 3.4.
## Курс плавно «змейкой» — отсюда лёгкие крены; у каждого свой небольшой разнобой высоты и крена.
## Окраска — выбранная в ангаре (Livery.current), уровень самолёта — выбранный в ангаре (Profile.plane_lvl).
## Механизация, детали силуэта, знаки, кормовая кабина и винты «Кита 1» — те же узлы, что в ангаре и в бою.
## Тени — дешёвые «высотные» пятна по силуэту (как у своих самолётов в бою), без прохода теней солнца.
## С-5 (аудит 3.5-s6): на «Низком» качестве — тоже 3D, облегчённые модели боя (models/battle), а не старые
## картинки art/planes другой формы и окраски.

const H0 := -PI / 2.0 - 0.2    # курс звена: вверх по экрану (к горизонту наклонной камеры) и чуть влево
const SPEED := 80.0            # пикс/с по плоскости боя (было 76 в 3.4 — та же неторопливость)
const WEAVE := 0.12            # «змейка» курса, ± рад
const WEAVE_W := 0.11          # её частота, рад/с (период ~57 с)
const BANK_K := 3.2            # крен от скорости разворота
## s13 (Kanta: «подрагивание самолётов на заставке»): the turn rate was the per-frame heading change over dt, so
## the uneven camera steps along the traced river (±10 % frame to frame) shook the bank by ±0.03 rad every
## frame and up to 0.25 rad in two frames. The rate now follows that raw value with this time constant, 1/s
const RATE_K := 1.2
## S11-01: the camera flies along the river valley (river, road, fields, villages, slopes on both sides:
## the Highlands at their most readable) instead of drifting over whatever lies up-screen. The route is
## the river line itself, traced ahead of the camera, and the camera follows its moving average over
## ±ROUTE_WIN px of river, so meanders do not swing the flight while the water stays on screen.
const ROUTE_STEP := 40.0       # river line sample spacing, px
const ROUTE_WIN := 1200.0      # half window of the moving average along the river, px
const ROUTE_AHEAD := 3000.0    # traced river kept ahead of the camera, px
const ROUTE_PER_FRAME := 8     # max river samples traced per frame (each ~14 river_field calls)
const ROUTE_MAX := 4000        # samples (160 km of river, ~35 min) before the route restarts here
const SETTLE_T := 8.0          # s to ease from where the camera was onto the route
const SETTLE_MAX := 600.0      # farther than this from the route (back from a sortie) — jump to it
const TURN_K := 0.6            # how fast the heading follows the route, 1/s
## s13 (Kanta's video: the flight crossed the logo and slid under the side panels): ANCHOR is now the centre of
## the formation, not the leader, at the centre of the free window of the menu (between the button column
## at 0.31 and the panels at 0.70 of the width, below the logo at 0.30 and above the hints at 0.95 of the
## height). The river route turns the flight any way, so the formation is closed up (FLIGHT slots ×0.77) and
## sized to fit that window at any heading: its farthest plane («Кит», 1.9 «Осы» lengths from the centre)
## stays inside at LEN_K 0.15
const ANCHOR := Vector2(0.505, 0.62)  # центр строя на экране, доля кадра
const LEN_K := 0.15            # длина «Осы» на экране, доля высоты кадра
const ALT := 60.0              # высота звена над плоскостью боя, пикс
## класс, место в строю (вперёд, вправо — в длинах «Осы»), длина относительно «Осы», фаза разнобоя
const FLIGHT := [
	["fighter", Vector2(0.0, 0.0), 1.0, 0.0],
	["attacker", Vector2(-0.85, -1.0), 1.08, 1.7],
	["bomber", Vector2(-1.2, 1.1), 1.45, 3.1],
]

## Centre of the formation in «Оса» lengths (forward, right): the mean of the FLIGHT slots
const _CENTRE := Vector2(-0.683, 0.033)

static var _t := 0.0
static var _head := H0         # course without the weave (along the route)
static var _rate := 0.0        # its turn rate, rad/s
static var _route := TitleRoute.new(ROUTE_STEP, ROUTE_WIN)   # traced river and its moving average
static var _dir := Vector2.ZERO             # tracing direction at the route's last point
static var _s := 0.0                        # camera's place on the route, px of river
static var _off := Vector2.ZERO             # camera minus route when the route started (eased out)
static var _off_t := 0.0
static var _on_route := false               # the camera follows the route (no weave then)
static var _last := Vector2.INF             # where advance() left the camera


## The flight's heading now (rad, as a 2D heading: 0 is right, −π/2 is up the screen). On the river
## route it is the camera's actual direction of motion; off it, H0 with a slow weave
static func heading() -> float:
	return _head if _on_route else _head + WEAVE * sin(_t * WEAVE_W)


## Turn rate of heading(), rad/s, smoothed over RATE_K (drives the bank)
static func turn_rate() -> float:
	return _rate if _on_route else _rate + WEAVE * WEAVE_W * cos(_t * WEAVE_W)


## The menu camera's step this frame (real time): the camera flies with the flight. pos is where the
## camera is now. S11-01: with the Highlands terrain built, the step follows the river valley route;
## without it (tests, the Archipelago coast, the first frames before the 3D scene) the old straight
## course H0 with a weave
static func advance(dt: float, pos := Vector2.INF) -> Vector2:
	_t += dt
	var t := _terrain()
	if t == null or not pos.is_finite():
		_route.clear()
		_on_route = false
		_last = Vector2.INF
		_head = lerp_angle(_head, H0, 1.0 - exp(-dt * TURN_K))
		_rate = lerpf(_rate, 0.0, 1.0 - exp(-dt * RATE_K))
		return Vector2.from_angle(heading()) * SPEED * dt
	if _route.size() == 0 or not _last.is_finite() or pos.distance_to(_last) > 1.0 \
			or _route.size() > ROUTE_MAX:
		_start_route(t, pos)   # first frame, the camera was moved (back from a sortie), or a long run
	if not _on_route:
		_head = heading()   # keep the weave's current angle: no snap when the weave stops
		_on_route = true
	_trace(t)
	var tan := _route.point(_s + 60.0) - _route.point(_s - 60.0)
	var k := tan.length() / 120.0   # smoothed path length per px of river (< 1 on meanders)
	_s += SPEED * dt / clampf(k, 0.25, 1.0)
	_off_t += dt
	var target := _route.point(_s) + _off * (1.0 - smoothstep(0.0, SETTLE_T, _off_t))
	var prev := _head
	if (target - pos).length_squared() > 1e-6:
		_head = lerp_angle(_head, (target - pos).angle(), 1.0 - exp(-dt * TURN_K))
	_rate = lerpf(_rate, angle_difference(prev, _head) / maxf(dt, 1e-4), 1.0 - exp(-dt * RATE_K))
	_last = target
	return target - pos


## Highlands terrain of the menu backdrop, or null (no 3D scene yet, or the Archipelago: its coast field
## has no river line to follow)
static func _terrain() -> Terrain3D:
	if Render3D.I == null or Render3D.I.terrain == null or Biome.sea():
		return null
	return Render3D.I.terrain


## New route from the river nearest to pos, traced in the direction closest to the current heading
## (H0 at the first start). The camera eases onto it over SETTLE_T, or jumps when it is farther than
## SETTLE_MAX (the menu opening after a sortie: the scene changes anyway); the heading keeps easing
static func _start_route(t: Terrain3D, pos: Vector2) -> void:
	var p := _to_river(t, pos)
	_dir = _river_tangent(t, p, Vector2.from_angle(_head))
	_route.clear()
	_route.add(p)
	_s = 0.0
	_trace(t)
	_off = pos - _route.point(0.0)
	if _off.length() > SETTLE_MAX:
		_off = Vector2.ZERO
	_off_t = 0.0


## Extends the route so it reaches ROUTE_AHEAD + ROUTE_WIN past the camera (spread over frames)
static func _trace(t: Terrain3D) -> void:
	var need := int((_s + ROUTE_WIN + ROUTE_AHEAD) / ROUTE_STEP) + 1
	var n := 0
	while _route.size() < need and n < ROUTE_PER_FRAME:
		var p := _to_river(t, _route.last() + _dir * ROUTE_STEP, 2, ROUTE_STEP)
		_dir = _river_tangent(t, p, _dir)
		_route.add(p)
		n += 1


## Newton steps onto the river line (river_field = 0), each at most max_step px. Tracing passes the
## sample spacing, so a flat stretch of the field cannot throw the route onto a neighbouring valley
static func _to_river(t: Terrain3D, p: Vector2, steps := 12, max_step := 1500.0) -> Vector2:
	for i in steps:
		var v := t.river_field(p.x, p.y)
		var g := _grad(t, p)
		if g.length_squared() < 1e-10:
			break
		var d := g * (v / g.length_squared())
		p -= d.limit_length(max_step)
		if absf(v) < 0.5:
			break
	return p


## River direction at p, the one of its two senses closer to want
static func _river_tangent(t: Terrain3D, p: Vector2, want: Vector2) -> Vector2:
	var g := _grad(t, p)
	if g.length_squared() < 1e-10:
		return want.normalized()
	var a := g.normalized().orthogonal()
	return a if a.dot(want) >= 0.0 else -a


## Gradient of river_field at p (central differences, 8 px)
static func _grad(t: Terrain3D, p: Vector2) -> Vector2:
	var e := 8.0
	return Vector2(t.river_field(p.x + e, p.y) - t.river_field(p.x - e, p.y),
		t.river_field(p.x, p.y + e) - t.river_field(p.x, p.y - e)) / (2.0 * e)


## Разнобой ведомого в строю: (покачивание вдоль/поперёк в долях «Осы», крен, высота)
static func wobble(ph: float) -> Vector4:
	return Vector4(sin(_t * 0.7 + ph) * 0.05, sin(_t * 0.9 + ph * 1.3) * 0.04,
		sin(_t * 0.5 + ph * 0.7) * 0.05, sin(_t * 0.8 + ph) * 12.0)


var r3: Render3D
var _units: Array[Unit3D] = []   # same records as Render3D._units
var _key := ""
var _check_t := 0.0


func _init(render: Render3D) -> void:
	r3 = render


## Звено видно: меню (или настройки из меню), 3D включено (на любом качестве графики)
static func want_3d() -> bool:
	return Render3D.enabled


func active() -> bool:
	return not _units.is_empty()


## Каждый кадр из Render3D._process (после камеры). on — заставка на экране
func sync(on: bool, delta: float) -> void:
	if not on or not want_3d():
		clear()
		return
	_check_t -= delta
	if _units.is_empty() or _check_t <= 0.0:
		_check_t = 0.5   # смена окраски / уровня в ангаре — пересобрать звено
		var key := ""
		for f in FLIGHT:
			key += "%s%d%s;" % [f[0], Profile.plane_lvl(f[0]), Livery.current(f[0])]
		key += "g%d" % mini(Settings.gopt("props"), 1)   # «Низкое» ↔ остальные: другая модель
		if key != _key:
			clear()
			_key = key
			_build()
	if _units.is_empty():
		return
	var cam := r3.cam
	var vs := get_viewport().get_visible_rect().size
	var o := cam.project_ray_origin(vs * ANCHOR)
	var d := cam.project_ray_normal(vs * ANCHOR)
	if d.y > -0.05:
		return
	var mid := Vector2(o.x + d.x * (-o.y / d.y), o.z + d.z * (-o.y / d.y))   # центр строя на плоскости боя
	var L := LEN_K * vs.y / maxf(r3._zoom, 0.01)
	var h := heading()
	var fwd := Vector2.from_angle(h)
	var right := fwd.orthogonal() * -1.0   # вправо по курсу (2D: y вниз)
	var lead := mid - (fwd * _CENTRE.x + right * _CENTRE.y) * L
	var bank := clampf(turn_rate() * BANK_K, -0.35, 0.35)
	for u: Unit3D in _units:
		var w := wobble(u.wob)
		var off: Vector2 = u.slot
		var p := lead + fwd * (off.x + w.x) * L + right * (off.y + w.y) * L
		var y := ALT + w.w
		var len_w: float = L * float(u.rel)   # длина на плоскости боя: на экране LEN_K высоты кадра при любом зуме
		u.k = len_w / float((u.tex as Texture2D).get_width())
		r3._place(u, p, h, bank + w.z, 0.0, y, r3._alt_scale(y))
		PlaneFx.update(u, delta, 0.0)
		var pts := PlaneFx.trail_points(u)
		var s := len_w / 100.0
		for i in pts.size():
			r3._trails.emit("title_%s_%d" % [u.cls, i], pts[i], [0.16, 2.5 * s, 9.0 * s, 3.0, 10.0 * s])


func _build() -> void:
	for f in FLIGHT:
		var cls: String = f[0]
		var lvl: int = Profile.plane_lvl(cls)
		var tex := PlaneArt.plane_tex(cls, lvl)
		var tex1 := PlaneArt.plane_tex(cls, 1)
		var path := "res://models/hangar/fh_hangar_%s_%d.glb" % [cls, lvl]
		if Settings.gopt("props") == 0:   # «Низкое»: облегчённая модель боя (те же оси и узлы деталей)
			var lite := "res://models/battle/fh_battle_%s_%d.glb" % [cls, lvl]
			if ResourceLoader.exists(lite):
				path = lite
		if tex == null or tex1 == null or not ResourceLoader.exists(path):
			continue
		var sc := load(path) as PackedScene
		var model: Node3D = sc.instantiate()
		model.scale = Vector3.ONE * float(tex.get_width())   # длина модели 1 = ширина картинки (как в бою)
		var root := Node3D.new()
		root.add_child(model)
		add_child(root)
		var key := "%s_%d" % [cls, lvl]
		# как в ангаре (Hangar3D._build): механизация убрана, детали силуэта, знаки, кормовая кабина, створки закрыты
		WingMech.attach(model, key)
		WingMech.attach_detail(model, key)
		Insignia.attach(model, key, "player")
		WingMech.attach_tail(model, key)
		WingMech.attach_bay(model, key)
		# длина относительно «Осы»: по классу и по картинке уровня (ур. 2 крупнее), как в бою
		var rel := float(f[2]) * float(tex.get_width()) / float(tex1.get_width())
		var u := Unit3D.new()
		u.node = root
		u.kind = "title"
		u.cls = cls
		u.tex = tex
		u.bm = sc
		u.slot = f[1]
		u.wob = f[3]
		u.rel = rel
		u.has_alt = true   # Render3D._place puts the plane on the camera ray at alt
		u.alt = ALT
		u.sh = r3._make_shadow(tex, root)
		PlaneFx.attach(u, tex)   # огонь сопел; винты «Кита 1» (WingMech.attach_props) с диском размытия
		Livery.apply(model, cls, lvl, Livery.current(cls))   # после всех деталей — перекрашиваются и они
		_units.append(u)


func clear() -> void:
	for u: Unit3D in _units:
		if is_instance_valid(u.node):
			(u.node as Node).queue_free()
	_units.clear()
	_key = ""
