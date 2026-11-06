class_name PickBalance
extends RefCounted
## S16-22 (Kanta 05.11): where card rerolls, bans and pins come from beyond the sortie start (Main.START_*).
## Kanta: «добавить перки и достижения, которые их дают; награждать ими и за активности». Three sources:
## crew rank (permanent, shown with the rank's unlocks), medals (MedalBalance «Разведка боем», «Штабист») and
## activities done in the sortie. Aces keep their +1 reroll and +1 ban (Main._on_enemy_killed).
## All numbers are first guesses for s17.

## Crew rank → what it adds to every sortie of that class, cumulative: [rank, kind].
const CREW := [[4, "rerolls"], [8, "pins"], [12, "bans"], [16, "rerolls"]]
## Rerolls for every activity done in the sortie (transport, convoy, AA site, base, rival ace duel).
const ACTIVITY_REROLLS := 1
## Kinds a sortie counts.
const KINDS := ["rerolls", "bans", "pins"]


## Extra rerolls / bans / pins a crew of rank `rank` brings to every sortie: {"rerolls": n, "bans": n, "pins": n}.
static func crew(rank: int) -> Dictionary:
	var out := {"rerolls": 0, "bans": 0, "pins": 0}
	for e: Array in CREW:
		if rank >= int(e[0]):
			out[e[1]] = int(out[e[1]]) + 1
	return out


## What rank `rank` itself opens, as [kind] (empty if nothing): for the crew unlock list.
static func crew_at(rank: int) -> Array:
	var out: Array = []
	for e: Array in CREW:
		if int(e[0]) == rank:
			out.append(e[1])
	return out
