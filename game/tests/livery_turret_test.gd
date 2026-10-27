extends SceneTree
## Unit tests for the turret paint that follows the plane's livery (Kanta 2026-10-27, s13 item 4: «Степь» and
## «Скальный осколок» for all planes, turrets in the same paint). Rules pinned here: every player turret file (each
## tier, the evolution, the «Кит» tail ball and cabin) has a baked twin in both new paints and turret_file picks it;
## the other liveries keep the sand-camo turret; both new liveries are in the picker of all three classes; the shipped
## list does not leak the bench-only proposals. Run from the repository root: `tools/ci/unit.sh`.
## Working part — livery_turret_test_run.gd (Livery and WeaponModels need the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/livery_turret_test_run.gd").new())
