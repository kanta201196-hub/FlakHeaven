class_name RivalAce
extends Enemy
## Активность «Догфайт»: вражеский ас-соперник с позывным и репликами по радио.
## Он не таранит — он садится вам на хвост и бьёт очередями, когда вы у него в прицеле.
## Как победить:
##  • сбросить газ (S) или резко развернуться — у аса минимальная скорость выше вашей,
##    он проскакивает вперёд («перелёт») и уходит в отворот;
##  • в этот момент сесть ему на хвост (бонус «на хвосте» работает и на нём);
##  • боевой разворот / бочка — сорвать его атаку.
## 3.5: сам уходит рывком с бочкой из-под очередей и отстреливает ловушки от ракет — бить нужно с хвоста.
## Сбит — гарантированный выбор из редких карточек. Через 90 с ас уходит сам.

const CALLSIGNS := ["Барон", "Шершень", "Граф", "Сокол-7", "Профессор", "Тётя Шура"]
const LINES := {
	"spawn": ["Ну здравствуй, новичок. Пристегнись.", "Я тебя давно ищу. Потанцуем?", "О, свежий самолёт. Будет что рассказать в столовой."],
	"behind": ["Вижу тебя. Ты у меня на мушке!", "Не верти хвостом — всё равно достану.", "Сиди смирно, сейчас будет больно."],
	"overshoot": ["Эй! Тормозить — нечестно!", "Проскочил… бывает.", "Ладно, ладно, зайду ещё раз."],
	"tailed": ["Кто это у меня на хвосте?!", "Слезь с хвоста, я тебе не такси!", "Ведомый, помоги! А, у меня нет ведомого…"],
	"hit": ["Ай! Это была новая краска!", "Ну всё, теперь это личное."],
	"down": ["Катапультируюсь! Увидимся в столовой…", "Хорош… Признаю.", "Передай механику — он был прав про двигатель."],
	"escape": ["Топливо на нуле. В другой раз, новичок!", "Мне пора на обед. Не скучай!"],
	"again": ["Снова ты? В прошлый раз тебе повезло.", "Узнаю этот самолёт. Сегодня без поблажек.", "Мы уже встречались. Второй раз не уйдёшь."],
}

var callsign := ""
var _again := false   # «Барон» уже встречался в кампании
var life := 90.0
var _state := "chase"   # chase — заходит в хвост; break — отворот после перелёта
var _state_t := 0.0
var _break_dir := 0.0
var _aim := 0.0
var _shots := 0
var _shot_t := 0.0
var _burst_cd := 1.0
var _said := {}
var _speed := 300.0
var _hp_said := false
var _tailed_t := 0.0
var _evade_cd := 1.0
var _scan_t := 0.0
var _flare_cd := 0.0


func setup(hp_total: float) -> void:
	# U-05: в операциях 2–4 кампании в дуэль выходит «Барон» и помнит прошлые встречи
	if Campaign.baron():
		callsign = "Барон"
		_again = Campaign.baron_met() > 0
		Campaign.on_baron_met()
	else:
		callsign = CALLSIGNS[randi() % CALLSIGNS.size()]
	hp = hp_total
	max_hp = hp_total
	min_life = 14.0   # правка 3.5-s4: не падает за секунды при любой сборке
	radius = 18.0
	big = true
	no_despawn = true
	contact_damage = 6.0
	xp = 25
	parts = 40
	repair_chance = 1.0
	kill_shake = 10.0


func kind() -> String:
	return "ас-соперник"


func apply_hp_mult(_m: float) -> void:
	pass


func _ready() -> void:
	super()
	say("again" if _again else "spawn")


func say(key: String, force := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - float(_said.get("_last", -99.0)) < 4.0:
		return
	_said["_last"] = now
	var arr: Array = LINES[key]
	Main.I.radio(callsign, arr[randi() % arr.size()], true)


func take_hit(dmg: float, source := "прочее") -> void:
	super(dmg, source)
	if hp > 0.0 and hp < max_hp * 0.5 and not _hp_said:
		_hp_said = true
		say("hit", true)


func behave(delta: float) -> void:
	var p := Main.I.player
	if p == null or p.hp <= 0.0:
		position += Vector2.from_angle(heading) * _speed * delta
		return
	life -= delta
	if life <= 0.0:
		say("escape", true)
		Main.I.on_activity_failed("dogfight", callsign)
		remove_from_group("enemies")
		queue_free()
		return
	_state_t += delta
	var pf := Vector2.from_angle(p.heading)
	var to := p.global_position - global_position
	var d := to.length()
	var cruise := p.cruise_speed()
	# Ас держит минимум 85% крейсерской игрока — резкий сброс газа заставляет его проскочить
	var min_spd := cruise * 0.85
	var max_spd := cruise * 1.35
	match _state:
		"chase":
			var slot := p.global_position - pf * 260.0
			var want := slot - global_position
			heading = rotate_toward(heading, want.angle(), deg_to_rad(Tuning.g("turn_rate") * 0.85) * delta)
			# подстраивает скорость под игрока, но не ниже минимума
			var target_spd := p.velocity.length() + clampf(want.length() - 60.0, -200.0, 400.0) * 0.8
			_speed = move_toward(_speed, clampf(target_spd, min_spd, max_spd), 500.0 * delta)
			# перелёт: ас оказался впереди игрока
			if d < 320.0 and pf.dot(-to.normalized()) > 0.3:
				_start_break()
		"break":
			heading = rotate_toward(heading, _break_dir, deg_to_rad(Tuning.g("turn_rate") * 0.7) * delta)
			_speed = move_toward(_speed, cruise * 1.1, 300.0 * delta)
			if _state_t > 1.6:
				_state = "chase"
				_state_t = 0.0
	position += Vector2.from_angle(heading) * _speed * delta

	# 3.5: уход из-под огня и ловушки
	_evade_cd -= delta
	_scan_t -= delta
	_flare_cd -= delta
	flare_defense(delta, 400.0, 240.0, 0.8, 2.5, 8.0)
	if _evade_cd <= 0.0 and _scan_t <= 0.0 and evade_t <= 0.0 and _shots == 0:
		_scan_t = 0.15
		var threat := incoming_fire(0.4, 3)
		if threat != Vector2.ZERO:
			start_evade(threat, 300.0, 0.7)
			_evade_cd = randf_range(2.2, 3.2)

	# игрок у аса на хвосте?
	if p.on_tail() and p.tail_target == self:
		_tailed_t += delta
		if _tailed_t > 1.0:
			say("tailed")
			_tailed_t = -3.0

	# Стрельба: игрок в узком конусе прицела аса
	if _shots > 0:
		_shot_t -= delta
		if _shot_t <= 0.0:
			fire_at_player(randf_range(-0.05, 0.05))
			_shots -= 1
			_shot_t = 0.09
		return
	if _aim > 0.0:
		_aim -= delta
		if _aim <= 0.0:
			_shots = 4
		return
	_burst_cd -= delta
	var off := absf(wrapf(to.angle() - heading, -PI, PI))
	if _state == "chase" and _burst_cd <= 0.0 and d < 560.0 and off < deg_to_rad(14.0):
		_aim = 0.35
		_burst_cd = 1.6
		say("behind")


func threatening() -> bool:
	# для предупреждения «ХВОСТ!»: ас сзади игрока и целится
	var p := Main.I.player
	if p == null:
		return false
	var to := p.global_position - global_position
	return _state == "chase" and to.length() < 650.0 and Vector2.from_angle(p.heading).dot(to.normalized()) > 0.3


func _start_break() -> void:
	_state = "break"
	_state_t = 0.0
	_break_dir = heading + (1.0 if randf() < 0.5 else -1.0) * deg_to_rad(110.0)
	_shots = 0
	_aim = 0.0
	say("overshoot")
	Main.I.fx.text(global_position + Vector2(0, -40), "Перелёт!", Color(0.6, 0.95, 1.0))


func _die() -> void:
	say("down", true)
	Main.I.on_activity_success("dogfight")
	super()


func _draw() -> void:
	var xf := Transform2D(heading, Vector2.ZERO).scaled(Vector2(1.2, 1.2))
	var c := body_color(Color(0.95, 0.2, 0.25))
	if not draw_enemy_sprite("e_rival", 64.0):
		draw_colored_polygon(xf * PackedVector2Array([Vector2(20, 0), Vector2(-2, 5), Vector2(-8, 17), Vector2(-14, 5), Vector2(-16, 0), Vector2(-14, -5), Vector2(-8, -17), Vector2(-2, -5)]), c)
	draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 32, Color(1, 0.3, 0.3, 0.6), 2.0)
	if _aim > 0.0 or _shots > 0:
		draw_circle(xf * Vector2(32, 0), 6.0, Color(1.0, 0.9, 0.3))
	draw_string(Hud.ui_font(), Vector2(-100, -radius - 22.0), "«%s»" % callsign, HORIZONTAL_ALIGNMENT_CENTER, 200, 17, Color(1, 0.75, 0.75))
	draw_hp_bar()
