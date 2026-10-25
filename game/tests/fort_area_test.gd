extends SceneTree
## Unit tests of the «Укрепрайон» activity's pure logic (FortArea, FA-01): which map fort is taken,
## where the 4 tower launchers and the 2 yard jeeps stand, and the base-wide missile cap
## (Kanta 2026-10-25: at most 4 base missiles in the air). Runs from tools/ci/unit.sh.
## Working part — fort_area_test_run.gd (FortArea compiles against the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/fort_area_test_run.gd").new())
