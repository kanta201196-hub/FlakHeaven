extends SceneTree
## Unit tests for the turret paint that follows the plane's livery (Kanta 2026-10-27, s13 item 4: «Степь» and
## «Скальный осколок», then all ten round-2 paints (Livery.ROUND2), for all planes, turrets in the same paint). Rules
## pinned here: every player turret file (each tier, the evolution, the «Кит» tail ball and cabin) has a baked twin in
## every Livery.TURRET_PAINT paint and turret_file picks it; the other liveries keep the sand-camo turret; every
## shipped new livery is in the picker of all three classes, once; the shipped list does not leak the bench-only
## proposals; every plane model has a nose for the shark mouth. Run from the repository root: `tools/ci/unit.sh`.
## Working part — livery_turret_test_run.gd (Livery and WeaponModels need the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/livery_turret_test_run.gd").new())
