class_name CampaignGates
extends RefCounted
## Progression gates of the campaign map («Подготовка и вылет», Kanta 06.11): the first biome is open from the start,
## every later biome opens after BIOME_UNLOCK_OPS operations of the first biome are cleared. Pure rules; `Campaign`
## counts the cleared operations and the mission screen (`HudCampaign`) reads the result.

## Operations of the first biome to clear before the next biome opens (Kanta 06.11: «второй открывается только после
## 3 миссий в первом»).
const BIOME_UNLOCK_OPS := 3


## Whether `biome` is open when `cleared_in_first` operations of `first` (the starting biome) are cleared.
static func biome_open(biome: String, first: String, cleared_in_first: int) -> bool:
	return biome == first or cleared_in_first >= BIOME_UNLOCK_OPS


## Operations of the first biome still to clear before the next biome opens (0 when it is open).
static func left(cleared_in_first: int) -> int:
	return maxi(0, BIOME_UNLOCK_OPS - cleared_in_first)
