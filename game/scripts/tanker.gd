class_name Tanker
extends Node2D
## 3.5: свой заправщик (пункт 20 теста 3.4-t1, решение «Бак 9 минут»).
## Прилетает, когда в баке 20%, и выходит вперёд самолёта игрока. Заправка — держаться у него
## в хвосте (зелёный конус за ним): 6 с — полный бак. Его атакуют перехватчики — защитите его.
## Через 60 с или после заправки уходит; сбит — следующий через 2 минуты.

const LIFE := 60.0
const FILL_TIME := 6.0          # секунд в конусе до полного бака
const SLOT := 340.0             # держится впереди игрока на этом расстоянии
const CONE_NEAR := 130.0
const CONE_FAR := 460.0
const CONE_HALF_W := 120.0
const HP := 320.0

var fuel: Fuel
var heading := 0.0
var speed := 300.0
var hp := HP
var max_hp := HP
var life := LIFE
var leaving := false
var refueled := false
var filling := false            # игрок сейчас в конусе
var fill_shown := 0.0           # сколько заправлено за этот прилёт (для полоски)
var _flash := 0.0
var _gone := false
var _t := 0.0


func setup(p: Player, f: Fuel) -> void:
	fuel = f
	var side := 1.0 if randf() < 0.5 else -1.0
	position = p.global_position + Vector2.from_angle(p.heading + side * randf_range(0.6, 1.0)) * 1900.0
	heading = (p.global_position + Vector2.from_angle(p.heading) * 600.0 - position).angle()
	speed = _base_speed(p)
	# перехватчики идут на заправщик: 2, с 8-й минуты — 3
	var n := 2 + (1 if Main.I.run_time > 480.0 else 0)
	var from := position + Vector2.from_angle(heading + side * 1.4) * 700.0
	for i in n:
		var e := Interceptor.new()
		e.position = from + Vector2(randf_range(-120, 120), randf_range(-120, 120))
		e.heading = (position - e.position).angle()
		e.hunt = self
		Main.I.world.add_child(e)
		e.apply_hp_mult(Tuning.g("enemy_hp_mult") * Spawner.hp_ramp(Main.I.run_time))


func _ready() -> void:
	add_to_group("allies3d")
	z_index = 1


static func _base_speed(p: Player) -> float:
	return p.cruise_speed() / maxf(Fuel.speed_k(), 0.01)


## Для 3D: текстура и длина (как у ведомых)
func ally_tex() -> Texture2D:
	var t: Texture2D = Enemy.etex("a_tanker")
	return t if t != null else PlaneArt.plane_tex("bomber", 2)


func ally_len() -> float:
	return Tuning.g("plane_len") * 1.9


func alive() -> bool:
	return hp > 0.0 and not _gone


## Урон от врагов (перехватчики бьют по нему очередями)
func take_damage(d: float) -> void:
	if hp <= 0.0 or _gone:
		return
	hp -= d
	_flash = 0.08
	if hp <= 0.0:
		Main.I.fx.explosion(global_position, 46.0)
		Main.I.add_shake(6.0)
		Main.I.show_banner("Заправщик сбит! Следующий — через 2 минуты", 4.0)
		Main.I.sfx.play("shield_break", -4.0, 0.6)
		_finish(false)


func _finish(ok: bool) -> void:
	if _gone:
		return
	_gone = true
	if fuel != null:
		fuel.on_tanker_gone(ok)
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: tanker %s at %.0f, fuel %.0f%%" % ["refuel" if ok else "lost", Main.I.run_time, fuel.frac() * 100.0 if fuel != null else -1.0])
	if hp <= 0.0:
		remove_from_group("allies3d")
		queue_free()


func _process(delta: float) -> void:
	var p := Main.I.player
	if p == null:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	life -= delta
	if not leaving and (life <= 0.0 or refueled):
		leaving = true
		if not refueled:
			Main.I.show_banner("Заправщик уходит — следующий через 2 минуты", 3.0)
			_finish(false)
	var fwd := Vector2.from_angle(p.heading)
	if leaving:
		# уходит в сторону с набором скорости
		heading = rotate_toward(heading, p.heading + 0.9, deg_to_rad(25.0) * delta)
		speed = move_toward(speed, _base_speed(p) * 1.3, 120.0 * delta)
		filling = false
	else:
		# выходит в точку впереди игрока и держит его курс и скорость
		var slot := p.global_position + fwd * SLOT
		var to := slot - global_position
		var d := to.length()
		var want := to.angle() if d > 160.0 else p.heading
		heading = rotate_toward(heading, want, deg_to_rad(38.0) * delta)
		var ahead := to.dot(Vector2.from_angle(heading))   # >0 — слот впереди нас
		var target := p.velocity.length() + clampf(ahead, -300.0, 600.0) * 0.9
		speed = move_toward(speed, clampf(target, 120.0, _base_speed(p) * 1.6), 260.0 * delta)
		_refuel(p, delta)
	position += Vector2.from_angle(heading) * speed * delta
	if leaving and global_position.distance_to(p.global_position) > 2400.0:
		if not _gone:
			_finish(refueled)
		remove_from_group("allies3d")
		queue_free()
		return
	queue_redraw()


func _refuel(p: Player, delta: float) -> void:
	var back := -Vector2.from_angle(heading)
	var rel := p.global_position - global_position
	var along := rel.dot(back)
	var lat := absf(rel.dot(Vector2(-back.y, back.x)))
	var aligned := absf(wrapf(p.heading - heading, -PI, PI)) < deg_to_rad(45.0)
	filling = along > CONE_NEAR and along < CONE_FAR and lat < CONE_HALF_W and aligned and p.hp > 0.0
	if not filling or fuel == null:
		return
	var add := delta / FILL_TIME
	fuel.add(add)
	fill_shown += add
	Main.I.tele.add("fuel_fill_s", delta)
	if fuel.frac() >= 0.999:
		refueled = true
		Main.I.show_banner("Заправка завершена — бак полный", 3.0)
		Main.I.sfx.play("evac", -6.0, 1.4)
		_finish(true)


func _draw() -> void:
	var xf := Transform2D(heading, Vector2.ZERO)
	# конус заправки за хвостом
	if not leaving:
		var a := 0.16 + (0.14 * absf(sin(_t * 6.0)) if filling else 0.0)
		var cone := xf * PackedVector2Array([Vector2(-CONE_NEAR, -40), Vector2(-CONE_FAR, -CONE_HALF_W), Vector2(-CONE_FAR, CONE_HALF_W), Vector2(-CONE_NEAR, 40)])
		draw_colored_polygon(cone, Color(0.4, 1.0, 0.5, a))
		draw_line(xf * Vector2(-40, 0), xf * Vector2(-150, 0), Color(0.85, 0.9, 0.95, 0.9), 3.0) # штанга
	if not Render3D.enabled:
		var t := ally_tex()
		if t != null:
			var k := ally_len() / float(t.get_width())
			draw_set_transform(Vector2.ZERO, heading, Vector2(k, k))
			draw_texture(t, -t.get_size() / 2.0, Color(4, 4, 4, 1) if _flash > 0.0 else Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# прочность и заправка
	var w := 90.0
	draw_rect(Rect2(-w / 2.0, -78, w, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w / 2.0, -78, w * hp / max_hp, 6), Color(0.4, 0.9, 1.0))
	if filling and fuel != null:
		draw_arc(Vector2.ZERO, 70.0, -PI / 2.0, -PI / 2.0 + TAU * fuel.frac(), 48, Color(0.5, 1.0, 0.5, 0.9), 4.0)
	draw_string(Hud.ui_font(), Vector2(-90, -88), "Заправщик", HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(0.7, 1.0, 0.8))
