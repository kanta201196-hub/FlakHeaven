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
## «Низкое» качество графики: моделей нет, меню рисует картинки art/planes, повёрнутые по heading().

const H0 := -PI / 2.0 - 0.2    # курс звена: вверх по экрану (к горизонту наклонной камеры) и чуть влево
const SPEED := 80.0            # пикс/с по плоскости боя (было 76 в 3.4 — та же неторопливость)
const WEAVE := 0.12            # «змейка» курса, ± рад
const WEAVE_W := 0.11          # её частота, рад/с (период ~57 с)
const BANK_K := 3.2            # крен от скорости разворота
const ANCHOR := Vector2(0.56, 0.54)  # ведущий на экране, доля кадра (справа от кнопок, под журналом)
const LEN_K := 0.17            # длина «Осы» на экране, доля высоты кадра
const ALT := 60.0              # высота звена над плоскостью боя, пикс
## класс, место в строю (вперёд, вправо — в длинах «Осы»), длина относительно «Осы», фаза разнобоя
const FLIGHT := [
	["fighter", Vector2(0.0, 0.0), 1.0, 0.0],
	["attacker", Vector2(-1.1, -1.3), 1.08, 1.7],
	["bomber", Vector2(-1.55, 1.45), 1.45, 3.1],
]

static var _t := 0.0


## Курс звена сейчас (рад, как heading в 2D: 0 — вправо, −π/2 — вверх по экрану)
static func heading() -> float:
	return H0 + WEAVE * sin(_t * WEAVE_W)


## Скорость разворота, рад/с
static func turn_rate() -> float:
	return WEAVE * WEAVE_W * cos(_t * WEAVE_W)


## Шаг камеры меню за кадр (реальное время): камера плывёт вместе со звеном
static func advance(dt: float) -> Vector2:
	_t += dt
	return Vector2.from_angle(heading()) * SPEED * dt


## Разнобой ведомого в строю: (покачивание вдоль/поперёк в долях «Осы», крен, высота)
static func wobble(ph: float) -> Vector4:
	return Vector4(sin(_t * 0.7 + ph) * 0.05, sin(_t * 0.9 + ph * 1.3) * 0.04,
		sin(_t * 0.5 + ph * 0.7) * 0.05, sin(_t * 0.8 + ph) * 12.0)


var r3: Render3D
var _units: Array = []   # записи как у Render3D._units: node, k, fx, mech, sh …
var _key := ""
var _check_t := 0.0


func _init(render: Render3D) -> void:
	r3 = render


## Звено видно: меню (или настройки из меню), 3D включено, качество не «Низкое»
static func want_3d() -> bool:
	return Render3D.enabled and Settings.gfx > 0


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
	var lead := Vector2(o.x + d.x * (-o.y / d.y), o.z + d.z * (-o.y / d.y))   # точка ведущего на плоскости боя
	var L := LEN_K * vs.y / maxf(r3._zoom, 0.01)
	var h := heading()
	var fwd := Vector2.from_angle(h)
	var right := fwd.orthogonal() * -1.0   # вправо по курсу (2D: y вниз)
	var bank := clampf(turn_rate() * BANK_K, -0.35, 0.35)
	for u: Dictionary in _units:
		var w := wobble(float(u["ph"]))
		var off: Vector2 = u["slot"]
		var p := lead + fwd * (off.x + w.x) * L + right * (off.y + w.y) * L
		var y := ALT + w.w
		var len_w: float = L * float(u["rel"])   # длина на плоскости боя: на экране LEN_K высоты кадра при любом зуме
		u["k"] = len_w / float((u["tex"] as Texture2D).get_width())
		r3._place(u, p, h, bank + w.z, 0.0, y, r3._alt_scale(y))
		PlaneFx.update(u, delta, 0.0)
		var pts := PlaneFx.trail_points(u)
		var s := len_w / 100.0
		for i in pts.size():
			r3._trails.emit("title_%s_%d" % [u["cls"], i], pts[i], [0.16, 2.5 * s, 9.0 * s, 3.0, 10.0 * s])


func _build() -> void:
	for f in FLIGHT:
		var cls: String = f[0]
		var lvl: int = Profile.plane_lvl(cls)
		var tex := PlaneArt.plane_tex(cls, lvl)
		var tex1 := PlaneArt.plane_tex(cls, 1)
		var path := "res://models/hangar/fh_hangar_%s_%d.glb" % [cls, lvl]
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
		var u := {"node": root, "kind": "title", "cls": cls, "tex": tex, "bm": sc, "slot": f[1], "ph": f[3],
			"rel": rel, "k": 1.0, "alt": ALT}   # alt — Render3D._place ставит самолёт на луч камеры
		u["sh"] = r3._make_shadow(tex, root)
		PlaneFx.attach(u, tex)   # огонь сопел; винты «Кита 1» (WingMech.attach_props) с диском размытия
		Livery.apply(model, cls, lvl, Livery.current(cls))   # после всех деталей — перекрашиваются и они
		_units.append(u)


func clear() -> void:
	for u: Dictionary in _units:
		if is_instance_valid(u["node"]):
			(u["node"] as Node).queue_free()
	_units.clear()
	_key = ""
