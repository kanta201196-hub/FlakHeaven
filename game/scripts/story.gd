class_name Story
extends RefCounted
## EX-09 (Kanta «Б — делай», 22.10): радио и сквозная линия «Где Гром?» в кампании Нагорья.
## Тексты — таблица `StoryText` и docs/playtest/external-2/ex09-story-texts.md (номера строк там же).
## Радио идёт очередью: строка ждёт, пока погаснет предыдущая (не дольше 3 с), бой не останавливается.
## Прогресс линии — в сохранении кампании: rescued (спасён сбитый пилот), grom_free («Гром» на свободе).

const DISPATCH := StoryText.DISPATCH
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
	_ground_said = false
	_hq_met = -1
	rescue_done = false
	var op := highland_op()
	say(DISPATCH, StoryText.radio("start.pass" if op <= OP_PASS else "start.other"))
	if op >= 0 and Tuning.g("story_accents") > 0.0:
		m.sfx.play("sting_start", -8.0)   # step 4: the operation's opening hit (file optional)
	if m.class_task != null and m.class_task.cls != "":
		say(DISPATCH, Loc.t(StoryText.radio("task")) % Loc.t(String(ClassTask.DEFS[m.class_task.cls]["brief"])))


static func tick(m: Main) -> void:
	if not _baron_taunt and highland_op() == OP_PASS and m.run_time >= 480.0:
		_baron_taunt = true
		say("Барон", StoryText.radio("baron.taunt"), true)
	# S9-17: вылет начинается без ведомых — «Гром» догоняет звено на 3-й минуте
	if not _grom_in and highland_op() == OP_SKY and Campaign.flag("grom_free") and m.run_time >= GROM_AT:
		_grom_in = true
		m.player.add_wingman("swift", 2.0)
		say("Гром", StoryText.radio("grom.join"))
		Cinematic.accent(m, "grom", StoryText.accent("grom"))
	if not _finale and highland_op() == OP_SKY and Campaign.flag("grom_free") and m.op_flags.get("fortress", false):
		_finale = true
		say("Гром", StoryText.radio("grom.finale"))
	# строка ждёт конца предыдущей, но не дольше 3 с — болтовня ведомых её не перебивает
	if not _queue.is_empty() and (m.hud.radio_t <= 0.3 or Time.get_ticks_msec() - int(_queue[0][3]) > 3000):
		var l: Array = _queue.pop_front()
		Events.radio.emit(l[0], l[1], l[2])


## «Крепость» на подходе (шаг 6): «Купол» впервые видит летающий штаб (оп. 2), штаб отвечает своей репликой
## (`StoryText.OP_LINES` "hq.<op>.arrive", красная рамка); счётчик встреч — `Campaign.met("hq")`
static func on_fortress_sight() -> void:
	var op := highland_op()
	if op < 0 or _hq_met >= 0:
		return
	_hq_met = Campaign.met("hq")
	Campaign.on_met("hq")
	if op == OP_RIVER:
		say(DISPATCH, StoryText.radio("fortress.sight.riverbed"))
	hq_line("arrive")


## Реплика контролёра «Крепости» для момента `moment` этой операции (пусто — молчит)
static func hq_line(moment: String) -> void:
	var op := highland_op()
	if op < 0 or _hq_met < 0:
		return
	var line := StoryText.op_line("hq", String(Campaign.op()["id"]), moment, _hq_met)
	if line != "":
		say(StoryText.ENEMY_HQ, line, true)


static var _hq_met := -1   # встреч с «Крепостью» до этого вылета; -1 — в этом вылете она ещё не появлялась


## Первая позиция ПВО в «Перевале» — «Купол» замечает, что противник строит (шаг 5; один раз за вылет)
static func on_ground_site() -> void:
	if highland_op() == OP_PASS and not _ground_said:
		_ground_said = true
		say(DISPATCH, StoryText.radio("ground.pass"))


static var _ground_said := false


## Сбит «Барон» в «Крепостях» — «Гром» жив, в финальной операции он летит в звене
static func on_baron_down() -> void:
	if highland_op() == OP_FORTS and not Campaign.flag("grom_free"):
		Campaign.set_flag("grom_free")
		say(DISPATCH, StoryText.radio("grom.alive"))


## Активность «Сбитый пилот» — один раз за вылет в «Сухом русле» (первая активность вылета)
static func wants_rescue() -> bool:
	return highland_op() == OP_RIVER and not rescue_done
