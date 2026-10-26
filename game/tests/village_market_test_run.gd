extends Node
## Working part of village_market_test.gd: builds every village layout with models and with the old boxes and
## checks the market's tents and the layout generator's end state.

const MIN_TENTS := 10   ## a square that reads as a bazaar


func _ready() -> void:
	var ok := true
	for v in 4:
		var homes := _build(v, true)
		var state_models: int = AdobeBuild._vcache["village%d_edge" % v][1]
		var again := _build(v, true)
		_build(v, false)
		var state_boxes: int = AdobeBuild._vcache["village%d_edge" % v][1]
		var tents := 0
		var bad := 0
		for h: Array in homes:
			var k := int(h[0])
			if k < VillageHouses.TENT or k > VillageHouses.TENT + 2:
				continue
			tents += 1
			var c: Vector2 = h[1]
			if c.length() > AdobeBuild.SQ_R or AdobeBuild.path_info(v, c).x < AdobeBuild.MKT_CLEAR:
				bad += 1
		var kinds := {}
		for h: Array in homes:
			kinds[int(h[0])] = true
		print("UNIT: village%d market tents %d, models %d, kinds %d, layout rng same: %s" % [v, tents, homes.size(), kinds.size(), state_models == state_boxes])
		if tents < MIN_TENTS:
			print("FAIL village_market: village%d has %d tents (< %d)" % [v, tents, MIN_TENTS])
			ok = false
		if bad > 0:
			print("FAIL village_market: village%d has %d tents off the square or on a street" % [v, bad])
			ok = false
		if str(homes) != str(again):
			print("FAIL village_market: village%d models differ between two builds" % v)
			ok = false
		if state_models != state_boxes:
			print("FAIL village_market: village%d layout generator ends elsewhere with models (%d) than with boxes (%d)" % [v, state_models, state_boxes])
			ok = false
		for k in [VillageHouses.STALL, VillageHouses.ORCHARD, VillageHouses.TANDOOR, VillageHouses.WOODPILE]:
			if not kinds.has(k):
				print("FAIL village_market: village%d has no model of kind %d" % [v, k])
				ok = false
	AdobeBuild.model_houses = true
	get_tree().quit(0 if ok else 1)


func _build(v: int, models: bool) -> Array:
	AdobeBuild.model_houses = models
	for k in ["", "_stats", "_edge", "_homes", "_arrays"]:
		AdobeBuild._vcache.erase("village%d%s" % [v, k])
	AdobeBuild.village(v)
	return AdobeBuild._vcache.get("village%d_homes" % v, []).duplicate(true)
