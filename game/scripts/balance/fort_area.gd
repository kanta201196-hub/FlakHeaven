class_name FortBalance
extends RefCounted
## Numbers of the «Укрепрайон» activity (FortArea, FA-01, spec 2026-10-25-fortified-area-design.md).
## Values marked *guess* in the spec are tuned after the first play test.

## Kanta 2026-10-25: at most this many base missiles in the air (locks in progress count too), so the
## four tower launchers never salvo the player all at once.
const MISSILE_CAP := 4
## Approach closer than this — alarm, banner «Обнаружена база противника», timer (same as the AA site).
const ACTIVATE_R := 1150.0
## Optional-activity timer after the alarm (*guess*, the AA site has 60 s and one bunker).
const LIMIT := 90.0
## The activity takes a real map fort within REACH of the point AHEAD px along the player's heading (*guess*).
const AHEAD := 1700.0
const REACH := 6000.0   # 3000 found a fort ahead only 55 % of the time, 6000 — 94 % (400 random points, 2026-10-25)
## Leaving this far after the end clears the base's leftovers (as the AA site).
const CLEAR_R := 2600.0
## Missile `who` of the base: the base counts its own missiles in the air by it.
const WHO := "укрепрайон"
## Tower top above the ground, share of the fort size (unit mesh tower height 0.17, AdobeBuild.fort).
const TOWER_H := 0.17
