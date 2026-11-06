extends SceneTree
## Unit test for `GroundTarget.site_floor_hp` (S16-05/06): site members hold longer than convoy vehicles at the same
## player damage, and the old base × growth value still wins when the player's damage is low.
## Run from the repository root: `tools/ci/unit.sh`.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/site_hp_test_run.gd").new())
