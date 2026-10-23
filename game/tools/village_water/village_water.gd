extends SceneTree
## Проверка S9-07/S9-08 (правка Kanta 23.10): сады, поля, окопы, позиции орудий и посты кишлака, сады
## и юрты BiomeProps, сцены прошедших боёв — не на ручье долины-притока (протоке) и не в охранной зоне реки.
## Все кишлаки на квадрате клеток; «до» — раскладка окраины без учёта воды, «после» — как в игре.
## Запуск (из корня репозитория):
##   godot --headless --path game -s res://tools/village_water/village_water.gd -- --r=20
## В выводе «после» на воде везде 0, последняя строка «WATER итог: ok».


func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/village_water/village_water_run.gd").new())
