extends SceneTree
## Unit tests for `AcesBalance`: the «Битва асов» test mode (Kanta 2026-10-26, AB-01). Rules pinned here:
## three missiles kill the player, two long bursts of an ace kill the player, other damage is untouched;
## the ace schedule (first, interval, at most two at once); spawn caps per enemy kind; AB-03 (Kanta 04.11):
## a rival ace takes at least ACE_MISSILES of the player's missiles, sees a ram coming, launches only ahead in range.
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
	_test_build_loop()
	_test_ace_missile_cap()
	_test_collision_ahead()
	_test_ace_launch()
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
	_check(r.pending_levels == 0 and r.rare_picks == 0, "on_rival_down queues no pick itself (Main adds AcesBalance.ace_picks)")


func _test_turn_look() -> void:
	_check(AcesBalance.bank_rate(0.0, 0.8) == AcesBalance.BANK_IN_RATE, "rolls into a turn fast from level")
	_check(AcesBalance.bank_rate(0.3, 0.8) == AcesBalance.BANK_IN_RATE, "rolls deeper fast")
	_check(AcesBalance.bank_rate(0.8, 0.1) == AcesBalance.BANK_OUT_RATE, "levels out slowly")
	_check(AcesBalance.bank_rate(0.5, -0.5) == AcesBalance.BANK_OUT_RATE, "reversing the turn first levels out slowly")
	_check(AcesBalance.BANK_IN_RATE > AcesBalance.BANK_OUT_RATE, "roll-in faster than roll-out")
	_check(deg_to_rad(AcesBalance.BANK_VIS_DEG) > 0.55 and AcesBalance.BANK_VIS_DEG < 90.0, "deeper bank than the campaign, never fully on its side")
	var turn := 210.0 * AcesBalance.TURN_K
	_check(turn >= 90.0 and turn <= 120.0, "«Оса» turns about 100°/s like Sky Knights (%.0f)" % turn)


func _test_build_loop() -> void:
	# option 1 (Kanta 26.10): a draft before takeoff, a card per ace shot down, a cap per sortie
	var r := RunState.new()
	r.add_picks(AcesBalance.DRAFT_PICKS)
	_check(r.pending_levels == 8 and r.rare_picks == 0, "8 ordinary picks before takeoff")
	var total := AcesBalance.DRAFT_PICKS
	for n in range(1, 30):
		var k := AcesBalance.ace_picks(n)
		if n == 1:
			_check(k == 1, "the first ace gives a card")
		total += k
	_check(total == AcesBalance.CARDS_MAX, "never more than %d cards per sortie (%d)" % [AcesBalance.CARDS_MAX, total])
	r.add_picks(-3)
	_check(r.pending_levels == 8, "negative picks are ignored")


func _test_ace_missile_cap() -> void:
	var cap := AcesBalance.ace_hit_cap("homing", AcesBalance.ACE_HP)
	var hp := AcesBalance.ACE_HP
	var n := 0
	while hp > 0.0 and n < 100:
		hp -= minf(500.0, cap)   # a level-5 missile far above the hull
		n += 1
	_check(n == int(AcesBalance.ACE_MISSILES), "even a huge missile needs %d hits on an ace (%d)" % [int(AcesBalance.ACE_MISSILES), n])
	_check(AcesBalance.ace_hit_cap("gun", AcesBalance.ACE_HP) == INF, "bullets are not capped")
	_check(AcesBalance.ace_hit_cap("blast", AcesBalance.ACE_HP) == INF, "rockets are not capped")
	_check(AcesBalance.ace_hit_cap("homing", AcesBalance.ACE_HP, 0.0) == INF, "slider 0 turns the cap off (s15)")


func _test_collision_ahead() -> void:
	_check(AcesBalance.collision_ahead(Vector2(300, 0), Vector2(-500, 0)), "head-on at 300 px and 500 px/s closing: ram ahead")
	_check(not AcesBalance.collision_ahead(Vector2(300, 0), Vector2(500, 0)), "opening: no ram")
	_check(not AcesBalance.collision_ahead(Vector2(300, 300), Vector2(-500, 0)), "passing 300 px to the side: no ram")
	_check(not AcesBalance.collision_ahead(Vector2(2000, 0), Vector2(-500, 0)), "too far to matter within AVOID_T")
	_check(AcesBalance.collision_ahead(Vector2(50, 0), Vector2.ZERO), "already overlapping")


func _test_ace_launch() -> void:
	_check(AcesBalance.ace_can_launch(600.0, 10.0), "player ahead at 600 px: launch")
	_check(not AcesBalance.ace_can_launch(600.0, 60.0), "player off the nose: no launch")
	_check(not AcesBalance.ace_can_launch(100.0, 0.0), "too close: guns, not missiles")
	_check(not AcesBalance.ace_can_launch(2000.0, 0.0), "out of range")
	_check(AcesBalance.ACE_MSL_CD >= 3.0, "missiles are not a stream: at least 3 s between launches")
