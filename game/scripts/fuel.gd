class_name Fuel
extends Node
## 3.5: топливо в вылете (решение владельца 16.10.2026: «Бак 9 минут»).
## Бак на 9 минут полёта, форсаж тратит вдвое быстрее. Когда в баке остаётся 20% (~7-я минута),
## прилетает свой заправщик (Tanker); не успел или его сбили — следующий через 2 минуты.
## Пустой бак: скорость −30% и без форсажа, но самолёт не падает.
## Живёт внутри спавнера (новый вылет — новый бак).

const CAPACITY := 540.0        # секунд полёта на полном баке
const AB_BURN := 2.0           # форсаж: расход ×2
const CALL_AT := 0.2           # доля бака, при которой вызывается заправщик (~7-я минута без форсажа)
const RETRY := 120.0           # следующий заправщик после промаха, с
const EMPTY_SPEED := 0.7

var left := CAPACITY
var tanker: Tanker = null
var _retry_t := 0.0
var _warned := false
var _empty_said := false
var refuels := 0


func _process(delta: float) -> void:
	var m := Main.I
	var p := m.player
	if p == null or p.hp <= 0.0 or m.state != "playing":
		return
	var burn := AB_BURN if p.ab_t > 0.0 else 1.0
	left = maxf(0.0, left - delta * burn)
	m.tele.add("fuel_ab_s", delta if p.ab_t > 0.0 else 0.0)
	if left <= 0.0:
		m.tele.add("fuel_empty_s", delta)
		if not _empty_said:
			_empty_said = true
			m.show_banner("Бак пуст! Скорость −30%, форсажа нет — ждите заправщик", 4.0)
			m.sfx.play("lock", -4.0, 0.5)
	elif frac() < 0.1 and not _warned:
		_warned = true
		m.show_banner("Топливо на исходе", 3.0)
	_retry_t -= delta
	if not is_instance_valid(tanker) and frac() <= CALL_AT and _retry_t <= 0.0:
		_call_tanker(p)


func frac() -> float:
	return left / CAPACITY


func empty() -> bool:
	return left <= 0.0


## Заправка: amount — доля бака
func add(amount: float) -> void:
	left = minf(CAPACITY, left + CAPACITY * amount)
	if left > 0.0:
		_empty_said = false
	if frac() > 0.1:
		_warned = false


func on_tanker_gone(refueled: bool) -> void:
	if refueled:
		refuels += 1
		Main.I.tele.add("fuel_refuels")
	else:
		_retry_t = RETRY
		Main.I.tele.add("fuel_tankers_missed")


func _call_tanker(p: Player) -> void:
	tanker = Tanker.new()
	tanker.setup(p, self)
	Main.I.world.add_child(tanker)
	Main.I.show_banner("Заправщик на подходе! Зайдите ему в хвост и держитесь за ним", 4.0)
	Main.I.sfx.play("evac", -8.0, 0.8)
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: tanker called at %.0f, fuel %.0f%%" % [Main.I.run_time, frac() * 100.0])


# ---------- для игрока (player.gd) ----------

static func current() -> Fuel:
	var m := Main.I
	if m == null or m.spawner == null or not is_instance_valid(m.spawner) or m.spawner.fuel == null:
		return null
	return m.spawner.fuel


## Множитель крейсерской скорости: на пустом баке −30%
static func speed_k() -> float:
	var f := current()
	return EMPTY_SPEED if f != null and f.empty() else 1.0


static func can_afterburn() -> bool:
	var f := current()
	return f == null or not f.empty()
