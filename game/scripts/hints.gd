class_name Hints
extends RefCounted
## U-02/U-03: подсказки новичку — по одной, в момент, когда это нужно, и не больше заданного числа раз.
## Счётчики показов — user://hints.cfg (секция «seen»). Текст рисует HudFlight (строка над нижней подсказкой).

const PATH := "user://hints.cfg"

static var _cfg: ConfigFile = null
static var text := ""
static var t := 0.0
static var _queue: Array = []   # [[id, текст, длительность], …]


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	_cfg.load(PATH)


static func seen(id: String) -> int:
	_load()
	return int(_cfg.get_value("seen", id, 0))


## Показать подсказку, если её показывали меньше times раз. Занято — в очередь.
static func show(id: String, s: String, dur := 7.0, times := 1) -> void:
	if seen(id) >= times:
		return
	for q in _queue:
		if q[0] == id:
			return
	_cfg.set_value("seen", id, seen(id) + 1)
	_cfg.save(PATH)
	if Main.I != null and Main.I._autotest:
		print("HINT %s: %s" % [id, s])
	_queue.append([id, s, dur])
	if t <= 0.0:
		_next()


static func _next() -> void:
	if _queue.is_empty():
		text = ""
		return
	var q: Array = _queue.pop_front()
	text = q[1]
	t = float(q[2])


static func tick(delta: float) -> void:
	if t > 0.0:
		t -= delta
		if t <= 0.0:
			_next()


## Отметить показ без текста в бою (объяснения на экранах выбора); возвращает номер показа
static func bump(id: String) -> int:
	var n := seen(id) + 1
	_cfg.set_value("seen", id, n)
	_cfg.save(PATH)
	return n


## Сбросить очередь (новый вылет)
static func clear() -> void:
	_queue.clear()
	text = ""
	t = 0.0


## Показать все подсказки заново (кнопка в настройках)
static func reset() -> void:
	_load()
	_cfg.clear()
	_cfg.save(PATH)
