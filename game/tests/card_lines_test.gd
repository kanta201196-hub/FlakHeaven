extends SceneTree
## Unit tests for the real-number lines of mastery rank and «Э+» cards (Kanta 06.11: «что такое к профилю?» and
## «отличаются ли показатели карточек от рангов?»): each line is measured on the group itself, the group is left as it
## was, and a reload already at its floor says so instead of promising a cut.
## Run from the repository root: `tools/ci/unit.sh`. Working part — card_lines_test_run.gd (needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/card_lines_test_run.gd").new())
