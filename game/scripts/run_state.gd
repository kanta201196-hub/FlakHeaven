class_name RunState
extends RefCounted
## State of one sortie: clock, level and XP, card queue, spare parts, kills and activities
## (ADR-02, CS-03). `Main.start_run` creates a fresh one as `Main.run`.
## Fields are read freely; they change only through the methods below, so rewards follow one
## formula (`Rewards`) and the card queue cannot get out of sync (CR-02).
## Uses no autoloads and no nodes, so `tests/run_state_test.gd` runs it headless.

## Sortie time, s (game time, stops on card screens).
var run_time := 0.0
var level := 1
## XP collected towards the next level.
var xp := 0.0
## Levels gained but not yet turned into a card pick.
var pending_levels := 0
## How many of `pending_levels` are picks from rare cards.
var rare_picks := 0
## Labels of the pending rare picks, oldest first («ЗА АСА»).
var rare_reasons: Array = []
## Spare parts earned this sortie (hangar currency) before the end-of-sortie share.
var parts := 0.0
## Parts kept after the sortie (100 % on evacuation, 50 % on death, times operation reward).
var parts_kept := 0
var kills := 0
## Completed activities that count towards the every-2nd rare pick.
var activities_done := 0
## Kill streak: kills without a pause longer than `streak_t`.
var streak := 0
var streak_t := 0.0
var best_streak := 0
var tail_kills := 0
var near_misses := 0
var bosses_killed := 0


## Adds XP (already multiplied by the F1 `xp_mult` slider) and queues every level gained.
func add_xp(v: float) -> void:
	xp += v
	while xp >= xp_need():
		xp -= xp_need()
		level += 1
		pending_levels += 1


## XP needed for the next level.
func xp_need() -> float:
	return XpCurve.need(level)


## Multiplier for kill XP at the current sortie time.
func kill_xp_k() -> float:
	return XpCurve.kill_k(run_time)


## Reward multiplier for staying after 15:00: +10 % per minute.
func continue_mult() -> float:
	return 1.0 + Rewards.LATE_BONUS_PER_MIN * maxf(0.0, (run_time - Rewards.SORTIE_LENGTH) / 60.0)


## Streak multiplier for kill parts and XP.
func streak_mult() -> float:
	return 1.0 + minf(streak, Rewards.STREAK_CAP) * Rewards.STREAK_STEP


## Counts a kill: kills, streak, tail kills; pays `base_parts` times the streak multiplier
## (and the late bonus). Returns the parts paid.
func on_kill(base_parts: float, from_tail := false) -> float:
	kills += 1
	streak += 1
	streak_t = Rewards.STREAK_WINDOW
	best_streak = maxi(best_streak, streak)
	if from_tail:
		tail_kills += 1
	return grant_parts(base_parts * streak_mult(), &"kill") if base_parts > 0.0 else 0.0


## A projectile passed close: counts it and keeps the streak alive a little longer.
func on_near_miss() -> void:
	near_misses += 1
	streak_t = maxf(streak_t, Rewards.NEAR_MISS_HOLD)


## A boss (ace, warship) was destroyed.
func on_boss_killed() -> void:
	bosses_killed += 1


## Advances the streak timer by `delta` s of game time; the streak ends when it runs out.
func tick(delta: float) -> void:
	streak_t -= delta
	if streak_t <= 0.0:
		streak = 0


## Pays `amount` spare parts with the post-15:00 multiplier applied once (`late_bonus` false —
## the amount already includes it, e.g. cargo valued when dropped). Returns the amount actually
## paid, for banners and the log. `reason` is for the log.
func grant_parts(amount: float, _reason: StringName = &"", late_bonus := true) -> float:
	var paid := amount * (continue_mult() if late_bonus else 1.0)
	parts += paid
	return paid


## Queues one pick from rare cards; `reason_label` is shown on the card screen.
func grant_rare_pick(reason_label: String) -> void:
	pending_levels += 1
	rare_picks += 1
	rare_reasons.append(reason_label)


## Pays the reward for a completed activity `kind` (see `Rewards.ACTIVITY`).
## Changes parts, the card queue and `activities_done`. Returns what was paid:
## `rare` (bool), `parts` (float, paid amount), `heal` (share of max hull the caller repairs),
## `course_pts` (int, the caller adds them to the player). Unknown kind: error and `{}`.
func award_activity(kind: StringName) -> Dictionary:
	if not Rewards.ACTIVITY.has(kind):
		push_error("RunState.award_activity: unknown kind %s" % kind)
		return {}
	var r: Dictionary = Rewards.ACTIVITY[kind]
	if r["counted"]:
		activities_done += 1
	var rare: bool = r["rare"] == Rewards.Rare.ALWAYS \
		or (r["rare"] == Rewards.Rare.EVERY_2ND and activities_done % 2 == 1)
	var amount: float = r["parts"] + (0.0 if rare else float(r["parts_common"]))
	var paid := grant_parts(amount, kind) if amount > 0.0 else 0.0
	if rare:
		grant_rare_pick(r["reason"])
	return {"kind": kind, "rare": rare, "parts": paid,
		"heal": 0.0 if rare else float(r["heal_common"]), "course_pts": int(r["course_pts"])}


## Takes one card pick off the queue (`rare` — it was a pick from rare cards).
func take_pick(rare: bool) -> void:
	pending_levels -= 1
	if rare:
		rare_picks -= 1
		if not rare_reasons.is_empty():
			rare_reasons.pop_front()


## Nothing left to offer: clears the queue and pays parts for every pending level.
## Returns `{levels, parts, heal}`: levels paid, parts paid, share of max hull to repair.
func pay_all_cards_taken() -> Dictionary:
	var n := pending_levels
	pending_levels = 0
	rare_picks = 0
	rare_reasons.clear()
	var paid := grant_parts(Rewards.ALL_CARDS_PARTS_PER_LEVEL * n, &"all_cards")
	return {"levels": n, "parts": paid,
		"heal": minf(Rewards.ALL_CARDS_HEAL_MAX, Rewards.ALL_CARDS_HEAL_PER_LEVEL * n)}


## Debug and screenshot setups only (`main_debug.gd`, F-keys): sets a field directly.
func debug_set(field: StringName, value: Variant) -> void:
	assert(field in self, "RunState has no field %s" % field)
	set(field, value)
