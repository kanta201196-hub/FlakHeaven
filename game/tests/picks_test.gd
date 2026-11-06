extends SceneTree
## Unit tests for `PickBalance` (S16-22): crew ranks add rerolls, bans and pins cumulatively, and each rank reports
## what it opens. Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(PickBalance.crew(1) == {"rerolls": 0, "bans": 0, "pins": 0}, "rank 1 adds nothing")
	_check(PickBalance.crew(4)["rerolls"] == 1, "rank 4: +1 reroll")
	var c := PickBalance.crew(20)
	_check(c["rerolls"] == 2 and c["bans"] == 1 and c["pins"] == 1, "rank 20: +2 rerolls, +1 ban, +1 pin (%s)" % c)
	_check(PickBalance.crew_at(8) == ["pins"] and PickBalance.crew_at(9).is_empty(), "rank 8 opens a pin, rank 9 nothing")
	_check(PickBalance.ACTIVITY_REROLLS >= 1, "an activity pays at least one reroll")
	for m in ["scout", "planner"]:
		_check(not MedalBalance.by_id(m).is_empty(), "medal %s exists" % m)
	_check(MedalBalance.PIECES.has("pins"), "pins counted in pieces")
	var b := MedalBalance.bonuses({"scout": 3, "planner": 2})
	_check(int(b.get("rerolls", 0)) == 3 and int(b.get("bans", 0)) == 2, "medal tiers give rerolls and bans (%s)" % b)
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
