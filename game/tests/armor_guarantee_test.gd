extends SceneTree
## Unit tests for `CardBalance.armor_due`: GD-06 (Kanta 2026-10-25, option «б»), the «Бронеплиты»
## card is guaranteed in a card choice when the plane has none by level 10. Rules pinned here:
## not before level 10; never once the card is taken; after a guaranteed offer it waits
## ARMOR_EVERY choices before the next one, so a player who declines is not asked every time.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_not_before_level()
	_test_due_at_level()
	_test_not_when_taken()
	_test_waits_after_offer()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_not_before_level() -> void:
	_check(not CardBalance.armor_due(CardBalance.ARMOR_LVL - 1, 0, 8, 0), "level 9: not guaranteed yet")


func _test_due_at_level() -> void:
	_check(CardBalance.armor_due(CardBalance.ARMOR_LVL, 0, 9, 0), "level 10, no armor: guaranteed")
	_check(CardBalance.armor_due(30, 0, 29, 0), "level 30, no armor, never offered: guaranteed")


func _test_not_when_taken() -> void:
	_check(not CardBalance.armor_due(12, 1, 11, 0), "armor already taken: no guarantee")


func _test_waits_after_offer() -> void:
	var next := CardBalance.next_pick(10)
	_check(next == 10 + CardBalance.ARMOR_EVERY, "next guaranteed choice is ARMOR_EVERY picks later")
	_check(not CardBalance.armor_due(11, 0, 11, next), "declined at pick 10: not at pick 11")
	_check(CardBalance.armor_due(14, 0, next, next), "declined: guaranteed again at the next due pick")
