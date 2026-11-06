extends SceneTree
## Unit tests for `CardText`: the «(всего +N%)» total on single-stat module cards (Kanta
## 24.10, idea 3: multiplier now × (1 + step × rarity) − 1, rounded, signed) and the weapon
## level text split into "now" and "later" (S11-20: the card must say whether a bonus comes
## with this pick or only at a later level), and the number formats of «now → after» card lines (Kanta 06.11:
## real numbers instead of «+12 % к профилю»).
## Run from the repository root: `tools/ci/unit.sh`.

var _failed := 0
var _checks := 0


func _init() -> void:
	_check(CardText.total_pct(1.0, 0.06, 1.0) == "+6%", "first pick shows its own bonus: %s" % CardText.total_pct(1.0, 0.06, 1.0))
	_check(CardText.total_pct(1.13, 0.06, 2.0) == "+27%", "stacks multiply with what is already there: %s" % CardText.total_pct(1.13, 0.06, 2.0))
	_check(CardText.total_pct(0.8, 0.1, 1.0) == "−12%", "a total below base gets a minus sign: %s" % CardText.total_pct(0.8, 0.1, 1.0))
	_check(CardText.total_pct(0.95, 0.05, 1.0) == "0%", "a zero total has no sign: %s" % CardText.total_pct(0.95, 0.05, 1.0))
	_test_level_text()
	_test_numbers()
	print("UNIT: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _test_level_text() -> void:
	var ru := "1 ракета с точки; ур. 2–5: +30% урона, −10% перезарядки; ур. 4: ещё +80% урона и +20% скорости"
	var a := CardText.level_split(ru, 1, 2)
	_check(a["now"] == PackedStringArray(["+30% урона, −10% перезарядки"]), "range 2–5 applies at level 2: %s" % [a["now"]])
	_check(a["later"].size() == 1 and int(a["later"][0][0]) == 4 and String(a["later"][0][1]) == "ещё +80% урона и +20% скорости", "level 4 comes later: %s" % [a["later"]])
	_check(a["base"] == PackedStringArray(["1 ракета с точки"]), "text without a level stays as base: %s" % [a["base"]])
	var b := CardText.level_split(ru, 3, 4)
	_check(b["now"] == PackedStringArray(["+30% урона, −10% перезарядки", "ещё +80% урона и +20% скорости"]), "at level 4 both apply now: %s" % [b["now"]])
	_check(b["later"].is_empty(), "nothing later at level 4")
	var en := CardText.level_split("1 missile per pylon; Lv. 2–5: +30% damage, −10% cooldown; Lv. 4: another +80% damage", 2, 3)
	_check(en["now"] == PackedStringArray(["+30% damage, −10% cooldown"]) and int(en["later"][0][0]) == 4, "English «Lv.» prefix: %s / %s" % [en["now"], en["later"]])
	var zh := CardText.level_split("每个挂点1枚导弹；Lv.2–5：伤害+30%，冷却−10%；Lv.4：伤害再+80%，速度+20%", 1, 2)
	_check(zh["now"] == PackedStringArray(["伤害+30%，冷却−10%"]) and int(zh["later"][0][0]) == 4, "Chinese separators: %s / %s" % [zh["now"], zh["later"]])
	var c := CardText.level_split("ур. 2–5: +25% урона", 0, 1)
	_check(c["now"].is_empty() and int(c["later"][0][0]) == 2, "a range that has not started yet is later, from its first level")
	var d := CardText.level_split("залп — 4 ракеты с точки, ур. 3–4 — 5, ур. 5 — 6; ур. 2–5: +25% урона", 2, 3)
	_check(d["base"].size() == 1 and d["now"].size() == 1, "a base part that only mentions levels stays base: %s" % [d["base"]])
	var e := CardText.level_split(ru, 3, 5)
	_check(e["now"].size() == 2 and e["later"].is_empty(), "a two-level jump gets the level it passes too: %s" % [e["now"]])
	var f := CardText.level_split(ru, 4, 5)
	_check(f["now"] == PackedStringArray(["+30% урона, −10% перезарядки"]), "a single level already taken is not repeated: %s" % [f["now"]])


func _test_numbers() -> void:
	TranslationServer.set_locale("ru")   # the decimal comma is Russian only (CardText.dec)
	_check(CardText.num(33.6) == "34", "big numbers are whole: %s" % CardText.num(33.6))
	_check(CardText.num(7.5) == "7,5" and CardText.num(7.0) == "7", "small numbers keep one decimal with a comma: %s %s" % [CardText.num(7.5), CardText.num(7.0)])
	_check(CardText.sec(2.88) == "2,9 с" and CardText.sec(3.0) == "3 с", "seconds: %s / %s" % [CardText.sec(2.88), CardText.sec(3.0)])
	_check(CardText.factor(1.3) == "×1,3" and CardText.factor(1.12) == "×1,12" and CardText.factor(2.0) == "×2", "factors: %s %s %s" % [CardText.factor(1.3), CardText.factor(1.12), CardText.factor(2.0)])
	_check(CardText.step("Урон", "30", "34") == "Урон: 30 → 34", "a step line")
	_check(CardText.step("Перезарядка", "3 с", "3 с", " (предел)") == "Перезарядка: 3 с (предел)", "an equal step says so instead of «3 → 3»")
