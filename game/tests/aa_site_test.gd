extends SceneTree
## Unit test of AA site placement (Kanta's rule, repeated 2026-10-24): by the river only the convoy
## on its road; the AA bunker and vehicles stand away from the river and never in a river or a
## village stream — on the old relief and on the RV-01 landform regions.
## Runs from tools/ci/unit.sh. Working part — aa_site_test_run.gd: Terrain3D needs the autoloads
## (Tuning, Settings), which exist only after this SceneTree starts.


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/aa_site_test_run.gd").new())
