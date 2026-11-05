class_name PairFx
extends RefCounted
## Numbers and shared effects of the six pair synergies of PG-11 (Kanta 2026-11-05): «Перекрёстный огонь»,
## «Загонщик», «Обманка», «Огненный коридор», «Зарево», «Броневой бой». Their recipes are in `SynPairs`, their
## texts in `Cards.SYNERGIES`. Kept in one place so the balance run finds every number of the new synergies here;
## first guesses, not measured yet (plan: docs/superpowers/plans/2026-11-05-build-depth.md, part B).

## «Перекрёстный огонь» / «Загонщик»: damage factor on a marked target, and how long a course gun hit marks it, s
const MARK_K := 1.5
const CROSS_T := 2.0
const HUNT_T := 3.0
## «Обманка»: damage of the answering missile; «Зарево»: bomb damage, radius and search range, px
const DECOY_DMG := 40.0
const GLOW_DMG := 50.0
const GLOW_R := 90.0
const GLOW_RANGE := 600.0
## «Огненный коридор»: fire left by a volley rocket (radius px, damage per s, time s) and the bomb radius factor in it
const CORRIDOR_R := 45.0
const CORRIDOR_DPS := 10.0
const CORRIDOR_T := 2.0
const CORRIDOR_R_K := 1.5
const CORRIDOR_SRC := "связка: огненный коридор"
## «Броневой бой»: course gun damage per stack, stacks cap, how long the stacks hold after the last hit, s
const IRONCLAD_K := 0.08
const IRONCLAD_MAX := 5
const IRONCLAD_T := 5.0


## Colour of synergy `id` (for its sparks and rings)
static func color(id: String) -> Color:
	return Cards.SYNERGIES.get(id, {}).get("color", Color(1, 0.85, 0.3))


## A flare took an enemy missile away at `at`: «Обманка» answers with a guided missile at the nearest enemy,
## «Зарево» drops a bomb on the nearest ground target. Missile damage scales with the plane's missile factor.
static func on_flare_intercept(p: Player, at: Vector2) -> void:
	if p.syn.has("decoy"):
		var t := Weapons.pick_target(at, 900.0, "nearest")
		if t != null:
			Main.I.projectiles.spawn_player_missile(at, (t.global_position - at).normalized() * 250.0, t,
				DECOY_DMG * p.missile_k(), "связка: обманка")
			Main.I.fx.ring(at, 40.0, color("decoy"))
	if p.syn.has("glow"):
		var g := Weapons.pick_target(p.global_position, GLOW_RANGE, "nearest", [], false, true)
		if g != null:
			Main.I.projectiles.spawn_bomb(p.global_position, 0.5, GLOW_DMG, GLOW_R, "связка: зарево", g.global_position, true)
