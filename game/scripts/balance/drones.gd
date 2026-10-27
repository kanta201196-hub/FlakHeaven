class_name DroneBalance
extends RefCounted
## Drone strength. Kanta 2026-10-27 (s13 notes, item 11): drones are many and are the background for drive, so they
## must burst apart from a couple of hits. Their HP follows the player's course gun instead of the time ramp, the
## operation difficulty and the pressure system, so a late drone dies as fast as an early one.

## A drone holds this many course-gun bullets (the player's current base hit, without the tail and combat-turn
## bonuses): two hits kill it, one hit kills it on the tail or in a combat turn.
const HITS := 1.5
## Floor, HP: a drone never dies from a single wingman or turret graze
const HP_MIN := 6.0


## Drone HP for a player whose course-gun bullet deals `gun_hit`
static func hp(gun_hit: float) -> float:
	return maxf(gun_hit * HITS, HP_MIN)
