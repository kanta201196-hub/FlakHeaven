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
const REACH := 7500.0   # 3000 found a fort ahead only 55 % of the time, 6000 — 94 % (400 random points, 2026-10-25); 7500 since forts keep a screen apart (2026-10-26, s12): the same share of points (335/400 vs 331/400 before) still find one
## Leaving this far after the end clears the base's leftovers (as the AA site).
const CLEAR_R := 2600.0
## S14-05: when the activity takes a fort, the ground this far from it (in fort sizes) is rebuilt with the
## fort's pad, trodden earth, fields and sandbag posts: the pad fades out by up to ~1.5 sizes (0.6 · Terrain3D.PAD_REACH),
## props of the cells round it look one size out, and its side valley to the river (Terrain3D._sides) reaches farther.
const GROUND_R := 2.5
## Missile `who` of the base: the base counts its own missiles in the air by it.
const WHO := "укрепрайон"

## FA-03 destructibility (spec «Conditional destructibility», *guess*): explosive hits a wall section and the
## gate take before they break. A hit weighs its blast radius against a bomb's (FortDamage.hit_weight).
const WALL_POOL := 2.0
const GATE_POOL := 1.5
const BOMB_R := 130.0   # the bombs' base radius (weapons.gd «bombs» range)
## The heaviest single hit, in bombs (a big thermobaric blast).
const HIT_CAP := 1.5
## Only ordnance blasts (rockets, bombs, thermobaric, chain reaction) of at least this base radius reach the walls;
## cannon HE splash and A-A missile splash never do.
const BLAST_MIN_R := 50.0
## A tower's crown is knocked about at this share of its launcher's HP (spec: 50 %).
const TOWER_DAMAGED := 0.5
