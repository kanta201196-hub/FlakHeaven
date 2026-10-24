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

## Course gun variants: multipliers on rate, damage and bullet speed, spread half-angle in degrees and
## the defence class of its bullets (`Enemy.src_class`). DPS stays within ±15 % of the standard gun,
## so the choice is about feel and targets, not raw power.
const GUNS := {
	"std": {"rate": 1.0, "dmg": 1.0, "speed": 1.0, "spread": 0.0, "ap": false},
	"twin": {"rate": 1.6, "dmg": 0.65, "speed": 1.0, "spread": 3.0, "ap": false},
	"heavy": {"rate": 0.55, "dmg": 2.0, "speed": 1.15, "spread": 0.0, "ap": true},
}
const GUN_ORDER := ["std", "twin", "heavy"]
## Price in parts, paid once per class.
const GUN_PRICE := {"std": 0, "twin": 250, "heavy": 400}


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


## Multipliers of course gun `id`; an unknown id is the standard gun.
static func gun_k(id: String) -> Dictionary:
	return GUNS.get(id, GUNS["std"])
