class_name CardText
extends RefCounted
## Pure helpers for texts on level-up cards, kept apart from `Cards` so unit tests can load
## them without the game scene. Tests: game/tests/card_total_test.gd.


## Total bonus after taking a card, from the base 100%: `now` × (1 + `step` × `k`) − 1, as
## "+27%", "−12%" or "0%" (the «(всего …)» part of single-stat module cards).
static func total_pct(now: float, step: float, k: float) -> String:
	var v := int(round((now * (1.0 + step * k) - 1.0) * 100.0))
	return "0%" if v == 0 else ("+%d%%" % v if v > 0 else "−%d%%" % -v)
