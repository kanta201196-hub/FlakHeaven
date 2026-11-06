class_name CardText
extends RefCounted
## Pure helpers for texts on level-up cards, kept apart from `Cards` so unit tests can load
## them without the game scene. Tests: game/tests/card_text_test.gd.


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


## Decimal mark of number text `s` for the player's language: a comma in Russian (as `DistText`), a point otherwise.
static func dec(s: String) -> String:
	return s.replace(".", ",") if TranslationServer.get_locale().begins_with("ru") else s


## A damage or other count for a card line: whole above 10 («34»), one decimal below («7,5»), so a
## small step (+8 %) still shows.
static func num(v: float) -> String:
	if absf(v) >= 10.0:
		return "%d" % roundi(v)
	return dec(("%.1f" % v).trim_suffix(".0"))


## Seconds with one decimal (comma in Russian): «3 с», «2,9 с».
static func sec(v: float) -> String:
	return Loc.t("%s с") % dec(("%.1f" % v).trim_suffix(".0"))


## Factor «×1,3» (two decimals when needed: «×1,12»).
static func factor(v: float) -> String:
	return "×" + dec(("%.2f" % v).trim_suffix("0").trim_suffix(".0"))


## One «now → after» line of a card: «Урон за попадание: 30 → 34». Equal ends say so instead of a fake step.
static func step(label: String, now: String, after: String, same_note := "") -> String:
	if now == after:
		return "%s: %s%s" % [label, now, same_note]
	return "%s: %s → %s" % [label, now, after]
