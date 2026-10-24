class_name FxMath
extends RefCounted
## Pure helpers shared by the CPU (`Boom3D`) and GPU (`GpuFx`) effect paths, kept apart so they are unit-tested
## (`game/tests/vfx_test.gd`) and both paths pick kinds and particle counts by the same rules.

## Particle count factor per «Качество графики» preset (0 low … 3 ultra)
const PRESET := [0.45, 0.7, 1.0, 1.25]
## Particles alive after which new explosions get poorer, per preset (a 30-explosion fight stays bounded)
const BUDGET := [500.0, 800.0, 1200.0, 1600.0]


## Explosion kind when the caller gave none: ground target below, small air burst = flak, large = big
static func kind_for(s: float, air: bool, kind := "") -> String:
	if kind != "":
		return kind
	if not air:
		return "ground"
	if s < 18.0:
		return "flak"
	if s >= 50.0:
		return "big"
	return "air"


## Multiplier for particle counts of a new explosion: preset factor × crowding (down to 30 % when busy)
static func quality(gfx: int, alive: int) -> float:
	var gi := clampi(gfx, 0, 3)
	return PRESET[gi] * clampf(1.25 - float(alive) / BUDGET[gi], 0.3, 1.0)
