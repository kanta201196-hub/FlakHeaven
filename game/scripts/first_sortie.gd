class_name FirstSortie
extends RefCounted
## PG-17 (genre research item 9, Kanta 11.11): a profile's very first sortie is lighter, so a newcomer learns to fly,
## shoot and pick cards before side goals and orders pile on. In it the operation's optional objectives
## (`OpTaskBalance`) and the wing orders (G, the pause selector) are hidden; fuel, the class task and the map
## activities stay. In the second sortie both come back marked «новое», and HQ says so on the radio once.
## The phase is worked out from the profile's finished-sortie counter (`Profile.data.sorties`, which grows only for
## sorties of 30 s and more, so a quick quit keeps the next one light) and kept for the whole sortie by `begin`,
## because the counter itself grows at the sortie's end. «Битва асов» is not a newcomer's mode: always full.

## First sortie: objectives and wing orders hidden.
const LIGHT := 0
## Second sortie: everything shown, marked «новое».
const NEW := 1
## From the third sortie on, or with the F1 toggle at 0: as before PG-17.
const FULL := 2

static var _phase := FULL


## The phase for a profile that has finished `sorties` sorties; `toggle_on` is the F1 toggle, `aces` the «Битва асов»
## mode. Pure, so it is unit-tested (`first_sortie_test.gd`).
static func phase(sorties: int, toggle_on: bool, aces: bool) -> int:
	if not toggle_on or aces:
		return FULL
	if sorties <= 0:
		return LIGHT
	return NEW if sorties == 1 else FULL


## The radio line HQ says at the start of the second sortie: what has opened. `has_tasks` — the operation has side
## objectives this sortie (the sea biome has none yet), so the line only names what the player will actually see.
static func radio_line(has_tasks: bool) -> String:
	if has_tasks:
		return "Сегодня у операции есть свои задания — смотрите список целей, за каждое запчасти. И звено теперь слушает приказы: кого бить первым."
	return "Звено теперь слушает приказы: кого бить первым. Плитка «Звено» внизу и пауза."


## F1 toggle `first_sortie` (R-22: on by default, 0 — the first sortie as before PG-17).
static func on() -> bool:
	return Tuning.g("first_sortie") >= 1.0


## Fixes the phase for the sortie that starts now.
static func begin(sorties: int, aces: bool) -> void:
	_phase = phase(sorties, on(), aces)


## The current sortie is the light first one.
static func light() -> bool:
	return _phase == LIGHT


## The current sortie is the second one: the opened features carry the «новое» mark.
static func fresh() -> bool:
	return _phase == NEW


## The phase of the sortie the player is preparing now (mission screen, before `begin`).
static func upcoming() -> int:
	return phase(int(Profile.data.get("sorties", 0)), on(), false)
