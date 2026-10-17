class_name GroundDrive
extends RefCounted
## Движение наземной машины без «перекатывания» (концепция конвоя, раздел 5; общий модуль — потом и для ПВО):
## скорость меняется плавно (разгон и торможение), колёсная машина поворачивает по дуге с радиусом,
## гусеничная ещё и медленно разворачивается на месте; на крутом повороте машина сама сбавляет ход.
## Хранит то, что нужно 3D для живой картинки: пройденный путь (качение колёс), руль, продольное ускорение
## (клевок носом при торможении) и скорость поворота (крен наружу).
## Как подключить: drive.pos — точка рельефа (Enemy.anchor), drive.heading — курс корпуса;
## каждый кадр — drive_to(точка, скорость, delta) или stop(delta), потом anchor = drive.pos.

var pos := Vector2.ZERO
var heading := 0.0
var speed := 0.0            # пикс./с, вперёд
var max_speed := 70.0
var accel := 45.0           # пикс./с²
var brake := 90.0
var turn_r := 60.0          # наименьший радиус поворота, пикс.
var pivot := 0.0            # разворот на месте, рад/с (гусеницы); 0 — колёсная
## для 3D
var dist := 0.0             # пройденный путь, пикс.
var steer := 0.0            # руль −1…1 (передние колёса)
var acc_now := 0.0          # продольное ускорение, пикс./с²
var yaw_rate := 0.0         # рад/с


func _init(p := Vector2.ZERO, h := 0.0) -> void:
	pos = p
	heading = h


## Скорость плавно к want (разгон accel, торможение brake)
func set_speed(want: float, delta: float) -> void:
	var was := speed
	speed = move_toward(speed, want, (accel if want > speed else brake) * delta)
	acc_now = lerpf(acc_now, (speed - was) / maxf(delta, 1e-4), 1.0 - exp(-delta * 8.0))


## Ехать к точке target со скоростью want (пикс./с); на крутом повороте машина сама сбавляет ход
func drive_to(target: Vector2, want: float, delta: float) -> void:
	var to := target - pos
	if to.length() < 1.0:
		stop(delta)
		return
	var err := wrapf(to.angle() - heading, -PI, PI)
	# поворот по дуге: чем медленнее едет, тем медленнее поворачивает; гусеницы — ещё и на месте
	var arc := absf(speed) / turn_r
	var yaw_max := arc + pivot
	var yaw := clampf(err * 2.5, -yaw_max, yaw_max)
	heading = wrapf(heading + yaw * delta, -PI, PI)
	yaw_rate = yaw
	steer = clampf(yaw / maxf(arc, 0.05), -1.0, 1.0) if arc > 0.01 else 0.0
	# цель сбоку или сзади — сбросить ход до скорости поворота
	var k := clampf(cos(err) * 1.2, 0.25 if pivot <= 0.0 else 0.0, 1.0)
	set_speed(minf(want, max_speed) * k, delta)
	_move(delta)


## Тормозить до полной остановки (корпус стоит, колёса не крутятся)
func stop(delta: float) -> void:
	yaw_rate = 0.0
	steer = move_toward(steer, 0.0, delta * 2.0)
	set_speed(0.0, delta)
	_move(delta)


## Повернуть корпус на месте к курсу (только гусеничные); колёсная — стоит
func face(angle: float, delta: float) -> void:
	if pivot <= 0.0 or absf(speed) > 2.0:
		stop(delta)
		return
	var was := heading
	heading = rotate_toward(heading, angle, pivot * delta)
	yaw_rate = wrapf(heading - was, -PI, PI) / maxf(delta, 1e-4)
	set_speed(0.0, delta)


func _move(delta: float) -> void:
	var step := speed * delta
	pos += Vector2.from_angle(heading) * step
	dist += step
