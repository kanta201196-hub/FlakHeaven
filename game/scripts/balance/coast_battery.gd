class_name BatteryBalance
extends RefCounted
## Numbers of the «Береговая батарея» activity (CoastBattery, B2-A01, plan docs/superpowers/plans/2026-11-08-coastal-battery.md).
## Values marked *guess* are tuned after the first play test.

## Kanta 08.11: four guns.
const GUNS := 4
## Guns stand at least GAP_MIN apart, and each one has a neighbour within GAP_MAX (Kanta 08.11: 300–600 px, spread
## over capes and islets, still one battery).
const GAP_MIN := 300.0
const GAP_MAX := 600.0
## Guns are looked for within this radius of the battery's centre.
const SEARCH_R := 900.0
## Grid step of the shore candidate search, px.
const GRID := 50.0
## A gun stands on land this far from the water's edge, px (a cape or islet, not inland, not on the beach).
const SHORE_MIN := 40.0
const SHORE_MAX := 250.0
## Level pad: ground at ±PAD_R differs from the centre by at most PAD_TOL px (the scenery battery's _level: berm hides
## 0.14 of the 56–64 px site).
const PAD_R := 30.0
const PAD_TOL := 9.0

## Approach this close to the centre — alarm and timer (as the fort).
const ACTIVATE_R := 1150.0
## Optional-activity timer after the alarm (as the fort, 150 s).
const LIMIT := 150.0
## Leaving this far after the end clears the battery's leftovers (as the fort).
const CLEAR_R := 2600.0

## Shell damage before the campaign's damage multiplier (*guess*: SAM missile 24, «Сторож» salvo 30).
const SHELL_DMG := 20.0
## Burst radius, px (*guess*; the «Сторож» salvo circle is 200).
const BURST_R := 110.0
## Kanta 08.11: the ring shows ~1 s before the burst; the shell aims at the player's point after this time.
const RING_T := 1.0
## Reload per gun, s, random in the range (*guess*; SAM 5–6.5).
const RELOAD_MIN := 5.0
const RELOAD_MAX := 6.0
## Range of one gun, px (*guess*; SAM 900).
const RANGE := 1100.0
## At most this many rings on the ground for the whole battery (*guess*), so the guns never wall the sky off.
const RING_CAP := 2
## Gun barrel elevation, rad: low at the range limit, high right overhead (look only).
const ELEV_MIN := 0.12
const ELEV_MAX := 0.9

## Sprite and length of a gun (the scenery gun site, 56–64 px across on the ground).
const TEX := "e_coast_gun"
const LEN := 62.0
## Wreck: the scenery's broken site (b2_shore.py a01_battery_gun_broken), same scale as the intact one.
const WRECK := "res://models/biome2/a01_battery_gun_broken.glb"
## Shell `who` for the damage stats.
const WHO := "береговая батарея"
