extends SceneTree
## Unit test of `Cards.is_fork`: when the level-up screen is the «or-or» fork (header «ИЛИ-ИЛИ», cards marked as a
## mastery branch, no lock or ban). s15 (Kanta's recording, from level 36): a single profile-rank card — a «first»
## branch card that shares the screen with ordinary ones — turned the whole row of 4 different cards into a fork.
## A fork is only a row of two or more cards that are all first-branch or all profile cards.
## The checks are in `card_fork_cases.gd`; waits one frame so autoloads exist (as `profiles_test.gd`).
## Run from the repository root: `tools/ci/unit.sh`.


func _init() -> void:
	await process_frame
	var r: Array = load("res://tests/card_fork_cases.gd").new().run()
	print("UNIT: %d checks, %d failed" % [r[0], r[1]])
	quit(1 if int(r[1]) > 0 else 0)
