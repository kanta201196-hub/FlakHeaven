class_name WeaponBalance
extends RefCounted
## Balance numbers of the standard weapons added in PG-01 and of the course gun variants (ADR-04).
## Base cooldown, damage and range of each weapon stay in `Weapons.DEFS`; here — how they grow with the
## weapon level, the reload floors and the course guns. Older weapons keep their numbers in
## `hardpoint.gd` until that file is touched for them.

## Growth per level above 1, as a share of level 1: damage up, reload down, range (blast radius) up.
## Linear like `aam` and `bombs`: level 5 of `srm` reloads in 0.68 of level 1.
const LEVEL := {
	"srm": {"dmg": 0.25, "cd": 0.08},
	"agm": {"dmg": 0.25, "cd": 0.06},
	"hebomb": {"dmg": 0.25, "range": 0.08},
}

## Reload never goes below this, s: reload cards stack (the same reason as `Hardpoint.MSL_CD_MIN`).
const CD_FLOOR := {"srm": 2.0, "agm": 3.5}

## `srm` turns this much faster than `aam` (320°/s): short range, agile targets.
const SRM_TURN_K := 1.4
## `agm` hits ground targets only; ground factor like other anti-ground weapons (rockets ×3, bombs ×2).
const AGM_GROUND_K := 2.0
## `hebomb`: fuse, s, and screen shake on the blast.
const HEBOMB_FUSE := 0.6
const HEBOMB_SHAKE := 5.0

## Course gun variants: multipliers on rate, damage and bullet speed and spread half-angle in degrees.
## DPS stays within ±15 % of the standard gun, so the choice is about feel, not raw power. Armor piercing
## is the job of the ammo (`AMMO`), not of the gun.
const GUNS := {
	"std": {"rate": 1.0, "dmg": 1.0, "speed": 1.0, "spread": 0.0},
	"twin": {"rate": 1.6, "dmg": 0.65, "speed": 1.0, "spread": 3.0},
	"heavy": {"rate": 0.55, "dmg": 2.0, "speed": 1.15, "spread": 0.0},
}
const GUN_ORDER := ["std", "twin", "heavy"]
## Price in parts, paid once per plane (class and plane level, Kanta 24.10).
const GUN_PRICE := {"std": 0, "twin": 250, "heavy": 400}

## Ammo of the course gun (Kanta 24.10; his first numbers, to be tuned by the balance run): damage and bullet
## speed multipliers on top of the gun variant. `ap` — armor-piercing (bullets of class "gun_ap", armor does
## not halve them: maximum damage to one target); `he` — high-explosive, `splash_r` px around the hit takes
## `splash_k` of the damage (groups); `inc` — incendiary, sets the target on fire for `burn` of the hit
## damage over `BURN_TIME`, stacking up to `BURN_STACKS` (bosses).
const AMMO := {
	"std": {"dmg": 1.0, "speed": 1.0, "ap": false, "splash_r": 0.0, "splash_k": 0.0, "burn": 0.0},
	"ap": {"dmg": 0.75, "speed": 1.0, "ap": true, "splash_r": 0.0, "splash_k": 0.0, "burn": 0.0},
	"he": {"dmg": 1.0, "speed": 0.75, "ap": false, "splash_r": 34.0, "splash_k": 0.5, "burn": 0.0},
	"inc": {"dmg": 0.85, "speed": 0.8, "ap": false, "splash_r": 0.0, "splash_k": 0.0, "burn": 0.5},
}
const AMMO_ORDER := ["std", "ap", "he", "inc"]
## Price in parts, paid once per plane; a guess until the first playtest.
const AMMO_PRICE := {"std": 0, "ap": 200, "he": 250, "inc": 300}
const BURN_TIME := 2.0
const BURN_STACKS := 5


## Damage factor of weapon `w` at `level` (1 at level 1).
static func dmg_k(w: String, level: int) -> float:
	return 1.0 + float(LEVEL.get(w, {}).get("dmg", 0.0)) * (level - 1)


## Reload factor of weapon `w` at `level` (1 at level 1, smaller is faster).
static func cd_k(w: String, level: int) -> float:
	return 1.0 - float(LEVEL.get(w, {}).get("cd", 0.0)) * (level - 1)


## Range or blast radius factor of weapon `w` at `level`.
static func range_k(w: String, level: int) -> float:
	return 1.0 + float(LEVEL.get(w, {}).get("range", 0.0)) * (level - 1)


## Lowest reload of weapon `w`, s; 0 — no floor.
static func cd_floor(w: String) -> float:
	return float(CD_FLOOR.get(w, 0.0))


## Multipliers of ammo `id`; an unknown id is the standard ammo.
static func ammo_k(id: String) -> Dictionary:
	return AMMO.get(id, AMMO["std"])


## Burn state after one more incendiary hit of `hit_dmg`: `b` is {"n": stacks, "dps": damage per s, "t": time
## left}. Each hit adds one stack (up to `BURN_STACKS`) of `burn` × hit over `BURN_TIME` and refreshes the time.
static func burn_add(b: Dictionary, hit_dmg: float) -> Dictionary:
	var n := mini(int(b.get("n", 0)) + 1, BURN_STACKS)
	var per := hit_dmg * float(AMMO["inc"]["burn"]) / BURN_TIME
	var dps := float(b.get("dps", 0.0))
	# stacks keep the strongest hits: below the cap add, at the cap replace the average stack if stronger
	if int(b.get("n", 0)) < BURN_STACKS:
		dps += per
	else:
		dps = maxf(dps, dps - dps / BURN_STACKS + per)
	return {"n": n, "dps": dps, "t": BURN_TIME}


## Multipliers of course gun `id`; an unknown id is the standard gun.
static func gun_k(id: String) -> Dictionary:
	return GUNS.get(id, GUNS["std"])
