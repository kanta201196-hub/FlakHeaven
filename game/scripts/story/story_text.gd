class_name StoryText
extends RefCounted
## All story strings of the Highlands campaign in one table (plan step 1: skeleton; steps 5–8 fill the operations).
## Keys follow `StoryFlags.line_key` (speaker.op.moment). Russian is the source language; the HUD translates at
## draw time (`Loc.out`), so the lines stay plain Russian here and in `.po`. Design: `docs/story/highlands-storyline.md`.

const DISPATCH := "Купол"
## The Fortress controller: an enemy voice (red frame), unlike «Купол» who talks for our base.
const ENEMY_HQ := "Штаб «Монолита»"

## Radio of `story.gd` (EX-09 «Где Гром?»), by moment.
const RADIO := {
	"start.pass": "Звено, небо ваше. Колонна идёт по графику — не дайте её тронуть.",
	"start.other": "Разведка видит движение у перевала. Держитесь выше хребта.",
	"task": "Задание для вас: %s.",
	"baron.taunt": "Ваш ведущий падал красиво. Посмотрим, как упадёте вы.",
	"grom.join": "Звено, я снова в строю. Должок за мной.",
	"grom.finale": "Небо над Шахрисангом наше. Спасибо, что не бросили.",
	"grom.alive": "Перехват из крепости: «Гром» жив! Наземные идут за ним.",
}

## Per-operation lines of recurring enemy pilots («Почтальон», «Сквозняк») and the Fortress controller:
## key → Array of lines; index by `StoryFlags.line_index(met, n)`. Filled in steps 5–8; empty means «use the
## generic line of the unit».
const OP_LINES := {}


## Radio line by key, or "" when the table has none (callers fall back to their generic lines).
static func radio(key: String) -> String:
	return String(RADIO.get(key, ""))


## Line of a recurring pilot for this operation and moment, chosen by how often the player met them.
static func op_line(speaker: String, op_id: String, moment: String, met: int) -> String:
	var arr: Array = OP_LINES.get(StoryFlags.line_key(speaker, op_id, moment), [])
	if arr.is_empty():
		return ""
	return String(arr[StoryFlags.line_index(met, arr.size())])
