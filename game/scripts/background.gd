class_name Background
extends Node2D
## Биом 1 «Горная пустыня» (2.6).
##  • земля — шейдер: 4 бесшовные текстуры смешиваются пятнами по шуму (shaders/ground.gdshader);
##  • объекты — скалы, гора, крепость, деревня, оазис, воронки, обломки: по одному на клетку карты,
##    клетка всегда выглядит одинаково (по ней можно ориентироваться), с тенью по высоте объекта;
##  • облака — отдельный узел Clouds (выше самолётов, с параллаксом и тенью на земле).
## Если картинок биома нет — рисуется старый фон-заглушка (сетка и «острова»).

## 3.3: вымышленное название биома с отсылкой к горам Гиндукуша (реальные места не переносим)
const BIOME_NAME := "Нагорье Шахрисанг"
const BIOME_SUB := "ущелья, кишлаки, следы боёв"

const CHUNK := 1400.0
const OBJ_CHANCE := 0.62

## имя: [размер в мире (длинная сторона), высота для тени, вес выпадения, оттенок]
const OBJECTS := {
	"o_rocks_big": [300.0, 14.0, 3.0, Color(0.88, 0.84, 0.8)],
	"o_rocks_small": [150.0, 8.0, 5.0, Color(0.92, 0.9, 0.86)],
	"o_mesa": [560.0, 34.0, 1.2, Color(0.9, 0.86, 0.82)],
	"o_fort": [380.0, 18.0, 1.0, Color(1, 1, 1)],
	"o_village": [900.0, 10.0, 1.2, Color(1, 1, 1)],   # тест 3.5-s4 (п. 19): разрушенный городок — крупнее (было 440, потом 640)
	"o_oasis": [420.0, 16.0, 1.0, Color(1, 1, 1)],
	"o_crater": [170.0, 0.0, 3.0, Color(1, 1, 1)],
	"o_wreck": [150.0, 3.0, 1.2, Color(1, 1, 1)],
}

var ground: ColorRect
var _tex := {}
var _names: Array = []
var _total_w := 0.0
var biome_ok := false


func _ready() -> void:
	z_index = -10
	process_mode = Node.PROCESS_MODE_ALWAYS # фон меню рисуется и на паузе
	var paths := ["sand", "clay", "gravel", "riverbed"]
	var texs := []
	for n in paths:
		var p := "res://art/ground/g_%s.png" % n
		texs.append(load(p) if ResourceLoader.exists(p) else null)
	biome_ok = not texs.has(null) and ResourceLoader.exists("res://shaders/ground.gdshader")
	if biome_ok:
		ground = ColorRect.new()
		ground.z_index = -20
		ground.z_as_relative = false
		ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/ground.gdshader")
		mat.set_shader_parameter("t_sand", texs[0])
		mat.set_shader_parameter("t_clay", texs[1])
		mat.set_shader_parameter("t_gravel", texs[2])
		mat.set_shader_parameter("t_river", texs[3])
		mat.set_shader_parameter("seed", float(randi() % 1000))
		ground.material = mat
		add_child(ground)
		for k in OBJECTS:
			var p: String = "res://art/objects/%s.png" % k
			if ResourceLoader.exists(p):
				_tex[k] = load(p)
				_names.append(k)
				_total_w += float(OBJECTS[k][2])


func _view() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2()
	var center := cam.get_screen_center_position()
	var half := get_viewport_rect().size / cam.zoom * 0.5 + Vector2(220, 220)
	return Rect2(center - half, half * 2.0)


func _process(_delta: float) -> void:
	if biome_ok:
		ground.visible = not Render3D.enabled
		var v := _view()
		ground.position = v.position
		ground.size = v.size
	queue_redraw()


## Объект клетки (или пусто): одинаковый для одной и той же клетки.
## Тест 3.5-s4 (п. 20): поправка места объекта по рельефу (Terrain3D.fix_object — не в реке);
## задаёт 3D-рельеф, без него объекты стоят как выпали. Результат с поправкой кэшируется
var place_filter := Callable()
var _placed := {}


func chunk_object(cx: int, cy: int) -> Dictionary:
	if not place_filter.is_valid():
		return _chunk_object_raw(cx, cy)
	var key := Vector2i(cx, cy)
	if not _placed.has(key):
		if _placed.size() > 4000:
			_placed.clear()
		var o := _chunk_object_raw(cx, cy)
		_placed[key] = o if o.is_empty() else place_filter.call(o)
	return _placed[key]


func _chunk_object_raw(cx: int, cy: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cy)) ^ 0x0b1e
	if _names.is_empty() or rng.randf() > OBJ_CHANCE:
		return {}
	var r := rng.randf() * _total_w
	var name: String = _names[0]
	for k in _names:
		r -= float(OBJECTS[k][2])
		if r <= 0.0:
			name = k
			break
	var size: float = OBJECTS[name][0] * rng.randf_range(0.85, 1.15)
	var margin := size * 0.5 + 40.0
	var p := Vector2((cx * CHUNK) + rng.randf_range(margin, CHUNK - margin), (cy * CHUNK) + rng.randf_range(margin, CHUNK - margin))
	# var — раскладка построек (AdobeBuild): от клетки, не от rng — остальные поля не сдвигаются
	return {"name": name, "pos": p, "size": size, "rot": rng.randf() * TAU, "flip": rng.randf() < 0.5, "var": absi(hash(Vector2i(cx, cy))) % 4}


func _draw() -> void:
	var view := _view()
	if view.size == Vector2.ZERO or (Render3D.enabled and biome_ok):
		return
	if not biome_ok:
		_draw_placeholder(view)
		return
	var g := view.grow(700.0)
	var objs: Array = []
	for cx in range(int(floorf(g.position.x / CHUNK)), int(floorf(g.end.x / CHUNK)) + 1):
		for cy in range(int(floorf(g.position.y / CHUNK)), int(floorf(g.end.y / CHUNK)) + 1):
			var o := chunk_object(cx, cy)
			if not o.is_empty() and view.grow(o["size"]).has_point(o["pos"]):
				objs.append(o)
	# сначала все тени, потом объекты — тени не ложатся поверх соседей
	for o in objs:
		var h: float = OBJECTS[o["name"]][1]
		if h > 0.0:
			_draw_obj(o, Vector2(h, h * 1.5), Color(0.08, 0.06, 0.03, 0.42))
	# 2.8: объём — высокие объекты «растут» к камере: несколько слоёв со сдвигом от центра экрана
	# (перспектива сверху), нижние слои темнее — получаются стены и склоны
	var cam_c := view.get_center()
	var half_d := view.size.length() * 0.5
	for o in objs:
		var h: float = OBJECTS[o["name"]][1]
		var col: Color = OBJECTS[o["name"]][3]
		if h < 6.0 or OS.get_cmdline_user_args().has("--noext"):
			_draw_obj(o, Vector2.ZERO, col)
			continue
		var lean: Vector2 = ((o["pos"] as Vector2) - cam_c) / half_d * h * 1.6
		var natural: bool = o["name"] in ["o_mesa", "o_rocks_big", "o_rocks_small", "o_oasis"]
		var n := clampi(int(h / 3.0) + 2, 3, 12)
		for i in n + 1:
			var t := float(i) / n
			var shade := lerpf(0.45, 1.0, t)
			var sh := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
			_draw_obj(o, lean * t, sh, lerpf(1.0, 0.9, t) if natural else 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_obj(o: Dictionary, off: Vector2, col: Color, shrink := 1.0) -> void:
	var t: Texture2D = _tex[o["name"]]
	var k: float = o["size"] * shrink / float(maxi(t.get_width(), t.get_height()))
	var sc := Vector2(k * (-1.0 if o["flip"] else 1.0), k)
	draw_set_transform(o["pos"] + off, o["rot"], sc)
	draw_texture(t, -t.get_size() / 2.0, col)


func _draw_placeholder(view: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	var g := view.grow(160.0)
	var ch := 800.0
	for cx in range(int(floorf(g.position.x / ch)), int(floorf(g.end.x / ch)) + 1):
		for cy in range(int(floorf(g.position.y / ch)), int(floorf(g.end.y / ch)) + 1):
			rng.seed = hash(Vector2i(cx, cy)) ^ 0x5eed
			for i in rng.randi_range(4, 9):
				var p := Vector2((cx + rng.randf()) * ch, (cy + rng.randf()) * ch)
				var r := rng.randf_range(30.0, 160.0)
				var c := Color(0.16, 0.2, 0.17).lerp(Color(0.13, 0.17, 0.24), rng.randf())
				if view.grow(r).has_point(p):
					draw_circle(p, r, c)
	var step := 160.0
	var gc := Color(1, 1, 1, 0.05)
	var x := floorf(view.position.x / step) * step
	while x < view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), gc, 1.0)
		x += step
	var y := floorf(view.position.y / step) * step
	while y < view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), gc, 1.0)
		y += step
