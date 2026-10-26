extends SceneTree
## Unit test of big-structure spacing in the Highlands (Kanta 26.10, s12: two forts on one screen, a fort
## next to a village): villages, forts and oases keep about a screen of ground between their edges, and no
## mesa stands on a settlement. Runs from tools/ci/unit.sh. Working part — settlement_spacing_test_run.gd:
## Terrain3D needs the autoloads, which exist only after this SceneTree starts.


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/settlement_spacing_test_run.gd").new())
