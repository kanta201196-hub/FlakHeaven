extends SceneTree
## Unit tests for `AcesBalance`: the «Битва асов» test mode (Kanta 2026-10-26, AB-01). Rules pinned here:
## three missiles kill the player, two long bursts of an ace kill the player, other damage is untouched;
## the ace schedule (first, interval, at most two at once); spawn caps per enemy kind.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_missiles()
	_test_bursts()
	_test_other_damage()
	_test_ace_schedule()
	_test_caps()
	_test_score()
	_test_turn_look()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _hits_to_kill(source: String, max_hp: float, who := "") -> int:
	var hp := max_hp
	var n := 0
	while hp > 0.0 and n < 100:
		hp -= AcesBalance.player_hit(source, 1.0, max_hp, who)
		n += 1
	return n


func _test_missiles() -> void:
	for max_hp in [120.0, 160.0, 250.0]:
		_check(_hits_to_kill("ракеты", max_hp) == 3, "3 missiles kill at max hp %.0f" % max_hp)
	_check(is_equal_approx(AcesBalance.player_hit("ракеты", 999.0, 120.0), AcesBalance.player_hit("ракеты", 1.0, 120.0)),
		"missile damage does not depend on the missile's own number")


func _test_bursts() -> void:
	var n := _hits_to_kill("пули", 120.0, "ас-соперник")
	# an ace burst is 5 rounds; two long bursts with a miss or two = 8–10 hits
	_check(n >= 8 and n <= 10, "two long ace bursts kill (%d hits)" % n)
	var light := _hits_to_kill("пули", 172.0, "перехватчики")
	# s12: two interceptors killed «Оса» in 78 s before any ace; their guns must not be ace guns
	_check(light >= 20, "interceptor guns need 20+ hits (%d)" % light)


func _test_other_damage() -> void:
	_check(is_equal_approx(AcesBalance.player_hit("прочее", 7.0, 120.0), 7.0), "unknown source keeps its damage")
	_check(_hits_to_kill("таран", 120.0) == 2, "two rams kill")


func _test_ace_schedule() -> void:
	_check(not AcesBalance.ace_due(AcesBalance.ACE_FIRST - 1.0, AcesBalance.ACE_FIRST, 0), "no ace before the first time")
	_check(AcesBalance.ace_due(AcesBalance.ACE_FIRST, AcesBalance.ACE_FIRST, 0), "first ace on time")
	_check(AcesBalance.ace_due(100.0, 90.0, AcesBalance.ACE_MAX - 1), "second ace while one is up")
	_check(not AcesBalance.ace_due(100.0, 90.0, AcesBalance.ACE_MAX), "never more than ACE_MAX aces")
	_check(AcesBalance.ACE_EVERY < 60.0, "aces come more often than once a minute")


func _test_caps() -> void:
	_check(AcesBalance.needs("interceptor", AcesBalance.INTERCEPTOR_MAX - 1), "room for an interceptor")
	_check(not AcesBalance.needs("interceptor", AcesBalance.INTERCEPTOR_MAX), "interceptors capped")
	_check(AcesBalance.CARRIER_MAX > AcesBalance.INTERCEPTOR_MAX, "more missile carriers than interceptors")
	_check(AcesBalance.ACE_MAX >= AcesBalance.INTERCEPTOR_MAX + AcesBalance.CARRIER_MAX,
		"s12: aces are at least half of the sky, not the escorts")
	_check(AcesBalance.ACE_FLARE_CHANCE < 0.8 and AcesBalance.ACE_FLARE_CHARGES < 3, "aces flare less than in the campaign")
	_check(not AcesBalance.needs("drone", 0), "no drones in the mode")
	_check(AcesBalance.ACE_HP > AcesBalance.CARRIER_HP and AcesBalance.CARRIER_HP > AcesBalance.INTERCEPTOR_HP,
		"ace > carrier > interceptor")


func _test_score() -> void:
	var r := RunState.new()
	r.on_rival_down()
	r.on_rival_down()
	r.on_rival_gone()
	_check(r.aces_down == 2 and r.aces_gone == 1, "aces shot down and gone are counted apart")
	_check(r.pending_levels == 0 and r.rare_picks == 0, "a downed ace gives no card pick in the mode")


func _test_turn_look() -> void:
	_check(AcesBalance.bank_rate(0.0, 0.8) == AcesBalance.BANK_IN_RATE, "rolls into a turn fast from level")
	_check(AcesBalance.bank_rate(0.3, 0.8) == AcesBalance.BANK_IN_RATE, "rolls deeper fast")
	_check(AcesBalance.bank_rate(0.8, 0.1) == AcesBalance.BANK_OUT_RATE, "levels out slowly")
	_check(AcesBalance.bank_rate(0.5, -0.5) == AcesBalance.BANK_OUT_RATE, "reversing the turn first levels out slowly")
	_check(AcesBalance.BANK_IN_RATE > AcesBalance.BANK_OUT_RATE, "roll-in faster than roll-out")
	_check(deg_to_rad(AcesBalance.BANK_VIS_DEG) > 0.55 and AcesBalance.BANK_VIS_DEG < 90.0, "deeper bank than the campaign, never fully on its side")
	var turn := 210.0 * AcesBalance.TURN_K
	_check(turn >= 90.0 and turn <= 120.0, "«Оса» turns about 100°/s like Sky Knights (%.0f)" % turn)
