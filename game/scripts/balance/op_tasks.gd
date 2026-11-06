class_name OpTaskBalance
extends RefCounted
## OT-01 (Kanta 06.11: «содержание операций должно иметь задания внутренние, которые соответствуют их сути, помимо
## основной»): each Highlands operation has two side objectives that tell what the operation is about, and its own
## order of map activities so the objectives' activities come often enough. Objectives are optional: the operation is
## passed by its main goal (`Campaign.OPS[].need`) as before; each objective done pays `PARTS` once per sortie, the
## campaign save remembers which were ever done (✓ on the operation card).
## No timers: the skill's rule «no forced timer goals». The sea biome is on hold (Kanta 24.10) — common queue, no
## objectives. Needs are first guesses: in the s16 log a 16-minute sortie finished 13 activities (≈ 2 per queue slot
## of a 6-slot queue), a weaker run ~8–10.

## Parts for each objective done (before the post-15:00 multiplier and medal bonus, like activity parts).
const PARTS := 60.0

## Objectives by operation id. `act` — the activity kind (Spawner.ACTIVITIES) whose success counts; `need` — how many;
## `brief` — the line on the operation card; `hud` — the combat panel line with «%d из %d».
const TASKS := {
	"pass": [
		{"id": "convoys", "act": "convoy", "need": 3, "brief": "Сжечь 3 колонны противника на дороге", "hud": "колонны %d из %d"},
		{"id": "aa", "act": "ground", "need": 2, "brief": "Подавить 2 позиции ПВО у перевала", "hud": "позиции ПВО %d из %d"},
	],
	"riverbed": [
		{"id": "aa", "act": "ground", "need": 3, "brief": "Подавить 3 позиции ПВО в руслах", "hud": "позиции ПВО %d из %d"},
		{"id": "convoys", "act": "convoy", "need": 2, "brief": "Перехватить 2 колонны с ракетами для ПВО", "hud": "колонны %d из %d"},
	],
	"forts": [
		{"id": "forts", "act": "fort", "need": 3, "brief": "Разгромить 3 укрепрайона в старых крепостях", "hud": "укрепрайоны %d из %d"},
		{"id": "convoys", "act": "convoy", "need": 2, "brief": "Сжечь 2 колонны снабжения крепостей", "hud": "колонны %d из %d"},
	],
	"sky": [
		{"id": "duels", "act": "dogfight", "need": 2, "brief": "Выиграть 2 дуэли с вражескими асами", "hud": "дуэли %d из %d"},
		{"id": "transports", "act": "transport", "need": 2, "brief": "Сбить 2 транспортника с подкреплением", "hud": "транспортники %d из %d"},
	],
}

## Activity order by operation id: the objectives' kinds take two slots of six, the rest one or none. An operation
## missing here uses `Spawner.ACTIVITIES`. «Укрепрайон» falls back to the next kind when no fort is in reach.
const QUEUE := {
	"pass": ["convoy", "ground", "dogfight", "convoy", "transport", "ground", "fort"],
	"riverbed": ["ground", "convoy", "dogfight", "ground", "transport", "convoy", "fort"],
	"forts": ["fort", "convoy", "ground", "fort", "dogfight", "convoy", "transport"],
	"sky": ["dogfight", "transport", "convoy", "dogfight", "ground", "transport"],
}


## Objectives of operation `op_id` (empty when it has none).
static func tasks(op_id: String) -> Array:
	return TASKS.get(op_id, [])


## Activity order of operation `op_id`.
static func queue(op_id: String) -> Array:
	return QUEUE.get(op_id, Spawner.ACTIVITIES)


## F1 toggle `op_tasks` (R-22: a new feel stays switchable until Kanta's «ок»): 1 — objectives and the operation's
## queue, 0 — as in s16.
static func on() -> bool:
	return Tuning.g("op_tasks") >= 1.0
