extends SceneTree
## Unit tests for `CardText.total_pct`: the «(всего +N%)» total on single-stat module cards
## (Sublight reference, Kanta 24.10, idea 3). The total is the bonus after taking the card,
## counted from the base 100%: multiplier now × (1 + step × rarity) − 1, rounded, signed.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(CardText.total_pct(1.0, 0.06, 1.0) == "+6%", "first pick shows its own bonus: %s" % CardText.total_pct(1.0, 0.06, 1.0))
	_check(CardText.total_pct(1.13, 0.06, 2.0) == "+27%", "stacks multiply with what is already there: %s" % CardText.total_pct(1.13, 0.06, 2.0))
	_check(CardText.total_pct(0.8, 0.1, 1.0) == "−12%", "a total below base gets a minus sign: %s" % CardText.total_pct(0.8, 0.1, 1.0))
	_check(CardText.total_pct(0.95, 0.05, 1.0) == "0%", "a zero total has no sign: %s" % CardText.total_pct(0.95, 0.05, 1.0))
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
