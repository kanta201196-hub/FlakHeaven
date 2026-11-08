extends SceneTree
## Unit tests of the «Береговая батарея» (CoastBattery, B2-A01, Kanta 08.11): picking 4 spread gun spots, the
## battery-wide ring cap, the shell's aim and hit test, and placement on the real Archipelago terrain.
## Runs from tools/ci/unit.sh. Working part — coast_battery_test_run.gd: the scripts need the autoloads (Events,
## Tuning), which exist only after this SceneTree starts.


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/coast_battery_test_run.gd").new())
