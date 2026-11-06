extends SceneTree
## Unit tests for `FlightBalance` soft bank (Kanta 2026-11-06: the plane rolls out of a turn too fast).
## Rules pinned here: with the toggle on, the visible bank rolls in a little slower and levels out clearly
## slower than the flight bank it follows; the multipliers never speed it up; off, it is the flight rate as is.
## Run from the repository root: `tools/ci/unit.sh`.

const DT := 1.0 / 60.0

var _failed := 0
var _checks := 0


func _init() -> void:
	_rates()
	_settle_times()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _rates() -> void:
	var r_in := FlightBalance.vis_bank_rate(0.0, 0.8, 11.0, 11.0, FlightBalance.SOFT_IN_K, FlightBalance.SOFT_OUT_K)
	var r_out := FlightBalance.vis_bank_rate(0.8, 0.0, 11.0, 11.0, FlightBalance.SOFT_IN_K, FlightBalance.SOFT_OUT_K)
	_check(is_equal_approx(r_in, 11.0 * FlightBalance.SOFT_IN_K), "rolls in at rate × SOFT_IN_K")
	_check(is_equal_approx(r_out, 11.0 * FlightBalance.SOFT_OUT_K), "levels out at rate × SOFT_OUT_K")
	_check(r_out < r_in, "levels out slower than it rolls in")
	_check(FlightBalance.SOFT_IN_K < 1.0 and FlightBalance.SOFT_IN_K >= 0.6, "roll-in only a little slower")
	_check(FlightBalance.SOFT_OUT_K < FlightBalance.SOFT_IN_K and FlightBalance.SOFT_OUT_K >= 0.35, "level-out slower, still settles")
	var rev := FlightBalance.vis_bank_rate(0.5, -0.5, 10.0, 3.5, 0.75, 0.5)
	_check(is_equal_approx(rev, 3.5 * 0.5), "reversing the turn first levels out (aces out rate × k)")
	_check(is_equal_approx(FlightBalance.vis_bank_rate(0.2, 0.9, 10.0, 3.5, 2.0, 2.0), 10.0), "multipliers never speed it up")
	_check(is_equal_approx(FlightBalance.vis_bank_rate(0.2, 0.9, 10.0, 3.5, 0.0, 0.0), 10.0 * FlightBalance.MIN_K), "never freezes")


## Time for the visible bank to come back from full to 10 % after the turn ends: longer with soft bank,
## yet under 1 s for the fighter (it still reads as one motion, not a drift).
func _settle_times() -> void:
	var hard := _settle(11.0, 1.0, 1.0)
	var soft := _settle(11.0, FlightBalance.SOFT_IN_K, FlightBalance.SOFT_OUT_K)
	_check(soft > hard * 1.4, "fighter levels out clearly slower (%.2f s vs %.2f s)" % [soft, hard])
	_check(soft < 1.0, "fighter still levels out within 1 s (%.2f s)" % soft)


func _settle(rate: float, k_in: float, k_out: float) -> float:
	var b := 1.0
	var t := 0.0
	while absf(b) > 0.1 and t < 10.0:
		var r := FlightBalance.vis_bank_rate(b, 0.0, rate, rate, k_in, k_out)
		b = lerpf(b, 0.0, 1.0 - exp(-DT * r))
		t += DT
	return t


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: " + what)
