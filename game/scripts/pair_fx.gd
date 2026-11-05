class_name PairFx
extends RefCounted
## Shared combat effects of the six pair synergies of PG-11 (Kanta 2026-11-05): «Перекрёстный огонь», «Загонщик»,
## «Обманка», «Огненный коридор», «Зарево», «Броневой бой». Their recipes and numbers are in `SynPairs`
## (balance/syn_pairs.gd), their texts in `Cards.SYNERGIES`.

## Colour of synergy `id` (for its sparks and rings)
static func color(id: String) -> Color:
	return Cards.SYNERGIES.get(id, {}).get("color", Color(1, 0.85, 0.3))


## A flare took an enemy missile away at `at`: «Обманка» answers with a guided missile at the nearest enemy,
## «Зарево» drops a bomb on the nearest ground target. Missile damage scales with the plane's missile factor.
static func on_flare_intercept(p: Player, at: Vector2) -> void:
	if p.syn.has("decoy"):
		var t := Weapons.pick_target(at, SynPairs.DECOY_RANGE, "nearest")
		if t != null:
			Main.I.projectiles.spawn_player_missile(at, (t.global_position - at).normalized() * SynPairs.DECOY_SPD, t,
				SynPairs.DECOY_DMG * p.missile_k(), "связка: обманка")
			Main.I.fx.ring(at, 40.0, color("decoy"))
	if p.syn.has("glow"):
		var g := Weapons.pick_target(p.global_position, SynPairs.GLOW_RANGE, "nearest", [], false, true)
		if g != null:
			Main.I.projectiles.spawn_bomb(p.global_position, 0.5, SynPairs.GLOW_DMG, SynPairs.GLOW_R, "связка: зарево", g.global_position, true)
