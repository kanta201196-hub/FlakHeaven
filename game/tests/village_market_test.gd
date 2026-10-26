extends SceneTree
## VIS-01 market and clutter (Kanta 26.10.2026: tents in the kishlak's centre, models for the old box clutter):
## the market fills the square off the streets, is the same on every build, and recording models instead of
## boxes leaves the village's layout generator untouched. Runs from tools/ci/unit.sh. Working part —
## village_market_test_run.gd (needs the autoloads).


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/village_market_test_run.gd").new())
