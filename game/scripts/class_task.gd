class_name ClassTask
extends RefCounted
## EX-07: задание класса в брифинге операции (вариант 2, решение Kanta 21.10).
## У каждого класса своя задача на вылет: «Оса» перехватывает бомбардировщики до 12:00,
## «Грач» давит ПВО, «Кит» жжёт колонны. Выполнил — выбор из редких карточек и запчасти
## (`Rewards.ACTIVITY[&"class_task"]`, платит `RunState`).
## Видно в брифинге (все три) и в бою (строка в правой панели).

const DEFS := {
	"fighter": {"brief": "«Оса»: сбить 4 бомбардировщика до 12:00", "hud": "Бомбардировщики %d из %d", "need": 4, "until": 720.0},
	"attacker": {"brief": "«Грач»: подавить 8 установок ПВО", "hud": "Установки ПВО %d из %d", "need": 8, "until": 0.0},
	"bomber": {"brief": "«Кит»: сжечь 10 машин колонн", "hud": "Машины колонн %d из %d", "need": 10, "until": 0.0},
}

var cls := ""
var n := 0
var state := ""   # "" — идёт, "done", "failed"


func _init(cls_id: String) -> void:
	cls = cls_id if DEFS.has(cls_id) else ""


func need() -> int:
	return int(DEFS[cls]["need"]) if cls != "" else 0


func _counts(e: Enemy) -> bool:
	match cls:
		"fighter":
			return e is Bomber
		"attacker":
			return e is GroundTarget
		"bomber":
			return e is ConvoyVehicle
	return false


func on_kill(m: Main, e: Enemy) -> void:
	if state != "" or cls == "" or not _counts(e):
		return
	n += 1
	if n < need():
		return
	state = "done"
	m.tele.v["class_task_t"] = m.run_time
	if OS.get_cmdline_user_args().has("--autotest"):
		print("AUTOTEST: class task done at %.0f" % m.run_time)
	Events.activity_succeeded.emit(&"class_task")   # reward, banner and sound: Main / RunState
	Events.radio.emit("Штаб", "Задание выполнено, отличная работа. Награда ваша.", false)


func update(m: Main) -> void:
	if state != "" or cls == "":
		return
	var until := float(DEFS[cls]["until"])
	if until > 0.0 and m.run_time >= until:
		state = "failed"
		Events.banner.emit("Задание класса не выполнено — срок вышел", 3.0)


## Строка для правой панели в бою
func hud_line() -> String:
	if cls == "":
		return ""
	if state == "done":
		return Loc.t("✓ задание класса выполнено")
	if state == "failed":
		return Loc.t("задание класса: срок вышел")
	var s := Loc.t(String(DEFS[cls]["hud"])) % [n, need()]
	var until := float(DEFS[cls]["until"])
	if until > 0.0:
		s += Loc.t(" до %d:00") % int(until / 60.0)
	return s
