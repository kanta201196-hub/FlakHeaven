class_name TitleFlight
extends Node3D
## Тест 3.5-s5 (п. 1): заставка главного меню — звено «Оса», «Грач», «Кит» 3D-моделями ангара
## (models/hangar, как после переделки M-34) прямо в 3D-сцене над живым биомом.
## Камера меню плывёт по курсу звена (main.gd берёт шаг из advance()), поэтому самолёты стоят в кадре,
## а земля уходит назад под ними — звено летит носом вперёд, а не ползёт боком, как плоские картинки 3.4.
## Курс прямо к верху экрана (S14-11) с едва заметной «змейкой» — отсюда лёгкие крены; у каждого свой небольшой разнобой высоты и крена.
## Окраска — выбранная в ангаре (Livery.current), уровень самолёта — выбранный в ангаре (Profile.plane_lvl).
## Механизация, детали силуэта, знаки, кормовая кабина и винты «Кита 1» — те же узлы, что в ангаре и в бою.
## Тени — дешёвые «высотные» пятна по силуэту (как у своих самолётов в бою), без прохода теней солнца.
## С-5 (аудит 3.5-s6): на «Низком» качестве — тоже 3D, облегчённые модели боя (models/battle), а не старые
## картинки art/planes другой формы и окраски.

## S14-11 (Kanta: «самолёты не должны летать по кругу, пусть летят в одну сторону к верху экрана»): the flight
## holds one course straight up the screen. The river route of S11-01 turned it with every meander, so over a
## minute the planes pointed every way; the camera now flies a straight line and the ground passes under it.
## A slow, small weave keeps a little life in the banks without turning the nose away from the top.
const H0 := -PI / 2.0          # курс звена: прямо вверх по экрану
const SPEED := 80.0            # пикс/с по плоскости боя (было 76 в 3.4 — та же неторопливость)
const WEAVE := 0.035           # «змейка» курса, ± рад (2°: нос всегда к верху экрана)
const WEAVE_W := 0.11          # её частота, рад/с (период ~57 с)
const BANK_K := 3.2            # крен от скорости разворота
## s13 (Kanta's video: the flight crossed the logo and slid under the side panels): ANCHOR is now the centre of
## the formation, not the leader, at the centre of the free window of the menu (between the button column
## at 0.31 and the panels at 0.70 of the width, below the logo at 0.30 and above the hints at 0.95 of the
## height). The formation is closed up (FLIGHT slots ×0.77) and sized to fit that window: its farthest plane
## («Кит», 1.9 «Осы» lengths from the centre) stays inside at LEN_K 0.15
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


## The flight's heading now (rad, as a 2D heading: 0 is right, −π/2 is up the screen): H0 with the slow weave
## Cutscene (story step 2): the scene sets the course; the camera is driven by `Cutscene`, not by the menu flight.
static var override := false
static var ov_heading := 0.0
## Story step 9: the campaign screen's operation vignette anchors the flight in its window (screen fraction);
## Vector2.INF — the menu's ANCHOR.
static var ov_anchor := Vector2.INF


static func heading() -> float:
	if override:
		return ov_heading
	return H0 + WEAVE * sin(_t * WEAVE_W)


## Turn rate of heading(), rad/s (drives the bank): the weave's derivative, smooth by construction
static func turn_rate() -> float:
	if override:
		return 0.0
	return WEAVE * WEAVE_W * cos(_t * WEAVE_W)


## The menu camera's step this frame (real time): the camera flies with the flight, straight along heading().
## pos is kept for the caller's signature (where the camera is now); the course no longer depends on it
static func advance(dt: float, _pos := Vector2.INF) -> Vector2:
	_t += dt
	return Vector2.from_angle(heading()) * SPEED * dt


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
	var anc := ov_anchor if ov_anchor != Vector2.INF else ANCHOR
	var o := cam.project_ray_origin(vs * anc)
	var d := cam.project_ray_normal(vs * anc)
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
