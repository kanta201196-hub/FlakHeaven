class_name PrepHint
extends RefCounted
## «Можно улучшить самолёт» before take-off (06.11 sortie review, point 4, Kanta «да»): a plane flown with zero node
## upgrades while parts lie unspent died at 13:10 with a 154 hull; upgraded, it reached the evacuation with 450.
## Pure rule; the hangar and the mission screen ask it and draw the reminder. It never blocks the sortie.


## Whether to remind: every node of the plane in flight is at level 0 and `parts` pay for the cheapest node level.
static func upgrade_due(node_levels: Array, parts: int, cheapest: int) -> bool:
	for lv in node_levels:
		if int(lv) > 0:
			return false
	return parts >= cheapest
