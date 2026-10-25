extends SceneTree
## Unit test of convoy routes (Kanta 25.10, s11: «колонны перемещаются только по дорогам»): a column
## spawned anywhere in the Highlands, including over the mountains far from any river, drives on the
## road (on the valley floor), never on a straight line across ridges and passes; a bomber patrol with
## no road near its point is dropped instead. Runs from tools/ci/unit.sh. Working part —
## convoy_road_test_run.gd: Terrain3D needs the autoloads, which exist only after this SceneTree starts.


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/convoy_road_test_run.gd").new())
