class_name VisualBench
extends RefCounted
## B-23: стенд скриншотов для сравнения картинки «до/после» (-- --visual).
## Фиксированное зерно, без врагов и интерфейса; 6 точек камеры → user://vis_*.png.
## В журнал — средняя яркость и доля пересвеченных пикселей (> 245) каждого кадра.

const SEED := 20261014
const WAIT := 0.6      # секунд реального времени на точку: камера и 3D успевают встать

var m: Main
var _i := -1
var _t := 0.0
var _phase := 0        # 0 — встать в точку, 1 — снять
var _points: Array = []


static func seed_world() -> void:
	seed(SEED)


func _init(main: Main) -> void:
	m = main


func process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.01)
	if m.state == "menu" and _i < 0 and _t > 1.0:
		m.select_class("fighter")
		_t = 0.0
		return
	if m.state != "playing" or not is_instance_valid(m.player):
		return
	m.god_mode = true
	m.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for e in m.get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	if m.hud != null:
		m.hud.visible = false
	if _i < 0:
		if _t < 1.0:
			return
		_points = _make_points()
		_i = 0
		_t = 0.0
	if _i >= _points.size():
		print("VISUAL done")
		m.get_tree().quit()
		return
	var p: Dictionary = _points[_i]
	_hold(p)
	if _phase == 0 and _t > WAIT:
		if p.get("boom", false):
			var c: Vector2 = p["pos"]
			m.fx.explosion(c + Vector2(220, -90), 34.0)
			m.fx.explosion(c + Vector2(-260, 140), 22.0)
			m.fx.explosion(c + Vector2(60, 230), 16.0, false)
		_phase = 1
		_t = 0.0
	elif _phase == 1 and _t > (0.25 if p.get("boom", false) else 0.05):
		_save(p["name"])
		_phase = 0
		_t = 0.0
		_i += 1


func _hold(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	m.player.global_position = pos
	m.player.heading = -PI / 4.0
	m.camera.global_position = pos
	m.camera.zoom = Vector2.ONE * float(p.get("zoom", 1.0))
	m.camera.reset_smoothing()


func _save(name: String) -> void:
	var img := m.get_viewport().get_texture().get_image()
	img.save_png("user://vis_%s.png" % name)
	# яркость: каждый 4-й пиксель по обеим осям
	var n := 0
	var hot := 0
	var sum := 0.0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			var l := (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			sum += l
			n += 1
			if l > 245.0:
				hot += 1
	print("VISUAL %s lum=%.1f hot=%.2f%%" % [name, sum / maxf(n, 1), 100.0 * hot / maxf(n, 1)])


## Точки: пустыня, гора, кишлак, оазис, бой со взрывами, крупный план самолёта
func _make_points() -> Array:
	var bg := m.background
	var found := {}
	var empty := Vector2.INF
	for r in range(0, 14):
		for cx in range(-r, r + 1):
			for cy in range(-r, r + 1):
				if maxi(absi(cx), absi(cy)) != r:
					continue
				var o := bg.chunk_object(cx, cy)
				if o.is_empty():
					if empty == Vector2.INF:
						empty = Vector2((cx + 0.5) * Background.CHUNK, (cy + 0.5) * Background.CHUNK)
				elif not found.has(o["name"]):
					found[o["name"]] = o["pos"]
	if empty == Vector2.INF:
		empty = Vector2.ZERO
	var pts := [{"name": "desert", "pos": empty}]
	for k in [["mountain", "o_mesa"], ["village", "o_village"], ["oasis", "o_oasis"]]:
		pts.append({"name": k[0], "pos": found.get(k[1], empty + Vector2(4000, 0))})
	pts.append({"name": "battle", "pos": empty + Vector2(0, -300), "boom": true})
	pts.append({"name": "closeup", "pos": found.get("o_rocks_big", empty) + Vector2(-260, 0), "zoom": 2.5})
	return pts

