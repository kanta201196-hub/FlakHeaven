extends SceneTree
## Unit tests for `BuildOrder.newer`: the build-number order that decides whether the main
## menu offers a newer test build (Kanta 2026-10-25). Numbers compare in order, not as text
## ("s10" is later than "s9"); equal, empty or unparsable builds are never "newer".
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(BuildOrder.newer("3.5-s12", "3.5-s11"), "s12 after s11")
	_check(BuildOrder.newer("3.5-s10", "3.5-s9"), "s10 after s9 (numbers, not text)")
	_check(BuildOrder.newer("3.6-s1", "3.5-s11"), "minor version wins over build number")
	_check(not BuildOrder.newer("3.5-s11", "3.5-s11"), "same build is not newer")
	_check(not BuildOrder.newer("3.5-s9", "3.5-s11"), "older build is not newer")
	_check(not BuildOrder.newer("", "3.5-s11"), "empty build from the site is ignored")
	_check(not BuildOrder.newer("beta", "3.5-s11"), "build without numbers is ignored")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
