class_name MobileRules
extends RefCounted
## Phone/tablet limits the PC game reads (Android draft). `on` is false on PC, so every check
## here is a no-op there. Kept apart from the MobileMode autoload because that node frees itself
## on PC, and code must still be able to ask «are we on a phone?».

## True on Android/iOS (or PC with `--mobile`); set once by MobileMode at start
static var on := false

## Highest value each graphics option may take on a phone, whatever preset the player picks.
## Shadows stay on (the Compatibility renderer has no «off»), filtered cheaply; no MSAA — at
## tablet resolutions it alone can halve the frame rate (guess until a tablet log says otherwise).
const MAX := {"aa": GfxPresets.AA_OFF, "shadows": GfxPresets.SHADOWS_LOW, "shadow_res": 0,
	"terrain": 1, "props": 1, "effects": 1, "glow": 0}

## 3D lines drawn at render scale 100 %; tablets have 1600–1840 physical lines, which the
## preset's render scale would otherwise apply to (e.g. 80 % of 1840 = 1472 lines).
const LINES_AT_FULL := 900.0


## `v` limited to the phone maximum of option `id` (unchanged on PC).
static func cap(id: String, v: int) -> int:
	if not on or not MAX.has(id):
		return v
	return mini(v, int(MAX[id]))


## Extra factor on the 3D render scale so it follows LINES_AT_FULL instead of the panel's own
## resolution; 1.0 on PC and on screens already that small.
static func scale_k(screen_lines: float) -> float:
	if not on or screen_lines <= 0.0:
		return 1.0
	return clampf(LINES_AT_FULL / screen_lines, 0.3, 1.0)
