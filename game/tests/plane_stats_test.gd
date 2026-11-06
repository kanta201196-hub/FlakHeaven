extends SceneTree
## Unit tests for `PlaneStats` (S16-08): the hangar's plane stats come from the sortie's own rules — plane 2 has
## +15% hull, +5% speed and turn and one more hardpoint group (the heavy mount) than plane 1 with the same nodes, the
## hangar nodes of each plane count only for that plane, the profile's flying plane is left as it was, and the kit's damage
## per second with its air / ground factors follows each class's starting weapons (Kanta 06.11).
## Run from the repository root: `tools/ci/unit.sh`. Working part — plane_stats_test_run.gd (needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/plane_stats_test_run.gd").new())
