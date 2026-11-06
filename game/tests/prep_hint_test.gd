extends SceneTree
## Unit tests for `PrepHint` (06.11 sortie review, point 4): the «можно улучшить самолёт» reminder shows only for a plane
## with zero upgrades when the parts pay for the cheapest node.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(PrepHint.upgrade_due([0, 0, 0, 0, 0, 0], 80, 80), "no upgrades, parts for one node: remind")
	_check(PrepHint.upgrade_due([0, 0, 0, 0, 0, 0], 10600, 80), "no upgrades, many parts: remind")
	_check(not PrepHint.upgrade_due([0, 0, 0, 0, 0, 0], 79, 80), "no upgrades, too few parts: silent")
	_check(not PrepHint.upgrade_due([0, 1, 0, 0, 0, 0], 10600, 80), "one node upgraded: silent")
	_check(PrepHint.upgrade_due([], 80, 80), "no nodes listed counts as no upgrades")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
