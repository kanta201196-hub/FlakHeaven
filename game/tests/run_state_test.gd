extends SceneTree
## Unit tests for `RunState` and the reward table (CS-03). No framework: each check prints
## FAIL with a message; the process exits with code 1 if any check failed.
## Run from the repository root: `tools/ci/unit.sh`.
## Tests pin the rules (who gets a rare pick, the multiplier is applied once, the queue stays
## consistent), not every number of the table.

var _failed := 0
var _checks := 0


func _init() -> void:
	_test_reward_kinds()
	_test_every_second_shared()
	_test_always_rare()
	_test_class_task_not_counted()
	_test_continue_mult_once()
	_test_xp_levels()
	_test_rare_queue()
	_test_all_cards_taken()
	_test_kill_streak()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## Every kind in the table pays without errors and returns the full result.
func _test_reward_kinds() -> void:
	for kind: StringName in Rewards.ACTIVITY:
		var r := RunState.new().award_activity(kind)
		_check(r.has_all(["rare", "parts", "heal", "course_pts"]), "result keys for %s" % kind)
		_check(float(r["parts"]) >= 0.0, "parts not negative for %s" % kind)


## «Every 2nd» counts all counted activities together: ground, convoy, transport alternate.
func _test_every_second_shared() -> void:
	var s := RunState.new()
	var a := s.award_activity(&"ground")
	var b := s.award_activity(&"convoy")
	var c := s.award_activity(&"transport")
	var d := s.award_activity(&"ground")
	_check(a["rare"] and not b["rare"] and c["rare"] and not d["rare"], "every 2nd is 1st, 3rd…")
	_check(s.activities_done == 4, "four counted activities")
	_check(s.rare_picks == 2 and s.pending_levels == 2, "two rare picks queued")
	_check(d["heal"] > 0.0 and a["heal"] == 0.0, "repair only without a rare pick")
	_check(d["parts"] > a["parts"], "ground pays more parts without a rare pick")


## Dogfight and rescue always give a rare pick and still move the every-2nd counter.
func _test_always_rare() -> void:
	var s := RunState.new()
	_check(s.award_activity(&"dogfight")["rare"], "dogfight 1 rare")
	_check(s.award_activity(&"rescue")["rare"], "rescue 2 rare")
	_check(s.activities_done == 2, "dogfight and rescue are counted")
	_check(s.award_activity(&"ground")["rare"], "3rd counted activity is rare")


## The class task gives a rare pick but does not shift the every-2nd counter.
func _test_class_task_not_counted() -> void:
	var s := RunState.new()
	var r := s.award_activity(&"class_task")
	_check(r["rare"] and s.activities_done == 0, "class task: rare, not counted")
	_check(r["course_pts"] == 0, "class task: no course points")
	_check(s.award_activity(&"convoy")["rare"], "next counted activity is still the 1st")


## After 15:00 the multiplier is applied exactly once and the result equals what was added.
func _test_continue_mult_once() -> void:
	var s := RunState.new()
	s.run_time = Rewards.SORTIE_LENGTH + 120.0
	var k := s.continue_mult()
	_check(is_equal_approx(k, 1.0 + 2.0 * Rewards.LATE_BONUS_PER_MIN), "two minutes late")
	var paid := s.grant_parts(100.0)
	_check(is_equal_approx(paid, 100.0 * k) and is_equal_approx(s.parts, paid), "mult applied once")
	var r := RunState.new()
	r.run_time = s.run_time
	var res := r.award_activity(&"transport")
	_check(is_equal_approx(res["parts"], r.parts), "paid amount is what the banner shows")
	_check(RunState.new().continue_mult() == 1.0, "no bonus before 15:00")
	var c := RunState.new()
	c.run_time = s.run_time
	_check(is_equal_approx(c.grant_parts(50.0, &"cargo", false), 50.0), "no bonus when already applied")


## XP: a known sum gives the expected levels; leftover XP stays below the next need.
func _test_xp_levels() -> void:
	var s := RunState.new()
	var sum := 0.0
	for lv in range(1, 11):
		sum += XpCurve.need(lv)
	s.add_xp(sum + 1.0)
	_check(s.level == 11 and s.pending_levels == 10, "ten levels from the sum of ten needs")
	_check(s.xp < s.xp_need(), "leftover below next need")
	_check(XpCurve.need(2) > XpCurve.need(1), "curve grows")
	_check(XpCurve.kill_k(0.0) == 1.0 and XpCurve.kill_k(10000.0) == XpCurve.KILL_LATE, "kill XP fade")


## A rare pick queues a level and its label; taking it removes both.
func _test_rare_queue() -> void:
	var s := RunState.new()
	s.grant_rare_pick("A")
	s.grant_rare_pick("B")
	_check(s.pending_levels == 2 and s.rare_reasons == ["A", "B"], "queue keeps order")
	s.take_pick(true)
	_check(s.pending_levels == 1 and s.rare_picks == 1 and s.rare_reasons == ["B"], "oldest taken")
	s.take_pick(true)
	_check(s.pending_levels == 0 and s.rare_picks == 0 and s.rare_reasons.is_empty(), "queue empty")


## All cards taken: the queue is cleared and every pending level is paid.
func _test_all_cards_taken() -> void:
	var s := RunState.new()
	s.grant_rare_pick("A")
	s.add_xp(XpCurve.need(1))
	var r := s.pay_all_cards_taken()
	_check(r["levels"] == 2 and s.pending_levels == 0 and s.rare_picks == 0, "queue cleared")
	_check(is_equal_approx(r["parts"], 2 * Rewards.ALL_CARDS_PARTS_PER_LEVEL), "parts per level")
	_check(r["heal"] <= Rewards.ALL_CARDS_HEAL_MAX, "heal capped")


## Kills build a streak that raises kill parts; it ends when the timer runs out; a near miss
## holds it.
func _test_kill_streak() -> void:
	var s := RunState.new()
	var first := s.on_kill(10.0)
	var second := s.on_kill(10.0, true)
	_check(s.kills == 2 and s.streak == 2 and s.tail_kills == 1, "kills, streak, tail kill counted")
	_check(second > first, "streak raises kill parts")
	s.tick(Rewards.STREAK_WINDOW + 0.1)
	_check(s.streak == 0 and s.best_streak == 2, "streak ends, best kept")
	s.on_kill(0.0)
	s.tick(Rewards.STREAK_WINDOW - 0.1)
	s.on_near_miss()
	s.tick(Rewards.NEAR_MISS_HOLD - 0.1)
	_check(s.streak == 1 and s.near_misses == 1, "near miss holds the streak")
	_check(s.streak_mult() <= 1.0 + Rewards.STREAK_CAP * Rewards.STREAK_STEP, "streak mult capped")
