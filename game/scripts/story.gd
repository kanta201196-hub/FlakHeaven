class_name Story
extends RefCounted
## EX-09 (Kanta «Б — делай», 22.10): радио и сквозная линия «Где Гром?» в кампании Нагорья.
## Тексты — docs/playtest/external-2/ex09-story-texts.md (номера строк там же).
## Радио идёт очередью: строка ждёт, пока погаснет предыдущая (не дольше 3 с), бой не останавливается.
## Прогресс линии — в сохранении кампании: rescued (спасён сбитый пилот), grom_free («Гром» на свободе).

const DISPATCH := "Купол"
const GROM_AT := 180.0

## Операции Нагорья по порядку: «Перевал», «Сухое русло», «Крепости», «Небо над Шахрисангом»
const OP_PASS := 0
const OP_RIVER := 1
const OP_FORTS := 2
const OP_SKY := 3

static var _queue: Array = []
static var _baron_taunt := false
static var _finale := false
static var _grom_in := false
static var rescue_done := false   # активность «Сбитый пилот» уже была в этом вылете


static func highland_op() -> int:
	if Campaign.biome_of(Campaign.index()) != Biome.HIGHLAND:
		return -1
	return Campaign.index()


static func say(from: String, text: String, enemy := false) -> void:
	_queue.append([from, text, enemy, Time.get_ticks_msec()])


## Начало вылета: приветствие «Купола» и задание класса
static func start(m: Main) -> void:
	_queue.clear()
	_baron_taunt = false
	_finale = false
	_grom_in = false
	rescue_done = false
	var op := highland_op()
	say(DISPATCH, "Звено, небо ваше. Колонна идёт по графику — не дайте её тронуть." if op <= OP_PASS else "Разведка видит движение у перевала. Держитесь выше хребта.")
	if m.class_task != null and m.class_task.cls != "":
		say(DISPATCH, Loc.t("Задание для вас: %s.") % Loc.t(String(ClassTask.DEFS[m.class_task.cls]["brief"])))


static func tick(m: Main) -> void:
	if not _baron_taunt and highland_op() == OP_PASS and m.run_time >= 480.0:
		_baron_taunt = true
		say("Барон", "Ваш ведущий падал красиво. Посмотрим, как упадёте вы.", true)
	# S9-17: вылет начинается без ведомых — «Гром» догоняет звено на 3-й минуте
	if not _grom_in and highland_op() == OP_SKY and Campaign.flag("grom_free") and m.run_time >= GROM_AT:
		_grom_in = true
		m.player.add_wingman("swift", 2.0)
		say("Гром", "Звено, я снова в строю. Должок за мной.")
	if not _finale and highland_op() == OP_SKY and Campaign.flag("grom_free") and m.op_flags.get("fortress", false):
		_finale = true
		say("Гром", "Небо над Шахрисангом наше. Спасибо, что не бросили.")
	# строка ждёт конца предыдущей, но не дольше 3 с — болтовня ведомых её не перебивает
	if not _queue.is_empty() and (m.hud.radio_t <= 0.3 or Time.get_ticks_msec() - int(_queue[0][3]) > 3000):
		var l: Array = _queue.pop_front()
		Events.radio.emit(l[0], l[1], l[2])


## Сбит «Барон» в «Крепостях» — «Гром» жив, в финальной операции он летит в звене
static func on_baron_down() -> void:
	if highland_op() == OP_FORTS and not Campaign.flag("grom_free"):
		Campaign.set_flag("grom_free")
		say(DISPATCH, "Перехват из крепости: «Гром» жив! Наземные идут за ним.")


## Активность «Сбитый пилот» — один раз за вылет в «Сухом русле» (первая активность вылета)
static func wants_rescue() -> bool:
	return highland_op() == OP_RIVER and not rescue_done
