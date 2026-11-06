class_name DistText
extends RefCounted
## World distances and speeds as the player reads them: metres / kilometres on edge markers and task plates, km/h in
## the hangar. Display only: no gameplay distance or speed changes here.
##
## Kanta 06.11: «we fly a plane and the marker says 100 m». The old labels divided world px by 10, so the fighter's
## 390 px/s cruise read as ~140 km/h and a site two screens away as ~900 m. Models on the ground are drawn at ~6 px
## per metre (the «2–4 km up» map scale, A-08), but at that scale the planes would crawl at ~230 km/h; the game
## compresses the map round the plane on purpose. The marker scale therefore follows the speed: with M_PER_PX the
## fighter cruises at ~840 km/h, the attacker ~720, the bomber ~690 (jet strike aircraft of the inspiring era), so
## «5 km» on a marker takes about as long to fly as 5 km would.

## Metres per world px for every distance and speed shown to the player.
const M_PER_PX := 0.6
## From this many metres the label switches to kilometres with one decimal.
const KM_FROM := 1000.0


## Metres for a world distance of `px` (its size: the sign is dropped).
static func metres(px: float) -> float:
	return absf(px) * M_PER_PX


## Label for a world distance of `px`: «300 м» (rounded to 10 m) under a kilometre, «5,3 км» from one. Units go
## through translation («%d м», «%s км»); the decimal comma is Russian only.
static func text(px: float) -> String:
	var m := roundf(metres(px) / 10.0) * 10.0
	if m < KM_FROM:
		return Loc.t("%d м") % int(m)
	var km := "%.1f" % (metres(px) / 1000.0)
	if TranslationServer.get_locale().begins_with("ru"):
		km = km.replace(".", ",")
	return Loc.t("%s км") % km


## Speed of `px_per_s` world px per second in km/h, rounded.
static func kmh(px_per_s: float) -> int:
	return roundi(px_per_s * M_PER_PX * 3.6)
