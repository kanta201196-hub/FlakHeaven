extends SceneTree
## Unit tests for `MusicDirector` (S16-02): in flight the boss/ace music starts at once but returns to the battle
## music only after a calm hold, so short ace duels and boss deaths do not flip the track back and forth.
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	var d := MusicDirector.new()
	_check(d.step("menu", 0.1) == "menu", "menu passes through")
	_check(d.step("battle", 0.1) == "battle", "battle passes through")
	_check(d.step("boss", 0.1) == "boss", "boss starts at once")
	_check(d.step("battle", 0.1) == "boss", "boss gone for 0.1 s: still boss music")
	_check(d.step("battle", MusicDirector.BOSS_HOLD * 0.5) == "boss", "half the hold: still boss music")
	_check(d.step("boss", 0.1) == "boss", "boss back during the hold")
	_check(d.step("battle", MusicDirector.BOSS_HOLD * 0.9) == "boss", "the calm timer restarted when the boss came back")
	_check(d.step("battle", MusicDirector.BOSS_HOLD * 0.2) == "battle", "calm longer than the hold: battle music")
	d.step("boss", 0.1)
	_check(d.step("result", 0.1) == "result", "result (death, evacuation) does not wait for the hold")
	d.step("boss", 0.1)
	_check(d.step("menu", 0.1) == "menu", "menu does not wait for the hold")

	var off := MusicDirector.new()
	off.steady = false
	off.step("boss", 0.1)
	_check(off.step("battle", 0.1) == "battle", "steady off: battle at once, as in s16")
	_check(MusicDirector.BOSS_HOLD >= 4.0 and MusicDirector.BOSS_HOLD <= 20.0, "hold is a few seconds")
	_check(MusicDirector.fade_time("battle", "boss", true) > MusicDirector.fade_time("menu", "battle", true), "battle ↔ boss fades slower")
	_check(is_equal_approx(MusicDirector.fade_time("battle", "boss", false), 1.5), "steady off: 1.5 s fade, as in s16")
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
