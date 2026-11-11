extends Node
## Unit tests for the lighter first sortie (PG-17): which sortie of a profile is light, which one marks the opened
## features «новое», that the F1 toggle at 0 and «Битва асов» keep everything as before, and that the second sortie's
## radio line only names what the player will see. Working part of first_sortie_test.gd.

var _failed := 0
var _checks := 0


func _ready() -> void:
	_check(FirstSortie.phase(0, true, false) == FirstSortie.LIGHT, "first sortie of a profile is light")
	_check(FirstSortie.phase(-3, true, false) == FirstSortie.LIGHT, "a broken counter below 0 reads as the first sortie")
	_check(FirstSortie.phase(1, true, false) == FirstSortie.NEW, "second sortie marks the opened features «новое»")
	_check(FirstSortie.phase(2, true, false) == FirstSortie.FULL, "third sortie: as before, no mark")
	_check(FirstSortie.phase(40, true, false) == FirstSortie.FULL, "veteran profile: as before")
	for n in [0, 1, 2]:
		_check(FirstSortie.phase(n, false, false) == FirstSortie.FULL, "toggle 0, sortie %d: as before PG-17" % n)
		_check(FirstSortie.phase(n, true, true) == FirstSortie.FULL, "«Битва асов», sortie %d: always full" % n)
	var with_tasks := FirstSortie.radio_line(true)
	var no_tasks := FirstSortie.radio_line(false)
	_check(with_tasks.contains("задания") and with_tasks.contains("звено"), "radio line names objectives and wing orders")
	_check(not no_tasks.contains("задания") and no_tasks.contains("Звено"), "no objectives in the operation: wing orders only")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
