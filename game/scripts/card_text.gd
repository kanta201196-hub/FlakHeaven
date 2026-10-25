class_name CardText
extends RefCounted
## Pure helpers for texts on level-up cards, kept apart from `Cards` so unit tests can load
## them without the game scene. Tests: game/tests/card_total_test.gd.


## Total bonus after taking a card, from the base 100%: `now` × (1 + `step` × `k`) − 1, as
## "+27%", "−12%" or "0%" (the «(всего …)» part of single-stat module cards).
static func total_pct(now: float, step: float, k: float) -> String:
	var v := int(round((now * (1.0 + step * k) - 1.0) * 100.0))
	return "0%" if v == 0 else ("+%d%%" % v if v > 0 else "−%d%%" % -v)


## Level prefix of a weapon level part: «ур. 2–5:», «Lv. 4:», «Lv.2–5：».
static var _lvl_re := RegEx.create_from_string("^(?:ур\\.|Lv\\.)\\s?(\\d+)(?:[–-](\\d+))?\\s?[:：]\\s?(.+)$")  # i18n-skip


## Splits a translated weapon level text (parts separated by «;» or «；») for a pick that
## takes the weapon from level `from` to `to` (a rare card can jump two levels): {now: parts
## for any level gained by this pick, later: [[first level, part]] still ahead, base: parts
## with no level prefix}. Single levels already taken are dropped. Used by `Cards` for the
## «Сейчас / На ур. N» lines (S11-20).
static func level_split(text: String, from: int, to: int) -> Dictionary:
	var now := PackedStringArray()
	var later: Array = []
	var base := PackedStringArray()
	for part in text.replace("；", ";").split(";", false):
		var s := part.strip_edges()
		var m := _lvl_re.search(s)
		if m == null:
			base.append(s)
			continue
		var a := int(m.get_string(1))
		var b := int(m.get_string(2)) if m.get_string(2) != "" else a
		if a <= to and b > from:
			now.append(m.get_string(3))
		elif a > to:
			later.append([a, m.get_string(3)])
	return {"now": now, "later": later, "base": base}
