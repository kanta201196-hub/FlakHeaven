extends SceneTree
## Карта расстановки биома сверху (тред «Второй биом», 18.10.2026): зоны рельефа, объекты клеток,
## модели BiomeProps и сцены прошедших боёв — теми же функциями, что в игре.
## Запуск (из корня репозитория):
##   godot --headless --path game -s res://tools/biome_map/biome_map.gd -- --cx=-8 --cz=-5 --w=16 --h=10 --out=/путь/map.json
##   python3 game/tools/biome_map/render_map.py /путь/map.json /путь/map.png [px мира на пиксель, 10]
## Рабочая часть — biome_map_run.gd: грузится здесь, когда автозагрузки (Tuning, Settings) уже есть.


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/biome_map/biome_map_run.gd").new())
